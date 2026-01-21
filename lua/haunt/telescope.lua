---@toc_entry Telescope
---@tag haunt-telescope
---@text
--- # Telescope ~
---
--- The telescope picker provides an interactive interface to browse and manage bookmarks.
--- Requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim).
---
--- Telescope actions: ~
---   - `<CR>`: Jump to the selected bookmark
---   - `d` (normal mode): Delete the selected bookmark
---   - `a` (normal mode): Edit the bookmark's annotation
---
--- The keybindings can be customized via |HauntConfig|.telescope_keys.

---@private
local M = {}

---@private
---@type ApiModule|nil
local api = nil
---@private
---@type HauntModule|nil
local haunt = nil

---@private
local function ensure_modules()
	if not api then
		api = require("haunt.api")
	end
	if not haunt then
		haunt = require("haunt")
	end
end

---@private
--- Execute a callback with buffer context temporarily switched
--- Switches to the target buffer, sets cursor position, executes callback, then safely restores
--- Uses pcall and validation to prevent errors when restoring picker buffer state
---@param bufnr number Target buffer number
---@param line number Line number to set cursor to
---@param callback function Function to execute in the target buffer context
---@return any The return value of the callback
local function with_buffer_context(bufnr, line, callback)
	-- Save current buffer and window
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()
	local cursor_saved = vim.api.nvim_win_get_cursor(current_win)

	-- Ensure target buffer is loaded
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		vim.fn.bufload(bufnr)
	end

	-- Switch to target buffer
	vim.api.nvim_set_current_buf(bufnr)

	-- Move cursor to the bookmark line (with validation)
	-- Clamp line to valid range to avoid "Cursor position outside buffer" error
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local safe_line = math.min(math.max(1, line), line_count)
	pcall(vim.api.nvim_win_set_cursor, current_win, { safe_line, 0 })

	-- Execute the callback
	local result = callback()

	-- Safely restore original buffer with validation
	-- The picker buffer might not be in a valid state to restore, so use pcall
	if vim.api.nvim_buf_is_valid(current_bufnr) and vim.api.nvim_buf_is_loaded(current_bufnr) then
		-- Attempt to restore buffer - use pcall to handle any state errors
		pcall(vim.api.nvim_set_current_buf, current_bufnr)

		-- Only restore cursor if we successfully switched back to the original buffer
		if vim.api.nvim_get_current_buf() == current_bufnr then
			pcall(vim.api.nvim_win_set_cursor, current_win, cursor_saved)
		end
	end

	return result
end

---@private
--- Handle deleting a bookmark from telescope
---@param prompt_bufnr number The telescope prompt buffer number
---@return nil
local function handle_delete(prompt_bufnr)
	ensure_modules()
	---@cast api -nil

	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")

	local selection = action_state.get_selected_entry()
	if not selection then
		return
	end

	-- Delete the bookmark by its ID
	local success = api.delete_by_id(selection.id)

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

	-- Close and reopen to refresh the list
	actions.close(prompt_bufnr)
	vim.schedule(function()
		M.show()
	end)
end

---@private
--- Handle editing a bookmark annotation from telescope
---@param prompt_bufnr number The telescope prompt buffer number
---@return nil
local function handle_edit_annotation(prompt_bufnr)
	ensure_modules()
	---@cast api -nil

	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")

	local selection = action_state.get_selected_entry()
	if not selection then
		return
	end

	-- Prompt for new annotation
	local default_text = selection.note or ""

	-- Close telescope temporarily to show input prompt clearly
	actions.close(prompt_bufnr)

	local annotation = vim.fn.input({
		prompt = "Annotation: ",
		default = default_text,
	})

	-- If user cancelled (ESC), annotation will be empty string
	-- Only proceed if something was entered or if clearing existing annotation
	if annotation == "" and default_text == "" then
		-- User cancelled with no existing annotation, reopen picker
		M.show()
		return
	end

	-- Open the file in a buffer if not already open
	local bufnr = vim.fn.bufnr(selection.file)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(selection.file)
		vim.fn.bufload(bufnr)
	end

	-- Use helper to execute annotate in the buffer context
	with_buffer_context(bufnr, selection.line, function()
		api.annotate(annotation)
	end)

	-- Reopen the picker with updated data
	M.show()
end

--- Open the bookmark telescope picker.
---
--- Displays all bookmarks in an interactive picker powered by telescope.nvim.
--- Allows jumping to, deleting, or editing bookmark annotations.
---
---@param opts? table Optional telescope picker options
---@usage >lua
---   -- Show the telescope picker
---   require('haunt.telescope').show()
---<
function M.show(opts)
	ensure_modules()
	---@cast api -nil
	---@cast haunt -nil

	-- Check if telescope is available
	local ok, _ = pcall(require, "telescope")
	if not ok then
		vim.notify("haunt.nvim: telescope.nvim is not installed", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")
	local entry_display = require("telescope.pickers.entry_display")

	-- Check if there are any bookmarks
	local bookmarks = api.get_bookmarks()
	if #bookmarks == 0 then
		vim.notify("haunt.nvim: No bookmarks found", vim.log.levels.INFO)
		return
	end

	-- Get keybinding configuration
	local cfg = haunt.get_config()
	local telescope_keys = cfg.telescope_keys or cfg.picker_keys

	opts = opts or {}

	-- Create entry display
	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 30 }, -- filename
			{ width = 5 }, -- line number
			{ remaining = true }, -- annotation
		},
	})

	local function make_display(entry)
		local relpath = vim.fn.fnamemodify(entry.file, ":.")
		local filename = vim.fn.fnamemodify(relpath, ":t")
		local dir = vim.fn.fnamemodify(relpath, ":h")
		local display_path = filename
		if dir ~= "." then
			display_path = filename .. " " .. dir .. "/"
		end

		return displayer({
			{ display_path, "TelescopeResultsIdentifier" },
			{ ":" .. tostring(entry.line), "TelescopeResultsNumber" },
			{ entry.note or "", "TelescopeResultsComment" },
		})
	end

	-- Create finder
	local finder = finders.new_table({
		results = bookmarks,
		entry_maker = function(bookmark)
			-- Create searchable text
			local ordinal = bookmark.file .. ":" .. bookmark.line
			if bookmark.note and bookmark.note ~= "" then
				ordinal = ordinal .. " " .. bookmark.note
			end

			return {
				value = bookmark,
				display = make_display,
				ordinal = ordinal,
				file = bookmark.file,
				line = bookmark.line,
				note = bookmark.note,
				id = bookmark.id,
				filename = bookmark.file,
				lnum = bookmark.line,
				col = 1,
			}
		end,
	})

	-- Create the picker
	pickers
		.new(opts, {
			prompt_title = "Hauntings",
			finder = finder,
			sorter = conf.generic_sorter(opts),
			previewer = previewers.vim_buffer_cat.new(opts),
			attach_mappings = function(prompt_bufnr, map)
				-- Default action: jump to bookmark
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					if not selection then
						return
					end
					actions.close(prompt_bufnr)

					-- Open file
					local bufnr = vim.fn.bufnr(selection.file)
					if bufnr == -1 then
						-- File not loaded, open it
						vim.cmd("edit " .. vim.fn.fnameescape(selection.file))
					else
						-- File already loaded, switch to it
						vim.cmd("buffer " .. bufnr)
					end

					-- Go to line
					vim.api.nvim_win_set_cursor(0, { selection.line, 0 })
					vim.cmd("normal! zz")
				end)

				-- Delete action
				local delete_key = telescope_keys.delete and telescope_keys.delete.key or "d"
				map("n", delete_key, function()
					handle_delete(prompt_bufnr)
				end)

				-- Edit annotation action
				local edit_key = telescope_keys.edit_annotation and telescope_keys.edit_annotation.key or "a"
				map("n", edit_key, function()
					handle_edit_annotation(prompt_bufnr)
				end)

				return true
			end,
		})
		:find()
end

return M
