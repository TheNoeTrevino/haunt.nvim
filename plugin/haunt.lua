---@toc_entry Commands
---@tag haunt-commands
---@text
--- # Commands ~
---
--- haunt.nvim provides the following user commands:
---
--- `:HauntToggle` - Toggle bookmark annotation visibility
--- `:[range]HauntAnnotate [text]` - Add or edit annotation for bookmark at cursor, or annotate a line range (e.g. `:'<,'>HauntAnnotate`)
--- `:HauntDelete` - Delete bookmark at current line
--- `:HauntNext` - Jump to next bookmark
--- `:HauntPrev` - Jump to previous bookmark
--- `:HauntList` - Open interactive picker to browse all bookmarks
--- `:HauntClear` - Clear all bookmarks in current buffer
--- `:HauntClearAll` - Clear all bookmarks across all files
--- `:HauntChangeDataDir [path]` - Change bookmark data directory (for project-specific bookmarks)
--- `:HauntMigrate` - Migrate bookmarks from v1 to v2 storage (project-relative paths)
--- `:HauntReload` - Reload bookmarks from disk (e.g. after switching branches externally)
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
---@field range? boolean

---@type table<string, HauntCommandInfo>
local commands = {
	HauntToggle = { fn = "toggle_annotation", desc = "Toggle bookmark annotation visibility" },
	HauntAnnotate = { fn = "annotate", desc = "Add/edit annotation", has_args = true, range = true },
	HauntClear = { fn = "clear", desc = "Clear bookmarks in current file" },
	HauntClearAll = { fn = "clear_all", desc = "Clear all bookmarks" },
	HauntNext = { fn = "next", desc = "Jump to next bookmark" },
	HauntPrev = { fn = "prev", desc = "Jump to previous bookmark" },
	HauntDelete = { fn = "delete", desc = "Delete bookmark at current line" },
	HauntQf = { fn = "to_quickfix", desc = "Send Buffer Annotations to Quickfix List", args = { current_buffer = true } },
	HauntQfAll = { fn = "to_quickfix", desc = "Send All Annotations to Quickfix List" },
	HauntChangeDataDir = { fn = "change_data_dir", desc = "Change bookmark data directory", has_args = true },
	HauntReload = { fn = "reload", desc = "Reload bookmarks from disk" },
}

for name, info in pairs(commands) do
	vim.api.nvim_create_user_command(name, function(opts)
		if info.has_args then
			local text = opts.args ~= "" and opts.args or nil
			local range = (info.range and opts.range > 0) and { line1 = opts.line1, line2 = opts.line2 } or nil
			require("haunt.api")[info.fn](text, range)
		elseif info.args then
			require("haunt.api")[info.fn](info.args)
		else
			require("haunt.api")[info.fn]()
		end
	end, { desc = info.desc, nargs = info.has_args and "?" or 0, range = info.range })
end

-- Special case for HauntList (uses picker)
vim.api.nvim_create_user_command("HauntList", function()
	require("haunt.picker").show()
end, { desc = "List all bookmarks" })

-- Special case for HauntMigrate (one-shot v1->v2 storage migration)
vim.api.nvim_create_user_command("HauntMigrate", function()
	require("haunt.migration").migrate_current_project()
end, { desc = "Migrate bookmarks from v1 to v2 storage (project-relative paths)" })

-- Deferred restoration setup. Dashboard plugins seemingly block this
vim.api.nvim_create_autocmd("UIEnter", {
	once = true,
	callback = function()
		vim.schedule(function()
			require("haunt")._setup_restoration_autocmd()
		end)
	end,
})
