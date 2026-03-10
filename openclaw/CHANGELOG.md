# Changelog

All notable changes to the Mem0 OpenClaw Plugin.

## [2.2.1] - 2026-03-09

### Release Summary

Improve L1 file compression with intelligent core information summary extraction. Uses keyword-based and pattern-based matching to preserve important content.

### Changed

- **Smart Summary Extraction** - New `extractSummary()` method
  - Extract headers, tasks, and markers
  - Detect configuration and key information
  - Identify priorities and completion status
  - Limit to ~20 key items for efficiency

- **Cleaner Header Extraction** - New `extractHeader()` method
  - Skip leading empty lines
  - Preserve first 20 meaningful lines

- **Enhanced Shell Script** - Updated `compress_l1_files()` function
  - Multiple grep patterns for better coverage
  - Chinese and English keyword support
  - Pattern matching for configuration, keys, tasks, priorities

### Compression Algorithm

```
原始大文件
    │
    ├─> 提取头部 (20行，跳过空行)
    │
    ├─> 智能摘要 (使用多种模式)
    │   ├─ Headers: ^#{1,3} ...
    │   ├─ Tasks: [-*] [?] ... | TODO|FIXME
    │   ├─ Keys: 配置|设置|API|密钥|数据库...
    │   ├─ Rules: 规则|策略|依赖...
    │   ├─ Priorities: 重要|关键|核心|必须...
    │   └─ Status: 完成|done|已解决|结论...
    │
    └─> 最近更新 (50行)
```

### Before vs After

**Before (v2.2.0)**: Simple header (20 lines) + keywords (20 lines) + tail (30 lines)

**After (v2.2.1)**: Clean header + **intelligent summary** (20 key items) + tail (50 lines)

### Upgrade from 2.2.0

```bash
# Download and install
wget https://github.com/jxufesoft/mem0/releases/download/v2.2.1/mem0-openclaw-mem0-2.2.1.tgz
openclaw plugins install ./mem0-openclaw-mem0-2.2.1.tgz
```

---

## [2.2.0] - 2026-03-09

### Release Summary

Replace cron-based with trigger-based memory optimization for real-time automatic memory management. The `MemoryOptimizer` class now automatically optimizes L0/L1 memory when context exceeds threshold, without requiring scheduled jobs.

### Added

- **MemoryOptimizer Class** (`lib/setup.ts`) - TypeScript-based trigger optimization
  - `checkAndOptimize()` - Check and optimize if needed (with rate limiting)
  - `optimize()` - Force optimization regardless of threshold
  - `getContextSize()` - Get L0/L1/total size in bytes
  - `needsOptimization()` - Check if optimization is needed

- **Trigger-Based Optimization** - Automatic optimization on:
  1. `buildSystemPrompt` - Every conversation start
  2. `agent_end` - After L1 auto-write

- **Rate Limiting** - Minimum 1 minute between optimizations to prevent performance impact

- **Optimization Operations**:
  - `compressL1Files()` - Compress files > 50KB
  - `deduplicateL1Content()` - Remove duplicate lines
  - `archiveOldFiles()` - Archive files > 7 days old
  - `pruneL0File()` - Prune L0 to max 100 lines

### Changed

- **Removed Cron Dependency** - No longer uses scheduled jobs
- **runSetup() Return Type** - Simplified to `{ scriptPath: string }` (removed `crontabConfigured`)
- **Shell Script Role** - Now for manual use only, not automatic scheduling

### Performance

| Operation | Time | Notes |
|-----------|------|-------|
| getContextSize (600KB) | 1ms | File stat operations |
| optimize (600KB→5KB) | 14ms | Full optimization cycle |
| Compression Rate | 89-99% | Typical reduction |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Trigger-Based Optimization                  │
├─────────────────────────────────────────────────────────────┤
│  Trigger 1: buildSystemPrompt (conversation start)          │
│  Trigger 2: agent_end + L1 auto-write                       │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Check Size  │ →  │ Rate Limit  │ →  │  Optimize   │     │
│  │ (>100KB?)   │    │  (1 min)    │    │  if needed  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                             │
│  Operations: compress → dedup → archive → prune             │
└─────────────────────────────────────────────────────────────┘
```

### Test Results

| Test Suite | Tests | Status |
|------------|-------|--------|
| Functional Tests | 11 | ✅ PASS |
| Edge Case Tests | 4 | ✅ PASS |
| **Total** | **15** | ✅ **100%** |

### Upgrade from 2.1.2

```bash
# Remove old cron entry (no longer needed)
crontab -l | grep -v memory_manager.sh | crontab -

# Install new version
wget https://github.com/jxufesoft/mem0/releases/download/v2.2.0/mem0-openclaw-mem0-2.2.0.tgz
openclaw plugins install ./mem0-openclaw-mem0-2.2.0.tgz

# Restart gateway
openclaw gateway restart
```

### Manual Commands

Shell script still available for manual use:

```bash
# Check context status
bash ~/.openclaw/scripts/memory_manager.sh context

# Force optimization
bash ~/.openclaw/scripts/memory_manager.sh optimize

# Individual operations
bash ~/.openclaw/scripts/memory_manager.sh compress
bash ~/.openclaw/scripts/memory_manager.sh dedup
bash ~/.openclaw/scripts/memory_manager.sh archive
bash ~/.openclaw/scripts/memory_manager.sh prune
```

---

## [2.1.2] - 2026-03-09

### Release Summary

Automatic setup for memory_manager.sh script on new installations.

### Added

- **Auto-Setup Module** (`lib/setup.ts`) - Creates memory_manager.sh automatically on first load
- **Crontab Auto-Configuration** - Sets up daily 3AM cleanup job
- **First-Time Optimization** - Runs initial memory optimization after setup

### How It Works

When plugin is installed on a new machine:

```
Plugin Load → Check ~/.openclaw/scripts/memory_manager.sh
                ↓ (not exists)
            Create script with server config
            Add crontab entry (3:00 AM daily)
            Run initial optimization
                ↓
            Setup Complete ✅
```

### Files Changed

- `lib/setup.ts` - New auto-setup module
- `index.ts` - Import and call runSetup() on server mode

### Manual Commands

After installation, you can also run manually:

```bash
# Run memory optimization now
bash ~/.openclaw/scripts/memory_manager.sh

# Check crontab
crontab -l | grep memory

# View logs
tail -f ~/.openclaw/logs/memory_manager.log
```

### Upgrade from 2.1.1

```bash
# Download and install
wget https://github.com/jxufesoft/mem0/releases/download/v2.1.2/mem0-openclaw-mem0-2.1.2.tgz
openclaw plugins install ./mem0-openclaw-mem0-2.1.2.tgz

# Restart gateway
openclaw gateway restart
```

---

## [2.1.0] - 2026-03-09

### Release Summary

Hash-based memory deduplication feature to prevent storing duplicate memories. Includes new API endpoints and automatic deduplication on memory add.

### Added

- **Hash-based Deduplication** - Automatic duplicate detection using MD5 hash
- **`GET /deduplicate`** - View duplicate memory statistics
- **`POST /deduplicate`** - Clean up duplicates (with dry-run support)
- **Auto-Dedup on Add** - Automatic duplicate prevention when adding memories

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Dual-Layer Protection                 │
├─────────────────────────────────────────────────────────┤
│  Layer 1: LLM Semantic Deduplication (existing)         │
│           Detects semantically similar memories          │
│                                                          │
│  Layer 2: Hash Exact Matching (NEW)                     │
│           MD5 hash comparison for exact duplicates       │
└─────────────────────────────────────────────────────────┘
```

### Fixed

- **Duplicate Memory Issue** - Fixed "喜欢编程" being stored multiple times
- **Search Quality** - Improved by removing duplicate results

### Test Results

| Test | Status |
|------|--------|
| Duplicate Detection | ✅ PASS |
| Auto-Dedup on Add | ✅ PASS |
| Manual Cleanup | ✅ PASS |
| Dry-Run Mode | ✅ PASS |
| L2 Recall | ✅ PASS |
| Telegram Integration | ✅ PASS |

### Upgrade from 2.0.3

```bash
# Download and install
wget https://github.com/jxufesoft/mem0/releases/download/v2.1.0/mem0-openclaw-mem0-2.1.0.tgz
openclaw plugins install ./mem0-openclaw-mem0-2.1.0.tgz

# Or from source
cd openclaw && npm pack
openclaw plugins install ./mem0-openclaw-mem0-2.1.0.tgz
```

---

## [2.0.3] - 2026-03-08

### Release Summary

Minor documentation update to align API authentication format with server implementation.

### Changed

- **API Authentication Format** - Updated README.md curl examples from `X-API-Key` header to `Authorization: Bearer` format
- **agent_id Parameter** - Added documentation for required `agent_id` query parameter on GET/PUT/DELETE `/memories/{id}` endpoints
- **Server README** - Added complete curl examples for all 13 API endpoints with proper authentication

### Documentation Updates

- `server/README.md` - Updated authentication format and added parameter requirements
- API endpoint documentation now correctly shows Bearer token authentication

### Test Results

All 13 API tests passed (100%):
- Health check, API key management (create/list/revoke)
- Memory CRUD operations (create/read/update/delete)
- Search, history, batch operations
- Authentication validation

### Upgrade from 2.0.0

No code changes required. Simply reinstall the plugin:

```bash
openclaw plugins install mem0-openclaw-mem0-2.0.1.tgz
```

---

## [2.0.0] - 2026-03-07

### Release Summary

Mem0 Plugin v2.0.0 is a complete rewrite with three-tier memory architecture, server mode support, and comprehensive testing. All 23 tests passed with 100% pass rate and excellent performance ratings.

### Deployment Updates (2026-03-07 14:00)
- **Data Directory** - Changed from `/opt/mem0-data` to `/home/yhz/mem0-data`
- **External Access** - Server binds to `0.0.0.0:8000` for LAN/external access
- **PostgreSQL Connection** - Changed from hardcoded IP to container name (`mem0-postgres`)
- **Container Cleanup** - Removed duplicate `mem0-api` container (port 8888)
- **Documentation** - Updated all docs with new deployment configuration

### Critical Fix (2026-03-07 04:30)
- **Server Mode Implementation** - Added full ServerProvider class to index.ts
- **L0/L1 Integration** - Integrated L0Manager and L1Manager into main plugin
- **Configuration Support** - Added serverUrl, serverApiKey, agentId, and all L0/L1 config keys
- **Auto-Recall Enhancement** - Now includes L0/L1 content alongside L2 vector search
- **Auto-Capture Enhancement** - L1 auto-write when enabled

### Test Results (2026-03-07)

**功能测试**: 23/23 通过 (100%)

| 阶段 | 测试数 | 状态 |
|------|--------|------|
| 基础健康检查 | 2 | ✅ |
| CRUD 功能测试 | 6 | ✅ |
| 批量操作测试 | 2 | ✅ |
| 性能测试 | 4 | ✅ |
| 多 Agent 隔离测试 | 2 | ✅ |
| 错误处理测试 | 3 | ✅ |
| L0/L1 记忆层测试 | 3 | ✅ |
| 清理测试数据 | 1 | ✅ |

**性能测试结果**:

| 操作 | 平均延迟 | P95 | 吞吐量 |
|------|---------|-----|--------|
| 健康检查 | 15ms | 18ms | 69 req/s |
| 搜索记忆 | 82ms | 101ms | 10 req/s |
| 获取全部 | 20ms | 43ms | 33 req/s |
| 创建记忆(含LLM) | 5.5s | 5.8s | 0.18 req/s |
| 更新记忆 | 16ms | 22ms | 43 req/s |
| 获取历史 | 14ms | 18ms | 52 req/s |
| 并发(50) | 137ms | - | 365 req/s |

**总体评级**: ⭐⭐⭐⭐⭐ 优秀 (100分)

### Added

- **Three-Tier Memory Architecture** - L0 (memory.md) + L1 (date/category files) + L2 (vector search)
- **L0Manager** - Fast persistent memory layer for critical user facts
- **L1Manager** - Structured context layer with date and category files
- **Server Mode Support** - New provider for Enhanced Mem0 Server
- **Multi-Agent Isolation** - Per-agent memory collection isolation
- **Automatic Retry** - ServerClient with 3-retry exponential backoff
- **OpenClaw Systemd Service** - Native systemd integration for auto-start
- **Comprehensive Test Suite** - 23 tests with 100% pass rate
- **Performance Benchmark** - Detailed latency and throughput metrics

### Changed

- **Plugin Version** - Upgraded from 0.1.2 to 2.0.0
- **Provider Architecture** - Unified interface for Platform, OSS, and Server providers
- **API Compatibility** - Fixed PlatformProvider API calls to use camelCase (organizationId, projectId)
- **Configuration Schema** - Extended with server mode and L0/L1 options

### Fixed

- **PlatformProvider API Call** - Fixed snake_case to camelCase for organizationId and projectId
- **L1Manager Missing Method** - Added isAutoWriteEnabled() method
- **TypeScript Types** - Fixed type definitions and ClientOptions compatibility
- **Server Mode Support** - Added full ServerProvider implementation
- **Memory ID Extraction** - Fixed regex for proper ID capture in tests

### Performance

| Metric | Value | Rating |
|--------|-------|--------|
| Health Check | 15ms | ⭐⭐⭐⭐⭐ |
| Database Query | 20ms | ⭐⭐⭐⭐⭐ |
| Vector Search | 82ms | ⭐⭐⭐⭐⭐ |
| Concurrent Throughput | 365 req/s | ⭐⭐⭐⭐⭐ |
| Memory Update | 16ms | ⭐⭐⭐⭐⭐ |

### Documentation

- Updated README.md - Added performance section and systemd setup
- Updated BEGINNER_GUIDE.md - Complete beginner tutorial
- Updated INSTALLATION_GUIDE.md - Server mode configuration
- Updated DEPLOYMENT_GUIDE.md - Production deployment with systemd
- Updated TEST_REPORT.md - Latest test results
- Updated docs/ARCHITECTURE.md - Three-tier architecture details
- Updated docs/DEPLOYMENT.md - Systemd service setup

---

## [0.1.2] - Previous Release

### Features
- Platform mode support
- Open-source mode support
- Auto-recall and auto-capture hooks
- 7 agent tools

---

## Upgrade Guide

### From 0.1.2 to 2.0.0

1. Update plugin configuration to include new `server` mode option
2. Add L0/L1 settings if desired (`l0Enabled`, `l1Enabled`, etc.)
3. Update `openclaw.plugin.json` with new configuration schema
4. Run tests to verify installation:
   ```bash
   bash test_plugin_comprehensive.sh
   ```

### Configuration Changes

**Old Configuration (0.1.2)**:
```json5
{
  "mode": "platform",
  "apiKey": "${MEM0_API_KEY}",
  "userId": "default"
}
```

**New Configuration (2.0.0)**:
```json5
{
  "mode": "server",
  "serverUrl": "http://localhost:8000",
  "serverApiKey": "${MEM0_SERVER_API_KEY}",
  "agentId": "openclaw-main",
  "userId": "default",
  "l0Enabled": true,
  "l1Enabled": true,
  "l1AutoWrite": true
}
```

---

## Support

For support and issues:
- GitHub: https://github.com/mem0ai/mem0/issues
- Docs: https://docs.mem0.ai
- Community: https://discord.gg/mem0

---

## [2.1.2] - 2026-03-09

### Release Summary

Automatic setup for memory_manager.sh script on new installations.

### Added

- **Auto-Setup Module** (`lib/setup.ts`) - Creates memory_manager.sh automatically on first load
- **Crontab Auto-Configuration** - Sets up daily 3AM cleanup job
- **First-Time Optimization** - Runs initial memory optimization after setup

### How It Works

When plugin is installed on a new machine:

```
Plugin Load → Check ~/.openclaw/scripts/memory_manager.sh
                ↓ (not exists)
            Create script with server config
            Add crontab entry (3:00 AM daily)
            Run initial optimization
                ↓
            Setup Complete ✅
```

### Files Changed

- `lib/setup.ts` - New auto-setup module
- `index.ts` - Import and call runSetup() on server mode

### Manual Commands

After installation, you can also run manually:

```bash
# Run memory optimization now
bash ~/.openclaw/scripts/memory_manager.sh

# Check crontab
crontab -l | grep memory

# View logs
tail -f ~/.openclaw/logs/memory_manager.log
```

### Upgrade from 2.1.1

```bash
# Download and install
wget https://github.com/jxufesoft/mem0/releases/download/v2.1.2/mem0-openclaw-mem0-2.1.2.tgz
openclaw plugins install ./mem0-openclaw-mem0-2.1.2.tgz

# Restart gateway
openclaw gateway restart
```

---
