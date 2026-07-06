#!/bin/bash
# sync-memories.sh — Bidirectional memory sync
# Claude Code .md files ↔ Local PostgreSQL ↔ Mac Mini master
# Falls back to a local SQLite file if the Postgres container can't be brought up.
#
# Usage:
#   bash sync-memories.sh push    # .md files → PostgreSQL/SQLite (after Claude Code session)
#   bash sync-memories.sh pull    # PostgreSQL/SQLite → .md files (before Claude Code session)
#   bash sync-memories.sh full    # push + pull + sync to Mac Mini if reachable
#
# Called automatically by Claude Code hooks (configured in settings.json):
#   Stop hook  → push (save new memories)
#   SessionStart hook → pull (load shared memories into current workspace)
#
# Storage precedence per run:
#   1. Local PostgreSQL (agent-memory-db) — started automatically if it isn't running.
#   2. Local SQLite file — used only if Docker/Postgres genuinely can't come up,
#      so a session never silently loses memory writes. Reconciled back into
#      Postgres automatically the next time Postgres is available.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_HOST="localhost"
LOCAL_PORT="5433"
LOCAL_DB="agent_memory"
LOCAL_USER="agent_user"
LOCAL_PASS="agent_local_only"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.agent-memory.yml"
PG_START_TIMEOUT=15   # seconds to wait for agent-memory-db to become healthy

MASTER_HOST="192.168.1.20"
MASTER_PORT="5432"
MASTER_DB="kafka_dev"
MASTER_USER="kafka_user"
MASTER_PASS="kafka_pass"

SQLITE_DB="$HOME/.claude/agent-memory-fallback.sqlite3"

# Auto-discover ALL workspace memory directories — no hardcoding needed
CLAUDE_MEMORY_DIRS=()
for dir in "$HOME"/.claude/projects/*/memory; do
    [ -d "$dir" ] && CLAUDE_MEMORY_DIRS+=("$dir")
done

HERMES_DIR="$HOME/.hermes"

docker_daemon_up() {
    docker info > /dev/null 2>&1
}

local_pg_ready() {
    docker exec agent-memory-db pg_isready -U "$LOCAL_USER" -d "$LOCAL_DB" > /dev/null 2>&1
}

# Ensures agent-memory-db is running, starting it if needed. Returns 1 (and lets
# the caller fall back to SQLite) only if Docker itself is down or the container
# fails to become healthy within PG_START_TIMEOUT.
ensure_local_pg() {
    local_pg_ready && return 0

    if ! docker_daemon_up; then
        echo "⚠️  Docker daemon not running — falling back to local SQLite" >&2
        return 1
    fi

    echo "→ agent-memory-db not running — starting it..." >&2
    if docker ps -a --format '{{.Names}}' | grep -qx "agent-memory-db"; then
        docker start agent-memory-db > /dev/null 2>&1 || true
    elif [ -f "$COMPOSE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" up -d > /dev/null 2>&1 || true
    else
        echo "⚠️  $COMPOSE_FILE not found — falling back to local SQLite" >&2
        return 1
    fi

    local waited=0
    while [ "$waited" -lt "$PG_START_TIMEOUT" ]; do
        local_pg_ready && { echo "✓ agent-memory-db is up" >&2; return 0; }
        sleep 1
        waited=$((waited + 1))
    done

    echo "⚠️  agent-memory-db did not become ready in ${PG_START_TIMEOUT}s — falling back to local SQLite" >&2
    return 1
}

master_reachable() {
    ping -c 1 -t 2 "$MASTER_HOST" > /dev/null 2>&1
}

psql_local() {
    docker exec agent-memory-db psql -U "$LOCAL_USER" -d "$LOCAL_DB" -tA "$@" 2>/dev/null
}

push_md_to_pg() {
    if ! local_pg_ready; then
        return 0
    fi

    # Collect newest version of each memory across all workspaces (by mtime)
    local -A newest_file
    local -A newest_mtime
    for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -f "$f" ] || continue
            local basename
            basename=$(basename "$f" .md)
            [ "$basename" = "MEMORY" ] && continue

            local mtime
            mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
            if [ -z "${newest_mtime[$basename]:-}" ] || [ "$mtime" -gt "${newest_mtime[$basename]:-0}" ]; then
                newest_file[$basename]="$f"
                newest_mtime[$basename]="$mtime"
            fi
        done
    done

    # Push only the newest version of each memory to PG
    local count=0
    for basename in "${!newest_file[@]}"; do
        local f="${newest_file[$basename]}"
        local content memory_type
        content=$(cat "$f")
        memory_type=$(sed -n 's/^  *type: *//p' "$f" 2>/dev/null | head -1)
        [ -z "$memory_type" ] && memory_type="general"

        psql_local -c "
            INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device, updated_at)
            VALUES ('$basename', '$memory_type', \$\$${content}\$\$, ARRAY['claude-code','auto-sync'], 'macbook-air', NOW())
            ON CONFLICT (agent_id) DO UPDATE SET
                content = EXCLUDED.content,
                memory_type = EXCLUDED.memory_type,
                tags = EXCLUDED.tags,
                updated_at = NOW(),
                synced_to_master = FALSE;" 2>/dev/null
        count=$((count + 1))
    done

    # Also sync Hermes MEMORY.md and USER.md
    for f in "$HERMES_DIR/MEMORY.md" "$HERMES_DIR/USER.md"; do
        [ -f "$f" ] || continue
        local basename content
        basename="hermes-$(basename "$f" .md)"
        content=$(cat "$f")
        psql_local -c "
            INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device, updated_at)
            VALUES ('$basename', 'hermes', \$\$${content}\$\$, ARRAY['hermes','auto-sync'], 'macbook-air', NOW())
            ON CONFLICT (agent_id) DO UPDATE SET
                content = EXCLUDED.content,
                updated_at = NOW(),
                synced_to_master = FALSE;" 2>/dev/null
        count=$((count + 1))
    done

    if [ $count -gt 0 ]; then
        echo "→ Pushed $count memory files to local PostgreSQL"
    fi
}

pull_pg_to_md() {
    if ! local_pg_ready; then
        return 0
    fi

    local agent_ids
    agent_ids=$(psql_local -c "SELECT agent_id FROM agent_memories WHERE 'claude-code' = ANY(tags) ORDER BY agent_id;")

    [ -z "$agent_ids" ] && return 0

    local count=0
    for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
        [ -d "$dir" ] || continue

        local dir_changed=false
        for agent_id in $agent_ids; do
            local target="$dir/${agent_id}.md"

            local pg_content
            pg_content=$(psql_local -c "SELECT content FROM agent_memories WHERE agent_id = '$agent_id';")
            [ -z "$pg_content" ] && continue

            if [ -f "$target" ]; then
                local existing
                existing=$(cat "$target")
                [ "$existing" = "$pg_content" ] && continue
            fi

            echo "$pg_content" > "$target"
            dir_changed=true
            count=$((count + 1))
        done

        if $dir_changed; then
            rebuild_memory_index "$dir"
        fi
    done

    if [ $count -gt 0 ]; then
        echo "→ Pulled $count memory files across workspaces"
    fi
}

rebuild_memory_index() {
    local dir="$1"
    local index="$dir/MEMORY.md"
    local entries=""

    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        local basename
        basename=$(basename "$f" .md)
        [ "$basename" = "MEMORY" ] && continue

        local description
        description=$(sed -n 's/^description: *//p' "$f" 2>/dev/null | head -1 | sed 's/^"//;s/"$//')
        [ -z "$description" ] && description="(no description)"

        local name
        name=$(sed -n 's/^name: *//p' "$f" 2>/dev/null | head -1)
        [ -z "$name" ] && name="$basename"

        entries="${entries}- [${name}](${basename}.md) — ${description}\n"
    done

    printf "%b" "$entries" > "$index"
}

sqlite_init() {
    command -v sqlite3 > /dev/null 2>&1 || return 1
    sqlite3 "$SQLITE_DB" "
        CREATE TABLE IF NOT EXISTS agent_memories (
            agent_id         TEXT PRIMARY KEY,
            memory_type      TEXT,
            content          TEXT,
            tags             TEXT,
            source_device    TEXT,
            updated_at       TEXT,
            synced_to_master INTEGER DEFAULT 0
        );" 2>/dev/null
}

sqlite_upsert() {
    local agent_id="$1" memory_type="$2" content="$3" tags="$4" source_device="$5"
    local esc_content="${content//\'/\'\'}"
    sqlite3 "$SQLITE_DB" "
        INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device, updated_at, synced_to_master)
        VALUES ('$agent_id', '$memory_type', '$esc_content', '$tags', '$source_device', datetime('now'), 0)
        ON CONFLICT(agent_id) DO UPDATE SET
            content = excluded.content,
            memory_type = excluded.memory_type,
            updated_at = excluded.updated_at,
            synced_to_master = 0;" 2>/dev/null
}

# Used only when ensure_local_pg fails — writes memory .md files to a local
# SQLite file so a session never silently loses writes while Postgres is down.
push_md_to_sqlite() {
    sqlite_init || { echo "⚠️  sqlite3 unavailable — memory writes for this session will not persist" >&2; return 0; }

    local -A newest_file
    local -A newest_mtime
    for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -f "$f" ] || continue
            local basename
            basename=$(basename "$f" .md)
            [ "$basename" = "MEMORY" ] && continue

            local mtime
            mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
            if [ -z "${newest_mtime[$basename]:-}" ] || [ "$mtime" -gt "${newest_mtime[$basename]:-0}" ]; then
                newest_file[$basename]="$f"
                newest_mtime[$basename]="$mtime"
            fi
        done
    done

    local count=0
    for basename in "${!newest_file[@]}"; do
        local f="${newest_file[$basename]}"
        local content memory_type
        content=$(cat "$f")
        memory_type=$(sed -n 's/^  *type: *//p' "$f" 2>/dev/null | head -1)
        [ -z "$memory_type" ] && memory_type="general"
        sqlite_upsert "$basename" "$memory_type" "$content" "claude-code,auto-sync" "macbook-air"
        count=$((count + 1))
    done

    for f in "$HERMES_DIR/MEMORY.md" "$HERMES_DIR/USER.md"; do
        [ -f "$f" ] || continue
        local basename content
        basename="hermes-$(basename "$f" .md)"
        content=$(cat "$f")
        sqlite_upsert "$basename" "hermes" "$content" "hermes,auto-sync" "macbook-air"
        count=$((count + 1))
    done

    if [ $count -gt 0 ]; then
        echo "→ Pushed $count memory files to local SQLite fallback (Postgres unavailable)"
    fi
}

# Used only when ensure_local_pg fails — reads memory .md files back from the
# SQLite fallback so a workspace still gets its memories when Postgres is down.
pull_sqlite_to_md() {
    sqlite_init || return 0
    [ -f "$SQLITE_DB" ] || return 0

    local agent_ids
    agent_ids=$(sqlite3 "$SQLITE_DB" "SELECT agent_id FROM agent_memories WHERE tags LIKE '%claude-code%';" 2>/dev/null)
    [ -z "$agent_ids" ] && return 0

    local count=0
    for dir in "${CLAUDE_MEMORY_DIRS[@]}"; do
        [ -d "$dir" ] || continue

        local dir_changed=false
        while IFS= read -r agent_id; do
            [ -z "$agent_id" ] && continue
            local target="$dir/${agent_id}.md"
            local sqlite_content
            sqlite_content=$(sqlite3 "$SQLITE_DB" "SELECT content FROM agent_memories WHERE agent_id = '$agent_id';" 2>/dev/null)
            [ -z "$sqlite_content" ] && continue

            if [ -f "$target" ]; then
                local existing
                existing=$(cat "$target")
                [ "$existing" = "$sqlite_content" ] && continue
            fi

            echo "$sqlite_content" > "$target"
            dir_changed=true
            count=$((count + 1))
        done <<< "$agent_ids"

        if $dir_changed; then
            rebuild_memory_index "$dir"
        fi
    done

    if [ $count -gt 0 ]; then
        echo "→ Pulled $count memory files from local SQLite fallback (Postgres unavailable)"
    fi
}

# Once Postgres is back, migrate anything the SQLite fallback collected while
# it was down, then clear the fallback so it doesn't silently shadow Postgres.
reconcile_sqlite_to_pg() {
    [ -f "$SQLITE_DB" ] || return 0
    command -v sqlite3 > /dev/null 2>&1 || return 0
    local_pg_ready || return 0

    # agent_id/memory_type/tags never contain newlines, so this list is safe to
    # split line-by-line; content (which can) is fetched per-row below instead
    # of in this bulk query.
    local agent_ids
    agent_ids=$(sqlite3 "$SQLITE_DB" "SELECT agent_id FROM agent_memories;" 2>/dev/null)
    [ -z "$agent_ids" ] && return 0

    local count=0
    while IFS= read -r agent_id; do
        [ -z "$agent_id" ] && continue
        local memory_type content tags tags_sql
        memory_type=$(sqlite3 "$SQLITE_DB" "SELECT memory_type FROM agent_memories WHERE agent_id = '$agent_id';" 2>/dev/null)
        content=$(sqlite3 "$SQLITE_DB" "SELECT content FROM agent_memories WHERE agent_id = '$agent_id';" 2>/dev/null)
        tags=$(sqlite3 "$SQLITE_DB" "SELECT tags FROM agent_memories WHERE agent_id = '$agent_id';" 2>/dev/null)
        tags_sql=$(printf "ARRAY[%s]" "$(echo "$tags" | awk -F',' '{for(i=1;i<=NF;i++) printf "%s%s", (i>1?",":""), "\x27" $i "\x27"}')")

        psql_local -c "
            INSERT INTO agent_memories (agent_id, memory_type, content, tags, source_device, updated_at)
            VALUES ('$agent_id', '$memory_type', \$\$${content}\$\$, ${tags_sql}, 'macbook-air', NOW())
            ON CONFLICT (agent_id) DO UPDATE SET
                content = EXCLUDED.content,
                memory_type = EXCLUDED.memory_type,
                tags = EXCLUDED.tags,
                updated_at = NOW(),
                synced_to_master = FALSE;" 2>/dev/null
        count=$((count + 1))
    done <<< "$agent_ids"

    if [ $count -gt 0 ]; then
        rm -f "$SQLITE_DB"
        echo "→ Reconciled $count memory entries from SQLite fallback into PostgreSQL"
    fi
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

push() {
    if ensure_local_pg; then
        reconcile_sqlite_to_pg
        push_md_to_pg
    else
        push_md_to_sqlite
    fi
}

pull() {
    if ensure_local_pg; then
        reconcile_sqlite_to_pg
        pull_pg_to_md
    else
        pull_sqlite_to_md
    fi
}

case "${1:-full}" in
    push)
        push
        ;;
    pull)
        pull
        ;;
    full)
        push
        pull
        sync_to_master
        ;;
    *)
        echo "Usage: $0 {push|pull|full}"
        exit 1
        ;;
esac
