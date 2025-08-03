#!/bin/bash

set -e

JUNO_DIR=/var/lib/juno
KEYS_DIR=/var/lib/juno/keys

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Starting Juno Starknet Node ==="
log "Juno data directory: $JUNO_DIR"
log "Network: ${NETWORK:-mainnet}"
log "Staking enabled: ${ENABLE_STAKING:-false}"
log "Metrics enabled: ${ENABLE_METRICS:-true}"

validate_staking_config() {
    if [ "$ENABLE_STAKING" = "true" ]; then
        if [ -z "$ETH_L1_RPC_URL" ]; then
            log "ERROR: ETH_L1_RPC_URL is required when staking is enabled"
            exit 1
        fi
        
        if [ -z "$VALIDATOR_KEY_FILE" ]; then
            log "ERROR: VALIDATOR_KEY_FILE is required when staking is enabled"
            exit 1
        fi
        
        if [ ! -f "$VALIDATOR_KEY_FILE" ]; then
            log "ERROR: Validator key file not found: $VALIDATOR_KEY_FILE"
            log "Please place your validator private key in: $KEYS_DIR/"
            exit 1
        fi
        
        log "✓ Staking configuration validated"
    fi
}

download_snapshot() {
    if [ "$(ls -A $JUNO_DIR/juno_mainnet 2>/dev/null)" ]; then  # ⬆️ CAMBIO: Mejor detección
        log "Database already exists, skipping snapshot download"
        return 0
    fi
    
    if [ -n "$SNAPSHOT_URL" ]; then
        log "Downloading snapshot from: $SNAPSHOT_URL"
        
        local snapshot_file="snapshot.tar"  # ⬆️ CAMBIO: Variable local
        
        # ⬆️ CAMBIO: Download con retries y mejor timeout
        if wget --progress=dot:giga --tries=3 --timeout=300 \
               -O "$snapshot_file" "$SNAPSHOT_URL"; then
            log "Extracting snapshot..."
            tar --checkpoint=65536 -xf "$snapshot_file" -C "$JUNO_DIR" && rm "$snapshot_file"
            log "✓ Snapshot extracted successfully"
        else
            log "⚠ Failed to download snapshot, starting fresh sync"
            rm -f "$snapshot_file"
        fi
    else
        log "No snapshot URL provided, starting fresh sync"
    fi
}

build_juno_command() {
    local cmd="juno"
    
    # Basic configuration
    cmd="$cmd --http --http-port 6060 --http-host 0.0.0.0"
    cmd="$cmd --db-path $JUNO_DIR"
    cmd="$cmd --network ${NETWORK:-mainnet}"
    cmd="$cmd --log-level ${LOG_LEVEL:-info}"
    
    # L1 verification
    if [ -n "$ETH_L1_RPC_URL" ]; then
        log "✓ L1 verification enabled"
        cmd="$cmd --eth-node $ETH_L1_RPC_URL"
    else
        log "⚠ L1 verification disabled"
        cmd="$cmd --disable-l1-verification"
    fi
    
    # WebSocket configuration
    if [ "$ENABLE_WS" = "true" ]; then
        log "✓ WebSocket enabled on port ${WS_PORT:-6061}"
        cmd="$cmd --ws --ws-port ${WS_PORT:-6061} --ws-host ${WS_HOST:-0.0.0.0}"
    fi
    
    # Configuración de métricas
    if [ "$ENABLE_METRICS" = "true" ]; then
        log "✓ Metrics enabled on port ${METRICS_PORT:-9090}"
        cmd="$cmd --metrics --metrics-host ${METRICS_HOST:-0.0.0.0} --metrics-port ${METRICS_PORT:-9090}"
    fi
    
    # Configuración completa de staking
    if [ "$ENABLE_STAKING" = "true" ]; then
        log "✓ Validator staking enabled"
        cmd="$cmd --validator"
        cmd="$cmd --validator-key-file $VALIDATOR_KEY_FILE"
        
        if [ -n "$VALIDATOR_GRAFFITI" ]; then
            cmd="$cmd --validator-graffiti \"$VALIDATOR_GRAFFITI\""
        fi
    fi
    
    # Extra options
    if [ -n "$EXTRA_OPTS" ]; then
        log "✓ Extra options: $EXTRA_OPTS"
        cmd="$cmd $EXTRA_OPTS"
    fi
    
    echo "$cmd"
}

preflight_checks() {
    log "Running pre-flight checks..."
    
    # Check disk space (minimum 200GB recommended)
    local available_space=$(df $JUNO_DIR | tail -1 | awk '{print $4}')
    local min_space_kb=$((200 * 1024 * 1024)) # 200GB in KB
    
    if [ "$available_space" -lt "$min_space_kb" ]; then
        log "⚠ WARNING: Available disk space is less than 200GB"
        log "  Available: $(($available_space / 1024 / 1024))GB"
        log "  Recommended: 200GB minimum for mainnet"
    fi
    
    # Create keys directory if staking is enabled
    if [ "$ENABLE_STAKING" = "true" ]; then
        mkdir -p "$KEYS_DIR"
        chmod 700 "$KEYS_DIR"
    fi
    
    log "✓ Pre-flight checks completed"
}

main() {
    preflight_checks
    validate_staking_config
    download_snapshot
    
    local juno_cmd=$(build_juno_command)
    
    log "=== Starting Juno with command ==="
    log "$juno_cmd"
    log "================================="
    
    # Execute Juno
    exec $juno_cmd
}

trap 'log "Received shutdown signal, stopping Juno..."; exit 0' SIGTERM SIGINT

main "$@"