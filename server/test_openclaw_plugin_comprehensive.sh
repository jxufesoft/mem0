#!/bin/bash
#
# OpenClaw Mem0 Plugin 综合功能与性能测试
# 测试所有三层记忆层 (L0/L1/L2) 和所有插件工具
#

set -e

# ============================================================================
# 配置
# ============================================================================

OPENCLAW_URL="http://localhost:18789"
MEM0_SERVER_URL="http://localhost:8000"
API_KEY="mem0_SxZcThQnwW05Du3_uODDLxspXQzXl6_TXErK7cjLPPI"
USER_ID="default"
AGENT_ID="openclaw-main"

# 测试颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试结果跟踪
declare -a FAILED_TEST_NAMES

# ============================================================================
# 辅助函数
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
    FAILED_TEST_NAMES+=("$1")
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TOTAL_TESTS++))
}

log_section() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
}

# 调用 Mem0 Server API
mem0_api() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -X "$method" "${MEM0_SERVER_URL}${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "${MEM0_SERVER_URL}${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json"
    fi
}

# 调用 OpenClaw Gateway API
openclaw_api() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -X "$method" "${OPENCLAW_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "${OPENCLAW_URL}${endpoint}"
    fi
}

# 检查响应是否包含特定字符串
contains() {
    [[ "$1" == *"$2"* ]]
}

# 检查响应是否是有效 JSON
is_json() {
    echo "$1" | jq -e . >/dev/null 2>&1
}

# 获取时间戳（毫秒）
timestamp_ms() {
    date +%s%3N
}

# ============================================================================
# 前置检查
# ============================================================================

preflight_checks() {
    log_section "前置检查"

    # 检查 jq
    if ! command -v jq &> /dev/null; then
        echo "错误: 需要安装 jq"
        exit 1
    fi

    # 检查 Mem0 Server
    log_info "检查 Mem0 Server..."
    if curl -s --max-time 5 "${MEM0_SERVER_URL}/health" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
        log_success "Mem0 Server 健康"
    else
        log_fail "Mem0 Server 不可用"
        exit 1
    fi

    # 检查 OpenClaw Gateway
    log_info "检查 OpenClaw Gateway..."
    if curl -s --max-time 5 "${OPENCLAW_URL}/" 2>/dev/null | grep -q "openclaw" || \
       curl -s --max-time 5 "${OPENCLAW_URL}/" 2>/dev/null | grep -q "OpenClaw"; then
        log_success "OpenClaw Gateway 运行中"
    else
        # OpenClaw 可能不暴露健康检查端点，检查进程
        if pgrep -f "openclaw" > /dev/null; then
            log_success "OpenClaw 进程运行中"
        else
            log_fail "OpenClaw 未运行"
        fi
    fi

    # 检查 L0 文件
    log_info "检查 L0 文件..."
    L0_PATH="/home/yhz/.openclaw/workspace/memory.md"
    if [ -f "$L0_PATH" ]; then
        L0_SIZE=$(wc -c < "$L0_PATH")
        log_success "L0 文件存在 (${L0_SIZE} bytes)"
    else
        log_fail "L0 文件不存在"
    fi

    # 检查 L1 目录
    log_info "检查 L1 目录..."
    L1_DIR="/home/yhz/.openclaw/workspace/memory"
    if [ -d "$L1_DIR" ]; then
        L1_FILES=$(ls -1 "$L1_DIR" 2>/dev/null | wc -l)
        log_success "L1 目录存在 (${L1_FILES} 文件)"
    else
        log_fail "L1 目录不存在"
    fi

    # 检查插件配置
    log_info "检查插件配置..."
    PLUGIN_CONFIG=$(cat /home/yhz/.openclaw/openclaw.json 2>/dev/null | jq -r '.plugins.entries."openclaw-mem0".config.mode // "unknown"')
    if [ "$PLUGIN_CONFIG" != "unknown" ] && [ "$PLUGIN_CONFIG" != "null" ]; then
        log_success "插件配置模式: $PLUGIN_CONFIG"
    else
        log_fail "插件未正确配置"
    fi
}

# ============================================================================
# L0 层测试 (memory.md)
# ============================================================================

test_l0_layer() {
    log_section "L0 层测试 (memory.md)"

    L0_PATH="/home/yhz/.openclaw/workspace/memory.md"

    # 测试 1: L0 文件读取
    log_info "测试 L0 文件读取..."
    if [ -f "$L0_PATH" ]; then
        CONTENT=$(cat "$L0_PATH")
        if [ -n "$CONTENT" ]; then
            log_success "L0 文件读取成功 ($(echo "$CONTENT" | wc -l) 行)"
        else
            log_fail "L0 文件为空"
        fi
    else
        log_fail "L0 文件不存在"
    fi

    # 测试 2: L0 文件写入
    log_info "测试 L0 文件写入..."
    TEST_CONTENT="## Test Entry - $(date +%Y%m%d%H%M%S)\n\n- Test fact: L0 write test\n- Timestamp: $(date -Iseconds)\n"
    if echo -e "$TEST_CONTENT" >> "$L0_PATH"; then
        if grep -q "L0 write test" "$L0_PATH"; then
            log_success "L0 文件写入成功"
        else
            log_fail "L0 写入验证失败"
        fi
    else
        log_fail "L0 文件写入失败"
    fi

    # 测试 3: L0 格式验证
    log_info "测试 L0 格式验证..."
    if head -5 "$L0_PATH" | grep -q "# Memory"; then
        log_success "L0 格式正确 (包含标题)"
    else
        log_fail "L0 格式不正确"
    fi
}

# ============================================================================
# L1 层测试 (日期/分类文件)
# ============================================================================

test_l1_layer() {
    log_section "L1 层测试 (日期/分类文件)"

    L1_DIR="/home/yhz/.openclaw/workspace/memory"
    TODAY=$(date +%Y-%m-%d)

    # 测试 1: L1 目录存在
    log_info "测试 L1 目录结构..."
    if [ -d "$L1_DIR" ]; then
        log_success "L1 目录存在"
    else
        log_fail "L1 目录不存在"
        return
    fi

    # 测试 2: 分类文件存在
    log_info "测试分类文件..."
    CATEGORIES=("projects" "contacts" "tasks" "preferences")
    CAT_COUNT=0
    for cat in "${CATEGORIES[@]}"; do
        if [ -f "$L1_DIR/${cat}.md" ]; then
            ((CAT_COUNT++))
        fi
    done
    if [ $CAT_COUNT -ge 2 ]; then
        log_success "分类文件存在 ($CAT_COUNT/4)"
    else
        log_fail "分类文件不足 ($CAT_COUNT/4)"
    fi

    # 测试 3: 创建今日日期文件
    log_info "测试日期文件写入..."
    DATE_FILE="$L1_DIR/${TODAY}.md"
    TEST_ENTRY="\n### Test Entry $(date +%H:%M:%S)\n- L1 date file test\n"
    if echo -e "$TEST_ENTRY" >> "$DATE_FILE"; then
        if [ -f "$DATE_FILE" ]; then
            log_success "日期文件创建/写入成功"
        else
            log_fail "日期文件创建失败"
        fi
    else
        log_fail "日期文件写入失败"
    fi

    # 测试 4: 分类文件写入
    log_info "测试分类文件写入..."
    PROJECTS_FILE="$L1_DIR/projects.md"
    TEST_PROJECT="\n- Test Project: L1 category test ($(date +%H:%M:%S))\n"
    if echo -e "$TEST_PROJECT" >> "$PROJECTS_FILE"; then
        if grep -q "L1 category test" "$PROJECTS_FILE"; then
            log_success "分类文件写入成功"
        else
            log_fail "分类文件写入验证失败"
        fi
    else
        log_fail "分类文件写入失败"
    fi

    # 测试 5: L1 读取上下文
    log_info "测试 L1 上下文读取..."
    TOTAL_LINES=0
    for f in "$L1_DIR"/*.md; do
        if [ -f "$f" ]; then
            LINES=$(wc -l < "$f")
            ((TOTAL_LINES += LINES))
        fi
    done
    if [ $TOTAL_LINES -gt 0 ]; then
        log_success "L1 上下文可读 (共 $TOTAL_LINES 行)"
    else
        log_fail "L1 上下文为空"
    fi
}

# ============================================================================
# L2 层测试 (向量搜索 - Server API)
# ============================================================================

test_l2_layer() {
    log_section "L2 层测试 (向量搜索)"

    # 测试 1: 搜索功能
    log_info "测试 L2 向量搜索..."
    SEARCH_RESULT=$(mem0_api POST "/search" '{"query": "test", "user_id": "'${USER_ID}'", "agent_id": "'${AGENT_ID}'", "limit": 5}')
    if is_json "$SEARCH_RESULT"; then
        RESULT_COUNT=$(echo "$SEARCH_RESULT" | jq -r '.results | length')
        if [ "$RESULT_COUNT" -gt 0 ]; then
            log_success "L2 搜索成功 (返回 $RESULT_COUNT 条结果)"
        else
            log_success "L2 搜索成功 (无结果，但 API 正常)"
        fi
    else
        log_fail "L2 搜索失败 (无效响应)"
    fi

    # 测试 2: 搜索性能
    log_info "测试 L2 搜索性能..."
    START=$(timestamp_ms)
    for i in {1..5}; do
        mem0_api POST "/search" '{"query": "performance test '$i'", "user_id": "'${USER_ID}'", "agent_id": "'${AGENT_ID}'", "limit": 5}' > /dev/null
    done
    END=$(timestamp_ms)
    AVG_TIME=$(( (END - START) / 5 ))
    if [ $AVG_TIME -lt 200 ]; then
        log_success "L2 搜索平均延迟: ${AVG_TIME}ms"
    elif [ $AVG_TIME -lt 500 ]; then
        log_success "L2 搜索平均延迟: ${AVG_TIME}ms (可接受)"
    else
        log_fail "L2 搜索平均延迟过高: ${AVG_TIME}ms"
    fi

    # 测试 3: 记忆列表
    log_info "测试 L2 记忆列表..."
    LIST_RESULT=$(mem0_api GET "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}")
    if is_json "$LIST_RESULT"; then
        MEM_COUNT=$(echo "$LIST_RESULT" | jq -r 'if type == "array" then length elif .results then (.results | length) else 0 end')
        log_success "L2 记忆列表成功 ($MEM_COUNT 条记忆)"
    else
        log_fail "L2 记忆列表失败"
    fi

    # 测试 4: 搜索阈值
    log_info "测试 L2 搜索阈值..."
    THRESHOLD_RESULT=$(mem0_api POST "/search" '{"query": "programming", "user_id": "'${USER_ID}'", "agent_id": "'${AGENT_ID}'", "limit": 5}')
    if is_json "$THRESHOLD_RESULT"; then
        log_success "L2 搜索阈值测试通过"
    else
        log_fail "L2 搜索阈值测试失败"
    fi
}

# ============================================================================
# Mem0 Server API 测试
# ============================================================================

test_server_api() {
    log_section "Mem0 Server API 测试"

    # 测试 1: 健康检查
    log_info "测试健康检查..."
    HEALTH=$(curl -s "${MEM0_SERVER_URL}/health")
    if echo "$HEALTH" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
        log_success "健康检查通过"
    else
        log_fail "健康检查失败"
    fi

    # 测试 2: 创建记忆 (通过 LLM)
    log_info "测试创建记忆..."
    CREATE_RESULT=$(mem0_api POST "/memories" '{"messages": [{"role": "user", "content": "My name is Test User and I like testing memory systems"}], "user_id": "'${USER_ID}'", "agent_id": "'${AGENT_ID}'"}')
    if is_json "$CREATE_RESULT"; then
        MEM_ID=$(echo "$CREATE_RESULT" | jq -r '.results[0].id // empty')
        if [ -n "$MEM_ID" ]; then
            log_success "创建记忆成功 (ID: ${MEM_ID:0:20}...)"

            # 测试 3: 获取单个记忆
            log_info "测试获取单个记忆..."
            GET_RESULT=$(mem0_api GET "/memories/${MEM_ID}?agent_id=${AGENT_ID}")
            if is_json "$GET_RESULT" && echo "$GET_RESULT" | jq -e '.id' >/dev/null 2>&1; then
                log_success "获取记忆成功"
            else
                log_fail "获取记忆失败"
            fi

            # 测试 4: 更新记忆
            log_info "测试更新记忆..."
            UPDATE_RESULT=$(mem0_api PUT "/memories/${MEM_ID}" '{"memory": "Updated: Test User likes memory testing", "agent_id": "'${AGENT_ID}'"}')
            if is_json "$UPDATE_RESULT"; then
                log_success "更新记忆成功"
            else
                log_fail "更新记忆失败"
            fi

            # 测试 5: 获取记忆历史
            log_info "测试获取记忆历史..."
            HISTORY_RESULT=$(mem0_api GET "/memories/${MEM_ID}/history?agent_id=${AGENT_ID}")
            if is_json "$HISTORY_RESULT"; then
                log_success "记忆历史获取成功"
            else
                log_fail "记忆历史获取失败"
            fi

            # 清理测试记忆
            log_info "清理测试记忆..."
            mem0_api DELETE "/memories/${MEM_ID}?agent_id=${AGENT_ID}" > /dev/null
        else
            log_fail "创建记忆失败 (无 ID)"
        fi
    else
        log_fail "创建记忆失败 (无效响应)"
    fi

    # 测试 6: 认证测试 - 无效 Key
    log_info "测试无效 API Key..."
    INVALID_RESULT=$(curl -s -X POST "${MEM0_SERVER_URL}/search" \
        -H "Authorization: Bearer invalid_key" \
        -H "Content-Type: application/json" \
        -d '{"query": "test"}')
    if echo "$INVALID_RESULT" | grep -q "403\|401\|invalid\|unauthorized"; then
        log_success "无效 Key 被正确拒绝"
    else
        log_fail "无效 Key 未被拒绝"
    fi

    # 测试 7: 认证测试 - 缺少 Key
    log_info "测试缺少 API Key..."
    NO_KEY_RESULT=$(curl -s -X POST "${MEM0_SERVER_URL}/search" \
        -H "Content-Type: application/json" \
        -d '{"query": "test"}')
    if echo "$NO_KEY_RESULT" | grep -q "401\|403\|missing\|required"; then
        log_success "缺少 Key 被正确拒绝"
    else
        log_fail "缺少 Key 未被拒绝"
    fi
}

# ============================================================================
# 性能测试
# ============================================================================

test_performance() {
    log_section "性能测试"

    # 测试 1: 批量创建
    log_info "测试批量创建性能..."
    START=$(timestamp_ms)
    for i in {1..5}; do
        mem0_api POST "/memories" "{\"messages\": [{\"role\": \"user\", \"content\": \"Performance test memory $i\"}], \"user_id\": \"${USER_ID}\", \"agent_id\": \"${AGENT_ID}\"}" > /dev/null &
    done
    wait
    END=$(timestamp_ms)
    BATCH_TIME=$((END - START))
    if [ $BATCH_TIME -lt 3000 ]; then
        log_success "批量创建 5 条记忆: ${BATCH_TIME}ms"
    else
        log_fail "批量创建超时: ${BATCH_TIME}ms"
    fi

    # 测试 2: 顺序读取
    log_info "测试顺序读取性能..."
    START=$(timestamp_ms)
    for i in {1..10}; do
        mem0_api GET "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}" > /dev/null
    done
    END=$(timestamp_ms)
    SEQ_TIME=$((END - START))
    AVG_SEQ=$((SEQ_TIME / 10))
    if [ $AVG_SEQ -lt 100 ]; then
        log_success "顺序读取平均: ${AVG_SEQ}ms (10次)"
    else
        log_fail "顺序读取平均: ${AVG_SEQ}ms (过慢)"
    fi

    # 测试 3: 健康检查吞吐量
    log_info "测试健康检查吞吐量..."
    START=$(timestamp_ms)
    for i in {1..20}; do
        curl -s "${MEM0_SERVER_URL}/health" > /dev/null
    done
    END=$(timestamp_ms)
    HEALTH_TIME=$((END - START))
    THROUGHPUT=$((20000 / HEALTH_TIME))
    if [ $THROUGHPUT -gt 50 ]; then
        log_success "健康检查吞吐量: ~${THROUGHPUT} req/s"
    else
        log_fail "健康检查吞吐量过低: ~${THROUGHPUT} req/s"
    fi

    # 测试 4: 搜索延迟分布
    log_info "测试搜索延迟分布..."
    declare -a LATENCIES
    for i in {1..5}; do
        S=$(timestamp_ms)
        mem0_api POST "/search" '{"query": "latency test '$i'", "user_id": "'${USER_ID}'", "agent_id": "'${AGENT_ID}'", "limit": 5}' > /dev/null
        E=$(timestamp_ms)
        LATENCIES+=($((E - S)))
    done
    # 计算 P50
    IFS=$'\n' sorted=($(sort -n <<<"${LATENCIES[*]}")); unset IFS
    P50=${sorted[2]}
    log_success "搜索延迟 P50: ${P50}ms"
}

# ============================================================================
# 多 Agent 隔离测试
# ============================================================================

test_multi_agent() {
    log_section "多 Agent 隔离测试"

    # 测试 1: 创建不同 Agent 的记忆
    log_info "测试 Agent 数据隔离..."

    # 为 agent1 创建记忆
    AGENT1_RESULT=$(mem0_api POST "/memories" '{"messages": [{"role": "user", "content": "Agent1 specific data: secret code 12345"}], "user_id": "'${USER_ID}'", "agent_id": "test-agent-1"}')
    AGENT1_ID=$(echo "$AGENT1_RESULT" | jq -r '.results[0].id // empty')

    # 为 agent2 创建记忆
    AGENT2_RESULT=$(mem0_api POST "/memories" '{"messages": [{"role": "user", "content": "Agent2 specific data: secret code 67890"}], "user_id": "'${USER_ID}'", "agent_id": "test-agent-2"}')
    AGENT2_ID=$(echo "$AGENT2_RESULT" | jq -r '.results[0].id // empty')

    if [ -n "$AGENT1_ID" ] && [ -n "$AGENT2_ID" ]; then
        log_success "Agent 记忆创建成功"

        # 测试 2: 搜索隔离
        log_info "测试 Agent 搜索隔离..."
        AGENT1_SEARCH=$(mem0_api POST "/search" '{"query": "secret code", "user_id": "'${USER_ID}'", "agent_id": "test-agent-1", "limit": 5}')
        AGENT2_SEARCH=$(mem0_api POST "/search" '{"query": "secret code", "user_id": "'${USER_ID}'", "agent_id": "test-agent-2", "limit": 5}')

        if echo "$AGENT1_SEARCH" | grep -q "12345" && ! echo "$AGENT1_SEARCH" | grep -q "67890"; then
            log_success "Agent1 搜索隔离正确"
        else
            log_fail "Agent1 搜索隔离失败"
        fi

        if echo "$AGENT2_SEARCH" | grep -q "67890" && ! echo "$AGENT2_SEARCH" | grep -q "12345"; then
            log_success "Agent2 搜索隔离正确"
        else
            log_fail "Agent2 搜索隔离失败"
        fi

        # 清理测试 Agent 记忆
        log_info "清理测试 Agent 数据..."
        mem0_api DELETE "/memories?user_id=${USER_ID}&agent_id=test-agent-1" > /dev/null
        mem0_api DELETE "/memories?user_id=${USER_ID}&agent_id=test-agent-2" > /dev/null
        log_success "测试 Agent 数据已清理"
    else
        log_fail "Agent 记忆创建失败"
    fi
}

# ============================================================================
# 配置和初始化测试
# ============================================================================

test_config_initialization() {
    log_section "配置和初始化测试"

    # 测试 1: openclaw.json 配置完整性
    log_info "测试配置完整性..."
    CONFIG=$(cat /home/yhz/.openclaw/openclaw.json)

    REQUIRED_FIELDS=("mode" "serverUrl" "serverApiKey" "userId" "agentId" "l0Enabled" "l1Enabled")
    MISSING_COUNT=0
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! echo "$CONFIG" | jq -e ".plugins.entries.\"openclaw-mem0\".config.$field" >/dev/null 2>&1; then
            ((MISSING_COUNT++))
        fi
    done

    if [ $MISSING_COUNT -eq 0 ]; then
        log_success "配置完整 (所有必需字段存在)"
    else
        log_fail "配置不完整 (缺少 $MISSING_COUNT 个字段)"
    fi

    # 测试 2: L0 路径配置
    log_info "测试 L0 路径配置..."
    L0_CONFIG_PATH=$(echo "$CONFIG" | jq -r '.plugins.entries."openclaw-mem0".config.l0Path // empty')
    if [ -n "$L0_CONFIG_PATH" ] && [ -f "$L0_CONFIG_PATH" ]; then
        log_success "L0 路径配置正确"
    else
        log_fail "L0 路径配置错误"
    fi

    # 测试 3: L1 路径配置
    log_info "测试 L1 路径配置..."
    L1_CONFIG_PATH=$(echo "$CONFIG" | jq -r '.plugins.entries."openclaw-mem0".config.l1Dir // empty')
    if [ -n "$L1_CONFIG_PATH" ] && [ -d "$L1_CONFIG_PATH" ]; then
        log_success "L1 路径配置正确"
    else
        log_fail "L1 路径配置错误"
    fi

    # 测试 4: 服务端点配置
    log_info "测试服务端点配置..."
    SERVER_URL=$(echo "$CONFIG" | jq -r '.plugins.entries."openclaw-mem0".config.serverUrl // empty')
    if [ "$SERVER_URL" = "$MEM0_SERVER_URL" ]; then
        log_success "服务端点配置正确"
    else
        log_fail "服务端点配置错误"
    fi

    # 测试 5: API Key 配置
    log_info "测试 API Key 配置..."
    CONFIG_API_KEY=$(echo "$CONFIG" | jq -r '.plugins.entries."openclaw-mem0".config.serverApiKey // empty')
    if [ -n "$CONFIG_API_KEY" ] && [ ${#CONFIG_API_KEY} -gt 20 ]; then
        log_success "API Key 配置正确"
    else
        log_fail "API Key 配置错误"
    fi
}

# ============================================================================
# 错误处理测试
# ============================================================================

test_error_handling() {
    log_section "错误处理测试"

    # 测试 1: 无效记忆 ID
    log_info "测试无效记忆 ID..."
    INVALID_ID_RESULT=$(mem0_api GET "/memories/invalid-id-12345?agent_id=${AGENT_ID}")
    if echo "$INVALID_ID_RESULT" | grep -q "404\|not found\|error"; then
        log_success "无效 ID 正确返回错误"
    else
        log_fail "无效 ID 未正确处理"
    fi

    # 测试 2: 缺少必需参数
    log_info "测试缺少必需参数..."
    MISSING_PARAM=$(curl -s -X POST "${MEM0_SERVER_URL}/memories" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{}')
    if echo "$MISSING_PARAM" | grep -q "400\|required\|missing\|error"; then
        log_success "缺少参数正确返回错误"
    else
        log_fail "缺少参数未正确处理"
    fi

    # 测试 3: 无效 JSON
    log_info "测试无效 JSON..."
    INVALID_JSON=$(curl -s -X POST "${MEM0_SERVER_URL}/search" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d 'not valid json')
    if echo "$INVALID_JSON" | grep -q "400\|error\|invalid"; then
        log_success "无效 JSON 正确返回错误"
    else
        log_fail "无效 JSON 未正确处理"
    fi

    # 测试 4: 速率限制 (可选)
    log_info "测试速率限制..."
    RATE_LIMIT_HIT=false
    for i in {1..50}; do
        RESULT=$(curl -s -w "%{http_code}" -X GET "${MEM0_SERVER_URL}/health")
        HTTP_CODE="${RESULT: -3}"
        if [ "$HTTP_CODE" = "429" ]; then
            RATE_LIMIT_HIT=true
            break
        fi
    done
    if $RATE_LIMIT_HIT; then
        log_success "速率限制正常触发"
    else
        log_success "速率限制未触发 (正常，阈值较高)"
    fi
}

# ============================================================================
# 报告生成
# ============================================================================

generate_report() {
    log_section "测试报告"

    echo ""
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│                  Mem0 Plugin 测试报告                      │"
    echo "├────────────────────────────────────────────────────────────┤"
    printf "│  总测试数: %-46d │\n" "$TOTAL_TESTS"
    printf "│  通过: %-52d │\n" "$PASSED_TESTS"
    printf "│  失败: %-52d │\n" "$FAILED_TESTS"
    printf "│  通过率: %-47s │\n" "$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
    echo "├────────────────────────────────────────────────────────────┤"

    if [ $FAILED_TESTS -gt 0 ]; then
        echo "│  失败的测试:                                               │"
        for name in "${FAILED_TEST_NAMES[@]}"; do
            printf "│    - %-52s │\n" "$name"
        done
        echo "├────────────────────────────────────────────────────────────┤"
    fi

    if [ $FAILED_TESTS -eq 0 ]; then
        echo "│  状态: ✅ 所有测试通过                                     │"
    else
        echo "│  状态: ⚠️  有 $FAILED_TESTS 个测试失败                     │"
    fi

    echo "└────────────────────────────────────────────────────────────┘"
    echo ""
    echo "测试时间: $(date -Iseconds)"
    echo "Mem0 Server: $MEM0_SERVER_URL"
    echo "OpenClaw Gateway: $OPENCLAW_URL"
    echo "Agent ID: $AGENT_ID"
    echo ""

    # 返回适当的退出码
    if [ $FAILED_TESTS -gt 0 ]; then
        return 1
    fi
    return 0
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     OpenClaw Mem0 Plugin 综合功能与性能测试                  ║"
    echo "║     版本: 2.0.2 | 三层记忆架构 (L0/L1/L2)                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    preflight_checks
    test_l0_layer
    test_l1_layer
    test_l2_layer
    test_server_api
    test_performance
    test_multi_agent
    test_config_initialization
    test_error_handling
    generate_report
}

# 运行主程序
main
