# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mem0 is an intelligent memory layer for AI assistants and agents. It enables personalized AI interactions by remembering user preferences, adapting to individual needs, and continuously learning over time.

## Common Commands

### Development Environment Setup
```bash
make install          # Create hatch environment
make install_all      # Install all optional dependencies
```

### Code Quality
```bash
make format           # Format code with ruff
make sort             # Sort imports with isort
make lint             # Lint code with ruff
```

### Testing
```bash
make test             # Run all tests
make test-py-3.9      # Run tests on Python 3.9
make test-py-3.10     # Run tests on Python 3.10
make test-py-3.11     # Run tests on Python 3.11
make test-py-3.12     # Run tests on Python 3.12

# Run a specific test file
pytest tests/memory/test_main.py -v

# Run a specific test function
pytest tests/memory/test_main.py::test_add_memory -v
```

### Build and Publish
```bash
make build            # Build the package
make publish          # Publish to PyPI
make clean            # Clean build artifacts
```

### Documentation
```bash
make docs             # Start local documentation server (cd docs && mintlify dev)
```

### Server
```bash
# The server is in server/main.py - a FastAPI REST API
# Key endpoints: /memories, /search, /configure, /reset
```

## High-Level Architecture

### Core Memory System

The memory system (`mem0/memory/main.py`) is the heart of the project. It provides:

- **Memory**: Main synchronous class for memory operations
- **AsyncMemory**: Async variant for async workflows
- **MemoryClient/AsyncMemoryClient**: For hosted platform API usage

Memory operations follow this flow:
1. `add()` - Extracts facts from messages using LLM, embeds them, stores in vector store
2. `search()` - Searches vector store by query, optionally reranks results
3. `get()` / `get_all()` - Retrieves stored memories
4. `update()` - Updates existing memory content
5. `delete()` / `delete_all()` - Removes memories
6. `history()` - Gets change history for a memory

### Configuration System

All configuration uses Pydantic models (`mem0/configs/base.py`):

- **MemoryConfig**: Main config containing vector_store, llm, embedder, graph_store, reranker
- **MemoryItem**: Represents a single memory with id, memory, hash, metadata, score, timestamps
- **MemoryType**: Enum for SEMANTIC, EPISODIC, PROCEDURAL memory types

### Component Factory Pattern

The factory pattern (`mem0/utils/factory.py`) creates components based on provider:

- **LlmFactory**: Creates LLM instances (openai, anthropic, groq, together, azure_openai, ollama, gemini, etc.)
- **EmbedderFactory**: Creates embedding models (openai, huggingface, azure_openai, ollama, gemini, etc.)
- **VectorStoreFactory**: Creates vector store backends (qdrant, chroma, pgvector, pinecone, weaviate, etc.)
- **GraphStoreFactory**: Creates graph memory backends (neo4j, memgraph, kuzu, neptune)
- **RerankerFactory**: Creates rerankers (cohere, sentence_transformer, zero_entropy, llm_reranker, huggingface)

### Storage Layer

- **Vector Stores** (`mem0/vector_stores/`): Multiple providers supported - Qdrant is default. Each implements common interface for add, search, update, delete, reset.
- **History Storage** (`mem0/memory/storage.py`): SQLite-based tracking of memory changes with actor_id, role tracking
- **Graph Memory** (`mem0/memory/graph_memory.py`, `mem0/graphs/`): Optional graph-based memory with Neptune/Neo4j/Memgraph/Kuzu support

### Key Abstractions

- **MemoryBase** (`mem0/memory/base.py`): Abstract base class defining core memory interface
- **Fact Extraction**: LLM-based extraction of structured facts from conversational messages
- **Embedding Pipeline**: Messages -> LLM fact extraction -> Embedding -> Vector storage
- **Search Pipeline**: Query -> Embedding -> Vector search -> (optional) Reranking

### Response Format

All API responses use consistent format: `{"results": [...], "relations": [...]}` (relations optional for graph stores). This was standardized in v1.0.0 - older versions returned raw lists.

### Server API

The FastAPI server (`server/main.py`) exposes REST endpoints:
- POST `/configure` - Update memory config
- POST `/memories` - Create memories
- GET `/memories` - Get all memories (requires user_id/agent_id/run_id)
- GET `/memories/{id}` - Get specific memory
- GET `/memories/{id}/history` - Get memory history
- POST `/search` - Search memories
- PUT `/memories/{id}` - Update memory
- DELETE `/memories/{id}` - Delete memory
- DELETE `/memories` - Delete all memories for identifier
- POST `/reset` - Completely reset all memories

### Testing Structure

Tests are organized by component:
- `tests/memory/` - Core memory tests
- `tests/llms/` - LLM provider tests
- `tests/embeddings/` - Embedding provider tests
- `tests/vector_stores/` - Vector store provider tests
- `tests/test_main.py` - Main integration tests

### Memory Types

- **SEMANTIC**: General knowledge and facts
- **EPISODIC**: Event-based memories (what happened when)
- **PROCEDURAL**: How-to knowledge and workflows

### Important Notes

- Default LLM is `gpt-4.1-nano-2025-04-14` from OpenAI
- Default vector store is Qdrant
- History DB defaults to `~/.mem0/history.db`
- All identifiers (user_id, agent_id, run_id) are optional but at least one is required for most operations
- The project uses hatchling as the build system
- Python versions supported: 3.9, 3.10, 3.11, 3.12
