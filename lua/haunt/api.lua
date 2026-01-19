---@toc_entry API Functions
---@tag haunt-api
---@text
--- # API Functions ~
---
--- All API functions are available through `require('haunt.api')`.
---
--- These functions provide the core functionality for managing bookmarks:
--- creating, navigating, annotating, and deleting bookmarks.

---@class ApiModule
---@field toggle_annotation fun(): boolean
---@field toggle_all_lines fun(): boolean
---@field are_annotations_visible fun(): boolean
---@field delete fun(): boolean
---@field get_bookmarks fun(): Bookmark[]
---@field has_bookmarks fun(): boolean
---@field load fun(): boolean
---@field restore_buffer_bookmarks fun(bufnr: number): boolean
---@field save fun(): boolean
---@field annotate fun(text?: string): boolean
---@field clear fun(): boolean
---@field clear_all fun(): boolean
---@field next fun(): boolean
---@field prev fun(): boolean
---@field delete_by_id fun(bookmark_id: string): boolean
---@field cleanup_buffer_tracking fun(bufnr: number)
---@field _reset_for_testing fun()

---@private
---@type ApiModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local utils = require("haunt.utils")

---@private
---@type boolean
local _autosave_setup = false

---@private
---@type boolean
local _annotations_visible = true

---@private
---@type StoreModule|nil
local store = nil
---@private
---@type DisplayModule|nil
local display = nil
---@private
---@type PersistenceModule|nil
local persistence = nil
---@private
---@type NavigationModule|nil
local navigation = nil
---@private
---@type RestorationModule|nil
local restoration = nil

---@private
local function ensure_modules()
	if not store then
		store = require("haunt.store")
	end
	if not display then
		display = require("haunt.display")
	end
	if not persistence then
		persistence = require("haunt.persistence")
	end
	if not navigation then
		navigation = require("haunt.navigation")
	end
	if not restoration then
		restoration = require("haunt.restoration")
	end
end

--- Clean up all visual elements for a bookmark
--- Removes extmarks, signs, and annotations from the buffer
---@param bufnr number Buffer number
---@param bookmark Bookmark The bookmark whose visuals should be cleaned up
local function cleanup_bookmark_visuals(bufnr, bookmark)
	ensure_modules()
	---@cast display -nil

	-- Delete annotation extmark if it exists
	if bookmark.annotation_extmark_id then
		display.hide_annotation(bufnr, bookmark.annotation_extmark_id)
	end

	if bookmark.extmark_id then
		-- Delete the extmark
		display.delete_bookmark_mark(bufnr, bookmark.extmark_id)

		-- Unplace the sign
		display.unplace_sign(bufnr, bookmark.extmark_id)
	end
end

--- Create a bookmark with visual elements and persist it
--- This is a helper function to avoid code duplication between toggle_annotation() and annotate()
---@param bufnr number Buffer number
---@param filepath string Normalized absolute file path
---@param line number 1-based line number
---@param note string|nil Optional annotation text
---@return boolean success True if bookmark was created and persisted successfully
local function create_and_persist_bookmark(bufnr, filepath, line, note)
	ensure_modules()
	---@cast store -nil
	---@cast display -nil
	---@cast persistence -nil

	-- Create bookmark with unique ID
	local new_bookmark, err = persistence.create_bookmark(filepath, line, note)
	if not new_bookmark then
		vim.notify("haunt.nvim: Failed to create bookmark: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Set extmark for line tracking
	local extmark_id = display.set_bookmark_mark(bufnr, new_bookmark)
	if not extmark_id then
		vim.notify("haunt.nvim: Failed to create extmark", vim.log.levels.ERROR)
		return false
	end

	-- Store extmark_id in bookmark
	new_bookmark.extmark_id = extmark_id

	-- Show annotation as virtual text if note exists
	if note then
		local annotation_extmark_id = display.show_annotation(bufnr, line, note)
		new_bookmark.annotation_extmark_id = annotation_extmark_id
	end

	-- Place sign (using extmark_id as sign_id)
	display.place_sign(bufnr, line, extmark_id)

	-- Add to store
	store.add_bookmark(new_bookmark)

	-- Save to persistence
	local save_ok = store.save()
	if not save_ok then
		-- Rollback: remove from store and clean up all visual elements
		store.remove_bookmark(new_bookmark)

		if new_bookmark.annotation_extmark_id then
			display.hide_annotation(bufnr, new_bookmark.annotation_extmark_id)
		end
		display.delete_bookmark_mark(bufnr, extmark_id)
		display.unplace_sign(bufnr, extmark_id)
		vim.notify("haunt.nvim: Failed to save bookmarks", vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Update an existing bookmark's annotation
---@param bufnr number Buffer number
---@param line number 1-based line number
---@param bookmark Bookmark The bookmark to update
---@param new_note string The new annotation text
---@return boolean success True if bookmark was updated and persisted successfully
local function update_bookmark_annotation(bufnr, line, bookmark, new_note)
	ensure_modules()
	---@cast store -nil
	---@cast display -nil

	local old_note = bookmark.note
	local old_annotation_extmark_id = bookmark.annotation_extmark_id

	-- Hide old annotation if it exists
	if old_annotation_extmark_id then
		display.hide_annotation(bufnr, old_annotation_extmark_id)
	end

	-- Show new annotation and update bookmark
	local new_extmark_id = display.show_annotation(bufnr, line, new_note)
	bookmark.note = new_note
	bookmark.annotation_extmark_id = new_extmark_id

	-- Save to persistence
	local save_ok = store.save()
	if not save_ok then
		-- Rollback
		bookmark.note = old_note
		bookmark.annotation_extmark_id = old_annotation_extmark_id
		if new_extmark_id then
			display.hide_annotation(bufnr, new_extmark_id)
		end

		if old_annotation_extmark_id then
			bookmark.annotation_extmark_id = display.show_annotation(bufnr, line, old_note or "")
		end

		vim.notify("haunt.nvim: Failed to save bookmarks after annotation update", vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Toggle annotation visibility at the current cursor position.
---
--- If a bookmark exists at the current line and has an annotation,
--- this will show/hide the annotation virtual text. If no annotation
--- exists, does nothing.
---
---@return boolean success True if toggled successfully
---
---@usage >lua
---   require('haunt.api').toggle_annotation()
--- <
function M.toggle_annotation()
	ensure_modules()
	---@cast store -nil
	---@cast display -nil

	require("haunt")._ensure_initialized()

	-- Set up autosave autocmds after first bookmark is created
	if not _autosave_setup then
		require("haunt").setup_autocmds()
		_autosave_setup = true
	end

	local bufnr = vim.api.nvim_get_current_buf()

	local valid, error_msg = utils.validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number
	local filepath = utils.normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if a bookmark exists at this line
	local existing_bookmark, _ = store.get_bookmark_at_line(filepath, line)
	if not existing_bookmark then
		vim.notify("haunt.nvim: No bookmark on this line", vim.log.levels.INFO)
		return false
	end

	-- if no note exists do nothing, keep sign col
	if not existing_bookmark.note then
		return true
	end

	-- toggle visibility
	if existing_bookmark.annotation_extmark_id then
		display.hide_annotation(bufnr, existing_bookmark.annotation_extmark_id)
		existing_bookmark.annotation_extmark_id = nil
	else
		local extmark_id = display.show_annotation(bufnr, line, existing_bookmark.note)
		existing_bookmark.annotation_extmark_id = extmark_id
	end

	return true
end

--- Toggle visibility of ALL annotations across ALL bookmarks.
---
--- This is useful for temporarily hiding all annotations to reduce
--- visual noise, then showing them again.
---
---@return boolean visible The new visibility state (true = visible, false = hidden)
---
---@usage >lua
---   local visible = require('haunt.api').toggle_all_lines()
---   print(visible and "Annotations shown" or "Annotations hidden")
--- <
function M.toggle_all_lines()
	ensure_modules()
	---@cast store -nil
	---@cast display -nil

	_annotations_visible = not _annotations_visible

	local bookmarks = store.get_all_raw()
	for _, bookmark in ipairs(bookmarks) do
		if not bookmark.note then
			goto continue
		end

		local bufnr = vim.fn.bufnr(bookmark.file)
		if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
			goto continue
		end

		-- get line from extmark, persistence can become ood
		local current_line = nil
		if bookmark.extmark_id then
			current_line = display.get_extmark_line(bufnr, bookmark.extmark_id)
		end
		if not current_line then -- fallback
			current_line = bookmark.line
		end

		-- if line is gone, move on
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		if current_line < 1 or current_line > line_count then
			goto continue
		end

		-- actual toggling logic
		if _annotations_visible then
			-- Only update annotation if it doesn't exist or is at wrong position
			local needs_update = true
			if bookmark.annotation_extmark_id then
				local annotation_line = display.get_extmark_line(bufnr, bookmark.annotation_extmark_id)
				-- If annotation is already at the correct position, no update needed
				if annotation_line == current_line then
					needs_update = false
				else
					-- Position changed, hide old annotation
					display.hide_annotation(bufnr, bookmark.annotation_extmark_id)
				end
			end

			if needs_update then
				local ok, extmark_id = pcall(display.show_annotation, bufnr, current_line, bookmark.note)
				if ok then
					bookmark.annotation_extmark_id = extmark_id
				end
			end
		else
			if bookmark.annotation_extmark_id then
				display.hide_annotation(bufnr, bookmark.annotation_extmark_id)
				bookmark.annotation_extmark_id = nil
			end
		end

		::continue::
	end

	return _annotations_visible
end

--- Check if annotations are globally visible.
---
---@return boolean visible True if annotations should be displayed
function M.are_annotations_visible()
	return _annotations_visible
end

--- Delete the bookmark at the current cursor position.
---
--- Removes the bookmark from persistence and cleans up all visual elements
--- (sign, extmarks, annotations).
---
---@return boolean success True if bookmark was deleted
---
---@usage >lua
---   require('haunt.api').delete()
--- <
function M.delete()
	ensure_modules()
	---@cast store -nil

	require("haunt")._ensure_initialized()

	local bufnr = vim.api.nvim_get_current_buf()

	local valid, error_msg = utils.validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number
	local filepath = utils.normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if a bookmark exists at this line
	local existing_bookmark, _ = store.get_bookmark_at_line(filepath, line)
	if not existing_bookmark then
		vim.notify("haunt.nvim: No bookmark on this line", vim.log.levels.INFO)
		return false
	end

	cleanup_bookmark_visuals(bufnr, existing_bookmark)
	store.remove_bookmark(existing_bookmark)

	-- Save to persistence
	local save_ok = store.save()
	if not save_ok then
		vim.notify("haunt.nvim: Failed to save bookmarks after removal", vim.log.levels.ERROR)
		return false
	end

	vim.notify("haunt.nvim: Bookmark deleted", vim.log.levels.INFO)
	return true
end

--- Add or edit an annotation for a bookmark.
---
--- If a bookmark exists at the current line, updates its annotation.
--- If no bookmark exists, creates a new bookmark with the annotation.
--- Empty input cancels the operation.
---
---@param text? string Optional annotation text. If provided, skips the input prompt.
---@return boolean success True if annotation was created/updated
---
---@usage >lua
---   -- Prompt user for annotation
---   require('haunt.api').annotate()
---
---   -- Set annotation programmatically
---   require('haunt.api').annotate("TODO: Fix this bug")
--- <
function M.annotate(text)
	ensure_modules()
	---@cast store -nil

	-- Ensure display layer is initialized
	require("haunt")._ensure_initialized()

	-- Set up autosave autocmds after first bookmark is created
	if not _autosave_setup then
		require("haunt").setup_autocmds()
		_autosave_setup = true
	end

	-- Get current buffer and cursor position
	local bufnr = vim.api.nvim_get_current_buf()

	-- Validate buffer can have bookmarks
	local valid, error_msg = utils.validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number

	local filepath = utils.normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	local existing_bookmark, _ = store.get_bookmark_at_line(filepath, line)

	-- use param if programmatic call, otherwise prompt user
	local annotation = text
	if not annotation then
		local default_text = existing_bookmark and existing_bookmark.note or ""
		annotation = vim.fn.input({
			prompt = " Annotation: ",
			default = default_text,
		})
	end

	-- no input is a cancel
	if annotation == "" then
		return false
	end

	if existing_bookmark then
		local success = update_bookmark_annotation(bufnr, line, existing_bookmark, annotation)
		if success then
			vim.notify("haunt.nvim: Annotation updated", vim.log.levels.INFO)
		end
		return success
	end

	local success = create_and_persist_bookmark(bufnr, filepath, line, annotation)
	if success then
		vim.notify("haunt.nvim: Annotation created", vim.log.levels.INFO)
	end
	return success
end

--- Clear all bookmarks in the current file.
---
---@return boolean success True if cleared successfully
---
---@usage >lua
---   require('haunt.api').clear()
--- <
function M.clear()
	ensure_modules()
	---@cast store -nil

	local current_file = utils.normalize_filepath(vim.fn.expand("%"))

	if current_file == "" then
		vim.notify("haunt.nvim: No file in current buffer", vim.log.levels.WARN)
		return false
	end

	-- Get bookmarks before clearing for visual cleanup
	local bookmarks = store.get_all_raw()
	local file_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == current_file then
			table.insert(file_bookmarks, bookmark)
		end
	end

	-- early return for no bookmarks
	if #file_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks to clear in current file", vim.log.levels.INFO)
		return true
	end

	local bufnr = vim.api.nvim_get_current_buf()

	for _, bookmark in ipairs(file_bookmarks) do
		cleanup_bookmark_visuals(bufnr, bookmark)
	end

	-- Clear from store
	store.clear_file_bookmarks(current_file)

	local save_ok = store.save()

	if save_ok then
		local count = #file_bookmarks
		vim.notify(string.format("haunt.nvim: Cleared %d bookmark(s) from current file", count), vim.log.levels.INFO)
		return true
	else
		vim.notify("haunt.nvim: Failed to save after clearing bookmarks", vim.log.levels.ERROR)
		return false
	end
end

--- Clear all bookmarks in the project/branch.
---
--- Shows a confirmation prompt before clearing.
---
---@return boolean success True if cleared successfully
---
---@usage >lua
---   require('haunt.api').clear_all()
--- <
function M.clear_all()
	ensure_modules()
	---@cast store -nil

	if not store.has_bookmarks() then
		vim.notify("haunt.nvim: No bookmarks to clear", vim.log.levels.INFO)
		return true
	end

	local choice = vim.fn.confirm("Clear all bookmarks in the CWD?", "&Yes\n&No", 2)

	-- no = 2, cancelled = 0
	if choice ~= 1 then
		vim.notify("haunt.nvim: Clear all cancelled", vim.log.levels.INFO)
		return false
	end

	-- Group bookmarks by file to find corresponding buffers
	local bookmarks = store.get_all_raw()
	--- @type table<string, Bookmark[]>
	local grouped_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		if not grouped_bookmarks[bookmark.file] then
			grouped_bookmarks[bookmark.file] = {}
		end
		table.insert(grouped_bookmarks[bookmark.file], bookmark)
	end

	-- iterate over file -> bookmarks map
	for file_path, file_bookmarks in pairs(grouped_bookmarks) do
		local bufnr = vim.fn.bufnr(file_path)
		if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
			goto continue
		end

		for _, bookmark in ipairs(file_bookmarks) do
			cleanup_bookmark_visuals(bufnr, bookmark)
		end

		::continue::
	end

	-- Get count before clearing
	local count = #bookmarks

	-- Clear all from store
	store.clear_all_bookmarks()

	-- Save empty bookmark list to persistence
	local save_ok = store.save()

	if save_ok then
		vim.notify(string.format("haunt.nvim: Cleared all %d bookmark(s)", count), vim.log.levels.INFO)
		return true
	else
		vim.notify("haunt.nvim: Failed to save after clearing all bookmarks", vim.log.levels.ERROR)
		return false
	end
end

--- Delete a bookmark by its unique ID.
---
--- This is useful for programmatic deletion without needing to navigate
--- to the bookmark (e.g., from the picker).
---
---@param bookmark_id string The unique ID of the bookmark to delete
---@return boolean success True if the bookmark was deleted
---
---@usage >lua
---   local bookmarks = require('haunt.api').get_bookmarks()
---   if #bookmarks > 0 then
---     require('haunt.api').delete_by_id(bookmarks[1].id)
---   end
--- <
function M.delete_by_id(bookmark_id)
	ensure_modules()
	---@cast store -nil

	local bookmark, _ = store.find_by_id(bookmark_id)
	if not bookmark then
		vim.notify("haunt.nvim: Bookmark not found", vim.log.levels.WARN)
		return false
	end

	local bufnr, err = utils.ensure_buffer_for_file(bookmark.file)
	if not bufnr then
		vim.notify("haunt.nvim: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	cleanup_bookmark_visuals(bufnr, bookmark)
	store.remove_bookmark(bookmark)

	local save_ok = store.save()
	if not save_ok then
		vim.notify("haunt.nvim: Failed to save bookmarks after deletion", vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Get all bookmarks as a deep copy.
---
--- Returns all bookmarks currently in memory. The returned table is a
--- deep copy, so modifications won't affect the internal state.
---
---@return Bookmark[] bookmarks Array of all bookmarks
---
---@usage >lua
---   local bookmarks = require('haunt.api').get_bookmarks()
---   for _, bookmark in ipairs(bookmarks) do
---     print(string.format("%s:%d - %s",
---       bookmark.file, bookmark.line, bookmark.note or ""))
---   end
--- <
function M.get_bookmarks()
	ensure_modules()
	---@cast store -nil
	return store.get_bookmarks()
end

--- Check if any bookmarks exist.
---
--- Returns true if there are any bookmarks in memory (after loading from disk).
--- This is more reliable than checking package.loaded state.
---
---@return boolean has_bookmarks True if bookmarks exist, false otherwise
---
---@usage >lua
---   if require('haunt.api').has_bookmarks() then
---     print("Bookmarks found!")
---   end
--- <
function M.has_bookmarks()
	ensure_modules()
	---@cast store -nil
	return store.has_bookmarks()
end

--- Load bookmarks from persistent storage.
---
--- This is called automatically when needed. You typically don't need
--- to call this manually unless you want to reload bookmarks from disk.
---
---@return boolean success True if load succeeded
function M.load()
	ensure_modules()
	---@cast store -nil
	return store.load()
end

--- Save bookmarks to persistent storage.
---
--- Bookmarks are auto-saved on buffer hide and Neovim exit, but you can
--- call this manually to force a save.
---
---@return boolean success True if save succeeded
---
---@usage >lua
---   require('haunt.api').save()
--- <
function M.save()
	ensure_modules()
	---@cast store -nil
	return store.save()
end

--- Jump to the next bookmark in the current buffer.
---
--- Wraps around to the first bookmark if at the end.
---
---@return boolean success True if jumped to a bookmark
---
---@usage >lua
---   require('haunt.api').next()
--- <
function M.next()
	ensure_modules()
	---@cast navigation -nil
	return navigation.next()
end

--- Jump to the previous bookmark in the current buffer.
---
--- Wraps around to the last bookmark if at the beginning.
---
---@return boolean success True if jumped to a bookmark
---
---@usage >lua
---   require('haunt.api').prev()
--- <
function M.prev()
	ensure_modules()
	---@cast navigation -nil
	return navigation.prev()
end

--- Restore bookmark visuals for a specific buffer.
---
--- This is called automatically when buffers are opened. You typically
--- don't need to call this manually.
---
---@param bufnr number Buffer number to restore bookmarks for
---@return boolean success True if restoration succeeded or was skipped
function M.restore_buffer_bookmarks(bufnr)
	ensure_modules()
	---@cast restoration -nil
	return restoration.restore_buffer_bookmarks(bufnr, _annotations_visible)
end

--- Clean up restoration tracking for a deleted buffer
--- This prevents memory leaks in the restored_buffers table
---@param bufnr number Buffer number that was deleted
function M.cleanup_buffer_tracking(bufnr)
	ensure_modules()
	---@cast restoration -nil
	restoration.cleanup_buffer_tracking(bufnr)
end

--- Reset internal state for testing purposes only
--- WARNING: This will clear ALL bookmarks from memory without persisting
--- Only use in test environments
---@private
function M._reset_for_testing()
	ensure_modules()
	---@cast store -nil
	store._reset_for_testing()
	_autosave_setup = false
	_annotations_visible = true
end

return M
