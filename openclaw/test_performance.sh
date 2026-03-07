#!/bin/bash

# OpenClaw Mem0 Plugin 性能测试脚本
# 测试各种操作的吞吐量和延迟

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 测试配置
SERVER_URL="http://localhost:8000"
API_KEY="mem0_SxZcThQnwW05Du3_uODDLxspXQzXl6_TXErK7cjLPPI"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
USER_ID="perf-test-${TIMESTAMP}"
AGENT_ID="perf-agent"

# 结果存储
RESULTS_DIR="/tmp/mem0_perf_results_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# 辅助函数
log() {
    echo "[$(date '+%H:%M:%S.%3N')] $1"
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [[ -n "$data" ]]; then
        curl -s -w "\n%{http_code}\n%{time_total}" -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${API_KEY}" \
            -d "$data" 2>/dev/null
    else
        curl -s -w "\n%{http_code}\n%{time_total}" -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${API_KEY}" 2>/dev/null
    fi
}

section() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 计算统计数据
calc_stats() {
    local file=$1
    local values=$(cat "$file" | tr '\n' ' ')
    local count=$(echo "$values" | wc -w)
    
    if [[ $count -eq 0 ]]; then
        echo "0 0 0 0 0"
        return
    fi
    
    # 排序计算百分位
    local sorted=$(echo "$values" | tr ' ' '\n' | sort -n | tr '\n' ' ')
    local sum=$(echo "$values" | awk '{sum+=$1} END {printf "%.6f", sum}')
    local avg=$(echo "scale=6; $sum / $count" | bc)
    
    # P50
    local p50_idx=$((count / 2))
    local p50=$(echo "$sorted" | cut -d' ' -f$((p50_idx + 1)))
    
    # P95
    local p95_idx=$(echo "$count * 95 / 100" | bc)
    local p95=$(echo "$sorted" | cut -d' ' -f$((p95_idx + 1)))
    
    # P99
    local p99_idx=$(echo "$count * 99 / 100" | bc)
    local p99=$(echo "$sorted" | cut -d' ' -f$((p99_idx + 1)))
    
    # Max
    local max=$(echo "$sorted" | tr ' ' '\n' | tail -1)
    
    echo "$avg $p50 $p95 $p99 $max"
}

format_ms() {
    local sec=$1
    echo $(echo "scale=2; $sec * 1000" | bc)
}

# ==================== 开始测试 ====================

section "OpenClaw Mem0 Plugin 性能测试"
echo -e "${BLUE}测试配置:${NC}"
echo "  服务器: $SERVER_URL"
echo "  用户 ID: $USER_ID"
echo "  Agent ID: $AGENT_ID"
echo "  时间: $(date)"
echo ""

# 预热
section "预热测试"
echo -e "${YELLOW}发送 5 个预热请求...${NC}"
for i in {1..5}; do
    api_call POST "/search" '{"query": "warmup", "user_id": "'"$USER_ID"'", "agent_id": "'"$AGENT_ID"'"}' > /dev/null
done
echo -e "${GREEN}预热完成${NC}"

# ==================== 测试 1: 健康检查性能 ====================
section "测试 1: 健康检查性能 (100 次)"

HEALTH_TIMES="$RESULTS_DIR/health_times.txt"
> "$HEALTH_TIMES"

echo -e "${YELLOW}执行中...${NC}"
START_TOTAL=$(date +%s.%N)

for i in {1..100}; do
    START=$(date +%s.%N)
    curl -s "${SERVER_URL}/health" > /dev/null
    END=$(date +%s.%N)
    echo "scale=6; $END - $START" | bc >> "$HEALTH_TIMES"
done

END_TOTAL=$(date +%s.%N)
TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)

STATS=$(calc_stats "$HEALTH_TIMES")
AVG=$(echo "$STATS" | cut -d' ' -f1)
P50=$(echo "$STATS" | cut -d' ' -f2)
P95=$(echo "$STATS" | cut -d' ' -f3)
P99=$(echo "$STATS" | cut -d' ' -f4)
MAX=$(echo "$STATS" | cut -d' ' -f5)

THROUGHPUT=$(echo "scale=1; 100 / $TOTAL_TIME" | bc)

echo ""
echo -e "${GREEN}结果:${NC}"
echo -e "  总耗时: ${TOTAL_TIME}s"
echo -e "  吞吐量: ${THROUGHPUT} req/s"
echo -e "  平均延迟: $(format_ms $AVG)ms"
echo -e "  P50: $(format_ms $P50)ms"
echo -e "  P95: $(format_ms $P95)ms"
echo -e "  P99: $(format_ms $P99)ms"
echo -e "  最大: $(format_ms $MAX)ms"

# ==================== 测试 2: 记忆创建性能 ====================
section "测试 2: 记忆创建性能 (30 次)"

CREATE_TIMES="$RESULTS_DIR/create_times.txt"
> "$CREATE_TIMES"
MEMORY_IDS="$RESULTS_DIR/memory_ids.txt"
> "$MEMORY_IDS"

echo -e "${YELLOW}执行中 (包含 LLM 事实提取)...${NC}"
START_TOTAL=$(date +%s.%N)

for i in {1..30}; do
    START=$(date +%s.%N)
    RESULT=$(api_call POST "/memories" "{
        \"messages\": [{\"role\": \"user\", \"content\": \"性能测试记录 $i: 用户喜欢编程和阅读技术文档，项目名称是 Project-$i\"}],
        \"user_id\": \"$USER_ID\",
        \"agent_id\": \"$AGENT_ID\"
    }")
    END=$(date +%s.%N)
    
    echo "scale=6; $END - $START" | bc >> "$CREATE_TIMES"
    
    # 提取记忆 ID
    echo "$RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 >> "$MEMORY_IDS"
    
    printf "\r  进度: %d/30" $i
done

END_TOTAL=$(date +%s.%N)
TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)

echo ""
echo ""

STATS=$(calc_stats "$CREATE_TIMES")
AVG=$(echo "$STATS" | cut -d' ' -f1)
P50=$(echo "$STATS" | cut -d' ' -f2)
P95=$(echo "$STATS" | cut -d' ' -f3)
P99=$(echo "$STATS" | cut -d' ' -f4)
MAX=$(echo "$STATS" | cut -d' ' -f5)

THROUGHPUT=$(echo "scale=2; 30 / $TOTAL_TIME" | bc)

echo -e "${GREEN}结果:${NC}"
echo -e "  总耗时: ${TOTAL_TIME}s"
echo -e "  吞吐量: ${THROUGHPUT} req/s"
echo -e "  平均延迟: $(format_ms $AVG)ms"
echo -e "  P50: $(format_ms $P50)ms"
echo -e "  P95: $(format_ms $P95)ms"
echo -e "  P99: $(format_ms $P99)ms"
echo -e "  最大: $(format_ms $MAX)ms"

# ==================== 测试 3: 搜索性能 ====================
section "测试 3: 搜索性能 (100 次)"

SEARCH_TIMES="$RESULTS_DIR/search_times.txt"
> "$SEARCH_TIMES"

echo -e "${YELLOW}执行中 (向量语义搜索)...${NC}"
START_TOTAL=$(date +%s.%N)

for i in {1..100}; do
    START=$(date +%s.%N)
    api_call POST "/search" "{
        \"query\": \"编程 OR 项目 OR 技术文档\",
        \"user_id\": \"$USER_ID\",
        \"agent_id\": \"$AGENT_ID\"
    }" > /dev/null
    END=$(date +%s.%N)
    echo "scale=6; $END - $START" | bc >> "$SEARCH_TIMES"
    
    if (( i % 10 == 0 )); then
        printf "\r  进度: %d/100" $i
    fi
done

END_TOTAL=$(date +%s.%N)
TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)

echo ""
echo ""

STATS=$(calc_stats "$SEARCH_TIMES")
AVG=$(echo "$STATS" | cut -d' ' -f1)
P50=$(echo "$STATS" | cut -d' ' -f2)
P95=$(echo "$STATS" | cut -d' ' -f3)
P99=$(echo "$STATS" | cut -d' ' -f4)
MAX=$(echo "$STATS" | cut -d' ' -f5)

THROUGHPUT=$(echo "scale=1; 100 / $TOTAL_TIME" | bc)

echo -e "${GREEN}结果:${NC}"
echo -e "  总耗时: ${TOTAL_TIME}s"
echo -e "  吞吐量: ${THROUGHPUT} req/s"
echo -e "  平均延迟: $(format_ms $AVG)ms"
echo -e "  P50: $(format_ms $P50)ms"
echo -e "  P95: $(format_ms $P95)ms"
echo -e "  P99: $(format_ms $P99)ms"
echo -e "  最大: $(format_ms $MAX)ms"

# ==================== 测试 4: 获取所有记忆性能 ====================
section "测试 4: 获取所有记忆性能 (100 次)"

GETALL_TIMES="$RESULTS_DIR/getall_times.txt"
> "$GETALL_TIMES"

echo -e "${YELLOW}执行中...${NC}"
START_TOTAL=$(date +%s.%N)

for i in {1..100}; do
    START=$(date +%s.%N)
    api_call GET "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}" > /dev/null
    END=$(date +%s.%N)
    echo "scale=6; $END - $START" | bc >> "$GETALL_TIMES"
    
    if (( i % 10 == 0 )); then
        printf "\r  进度: %d/100" $i
    fi
done

END_TOTAL=$(date +%s.%N)
TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)

echo ""
echo ""

STATS=$(calc_stats "$GETALL_TIMES")
AVG=$(echo "$STATS" | cut -d' ' -f1)
P50=$(echo "$STATS" | cut -d' ' -f2)
P95=$(echo "$STATS" | cut -d' ' -f3)
P99=$(echo "$STATS" | cut -d' ' -f4)
MAX=$(echo "$STATS" | cut -d' ' -f5)

THROUGHPUT=$(echo "scale=1; 100 / $TOTAL_TIME" | bc)

echo -e "${GREEN}结果:${NC}"
echo -e "  总耗时: ${TOTAL_TIME}s"
echo -e "  吞吐量: ${THROUGHPUT} req/s"
echo -e "  平均延迟: $(format_ms $AVG)ms"
echo -e "  P50: $(format_ms $P50)ms"
echo -e "  P95: $(format_ms $P95)ms"
echo -e "  P99: $(format_ms $P99)ms"
echo -e "  最大: $(format_ms $MAX)ms"

# ==================== 测试 5: 并发搜索性能 ====================
section "测试 5: 并发搜索性能 (10/20/50 并发)"

for CONCURRENCY in 10 20 50; do
    echo -e "${YELLOW}测试 ${CONCURRENCY} 并发...${NC}"
    
    START=$(date +%s.%N)
    
    for i in $(seq 1 $CONCURRENCY); do
        api_call POST "/search" "{
            \"query\": \"并发测试 $i\",
            \"user_id\": \"$USER_ID\",
            \"agent_id\": \"$AGENT_ID\"
        }" > /dev/null &
    done
    wait
    
    END=$(date +%s.%N)
    TIME=$(echo "scale=3; $END - $START" | bc)
    THROUGHPUT=$(echo "scale=1; $CONCURRENCY / $TIME" | bc)
    
    echo -e "  ${CONCURRENCY} 并发: ${TIME}s, ${THROUGHPUT} req/s"
done

# ==================== 测试 6: 更新记忆性能 ====================
section "测试 6: 更新记忆性能 (20 次)"

UPDATE_TIMES="$RESULTS_DIR/update_times.txt"
> "$UPDATE_TIMES"

# 获取一个有效的记忆 ID
MEMORY_ID=$(head -1 "$MEMORY_IDS")

if [[ -n "$MEMORY_ID" ]]; then
    echo -e "${YELLOW}执行中...${NC}"
    START_TOTAL=$(date +%s.%N)
    
    for i in {1..20}; do
        START=$(date +%s.%N)
        api_call PUT "/memories/${MEMORY_ID}?agent_id=${AGENT_ID}" "{
            \"data\": \"更新后的记忆内容 $i: 包含新的编程项目信息\"
        }" > /dev/null
        END=$(date +%s.%N)
        echo "scale=6; $END - $START" | bc >> "$UPDATE_TIMES"
    done
    
    END_TOTAL=$(date +%s.%N)
    TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)
    
    STATS=$(calc_stats "$UPDATE_TIMES")
    AVG=$(echo "$STATS" | cut -d' ' -f1)
    P50=$(echo "$STATS" | cut -d' ' -f2)
    P95=$(echo "$STATS" | cut -d' ' -f3)
    P99=$(echo "$STATS" | cut -d' ' -f4)
    
    THROUGHPUT=$(echo "scale=2; 20 / $TOTAL_TIME" | bc)
    
    echo -e "${GREEN}结果:${NC}"
    echo -e "  总耗时: ${TOTAL_TIME}s"
    echo -e "  吞吐量: ${THROUGHPUT} req/s"
    echo -e "  平均延迟: $(format_ms $AVG)ms"
    echo -e "  P50: $(format_ms $P50)ms"
    echo -e "  P95: $(format_ms $P95)ms"
    echo -e "  P99: $(format_ms $P99)ms"
else
    echo -e "${RED}跳过: 没有可用的记忆 ID${NC}"
fi

# ==================== 测试 7: 获取历史性能 ====================
section "测试 7: 获取记忆历史性能 (50 次)"

HISTORY_TIMES="$RESULTS_DIR/history_times.txt"
> "$HISTORY_TIMES"

if [[ -n "$MEMORY_ID" ]]; then
    echo -e "${YELLOW}执行中...${NC}"
    START_TOTAL=$(date +%s.%N)
    
    for i in {1..50}; do
        START=$(date +%s.%N)
        api_call GET "/memories/${MEMORY_ID}/history?agent_id=${AGENT_ID}" > /dev/null
        END=$(date +%s.%N)
        echo "scale=6; $END - $START" | bc >> "$HISTORY_TIMES"
    done
    
    END_TOTAL=$(date +%s.%N)
    TOTAL_TIME=$(echo "scale=3; $END_TOTAL - $START_TOTAL" | bc)
    
    STATS=$(calc_stats "$HISTORY_TIMES")
    AVG=$(echo "$STATS" | cut -d' ' -f1)
    P50=$(echo "$STATS" | cut -d' ' -f2)
    P95=$(echo "$STATS" | cut -d' ' -f3)
    P99=$(echo "$STATS" | cut -d' ' -f4)
    
    THROUGHPUT=$(echo "scale=1; 50 / $TOTAL_TIME" | bc)
    
    echo -e "${GREEN}结果:${NC}"
    echo -e "  总耗时: ${TOTAL_TIME}s"
    echo -e "  吞吐量: ${THROUGHPUT} req/s"
    echo -e "  平均延迟: $(format_ms $AVG)ms"
    echo -e "  P50: $(format_ms $P50)ms"
    echo -e "  P95: $(format_ms $P95)ms"
    echo -e "  P99: $(format_ms $P99)ms"
fi

# ==================== 测试 8: 批量删除性能 ====================
section "测试 8: 批量创建后删除性能"

BATCH_SIZES=(10 20 50)

for BATCH in "${BATCH_SIZES[@]}"; do
    echo -e "${YELLOW}批量创建 ${BATCH} 条记忆...${NC}"
    
    CREATE_START=$(date +%s.%N)
    for i in $(seq 1 $BATCH); do
        api_call POST "/memories" "{
            \"messages\": [{\"role\": \"user\", \"content\": \"批量测试 $i\"}],
            \"user_id\": \"batch-$BATCH\",
            \"agent_id\": \"$AGENT_ID\"
        }" > /dev/null
    done
    CREATE_END=$(date +%s.%N)
    CREATE_TIME=$(echo "scale=3; $CREATE_END - $CREATE_START" | bc)
    
    echo -e "${YELLOW}批量删除 ${BATCH} 条记忆...${NC}"
    DELETE_START=$(date +%s.%N)
    api_call DELETE "/memories?user_id=batch-$BATCH&agent_id=${AGENT_ID}" > /dev/null
    DELETE_END=$(date +%s.%N)
    DELETE_TIME=$(echo "scale=3; $DELETE_END - $DELETE_START" | bc)
    
    echo -e "  创建 ${BATCH} 条: ${CREATE_TIME}s"
    echo -e "  删除全部: ${DELETE_TIME}s"
done

# ==================== 清理测试数据 ====================
section "清理测试数据"
echo -e "${YELLOW}删除所有测试记忆...${NC}"
api_call DELETE "/memories?user_id=${USER_ID}&agent_id=${AGENT_ID}" > /dev/null
echo -e "${GREEN}清理完成${NC}"

# ==================== 性能报告 ====================
section "性能测试报告"

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                    Mem0 Plugin 性能测试报告                         ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║  操作              │  平均延迟    │  P95         │  吞吐量        ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════════╣${NC}"

# 健康检查
HEALTH_STATS=$(calc_stats "$HEALTH_TIMES")
HEALTH_AVG=$(format_ms $(echo "$HEALTH_STATS" | cut -d' ' -f1))
HEALTH_P95=$(format_ms $(echo "$HEALTH_STATS" | cut -d' ' -f3))
HEALTH_TPS=$(echo "scale=0; 1000 / $HEALTH_AVG" | bc)
printf "${MAGENTA}║${NC}  健康检查          │  %5sms     │  %5sms     │  %5d req/s   ${MAGENTA}║${NC}\n" "$HEALTH_AVG" "$HEALTH_P95" "$HEALTH_TPS"

# 搜索
SEARCH_STATS=$(calc_stats "$SEARCH_TIMES")
SEARCH_AVG=$(format_ms $(echo "$SEARCH_STATS" | cut -d' ' -f1))
SEARCH_P95=$(format_ms $(echo "$SEARCH_STATS" | cut -d' ' -f3))
SEARCH_TPS=$(echo "scale=0; 1000 / $SEARCH_AVG" | bc)
printf "${MAGENTA}║${NC}  搜索记忆          │  %5sms     │  %5sms     │  %5d req/s   ${MAGENTA}║${NC}\n" "$SEARCH_AVG" "$SEARCH_P95" "$SEARCH_TPS"

# 获取全部
GETALL_STATS=$(calc_stats "$GETALL_TIMES")
GETALL_AVG=$(format_ms $(echo "$GETALL_STATS" | cut -d' ' -f1))
GETALL_P95=$(format_ms $(echo "$GETALL_STATS" | cut -d' ' -f3))
GETALL_TPS=$(echo "scale=0; 1000 / $GETALL_AVG" | bc)
printf "${MAGENTA}║${NC}  获取全部          │  %5sms     │  %5sms     │  %5d req/s   ${MAGENTA}║${NC}\n" "$GETALL_AVG" "$GETALL_P95" "$GETALL_TPS"

# 创建
CREATE_STATS=$(calc_stats "$CREATE_TIMES")
CREATE_AVG=$(format_ms $(echo "$CREATE_STATS" | cut -d' ' -f1))
CREATE_P95=$(format_ms $(echo "$CREATE_STATS" | cut -d' ' -f3))
CREATE_TPS=$(echo "scale=1; 1000 / $CREATE_AVG" | bc)
printf "${MAGENTA}║${NC}  创建记忆(含LLM)   │  %5sms     │  %5sms     │  %5s req/s   ${MAGENTA}║${NC}\n" "$CREATE_AVG" "$CREATE_P95" "$CREATE_TPS"

# 更新
if [[ -f "$UPDATE_TIMES" && -s "$UPDATE_TIMES" ]]; then
    UPDATE_STATS=$(calc_stats "$UPDATE_TIMES")
    UPDATE_AVG=$(format_ms $(echo "$UPDATE_STATS" | cut -d' ' -f1))
    UPDATE_P95=$(format_ms $(echo "$UPDATE_STATS" | cut -d' ' -f3))
    UPDATE_TPS=$(echo "scale=1; 1000 / $UPDATE_AVG" | bc)
    printf "${MAGENTA}║${NC}  更新记忆          │  %5sms     │  %5sms     │  %5s req/s   ${MAGENTA}║${NC}\n" "$UPDATE_AVG" "$UPDATE_P95" "$UPDATE_TPS"
fi

# 历史
if [[ -f "$HISTORY_TIMES" && -s "$HISTORY_TIMES" ]]; then
    HISTORY_STATS=$(calc_stats "$HISTORY_TIMES")
    HISTORY_AVG=$(format_ms $(echo "$HISTORY_STATS" | cut -d' ' -f1))
    HISTORY_P95=$(format_ms $(echo "$HISTORY_STATS" | cut -d' ' -f3))
    HISTORY_TPS=$(echo "scale=0; 1000 / $HISTORY_AVG" | bc)
    printf "${MAGENTA}║${NC}  获取历史          │  %5sms     │  %5sms     │  %5d req/s   ${MAGENTA}║${NC}\n" "$HISTORY_AVG" "$HISTORY_P95" "$HISTORY_TPS"
fi

echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║                       性能评级                                      ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════════╣${NC}"

# 计算总体评级
OVERALL_SCORE=0
if [[ $(echo "$HEALTH_AVG < 20" | bc) -eq 1 ]]; then OVERALL_SCORE=$((OVERALL_SCORE + 20)); fi
if [[ $(echo "$SEARCH_AVG < 100" | bc) -eq 1 ]]; then OVERALL_SCORE=$((OVERALL_SCORE + 25)); fi
if [[ $(echo "$GETALL_AVG < 50" | bc) -eq 1 ]]; then OVERALL_SCORE=$((OVERALL_SCORE + 20)); fi
if [[ $(echo "$CREATE_AVG < 2000" | bc) -eq 1 ]]; then OVERALL_SCORE=$((OVERALL_SCORE + 20)); fi
if [[ -n "$UPDATE_AVG" ]] && [[ $(echo "$UPDATE_AVG < 200" | bc) -eq 1 ]]; then OVERALL_SCORE=$((OVERALL_SCORE + 15)); fi

if [[ $OVERALL_SCORE -ge 90 ]]; then
    RATING="⭐⭐⭐⭐⭐ 优秀 (95分+)"
elif [[ $OVERALL_SCORE -ge 75 ]]; then
    RATING="⭐⭐⭐⭐ 良好 (75-94分)"
elif [[ $OVERALL_SCORE -ge 60 ]]; then
    RATING="⭐⭐⭐ 合格 (60-74分)"
else
    RATING="⭐⭐ 需优化 (60分以下)"
fi

printf "${MAGENTA}║${NC}  综合评分: %-50s  ${MAGENTA}║${NC}\n" "$OVERALL_SCORE 分"
printf "${MAGENTA}║${NC}  总体评级: %-50s  ${MAGENTA}║${NC}\n" "$RATING"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo "详细结果保存在: $RESULTS_DIR"
echo "测试完成时间: $(date)"
