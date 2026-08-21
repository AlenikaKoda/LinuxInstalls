
# Multi-Instance SSH Server Manager
A lightweight Bash suite that automatically creates, configures, and safely removes completely isolated OpenSSH server instances on Linux. 
Perfect for providing dedicated SSH access to specific users, teams, or applications without modifying your primary server's SSH configuration.

## Features
* **User Restriction:** Prompts for a username during setup, optionally creates the user, and uses `AllowUsers` to restrict the instance exclusively to them.
* **Complete Isolation:** Each instance gets its own configuration directory (`/opt/custom_sshd/<name>`) and independent host keys.
* **Auto-Port Assignment:** Automatically scans for the next available port starting from `2222` to prevent collisions.
* **Systemd Integration:** Generates a dedicated `systemd` service for each instance so they start on boot and auto-restart if they crash.
* **Auto-Firewall Management:** Detects your active firewall (`ufw`, `firewalld`, or `iptables`) to open the port on creation, and cleanly closes it on removal.

## Setup
Make both scripts executable:
```bash
chmod +x create_ssh_service.sh
chmod +x remove_ssh_service.sh
```

## Creating an Instance
Pass the desired name of your instance as the argument. You will be prompted to specify (and optionally create) the user who is allowed to connect.

```bash
sudo ./create_ssh_service.sh contractor
```

**Connection Example:**
```bash
ssh -p 2222 bob@your-server-ip
```

## Removing an Instance

To cleanly tear down an instance, close its firewall port, remove its systemd service, and optionally delete the user data:
```bash
sudo ./remove_ssh_service.sh contractor
```

## Manual Service Management
Every instance runs as its own systemd service named `custom-sshd-<instance_name>.service`.
* **Check status:** `sudo systemctl status custom-sshd-contractor.service`
* **View logs:** `sudo journalctl -u custom-sshd-contractor.service -f`
* **Restart:** `sudo systemctl restart custom-sshd-contractor.service`
