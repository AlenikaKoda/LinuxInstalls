# Multi-Instance SSH Server Generator

A lightweight Bash script that automatically creates, configures, and manages completely isolated OpenSSH server instances on Linux. 

Perfect for providing dedicated SSH access to specific teams, contractors, or applications without touching your primary server's SSH configuration.

## Features

* **Complete Isolation:** Each instance gets its own configuration directory (`/opt/custom_sshd/<name>`) and independent host keys.
* **Auto-Port Assignment:** Automatically scans for the next available port starting from `2222` to prevent collisions.
* **Systemd Integration:** Generates a dedicated `systemd` service for each instance so they start on boot and auto-restart if they crash.
* **Auto-Firewall:** Detects your active firewall (`ufw`, `firewalld`, or `iptables`) and automatically opens the required TCP port.

## Prerequisites

* A Linux distribution using `systemd`
* Root privileges (`sudo`)
* `sshd` (OpenSSH Server) installed

## Usage

1. **Make the script executable:**
```bash
   chmod +x create_ssh_service.sh

```

2. **Create a new SSH instance:**
Pass the desired name of your instance as the only argument.
```bash
sudo ./create_ssh_service.sh dev_team

```


3. **Connect to your new instance:**
The script will output the assigned port (e.g., `2222`). Use it to connect:
```bash
ssh -p 2222 username@your-server-ip

```

## Management & Maintenance

Every instance runs as its own systemd service named `custom-sshd-<instance_name>.service`.

**Check status:**

```bash
sudo systemctl status custom-sshd-dev_team.service

```

**View live logs:**

```bash
sudo journalctl -u custom-sshd-dev_team.service -f

```

**Restart the instance:**

```bash
sudo systemctl restart custom-sshd-dev_team.service

```

**Completely remove an instance:**

```bash
sudo systemctl disable --now custom-sshd-dev_team.service
sudo rm /etc/systemd/system/custom-sshd-dev_team.service
sudo rm -rf /opt/custom_sshd/dev_team
sudo systemctl daemon-reload

```

Note: If you uninstall, you will need to manually remove the port rule from your firewall.
