"""
Mem0 Enhanced Server

Production-grade REST API server with:
- Asyncio for concurrent operations
- Multi-agent instance pooling
- API Key authentication
- Redis sliding window rate limiting
- Per-agent collection isolation
"""

import asyncio
import json
import logging
import os
import secrets
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional

import redis.asyncio as redis
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel, Field

from mem0 import Memory

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()


# ============================================================================
# Configuration
# ============================================================================

POSTGRES_HOST = os.environ.get("POSTGRES_HOST", "postgres")
POSTGRES_PORT = os.environ.get("POSTGRES_PORT", "5432")
POSTGRES_DB = os.environ.get("POSTGRES_DB", "postgres")
POSTGRES_USER = os.environ.get("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.environ.get("POSTGRES_PASSWORD", "postgres")
POSTGRES_COLLECTION_NAME = os.environ.get("POSTGRES_COLLECTION_NAME", "memories")

NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USERNAME = os.environ.get("NEO4J_USERNAME", "neo4j")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "mem0graph")

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
OPENAI_BASE_URL = os.environ.get("OPENAI_BASE_URL")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4.1-nano-2025-04-14")
OPENAI_EMBEDDING_MODEL = os.environ.get("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")

# Embedding dimensions for different models
# Configure based on the embedding model being used
EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", "1536"))  # Default for text-embedding-3-small
# For bge-m3: 1024 dimensions
# For text-embedding-3-small: 1536 dimensions
# For text-embedding-3-large: 3072 dimensions

HISTORY_DB_PATH = os.environ.get("HISTORY_DB_PATH", "/app/history/history.db")

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

ADMIN_SECRET_KEY = os.environ.get("ADMIN_SECRET_KEY", "admin_secret_key_CHANGE_ME")

RATE_LIMIT_REQUESTS = int(os.environ.get("RATE_LIMIT_REQUESTS", "200"))
RATE_LIMIT_WINDOW = int(os.environ.get("RATE_LIMIT_WINDOW", "60"))  # seconds


# ============================================================================
# Redis Client
# ============================================================================

class RedisManager:
    """Manage Redis connection with graceful degradation."""

    def __init__(self, url: str):
        self.url = url
        self.client: Optional[redis.Redis] = None
        self.enabled = False

    async def connect(self):
        """Connect to Redis if available."""
        try:
            self.client = redis.from_url(self.url, decode_responses=True)
            await self.client.ping()
            self.enabled = True
            logger.info("Redis connected successfully")
        except Exception as e:
            logger.warning(f"Redis connection failed, running without Redis: {e}")
            self.enabled = False

    async def close(self):
        """Close Redis connection."""
        if self.client:
            await self.client.close()

    async def check_rate_limit(self, key: str, limit: int, window: int) -> bool:
        """
        Check rate limit using sliding window.

        Args:
            key: Unique identifier for the rate limit (e.g., API key)
            limit: Maximum requests allowed
            window: Time window in seconds

        Returns:
            True if within limit, False otherwise
        """
        if not self.enabled:
            return True

        try:
            now = time.time()
            pipe = self.client.pipeline()
            pipe.zremrangebyscore(key, 0, now - window)
            pipe.zcard(key)
            pipe.zadd(key, {str(uuid.uuid4()): now})
            pipe.expire(key, window)
            results = await pipe.execute()
            count = results[1]
            return count <= limit
        except Exception as e:
            logger.warning(f"Rate limit check failed, allowing request: {e}")
            return True


# Global Redis manager
redis_manager = RedisManager(REDIS_URL)


# ============================================================================
# API Key Management
# ============================================================================

API_KEY_DB_PATH = "/app/history/api_keys.json"


def load_api_keys() -> Dict[str, Dict[str, Any]]:
    """Load API keys from file."""
    try:
        if os.path.exists(API_KEY_DB_PATH):
            with open(API_KEY_DB_PATH, "r") as f:
                return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load API keys: {e}")
    return {}


def save_api_keys(keys: Dict[str, Dict[str, Any]]):
    """Save API keys to file."""
    try:
        os.makedirs(os.path.dirname(API_KEY_DB_PATH), exist_ok=True)
        with open(API_KEY_DB_PATH, "w") as f:
            json.dump(keys, f, indent=2)
    except Exception as e:
        logger.error(f"Failed to save API keys: {e}")
        raise HTTPException(status_code=500, detail="Failed to save API key")


def generate_api_key() -> str:
    """Generate a secure random API key."""
    return f"mem0_{secrets.token_urlsafe(32)}"


def verify_api_key(api_key: str) -> Optional[Dict[str, Any]]:
    """Verify an API key and return its metadata."""
    keys = load_api_keys()
    key_data = keys.get(api_key)
    if key_data and not key_data.get("revoked", False):
        return key_data
    return None


# ============================================================================
# Multi-Agent Memory Instance Pool
# ============================================================================

_instances: Dict[str, Memory] = {}
_instance_locks: Dict[str, asyncio.Lock] = {}
_global_lock = asyncio.Lock()


def build_agent_config(agent_id: str) -> Dict[str, Any]:
    """
    Build configuration for a specific agent.

    Uses per-agent collection name for isolation.
    """
    config = {
        "version": "v1.1",
        "vector_store": {
            "provider": "pgvector",
            "config": {
                "host": POSTGRES_HOST,
                "port": int(POSTGRES_PORT),
                "dbname": POSTGRES_DB,
                "user": POSTGRES_USER,
                "password": POSTGRES_PASSWORD,
                "collection_name": f"{POSTGRES_COLLECTION_NAME}_{agent_id.replace('-', '_')}",
                "embedding_model_dims": EMBEDDING_DIMENSIONS,
            },
        },
        "llm": {
            "provider": "openai",
            "config": {
                "api_key": OPENAI_API_KEY,
                "temperature": 0.2,
                "model": OPENAI_MODEL,
            },
        },
        "embedder": {
            "provider": "openai",
            "config": {
                "api_key": OPENAI_API_KEY,
                "model": OPENAI_EMBEDDING_MODEL,
                "embedding_dims": EMBEDDING_DIMENSIONS,
            },
        },
        "history_db_path": HISTORY_DB_PATH,
    }

    # Add base_url to llm config if provided
    if OPENAI_BASE_URL:
        config["llm"]["config"]["openai_base_url"] = OPENAI_BASE_URL

    # Add base_url to embedder config if provided
    if OPENAI_BASE_URL:
        config["embedder"]["config"]["openai_base_url"] = OPENAI_BASE_URL

    # Optional: Add graph store if all required settings are available
    # Note: Graph memory currently requires user_id for some operations
    # Temporarily disabled to support agent_id-only queries
    # if NEO4J_URI and NEO4J_USERNAME and NEO4J_PASSWORD:
    #     config["graph_store"] = {
    #         "provider": "neo4j",
    #         "config": {
    #             "url": NEO4J_URI,
    #             "username": NEO4J_USERNAME,
    #             "password": NEO4J_PASSWORD,
    #         },
    #     }

    return config


async def get_agent_instance(agent_id: str) -> Memory:
    """
    Get or create a Memory instance for an agent.

    Uses double-checked locking pattern for thread safety.
    """
    # First check without lock
    if agent_id in _instances:
        return _instances[agent_id]

    async with _global_lock:
        # Second check with lock
        if agent_id in _instances:
            return _instances[agent_id]

        # Get per-agent lock or create it
        if agent_id not in _instance_locks:
            _instance_locks[agent_id] = asyncio.Lock()

        async with _instance_locks[agent_id]:
            # Third check with per-agent lock
            if agent_id in _instances:
                return _instances[agent_id]

            # Create new instance
            config = build_agent_config(agent_id)
            logger.info(f"Creating new Memory instance for agent: {agent_id}")
            instance = Memory.from_config(config)
            _instances[agent_id] = instance
            return instance


# ============================================================================
# Lifecycle
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    # Startup
    logger.info("Starting Mem0 Enhanced Server...")
    await redis_manager.connect()

    # Create history directory
    os.makedirs(os.path.dirname(HISTORY_DB_PATH), exist_ok=True)

    yield

    # Shutdown
    logger.info("Shutting down Mem0 Enhanced Server...")
    await redis_manager.close()


# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(
    title="Mem0 Enhanced Server",
    description="Production-grade REST API for managing and searching memories with multi-agent support, authentication, and rate limiting.",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Pydantic Models
# ============================================================================

class Message(BaseModel):
    role: str = Field(..., description="Role of the message (user or assistant).")
    content: str = Field(..., description="Message content.")


class MemoryCreate(BaseModel):
    messages: List[Message] = Field(..., description="List of messages to store.")
    user_id: Optional[str] = None
    agent_id: Optional[str] = None
    run_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class SearchRequest(BaseModel):
    query: str = Field(..., description="Search query.")
    user_id: Optional[str] = None
    run_id: Optional[str] = None
    agent_id: Optional[str] = None
    filters: Optional[Dict[str, Any]] = None
    limit: Optional[int] = Field(10, description="Number of results to return.")


class CreateKeyRequest(BaseModel):
    agent_id: str = Field(..., description="Agent ID for this API key.")
    description: Optional[str] = Field("", description="Description for the API key.")


class RevokeKeyRequest(BaseModel):
    api_key: str = Field(..., description="API key to revoke.")


# ============================================================================
# Middleware: API Key & Rate Limiting
# ============================================================================

async def verify_key(api_key: str, request: Request) -> bool:
    """Verify API key and check rate limit."""
    # Check admin secret for admin endpoints
    if request.url.path.startswith("/admin"):
        return api_key == ADMIN_SECRET_KEY

    # Verify regular API key
    key_data = verify_api_key(api_key)
    if not key_data:
        return False

    # Check rate limit
    within_limit = await redis_manager.check_rate_limit(api_key, RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW)
    if not within_limit:
        logger.warning(f"Rate limit exceeded for API key: {api_key[:10]}...")
        return False

    return True


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Middleware for API key authentication and rate limiting."""
    # Skip auth for health endpoint and docs
    if request.url.path in ["/", "/docs", "/openapi.json", "/health"]:
        return await call_next(request)

    api_key = request.headers.get("X-API-Key")
    if not api_key:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": "Missing X-API-Key header"},
        )

    if not await verify_key(api_key, request):
        return JSONResponse(
            status_code=status.HTTP_403_FORBIDDEN,
            content={"detail": "Invalid API key or rate limit exceeded"},
        )

    return await call_next(request)


# ============================================================================
# Health Check
# ============================================================================

class HealthResponse(BaseModel):
    status: str
    loaded_agents: int
    redis: str


@app.get("/health", response_model=HealthResponse, summary="Health check")
async def health_check():
    """Check server health status."""
    redis_status = "ok" if redis_manager.enabled else "disabled"
    return HealthResponse(
        status="healthy",
        loaded_agents=len(_instances),
        redis=redis_status,
    )


# ============================================================================
# Admin Endpoints
# ============================================================================

@app.post("/admin/keys", summary="Create API key")
async def create_api_key(req: CreateKeyRequest):
    """Create a new API key for an agent."""
    keys = load_api_keys()
    api_key = generate_api_key()

    keys[api_key] = {
        "agent_id": req.agent_id,
        "description": req.description,
        "created_at": time.time(),
        "revoked": False,
    }

    save_api_keys(keys)
    logger.info(f"Created API key for agent: {req.agent_id}")

    return {
        "api_key": api_key,
        "agent_id": req.agent_id,
        "description": req.description,
    }


@app.get("/admin/keys", summary="List API keys")
async def list_api_keys():
    """List all API keys (without full key value)."""
    keys = load_api_keys()
    result = []
    for key, data in keys.items():
        result.append({
            "key_prefix": key[:16] + "...",
            "agent_id": data["agent_id"],
            "description": data["description"],
            "created_at": data["created_at"],
            "revoked": data["revoked"],
        })
    return {"keys": result}


@app.delete("/admin/keys", summary="Revoke API key")
async def revoke_api_key(req: RevokeKeyRequest):
    """Revoke an API key."""
    keys = load_api_keys()
    if req.api_key not in keys:
        raise HTTPException(status_code=404, detail="API key not found")

    keys[req.api_key]["revoked"] = True
    save_api_keys(keys)
    logger.info(f"Revoked API key: {req.api_key[:16]}...")

    return {"message": "API key revoked successfully"}


# ============================================================================
# Memory Endpoints
# ============================================================================

@app.post("/configure", summary="Configure Mem0")
async def set_config(config: Dict[str, Any]):
    """Set memory configuration (not recommended in production)."""
    # In production, configuration should be managed via environment variables
    # This endpoint is kept for backward compatibility
    logger.warning("Dynamic configuration not recommended in production")
    return {"message": "Configuration should be managed via environment variables"}


@app.post("/memories", summary="Create memories")
async def add_memory(memory_create: MemoryCreate, request: Request):
    """Store new memories."""
    if not any([memory_create.user_id, memory_create.agent_id, memory_create.run_id]):
        raise HTTPException(status_code=400, detail="At least one identifier (user_id, agent_id, run_id) is required.")

    # Get agent instance for this agent_id
    agent_id = memory_create.agent_id or "default"
    memory_instance = await get_agent_instance(agent_id)

    params = {k: v for k, v in memory_create.model_dump().items() if v is not None and k != "messages"}
    try:
        response = memory_instance.add(messages=[m.model_dump() for m in memory_create.messages], **params)
        return JSONResponse(content=response)
    except Exception as e:
        logger.exception(f"Error in add_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories", summary="Get memories")
async def get_all_memories(
    user_id: Optional[str] = None,
    run_id: Optional[str] = None,
    agent_id: Optional[str] = None,
):
    """Retrieve stored memories."""
    if not any([user_id, run_id, agent_id]):
        raise HTTPException(status_code=400, detail="At least one identifier is required.")

    agent_id = agent_id or "default"
    memory_instance = await get_agent_instance(agent_id)

    try:
        params = {
            k: v for k, v in {"user_id": user_id, "run_id": run_id, "agent_id": agent_id}.items() if v is not None
        }
        return memory_instance.get_all(**params)
    except Exception as e:
        logger.exception(f"Error in get_all_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories/{memory_id}", summary="Get a memory")
async def get_memory(memory_id: str, agent_id: Optional[str] = "default"):
    """Retrieve a specific memory by ID."""
    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.get(memory_id)
    except Exception as e:
        logger.exception(f"Error in get_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/search", summary="Search memories")
async def search_memories(search_req: SearchRequest):
    """Search for memories based on a query."""
    agent_id = search_req.agent_id or "default"
    memory_instance = await get_agent_instance(agent_id)

    try:
        params = {k: v for k, v in search_req.model_dump().items() if v is not None and k != "query"}
        return memory_instance.search(query=search_req.query, **params)
    except Exception as e:
        logger.exception(f"Error in search_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/memories/{memory_id}", summary="Update a memory")
async def update_memory(memory_id: str, updated_memory: Dict[str, Any], agent_id: Optional[str] = "default"):
    """Update an existing memory with new content."""
    memory_instance = await get_agent_instance(agent_id)
    try:
        # Extract data from request - support both string and dict format
        if isinstance(updated_memory, dict):
            # Support {"data": "..."} or {"memory": "..."} format
            data = updated_memory.get("data") or updated_memory.get("memory", updated_memory)
            if isinstance(data, dict):
                # If still a dict, try to stringify or extract meaningful content
                data = data.get("memory") or data.get("content") or str(data)
        else:
            data = str(updated_memory)
        return memory_instance.update(memory_id=memory_id, data=data)
    except Exception as e:
        logger.exception(f"Error in update_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories/{memory_id}/history", summary="Get memory history")
async def memory_history(memory_id: str, agent_id: Optional[str] = "default"):
    """Retrieve memory history."""
    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.history(memory_id=memory_id)
    except Exception as e:
        logger.exception(f"Error in memory_history for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories/{memory_id}", summary="Delete a memory")
async def delete_memory(memory_id: str, agent_id: Optional[str] = "default"):
    """Delete a specific memory by ID."""
    memory_instance = await get_agent_instance(agent_id)
    try:
        memory_instance.delete(memory_id=memory_id)
        return {"message": "Memory deleted successfully"}
    except Exception as e:
        logger.exception(f"Error in delete_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories", summary="Delete all memories")
async def delete_all_memories(
    user_id: Optional[str] = None,
    run_id: Optional[str] = None,
    agent_id: Optional[str] = None,
):
    """Delete all memories for a given identifier."""
    if not any([user_id, run_id, agent_id]):
        raise HTTPException(status_code=400, detail="At least one identifier is required.")

    agent_id = agent_id or "default"
    memory_instance = await get_agent_instance(agent_id)

    try:
        params = {
            k: v for k, v in {"user_id": user_id, "run_id": run_id, "agent_id": agent_id}.items() if v is not None
        }
        memory_instance.delete_all(**params)
        return {"message": "All relevant memories deleted"}
    except Exception as e:
        logger.exception(f"Error in delete_all_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/reset", summary="Reset all memories")
async def reset_memory(agent_id: Optional[str] = "default"):
    """Completely reset stored memories for an agent."""
    memory_instance = await get_agent_instance(agent_id)
    try:
        memory_instance.reset()
        # Also remove from cache
        if agent_id in _instances:
            del _instances[agent_id]
        if agent_id in _instance_locks:
            del _instance_locks[agent_id]
        return {"message": "All memories reset"}
    except Exception as e:
        logger.exception(f"Error in reset_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/", summary="Redirect to the OpenAPI documentation", include_in_schema=False)
async def home():
    """Redirect to the OpenAPI documentation."""
    return RedirectResponse(url="/docs")
