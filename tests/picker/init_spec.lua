---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker", function()
	local picker
	local api
	local haunt

	-- Mock Snacks.nvim picker
	local mock_snacks

	-- Mock fzf-lua
	local mock_fzf

	-- Mock vim functions
	local original_notify
	local original_ui_select
	local notifications
	local ui_select_calls

	-- Create mock fzf-lua
	local function create_mock_fzf()
		local mock = {
			fzf_exec_called = false,
			fzf_exec_items = nil,
			fzf_exec_opts = nil,
		}
		mock.fzf_exec = function(items, opts)
			mock.fzf_exec_called = true
			mock.fzf_exec_items = items
			mock.fzf_exec_opts = opts
		end
		return mock
	end

	-- Create mock Snacks picker
	local function create_mock_snacks()
		local mock = {
			picker_called = false,
			picker_config = nil,
			picker_instance = {
				closed = false,
				refreshed = false,
				close = function(self)
					self.closed = true
				end,
				refresh = function(self)
					self.refreshed = true
				end,
			},
		}
		mock.picker = function(config)
			mock.picker_called = true
			mock.picker_config = config
			return mock.picker_instance
		end
		return mock
	end

	before_each(function()
		helpers.reset_modules()
		package.loaded["snacks"] = nil
		package.loaded["telescope"] = nil
		package.loaded["fzf-lua"] = nil

		-- Setup mocks
		mock_snacks = create_mock_snacks()
		notifications = {}
		ui_select_calls = {}

		-- Mock vim.notify to capture notifications
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		-- Mock vim.ui.select
		original_ui_select = vim.ui.select
		vim.ui.select = function(items, opts, on_choice)
			table.insert(ui_select_calls, { items = items, opts = opts, on_choice = on_choice })
		end

		-- Initialize modules
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
	end)

	after_each(function()
		vim.notify = original_notify
		vim.ui.select = original_ui_select
		package.loaded["snacks"] = nil
		package.loaded["telescope"] = nil
		package.loaded["fzf-lua"] = nil
	end)

	describe("picker config option", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("defaults to 'auto' picker", function()
			local cfg = haunt.get_config()
			assert.are.equal("auto", cfg.picker)
		end)

		it("uses snacks when picker is set to 'snacks'", function()
			package.loaded["snacks"] = mock_snacks
			haunt.setup({ picker = "snacks" })
			picker = require("haunt.picker")

			picker.show()

			assert.is_true(mock_snacks.picker_called)
		end)

		it("warns when snacks is not available and picker is 'snacks'", function()
			haunt.setup({ picker = "snacks" })
			picker = require("haunt.picker")

			picker.show()

			local has_warning = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("Snacks.nvim is not available") then
					has_warning = true
					break
				end
			end
			assert.is_true(has_warning)
		end)

		it("warns when telescope is not available and picker is 'telescope'", function()
			haunt.setup({ picker = "telescope" })
			picker = require("haunt.picker")

			picker.show()

			local has_warning = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("Telescope.nvim is not available") then
					has_warning = true
					break
				end
			end
			assert.is_true(has_warning)
		end)

		it("warns when fzf-lua is not available and picker is 'fzf'", function()
			haunt.setup({ picker = "fzf" })
			picker = require("haunt.picker")

			picker.show()

			local has_warning = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("fzf%-lua is not available") then
					has_warning = true
					break
				end
			end
			assert.is_true(has_warning)
		end)

		it("uses fzf when picker is set to 'fzf'", function()
			mock_fzf = create_mock_fzf()
			package.loaded["fzf-lua"] = mock_fzf
			haunt.setup({ picker = "fzf" })
			picker = require("haunt.picker")

			picker.show()

			assert.is_true(mock_fzf.fzf_exec_called)
		end)

		it("uses fzf in auto mode when snacks and telescope unavailable", function()
			mock_fzf = create_mock_fzf()
			package.loaded["fzf-lua"] = mock_fzf
			haunt.setup({ picker = "auto" })
			picker = require("haunt.picker")

			picker.show()

			assert.is_true(mock_fzf.fzf_exec_called)
			assert.are.equal(0, #ui_select_calls)
		end)

		it("falls back to vim.ui.select in auto mode when no picker available", function()
			haunt.setup({ picker = "auto" })
			picker = require("haunt.picker")

			picker.show()

			assert.are.equal(1, #ui_select_calls)
		end)

		it("uses snacks first in auto mode when available", function()
			package.loaded["snacks"] = mock_snacks
			haunt.setup({ picker = "auto" })
			picker = require("haunt.picker")

			picker.show()

			assert.is_true(mock_snacks.picker_called)
			assert.are.equal(0, #ui_select_calls)
		end)
	end)

	describe("show()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("notifies when no bookmarks exist (via snacks)", function()
			package.loaded["snacks"] = mock_snacks
			picker = require("haunt.picker")

			picker.show()

			assert.is_false(mock_snacks.picker_called)
			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
		end)

		it("notifies when no bookmarks exist (via fallback)", function()
			picker = require("haunt.picker")

			picker.show()

			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
		end)

		it("calls Snacks.picker when bookmarks exist", function()
			package.loaded["snacks"] = mock_snacks
			picker = require("haunt.picker")

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")

			picker.show()

			assert.is_true(mock_snacks.picker_called)
			assert.is_not_nil(mock_snacks.picker_config)
		end)

		it("falls back to vim.ui.select when Snacks is not available", function()
			picker = require("haunt.picker")

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			picker.show()

			assert.are.equal(1, #ui_select_calls)
			assert.are.equal(1, #ui_select_calls[1].items)
		end)

		it("passes opts to underlying picker", function()
			package.loaded["snacks"] = mock_snacks
			picker = require("haunt.picker")

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local custom_opts = { title = "Custom Title" }
			picker.show(custom_opts)

			assert.are.equal("Custom Title", mock_snacks.picker_config.title)
		end)
	end)
end)
