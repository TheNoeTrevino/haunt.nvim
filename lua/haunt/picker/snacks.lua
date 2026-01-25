---@toc_entry Picker Snacks
---@tag haunt-picker-snacks
---@text
--- # Picker Snacks ~
---
--- Snacks.nvim picker implementation for haunt.nvim.
--- Requires Snacks.nvim (https://github.com/folke/snacks.nvim) to be installed.
---
--- Picker actions: ~
---   - `<CR>`: Jump to the selected bookmark
---   - `d` (normal mode): Delete the selected bookmark
---   - `a` (normal mode): Edit the bookmark's annotation
---
--- The keybindings can be customized via |HauntConfig|.picker_keys.

---@type PickerModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local utils = require("haunt.picker.utils")

---@private
---@type PickerRouter|nil
local picker_module = nil

--- Set the parent picker module reference for reopening after edit
---@param module PickerRouter The parent picker module
function M.set_picker_module(module)
	picker_module = module
end

--- Check if Snacks.nvim is available
---@return boolean available True if Snacks.nvim is installed
function M.is_available()
	local ok, _ = pcall(require, "snacks")
	return ok
end

---@private
---@param picker snacks.Picker The Snacks picker instance
---@param item PickerItem|nil The selected bookmark item
local function handle_delete(picker, item)
	local api = utils.get_api()

	if not item then
		return
	end

	-- Delete the bookmark by its ID (no need for buffer context)
	local success = api.delete_by_id(item.id)

	if not success then
		vim.notify("haunt.nvim: Failed to delete bookmark", vim.log.levels.WARN)
		return
	end

	-- Check if there are any bookmarks left
	local remaining = api.get_bookmarks()
	if #remaining == 0 then
		picker:close()
		vim.notify("haunt.nvim: No bookmarks remaining", vim.log.levels.INFO)
		return
	end

	-- Refresh the picker to show updated list
	picker:refresh()
end

---@private
---@param picker snacks.Picker The Snacks picker instance
---@param item PickerItem The selected bookmark item
local function handle_edit_annotation(picker, item)
	utils.handle_edit_annotation({
		item = item,
		close_picker = function()
			picker:close()
		end,
		reopen_picker = function()
			if picker_module then
				picker_module.show()
			end
		end,
	})
end

--- Show the Snacks.nvim picker
---@param opts? table Options to pass to Snacks.picker (see snacks.picker.Config)
---@return boolean success True if picker was shown
function M.show(opts)
	local ok, Snacks = pcall(require, "snacks")
	if not ok then
		return false
	end

	local api = utils.get_api()
	local haunt = utils.get_haunt()

	-- Check if there are any bookmarks
	local initial_bookmarks = api.get_bookmarks()
	if #initial_bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return true
	end

	-- Get keybinding configuration (config.get() always returns defaults if not set)
	local cfg = haunt.get_config()
	local picker_keys = cfg.picker_keys

	-- Build keys table for Snacks picker in the correct format
	-- Keys need to be in both input and list windows so they work regardless of focus
	local input_keys = {}
	local list_keys = {}

	if picker_keys.delete then
		local key = picker_keys.delete.key or "d"
		local mode = picker_keys.delete.mode or { "n" }
		input_keys[key] = { "delete", mode = mode }
		list_keys[key] = { "delete", mode = mode }
	end

	if picker_keys.edit_annotation then
		local key = picker_keys.edit_annotation.key or "a"
		local mode = picker_keys.edit_annotation.mode or { "n" }
		input_keys[key] = { "edit_annotation", mode = mode }
		list_keys[key] = { "edit_annotation", mode = mode }
	end

	---@type snacks.picker.Config
	local picker_opts = {
		title = "Hauntings",
		-- Use a finder function so picker:refresh() works correctly
		finder = function()
			return utils.build_picker_items(api.get_bookmarks())
		end,
		-- Custom format function for bookmark items
		format = function(item, _)
			local result = {}

			-- Use cached path values
			local filename = item.filename
			local dir = vim.fn.fnamemodify(item.relpath, ":h")
			if dir == "." then
				dir = ""
			else
				dir = dir .. "/"
			end

			-- Format: filename (in directory) :line note
			result[#result + 1] = { filename, "SnacksPickerFile" }
			if dir ~= "" then
				result[#result + 1] = { " " .. dir, "SnacksPickerDir" }
			end
			result[#result + 1] = { ":", "SnacksPickerIcon" }
			result[#result + 1] = { tostring(item.pos[1]), "SnacksPickerMatch" }

			-- Add annotation if present
			if item.note and item.note ~= "" then
				result[#result + 1] = { " " .. item.note, "SnacksPickerComment" }
			end

			return result
		end,
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()
			utils.jump_to_bookmark(item --[[@as PickerItem]])
		end,
		actions = {
			delete = handle_delete,
			edit_annotation = handle_edit_annotation,
		},
		win = {
			input = {
				keys = input_keys,
			},
			list = {
				keys = list_keys,
			},
		},
	}
	picker_opts = vim.tbl_deep_extend("force", picker_opts, opts or {})
	Snacks.picker(picker_opts)
	return true
end

return M
