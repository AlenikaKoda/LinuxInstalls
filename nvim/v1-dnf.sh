#!/bin/bash

echo

echo "========================================="
echo " Starting Neovim Setup for Fedora"
echo "========================================="

# 1. Install System Dependencies via DNF
echo "[1/4] Installing system dependencies and LSPs..."
sudo dnf install -y neovim git curl wget gcc gcc-c++ make cmake \
    nodejs npm python3-pip ripgrep fd-find \
    golang clang-tools-extra dotnet-sdk-8.0 unzip fontconfig \
    lldb gdb fish

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

# 3. Backup existing Neovim config
echo "[3/4] Backing up existing Neovim configuration..."
if [ -d "$HOME/.config/nvim" ]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Existing config backed up to ~/.config/nvim.bak.*"
fi
if [ -d "$HOME/.local/share/nvim" ]; then
    mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.bak.$(date +%Y%m%d_%H%M%S)"
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
          -- specifically for C/C++ (inconsistent brace placement,
          -- phantom extra indent on nested blocks) while being fine
          -- for the other languages here. Disabling it just for c/cpp
          -- falls back to Vim's built-in 'cindent', which Neovim
          -- already auto-enables for these filetypes via its standard
          -- ftplugin and is much more predictable for brace-heavy code.
          disable = { "c", "cpp" },
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
        languages = {
          c = { template = { annotation_convention = "doxygen" } },
          cpp = { template = { annotation_convention = "doxygen" } },
        },
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

      -- Alt+,/. : reorder the current buffer left/right in the
      -- bufferline (persists for the session as long as
      -- sessionoptions includes "globals", which lazy.nvim's default
      -- vimrc already does).
      vim.keymap.set('n', '<A-,>', '<cmd>BufferLineMovePrev<cr>', { desc = "Move Buffer Left" })
      vim.keymap.set('n', '<A-.>', '<cmd>BufferLineMoveNext<cr>', { desc = "Move Buffer Right" })

      -- Pin the current buffer -- pinned buffers stay pinned to the
      -- start of the bufferline regardless of sorting/reordering.
      --
      -- Pin state is ALSO recorded in a plain buffer-local variable
      -- here, set at the same time as the real toggle. bufferline's
      -- internal pin/group state isn't reliably exposed as a stable
      -- public API across versions -- require('bufferline').group_action
      -- (used previously) doesn't exist on the version actually
      -- installed here, hence the E5108 error. Tracking it ourselves
      -- means <leader>bx below never has to ask bufferline which
      -- buffers are pinned at all.
      --
      -- redrawtabline is a best-effort nudge for a separate, known
      -- bufferline rough edge: after a buffer's position changes (e.g.
      -- pinning moves it to the front), the ordinal NUMBER LABEL can
      -- briefly lag behind and show the old numbering until the next
      -- redraw. This doesn't affect the earlier Alt+number jump
      -- itself -- it still goes to the correct buffer -- only what's
      -- printed on the tab. If the label still looks wrong after this,
      -- or Alt+number ever jumps to the WRONG buffer (not just shows
      -- the wrong label), let me know and we'll dig further.
      vim.keymap.set('n', '<leader>bp', function()
        vim.cmd('BufferLineTogglePin')
        vim.cmd('redrawtabline')
        local buf = vim.api.nvim_get_current_buf()
        vim.b[buf].pinned = not vim.b[buf].pinned
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

  -- Nicer notifications (replaces the default vim.notify popups)
  {
    "rcarriga/nvim-notify",
    config = function()
      require("notify").setup({
        background_colour = "#000000",
        timeout = 3000,
        render = "compact",
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
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, { buffer = bufnr, silent = true, desc = "Find References" })
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

  -- Doxygen comment generation. There's no such thing as a real
  -- "Doxygen language server" -- Doxygen comments are just C/C++
  -- comments with special syntax, and clangd already parses and
  -- renders them in hover docs with zero config. What this adds is
  -- generating the comment SKELETON itself: put the cursor on/inside a
  -- function and generate an empty @brief/@param/@return block for it.
  {
    "danymat/neogen",
    dependencies = "nvim-treesitter/nvim-treesitter",
    config = function()
      require("neogen").setup({
        -- cpp/c's default annotation_convention is already
        -- "doxygen_cpp", so nothing to override there.
        snippet_engine = "luasnip", -- inserted fields become LuaSnip
        -- tabstops, so <Tab>/<S-Tab> (already wired up above for
        -- cmp/LuaSnip) cycles through @brief, each @param, and @return.
      })
      vim.keymap.set('n', '<leader>ld', function()
        require("neogen").generate()
      end, { desc = "Generate Doc Comment (Doxygen)" })
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
      vim.keymap.set('n', '<F5>', dap.continue, { desc = "Debug: Continue" })
      vim.keymap.set('n', '<F10>', dap.step_over, { desc = "Debug: Step Over" })
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

# --- ~/.clang-format ---
# Personal fallback clang-format style. clang-format walks UP from the
# file being formatted looking for a .clang-format file; $HOME sits
# above every project you'll open, so this becomes your default style
# for any project that doesn't ship its own .clang-format (a project's
# own file, being closer to the file, always takes precedence over
# this one). BreakBeforeBraces: Attach keeps braces on the same line
# as the declaration (K&R), instead of Allman-style braces on their
# own line.
#
# NOTE: written unconditionally (not "if missing") every run, same as
# the rest of this config -- an earlier version only wrote this if the
# file didn't already exist, which meant a stray pre-existing
# ~/.clang-format (from some other tool, or leftover from before this
# script managed it) would silently block the fix forever.
cat << 'EOF' > "$HOME/.clang-format"
BasedOnStyle: LLVM
BreakBeforeBraces: Attach
IndentWidth: 4
ColumnLimit: 100
EOF
echo "Wrote ~/.clang-format (Attach braces)."

echo "========================================="
echo " Setup Complete!"
echo " Run 'nvim'. p and P are restored, use <leader>p to force inline paste!"
echo " Debugger: <leader>db to set a breakpoint, F5 / <leader>dc to start/continue,"
echo " <leader>du to toggle the debug UI. First debug session will auto-install codelldb via Mason."
echo " Project-specific CMake debug targets loaded from ~/.config/nvim/lua/dap/configurations/cmake.lua"
echo "========================================="
