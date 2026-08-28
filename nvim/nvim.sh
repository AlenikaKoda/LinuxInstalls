#!/bin/bash

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

# 4. Create Neovim Configuration Structure
echo "[4/4] Writing new Neovim configuration..."
NVIM_DIR="$HOME/.config/nvim"
mkdir -p "$NVIM_DIR/lua/plugins"
mkdir -p "$NVIM_DIR/lua/dap/configurations"

# --- init.lua ---
cat << 'EOF' > "$NVIM_DIR/init.lua"
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic Options
vim.opt.number = true
-- Tab width: 4, using real tab characters (not expanded to spaces)
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = false
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 1000
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.termguicolors = true
vim.opt.hlsearch = true
vim.opt.laststatus = 3 -- global statusline (for lualine)
-- Drops the "N lines, M bytes written" message after :w. Mainly
-- motivated by hex.nvim's save flow: it runs an xxd filter (which
-- prints its own "N lines filtered" message) as part of writing, and
-- the write's own message stacking on top of that is what triggers
-- Vim's "Press ENTER to continue" prompt after every hex-mode save.
-- Removing this message means there's only one left, which doesn't
-- need the prompt.
vim.opt.shortmess:append("W")

-- Styled window borders between splits (nvim-tree, terminal, etc.)
vim.opt.fillchars = {
  eob = " ",
  vert = "│",
  horiz = "─",
  horizup = "┴",
  horizdown = "┬",
  vertleft = "┤",
  vertright = "├",
  verthoriz = "┼",
}
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#3b4261" })
  end,
})

-- Rounded borders on ALL floating windows (hover, signature help, LspInfo,
-- Mason, diagnostics float, etc.) that don't set their own border.
-- Requires Neovim 0.11+; older versions just skip this and fall back to
-- whatever each plugin sets individually.
if vim.fn.has("nvim-0.11") == 1 then
  vim.o.winborder = "rounded"
end

-- Don't auto-continue comments (// , # , etc.) onto a new line when
-- pressing Enter in insert mode or o/O in normal mode -- EXCEPT when
-- the current line is comment-ONLY (nothing but whitespace + the
-- comment itself, no real code before it), where continuing onto the
-- next line with the same comment marker is actually convenient
-- (writing a multi-line comment block) rather than the annoying case
-- (writing code that happens to have a trailing comment, then hitting
-- Enter to write MORE code and getting an unwanted comment prefix
-- inserted). Many filetypes' own ftplugins (e.g. c.vim) set
-- 'formatoptions' with these flags as part of their own FileType
-- handling -- this runs on the same event, registered afterward, so
-- it reliably strips them back off regardless of what a given
-- filetype's ftplugin set; the <CR> mapping further below re-adds 'r'
-- for just the one keypress when the comment-only condition applies.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

-- SSH Clipboard Support (OSC 52)
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    -- We now return BOTH the text and the register type ('v', 'V', or '^V')
    -- This restores native p and P line-wise behavior
    ['+'] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end,
    ['*'] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end,
  },
}

-- GENERAL KEYMAPS --

-- Clear search highlight on pressing Esc in normal mode
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Is the cursor's current line comment-ONLY -- i.e. its first
-- non-blank character falls inside a treesitter comment node, meaning
-- there's no real code before the comment on this line? Using
-- treesitter's `comment` node type rather than per-filetype regex
-- (// vs # vs -- etc.) since virtually every grammar names it the
-- same way, so this works generically across languages rather than
-- needing a pattern maintained per filetype. Queries a single point
-- (the first non-blank column) rather than a range spanning the whole
-- line, since a range query only succeeds if it fits entirely inside
-- one node -- comment nodes don't always extend to the exact byte
-- offset a plain string length points at (trailing whitespace,
-- multi-byte characters), and a point query avoids depending on that.
local function cursor_line_is_comment_only()
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then
    return false
  end
  local line = vim.api.nvim_get_current_line()
  local first_col = line:find("%S")
  if not first_col then
    return false
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local ok2, tree = pcall(function() return parser:parse()[1] end)
  if not ok2 or not tree then
    return false
  end
  local col = first_col - 1
  local node = tree:root():named_descendant_for_range(row, col, row, col + 1)
  while node do
    if node:type():match("comment") then
      return true
    end
    node = node:parent()
  end
  return false
end

-- <CR> in insert mode: on a comment-only line, repeats the line's
-- comment marker (and a single following space, if one was there) on
-- the new line -- twice in a row with nothing typed in between breaks
-- out instead of continuing again, matching Vim's own long-standing
-- convention for this.
--
-- This used to reuse Neovim's native comment-leader logic instead, by
-- temporarily appending 'r' to formatoptions around the <CR>
-- keypress and reverting it via vim.schedule() afterward -- that
-- never actually worked: there's no guarantee the scheduled revert
-- runs AFTER Neovim's own logic gets to read formatoptions during
-- that same <CR>'s processing, and apparently it ran first every
-- time, removing 'r' before it could take effect. Computing the
-- prefix directly and returning it as part of the same keystring
-- sidesteps that ordering question entirely -- nothing here depends
-- on when anything else happens to run.
--
-- Covers //, #, and -- (C-family/JS/TS/Go, Python/bash/YAML/CMake,
-- and Lua/SQL respectively) rather than being fully comment-syntax-
-- agnostic like the detection above -- that's the trade-off for not
-- depending on formatoptions/'comments' timing.
--
-- NOTE: this mapping ends up invoked through nvim-cmp's OWN <CR>
-- fallback chain, not called directly by Neovim -- cmp.setup() runs
-- after this file's top-level code and, per its own keymap-
-- composition system (cmp/utils/keymap.lua), absorbs whatever <CR>
-- mapping already existed as the function it calls when its
-- completion menu isn't visible, rather than simply discarding it.
-- That has two consequences: (1) it still runs under a textlock, so
-- direct buffer edits like nvim_set_current_line() throw E565 --
-- fixed below by returning keys instead; (2) it runs on literally
-- every <CR> press everywhere, including while navigating a LuaSnip
-- snippet session, which this was never meant to touch at all --
-- guarded against below by bailing out to a plain <CR> whenever one
-- is active for the buffer.
vim.keymap.set('i', '<CR>', function()
  local ok_ls, luasnip = pcall(require, "luasnip")
  if ok_ls and luasnip.session.current_nodes[vim.api.nvim_get_current_buf()] then
    return '<CR>'
  end

  local line = vim.api.nvim_get_current_line()

  -- Current line is JUST a marker with nothing typed after it (i.e.
  -- the previous <CR> continued the comment and nothing was added
  -- since) -- break out: clear the line and start fresh, rather than
  -- continuing yet again. Without this, pressing Enter repeatedly
  -- with nothing typed in between just continues forever.
  --
  -- <Esc>S (leave insert mode, then substitute-line) rather than
  -- calling nvim_set_current_line() directly -- direct buffer edits
  -- aren't allowed from inside this callback (see the textlock note
  -- above), so the change has to be expressed as keys to feed
  -- instead, same as the <CR> continuation itself already is.
  if line:match("^%s*//%s?$") or line:match("^%s*#%s?$") or line:match("^%s*%-%-%s?$") then
    return '<Esc>S'
  end

  if cursor_line_is_comment_only() then
    -- Only the marker itself gets typed onto the new line -- NOT the
    -- current line's own leading whitespace. The active indent logic
    -- (cindent, etc.) already indents the new line to match on its
    -- own; re-typing the captured leading whitespace on top of that
    -- is what compounded further right on every single Enter before.
    local prefix = line:match("^%s*(//%s?)")
      or line:match("^%s*(#%s?)")
      or line:match("^%s*(%-%-%s?)")
    if prefix then
      return '<CR>' .. prefix
    end
  end
  return '<CR>'
end, { expr = true, desc = "Smart comment-continuing newline" })

-- Clears the current line's content, leaving it as a blank line in
-- place rather than deleting the line itself (which would shift
-- everything below it up, like dd does). Motivating case: undoing an
-- auto-continued comment from the mapping above when you didn't
-- actually want it, without backspacing it out character by
-- character.
vim.keymap.set('n', '<leader>cb', function()
  vim.api.nvim_set_current_line("")
end, { desc = "Clear Line (Blank)" })

-- Forced Inline Paste (The behavior you liked)
-- This forces the pasted text to be treated as characters at your exact cursor position
vim.keymap.set('n', '<leader>p', function()
  local reg_content = vim.fn.getreg('"', 1, true)
  vim.api.nvim_put(reg_content, 'c', true, true)
end, { desc = "Force Paste Inline" })

-- Visual mode paste: Prevent replacing the unnamed register when pasting over selected text
vim.keymap.set("x", "p", '"_dP')
vim.keymap.set("x", "P", '"_dP')

-- Move lines up and down in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Move current line/selection up and down with Alt+j/k, across
-- normal, insert, and visual mode.
vim.keymap.set('n', '<A-j>', ':m .+1<CR>==', { desc = "Move line down" })
vim.keymap.set('n', '<A-k>', ':m .-2<CR>==', { desc = "Move line up" })
vim.keymap.set('i', '<A-j>', '<Esc>:m .+1<CR>==gi', { desc = "Move line down" })
vim.keymap.set('i', '<A-k>', '<Esc>:m .-2<CR>==gi', { desc = "Move line up" })
vim.keymap.set('v', '<A-j>', ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set('v', '<A-k>', ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Easy Save
vim.keymap.set({'n', 'v', 'i'}, '<C-s>', '<cmd>w<CR><Esc>', { desc = "Save File" })

-- Window Navigation (Ctrl + h/j/k/l)
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = "Go to left window" })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = "Go to lower window" })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = "Go to upper window" })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = "Go to right window" })

-- Window Splits (Namespaced under <leader>s)
vim.keymap.set('n', '<leader>sv', '<C-w>v', { desc = "Split Vertically" })
vim.keymap.set('n', '<leader>sh', '<C-w>s', { desc = "Split Horizontally" })
vim.keymap.set('n', '<leader>se', '<C-w>=', { desc = "Make Splits Equal" })
vim.keymap.set('n', '<leader>sx', '<cmd>close<CR>', { desc = "Close Current Split" })

-- ---------------------------------------------------------------------
-- Neovim 0.12 compatibility shim for nvim-treesitter's legacy (master
-- branch) query predicates/directives.
--
-- In Neovim 0.12 a capture in `match[id]` can now be a LIST of TSNode
-- instead of a single TSNode (for captures that quantify to more than
-- one node). nvim-treesitter's `master` branch is frozen for backward
-- compatibility and its query_predicates.lua still assumes a single
-- node everywhere, so it calls node:range() on what's now a table and
-- throws "attempt to call method 'range' (a nil value)". This is a
-- known, currently unresolved upstream issue (nvim-treesitter/nvim-
-- treesitter#8618 and #8636, both closed "not planned" since master
-- won't receive further fixes). It's cosmetic -- highlighting still
-- works -- but it spams :messages, most often on markdown files
-- (fenced code blocks use the conceal_lines directive).
--
-- This wraps query.add_predicate/add_directive so any capture that has
-- "spilled" into a list of nodes is transparently unwrapped to its
-- first node before the underlying handler runs, restoring the
-- single-node behavior those legacy handlers expect. Must run before
-- nvim-treesitter is loaded (its query_predicates.lua registers its
-- handlers at require-time), so this sits above the lazy.nvim
-- bootstrap/setup call below.
-- ---------------------------------------------------------------------
do
  local query = vim.treesitter.query
  local function normalize_match(match)
    local out = {}
    for id, val in pairs(match) do
      if type(val) == "table" and val[1] ~= nil and type(val[1]) == "userdata" then
        out[id] = val[1]
      else
        out[id] = val
      end
    end
    return out
  end

  local orig_add_predicate = query.add_predicate
  query.add_predicate = function(name, handler, opts)
    return orig_add_predicate(name, function(match, ...)
      return handler(normalize_match(match), ...)
    end, opts)
  end

  local orig_add_directive = query.add_directive
  query.add_directive = function(name, handler, opts)
    return orig_add_directive(name, function(match, ...)
      return handler(normalize_match(match), ...)
    end, opts)
  end
end

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")
EOF

# --- plugins.lua ---
cat << 'EOF' > "$NVIM_DIR/lua/plugins/init.lua"
return {
  -- REALLY Dark Theme (Pitch Black TokyoNight)
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "night",
        transparent = false,
        on_colors = function(colors)
          colors.bg = "#000000" -- Pure black background
          colors.bg_dark = "#000000"
          colors.bg_float = "#050505"
          colors.bg_highlight = "#1a1a1a"
          colors.bg_popup = "#050505"
          colors.bg_sidebar = "#000000"
          colors.bg_statusline = "#000000"
        end,
        on_highlights = function(hl, c)
          hl.DiagnosticVirtualTextError = { bg = "#351010", fg = c.error }
          hl.DiagnosticVirtualTextWarn  = { bg = "#35280b", fg = c.warning }
          hl.DiagnosticVirtualTextInfo  = { bg = "#0b2035", fg = c.info }
          hl.DiagnosticVirtualTextHint  = { bg = "#0b3528", fg = c.hint }

          hl.DiagnosticVirtualLinesError = { bg = "#351010", fg = c.error }
          hl.DiagnosticVirtualLinesWarn  = { bg = "#35280b", fg = c.warning }
          hl.DiagnosticVirtualLinesInfo  = { bg = "#0b2035", fg = c.info }
          hl.DiagnosticVirtualLinesHint  = { bg = "#0b3528", fg = c.hint }
        end,
      })
      vim.cmd[[colorscheme tokyonight]]
    end,
  },

  -- Treesitter (syntax-aware highlighting + indentation)
  --
  -- NOTE: pinned to branch = "master". Upstream's default branch is now
  -- "main", which is a full incompatible rewrite that deleted the old
  -- require("nvim-treesitter.configs").setup({...}) API entirely (this
  -- is what caused "module 'nvim-treesitter.configs' not found"). The
  -- "master" branch is explicitly kept frozen by upstream for backward
  -- compatibility with this config style, so pin to it rather than
  -- rewriting everything against the new API.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "c", "cpp", "lua", "go", "python", "javascript", "typescript",
          "html", "css", "bash", "json", "yaml", "markdown", "cmake",
          "doxygen",
        },
        highlight = { enable = true },
        indent = {
          enable = true,
          -- treesitter's indent module is well-known to be unreliable
          -- for a handful of languages specifically (inconsistent
          -- brace placement, phantom extra indent on nested blocks)
          -- while being fine for the rest. This is more pronounced on
          -- the "master" branch pinned above, since it's frozen and
          -- gets no further upstream fixes at all. Disabling it for
          -- these falls back to Neovim's own built-in, per-filetype
          -- indent logic (cindent for c/cpp, the bundled javascript/
          -- typescript indent scripts for the rest), which is far
          -- more predictable for brace-heavy code.
          --
          -- css and json are also curly-brace languages that CAN hit
          -- the same class of issue -- add them here too if you
          -- notice the same symptom there.
          disable = { "c", "cpp", "javascript", "typescript" },
        },
      })
    end,
  },

  -- Doxygen (and other language) doc-comment generation.
  --
  -- Not a language server -- clangd already understands Doxygen syntax
  -- in existing comments (hover/signature-help render @param/@return),
  -- this is the other half: generating the comment skeleton itself.
  -- Place the cursor on/above a function and press <leader>cd to drop
  -- in a Doxygen-style block with @brief/@param/@return stubs already
  -- matching that function's actual parameters and return type.
  {
    "danymat/neogen",
    dependencies = "nvim-treesitter/nvim-treesitter",
    config = function()
      require("neogen").setup({
        enabled = true,
        -- c/cpp's default annotation_convention is already
        -- "doxygen_cpp", so nothing to override there.
        snippet_engine = "luasnip", -- inserted fields become LuaSnip
        -- tabstops, so <Tab>/<S-Tab> (wired up in the nvim-cmp config
        -- below for cmp/LuaSnip) cycles through @brief, each @param,
        -- and @return.
      })
      vim.keymap.set("n", "<leader>cd", function()
        require("neogen").generate()
      end, { desc = "Generate Doxygen Comment" })
    end,
  },

  -- Dashboard (NvChad-style start screen)
  {
    "goolord/alpha-nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")

      dashboard.section.header.val = {
        "                                                     ",
        "  ███╗   ██╗██╗   ██╗██╗███╗   ███╗                 ",
        "  ████╗  ██║██║   ██║██║████╗ ████║                 ",
        "  ██╔██╗ ██║██║   ██║██║██╔████╔██║                 ",
        "  ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║                 ",
        "  ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║                 ",
        "  ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝                 ",
        "                                                     ",
      }

      dashboard.section.buttons.val = {
        dashboard.button("f", "  Find File", "<cmd>Telescope find_files<CR>"),
        dashboard.button("r", "  Recent Files", "<cmd>Telescope oldfiles<CR>"),
        dashboard.button("w", "  Live Grep", "<cmd>Telescope live_grep<CR>"),
        dashboard.button("e", "  New File", "<cmd>ene<CR>"),
        dashboard.button("c", "  Edit Config", "<cmd>edit ~/.config/nvim/init.lua<CR>"),
        dashboard.button("q", "  Quit", "<cmd>qa<CR>"),
      }

      alpha.setup(dashboard.opts)
    end,
  },

  -- Which-Key (Registers your namespaces so the menu looks clean)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      local wk = require("which-key")
      wk.setup({
        delay = 0,
      })
      -- Define group names for the menu
      wk.add({
        { "<leader>b", group = "Buffers" },
        { "<leader>c", group = "Comments" },
        { "<leader>f", group = "Find / Grep" },
        { "<leader>l", group = "LSP" },
        { "<leader>s", group = "Splits" },
        { "<leader>t", group = "Terminal" },
        { "<leader>d", group = "Debug" },
      })
    end,
  },

  -- Telescope (Fuzzy Finding and Grepping)
  {
    "nvim-telescope/telescope.nvim",
    -- NOTE: intentionally NOT pinned to branch = "0.1.x" -- that branch's
    -- previewer calls nvim-treesitter's now-removed `ft_to_lang` helper,
    -- which crashes the file preview with "attempt to call field
    -- 'ft_to_lang' (a nil value)". The current default branch calls the
    -- built-in vim.treesitter.language.get_lang() instead, which isn't
    -- affected by that removal.
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = "Find Files" })
      vim.keymap.set('n', '<leader>fw', builtin.live_grep, { desc = "Find Word (Live Grep)" })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = "Find Open Buffers" })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = "Find Help Tags" })
      vim.keymap.set('n', '<leader>fr', builtin.oldfiles, { desc = "Find Recent Files" })
    end,
  },

  -- NvimTree (On the right)
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = {
          side = "right",
          width = 30,
        },
        -- Routes the paste overwrite/rename CHOICE through
        -- vim.ui.select tagged with kind = "nvimtree_overwrite_rename"
        -- (nvim-tree's own documented hook for this), which the gP
        -- batch-paste below intercepts.
        select_prompts = true,

        -- Keep nvim-tree's own default mappings and add gP on top of
        -- them, via the officially documented on_attach recipe --
        -- rather than the TreeAttachedPost event this used before,
        -- whose handler is passed the bufnr directly as a plain
        -- number (confirmed from nvim-tree's own docs), not a table
        -- with a .buf field -- indexing that number is what threw
        -- "attempt to index local 'data' (a number value)".
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")

          -- The helper that installs the defaults has been named
          -- differently across versions (api.config.mappings.
          -- default_on_attach vs the older api.map.on_attach.default)
          -- -- try both rather than assume one, so this doesn't
          -- silently lose every default mapping on a version where
          -- the other name is the real one.
          if not pcall(api.config.mappings.default_on_attach, bufnr) then
            pcall(api.map.on_attach.default, bufnr)
          end

          -- gP: paste, resolving every naming collision in this one
          -- paste with a single :s///-style pattern/replacement
          --
          -- CAVEAT: this assumes a single-file-style overwrite/rename
          -- choice per conflict. nvim-tree turns out to have a
          -- SEPARATE, differently-shaped dialog specifically for
          -- multi-file conflicts in one paste ("N file(s) already
          -- exist" / Rename (suffix) / Overwrite all / Skip all),
          -- which this doesn't detect or intercept -- so gP is only
          -- confirmed reliable for a single conflicting file. For
          -- "always rename every file, conflict or not" -- which is
          -- what was actually being asked for -- gM below is the
          -- better fit: it doesn't touch nvim-tree's paste/conflict
          -- system at all, just copies marked files directly.
          -- instead of nvim-tree's normal one-at-a-time
          -- overwrite/rename prompt per conflicting file. Plain `p`
          -- (bound above by default_on_attach) is untouched -- this
          -- is a deliberately separate mapping, not a replacement.
          --
          -- nvim-tree doesn't expose a way to enumerate the clipboard
          -- or pre-scan for collisions before pasting (only
          -- print/clear it), and conflicts are resolved one at a time
          -- internally as the paste runs -- there's no "here's the
          -- whole batch" moment to hook into directly. This gets the
          -- same practical result a different way: ask ONCE upfront
          -- for the pattern, then answer nvim-tree's own conflict
          -- prompts programmatically for the duration of that paste
          -- using vim.fn.substitute() (real Vim regex, same engine
          -- :s/// itself uses) against the filename nvim-tree
          -- pre-fills as its default.
          --
          -- vim.ui.select/vim.ui.input are wrapped HERE, at call time
          -- inside the keymap function, rather than once when this
          -- plugin's config runs. nvim-tree loads eagerly at startup,
          -- but dressing.nvim (which ALSO wraps these same two
          -- functions, to prettify them) loads lazily on VeryLazy,
          -- afterward -- wrapping once at config time would capture
          -- the plain pre-dressing versions, which then get silently
          -- overwritten (discarding this wrapper entirely) once
          -- dressing finishes loading. Wrapping fresh on every call
          -- instead always captures whatever's actually active.
          vim.keymap.set('n', 'gP', function()
            vim.ui.input({ prompt = "Rename pattern/replacement (Vim regex, e.g. foo/bar): " }, function(input)
              if not input or input == "" then
                api.fs.paste()
                return
              end
              local pattern, replacement = input:match("^(.-)/(.*)$")
              if not pattern then
                vim.notify("Expected pattern/replacement, e.g. foo/bar", vim.log.levels.WARN)
                return
              end

              local real_select = vim.ui.select
              local real_input = vim.ui.input

              vim.ui.select = function(items, opts, on_choice)
                if opts and opts.kind == "nvimtree_overwrite_rename" then
                  for i, item in ipairs(items) do
                    if tostring(item):lower():match("rename") then
                      on_choice(item, i)
                      return
                    end
                  end
                end
                real_select(items, opts, on_choice)
              end

              vim.ui.input = function(input_opts, on_confirm)
                if input_opts and input_opts.default then
                  local ok, new_name = pcall(vim.fn.substitute, input_opts.default, pattern, replacement, "")
                  on_confirm(ok and new_name ~= "" and new_name or input_opts.default)
                  return
                end
                real_input(input_opts, on_confirm)
              end

              -- Restored via a short defer rather than immediately
              -- after api.fs.paste() returns, since it's not
              -- confirmed whether paste() resolves every prompt
              -- synchronously before returning to caller or defers
              -- some of them -- restoring immediately risked only
              -- patching the FIRST conflict in a multi-file paste and
              -- silently falling back to normal prompts for the rest.
              -- If that's what happens, this assumption is the next
              -- thing to revisit.
              api.fs.paste()
              vim.defer_fn(function()
                vim.ui.select = real_select
                vim.ui.input = real_input
              end, 2000)
            end)
          end, { desc = "nvim-tree: Paste (Batch Rename Regex)", buffer = bufnr, silent = true })

          -- Clears the copy/cut clipboard outright. Useful if it's
          -- holding a stale entry -- a file that's since been
          -- renamed, moved, or deleted -- which pastes as "ENOENT: no
          -- such file or directory" until cleared and re-copied fresh.
          vim.keymap.set('n', 'gC', api.fs.clear_clipboard, { desc = "nvim-tree: Clear Clipboard", buffer = bufnr, silent = true })

          -- gM: copy every MARKED file/folder (toggle a mark with m,
          -- shown as a star) into the directory under the cursor,
          -- applying a single :s///-style pattern/replacement to
          -- EVERY name unconditionally -- not just on collision. This
          -- is deliberately separate from nvim-tree's own copy/paste
          -- clipboard (c/x/p/gP above) entirely: it reads the marked
          -- list via api.marks.list() (a real, documented, stable
          -- API -- unlike the clipboard, which has no equivalent way
          -- to enumerate its contents) and shells out to `cp -r` to
          -- do the actual copying itself, the same approach used in
          -- nvim-tree's own official custom-copy recipe. Marks are
          -- left as-is afterward (not auto-cleared), matching how the
          -- regular clipboard also isn't cleared after a paste --
          -- toggle them off individually with m if you're done with
          -- them.
          vim.keymap.set('n', 'gM', function()
            local marks = api.marks.list()
            if not marks or #marks == 0 then
              vim.notify("No marked files (mark with 'm' first)", vim.log.levels.WARN)
              return
            end
            local cursor_node = api.tree.get_node_under_cursor()
            if not cursor_node then
              return
            end
            local dest_dir = cursor_node.type == "directory" and cursor_node.absolute_path
              or vim.fn.fnamemodify(cursor_node.absolute_path, ":h")

            vim.ui.input({ prompt = "Rename pattern/replacement (Vim regex, e.g. Foo/Bar): " }, function(input)
              if not input or input == "" then
                return
              end
              local pattern, replacement = input:match("^(.-)/(.*)$")
              if not pattern then
                vim.notify("Expected pattern/replacement, e.g. Foo/Bar", vim.log.levels.WARN)
                return
              end
              for _, node in ipairs(marks) do
                if not vim.loop.fs_stat(node.absolute_path) then
                  -- Marks persist by path in nvim-tree's own state and
                  -- are NOT cleared when the underlying file/folder is
                  -- deleted, so a stale mark can point at a path that
                  -- no longer exists (e.g. you marked it, then deleted
                  -- it). Clean up the stale mark itself here instead
                  -- of attempting (and failing) a copy from it.
                  pcall(api.marks.toggle, node)
                  vim.notify("Skipped stale mark (no longer exists): " .. node.absolute_path, vim.log.levels.WARN)
                else
                  local base = vim.fn.fnamemodify(node.absolute_path, ":t")
                  local ok, new_name = pcall(vim.fn.substitute, base, pattern, replacement, "")
                  if not ok or new_name == "" then
                    new_name = base
                  end
                  local dest_path = dest_dir .. "/" .. new_name
                  if dest_path == node.absolute_path then
                    -- The pattern didn't match this particular name
                    -- (so it came back unchanged) and the destination
                    -- is the same directory the file's already in --
                    -- that's a copy onto itself, which cp correctly
                    -- refuses. Skip it up front with a clearer reason
                    -- instead of surfacing cp's raw "same file" error.
                    vim.notify("Skipped " .. base .. ": pattern didn't match, and destination is the same as source", vim.log.levels.WARN)
                  else
                    local result = vim.fn.system({ "cp", "-r", node.absolute_path, dest_path })
                    if vim.v.shell_error ~= 0 then
                      vim.notify("Copy failed for " .. base .. ": " .. result, vim.log.levels.ERROR)
                    end
                  end
                end
              end
              api.tree.reload()
            end)
          end, { desc = "nvim-tree: Copy Marked (Regex Rename)", buffer = bufnr, silent = true })
        end,
      })
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { silent = true, desc = "Toggle File Explorer" })
    end,
  },

  -- Bufferline (Tabs)
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = "nvim_lsp",
          show_buffer_close_icons = false,
          numbers = "ordinal", -- shows 1, 2, 3... on the left of each tab,
          -- matching the position used by the Alt+number jump below.
          --
          -- Makes :BufferLineMovePrev/MoveNext refuse to walk an
          -- unpinned buffer across the pinned block (wraps to the
          -- other end instead) -- this is bufferline's own built-in
          -- boundary check (see get_last_pinned_index/M.move in its
          -- source), just off by default.
          move_wraps_at_ends = true,
        }
      })

      -- Navigate buffers. Using bufferline's own cycle commands rather
      -- than :bprevious/:bnext -- once buffers can be reordered (see
      -- <A-,>/<A-.> below), plain :bnext/:bprevious would cycle by
      -- vim's internal buffer number instead of the order shown on
      -- screen, which stops matching what you actually see. This is
      -- bufferline's own documented recommendation for exactly this
      -- situation.
      vim.keymap.set('n', '<S-h>', '<cmd>BufferLineCyclePrev<cr>', { desc = "Prev buffer" })
      vim.keymap.set('n', '<S-l>', '<cmd>BufferLineCycleNext<cr>', { desc = "Next buffer" })
      vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<cr>', { desc = "Close Current Buffer" })

      -- Alt+1..9: jump straight to the buffer at that ordinal position
      -- (the number shown on the left of each tab). Alt+0 jumps to the
      -- last one, mirroring bufferline's own "$" convention.
      for i = 1, 9 do
        vim.keymap.set('n', ('<A-%d>'):format(i), function()
          require('bufferline').go_to(i, true)
        end, { desc = "Go to Buffer " .. i })
      end
      vim.keymap.set('n', '<A-0>', function()
        require('bufferline').go_to(-1, true)
      end, { desc = "Go to Last Buffer" })

      -- F1..F9: same jump-by-position, on Fn+Number instead of
      -- Alt+Number. Explicitly setting <F1> here overrides Neovim's
      -- default <F1>-opens-help binding outright (any explicit
      -- vim.keymap.set for a key always supersedes Neovim's built-in
      -- default for it), so no separate step is needed to "disable"
      -- that.
      --
      -- <F5> and <F10> are set below, OUTSIDE this loop -- both are
      -- shared with nvim-dap (Continue and Step Over respectively) and
      -- toggle dynamically based on whether a debug session is active
      -- (see the dap.listeners hooks in the DAP plugin further down).
      -- At rest, both act as ordinary buffer jumps like everything
      -- else in this loop.
      for _, i in ipairs({ 1, 2, 3, 4, 6, 7, 8, 9 }) do
        vim.keymap.set('n', ('<F%d>'):format(i), function()
          require('bufferline').go_to(i, true)
        end, { desc = "Go to Buffer " .. i })
      end
      vim.keymap.set('n', '<F5>', function()
        require('bufferline').go_to(5, true)
      end, { desc = "Go to Buffer 5" })
      vim.keymap.set('n', '<F10>', function()
        require('bufferline').go_to(-1, true)
      end, { desc = "Go to Last Buffer" })

      -- Alt+,/. : reorder the current buffer left/right in the
      -- bufferline (persists for the session as long as
      -- sessionoptions includes "globals", which lazy.nvim's default
      -- vimrc already does). move_wraps_at_ends above handles keeping
      -- these from crossing into the pinned block -- no custom guard
      -- needed here.
      vim.keymap.set('n', '<A-,>', '<cmd>BufferLineMovePrev<cr>', { desc = "Move Buffer Left" })
      vim.keymap.set('n', '<A-.>', '<cmd>BufferLineMoveNext<cr>', { desc = "Move Buffer Right" })

      -- Pin the current buffer -- pinned buffers stay pinned to the
      -- start of the bufferline regardless of sorting/reordering.
      --
      -- Pin state is ALSO recorded in a plain buffer-local variable
      -- here, set at the same time as the real toggle. bufferline's
      -- internal pin/group state isn't reliably exposed as a stable
      -- public API across versions -- require('bufferline').group_action
      -- (tried previously) doesn't exist on the version actually
      -- installed here, hence the earlier E5108 error. Tracking it
      -- ourselves means <leader>bx below never has to ask bufferline
      -- which buffers are pinned at all.
      --
      -- :BufferLineTogglePin only updates the RENDER-time grouping; it
      -- doesn't physically move the buffer within bufferline's
      -- internal position list (state.components), which is the exact
      -- list go_to()/number labels are computed from. That gap is what
      -- caused Alt+number to occasionally land on/label the wrong
      -- buffer right after pinning. move_to() operates on that same
      -- internal list directly (it's what :BufferLineMovePrev/Next and
      -- the sort commands use internally), so calling it here forces
      -- the two back into sync immediately: to the front when pinning,
      -- to just after the remaining pinned block when unpinning.
      vim.keymap.set('n', '<leader>bp', function()
        vim.cmd('BufferLineTogglePin')
        local buf = vim.api.nvim_get_current_buf()
        local now_pinned = not vim.b[buf].pinned
        vim.b[buf].pinned = now_pinned

        if now_pinned then
          require('bufferline').move_to(1)
        else
          local pinned_count = 0
          for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
            if b.bufnr ~= buf and vim.b[b.bufnr].pinned then
              pinned_count = pinned_count + 1
            end
          end
          require('bufferline').move_to(pinned_count + 1)
        end
      end, { desc = "Toggle Pin" })

      -- Close every unpinned buffer that has NO unsaved changes, using
      -- the buffer-local pin flag set above -- deliberately not using
      -- :BufferLineGroupClose ungrouped, since its default
      -- close_command is "bdelete! %d" (forced), which would silently
      -- discard unsaved work in any unpinned buffer.
      vim.keymap.set('n', '<leader>bx', function()
        for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
          if not vim.b[buf.bufnr].pinned and buf.changed == 0 then
            pcall(vim.cmd, 'bdelete ' .. buf.bufnr)
          end
        end
      end, { desc = "Close Unpinned Saved Buffers" })
    end,
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "tokyonight",
          component_separators = { left = "│", right = "│" },
          section_separators = { left = "", right = "" },
          globalstatus = true,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diagnostics" },
          lualine_c = { { "filename", path = 1 } },
          lualine_x = { "encoding", "filetype" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })
    end,
  },

  -- ToggleTerm (Floating & Bottom Terminal)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      -- shell = "fish": the embedded terminal launches fish instead of
      -- your login shell. fish has grey inline "ghost text" suggestions
      -- built in (paths, directory contents, and history) with zero
      -- config -- accept with -> or <End>. This only affects terminals
      -- opened from Neovim; your system login shell is untouched.
      require("toggleterm").setup({
        shell = "fish",
      })
      vim.keymap.set('n', '<leader>tf', '<cmd>ToggleTerm direction=float<cr>', { desc = "Floating Terminal" })
      vim.keymap.set('n', '<leader>th', '<cmd>ToggleTerm direction=horizontal<cr>', { desc = "Bottom Terminal" })
      vim.keymap.set('n', '<leader>tv', '<cmd>ToggleTerm direction=vertical size=40<cr>', { desc = "Side Terminal" })
    end,
  },

  -- Git State
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup()
    end,
  },

  -- Indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    config = function()
      require("ibl").setup({
        indent = { char = "│" },
        scope = {
          enabled = true,
          -- show_start/show_end default to true and underline the
          -- first/last line of whatever lexical scope the cursor is
          -- currently inside (recalculated as the cursor moves --
          -- that's why it seemed to "follow" the cursor). The colored
          -- guide itself is kept; just the underline is turned off.
          show_start = false,
          show_end = false,
        },
      })
    end,
  },

  -- Inline hex/rgb color preview
  {
    "norcalli/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup()
    end,
  },

  -- Hex file viewer/editor. Toggles between normal and hex-dump view
  -- (backed by xxd) rather than showing both simultaneously -- that
  -- trade-off is deliberate: since the hex dump is just ordinary,
  -- plain buffer text under the hood, editing it gets Neovim's normal
  -- undo/redo for free, and nothing writes to disk until an explicit
  -- :w, same as any other file. The only plugin found that does a
  -- true live simultaneous hex+ASCII view (hexview.nvim, used here
  -- previously) manages bytes with its own custom logic instead of
  -- going through normal buffer text editing, which is exactly why it
  -- has no undo at all -- not a gap that plugin could patch, an
  -- architectural trade-off against the same thing being fixed here.
  {
    "RaafatTurki/hex.nvim",
    config = function()
      require("hex").setup()
      vim.keymap.set('n', '<leader>h', function()
        if not vim.bo.binary then
          -- Hex editing depends on the buffer actually being loaded
          -- as binary. Otherwise Neovim applies normal text encoding/
          -- line-ending handling to the raw bytes first (NUL bytes
          -- included, which any real binary is full of) -- that
          -- misinterpretation is what produces "CONVERSION ERROR"
          -- rather than a clean hex dump, and it happens BEFORE xxd
          -- ever runs. Re-reading with ++bin loads the file correctly
          -- from scratch instead of operating on an already-misread
          -- buffer.
          --
          -- That reload is forced (!), which discards whatever's
          -- currently in the buffer without asking -- refuse to do it
          -- if there are unsaved changes rather than silently losing
          -- them. Only relevant on this first switch into hex mode:
          -- once vim.bo.binary is already true, no reload happens and
          -- this check doesn't apply.
          if vim.bo.modified then
            vim.notify("Buffer has unsaved changes -- save first (or :e! to discard) before opening hex view", vim.log.levels.WARN)
            return
          end
          vim.cmd('edit! ++bin %')
        end
        vim.cmd('HexToggle')
      end, { desc = "Toggle Hex View" })
    end,
  },

  -- Nicer notifications (replaces the default vim.notify popups)
  {
    "rcarriga/nvim-notify",
    config = function()
      require("notify").setup({
        background_colour = "#000000",
        timeout = 3000,
        -- Stack upward from the bottom instead of down from the top
        -- (nvim-notify anchors to the right by default either way),
        -- so notifications land bottom-right instead of top-right.
        top_down = false,
        -- Switched from "compact": that renderer has a documented
        -- history of text overflow/wrapping bugs, and is the prime
        -- suspect for the garbled/duplicated text seen in some
        -- NvimTree error notifications. Not confirmed as the actual
        -- cause, but worth trying alongside the position change.
      })
      vim.notify = require("notify")
    end,
  },

  -- Prettier vim.ui.input / vim.ui.select -- upgrades your existing
  -- rename prompt, conditional breakpoint prompt, and DAP path prompts
  -- to floating, styled dialogs instead of the command-line input.
  {
    "stevearc/dressing.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- LSP and Mason
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Enable native above-line virtual lines with custom formatting
      vim.diagnostic.config({
        underline = false, -- virtual_lines already shows the message; skip the extra underline
        virtual_text = false,
        virtual_lines = {
          format = function(diagnostic)
            local msg = diagnostic.message or ""
            msg = msg:gsub("^[a-z_][a-z0-9_%-]*:%s*", "")
            return msg
          end,
        },
      })

      -- NOTE: modern Neovim (0.11+) dedupes diagnostics internally, and
      -- the old vim.lsp.with()-based publishDiagnostics override is
      -- deprecated, so it's intentionally not used here.

      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = { "clangd", "gopls", "omnisharp", "ts_ls", "html", "cssls" },
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- LSP Keymaps (Organized under <leader>l), applied on attach via
      -- the LspAttach autocommand rather than a per-server on_attach
      -- callback passed through lspconfig[x].setup().
      local function on_attach(bufnr)
        -- Core goto commands (Standard Vim behavior, no leader required)
        --
        -- #include lines get special handling: clangd resolves
        -- textDocument/definition (and /declaration) on an #include
        -- directive to the target header regardless of which token on
        -- that line the cursor sits on, so both gd and gD below open
        -- it directly. If clangd hasn't attached/indexed yet, or the
        -- header isn't part of the compile database, we fall back to
        -- Vim's built-in "goto file under cursor" (gf), which still
        -- resolves a local #include "quoted.h" relative to the
        -- current file even with no LSP involved at all.
        local function is_include_line()
          return vim.api.nvim_get_current_line():match('^%s*#%s*include') ~= nil
        end

        -- Shared result handler for definition/declaration: jump
        -- straight there for a single match; fill the quickfix list
        -- and open it for multiple (e.g. a function declared once but
        -- defined across several translation units) instead of
        -- silently picking whichever one clangd listed first.
        local function on_list(t)
          if vim.tbl_isempty(t.items) then
            if is_include_line() then
              vim.cmd('normal! gf')
            end
            return
          end
          vim.fn.setqflist({}, ' ', t)
          if #t.items > 1 then
            vim.cmd('botright copen')
          else
            vim.cmd('cfirst')
          end
        end

        vim.keymap.set('n', 'gd', function()
          if is_include_line() then
            vim.lsp.buf.definition({ on_list = on_list })
          else
            -- Regular symbol: Telescope gives a fuzzy picker with
            -- preview when there's more than one candidate (e.g.
            -- overloads), and jumps straight there for a single one --
            -- nicer than the bare quickfix list for that common case.
            require('telescope.builtin').lsp_definitions({ reuse_win = true })
          end
        end, { buffer = bufnr, silent = true, desc = "Go to Definition" })

        vim.keymap.set('n', 'gD', function()
          -- No Telescope equivalent exists for declaration (only
          -- definition/references/implementation/type_definition are
          -- exposed), so this stays on vim.lsp.buf.declaration --
          -- just with the same on_list handling as gd above.
          vim.lsp.buf.declaration({ on_list = on_list })
        end, { buffer = bufnr, silent = true, desc = "Go to Declaration" })

        vim.keymap.set('n', 'gr', function()
          -- vim.lsp.buf.references() on its own just fills the
          -- quickfix list silently without opening it, so pressing gr
          -- looks like nothing happened. Telescope's picker actually
          -- shows the list with a preview, same as gd above.
          require('telescope.builtin').lsp_references({ reuse_win = true })
        end, { buffer = bufnr, silent = true, desc = "Find References" })

        vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, silent = true, desc = "Hover Info" })

        -- Safe Rename Function (Fixes double execution/prompt issues)
        local function safe_rename()
          local current_name = vim.fn.expand("<cword>")
          vim.ui.input({ prompt = "Rename: ", default = current_name }, function(new_name)
            if not new_name or new_name == "" or new_name == current_name then
              return
            end
            vim.lsp.buf.rename(new_name)
          end)
        end

        -- Leader commands (Grouped under l)
        vim.keymap.set('n', '<leader>lr', safe_rename, { buffer = bufnr, silent = true, desc = "Rename Symbol" })
        vim.keymap.set('n', '<leader>la', vim.lsp.buf.code_action, { buffer = bufnr, silent = true, desc = "Code Actions" })
        vim.keymap.set('n', '<leader>lf', function() vim.lsp.buf.format { async = true } end, { buffer = bufnr, silent = true, desc = "Format File" })
        vim.keymap.set('n', '<leader>li', '<cmd>LspInfo<CR>', { buffer = bufnr, silent = true, desc = "LSP Info" })
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(args)
          on_attach(args.buf)
        end,
      })

      -- Setup LSPs via the built-in vim.lsp.config()/vim.lsp.enable()
      -- API (replaces the deprecated require('lspconfig')[x].setup()
      -- framework). Default per-server settings still come from
      -- nvim-lspconfig, which only needs to be on the runtimepath.
      local servers = { "clangd", "gopls", "omnisharp", "ts_ls", "html", "cssls" }
      for _, lsp in ipairs(servers) do
        vim.lsp.config(lsp, {
          capabilities = capabilities,
        })
      end
      vim.lsp.enable(servers)
    end,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      -- Without this, LuaSnip never checks whether the cursor has
      -- actually left a snippet's text -- so pressing Tab later, even
      -- lines away, can jump straight back into an old, unfinished
      -- placeholder session (e.g. clangd's function-argument
      -- placeholders). region_check_events makes it watch cursor
      -- movement and automatically exit a snippet once you've moved
      -- outside its region, in both normal and insert mode.
      luasnip.setup({
        region_check_events = "CursorMoved,CursorMovedI",
      })

      cmp.setup({
        -- Ghost text: previews the currently-selected completion inline
        -- after the cursor, instead of only showing it in the popup menu.
        -- Combined with the cmp-path source below, this is what gives you
        -- inline "ghost" previews as you type a filesystem path (e.g.
        -- typing ./src/ will ghost-preview entries found in that
        -- directory) without needing a separate plugin for it.
        experimental = {
          ghost_text = true,
        },
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          -- Safely close the menu without reverting text state
          ['<Up>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.close() end
            fallback()
          end, { 'i', 's' }),
          ['<Down>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.close() end
            fallback()
          end, { 'i', 's' }),
          ['<Left>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.close() end
            fallback()
          end, { 'i', 's' }),
          ['<Right>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.close() end
            fallback()
          end, { 'i', 's' }),
          ['<Esc>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.close() end
            fallback()
          end, { 'i', 's' }),

          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              -- No completion menu open, but we're sitting in a snippet
              -- (e.g. clangd's function-argument placeholders after
              -- accepting a call like memcpy(...)) -- jump to the next
              -- tabstop/placeholder instead of inserting a literal tab.
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { 'i', 's' }),

          ['<CR>'] = cmp.mapping.confirm({ select = false }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          -- Lists and completes filesystem paths/directory contents as
          -- you type a path string (e.g. after typing "./" or "/home/").
          -- This is the source that feeds the ghost-text path preview.
          { name = "path" },
        }),
      })
    end,
  },

  -- Auto-pair brackets/quotes: (), {}, [], "", '' -- nvim-autopairs'
  -- own defaults. <> was tried here too but removed: it collided too
  -- much with < and > as comparison operators to be worth keeping.
  {
    "windwp/nvim-autopairs",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      local autopairs = require("nvim-autopairs")
      -- map_cr defaults to true, which makes nvim-autopairs install
      -- its OWN insert-mode <CR> mapping (for expanding bracket pairs
      -- onto their own indented line). That's set during plugin
      -- loading, which runs after init.lua's own top-level code --
      -- where the comment-continuation <CR> mapping lives -- so it
      -- was silently overwriting that mapping entirely regardless of
      -- what it did internally. Disabled here to free up <CR> for
      -- that mapping; the trade-off is losing autopairs' own
      -- brace-expands-on-Enter behavior, which was never explicitly
      -- asked for.
      autopairs.setup({ map_cr = false })

      -- Integrates with nvim-cmp so accepting a completion (e.g. a
      -- function call) doesn't end up with doubled-up parens.
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      require("cmp").event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },

  -- =========================================================
  -- DAP: In-editor C/C++ debugging (breakpoints, step, watch)
  -- Uses codelldb (installed via Mason) as the debug adapter.
  -- =========================================================
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "theHamsta/nvim-dap-virtual-text",
      "jay-babu/mason-nvim-dap.nvim",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      -- Auto-install codelldb through Mason and wire it into nvim-dap.
      -- NOTE: omitting `handlers` entirely (rather than passing {}) is
      -- what makes mason-nvim-dap run its DEFAULT handler, which is
      -- what actually registers a working dap.adapters.codelldb with
      -- correct dynamic ${port} allocation. Passing handlers = {}
      -- disables that default handler instead of using it.
      require("mason-nvim-dap").setup({
        ensure_installed = { "codelldb" },
        automatic_installation = true,
      })

      require("dapui").setup()
      require("nvim-dap-virtual-text").setup({
        commented = true,
      })

      -- Auto open/close the UI when a debug session starts/ends
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- <F5> and <F10> are each shared between an nvim-dap action
      -- (Continue, Step Over) and a bufferline buffer jump (buffer 5,
      -- last buffer) -- at rest they're buffer jumps; for the
      -- duration of a debug session they're handed over to DAP
      -- instead, so nothing fights over the same key. Note this means
      -- <F5> can no longer START a fresh session on its own (there's
      -- no session yet at that point, so it's still doing buffer-jump
      -- duty) -- use <leader>dc or <leader>db to start one, then <F5>
      -- takes over for continuing from there. Reusing the same
      -- listener points as the dapui open/close hooks above.
      dap.listeners.after.event_initialized["fkey_toggle"] = function()
        vim.keymap.set('n', '<F5>', dap.continue, { desc = "Debug: Continue" })
        vim.keymap.set('n', '<F10>', dap.step_over, { desc = "Debug: Step Over" })
      end
      local function restore_fkey_buffer_jumps()
        vim.keymap.set('n', '<F5>', function()
          require('bufferline').go_to(5, true)
        end, { desc = "Go to Buffer 5" })
        vim.keymap.set('n', '<F10>', function()
          require('bufferline').go_to(-1, true)
        end, { desc = "Go to Last Buffer" })
      end
      dap.listeners.before.event_terminated["fkey_toggle"] = restore_fkey_buffer_jumps
      dap.listeners.before.event_exited["fkey_toggle"] = restore_fkey_buffer_jumps

      -- C / C++ / Rust launch configs, all sharing the codelldb adapter
      dap.configurations.cpp = {
        {
          name = "Launch executable",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input(
              "Path to executable: ",
              vim.fn.getcwd() .. "/",
              "file"
            )
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          args = {},
        },
        {
          name = "Attach to process",
          type = "codelldb",
          request = "attach",
          pid = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.c = dap.configurations.cpp
      dap.configurations.rust = dap.configurations.cpp

      -- Breakpoint / stepping signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticInfo", linehl = "DapStoppedLine", numhl = "" })
      vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#0b3528" })

      -- Keymaps, grouped under <leader>d (shows in which-key)
      -- <F5> and <F10> intentionally NOT bound here -- both are set
      -- dynamically by the dap.listeners hooks above (Continue/Step
      -- Over only while a session is active; bufferline's buffer-5/
      -- last-buffer jumps otherwise).
      vim.keymap.set('n', '<F11>', dap.step_into, { desc = "Debug: Step Into" })
      vim.keymap.set('n', '<F12>', dap.step_out, { desc = "Debug: Step Out" })

      vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = "Toggle Breakpoint" })
      vim.keymap.set('n', '<leader>dB', function()
        dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
      end, { desc = "Conditional Breakpoint" })
      vim.keymap.set('n', '<leader>dc', dap.continue, { desc = "Continue" })
      vim.keymap.set('n', '<leader>do', dap.step_over, { desc = "Step Over" })
      vim.keymap.set('n', '<leader>di', dap.step_into, { desc = "Step Into" })
      vim.keymap.set('n', '<leader>dO', dap.step_out, { desc = "Step Out" })
      vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = "Open REPL" })
      vim.keymap.set('n', '<leader>dl', dap.run_last, { desc = "Run Last" })
      vim.keymap.set('n', '<leader>dt', dap.terminate, { desc = "Terminate Session" })
      vim.keymap.set('n', '<leader>du', dapui.toggle, { desc = "Toggle Debug UI" })
      vim.keymap.set('n', '<leader>dh', function()
        require("dap.ui.widgets").hover()
      end, { desc = "Hover Variable" })

      -- Load project-specific CMake-built target configs (defines
      -- Debug configs for build/tests/... and build/demo/... binaries).
      -- This also makes nvim-dap lazy-load the same file automatically
      -- when you start debugging from a CMakeLists.txt buffer.
      require("dap.configurations.cmake")
    end,
  },
}
EOF

# --- dap/configurations/cmake.lua ---
# Project-specific nvim-dap launch configs for CMake-built binaries.
cat << 'EOF' > "$NVIM_DIR/lua/dap/configurations/cmake.lua"
-- dap.configurations.cmake
--
-- nvim-dap debug configurations for this project's CMake-built
-- binaries: tests/test_dynamic_library and demo/example_host.
--
-- Load from your Neovim config, e.g.:
--
--   dofile(vim.fn.getcwd() .. '/dap.configurations.cmake')
--
-- (or place it under a Lua module path as dap/configurations/cmake.lua
-- and `require('dap.configurations.cmake')` instead).
--
-- Assumes:
--  * nvim-dap is installed.
--  * a `codelldb` adapter is available on PATH (e.g. installed via
--    mason.nvim) -- this file only registers dap.adapters.codelldb if
--    nothing has registered one already, so it won't clobber your own
--    adapter config.
--  * the project has been built with scripts/build.sh, so the binaries
--    referenced below exist under build/.
--
-- Debugging needs actual debug symbols: build with
--   ./scripts/build.sh --debug
-- Release builds will run under the debugger but won't have useful
-- source-line info.
local dap = require('dap')
-- ---------------------------------------------------------------------
-- Locate the project root by walking up from the current working
-- directory to find CMakeLists.txt. Falls back to cwd if not found,
-- which covers the common case of launching nvim from the project
-- root directly.
-- ---------------------------------------------------------------------
local function project_root()
  local found = vim.fs.find('CMakeLists.txt', {
    upward = true,
    path = vim.fn.getcwd(),
  })[1]
  if found then
    return vim.fs.dirname(found)
  end
  return vim.fn.getcwd()
end
local function build_dir()
  return project_root() .. '/build'
end
-- ---------------------------------------------------------------------
-- codelldb adapter (skipped if one is already registered elsewhere,
-- e.g. by mason-nvim-dap)
--
-- NOTE: this must be a plain table, not a function. nvim-dap only
-- performs its automatic ${port} -> real free port substitution (and
-- spawns the executable itself, waiting for it to be ready) for
-- table-style server adapters. A function-style adapter is expected
-- to resolve the port itself; leaving the literal string "${port}"
-- in a function adapter's return value causes nvim-dap to try to
-- connect to a host literally named "${port}", which fails with
-- ECONNREFUSED.
-- ---------------------------------------------------------------------
if not dap.adapters.codelldb then
  dap.adapters.codelldb = {
    type = 'server',
    port = '${port}',
    executable = {
      command = vim.fn.exepath('codelldb'),
      args = { '--port', '${port}' },
    },
  }
end
-- ---------------------------------------------------------------------
-- Platform-appropriate shared library naming, matching
-- dynlib::DynamicLibrary::MakeLibraryFileName().
-- ---------------------------------------------------------------------
local function shared_lib_prefix()
  return vim.loop.os_uname().sysname == 'Windows_NT' and '' or 'lib'
end
local function shared_lib_ext()
  local sysname = vim.loop.os_uname().sysname
  if sysname == 'Windows_NT' then
    return '.dll'
  elseif sysname == 'Darwin' then
    return '.dylib'
  end
  return '.so'
end
local function fixture_lib_path()
  return build_dir() .. '/tests/' .. shared_lib_prefix() .. 'dynlib_test_fixture' .. shared_lib_ext()
end
local function demo_plugin_path()
  return build_dir() .. '/demo/' .. shared_lib_prefix() .. 'example_plugin' .. shared_lib_ext()
end
-- ---------------------------------------------------------------------
-- Debug configurations
-- ---------------------------------------------------------------------
local configurations = {
  {
    name = 'Debug test_dynamic_library (tests)',
    type = 'codelldb',
    request = 'launch',
    program = function()
      return build_dir() .. '/tests/test_dynamic_library'
    end,
    args = function()
      return { fixture_lib_path() }
    end,
    cwd = function()
      return build_dir() .. '/tests'
    end,
    stopOnEntry = false,
  },
  {
    name = 'Debug example_host (demo)',
    type = 'codelldb',
    request = 'launch',
    program = function()
      return build_dir() .. '/demo/example_host'
    end,
    args = function()
      return { demo_plugin_path() }
    end,
    cwd = function()
      return build_dir() .. '/demo'
    end,
    stopOnEntry = false,
  },
  {
    name = 'Debug example_host (prompt for plugin path)',
    type = 'codelldb',
    request = 'launch',
    program = function()
      return build_dir() .. '/demo/example_host'
    end,
    args = function()
      local path = vim.fn.input('Plugin path: ', demo_plugin_path(), 'file')
      return { path }
    end,
    cwd = function()
      return build_dir() .. '/demo'
    end,
    stopOnEntry = false,
  },
}
dap.configurations.cpp = vim.list_extend(dap.configurations.cpp or {}, configurations)
dap.configurations.c = vim.list_extend(dap.configurations.c or {}, configurations)
return configurations
EOF

# --- ~/.clang-format and ~/.clang-tidy ---
# Personal fallback style, implementing a specific C/C++ coding style
# guide (naming conventions, brace style, include ordering, etc. --
# see the comments in each file below for exactly which guide section
# each setting maps to). Both tools walk UP from the file being
# checked/formatted looking for their respective config file; $HOME
# sits above every project you'll open, so these become your default
# for any project that doesn't ship its own .clang-format/.clang-tidy
# (a project's own file, being closer to the file, always takes
# precedence over these).
#
# NOTE: this REPLACES the earlier simpler .clang-format (LLVM +
# Attach/K&R braces) with a full style-guide implementation -- brace
# style is intentionally flipped back to Allman here as part of that,
# since this is a deliberate, complete style guide rather than the
# earlier ad-hoc preference.
#
# <leader>lf (LSP format) only consumes .clang-format -- clangd's
# formatting is pure clang-format, unrelated to clang-tidy. The
# .clang-tidy file is picked up separately and automatically by
# clangd for live diagnostics (clang-tidy integration is on by
# default in clangd), not by <leader>lf itself.
#
# Written unconditionally (not "if missing") every run, same as the
# rest of this config -- so a stray pre-existing file from some other
# tool can't silently block these from taking effect.
cat << 'EOF' > "$HOME/.clang-format"
# .clang-format
# Enforces the formatting rules from the C/C++ Coding Style Guide (Part I: C++ Style).
# Applies equally to Part II C API files per §15 (Indentation and Braces) — same
# tabs/Allman/line-length rules, just different naming (naming can't be enforced
# by clang-format; see .clang-tidy and TOOLING.md).
Language: Cpp
Standard: Latest
# --- Indentation (style guide §2) ---
UseTab: Always
TabWidth: 4
IndentWidth: 4
ContinuationIndentWidth: 4
IndentCaseLabels: true
IndentPPDirectives: None
IndentExternBlock: Indent
# Access specifiers (public:/private:) sit unindented, flush with the class
# keyword — only members are indented one level, matching every example in §1/§6.
AccessModifierOffset: -4
# Namespace bodies are indented like any other block (style guide §Namespaces).
NamespaceIndentation: All
# --- Braces: Allman style everywhere (style guide §3) ---
BreakBeforeBraces: Allman
Cpp11BracedListStyle: true
# InlineOnly (not Empty or None): out-of-class function definitions always
# get full Allman expansion regardless of length, same as before -- this
# only additionally allows a function *defined inside a class body* to
# stay a compact one-liner if it's short enough to fit. That's specifically
# for the trivial-one-liner exception to "avoid inline member definitions"
# in Class Member Organization (style guide §6) -- a plain getter like
# `int getValue() const { return m_value; }` stays inline-and-compact;
# anything defined out-of-class still always gets the full brace expansion.
AllowShortFunctionsOnASingleLine: InlineOnly
AllowShortIfStatementsOnASingleLine: Never
AllowShortLoopsOnASingleLine: false
AllowShortBlocksOnASingleLine: Never
AllowShortEnumsOnASingleLine: false
AllowShortCaseLabelsOnASingleLine: false
# No trailing "// namespace X" / "// class X" comments on closing braces
# (style guide §Namespaces / §6).
FixNamespaceComments: false
# --- Pointers and references attach to the type (style guide §4) ---
PointerAlignment: Left
ReferenceAlignment: Pointer
DerivePointerAlignment: false
# --- Line length (style guide §8) ---
ColumnLimit: 100
# --- Spacing (style guide §5) ---
SpaceBeforeParens: ControlStatements
SpacesInParentheses: false
SpacesInSquareBrackets: false
SpaceAfterCStyleCast: false
SpaceBeforeAssignmentOperators: true
SpacesInAngles: false
# --- Include ordering (style guide §7: main header, C headers, C++ std,
# third-party, project headers) ---
SortIncludes: true
SortUsingDeclarations: true
IncludeBlocks: Regroup
IncludeIsMainRegex: '(Test)?$'
IncludeCategories:
  # 1. Corresponding header is auto-detected and always sorted first.
  # 2. C system headers wrapped for C++ (<cstdio>, <cstdint>, ...).
  - Regex: '^<(cassert|cctype|cerrno|cfenv|cfloat|cinttypes|climits|clocale|cmath|csetjmp|csignal|cstdarg|cstddef|cstdint|cstdio|cstdlib|cstring|ctime|cuchar|cwchar|cwctype)>$'
    Priority: 1
    CaseSensitive: true
  # 3. C++ standard library headers (no dot, no slash — <vector>, <memory>, ...).
  - Regex: '^<[a-z_]+>$'
    Priority: 2
    CaseSensitive: true
  # 4. Third-party / external library headers (<fmt/format.h>, <boost/...>, ...).
  - Regex: '^<.*>$'
    Priority: 3
    CaseSensitive: true
  # 5. Project headers, quoted ("NetworkManager.hpp", ...).
  - Regex: '^".*"$'
    Priority: 4
    CaseSensitive: true
# --- Misc ---
AlignTrailingComments: true
AlignConsecutiveAssignments: false
AlignConsecutiveDeclarations: false
# Parameters/arguments: never one-per-line (style guide §8). When a
# signature/call doesn't fit on one line, keep everything together on a
# single continuation line if it fits there (AllowAll...OnNextLine), and
# fall back to packing multiple per line (BinPack...) rather than ever
# breaking to one per line. This can't force a genuinely long signature
# to fit within ColumnLimit without wrapping at all -- doing that would
# require ColumnLimit: 0 project-wide, which would also stop comments and
# ordinary expressions from ever wrapping. See §8 for the full rule.
#
# COMPATIBILITY NOTE: clang-format 20 changed BinPackParameters (and the
# equivalent for call arguments) from a boolean to an enum, and later
# versions deprecated it again in favor of a nested PackParameters/
# PackArguments option. The boolean form below is correct for clang-format
# through 19 (still the most common version in practice, e.g. Ubuntu
# 24.04 LTS ships 18). On clang-format 20 or newer, replace `true` with
# `BinPack` on both lines if you find these are being silently ignored.
BinPackArguments: true
BinPackParameters: true
AllowAllArgumentsOnNextLine: true
AllowAllParametersOfDeclarationOnNextLine: true
BreakConstructorInitializers: BeforeColon
ConstructorInitializerIndentWidth: 4
PenaltyReturnTypeOnItsOwnLine: 1000
EOF

cat << 'EOF' > "$HOME/.clang-tidy"
# .clang-tidy
# Enforces naming conventions (style guide §1) and a subset of the Language
# Feature Do's and Don'ts (style guide §10) for C++ code. Place at the repo
# root for Part I (C++) files. For Part II (C API) files, use the
# directory-scoped override in c-api/.clang-tidy instead — clang-tidy picks
# the closest .clang-tidy file up the directory tree, so nesting one there
# gives that subtree different naming rules without affecting the rest of
# the project. See TOOLING.md for what this file can't check.
#
# readability-redundant-inline-specifier is a narrow, complementary aid for
# the "avoid inline member definitions" rule in §6 (Class Member
# Organization): it only catches an explicit `inline` keyword that's
# already redundant (e.g. on a function defined in the class body, which
# is implicitly inline regardless). It does not catch — and nothing in
# this file catches — an inline definition that omits the keyword
# entirely, which is the actual, common case the style guide rule is
# about; that one stays a code-review judgment call. See TOOLING.md.
Checks: >
  -*,
  readability-identifier-naming,
  readability-redundant-inline-specifier,
  modernize-use-nullptr,
  modernize-use-override,
  modernize-use-equals-default,
  modernize-use-equals-delete,
  modernize-loop-convert,
  modernize-concat-nested-namespaces,
  modernize-use-default-member-init,
  modernize-avoid-c-arrays,
  modernize-use-nodiscard,
  cppcoreguidelines-special-member-functions,
  cppcoreguidelines-owning-memory,
  cppcoreguidelines-no-malloc,
  cppcoreguidelines-pro-type-member-init,
  cppcoreguidelines-pro-type-cstyle-cast,
  cppcoreguidelines-macro-usage,
  performance-unnecessary-value-param,
  performance-unnecessary-copy-initialization,
  bugprone-exception-escape,
  bugprone-use-after-move
WarningsAsErrors: ''
HeaderFilterRegex: '.*\.hpp$'
FormatStyle: file
CheckOptions:
  # --- Naming Conventions — style guide §1 ---
  - key: readability-identifier-naming.NamespaceCase
    value: lower_case
  - key: readability-identifier-naming.ClassCase
    value: CamelCase
  - key: readability-identifier-naming.StructCase
    value: CamelCase
  - key: readability-identifier-naming.EnumCase
    value: CamelCase
  - key: readability-identifier-naming.EnumConstantCase
    value: CamelCase
  - key: readability-identifier-naming.FunctionCase
    value: camelBack
  - key: readability-identifier-naming.MethodCase
    value: camelBack
  - key: readability-identifier-naming.VariableCase
    value: camelBack
  - key: readability-identifier-naming.LocalVariableCase
    value: camelBack
  - key: readability-identifier-naming.ParameterCase
    value: camelBack
  # A plain local `const` (not `static`, not `constexpr`) stays under the
  # Local Variables rule (camelCase) per the style guide's own note that
  # only *global/static* const/constexpr values are "constants" for this
  # rule's purposes -- without this, it silently inherits the general
  # ConstantCase (PascalCase) fallback below instead, which would flag
  # totally ordinary code like `const std::string name = ...;` inside a
  # function. StaticConstantCase/GlobalConstantCase/ConstexprVariableCase
  # below are unaffected and still require PascalCase, matching the guide.
  - key: readability-identifier-naming.LocalConstantCase
    value: camelBack
  # Private/protected member variables: camelCase with an m_ prefix.
  - key: readability-identifier-naming.PrivateMemberCase
    value: camelBack
  - key: readability-identifier-naming.PrivateMemberPrefix
    value: m_
  - key: readability-identifier-naming.ProtectedMemberCase
    value: camelBack
  - key: readability-identifier-naming.ProtectedMemberPrefix
    value: m_
  # Public members (e.g. plain data structs) — camelCase, no prefix.
  - key: readability-identifier-naming.PublicMemberCase
    value: camelBack
  # Static class data members — camelCase with an s_ prefix (distinct from
  # instance members above). "ClassMember" is clang-tidy's category for
  # static (non-const) data members specifically.
  - key: readability-identifier-naming.ClassMemberCase
    value: camelBack
  - key: readability-identifier-naming.ClassMemberPrefix
    value: s_
  # Global (namespace/file-scope, mutable) variables — camelCase with a g_
  # prefix, to flag genuinely global mutable state at every use site.
  - key: readability-identifier-naming.GlobalVariableCase
    value: camelBack
  - key: readability-identifier-naming.GlobalVariablePrefix
    value: g_
  # Static variables — function-local `static` or file-scope `static` —
  # camelCase with an s_ prefix, for the same reason as globals above.
  - key: readability-identifier-naming.StaticVariableCase
    value: camelBack
  - key: readability-identifier-naming.StaticVariablePrefix
    value: s_
  # Constants and enum values — PascalCase (style guide §1 table).
  - key: readability-identifier-naming.ConstantCase
    value: CamelCase
  - key: readability-identifier-naming.GlobalConstantCase
    value: CamelCase
  - key: readability-identifier-naming.StaticConstantCase
    value: CamelCase
  - key: readability-identifier-naming.ClassConstantCase
    value: CamelCase
  - key: readability-identifier-naming.ConstexprVariableCase
    value: CamelCase
  # Template parameters — PascalCase (e.g. ValueType).
  - key: readability-identifier-naming.TemplateParameterCase
    value: CamelCase
  - key: readability-identifier-naming.TypeTemplateParameterCase
    value: CamelCase
  # Type aliases / typedefs — PascalCase, matching class naming.
  - key: readability-identifier-naming.TypeAliasCase
    value: CamelCase
  - key: readability-identifier-naming.TypedefCase
    value: CamelCase
  # Macros — ALL_CAPS_SNAKE_CASE (the one deliberate exception in §1).
  - key: readability-identifier-naming.MacroDefinitionCase
    value: UPPER_CASE
  # --- cppcoreguidelines-owning-memory — style guide §10, Memory and Ownership ---
  # Flags raw new/delete and legacy C allocators used for ownership instead of
  # std::unique_ptr / std::shared_ptr.
  - key: cppcoreguidelines-owning-memory.LegacyResourceProducers
    value: 'malloc;calloc;realloc;strdup;strndup'
  - key: cppcoreguidelines-owning-memory.LegacyResourceConsumers
    value: 'free;realloc'
  # --- cppcoreguidelines-macro-usage — style guide §10, prefer constexpr over #define ---
  # Allow include-guard-style and project-prefixed macros; flag everything else
  # that could instead be a constexpr constant.
  - key: cppcoreguidelines-macro-usage.AllowedRegexp
    value: '^[A-Z0-9_]+_H(PP)?$'
  - key: cppcoreguidelines-macro-usage.CheckCapsOnly
    value: false
EOF
echo "Wrote ~/.clang-format and ~/.clang-tidy (Allman braces, real tabs)."

echo "========================================="
echo " Setup Complete!"
echo " Run 'nvim'. p and P are restored, use <leader>p to force inline paste!"
echo " Debugger: <leader>db to set a breakpoint, F5 / <leader>dc to start/continue,"
echo " <leader>du to toggle the debug UI. First debug session will auto-install codelldb via Mason."
echo " Project-specific CMake debug targets loaded from ~/.config/nvim/lua/dap/configurations/cmake.lua"
echo "========================================="
