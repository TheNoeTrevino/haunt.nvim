---@toc_entry Picker Utilities
---@tag haunt-picker-utils
---@text
--- # Picker Utilities ~
---
--- Shared utilities for all picker implementations.
--- This module provides common functions used by Snacks, Telescope, and fallback pickers.

---@class PickerUtils
---@field ensure_modules fun()
---@field get_api fun(): ApiModule
---@field get_haunt fun(): HauntModule
---@field with_buffer_context fun(bufnr: number, line: number, callback: function): any
---@field build_picker_items fun(bookmarks: Bookmark[]): PickerItem[]
---@field line_label fun(line: number, end_line?: number): string
---@field jump_to_bookmark fun(item: PickerItem)
---@field handle_edit_annotation fun(ctx: EditAnnotationContext)

---@type PickerUtils
---@diagnostic disable-next-line: missing-fields
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

--- Format a bookmark's lines for a picker label: `45`, or `45–48` for a range
---@param line number 1-based first line
---@param end_line? number 1-based last line of a range
---@return string label
function M.line_label(line, end_line)
	if end_line then
		return string.format("%d–%d", line, end_line)
	end
	return tostring(line)
end

---@private
--- Byte length of a line, from its loaded buffer or else the file on disk
---@param file string Absolute file path
---@param lnum number 1-based line number
---@return number|nil length Nil when the line cannot be read
local function line_length(file, lnum)
	local bufnr = vim.fn.bufnr(file)
	if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
		local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
		return line and #line or nil
	end
	local ok, lines = pcall(vim.fn.readfile, file, "", lnum)
	local line = ok and lines[lnum] or nil
	return line and #line or nil
end

--- Build picker items from bookmarks
---@param bookmarks Bookmark[]
---@return PickerItem[]
function M.build_picker_items(bookmarks)
	local items = {}
	for i, bm in ipairs(bookmarks) do
		local relpath = vim.fn.fnamemodify(bm.file, ":.")
		local filename = vim.fn.fnamemodify(bm.file, ":t")
		local text = relpath .. ":" .. M.line_label(bm.line, bm.end_line)
		if bm.note and bm.note ~= "" then
			text = text .. " " .. bm.note
		end
		-- Previews highlight the whole range, through the end of its last line
		local end_pos = nil
		if bm.end_line then
			local len = line_length(bm.file, bm.end_line)
			end_pos = len and { bm.end_line, len } or nil
		end
		table.insert(items, {
			idx = i,
			score = i,
			file = bm.file,
			relpath = relpath,
			filename = filename,
			pos = { bm.line, 0 },
			end_pos = end_pos,
			text = text,
			note = bm.note,
			id = bm.id,
			line = bm.line,
			end_line = bm.end_line,
		})
	end
	return items
end

--- Jump to a bookmark item (shared logic for all pickers)
---@param item PickerItem The selected bookmark item
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

--- Handle editing a bookmark annotation (shared across picker implementations)
---@param ctx EditAnnotationContext
function M.handle_edit_annotation(ctx)
	local api_module = M.get_api()
	local item = ctx.item

	if not item then
		return
	end

	local default_text = item.note or ""

	-- Close picker temporarily to show input prompt clearly
	ctx.close_picker()

	local annotation = vim.fn.input({
		prompt = "Annotation: ",
		default = default_text,
	})

	-- If user cancelled (ESC) with no existing annotation, reopen picker
	if annotation == "" and default_text == "" then
		ctx.reopen_picker()
		return
	end

	-- By id, not by line: several bookmarks can start on one line
	api_module.annotate_by_id(item.id, annotation)

	-- Reopen the picker with updated data
	ctx.reopen_picker()
end

return M
