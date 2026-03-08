# Mem0 Plugin for OpenClaw

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/mem0ai/mem0)
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
- 💾 **数据持久化** - 所有数据保存到宿主机映射目录

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

**方式 1: 从 npm 安装**
```bash
npm install @mem0/openclaw-mem0
```

**方式 2: 从本地包安装**
```bash
openclaw plugin install mem0-openclaw-mem0-2.0.0.tgz

openclaw plugins install ./mem0-openclaw-mem0-2.0.1.tgz
openclaw gateway restart


openclaw plugins uninstall @mem0/openclaw-mem0
 rm -rf /home/yhz/.openclaw/extensions/openclaw-mem0
openclaw gateway restart
```

**方式 3: 从源码安装**
```bash
cd openclaw
npm pack
openclaw plugin install mem0-openclaw-mem0-2.0.0.tgz
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

> **注意**: Mem0 Server 默认绑定到 `0.0.0.0:8000`，可以从局域网或外部访问。
> 本地访问使用 `http://localhost:8000`，远程访问使用 `http://YOUR_SERVER_IP:8000`。

**OSS 模式**
```bash
openclaw config set plugins.entries.openclaw-mem0.config.mode open-source
```

**Platform 模式**
```bash
openclaw config set plugins.entries.openclaw-mem0.config.mode platform
openclaw config set plugins.entries.openclaw-mem0.config.apiKey your-mem0-api-key
```

### 启用 L0/L1 记忆层

```bash
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled true
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled true
openclaw config set plugins.entries.openclaw-mem0.config.l1AutoWrite true
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
│  │  • 手动更新                                       │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  L1: Structured Context (date/category files)   │   │
│  │  • 按日期/分类组织                                │   │
│  │  • 快速读取 (~5ms)                               │   │
│  │  • 自动/手动写入                                  │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  L2: Vector Search (Mem0 Server)                │   │
│  │  • 语义搜索 (~82ms)                              │   │
│  │  • 自动事实提取                                   │   │
│  │  • 向量嵌入存储                                   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 📋 配置选项

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `mode` | string | - | 运行模式: platform, open-source, server |
| `serverUrl` | string | - | Mem0 Server URL (Server 模式) |
| `serverApiKey` | string | - | API Key (Server 模式) |
| `agentId` | string | - | Agent 标识符 |
| `userId` | string | default | 用户标识符 |
| `l0Enabled` | boolean | false | 启用 L0 持久层 |
| `l0Path` | string | memory.md | L0 文件路径 |
| `l1Enabled` | boolean | false | 启用 L1 结构化层 |
| `l1Dir` | string | memory | L1 目录路径 |
| `l1RecentDays` | number | 7 | 最近天数 |
| `l1Categories` | array | [] | 分类列表 |
| `l1AutoWrite` | boolean | false | 自动写入 |

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
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

## 📄 License

Apache-2.0

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

---

**维护者**: Mem0 Team  
**版本**: 2.0.0  
**最后更新**: 2026-03-07
