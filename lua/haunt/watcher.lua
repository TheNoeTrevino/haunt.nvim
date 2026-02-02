---@toc_entry Watcher Module
---@tag haunt-watcher
---@text
--- # Watcher Module ~
---
--- Watches the project's `<gitdir>/HEAD` for changes (e.g. branch
--- checkouts) and triggers `api.reload()` automatically when the storage
--- path the project resolves to no longer matches the path stamped onto
--- the in-memory store.
---
--- The primary backend is libuv `fs_event` (kernel-level: inotify on
--- Linux, FSEvents on macOS, ReadDirectoryChangesW on Windows). fs_event
--- watches the gitdir as a directory and the callback filters for HEAD.
--- If fs_event fails to start (rare; some sandboxed/networked filesystems
--- don't support it), we fall back to a periodic `fs_poll` on the HEAD
--- file directly so the feature still works.
---
--- Mid-rebase, HEAD bounces through detached SHAs and back; the watcher
--- skips reloads while a rebase is in progress so we don't briefly load
--- bookmarks for the transient detached state.

---@class WatcherModule
---@field start fun(): boolean
---@field stop fun()
---@field restart fun(): boolean
---@field _check_and_reload fun()

local uv = vim.uv

---@private
---@type WatcherModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local DEBOUNCE_MS = 200
local FS_POLL_INTERVAL_MS = 1000

---@private
---@type uv.uv_fs_event_t|uv.uv_fs_poll_t|nil
local _handle = nil
---@private
---@type uv.uv_timer_t|nil
local _debounce = nil
---@private
---@type string|nil
local _watched_target = nil
---@private
---@type string|nil
local _watched_gitdir = nil

local function close_handle()
	if _handle and not _handle:is_closing() then
		_handle:stop()
		_handle:close()
	end
	_handle = nil
	_watched_target = nil
end

local function close_debounce()
	if _debounce and not _debounce:is_closing() then
		_debounce:stop()
		_debounce:close()
	end
	_debounce = nil
end

---@return string|nil gitdir Absolute path to the gitdir, or nil if not in a git repo
local function get_absolute_gitdir()
	local result = require("haunt.project").run_git("git rev-parse --absolute-git-dir")
	if not result or not result[1] or result[1] == "" then
		return nil
	end
	return result[1]
end

---@param gitdir string
---@return boolean
local function is_rebase_in_progress(gitdir)
	return uv.fs_stat(gitdir .. "/rebase-merge") ~= nil or uv.fs_stat(gitdir .. "/rebase-apply") ~= nil
end

--- Watcher callbacks fire on libuv's thread; `vim.schedule_wrap` lifts work
--- back onto the main loop where touching nvim state is safe. The debounce
--- timer coalesces the burst of writes git emits during a single checkout.
local function schedule_check()
	close_debounce()
	_debounce = uv.new_timer()
	if not _debounce then
		return
	end
	_debounce:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			close_debounce()
			M._check_and_reload()
		end)
	)
end

--- Recompute the project's expected storage path; if it differs from the
--- in-memory store's stamped path, save+reload. Skips reload mid-rebase
--- since HEAD bounces through detached states transiently.
---@private
function M._check_and_reload()
	if _watched_gitdir == nil then
		return
	end
	if is_rebase_in_progress(_watched_gitdir) then
		return
	end

	local store = require("haunt.store")
	local persistence = require("haunt.persistence")
	local project = require("haunt.project")
	local hooks = require("haunt.hooks")

	local stamped_path = store.get_loaded_storage_path()
	if stamped_path == nil then
		return
	end

	project.invalidate()
	local current_path = persistence.get_storage_path()

	if current_path == stamped_path then
		return
	end

	if store.has_bookmarks() then
		store.save()
	end

	hooks.emit_branch_change({
		gitdir = _watched_gitdir,
		old_storage_path = stamped_path,
		new_storage_path = current_path,
	})

	-- api.reload() restarts this watcher itself, so the gitdir/HEAD target
	-- gets re-resolved if a worktree switch happened to land here too.
	require("haunt.api").reload("branch_change")
end

--- fs_event delivers a filename for each change in the watched directory.
--- We only care about HEAD; ignore the noisy churn from index, packed-refs,
--- pack files, and `index.lock`. A nil filename (some platforms / event
--- coalescing) is treated as "unknown — trust the event" since the
--- subsequent `_check_and_reload` is idempotent on no-op branch state.
---@param filename string|nil
---@return boolean
local function should_notify(filename)
	if filename == nil or filename == "" then
		return true
	end
	return filename == "HEAD"
end

--- Common binding logic for both backends: pcall the start, handle errors,
--- close on failure, stash module state on success.
---@param handle uv.uv_fs_event_t|uv.uv_fs_poll_t|nil
---@param backend_name string Used in the failure-path debug notification
---@param target string Path the handle is bound to
---@param starter fun(handle: any) Calls `handle:start(...)` with backend-specific args
---@return boolean started
local function bind_handle(handle, backend_name, target, starter)
	if not handle then
		return false
	end

	local ok, err = pcall(starter, handle)
	if not ok then
		if not handle:is_closing() then
			handle:close()
		end
		vim.notify("haunt.nvim: " .. backend_name .. " start failed: " .. tostring(err), vim.log.levels.DEBUG)
		return false
	end

	_handle = handle
	_watched_target = target
	return true
end

---@param gitdir string
---@return boolean started
local function start_fs_event(gitdir)
	return bind_handle(uv.new_fs_event(), "fs_event", gitdir, function(handle)
		handle:start(gitdir, {}, function(err, filename)
			if err or not should_notify(filename) then
				return
			end
			schedule_check()
		end)
	end)
end

---@param head_path string
---@return boolean started
local function start_fs_poll(head_path)
	return bind_handle(uv.new_fs_poll(), "fs_poll", head_path, function(handle)
		handle:start(head_path, FS_POLL_INTERVAL_MS, function(err)
			if err then
				return
			end
			schedule_check()
		end)
	end)
end

--- Start watching the project's HEAD. No-op outside a git repo.
--- Idempotent — if already watching the right gitdir, returns true without
--- rebinding.
---@return boolean started True if the watcher is running after this call
function M.start()
	local gitdir = get_absolute_gitdir()
	if not gitdir then
		M.stop()
		return false
	end

	local head_path = gitdir .. "/HEAD"
	if vim.fn.filereadable(head_path) == 0 then
		M.stop()
		return false
	end

	-- Short-circuit: already watching this gitdir (fs_event) or its HEAD
	-- (fs_poll fallback). Either is correct for the same repo.
	if _handle and (_watched_target == gitdir or _watched_target == head_path) then
		_watched_gitdir = gitdir
		return true
	end

	close_handle()

	if start_fs_event(gitdir) then
		_watched_gitdir = gitdir
		return true
	end

	if start_fs_poll(head_path) then
		_watched_gitdir = gitdir
		return true
	end

	return false
end

--- Stop the watcher and release any handles. Safe to call repeatedly.
function M.stop()
	close_debounce()
	close_handle()
	_watched_gitdir = nil
end

--- Stop the current watcher (if any) and re-resolve gitdir, then start.
--- Use after a cross-project `:cd` or worktree switch that may have
--- changed the gitdir we should be watching.
---@return boolean started
function M.restart()
	M.stop()
	return M.start()
end

return M
