---@toc_entry Annotation Input
---@tag haunt-input
---@text
--- # Annotation Input ~
---
--- Provides a configurable input prompt for annotations.

---@class HauntAnnotationInputRequest
---@field prompt string
---@field default string
---@field title? string
---@field on_confirm fun(value: string)
---@field on_cancel? fun()

local M = {}

---@private
---@return HauntAnnotationInputConfig
local function get_input_config()
	local haunt = require("haunt")
	local cfg = haunt.get_config()
	return cfg.annotation_input or {}
end

---@private
---@return boolean
local function is_snacks_available()
	local ok, _ = pcall(require, "snacks")
	return ok
end

---@private
---@param config HauntAnnotationInputConfig
---@return HauntAnnotationInputProvider
local function resolve_provider(config)
	if config.provider == "vim_fn" then
		return "vim_fn"
	end
	if config.provider == "snacks" then
		return is_snacks_available() and "snacks" or "vim_fn"
	end
	return is_snacks_available() and "snacks" or "vim_fn"
end

---@private
---@param position HauntAnnotationInputPosition
---@param width integer
---@param height integer
---@param minheight integer
---@param maxheight integer
---@return table
local function build_win_config(position, width, height, minheight, maxheight)
	local win = {
		style = "input",
		width = width,
		height = height,
		minheight = minheight,
		maxheight = maxheight,
	}

	-- TODO: rename to cursor_above
	if position == "cursor" then
		win.relative = "cursor"
		win.row = -height - 2
		win.col = 1
		return win
	end

	if position == "cursor_below" then
		win.relative = "cursor"
		win.row = 1
		win.col = 1
		return win
	end

	-- TODO: this should be an object
	local margin = 4
	local rows = vim.o.lines
	local cols = vim.o.columns
	local row = margin - 3
	local col = margin

	-- TODO: we should pass in the object above and get back an object
	-- The type should be the enum
	if position == "top_right" then
		col = math.max(margin, cols - width - margin)
	elseif position == "bottom_left" then
		row = math.max(margin, rows - height - margin)
	elseif position == "bottom_right" then
		row = math.max(margin, rows - height - margin)
		col = math.max(margin, cols - width - margin)
	elseif position == "center" then
		row = math.max(margin, math.floor((rows - height) / 2))
		col = math.max(margin, math.floor((cols - width) / 2))
	end

	-- TODO: object.row, o.col, etc...
	win.relative = "editor"
	win.row = row
	win.col = col
	return win
end

---@private
---@param text string
---@return string[]
local function split_lines(text)
	if text == "" then
		return { "" }
	end
	return vim.split(text, "\n", { plain = true })
end

---@private
---@param bufnr number
---@return string
local function collect_text(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return table.concat(lines, "\n")
end

--- Prompt the user for an annotation.
---@param request HauntAnnotationInputRequest
---@return boolean prompted True if an input was shown or handled
function M.prompt_annotation(request)
	local config = get_input_config()
	local provider = resolve_provider(config)
	local default_text = request.default or ""
	local snacks_available = is_snacks_available()
	if (config.provider == "snacks" or config.provider == "auto") and not snacks_available then
		vim.notify("haunt.nvim: Floating annotation input requires Snacks.nvim", vim.log.levels.WARN)
	end

	-- FIX: no type
	local function handle_value(value)
		local annotation = value or ""
		if annotation == "" then
			if request.on_cancel then
				request.on_cancel()
			end
			return false
		end
		request.on_confirm(annotation)
		return true
	end

	if provider == "snacks" then
		local ok, Snacks = pcall(require, "snacks")
		if ok and Snacks and Snacks.win then
			local width = config.width or 45
			local minheight = config.minheight or 6
			local maxheight = config.maxheight or minheight
			local height = minheight
			local win = build_win_config(config.position or "cursor", width, height, minheight, maxheight)
			local title = request.title or (default_text ~= "" and "Edit Annotation" or "New Annotation")
			local save_keys = config.save_keys or {
				{ key = "<CR>", mode = { "n", "i" } },
			}
			local quit_keys = config.quit_keys
				or {
					{ key = "q", mode = { "n" } },
					{ key = "<Esc>", mode = { "n" } },
				}
			local saved = false
			local cancelled = false

			-- FIX: no type
			local function save_from_win(win_instance)
				if saved then
					return
				end
				saved = true
				if win_instance and win_instance.buf and vim.api.nvim_buf_is_valid(win_instance.buf) then
					handle_value(collect_text(win_instance.buf))
					return
				end
				handle_value("")
			end

			-- FIX: no type
			local function save_and_close(win_instance)
				save_from_win(win_instance)
				if win_instance and win_instance.close then
					win_instance:close()
				end
			end

			-- FIX: no type
			local function cancel_and_close(win_instance)
				if cancelled then
					return
				end
				cancelled = true
				if request.on_cancel then
					request.on_cancel()
				end
				if win_instance and win_instance.close then
					win_instance:close()
				end
			end

			-- FIX: no type
			local keys = {}
			for _, key_config in ipairs(save_keys) do
				local key = key_config.key
				local mode = key_config.mode or { "n", "i" }
				table.insert(keys, {
					key,
					function(self)
						save_and_close(self)
					end,
					mode = mode,
					desc = "save",
				})
			end
			-- FIX: no type
			for _, key_config in ipairs(quit_keys) do
				local key = key_config.key
				local mode = key_config.mode or { "n" }
				table.insert(keys, {
					key,
					function(self)
						cancel_and_close(self)
					end,
					mode = mode,
					desc = "cancel",
				})
			end

			--- @alias Snacks.snacks.plugins.snacks.win
			local win_opts = vim.tbl_deep_extend("force", win, {
				title = { { " " .. title .. " ", "Title" } },
				title_pos = "center",
				footer_keys = false,
				enter = true,
				keys = keys,
				wo = {
					winhighlight = table.concat({
						"NormalFloat:SnacksInputNormal",
						"FloatBorder:Identifier",
						"WinSeparator:Identifier",
						"FloatTitle:Title",
						"FloatFooter:Title",
					}, ","),
				},
				bo = {
					filetype = "haunt_annotation",
					buftype = "nofile",
				},
				text = split_lines(default_text),
				on_win = function(win_instance)
					if win_instance and win_instance.win then
						vim.api.nvim_set_current_win(win_instance.win)
					end
					vim.cmd("normal! G$")
					vim.cmd("startinsert!")
				end,
				on_close = function(win_instance)
					vim.cmd("stopinsert")
					if not saved and not cancelled then
						save_from_win(win_instance)
					end
				end,
			})

			Snacks.win(win_opts)
			return true
		end
	end

	local annotation = vim.fn.input({
		prompt = request.prompt,
		default = default_text,
	})
	return handle_value(annotation)
end

return M
