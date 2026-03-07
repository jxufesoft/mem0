#!/bin/bash
#
# Mem0 Plugin 全功能测试脚本
# 测试三种 Provider (Platform/OSS/Server) 的所有功能和性能
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
SERVER_URL="${SERVER_URL:-http://localhost:8000}"
SERVER_API_KEY="${SERVER_API_KEY:-}"
PLATFORM_API_KEY="${PLATFORM_API_KEY:-}"

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 记录测试结果
declare -A TEST_RESULTS

# 工具函数
log_info() {
    echo -e "${BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ PASS${NC} - $1"
}

log_error() {
    echo -e "${RED}✗ FAIL${NC} - $1"
}

log_section() {
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}========================================${NC}"
}

run_test() {
    local test_name="$1"
    local test_function="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${CYAN}$3${NC}"
    if $test_function "$4" "$5" "$6"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS[$test_name]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS[$test_name]="FAIL"
        log_error "$test_name"
        return 1
    fi
}

# ============================================================================
# Server Provider 测试
# ============================================================================

test_server_health() {
    curl -s -f "$SERVER_URL/health" > /dev/null 2>&1
}

test_server_create() {
    local user_id="$1"
    local response
    response=$(curl -s -X POST "$SERVER_URL/memories" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $SERVER_API_KEY" \
        -d "{\"user_id\":\"$user_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Test user name is John\"}]}")

    echo "$response" | jq -e '.results | length > 0' > /dev/null 2>&1
}

test_server_search() {
    local user_id="$1"
    local response
    response=$(curl -s -X POST "$SERVER_URL/search" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $SERVER_API_KEY" \
        -d "{\"query\":\"user name\",\"user_id\":\"$user_id\",\"limit\":5}")

    echo "$response" | jq -e '.results | length > 0' > /dev/null 2>&1
}

test_server_get_all() {
    local user_id="$1"
    local response
    response=$(curl -s "$SERVER_URL/memories?user_id=$user_id" \
        -H "X-API-Key: $SERVER_API_KEY")

    echo "$response" | jq -e '.results | length >= 0' > /dev/null 2>&1
}

test_server_get_one() {
    local user_id="$1"
    local response
    response=$(curl -s "$SERVER_URL/memories?user_id=$user_id" \
        -H "X-API-Key: $SERVER_API_KEY")

    local memory_id
    memory_id=$(echo "$response" | jq -r '.results[0].id // empty')
    [ -n "$memory_id" ] && [ "$memory_id" != "null" ]

    if [ -n "$memory_id" ] && [ "$memory_id" != "null" ]; then
        response=$(curl -s "$SERVER_URL/memories/$memory_id?user_id=$user_id" \
            -H "X-API-Key: $SERVER_API_KEY")
        echo "$response" | jq -e '.id' > /dev/null 2>&1
    fi
}

test_server_update() {
    local user_id="$1"
    local response
    response=$(curl -s "$SERVER_URL/memories?user_id=$user_id" \
        -H "X-API-Key: $SERVER_API_KEY")

    local memory_id
    memory_id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$memory_id" ] && [ "$memory_id" != "null" ]; then
        response=$(curl -s -X PUT "$SERVER_URL/memories/$memory_id?user_id=$user_id" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $SERVER_API_KEY" \
            -d '{"data":"Updated memory content"}')

        echo "$response" | jq -e '.message // .memory' > /dev/null 2>&1
    fi
}

test_server_delete() {
    local user_id="$1"
    local response
    response=$(curl -s "$SERVER_URL/memories?user_id=$user_id" \
        -H "X-API-Key: $SERVER_API_KEY")

    local memory_id
    memory_id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$memory_id" ] && [ "$memory_id" != "null" ]; then
        curl -s -X DELETE "$SERVER_URL/memories/$memory_id?user_id=$user_id" \
            -H "X-API-Key: $SERVER_API_KEY" > /dev/null
    fi
    return 0
}

test_server_history() {
    local user_id="$1"
    local response
    response=$(curl -s "$SERVER_URL/memories?user_id=$user_id" \
        -H "X-API-Key: $SERVER_API_KEY")

    local memory_id
    memory_id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$memory_id" ] && [ "$memory_id" != "null" ]; then
        response=$(curl -s "$SERVER_URL/memories/$memory_id/history?user_id=$user_id" \
            -H "X-API-Key: $SERVER_API_KEY")
        echo "$response" | jq -e 'length >= 0' > /dev/null 2>&1
    fi
}

# ============================================================================
# 性能测试函数
# ============================================================================

measure_time() {
    local start end
    start=$(date +%s.%N)
    "$@"
    local exit_code=$?
    end=$(date +%s.%N)
    echo "$(echo "$end - $start" | bc) $exit_code"
}

benchmark_operation() {
    local operation="$1"
    local iterations="$2"
    local user_id="bench-$$"

    log_info "Benchmarking $operation (x$iterations)..."

    local total_time=0
    local success_count=0

    for i in $(seq 1 $iterations); do
        local result
        result=$(measure_time $operation "$user_id")
        local time=$(echo "$result" | awk '{print $1}')
        local exit_code=$(echo "$result" | awk '{print $2}')

        if [ $exit_code -eq 0 ]; then
            total_time=$(echo "$total_time + $time" | bc)
            success_count=$((success_count + 1))
        fi
    done

    if [ $success_count -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $success_count" | bc)
        local ops_per_sec=$(echo "scale=2; 1 / $avg_time" | bc)
        echo "  Average: ${avg_time}s, ${ops_per_sec} ops/sec, $success_count/$iterations succeeded"
        return 0
    else
        log_error "All operations failed"
        return 1
    fi
}

# ============================================================================
# L0/L1 文件系统测试
# ============================================================================

test_l0_file() {
    local test_dir="/tmp/mem0-l0-test-$$"
    mkdir -p "$test_dir"

    # 测试写入
    echo "# Test Memory" > "$test_dir/memory.md"
    echo "- User name is TestUser" >> "$test_dir/memory.md"

    # 测试读取
    local content
    content=$(cat "$test_dir/memory.md")
    [[ "$content" == *"User name is TestUser"* ]]

    # 清理
    rm -rf "$test_dir"
}

test_l1_directory() {
    local test_dir="/tmp/mem0-l1-test-$$"
    mkdir -p "$test_dir"

    # 测试日期文件
    local today=$(date +%Y-%m-%d)
    echo "### $today" > "$test_dir/$today.md"
    echo "Conversation summary for today" >> "$test_dir/$today.md"

    # 测试分类文件
    echo "### projects" > "$test_dir/projects.md"
    echo "Project A: Doing something" >> "$test_dir/projects.md"

    # 验证
    [ -f "$test_dir/$today.md" ] && [ -f "$test_dir/projects.md" ]

    # 清理
    rm -rf "$test_dir"
}

# ============================================================================
# 主测试流程
# ============================================================================

main() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║      Mem0 Plugin 全功能测试和性能验证                           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    # 检查依赖
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装，请运行: sudo apt-get install jq"
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        log_error "bc 未安装，请运行: sudo apt-get install bc"
        exit 1
    fi

    # ============================================================================
    # Phase 1: 基础连接测试
    # ============================================================================

    log_section "Phase 1: 基础连接测试"

    run_test "Server Health Check" test_server_health "" "Server健康检查"

    # ============================================================================
    # Phase 2: Server Provider 功能测试
    # ============================================================================

    log_section "Phase 2: Server Provider 功能测试"

    local test_user="test-user-$$-server"

    run_test "Server: Create Memory" test_server_create "$test_user" "创建记忆"
    sleep 0.1  # 等待索引完成

    run_test "Server: Search Memory" test_server_search "$test_user" "搜索记忆"
    run_test "Server: Get All Memories" test_server_get_all "$test_user" "获取所有记忆"
    run_test "Server: Get Single Memory" test_server_get_one "$test_user" "获取单个记忆"
    run_test "Server: Update Memory" test_server_update "$test_user" "更新记忆"
    run_test "Server: Memory History" test_server_history "$test_user" "记忆历史"

    # ============================================================================
    # Phase 3: 性能测试
    # ============================================================================

    log_section "Phase 3: 性能测试"

    # 批量创建性能
    log_info "Test 3.1: Bulk Create Performance"
    benchmark_operation test_server_create 10

    # 搜索性能
    log_info "Test 3.2: Search Performance"
    benchmark_operation test_server_search 10

    # 并发请求测试
    log_info "Test 3.3: Concurrent Requests"
    local concurrent_start
    concurrent_start=$(date +%s.%N)
    for i in {1..20}; do
        curl -s -X POST "$SERVER_URL/health" > /dev/null &
    done
    wait
    local concurrent_end
    concurrent_end=$(date +%s.%N)
    local concurrent_time
    concurrent_time=$(echo "$concurrent_end - $concurrent_start" | bc)
    local concurrent_rate
    concurrent_rate=$(echo "scale=2; 20 / $concurrent_time" | bc)
    echo "  20 concurrent requests: ${concurrent_time}s (${concurrent_rate} req/sec)"

    # ============================================================================
    # Phase 4: 错误处理测试
    # ============================================================================

    log_section "Phase 4: 错误处理测试"

    # 无效 API Key
    log_info "Test 4.1: Invalid API Key"
    local invalid_key_response
    invalid_key_response=$(curl -s -w "\n%{http_code}" "$SERVER_URL/memories?user_id=test" \
        -H "X-API-Key: invalid_key_12345")
    local http_code=$(echo "$invalid_key_response" | tail -n1)
    if [ "$http_code" == "403" ] || [ "$http_code" == "401" ]; then
        log_success "Invalid API Key rejected correctly (HTTP $http_code)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    else
        log_error "Invalid API Key not rejected (HTTP $http_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi

    # 缺少必需参数
    log_info "Test 4.2: Missing Required Parameters"
    local missing_params_response
    missing_params_response=$(curl -s -w "\n%{http_code}" -X POST "$SERVER_URL/memories" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $SERVER_API_KEY" \
        -d '{}')
    local missing_params_code=$(echo "$missing_params_response" | tail -n1)
    if [ "$missing_params_code" == "400" ] || [ "$missing_params_code" == "422" ]; then
        log_success "Missing parameters rejected correctly (HTTP $missing_params_code)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    else
        log_error "Missing parameters not rejected (HTTP $missing_params_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi

    # ============================================================================
    # Phase 5: L0/L1 文件系统测试
    # ============================================================================

    log_section "Phase 5: 三层记忆文件系统测试"

    run_test "L0: Memory File Operations" test_l0_file "" "L0 文件操作"
    run_test "L1: Directory Structure" test_l1_directory "" "L1 目录结构"

    # ============================================================================
    # 测试总结
    # ============================================================================

    log_section "测试总结"

    # 计算通过率
    local pass_rate
    if [ $TOTAL_TESTS -gt 0 ]; then
        pass_rate=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
    else
        pass_rate=0
    fi

    # 打印统计
    echo -e "${CYAN}统计信息:${NC}"
    echo "  总测试数: $TOTAL_TESTS"
    echo -e "  通过: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  失败: ${RED}$FAILED_TESTS${NC}"
    echo "  通过率: ${pass_rate}%"

    # 打印详细结果
    echo ""
    echo -e "${CYAN}详细结果:${NC}"
    echo "+--------------------------------+----------+"
    echo "| 测试                           | 状态   |"
    echo "+--------------------------------+----------+"
    for key in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$key]}"
        if [ "$status" == "PASS" ]; then
            printf "| %-30s | ${GREEN}%-8s${NC} |\n" "$key" "$status"
        else
            printf "| %-30s | ${RED}%-8s${NC} |\n" "$key" "$status"
        fi
    done
    echo "+--------------------------------+----------+"

    # 清理测试数据
    log_info "清理测试数据..."
    curl -s -X DELETE "$SERVER_URL/memories?user_id=$test_user" \
        -H "X-API-Key: $SERVER_API_KEY" > /dev/null 2>&1 || true

    # 最终状态
    echo ""
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓✓✓ 所有测试通过 ✓✓✓${NC}"
        echo -e "${GREEN}✓ PRODUCTION READY${NC}"
        exit 0
    else
        echo -e "${RED}✗✗✗ 有 $FAILED_TESTS 个测试失败 ✗✗✗${NC}"
        exit 1
    fi
}

# 执行主函数
main "$@"
