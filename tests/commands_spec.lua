---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt user commands", function()
	local haunt
	local api

	before_each(function()
		helpers.reset_modules()
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
	end)

	describe("command registration", function()
		local expected_commands = {
			"HauntToggle",
			"HauntAnnotate",
			"HauntList",
			"HauntClear",
			"HauntClearAll",
			"HauntNext",
			"HauntPrev",
		}

		for _, cmd in ipairs(expected_commands) do
			it("registers " .. cmd, function()
				local exists = vim.fn.exists(":" .. cmd) == 2
				assert.is_true(exists)
			end)
		end
	end)

	describe("HauntAnnotate", function()
		local bufnr, test_file
		local original_input

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			original_input = vim.fn.input
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("creates annotated bookmark", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.fn.input = function()
				return "Command annotation"
			end

			vim.cmd("HauntAnnotate")

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal("Command annotation", bookmarks[1].note)
		end)
	end)

	describe("HauntDelete", function()
		local bufnr, test_file
		local original_input

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			original_input = vim.fn.input
			vim.fn.input = function()
				return "Test"
			end
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("removes bookmark at cursor", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")

			local before = api.get_bookmarks()
			assert.are.equal(1, #before)

			vim.cmd("HauntDelete")

			local after = api.get_bookmarks()
			assert.are.equal(0, #after)
		end)
	end)

	describe("HauntNext / HauntPrev", function()
		local bufnr, test_file
		local original_input

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
			original_input = vim.fn.input
			vim.fn.input = function()
				return "Test"
			end

			-- Create bookmarks at lines 1, 3, 5
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			vim.cmd("HauntAnnotate")
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			vim.cmd("HauntAnnotate")
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("HauntNext jumps to next bookmark", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntNext")
			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("HauntPrev jumps to previous bookmark", function()
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			vim.cmd("HauntPrev")
			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)
	end)

	describe("HauntClear", function()
		local bufnr1, test_file1, bufnr2, test_file2
		local original_input

		before_each(function()
			original_input = vim.fn.input
			vim.fn.input = function()
				return "Test"
			end

			bufnr1, test_file1 = helpers.create_test_buffer({ "File1 Line 1", "File1 Line 2" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			vim.cmd("HauntAnnotate")

			bufnr2, test_file2 = helpers.create_test_buffer({ "File2 Line 1" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("clears only current file bookmarks", function()
			local before = api.get_bookmarks()
			assert.are.equal(3, #before)

			vim.api.nvim_set_current_buf(bufnr1)
			vim.cmd("HauntClear")

			local after = api.get_bookmarks()
			assert.are.equal(1, #after)
		end)
	end)

	describe("HauntClearAll", function()
		local bufnr, test_file
		local original_input, original_confirm

		before_each(function()
			original_input = vim.fn.input
			original_confirm = vim.fn.confirm

			vim.fn.input = function()
				return "Test"
			end

			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			vim.cmd("HauntAnnotate")
		end)

		after_each(function()
			vim.fn.input = original_input
			vim.fn.confirm = original_confirm
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("clears all bookmarks when confirmed", function()
			vim.fn.confirm = function()
				return 1
			end

			local before = api.get_bookmarks()
			assert.are.equal(2, #before)

			vim.cmd("HauntClearAll")

			local after = api.get_bookmarks()
			assert.are.equal(0, #after)
		end)
	end)

	describe("HauntList", function()
		local bufnr, test_file
		local original_input

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			original_input = vim.fn.input
			vim.fn.input = function()
				return "Test"
			end

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("HauntAnnotate")
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("calls picker.show without throwing", function()
			-- HauntList requires Snacks.nvim which may not be installed in test env
			-- We just verify the picker module can be required and show() can be called
			local picker = require("haunt.picker")
			local ok = pcall(picker.show)
			-- Should not throw, even if Snacks is not available (it notifies instead)
			assert.is_true(ok)
		end)
	end)
end)
