# Mem0 Server 架构设计文档

## 版本信息

- **文档版本**: 1.0.0
- **最后更新**: 2026-03-07
- **Server 版本**: 2.0.0

---

## 目录

1. [架构概述](#架构概述)
2. [技术选型](#技术选型)
3. [模块设计](#模块设计)
4. [数据模型](#数据模型)
5. [API 设计](#api-设计)
6. [安全架构](#安全架构)
7. [并发模型](#并发模型)

---

## 架构概述

### 1.1 设计目标

| 目标 | 描述 | 优先级 |
|------|------|--------|
| **高性能** | 低延迟、高吞吐量 | P0 |
| **高可用** | 容错、优雅降级 | P0 |
| **可扩展** | 水平/垂直扩展 | P1 |
| **安全性** | 认证、隔离、速率限制 | P0 |
| **易部署** | Docker、环境变量 | P1 |

### 1.2 整体架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                      客户端请求                                │
│                    (Plugin/SDK/CLI)                            │
└────────────────────────┬────────────────────────────────────────────┘
                     │
                     │ HTTP/HTTPS
                     │ X-API-Key header
                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   FastAPI 应用                                  │
│  ────────────────────────────────────────────────────            │
│                                                            │
│  ┌────────────────────────────────────────────────────┐          │
│  │         中间件层 (Middleware Layer)              │          │
│  │  ───────────────────────────────────────        │          │
│  │  · CORS Middleware                             │          │
│  │  · Auth Middleware (API Key + Rate Limit)       │          │
│  │  · Error Handling                             │          │
│  └────────────────────────────────────────────────────┘          │
│                           │                                    │
│  ┌────────────────────────────────────────────────────┐          │
│  │         路由层 (Routing Layer)                 │          │
│  │  ───────────────────────────────────────        │          │
│  │  · /health                                     │          │
│  │  · /admin/*                                    │          │
│  │  · /memories                                   │          │
│  │  · /search                                     │          │
│  └────────────────────────────────────────────────────┘          │
│                           │                                    │
│  ┌────────────────────────────────────────────────────┐          │
│  │       服务层 (Service Layer)                      │          │
│  │  ───────────────────────────────────────        │          │
│  │  ┌──────────────┐  ┌──────────────┐        │          │
│  │  │ API Key     │  │ Multi-Agent  │        │          │
│  │  │ Management  │  │ Instance    │        │          │
│  │  └──────────────┘  │ Pool         │        │          │
│  │                   └──────────────┘        │          │
│  │  ┌──────────────┐  ┌──────────────┐        │          │
│  │  │ Rate Limit  │  │ Config      │        │          │
│  │  │ (Redis)     │  │ Builder     │        │          │
│  │  └──────────────┘  └──────────────┘        │          │
│  └────────────────────────────────────────────────────┘          │
│                           │                                    │
│  ┌────────────────────────────────────────────────────┐          │
│  │       内存层 (Memory Layer)                       │          │
│  │  ───────────────────────────────────────        │          │
│  │  ┌──────────────┐  ┌──────────────┐        │          │
│  │  │ Instance     │  │ Instance     │        │          │
│  │  │ Pool        │  │ Locks       │        │          │
│  │  │ (_instances)│  │ (_locks)    │        │          │
│  │  └──────────────┘  └──────────────┘        │          │
│  └────────────────────────────────────────────────────┘          │
│                           │                                    │
│  ┌────────────────────────────────────────────────────┐          │
│  │    Mem0 Core Library (memory package)            │          │
│  │  ───────────────────────────────────────        │          │
│  │  · Memory 类                                   │          │
│  │  · Fact Extraction (LLM)                      │          │
│  │  · Embedding (向量嵌入)                        │          │
│  │  · Vector Search (向量搜索)                     │          │
│  │  · History Tracking (历史跟踪)                 │          │
│  └────────────────────────────────────────────────────┘          │
│                           │                                    │
└───────────────────────────┼────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                   │
        ▼                                   ▼
┌───────────────┐                   ┌───────────────┐
│ PostgreSQL    │                   │    Redis     │
│ + pgvector   │                   │ (Rate Limit  │
│              │                   │  & Cache)    │
│ · Vector DB  │                   └───────────────┘
│ · HNSW Index │
│ · Collections │
└───────────────┘
```

---

## 技术选型

### 2.1 核心框架

| 技术 | 版本 | 选型理由 |
|------|------|----------|
| **FastAPI** | Latest | 异步支持、自动文档、类型安全 |
| **Pydantic** | Latest | 数据验证、序列化 |
| **Uvicorn** | Latest | ASGI 服务器、高性能 |

### 2.2 数据库

| 技术 | 版本 | 用途 | 选型理由 |
|------|------|------|----------|
| **PostgreSQL** | 16+ | 主数据库 | 成熟、可靠、扩展性强 |
| **pgvector** | Latest | 向量存储 | 原生向量支持、HNSW 索引 |
| **Redis** | 7+ | 缓存/速率限制 | 高性能、原子操作 |
| **Neo4j** | 5.26 | 图存储（可选）| 实体关系 |

### 2.3 AI/ML

| 技术 | 用途 | 选型理由 |
|------|------|----------|
| **OpenAI API** | LLM 事实提取 | 可靠、高质量 |
| **text-embedding-3-small** | 向量嵌入 | 平衡性能/成本 |
| **bge-m3** | 备选嵌入模型 | 多语言支持 |

### 2.4 运维工具

| 技术 | 用途 |
|------|------|
| **Docker** | 容器化 |
| **Docker Compose** | 编排 |
| **Health Checks** | 健康监控 |
| **Logging** | 日志记录 |

---

## 模块设计

### 3.1 模块划分

```
server/
├── main.py                    # 主应用入口
├── Dockerfile                  # Docker 镜像
├── docker-compose.prod.yaml     # 生产编排
├── .env.example               # 环境变量模板
└── postgres-init/              # 初始化脚本
    ├── init.sql
    └── setup-hnsw.sql
```

### 3.2 RedisManager 模块

**职责**：Redis 连接管理和速率限制

```python
class RedisManager:
    """Manage Redis connection with graceful degradation."""

    def __init__(self, url: str):
        self.url = url
        self.client: Optional[redis.Redis] = None
        self.enabled = False

    async def connect(self):
        """Connect to Redis if available."""

    async def close(self):
        """Close Redis connection."""

    async def check_rate_limit(self, key: str, limit: int, window: int) -> bool:
        """Check rate limit using sliding window."""
```

**特性**：
- 优雅降级（Redis 不可用时继续服务）
- 滑动窗口算法
- 原子操作保证正确性

### 3.3 API Key Management 模块

**职责**：API Key 的创建、存储、验证

```python
def load_api_keys() -> Dict[str, Dict[str, Any]]:
    """Load API keys from file."""

def save_api_keys(keys: Dict[str, Dict[str, Any]]):
    """Save API keys to file."""

def generate_api_key() -> str:
    """Generate a secure random API key."""

def verify_api_key(api_key: str) -> Optional[Dict[str, Any]]:
    """Verify an API key and return its metadata."""
```

**存储格式**：
```json
{
  "mem0_xxx...": {
    "agent_id": "my-agent",
    "description": "Production key",
    "created_at": 1709845432.123,
    "revoked": false
  }
}
```

### 3.4 Multi-Agent Instance Pool 模块

**职责**：按 agent_id 隔离的 Memory 实例池

```python
_instances: Dict[str, Memory] = {}
_instance_locks: Dict[str, asyncio.Lock] = {}
_global_lock = asyncio.Lock()

async def get_agent_instance(agent_id: str) -> Memory:
    """
    Get or create a Memory instance for an agent.
    Uses double-checked locking pattern for thread safety.
    """

def build_agent_config(agent_id: str) -> Dict[str, Any]:
    """
    Build configuration for a specific agent.
    Uses per-agent collection name for isolation.
    """
```

**隔离机制**：
- 每个 agent_id 独立的 Memory 实例
- Per-agent collection 命名：`memories_{agent_id}`
- 双重检查锁定保证线程安全

### 3.5 Auth Middleware 模块

**职责**：API Key 认证和速率限制

```python
async def verify_key(api_key: str, request: Request) -> bool:
    """Verify API key and check rate limit."""

@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Middleware for API key authentication and rate limiting."""
```

**认证流程**：
1. 检查 X-API-Key header
2. 管理端点验证 ADMIN_SECRET_KEY
3. 普通 API 端点验证 API Key
4. 检查速率限制
5. 通过/拒绝请求

---

## 数据模型

### 4.1 Pydantic Models

#### Message
```python
class Message(BaseModel):
    role: str = Field(..., description="Role of message (user or assistant).")
    content: str = Field(..., description="Message content.")
```

#### MemoryCreate
```python
class MemoryCreate(BaseModel):
    messages: List[Message] = Field(..., description="List of messages to store.")
    user_id: Optional[str] = None
    agent_id: Optional[str] = None
    run_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
```

#### SearchRequest
```python
class SearchRequest(BaseModel):
    query: str = Field(..., description="Search query.")
    user_id: Optional[str] = None
    run_id: Optional[str] = None
    agent_id: Optional[str] = None
    filters: Optional[Dict[str, Any]] = None
    limit: Optional[int] = Field(10, description="Number of results to return.")
```

#### CreateKeyRequest
```python
class CreateKeyRequest(BaseModel):
    agent_id: str = Field(..., description="Agent ID for this API key.")
    description: Optional[str] = Field("", description="Description for API key.")
```

#### HealthResponse
```python
class HealthResponse(BaseModel):
    status: str
    loaded_agents: int
    redis: str
```

### 4.2 Memory Item Schema

```typescript
interface MemoryItem {
  id: string;
  memory: string;
  user_id?: string;
  agent_id?: string;
  run_id?: string;
  score?: number;
  categories?: string[];
  metadata?: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
}
```

---

## API 设计

### 5.1 端点分类

```
API 端点
├── 健康检查
│   └── GET /health
├── 管理端点 (需要 ADMIN_SECRET_KEY)
│   ├── POST /admin/keys
│   ├── GET /admin/keys
│   └── DELETE /admin/keys
├── 配置端点
│   └── POST /configure
└── 记忆端点 (需要 API Key)
    ├── POST /memories
    ├── GET /memories
    ├── GET /memories/{id}
    ├── POST /search
    ├── PUT /memories/{id}
    ├── GET /memories/{id}/history
    ├── DELETE /memories/{id}
    ├── DELETE /memories
    └── POST /reset
```

### 5.2 响应格式标准

#### 成功响应
```json
{
  "results": [
    {
      "id": "uuid",
      "memory": "content",
      "score": 0.95,
      "metadata": {}
    }
  ],
  "relations": []
}
```

#### 错误响应
```json
{
  "detail": "Error message"
}
```

### 5.3 HTTP 状态码

| 状态码 | 含义 |
|--------|------|
| **200** | 成功 |
| **400** | 请求参数错误 |
| **401** | 缺少认证 |
| **403** | 认证失败或速率超限 |
| **404** | 资源不存在 |
| **500** | 服务器错误 |

---

## 安全架构

### 6.1 认证流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                      请求到达                                │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────────┐
              │ 检查 X-API-Key      │
              └──────────┬───────────┘
                         │
            ┌────────────┴────────────┐
            │                         │
            ▼                         ▼
    ┌───────────┐            ┌───────────┐
    │  无 Header │            │  有 Header│
    └─────┬─────┘            └─────┬─────┘
          │                        │
          ▼                        ▼
    ┌───────────┐         ┌─────────────────┐
    │ HTTP 401  │         │ 检查路径类型    │
    └───────────┘         └──────┬──────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ /admin/*       │         │ /*            │
            └───────┬───────┘         └───────┬───────┘
                    │                         │
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ 验证          │         │ 验证          │
            │ ADMIN_SECRET  │         │ API Keys      │
            └───────┬───────┘         └───────┬───────┘
                    │                         │
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ 检查 revoked  │         │ 检查 revoked  │
            └───────┬───────┘         └───────┬───────┘
                    │                         │
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ 速率限制检查   │         │ 速率限制检查   │
            └───────┬───────┘         └───────┬───────┘
                    │                         │
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ 允许/拒绝     │         │ 允许/拒绝     │
            └───────────────┘         └───────────────┘
```

### 6.2 速率限制设计

**算法**：滑动窗口（Sliding Window）

```python
# Redis ZSET 实现
key = f"ratelimit:{api_key}"
now = time.time()
window = 60  # 秒
limit = 200

# 移除过期的请求
pipe.zremrangebyscore(key, 0, now - window)

# 计数当前窗口内的请求
count = pipe.zcard(key)

# 如果未超限，添加当前请求
if count < limit:
    pipe.zadd(key, {str(uuid.uuid4()): now})

# 设置过期时间
pipe.expire(key, window)
```

### 6.3 多代理隔离

**隔离层级**：

| 层级 | 隔离方式 | 实现 |
|------|-----------|------|
| **集合级别** | 不同 agent_id 使用不同集合 | `memories_{agent_id}` |
| **实例级别** | 每个 agent_id 独立 Memory 实例 | `_instances[agent_id]` |
| **API Key 绑定** | Key 关联特定 agent_id | `api_keys[key]["agent_id"]` |

**查询限制**：
- 使用 agent_id 的 API Key 只能访问该 agent 的记忆
- 跨 agent 查询被阻止
- 删除操作仅限当前 agent

---

## 并发模型

### 7.1 异步架构

```
┌─────────────────────────────────────────────────────────────────┐
│                   Uvicorn ASGI Server                      │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐      │
│  │              事件循环 (Event Loop)                │      │
│  │  ────────────────────────────────────────         │      │
│  │                                                   │      │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │      │
│  │  │Task 1│  │Task 2│  │Task 3│  │Task 4│ │      │
│  │  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘ │      │
│  │     │         │         │         │         │      │
│  │     └─────────┴─────────┴─────────┘         │      │
│  │                   │                            │      │
│  │                   ▼                            │      │
│  │  ┌─────────────────────────────────┐         │      │
│  │  │      I/O 操作 (await)          │         │      │
│  │  │  ───────────────────────       │         │      │
│  │  │  · 数据库查询                 │         │      │
│  │  │  · LLM API 调用              │         │      │
│  │  │  · Redis 操作                │         │      │
│  │  └─────────────────────────────────┘         │      │
│  └─────────────────────────────────────────────────────┘      │
│                                                           │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 锁机制

**全局锁**：
```python
_global_lock = asyncio.Lock()
```
- 用于保护 `_instances` 和 `_instance_locks` 字典
- 双重检查锁定模式

**Per-Agent 锁**：
```python
_instance_locks: Dict[str, asyncio.Lock] = {}
```
- 每个 agent_id 独立的锁
- 用于同步 Memory 实例的创建

**双重检查锁定**：
```python
# 第一次检查（无锁）
if agent_id not in _instances:
    async with _global_lock:
        # 第二次检查（有锁）
        if agent_id not in _instances:
            # 创建实例
            _instances[agent_id] = Memory.from_config(config)
```

---

## 附录

### A. 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `POSTGRES_HOST` | postgres | PostgreSQL 主机 |
| `POSTGRES_PORT` | 5432 | PostgreSQL 端口 |
| `POSTGRES_DB` | postgres | 数据库名称 |
| `POSTGRES_USER` | postgres | 用户名 |
| `POSTGRES_PASSWORD` | postgres | 密码 |
| `POSTGRES_COLLECTION_NAME` | memories | 默认集合名 |
| `OPENAI_API_KEY` | - | LLM API Key |
| `OPENAI_BASE_URL` | - | LLM 基础 URL |
| `OPENAI_MODEL` | gpt-4.1-nano-2025-04-14 | LLM 模型 |
| `OPENAI_EMBEDDING_MODEL` | text-embedding-3-small | 嵌入模型 |
| `EMBEDDING_DIMENSIONS` | 1536 | 向量维度 |
| `REDIS_URL` | redis://localhost:6379/0 | Redis URL |
| `ADMIN_SECRET_KEY` | admin_secret_key_CHANGE_ME | 管理员密钥 |
| `RATE_LIMIT_REQUESTS` | 200 | 速率限制请求数 |
| `RATE_LIMIT_WINDOW` | 60 | 速率限制窗口（秒）|

---

**文档结束**
