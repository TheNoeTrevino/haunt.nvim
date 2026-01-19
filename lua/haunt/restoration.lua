---@class RestorationModule
---@field restore_buffer_bookmarks fun(bufnr: number, annotations_visible: boolean): boolean
---@field cleanup_buffer_tracking fun(bufnr: number)

---@type RestorationModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local utils = require("haunt.utils")

---@private
---@type table<number, boolean>
local restored_buffers = {}

---@private
---@type StoreModule|nil
local store = nil
---@private
---@type DisplayModule|nil
local display = nil

---@private
local function ensure_modules()
	if not store then
		store = require("haunt.store")
	end
	if not display then
		display = require("haunt.display")
	end
end

--- Restore visual elements (extmarks, signs, annotations) for a bookmark in a loaded buffer
--- This is called when loading bookmarks to recreate visual state
---@param bufnr number Buffer number
---@param bookmark Bookmark The bookmark to restore
---@param annotations_visible boolean Whether annotations should be displayed
local function restore_bookmark_display(bufnr, bookmark, annotations_visible)
	ensure_modules()
	---@cast display -nil

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
	if bookmark.note and annotations_visible then
		local annotation_extmark_id = display.show_annotation(bufnr, bookmark.line, bookmark.note)
		bookmark.annotation_extmark_id = annotation_extmark_id
	end
end

--- Restore bookmark visuals for a specific buffer.
---
--- This is called automatically when buffers are opened. You typically
--- don't need to call this manually.
---
---@param bufnr number Buffer number to restore bookmarks for
---@param annotations_visible boolean Whether annotations should be displayed
---@return boolean success True if restoration succeeded or was skipped
function M.restore_buffer_bookmarks(bufnr, annotations_visible)
	ensure_modules()
	---@cast store -nil
	---@cast display -nil

	require("haunt")._ensure_initialized()

	local valid, _ = utils.validate_buffer_for_bookmarks(bufnr)
	if not valid then
		return true
	end

	-- Guard against race condition: check if buffer already restored
	if restored_buffers[bufnr] then
		return true
	end

	-- Mark buffer as restored before doing work to prevent concurrent restoration
	restored_buffers[bufnr] = true

	-- Additional safety check: verify no extmarks exist (shouldn't happen with guard above)
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, { limit = 1 })

	-- already restored
	if #extmarks > 0 then
		return true
	end

	local filepath = utils.normalize_filepath(vim.api.nvim_buf_get_name(bufnr))
	if filepath == "" then
		return true
	end

	-- Find all bookmarks for this file
	local all_bookmarks = store.get_all_raw()
	local buffer_bookmarks = {}
	for _, bookmark in ipairs(all_bookmarks) do
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
		-- Use pcall to handle race conditions where buffer becomes invalid
		local ok, err = pcall(restore_bookmark_display, bufnr, bookmark, annotations_visible)
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

--- Clean up restoration tracking for a deleted buffer
--- This prevents memory leaks in the restored_buffers table
---@param bufnr number Buffer number that was deleted
function M.cleanup_buffer_tracking(bufnr)
	restored_buffers[bufnr] = nil
end

return M
