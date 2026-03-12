/**
 * L1 Manager - Date/Category File Management
 *
 * L1 layer provides structured memory storage in date-based and category-based files.
 * - Date files: Daily conversation summaries (e.g., 2026-03-05.md)
 * - Category files: Projects, contacts, tasks, etc.
 */

import * as fs from "node:fs/promises";
import * as path from "node:path";


// ============================================================================
// Types
// ============================================================================

export interface L1Config {
  enabled: boolean;
  dir: string;
  recentDays: number;
  categories: string[];
  autoWrite: boolean;
}

export interface L1Context {
  dateFiles: Array<{ date: string; content: string }>;
  categoryFiles: Array<{ category: string; content: string }>;
}

export interface L1WriteDecision {
  shouldWrite: boolean;
  categories: string[];
  summary?: string;
}


// ============================================================================
// L1 Manager
// ============================================================================

export class L1Manager {
  constructor(private config: L1Config) {}

  /**
   * Check if L1 is enabled
   */
  isEnabled(): boolean {
    return this.config.enabled;
  }

  /**
   * Check if auto-write is enabled for L1
   */
  isAutoWriteEnabled(): boolean {
    return this.config.autoWrite;
  }

  /**
   * Get the directory path for L1 files
   */
  private get dirPath(): string {
    return path.resolve(this.config.dir);
  }

  /**
   * Ensure the L1 directory exists
   */
  private async ensureDir(): Promise<void> {
    try {
      await fs.mkdir(this.dirPath, { recursive: true });
    } catch (error) {
      console.error(`Failed to create L1 directory: ${error}`);
    }
  }

  /**
   * Get file path for a date file
   */
  private getDateFilePath(date: Date): string {
    const dateStr = date.toISOString().split("T")[0]; // YYYY-MM-DD
    return path.join(this.dirPath, `${dateStr}.md`);
  }

  /**
   * Get file path for a category file
   */
  private getCategoryFilePath(category: string): string {
    return path.join(this.dirPath, `${category}.md`);
  }

  /**
   * Read a file if it exists
   */
  private async readFile(filePath: string): Promise<string> {
    try {
      return await fs.readFile(filePath, "utf-8");
    } catch {
      return "";
    }
  }

  /**
   * Write to a file (appending)
   */
  private async writeFile(filePath: string, content: string): Promise<void> {
    try {
      await this.ensureDir();
      await fs.writeFile(filePath, content, "utf-8");
    } catch (error) {
      console.error(`Failed to write L1 file ${filePath}: ${error}`);
    }
  }

  /**
   * Append to a file
   */
  private async appendFile(filePath: string, content: string): Promise<void> {
    try {
      await this.ensureDir();
      await fs.appendFile(filePath, content, "utf-8");
    } catch (error) {
      console.error(`Failed to append to L1 file ${filePath}: ${error}`);
    }
  }

  /**
   * Read context from recent date files and all category files
   */
  async readContext(): Promise<L1Context> {
    if (!this.config.enabled) {
      return { dateFiles: [], categoryFiles: [] };
    }

    try {
      await this.ensureDir();

      // Read date files for recent days
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

      // Read all category files
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

  /**
   * Append content to today's date file
   */
  async appendToday(content: string): Promise<void> {
    if (!this.config.enabled) {
      return;
    }

    try {
      const filePath = this.getDateFilePath(new Date());
      const existing = await this.readFile(filePath);
      await this.writeFile(filePath, existing + content);
    } catch (error) {
      console.error(`Failed to append to today's L1 file: ${error}`);
    }
  }

  /**
   * Append content to a category file
   */
  async appendToCategory(category: string, content: string): Promise<void> {
    if (!this.config.enabled || !this.config.categories.includes(category)) {
      return;
    }

    try {
      const filePath = this.getCategoryFilePath(category);
      const existing = await this.readFile(filePath);
      await this.writeFile(filePath, existing + content);
    } catch (error) {
      console.error(`Failed to append to L1 category file: ${error}`);
    }
  }

  /**
   * Analyze conversation content to determine if it should be written to L1
   * and which categories it belongs to.
   *
   * This is a simple heuristic-based analysis. In a production environment,
   * you might want to use an LLM for more sophisticated analysis.
   */
  analyzeCapture(conversation: string): L1WriteDecision {
    const text = conversation.toLowerCase();

    // Keywords that indicate project-related content
    const projectKeywords = [
      "project", "repo", "repository", "codebase", "feature", "bug", "issue",
      "pull request", "pr", "commit", "branch", "merge", "deploy", "release",
    ];

    // Keywords that indicate contact-related content
    const contactKeywords = [
      "contact", "email", "phone", "slack", "discord", "team", "colleague",
      "coworker", "manager", "client", "customer", "vendor",
    ];

    // Keywords that indicate task-related content
    const taskKeywords = [
      "task", "todo", "to-do", "reminder", "deadline", "schedule", "agenda",
      "meeting", "action item", "follow-up", "need to", "should", "must",
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

    // Always write to date file if there's meaningful content
    const shouldWrite = conversation.length > 50 || categories.length > 0;

    // Generate a simple summary (first 200 chars)
    const summary = conversation.slice(0, 200).trim() + (conversation.length > 200 ? "..." : "");

    return { shouldWrite, categories, summary };
  }

  /**
   * Extract key information from L1 file content
   */
  private extractKeyInfo(content: string): string {
    const lines = content.split('\n');
    const keyLines: string[] = [];
    const seen = new Set<string>();

    const importantPatterns = [
      /^#{1,3}\s+/,
      /^[*-]\s+\[?\[?!.*\]\]?\s*/,
      /^[*-]\s+.*(TODO|FIXME|HACK|任务|截止|deadline)/i,
      /.*(重要|关键|core|注意|警告|critical|essential|must|必须|配置|config|项目|project|任务|task).*/i,
    ];

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.length < 3) continue;

      const isImportant = importantPatterns.some(p => p.test(trimmed));
      if (isImportant && !seen.has(trimmed.slice(0, 80))) {
        seen.add(trimmed.slice(0, 80));
        keyLines.push(line);
      }
      if (keyLines.length >= 10) break;
    }

    // Add recent lines
    const recentLines = lines.slice(-15);
    for (const line of recentLines) {
      const trimmed = line.trim();
      if (trimmed && !seen.has(trimmed.slice(0, 80))) {
        keyLines.push(line);
      }
    }

    return keyLines.join('\n');
  }

  /**
   * Compact a single L1 file content
   */
  private compactFileContent(content: string, maxBytes: number = 2000): string {
    const bytes = Buffer.byteLength(content, 'utf-8');
    if (bytes <= maxBytes) {
      return content;
    }

    const lines = content.split('\n');
    const header = lines.slice(0, 10);
    const keyInfo = this.extractKeyInfo(lines.slice(10).join('\n'));
    const recent = lines.slice(-15);

    return [
      ...header,
      '',
      '--- [已精简] ---',
      keyInfo,
      '',
      '--- [最近] ---',
      ...recent,
    ].join('\n');
  }

  /**
   * Format L1 content as a System Prompt block for injection
   * With automatic compacting if content is too large
   */
  async toSystemBlock(maxBytesPerFile: number = 2000): Promise<string> {
    const context = await this.readContext();
    const parts: string[] = [];

    // Add date files (compacted)
    for (const file of context.dateFiles) {
      if (file.content.trim()) {
        const compacted = this.compactFileContent(file.content, maxBytesPerFile);
        parts.push(`### ${file.date}\n${compacted.trim()}`);
      }
    }

    // Add category files (compacted)
    for (const file of context.categoryFiles) {
      if (file.content.trim()) {
        const compacted = this.compactFileContent(file.content, maxBytesPerFile);
        parts.push(`### ${file.category}\n${compacted.trim()}`);
      }
    }

    if (parts.length === 0) {
      return "";
    }

    return `<!-- L1: Recent Context -->\n${parts.join("\n\n")}\n<!-- End L1 -->`;
  }

  /**
   * Write to L1 based on conversation analysis
   */
  async writeFromConversation(conversation: string): Promise<L1WriteDecision> {
    if (!this.config.autoWrite) {
      return { shouldWrite: false, categories: [] };
    }

    const decision = this.analyzeCapture(conversation);

    if (decision.shouldWrite) {
      // Write to date file
      if (decision.summary) {
        await this.appendToday(`\n${decision.summary}\n`);
      }

      // Write to category files
      for (const category of decision.categories) {
        if (decision.summary) {
          await this.appendToCategory(category, `\n${decision.summary}\n`);
        }
      }
    }

    return decision;
  }

  /**
   * Archive old files to archive subdirectory
   * Returns count of archived files
   */
  async archiveOldFiles(maxAgeDays: number = 14): Promise<{ archivedCount: number; archivedFiles: string[] }> {
    if (!this.config.enabled) {
      return { archivedCount: 0, archivedFiles: [] };
    }

    try {
      await this.ensureDir();
      const archiveDir = path.join(this.dirPath, "archive", new Date().toISOString().slice(0, 7));
      await fs.mkdir(archiveDir, { recursive: true });

      const files = await fs.readdir(this.dirPath);
      const cutoffTime = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
      const archivedFiles: string[] = [];

      // Patterns for files that should be archived
      const testPatterns = /test|report|summary|final|plugin/i;

      for (const file of files) {
        if (!file.endsWith(".md")) continue;

        const filePath = path.join(this.dirPath, file);
        const stats = await fs.stat(filePath);

        // Archive if: old date file OR test/report file
        const isOldDateFile = file.match(/^\d{4}-\d{2}-\d{2}\.md$/) && stats.mtimeMs < cutoffTime;
        const isTestFile = testPatterns.test(file) && !this.config.categories.some(c => file.startsWith(c));

        if (isOldDateFile || isTestFile) {
          await fs.rename(filePath, path.join(archiveDir, file));
          archivedFiles.push(file);
        }
      }

      return { archivedCount: archivedFiles.length, archivedFiles };
    } catch (error) {
      console.error(`Failed to archive L1 files: ${error}`);
      return { archivedCount: 0, archivedFiles: [] };
    }
  }

  /**
   * Get statistics about L1 directory
   */
  async getStats(): Promise<{
    totalFiles: number;
    totalSizeBytes: number;
    dateFiles: number;
    categoryFiles: number;
    otherFiles: number;
  }> {
    if (!this.config.enabled) {
      return { totalFiles: 0, totalSizeBytes: 0, dateFiles: 0, categoryFiles: 0, otherFiles: 0 };
    }

    try {
      await this.ensureDir();
      const files = await fs.readdir(this.dirPath);
      let totalSize = 0;
      let dateFiles = 0;
      let categoryFiles = 0;
      let otherFiles = 0;

      for (const file of files) {
        if (!file.endsWith(".md")) continue;

        const filePath = path.join(this.dirPath, file);
        const stats = await fs.stat(filePath);
        totalSize += stats.size;

        if (file.match(/^\d{4}-\d{2}-\d{2}\.md$/)) {
          dateFiles++;
        } else if (this.config.categories.some(c => file.startsWith(c))) {
          categoryFiles++;
        } else {
          otherFiles++;
        }
      }

      return {
        totalFiles: dateFiles + categoryFiles + otherFiles,
        totalSizeBytes: totalSize,
        dateFiles,
        categoryFiles,
        otherFiles
      };
    } catch (error) {
      console.error(`Failed to get L1 stats: ${error}`);
      return { totalFiles: 0, totalSizeBytes: 0, dateFiles: 0, categoryFiles: 0, otherFiles: 0 };
    }
  }

  /**
   * Clean up test and temporary files
   */
  async cleanup(): Promise<{ removedCount: number; removedFiles: string[] }> {
    if (!this.config.enabled) {
      return { removedCount: 0, removedFiles: [] };
    }

    try {
      await this.ensureDir();
      const files = await fs.readdir(this.dirPath);
      const testPatterns = /test|stress|batch|encoding|structure|comprehensive/i;
      const removedFiles: string[] = [];

      for (const file of files) {
        if (!file.endsWith(".md")) continue;

        // Skip category files and recent date files
        if (this.config.categories.some(c => file.startsWith(c))) continue;
        if (file.match(/^\d{4}-\d{2}-\d{2}\.md$/)) continue;

        if (testPatterns.test(file)) {
          const filePath = path.join(this.dirPath, file);
          await fs.unlink(filePath);
          removedFiles.push(file);
        }
      }

      return { removedCount: removedFiles.length, removedFiles };
    } catch (error) {
      console.error(`Failed to cleanup L1 files: ${error}`);
      return { removedCount: 0, removedFiles: [] };
    }
  }
}