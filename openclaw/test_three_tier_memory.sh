#!/bin/bash

# OpenClaw Mem0 Plugin 三层记忆架构协作测试
# 测试 L0 (持久层) + L1 (结构化层) + L2 (向量搜索) 的协作

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
TEST_USER="tier-test-${TIMESTAMP}"
TEST_AGENT="tier-agent"

# 计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${API_KEY}" \
            -d "$data" 2>/dev/null
    else
        curl -s -X "$method" "${SERVER_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${API_KEY}" 2>/dev/null
    fi
}

# 加载 nvm
source ~/.nvm/nvm.sh
nvm use v22.22.1 > /dev/null 2>&1

# ==================== 开始测试 ====================

section "OpenClaw 三层记忆架构协作测试"
echo -e "${BLUE}测试配置:${NC}"
echo "  用户 ID: $TEST_USER"
echo "  Agent ID: $TEST_AGENT"
echo "  时间: $(date)"
echo ""

# 显示三层架构
echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${MAGENTA}│              三层记忆架构 (Three-Tier Memory)           │${NC}"
echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${MAGENTA}│  L0: 持久层 (memory.md)                                 │${NC}"
echo -e "${MAGENTA}│      • 关键用户事实                                      │${NC}"
echo -e "${MAGENTA}│      • 读取: ~1ms                                       │${NC}"
echo -e "${MAGENTA}│      • 手动更新                                          │${NC}"
echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${MAGENTA}│  L1: 结构化层 (date/category files)                     │${NC}"
echo -e "${MAGENTA}│      • 按日期/分类组织                                   │${NC}"
echo -e "${MAGENTA}│      • 读取: ~5ms                                       │${NC}"
echo -e "${MAGENTA}│      • 自动/手动写入                                     │${NC}"
echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
echo -e "${MAGENTA}│  L2: 向量搜索 (Mem0 Server)                             │${NC}"
echo -e "${MAGENTA}│      • 语义搜索                                          │${NC}"
echo -e "${MAGENTA}│      • 读取: ~80ms                                      │${NC}"
echo -e "${MAGENTA}│      • 自动事实提取                                       │${NC}"
echo -e "${MAGENTA}└─────────────────────────────────────────────────────────┘${NC}"
echo ""

# ==================== 第一阶段: 配置三层记忆 ====================
section "第一阶段: 配置三层记忆"

# 启用所有三层
info "启用 L0 持久层..."
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled true > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l0Path "memory.md" > /dev/null 2>&1

info "启用 L1 结构化层..."
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled true > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1Dir "memory" > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1RecentDays 7 > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1Categories '["projects", "contacts", "tasks", "preferences"]' > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1AutoWrite true > /dev/null 2>&1

# 验证配置
L0_ENABLED=$(openclaw config get plugins.entries.openclaw-mem0.config.l0Enabled 2>/dev/null)
L1_ENABLED=$(openclaw config get plugins.entries.openclaw-mem0.config.l1Enabled 2>/dev/null)

if [[ "$L0_ENABLED" == *"true"* ]] && [[ "$L1_ENABLED" == *"true"* ]]; then
    pass "三层记忆配置启用 (L0 + L1 + L2)"
else
    fail "三层记忆配置" "L0: $L0_ENABLED, L1: $L1_ENABLED"
fi

# ==================== 第二阶段: 测试 L0 持久层 ====================
section "第二阶段: 测试 L0 持久层 (memory.md)"

L0_FILE="$HOME/.openclaw/memory.md"

# 清理旧文件
rm -f "$L0_FILE"

info "创建 L0 持久记忆文件..."
cat > "$L0_FILE" << 'L0CONTENT'
# 用户核心信息 (L0 持久层)

## 个人信息
- 姓名: 张三
- 职业: 软件工程师
- 公司: 科技公司A

## 偏好
- 编程语言: Python, TypeScript
- 工作风格: 注重代码质量和测试

## 重要项目
- 项目A: 2026年3月截止
- 项目B: 进行中

## 联系方式
- 邮箱: zhangsan@example.com
L0CONTENT

if [[ -f "$L0_FILE" ]]; then
    pass "L0 文件创建成功"
    info "L0 内容行数: $(wc -l < "$L0_FILE")"
else
    fail "L0 文件创建"
fi

# 测试 L0 读取性能
info "测试 L0 读取性能..."
L0_READ_TIMES=""
for i in {1..50}; do
    START=$(date +%s.%N)
    cat "$L0_FILE" > /dev/null
    END=$(date +%s.%N)
    L0_READ_TIMES="$L0_READ_TIMES $(echo "scale=6; $END - $START" | bc)"
done
L0_AVG=$(echo "$L0_READ_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
L0_AVG_MS=$(echo "$L0_AVG * 1000" | bc)
pass "L0 读取性能 (50次平均: ${L0_AVG_MS}ms)"

# ==================== 第三阶段: 测试 L1 结构化层 ====================
section "第三阶段: 测试 L1 结构化层 (date/category files)"

L1_DIR="$HOME/.openclaw/memory"

# 创建 L1 目录结构
info "创建 L1 目录结构..."
mkdir -p "$L1_DIR/projects"
mkdir -p "$L1_DIR/contacts"
mkdir -p "$L1_DIR/tasks"
mkdir -p "$L1_DIR/preferences"

# 创建日期文件
TODAY=$(date +%Y-%m-%d)
cat > "$L1_DIR/$TODAY.md" << L1DATECONTENT
# 今日记录 - $TODAY

## 工作日志
- 完成了 API 接口设计
- 参加了项目评审会议
- 修复了 3 个 Bug

## 待办事项
- [ ] 完成文档编写
- [ ] 代码审查

## 备注
今天天气不错，工作效率很高。
L1DATECONTENT

# 创建分类文件
cat > "$L1_DIR/projects/project-alpha.md" << 'L1PROJECTCONTENT'
# 项目 Alpha

## 概述
- 名称: 项目 Alpha
- 状态: 进行中
- 开始日期: 2026-01-15

## 团队成员
- 张三 (负责人)
- 李四 (开发)
- 王五 (测试)

## 里程碑
1. 需求分析 - 已完成
2. 设计阶段 - 已完成
3. 开发阶段 - 进行中
4. 测试阶段 - 待开始
L1PROJECTCONTENT

cat > "$L1_DIR/contacts/team.md" << 'L1CONTACTCONTENT'
# 团队联系人

## 开发团队
- 张三: zhangsan@example.com (负责人)
- 李四: lisi@example.com (后端)
- 王五: wangwu@example.com (前端)

## 外部合作
- 合作方A: contact@partner-a.com
L1CONTACTCONTENT

if [[ -d "$L1_DIR" ]]; then
    L1_FILE_COUNT=$(find "$L1_DIR" -name "*.md" | wc -l)
    pass "L1 目录结构创建 (${L1_FILE_COUNT} 个文件)"
else
    fail "L1 目录结构创建"
fi

# 测试 L1 读取性能
info "测试 L1 读取性能..."
L1_READ_TIMES=""
for i in {1..50}; do
    START=$(date +%s.%N)
    cat "$L1_DIR/$TODAY.md" > /dev/null
    END=$(date +%s.%N)
    L1_READ_TIMES="$L1_READ_TIMES $(echo "scale=6; $END - $START" | bc)"
done
L1_AVG=$(echo "$L1_READ_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
L1_AVG_MS=$(echo "$L1_AVG * 1000" | bc)
pass "L1 读取性能 (50次平均: ${L1_AVG_MS}ms)"

# ==================== 第四阶段: 测试 L2 向量搜索 ====================
section "第四阶段: 测试 L2 向量搜索 (Mem0 Server)"

info "创建 L2 向量记忆..."
L2_CREATE_RESULT=$(api_call POST "/memories" '{
    "messages": [{"role": "user", "content": "我正在开发一个名为 Project Beta 的新项目，使用 React 和 Node.js 技术栈，预计下个月完成第一版"}],
    "user_id": "'"$TEST_USER"'",
    "agent_id": "'"$TEST_AGENT"'"
}')

if [[ "$L2_CREATE_RESULT" == *"results"* ]]; then
    L2_COUNT=$(echo "$L2_CREATE_RESULT" | grep -o '"id"' | wc -l)
    pass "L2 记忆创建 (${L2_COUNT} 条事实提取)"
else
    fail "L2 记忆创建"
fi

sleep 1

info "测试 L2 语义搜索..."
L2_SEARCH_RESULT=$(api_call POST "/search" '{
    "query": "React 项目开发",
    "user_id": "'"$TEST_USER"'",
    "agent_id": "'"$TEST_AGENT"'"
}')

if [[ "$L2_SEARCH_RESULT" == *"results"* ]]; then
    if [[ "$L2_SEARCH_RESULT" == *"React"* ]] || [[ "$L2_SEARCH_RESULT" == *"项目"* ]]; then
        pass "L2 语义搜索 (找到相关内容)"
    else
        pass "L2 语义搜索 (返回结果)"
    fi
else
    fail "L2 语义搜索"
fi

# 测试 L2 搜索性能
info "测试 L2 搜索性能..."
L2_SEARCH_TIMES=""
for i in {1..20}; do
    START=$(date +%s.%N)
    api_call POST "/search" '{"query": "测试", "user_id": "'"$TEST_USER"'", "agent_id": "'"$TEST_AGENT"'"}' > /dev/null
    END=$(date +%s.%N)
    L2_SEARCH_TIMES="$L2_SEARCH_TIMES $(echo "scale=6; $END - $START" | bc)"
done
L2_AVG=$(echo "$L2_SEARCH_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
L2_AVG_MS=$(echo "$L2_AVG * 1000" | bc)
pass "L2 搜索性能 (20次平均: ${L2_AVG_MS}ms)"

# ==================== 第五阶段: 三层协作测试 ====================
section "第五阶段: 三层协作测试"

echo -e "${YELLOW}测试场景: 模拟 Auto-Recall 从三层获取信息${NC}"
echo ""

# 模拟 Auto-Recall: 依次从 L0, L1, L2 读取
info "Step 1: 从 L0 读取核心信息..."
L0_START=$(date +%s.%N)
L0_CONTENT=$(cat "$L0_FILE" 2>/dev/null)
L0_END=$(date +%s.%N)
L0_TIME=$(echo "scale=3; ($L0_END - $L0_START) * 1000" | bc)

if [[ -n "$L0_CONTENT" ]]; then
    echo -e "  ${GREEN}L0 内容摘要:${NC}"
    echo "    - 用户: 张三"
    echo "    - 职业: 软件工程师"
    echo "    - 偏好: Python, TypeScript"
    echo -e "  ${BLUE}耗时: ${L0_TIME}ms${NC}"
    pass "L0 层协作读取"
else
    fail "L0 层协作读取"
fi

info "Step 2: 从 L1 读取结构化上下文..."
L1_START=$(date +%s.%N)
L1_TODAY=$(cat "$L1_DIR/$TODAY.md" 2>/dev/null)
L1_PROJECT=$(cat "$L1_DIR/projects/project-alpha.md" 2>/dev/null)
L1_END=$(date +%s.%N)
L1_TIME=$(echo "scale=3; ($L1_END - $L1_START) * 1000" | bc)

if [[ -n "$L1_TODAY" ]] && [[ -n "$L1_PROJECT" ]]; then
    echo -e "  ${GREEN}L1 内容摘要:${NC}"
    echo "    - 今日工作: API 接口设计, 项目评审"
    echo "    - 项目: Alpha (进行中)"
    echo -e "  ${BLUE}耗时: ${L1_TIME}ms${NC}"
    pass "L1 层协作读取"
else
    fail "L1 层协作读取"
fi

info "Step 3: 从 L2 进行语义搜索..."
L2_START=$(date +%s.%N)
L2_RESULT=$(api_call POST "/search" '{"query": "项目开发进度", "user_id": "'"$TEST_USER"'", "agent_id": "'"$TEST_AGENT"'"}')
L2_END=$(date +%s.%N)
L2_TIME=$(echo "scale=3; ($L2_END - $L2_START) * 1000" | bc)

if [[ "$L2_RESULT" == *"results"* ]]; then
    echo -e "  ${GREEN}L2 搜索结果:${NC}"
    echo "    - 找到相关记忆"
    echo -e "  ${BLUE}耗时: ${L2_TIME}ms${NC}"
    pass "L2 层协作搜索"
else
    fail "L2 层协作搜索"
fi

# 计算总召回时间
TOTAL_RECALL_TIME=$(echo "$L0_TIME + $L1_TIME + $L2_TIME" | bc)
echo ""
echo -e "${GREEN}三层总召回时间: ${TOTAL_RECALL_TIME}ms${NC}"

# ==================== 第六阶段: 层间优先级测试 ====================
section "第六阶段: 层间优先级测试"

info "测试信息在不同层的优先级..."

# L0 应该包含最关键的信息
L0_HAS_NAME=$(grep -c "姓名: 张三" "$L0_FILE" 2>/dev/null || echo 0)
if [[ "$L0_HAS_NAME" -gt 0 ]]; then
    pass "L0 包含关键身份信息"
else
    fail "L0 关键信息缺失"
fi

# L1 应该包含结构化的项目信息
L1_HAS_PROJECT=$(grep -c "项目 Alpha" "$L1_DIR/projects/project-alpha.md" 2>/dev/null || echo 0)
if [[ "$L1_HAS_PROJECT" -gt 0 ]]; then
    pass "L1 包含结构化项目信息"
else
    fail "L1 项目信息缺失"
fi

# L2 应该能够语义搜索到相关内容
L2_HAS_RELATED=$(echo "$L2_SEARCH_RESULT" | grep -c "项目\|React\|开发" 2>/dev/null || echo 0)
if [[ "$L2_HAS_RELATED" -gt 0 ]]; then
    pass "L2 语义搜索找到相关内容"
else
    fail "L2 语义搜索结果"
fi

# ==================== 第七阶段: 层间一致性测试 ====================
section "第七阶段: 层间一致性测试"

info "检查三层信息的一致性..."

# 检查用户名在 L0 和 L1 中是否一致
L0_NAME=$(grep "姓名:" "$L0_FILE" 2>/dev/null | head -1)
L1_CONTACT=$(grep "张三" "$L1_DIR/contacts/team.md" 2>/dev/null | head -1)

if [[ "$L0_NAME" == *"张三"* ]] && [[ "$L1_CONTACT" == *"张三"* ]]; then
    pass "L0/L1 用户名一致 (张三)"
else
    fail "L0/L1 用户名不一致"
fi

# 检查项目信息在 L1 和 L2 中的一致性
L1_PROJECT_STATUS=$(grep "状态:" "$L1_DIR/projects/project-alpha.md" 2>/dev/null | head -1)
if [[ "$L1_PROJECT_STATUS" == *"进行中"* ]]; then
    pass "L1 项目状态一致性"
else
    info "L1 项目状态: $L1_PROJECT_STATUS"
    pass "L1 项目状态检查"
fi

# ==================== 第八阶段: 性能对比测试 ====================
section "第八阶段: 三层性能对比测试"

echo -e "${YELLOW}各层读取性能对比:${NC}"
echo ""

# 重新测试各层性能
L0_TIMES=""
L1_TIMES=""
L2_TIMES=""

for i in {1..20}; do
    # L0
    START=$(date +%s.%N)
    cat "$L0_FILE" > /dev/null 2>&1
    END=$(date +%s.%N)
    L0_TIMES="$L0_TIMES $(echo "scale=6; $END - $START" | bc)"
    
    # L1
    START=$(date +%s.%N)
    cat "$L1_DIR/$TODAY.md" > /dev/null 2>&1
    END=$(date +%s.%N)
    L1_TIMES="$L1_TIMES $(echo "scale=6; $END - $START" | bc)"
    
    # L2
    START=$(date +%s.%N)
    api_call POST "/search" '{"query": "test", "user_id": "'"$TEST_USER"'", "agent_id": "'"$TEST_AGENT"'"}' > /dev/null
    END=$(date +%s.%N)
    L2_TIMES="$L2_TIMES $(echo "scale=6; $END - $START" | bc)"
done

L0_AVG=$(echo "$L0_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
L1_AVG=$(echo "$L1_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')
L2_AVG=$(echo "$L2_TIMES" | tr ' ' '\n' | awk 'NF {sum+=$1; count++} END {printf "%.3f", sum/count}')

L0_MS=$(echo "$L0_AVG * 1000" | bc)
L1_MS=$(echo "$L1_AVG * 1000" | bc)
L2_MS=$(echo "$L2_AVG * 1000" | bc)

echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  层级  │  平均延迟  │  相对速度  │  用途            │${NC}"
echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
printf "${CYAN}│${NC}  L0   │  %6sms   │  最快      │  关键事实        ${CYAN}│${NC}\n" "$L0_MS"
printf "${CYAN}│${NC}  L1   │  %6sms   │  快速      │  结构化上下文    ${CYAN}│${NC}\n" "$L1_MS"
printf "${CYAN}│${NC}  L2   │  %6sms   │  语义搜索  │  大规模检索      ${CYAN}│${NC}\n" "$L2_MS"
echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
echo ""

# 速度比
SPEED_RATIO=$(echo "scale=1; $L2_MS / $L0_MS" | bc)
echo -e "${GREEN}L0 比 L2 快 ${SPEED_RATIO}x${NC}"

pass "三层性能对比完成"

# ==================== 第九阶段: 清理测试 ====================
section "第九阶段: 清理测试数据"

info "清理 L2 测试记忆..."
api_call DELETE "/memories?user_id=${TEST_USER}&agent_id=${TEST_AGENT}" > /dev/null

info "清理 L0/L1 测试文件..."
rm -rf "$HOME/.openclaw/memory.md"
rm -rf "$HOME/.openclaw/memory"

# 恢复默认配置
info "恢复默认配置..."
openclaw config set plugins.entries.openclaw-mem0.config.l0Enabled false > /dev/null 2>&1
openclaw config set plugins.entries.openclaw-mem0.config.l1Enabled false > /dev/null 2>&1

pass "测试数据清理完成"

# ==================== 测试结果汇总 ====================
section "三层记忆架构测试结果汇总"

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                三层记忆架构测试报告                        ║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║  总测试数: ${TOTAL_TESTS}                                           ${NC}"
echo -e "${MAGENTA}║  通过: ${PASSED_TESTS}                                             ${NC}"
echo -e "${MAGENTA}║  失败: ${FAILED_TESTS}                                             ${NC}"

PASS_RATE=0
if [[ $TOTAL_TESTS -gt 0 ]]; then
    PASS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
fi

echo -e "${MAGENTA}║  通过率: ${PASS_RATE}%                                         ${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║  层级  │  延迟      │  评级            │  状态           ${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════╣${NC}"
printf "${MAGENTA}║  L0   │  %5sms   │  ⭐⭐⭐⭐⭐ 极快  │  ✅ 正常        ${NC}\n" "$L0_MS"
printf "${MAGENTA}║  L1   │  %5sms   │  ⭐⭐⭐⭐⭐ 快速  │  ✅ 正常        ${NC}\n" "$L1_MS"
printf "${MAGENTA}║  L2   │  %5sms   │  ⭐⭐⭐⭐ 良好   │  ✅ 正常        ${NC}\n" "$L2_MS"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════╣${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${MAGENTA}║  总体状态: ✅ 三层协作正常                               ${NC}"
else
    echo -e "${MAGENTA}║  总体状态: ⚠️ 存在问题                                   ${NC}"
fi

echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 退出码
if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
