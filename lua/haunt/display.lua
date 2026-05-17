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
---@field clear_buffer_signs fun(bufnr: number): boolean
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
local function define_highlights()
	local existing = vim.api.nvim_get_hl(0, { name = "HauntAnnotation" })
	if vim.tbl_isempty(existing) then
		vim.api.nvim_set_hl(0, "HauntAnnotation", { link = "DiagnosticVirtualTextHint" })
	end

	local existing_border = vim.api.nvim_get_hl(0, { name = "HauntAnnotationBorder" })
	if vim.tbl_isempty(existing_border) then
		vim.api.nvim_set_hl(0, "HauntAnnotationBorder", { link = "FloatBorder" })
	end
end

local function ensure_highlights_defined()
	if _highlights_defined then
		return
	end
	_highlights_defined = true

	define_highlights()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("haunt_highlights", { clear = true }),
		callback = define_highlights,
		desc = "Re-apply HauntAnnotation highlight after colorscheme change",
	})
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

--- Word-wrap a string to fit within max_width display columns.
--- Breaks at word boundaries when possible, hard-breaks otherwise.
---@param text string The text to wrap
---@param max_width number Maximum display width per line
---@return string[] wrapped The wrapped lines
local function wrap_text(text, max_width)
	max_width = tonumber(max_width) or 1
	if max_width < 1 then
		max_width = 1
	end

	if vim.fn.strdisplaywidth(text) <= max_width then
		return { text }
	end

	local result = {}
	local remaining = text

	while vim.fn.strdisplaywidth(remaining) > max_width do
		local cut
		local hard_cut = 0
		local char_count = vim.fn.strchars(remaining)

		-- Find the last space that fits within max_width.
		for i = 1, char_count do
			local segment = vim.fn.strcharpart(remaining, 0, i)
			if vim.fn.strdisplaywidth(segment) > max_width then
				break
			end
			hard_cut = i
			if vim.fn.strcharpart(remaining, i - 1, 1) == " " then
				cut = i
			end
		end

		if not cut then
			-- No space found, so hard-break at max_width.
			cut = math.max(hard_cut, 1)
		end

		table.insert(result, vim.fn.strcharpart(remaining, 0, cut))
		remaining = vim.fn.strcharpart(remaining, cut)
	end

	if #remaining > 0 then
		table.insert(result, remaining)
	end

	return result
end

local BORDER_PRESETS = {
	rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
	single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
	double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
}

--- Resolve a border spec (preset string or array) into an 8-element array of {char, hl} pairs.
--- Accepts preset strings ("rounded", "single", "double", "none") or an array of characters
--- whose length divides 8 (cycled to fill all 8 positions). Each element can be a string or
--- {char, hl_group}.
---@param spec string|string[]|(string|string[])[]|nil
---@param default_hl string Fallback highlight group when the element doesn't specify one
---@return {[1]: string, [2]: string}[] border 8 elements: {char, hl_group}
local function resolve_border(spec, default_hl)
	if spec == nil or spec == "rounded" then
		spec = BORDER_PRESETS.rounded
	elseif type(spec) == "string" then
		if spec == "none" then
			return vim.fn["repeat"]({ { "", default_hl } }, 8)
		end
		local preset = BORDER_PRESETS[spec]
		if not preset then
			vim.notify(
				string.format("haunt.nvim: unknown above_border preset %q, falling back to 'rounded'", spec),
				vim.log.levels.WARN
			)
			preset = BORDER_PRESETS.rounded
		end
		spec = preset
	end

	if type(spec) ~= "table" or #spec == 0 then
		vim.notify("haunt.nvim: invalid above_border value, falling back to 'rounded'", vim.log.levels.WARN)
		spec = BORDER_PRESETS.rounded
	elseif 8 % #spec ~= 0 then
		vim.notify(
			string.format(
				"haunt.nvim: above_border array length %d does not divide 8, falling back to 'rounded'",
				#spec
			),
			vim.log.levels.WARN
		)
		spec = BORDER_PRESETS.rounded
	end

	local raw = spec
	local n = #raw
	local out = {}
	for i = 1, 8 do
		local elem = raw[((i - 1) % n) + 1]
		if type(elem) == "table" then
			out[i] = { elem[1] or "", elem[2] or default_hl }
		else
			out[i] = { elem or "", default_hl }
		end
	end
	return out
end

--- Build virtual lines for a boxed annotation displayed above the target line
---@param note string The annotation text (may contain newlines)
---@param prefix string Text to display before the first line (e.g. icon)
---@param hl_group string Highlight group for the content
---@param border table Resolved 8-element border array from resolve_border()
---@param wrap_at number Max content width before wrapping
---@return table virt_lines Array of virtual line chunks for nvim_buf_set_extmark
local function build_box_lines(note, prefix, hl_group, border, wrap_at)
	-- Split on literal "\n" (backslash-n typed into vim.fn.input) and real newlines
	local lines = vim.split(note:gsub("\\n", "\n"), "\n")
	local prefix_width = vim.fn.strdisplaywidth(prefix)
	local indent = string.rep(" ", prefix_width)

	local left_w = vim.fn.strdisplaywidth(border[8][1])
	local right_w = vim.fn.strdisplaywidth(border[4][1])
	local border_overhead = left_w + right_w + 1
	local max_content_width = math.max((tonumber(wrap_at) or 80) - border_overhead, 1)

	local content = {}
	local max_width = 0

	for i, line in ipairs(lines) do
		local full_line = i == 1 and (prefix .. line) or (indent .. line)
		local wrapped = wrap_text(full_line, max_content_width)
		table.insert(content, wrapped[1])
		local w = vim.fn.strdisplaywidth(wrapped[1])
		if w > max_width then
			max_width = w
		end
		for j = 2, #wrapped do
			local continuation = indent .. wrapped[j]
			local cw = vim.fn.strdisplaywidth(continuation)
			if cw > max_content_width then
				local rewrapped = wrap_text(continuation, max_content_width)
				for _, rwl in ipairs(rewrapped) do
					local rw = vim.fn.strdisplaywidth(rwl)
					if rw > max_width then
						max_width = rw
					end
					table.insert(content, rwl)
				end
			else
				if cw > max_width then
					max_width = cw
				end
				table.insert(content, continuation)
			end
		end
	end

	local inner_width = max_content_width + 1
	local virt_lines = {}

	local topleft, top, topright = border[1], border[2], border[3]
	local right, bottomright = border[4], border[5]
	local bottom, bottomleft, left = border[6], border[7], border[8]

	-- Top border
	table.insert(virt_lines, {
		{ topleft[1], topleft[2] },
		{ string.rep(top[1], inner_width), top[2] },
		{ topright[1], topright[2] },
	})

	-- Body rows
	for _, text in ipairs(content) do
		local fill = inner_width - vim.fn.strdisplaywidth(text)
		table.insert(virt_lines, {
			{ left[1], left[2] },
			{ text .. string.rep(" ", fill), hl_group },
			{ right[1], right[2] },
		})
	end

	-- Bottom border
	table.insert(virt_lines, {
		{ bottomleft[1], bottomleft[2] },
		{ string.rep(bottom[1], inner_width), bottom[2] },
		{ bottomright[1], bottomright[2] },
	})

	return virt_lines
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
	local hl_group = cfg.virt_text_hl or "HauntAnnotation"
	local prefix = cfg.annotation_prefix or "  "
	local suffix = cfg.annotation_suffix or ""
	local virt_text_pos = cfg.virt_text_pos or "eol"

	if virt_text_pos == "above" then
		local max_width = cfg.above_max_width or 80
		local text_width = max_width
		local win = vim.fn.bufwinid(bufnr)
		if win ~= -1 then
			local info = vim.fn.getwininfo(win)[1]
			text_width = math.min(max_width, info.width - info.textoff)
		end
		local border = resolve_border(cfg.above_border, "HauntAnnotationBorder")
		local box_lines = build_box_lines(note .. suffix, prefix, hl_group, border, text_width)
		-- virt_lines_above on row 0 is invisible (Neovim clips virtual lines
		-- above the window topline). Fall back to placing below line 1.
		local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.get_namespace(), line - 1, 0, {
			virt_lines = box_lines,
			virt_lines_above = line > 1,
		})
		return extmark_id
	end

	local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.get_namespace(), line - 1, 0, {
		virt_text = { { prefix .. note .. suffix, hl_group } },
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

	-- right_gravity=true: when a new line is inserted *at* the bookmark's
	-- position (e.g. `O` to open a line above), the extmark moves down to
	-- track the original line's content rather than left-anchoring and
	-- sticking to the newly inserted line. See issue #72.
	local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.get_namespace(), line, 0, {
		right_gravity = true,
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

--- Clear all haunt signs from a buffer
---@param bufnr number Buffer number to clear signs from
---@return boolean success True if clearing was successful
function M.clear_buffer_signs(bufnr)
	if not is_valid_buffer(bufnr) then
		return false
	end

	vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
	return true
end

return M
