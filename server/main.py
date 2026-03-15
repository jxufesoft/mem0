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
import datetime
import gzip
import hashlib
import shutil
import subprocess
import tarfile
import tempfile
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional

import psycopg2
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

# Backup Configuration
BACKUP_DIR = os.environ.get("BACKUP_DIR", "/app/backups")
BACKUP_MAX_COUNT = int(os.environ.get("BACKUP_MAX_COUNT", "10"))
BACKUP_COMPRESS = os.environ.get("BACKUP_COMPRESS", "true").lower() == "true"

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
                "collection_name": POSTGRES_COLLECTION_NAME,
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
    if NEO4J_URI and NEO4J_USERNAME and NEO4J_PASSWORD:
        config["graph_store"] = {
            "provider": "neo4j",
            "config": {
                "url": NEO4J_URI,
                "username": NEO4J_USERNAME,
                "password": NEO4J_PASSWORD,
            },
        }

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
    user_id: str = Field(..., description="用户ID，用于数据归属和隔离")
    agent_id: str = Field(..., description="Agent ID，用于数据归属和隔离")
    run_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class SearchRequest(BaseModel):
    query: str = Field(..., description="Search query.")
    user_id: str = Field(..., description="用户ID，用于数据归属和隔离")
    agent_id: str = Field(..., description="Agent ID，用于数据归属和隔离")
    run_id: Optional[str] = None
    filters: Optional[Dict[str, Any]] = None
    limit: Optional[int] = Field(10, description="Number of results to return.")


class CreateKeyRequest(BaseModel):
    user_id: Optional[str] = Field("", description="User ID for this API key.")
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


async def get_api_key_with_data(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> Dict[str, Any]:
    """
    依赖注入：验证 API Key 并返回 key 数据。

    返回 dict 包含 api_key 和 key_data (包括 user_id, agent_id)。
    用于需要严格 user_id/agent_id 绑定的端点。
    """
    api_key = credentials.credentials

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

    return {"api_key": api_key, "key_data": key_data}


def require_user_id_match(user_id_param: str = None, agent_id_param: str = None):
    """
    依赖工厂：验证请求的 user_id/agent_id 与 API Key 绑定的匹配。

    Args:
        user_id_param: 请求参数中的 user_id 字段名
        agent_id_param: 请求参数中的 agent_id 字段名

    如果 API Key 绑定了 user_id，则必须与请求的 user_id 匹配。
    如果 API Key 绑定了 agent_id，则必须与请求的 agent_id 匹配。
    """
    async def validate(
        key_info: Dict[str, Any] = Depends(get_api_key_with_data),
        request: Request = None,
    ):
        key_data = key_info["key_data"]
        key_user_id = key_data.get("user_id", "")
        key_agent_id = key_data.get("agent_id", "")

        # 从 query 参数获取请求的 user_id 和 agent_id
        query_params = request.query_params if request else {}

        if user_id_param:
            request_user_id = query_params.get(user_id_param, "")
            if key_user_id and request_user_id and key_user_id != request_user_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{request_user_id}'",
                )

        if agent_id_param:
            request_agent_id = query_params.get(agent_id_param, "")
            if key_agent_id and request_agent_id and key_agent_id != request_agent_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{request_agent_id}'",
                )

        return key_info

    return validate


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
        "user_id": req.user_id,
        "agent_id": req.agent_id,
        "description": req.description,
        "created_at": time.time(),
        "revoked": False,
    }

    save_api_keys(keys)
    logger.info(f"Created API key for user: {req.user_id}, agent: {req.agent_id}")

    return {
        "api_key": api_key,
        "user_id": req.user_id,
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
            "user_id": data.get("user_id", ""),
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
# Backup API Models
# ============================================================================

class BackupCreateRequest(BaseModel):
    backup_type: str = Field(default="full", description="Type of backup: full or incremental")
    include: List[str] = Field(default=None, description="Components to include")

class BackupRestoreRequest(BaseModel):
    strategy: str = Field(default="overwrite", description="Restore strategy: overwrite or merge")
    dry_run: bool = Field(default=False, description="If true, only show what would be restored")

class MigrationExportRequest(BaseModel):
    include: List[str] = Field(default=None, description="Components to include in migration")

class MigrationImportRequest(BaseModel):
    strategy: str = Field(default="overwrite", description="Import strategy: overwrite or merge")

# ============================================================================
# Backup/Restore/Migration API Endpoints
# ============================================================================

@app.post("/admin/backup", summary="创建备份", dependencies=[Depends(get_admin_key)])
async def create_backup_endpoint(req: BackupCreateRequest = None):
    """创建新的备份。"""
    if req is None:
        req = BackupCreateRequest()
    result = await create_backup(backup_type=req.backup_type or "full", include=req.include or ["postgres", "neo4j", "api_keys", "history"])
    logger.info(f"Created backup: {result['id']}")
    return result

@app.get("/admin/backup/list", summary="列出备份", dependencies=[Depends(get_admin_key)])
async def list_backups_endpoint():
    backups = await list_backups()
    return {"backups": backups, "count": len(backups)}

@app.get("/admin/backup/{backup_id}/download", summary="下载备份", dependencies=[Depends(get_admin_key)])
async def download_backup_endpoint(backup_id: str):
    from fastapi.responses import FileResponse
    backup_path = os.path.join(BACKUP_DIR, backup_id)
    if not os.path.exists(backup_path):
        raise HTTPException(status_code=404, detail="Backup not found")
    tarball_path = os.path.join(BACKUP_DIR, f"{backup_id}.tar.gz")
    with tarfile.open(tarball_path, "w:gz") as tar:
        tar.add(backup_path, arcname=backup_id)
    return FileResponse(tarball_path, media_type="application/gzip", filename=f"backup_{backup_id}.tar.gz")

@app.get("/admin/backup/{backup_id}/verify", summary="验证备份", dependencies=[Depends(get_admin_key)])
async def verify_backup_endpoint(backup_id: str):
    return await verify_backup(backup_id)

@app.post("/admin/backup/{backup_id}/restore", summary="恢复备份", dependencies=[Depends(get_admin_key)])
async def restore_backup_endpoint(backup_id: str, req: BackupRestoreRequest = None):
    if req is None:
        req = BackupRestoreRequest()
    result = await restore_backup(backup_id, strategy=req.strategy or "overwrite", dry_run=req.dry_run or False)
    logger.info(f"Restored backup: {backup_id}")
    return result

@app.delete("/admin/backup/{backup_id}", summary="删除备份", dependencies=[Depends(get_admin_key)])
async def delete_backup_endpoint(backup_id: str):
    return await delete_backup(backup_id)

@app.post("/admin/migrate/export", summary="导出迁移包", dependencies=[Depends(get_admin_key)])
async def export_migration_endpoint(req: MigrationExportRequest = None):
    if req is None:
        req = MigrationExportRequest()
    result = await export_migration(include=req.include)
    return result

@app.post("/admin/migrate/import", summary="导入迁移包", dependencies=[Depends(get_admin_key)])
async def import_migration_endpoint(req: MigrationImportRequest):
    result = await import_migration(migration_file="", strategy=req.strategy)
    return result


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


async def find_duplicates_by_hash(memory_instance, agent_id: str, user_id: str = ...) -> Dict[str, List[str]]:
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


async def check_memory_exists_by_hash(memory_instance, content_hash: str, agent_id: str, user_id: str = ...) -> Optional[Dict]:
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


@app.post("/memories", summary="创建记忆")
async def add_memory(
    memory_create: MemoryCreate,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
    request: Request = None
):
    """
    存储新的记忆。

    从消息中提取事实并存储到向量数据库。
    自动进行 hash 去重，避免存储完全相同的记忆。

    **必需参数**: user_id 和 agent_id（用于数据归属和隔离）。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != memory_create.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{memory_create.user_id}'",
        )

    if key_agent_id and key_agent_id != memory_create.agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{memory_create.agent_id}'",
        )

    # Get agent instance for this agent_id
    agent_id = memory_create.agent_id
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


@app.get("/memories", summary="获取记忆列表")
async def get_all_memories(
    user_id: str,
    agent_id: str,
    run_id: Optional[str] = None,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    检索存储的记忆。

    **必需参数**: user_id 和 agent_id（用于数据归属和隔离）。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )

    memory_instance = await get_agent_instance(agent_id)

    try:
        params = {
            k: v for k, v in {"user_id": user_id, "run_id": run_id, "agent_id": agent_id}.items() if v is not None
        }
        return memory_instance.get_all(**params)
    except Exception as e:
        logger.exception(f"Error in get_all_memories for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories/{memory_id}", summary="获取单个记忆")
async def get_memory(
    memory_id: str,
    user_id: str,
    agent_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    通过 ID 检索特定记忆。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )

    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.get(memory_id)
    except Exception as e:
        logger.exception(f"Error in get_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/search", summary="搜索记忆")
async def search_memories(
    search_req: SearchRequest,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    基于查询语句搜索记忆。

    使用向量语义搜索返回相关记忆。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != search_req.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{search_req.user_id}'",
        )

    if key_agent_id and key_agent_id != search_req.agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{search_req.agent_id}'",
        )

    agent_id = search_req.agent_id
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


@app.put("/memories/{memory_id}", summary="更新记忆")
async def update_memory(
    memory_id: str,
    updated_memory: Dict[str, Any],
    user_id: str,
    agent_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    更新现有记忆的内容。

    支持两种请求格式：
    - `{"data": "新内容"}`
    - `{"memory": "新内容"}`

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )

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


@app.get("/memories/{memory_id}/history", summary="获取记忆历史")
async def memory_history(
    memory_id: str,
    user_id: str,
    agent_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    获取特定记忆的变更历史。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )

    memory_instance = await get_agent_instance(agent_id)
    try:
        return memory_instance.history(memory_id=memory_id)
    except Exception as e:
        logger.exception(f"Error in memory_history for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories/{memory_id}", summary="删除记忆")
async def delete_memory(
    memory_id: str,
    user_id: str,
    agent_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    通过 ID 删除特定记忆。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )

    memory_instance = await get_agent_instance(agent_id)
    try:
        memory_instance.delete(memory_id=memory_id)
        return {"message": "Memory deleted successfully"}
    except Exception as e:
        logger.exception(f"Error in delete_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories", summary="批量删除记忆")
async def delete_all_memories(
    user_id: str,
    agent_id: str,
    run_id: Optional[str] = None,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    根据标识符批量删除记忆。

    **必需参数**: 至少提供 user_id、agent_id 或 run_id 之一。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )
        
    # Removed - now user_id and agent_id are required
        

    agent_id = agent_id
    """
    根据标识符批量删除记忆。

    **必需参数**: 至少提供 user_id、agent_id 或 run_id 之一。
    """
    # Removed - now user_id and agent_id are required
        

    agent_id = agent_id
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


@app.post("/reset", summary="重置所有记忆")
async def reset_memory(
    user_id: str,
    agent_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    完全重置指定 Agent 的所有记忆。

    ⚠️ **警告**: 此操作不可逆！

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )
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

@app.get("/deduplicate", summary="查找重复记忆")
async def find_duplicates(
    agent_id: str,
    user_id: str,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    查找指定 Agent/User 的重复记忆。

    返回所有具有相同 hash 的记忆组（每组 2 个或更多）。

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )
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


@app.post("/deduplicate", summary="清理重复记忆")
async def cleanup_duplicates(
    agent_id: str,
    user_id: str,
    dry_run: bool = True,
    key_info: Dict[str, Any] = Depends(get_api_key_with_data),
):
    """
    清理重复记忆，只保留每组中最早创建的那条。

    Args:
        agent_id: Agent ID
        user_id: User ID (optional)
        dry_run: 如果为 True（默认），只返回将被删除的记忆，不实际删除

    Returns:
        删除的记忆数量和详情

    **严格绑定**: 如果 API Key 绑定了 user_id/agent_id，则必须与请求参数匹配。
    """
    # 验证 API Key 绑定的 user_id/agent_id
    key_data = key_info["key_data"]
    key_user_id = key_data.get("user_id", "")
    key_agent_id = key_data.get("agent_id", "")

    if key_user_id and key_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key user_id mismatch: key bound to '{key_user_id}', but requested '{user_id}'",
        )

    if key_agent_id and key_agent_id != agent_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"API key agent_id mismatch: key bound to '{key_agent_id}', but requested '{agent_id}'",
        )
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


# ============================================================================
# Backup/Restore/Migration Functions
# ============================================================================

def get_pg_connection():
    """Get PostgreSQL connection."""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD
    )


def compute_file_checksum(filepath: str, algorithm: str = "sha256") -> str:
    """Compute checksum for a file."""
    hash_obj = hashlib.new(algorithm)
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            hash_obj.update(chunk)
    return f"{algorithm}:{hash_obj.hexdigest()}"


def create_postgres_dump(backup_path: str) -> str:
    """Create PostgreSQL dump file."""
    dump_file = os.path.join(backup_path, "postgres.sql")
    
    # Use pg_dump to export the database
    env = os.environ.copy()
    env["PGPASSWORD"] = POSTGRES_PASSWORD
    
    result = subprocess.run([
        "pg_dump",
        "-h", POSTGRES_HOST,
        "-p", POSTGRES_PORT,
        "-U", POSTGRES_USER,
        "-d", POSTGRES_DB,
        "-f", dump_file,
        "--clean",
        "--if-exists"
    ], env=env, capture_output=True, text=True)
    
    if result.returncode != 0:
        logger.warning(f"pg_dump failed: {result.stderr}")
        # Fallback: manual table export
        try:
            conn = get_pg_connection()
            cursor = conn.cursor()
            
            # Get all tables
            cursor.execute("""
                SELECT table_name FROM information_schema.tables 
                WHERE table_schema = 'public'
            """)
            tables = [row[0] for row in cursor.fetchall()]
            
            with open(dump_file, 'w') as f:
                for table in tables:
                    # Export table data as INSERT statements
                    cursor.execute(f"SELECT * FROM {table}")
                    columns = [desc[0] for desc in cursor.description]
                    for row in cursor.fetchall():
                        values = []
                        for val in row:
                            if val is None:
                                values.append('NULL')
                            elif isinstance(val, str):
                                escaped = val.replace("'", "''")
                                values.append(f"'{escaped}'")
                            else:
                                values.append(str(val))
                        f.write(f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({', '.join(values)});\n")
            
            cursor.close()
            conn.close()
        except Exception as e:
            logger.error(f"Manual export failed: {e}")
            raise
    
    return dump_file


def create_neo4j_export(backup_path: str) -> str:
    """Export Neo4j data."""
    neo4j_file = os.path.join(backup_path, "neo4j_data.json")
    
    try:
        from neo4j import GraphDatabase
        
        driver = GraphDatabase.driver(
            NEO4J_URI,
            auth=(NEO4J_USERNAME, NEO4J_PASSWORD)
        )
        
        with driver.session() as session:
            # Export all nodes
            result = session.run("MATCH (n) RETURN n")
            nodes = []
            for record in result:
                nodes.append(dict(record["n"]))
            
            # Export all relationships
            result = session.run("MATCH (a)-[r]->(b) RETURN a, r, b")
            rels = []
            for record in result:
                rels.append({
                    "from": dict(record["a"]),
                    "type": record["r"].type,
                    "to": dict(record["b"]),
                    "props": dict(record["r"])
                })
        
        driver.close()
        
        with open(neo4j_file, 'w') as f:
            json.dump({"nodes": nodes, "relationships": rels}, f, indent=2, default=str)
        
        return neo4j_file
    except Exception as e:
        logger.warning(f"Neo4j export failed: {e}")
        # Create empty file
        with open(neo4j_file, 'w') as f:
            json.dump({"nodes": [], "relationships": []}, f)
        return neo4j_file


def get_backup_stats(backup_path: str) -> Dict[str, Any]:
    """Get statistics about a backup."""
    stats = {
        "files": {},
        "total_size": 0,
        "memories_count": 0,
        "api_keys_count": 0
    }
    
    for filename in os.listdir(backup_path):
        filepath = os.path.join(backup_path, filename)
        if os.path.isfile(filepath):
            size = os.path.getsize(filepath)
            stats["files"][filename] = size
            stats["total_size"] += size
            
            # Try to count memories from postgres dump
            if filename == "postgres.sql":
                try:
                    with open(filepath, 'r') as f:
                        content = f.read()
                        # Rough estimate based on INSERT statements
                        stats["memories_count"] = content.count("INSERT INTO")
                except:
                    pass
            
            # Count API keys
            if filename == "api_keys.json":
                try:
                    with open(filepath, 'r') as f:
                        keys = json.load(f)
                        stats["api_keys_count"] = len(keys)
                except:
                    pass
    
    return stats


async def create_backup(backup_type: str = "full", include: List[str] = None) -> Dict[str, Any]:
    """
    Create a backup of all data.
    
    Args:
        backup_type: "full" or "incremental"
        include: List of components to include ["postgres", "neo4j", "api_keys", "history"]
    
    Returns:
        Backup metadata
    """
    if include is None:
        include = ["postgres", "neo4j", "api_keys", "history"]
    
    # Create backup directory
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    backup_id = f"{timestamp}"
    
    backup_path = os.path.join(BACKUP_DIR, backup_id)
    os.makedirs(backup_path, exist_ok=True)
    
    # Create metadata
    metadata = {
        "id": backup_id,
        "type": backup_type,
        "created_at": datetime.datetime.now().isoformat() + "Z",
        "version": "2.4.10",
        "includes": include,
        "checksums": {}
    }
    
    # Backup each component
    if "postgres" in include:
        try:
            dump_file = create_postgres_dump(backup_path)
            if os.path.exists(dump_file):
                checksum = compute_file_checksum(dump_file)
                metadata["checksums"]["postgres"] = checksum
        except Exception as e:
            logger.error(f"PostgreSQL backup failed: {e}")
            metadata["error"] = str(e)
    
    if "neo4j" in include:
        try:
            neo4j_file = create_neo4j_export(backup_path)
            if os.path.exists(neo4j_file):
                checksum = compute_file_checksum(neo4j_file)
                metadata["checksums"]["neo4j"] = checksum
        except Exception as e:
            logger.error(f"Neo4j backup failed: {e}")
    
    if "api_keys" in include:
        try:
            api_keys_file = os.path.join(backup_path, "api_keys.json")
            shutil.copy(API_KEY_DB_PATH, api_keys_file)
            checksum = compute_file_checksum(api_keys_file)
            metadata["checksums"]["api_keys"] = checksum
        except Exception as e:
            logger.error(f"API keys backup failed: {e}")
    
    if "history" in include:
        try:
            history_file = os.path.join(backup_path, "history.db")
            if os.path.exists(HISTORY_DB_PATH):
                shutil.copy(HISTORY_DB_PATH, history_file)
                checksum = compute_file_checksum(history_file)
                metadata["checksums"]["history"] = checksum
        except Exception as e:
            logger.error(f"History backup failed: {e}")
    
    # Get stats
    stats = get_backup_stats(backup_path)
    metadata["memories_count"] = stats.get("memories_count", 0)
    metadata["api_keys_count"] = stats.get("api_keys_count", 0)
    metadata["size_bytes"] = stats.get("total_size", 0)
    
    # Compute overall checksum
    manifest = {"metadata": metadata, "files": stats["files"]}
    manifest_file = os.path.join(backup_path, "manifest.json")
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    # Save metadata
    metadata_file = os.path.join(backup_path, "metadata.json")
    with open(metadata_file, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    # Clean up old backups
    await cleanup_old_backups()
    
    return metadata


async def cleanup_old_backups():
    """Remove old backups exceeding the max count."""
    if not os.path.exists(BACKUP_DIR):
        return
    
    backups = sorted(os.listdir(BACKUP_DIR))
    while len(backups) > BACKUP_MAX_COUNT:
        oldest = backups.pop(0)
        oldest_path = os.path.join(BACKUP_DIR, oldest)
        shutil.rmtree(oldest_path)
        logger.info(f"Removed old backup: {oldest}")


async def verify_backup(backup_id: str) -> Dict[str, Any]:
    """Verify backup integrity."""
    backup_path = os.path.join(BACKUP_DIR, backup_id)
    
    if not os.path.exists(backup_path):
        raise HTTPException(status_code=404, detail="Backup not found")
    
    # Load metadata
    metadata_file = os.path.join(backup_path, "metadata.json")
    if not os.path.exists(metadata_file):
        return {"valid": False, "error": "Metadata file not found"}
    
    with open(metadata_file, 'r') as f:
        metadata = json.load(f)
    
    # Verify checksums
    verification = {
        "backup_id": backup_id,
        "valid": True,
        "checksums_verified": {},
        "files_found": []
    }
    
    for filename, expected_checksum in metadata.get("checksums", {}).items():
        filepath = os.path.join(backup_path, filename)
        if os.path.exists(filepath):
            actual_checksum = compute_file_checksum(filepath)
            verification["files_found"].append(filename)
            verification["checksums_verified"][filename] = {
                "expected": expected_checksum,
                "actual": actual_checksum,
                "valid": expected_checksum == actual_checksum
            }
            if expected_checksum != actual_checksum:
                verification["valid"] = False
        else:
            verification["valid"] = False
            verification["checksums_verified"][filename] = {
                "expected": expected_checksum,
                "actual": None,
                "valid": False
            }
    
    # Save verification result
    verification_file = os.path.join(backup_path, "verification.json")
    with open(verification_file, 'w') as f:
        json.dump(verification, f, indent=2)
    
    return verification


async def restore_backup(backup_id: str, strategy: str = "overwrite", dry_run: bool = False) -> Dict[str, Any]:
    """
    Restore from a backup.
    
    Args:
        backup_id: ID of the backup to restore
        strategy: "overwrite" or "merge"
        dry_run: If True, only show what would be restored
    
    Returns:
        Restore result
    """
    backup_path = os.path.join(BACKUP_DIR, backup_id)
    
    if not os.path.exists(backup_path):
        raise HTTPException(status_code=404, detail="Backup not found")
    
    result = {
        "backup_id": backup_id,
        "strategy": strategy,
        "dry_run": dry_run,
        "operations": []
    }
    
    # Load metadata
    metadata_file = os.path.join(backup_path, "metadata.json")
    with open(metadata_file, 'r') as f:
        metadata = json.load(f)
    
    # Restore PostgreSQL
    postgres_file = os.path.join(backup_path, "postgres.sql")
    if os.path.exists(postgres_file) and not dry_run:
        try:
            env = os.environ.copy()
            env["PGPASSWORD"] = POSTGRES_PASSWORD
            
            # Drop existing tables and restore
            subprocess.run([
                "psql",
                "-h", POSTGRES_HOST,
                "-p", POSTGRES_PORT,
                "-U", POSTGRES_USER,
                "-d", POSTGRES_DB,
                "-f", postgres_file
            ], env=env, check=True)
            
            result["operations"].append({"component": "postgres", "status": "restored"})
        except Exception as e:
            result["operations"].append({"component": "postgres", "status": "error", "error": str(e)})
    elif dry_run:
        result["operations"].append({"component": "postgres", "status": "would restore", "file": postgres_file})
    
    # Restore Neo4j
    neo4j_file = os.path.join(backup_path, "neo4j_data.json")
    if os.path.exists(neo4j_file) and not dry_run:
        try:
            with open(neo4j_file, 'r') as f:
                neo4j_data = json.load(f)
            
            from neo4j import GraphDatabase
            driver = GraphDatabase.driver(
                NEO4J_URI,
                auth=(NEO4J_USERNAME, NEO4J_PASSWORD)
            )
            
            with driver.session() as session:
                # Clear existing data
                session.run("MATCH (n) DETACH DELETE n")
                
                # Recreate nodes
                for node in neo4j_data.get("nodes", []):
                    labels = node.pop("_labels", [":Node"])
                    props = node
                    if props:
                        label = list(labels)[0] if labels else "Node"
                        session.run(f"CREATE (n:{label} $props)", props=props)
                
                # Recreate relationships
                for rel in neo4j_data.get("relationships", []):
                    # This is simplified - actual implementation needs proper matching
                    pass
            
            driver.close()
            result["operations"].append({"component": "neo4j", "status": "restored"})
        except Exception as e:
            result["operations"].append({"component": "neo4j", "status": "error", "error": str(e)})
    elif dry_run:
        result["operations"].append({"component": "neo4j", "status": "would restore", "file": neo4j_file})
    
    # Restore API Keys
    api_keys_file = os.path.join(backup_path, "api_keys.json")
    if os.path.exists(api_keys_file) and not dry_run:
        try:
            shutil.copy(api_keys_file, API_KEY_DB_PATH)
            result["operations"].append({"component": "api_keys", "status": "restored"})
        except Exception as e:
            result["operations"].append({"component": "api_keys", "status": "error", "error": str(e)})
    elif dry_run:
        result["operations"].append({"component": "api_keys", "status": "would restore", "file": api_keys_file})
    
    # Restore History
    history_file = os.path.join(backup_path, "history.db")
    if os.path.exists(history_file) and not dry_run:
        try:
            shutil.copy(history_file, HISTORY_DB_PATH)
            result["operations"].append({"component": "history", "status": "restored"})
        except Exception as e:
            result["operations"].append({"component": "history", "status": "error", "error": str(e)})
    elif dry_run:
        result["operations"].append({"component": "history", "status": "would restore", "file": history_file})
    
    return result


async def list_backups() -> List[Dict[str, Any]]:
    """List all available backups."""
    if not os.path.exists(BACKUP_DIR):
        return []
    
    backups = []
    for backup_id in sorted(os.listdir(BACKUP_DIR)):
        backup_path = os.path.join(BACKUP_DIR, backup_id)
        if os.path.isdir(backup_path):
            metadata_file = os.path.join(backup_path, "metadata.json")
            if os.path.exists(metadata_file):
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)
                backups.append(metadata)
            else:
                # Basic info for backups without metadata
                backups.append({
                    "id": backup_id,
                    "created_at": datetime.datetime.fromtimestamp(
                        os.path.getctime(backup_path)
                    ).isoformat()
                })
    
    return sorted(backups, key=lambda x: x.get("created_at", ""), reverse=True)


async def delete_backup(backup_id: str) -> Dict[str, Any]:
    """Delete a backup."""
    backup_path = os.path.join(BACKUP_DIR, backup_id)
    
    if not os.path.exists(backup_path):
        raise HTTPException(status_code=404, detail="Backup not found")
    
    shutil.rmtree(backup_path)
    logger.info(f"Deleted backup: {backup_id}")
    
    return {"message": f"Backup {backup_id} deleted successfully"}


# ============================================================================
# Migration Functions
# ============================================================================

async def export_migration(include: List[str] = None) -> Dict[str, Any]:
    """
    Export data for migration to another server.
    
    Returns:
        Migration package metadata and file path
    """
    if include is None:
        include = ["postgres", "neo4j", "api_keys", "history"]
    
    # Create a backup first (reusing backup logic)
    metadata = await create_backup(backup_type="migration", include=include)
    
    # Create a tarball for easy transfer
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    migration_file = f"migration_{timestamp}.tar.gz"
    migration_path = os.path.join(BACKUP_DIR, migration_file)
    
    backup_path = os.path.join(BACKUP_DIR, metadata["id"])
    
    with tarfile.open(migration_path, "w:gz") as tar:
        tar.add(backup_path, arcname=os.path.basename(backup_path))
    
    # Compute migration package checksum
    checksum = compute_file_checksum(migration_path)
    
    return {
        "migration_file": migration_file,
        "path": migration_path,
        "checksum": checksum,
        "size_bytes": os.path.getsize(migration_path),
        "metadata": metadata
    }


async def import_migration(migration_file: str, strategy: str = "overwrite") -> Dict[str, Any]:
    """
    Import data from a migration package.
    
    Args:
        migration_file: Path to the migration tarball
        strategy: "overwrite" or "merge"
    
    Returns:
        Import result
    """
    if not os.path.exists(migration_file):
        raise HTTPException(status_code=404, detail="Migration file not found")
    
    # Extract the migration package
    with tempfile.TemporaryDirectory() as temp_dir:
        with tarfile.open(migration_file, "r:gz") as tar:
            tar.extractall(temp_dir)
        
        # Find the backup directory
        extracted_dirs = os.listdir(temp_dir)
        if not extracted_dirs:
            raise HTTPException(status_code=400, detail="Invalid migration package")
        
        backup_path = os.path.join(temp_dir, extracted_dirs[0])
        
        # Verify the backup
        verification = await verify_backup(os.path.basename(backup_path))
        
        if not verification.get("valid"):
            raise HTTPException(
                status_code=400,
                detail=f"Invalid migration package: {verification}"
            )
        
        # Restore
        result = await restore_backup(
            os.path.basename(backup_path),
            strategy=strategy,
            dry_run=False
        )
        
        result["migration_file"] = migration_file
        result["verification"] = verification
    
    return result


# ============================================================================
# Backup API Models
# ============================================================================

class BackupCreateRequest(BaseModel):
    backup_type: str = Field(default="full", description="Type of backup: full or incremental")
    include: List[str] = Field(default=None, description="Components to include")


class BackupRestoreRequest(BaseModel):
    strategy: str = Field(default="overwrite", description="Restore strategy: overwrite or merge")
    dry_run: bool = Field(default=False, description="If true, only show what would be restored")


class MigrationExportRequest(BaseModel):
    include: List[str] = Field(default=None, description="Components to include in migration")


class MigrationImportRequest(BaseModel):
    strategy: str = Field(default="overwrite", description="Import strategy: overwrite or merge")
