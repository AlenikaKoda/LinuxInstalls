#!/bin/bash
echo "=== Installing Lan Mouse ==="
if command -v paru &> /dev/null; then
    paru -S --noconfirm lan-mouse
elif command -v yay &> /dev/null; then
    yay -S --noconfirm lan-mouse
else
    sudo pacman -S --noconfirm lan-mouse
fi

echo -e "\n=== Configuring Firewall (Port 4242 TCP/UDP) ==="
# Detect Firewalld
if systemctl is-active --quiet firewalld; then
    echo "Firewalld detected. Applying permanent rules..."
    sudo firewall-cmd --zone=public --add-port=4242/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=4242/udp --permanent
    sudo firewall-cmd --reload
    echo "Firewalld rules applied."
# Detect UFW
elif command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    echo "UFW detected. Applying rules..."
    sudo ufw allow 4242/tcp
    sudo ufw allow 4242/udp
    echo "UFW rules applied."
else
    echo "Neither UFW nor Firewalld was detected. Make sure to open port 4242 manually."
fi

echo -e "\nLan Mouse setup complete!"
