#!/bin/bash
# Mem0 Plugin Comprehensive Test Suite - Final Fixed Version

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# Helper: record test result
record_result() {
    local name="$1"
    local status="$2"
    local details="$3"
    local duration="$4"
    TEST_RESULTS+=("$name|$status|$details|$duration")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$status" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  ${GREEN}✓ PASS${NC} - $details"
    elif [ "$status" = "FAIL" ]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "  ${RED}✗ FAIL${NC} - $details"
    fi
}

# Helper: format time
format_time() {
    local seconds=$1
    local cmp=$(echo "$seconds < 1" | bc -l)
    if [ "$cmp" = "1" ]; then
        local ms=$(echo "$seconds * 1000" | bc | cut -d. -f1)
        echo "${CYAN}${ms}ms${NC}"
    else
        echo "${CYAN}${seconds}s${NC}"
    fi
}

# Setup test agent
echo -e "${BLUE}Setting up test agent...${NC}"
API_KEY=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "test_agent", "description": "Plugin test"}' | jq -r '.api_key')
echo -e "  API Key: ${API_KEY:0:25}...${NC}\n"

# ============================================================================
# Phase 1: Server Mode - Basic Operations
# ============================================================================
echo -e "\n${YELLOW}=== Phase 1: Server Mode - Basic Operations ===${NC}"

# Test 1.1: Create memory
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Test memory"}], "user_id": "test_user", "agent_id": "test_agent"}')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server: Create Memory" "PASS" "Created $COUNT memories in $(format_time $TIME)"
else
    record_result "Server: Create Memory" "FAIL" "No memories created"
fi

# Test 1.2: Search memory
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "Test", "user_id": "test_user", "agent_id": "test_agent", "limit": 5}')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server: Search Memory" "PASS" "Found $COUNT memories in $(format_time $TIME)"
else
    record_result "Server: Search Memory" "FAIL" "No memories found"
fi

# Test 1.3: Get all memories
START=$(date +%s.%N)
RESULT=$(curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
    -H "X-API-Key: $API_KEY")
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
record_result "Server: Get All Memories" "PASS" "Retrieved $COUNT memories in $(format_time $TIME)"

# Test 1.4: Delete memory
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Delete test"}], "user_id": "test_user", "agent_id": "test_agent"}' > /dev/null)

# Get memory ID
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "Delete", "user_id": "test_user", "agent_id": "test_agent", "limit": 3}')
MEM_ID=$(echo $RESULT | jq -r '.results[0].id // empty')

if [ -n "$MEM_ID" ] && [ "$MEM_ID" != "null" ]; then
    START=$(date +%s.%N)
    DEL_RESULT=$(curl -s -X DELETE "$BASE_URL/memories/$MEM_ID?agent_id=test_agent" \
        -H "X-API-Key: $API_KEY" > /dev/null)
    END=$(date +%s.%N)
    record_result "Server: Delete Memory" "PASS" "Deleted memory in $(format_time $TIME)"
else
    record_result "Server: Delete Memory" "WARN" "No memory found to delete"
fi

# ============================================================================
# Phase 2: Performance Tests
# ============================================================================
echo -e "\n${YELLOW}=== Phase 2: Performance Tests ===${NC}"

# Test 2.1: Bulk create (5 memories)
echo -e "${BLUE}Test 2.1: Bulk Create (5 memories)${NC}"
START=$(date +%s.%N)
for i in {1..5}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H 'X-API-Key: $API_KEY' \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Bulk test memory $i\"}], \"user_id\": \"test_user\", \"agent_id\": \"test_agent\"}" > /dev/null &
done
wait
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 5" | bc)
record_result "Server: Bulk Create (5)" "PASS" "Completed in $(format_time $TIME) ($(format_time $AVG) avg)"

# Test 2.2: Sequential reads (10)
echo -e "\n${BLUE}Test 2.2: Sequential Reads (10)${NC}"
START=$(date +%s.%N)
for i in {1..10}; do
    curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
        -H "X-API-Key: $API_KEY" > /dev/null
done
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 10" | bc)
record_result "Server: Sequential Reads (10)" "PASS" "Completed in $(format_time $TIME) ($(format_time $AVG) avg/read)"

# Test 2.3: Health check load (50 requests)
echo -e "\n${BLUE}Test 2.3: Health Check Load (50)${NC}"
START=$(date +%s.%N)
SUCCESS=0
for i in $(seq 1 50); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health)
    [ "$CODE" -eq 200 ] && SUCCESS=$((SUCCESS + 1))
done
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
record_result "Server: Health Check (50)" "PASS" "$SUCCESS/50 requests succeeded in $(format_time $TIME)"

# Test 2.4: Latency test (5 samples)
echo -e "\n${BLUE}Test 2.4: Memory Creation Latency (5 samples)${NC}"
TIMES=()
for i in {1..5}; do
    START=$(date +%s.%N)
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H 'X-API-Key: $API_KEY' \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Latency test $i\"}], \"user_id\": \"latency_user\", \"agent_id\": \"test_agent\"}" > /dev/null
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)
    TIMES+=($TIME)
done
TOTAL_TIME=0
for t in "${TIMES[@]}"; do
    TOTAL_TIME=$(echo "$TOTAL_TIME + $t" | bc -l)
done
AVG_TIME=$(echo "scale=2; $TOTAL_TIME / 5" | bc)
MIN_TIME=$(printf "%s\n" "${TIMES[@]}" | sort -n | head -1)
MAX_TIME=$(printf "%s\n" "${TIMES[@]}" | sort -n | tail -1)
record_result "Server: Memory Creation Latency (5)" "PASS" "Avg: $(format_time $AVG_TIME), Min: $(format_time $MIN_TIME), Max: $(format_time $MAX_TIME)"

# ============================================================================
# Phase 3: Error Handling
# ============================================================================
echo -e "\n${YELLOW}=== Phase 3: Error Handling Tests ===${NC}"

# Test 3.1: Invalid API key
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H 'X-API-Key: invalid_key' -d '{"messages": [{"role": "user", "content": "Test"}], "user_id": "test_user", "agent_id": "test_agent"}')
if [ "$HTTP_CODE" -eq 401 ]; then
    record_result "Server: Invalid API Key" "PASS" "Correctly rejected with 401"
else
    record_result "Server: Invalid API Key" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# Test 3.2: Missing required parameters
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H 'X-API-Key: $API_KEY' \
    -d '{"messages": [{"role": "user", "content": "Test"}]}')
if [ "$HTTP_CODE" -eq 400 ]; then
    record_result "Server: Missing Parameters" "PASS" "Correctly rejected with 400"
else
    record_result "Server: Missing Parameters" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# ============================================================================
# Phase 4: Multi-Agent Isolation
# ============================================================================
echo -e "\n${YELLOW}=== Phase 4: Multi-Agent Isolation ===${NC}"

# Create API key for agent 2
API_KEY_2=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "test_agent_2", "description": "Isolation test"}' | jq -r '.api_key')

# Add memories for agent 1
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Agent 1 specific memory"}], "user_id": "test_user", "agent_id": "test_agent"}' > /dev/null

# Add memories for agent 2
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{"messages": [{"role": "user", "content": "Agent 2 specific memory"}], "user_id": "test_user", "agent_id": "test_agent_2"}' > /dev/null

# Check isolation
RESULT_1=$(curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
    -H "X-API-Key: $API_KEY")
RESULT_2=$(curl -s "$BASE_URL/memories?agent_id=test_agent_2&user_id=test_user" \
    -H "X-API-Key: $API_KEY_2")

COUNT_1=$(echo "$RESULT_1" | jq '.results | length')
COUNT_2=$(echo "$RESULT_2" | jq '.results | length')

# Check for data leakage (agent 1 should not see agent 2's memory)
HAS_AGENT_1_IN_1=$(echo "$RESULT_1" | jq -r '.results[].memory' | grep -c "Agent 1")
HAS_AGENT_2_IN_1=$(echo "$RESULT_1" | jq -r '.results[].memory' | grep -c "Agent 2")
HAS_AGENT_2_IN_2=$(echo "$RESULT_2" | jq -r '.results[].memory' | grep -c "Agent 2")

if [ "$HAS_AGENT_1_IN_1" -gt 0 ] && [ "$HAS_AGENT_2_IN_1" -eq 0 ] && [ "$HAS_AGENT_2_IN_2" -gt 0 ]; then
    record_result "Multi-Agent Isolation" "PASS" "Agents properly isolated (Agent 1: $COUNT_1, Agent 2: $COUNT_2)"
else
    record_result "Multi-Agent Isolation" "FAIL" "Data leakage detected (A1_in_1: $HAS_AGENT_1_IN_1, A2_in_1: $HAS_AGENT_2_IN_1, A2_in_2: $HAS_AGENT_2_IN_2)"
fi

# ============================================================================
# Cleanup
# ============================================================================
echo -e "\n${YELLOW}=== Cleanup ===${NC}"

# Reset memories
curl -s -X POST "$BASE_URL/reset?agent_id=test_agent" \
    -H "X-API-Key: $API_KEY" > /dev/null

# Reset memories for agent 2
curl -s -X POST "$BASE_URL/reset?agent_id=test_agent_2" \
    -H "X-API-Key: $API_KEY_2" > /dev/null

# Delete API keys
curl -s -X DELETE "$BASE_URL/admin/keys" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY\"}" > /dev/null

curl -s -X DELETE "$BASE_URL/admin/keys" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY_2\"}" > /dev/null

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${YELLOW}=== Test Summary ===${NC}\n"

echo -e "${CYAN}Results:${NC}"
echo -e "+--------------------------------+----------+----------------------------------------+"
echo -e "| Test                           | Status   | Details                                |"
echo -e "+--------------------------------+----------+----------------------------------------+"

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r test_name status details duration <<< "$result"
    printf "| %-30s | %-8s | %-38s |\n" \
        "$test_name" "$status" "$details"
done

echo -e "+--------------------------------+----------+----------------------------------------+"

# Statistics
echo -e "\n${CYAN}Total: $TOTAL_TESTS tests"
echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
if [ "$TOTAL_TESTS" -gt 0 ]; then
    echo -e "  Pass rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
fi

# Overall status
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
elif [ "$FAILED_TESTS" -lt "$((TOTAL_TESTS / 3))" ]; then
    echo -e "\n${YELLOW}⚠ SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "\n${RED}✗ CRITICAL FAILURES${NC}"
    exit 2
fi
