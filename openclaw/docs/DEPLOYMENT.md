# Mem0 Plugin 部署文档

## 版本信息

- **文档版本**: 2.0.0 (更新: 2026-03-07)
- **最后更新**: 2026-03-07
- **Plugin 版本**: v2.0.0

---

## 目录

1. [部署概述](#部署概述)
2. [快速开始](#快速开始)
3. [配置说明](#配置说明)
4. [不同模式部署](#不同模式部署)
5. [故障排查](#故障排查)

---

## 部署概述

### 1.1 支持的部署模式

| 模式 | 说明 | 部署要求 |
|------|------|----------|
| **Platform** | 使用 Mem0 云服务 | API Key、网络连接 |
| **Open-Source** | 本地自托管 | 向量数据库、LLM API |
| **Server** | 使用 Enhanced Server | Server URL、API Key |

### 1.2 前置要求

| 要求 | 版本 |
|------|------|
| Node.js | 18.x+ |
| OpenClaw Platform | Latest |
| Mem0 Server（Server 模式）| 2.0.0+ |

---

## 快速开始

### 2.1 安装 Plugin

#### 通过 OpenClaw CLI

```bash
# 添加 Plugin
openclaw plugin install openclaw-mem0

# 或从本地安装
openclaw plugin install ./openclaw
```

#### 手动安装

```bash
# 复制 Plugin 目录到 OpenClaw plugins 目录
cp -r openclaw ~/.openclaw/plugins/openclaw-mem0

# 或构建
cd openclaw
npm run build
```

### 2.2 基本配置

```json
{
  "mode": "platform",
  "apiKey": "m0-your-api-key",
  "userId": "default"
}
```

---

## 配置说明

### 3.1 配置参数

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| **mode** | 是 | "platform" | 运行模式："platform"、"open-source"、"server" |
| **userId** | 否 | "default" | 默认用户 ID |
| **autoCapture** | 否 | true | 自动捕获对话内容 |
| **autoRecall** | 否 | true | 自动回忆相关记忆 |
| **searchThreshold** | 否 | 0.5 | 搜索相似度阈值 (0-1) |
| **topK** | 否 | 5 | 返回的最大结果数 |

### 3.2 Platform 模式配置

```json
{
  "mode": "platform",
  "apiKey": "m0-your-api-key",
  "orgId": "org-xxx",
  "projectId": "proj-xxx",
  "userId": "user-123",
  "customInstructions": "Only store user preferences and important facts",
  "customCategories": {
    "projects": "Project-related information",
    "contacts": "Contact information"
  },
  "enableGraph": true,
  "searchThreshold": 0.6,
  "topK": 10
}
```

### 3.3 Server 模式配置

```json
{
  "mode": "server",
  "serverUrl": "http://YOUR_SERVER_IP:8000",
  "serverApiKey": "mem0_your_server_api_key",
  "agentId": "my-agent",
  "userId": "user-123",
  "searchThreshold": 0.5,
  "topK": 5
}
```

### 3.4 Open-Source 模式配置

```json
{
  "mode": "open-source",
  "userId": "user-123",
  "customPrompt": "Extract important facts from the conversation",
  "searchThreshold": 0.5,
  "topK": 5,
  "oss": {
    "vectorStore": {
      "provider": "pgvector",
      "config": {
        "host": "localhost",
        "port": 5432,
        "dbname": "mem0db",
        "user": "postgres",
        "password": "your-password",
        "collection_name": "memories"
      }
    },
    "llm": {
      "provider": "openai",
      "config": {
        "api_key": "sk-your-openai-key",
        "model": "gpt-4.1-nano-2025-04-14"
      }
    },
    "embedder": {
      "provider": "openai",
      "config": {
        "api_key": "sk-your-openai-key",
        "model": "text-embedding-3-small",
        "embedding_dims": 1536
      }
    },
    "historyDbPath": "./history/history.db"
  }
}
```

### 3.5 三层记忆配置

```json
{
  "mode": "server",
  "serverUrl": "http://YOUR_SERVER_IP:8000",
  "serverApiKey": "mem0_your_key",

  // L0 配置
  "l0Enabled": true,
  "l0Path": "./memory.md",

  // L1 配置
  "l1Enabled": true,
  "l1Dir": "./memory",
  "l1RecentDays": 7,
  "l1Categories": ["projects", "contacts", "tasks"],
  "l1AutoWrite": true,

  // 自动功能
  "autoCapture": true,
  "autoRecall": true
}
```

---

## 不同模式部署

### 4.1 Platform 模式部署

#### 4.1.1 获取 API Key

1. 访问 [app.mem0.ai](https://app.mem0.ai)
2. 注册/登录账号
3. 创建项目
4. 获取 API Key（格式：`m0-...`）

#### 4.1.2 配置

```json
{
  "mode": "platform",
  "apiKey": "m0-your-api-key",
  "userId": "your-user-id"
}
```

#### 4.1.3 验证

```bash
# 测试连接
openclaw mem0 search --query "test"

# 查看统计
openclaw mem0 stats
```

### 4.2 Server 模式部署

#### 4.2.1 启动 Server

参考 [Server 部署文档](../server/docs/DEPLOYMENT.md)

#### 4.2.2 创建 API Key

```bash
# 使用 ADMIN_SECRET_KEY 创建
curl -X POST http://localhost:8000/admin/keys \
  -H "X-API-Key: npl_2008" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "test",
    "description": "Plugin API Key"
  }'

# 响应：
# {
#   "api_key": "mem0_xxx...",
#   "agent_id": "my-agent"
# }
```

#### 4.2.3 配置 Plugin

```json
{
  "mode": "server",
  "serverUrl": "http://YOUR_SERVER_IP:8000",
  "serverApiKey": "mem0_xxx...",
  "agentId": "my-agent"
}
```

### 4.3 Open-Source 模式部署

#### 4.3.1 安装依赖

```bash
# 安装 Mem0 SDK
npm install mem0ai

# 或使用 Python
pip install mem0ai
```

#### 4.3.2 配置向量数据库

参考 Mem0 文档配置：
- PostgreSQL + pgvector
- Qdrant
- Chroma
- Pinecone
- Weaviate

#### 4.3.3 配置 LLM

支持多种 LLM 提供商：
- OpenAI
- Anthropic
- Groq
- Together AI
- Ollama
- Gemini
- Azure OpenAI

---

## 故障排查

### 5.1 常见问题

#### 问题 1：Plugin 加载失败

**症状**：
```
Error: Failed to load plugin openclaw-mem0
```

**解决方案**：
```bash
# 检查 Plugin 结构
ls -la ~/.openclaw/plugins/openclaw-mem0

# 确保包含 openclaw.plugin.json
cat ~/.openclaw/plugins/openclaw-mem0/openclaw.plugin.json

# 重新安装
openclaw plugin uninstall openclaw-mem0
openclaw plugin install ./openclaw
```

#### 问题 2：Platform API 连接失败

**症状**：
```
Error: Failed to connect to Mem0 Platform
```

**解决方案**：
```bash
# 检查 API Key
echo $MEM0_API_KEY

# 测试连接
curl -H "Authorization: Token m0-your-api-key" \
  https://api.mem0.ai/v1/memories

# 检查网络连接
ping api.mem0.ai
```

#### 问题 3：Server 模式连接失败

**症状**：
```
Error: Failed to connect to Mem0 Server
```

**解决方案**：
```bash
# 检查 Server 是否运行
curl http://localhost:8000/health
# 或从外部访问: curl http://YOUR_SERVER_IP:8000/health

# 检查 API Key
openclaw mem0 search --query "test"

# 检查网络配置
curl -H "X-API-Key: mem0_your_key" \
  http://localhost:8000/health
```

#### 问题 4：Open-Source 模式配置错误

**症状**：
```
Error: Invalid vector store configuration
```

**解决方案**：
```bash
# 验证 PostgreSQL 连接
psql -h localhost -U postgres -d mem0db

# 检查 pgvector 扩展
psql -U postgres -d mem0db -c "\dx"

# 验证向量表
psql -U postgres -d mem0db -c "\d memories"
```

#### 问题 5：L0/L1 文件权限错误

**症状**：
```
Error: Failed to write to memory file
```

**解决方案**：
```bash
# 检查文件权限
ls -la ./memory.md
ls -la ./memory/

# 修复权限
chmod 644 ./memory.md
chmod 755 ./memory/

# 或更改所有权
sudo chown -R $USER:$USER ./memory.md
sudo chown -R $USER:$USER ./memory/
```

### 5.2 调试模式

```bash
# 启用详细日志
export DEBUG=1
export LOG_LEVEL=debug

# 运行 OpenClaw
openclaw agent
```

### 5.3 性能优化

#### L0/L1 层优化

```json
{
  "l0Enabled": true,
  "l1RecentDays": 3,  // 减少加载的文件数
  "l1AutoWrite": false  // 禁用自动写入以提高性能
}
```

#### 搜索优化

```json
{
  "searchThreshold": 0.7,  // 提高阈值减少结果
  "topK": 3  // 减少返回结果数
}
```

---

## 附录

### A. 配置文件位置

| 系统 | 配置目录 |
|------|----------|
| **Linux/macOS** | `~/.openclaw/plugins/openclaw-mem0/config.json` |
| **Windows** | `%APPDATA%\OpenClaw\plugins\openclaw-mem0\config.json` |

### B. 环境变量

| 变量 | 说明 |
|------|------|
| `MEM0_API_KEY` | Platform 模式的 API Key |
| `MEM0_MODE` | 默认模式（platform/server/open-source）|
| `MEM0_USER_ID` | 默认用户 ID |
| `MEM0_SERVER_URL` | Server 模式的 URL |
| `MEM0_SERVER_API_KEY` | Server 模式的 API Key |

### C. 日志位置

| 日志 | 位置 |
|------|------|
| **Plugin 日志** | `~/.openclaw/logs/openclaw-mem0.log` |
| **L0 文件** | `./memory.md` |
| **L1 文件** | `./memory/` |

---
 已成功打包 Mem0 Plugin，生成了以下文件：

  📦 打包文件

  ┌───────────────────────────────────┬────────┬──────┬─────────────────┐
  │               文件                │  格式  │ 大小 │      用途       │
  ├───────────────────────────────────┼────────┼──────┼─────────────────┤
  │ mem0-openclaw-mem0-2.0.0.tgz      │ npm 包 │ 30K  │ 标准 npm 包格式 │
  ├───────────────────────────────────┼────────┼──────┼─────────────────┤
  │ openclaw-mem0-plugin-2.0.0.tar.gz │ tar.gz │ 30K  │ 传统源码打包    │
  └───────────────────────────────────┴────────┴──────┴─────────────────┘

  📄 安装说明

  - INSTALL.md - 包含详细的安装指南、配置说明和故障排查

  📁 打包位置

  /home/yhz/project/mem0/dist/
  ├── mem0-openclaw-mem0-2.0.0.tgz
  ├── openclaw-mem0-plugin-2.0.0.tar.gz
  └── INSTALL.md

---
  🚀 快速安装

  方式一：npm 包安装

  npm install /path/to/mem0-openclaw-mem0-2.0.0.tgz

  方式二：源码安装

  # 解压
  tar -xzf openclaw-mem0-plugin-2.0.0.tar.gz

  # 安装到 OpenClaw
  openclaw plugin install ./openclaw

  方式三：直接复制

  cp -r openclaw ~/.openclaw/plugins/openclaw-mem0

---
  ⚙️  快速配置

  Platform 模式

  openclaw config set mem0.mode platform
  openclaw config set mem0.apiKey m0-your-api-key

  Server 模式

  openclaw config set mem0.mode server
  openclaw config set mem0.serverUrl http://localhost:8000
  openclaw config set mem0.serverApiKey mem0_your_key

---
  打包包含完整的源码、文档和配置文件，可以直接使用！

**文档结束**
