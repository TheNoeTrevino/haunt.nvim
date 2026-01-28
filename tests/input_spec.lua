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
				assert.is_false(opts.footer_keys)
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

	it("maps configured save and quit keys correctly", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
				save_keys = {
					{ key = "<CR>", mode = { "n", "i" } },
				},
				quit_keys = {
					{ key = "q", mode = { "n" } },
					{ key = "<Esc>", mode = { "n" } },
				},
			},
		})
		local input = require("haunt.input")
		local key_map = {}

		package.loaded["snacks"] = {
			win = function(opts)
				for _, mapping in ipairs(opts.keys or {}) do
					key_map[mapping[1]] = { desc = mapping.desc, mode = mapping.mode }
				end
				return { buf = vim.api.nvim_create_buf(false, true), close = function() end }
			end,
		}

		input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Test",
			on_confirm = function() end,
		})

		assert.is_table(key_map["<CR>"])
		assert.are.equal("save", key_map["<CR>"].desc)
		assert.is_true(vim.tbl_contains(key_map["<CR>"].mode, "n"))
		assert.is_true(vim.tbl_contains(key_map["<CR>"].mode, "i"))

		assert.are.equal("cancel", key_map["q"].desc)
		assert.are.equal("cancel", key_map["<Esc>"].desc)
	end)

	it("save_keys work in both normal and insert mode", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
				save_keys = {
					{ key = "<CR>", mode = { "n", "i" } },
				},
			},
		})
		local input = require("haunt.input")
		local key_modes = {}

		package.loaded["snacks"] = {
			win = function(opts)
				for _, mapping in ipairs(opts.keys or {}) do
					if mapping.desc == "save" then
						key_modes[mapping[1]] = mapping.mode
					end
				end
				return { buf = vim.api.nvim_create_buf(false, true), close = function() end }
			end,
		}

		input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Test",
			on_confirm = function() end,
		})

		assert.is_table(key_modes["<CR>"])
		assert.are.equal(2, #key_modes["<CR>"])
		assert.is_true(vim.tbl_contains(key_modes["<CR>"], "n"))
		assert.is_true(vim.tbl_contains(key_modes["<CR>"], "i"))
	end)

	it("allows custom key modes configuration", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
				save_keys = {
					{ key = "<C-s>", mode = { "i" } },
				},
				quit_keys = {
					{ key = "q", mode = { "n" } },
				},
			},
		})
		local input = require("haunt.input")
		local key_map = {}

		package.loaded["snacks"] = {
			win = function(opts)
				for _, mapping in ipairs(opts.keys or {}) do
					key_map[mapping[1]] = { desc = mapping.desc, mode = mapping.mode }
				end
				return { buf = vim.api.nvim_create_buf(false, true), close = function() end }
			end,
		}

		input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Test",
			on_confirm = function() end,
		})

		assert.is_table(key_map["<C-s>"])
		assert.are.equal("save", key_map["<C-s>"].desc)
		assert.are.equal(1, #key_map["<C-s>"].mode)
		assert.are.equal("i", key_map["<C-s>"].mode[1])
	end)

	it("supports multiple keys for same action", function()
		local haunt = require("haunt")
		haunt.setup({
			annotation_input = {
				provider = "snacks",
				save_keys = {
					{ key = "<CR>", mode = { "n", "i" } },
					{ key = "<C-s>", mode = { "n", "i" } },
				},
			},
		})
		local input = require("haunt.input")
		local key_map = {}

		package.loaded["snacks"] = {
			win = function(opts)
				for _, mapping in ipairs(opts.keys or {}) do
					key_map[mapping[1]] = { desc = mapping.desc, mode = mapping.mode }
				end
				return { buf = vim.api.nvim_create_buf(false, true), close = function() end }
			end,
		}

		input.prompt_annotation({
			prompt = "Annotation: ",
			default = "Test",
			on_confirm = function() end,
		})

		assert.are.equal("save", key_map["<CR>"].desc)
		assert.are.equal("save", key_map["<C-s>"].desc)
	end)
end)
