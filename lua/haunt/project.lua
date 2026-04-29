---@toc_entry Project Module
---@tag haunt-project
---@tag Project
---@text
--- # Project Module ~
---
--- Centralizes project identification (git root, branch, stable project id).
--- Used to support storing bookmark paths relative to project root and keying
--- storage files by stable project identifiers across forks/clones.

--- Project information returned by `get_info()`.
---@class ProjectInfo
---@field root string|nil Absolute path to project root (git toplevel) or nil
---@field branch string|nil Current branch name, short commit (detached HEAD), or nil
---@field project_id string Stable project identifier (root commit hash, repo path, or cwd)

---@class ProjectModule
---@field get_info fun(): ProjectInfo
---@field invalidate fun()
---@field setup_autocmds fun()

---@private
---@type ProjectModule
---@diagnostic disable-next-line: missing-fields
local M = {}

---@type ProjectInfo|nil
local _info_cache = nil
---@type number
local _cache_time = 0
---@type string|nil
local _cache_cwd = nil
local CACHE_TTL_MS = 5 * 1000

---@type boolean
local _git_warning_shown = false

--- Run a git command and return the result lines.
--- Handles "git not installed" (exit 127) gracefully with a one-time debug notify.
---@param cmd string The git command to run
---@return string[]|nil lines Output lines on success (exit 0), or nil otherwise
local function run_git(cmd)
	local result = vim.fn.systemlist(cmd)
	local exit_code = vim.v.shell_error

	if exit_code == 127 and not _git_warning_shown then
		_git_warning_shown = true
		vim.notify(
			"haunt.nvim: git command not found. Project identification will fall back to working directory.",
			vim.log.levels.DEBUG
		)
	end

	if exit_code == 0 then
		return result
	end

	return nil
end

---@return string|nil root
local function get_root()
	local result = run_git("git rev-parse --show-toplevel")
	if result and result[1] and result[1] ~= "" then
		return result[1]
	end
	return nil
end

---@return string|nil branch
local function get_branch()
	local result = run_git("git branch --show-current")
	if not result then
		return nil
	end

	local branch = result[1]
	if branch and branch ~= "" then
		return branch
	end

	-- Detached HEAD (e.g. tag checkout): identify by short commit hash instead
	local hash_result = run_git("git rev-parse --short HEAD")
	if hash_result and hash_result[1] and hash_result[1] ~= "" then
		return hash_result[1]
	end

	return nil
end

---@param root string|nil
---@return string project_id
local function project_id_with_root(root)
	local result = run_git("git rev-list --max-parents=0 HEAD")
	if result and result[1] and result[1] ~= "" then
		return result[1]
	end

	if root and root ~= "" then
		return root
	end

	return vim.fn.getcwd()
end

--- Get project info as a table, cached with a 5-second TTL.
--- The cache is also invalidated on `DirChanged`, `FocusGained`, and
--- `VimResume` (see `setup_autocmds`), so the TTL is just a backstop for
--- cases those events don't cover.
---@return ProjectInfo info Project info: {root, branch, project_id}
function M.get_info()
	local now = vim.uv.hrtime() / 1e6
	local cwd = vim.fn.getcwd()
	if _info_cache and _cache_cwd == cwd and (now - _cache_time) < CACHE_TTL_MS then
		return _info_cache
	end

	local root = get_root()
	local info = {
		root = root,
		branch = get_branch(),
		project_id = project_id_with_root(root),
	}

	_info_cache = info
	_cache_time = now
	_cache_cwd = cwd

	return info
end

--- Drop the cached project info so the next call to `get_info` re-resolves.
--- Called from autocmds that signal the cwd, focus, or shell state may have
--- changed (see `setup_autocmds`); also exposed so callers performing an
--- operation that intentionally invalidates project state (e.g. switching
--- data dirs) can opt in.
function M.invalidate()
	_info_cache = nil
	_cache_time = 0
	_cache_cwd = nil
end

--- Register autocmds that invalidate the project info cache when the user
--- could plausibly have changed cwd, branch, or git state:
---   - `DirChanged`: `:cd`, `:lcd`, `:tcd` from inside Neovim.
---   - `FocusGained`: alt-tabbed to an external terminal/git tool and back.
---   - `VimResume`: Ctrl+Z to a shell, did something, then `fg`'d back.
---
--- Idempotent — safe to call multiple times (clears the augroup first).
function M.setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("haunt_project_cache", { clear = true })
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "VimResume" }, {
		group = augroup,
		callback = function()
			M.invalidate()
		end,
		desc = "Invalidate haunt project cache when cwd/branch may have changed",
	})
end

--- Test-only seam: pre-populate the project info cache so tests can run
--- without a real git repository. Production code must not call this; use
--- the `tests/helpers/project_mock` module from tests instead.
---@private
---@param info ProjectInfo
function M._test_set_info(info)
	_info_cache = info
	_cache_time = vim.uv.hrtime() / 1e6
	_cache_cwd = vim.fn.getcwd()
end

return M
