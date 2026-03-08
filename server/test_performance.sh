#!/bin/bash
# Mem0 Server Performance Test Suite
# 测试服务器的各种性能指标

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Performance tracking
PERF_RESULTS=()

# Helper functions
setup_agent() {
    local agent_id=$1
    local description=$2
    curl -s -X POST $BASE_URL/admin/keys \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $ADMIN_KEY" \
        -d "{\"agent_id\": \"$agent_id\", \"description\": \"$description\"}" \
        | jq -r '.api_key'
}

cleanup_agent() {
    local agent_id=$1
    local api_key=$2
    # Reset all memories for agent
    curl -s -X POST "$BASE_URL/reset?agent_id=$agent_id" \
        -H "X-API-Key: $api_key" > /dev/null
}

format_time() {
    local seconds=$1
    if (( $(echo "$seconds < 1" | bc -l) )); then
        echo "${CYAN}${seconds}s${NC}"
    elif (( $(echo "$seconds < 60" | bc -l) )); then
        local ms=$(echo "$seconds * 1000" | bc | cut -d. -f1)
        echo "${CYAN}${ms}ms${NC}"
    else
        echo "${CYAN}${seconds}s${NC}"
    fi
}

record_result() {
    local test_name=$1
    local metric=$2
    local value=$3
    local unit=$4
    PERF_RESULTS+=("$test_name|$metric|$value|$unit")
}

# ============================================================================
# Phase 1: Baseline Tests
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 1: Baseline Tests${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 1.1: Single Memory Creation
echo -e "${BLUE}Test 1.1: Single Memory Creation${NC}"
API_KEY=$(setup_agent "perf_agent_01" "Performance test agent")

START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "The quick brown fox jumps over the lazy dog. This is a test of memory storage performance."}],
        "user_id": "perf_user",
        "agent_id": "perf_agent_01"
    }')
END=$(date +%s.%N)

MEMORY_COUNT=$(echo $RESULT | jq '.results | length')
TIME_ELAPSED=$(echo "$END - $START" | bc)
record_result "Single Memory Creation" "time" "$TIME_ELAPSED" "s"
echo -e "  Time: $(format_time $TIME_ELAPSED)"
echo -e "  Memories created: ${GREEN}$MEMORY_COUNT${NC}"

# Test 1.2: Memory Search (single match)
echo -e "\n${BLUE}Test 1.2: Memory Search (single match)${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "query": "quick brown fox",
        "user_id": "perf_user",
        "agent_id": "perf_agent_01",
        "limit": 10
    }')
END=$(date +%s.%N)

SEARCH_COUNT=$(echo $RESULT | jq '.results | length')
TIME_ELAPSED=$(echo "$END - $START" | bc)
record_result "Memory Search (single)" "time" "$TIME_ELAPSED" "s"
echo -e "  Time: $(format_time $TIME_ELAPSED)"
echo -e "  Results found: ${GREEN}$SEARCH_COUNT${NC}"

# ============================================================================
# Phase 2: Bulk Operations
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 2: Bulk Operations${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 2.1: Bulk Memory Creation (10 memories)
echo -e "${BLUE}Test 2.1: Bulk Memory Creation (10 memories)${NC}"
START=$(date +%s.%N)

MESSAGES='[
    {"role": "user", "content": "Memory 1: User prefers dark mode in applications"},
    {"role": "user", "content": "Memory 2: Works as a software engineer"},
    {"role": "user", "content": "Memory 3: Lives in San Francisco"},
    {"role": "user", "content": "Memory 4: Uses Python for backend development"},
    {"role": "user", "content": "Memory 5: Has experience with React and Vue.js"},
    {"role": "user", "content": "Memory 6: Enjoys hiking and outdoor activities"},
    {"role": "user", "content": "Memory 7: Prefers vegetarian food options"},
    {"role": "user", "content": "Memory 8: Reads science fiction novels"},
    {"role": "user", "content": "Memory 9: Has a cat named Whiskers"},
    {"role": "user", "content": "Memory 10: Plays guitar in a band"}
]'

RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d "{\"messages\": $MESSAGES, \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent_01\"}")

END=$(date +%s.%N)
MEMORY_COUNT=$(echo $RESULT | jq '.results | length')
TIME_ELAPSED=$(echo "$END - $START" | bc)

record_result "Bulk Memory Creation (10)" "time" "$TIME_ELAPSED" "s"
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 10" | bc)
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per memory: ${CYAN}${AVG_TIME}s${NC}"
echo -e "  Memories created: ${GREEN}$MEMORY_COUNT${NC}"

# Test 2.2: Retrieve All Memories (10)
echo -e "\n${BLUE}Test 2.2: Retrieve All Memories (10)${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s "$BASE_URL/memories?agent_id=perf_agent_01&user_id=perf_user" \
    -H "X-API-Key: $API_KEY")
END=$(date +%s.%N)

RETRIEVED_COUNT=$(echo $RESULT | jq '.results | length')
TIME_ELAPSED=$(echo "$END - $START" | bc)

record_result "Retrieve All Memories (10)" "time" "$TIME_ELAPSED" "s"
echo -e "  Time: $(format_time $TIME_ELAPSED)"
echo -e "  Memories retrieved: ${GREEN}$RETRIEVED_COUNT${NC}"

# ============================================================================
# Phase 3: Concurrency Tests
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 3: Concurrency Tests${NC}"
echo -e "${YELLOW}=========================================${NC}\n"

# Test 3.1: Concurrent Memory Creation (5 parallel)
echo -e "${BLUE}Test 3.1: Concurrent Memory Creation (5 parallel)${NC}"
START=$(date +%s.%N)

# Launch 5 parallel requests
for i in {1..5}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Concurrent test memory $i\"}], \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent_01\"}" > /dev/null &
done

# Wait for all requests to complete
wait

END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)

record_result "Concurrent Creation (5)" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per request: ${CYAN}$(echo "scale=3; $TIME_ELAPSED / 5" | bc)s${NC}"

# Test 3.2: Concurrent Search (10 parallel)
echo -e "\n${BLUE}Test 3.2: Concurrent Search (10 parallel)${NC}"
START=$(date +%s.%N)

for i in {1..10}; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"query\": \"concurrent test $i\", \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent_01\", \"limit\": 3}" > /dev/null &
done

wait
END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)

record_result "Concurrent Search (10)" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per request: ${CYAN}$(echo "scale=3; $TIME_ELAPSED / 10" | bc)s${NC}"

# ============================================================================
# Phase 4: Multi-Agent Isolation Performance
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 4: Multi-Agent Isolation Performance${NC}"
echo -e "${YELLOW}=========================================${NC}\n"

API_KEY_2=$(setup_agent "perf_agent_02" "Performance test agent 2")
API_KEY_3=$(setup_agent "perf_agent_03" "Performance test agent 3")

# Create memories for different agents
echo -e "${BLUE}Test 4.1: Create memories for 3 different agents${NC}"
START=$(date +%s.%N)

curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Agent 1 specific memory"}], "user_id": "perf_user", "agent_id": "perf_agent_01"}' > /dev/null &

curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{"messages": [{"role": "user", "content": "Agent 2 specific memory"}], "user_id": "perf_user", "agent_id": "perf_agent_02"}' > /dev/null &

curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_3" \
    -d '{"messages": [{"role": "user", "content": "Agent 3 specific memory"}], "user_id": "perf_user", "agent_id": "perf_agent_03"}' > /dev/null &

wait
END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)

record_result "Multi-Agent Create (3)" "time" "$TIME_ELAPSED" "s"
echo -e "  Time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per agent: ${CYAN}$(echo "scale=3; $TIME_ELAPSED / 3" | bc)s${NC}"

# Test 4.2: Search each agent's memories
echo -e "\n${BLUE}Test 4.2: Search each agent's memories${NC}"
START=$(date +%s.%N)

RESULT_1=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "specific", "agent_id": "perf_agent_01", "limit": 5}' > /dev/null)

RESULT_2=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{"query": "specific", "agent_id": "perf_agent_02", "limit": 5}' > /dev/null)

RESULT_3=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_3" \
    -d '{"query": "specific", "agent_id": "perf_agent_03", "limit": 5}' > /dev/null &

wait
END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)

COUNT_1=$(echo $RESULT_1 | jq '.results | length')
COUNT_2=$(echo $RESULT_2 | jq '.results | length')
COUNT_3=$(echo $RESULT_3 | jq '.results | length')

record_result "Multi-Agent Search (3)" "time" "$TIME_ELAPSED" "s"
echo -e "  Time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per agent: ${CYAN}$(echo "scale=3; $TIME_ELAPSED / 3" | bc)s${NC}"
echo -e "  Agent 1 results: $COUNT_1"
echo -e "  Agent 2 results: $COUNT_2"
echo -e "  Agent 3 results: $COUNT_3"

# ============================================================================
# Phase 5: Load Testing
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 5: Load Testing${NC}"
echo -e "${YELLOW}=========================================${NC}\n"

# Test 5.1: Sequential read operations (20 requests)
echo -e "${BLUE}Test 5.1: Sequential read operations (20 requests)${NC}"
START=$(date +%s.%N)

for i in {1..20}; do
    curl -s "$BASE_URL/memories?agent_id=perf_agent_01&user_id=perf_user" \
        -H "X-API-Key: $API_KEY" > /dev/null
done

END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 20" | bc)

record_result "Sequential Read (20)" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per request: ${CYAN}${AVG_TIME}s${NC}"

# Test 5.2: Health check load (50 requests)
echo -e "\n${BLUE}Test 5.2: Health check load (50 requests)${NC}"
START=$(date +%s.%N)

SUCCESS_COUNT=0
for i in {1..50}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health)
    if [ "$HTTP_CODE" -eq 200 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
done

END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 50" | bc)

record_result "Health Check (50)" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per request: ${CYAN}${AVG_TIME}s${NC}"
echo -e "  Success rate: ${GREEN}$SUCCESS_COUNT/50${NC}"

# Test 5.3: Random read queries (20)
echo -e "\n${BLUE}Test 5.3: Random read queries (20)${NC}"
START=$(date +%s.%N)

# First, add more memories for testing
for i in {1..20}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Load test memory $i\"}], \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent_01\"}" > /dev/null &
done
wait

# Perform random reads
SEARCH_QUERIES=(
    "software"
    "San Francisco"
    "prefers"
    "experience"
    "memory"
    "test"
    "quick"
    "brown"
    "specific"
)

for query in "${SEARCH_QUERIES[@]}"; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"query\": \"$query\", \"agent_id\": \"perf_agent_01\", \"limit\": 5}" > /dev/null
done

END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 20" | bc)

record_result "Random Search (20)" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per query: ${CYAN}${AVG_TIME}s${NC}"

# ============================================================================
# Phase 6: Memory Growth Performance
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Phase 6: Memory Growth Performance${NC}"
echo -e "${YELLOW}=========================================${NC}\n"

cleanup_agent "perf_agent_02" "$API_KEY_2"
API_KEY_2=$(setup_agent "perf_agent_02" "Growth test agent")

# Test 6.1: Create 50 memories and measure performance
echo -e "${BLUE}Test 6.1: Create 50 memories${NC}"
START=$(date +%s.%N)

# Create memories in batches of 10
for batch in {1..5}; do
    MESSAGES="[]"
    for i in $(seq 1 10); do
        idx=$(( (batch - 1) * 10 + i))
        MESSAGES="$MESSAGES, {\"role\": \"user\", \"content\": \"Growth test memory $idx\"}"
    done

    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY_2" \
        -d "{\"messages\": $MESSAGES, \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent_02\"}" > /dev/null
done

END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 50" | bc)

record_result "Create 50 Memories" "time" "$TIME_ELAPSED" "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per memory: ${CYAN}${AVG_TIME}s${NC}"

# Verify memory count
RESULT=$(curl -s "$BASE_URL/memories?agent_id=perf_agent_02&user_id=perf_user" \
    -H "X-API-Key: $API_KEY_2")
FINAL_COUNT=$(echo $RESULT | jq '.results | length')
echo -e "  Verified count: ${GREEN}$FINAL_COUNT${NC}"

# Test 6.2: Search performance with 50 memories
echo -e "\n${BLUE}Test 6.2: Search performance with 50 memories${NC}"
START=$(date +%s.%N)

for i in {1..10}; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY_2" \
        -d "{\"query\": \"Growth test memory\", \"agent_id\": \"perf_agent_02\", \"limit\": 10}" > /dev/null &
done

wait
END=$(date +%s.%N)
TIME_ELAPSED=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME_ELAPSED / 10" | bc)

record_result "Search with 50 Memories" "time" "$TIME_ELAPSED) "s"
echo -e "  Total time: $(format_time $TIME_ELAPSED)"
echo -e "  Avg per search: ${CYAN}${AVG_TIME}s${NC}"

# ============================================================================
# Performance Summary
# ============================================================================
echo -e "\n${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Performance Test Summary${NC}"
echo -e "${YELLOW}=========================================${NC}\n"

echo -e "${CYAN}Test Results:${NC}"
echo -e "+--------------------------------------+-----------+--------+"
echo -e "| Test                        | Metric     | Value  | Unit   |"
echo -e "+--------------------------------------+-----------+--------+--------+"

for result in "${PERF_RESULTS[@]}"; do
    IFS='|' read -r test_name metric value unit <<< "$result"
    printf "| %-27s | %-10s | %6s | %-6s |\n" "$test_name" "$metric" "$value" "$unit"
done

echo -e "+--------------------------------------+-----------+--------+--------+"

# Calculate some key metrics
echo -e "\n${CYAN}Key Insights:${NC}"

# Calculate total operations
TOTAL_OPS=0
for result in "${PERF_RESULTS[@]}"; do
    IFS='|' read -r test_name metric value unit <<< "$result"
    if [[ "$test_name" == *"(10)"* ]] || [[ "$test_name" == *"(20)"* ]] || [[ "$test_name" == *"(50)"* ]]; then
        TOTAL_OPS=$((TOTAL_OPS + 10))
    elif [[ "$test_name" == *"(20)"* ]]; then
        TOTAL_OPS=$((TOTAL_OPS + 20))
    elif [[ "$test_name" == *"(50)"* ]]; then
        TOTAL_OPS=$((TOTAL_OPS + 50))
    fi
done

TOTAL_TESTS=${#PERF_RESULTS[@]}
echo -e "  Total operations performed: ${GREEN}$TOTAL_OPS${NC}"
echo -e "  Total tests executed: ${GREEN}$TOTAL_TESTS${NC}"

# Find fastest and slowest single operations
FASTEST=""
FASTEST_TIME=9999
SLOWEST=""
SLOWEST_TIME=0

for result in "${PERF_RESULTS[@]}"; do
    IFS='|' read -r test_name metric value unit <<< "$result"
    if [[ "$test_name" == *"Single"* ]] || [[ "$test_name" == *"Search (single)"* ]]; then
        if (( $(echo "$value < $FASTEST_TIME" | bc -l) )); then
            FASTEST_TIME=$value
            FASTEST="$test_name"
        fi
        if (( $(echo "$value > $SLOWEST_TIME" | bc -l) )); then
            SLOWEST_TIME=$value
            SLOWEST="$test_name"
        fi
    fi
done

echo -e "  Fastest operation: ${GREEN}$FASTEST${NC} ($CYAN}${FASTEST_TIME}s${NC})"
echo -e "  Slowest operation: ${RED}$SLOWEST${NC} ($CYAN}${SLOWEST_TIME}s${NC})"

# ============================================================================
# Cleanup
# ============================================================================
echo -e "\n${YELLOW}Cleaning up test data...${NC}"

cleanup_agent "perf_agent_01" "$API_KEY"
cleanup_agent "perf_agent_02" "$API_KEY_2"
cleanup_agent "perf_agent_03" "$API_KEY_3"

# Delete API keys
curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY\"}" > /dev/null

curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY_2\"}" > /dev/null

curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY_3\"}" > /dev/null

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Performance Test Complete${NC}"
echo -e "${YELLOW}=========================================${NC}\n"
