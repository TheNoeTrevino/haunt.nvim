---@class StoreModule
---@field get_bookmarks fun(): Bookmark[]
---@field has_bookmarks fun(): boolean
---@field load fun(): boolean
---@field save fun(): boolean
---@field find_by_id fun(bookmark_id: string): Bookmark|nil, number|nil
---@field get_bookmark_at_line fun(filepath: string, line: number): Bookmark|nil, number|nil
---@field get_sorted_bookmarks_for_file fun(filepath: string): Bookmark[]
---@field add_bookmark fun(bookmark: Bookmark)
---@field remove_bookmark fun(bookmark: Bookmark): boolean
---@field remove_bookmark_at_index fun(index: number): Bookmark|nil
---@field clear_file_bookmarks fun(filepath: string): Bookmark[]
---@field clear_all_bookmarks fun(): number
---@field get_all_raw fun(): Bookmark[]
---@field _reset_for_testing fun()

---@type StoreModule
---@diagnostic disable-next-line: missing-fields
local M = {}

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
---@type PersistenceModule|nil
local persistence = nil

---@private
local function ensure_persistence()
	if not persistence then
		persistence = require("haunt.persistence")
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
---@return boolean success True if load succeeded
function M.load()
	if _loaded then
		return true
	end

	ensure_persistence()
	---@cast persistence -nil
	local loaded_bookmarks = persistence.load_bookmarks()
	if loaded_bookmarks then
		bookmarks = loaded_bookmarks
		rebuild_file_index()
	end
	_loaded = true

	return true
end

--- Save bookmarks to persistent storage.
---
--- Bookmarks are auto-saved on buffer hide and Neovim exit, but you can
--- call this manually to force a save.
---
---@return boolean success True if save succeeded
function M.save()
	ensure_persistence()
	---@cast persistence -nil
	local success = persistence.save_bookmarks(bookmarks)
	return success
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
end

return M
