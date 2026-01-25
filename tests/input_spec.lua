---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.input", function()
	local original_input

	before_each(function()
		helpers.reset_modules()
		original_input = vim.fn.input
	end)

	after_each(function()
		vim.fn.input = original_input
		package.loaded["snacks"] = nil
	end)

	it("uses Snacks input when available", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "auto",
				position = "center",
				width = 45,
				minheight = 6,
				maxheight = 12,
			},
		})
		local input = require("haunt.input")
		local called = false
		local saved_text

		package.loaded["snacks"] = {
			win = function(opts)
				called = true
				assert.are.equal("Edit Annotation", opts.title)
				assert.is_true(opts.footer_keys)
				assert.is_table(opts.keys)

				local bufnr = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Snacks note" })
				local win = { buf = bufnr, close = function() end, win = vim.api.nvim_get_current_win() }

				if opts.on_close then
					opts.on_close(win)
				end
				return win
			end,
		}

		local ok = input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Existing",
			title = "Edit Annotation",
			on_confirm = function(value)
				saved_text = value
			end,
		})

		assert.is_true(ok)
		assert.is_true(called)
		assert.are.equal("Snacks note", saved_text)
	end)

	it("falls back to vim.fn.input when Snacks is unavailable", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
			},
		})
		local input = require("haunt.input")
		local called = false

		vim.fn.input = function()
			called = true
			return "Fallback note"
		end

		local ok = input.prompt_annotation({
			prompt = "Annotation: ",
			default = "",
			on_confirm = function(value)
				assert.are.equal("Fallback note", value)
			end,
		})

		assert.is_true(ok)
		assert.is_true(called)
	end)

	it("shows configured save keys in footer", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
				save_keys = { "<CR>" },
				quit_keys = { "q", "<Esc>" },
			},
		})
		local input = require("haunt.input")
		local key_map = {}

		package.loaded["snacks"] = {
			win = function(opts)
				for _, mapping in ipairs(opts.keys or {}) do
					key_map[mapping[1]] = mapping.desc
				end
				return { buf = vim.api.nvim_create_buf(false, true), close = function() end }
			end,
		}

		input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Test",
			title = "Edit Annotation",
			on_confirm = function() end,
		})

		assert.are.equal("cancel", key_map["q"])
		assert.are.equal("cancel", key_map["<Esc>"])
		assert.are.equal("save", key_map["<CR>"])
	end)
end)
