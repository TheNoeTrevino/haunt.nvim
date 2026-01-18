---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

describe("haunt.api", function()
	local api
	local display

	-- Helper to create a test buffer
	local function create_test_buffer(lines)
		local bufnr = vim.api.nvim_create_buf(false, false)
		local test_file = vim.fn.tempname() .. ".lua"
		vim.api.nvim_buf_set_name(bufnr, test_file)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "Line 1", "Line 2", "Line 3" })
		vim.api.nvim_set_current_buf(bufnr)
		return bufnr, test_file
	end

	-- Helper to cleanup buffer
	local function cleanup_buffer(bufnr, test_file)
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		if test_file then
			vim.fn.delete(test_file)
		end
	end

	before_each(function()
		package.loaded["haunt.api"] = nil
		package.loaded["haunt.display"] = nil
		package.loaded["haunt.persistence"] = nil
		package.loaded["haunt.config"] = nil
		api = require("haunt.api")
		display = require("haunt.display")
		local config = require("haunt.config")
		config.setup()
		api._reset_for_testing() -- Clear any persisted bookmarks
	end)

	describe("toggle_annotation", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer()
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
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

			-- Count extmarks in buffer at line 1
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), { 0, 0 }, { 0, -1 }, {})
			local annotation_count = 0
			for _, extmark in ipairs(extmarks) do
				local details =
					vim.api.nvim_buf_get_extmark_by_id(bufnr, display.get_namespace(), extmark[1], { details = true })
				if details and details[3] and details[3].virt_text then
					annotation_count = annotation_count + 1
				end
			end
			assert.are.equal(1, annotation_count)
		end)
	end)

	describe("toggle_all_lines", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			-- Create bookmarks with annotations
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Note 2")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Note 3")
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
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

			-- Count extmarks in buffer
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, {})
			local annotation_count = 0
			for _, extmark in ipairs(extmarks) do
				local details =
					vim.api.nvim_buf_get_extmark_by_id(bufnr, display.get_namespace(), extmark[1], { details = true })
				if details and details[3] and details[3].virt_text then
					annotation_count = annotation_count + 1
				end
			end
			-- Should have exactly 3 annotations (one per bookmark)
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

			-- Count extmarks to ensure no duplicates
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, {})
			local annotation_count = 0
			for _, extmark in ipairs(extmarks) do
				local details =
					vim.api.nvim_buf_get_extmark_by_id(bufnr, display.get_namespace(), extmark[1], { details = true })
				if details and details[3] and details[3].virt_text then
					annotation_count = annotation_count + 1
				end
			end
			-- Should have exactly 3 annotations (one per bookmark), no duplicates
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
			bufnr, test_file = create_test_buffer()
			original_input = vim.fn.input
		end)

		after_each(function()
			vim.fn.input = original_input
			cleanup_buffer(bufnr, test_file)
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
	end)

	describe("delete", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer()
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
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
	end)

	describe("navigation", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })

			-- Create bookmarks at lines 1, 3, 5
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Bookmark 3")
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("Bookmark 5")
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
		end)

		local next_cases = {
			{ from = 1, expected = 3, desc = "line 1 to line 3" },
			{ from = 3, expected = 5, desc = "line 3 to line 5" },
			{ from = 5, expected = 1, desc = "line 5 wraps to line 1" },
			{ from = 2, expected = 3, desc = "line 2 (no bookmark) to line 3" },
		}

		for _, case in ipairs(next_cases) do
			it("next jumps from " .. case.desc, function()
				vim.api.nvim_win_set_cursor(0, { case.from, 0 })
				api.next()
				local pos = vim.api.nvim_win_get_cursor(0)
				assert.are.equal(case.expected, pos[1])
			end)
		end

		local prev_cases = {
			{ from = 5, expected = 3, desc = "line 5 to line 3" },
			{ from = 3, expected = 1, desc = "line 3 to line 1" },
			{ from = 1, expected = 5, desc = "line 1 wraps to line 5" },
			{ from = 4, expected = 3, desc = "line 4 (no bookmark) to line 3" },
		}

		for _, case in ipairs(prev_cases) do
			it("prev jumps from " .. case.desc, function()
				vim.api.nvim_win_set_cursor(0, { case.from, 0 })
				api.prev()
				local pos = vim.api.nvim_win_get_cursor(0)
				assert.are.equal(case.expected, pos[1])
			end)
		end
	end)

	describe("clear", function()
		local bufnr1, test_file1, bufnr2, test_file2

		before_each(function()
			bufnr1, test_file1 = create_test_buffer({ "File1 Line 1", "File1 Line 2" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File1 Bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("File1 Bookmark 2")

			bufnr2, test_file2 = create_test_buffer({ "File2 Line 1" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File2 Bookmark")
		end)

		after_each(function()
			cleanup_buffer(bufnr1, test_file1)
			cleanup_buffer(bufnr2, test_file2)
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
	end)

	describe("clear_all", function()
		local bufnr, test_file
		local original_confirm

		before_each(function()
			bufnr, test_file = create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Bookmark 2")

			original_confirm = vim.fn.confirm
		end)

		after_each(function()
			vim.fn.confirm = original_confirm
			cleanup_buffer(bufnr, test_file)
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
	end)

	describe("save / load", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer()
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
		end)

		it("persists bookmarks across reload", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Persisted bookmark")

			local save_ok = api.save()
			assert.is_true(save_ok)

			-- Reload module
			package.loaded["haunt.api"] = nil
			local api2 = require("haunt.api")

			local load_ok = api2.load()
			assert.is_true(load_ok)

			local bookmarks = api2.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal(1, bookmarks[1].line)
		end)
	end)

	describe("file-based indexing", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
		end)

		after_each(function()
			cleanup_buffer(bufnr, test_file)
		end)

		it("maintains sorted order when adding bookmarks out of order", function()
			-- Add bookmarks in reverse order
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("Fifth")

			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")

			-- Navigate should work in sorted order
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, cursor[1]) -- Should jump to line 3, not line 5

			api.next()
			cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, cursor[1]) -- Should jump to line 5
		end)

		it("removes bookmark from index when deleted", function()
			-- Add three bookmarks
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("Fifth")

			-- Delete middle bookmark
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.delete()

			-- Navigate should skip deleted bookmark
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, cursor[1]) -- Should jump directly from line 1 to line 5
		end)

		it("clears file from index when all bookmarks removed", function()
			-- Add bookmarks
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")

			-- Clear current file
			api.clear()

			-- Verify no bookmarks remain
			local bookmarks = api.get_bookmarks()
			assert.are.equal(0, #bookmarks)
		end)

		it("rebuilds index when loading from persistence", function()
			-- Create bookmarks
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("Fifth")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			api.annotate("Fourth")

			-- Save
			api.save()

			-- Reload module
			package.loaded["haunt.api"] = nil
			local api2 = require("haunt.api")
			api2.load()

			-- Navigation should work correctly (verifying index was rebuilt)
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api2.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(4, cursor[1]) -- Should jump to line 4 (sorted order)
		end)

		it("handles multiple files independently in index", function()
			-- Create first file bookmarks
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File1 Line1")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("File1 Line3")

			-- Create second file
			local bufnr2, test_file2 = create_test_buffer({ "A", "B", "C", "D" })
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("File2 Line2")
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			api.annotate("File2 Line4")

			-- Navigate in second file
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(4, cursor[1]) -- Should stay within file 2

			-- Switch back to first file and verify navigation
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, cursor[1]) -- Should navigate within file 1

			cleanup_buffer(bufnr2, test_file2)
		end)

		it("clears entire index when clear_all is called", function()
			-- Add bookmarks to current file
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")

			-- Create second file with bookmarks
			local bufnr2, test_file2 = create_test_buffer({ "A", "B" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File2")

			-- Clear all (mock confirm to return 1 for "Yes")
			local original_confirm = vim.fn.confirm
			vim.fn.confirm = function()
				return 1
			end

			api.clear_all()

			-- Restore original confirm
			vim.fn.confirm = original_confirm

			-- Verify all bookmarks cleared
			local bookmarks = api.get_bookmarks()
			assert.are.equal(0, #bookmarks)

			cleanup_buffer(bufnr2, test_file2)
		end)

		it("maintains index when delete_by_id is called", function()
			-- Add three bookmarks
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("Fifth")

			local bookmarks = api.get_bookmarks()
			local middle_id = bookmarks[2].id

			-- Delete middle bookmark by id
			api.delete_by_id(middle_id)

			-- Navigate should skip deleted bookmark
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(5, cursor[1]) -- Should jump from line 1 to line 5
		end)

		it("handles navigation wrapping with indexed bookmarks", function()
			-- Add bookmarks
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			api.annotate("Fourth")

			-- Start at last bookmark, next should wrap to first
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			api.next()
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, cursor[1]) -- Should wrap to line 2

			-- Test prev wrapping
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.prev()
			cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(4, cursor[1]) -- Should wrap to line 4
		end)
	end)
end)
