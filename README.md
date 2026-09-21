# LinuxInstalls
Personal Linux installation scripts.

## Git
Gitea based git server.

## Nvim
A scripted Neovim setup built around C/C++ development (CMake + clangd + codelldb), with LSP support for Go, C#, TypeScript/JavaScript, HTML, and CSS alongside it. `setup_neovim.sh` handles installing dependencies and putting everything in place; the actual config lives in `config/` as plain files, not embedded in the script.

Supports **Fedora, Ubuntu, Debian, and Arch Linux** (and their common derivatives — Pop!_OS, Linux Mint, Manjaro, EndeavourOS, etc. — via `/etc/os-release`'s `ID_LIKE`) — the script detects which one you're on and uses the right package manager and package names automatically.

## Lan Mouse
lan-mouse shares your mouse and keyboard across multiple computers over your local network. Moving your cursor off the edge of one screen seamlessly switches control to the other machine, and syncs your clipboard so you can copy and paste text between them.

## SSH
A lightweight Bash suite that automatically creates, configures, and safely removes completely isolated OpenSSH server instances on Linux. 
Perfect for providing dedicated SSH access to specific users, teams, or applications without modifying your primary server's SSH configuration.

## TMux
Simple TMux installation and configuration.

## MOTD
Ralsei `/etc/motd` installer, requires [cpo](#cpo)

## CPO
Utility command that merges `cp` and `chown`, copies a file or directory and changes ownership based on the destination location.

## MVO
Utility command that merges `mv` and `chown`, moves a file or directory and changes ownership based on the destination location.
