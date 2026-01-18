---@toc_entry API Functions
---@tag haunt-api
---@text
--- # API Functions ~
---
--- All API functions are available through `require('haunt.api')`.
---
--- These functions provide the core functionality for managing bookmarks:
--- creating, navigating, annotating, and deleting bookmarks.

---@private
local M = {}

---@private
local bookmarks = {}

---@private
local _loaded = false

---@private
local _autosave_setup = false

---@private
local _annotations_visible = true

---@private
local persistence = nil
---@private
local display = nil

---@private
local function ensure_modules()
	if not persistence then
		persistence = require("haunt.persistence")
	end
	if not display then
		display = require("haunt.display")
	end
	---@cast persistence -nil
	---@cast display -nil
end

--- Ensure bookmarks have been loaded
--- Triggers deferred loading if not already loaded
local function ensure_loaded()
	if not _loaded then
		M.load()
	end
end

--- Normalize a file path to absolute form
--- Ensures consistent path representation for comparisons
---@param path string The file path to normalize
---@return string normalized_path The absolute file path
local function normalize_filepath(path)
	if path == "" then
		return ""
	end
	return vim.fn.fnamemodify(path, ":p")
end

--- Ensure a buffer exists and is loaded for a file path
--- Creates the buffer if it doesn't exist and loads it
---@param filepath string The file path to get/create a buffer for
---@return number|nil bufnr The buffer number, or nil if failed
---@return string|nil error_msg Error message if validation fails
local function ensure_buffer_for_file(filepath)
	local bufnr = vim.fn.bufnr(filepath)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(filepath)
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, "Failed to create buffer for file: " .. filepath
	end

	vim.fn.bufload(bufnr)

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil, "Failed to load buffer for file: " .. filepath
	end

	return bufnr, nil
end

--- Find a bookmark by its ID
---@param bookmark_id string The unique ID of the bookmark to find
---@return table|nil bookmark The bookmark if found, nil otherwise
---@return number|nil index The index in the bookmarks array, nil if not found
local function find_by_id(bookmark_id)
	for i, bm in ipairs(bookmarks) do
		if bm.id == bookmark_id then
			return bm, i
		end
	end
	return nil, nil
end

--- Clean up all visual elements for a bookmark
--- Removes extmarks, signs, and annotations from the buffer
---@param bufnr number Buffer number
---@param bookmark table The bookmark whose visuals should be cleaned up
local function cleanup_bookmark_visuals(bufnr, bookmark)
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

--- Validate that a buffer can have bookmarks
--- Checks for empty filepath, special buffers, buffer types, and modifiable status
---@param bufnr number Buffer number to validate
---@return boolean valid True if buffer can have bookmarks
---@return string|nil error_msg Error message if validation fails
local function validate_buffer_for_bookmarks(bufnr)
	-- Check if buffer exists and is valid
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false, "Invalid buffer"
	end

	-- Get buffer filepath
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	-- Check if buffer has a name
	if filepath == "" then
		return false, "Cannot bookmark unnamed buffer"
	end

	-- Check buffer type (only normal files can have bookmarks)
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" then
		return false, "Cannot bookmark special buffers (terminal, help, etc.)"
	end

	-- Check if buffer is modifiable
	if not vim.bo[bufnr].modifiable then
		return false, "Cannot bookmark read-only buffer"
	end

	-- Check for special buffer schemes (term://, fugitive://, etc.)
	if filepath:match("^%w+://") then
		return false, "Cannot bookmark special buffers (protocol schemes)"
	end

	return true, nil
end

--- Create a bookmark with visual elements and persist it
--- This is a helper function to avoid code duplication between toggle() and annotate()
---@param bufnr number Buffer number
---@param filepath string Normalized absolute file path
---@param line number 1-based line number
---@param note string|nil Optional annotation text
---@return boolean success True if bookmark was created and persisted successfully
local function create_and_persist_bookmark(bufnr, filepath, line, note)
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

	-- Add to in-memory bookmarks first to keep state consistent
	table.insert(bookmarks, new_bookmark)

	-- Save to persistence
	local save_ok = persistence.save_bookmarks(bookmarks)
	if not save_ok then
		-- Rollback: remove from memory and clean up all visual elements
		-- Remove the bookmark we just added (which is at the end of the table)
		table.remove(bookmarks, #bookmarks)

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
---@param bookmark table The bookmark to update
---@param new_note string The new annotation text
---@return boolean success True if bookmark was updated and persisted successfully
local function update_bookmark_annotation(bufnr, line, bookmark, new_note)
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
	local save_ok = persistence.save_bookmarks(bookmarks)
	if not save_ok then
		-- Rollback
		bookmark.note = old_note
		bookmark.annotation_extmark_id = old_annotation_extmark_id
		display.hide_annotation(bufnr, new_extmark_id)

		if old_annotation_extmark_id then
			bookmark.annotation_extmark_id = display.show_annotation(bufnr, line, old_note or "")
		end

		vim.notify("haunt.nvim: Failed to save bookmarks after annotation update", vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Find a bookmark at a specific line in a buffer
---@param bufnr number Buffer number
---@param line number 1-based line number
---@return table|nil bookmark The bookmark at the line, or nil if none exists
---@return number|nil index The index of the bookmark in the bookmarks table
local function get_bookmark_at_line(bufnr, line)
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- If buffer has no name, can't have bookmarks
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

--- Toggle annotation visibility at the current cursor position.
---
--- If a bookmark exists at the current line and has an annotation,
--- this will show/hide the annotation virtual text. If no annotation
--- exists, does nothing.
---
---@return boolean success True if toggled successfully
---
---@usage >lua
---   require('haunt.api').toggle()
--- <
function M.toggle()
	ensure_loaded()
	ensure_modules()

	require("haunt")._ensure_initialized()

	-- Set up autosave autocmds after first bookmark is created
	if not _autosave_setup then
		require("haunt").setup_autocmds()
		_autosave_setup = true
	end

	local bufnr = vim.api.nvim_get_current_buf()

	local valid, error_msg = validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number

	-- Check if a bookmark exists at this line
	local existing_bookmark, _ = get_bookmark_at_line(bufnr, line)
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
	ensure_loaded()
	ensure_modules()

	_annotations_visible = not _annotations_visible

	for _, bookmark in ipairs(bookmarks) do
		if not bookmark.note then
			goto continue
		end

		local bufnr = vim.fn.bufnr(bookmark.file)
		if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
			goto continue
		end

		-- actual toggling logic
		if _annotations_visible then
			bookmark.annotation_extmark_id = display.show_annotation(bufnr, bookmark.line, bookmark.note)
		else
			if bookmark.annotation_extmark_id then
				display.hide_annotation(bufnr, bookmark.annotation_extmark_id)
			end
			bookmark.annotation_extmark_id = nil
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
	ensure_loaded()
	ensure_modules()

	require("haunt")._ensure_initialized()

	local bufnr = vim.api.nvim_get_current_buf()

	local valid, error_msg = validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number

	-- Check if a bookmark exists at this line
	local existing_bookmark, index = get_bookmark_at_line(bufnr, line)
	if not existing_bookmark then
		vim.notify("haunt.nvim: No bookmark on this line", vim.log.levels.INFO)
		return false
	end

	cleanup_bookmark_visuals(bufnr, existing_bookmark)

	table.remove(bookmarks, index)

	-- Save to persistence
	local save_ok = persistence.save_bookmarks(bookmarks)
	if not save_ok then
		vim.notify("haunt.nvim: Failed to save bookmarks after removal", vim.log.levels.ERROR)
		return false
	end

	vim.notify("haunt.nvim: Bookmark deleted", vim.log.levels.INFO)
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
	return vim.deepcopy(bookmarks)
end

--- Restore visual elements (extmarks, signs, annotations) for a bookmark in a loaded buffer
--- This is called when loading bookmarks to recreate visual state
---@param bufnr number Buffer number
---@param bookmark table The bookmark to restore
local function restore_bookmark_display(bufnr, bookmark)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Clean up old extmark if it exists to prevent orphaning
	if bookmark.extmark_id then
		display.delete_bookmark_mark(bufnr, bookmark.extmark_id)
		display.unplace_sign(bufnr, bookmark.extmark_id)
	end

	-- Clean up old annotation extmark if it exists
	if bookmark.annotation_extmark_id then
		display.hide_annotation(bufnr, bookmark.annotation_extmark_id)
	end

	-- Create extmark for line tracking
	local extmark_id = display.set_bookmark_mark(bufnr, bookmark)
	if not extmark_id then
		return
	end

	bookmark.extmark_id = extmark_id

	-- Place sign
	display.place_sign(bufnr, bookmark.line, extmark_id)

	-- Show annotation if it exists and global visibility is enabled
	if bookmark.note and _annotations_visible then
		local annotation_extmark_id = display.show_annotation(bufnr, bookmark.line, bookmark.note)
		bookmark.annotation_extmark_id = annotation_extmark_id
	end
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

	ensure_modules()
	local loaded_bookmarks = persistence.load_bookmarks()
	if loaded_bookmarks then
		bookmarks = loaded_bookmarks
	end
	_loaded = true

	return true
end

--- Restore bookmark visuals for a specific buffer.
---
--- This is called automatically when buffers are opened. You typically
--- don't need to call this manually.
---
---@param bufnr number Buffer number to restore bookmarks for
---@return boolean success True if restoration succeeded or was skipped
function M.restore_buffer_bookmarks(bufnr)
	ensure_loaded()
	ensure_modules()
	require("haunt")._ensure_initialized()

	local valid, _ = validate_buffer_for_bookmarks(bufnr)
	if not valid then
		return true
	end

	-- check if bookmarks have already been restored for this buffer
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, { limit = 1 })

	-- already restored
	if #extmarks > 0 then
		return true
	end

	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))
	if filepath == "" then
		return true
	end

	-- Find all bookmarks for this file
	local buffer_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath then
			table.insert(buffer_bookmarks, bookmark)
		end
	end

	-- early return for no bookmarks
	if #buffer_bookmarks == 0 then
		return true
	end

	-- Restore visual elements for each bookmark
	local success = true
	for _, bookmark in ipairs(buffer_bookmarks) do
		-- this is very go-like
		-- Use pcall to handle race conditions where buffer becomes invalid
		local ok, err = pcall(restore_bookmark_display, bufnr, bookmark)
		if ok then
			goto continue
		end

		-- Log at DEBUG level - this is expected in race conditions
		vim.notify(
			string.format("haunt.nvim: Failed to restore bookmark in %s: %s", bookmark.file, tostring(err)),
			vim.log.levels.DEBUG
		)
		success = false

		::continue::
	end

	return success
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
	local success = persistence.save_bookmarks(bookmarks)
	return success
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
	ensure_loaded()
	ensure_modules()

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
	local valid, error_msg = validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number

	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	local existing_bookmark, _ = get_bookmark_at_line(bufnr, line)

	-- use param if programmatic call, otherwise prompt user
	local annotation = text
	if not annotation then
		local default_text = existing_bookmark and existing_bookmark.note or ""
		annotation = vim.fn.input({
			prompt = "󱙝 Annotation: ",
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
	ensure_loaded()
	ensure_modules()
	local current_file = normalize_filepath(vim.fn.expand("%"))

	if current_file == "" then
		vim.notify("haunt.nvim: No file in current buffer", vim.log.levels.WARN)
		return false
	end

	local file_bookmarks = {}
	local indices_to_remove = {}
	for i, bookmark in ipairs(bookmarks) do
		if bookmark.file == current_file then
			table.insert(file_bookmarks, bookmark)
			table.insert(indices_to_remove, i)
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

	-- Remove bookmarks from in-memory table (in reverse order to avoid index shifting)
	for i = #indices_to_remove, 1, -1 do
		table.remove(bookmarks, indices_to_remove[i])
	end

	local save_ok = persistence.save_bookmarks(bookmarks)

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
	ensure_loaded()
	ensure_modules()

	if #bookmarks == 0 then
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
	--- @type table<string, Bookmark[]>
	local bookmarks_by_file = {}
	for _, bookmark in ipairs(bookmarks) do
		if not bookmarks_by_file[bookmark.file] then
			bookmarks_by_file[bookmark.file] = {}
		end
		table.insert(bookmarks_by_file[bookmark.file], bookmark)
	end

	-- iterate over file -> bookmarks map
	for file_path, file_bookmarks in pairs(bookmarks_by_file) do
		local bufnr = vim.fn.bufnr(file_path)
		if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
			goto continue
		end

		for _, bookmark in ipairs(file_bookmarks) do
			cleanup_bookmark_visuals(bufnr, bookmark)
		end

		::continue::
	end

	-- preclear save
	local count = #bookmarks

	-- clear
	bookmarks = {}

	-- Save empty bookmark list to persistence
	local save_ok = persistence.save_bookmarks(bookmarks)

	if save_ok then
		vim.notify(string.format("haunt.nvim: Cleared all %d bookmark(s)", count), vim.log.levels.INFO)
		return true
	else
		vim.notify("haunt.nvim: Failed to save after clearing all bookmarks", vim.log.levels.ERROR)
		return false
	end
end

---@private
local function get_sorted_bookmarks_for_file(filepath)
	local file_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath then
			table.insert(file_bookmarks, bookmark)
		end
	end

	-- Sort by line number asc
	table.sort(file_bookmarks, function(a, b)
		return a.line < b.line
	end)

	return file_bookmarks
end

---@private
local function navigate_bookmark(direction)
	ensure_loaded()

	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	if filepath == "" then
		vim.notify("haunt.nvim: Cannot navigate bookmarks in unnamed buffer", vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1]
	local current_col = cursor[2]
	local file_bookmarks = get_sorted_bookmarks_for_file(filepath)

	if #file_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks in current buffer", vim.log.levels.INFO)
		return false
	end

	-- closure to keep things tidy
	---@param line number The line to jump to
	local function jump_to(line)
		vim.cmd("normal! m'")
		vim.api.nvim_win_set_cursor(0, { line, current_col })
	end

	if #file_bookmarks == 1 then
		vim.notify("haunt.nvim: Only one bookmark in current buffer", vim.log.levels.INFO)
		jump_to(file_bookmarks[1].line)
		return true
	end

	local is_next = direction == "next"

	-- find neighbor, or wrap around
	if is_next then
		for _, bookmark in ipairs(file_bookmarks) do
			if bookmark.line > current_line then
				jump_to(bookmark.line)
				return true
			end
		end
		jump_to(file_bookmarks[1].line)
	else
		for i = #file_bookmarks, 1, -1 do
			if file_bookmarks[i].line < current_line then
				jump_to(file_bookmarks[i].line)
				return true
			end
		end
		jump_to(file_bookmarks[#file_bookmarks].line)
	end

	return true
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
	return navigate_bookmark("next")
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
	return navigate_bookmark("prev")
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
	ensure_loaded()
	ensure_modules()

	local bookmark, bookmark_index = find_by_id(bookmark_id)
	if not bookmark or not bookmark_index then
		vim.notify("haunt.nvim: Bookmark not found", vim.log.levels.WARN)
		return false
	end

	local bufnr, err = ensure_buffer_for_file(bookmark.file)
	if not bufnr then
		vim.notify("haunt.nvim: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	cleanup_bookmark_visuals(bufnr, bookmark)
	table.remove(bookmarks, bookmark_index)

	local save_ok = persistence.save_bookmarks(bookmarks)
	if not save_ok then
		vim.notify("haunt.nvim: Failed to save bookmarks after deletion", vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Reset internal state for testing purposes only
--- WARNING: This will clear ALL bookmarks from memory without persisting
--- Only use in test environments
---@private
function M._reset_for_testing()
	bookmarks = {}
	_loaded = true -- Prevent auto-loading from disk
	_autosave_setup = false
	_annotations_visible = true
end

return M
