#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "Error: systemd is not installed or running."
  exit 1
fi

INSTANCE_NAME=$1
if [ -z "$INSTANCE_NAME" ]; then
  echo "Usage: $0 <instance_name>"
  exit 1
fi

BASE_DIR="/opt/custom_sshd/$INSTANCE_NAME"
CONFIG_FILE="$BASE_DIR/sshd_config"
SERVICE_NAME="custom-sshd-${INSTANCE_NAME}.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

if [ -d "$BASE_DIR" ] || [ -f "$SERVICE_FILE" ]; then
  echo "Error: An instance or service named '$INSTANCE_NAME' already exists."
  exit 1
fi

# --- USER MANAGEMENT ---
read -p "Enter the username to restrict this SSH instance to: " SSH_USER
if [ -z "$SSH_USER" ]; then
    echo "Error: Username cannot be empty."
    exit 1
fi

if id "$SSH_USER" >/dev/null 2>&1; then
    echo "User '$SSH_USER' already exists. This instance will be restricted to them."
else
    read -p "User '$SSH_USER' does not exist. Create new user? [Y/n] " CREATE_USER
    if [[ "$CREATE_USER" =~ ^[Yy]$ ]] || [[ -z "$CREATE_USER" ]]; then
        useradd -m -s /bin/bash "$SSH_USER"
        echo "Please set a password for the new user '$SSH_USER':"
        passwd "$SSH_USER"
    else
        echo "Aborting setup."
        exit 1
    fi
fi

# --- SSHD LOCATOR (Crucial for cross-distro support) ---
SSHD_BIN=$(command -v sshd || echo "/usr/sbin/sshd")
if [ ! -x "$SSHD_BIN" ]; then
  echo "Error: sshd binary not found at $SSHD_BIN. Please install OpenSSH."
  exit 1
fi

echo "Creating isolated environment for '$INSTANCE_NAME'..."
mkdir -p "$BASE_DIR"

# --- PORT DETECTION ---
is_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tln | grep -q ":${port}\b"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln | grep -q ":${port}\b"
    else
        (echo >/dev/tcp/127.0.0.1/${port}) >/dev/null 2>&1
    fi
}

PORT=2222
while is_port_in_use $PORT; do
  PORT=$((PORT+1))
done
echo "Found available port: $PORT"

# --- CONFIGURATION ---
echo "Generating host keys..."
ssh-keygen -t rsa -b 4096 -f "$BASE_DIR/ssh_host_rsa_key" -N "" -q
ssh-keygen -t ed25519 -f "$BASE_DIR/ssh_host_ed25519_key" -N "" -q

cat <<EOF > "$CONFIG_FILE"
Port $PORT
HostKey $BASE_DIR/ssh_host_rsa_key
HostKey $BASE_DIR/ssh_host_ed25519_key

# Security & Authentication defaults
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Restrict to the requested user
AllowUsers $SSH_USER

Subsystem sftp internal-sftp
EOF

# --- FIREWALL ---
open_firewall_port() {
    local p=$1
    echo "Configuring firewall for port $p..."
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=${p}/tcp >/dev/null
        firewall-cmd --reload >/dev/null
        echo " -> Opened port $p using firewalld."
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow ${p}/tcp >/dev/null
        echo " -> Opened port $p using ufw."
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport ${p} -j ACCEPT
        echo " -> Opened port $p using iptables."
    fi
}
open_firewall_port $PORT

# --- SYSTEMD SERVICE ---
echo "Creating systemd service: $SERVICE_NAME..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Isolated SSHd instance ($INSTANCE_NAME) restricted to $SSH_USER
After=network.target auditd.service

[Service]
ExecStart=$SSHD_BIN -D -f $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "----------------------------------------------------"
echo "Success! SSH Server '$INSTANCE_NAME' is running."
echo "Port: $PORT"
echo "Allowed User: $SSH_USER"
echo "Connect: ssh -p $PORT $SSH_USER@<server-ip>"
echo "----------------------------------------------------"
