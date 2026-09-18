#!/bin/bash

# Resolve this script's own directory so config/ can sit right next to
# it and be found regardless of where/how this is invoked (./setup_neovim.sh,
# bash /some/path/setup_neovim.sh, a symlink, etc.) -- config and other
# files are real, standalone files under config/, not embedded in this
# script, so this script's only job is installing dependencies and
# copying them into place.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: $CONFIG_DIR not found."
    echo "This script expects a config/ directory next to it (keep the two together"
    echo "however you copy/clone this -- e.g. don't move setup_neovim.sh on its own)."
    exit 1
fi

echo

echo "========================================="
echo " Starting Neovim Setup"
echo "========================================="

# 1. Detect distro and install system dependencies
echo "[1/4] Detecting distro and installing system dependencies..."

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot detect your Linux distribution (/etc/os-release not found)."
    echo "This script supports Fedora, Ubuntu, Debian, and Arch Linux."
    exit 1
fi
. /etc/os-release
DISTRO_ID="$ID"
DISTRO_ID_LIKE="${ID_LIKE:-}"

# Normalize into one of: fedora, debian, arch. Checking ID_LIKE too so
# common derivatives (Pop!_OS, Linux Mint, Manjaro, EndeavourOS, etc.)
# land in the right family even though only the four distros above
# were specifically asked for.
case "$DISTRO_ID $DISTRO_ID_LIKE" in
    *fedora*|*rhel*)
        DISTRO_FAMILY="fedora"
        ;;
    *arch*)
        DISTRO_FAMILY="arch"
        ;;
    *debian*|*ubuntu*)
        DISTRO_FAMILY="debian"
        ;;
    *)
        echo "ERROR: Unsupported or undetected distro (ID=$DISTRO_ID, ID_LIKE=$DISTRO_ID_LIKE)."
        echo "This script supports Fedora, Ubuntu, Debian, and Arch Linux."
        exit 1
        ;;
esac
echo "Detected: $DISTRO_ID (family: $DISTRO_FAMILY)"

# Which Neovim frontend(s) to set up. Neovide (a separate GUI
# application) always runs the real `nvim` binary as its backend --
# the terminal-based install right below happens either way and is
# what Neovide itself depends on -- this choice only controls whether
# Neovide is ALSO installed on top of it. Both frontends share the
# exact same config (see config/nvim/init.lua's `if vim.g.neovide`
# block), so there's nothing else to pick between; this is purely an
# installation question.
NVIM_FRONTEND="terminal"
if [ -t 0 ]; then
    echo
    echo "Which Neovim frontend(s) do you want installed?"
    echo "  1) Terminal-based only (nvim in your terminal)"
    echo "  2) Desktop application only (Neovide GUI -- still needs the nvim"
    echo "     binary below as its backend, so that's installed either way)"
    echo "  3) Both"
    read -rp "Enter 1, 2, or 3 [1]: " FRONTEND_CHOICE
    case "$FRONTEND_CHOICE" in
        2) NVIM_FRONTEND="desktop" ;;
        3) NVIM_FRONTEND="both" ;;
        *) NVIM_FRONTEND="terminal" ;;
    esac
else
    echo "Non-interactive shell detected -- defaulting to terminal-based Neovim only."
    echo "Run this script directly (not piped) and choose option 2 or 3 to also install Neovide."
fi

case "$DISTRO_FAMILY" in
    fedora)
        sudo dnf install -y neovim git curl wget gcc gcc-c++ make cmake \
            nodejs npm python3-pip ripgrep fd-find \
            golang clang-tools-extra dotnet-sdk-8.0 unzip fontconfig \
            lldb gdb fish
        ;;

    debian)
        export DEBIAN_FRONTEND=noninteractive
        sudo apt-get update
        # Package name differences from Fedora: g++ (not gcc-c++),
        # golang-go (not golang), clang-tools (not clang-tools-extra --
        # Debian/Ubuntu split clang-format/clang-tidy differently, this
        # is the closest equivalent bundle).
        sudo apt-get install -y neovim git curl wget gcc g++ make cmake \
            nodejs npm python3-pip ripgrep fd-find \
            golang-go clang-tools unzip fontconfig \
            lldb gdb fish

        # fd-find installs its binary as `fdfind` on Debian/Ubuntu (a
        # name clash with an unrelated existing package called `fd`),
        # unlike Fedora/Arch where it's just `fd`. Symlink it so tools
        # that look for a plain `fd` on PATH (e.g. Telescope's
        # find_files) work the same way here as everywhere else.
        if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            echo "Symlinked fdfind -> ~/.local/bin/fd (make sure ~/.local/bin is on your PATH)."
        fi

        # .NET SDK: Ubuntu ships dotnet-sdk-8.0 directly in its own
        # repos. Debian does not (long-standing packaging/licensing
        # reasons) and needs Microsoft's own apt feed added first.
        # Best-effort either way -- a failure here doesn't stop the
        # rest of the script, since this only matters for C#/omnisharp.
        if [ "$DISTRO_ID" = "ubuntu" ] || echo "$DISTRO_ID_LIKE" | grep -qi ubuntu; then
            sudo apt-get install -y dotnet-sdk-8.0 || \
                echo "WARNING: dotnet-sdk-8.0 install failed -- see https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu-install"
        else
            (
                set -e
                DEBIAN_MAJOR="${VERSION_ID%%.*}"
                wget -q "https://packages.microsoft.com/config/debian/${DEBIAN_MAJOR}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
                sudo dpkg -i /tmp/packages-microsoft-prod.deb
                rm -f /tmp/packages-microsoft-prod.deb
                sudo apt-get update
                sudo apt-get install -y dotnet-sdk-8.0
            ) || echo "WARNING: dotnet-sdk-8.0 install failed -- see https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian for manual steps"
        fi
        ;;

    arch)
        # Arch's own wiki explicitly warns against `pacman -Sy
        # <package>` (sync without upgrading first) -- it risks
        # partial-upgrade dependency issues. -Syu first is the
        # recommended safe order; this does mean the script also
        # upgrades your existing packages, not just installs new ones,
        # which is expected/intentional here, not a side effect to
        # work around.
        sudo pacman -Syu --noconfirm
        # Package name differences from Fedora: gcc includes g++
        # already (no separate gcc-c++ package), python-pip (not
        # python3-pip -- Arch's default python already is python3),
        # fd (not fd-find), go (not golang), clang bundles clang-format/
        # clang-tidy directly (no separate clang-tools-extra).
        sudo pacman -S --noconfirm neovim git curl wget gcc make cmake \
            nodejs npm python-pip ripgrep fd \
            go clang dotnet-sdk-8.0 unzip fontconfig \
            lldb gdb fish
        ;;
esac

# Neovide install, if chosen above. Best-effort, same philosophy as
# the .NET SDK install below: a failure here is a WARNING, not a
# reason to stop the rest of the setup.
if [ "$NVIM_FRONTEND" = "desktop" ] || [ "$NVIM_FRONTEND" = "both" ]; then
    echo "Installing Neovide (desktop Neovim GUI)..."
    case "$DISTRO_FAMILY" in
        arch)
            # Packaged directly upstream -- see
            # https://neovide.dev/installation.html#arch-linux
            sudo pacman -S --noconfirm neovide libxkbcommon-x11 || \
                echo "WARNING: Neovide install failed -- see https://neovide.dev/installation.html"
            ;;
        fedora|debian)
            # Neither Fedora nor Debian/Ubuntu package Neovide --
            # upstream's own install docs point at building it from
            # source via cargo instead. This pulls in a Rust
            # toolchain (via rustup, only if cargo isn't already on
            # PATH) and compiles Neovide and its dependency tree,
            # which can take several minutes.
            echo "Neovide has no Fedora/Debian/Ubuntu package -- building it from source"
            echo "(via cargo -- this can take several minutes)..."
            (
                set -e
                case "$DISTRO_FAMILY" in
                    fedora)
                        sudo dnf install -y clang ninja-build fontconfig-devel freetype-devel \
                            @development-tools libstdc++-static libstdc++-devel
                        ;;
                    debian)
                        sudo apt-get install -y curl gnupg ca-certificates git clang ninja-build \
                            gcc-multilib g++-multilib cmake libssl-dev pkg-config libfreetype6-dev \
                            libasound2-dev libexpat1-dev libxcb-composite0-dev libbz2-dev libsndio-dev \
                            freeglut3-dev libxmu-dev libxi-dev libfontconfig1-dev libxcursor-dev
                        ;;
                esac
                if ! command -v cargo >/dev/null 2>&1; then
                    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                fi
                # shellcheck disable=SC1091
                . "$HOME/.cargo/env"
                cargo install --git https://github.com/neovide/neovide --locked
            ) || echo "WARNING: Neovide build failed -- see https://neovide.dev/installation.html#linux-source for manual steps"
            ;;
    esac
fi

# This config relies on fairly recent Neovim APIs (vim.lsp.config/
# enable, virtual_lines diagnostics, vim.o.winborder -- all 0.11+).
# Distro-packaged Neovim can lag well behind that, especially on
# Debian stable and older Ubuntu LTS releases. Warn (don't fail) if
# what actually got installed is too old.
NVIM_VER_LINE=$(nvim --version 2>/dev/null | head -n1)
NVIM_MAJOR=$(echo "$NVIM_VER_LINE" | sed -n 's/.*v\([0-9]*\)\.\([0-9]*\).*/\1/p')
NVIM_MINOR=$(echo "$NVIM_VER_LINE" | sed -n 's/.*v\([0-9]*\)\.\([0-9]*\).*/\2/p')
if [ -n "$NVIM_MAJOR" ] && [ -n "$NVIM_MINOR" ] && [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -lt 11 ]; then
    echo "WARNING: Installed Neovim is v${NVIM_MAJOR}.${NVIM_MINOR}, but this config needs 0.11+."
    echo "         Debian stable and older Ubuntu LTS releases often ship an older"
    echo "         version. See https://github.com/neovim/neovim/blob/master/INSTALL.md"
    echo "         for official AppImage/PPA/prebuilt options if so."
fi

# Install global NPM packages for JS/TS, HTML, and CSS LSPs
echo "Installing NPM-based LSPs..."
sudo npm install -g typescript typescript-language-server vscode-langservers-extracted

# 2. Install Nerd Fonts (JetBrainsMono and Cascadia Code)
echo "[2/4] Installing JetBrainsMono and Cascadia Code Nerd Fonts..."
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# JetBrainsMono
if [ ! -f "$FONT_DIR/JetBrainsMonoNerdFont-Regular.ttf" ]; then
    wget -q --show-progress https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O /tmp/JetBrainsMono.zip
    unzip -q -o /tmp/JetBrainsMono.zip -d "$FONT_DIR"
    rm /tmp/JetBrainsMono.zip
    echo "JetBrainsMono Nerd Font downloaded."
else
    echo "JetBrainsMono Nerd Font already installed."
fi

# Cascadia Code (CaskaydiaCove)
if [ ! -f "$FONT_DIR/CaskaydiaCoveNerdFont-Regular.ttf" ]; then
    wget -q --show-progress https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip -O /tmp/CascadiaCode.zip
    unzip -q -o /tmp/CascadiaCode.zip -d "$FONT_DIR"
    rm /tmp/CascadiaCode.zip
    echo "Cascadia Code Nerd Font downloaded."
else
    echo "Cascadia Code Nerd Font already installed."
fi

# Update font cache
fc-cache -fv
echo "Fonts installed and cache updated successfully!"

# 3. Delete existing Neovim config
echo "[3/4] Deleting existing Neovim configurations..."
if [ -d "$HOME/.config/nvim" ]; then
    rm -fr "$HOME/.config/nvim"
fi
if [ -d "$HOME/.local/share/nvim" ]; then
    rm -fr "$HOME/.local/share/nvim"
fi

# 4. Install Neovim configuration (copied from config/nvim, not
# embedded in this script -- edit those files directly to customize).
echo "[4/4] Installing new Neovim configuration..."
NVIM_DIR="$HOME/.config/nvim"
mkdir -p "$NVIM_DIR/lua/plugins"
mkdir -p "$NVIM_DIR/lua/dap/configurations"

cp "$CONFIG_DIR/nvim/init.lua" "$NVIM_DIR/init.lua"
cp "$CONFIG_DIR/nvim/lua/plugins/init.lua" "$NVIM_DIR/lua/plugins/init.lua"
cp "$CONFIG_DIR/nvim/lua/dap/configurations/cmake.lua" "$NVIM_DIR/lua/dap/configurations/cmake.lua"

# --- ~/.clang-format, ~/.clang-tidy, and ~/cpp-style-guide.md ---
# Personal fallback style, implementing a specific C/C++ coding style
# guide (naming conventions, brace style, include ordering, etc. --
# see the comments in each file for exactly which guide section a
# given setting maps to, and cpp-style-guide.md itself for the guide
# those comments point into). Both tools walk UP from the file being
# checked/formatted looking for their respective config file; $HOME
# sits above every project you'll open, so these become your default
# for any project that doesn't ship its own .clang-format/.clang-tidy
# (a project's own file, being closer to the file, always takes
# precedence over these).
#
# <leader>lf (LSP format) and <leader>lt (clang-tidy --fix) each only
# consume .clang-format / .clang-tidy respectively. clangd's live
# diagnostics pick up .clang-tidy automatically too (clang-tidy
# integration is on by default in clangd).
#
# Copied unconditionally (not "if missing") every run, same as the
# rest of this config -- so a stray pre-existing file from some other
# tool can't silently block these from taking effect.
cp "$CONFIG_DIR/clang-format" "$HOME/.clang-format"
cp "$CONFIG_DIR/clang-tidy" "$HOME/.clang-tidy"
cp "$CONFIG_DIR/cpp-style-guide.md" "$HOME/cpp-style-guide.md"

echo "Wrote ~/.clang-format and ~/.clang-tidy (Allman braces, real tabs), and ~/cpp-style-guide.md."

echo "========================================="
echo " Setup Complete!"
echo " Run 'nvim'. p and P are restored, use <leader>p to force inline paste!"
echo " Debugger: <leader>db to set a breakpoint, F5 / <leader>dc to start/continue,"
echo " <leader>du to toggle the debug UI. First debug session will auto-install codelldb via Mason."
echo " Project-specific CMake debug targets loaded from ~/.config/nvim/lua/dap/configurations/cmake.lua"
if [ "$NVIM_FRONTEND" = "desktop" ] || [ "$NVIM_FRONTEND" = "both" ]; then
    echo " Neovide: run 'neovide' to launch the desktop app (same config, same keymaps)."
    echo " If the command isn't found yet, open a new shell first (rustup updates PATH"
    echo " in shell startup files, which this script's own shell won't have re-read)."
fi
echo "========================================="
