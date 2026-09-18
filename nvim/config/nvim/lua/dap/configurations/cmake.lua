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
