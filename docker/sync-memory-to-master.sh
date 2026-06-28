#!/bin/bash
# sync-memory-to-master.sh
# Syncs unsynced local agent memories from MacBook Air → Mac Mini master PostgreSQL.
# Run manually or via cron when connected to home network.
#
# Usage: bash docker/sync-memory-to-master.sh

set -euo pipefail

LOCAL_HOST="localhost"
LOCAL_PORT="5433"
LOCAL_DB="agent_memory"
LOCAL_USER="agent_user"
LOCAL_PASS="agent_local_only"

MASTER_HOST="192.168.68.20"
MASTER_PORT="5432"
MASTER_DB="kafka_dev"
MASTER_USER="kafka_user"
MASTER_PASS="kafka_pass"

# Check Mac Mini reachable
if ! ping -c 1 -t 3 "$MASTER_HOST" > /dev/null 2>&1; then
    echo "⚠️  Mac Mini ($MASTER_HOST) not reachable — skipping sync"
    exit 0
fi

# Check local DB running
if ! pg_isready -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" > /dev/null 2>&1; then
    echo "⚠️  Local agent-memory-db not running — start with:"
    echo "   docker compose -f docker/docker-compose.agent-memory.yml up -d"
    exit 1
fi

# Count unsynced memories
UNSYNCED=$(PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -tAc \
    "SELECT count(*) FROM agent_memories WHERE synced_to_master = FALSE;")

if [ "$UNSYNCED" -eq 0 ]; then
    echo "✓ No unsynced memories — nothing to push"
    exit 0
fi

echo "→ Syncing $UNSYNCED memories to Mac Mini master..."

# Export unsynced rows as INSERT statements
PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -tAc \
    "SELECT format(
        'INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device, created_at, updated_at) VALUES (%L, %L, %L, %L, %L, %L, %L) ON CONFLICT DO NOTHING;',
        agent_id, memory_type, content, tags::text, source_device, created_at, updated_at
    ) FROM agent_memories WHERE synced_to_master = FALSE;" | \
    PGPASSWORD="$MASTER_PASS" psql -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$MASTER_USER" -d "$MASTER_DB"

# Mark as synced
PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -c \
    "UPDATE agent_memories SET synced_to_master = TRUE WHERE synced_to_master = FALSE;"

echo "✓ Synced $UNSYNCED memories to Mac Mini master"

# Pull count from master for verification
MASTER_COUNT=$(PGPASSWORD="$MASTER_PASS" psql -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$MASTER_USER" -d "$MASTER_DB" -tAc \
    "SELECT count(*) FROM agent_memories;" 2>/dev/null || echo "?")

echo "  Local: $(PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -tAc 'SELECT count(*) FROM agent_memories;') total"
echo "  Master: $MASTER_COUNT total"
