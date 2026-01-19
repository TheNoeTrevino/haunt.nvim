---@toc_entry Bookmark Structure
---@tag haunt-bookmark
---@tag Bookmark
---@text
--- # Bookmark Structure ~
---
--- Bookmarks are stored as tables with the following fields:

--- Bookmark data structure.
---
--- Represents a single bookmark in haunt.nvim.
---
---@class Bookmark
---@field file string Absolute path to the bookmarked file
---@field line number 1-based line number of the bookmark
---@field note string|nil Optional annotation text displayed as virtual text
---@field id string Unique bookmark identifier (auto-generated)
---@field extmark_id number|nil Extmark ID for line tracking (internal)
---@field annotation_extmark_id number|nil Extmark ID for annotation display (internal)

---@class PersistenceModule
---@field set_data_dir fun(dir: string)
---@field ensure_data_dir fun(): string|nil, string|nil
---@field get_git_info fun(): {root: string|nil, branch: string|nil}
---@field get_storage_path fun(): string|nil, string|nil
---@field save_bookmarks fun(bookmarks: Bookmark[], filepath?: string): boolean
---@field load_bookmarks fun(filepath?: string): Bookmark[]|nil
---@field create_bookmark fun(file: string, line: number, note?: string): Bookmark|nil, string|nil
---@field is_valid_bookmark fun(bookmark: table): boolean

---@type PersistenceModule
---@diagnostic disable-next-line: missing-fields
local M = {}

---@private
---@type string|nil
local custom_data_dir = nil

-- Git info cache with TTL
---@type {root: string|nil, branch: string|nil}|nil
local _git_info_cache = nil
---@type number
local _cache_time = 0
---@type number
local CACHE_TTL = 5000 -- 5 seconds in milliseconds

-- Track if we've already warned about git not being available
---@type boolean
local _git_warning_shown = false

--- Gets the git root directory for the current working directory
---@return string|nil git_root The git repository root path, or nil if not in a git repo
local function get_git_root()
	local result = vim.fn.systemlist("git rev-parse --show-toplevel")
	local exit_code = vim.v.shell_error

	if exit_code == 0 and result[1] then
		return result[1]
	end

	-- Exit code 128 typically means "not a git repository" - this is expected
	-- Exit code 127 means "command not found" - git is not installed
	if exit_code == 127 and not _git_warning_shown then
		_git_warning_shown = true
		vim.notify(
			"haunt.nvim: git command not found. Bookmarks will be stored per working directory instead of per repository/branch.",
			vim.log.levels.DEBUG
		)
	end

	return nil
end

--- Gets the current git branch name
---@return string|nil branch The current git branch name, or nil if not in a git repo
local function get_git_branch()
	-- Use --show-current which returns empty string for detached HEAD and repos with no commits
	-- This is more appropriate than --abbrev-ref HEAD which returns "HEAD" for detached state
	local result = vim.fn.systemlist("git branch --show-current")
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		-- Don't warn here since get_git_root() already handles the "git not found" case
		return nil
	end

	local branch = result[1]
	-- Return nil for empty string (detached HEAD or no commits) or missing result
	if not branch or branch == "" then
		return nil
	end
	return branch
end

--- Set custom data directory
---@param dir string|nil Custom data directory path
function M.set_data_dir(dir)
	custom_data_dir = dir
end

--- Ensures the haunt data directory exists
---@return string data_dir The haunt data directory path
function M.ensure_data_dir()
	local config = require("haunt.config")
	local data_dir = custom_data_dir or config.DEFAULT_DATA_DIR
	vim.fn.mkdir(data_dir, "p")
	return data_dir
end

--- Get git repository information for the current working directory
--- Uses caching with 5-second TTL to avoid repeated system calls
--- @return { root: string|nil, branch: string|nil }
--- Returns a table with:
---   - root: absolute path to git repository root, or nil if not in a git repo
---   - branch: name of current branch, or nil if not in a git repo, detached HEAD, or no commits
function M.get_git_info()
	local now = vim.uv.hrtime() / 1e6 -- Convert to milliseconds

	-- Check if cache is valid
	if _git_info_cache and (now - _cache_time) < CACHE_TTL then
		return _git_info_cache
	end

	-- Cache miss or expired - fetch fresh data
	local result = {
		root = get_git_root(),
		branch = get_git_branch(),
	}

	-- Update cache
	_git_info_cache = result
	_cache_time = now

	return result
end

--- Generates a storage path for the current git repository and branch
--- Uses an 8-character SHA256 hash of "repo_root|branch" for the filename
--- Falls back to CWD and "__default__" branch when not in a git repository
---@return string path The full path to the storage file
function M.get_storage_path()
	-- Use git root if available, otherwise fall back to CWD
	local repo_root = get_git_root() or vim.fn.getcwd()

	-- Use git branch if available, otherwise fall back to "__default__"
	local branch = get_git_branch() or "__default__"

	-- Create hash key from repo_root and branch
	local key = repo_root .. "|" .. branch

	-- Generate 12-character hash using SHA256 (reduces collision risk)
	local hash = vim.fn.sha256(key):sub(1, 12)

	-- Ensure data directory exists
	local data_dir = M.ensure_data_dir()

	-- Return full path to storage file
	return data_dir .. hash .. ".json"
end

--- Save bookmarks to JSON file
---@param bookmarks table Array of bookmark tables to save
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return boolean success True if save was successful, false otherwise
function M.save_bookmarks(bookmarks, filepath)
	-- Validate input
	if type(bookmarks) ~= "table" then
		vim.notify("haunt.nvim: save_bookmarks: bookmarks must be a table", vim.log.levels.ERROR)
		return false
	end

	-- Get storage path
	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		vim.notify("haunt.nvim: save_bookmarks: could not determine storage path", vim.log.levels.ERROR)
		return false
	end

	-- Ensure storage directory exists
	M.ensure_data_dir()

	-- Create data structure with version
	local data = {
		version = 1,
		bookmarks = bookmarks,
	}

	-- Encode to JSON
	local ok, json_str = pcall(vim.json.encode, data)
	if not ok then
		vim.notify("haunt.nvim: save_bookmarks: JSON encoding failed: " .. tostring(json_str), vim.log.levels.ERROR)
		return false
	end

	-- Write to file
	local write_ok = pcall(vim.fn.writefile, { json_str }, storage_path)
	if not write_ok then
		vim.notify("haunt.nvim: save_bookmarks: failed to write file: " .. storage_path, vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Load bookmarks from JSON file
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return table bookmarks Array of bookmarks, or empty table if file doesn't exist or on error
function M.load_bookmarks(filepath)
	-- Get storage path
	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		vim.notify("haunt.nvim: load_bookmarks: could not determine storage path", vim.log.levels.WARN)
		return {}
	end

	-- Check if file exists
	if vim.fn.filereadable(storage_path) == 0 then
		-- File doesn't exist, return empty table (not an error)
		return {}
	end

	-- Read file
	local ok, lines = pcall(vim.fn.readfile, storage_path)
	if not ok then
		vim.notify("haunt.nvim: load_bookmarks: failed to read file: " .. storage_path, vim.log.levels.ERROR)
		return {}
	end

	-- Join lines into single string
	local json_str = table.concat(lines, "\n")

	-- Decode JSON
	local decode_ok, data = pcall(vim.json.decode, json_str)
	if not decode_ok then
		vim.notify("haunt.nvim: load_bookmarks: JSON decoding failed: " .. tostring(data), vim.log.levels.ERROR)
		return {}
	end

	-- Validate structure
	if type(data) ~= "table" then
		vim.notify("haunt.nvim: load_bookmarks: invalid data structure (not a table)", vim.log.levels.ERROR)
		return {}
	end

	-- Validate version field
	if not data.version then
		vim.notify("haunt.nvim: load_bookmarks: missing version field", vim.log.levels.WARN)
		return {}
	end

	-- Check version compatibility
	if data.version ~= 1 then
		vim.notify("haunt.nvim: load_bookmarks: unsupported version: " .. tostring(data.version), vim.log.levels.ERROR)
		return {}
	end

	-- Validate bookmarks field
	if type(data.bookmarks) ~= "table" then
		vim.notify("haunt.nvim: load_bookmarks: invalid bookmarks field (not a table)", vim.log.levels.ERROR)
		return {}
	end

	return data.bookmarks
end

--- Create a new bookmark
--- @param file string Absolute path to the file
--- @param line number 1-based line number
--- @param note? string Optional annotation text
--- @return Bookmark|nil bookmark A new bookmark table, or nil if validation fails
--- @return string|nil error_msg Error message if validation fails
function M.create_bookmark(file, line, note)
	-- Validate inputs
	if type(file) ~= "string" or file == "" then
		vim.notify("haunt.nvim: create_bookmark: file must be a non-empty string", vim.log.levels.ERROR)
		return nil, "file must be a non-empty string"
	end

	if type(line) ~= "number" or line < 1 then
		vim.notify("haunt.nvim: create_bookmark: line must be a positive number", vim.log.levels.ERROR)
		return nil, "line must be a positive number"
	end

	if note ~= nil and type(note) ~= "string" then
		vim.notify("haunt.nvim: create_bookmark: note must be nil or a string", vim.log.levels.ERROR)
		return nil, "note must be nil or a string"
	end

	-- Generate unique ID using SHA256 hash of file + line + timestamp
	local timestamp = tostring(vim.uv.hrtime())
	local id_key = file .. tostring(line) .. timestamp
	local id = vim.fn.sha256(id_key):sub(1, 16) -- 16 chars for uniqueness

	return {
		file = file,
		line = line,
		note = note,
		id = id,
		extmark_id = nil, -- Will be set by display layer
	}
end

--- Validate a bookmark structure
--- @param bookmark any The value to validate
--- @return boolean valid True if the bookmark structure is valid
function M.is_valid_bookmark(bookmark)
	-- Check that bookmark is a table
	if type(bookmark) ~= "table" then
		return false
	end

	-- required fields
	if type(bookmark.file) ~= "string" or bookmark.file == "" then
		return false
	end

	if type(bookmark.line) ~= "number" or bookmark.line < 1 then
		return false
	end

	if type(bookmark.id) ~= "string" or bookmark.id == "" then
		return false
	end

	-- optional fields (nil | right type)
	if bookmark.note ~= nil and type(bookmark.note) ~= "string" then
		return false
	end

	if bookmark.extmark_id ~= nil and type(bookmark.extmark_id) ~= "number" then
		return false
	end

	return true
end

return M
