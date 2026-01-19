---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.api", function()
	local api
	local display

	before_each(function()
		helpers.reset_modules()
		api = require("haunt.api")
		display = require("haunt.display")
		local config = require("haunt.config")
		config.setup()
		api._reset_for_testing()
	end)

	describe("toggle_annotation", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns false when no bookmark exists at line", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local ok = api.toggle_annotation()
			assert.is_false(ok)

			local bookmarks = api.get_bookmarks()
			assert.are.equal(0, #bookmarks)
		end)

		it("hides annotation when toggled", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			local bookmarks = api.get_bookmarks()
			local initial_extmark_id = bookmarks[1].annotation_extmark_id
			assert.is_not_nil(initial_extmark_id)

			-- Toggle off
			api.toggle_annotation()
			bookmarks = api.get_bookmarks()
			assert.is_nil(bookmarks[1].annotation_extmark_id)
		end)

		it("shows annotation when toggled back", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			-- Toggle off
			api.toggle_annotation()
			-- Toggle on
			api.toggle_annotation()

			local bookmarks = api.get_bookmarks()
			assert.is_not_nil(bookmarks[1].annotation_extmark_id)
		end)

		it("does not create duplicate annotations when toggled multiple times", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			-- Toggle off and on multiple times
			api.toggle_annotation()
			api.toggle_annotation()
			api.toggle_annotation()
			api.toggle_annotation()

			local annotation_count = helpers.count_annotation_extmarks(bufnr, display.get_namespace())
			assert.are.equal(1, annotation_count)
		end)
	end)

	describe("toggle_all_lines", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			-- Create bookmarks with annotations
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Note 2")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Note 3")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("hides all annotations when toggled off", function()
			local visible = api.toggle_all_lines()
			assert.is_false(visible)

			local bookmarks = api.get_bookmarks()
			for _, bookmark in ipairs(bookmarks) do
				assert.is_nil(bookmark.annotation_extmark_id)
			end
		end)

		it("shows all annotations when toggled back on", function()
			-- Toggle off
			api.toggle_all_lines()
			-- Toggle on
			local visible = api.toggle_all_lines()
			assert.is_true(visible)

			local bookmarks = api.get_bookmarks()
			for _, bookmark in ipairs(bookmarks) do
				assert.is_not_nil(bookmark.annotation_extmark_id)
			end
		end)

		it("works correctly when toggled multiple times", function()
			-- Toggle off, on, off, on
			api.toggle_all_lines() -- off
			api.toggle_all_lines() -- on
			api.toggle_all_lines() -- off
			local visible = api.toggle_all_lines() -- on
			assert.is_true(visible)

			local bookmarks = api.get_bookmarks()
			for _, bookmark in ipairs(bookmarks) do
				assert.is_not_nil(bookmark.annotation_extmark_id)
			end
		end)

		it("does not create duplicate annotations when toggled repeatedly", function()
			-- Toggle multiple times
			api.toggle_all_lines() -- off
			api.toggle_all_lines() -- on
			api.toggle_all_lines() -- off
			api.toggle_all_lines() -- on

			-- Should have exactly 3 annotations (one per bookmark)
			local annotation_count = helpers.count_annotation_extmarks(bufnr, display.get_namespace())
			assert.are.equal(3, annotation_count)
		end)

		it("handles interaction with individual toggle correctly", function()
			-- Toggle all off
			api.toggle_all_lines()

			-- Toggle one individual bookmark on
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.toggle_annotation()

			-- Toggle all on
			api.toggle_all_lines()

			-- Should have exactly 3 annotations (one per bookmark), no duplicates
			local annotation_count = helpers.count_annotation_extmarks(bufnr, display.get_namespace())
			assert.are.equal(3, annotation_count)
		end)

		it("uses current extmark position not stored line when buffer is modified", function()
			-- Add a line at the beginning
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "New Line 0" })

			-- All bookmarks should have moved down by 1
			-- Toggle should still work without errors
			local ok, result = pcall(api.toggle_all_lines)
			assert.is_true(ok)
			assert.is_false(result) -- toggled off

			-- Toggle back on
			ok, result = pcall(api.toggle_all_lines)
			assert.is_true(ok)
			assert.is_true(result) -- toggled on

			-- Verify no errors and annotations are at correct positions
			local bookmarks = api.get_bookmarks()
			for _, bookmark in ipairs(bookmarks) do
				assert.is_not_nil(bookmark.annotation_extmark_id)
			end
		end)

		it("handles deleted lines gracefully", function()
			-- Delete line 2
			vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})

			-- Toggle should not error even though one bookmark might be invalid
			local ok, result = pcall(api.toggle_all_lines)
			assert.is_true(ok)

			-- Should still have bookmarks
			local bookmarks = api.get_bookmarks()
			assert.are.equal(3, #bookmarks)
		end)
	end)

	describe("annotate", function()
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

		it("creates bookmark with annotation", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.fn.input = function()
				return "Test annotation"
			end

			api.annotate()

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal("Test annotation", bookmarks[1].note)
		end)

		it("updates existing annotation", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			-- First annotation
			vim.fn.input = function()
				return "First note"
			end
			api.annotate()

			-- Update annotation
			vim.fn.input = function()
				return "Updated note"
			end
			api.annotate()

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal("Updated note", bookmarks[1].note)
		end)

		it("accepts text parameter to skip input", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			api.annotate("Direct annotation")

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal("Direct annotation", bookmarks[1].note)
		end)

		it("returns false on empty input (cancel)", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.fn.input = function()
				return ""
			end

			local result = api.annotate()

			assert.is_false(result)
			assert.are.equal(0, #api.get_bookmarks())
		end)
	end)

	describe("delete", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("removes existing bookmark", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local before = api.get_bookmarks()
			assert.are.equal(1, #before)

			local ok = api.delete()
			assert.is_true(ok)

			local after = api.get_bookmarks()
			assert.are.equal(0, #after)
		end)

		it("returns false when no bookmark exists", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			local ok = api.delete()
			assert.is_false(ok)
		end)

		it("cleans up extmarks and signs", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			api.delete()

			-- Check no extmarks remain
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.are.equal(0, #extmarks)

			-- Check no signs remain
			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.are.equal(0, #signs[1].signs)
		end)
	end)

	describe("delete_by_id", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("deletes bookmark by ID", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")

			local bookmarks = api.get_bookmarks()
			local first_id = bookmarks[1].id

			local ok = api.delete_by_id(first_id)

			assert.is_true(ok)
			assert.are.equal(1, #api.get_bookmarks())
			assert.are.equal("Second", api.get_bookmarks()[1].note)
		end)

		it("returns false for non-existent ID", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local ok = api.delete_by_id("nonexistent-id")

			assert.is_false(ok)
			assert.are.equal(1, #api.get_bookmarks())
		end)
	end)

	describe("clear", function()
		local bufnr1, test_file1, bufnr2, test_file2

		before_each(function()
			bufnr1, test_file1 = helpers.create_test_buffer({ "File1 Line 1", "File1 Line 2" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File1 Bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("File1 Bookmark 2")

			bufnr2, test_file2 = helpers.create_test_buffer({ "File2 Line 1" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File2 Bookmark")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("clears only current file bookmarks", function()
			local before = api.get_bookmarks()
			assert.are.equal(3, #before)

			vim.api.nvim_set_current_buf(bufnr1)
			local ok = api.clear()
			assert.is_true(ok)

			local after = api.get_bookmarks()
			assert.are.equal(1, #after)
		end)

		it("returns true when no bookmarks in file", function()
			-- Switch to file1 and clear
			vim.api.nvim_set_current_buf(bufnr1)
			api.clear()

			-- Clear again (no bookmarks)
			local ok = api.clear()
			assert.is_true(ok)
		end)
	end)

	describe("clear_all", function()
		local bufnr, test_file
		local original_confirm

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Bookmark 2")

			original_confirm = vim.fn.confirm
		end)

		after_each(function()
			vim.fn.confirm = original_confirm
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("clears all bookmarks when confirmed", function()
			vim.fn.confirm = function()
				return 1
			end -- Yes

			local before = api.get_bookmarks()
			assert.are.equal(2, #before)

			local ok = api.clear_all()
			assert.is_true(ok)

			local after = api.get_bookmarks()
			assert.are.equal(0, #after)
		end)

		it("does not clear when cancelled", function()
			vim.fn.confirm = function()
				return 2
			end -- No

			local before = api.get_bookmarks()
			assert.are.equal(2, #before)

			local ok = api.clear_all()
			assert.is_false(ok)

			local after = api.get_bookmarks()
			assert.are.equal(2, #after)
		end)

		it("cleans up all visual elements", function()
			vim.fn.confirm = function()
				return 1
			end

			api.clear_all()

			-- Check no extmarks remain
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.are.equal(0, #extmarks)

			-- Check no signs remain
			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.are.equal(0, #signs[1].signs)
		end)
	end)

	describe("are_annotations_visible", function()
		it("returns true by default", function()
			assert.is_true(api.are_annotations_visible())
		end)

		it("returns false after toggle_all_lines hides annotations", function()
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			api.toggle_all_lines()

			assert.is_false(api.are_annotations_visible())

			helpers.cleanup_buffer(bufnr, test_file)
		end)
	end)

	describe("get_bookmarks / has_bookmarks", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns empty array when no bookmarks", function()
			local bookmarks = api.get_bookmarks()
			assert.is_table(bookmarks)
			assert.are.equal(0, #bookmarks)
		end)

		it("has_bookmarks returns false when empty", function()
			assert.is_false(api.has_bookmarks())
		end)

		it("has_bookmarks returns true when bookmarks exist", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			assert.is_true(api.has_bookmarks())
		end)

		it("get_bookmarks returns deep copy", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original")

			local bookmarks = api.get_bookmarks()
			bookmarks[1].note = "Modified"

			local bookmarks2 = api.get_bookmarks()
			assert.are.equal("Original", bookmarks2[1].note)
		end)
	end)
end)
