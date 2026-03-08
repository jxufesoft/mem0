#!/bin/bash
# Comprehensive API Test Script for Mem0 Server

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL=0
PASSED=0
FAILED=0

# Helper function to test API
test_api() {
    local name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expected_code="$5"
    local headers="$6"

    TOTAL=$((TOTAL + 1))
    echo -e "${YELLOW}TEST $TOTAL: $name${NC}"

    if [ -z "$data" ]; then
        CMD="curl -s -w '\n%{http_code}' -X $method $url $headers"
    else
        CMD="curl -s -w '\n%{http_code}' -X $method $url -H 'Content-Type: application/json' -d '$data' $headers"
    fi

    RESULT=$(eval $CMD)
    HTTP_CODE=$(echo "$RESULT" | tail -n1)
    BODY=$(echo "$RESULT" | sed '$d')

    if [ "$HTTP_CODE" -eq "$expected_code" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗ FAIL${NC} (Expected: $expected_code, Got: $HTTP_CODE)"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "=========================================="
echo "Mem0 Server API Comprehensive Test Suite"
echo "=========================================="
echo ""

# ============================================================================
# Phase 1: Admin Endpoints (require ADMIN_SECRET_KEY)
# ============================================================================
echo -e "${YELLOW}=== Phase 1: Admin Endpoints ===${NC}"

ADMIN_HEADERS="-H 'X-API-Key: $ADMIN_KEY'"

# Test 1: Create API Key
API_KEY_RESPONSE=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "test_agent_001", "description": "Test agent for API testing"}')

API_KEY=$(echo $API_KEY_RESPONSE | jq -r '.api_key')
echo "  Created API Key: $API_KEY"

test_api "Create API key" \
    "POST" \
    "$BASE_URL/admin/keys" \
    '{"agent_id": "test_agent_002", "description": "Test agent 2"}' \
    200 \
    "$ADMIN_HEADERS"

# Test 2: List API Keys
test_api "List API keys" \
    "GET" \
    "$BASE_URL/admin/keys" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 3: List API Keys with admin key
test_api "List API keys (admin)" \
    "GET" \
    "$BASE_URL/admin/keys" \
    "" \
    200 \
    "$ADMIN_HEADERS"

echo ""
# ============================================================================
# Phase 2: Agent API Key Authentication
# ============================================================================
echo -e "${YELLOW}=== Phase 2: Agent API Key Authentication ===${NC}"

AGENT_HEADERS="-H 'X-API-Key: $API_KEY'"

# Test 4: Health check with agent key
test_api "Health check (agent key)" \
    "GET" \
    "$BASE_URL/health" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 5: Test invalid API key
test_api "Invalid API key should fail" \
    "GET" \
    "$BASE_URL/health" \
    "" \
    403 \
    "-H 'X-API-Key: invalid_key_12345'"

# Test 6: Test missing API key
test_api "Missing API key should fail" \
    "GET" \
    "$BASE_URL/memories" \
    "" \
    401 \
    ""

echo ""
# ============================================================================
# Phase 3: Memory Creation
# ============================================================================
echo -e "${YELLOW}=== Phase 3: Memory Creation ===${NC}"

# Test 7: Create memory (single message)
test_api "Create memory (single message)" \
    "POST" \
    "$BASE_URL/memories" \
    '{
        "messages": [{"role": "user", "content": "Hello, my name is John and I love programming in Python"}],
        "user_id": "user_001",
        "agent_id": "test_agent_001"
    }' \
    200 \
    "$AGENT_HEADERS"

# Test 8: Create memory (conversation)
test_api "Create memory (conversation)" \
    "POST" \
    "$BASE_URL/memories" \
    '{
        "messages": [
            {"role": "user", "content": "What do you know about me?"},
            {"role": "assistant", "content": "You are John and you love Python programming."}
        ],
        "user_id": "user_001",
        "agent_id": "test_agent_001"
    }' \
    200 \
    "$AGENT_HEADERS"

# Test 9: Create memory with metadata
test_api "Create memory with metadata" \
    "POST" \
    "$BASE_URL/memories" \
    '{
        "messages": [{"role": "user", "content": "I work as a software engineer at TechCorp"}],
        "user_id": "user_001",
        "agent_id": "test_agent_001",
        "metadata": {"source": "interview", "date": "2026-03-06"}
    }' \
    200 \
    "$AGENT_HEADERS"

# Test 10: Create memory without identifier should fail
test_api "Create memory without identifier should fail" \
    "POST" \
    "$BASE_URL/memories" \
    '{
        "messages": [{"role": "user", "content": "Test message"}]
    }' \
    400 \
    "$AGENT_HEADERS"

echo ""
# ============================================================================
# Phase 4: Memory Retrieval
# ============================================================================
echo -e "${YELLOW}=== Phase 4: Memory Retrieval ===${NC}"

# Test 11: Get all memories for user
test_api "Get all memories (user_id)" \
    "GET" \
    "$BASE_URL/memories?user_id=user_001" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 12: Get all memories for agent
test_api "Get all memories (agent_id)" \
    "GET" \
    "$BASE_URL/memories?agent_id=test_agent_001" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 13: Get all memories without identifier should fail
test_api "Get memories without identifier should fail" \
    "GET" \
    "$BASE_URL/memories" \
    "" \
    400 \
    "$AGENT_HEADERS"

echo ""
# ============================================================================
# Phase 5: Memory Search
# ============================================================================
echo -e "${YELLOW}=== Phase 5: Memory Search ===${NC}"

# Test 14: Search memories
test_api "Search memories (Python)" \
    "POST" \
    "$BASE_URL/search" \
    '{
        "query": "What does John like to do?",
        "user_id": "user_001",
        "agent_id": "test_agent_001",
        "limit": 5
    }' \
    200 \
    "$AGENT_HEADERS"

# Test 15: Search memories with filters
test_api "Search memories with filters" \
    "POST" \
    "$BASE_URL/search" \
    '{
        "query": "work",
        "user_id": "user_001",
        "filters": {"source": "interview"},
        "limit": 5
    }' \
    200 \
    "$AGENT_HEADERS"

# Test 16: Search memories with different agent
test_api "Search memories (different agent)" \
    "POST" \
    "$BASE_URL/search" \
    '{
        "query": "programming",
        "agent_id": "test_agent_002",
        "limit": 5
    }' \
    200 \
    "$AGENT_HEADERS"

echo ""
# ============================================================================
# Phase 6: Memory Update and Delete
# ============================================================================
echo -e "${YELLOW}=== Phase 6: Memory Update and Delete ===${NC}"

# First get a memory_id
MEMORY_RESULT=$(curl -s $BASE_URL/memories?user_id=user_001&agent_id=test_agent_001 -H "X-API-Key: $API_KEY")
MEMORY_ID=$(echo $MEMORY_RESULT | jq -r '.results[0].id // empty')

if [ -n "$MEMORY_ID" ] && [ "$MEMORY_ID" != "null" ]; then
    echo "  Found memory_id: $MEMORY_ID"

    # Test 17: Get specific memory
    test_api "Get specific memory" \
        "GET" \
        "$BASE_URL/memories/$MEMORY_ID?agent_id=test_agent_001" \
        "" \
        200 \
        "$AGENT_HEADERS"

    # Test 18: Get memory history
    test_api "Get memory history" \
        "GET" \
        "$BASE_URL/memories/$MEMORY_ID/history?agent_id=test_agent_001" \
        "" \
        200 \
        "$AGENT_HEADERS"

    # Test 19: Update memory
    test_api "Update memory" \
        "PUT" \
        "$BASE_URL/memories/$MEMORY_ID?agent_id=test_agent_001" \
        '{"memory": "John loves Python programming and is an expert in it."}' \
        200 \
        "$AGENT_HEADERS"

    # Test 20: Delete specific memory
    test_api "Delete specific memory" \
        "DELETE" \
        "$BASE_URL/memories/$MEMORY_ID?agent_id=test_agent_001" \
        "" \
        200 \
        "$AGENT_HEADERS"
else
    echo -e "${YELLOW}  Skipping individual memory tests (no memories found)${NC}"
fi

echo ""
# ============================================================================
# Phase 7: Delete All Memories
# ============================================================================
echo -e "${YELLOW}=== Phase 7: Delete All Memories ===${NC}"

# Test 21: Delete all memories for user
test_api "Delete all memories (user_id)" \
    "DELETE" \
    "$BASE_URL/memories?user_id=user_001" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 22: Delete all memories for agent
test_api "Delete all memories (agent_id)" \
    "DELETE" \
    "$BASE_URL/memories?agent_id=test_agent_001" \
    "" \
    200 \
    "$AGENT_HEADERS"

# Test 23: Delete all without identifier should fail
test_api "Delete all without identifier should fail" \
    "DELETE" \
    "$BASE_URL/memories" \
    "" \
    400 \
    "$AGENT_HEADERS"

echo ""
# ============================================================================
# Phase 8: Reset and Configuration
# ============================================================================
echo -e "${YELLOW}=== Phase 8: Reset and Configuration ===${NC}"

# Test 24: Configure endpoint
test_api "Configure endpoint" \
    "POST" \
    "$BASE_URL/configure" \
    '{"vector_store": {"provider": "pgvector"}}' \
    200 \
    "$AGENT_HEADERS"

# Test 25: Reset memory for agent
test_api "Reset memory for agent" \
    "POST" \
    "$BASE_URL/reset?agent_id=test_agent_001" \
    "" \
    200 \
    "$AGENT_HEADERS"

echo ""
# ============================================================================
# Phase 9: Rate Limiting Test
# ============================================================================
echo -e "${YELLOW}=== Phase 9: Rate Limiting Test ===${NC}"

# Test 26: Multiple rapid requests to test rate limiting
RATE_LIMIT_TESTS=10
RATE_LIMIT_PASSED=0
for i in $(seq 1 $RATE_LIMIT_TESTS); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health -H "X-API-Key: $API_KEY")
    if [ "$CODE" -eq 200 ]; then
        RATE_LIMIT_PASSED=$((RATE_LIMIT_PASSED + 1))
    fi
done
TOTAL=$((TOTAL + 1))
echo "  Rate limit test: $RATE_LIMIT_PASSED/$RATE_LIMIT_TESTS requests succeeded"
if [ "$RATE_LIMIT_PASSED" -eq "$RATE_LIMIT_TESTS" ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Rate limiting allows normal traffic"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ FAIL${NC} - Unexpected rate limiting"
    FAILED=$((FAILED + 1))
fi

echo ""
# ============================================================================
# Phase 10: Multi-Agent Isolation Test
# ============================================================================
echo -e "${YELLOW}=== Phase 10: Multi-Agent Isolation Test ===${NC}"

# Create memory for agent 1
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Agent 1: I am specialized in Python"}],
        "user_id": "user_001",
        "agent_id": "test_agent_001"
    }' > /dev/null

# Create memory for agent 2
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Agent 2: I am specialized in JavaScript"}],
        "user_id": "user_001",
        "agent_id": "test_agent_002"
    }' > /dev/null

# Check agent isolation
AGENT1_MEMORIES=$(curl -s "$BASE_URL/memories?agent_id=test_agent_001&user_id=user_001" -H "X-API-Key: $API_KEY" | jq '.results | length')
AGENT2_MEMORIES=$(curl -s "$BASE_URL/memories?agent_id=test_agent_002&user_id=user_001" -H "X-API-Key: $API_KEY" | jq '.results | length')

TOTAL=$((TOTAL + 1))
echo "  Agent 1 memories: $AGENT1_MEMORIES"
echo "  Agent 2 memories: $AGENT2_MEMORIES"

if [ "$AGENT1_MEMORIES" -gt 0 ] && [ "$AGENT2_MEMORIES" -gt 0 ]; then
    # Verify content is different
    AGENT1_CONTENT=$(curl -s "$BASE_URL/memories?agent_id=test_agent_001&user_id=user_001" -H "X-API-Key: $API_KEY" | jq -r '.results[0].memory')
    AGENT2_CONTENT=$(curl -s "$BASE_URL/memories?agent_id=test_agent_002&user_id=user_001" -H "X-API-Key: $API_KEY" | jq -r '.results[0].memory')

    if [[ "$AGENT1_CONTENT" != *"JavaScript"* ]]; then
        echo -e "  ${GREEN}✓ PASS${NC} - Agent isolation working correctly"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAIL${NC} - Agent isolation failed (found cross-agent data)"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "  ${RED}✗ FAIL${NC} - Agent isolation test failed (no memories found)"
    FAILED=$((FAILED + 1))
fi

echo ""
# ============================================================================
# Phase 11: Revoke API Key
# ============================================================================
echo -e "${YELLOW}=== Phase 11: Admin - Revoke API Key ===${NC}"

# Revoke the test key
test_api "Revoke API key" \
    "DELETE" \
    "$BASE_URL/admin/keys" \
    "{\"api_key\": \"$API_KEY\"}" \
    200 \
    "$ADMIN_HEADERS"

# Test revoked key no longer works
test_api "Revoked key should fail" \
    "GET" \
    "$BASE_URL/health" \
    "" \
    403 \
    "-H 'X-API-Key: $API_KEY'"

echo ""
# ============================================================================
# Test Summary
# ============================================================================
echo "=========================================="
echo -e "${YELLOW}Test Summary${NC}"
echo "=========================================="
echo -e "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
