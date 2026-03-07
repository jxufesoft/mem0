/**
 * L0 Manager - Memory.md File Management
 *
 * L0 layer provides persistent, human-readable memory storage in a single memory.md file.
 * This is the fastest access layer and contains the most important facts about the user.
 */

import * as fs from "node:fs/promises";
import * as path from "node:path";


// ============================================================================
// Types
// ============================================================================

export interface L0Config {
  enabled: boolean;
  path: string;
}

export interface L0Block {
  content: string;
  lastModified: number;
}


// ============================================================================
// L0 Manager
// ============================================================================

export class L0Manager {
  constructor(private config: L0Config) {}

  /**
   * Check if L0 is enabled
   */
  isEnabled(): boolean {
    return this.config.enabled;
  }

  /**
   * Get the full path to the memory.md file
   */
  private get filePath(): string {
    return path.resolve(this.config.path);
  }

  /**
   * Ensure the memory.md file exists
   */
  private async ensureFile(): Promise<void> {
    try {
      await fs.access(this.filePath);
    } catch {
      // File doesn't exist, create it with header
      await fs.mkdir(path.dirname(this.filePath), { recursive: true });
      await fs.writeFile(
        this.filePath,
        "# Memory\n\n> This file contains important facts and information about you.\n> It is automatically maintained by the memory system.\n\n",
      );
    }
  }

  /**
   * Read the complete content of memory.md
   */
  async readAll(): Promise<string> {
    if (!this.config.enabled) {
      return "";
    }

    try {
      await this.ensureFile();
      return await fs.readFile(this.filePath, "utf-8");
    } catch (error) {
      console.error(`Failed to read L0 memory file: ${error}`);
      return "";
    }
  }

  /**
   * Read memory.md as a structured block
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
   * Append a new fact to memory.md
   */
  async append(fact: string): Promise<void> {
    if (!this.config.enabled) {
      return;
    }

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
   * Overwrite the entire memory.md file with new content
   */
  async overwrite(content: string): Promise<void> {
    if (!this.config.enabled) {
      return;
    }

    try {
      await this.ensureFile();
      await fs.writeFile(this.filePath, content, "utf-8");
    } catch (error) {
      console.error(`Failed to overwrite L0 memory file: ${error}`);
    }
  }

  /**
   * Format L0 content as a System Prompt block for injection
   */
  async toSystemBlock(): Promise<string> {
    const content = await this.readAll();
    if (!content.trim()) {
      return "";
    }

    return `<!-- L0: Persistent Memory -->\n${content}\n<!-- End L0 -->`;
  }

  /**
   * Extract facts from L0 content
   */
  extractFacts(content: string): string[] {
    const lines = content.split("\n");
    const facts: string[] = [];

    for (const line of lines) {
      const trimmed = line.trim();
      // Match bullet points or numbered lists
      if (trimmed.startsWith("- ") || trimmed.match(/^\d+\.\s+/)) {
        const fact = trimmed.replace(/^-\s+|^\d+\.\s+/, "");
        if (fact) {
          facts.push(fact);
        }
      }
    }

    return facts;
  }
}
