#!/usr/bin/env bash
#
# setup-gitea-podman.sh
#
# Runs Gitea (https://about.gitea.com) as a rootless-IMAGE container under
# ROOTFUL Podman + systemd (Quadlet), on a fresh Linux box. This is the
# Podman counterpart to setup-git-server.sh; read that script's header for
# the overall goals (GitHub-style SSH access, push-to-create). The container
# architecture differs in one important way: there is no host sshd involved.
# Gitea's OWN built-in SSH server runs inside the container and is published
# to the host, so there are no OS user accounts to manage -- SSH keys are
# tied to Gitea accounts in its database, exactly like GitHub.
#
# All persistent data lives OUTSIDE the container, under --data-root
# (default /srv/gitea), in two directories bind-mounted in:
#   <data-root>/work    -> /var/lib/gitea  (repos, sqlite db, LFS, avatars, SSH host keys)
#   <data-root>/config  -> /etc/gitea      (app.ini -- also holds the secrets the
#                                            database's encrypted columns depend on)
# The container itself is disposable: `podman rm` it, or even reinstall this
# script against the same --data-root, and nothing is lost. Use
# gitea-podman-backup.sh / gitea-podman-restore.sh to back up and restore
# that data; this script only sets the container up.
#
# Requires: a Podman new enough to generate systemd units from Quadlet
# (.container) files (Podman >= 4.4) -- this is checked, not assumed.
#
# Supported distros: Arch, Debian, Ubuntu, Fedora (and close derivatives).
# Must be run as root on a machine where systemd is actually running (a VM
# or bare metal -- not a plain Docker container). Written for a first-time
# install; re-running it over an existing --data-root reuses the existing
# secrets and accounts and just brings the container up to date.
#
# Usage:
#   sudo ./setup-gitea-podman.sh [options]
#
# Run with --help for the full list of options.

set -euo pipefail
umask 022

# ----------------------------------------------------------------------------
# Defaults (overridable via env vars, then via flags below)
# ----------------------------------------------------------------------------
GITEA_DATA_ROOT="${GITEA_DATA_ROOT:-/srv/gitea}"
GITEA_BACKUP_DIR="${GITEA_BACKUP_DIR:-/srv/gitea-backups}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-22}"
GITEA_DOMAIN="${GITEA_DOMAIN:-}"
GITEA_VERSION="${GITEA_VERSION:-latest}"
GITEA_DISABLE_REGISTRATION="${GITEA_DISABLE_REGISTRATION:-true}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-admin}"
GITEA_ADMIN_EMAIL="${GITEA_ADMIN_EMAIL:-admin@example.com}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-}"
GITEA_CONTAINER_UID="${GITEA_CONTAINER_UID:-1000}"
GITEA_CONTAINER_GID="${GITEA_CONTAINER_GID:-1000}"

# Fixed by the image; not meant to be tuned per-install.
readonly SSH_LISTEN_PORT=2222
readonly CONTAINER_NAME="gitea"
readonly UNIT_NAME="gitea.service"
readonly QUADLET_DIR="/etc/containers/systemd"
readonly QUADLET_FILE="${QUADLET_DIR}/gitea.container"
readonly CONF_DIR="/etc/gitea-podman"
readonly CONF_FILE="${CONF_DIR}/gitea-podman.conf"

# Filled in while the script runs
DISTRO_FAMILY=""
IMAGE=""
GITEA_INSTALLED_VERSION=""
ADMIN_CREATED="false"

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------
C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_RESET='\033[0m'
log()   { printf '%b\n' "${C_GREEN}[+]${C_RESET} $*"; }
warn()  { printf '%b\n' "${C_YELLOW}[!]${C_RESET} $*" >&2; }
error_exit() { printf '%b\n' "${C_RED}[x]${C_RESET} $*" >&2; exit 1; }

print_help() {
    cat <<'EOF'
Usage: sudo ./setup-gitea-podman.sh [options]

Runs Gitea under rootful Podman + systemd (Quadlet), with all data kept
in a host directory separate from the container.

Options:
  --data-root <dir>        Where repos/db/config live    (default: /srv/gitea)
  --backup-dir <dir>        Recorded for the backup script (default: /srv/gitea-backups)
  --domain <host>           Hostname/IP used in clone URLs (default: auto-detected)
  --http-port <port>        Web UI port on the host        (default: 3000)
  --ssh-port <port>         SSH port on the host            (default: 22)
  --version <tag>           Gitea version, e.g. 1.27.3       (default: latest release)
  --admin-user <name>       Initial admin username           (default: admin)
  --admin-email <email>     Initial admin email                (default: admin@example.com)
  --admin-password <pass>   Initial admin password, 8+ chars    (default: randomly generated)
  --allow-registration      Let anyone sign up from the web UI  (default: off)
  --uid <uid>  --gid <gid>  UID:GID the container runs as        (default: 1000:1000,
                             matches the official rootless image -- only change this
                             if you know the image has changed)
  -h, --help                Show this help and exit

Every option can also be set as an environment variable of the same
name in caps with a GITEA_ prefix, e.g.:
  GITEA_DOMAIN=git.example.com sudo -E ./setup-gitea-podman.sh
EOF
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error_exit "Please run this script as root, e.g.: sudo $0"
    fi
    command -v systemctl &>/dev/null || error_exit "This script requires systemd."
    [[ -d /run/systemd/system ]] \
        || error_exit "systemd is not running as init here (container/chroot/WSL?). Run this on a real VM or host."
}

# ----------------------------------------------------------------------------
# Argument parsing + validation
# ----------------------------------------------------------------------------
need_arg() { [[ $# -ge 2 ]] || error_exit "Option $1 needs a value (see --help)"; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-root)      need_arg "$@"; GITEA_DATA_ROOT="$2"; shift 2 ;;
            --backup-dir)     need_arg "$@"; GITEA_BACKUP_DIR="$2"; shift 2 ;;
            --domain)         need_arg "$@"; GITEA_DOMAIN="$2"; shift 2 ;;
            --http-port)      need_arg "$@"; GITEA_HTTP_PORT="$2"; shift 2 ;;
            --ssh-port)       need_arg "$@"; GITEA_SSH_PORT="$2"; shift 2 ;;
            --version)        need_arg "$@"; GITEA_VERSION="$2"; shift 2 ;;
            --admin-user)     need_arg "$@"; GITEA_ADMIN_USER="$2"; shift 2 ;;
            --admin-email)    need_arg "$@"; GITEA_ADMIN_EMAIL="$2"; shift 2 ;;
            --admin-password) need_arg "$@"; GITEA_ADMIN_PASSWORD="$2"; shift 2 ;;
            --allow-registration) GITEA_DISABLE_REGISTRATION="false"; shift ;;
            --uid)            need_arg "$@"; GITEA_CONTAINER_UID="$2"; shift 2 ;;
            --gid)            need_arg "$@"; GITEA_CONTAINER_GID="$2"; shift 2 ;;
            -h|--help) print_help; exit 0 ;;
            *) error_exit "Unknown option: $1 (see --help)" ;;
        esac
    done
}

validate_port() {
    if [[ ! "$1" =~ ^[0-9]+$ ]] || (( 10#$1 < 1 || 10#$1 > 65535 )); then
        error_exit "Invalid $2: '$1' (expected a port number 1-65535)"
    fi
}

validate_settings() {
    validate_port "$GITEA_HTTP_PORT" "HTTP port"
    validate_port "$GITEA_SSH_PORT" "SSH port"
    [[ "$GITEA_HTTP_PORT" != "$SSH_LISTEN_PORT" ]] || true   # no conflict possible: different sockets
    [[ "$GITEA_ADMIN_USER" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
        || error_exit "Invalid admin username '${GITEA_ADMIN_USER}' (letters, digits, '.', '_' and '-' only)."
    [[ "$GITEA_ADMIN_EMAIL" == ?*@?* ]] \
        || error_exit "Invalid admin email '${GITEA_ADMIN_EMAIL}'."
    (( ${#GITEA_ADMIN_PASSWORD} >= 8 )) \
        || error_exit "The admin password must be at least 8 characters (Gitea's default minimum)."
    [[ "$GITEA_CONTAINER_UID" =~ ^[0-9]+$ && "$GITEA_CONTAINER_GID" =~ ^[0-9]+$ ]] \
        || error_exit "--uid/--gid must be numeric."
    [[ "$GITEA_DATA_ROOT" == /* ]] || error_exit "--data-root must be an absolute path."
    [[ "$GITEA_BACKUP_DIR" == /* ]] || error_exit "--backup-dir must be an absolute path."
    local rd rb
    rd="$(realpath -m -- "$GITEA_DATA_ROOT")"; rb="$(realpath -m -- "$GITEA_BACKUP_DIR")"
    case "$rb/" in "$rd/"*) error_exit "--backup-dir is inside --data-root; they must be separate." ;; esac
    case "$rd/" in "$rb/"*) error_exit "--data-root is inside --backup-dir; they must be separate." ;; esac
    GITEA_DATA_ROOT="$rd"; GITEA_BACKUP_DIR="$rb"
}

# ----------------------------------------------------------------------------
# Detection helpers
# ----------------------------------------------------------------------------
detect_distro_family() {
    [[ -r /etc/os-release ]] || error_exit "Cannot read /etc/os-release; unsupported system."
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian|linuxmint|pop|raspbian) DISTRO_FAMILY="debian" ;;
        fedora|rhel|centos|rocky|almalinux|nobara) DISTRO_FAMILY="fedora" ;;
        arch|archarm|manjaro|endeavouros) DISTRO_FAMILY="arch" ;;
        *)
            case "${ID_LIKE:-}" in
                *debian*) DISTRO_FAMILY="debian" ;;
                *fedora*|*rhel*) DISTRO_FAMILY="fedora" ;;
                *arch*) DISTRO_FAMILY="arch" ;;
                *) error_exit "Unsupported distro: ${PRETTY_NAME:-${ID:-unknown}}. This script supports Arch, Debian, Ubuntu and Fedora." ;;
            esac
            ;;
    esac
    log "Detected ${PRETTY_NAME:-${ID:-unknown}} -> using ${DISTRO_FAMILY} package family."
}

detect_domain() {
    local ip=""
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}') || true
    if [[ -z "$ip" ]]; then ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true; fi
    if [[ -n "$ip" ]]; then echo "$ip"; return; fi
    if [[ -r /etc/hostname ]]; then local h=""; h=$(< /etc/hostname); [[ -n "$h" ]] && { echo "$h"; return; }; fi
    echo "localhost"
}

generate_password() { tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20 || true; }

get_latest_version() {
    local latest="" json=""
    json=$(curl -fsSL --max-time 20 https://dl.gitea.com/gitea/version.json 2>/dev/null) || true
    latest=$(printf '%s' "$json" | tr -d '\n' | awk '
        { i = index($0, "\"latest\"")
          if (i && match(substr($0, i), /"version"[[:space:]]*:[[:space:]]*"v?[0-9][^"]*"/)) {
              v = substr($0, i + RSTART - 1, RLENGTH)
              sub(/^"version"[[:space:]]*:[[:space:]]*"v?/, "", v); sub(/"$/, "", v); print v } }') || true
    if [[ -z "$latest" ]]; then
        latest=$(curl -fsSL --max-time 20 https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
            | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' | head -n1) || true
    fi
    echo "$latest"
}

# ----------------------------------------------------------------------------
# Install steps
# ----------------------------------------------------------------------------
install_podman() {
    log "Installing Podman..."
    case "$DISTRO_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y podman curl ca-certificates
            ;;
        fedora)
            dnf install -y podman curl ca-certificates
            ;;
        arch)
            pacman -Syu --noconfirm --needed podman curl ca-certificates
            ;;
    esac
}

require_quadlet() {
    log "Checking for Quadlet support (Podman >= 4.4)..."
    command -v podman &>/dev/null || error_exit "podman was not found on PATH after installation."
    local pv gen=""
    pv="$(podman --version 2>/dev/null | awk '{print $3}')"
    for gen in /usr/lib/systemd/system-generators/podman-system-generator \
               /usr/libexec/podman/podman-system-generator; do
        [[ -x "$gen" ]] && break
        gen=""
    done
    if [[ -z "$gen" ]]; then
        error_exit "Podman ${pv:-unknown} does not ship the Quadlet systemd generator (needs Podman >= 4.4). \
On Debian this usually means bookworm's default repo is too old: enable bookworm-backports \
(echo 'deb http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/backports.list \
&& apt-get update && apt-get install -y -t bookworm-backports podman), then re-run this script."
    fi
    # A dry run smoke-tests the generator itself, not just its presence.
    local tmp; tmp="$(mktemp -d)"
    cat > "${tmp}/quadlet-smoketest.container" <<'EOF'
[Container]
Image=localhost/nonexistent:latest
EOF
    if ! QUADLET_UNIT_DIRS="$tmp" "$gen" --dryrun "${tmp}/out" &>/dev/null; then
        rm -rf -- "$tmp"
        error_exit "The Quadlet generator (${gen}) did not run successfully. Try 'apt/dnf/pacman upgrade podman'."
    fi
    rm -rf -- "$tmp"
    log "Podman ${pv:-?} with a working Quadlet generator found."
}

resolve_image() {
    local version
    if [[ "$GITEA_VERSION" == "latest" ]]; then
        log "Looking up the latest Gitea release..."
        version="$(get_latest_version)"
        [[ -n "$version" ]] || error_exit "Could not determine the latest Gitea version (dl.gitea.com and the GitHub API were both unreachable or rate-limited). Re-run with --version <x.y.z>."
    else
        version="${GITEA_VERSION#v}"
    fi
    IMAGE="docker.io/gitea/gitea:${version}-rootless"
    GITEA_INSTALLED_VERSION="$version"
    log "Using image ${IMAGE}"
}

pull_image() {
    log "Pulling ${IMAGE} (this can take a while on first run)..."
    podman pull -q "$IMAGE" \
        || error_exit "Could not pull ${IMAGE}. Check network access to docker.io, and that --version is a real Gitea release (rootless images have shipped since Gitea 1.14)."
    podman run --rm --user "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" --entrypoint gitea "$IMAGE" --version >/dev/null 2>&1 \
        || error_exit "The pulled image did not run 'gitea --version' successfully."
}

setup_directories() {
    log "Setting up ${GITEA_DATA_ROOT} ..."
    local work="${GITEA_DATA_ROOT}/work" conf="${GITEA_DATA_ROOT}/config"
    mkdir -p -- "$work" "$conf"
    # The container runs as this UID with ALL capabilities dropped (no DAC_OVERRIDE),
    # so it is subject to ordinary Unix permission checks like anyone else: these
    # directories must actually be owned by that UID, not just root-writable.
    chown -R "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" "$work"
    chmod 750 "$work"
    chown "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" "$conf"
    chmod 700 "$conf"
    : > "${work}/.gitea-podman-data"     # marker the backup/restore scripts check for
    chown "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" "${work}/.gitea-podman-data"

    if [[ ! -d "$GITEA_BACKUP_DIR" ]]; then
        mkdir -p -- "$GITEA_BACKUP_DIR"
        chmod 0700 -- "$GITEA_BACKUP_DIR"
        log "Created backup directory ${GITEA_BACKUP_DIR} (nothing is written there by this script)."
    fi
}

# --- app.ini -----------------------------------------------------------------

config_value() {
    local key="$1" file="${GITEA_DATA_ROOT}/config/app.ini"
    [[ -r "$file" ]] || return 0
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\\1/p" "$file" | head -n1
}

secret_for() {   # usage: secret_for <app.ini key> <'gitea generate secret' type>
    local value=""
    value="$(config_value "$1")"
    if [[ -z "$value" ]]; then
        value="$(podman run --rm --user "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" --entrypoint gitea "$IMAGE" generate secret "$2")" \
            || error_exit "'gitea generate secret $2' failed."
    fi
    [[ -n "$value" ]] || error_exit "Got an empty value for $1."
    printf '%s' "$value"
}

write_config() {
    local conf="${GITEA_DATA_ROOT}/config"
    local app="${conf}/app.ini"
    local secret_key internal_token lfs_jwt_secret oauth2_jwt_secret

    if [[ -f "$app" ]]; then
        cp -p -- "$app" "${app}.bak.$(date +%s)"
        warn "Existing ${app} found; backed it up (its secrets are kept, the rest is rewritten)."
    fi

    log "Generating secrets and writing ${app}..."
    # Same reasoning as the host script: the running container is not allowed to
    # write back to app.ini (it is not even its own file -- see setup_directories),
    # so every secret Gitea would otherwise generate itself on first start has to
    # already be here, or startup aborts trying to save them.
    secret_key="$(secret_for SECRET_KEY SECRET_KEY)"
    internal_token="$(secret_for INTERNAL_TOKEN INTERNAL_TOKEN)"
    lfs_jwt_secret="$(secret_for LFS_JWT_SECRET JWT_SECRET)"
    oauth2_jwt_secret="$(secret_for JWT_SECRET JWT_SECRET)"

    : > "$app"
    chown "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" "$app"
    chmod 600 "$app"

    cat > "$app" <<EOF
APP_NAME = Gitea
RUN_MODE = prod
RUN_USER = git

[server]
PROTOCOL = http
DOMAIN = ${GITEA_DOMAIN}
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
ROOT_URL = http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/
APP_DATA_PATH = /var/lib/gitea/data
DISABLE_SSH = false
START_SSH_SERVER = true
SSH_DOMAIN = ${GITEA_DOMAIN}
; SSH_PORT is what's shown in clone URLs (the host-published port); SSH_LISTEN_PORT
; is what Gitea's built-in SSH server actually binds to INSIDE the container -- fixed
; at a non-privileged port, mapped to the outside via the Quadlet unit's PublishPort.
SSH_PORT = ${GITEA_SSH_PORT}
SSH_LISTEN_PORT = ${SSH_LISTEN_PORT}
LFS_START_SERVER = true
LFS_JWT_SECRET = ${lfs_jwt_secret}

[database]
DB_TYPE = sqlite3
PATH = /var/lib/gitea/data/gitea.db

[repository]
ROOT = /var/lib/gitea/git/gitea-repositories
DEFAULT_BRANCH = main
ENABLE_PUSH_CREATE_USER = true
ENABLE_PUSH_CREATE_ORG = true
DEFAULT_PUSH_CREATE_PRIVATE = true

[security]
INSTALL_LOCK = true
SECRET_KEY = ${secret_key}
INTERNAL_TOKEN = ${internal_token}

[oauth2]
JWT_SECRET = ${oauth2_jwt_secret}

[service]
DISABLE_REGISTRATION = ${GITEA_DISABLE_REGISTRATION}
REQUIRE_SIGNIN_VIEW = true
DEFAULT_KEEP_EMAIL_PRIVATE = true
DEFAULT_ALLOW_CREATE_ORGANIZATION = true

[log]
; Console, not a file under the data volume: 'journalctl -u gitea' is the log,
; which keeps log rotation the host's job (journald) instead of ours.
MODE = console
LEVEL = info
EOF
}

# --- one-shot container runs (init/admin) ------------------------------------

run_oneshot() {
    podman run --rm \
        --user "${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}" \
        --cap-drop=all --security-opt=no-new-privileges \
        -v "${GITEA_DATA_ROOT}/work:/var/lib/gitea:Z" \
        -v "${GITEA_DATA_ROOT}/config:/etc/gitea:Z" \
        "$IMAGE" "$@"
}

init_database() {
    if systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null; then
        systemctl stop "$UNIT_NAME"
    fi
    log "Initialising the database..."
    # /usr/local/bin/gitea in this image is a wrapper that injects "-c
    # $GITEA_APP_INI" for us, so the bare subcommand is all that's needed.
    run_oneshot gitea migrate || error_exit "'gitea migrate' failed -- see the error above."
}

admin_user_exists() {
    run_oneshot gitea admin user list 2>/dev/null \
        | awk -v u="$GITEA_ADMIN_USER" 'NR > 1 && tolower($2) == tolower(u) { found = 1 } END { exit !found }'
}

create_admin_user() {
    log "Creating admin user '${GITEA_ADMIN_USER}'..."
    if run_oneshot gitea admin user create \
        --username "$GITEA_ADMIN_USER" \
        --password "$GITEA_ADMIN_PASSWORD" \
        --email "$GITEA_ADMIN_EMAIL" \
        --admin --must-change-password=false; then
        ADMIN_CREATED="true"
        log "Admin user created."
    elif admin_user_exists; then
        warn "User '${GITEA_ADMIN_USER}' already exists (previous run?); leaving it and its password unchanged."
    else
        error_exit "Could not create the admin user -- see the error above."
    fi
}

# --- Quadlet / systemd ---------------------------------------------------------

write_quadlet_unit() {
    log "Writing Quadlet unit ${QUADLET_FILE}..."
    mkdir -p -- "$QUADLET_DIR"
    cat > "$QUADLET_FILE" <<EOF
# Generated by setup-gitea-podman.sh. PodmanArgs below gives Gitea up to 90s
# to shut down cleanly (finish requests, close the sqlite connection) before
# Podman SIGKILLs it -- matters most when the backup script stops this unit.
[Unit]
Description=Gitea (Podman)
Wants=network-online.target
After=network-online.target

[Container]
Image=${IMAGE}
ContainerName=${CONTAINER_NAME}
User=${GITEA_CONTAINER_UID}:${GITEA_CONTAINER_GID}
Volume=${GITEA_DATA_ROOT}/work:/var/lib/gitea:Z
Volume=${GITEA_DATA_ROOT}/config:/etc/gitea:Z
PublishPort=0.0.0.0:${GITEA_HTTP_PORT}:3000
PublishPort=0.0.0.0:${GITEA_SSH_PORT}:${SSH_LISTEN_PORT}
DropCapability=ALL
NoNewPrivileges=true
PodmanArgs=--stop-timeout=90

[Service]
Restart=always
TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

start_service() {
    log "Starting ${UNIT_NAME}..."
    systemctl enable "$UNIT_NAME"
    systemctl restart "$UNIT_NAME"
}

wait_for_gitea() {
    log "Waiting for Gitea to come up..."
    local host="$GITEA_DOMAIN"
    [[ "$host" != "0.0.0.0" ]] || host="127.0.0.1"
    local _
    for _ in $(seq 1 60); do
        if curl -fsS -o /dev/null "http://${host}:${GITEA_HTTP_PORT}/api/healthz" 2>/dev/null; then
            log "Gitea is up."
            return 0
        fi
        sleep 2
    done
    warn "Gitea did not answer within 2 minutes. Last log lines:"
    journalctl -u "$UNIT_NAME" -n 40 --no-pager >&2 || true
    error_exit "Gitea failed to start -- fix the problem shown above (full log: journalctl -u $UNIT_NAME)."
}

write_adduser_helper() {
    cat > /usr/local/bin/gitea-podman-adduser <<EOF
#!/usr/bin/env bash
# Convenience wrapper around 'gitea admin user create', run inside the LIVE container.
# Examples:
#   sudo gitea-podman-adduser --username alice --email alice@example.com --password 'TempPass123!'
#   sudo gitea-podman-adduser --username bob --email bob@example.com --password 'TempPass123!' --admin
[[ \$EUID -eq 0 ]] || exec sudo "\$0" "\$@"
exec podman exec -i ${CONTAINER_NAME} gitea admin user create "\$@"
EOF
    chmod 755 /usr/local/bin/gitea-podman-adduser
}

configure_firewall() {
    if command -v ufw &>/dev/null && [[ "$(ufw status 2>/dev/null)" == *"Status: active"* ]]; then
        log "Opening ports in ufw..."
        ufw allow "${GITEA_SSH_PORT}/tcp" || true
        ufw allow "${GITEA_HTTP_PORT}/tcp" || true
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        log "Opening ports in firewalld..."
        firewall-cmd --permanent --add-port="${GITEA_SSH_PORT}/tcp" || true
        firewall-cmd --permanent --add-port="${GITEA_HTTP_PORT}/tcp" || true
        firewall-cmd --reload || true
    else
        log "No active firewall manager (ufw/firewalld) found; nothing to configure there."
    fi
}

write_conf_file() {
    # The single source of truth gitea-podman-backup.sh / -restore.sh read from --
    # keeps them from duplicating (and drifting from) what this script set up.
    mkdir -p -- "$CONF_DIR"
    chmod 0700 -- "$CONF_DIR"
    cat > "$CONF_FILE" <<EOF
DATA_ROOT=${GITEA_DATA_ROOT}
BACKUP_DIR=${GITEA_BACKUP_DIR}
CONTAINER_NAME=${CONTAINER_NAME}
UNIT_NAME=${UNIT_NAME}
IMAGE=${IMAGE}
CONTAINER_UID=${GITEA_CONTAINER_UID}
CONTAINER_GID=${GITEA_CONTAINER_GID}
HTTP_BIND=0.0.0.0
HTTP_PORT=${GITEA_HTTP_PORT}
SSH_BIND=0.0.0.0
SSH_PORT=${GITEA_SSH_PORT}
DOMAIN=${GITEA_DOMAIN}
EOF
    chmod 600 "$CONF_FILE"
}

print_summary() {
    local registration="enabled" admin_password_line
    [[ "$GITEA_DISABLE_REGISTRATION" == "true" ]] && registration="disabled"
    if [[ "$ADMIN_CREATED" == "true" ]]; then
        admin_password_line="${GITEA_ADMIN_PASSWORD}   (log in and change/rotate it)"
    else
        admin_password_line="(account already existed -- password left unchanged)"
    fi

    cat <<EOF

============================================================================
 Gitea ${GITEA_INSTALLED_VERSION} is running in Podman (image ${IMAGE})
============================================================================

  Web UI         http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/
  Admin user     ${GITEA_ADMIN_USER}
  Admin email    ${GITEA_ADMIN_EMAIL}
  Admin password ${admin_password_line}

Clone and push over SSH, exactly like GitHub -- there is no separate SSH
key file to install on the server: add your key in the web UI (Settings ->
SSH / GPG Keys) and Gitea's own SSH server (inside the container) handles
the rest.

  git@${GITEA_DOMAIN}:<username>/<repo>.git    $( [[ "$GITEA_SSH_PORT" != 22 ]] && echo "(add: -p ${GITEA_SSH_PORT}, or set it in your SSH config)" )

A repo doesn't need to be created first -- the first push creates it
(as a private repo by default):

  mkdir myproject && cd myproject && git init
  git commit --allow-empty -m "init"
  git remote add origin git@${GITEA_DOMAIN}:${GITEA_ADMIN_USER}/myproject.git
  git push -u origin main

Add more accounts any time with:

  sudo gitea-podman-adduser --username <name> --email <email> --password '<temp-pass>'

Data lives OUTSIDE the container and survives 'podman rm'/reinstalls:
  Work dir (repos, db, LFS, SSH host keys):  ${GITEA_DATA_ROOT}/work
  Config (app.ini + secrets):                ${GITEA_DATA_ROOT}/config
  Recorded backup directory:                 ${GITEA_BACKUP_DIR}  (nothing written yet --
                                              run gitea-podman-backup.sh to take a backup)

Useful commands:
  systemctl status ${UNIT_NAME}
  systemctl restart ${UNIT_NAME}
  journalctl -u ${UNIT_NAME} -f
  podman exec -it ${CONTAINER_NAME} sh

Public sign-up from the web UI: ${registration} (see [service] DISABLE_REGISTRATION in app.ini)

This is plain HTTP -- fine on a LAN or over a VPN. For anything reachable
from the open internet: put it behind a reverse proxy (nginx/Caddy) with a
real TLS certificate, and double check any cloud provider firewall/security
group rules in addition to the local firewall this script already configured.

Back this up regularly -- see gitea-podman-backup.sh. Data loss protection
only works if you actually run it (a systemd timer is the easiest way).
============================================================================
EOF
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    require_root
    : "${GITEA_ADMIN_PASSWORD:=$(generate_password)}"
    validate_settings
    detect_distro_family

    install_podman
    require_quadlet
    : "${GITEA_DOMAIN:=$(detect_domain)}"

    resolve_image
    pull_image
    setup_directories
    write_config
    init_database
    create_admin_user
    write_quadlet_unit
    start_service
    wait_for_gitea
    write_adduser_helper
    configure_firewall
    write_conf_file
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
