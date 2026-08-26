---@toc_entry Watcher Module
---@tag haunt-watcher
---@text
--- # Watcher Module ~
---
--- Runs two independent filesystem watches:
---
--- 1. The project's `<gitdir>/HEAD`, for branch checkouts. When the storage
---    path the project resolves to no longer matches the path stamped onto
---    the in-memory store, `api.reload()` is triggered.
--- 2. The data directory holding the bookmark storage file, for writes made
---    by anything other than this Neovim instance (the `haunt` CLI, an agent,
---    a dotfile sync). External writes trigger `api.reload("external_write")`
---    so the on-disk state wins instead of being silently overwritten by the
---    next `store.save()`.
---
--- The primary backend is libuv `fs_event` (kernel-level: inotify on
--- Linux, FSEvents on macOS, ReadDirectoryChangesW on Windows). Both
--- watches bind to a *directory* and filter events by filename — the
--- storage file in particular is deleted whenever the bookmark list empties
--- (see `persistence.save_bookmarks`), so there is frequently no file to
--- bind to. If fs_event fails to start (rare; some sandboxed/networked
--- filesystems don't support it), we fall back to a periodic `fs_poll` on
--- the file directly so the feature still works.
---
--- Mid-rebase, HEAD bounces through detached SHAs and back; the watcher
--- skips reloads while a rebase is in progress so we don't briefly load
--- bookmarks for the transient detached state.

---@class WatcherModule
---@field start fun(): boolean
---@field stop fun()
---@field restart fun(): boolean
---@field mark_synced fun(path?: string)
---@field _check_and_reload fun()
---@field _check_storage_and_reload fun()

local uv = vim.uv

---@private
---@type WatcherModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local DEBOUNCE_MS = 200
local FS_POLL_INTERVAL_MS = 1000

--- A single filesystem watch: its handle, what that handle is bound to, and
--- its own debounce timer. Each watch debounces independently — sharing one
--- timer would let a HEAD event cancel a pending storage check.
---@class WatchSlot
---@field handle uv.uv_fs_event_t|uv.uv_fs_poll_t|nil
---@field target string|nil
---@field debounce uv.uv_timer_t|nil

---@private
---@type WatchSlot
local _head = { handle = nil, target = nil, debounce = nil }

---@private
---@type WatchSlot
local _storage = { handle = nil, target = nil, debounce = nil }

---@private
---@type string|nil
local _watched_gitdir = nil

--- Stat of the storage file as of the last time this Neovim instance and the
--- file were known to agree — set after our own saves and after every reload.
--- `nil` means "no known state" (never synced, or the file was absent).
---@private
---@type {mtime_sec: number, mtime_nsec: number, size: number}|nil
local _synced_stamp = nil

---@param slot WatchSlot
local function close_slot_handle(slot)
	if slot.handle and not slot.handle:is_closing() then
		slot.handle:stop()
		slot.handle:close()
	end
	slot.handle = nil
	slot.target = nil
end

---@param slot WatchSlot
local function close_slot_debounce(slot)
	if slot.debounce and not slot.debounce:is_closing() then
		slot.debounce:stop()
		slot.debounce:close()
	end
	slot.debounce = nil
end

--- Watcher callbacks fire on libuv's thread; `vim.schedule_wrap` lifts work
--- back onto the main loop where touching nvim state is safe. The debounce
--- timer coalesces the burst of writes a single logical change emits (git
--- checkout touches HEAD repeatedly; a JSON rewrite is truncate-then-write).
---@param slot WatchSlot
---@param check fun()
local function schedule_check(slot, check)
	close_slot_debounce(slot)
	slot.debounce = uv.new_timer()
	if not slot.debounce then
		return
	end
	slot.debounce:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			close_slot_debounce(slot)
			check()
		end)
	)
end

--- Common binding logic for both backends: pcall the start, handle errors,
--- close on failure, stash slot state on success.
---@param slot WatchSlot
---@param handle uv.uv_fs_event_t|uv.uv_fs_poll_t|nil
---@param backend_name string Used in the failure-path debug notification
---@param target string Path the handle is bound to
---@param starter fun(handle: any) Calls `handle:start(...)` with backend-specific args
---@return boolean started
local function bind_handle(slot, handle, backend_name, target, starter)
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

	slot.handle = handle
	slot.target = target
	return true
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

--- Stat a path down to the fields we compare for change detection.
---@param path string
---@return {mtime_sec: number, mtime_nsec: number, size: number}|nil stamp nil if the path does not exist
local function stat_stamp(path)
	local st = uv.fs_stat(path)
	if not st then
		return nil
	end
	return {
		mtime_sec = st.mtime.sec,
		mtime_nsec = st.mtime.nsec,
		size = st.size,
	}
end

--- Record the storage file's current state as "in sync with this instance".
---
--- Called after our own writes (`store.save`), after loads, and after any
--- reload this watcher performs. Everything the storage watch does hangs off
--- this stamp: without it, every save we make would echo back as an event and
--- trigger a pointless reload (clearing and re-restoring every extmark).
---@param path? string Storage path to stamp; defaults to the store's stamped path
function M.mark_synced(path)
	path = path or require("haunt.store").get_loaded_storage_path()
	if not path then
		_synced_stamp = nil
		return
	end
	_synced_stamp = stat_stamp(path)
end

--- Decide whether the storage file differs from the state this instance last
--- synced with — i.e. whether somebody else wrote (or deleted) it.
---
--- `current` is the file's stat right now (nil when the file does not exist);
--- `synced` is the stamp recorded by `mark_synced` (nil when this instance has
--- no known state for it). Returning true triggers a full reload: every
--- extmark in every loaded buffer is cleared and restored from disk.
---@param current {mtime_sec: number, mtime_nsec: number, size: number}|nil
---@param synced {mtime_sec: number, mtime_nsec: number, size: number}|nil
---@return boolean changed True if the file was written by something other than us
local function is_externally_changed(current, synced)
	-- No file and no record: nothing to reload onto. This is the steady state
	-- after our own `clear_all` (save deletes the file, mark_synced stamps nil),
	-- so it must not fire.
	if current == nil and synced == nil then
		return false
	end

	-- The file vanished out from under a state we were tracking, or appeared
	-- where we had none. The latter is the CLI's first write into a project
	-- we'd emptied — the single most important case to catch.
	if current == nil or synced == nil then
		return true
	end

	if current.size ~= synced.size then
		return true
	end

	if current.mtime_sec ~= synced.mtime_sec then
		return true
	end

	-- Sub-second precision is a bonus, not a guarantee: some filesystems (and
	-- notably some Docker volume drivers, which the CLI's contract tests will
	-- run on) report mtime at second granularity and leave nsec at 0. Only
	-- trust the field when both sides actually populated it — comparing a real
	-- nsec against a zeroed one would reload on every single save.
	if current.mtime_nsec ~= 0 and synced.mtime_nsec ~= 0 then
		return current.mtime_nsec ~= synced.mtime_nsec
	end

	return false
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

--- Reload when the storage file was written by someone other than us.
---
--- Deliberately does NOT save first: an external write means the on-disk
--- state is the newer one, and `store.save()` would overwrite it with our
--- in-memory array — the exact clobber this watch exists to prevent.
---@private
function M._check_storage_and_reload()
	local store = require("haunt.store")

	local stamped_path = store.get_loaded_storage_path()
	if stamped_path == nil then
		return
	end

	if not is_externally_changed(stat_stamp(stamped_path), _synced_stamp) then
		return
	end

	require("haunt.api").reload("external_write")

	-- Re-stamp against what we just loaded, so the echo of this same write
	-- (fs_event often reports a write more than once) doesn't reload again.
	M.mark_synced()
end

--- fs_event delivers a filename for each change in the watched directory.
--- A nil filename (some platforms / event coalescing) is treated as
--- "unknown — trust the event" since the subsequent check is idempotent.
---@param filename string|nil
---@param wanted string The basename we care about
---@return boolean
local function should_notify(filename, wanted)
	if filename == nil or filename == "" then
		return true
	end
	return filename == wanted
end

---@param gitdir string
---@return boolean started
local function start_head_fs_event(gitdir)
	return bind_handle(_head, uv.new_fs_event(), "fs_event", gitdir, function(handle)
		handle:start(gitdir, {}, function(err, filename)
			-- Ignore the noisy churn from index, packed-refs, pack files,
			-- and index.lock; only HEAD signals a checkout.
			if err or not should_notify(filename, "HEAD") then
				return
			end
			schedule_check(_head, M._check_and_reload)
		end)
	end)
end

---@param head_path string
---@return boolean started
local function start_head_fs_poll(head_path)
	return bind_handle(_head, uv.new_fs_poll(), "fs_poll", head_path, function(handle)
		handle:start(head_path, FS_POLL_INTERVAL_MS, function(err)
			if err then
				return
			end
			schedule_check(_head, M._check_and_reload)
		end)
	end)
end

---@param data_dir string
---@return boolean started
local function start_storage_fs_event(data_dir)
	return bind_handle(_storage, uv.new_fs_event(), "fs_event", data_dir, function(handle)
		handle:start(data_dir, {}, function(err, filename)
			if err then
				return
			end
			-- Resolved per-event, not per-bind: the stamped path follows
			-- branch switches, and reading it is free (no git shell-out).
			local stamped = require("haunt.store").get_loaded_storage_path()
			if stamped and not should_notify(filename, vim.fs.basename(stamped)) then
				return
			end
			schedule_check(_storage, M._check_storage_and_reload)
		end)
	end)
end

---@param storage_path string
---@return boolean started
local function start_storage_fs_poll(storage_path)
	return bind_handle(_storage, uv.new_fs_poll(), "fs_poll", storage_path, function(handle)
		handle:start(storage_path, FS_POLL_INTERVAL_MS, function()
			-- Unlike fs_event, an error here is meaningful: fs_poll reports
			-- ENOENT for a missing file, and a deleted storage file is
			-- exactly the "emptied by the CLI" case we must react to.
			schedule_check(_storage, M._check_storage_and_reload)
		end)
	end)
end

--- Start watching the data directory for external writes to the storage file.
--- Unlike the HEAD watch this works outside a git repo, since `project_id`
--- falls back to the cwd and bookmarks still have a storage file.
---@return boolean started
local function start_storage_watch()
	local persistence = require("haunt.persistence")
	local data_dir = persistence.ensure_data_dir()
	if not data_dir then
		return false
	end

	if _storage.handle and _storage.target == data_dir then
		return true
	end

	close_slot_handle(_storage)

	if start_storage_fs_event(data_dir) then
		return true
	end

	local stamped = require("haunt.store").get_loaded_storage_path()
	if stamped then
		return start_storage_fs_poll(stamped)
	end

	return false
end

--- Start watching the project's HEAD and the bookmark storage file.
--- The HEAD watch is a no-op outside a git repo; the storage watch is not.
--- Idempotent — if already watching the right targets, returns without
--- rebinding.
---@return boolean started True if the HEAD watch is running after this call
function M.start()
	-- `api.reload()` calls `restart()`, so anything that throws in here would
	-- take a reload down with it. A watch is an optimization — losing it
	-- degrades to "reload manually", which is survivable; losing the reload
	-- is not.
	local storage_ok, storage_err = pcall(start_storage_watch)
	if not storage_ok then
		vim.notify("haunt.nvim: storage watch failed to start: " .. tostring(storage_err), vim.log.levels.DEBUG)
	end

	local gitdir = get_absolute_gitdir()
	if not gitdir then
		close_slot_debounce(_head)
		close_slot_handle(_head)
		_watched_gitdir = nil
		return false
	end

	local head_path = gitdir .. "/HEAD"
	if vim.fn.filereadable(head_path) == 0 then
		close_slot_debounce(_head)
		close_slot_handle(_head)
		_watched_gitdir = nil
		return false
	end

	-- Short-circuit: already watching this gitdir (fs_event) or its HEAD
	-- (fs_poll fallback). Either is correct for the same repo.
	if _head.handle and (_head.target == gitdir or _head.target == head_path) then
		_watched_gitdir = gitdir
		return true
	end

	close_slot_handle(_head)

	if start_head_fs_event(gitdir) then
		_watched_gitdir = gitdir
		return true
	end

	if start_head_fs_poll(head_path) then
		_watched_gitdir = gitdir
		return true
	end

	return false
end

--- Stop both watches and release any handles. Safe to call repeatedly.
function M.stop()
	close_slot_debounce(_head)
	close_slot_handle(_head)
	close_slot_debounce(_storage)
	close_slot_handle(_storage)
	_watched_gitdir = nil
end

--- Stop the current watches (if any) and re-resolve targets, then start.
--- Use after a cross-project `:cd` or worktree switch that may have
--- changed the gitdir we should be watching.
---@return boolean started
function M.restart()
	M.stop()
	return M.start()
end

return M
