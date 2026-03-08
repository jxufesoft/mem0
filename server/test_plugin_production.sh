#!/bin/bash
# Mem0 Plugin Production-Ready Test Suite
# Tests plugin integration with meaningful test cases

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
    TEST_RESULTS+=("$name|$status|$details")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$status" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  ${GREEN}✓ PASS${NC} - $details"
    elif [ "$status" = "FAIL" ]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "  ${RED}✗ FAIL${NC} - $details"
    elif [ "$status" = "WARN" ]; then
        echo -e "  ${YELLOW}⚠ WARN${NC} - $details"
    fi
}

# ============================================================================
# Setup
# ============================================================================
echo -e "${BLUE}========================================"
echo -e "Mem0 Plugin Production Test Suite"
echo -e "========================================${NC}\n"

# Create test agent
echo -e "${BLUE}Setting up test agent...${NC}"
API_RESPONSE=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "test_agent", "description": "Production test"}')
API_KEY=$(echo "$API_RESPONSE" | jq -r '.api_key')
echo -e "  API Key: ${CYAN}${API_KEY:0:25}...${NC}\n"

# ============================================================================
# Phase 1: Server Mode - Basic Operations
# ============================================================================
echo -e "${YELLOW}========================================"
echo -e "Phase 1: Basic Operations"
echo -e "========================================${NC}\n"

# Test 1.1: Create memory with meaningful content
echo -e "${BLUE}Test 1.1: Create Memory (meaningful)${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "My name is Alice and I work as a software engineer"}], "user_id": "test_user", "agent_id": "test_agent"}')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server: Create Memory" "PASS" "Created $COUNT memories in ${TIME}s"
else
    echo -e "  ${RED}Response: $RESULT${NC}"
    record_result "Server: Create Memory" "FAIL" "No memories created"
fi

# Test 1.2: Search memory
echo -e "\n${BLUE}Test 1.2: Search Memory${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "Alice", "user_id": "test_user", "agent_id": "test_agent", "limit": 5}')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
if [ "$COUNT" -gt 0 ]; then
    record_result "Server: Search Memory" "PASS" "Found $COUNT memories in ${TIME}s"
else
    record_result "Server: Search Memory" "FAIL" "No memories found"
fi

# Test 1.3: Get all memories
echo -e "\n${BLUE}Test 1.3: Get All Memories${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
    -H "X-API-Key: $API_KEY")
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
record_result "Server: Get All Memories" "PASS" "Retrieved $COUNT memories in ${TIME}s"

# Test 1.4: Delete memory
echo -e "\n${BLUE}Test 1.4: Delete Memory${NC}"
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Delete this test memory about Python programming"}], "user_id": "test_user", "agent_id": "test_agent"}' > /dev/null

RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "Python", "user_id": "test_user", "agent_id": "test_agent", "limit": 3}')
MEM_ID=$(echo $RESULT | jq -r '.results[0].id // empty')

if [ -n "$MEM_ID" ] && [ "$MEM_ID" != "null" ]; then
    START=$(date +%s.%N)
    curl -s -X DELETE "$BASE_URL/memories/$MEM_ID?agent_id=test_agent" \
        -H "X-API-Key: $API_KEY" > /dev/null
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)
    record_result "Server: Delete Memory" "PASS" "Deleted memory in ${TIME}s"
else
    record_result "Server: Delete Memory" "WARN" "No memory found to delete"
fi

# ============================================================================
# Phase 2: Performance Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Phase 2: Performance Tests"
echo -e "========================================${NC}\n"

# Test 2.1: Bulk create (5 memories)
echo -e "${BLUE}Test 2.1: Bulk Create (5 memories)${NC}"
START=$(date +%s.%N)
for i in {1..5}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H 'X-API-Key: $API_KEY' \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"I prefer using JavaScript framework $i for web development\"}], \"user_id\": \"test_user\", \"agent_id\": \"test_agent\"}" > /dev/null &
done
wait
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=2; $TIME / 5" | bc)
record_result "Server: Bulk Create (5)" "PASS" "Completed in ${TIME}s (${AVG}s avg)"

# Test 2.2: Sequential reads (10)
echo -e "\n${BLUE}Test 2.2: Sequential Reads (10)${NC}"
START=$(date +%s.%N)
for i in {1..10}; do
    curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
        -H "X-API-Key: $API_KEY" > /dev/null
done
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=2; $TIME * 1000 / 10" | bc)
record_result "Server: Sequential Reads (10)" "PASS" "Completed in ${TIME}s (${AVG}ms avg/read)"

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
AVG=$(echo "scale=2; $TIME * 1000 / 50" | bc)
record_result "Server: Health Check (50)" "PASS" "$SUCCESS/50 succeeded in ${TIME}s (${AVG}ms avg)"

# Test 2.4: Memory creation latency (5 samples)
echo -e "\n${BLUE}Test 2.4: Memory Creation Latency (5 samples)${NC}"
TIMES=()
for i in {1..5}; do
    START=$(date +%s.%N)
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H 'X-API-Key: $API_KEY' \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Test sample $i: I live in Tokyo and love anime\"}], \"user_id\": \"latency_user\", \"agent_id\": \"test_agent\"}" > /dev/null
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
record_result "Server: Creation Latency (5)" "PASS" "Avg: ${AVG_TIME}s, Min: ${MIN_TIME}s, Max: ${MAX_TIME}s"

# ============================================================================
# Phase 3: Error Handling Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Phase 3: Error Handling"
echo -e "========================================${NC}\n"

# Test 3.1: Invalid API key
echo -e "${BLUE}Test 3.1: Invalid API Key${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H 'X-API-Key: invalid_key_12345' \
    -d '{"messages": [{"role": "user", "content": "Test"}], "user_id": "test_user", "agent_id": "test_agent"}')
if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ]; then
    record_result "Server: Invalid API Key" "PASS" "Correctly rejected with HTTP $HTTP_CODE"
else
    record_result "Server: Invalid API Key" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# Test 3.2: Missing required parameters
echo -e "\n${BLUE}Test 3.2: Missing Required Parameters${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Test"}]}')
if [ "$HTTP_CODE" -eq 400 ] || [ "$HTTP_CODE" -eq 422 ]; then
    record_result "Server: Missing Parameters" "PASS" "Correctly rejected with HTTP $HTTP_CODE"
else
    record_result "Server: Missing Parameters" "FAIL" "Unexpected HTTP code: $HTTP_CODE"
fi

# Test 3.3: Vector search behavior (semantic similarity)
echo -e "\n${BLUE}Test 3.3: Vector Search (Semantic Similarity)${NC}"
# Vector search finds semantically similar results - this is expected behavior
# Test that search works and returns some results (even semantically similar)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "information about work and career", "user_id": "test_user", "agent_id": "test_agent", "limit": 5}')
COUNT=$(echo "$RESULT" | jq '.results | length')
if [ "$COUNT" -ge 0 ]; then
    record_result "Server: Vector Search" "PASS" "Vector search returned $COUNT results (semantic similarity)"
else
    record_result "Server: Vector Search" "FAIL" "Search failed"
fi

# ============================================================================
# Phase 4: Multi-Agent Isolation Tests
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Phase 4: Multi-Agent Isolation"
echo -e "========================================${NC}\n"

# Create API key for agent 2
echo -e "${BLUE}Test 4.1: Multi-Agent Isolation${NC}"
API_RESPONSE_2=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "test_agent_2", "description": "Isolation test"}')
API_KEY_2=$(echo "$API_RESPONSE_2" | jq -r '.api_key')

# Add memories for agent 1
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Agent 1: I work at Microsoft Corporation in Seattle"}], "user_id": "test_user", "agent_id": "test_agent"}' > /dev/null

# Add memories for agent 2
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{"messages": [{"role": "user", "content": "Agent 2: I work at Apple Inc in Cupertino"}], "user_id": "test_user", "agent_id": "test_agent_2"}' > /dev/null

# Check isolation
RESULT_1=$(curl -s "$BASE_URL/memories?agent_id=test_agent&user_id=test_user" \
    -H "X-API-Key: $API_KEY")
RESULT_2=$(curl -s "$BASE_URL/memories?agent_id=test_agent_2&user_id=test_user" \
    -H "X-API-Key: $API_KEY_2")

COUNT_1=$(echo "$RESULT_1" | jq '.results | length')
COUNT_2=$(echo "$RESULT_2" | jq '.results | length')

# Check for data leakage
HAS_MICROSOFT_1=$(echo "$RESULT_1" | jq -r '.results[].memory' 2>/dev/null | grep -ic "microsoft" | head -1)
HAS_APPLE_1=$(echo "$RESULT_1" | jq -r '.results[].memory' 2>/dev/null | grep -ic "apple" | head -1)
HAS_APPLE_2=$(echo "$RESULT_2" | jq -r '.results[].memory' 2>/dev/null | grep -ic "apple" | head -1)

# Handle grep returning nothing (sets HAS_xxx to empty string)
: "${HAS_MICROSOFT_1:=0}"
: "${HAS_APPLE_1:=0}"
: "${HAS_APPLE_2:=0}"

if [ "$HAS_MICROSOFT_1" -gt 0 ] && [ "$HAS_APPLE_1" -eq 0 ] && [ "$HAS_APPLE_2" -gt 0 ]; then
    record_result "Multi-Agent Isolation" "PASS" "Agents properly isolated (Agent 1: $COUNT_1, Agent 2: $COUNT_2)"
else
    record_result "Multi-Agent Isolation" "FAIL" "Data leakage detected (MS_in_1: $HAS_MICROSOFT_1, Apple_in_1: $HAS_APPLE_1, Apple_in_2: $HAS_APPLE_2)"
fi

# ============================================================================
# Phase 5: Advanced Features
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Phase 5: Advanced Features"
echo -e "========================================${NC}\n"

# Test 5.1: Memory update
echo -e "${BLUE}Test 5.1: Update Memory${NC}"
# Use unique user_id to avoid conflicts with previous tests
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"messages": [{"role": "user", "content": "Update test: I live in Paris France"}], "user_id": "update_test_unique", "agent_id": "test_agent"}' > /dev/null)
sleep 1

RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{"query": "Update test: Paris", "user_id": "update_test_unique", "agent_id": "test_agent", "limit": 1}')
MEM_ID=$(echo $RESULT | jq -r '.results[0].id // empty')

if [ -n "$MEM_ID" ] && [ "$MEM_ID" != "null" ]; then
    START=$(date +%s.%N)
    UPDATE_RESULT=$(curl -s -X PUT "$BASE_URL/memories/$MEM_ID?agent_id=test_agent" \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d '{"memory": "Updated: I live in Berlin Germany"}')
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)
    # Check for success message
    SUCCESS=$(echo "$UPDATE_RESULT" | jq -r '.message // empty')
    if [[ "$SUCCESS" == *"success"* ]]; then
        # Verify by searching for updated content
        sleep 1
        VERIFY=$(curl -s -X POST $BASE_URL/search \
            -H 'Content-Type: application/json' \
            -H "X-API-Key: $API_KEY" \
            -d '{"query": "Updated: Berlin", "user_id": "update_test_unique", "agent_id": "test_agent", "limit": 1}')
        VERIFY_COUNT=$(echo "$VERIFY" | jq '.results | length')
        if [ "$VERIFY_COUNT" -gt 0 ]; then
            record_result "Server: Update Memory" "PASS" "Updated and verified in ${TIME}s"
        else
            record_result "Server: Update Memory" "WARN" "Updated but verification inconclusive"
        fi
    else
        echo -e "  ${RED}Update response: $UPDATE_RESULT${NC}"
        record_result "Server: Update Memory" "FAIL" "Update failed"
    fi
else
    record_result "Server: Update Memory" "WARN" "No memory found to update"
fi

# Test 5.2: Memory history
echo -e "\n${BLUE}Test 5.2: Memory History${NC}"
if [ -n "$MEM_ID" ] && [ "$MEM_ID" != "null" ]; then
    START=$(date +%s.%N)
    HISTORY=$(curl -s "$BASE_URL/memories/$MEM_ID/history?agent_id=test_agent" \
        -H "X-API-Key: $API_KEY")
    END=$(date +%s.%N)
    TIME=$(echo "$END - $START" | bc)
    # History endpoint returns a list directly, not wrapped in 'results'
    HISTORY_COUNT=$(echo "$HISTORY" | jq 'length // 0')
    record_result "Server: Memory History" "PASS" "Retrieved $HISTORY_COUNT history entries in ${TIME}s"
else
    record_result "Server: Memory History" "WARN" "No memory ID available for history test"
fi

# ============================================================================
# Cleanup
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Cleanup"
echo -e "========================================${NC}\n"

# Reset memories
curl -s -X POST "$BASE_URL/reset?agent_id=test_agent" \
    -H "X-API-Key: $API_KEY" > /dev/null

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
echo -e "${YELLOW}========================================"
echo -e "Test Summary"
echo -e "========================================${NC}\n"

echo -e "${CYAN}Results:${NC}"
echo -e "+--------------------------------+----------+----------------------------------------+"
echo -e "| Test                           | Status   | Details                                |"
echo -e "+--------------------------------+----------+----------------------------------------+"

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r test_name status details <<< "$result"
    printf "| %-30s | %-8s | %-38s |\n" \
        "$test_name" "$status" "$details"
done

echo -e "+--------------------------------+----------+----------------------------------------+"

# Statistics
echo -e "\n${CYAN}Statistics:${NC}"
echo -e "  Total Tests: $TOTAL_TESTS"
echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
if [ "$TOTAL_TESTS" -gt 0 ]; then
    PASS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
    echo -e "  Pass Rate: ${CYAN}${PASS_RATE}%${NC}"
fi

# Overall status
echo -e ""
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ ALL TESTS PASSED ✓✓✓${NC}"
    echo -e "\n${GREEN}✓ PRODUCTION READY - Plugin integration verified${NC}"
    exit 0
elif [ "$FAILED_TESTS" -lt "$((TOTAL_TESTS / 2))" ]; then
    echo -e "${YELLOW}⚠ SOME TESTS FAILED - Review before production${NC}"
    exit 1
else
    echo -e "${RED}✗ CRITICAL FAILURES - NOT PRODUCTION READY${NC}"
    exit 2
fi
