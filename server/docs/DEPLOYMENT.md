# Mem0 Server 部署文档

## 版本信息

- **文档版本**: 2.0.0
- **最后更新**: 2026-03-07
- **Server 版本**: 2.0.0 (Enhanced)

---

## 目录

1. [部署概述](#部署概述)
2. [快速开始](#快速开始)
3. [Docker 部署](#docker-部署)
4. [生产部署](#生产部署)
5. [数据持久化](#数据持久化)
6. [外部访问配置](#外部访问配置)
7. [监控运维](#监控运维)
8. [故障排查](#故障排查)

---

## 部署概述

### 1.1 部署架构

```
┌─────────────────────────────────────────────────────────────────┐
│                   外部访问 (0.0.0.0:8000)                      │
└────────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                     │
        ▼                     ▼
┌─────────────────┐   ┌─────────────────┐
│ mem0-server     │   │ mem0-redis      │
│ (FastAPI)      │   │ (速率限制)       │
│ 0.0.0.0:8000   │   │ 6379            │
└────┬────┬─────┘   └─────────────────┘
     │    │
     │    └────────────────┐
     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐
│ mem0-postgres   │   │ mem0-neo4j      │
│ + pgvector     │   │ (图存储)         │
│ 5432           │   │ 7687            │
└─────────────────┘   └─────────────────┘
```

### 1.2 部署方式

| 方式 | 适用场景 | 复杂度 |
|------|-----------|---------|
| **Docker Compose** | 开发、测试、生产 | 低 |
| **Kubernetes** | 大规模生产、高可用 | 中高 |
| **传统部署** | 有特定环境要求 | 中 |

---

## 快速开始

### 2.1 前置要求

| 要求 | 版本 |
|------|------|
| Docker | 20.10+ |
| Docker Compose | 2.0+ |
| 内存 | 4GB+ |
| 存储 | 20GB+ |

### 2.2 克隆项目

```bash
git clone https://github.com/mem0ai/mem0.git
cd mem0/server
```

### 2.3 配置环境变量

```bash
# 复制模板
cp .env.example .env

# 编辑配置
nano .env
```

**重要配置项**:
```bash
# PostgreSQL - 使用容器名而非 IP
POSTGRES_HOST=mem0-postgres

# 端口绑定 - 0.0.0.0 支持外部访问
# 在 docker-compose.prod.yaml 中配置
```

### 2.4 启动服务

```bash
# 构建并启动所有服务
docker compose -f docker-compose.prod.yaml up -d --build

# 查看日志
docker compose -f docker-compose.prod.yaml logs -f

# 检查健康状态 (本地)
curl http://localhost:8000/health

# 检查健康状态 (外部)
curl http://YOUR_SERVER_IP:8000/health
```

---

## Docker 部署

### 3.1 生产配置 (docker-compose.prod.yaml)

```yaml
networks:
  mem0net:
    name: mem0net
    driver: bridge

services:
  mem0-postgres:
    image: pgvector/pgvector:pg16
    container_name: mem0-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-mem0db}
      POSTGRES_USER: ${POSTGRES_USER:-mem0user}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-mem0pass}
    volumes:
      - /home/yhz/mem0-data/postgres:/var/lib/postgresql/data:z
    networks: [mem0net]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-mem0user}"]
      interval: 10s
      timeout: 5s
      retries: 5

  mem0-server:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mem0-server
    restart: unless-stopped
    env_file: .env
    volumes:
      - /home/yhz/mem0-data/history:/app/history:z
    ports:
      - "0.0.0.0:8000:8000"  # 绑定到所有网卡
    depends_on:
      mem0-postgres: { condition: service_healthy }
    networks: [mem0net]
```

---

## 数据持久化

### 4.1 数据目录结构

所有数据保存在 `/home/yhz/mem0-data/`:

```
/home/yhz/mem0-data/
├── postgres/     # 向量数据 (pgvector)
├── neo4j/        # 图数据库
│   ├── data/
│   ├── logs/
│   └── import/
├── redis/        # 缓存/速率限制
└── history/      # API Keys, 历史记录
```

### 4.2 容器卷映射

| 容器 | 宿主机路径 | 容器路径 | 内容 |
|------|-----------|----------|------|
| mem0-postgres | `/home/yhz/mem0-data/postgres` | `/var/lib/postgresql/data` | 向量数据 |
| mem0-neo4j | `/home/yhz/mem0-data/neo4j/data` | `/data` | 图数据库 |
| mem0-redis | `/home/yhz/mem0-data/redis` | `/data` | 缓存 |
| mem0-server | `/home/yhz/mem0-data/history` | `/app/history` | API Keys |

### 4.3 数据备份

```bash
# 备份 PostgreSQL
docker exec mem0-postgres pg_dump -U postgres mem0db > backup_$(date +%Y%m%d).sql

# 备份所有数据目录
tar -czvf mem0-data-backup-$(date +%Y%m%d).tar.gz /home/yhz/mem0-data/
```

---

## 外部访问配置

### 5.1 端口绑定

服务器绑定到 `0.0.0.0:8000`，支持局域网和外部访问:

```yaml
ports:
  - "0.0.0.0:8000:8000"
```

### 5.2 防火墙配置

```bash
# 开放 8000 端口
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload

# 验证端口开放
sudo firewall-cmd --list-ports
```

### 5.3 访问测试

```bash
# 本地访问
curl http://localhost:8000/health

# 局域网访问
curl http://192.168.x.x:8000/health

# API 文档
http://YOUR_SERVER_IP:8000/docs
```

---

## 监控运维

### 6.1 健康检查

```bash
# 查看所有容器状态
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 健康检查端点
curl http://localhost:8000/health
# 返回: {"status":"healthy","loaded_agents":0,"redis":"ok"}
```

### 6.2 日志查看

```bash
# 查看服务器日志
docker logs mem0-server -f --tail 100

# 查看所有服务日志
docker compose -f docker-compose.prod.yaml logs -f
```

### 6.3 资源监控

```bash
# 查看容器资源使用
docker stats mem0-server mem0-postgres mem0-redis mem0-neo4j
```

---

## 故障排查

### 7.1 常见问题

**PostgreSQL 连接失败**
```bash
# 检查容器状态
docker ps | grep postgres

# 检查连接配置
# 确保 POSTGRES_HOST=mem0-postgres (使用容器名)
```

**服务 unhealthy**
```bash
# 查看日志
docker logs mem0-server --tail 50

# 重启服务
docker compose -f docker-compose.prod.yaml restart mem0-server
```

**外部无法访问**
```bash
# 检查端口绑定
docker port mem0-server

# 检查防火墙
sudo firewall-cmd --list-ports
```

---

**文档版本**: 2.0
**最后更新**: 2026-03-07
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-mem0db}
      POSTGRES_USER: ${POSTGRES_USER:-mem0user}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-mem0pass}
    volumes:
      - /opt/mem0-data/postgres:/var/lib/postgresql/data:z
      - ./postgres-init:/docker-entrypoint-initdb.d:ro,z
    networks: [mem0net]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-mem0user} -d ${POSTGRES_DB:-mem0db}"]
      interval: 10s
      timeout: 5s
      retries: 5

  mem0-neo4j:
    image: neo4j:5.26-community
    container_name: mem0-neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: "${NEO4J_USERNAME:-neo4j}/${NEO4J_PASSWORD:-mem0graph}"
      NEO4J_dbms_memory_heap_initial__size: 256m
      NEO4J_dbms_memory_heap_max__size: 1G
    volumes:
      - /opt/mem0-data/neo4j/data:/data:z
      - /opt/mem0-data/neo4j/logs:/logs:z
      - /opt/mem0-data/neo4j/import:/import:z
    networks: [mem0net]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:7474 || exit 1"]
      interval: 15s
      retries: 5

  mem0-redis:
    image: redis:7-alpine
    container_name: mem0-redis
    restart: unless-stopped
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:-mem0redis}
    command: sh -c "redis-server --requirepass $$REDIS_PASSWORD --maxmemory 512mb --maxmemory-policy allkeys-lru"
    volumes:
      - /opt/mem0-data/redis:/data:z
    networks: [mem0net]
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-mem0redis}", "ping"]
      interval: 10s
      retries: 3

  mem0-server:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mem0-server
    restart: unless-stopped
    env_file: .env
    volumes:
      - /opt/mem0-data/history:/app/history:z
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      mem0-postgres: { condition: service_healthy }
      mem0-neo4j: { condition: service_healthy }
      mem0-redis: { condition: service_healthy }
    networks: [mem0net]
```

### 3.3 启动命令

```bash
# 启动所有服务
docker-compose -f docker-compose.prod.yaml up -d

# 启动特定服务
docker-compose -f docker-compose.prod.yaml up -d mem0-server

# 停止服务
docker-compose -f docker-compose.prod.yaml down

# 重启服务
docker-compose -f docker-compose.prod.yaml restart mem0-server

# 查看日志
docker-compose -f docker-compose.prod.yaml logs -f mem0-server

# 查看所有服务状态
docker-compose -f docker-compose.prod.yaml ps
```

---

## 生产部署

### 4.1 环境准备

#### 4.1.1 系统要求

| 资源 | 最小值 | 推荐值 |
|------|--------|--------|
| **CPU** | 2 核心 | 4+ 核心 |
| **内存** | 4GB | 8GB+ |
| **存储** | 50GB SSD | 100GB+ SSD |
| **网络** | 100Mbps | 1Gbps |

#### 4.1.2 安全配置

```bash
# 创建专用用户
useradd -r -s /bin/false mem0

# 创建数据目录
mkdir -p /opt/mem0-data/{postgres,neo4j,redis,history}
chown -R mem0:mem0 /opt/mem0-data

# 设置权限
chmod 750 /opt/mem0-data
```

### 4.2 反向代理配置

#### 4.2.1 Nginx 配置

```nginx
upstream mem0_backend {
    server 127.0.0.1:8000;
    keepalive 64;
}

server {
    listen 80;
    server_name mem0.example.com;

    # 重定向到 HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name mem0.example.com;

    # SSL 证书
    ssl_certificate /etc/ssl/certs/mem0.crt;
    ssl_certificate_key /etc/ssl/private/mem0.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 请求大小限制
    client_max_body_size 10M;

    # 超时配置
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    location / {
        proxy_pass http://mem0_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 4.3 Kubernetes 部署

#### 4.3.1 ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mem0-config
data:
  POSTGRES_HOST: "postgres-service"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "mem0db"
  REDIS_URL: "redis://redis-service:6379/0"
```

#### 4.3.2 Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mem0-secrets
type: Opaque
data:
  POSTGRES_PASSWORD: <base64-encoded-password>
  OPENAI_API_KEY: <base64-encoded-api-key>
  ADMIN_SECRET_KEY: <base64-encoded-admin-key>
```

#### 4.3.3 Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mem0-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: mem0-server
  template:
    metadata:
      labels:
        app: mem0-server
    spec:
      containers:
      - name: mem0-server
        image: mem0/server:2.0.0
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: mem0-config
        - secretRef:
            name: mem0-secrets
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "2Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
```

#### 4.3.4 Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mem0-service
spec:
  type: LoadBalancer
  selector:
    app: mem0-server
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8000
```

---

## 配置管理

### 5.1 环境变量

| 变量 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `POSTGRES_HOST` | 是 | postgres | PostgreSQL 主机 |
| `POSTGRES_PORT` | 是 | 5432 | PostgreSQL 端口 |
| `POSTGRES_DB` | 是 | postgres | 数据库名称 |
| `POSTGRES_USER` | 是 | postgres | 用户名 |
| `POSTGRES_PASSWORD` | 是 | postgres | 密码 |
| `POSTGRES_COLLECTION_NAME` | 否 | memories | 默认集合名 |
| `NEO4J_URI` | 否 | bolt://neo4j:7687 | Neo4j 连接 URL |
| `NEO4J_USERNAME` | 否 | neo4j | Neo4j 用户名 |
| `NEO4J_PASSWORD` | 否 | mem0graph | Neo4j 密码 |
| `OPENAI_API_KEY` | 是 | - | LLM API Key |
| `OPENAI_BASE_URL` | 否 | - | LLM 基础 URL |
| `OPENAI_MODEL` | 否 | gpt-4.1-nano-2025-04-14 | LLM 模型 |
| `OPENAI_EMBEDDING_MODEL` | 否 | text-embedding-3-small | 嵌入模型 |
| `EMBEDDING_DIMENSIONS` | 否 | 1536 | 向量维度 |
| `HISTORY_DB_PATH` | 否 | /app/history/history.db | 历史数据库路径 |
| `REDIS_URL` | 否 | redis://localhost:6379/0 | Redis URL |
| `REDIS_PASSWORD` | 否 | - | Redis 密码 |
| `ADMIN_SECRET_KEY` | 是 | - | 管理员密钥 |
| `RATE_LIMIT_REQUESTS` | 否 | 200 | 速率限制请求数 |
| `RATE_LIMIT_WINDOW` | 否 | 60 | 速率限制窗口（秒）|

### 5.2 .env.example

```bash
# PostgreSQL 配置
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=mem0db
POSTGRES_USER=mem0user
POSTGRES_PASSWORD=CHANGE_ME_SECURE_PASSWORD
POSTGRES_COLLECTION_NAME=memories

# Neo4j 配置（可选）
NEO4J_URI=bolt://neo4j:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=CHANGE_ME_SECURE_PASSWORD

# OpenAI 配置
OPENAI_API_KEY=sk-your-openai-api-key
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-nano-2025-04-14
OPENAI_EMBEDDING_MODEL=text-embedding-3-small

# 向量配置
EMBEDDING_DIMENSIONS=1536

# 历史数据库
HISTORY_DB_PATH=/app/history/history.db

# Redis 配置
REDIS_URL=redis://redis:6379/0
REDIS_PASSWORD=CHANGE_ME_SECURE_PASSWORD

# 管理配置
ADMIN_SECRET_KEY=CHANGE_ME_SECURE_ADMIN_KEY

# 速率限制
RATE_LIMIT_REQUESTS=200
RATE_LIMIT_WINDOW=60
```

---

## 监控运维

### 6.1 健康检查

```bash
# 基本健康检查
curl http://localhost:8000/health

# 预期响应
{
  "status": "healthy",
  "loaded_agents": 2,
  "redis": "ok"
}
```

### 6.2 日志查看

```bash
# Docker 日志
docker logs -f mem0-server

# Docker Compose 日志
docker-compose logs -f mem0-server

# 查看最近 100 行
docker logs --tail 100 mem0-server

# 查看错误日志
docker logs mem0-server 2>&1 | grep ERROR
```

### 6.3 Prometheus 监控（可选）

```python
# 添加到 main.py
from prometheus_client import Counter, Histogram, generate_latest

# 指标
request_count = Counter('mem0_requests_total', 'Total requests')
request_duration = Histogram('mem0_request_duration_seconds', 'Request duration')

# 端点
@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")
```

### 6.4 告警规则

```yaml
groups:
  - name: mem0-alerts
    rules:
      - alert: Mem0HighErrorRate
        expr: rate(mem0_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"

      - alert: Mem0HighLatency
        expr: histogram_quantile(0.95, mem0_request_duration_seconds) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected"
```

---

## 故障排查

### 7.1 常见问题

#### 问题 1：无法连接到 PostgreSQL

**症状**：
```
connection to server at "postgres", port 5432 failed
```

**解决方案**：
```bash
# 检查 PostgreSQL 是否运行
docker ps | grep postgres

# 检查 PostgreSQL 日志
docker logs mem0-postgres

# 测试连接
docker exec -it mem0-postgres psql -U mem0user -d mem0db
```

#### 问题 2：Redis 连接失败

**症状**：
```
Redis connection failed, running without Redis
```

**解决方案**：
```bash
# 检查 Redis 是否运行
docker ps | grep redis

# 检查 Redis 日志
docker logs mem0-redis

# 测试连接
docker exec -it mem0-redis redis-cli ping
```

#### 问题 3：速率限制异常

**症状**：
```
Rate limit exceeded for API key
```

**解决方案**：
```bash
# 检查 Redis 中的速率限制数据
docker exec -it mem0-redis redis-cli -a $REDIS_PASSWORD
> ZRANGE ratelimit:your-api-key 0 -1 WITHSCORES

# 清空速率限制（测试用）
> DEL ratelimit:your-api-key
```

#### 问题 4：LLM API 超时

**症状**：
```
Error in add_memory: timeout
```

**解决方案**：
```bash
# 检查 OPENAI_BASE_URL 是否正确
echo $OPENAI_BASE_URL

# 测试 API 连接
curl -I https://api.openai.com/v1

# 增加 timeout
# 在 mem0 配置中添加:
# "llm": {
#   "config": {
#     "timeout": 60
#   }
# }
```

### 7.2 调试模式

```bash
# 设置日志级别为 DEBUG
export LOG_LEVEL=DEBUG

# 启动服务
docker-compose up

# 查看详细日志
docker-compose logs -f | grep DEBUG
```

### 7.3 性能调优

#### 数据库调优

```sql
-- 增加 PostgreSQL 连接池
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';

-- 重启 PostgreSQL
SELECT pg_reload_conf();
```

#### Redis 调优

```bash
# 增加最大内存
redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru

# 启用持久化（可选）
redis-server --save 900 1 --save 300 10
```

---

## 附录

### A. 端口列表

| 端口 | 服务 | 说明 |
|------|------|------|
| 8000 | mem0-server | HTTP API |
| 5432 | PostgreSQL | 数据库 |
| 7474 | Neo4j | HTTP 界面 |
| 7687 | Neo4j | Bolt 协议 |
| 6379 | Redis | 缓存 |

### B. 数据目录

| 目录 | 内容 |
|------|------|
| `/opt/mem0-data/postgres` | PostgreSQL 数据 |
| `/opt/mem0-data/neo4j/data` | Neo4j 数据 |
| `/opt/mem0-data/neo4j/logs` | Neo4j 日志 |
| `/opt/mem0-data/redis` | Redis 数据 |
| `/opt/mem0-data/history` | 记忆历史和 API Keys |

### C. 备份策略

```bash
# PostgreSQL 备份
docker exec mem0-postgres pg_dump -U mem0user mem0db > backup.sql

# 恢复
docker exec -i mem0-postgres psql -U mem0user mem0db < backup.sql

# Neo4j 备份
docker exec mem0-neo4j neo4j-admin backup --from=/data --to=/backup

# Redis 备份
docker exec mem0-redis redis-cli SAVE
docker cp mem0-redis:/data/dump.rdb ./redis-backup.rdb
```

---

**文档结束**
