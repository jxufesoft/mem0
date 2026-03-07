-- PostgreSQL initialization script for Mem0 with pgvector
--
-- This script is run when the database is first created.
-- It creates the required extensions and grants permissions.
--
-- Note: This script assumes the default user 'mem0user' from the
-- docker-compose.prod.yaml configuration. If you change POSTGRES_USER
-- in your .env file, you may need to adjust permissions manually.

-- Create required extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant permissions to the default mem0 user
-- Note: The database user is created by PostgreSQL based on POSTGRES_USER env var
GRANT ALL PRIVILEGES ON DATABASE mem0db TO mem0user;
GRANT ALL ON SCHEMA public TO mem0user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mem0user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mem0user;

-- Allow future tables to inherit these permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO mem0user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO mem0user;
