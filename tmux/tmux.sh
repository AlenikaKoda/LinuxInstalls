#!/usr/bin/env bash

# --------------------------
# 1. Install Tmux (Cross-Distro)
# --------------------------
if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux not found. Attempting to install..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y tmux
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm tmux
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y tmux
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y tmux
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add tmux
    else
        echo "Error: Could not detect package manager. Please install tmux manually."
        exit 1
    fi
    echo "tmux installed successfully!"
else
    echo "tmux is already installed."
fi

# --------------------------
# 2. Apply Configuration
# --------------------------
TMUX_CONF="$HOME/.tmux.conf"

# Forcibly remove existing config without backing up
rm -f "$TMUX_CONF"

# Write the new configuration
cat << 'EOF' > "$TMUX_CONF"
# ==========================
# Tmux Minimal Style Config
# ==========================

# --------------------------
# Neovim / True Color Fixes
# --------------------------
# Use modern tmux term if available, fixes background bleeding
set -g default-terminal "tmux-256color"

# Force True Color (RGB/Tc) for ALL terminal emulators (* wildcard)
set -ag terminal-overrides ",*:Tc"
set -ag terminal-overrides ",*:RGB"

# Pass through undercurl (squiggles) for Neovim
set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
# Pass through colored underlines for Neovim
set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

# Fix Neovim ESC delay
set -sg escape-time 10
# Allow Neovim to detect when the terminal window gains/loses focus
set -g focus-events on

# --------------------------
# Status Bar
# --------------------------
set -g status-style "bg=default,fg=default"
set -g status-justify centre
set -g status-position bottom

# Left side: Session name
set -g status-left-length 40
set -g status-left "#[fg=green,bold][#S] #[default]"

# Right side: Minimal time and date
set -g status-right-length 40
set -g status-right "#[fg=color244]%H:%M #[fg=color250]%d-%b"

# --------------------------
# Window Status
# --------------------------
# Inactive windows
set -g window-status-format " #I:#W "
set -g window-status-style "bg=default,fg=color244"

# Active window (highlighted subtly)
set -g window-status-current-format " #I:#W "
set -g window-status-current-style "bg=default,fg=cyan,bold"

# --------------------------
# Pane Borders
# --------------------------
set -g pane-border-style "fg=color238"
set -g pane-active-border-style "fg=cyan"

# --------------------------
# Quality of Life
# --------------------------
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
EOF

echo "Old configuration deleted and new configuration applied to $TMUX_CONF!"

# Reload tmux if it is currently running
if [ -n "$TMUX" ]; then
    tmux source-file "$TMUX_CONF"
    echo "Live tmux session reloaded with new styles."
fi
