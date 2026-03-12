# Mem0 Plugin 架构设计文档

## 版本信息

- **文档版本**: 2.0.0 (更新: 2026-03-07)
- **最后更新**: 2026-03-07
- **Plugin 版本**: v2.0.0

---

## 目录

1. [架构概述](#架构概述)
2. [技术选型](#技术选型)
3. [模块设计](#模块设计)
4. [三层记忆架构](#三层记忆架构)
5. [Provider 架构](#provider-架构)
6. [工具系统](#工具系统)

---

## 架构概述

### 1.1 设计目标

| 目标 | 描述 | 优先级 |
|------|------|--------|
| **多模式支持** | 支持 Platform、Open-Source、Server 三种模式 | P0 |
| **三层记忆** | L0/L1/L2 分层记忆架构 | P0 |
| **自动回忆** | 自动注入相关记忆到对话上下文 | P0 |
| **自动捕获** | 自动存储对话中的关键事实 | P1 |
| **性能优化** | 快速访问、低延迟 | P1 |

### 1.2 整体架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                    OpenClaw Platform                           │
│                    (Plugin Host)                                │
└──────────────────────────────┬────────────────────────────────────┘
                               │
                               │ Plugin SDK
                               │
        ┌──────────────────────────▼───────────────────────────────┐
        │                 Mem0 Plugin                          │
        │  ────────────────────────────────────────────         │
        │                                                     │
        │  ┌───────────────────────────────────────────────┐     │
        │  │         Plugin Entry (index.ts)              │     │
        │  │  ───────────────────────────────────────     │     │
        │  │  · Plugin 初始化                            │     │
        │  │  · 配置解析                                │     │
        │  │  · Provider 选择                           │     │
        │  │  · 工具注册                                │     │
        │  └───────────────────────────────────────────────┘     │
        │                     │                                   │
        │        ┌────────────┴────────────┐                    │
        │        │                         │                    │
        │        ▼                         ▼                    │
        │  ┌───────────┐          ┌───────────┐               │
        │  │ Providers │          │ Managers   │               │
        │  ────────────┘          ────────────┘               │
        │                                                     │
        │  ┌───────────────────────────────────────────────┐     │
        │  │           Providers (Provider Pattern)         │     │
        │  │  ──────────────────────────────────         │     │
        │  │  ┌──────────┐  ┌──────────┐            │     │
        │  │  │Platform  │  │  OSS     │            │     │
        │  │  │Provider  │  │Provider  │            │     │
        │  │  └──────────┘  └──────────┘            │     │
        │  │  ┌──────────┐                            │     │
        │  │  │ Server    │                            │     │
        │  │  │Provider  │                            │     │
        │  │  └──────────┘                            │     │
        │  └───────────────────────────────────────────────┘     │
        │                                                     │
        │  ┌───────────────────────────────────────────────┐     │
        │  │              Managers                       │     │
        │  │  ──────────────────────────────────         │     │
        │  │  ┌──────────┐  ┌──────────┐            │     │
        │  │  │L0Manager │  │L1Manager │            │     │
        │  │  │(L0 Layer)│  │(L1 Layer)│            │     │
        │  │  └──────────┘  └──────────┘            │     │
        │  └───────────────────────────────────────────────┘     │
        │                                                     │
        │  ┌───────────────────────────────────────────────┐     │
        │  │          ServerClient (HTTP Client)          │     │
        │  │  ──────────────────────────────────         │     │
        │  │  · Axios HTTP Client                     │     │
        │  │  · 自动重试 (3 次)                    │     │
        │  │  · 错误处理                           │     │
        │  └───────────────────────────────────────────────┘     │
        │                     │                                   │
        └─────────────────────┼────────────────────────────────────┘
                              │
        ┌─────────────────────┴────────────────────────────────────┐
        │                                                      │
        ▼                                                      ▼
┌───────────────────┐                                 ┌───────────────────┐
│  Mem0 Platform   │                                 │ Mem0 Enhanced    │
│  (Cloud Service)  │                                 │ Server           │
│                  │                                 │                  │
│  · REST API       │                                 │  · REST API       │
│  · LLM/Embedding │                                 │  · LLM/Embedding │
│  · Vector Store   │                                 │  · Vector Store   │
└───────────────────┘                                 └───────────────────┘
```

---

## 技术选型

### 2.1 核心技术

| 技术 | 版本 | 选型理由 |
|------|------|----------|
| **TypeScript** | 5.x | 类型安全、IDE 支持 |
| **OpenClaw Plugin SDK** | Latest | 标准 Plugin 接口 |
| **Axios** | Latest | HTTP 客户端、自动重试 |
| **axios-retry** | Latest | 指数退避重试 |

### 2.2 Node.js 依赖

| 包 | 版本 | 用途 |
|------|------|------|
| `@openclaw/plugin-sdk` | Latest | Plugin 开发框架 |
| `axios` | Latest | HTTP 请求 |
| `axios-retry` | Latest | 自动重试 |
| `mem0ai` | Latest | Mem0 SDK（OSS 模式）|

---

## 模块设计

### 3.1 目录结构

```
openclaw/
├── index.ts                    # Plugin 入口
├── openclaw.plugin.json       # Plugin 配置
├── package.json              # 依赖配置
├── README.md                # 文档
└── lib/
    ├── server-client.ts      # HTTP 客户端
    ├── l0-manager.ts       # L0 层管理器
    ├── l1-manager.ts       # L1 层管理器
    └── utils/
        └── memory.ts       # 记忆工具函数
```

### 3.2 Plugin Entry (index.ts)

**职责**：Plugin 初始化、Provider 选择、工具注册

```typescript
export const plugin: OpenClawPlugin = {
  // Plugin 信息
  id: "openclaw-mem0",
  kind: "memory",
  name: "Mem0 Memory",
  version: "1.0.0",

  // 初始化函数
  async initialize(config: Mem0Config, api: OpenClawPluginApi) {
    // 解析配置
    // 选择 Provider
    // 初始化 Managers
    // 注册工具
  },

  // 配置 Schema
  configSchema: { /* ... */ },
  uiHints: { /* ... */ }
};
```

### 3.3 Provider Pattern

**职责**：统一接口适配不同后端

```typescript
// Provider 接口
interface MemoryProvider {
  add(messages: Message[], options: AddOptions): Promise<AddResult>;
  search(query: string, options: SearchOptions): Promise<MemoryItem[]>;
  list(options: ListOptions): Promise<MemoryItem[]>;
  get(id: string, agentId?: string): Promise<MemoryItem>;
  forget(id: string, agentId?: string): Promise<void>;
  forgetByQuery(query: string, options: SearchOptions): Promise<void>;
  health(): Promise<HealthStatus>;
}

// PlatformProvider
class PlatformProvider implements MemoryProvider {
  // 使用 Mem0 Platform API
}

// OSSProvider
class OSSProvider implements MemoryProvider {
  // 使用本地 Mem0 SDK
}

// ServerProvider
class ServerProvider implements MemoryProvider {
  // 使用 ServerClient 与 Enhanced Server 通信
}
```

### 3.4 L0Manager

**职责**：L0 层 memory.md 文件管理

```typescript
class L0Manager {
  private config: L0Config;

  async readAll(): Promise<string> { /* ... */ }
  async readBlock(): Promise<L0Block> { /* ... */ }
  async append(fact: string): Promise<void> { /* ... */ }
  async overwrite(content: string): Promise<void> { /* ... */ }
  async toSystemBlock(): Promise<string> { /* ... */ }
  extractFacts(content: string): string[] { /* ... */ }
}
```

### 3.5 L1Manager

**职责**：L1 层日期/分类文件管理

```typescript
class L1Manager {
  private config: L1Config;

  async readContext(): Promise<L1Context> { /* ... */ }
  async appendToday(content: string): Promise<void> { /* ... */ }
  async appendToCategory(category: string, content: string): Promise<void> { /* ... */ }
  async toSystemBlock(): Promise<string> { /* ... */ }
  analyzeCapture(conversation: string): L1WriteDecision { /* ... */ }
}
```

---

## 三层记忆架构

### 4.1 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      三层记忆架构                              │
│                                                           │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  L0: 持久记忆层 (Memory.md)                   │    │
│  │  ───────────────────────────────────────         │    │
│  │  · 单文件存储                                      │    │
│  │  · 最快访问                                        │    │
│  │  · 最重要的用户事实                                │    │
│  └───────────────────────────────────────────────────────┘    │
│                         │                                      │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  L1: 结构化层 (日期/分类文件)                   │    │
│  │  ───────────────────────────────────────         │    │
│  │  · 2026-03-07.md                                │    │
│  │  · projects.md, contacts.md, tasks.md              │    │
│  │  · 最近的对话上下文                               │    │
│  └───────────────────────────────────────────────────────┘    │
│                         │                                      │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  L2: 向量层 (Server/OSS/Platform)              │    │
│  │  ───────────────────────────────────────         │    │
│  │  · PostgreSQL + pgvector                          │    │
│  │  · 语义相似度搜索                               │    │
│  │  · 所有提取的事实                                │    │
│  └───────────────────────────────────────────────────────┘    │
│                                                           │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 数据流

```
自动回忆流程:
┌──────────────┐
│ 对话开始     │
└──────┬───────┘
       │
       ▼
┌─────────────────────────────────┐
│  读取 L0 (memory.md)       │
│  读取 L1 (日期/分类文件)   │
│  读取 L2 (向量搜索)        │
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│  合并为 System Prompt       │
│  格式:                    │
│  <!-- L0 -->              │
│  ...content...            │
│  <!-- End L0 -->          │
│  <!-- L1 -->              │
│  ...content...            │
│  <!-- End L1 -->          │
│  <!-- L2 -->              │
│  ...results...           │
│  <!-- End L2 -->          │
└────────────┬────────────────┘
             │
             ▼
┌──────────────┐
│ 注入到对话  │
└──────────────┘
```

---

## Provider 架构

### 5.1 PlatformProvider

**连接方式**：Mem0 Platform REST API

**配置**：
```typescript
interface PlatformConfig {
  apiKey: string;                    // Mem0 Cloud API Key
  orgId?: string;                   // 组织 ID（可选）
  projectId?: string;               // 项目 ID（可选）
  userId?: string;                  // 用户标识
  customInstructions?: string;      // 自定义指令
  customCategories?: Record<string, string>; // 自定义分类
  enableGraph?: boolean;            // 启用关系图谱
  searchThreshold?: number;         // 搜索相似度阈值
  topK?: number;                    // 返回结果数
}
```

**特性**：
- ✅ 云托管
- ✅ 自动扩展
- ✅ 图记忆支持
- ✅ 自定义类别
- ⚠️ 需要网络连接

### 5.2 OSSProvider

**连接方式**：本地 Mem0 SDK

**配置**：
```typescript
interface OSSConfig {
  userId?: string;                  // 用户标识
  customPrompt?: string;             // 自定义系统提示词
  searchThreshold?: number;         // 搜索相似度阈值
  topK?: number;                    // 返回结果数
  oss?: {
    vectorStore?: { provider: string; config: any };  // 向量存储
    llm?: { provider: string; config: any };          // LLM
    embedder?: { provider: string; config: any };      // Embedder
    historyDbPath?: string;                           // 历史数据库
  };
}
```

**特性**：
- ✅ 完全自托管
- ✅ 数据隐私
- ✅ 无网络依赖
- ⚠️ 需要自行维护
- ⚠️ 需要配置向量存储/LLM

### 5.3 ServerProvider

**连接方式**：Enhanced Server REST API

**配置**：
```typescript
interface ServerConfig {
  serverUrl: string;
  apiKey: string;
  agentId?: string;
  userId?: string;
  searchThreshold?: number;
  topK?: number;
}
```

**特性**：
- ✅ 自托管（但由 Server 管理）
- ✅ 多代理隔离
- ✅ 速率限制
- ✅ 认证
- ⚠️ 需要运行 Server

---

## 工具系统

### 6.1 工具列表

| 工具 | 描述 | Provider |
|------|------|----------|
| `memory_search` | 搜索记忆 | All |
| `memory_list` | 列出记忆 | All |
| `memory_store` | 存储记忆 | All |
| `memory_get` | 获取单个记忆 | Server, OSS |
| `memory_forget` | 删除记忆 | Server, OSS |
| `memory_l0_update` | 更新 L0 记忆 | All |
| `memory_l1_write` | 写入 L1 记忆 | All |

### 6.2 工具 Schema

```typescript
// memory_search
{
  name: "memory_search",
  description: "Search for relevant memories",
  inputSchema: {
    query: { type: "string" },
    limit: { type: "number", default: 5 }
  }
}

// memory_store
{
  name: "memory_store",
  description: "Store a new memory",
  inputSchema: {
    content: { type: "string" },
    metadata: { type: "object" }
  }
}

// memory_l0_update
{
  name: "memory_l0_update",
  description: "Update L0 persistent memory",
  inputSchema: {
    action: { type: "string", enum: ["append", "replace"] },
    content: { type: "string" }
  }
}
```

---

## 附录

### A. 配置优先级

配置解析顺序：
1. 环境变量
2. Plugin 配置（openclaw.plugin.json）
3. 运行时参数

### B. 错误处理

| 错误类型 | 处理方式 |
|----------|----------|
| **网络错误** | 自动重试（最多 3 次）|
| **API 错误 5xx** | 指数退避重试 |
| **认证错误** | 返回错误，不重试 |
| **超时** | 返回超时错误 |

---

**文档结束**
