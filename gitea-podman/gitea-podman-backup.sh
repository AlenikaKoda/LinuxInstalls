#!/usr/bin/env bash
#
# gitea-podman-backup.sh
#
# Creates a consistent, verified backup of ALL data of the Gitea container installed by
# setup-gitea-podman.sh: repositories, SQLite database, LFS objects, attachments, avatars,
# packages, SSH host keys, custom/ files and app.ini (whose secrets the encrypted data in
# the database depends on -- a database backup without them is not restorable).
#
# How it stays consistent
#   The service is stopped (gracefully, so Gitea and SQLite shut down cleanly), the data
#   directories are archived while nothing can write to them, and the service is started
#   again. Typical downtime: seconds to a few minutes, depending on the amount of data.
#   The service is ALWAYS started again if this script stopped it -- also on errors and
#   on Ctrl-C/SIGTERM.
#
# What "verified" means (all of it happens before an old backup could ever be pruned)
#   1. the archive is written under a temporary name (*.partial) and only renamed into
#      place after everything below succeeded, so a crash never leaves a half-written
#      file that looks like a backup;
#   2. gzip integrity test + tar structure test + required members are present;
#   3. the archive is compared byte-for-byte against the live data (tar --compare) while
#      the service is still stopped (skip with --fast);
#   4. a SHA-256 sidecar file is written next to the archive;
#   5. after the restart, the SQLite database inside the archive is extracted to a scratch
#      directory and checked with PRAGMA integrity_check.
#
# Retention: with --keep N the newest N backups are kept and older ones deleted -- but only
# after the new backup passed every check, and only files this script named itself.
# Without --keep nothing is ever deleted.
#
# Usage:   sudo gitea-podman-backup [options]
# Options:
#   --dest DIR         backup directory (default: BACKUP_DIR from the config file)
#   --keep N           keep only the newest N backups (N >= 1) after a fully successful run
#   --dry-run          check everything and print the plan, but stop/change nothing
#   --fast             skip the byte-for-byte comparison (shorter downtime, weaker check)
#   --skip-db-check    don't run sqlite3 integrity_check on the archived database
#   --wait SECONDS     how long to wait for Gitea to be healthy again (default 300)
#   --quiet            only print warnings and errors (for timers/cron)
#   -h, --help
#
# Exit codes:  0 backup complete and verified
#              1 failed -- no new backup was created (the service was restarted)
#              2 usage error
#              3 backup file created, but a post-check needs attention (database
#                integrity problem, or Gitea not healthy after the restart) -- old
#                backups were NOT pruned
#             75 another backup/restore is running (lock held)
#
# Backups contain secrets (app.ini, password hashes, 2FA seeds): they are written with
# mode 0600 in a 0700 directory. Copy them off this machine -- a backup on the same disk
# does not protect against losing the disk.

set -euo pipefail
umask 077

SCRIPT_VERSION="1"
CONF_FILE="${GITEA_PODMAN_CONF:-/etc/gitea-podman/gitea-podman.conf}"
LOCK_FILE="${GITEA_PODMAN_LOCK:-/run/lock/gitea-podman.lock}"
QUADLET_DIR="${GITEA_QUADLET_DIR:-/etc/containers/systemd}"

OPT_DEST=""; OPT_KEEP=""; DRY_RUN=0; FAST=0; QUIET=0; SKIP_DB_CHECK=0; WAIT_SECS=300

# Filled from the config file
DATA_ROOT=""; BACKUP_DIR=""; CONTAINER_NAME=""; UNIT_NAME=""; IMAGE=""
CONTAINER_UID=""; CONTAINER_GID=""; HTTP_BIND=""; HTTP_PORT=""; HEALTH_URL=""

# Run state, used by the cleanup trap
STOPPED_BY_US=0
WORKDIR_TMP=""
PARTIAL=""
FINAL=""
IMAGE_ID=""; IMAGE_DIGEST=""; GITEA_VERSION_TAG="unknown"
WORK_BYTES=0; CONFIG_BYTES=0
DOWNTIME_SECS=0

log()  { if (( ! QUIET )); then printf '%s [+] %s\n' "$(date '+%F %T')" "$*"; fi; }
warn() { printf '%s [!] %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { printf '%s [x] %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ----------------------------------------------------------------------------
# Config file (plain KEY=value lines written by the setup script; never sourced)
# ----------------------------------------------------------------------------
conf_get() {
    [[ -r "$CONF_FILE" ]] || return 0
    sed -n "s/^${1}=//p" "$CONF_FILE" | head -n1
}

ini_get() {   # ini_get <file> <section> <key>
    awk -v sec="$2" -v key="$3" '
        /^[[:space:]]*[;#]/ { next }
        /^[[:space:]]*\[/ { cur = $0; gsub(/[][[:space:]]/, "", cur); next }
        { k = $0; sub(/[[:space:]]*=.*/, "", k); gsub(/^[[:space:]]+/, "", k)
          if (cur == sec && k == key) { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit } }' "$1"
}

load_conf() {
    [[ -f "$CONF_FILE" ]] || die "Config file $CONF_FILE not found -- run setup-gitea-podman.sh first."
    local owner mode
    owner="$(stat -c '%u' "$CONF_FILE")"; mode="$(stat -c '%a' "$CONF_FILE")"
    [[ "$owner" == 0 ]] || die "$CONF_FILE must be owned by root."
    (( (8#$mode & 8#022) == 0 )) || die "$CONF_FILE must not be writable by group/others."

    DATA_ROOT="$(conf_get DATA_ROOT)"
    BACKUP_DIR="$(conf_get BACKUP_DIR)"
    CONTAINER_NAME="$(conf_get CONTAINER_NAME)"
    UNIT_NAME="$(conf_get UNIT_NAME)"
    IMAGE="$(conf_get IMAGE)"
    CONTAINER_UID="$(conf_get CONTAINER_UID)"
    CONTAINER_GID="$(conf_get CONTAINER_GID)"
    HTTP_BIND="$(conf_get HTTP_BIND)"
    HTTP_PORT="$(conf_get HTTP_PORT)"
    local k
    for k in DATA_ROOT BACKUP_DIR CONTAINER_NAME UNIT_NAME IMAGE CONTAINER_UID CONTAINER_GID HTTP_BIND HTTP_PORT; do
        [[ -n "${!k}" ]] || die "$k is missing in $CONF_FILE."
    done
    [[ "$DATA_ROOT" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "Suspicious DATA_ROOT in $CONF_FILE."
    [[ "$BACKUP_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "Suspicious BACKUP_DIR in $CONF_FILE."
    local host="$HTTP_BIND"
    [[ "$host" != "0.0.0.0" ]] || host="127.0.0.1"
    HEALTH_URL="http://${host}:${HTTP_PORT}/api/healthz"
}

# ----------------------------------------------------------------------------
# Service helpers
# ----------------------------------------------------------------------------
svc_active() {
    local s
    s="$(systemctl is-active "$UNIT_NAME" 2>/dev/null || true)"
    case "$s" in active|activating|reloading) return 0 ;; *) return 1 ;; esac
}

container_running() {
    [[ "$(podman inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]
}

wait_healthy() {   # wait_healthy <seconds>
    local limit="$1" i
    for (( i = 0; i < limit; i += 2 )); do
        if curl -fsS --max-time 5 -o /dev/null "$HEALTH_URL" 2>/dev/null; then return 0; fi
        sleep 2
    done
    return 1
}

# ----------------------------------------------------------------------------
# Cleanup: always undo what we changed (partial files, temp dir, stopped service)
# ----------------------------------------------------------------------------
# shellcheck disable=SC2329 # invoked via 'trap cleanup EXIT', not called directly
cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    if [[ -n "$PARTIAL" && -e "$PARTIAL" ]]; then rm -f -- "$PARTIAL"; fi
    if [[ -n "$WORKDIR_TMP" && -d "$WORKDIR_TMP" && "$WORKDIR_TMP" == "${BACKUP_DIR}/.tmp."* ]]; then
        rm -rf -- "$WORKDIR_TMP"
    fi
    if (( STOPPED_BY_US )); then
        warn "Starting $UNIT_NAME again (it was stopped for the backup)..."
        if systemctl start "$UNIT_NAME"; then
            STOPPED_BY_US=0
        else
            warn "!!! COULD NOT START $UNIT_NAME -- start it manually: systemctl start $UNIT_NAME"
            (( rc != 0 )) || rc=1
        fi
    fi
    exit "$rc"
}

# ----------------------------------------------------------------------------
# Arguments
# ----------------------------------------------------------------------------
need_arg() { [[ $# -ge 2 ]] || { warn "Option $1 needs a value (see --help)"; exit 2; }; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dest)          need_arg "$@"; OPT_DEST="$2"; shift 2 ;;
            --keep)          need_arg "$@"; OPT_KEEP="$2"; shift 2 ;;
            --wait)          need_arg "$@"; WAIT_SECS="$2"; shift 2 ;;
            --dry-run)       DRY_RUN=1; shift ;;
            --fast)          FAST=1; shift ;;
            --skip-db-check) SKIP_DB_CHECK=1; shift ;;
            --quiet)         QUIET=1; shift ;;
            -h|--help)       usage; exit 0 ;;
            *) warn "Unknown option: $1 (see --help)"; exit 2 ;;
        esac
    done
    if [[ -n "$OPT_KEEP" ]]; then
        if [[ ! "$OPT_KEEP" =~ ^[0-9]+$ ]] || (( OPT_KEEP < 1 )); then
            warn "--keep needs a number >= 1"; exit 2
        fi
    fi
    [[ "$WAIT_SECS" =~ ^[0-9]+$ ]] || { warn "--wait needs a number of seconds"; exit 2; }
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------
preflight() {
    [[ $EUID -eq 0 ]] || die "Run this as root (sudo)."
    local c
    for c in podman systemctl tar gzip sha256sum flock curl awk sed df du stat realpath date; do
        command -v "$c" >/dev/null 2>&1 || die "Required command not found: $c"
    done
    if (( ! SKIP_DB_CHECK )); then
        command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is needed to verify the database backup (install it, or pass --skip-db-check)."
    fi
    load_conf
    [[ -n "$OPT_DEST" ]] && BACKUP_DIR="$OPT_DEST"
    [[ "$BACKUP_DIR" =~ ^/[A-Za-z0-9_./-]+$ ]] || die "--dest must be an absolute path (letters, digits, _ . / - only)."

    [[ -d "$DATA_ROOT/work" && -d "$DATA_ROOT/config" ]] \
        || die "$DATA_ROOT/work or $DATA_ROOT/config is missing -- is the data disk mounted? Refusing to back up an empty tree."
    [[ -f "$DATA_ROOT/config/app.ini" ]] || die "$DATA_ROOT/config/app.ini is missing -- refusing to make a backup without the config/secrets."
    [[ -e "$DATA_ROOT/work/.gitea-podman-data" ]] \
        || die "Marker file $DATA_ROOT/work/.gitea-podman-data is missing -- this does not look like the Gitea data directory."
    systemctl cat "$UNIT_NAME" >/dev/null 2>&1 || die "systemd unit $UNIT_NAME not found -- run setup-gitea-podman.sh first."

    # The backup directory must be separate from the data it protects.
    local rd rb
    rd="$(realpath -m -- "$DATA_ROOT")"; rb="$(realpath -m -- "$BACKUP_DIR")"
    case "$rb/" in "$rd/"*) die "Backup directory $rb is inside the data directory $rd." ;; esac
    case "$rd/" in "$rb/"*) die "Data directory $rd is inside the backup directory $rb." ;; esac
    BACKUP_DIR="$rb"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        if (( DRY_RUN )); then log "(dry-run) would create $BACKUP_DIR"; else mkdir -p -- "$BACKUP_DIR"; chmod 0700 -- "$BACKUP_DIR"; fi
    fi
    if [[ -d "$BACKUP_DIR" ]]; then
        [[ -w "$BACKUP_DIR" ]] || die "$BACKUP_DIR is not writable."
        if [[ "$(stat -c %d -- "$DATA_ROOT")" == "$(stat -c %d -- "$BACKUP_DIR")" ]]; then
            warn "$BACKUP_DIR is on the same filesystem as the data: this does not protect against disk failure. Copy the backups elsewhere too."
        fi
    fi
}

check_space() {
    WORK_BYTES="$(du -sb -- "$DATA_ROOT/work" | awk '{print $1}')"
    CONFIG_BYTES="$(du -sb -- "$DATA_ROOT/config" | awk '{print $1}')"
    local used need avail probe="$BACKUP_DIR"
    used=$(( WORK_BYTES + CONFIG_BYTES ))
    need=$(( used + used / 10 + 268435456 ))          # +10% and 256 MiB headroom, assuming zero compression
    [[ -d "$probe" ]] || probe="$(dirname -- "$BACKUP_DIR")"
    avail="$(df -B1 --output=avail -- "$probe" | tail -n1 | tr -d ' ')"
    log "Data size: $(numfmt --to=iec "$used"); free space in backup dir: $(numfmt --to=iec "$avail")"
    if (( avail < need )); then
        die "Not enough free space for a safe backup: need about $(numfmt --to=iec "$need"), have $(numfmt --to=iec "$avail"). Nothing was stopped or changed."
    fi
}

collect_info() {   # while the container still exists
    IMAGE_ID="$(podman image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || true)"
    IMAGE_DIGEST="$(podman image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$IMAGE" 2>/dev/null || true)"
    local v
    v="$(sed -nE 's/.*:([0-9]+\.[0-9]+\.[0-9]+)(-rootless)?$/\1/p' <<<"$IMAGE")"
    GITEA_VERSION_TAG="${v:-unknown}"
}

warn_if_data_outside_volumes() {   # data written to the container's own layer would NOT be in the backup
    container_running || return 0
    local unexpected
    # podman diff reports the two bind-mount points themselves (and their parent
    # directory chain, created as a side effect of setting up the mount) as "added"
    # even though their CONTENTS are the host volumes, not container-layer writes.
    # Excluding exactly those directories (not their contents) leaves genuine
    # container-layer writes elsewhere still flagged.
    unexpected="$(podman diff "$CONTAINER_NAME" 2>/dev/null | awk '
        $2 == "/etc" || $2 == "/tmp" || $2 ~ /^\/tmp\// || $2 == "/run" || $2 ~ /^\/run\// || $2 ~ /^\/dev\// { next }
        $2 == "/etc/gitea" || $2 == "/var" || $2 == "/var/lib" || $2 == "/var/lib/gitea" { next }
        { print }' | head -n 10)" || true
    if [[ -n "$unexpected" ]]; then
        warn "The container has files OUTSIDE its persistent volumes; they are NOT covered by this backup:"
        printf '%s\n' "$unexpected" | sed 's/^/        /' >&2
    fi
}

stop_service() {
    if svc_active; then
        log "Stopping $UNIT_NAME (graceful; up to 2.5 min)..."
        STOPPED_BY_US=1                       # set first: an interrupted/failed stop is undone by the trap too
        systemctl stop "$UNIT_NAME" || die "Could not stop $UNIT_NAME."
    else
        log "$UNIT_NAME is not running; backing up the data as it is."
    fi
    if container_running; then
        die "Container $CONTAINER_NAME is still running after the stop -- refusing to back up live data."
    fi
}

write_manifest() {
    local f="$WORKDIR_TMP/BACKUP-INFO.txt" app="$DATA_ROOT/config/app.ini"
    mkdir -p -- "$WORKDIR_TMP/infra"
    [[ -f "$CONF_FILE" ]] && cp -p -- "$CONF_FILE" "$WORKDIR_TMP/infra/gitea-podman.conf"
    local q="${QUADLET_DIR}/${UNIT_NAME%.service}.container"
    [[ -f "$q" ]] && cp -p -- "$q" "$WORKDIR_TMP/infra/$(basename -- "$q")"
    {
        echo "format=1"
        echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "hostname=$(hostname 2>/dev/null || echo unknown)"
        echo "script_version=$SCRIPT_VERSION"
        echo "container=$CONTAINER_NAME"
        echo "image=$IMAGE"
        echo "image_id=$IMAGE_ID"
        echo "image_digest=$IMAGE_DIGEST"
        echo "gitea_version=$GITEA_VERSION_TAG"
        echo "data_root=$DATA_ROOT"
        echo "container_uid=$CONTAINER_UID"
        echo "container_gid=$CONTAINER_GID"
        echo "work_bytes=$WORK_BYTES"
        echo "config_bytes=$CONFIG_BYTES"
        echo "db_type=$(ini_get "$app" database DB_TYPE)"
        echo "root_url=$(ini_get "$app" server ROOT_URL)"
        echo "ssh_port=$(ini_get "$app" server SSH_PORT)"
    } > "$f"
}

create_archive() {
    log "Archiving $DATA_ROOT/{work,config} -> $(basename -- "$PARTIAL") ..."
    local st
    set +e
    tar --create --file=- --numeric-owner \
        -C "$WORKDIR_TMP" BACKUP-INFO.txt infra \
        -C "$DATA_ROOT" config work \
        | gzip -c > "$PARTIAL"
    st=("${PIPESTATUS[@]}")
    set -e
    # tar exit 1 means "a file changed while being read" -- unacceptable for a consistent snapshot.
    [[ "${st[0]}" -eq 0 && "${st[1]}" -eq 0 ]] || die "Archiving failed (tar exit ${st[0]}, gzip exit ${st[1]}); no backup was created."
    sync -f -- "$PARTIAL" || true
}

verify_archive_structure() {
    log "Verifying archive integrity..."
    gzip -t -- "$PARTIAL" || die "gzip integrity test failed -- discarding the archive."
    tar -tzf "$PARTIAL" > "$WORKDIR_TMP/listing.txt" || die "tar cannot read the archive back -- discarding it."
    local m
    for m in BACKUP-INFO.txt config/app.ini work/.gitea-podman-data; do
        grep -qxF -- "$m" "$WORKDIR_TMP/listing.txt" || die "Archive is missing required member '$m' -- discarding it."
    done
    if [[ "$DB_REL" != "" ]]; then
        grep -qxF -- "$DB_REL" "$WORKDIR_TMP/listing.txt" || die "Archive is missing the database file '$DB_REL' -- discarding it."
    fi
}

verify_archive_content() {
    if (( FAST )); then
        warn "--fast: skipping the byte-for-byte comparison of the archive with the live data."
        return 0
    fi
    log "Comparing the archive with the (stopped) data, byte for byte..."
    tar -dzf "$PARTIAL" --numeric-owner -C "$DATA_ROOT" config work \
        || die "The archive does NOT match the data on disk -- discarding it (nothing was pruned)."
    tar -dzf "$PARTIAL" --numeric-owner -C "$WORKDIR_TMP" BACKUP-INFO.txt infra \
        || die "The archive's metadata does not match -- discarding it."
}

finalize_archive() {
    local hash
    hash="$(sha256sum -- "$PARTIAL" | awk '{print $1}')"
    [[ -n "$hash" ]] || die "Could not compute the SHA-256 of the archive."
    # Sidecar first, archive last: a crash in between leaves at most an orphan sidecar.
    printf '%s  %s\n' "$hash" "$(basename -- "$FINAL")" > "${FINAL}.sha256.tmp"
    mv -T -- "${FINAL}.sha256.tmp" "${FINAL}.sha256"
    [[ ! -e "$FINAL" ]] || die "$FINAL already exists -- refusing to overwrite a backup."
    mv -T -- "$PARTIAL" "$FINAL"
    PARTIAL=""
    sync -f -- "$BACKUP_DIR" || true
    ARCHIVE_SHA="$hash"
}

restart_service() {
    (( STOPPED_BY_US )) || return 0
    log "Starting $UNIT_NAME again..."
    systemctl start "$UNIT_NAME" || die "COULD NOT START $UNIT_NAME (the backup itself is safe): start it manually."
    STOPPED_BY_US=0
    DOWNTIME_SECS=$(( SECONDS - T_STOP ))
}

post_verify() {   # exit-status contract: number of problems found
    local problems=0
    log "Re-checking the finished archive..."
    if ! ( cd -- "$BACKUP_DIR" && sha256sum --check --status -- "$(basename -- "$FINAL").sha256" ); then
        warn "SHA-256 of the finished archive does not match its sidecar file!"
        problems=$(( problems + 1 ))
    fi
    if (( ! SKIP_DB_CHECK )) && [[ -n "$DB_REL" ]]; then
        local tmp="$WORKDIR_TMP/dbcheck" res
        mkdir -p -- "$tmp"
        if tar -xzf "$FINAL" -C "$tmp" --numeric-owner --wildcards "${DB_REL}*" 2>/dev/null && [[ -f "$tmp/$DB_REL" ]]; then
            res="$(sqlite3 "$tmp/$DB_REL" 'PRAGMA integrity_check;' 2>&1 || true)"
            if [[ "$res" == "ok" ]]; then
                log "SQLite integrity_check on the archived database: ok"
            else
                warn "SQLite integrity_check on the archived database FAILED:"
                printf '%s\n' "$res" | head -n 8 | sed 's/^/        /' >&2
                problems=$(( problems + 1 ))
            fi
        else
            warn "Could not extract the database from the archive for the integrity check."
            problems=$(( problems + 1 ))
        fi
    fi
    return "$problems"
}

prune_old() {
    [[ -n "$OPT_KEEP" ]] || return 0
    local f n=0 removed=0
    while IFS= read -r f; do
        n=$(( n + 1 ))
        if (( n > OPT_KEEP )); then
            log "Pruning old backup: $(basename -- "$f")"
            rm -f -- "$f" "${f}.sha256"
            removed=$(( removed + 1 ))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'gitea-backup-????????T??????Z.tar.gz' | sort -r)
    log "Retention: keeping the newest $OPT_KEEP; removed $removed."
}

cleanup_stale() {   # leftovers of a crashed earlier run (we hold the lock, so nobody else is using them)
    [[ -d "$BACKUP_DIR" ]] || return 0
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'gitea-backup-*.tar.gz.partial' -delete
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'gitea-backup-*.sha256.tmp' -delete
    find "$BACKUP_DIR" -maxdepth 1 -type d -name '.tmp.*' -exec rm -rf -- {} +
}

# ----------------------------------------------------------------------------
main() {
    parse_args "$@"
    preflight

    local app="$DATA_ROOT/config/app.ini" dbtype dbpath
    dbtype="$(ini_get "$app" database DB_TYPE)"
    DB_REL=""
    if [[ "$dbtype" == "sqlite3" ]]; then
        dbpath="$(ini_get "$app" database PATH)"
        case "$dbpath" in
            /var/lib/gitea/*) DB_REL="work/${dbpath#/var/lib/gitea/}" ;;
            *) warn "Unexpected SQLite path '$dbpath' in app.ini; the database check will be skipped." ;;
        esac
    else
        warn "DB_TYPE is '${dbtype:-unset}', not sqlite3 -- this script only knows how to verify SQLite."
    fi

    # Locking is handled by the flock wrapper at the bottom of this file -- by
    # the time main() runs, the lock is already held for this whole invocation.
    check_space
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    FINAL="${BACKUP_DIR}/gitea-backup-${ts}.tar.gz"

    if (( DRY_RUN )); then
        log "(dry-run) would stop $UNIT_NAME, write $FINAL (+ .sha256), verify it and start the service again."
        [[ -n "$OPT_KEEP" ]] && log "(dry-run) would then keep only the newest $OPT_KEEP backups."
        exit 0
    fi

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    cleanup_stale
    WORKDIR_TMP="$(mktemp -d "${BACKUP_DIR}/.tmp.XXXXXXXX")"
    PARTIAL="${FINAL}.partial"

    warn_if_data_outside_volumes
    collect_info
    local was_active=0
    if svc_active; then was_active=1; fi

    if (( ! was_active )) && container_running; then
        die "Container $CONTAINER_NAME is running but $UNIT_NAME is not active -- it is not managed by systemd; refusing to touch it."
    fi

    stop_service
    T_STOP=$SECONDS
    write_manifest
    create_archive
    verify_archive_structure
    verify_archive_content
    finalize_archive
    if (( was_active )); then restart_service; else DOWNTIME_SECS=$(( SECONDS - T_STOP )); fi

    local rc=0
    if (( was_active )); then
        log "Waiting for Gitea to answer on $HEALTH_URL ..."
        if wait_healthy "$WAIT_SECS"; then
            log "Gitea is healthy again."
        else
            warn "Gitea did not become healthy within ${WAIT_SECS}s after the restart (the backup itself is complete). Check: journalctl -u $UNIT_NAME"
            rc=3
        fi
    fi

    if ! post_verify; then rc=3; fi

    local size
    size="$(numfmt --to=iec "$(stat -c %s -- "$FINAL")")"
    if (( rc == 0 )); then
        prune_old
        log "DONE: $FINAL ($size), sha256 ${ARCHIVE_SHA:0:16}..., downtime ${DOWNTIME_SECS}s."
    else
        warn "Backup written to $FINAL ($size) but needs attention (see above). Old backups were NOT pruned."
    fi
    exit "$rc"
}

# One backup/restore at a time -- for real, this time. A plain 'exec 9>lockfile;
# flock -n 9' inside main() looks right but isn't: that fd has no close-on-exec
# set, so the instant this script starts the Gitea container, podman's conmon
# (a daemon that outlives this script entirely) inherits it via fork/exec and
# keeps the lock held forever -- every later backup would then wedge on a false
# "already running", from someone who last looked stopped the container weeks
# ago. Relaunching under the external `flock` command sidesteps this: flock
# opens the lockfile itself with O_CLOEXEC, so the fd is already gone by the
# time this script (running as flock's child) even starts, and nothing this
# script spawns can inherit what it never had.
if [[ "${GITEA_PODMAN_BACKUP_RELAUNCHED:-}" != "1" ]]; then
    for a in "$@"; do [[ "$a" == "-h" || "$a" == "--help" ]] && { usage; exit 0; }; done
    mkdir -p -- "$(dirname -- "$LOCK_FILE")"
    export GITEA_PODMAN_BACKUP_RELAUNCHED=1
    rc=0
    flock -n -E 75 "$LOCK_FILE" "$0" "$@" || rc=$?
    [[ $rc -eq 75 ]] && warn "Another gitea-podman backup/restore is running (lock: $LOCK_FILE)."
    exit "$rc"
fi

main "$@"
