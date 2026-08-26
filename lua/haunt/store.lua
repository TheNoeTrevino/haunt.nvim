---@class StoreModule
---@field get_bookmarks fun(): Bookmark[]
---@field has_bookmarks fun(): boolean
---@field load fun(): boolean
---@field reload fun()
---@field save fun(): boolean
---@field get_quickfix_items fun(opts?: QuickfixOpts): QuickfixItem[]
---@field find_by_id fun(bookmark_id: string): Bookmark|nil
---@field get_bookmark_at_line fun(filepath: string, line: number): Bookmark|nil, number|nil
---@field get_sorted_bookmarks_for_file fun(filepath: string): Bookmark[]
---@field add_bookmark fun(bookmark: Bookmark)
---@field remove_bookmark fun(bookmark: Bookmark): boolean
---@field remove_bookmark_at_index fun(index: number): Bookmark|nil
---@field clear_file_bookmarks fun(filepath: string): Bookmark[]
---@field clear_all_bookmarks fun(): number
---@field get_all_raw fun(): Bookmark[]
---@field get_loaded_project_id fun(): string|nil
---@field get_loaded_project_root fun(): string|nil
---@field get_loaded_storage_path fun(): string|nil
---@field _reset_for_testing fun()

---@type StoreModule
---@diagnostic disable-next-line: missing-fields
local M = {}

---@class QuickfixOpts
---@field current_buffer? boolean If true, only include bookmarks from the current buffer
---@field append_annotations? boolean If true, include annotations in quickfix text

---@class QuickfixItem
---@field filename string
---@field lnum integer
---@field col integer
---@field text string

local utils = require("haunt.utils")

---@private
--- The in-memory bookmark array. `bookmark.line` in here is a SNAPSHOT: it is
--- authoritative only for persistence and for buffers that aren't loaded (no
--- extmark to ask). While a buffer is loaded, the tracking extmark is the
--- source of truth for position. Nothing outside `synced_bookmarks()` and the
--- load/save boundary may read `.line` from this table directly - every
--- public accessor goes through `synced_bookmarks()` so it cannot observe stale
--- lines
---@type Bookmark[]
local bookmarks = {}

---@private
---@type boolean
local _loaded = false

---@private
--- The project_id the in-memory bookmarks belong to. Set on load/reload.
--- Used by `haunt.project.handle_dir_change` to detect cross-project cd.
---@type string|nil
local _loaded_project_id = nil

---@private
--- The project root the in-memory bookmarks were serialized against, captured
--- at load time. Saves always use this root (not the cache's current value)
--- so a `:cd` into a different project doesn't corrupt the relative paths.
---@type string|nil
local _loaded_project_root = nil

---@private
--- The storage path the in-memory bookmarks were loaded from. Saves always
--- write here, regardless of where the project cache would resolve "now".
---@type string|nil
local _loaded_storage_path = nil

---@private
---@type PersistenceModule|nil
local persistence = nil

---@private
---@type HooksModule|nil
local hooks = nil

---@private
local function ensure_persistence()
	if not persistence then
		persistence = require("haunt.persistence")
	end
end

---@private
local function ensure_hooks()
	if not hooks then
		hooks = require("haunt.hooks")
	end
end

--- Ensure bookmarks have been loaded
--- Triggers deferred loading if not already loaded
local function ensure_loaded()
	if not _loaded then
		M.load()
	end
end

--- Pull each bookmark's current line from its tracking extmark.
--- The visual extmark moves with text edits, but `bookmark.line` is set at
--- creation and never reassigned — without this sync, reads (picker, save)
--- see the stale on-create line instead of where the bookmark visually sits
--- now (issues #72, #92).
local function sync_lines_from_extmarks()
	local display = require("haunt.display")
	-- Cache the resolved bufnr per file so we make at most one `vim.fn.bufnr`
	-- (buffer-list scan) per distinct file, not one per bookmark. `false` is
	-- the sentinel for "already checked and not loaded" so the lookup stays
	-- O(1) on subsequent bookmarks in the same file.
	local bufnr_cache = {}
	for _, bm in ipairs(bookmarks) do
		if not bm.extmark_id then
			goto continue
		end

		local bufnr = bufnr_cache[bm.file]
		if bufnr == nil then
			bufnr = vim.fn.bufnr(bm.file)
			if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
				bufnr = false
			end
			bufnr_cache[bm.file] = bufnr
		end
		if not bufnr then
			goto continue
		end

		local cur = display.get_extmark_line(bufnr, bm.extmark_id)
		if cur then
			bm.line = cur
		end

		::continue::
	end
end

--- THE read funnel. Every public accessor that exposes bookmarks (or anything
--- derived from their positions) goes through here — it is the only place
--- outside persistence allowed to touch the raw array. Loading and syncing
--- happen unconditionally, so no caller can observe a stale `.line` and the
--- #72/#92/#99 class of bug cannot be reintroduced by a new getter.
---
--- Returns the LIVE internal array: cheap, and several internal callers
--- (restoration, display toggles, hooks) rely on reference identity with the
--- stored bookmark. Accessors that hand data to plugin users must copy.
---@return Bookmark[] bookmarks Live references, lines synced from extmarks
local function synced_bookmarks()
	ensure_loaded()
	sync_lines_from_extmarks()
	return bookmarks
end

--- Find a bookmark by its ID
---@param bookmark_id string The unique ID of the bookmark to find
---@return Bookmark|nil bookmark The bookmark if found, nil otherwise
function M.find_by_id(bookmark_id)
	---@param bookmark Bookmark
	return vim.iter(synced_bookmarks()):find(function(bookmark)
		return bookmark.id == bookmark_id
	end)
end

--- Find a bookmark at a specific line in a file
---@param filepath string Normalized absolute file path
---@param line number 1-based line number
---@return Bookmark|nil bookmark The bookmark at the line, or nil if none exists
---@return number|nil index The index of the bookmark in the bookmarks table
function M.get_bookmark_at_line(filepath, line)
	-- If file has no name, can't have bookmarks
	if filepath == "" then
		return nil, nil
	end

	-- Iterate (index, bookmark) pairs so the index survives the pipeline;
	-- `find` short-circuits on the first match and returns nil, nil otherwise.
	---@param bookmark Bookmark
	local i, found = vim.iter(ipairs(synced_bookmarks())):find(function(_, bookmark)
		return bookmark.file == filepath and bookmark.line == line
	end)

	return found, i
end

--- Get bookmarks for a specific file, sorted by their current line.
---
--- Returns a fresh array of live bookmark references (not copies) — callers
--- pass them straight to hooks, which expect identity with the stored bookmark.
---@param filepath string The normalized file path
---@return Bookmark[] bookmarks Array of bookmarks for the file, sorted by line
function M.get_sorted_bookmarks_for_file(filepath)
	local file_bookmarks = vim
		.iter(synced_bookmarks())
		---@param bookmark Bookmark
		:filter(function(bookmark)
			return bookmark.file == filepath
		end)
		:totable()

	table.sort(file_bookmarks, function(a, b)
		return a.line < b.line
	end)

	return file_bookmarks
end

--- Get all bookmarks as a deep copy.
---
--- Returns all bookmarks currently in memory. The returned table is a
--- deep copy, so modifications won't affect the internal state.
---
---@return Bookmark[] bookmarks Array of all bookmarks
function M.get_bookmarks()
	return vim.deepcopy(synced_bookmarks())
end

--- Get bookmark locations as quickfix items.
---
---@param opts? QuickfixOpts Options for filtering and formatting
---@return QuickfixItem[] items Quickfix items
function M.get_quickfix_items(opts)
	opts = opts or {}

	local append_annotations = opts.append_annotations
	if append_annotations == nil then
		append_annotations = true
	end

	local filter_to_current_file = nil
	if opts.current_buffer then
		filter_to_current_file = utils.normalize_filepath(vim.api.nvim_buf_get_name(0))
		if filter_to_current_file == "" then
			return {}
		end
	end

	-- Build plain items straight off the live references — nothing here
	-- mutates a bookmark, and the items themselves are what get sorted.
	local items = vim
		.iter(synced_bookmarks())
		---@param bookmark Bookmark
		:filter(function(bookmark)
			return not filter_to_current_file or bookmark.file == filter_to_current_file
		end)
		---@param bookmark Bookmark
		:map(function(bookmark)
			local text = "Haunt bookmark"
			if append_annotations and bookmark.note and bookmark.note ~= "" then
				text = bookmark.note
			end
			return {
				filename = bookmark.file, -- absolute path works best for quickfix
				lnum = bookmark.line,
				col = 1,
				text = text,
			}
		end)
		:totable()

	table.sort(items, function(a, b)
		if a.filename == b.filename then
			return a.lnum < b.lnum
		end
		return a.filename < b.filename
	end)

	return items
end

--- Get live references to all bookmarks (for internal use only).
---
--- This is the mutation channel: restoration and display toggles write extmark
--- ids back onto the returned bookmarks, so they need identity with internal
--- state — a copy would silently discard their writes.
--- Lines are synced through the read funnel like every other accessor.
--- WARNING: Modifications to the returned table affect internal state.
---@return Bookmark[] bookmarks Direct reference to bookmarks array
function M.get_all_raw()
	return synced_bookmarks()
end

--- Check if any bookmarks exist.
---
--- Returns true if there are any bookmarks in memory (after loading from disk).
---
---@return boolean has_bookmarks True if bookmarks exist, false otherwise
function M.has_bookmarks()
	ensure_loaded()
	return #bookmarks > 0
end

--- Load bookmarks from persistent storage.
---
--- This is called automatically when needed. You typically don't need
--- to call this manually unless you want to reload bookmarks from disk.
---
--- Returns false when persistence reports a load failure (unreadable file,
--- malformed JSON, unsupported version). In that case the in-memory store
--- is left untouched, `_loaded` is not set, and `on_load` is NOT emitted —
--- observers only see successful loads. A fresh user with no storage file
--- is a successful load with zero bookmarks (returns true).
---
---@return boolean success True if load succeeded
function M.load()
	if _loaded then
		return true
	end

	ensure_persistence()
	ensure_hooks()
	---@cast persistence -nil
	---@cast hooks -nil

	local loaded_bookmarks = persistence.load_bookmarks()
	if not loaded_bookmarks then
		return false
	end

	bookmarks = loaded_bookmarks
	_loaded = true

	local info = require("haunt.project").get_info()
	_loaded_project_id = info.project_id
	_loaded_project_root = info.root
	_loaded_storage_path = persistence.get_storage_path()

	-- What we just read is by definition in sync with us.
	require("haunt.watcher").mark_synced(_loaded_storage_path)

	hooks.emit_load({
		bookmarks = bookmarks,
		count = #bookmarks,
	})

	return true
end

--- Reset state and reload bookmarks from persistent storage.
---
--- Clears all in-memory bookmarks and reloads from disk.
--- Used when changing data_dir to load from a new location.
function M.reload()
	bookmarks = {}
	_loaded = false
	_loaded_project_id = nil
	_loaded_project_root = nil
	_loaded_storage_path = nil
	M.load()
end

--- Save bookmarks to persistent storage.
---
--- Pulls each bookmark's current line from its tracking extmark, then writes
--- to the stamped storage path/root captured at load time (not the project
--- cache's current values), so a `:cd` into a different project doesn't
--- redirect saves mid-flight.
---
---@return boolean success True if save succeeded
function M.save()
	ensure_persistence()
	ensure_hooks()
	---@cast persistence -nil
	---@cast hooks -nil

	-- The funnel refreshes `.line` snapshots from extmarks; persistence then
	-- serializes those snapshots. This is the only writer of snapshot state.
	local synced = synced_bookmarks()

	hooks.emit_pre_save({
		bookmarks = synced,
		count = #synced,
	})

	local success = persistence.save_bookmarks(synced, _loaded_storage_path, _loaded_project_root)

	-- Record the file state we just produced so the storage watcher doesn't
	-- mistake our own write for an external one and reload on top of itself.
	require("haunt.watcher").mark_synced(_loaded_storage_path)

	hooks.emit_post_save({
		bookmarks = synced,
		count = #synced,
		success = success,
	})

	return success
end

--- The project_id stamped onto the in-memory store. Used by the dir-change
--- handler to detect when the user has cd'd into a different project.
---@return string|nil
function M.get_loaded_project_id()
	return _loaded_project_id
end

--- The project root stamped onto the in-memory store. Used by the dir-change
--- handler to short-circuit when cwd is still under this root.
---@return string|nil
function M.get_loaded_project_root()
	return _loaded_project_root
end

--- The storage file path stamped onto the in-memory store at load time.
--- Used by the branch watcher: when `<gitdir>/HEAD` changes, the watcher
--- recomputes the project's expected storage path and reloads if it no
--- longer matches what's in memory (i.e. the user switched branches).
---@return string|nil
function M.get_loaded_storage_path()
	return _loaded_storage_path
end

--- Add a bookmark to the store
---@param bookmark Bookmark The bookmark to add
function M.add_bookmark(bookmark)
	ensure_loaded()
	table.insert(bookmarks, bookmark)
end

--- Remove a bookmark from the store
---@param bookmark Bookmark The bookmark to remove
---@return boolean success True if bookmark was found and removed
function M.remove_bookmark(bookmark)
	ensure_loaded()
	for i, bm in ipairs(bookmarks) do
		if bm.id == bookmark.id then
			table.remove(bookmarks, i)
			return true
		end
	end
	return false
end

--- Remove a bookmark at a specific index
---@param index number The index to remove
---@return Bookmark|nil bookmark The removed bookmark, or nil if index invalid
function M.remove_bookmark_at_index(index)
	ensure_loaded()
	if index < 1 or index > #bookmarks then
		return nil
	end
	return table.remove(bookmarks, index)
end

--- Clear all bookmarks for a specific file
---@param filepath string The file path to clear
---@return Bookmark[] removed Array of removed bookmarks
function M.clear_file_bookmarks(filepath)
	ensure_loaded()
	local removed = {}
	local indices_to_remove = {}

	for i, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath then
			table.insert(removed, bookmark)
			table.insert(indices_to_remove, i)
		end
	end

	-- Remove in reverse order to avoid index shifting
	for i = #indices_to_remove, 1, -1 do
		table.remove(bookmarks, indices_to_remove[i])
	end

	return removed
end

--- Clear all bookmarks
---@return number count Number of bookmarks that were cleared
function M.clear_all_bookmarks()
	ensure_loaded()
	local count = #bookmarks
	bookmarks = {}
	return count
end

--- Reset internal state for testing purposes only
--- WARNING: This will clear ALL bookmarks from memory without persisting
--- Only use in test environments
---@private
function M._reset_for_testing()
	bookmarks = {}
	_loaded = true -- Prevent auto-loading from disk
	_loaded_project_id = nil
	_loaded_project_root = nil
	_loaded_storage_path = nil
end

return M
