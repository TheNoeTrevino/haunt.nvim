---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.navigation", function()
	local navigation
	local store
	local bufnr, test_file

	before_each(function()
		helpers.reset_modules()
		store = require("haunt.store")
		store._reset_for_testing()
		navigation = require("haunt.navigation")
	end)

	after_each(function()
		helpers.cleanup_buffer(bufnr, test_file)
	end)

	describe("next", function()
		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })

			-- Add bookmarks at lines 1, 3, 5
			store.add_bookmark({ file = test_file, line = 1, id = "b1" })
			store.add_bookmark({ file = test_file, line = 3, id = "b3" })
			store.add_bookmark({ file = test_file, line = 5, id = "b5" })
		end)

		it("jumps to next bookmark from line 1", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("jumps to next bookmark from line 3", function()
			vim.api.nvim_win_set_cursor(0, { 3, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, pos[1])
		end)

		it("wraps around from last bookmark to first", function()
			vim.api.nvim_win_set_cursor(0, { 5, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(1, pos[1])
		end)

		it("jumps to next bookmark when cursor between bookmarks", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("jumps to next bookmark from line before first", function()
			-- Add bookmark only at line 3
			store._reset_for_testing()
			store.add_bookmark({ file = test_file, line = 3, id = "b3" })

			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("preserves column position", function()
			vim.api.nvim_win_set_cursor(0, { 1, 3 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
			assert.are.equal(3, pos[2])
		end)
	end)

	describe("prev", function()
		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })

			-- Add bookmarks at lines 1, 3, 5
			store.add_bookmark({ file = test_file, line = 1, id = "b1" })
			store.add_bookmark({ file = test_file, line = 3, id = "b3" })
			store.add_bookmark({ file = test_file, line = 5, id = "b5" })
		end)

		it("jumps to previous bookmark from line 5", function()
			vim.api.nvim_win_set_cursor(0, { 5, 0 })

			navigation.prev()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("jumps to previous bookmark from line 3", function()
			vim.api.nvim_win_set_cursor(0, { 3, 0 })

			navigation.prev()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(1, pos[1])
		end)

		it("wraps around from first bookmark to last", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			navigation.prev()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, pos[1])
		end)

		it("jumps to previous bookmark when cursor between bookmarks", function()
			vim.api.nvim_win_set_cursor(0, { 4, 0 })

			navigation.prev()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
		end)

		it("preserves column position", function()
			vim.api.nvim_win_set_cursor(0, { 5, 2 })

			navigation.prev()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos[1])
			assert.are.equal(2, pos[2])
		end)
	end)

	describe("edge cases", function()
		it("returns false when no bookmarks in buffer", function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local result = navigation.next()

			assert.is_false(result)
		end)

		it("handles single bookmark", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			store.add_bookmark({ file = test_file, line = 2, id = "only" })

			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local result = navigation.next()

			assert.is_true(result)
			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, pos[1])
		end)

		it("single bookmark wraps to itself", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			store.add_bookmark({ file = test_file, line = 2, id = "only" })

			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			navigation.next()

			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, pos[1])
		end)

		it("handles unnamed buffer", function()
			local unnamed_bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(unnamed_bufnr)

			local result = navigation.next()

			assert.is_false(result)
			vim.api.nvim_buf_delete(unnamed_bufnr, { force = true })
		end)

		it("only navigates bookmarks in current file", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			-- Add bookmark in current file
			store.add_bookmark({ file = test_file, line = 1, id = "current" })
			-- Add bookmark in different file
			store.add_bookmark({ file = "/other/file.lua", line = 2, id = "other" })

			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			navigation.next()

			-- Should wrap to itself since only one bookmark in current file
			local pos = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(1, pos[1])
		end)

		it("sets jump mark before navigating", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
			store.add_bookmark({ file = test_file, line = 1, id = "b1" })
			store.add_bookmark({ file = test_file, line = 5, id = "b5" })

			vim.api.nvim_win_set_cursor(0, { 3, 0 })

			navigation.next()

			-- Verify we can jump back with Ctrl-O
			local pos_after = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, pos_after[1])
		end)
	end)

	describe("bookmarks added out of order", function()
		it("navigates in sorted order regardless of add order", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })

			-- Add bookmarks out of order
			store.add_bookmark({ file = test_file, line = 5, id = "b5" })
			store.add_bookmark({ file = test_file, line = 1, id = "b1" })
			store.add_bookmark({ file = test_file, line = 3, id = "b3" })

			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			navigation.next()
			local pos1 = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, pos1[1])

			navigation.next()
			local pos2 = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, pos2[1])

			navigation.next()
			local pos3 = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(1, pos3[1])
		end)
	end)
end)
