---@toc_entry Migration Module
---@tag haunt-migration
---@tag Migration
---@text
--- # Migration Module ~
---
--- Provides migration from the v1 on-disk bookmark format (absolute paths,
--- repo-path-keyed filename) to the v2 format (project-relative paths,
--- root-commit-keyed filename).
---
--- The v2 format is now what `haunt.persistence` writes and reads. v1 files on
--- disk are left alone and refuse to load until migrated. `auto_migrate()`
--- runs once on startup and silently upgrades a single-state v1 file in place;
--- the `:HauntMigrate` command (see `migrate_current_project`) does the same
--- thing but emits info-level notifies on every gate so the user can debug a
--- non-event manually.

---@class MigrationModule
---@field migrate_current_project fun()
---@field auto_migrate fun()
---@field _reset_for_testing fun()

---@private
---@type MigrationModule
---@diagnostic disable-next-line: missing-fields
local M = {}

--- Session-scoped tracker for one-time ERROR notifications about projects that
--- have BOTH v1 and v2 storage files. Keyed by old_path; reset across sessions
--- and by `_reset_for_testing` so the "notify only once" behavior can be tested.
---@private
---@type table<string, boolean>
local _dual_state_notified = {}

local function dual_state_message(old_path, new_path, suffix)
	return string.format(
		"haunt.nvim: cannot migrate — both v1 (%s) and v2 (%s) storage files exist for this project. "
			.. "To resolve: back up %s if needed, delete it, then %s.",
		old_path,
		new_path,
		new_path,
		suffix
	)
end

--- Decode a JSON file.
---@param path string
---@return table|nil data Parsed table, or nil on error
---@return string|nil err Error message on failure
local function read_json_file(path)
	local read_ok, lines = pcall(vim.fn.readfile, path)
	if not read_ok then
		return nil, "failed to read file: " .. path
	end

	local json_str = table.concat(lines, "\n")
	local decode_ok, data = pcall(vim.json.decode, json_str)
	if not decode_ok then
		return nil, "JSON decode failed: " .. tostring(data)
	end

	if type(data) ~= "table" then
		return nil, "invalid data structure (not a table)"
	end

	return data, nil
end

--- Walk v1 bookmarks and produce the v2 transformed list.
--- Delegates to `persistence._build_serializable`; v1 bookmarks have no
--- `absolute` field, so every entry is tested against the project root.
---@param v1_bookmarks table[] Bookmarks from the v1 file
---@param project_root string Project root absolute path
---@return table[] transformed
---@return number relative_count
---@return number absolute_count
local function transform_bookmarks(v1_bookmarks, project_root)
	local persistence = require("haunt.persistence")
	local transformed = persistence._build_serializable(v1_bookmarks, project_root)

	local absolute_count = 0
	for _, entry in ipairs(transformed) do
		if entry.absolute then
			absolute_count = absolute_count + 1
		end
	end

	return transformed, #transformed - absolute_count, absolute_count
end

--- Resolve config + project info into the legacy and current storage paths.
---@return {info: ProjectInfo, old_path: string, new_path: string}|nil paths nil when not in a git repo
local function resolve_paths()
	local project = require("haunt.project")
	local persistence = require("haunt.persistence")
	local config = require("haunt.config").get()

	local info = project.get_info()
	if not info.root then
		return nil
	end

	local per_branch = config.per_branch_bookmarks
	local old_path = persistence._get_v1_storage_path(info.root, info.branch, per_branch)
	local new_path = persistence.get_storage_path()
	return { info = info, old_path = old_path, new_path = new_path }
end

--- Run the migration body: write v2, rename v1 to backup, notify, reload.
--- Caller has already validated that `data` is a v1 file with bookmarks.
---@param info ProjectInfo
---@param old_path string
---@param new_path string
---@param data table Parsed v1 file contents
local function do_migrate(info, old_path, new_path, data)
	local backup_path = old_path .. ".v1.bak"

	vim.notify(
		string.format("haunt.nvim: starting migration.\n Backup will be saved to %s if you need to roll back.", backup_path),
		vim.log.levels.INFO
	)

	---@cast info -nil
	local transformed, relative_count, absolute_count = transform_bookmarks(data.bookmarks, info.root)

	local v2_data = {
		version = 2,
		bookmarks = transformed,
	}

	local encode_ok, json_str = pcall(vim.json.encode, v2_data)
	if not encode_ok then
		vim.notify("haunt.nvim: JSON encoding failed: " .. tostring(json_str), vim.log.levels.ERROR)
		return
	end

	-- vim.fn.writefile returns -1 on failure rather than throwing, so check both.
	local write_ok, write_ret = pcall(vim.fn.writefile, { json_str }, new_path)
	if not write_ok or write_ret == -1 then
		vim.notify("haunt.nvim: failed to write v2 file at " .. new_path, vim.log.levels.ERROR)
		return
	end

	-- Rename v1 to .v1.bak rather than delete, so the user can roll back.
	-- If the rename fails we'd be left in a dual-state (v1 + v2 both present),
	-- which permanently locks future migrations. Delete the just-written v2 so
	-- the next attempt starts from the same single-state v1 the user had.
	local rename_ok, rename_result = pcall(vim.uv.fs_rename, old_path, backup_path)
	if not rename_ok or not rename_result then
		pcall(vim.uv.fs_unlink, new_path)
		vim.notify(
			"haunt.nvim: migration aborted — failed to rename v1 file to "
				.. backup_path
				.. ". v1 file preserved; resolve the filesystem issue and re-run :HauntMigrate.",
			vim.log.levels.ERROR
		)
		return
	end

	local total = relative_count + absolute_count
	vim.notify(
		string.format(
			"haunt.nvim: migration successful\n%d bookmarks (%d relative, %d absolute). Backup at %s.",
			total,
			relative_count,
			absolute_count,
			backup_path
		),
		vim.log.levels.INFO
	)

	require("haunt.api").reload()
end

--- Migrate the current project's v1 bookmark file to v2.
---
--- Notifies on every gate failure (no git repo, no v1 file, version mismatch,
--- dual-state); intended invocation is the user-facing `:HauntMigrate`.
function M.migrate_current_project()
	local paths = resolve_paths()
	if not paths then
		vim.notify("haunt.nvim: not in a git repo, cannot migrate", vim.log.levels.WARN)
		return
	end

	local info, old_path, new_path = paths.info, paths.old_path, paths.new_path

	if old_path == new_path then
		vim.notify("haunt.nvim: nothing to migrate (storage path unchanged)", vim.log.levels.INFO)
		return
	end

	if vim.fn.filereadable(old_path) ~= 1 then
		vim.notify("haunt.nvim: no v1 file found to migrate at " .. old_path, vim.log.levels.INFO)
		return
	end

	local data, err = read_json_file(old_path)
	if not data then
		vim.notify("haunt.nvim: failed to parse v1 file at " .. old_path .. ": " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	if data.version ~= 1 then
		vim.notify(
			"haunt.nvim: refusing to migrate file at " .. old_path .. ": expected version=1, got " .. tostring(data.version),
			vim.log.levels.ERROR
		)
		return
	end

	if type(data.bookmarks) ~= "table" then
		vim.notify(
			"haunt.nvim: refusing to migrate file at " .. old_path .. ": missing or invalid bookmarks field",
			vim.log.levels.ERROR
		)
		return
	end

	if vim.fn.filereadable(new_path) == 1 then
		vim.notify(dual_state_message(old_path, new_path, "re-run"), vim.log.levels.ERROR)
		return
	end

	do_migrate(info, old_path, new_path, data)
end

--- Auto-migrate on startup. Silent on every non-issue; emits an idempotent
--- ERROR notify only when both v1 and v2 storage files exist for the project.
function M.auto_migrate()
	local paths = resolve_paths()
	if not paths then
		return
	end

	local info, old_path, new_path = paths.info, paths.old_path, paths.new_path

	if old_path == new_path then
		return
	end

	if vim.fn.filereadable(old_path) ~= 1 then
		return
	end

	local data = read_json_file(old_path)
	if not data or data.version ~= 1 or type(data.bookmarks) ~= "table" then
		return
	end

	if vim.fn.filereadable(new_path) == 1 then
		if not _dual_state_notified[old_path] then
			_dual_state_notified[old_path] = true
			vim.notify(dual_state_message(old_path, new_path, "restart Neovim"), vim.log.levels.ERROR)
		end
		return
	end

	do_migrate(info, old_path, new_path, data)
end

--- Reset session-scoped state for tests.
---@private
function M._reset_for_testing()
	_dual_state_notified = {}
end

return M
