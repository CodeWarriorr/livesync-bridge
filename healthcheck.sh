#!/bin/bash
# LiveSync Bridge Health Check
# Restarts bridge if CouchDB connection errors detected or listener is stale.
# Run via cron every 30 minutes.

LOG="/home/openclaw/livesync-bridge/healthcheck.log"
CONTAINER="livesync-bridge-bridge-1"
MAX_LOG_LINES=200

log() { echo "$(date -u '+%Y-%m-%d %H:%M UTC') $1" >> "$LOG"; }

# Rotate log if >1000 lines
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 1000 ]; then
    tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# Check container running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$CONTAINER"; then
    log "RESTART: container not running, starting via compose"
    cd /home/openclaw/livesync-bridge && docker compose up -d >> "$LOG" 2>&1
    exit 0
fi

# Get recent logs (last 30 min)
RECENT=$(docker logs "$CONTAINER" --since 30m 2>&1)

# Check for connection errors
ERRORS=$(echo "$RECENT" | grep -c "error reading a body from connection")
if [ "$ERRORS" -gt 0 ]; then
    log "RESTART: found $ERRORS connection errors in last 30m"
    docker restart "$CONTAINER" >> "$LOG" 2>&1
    exit 0
fi

# Check for Uncaught errors (crash indicator — container auto-restarts but listener may be dead)
UNCAUGHT=$(echo "$RECENT" | grep -c "Uncaught")
if [ "$UNCAUGHT" -gt 0 ]; then
    log "RESTART: found $UNCAUGHT uncaught errors in last 30m"
    docker restart "$CONTAINER" >> "$LOG" 2>&1
    exit 0
fi

# Check CouchDB listener is alive: look for ANY obsidian-vault activity in last 2 hours
# (Remote tweaks count — they prove the CouchDB connection is alive)
COUCH_ALIVE=$(docker logs "$CONTAINER" --since 2h 2>&1 | grep -c "\[obsidian-vault\]")
if [ "$COUCH_ALIVE" -eq 0 ]; then
    log "RESTART: no CouchDB activity in 2 hours — listener may be dead"
    docker restart "$CONTAINER" >> "$LOG" 2>&1
    exit 0
fi

log "OK: container healthy (couch_events=$COUCH_ALIVE in 2h, errors=$ERRORS)"
