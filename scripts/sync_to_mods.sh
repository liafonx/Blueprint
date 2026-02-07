#!/bin/zsh
# Syncs mod files to the game's Mods directory using rsync.
# Reads all configuration from mod.config.json (single source of truth)
#
# Config Version: 2.0.1
# Note: Uses zsh for macOS compatibility (bash 3.x lacks readarray)
#
# Usage:
#   ./scripts/sync_to_mods.sh                    # One-time sync
#   ./scripts/sync_to_mods.sh --watch            # Watch for changes (requires fswatch)
#   ./scripts/sync_to_mods.sh /custom/Mods/path  # Custom Mods path

set -e

# Get paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$DEV_DIR/mod.config.json"

# Check for config file
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: mod.config.json not found in $DEV_DIR"
    echo "Please create mod.config.json with required configuration"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

# ============================================
# Read all config from mod.config.json
# ============================================
MOD_NAME=$(jq -r '.mod_name' "$CONFIG_FILE")
MODS_DIR=$(jq -r '.paths.mods_dir // "~/Library/Application Support/Balatro/Mods"' "$CONFIG_FILE")
WATCH_ENABLED=$(jq -r '.sync.watch_enabled // true' "$CONFIG_FILE")

# Expand ~ in paths
MODS_DIR="${MODS_DIR/#\~/$HOME}"

if [[ -z "$MOD_NAME" || "$MOD_NAME" == "null" ]]; then
    echo "Error: mod_name not found in mod.config.json"
    exit 1
fi

# Read include_files as array (zsh syntax)
INCLUDE_LIST=("${(@f)$(jq -r '.include_files[]' "$CONFIG_FILE")}")

# Parse arguments (can override config)
WATCH_MODE=false

for arg in "$@"; do
    case $arg in
        --watch)
            WATCH_MODE=true
            ;;
        *)
            if [[ -d "$arg" ]]; then
                MODS_DIR="$arg"
            fi
            ;;
    esac
done

TARGET_DIR="$MODS_DIR/$MOD_NAME"

# Build rsync include/exclude args
RSYNC_ARGS=()
for item in "${INCLUDE_LIST[@]}"; do
    RSYNC_ARGS+=("--include=$item")
done
RSYNC_ARGS+=("--exclude=*")

do_sync() {
    echo "[$(date +%H:%M:%S)] Syncing to $TARGET_DIR ..."
    rsync -av --delete "${RSYNC_ARGS[@]}" "$DEV_DIR/" "$TARGET_DIR/"
    echo "[$(date +%H:%M:%S)] Done!"
}

echo "Mod:         $MOD_NAME"
echo "Dev folder:  $DEV_DIR"
echo "Target:      $TARGET_DIR"
echo "Files:       ${#INCLUDE_LIST[@]} patterns"
echo ""

# Create target dir
mkdir -p "$TARGET_DIR"

# Initial sync
do_sync

if [[ "$WATCH_MODE" == true ]]; then
    echo ""
    echo "Watching for changes... (Ctrl+C to stop)"
    echo ""

    # Check if fswatch is installed
    if ! command -v fswatch &> /dev/null; then
        echo "Error: fswatch is required for watch mode."
        echo "Install with: brew install fswatch"
        exit 1
    fi

    # Build watch paths from include list
    WATCH_PATHS=()
    for item in "${INCLUDE_LIST[@]}"; do
        # Strip glob patterns for directory watching
        clean_path="${item%%/\*\*\*}"
        clean_path="${clean_path%%/\*}"
        if [[ -e "$DEV_DIR/$clean_path" ]]; then
            WATCH_PATHS+=("$DEV_DIR/$clean_path")
        fi
    done

    if [[ ${#WATCH_PATHS[@]} -eq 0 ]]; then
        # Fallback to watching entire dev dir
        WATCH_PATHS=("$DEV_DIR")
    fi

    fswatch -o "${WATCH_PATHS[@]}" | while read -r; do
        do_sync
    done
fi
