local M = {}

local config = {
	history_limit = 10,
}

M.history = {}
M.active_history_file = nil

local function read_file(path)
	local lines = {}
	local file, err = io.open(path, "r")
	if not file then
		if err and not err:match("No such file or directory") then
			vim.notify("[telescope_grep_history] Error reading file: " .. path .. " - " .. err, vim.log.levels.WARN)
		end
		return lines
	end

	for line in file:lines() do
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	file:close()
	return lines
end

local function write_file(path, lines)
	local dir = vim.fn.fnamemodify(path, ":h")

	if vim.fn.filereadable(dir) == 1 and vim.fn.isdirectory(dir) == 0 then
		vim.notify(
			"[telescope_grep_history] Error: Cannot create history directory '"
				.. dir
				.. "', a file with that name already exists.",
			vim.log.levels.ERROR
		)
		return
	end

	if vim.fn.isdirectory(dir) == 0 then
		local ok, err = pcall(vim.fn.mkdir, dir, "p")
		if not ok then
			vim.notify(
				"[telescope_grep_history] Error creating directory: " .. dir .. " - " .. (err or "Unknown error"),
				vim.log.levels.ERROR
			)
			return
		end
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

	for i = #lines, 1, -1 do
		file:write(lines[i] .. "\n")
	end
	file:close()
end

function M.load_history_from(path)
	if not path then
		M.history = {}
		return
	end
	local file_content = read_file(path)
	local reversed_history = {}
	for i = #file_content, 1, -1 do
		table.insert(reversed_history, file_content[i])
	end
	M.history = reversed_history
	while #M.history > config.history_limit do
		table.remove(M.history, 1)
	end
end

function M.save_history()
	if not M.active_history_file then
		return
	end
	write_file(M.active_history_file, M.history)
end

function M.update_active_history_file(path)
	if M.active_history_file ~= path then
		M.active_history_file = path
		M.load_history_from(M.active_history_file)
	end
end

function M.add_entry(query)
	query = vim.trim(query)
	if query == "" then
		return
	end

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

	table.insert(M.history, query)

	while #M.history > config.history_limit do
		table.remove(M.history, 1)
	end

	M.save_history()
end

function M.setup(opts)
	opts = opts or {}
	config.history_limit = opts.history_limit or config.history_limit
end

M.read_file = read_file

return M
