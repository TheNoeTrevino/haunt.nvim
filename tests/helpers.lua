--- Shared test helpers for haunt.nvim test suite
---@class TestHelpers
local M = {}

--- Create a test buffer with optional content
---@param lines? string[] Lines to populate the buffer with
---@param filename? string Optional custom filename (defaults to tempname())
---@return number bufnr The buffer number
---@return string test_file The file path
function M.create_test_buffer(lines, filename)
	local bufnr = vim.api.nvim_create_buf(false, false)
	local test_file = filename or (vim.fn.tempname() .. ".lua")
	vim.api.nvim_buf_set_name(bufnr, test_file)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "Line 1", "Line 2", "Line 3" })
	vim.api.nvim_set_current_buf(bufnr)
	return bufnr, test_file
end

--- Cleanup a test buffer and its associated file
---@param bufnr? number The buffer number to delete
---@param test_file? string The file path to delete
function M.cleanup_buffer(bufnr, test_file)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
	if test_file then
		vim.fn.delete(test_file)
	end
end

--- Reset all haunt modules for clean test state
--- Call this in before_each to ensure isolation between tests
function M.reset_modules()
	package.loaded["haunt"] = nil
	package.loaded["haunt.api"] = nil
	package.loaded["haunt.display"] = nil
	package.loaded["haunt.persistence"] = nil
	package.loaded["haunt.config"] = nil
	package.loaded["haunt.store"] = nil
	package.loaded["haunt.utils"] = nil
	package.loaded["haunt.navigation"] = nil
	package.loaded["haunt.restoration"] = nil
	package.loaded["haunt.picker"] = nil
	package.loaded["haunt.picker.init"] = nil
	package.loaded["haunt.picker.utils"] = nil
	package.loaded["haunt.picker.snacks"] = nil
	package.loaded["haunt.picker.telescope"] = nil
	package.loaded["haunt.picker.fzf"] = nil
	package.loaded["haunt.picker.fallback"] = nil
	package.loaded["haunt.sidekick"] = nil
end

--- Setup haunt for testing with default config
--- Returns commonly used modules
---@return table modules Table with api, store, display, config, etc.
function M.setup_haunt()
	M.reset_modules()
	local haunt = require("haunt")
	haunt.setup()
	local api = require("haunt.api")
	api._reset_for_testing()

	return {
		haunt = haunt,
		api = api,
		store = require("haunt.store"),
		display = require("haunt.display"),
		config = require("haunt.config"),
		utils = require("haunt.utils"),
		navigation = require("haunt.navigation"),
		restoration = require("haunt.restoration"),
		persistence = require("haunt.persistence"),
	}
end

--- Create a mock display module for isolated testing
---@return table mock_display Mock display module with tracking
function M.create_mock_display()
	local mock = {
		calls = {},
		namespace = 1000,
		next_extmark_id = 1,
	}

	function mock.get_namespace()
		return mock.namespace
	end

	function mock.setup_signs()
		table.insert(mock.calls, { fn = "setup_signs" })
	end

	function mock.show_annotation(bufnr, line, note)
		local id = mock.next_extmark_id
		mock.next_extmark_id = mock.next_extmark_id + 1
		table.insert(mock.calls, { fn = "show_annotation", args = { bufnr, line, note }, returned = id })
		return id
	end

	function mock.hide_annotation(bufnr, extmark_id)
		table.insert(mock.calls, { fn = "hide_annotation", args = { bufnr, extmark_id } })
		return true
	end

	function mock.set_bookmark_mark(bufnr, bookmark)
		local id = mock.next_extmark_id
		mock.next_extmark_id = mock.next_extmark_id + 1
		table.insert(mock.calls, { fn = "set_bookmark_mark", args = { bufnr, bookmark }, returned = id })
		return id
	end

	function mock.get_extmark_line(bufnr, extmark_id)
		table.insert(mock.calls, { fn = "get_extmark_line", args = { bufnr, extmark_id } })
		return nil -- Default to nil, tests can override
	end

	function mock.delete_bookmark_mark(bufnr, extmark_id)
		table.insert(mock.calls, { fn = "delete_bookmark_mark", args = { bufnr, extmark_id } })
		return true
	end

	function mock.place_sign(bufnr, line, sign_id)
		table.insert(mock.calls, { fn = "place_sign", args = { bufnr, line, sign_id } })
	end

	function mock.unplace_sign(bufnr, sign_id)
		table.insert(mock.calls, { fn = "unplace_sign", args = { bufnr, sign_id } })
	end

	function mock.clear_buffer_marks(bufnr)
		table.insert(mock.calls, { fn = "clear_buffer_marks", args = { bufnr } })
		return true
	end

	function mock.get_config()
		return require("haunt.config").get()
	end

	function mock.is_initialized()
		return true
	end

	--- Helper to check if a function was called
	function mock.was_called(fn_name)
		for _, call in ipairs(mock.calls) do
			if call.fn == fn_name then
				return true
			end
		end
		return false
	end

	--- Helper to get all calls to a function
	function mock.get_calls(fn_name)
		local result = {}
		for _, call in ipairs(mock.calls) do
			if call.fn == fn_name then
				table.insert(result, call)
			end
		end
		return result
	end

	--- Reset call tracking
	function mock.reset()
		mock.calls = {}
		mock.next_extmark_id = 1
	end

	return mock
end

--- Create a mock persistence module for isolated testing
---@return table mock_persistence Mock persistence module with tracking
function M.create_mock_persistence()
	local mock = {
		calls = {},
		saved_bookmarks = nil,
		bookmarks_to_load = {},
		next_id = 1,
	}

	function mock.create_bookmark(file, line, note)
		local id = "mock_" .. mock.next_id
		mock.next_id = mock.next_id + 1
		local bookmark = {
			file = file,
			line = line,
			note = note,
			id = id,
		}
		table.insert(mock.calls, { fn = "create_bookmark", args = { file, line, note }, returned = bookmark })
		return bookmark
	end

	function mock.save_bookmarks(bookmarks, filepath)
		mock.saved_bookmarks = vim.deepcopy(bookmarks)
		table.insert(mock.calls, { fn = "save_bookmarks", args = { bookmarks, filepath } })
		return true
	end

	function mock.load_bookmarks(filepath)
		table.insert(mock.calls, { fn = "load_bookmarks", args = { filepath } })
		return vim.deepcopy(mock.bookmarks_to_load)
	end

	function mock.is_valid_bookmark(bookmark)
		return type(bookmark) == "table"
			and type(bookmark.file) == "string"
			and bookmark.file ~= ""
			and type(bookmark.line) == "number"
			and bookmark.line >= 1
			and type(bookmark.id) == "string"
			and bookmark.id ~= ""
	end

	function mock.get_storage_path()
		return "/tmp/mock_haunt_storage.json"
	end

	function mock.ensure_data_dir()
		return "/tmp/mock_haunt/"
	end

	function mock.get_git_info()
		return { root = "/mock/repo", branch = "main" }
	end

	function mock.set_data_dir() end

	--- Helper to check if a function was called
	function mock.was_called(fn_name)
		for _, call in ipairs(mock.calls) do
			if call.fn == fn_name then
				return true
			end
		end
		return false
	end

	--- Helper to get all calls to a function
	function mock.get_calls(fn_name)
		local result = {}
		for _, call in ipairs(mock.calls) do
			if call.fn == fn_name then
				table.insert(result, call)
			end
		end
		return result
	end

	--- Reset call tracking
	function mock.reset()
		mock.calls = {}
		mock.saved_bookmarks = nil
		mock.next_id = 1
	end

	return mock
end

--- Check if clipboard is available (for skipping clipboard tests in CI)
---@return boolean available Whether clipboard provider is available
function M.has_clipboard()
	local ok = pcall(vim.fn.setreg, "+", "clipboard_test")
	if not ok then
		return false
	end
	local result = vim.fn.getreg("+")
	return result == "clipboard_test"
end

--- Count extmarks with virtual text in a buffer (for testing annotation duplicates)
---@param bufnr number Buffer number
---@param namespace number Namespace ID
---@return number count Number of extmarks with virtual text
function M.count_annotation_extmarks(bufnr, namespace)
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
	local count = 0
	for _, extmark in ipairs(extmarks) do
		local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, extmark[1], { details = true })
		if details and details[3] and details[3].virt_text then
			count = count + 1
		end
	end
	return count
end

function M.is_quickfix_open()
	for _, w in ipairs(vim.fn.getwininfo()) do
		if w.quickfix == 1 then
			return true
		end
	end
	return false
end

--- Create a temporary directory for testing data_dir changes
---@return string dir_path Path to the temporary directory (with trailing slash)
function M.create_temp_data_dir()
	local dir = vim.fn.tempname() .. "_haunt_test/"
	vim.fn.mkdir(dir, "p")
	return dir
end

--- Clean up a temporary directory
---@param dir_path string Path to remove
function M.cleanup_temp_dir(dir_path)
	if dir_path and vim.fn.isdirectory(dir_path) == 1 then
		vim.fn.delete(dir_path, "rf")
	end
end

--- Create a bookmarks JSON file in a data directory
--- This simulates pre-existing bookmarks for testing change_data_dir
---@param data_dir string The data directory path
---@param bookmarks table[] Array of bookmark tables
---@param storage_hash? string Optional hash for filename (defaults to a test hash)
---@return string filepath The path to the created JSON file
function M.create_bookmarks_file(data_dir, bookmarks, storage_hash)
	local hash = storage_hash or "test12345678"
	local filepath = data_dir .. hash .. ".json"
	local data = {
		version = 1,
		bookmarks = bookmarks,
	}
	local json_str = vim.json.encode(data)
	vim.fn.writefile({ json_str }, filepath)
	return filepath
end

--- Read bookmarks from a JSON file in a data directory
---@param filepath string Path to the JSON file
---@return table|nil data The parsed JSON data, or nil if file doesn't exist
function M.read_bookmarks_file(filepath)
	if vim.fn.filereadable(filepath) == 0 then
		return nil
	end
	local lines = vim.fn.readfile(filepath)
	local json_str = table.concat(lines, "\n")
	local ok, data = pcall(vim.json.decode, json_str)
	if ok then
		return data
	end
	return nil
end

return M
