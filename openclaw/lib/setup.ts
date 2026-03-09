/**
 * Memory Manager Setup
 * 
 * Automatically creates memory_manager.sh script and crontab entry
 * when plugin is first loaded on a new machine.
 */

import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as os from "node:os";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

const SCRIPT_VERSION = "1.1.0";

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
# 1.5 L1 文件压缩 (新增)
# ============================================
compress_l1_files() {
    log "=== 开始 L1 压缩 ==="

    local max_bytes=\$((L1_FILE_MAX_KB * 1024))
    local compressed_count=0

    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -v archive); do
        local file_size=\$(get_file_size "\$file")
        local filename=\$(basename "\$file")

        if [ \$file_size -gt \$max_bytes ]; then
            log "压缩大文件: \$filename (\$((file_size / 1024))KB)"

            # 备份原文件
            cp "\$file" "\$file.bak"

            # 保留文件头部 (前 20 行) 和尾部 (最近记录)
            # 提取关键信息，去除重复空行
            {
                head -20 "\$file"
                echo ""
                echo "--- [自动压缩于 $(date '+%Y-%m-%d %H:%M')] ---"
                echo ""
                # 提取包含关键词的行
                grep -E "^[#-]|重要|关键|TODO|FIXME|项目|任务|截止|deadline|important|key" "\$file" 2>/dev/null || true
                echo ""
                echo "## 最近更新"
                tail -30 "\$file"
            } | sed '/^$/N;/^\\n$/D' > "\${file}.tmp"

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
 * Get script path
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
 * Check if crontab is configured
 */
async function crontabConfigured(): Promise<boolean> {
  try {
    const { stdout } = await execAsync("crontab -l 2>/dev/null || echo ''");
    return stdout.includes("memory_manager.sh");
  } catch {
    return false;
  }
}

/**
 * Create the memory manager script
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
 * Setup crontab for automatic execution
 */
async function setupCrontab(): Promise<boolean> {
  const scriptPath = getScriptPath();
  const cronEntry = `0 3 * * * ${scriptPath} >> ~/.openclaw/logs/memory_manager.log 2>&1`;
  
  try {
    // Get current crontab
    const { stdout: currentCrontab } = await execAsync("crontab -l 2>/dev/null || echo ''");
    
    // Check if already configured
    if (currentCrontab.includes("memory_manager.sh")) {
      console.log("[mem0-setup] Crontab already configured");
      return true;
    }
    
    // Add new entry
    const newCrontab = (currentCrontab.trim() + "\n" + cronEntry).trim() + "\n";
    await execAsync(`echo '${newCrontab}' | crontab -`);
    
    console.log("[mem0-setup] Crontab configured: daily at 3:00 AM");
    return true;
  } catch (error) {
    console.error("[mem0-setup] Failed to setup crontab:", error);
    return false;
  }
}

/**
 * Run setup for first-time installation
 */
export async function runSetup(config: SetupConfig): Promise<{
  scriptPath: string;
  crontabConfigured: boolean;
}> {
  const scriptPath = getScriptPath();
  const scriptAlreadyExists = await scriptExists();
  const crontabAlreadyConfigured = await crontabConfigured();
  
  // Create script if not exists
  if (scriptAlreadyExists) {
    console.log("[mem0-setup] Script already exists, skipping creation");
  } else {
    console.log("[mem0-setup] Creating memory_manager.sh...");
    await createScript(config);
    console.log(`[mem0-setup] Script created: ${scriptPath}`);
  }
  
  // Always ensure crontab is configured
  if (crontabAlreadyConfigured) {
    console.log("[mem0-setup] Crontab already configured");
  } else {
    console.log("[mem0-setup] Setting up crontab...");
    await setupCrontab();
  }
  
  // Run first-time optimization only if script was just created
  if (!scriptAlreadyExists) {
    console.log("[mem0-setup] Running initial memory optimization...");
    try {
      await execAsync(`bash ${scriptPath}`);
    } catch (error) {
      console.error("[mem0-setup] Initial optimization failed:", error);
    }
  }
  
  console.log("[mem0-setup] Setup complete!");
  
  return { 
    scriptPath, 
    crontabConfigured: await crontabConfigured() 
  };
}
