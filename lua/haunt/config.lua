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
---@field picker_keys table<string, table> Keybindings for picker actions (default: {delete = {key = 'd', mode = {'n'}}, edit_annotation = {key = 'a', mode = {'n'}}})
---@field per_branch_bookmarks? boolean Whether bookmarks are scoped per git branch (default: true). When false, bookmarks persist across all branches in the same repository.
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
	picker_keys = {
		delete = { key = "d", mode = { "n" } },
		edit_annotation = { key = "a", mode = { "n" } },
	},
}
--minidoc_afterlines_end

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
