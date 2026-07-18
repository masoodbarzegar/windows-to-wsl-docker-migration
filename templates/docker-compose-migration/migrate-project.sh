#!/usr/bin/env bash
#
# migrate-project.sh -- conservative, non-destructive migration PREP helper.
#
# What this script does:
#   1. Validates the source path exists.
#   2. Refuses to touch a destination that already exists and is non-empty.
#   3. Creates the destination directory.
#   4. Copies files from source to destination with rsync (one-way, no deletes).
#   5. Writes a migration inventory report (git state, compose/env/db-folder
#      detection, rough size).
#   6. If a Compose file exists at the destination, runs
#      `docker compose -f <file> config` (validation only) and records the result.
#
# What this script will NEVER do, by design:
#   - start, stop, or restart any container
#   - remove any file or directory
#   - remove, prune, or otherwise modify any Docker resource
#   - modify anything under the source path
#   - restore or touch any database
#   - run `docker compose up` / `down` in any form
#
# Use --dry-run to see every planned action without performing any of them.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=0
EXCLUDE_DEPS=0
SOURCE=""
DESTINATION=""
REPORT_PATH=""

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --source <path> --destination <path> [options]

Required:
  --source <path>        Existing project directory to copy from (read-only).
  --destination <path>   Target directory under WSL. Must not already exist,
                          or must be empty if it does.

Options:
  --dry-run               Print every planned action, perform none of them.
  --exclude-deps           Exclude vendor/ and node_modules/ from the copy
                            (only use this if you intend to reinstall them
                            fresh in WSL -- see PROJECT-MIGRATION-CHECKLIST.md).
  --report <path>          Where to write the migration inventory report.
                            Default: sibling of destination,
                            "<destination>.inventory-<timestamp>.md"
  -h, --help                Show this help text.

This script never starts/stops containers, never deletes files, never
touches Docker resources, and never modifies the source path. It only
prepares a destination and reports on it.
EOF
}

log_plan() {
  echo "[PLAN]     $*"
}

log_run() {
  echo "[RUN]      $*"
}

log_skip() {
  echo "[DRY-RUN]  would run: $*"
}

# Runs a command, or just announces it under --dry-run. Never used for
# anything destructive (see header comment) -- only mkdir, rsync (no
# --delete), and read-only docker compose config.
run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_skip "$*"
  else
    log_run "$*"
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"; shift 2 ;;
    --destination)
      DESTINATION="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --exclude-deps)
      EXCLUDE_DEPS=1; shift ;;
    --report)
      REPORT_PATH="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$SOURCE" || -z "$DESTINATION" ]]; then
  echo "Error: --source and --destination are both required." >&2
  usage
  exit 1
fi

# Normalize to absolute paths where possible (source must exist to resolve).
if [[ ! -e "$SOURCE" ]]; then
  echo "Error: source path does not exist: $SOURCE" >&2
  exit 1
fi
if [[ ! -d "$SOURCE" ]]; then
  echo "Error: source path is not a directory: $SOURCE" >&2
  exit 1
fi
SOURCE="$(cd "$SOURCE" && pwd)"

# Refuse to overwrite a non-empty destination.
if [[ -e "$DESTINATION" ]]; then
  if [[ ! -d "$DESTINATION" ]]; then
    echo "Error: destination exists and is not a directory: $DESTINATION" >&2
    exit 1
  fi
  if [[ -n "$(ls -A "$DESTINATION" 2>/dev/null)" ]]; then
    echo "Error: destination already exists and is not empty: $DESTINATION" >&2
    echo "Refusing to touch it. Choose a new destination or empty it yourself first." >&2
    exit 1
  fi
fi

if [[ -z "$REPORT_PATH" ]]; then
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  DEST_PARENT="$(dirname "$DESTINATION")"
  DEST_BASENAME="$(basename "$DESTINATION")"
  REPORT_PATH="${DEST_PARENT}/${DEST_BASENAME}.inventory-${TIMESTAMP}.md"
fi

echo "=================================================================="
echo " Migration prep: $SOURCE"
echo "             ->  $DESTINATION"
echo " Dry run:        $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo " Exclude deps:    $([[ $EXCLUDE_DEPS -eq 1 ]] && echo "vendor/, node_modules/" || echo "none (full copy)")"
echo " Report:          $REPORT_PATH"
echo "=================================================================="

log_plan "create destination directory: $DESTINATION"
run_cmd mkdir -p "$DESTINATION"

RSYNC_ARGS=(-avh --progress)
if [[ "$EXCLUDE_DEPS" -eq 1 ]]; then
  RSYNC_ARGS+=(--exclude "vendor/" --exclude "node_modules/")
fi
# Trailing slash on source: copy contents, not the directory itself, into destination.
# No --delete, ever: this script only ever adds to destination, never removes.
log_plan "copy files with rsync (one-way, no deletions, .git preserved)"
run_cmd rsync "${RSYNC_ARGS[@]}" "${SOURCE}/" "${DESTINATION}/"

# --- Inventory report ------------------------------------------------------
generate_report() {
  {
    echo "# Migration Inventory Report"
    echo
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Source: \`$SOURCE\`"
    echo "Destination: \`$DESTINATION\`"
    echo
    echo "## Git state"
    if [[ -d "${DESTINATION}/.git" ]]; then
      echo '```'
      git -C "$DESTINATION" log -1 --format="last commit: %H %ad %s" --date=short 2>&1 || echo "(git log failed)"
      git -C "$DESTINATION" remote -v 2>&1 || echo "(no remotes)"
      echo "uncommitted changes:"
      git -C "$DESTINATION" status --short 2>&1 | head -20
      echo '```'
    else
      echo "No \`.git\` directory found -- not a git repository."
    fi
    echo
    echo "## Compose files found"
    COMPOSE_FILES=$(find "$DESTINATION" -maxdepth 2 -type f \( -iname "docker-compose*.yml" -o -iname "docker-compose*.yaml" -o -iname "compose.yml" -o -iname "compose.yaml" \) 2>/dev/null || true)
    if [[ -n "$COMPOSE_FILES" ]]; then
      echo '```'
      echo "$COMPOSE_FILES"
      echo '```'
    else
      echo "None found at depth <= 2."
    fi
    echo
    echo "## Dockerfiles found"
    DOCKERFILES=$(find "$DESTINATION" \( -path "*/vendor" -o -path "*/node_modules" -o -path "*/.git" \) -prune -o -type f \( -iname "Dockerfile" -o -iname "Dockerfile.*" \) -print 2>/dev/null || true)
    if [[ -n "$DOCKERFILES" ]]; then
      echo '```'
      echo "$DOCKERFILES"
      echo '```'
    else
      echo "None found."
    fi
    echo
    echo "## .env files found (names only -- values not read)"
    ENV_FILES=$(find "$DESTINATION" \( -path "*/vendor" -o -path "*/node_modules" -o -path "*/.git" \) -prune -o -type f \( -iname ".env" -o -iname ".env.*" \) -print 2>/dev/null || true)
    if [[ -n "$ENV_FILES" ]]; then
      echo '```'
      echo "$ENV_FILES"
      echo '```'
    else
      echo "None found."
    fi
    echo
    echo "## Database-looking data folders"
    DB_DIRS=$(find "$DESTINATION" -maxdepth 3 -type d \( -iname "dbdata" -o -iname "db_data" -o -iname "pg_data" -o -iname "mysql_data" \) 2>/dev/null || true)
    if [[ -n "$DB_DIRS" ]]; then
      while IFS= read -r d; do
        SIZE=$(du -sh "$d" 2>/dev/null | cut -f1 || echo "unknown")
        echo "- \`$d\` (approx $SIZE)"
      done <<< "$DB_DIRS"
      echo
      echo "**If any of the above hold real database files, do not rely on this file copy alone --**"
      echo "**take a logical dump (mysqldump/pg_dump) per PROJECT-MIGRATION-CHECKLIST.md Phase 2.**"
    else
      echo "None found."
    fi
    echo
    echo "## Total destination size"
    echo '```'
    du -sh "$DESTINATION" 2>/dev/null || echo "unknown"
    echo '```'
    echo
    echo "## Compose config validation"
    if [[ -n "$COMPOSE_FILES" ]]; then
      FIRST_COMPOSE_FILE=$(echo "$COMPOSE_FILES" | head -1)
      echo "Ran: \`docker compose -f \"$FIRST_COMPOSE_FILE\" config\` (validation only -- no containers started)"
      echo '```'
      (cd "$(dirname "$FIRST_COMPOSE_FILE")" && docker compose -f "$(basename "$FIRST_COMPOSE_FILE")" config 2>&1) || echo "(docker compose config reported errors above)"
      echo '```'
    else
      echo "Skipped -- no Compose file found at the destination."
    fi
  } > "$REPORT_PATH"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_skip "generate migration inventory report -> $REPORT_PATH"
  log_skip "if a compose file is present, run: docker compose -f <file> config"
else
  log_run "generate migration inventory report -> $REPORT_PATH"
  generate_report
  echo
  echo "Report written to: $REPORT_PATH"
fi

echo
echo "Done. No containers were started or stopped. No files were deleted."
echo "No Docker resource (container, image, volume, network) was created,"
echo "removed, or modified. Review the report, then follow"
echo "PROJECT-MIGRATION-CHECKLIST.md for the remaining phases."
