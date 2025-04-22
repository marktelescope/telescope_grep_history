-- ~/.config/nvim/lua/telescope_grep_history/init.lua
-- Main plugin file for telescope_grep_history (scoped history for grep pickers)

local history = require("telescope_grep_history.history")
local Path -- Defer require until needed/available

local M = {}

-- Default configuration
M.config = {
	history_scope = "project", -- "project" or "global"
	project_markers = {
		".git",
		".svn",
		"_darcs",
		"Makefile",
		"package.json",
		"Cargo.toml",
		"setup.py",
		".project",
		".sln",
		".idea",
		".vscode",
		"go.mod",
		"lua",
	}, -- Files/dirs indicating root
	history_dir = vim.fn.stdpath("data") .. "/telescope_grep_history", -- Directory to store history files
	history_limit = 10, -- Default history limit per project/global
	global_history_file = vim.fn.stdpath("data") .. "/telescope_grep_global_history.txt", -- Fallback/Global file
	use_plenary_path = pcall(require, "plenary.path"), -- Check if plenary is available
}

-- --- Project Detection ---

-- Find project root by searching upwards for markers
local function find_project_root(start_dir)
	local current_dir = start_dir
	if not current_dir or current_dir == "" then
		return nil
	end

	-- Check if Plenary is available and require it if needed
	if M.config.use_plenary_path and Path == nil then
		Path = require("plenary.path")
	end

	-- Normalize path and ensure it's absolute
	if M.config.use_plenary_path and Path then
		current_dir = Path:new(current_dir):absolute()
	else
		-- Fallback if plenary not available or require failed
		current_dir = vim.fn.fnamemodify(vim.fs.normalize(current_dir), ":p")
	end

	-- Ensure current_dir is a string before proceeding
	if type(current_dir) ~= "string" then
		current_dir = tostring(current_dir)
	end

	while true do
		for _, marker in ipairs(M.config.project_markers) do
			local marker_path
			if M.config.use_plenary_path and Path then
				marker_path = Path:new(current_dir, marker)
				if marker_path:exists() then
					-- vim.notify("[telescope_grep_history] Found project root: " .. tostring(current_dir) .. " (marker: " .. marker .. ")", vim.log.levels.DEBUG)
					return tostring(current_dir)
				end
			else
				marker_path = current_dir .. "/" .. marker -- Simple concatenation
				if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
					-- Ensure consistent normalization right before returning
					local return_path = vim.fs.normalize(current_dir) -- <<< APPLY NORMALIZATION HERE

					-- vim.notify("[telescope_grep_history] Found project root: " .. current_dir .. " (marker: " .. marker .. ")", vim.log.levels.DEBUG)
					-- Optional: Keep debug log if you still have it
					vim.notify("[GH_DEBUG find_project_root] RETURNING (Fallback): " .. vim.inspect(return_path))
					return return_path -- Return the explicitly normalized path
				end
			end
		end -- end loop through markers

		-- Move up one directory
		local parent_dir
		local parent_obj -- Define outside the if block

		if M.config.use_plenary_path and Path then
			parent_obj = Path:new(current_dir):parent()
			-- Ensure parent exists and is different from current
			if not parent_obj or parent_obj:absolute() == current_dir then
				return nil
			end -- Reached root or error
			parent_dir = tostring(parent_obj)
		else
			parent_dir = vim.fn.fnamemodify(current_dir, ":h")
			-- Ensure parent exists and is different from current
			if parent_dir == current_dir or parent_dir == "" then
				return nil
			end -- Reached root or error
		end

		if parent_dir == nil then
			return nil
		end -- Safety check

		current_dir = parent_dir
	end -- <<<< CORRECTION: Added missing 'end' for the while loop
	-- The loop should only exit via the return statements inside it.
end

-- --- History File Path Generation ---

-- Simple hash function for filename generation
local function hash_string(str)
	local hash = 5381
	for i = 1, #str do
		hash = (hash * 33) + string.byte(str, i)
		-- Keep it within reasonable integer limits (Lua 5.1 uses doubles)
		hash = hash % 0xFFFFFFFF
	end
	return string.format("%x", hash) -- Return as hex string
end

-- Get the path for the history file based on scope and project root
local function get_history_path(project_root)
	if M.config.history_scope == "global" then
		return M.config.global_history_file
	end

	if project_root and project_root ~= "" then
		local hashed_root = hash_string(project_root)
		local filename = hashed_root .. "_grep_history.txt" -- Add _grep_ for clarity within dir
		if M.config.use_plenary_path and Path then
			return tostring(Path:new(M.config.history_dir, filename))
		else
			return M.config.history_dir .. "/" .. filename
		end
	else
		-- Fallback to global if no project root found in project scope
		-- vim.notify("[telescope_grep_history] No project root found, falling back to global history.", vim.log.levels.WARN)
		return M.config.global_history_file
	end
end

-- --- History Switching Logic ---

-- Function to be called by autocmds to update history based on current dir
function M.update_active_history()
	local current_dir = vim.fn.getcwd(-1, -1) -- Get CWD without triggering autocmds
	if not current_dir then
		return
	end -- Handle potential nil CWD early

	local project_root = nil
	if M.config.history_scope == "project" then
		project_root = find_project_root(current_dir)
	end
	local history_file_path = get_history_path(project_root)
	-- vim.notify("[telescope_grep_history] update_active_history called. CWD: ".. current_dir .. ", Project Root: " .. (project_root or "nil") .. ", History File: " .. (history_file_path or "nil"), vim.log.levels.DEBUG)
	history.update_active_history_file(history_file_path)
end

-- --- Telescope Integration ---

-- Define the mapping function to be attached to pickers
-- This function will be returned by setup()
local function create_attach_mappings()
	-- Get telescope modules locally within the function closure
	local actions = require("telescope.actions")
	local state = require("telescope.actions.state")

	local function grep_history_attach_mappings(prompt_bufnr, map)
		-- History index for the buffer (-1 means user input)
		vim.b[prompt_bufnr].history_index = -1

		-- Map Enter (<CR>) -- Standard behavior: Save history, select first, close.
		map("i", "<CR>", function()
			local picker = state.get_current_picker(prompt_bufnr)
			local current_query = picker and picker:_get_prompt() or ""
			if current_query ~= "" then
				history.add_entry(current_query) -- Use the history module function
			end
			vim.b[prompt_bufnr].history_index = -1 -- Reset history index on selection
			actions.select_default(prompt_bufnr)
			return true -- Consume the mapping
		end)

		-- Map <Up> -- Move focus from prompt to results (last item) + Normal mode
		map("i", "<Up>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				pcall(actions.move_selection_previous, prompt_bufnr) -- Use pcall for safety
				vim.cmd("stopinsert")
				return true -- Consume the mapping
			else
				-- Allow default <Up> behavior if not in prompt buffer
				return false
			end
		end)

		-- Map <Down> -- Move focus from prompt to results (first item) + Normal mode
		map("i", "<Down>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				pcall(actions.move_selection_next, prompt_bufnr) -- Use pcall for safety
				vim.cmd("stopinsert")
				return true -- Consume the mapping
			else
				-- Allow default <Down> behavior if not in prompt buffer
				return false
			end
		end)

		-- Map <Tab> -- Cycle FORWARDS through history (Newest -> Oldest -> Wrap)
		map("i", "<Tab>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				local picker = state.get_current_picker(prompt_bufnr)
				if not picker then
					return true
				end -- Should not happen

				-- Use history data from the history module
				local num_history = #history.history
				if num_history == 0 then
					return true
				end -- No history to cycle

				local current_index = vim.b[prompt_bufnr].history_index
				local next_index

				if current_index == -1 then
					-- First time pressing Tab: Start with the newest item (last in array)
					next_index = num_history - 1 -- 0-based index for calculation
				else
					-- Cycle backwards through 0-based indices (newest -> oldest)
					next_index = current_index - 1
				end

				-- Wrap around if we go past the oldest item
				if next_index < 0 then
					next_index = num_history - 1 -- Wrap back to newest
				end

				vim.b[prompt_bufnr].history_index = next_index
				-- Access history array using 1-based Lua index
				local entry = history.history[next_index + 1]
				if entry then -- Only update if entry exists
					picker:set_prompt(entry)
				end
				return true -- Consume the mapping
			else
				-- Allow default <Tab> behavior if not in prompt buffer
				return false
			end
		end) -- End <Tab> mapping

		return true -- Indicate successful attachment
	end -- End of grep_history_attach_mappings function

	-- Return the inner function so it can be assigned
	return grep_history_attach_mappings
end -- End of create_attach_mappings function

-- --- Main Setup Function ---

function M.setup(user_opts)
	user_opts = user_opts or {}
	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, user_opts)

	-- Setup the underlying history module with the limit
	history.setup({ history_limit = M.config.history_limit })

	-- Setup autocmds for project scope switching
	if M.config.history_scope == "project" then
		local group = vim.api.nvim_create_augroup("TelescopeGrepHistoryProjectSwitch", { clear = true })
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			pattern = "*", -- <<< CORRECTION: Use '*' pattern
			desc = "Load project grep history on startup",
			callback = function()
				-- vim.notify("[telescope_grep_history] VimEnter autocmd fired.", vim.log.levels.DEBUG)
				M.update_active_history()
			end,
		})
		vim.api.nvim_create_autocmd("DirChanged", {
			group = group,
			pattern = "*", -- <<< CORRECTION: Use '*' pattern
			desc = "Update project grep history on directory change",
			callback = function(args)
				-- vim.notify("[telescope_grep_history] DirChanged autocmd fired. CWD="..vim.fn.getcwd(-1,-1), vim.log.levels.DEBUG)
				M.update_active_history()
			end,
		})
	end

	-- Perform initial history load based on current directory at setup time
	-- This handles the case where the user config is loaded after VimEnter (e.g. with lazy.nvim)
	M.update_active_history()

	-- Create and return the attach_mappings function
	local attach_mappings_func = create_attach_mappings()

	-- Return a table containing the attach_mappings function
	return {
		attach_mappings = attach_mappings_func,
		-- Expose update function for manual trigger or debugging if needed
		update_active_history = M.update_active_history,
		-- Expose config if needed elsewhere
		-- config = M.config,
	}
end

return M
