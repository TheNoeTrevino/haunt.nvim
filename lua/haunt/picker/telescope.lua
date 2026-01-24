---@toc_entry Picker Telescope
---@tag haunt-picker-telescope
---@text
--- # Picker Telescope ~
---
--- Telescope.nvim picker implementation for haunt.nvim.
--- Requires Telescope.nvim (https://github.com/nvim-telescope/telescope.nvim) to be installed.
---
--- Picker actions: ~
---   - `<CR>`: Jump to the selected bookmark
---   - `d` (normal mode): Delete the selected bookmark
---   - `a` (normal mode): Edit the bookmark's annotation
---
--- The keybindings can be customized via |HauntConfig|.picker_keys.

---@private
local M = {}

local utils = require("haunt.picker.utils")

---@private
--- Reference to the parent picker module for reopening after edit
---@type table|nil
local picker_module = nil

---@private
--- Set the parent picker module reference
---@param module table The parent picker module
function M.set_picker_module(module)
	picker_module = module
end

--- Check if Telescope.nvim is available
---@return boolean available True if Telescope.nvim is installed
function M.is_available()
	local ok, _ = pcall(require, "telescope")
	return ok
end

--- Show the Telescope.nvim picker
---@param opts? table Options to pass to Telescope
---@return boolean success True if picker was shown
function M.show(opts)
	local has_telescope, _ = pcall(require, "telescope")
	if not has_telescope then
		return false
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local entry_display = require("telescope.pickers.entry_display")

	local api = utils.get_api()
	local haunt = utils.get_haunt()

	-- Check if there are any bookmarks
	local bookmarks = api.get_bookmarks()
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return true
	end

	-- Get keybinding configuration
	local cfg = haunt.get_config()
	local picker_keys = cfg.picker_keys

	local items = utils.build_picker_items(bookmarks)

	-- Calculate display widths for alignment
	local max_filename_width = 0
	local max_line_width = 0
	for _, item in ipairs(items) do
		local filename = vim.fn.fnamemodify(item.file, ":t")
		max_filename_width = math.max(max_filename_width, #filename)
		max_line_width = math.max(max_line_width, #tostring(item.line))
	end

	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = max_filename_width },
			{ width = max_line_width + 1 },
			{ remaining = true },
		},
	})

	-- Custom display function for bookmark entries
	local make_display = function(entry)
		local filename = vim.fn.fnamemodify(entry.value.file, ":t")
		local dir = vim.fn.fnamemodify(vim.fn.fnamemodify(entry.value.file, ":."), ":h")
		local dir_display = ""
		if dir ~= "." then
			dir_display = " " .. dir .. "/"
		end

		local note_display = ""
		if entry.value.note and entry.value.note ~= "" then
			note_display = " " .. entry.value.note
		end

		-- Format: filename :line directory/ note
		return displayer({
			{ filename, "TelescopeResultsIdentifier" },
			{ ":" .. tostring(entry.value.line), "TelescopeResultsNumber" },
			{ dir_display .. note_display, "TelescopeResultsComment" },
		})
	end

	-- Delete action for Telescope
	local function telescope_delete(prompt_bufnr)
		local selection = action_state.get_selected_entry()
		if not selection then
			return
		end

		-- Delete the bookmark by its ID
		local success = api.delete_by_id(selection.value.id)
		if not success then
			vim.notify("haunt.nvim: Failed to delete bookmark", vim.log.levels.WARN)
			return
		end

		-- Check if there are any bookmarks left
		local remaining = api.get_bookmarks()
		if #remaining == 0 then
			actions.close(prompt_bufnr)
			vim.notify("haunt.nvim: No bookmarks remaining", vim.log.levels.INFO)
			return
		end

		-- Refresh picker to show updated list
		local current_picker = action_state.get_current_picker(prompt_bufnr)
		local new_items = utils.build_picker_items(remaining)
		current_picker:refresh(finders.new_table({
			results = new_items,
			entry_maker = function(item)
				return {
					value = item,
					display = make_display,
					ordinal = item.text,
					filename = item.file,
					lnum = item.line,
				}
			end,
		}), { reset_prompt = false })
	end

	-- Edit annotation action for Telescope
	local function telescope_edit_annotation(prompt_bufnr)
		local selection = action_state.get_selected_entry()
		if not selection then
			return
		end

		local item = selection.value

		-- Prompt for new annotation
		local default_text = item.note or ""

		-- Close picker temporarily to show input prompt clearly
		actions.close(prompt_bufnr)

		local annotation = vim.fn.input({
			prompt = "Annotation: ",
			default = default_text,
		})

		-- If user cancelled (ESC), annotation will be empty string
		-- Only proceed if something was entered or if clearing existing annotation
		if annotation == "" and default_text == "" then
			-- User cancelled with no existing annotation, reopen picker
			if picker_module then
				picker_module.show()
			end
			return
		end

		-- Open the file in a buffer if not already open
		local bufnr = vim.fn.bufnr(item.file)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(item.file)
			vim.fn.bufload(bufnr)
		end

		-- Use helper to execute annotate in the buffer context
		utils.with_buffer_context(bufnr, item.line, function()
			api.annotate(annotation)
		end)

		-- Reopen the picker with updated data
		if picker_module then
			picker_module.show()
		end
	end

	-- Build attach_mappings function for custom keybindings
	local function attach_mappings(prompt_bufnr, map)
		-- Replace default select action with jump to bookmark
		actions.select_default:replace(function()
			local selection = action_state.get_selected_entry()
			if not selection then
				return
			end
			actions.close(prompt_bufnr)
			utils.jump_to_bookmark(selection.value)
		end)

		-- Map delete key
		if picker_keys.delete then
			local key = picker_keys.delete.key or "d"
			local modes = picker_keys.delete.mode or { "n" }
			for _, mode in ipairs(modes) do
				map(mode, key, telescope_delete)
			end
		end

		-- Map edit annotation key
		if picker_keys.edit_annotation then
			local key = picker_keys.edit_annotation.key or "a"
			local modes = picker_keys.edit_annotation.mode or { "n" }
			for _, mode in ipairs(modes) do
				map(mode, key, telescope_edit_annotation)
			end
		end

		return true
	end

	local picker_opts = vim.tbl_deep_extend("force", {
		prompt_title = "Hauntings",
		finder = finders.new_table({
			results = items,
			entry_maker = function(item)
				return {
					value = item,
					display = make_display,
					ordinal = item.text,
					filename = item.file,
					lnum = item.line,
				}
			end,
		}),
		sorter = conf.generic_sorter({}),
		previewer = conf.grep_previewer({}),
		attach_mappings = attach_mappings,
	}, opts or {})

	pickers.new({}, picker_opts):find()
	return true
end

return M
