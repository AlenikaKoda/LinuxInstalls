# Neovim Setup for Fedora

A single-script Neovim configuration built around C/C++ development (CMake + clangd + codelldb), with LSP support for Go, C#, TypeScript/JavaScript, HTML, and CSS alongside it.

## Installing

```bash
chmod +x setup_neovim.sh
./setup_neovim.sh
```

**This deletes `~/.config/nvim` and `~/.local/share/nvim` before writing the new config** — there is no backup step. If you have an existing Neovim setup you care about, copy it elsewhere first.

The script:
1. Installs system packages via `dnf` (compilers, debuggers, language runtimes, LSPs) and two Nerd Fonts (JetBrainsMono, Cascadia Code) for icon glyphs.
2. Wipes and rewrites `~/.config/nvim`.
3. Writes a personal `~/.clang-format` fallback (see [Formatting](#formatting)).

First launch will take a minute or two: `lazy.nvim` bootstraps itself and installs all plugins, then Mason installs the language servers and `codelldb`.

## What gets installed

- **Compilers/tools**: gcc, g++, make, cmake, clang-tools-extra, lldb, gdb, dotnet-sdk-8.0, golang, nodejs/npm, python3-pip
- **CLI tools**: ripgrep, fd-find, git, curl, wget, unzip, fish (used only for Neovim's embedded terminal — see [Terminal](#terminal))
- **Language servers**: clangd, gopls, omnisharp, ts_ls, html, cssls (via Mason), plus `typescript-language-server` and `vscode-langservers-extracted` via npm
- **Debug adapter**: codelldb (auto-installed by Mason on first debug session)

## Editor basics

- Relative + absolute line numbers, system clipboard integration (`unnamedplus`), persistent undo, smart-case search, always-on sign column.
- Tab width: **4**, using real tab characters — not expanded to spaces.
- True color, rounded borders on floating windows (hover, LspInfo, Mason, etc. — Neovim 0.11+), styled window separators.
- OSC 52 clipboard support, so yank/paste works correctly over SSH.
- `c`/`cpp`/`javascript`/`typescript` indentation uses Neovim's own built-in per-filetype indent logic (`cindent` for c/cpp, the bundled JS/TS indent scripts for the rest) rather than treesitter's indent module — treesitter's indent is known to be unreliable for these specifically (inconsistent brace placement, phantom extra indent on nested blocks), more so since the `nvim-treesitter` branch this config uses is frozen upstream (see [Known quirks](#known-quirks)). `css`/`json` are also curly-brace languages that can hit the same issue — worth disabling there too if it comes up.

### General keymaps

| Key | Mode | Action |
|---|---|---|
| `<Esc>` | Normal | Clear search highlight |
| `<leader>p` | Normal | Force inline paste (paste as characters at cursor, ignoring line-wise register type) |
| `p` / `P` | Visual | Paste over selection without clobbering the unnamed register |
| `J` / `K` | Visual | Move selected lines down / up |
| `<C-s>` | Normal/Visual/Insert | Save file |
| `<C-h/j/k/l>` | Normal | Move to left/lower/upper/right window |
| `<leader>sv` / `<leader>sh` | Normal | Split vertically / horizontally |
| `<leader>se` | Normal | Equalize split sizes |
| `<leader>sx` | Normal | Close current split |

## Look & feel

- **Theme**: `tokyonight` (night variant), customized to a pure black background, with custom colors for error/warn/info/hint diagnostic virtual lines.
- **Dashboard**: `alpha-nvim` start screen with quick actions — find file, recent files, live grep, new file, edit config, quit.
- **Statusline**: `lualine`, themed to match, shows mode, git branch, diagnostics, filename, encoding/filetype, progress, and cursor location.
- **Indent guides**: `indent-blankline` — colored guide per indent level, plus the current lexical scope (the block your cursor is inside) is highlighted with its own guide color. The underline that used to mark the scope's start/end line is disabled (`show_start`/`show_end = false`) — just the colored guide remains.
- **Inline color previews**: `nvim-colorizer` shows hex/rgb color values with their actual color as a background.
- **Notifications**: `nvim-notify` replaces the default notification popups with floating, styled ones.
- **Prompts**: `dressing.nvim` upgrades the rename prompt, breakpoint-condition prompt, and DAP path prompts to floating dialogs instead of plain command-line input.

## Buffers & tabs (`bufferline`)

Each buffer tab shows its ordinal position number. Pinned buffers are always kept leftmost as a block.

| Key | Action |
|---|---|
| `<S-h>` / `<S-l>` | Previous / next buffer (follows the order shown on screen, including any reordering) |
| `<A-1>` … `<A-9>` / `<F1>`–`<F9>` | Jump directly to the buffer at that position. `<F5>` and `<F10>` each pull double duty with the debugger (see [Debugging](#debugging-nvim-dap)) — they act as buffer jumps at rest, and hand themselves over to DAP for the duration of an active debug session. |
| `<A-0>` / `<F10>` | Jump to the last buffer. |
| `<A-,>` / `<A-.>` | Move current buffer left / right (blocked from crossing into the pinned block — wraps to the other end instead) |
| `<leader>bp` | Toggle pin on current buffer |
| `<leader>bx` | Close every **unpinned** buffer with **no unsaved changes** (pinned buffers and anything modified are left alone) |
| `<leader>bd` | Close current buffer |

Setting an explicit `<F1>` mapping here also overrides Neovim's built-in `<F1>`-opens-help default — any explicit keymap for a key always takes precedence over Neovim's default for it.

## File & text search (`telescope`)

| Key | Action |
|---|---|
| `<leader>ff` | Find files |
| `<leader>fw` | Live grep |
| `<leader>fb` | List open buffers |
| `<leader>fh` | Search help tags |
| `<leader>fr` | Recent files |
| `<leader>e` | Toggle the file explorer sidebar (`nvim-tree`, right side) |

## LSP & code intelligence

Configured servers: **clangd** (C/C++), **gopls** (Go), **omnisharp** (C#), **ts_ls** (TS/JS), **html**, **cssls**. Diagnostics render as virtual lines above the offending line (not inline virtual text), with the message's leading category prefix stripped; diagnostic underlines are off.

| Key | Action |
|---|---|
| `gd` | Go to definition. Fuzzy picker with preview if there's more than one match (e.g. overloads); jumps directly for a single match. **On an `#include` line, opens the header file directly** — falls back to Vim's built-in `gf` if clangd can't resolve it. |
| `gD` | Go to declaration. Same `#include`-awareness and fallback as `gd`. |
| `gr` | Find all references, in a fuzzy picker with preview. |
| `K` | Hover documentation (renders Doxygen comments if present). |
| `<leader>lr` | Rename symbol (prompts for new name, safe against double-firing). |
| `<leader>la` | Code actions. |
| `<leader>lf` | Format file (via clangd/LSP formatting — see [Formatting](#formatting) for the style used). |
| `<leader>li` | Show LSP client info. |
| `<leader>cd` | Generate a Doxygen-style comment block (`@brief`/`@param`/`@return`) above the function under the cursor — see [Documentation generation](#documentation-generation). |

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

## Formatting

`~/.clang-format` is written on every run (LLVM-based, `BreakBeforeBraces: Attach` for K&R-style braces, 4-wide real tabs via `UseTab: Always`/`TabWidth: 4` to match the editor, 100-column limit). `clang-format` walks upward from the file being formatted looking for a `.clang-format`; since `$HOME` sits above every project, this acts as a personal default for any project that doesn't ship its own `.clang-format` — a project's own file always takes precedence.

## Known quirks

- **`nvim-treesitter` is pinned to its `master` branch**, not the current upstream default (`main`). `main` is an incompatible rewrite that removed the `nvim-treesitter.configs` API this config (and most existing configs/plugins) are built on. `master` is kept frozen upstream specifically for this kind of backward compatibility.
- A **Neovim 0.12 compatibility shim** is included for `master`-branch treesitter: 0.12 changed query predicate/directive results to sometimes be a list of nodes instead of a single node, which `master`'s legacy predicate handlers don't expect — this caused a `"Decoration provider ... attempt to call method 'range'"` error (most visible on markdown files). The shim normalizes results back to a single node before those handlers run. Purely cosmetic when unpatched (highlighting still worked) but noisy.
