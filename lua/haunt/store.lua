---@class StoreModule
---@field get_bookmarks fun(): Bookmark[]
---@field has_bookmarks fun(): boolean
---@field load fun(): boolean
---@field reload fun()
---@field save fun(): boolean
---@field get_quickfix_items fun(opts?: QuickfixOpts): QuickfixItem[]
---@field find_by_id fun(bookmark_id: string): Bookmark|nil, number|nil
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
---@type Bookmark[]
local bookmarks = {}

---@private
---@type table<string, Bookmark[]>
local bookmarks_by_file = {}

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

--- Add a bookmark to the file-based index
--- Maintains sorted order by line number using binary search insertion
---@param bookmark Bookmark The bookmark to add to the index
local function add_to_file_index(bookmark)
	if not bookmarks_by_file[bookmark.file] then
		bookmarks_by_file[bookmark.file] = {}
	end

	local file_bookmarks = bookmarks_by_file[bookmark.file]

	-- Binary search to find insertion point
	local left, right = 1, #file_bookmarks
	local insert_pos = #file_bookmarks + 1

	while left <= right do
		local mid = math.floor((left + right) / 2)
		if file_bookmarks[mid].line < bookmark.line then
			left = mid + 1
		else
			insert_pos = mid
			right = mid - 1
		end
	end

	table.insert(file_bookmarks, insert_pos, bookmark)
end

--- Remove a bookmark from the file-based index
---@param bookmark Bookmark The bookmark to remove from the index
local function remove_from_file_index(bookmark)
	local file_bookmarks = bookmarks_by_file[bookmark.file]
	if not file_bookmarks then
		return
	end

	for i, bm in ipairs(file_bookmarks) do
		if bm.id == bookmark.id then
			table.remove(file_bookmarks, i)
			-- Clean up empty file entries
			if #file_bookmarks == 0 then
				bookmarks_by_file[bookmark.file] = nil
			end
			break
		end
	end
end

--- Clear all bookmarks for a specific file from the index
---@param filepath string The file path to clear from the index
local function clear_file_from_index(filepath)
	bookmarks_by_file[filepath] = nil
end

--- Rebuild the entire file-based index from the bookmarks array
--- This is called after loading bookmarks from persistence
local function rebuild_file_index()
	bookmarks_by_file = {}

	for _, bookmark in ipairs(bookmarks) do
		add_to_file_index(bookmark)
	end
end

--- Ensure bookmarks have been loaded
--- Triggers deferred loading if not already loaded
local function ensure_loaded()
	if not _loaded then
		M.load()
	end
end

--- Find a bookmark by its ID
---@param bookmark_id string The unique ID of the bookmark to find
---@return Bookmark|nil bookmark The bookmark if found, nil otherwise
---@return number|nil index The index in the bookmarks array, nil if not found
function M.find_by_id(bookmark_id)
	ensure_loaded()
	for i, bm in ipairs(bookmarks) do
		if bm.id == bookmark_id then
			return bm, i
		end
	end
	return nil, nil
end

--- Find a bookmark at a specific line in a file
---@param filepath string Normalized absolute file path
---@param line number 1-based line number
---@return Bookmark|nil bookmark The bookmark at the line, or nil if none exists
---@return number|nil index The index of the bookmark in the bookmarks table
function M.get_bookmark_at_line(filepath, line)
	ensure_loaded()

	-- If file has no name, can't have bookmarks
	if filepath == "" then
		return nil, nil
	end

	-- Search through all bookmarks for one at this file and line
	for i, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath and bookmark.line == line then
			return bookmark, i
		end
	end

	return nil, nil
end

--- Get sorted bookmarks for a specific file
--- O(1) lookup from file-based index (already sorted)
---@param filepath string The normalized file path
---@return Bookmark[] bookmarks Sorted array of bookmarks for the file
function M.get_sorted_bookmarks_for_file(filepath)
	ensure_loaded()
	return bookmarks_by_file[filepath] or {}
end

--- Get all bookmarks as a deep copy.
---
--- Returns all bookmarks currently in memory. The returned table is a
--- deep copy, so modifications won't affect the internal state.
---
---@return Bookmark[] bookmarks Array of all bookmarks
function M.get_bookmarks()
	ensure_loaded()
	return vim.deepcopy(bookmarks)
end

--- Get bookmark locations as quickfix items.
---
---@param opts? QuickfixOpts Options for filtering and formatting
---@return QuickfixItem[] items Quickfix items
function M.get_quickfix_items(opts)
	ensure_loaded()

	opts = opts or {}

	local append_annotations = opts.append_annotations
	if append_annotations == nil then
		append_annotations = true
	end

	local current_buffer = opts.current_buffer or false

	-- Work on a copy to avoid mutating store order
	local active_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		table.insert(active_bookmarks, bookmark)
	end

	if current_buffer then
		local current_file = utils.normalize_filepath(vim.api.nvim_buf_get_name(0))
		if current_file == "" then
			return {}
		end

		local filtered = {}
		for _, bookmark in ipairs(active_bookmarks) do
			if bookmark.file == current_file then
				table.insert(filtered, bookmark)
			end
		end
		active_bookmarks = filtered
	end

	if #active_bookmarks == 0 then
		return {}
	end

	table.sort(active_bookmarks, function(a, b)
		if a.file == b.file then
			return a.line < b.line
		end
		return a.file < b.file
	end)

	local items = {}
	for _, bookmark in ipairs(active_bookmarks) do
		local text = "Haunt bookmark"
		if append_annotations and bookmark.note and bookmark.note ~= "" then
			text = bookmark.note
		end

		table.insert(items, {
			filename = bookmark.file, -- absolute path works best for quickfix
			lnum = bookmark.line,
			col = 1,
			text = text,
		})
	end

	return items
end

--- Get raw reference to bookmarks array (for internal use only)
--- WARNING: Modifications to returned table affect internal state
---@return Bookmark[] bookmarks Direct reference to bookmarks array
function M.get_all_raw()
	ensure_loaded()
	return bookmarks
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
	rebuild_file_index()
	_loaded = true

	local info = require("haunt.project").get_info()
	_loaded_project_id = info.project_id
	_loaded_project_root = info.root
	_loaded_storage_path = persistence.get_storage_path()

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
	bookmarks_by_file = {}
	_loaded = false
	_loaded_project_id = nil
	_loaded_project_root = nil
	_loaded_storage_path = nil
	M.load()
end

--- Pull each bookmark's current line from its tracking extmark.
--- The visual extmark moves with text edits, but `bookmark.line` is set at
--- creation and never reassigned — without this sync the on-disk line is
--- pinned forever (issue #72).
local function sync_lines_from_extmarks()
	local display = require("haunt.display")
	for _, bm in ipairs(bookmarks) do
		if not bm.extmark_id then
			goto continue
		end

		local bufnr = vim.fn.bufnr(bm.file)
		if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
			goto continue
		end

		local cur = display.get_extmark_line(bufnr, bm.extmark_id)
		if cur then
			bm.line = cur
		end

		::continue::
	end
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

	sync_lines_from_extmarks()

	hooks.emit_pre_save({
		bookmarks = bookmarks,
		count = #bookmarks,
	})

	local success = persistence.save_bookmarks(bookmarks, _loaded_storage_path, _loaded_project_root)

	hooks.emit_post_save({
		bookmarks = bookmarks,
		count = #bookmarks,
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
	add_to_file_index(bookmark)
end

--- Remove a bookmark from the store
---@param bookmark Bookmark The bookmark to remove
---@return boolean success True if bookmark was found and removed
function M.remove_bookmark(bookmark)
	ensure_loaded()
	for i, bm in ipairs(bookmarks) do
		if bm.id == bookmark.id then
			table.remove(bookmarks, i)
			remove_from_file_index(bookmark)
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
	local bookmark = table.remove(bookmarks, index)
	if bookmark then
		remove_from_file_index(bookmark)
	end
	return bookmark
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

	-- Clear from index
	clear_file_from_index(filepath)

	return removed
end

--- Clear all bookmarks
---@return number count Number of bookmarks that were cleared
function M.clear_all_bookmarks()
	ensure_loaded()
	local count = #bookmarks
	bookmarks = {}
	bookmarks_by_file = {}
	return count
end

--- Reset internal state for testing purposes only
--- WARNING: This will clear ALL bookmarks from memory without persisting
--- Only use in test environments
---@private
function M._reset_for_testing()
	bookmarks = {}
	bookmarks_by_file = {}
	_loaded = true -- Prevent auto-loading from disk
	_loaded_project_id = nil
	_loaded_project_root = nil
	_loaded_storage_path = nil
end

return M
