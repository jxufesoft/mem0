# Mem0 Plugin 详细设计文档

## 版本信息

- **文档版本**: 2.0.0
- **最后更新**: 2026-03-08
- **Plugin 版本**: v2.0.0

---

## 目录

1. [模块详解](#模块详解)
2. [核心算法](#核心算法)
3. [数据结构](#数据结构)
4. [状态管理](#状态管理)
5. [错误处理](#错误处理)

---

## 模块详解

### 1.1 Plugin Entry (index.ts)

#### 1.1.1 插件初始化

```typescript
export const plugin: OpenClawPlugin = {
  id: "openclaw-mem0",
  kind: "memory",
  name: "Mem0 Memory",
  version: "1.0.0",

  async initialize(config: Mem0Config, api: OpenClawPluginApi) {
    // 1. 解析配置
    const mode = config.mode || "platform";

    // 2. 选择 Provider
    let provider: MemoryProvider;
    switch (mode) {
      case "platform":
        provider = new PlatformProvider(config, api);
        break;
      case "open-source":
        provider = new OSSProvider(config, api);
        break;
      case "server":
        provider = new ServerProvider(config, api);
        break;
      default:
        throw new Error(`Unknown mode: ${mode}`);
    }

    // 3. 初始化 L0 Manager
    const l0Manager = new L0Manager({
      enabled: config.l0Enabled ?? true,
      path: config.l0Path || "./memory.md"
    });

    // 4. 初始化 L1 Manager
    const l1Manager = new L1Manager({
      enabled: config.l1Enabled ?? true,
      dir: config.l1Dir || "./memory",
      recentDays: config.l1RecentDays ?? 7,
      categories: config.l1Categories ?? ["projects", "contacts", "tasks"],
      autoWrite: config.l1AutoWrite ?? true
    });

    // 5. 注册工具
    api.registerTool(memory_search);
    api.registerTool(memory_list);
    api.registerTool(memory_store);
    // ... 其他工具

    // 6. 设置钩子
    api.on("before-turn", async (context) => {
      // 自动回忆：注入相关记忆
      if (config.autoRecall) {
        const systemPrompt = await buildSystemPrompt(
          provider, l0Manager, l1Manager, context
        );
        context.injectSystemPrompt(systemPrompt);
      }
    });

    api.on("after-turn", async (context) => {
      // 自动捕获：存储关键事实
      if (config.autoCapture) {
        await autoCapture(provider, l0Manager, l1Manager, context);
      }
    });
  },

  configSchema: { /* ... */ },
  uiHints: { /* ... */ }
};
```

#### 1.1.2 配置解析

```typescript
interface Mem0Config {
  // 模式选择
  mode: "platform" | "open-source" | "server";

  // Platform 模式
  apiKey?: string;
  orgId?: string;
  projectId?: string;
  customInstructions?: string;
  enableGraph?: boolean;
  customCategories?: Record<string, string>;

  // Server 模式
  serverUrl?: string;
  serverApiKey?: string;
  agentId?: string;

  // 通用配置
  userId?: string;
  autoCapture?: boolean;
  autoRecall?: boolean;
  searchThreshold?: number;
  topK?: number;

  // L0/L1 配置
  l0Enabled?: boolean;
  l0Path?: string;
  l1Enabled?: boolean;
  l1Dir?: string;
  l1RecentDays?: number;
  l1Categories?: string[];
  l1AutoWrite?: boolean;

  // OSS 模式
  oss?: {
    vectorStore?: { provider: string; config: any };
    llm?: { provider: string; config: any };
    embedder?: { provider: string; config: any };
    historyDbPath?: string;
  };
  customPrompt?: string;
}
```

### 1.2 ServerClient

#### 1.2.1 类定义

```typescript
export class ServerClient {
  private client: AxiosInstance;

  constructor(config: ServerConfig) {
    this.client = axios.create({
      baseURL: config.serverUrl,
      headers: {
        "X-API-Key": config.apiKey,
        "Content-Type": "application/json",
      },
    });

    // 配置自动重试
    axiosRetry(this.client, {
      retries: 3,
      retryDelay: axiosRetry.exponentialDelay,
      retryCondition: (error: AxiosError) => {
        // 重试网络错误、5xx 错误、429
        return (
          axiosRetry.isNetworkOrIdempotentRequestError(error) ||
          (error.response?.status ?? 0) >= 500 ||
          error.response?.status === 429
        );
      },
    });
  }
}
```

#### 1.2.2 API 方法

```typescript
export class ServerClient {
  /**
   * 添加记忆
   */
  async add(
    messages: Message[],
    options: {
      user_id: string;
      run_id?: string;
      agent_id?: string;
      metadata?: Record<string, unknown>;
    }
  ): Promise<AddResult> {
    const response = await this.client.post<AddResult>("/memories", {
      messages,
      ...options,
    });
    return response.data;
  }

  /**
   * 搜索记忆
   */
  async search(options: SearchOptions): Promise<MemoryItem[]> {
    const response = await this.client.post<{ results: MemoryItem[] }>(
      "/search",
      options
    );
    return response.data.results || [];
  }

  /**
   * 获取所有记忆
   */
  async list(options: ListOptions): Promise<MemoryItem[]> {
    const params = new URLSearchParams();
    if (options.user_id) params.append("user_id", options.user_id);
    if (options.run_id) params.append("run_id", options.run_id);
    if (options.agent_id) params.append("agent_id", options.agent_id);

    const response = await this.client.get(
      `/memories?${params.toString()}`
    );
    const data = response.data as { results?: MemoryItem[] } | MemoryItem[];
    return Array.isArray(data) ? data : (data.results || []);
  }

  /**
   * 获取单个记忆
   */
  async get(memoryId: string, agent_id?: string): Promise<MemoryItem> {
    const params = agent_id ? `?agent_id=${agent_id}` : "";
    const response = await this.client.get<MemoryItem>(
      `/memories/${memoryId}${params}`
    );
    return response.data;
  }

  /**
   * 删除记忆
   */
  async forget(memoryId: string, agent_id?: string): Promise<void> {
    const params = agent_id ? `?agent_id=${agent_id}` : "";
    await this.client.delete(`/memories/${memoryId}${params}`);
  }

  /**
   * 按查询删除记忆
   */
  async forgetByQuery(query: string, options: SearchOptions): Promise<void> {
    // 先搜索匹配的记忆
    const results = await this.search(options);

    // 删除所有找到的记忆
    await Promise.all(
      results.map((mem) => this.forget(mem.id, options.agent_id)),
    );
  }

  /**
   * 健康检查
   */
  async health(): Promise<HealthStatus> {
    const response = await this.client.get("/health");
    return response.data;
  }
}
```

### 1.3 L0Manager

#### 1.3.1 类定义

```typescript
export class L0Manager {
  constructor(private config: L0Config) {}

  isEnabled(): boolean {
    return this.config.enabled;
  }

  private get filePath(): string {
    return path.resolve(this.config.path);
  }

  private async ensureFile(): Promise<void> {
    try {
      await fs.access(this.filePath);
    } catch {
      await fs.mkdir(path.dirname(this.filePath), { recursive: true });
      await fs.writeFile(
        this.filePath,
        "# Memory\n\n> This file contains important facts and information about you.\n> It is automatically maintained by memory system.\n\n",
      );
    }
  }
}
```

#### 1.3.2 读写方法

```typescript
export class L0Manager {
  /**
   * 读取完整内容
   */
  async readAll(): Promise<string> {
    if (!this.config.enabled) return "";

    try {
      await this.ensureFile();
      return await fs.readFile(this.filePath, "utf-8");
    } catch (error) {
      console.error(`Failed to read L0 memory file: ${error}`);
      return "";
    }
  }

  /**
   * 读取为结构化块
   */
  async readBlock(): Promise<L0Block> {
    const content = await this.readAll();
    let lastModified = 0;

    try {
      const stats = await fs.stat(this.filePath);
      lastModified = stats.mtimeMs;
    } catch {
      // File doesn't exist yet
    }

    return { content, lastModified };
  }

  /**
   * 追加新事实
   */
  async append(fact: string): Promise<void> {
    if (!this.config.enabled) return;

    try {
      await this.ensureFile();
      const content = await fs.readFile(this.filePath, "utf-8");
      const newContent = content.trimEnd() + `\n- ${fact}\n`;
      await fs.writeFile(this.filePath, newContent, "utf-8");
    } catch (error) {
      console.error(`Failed to append to L0 memory file: ${error}`);
    }
  }

  /**
   * 覆盖整个文件
   */
  async overwrite(content: string): Promise<void> {
    if (!this.config.enabled) return;

    try {
      await this.ensureFile();
      await fs.writeFile(this.filePath, content, "utf-8");
    } catch (error) {
      console.error(`Failed to overwrite L0 memory file: ${error}`);
    }
  }
}
```

#### 1.3.3 系统提示格式化

```typescript
export class L0Manager {
  /**
   * 格式化为 System Prompt 块
   */
  async toSystemBlock(): Promise<string> {
    const content = await this.readAll();
    if (!content.trim()) return "";

    return `<!-- L0: Persistent Memory -->\n${content}\n<!-- End L0 -->`;
  }

  /**
   * 提取事实
   */
  extractFacts(content: string): string[] {
    const lines = content.split("\n");
    const facts: string[] = [];

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("- ") || trimmed.match(/^\d+\.\s+/)) {
        const fact = trimmed.replace(/^-\s+|^\d+\.\s+/, "");
        if (fact) facts.push(fact);
      }
    }

    return facts;
  }
}
```

### 1.4 L1Manager

#### 1.4.1 类定义

```typescript
export class L1Manager {
  constructor(private config: L1Config) {}

  isEnabled(): boolean {
    return this.config.enabled;
  }

  private get dirPath(): string {
    return path.resolve(this.config.dir);
  }

  private async ensureDir(): Promise<void> {
    try {
      await fs.mkdir(this.dirPath, { recursive: true });
    } catch (error) {
      console.error(`Failed to create L1 directory: ${error}`);
    }
  }
}
```

#### 1.4.2 文件路径管理

```typescript
export class L1Manager {
  /**
   * 获取日期文件路径
   */
  private getDateFilePath(date: Date): string {
    const dateStr = date.toISOString().split("T")[0]; // YYYY-MM-DD
    return path.join(this.dirPath, `${dateStr}.md`);
  }

  /**
   * 获取分类文件路径
   */
  private getCategoryFilePath(category: string): string {
    return path.join(this.dirPath, `${category}.md`);
  }

  /**
   * 读取文件（如果存在）
   */
  private async readFile(filePath: string): Promise<string> {
    try {
      return await fs.readFile(filePath, "utf-8");
    } catch {
      return "";
    }
  }
}
```

#### 1.4.3 上下文读取

```typescript
export class L1Manager {
  /**
   * 读取最近日期文件和所有分类文件
   */
  async readContext(): Promise<L1Context> {
    if (!this.config.enabled) {
      return { dateFiles: [], categoryFiles: [] };
    }

    try {
      await this.ensureDir();

      // 读取日期文件
      const dateFiles: Array<{ date: string; content: string }> = [];
      const today = new Date();

      for (let i = 0; i < this.config.recentDays; i++) {
        const date = new Date(today);
        date.setDate(date.getDate() - i);
        const filePath = this.getDateFilePath(date);
        const content = await this.readFile(filePath);
        if (content.trim()) {
          dateFiles.push({
            date: date.toISOString().split("T")[0],
            content,
          });
        }
      }

      // 读取分类文件
      const categoryFiles: Array<{ category: string; content: string }> = [];
      for (const category of this.config.categories) {
        const filePath = this.getCategoryFilePath(category);
        const content = await this.readFile(filePath);
        if (content.trim()) {
          categoryFiles.push({ category, content });
        }
      }

      return { dateFiles, categoryFiles };
    } catch (error) {
      console.error(`Failed to read L1 context: ${error}`);
      return { dateFiles: [], categoryFiles: [] };
    }
  }
}
```

#### 1.4.4 内容写入

```typescript
export class L1Manager {
  /**
   * 追加到今天的日期文件
   */
  async appendToday(content: string): Promise<void> {
    if (!this.config.enabled) return;

    try {
      const filePath = this.getDateFilePath(new Date());
      const existing = await this.readFile(filePath);
      await this.writeFile(filePath, existing + content);
    } catch (error) {
      console.error(`Failed to append to today's L1 file: ${error}`);
    }
  }

  /**
   * 追加到分类文件
   */
  async appendToCategory(category: string, content: string): Promise<void> {
    if (!this.config.enabled || !this.config.categories.includes(category)) return;

    try {
      const filePath = this.getCategoryFilePath(category);
      const existing = await this.readFile(filePath);
      await this.writeFile(filePath, existing + content);
    } catch (error) {
      console.error(`Failed to append to L1 category file: ${error}`);
    }
  }
}
```

#### 1.4.5 对话分析

```typescript
export class L1Manager {
  /**
   * 分析对话内容，决定是否写入 L1
   */
  analyzeCapture(conversation: string): L1WriteDecision {
    const text = conversation.toLowerCase();

    // 项目关键词
    const projectKeywords = [
      "project", "repo", "repository", "codebase", "feature", "bug",
      "issue", "pull request", "pr", "commit", "branch", "merge",
    ];

    // 联系人关键词
    const contactKeywords = [
      "contact", "email", "phone", "slack", "discord", "team",
      "colleague", "coworker", "manager", "client", "customer",
    ];

    // 任务关键词
    const taskKeywords = [
      "task", "todo", "to-do", "reminder", "deadline", "schedule",
      "agenda", "meeting", "action item", "follow-up", "need to",
    ];

    const categories: string[] = [];

    if (projectKeywords.some(kw => text.includes(kw))) {
      categories.push("projects");
    }

    if (contactKeywords.some(kw => text.includes(kw))) {
      categories.push("contacts");
    }

    if (taskKeywords.some(kw => text.includes(kw))) {
      categories.push("tasks");
    }

    const shouldWrite = conversation.length > 50 || categories.length > 0;
    const summary = conversation.slice(0, 200).trim() + (conversation.length > 200 ? "..." : "");

    return { shouldWrite, categories, summary };
  }
}
```

---

## 核心算法

### 2.1 自动回忆算法

```typescript
async function buildSystemPrompt(
  provider: MemoryProvider,
  l0Manager: L0Manager,
  l1Manager: L1Manager,
  context: ConversationContext
): Promise<string> {
  const parts: string[] = [];

  // L0: 读取持久记忆
  const l0Content = await l0Manager.readAll();
  if (l0Content.trim()) {
    parts.push(`<!-- L0: Persistent Memory -->\n${l0Content}\n<!-- End L0 -->`);
  }

  // L1: 读取最近上下文
  const l1Context = await l1Manager.readContext();
  const l1Parts: string[] = [];

  for (const file of l1Context.dateFiles) {
    if (file.content.trim()) {
      l1Parts.push(`### ${file.date}\n${file.content.trim()}`);
    }
  }

  for (const file of l1Context.categoryFiles) {
    if (file.content.trim()) {
      l1Parts.push(`### ${file.category}\n${file.content.trim()}`);
    }
  }

  if (l1Parts.length > 0) {
    parts.push(`<!-- L1: Recent Context -->\n${l1Parts.join("\n\n")}\n<!-- End L1 -->`);
  }

  // L2: 向量搜索相关记忆
  const query = extractQueryFromContext(context);
  const searchResults = await provider.search(query, {
    user_id: context.userId,
    limit: 5,
  });

  if (searchResults.length > 0) {
    const l2Parts = searchResults.map(m => `- ${m.memory}`).join("\n");
    parts.push(`<!-- L2: Relevant Memories -->\n${l2Parts}\n<!-- End L2 -->`);
  }

  return parts.join("\n\n");
}
```

### 2.2 自动捕获算法

```typescript
async function autoCapture(
  provider: MemoryProvider,
  l0Manager: L0Manager,
  l1Manager: L1Manager,
  context: ConversationContext
): Promise<void> {
  const lastMessage = context.messages[context.messages.length - 1];
  if (!lastMessage || lastMessage.role !== "assistant") return;

  // L1: 写入到日期/分类文件
  const conversation = context.messages.map(m => m.content).join("\n");
  const l1Decision = await l1Manager.writeFromConversation(conversation);

  // L2: 通过 Provider 存储到向量数据库
  await provider.add(context.messages, {
    user_id: context.userId,
    agent_id: context.agentId,
    run_id: context.runId,
  });
}
```

---

## 数据结构

### 3.1 类型定义

```typescript
// 消息类型
interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

// 记忆项
interface MemoryItem {
  id: string;
  memory: string;
  user_id?: string;
  agent_id?: string;
  run_id?: string;
  score?: number;
  categories?: string[];
  metadata?: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
}

// 添加结果
interface AddResult {
  results: Array<{
    id: string;
    memory: string;
    event: "ADD" | "UPDATE" | "DELETE" | "NOOP";
  }>;
  relations?: Array<{
    from: string;
    to: string;
    type: string;
  }>;
}

// 搜索选项
interface SearchOptions {
  query: string;
  user_id?: string;
  run_id?: string;
  agent_id?: string;
  limit?: number;
  filters?: Record<string, unknown>;
}

// 列表选项
interface ListOptions {
  user_id?: string;
  run_id?: string;
  agent_id?: string;
}

// 健康状态
interface HealthStatus {
  status: string;
  loaded_agents: number;
  redis: string;
}

// L0 配置
interface L0Config {
  enabled: boolean;
  path: string;
}

// L0 块
interface L0Block {
  content: string;
  lastModified: number;
}

// L1 配置
interface L1Config {
  enabled: boolean;
  dir: string;
  recentDays: number;
  categories: string[];
  autoWrite: boolean;
}

// L1 上下文
interface L1Context {
  dateFiles: Array<{ date: string; content: string }>;
  categoryFiles: Array<{ category: string; content: string }>;
}

// L1 写入决策
interface L1WriteDecision {
  shouldWrite: boolean;
  categories: string[];
  summary?: string;
}
```

---

## 状态管理

### 4.1 配置状态

```typescript
class ConfigManager {
  private config: Mem0Config;
  private provider: MemoryProvider;
  private l0Manager: L0Manager;
  private l1Manager: L1Manager;

  updateConfig(newConfig: Partial<Mem0Config>): void {
    // 合并配置
    this.config = { ...this.config, ...newConfig };

    // 重新初始化组件
    this.reinitialize();
  }

  private reinitialize(): void {
    // 更新 L0 Manager
    this.l0Manager = new L0Manager({
      enabled: this.config.l0Enabled ?? true,
      path: this.config.l0Path || "./memory.md"
    });

    // 更新 L1 Manager
    this.l1Manager = new L1Manager({
      enabled: this.config.l1Enabled ?? true,
      dir: this.config.l1Dir || "./memory",
      recentDays: this.config.l1RecentDays ?? 7,
      categories: this.config.l1Categories ?? ["projects", "contacts", "tasks"],
      autoWrite: this.config.l1AutoWrite ?? true
    });

    // 更新 Provider
    this.provider = this.createProvider();
  }
}
```

### 4.2 缓存策略

```typescript
class MemoryCache {
  private cache: Map<string, { data: any; expiry: number }>;
  private ttl: number = 300000; // 5 分钟

  get(key: string): any | null {
    const item = this.cache.get(key);
    if (!item) return null;

    if (Date.now() > item.expiry) {
      this.cache.delete(key);
      return null;
    }

    return item.data;
  }

  set(key: string, data: any): void {
    this.cache.set(key, {
      data,
      expiry: Date.now() + this.ttl
    });
  }

  clear(): void {
    this.cache.clear();
  }
}
```

---

## 错误处理

### 5.1 错误分类

| 错误类型 | 处理方式 |
|----------|----------|
| **网络错误** | 自动重试（最多 3 次）|
| **超时错误** | 自动重试（指数退避）|
| **5xx 错误** | 自动重试（最多 3 次）|
| **429 错误** | 自动重试（指数退避）|
| **4xx 错误** | 返回错误，不重试 |
| **认证错误** | 返回错误，不重试 |

### 5.2 重试策略

```typescript
axiosRetry(client, {
  retries: 3,
  retryDelay: axiosRetry.exponentialDelay,
  retryCondition: (error: AxiosError) => {
    return (
      // 网络错误
      axiosRetry.isNetworkOrIdempotentRequestError(error) ||
      // 5xx 错误
      (error.response?.status ?? 0) >= 500 ||
      // 速率限制
      error.response?.status === 429
    );
  },
  onRetry: (retryCount, error, requestConfig) => {
    console.log(`Retrying request (${retryCount}/3)...`, {
      error: error.message,
      url: requestConfig.url
    });
  }
});
```

### 5.3 错误日志

```typescript
function logError(error: unknown, context: string): void {
  if (error instanceof Error) {
    console.error(`[${context}] ${error.message}`, {
      stack: error.stack,
      name: error.name
    });
  } else {
    console.error(`[${context}] Unknown error:`, error);
  }
}
```

---

**文档结束**

## 安装和部署

本设计文档中描述的 Plugin 的安装和部署：

### 快速安装

\`\`\`bash
# 从打包文件安装
openclaw plugins install ./mem0-openclaw-mem0-2.0.0.tgz
\`\`\`

### 源码构建

\`\`\`bash
# 从源码构建
cd /home/yhz/project/mem0/openclaw
npm install
npm run test
npm pack
\`\`\`

### 详细文档

- [INSTALLATION_GUIDE.md](../INSTALLATION_GUIDE.md) - 完整安装指南
- [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) - 部署指南
- [PACKAGE_REPORT.md](../PACKAGE_REPORT.md) - 包信息和验证

---

**文档版本**: 2.0.0
**最后更新**: 2026-03-07
