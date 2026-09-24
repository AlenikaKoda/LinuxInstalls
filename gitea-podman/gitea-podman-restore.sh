#!/usr/bin/env bash
#
# gitea-podman-restore.sh
#
# Restores Gitea data from an archive made by gitea-podman-backup.sh. This is
# a destructive operation by nature (it replaces live data), so the defaults
# are the safe ones:
#   - with no --yes, nothing is touched: the archive is verified and a plan
#     is printed. --yes is required to actually restore.
#   - the CURRENT data is never deleted. It is moved aside to a timestamped
#     directory next to it, and stays there until YOU remove it. If the
#     restore turns out to be wrong, moving it back is a straight 'mv'.
#   - the archive is verified (checksum, gzip, tar structure, required
#     members) BEFORE anything live is touched, and the restored database is
#     integrity-checked BEFORE the service is started on top of it -- a
#     restore that fails that check leaves the service stopped rather than
#     start Gitea against data that might make things worse.
#   - --target-root lets you do a full restore "drill" into a scratch
#     directory to prove a backup actually works, without touching the live
#     service or data at all.
#
# Shares gitea-podman-backup.sh's config file and lock, so a backup and a
# restore can never run at the same time.
#
# Usage:   sudo gitea-podman-restore <backup-file.tar.gz> [options]
#     or:  sudo gitea-podman-restore --latest [options]
# Options:
#   --latest              Use the newest backup in BACKUP_DIR instead of a path
#   --yes                  Actually perform a live restore (required; without
#                           it this verifies the archive and prints the plan)
#   --target-root DIR       Extract into DIR instead of the live setup -- a
#                           restore drill. DIR must not already exist. Never
#                           touches the live service, lock, or data.
#   --skip-db-check          Don't run sqlite3 integrity_check (not recommended)
#   --keep-previous / --delete-previous   What to do with the moved-aside pre-
#                           restore data on a FULLY successful restore (default:
#                           keep -- see it named in the summary, remove it
#                           yourself once you've confirmed the restore is good)
#   --wait SECONDS           How long to wait for Gitea to become healthy
#                           after starting it (default 300)
#   --quiet                 Only print warnings and errors
#   -h, --help
#
# Exit codes:  0 restore complete (or, with no --yes, archive verified OK)
#              1 failed -- refused before touching live data, or the archive
#                itself is bad
#              2 usage error
#              3 restore extracted, but the restored database failed its
#                integrity check -- the service was NOT started; your
#                previous data is untouched, at the path printed in the
#                summary
#             75 a backup or restore is already running (lock held)

set -euo pipefail
umask 077

CONF_FILE="${GITEA_PODMAN_CONF:-/etc/gitea-podman/gitea-podman.conf}"
LOCK_FILE="${GITEA_PODMAN_LOCK:-/run/lock/gitea-podman.lock}"

ARCHIVE=""; USE_LATEST=0; CONFIRM=0; TARGET_ROOT=""; SKIP_DB_CHECK=0
KEEP_PREVIOUS=1; WAIT_SECS=300; QUIET=0

DATA_ROOT=""; BACKUP_DIR=""; CONTAINER_NAME=""; UNIT_NAME=""
CONTAINER_UID=""; CONTAINER_GID=""; HTTP_BIND=""; HTTP_PORT=""; HEALTH_URL=""

STOPPED_BY_US=0
WORKDIR_TMP=""
ASIDE_WORK=""; ASIDE_CONFIG=""
DB_REL=""

log()  { if (( ! QUIET )); then printf '%s [+] %s\n' "$(date '+%F %T')" "$*"; fi; }
warn() { printf '%s [!] %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { printf '%s [x] %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

conf_get() { [[ -r "$CONF_FILE" ]] || return 0; sed -n "s/^${1}=//p" "$CONF_FILE" | head -n1; }

ini_get() {   # ini_get <file> <section> <key>
    awk -v sec="$2" -v key="$3" '
        /^[[:space:]]*[;#]/ { next }
        /^[[:space:]]*\[/ { cur = $0; gsub(/[][[:space:]]/, "", cur); next }
        { k = $0; sub(/[[:space:]]*=.*/, "", k); gsub(/^[[:space:]]+/, "", k)
          if (cur == sec && k == key) { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit } }' "$1" 2>/dev/null
}

load_conf() {
    [[ -f "$CONF_FILE" ]] || die "Config file $CONF_FILE not found -- run setup-gitea-podman.sh first (on a fresh machine, run it BEFORE this script, so there is a service and a UID/GID to restore into)."
    local owner mode
    owner="$(stat -c '%u' "$CONF_FILE")"; mode="$(stat -c '%a' "$CONF_FILE")"
    [[ "$owner" == 0 ]] || die "$CONF_FILE must be owned by root."
    (( (8#$mode & 8#022) == 0 )) || die "$CONF_FILE must not be writable by group/others."
    DATA_ROOT="$(conf_get DATA_ROOT)"; BACKUP_DIR="$(conf_get BACKUP_DIR)"
    CONTAINER_NAME="$(conf_get CONTAINER_NAME)"; UNIT_NAME="$(conf_get UNIT_NAME)"
    CONTAINER_UID="$(conf_get CONTAINER_UID)"; CONTAINER_GID="$(conf_get CONTAINER_GID)"
    HTTP_BIND="$(conf_get HTTP_BIND)"; HTTP_PORT="$(conf_get HTTP_PORT)"
    local k
    for k in DATA_ROOT BACKUP_DIR CONTAINER_NAME UNIT_NAME CONTAINER_UID CONTAINER_GID HTTP_BIND HTTP_PORT; do
        [[ -n "${!k}" ]] || die "$k is missing in $CONF_FILE."
    done
    [[ "$DATA_ROOT" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "Suspicious DATA_ROOT in $CONF_FILE."
    local host="$HTTP_BIND"; [[ "$host" != "0.0.0.0" ]] || host="127.0.0.1"
    HEALTH_URL="http://${host}:${HTTP_PORT}/api/healthz"
}

svc_active() {
    local s; s="$(systemctl is-active "$UNIT_NAME" 2>/dev/null || true)"
    case "$s" in active|activating|reloading) return 0 ;; *) return 1 ;; esac
}
container_running() { [[ "$(podman inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]; }
wait_healthy() {
    local limit="$1" i
    for (( i = 0; i < limit; i += 2 )); do
        curl -fsS --max-time 5 -o /dev/null "$HEALTH_URL" 2>/dev/null && return 0
        sleep 2
    done
    return 1
}

# shellcheck disable=SC2329 # invoked via 'trap cleanup EXIT' in main(), not called directly
cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    if [[ -n "$WORKDIR_TMP" && -d "$WORKDIR_TMP" ]]; then rm -rf -- "$WORKDIR_TMP"; fi
    # main() explicitly clears STOPPED_BY_US at every well-handled exit point
    # (success, the DB-integrity-failure case where staying stopped is the
    # point, and right after a successful restart) -- so if it's still 1 here,
    # something unexpected happened between stopping the service and one of
    # those points, and the safest recovery is to try bringing it back up.
    if (( STOPPED_BY_US )); then
        warn "Starting $UNIT_NAME again (best-effort, after an unexpected error)..."
        if systemctl start "$UNIT_NAME" 2>/dev/null; then
            STOPPED_BY_US=0
        else
            warn "!!! COULD NOT START $UNIT_NAME -- start it manually: systemctl start $UNIT_NAME"
        fi
    fi
    exit "$rc"
}

need_arg() { [[ $# -ge 2 ]] || { warn "Option $1 needs a value (see --help)"; exit 2; }; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --latest)          USE_LATEST=1; shift ;;
            --yes)             CONFIRM=1; shift ;;
            --target-root)     need_arg "$@"; TARGET_ROOT="$2"; shift 2 ;;
            --skip-db-check)   SKIP_DB_CHECK=1; shift ;;
            --keep-previous)   KEEP_PREVIOUS=1; shift ;;
            --delete-previous) KEEP_PREVIOUS=0; shift ;;
            --wait)            need_arg "$@"; WAIT_SECS="$2"; shift 2 ;;
            --quiet)           QUIET=1; shift ;;
            -h|--help)         usage; exit 0 ;;
            --) shift; [[ -n "${1:-}" ]] && { ARCHIVE="$1"; shift; }; ;;
            -*) warn "Unknown option: $1 (see --help)"; exit 2 ;;
            *)
                [[ -z "$ARCHIVE" ]] || { warn "Only one backup file may be given (see --help)"; exit 2; }
                ARCHIVE="$1"; shift ;;
        esac
    done
    [[ "$WAIT_SECS" =~ ^[0-9]+$ ]] || { warn "--wait needs a number of seconds"; exit 2; }
    if (( USE_LATEST )) && [[ -n "$ARCHIVE" ]]; then warn "Give either a backup file or --latest, not both."; exit 2; fi
    if (( ! USE_LATEST )) && [[ -z "$ARCHIVE" ]]; then warn "Which backup? Give a path, or --latest (see --help)"; exit 2; fi
}

preflight() {
    [[ $EUID -eq 0 ]] || die "Run this as root (sudo)."
    local c
    for c in podman systemctl tar gzip sha256sum flock curl awk sed stat realpath date mktemp; do
        command -v "$c" >/dev/null 2>&1 || die "Required command not found: $c"
    done
    (( SKIP_DB_CHECK )) || command -v sqlite3 >/dev/null 2>&1 \
        || die "sqlite3 is needed to verify the restored database (install it, or pass --skip-db-check)."
    load_conf

    if (( USE_LATEST )); then
        ARCHIVE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'gitea-backup-????????T??????Z.tar.gz' 2>/dev/null | sort -r | head -n1)"
        [[ -n "$ARCHIVE" ]] || die "No backups matching gitea-backup-*.tar.gz found in $BACKUP_DIR."
        log "Using the newest backup: $(basename -- "$ARCHIVE")"
    fi
    ARCHIVE="$(realpath -e -- "$ARCHIVE" 2>/dev/null)" || die "Backup file not found: $ARCHIVE"
    [[ -r "$ARCHIVE" ]] || die "Cannot read $ARCHIVE."

    if [[ -n "$TARGET_ROOT" ]]; then
        TARGET_ROOT="$(realpath -m -- "$TARGET_ROOT")"
        [[ ! -e "$TARGET_ROOT" ]] || die "--target-root $TARGET_ROOT already exists -- a drill restore refuses to reuse or overwrite an existing path. Pick an empty/new path."
    fi

    systemctl cat "$UNIT_NAME" >/dev/null 2>&1 || [[ -n "$TARGET_ROOT" ]] \
        || die "systemd unit $UNIT_NAME not found -- run setup-gitea-podman.sh first."
}

verify_checksum() {
    local sidecar="${ARCHIVE}.sha256"
    if [[ -f "$sidecar" ]]; then
        log "Verifying checksum against $(basename -- "$sidecar")..."
        ( cd -- "$(dirname -- "$ARCHIVE")" && sha256sum --check --status -- "$(basename -- "$sidecar")" ) \
            || die "Checksum does NOT match $(basename -- "$sidecar") -- refusing to restore from a file that doesn't match its own sidecar. Nothing was touched."
    else
        warn "No .sha256 sidecar next to this archive -- skipping checksum verification (structure/gzip checks below still run)."
    fi
}

verify_structure() {
    log "Verifying archive integrity (gzip + tar structure)..."
    gzip -t -- "$ARCHIVE" || die "gzip integrity test failed on $ARCHIVE -- refusing to restore from it. Nothing was touched."
    WORKDIR_TMP="$(mktemp -d)"
    tar -tzf "$ARCHIVE" > "${WORKDIR_TMP}/listing.txt" || die "tar cannot read $ARCHIVE -- refusing to restore from it. Nothing was touched."
    local m
    for m in BACKUP-INFO.txt config/app.ini work/.gitea-podman-data; do
        grep -qxF -- "$m" "${WORKDIR_TMP}/listing.txt" \
            || die "$ARCHIVE is missing required member '$m' -- this doesn't look like a complete gitea-podman-backup.sh archive. Nothing was touched."
    done
    tar -xzf "$ARCHIVE" -C "$WORKDIR_TMP" --numeric-owner BACKUP-INFO.txt infra config/app.ini 2>/dev/null || true
    # Same technique the backup script itself uses on the live app.ini: read
    # [database] straight from the archived one rather than guess a filename
    # pattern, so this stays correct even if Gitea ever changes the default.
    local app="${WORKDIR_TMP}/config/app.ini" dbtype dbpath
    if [[ -f "$app" ]]; then
        dbtype="$(ini_get "$app" database DB_TYPE)"
        if [[ "$dbtype" == "sqlite3" ]]; then
            dbpath="$(ini_get "$app" database PATH)"
            case "$dbpath" in
                /var/lib/gitea/*) DB_REL="work/${dbpath#/var/lib/gitea/}" ;;
                *) warn "Unexpected SQLite path '$dbpath' in the archived app.ini; the database check will be skipped." ;;
            esac
        fi
    fi
}

print_plan() {
    local info="${WORKDIR_TMP}/BACKUP-INFO.txt" dest="$DATA_ROOT"
    [[ -n "$TARGET_ROOT" ]] && dest="$TARGET_ROOT (drill -- live data and service are not touched)"
    cat <<EOF

============================================================================
 Restore plan
============================================================================
  Archive        $ARCHIVE
  Checksum       $( [[ -f "${ARCHIVE}.sha256" ]] && echo "verified against ${ARCHIVE}.sha256" || echo "no sidecar found -- unverified" )
EOF
    if [[ -f "$info" ]]; then
        sed -nE 's/^created_utc=(.*)/  Backup made    \1/p; s/^gitea_version=(.*)/  Gitea version  \1/p; s/^hostname=(.*)/  From host      \1/p' "$info"
    fi
    cat <<EOF
  Restore into   $dest
EOF
    if [[ -z "$TARGET_ROOT" ]]; then
        cat <<EOF
  Current data   moved aside to a timestamped directory next to $DATA_ROOT, NOT deleted
                 ($( [[ $KEEP_PREVIOUS -eq 1 ]] && echo "kept after a successful restore -- remove it yourself once you've checked things over" || echo "deleted automatically once the restore succeeds and Gitea is healthy" ))
EOF
    fi
    if (( ! CONFIRM )) && [[ -z "$TARGET_ROOT" ]]; then
        cat <<EOF

Nothing has been touched. Re-run with --yes to actually restore.
============================================================================
EOF
    else
        echo "============================================================================"
    fi
}

do_drill() {
    log "Extracting into $TARGET_ROOT for inspection (service and live data untouched)..."
    mkdir -p -- "$TARGET_ROOT"
    tar -xzf "$ARCHIVE" -C "$TARGET_ROOT" --numeric-owner || die "Extraction into $TARGET_ROOT failed."
    local rc=0
    if (( ! SKIP_DB_CHECK )) && [[ -n "$DB_REL" && -f "${TARGET_ROOT}/${DB_REL}" ]]; then
        local res; res="$(sqlite3 "${TARGET_ROOT}/${DB_REL}" 'PRAGMA integrity_check;' 2>&1 || true)"
        if [[ "$res" == "ok" ]]; then
            log "SQLite integrity_check: ok"
        else
            warn "SQLite integrity_check FAILED on the extracted database:"
            printf '%s\n' "$res" | head -n 8 | sed 's/^/        /' >&2
            rc=3
        fi
    fi
    log "Drill extraction complete: $TARGET_ROOT"
    log "Nothing on the live system was touched. Remove $TARGET_ROOT yourself when done inspecting it."
    exit "$rc"
}

stop_service() {
    if svc_active; then
        log "Stopping $UNIT_NAME (graceful; up to 2.5 min)..."
        STOPPED_BY_US=1
        systemctl stop "$UNIT_NAME" || die "Could not stop $UNIT_NAME. Nothing was moved or overwritten."
    else
        log "$UNIT_NAME is not running; proceeding."
    fi
    if container_running; then
        die "Container $CONTAINER_NAME is still running after the stop -- refusing to touch live data."
    fi
}

move_aside_current_data() {
    local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
    ASIDE_WORK="${DATA_ROOT}/work.before-restore-${ts}"
    ASIDE_CONFIG="${DATA_ROOT}/config.before-restore-${ts}"
    log "Moving current data aside (not deleting): $(basename -- "$ASIDE_WORK"), $(basename -- "$ASIDE_CONFIG")"
    if [[ -d "${DATA_ROOT}/work" ]]; then
        mv -T -- "${DATA_ROOT}/work" "$ASIDE_WORK" || die "Could not move ${DATA_ROOT}/work aside -- stopping before anything is overwritten."
    fi
    if [[ -d "${DATA_ROOT}/config" ]]; then
        mv -T -- "${DATA_ROOT}/config" "$ASIDE_CONFIG" || die "Could not move ${DATA_ROOT}/config aside -- stopping before anything is overwritten."
    fi
}

extract_data() {
    log "Extracting archive into $DATA_ROOT..."
    mkdir -p -- "$DATA_ROOT"
    tar -xzf "$ARCHIVE" -C "$DATA_ROOT" --numeric-owner config work \
        || die "Extraction failed. Your previous data is untouched at $(basename -- "$ASIDE_WORK") / $(basename -- "$ASIDE_CONFIG")."
    chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "${DATA_ROOT}/work" "${DATA_ROOT}/config"
    chmod 750 "${DATA_ROOT}/work"
    chmod 700 "${DATA_ROOT}/config"
    find "${DATA_ROOT}/config" -type f -exec chmod 600 {} +
}

check_restored_db() {
    (( ! SKIP_DB_CHECK )) || { warn "--skip-db-check: not verifying the restored database before starting Gitea."; return 0; }
    [[ -n "$DB_REL" ]] || { warn "Could not identify the database file in the archive; skipping the integrity check."; return 0; }
    local path="${DATA_ROOT}/${DB_REL}"
    [[ -f "$path" ]] || { warn "Expected database at $path was not found after extraction; skipping the integrity check."; return 0; }
    log "Checking the restored database before starting Gitea..."
    local res; res="$(sqlite3 "$path" 'PRAGMA integrity_check;' 2>&1 || true)"
    if [[ "$res" == "ok" ]]; then
        log "SQLite integrity_check: ok"
        return 0
    fi
    warn "SQLite integrity_check FAILED on the restored database:"
    printf '%s\n' "$res" | head -n 8 | sed 's/^/        /' >&2
    return 1
}

# ----------------------------------------------------------------------------
main() {
    parse_args "$@"
    preflight
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    verify_checksum
    verify_structure

    if [[ -n "$TARGET_ROOT" ]]; then
        print_plan
        do_drill
    fi

    print_plan
    if (( ! CONFIRM )); then
        log "Archive verified OK. Add --yes to actually restore."
        exit 0
    fi

    stop_service
    move_aside_current_data
    extract_data

    if ! check_restored_db; then
        warn "NOT starting $UNIT_NAME on top of a database that failed its integrity check."
        warn "Your previous data is intact at:"
        warn "  $ASIDE_WORK"
        warn "  $ASIDE_CONFIG"
        warn "To go back: stop here, remove what was just extracted, and move those two back into place."
        STOPPED_BY_US=0   # leaving it stopped is the point; the cleanup trap should not try to start it
        exit 3
    fi

    log "Starting $UNIT_NAME..."
    systemctl start "$UNIT_NAME" || {
        warn "COULD NOT START $UNIT_NAME after the restore. The restored data is in place at $DATA_ROOT;"
        warn "your previous data is intact at $ASIDE_WORK / $ASIDE_CONFIG if you need to revert."
        exit 1
    }
    STOPPED_BY_US=0

    local rc=0
    log "Waiting for Gitea to answer on $HEALTH_URL ..."
    if wait_healthy "$WAIT_SECS"; then
        log "Gitea is healthy again."
    else
        warn "Gitea did not become healthy within ${WAIT_SECS}s after the restore. Check: journalctl -u $UNIT_NAME"
        rc=3
    fi

    if (( rc == 0 )); then
        if (( KEEP_PREVIOUS )); then
            log "DONE. Your data before this restore is kept at:"
            log "  $ASIDE_WORK"
            log "  $ASIDE_CONFIG"
            log "Remove those yourself once you've confirmed the restore looks right."
        else
            log "Restore succeeded and Gitea is healthy; removing the pre-restore copy (--delete-previous)..."
            rm -rf -- "$ASIDE_WORK" "$ASIDE_CONFIG"
            log "DONE."
        fi
    else
        warn "Restore extracted and started, but needs attention (see above). Your data before this"
        warn "restore is still kept at $ASIDE_WORK / $ASIDE_CONFIG regardless of --delete-previous."
    fi
    exit "$rc"
}

if [[ "${GITEA_PODMAN_RESTORE_RELAUNCHED:-}" != "1" ]]; then
    for a in "$@"; do [[ "$a" == "-h" || "$a" == "--help" ]] && { usage; exit 0; }; done
    mkdir -p -- "$(dirname -- "$LOCK_FILE")"
    export GITEA_PODMAN_RESTORE_RELAUNCHED=1
    rc=0
    flock -n -E 75 "$LOCK_FILE" "$0" "$@" || rc=$?
    [[ $rc -eq 75 ]] && warn "A backup or restore is already running (lock: $LOCK_FILE)."
    exit "$rc"
fi

main "$@"
