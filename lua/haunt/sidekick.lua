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
---@field yank_locations fun(opts?: SidekickOpts): boolean

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
--- `- @/{path} :L{line} - "{note}"`
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
		local filtered = {}
		for _, bookmark in ipairs(bookmarks) do
			if bookmark.file == current_file then
				table.insert(filtered, bookmark)
			end
		end
		bookmarks = filtered
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
	local lines = {}
	for _, bookmark in ipairs(bookmarks) do
		local relative_path = to_relative_path(bookmark.file)
		local line_str = string.format("- @/%s :L%d", relative_path, bookmark.line)

		-- Append annotation if requested and exists
		if append_annotations and bookmark.note and bookmark.note ~= "" then
			line_str = line_str .. string.format(' - "%s"', bookmark.note)
		end

		table.insert(lines, line_str)
	end

	return table.concat(lines, "\n")
end

--- Yank bookmark locations to the unnamedplus register.
---
--- Retrieves all bookmarks formatted for sidekick and copies them to the
--- unnamedplus register (system clipboard). Works as a fallback when
--- sidekick.nvim is not installed by providing direct access to formatted
--- bookmark locations.
---
---@param opts? SidekickOpts Options for filtering and formatting
---@return boolean success True if yank was successful, false otherwise
---
---@usage >lua
---   -- made for those who won't (for whatever reason) install sidekick.nvim
---   local haunt_sk = require('haunt.sidekick')
---   haunt_sk.yank_locations()
---
---   -- Yank only current buffer bookmarks
---   haunt_sk.yank_locations({ current_buffer = true })
---
---   -- Then go paste into the cli tool, manually
---<
function M.yank_locations(opts)
	opts = opts or {}

	local locations = M.get_locations(opts)

	if locations == "" then
		vim.notify("No bookmarks to yank", vim.log.levels.WARN)
		return false
	end

	vim.fn.setreg("+", locations)

	local count = select(2, locations:gsub("\n", "\n")) + 1
	vim.notify(string.format("Yanked %d bookmark location(s) to clipboard", count), vim.log.levels.INFO)

	return true
end

return M
