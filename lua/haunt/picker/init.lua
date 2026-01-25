---@toc_entry Picker
---@tag haunt-picker
---@text
--- # Picker ~
---
--- The picker provides an interactive interface to browse and manage bookmarks.
--- Supports Snacks.nvim (https://github.com/folke/snacks.nvim),
--- Telescope.nvim (https://github.com/nvim-telescope/telescope.nvim), and
--- fzf-lua (https://github.com/ibhagwan/fzf-lua).
--- Falls back to vim.ui.select for basic functionality if none are available.
---
--- Configure which picker to use via |HauntConfig|.picker:
---   - `"auto"` (default): Try Snacks, Telescope, fzf-lua, then vim.ui.select
---   - `"snacks"`: Use Snacks.nvim picker
---   - `"telescope"`: Use Telescope.nvim picker
---   - `"fzf"`: Use fzf-lua picker
---
--- Picker actions: ~
---   - `<CR>`: Jump to the selected bookmark
---   - `d` (normal mode): Delete the selected bookmark
---   - `a` (normal mode): Edit the bookmark's annotation
---
--- The keybindings can be customized via |HauntConfig|.picker_keys.

---@type PickerRouter
---@diagnostic disable-next-line: missing-fields
local M = {}

---@private
---@type HauntModule|nil
local haunt = nil

---@private
local function ensure_modules()
	if not haunt then
		haunt = require("haunt")
	end
end

---@private
---@param name string Picker module name ("snacks", "telescope", "fallback")
---@return PickerModule
local function lazy_picker(name)
	---@type PickerModule|nil
	local picker = nil

	---@type PickerModule
	return setmetatable({}, {
		__index = function(_, key)
			if not picker then
				picker = require("haunt.picker." .. name)
				picker.set_picker_module(M)
			end
			return picker[key]
		end,
	})
end

local snacks = lazy_picker("snacks")
local telescope = lazy_picker("telescope")
local fzf = lazy_picker("fzf")
local fallback = lazy_picker("fallback")

---@private
---@param opts? table Options passed to the underlying picker
local function handle_auto_picker(opts)
	if snacks.show(opts) then
		return
	end

	if telescope.show(opts) then
		return
	end

	if fzf.show(opts) then
		return
	end

	fallback.show(opts)
end

--- Open the bookmark picker.
---
--- Displays all bookmarks in an interactive picker. The picker used depends
--- on the |HauntConfig|.picker setting:
---   - `"auto"` (default): Try Snacks, Telescope, fzf-lua, then vim.ui.select
---   - `"snacks"`: Use Snacks.nvim picker
---   - `"telescope"`: Use Telescope.nvim picker
---   - `"fzf"`: Use fzf-lua picker
---
--- Allows jumping to, deleting, or editing bookmark annotations, if you have
--- snacks or telescope installed. Otherwise, falls back to a vim.ui.select
---
--- Note: The opts parameter is passed directly to the underlying picker
--- implementation. It is up to the user to ensure they're passing the
--- correct type for their configured picker. Consider annotating the type
--- yourself, e.g.:
--- >lua
---   ---@type snacks.picker.Config
---   local opts = { ... }
---   require('haunt.picker').show(opts)
--- <
---
---@usage >lua
---   -- Show the picker
---   require('haunt.picker').show()
---<
---@param opts? table Options passed to the underlying picker
function M.show(opts)
	ensure_modules()
	---@cast haunt -nil

	local picker_type = haunt.get_config().picker or "auto"

	if picker_type == "snacks" then
		if not snacks.show(opts) then
			vim.notify("haunt.nvim: Snacks.nvim is not available", vim.log.levels.WARN)
		end
		return
	end

	if picker_type == "telescope" then
		if not telescope.show(opts) then
			vim.notify("haunt.nvim: Telescope.nvim is not available", vim.log.levels.WARN)
		end
		return
	end

	if picker_type == "fzf" then
		if not fzf.show(opts) then
			vim.notify("haunt.nvim: fzf-lua is not available", vim.log.levels.WARN)
		end
		return
	end

	handle_auto_picker(opts)
end

return M
