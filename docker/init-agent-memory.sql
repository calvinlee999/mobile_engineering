-- Agent Memory Schema — matches Mac Mini's agent_memories table
-- Local copy for offline operation. Syncs to Mac Mini master.

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

CREATE INDEX IF NOT EXISTS idx_agent_memories_agent_id ON agent_memories(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_memories_type ON agent_memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_agent_memories_tags ON agent_memories USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_agent_memories_synced ON agent_memories(synced_to_master);
