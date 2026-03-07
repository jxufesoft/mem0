# Mem0 Plugin 部署指南

**版本**: 2.0.0  
**更新日期**: 2026-03-07  

本指南涵盖从开发环境到生产环境的完整部署流程。

---

## 📋 目录

1. [开发环境部署](#1-开发环境部署)
2. [生产环境部署](#2-生产环境部署)
3. [OpenClaw 系统服务](#3-openclaw-系统服务)
4. [Docker Compose 部署](#4-docker-compose-部署)
5. [配置管理](#5-配置管理)
6. [监控与运维](#6-监控与运维)
7. [故障排查](#7-故障排查)

---

## 1. 开发环境部署

### 1.1 前置条件

```bash
# 检查 Node.js 版本 (需要 >= 22.12.0)
node --version

# 检查 npm 版本
npm --version

# 检查 OpenClaw 安装
openclaw --version
```

### 1.2 安装 Plugin

```bash
# 方式 1: 从 npm 安装
npm install @mem0/openclaw-mem0

# 方式 2: 从本地包安装
openclaw plugin install mem0-openclaw-mem0-2.0.0.tgz

# 方式 3: 开发模式 (符号链接)
cd /path/to/mem0/openclaw
npm link
ln -s $(pwd) ~/.openclaw/extensions/openclaw-mem0
```

### 1.3 配置 Plugin

```bash
# 启用 Plugin
openclaw config set plugins.entries.openclaw-mem0.enabled true

# 设置 Server 模式
openclaw config set plugins.entries.openclaw-mem0.config.mode server
openclaw config set plugins.entries.openclaw-mem0.config.serverUrl http://localhost:8000
openclaw config set plugins.entries.openclaw-mem0.config.serverApiKey your-api-key

# 验证配置
openclaw config get plugins.entries.openclaw-mem0
```

### 1.4 启动 Gateway

```bash
# 前台启动
openclaw gateway run

# 检查状态
openclaw health
```

---

## 2. 生产环境部署

### 2.1 环境准备

```bash
# 安装 Node.js (推荐使用 nvm)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
nvm alias default 22

# 安装 OpenClaw
npm install -g openclaw

# 验证安装
openclaw --version
```

### 2.2 Mem0 Server 部署

```bash
# 克隆仓库
git clone https://github.com/mem0ai/mem0.git
cd mem0/server

# 复制配置文件
cp docker-compose.prod.yaml docker-compose.override.yaml

# 编辑环境变量
vim .env

# 启动服务
docker-compose -f docker-compose.prod.yaml up -d

# 验证服务
curl http://localhost:8000/health
```

### 2.3 Plugin 生产配置

```bash
# 创建生产配置
openclaw config set plugins.entries.openclaw-mem0.enabled true
openclaw config set plugins.entries.openclaw-mem0.config.mode server
openclaw config set plugins.entries.openclaw-mem0.config.serverUrl http://mem0-server:8000
openclaw config set plugins.entries.openclaw-mem0.config.serverApiKey ${MEM0_API_KEY}
openclaw config set plugins.entries.openclaw-mem0.config.agentId openclaw-prod
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled true
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled true
```

---

## 3. OpenClaw 系统服务

### 3.1 创建 Systemd 服务

```bash
# 创建服务目录
mkdir -p ~/.config/systemd/user

# 创建服务文件
cat > ~/.config/systemd/user/openclaw-gateway.service << 'EOL'
[Unit]
Description=OpenClaw Gateway Service
Documentation=https://docs.openclaw.ai/cli/gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
Environment="PATH=/home/YOUR_USER/.nvm/versions/node/v22.22.1/bin:/usr/local/bin:/usr/bin:/bin"
Environment="NODE_VERSION=v22.22.1"
ExecStart=/home/YOUR_USER/.nvm/versions/node/v22.22.1/bin/node /home/YOUR_USER/.nvm/versions/node/v22.22.1/lib/node_modules/openclaw/openclaw.mjs gateway run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOL

# 替换用户名
sed -i "s/YOUR_USER/$USER/g" ~/.config/systemd/user/openclaw-gateway.service
```

### 3.2 启用服务

```bash
# 重新加载 systemd
systemctl --user daemon-reload

# 启用服务 (开机自启)
systemctl --user enable openclaw-gateway

# 启动服务
systemctl --user start openclaw-gateway

# 检查状态
systemctl --user status openclaw-gateway

# 启用 linger (无需登录即可启动服务)
loginctl enable-linger $USER
```

### 3.3 服务管理命令

```bash
# 查看状态
systemctl --user status openclaw-gateway

# 启动服务
systemctl --user start openclaw-gateway

# 停止服务
systemctl --user stop openclaw-gateway

# 重启服务
systemctl --user restart openclaw-gateway

# 查看日志
journalctl --user -u openclaw-gateway -f

# 查看最近 100 行日志
journalctl --user -u openclaw-gateway -n 100
```

---

## 4. Docker Compose 部署

### 4.1 完整 Stack 配置

```yaml
# docker-compose.yml
version: '3.8'

services:
  openclaw-gateway:
    image: node:22
    container_name: openclaw-gateway
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    volumes:
      - ~/.openclaw:/root/.openclaw
      - ~/.nvm/versions/node/v22.22.1:/usr/local/node
    command: /usr/local/node/bin/node /usr/local/node/lib/node_modules/openclaw/openclaw.mjs gateway run
    ports:
      - "18789:18789"
    networks:
      - mem0-network
    depends_on:
      - mem0-server

  mem0-server:
    image: mem0/server:latest
    container_name: mem0-server
    restart: unless-stopped
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_USER=mem0
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=mem0db
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    ports:
      - "8000:8000"
    networks:
      - mem0-network
    depends_on:
      - postgres
      - redis

  postgres:
    image: pgvector/pgvector:pg16
    container_name: mem0-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=mem0
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=mem0db
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - mem0-network

  redis:
    image: redis:7-alpine
    container_name: mem0-redis
    restart: unless-stopped
    volumes:
      - redis-data:/data
    networks:
      - mem0-network

networks:
  mem0-network:
    driver: bridge

volumes:
  postgres-data:
  redis-data:
```

### 4.2 启动 Stack

```bash
# 创建环境变量文件
cat > .env << 'EOL'
POSTGRES_PASSWORD=your-secure-password
EOL

# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 检查服务状态
docker-compose ps
```

---

## 5. 配置管理

### 5.1 配置文件位置

```
~/.openclaw/
├── openclaw.json          # 主配置文件
├── extensions/
│   └── openclaw-mem0/     # Plugin 目录
│       ├── index.ts
│       └── lib/
└── memory/                # L1 记忆目录
    ├── 2026-03-07.md
    └── projects/
```

### 5.2 配置模板

**Server 模式 (生产推荐)**
```json
{
  "plugins": {
    "slots": {
      "memory": "openclaw-mem0"
    },
    "entries": {
      "openclaw-mem0": {
        "enabled": true,
        "config": {
          "mode": "server",
          "serverUrl": "http://mem0-server:8000",
          "serverApiKey": "${MEM0_API_KEY}",
          "agentId": "openclaw-prod",
          "userId": "default",
          "l0Enabled": true,
          "l1Enabled": true,
          "l1AutoWrite": true,
          "l1Categories": ["projects", "contacts", "tasks"]
        }
      }
    }
  }
}
```

### 5.3 环境变量

```bash
# ~/.bashrc 或 ~/.zshrc
export MEM0_API_KEY="your-api-key"
export MEM0_SERVER_URL="http://localhost:8000"
export OPENCLAW_GATEWAY_PORT="18789"
```

---

## 6. 监控与运维

### 6.1 健康检查

```bash
# OpenClaw Gateway
openclaw health

# Mem0 Server
curl http://localhost:8000/health

# 检查 Plugin 状态
openclaw health | grep mem0
```

### 6.2 日志管理

```bash
# Gateway 日志
journalctl --user -u openclaw-gateway -f

# 文件日志位置
ls -la /tmp/openclaw/openclaw-*.log

# Server 日志
docker logs mem0-server -f
```

### 6.3 性能监控

```bash
# 运行性能测试
cd /home/yhz/project/mem0/openclaw
bash test_performance.sh

# 检查资源使用
docker stats mem0-server mem0-postgres mem0-redis
```

### 6.4 备份策略

```bash
# 备份 PostgreSQL
docker exec mem0-postgres pg_dump -U mem0 mem0db > backup_$(date +%Y%m%d).sql

# 备份 OpenClaw 配置
cp -r ~/.openclaw ~/.openclaw.backup.$(date +%Y%m%d)

# 备份 L0/L1 记忆
tar -czvf memory_backup_$(date +%Y%m%d).tar.gz ~/.openclaw/memory*
```

---

## 7. 故障排查

### 7.1 常见问题

**Plugin 显示 error 状态**
```bash
# 检查配置
openclaw config get plugins.entries.openclaw-mem0

# 检查日志
journalctl --user -u openclaw-gateway -n 50

# 重启 Gateway
systemctl --user restart openclaw-gateway
```

**Gateway 无法连接**
```bash
# 检查服务状态
systemctl --user status openclaw-gateway

# 检查端口
ss -tlnp | grep 18789

# 检查防火墙
sudo firewall-cmd --list-ports
```

**Mem0 Server 无响应**
```bash
# 检查容器状态
docker ps -a | grep mem0

# 检查日志
docker logs mem0-server --tail 100

# 重启服务
docker restart mem0-server
```

**API Key 无效**
```bash
# 验证 API Key
curl -X POST http://localhost:8000/search \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'

# 检查 API Key 文件
docker exec mem0-server cat /app/history/api_keys.json
```

### 7.2 诊断命令

```bash
# 完整诊断
openclaw doctor

# 网络诊断
curl -v http://localhost:8000/health
curl -v http://localhost:18789

# 资源使用
top -p $(pgrep -f openclaw)
```

---

## 📊 性能基准

| 指标 | 生产目标 | 实测值 |
|------|---------|--------|
| 健康检查延迟 | <50ms | 14ms ✅ |
| 搜索延迟 | <200ms | 82ms ✅ |
| 获取全部延迟 | <100ms | 20ms ✅ |
| 并发吞吐量 | >100 req/s | 365 req/s ✅ |

---

**部署指南版本**: 2.0  
**最后更新**: 2026-03-07
