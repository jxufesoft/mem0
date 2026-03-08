# Mem0 Enhanced Server 技术文档

## 目录

1. [系统架构](#系统架构)
2. [API 文档](#api-文档)
3. [部署指南](#部署指南)
4. [配置参考](#配置参考)
5. [运维指南](#运维指南)
6. [故障排查](#故障排查)

---

## 系统架构

### 架构概述

Mem0 Enhanced Server 是一个生产级的记忆管理系统，提供 RESTful API 用于管理和搜索用户/代理的记忆。

```
┌─────────────────────────────────────────────────────────────┐
│                  Client Application                  │
│                   (OpenClaw Plugin)                 │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│            Mem0 Enhanced Server                 │
│         (FastAPI + Python + Uvicorn)         │
│                                               │
│  ┌────────────┐  ┌───────────┐  ┌────────┐│
│  │   API Key  │  │   Rate     │  │ Instance││
│  │   Manager  │  │   Limit    │  │   Pool ││
│  └────────────┘  │   Manager   │  └────────┘│
│                 └───────────┘               │
└──────────────────────┬───────────────────────────┘
                       │
        ┌────────────┼─────────────┬───────────────┬─────────────┐
        ▼            ▼             ▼             ▼
┌──────────────┐  ┌──────────┐  ┌────────────┐  ┌───────────┐
│  PostgreSQL  │  │   Neo4j  │  │   Redis    │  │   LLM     │
│  + pgvector  │  │   Graph   │  │   Cache     │  │   API     │
│              │  │           │  │            │  │           │
└──────────────┘  └───────────┘  └────────────┘  └───────────┘
```

### 核心组件

#### 1. API Server (FastAPI)
- **框架**: FastAPI 3.11+
- **ASGI 服务器**: Uvicorn (4 workers)
- **认证**: X-API-Key header + Admin Secret Key
- **速率限制**: Redis 滑动窗口

#### 2. Multi-Agent Memory Instance Pool
- **模式**: Double-checked locking
- **隔离**: 每个 Agent 有独立的 PostgreSQL collection
- **缓存**: 内存中的 Memory 实例池

#### 3. Vector Store (PostgreSQL + pgvector)
- **用途**: 存储和搜索向量嵌入
- **索引**: HNSW (Hierarchical Navigable Small World)
- **维度**: 可配置（默认 1536，bge-m3: 1024）

#### 4. Graph Store (Neo4j)
- **用途**: 存储实体关系
- **可选**: 可以禁用以简化部署
- **配置**: 独立的 Neo4j 实例

#### 5. Rate Limiting (Redis)
- **算法**: 滑动窗口
- **默认配置**: 200 req/60s
- **粒度**: 每个 API Key 独立限制

#### 6. LLM Integration
- **支持**: OpenAI 兼容 API
- **用途**: 事实提取、重新排序
- **可配置**: 自定义端点、模型

#### 7. Embedding
- **支持**: OpenAI 兼容 API
- **用途**: 文本向量化
- **可配置**: 模型、维度、自定义端点

### 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│                  Client Request                     │
│                  (X-API-Key + Data)                 │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│              Authentication Middleware                │
│  ┌────────────────────────────────────────────┐  │
│  │  Verify API Key (Agent or Admin)   │  │
│  │  Check Rate Limit (Redis)             │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│              Memory Instance Pool                 │
│  ┌────────────────────────────────────────────┐  │
│  │  Get or Create Agent Instance        │  │
│  │  - Per-agent PostgreSQL collection    │  │
│  │  - Shared LLM/Embedder           │  │
│  └────────────────────────────────────────────┘  │
└──────────────┬───────────────────────────────────┘
              │
              │
              ▼
┌──────────────────────────────────────────────────────┐
│           Memory Processing Pipeline            │
│  ┌────────────────────────────────────────────┐  │
│  │ 1. Extract Facts (LLM)           │  │
│  │ 2. Embed Text (Embedder)          │  │
│  │ 3. Store Vectors (PostgreSQL)       │  │
│  │ 4. Store Relations (Neo4j - opt)   │  │
│  │ 5. Track History (SQLite)           │  │
│  └────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────┐
│               Response to Client               │
│  ┌────────────────────────────────────────────┐  │
│  │ { results: [...], relations: [...] }   │  │
│  └────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

### 多 Agent 架构

每个 Agent 有独立的 PostgreSQL collection，实现数据隔离：

```python
# Agent 1 的 collection
collection_name: "memories_agent_001"  # 包含 agent_001 的记忆

# Agent 2 的 collection
collection_name: "memories_agent_002"  # 包含 agent_002 的记忆

# 共享组件
- LLM: 所有 Agent 共享
- Embedder: 所有 Agent 共享
- Redis: 所有 Agent 共享（独立限流）
- Neo4j: 所有 Agent 共享（可选）
```

### 性能特性

1. **异步处理**: asyncio 并发
2. **实例池**: 避免重复初始化
3. **连接池**: psycopg2 连接池
4. **索引优化**: HNSW 向量索引
5. **Redis 缓存**: 可选的搜索结果缓存

---

## API 文档

### 基础信息

- **Base URL**: `http://your-server:8000`
- **Content-Type**: `application/json`
- **认证**: Header `X-API-Key: <your-key>`
- **API Version**: v2.0.0

### 端点列表

| 方法 | 端点 | 描述 | 认证 |
|------|--------|------|--------|
| GET | `/health` | 健康检查 | 否 |
| POST | `/admin/keys` | 创建 API Key | Admin |
| GET | `/admin/keys` | 列出 API Keys | Admin |
| DELETE | `/admin/keys` | 撤销 API Key | Admin |
| POST | `/memories` | 创建记忆 | Agent |
| GET | `/memories` | 获取所有记忆 | Agent |
| GET | `/memories/{id}` | 获取单个记忆 | Agent |
| POST | `/search` | 搜索记忆 | Agent |
| PUT | `/memories/{id}` | 更新记忆 | Agent |
| DELETE | `/memories/{id}` | 删除记忆 | Agent |
| DELETE | `/memories` | 删除所有记忆 | Agent |
| POST | `/reset` | 重置所有记忆 | Agent |
| POST | `/configure` | 配置内存（不推荐）| Agent |

### 通用响应格式

```json
{
  "results": [
    {
      "id": "uuid",
      "memory": "记忆内容",
      "user_id": "用户ID",
      "agent_id": "代理ID",
      "run_id": "运行ID",
      "score": 0.95,
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z",
      "metadata": {},
      "categories": []
    }
  ],
  "relations": {
    "deleted_entities": [],
    "added_entities": []
  }
}
```

### 错误响应格式

```json
{
  "detail": "错误描述"
}
```

HTTP 状态码：
- `200 OK`: 请求成功
- `201 Created`: 资源创建成功
- `400 Bad Request`: 请求参数错误
- `401 Unauthorized`: 缺少 API Key
- `403 Forbidden`: API Key 无效或超限
- `404 Not Found`: 资源不存在
- `500 Internal Server Error`: 服务器内部错误

### API 端点详解

#### 1. 健康检查

```bash
GET /health
# 无需认证
```

响应：
```json
{
  "status": "healthy",
  "loaded_agents": 3,
  "redis": "ok"
}
```

#### 2. 创建 API Key (Admin)

```bash
POST /admin/keys
Header: X-API-Key: <ADMIN_SECRET_KEY>
Content-Type: application/json

{
  "agent_id": "agent_001",
  "description": "用于测试的代理"
}
```

响应：
```json
{
  "api_key": "mem0_xxxxxxxxxxxxxxxxxxxxxx",
  "agent_id": "agent_001",
  "description": "用于测试的代理"
}
```

#### 3. 列出 API Keys (Admin)

```bash
GET /admin/keys
Header: X-API-Key: <ADMIN_SECRET_KEY>
```

响应：
```json
{
  "keys": [
    {
      "key_prefix": "mem0_xxxxxx...",
      "agent_id": "agent_001",
      "description": "测试代理",
      "created_at": 1704064000.123,
      "revoked": false
    }
  ]
}
```

#### 4. 撤销 API Key (Admin)

```bash
DELETE /admin/keys
Header: X-API-Key: <ADMIN_SECRET_KEY>
Content-Type: application/json

{
  "api_key": "mem0_xxxxxxxxxxxxxxxxxxxxxx"
}
```

响应：
```json
{
  "message": "API key revoked successfully"
}
```

#### 5. 创建记忆

```bash
POST /memories
Header: X-API-Key: <AGENT_API_KEY>
Content-Type: application/json

{
  "messages": [
    {
      "role": "user",
      "content": "我的名字是 Alice"
    },
    {
      "role": "assistant",
      "content": "我记住了你的名字是 Alice"
    }
  ],
  "user_id": "user_001",
  "agent_id": "agent_001",
  "metadata": {
    "source": "user_input",
    "priority": "high"
  }
}
```

响应：
```json
{
  "results": [
    {
      "id": "uuid-1",
      "memory": "名字是 Alice",
      "event": "ADD",
      "user_id": "user_001",
      "agent_id": "agent_001"
    }
  ]
}
```

#### 6. 获取所有记忆

```bash
GET /memories?user_id=user_001&agent_id=agent_001&limit=10
Header: X-API-Key: <AGENT_API_KEY>
```

查询参数：
- `user_id`: 用户ID（可选）
- `agent_id`: 代理ID（可选）
- `run_id`: 运行ID（可选）
- 至少需要一个

#### 7. 获取单个记忆

```bash
GET /memories/{memory_id}?agent_id=agent_001
Header: X-API-Key: <AGENT_API_KEY>
```

#### 8. 搜索记忆

```bash
POST /search
Header: X-API-Key: <AGENT_API_KEY>
Content-Type: application/json

{
  "query": "Alice 喜欢什么?",
  "user_id": "user_001",
  "agent_id": "agent_001",
  "limit": 5,
  "filters": {
    "category": "preferences"
  },
  "threshold": 0.7
}
```

参数：
- `query`: 搜索查询（必需）
- `limit`: 返回结果数量（默认: 10）
- `threshold`: 最小相似度分数（可选）
- `filters`: 元数据过滤（可选）
- `user_id`, `agent_id`, `run_id`: 作用域过滤（可选）

#### 9. 更新记忆

```bash
PUT /memories/{memory_id}?agent_id=agent_001
Header: X-API-Key: <AGENT_API_KEY>
Content-Type: application/json

{
  "memory": "Alice 喜欢编程和音乐",
  "metadata": {
    "verified": true
  }
}
```

#### 10. 删除记忆

```bash
DELETE /memories/{memory_id}?agent_id=agent_001
Header: X-API-Key: <AGENT_API_KEY>
```

响应：
```json
{
  "message": "Memory deleted successfully"
}
```

#### 11. 删除所有记忆

```bash
DELETE /memories?user_id=user_001&agent_id=agent_001
Header: X-API-Key: <AGENT_API_KEY>
```

#### 12. 重置记忆

```bash
POST /reset?agent_id=agent_001
Header: X-API-Key: <AGENT_API_KEY>
```

响应：
```json
{
  "message": "All memories reset"
}
```

### 认证流程

```
┌─────────────────────────────────────────────────────────┐
│                  Client Request                     │
│                  (X-API-Key: xxxxx)                 │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│              Authentication Middleware                │
│  ┌────────────────────────────────────────────┐  │
│  │  Request.path.startswith("/admin") ?     │  │
│  │    ┌──────────┐  ┌────────────┐  │  │
│  │    │ Verify    │  │ Verify     │  │
│  │    │ Admin     │  │ Agent Key  │  │
│  │    │ Secret    │  │            │  │
│  │    └──────────┘  └────────────┘  │  │
│  │                                      │  │
│  │  ┌────────────────────────────────────────────┐  │
│  │  │ If valid:                          │  │
│  │  │  ┌──────────────────────────────────┐  │  │
│  │  │  │ Check Rate Limit (Redis)      │  │
│  │  │  │ - Sliding window algorithm │  │
│  │  │  │ - Track per API key        │  │
│  │  │  └──────────────────────────────┘  │  │
│  │  │                                  │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ If within limit:             │  │
│  │  │  Allow request                │  │
│  │  └──────────────────────────────────┘  │  │
│  │  │                                  │  │
│  └────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

### 速率限制

Redis 滑动窗口算法：
- 记录每个请求的时间戳
- 删除窗口外的旧时间戳
- 统计窗口内的请求数
- 超出限制时返回 403

配置参数：
- `RATE_LIMIT_REQUESTS`: 默认 200
- `RATE_LIMIT_WINDOW`: 默认 60 秒

---

## 部署指南

### Docker Compose 部署

#### 目录结构

```
mem0-server/
├── docker-compose.prod.yaml    # 生产配置
├── Dockerfile                    # 服务镜像
├── main.py                       # 服务器代码
├── requirements.txt               # Python 依赖
├── .env                          # 环境变量
└── postgres-init/               # 数据库初始化
    └── 01-init.sql
```

#### 快速启动

```bash
# 1. 克隆仓库
git clone <repository-url>
cd mem0/server

# 2. 配置环境变量
cp .env.example .env
vim .env  # 编辑配置

# 3. 启动服务
docker compose -f docker-compose.prod.yaml up -d

# 4. 查看状态
docker compose -f docker-compose.prod.yaml ps
docker compose -f docker-compose.prod.yaml logs -f
```

#### 服务列表

| 服务 | 镜像 | 端口 | 说明 |
|------|------|------|------|
| mem0-postgres | pgvector/pgvector:pg16 | 5432 | PostgreSQL + pgvector |
| mem0-neo4j | neo4j:5.26-community | 7474, 7687 | Neo4j 图数据库 |
| mem0-redis | redis:7-alpine | 6379 | Redis 缓存/限流 |
| mem0-server | 自定义构建 | 8000 | Mem0 API 服务器 |

### 环境配置

#### .env 文件

```bash
# ============================================================================
# LLM 配置
# ============================================================================
OPENAI_API_KEY=sk-your-api-key-here
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-nano-2025-04-14
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIMENSIONS=1536

# ============================================================================
# PostgreSQL + pgvector 配置
# ============================================================================
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=mem0db
POSTGRES_USER=mem0user
POSTGRES_PASSWORD=your-secure-password
POSTGRES_COLLECTION_NAME=memories

# ============================================================================
# Neo4j 配置（可选）
# ============================================================================
NEO4J_URI=bolt://neo4j:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your-secure-password

# ============================================================================
# Redis 配置
# ============================================================================
REDIS_URL=redis://redis:6379/0
REDIS_PASSWORD=your-secure-password

# ============================================================================
# 认证
# ============================================================================
ADMIN_SECRET_KEY=your-very-secure-admin-secret

# ============================================================================
# 速率限制
# ============================================================================
RATE_LIMIT_REQUESTS=200
RATE_LIMIT_WINDOW=60

# ============================================================================
# 其他
# ============================================================================
HISTORY_DB_PATH=/app/history/history.db
```

### 数据持久化

所有数据持久化到 Docker volumes：

```yaml
volumes:
  postgres-data:
    driver: local
  neo4j-data:
    driver: local
  neo4j-logs:
    driver: local
  redis-data:
    driver: local
  postgres-init:
    driver: local
  history-data:
    driver: local
```

### 健康检查

```bash
# 检查所有服务状态
docker compose -f docker-compose.prod.yaml ps

# 查看服务日志
docker compose -f docker-compose.prod.yaml logs -f --tail=100

# 健康检查
curl http://localhost:8000/health
```

### 扩展部署

#### 水平扩展

```yaml
# docker-compose.yaml 中的 worker 数量
services:
  mem0-server:
    deploy:
      replicas: 3  # 3 个实例
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

#### 负载均衡

使用 Nginx 或 HAProxy 负载均衡多个实例：

```nginx
upstream mem0_servers {
    server mem0-server-1:8000;
    server mem0-server-2:8000;
    server mem0-server-3:8000;
}

server {
    listen 80;

    location / {
        proxy_pass http://mem0_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 配置参考

### 环境变量完整列表

| 变量 | 必需 | 默认值 | 说明 |
|------|--------|---------|------|
| OPENAI_API_KEY | 是 | - | LLM API 密钥 |
| POSTGRES_HOST | 否 | postgres | PostgreSQL 主机 |
| POSTGRES_PORT | 否 | 5432 | PostgreSQL 端口 |
| POSTGRES_DB | 否 | postgres | PostgreSQL 数据库名 |
| POSTGRES_USER | 否 | postgres | PostgreSQL 用户名 |
| POSTGRES_PASSWORD | 否 | postgres | PostgreSQL 密码 |
| ADMIN_SECRET_KEY | 是 | admin_secret_key_CHANGE_ME | Admin API 密钥 |
| POSTGRES_COLLECTION_NAME | 否 | memories | Collection 前缀 |
| EMBEDDING_DIMENSIONS | 否 | 1536 | 向量维度 |

### LLM 配置

| 变量 | 说明 | 推荐值 |
|------|------|---------|
| OPENAI_MODEL | 使用的模型 | gpt-4.1-nano-2025-04-14 |
| OPENAI_EMBEDDING_MODEL | 嵌入模型 | text-embedding-3-small |
| EMBEDDING_DIMENSIONS | 向量维度 | 1536 (text-embedding-3-small)<br>1024 (bge-m3) |
| OPENAI_BASE_URL | 自定义端点 | https://api.openai.com/v1 |

### PostgreSQL 配置

| 变量 | 说明 | 推荐值 |
|------|------|---------|
| POSTGRES_HOST | 数据库主机 | localhost 或容器名 |
| POSTGRES_PORT | 数据库端口 | 5432 |
| POSTGRES_DB | 数据库名 | mem0db |
| POSTGRES_USER | 数据库用户 | mem0user |
| POSTGRES_PASSWORD | 数据库密码 | 强密码 |
| POSTGRES_COLLECTION_NAME | Collection 前缀 | memories |
| EMBEDDING_DIMENSIONS | 向量维度 | 根据模型配置 |

### Redis 配置

| 变量 | 说明 | 推荐值 |
|------|------|---------|
| REDIS_URL | Redis 连接 | redis://redis:6379/0 |
| REDIS_PASSWORD | Redis 密码 | 强密码 |
| RATE_LIMIT_REQUESTS | 请求限制 | 200 |
| RATE_LIMIT_WINDOW | 时间窗口（秒） | 60 |

### Neo4j 配置

| 变量 | 说明 | 推荐值 |
|------|------|---------|
| NEO4J_URI | Neo4j 连接 | bolt://neo4j:7687 |
| NEO4J_USERNAME | Neo4j 用户 | neo4j |
| NEO4J_PASSWORD | Neo4j 密码 | 强密码 |

---

## 运维指南

### 日志管理

#### 查看日志

```bash
# 查看服务器日志
docker logs mem0-server --tail 100 -f

# 查看所有服务日志
docker compose -f docker-compose.prod.yaml logs --tail=50

# 查看特定时间段的日志
docker logs mem0-server --since "2024-01-01T00:00:00" --until "2024-01-01T01:00:00"
```

#### 日志级别

服务器日志级别：
- `INFO`: 正常操作信息
- `WARNING`: 警告信息
- `ERROR`: 错误信息
- `DEBUG`: 调试信息（需要修改代码）

### 监控指标

#### 关键指标

1. **性能指标**
   - API 响应时间
   - 数据库查询时间
   - LLM 调用时间
   - 内存使用率
   - CPU 使用率

2. **业务指标**
   - 总请求数
   - 错误率
   - 速率限制触发次数
   - 活跃代理数量
   - 存储的记忆数量

3. **资源指标**
   - PostgreSQL 连接数
   - Redis 内存使用
   - 磁盘 I/O
   - 网络流量

#### 监控集成

```python
# 使用 Prometheus 监控
from prometheus_client import Counter, Histogram

# 指标定义
api_requests_total = Counter('mem0_api_requests_total', 'Total API requests')
api_request_duration = Histogram('mem0_api_request_duration_seconds', 'API request duration')
memory_operations_total = Counter('mem0_memory_operations_total', 'Memory operations')

# 在 API 端点中记录
@api_requests_total.labels(method='POST', endpoint='/memories').inc()
api_request_duration.observe(request_duration)
```

### 备份策略

#### 数据备份

```bash
# 备份 PostgreSQL
docker exec mem0-postgres pg_dump -U postgres -d mem0db > backup_$(date +%Y%m%d).sql

# 备份 Neo4j
docker exec mem0-neo4j neo4j-admin backup
docker cp mem0-neo4j:/var/lib/neo4j/data ./neo4j-backup

# 备份 Redis
docker exec mem0-redis redis-cli --rdb > redis-backup.rdb

# 备份历史数据
docker cp mem0-server:/app/history/history.db ./history-backup.db
```

#### 恢复流程

```bash
# 恢复 PostgreSQL
docker exec -i mem0-postgres psql -U postgres -d mem0db < backup_20240101.sql

# 恢复 Redis
docker exec -i mem0-redis redis-cli --rdb < redis-backup.rdb
```

### 维护操作

#### 日常维护

```bash
# 1. 检查磁盘空间
docker system df -v

# 2. 清理旧日志
docker logs mem0-server > /dev/null 2>&1 | grep -q "old_log"

# 3. 重启服务（如需要）
docker compose -f docker-compose.prod.yaml restart mem0-server

# 4. 检查服务健康状态
docker compose -f docker-compose.prod.yaml ps
curl http://localhost:8000/health
```

#### 数据库维护

```bash
# 连接到 PostgreSQL
docker exec -it mem0-postgres psql -U postgres -d mem0db

# VACUUM 表
VACUUM ANALYZE mem0_vectors_agent_001;

# 查看表大小
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(table_schema, tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(table_schema, tablename) DESC;

# 查看索引使用
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public';
```

### 性能优化

#### PostgreSQL 优化

```sql
-- 优化查询计划
ANALYZE mem0_vectors_agent_001;

-- 更新统计信息
VACUUM ANALYZE mem0_vectors_agent_001;

-- 重建索引
REINDEX INDEX CONCURRENTLY mem0_vectors_agent_001_hnsw_idx;
```

#### Redis 优化

```bash
# 查看 Redis 内存使用
docker exec mem0-redis redis-cli INFO memory

# 监控慢查询
docker exec mem0-redis redis-cli SLOWLOG GET 10
```

---

## 故障排查

### 常见问题

#### 1. 服务器启动失败

**症状**: 容器无法启动

**排查步骤**:
```bash
# 1. 检查端口占用
netstat -tlnp | grep -E ':(8000|5432|7687|6379)'

# 2. 查看容器日志
docker logs mem0-server

# 3. 检查环境变量
docker compose -f docker-compose.prod.yaml config

# 4. 验证依赖服务状态
docker compose -f docker-compose.prod.yaml ps
```

**解决方案**:
- 确保端口未被占用
- 检查 .env 文件格式
- 验证所有必需环境变量已设置
- 重启 Docker daemon: `sudo systemctl restart docker`

#### 2. 连接数据库失败

**症状**: API 返回 500 错误，日志显示连接错误

**排查步骤**:
```bash
# 1. 检查 PostgreSQL 状态
docker exec mem0-postgres pg_isready -U postgres

# 2. 测试数据库连接
docker exec mem0-server python -c "
import psycopg2
conn = psycopg2.connect('host=postgres user=postgres password=xxx dbname=mem0db')
print('Connection successful')
"

# 3. 检查 pgvector 扩展
docker exec mem0-postgres psql -U postgres -d mem0db -c "SELECT * FROM pg_extension WHERE extname = 'vector'"
```

**解决方案**:
- 确保 PostgreSQL 容器健康运行
- 验证 pgvector 扩展已安装
- 检查数据库连接字符串
- 检查用户权限

#### 3. 速率限制触发

**症状**: API 返回 403 错误

**排查步骤**:
```bash
# 1. 检查 Redis 状态
docker exec mem0-redis redis-cli ping

# 2. 查看特定 API Key 的限制情况
docker exec mem0-redis redis-cli ZRANGE rate:limit:mem0_xxx 0 -1

# 3. 手动清除限制
docker exec mem0-redis redis-cli DEL rate:limit:mem0_xxx
```

**解决方案**:
- 检查 API Key 是否正确
- 调整 RATE_LIMIT_REQUESTS 配置
- 临时清除限制用于测试

#### 4. 内存溢出

**症状**: 服务器响应缓慢或崩溃

**排查步骤**:
```bash
# 1. 检查容器资源使用
docker stats mem0-server --no-stream

# 2. 查看内存使用
docker exec mem0-server free -h

# 3. 检查进程
docker exec mem0-server ps aux
```

**解决方案**:
- 增加 Docker 内存限制
- 优化批量操作大小
- 增加实例数量进行水平扩展

#### 5. API Key 认证失败

**症状**: 401 Unauthorized

**排查步骤**:
```bash
# 1. 验证 API Key 格式
curl -H "X-API-Key: xxxxx" http://localhost:8000/health

# 2. 检查 Admin Secret Key
curl -H "X-API-Key: admin_secret" http://localhost:8000/admin/keys

# 3. 查看存储的 API Keys
curl -H "X-API-Key: admin_secret" http://localhost:8000/admin/keys
```

**解决方案**:
- 确保使用正确的 API Key
- Admin 端点必须使用 ADMIN_SECRET_KEY
- Agent 端点使用生成的 Agent API Key

#### 6. 向量维度不匹配

**症状**: 错误 "expected X dimensions, not Y"

**排查步骤**:
```bash
# 1. 检查配置
grep EMBEDDING_DIMENSIONS .env

# 2. 检查嵌入模型
grep OPENAI_EMBEDDING_MODEL .env

# 3. 验证一致性
# text-embedding-3-small -> 1536
# bge-m3 -> 1024
# text-embedding-3-large -> 3072
```

**解决方案**:
- 确保 EMBEDDING_DIMENSIONS 与模型匹配
- 对于 bge-m3，设置为 1024
- 对于 OpenAI 模型，参考官方维度

### 调试模式

#### 启用详细日志

```python
# 修改 main.py 中的日志级别
import logging

# 开发/调试环境
logging.basicConfig(level=logging.DEBUG, ...)

# 生产环境
logging.basicConfig(level=logging.INFO, ...)
```

#### 数据库调试

```bash
# 启用 PostgreSQL 查询日志
docker exec -i mem0-postgres psql -U postgres -d mem0db
ALTER DATABASE mem0db SET log_statement = 'all';

# 查看慢查询
SELECT
    query,
    mean_exec_time,
    calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### 性能问题排查

#### 分析 API 延迟

```bash
# 使用 curl 测量 API 延迟
time curl -H "X-API-Key: xxxxx" http://localhost:8000/health

# 使用 Apache Bench 进行压力测试
ab -n 1000 -c 10 -H "X-API-Key: xxxxx" http://localhost:8000/health
```

#### 数据库性能分析

```bash
# 查看活跃连接
docker exec mem0-postgres psql -U postgres -d mem0db -c "
SELECT count(*), state
FROM pg_stat_activity
WHERE datname = 'mem0db';
"

# 查看锁等待
docker exec mem0-postgres psql -U postgres -d mem0db -c "
SELECT lock_type, count(*)
FROM pg_locks
WHERE pid != pg_backend_pid();
"

# 查看慢查询
docker exec mem0-postgres psql -U postgres -d mem0db -c "
SELECT pid, now() - query_start, duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
"
```

### 安全检查

#### 验证配置安全性

```bash
# 检查文件权限
ls -la .env
chmod 600 .env

# 检查 Docker secrets
docker secret ls

# 验证环境变量不包含敏感信息
docker compose -f docker-compose.prod.yaml config
```

#### 网络安全

```bash
# 检查端口暴露
docker compose -f docker-compose.prod.yaml ps

# 配置防火墙
sudo ufw allow 8000/tcp

# 使用反向代理
# 配置 Nginx/HAProxy 进行 TLS 终止和负载均衡
```

---

## 附录

### 快速参考

#### API 快速命令

```bash
# 健康检查
curl http://localhost:8000/health

# 创建 API Key
curl -X POST http://localhost:8000/admin/keys \
  -H "Content-Type: application/json" \
  -H "X-API-Key: admin_secret" \
  -d '{"agent_id": "test", "description": "Test"}'

# 创建记忆
curl -X POST http://localhost:8000/memories \
  -H "Content-Type: application/json" \
  -H "X-API-Key: agent_key" \
  -d '{"messages": [{"role": "user", "content": "Test memory"}], "user_id": "user_001"}'

# 搜索记忆
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -H "X-API-Key: agent_key" \
  -d '{"query": "test", "user_id": "user_001"}'

# 获取所有记忆
curl http://localhost:8000/memories?user_id=user_001 \
  -H "X-API-Key: agent_key"
```

#### Docker 快速命令

```bash
# 启动所有服务
docker compose -f docker-compose.prod.yaml up -d

# 停止所有服务
docker compose -f docker-compose.prod.yaml down

# 重启服务
docker compose -f docker-compose.prod.yaml restart

# 查看日志
docker compose -f docker-compose.prod.yaml logs -f

# 查看状态
docker compose -f docker-compose.prod.yaml ps

# 进入容器
docker compose -f docker-compose.prod.yaml exec mem0-server bash

# 清理未使用的资源
docker system prune -f

# 更新镜像
docker compose -f docker-compose.prod.yaml pull
docker compose -f docker-compose.prod.yaml up -d --build
```

#### PostgreSQL 命令

```bash
# 连接数据库
docker exec -it mem0-postgres psql -U postgres -d mem0db

# 查看表
\dt

# 查看所有 collection
SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'mem0_vectors_%';

# 查看表大小
SELECT pg_size_pretty(pg_total_relation_size('mem0_vectors_' || tablename))
FROM pg_tables
WHERE schemaname = 'public';

# 重置特定 agent 的数据
DROP TABLE IF EXISTS mem0_vectors_agent_001;
```

#### Redis 命令

```bash
# 连接 Redis
docker exec -it mem0-redis redis-cli

# 查看所有键
KEYS *

# 查看特定模式
KEYS rate:*

# 清除所有限流数据
FLUSHDB

# 查看内存使用
INFO memory
```

### 性能基准

| 操作 | 预期时间 | 说明 |
|------|----------|------|
| 健康检查 | < 50ms | 轻量级查询 |
| 单个记忆创建 | 200-500ms | 包含 LLM 调用 |
| 批量创建 (10条) | 1-2s | 批量处理 |
| 记忆搜索 | 50-100ms | 向量搜索 |
| 顺序读取 | 20-50ms | 数据库查询 |
| 并发创建 | 50-100ms | 包含并发开销 |

### 支持资源

- **官方文档**: https://docs.mem0.ai/
- **GitHub Issues**: https://github.com/mem0ai/mem0/issues
- **Discord**: https://discord.gg/mem0
- **社区论坛**: https://community.mem0.ai/

---

**文档版本**: 1.0.0
**最后更新**: 2026-03-06
