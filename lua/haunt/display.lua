---@class DisplayModule
---@field get_namespace fun(): number
---@field setup_signs fun(opts: table)
---@field get_config fun(): table
---@field is_initialized fun(): boolean
---@field show_annotation fun(bufnr: number, line: number, note: string): number|nil
---@field hide_annotation fun(bufnr: number, extmark_id: number): boolean
---@field set_bookmark_mark fun(bufnr: number, bookmark: Bookmark): number|nil
---@field get_extmark_line fun(bufnr: number, extmark_id: number): number|nil
---@field delete_bookmark_mark fun(bufnr: number, extmark_id: number)
---@field clear_buffer_marks fun(bufnr: number)
---@field place_sign fun(bufnr: number, line: number, sign_id: number)
---@field unplace_sign fun(bufnr: number, sign_id: number)

---@type DisplayModule
---@diagnostic disable-next-line: missing-fields
local M = {}

-- Lazy namespace creation (create on first use, not at module load)
---@type number|nil
local _namespace = nil

-- Track if highlight groups have been defined
---@type boolean
local _highlights_defined = false

--- Check if a buffer number is valid
---@param bufnr any The value to check
---@return boolean is_valid True if bufnr is a valid buffer number
local function is_valid_buffer(bufnr)
	return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

--- Define custom highlight groups for haunt
--- Creates HauntAnnotation highlight group with sensible defaults
--- Users can override this by defining the highlight group themselves
local function ensure_highlights_defined()
	if _highlights_defined then
		return
	end
	_highlights_defined = true

	-- Only set if not already defined by user
	-- Link to DiagnosticVirtualTextHint which typically has a subtle background
	-- and is semantically appropriate for hint/annotation text
	local existing = vim.api.nvim_get_hl(0, { name = "HauntAnnotation" })
	if vim.tbl_isempty(existing) then
		vim.api.nvim_set_hl(0, "HauntAnnotation", { link = "DiagnosticVirtualTextHint" })
	end
end

--- Get or create the namespace for haunt extmarks
---@return number namespace The namespace ID
function M.get_namespace()
	if not _namespace then
		_namespace = vim.api.nvim_create_namespace("haunt")
	end
	return _namespace
end

local config = require("haunt.config")

-- Track if signs have been defined
---@type boolean
local _signs_defined = false

--- Ensure signs are defined (lazy definition)
--- Only defines signs once when first needed
local function ensure_signs_defined()
	if _signs_defined then
		return
	end
	_signs_defined = true

	local cfg = config.get()
	vim.fn.sign_define("HauntBookmark", {
		text = cfg.sign,
		texthl = cfg.sign_hl,
		linehl = cfg.line_hl or "",
	})
end

--- Setup bookmark signs with vim.fn.sign_define()
--- Creates a "HauntBookmark" sign that can be reused for all bookmarks
--- Lightweight - stores config via config module, doesn't define signs yet
---@param opts? HauntConfig Optional configuration table
---@return nil
function M.setup_signs(opts)
	-- Config is already set up by init.lua, this is just for compatibility
	-- The config module handles merging with defaults
	if opts and not config.is_setup() then
		config.setup(opts)
	end
	-- Don't call sign_define here - it will be called lazily when first needed
end

--- Get the current display configuration
---@return HauntConfig config The current display configuration
function M.get_config()
	return config.get()
end

--- Check if config has been initialized
---@return boolean initialized True if setup has been called
function M.is_initialized()
	return config.is_setup()
end

--- Show annotation as virtual text at the end of a line
---@param bufnr number Buffer number
---@param line number 1-based line number
---@param note string The annotation text to display
---@return number|nil extmark_id The ID of the created extmark, or nil if validation fails
function M.show_annotation(bufnr, line, note)
	ensure_highlights_defined()

	if not is_valid_buffer(bufnr) then
		vim.notify("haunt.nvim: show_annotation: invalid buffer", vim.log.levels.WARN)
		return nil
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line < 1 or line > line_count then
		vim.notify(
			string.format("haunt.nvim: Cannot show annotation at line %d (buffer has %d lines)", line, line_count),
			vim.log.levels.WARN
		)
		return nil
	end

	local cfg = config.get()
	-- some guards
	local hl_group = cfg.virt_text_hl or "HauntAnnotation"
	local prefix = cfg.annotation_prefix or "  "
	local virt_text_pos = cfg.virt_text_pos or "eol"

	-- nvim_buf_set_extmark uses 0-based line numbers
	local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.get_namespace(), line - 1, 0, {
		virt_text = { { prefix .. note, hl_group } },
		virt_text_pos = virt_text_pos,
	})

	return extmark_id
end

--- Hide annotation by removing the extmark
---@param bufnr number Buffer number
---@param extmark_id number The extmark ID to remove
---@return boolean success True if hiding was successful, false otherwise
function M.hide_annotation(bufnr, extmark_id)
	if not is_valid_buffer(bufnr) then
		return false
	end

	-- Try to delete extmark (may fail if extmark doesn't exist, which is OK)
	local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, M.get_namespace(), extmark_id)
	return ok
end

--- Set a bookmark extmark for line tracking
--- Creates an extmark at the bookmark's line that will automatically move with text edits
--- This extmark is separate from the annotation extmark and is used purely for line tracking
---@param bufnr number Buffer number where the bookmark is located
---@param bookmark Bookmark The bookmark data structure
---@return number|nil extmark_id The created extmark ID, or nil if creation failed
function M.set_bookmark_mark(bufnr, bookmark)
	-- Validate inputs
	if not is_valid_buffer(bufnr) then
		vim.notify("haunt.nvim: set_bookmark_mark: invalid buffer number", vim.log.levels.ERROR)
		return nil
	end

	if type(bookmark) ~= "table" or type(bookmark.line) ~= "number" then
		vim.notify("haunt.nvim: set_bookmark_mark: invalid bookmark structure", vim.log.levels.ERROR)
		return nil
	end

	-- Convert from 1-based to 0-based indexing for nvim_buf_set_extmark
	local line = bookmark.line - 1

	-- Check if line is within buffer bounds
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line < 0 or line >= line_count then
		vim.notify(
			string.format(
				"haunt.nvim: set_bookmark_mark: line %d out of bounds (buffer has %d lines)",
				bookmark.line,
				line_count
			),
			vim.log.levels.ERROR
		)
		return nil
	end

	-- Create extmark with right_gravity=false so it stays at the beginning of the line
	-- even when text is inserted at the start of the line
	local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.get_namespace(), line, 0, {
		-- Track line movements automatically
		right_gravity = false,
		-- This extmark is invisible - it's only for tracking the line position
	})

	if not ok then
		vim.notify(
			string.format("haunt.nvim: set_bookmark_mark: failed to create extmark: %s", tostring(extmark_id)),
			vim.log.levels.ERROR
		)
		return nil
	end

	return extmark_id
end

--- Get the current line number for an extmark
--- Queries the extmark position to find where it has moved to
--- This allows bookmarks to stay synced with the buffer as text is edited
---@param bufnr number Buffer number where the extmark is located
---@param extmark_id number The extmark ID to query
---@return number|nil line The current 1-based line number, or nil if extmark not found
function M.get_extmark_line(bufnr, extmark_id)
	-- Validate inputs
	if not is_valid_buffer(bufnr) then
		vim.notify("haunt.nvim: get_extmark_line: invalid buffer number", vim.log.levels.ERROR)
		return nil
	end

	if type(extmark_id) ~= "number" then
		vim.notify("haunt.nvim: get_extmark_line: invalid extmark ID", vim.log.levels.ERROR)
		return nil
	end

	-- Query extmark position
	local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, M.get_namespace(), extmark_id, {})

	if not ok then
		-- Extmark not found or other error
		return nil
	end

	-- pos is a tuple {row, col} where row is 0-indexed
	-- Convert to 1-based line number
	if type(pos) == "table" and type(pos[1]) == "number" then
		return pos[1] + 1
	end

	return nil
end

--- Delete a bookmark extmark
--- Removes the extmark from the buffer when a bookmark is deleted
---@param bufnr number Buffer number where the extmark is located
---@param extmark_id number The extmark ID to delete
---@return boolean success True if deletion was successful, false otherwise
function M.delete_bookmark_mark(bufnr, extmark_id)
	-- Validate inputs
	if not is_valid_buffer(bufnr) then
		vim.notify("haunt.nvim: delete_bookmark_mark: invalid buffer number", vim.log.levels.ERROR)
		return false
	end

	if type(extmark_id) ~= "number" then
		vim.notify("haunt.nvim: delete_bookmark_mark: invalid extmark ID", vim.log.levels.ERROR)
		return false
	end

	-- Delete the extmark
	local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, M.get_namespace(), extmark_id)

	if not ok then
		vim.notify(
			string.format("haunt.nvim: delete_bookmark_mark: failed to delete extmark %d", extmark_id),
			vim.log.levels.WARN
		)
		return false
	end

	return true
end

--- Clear all bookmark extmarks from a buffer
--- Useful when reloading bookmarks or clearing all bookmarks
---@param bufnr number Buffer number to clear extmarks from
---@return boolean success True if clearing was successful, false otherwise
function M.clear_buffer_marks(bufnr)
	-- Validate input
	if not is_valid_buffer(bufnr) then
		vim.notify("haunt.nvim: clear_buffer_marks: invalid buffer number", vim.log.levels.ERROR)
		return false
	end

	-- Clear all extmarks in the namespace for this buffer
	local ok = pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.get_namespace(), 0, -1)

	if not ok then
		vim.notify("haunt.nvim: clear_buffer_marks: failed to clear extmarks", vim.log.levels.ERROR)
		return false
	end

	return true
end

-- Sign group name for organizing haunt signs
local SIGN_GROUP = "haunt_signs"

--- Place a sign at a specific line in a buffer
---@param bufnr number Buffer number
---@param line number 1-based line number
---@param sign_id number Unique sign ID
function M.place_sign(bufnr, line, sign_id)
	ensure_signs_defined()
	vim.fn.sign_place(sign_id, SIGN_GROUP, "HauntBookmark", bufnr, { lnum = line, priority = 10 })
end

--- Remove a sign from a buffer
---@param bufnr number Buffer number
---@param sign_id number Sign ID to remove
function M.unplace_sign(bufnr, sign_id)
	vim.fn.sign_unplace(SIGN_GROUP, {
		buffer = bufnr,
		id = sign_id,
	})
end

return M
