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
---@field file string Absolute path while in memory; serialized as relative to project root unless `absolute=true`
---@field line number 1-based line number of the bookmark
---@field note string|nil Optional annotation text displayed as virtual text
---@field id string Unique bookmark identifier (auto-generated)
---@field absolute? boolean Whether file is stored as absolute path (out-of-project)
---@field extmark_id number|nil Extmark ID for line tracking (internal)
---@field annotation_extmark_id number|nil Extmark ID for annotation display (internal)

---@class PersistenceModule
---@field set_data_dir fun(dir: string|nil)
---@field ensure_data_dir fun(): string|nil, string|nil
---@field get_git_info fun(): {root: string|nil, branch: string|nil}
---@field get_storage_path fun(): string
---@field _get_v1_storage_path fun(repo_root: string, branch: string|nil, per_branch: boolean|nil): string
---@field save_bookmarks fun(bookmarks: Bookmark[], filepath?: string, project_root?: string|nil): boolean
---@field load_bookmarks fun(filepath?: string): Bookmark[]|nil
---@field create_bookmark fun(file: string, line: number, note?: string): Bookmark|nil, string|nil
---@field is_valid_bookmark fun(bookmark: table): boolean
---@field _build_serializable fun(bookmarks: Bookmark[], project_root?: string|nil): table[]

---@private
---@type PersistenceModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local STORAGE_VERSION = 2
local DEFAULT_BRANCH_KEY = "__default__"

---@private
---@type string|nil
local custom_data_dir = nil

--- Get git repository information for the current working directory.
--- Thin shim over haunt.project for backward compatibility with consumers
--- (and the test suite) that referenced this on persistence.
---@return { root: string|nil, branch: string|nil }
function M.get_git_info()
	local info = require("haunt.project").get_info()
	return { root = info.root, branch = info.branch }
end

--- Set custom data directory
--- Expands ~ to home directory and ensures trailing slash
---@param dir string|nil Custom data directory path, or nil to reset to default
function M.set_data_dir(dir)
	if dir == nil then
		custom_data_dir = nil
		return
	end

	local expanded = vim.fn.expand(dir)

	if expanded:sub(-1) ~= "/" then
		expanded = expanded .. "/"
	end

	custom_data_dir = expanded
end

---@return string data_dir The haunt data directory path
local function get_data_dir()
	local config = require("haunt.config")
	return custom_data_dir or config.DEFAULT_DATA_DIR
end

--- Ensures the haunt data directory exists
---@return string data_dir The haunt data directory path
function M.ensure_data_dir()
	local data_dir = get_data_dir()
	vim.fn.mkdir(data_dir, "p")
	return data_dir
end

---@param key string Pre-built keying string to hash into the filename
---@return string path
local function path_for_key(key)
	return get_data_dir() .. vim.fn.sha256(key):sub(1, 12) .. ".json"
end

--- Generates a storage path for the current project and branch.
--- Uses a 12-character SHA256 hash of "project_id|branch" (or just "project_id"
--- when per_branch_bookmarks is disabled). project_id is a stable identifier
--- (root commit hash, repo path, or cwd) supplied by haunt.project, so
--- forks/clones of the same project produce the same storage file.
---@return string path The full path to the storage file
function M.get_storage_path()
	local config = require("haunt.config").get()
	local info = require("haunt.project").get_info()

	local key = info.project_id
	if config.per_branch_bookmarks then
		key = key .. "|" .. (info.branch or DEFAULT_BRANCH_KEY)
	end

	return path_for_key(key)
end

--- Compute the legacy v1 storage path for a project keyed by repo path.
--- Exposed for haunt.migration; not part of the stable public API.
---@param repo_root string Absolute path to the git repository root
---@param branch string|nil Current branch (nil falls back to the default-branch key)
---@param per_branch boolean|nil Whether per-branch bookmarks are enabled (truthy means yes)
---@return string path
function M._get_v1_storage_path(repo_root, branch, per_branch)
	local key = repo_root
	if per_branch then
		key = key .. "|" .. (branch or DEFAULT_BRANCH_KEY)
	end
	return path_for_key(key)
end

--- Build a serializable copy of bookmarks for v2 storage.
--- - In-project bookmarks are stored relative to the project root.
--- - Bookmarks flagged `absolute=true`, or whose file lies outside the project,
---   are stored as absolute paths with `absolute=true`.
--- - Runtime-only fields (extmark IDs) are stripped.
---@param bookmarks Bookmark[] In-memory bookmarks list
---@param project_root string|nil Project root; defaults to the cached project info
---@return table[] serializable Transformed bookmarks ready to be JSON-encoded
function M._build_serializable(bookmarks, project_root)
	local utils = require("haunt.utils")
	if project_root == nil then
		project_root = require("haunt.project").get_info().root
	end
	local result = {}

	for i, bookmark in ipairs(bookmarks) do
		local entry = {
			file = bookmark.file,
			line = bookmark.line,
			note = bookmark.note,
			id = bookmark.id,
		}

		local relative = nil
		if project_root and not bookmark.absolute then
			relative = utils.to_relative(bookmark.file, project_root)
		end

		if relative then
			entry.file = relative
		else
			entry.absolute = true
		end

		result[i] = entry
	end

	return result
end

--- Build the JSON payload + storage path for a save operation.
--- Shared by sync and async save paths.
---@param bookmarks table
---@param filepath? string
---@param project_root? string|nil Override project root for serialization (callers
--- with a stamped origin pass it here so the save reflects the project the
--- bookmarks belong to, not whatever the cache currently resolves to).
---@return {storage_path: string, json_str: string}|nil payload
---@return string|nil err
local function build_save_payload(bookmarks, filepath, project_root)
	if type(bookmarks) ~= "table" then
		return nil, "bookmarks must be a table"
	end

	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		return nil, "could not determine storage path"
	end

	M.ensure_data_dir()

	local data = {
		version = STORAGE_VERSION,
		bookmarks = M._build_serializable(bookmarks, project_root),
	}

	local ok, json_str = pcall(vim.json.encode, data)
	if not ok then
		return nil, "JSON encoding failed: " .. tostring(json_str)
	end

	return { storage_path = storage_path, json_str = json_str }, nil
end

--- Save bookmarks to JSON file
---@param bookmarks table Array of bookmark tables to save
---@param filepath? string Optional custom file path (defaults to git-based path)
---@param project_root? string|nil Optional project root for serialization
---@return boolean success True if save was successful, false otherwise
function M.save_bookmarks(bookmarks, filepath, project_root)
	if type(bookmarks) == "table" and #bookmarks == 0 then
		local storage_path = filepath or M.get_storage_path()
		if storage_path then
			vim.fn.delete(storage_path)
		end
		return true
	end

	local payload, err = build_save_payload(bookmarks, filepath, project_root)
	if not payload then
		vim.notify("haunt.nvim: save_bookmarks: " .. err, vim.log.levels.ERROR)
		return false
	end

	-- vim.fn.writefile returns -1 on I/O failure (full disk, perms, missing
	-- parent dir) rather than throwing, so check both the pcall result and
	-- the return value.
	local write_ok, write_ret = pcall(vim.fn.writefile, { payload.json_str }, payload.storage_path)
	if not write_ok or write_ret == -1 then
		vim.notify("haunt.nvim: save_bookmarks: failed to write file: " .. payload.storage_path, vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Resolve v2 bookmarks: turn project-relative paths back into absolute paths.
--- - bookmark.absolute == true: file is already absolute, pass through unchanged.
--- - otherwise: resolve relative to the current project root.
---   When no project root is available (not in a git repo), emit a single warning
---   and leave bookmark.file as the stored relative string. The bookmark won't
---   resolve to a real file but the load will not crash.
---@param bookmarks table[] Raw bookmarks read from disk (v2 shape)
---@return table[] resolved Bookmarks with absolute file paths in memory
local function resolve_v2_bookmarks(bookmarks)
	local utils = require("haunt.utils")
	local project_root = require("haunt.project").get_info().root
	local warned_no_root = false

	for _, bookmark in ipairs(bookmarks) do
		if bookmark.absolute == true then
			goto continue
		end

		if not project_root then
			if not warned_no_root then
				warned_no_root = true
				vim.notify("haunt.nvim: cannot resolve relative paths — not in a git repo", vim.log.levels.WARN)
			end
			goto continue
		end

		bookmark.file = utils.to_absolute(bookmark.file, project_root)

		::continue::
	end

	return bookmarks
end

--- Load bookmarks from JSON file.
---
--- Returns:
---   - An array of bookmarks on a successful load.
---   - `{}` when the storage file does not exist (a fresh user is a
---     successful load with zero bookmarks).
---   - `nil` on any actual load failure: storage path unresolvable,
---     read/parse error, missing/unsupported version, v1 file detected,
---     invalid structure. Each failure path emits its own notify.
---
--- Callers (store.load) use the nil return to distinguish "load failed —
--- leave the in-memory store untouched and suppress on_load" from
--- "loaded, nothing to do."
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return Bookmark[]|nil bookmarks Array on success/empty, nil on failure
function M.load_bookmarks(filepath)
	-- Close the race with a scheduled auto_migrate from setup(): any reader
	-- blocks here until migration has run for this session.
	require("haunt.migration").ensure_done()

	-- Get storage path
	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		vim.notify("haunt.nvim: load_bookmarks: could not determine storage path", vim.log.levels.WARN)
		return nil
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
		return nil
	end

	-- Join lines into single string
	local json_str = table.concat(lines, "\n")

	-- Decode JSON
	local decode_ok, data = pcall(vim.json.decode, json_str)
	if not decode_ok then
		vim.notify("haunt.nvim: load_bookmarks: JSON decoding failed: " .. tostring(data), vim.log.levels.ERROR)
		return nil
	end

	-- Validate structure
	if type(data) ~= "table" then
		vim.notify("haunt.nvim: load_bookmarks: invalid data structure (not a table)", vim.log.levels.ERROR)
		return nil
	end

	-- Validate version field
	if not data.version then
		vim.notify("haunt.nvim: load_bookmarks: missing version field", vim.log.levels.WARN)
		return nil
	end

	if data.version == 1 then
		vim.notify(
			"haunt.nvim: v1 bookmark storage detected at "
				.. storage_path
				.. ". Auto-migration runs on setup — if it didn't, run :HauntMigrate.",
			vim.log.levels.WARN
		)
		return nil
	end

	if data.version == STORAGE_VERSION then
		if type(data.bookmarks) ~= "table" then
			vim.notify("haunt.nvim: load_bookmarks: invalid bookmarks field (not a table)", vim.log.levels.ERROR)
			return nil
		end
		return resolve_v2_bookmarks(data.bookmarks)
	end

	vim.notify("haunt.nvim: load_bookmarks: unsupported version: " .. tostring(data.version), vim.log.levels.ERROR)
	return nil
end

--- Generate a unique bookmark ID
--- @param file string Absolute path to the file
--- @param line number 1-based line number
--- @return string id A 16-character unique identifier
local function generate_bookmark_id(file, line)
	local timestamp = tostring(vim.uv.hrtime())
	local id_key = file .. tostring(line) .. timestamp
	return vim.fn.sha256(id_key):sub(1, 16)
end

--- Create a new bookmark. Does NOT save it!
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

	return {
		file = file,
		line = line,
		note = note,
		id = generate_bookmark_id(file, line),
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

	if bookmark.absolute ~= nil and type(bookmark.absolute) ~= "boolean" then
		return false
	end

	return true
end

return M
