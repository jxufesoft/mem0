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
| 端点类型 | 认证要求 |
|---------|---------|
| `/health` | 无需认证 |
| `/memories/*`, `/search` | API Key |
| `/admin/*` | ADMIN_SECRET_KEY |

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
  -H "X-API-Key: $ADMIN_SECRET_KEY" \
  -d '{"agent_id": "my-agent", "description": "My Agent API Key"}'
```

## API 端点

| 方法 | 端点 | 说明 |
|------|------|------|
| GET | /health | 健康检查 |
| POST | /admin/keys | 创建 API Key |
| GET | /admin/keys | 列出 API Keys |
| DELETE | /admin/keys | 撤销 API Key |
| POST | /memories | 创建记忆 |
| GET | /memories | 获取记忆列表 |
| GET | /memories/{id} | 获取单个记忆 |
| PUT | /memories/{id} | 更新记忆 |
| DELETE | /memories/{id} | 删除记忆 |
| GET | /memories/{id}/history | 获取记忆历史 |
| POST | /search | 搜索记忆 |
| DELETE | /memories | 批量删除记忆 |
| POST | /reset | 重置所有记忆 |

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

- [技术文档](./TECHNICAL_DOCUMENTATION.md) - 详细技术文档
- [部署指南](../openclaw/DEPLOYMENT_GUIDE.md) - 生产部署指南
