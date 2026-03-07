# Mem0 Server 详细设计文档

## 版本信息

- **文档版本**: 1.0.0
- **最后更新**: 2026-03-07
- **Server 版本**: 2.0.0

---

## 目录

1. [模块详解](#模块详解)
2. [核心算法](#核心算法)
3. [数据库设计](#数据库设计)
4. [错误处理](#错误处理)
5. [性能优化](#性能优化)
6. [监控与日志](#监控与日志)

---

## 模块详解

### 1.1 RedisManager

#### 1.1.1 类定义

```python
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
            key: Unique identifier for rate limit (e.g., API key)
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
            # 1. 移除过期的请求
            pipe.zremrangebyscore(key, 0, now - window)
            # 2. 计数当前窗口内的请求
            pipe.zcard(key)
            # 3. 添加当前请求
            pipe.zadd(key, {str(uuid.uuid4()): now})
            # 4. 设置过期时间
            pipe.expire(key, window)
            # 5. 执行所有命令
            results = await pipe.execute()
            count = results[1]
            return count <= limit
        except Exception as e:
            logger.warning(f"Rate limit check failed, allowing request: {e}")
            return True
```

#### 1.1.2 设计决策

| 决策 | 理由 |
|------|------|
| **优雅降级** | Redis 不可用时继续服务，避免单点故障 |
| **Pipeline** | 减少网络往返，提高性能 |
| **ZSET** | 高效的滑动窗口实现 |
| **UUID 标识符** | 避免时间戳冲突 |

### 1.2 API Key Management

#### 1.2.1 数据结构

```json
{
  "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6": {
    "agent_id": "my-agent",
    "description": "Production API key",
    "created_at": 1709845432.123,
    "revoked": false
  }
}
```

#### 1.2.2 函数实现

```python
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
```

#### 1.2.3 安全特性

| 特性 | 实现 |
|------|------|
| **安全随机** | `secrets.token_urlsafe(32)` |
| **Key 前缀** | `mem0_` 前缀便于识别 |
| **撤销机制** | `revoked` 标志位 |
| **时间戳** | `created_at` 追踪创建时间 |

### 1.3 Multi-Agent Instance Pool

#### 1.3.1 数据结构

```python
_instances: Dict[str, Memory] = {}
_instance_locks: Dict[str, asyncio.Lock] = {}
_global_lock = asyncio.Lock()
```

#### 1.3.2 配置构建

```python
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

    # Add base_url if provided
    if OPENAI_BASE_URL:
        config["llm"]["config"]["openai_base_url"] = OPENAI_BASE_URL
        config["embedder"]["config"]["openai_base_url"] = OPENAI_BASE_URL

    return config
```

#### 1.3.3 实例获取

```python
async def get_agent_instance(agent_id: str) -> Memory:
    """
    Get or create a Memory instance for an agent.

    Uses double-checked locking pattern for thread safety.
    """
    # 第一次检查（无锁）
    if agent_id in _instances:
        return _instances[agent_id]

    # 获取全局锁
    async with _global_lock:
        # 第二次检查（有锁）
        if agent_id in _instances:
            return _instances[agent_id]

        # 获取或创建 per-agent 锁
        if agent_id not in _instance_locks:
            _instance_locks[agent_id] = asyncio.Lock()

        # 使用 per-agent 锁
        async with _instance_locks[agent_id]:
            # 第三次检查（per-agent 锁）
            if agent_id in _instances:
                return _instances[agent_id]

            # 创建新实例
            config = build_agent_config(agent_id)
            logger.info(f"Creating new Memory instance for agent: {agent_id}")
            instance = Memory.from_config(config)
            _instances[agent_id] = instance
            return instance
```

#### 1.3.4 隔离策略

| 策略 | 实现 |
|------|------|
| **集合隔离** | `collection_name = f"memories_{agent_id}"` |
| **实例隔离** | 每个 agent_id 独立 Memory 对象 |
| **锁隔离** | Per-agent asyncio.Lock |
| **命名规范** | `-` 替换为 `_` 避免冲突 |

### 1.4 认证中间件

#### 1.4.1 认证流程

```python
async def verify_key(api_key: str, request: Request) -> bool:
    """Verify API key and check rate limit."""
    # 检查管理端点
    if request.url.path.startswith("/admin"):
        return api_key == ADMIN_SECRET_KEY

    # 验证普通 API Key
    key_data = verify_api_key(api_key)
    if not key_data:
        return False

    # 检查速率限制
    within_limit = await redis_manager.check_rate_limit(
        api_key, RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW
    )
    if not within_limit:
        logger.warning(f"Rate limit exceeded for API key: {api_key[:10]}...")
        return False

    return True


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Middleware for API key authentication and rate limiting."""
    # 跳过公开端点
    if request.url.path in ["/", "/docs", "/openapi.json", "/health"]:
        return await call_next(request)

    # 检查 X-API-Key
    api_key = request.headers.get("X-API-Key")
    if not api_key:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"detail": "Missing X-API-Key header"},
        )

    # 验证 Key
    if not await verify_key(api_key, request):
        return JSONResponse(
            status_code=status.HTTP_403_FORBIDDEN,
            content={"detail": "Invalid API key or rate limit exceeded"},
        )

    return await call_next(request)
```

#### 1.4.2 错误响应

| 场景 | 状态码 | 响应 |
|--------|--------|------|
| **缺少 X-API-Key** | 401 | `{"detail": "Missing X-API-Key header"}` |
| **无效 API Key** | 403 | `{"detail": "Invalid API key or rate limit exceeded"}` |
| **速率超限** | 403 | `{"detail": "Invalid API key or rate limit exceeded"}` |
| **Key 已撤销** | 403 | `{"detail": "Invalid API key or rate limit exceeded"}` |

---

## 核心算法

### 2.1 滑动窗口速率限制

#### 2.1.1 算法描述

滑动窗口算法在固定时间窗口内限制请求数量，窗口随时间滑动。

```
时间轴：─────────────────────────────────────>
        |←─── window (60s) ─→|

当前时间：now
窗口范围：[now - window, now]

请求时间戳：t1, t2, t3, t4, t5, ...

有效请求：t_i ∈ [now - window, now]
无效请求：t_i ∉ [now - window, now]
```

#### 2.1.2 Redis 实现

```python
# 使用 ZSET 存储，score 为时间戳
key = f"ratelimit:{api_key}"
now = time.time()
window = 60
limit = 200

# 1. 移除过期请求（score < now - window）
pipe.zremrangebyscore(key, 0, now - window)

# 2. 计数当前请求
pipe.zcard(key)

# 3. 添加新请求（score = now）
pipe.zadd(key, {str(uuid.uuid4()): now})

# 4. 设置过期时间（避免内存泄漏）
pipe.expire(key, window)

# 5. 执行管道
results = await pipe.execute()
count = results[1]

# 6. 判断是否超限
return count <= limit
```

#### 2.1.3 复杂度分析

| 操作 | 复杂度 | 说明 |
|------|---------|------|
| `zremrangebyscore` | O(log N + M) | N = 总成员数，M = 移除数 |
| `zcard` | O(1) | 直接计数 |
| `zadd` | O(log N) | 插入新成员 |
| `expire` | O(1) | 设置 TTL |

**总体复杂度**：O(log N)

### 2.2 双重检查锁定

#### 2.2.1 算法描述

双重检查锁定（Double-Checked Locking）是一种减少锁争用的并发模式。

```
第一次检查（无锁）→ 存在？→ 返回实例
                    │
                    否
                    ▼
            获取全局锁
                    │
第二次检查（有锁）→ 存在？→ 返回实例
                    │
                    否
                    ▼
            创建新实例
                    │
            添加到缓存
                    │
            返回实例
```

#### 2.2.2 Python asyncio 实现

```python
async def get_agent_instance(agent_id: str) -> Memory:
    # 第一次检查（无锁）
    if agent_id in _instances:
        return _instances[agent_id]

    # 获取全局锁
    async with _global_lock:
        # 第二次检查（有锁）
        if agent_id in _instances:
            return _instances[agent_id]

        # 创建实例
        instance = Memory.from_config(build_agent_config(agent_id))
        _instances[agent_id] = instance
        return instance
```

#### 2.2.3 优点

| 优点 | 说明 |
|------|------|
| **减少锁争用** | 大部分情况无需加锁 |
| **延迟初始化** | 按需创建实例 |
| **线程安全** | asyncio.Lock 保证原子性 |
| **内存高效** | 单例模式避免重复创建 |

---

## 数据库设计

### 3.1 PostgreSQL + pgvector

#### 3.1.1 扩展安装

```sql
-- 启用 pgvector 扩展
CREATE EXTENSION IF NOT EXISTS vector;
```

#### 3.1.2 表结构

```sql
-- 记忆表
CREATE TABLE IF NOT EXISTS memories (
    id VARCHAR(36) PRIMARY KEY,
    memory TEXT NOT NULL,
    embedding vector(1024),  -- 或 1536，取决于嵌入模型
    user_id VARCHAR,
    agent_id VARCHAR,
    run_id VARCHAR,
    metadata JSONB,
    categories VARCHAR[],
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 创建 HNSW 索引
CREATE INDEX memories_embedding_idx ON memories
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- 普通索引
CREATE INDEX memories_user_id_idx ON memories(user_id);
CREATE INDEX memories_agent_id_idx ON memories(agent_id);
CREATE INDEX memories_run_id_idx ON memories(run_id);
CREATE INDEX memories_created_at_idx ON memories(created_at DESC);
```

#### 3.1.3 HNSW 索引参数

| 参数 | 默认值 | 说明 |
|------|---------|------|
| `m` | 16 | 每个节点的最大连接数 |
| `ef_construction` | 64 | 构建时的搜索范围 |
| `ef` (查询时) | 40 | 查询时的搜索范围 |

**权衡**：
- `m` ↑ → 精度 ↑，内存 ↑
- `ef_construction` ↑ → 精度 ↑，构建时间 ↑
- `ef` ↑ → 精度 ↑，查询时间 ↑

### 3.2 Neo4j 图存储（可选）

#### 3.2.1 数据模型

```cypher
// 实体节点
CREATE (:Entity {id: 'uuid', name: 'string', type: 'string'})

// 关系
(:Entity)-[:RELATED_TO {type: 'string', weight: float}]->(:Entity)
(:Entity)-[:HAS_ATTRIBUTE {key: 'string', value: 'string'}]->(:Attribute)
```

#### 3.2.2 查询示例

```cypher
// 查找相关实体
MATCH (e:Entity {id: $id})-[r:RELATED_TO]-(related:Entity)
RETURN related, r
ORDER BY r.weight DESC
LIMIT 10

// 查找路径
MATCH path = shortestPath((e1:Entity {id: $id1})-[:RELATED_TO*]-(e2:Entity {id: $id2}))
RETURN path
```

### 3.3 SQLite 历史数据库

#### 3.3.1 表结构

```sql
-- 记忆变更历史表
CREATE TABLE IF NOT EXISTS memory_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id VARCHAR(36) NOT NULL,
    previous_value TEXT,
    new_value TEXT,
    event VARCHAR(10) NOT NULL,  -- ADD, UPDATE, DELETE
    actor_id VARCHAR(36),
    role VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 索引
CREATE INDEX history_memory_id_idx ON memory_history(memory_id);
CREATE INDEX history_timestamp_idx ON memory_history(timestamp DESC);
```

---

## 错误处理

### 4.1 错误分类

| 类别 | HTTP 状态码 | 示例 |
|------|-------------|------|
| **认证错误** | 401, 403 | 缺少/无效 API Key |
| **参数错误** | 400 | 缺少必需参数 |
| **资源错误** | 404 | 记忆不存在 |
| **服务器错误** | 500 | 数据库连接失败 |

### 4.2 错误响应格式

```json
{
  "detail": "Error message"
}
```

### 4.3 全局异常处理

```python
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Handle all uncaught exceptions."""
    logger.exception(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error"},
    )
```

### 4.4 端点特定错误处理

```python
@app.post("/memories", summary="Create memories")
async def add_memory(memory_create: MemoryCreate, request: Request):
    """Store new memories."""
    # 参数验证
    if not any([memory_create.user_id, memory_create.agent_id, memory_create.run_id]):
        raise HTTPException(
            status_code=400,
            detail="At least one identifier (user_id, agent_id, run_id) is required."
        )

    try:
        # 执行操作
        agent_id = memory_create.agent_id or "default"
        memory_instance = await get_agent_instance(agent_id)
        response = memory_instance.add(
            messages=[m.model_dump() for m in memory_create.messages],
            **{k: v for k, v in memory_create.model_dump().items() if v is not None and k != "messages"}
        )
        return JSONResponse(content=response)
    except Exception as e:
        logger.exception(f"Error in add_memory for agent {agent_id}:")
        raise HTTPException(status_code=500, detail=str(e))
```

---

## 性能优化

### 5.1 数据库优化

#### 5.1.1 连接池

```python
# psycopg2 连接池配置
{
    "minconn": 2,
    "maxconn": 20,
    "options": "-c statement_timeout=5000"
}
```

#### 5.1.2 查询优化

| 优化 | 效果 |
|------|------|
| **HNSW 索引** | 向量搜索从 O(N) → O(log N) |
| **分页限制** | 减少数据传输 |
| **选择性查询** | 避免全表扫描 |
| **批量操作** | 减少往返次数 |

### 5.2 应用层优化

#### 5.2.1 异步并发

```python
# 并发处理多个请求
async def process_multiple_requests(requests: List[Request]):
    """Process multiple requests concurrently."""
    tasks = [process_request(req) for req in requests]
    return await asyncio.gather(*tasks)
```

#### 5.2.2 缓存策略

| 缓存类型 | 用途 | TTL |
|----------|------|-----|
| **搜索结果** | 缓存常见查询 | 5 分钟 |
| **API Key 验证** | 减少文件读取 | 1 分钟 |
| **配置加载** | 减少配置解析 | 永久 |

### 5.3 内存优化

| 优化 | 说明 |
|------|------|
| **实例池复用** | 避免重复创建 Memory 实例 |
| **弱引用** | 允许 GC 回收未使用实例 |
| **延迟加载** | 按需加载资源 |

---

## 监控与日志

### 6.1 日志级别

| 级别 | 用途 | 示例 |
|------|------|------|
| `DEBUG` | 详细调试信息 | 函数参数、中间值 |
| `INFO` | 一般信息 | 请求处理、实例创建 |
| `WARNING` | 警告信息 | Redis 连接失败、速率超限 |
| `ERROR` | 错误信息 | API Key 验证失败 |
| `EXCEPTION` | 异常堆栈 | 未捕获异常 |

### 6.2 日志格式

```python
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
```

### 6.3 健康检查

```python
@app.get("/health", response_model=HealthResponse, summary="Health check")
async def health_check():
    """Check server health status."""
    redis_status = "ok" if redis_manager.enabled else "disabled"
    return HealthResponse(
        status="healthy",
        loaded_agents=len(_instances),
        redis=redis_status,
    )
```

### 6.4 监控指标

| 指标 | 说明 |
|------|------|
| **请求延迟** | P50, P95, P99 |
| **吞吐量** | requests/second |
| **错误率** | errors/total |
| **活跃实例** | 加载的 Memory 实例数 |
| **Redis 状态** | 连接状态、命令延迟 |

---

## 附录

### A. 性能基准

| 操作 | P50 | P95 | P99 |
|------|-----|-----|-----|
| **健康检查** | 12ms | 14ms | 18ms |
| **创建记忆（含 LLM）** | 4.0s | 4.5s | 5.0s |
| **搜索记忆** | 80ms | 95ms | 120ms |
| **获取所有记忆** | 20ms | 30ms | 50ms |
| **更新记忆** | 90ms | 110ms | 150ms |
| **删除记忆** | 25ms | 35ms | 50ms |

### B. 配置最佳实践

| 场景 | 配置 |
|------|------|
| **开发环境** | 低速率限制、详细日志 |
| **生产环境** | 高速率限制、结构化日志 |
| **高并发** | 增加连接池、调优 HNSW 参数 |
| **低延迟** | 启用缓存、本地 LLM |

---

**文档结束**
