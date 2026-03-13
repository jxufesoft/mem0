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
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
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
# Security Schemes for OpenAPI
# ============================================================================

# HTTP Bearer security scheme for Swagger UI
security = HTTPBearer(
    scheme_name="X-API-Key",
    description="API Key 认证。在请求头中添加 X-API-Key。\n\n- **普通 API**: 使用通过 /admin/keys 创建的 API Key\n- **管理端点 (/admin/*)**: 使用 ADMIN_SECRET_KEY 环境变量",
)


# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(
    title="Mem0 Enhanced Server",
    description="""## Mem0 增强版 REST API

生产级记忆管理服务，支持多 Agent、认证和速率限制。

### 认证方式

所有端点（除 /health 外）需要 API Key 认证：

- **请求头**: `X-API-Key: your-api-key`
- **普通端点**: 使用 `/admin/keys` 创建的 API Key
- **管理端点 (/admin/\*)**: 使用 `ADMIN_SECRET_KEY` 环境变量

### 功能特性

- 🧠 多 Agent 隔离存储
- 🔐 API Key 认证
- ⚡ Redis 速率限制
- 🔍 向量语义搜索
""",
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


async def get_api_key(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """
    依赖注入：验证 API Key 并返回。

    用于 Swagger UI 的 "Authorize" 按钮和 OpenAPI 文档。
    """
    api_key = credentials.credentials

    # 对于管理端点，检查 ADMIN_SECRET_KEY
    # 注意：由于这里无法获取 request，我们在中间件中处理 admin 认证

    # 验证普通 API Key
    key_data = verify_api_key(api_key)
    if not key_data:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API key",
        )

    # 检查速率限制
    within_limit = await redis_manager.check_rate_limit(api_key, RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW)
    if not within_limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded",
        )

    return api_key


async def get_admin_key(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """
    依赖注入：验证管理 API Key。

    仅用于 /admin/* 端点。
    """
    api_key = credentials.credentials

    if api_key != ADMIN_SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key",
        )

    return api_key


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Middleware for API key authentication and rate limiting."""
    # Skip auth for health endpoint and docs
    if request.url.path in ["/", "/docs", "/openapi.json", "/health", "/redoc"]:
        return await call_next(request)

    # Skip for OPTIONS requests (CORS preflight)
    if request.method == "OPTIONS":
        return await call_next(request)

    api_key = request.headers.get("X-API-Key") or request.headers.get("Authorization", "").replace("Bearer ", "")
    if not api_key:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": "Missing X-API-Key header or Authorization Bearer token"},
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
# Admin Endpoints (需要管理员 API Key)
# ============================================================================

@app.post("/admin/keys", summary="创建 API Key", dependencies=[Depends(get_admin_key)])
async def create_api_key(req: CreateKeyRequest):
    """
    创建新的 API Key。

    **需要管理员权限**: 使用 ADMIN_SECRET_KEY 环境变量值作为 X-API-Key。

    返回新创建的 API Key，可用于后续 API 调用。
    """
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


@app.get("/admin/keys", summary="列出所有 API Keys", dependencies=[Depends(get_admin_key)])
async def list_api_keys():
    """
    列出所有 API Keys（显示完整密钥）。

    **需要管理员权限**: 使用 ADMIN_SECRET_KEY 环境变量值作为 X-API-Key。
    """
    keys = load_api_keys()
    result = []
    for key, data in keys.items():
        result.append({
            "api_key": key,
            "agent_id": data["agent_id"],
            "description": data["description"],
            "created_at": data["created_at"],
            "revoked": data["revoked"],
        })
    return {"keys": result}


@app.delete("/admin/keys", summary="撤销 API Key", dependencies=[Depends(get_admin_key)])
async def revoke_api_key(req: RevokeKeyRequest):
    """
    撤销指定的 API Key。

    **需要管理员权限**: 使用 ADMIN_SECRET_KEY 环境变量值作为 X-API-Key。
    """
    keys = load_api_keys()
    if req.api_key not in keys:
        raise HTTPException(status_code=404, detail="API key not found")

    keys[req.api_key]["revoked"] = True
    save_api_keys(keys)
    logger.info(f"Revoked API key: {req.api_key[:16]}...")

    return {"message": "API key revoked successfully"}


# ============================================================================
# Memory Endpoints (需要 API Key 认证)
# ============================================================================

# ============================================================================
# Deduplication Helper Functions
# ============================================================================

import hashlib

def compute_memory_hash(data: str) -> str:
    """Compute MD5 hash for memory content."""
    return hashlib.md5(data.encode()).hexdigest()


async def find_duplicates_by_hash(memory_instance, agent_id: str, user_id: Optional[str] = None) -> Dict[str, List[str]]:
    """
    Find duplicate memories by hash.

    Returns a dict mapping hash -> list of memory IDs with that hash.
    Only includes hashes with more than one memory (actual duplicates).
    """
    try:
        # Get all memories for this agent/user
        params = {"agent_id": agent_id}
        if user_id:
            params["user_id"] = user_id

        all_memories = memory_instance.get_all(**params)
        results = all_memories.get("results", [])

        # Group by hash
        hash_to_ids = {}
        for mem in results:
            mem_hash = mem.get("hash")
            if mem_hash:
                if mem_hash not in hash_to_ids:
                    hash_to_ids[mem_hash] = []
                hash_to_ids[mem_hash].append({
                    "id": mem["id"],
                    "memory": mem.get("memory", ""),
                    "created_at": mem.get("created_at", "")
                })

        # Filter to only duplicates
        duplicates = {h: ids for h, ids in hash_to_ids.items() if len(ids) > 1}
        return duplicates
    except Exception as e:
        logger.error(f"Error finding duplicates: {e}")
        return {}


async def check_memory_exists_by_hash(memory_instance, content_hash: str, agent_id: str, user_id: Optional[str] = None) -> Optional[Dict]:
    """
    Check if a memory with the given hash already exists.

    Returns the existing memory if found, None otherwise.
    """
    try:
        params = {"agent_id": agent_id}
        if user_id:
            params["user_id"] = user_id

        all_memories = memory_instance.get_all(**params)
        results = all_memories.get("results", [])

        for mem in results:
            if mem.get("hash") == content_hash:
                return mem
        return None
    except Exception as e:
        logger.error(f"Error checking memory by hash: {e}")
        return None


@app.post("/configure", summary="配置 Mem0", dependencies=[Depends(get_api_key)])
async def set_config(config: Dict[str, Any]):
    """
    设置记忆配置（不推荐在生产环境使用）。

    生产环境应通过环境变量管理配置。
    """
    logger.warning("Dynamic configuration not recommended in production")
    return {"message": "Configuration should be managed via environment variables"}


@app.post("/memories", summary="创建记忆", dependencies=[Depends(get_api_key)])
async def add_memory(memory_create: MemoryCreate, request: Request):
    """
    存储新的记忆。

    从消息中提取事实并存储到向量数据库。
    自动进行 hash 去重，避免存储完全相同的记忆。

    **必需参数**: 至少提供 user_id、agent_id 或 run_id 之一。
    """
    if not any([memory_create.user_id, memory_create.agent_id, memory_create.run_id]):
        raise HTTPException(status_code=400, detail="At least one identifier (user_id, agent_id, run_id) is required.")

    # Get agent instance for this agent_id
    agent_id = memory_create.agent_id or "default"
    user_id = memory_create.user_id
    memory_instance = await get_agent_instance(agent_id)

    params = {k: v for k, v in memory_create.model_dump().items() if v is not None and k != "messages"}
    try:
        response = memory_instance.add(messages=[m.model_dump() for m in memory_create.messages], **params)

        # Post-process: Auto deduplication for newly added memories
        results = response.get("results", [])
        dedup_stats = {"checked": 0, "duplicates_removed": 0}

        for i, result in enumerate(results):
            if result.get("event") == "ADD":
                dedup_stats["checked"] += 1
                new_memory_id = result.get("id")
                new_memory_content = result.get("memory", "")
                new_hash = compute_memory_hash(new_memory_content)

                # Check if a memory with the same hash already existed before this add
                existing = await check_memory_exists_by_hash(
                    memory_instance, new_hash, agent_id, user_id
                )

                if existing and existing.get("id") != new_memory_id:
                    # Found a duplicate - delete the newly created one
                    try:
                        memory_instance.delete(memory_id=new_memory_id)
                        dedup_stats["duplicates_removed"] += 1
                        logger.info(f"Auto-dedup: Removed duplicate memory {new_memory_id} ('{new_memory_content[:30]}...'), keeping {existing['id']}")

                        # Update the result to indicate dedup
                        results[i] = {
                            "id": existing["id"],
                            "memory": new_memory_content,
                            "event": "NOOP",
                            "reason": "duplicate_detected",
                            "existing_memory_id": existing["id"]
                        }
                    except Exception as e:
                        logger.error(f"Failed to delete duplicate memory {new_memory_id}: {e}")

        if dedup_stats["duplicates_removed"] > 0:
            logger.info(f"Auto-dedup summary: checked {dedup_stats['checked']}, removed {dedup_stats['duplicates_removed']} duplicates")

        return JSONResponse(content=response)
    except Exception as e:
        logger.exception(f"Error in add_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories", summary="获取记忆列表", dependencies=[Depends(get_api_key)])
async def get_all_memories(
    user_id: Optional[str] = None,
    run_id: Optional[str] = None,
    agent_id: Optional[str] = None,
):
    """
    检索存储的记忆。

    **必需参数**: 至少提供 user_id、agent_id 或 run_id 之一。
    """
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


@app.get("/memories/{memory_id}", summary="获取单个记忆", dependencies=[Depends(get_api_key)])
async def get_memory(memory_id: str, agent_id: Optional[str] = "default"):
    """
    通过 ID 检索特定记忆。
    """
    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.get(memory_id)
    except Exception as e:
        logger.exception(f"Error in get_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/search", summary="搜索记忆", dependencies=[Depends(get_api_key)])
async def search_memories(search_req: SearchRequest):
    """
    基于查询语句搜索记忆。

    使用向量语义搜索返回相关记忆。
    """
    agent_id = search_req.agent_id or "default"
    memory_instance = await get_agent_instance(agent_id)

    try:
        params = {k: v for k, v in search_req.model_dump().items() if v is not None and k != "query"}
        return memory_instance.search(query=search_req.query, **params)
    except Exception as e:
        logger.exception(f"Error in search_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))

    try:
        params = {k: v for k, v in search_req.model_dump().items() if v is not None and k != "query"}
        return memory_instance.search(query=search_req.query, **params)
    except Exception as e:
        logger.exception(f"Error in search_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/memories/{memory_id}", summary="更新记忆", dependencies=[Depends(get_api_key)])
async def update_memory(memory_id: str, updated_memory: Dict[str, Any], agent_id: Optional[str] = "default"):
    """
    更新现有记忆的内容。

    支持两种请求格式：
    - `{"data": "新内容"}`
    - `{"memory": "新内容"}`
    """
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


@app.get("/memories/{memory_id}/history", summary="获取记忆历史", dependencies=[Depends(get_api_key)])
async def memory_history(memory_id: str, agent_id: Optional[str] = "default"):
    """
    获取特定记忆的变更历史。
    """
    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.history(memory_id=memory_id)
    except Exception as e:
        logger.exception(f"Error in memory_history for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories/{memory_id}", summary="删除记忆", dependencies=[Depends(get_api_key)])
async def delete_memory(memory_id: str, agent_id: Optional[str] = "default"):
    """
    通过 ID 删除特定记忆。
    """
    memory_instance = await get_agent_instance(agent_id)
    try:
        memory_instance.delete(memory_id=memory_id)
        return {"message": "Memory deleted successfully"}
    except Exception as e:
        logger.exception(f"Error in delete_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories", summary="批量删除记忆", dependencies=[Depends(get_api_key)])
async def delete_all_memories(
    user_id: Optional[str] = None,
    run_id: Optional[str] = None,
    agent_id: Optional[str] = None,
):
    """
    根据标识符批量删除记忆。

    **必需参数**: 至少提供 user_id、agent_id 或 run_id 之一。
    """
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


@app.post("/reset", summary="重置所有记忆", dependencies=[Depends(get_api_key)])
async def reset_memory(agent_id: Optional[str] = "default"):
    """
    完全重置指定 Agent 的所有记忆。

    ⚠️ **警告**: 此操作不可逆！
    """
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


# ============================================================================
# Deduplication Endpoints
# ============================================================================

@app.get("/deduplicate", summary="查找重复记忆", dependencies=[Depends(get_api_key)])
async def find_duplicates(
    agent_id: Optional[str] = "default",
    user_id: Optional[str] = None,
):
    """
    查找指定 Agent/User 的重复记忆。

    返回所有具有相同 hash 的记忆组（每组 2 个或更多）。
    """
    memory_instance = await get_agent_instance(agent_id)
    try:
        duplicates = await find_duplicates_by_hash(memory_instance, agent_id, user_id)

        total_duplicates = sum(len(ids) - 1 for ids in duplicates.values())
        return {
            "total_duplicate_count": total_duplicates,
            "duplicate_groups": len(duplicates),
            "duplicates": duplicates
        }
    except Exception as e:
        logger.exception(f"Error finding duplicates for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/deduplicate", summary="清理重复记忆", dependencies=[Depends(get_api_key)])
async def cleanup_duplicates(
    agent_id: Optional[str] = "default",
    user_id: Optional[str] = None,
    dry_run: bool = True,
):
    """
    清理重复记忆，只保留每组中最早创建的那条。

    Args:
        agent_id: Agent ID
        user_id: User ID (optional)
        dry_run: 如果为 True（默认），只返回将被删除的记忆，不实际删除

    Returns:
        删除的记忆数量和详情
    """
    memory_instance = await get_agent_instance(agent_id)
    try:
        duplicates = await find_duplicates_by_hash(memory_instance, agent_id, user_id)

        deleted_count = 0
        deleted_memories = []

        for content_hash, mem_list in duplicates.items():
            # Sort by created_at, keep the oldest one
            sorted_mems = sorted(mem_list, key=lambda x: x.get("created_at", ""))
            # Delete all but the first (oldest)
            for mem in sorted_mems[1:]:
                if not dry_run:
                    try:
                        memory_instance.delete(memory_id=mem["id"])
                        deleted_count += 1
                        deleted_memories.append({
                            "id": mem["id"],
                            "memory": mem["memory"],
                            "hash": content_hash
                        })
                        logger.info(f"Deleted duplicate memory {mem['id']}: {mem['memory']}")
                    except Exception as e:
                        logger.error(f"Failed to delete memory {mem['id']}: {e}")
                else:
                    deleted_count += 1
                    deleted_memories.append({
                        "id": mem["id"],
                        "memory": mem["memory"],
                        "hash": content_hash,
                        "would_delete": True
                    })

        return {
            "dry_run": dry_run,
            "deleted_count": deleted_count if not dry_run else 0,
            "would_delete_count": deleted_count,
            "deleted_memories": deleted_memories,
            "message": "Dry run completed - no memories deleted" if dry_run else f"Deleted {deleted_count} duplicate memories"
        }
    except Exception as e:
        logger.exception(f"Error cleaning duplicates for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/", summary="Redirect to the OpenAPI documentation", include_in_schema=False)
async def home():
    """Redirect to the OpenAPI documentation."""
    return RedirectResponse(url="/docs")


# ============================================================================
# Memory Management Endpoints
# ============================================================================

@app.get("/memory/stats", summary="获取记忆统计", dependencies=[Depends(get_api_key)])
async def get_memory_stats():
    """
    获取 L0/L1/L2 三层记忆的统计信息。
    """
    import os
    from datetime import datetime
    
    memory_dir = os.path.expanduser("~/.openclaw/workspace/memory")
    l0_file = os.path.expanduser("~/.openclaw/workspace/memory.md")
    
    stats = {
        "timestamp": datetime.now().isoformat(),
        "l0": {},
        "l1": {},
        "l2": {}
    }
    
    # L0 stats
    if os.path.exists(l0_file):
        stats["l0"] = {
            "size_bytes": os.path.getsize(l0_file),
            "size_kb": round(os.path.getsize(l0_file) / 1024, 2),
            "exists": True
        }
    else:
        stats["l0"] = {"exists": False}
    
    # L1 stats
    if os.path.exists(memory_dir):
        files = [f for f in os.listdir(memory_dir) if f.endswith('.md')]
        total_size = sum(
            os.path.getsize(os.path.join(memory_dir, f))
            for f in files if os.path.isfile(os.path.join(memory_dir, f))
        )
        stats["l1"] = {
            "total_files": len(files),
            "total_size_bytes": total_size,
            "total_size_kb": round(total_size / 1024, 2)
        }
    else:
        stats["l1"] = {"exists": False}
    
    # L2 stats (from current agent)
    try:
        params = {"agent_id": "openclaw-main"}
        all_memories = memory_instance.get_all(**params) if 'memory_instance' in dir() else {"results": []}
        stats["l2"] = {
            "total_memories": len(all_memories.get("results", [])),
            "status": "connected"
        }
    except Exception as e:
        stats["l2"] = {"status": "error", "message": str(e)}
    
    return stats


@app.post("/memory/optimize", summary="优化记忆", dependencies=[Depends(get_api_key)])
async def optimize_memory(
    dry_run: bool = True,
    archive_days: int = 14,
    l0_max_lines: int = 100
):
    """
    执行记忆优化：
    - 归档旧文件
    - 精简 L0
    - L2 去重
    """
    import os
    import shutil
    from datetime import datetime, timedelta
    
    results = {
        "dry_run": dry_run,
        "timestamp": datetime.now().isoformat(),
        "operations": []
    }
    
    memory_dir = os.path.expanduser("~/.openclaw/workspace/memory")
    l0_file = os.path.expanduser("~/.openclaw/workspace/memory.md")
    archive_dir = os.path.join(memory_dir, "archive", datetime.now().strftime('%Y-%m'))
    
    # 1. Archive old files
    if os.path.exists(memory_dir):
        archived_count = 0
        cutoff_date = datetime.now() - timedelta(days=archive_days)
        test_patterns = ['test', 'Test', 'TEST', 'report', 'Report', 'summary', 'Summary', 'final', 'Final', 'plugin', 'Plugin']
        
        for filename in os.listdir(memory_dir):
            filepath = os.path.join(memory_dir, filename)
            if not os.path.isfile(filepath):
                continue
            
            # Check if it's a test file or old date file
            is_test = any(p in filename for p in test_patterns)
            is_old_date = filename.startswith('20') and datetime.fromtimestamp(os.path.getmtime(filepath)) < cutoff_date
            
            if is_test or is_old_date:
                if not dry_run:
                    os.makedirs(archive_dir, exist_ok=True)
                    shutil.move(filepath, os.path.join(archive_dir, filename))
                archived_count += 1
        
        if archived_count > 0:
            results["operations"].append({
                "operation": "archive_l1",
                "files_archived": archived_count,
                "dry_run": dry_run
            })
    
    # 2. Prune L0
    if os.path.exists(l0_file):
        with open(l0_file, 'r') as f:
            lines = f.readlines()
        
        if len(lines) > l0_max_lines:
            if not dry_run:
                # Keep header and recent entries
                header = lines[:20]
                recent = lines[-(l0_max_lines - 25):]
                new_content = header + ["\n## Auto-pruned entries\n\n"] + recent
                with open(l0_file, 'w') as f:
                    f.writelines(new_content)
            
            results["operations"].append({
                "operation": "prune_l0",
                "original_lines": len(lines),
                "new_lines": l0_max_lines,
                "reduced_by": len(lines) - l0_max_lines,
                "dry_run": dry_run
            })
    
    # 3. L2 dedup (already handled by /deduplicate endpoint)
    results["operations"].append({
        "operation": "dedup_l2",
        "message": "Use POST /deduplicate endpoint for L2 deduplication"
    })
    
    return results
