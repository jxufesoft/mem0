# OpenClaw × Mem0 三层分层记忆生产级完整方案 - Implementation Summary

## Overview

This implementation provides a complete three-tier memory architecture for OpenClaw with production-grade Mem0 server support.

## What Was Implemented

### Module 1: Server-Side Enhancements

#### 1. Enhanced Server (`server/main.py`)

**Key Features:**
- **Asyncio Architecture**: Full async support for 10+ concurrent agent operations
- **Multi-Agent Instance Pool**: `_instances` dictionary with double-checked locking pattern
- **API Key Authentication**: `X-API-Key` header verification with admin secret key support
- **Redis Rate Limiting**: Sliding window rate limiting (configurable requests/window)
- **Per-Agent Collection Isolation**: Each agent gets its own collection in PostgreSQL
- **Health Check Endpoint**: `/health` endpoint for monitoring

**New Endpoints:**
- `GET /health` - Server health and status
- `POST /admin/keys` - Create new API key
- `GET /admin/keys` - List all API keys
- `DELETE /admin/keys` - Revoke an API key

**New Environment Variables:**
```
REDIS_URL              - Redis connection string
ADMIN_SECRET_KEY       - Secret for admin operations
RATE_LIMIT_REQUESTS    - Max requests per window (default: 200)
RATE_LIMIT_WINDOW       - Time window in seconds (default: 60)
OPENAI_BASE_URL        - Custom LLM endpoint (optional)
OPENAI_MODEL           - Custom model name (optional)
OPENAI_EMBEDDING_MODEL - Custom embedding model (optional)
```

#### 2. Server Dependencies (`server/requirements.txt`)

Added:
- `uvloop==0.21.0` - High-performance event loop
- `httptools==0.6.4` - Fast HTTP parsing
- `redis[asyncio]==5.2.1` - Async Redis client with rate limiting support

#### 3. Production Dockerfile (`server/Dockerfile`)

- Based on `python:3.11-slim-bookworm`
- Multi-worker support (4 workers)
- Healthcheck integrated
- Optimized with uvloop and httptools

#### 4. PostgreSQL Init Script (`server/postgres-init/01-init.sql`)

- Creates `vector` extension
- Creates `uuid-ossp` extension
- Grants permissions to mem0user

#### 5. Production Docker Compose (`server/docker-compose.prod.yaml`)

**Services:**
- `mem0-postgres` - PostgreSQL with pgvector
- `mem0-neo4j` - Neo4j for graph memory
- `mem0-redis` - Redis for rate limiting
- `mem0-server` - Enhanced FastAPI server

**Key Features:**
- All data mounted to `/opt/mem0-data/` on host
- Health checks for all services
- Proper service dependencies
- SELinux-compatible (`:z` flag)

#### 6. Server Environment Template (`server/.env`)

Complete template with all required configuration options.

---

### Module 2: Plugin-Side Enhancements

#### 1. Server Client (`openclaw/lib/server-client.ts`)

HTTP client for Mem0 Enhanced Server with:
- Custom server URL and API key support
- Automatic retry with exponential backoff
- Full CRUD operations
- `forgetByQuery` method

**Methods:**
- `add()` - Store memories
- `search()` - Search memories
- `list()` - List all memories
- `get()` - Get specific memory
- `forget()` - Delete by ID
- `forgetByQuery()` - Delete by query
- `health()` - Check server health

#### 2. L0 Manager (`openclaw/lib/l0-manager.ts`)

Manages the `memory.md` file for fastest access to critical user facts.

**Methods:**
- `readAll()` - Read complete memory.md content
- `readBlock()` - Read as structured block with timestamp
- `append()` - Append new fact
- `overwrite()` - Replace entire content
- `toSystemBlock()` - Format for system prompt injection
- `extractFacts()` - Extract bullet-point facts

#### 3. L1 Manager (`openclaw/lib/l1-manager.ts`)

Manages date and category files for structured context.

**File Structure:**
```
memory/
├── 2026-03-05.md    # Daily conversation summary
├── projects.md       # Project-related information
├── contacts.md       # Contact information
└── tasks.md          # Tasks and TODOs
```

**Methods:**
- `readContext()` - Read recent date files + all category files
- `appendToday()` - Append to today's date file
- `appendToCategory()` - Append to specific category file
- `analyzeCapture()` - Analyze conversation for L1 writing
- `toSystemBlock()` - Format for system prompt injection
- `writeFromConversation()` - Auto-write based on conversation

#### 4. Enhanced Plugin (`openclaw/index.ts`)

**New Mode:**
- `"server"` - Connects to enhanced Mem0 Server

**New Configuration Options:**
```typescript
{
  // Server mode
  serverUrl: string;      // Required for server mode
  serverApiKey: string;    // Required for server mode
  agentId: string;        // Agent ID for collection isolation

  // L0 settings
  l0Enabled: boolean;
  l0Path: string;        // Default: "memory.md"

  // L1 settings
  l1Enabled: boolean;
  l1Dir: string;         // Default: "memory"
  l1RecentDays: number;  // Default: 7
  l1Categories: string[]; // Default: ["projects", "contacts", "tasks"]
  l1AutoWrite: boolean;  // Auto-write to L1
}
```

**New Tools:**
1. `memory_l0_update` - Update L0 memory.md file
   - Parameters: `action` ("append" | "overwrite"), `content`

2. `memory_l1_write` - Write to L1 files
   - Parameters: `target` ("today" | "projects" | "contacts" | "tasks" | "custom"), `content`, `customCategory`

**Enhanced Auto-Recall:**
- L0: Reads memory.md if enabled
- L1: Reads date/category files if enabled
- L2: Searches vector store (always)

**Enhanced Auto-Capture:**
- L2: Stores to vector store (always)
- L1: Auto-writes to date/category files if `l1AutoWrite` enabled

#### 5. Updated Dependencies (`openclaw/package.json`)

Added:
- `axios@^1.7.9` - HTTP client
- `axios-retry@^4.5.0` - Automatic retry logic

#### 6. Updated Metadata (`openclaw/openclaw.plugin.json`)

Added UI hints and schema for:
- Server mode configuration
- L0/L1 settings
- All new options

---

## Deployment Guide

### Server Deployment

```bash
# 1. Create data directories
sudo mkdir -p /opt/mem0-data/{postgres,neo4j/data,neo4j/logs,neo4j/import,redis,history}
sudo chown -R 1000:1000 /opt/mem0-data/

# Optional: Set SELinux context (Rocky Linux 10)
sudo chcon -Rt svirt_sandbox_file_t /opt/mem0-data/

# 2. Configure environment
cd /home/yhz/project/mem0/server
cp .env .env.local
# Edit .env.local with your settings

# 3. Deploy
docker compose -f docker-compose.prod.yaml up -d

# 4. Check health
curl http://localhost:8000/health

# 5. Create API key
MEM0_KEY=$(curl -s -X POST http://localhost:8000/admin/keys \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $(grep ADMIN_SECRET_KEY .env.local | cut -d= -f2)" \
  -d '{"agent_id":"openclaw-main","description":"OpenClaw主Agent"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['api_key'])")

echo "Your API Key: $MEM0_KEY"
```

### Plugin Configuration

```json
{
  "openclaw-mem0": {
    "enabled": true,
    "config": {
      "mode": "server",
      "serverUrl": "http://localhost:8000",
      "serverApiKey": "${MEM0_SERVER_API_KEY}",
      "agentId": "openclaw-main",
      "userId": "your-user-id",
      "l0Enabled": true,
      "l0Path": "memory.md",
      "l1Enabled": true,
      "l1Dir": "memory",
      "l1RecentDays": 7,
      "l1Categories": ["projects", "contacts", "tasks"],
      "l1AutoWrite": true,
      "autoRecall": true,
      "autoCapture": true
    }
  }
}
```

---

## Testing Guide

### Server Testing

```bash
# Health check
curl http://localhost:8000/health

# Create memory
curl -X POST http://localhost:8000/memories \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $MEM0_KEY" \
  -d '{
    "messages":[{"role":"user","content":"我叫 yuhao"}],
    "agent_id":"openclaw-main",
    "user_id":"yuhao"
  }'

# Search memory
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $MEM0_KEY" \
  -d '{"query":"用户名字","agent_id":"openclaw-main","user_id":"yuhao","limit":5}'
```

### Plugin Testing

```bash
# Install plugin
openclaw plugins install /path/to/openclaw-mem0

# L0 test
echo "用户姓名: yuhao" > ~/.openclaw/workspace/memory.md
# Check system prompt injection

# L1 test
mkdir -p ~/.openclaw/workspace/memory
echo "# 2026-03-05\n\n今日对话摘要..." > ~/.openclaw/workspace/memory/2026-03-05.md
# Check system prompt injection

# L2 test
# Use memory_search, memory_store tools in conversation
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        OpenClaw Agent                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   L0 Layer   │  │   L1 Layer   │  │   L2 Layer   │       │
│  │  memory.md   │  │  memory/     │  │  Mem0 Server │       │
│  │  (Fastest)   │  │  (Fast)      │  │  (Semantic)  │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         │                 │                  │                 │
│         ▼                 ▼                  ▼                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           System Prompt Injection (autoRecall)            │ │
│  └──────────────────────────────────────────────────────────┘ │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                  Agent Conversation                      │ │
│  └──────────────────────────────────────────────────────────┘ │
│                              │                              │
│                              ▼                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │          Memory Storage (autoCapture)                     │ │
│  │  L2: Always stored to vector store                      │ │
│  │  L1: Optional auto-write to date/category files          │ │
│  │  L0: Manual update via memory_l0_update tool            │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
mem0/
├── server/
│   ├── main.py                    # Enhanced FastAPI server (async, auth, rate limit)
│   ├── requirements.txt            # Dependencies with redis/uvloop
│   ├── Dockerfile                 # Production image
│   ├── docker-compose.prod.yaml    # Production deployment
│   ├── .env                       # Environment template
│   ├── .gitignore                 # Exclude sensitive files
│   └── postgres-init/
│       └── 01-init.sql            # PostgreSQL initialization
│
└── openclaw/
    ├── index.ts                   # Main plugin (updated)
    ├── package.json               # Dependencies (added axios)
    ├── openclaw.plugin.json      # UI hints (updated)
    ├── README.md                  # Documentation (updated)
    └── lib/
        ├── server-client.ts       # HTTP client for server mode
        ├── l0-manager.ts         # L0 memory.md management
        ├── l1-manager.ts         # L1 date/category management
        └── index.d.ts           # TypeScript definitions
```

---

## Backward Compatibility

- Platform and open-source modes are **fully backward compatible**
- New `server` mode is optional
- L0/L1 layers are optional (disabled by default)
- Existing configurations continue to work without changes

---

## Security Considerations

1. **API Keys**: Stored server-side in `/app/history/api_keys.json`
2. **Rate Limiting**: Prevents abuse via Redis sliding window
3. **Per-Agent Isolation**: Each agent has its own collection
4. **SELinux**: Data volumes use `:z` flag for proper context
5. **Secret Management**: `.env` is excluded from git

---

## Performance Notes

- **Concurrency**: 4 uvicorn workers with asyncio support
- **Rate Limiting**: Configurable (default: 200 requests/60s)
- **Caching**: Memory instances cached per agent with double-checked locking
- **L0/L1**: File-based for fastest possible access
- **L2**: Vector search with configurable threshold and top-K

---

## Troubleshooting

### Server won't start
- Check `.env` file has all required variables
- Ensure `/opt/mem0-data/` has correct permissions
- Check docker logs: `docker compose logs mem0-server`

### API Key authentication fails
- Verify `X-API-Key` header is set correctly
- Check Redis is running for rate limiting
- Admin endpoints require `ADMIN_SECRET_KEY`

### L0/L1 files not loaded
- Verify `l0Enabled` and `l1Enabled` are `true` in config
- Check file paths are accessible
- Verify OpenClaw workspace permissions

---

## License

Apache 2.0 - Same as parent mem0ai/mem0 project
