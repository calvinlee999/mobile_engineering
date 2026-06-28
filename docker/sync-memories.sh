#!/bin/bash
# sync-memories.sh — Bidirectional memory sync
# Claude Code .md files ↔ Local PostgreSQL ↔ Mac Mini master
#
# Usage:
#   bash sync-memories.sh push    # .md files → PostgreSQL (after Claude Code session)
#   bash sync-memories.sh pull    # PostgreSQL → .md files (before Claude Code session)
#   bash sync-memories.sh full    # push + pull + sync to Mac Mini if reachable
#
# Called automatically by Claude Code hooks (configured in settings.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

CLAUDE_MEMORY_DIRS=(
    "$HOME/.claude/projects/-Users-calvinlee-ai-workspace-local-calvin-infratructure-target/memory"
    "$HOME/.claude/projects/-Users-calvinlee-ai-workspace-local-mobile-engineering/memory"
)

HERMES_DIR="$HOME/.hermes"

local_pg_ready() {
    pg_isready -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" > /dev/null 2>&1
}

master_reachable() {
    ping -c 1 -t 2 "$MASTER_HOST" > /dev/null 2>&1
}

push_md_to_pg() {
    if ! local_pg_ready; then
        return 0
    fi

    local count=0
    for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -f "$f" ] || continue
            basename=$(basename "$f" .md)
            [ "$basename" = "MEMORY" ] && continue

            content=$(cat "$f")
            source_tool="claude-code"
            memory_type=$(grep -oP '(?<=type: )\w+' "$f" 2>/dev/null || echo "general")

            PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -q -c "
                INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device)
                VALUES ('$basename', '$memory_type', \$\$${content}\$\$, ARRAY['$source_tool','auto-sync'], 'macbook-air')
                ON CONFLICT DO NOTHING;" 2>/dev/null
            count=$((count + 1))
        done
    done

    # Also sync Hermes MEMORY.md and USER.md
    for f in "$HERMES_DIR/MEMORY.md" "$HERMES_DIR/USER.md"; do
        [ -f "$f" ] || continue
        basename=$(basename "$f" .md)
        content=$(cat "$f")
        PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -q -c "
            INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device)
            VALUES ('hermes-$basename', 'hermes', \$\$${content}\$\$, ARRAY['hermes','auto-sync'], 'macbook-air')
            ON CONFLICT DO NOTHING;" 2>/dev/null
        count=$((count + 1))
    done

    [ $count -gt 0 ] && echo "→ Pushed $count memory files to local PostgreSQL"
}

pull_pg_to_md() {
    if ! local_pg_ready; then
        return 0
    fi

    # Pull memories from PG that came from Hermes (not already in .md files)
    local hermes_memories
    hermes_memories=$(PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -tAc \
        "SELECT DISTINCT agent_id FROM agent_memories WHERE 'hermes' = ANY(tags) AND NOT ('claude-code' = ANY(tags));" 2>/dev/null)

    local count=0
    for agent_id in $hermes_memories; do
        content=$(PGPASSWORD="$LOCAL_PASS" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" -tAc \
            "SELECT content FROM agent_memories WHERE agent_id = '$agent_id' ORDER BY updated_at DESC LIMIT 1;" 2>/dev/null)
        [ -z "$content" ] && continue

        for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
            [ -d "$dir" ] || continue
            target="$dir/hermes-${agent_id}.md"
            if [ ! -f "$target" ]; then
                echo "$content" > "$target"
                count=$((count + 1))
            fi
            break
        done
    done

    [ $count -gt 0 ] && echo "→ Pulled $count Hermes memories to Claude Code .md files"
}

sync_to_master() {
    if ! master_reachable; then
        echo "⚠️  Mac Mini not reachable — skipping master sync"
        return 0
    fi

    if ! local_pg_ready; then
        return 0
    fi

    bash "$SCRIPT_DIR/sync-memory-to-master.sh"
}

case "${1:-full}" in
    push)
        push_md_to_pg
        ;;
    pull)
        pull_pg_to_md
        ;;
    full)
        push_md_to_pg
        pull_pg_to_md
        sync_to_master
        ;;
    *)
        echo "Usage: $0 {push|pull|full}"
        exit 1
        ;;
esac
