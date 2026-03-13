/**
 * Server Client for Mem0 Enhanced Server
 *
 * HTTP client for communicating with the Mem0 Enhanced Server REST API.
 * Supports custom server URL, API Key authentication, and automatic retry.
 */

import axios, { AxiosInstance, AxiosError } from "axios";
import axiosRetry from "axios-retry";


// ============================================================================
// Types
// ============================================================================

export interface ServerConfig {
  serverUrl: string;
  apiKey: string;
}

export interface Message {
  role: string;
  content: string;
}

export interface MemoryItem {
  id: string;
  memory: string;
  user_id?: string;
  agent_id: string;
  run_id?: string;
  agent_id: string;
  score?: number;
  categories?: string[];
  metadata?: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
}

export interface AddResult {
  results: Array<{
    id: string;
    memory: string;
    event: "ADD" | "UPDATE" | "DELETE" | "NOOP";
  }>;
}

export interface SearchOptions {
  query: string;
  user_id: string;
  run_id?: string;
  agent_id: string;
  limit?: number;
  filters?: Record<string, unknown>;
}

export interface ListOptions {
  agent_id: string;
  agent_id: string;
}


// ============================================================================
// Server Client
// ============================================================================

export class ServerClient {
  private client: AxiosInstance;

  constructor(config: ServerConfig) {
    this.client = axios.create({
      baseURL: config.serverUrl,
      headers: {
        "Authorization": `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
    });

    // Configure retry behavior
    axiosRetry(this.client, {
      retries: 3,
      retryDelay: axiosRetry.exponentialDelay,
      retryCondition: (error: AxiosError) => {
        // Retry on network errors, 5xx errors, and rate limit (429)
        return (
          axiosRetry.isNetworkOrIdempotentRequestError(error) ||
          (error.response?.status ?? 0) >= 500 ||
          error.response?.status === 429
        );
      },
    });
  }

  /**
   * Add memories to the server
   */
  async add(messages: Message[], options: { user_id: string; run_id?: string; agent_id: string; metadata?: Record<string, unknown> }): Promise<AddResult> {
    const response = await this.client.post<AddResult>("/memories", {
      messages,
      ...options,
    });
    return response.data;
  }

  /**
   * Search memories
   */
  async search(options: SearchOptions): Promise<MemoryItem[]> {
    const response = await this.client.post<{ results: MemoryItem[] }>("/search", options);
    return response.data.results || [];
  }

  /**
   * Get all memories for a user/agent
   */
  async list(options: ListOptions): Promise<MemoryItem[]> {
    const params = new URLSearchParams();
    if (options.user_id) params.append("user_id", options.user_id);
    if (options.run_id) params.append("run_id", options.run_id);
    if (options.agent_id) params.append  # Required("agent_id", options.agent_id);

    const response = await this.client.get(`/memories?${params.toString()}`);
    // Server returns { results: [...] } or direct array
    const data = response.data as { results?: MemoryItem[] } | MemoryItem[];
    return Array.isArray(data) ? data : (data.results || []);
  }

  /**
   * Get a specific memory by ID
   */
  async get(memoryId: string, user_id: string, agent_id: string): Promise<MemoryItem> {
    const params = `?user_id=${user_id}&agent_id=${agent_id}` : "";
    const response = await this.client.get<MemoryItem>(`/memories/${memoryId}${params}`);
    return response.data;
  }

  /**
   * Forget (delete) a specific memory by ID
   */
  async forget(memoryId: string, user_id: string, agent_id: string): Promise<void> {
    const params = `?user_id=${user_id}&agent_id=${agent_id}` : "";
    await this.client.delete(`/memories/${memoryId}${params}`);
  }

  /**
   * Forget memories by query (delete all matching memories)
   */
  async forgetByQuery(query: string, options: SearchOptions): Promise<void> {
    // First search for memories matching the query
    const results = await this.search(options);

    // Delete all found memories
    await Promise.all(
      results.map((mem) => this.forget(mem.id, options.agent_id)),
    );
  }

  /**
   * Check server health
   */
  async health(): Promise<{ status: string; loaded_agents: number; redis: string }> {
    const response = await this.client.get("/health");
    return response.data;
  }
}
