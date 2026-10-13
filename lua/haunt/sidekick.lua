---@toc_entry Sidekick
---@tag haunt-sidekick
---@text
--- # Sidekick ~
---
--- Integration with sidekick.nvim (https://github.com/folke/sidekick.nvim).
--- Provides bookmark locations in a format compatible with sidekick's location system.
---

---@class SidekickModule
---@field get_locations fun(opts?: SidekickOpts): string

---@private
---@type SidekickModule
---@diagnostic disable-next-line: missing-fields
local M = {}

---@class SidekickOpts
---@field current_buffer? boolean If true, return only bookmarks for the current buffer (default: false)
---@field append_annotations? boolean If true, append annotation text to each location (default: true)

---@private
--- Convert an absolute path to a relative path from the cwd
---@param absolute_path string The absolute file path
---@return string relative_path The path relative to cwd
local function to_relative_path(absolute_path)
	local relative = vim.fn.fnamemodify(absolute_path, ":.")
	-- If the path couldn't be made relative (e.g., different drive on Windows),
	-- return the original path
	if relative == "" then
		return absolute_path
	end
	return relative
end

--- Get bookmark locations formatted for sidekick.nvim.
---
--- Returns bookmarks in sidekick-compatible format:
--- `- @/{path} :L{line} - "{note}"`, or `:L{line}-L{end_line}` for a range
---
---@param opts? SidekickOpts Options for filtering and formatting
---@return string # Formatted bookmark locations, one per line
---
---@usage >lua
---   -- Get all bookmarks
---   local sidekick = require('haunt.sidekick')
---   local locations = sidekick.get_locations()
---
---   -- Get only current buffer bookmarks
---   local current = sidekick.get_locations({ current_buffer = true })
---<
function M.get_locations(opts)
	opts = opts or {}

	-- Default append_annotations to true
	local append_annotations = opts.append_annotations
	if append_annotations == nil then
		append_annotations = true
	end

	local current_buffer = opts.current_buffer or false

	-- Get all bookmarks from the API
	local api = require("haunt.api")
	local bookmarks = api.get_bookmarks()

	-- If no bookmarks, return empty string
	if #bookmarks == 0 then
		return ""
	end

	-- Filter to current buffer if requested
	if current_buffer then
		local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
		bookmarks = vim
			.iter(bookmarks)
			---@param bookmark Bookmark
			:filter(function(bookmark)
				return bookmark.file == current_file
			end)
			:totable()
	end

	-- If no bookmarks after filtering, return empty string
	if #bookmarks == 0 then
		return ""
	end

	-- Sort bookmarks by file path, then by line number
	table.sort(bookmarks, function(a, b)
		if a.file == b.file then
			return a.line < b.line
		end
		return a.file < b.file
	end)

	-- Format each bookmark
	local lines = vim
		.iter(bookmarks)
		---@param bookmark Bookmark
		:map(function(bookmark)
			local relative_path = to_relative_path(bookmark.file)
			local line_str = string.format("- @/%s :L%d", relative_path, bookmark.line)
			-- Same range form sidekick.nvim writes for a line range
			if bookmark.end_line then
				line_str = line_str .. string.format("-L%d", bookmark.end_line)
			end

			-- Append annotation if requested and exists
			if append_annotations and bookmark.note and bookmark.note ~= "" then
				line_str = line_str .. string.format(' - "%s"', bookmark.note)
			end

			return line_str
		end)
		:totable()

	return table.concat(lines, "\n")
end

return M
