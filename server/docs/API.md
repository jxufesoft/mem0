# Mem0 Server API 文档

## 版本信息

- **文档版本**: 1.0.0
- **最后更新**: 2026-03-07
- **API 版本**: 2.0.0
- **Base URL**: \`http://localhost:8000\`

---

## 目录

1. [概述](#概述)
2. [认证](#认证)
3. [端点列表](#端点列表)
4. [数据模型](#数据模型)
5. [错误码](#错误码)
6. [使用示例](#使用示例)

---

## 概述

### 1.1 基本信息

| 项目 | 值 |
|------|-----|
| **协议** | HTTP/1.1, HTTPS |
| **数据格式** | JSON |
| **字符编码** | UTF-8 |
| **认证方式** | Authorization: Bearer <api_key> |
| **速率限制** | 200 请求 / 60 秒 |

### 1.2 交互式文档

访问 \`http://localhost:8000/docs\` 查看 Swagger UI 交互式 API 文档。

---

## 认证

### 2.1 API Key 认证

所有 API 请求（除公开端点外）需要包含 \`X-API-Key\` header：

\`\`\`http
GET /memories HTTP/1.1
Host: localhost:8000
Authorization: Bearer mem0_your_api_key_here
Content-Type: application/json
\`\`\`

### 2.2 管理员认证

管理端点需要 \`ADMIN_SECRET_KEY\`：

\`\`\`http
POST /admin/keys HTTP/1.1
Host: localhost:8000
Authorization: Bearer your_admin_secret_key
Content-Type: application/json
\`\`\`

### 2.3 公开端点

以下端点不需要认证：
- \`GET /\`
- \`GET /docs\`
- \`GET /openapi.json\`
- \`GET /health\`

### 2.4 API Key 生命周期

| 状态 | 说明 | 撤销后 |
|------|------|--------|
| **生成** | 创建新的 API Key | - |
| **有效** | 正常使用中 | 可撤销 |
| **已撤销** | 不可使用 | 不可恢复 |

---

## 端点列表

### 3.1 健康检查

#### GET /health

检查服务器健康状态。

**请求**：
\`\`\`http
GET /health HTTP/1.1
Host: localhost:8000
\`\`\`

**响应**：
\`\`\`json
{
  "status": "healthy",
  "loaded_agents": 2,
  "redis": "ok"
}
\`\`\`

| 字段 | 类型 | 说明 |
|------|------|------|
| \`status\` | string | 服务器状态 |
| \`loaded_agents\` | integer | 已加载的代理实例数 |
| \`redis\` | string | Redis 状态（"ok" 或 "disabled"）|

---

### 3.2 API Key 管理

#### 生成 API Key

创建新的 API Key。

**认证**：需要 \`ADMIN_SECRET_KEY\`

**curl 示例**：
\`\`\`bash
curl -X POST http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" \\
  -H "Content-Type: application/json" \\
  -d '{
    "agent_id": "my-agent",
    "description": "Production API key for production environment"
  }'
\`\`\`

**响应示例**：
\`\`\`json
{
  "api_key": "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "agent_id": "my-agent",
  "description": "Production API key for production environment"
}
\`\`\`

**请求体**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 是 | 代理 ID |
| \`description\` | string | 否 | API Key 描述 |

**响应字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| \`api_key\` | string | 生成的 API Key |
| \`agent_id\` | string | 关联的代理 ID |
| \`description\` | string | API Key 描述 |

---

#### 列出所有 API Key

列出所有 API Key（不显示完整密钥，仅显示前缀）。

**认证**：需要 \`ADMIN_SECRET_KEY\`

**curl 示例**：
\`\`\`bash
curl -X GET http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key"
\`\`\`

**响应示例**：
\`\`\`json
{
  "keys": [
    {
      "key_prefix": "mem0_a1b2c3d4e5f...",
      "agent_id": "my-agent",
      "description": "Production API key",
      "created_at": 1709845432.123,
      "revoked": false
    },
    {
      "key_prefix": "mem0_xxx...",
      "agent_id": "test-agent",
      "description": "Test API key",
      "created_at": 1709846000.000,
      "revoked": false
    }
  ]
}
\`\`\`

**响应字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| \`keys[]\` | array | API Key 列表 |
| \`key_prefix\` | string | API Key 前 16 个字符（用于标识）|
| \`agent_id\` | string | 关联的代理 ID |
| \`description\` | string | API Key 描述 |
| \`created_at\` | number | 创建时间戳 |
| \`revoked\` | boolean | 是否已撤销 |

---

#### 撤销 API Key

撤销 API Key，使其无法继续使用。

**认证**：需要 \`ADMIN_SECRET_KEY\`

**curl 示例 1：撤销指定 key**
\`\`\`bash
curl -X DELETE http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" \\
  -H "Content-Type: application/json" \\
  -d '{
    "api_key": "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
  }'
\`\`\`

**curl 示例 2：从列表中查找并撤销**
\`\`\`bash
# 先列出所有 keys
KEYS=$(curl -s -X GET http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" | jq -r '.keys[] | .key_prefix')

# 显示并选择要撤销的 key
echo "Available keys:"
echo "$KEYS"
echo ""
echo "Enter key prefix to revoke:"
read KEY_PREFIX

# 撤销选中的 key
curl -X DELETE http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" \\
  -H "Content-Type: application/json" \\
  -d "{
    \"api_key\": \"$KEY_PREFIX\"
  }"
\`\`\`

**响应示例**：
\`\`\`json
{
  "message": "API key revoked successfully"
}
\`\`\`

**请求体**：
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`api_key\` | string | 是 | 要撤销的完整 API Key |

**响应字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| \`message\` | string | 撤销结果消息 |

**撤销后验证**：
\`\`\`bash
# 撤销后，该 API Key 将无法使用
curl -X POST http://localhost:8000/memories \\
  -H "Authorization: Bearer mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6" \\
  -H "Content-Type: application/json" \\
  -d '{
    "messages": [{"role": "user", "content": "test"}]
  }'

# 返回 403 Forbidden
{
  "detail": "Invalid API key or rate limit exceeded"
}
\`\`\`

---

### 3.3 记忆端点

#### POST /memories

存储新记忆。

**认证**：需要 API Key

**请求体**：
\`\`\`json
{
  "messages": [
    {
      "role": "user",
      "content": "My name is John and I live in San Francisco."
    },
    {
      "role": "assistant",
      "content": "Got it, I'll remember that."
    }
  ],
  "user_id": "user-123",
  "agent_id": "my-agent",
  "run_id": "run-456",
  "metadata": {
    "source": "chat"
  }
}
\`\`\`

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`messages\` | array | 是 | 对话消息列表 |
| \`messages[].role\` | string | 是 | 消息角色（"user" 或 "assistant"）|
| \`messages[].content\` | string | 是 | 消息内容 |
| \`user_id\` | string | 否* | 用户 ID |
| \`agent_id\` | string | 否* | 代理 ID |
| \`run_id\` | string | 否* | 运行 ID |
| \`metadata\` | object | 否 | 元数据 |

*至少需要 \`user_id\`、\`agent_id\` 或 \`run_id\` 中的一个。

**响应**：
\`\`\`json
{
  "results": [
    {
      "id": "uuid-1",
      "memory": "User name is John",
      "event": "ADD"
    },
    {
      "id": "uuid-2",
      "memory": "User lives in San Francisco",
      "event": "ADD"
    }
  ],
  "relations": []
}
\`\`\`

#### GET /memories

获取所有记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`user_id\` | string | 否* | 用户 ID |
| \`agent_id\` | string | 否* | 代理 ID |
| \`run_id\` | string | 否* | 运行 ID |

*至少需要一个参数。

**请求**：
\`\`\`http
GET /memories?user_id=user-123&agent_id=my-agent HTTP/1.1
Host: localhost:8000
Authorization: Bearer mem0_your_api_key
\`\`\`

**响应**：
\`\`\`json
{
  "results": [
    {
      "id": "uuid-1",
      "memory": "User name is John",
      "user_id": "user-123",
      "agent_id": "my-agent",
      "created_at": "2024-03-07T10:30:00Z"
    },
    {
      "id": "uuid-2",
      "memory": "User lives in San Francisco",
      "user_id": "user-123",
      "agent_id": "my-agent",
      "created_at": "2024-03-07T10:30:01Z"
    }
  ]
}
\`\`\`

#### GET /memories/{memory_id}

获取单个记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 否 | 代理 ID（默认 "default"）|

**请求**：
\`\`\`http
GET /memories/uuid-1?agent_id=my-agent HTTP/1.1
Host: localhost:8000
Authorization: Bearer mem0_your_api_key
\`\`\`

**响应**：
\`\`\`json
{
  "id": "uuid-1",
  "memory": "User name is John",
  "user_id": "user-123",
  "agent_id": "my-agent",
  "created_at": "2024-03-07T10:30:00Z",
  "updated_at": "2024-03-07T10:35:00Z"
}
\`\`\`

#### POST /search

搜索记忆。

**认证**：需要 API Key

**请求体**：
\`\`\`json
{
  "query": "What do you know about John?",
  "user_id": "user-123",
  "agent_id": "my-agent",
  "limit": 5,
  "filters": {
    "category": "personal"
  }
}
\`\`\`

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`query\` | string | 是 | 搜索查询 |
| \`user_id\` | string | 否 | 用户 ID |
| \`agent_id\` | string | 否 | 代理 ID |
| \`run_id\` | string | 否 | 运行 ID |
| \`limit\` | integer | 否 | 返回结果数（默认 10）|
| \`filters\` | object | 否 | 过滤条件 |

**响应**：
\`\`\`json
{
  "results": [
    {
      "id": "uuid-1",
      "memory": "User name is John",
      "score": 0.95,
      "user_id": "user-123",
      "agent_id": "my-agent"
    },
    {
      "id": "uuid-2",
      "memory": "User lives in San Francisco",
      "score": 0.87,
      "user_id": "user-123",
      "agent_id": "my-agent"
    }
  ],
  "relations": []
}
\`\`\`

#### PUT /memories/{memory_id}

更新记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 否 | 代理 ID（默认 "default"）|

**请求体**：
\`\`\`json
{
  "memory": "Updated memory content"
}
\`\`\`

或

\`\`\`json
{
  "data": "Updated memory content"
}
\`\`\`

**响应**：
\`\`\`json
{
  "id": "uuid-1",
  "memory": "Updated memory content",
  "event": "UPDATE"
}
\`\`\`

#### GET /memories/{memory_id}/history

获取记忆历史。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 否 | 代理 ID（默认 "default"）|

**响应**：
\`\`\`json
[
  {
    "memory_id": "uuid-1",
    "previous_value": null,
    "new_value": "User name is John",
    "event": "ADD",
    "actor_id": "user-123",
    "role": "user",
    "timestamp": "2024-03-07T10:30:00Z"
  },
  {
    "memory_id": "uuid-1",
    "previous_value": "User name is John",
    "new_value": "User name is John Doe",
    "event": "UPDATE",
    "actor_id": "user-123",
    "role": "user",
    "timestamp": "2024-03-07T10:35:00Z"
  }
]
\`\`\`

#### DELETE /memories/{memory_id}

删除单个记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 否 | 代理 ID（默认 "default"）|

**请求**：
\`\`\`http
DELETE /memories/uuid-1?agent_id=my-agent HTTP/1.1
Host: localhost:8000
Authorization: Bearer mem0_your_api_key
\`\`\`

**响应**：
\`\`\`json
{
  "message": "Memory deleted successfully"
}
\`\`\`

#### DELETE /memories

删除所有记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`user_id\` | string | 否* | 用户 ID |
| \`agent_id\` | string | 否* | 代理 ID |
| \`run_id\` | string | 否* | 运行 ID |

*至少需要一个参数。

**请求**：
\`\`\`http
DELETE /memories?user_id=user-123&agent_id=my-agent HTTP/1.1
Host: localhost:8000
Authorization: Bearer mem0_your_api_key
\`\`\`

**响应**：
\`\`\`json
{
  "message": "All relevant memories deleted"
}
\`\`\`

#### POST /reset

重置所有记忆。

**认证**：需要 API Key

**查询参数**：
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| \`agent_id\` | string | 否 | 代理 ID（默认 "default"）|

**响应**：
\`\`\`json
{
  "message": "All memories reset"
}
\`\`\`

#### POST /configure

配置 Mem0（不推荐在生产中使用）。

**认证**：需要 API Key

**请求体**：
\`\`\`json
{
  "vector_store": {
    "provider": "pgvector",
    "config": {
      "host": "postgres",
      "port": 5432
    }
  }
}
\`\`\`

**响应**：
\`\`\`json
{
  "message": "Configuration should be managed via environment variables"
}
\`\`\`

---

## 数据模型

### 4.1 Message

\`\`\`\`typescript
interface Message {
  role: string;      // "user" or "assistant"
  content: string;    // Message content
}
\`\`\`

### 4.2 MemoryItem

\`\`\`typescript
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
\`\`\`

### 4.3 AddResult

\`\`\`typescript
interface AddResult {
  results: Array<{
    id: string;
    memory: string;
    event: "ADD" | "UPDATE" | "DELETE" | "NOOP";
  }>;
  relations?: Array<{
    from: string;
    to: string;
    type: string;
  }>;
}
\`\`\`

### 4.4 SearchResponse

\`\`\`typescript
interface SearchResponse {
  results: MemoryItem[];
  relations?: Array<{
    from: string;
    to: string;
    type: string;
  }>;
}
\`\`\`

---

## 错误码

### 5.1 HTTP 状态码

| 状态码 | 含义 | 描述 |
|--------|------|------|
| **200 OK** | 成功 | 请求成功处理 |
| **400 Bad Request** | 请求错误 | 参数缺失或无效 |
| **401 Unauthorized** | 未认证 | 缺少 Authorization header |
| **403 Forbidden** | 禁止访问 | API Key 无效或速率超限 |
| **404 Not Found** | 资源不存在 | 记忆 ID 不存在 |
| **429 Too Many Requests** | 速率超限 | 超过速率限制 |

### 5.2 错误响应格式

\`\`\`json
{
  "detail": "Error message describing what went wrong"
}
\`\`\`

### 5.3 常见错误

| 错误 | HTTP 状态 | 说明 |
|------|-----------|------|
| "Missing Authorization header" | 401 | 请求缺少认证头 |
| "Invalid API key or rate limit exceeded" | 403 | API Key 无效或撤销 |
| "At least one identifier (user_id, agent_id, run_id) is required" | 400 | 缺少必需的标识符 |
| "API key not found" | 404 | API Key 不存在 |
| "Memory not found" | 404 | 记忆不存在 |

---

## 使用示例

### 6.1 cURL 示例

#### API Key 管理

\`\`\`bash
# 生成新的 API Key
curl -X POST http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" \\
  -H "Content-Type: application/json" \\
  -d '{
    "agent_id": "production-agent",
    "description": "Production API key"
  }'

# 列出所有 API Keys
curl -X GET http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key"

# 撤销指定的 API Key
curl -X DELETE http://localhost:8000/admin/keys \\
  -H "Authorization: Bearer your_admin_secret_key" \\
  -H "Content-Type: application/json" \\
  -d '{
    "api_key": "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
  }'
\`\`\`

#### 记忆操作

\`\`\`bash
# 添加记忆
curl -X POST http://localhost:8000/memories \\
  -H "Authorization: Bearer mem0_your_api_key" \\
  -H "Content-Type: application/json" \\
  -d '{
    "messages": [
      {"role": "user", "content": "My name is John and I live in San Francisco."}
    ],
    "user_id": "user-123",
    "agent_id": "my-agent"
  }'

# 搜索记忆
curl -X POST http://localhost:8000/search \\
  -H "Authorization: Bearer mem0_your_api_key \\
  -H "Content-Type: application/json" \\
  -d '{
    "query": "What do you know about John?",
    "user_id": "user-123",
    "limit": 5
  }'

# 获取所有记忆
curl -X GET "http://localhost:8000/memories?user_id=user-123&agent_id=my-agent" \\
  -H "Authorization: Bearer mem0_your_api_key"

# 更新记忆
curl -X PUT "http://localhost:8000/memories/uuid-1?agent_id=my-agent" \\
  -H "Authorization: Bearer mem0_your_key \\
  -H "Content-Type: application/json" \\
  -d '{
    "memory": "Updated memory content"
  }'

# 删除记忆
curl -X DELETE "http://localhost:8000/memories/uuid-1?agent_id=my-agent" \\
  -H "Authorization: Bearer mem0_your_api_key"

# 删除所有记忆
curl -X DELETE "http://localhost:8000/memories?user_id=user-123&agent_id=my-agent" \\
  -H "Authorization: Bearer mem0_your_api_key"

# 重置所有记忆
curl -X POST "http://localhost:8000/reset?agent_id=my-agent \\
  -H "Authorization: Bearer mem0_your_api_key"

# 健康检查
curl -X GET http://localhost:8000/health
\`\`\`

### 6.2 Python 示例

\`\`\`python
import requests

BASE_URL = "http://localhost:8000"
API_KEY = "mem0_your_api_key"
ADMIN_KEY = "your_admin_secret_key"

headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

admin_headers = {
    "X-API-Key": ADMIN_KEY,
    "Content-Type": "application/json"
}

# 生成新的 API Key
response = requests.post(
    f"{BASE_URL}/admin/keys",
    headers=admin_headers,
    json={
        "agent_id": "production-agent",
        "description": "Production API key"
    }
)
print("Generated API Key:", response.json()["api_key"])

# 列出所有 API Keys
response = requests.get(f"{BASE_URL}/admin/keys", headers=admin_headers)
print("API Keys:", response.json())

# 添加记忆
response = requests.post(
    f"{BASE_URL}/memories",
    headers=headers,
    json={
        "messages": [
            {"role": "user", "content": "My name is John"}
        ],
        "user_id": "user-123"
    }
)
print(response.json())

# 搜索记忆
response = requests.post(
    f"{BASE_URL}/search",
    headers=headers,
    json={
        "query": "What is my name?",
        "user_id": "user-123"
    }
)
print(response.json())

# 撤销 API Key
response = requests.delete(
    f"{BASE_URL}/admin/keys",
    headers=admin_headers,
    json={
        "api_key": "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    }
)
print(response.json())
\`\`\`

### 6.3 JavaScript 示例

\`\`\`javascript
const BASE_URL = "http://localhost:8000";
const API_KEY = "mem0_your_api_key";
const ADMIN_KEY = "your_admin_secret_key";

const headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
};

const adminHeaders = {
    "X-API-Key": ADMIN_KEY,
    "Content-Type": "application/json"
};

// 生成新的 API Key
fetch(\`\${BASE_URL}/admin/keys\`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({
        agent_id: "production-agent",
        description: "Production API key"
    })
}).then(r => r.json()).then(data => {
    console.log("Generated API Key:", data.api_key);
});

// 列出所有 API Keys
fetch(\`\${BASE_URL}/admin/keys\`, {
    method: "GET",
    headers: adminHeaders
}).then(r => r.json()).then(data => {
    console.log("API Keys:", data);
});

// 撤销 API Key
fetch(\`\${BASE_URL}/admin/keys\`, {
    method: "DELETE",
    headers: adminHeaders,
    body: JSON.stringify({
        api_key: "mem0_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    })
}).then(r => r.json()).then(data => {
    console.log("Revoked:", data.message);
});

// 添加记忆
fetch(\`\${BASE_URL}/memories\`, {
    method: "POST",
    headers,
    body: JSON.stringify({
        messages: [
            { role: "user", content: "My name is John" }
        ],
        user_id: "user-123"
    })
}).then(r => r.json()).then(console.log);

// 搜索记忆
fetch(\`\${BASE_URL}/search\`, {
    method: "POST",
    headers,
    body: JSON.stringify({
        query: "What is my name?",
        user_id: "user-123"
    })
}).then(r => r.json()).then(console.log);
\`\`\`

### 6.4 Shell 管理脚本

\`\`\`bash
#!/bin/bash
# API Key 管理脚本

BASE_URL="http://localhost:8000"
ADMIN_KEY="your_admin_secret_key"

# 显示菜单
echo "=== Mem0 API Key 管理 ==="
echo "1. 生成新的 API Key"
echo "2. 列出所有 API Keys"
echo "3. 撤销 API Key"
echo "4. 测试 API Key"
echo "5. 退出"
echo ""
read -p "请选择操作: " choice

case \$choice in
    1)
        echo -n "生成新的 API Key"
        read -p "输入 agent_id: " agent_id
        read -p "输入描述: " description
        curl -X POST "\$BASE_URL/admin/keys" \\
            -H "Authorization: Bearer \$ADMIN_KEY \\
            -H "Content-Type: application/json" \\
            -d "{\\"agent_id\\": \\"\$agent_id\\\", \\"description\\\": \\"\$description\\\" \\"}" \\
            | jq -r '.'
        ;;
    2)
        echo "列出所有 API Keys"
        curl -X GET "\$BASE_URL/admin/keys" \\
            -H "Authorization: Bearer \$ADMIN_KEY" | jq -r '.keys[] | "\\(.agent_id) - \\(.description) - \\(.key_prefix) (已撤销: \\(.revoked))"'
        ;;
    3)
        echo "撤销 API Key"
        # 列出所有 keys 供选择
        curl -s -X GET "\$BASE_URL/admin/keys" \\
            -H "Authorization: Bearer \$ADMIN_KEY" | jq -r '.keys[] | \\(.key_prefix) - \\(.agent_id)"' | nl
        read -p "输入要撤销的 key_prefix: " key_to_revoke
        
        # 构造完整 key（实际使用时需要保存完整 key）
        # 注意：这里需要用户从其他地方获取完整 key，因为 list 不返回完整 key
        read -p "输入完整 API Key 要撤销: " full_key_to_revoke
        
        curl -X DELETE "\$BASE_URL/admin/keys" \\
            -H "Authorization: Bearer \$ADMIN_KEY \\
            -H "Content-Type: application/json" \\
            -d "{\\"api_key\\": \\"\$full_key_to_revoke\\"" \\
            | jq -r '.message'
        ;;
    4)
        echo "测试 API Key"
        read -p "输入 API Key: " test_api_key
        echo "测试搜索..."
        curl -X POST "\$BASE_URL/search" \\
            -H "Authorization: Bearer \$test_api_key \\
            -H "Content-Type: application/json" \\
            -d "{\\"query\\": \\"test\\", \\"user_id\\\": \\"test\\" }" \\
            | jq -r '.results[] | .memory'
        ;;
    5)
        echo "退出"
        exit 0
        ;;
esac
\`\`\`

---

## 附录

### A. API Key 管理

| 操作 | 说明 | 端点 |
|------|------|------|
| **生成 Key** | 创建新的 API Key | \`POST /admin/keys\` |
| **列出 Key** | 查看所有 Keys（仅前缀）| \`GET /admin/keys\` |
| **撤销 Key** | 撤销指定的 Key | \`DELETE /admin/keys\` |
| **验证 Key** | 测试 Key 是否有效 | \`POST /search\` |

### B. 速率限制

当前配置：
- **窗口大小**：60 秒
- **请求限制**：200 请求

当超过限制时，响应状态码为 403。

### C. 分页

\`GET /memories\` 端点返回所有匹配的记忆。对于大量数据，建议使用过滤条件。

---

**文档结束**
