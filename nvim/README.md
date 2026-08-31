# Neovim Setup

A single-script Neovim configuration built around C/C++ development (CMake + clangd + codelldb), with LSP support for Go, C#, TypeScript/JavaScript, HTML, and CSS alongside it.

Supports **Fedora, Ubuntu, Debian, and Arch Linux** (and their common derivatives — Pop!_OS, Linux Mint, Manjaro, EndeavourOS, etc. — via `/etc/os-release`'s `ID_LIKE`) — the script detects which one you're on and uses the right package manager and package names automatically.

## Contents

- [Installing](#installing)
- [What gets installed](#what-gets-installed)
- [Editor basics](#editor-basics)
- [Look & feel](#look--feel)
- [Buffers & tabs](#buffers--tabs-bufferline)
- [Text search (Telescope)](#text-search-telescope)
- [File explorer (nvim-tree)](#file-explorer-nvim-tree)
- [LSP & code intelligence](#lsp--code-intelligence)
- [Autocompletion & snippets](#autocompletion--snippets)
- [Documentation generation](#documentation-generation)
- [Debugging (nvim-dap)](#debugging-nvim-dap)
- [Terminal](#terminal)
- [Git](#git)
- [Hex viewer](#hex-viewer)
- [Formatting and linting](#formatting-and-linting)
- [Known quirks](#known-quirks)

## Installing

```bash
chmod +x setup_neovim.sh
./setup_neovim.sh
```

**This deletes `~/.config/nvim` and `~/.local/share/nvim` before writing the new config** — there is no backup step. If you have an existing Neovim setup you care about, copy it elsewhere first.

The script:
1. Detects your distro and installs system packages via the right manager (`dnf`/`apt`/`pacman`), plus two Nerd Fonts (JetBrainsMono, Cascadia Code) for icon glyphs.
2. Wipes and rewrites `~/.config/nvim`.
3. Writes personal `~/.clang-format`/`~/.clang-tidy` fallbacks (see [Formatting and linting](#formatting-and-linting)).

First launch takes a minute or two: `lazy.nvim` bootstraps itself and installs all plugins, then Mason installs the language servers and `codelldb`.

### Distro-specific notes

- **Debian**: the .NET SDK isn't in Debian's own repos, so the script adds Microsoft's apt feed just for that one package. This step is best-effort — if it fails, the rest of the script still completes; see the printed warning for manual install instructions (only matters for C#/omnisharp).
- **Ubuntu/Debian**: `fd-find`'s binary is named `fdfind` (a package-name clash with something unrelated), not `fd` like on Fedora/Arch. The script symlinks `~/.local/bin/fd` to it so anything expecting a plain `fd` on `PATH` (e.g. Telescope's file finder) works the same as everywhere else — make sure `~/.local/bin` is actually on your `PATH`.
- **Arch**: the script runs a full `pacman -Syu` before installing anything new, per Arch's own guidance against partial upgrades — this does mean it'll upgrade your existing packages too, not just add new ones.
- **Older distro releases** (Debian stable, older Ubuntu LTS): this config relies on Neovim 0.11+ APIs throughout. If your distro's packaged Neovim is older, the script prints a warning after install — see [Neovim's install docs](https://github.com/neovim/neovim/blob/master/INSTALL.md) for an AppImage/PPA/prebuilt build if so.

## What gets installed

Package names vary by distro (see the script for the exact list per package manager), but the same set gets installed everywhere:

- **Compilers/tools**: gcc, g++, make, cmake, clang tooling, lldb, gdb, .NET SDK 8.0, Go, nodejs/npm, python3-pip
- **CLI tools**: ripgrep, fd, git, curl, wget, unzip, fish (used only for Neovim's embedded terminal — see [Terminal](#terminal))
- **Language servers**: clangd, gopls, omnisharp, ts_ls, html, cssls (via Mason), plus `typescript-language-server` and `vscode-langservers-extracted` via npm
- **Debug adapter**: codelldb (auto-installed by Mason on first debug session)

## Editor basics

- Relative + absolute line numbers, system clipboard integration (`unnamedplus`), persistent undo, smart-case search, always-on sign column.
- Tab width: **4**, using real tab characters — not expanded to spaces.
- `c`/`cpp`/`javascript`/`typescript` indentation uses Neovim's own built-in per-filetype indent logic (`cindent` for c/cpp, the bundled JS/TS indent scripts for the rest) rather than treesitter's indent module — treesitter's indent is known to be unreliable for these specifically (inconsistent brace placement, phantom extra indent on nested blocks), more so since the `nvim-treesitter` branch this config uses is frozen upstream (see [Known quirks](#known-quirks)). `css`/`json` are also curly-brace languages that can hit the same issue — worth disabling there too if it comes up.
- Comments don't auto-continue onto a new line when the current line has real code on it — pressing Enter or `o`/`O` there starts a plain new line. On a comment-*only* line, Enter continues it with the same marker (`//`, `#`, or `--`); pressing Enter a second time with nothing typed breaks out instead of continuing again, clearing that line — same convention Vim itself has always used for this.
- Bracket/quote pairs auto-close as you type: `()`, `{}`, `[]`, `""`, `''`.
- True color, rounded borders on floating windows (hover, LspInfo, Mason, etc. — Neovim 0.11+), styled window separators.
- OSC 52 clipboard support, so yank/paste works correctly over SSH.

### General keymaps

| Key | Mode | Action |
|---|---|---|
| `<Esc>` | Normal | Clear search highlight |
| `<leader>p` | Normal | Force inline paste (paste as characters at cursor, ignoring line-wise register type) |
| `p` / `P` | Visual | Paste over selection without clobbering the unnamed register |
| `J` / `K` | Visual | Move selected lines down / up |
| `<A-j>` / `<A-k>` | Normal/Insert/Visual | Move current line (or selection) down / up |
| `<leader>cb` | Normal | Clear the current line's content, leaving it blank in place (doesn't delete the line itself) |
| `<C-s>` | Normal/Visual/Insert | Save file |
| `<C-h/j/k/l>` | Normal | Move to left/lower/upper/right window |
| `<leader>sv` / `<leader>sh` | Normal | Split vertically / horizontally |
| `<leader>se` | Normal | Equalize split sizes |
| `<leader>sx` | Normal | Close current split |

## Look & feel

- **Theme**: `tokyonight` (night variant), customized to a pure black background, with custom colors for error/warn/info/hint diagnostic virtual lines.
- **Dashboard**: `alpha-nvim` start screen with quick actions — find file, recent files, live grep, new file, edit config, quit.
- **Statusline**: `lualine`, styled with true Powerline arrow separators (the seamless, edge-to-edge kind — between sections, a thinner version between components within a section). Left to right:
  - Mode, plus a macro-recording indicator (`● REC @<register>`) that only appears while a macro is actually being recorded.
  - Git branch and a diff summary (added/changed/removed), grouped together as one git cluster instead of being split across the line.
  - File-type icon fused directly to the filename with no separator between them — it reads as one unit rather than a boxed-off icon — plus a `●` for unsaved changes and `[RO]` for read-only buffers.
  - Search count, diagnostics, the name(s) of any attached LSP client(s), and a word count that only shows up on prose filetypes (markdown, text, tex, commit messages).
  - Progress, cursor location, and the file's encoding/line-ending — but only when they differ from Neovim's own defaults (utf-8, unix), so a normal file doesn't clutter the line confirming the obvious.
  - A clock with the abbreviated weekday.
  - The Powerline glyphs live in the E0B0–E0B3 Unicode range, part of the same Nerd Font patch as the file/branch icons elsewhere in the statusline — if the icons render, the arrows will too. If they instead show as boxes or `?`, it means the terminal's font setting isn't pointed at the *patched* font family specifically (Nerd Fonts rename it, e.g. "CaskaydiaCove Nerd Font" rather than plain "Cascadia Code"). Verify with `echo -e "\ue0b0"` in a terminal, outside Neovim entirely — if that's blank, fix the terminal's font setting rather than the config.
- **Indent guides**: `indent-blankline` — colored guide per indent level, plus the current lexical scope (the block your cursor is inside) is highlighted with its own guide color. The underline that used to mark the scope's start/end line is disabled (`show_start`/`show_end = false`) — just the colored guide remains.
- **Inline color previews**: `nvim-colorizer` shows hex/rgb color values with their actual color as a background.
- **Notifications**: `nvim-notify` replaces the default notification popups with floating, styled ones, positioned bottom-right.
- **Prompts**: `dressing.nvim` upgrades the rename prompt, breakpoint-condition prompt, and DAP path prompts to floating dialogs instead of plain command-line input.

## Buffers & tabs (`bufferline`)

Each buffer tab shows its ordinal position number. Pinned buffers are always kept leftmost as a block.

| Key | Action |
|---|---|
| `<S-h>` / `<S-l>` | Previous / next buffer (follows the order shown on screen, including any reordering) |
| `<A-1>` … `<A-9>` / `<F1>`–`<F9>` | Jump directly to the buffer at that position. `<F5>` and `<F10>` each pull double duty with the debugger (see [Debugging](#debugging-nvim-dap)) — they act as buffer jumps at rest, and hand themselves over to DAP for the duration of an active debug session. |
| `<A-0>` / `<F10>` | Jump to the last buffer |
| `<A-,>` / `<A-.>` | Move current buffer left / right (blocked from crossing into the pinned block — wraps to the other end instead) |
| `<leader>bp` | Toggle pin on current buffer |
| `<leader>bx` | Close every **unpinned** buffer with **no unsaved changes** (pinned buffers and anything modified are left alone) |
| `<leader>bd` | Close current buffer |

Setting an explicit `<F1>` mapping here also overrides Neovim's built-in `<F1>`-opens-help default — any explicit keymap for a key always takes precedence over Neovim's default for it.

## Text search (`Telescope`)

| Key | Action |
|---|---|
| `<leader>ff` | Find files |
| `<leader>fw` | Live grep |
| `<leader>fb` | List open buffers |
| `<leader>fh` | Search help tags |
| `<leader>fr` | Recent files |

## File explorer (`nvim-tree`)

`<leader>e` toggles the file explorer sidebar (right side). On top of nvim-tree's own defaults (`c`/`x`/`p` to copy/cut/paste, `m` to mark, `d` to delete, etc.), three custom commands:

| Key | Action |
|---|---|
| `gP` | Paste, resolving every naming **collision** in that paste with one `pattern/replacement` (Vim regex — same as `:s///`) instead of nvim-tree's normal one-at-a-time overwrite/rename prompt per conflicting file. Plain `p` is untouched. Only confirmed reliable for a **single** conflicting file at a time — see [Known quirks](#known-quirks). |
| `gM` | Copy every **marked** file/folder (mark with `m`, shown as a star) into the directory under the cursor, applying that same `pattern/replacement` regex to **every** name unconditionally — not just on collision. Doesn't touch nvim-tree's clipboard at all; reads the mark list directly and shells out to `cp -r` to do the copying itself. Marks aren't auto-cleared afterward — toggle them off individually with `m` when done. |
| `gC` | Clear the copy/cut clipboard outright. Useful if it's holding a stale entry (a file since renamed, moved, or deleted), which otherwise pastes as `ENOENT: no such file or directory` until cleared and re-copied fresh. |

`gP` and `gM` both fail safely rather than silently: a stale mark (pointing at a since-deleted path) is skipped and cleaned up automatically instead of attempted, and a rename that would produce a no-op copy-onto-itself is skipped with a clear reason instead of surfacing a raw `cp` error.

## LSP & code intelligence

Configured servers: **clangd** (C/C++), **gopls** (Go), **omnisharp** (C#), **ts_ls** (TS/JS), **html**, **cssls**. Diagnostics render as virtual lines above the offending line (not inline virtual text), with the message's leading category prefix stripped; diagnostic underlines are off.

| Key | Action |
|---|---|
| `gd` | Go to definition. Fuzzy picker with preview if there's more than one match (e.g. overloads); jumps directly for a single match. **On an `#include` line, opens the header file directly** — falls back to Vim's built-in `gf` if clangd can't resolve it. |
| `gD` | Go to declaration. Same `#include`-awareness and fallback as `gd`. |
| `gr` | Find all references, in a fuzzy picker with preview. |
| `K` | Hover documentation (renders Doxygen comments if present). |
| `<leader>lr` | Rename symbol (prompts for new name, safe against double-firing) |
| `<leader>la` | Code actions |
| `<leader>lf` | Format file (via clangd/LSP formatting — see [Formatting and linting](#formatting-and-linting) for the style used) |
| `<leader>li` | Show LSP client info |
| `<leader>cd` | Generate a Doxygen-style comment block — see [Documentation generation](#documentation-generation) |

## Autocompletion & snippets

`nvim-cmp` with LSP, snippet, buffer, and path sources.

- **Ghost text**: the top completion candidate previews inline after the cursor as you type — including path/directory completions (type `./` or `/home/` and see what's in that directory before you finish typing it).
- **`<Tab>` / `<S-Tab>`**: cycle the completion menu when it's open; otherwise, jump forward/backward through snippet placeholders (e.g. clangd's function-argument placeholders after accepting a call like `memcpy(...)`) if you're inside one.
- **`<CR>`**: confirm the selected completion.
- **`<Up>/<Down>/<Left>/<Right>/<Esc>`**: close the completion menu, then perform the normal cursor/escape action.
- Snippet sessions auto-close once the cursor actually leaves their text (different line, or outside the placeholder's parentheses) — so `Tab` won't unexpectedly jump back into an old, already-finished snippet later on.

## Documentation generation

`neogen` generates Doxygen-style comment skeletons — `<leader>cd` on/above a function drops in `@brief`/one `@param` per argument/`@return` matching that function's real signature. Fields are inserted as snippet placeholders, so `<Tab>`/`<S-Tab>` cycles through them the same way as any other snippet.

(There's no such thing as an actual "Doxygen language server" — clangd already understands Doxygen comment syntax natively for hover/signature help. This only handles generating the comment itself.)

## Debugging (`nvim-dap`)

C/C++ (and Rust) debugging via `codelldb`, auto-installed by Mason on first use. UI (`nvim-dap-ui`) opens automatically when a session starts and closes when it ends; variable values show inline via virtual text.

| Key | Action |
|---|---|
| `F5` / `<leader>dc` | Continue / start debugging — `F5` only while a session is already active; before that it's the "jump to buffer 5" shortcut, so **start a session with `<leader>dc` or `<leader>db`**, not `F5` |
| `F10` / `<leader>do` | Step over — `F10` only while a debug session is active; otherwise it's the "jump to last buffer" shortcut (see [Buffers & tabs](#buffers--tabs-bufferline)) |
| `F11` / `<leader>di` | Step into |
| `F12` / `<leader>dO` | Step out |
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>dr` | Open the debug REPL |
| `<leader>dl` | Re-run the last debug configuration |
| `<leader>dt` | Terminate the session |
| `<leader>du` | Toggle the debug UI |
| `<leader>dh` | Hover the variable under the cursor |

Default launch configs prompt for a path to the executable, or let you attach to a running process. `~/.config/nvim/lua/dap/configurations/cmake.lua` additionally defines project-specific configs for CMake-built targets (`build/tests/test_dynamic_library`, `build/demo/example_host`) — this file is a template with this repo's specific binary names/paths and will need editing for a different project.

## Terminal

| Key | Action |
|---|---|
| `<leader>tf` | Floating terminal |
| `<leader>th` | Horizontal terminal (bottom) |
| `<leader>tv` | Vertical terminal (side) |

Neovim's embedded terminal launches **fish** instead of your login shell, purely for its built-in inline "ghost text" suggestions for paths and command history (no config needed, accept with `→`/`End`) — a terminal-side equivalent of the completion ghost text above, since a `:terminal` buffer is a raw PTY that `nvim-cmp` has no visibility into. Your actual system login shell is untouched.

## Git

`gitsigns` shows added/changed/removed lines in the sign column against the current git state.

## Hex viewer

`<leader>h` toggles the current buffer between normal and hex-dump view (backed by `xxd`), rather than showing both simultaneously. That's deliberate: the hex dump is just ordinary buffer text under the hood, so editing it gets normal Neovim undo/redo for free, and nothing writes to disk until an explicit `:w` — same as any other file. A plugin doing a true live simultaneous hex+ASCII view was tried first, but it manages bytes with its own logic outside normal buffer editing, which is exactly why it had no undo at all.

The mapping also makes sure the buffer is actually loaded in binary mode before toggling (re-reading it with `++bin` if not) — opening a real binary file without that causes Neovim to misinterpret raw bytes as text before `xxd` even runs, surfacing as a `CONVERSION ERROR` instead of a clean hex dump. Since that reload discards whatever's currently in the buffer, `<leader>h` refuses to run it if there are unsaved changes — save (or explicitly discard with `:e!`) first.

## Formatting and linting

`~/.clang-format` and `~/.clang-tidy` are both written on every run, implementing a specific C/C++ coding style guide (naming conventions, Allman braces, real tabs, include ordering, and a curated set of modernize/cppcoreguidelines/bugprone clang-tidy checks — see the comments in each file for exactly which style guide section a given setting maps to). Both tools walk upward from the file being checked looking for their config file; since `$HOME` sits above every project, these act as your personal default for any project that doesn't ship its own `.clang-format`/`.clang-tidy` — a project's own file always takes precedence.

`<leader>lf` (LSP format) only consumes `.clang-format` — clangd's formatting is pure clang-format and has nothing to do with clang-tidy. `.clang-tidy` is picked up separately and automatically by clangd for live diagnostics, since clangd's clang-tidy integration is on by default.

## Known quirks

- **`nvim-treesitter` is pinned to its `master` branch**, not the current upstream default (`main`). `main` is an incompatible rewrite that removed the `nvim-treesitter.configs` API this config (and most existing configs/plugins) are built on. `master` is kept frozen upstream specifically for this kind of backward compatibility.
- A **Neovim 0.12 compatibility shim** is included for `master`-branch treesitter: 0.12 changed query predicate/directive results to sometimes be a list of nodes instead of a single node, which `master`'s legacy predicate handlers don't expect — this caused a `"Decoration provider ... attempt to call method 'range'"` error (most visible on markdown files). The shim normalizes results back to a single node before those handlers run. Purely cosmetic when unpatched (highlighting still worked) but noisy.
- **`nvim-cmp` absorbs the `<CR>` mapping used for smart comment continuation** as its own fallback, rather than it being called directly by Neovim. `cmp.setup()` runs after `init.lua`'s top-level code, and per its own keymap-composition system, it wraps whatever `<CR>` mapping already existed as the function it calls when its completion menu isn't visible, instead of simply discarding it. Worth knowing if you ever add or change an insert-mode `<CR>` mapping here: it will run through cmp's fallback chain rather than being invoked directly, which also means direct buffer edits from inside it (e.g. `nvim_set_current_line()`) fail with `E565` — express any change as keys to return instead.
- **`gP`'s regex-on-paste only handles single-file conflicts reliably.** nvim-tree has a separate, differently-shaped dialog specifically for multi-file conflicts within one paste ("N file(s) already exist" / Rename (suffix) / Overwrite all / Skip all), which `gP` doesn't detect. `gM` (copying marked files with an unconditional regex) was built as the more reliable tool for renaming several files at once.
- **`gM`'s stale-mark cleanup depends on `api.marks.toggle`**, a function name inferred from `m`'s own behavior rather than confirmed in nvim-tree's documentation directly, so it's wrapped defensively — if it's wrong on a given nvim-tree version, a stale mark just won't auto-clear (still requires manually pressing `m` on it), without otherwise breaking `gM`.
- **Smart comment continuation (`<CR>`) only recognizes `//`, `#`, and `--`** (C-family/JS/TS/Go, Python/bash/YAML/CMake, and Lua/SQL respectively) rather than being fully comment-syntax-agnostic — it computes the marker to repeat directly rather than deferring to Neovim's own `'comments'`-option-driven logic, which would cover more comment styles but came with its own timing problems (see the `<CR>`/cmp entry above).
