-- lua/haunt/persistence.lua
-- Updated to support project-relative paths for cross-machine syncing

---@class PersistenceModule
---@field set_data_dir fun(dir: string|nil)
---@field ensure_data_dir fun(): string|nil, string|nil
---@field get_git_info fun(): {root: string|nil, branch: string|nil}
---@field get_storage_path fun(): string|nil, string|nil
---@field save_bookmarks fun(bookmarks: Bookmark[], filepath?: string): boolean
---@field load_bookmarks fun(filepath?: string): Bookmark[]|nil
---@field create_bookmark fun(file: string, line: number, note?: string): Bookmark|nil, string|nil
---@field is_valid_bookmark fun(bookmark: table): boolean

---@private
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

-- Format version for storage
local CURRENT_FORMAT_VERSION = 2

--- Gets the git root directory for the current working directory
---@return string|nil git_root The git repository root path, or nil if not in a git repo
local function get_git_root()
	local result = vim.fn.systemlist("git rev-parse --show-toplevel")
	local exit_code = vim.v.shell_error

	if exit_code == 0 and result[1] then
		return result[1]
	end

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
	local result = vim.fn.systemlist("git branch --show-current")
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		return nil
	end

	local branch = result[1]
	if not branch or branch == "" then
		return nil
	end
	return branch
end

--- Set custom data directory
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

--- Ensures the haunt data directory exists
---@return string data_dir The haunt data directory path
function M.ensure_data_dir()
	local config = require("haunt.config")
	local data_dir = custom_data_dir or config.DEFAULT_DATA_DIR
	vim.fn.mkdir(data_dir, "p")
	return data_dir
end

--- Get git repository information for the current working directory
---@return { root: string|nil, branch: string|nil }
function M.get_git_info()
	local now = vim.uv.hrtime() / 1e6

	if _git_info_cache and (now - _cache_time) < CACHE_TTL then
		return _git_info_cache
	end

	local result = {
		root = get_git_root(),
		branch = get_git_branch(),
	}

	_git_info_cache = result
	_cache_time = now

	return result
end

--- Generates a storage path for the current git repository and branch
---@return string path The full path to the storage file
function M.get_storage_path()
	local repo_root = get_git_root() or vim.fn.getcwd()
	local branch = get_git_branch() or "__default__"
	local key = repo_root .. "|" .. branch
	local hash = vim.fn.sha256(key):sub(1, 12)
	local data_dir = M.ensure_data_dir()
	return data_dir .. hash .. ".json"
end

--- Detect project root for current context
---@return string|nil root_dir
---@return string method
local function detect_project_root()
	local root_module = require("haunt.root")
	local bufnr = vim.api.nvim_get_current_buf()
	return root_module.detect(bufnr)
end

--- Convert bookmarks to storage format (v2)
---@param bookmarks Bookmark[]
---@param project_root string|nil
---@return table storage_data
local function bookmarks_to_storage_v2(bookmarks, project_root)
	local paths = require("haunt.paths")
	local config = require("haunt.config").get()

	local stored_bookmarks = {}

	for _, bookmark in ipairs(bookmarks) do
		local stored = {
			line = bookmark.line,
			note = bookmark.note,
			id = bookmark.id,
		}

		-- Store relative path if possible
		if config.storage.use_relative_paths and project_root then
			stored.file = paths.to_relative(bookmark.file, project_root)
		else
			stored.file = bookmark.file
		end

		-- Store backup absolute path (normalized with ~)
		if config.storage.store_backup_paths then
			stored.file_absolute = paths.normalize_home(bookmark.file)
		end

		table.insert(stored_bookmarks, stored)
	end

	return {
		format_version = CURRENT_FORMAT_VERSION,
		project = project_root and {
			root = paths.normalize_home(project_root),
			root_absolute = project_root,
		} or vim.NIL,
		bookmarks = stored_bookmarks,
		metadata = {
			created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			haunt_version = "0.5.0", -- TODO: Get from plugin version
		},
	}
end

--- Migrate v1 format to v2
---@param v1_data table
---@return table v2_data
local function migrate_v1_to_v2(v1_data)
	local project_root, detection_method = detect_project_root()
	local paths = require("haunt.paths")

	local bookmarks = v1_data.bookmarks or {}
	local migrated_bookmarks = {}

	for _, bookmark in ipairs(bookmarks) do
		local migrated = {
			line = bookmark.line,
			note = bookmark.note,
			id = bookmark.id,
		}

		-- Convert to relative path if in project
		if project_root then
			migrated.file = paths.to_relative(bookmark.file, project_root)
		else
			migrated.file = bookmark.file
		end

		-- Store backup
		migrated.file_absolute = paths.normalize_home(bookmark.file)

		table.insert(migrated_bookmarks, migrated)
	end

	return {
		format_version = CURRENT_FORMAT_VERSION,
		project = project_root and {
			root = paths.normalize_home(project_root),
			root_absolute = project_root,
			detection_method = detection_method,
		} or vim.NIL,
		bookmarks = migrated_bookmarks,
		metadata = {
			created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			haunt_version = "0.5.0",
			migrated_from = "v1",
		},
	}
end

--- Convert storage format back to bookmarks
---@param storage_data table
---@param project_root string|nil
---@return Bookmark[]
local function storage_to_bookmarks(storage_data, project_root)
	local paths = require("haunt.paths")
	local bookmarks = {}

	for _, stored in ipairs(storage_data.bookmarks or {}) do
		local file_path = nil

		-- Try relative path first (if we have a project root)
		if stored.file and project_root then
			file_path = paths.to_absolute(stored.file, project_root)

			-- Check if file exists
			if not paths.file_exists(file_path) then
				file_path = nil
			end
		end

		-- Fall back to absolute path
		if not file_path and stored.file_absolute then
			file_path = paths.expand_home(stored.file_absolute)

			if not paths.file_exists(file_path) then
				-- File doesn't exist - skip with warning
				vim.notify(
					string.format("haunt.nvim: File not found, skipping bookmark: %s", stored.file_absolute or stored.file),
					vim.log.levels.WARN
				)
				goto continue
			end
		end

		-- If we still don't have a valid path, try the stored file as-is
		if not file_path and stored.file then
			file_path = paths.expand_home(stored.file)
			if not paths.file_exists(file_path) then
				goto continue
			end
		end

		if file_path then
			table.insert(bookmarks, {
				file = file_path,
				line = stored.line,
				note = stored.note,
				id = stored.id,
				extmark_id = nil,
			})
		end

		::continue::
	end

	return bookmarks
end

--- Save bookmarks to JSON file
---@param bookmarks table Array of bookmark tables to save
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return boolean success True if save was successful, false otherwise
function M.save_bookmarks(bookmarks, filepath)
	if type(bookmarks) ~= "table" then
		vim.notify("haunt.nvim: save_bookmarks: bookmarks must be a table", vim.log.levels.ERROR)
		return false
	end

	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		vim.notify("haunt.nvim: save_bookmarks: could not determine storage path", vim.log.levels.ERROR)
		return false
	end

	M.ensure_data_dir()

	-- Detect project root
	local project_root, _ = detect_project_root()

	-- Convert to storage format
	local data = bookmarks_to_storage_v2(bookmarks, project_root)

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
	local storage_path = filepath or M.get_storage_path()
	if not storage_path then
		vim.notify("haunt.nvim: load_bookmarks: could not determine storage path", vim.log.levels.WARN)
		return {}
	end

	if vim.fn.filereadable(storage_path) == 0 then
		return {}
	end

	local ok, lines = pcall(vim.fn.readfile, storage_path)
	if not ok then
		vim.notify("haunt.nvim: load_bookmarks: failed to read file: " .. storage_path, vim.log.levels.ERROR)
		return {}
	end

	local json_str = table.concat(lines, "\n")

	local decode_ok, data = pcall(vim.json.decode, json_str)
	if not decode_ok then
		vim.notify("haunt.nvim: load_bookmarks: JSON decoding failed: " .. tostring(data), vim.log.levels.ERROR)
		return {}
	end

	if type(data) ~= "table" then
		vim.notify("haunt.nvim: load_bookmarks: invalid data structure (not a table)", vim.log.levels.ERROR)
		return {}
	end

	-- Handle version migration
	local version = data.format_version or data.version or 1

	if version == 1 then
		-- Migrate v1 to v2
		vim.notify("haunt.nvim: Migrating bookmarks from v1 to v2 format...", vim.log.levels.INFO)
		data = migrate_v1_to_v2(data)

		-- Save migrated data
		local backup_path = storage_path .. ".v1.backup"
		vim.fn.writefile({ json_str }, backup_path)
		vim.notify("haunt.nvim: Old format backed up to: " .. backup_path, vim.log.levels.INFO)

		-- Save new format
		M.save_bookmarks(storage_to_bookmarks(data, data.project and data.project.root_absolute or nil), filepath)
	elseif version ~= CURRENT_FORMAT_VERSION then
		vim.notify("haunt.nvim: Unsupported format version: " .. tostring(version), vim.log.levels.ERROR)
		return {}
	end

	-- Get current project root for path resolution
	local project_root, _ = detect_project_root()

	-- Use stored project root if available, otherwise use detected
	if data.project and data.project.root_absolute then
		project_root = data.project.root_absolute
	end

	return storage_to_bookmarks(data, project_root)
end

--- Generate a unique bookmark ID
---@param file string Absolute path to the file
---@param line number 1-based line number
---@return string id A 16-character unique identifier
local function generate_bookmark_id(file, line)
	local timestamp = tostring(vim.uv.hrtime())
	local id_key = file .. tostring(line) .. timestamp
	return vim.fn.sha256(id_key):sub(1, 16)
end

--- Create a new bookmark. Does NOT save it!
---@param file string Absolute path to the file
---@param line number 1-based line number
---@param note? string Optional annotation text
---@return Bookmark|nil bookmark A new bookmark table, or nil if validation fails
---@return string|nil error_msg Error message if validation fails
function M.create_bookmark(file, line, note)
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
		extmark_id = nil,
	}
end

--- Validate a bookmark structure
---@param bookmark any The value to validate
---@return boolean valid True if the bookmark structure is valid
function M.is_valid_bookmark(bookmark)
	if type(bookmark) ~= "table" then
		return false
	end

	if type(bookmark.file) ~= "string" or bookmark.file == "" then
		return false
	end

	if type(bookmark.line) ~= "number" or bookmark.line < 1 then
		return false
	end

	if type(bookmark.id) ~= "string" or bookmark.id == "" then
		return false
	end

	if bookmark.note ~= nil and type(bookmark.note) ~= "string" then
		return false
	end

	if bookmark.extmark_id ~= nil and type(bookmark.extmark_id) ~= "number" then
		return false
	end

	return true
end

return M
