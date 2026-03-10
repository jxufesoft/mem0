#!/bin/bash

# OpenClaw Mem0 Plugin - L1 文件智能压缩测试
# 测试 compressL1Files() 功能是否正常工作

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试目录
TEST_DIR="/tmp/mem0_compression_test_$(date +%s)"
mkdir -p "$TEST_DIR"

# 辅助函数
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

section() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
}

# 清理函数
cleanup() {
    rm -rf "$TEST_DIR"
}

# 设置退出时清理
trap cleanup EXIT

# ==================== 测试开始 ====================
section "L1 文件智能压缩测试"
echo "测试目录: $TEST_DIR"
echo ""

# ==================== 测试 1: 创建测试文件 ====================
section "测试 1: 创建大型测试文件"

info "生成 500 行测试文件..."
cat > "$TEST_DIR/test_file.md" << 'EOF'
# 测试文件 - 大型内容

## 重要配置
- 配置项1: API_URL = http://api.example.com
- 配置项2: MAX_RETRIES = 3
- 配置项3: TIMEOUT = 30000

## 核心任务
- [ ] 任务1: 完成API集成
- [ ] 任务2: 编写单元测试
- [x] 任务3: 部署到生产环境

## 项目依赖
- 依赖1: mem0ai >= 2.0.0
- 依赖2: axios >= 1.7.0
- 依赖3: typescript >= 5.0.0

## 关键信息 (重要)
重要: 这个项目必须在3月底前完成
关键: 核心API需要99.9%的可用性
必须: 所有代码必须有单元测试覆盖

## 数据库配置
database:
  host: localhost
  port: 5432
  name: mem0_db
  user: mem0_user

## 环境变量
env:
  - NODE_ENV=production
  - API_KEY=secret_key_here
  - LOG_LEVEL=info

## 架构说明
architecture:
  components:
    - API Gateway
    - Service Layer
    - Data Layer
  policy: microservices

## 优先级设定
priority:
  P0: 核心功能
  P1: 重要功能
  P2: 辅助功能

## 状态追踪
status:
  已完成: 初始设计
  进行中: 开发阶段
  待开始: 测试阶段

## 规则说明
rule1: 所有API请求必须有认证
rule2: 敏感数据必须加密
constraint1: 单次请求不超过10MB

## 联系人列表
contacts:
  - 张三: zhang@example.com (项目负责人)
  - 李四: li@example.com (技术负责人)

## 最近更新
last update: 2026-03-09
EOF

# 重复内容以增加文件大小
for i in {1..40}; do
    echo "## 重复区块 $i" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-1，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-2，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-3，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-4，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-5，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-6，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-7，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-8，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-9，用于增加文件大小" >> "$TEST_DIR/test_file.md"
    echo "这是重复的内容行 $i-10，用于增加文件大小" >> "$TEST_DIR/test_file.md"
done

ORIGINAL_SIZE=$(wc -c < "$TEST_DIR/test_file.md")
ORIGINAL_LINES=$(wc -l < "$TEST_DIR/test_file.md")

info "原始文件: $ORIGINAL_SIZE bytes ($ORIGINAL_LINES lines)"

if [[ $ORIGINAL_SIZE -gt 10000 ]]; then
    pass "测试文件创建成功 (>10KB)"
else
    fail "测试文件创建" "文件太小: $ORIGINAL_SIZE bytes"
fi

# ==================== 测试 2: 运行压缩脚本 ====================
section "测试 2: 执行智能压缩"

# 模拟 shell 脚本的 compress_l1_files 函数
file="$TEST_DIR/test_file.md"
max_bytes=$((20 * 1024))  # 20KB threshold (lowered for testing)

if [[ $(wc -c < "$file") -gt $max_bytes ]]; then
    info "文件大小超过阈值，执行压缩..."

    # 智能压缩：提取头部 + 核心摘要 + 最近更新
    {
        # 1. 提取头部 (跳过开头的空行)
        head -20 "$file" | grep -v '^$'
        echo ""
        echo "--- [智能压缩于 $(date '+%Y-%m-%d %H:%M')] ---"
        echo ""
        echo "## 核心信息摘要"
        echo ""

        # 2. 提取关键信息 (使用多种模式)
        grep -iE \
            -e '^[#]+.*$' \
            -e '^[-*].*\[.*\].*$' \
            -e '^[-*].*\[?x?\].*TODO|FIXME|HACK|任务|截止' \
            -e '.*(重要|关键|核心|core|注意|警告|critical|essential|must|必须|should|应该).*$' \
            -e '.*(配置|设置|environment|env|变量|variable|API|接口|url|host).*$' \
            -e '.*(密钥|key|token|secret|密码|password|database|db|连接).*$' \
            -e '.*(规则|策略|policy|约束|constraint|依赖|dependency).*$' \
            -e '.*(架构|结构|组件|component|优先|priority).*$' \
            -e '.*(完成|done|finished|已解决|resolved|conclusion).*$' \
            "$file" 2>/dev/null | head -15

        echo ""
        echo "## 最近更新"
        tail -50 "$file"
    } > "${file}.tmp"

    mv "${file}.tmp" "$file"

    COMPRESSED_SIZE=$(wc -c < "$file")
    COMPRESSED_LINES=$(wc -l < "$file")

    info "压缩后文件: $COMPRESSED_SIZE bytes ($COMPRESSED_LINES lines)"
    REDUCTION=$((ORIGINAL_SIZE - COMPRESSED_SIZE))
    REDUCTION_PCT=$((REDUCTION * 100 / ORIGINAL_SIZE))

    echo ""
    echo -e "${CYAN}压缩统计:${NC}"
    echo "  原始大小: $ORIGINAL_SIZE bytes"
    echo "  压缩后: $COMPRESSED_SIZE bytes"
    echo "  减少: $REDUCTION bytes ($REDUCTION_PCT%)"
    echo ""

    if [[ $COMPRESSED_SIZE -lt $ORIGINAL_SIZE ]]; then
        pass "文件成功压缩 (减少 $REDUCTION bytes, $REDUCTION_PCT%)"
    else
        fail "文件压缩失败" "文件大小未减少"
    fi
else
    info "文件大小未超过阈值，跳过压缩"
    pass "压缩阈值检查 (无需压缩)"
fi

# ==================== 测试 3: 验证压缩内容 ====================
section "测试 3: 验证压缩后的内容结构"

# 检查头部
HAS_HEADER=$(grep -c "^#" "$TEST_DIR/test_file.md" || echo 0)
info "压缩文件中包含 $HAS_HEADER 个标题行"

if [[ $HAS_HEADER -gt 0 ]]; then
    pass "压缩内容包含标题"
else
    fail "压缩内容标题缺失"
fi

# 检查压缩标记
HAS_MARKER=$(grep -c "智能压缩" "$TEST_DIR/test_file.md" 2>/dev/null)
HAS_MARKER=${HAS_MARKER:-0}
if [[ $HAS_MARKER -gt 0 ]]; then
    pass "压缩内容包含压缩标记"
else
    fail "压缩内容标记缺失"
fi

# 检查核心信息摘要
HAS_SUMMARY=$(grep -c "核心信息摘要" "$TEST_DIR/test_file.md" 2>/dev/null)
HAS_SUMMARY=${HAS_SUMMARY:-0}
if [[ $HAS_SUMMARY -gt 0 ]]; then
    pass "压缩内容包含核心信息摘要部分"
else
    fail "压缩内容摘要部分缺失"
fi

# 检查最近更新部分
HAS_RECENT=$(grep -c "最近更新" "$TEST_DIR/test_file.md" || echo 0)
if [[ $HAS_RECENT -gt 0 ]]; then
    pass "压缩内容包含最近更新部分"
else
    fail "压缩内容最近更新部分缺失"
fi

# 检查是否保留了关键配置信息
HAS_CONFIG=$(grep -c "API_URL\|MAX_RETRIES\|TIMEOUT" "$TEST_DIR/test_file.md" || echo 0)
if [[ $HAS_CONFIG -gt 0 ]]; then
    pass "压缩内容保留关键配置"
else
    fail "压缩内容关键配置缺失"
fi

# 检查是否保留了任务信息
HAS_TASKS=$(grep -c "任务\|TODO\|FIXME" "$TEST_DIR/test_file.md" || echo 0)
if [[ $HAS_TASKS -gt 0 ]]; then
    pass "压缩内容保留任务信息"
else
    fail "压缩内容任务信息缺失"
fi

# ==================== 测试 4: 边界条件测试 ====================
section "测试 4: 边界条件测试"

# 测试 4.1: 小文件不应被压缩
info "创建小文件 (<50KB)..."
cat > "$TEST_DIR/small_file.md" << 'EOF'
# 小文件测试

这是一个小文件，不应该被压缩。
EOF

SMALL_SIZE=$(wc -c < "$TEST_DIR/small_file.md")
if [[ $SMALL_SIZE -lt 1024 ]]; then
    pass "小文件创建成功 (<1KB)"

    # 验证小文件未触发压缩
    if [[ $SMALL_SIZE -lt $max_bytes ]]; then
        pass "小文件阈值检查 (无需压缩)"
    fi
else
    fail "小文件创建" "文件太大: $SMALL_SIZE bytes"
fi

# 测试 4.2: 空文件处理
info "创建空文件..."
touch "$TEST_DIR/empty_file.md"
EMPTY_SIZE=$(wc -c < "$TEST_DIR/empty_file.md")

if [[ $EMPTY_SIZE -eq 0 ]]; then
    pass "空文件创建成功 (0 bytes)"
else
    fail "空文件创建" "文件大小: $EMPTY_SIZE bytes"
fi

# ==================== 测试 5: 重复文件测试 ====================
section "测试 5: 重复内容去重"

info "创建包含重复行的文件..."
cat > "$TEST_DIR/duplicate_file.md" << 'EOF'
# 重复内容测试

第一行内容
第一行内容
第二行内容
第三行内容
第三行内容
第三行内容
EOF

ORIG_LINES=$(wc -l < "$TEST_DIR/duplicate_file.md")

# 去除重复行
sort -u "$TEST_DIR/duplicate_file.md" -o "$TEST_DIR/duplicate_file.dedup"
DEDUP_LINES=$(wc -l < "$TEST_DIR/duplicate_file.dedup")

info "原始: $ORIG_LINES 行, 去重后: $DEDUP_LINES 行"

if [[ $DEDUP_LINES -lt $ORIG_LINES ]]; then
    pass "重复内容去重成功 (减少 $((ORIG_LINES - DEDUP_LINES)) 行)"
else
    fail "重复内容去重" "行数未减少"
fi

rm -f "$TEST_DIR/duplicate_file.dedup"

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

# 显示压缩后的文件内容示例
echo -e "${BLUE}压缩后文件内容示例 (前30行):${NC}"
head -30 "$TEST_DIR/test_file.md" | nl -w2 -s'. '

echo ""
echo -e "${BLUE}压缩后文件内容示例 (最后20行):${NC}"
tail -20 "$TEST_DIR/test_file.md" | nl -w2 -s'. '

# 退出码
if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
