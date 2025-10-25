-- lua/telescope_grep_history/init.lua
local history = require("telescope_grep_history.history")
local Path

local M = {}

M.config = {
	history_scope = "project",
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
	},
	history_dir = vim.fn.stdpath("data") .. "/telescope_grep_history",
	history_limit = 10,
	global_history_file = vim.fn.stdpath("data") .. "/telescope_grep_global_history.txt",
	use_plenary_path = pcall(require, "plenary.path"),
}

local function find_project_root(start_dir)
	local current_dir = start_dir
	if not current_dir or current_dir == "" then
		return nil
	end

	if M.config.use_plenary_path and Path == nil then
		Path = require("plenary.path")
	end

	if M.config.use_plenary_path and Path then
		current_dir = Path:new(current_dir):absolute()
	else
		current_dir = vim.fn.fnamemodify(vim.fs.normalize(current_dir), ":p")
	end

	if type(current_dir) ~= "string" then
		current_dir = tostring(current_dir)
	end

	while true do
		for _, marker in ipairs(M.config.project_markers) do
			local marker_path
			if M.config.use_plenary_path and Path then
				marker_path = Path:new(current_dir, marker)
				if marker_path:exists() then
					return tostring(current_dir)
				end
			else
				marker_path = current_dir .. "/" .. marker
				if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
					local return_path = vim.fs.normalize(current_dir)

					vim.notify("[GH_DEBUG find_project_root] RETURNING (Fallback): " .. vim.inspect(return_path))
					return return_path
				end
			end
		end

		local parent_dir
		local parent_obj

		if M.config.use_plenary_path and Path then
			parent_obj = Path:new(current_dir):parent()
			if not parent_obj or parent_obj:absolute() == current_dir then
				return nil
			end
			parent_dir = tostring(parent_obj)
		else
			parent_dir = vim.fn.fnamemodify(current_dir, ":h")
			if parent_dir == current_dir or parent_dir == "" then
				return nil
			end
		end

		if parent_dir == nil then
			return nil
		end

		current_dir = parent_dir
	end
end

local function hash_string(str)
	local hash = 5381
	for i = 1, #str do
		hash = (hash * 33) + string.byte(str, i)
		hash = hash % 0xFFFFFFFF
	end
	return string.format("%x", hash)
end

local function get_history_path(project_root)
	if M.config.history_scope == "global" then
		return M.config.global_history_file
	end

	if project_root and project_root ~= "" then
		local hashed_root = hash_string(project_root)
		local filename = hashed_root .. "_grep_history.txt"
		if M.config.use_plenary_path and Path then
			return tostring(Path:new(M.config.history_dir, filename))
		else
			return M.config.history_dir .. "/" .. filename
		end
	else
		return M.config.global_history_file
	end
end

function M.update_active_history()
	local current_dir = vim.fn.getcwd(-1, -1)
	if not current_dir then
		return
	end

	local project_root = nil
	if M.config.history_scope == "project" then
		project_root = find_project_root(current_dir)
	end
	local history_file_path = get_history_path(project_root)
	history.update_active_history_file(history_file_path)
end

local function create_attach_mappings()
	local actions = require("telescope.actions")
	local state = require("telescope.actions.state")

	local function grep_history_attach_mappings(prompt_bufnr, map)
		vim.b[prompt_bufnr].history_index = -1

		local function save_current_prompt(set_search_register)
			local picker = state.get_current_picker(prompt_bufnr)
			local current_query = picker and picker:_get_prompt() or ""
			if vim.trim(current_query) ~= "" then
				history.add_entry(current_query)
				if set_search_register then
					-- Set Vim's search register for n/N navigation
					vim.fn.setreg("/", vim.trim(current_query))
				end
			end
		end

		map("i", "<CR>", function()
			save_current_prompt(true)
			vim.b[prompt_bufnr].history_index = -1
			actions.select_default(prompt_bufnr)
			vim.schedule(function()
				vim.fn.setreg("/", vim.fn.getreg("/"))
			end)
			return true
		end)

		map("i", "<Up>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				save_current_prompt(false)
				vim.b[prompt_bufnr].history_index = -1
				pcall(actions.move_selection_previous, prompt_bufnr)
				vim.cmd("stopinsert")
				return true
			else
				return false
			end
		end)

		map("i", "<Down>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				save_current_prompt(false)
				vim.b[prompt_bufnr].history_index = -1
				pcall(actions.move_selection_next, prompt_bufnr)
				vim.cmd("stopinsert")
				return true
			else
				return false
			end
		end)

		map("i", "<Tab>", function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			if current_bufnr == prompt_bufnr then
				local picker = state.get_current_picker(prompt_bufnr)
				if not picker then
					return true
				end

				local num_history = #history.history
				if num_history == 0 then
					return true
				end

				local current_index = vim.b[prompt_bufnr].history_index
				local next_index

				if current_index == -1 then
					next_index = num_history - 1
				else
					next_index = current_index - 1
				end

				if next_index < 0 then
					next_index = num_history - 1
				end

				vim.b[prompt_bufnr].history_index = next_index
				local entry = history.history[next_index + 1]
				if entry then
					picker:set_prompt(entry)
					picker:refresh()
				end
				return true
			else
				return false
			end
		end)

		return true
	end

	return grep_history_attach_mappings
end

function M.setup(user_opts)
	user_opts = user_opts or {}
	M.config = vim.tbl_deep_extend("force", M.config, user_opts)

	history.setup({ history_limit = M.config.history_limit })

	if M.config.history_scope == "project" then
		local group = vim.api.nvim_create_augroup("TelescopeGrepHistoryProjectSwitch", { clear = true })
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			pattern = "*",
			desc = "Load project grep history on startup",
			callback = function()
				M.update_active_history()
			end,
		})
		vim.api.nvim_create_autocmd("DirChanged", {
			group = group,
			pattern = "*",
			desc = "Update project grep history on directory change",
			callback = function(args)
				M.update_active_history()
			end,
		})
	end

	M.update_active_history()

	local attach_mappings_func = create_attach_mappings()

	return {
		attach_mappings = attach_mappings_func,
		update_active_history = M.update_active_history,
	}
end

return M
