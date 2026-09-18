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

-- Neovide (desktop GUI) specific settings. vim.g.neovide is only set
-- (truthy) when Neovide itself launches this config as its backend --
-- plain terminal Neovim never defines it, so everything in this block
-- is a no-op there. Terminal Neovim gets its cursor animation from
-- smear-cursor.nvim instead (see plugins/init.lua): a terminal has no
-- equivalent native capability to hook into, which is exactly the gap
-- that plugin fills.
if vim.g.neovide then
  vim.o.guifont = "JetBrainsMono Nerd Font:h13"

  -- Cursor trail: Neovide renders this itself (GPU-accelerated),
  -- which is why this lives in its own branch instead of always
  -- loading smear-cursor.nvim -- running both would be two different
  -- animation systems fighting over the same cursor. trail_size is a
  -- taste knob (0-1); turn it down if it feels like too much.
  vim.g.neovide_cursor_vfx_mode = "railgun"
  vim.g.neovide_cursor_trail_size = 0.5
  vim.g.neovide_cursor_animate_in_insert_mode = true

  -- Neovide has no background-image setting -- two attempts to add
  -- one (neovide/neovide#2419, #3067) were both closed as abandoned/
  -- stalled, most recently in October 2025; the feature request itself
  -- (neovide/neovide#342) is still open if you want to track it.
  -- vim.g.neovide_opacity below is the closest thing that actually
  -- exists: it makes the window itself translucent, so on a
  -- compositing window manager (Hyprland included), whatever sits
  -- behind the window -- your desktop wallpaper, if Neovide isn't
  -- covering the whole screen, or another window -- blends through.
  -- It's not the same as a picture rendered inside the editor, but if
  -- your wallpaper already is that Arch logo, this is what gets you
  -- there. 1.0 = fully opaque (no effect); lower it to taste.
  vim.g.neovide_opacity = 0.9
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

-- Toggle comment on the current line / a visual selection.
--
-- Neovim 0.10+ already ships this natively on gcc (line) and gc (a
-- motion in normal mode, or the selection in visual mode) -- both
-- keep working exactly as before, untouched. This just adds
-- <leader>c/ as a second, which-key-discoverable entry point in the
-- existing "Comments" group, aliased onto those same native mappings
-- (remap = true so the fed keys re-trigger gcc/gc rather than this
-- reimplementing comment-toggling itself): same single keystroke
-- comments or uncomments, since gc/gcc already toggle based on the
-- current state.
vim.keymap.set('n', '<leader>c/', 'gcc', { remap = true, desc = "Toggle Comment (Line)" })
vim.keymap.set('x', '<leader>c/', 'gc', { remap = true, desc = "Toggle Comment (Selection)" })

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

-- Rule-of-five boilerplate for C++ (Namespaced under <leader>o, "OOP")
--
-- <leader>oc / <leader>om insert the copy or move constructor +
-- assignment operator pair, defaulted, for whichever class/struct
-- the cursor is currently inside -- found by walking up the
-- Treesitter tree rather than requiring the cursor to sit on the
-- class's own name line. Nested classes resolve to the innermost
-- one. `= default` covers the overwhelming majority of real
-- rule-of-five cases; delete it and write a body for the rare one
-- that needs custom logic.
local function enclosing_class_name()
  local ok, node = pcall(vim.treesitter.get_node)
  if not ok then
    return nil
  end
  while node do
    local t = node:type()
    if t == "class_specifier" or t == "struct_specifier" then
      local name_node = node:field("name")[1]
      return name_node and vim.treesitter.get_node_text(name_node, 0) or nil
    end
    node = node:parent()
  end
  return nil
end

local function insert_special_members(kind)
  local name = enclosing_class_name()
  if not name then
    vim.notify("No enclosing class/struct found here", vim.log.levels.WARN)
    return
  end
  local lines = kind == "copy" and {
    name .. "(const " .. name .. "&) = default;",
    name .. "& operator=(const " .. name .. "&) = default;",
  } or {
    name .. "(" .. name .. "&&) noexcept = default;",
    name .. "& operator=(" .. name .. "&&) noexcept = default;",
  }
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
  -- Reindent the inserted lines to match the surrounding brace depth
  -- rather than landing at column 0.
  vim.cmd(string.format("%d,%dnormal! ==", row + 1, row + #lines))
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "cpp",
  callback = function(args)
    vim.keymap.set("n", "<leader>oc", function() insert_special_members("copy") end,
      { buffer = args.buf, desc = "Insert Copy Ctor + Assignment" })
    vim.keymap.set("n", "<leader>om", function() insert_special_members("move") end,
      { buffer = args.buf, desc = "Insert Move Ctor + Assignment" })
  end,
})

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
