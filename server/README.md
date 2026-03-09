# Mem0 Enhanced Server

**版本**: v2.0.0 | **状态**: 生产就绪

Mem0 增强版 REST API 服务器，基于 FastAPI 构建，支持多 Agent、认证和速率限制。

## 功能特性

### 核心功能
- 📝 **记忆管理**: 创建、检索、搜索、更新、删除记忆
- 🔐 **API Key 认证**: 支持多 API Key 管理
- ⚡ **速率限制**: Redis 滑动窗口限流
- 🐳 **Docker 部署**: 完整的 docker-compose 配置

### 多 Agent 支持
- 按 `agent_id` 隔离存储
- 独立的向量集合（pgvector collection）
- 每个 Agent 独立的 Memory 实例

### 认证方式

所有 API 请求使用 `Authorization: Bearer <token>` 格式认证。

| 端点类型 | 认证要求 | Header 格式 |
|---------|---------|-------------|
| `/health` | 无需认证 | - |
| `/memories/*`, `/search` | API Key | `Authorization: Bearer ${API_KEY}` |
| `/admin/*` | ADMIN_SECRET_KEY | `Authorization: Bearer ${ADMIN_KEY}` |

## 快速开始

### Docker Compose 部署

```bash
cd server

# 创建数据目录
mkdir -p ~/mem0-data/{postgres,neo4j/data,redis,history}

# 启动服务
docker compose -f docker-compose.prod.yaml up -d

# 验证服务
curl http://localhost:8000/health
```

### 创建 API Key

```bash
# 使用管理员密钥创建 API Key
curl -X POST http://localhost:8000/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -d '{"agent_id": "my-agent", "description": "My Agent API Key"}'
```

## API 端点

| 方法 | 端点 | 说明 | 认证 |
|------|------|------|------|
| GET | /health | 健康检查 | 无 |
| POST | /admin/keys | 创建 API Key | Admin |
| GET | /admin/keys | 列出 API Keys | Admin |
| DELETE | /admin/keys | 撤销 API Key | Admin |
| POST | /memories | 创建记忆 | API Key |
| GET | /memories | 获取记忆列表 | API Key |
| GET | /memories/{id} | 获取单个记忆 | API Key |
| PUT | /memories/{id} | 更新记忆 | API Key |
| DELETE | /memories/{id} | 删除记忆 | API Key |
| GET | /memories/{id}/history | 获取记忆历史 | API Key |
| POST | /search | 搜索记忆 | API Key |
| DELETE | /memories | 批量删除记忆 | API Key |
| POST | /reset | 重置所有记忆 | API Key |

## API 使用示例

### 环境变量设置

```bash
# 服务器地址
export SERVER_URL="http://localhost:8000"

# 管理员密钥（用于 /admin/* 端点）
export ADMIN_KEY="admin_secret_key_CHANGE_ME"

# API Key（用于 /memories, /search 等端点）
export API_KEY="your-api-key-here"
```

---

### 1. 健康检查（无需认证）

```bash
curl -X GET "${SERVER_URL}/health"
```

**响应示例：**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-07T12:00:00Z"
}
```

---

### 2. 创建 API Key（管理员）

```bash
curl -X POST "${SERVER_URL}/admin/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ADMIN_KEY}" \
  -d '{
    "agent_id": "my-agent",
    "description": "My Agent API Key"
  }'
```

**响应示例：**
```json
{
  "api_key": "ak_live_abc123def456",
  "agent_id": "my-agent",
  "description": "My Agent API Key",
  "created_at": "2026-03-07T12:00:00Z"
}
```

---

### 3. 列出所有 API Keys（管理员）

```bash
curl -X GET "${SERVER_URL}/admin/keys" \
  -H "Authorization: Bearer ${ADMIN_KEY}"
```

**响应示例：**
```json
{
  "keys": [
    {
      "api_key": "ak_live_abc123...",
      "agent_id": "my-agent",
      "description": "My Agent API Key",
      "created_at": "2026-03-07T12:00:00Z",
      "is_active": true
    }
  ]
}
```

---

### 4. 撤销 API Key（管理员）

```bash
curl -X DELETE "${SERVER_URL}/admin/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ADMIN_KEY}" \
  -d '{
    "api_key": "ak_live_abc123def456"
  }'
```

**响应示例：**
```json
{
  "status": "revoked",
  "api_key": "ak_live_abc123def456"
}
```

---

### 5. 创建记忆

```bash
curl -X POST "${SERVER_URL}/memories" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "messages": [
      {"role": "user", "content": "我叫张三，我喜欢编程"}
    ],
    "agent_id": "my-agent",
    "metadata": {
      "source": "chat"
    }
  }'
```

**响应示例：**
```json
{
  "results": [
    {
      "id": "mem_abc123",
      "memory": "用户名叫张三",
      "hash": "hash123",
      "metadata": {"source": "chat"},
      "created_at": "2026-03-07T12:00:00Z",
      "updated_at": "2026-03-07T12:00:00Z"
    },
    {
      "id": "mem_def456",
      "memory": "张三喜欢编程",
      "hash": "hash456",
      "metadata": {"source": "chat"},
      "created_at": "2026-03-07T12:00:00Z",
      "updated_at": "2026-03-07T12:00:00Z"
    }
  ]
}
```

---

### 6. 获取所有记忆

```bash
curl -X GET "${SERVER_URL}/memories?agent_id=my-agent" \
  -H "Authorization: Bearer ${API_KEY}"
```

**响应示例：**
```json
{
  "results": [
    {
      "id": "mem_abc123",
      "memory": "用户名叫张三",
      "hash": "hash123",
      "metadata": {},
      "created_at": "2026-03-07T12:00:00Z",
      "updated_at": "2026-03-07T12:00:00Z"
    }
  ]
}
```

---

### 7. 获取单个记忆

> **注意**: 需要传递 `agent_id` 查询参数

```bash
curl -X GET "${SERVER_URL}/memories/mem_abc123?agent_id=my-agent" \
  -H "Authorization: Bearer ${API_KEY}"
```

**响应示例：**
```json
{
  "id": "mem_abc123",
  "memory": "用户名叫张三",
  "hash": "hash123",
  "metadata": {},
  "created_at": "2026-03-07T12:00:00Z",
  "updated_at": "2026-03-07T12:00:00Z"
}
```

---

### 8. 搜索记忆

```bash
curl -X POST "${SERVER_URL}/search" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "query": "用户叫什么名字",
    "agent_id": "my-agent",
    "limit": 5
  }'
```

**响应示例：**
```json
{
  "results": [
    {
      "id": "mem_abc123",
      "memory": "用户名叫张三",
      "hash": "hash123",
      "score": 0.95,
      "metadata": {},
      "created_at": "2026-03-07T12:00:00Z"
    }
  ]
}
```

---

### 9. 更新记忆

> **注意**: 需要传递 `agent_id` 查询参数

```bash
curl -X PUT "${SERVER_URL}/memories/mem_abc123?agent_id=my-agent" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "memory": "用户名叫张三，是一名软件工程师"
  }'
```

**响应示例：**
```json
{
  "id": "mem_abc123",
  "memory": "用户名叫张三，是一名软件工程师",
  "hash": "hash789",
  "metadata": {},
  "created_at": "2026-03-07T12:00:00Z",
  "updated_at": "2026-03-07T12:30:00Z"
}
```

---

### 10. 获取记忆历史

> **注意**: 需要传递 `agent_id` 查询参数

```bash
curl -X GET "${SERVER_URL}/memories/mem_abc123/history?agent_id=my-agent" \
  -H "Authorization: Bearer ${API_KEY}"
```

**响应示例：**
```json
{
  "results": [
    {
      "id": "hist_001",
      "memory_id": "mem_abc123",
      "old_memory": "用户名叫张三",
      "new_memory": "用户名叫张三，是一名软件工程师",
      "event": "UPDATE",
      "created_at": "2026-03-07T12:30:00Z"
    }
  ]
}
```

---

### 11. 删除单个记忆

> **注意**: 需要传递 `agent_id` 查询参数

```bash
curl -X DELETE "${SERVER_URL}/memories/mem_abc123?agent_id=my-agent" \
  -H "Authorization: Bearer ${API_KEY}"
```

**响应示例：**
```json
{
  "status": "deleted",
  "memory_id": "mem_abc123"
}
```

---

### 12. 批量删除记忆

```bash
curl -X DELETE "${SERVER_URL}/memories" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "agent_id": "my-agent",
    "memory_ids": ["mem_abc123", "mem_def456"]
  }'
```

**响应示例：**
```json
{
  "status": "deleted",
  "count": 2
}
```

---

### 13. 重置所有记忆

```bash
curl -X POST "${SERVER_URL}/reset" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "agent_id": "my-agent"
  }'
```

**响应示例：**
```json
{
  "status": "reset",
  "message": "All memories for agent my-agent have been deleted"
}
```

---

## 错误响应

| HTTP 状态码 | 说明 |
|------------|------|
| 400 | 请求参数错误 |
| 401 | 缺少 API Key |
| 403 | API Key 无效或已撤销 |
| 404 | 资源不存在 |
| 429 | 请求频率超限 |
| 500 | 服务器内部错误 |

**错误响应格式：**
```json
{
  "detail": "Invalid API Key"
}
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| POSTGRES_HOST | postgres | PostgreSQL 主机 |
| POSTGRES_PORT | 5432 | PostgreSQL 端口 |
| POSTGRES_DB | postgres | 数据库名 |
| POSTGRES_USER | postgres | 数据库用户 |
| POSTGRES_PASSWORD | postgres | 数据库密码 |
| REDIS_URL | redis://localhost:6379/0 | Redis 连接 URL |
| ADMIN_SECRET_KEY | admin_secret_key_CHANGE_ME | 管理员密钥 |
| OPENAI_API_KEY | - | OpenAI API Key |
| OPENAI_BASE_URL | - | OpenAI 兼容 API 基础 URL |
| OPENAI_MODEL | gpt-4.1-nano-2025-04-14 | LLM 模型 |
| OPENAI_EMBEDDING_MODEL | text-embedding-3-small | 嵌入模型 |
| EMBEDDING_DIMENSIONS | 1536 | 嵌入维度 |

## 文档

- [Plugin 部署指南](../openclaw/DEPLOYMENT_GUIDE.md) - 生产部署指南
- [Plugin 安装指南](../openclaw/INSTALLATION_GUIDE.md) - 安装步骤
- [Plugin 新手指南](../openclaw/BEGINNER_GUIDE.md) - 快速上手
- [测试报告](../openclaw/TEST_REPORT.md) - 详细测试报告
- [测试摘要](../openclaw/TEST_SUMMARY.md) - 测试结果概览
