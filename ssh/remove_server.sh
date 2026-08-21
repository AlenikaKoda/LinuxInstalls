#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
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

if [ ! -d "$BASE_DIR" ]; then
  echo "Error: Instance '$INSTANCE_NAME' does not seem to exist in $BASE_DIR."
  exit 1
fi

# Extract variables from config before deleting
PORT=$(grep "^Port " "$CONFIG_FILE" | awk '{print $2}')
SSH_USER=$(grep "^AllowUsers " "$CONFIG_FILE" | awk '{print $2}')

echo "Stopping and disabling service $SERVICE_NAME..."
systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

echo "Removing systemd unit and reloading daemon..."
rm -f "$SERVICE_FILE"
systemctl daemon-reload

echo "Removing instance configuration directory..."
rm -rf "$BASE_DIR"

# --- FIREWALL CLEANUP ---
close_firewall_port() {
    local p=$1
    if [ -n "$p" ]; then
        echo "Closing firewall port $p..."
        if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --remove-port=${p}/tcp >/dev/null
            firewall-cmd --reload >/dev/null
            echo " -> Closed port $p using firewalld."
        elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
            ufw delete allow ${p}/tcp >/dev/null
            echo " -> Closed port $p using ufw."
        elif command -v iptables >/dev/null 2>&1; then
            iptables -D INPUT -p tcp --dport ${p} -j ACCEPT 2>/dev/null || true
            echo " -> Closed port $p using iptables."
        fi
    fi
}
close_firewall_port "$PORT"

echo "----------------------------------------------------"
echo "Instance '$INSTANCE_NAME' completely removed."

# --- USER CLEANUP PROMPT ---
if [ -n "$SSH_USER" ] && id "$SSH_USER" >/dev/null 2>&1; then
    echo "----------------------------------------------------"
    echo "This instance was restricted to the user '$SSH_USER'."
    read -p "Do you want to permanently DELETE user '$SSH_USER' and their HOME directory? [y/N] " DEL_USER
    if [[ "$DEL_USER" =~ ^[Yy]$ ]]; then
        userdel -r "$SSH_USER"
        echo "User '$SSH_USER' and their home directory have been deleted."
    else
        echo "User '$SSH_USER' was left untouched."
    fi
fi
echo "----------------------------------------------------"
