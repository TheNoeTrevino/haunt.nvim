---@toc_entry Picker Fallback
---@tag haunt-picker-fallback
---@text
--- # Picker Fallback ~
---
--- Fallback picker implementation using vim.ui.select.
--- Used when neither Snacks.nvim nor Telescope.nvim is available.
---
--- This picker provides basic functionality:
---   - `<CR>`: Jump to the selected bookmark
---
--- Note: Delete and edit annotation actions are not available in the fallback picker.

---@private
local M = {}

local utils = require("haunt.picker.utils")

--- Show the fallback picker using vim.ui.select
---@return boolean success Always returns true (fallback is always available)
function M.show()
	local api = utils.get_api()

	local bookmarks = api.get_bookmarks()
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return true
	end

	vim.ui.select(utils.build_picker_items(bookmarks), {
		prompt = "Hauntings",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end
		utils.jump_to_bookmark(choice)
	end)

	return true
end

return M
