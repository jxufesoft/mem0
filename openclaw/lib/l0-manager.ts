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
   * Extract key information from content (headers, important items)
   */
  private extractKeyInfo(content: string, maxLines: number = 30): string {
    const lines = content.split('\n');
    if (lines.length <= maxLines) {
      return content;
    }

    const keyLines: string[] = [];
    const seen = new Set<string>();

    // Key patterns for important content
    const importantPatterns = [
      /^#{1,3}\s+/,
      /^[*-]\s+\[?\[?!.*\]\]?\s*/,
      /^[*-]\s+.*(TODO|FIXME|HACK|任务|截止|deadline)/i,
      /.*(重要|关键|core|注意|警告|critical|essential|must|必须|配置|config|环境|env).*/i,
    ];

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.length < 3) continue;

      const isImportant = importantPatterns.some(p => p.test(trimmed));
      if (isImportant && !seen.has(trimmed.slice(0, 80))) {
        seen.add(trimmed.slice(0, 80));
        keyLines.push(line);
      }
      if (keyLines.length >= 15) break;
    }

    const recentLines = lines.slice(-20);
    for (const line of recentLines) {
      const trimmed = line.trim();
      if (trimmed && !seen.has(trimmed.slice(0, 80))) {
        keyLines.push(line);
      }
    }

    return keyLines.join('\n');
  }

  /**
   * Compact content for system prompt injection
   */
  private compactContent(content: string, maxBytes: number = 8000): string {
    const bytes = Buffer.byteLength(content, 'utf-8');
    if (bytes <= maxBytes) {
      return content;
    }

    const lines = content.split('\n');
    const header = lines.slice(0, 15);
    const keyInfo = this.extractKeyInfo(lines.slice(15).join('\n'), 30);
    const recent = lines.slice(-30);

    const compacted = [
      ...header,
      '',
      '--- [已精简] ---',
      '',
      keyInfo,
      '',
      '--- [最近记录] ---',
      ...recent,
    ].join('\n');

    return compacted;
  }

  /**
   * Format L0 content as a System Prompt block for injection
   * With automatic compacting if content is too large
   */
  async toSystemBlock(maxBytes: number = 8000): Promise<string> {
    let content = await this.readAll();
    if (!content.trim()) {
      return "";
    }

    // Compact if needed
    content = this.compactContent(content, maxBytes);

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

  /**
   * Auto-prune L0 file to keep it concise
   * Keeps header and most recent entries
   */
  async prune(maxLines: number = 100): Promise<{ pruned: boolean; originalLines: number; newLines: number }> {
    if (!this.config.enabled) {
      return { pruned: false, originalLines: 0, newLines: 0 };
    }

    try {
      const content = await this.readAll();
      const lines = content.split("\n");

      if (lines.length <= maxLines) {
        return { pruned: false, originalLines: lines.length, newLines: lines.length };
      }

      // Keep header (first 20 lines) and recent entries
      const header = lines.slice(0, 20);
      const recent = lines.slice(-(maxLines - 25));
      const newContent = [
        ...header,
        "",
        "## Auto-pruned Recent Entries",
        "",
        "> Older entries have been archived. Contact system for full history.",
        "",
        ...recent
      ].join("\n");

      await this.overwrite(newContent);

      return {
        pruned: true,
        originalLines: lines.length,
        newLines: maxLines
      };
    } catch (error) {
      console.error(`Failed to prune L0: ${error}`);
      return { pruned: false, originalLines: 0, newLines: 0 };
    }
  }

  /**
   * Get statistics about L0
   */
  async getStats(): Promise<{ sizeBytes: number; lineCount: number; exists: boolean }> {
    if (!this.config.enabled) {
      return { sizeBytes: 0, lineCount: 0, exists: false };
    }

    try {
      const stats = await fs.stat(this.filePath);
      const content = await this.readAll();
      return {
        sizeBytes: stats.size,
        lineCount: content.split("\n").length,
        exists: true
      };
    } catch {
      return { sizeBytes: 0, lineCount: 0, exists: false };
    }
  }
}