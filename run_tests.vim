
" run_tests.vim - Script to launch Plenary tests using a custom init file.

" Be less verbose about file messages
set shortmess+=F

" --- Add Plenary to Launcher's Runtime Path ---
" Calculate the path relative to this script (run_tests.vim in project root)
let s:launcher_script_dir = expand('<sfile>:p:h')
" *** ADJUST this path if your Plenary location is different ***
let s:plenary_path = s:launcher_script_dir . '/tests/site/pack/deps/start/plenary.nvim'

" Add Plenary's path to the runtimepath for *this* Neovim instance
if isdirectory(s:plenary_path)
  " Using execute() because we use a variable
  execute 'set runtimepath+=' . fnameescape(s:plenary_path)
else
  " --- CRITICAL ERROR: Plenary Not Found ---
  echohl ErrorMsg
  echo "ERROR: Plenary plugin not found for launcher!"
  echo "       Expected at: " . s:plenary_path
  echo "       Please check the path in run_tests.vim"
  echohl None
  cquit!
endif

" --- Load Plenary Plugin ---
" Explicitly load the plugin script so its commands are available.
try
  runtime! plugin/plenary.vim
catch
  " --- CRITICAL ERROR: Plenary Load Failed ---
  echohl ErrorMsg
  echo "ERROR: Failed to load Plenary plugin runtime files."
  echo "       Check path and Plenary installation: " . s:plenary_path
  echo v:exception
  echohl None
  cquit!
endtry

" Now, Plenary commands should be available...

" Calculate the absolute path to the test initialization script
let s:test_init_script = s:launcher_script_dir . '/tests/test_init.vim'

" --- Sanity Check: Ensure the test init script exists ---
if !filereadable(s:test_init_script)
  " --- CRITICAL ERROR: Test Init Script Not Found ---
  echohl ErrorMsg
  echo "ERROR: Test init script not found!"
  echo "       Expected at: " . s:test_init_script
  echo "       Please ensure the file exists and the path is correct."
  echohl None
  cquit!
endif

" --- Execute Plenary ---
" We need to use execute because we are building the command string dynamically
" with the variable s:test_init_script.
try
  execute 'PlenaryBustedDirectory tests/ {minimal_init = ''' . fnameescape(s:test_init_script) . '''}'
catch
  " --- CRITICAL ERROR: Plenary Command Failed ---
  echohl ErrorMsg
  echo "ERROR: Failed to execute PlenaryBustedDirectory command:"
  echo v:exception
  echohl None
  cquit!
endtry

" --- Exit Neovim ---
silent! quit!
