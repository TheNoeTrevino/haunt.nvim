---@toc_entry Picker Utilities
---@tag haunt-picker-utils
---@text
--- # Picker Utilities ~
---
--- Shared utilities for all picker implementations.
--- This module provides common functions used by Snacks, Telescope, and fallback pickers.

---@private
local M = {}

---@private
---@type ApiModule|nil
local api = nil
---@private
---@type HauntModule|nil
local haunt = nil

---@private
function M.ensure_modules()
	if not api then
		api = require("haunt.api")
	end
	if not haunt then
		haunt = require("haunt")
	end
end

--- Get the API module
---@return ApiModule
function M.get_api()
	M.ensure_modules()
	---@cast api -nil
	return api
end

--- Get the haunt module
---@return HauntModule
function M.get_haunt()
	M.ensure_modules()
	---@cast haunt -nil
	return haunt
end

--- Execute a callback with buffer context temporarily switched
--- Switches to the target buffer, sets cursor position, executes callback, then safely restores
--- Uses pcall and validation to prevent errors when restoring picker buffer state
---@param bufnr number Target buffer number
---@param line number Line number to set cursor to
---@param callback function Function to execute in the target buffer context
---@return any The return value of the callback
function M.with_buffer_context(bufnr, line, callback)
	-- Save current buffer and window
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()
	local cursor_saved = vim.api.nvim_win_get_cursor(current_win)

	-- Ensure target buffer is loaded
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		vim.fn.bufload(bufnr)
	end

	-- Switch to target buffer
	vim.api.nvim_set_current_buf(bufnr)

	-- Move cursor to the bookmark line (with validation)
	-- Clamp line to valid range to avoid "Cursor position outside buffer" error
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local safe_line = math.min(math.max(1, line), line_count)
	pcall(vim.api.nvim_win_set_cursor, current_win, { safe_line, 0 })

	-- Execute the callback
	local result = callback()

	-- Safely restore original buffer with validation
	-- The picker buffer might not be in a valid state to restore, so use pcall
	if vim.api.nvim_buf_is_valid(current_bufnr) and vim.api.nvim_buf_is_loaded(current_bufnr) then
		-- Attempt to restore buffer - use pcall to handle any state errors
		pcall(vim.api.nvim_set_current_buf, current_bufnr)

		-- Only restore cursor if we successfully switched back to the original buffer
		if vim.api.nvim_get_current_buf() == current_bufnr then
			pcall(vim.api.nvim_win_set_cursor, current_win, cursor_saved)
		end
	end

	return result
end

--- Build picker items from bookmarks
---@param bookmarks Bookmark[]
---@return table[]
function M.build_picker_items(bookmarks)
	local items = {}
	for i, bm in ipairs(bookmarks) do
		local text = vim.fn.fnamemodify(bm.file, ":.") .. ":" .. bm.line
		if bm.note and bm.note ~= "" then
			text = text .. " " .. bm.note
		end
		table.insert(items, {
			idx = i,
			score = i,
			file = bm.file,
			pos = { bm.line, 0 },
			text = text,
			note = bm.note,
			id = bm.id,
			line = bm.line,
		})
	end
	return items
end

--- Jump to a bookmark item (shared logic for all pickers)
---@param item table The selected bookmark item
function M.jump_to_bookmark(item)
	if not item then
		return
	end

	-- Open file
	local bufnr = vim.fn.bufnr(item.file)
	if bufnr == -1 then
		-- File not loaded, open it
		vim.cmd("edit " .. vim.fn.fnameescape(item.file))
	else
		-- File already loaded, switch to it
		vim.cmd("buffer " .. bufnr)
	end

	-- Go to line and center
	vim.api.nvim_win_set_cursor(0, { item.line, 0 })
	vim.cmd("normal! zz")
end

return M
