---@toc_entry Picker fzf-lua
---@tag haunt-picker-fzf
---@text
--- # Picker fzf-lua ~
---
--- fzf-lua picker implementation for haunt.nvim.
--- Requires fzf-lua (https://github.com/ibhagwan/fzf-lua) to be installed.
---
--- Picker actions: ~
---   - `<CR>`: Jump to the selected bookmark
---   - `ctrl-x`: Delete the selected bookmark
---   - `ctrl-e`: Edit the bookmark's annotation
---
--- fzf has no normal mode, so a plain letter key would block typing that
--- letter in the prompt. fzf-lua uses the `fzf_key` field of each
--- |HauntConfig|.picker_keys entry in place of `key` and `mode`, unless
--- `key` is already an fzf key such as "ctrl-d".

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

--- Check if fzf-lua is available
---@return boolean available True if fzf-lua is installed
function M.is_available()
	local ok, _ = pcall(require, "fzf-lua")
	return ok
end

---@private
--- Pick the fzf key for a picker_keys entry. A `key` that is already an fzf
--- key (e.g. "ctrl-d", "alt-a", "f2") still works, as it did before
--- `fzf_key` existed. A plain letter would block typing it, so it falls
--- back to `fzf_key`
---@param key_cfg table The picker_keys entry
---@param default string Key to use when neither field gives a usable key
---@return string
local function fzf_key_for(key_cfg, default)
	local key = key_cfg.key
	if key and (key:match("^%a+%-.") or key:match("^f%d+$")) then
		return key
	end
	return key_cfg.fzf_key or default
end

---@private
---@param item PickerItem The selected bookmark item
---@param reopen_fn fun() Function to reopen the picker after deletion
local function handle_delete(item, reopen_fn)
	local api = utils.get_api()

	if not item then
		return
	end

	local success = api.delete_by_id(item.id)

	if not success then
		vim.notify("haunt.nvim: Failed to delete bookmark", vim.log.levels.WARN)
		return
	end

	local remaining = api.get_bookmarks()
	if #remaining == 0 then
		vim.notify("haunt.nvim: No bookmarks remaining", vim.log.levels.INFO)
		return
	end

	reopen_fn()
end

---@private
---@param item PickerItem The selected bookmark item
---@param opts? table The opts the picker was opened with, reused when it reopens
local function handle_edit_annotation(item, opts)
	utils.handle_edit_annotation({
		item = item,
		close_picker = function()
			-- fzf-lua closes automatically when an action is triggered
		end,
		reopen_picker = function()
			if picker_module then
				picker_module.show(opts)
			end
		end,
	})
end

--- Show the fzf-lua picker
---@param opts? table Options to pass to fzf-lua (see fzf-lua documentation)
---@return boolean success True if picker was shown
function M.show(opts)
	local ok, fzf = pcall(require, "fzf-lua")
	if not ok then
		return false
	end

	local api = utils.get_api()
	local haunt = utils.get_haunt()

	local bookmarks = api.get_bookmarks()
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return true
	end

	local cfg = haunt.get_config()
	local picker_keys = cfg.picker_keys

	local items = utils.build_picker_items(bookmarks)

	-- Maps each displayed entry back to its bookmark, filled in below
	local lookup = {}

	--- Find the bookmark for a selected entry. fzf strips colors and icons
	--- can differ from the entry we built, so fall back to parsing the entry
	--- the way fzf-lua does
	---@param selected? string[] Selected entries
	---@param fzf_opts? table Resolved fzf-lua opts passed to the action
	---@return PickerItem|nil
	local function selected_item(selected, fzf_opts)
		local entry = selected and selected[1]
		if not entry then
			return nil
		end
		if lookup[entry] then
			return lookup[entry]
		end

		local has_path, fzf_path = pcall(require, "fzf-lua.path")
		if not has_path then
			return nil
		end
		local file = fzf_path.entry_to_file(entry, fzf_opts)
		if not file or not file.path then
			return nil
		end
		local abs = vim.fn.fnamemodify(file.path, ":p")
		for _, item in ipairs(items) do
			if vim.fn.fnamemodify(item.file, ":p") == abs and item.line == file.line then
				return item
			end
		end
		return nil
	end

	-- Build actions table with configurable keybindings
	local actions = {}

	-- Default action: jump to bookmark
	actions["default"] = function(selected, fzf_opts)
		local item = selected_item(selected, fzf_opts)
		if item then
			utils.jump_to_bookmark(item)
		end
	end

	-- Delete action
	if picker_keys.delete then
		local key = fzf_key_for(picker_keys.delete, "ctrl-x")
		actions[key] = function(selected, fzf_opts)
			local item = selected_item(selected, fzf_opts)
			if item then
				handle_delete(item, function()
					M.show(opts)
				end)
			end
		end
	end

	-- Edit annotation action
	if picker_keys.edit_annotation then
		local key = fzf_key_for(picker_keys.edit_annotation, "ctrl-e")
		actions[key] = function(selected, fzf_opts)
			local item = selected_item(selected, fzf_opts)
			if item then
				handle_edit_annotation(item, opts)
			end
		end
	end

	local fzf_opts = {
		prompt = "Hauntings> ",
		previewer = "builtin",
		actions = actions,
	}
	fzf_opts = vim.tbl_deep_extend("force", fzf_opts, opts or {})

	-- Resolve the opts with the user's fzf-lua globals up front, like the
	-- built-in fzf-lua providers do, so entries can be formatted with the
	-- user's path settings (formatter, path_shorten, file_icons)
	local has_config, fzf_config = pcall(require, "fzf-lua.config")
	local has_make_entry, make_entry = pcall(require, "fzf-lua.make_entry")
	local format_file = nil
	if has_config and has_make_entry then
		fzf_opts = fzf_config.normalize_opts(fzf_opts, {})
		if not fzf_opts then
			return true
		end
		make_entry.preprocess(fzf_opts)
		format_file = make_entry.file
	end

	-- Build display list. fzf-lua gets absolute paths and makes them
	-- relative to its own cwd, so previews still work when opts.cwd is set.
	-- Without fzf-lua's formatter, show paths relative to Neovim's cwd
	local display_list = {}
	for _, item in ipairs(items) do
		local label
		if format_file then
			label = format_file(string.format("%s:%d:%d", item.file, item.line, item.pos[2] or 0), fzf_opts)
		else
			label = string.format("%s:%d:%d", item.relpath, item.line, item.pos[2] or 0)
		end
		if label then
			if item.note and item.note ~= "" then
				label = label .. " " .. item.note
			end
			table.insert(display_list, label)
			lookup[label] = item
		end
	end

	-- fzf-lua drops entries that match its file_ignore_patterns or cwd_only
	if #display_list == 0 then
		vim.notify("haunt.nvim: No bookmarks to show with the current fzf-lua filters", vim.log.levels.INFO)
		return true
	end

	fzf.fzf_exec(display_list, fzf_opts)
	return true
end

return M
