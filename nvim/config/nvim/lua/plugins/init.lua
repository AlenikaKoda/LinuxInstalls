return {
  -- REALLY Dark Theme (near-black koda)
  --
  -- Terminal Neovim and Neovide (the desktop GUI app) render the same
  -- highlight groups, so the theme itself needs nothing
  -- frontend-specific -- it's only the cursor *animation* that splits
  -- in two below, since a terminal and a GPU-rendered GUI window have
  -- different ways of drawing one.
  {
    "oskarnurm/koda.nvim",
    priority = 1000,
    config = function()
      require("koda").setup({
        -- Terminal only (see the "not Neovide" comment on the setting
        -- above): clears highlight-group backgrounds to NONE so
        -- whatever the *terminal emulator* draws behind Neovim shows
        -- through the gaps -- including a background image, if the
        -- terminal supports one (e.g. kitty's own `background_image`
        -- setting in kitty.conf, which is a terminal-level feature
        -- this config has no reach into). Without that configured on
        -- the terminal side, this just shows the terminal's normal
        -- background color instead, which is a harmless no-op look.
        -- Neovide doesn't use this option at all -- see
        -- vim.g.neovide_opacity in init.lua for its equivalent.
        transparent = not vim.g.neovide,
        colors = {
          -- koda's own "dark" variant defaults to #101010 -- nudged a
          -- touch further down to match the old pure-black background.
          bg = "#090909",
          line = "#1a1a1a",
        },
        on_highlights = function(hl, c)
          -- koda has no dedicated "hint" color; c.cyan is the closest
          -- hue match to the dark-teal hint background below.
          hl.DiagnosticVirtualTextError = { bg = "#351010", fg = c.danger }
          hl.DiagnosticVirtualTextWarn  = { bg = "#35280b", fg = c.warning }
          hl.DiagnosticVirtualTextInfo  = { bg = "#0b2035", fg = c.info }
          hl.DiagnosticVirtualTextHint  = { bg = "#0b3528", fg = c.cyan }

          hl.DiagnosticVirtualLinesError = { bg = "#351010", fg = c.danger }
          hl.DiagnosticVirtualLinesWarn  = { bg = "#35280b", fg = c.warning }
          hl.DiagnosticVirtualLinesInfo  = { bg = "#0b2035", fg = c.info }
          hl.DiagnosticVirtualLinesHint  = { bg = "#0b3528", fg = c.cyan }
        end,
      })
      vim.cmd.colorscheme("koda-dark")
    end,
  },

  -- Animated "smear" cursor trail, terminal only -- Neovide has its
  -- own native, GPU-accelerated cursor VFX (see the `if vim.g.neovide`
  -- block in init.lua), and running both at once would just be two
  -- animation systems fighting over the same cursor. `cond` here means
  -- this plugin doesn't even load under Neovide. Tuning below is
  -- upstream's own suggested starting point.
  {
    "sphamba/smear-cursor.nvim",
    cond = not vim.g.neovide,
    config = function()
      require("smear_cursor").setup({
        cursor_color = "#ffffff",
        never_draw_over_target = true,
        smear_insert_mode = false,
        min_vertical_distance_smear = 2,
        min_horizontal_distance_smear = 2,
        time_interval = 17, -- ms
        stiffness = 0.9,
        trailing_stiffness = 0.4,
        damping = 0.99, -- stops bouncing
      })
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
        { "<leader>o", group = "OOP" },
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
          -- "auto" derives lualine's colors from the active colorscheme's
          -- own highlight groups -- koda doesn't ship a hand-built lualine
          -- theme the way some more established colorschemes do, so this
          -- is what keeps the statusline actually matching it instead of
          -- falling back to lualine's generic default palette.
          theme = "auto",
          -- Powerline private-use-area glyphs (E0B0-E0B3). This needs
          -- the terminal's font actually set to the PATCHED family
          -- (e.g. "JetBrainsMono Nerd Font" / "CaskaydiaCove Nerd
          -- Font", not plain "JetBrains Mono"/"Cascadia Code") -- if
          -- these render as boxes/question marks, that's the fix.
          -- The thin variants (E0B1/E0B3) are used between components
          -- within a section so they pick up each component's colors
          -- instead of a fixed one.
          -- Powerline glyphs U+E0B0-U+E0B3, written as raw UTF-8 byte
          -- escapes (not literal characters) so they can't get
          -- silently stripped by an editor/tool that mishandles
          -- Private Use Area codepoints.
          component_separators = { left = "\238\130\177", right = "\238\130\179" },
          section_separators = { left = "\238\130\176", right = "\238\130\178" },
          globalstatus = true,
        },
        sections = {
          lualine_a = {
            "mode",
            -- Only appears while recording a macro -- `cond` hides
            -- the component (and its separator) entirely the rest of
            -- the time, so it doesn't sit there empty.
            {
              function()
                return "\226\151\143 REC @" .. vim.fn.reg_recording()
              end,
              cond = function()
                return vim.fn.reg_recording() ~= ""
              end,
              color = { fg = "#e0af68", gui = "bold" },
            },
          },
          lualine_b = {
            -- Icon is baked into lualine's own "branch" component --
            -- nothing authored here, so no glyph-encoding risk.
            { "branch" },
            -- Moved in next to branch (was in lualine_x) so all the
            -- git state reads as one cluster instead of being split
            -- across opposite ends of the line.
            { "diff" },
          },
          lualine_c = {
            -- separator = "" fuses this to the filename that follows
            -- instead of leaving the icon boxed off by its own arrow
            -- on both sides.
            { "filetype", icon_only = true, padding = { left = 1, right = 0 }, separator = "" },
            {
              "filename",
              path = 0,
              symbols = { modified = " \226\151\143", readonly = " [RO]", unnamed = "[No Name]" },
            },
          },
          lualine_x = {
            "searchcount",
            "diagnostics",
            -- Attached LSP client name(s) -- hidden via `cond` when
            -- nothing's attached to the buffer.
            {
              function()
                local names = {}
                for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
                  table.insert(names, client.name)
                end
                return "\239\128\147 " .. table.concat(names, ", ")
              end,
              cond = function()
                return #vim.lsp.get_clients({ bufnr = 0 }) > 0
              end,
            },
            -- Word count, only for prose filetypes -- noise anywhere
            -- else, so it's gated the same way.
            {
              function()
                return "\194\182 " .. vim.fn.wordcount().words
              end,
              cond = function()
                local ft = vim.bo.filetype
                return ft == "markdown" or ft == "text" or ft == "gitcommit" or ft == "tex"
              end,
            },
          },
          lualine_y = {
            "progress",
            "location",
            -- Encoding/line-ending: only shown when they DIFFER from
            -- Neovim's own defaults (utf-8, unix) -- surfaces the
            -- unusual case instead of confirming the boring default
            -- on every single file.
            {
              function()
                local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
                local parts = {}
                if enc ~= "utf-8" then
                  table.insert(parts, enc)
                end
                if vim.bo.fileformat ~= "unix" then
                  table.insert(parts, vim.bo.fileformat)
                end
                return table.concat(parts, " ")
              end,
              cond = function()
                local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
                return enc ~= "utf-8" or vim.bo.fileformat ~= "unix"
              end,
            },
          },
          lualine_z = {
            function()
              return " " .. os.date("%a %H:%M")
            end,
          },
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
      -- Enable native virtual lines (rendered directly below the
      -- affected line) with custom formatting
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

      -- Some clangd tweaks (e.g. several of its clang-tidy quick
      -- fixes) are only sent to clients that advertise support for
      -- resolving a code action's edit in a second round-trip, rather
      -- than requiring the whole edit up front. cmp-nvim-lsp's
      -- capabilities don't declare this on their own, so without it
      -- clangd just leaves those actions out of the list entirely
      -- instead of sending something the client can't apply.
      capabilities.textDocument.codeAction = vim.tbl_deep_extend("force", capabilities.textDocument.codeAction or {}, {
        dataSupport = true,
        resolveSupport = { properties = { "edit" } },
      })

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

        -- clangd doesn't support renaming macros or namespaces at all
        -- (clangd/clangd#1890, still open) -- it's supposed to just
        -- reply "symbol is not a supported kind", but has a separate
        -- crash bug where it can SIGSEGV while handling that same
        -- rejection instead of returning the error cleanly. This
        -- catches the common case (cursor on the #define/namespace
        -- line itself) with treesitter before ever asking clangd, so
        -- the crash can't be triggered that way. It can't catch every
        -- case -- invoking rename on a macro from where it's *used*
        -- rather than defined still reaches clangd, since a macro
        -- usage is just plain text to treesitter, indistinguishable
        -- from any other identifier. If clangd crashes anyway, restart
        -- it with :LspRestart; renaming a macro by hand with
        -- :%s/\<old\>/new/g is the right tool regardless, since it's
        -- pure text substitution with no scope for clangd to resolve.
        local function renaming_unsupported_kind()
          local ok, node = pcall(vim.treesitter.get_node)
          if not ok then
            return false
          end
          local cword = vim.fn.expand("<cword>")
          while node do
            local kind = node:type()
            if kind == "preproc_def" or kind == "preproc_function_def" or kind == "namespace_definition" then
              local name_node = node:field("name")[1]
              if name_node and vim.treesitter.get_node_text(name_node, 0) == cword then
                return true
              end
            end
            node = node:parent()
          end
          return false
        end

        -- Safe Rename Function (Fixes double execution/prompt issues)
        local function safe_rename()
          if renaming_unsupported_kind() then
            vim.notify(
              "clangd can't rename macros or namespaces (unsupported upstream, and known to crash on the attempt) -- "
                .. "use :%s/\\<old\\>/new/g instead.",
              vim.log.levels.WARN
            )
            return
          end
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

        -- Neovim's default vim.lsp.buf.code_action() only looks at
        -- diagnostics on the exact cursor line. That's a needlessly
        -- easy way to come up empty here specifically: virtual_lines
        -- (set above) renders a diagnostic's message as an extra line
        -- directly BELOW its own line, right where the next real line
        -- of code sits -- so a diagnostic that reads as "right there"
        -- is actually one line above the cursor as far as the LSP
        -- request is concerned. This widens the request to also catch
        -- a diagnostic one line either side, pulling each one's
        -- original LSP-format diagnostic back out of user_data.lsp
        -- (vim.diagnostic.get() preserves it there for exactly this),
        -- and grows the requested range to actually cover them too --
        -- a server is free to ignore a diagnostic in context that
        -- falls outside the requested range, so widening only the
        -- diagnostics list without the range wouldn't reliably help.
        --
        -- code_action()'s `range` wants plain {row, col} tuples using
        -- mark-like indexing (1-indexed row, 0-indexed col -- the same
        -- shape nvim_win_get_cursor()/nvim_buf_get_mark() use), NOT LSP
        -- {line=, character=} position objects: it hands start/end
        -- straight to vim.lsp.util.make_given_range_params(), which
        -- indexes into them positionally (start_pos[1], start_pos[2]).
        -- A {line=, character=} table has no numeric [1]/[2], so that
        -- indexing was silently nil and the arithmetic on it crashed
        -- with E5108 ("attempt to perform arithmetic on a nil value")
        -- every time this ran. min_line/max_line below are 0-indexed
        -- (from diagnostic .lnum/.end_lnum), so +1 converts to mark
        -- indexing; the end column is the target line's real length so
        -- the range also reaches a diagnostic that starts mid-line
        -- rather than only ones starting at column 0.
        vim.keymap.set('n', '<leader>la', function()
          local row = vim.api.nvim_win_get_cursor(0)[1] - 1
          local nearby, min_line, max_line = {}, row, row
          for _, d in ipairs(vim.diagnostic.get(bufnr)) do
            if math.abs(d.lnum - row) <= 1 and d.user_data and d.user_data.lsp then
              table.insert(nearby, d.user_data.lsp)
              min_line = math.min(min_line, d.lnum)
              max_line = math.max(max_line, d.end_lnum or d.lnum)
            end
          end
          if vim.tbl_isempty(nearby) then
            vim.lsp.buf.code_action()
            return
          end
          local last_line = vim.api.nvim_buf_get_lines(bufnr, max_line, max_line + 1, false)[1] or ""
          vim.lsp.buf.code_action({
            context = { diagnostics = nearby },
            range = { start = { min_line + 1, 0 }, ["end"] = { max_line + 1, #last_line } },
          })
        end, { buffer = bufnr, silent = true, desc = "Code Actions" })
        -- Visual-mode counterpart: several clangd tweaks (Extract
        -- Function/Variable, raw-string conversion, ...) only show up
        -- when the request carries an actual selection range instead
        -- of the zero-width one normal mode sends.
        vim.keymap.set('x', '<leader>la', vim.lsp.buf.code_action, { buffer = bufnr, silent = true, desc = "Code Actions (Selection)" })
        vim.keymap.set('n', '<leader>lf', function() vim.lsp.buf.format { async = true } end, { buffer = bufnr, silent = true, desc = "Format File" })
        -- "Fix all clang-tidy issues in this file" turns out not to be
        -- something clangd's code actions can actually do: this used
        -- to filter for LSP's `source.fixAll` code action kind, but
        -- clangd never returns actions of that kind -- clang-tidy
        -- fixes surface from clangd only as individual `quickfix`
        -- actions, one per diagnostic, and clangd's own issue tracker
        -- confirms there's no batched "fix everything" kind (clangd/
        -- clangd#1446). So this always came back "No code actions
        -- available" no matter what the file contained.
        --
        -- Running the actual clang-tidy binary with --fix sidesteps
        -- clangd's code actions entirely and does what this key was
        -- always meant to: apply every fix the tool can make across
        -- the whole file in one pass, using the same .clang-tidy and
        -- compile_commands.json clangd itself uses. --fix (rather than
        -- --fix-errors) deliberately leaves the file untouched if
        -- clang-tidy hits real compiler errors, instead of forcing
        -- fixes onto code that doesn't compile -- switch it to
        -- --fix-errors below if you'd rather it try anyway.
        vim.keymap.set('n', '<leader>lt', function()
          if vim.fn.executable("clang-tidy") == 0 then
            vim.notify("clang-tidy not found on PATH", vim.log.levels.ERROR)
            return
          end
          local filepath = vim.api.nvim_buf_get_name(bufnr)
          if filepath == "" then
            vim.notify("Buffer has no file on disk to run clang-tidy on", vim.log.levels.WARN)
            return
          end
          -- clang-tidy reads from disk, not the buffer -- make sure
          -- what's on disk actually matches what's on screen first.
          if vim.bo[bufnr].modified then
            vim.cmd("write")
          end

          local cmd = { "clang-tidy", "--fix" }
          local db = vim.fs.find("compile_commands.json", {
            upward = true,
            path = vim.fs.dirname(filepath),
          })[1]
          if db then
            vim.list_extend(cmd, { "-p", vim.fs.dirname(db) })
          end
          table.insert(cmd, filepath)

          -- No "starting..." notification, and nothing shown at all on
          -- a normal (exit 0) run: clang-tidy always writes chatter to
          -- stderr -- including a notice about a missing compile
          -- database, and its own end-of-run warning count -- even
          -- when everything worked fine, so treating that output as
          -- warning-worthy just because it's non-empty was the actual
          -- source of the noise. Only a genuine failure (non-zero
          -- exit) surfaces anything here.
          vim.system(cmd, { text = true }, function(result)
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(bufnr) then
                return
              end
              -- Reload from disk so the buffer picks up whatever
              -- clang-tidy just rewrote. :edit! (rather than
              -- :checktime) reloads unconditionally instead of
              -- prompting, since 'autoread' isn't set above.
              local view = vim.fn.winsaveview()
              vim.api.nvim_buf_call(bufnr, function()
                vim.cmd("edit!")
              end)
              pcall(vim.fn.winrestview, view)

              if result.code ~= 0 then
                local msg = vim.trim(result.stderr or "")
                if #msg > 400 then
                  msg = msg:sub(1, 400) .. "\n... (truncated -- re-run in a terminal for full output)"
                end
                vim.notify("clang-tidy exited with status " .. result.code .. ":\n" .. msg, vim.log.levels.WARN)
              else
                vim.notify("clang-tidy --fix finished", vim.log.levels.INFO)
              end
            end)
          end)
        end, { buffer = bufnr, silent = true, desc = "Fix All (clang-tidy)" })
        vim.keymap.set('n', '<leader>li', '<cmd>LspInfo<CR>', { buffer = bufnr, silent = true, desc = "LSP Info" })

        -- Diagnostic navigation, by severity. ]d/[d for "whatever's
        -- next" regardless of severity; ]e/[e, ]w/[w, ]t/[t narrow to
        -- errors, warnings, and hints ("tip" is the mnemonic here --
        -- LSP itself calls that severity level "Hint") respectively.
        -- No `float` option on the jump itself: virtual_lines (set
        -- above) already shows the message text permanently, so a
        -- floating preview on top of it would just be redundant.
        local function diag_jump(count, severity)
          return function()
            vim.diagnostic.jump({ count = count, severity = severity })
          end
        end
        vim.keymap.set('n', ']d', diag_jump(1), { buffer = bufnr, silent = true, desc = "Next Diagnostic" })
        vim.keymap.set('n', '[d', diag_jump(-1), { buffer = bufnr, silent = true, desc = "Previous Diagnostic" })
        vim.keymap.set('n', ']e', diag_jump(1, vim.diagnostic.severity.ERROR), { buffer = bufnr, silent = true, desc = "Next Error" })
        vim.keymap.set('n', '[e', diag_jump(-1, vim.diagnostic.severity.ERROR), { buffer = bufnr, silent = true, desc = "Previous Error" })
        vim.keymap.set('n', ']w', diag_jump(1, vim.diagnostic.severity.WARN), { buffer = bufnr, silent = true, desc = "Next Warning" })
        vim.keymap.set('n', '[w', diag_jump(-1, vim.diagnostic.severity.WARN), { buffer = bufnr, silent = true, desc = "Previous Warning" })
        vim.keymap.set('n', ']t', diag_jump(1, vim.diagnostic.severity.HINT), { buffer = bufnr, silent = true, desc = "Next Tip" })
        vim.keymap.set('n', '[t', diag_jump(-1, vim.diagnostic.severity.HINT), { buffer = bufnr, silent = true, desc = "Previous Tip" })
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(args)
          on_attach(args.buf)
        end,
      })

      -- Per-server overrides beyond the shared `capabilities` above.
      -- clangd's own binary defaults already cover most of this, but
      -- being explicit documents intent and avoids depending on
      -- whatever a given clangd build's defaults happen to be:
      --   --background-index    index the whole project up front,
      --                         not just open files -- clang-tidy
      --                         checks and code actions that need
      --                         full semantic info are noticeably
      --                         thinner without it.
      --   --clang-tidy          explicit, even though on by default.
      --   --header-insertion/--completion-style/--all-scopes-completion/
      --   --cross-file-rename   richer completion and project-wide
      --                         rename instead of the conservative
      --                         single-file defaults.
      -- None of this substitutes for a compile_commands.json, though:
      -- without one, clangd falls back to guessed compiler flags, and
      -- most clang-tidy checks -- and the code actions/fixes tied to
      -- them -- need real -std/-I flags to run at all. Generate one
      -- via CMake (`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, then symlink
      -- or copy build/compile_commands.json to the project root) or
      -- `bear` for non-CMake projects if <leader>la/<leader>lt still
      -- come up thin on a real project after this.
      local server_opts = {
        clangd = {
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--completion-style=detailed",
            "--header-insertion=iwyu",
            "--all-scopes-completion",
            "--cross-file-rename",
          },
        },
      }

      -- Setup LSPs via the built-in vim.lsp.config()/vim.lsp.enable()
      -- API (replaces the deprecated require('lspconfig')[x].setup()
      -- framework). Default per-server settings still come from
      -- nvim-lspconfig, which only needs to be on the runtimepath.
      local servers = { "clangd", "gopls", "omnisharp", "ts_ls", "html", "cssls" }
      for _, lsp in ipairs(servers) do
        vim.lsp.config(lsp, vim.tbl_deep_extend("force", { capabilities = capabilities }, server_opts[lsp] or {}))
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
