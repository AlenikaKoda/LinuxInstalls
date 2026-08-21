#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "Error: systemd is not installed or running. This script requires systemd for auto-restarts."
  exit 1
fi

INSTANCE_NAME=$1
if [ -z "$INSTANCE_NAME" ]; then
  echo "Usage: $0 <instance_name>"
  exit 1
fi

# Locate the sshd binary
SSHD_BIN=$(command -v sshd || echo "/usr/sbin/sshd")
if [ ! -x "$SSHD_BIN" ]; then
  echo "Error: sshd binary not found. Please install OpenSSH."
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

echo "Creating isolated environment for '$INSTANCE_NAME'..."
mkdir -p "$BASE_DIR"

# Port detection function
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

# Find the next available port starting from 2222
PORT=2222
while is_port_in_use $PORT; do
  PORT=$((PORT+1))
done
echo "Found available port: $PORT"

# Generate isolated Host Keys
echo "Generating host keys..."
ssh-keygen -t rsa -b 4096 -f "$BASE_DIR/ssh_host_rsa_key" -N "" -q
ssh-keygen -t ed25519 -f "$BASE_DIR/ssh_host_ed25519_key" -N "" -q

# Generate the isolated sshd_config
cat <<EOF > "$CONFIG_FILE"
Port $PORT
HostKey $BASE_DIR/ssh_host_rsa_key
HostKey $BASE_DIR/ssh_host_ed25519_key

# Security & Authentication defaults
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Subsystem configuration
Subsystem sftp internal-sftp
EOF

# Firewall configuration function
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
        echo " -> Opened port $p using iptables (Note: this rule won't survive a reboot without iptables-persistent)."
    else
        echo " -> Warning: No supported active firewall found. Port $p might need manual opening."
    fi
}

open_firewall_port $PORT

# Generate the systemd service file
echo "Creating systemd service: $SERVICE_NAME..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Custom SSHd instance ($INSTANCE_NAME)
After=network.target auditd.service

[Service]
# -D prevents sshd from detaching, which systemd prefers for standard services
ExecStart=$SSHD_BIN -D -f $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
echo "Starting and enabling the service..."
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "----------------------------------------------------"
echo "Success! SSH Server '$INSTANCE_NAME' is running and will auto-restart."
echo "Port: $PORT"
echo "Config: $CONFIG_FILE"
echo "Service: $SERVICE_NAME"
echo ""
echo "To check status: systemctl status $SERVICE_NAME"
echo "To view logs: journalctl -u $SERVICE_NAME -f"
echo "To completely remove: systemctl disable --now $SERVICE_NAME && rm $SERVICE_FILE && rm -rf $BASE_DIR"
echo "----------------------------------------------------"
