# Mem0 项目更新日志

## [2.0.0] - 2026-03-07

### 新增
- ✅ Server 2.0.0 - 多代理支持、API Key 认证、速率限制
- ✅ Plugin v1.0.0 - 三种 Provider 模式、三层记忆架构
- ✅ 生产就绪状态 - 14/14 测试通过（100%）
- ✅ 完整技术文档 - 架构、详细设计、部署、API 文档

### Server (v2.0.0)
- ✅ 多代理实例池（per-agent collection 隔离）
- ✅ Redis 滑动窗口速率限制
- ✅ API Key 管理系统（创建、列表、撤销）
- ✅ Admin 端点（需要 ADMIN_SECRET_KEY）
- ✅ PUT `/memories/{id}` Bug 修复（支持多种请求格式）
- ✅ 健康检查端点（/health）

### Plugin (v1.0.0)
- ✅ 三种 Provider：Platform、Open-Source、Server
- ✅ 三层记忆架构：L0（memory.md）、L1（日期/分类）、L2（向量存储）
- ✅ 自动回忆（auto-recall）- 注入相关记忆到 System Prompt
- ✅ 自动捕获（auto-capture）- 自动存储对话中的关键事实
- ✅ ServerClient HTTP 客户端（axios + 自动重试）
- ✅ L0Manager - memory.md 文件管理
- ✅ L1Manager - 日期/分类文件管理

### 测试
- ✅ 生产测试套件（test_plugin_production.sh）- 14 个测试用例
- ✅ 100% 测试通过率
- ✅ 性能评级：⭐⭐⭐⭐⭐（5/5 星）
- ✅ 多 Agent 隔离验证通过
- ✅ 安全性验证通过

### 文档
- ✅ 总体架构文档（docs/ARCHITECTURE.md）
- ✅ Server 架构设计（server/docs/ARCHITECTURE.md）
- ✅ Server 详细设计（server/docs/DETAILED_DESIGN.md）
- ✅ Server 部署文档（server/docs/DEPLOYMENT.md）
- ✅ Server API 文档（server/docs/API.md）
- ✅ Plugin 架构设计（openclaw/docs/ARCHITECTURE.md）
- ✅ Plugin 详细设计（openclaw/docs/DETAILED_DESIGN.md）
- ✅ Plugin 部署文档（openclaw/docs/DEPLOYMENT.md）

---

## [1.0.0] - 初始版本

### Server
- ✅ FastAPI REST API
- ✅ PostgreSQL + pgvector 向量存储
- ✅ LLM 事实提取
- ✅ 记忆 CRUD 操作

### Plugin
- ✅ Platform 模式（Mem0 云服务）
- ✅ Open-Source 模式（本地 SDK）
- ✅ Server 模式（增强服务器）

---

## 版本说明

### 版本号格式

`主版本号.次版本号.修订号`

- **主版本号**：重大架构变更
- **次版本号**：新功能、重要改进
- **修订号**：Bug 修复、小幅改进

### 状态标记

- ✅ 新增功能
- 🔄 改进
- 🐛 Bug 修复
- 📝 文档更新
- ⚠️ 弃用

---

## 贡献指南

### 提交信息格式

```
<类型>(<范围>): <描述>

[可选的正文]

[可选的页脚]
```

**类型**：
- feat: 新功能
- fix: Bug 修复
- docs: 文档更新
- style: 代码格式
- refactor: 代码重构
- perf: 性能优化
- test: 测试相关
- chore: 构建/工具

**示例**：
```
feat(server): 添加多代理实例池
fix(plugin): 修复 L0Manager 文件权限问题
docs(api): 更新 API 文档
```

---

## 联系方式

- **GitHub**: https://github.com/mem0ai/mem0
- **Issues**: https://github.com/mem0ai/mem0/issues
- **Discord**: https://discord.gg/mem0

---

**更新日志结束**
