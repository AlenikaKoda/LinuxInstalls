#!/usr/bin/env bash
#
# setup-git-server.sh
#
# Sets up a self-hosted Git server (Gitea: https://about.gitea.com) on a
# fresh Linux box, with a GitHub-style workflow:
#   - real user accounts, managed from the command line
#   - SSH clone/push exactly like GitHub: git@<host>:<user>/<repo>.git
#   - repos are created automatically on first push (push-to-create) --
#     no manual "create repo" step needed
#   - a small web UI for browsing repos, issues, PRs, etc.
#
# Supported distros: Arch, Debian, Ubuntu, Fedora (and close derivatives).
# Must be run as root on a machine where systemd is actually running (a VM
# or bare metal -- not a plain Docker container). Written for a first-time
# install; re-running it keeps the existing secrets, the service user and
# existing accounts.
#
# Usage:
#   sudo ./setup-git-server.sh [options]
#
# Run with --help for the full list of options.

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults (overridable via env vars, then via flags below)
# ----------------------------------------------------------------------------
GITEA_USER="${GITEA_USER:-git}"
GITEA_HOME="${GITEA_HOME:-/home/${GITEA_USER}}"
GITEA_WORK_DIR="${GITEA_WORK_DIR:-/var/lib/gitea}"
GITEA_CONFIG_DIR="${GITEA_CONFIG_DIR:-/etc/gitea}"
GITEA_CONFIG="${GITEA_CONFIG_DIR}/app.ini"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-}"
GITEA_DOMAIN="${GITEA_DOMAIN:-}"
GITEA_VERSION="${GITEA_VERSION:-latest}"
GITEA_DISABLE_REGISTRATION="${GITEA_DISABLE_REGISTRATION:-true}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-admin}"
GITEA_ADMIN_EMAIL="${GITEA_ADMIN_EMAIL:-admin@example.com}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-}"

# Filled in while the script runs
DISTRO_FAMILY=""
GITEA_GROUP=""
GITEA_INSTALLED_VERSION=""
ADMIN_CREATED="false"
TMP_FILE=""

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------
C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_RESET='\033[0m'
log()   { printf '%b\n' "${C_GREEN}[+]${C_RESET} $*"; }
warn()  { printf '%b\n' "${C_YELLOW}[!]${C_RESET} $*" >&2; }
error_exit() { printf '%b\n' "${C_RED}[x]${C_RESET} $*" >&2; exit 1; }

cleanup() {
    if [[ -n "${TMP_FILE:-}" ]]; then
        rm -f -- "$TMP_FILE" "${TMP_FILE}.sha256"
    fi
}
trap cleanup EXIT

print_help() {
    cat <<'EOF'
Usage: sudo ./setup-git-server.sh [options]

Sets up a self-hosted Gitea git server (Arch, Debian, Ubuntu, Fedora)
with GitHub-style SSH access (git@host:user/repo.git) and automatic
repo creation on first push.

Options:
  --domain <host>          Hostname/IP used in clone URLs   (default: auto-detected)
  --http-port <port>       Web UI port                      (default: 3000)
  --ssh-port <port>        SSH port                         (default: read from sshd config, else 22)
  --version <tag>          Gitea version, e.g. 1.27.3        (default: latest release)
  --admin-user <name>      Initial admin username            (default: admin)
  --admin-email <email>    Initial admin email                (default: admin@example.com)
  --admin-password <pass>  Initial admin password, 8+ chars   (default: randomly generated)
  --allow-registration     Let anyone sign up from the web UI (default: off)
  -h, --help                Show this help and exit

Every option can also be set as an environment variable of the same
name in caps, e.g.:
  GITEA_DOMAIN=git.example.com sudo -E ./setup-git-server.sh
EOF
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error_exit "Please run this script as root, e.g.: sudo $0"
    fi
    command -v systemctl &>/dev/null || error_exit "This script requires systemd."
    # The systemctl binary can exist without systemd actually running (Docker,
    # chroots, WSL without systemd) -- every enable/start below would then fail.
    [[ -d /run/systemd/system ]] \
        || error_exit "systemd is not running as init here (container/chroot/WSL?). Run this on a real VM or host."
}

# ----------------------------------------------------------------------------
# Argument parsing + validation
# ----------------------------------------------------------------------------
need_arg() {   # usage: need_arg "$@"  -- an option that takes a value must have one
    [[ $# -ge 2 ]] || error_exit "Option $1 needs a value (see --help)"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)         need_arg "$@"; GITEA_DOMAIN="$2"; shift 2 ;;
            --http-port)      need_arg "$@"; GITEA_HTTP_PORT="$2"; shift 2 ;;
            --ssh-port)       need_arg "$@"; GITEA_SSH_PORT="$2"; shift 2 ;;
            --version)        need_arg "$@"; GITEA_VERSION="$2"; shift 2 ;;
            --admin-user)     need_arg "$@"; GITEA_ADMIN_USER="$2"; shift 2 ;;
            --admin-email)    need_arg "$@"; GITEA_ADMIN_EMAIL="$2"; shift 2 ;;
            --admin-password) need_arg "$@"; GITEA_ADMIN_PASSWORD="$2"; shift 2 ;;
            --allow-registration) GITEA_DISABLE_REGISTRATION="false"; shift ;;
            -h|--help) print_help; exit 0 ;;
            *) error_exit "Unknown option: $1 (see --help)" ;;
        esac
    done
}

validate_port() {   # usage: validate_port <value> <what>
    if [[ ! "$1" =~ ^[0-9]+$ ]] || (( 10#$1 < 1 || 10#$1 > 65535 )); then
        error_exit "Invalid $2: '$1' (expected a port number 1-65535)"
    fi
}

validate_settings() {
    validate_port "$GITEA_HTTP_PORT" "HTTP port"
    if [[ -n "$GITEA_SSH_PORT" ]]; then
        validate_port "$GITEA_SSH_PORT" "SSH port"
    fi
    [[ "$GITEA_ADMIN_USER" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
        || error_exit "Invalid admin username '${GITEA_ADMIN_USER}' (letters, digits, '.', '_' and '-' only)."
    [[ "$GITEA_ADMIN_EMAIL" == ?*@?* ]] \
        || error_exit "Invalid admin email '${GITEA_ADMIN_EMAIL}'."
    (( ${#GITEA_ADMIN_PASSWORD} >= 8 )) \
        || error_exit "The admin password must be at least 8 characters (Gitea's default minimum)."
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

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        # Gitea publishes arm-5, arm-6 and arm64 builds -- there is no arm-7.
        # The arm-6 build runs fine on ARMv7 machines.
        armv7l|armv7|armv6l) echo "arm-6" ;;
        armv5*) echo "arm-5" ;;
        i386|i686) echo "386" ;;
        riscv64) echo "riscv64" ;;
        *) error_exit "Unsupported CPU architecture: $(uname -m)" ;;
    esac
}

detect_domain() {
    local ip=""
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}') || true
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
    fi
    if [[ -n "$ip" ]]; then
        echo "$ip"; return
    fi
    if [[ -r /etc/hostname ]]; then
        local h=""; h=$(< /etc/hostname)
        if [[ -n "$h" ]]; then echo "$h"; return; fi
    fi
    echo "localhost"
}

detect_ssh_port() {
    local port="" sshd_bin=""
    sshd_bin="$(command -v sshd 2>/dev/null || true)"
    if [[ -z "$sshd_bin" && -x /usr/sbin/sshd ]]; then
        sshd_bin=/usr/sbin/sshd
    fi
    # 'sshd -T' prints the effective config (includes and drop-ins resolved)...
    if [[ -n "$sshd_bin" ]]; then
        port=$("$sshd_bin" -T 2>/dev/null | awk '$1 == "port" { print $2; exit }') || true
    fi
    # ...falling back to a plain look at the config files.
    if [[ -z "$port" ]]; then
        port=$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
            | awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ { print $2; exit }') || true
    fi
    echo "${port:-22}"
}

generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20 || true
}

get_latest_version() {
    local latest="" json=""
    # 1) Gitea's own version feed -- the one its built-in update checker and
    #    contrib/upgrade.sh use. Same host the binary comes from, no API rate limit.
    json=$(curl -fsSL --max-time 20 https://dl.gitea.com/gitea/version.json 2>/dev/null) || true
    latest=$(printf '%s' "$json" | tr -d '\n' | awk '
        { i = index($0, "\"latest\"")
          if (i && match(substr($0, i), /"version"[[:space:]]*:[[:space:]]*"v?[0-9][^"]*"/)) {
              v = substr($0, i + RSTART - 1, RLENGTH)
              sub(/^"version"[[:space:]]*:[[:space:]]*"v?/, "", v); sub(/"$/, "", v); print v } }') || true
    # 2) Fallback: the GitHub API. Anonymous requests are capped at 60/hour per
    #    IP, which shared VPS/NAT addresses regularly use up.
    if [[ -z "$latest" ]]; then
        latest=$(curl -fsSL --max-time 20 https://api.github.com/repos/go-gitea/gitea/releases/latest 2>/dev/null \
            | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' \
            | head -n1) || true
    fi
    echo "$latest"
}

# ----------------------------------------------------------------------------
# Install steps
# ----------------------------------------------------------------------------
install_dependencies() {
    log "Installing dependencies..."
    case "$DISTRO_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y git curl ca-certificates openssh-server sudo
            ;;
        fedora)
            dnf install -y git ca-certificates openssh-server sudo
            # Some Fedora/RHEL images ship curl-minimal, which conflicts with the
            # full curl package -- only install curl when there is none at all.
            command -v curl &>/dev/null || dnf install -y curl
            ;;
        arch)
            # Never do a partial upgrade (-Sy without -u) on Arch.
            pacman -Syu --noconfirm --needed git curl ca-certificates openssh sudo
            ;;
    esac
}

enable_sshd() {
    log "Making sure the SSH server is enabled..."
    local unit
    # (No 'systemctl list-unit-files | grep -q' here: under pipefail, grep -q
    # exiting early can make the pipeline report failure.)
    for unit in ssh.service sshd.service; do
        if systemctl cat "$unit" &>/dev/null; then
            systemctl enable --now "$unit"
            return 0
        fi
    done
    warn "Could not find an ssh/sshd systemd unit. Make sure OpenSSH server is installed and running."
}

create_git_user() {
    if id -u "$GITEA_USER" &>/dev/null; then
        log "User '${GITEA_USER}' already exists, leaving it alone."
    else
        log "Creating system user '${GITEA_USER}'..."
        useradd --system --user-group --shell /bin/bash --comment 'Git Version Control' \
            --create-home --home-dir "$GITEA_HOME" "$GITEA_USER"
        # 'useradd --system' leaves the password locked ("!"). sshd only refuses
        # locked accounts when UsePAM is off; "*" (no valid password, but not
        # locked) makes key logins work whatever the sshd config says.
        usermod --password '*' "$GITEA_USER"
    fi

    # Use what the system really has (matters when the user already existed).
    local entry
    entry="$(getent passwd "$GITEA_USER")"
    GITEA_HOME="$(cut -d: -f6 <<<"$entry")"
    GITEA_GROUP="$(id -gn "$GITEA_USER")"
    case "$(cut -d: -f7 <<<"$entry")" in
        */nologin|*/false|*/git-shell)
            warn "User '${GITEA_USER}' has a non-interactive login shell, so SSH pushes will fail. Fix: usermod -s /bin/bash ${GITEA_USER}"
            ;;
    esac
}

setup_directories() {
    log "Setting up directories..."
    mkdir -p "$GITEA_WORK_DIR"/{custom,data,log}
    chown -R "${GITEA_USER}:${GITEA_GROUP}" "$GITEA_WORK_DIR"
    chmod -R 750 "$GITEA_WORK_DIR"

    mkdir -p "$GITEA_CONFIG_DIR"
    chown "root:${GITEA_GROUP}" "$GITEA_CONFIG_DIR"
    chmod 750 "$GITEA_CONFIG_DIR"

    install -d -m 700 -o "$GITEA_USER" -g "$GITEA_GROUP" "${GITEA_HOME}/.ssh"
    if [[ ! -f "${GITEA_HOME}/.ssh/authorized_keys" ]]; then
        install -m 600 -o "$GITEA_USER" -g "$GITEA_GROUP" /dev/null "${GITEA_HOME}/.ssh/authorized_keys"
    fi

    install -d -m 750 -o "$GITEA_USER" -g "$GITEA_GROUP" "${GITEA_HOME}/gitea-repositories"
}

install_gitea_binary() {
    local arch version url
    arch="$(detect_arch)"
    if [[ "$GITEA_VERSION" == "latest" ]]; then
        log "Looking up the latest Gitea release..."
        version="$(get_latest_version)"
        [[ -n "$version" ]] || error_exit "Could not determine the latest Gitea version (dl.gitea.com and the GitHub API were both unreachable or rate-limited). Re-run with --version <x.y.z>."
    else
        version="${GITEA_VERSION#v}"   # accept both 1.27.3 and v1.27.3
    fi
    log "Installing Gitea v${version} (linux-${arch})..."
    url="https://dl.gitea.com/gitea/${version}/gitea-${version}-linux-${arch}"
    TMP_FILE="$(mktemp)"
    curl -fL --retry 3 --retry-delay 2 -o "$TMP_FILE" "$url" \
        || error_exit "Failed to download Gitea from $url -- check the version/architecture and try again."

    if curl -fsSL -o "${TMP_FILE}.sha256" "${url}.sha256" 2>/dev/null; then
        local expected actual
        expected="$(awk '{print $1}' "${TMP_FILE}.sha256")"
        actual="$(sha256sum "$TMP_FILE" | awk '{print $1}')"
        if [[ -n "$expected" ]]; then
            if [[ "$expected" != "$actual" ]]; then
                error_exit "Checksum verification failed for the downloaded Gitea binary. Aborting."
            fi
            log "Checksum verified."
        else
            warn "Downloaded checksum file was empty; skipping verification."
        fi
    else
        warn "No checksum file published for this release; skipping verification."
    fi

    install -m 755 -o root -g root "$TMP_FILE" "$GITEA_BIN"
    "$GITEA_BIN" --version >/dev/null 2>&1 \
        || error_exit "The downloaded binary does not run on this machine ($(uname -m))."
    GITEA_INSTALLED_VERSION="$version"
}

# --- app.ini -----------------------------------------------------------------

config_value() {   # usage: config_value KEY  -> current value of KEY in app.ini (empty if none)
    local key="$1"
    [[ -r "$GITEA_CONFIG" ]] || return 0
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\\1/p" "$GITEA_CONFIG" | head -n1
}

secret_for() {   # usage: secret_for <app.ini key> <'gitea generate secret' type>
    local value=""
    value="$(config_value "$1")"        # re-runs keep the secrets from the last run
    if [[ -z "$value" ]]; then
        value="$("$GITEA_BIN" generate secret "$2")" \
            || error_exit "'gitea generate secret $2' failed."
    fi
    [[ -n "$value" ]] || error_exit "Got an empty value for $1."
    printf '%s' "$value"
}

write_config() {
    local secret_key internal_token lfs_jwt_secret oauth2_jwt_secret

    if [[ -f "$GITEA_CONFIG" ]]; then
        cp -p "$GITEA_CONFIG" "${GITEA_CONFIG}.bak.$(date +%s)"
        warn "Existing ${GITEA_CONFIG} found; backed it up (its secrets are kept, the rest is rewritten)."
    fi

    log "Generating secrets and writing ${GITEA_CONFIG}..."
    # Every secret that Gitea would otherwise generate itself and try to write
    # back into app.ini on first start has to be in the file already. app.ini is
    # read-only for the service user, so a missing oauth2 JWT_SECRET, LFS_JWT_SECRET
    # or INTERNAL_TOKEN makes Gitea abort at startup ("save oauth2.JWT_SECRET
    # failed: ...permission denied"). WORK_PATH is set below so it doesn't try to
    # write that back either (it would only log an error, but every start).
    secret_key="$(secret_for SECRET_KEY SECRET_KEY)"
    internal_token="$(secret_for INTERNAL_TOKEN INTERNAL_TOKEN)"
    lfs_jwt_secret="$(secret_for LFS_JWT_SECRET JWT_SECRET)"
    oauth2_jwt_secret="$(secret_for JWT_SECRET JWT_SECRET)"

    # Create the file with its final ownership/permissions *before* the secrets go in.
    : > "$GITEA_CONFIG"
    chown "root:${GITEA_GROUP}" "$GITEA_CONFIG"
    chmod 640 "$GITEA_CONFIG"

    cat > "$GITEA_CONFIG" <<EOF
APP_NAME = Gitea
RUN_USER = ${GITEA_USER}
RUN_MODE = prod
; Also used by the 'gitea serv' / hook processes that sshd and git start
; without any environment -- without it they fall back to /usr/local/bin.
WORK_PATH = ${GITEA_WORK_DIR}

[server]
PROTOCOL = http
DOMAIN = ${GITEA_DOMAIN}
HTTP_ADDR = 0.0.0.0
HTTP_PORT = ${GITEA_HTTP_PORT}
ROOT_URL = http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/
APP_DATA_PATH = ${GITEA_WORK_DIR}/data
DISABLE_SSH = false
START_SSH_SERVER = false
SSH_DOMAIN = ${GITEA_DOMAIN}
SSH_PORT = ${GITEA_SSH_PORT}
SSH_CREATE_AUTHORIZED_KEYS_FILE = true
LFS_START_SERVER = true
LFS_JWT_SECRET = ${lfs_jwt_secret}

[database]
DB_TYPE = sqlite3
PATH = ${GITEA_WORK_DIR}/data/gitea.db

[repository]
ROOT = ${GITEA_HOME}/gitea-repositories
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
MODE = console
LEVEL = info
ROOT_PATH = ${GITEA_WORK_DIR}/log
EOF
}

# --- running gitea as the service user ---------------------------------------

run_as_gitea() {
    # Run a command as the service user, from a directory it can read (sudo keeps
    # the caller's cwd, e.g. /root), with the same work dir the service uses.
    ( cd "$GITEA_WORK_DIR" && sudo -H -u "$GITEA_USER" env GITEA_WORK_DIR="$GITEA_WORK_DIR" "$@" )
}

init_database() {
    # On a re-run the old service may still be up; don't migrate underneath it.
    if systemctl is-active --quiet gitea 2>/dev/null; then
        systemctl stop gitea
    fi
    # 'gitea admin user create' does NOT create the schema -- 'gitea migrate' does.
    log "Initialising the database..."
    run_as_gitea "$GITEA_BIN" --config "$GITEA_CONFIG" migrate \
        || error_exit "'gitea migrate' failed -- see the error above."
}

admin_user_exists() {
    run_as_gitea "$GITEA_BIN" --config "$GITEA_CONFIG" admin user list 2>/dev/null \
        | awk -v u="$GITEA_ADMIN_USER" 'NR > 1 && tolower($2) == tolower(u) { found = 1 } END { exit !found }'
}

create_admin_user() {
    log "Creating admin user '${GITEA_ADMIN_USER}'..."
    if run_as_gitea "$GITEA_BIN" --config "$GITEA_CONFIG" admin user create \
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

write_systemd_unit() {
    log "Creating the systemd service..."
    cat > /etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=${GITEA_USER}
Group=${GITEA_GROUP}
WorkingDirectory=${GITEA_WORK_DIR}
ExecStart=${GITEA_BIN} web --config ${GITEA_CONFIG}
Restart=always
Environment=USER=${GITEA_USER} HOME=${GITEA_HOME} GITEA_WORK_DIR=${GITEA_WORK_DIR}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gitea
    systemctl restart gitea
}

wait_for_gitea() {
    log "Waiting for Gitea to come up..."
    for _ in $(seq 1 60); do
        # /api/healthz needs no login (the front page redirects to the sign-in
        # page under REQUIRE_SIGNIN_VIEW) and only answers 2xx when the database
        # is reachable too.
        if curl -fsS -o /dev/null "http://127.0.0.1:${GITEA_HTTP_PORT}/api/healthz" 2>/dev/null; then
            log "Gitea is up."
            return 0
        fi
        sleep 1
    done
    warn "Gitea did not answer on port ${GITEA_HTTP_PORT} within 60s. Last log lines:"
    journalctl -u gitea -n 30 --no-pager >&2 || true
    error_exit "Gitea failed to start -- fix the problem shown above (full log: journalctl -u gitea)."
}

write_adduser_helper() {
    cat > /usr/local/bin/gitea-adduser <<EOF
#!/usr/bin/env bash
# Convenience wrapper around 'gitea admin user create'.
# Examples:
#   sudo gitea-adduser --username alice --email alice@example.com --password 'TempPass123!'
#   sudo gitea-adduser --username bob --email bob@example.com --password 'TempPass123!' --admin
[[ \$EUID -eq 0 ]] || exec sudo "\$0" "\$@"
cd ${GITEA_WORK_DIR}
exec sudo -H -u ${GITEA_USER} env GITEA_WORK_DIR=${GITEA_WORK_DIR} ${GITEA_BIN} --config ${GITEA_CONFIG} admin user create "\$@"
EOF
    chmod 755 /usr/local/bin/gitea-adduser
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

apply_selinux_context() {
    if command -v restorecon &>/dev/null; then
        log "Applying SELinux file contexts..."
        restorecon -Rv "$GITEA_BIN" "$GITEA_WORK_DIR" "$GITEA_CONFIG_DIR" "$GITEA_HOME" &>/dev/null || true
    fi
}

print_summary() {
    local registration="enabled" admin_password_line
    if [[ "$GITEA_DISABLE_REGISTRATION" == "true" ]]; then
        registration="disabled"
    fi
    if [[ "$ADMIN_CREATED" == "true" ]]; then
        admin_password_line="${GITEA_ADMIN_PASSWORD}   (log in and change/rotate it)"
    else
        admin_password_line="(account already existed -- password left unchanged)"
    fi

    cat <<EOF

============================================================================
 Gitea is installed and running (version ${GITEA_INSTALLED_VERSION})
============================================================================

  Web UI         http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/
  Admin user     ${GITEA_ADMIN_USER}
  Admin email    ${GITEA_ADMIN_EMAIL}
  Admin password ${admin_password_line}

Clone and push over SSH, exactly like GitHub:

  git@${GITEA_DOMAIN}:<username>/<repo>.git

A repo doesn't need to be created first -- the first push creates it
(as a private repo by default):

  mkdir myproject && cd myproject && git init
  git commit --allow-empty -m "init"
  git remote add origin git@${GITEA_DOMAIN}:${GITEA_ADMIN_USER}/myproject.git
  git push -u origin main

Each user needs an SSH key on file before they can push: Web UI ->
Settings -> SSH / GPG Keys -> Add Key.

Add more accounts any time with:

  sudo gitea-adduser --username <name> --email <email> --password '<temp-pass>'

Useful commands:
  systemctl status gitea
  systemctl restart gitea
  journalctl -u gitea -f
  Config:        ${GITEA_CONFIG}
  Repo storage:  ${GITEA_HOME}/gitea-repositories

Public sign-up from the web UI: ${registration} (see [service] DISABLE_REGISTRATION in the config)

This is plain HTTP -- fine on a LAN or over a VPN. For anything reachable
from the open internet: put it behind a reverse proxy (nginx/Caddy) with
a real TLS certificate, and double check any cloud provider firewall /
security group rules in addition to the local firewall this script
already configured.
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

    install_dependencies
    enable_sshd

    # These need tools/services installed above (ip, sshd), so detect them now.
    : "${GITEA_DOMAIN:=$(detect_domain)}"
    : "${GITEA_SSH_PORT:=$(detect_ssh_port)}"

    create_git_user
    setup_directories
    install_gitea_binary
    write_config
    init_database
    create_admin_user
    write_systemd_unit
    wait_for_gitea
    write_adduser_helper
    configure_firewall
    apply_selinux_context
    print_summary
}

# Only run when executed, not when sourced (handy for testing single functions).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi

