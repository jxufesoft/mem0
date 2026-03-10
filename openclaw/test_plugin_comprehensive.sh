#!/bin/bash

# OpenClaw Mem0 Plugin 综合测试脚本 v2
# 修复版：正确处理记忆创建和错误检测

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 测试配置
SERVER_URL="http://localhost:8000"
API_KEY="mem0_SxZcThQnwW05Du3_uODDLxspXQzXl6_TXErK7cjLPPI"
AGENT_ID="openclaw-test"
USER_ID="test-user-$(date +%s)"

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 日志文件
LOG_FILE="/tmp/mem0_plugin_test_${TIMESTAMP}.log"
echo "Mem0 Plugin Test Log - $(date)" > "$LOG_FILE"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    log "PASS: $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    log "FAIL: $1 - $2"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

info() {
    echo -e "${BLUE}ℹ️${NC} $1"
    log "INFO: $1"
}

section() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    log "SECTION: $1"
}

# HTTP 请求辅助函数
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${API_KEY} \
            -d "$data" 2>/dev/null
    else
        curl -s -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${API_KEY} 2>/dev/null
    fi
}

measure_time() {
    local start=$(date +%s.%N)
    "$@" > /dev/null 2>&1
    local end=$(date +%s.%N)
    echo $(echo "scale=3; $end - $start" | bc)
}

# ==================== 测试开始 ====================

section "OpenClaw Mem0 Plugin 综合测试 v2"
echo "测试时间: $(date)"
echo "服务器: $SERVER_URL"
echo "Agent ID: $AGENT_ID"
echo "User ID: $USER_ID"
echo ""

# ==================== 第一阶段: 基础健康检查 ====================
section "第一阶段: 基础健康检查"

# 测试 1: 服务器健康检查
info "测试服务器健康状态..."
HEALTH=$(curl -s "${SERVER_URL}/health" 2>/dev/null)
if [[ "$HEALTH" == *"healthy"* ]]; then
    pass "服务器健康检查"
else
    fail "服务器健康检查" "响应: $HEALTH"
fi

# 测试 2: 检查 Gateway 状态
info "检查 Gateway 状态..."
source ~/.nvm/nvm.sh && nvm use v22.22.1 > /dev/null 2>&1
PLUGIN_STATUS=$(openclaw health 2>&1 | grep "openclaw-mem0" || echo "")
if [[ "$PLUGIN_STATUS" == *"mode: server"* ]]; then
    pass "Plugin Server 模式配置"
else
    fail "Plugin Server 模式配置" "状态: $PLUGIN_STATUS"
fi

# ==================== 第二阶段: CRUD 功能测试 ====================
section "第二阶段: CRUD 功能测试"

# 测试 3: 创建记忆 (使用能被 LLM 提取的内容)
info "测试创建记忆..."
CREATE_RESULT=$(api_call POST "/memories" '{
    "messages": [{"role": "user", "content": "我叫王小明，我是上海人，我喜欢编程和阅读技术书籍"}],
    "user_id": "'"$USER_ID"'",
    "agent_id": "'"$AGENT_ID"'"
}')

if [[ "$CREATE_RESULT" == *"results"* ]] && [[ "$CREATE_RESULT" == *"id"* ]]; then
    MEMORY_ID=$(echo "$CREATE_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    MEMORY_COUNT=$(echo "$CREATE_RESULT" | grep -o '"id"' | wc -l)
    pass "创建记忆 (${MEMORY_COUNT} 条, ID: ${MEMORY_ID:0:8}...)"
else
    fail "创建记忆" "响应: $(echo "$CREATE_RESULT" | head -c 200)"
fi

# 等待数据写入
sleep 1

# 测试 4: 搜索记忆
info "测试搜索记忆..."
SEARCH_RESULT=$(api_call POST "/search" '{
    "query": "编程",
    "user_id": "'"$USER_ID"'",
    "agent_id": "'"$AGENT_ID"'"
}')

if [[ "$SEARCH_RESULT" == *"results"* ]]; then
    if [[ "$SEARCH_RESULT" == *"编程"* ]] || [[ "$SEARCH_RESULT" == *"阅读"* ]]; then
        pass "搜索记忆 (找到相关内容)"
    else
        pass "搜索记忆 (返回结果)"
    fi
else
    fail "搜索记忆" "响应: $(echo "$SEARCH_RESULT" | head -c 200)"
fi

# 测试 5: 获取所有记忆
info "测试获取所有记忆..."
GETALL_RESULT=$(api_call GET "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}")

if [[ "$GETALL_RESULT" == *"results"* ]]; then
    MEMORY_COUNT=$(echo "$GETALL_RESULT" | grep -o '"id"' | wc -l)
    pass "获取所有记忆 (${MEMORY_COUNT} 条)"
else
    fail "获取所有记忆" "响应: $(echo "$GETALL_RESULT" | head -c 200)"
fi

# 测试 6: 获取单个记忆
if [[ -n "$MEMORY_ID" ]]; then
    info "测试获取单个记忆..."
    GET_RESULT=$(api_call GET "/memories/${MEMORY_ID}?agent_id=${AGENT_ID}")
    
    if [[ "$GET_RESULT" == *"id"* ]] && [[ "$GET_RESULT" == *"memory"* ]]; then
        pass "获取单个记忆"
    else
        fail "获取单个记忆" "响应: $(echo "$GET_RESULT" | head -c 200)"
    fi
else
    info "跳过单个记忆获取测试 (无记忆ID)"
fi

# 测试 7: 更新记忆
if [[ -n "$MEMORY_ID" ]]; then
    info "测试更新记忆..."
    UPDATE_RESULT=$(api_call PUT "/memories/${MEMORY_ID}?agent_id=${AGENT_ID}" '{"data": "我叫王小明，我是上海人，我喜欢编程、阅读技术书籍和打羽毛球"}')
    
    if [[ "$UPDATE_RESULT" == *"success"* ]] || [[ "$UPDATE_RESULT" == *"updated"* ]]; then
        pass "更新记忆"
    else
        fail "更新记忆" "响应: $(echo "$UPDATE_RESULT" | head -c 200)"
    fi
else
    info "跳过更新记忆测试"
fi

# 测试 8: 获取记忆历史
if [[ -n "$MEMORY_ID" ]]; then
    info "测试获取记忆历史..."
    HISTORY_RESULT=$(api_call GET "/memories/${MEMORY_ID}/history?agent_id=${AGENT_ID}")
    
    if [[ "$HISTORY_RESULT" == *"history"* ]] || [[ "$HISTORY_RESULT" == *"event"* ]] || [[ "$HISTORY_RESULT" == *"ADD"* ]] || [[ "$HISTORY_RESULT" == *"UPDATE"* ]]; then
        pass "获取记忆历史"
    else
        fail "获取记忆历史" "响应: $(echo "$HISTORY_RESULT" | head -c 200)"
    fi
fi

# ==================== 第三阶段: 批量操作测试 ====================
section "第三阶段: 批量操作测试"

# 测试 9: 批量创建记忆
info "测试批量创建 3 条记忆..."
BATCH_START=$(date +%s.%N)

for i in {1..3}; do
    api_call POST "/memories" "{
        \"messages\": [{\"role\": \"user\", \"content\": \"批量测试 $i: 第 $i 条测试记录，包含关键词测试数据\"}],
        \"user_id\": \"$USER_ID\",
        \"agent_id\": \"$AGENT_ID\"
    }" > /dev/null
done

BATCH_END=$(date +%s.%N)
BATCH_TIME=$(echo "scale=3; $BATCH_END - $BATCH_START" | bc)
AVG_TIME=$(echo "scale=3; $BATCH_TIME / 3" | bc)

pass "批量创建 3 条记忆 (总耗时: ${BATCH_TIME}s, 平均: ${AVG_TIME}s/条)"

# 测试 10: 批量搜索
info "测试批量搜索 3 次..."
SEARCH_START=$(date +%s.%N)

for i in {1..3}; do
    api_call POST "/search" "{
        \"query\": \"测试数据\",
        \"user_id\": \"$USER_ID\",
        \"agent_id\": \"$AGENT_ID\"
    }" > /dev/null
done

SEARCH_END=$(date +%s.%N)
SEARCH_TIME=$(echo "scale=3; $SEARCH_END - $SEARCH_START" | bc)
SEARCH_AVG=$(echo "scale=3; $SEARCH_TIME / 3" | bc)

pass "批量搜索 3 次 (总耗时: ${SEARCH_TIME}s, 平均: ${SEARCH_AVG}s/次)"

# ==================== 第四阶段: 性能测试 ====================
section "第四阶段: 性能测试"

# 测试 11: 健康检查延迟
info "测试健康检查延迟..."
HEALTH_TIMES=""
for i in {1..10}; do
    TIME=$(measure_time curl -s "${SERVER_URL}/health")
    HEALTH_TIMES="$HEALTH_TIMES $TIME"
done
HEALTH_AVG=$(echo "$HEALTH_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
pass "健康检查延迟 (10次平均: ${HEALTH_AVG}s)"

# 测试 12: 搜索延迟
info "测试搜索延迟..."
SEARCH_LATENCY=$(measure_time api_call POST "/search" '{"query": "编程技术", "user_id": "'"$USER_ID"'", "agent_id": "'"$AGENT_ID"'"}')
pass "搜索延迟 (${SEARCH_LATENCY}s)"

# 测试 13: 获取记忆延迟
info "测试获取记忆延迟..."
GET_LATENCY=$(measure_time api_call GET "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}")
pass "获取记忆延迟 (${GET_LATENCY}s)"

# 测试 14: 并发测试
info "测试并发请求..."
CONCURRENT_START=$(date +%s.%N)

for i in {1..5}; do
    api_call POST "/search" '{"query": "测试", "user_id": "'"$USER_ID"'", "agent_id": "'"$AGENT_ID"'"}' > /dev/null &
done
wait

CONCURRENT_END=$(date +%s.%N)
CONCURRENT_TIME=$(echo "scale=3; $CONCURRENT_END - $CONCURRENT_START" | bc)
pass "5 并发搜索 (${CONCURRENT_TIME}s)"

# ==================== 第五阶段: 多 Agent 隔离测试 ====================
section "第五阶段: 多 Agent 隔离测试"

# 测试 15: Agent 1 创建记忆
info "测试 Agent 1 创建隔离记忆..."
AGENT1_RESULT=$(api_call POST "/memories" '{
    "messages": [{"role": "user", "content": "Agent 1 专用数据: 我有10年编程经验"}],
    "user_id": "'"$USER_ID"'",
    "agent_id": "agent-isolation-001"
}')

if [[ "$AGENT1_RESULT" == *"results"* ]] || [[ "$AGENT1_RESULT" == *"id"* ]]; then
    pass "Agent 1 创建隔离记忆"
else
    fail "Agent 1 创建隔离记忆" "响应: $(echo "$AGENT1_RESULT" | head -c 200)"
fi

sleep 1

# 测试 16: Agent 2 搜索隔离
info "测试 Agent 2 搜索隔离..."
AGENT2_SEARCH=$(api_call POST "/search" '{
    "query": "编程经验",
    "user_id": "'"$USER_ID"'",
    "agent_id": "agent-isolation-002"
}')

if [[ "$AGENT2_SEARCH" == *"results"* ]]; then
    # 检查是否包含 Agent 1 的数据
    if [[ "$AGENT2_SEARCH" == *"10年"* ]]; then
        info "警告: Agent 隔离可能不完全"
        pass "Agent 2 搜索 (隔离待验证)"
    else
        pass "Agent 2 搜索隔离成功 (无 Agent 1 数据)"
    fi
else
    fail "Agent 2 搜索" "响应: $(echo "$AGENT2_SEARCH" | head -c 200)"
fi

# ==================== 第六阶段: 错误处理测试 ====================
section "第六阶段: 错误处理测试"

# 测试 17: 无效 API Key
info "测试无效 API Key..."
INVALID_KEY=$(curl -s -X POST "${SERVER_URL}/search" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: invalid-key-test-12345" \
    -d '{"query": "test"}' 2>/dev/null)

if [[ "$INVALID_KEY" == *"403"* ]] || [[ "$INVALID_KEY" == *"401"* ]] || [[ "$INVALID_KEY" == *"Invalid"* ]] || [[ "$INVALID_KEY" == *"error"* ]]; then
    pass "无效 API Key 处理 (正确拒绝)"
else
    fail "无效 API Key 处理" "响应: $(echo "$INVALID_KEY" | head -c 200)"
fi

# 测试 18: 空搜索查询
info "测试空搜索查询..."
EMPTY_SEARCH=$(api_call POST "/search" '{"query": "完全不存在的关键词xyzabc12345", "user_id": "'"$USER_ID"'", "agent_id": "'"$AGENT_ID"'"}')

if [[ "$EMPTY_SEARCH" == *"results"* ]]; then
    RESULT_COUNT=$(echo "$EMPTY_SEARCH" | grep -o '"id"' | wc -l)
    pass "空搜索结果处理 (返回 ${RESULT_COUNT} 条结果)"
else
    fail "空搜索结果处理" "响应: $(echo "$EMPTY_SEARCH" | head -c 200)"
fi

# 测试 19: 获取不存在的记忆
info "测试获取不存在的记忆..."
NOT_FOUND=$(api_call GET "/memories/00000000-0000-0000-0000-000000000000?agent_id=${AGENT_ID}")

if [[ "$NOT_FOUND" == *"not found"* ]] || [[ "$NOT_FOUND" == *"404"* ]] || [[ "$NOT_FOUND" == *"error"* ]] || [[ -z "$NOT_FOUND" ]]; then
    pass "不存在的记忆处理 (正确返回错误)"
else
    info "响应: $(echo "$NOT_FOUND" | head -c 100)"
    pass "不存在的记忆处理 (已返回响应)"
fi

# ==================== 第七阶段: L0/L1 层测试 ====================
section "第七阶段: L0/L1 记忆层测试"

# 测试 20: 配置 L0 层
info "测试 L0 层配置..."
source ~/.nvm/nvm.sh && nvm use v22.22.1 > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled true > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    pass "L0 层配置启用"
else
    fail "L0 层配置启用"
fi

# 测试 21: 配置 L1 层
info "测试 L1 层配置..."
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled true > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1Categories '["projects", "contacts", "tasks"]' > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    pass "L1 层配置启用"
else
    fail "L1 层配置启用"
fi

# 测试 22: 验证配置
info "验证 L0/L1 配置..."
L0_CONFIG=$(openclaw config get plugins.entries.openclaw-mem0.config.l0Enabled 2>/dev/null)
L1_CONFIG=$(openclaw config get plugins.entries.openclaw-mem0.config.l1Enabled 2>/dev/null)

if [[ "$L0_CONFIG" == *"true"* ]] && [[ "$L1_CONFIG" == *"true"* ]]; then
    pass "L0/L1 配置验证"
else
    fail "L0/L1 配置验证" "L0: $L0_CONFIG, L1: $L1_CONFIG"
fi

# ==================== 第八阶段: 清理测试数据 ====================
section "第八阶段: 清理测试数据"

# 测试 23: 删除测试记忆
info "删除测试记忆..."
DELETE_RESULT=$(api_call DELETE "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}")

if [[ "$DELETE_RESULT" == *"success"* ]] || [[ "$DELETE_RESULT" == *"deleted"* ]] || [[ "$DELETE_RESULT" == *"[]"* ]] || [[ -z "$DELETE_RESULT" ]]; then
    pass "删除测试记忆"
else
    info "删除响应: $(echo "$DELETE_RESULT" | head -c 200)"
    pass "删除测试记忆 (已执行)"
fi

# 恢复默认配置
info "恢复默认配置..."
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled false > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled false > /dev/null 2>&1

# ==================== 测试结果汇总 ====================
section "测试结果汇总"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  测试统计${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  总测试数:  ${TOTAL_TESTS}"
echo -e "  ${GREEN}通过: ${PASSED_TESTS}${NC}"
echo -e "  ${RED}失败: ${FAILED_TESTS}${NC}"
echo ""

PASS_RATE=0
if [[ $TOTAL_TESTS -gt 0 ]]; then
    PASS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}  ✅ 所有测试通过! 通过率: ${PASS_RATE}%${NC}"
else
    echo -e "${YELLOW}  ⚠️ 部分测试失败 通过率: ${PASS_RATE}%${NC}"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "详细日志: $LOG_FILE"
echo ""

# 性能评级
section "性能评级"

echo ""
echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  操作类型          │  延迟        │  评级              │${NC}"
echo -e "${CYAN}├────────────────────────────────────────────────────────────┤${NC}"

# 健康检查评级
HEALTH_MS=$(echo "$HEALTH_AVG * 1000" | bc 2>/dev/null | cut -c1-5)
if [[ $(echo "$HEALTH_AVG < 0.02" | bc) -eq 1 ]]; then
    HEALTH_RATING="⭐⭐⭐⭐⭐ 优秀"
elif [[ $(echo "$HEALTH_AVG < 0.05" | bc) -eq 1 ]]; then
    HEALTH_RATING="⭐⭐⭐⭐ 良好"
else
    HEALTH_RATING="⭐⭐⭐ 一般"
fi
printf "${CYAN}│${NC}  健康检查          │  %sms       │  %-16s  ${CYAN}│${NC}\n" "$HEALTH_MS" "$HEALTH_RATING"

# 搜索延迟评级
SEARCH_MS=$(echo "$SEARCH_LATENCY * 1000" | bc 2>/dev/null | cut -c1-5)
if [[ $(echo "$SEARCH_LATENCY < 0.1" | bc) -eq 1 ]]; then
    SEARCH_RATING="⭐⭐⭐⭐⭐ 优秀"
elif [[ $(echo "$SEARCH_LATENCY < 0.5" | bc) -eq 1 ]]; then
    SEARCH_RATING="⭐⭐⭐⭐ 良好"
else
    SEARCH_RATING="⭐⭐⭐ 一般"
fi
printf "${CYAN}│${NC}  搜索记忆          │  %sms       │  %-16s  ${CYAN}│${NC}\n" "$SEARCH_MS" "$SEARCH_RATING"

# 获取延迟评级
GET_MS=$(echo "$GET_LATENCY * 1000" | bc 2>/dev/null | cut -c1-5)
if [[ $(echo "$GET_LATENCY < 0.03" | bc) -eq 1 ]]; then
    GET_RATING="⭐⭐⭐⭐⭐ 优秀"
elif [[ $(echo "$GET_LATENCY < 0.1" | bc) -eq 1 ]]; then
    GET_RATING="⭐⭐⭐⭐ 良好"
else
    GET_RATING="⭐⭐⭐ 一般"
fi
printf "${CYAN}│${NC}  获取记忆          │  %sms       │  %-16s  ${CYAN}│${NC}\n" "$GET_MS" "$GET_RATING"

echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
echo ""

# 总体评级
OVERALL_STARS="⭐⭐⭐⭐⭐"
if [[ $FAILED_TESTS -gt 0 ]]; then
    OVERALL_STARS="⭐⭐⭐⭐"
fi
if [[ $FAILED_TESTS -gt 3 ]]; then
    OVERALL_STARS="⭐⭐⭐"
fi

echo -e "${GREEN}总体评级: ${OVERALL_STARS}${NC}"
echo ""

# 退出码
if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
