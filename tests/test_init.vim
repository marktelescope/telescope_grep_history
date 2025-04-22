" tests/test_init.vim - Minimal initialization script for Plenary tests.
" Used via the `minimal_init` option in PlenaryBustedDirectory.

" --- Basic Vim Setup ---
set nocompatible
filetype off
filetype plugin indent on
syntax enable

" --- Runtime Path Setup ---
" 1. Prepend the project root directory to the runtime path.
"    Calculate the absolute path FROM the location of *this* script file.
let s:test_init_dir = expand('<sfile>:p:h') " /path/to/project/tests
let s:project_root = fnamemodify(s:test_init_dir, ':h') " /path/to/project
execute 'set runtimepath^=' . fnameescape(s:project_root)

" 2. Add dependencies (Plenary, Telescope) to the runtime path.
"    Calculate the path relative to *this* script file (test_init.vim).
let s:script_dir = expand('<sfile>:p:h') " Gets the directory /path/to/project/tests
"    Define the path where dependencies are stored (ADJUST IF NEEDED)
let s:deps_dir = s:script_dir . '/site/pack/deps/start'

"    Add dependency paths using execute() because we use variables
"    Note: Removed directory existence warnings for brevity. Errors will occur
"          later during 'require' if paths are truly incorrect.
execute 'set runtimepath+=' . s:deps_dir . '/plenary.nvim'
execute 'set runtimepath+=' . s:deps_dir . '/telescope.nvim'

" --- CRITICAL: Synchronize runtimepath to Lua's package.path ---
" This ensures Lua's 'require' can find modules in the runtime paths.
lua << EOF
local rtp_paths = vim.split(vim.o.runtimepath, ',')
local lua_paths = {}
for _, path in ipairs(rtp_paths) do
  -- Clean path (remove trailing slashes/backslashes) just in case
  local clean_path = path:gsub("[\\/]$", "")
  if clean_path ~= '' then -- Avoid adding empty paths
    -- Add standard Lua search patterns for 'lua' directories
    table.insert(lua_paths, clean_path .. '/lua/?.lua')
    table.insert(lua_paths, clean_path .. '/lua/?/init.lua')
  end
end

-- Prepend our generated paths to the existing package.path
-- Use ';' as the separator (standard on Unix-like, works on Windows too for Lua)
package.path = table.concat(lua_paths, ';') .. ';' .. package.path

-- Removed debugging prints for CWD, initial/final package.path, etc.
EOF

" --- Final Setup ---
" You generally DON'T need to explicitly source plugin/plenary.vim here.
" Plenary's test runner handles its own setup.

" Make sure filetype detection is re-enabled
filetype on

" End of test_init.vim

