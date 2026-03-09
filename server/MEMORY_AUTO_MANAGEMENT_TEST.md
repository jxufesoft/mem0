# 记忆自动管理系统测试报告

**测试日期**: 2026-03-09
**Plugin 版本**: 2.1.0
**Server 版本**: 2.1.0

---

## 测试概述

测试 OpenClaw Plugin 中的三层记忆自动管理系统，- 自动优化
- 自动归档
- 自动清理
- Context 自动优化

---

## 优化结果

### 优化前后对比

| 指标 | 优化前 | 优化后 | 变化 |
|------|--------|--------|------|
| L0 行数 | 155 | 72 | -53% |
| L0 大小 | 4KB | 1KB | -75% |
| L1 文件数 | 42 | 14 | -67% |
| L1 大小 | 268KB | 5KB | -98% |
| L2 记忆数 | 95 | 95 | 0% |
| **Context 总计** | ~280KB | **~21KB** | **-93%** |

---

## 记忆层级结构

```
┌─────────────────────────────────────────────────────────┐
│                    三层记忆系统                           │
├─────────────────────────────────────────────────────────┤
│  L0: memory.md (~1KB)                                   │
│      - 核心用户信息                                       │
│      - 偏好设置                                          │
│      - 工作区信息                                         │
│      - 自动精简 (>100行触发)                              │
├─────────────────────────────────────────────────────────┤
│  L1: memory/ (~5KB)                                     │
│      - 日期文件 (最近7天)                                 │
│      - 分类文件 (projects, contacts, tasks, preferences) │
│      - 自动归档 (>14天文件)                               │
│      - 自动清理 (测试文件)                                │
├─────────────────────────────────────────────────────────┤
│  L2: pgvector (~13KB)                                   │
│      - 语义搜索 (topK=10)                                 │
│      - Hash 去重                                          │
│      - 阈值过滤 (0.2)                                      │
└─────────────────────────────────────────────────────────┘
```

---

## 自动管理功能

### 1. L0 自动精简

**触发条件**: 行数 > 100
**操作**: 保留头部20行 + 最近50行
**实现**: `l0-manager.ts` - `prune()`

```typescript
async prune(maxLines: number = 100) {
  const header = lines[:20];
  const recent = lines[-(maxLines - 25):];
  // 合并并保存
}
```

### 2. L1 自动归档

**触发条件**: 文件 > 14天 或 测试文件
**操作**: 移动到 archive/YYYY-MM/ 目录
**实现**: `l1-manager.ts` - `archiveOldFiles()`

```bash
# 归档目录结构
memory/archive/
├── 2026-03/
│   ├── test-performance.md
│   ├── plugin-test.md
│   └── 2026-02-20.md
```

### 3. L1 自动清理

**触发条件**: 匹配测试文件模式
**操作**: 删除测试文件
**实现**: `l1-manager.ts` - `cleanup()`

```typescript
// 清理模式
const testPatterns = /test|stress|batch|encoding|structure|comprehensive/i;
```

### 4. L2 自动去重

**触发条件**: 每次添加记忆时
**操作**: Hash 检查，**实现**: `server/main.py` - `add_memory()`

```python
# 在 add 端点中
new_hash = compute_memory_hash(new_memory_content)
if existing := check_memory_exists_by_hash(new_hash):
    delete(new_memory)
    return NOOP
```

---

## Context 大小控制

### 加载策略

| 层级 | 加载策略 | 最大大小 |
|------|----------|----------|
| L0 | 全部加载 | 4KB |
| L1 | 最近7天 + 配置分类 | 5KB |
| L2 | topK=10 + 阈值0.2 | 2KB |
| **总计** | | **~11KB** |

### 配置项

```json
{
  "topK": 10,
  "searchThreshold": 0.2,
  "l1RecentDays": 7,
  "l1Categories": ["projects", "contacts", "tasks", "preferences"]
}
```

---

## 定时任务

```bash
# crontab -l
0 3 * * * ~/.openclaw/scripts/memory_manager.sh

# 每天凌晨3点执行:
# - L0 精简
# - L1 归档
# - L2 去重
# - Context 优化
```

---

## 手动操作

### 运行记忆管理脚本

```bash
~/.openclaw/scripts/memory_manager.sh
```

### Server API

```bash
# 查看统计
curl http://localhost:8000/memory/stats \
  -H "Authorization: Bearer $API_KEY"

# 手动优化 (dry-run)
curl -X POST "http://localhost:8000/memory/optimize?dry_run=true" \
  -H "Authorization: Bearer $API_KEY"

# 执行优化
curl -X POST "http://localhost:8000/memory/optimize?dry_run=false" \
  -H "Authorization: Bearer $API_KEY"
```

---

## 测试结果

| 测试项 | 状态 | 说明 |
|-------|------|------|
| L0 精简 | ✅ | 155行 → 72行 |
| L1 归档 | ✅ | 28个测试文件已归档 |
| L1 清理 | ✅ | 测试文件已删除 |
| L2 去重 | ✅ | 0 重复记忆 |
| Context 优化 | ✅ | 280KB → 21KB |
| 定时任务 | ✅ | 已配置 |
| Server API | ✅ | /memory/stats, /memory/optimize |

**总体状态**: ✅ **记忆自动管理系统正常工作**

---

## 建议

1. **监控**: 定期检查 Context 大小
2. **告警**: Context > 50KB 时发送通知
3. **优化**: 考虑实现 L0 增量更新而非重写
4. **扩展**: 支持自定义归档规则

