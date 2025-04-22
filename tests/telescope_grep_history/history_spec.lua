-- tests/telescope_grep_history/history_spec.lua
-- Tests for history.lua based on source code analysis (NO HELPERS/MOCKS)
-- WARNING: Interacts with the real filesystem in vim.fn.stdpath('data')

-- Helper: Read file content, return lines in file order (handles nil path)
local function read_history_file_raw(path)
	local lines = {}
	if not path then
		return lines
	end
	local file = io.open(path, "r")
	if not file then
		return lines -- File doesn't exist
	end
	for line in file:lines() do
		-- History module skips empty lines on load, but we might want to see them for debugging
		-- Let's keep them for raw read, but expect history module won't load them.
		table.insert(lines, line)
	end
	file:close()
	return lines
end

-- Helper: Write lines to file in the format history.lua expects (newest first)
-- Creates necessary directories.
local function write_history_file_for_test(path, lines_oldest_first)
	if not path or not lines_oldest_first then
		return false
	end

	-- Ensure directory exists (mimics history.lua's write_file)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.filereadable(dir) == 1 and vim.fn.isdirectory(dir) == 0 then
		print("TEST ERROR: Cannot create dir, file exists:", dir)
		return false
	end
	if vim.fn.isdirectory(dir) == 0 then
		pcall(vim.fn.mkdir, dir, "p")
		if vim.fn.isdirectory(dir) == 0 then
			print("TEST ERROR: Failed to create dir:", dir)
			return false
		end
	end

	local file = io.open(path, "w")
	if not file then
		print("TEST ERROR: Failed to open file for writing:", path)
		return false
	end
	-- Write newest first (last element of input table)
	for i = #lines_oldest_first, 1, -1 do
		file:write(lines_oldest_first[i] .. "\n")
	end
	file:close()
	return true
end

describe("History Module (Real FileSystem Interaction)", function()
	local history_module
	local test_dir = vim.fn.stdpath("data") .. "/__test_telescope_grep_history__"
	local test_file_name_1 = "history_spec_test_file_1.txt"
	local test_file_name_2 = "history_spec_test_file_2.txt"
	local test_file_path_1 = test_dir .. "/" .. test_file_name_1
	local test_file_path_2 = test_dir .. "/" .. test_file_name_2
	local history_limit = 3 -- Use a small limit for easier testing

	before_each(function()
		-- Clean up potential leftovers BEFORE loading module
		os.remove(test_file_path_1)
		os.remove(test_file_path_2)
		-- Remove dir if empty (best effort cleanup)
		pcall(vim.fn.delete, test_dir, "rf") -- Use delete() which handles dirs

		-- Ensure the module is loaded fresh for the test
		package.loaded["telescope_grep_history.history"] = nil
		history_module = require("telescope_grep_history.history")

		-- Configure the module
		history_module.setup({ history_limit = history_limit })
		-- Set initial active file (will load if it exists, shouldn't here)
		history_module.update_active_history_file(test_file_path_1)

		-- Explicitly reset in-memory history *after* setup/update_active_history_file
		-- because update calls load_history_from
		history_module.history = {}
		-- Ensure active file is correctly set for subsequent adds if update didn't run load
		history_module.active_history_file = test_file_path_1
	end)

	after_each(function()
		-- Attempt cleanup
		os.remove(test_file_path_1)
		os.remove(test_file_path_2)
		pcall(vim.fn.delete, test_dir, "rf") -- Use delete()

		-- Clear module state
		if history_module then
			history_module.history = {}
			history_module.active_history_file = nil
		end
		package.loaded["telescope_grep_history.history"] = nil
	end)

	-----------------------------------------------------
	-- Basic Add & State Tests
	-----------------------------------------------------
	it("should add a single entry to in-memory history", function()
		local entry = "entry_1"
		history_module.add_entry(entry)
		assert.are.same({ entry }, history_module.history)
	end)

	it("should trim whitespace from added entries", function()
		local entry = "  entry_with_spaces  "
		history_module.add_entry(entry)
		assert.are.same({ vim.trim(entry) }, history_module.history)
	end)

	it("should ignore adding empty or whitespace-only entries", function()
		history_module.add_entry("   ")
		assert.are.equal(0, #history_module.history)
		history_module.add_entry("")
		assert.are.equal(0, #history_module.history)
	end)

	-----------------------------------------------------
	-- Duplicate Handling Tests
	-----------------------------------------------------
	it("should remove existing duplicate and add new one to the end", function()
		history_module.add_entry("entry_A")
		history_module.add_entry("entry_B")
		history_module.add_entry("entry_C") -- History: {A, B, C} (Limit 3)
		assert.are.same({ "entry_A", "entry_B", "entry_C" }, history_module.history)

		-- Re-add B
		history_module.add_entry("entry_B") -- Expected: {A, C, B}
		assert.are.same({ "entry_A", "entry_C", "entry_B" }, history_module.history)
	end)

	it("should handle duplicates case-sensitively", function()
		history_module.add_entry("entry_a")
		history_module.add_entry("Entry_A") -- Different entry
		assert.are.same({ "entry_a", "Entry_A" }, history_module.history)
		history_module.add_entry("entry_a") -- Re-add lowercase
		assert.are.same({ "Entry_A", "entry_a" }, history_module.history)
	end)

	-----------------------------------------------------
	-- History Limit Tests
	-----------------------------------------------------
	it("should enforce history limit on add_entry (removing oldest)", function()
		history_module.add_entry("entry_1")
		history_module.add_entry("entry_2")
		history_module.add_entry("entry_3") -- History: {1, 2, 3} (Limit 3)
		assert.are.same({ "entry_1", "entry_2", "entry_3" }, history_module.history)

		history_module.add_entry("entry_4") -- History should become: {2, 3, 4}
		assert.are.same({ "entry_2", "entry_3", "entry_4" }, history_module.history)

		history_module.add_entry("entry_5") -- History should become: {3, 4, 5}
		assert.are.same({ "entry_3", "entry_4", "entry_5" }, history_module.history)
	end)

	it("should enforce history limit correctly when adding duplicates past the limit", function()
		history_module.add_entry("entry_1")
		history_module.add_entry("entry_2")
		history_module.add_entry("entry_3") -- History: {1, 2, 3}

		history_module.add_entry("entry_1") -- History: {2, 3, 1}
		assert.are.same({ "entry_2", "entry_3", "entry_1" }, history_module.history)

		history_module.add_entry("entry_4") -- History: {3, 1, 4}
		assert.are.same({ "entry_3", "entry_1", "entry_4" }, history_module.history)
	end)

	-----------------------------------------------------
	-- File I/O Tests (Save & Load)
	-----------------------------------------------------
	it("should save history to file correctly (newest first)", function()
		history_module.add_entry("line_C") -- Newest
		history_module.add_entry("line_B")
		history_module.add_entry("line_A") -- Oldest (Limit 3, state is {C, B, A})

		-- Read file content directly
		local file_lines = read_history_file_raw(test_file_path_1)

		-- File should have newest first
		assert.are.same({ "line_A", "line_B", "line_C" }, file_lines)
	end)

	it("should load history from file correctly (reversing to oldest first in memory)", function()
		-- Prepare a test file with newest entry first
		local setup_ok = write_history_file_for_test(test_file_path_1, { "load_C", "load_B", "load_A" }) -- Oldest first in this table means newest first in file
		assert.is_true(setup_ok, "Failed to write test file for load test")

		-- Clear memory and load
		history_module.history = {}
		history_module.load_history_from(test_file_path_1)

		-- Memory should have oldest first
		assert.are.same({ "load_C", "load_B", "load_A" }, history_module.history)
	end)

	it("should apply history limit when loading from file", function()
		-- Prepare a test file with more entries than the limit (newest first)
		local setup_ok =
			write_history_file_for_test(test_file_path_1, { "load_1", "load_2", "load_3", "load_4", "load_5" }) -- 5 entries, limit is 3
		assert.is_true(setup_ok, "Failed to write test file for load limit test")

		history_module.load_history_from(test_file_path_1)

		-- Memory should contain only the newest 'limit' entries, in oldest-first order
		assert.are.same({ "load_3", "load_4", "load_5" }, history_module.history)
	end)

	it("should handle loading from a non-existent file (empty history)", function()
		-- Ensure file doesn't exist (done in before_each, but double check)
		os.remove(test_file_path_1)

		history_module.load_history_from(test_file_path_1)
		assert.are.equal(0, #history_module.history)
		assert.are.same({}, history_module.history)
	end)

	it("should handle loading when path is nil (empty history)", function()
		-- Add something to memory first
		history_module.add_entry("should_be_cleared")
		assert.are.equal(1, #history_module.history)

		history_module.load_history_from(nil)
		assert.are.equal(0, #history_module.history)
		assert.are.same({}, history_module.history)
	end)

	-----------------------------------------------------
	-- Active File Switching Tests
	-----------------------------------------------------
	it("should load new history when active file path changes via update_active_history_file", function()
		-- 1. Setup initial state in file 1
		history_module.add_entry("file1_entryA")
		history_module.add_entry("file1_entryB")
		assert.are.same({ "file1_entryA", "file1_entryB" }, history_module.history, "Initial state check")

		-- 2. Setup different state in file 2
		local setup_ok = write_history_file_for_test(test_file_path_2, { "file2_X", "file2_Y" }) -- Oldest first in table -> Newest first in file
		assert.is_true(setup_ok, "Failed to write test file 2")

		-- 3. Switch active file to file 2
		history_module.update_active_history_file(test_file_path_2)

		-- 4. Verify memory now reflects file 2's content (oldest first)
		assert.are.same({ "file2_X", "file2_Y" }, history_module.history, "State after switching to file 2")
		assert.are.equal(test_file_path_2, history_module.active_history_file, "Active file path after switch")

		-- 5. Add an entry - it should go to file 2
		history_module.add_entry("file2_Z") -- Memory: {X, Y, Z} (Limit 3)
		local file2_lines = read_history_file_raw(test_file_path_2)
		assert.are.same({ "file2_Z", "file2_Y", "file2_X" }, file2_lines, "File 2 content after adding entry") -- Newest first in file

		-- 6. Switch back to file 1
		history_module.update_active_history_file(test_file_path_1)
		assert.are.same(
			{ "file1_entryA", "file1_entryB" },
			history_module.history,
			"State after switching back to file 1"
		)
		assert.are.equal(test_file_path_1, history_module.active_history_file, "Active file path after switching back")
	end)

	it("should not reload history if update_active_history_file is called with the same path", function()
		-- 1. Add initial entry
		history_module.add_entry("initial_entry")
		assert.are.same({ "initial_entry" }, history_module.history)

		-- 2. Write something different to the file externally (simulate external change)
		local setup_ok = write_history_file_for_test(test_file_path_1, { "external_change" })
		assert.is_true(setup_ok, "Failed to write external change file")

		-- 3. Call update with the *same* path
		history_module.update_active_history_file(test_file_path_1)

		-- 4. Verify memory has NOT changed (load was skipped)
		assert.are.same({ "initial_entry" }, history_module.history)
		assert.are.equal(test_file_path_1, history_module.active_history_file)
	end)

	-----------------------------------------------------
	-- Filesystem Error Handling Tests
	-----------------------------------------------------
	describe("Filesystem Error Handling", function()
		it("should handle error when history directory is a file", function()
			-- Path where the history directory *should* be created by write_file
			local history_dir_path = vim.fn.fnamemodify(test_file_path_1, ":h")
			-- Path of the history file itself (needed later)
			local history_file_path = test_file_path_1

			-- Ensure containing directory exists, but target is clean
			pcall(vim.fn.delete, history_dir_path, "rf")
			vim.fn.mkdir(vim.fn.fnamemodify(history_dir_path, ":h"), "p")

			-- Create a FILE where the directory should go
			local file = io.open(history_dir_path, "w")
			assert.is_truthy(file, "Failed to create dummy file at directory path")
			if file then
				file:write("I am a file, not a directory!\n")
				file:close()
			end
			assert.is_true(vim.fn.filereadable(history_dir_path) == 1, "Dummy file not readable")
			assert.is_true(vim.fn.isdirectory(history_dir_path) == 0, "Dummy path is incorrectly a directory")

			-- Try adding an entry, which triggers save_history -> write_file
			-- We expect write_file to detect the error and return early.
			-- Use pcall to catch potential errors, though the function aims not to error out.
			local ok, err = pcall(history_module.add_entry, "test_entry_fails_save")

			-- Assertions:
			-- 1. The operation should not have crashed Neovim (pcall returned ok=true)
			assert.is_true(ok, "add_entry call failed unexpectedly: " .. tostring(err))
			-- 2. The dummy file should still exist and be a file
			assert.is_true(vim.fn.filereadable(history_dir_path) == 1, "Dummy file was deleted")
			assert.is_true(vim.fn.isdirectory(history_dir_path) == 0, "Dummy path was turned into a directory")
			-- 3. The *intended* history file should NOT have been created inside/over the dummy file
			assert.is_false(
				vim.fn.filereadable(history_file_path) == 1,
				"History file was created despite directory being a file"
			)
			-- 4. Optional: Check Neovim messages for the expected error notification (difficult to assert directly)
		end)
	end)
end)
