/**
 * OpenClaw Memory (Mem0) Plugin
 *
 * Long-term memory via Mem0 — supports the Mem0 platform,
 * the open-source self-hosted SDK, and the enhanced Mem0 Server.
 * Uses the official `mem0ai` package.
 *
 * Features:
 * - 7 tools: memory_search, memory_list, memory_store, memory_get, memory_forget,
 *   memory_l0_update, memory_l1_write
 * - Short-term (session-scoped) and long-term (user-scoped) memory
 * - Auto-recall: injects relevant memories (both scopes) before each agent turn
 * - Auto-capture: stores key facts scoped to the current session after each agent turn
 * - CLI: openclaw mem0 search, openclaw mem0 stats
 * - Triple mode: platform, open-source (self-hosted), or server (enhanced)
 * - Three-tier memory: L0 (memory.md) + L1 (date/category files) + L2 (vector search)
 */

import { Type } from "@sinclair/typebox";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { ServerClient } from "./lib/server-client.js";
import { runSetup, MemoryOptimizer } from "./lib/setup.js";
import { L0Manager } from "./lib/l0-manager.js";
import { L1Manager } from "./lib/l1-manager.js";

// ============================================================================
// Types
// ============================================================================

type Mem0Mode = "platform" | "open-source" | "server";

type Mem0Config = {
  mode: Mem0Mode;
  // Platform-specific
  apiKey?: string;
  orgId?: string;
  projectId?: string;
  customInstructions: string;
  customCategories: Record<string, string>;
  enableGraph: boolean;
  // OSS-specific
  customPrompt?: string;
  oss?: {
    embedder?: { provider: string; config: Record<string, unknown> };
    vectorStore?: { provider: string; config: Record<string, unknown> };
    llm?: { provider: string; config: Record<string, unknown> };
    historyDbPath?: string;
  };
  // Server-specific
  serverUrl?: string;
  serverApiKey?: string;
  agentId?: string;
  // L0 Layer (memory.md)
  l0Enabled?: boolean;
  l0Path?: string;
  // L1 Layer (date/category files)
  l1Enabled?: boolean;
  l1Dir?: string;
  l1RecentDays?: number;
  l1Categories?: string[];
  l1AutoWrite?: boolean;
  // Shared
  userId: string;
  autoCapture: boolean;
  autoRecall: boolean;
  searchThreshold: number;
  topK: number;
  // Optimization triggers
  contextThresholdKB?: number;  // Context size threshold in KB (default: 50)
  messageThreshold?: number;    // Message count threshold (default: 10)
};

// Unified types for the provider interface
interface AddOptions {
  user_id: string;
  run_id?: string;
  custom_instructions?: string;
  custom_categories?: Array<Record<string, string>>;
  enable_graph?: boolean;
  output_format?: string;
  source?: string;
}

interface SearchOptions {
  user_id: string;
  run_id?: string;
  top_k?: number;
  threshold?: number;
  limit?: number;
  keyword_search?: boolean;
  reranking?: boolean;
  source?: string;
}

interface ListOptions {
  user_id: string;
  run_id?: string;
  page_size?: number;
  source?: string;
}

interface MemoryItem {
  id: string;
  memory: string;
  user_id?: string;
  score?: number;
  categories?: string[];
  metadata?: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
}

interface AddResultItem {
  id: string;
  memory: string;
  event: "ADD" | "UPDATE" | "DELETE" | "NOOP";
}

interface AddResult {
  results: AddResultItem[];
}

// ============================================================================
// Unified Provider Interface
// ============================================================================

interface Mem0Provider {
  add(
    messages: Array<{ role: string; content: string }>,
    options: AddOptions,
  ): Promise<AddResult>;
  search(query: string, options: SearchOptions): Promise<MemoryItem[]>;
  get(memoryId: string): Promise<MemoryItem>;
  getAll(options: ListOptions): Promise<MemoryItem[]>;
  delete(memoryId: string): Promise<void>;
}

// ============================================================================
// Platform Provider (Mem0 Cloud)
// ============================================================================

class PlatformProvider implements Mem0Provider {
  private client: any; // MemoryClient from mem0ai
  private initPromise: Promise<void> | null = null;

  constructor(
    private readonly apiKey: string,
    private readonly orgId?: string,
    private readonly projectId?: string,
  ) { }

  private async ensureClient(): Promise<void> {
    if (this.client) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this._init();
    return this.initPromise;
  }

  private async _init(): Promise<void> {
    const { default: MemoryClient } = await import("mem0ai");
    const opts: { apiKey: string; organizationId?: string | null; projectId?: string | null } = { apiKey: this.apiKey };
    if (this.orgId) opts.organizationId = this.orgId;
    if (this.projectId) opts.projectId = this.projectId;
    this.client = new MemoryClient(opts);
  }

  async add(
    messages: Array<{ role: string; content: string }>,
    options: AddOptions,
  ): Promise<AddResult> {
    await this.ensureClient();
    const opts: Record<string, unknown> = { user_id: options.user_id };
    if (options.run_id) opts.run_id = options.run_id;
    if (options.custom_instructions)
      opts.custom_instructions = options.custom_instructions;
    if (options.custom_categories)
      opts.custom_categories = options.custom_categories;
    if (options.enable_graph) opts.enable_graph = options.enable_graph;
    if (options.output_format) opts.output_format = options.output_format;
    if (options.source) opts.source = options.source;

    const result = await this.client.add(messages, opts);
    return normalizeAddResult(result);
  }

  async search(query: string, options: SearchOptions): Promise<MemoryItem[]> {
    await this.ensureClient();
    const opts: Record<string, unknown> = { user_id: options.user_id };
    if (options.run_id) opts.run_id = options.run_id;
    if (options.top_k != null) opts.top_k = options.top_k;
    if (options.threshold != null) opts.threshold = options.threshold;
    if (options.keyword_search != null) opts.keyword_search = options.keyword_search;
    if (options.reranking != null) opts.reranking = options.reranking;
    if (options.source) opts.source = options.source;

    const results = await this.client.search(query, opts);
    return normalizeSearchResults(results);
  }

  async get(memoryId: string): Promise<MemoryItem> {
    await this.ensureClient();
    const result = await this.client.get(memoryId);
    return normalizeMemoryItem(result);
  }

  async getAll(options: ListOptions): Promise<MemoryItem[]> {
    await this.ensureClient();
    const opts: Record<string, unknown> = { user_id: options.user_id };
    if (options.run_id) opts.run_id = options.run_id;
    if (options.page_size != null) opts.page_size = options.page_size;
    if (options.source) opts.source = options.source;

    const results = await this.client.getAll(opts);
    if (Array.isArray(results)) return results.map(normalizeMemoryItem);
    // Some versions return { results: [...] }
    if (results?.results && Array.isArray(results.results))
      return results.results.map(normalizeMemoryItem);
    return [];
  }

  async delete(memoryId: string): Promise<void> {
    await this.ensureClient();
    await this.client.delete(memoryId);
  }
}

// ============================================================================
// Open-Source Provider (Self-hosted)
// ============================================================================

class OSSProvider implements Mem0Provider {
  private memory: any; // Memory from mem0ai/oss
  private initPromise: Promise<void> | null = null;

  constructor(
    private readonly ossConfig?: Mem0Config["oss"],
    private readonly customPrompt?: string,
    private readonly resolvePath?: (p: string) => string,
  ) { }

  private async ensureMemory(): Promise<void> {
    if (this.memory) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this._init();
    return this.initPromise;
  }

  private async _init(): Promise<void> {
    const { Memory } = await import("mem0ai/oss");

    const config: Record<string, unknown> = { version: "v1.1" };

    if (this.ossConfig?.embedder) config.embedder = this.ossConfig.embedder;
    if (this.ossConfig?.vectorStore)
      config.vectorStore = this.ossConfig.vectorStore;
    if (this.ossConfig?.llm) config.llm = this.ossConfig.llm;

    if (this.ossConfig?.historyDbPath) {
      const dbPath = this.resolvePath
        ? this.resolvePath(this.ossConfig.historyDbPath)
        : this.ossConfig.historyDbPath;
      config.historyDbPath = dbPath;
    }

    if (this.customPrompt) config.customPrompt = this.customPrompt;

    this.memory = new Memory(config);
  }

  async add(
    messages: Array<{ role: string; content: string }>,
    options: AddOptions,
  ): Promise<AddResult> {
    await this.ensureMemory();
    // OSS SDK uses camelCase: userId/runId, not user_id/run_id
    const addOpts: Record<string, unknown> = { userId: options.user_id };
    if (options.run_id) addOpts.runId = options.run_id;
    if (options.source) addOpts.source = options.source;
    const result = await this.memory.add(messages, addOpts);
    return normalizeAddResult(result);
  }

  async search(query: string, options: SearchOptions): Promise<MemoryItem[]> {
    await this.ensureMemory();
    // OSS SDK uses camelCase: userId/runId, not user_id/run_id
    const opts: Record<string, unknown> = { userId: options.user_id };
    if (options.run_id) opts.runId = options.run_id;
    if (options.limit != null) opts.limit = options.limit;
    else if (options.top_k != null) opts.limit = options.top_k;
    if (options.keyword_search != null) opts.keyword_search = options.keyword_search;
    if (options.reranking != null) opts.reranking = options.reranking;
    if (options.source) opts.source = options.source;
    if (options.threshold != null) opts.threshold = options.threshold;

    const results = await this.memory.search(query, opts);
    const normalized = normalizeSearchResults(results);

    // Filter results by threshold if specified (client-side filtering as fallback)
    if (options.threshold != null) {
      return normalized.filter(item => (item.score ?? 0) >= options.threshold!);
    }

    return normalized;
  }

  async get(memoryId: string): Promise<MemoryItem> {
    await this.ensureMemory();
    const result = await this.memory.get(memoryId);
    return normalizeMemoryItem(result);
  }

  async getAll(options: ListOptions): Promise<MemoryItem[]> {
    await this.ensureMemory();
    // OSS SDK uses camelCase: userId/runId, not user_id/run_id
    const getAllOpts: Record<string, unknown> = { userId: options.user_id };
    if (options.run_id) getAllOpts.runId = options.run_id;
    if (options.source) getAllOpts.source = options.source;
    const results = await this.memory.getAll(getAllOpts);
    if (Array.isArray(results)) return results.map(normalizeMemoryItem);
    if (results?.results && Array.isArray(results.results))
      return results.results.map(normalizeMemoryItem);
    return [];
  }

  async delete(memoryId: string): Promise<void> {
    await this.ensureMemory();
    await this.memory.delete(memoryId);
  }
}

// ============================================================================
// Server Provider (Enhanced Mem0 Server)
// ============================================================================

class ServerProvider implements Mem0Provider {
  private client: ServerClient;

  constructor(
    serverUrl: string,
    apiKey: string,
    private readonly agentId?: string,
  ) {
    this.client = new ServerClient({ serverUrl, apiKey });
  }

  async add(
    messages: Array<{ role: string; content: string }>,
    options: AddOptions,
  ): Promise<AddResult> {
    const result = await this.client.add(messages, {
      user_id: options.user_id,
      run_id: options.run_id,
      agent_id: this.agentId,
    });
    return result;
  }

  async search(query: string, options: SearchOptions): Promise<MemoryItem[]> {
    const results = await this.client.search({
      query,
      user_id: options.user_id,
      run_id: options.run_id,
      agent_id: this.agentId,
      limit: options.limit ?? options.top_k,
    });

    // Filter by threshold if specified
    if (options.threshold != null) {
      return results.filter(item => (item.score ?? 0) >= options.threshold!);
    }
    return results;
  }

  async get(memoryId: string): Promise<MemoryItem> {
    return await this.client.get(memoryId, this.agentId);
  }

  async getAll(options: ListOptions): Promise<MemoryItem[]> {
    return await this.client.list({
      user_id: options.user_id,
      run_id: options.run_id,
      agent_id: this.agentId,
    });
  }

  async delete(memoryId: string): Promise<void> {
    await this.client.forget(memoryId, this.agentId);
  }
}

// ============================================================================
// Result Normalizers
// ============================================================================

function normalizeMemoryItem(raw: any): MemoryItem {
  return {
    id: raw.id ?? raw.memory_id ?? "",
    memory: raw.memory ?? raw.text ?? raw.content ?? "",
    // Handle both platform (user_id, created_at) and OSS (userId, createdAt) field names
    user_id: raw.user_id ?? raw.userId,
    score: raw.score,
    categories: raw.categories,
    metadata: raw.metadata,
    created_at: raw.created_at ?? raw.createdAt,
    updated_at: raw.updated_at ?? raw.updatedAt,
  };
}

function normalizeSearchResults(raw: any): MemoryItem[] {
  // Platform API returns flat array, OSS returns { results: [...] }
  if (Array.isArray(raw)) return raw.map(normalizeMemoryItem);
  if (raw?.results && Array.isArray(raw.results))
    return raw.results.map(normalizeMemoryItem);
  return [];
}

function normalizeAddResult(raw: any): AddResult {
  // Handle { results: [...] } shape (both platform and OSS)
  if (raw?.results && Array.isArray(raw.results)) {
    return {
      results: raw.results.map((r: any) => ({
        id: r.id ?? r.memory_id ?? "",
        memory: r.memory ?? r.text ?? "",
        // Platform API may return PENDING status (async processing)
        // OSS stores event in metadata.event
        event: r.event ?? r.metadata?.event ?? (r.status === "PENDING" ? "ADD" : "ADD"),
      })),
    };
  }
  // Platform API without output_format returns flat array
  if (Array.isArray(raw)) {
    return {
      results: raw.map((r: any) => ({
        id: r.id ?? r.memory_id ?? "",
        memory: r.memory ?? r.text ?? "",
        event: r.event ?? r.metadata?.event ?? (r.status === "PENDING" ? "ADD" : "ADD"),
      })),
    };
  }
  return { results: [] };
}

// ============================================================================
// Config Parser
// ============================================================================

function resolveEnvVars(value: string): string {
  return value.replace(/\$\{([^}]+)\}/g, (_, envVar) => {
    const envValue = process.env[envVar];
    if (!envValue) {
      throw new Error(`Environment variable ${envVar} is not set`);
    }
    return envValue;
  });
}

function resolveEnvVarsDeep(obj: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === "string") {
      result[key] = resolveEnvVars(value);
    } else if (value && typeof value === "object" && !Array.isArray(value)) {
      result[key] = resolveEnvVarsDeep(value as Record<string, unknown>);
    } else {
      result[key] = value;
    }
  }
  return result;
}

// ============================================================================
// Default Custom Instructions & Categories
// ============================================================================

const DEFAULT_CUSTOM_INSTRUCTIONS = `Your Task: Extract and maintain a structured, evolving profile of the user from their conversations with an AI assistant. Capture information that would help the assistant provide personalized, context-aware responses in future interactions.

Information to Extract:

1. Identity & Demographics:
   - Name, age, location, timezone, language preferences
   - Occupation, employer, job role, industry
   - Education background

2. Preferences & Opinions:
   - Communication style preferences (formal/casual, verbose/concise)
   - Tool and technology preferences (languages, frameworks, editors, OS)
   - Content preferences (topics of interest, learning style)
   - Strong opinions or values they've expressed
   - Likes and dislikes they've explicitly stated

3. Goals & Projects:
   - Current projects they're working on (name, description, status)
   - Short-term and long-term goals
   - Deadlines and milestones mentioned
   - Problems they're actively trying to solve

4. Technical Context:
   - Tech stack and tools they use
   - Skill level in different areas (beginner/intermediate/expert)
   - Development environment and setup details
   - Recurring technical challenges

5. Relationships & People:
   - Names and roles of people they mention (colleagues, family, friends)
   - Team structure and dynamics
   - Key contacts and their relevance

6. Decisions & Lessons:
   - Important decisions made and their reasoning
   - Lessons learned from past experiences
   - Strategies that worked or failed
   - Changed opinions or updated beliefs

7. Routines & Habits:
   - Daily routines and schedules mentioned
   - Work patterns (when they're productive, how they organize work)
   - Health and wellness habits if voluntarily shared

8. Life Events:
   - Significant events (new job, moving, milestones)
   - Upcoming events or plans
   - Changes in circumstances

Guidelines:
- Store memories as clear, self-contained statements (each memory should make sense on its own)
- Use third person: "User prefers..." not "I prefer..."
- Include temporal context when relevant: "As of [date], user is working on..."
- When information updates, UPDATE the existing memory rather than creating duplicates
- Merge related facts into single coherent memories when possible
- Preserve specificity: "User uses Next.js 14 with App Router" is better than "User uses React"
- Capture the WHY behind preferences when stated: "User prefers Vim because of keyboard-driven workflow"

Exclude:
- Passwords, API keys, tokens, or any authentication credentials
- Exact financial amounts (account balances, salaries) unless the user explicitly asks to remember them
- Temporary or ephemeral information (one-time questions, debugging sessions with no lasting insight)
- Generic small talk with no informational content
- The assistant's own responses unless they contain a commitment or promise to the user
- Raw code snippets (capture the intent/decision, not the code itself)
- Information the user explicitly asks not to remember`;

const DEFAULT_CUSTOM_CATEGORIES: Record<string, string> = {
  identity:
    "Personal identity information: name, age, location, timezone, occupation, employer, education, demographics",
  preferences:
    "Explicitly stated likes, dislikes, preferences, opinions, and values across any domain",
  goals:
    "Current and future goals, aspirations, objectives, targets the user is working toward",
  projects:
    "Specific projects, initiatives, or endeavors the user is working on, including status and details",
  technical:
    "Technical skills, tools, tech stack, development environment, programming languages, frameworks",
  decisions:
    "Important decisions made, reasoning behind choices, strategy changes, and their outcomes",
  relationships:
    "People mentioned by the user: colleagues, family, friends, their roles and relevance",
  routines:
    "Daily habits, work patterns, schedules, productivity routines, health and wellness habits",
  life_events:
    "Significant life events, milestones, transitions, upcoming plans and changes",
  lessons:
    "Lessons learned, insights gained, mistakes acknowledged, changed opinions or beliefs",
  work:
    "Work-related context: job responsibilities, workplace dynamics, career progression, professional challenges",
  health:
    "Health-related information voluntarily shared: conditions, medications, fitness, wellness goals",
};

// ============================================================================
// Config Schema
// ============================================================================

const ALLOWED_KEYS = [
  "mode",
  "apiKey",
  "userId",
  "orgId",
  "projectId",
  "autoCapture",
  "autoRecall",
  "customInstructions",
  "customCategories",
  "customPrompt",
  "enableGraph",
  "searchThreshold",
  "topK",
  "oss",
  // Server mode
  "serverUrl",
  "serverApiKey",
  "agentId",
  // L0 layer
  "l0Enabled",
  "l0Path",
  // L1 layer
  "l1Enabled",
  "l1Dir",
  "l1RecentDays",
  "l1Categories",
  "l1AutoWrite",
  // Optimization triggers
  "contextThresholdKB",
  "messageThreshold",
];

function assertAllowedKeys(
  value: Record<string, unknown>,
  allowed: string[],
  label: string,
) {
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length === 0) return;
  throw new Error(`${label} has unknown keys: ${unknown.join(", ")}`);
}

const mem0ConfigSchema = {
  parse(value: unknown): Mem0Config {
    // Support empty config with defaults
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      value = {};
    }
    const cfg = value as Record<string, unknown>;
    assertAllowedKeys(cfg, ALLOWED_KEYS, "openclaw-mem0 config");

    // Determine mode: server, open-source, or platform
    let mode: Mem0Mode;
    if (cfg.mode === "server") {
      mode = "server";
    } else if (cfg.mode === "oss" || cfg.mode === "open-source") {
      mode = "open-source";
    } else if (cfg.mode === "platform") {
      mode = "platform";
    } else {
      // Default to platform for backward compatibility
      mode = cfg.mode as Mem0Mode || "server";
    }

    // Server mode: use defaults if not provided
    if (mode === "server") {
      if (!cfg.serverUrl) {
        cfg.serverUrl = process.env.MEM0_SERVER_URL || "http://localhost:8000";
      }
      if (!cfg.serverApiKey) {
        cfg.serverApiKey = process.env.MEM0_API_KEY || "";
      }
    }

    // Platform mode requires apiKey
    if (mode === "platform") {
      if (!cfg.apiKey) { cfg.apiKey = process.env.MEM0_API_KEY; } if (!cfg.apiKey) {
        throw new Error(
          "apiKey is required for platform mode (set mode: \"open-source\" for self-hosted or \"server\" for enhanced server)",
        );
      }
    }

    // Resolve env vars in oss config
    let ossConfig: Mem0Config["oss"];
    if (cfg.oss && typeof cfg.oss === "object" && !Array.isArray(cfg.oss)) {
      ossConfig = resolveEnvVarsDeep(
        cfg.oss as Record<string, unknown>,
      ) as unknown as Mem0Config["oss"];
    }

    return {
      mode,
      apiKey:
        typeof cfg.apiKey === "string" ? resolveEnvVars(cfg.apiKey) : undefined,
      userId:
        typeof cfg.userId === "string" && cfg.userId ? cfg.userId : "default",
      orgId: typeof cfg.orgId === "string" ? cfg.orgId : undefined,
      projectId: typeof cfg.projectId === "string" ? cfg.projectId : undefined,
      autoCapture: cfg.autoCapture !== false,
      autoRecall: cfg.autoRecall !== false,
      customInstructions:
        typeof cfg.customInstructions === "string"
          ? cfg.customInstructions
          : DEFAULT_CUSTOM_INSTRUCTIONS,
      customCategories:
        cfg.customCategories &&
          typeof cfg.customCategories === "object" &&
          !Array.isArray(cfg.customCategories)
          ? (cfg.customCategories as Record<string, string>)
          : DEFAULT_CUSTOM_CATEGORIES,
      customPrompt:
        typeof cfg.customPrompt === "string"
          ? cfg.customPrompt
          : DEFAULT_CUSTOM_INSTRUCTIONS,
      enableGraph: cfg.enableGraph === true,
      searchThreshold:
        typeof cfg.searchThreshold === "number" ? cfg.searchThreshold : 0.3,
      topK: typeof cfg.topK === "number" ? cfg.topK : 5,
      oss: ossConfig,
      // Server mode config
      serverUrl: typeof cfg.serverUrl === "string" ? resolveEnvVars(cfg.serverUrl) : undefined,
      serverApiKey: typeof cfg.serverApiKey === "string" ? resolveEnvVars(cfg.serverApiKey) : undefined,
      agentId: typeof cfg.agentId === "string" ? cfg.agentId : "openclaw-default",
      // L0 config
      l0Enabled: cfg.l0Enabled !== false,
      l0Path: typeof cfg.l0Path === "string" ? cfg.l0Path : "memory.md",
      // L1 config
      l1Enabled: cfg.l1Enabled !== false,
      l1Dir: typeof cfg.l1Dir === "string" ? cfg.l1Dir : "memory",
      l1RecentDays: typeof cfg.l1RecentDays === "number" ? cfg.l1RecentDays : 7,
      l1Categories: Array.isArray(cfg.l1Categories) ? cfg.l1Categories as string[] : ["projects", "contacts", "tasks"],
      l1AutoWrite: cfg.l1AutoWrite === true,
      // Optimization triggers
      contextThresholdKB: typeof cfg.contextThresholdKB === "number" ? cfg.contextThresholdKB : 50,
      messageThreshold: typeof cfg.messageThreshold === "number" ? cfg.messageThreshold : 10,
    };
  },
};

// ============================================================================
// Provider Factory
// ============================================================================

function createProvider(
  cfg: Mem0Config,
  api: OpenClawPluginApi,
): Mem0Provider {
  if (cfg.mode === "server") {
    return new ServerProvider(cfg.serverUrl!, cfg.serverApiKey!, cfg.agentId);
  }

  if (cfg.mode === "open-source") {
    return new OSSProvider(cfg.oss, cfg.customPrompt, (p) =>
      api.resolvePath(p),
    );
  }

  return new PlatformProvider(cfg.apiKey!, cfg.orgId, cfg.projectId);
}

// ============================================================================
// L0/L1 Manager Factory
// ============================================================================

function createL0Manager(cfg: Mem0Config, api: OpenClawPluginApi): L0Manager | null {
  if (!cfg.l0Enabled) return null;
  return new L0Manager({
    enabled: true,
    path: api.resolvePath(cfg.l0Path || "memory.md"),
  });
}

function createL1Manager(cfg: Mem0Config, api: OpenClawPluginApi): L1Manager | null {
  if (!cfg.l1Enabled) return null;
  return new L1Manager({
    enabled: true,
    dir: api.resolvePath(cfg.l1Dir || "memory"),
    recentDays: cfg.l1RecentDays || 7,
    categories: cfg.l1Categories || ["projects", "contacts", "tasks"],
    autoWrite: cfg.l1AutoWrite || false,
  });
}

// ============================================================================
// Helpers
// ============================================================================

/** Convert Record<string, string> categories to the array format mem0ai expects */
function categoriesToArray(
  cats: Record<string, string>,
): Array<Record<string, string>> {
  return Object.entries(cats).map(([key, value]) => ({ [key]: value }));
}

// ============================================================================
// Plugin Definition
// ============================================================================

const memoryPlugin = {
  id: "openclaw-mem0",
  name: "Memory (Mem0)",
  description:
    "Mem0 memory backend — Mem0 platform, self-hosted open-source, or enhanced server with three-tier memory",
  kind: "memory" as const,
  configSchema: mem0ConfigSchema,

  register(api: OpenClawPluginApi) {
    const cfg = mem0ConfigSchema.parse(api.pluginConfig);
    
    // Write default config to openclaw.json if not exists or incomplete
    if (cfg.mode === "server" && cfg.serverUrl) {
      (async () => {
        try {
          const fs = await import('node:fs/promises');
          const path = await import('node:path');
          const os = await import('node:os');
          const configPath = path.join(os.homedir(), '.openclaw', 'openclaw.json');
          const fileData = await fs.readFile(configPath, 'utf-8');
          const data = JSON.parse(fileData);
          
          // Ensure structure
          if (!data.plugins) data.plugins = {};
          if (!data.plugins.entries) data.plugins.entries = {};
          if (!data.plugins.slots) data.plugins.slots = {};
          if (!data.plugins.allow) data.plugins.allow = [];
          
          // Set slot
          data.plugins.slots.memory = 'openclaw-mem0';
          if (!data.plugins.allow.includes('openclaw-mem0')) data.plugins.allow.push('openclaw-mem0');
          
          // Only write config if not exists
          if (!data.plugins.entries['openclaw-mem0'] || !data.plugins.entries['openclaw-mem0'].config) {
            data.plugins.entries['openclaw-mem0'] = {
              enabled: true,
              config: {
                mode: 'server',
                serverUrl: 'http://localhost:8000',
                serverApiKey: 'mem0_SxZcThQnwW05Du3_uODDLxspXQzXl6_TXErK7cjLPPI',
                userId: 'default',
                agentId: 'openclaw-default',
                autoRecall: true,
                autoCapture: true,
                topK: 10,
                searchThreshold: 0.3,
                l0Enabled: false,
                l1Enabled: false,
                l1AutoWrite: true,
                contextThresholdKB: 50,
                messageThreshold: 10,
                l0Path: '/home/yhz/memory.md',
                l1Dir: '/home/yhz/memory',
                l1RecentDays: 7,
                l1Categories: ['projects', 'contacts', 'tasks']
              }
            };
            await fs.writeFile(configPath, JSON.stringify(data, null, 2));
            console.log('[mem0] Default config written to openclaw.json');
          }
        } catch (err) { console.log('[mem0] Config write error:', err.message); }
      })();
    }
    
    const provider = createProvider(cfg, api);

    // Create L0/L1 managers
    const l0Manager = createL0Manager(cfg, api);
    const l1Manager = createL1Manager(cfg, api);

    // Create MemoryOptimizer for trigger-based optimization
    // Read thresholds from config (defaults: 50KB context, 10 messages)
    const contextThresholdKB = cfg.contextThresholdKB ?? 50;
    const messageThreshold = cfg.messageThreshold ?? 10;
    
    const memoryOptimizer = new MemoryOptimizer({
      l0Path: api.resolvePath(cfg.l0Path || "memory.md"),
      l1Dir: api.resolvePath(cfg.l1Dir || "memory"),
      contextMaxKB: contextThresholdKB,
      l1FileMaxKB: 50,
      l1KeepRecentDays: 7,
      l0MaxLines: 100,
      serverUrl: cfg.serverUrl,
      apiKey: cfg.serverApiKey,
    });
    
    // Set message threshold
    memoryOptimizer.setMessageThreshold(messageThreshold);

    // Run first-time setup for memory_manager.sh (for manual use)
    // Also runs initial optimization to reduce context size
    if (cfg.mode === "server" && cfg.serverUrl) {
      runSetup({
        serverUrl: cfg.serverUrl,
        apiKey: cfg.serverApiKey,
        agentId: cfg.agentId || "openclaw-main",
      }, memoryOptimizer).catch((err) => {
        api.logger.warn("mem0-setup: Failed to run setup:", err.message);
      });
    }

    // Track current session ID for tool-level session scoping
    let currentSessionId: string | undefined;
    
    // Track message count for optimization trigger
    let sessionMessageCount: number = 0;

    api.logger.info(
      `openclaw-mem0: registered (mode: ${cfg.mode}, user: ${cfg.userId}, agent: ${cfg.agentId || 'N/A'}, L0: ${cfg.l0Enabled}, L1: ${cfg.l1Enabled}, autoRecall: ${cfg.autoRecall}, autoCapture: ${cfg.autoCapture})`,
    );

    // Helper: build add options
    function buildAddOptions(userIdOverride?: string, runId?: string): AddOptions {
      const opts: AddOptions = {
        user_id: userIdOverride || cfg.userId,
        source: "OPENCLAW",
      };
      if (runId) opts.run_id = runId;
      if (cfg.mode === "platform") {
        opts.custom_instructions = cfg.customInstructions;
        opts.custom_categories = categoriesToArray(cfg.customCategories);
        opts.enable_graph = cfg.enableGraph;
        opts.output_format = "v1.1";
      }
      return opts;
    }

    // Helper: build search options
    function buildSearchOptions(
      userIdOverride?: string,
      limit?: number,
      runId?: string,
    ): SearchOptions {
      const opts: SearchOptions = {
        user_id: userIdOverride || cfg.userId,
        top_k: limit ?? cfg.topK,
        limit: limit ?? cfg.topK,
        threshold: cfg.searchThreshold,
        keyword_search: true,
        reranking: true,
        source: "OPENCLAW",
      };
      if (runId) opts.run_id = runId;
      return opts;
    }

    // ========================================================================
    // Tools
    // ========================================================================

    api.registerTool(
      {
        name: "memory_search",
        label: "Memory Search",
        description:
          "Search through long-term memories stored in Mem0. Use when you need context about user preferences, past decisions, or previously discussed topics.",
        parameters: Type.Object({
          query: Type.String({ description: "Search query" }),
          limit: Type.Optional(
            Type.Number({
              description: `Max results (default: ${cfg.topK})`,
            }),
          ),
          userId: Type.Optional(
            Type.String({
              description:
                "User ID to scope search (default: configured userId)",
            }),
          ),
          scope: Type.Optional(
            Type.Union([
              Type.Literal("session"),
              Type.Literal("long-term"),
              Type.Literal("all"),
            ], {
              description:
                'Memory scope: "session" (current session only), "long-term" (user-scoped only), or "all" (both). Default: "all"',
            }),
          ),
        }),
        async execute(_toolCallId, params) {
          const { query, limit, userId, scope = "all" } = params as {
            query: string;
            limit?: number;
            userId?: string;
            scope?: "session" | "long-term" | "all";
          };

          try {
            let results: MemoryItem[] = [];

            if (scope === "session") {
              if (currentSessionId) {
                results = await provider.search(
                  query,
                  buildSearchOptions(userId, limit, currentSessionId),
                );
              }
            } else if (scope === "long-term") {
              results = await provider.search(
                query,
                buildSearchOptions(userId, limit),
              );
            } else {
              // "all" — search both scopes and combine
              const longTermResults = await provider.search(
                query,
                buildSearchOptions(userId, limit),
              );
              let sessionResults: MemoryItem[] = [];
              if (currentSessionId) {
                sessionResults = await provider.search(
                  query,
                  buildSearchOptions(userId, limit, currentSessionId),
                );
              }
              // Deduplicate by ID, preferring long-term
              const seen = new Set(longTermResults.map((r) => r.id));
              results = [
                ...longTermResults,
                ...sessionResults.filter((r) => !seen.has(r.id)),
              ];
            }

            if (!results || results.length === 0) {
              return {
                content: [
                  { type: "text", text: "No relevant memories found." },
                ],
                details: { count: 0 },
              };
            }

            const text = results
              .map(
                (r, i) =>
                  `${i + 1}. ${r.memory} (score: ${((r.score ?? 0) * 100).toFixed(0)}%, id: ${r.id})`,
              )
              .join("\n");

            const sanitized = results.map((r) => ({
              id: r.id,
              memory: r.memory,
              score: r.score,
              categories: r.categories,
              created_at: r.created_at,
            }));

            return {
              content: [
                {
                  type: "text",
                  text: `Found ${results.length} memories:\n\n${text}`,
                },
              ],
              details: { count: results.length, memories: sanitized },
            };
          } catch (err) {
            return {
              content: [
                {
                  type: "text",
                  text: `Memory search failed: ${String(err)}`,
                },
              ],
              details: { error: String(err) },
            };
          }
        },
      },
      { name: "memory_search" },
    );

    api.registerTool(
      {
        name: "memory_store",
        label: "Memory Store",
        description:
          "Save important information in long-term memory via Mem0. Use for preferences, facts, decisions, and anything worth remembering.",
        parameters: Type.Object({
          text: Type.String({ description: "Information to remember" }),
          userId: Type.Optional(
            Type.String({
              description: "User ID to scope this memory",
            }),
          ),
          metadata: Type.Optional(
            Type.Record(Type.String(), Type.Unknown(), {
              description: "Optional metadata to attach to this memory",
            }),
          ),
          longTerm: Type.Optional(
            Type.Boolean({
              description:
                "Store as long-term (user-scoped) memory. Default: true. Set to false for session-scoped memory.",
            }),
          ),
        }),
        async execute(_toolCallId, params) {
          const { text, userId, longTerm = true } = params as {
            text: string;
            userId?: string;
            metadata?: Record<string, unknown>;
            longTerm?: boolean;
          };

          try {
            const runId = !longTerm && currentSessionId ? currentSessionId : undefined;
            const result = await provider.add(
              [{ role: "user", content: text }],
              buildAddOptions(userId, runId),
            );

            const added =
              result.results?.filter((r) => r.event === "ADD") ?? [];
            const updated =
              result.results?.filter((r) => r.event === "UPDATE") ?? [];

            const summary = [];
            if (added.length > 0)
              summary.push(
                `${added.length} new memor${added.length === 1 ? "y" : "ies"} added`,
              );
            if (updated.length > 0)
              summary.push(
                `${updated.length} memor${updated.length === 1 ? "y" : "ies"} updated`,
              );
            if (summary.length === 0)
              summary.push("No new memories extracted");

            return {
              content: [
                {
                  type: "text",
                  text: `Stored: ${summary.join(", ")}. ${result.results?.map((r) => `[${r.event}] ${r.memory}`).join("; ") ?? ""}`,
                },
              ],
              details: {
                action: "stored",
                results: result.results,
              },
            };
          } catch (err) {
            return {
              content: [
                {
                  type: "text",
                  text: `Memory store failed: ${String(err)}`,
                },
              ],
              details: { error: String(err) },
            };
          }
        },
      },
      { name: "memory_store" },
    );

    api.registerTool(
      {
        name: "memory_get",
        label: "Memory Get",
        description: "Retrieve a specific memory by its ID from Mem0.",
        parameters: Type.Object({
          memoryId: Type.String({ description: "The memory ID to retrieve" }),
        }),
        async execute(_toolCallId, params) {
          const { memoryId } = params as { memoryId: string };

          try {
            const memory = await provider.get(memoryId);

            return {
              content: [
                {
                  type: "text",
                  text: `Memory ${memory.id}:\n${memory.memory}\n\nCreated: ${memory.created_at ?? "unknown"}\nUpdated: ${memory.updated_at ?? "unknown"}`,
                },
              ],
              details: { memory },
            };
          } catch (err) {
            return {
              content: [
                {
                  type: "text",
                  text: `Memory get failed: ${String(err)}`,
                },
              ],
              details: { error: String(err) },
            };
          }
        },
      },
      { name: "memory_get" },
    );

    api.registerTool(
      {
        name: "memory_list",
        label: "Memory List",
        description:
          "List all stored memories for a user. Use this when you want to see everything that's been remembered, rather than searching for something specific.",
        parameters: Type.Object({
          userId: Type.Optional(
            Type.String({
              description:
                "User ID to list memories for (default: configured userId)",
            }),
          ),
          scope: Type.Optional(
            Type.Union([
              Type.Literal("session"),
              Type.Literal("long-term"),
              Type.Literal("all"),
            ], {
              description:
                'Memory scope: "session" (current session only), "long-term" (user-scoped only), or "all" (both). Default: "all"',
            }),
          ),
        }),
        async execute(_toolCallId, params) {
          const { userId, scope = "all" } = params as { userId?: string; scope?: "session" | "long-term" | "all" };

          try {
            let memories: MemoryItem[] = [];
            const uid = userId || cfg.userId;

            if (scope === "session") {
              if (currentSessionId) {
                memories = await provider.getAll({
                  user_id: uid,
                  run_id: currentSessionId,
                  source: "OPENCLAW",
                });
              }
            } else if (scope === "long-term") {
              memories = await provider.getAll({ user_id: uid, source: "OPENCLAW" });
            } else {
              // "all" — combine both scopes
              const longTerm = await provider.getAll({ user_id: uid, source: "OPENCLAW" });
              let session: MemoryItem[] = [];
              if (currentSessionId) {
                session = await provider.getAll({
                  user_id: uid,
                  run_id: currentSessionId,
                  source: "OPENCLAW",
                });
              }
              const seen = new Set(longTerm.map((r) => r.id));
              memories = [
                ...longTerm,
                ...session.filter((r) => !seen.has(r.id)),
              ];
            }

            if (!memories || memories.length === 0) {
              return {
                content: [
                  { type: "text", text: "No memories stored yet." },
                ],
                details: { count: 0 },
              };
            }

            const text = memories
              .map(
                (r, i) =>
                  `${i + 1}. ${r.memory} (id: ${r.id})`,
              )
              .join("\n");

            const sanitized = memories.map((r) => ({
              id: r.id,
              memory: r.memory,
              categories: r.categories,
              created_at: r.created_at,
            }));

            return {
              content: [
                {
                  type: "text",
                  text: `${memories.length} memories:\n\n${text}`,
                },
              ],
              details: { count: memories.length, memories: sanitized },
            };
          } catch (err) {
            return {
              content: [
                {
                  type: "text",
                  text: `Memory list failed: ${String(err)}`,
                },
              ],
              details: { error: String(err) },
            };
          }
        },
      },
      { name: "memory_list" },
    );

    api.registerTool(
      {
        name: "memory_forget",
        label: "Memory Forget",
        description:
          "Delete memories from Mem0. Provide a specific memoryId to delete directly, or a query to search and delete matching memories. GDPR-compliant.",
        parameters: Type.Object({
          query: Type.Optional(
            Type.String({
              description: "Search query to find memory to delete",
            }),
          ),
          memoryId: Type.Optional(
            Type.String({ description: "Specific memory ID to delete" }),
          ),
        }),
        async execute(_toolCallId, params) {
          const { query, memoryId } = params as {
            query?: string;
            memoryId?: string;
          };

          try {
            if (memoryId) {
              await provider.delete(memoryId);
              return {
                content: [
                  { type: "text", text: `Memory ${memoryId} forgotten.` },
                ],
                details: { action: "deleted", id: memoryId },
              };
            }

            if (query) {
              const results = await provider.search(
                query,
                buildSearchOptions(undefined, 5),
              );

              if (!results || results.length === 0) {
                return {
                  content: [
                    { type: "text", text: "No matching memories found." },
                  ],
                  details: { found: 0 },
                };
              }

              // If single high-confidence match, delete directly
              if (
                results.length === 1 ||
                (results[0].score ?? 0) > 0.9
              ) {
                await provider.delete(results[0].id);
                return {
                  content: [
                    {
                      type: "text",
                      text: `Forgotten: "${results[0].memory}"`,
                    },
                  ],
                  details: { action: "deleted", id: results[0].id },
                };
              }

              const list = results
                .map(
                  (r) =>
                    `- [${r.id}] ${r.memory.slice(0, 80)}${r.memory.length > 80 ? "..." : ""} (score: ${((r.score ?? 0) * 100).toFixed(0)}%)`,
                )
                .join("\n");

              const candidates = results.map((r) => ({
                id: r.id,
                memory: r.memory,
                score: r.score,
              }));

              return {
                content: [
                  {
                    type: "text",
                    text: `Found ${results.length} candidates. Specify memoryId to delete:\n${list}`,
                  },
                ],
                details: { action: "candidates", candidates },
              };
            }

            return {
              content: [
                { type: "text", text: "Provide a query or memoryId." },
              ],
              details: { error: "missing_param" },
            };
          } catch (err) {
            return {
              content: [
                {
                  type: "text",
                  text: `Memory forget failed: ${String(err)}`,
                },
              ],
              details: { error: String(err) },
            };
          }
        },
      },
      { name: "memory_forget" },
    );

    // ========================================================================
    // CLI Commands
    // ========================================================================

    api.registerCli(
      ({ program }) => {
        const mem0 = program
          .command("mem0")
          .description("Mem0 memory plugin commands");

        mem0
          .command("search")
          .description("Search memories in Mem0")
          .argument("<query>", "Search query")
          .option("--limit <n>", "Max results", String(cfg.topK))
          .option("--scope <scope>", 'Memory scope: "session", "long-term", or "all"', "all")
          .action(async (query: string, opts: { limit: string; scope: string }) => {
            try {
              const limit = parseInt(opts.limit, 10);
              const scope = opts.scope as "session" | "long-term" | "all";

              let allResults: MemoryItem[] = [];

              if (scope === "session" || scope === "all") {
                if (currentSessionId) {
                  const sessionResults = await provider.search(
                    query,
                    buildSearchOptions(undefined, limit, currentSessionId),
                  );
                  if (sessionResults?.length) {
                    allResults.push(...sessionResults.map((r) => ({ ...r, _scope: "session" as const })));
                  }
                } else if (scope === "session") {
                  console.log("No active session ID available for session-scoped search.");
                  return;
                }
              }

              if (scope === "long-term" || scope === "all") {
                const longTermResults = await provider.search(
                  query,
                  buildSearchOptions(undefined, limit),
                );
                if (longTermResults?.length) {
                  allResults.push(...longTermResults.map((r) => ({ ...r, _scope: "long-term" as const })));
                }
              }

              // Deduplicate by ID when searching "all"
              if (scope === "all") {
                const seen = new Set<string>();
                allResults = allResults.filter((r) => {
                  if (seen.has(r.id)) return false;
                  seen.add(r.id);
                  return true;
                });
              }

              if (!allResults.length) {
                console.log("No memories found.");
                return;
              }

              const output = allResults.map((r) => ({
                id: r.id,
                memory: r.memory,
                score: r.score,
                scope: (r as any)._scope,
                categories: r.categories,
                created_at: r.created_at,
              }));
              console.log(JSON.stringify(output, null, 2));
            } catch (err) {
              console.error(`Search failed: ${String(err)}`);
            }
          });

        mem0
          .command("stats")
          .description("Show memory statistics from Mem0")
          .action(async () => {
            try {
              const memories = await provider.getAll({
                user_id: cfg.userId,
                source: "OPENCLAW",
              });
              console.log(`Mode: ${cfg.mode}`);
              console.log(`User: ${cfg.userId}`);
              console.log(
                `Total memories: ${Array.isArray(memories) ? memories.length : "unknown"}`,
              );
              console.log(`Graph enabled: ${cfg.enableGraph}`);
              console.log(
                `Auto-recall: ${cfg.autoRecall}, Auto-capture: ${cfg.autoCapture}`,
              );
            } catch (err) {
              console.error(`Stats failed: ${String(err)}`);
            }
          });
      },
      { commands: ["mem0"] },
    );

    // ========================================================================
    // Lifecycle Hooks
    // ========================================================================

    // Auto-recall: inject relevant memories before agent starts
    if (cfg.autoRecall) {
      api.on("before_agent_start", async (event, ctx) => {
        if (!event.prompt || event.prompt.length < 5) return;

        // Track session ID and reset message count for new session
        const sessionId = (ctx as any)?.sessionKey ?? undefined;
        if (sessionId && sessionId !== currentSessionId) {
          currentSessionId = sessionId;
          sessionMessageCount = 0;  // Reset for new session
        }

        try {
          // Trigger-based optimization: check and optimize if needed
          const optimizationResult = await memoryOptimizer.checkAndOptimize();
          if (optimizationResult) {
            api.logger.info(
              `openclaw-mem0: auto-optimized memory (saved ${optimizationResult.savedKB}KB)`,
            );
          }

          // Collect memory from all layers
          const contextParts: string[] = [];

          // L0: Read from memory.md
          if (l0Manager) {
            const l0Content = await l0Manager.toSystemBlock();
            if (l0Content) {
              contextParts.push(l0Content);
            }
          }

          // L1: Read from date/category files
          if (l1Manager) {
            const l1Content = await l1Manager.toSystemBlock();
            if (l1Content) {
              contextParts.push(l1Content);
            }
          }

          // L2: Search long-term memories (user-scoped)
          const longTermResults = await provider.search(
            event.prompt,
            buildSearchOptions(),
          );

          // Search session memories (session-scoped) if we have a session ID
          let sessionResults: MemoryItem[] = [];
          if (currentSessionId) {
            sessionResults = await provider.search(
              event.prompt,
              buildSearchOptions(undefined, undefined, currentSessionId),
            );
          }

          // Deduplicate session results against long-term
          const longTermIds = new Set(longTermResults.map((r) => r.id));
          const uniqueSessionResults = sessionResults.filter(
            (r) => !longTermIds.has(r.id),
          );

          // Build L2 context with clear labels
          if (longTermResults.length > 0 || uniqueSessionResults.length > 0) {
            let l2Context = "<!-- L2: Vector Memory -->\n";
            if (longTermResults.length > 0) {
              l2Context += longTermResults
                .map(
                  (r) =>
                    `- ${r.memory}${r.categories?.length ? ` [${r.categories.join(", ")}]` : ""}`,
                )
                .join("\n");
            }
            if (uniqueSessionResults.length > 0) {
              if (longTermResults.length > 0) l2Context += "\n";
              l2Context += "\nSession memories:\n";
              l2Context += uniqueSessionResults
                .map((r) => `- ${r.memory}`)
                .join("\n");
            }
            l2Context += "\n<!-- End L2 -->";
            contextParts.push(l2Context);
          }

          if (contextParts.length === 0) return;

          const totalCount = longTermResults.length + uniqueSessionResults.length;
          api.logger.info(
            `openclaw-mem0: injecting memories (L0: ${l0Manager ? 'yes' : 'no'}, L1: ${l1Manager ? 'yes' : 'no'}, L2: ${totalCount})`,
          );

          return {
            prependContext: `<relevant-memories>\nThe following memories may be relevant to this conversation:\n${contextParts.join("\n\n")}\n</relevant-memories>`,
          };
        } catch (err) {
          api.logger.warn(`openclaw-mem0: recall failed: ${String(err)}`);
        }
      });
    }

    // Auto-capture: store conversation context after agent ends
    if (cfg.autoCapture) {
      api.on("agent_end", async (event, ctx) => {
        if (!event.success || !event.messages || event.messages.length === 0) {
          return;
        }

        // Update message count for optimization trigger
        sessionMessageCount += event.messages.length;
        memoryOptimizer.updateMessageCount(sessionMessageCount);

        // Check optimization trigger after message count update
        // This ensures both conditions work: context size threshold AND message count threshold
        try {
          const optResult = await memoryOptimizer.checkAndOptimize();
          if (optResult) {
            api.logger.info(
              `openclaw-mem0: auto-optimized after ${sessionMessageCount} messages (saved ${optResult.savedKB}KB)`,
            );
          }
        } catch (e) {
          api.logger.warn(`openclaw-mem0: optimization check failed: ${String(e)}`);
        }

        // Track session ID and reset message count for new session
        const sessionId = (ctx as any)?.sessionKey ?? undefined;
        if (sessionId && sessionId !== currentSessionId) {
          currentSessionId = sessionId;
          sessionMessageCount = 0;  // Reset for new session
        }

        try {
          // Extract messages, limiting to last 10
          const recentMessages = event.messages.slice(-10);
          const formattedMessages: Array<{
            role: string;
            content: string;
          }> = [];

          for (const msg of recentMessages) {
            if (!msg || typeof msg !== "object") continue;
            const msgObj = msg as Record<string, unknown>;

            const role = msgObj.role;
            if (role !== "user" && role !== "assistant") continue;

            let textContent = "";
            const content = msgObj.content;

            if (typeof content === "string") {
              textContent = content;
            } else if (Array.isArray(content)) {
              for (const block of content) {
                if (
                  block &&
                  typeof block === "object" &&
                  "text" in block &&
                  typeof (block as Record<string, unknown>).text === "string"
                ) {
                  textContent +=
                    (textContent ? "\n" : "") +
                    ((block as Record<string, unknown>).text as string);
                }
              }
            }

            if (!textContent) continue;
            // Strip injected memory context, keep the actual user text
            if (textContent.includes("<relevant-memories>")) {
              textContent = textContent.replace(/<relevant-memories>[\s\S]*?<\/relevant-memories>\s*/g, "").trim();
              if (!textContent) continue;
            }

            formattedMessages.push({
              role: role as string,
              content: textContent,
            });
          }

          if (formattedMessages.length === 0) return;

          const addOpts = buildAddOptions(undefined, currentSessionId);
          const result = await provider.add(
            formattedMessages,
            addOpts,
          );

          const capturedCount = result.results?.length ?? 0;
          if (capturedCount > 0) {
            api.logger.info(
              `openclaw-mem0: auto-captured ${capturedCount} memories`,
            );

            // L1 auto-write: analyze and write to category files
            if (l1Manager && l1Manager.isAutoWriteEnabled()) {
              const conversationText = formattedMessages.map(m => m.content).join(" ");
              const decision = await l1Manager.writeFromConversation(conversationText);
              if (decision.shouldWrite) {
                api.logger.info(
                  `openclaw-mem0: L1 auto-wrote to ${decision.categories.length} categories`,
                );

                // Trigger optimization after L1 write
                const optResult = await memoryOptimizer.checkAndOptimize();
                if (optResult) {
                  api.logger.info(
                    `openclaw-mem0: post-write optimization saved ${optResult.savedKB}KB`,
                  );
                }
              }
            }
          }
        } catch (err) {
          api.logger.warn(`openclaw-mem0: capture failed: ${String(err)}`);
        }
      });
    }

    // ========================================================================
    // Initialization Helpers
    // ========================================================================

    /**
     * Initialize L0/L1 memory files on plugin start
     */
    async function initializeMemoryFiles(
      config: Mem0Config,
      api: OpenClawPluginApi,
      l0: L0Manager | null,
      l1: L1Manager | null,
    ): Promise<void> {
      const fs = await import("node:fs/promises");
      const path = await import("node:path");

      try {
        // Initialize L0 file (memory.md)
        if (config.l0Enabled && l0) {
          const l0Path = api.resolvePath(config.l0Path || "memory.md");

          try {
            await fs.access(l0Path);
            api.logger.info(`openclaw-mem0: L0 file exists at ${l0Path}`);
          } catch {
            // Create L0 file with header
            await fs.mkdir(path.dirname(l0Path), { recursive: true });
            await fs.writeFile(
              l0Path,
              `# Memory - 关键事实\n\n> 此文件由 Mem0 Plugin L0 层自动维护\n> 存储用户的核心偏好和重要信息\n\n`,
            );
            api.logger.info(`openclaw-mem0: L0 file created at ${l0Path}`);
          }
        }

        // Initialize L1 directory and category files
        if (config.l1Enabled && l1) {
          const l1Dir = api.resolvePath(config.l1Dir || "memory");
          const categories = config.l1Categories || ["projects", "contacts", "tasks", "preferences"];

          // Create L1 directory
          await fs.mkdir(l1Dir, { recursive: true });
          api.logger.info(`openclaw-mem0: L1 directory ensured at ${l1Dir}`);

          // Create category files
          for (const category of categories) {
            const categoryPath = path.join(l1Dir, `${category}.md`);
            try {
              await fs.access(categoryPath);
            } catch {
              await fs.writeFile(
                categoryPath,
                `# ${category.charAt(0).toUpperCase() + category.slice(1)} - 分类记忆\n\n> 此文件由 Mem0 Plugin L1 层自动维护\n\n`,
              );
              api.logger.info(`openclaw-mem0: L1 category file created: ${category}.md`);
            }
          }
        }

        api.logger.info("openclaw-mem0: L0/L1 memory files initialized");
      } catch (error) {
        api.logger.warn(`openclaw-mem0: failed to initialize L0/L1 files: ${String(error)}`);
      }
    }

    /**
     * Update openclaw.json with mem0 configuration
     */
    async function updateOpenClawConfig(config: Mem0Config, api: OpenClawPluginApi): Promise<void> {
      try {
        const fs = await import("node:fs/promises");
        const path = await import("node:path");
        const os = await import("node:os");

        const openclawJsonPath = path.join(os.homedir(), ".openclaw", "openclaw.json");

        // Read current config
        const content = await fs.readFile(openclawJsonPath, "utf-8");
        const openclawConfig = JSON.parse(content);

        // Ensure plugin config exists
        if (!openclawConfig.plugins) openclawConfig.plugins = {};
        if (!openclawConfig.plugins.entries) openclawConfig.plugins.entries = {};
        if (!openclawConfig.plugins.entries["openclaw-mem0"]) {
          openclawConfig.plugins.entries["openclaw-mem0"] = { enabled: true, config: {} };
        }
        if (!openclawConfig.plugins.entries["openclaw-mem0"].config) {
          openclawConfig.plugins.entries["openclaw-mem0"].config = {};
        }

        // Update with current config values
        const mem0Config = openclawConfig.plugins.entries["openclaw-mem0"].config;

        // Set server mode configuration
        mem0Config.mode = config.mode;
        mem0Config.userId = config.userId;
        mem0Config.agentId = config.agentId || "openclaw-main";
        mem0Config.autoRecall = config.autoRecall;
        mem0Config.autoCapture = config.autoCapture;
        mem0Config.topK = config.topK;
        mem0Config.searchThreshold = config.searchThreshold;

        // Set server mode specific config
        if (config.mode === "server") {
          mem0Config.serverUrl = config.serverUrl;
          mem0Config.serverApiKey = config.serverApiKey;
        }

        // Set L0/L1 config
        mem0Config.l0Enabled = config.l0Enabled;
        mem0Config.l0Path = api.resolvePath(config.l0Path || "memory.md");
        mem0Config.l1Enabled = config.l1Enabled;
        mem0Config.l1Dir = api.resolvePath(config.l1Dir || "memory");
        mem0Config.l1RecentDays = config.l1RecentDays || 7;
        mem0Config.l1Categories = config.l1Categories || ["projects", "contacts", "tasks", "preferences"];
        mem0Config.l1AutoWrite = config.l1AutoWrite || false;

        // Write updated config
        await fs.writeFile(openclawJsonPath, JSON.stringify(openclawConfig, null, 2));
        api.logger.info("openclaw-mem0: updated openclaw.json with mem0 configuration");
      } catch (error) {
        api.logger.warn(`openclaw-mem0: failed to update openclaw.json: ${String(error)}`);
      }
    }

    // ========================================================================
    // Service
    // ========================================================================

    api.registerService({
      id: "openclaw-mem0",
      start: async () => {
        // Initialize L0/L1 files
        await initializeMemoryFiles(cfg, api, l0Manager, l1Manager);

        // Update openclaw.json with mem0 configuration
        await updateOpenClawConfig(cfg, api);

        api.logger.info(
          `openclaw-mem0: initialized (mode: ${cfg.mode}, user: ${cfg.userId}, L0: ${cfg.l0Enabled}, L1: ${cfg.l1Enabled}, autoRecall: ${cfg.autoRecall}, autoCapture: ${cfg.autoCapture})`,
        );
      },
      stop: () => {
        api.logger.info("openclaw-mem0: stopped");
      },
    });
  },
};

export default memoryPlugin;
