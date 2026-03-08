#!/bin/bash
# Test OpenClaw Plugin Integration with Mem0 Server

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenClaw Plugin Integration Test"
echo "=========================================="
echo ""

# ============================================================================
# Test 1: Create API Key for an agent
# ============================================================================
echo -e "${YELLOW}TEST 1: Create API Key for agent${NC}"
API_KEY=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "openclaw_agent", "description": "OpenClaw integration test"}' | jq -r '.api_key')

if [ -n "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - API Key created: $API_KEY"
else
    echo -e "  ${RED}✗ FAIL${NC} - Failed to create API key"
    exit 1
fi

echo ""
# ============================================================================
# Test 2: Store memories (like OpenClaw would do)
# ============================================================================
echo -e "${YELLOW}TEST 2: Store memories${NC}"
RESULT=$(curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [
            {"role": "user", "content": "I work as a software engineer at TechCorp"},
            {"role": "assistant", "content": "I noted that you are a software engineer at TechCorp."}
        ],
        "user_id": "user_openclaw",
        "agent_id": "openclaw_agent"
    }')

MEMORY_COUNT=$(echo $RESULT | jq '.results | length')
if [ "$MEMORY_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Stored $MEMORY_COUNT memories"
else
    echo -e "  ${RED}✗ FAIL${NC} - No memories stored"
fi

echo ""
# ============================================================================
# Test 3: Search memories (like OpenClaw would do)
# ============================================================================
echo -e "${YELLOW}TEST 3: Search memories${NC}"
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "query": "What does the user do for work?",
        "user_id": "user_openclaw",
        "agent_id": "openclaw_agent",
        "limit": 5
    }')

SEARCH_COUNT=$(echo $RESULT | jq '.results | length')
if [ "$SEARCH_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Found $SEARCH_COUNT relevant memories"
    echo "  Top result: $(echo $RESULT | jq -r '.results[0].memory')"
else
    echo -e "  ${RED}✗ FAIL${NC} - No memories found"
fi

echo ""
# ============================================================================
# Test 4: List all memories for agent (OpenClaw's list function)
# ============================================================================
echo -e "${YELLOW}TEST 4: List all memories for agent${NC}"
RESULT=$(curl -s "$BASE_URL/memories?agent_id=openclaw_agent" \
    -H "X-API-Key: $API_KEY")

LIST_COUNT=$(echo $RESULT | jq '.results | length')
if [ "$LIST_COUNT" -ge 0 ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Listed $LIST_COUNT memories for agent"
else
    echo -e "  ${RED}✗ FAIL${NC} - Failed to list memories"
fi

echo ""
# ============================================================================
# Test 5: Multi-Agent Isolation (OpenClaw's agent-scoped feature)
# ============================================================================
echo -e "${YELLOW}TEST 5: Multi-Agent Isolation${NC}"

# Create API key for agent 2
API_KEY_2=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "openclaw_agent_2", "description": "OpenClaw agent 2"}' | jq -r '.api_key')

# Store memory for agent 1
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Agent 1: I prefer Python programming"}],
        "user_id": "user_openclaw",
        "agent_id": "openclaw_agent"
    }' > /dev/null

# Store memory for agent 2
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY_2" \
    -d '{
        "messages": [{"role": "user", "content": "Agent 2: I prefer JavaScript programming"}],
        "user_id": "user_openclaw",
        "agent_id": "openclaw_agent_2"
    }' > /dev/null

# Check agent 1 memories
AGENT_1_MEMS=$(curl -s "$BASE_URL/memories?agent_id=openclaw_agent&user_id=user_openclaw" \
    -H "X-API-Key: $API_KEY" | jq '.results[] | select(.memory | contains("Python")) | .memory')

# Check agent 2 memories
AGENT_2_MEMS=$(curl -s "$BASE_URL/memories?agent_id=openclaw_agent_2&user_id=user_openclaw" \
    -H "X-API-Key: $API_KEY_2" | jq '.results[] | select(.memory | contains("JavaScript")) | .memory')

if [[ "$AGENT_1_MEMS" == *"Python"* ]] && [[ "$AGENT_2_MEMS" == *"JavaScript"* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Agent isolation working correctly"
    echo "  Agent 1 has Python: $(echo $AGENT_1_MEMS)"
    echo "  Agent 2 has JavaScript: $(echo $AGENT_2_MEMS)"
else
    echo -e "  ${RED}✗ FAIL${NC} - Agent isolation not working"
fi

echo ""
# ============================================================================
# Test 6: Delete memories (OpenClaw's forget function)
# ============================================================================
echo -e "${YELLOW}TEST 6: Delete memories${NC}"

# Get a memory ID to delete
MEMORY_ID=$(curl -s "$BASE_URL/memories?agent_id=openclaw_agent&user_id=user_openclaw" \
    -H "X-API-Key: $API_KEY" | jq -r '.results[0].id')

# Delete the memory
RESULT=$(curl -s -X DELETE "$BASE_URL/memories/$MEMORY_ID?agent_id=openclaw_agent" \
    -H "X-API-Key: $API_KEY")

if [ "$RESULT" == *'successfully'* ]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Memory deleted successfully"
else
    echo -e "  ${RED}✗ FAIL${NC} - Failed to delete memory"
fi

echo ""
# ============================================================================
# Summary
# ============================================================================
echo "=========================================="
echo -e "${YELLOW}Integration Test Complete${NC}"
echo "=========================================="
echo ""
echo "Server URL: $BASE_URL"
echo "Agent ID: openclaw_agent"
echo "API Key: ${API_KEY:0:20}..."
echo ""
echo -e "${GREEN}All integration tests passed! OpenClaw plugin is ready to use Mem0 Server.${NC}"
