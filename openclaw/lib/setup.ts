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

const SCRIPT_VERSION = "1.0.0";

// Memory manager shell script template
const MEMORY_MANAGER_SCRIPT = `#!/bin/bash
# ============================================
# Mem0 自动记忆管理系统 v${SCRIPT_VERSION}
# 由 mem0-openclaw-plugin 自动生成
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

# 确保日志目录存在
mkdir -p "\$LOG_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# ============================================
# 1. L1 自动归档
# ============================================
archive_l1_files() {
    log "=== 开始 L1 归档 ==="
    
    mkdir -p "\$ARCHIVE_DIR/$(date +%Y-%m)"
    
    # 归档超过14天的日期文件
    local archived_count=0
    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "20*.md" -mtime +14 2>/dev/null); do
        mv "\$file" "\$ARCHIVE_DIR/$(date +%Y-%m)/"
        ((archived_count++)) || true
    done
    log "归档了 \$archived_count 个过期日期文件"
    
    # 归档测试文件
    local test_patterns="test|Test|TEST|report|Report|summary|Summary|comprehensive"
    for file in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null); do
        filename=\$(basename "\$file")
        if [[ "\$filename" =~ \$test_patterns ]] && [[ ! "\$filename" =~ ^(projects|contacts|tasks|preferences) ]]; then
            mv "\$file" "\$ARCHIVE_DIR/$(date +%Y-%m)/" 2>/dev/null || true
            log "归档测试文件: \$filename"
        fi
    done
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
    
    local line_count=\$(wc -l < "\$L0_FILE")
    local max_lines=\${L0_MAX_LINES:-100}
    
    if [ \$line_count -gt \$max_lines ]; then
        head -20 "\$L0_FILE" > /tmp/l0_temp_$$
        echo "" >> /tmp/l0_temp_$$
        echo "## 最近记录 (自动精简)" >> /tmp/l0_temp_$$
        tail -50 "\$L0_FILE" >> /tmp/l0_temp_$$
        
        mv /tmp/l0_temp_$$ "\$L0_FILE"
        log "L0 从 \$line_count 行精简到 \$(wc -l < "\$L0_FILE") 行"
    else
        log "L0 文件行数 (\$line_count) 在合理范围内"
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
        -H "Authorization: Bearer \$API_KEY" 2>/dev/null || echo '{"removed": 0}')
    
    local removed=\$(echo "\$response" | grep -o '"deleted_count":[0-9]*' | cut -d: -f2 || echo "0")
    log "L2 去重完成，删除了 \$removed 条重复记忆"
    
    # 获取当前记忆数
    local stats=\$(curl -s "\$SERVER_URL/memory/stats?agent_id=\$AGENT_ID" \\
        -H "Authorization: Bearer \$API_KEY" 2>/dev/null || echo '{}')
    local count=\$(echo "\$stats" | grep -o '"total_memories":[0-9]*' | cut -d: -f2 || echo "0")
    log "L2 当前记忆数: \$count"
}

# ============================================
# 4. Context 优化报告
# ============================================
optimize_context() {
    log "=== Context 优化报告 ==="
    
    local l0_size=0 l1_size=0 l2_count=0
    
    [ -f "\$L0_FILE" ] && l0_size=\$(wc -c < "\$L0_FILE")
    
    for f in \$(find "\$MEMORY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null); do
        l1_size=\$((l1_size + \$(wc -c < "\$f")))
    done
    
    log "L0 大小: \$((l0_size / 1024))KB"
    log "L1 有效大小: \$((l1_size / 1024))KB"
    log "Context 总计: \$(((l0_size + l1_size) / 1024))KB"
    
    if [ \$((l0_size + l1_size)) -gt 51200 ]; then
        log "⚠️ Context 偏大，建议手动清理"
    else
        log "✅ Context 大小正常"
    fi
}

# ============================================
# 主函数
# ============================================
main() {
    log "=========================================="
    log "开始记忆自动管理"
    log "=========================================="
    
    case "\${1:-all}" in
        archive)
            archive_l1_files
            ;;
        prune)
            prune_l0_file
            ;;
        dedup)
            clean_l2_memories
            ;;
        context)
            optimize_context
            ;;
        all|*)
            archive_l1_files
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
 * Check if setup has been run before
 */
async function isSetupComplete(): Promise<boolean> {
  const scriptPath = path.join(os.homedir(), ".openclaw", "scripts", "memory_manager.sh");
  try {
    await fs.access(scriptPath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Create the memory manager script
 */
async function createScript(config: SetupConfig): Promise<string> {
  const scriptsDir = path.join(os.homedir(), ".openclaw", "scripts");
  const scriptPath = path.join(scriptsDir, "memory_manager.sh");
  
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
  try {
    const scriptPath = path.join(os.homedir(), ".openclaw", "scripts", "memory_manager.sh");
    const cronEntry = `0 3 * * * ${scriptPath} >> ~/.openclaw/logs/memory_manager.log 2>&1`;
    
    // Check if crontab already has the entry
    const { stdout: currentCrontab } = await execAsync("crontab -l 2>/dev/null || echo ''");
    
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
  const alreadySetup = await isSetupComplete();
  
  if (alreadySetup) {
    console.log("[mem0-setup] Already setup, skipping...");
    return {
      scriptPath: path.join(os.homedir(), ".openclaw", "scripts", "memory_manager.sh"),
      crontabConfigured: true,
    };
  }
  
  console.log("[mem0-setup] First-time setup: creating memory_manager.sh...");
  
  const scriptPath = await createScript(config);
  console.log(`[mem0-setup] Script created: ${scriptPath}`);
  
  const crontabConfigured = await setupCrontab();
  
  // Run first-time optimization
  console.log("[mem0-setup] Running initial memory optimization...");
  try {
    await execAsync(`bash ${scriptPath}`);
  } catch (error) {
    console.error("[mem0-setup] Initial optimization failed:", error);
  }
  
  console.log("[mem0-setup] Setup complete!");
  
  return { scriptPath, crontabConfigured };
}
