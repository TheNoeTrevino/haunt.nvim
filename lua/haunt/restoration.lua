---@class RestorationModule
---@field restore_buffer_bookmarks fun(bufnr: number, annotations_visible: boolean): boolean
---@field cleanup_buffer_tracking fun(bufnr: number)
---@field reset_tracking fun()

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
---@type HooksModule|nil
local hooks = nil
---@private
local function ensure_modules()
	if not store then
		store = require("haunt.store")
	end
	if not display then
		display = require("haunt.display")
	end
	if not hooks then
		hooks = require("haunt.hooks")
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
		-- The namespace is empty here, so any ids a bookmark still holds are
		-- stale. A reloaded buffer reuses ids from 1, and clearing by a stale
		-- id would delete another bookmark's fresh extmark.
		bookmark.extmark_id = nil
		bookmark.annotation_extmark_id = nil

		-- Use pcall to handle race conditions where buffer becomes invalid
		local ok, rendered = pcall(display.render_bookmark, bufnr, bookmark, annotations_visible)
		if ok and rendered then
			goto continue
		end

		local err = ok and "could not create extmark" or rendered

		-- Log at DEBUG level - this is expected in race conditions
		vim.notify(
			string.format("haunt.nvim: Failed to restore bookmark in %s: %s", bookmark.file, tostring(err)),
			vim.log.levels.DEBUG
		)
		success = false

		::continue::
	end

	---@cast hooks -nil
	hooks.emit_restore({
		bufnr = bufnr,
		file = filepath,
		bookmarks = buffer_bookmarks,
		count = #buffer_bookmarks,
	})

	return success
end

--- Clean up restoration tracking for a deleted buffer
--- This prevents memory leaks in the restored_buffers table
---@param bufnr number Buffer number that was deleted
function M.cleanup_buffer_tracking(bufnr)
	restored_buffers[bufnr] = nil
end

--- Reset all restoration tracking
--- Used when changing data_dir to allow buffers to be re-restored
function M.reset_tracking()
	restored_buffers = {}
end

return M
