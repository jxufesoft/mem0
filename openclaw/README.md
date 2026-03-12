# Mem0 Plugin for OpenClaw

[![Version](https://img.shields.io/badge/version-2.1.2-blue.svg)](https://github.com/mem0ai/mem0)
[![Tests](https://img.shields.io/badge/tests-23%2F23%20passed-brightgreen.svg)](./TEST_REPORT.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](./LICENSE)

三层分层记忆系统 for OpenClaw: L0(memory.md) + L1(日期/分类文件) + L2(Mem0 Server 向量搜索)

## ✨ 特性

- 🧠 **三层记忆架构** - L0 快速持久层 + L1 结构化上下文 + L2 向量语义搜索
- 🔄 **三种运行模式** - Platform (云服务) / OSS (开源) / Server (自托管)
- 🔒 **多 Agent 隔离** - 每个 Agent 独立的记忆集合
- ⚡ **高性能** - 15ms 健康检查, 82ms 搜索, 365 req/s 并发
- 🛠️ **7 个 Agent 工具** - 完整的 CRUD 操作和 L0/L1 管理
- 🔌 **OpenClaw 集成** - 自动召回和捕获钩子
- 🌐 **外部访问支持** - Server 绑定 0.0.0.0，支持局域网和远程访问
- 🤖 **自动记忆管理** - 首次安装自动创建管理脚本和定时任务
- 🔑 **Hash 去重** - 双层去重机制 (LLM 语义 + Hash 精确匹配)

## 📊 性能指标

| 操作 | 延迟 | 吞吐量 |
|------|------|--------|
| 健康检查 | 15ms | 69 req/s |
| 搜索记忆 | 82ms | 10 req/s |
| 获取全部 | 20ms | 33 req/s |
| 更新记忆 | 16ms | 43 req/s |
| 50 并发 | 137ms | 365 req/s |

**总体评级**: ⭐⭐⭐⭐⭐ (100/100)

## 🚀 快速开始

### 前置条件

- Node.js >= 22.12.0
- OpenClaw >= 2026.3.0
- Mem0 Server (Server 模式需要)

### 安装

**方式 1: 从 Release 下载安装**
```bash
# 下载最新版本
wget https://github.com/jxufesoft/mem0/releases/download/v2.1.2/mem0-openclaw-mem0-2.1.2.tgz

# 安装插件
openclaw plugins install ./mem0-openclaw-mem0-2.1.2.tgz

# 重启 Gateway (自动触发记忆管理脚本初始化)
openclaw gateway restart
```

**方式 2: 从源码安装**
```bash
cd openclaw
npm pack
openclaw plugins install ./mem0-openclaw-mem0-2.1.2.tgz
openclaw gateway restart
```

**卸载插件**
```bash
openclaw plugins uninstall openclaw-mem0
rm -rf ~/.openclaw/extensions/openclaw-mem0
openclaw gateway restart
```

### 配置

**Server 模式 (推荐)**
```bash
openclaw config set plugins.entries.openclaw-mem0.enabled true
openclaw config set plugins.entries.openclaw-mem0.config.mode server
openclaw config set plugins.entries.openclaw-mem0.config.serverUrl http://localhost:8000
openclaw config set plugins.entries.openclaw-mem0.config.serverApiKey your-api-key
openclaw config set plugins.entries.openclaw-mem0.config.agentId openclaw-main
```

**完整 openclaw.json 配置示例**
```json
"plugins": {
  "slots": {
    "memory": "openclaw-mem0"
  },
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
        "topK": 10,
        "searchThreshold": 0.2,
        "l0Enabled": true,
        "l0Path": "/home/yhz/.openclaw/workspace/memory.md",
        "l1Enabled": true,
        "l1Dir": "/home/yhz/.openclaw/workspace/memory",
        "l1RecentDays": 30,
        "l1Categories": ["projects", "contacts", "tasks", "preferences"],
        "l1AutoWrite": true
      }
    }
  }
}
```

> **注意**: Mem0 Server 默认绑定到 `0.0.0.0:8000`，可以从局域网或外部访问。
> 本地访问使用 `http://localhost:8000`，远程访问使用 `http://YOUR_SERVER_IP:8000`。

### 启用 L0/L1 记忆层

```bash
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled true
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled true
openclaw config set plugins.entries.openclaw-mem0.config.l1AutoWrite true
```

## 🤖 自动记忆管理

### 自动安装流程

插件首次加载时 (Server 模式) 会自动执行以下操作:

```
Plugin 加载
    ↓
检查 ~/.openclaw/scripts/memory_manager.sh
    ↓ (不存在)
自动创建管理脚本
自动配置 crontab (每日 3:00 AM)
运行首次优化
    ↓
Setup 完成 ✅
```

### 生成的文件

| 文件 | 说明 |
|------|------|
| `~/.openclaw/scripts/memory_manager.sh` | 自动管理脚本 |
| `~/.openclaw/logs/memory_manager.log` | 运行日志 |
| crontab entry | `0 3 * * *` 每日 3:00 AM 执行 |

### 手动运行记忆管理
> **首次安装建议**: 安装插件后立即运行一次，可以马上整理已有的记忆文件，无需等待定时任务：
> ```bash
> bash ~/.openclaw/scripts/memory_manager.sh
> ```
> 运行后会立即执行 L1 归档、L0 精简、L2 去重，将 Context 优化到最佳状态。

```bash
# 运行完整记忆管理
bash ~/.openclaw/scripts/memory_manager.sh

# 仅运行 L1 归档
bash ~/.openclaw/scripts/memory_manager.sh archive

# 仅运行 L0 精简
bash ~/.openclaw/scripts/memory_manager.sh prune

# 仅运行 L2 去重
bash ~/.openclaw/scripts/memory_manager.sh dedup

# 查看 Context 优化报告
bash ~/.openclaw/scripts/memory_manager.sh context

# 查看运行日志
tail -f ~/.openclaw/logs/memory_manager.log

# 检查定时任务
crontab -l | grep memory
```

### 记忆管理功能

| 功能 | 说明 | 频率 |
|------|------|------|
| L1 归档 | 归档 14 天前的日期文件 | 每日 |
| L0 精简 | 保持 L0 文件 ≤ 100 行 | 每日 |
| L2 去重 | 删除重复记忆 | 每日 |
| Context 优化 | 生成优化报告 | 每日 |

### 新机器安装验证

> **💡 提示**: 安装后可立即手动运行一次，不用等到每日 3:00 AM 自动执行：
> ```bash
> # 立即整理记忆文件
> bash ~/.openclaw/scripts/memory_manager.sh
> ```

```bash
# 1. 安装插件后重启
openclaw gateway restart

# 2. 验证脚本已创建
ls ~/.openclaw/scripts/memory_manager.sh

# 3. 验证 crontab 已配置
crontab -l | grep memory

# 4. 手动测试运行
bash ~/.openclaw/scripts/memory_manager.sh
```

## 🛠️ Agent 工具

| 工具 | 描述 | 用途 |
|------|------|------|
| `memory_search` | 语义搜索记忆 | 查找相关信息 |
| `memory_list` | 列出所有记忆 | 浏览记忆列表 |
| `memory_store` | 存储新记忆 | 保存重要信息 |
| `memory_get` | 获取单个记忆 | 查看特定记忆 |
| `memory_forget` | 删除记忆 | 移除过时信息 |
| `memory_l0_update` | 更新 L0 持久记忆 | 存储关键事实 |
| `memory_l1_write` | 写入 L1 结构化记忆 | 分类存储信息 |

## 🏗️ 三层记忆架构

```
┌─────────────────────────────────────────────────────────┐
│                    OpenClaw Agent                        │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐   │
│  │  L0: Persistent Memory (memory.md)              │   │
│  │  • 关键用户事实                                   │   │
│  │  • 快速读取 (~1ms)                               │   │
│  │  • 自动精简 (≤100行)                             │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  L1: Structured Context (date/category files)   │   │
│  │  • 按日期/分类组织                                │   │
│  │  • 快速读取 (~5ms)                               │   │
│  │  • 自动归档 (>14天)                              │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  L2: Vector Search (Mem0 Server)                │   │
│  │  • 语义搜索 (~82ms)                              │   │
│  │  • 自动事实提取                                   │   │
│  │  • Hash 去重                                     │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 🔑 Hash 去重机制

```
┌─────────────────────────────────────────────────────────┐
│                    双层去重保护                          │
├─────────────────────────────────────────────────────────┤
│  Layer 1: LLM 语义去重 (已存在)                         │
│           检测语义相似的记忆                             │
│                                                         │
│  Layer 2: Hash 精确去重 (v2.1.0+)                       │
│           MD5 hash 比较完全相同的记忆                    │
└─────────────────────────────────────────────────────────┘
```

**API 端点**:
- `GET /deduplicate` - 查看重复记忆统计
- `POST /deduplicate` - 清理重复记忆 (支持 dry-run)

## 📋 配置选项

### 核心参数

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `mode` | string | `"platform"` | 运行模式: `platform`（Mem0 Cloud）、`open-source`（自托管）、`server`（推荐） |
| `userId` | string | `"default"` | 用户标识，用于隔离不同用户的记忆 |
| `autoRecall` | boolean | `true` | 是否在对话前自动检索相关记忆并加入上下文 |
| `autoCapture` | boolean | `true` | 是否在对话后自动存储关键信息到 L2 向量存储 |
| `customInstructions` | string | `""` | 自定义指令，控制记忆存储行为 |
| `customCategories` | object | `{}` | 自定义分类，如 `{"projects": "项目信息"}` |
| `enableGraph` | boolean | `false` | 是否启用关系图谱 |

### 性能参数

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `topK` | number | `5` | 每次检索返回的最大记忆数量 |
| `searchThreshold` | number | `0.3` | 搜索相似度阈值（0-1），越大越严格 |

### 优化触发参数

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `contextThresholdKB` | number | `50` | 上下文大小阈值（KB），超过时触发自动优化 |
| `messageThreshold` | number | `10` | 消息数量阈值，达到后触发自动优化 |

### Platform 模式

| 选项 | 类型 | 必需 | 描述 |
|------|------|------|------|
| `apiKey` | string | ✅ | Mem0 Cloud API Key |
| `orgId` | string | ❌ | 组织 ID（可选） |
| `projectId` | string | ❌ | 项目 ID（可选） |

### Server 模式

| 选项 | 类型 | 必需 | 描述 |
|------|------|------|------|
| `serverUrl` | string | ✅ | Server 地址，如 `http://localhost:8000` |
| `serverApiKey` | string | ✅ | Server API Key |
| `agentId` | string | ❌ | Agent 标识，默认 `openclaw-default` |

### Open-Source 模式

| 选项 | 类型 | 描述 |
|------|------|------|
| `customPrompt` | string | 自定义系统提示词 |
| `oss.embedder` | object | Embedder 配置 |
| `oss.vectorStore` | object | 向量存储配置 |
| `oss.llm` | object | LLM 配置 |
| `oss.historyDbPath` | string | 历史数据库路径，默认 `~/.mem0/history.db` |

### L0 层

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `l0Enabled` | boolean | `true` | 是否启用 L0 层（持久记忆文件） |
| `l0Path` | string | `"memory.md"` | L0 文件路径 |

### L1 层

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `l1Enabled` | boolean | `true` | 是否启用 L1 层（结构化记忆） |
| `l1Dir` | string | `"memory"` | L1 目录路径 |
| `l1RecentDays` | number | `7` | 加载最近 N 天的日期文件 |
| `l1Categories` | array | `["projects","contacts","tasks"]` | 分类文件名 |
| `l1AutoWrite` | boolean | `false` | 是否在 `agent_end` 后自动分析对话并写入 L1 |

## 🔧 系统服务设置

将 OpenClaw Gateway 设置为 systemd 服务:

```bash
# 创建服务文件
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/openclaw-gateway.service << 'EOL'
[Unit]
Description=OpenClaw Gateway Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
Environment="PATH=/home/YOUR_USER/.nvm/versions/node/v22.22.1/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/home/YOUR_USER/.nvm/versions/node/v22.22.1/bin/node /home/YOUR_USER/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs gateway run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOL

# 启用并启动服务
systemctl --user daemon-reload
systemctl --user enable openclaw-gateway
systemctl --user start openclaw-gateway

# 启用 linger (开机自启)
loginctl enable-linger $USER
```

## 📚 文档

- [BEGINNER_GUIDE.md](./BEGINNER_GUIDE.md) - 零基础完整教程
- [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md) - 安装指南
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - 生产部署
- [TEST_REPORT.md](./TEST_REPORT.md) - 测试报告
- [CHANGELOG.md](./CHANGELOG.md) - 变更历史
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - 架构设计

## 🧪 测试

```bash
# 运行功能测试
bash test_plugin_comprehensive.sh

# 运行性能测试
bash test_performance.sh
```

## 🔍 故障排查

**Plugin 状态显示 error**
```bash
# 检查配置
openclaw config get plugins.entries.openclaw-mem0

# 检查日志
journalctl --user -u openclaw-gateway -f
```

**Gateway 未运行**
```bash
systemctl --user status openclaw-gateway
systemctl --user restart openclaw-gateway
```

**API Key 无效**
```bash
# 验证 API Key
curl -X POST http://localhost:8000/search \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "agent_id": "openclaw-main"}'
```

**记忆管理脚本未创建**
```bash
# 手动运行 setup
# 脚本会在插件首次加载时自动创建
# 如果没有创建，检查是否为 server 模式
openclaw config get plugins.entries.openclaw-mem0.config.mode
```

## 📄 License

Apache-2.0

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

---

**维护者**: Mem0 Team  
**版本**: 2.1.2  
**最后更新**: 2026-03-09
