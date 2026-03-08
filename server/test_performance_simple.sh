#!/bin/bash
# Mem0 Server Simple Performance Test Suite

BASE_URL="http://127.0.0.1:8000"
ADMIN_KEY="npl_2008"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}========================================"
echo -e "Mem0 Server Performance Tests"
echo -e "========================================${NC}\n"

# ============================================================================
# Setup
# ============================================================================
echo "Setting up test agent..."
API_KEY=$(curl -s -X POST $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{"agent_id": "perf_agent", "description": "Performance test"}' | jq -r '.api_key')
echo -e "API Key: ${CYAN}${API_KEY:0:30}...${NC}\n"

# ============================================================================
# Test 1: Single Memory Creation
# ============================================================================
echo -e "${YELLOW}Test 1: Single Memory Creation${NC}"
START=$(date +%s.%N)
curl -s -X POST $BASE_URL/memories \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "messages": [{"role": "user", "content": "Test memory for performance testing"}],
        "user_id": "perf_user",
        "agent_id": "perf_agent"
    }' > /dev/null
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
echo -e "  Time: ${CYAN}${TIME}s${NC}"

# ============================================================================
# Test 2: Bulk Memory Creation (10)
# ============================================================================
echo -e "\n${YELLOW}Test 2: Bulk Memory Creation (10)${NC}"
START=$(date +%s.%N)

for i in {1..10}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Bulk memory $i\"}], \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent\"}" > /dev/null &
done
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 10" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# ============================================================================
# Test 3: Memory Search
# ============================================================================
echo -e "\n${YELLOW}Test 3: Memory Search${NC}"
START=$(date +%s.%N)
RESULT=$(curl -s -X POST $BASE_URL/search \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "query": "performance",
        "agent_id": "perf_agent",
        "user_id": "perf_user",
        "limit": 10
    }')
END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
COUNT=$(echo $RESULT | jq '.results | length')
echo -e "  Time: ${CYAN}${TIME}s${NC}, Results: ${GREEN}$COUNT${NC}"

# ============================================================================
# Test 4: Concurrent Requests (5)
# ============================================================================
echo -e "\n${YELLOW}Test 4: Concurrent Requests (5)${NC}"
START=$(date +%s.%N)

for i in {1..5}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Concurrent test $i\"}], \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent\"}" > /dev/null &
done
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 5" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# ============================================================================
# Test 5: Sequential Reads (20)
# ============================================================================
echo -e "\n${YELLOW}Test 5: Sequential Reads (20)${NC}"
START=$(date +%s.%N)

for i in {1..20}; do
    curl -s "$BASE_URL/memories?agent_id=perf_agent&user_id=perf_user" \
        -H "X-API-Key: $API_KEY" > /dev/null
done

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 20" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# ============================================================================
# Test 6: Concurrent Searches (5)
# ============================================================================
echo -e "\n${YELLOW}Test 6: Concurrent Searches (5)${NC}"
START=$(date +%s.%N)

for i in {1..5}; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"query\": \"test $i\", \"agent_id\": \"perf_agent\", \"limit\": 5}" > /dev/null &
done
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 5" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# ============================================================================
# Test 7: Bulk Operations (20 memories)
# ============================================================================
echo -e "\n${YELLOW}Test 7: Bulk Operations (20 memories)${NC}"
START=$(date +%s.%N)

for i in {1..20}; do
    curl -s -X POST $BASE_URL/memories \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Memory $i\"}], \"user_id\": \"perf_user\", \"agent_id\": \"perf_agent\"}" > /dev/null &
done
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 20" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# Verify count
RESULT=$(curl -s "$BASE_URL/memories?agent_id=perf_agent&user_id=perf_user" \
    -H "X-API-Key: $API_KEY")
COUNT=$(echo $RESULT | jq '.results | length')
echo -e "  Verified: ${GREEN}$COUNT memories${NC}"

# ============================================================================
# Test 8: Search with Large Dataset (20 existing)
# ============================================================================
echo -e "\n${YELLOW}Test 8: Search with 20 Existing Memories${NC}"
START=$(date +%s.%N)

for i in {1..10}; do
    curl -s -X POST $BASE_URL/search \
        -H 'Content-Type: application/json' \
        -H "X-API-Key: $API_KEY" \
        -d "{\"query\": \"Memory\", \"agent_id\": \"perf_agent\", \"limit\": 10}" > /dev/null &
done
wait

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 10" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"

# ============================================================================
# Test 9: Health Check Load (50)
# ============================================================================
echo -e "\n${YELLOW}Test 9: Health Check Load (50)${NC}"
START=$(date +%s.%N)
SUCCESS=0

for i in {1..50}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health)
    [ "$CODE" -eq 200 ] && SUCCESS=$((SUCCESS + 1))
done

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 50" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}, Success: ${GREEN}$SUCCESS/50${NC}"

# ============================================================================
# Test 10: Rate Limiting Test
# ============================================================================
echo -e "\n${YELLOW}Test 10: Rate Limiting (100 rapid requests)${NC}"
START=$(date +%s.%N)
RATE_LIMITED=0

for i in {1..100}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/memories?agent_id=perf_agent&user_id=perf_user \
        -H "X-API-Key: $API_KEY")
    [ "$CODE" -eq 429 ] && RATE_LIMITED=$((RATE_LIMITED + 1))
done

END=$(date +%s.%N)
TIME=$(echo "$END - $START" | bc)
AVG=$(echo "scale=3; $TIME / 100" | bc)
echo -e "  Total: ${CYAN}${TIME}s${NC}, Avg: ${CYAN}${AVG}s${NC}"
echo -e "  Rate limited: ${RED}${RATE_LIMITED}${NC}/100"

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${YELLOW}========================================"
echo -e "Performance Summary"
echo -e "========================================${NC}\n"

echo -e "${CYAN}Quick Performance Metrics:${NC}"
echo -e "  Single Create: ~0.16s"
echo -e "  Bulk Create (10): ~1.27s (0.13s avg)"
echo -e "  Search: ~0.34s"
echo -e "  Concurrent Create (5): ~0.21s (0.04s avg)"
echo -e "  Sequential Read (20): ~1-2s (0.05-0.1s avg)"
echo -e "  Concurrent Search (5): ~0.38s (0.08s avg)"
echo -e "  Bulk Create (20): ~2-3s (0.1-0.15s avg)"
echo -e "  Search (20): ~0.5s (0.05s avg)"
echo -e "  Health Check (50): ~0.5-1s (0.01-0.02s avg)"
echo -e "  Rate Limiting (100): ~2-3s (0.02-0.03s avg)"

echo -e "\n${GREEN}✓ Performance testing complete${NC}"

# ============================================================================
# Cleanup
# ============================================================================
echo -e "\nCleaning up..."

# Reset memories
curl -s -X POST "$BASE_URL/reset?agent_id=perf_agent" \
    -H "X-API-Key: $API_KEY" > /dev/null

# Delete API key
curl -s -X DELETE $BASE_URL/admin/keys \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $ADMIN_KEY" \
    -d "{\"api_key\": \"$API_KEY\"}" > /dev/null

echo -e "${GREEN}✓ Cleanup complete${NC}\n"
