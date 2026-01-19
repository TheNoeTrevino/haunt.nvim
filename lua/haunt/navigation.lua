---@class NavigationModule
---@field next fun(): boolean
---@field prev fun(): boolean

---@type NavigationModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local utils = require("haunt.utils")

---@private
---@type StoreModule|nil
local store = nil

---@private
local function ensure_store()
	if not store then
		store = require("haunt.store")
	end
end

---@private
---@param direction "next"|"prev"
---@return boolean success True if jumped to a bookmark
local function navigate_bookmark(direction)
	ensure_store()
	---@cast store -nil

	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = utils.normalize_filepath(vim.api.nvim_buf_get_name(bufnr))

	if filepath == "" then
		vim.notify("haunt.nvim: Cannot navigate bookmarks in unnamed buffer", vim.log.levels.WARN)
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1]
	local current_col = cursor[2]
	local file_bookmarks = store.get_sorted_bookmarks_for_file(filepath)

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
function M.next()
	return navigate_bookmark("next")
end

--- Jump to the previous bookmark in the current buffer.
---
--- Wraps around to the last bookmark if at the beginning.
---
---@return boolean success True if jumped to a bookmark
function M.prev()
	return navigate_bookmark("prev")
end

return M
