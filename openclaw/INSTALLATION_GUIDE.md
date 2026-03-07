# Mem0 Plugin v2.0.0 安装指南

## 打包后的安装方式

---

## 方式 1: 从本地文件安装（推荐）

适用于：本地测试、自定义修改、离线环境

### 步骤 1: 准备打包文件

```bash
# 确认包文件存在
ls -lh mem0-openclaw-mem0-2.0.0.tgz

# 验证包内容
tar -tzf mem0-openclaw-mem0-2.0.0.tgz | head -20
```

### 步骤 2: 使用 OpenClaw CLI 安装

```bash
# 方法 A: 使用本地 tgz 文件
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz

# 方法 B: 解压后从目录安装
tar -xzf mem0-openclaw-mem0-2.0.0.tgz
openclaw plugins install ./package
```

### 步骤 3: 验证安装

```bash
# 列出已安装的插件
openclaw plugins list

# 查看插件状态
openclaw plugins show @mem0/openclaw-mem0
```

### 步骤 4: 配置插件

#### 模式 1: Platform 模式（Mem0 Cloud）

```bash
# 编辑 openclaw.json
nano ~/.openclaw/openclaw.json
```

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "config": {
        "mode": "platform",
        "apiKey": "${MEM0_API_KEY}",
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

获取 API Key:
```bash
# 从环境变量读取（如果已设置）
echo $MEM0_API_KEY

# 或从 app.mem0.ai 获取
# 访问 https://app.mem0.ai -> Settings -> API Keys
```

#### 模式 2: Open-Source 模式（自托管）

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

高级配置（自定义组件）：
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
              "model": "text-embedding-3-small",
              "baseURL": "https://api.openai.com/v1"
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
              "model": "gpt-4o",
              "temperature": 0.7
            }
          }
        }
      }
    }
  }
}
```

#### 模式 3: Server 模式（Enhanced Server）- 推荐

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

创建 API Key:
```bash
# 假设服务器已运行
curl -X POST http://localhost:8000/admin/keys \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${ADMIN_SECRET_KEY} \
  -d '{
    "agent_id": "openclaw-main",
    "description": "OpenClaw 主 Agent"
  }'

# 保存返回的 api_key 到环境变量
export MEM0_SERVER_API_KEY="mem0_xxxxxxxxxxxxxxxx"
```

---

## 方式 2: 开发模式安装（推荐给开发者）

适用于：开发、调试、持续集成

### 步骤 1: 从源码构建

```bash
# 克隆或使用本地代码
cd /home/yhz/project/mem0/openclaw

# 安装依赖
npm install

# 运行测试（可选）
npm run test

# 类型检查（可选）
npm run typecheck
```

### 步骤 2: 配置 OpenClaw 使用本地代码

```bash
# 编辑 openclaw.json
nano ~/.openclaw/openclaw.json
```

```json5
{
  "plugins": {
    "@mem0/openclaw-mem0": {
      "enabled": true,
      "path": "/home/yhz/project/mem0/openclaw",
      "config": {
        "mode": "server",
        "serverUrl": "http://localhost:8000",
        "serverApiKey": "${MEM0_SERVER_API_KEY}",
        "agentId": "openclaw-dev",
        "userId": "dev-user",
        "l0Enabled": true,
        "l1Enabled": true
      }
    }
  }
}
```

### 步骤 3: 热重载配置

```bash
# 重启 OpenClaw
openclaw restart

# 或重新加载配置
openclaw reload
```

---

## 方式 3: 从 Git 安装（持续开发）

适用于：团队协作、多环境

### 步骤 1: 使用 Git 链接

```bash
# 在项目目录中
cd /home/yhz/project/mem0

# 创建符号链接
ln -sf ./openclaw node_modules/@mem0/openclaw-mem0
```

### 步骤 2: 或使用 npm link

```bash
# 在 openclaw 目录中
cd /home/yhz/project/mem0/openclaw

# 链接到全局
npm link

# 在 OpenClaw 目录中使用
# 注意：这可能需要 OpenClaw 支持
```

---

## 三层记忆配置详解

### L0: 持久记忆层

```json5
{
  "l0Enabled": true,
  "l0Path": "memory.md"
}
```

**功能**:
- 单文件存储（memory.md）
- 最快访问速度
- 手动或自动更新
- 用于关键用户事实

**文件格式**:
```markdown
# Memory

> This file contains important facts and information about you.
> It is automatically maintained by the memory system.

- User name is John
- Timezone is UTC+8
- Primary language is English
- Prefers Python over Java
```

### L1: 结构化层

```json5
{
  "l1Enabled": true,
  "l1Dir": "memory",
  "l1RecentDays": 7,
  "l1Categories": ["projects", "contacts", "tasks"],
  "l1AutoWrite": true
}
```

**功能**:
- 日期文件：每日对话摘要
- 分类文件：项目、联系人、任务等
- 自动分析和写入
- 加载最近 N 天的内容

**目录结构**:
```
memory/
├── 2026-03-07.md        # 今日对话
├── 2026-03-06.md        # 昨日对话
├── 2026-03-05.md        # 前日对话
├── projects.md            # 项目信息
├── contacts.md            # 联系人信息
└── tasks.md              # 任务列表
```

### L2: 向量层（Server/Platform/OSS）

```json5
{
  "mode": "server",
  "topK": 5,
  "searchThreshold": 0.3
}
```

**功能**:
- 语义相似度搜索
- 自动记忆提取
- 记忆历史追踪
- 支持关系图（Platform 模式）

---

## 验证安装

### 基础验证

```bash
# 1. 检查插件是否加载
openclaw plugins list | grep mem0

# 预期输出：
# @mem0/openclaw-mem0@2.0.0  enabled

# 2. 查看插件详情
openclaw plugins show @mem0/openclaw-mem0
```

### 功能验证

```bash
# 3. 测试记忆存储
openclaw mem0 store "User prefers dark mode"

# 4. 测试记忆搜索
openclaw mem0 search "preferences"

# 5. 查看记忆统计
openclaw mem0 stats
```

### 完整验证（需要配置）

```bash
# 如果配置了 Server 模式
export SERVER_API_KEY="your-api-key"

# 运行完整测试
cd /home/yhz/project/mem0/openclaw
SERVER_API_KEY="$SERVER_API_KEY" npx tsx test_plugin.ts
```

---

## 常见问题排查

### 问题 1: 插件无法加载

**症状**: `Error: Plugin not found`

**解决方案**:
```bash
# 检查插件目录权限
ls -la ~/.openclaw/plugins/

# 检查包完整性
tar -tzf mem0-openclaw-mem0-2.0.0.tgz | wc -l
# 应该显示: 21 个文件

# 检查 npm 缓存
npm cache clean
# 重新安装
```

### 问题 2: TypeScript 错误

**症状**: 插件加载时报 TypeScript 错误

**解决方案**:
```bash
# 检查 TypeScript 版本
npm list typescript

# 如果版本不匹配，重新安装
npm install typescript@latest

# 清理并重新构建
rm -rf node_modules package-lock.json
npm install
```

### 问题 3: 配置文件找不到

**症状**: `Error: Configuration file not found`

**解决方案**:
```bash
# 检查 OpenClaw 配置目录
ls -la ~/.openclaw/

# 创建配置目录（如果不存在）
mkdir -p ~/.openclaw

# 创建最小配置
cat > ~/.openclaw/openclaw.json << 'EOF'
{
  "plugins": {}
}
EOF
```

### 问题 4: Server 连接失败

**症状**: `Error: Cannot connect to server`

**解决方案**:
```bash
# 检查服务器是否运行
curl http://localhost:8000/health

# 检查防火墙
netstat -tlnp | grep 8000

# 检查 API Key
curl -H "X-API-Key: YOUR_KEY" http://localhost:8000/health

# 查看服务器日志
docker logs mem0-server
```

### 问题 5: L0/L1 文件权限错误

**症状**: `Error: Permission denied`

**解决方案**:
```bash
# 检查文件权限
ls -la memory.md
ls -la memory/

# 修复权限
chmod 644 memory.md
chmod 755 memory/

# 检查所有者
whoami
stat memory.md | grep "Uid"
```

---

## 升级插件

### 升级步骤

```bash
# 1. 备份当前配置
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.backup

# 2. 卸载旧版本
openclaw plugins uninstall @mem0/openclaw-mem0

# 3. 安装新版本
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz

# 4. 验证配置
openclaw plugins show @mem0/openclaw-mem0

# 5. 测试功能
openclaw mem0 search "test"
```

### 配置迁移

如果配置结构有变化：

```bash
# 比较旧配置和新配置
diff ~/.openclaw/openclaw.json.backup ~/.openclaw/openclaw.json

# 手动迁移配置
# 更新配置文件以匹配新版本的 schema
```

---

## 卸载插件

```bash
# 卸载插件
openclaw plugins uninstall @mem0/openclaw-mem0

# 可选：删除本地文件
rm -rf ~/.openclaw/plugins/@mem0/openclaw-mem0

# 可选：删除记忆文件
# 注意：这会删除所有存储的记忆
rm -f memory.md
rm -rf memory/
```

---

## 高级配置

### 多环境配置

```bash
# 开发环境
export MEM0_ENV="development"
openclaw --config ~/.openclaw/openclaw.dev.json start

# 生产环境
export MEM0_ENV="production"
openclaw --config ~/.openclaw/openclaw.prod.json start
```

### 自定义记忆路径

```json5
{
  "config": {
    "l0Path": "/custom/path/memory.md",
    "l1Dir": "/custom/path/memory"
  }
}
```

### 调试模式

```bash
# 启用调试日志
export DEBUG="openclaw:mem0:*"
export LOG_LEVEL="debug"

# 启动 OpenClaw
openclaw start
```

---

## 文档索引

| 文档 | 用途 |
|------|------|
| [README.md](./README.md) | 快速开始 |
| [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) | 部署指南 |
| [CHANGELOG.md](./CHANGELOG.md) | 版本历史 |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | 架构文档 |
| [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) | Server 部署 |

---

**安装指南版本**: 2.0.0
**最后更新**: 2026-03-07
