---@class haunt.Api
local M = {}

-- Module-level variable to store bookmarks in memory
local bookmarks = {}

-- Required modules (loaded lazily)
---@type table?
local persistence = nil
---@type table?
local display = nil

--- Lazy load required modules
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

--- Find a bookmark at a specific line in a buffer
---@param bufnr number Buffer number
---@param line number 1-based line number
---@return table|nil bookmark The bookmark at the line, or nil if none exists
---@return number|nil index The index of the bookmark in the bookmarks table
local function get_bookmark_at_line(bufnr, line)
	-- Get the absolute file path for the buffer
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

--- Toggle a bookmark at the current cursor position
--- Adds a bookmark if none exists, removes if one already exists
---@return boolean success True if operation succeeded, false otherwise
function M.toggle()
	ensure_modules()

	-- Get current buffer
	local bufnr = vim.api.nvim_get_current_buf()

	-- Validate buffer can have bookmarks
	local valid, error_msg = validate_buffer_for_bookmarks(bufnr)
	if not valid then
		vim.notify("haunt.nvim: " .. error_msg, vim.log.levels.WARN)
		return false
	end

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] -- 1-based line number

	-- Get the absolute file path (normalized)
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if a bookmark exists at this line
	local existing_bookmark, index = get_bookmark_at_line(bufnr, line)

	if existing_bookmark then
		-- Remove existing bookmark
		cleanup_bookmark_visuals(bufnr, existing_bookmark)

		-- Remove from bookmarks table
		table.remove(bookmarks, index)

		-- Save to persistence
		local save_ok = persistence.save_bookmarks(bookmarks)
		if not save_ok then
			vim.notify("haunt.nvim: Failed to save bookmarks after removal", vim.log.levels.ERROR)
			return false
		end

		vim.notify("haunt.nvim: Bookmark removed", vim.log.levels.INFO)
		return true
	else
		-- Add new bookmark
		local success = create_and_persist_bookmark(bufnr, filepath, line, nil)
		if success then
			vim.notify("haunt.nvim: Bookmark added", vim.log.levels.INFO)
		end
		return success
	end
end

--- Get all bookmarks
---@return table bookmarks Array of all bookmarks
function M.get_bookmarks()
	return vim.deepcopy(bookmarks)
end

--- Update a bookmark's line number
--- This should be called by the display layer when extmarks move
---@param filepath string Absolute path to the file
---@param old_line number The old 1-based line number
---@param new_line number The new 1-based line number
---@return boolean success True if update succeeded, false otherwise
function M.update_bookmark_line(filepath, old_line, new_line)
	-- Find the bookmark at the old line
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath and bookmark.line == old_line then
			-- Update the line number
			bookmark.line = new_line
			return true
		end
	end
	return false
end

--- Synchronize bookmark positions with their extmarks
--- Checks if extmarks have moved and updates bookmark line numbers and sign positions
--- This function is called on text changes to keep bookmarks in sync
---@param bufnr number Buffer number to synchronize
function M.sync_extmark_positions(bufnr)
	ensure_modules()

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))
	if filepath == "" then
		return
	end

	-- Find all bookmarks for this buffer
	local buffer_bookmarks = {}
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath and bookmark.extmark_id then
			table.insert(buffer_bookmarks, bookmark)
		end
	end

	-- Update each bookmark's position
	for _, bookmark in ipairs(buffer_bookmarks) do
		local current_line = display.get_extmark_line(bufnr, bookmark.extmark_id)

		if current_line and current_line ~= bookmark.line then
			-- Remove old sign
			display.unplace_sign(bufnr, bookmark.extmark_id)

			-- Update bookmark line number
			bookmark.line = current_line

			-- Place sign at new position
			display.place_sign(bufnr, current_line, bookmark.extmark_id)

			-- Note: Annotation position updates automatically via extmarks
		end
	end
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
	if extmark_id then
		bookmark.extmark_id = extmark_id

		-- Place sign
		display.place_sign(bufnr, bookmark.line, extmark_id)

		-- Show annotation if it exists
		if bookmark.note then
			local annotation_extmark_id = display.show_annotation(bufnr, bookmark.line, bookmark.note)
			bookmark.annotation_extmark_id = annotation_extmark_id
		end
	end
end

--- Load bookmarks from persistence
--- This should be called when the plugin is initialized
---@return boolean success True if load succeeded, false otherwise
function M.load()
	ensure_modules()

	local loaded_bookmarks = persistence.load_bookmarks()
	if loaded_bookmarks then
		bookmarks = loaded_bookmarks

		-- Restore visual elements for bookmarks in currently open buffers
		for _, bookmark in ipairs(bookmarks) do
			local bufnr = vim.fn.bufnr(bookmark.file)
			if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
				-- Use pcall to handle race condition where buffer becomes invalid
				-- between the check above and the restore call
				local ok, err = pcall(restore_bookmark_display, bufnr, bookmark)
				if not ok then
					vim.notify(
						string.format("haunt.nvim: Failed to restore bookmark in %s: %s", bookmark.file, tostring(err)),
						vim.log.levels.WARN
					)
				end
			end
		end

		return true
	end

	return false
end

--- Save bookmarks to persistence
--- This can be called manually to force a save
---@return boolean success True if save succeeded, false otherwise
function M.save()
	ensure_modules()

	return persistence.save_bookmarks(bookmarks)
end

--- Annotate a bookmark at the current cursor position
--- If a bookmark already exists at the current line, pre-fill the input with its note
--- If no bookmark exists, create a new one with the annotation
--- Empty input will keep existing annotation or not create bookmark
---@param text? string Optional annotation text. If provided, skips user input prompt
---@return boolean success True if operation succeeded, false otherwise
function M.annotate(text)
	ensure_modules()

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

	-- Get the absolute file path (normalized)
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if a bookmark exists at this line
	local existing_bookmark, _ = get_bookmark_at_line(bufnr, line)

	-- Get annotation text
	local annotation
	if text then
		-- Use provided text (for programmatic calls)
		annotation = text
	else
		-- Prompt user for annotation
		local default_text = ""
		if existing_bookmark and existing_bookmark.note then
			default_text = existing_bookmark.note
		end

		annotation = vim.fn.input({
			prompt = "Annotation: ",
			default = default_text,
		})

		-- Handle empty input
		-- If user enters empty string, it could mean:
		-- 1. They cancelled (ESC)
		-- 2. They want to clear the annotation
		-- We treat empty string as cancel - keep existing or don't create new
		if annotation == "" then
			return false
		end
	end

	-- Update or create bookmark
	if existing_bookmark then
		-- Store old values for rollback
		local old_note = existing_bookmark.note
		local old_annotation_extmark_id = existing_bookmark.annotation_extmark_id

		-- Update visual text display first
		-- Hide old annotation if it exists
		if existing_bookmark.annotation_extmark_id then
			display.hide_annotation(bufnr, existing_bookmark.annotation_extmark_id)
		end

		-- Show new annotation
		local new_extmark_id = display.show_annotation(bufnr, line, annotation)

		-- Update bookmark's note and extmark temporarily for saving
		existing_bookmark.note = annotation
		existing_bookmark.annotation_extmark_id = new_extmark_id

		-- Save to persistence
		local save_ok = persistence.save_bookmarks(bookmarks)
		if not save_ok then
			-- Rollback: restore old values and visual state
			existing_bookmark.note = old_note
			existing_bookmark.annotation_extmark_id = old_annotation_extmark_id

			-- Hide the new annotation we just created
			display.hide_annotation(bufnr, new_extmark_id)

			-- Restore old annotation if it existed
			if old_annotation_extmark_id then
				local restored_extmark_id = display.show_annotation(bufnr, line, old_note or "")
				existing_bookmark.annotation_extmark_id = restored_extmark_id
			end

			vim.notify("haunt.nvim: Failed to save bookmarks after annotation update", vim.log.levels.ERROR)
			return false
		end

		vim.notify("haunt.nvim: Annotation updated", vim.log.levels.INFO)
		return true
	else
		-- Create new bookmark with annotation
		local success = create_and_persist_bookmark(bufnr, filepath, line, annotation)
		if success then
			vim.notify("haunt.nvim: Bookmark created with annotation", vim.log.levels.INFO)
		end
		return success
	end
end

--- Clear all bookmarks in the current file
---@return boolean success True if cleared successfully
function M.clear()
	ensure_modules()

	-- Get current buffer path (normalized)
	local current_file = normalize_filepath(vim.fn.expand("%"))

	if current_file == "" then
		vim.notify("haunt.nvim: No file in current buffer", vim.log.levels.WARN)
		return false
	end

	-- Find all bookmarks for the current file
	local file_bookmarks = {}
	local indices_to_remove = {}

	for i, bookmark in ipairs(bookmarks) do
		if bookmark.file == current_file then
			table.insert(file_bookmarks, bookmark)
			table.insert(indices_to_remove, i)
		end
	end

	-- Check if there are any bookmarks in this file
	if #file_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks to clear in current file", vim.log.levels.INFO)
		return true
	end

	-- Get current buffer number
	local bufnr = vim.api.nvim_get_current_buf()

	-- Delete extmarks and signs for each bookmark
	for _, bookmark in ipairs(file_bookmarks) do
		cleanup_bookmark_visuals(bufnr, bookmark)
	end

	-- Remove bookmarks from in-memory table (in reverse order to avoid index shifting)
	for i = #indices_to_remove, 1, -1 do
		table.remove(bookmarks, indices_to_remove[i])
	end

	local count = #file_bookmarks

	-- Save to persistence
	local save_ok = persistence.save_bookmarks(bookmarks)

	if save_ok then
		vim.notify(string.format("haunt.nvim: Cleared %d bookmark(s) from current file", count), vim.log.levels.INFO)
		return true
	else
		vim.notify("haunt.nvim: Failed to save after clearing bookmarks", vim.log.levels.ERROR)
		return false
	end
end

--- Clear all bookmarks in the project/branch
---@return boolean success True if cleared successfully
function M.clear_all()
	ensure_modules()

	-- Check if there are any bookmarks
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks to clear", vim.log.levels.INFO)
		return true
	end

	-- Show confirmation prompt
	local choice = vim.fn.confirm("Clear all bookmarks?", "&Yes\n&No", 2)

	-- If user chose No (2) or cancelled (0)
	if choice ~= 1 then
		vim.notify("haunt.nvim: Clear all cancelled", vim.log.levels.INFO)
		return false
	end

	-- Group bookmarks by file to find corresponding buffers
	local bookmarks_by_file = {}
	for _, bookmark in ipairs(bookmarks) do
		if not bookmarks_by_file[bookmark.file] then
			bookmarks_by_file[bookmark.file] = {}
		end
		table.insert(bookmarks_by_file[bookmark.file], bookmark)
	end

	-- Clear extmarks and signs from all buffers
	for file_path, file_bookmarks in pairs(bookmarks_by_file) do
		-- Try to find the buffer for this file
		local bufnr = vim.fn.bufnr(file_path)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			for _, bookmark in ipairs(file_bookmarks) do
				cleanup_bookmark_visuals(bufnr, bookmark)
			end
		end
	end

	-- Store count before clearing
	local count = #bookmarks

	-- Clear in-memory bookmarks
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

--- Get bookmarks for a specific file, sorted by line number
---@param filepath string Absolute path to the file
---@return table[] bookmarks Array of bookmarks for the file, sorted by line number
local function get_sorted_bookmarks_for_file(filepath)
	local file_bookmarks = {}

	-- Filter bookmarks for this file
	for _, bookmark in ipairs(bookmarks) do
		if bookmark.file == filepath then
			table.insert(file_bookmarks, bookmark)
		end
	end

	-- Sort by line number (ascending)
	table.sort(file_bookmarks, function(a, b)
		return a.line < b.line
	end)

	return file_bookmarks
end

--- Jump to the next bookmark in the current buffer
--- Wraps around to the first bookmark if at the end
---@return boolean success True if jumped to a bookmark, false otherwise
function M.next()
	-- Get current buffer
	local bufnr = vim.api.nvim_get_current_buf()

	-- Get the absolute file path (normalized)
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if buffer has a name
	if filepath == "" then
		vim.notify("haunt.nvim: Cannot navigate bookmarks in unnamed buffer", vim.log.levels.WARN)
		return false
	end

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based line number

	-- Get sorted bookmarks for this file
	local file_bookmarks = get_sorted_bookmarks_for_file(filepath)

	-- Handle edge case: no bookmarks in this file
	if #file_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks in current buffer", vim.log.levels.INFO)
		return false
	end

	-- Handle edge case: only one bookmark
	if #file_bookmarks == 1 then
		vim.notify("haunt.nvim: Only one bookmark in current buffer", vim.log.levels.INFO)
		-- Jump to it anyway
		vim.api.nvim_win_set_cursor(0, { file_bookmarks[1].line, 0 })
		return true
	end

	-- Find next bookmark after current line
	for _, bookmark in ipairs(file_bookmarks) do
		if bookmark.line > current_line then
			-- Found next bookmark, jump to it
			vim.api.nvim_win_set_cursor(0, { bookmark.line, 0 })
			return true
		end
	end

	-- No bookmark found after current line, wrap to first bookmark
	vim.api.nvim_win_set_cursor(0, { file_bookmarks[1].line, 0 })
	return true
end

--- Jump to the previous bookmark in the current buffer
--- Wraps around to the last bookmark if at the beginning
---@return boolean success True if jumped to a bookmark, false otherwise
function M.prev()
	-- Get current buffer
	local bufnr = vim.api.nvim_get_current_buf()

	-- Get the absolute file path (normalized)
	local filepath = normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	-- Check if buffer has a name
	if filepath == "" then
		vim.notify("haunt.nvim: Cannot navigate bookmarks in unnamed buffer", vim.log.levels.WARN)
		return false
	end

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based line number

	-- Get sorted bookmarks for this file
	local file_bookmarks = get_sorted_bookmarks_for_file(filepath)

	-- Handle edge case: no bookmarks in this file
	if #file_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks in current buffer", vim.log.levels.INFO)
		return false
	end

	-- Handle edge case: only one bookmark
	if #file_bookmarks == 1 then
		vim.notify("haunt.nvim: Only one bookmark in current buffer", vim.log.levels.INFO)
		-- Jump to it anyway
		vim.api.nvim_win_set_cursor(0, { file_bookmarks[1].line, 0 })
		return true
	end

	-- Find previous bookmark before current line (iterate backwards)
	for i = #file_bookmarks, 1, -1 do
		local bookmark = file_bookmarks[i]
		if bookmark.line < current_line then
			-- Found previous bookmark, jump to it
			vim.api.nvim_win_set_cursor(0, { bookmark.line, 0 })
			return true
		end
	end

	-- No bookmark found before current line, wrap to last bookmark
	vim.api.nvim_win_set_cursor(0, { file_bookmarks[#file_bookmarks].line, 0 })
	return true
end

return M
