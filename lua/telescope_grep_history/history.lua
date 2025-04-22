-- ~/.config/nvim/lua/telescope_grep_history/history.lua
-- Manages a single grep history list in memory and file I/O.

local M = {}

-- Configuration (only basic limit stored here)
local config = {
	history_limit = 10, -- Default, overridden by init.lua's setup
}

-- Store history in memory (oldest first -> newest last)
M.history = {}
-- Path to the currently active history file
M.active_history_file = nil

-- Helper: Read file into lines (handles potential file read errors)
local function read_file(path)
	local lines = {}
	local file, err = io.open(path, "r")
	if not file then
		-- Don't spam errors if file just doesn't exist yet
		if err and not err:match("No such file or directory") then
			vim.notify("[telescope_grep_history] Error reading file: " .. path .. " - " .. err, vim.log.levels.WARN)
		end
		return lines -- Return empty list
	end

	for line in file:lines() do
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	file:close()
	return lines
end

-- Helper: Write lines to file (saves newest first, creates dirs)
local function write_file(path, lines)
	-- Ensure directory exists
	local dir = vim.fn.fnamemodify(path, ":h")

	-- Check if the directory path exists and is a file (Error condition)
	if vim.fn.filereadable(dir) == 1 and vim.fn.isdirectory(dir) == 0 then
		vim.notify(
			"[telescope_grep_history] Error: Cannot create history directory '"
				.. dir
				.. "', a file with that name already exists.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Attempt to create the directory if it doesn't exist
	if vim.fn.isdirectory(dir) == 0 then
		local ok, err = pcall(vim.fn.mkdir, dir, "p")
		if not ok then
			vim.notify(
				"[telescope_grep_history] Error creating directory: " .. dir .. " - " .. (err or "Unknown error"),
				vim.log.levels.ERROR
			)
			return
		end
		-- Double check creation worked
		if vim.fn.isdirectory(dir) == 0 then
			vim.notify(
				"[telescope_grep_history] Error: Failed to create history directory: " .. dir,
				vim.log.levels.ERROR
			)
			return
		end
	end

	local file, err = io.open(path, "w")
	if not file then
		vim.notify(
			"[telescope_grep_history] Error opening file for writing: " .. path .. " - " .. (err or "Unknown error"),
			vim.log.levels.ERROR
		)
		return
	end

	-- Write newest first (which is last in M.history)
	for i = #lines, 1, -1 do
		file:write(lines[i] .. "\n")
	end
	file:close()
end

-- Load history from a specific file path
function M.load_history_from(path)
	if not path then
		-- vim.notify("[telescope_grep_history] Load request with nil path. Clearing history.", vim.log.levels.DEBUG)
		M.history = {} -- Reset if path is nil
		return
	end
	-- vim.notify("[telescope_grep_history] Attempting to load history from: " .. path, vim.log.levels.DEBUG)
	local file_content = read_file(path)
	-- File stores newest first, load into memory oldest first
	local reversed_history = {}
	for i = #file_content, 1, -1 do
		table.insert(reversed_history, file_content[i])
	end
	M.history = reversed_history
	-- Enforce limit
	while #M.history > config.history_limit do
		table.remove(M.history, 1) -- Remove oldest
	end
	-- vim.notify("[telescope_grep_history] Loaded " .. #M.history .. " entries from: " .. path, vim.log.levels.DEBUG)
end

-- Save current history to the active file
function M.save_history()
	if not M.active_history_file then
		-- This can happen briefly during startup before scope is determined, usually benign.
		-- vim.notify("[telescope_grep_history] Warning: No active history file set for saving.", vim.log.levels.DEBUG)
		return
	end
	-- vim.notify("[telescope_grep_history] Saving history to: " .. M.active_history_file, vim.log.levels.DEBUG)
	write_file(M.active_history_file, M.history)
end

-- Update the active history file path and load its content
function M.update_active_history_file(path)
	-- vim.notify("[telescope_grep_history] Request to update active file. Current: '" .. (M.active_history_file or "nil") .. "', New: '" .. (path or "nil") .. "'", vim.log.levels.DEBUG)
	if M.active_history_file ~= path then
		-- vim.notify("[telescope_grep_history] Paths differ! Switching history file.", vim.log.levels.DEBUG)
		M.active_history_file = path
		M.load_history_from(M.active_history_file)
		-- else
		-- vim.notify("[telescope_grep_history] Paths are the same. History file not switched.", vim.log.levels.DEBUG)
	end
end

-- Add entry to the current history
function M.add_entry(query)
	query = vim.trim(query)
	if query == "" then
		return
	end

	-- Remove duplicates (case-sensitive)
	local found_index = -1
	for i, entry in ipairs(M.history) do
		if entry == query then
			found_index = i
			break
		end
	end
	if found_index > 0 then
		table.remove(M.history, found_index)
	end

	-- Add to end (newest)
	table.insert(M.history, query)

	-- Enforce limit (remove oldest)
	while #M.history > config.history_limit do
		table.remove(M.history, 1)
	end

	M.save_history() -- Save immediately after adding
end

-- Basic setup function to store options (like limit) from init.lua
function M.setup(opts)
	opts = opts or {}
	config.history_limit = opts.history_limit or config.history_limit
end

M.read_file = read_file -- Expose for mocking in tests

return M
