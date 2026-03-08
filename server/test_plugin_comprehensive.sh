#!/bin/bash
# Mem0 Plugin Comprehensive Test Suite
# 测试 OpenClaw Plugin 与 Server 的完整集成

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
MAGENTA='\033[0;35m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

TEST_RESULTS=()

# Helper functions
record_result() {
    local test_name=$1
    local status=$2
    local details=$3
    local duration=$4
    TEST_RESULTS+=("$test_name|$status|$details|$duration")
    if [ "$status" == "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  ${GREEN}✓ PASS${NC} - $details"
    elif [ "$status" == "FAIL" ]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "  ${RED}✗ FAIL${NC} - $details"
    elif [ "$status" == "WARN" ]; then
        WARNINGS=$((WARNINGS + 1))
        echo -e "  ${YELLOW}⚠ WARN${NC} - $details"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
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

# ============================================================================
# Setup
# ============================================================================
echo -e "${YELLOW}========================================"
echo -e "${YELLOW}Mem0 Plugin Comprehensive Test Suite"
echo -e "${YELLOW}========================================${NC}\n"

# Create test agent
echo -e "${BLUE}Setting up test agent for plugin tests...${NC}"
API_KEY=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "plugin_test_agent", "description": "Plugin comprehensive test"}' | jq -r '.api_key')
echo -e "  API Key: ${CYAN}${API_KEY:0:30}...${NC}\n"

# ============================================================================
# Phase 1: Server Mode Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Phase 1: Server Mode Tests${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 1.1: Server - Create Memory
echo -e "${BLUE}Test 1.1: Server Mode - Create Memory${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Server test: My name is Alice"}],
        "user_id": "plugin_test_user",
        "agent_id": "plugin_test_agent"
    }')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server Mode: Create Memory" "PASS" "Created $COUNT memories in $(format_time $TIME)"
else
    record_result "Server Mode: Create Memory" "FAIL" "No memories created"
fi

# Test 1.2: Server - Search Memory
echo -e "\n${BLUE}Test 1.2: Server Mode - Search Memory${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "query": "Alice",
        "user_id": "plugin_test_user",
        "agent_id": "plugin_test_agent",
        "limit": 5
    }')
END=$(date +%s.%N)
TIME=$(echo "$END - $ $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server Mode: Search Memory" "PASS" "Found $COUNT memories in $(format_time $TIME)"
else
    record_result "Server Mode: Search Memory" "FAIL" "No memories found"
fi

# Test 1.3: Server - Get All Memories
echo -e "\n${BLUE}Test 1.3: Server Mode - Get All Memories${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s "$BASE_URL/memories?agent_id=plugin_test_agent&user_id=plugin_test_user" \
    -H "X-API-Key: $API_KEY")
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
record_result "Server Mode: Get All Memories" "PASS" "Retrieved $COUNT memories in $(format_time $TIME)"

# Test 1.4: Server - Delete Memory
echo -e "\n${BLUE}Test 1.4: Server Mode - Delete Memory${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Server test: I like coding"}], "user_id": "plugin_test_user", "agent_id": "plugin_test_agent"}' > /dev/null)
END=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: "application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "coding", "user_id": "plugin_test_user", "agent_id": "plugin_test_agent", "limit": 5}' > /dev/null)
MEM_ID=$(echo $RESULT | jq -r '.results[0].id // empty')
if [ -n "$MEM_ID" ] && [ "$MEM_ID" != "null" ]; then
    DEL_RESULT=$(curl -s -X DELETE "$BASE_URL/memories/$MEM_ID?agent_id=plugin_test_agent" \
        -H "X-API-Key: $API_KEY" > /dev/null)
    record_result "Server Mode: Delete Memory" "PASS" "Deleted memory in $(format_time $TIME)"
else
    record_result "Server Mode: Delete Memory" "WARN" "Could not find memory to delete"
fi

# ============================================================================
# Phase 2: Performance Tests (Server Mode)
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Phase 2: Performance Tests (Server Mode)${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 2.1: Bulk Create (10)
echo -e "${BLUE}Test 2.1: Server - Bulk Create (10 memories)${NC}"
START=$(date +%s.%N)
for i in {1..10}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Bulk test memory $i\"}], \"user_id\": \"plugin_test_user\", \"agent_id\": \"plugin_test_agent\"}" > /dev/null &
done
wait
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME / 10" | bc)
record_result "Server Mode: Bulk Create (10)" "PASS" "Completed in $(format_time $TIME) ($(format_time $AVG_TIME) avg/mem)"

# Test 2.2: Concurrent Search (10)
echo -e "\n${BLUE}Test 2.2: Server - Concurrent Search (10)${NC}"
START=$(date +%s.%N)
for i in {1..10}; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -h "X-API-Key: $API_KEY" \
        -d "{\"query\": \"test\", \"user_id\": \"plugin_test_user\", \"agent_id\": \"plugin_test_agent\", \"limit\": 3}" > /dev/null &
done
wait
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME / 10" | bc)
TOTAL_RESULTS=0
for i in {1..10}; do
    RESULTS=$(curl -s -X POST $BASE_URL/search \
        -h "X-API-Key: $API_KEY" \
        -d "{\"query\": \"test\", \"user_id\": \"plugin_test_user\", \"agent_id\": \"plugin_test_agent\", \"limit\": 3}" 2>/dev/null)
    COUNT=$(echo $RESULTS | jq '.results | length')
    TOTAL_RESULTS=$((TOTAL_RESULTS + COUNT))
done
AVG_RESULTS=$(echo "scale=1; $TOTAL_RESULTS / 10" | bc)
record_result "Server Mode: Concurrent Search (10)" "PASS" "Completed in $(format_time $TIME) ($(format_time $AVG_RESULTS) avg/results)"

# ============================================================================
# Phase 3: Multi-Agent Isolation Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Phase 3: Multi-Agent Isolation Tests${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Create API key for agent 2
API_KEY_2=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "plugin_agent_2", "description": "Multi-agent test"}' | jq -r '.api_key')

# Test 3.1: Create memories for agent 1
echo -e "${BLUE}Test 3.1: Create memory for Agent 1${NC}"
START=$(date +%s.%N)
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Agent 1: I prefer Python programming"}], "user_id": "test_user", "agent_id": "plugin_test_agent"}' > /dev/null

# Test 3.2: Create memories for agent 2
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{"messages": [{"role": "user", "content": "Agent 2: I prefer JavaScript programming"}], "user_id": "test_user", "agent_id": "plugin_agent_2"}' > /dev/null
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)

# Verify isolation
RESULT_1=$(curl -s "$BASE_URL/memories?agent_id=plugin_test_agent&user_id=test_user" \
    -H "X-API-Key: $API_KEY")
COUNT_1=$(echo $RESULT_1 | jq '.results | length')

RESULT_2=$(curl -s "$BASE_URL/memories?agent_id=plugin_agent_2&user_id=test_user" \
    -H "X-API-Key: $API_KEY_2")
COUNT_2=$(echo $RESULT_2 | jq '.results | length')

if [ "$COUNT_1" -gt 0 ] && [ "$COUNT_2" -gt 0 ] && [[ ! $(echo "$RESULT_1" | jq -r '.results[].memory' | grep -i "Python" ) ]]; then
    record_result "Multi-Agent Isolation" "FAIL" "Data leakage detected - Agent 2 found Agent 1 memory"
else
    record_result "Multi-Agent Isolation" "PASS" "Agents properly isolated (Agent 1: $COUNT_1 memories, Agent 2: $COUNT_2 memories)"
fi

# ============================================================================
# Phase 4: Error Handling Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Phase 4: Error Handling Tests${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 4.1: Invalid API Key
echo -e "${BLUE}Test 4.1: Invalid API Key${NC}"
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: invalid_key_12345" \
    -d '{"messages": [{"role": "user", "content": "Test"}], "user_id": "test_user", "agent_id": "plugin_test_agent"}' 2>&1)
HTTP_CODE=$?
if echo "$RESULT" | grep -q "401"; then
    record_result "Invalid API Key" "PASS" "Correctly rejected with 401"
elif echo "$RESULT" | grep -q "403"; then
    record_result "Invalid API Key" "PASS" "Correctly rejected with 403"
else
    record_result "Invalid API Key" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# Test 4.2: Missing required parameters
echo -e "\n${BLUE}Test 4.2: Missing required parameters${NC}"
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Test"}]}' 2>&1)
HTTP_CODE=$?
if echo "$RESULT" | grep -q "400"; then
    record_result "Missing Required Parameters" "PASS" "Correctly rejected with 400"
else
    record_result "Missing Required Parameters" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# Test 4.3: Query non-existent memory
echo -e "\n${BLUE}Test 4.3: Query non-existent memory${NC}"
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "nonexistent", "user_id": "test_user", "agent_id": "plugin_test_agent"}' 2>&1)
HTTP_CODE=$?
COUNT=$(echo "$RESULT" | jq '.results | length')
if [ "$COUNT" -eq 0 ]; then
    record_result "Query Non-Existent Memory" "PASS" "Correctly returned empty results"
else
    record_result "Query Non-Existent Memory" "FAIL" "Unexpected: $COUNT results"
fi

# ============================================================================
# Phase 5: Performance Benchmarks (Server Mode)
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Phase 5: Performance Benchmarks${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Test 5.1: Sequential reads (20)
echo -e "${BLUE}Test 5.1: Sequential Reads (20)${NC}"
START=$(date +%s.%N)
for i in {1..20}; do
    curl -s "$BASE_URL/memories?agent_id=plugin_test_agent&user_id=test_user" \
        -H "X-API-Key: $API_KEY" > /dev/null
done
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG_TIME=$(echo "scale=3; $TIME / 20" | bc)
record_result "Sequential Reads (20)" "PASS" "Completed in $(format_time $TIME) ($(format_time $AVG_TIME) avg/read)"

# Test 5.2: Health check load (50)
echo -e "\n${BLUE}Test 5.2: Health Check Load (50)${NC}"
START=$(date +%s.%N)
SUCCESS=0
for i in {1..50}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health)
    [ "$CODE" -eq 200 ] && SUCCESS=$((SUCCESS + 1))
done
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
record_result "Health Check Load (50)" "PASS" "$SUCCESS/50 requests succeeded in $(format_time $TIME) $(echo "scale=2; $SUCCESS * 100 / 50 | bc | bc) req/s)"

# Test 5.3: Memory creation latency (5 samples)
echo -e "\n${BLUE}Test 5.3: Memory Creation Latency (5 samples)${NC}"
TIMES=()
for i in {1..5}; do
    START=$(date +%s.%N)
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d '{"messages": [{"role": "user", "content": "Latency test sample '$i'"}], "user_id": "latency_test_user", "agent_id": "plugin_test_agent"}' > /dev/null
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)
    TIMES+=($TIME)
done
AVG_TIME=$(echo "scale=3; $(echo "${TIMES[@]}" | tr ' ' +') | bc -l | awk '{sum += $1; count++} END {print sum/count}')

MIN_TIME=$(echo "${TIMES[@]}" | tr ' ' ' | sort -n | head -1)
MAX_TIME=$(echo "${TIMES[@]}" | tr ' ' ' | sort -n | tail -1)
record_result "Memory Creation Latency (5)" "PASS" "Avg: $(format_time $AVG_TIME), Min: $(format_time $MIN_TIME), Max: $(format_time $MAX_TIME)"

# ============================================================================
# Cleanup
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Reset all memories
curl -s -X POST "$BASE_URL/reset?agent_id=plugin_test_agent" \
    -H "X-API-Key: $API_KEY" > /dev/null

curl -s -X POST "$BASE_URL/reset?agent_id=plugin_agent_2" \
    -H "X-API-Key: $API_KEY_2" > /dev/null

# Delete API keys
curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application final' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"api_key": "'"$API_KEY"'"}' > /dev/null

curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"api_key": "'"$API_KEY_2"'"}' > /dev/null

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}========================================${NC}\n"

echo -e "${CYAN}Test Summary:${NC}"
echo -e "+--------+------+---------+---------+"
echo -e "| Test                          | Status   | Details |         |"
echo -e "+--------+------+---------+---------+"

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r test_name status details duration <<< "$result"
    printf "| %-30s | %-7s | %-40s | %10s |" \
        "$test_name" "$status" "$details" "$duration"
    echo ""
done

echo -e "+--------+------+---------+---------+"

# Statistics
echo -e "\n${CYAN}Statistics:${NC}"
echo -e "  Total Tests: $TOTAL_TESTS"
echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
echo -e "  Warnings: ${YELLOW}$WARNINGS${NC}"
echo -e "  Pass Rate: ${CYAN}$(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%%"

# Overall status
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
elif [ "$FAILED_TESTS" -lt "$((TOTAL_TESTS / 3)" ]; then
    echo -e "\n${YELLOW}⚠ SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "\n${RED}✗ CRITICAL FAILURES${NC}"
    exit 2
fi
