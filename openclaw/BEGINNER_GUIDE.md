# Mem0 Plugin 完整安装配置教程（零基础版）

## 目录

1. [简介](#1-简介)
2. [前置条件](#2-前置条件)
3. [安装方式选择](#3-安装方式选择)
4. [方式一：从打包文件安装（推荐）](#4-方式一从打包文件安装推荐)
5. [方式二：从源码构建安装](#5-方式二从源码构建安装)
6. [方式三：使用 Server 模式（生产推荐）](#6-方式三使用-server-模式生产推荐)
7. [配置详解](#7-配置详解)
8. [验证安装](#8-验证安装)
9. [使用指南](#9-使用指南)
10. [常见问题](#10-常见问题)
11. [进阶配置](#11-进阶配置)

---

## 1. 简介

### 1.1 什么是 Mem0 Plugin？

Mem0 Plugin 是一个为 OpenClaw 提供长期记忆功能的插件。它能让你的 AI 助手记住用户的偏好、习惯和历史对话，提供更个性化的服务。

### 1.2 主要功能

- **三层记忆架构**：L0（快速访问）+ L1（结构化存储）+ L2（语义搜索）
- **自动记忆**：自动捕获和存储对话中的关键信息
- **智能回忆**：根据当前对话自动检索相关记忆
- **多模式支持**：Platform（云端）、Open-Source（自托管）、Server（生产环境）

### 1.3 工作原理图

```
用户对话 → Plugin 自动捕获 → 存储到三层记忆
    ↓                              ↓
用户提问 → Plugin 自动回忆 → 检索相关记忆 → 增强回答
```

---

## 2. 前置条件

### 2.1 系统要求

| 要求 | 最低配置 | 推荐配置 |
|------|----------|----------|
| **操作系统** | Linux / macOS / Windows | Linux (Ubuntu 20.04+) |
| **内存** | 4 GB | 8 GB+ |
| **硬盘** | 10 GB 可用空间 | 50 GB+ SSD |
| **CPU** | 2 核心 | 4+ 核心 |

### 2.2 软件要求

| 软件 | 版本 | 检查命令 | 安装方式 |
|------|------|----------|----------|
| **Node.js** | v18.0.0+ | `node --version` | [官网下载](https://nodejs.org/) |
| **npm** | v9.0.0+ | `npm --version` | 随 Node.js 安装 |
| **OpenClaw** | 最新版 | `openclaw --version` | [官网](https://openclaw.ai/) |
| **Git** | 任意版本 | `git --version` | `apt install git` |

### 2.3 检查环境

打开终端，依次运行以下命令：

```bash
# 1. 检查 Node.js
node --version
# 预期输出: v18.x.x 或更高
# 如果显示 "command not found"，请先安装 Node.js

# 2. 检查 npm
npm --version
# 预期输出: 9.x.x 或更高

# 3. 检查 OpenClaw
openclaw --version
# 预期输出: openclaw/x.x.x
# 如果显示 "command not found"，请先安装 OpenClaw

# 4. 检查 Git
git --version
# 预期输出: git version 2.x.x
```

### 2.4 如果缺少某个软件

#### 安装 Node.js (Linux/macOS)

```bash
# 方法 1: 使用 nvm（推荐）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18

# 方法 2: 使用包管理器
# Ubuntu/Debian:
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# macOS (使用 Homebrew):
brew install node@18
```

#### 安装 Node.js (Windows)

1. 访问 https://nodejs.org/
2. 下载 LTS 版本（长期支持版）
3. 双击安装包，按照向导安装
4. 打开 PowerShell，运行 `node --version` 验证

---

## 3. 安装方式选择

根据你的使用场景，选择合适的安装方式：

| 方式 | 适用场景 | 难度 | 推荐指数 |
|------|----------|------|----------|
| **方式一** | 快速体验、测试 | ⭐ | ⭐⭐⭐⭐⭐ |
| **方式二** | 开发、调试、学习 | ⭐⭐ | ⭐⭐⭐ |
| **方式三** | 生产环境、团队使用 | ⭐⭐⭐ | ⭐⭐⭐⭐ |

### 3.1 功能对比

| 功能 | 方式一 | 方式二 | 方式三 |
|------|--------|--------|--------|
| Platform 模式 | ✅ | ✅ | ✅ |
| Open-Source 模式 | ✅ | ✅ | ✅ |
| Server 模式 | ✅ | ✅ | ✅ |
| 三层记忆 | ✅ | ✅ | ✅ |
| 自动更新 | ❌ | ✅ | ✅ |
| 多 Agent 隔离 | ❌ | ❌ | ✅ |
| 速率限制 | ❌ | ❌ | ✅ |

---

## 4. 方式一：从打包文件安装（推荐）

### 4.1 准备工作

#### 4.1.1 获取 Plugin 包文件

**方法 A: 从本地获取**
```bash
# 假设你已经有打包好的文件
ls mem0-openclaw-mem0-2.0.0.tgz
```

**方法 B: 从 Git 获取并打包**
```bash
# 1. 克隆仓库
git clone https://github.com/mem0ai/mem0.git
cd mem0/openclaw

# 2. 安装依赖
npm install

# 3. 打包
npm pack

# 4. 确认包已生成
ls mem0-openclaw-mem0-2.0.0.tgz
```

#### 4.1.2 验证包文件完整性

```bash
# 1. 检查文件大小（应该在 50-70 KB 左右）
ls -lh mem0-openclaw-mem0-2.0.0.tgz
# 输出示例: -rw-r--r-- 1 user user 62K Mar  7 10:00 mem0-openclaw-mem0-2.0.0.tgz

# 2. 检查文件数量（应该有 23 个文件）
tar -tzf mem0-openclaw-mem0-2.0.0.tgz | wc -l
# 输出: 23

# 3. 查看包内容（可选）
tar -tzf mem0-openclaw-mem0-2.0.0.tgz | head -10
```

### 4.2 安装 Plugin

#### 4.2.1 使用 OpenClaw CLI 安装

```bash
# 确保在包文件所在目录
cd /path/to/mem0/openclaw

# 安装 Plugin
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz

# 预期输出:
# Installing plugin from ./mem0-openclaw-mem0-2.0.0.tgz...
# ✓ Plugin installed successfully: @mem0/openclaw-mem0@2.0.0
```

#### 4.2.2 如果安装失败

**错误 1**: `openclaw: command not found`
```bash
# 原因: OpenClaw 未安装或不在 PATH 中
# 解决: 先安装 OpenClaw 或使用完整路径
/path/to/openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz
```

**错误 2**: `Permission denied`
```bash
# 原因: 权限不足
# 解决: 使用 sudo 或修复权限
sudo openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz
```

**错误 3**: `Plugin already exists`
```bash
# 原因: 已安装过同版本
# 解决: 先卸载再安装
openclaw plugins uninstall @mem0/openclaw-mem0
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz
```

### 4.3 验证安装

```bash
# 1. 查看已安装的插件列表
openclaw plugins list

# 预期输出:
# Plugin                     Version    Status
# @mem0/openclaw-mem0       2.0.0      installed

# 2. 查看插件详情
openclaw plugins show @mem0/openclaw-mem0

# 预期输出:
# Name: @mem0/openclaw-mem0
# Version: 2.0.0
# Status: installed
# Path: ~/.openclaw/plugins/@mem0/openclaw-mem0
```

### 4.4 初始配置

创建 OpenClaw 配置文件（如果还没有）：

```bash
# 1. 创建配置目录
mkdir -p ~/.openclaw

# 2. 创建配置文件
nano ~/.openclaw/openclaw.json
```

复制以下内容到配置文件：

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "open-source",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true
      }
    }
  }
}
```

保存并退出（Ctrl+O, Enter, Ctrl+X）。

### 4.5 测试 Plugin

```bash
# 1. 重启 OpenClaw
openclaw restart

# 2. 测试记忆存储
openclaw mem0 store "User prefers dark mode"

# 3. 测试记忆搜索
openclaw mem0 search "preferences"

# 4. 查看统计
openclaw mem0 stats
```

---

## 5. 方式二：从源码构建安装

### 5.1 获取源码

```bash
# 方法 A: 从 Git 克隆
git clone https://github.com/mem0ai/mem0.git
cd mem0/openclaw

# 方法 B: 从 Fork 克隆（如果你有 Fork）
git clone https://github.com/YOUR_USERNAME/mem0.git
cd mem0/openclaw
```

### 5.2 安装依赖

```bash
# 安装所有依赖
npm install

# 预期输出:
# added 430 packages in 2m
```

### 5.3 运行测试

```bash
# 运行测试套件
npm run test

# 预期输出:
# Total Tests: 38
# Passed: 38 (100%)
# Failed: 0
```

### 5.4 类型检查

```bash
# 运行 TypeScript 类型检查
npm run typecheck

# 如果有错误，通常是预期的（缺少 openclaw/plugin-sdk）
```

### 5.5 配置 OpenClaw 使用本地代码

编辑 OpenClaw 配置文件：

```bash
nano ~/.openclaw/openclaw.json
```

添加以下内容：

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "path": "/home/yourusername/mem0/openclaw",  // 改成你的实际路径
      "config": {
        "mode": "open-source",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true
      }
    }
  }
}
```

### 5.6 开发时热重载

```bash
# 方法 1: 使用 nodemon 监听文件变化
npm install -g nodemon
nodemon --watch . --ext ts --exec "openclaw restart"

# 方法 2: 手动重启
# 修改代码后
openclaw restart
```

---

## 6. 方式三：使用 Server 模式（生产推荐）

### 6.1 为什么选择 Server 模式？

| 优势 | 说明 |
|------|------|
| **多 Agent 隔离** | 不同 Agent 的记忆完全隔离 |
| **速率限制** | 防止过度使用 |
| **认证** | API Key 认证保证安全 |
| **集中管理** | 所有 Agent 共享同一个 Server |
| **持久化** | PostgreSQL + pgvector 持久化存储 |

### 6.2 Server 端部署

#### 6.2.1 准备服务器

```bash
# 1. 安装 Docker 和 Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# 重新登录使生效

# 2. 验证安装
docker --version
docker compose version
```

#### 6.2.2 获取 Server 代码

```bash
# 克隆仓库
git clone https://github.com/mem0ai/mem0.git
cd mem0/server
```

#### 6.2.3 配置环境变量

```bash
# 1. 复制模板
cp .env.example .env

# 2. 编辑配置
nano .env
```

修改以下关键配置：

```bash
# PostgreSQL 配置
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=mem0db
POSTGRES_USER=mem0user
POSTGRES_PASSWORD=your_secure_password_here

# Neo4j 配置（可选，用于关系图）
NEO4J_URI=bolt://neo4j:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your_secure_password_here

# OpenAI API 配置（必需）
OPENAI_API_KEY=sk-your-openai-api-key-here
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4o
OPENAI_EMBEDDING_MODEL=text-embedding-3-small

# Redis 配置
REDIS_URL=redis://redis:6379/0
REDIS_PASSWORD=your_redis_password_here

# 管理员密钥（用于创建 API Key）
ADMIN_SECRET_KEY=your_admin_secret_key_here
```

#### 6.2.4 创建数据目录

```bash
# 创建数据目录
sudo mkdir -p /opt/mem0-data/{postgres,neo4j/data,neo4j/logs,neo4j/import,redis,history}

# 设置权限
sudo chown -R 1000:1000 /opt/mem0-data/
```

#### 6.2.5 启动服务

```bash
# 启动所有服务
docker compose -f docker-compose.prod.yaml up -d

# 查看日志
docker compose -f docker-compose.prod.yaml logs -f

# 按 Ctrl+C 退出日志查看
```

#### 6.2.6 验证服务

```bash
# 等待服务启动（约 30-60 秒）
sleep 30

# 检查服务状态
docker compose -f docker-compose.prod.yaml ps

# 预期输出:
# NAME              STATUS    PORTS
# mem0-postgres     running   0.0.0.0:5432->5432/tcp
# mem0-neo4j        running   0.0.0.0:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
# mem0-redis        running   0.0.0.0:6379->6379/tcp
# mem0-server       running   127.0.0.1:8000->8000/tcp

# 检查健康状态
curl http://localhost:8000/health

# 预期输出:
# {"status":"healthy","loaded_agents":0,"redis":"ok"}
```

### 6.3 创建 API Key

#### 6.3.1 创建 Agent API Key

```bash
# 使用管理员密钥创建 API Key
curl -X POST http://localhost:8000/admin/keys \
  -H "Content-Type: application/json" \
  -H "X-API-Key: npl_2008" \
  -d '{
    "agent_id": "openclaw-main",
    "description": "OpenClaw 主 Agent"
  }'

# 预期输出:
# {
#   "api_key": "mem0_OEeZGiN0DahJKbixyE3lPjT6yn1AZgAhn4lyar4xJno",
#   "agent_id": "openclaw-main",
#   "description": "OpenClaw 主 Agent",
#   "created_at": "2026-03-07T10:00:00Z"
# }
```

#### 6.3.2 保存 API Key

```bash
# 保存到环境变量
export MEM0_SERVER_API_KEY="mem0_OEeZGiN0DahJKbixyE3lPjT6yn1AZgAhn4lyar4xJno"

# 添加到 shell 配置文件（永久保存）
echo 'export MEM0_SERVER_API_KEY="mem0_OEeZGiN0DahJKbixyE3lPjT6yn1AZgAhn4lyar4xJno"' >> ~/.bashrc
source ~/.bashrc
```

### 6.4 配置 Plugin 使用 Server 模式

编辑 OpenClaw 配置文件：

```bash
nano ~/.openclaw/openclaw.json
```

添加以下内容：

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "openclaw-main",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true,
        "topK": 5,
        "searchThreshold": 0.3,
        "l0Enabled": true,
        "l0Path": "memory.md",
        "l1Enabled": true,
        "l1Dir": "memory",
        "l1RecentDays": 7,
        "l1Categories": ["projects", "contacts", "tasks"],
        "l1AutoWrite": true
      }
    }
  }
}
```

### 6.5 测试 Server 模式

```bash
# 1. 重启 OpenClaw
openclaw restart

# 2. 测试记忆存储
openclaw mem0 store "User's favorite color is blue"

# 3. 测试记忆搜索
openclaw mem0 search "color"

# 4. 直接测试 Server API
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $MEM0_SERVER_API_KEY" \
  -d '{"query":"color","user_id":"default","limit":5}'
```

---

## 7. 配置详解

### 7.1 配置文件位置

| 平台 | 位置 |
|------|------|
| **Linux/macOS** | `~/.openclaw/openclaw.json` |
| **Windows** | `C:\Users\YourName\.openclaw\openclaw.json` |

### 7.2 配置结构说明

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,              // 是否启用插件
      "config": {
        // 核心配置
        "mode": "server",            // 运行模式
        "userId": "default",         // 用户标识
        "autoRecall": true,          // 自动回忆
        "autoCapture": true,         // 自动捕获

        // Server 模式配置
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "openclaw-main",

        // 性能配置
        "topK": 5,                   // 检索数量
        "searchThreshold": 0.3,      // 搜索阈值

        // L0 配置
        "l0Enabled": true,
        "l0Path": "memory.md",

        // L1 配置
        "l1Enabled": true,
        "l1Dir": "memory",
        "l1RecentDays": 7,
        "l1Categories": ["projects", "contacts", "tasks"],
        "l1AutoWrite": true
      }
    }
  }
}
```

### 7.3 配置参数详解

#### 7.3.1 核心参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mode` | string | `"platform"` | 运行模式：`"platform"`、`"open-source"`、`"server"` |
| `userId` | string | `"default"` | 用户标识，用于隔离不同用户的记忆 |
| `autoRecall` | boolean | `true` | 是否在对话前自动检索相关记忆 |
| `autoCapture` | boolean | `true` | 是否在对话后自动存储关键信息 |

#### 7.3.2 性能参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `topK` | number | `5` | 每次检索返回的最大记忆数量 |
| `searchThreshold` | number | `0.3` | 搜索相似度阈值（0-1），越大越严格 |

#### 7.3.3 Server 模式参数

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `serverUrl` | string | ✅ | Server 地址 |
| `serverApiKey` | string | ✅ | API Key |
| `agentId` | string | ❌ | Agent 标识，默认 `"openclaw-default"` |

#### 7.3.4 L0 层参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `l0Enabled` | boolean | `false` | 是否启用 L0 层 |
| `l0Path` | string | `"memory.md"` | L0 文件路径 |

#### 7.3.5 L1 层参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `l1Enabled` | boolean | `false` | 是否启用 L1 层 |
| `l1Dir` | string | `"memory"` | L1 目录路径 |
| `l1RecentDays` | number | `7` | 加载最近 N 天的日期文件 |
| `l1Categories` | string[] | `["projects","contacts","tasks"]` | 分类文件名 |
| `l1AutoWrite` | boolean | `false` | 是否自动写入对话摘要 |

### 7.4 三种运行模式配置示例

#### 7.4.1 Platform 模式（Mem0 Cloud）

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "platform",
        "apiKey": "${MEM0_API_KEY}",
        "userId": "user-123",
        "orgId": "org-456",              // 可选
        "projectId": "proj-789",         // 可选
        "enableGraph": false,            // 是否启用关系图
        "customInstructions": "只存储用户偏好和重要事实",
        "autoRecall": true,
        "autoCapture": true,
        "topK": 5,
        "searchThreshold": 0.3
      }
    }
  }
}
```

**获取 API Key**:
1. 访问 https://app.mem0.ai
2. 注册/登录账号
3. 进入 Settings → API Keys
4. 点击 "Create New Key"
5. 复制 Key 并保存到环境变量

```bash
export MEM0_API_KEY="m0-xxxxxxxxxxxxxxxx"
```

#### 7.4.2 Open-Source 模式（自托管）

**基础配置**:
```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "open-source",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true,
        "topK": 5,
        "searchThreshold": 0.3
      }
    }
  }
}
```

**高级配置（自定义组件）**:
```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "open-source",
        "userId": "default",
        "oss": {
          "embedder": {
            "provider": "openai",
            "config": {
              "apiKey": "${OPENAI_API_KEY}",
              "model": "text-embedding-3-small"
            }
          },
          "vectorStore": {
            "provider": "qdrant",
            "config": {
              "host": "localhost",
              "port": 6333,
              "collectionName": "memories"
            }
          },
          "llm": {
            "provider": "openai",
            "config": {
              "apiKey": "${OPENAI_API_KEY}",
              "model": "gpt-4o"
            }
          },
          "historyDbPath": "/path/to/history.db"
        }
      }
    }
  }
}
```

#### 7.4.3 Server 模式（推荐）

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "openclaw-main",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true,
        "topK": 5,
        "searchThreshold": 0.3,
        "l0Enabled": true,
        "l0Path": "memory.md",
        "l1Enabled": true,
        "l1Dir": "memory",
        "l1RecentDays": 7,
        "l1Categories": ["projects", "contacts", "tasks"],
        "l1AutoWrite": true
      }
    }
  }
}
```

### 7.5 三层记忆配置

#### 7.5.1 L0 层：持久记忆

**启用 L0**:
```json5
{
  "l0Enabled": true,
  "l0Path": "memory.md"
}
```

**L0 文件示例** (`memory.md`):
```markdown
# Memory

> This file contains important facts and information about you.
> It is automatically maintained by the memory system.

- User name is John
- Email is john@example.com
- Timezone is UTC+8
- Primary language is English
- Prefers Python over JavaScript
- Works as a software engineer
```

**手动编辑 L0**:
```bash
# 使用文本编辑器编辑
nano memory.md

# 或使用 CLI
openclaw mem0 l0 update --append "User's favorite editor is VS Code"
```

#### 7.5.2 L1 层：结构化记忆

**启用 L1**:
```json5
{
  "l1Enabled": true,
  "l1Dir": "memory",
  "l1RecentDays": 7,
  "l1Categories": ["projects", "contacts", "tasks"],
  "l1AutoWrite": true
}
```

**L1 目录结构**:
```
memory/
├── 2026-03-07.md        # 今日对话
├── 2026-03-06.md        # 昨日对话
├── 2026-03-05.md        # 前日对话
├── projects.md            # 项目信息
├── contacts.md            # 联系人信息
└── tasks.md              # 任务列表
```

**日期文件示例** (`2026-03-07.md`):
```markdown
# 2026-03-07 对话摘要

## 上午
- 讨论了新项目的技术选型
- 决定使用 React + TypeScript

## 下午
- 修复了登录页面的 Bug
- 添加了记住密码功能
```

**分类文件示例** (`projects.md`):
```markdown
# Projects

## Project A
- 技术栈: React, Node.js, PostgreSQL
- 状态: 进行中
- 负责人: John

## Project B
- 技术栈: Vue, Python, MongoDB
- 状态: 规划中
```

#### 7.5.3 L2 层：语义搜索

L2 层通过 Server/Platform/OSS 自动启用，无需额外配置。

---

## 8. 验证安装

### 8.1 检查 Plugin 状态

```bash
# 1. 查看 Plugin 列表
openclaw plugins list

# 预期输出:
# Plugin                     Version    Status
# @mem0/openclaw-mem0       2.0.0      enabled

# 2. 查看 Plugin 详情
openclaw plugins show @mem0/openclaw-mem0

# 预期输出:
# Name: @mem0/openclaw-mem0
# Version: 2.0.0
# Status: enabled
# Config:
#   mode: server
#   userId: default
#   ...
```

### 8.2 测试基础功能

```bash
# 1. 测试记忆存储
openclaw mem0 store "User prefers dark mode in all applications"

# 预期输出:
# ✓ Memory stored successfully
# ID: mem_abc123...

# 2. 测试记忆搜索
openclaw mem0 search "preferences"

# 预期输出:
# Found 1 memory:
# - User prefers dark mode in all applications (score: 0.85)

# 3. 查看统计
openclaw mem0 stats

# 预期输出:
# Total memories: 1
# L0 enabled: true
# L1 enabled: true
```

### 8.3 测试三层记忆

```bash
# 1. 测试 L0
cat memory.md

# 预期看到:
# - User prefers dark mode in all applications

# 2. 测试 L1
ls -la memory/

# 预期看到:
# drwxr-xr-x  memory/
# -rw-r--r--  2026-03-07.md
# -rw-r--r--  projects.md

# 3. 测试 L2 (Server 模式)
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $MEM0_SERVER_API_KEY" \
  -d '{"query":"preferences","user_id":"default","limit":5}'

# 预期输出:
# {"results":[{"id":"mem_abc123","memory":"User prefers dark mode...","score":0.85}]}
```

### 8.4 完整测试套件

```bash
# 运行完整测试
cd /home/yhz/project/mem0/openclaw
SERVER_API_KEY="$MEM0_SERVER_API_KEY" npx tsx test_plugin.ts

# 预期输出:
# Total Tests: 17
# Passed: 17 (100%)
# Failed: 0
```

---

## 9. 使用指南

### 9.1 CLI 命令

#### 9.1.1 记忆存储

```bash
# 存储单条记忆
openclaw mem0 store "User's birthday is January 15th"

# 存储多条记忆
openclaw mem0 store "User speaks English and Spanish"
openclaw mem0 store "User works remotely"
```

#### 9.1.2 记忆搜索

```bash
# 基础搜索
openclaw mem0 search "birthday"

# 指定结果数量
openclaw mem0 search "work" --limit 10

# 指定范围
openclaw mem0 search "preferences" --scope long-term
```

#### 9.1.3 记忆列表

```bash
# 列出所有记忆
openclaw mem0 list

# 列出特定用户的记忆
openclaw mem0 list --user-id user-123

# 列出特定 Agent 的记忆
openclaw mem0 list --agent-id agent-456
```

#### 9.1.4 L0/L1 操作

```bash
# L0 操作
openclaw mem0 l0 update --append "New fact"
openclaw mem0 l0 update --replace  # 替换整个文件

# L1 操作
openclaw mem0 l1 write --date  # 写入今日日期文件
openclaw mem0 l1 write --category projects  # 写入分类文件
```

### 9.2 在对话中使用

#### 9.2.1 自动回忆

当 `autoRecall: true` 时，每次对话开始前，Plugin 会自动：

1. 读取 L0 memory.md
2. 读取 L1 最近的日期/分类文件
3. 搜索 L2 相关记忆
4. 将记忆注入到系统提示中

**示例对话**:
```
用户: What's my favorite color?
AI: Based on your preferences, your favorite color is blue.
```

#### 9.2.2 自动捕获

当 `autoCapture: true` 时，每次对话结束后，Plugin 会自动：

1. 分析对话内容
2. 提取关键事实
3. 存储到 L2（并可选写入 L1）

**示例**:
```
用户: I just got a new job at Google!
AI: Congratulations! That's great news.
[后台自动存储: "User works at Google"]
```

### 9.3 三层记忆协同工作

```
用户提问: "Tell me about my projects"
    ↓
L0: 读取 memory.md → "User is software engineer"
    ↓
L1: 读取 projects.md → 项目列表
    ↓
L2: 语义搜索 → 相关项目讨论
    ↓
合并三层信息 → 生成回答
```

---

## 10. 常见问题

### 10.1 安装问题

#### Q1: Plugin 无法加载

**症状**:
```
Error: Plugin @mem0/openclaw-mem0 not found
```

**解决方案**:
```bash
# 1. 检查 Plugin 是否安装
openclaw plugins list

# 2. 检查 Plugin 目录
ls -la ~/.openclaw/plugins/

# 3. 重新安装
openclaw plugins uninstall @mem0/openclaw-mem0
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz

# 4. 检查配置文件
cat ~/.openclaw/openclaw.json
```

#### Q2: TypeScript 编译错误

**症状**:
```
Error: Cannot find module 'openclaw/plugin-sdk'
```

**解决方案**:
```bash
# 这是预期的警告，不影响运行
# openclaw/plugin-sdk 由 OpenClaw 运行时提供

# 如果使用源码模式，可以忽略此错误
# 确保配置中 "path" 指向正确的目录
```

#### Q3: 依赖安装失败

**症状**:
```
npm ERR! EACCES permission denied
```

**解决方案**:
```bash
# 方法 1: 使用 sudo
sudo npm install

# 方法 2: 修复 npm 权限
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 方法 3: 使用 nvm
nvm install 18
nvm use 18
```

### 10.2 配置问题

#### Q4: 配置文件格式错误

**症状**:
```
Error: Invalid JSON in configuration file
```

**解决方案**:
```bash
# 1. 验证 JSON 格式
cat ~/.openclaw/openclaw.json | python3 -m json.tool

# 2. 使用在线工具验证
# 复制配置到 https://jsonlint.com/

# 3. 常见错误:
# - 多余的逗号
# - 缺少引号
# - 使用了单引号而不是双引号
```

#### Q5: 环境变量未生效

**症状**:
```
Error: API key is required
```

**解决方案**:
```bash
# 1. 检查环境变量
echo $MEM0_SERVER_API_KEY

# 2. 如果为空，设置环境变量
export MEM0_SERVER_API_KEY="your-key-here"

# 3. 添加到配置文件（永久）
echo 'export MEM0_SERVER_API_KEY="your-key-here"' >> ~/.bashrc
source ~/.bashrc

# 4. 或在配置中使用实际值（不推荐）
# "serverApiKey": "mem0_xxx"  # 直接写值
```

### 10.3 运行问题

#### Q6: Server 连接失败

**症状**:
```
Error: connect ECONNREFUSED 127.0.0.1:8000
```

**解决方案**:
```bash
# 1. 检查 Server 是否运行
docker compose -f docker-compose.prod.yaml ps

# 2. 查看 Server 日志
docker compose -f docker-compose.prod.yaml logs mem0-server

# 3. 检查端口占用
netstat -tlnp | grep 8000

# 4. 重启 Server
docker compose -f docker-compose.prod.yaml restart mem0-server
```

#### Q7: 记忆搜索无结果

**症状**:
```bash
openclaw mem0 search "test"
# Found 0 memories
```

**解决方案**:
```bash
# 1. 检查是否有记忆
openclaw mem0 list

# 2. 降低搜索阈值
# 在配置中设置:
# "searchThreshold": 0.1

# 3. 等待索引完成（新记忆需要时间）
sleep 5
openclaw mem0 search "test" --threshold 0.1

# 4. 检查 userId 是否匹配
# 确保搜索和存储使用相同的 userId
```

#### Q8: L0/L1 文件权限错误

**症状**:
```
Error: EACCES: permission denied, open 'memory.md'
```

**解决方案**:
```bash
# 1. 检查文件权限
ls -la memory.md memory/

# 2. 修复权限
chmod 644 memory.md
chmod 755 memory/

# 3. 修改所有者
chown $USER:$USER memory.md memory/

# 4. 检查父目录权限
ls -la . | grep memory
```

### 10.4 性能问题

#### Q9: 响应缓慢

**症状**: 对话响应时间超过 5 秒

**解决方案**:
```bash
# 1. 检查网络连接（Platform 模式）
ping api.mem0.ai

# 2. 检查 Server 负载
docker stats mem0-server

# 3. 减少 topK
# 在配置中设置:
# "topK": 3

# 4. 禁用 L0/L1（如果不需要）
# "l0Enabled": false,
# "l1Enabled": false
```

#### Q10: 内存占用高

**症状**: Node.js 进程占用大量内存

**解决方案**:
```bash
# 1. 限制 Node.js 内存
export NODE_OPTIONS="--max-old-space-size=512"

# 2. 减少 L1 recentDays
# "l1RecentDays": 3

# 3. 减少 L1 categories
# "l1Categories": ["projects"]

# 4. 定期清理旧记忆
openclaw mem0 list --before 2025-01-01 | xargs -I {} openclaw mem0 forget {}
```

---

## 11. 进阶配置

### 11.1 多环境配置

#### 11.1.1 创建多环境配置

```bash
# 开发环境
nano ~/.openclaw/openclaw.dev.json

# 生产环境
nano ~/.openclaw/openclaw.prod.json
```

#### 11.1.2 使用不同配置启动

```bash
# 开发环境
openclaw --config ~/.openclaw/openclaw.dev.json start

# 生产环境
openclaw --config ~/.openclaw/openclaw.prod.json start
```

### 11.2 自定义记忆路径

```json5
{
  "config": {
    "l0Path": "/data/memories/memory.md",
    "l1Dir": "/data/memories/context"
  }
}
```

### 11.3 多 Agent 配置

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0-agent1": {
      "enabled": true,
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "agent-1",
        "userId": "user-123"
      }
    },
    "@mem0/openclaw-mem0-agent2": {
      "enabled": true,
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "agent-2",
        "userId": "user-456"
      }
    }
  }
}
```

### 11.4 调试模式

```bash
# 启用详细日志
export DEBUG="openclaw:mem0:*"
export LOG_LEVEL="debug"

# 启动 OpenClaw
openclaw start

# 查看日志
tail -f ~/.openclaw/logs/openclaw.log
```

### 11.5 监控和日志

#### 11.5.1 查看 Plugin 日志

```bash
# 实时查看
openclaw logs --follow --plugin @mem0/openclaw-mem0

# 查看最近日志
openclaw logs --tail 100 --plugin @mem0/openclaw-mem0
```

#### 11.5.2 自定义日志级别

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "logLevel": "debug",  // "error", "warn", "info", "debug"
      "config": { ... }
    }
  }
}
```

---

## 12. 附录

### 12.1 配置模板

#### 12.1.1 最小配置

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "open-source",
        "userId": "default"
      }
    }
  }
}
```

#### 12.1.2 推荐配置（Server 模式）

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "openclaw-main",
        "userId": "default",
        "autoRecall": true,
        "autoCapture": true,
        "topK": 5,
        "searchThreshold": 0.3,
        "l0Enabled": true,
        "l1Enabled": true,
        "l1AutoWrite": true
      }
    }
  }
}
```

### 12.2 环境变量清单

| 变量名 | 用途 | 示例值 |
|--------|------|--------|
| `MEM0_API_KEY` | Platform 模式 API Key | `m0-xxx` |
| `MEM0_SERVER_API_KEY` | Server 模式 API Key | `mem0_xxx` |
| `OPENAI_API_KEY` | OpenAI API Key（OSS 模式） | `sk-xxx` |
| `DEBUG` | 调试模式 | `openclaw:mem0:*` |
| `LOG_LEVEL` | 日志级别 | `debug` |

### 12.3 端口清单

| 端口 | 服务 | 说明 |
|------|------|------|
| 8000 | mem0-server | HTTP API |
| 5432 | PostgreSQL | 数据库 |
| 7474 | Neo4j | HTTP 界面 |
| 7687 | Neo4j | Bolt 协议 |
| 6379 | Redis | 缓存 |

### 12.4 文件清单

| 文件/目录 | 位置 | 说明 |
|-----------|------|------|
| 配置文件 | `~/.openclaw/openclaw.json` | OpenClaw 配置 |
| Plugin 目录 | `~/.openclaw/plugins/@mem0/openclaw-mem0/` | Plugin 文件 |
| L0 文件 | `./memory.md` | 持久记忆 |
| L1 目录 | `./memory/` | 结构化记忆 |
| Server 数据 | `/opt/mem0-data/` | Server 数据 |

### 12.5 命令速查

```bash
# 安装
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz

# 查看
openclaw plugins list
openclaw plugins show @mem0/openclaw-mem0

# 卸载
openclaw plugins uninstall @mem0/openclaw-mem0

# 存储
openclaw mem0 store "fact"

# 搜索
openclaw mem0 search "query"

# 列表
openclaw mem0 list

# 统计
openclaw mem0 stats

# L0
openclaw mem0 l0 update --append "fact"

# L1
openclaw mem0 l1 write --category projects
```

---

## 13. 获取帮助

### 13.1 官方资源

- **文档**: https://docs.mem0.ai
- **GitHub**: https://github.com/mem0ai/mem0
- **Discord**: https://discord.gg/mem0
- **支持邮箱**: support@mem0.ai

### 13.2 社区资源

- **GitHub Issues**: 报告 Bug 或请求功能
- **Discord 社区**: 实时讨论和帮助
- **Stack Overflow**: 标签 `mem0`

### 13.3 本地文档

- [README.md](./README.md) - 快速开始
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - 部署指南
- [TEST_REPORT.md](./TEST_REPORT.md) - 测试报告
- [CHANGELOG.md](./CHANGELOG.md) - 版本历史

---

**教程版本**: 2.0.0
**最后更新**: 2026-03-07
**适用版本**: Mem0 Plugin v2.0.0

---

## 检查清单

安装完成后，请确认以下检查清单：

- [ ] Node.js 已安装（v18+）
- [ ] OpenClaw 已安装
- [ ] Plugin 已安装
- [ ] 配置文件已创建
- [ ] 配置参数已设置
- [ ] 基础功能测试通过
- [ ] L0/L1 功能测试通过（如果启用）
- [ ] Server 连接正常（如果使用 Server 模式）
- [ ] API Key 已配置（如果需要）

全部勾选后，你的 Mem0 Plugin 就已经成功配置并可以使用了！
