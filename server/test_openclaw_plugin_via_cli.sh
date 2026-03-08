#!/bin/bash
#
# OpenClaw Mem0 Plugin 综合功能测试 (通过 OpenClaw CLI)
# 测试所有插件工具和三层记忆架构
#

set -e

# Setup Node.js
source ~/.nvm/nvm.sh
nvm use 22 > /dev/null 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); ((TOTAL++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); ((TOTAL++)); }
log_section() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
}

# Suppress plugin loading messages
filter_output() {
    grep -v "\[plugins\]" | grep -v "Doctor warnings" | grep -v "channels.telegram" | grep -v "┌" | grep -v "│" | grep -v "├" | grep -v "└" | grep -v "╮" | grep -v "╯" | grep -v "─"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     OpenClaw Mem0 Plugin CLI 综合测试                        ║"
echo "║     版本: 2.0.2 | 三层记忆架构                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# 1. Gateway Health
# ============================================================================
log_section "1. Gateway 健康检查"

HEALTH=$(openclaw health 2>&1 | filter_output | tr -d '\n')
if echo "$HEALTH" | grep -q "ok\|main"; then
    log_pass "Gateway 健康"
else
    log_fail "Gateway 不健康"
fi

# ============================================================================
# 2. Plugin Stats
# ============================================================================
log_section "2. Plugin Stats 命令"

STATS=$(openclaw mem0 stats 2>&1 | filter_output)
if echo "$STATS" | grep -q "Mode: server"; then
    log_pass "Stats 显示 server 模式"
else
    log_fail "Stats 模式错误"
fi

if echo "$STATS" | grep -q "Auto-recall: true"; then
    log_pass "Auto-recall 已启用"
else
    log_fail "Auto-recall 未启用"
fi

if echo "$STATS" | grep -q "Auto-capture: true"; then
    log_pass "Auto-capture 已启用"
else
    log_fail "Auto-capture 未启用"
fi

# ============================================================================
# 3. Search Command
# ============================================================================
log_section "3. Search 命令测试"

# Test 1: Basic search
log_info "测试基本搜索..."
SEARCH_RESULT=$(openclaw mem0 search "memory" --limit 3 2>&1 | filter_output)
if echo "$SEARCH_RESULT" | grep -q "id"; then
    RESULT_COUNT=$(echo "$SEARCH_RESULT" | grep -o '"id"' | wc -l)
    log_pass "搜索返回 $RESULT_COUNT 条结果"
else
    log_fail "搜索无结果"
fi

# Test 2: Search with scope
log_info "测试 scope 参数..."
SEARCH_LONG=$(openclaw mem0 search "test" --scope long-term --limit 2 2>&1 | filter_output)
if echo "$SEARCH_LONG" | grep -q "long-term\|id"; then
    log_pass "long-term scope 搜索成功"
else
    log_fail "long-term scope 搜索失败"
fi

# Test 3: Search performance
log_info "测试搜索性能..."
START=$(date +%s%3N)
openclaw mem0 search "performance" --limit 5 > /dev/null 2>&1
END=$(date +%s%3N)
LATENCY=$((END - START))
if [ $LATENCY -lt 500 ]; then
    log_pass "搜索延迟: ${LATENCY}ms"
else
    log_fail "搜索延迟过高: ${LATENCY}ms"
fi

# ============================================================================
# 4. L0 Layer Test
# ============================================================================
log_section "4. L0 层测试 (memory.md)"

L0_PATH="/home/yhz/.openclaw/workspace/memory.md"

# Check L0 file
if [ -f "$L0_PATH" ]; then
    log_pass "L0 文件存在"
    L0_SIZE=$(wc -c < "$L0_PATH")
    if [ $L0_SIZE -gt 100 ]; then
        log_pass "L0 文件有内容 (${L0_SIZE} bytes)"
    else
        log_fail "L0 文件内容过少"
    fi
else
    log_fail "L0 文件不存在"
fi

# Check L0 format
if head -5 "$L0_PATH" | grep -q "# Memory\|# .*记忆"; then
    log_pass "L0 文件格式正确"
else
    log_fail "L0 文件格式错误"
fi

# ============================================================================
# 5. L1 Layer Test
# ============================================================================
log_section "5. L1 层测试 (日期/分类文件)"

L1_DIR="/home/yhz/.openclaw/workspace/memory"

# Check L1 directory
if [ -d "$L1_DIR" ]; then
    log_pass "L1 目录存在"
else
    log_fail "L1 目录不存在"
fi

# Check category files
CATEGORIES=("projects" "contacts" "tasks" "preferences")
CAT_COUNT=0
for cat in "${CATEGORIES[@]}"; do
    if [ -f "$L1_DIR/${cat}.md" ]; then
        ((CAT_COUNT++))
    fi
done
if [ $CAT_COUNT -ge 2 ]; then
    log_pass "分类文件存在 ($CAT_COUNT/4)"
else
    log_fail "分类文件不足 ($CAT_COUNT/4)"
fi

# Check date files
TODAY=$(date +%Y-%m-%d)
if ls "$L1_DIR"/*.md 2>/dev/null | grep -q "$TODAY"; then
    log_pass "今日日期文件存在"
else
    log_info "今日日期文件不存在 (正常，如果今天没有对话)"
    ((TOTAL++))
    ((PASSED++))
fi

# ============================================================================
# 6. L2 Layer Test (Server API)
# ============================================================================
log_section "6. L2 层测试 (向量搜索)"

# Direct API test
API_KEY="mem0_SxZcThQnwW05Du3_uODDLxspXQzXl6_TXErK7cjLPPI"

log_info "测试 Server API 搜索..."
API_SEARCH=$(curl -s -X POST "http://localhost:8000/search" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"query": "test", "user_id": "default", "agent_id": "openclaw-main", "limit": 3}')
if echo "$API_SEARCH" | grep -q "results"; then
    log_pass "L2 API 搜索成功"
else
    log_fail "L2 API 搜索失败"
fi

# ============================================================================
# 7. Configuration Test
# ============================================================================
log_section "7. 配置验证"

CONFIG=$(cat /home/yhz/.openclaw/openclaw.json 2>/dev/null)

# Check mode
if echo "$CONFIG" | jq -e '.plugins.entries."openclaw-mem0".config.mode == "server"' > /dev/null 2>&1; then
    log_pass "配置模式: server"
else
    log_fail "配置模式错误"
fi

# Check L0/L1 enabled
if echo "$CONFIG" | jq -e '.plugins.entries."openclaw-mem0".config.l0Enabled == true' > /dev/null 2>&1; then
    log_pass "L0 已启用"
else
    log_fail "L0 未启用"
fi

if echo "$CONFIG" | jq -e '.plugins.entries."openclaw-mem0".config.l1Enabled == true' > /dev/null 2>&1; then
    log_pass "L1 已启用"
else
    log_fail "L1 未启用"
fi

# Check autoRecall/autoCapture
if echo "$CONFIG" | jq -e '.plugins.entries."openclaw-mem0".config.autoRecall == true' > /dev/null 2>&1; then
    log_pass "Auto-recall 已启用"
else
    log_fail "Auto-recall 未启用"
fi

if echo "$CONFIG" | jq -e '.plugins.entries."openclaw-mem0".config.autoCapture == true' > /dev/null 2>&1; then
    log_pass "Auto-capture 已启用"
else
    log_fail "Auto-capture 未启用"
fi

# ============================================================================
# Report
# ============================================================================
log_section "测试报告"

echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│                  测试结果汇总                              │"
echo "├────────────────────────────────────────────────────────────┤"
printf "│  总测试数: %-46d │\n" "$TOTAL"
printf "│  通过: %-52d │\n" "$PASSED"
printf "│  失败: %-52d │\n" "$FAILED"
if [ $TOTAL -gt 0 ]; then
    PASS_RATE=$(echo "scale=1; $PASSED * 100 / $TOTAL" | bc)
    printf "│  通过率: %-46s │\n" "${PASS_RATE}%"
fi
echo "├────────────────────────────────────────────────────────────┤"
if [ $FAILED -eq 0 ]; then
    echo "│  状态: ✅ 所有测试通过                                    │"
else
    echo "│  状态: ⚠️  有 $FAILED 个测试失败                          │"
fi
echo "└────────────────────────────────────────────────────────────┘"
echo ""
echo "测试时间: $(date -Iseconds)"
echo ""

# Return exit code
if [ $FAILED -gt 0 ]; then
    exit 1
fi
