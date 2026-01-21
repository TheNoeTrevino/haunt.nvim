---@toc_entry Commands
---@tag haunt-commands
---@text
--- # Commands ~
---
--- haunt.nvim provides the following user commands:
---
--- `:HauntToggle` - Toggle bookmark annotation visibility
--- `:HauntAnnotate [text]` - Add or edit annotation for bookmark at cursor
--- `:HauntDelete` - Delete bookmark at current line
--- `:HauntNext` - Jump to next bookmark
--- `:HauntPrev` - Jump to previous bookmark
--- `:HauntList` - Open interactive picker to browse all bookmarks (Snacks.nvim)
--- `:HauntTelescope` - Open interactive picker to browse all bookmarks (Telescope)
--- `:HauntClear` - Clear all bookmarks in current buffer
--- `:HauntClearAll` - Clear all bookmarks across all files
---

-- haunt.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is installed

-- Prevent loading twice
if vim.g.loaded_haunt == 1 then
	return
end
vim.g.loaded_haunt = 1

---@class HauntCommandInfo
---@field fn string
---@field desc string
---@field has_args? boolean
---@field args? table

---@type table<string, HauntCommandInfo>
local commands = {
	HauntToggle = { fn = "toggle_annotation", desc = "Toggle bookmark annotation visibility" },
	HauntAnnotate = { fn = "annotate", desc = "Add/edit annotation", has_args = true },
	HauntClear = { fn = "clear", desc = "Clear bookmarks in current file" },
	HauntClearAll = { fn = "clear_all", desc = "Clear all bookmarks" },
	HauntNext = { fn = "next", desc = "Jump to next bookmark" },
	HauntPrev = { fn = "prev", desc = "Jump to previous bookmark" },
	HauntDelete = { fn = "delete", desc = "Delete bookmark at current line" },
	HauntQf = { fn = "to_quickfix", desc = "Send Buffer Annotations to Quickfix List", args = { current_buffer = true } },
	HauntQfAll = { fn = "to_quickfix", desc = "Send All Annotations to Quickfix List" },
}

for name, info in pairs(commands) do
	vim.api.nvim_create_user_command(name, function(opts)
		if info.has_args and opts.args ~= "" then
			require("haunt.api")[info.fn](opts.args)
		elseif info.args then
			require("haunt.api")[info.fn](info.args)
		else
			require("haunt.api")[info.fn]()
		end
	end, { desc = info.desc, nargs = info.has_args and "?" or 0 })
end

-- Special case for HauntList (uses Snacks picker)
vim.api.nvim_create_user_command("HauntList", function()
	require("haunt.picker").show()
end, { desc = "List all bookmarks (Snacks)" })

-- Telescope picker
vim.api.nvim_create_user_command("HauntTelescope", function()
	require("haunt.telescope").show()
end, { desc = "List all bookmarks (Telescope)" })

-- Deferred restoration setup. Dashboard plugins seemingly block this
vim.api.nvim_create_autocmd("UIEnter", {
	once = true,
	callback = function()
		vim.schedule(function()
			require("haunt")._setup_restoration_autocmd()
		end)
	end,
})
