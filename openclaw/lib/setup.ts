/**
 * Memory Manager Setup
 *
 * Provides memory optimization for L0/L1 layers.
 * Uses trigger-based optimization instead of cron jobs.
 */

import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as os from "node:os";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

const SCRIPT_VERSION = "1.3.0";

// ============================================================================
// Memory Optimizer Configuration
// ============================================================================

export interface OptimizerConfig {
  l0Path: string;           // L0 file path (memory.md)
  l1Dir: string;            // L1 directory path
  contextMaxKB: number;     // Max context size in KB (default: 50)
  l1FileMaxKB: number;      // Max single L1 file size in KB (default: 50)
  l1KeepRecentDays: number; // Keep L1 files for N days (default: 7)
  l0MaxLines: number;       // Max L0 lines (default: 100)
  serverUrl?: string;        // Server URL for L2 deduplication
  apiKey?: string;           // API key for L2 deduplication
}

export interface OptimizationResult {
  optimized: boolean;
  originalSizeKB: number;
  newSizeKB: number;
  savedKB: number;
  actions: string[];
}

// ============================================================================
// Memory Optimizer Class (Trigger-based)
// ============================================================================

export class MemoryOptimizer {
  private config: OptimizerConfig;
  private lastOptimization: number = 0;
  private minIntervalMs: number = 60 * 1000; // Min 1 min between optimizations
  private messageCount: number = 0;
  private messageThreshold: number = 10;  // Trigger after 10 messages

  constructor(config: Partial<OptimizerConfig> & { l0Path: string; l1Dir: string }) {
    this.config = {
      contextMaxKB: 50,
      l1FileMaxKB: 50,
      l1KeepRecentDays: 7,
      l0MaxLines: 100,
      serverUrl: undefined,
      apiKey: undefined,
      ...config,
    };
  }

  /**
   * Get file size in bytes
   */
  private async getFileSize(filePath: string): Promise<number> {
    try {
      const stats = await fs.stat(filePath);
      return stats.size;
    } catch {
      return 0;
    }
  }

  /**
   * Get file line count
   */
  private async getFileLines(filePath: string): Promise<number> {
    try {
      const content = await fs.readFile(filePath, "utf-8");
      return content.split("\n").length;
    } catch {
      return 0;
    }
  }

  /**
   * Get total context size (L0 + L1)
   */
  async getContextSize(): Promise<{ l0Bytes: number; l1Bytes: number; totalBytes: number }> {
    let l0Bytes = 0;
    let l1Bytes = 0;

    // L0 size
    l0Bytes = await this.getFileSize(this.config.l0Path);

    // L1 size (all .md files in directory, excluding archive)
    try {
      const files = await fs.readdir(this.config.l1Dir);
      for (const file of files) {
        if (!file.endsWith(".md")) continue;
        if (file.includes("archive")) continue;

        const filePath = path.join(this.config.l1Dir, file);
        const stat = await fs.stat(filePath);
        if (stat.isFile()) {
          l1Bytes += stat.size;
        }
      }
    } catch {
      // Directory doesn't exist
    }

    return {
      l0Bytes,
      l1Bytes,
      totalBytes: l0Bytes + l1Bytes,
    };
  }

  /**
   * Update message count (call this after each user message)
   */
  updateMessageCount(count: number): void {
    this.messageCount = count;
  }

  /**
   * Set message threshold (can be overridden from config)
   */
  setMessageThreshold(threshold: number): void {
    this.messageThreshold = threshold;
  }

  /**
   * Check if optimization is needed
   * Triggers when: context exceeds threshold OR message count exceeds threshold
   */
  async needsOptimization(): Promise<boolean> {
    const { totalBytes } = await this.getContextSize();
    const maxBytes = this.config.contextMaxKB * 1024;
    const needsBySize = totalBytes > maxBytes;
    const needsByMessages = this.messageCount > this.messageThreshold;
    return needsBySize || needsByMessages;
  }

  /**
   * Check and optimize if needed (trigger-based)
   * Returns null if no optimization was needed
   */
  async checkAndOptimize(): Promise<OptimizationResult | null> {
    // Rate limiting
    const now = Date.now();
    if (now - this.lastOptimization < this.minIntervalMs) {
      return null;
    }

    const needs = await this.needsOptimization();
    if (!needs) {
      return null;
    }

    this.lastOptimization = now;
    return this.optimize();
  }

  /**
   * Force optimization regardless of threshold
   * Calls memory_manager.sh script for all operations
   */
  async optimize(): Promise<OptimizationResult> {
    const actions: string[] = [];
    const { totalBytes: originalBytes } = await this.getContextSize();

    // Call memory_manager.sh script for optimization with env vars
    const scriptPath = path.join(os.homedir(), ".openclaw", "scripts", "memory_manager.sh");
    const envVars: string[] = [];
    if (this.config.serverUrl) {
      envVars.push(`MEM0_SERVER_URL=${this.config.serverUrl}`);
    }
    if (this.config.apiKey) {
      envVars.push(`MEM0_API_KEY=${this.config.apiKey}`);
    }
    if (this.config.l1Dir) {
      envVars.push(`MEMORY_DIR=${this.config.l1Dir}`);
    }
    if (this.config.l0Path) {
      envVars.push(`L0_FILE=${this.config.l0Path}`);
    }

    const envPrefix = envVars.length > 0 ? `${envVars.join(" ")} ` : "";
    const command = `${envPrefix}bash "${scriptPath}" optimize`;

    try {
      const { stdout, stderr } = await execAsync(command);
      actions.push("Shell optimization completed");

      // Parse stderr for detailed actions
      const lines = stderr.split("\n").filter(l => l.trim());
      for (const line of lines) {
        if (line.includes("归档了") || line.includes("压缩了") ||
            line.includes("去重") || line.includes("精简") ||
            line.includes("删除")) {
          actions.push(`Shell: ${line.trim()}`);
        }
      }
    } catch (error) {
      actions.push(`Shell optimization failed: ${error}`);
    }

    const { totalBytes: newBytes } = await this.getContextSize();

    return {
      optimized: true,
      originalSizeKB: Math.round(originalBytes / 1024),
      newSizeKB: Math.round(newBytes / 1024),
      savedKB: Math.round((originalBytes - newBytes) / 1024),
      actions,
    };
  }

  /**
   * Compress large L1 files with intelligent summary
   */
  private async compressL1Files(): Promise<string[]> {
    const actions: string[] = [];
    const maxBytes = this.config.l1FileMaxKB * 1024;

    try {
      await fs.mkdir(this.config.l1Dir, { recursive: true });
      const files = await fs.readdir(this.config.l1Dir);

      for (const file of files) {
        if (!file.endsWith(".md") || file.includes("archive")) continue;

        const filePath = path.join(this.config.l1Dir, file);
        const stat = await fs.stat(filePath);
        if (!stat.isFile()) continue;

        if (stat.size > maxBytes) {
          const content = await fs.readFile(filePath, "utf-8");
          const lines = content.split("\n");

          // Smart compression: extract core summary
          const header = this.extractHeader(lines, file);
          const summary = this.extractSummary(lines);
          const recent = lines.slice(-50); // Last 50 lines for recent context

          const compressed = [
			...header,
            "",
            `--- [智能压缩于 ${new Date().toISOString().slice(0, 16)}] ---`,
            "",
            "## 核心信息摘要",
            summary,
            "",
            "## 最近更新",
            ...recent,
          ].join("\n");

          await fs.writeFile(filePath, compressed, "utf-8");
          actions.push(`compressed: ${file}`);
        }
      }
    } catch (error) {
      console.error(`[MemoryOptimizer] compressL1Files error: ${error}`);
    }

    return actions;
  }

  /**
   * Extract file header (first 15-20 lines)
   */
  private extractHeader(lines: string[], filename: string): string[] {
    const headerLines = lines.slice(0, 20);
    // Filter out empty lines at the start for cleaner header
    let startIdx = 0;
    while (startIdx < headerLines.length && headerLines[startIdx].trim() === "") {
      startIdx++;
    }
    return headerLines.slice(startIdx, Math.min(startIdx + 20, headerLines.length));
  }

  /**
   * Extract core summary using keyword-based and pattern matching
   */
  private extractSummary(lines: string[]): string {
    const summary: string[] = [];
    const seen = new Set<string>();

    // Key patterns for important content
    const patterns = [
      // Headers (#, ##, ###)
      /^#{1,3}\s+.+/,
      // Important markers
      /^[*-]\s+\[?\[?!.*\]\]?\s*.+/,
      // Tasks/TODO
      /^\s*[-*]\s*\[?\[xX]\]?\s*(TODO|FIXME|HACK|XXX|任务|截止|deadline)/i,
      // Important statements with key terms
      /^(.*(重要|关键|关键信息|core|核心|注意|警告|warning|note|critical|essential|must|必须|应该).*).*$/i,

      // Questions and decisions
      /^\s*[-*]\s*(\?|决策|decision|question|question|结论|conclusion)/i,
    ];

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.length < 5) continue;

      // Check against patterns
      let isImportant = false;

      for (const pattern of patterns) {
        if (pattern.test(trimmed)) {
          isImportant = true;
          break;
        }
      }

      // Also check for important keywords in the line
      const importantKeywords = [
        "配置", "config", "设置", "setting", "option",
        "环境", "environment", "env", "变量", "variable",
        "API", "接口", "endpoint", "url", "地址", "host",
        "密钥", "key", "token", "secret", "密码", "password",
        "数据库", "database", "db", "连接", "connection",
        "规则", "rule", "策略", "policy", "约束", "constraint",
        "依赖", "dependency", "requirement", "prerequisite",
        "架构", "architecture", "结构", "structure", "组件", "component",
        "核心", "core", "主要", "main", "primary", "关键", "critical",
        "优先", "priority", "重要", "important", "必须", "required",
        "完成", "完成", "done", "finished", "已解决", "resolved",
      ];

      for (const keyword of importantKeywords) {
        if (trimmed.toLowerCase().includes(keyword)) {
          isImportant = true;
          break;
        }
      }

      if (isImportant) {
        const key = trimmed.slice(0, 80); // Limit line length
        if (!seen.has(key)) {
          seen.add(key);
          summary.push(trimmed.slice(0, 100)); // Store up to 100 chars per line
        }
      }

      // Stop after extracting ~15-20 key items
      if (summary.length >= 20) break;
    }

    return summary.length > 0 ? summary.join("\n") : "(无明显关键信息，已保留最近更新)";
  }

  /**
   * Deduplicate L1 content
   */
  private async deduplicateL1Content(): Promise<string[]> {
    const actions: string[] = [];

    try {
      const files = await fs.readdir(this.config.l1Dir);

      for (const file of files) {
        if (!file.endsWith(".md") || file.includes("archive")) continue;

        const filePath = path.join(this.config.l1Dir, file);
        const stat = await fs.stat(filePath);
        if (!stat.isFile()) continue;

        const content = await fs.readFile(filePath, "utf-8");
        const lines = content.split("\n");
        const originalLines = lines.length;

        // For date files, use uniq (consecutive duplicates only)
        // For category files, use Set (all duplicates)
        const isDateFile = /^\d{4}-\d{2}-\d{2}\.md$/.test(file);

        let dedupedLines: string[];
        if (isDateFile) {
          // Remove consecutive duplicates
          dedupedLines = lines.filter((line, i) => i === 0 || lines[i - 1] !== line);
        } else {
          // Remove all duplicates while preserving order
          const seen = new Set<string>();
          dedupedLines = lines.filter(line => {
            if (seen.has(line)) return false;
            seen.add(line);
            return true;
          });
        }

        if (dedupedLines.length < originalLines) {
          await fs.writeFile(filePath, dedupedLines.join("\n"), "utf-8");
          actions.push(`deduped: ${file} (removed ${originalLines - dedupedLines.length} lines)`);
        }
      }
    } catch (error) {
      console.error(`[MemoryOptimizer] deduplicateL1Content error: ${error}`);
    }

    return actions;
  }

  /**
   * Archive old L1 files
   */
  private async archiveOldFiles(): Promise<string[]> {
    const actions: string[] = [];
    const cutoffMs = this.config.l1KeepRecentDays * 24 * 60 * 60 * 1000;
    const cutoffTime = Date.now() - cutoffMs;

    try {
      const archiveDir = path.join(this.config.l1Dir, "archive", new Date().toISOString().slice(0, 7));
      await fs.mkdir(archiveDir, { recursive: true });

      const files = await fs.readdir(this.config.l1Dir);

      for (const file of files) {
        if (!file.endsWith(".md")) continue;

        const filePath = path.join(this.config.l1Dir, file);
        const stat = await fs.stat(filePath);
        if (!stat.isFile()) continue;

        // Archive old date files
        const isDateFile = /^\d{4}-\d{2}-\d{2}\.md$/.test(file);
        const isOld = stat.mtimeMs < cutoffTime;

        if (isDateFile && isOld) {
          await fs.rename(filePath, path.join(archiveDir, file));
          actions.push(`archived: ${file}`);
        }

        // Archive test/temp files
        if (/test|temp|tmp|backup/i.test(file) && !/^(projects|contacts|tasks|preferences)/.test(file)) {
          await fs.rename(filePath, path.join(archiveDir, file));
          actions.push(`archived temp: ${file}`);
        }
      }
    } catch (error) {
      console.error(`[MemoryOptimizer] archiveOldFiles error: ${error}`);
    }

    return actions;
  }

  /**
   * Prune L0 file
   */
  private async pruneL0File(): Promise<string[]> {
    const actions: string[] = [];

    try {
      const lineCount = await this.getFileLines(this.config.l0Path);
      if (lineCount <= this.config.l0MaxLines) {
        return actions;
      }

      const content = await fs.readFile(this.config.l0Path, "utf-8");
      const lines = content.split("\n");

      // Keep header (first 30 lines) + tail (last 50 lines)
      const header = lines.slice(0, 30);
      const tail = lines.slice(-50);

      const pruned = [
        ...header,
        "",
        "---",
        `## 最近记录 (自动精简于 ${new Date().toISOString().slice(0, 10)})`,
        ...tail,
      ].join("\n");

      await fs.writeFile(this.config.l0Path, pruned, "utf-8");
      actions.push(`pruned L0: ${lineCount} -> ${pruned.split("\n").length} lines`);
    } catch (error) {
      console.error(`[MemoryOptimizer] pruneL0File error: ${error}`);
    }

    return actions;
  }
}

// ============================================================================
// Shell Script (for manual use only)
// ============================================================================

// Memory manager shell script template
const MEMORY_MANAGER_SCRIPT = `#!/bin/bash
# ============================================
# Mem0 自动记忆管理系统 v${SCRIPT_VERSION}
# 由 mem0-openclaw-plugin 自动生成
# 支持自动优化、去重、压缩
# ============================================

set -e

# 配置 (可通过环境变量覆盖)
MEMORY_DIR="\${MEMORY_DIR:-$HOME/.openclaw/workspace/memory}"
ARCHIVE_DIR="\$MEMORY_DIR/archive"
L0_FILE="\${L0_FILE:-$HOME/.openclaw/workspace/memory.md}"
LOG_DIR="$HOME/.openclaw/logs"
LOG_FILE="\$LOG_DIR/memory_manager.log"
SERVER_URL="\${MEM0_SERVER_URL:-http://localhost:8000}"
API_KEY="\${MEM0_API_KEY:-}"
AGENT_ID="\${MEM0_AGENT_ID:-openclaw-main}"

# 阈值配置
CONTEXT_MAX_KB=\${CONTEXT_MAX_KB:-100}           # Context 最大 KB
L1_FILE_MAX_KB=\${L1_FILE_MAX_KB:-50}            # 单个 L1 文件最大 KB
L1_KEEP_RECENT_DAYS=\${L1_KEEP_RECENT_DAYS:-7}   # L1 保留最近天数
L0_MAX_LINES=\${L0_MAX_LINES:-100}               # L0 最大行数

# 确保日志目录存在
mkdir -p "\$LOG_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# 获取文件大小 (bytes)
get_file_size() {
    wc -c < "\$1" 2>/dev/null || echo 0
}

# 获取文件行数
get_file_lines() {
    wc -l < "\$1" 2>/dev/null || echo 0
}

# ============================================
# 1. L1 自动归档
# ============================================
archive_l1_files() {
    log "=== 开始 L1 归档 ==="

    mkdir -p "\$ARCHIVE_DIR/$(date +%Y-%m)"

    # 归档超过保留天数的日期文件
    local archived_count=0
    local cutoff_days=\$L1_KEEP_RECENT_DAYS
    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "20*.md" -mtime +\$cutoff_days 2>/dev/null); do
        mv "\$file" "\$ARCHIVE_DIR/$(date +%Y-%m)/"
        ((archived_count++)) || true
    done
    log "归档了 \$archived_count 个过期日期文件 (>\${cutoff_days}天)"

    # 归档测试文件和临时文件
    local test_patterns="test|Test|TEST|report|Report|summary|Summary|comprehensive|temp|tmp|backup"
    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null); do
        filename=\$(basename "\$file")
        if [[ "\$filename" =~ \$test_patterns ]] && [[ ! "\$filename" =~ ^(projects|contacts|tasks|preferences) ]]; then
            mv "\$file" "\$ARCHIVE_DIR/$(date +%Y-%m)/" 2>/dev/null || true
            log "归档临时文件: \$filename"
        fi
    done
}

# ============================================
# 1.5 L1 文件压缩 (智能摘要)
# ============================================
compress_l1_files() {
    log "=== 开始 L1 智能压缩 ==="

    local max_bytes=\$((L1_FILE_MAX_KB * 1024))
    local compressed_count=0

    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -v archive); do
        local file_size=\$(get_file_size "\$file")
        local filename=\$(basename "\$file")

        if [ \$file_size -gt \$max_bytes ]; then
            log "压缩大文件: \$filename (\$((file_size / 1024))KB)"

            # 备份原文件
            cp "\$file" "\$file.bak"

            # 智能压缩：提取头部 + 核心摘要 + 最近更新
            {
                # 1. 提取头部 (跳过开头的空行)
                head -20 "\$file" | grep -v '^\$'
                echo ""
                echo "--- [智能压缩于 $(date '+%Y-%m-%d %H:%M')] ---"
                echo ""
                echo "## 核心信息摘要"
                echo ""

                # 2. 提取关键信息 (使用多种模式)
                grep -iE \
                    -e '^[#]+.*$' \
                    -e '^[-*].*\[.*\].*$' \
                    -e '^[-*].*\[?x?\].*TODO|FIXME|HACK|任务|截止' \
                    -e '.*(重要|关键|核心|core|注意|警告|critical|essential|must|必须|should|应该).*\$' \
                    -e '.*(配置|设置|environment|env|变量|variable|API|接口|url|host).*\$' \
                    -e '.*(密钥|key|token|secret|密码|password|database|db|连接).*\$' \
                    -e '.*(规则|策略|policy|约束|constraint|依赖|dependency).*\$' \
                    -e '.*(架构|结构|组件|component|优先|priority).*\$' \
                    -e '.*(完成|done|finished|已解决|resolved|conclusion).*\$' \
                    "\$file" 2>/dev/null | head -15

                echo ""
                echo "## 最近更新"
                tail -50 "\$file"
            } > "\${file}.tmp"

            mv "\${file}.tmp" "\$file"
            rm -f "\$file.bak"

            local new_size=\$(get_file_size "\$file")
            log "  压缩后: \$((new_size / 1024))KB (减少 \$(((file_size - new_size) / 1024))KB)"
            ((compressed_count++)) || true
        fi
    done

    log "压缩了 \$compressed_count 个大文件"
}

# ============================================
# 1.6 L1 内容去重 (新增)
# ============================================
deduplicate_l1_content() {
    log "=== 开始 L1 去重 ==="

    local dedup_count=0

    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -v archive); do
        local filename=\$(basename "\$file")
        local orig_lines=\$(get_file_lines "\$file")

        # 去除完全重复的行 (保留第一次出现)
        sort -u "\$file" -o "\${file}.dedup" 2>/dev/null || continue

        # 如果是日期文件，需要保持时间顺序，不能简单排序
        if [[ "\$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.md$ ]]; then
            # 日期文件：只去除连续重复行
            uniq "\$file" > "\${file}.dedup"
        fi

        local new_lines=\$(get_file_lines "\${file}.dedup")
        local removed=\$((orig_lines - new_lines))

        if [ \$removed -gt 0 ]; then
            mv "\${file}.dedup" "\$file"
            log "去重 \$filename: 删除 \$removed 行重复内容"
            ((dedup_count++)) || true
        else
            rm -f "\${file}.dedup"
        fi
    done

    log "处理了 \$dedup_count 个文件"
}

# ============================================
# 2. L0 自动精简
# ============================================
prune_l0_file() {
    log "=== 开始 L0 精简 ==="

    if [ ! -f "\$L0_FILE" ]; then
        log "L0 文件不存在"
        return
    fi

    local line_count=\$(get_file_lines "\$L0_FILE")
    local max_lines=\$L0_MAX_LINES

    if [ \$line_count -gt \$max_lines ]; then
        # 创建精简版本：保留头部和最近的记录
        {
            head -30 "\$L0_FILE"
            echo ""
            echo "---"
            echo "## 最近记录 (自动精简于 $(date '+%Y-%m-%d'))"
            tail -50 "\$L0_FILE"
        } > /tmp/l0_temp_\$\$

        mv /tmp/l0_temp_\$\$ "\$L0_FILE"
        local new_lines=\$(get_file_lines "\$L0_FILE")
        log "L0 从 \$line_count 行精简到 \$new_lines 行"
    else
        log "L0 文件行数 (\$line_count) 在合理范围内 (<=\$max_lines)"
    fi
}

# ============================================
# 3. L2 去重和清理
# ============================================
clean_l2_memories() {
    log "=== 开始 L2 清理 ==="
    
    if [ -z "\$API_KEY" ]; then
        log "警告: 未配置 MEM0_API_KEY，跳过 L2 清理"
        return
    fi
    
    # 执行去重
    local response=\$(curl -s -X POST "\$SERVER_URL/deduplicate?agent_id=\$AGENT_ID&dry_run=false" \\
        -H "Authorization: Bearer \$API_KEY" 2>/dev/null || echo '{"deleted_count": 0}')
    
    local removed=\$(echo "\$response" | grep -o '"deleted_count":[0-9]*' | cut -d: -f2 || echo "0")
    log "L2 去重完成，删除了 \$removed 条重复记忆"
    
    # 获取当前记忆数
    local stats=\$(curl -s "\$SERVER_URL/memory/stats?agent_id=\$AGENT_ID" \\
        -H "Authorization: Bearer \$API_KEY" 2>/dev/null || echo '{}')
    local count=\$(echo "\$stats" | grep -o '"total_memories":[0-9]*' | cut -d: -f2 || echo "0")
    log "L2 当前记忆数: \$count"
}

# ============================================
# 4. Context 优化报告 (增强：自动优化)
# ============================================
optimize_context() {
    log "=== Context 状态检查 ==="

    local l0_size=0 l1_size=0

    # L0 大小
    if [ -f "\$L0_FILE" ]; then
        l0_size=\$(get_file_size "\$L0_FILE")
        log "L0 文件: \$(basename \$L0_FILE) (\$((l0_size / 1024))KB)"
    fi

    # L1 有效大小 (仅直接 .md 文件，排除 archive)
    local l1_files=\$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -v archive)
    for f in \$l1_files; do
        local f_size=\$(get_file_size "\$f")
        l1_size=\$((l1_size + f_size))
    done

    local total=\$((l0_size + l1_size))
    local max_bytes=\$((CONTEXT_MAX_KB * 1024))

    log "L1 有效大小: \$((l1_size / 1024))KB"
    log "Context 总计: \$((total / 1024))KB (阈值: \${CONTEXT_MAX_KB}KB)"

    # 自动优化：如果超过阈值，自动执行压缩和归档
    if [ \$total -gt \$max_bytes ]; then
        log ""
        log "⚠️ Context 超过阈值，启动自动优化..."
        log ""

        # 1. 先压缩大文件
        compress_l1_files

        # 2. 去重
        deduplicate_l1_content

        # 3. 归档旧文件
        archive_l1_files

        # 4. 精简 L0
        prune_l0_file

        # 5. 重新计算大小
        local new_l0=0 new_l1=0
        if [ -f "\$L0_FILE" ]; then
            new_l0=\$(get_file_size "\$L0_FILE")
        fi
        for f in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -v archive); do
            new_l1=\$((new_l1 + \$(get_file_size "\$f")))
        done
        local new_total=\$((new_l0 + new_l1))

        log ""
        log "✅ 自动优化完成"
        log "   优化前: \$((total / 1024))KB"
        log "   优化后: \$((new_total / 1024))KB"
        log "   减少: \$(((total - new_total) / 1024))KB"
    else
        log "✅ Context 大小正常 (\$((total / 1024))KB < \${CONTEXT_MAX_KB}KB)"
    fi
}

# ============================================
# 主函数
# ============================================
main() {
    log "=========================================="
    log "开始记忆自动管理 v${SCRIPT_VERSION}"
    log "=========================================="

    case "\${1:-all}" in
        archive)
            archive_l1_files
            ;;
        prune)
            prune_l0_file
            ;;
        compress)
            compress_l1_files
            ;;
        dedup)
            deduplicate_l1_content
            ;;
        l2)
            clean_l2_memories
            ;;
        context|status)
            optimize_context
            ;;
        optimize)
            # 强制优化：不管是否超阈值
            log "强制优化模式"
            compress_l1_files
            deduplicate_l1_content
            archive_l1_files
            prune_l0_file
            log "强制优化完成"
            ;;
        all|*)
            # 标准流程：归档 -> 去重 -> 压缩 -> L0精简 -> L2清理 -> Context检查(可能触发自动优化)
            archive_l1_files
            deduplicate_l1_content
            compress_l1_files
            prune_l0_file
            clean_l2_memories
            optimize_context
            ;;
    esac

    log "=========================================="
    log "记忆管理完成"
    log "=========================================="
}

main "\$@"
`;

export interface SetupConfig {
  serverUrl: string;
  apiKey: string;
  agentId: string;
}

/**
 * Get script path (for manual use)
 */
function getScriptPath(): string {
  return path.join(os.homedir(), ".openclaw", "scripts", "memory_manager.sh");
}

/**
 * Check if script exists
 */
async function scriptExists(): Promise<boolean> {
  try {
    await fs.access(getScriptPath());
    return true;
  } catch {
    return false;
  }
}

/**
 * Create the memory manager script (for manual/command-line use)
 * Note: Automatic optimization is now handled by MemoryOptimizer class
 */
async function createScript(config: SetupConfig): Promise<string> {
  const scriptPath = getScriptPath();
  const scriptsDir = path.dirname(scriptPath);

  // Ensure directory exists
  await fs.mkdir(scriptsDir, { recursive: true });

  // Write script with config embedded
  const script = MEMORY_MANAGER_SCRIPT
    .replace(/\$\{MEM0_SERVER_URL:-http:\/\/localhost:8000\}/, `\${MEM0_SERVER_URL:-${config.serverUrl}}`)
    .replace(/\$\{MEM0_API_KEY:-\}/, `\${MEM0_API_KEY:-${config.apiKey}}`)
    .replace(/\$\{MEM0_AGENT_ID:-openclaw-main\}/, `\${MEM0_AGENT_ID:-${config.agentId}}`);

  await fs.writeFile(scriptPath, script, { mode: 0o755 });

  return scriptPath;
}

/**
 * Run initial cleanup/optimization on first install or load
 * This reduces context size to acceptable levels after plugin initialization
 */
export async function runInitialOptimization(optimizer: MemoryOptimizer): Promise<{
  originalSizeKB: number;
  newSizeKB: number;
  savedKB: number;
}> {
  const { totalBytes: originalBytes } = await optimizer.getContextSize();

  console.log(`[mem0-setup] Initial optimization: ${Math.round(originalBytes / 1024)}KB current size`);

  // Run optimization (force optimization regardless of threshold)
  const result = await optimizer.optimize();

  const { totalBytes: newBytes } = await optimizer.getContextSize();
  const savedKB = Math.round((originalBytes - newBytes) / 1024);

  console.log(`[mem0-setup] Initial optimization complete: ${Math.round(originalBytes / 1024)}KB -> ${Math.round(newBytes / 1024)}KB (saved ${savedKB}KB)`);

  return {
    originalSizeKB: Math.round(originalBytes / 1024),
    newSizeKB: Math.round(newBytes / 1024),
    savedKB,
  };
}

/**
 * Run setup for first-time installation
 * Creates script for manual use, runs initial optimization to reduce context size
 */
// Auto-write config to openclaw.json
async function autoWriteConfig(config: SetupConfig): Promise<void> {
  const configPath = path.join(os.homedir(), '.openclaw', 'openclaw.json');
  try {
    const existingConfig = await fs.readFile(configPath, 'utf-8');
    let data = JSON.parse(existingConfig);
    if (!data.plugins) data.plugins = {};
    if (!data.plugins.entries) data.plugins.entries = {};
    if (!data.plugins.slots) data.plugins.slots = {};
    if (!data.plugins.allow) data.plugins.allow = [];
    data.plugins.slots.memory = 'openclaw-mem0';
    if (!data.plugins.allow.includes('openclaw-mem0')) {
      data.plugins.allow.push('openclaw-mem0');
    }
    const pluginConfig = {
      enabled: true,
      config: {
        mode: 'server',
        serverUrl: config.serverUrl || process.env.MEM0_SERVER_URL || 'http://localhost:8000',
        serverApiKey: config.apiKey || process.env.MEM0_API_KEY || 'mem0_请设置您的APIKey',
        userId: 'default',
        agentId: config.agentId || process.env.MEM0_AGENT_ID || 'openclaw-default',
        autoRecall: true,
        autoCapture: true,
        topK: 10,
        searchThreshold: 0.3,
        l0Enabled: false,
        l1Enabled: true,
        l1AutoWrite: true,
        contextThresholdKB: 50,
        messageThreshold: 10,
        l0Path: path.join(os.homedir(), 'memory.md'),
        l1Dir: path.join(os.homedir(), 'memory'),
        l1RecentDays: 7,
        l1Categories: ['projects', 'contacts', 'tasks']
      }
    };
    const existing = data.plugins.entries.openclaw_mem0?.config;
    if (existing) {
      for (const key in existing) {
        pluginConfig.config[key] = existing[key];
      }
    }
    data.plugins.entries.openclaw_mem0 = pluginConfig;
    await fs.writeFile(configPath, JSON.stringify(data, null, 2), 'utf-8');
    console.log('[mem0-setup] Auto-written config to openclaw.json');
  } catch (error) {
    console.log('[mem0-setup] Could not auto-write config:', String(error));
  }
}

export async function runSetup(config: SetupConfig, optimizer?: MemoryOptimizer): Promise<{
  scriptPath: string;
  optimizationResult?: {
    originalSizeKB: number;
    newSizeKB: number;
    savedKB: number;
  };
}> {
  const scriptPath = getScriptPath();
  const alreadyExists = await scriptExists();

  // Create script if not exists (for manual use)
  if (alreadyExists) {
    console.log("[mem0-setup] Script already exists");
  } else {
    console.log("[mem0-setup] Creating memory_manager.sh for manual use...");
    await createScript(config);
    console.log(`[mem0-setup] Script created: ${scriptPath}`);
  }

  // Run initial optimization if optimizer is provided
  let optimizationResult;
  if (optimizer) {
    console.log("[mem0-setup] Running initial optimization...");
    optimizationResult = await runInitialOptimization(optimizer);
  }

  console.log("[mem0-setup] Setup complete! Automatic optimization is trigger-based (no cron needed).");

  return { scriptPath, optimizationResult };
}
