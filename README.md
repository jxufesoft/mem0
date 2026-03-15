# Mem0 增强版 - AI 智能记忆层

<p align="center">
  <strong>三层记忆架构 | 生产就绪 | OpenClaw 集成</strong>
</p>

<p align="center">
  <a href="https://github.com/jxufesoft/mem0">
    <img src="https://img.shields.io/badge/GitHub-jxufesoft/mem0-blue" alt="GitHub">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/版本-2.4.11-green" alt="Version">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/测试通过率-100%25-brightgreen" alt="Tests">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/状态-生产就绪-success" alt="Status">
  </a>
</p>

---

## 📖 项目简介

本项目是基于 [Mem0](https://github.com/mem0ai/mem0) 的增强版本，提供：

- **OpenClaw 插件** - 为 OpenClaw AI 助手提供长期记忆能力
- **增强版 Server** - 支持 PostgreSQL + pgvector 的 REST API 服务
- **三层记忆架构** - L0/L1/L2 分层存储，兼顾速度和语义理解

### 核心特性

| 特性 | 说明 |
|------|------|
| 🧠 三层记忆 | L0(memory.md) + L1(日期/分类) + L2(向量搜索) |
| 🌐 外部访问 | Server 绑定 0.0.0.0，支持局域网访问 |
| 💾 数据持久化 | PostgreSQL + Neo4j + Redis 完整支持 |
| 🔄 自动记忆 | autoRecall/autoCapture 自动存取记忆 |
| 🐳 容器化部署 | Docker Compose 一键启动 |
| 💾 备份恢复 | 完整备份/恢复/迁移功能 |
| 🔐 API Key 认证 | 管理员密钥 + 用户 API Keys |

---

## 🏗️ 项目结构

```
mem0/
├── openclaw/                 # OpenClaw 记忆插件
│   ├── index.ts             # 插件主入口
│   ├── lib/                 # 核心库
│   │   ├── l0-manager.ts    # L0 记忆管理器
│   │   ├── l1-manager.ts    # L1 记忆管理器
│   │   └── server-client.ts # Server HTTP 客户端
│   └── docs/                # 插件文档
│
├── server/                   # 增强版 Mem0 Server
│   ├── main.py              # FastAPI 服务
│   ├── Dockerfile           # Docker 构建
│   ├── docker-compose.prod.yaml  # 生产部署配置
│   └── postgres-init/       # 数据库初始化
│
├── mem0/                     # Mem0 核心库
├── configs/                  # 配置文件
└── tests/                    # 测试套件
```

---

## 🚀 快速开始

### 环境要求

| 组件 | 版本 |
|------|------|
| Docker | 20.10+ |
| Docker Compose | 2.0+ |
| Node.js | 22+ (OpenClaw 插件) |
| Python | 3.10+ (开发) |

### 1. 启动 Mem0 Server

```bash
cd server

# 创建数据目录
mkdir -p ~/mem0-data/{postgres,neo4j/data,redis,history}

# 启动服务
docker-compose -f docker-compose.prod.yaml up -d

# 验证服务
curl http://localhost:8000/health
```

### 2. 安装 OpenClaw 插件

```bash
cd openclaw

# 打包插件
npm pack

# 安装到 OpenClaw
openclaw plugins install mem0-openclaw-mem0-2.0.0.tgz
```

### 3. 配置 OpenClaw

编辑 `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "allow": ["openclaw-mem0"],
    "slots": { "memory": "openclaw-mem0" },
    "entries": {
      "openclaw-mem0": {
        "enabled": true,
        "config": {
          "mode": "server",
          "serverUrl": "http://localhost:8000",
          "serverApiKey": "your-api-key",
          "userId": "default",
          "agentId": "openclaw-main",
          "autoRecall": true,
          "autoCapture": true,
          "l0Enabled": true,
          "l1Enabled": true
        }
      }
    }
  }
}
```

---

## 📊 三层记忆架构

```
┌─────────────────────────────────────────────────────────┐
│                    记忆读取优先级                         │
├─────────────────────────────────────────────────────────┤
│  L0: MEMORY.md (关键事实)                               │
│  ├── 延迟: ~4ms                                         │
│  ├── 存储: 永久文件                                      │
│  └── 用途: 用户核心信息、偏好设置                         │
├─────────────────────────────────────────────────────────┤
│  L1: 日期/分类文件 (结构化上下文)                        │
│  ├── 延迟: ~4ms                                         │
│  ├── 存储: 按日期 (YYYY-MM-DD.md) 和分类                 │
│  └── 用途: 对话历史、项目记录、任务跟踪                   │
├─────────────────────────────────────────────────────────┤
│  L2: Mem0 Server (向量语义搜索)                          │
│  ├── 延迟: 17-82ms                                      │
│  ├── 存储: PostgreSQL + pgvector                        │
│  └── 用途: 长期记忆、语义检索                            │
└─────────────────────────────────────────────────────────┘
```

**性能对比**: L0/L1 比 L2 快 **4-21 倍**

---

## 🧪 测试结果

### 功能测试 (23/23 通过)

| 模块 | 测试项 | 状态 |
|------|--------|------|
| 基础操作 | 健康检查、CRUD | ✅ |
| 批量操作 | 批量创建、读取 | ✅ |
| 搜索功能 | 向量搜索、过滤 | ✅ |
| 多 Agent | 数据隔离 | ✅ |
| 错误处理 | 认证、参数验证 | ✅ |
| 三层记忆 | L0/L1/L2 集成 | ✅ |

### 性能指标

| 操作 | 平均延迟 | P95 | 吞吐量 |
|------|---------|-----|--------|
| 健康检查 | 0.15ms | 16.7ms | 6578 req/s |
| 搜索记忆 | 1.72ms | 117ms | 581 req/s |
| 获取列表 | 0.23ms | 38.5ms | 4291 req/s |
| 更新记忆 | 0.96ms | 19.2ms | 1045 req/s |
| 创建记忆 | 159ms | 6087ms | 6.2 req/s |

**总体评级**: ⭐⭐⭐⭐⭐ 优秀

---

## 📁 数据目录

```
~/mem0-data/
├── postgres/          # PostgreSQL 数据
├── neo4j/             # Neo4j 图数据库
│   └── data/
├── redis/             # Redis 缓存
└── history/           # 记忆历史记录
```

---

### 💾 备份与恢复

Mem0 Server v2.4.11+ 内置完整备份功能：

```bash
# CLI 工具
cd server/tools

# 备份
./backup.sh create          # 创建备份
./backup.sh list            # 列出备份
./backup.sh download <id>   # 下载备份

# 恢复
./backup.sh restore <id>   # 恢复数据
./backup.sh restore <id> --dry-run  # 预览

# 迁移
./migrate.sh export        # 导出迁移包
./migrate.sh import <file>  # 导入迁移包
```

**API 端点**:
| 方法 | 端点 | 功能 |
|------|------|------|
| POST | /admin/backup | 创建备份 |
| GET | /admin/backup/list | 列出备份 |
| GET | /admin/backup/{id}/download | 下载备份 |
| POST | /admin/backup/{id}/restore | 恢复备份 |
| DELETE | /admin/backup/{id} | 删除备份 |
| POST | /admin/migrate/export | 导出迁移 |
| POST | /admin/migrate/import | 导入迁移 |

> ⚠️ 备份文件保存在 `server/backups/` 目录（宿主机持久化）

---

## 🔧 API 端点

### Mem0 Server (端口 8000)

| 方法 | 端点 | 说明 |
|------|------|------|
| GET | /health | 健康检查 |
| POST | /memories | 创建记忆 |
| GET | /memories | 获取所有记忆 |
| GET | /memories/{id} | 获取单个记忆 |
| PUT | /memories/{id} | 更新记忆 |
| DELETE | /memories/{id} | 删除记忆 |
| GET | /memories/{id}/history | 获取历史 |
| POST | /search | 搜索记忆 |

### 请求示例

```bash
# 创建记忆
curl -X POST http://localhost:8000/memories \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"messages": [{"role": "user", "content": "我喜欢编程"}], "user_id": "default"}'

# 搜索记忆
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"query": "编程", "user_id": "default"}'
```

---

## 📚 文档

| 文档 | 说明 |
|------|------|
| [OpenClaw 插件指南](./openclaw/BEGINNER_GUIDE.md) | 零基础完整教程 |
| [安装指南](./openclaw/INSTALLATION_GUIDE.md) | 详细安装步骤 |
| [部署指南](./openclaw/DEPLOYMENT_GUIDE.md) | 生产环境部署 |
| [架构设计](./openclaw/docs/ARCHITECTURE.md) | 系统架构说明 |
| [Server 部署](./server/README.md) | Server 配置说明 |

---

## 🐳 Docker 服务

```bash
# 查看服务状态
docker-compose -f docker-compose.prod.yaml ps

# 查看日志
docker-compose -f docker-compose.prod.yaml logs -f mem0-server

# 重启服务
docker-compose -f docker-compose.prod.yaml restart
```

### 服务组件

| 服务 | 端口 | 说明 |
|------|------|------|
| mem0-server | 8000 | API 服务 |
| mem0-postgres | 5432 | PostgreSQL + pgvector |
| mem0-neo4j | 7474/7687 | 图数据库 |
| mem0-redis | 6379 | 缓存/速率限制 |

---

## 🔄 Systemd 服务 (OpenClaw Gateway)

```bash
# 启动服务
systemctl --user start openclaw-gateway

# 开机自启
systemctl --user enable openclaw-gateway

# 查看状态
systemctl --user status openclaw-gateway
```

---

## 📝 更新日志

### v2.0.0 (2026-03-07)

**新增功能**
- 三层记忆架构 (L0/L1/L2)
- OpenClaw 插件 v2.0.0
- 增强版 Server (FastAPI)
- 自动记忆存取 (autoRecall/autoCapture)
- 外部访问支持 (0.0.0.0:8000)

**测试结果**
- 功能测试: 100% 通过 (23/23)
- 性能测试: ⭐⭐⭐⭐⭐ 优秀
- 生产状态: ✅ 就绪

---

## 🤝 致谢

本项目基于以下开源项目：
- [Mem0](https://github.com/mem0ai/mem0) - AI 记忆层
- [OpenClaw](https://openclaw.ai) - AI 助手平台
- [pgvector](https://github.com/pgvector/pgvector) - PostgreSQL 向量扩展

---

## 📄 许可证

Apache-2.0 License

---

<p align="center">
  <strong>Made with ❤️ for AI Memory</strong>
</p>
