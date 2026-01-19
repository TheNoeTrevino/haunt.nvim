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
---@field line_hl? string|nil The highlight group for the entire line (default: nil)
---@field virt_text_pos? string Position of virtual text: "eol" (default), "eol_right_align", "overlay", "right_align", "inline"
---@field data_dir? string|nil Custom data directory path (default: vim.fn.stdpath("data") .. "/haunt/")
---@field picker_keys table<string, table> Keybindings for picker actions (default: {delete = {key = 'd', mode = {'n'}}, edit_annotation = {key = 'a', mode = {'n'}}})
--minidoc_replace_start M.DEFAULT = {
M.DEFAULT = {
	--minidoc_replace_end
	sign = "󱙝",
	sign_hl = "DiagnosticInfo",
	virt_text_hl = "HauntAnnotation",
	annotation_prefix = " 󰆉 ",
	line_hl = nil,
	virt_text_pos = "eol",
	data_dir = nil,
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
	user_config = vim.tbl_deep_extend("force", M.DEFAULT, opts)
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
