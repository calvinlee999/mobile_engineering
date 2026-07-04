-- Agent Memory Schema — local (MacBook Air) staging table for Claude Code
-- memory files. Syncs to Mac Mini's claude_code_memory_sync table (a table
-- dedicated to this purpose — NOT Hermes's own agent_memories log, which uses
-- a different append-only schema and must not be overwritten by this sync).

CREATE TABLE IF NOT EXISTS agent_memories (
    id              SERIAL PRIMARY KEY,
    agent_id        VARCHAR(100) NOT NULL,
    memory_type     VARCHAR(50) NOT NULL,
    content         TEXT NOT NULL,
    tags            TEXT[] DEFAULT '{}',
    source_device   VARCHAR(50) DEFAULT 'macbook-air',
    synced_to_master BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE agent_memories ADD CONSTRAINT uq_agent_memories_agent_id UNIQUE (agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_memories_agent_id ON agent_memories(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_memories_type ON agent_memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_agent_memories_tags ON agent_memories USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_agent_memories_synced ON agent_memories(synced_to_master);
