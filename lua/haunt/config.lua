---@toc_entry Configuration
---@tag haunt-configuration
---@tag HauntConfig
---@text
--- # Configuration ~
---
--- haunt.nvim works with zero configuration, but you can customize the
--- appearance and behavior by passing options to |haunt.setup()|.

---@private
local M = {}

---@private
M.DEFAULT_DATA_DIR = vim.fn.stdpath("data") .. "/haunt/"

--- Configuration options for haunt.nvim.
---
--- All fields are optional. Default values are shown below.
---
---@class HauntConfig
---
---@text
--- Default configuration: ~
---
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@field sign? string The icon to display for bookmarks (default: '󱙝')
---@field sign_hl? string The highlight group for the sign text (default: 'DiagnosticInfo')
---@field virt_text_hl? string The highlight group for virtual text annotations (default: 'HauntAnnotation')
---@field annotation_prefix? string Text to display before the annotation (default: '  ')
---@field annotation_suffix? string Text to display after the annotation (default: '')
---@field line_hl? string|nil The highlight group for the entire line (default: nil)
---@field virt_text_pos? string Position of virtual text: "eol" (default), "eol_right_align", "overlay", "right_align", "inline", "above"
---@field above_max_width? number Maximum width for the "above" box (default: 80). The box is also clamped to the window width. Only applies when virt_text_pos = "above"
---@field above_border? string|string[]|(string|string[])[] Border style for the "above" box. Preset strings: "rounded" (default), "single", "double", "none". Also accepts an array of characters (clockwise from top-left); any length that divides 8 is cycled. Each element can be a string or {char, hl_group}.
---@field data_dir? string|nil Custom data directory path (default: vim.fn.stdpath("data") .. "/haunt/")
---@field picker? "snacks"|"telescope"|"fzf"|"auto" Which picker to use: "snacks", "telescope", "fzf", or "auto" (default: "auto"). "auto" tries Snacks first, then Telescope, then fzf-lua, then vim.ui.select
---@field picker_opts? {snacks?: table, telescope?: table, fzf?: table} Default options for each picker, passed to the picker when it opens, including from `:HauntList` (default: {snacks = {}, telescope = {}, fzf = {}}). Options passed to |haunt-picker|.show() override these
---@field picker_keys table<string, table> Keybindings for picker actions (default: {delete = {key = 'd', mode = {'n'}, fzf_key = 'ctrl-x'}, edit_annotation = {key = 'a', mode = {'n'}, fzf_key = 'ctrl-e'}}). fzf-lua has no normal mode, so it uses `fzf_key` in place of `key` and `mode`, unless `key` is already an fzf key such as "ctrl-d"
---@field per_branch_bookmarks? boolean Whether bookmarks are scoped per git branch (default: true). When false, bookmarks persist across all branches in the same repository.
---@field range? HauntRangeConfig How range annotations are drawn in the sign column. See |HauntRangeConfig|.
--minidoc_replace_start M.DEFAULT = {
M.DEFAULT = {
	--minidoc_replace_end
	sign = "󱙝",
	sign_hl = "DiagnosticInfo",
	virt_text_hl = "HauntAnnotation",
	annotation_prefix = " 󰆉 ",
	annotation_suffix = "",
	line_hl = nil,
	virt_text_pos = "eol",
	above_max_width = 80,
	above_border = "rounded",
	data_dir = nil,
	per_branch_bookmarks = true,
	picker = "auto",
	picker_opts = {
		snacks = {},
		telescope = {},
		fzf = {},
	},
	picker_keys = {
		delete = { key = "d", mode = { "n" }, fzf_key = "ctrl-x" },
		edit_annotation = { key = "a", mode = { "n" }, fzf_key = "ctrl-e" },
	},
	range = {
		style = "rail",
		reveal = "always",
		glyphs = { body = "│", tail = "╰" },
		priority = 5,
	},
}
--minidoc_afterlines_end

--- Sign column drawing for range annotations.
---
--- The first line of a range keeps the bookmark sign. With style "rail" the
--- lines below it get `glyphs.body` and the last line gets `glyphs.tail`,
--- highlighted with `HauntRange`. The rail sits at `priority`, below
--- gitsigns (6), so git status on a covered line is never hidden.
---@class HauntRangeConfig
---@field style? "rail"|"none" How to draw the lines a range covers (default: "rail")
---@field reveal? "always"|"cursor" "cursor" draws the rail only while the cursor is inside the range (default: "always")
---@field glyphs? {body?: string, tail?: string} Sign text for the covered lines and the last line (default: {body = "│", tail = "╰"})
---@field priority? number Sign priority of the rail (default: 5)

---@private
--- Allowed values for the enum-like range options.
local RANGE_CHOICES = {
	style = { rail = true, none = true },
	reveal = { always = true, cursor = true },
}

---@private
--- Warn about an invalid option and reset it to its default.
---@param name string Option path, for the message
---@param value any The rejected value
local function reject(name, value)
	vim.notify(
		string.format("haunt.nvim: invalid %s %s, falling back to the default", name, vim.inspect(value)),
		vim.log.levels.WARN
	)
end

---@private
--- Reset each invalid field of the merged `range` block to its default.
---@param cfg HauntConfig The merged configuration, fixed in place
local function validate_range(cfg)
	local defaults = M.DEFAULT.range
	if type(cfg.range) ~= "table" then
		reject("range", cfg.range)
		cfg.range = vim.deepcopy(defaults)
		return
	end

	local range = cfg.range
	for key, choices in pairs(RANGE_CHOICES) do
		if not choices[range[key]] then
			reject("range." .. key, range[key])
			range[key] = defaults[key]
		end
	end

	if type(range.priority) ~= "number" or range.priority < 0 then
		reject("range.priority", range.priority)
		range.priority = defaults.priority
	end

	if type(range.glyphs) ~= "table" then
		reject("range.glyphs", range.glyphs)
		range.glyphs = vim.deepcopy(defaults.glyphs)
	end
	for _, key in ipairs({ "body", "tail" }) do
		local glyph = range.glyphs[key]
		-- Sign text is at most two cells wide
		if type(glyph) ~= "string" or glyph == "" or vim.fn.strdisplaywidth(glyph) > 2 then
			reject("range.glyphs." .. key, glyph)
			range.glyphs[key] = defaults.glyphs[key]
		end
	end
end

-- User configuration (merged with defaults after setup)
---@type HauntConfig|nil
local user_config = nil

---@private
--- Merge user options with defaults and store
---@param opts? HauntConfig Optional user configuration
function M.setup(opts)
	opts = opts or {}
	local base = user_config or M.DEFAULT
	user_config = vim.tbl_deep_extend("force", base, opts)
	validate_range(user_config)
end

---@private
--- Get the current configuration
--- Returns user config if setup was called, otherwise returns defaults
---@return HauntConfig config The current configuration
function M.get()
	if not user_config then
		return vim.deepcopy(M.DEFAULT)
	end
	return vim.deepcopy(user_config)
end

---@private
--- Check if setup has been called
---@return boolean True if setup has been called
function M.is_setup()
	return user_config ~= nil
end

return M
