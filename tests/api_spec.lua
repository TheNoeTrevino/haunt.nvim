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

		it("rolls back store and visuals when save fails", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local before = api.get_bookmarks()
			assert.are.equal(1, #before)
			local original_id = before[1].id

			local store = require("haunt.store")
			local original_save = store.save
			store.save = function()
				return false
			end

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			local ok = api.delete()

			store.save = original_save

			assert.is_false(ok)

			local after = api.get_bookmarks()
			assert.are.equal(1, #after, "bookmark must remain in store on save failure")
			assert.are.equal(original_id, after[1].id)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#extmarks > 0, "visuals must be restored on save failure")

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.is_true(#signs[1].signs > 0, "sign must be restored on save failure")
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

		it("rolls back store and visuals when save fails", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local before = api.get_bookmarks()
			assert.are.equal(1, #before)
			local target_id = before[1].id

			local store = require("haunt.store")
			local original_save = store.save
			store.save = function()
				return false
			end

			local ok = api.delete_by_id(target_id)

			store.save = original_save

			assert.is_false(ok)

			local after = api.get_bookmarks()
			assert.are.equal(1, #after, "bookmark must remain in store on save failure")
			assert.are.equal(target_id, after[1].id)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#extmarks > 0, "visuals must be restored on save failure")
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

	describe("out-of-project bookmarks", function()
		local project_mock = require("tests.helpers.project_mock")
		local original_notify
		local notify_calls
		local out_of_project_msg =
			"haunt.nvim: bookmark is outside project root; stored as absolute path (will not sync across machines)"

		--- Count notify calls whose message matches the out-of-project text
		---@return number
		local function count_out_of_project_notifies()
			local count = 0
			for _, call in ipairs(notify_calls) do
				if call.msg == out_of_project_msg then
					count = count + 1
				end
			end
			return count
		end

		--- Create a buffer with a custom file path (no on-disk file required) and
		--- make it the current buffer with cursor at line 1.
		---@param filepath string
		---@return number bufnr
		local function make_named_buffer(filepath)
			local bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, filepath)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			return bufnr
		end

		before_each(function()
			notify_calls = {}
			original_notify = vim.notify
			vim.notify = function(msg, level)
				table.insert(notify_calls, { msg = msg, level = level })
			end
		end)

		after_each(function()
			project_mock.restore()
			vim.notify = original_notify
		end)

		it("does not flag bookmark or notify when file is inside project root", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bufnr = make_named_buffer("/fake/proj/src/main.lua")

			local ok = api.annotate("inside note")
			assert.is_true(ok)

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.is_not_true(bookmarks[1].absolute)
			assert.are.equal(0, count_out_of_project_notifies())

			helpers.cleanup_buffer(bufnr)
		end)

		it("sets absolute=true and notifies when file is outside project root", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bufnr = make_named_buffer("/fake/elsewhere/foo.lua")

			local ok = api.annotate("outside note")
			assert.is_true(ok)

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.is_true(bookmarks[1].absolute)
			assert.are.equal(1, count_out_of_project_notifies())

			helpers.cleanup_buffer(bufnr)
		end)

		it("notifies only once per session for repeated out-of-project bookmarks", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bufnr1 = make_named_buffer("/fake/elsewhere/one.lua")
			assert.is_true(api.annotate("first"))

			local bufnr2 = make_named_buffer("/fake/elsewhere/two.lua")
			assert.is_true(api.annotate("second"))

			local bookmarks = api.get_bookmarks()
			assert.are.equal(2, #bookmarks)
			-- Both bookmarks should be flagged absolute, but the notify fires only once.
			for _, bookmark in ipairs(bookmarks) do
				assert.is_true(bookmark.absolute)
			end
			assert.are.equal(1, count_out_of_project_notifies())

			helpers.cleanup_buffer(bufnr1)
			helpers.cleanup_buffer(bufnr2)
		end)

		it("notifies again after _reset_for_testing clears the session flag", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bufnr1 = make_named_buffer("/fake/elsewhere/one.lua")
			assert.is_true(api.annotate("first"))
			assert.are.equal(1, count_out_of_project_notifies())

			-- Reset session state, including the one-shot notify flag.
			api._reset_for_testing()

			local bufnr2 = make_named_buffer("/fake/elsewhere/two.lua")
			assert.is_true(api.annotate("second"))
			-- After the reset, the notify must fire a second time across the test.
			assert.are.equal(2, count_out_of_project_notifies())

			helpers.cleanup_buffer(bufnr1)
			helpers.cleanup_buffer(bufnr2)
		end)

		it("does not flag or notify in api.lua when project root is nil (no git repo)", function()
			project_mock.set({ root = nil, branch = nil, project_id = "fallback" })

			local bufnr = make_named_buffer("/fake/elsewhere/foo.lua")

			local ok = api.annotate("no project note")
			assert.is_true(ok)

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			-- api.lua leaves the flag unset; persistence flags defensively at save time.
			assert.is_not_true(bookmarks[1].absolute)
			assert.are.equal(0, count_out_of_project_notifies())

			helpers.cleanup_buffer(bufnr)
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

	describe("reload", function()
		local store
		local restoration

		--- Create a buffer with a custom file path (no on-disk file required).
		--- Returns the buffer number for later cleanup.
		---@param filepath string
		---@return number bufnr
		local function make_named_buffer(filepath)
			local bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, filepath)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
			return bufnr
		end

		before_each(function()
			-- Modules are already loaded by the outer before_each via
			-- helpers.reset_modules() + require("haunt.api"). Grab the same
			-- module instances that api.lua's ensure_modules() will see.
			store = require("haunt.store")
			restoration = require("haunt.restoration")
		end)

		it("clears extmarks and signs on all loaded buffers", function()
			local bufnr1 = make_named_buffer("/fake/proj/a.lua")
			local bufnr2 = make_named_buffer("/fake/proj/b.lua")

			local clear_marks_calls = {}
			local clear_signs_calls = {}
			local original_clear_marks = display.clear_buffer_marks
			local original_clear_signs = display.clear_buffer_signs
			display.clear_buffer_marks = function(bufnr)
				table.insert(clear_marks_calls, bufnr)
			end
			display.clear_buffer_signs = function(bufnr)
				table.insert(clear_signs_calls, bufnr)
			end

			local ok = api.reload()
			assert.is_true(ok)

			display.clear_buffer_marks = original_clear_marks
			display.clear_buffer_signs = original_clear_signs

			-- Both calls fired for both buffers (and possibly others
			-- that are in the global buffer list — we just need the
			-- two we created to appear).
			local function contains(list, value)
				for _, v in ipairs(list) do
					if v == value then
						return true
					end
				end
				return false
			end
			assert.is_true(contains(clear_marks_calls, bufnr1))
			assert.is_true(contains(clear_marks_calls, bufnr2))
			assert.is_true(contains(clear_signs_calls, bufnr1))
			assert.is_true(contains(clear_signs_calls, bufnr2))

			helpers.cleanup_buffer(bufnr1)
			helpers.cleanup_buffer(bufnr2)
		end)

		it("resets restoration tracking", function()
			local reset_calls = 0
			local original_reset_tracking = restoration.reset_tracking
			restoration.reset_tracking = function()
				reset_calls = reset_calls + 1
			end

			api.reload()

			restoration.reset_tracking = original_reset_tracking

			assert.are.equal(1, reset_calls)
		end)

		it("re-loads the store from disk", function()
			local reload_calls = 0
			local original_reload = store.reload
			store.reload = function()
				reload_calls = reload_calls + 1
			end

			api.reload()

			store.reload = original_reload

			assert.are.equal(1, reload_calls)
		end)

		it("restores visuals on all loaded buffers after reload", function()
			local bufnr1 = make_named_buffer("/fake/proj/c.lua")
			local bufnr2 = make_named_buffer("/fake/proj/d.lua")

			local restore_calls = {}
			local original_restore = restoration.restore_buffer_bookmarks
			restoration.restore_buffer_bookmarks = function(bufnr, visible)
				table.insert(restore_calls, { bufnr = bufnr, visible = visible })
			end

			api.reload()

			restoration.restore_buffer_bookmarks = original_restore

			local function contains_bufnr(list, value)
				for _, v in ipairs(list) do
					if v.bufnr == value then
						return true
					end
				end
				return false
			end
			assert.is_true(contains_bufnr(restore_calls, bufnr1))
			assert.is_true(contains_bufnr(restore_calls, bufnr2))

			helpers.cleanup_buffer(bufnr1)
			helpers.cleanup_buffer(bufnr2)
		end)
	end)

	describe("autosave registration", function()
		-- The VimLeavePre save autocmd was previously gated behind "first
		-- bookmark created in this session" via _autosave_setup. That meant
		-- a session that only edited text around pre-existing bookmarks
		-- (loaded from disk) never registered VimLeavePre, so line drift
		-- captured in extmarks was never flushed back on exit. The fix is
		-- to register VimLeavePre at plugin entry, regardless of whether
		-- the user adds a new bookmark.
		it("registers VimLeavePre on plugin entry, before any bookmarks are added", function()
			pcall(vim.api.nvim_del_augroup_by_name, "haunt_autosave")

			require("haunt")._setup_restoration_autocmd()

			local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
				group = "haunt_autosave",
				event = "VimLeavePre",
			})
			assert.is_true(ok, "haunt_autosave augroup should exist after _setup_restoration_autocmd")
			assert.is_true(
				#autocmds > 0,
				"VimLeavePre must be registered by _setup_restoration_autocmd, not lazily after first bookmark"
			)
		end)
	end)

	-- Regression: issue #92. The extmark in the buffer correctly follows text
	-- edits, but `bookmark.line` was only resynced from the extmark on save —
	-- so any read path (picker, get_bookmarks) returned the stale on-create
	-- line until a save happened. The picker would then jump to / display the
	-- wrong line.
	describe("get_bookmarks line follows extmark (issue #92)", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "line 1", "line 2", "line 3", "line 4" })
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("on line 3")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("reports the synced line after lines are inserted above", function()
			-- Sanity check: bookmark was created at line 3
			local before = api.get_bookmarks()
			assert.are.equal(1, #before)
			assert.are.equal(3, before[1].line)

			-- Insert 2 lines at the very top — the extmark should slide from
			-- row 2 (0-indexed) to row 4, i.e. line 5 in 1-based terms.
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new top 1", "new top 2" })

			local after = api.get_bookmarks()
			assert.are.equal(1, #after)
			assert.are.equal(
				5,
				after[1].line,
				"bookmark.line should follow the extmark after 2 lines are inserted above (was "
					.. tostring(after[1].line)
					.. ")"
			)
		end)

		it("annotate at the new visual line updates existing bookmark, not duplicate", function()
			-- Same setup as above: bookmark created at line 3, then 2 lines
			-- inserted above so the extmark is now visually at line 5.
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new top 1", "new top 2" })

			-- Move cursor to the bookmark's new visual row and re-annotate.
			-- Before the fix: get_bookmark_at_line(file, 5) misses (stale
			-- bookmark.line == 3) and annotate creates a duplicate.
			vim.api.nvim_win_set_cursor(0, { 5, 0 })
			api.annotate("updated note")

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks, "annotate must update, not duplicate")
			assert.are.equal("updated note", bookmarks[1].note)
		end)
	end)

	-- Issue #108: annotations that cover a range of lines.
	describe("annotate with a range", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "one", "two", "three", "four", "five", "six" })
		end)

		after_each(function()
			pcall(vim.keymap.del, "x", "<Plug>(haunt-test-annotate)")
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("saves end_line for an explicit range", function()
			assert.is_true(api.annotate("a block", { line1 = 2, line2 = 4 }))

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal(2, bookmarks[1].line)
			assert.are.equal(4, bookmarks[1].end_line)

			local saved = helpers.read_bookmarks_file(require("haunt.persistence").get_storage_path()).bookmarks
			assert.are.equal(2, saved[1].line)
			assert.are.equal(4, saved[1].end_line)
		end)

		it("orders a reversed range", function()
			api.annotate("a block", { line1 = 4, line2 = 2 })

			local bookmark = api.get_bookmarks()[1]
			assert.are.equal(2, bookmark.line)
			assert.are.equal(4, bookmark.end_line)
		end)

		it("treats a one-line range as a normal bookmark", function()
			api.annotate("one line", { line1 = 3, line2 = 3 })

			local bookmark = api.get_bookmarks()[1]
			assert.are.equal(3, bookmark.line)
			assert.is_nil(bookmark.end_line)
			local saved = helpers.read_bookmarks_file(require("haunt.persistence").get_storage_path()).bookmarks
			assert.is_nil(saved[1].end_line)
		end)

		it("rejects a range that starts past the end of the buffer", function()
			helpers.cleanup_buffer(bufnr, test_file)
			bufnr, test_file = helpers.create_test_buffer({ "one", "two", "three", "four", "five" })

			local messages = {}
			local original_notify = vim.notify
			vim.notify = function(msg)
				table.insert(messages, msg)
			end
			local ok = api.annotate("too far", { line1 = 8, line2 = 10 })
			vim.notify = original_notify

			assert.is_false(ok)
			assert.are.equal(0, #api.get_bookmarks())
			assert.is_truthy(table.concat(messages, "\n"):find("past the end of the buffer", 1, true))
		end)

		it("clamps a range that runs past the end of the buffer", function()
			api.annotate("a block", { line1 = 5, line2 = 99 })

			local bookmark = api.get_bookmarks()[1]
			assert.are.equal(5, bookmark.line)
			assert.are.equal(6, bookmark.end_line)
		end)

		it("annotates the range, not the cursor line", function()
			vim.api.nvim_win_set_cursor(0, { 6, 0 })
			api.annotate("a block", { line1 = 2, line2 = 4 })

			assert.are.equal(2, api.get_bookmarks()[1].line)
		end)

		for _, mode in ipairs({ "v", "V", "\22" }) do
			it("takes the range from Visual mode " .. vim.fn.keytrans(mode), function()
				vim.keymap.set("x", "<Plug>(haunt-test-annotate)", function()
					api.annotate("from visual")
				end)
				vim.api.nvim_win_set_cursor(0, { 2, 0 })
				vim.api.nvim_feedkeys(mode .. "jj" .. vim.keycode("<Plug>(haunt-test-annotate)"), "x", false)

				assert.are.equal("n", vim.fn.mode(), "annotate should leave Visual mode")
				local bookmark = api.get_bookmarks()[1]
				assert.are.equal(2, bookmark.line)
				assert.are.equal(4, bookmark.end_line)
			end)
		end
	end)

	-- Issue #108: the Cases table in docs/visual-annotations/priority.md.
	-- Range 70-80, single on 75.
	describe("nesting rules", function()
		local bufnr, test_file
		local original_input

		--- Find a bookmark by its note.
		---@param note string
		---@return Bookmark|nil bookmark
		local function by_note(note)
			return vim.iter(api.get_bookmarks()):find(function(bookmark)
				return bookmark.note == note
			end)
		end

		--- The rail signs in the buffer, keyed by 1-based line.
		---@return table<number, string> rows
		local function rail()
			local rows = {}
			local marks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, { details = true })
			for _, mark in ipairs(marks) do
				if mark[4].sign_text then
					rows[mark[2] + 1] = vim.trim(mark[4].sign_text)
				end
			end
			return rows
		end

		before_each(function()
			local lines = {}
			for i = 1, 90 do
				lines[i] = "line " .. i
			end
			bufnr, test_file = helpers.create_test_buffer(lines)
			original_input = vim.fn.input

			api.annotate("range", { line1 = 70, line2 = 80 })
			vim.api.nvim_win_set_cursor(0, { 75, 0 })
			api.annotate("single")
			assert.are.equal(2, #api.get_bookmarks())
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("annotate on 70 edits the range", function()
			vim.api.nvim_win_set_cursor(0, { 70, 0 })
			api.annotate("range edited")

			assert.are.equal(2, #api.get_bookmarks())
			local range = by_note("range edited")
			assert.are.equal(70, range.line)
			assert.are.equal(80, range.end_line)
		end)

		it("annotate on 75 edits the single", function()
			vim.api.nvim_win_set_cursor(0, { 75, 0 })
			api.annotate("single edited")

			assert.are.equal(2, #api.get_bookmarks())
			assert.is_not_nil(by_note("range"))
			assert.are.equal(75, by_note("single edited").line)
		end)

		it("annotate on 76 creates a single on 76", function()
			vim.api.nvim_win_set_cursor(0, { 76, 0 })
			api.annotate("new")

			assert.are.equal(3, #api.get_bookmarks())
			local new = by_note("new")
			assert.are.equal(76, new.line)
			assert.is_nil(new.end_line)
		end)

		it("visual annotate on 70-85 resizes the range to 70-85", function()
			local prompted_with
			vim.fn.input = function(opts)
				prompted_with = opts.default
				return "range resized"
			end

			assert.is_true(api.annotate(nil, { line1 = 70, line2 = 85 }))

			assert.are.equal("range", prompted_with, "the prompt starts from the existing note")
			assert.are.equal(2, #api.get_bookmarks())
			local range = by_note("range resized")
			assert.are.equal(70, range.line)
			assert.are.equal(85, range.end_line)

			-- The tracking extmark follows the new end
			local start_line, end_line = display.get_extmark_range(bufnr, range.extmark_id)
			assert.are.equal(70, start_line)
			assert.are.equal(85, end_line)

			-- The rail is redrawn to the new end
			local rows = rail()
			assert.are.equal("│", rows[80])
			assert.are.equal("╰", rows[85])
			assert.is_nil(rows[86])
		end)

		it("visual annotate on 72-78 creates a range 72-78", function()
			api.annotate("inner", { line1 = 72, line2 = 78 })

			assert.are.equal(3, #api.get_bookmarks())
			local inner = by_note("inner")
			assert.are.equal(72, inner.line)
			assert.are.equal(78, inner.end_line)
			assert.are.equal(80, by_note("range").end_line)
		end)

		it("delete on 75 deletes the single", function()
			vim.api.nvim_win_set_cursor(0, { 75, 0 })
			assert.is_true(api.delete())

			assert.is_nil(by_note("single"))
			assert.is_not_nil(by_note("range"))
		end)

		it("delete on 76 deletes the range", function()
			local hook_line
			require("haunt.hooks").on_delete(function(ctx)
				hook_line = ctx.line
			end)

			vim.api.nvim_win_set_cursor(0, { 76, 0 })
			assert.is_true(api.delete())

			assert.is_nil(by_note("range"))
			assert.is_not_nil(by_note("single"))
			assert.are.equal(70, hook_line, "the hook gets the bookmark's line, not the cursor's")
		end)

		it("toggle on 75 toggles the single", function()
			vim.api.nvim_win_set_cursor(0, { 75, 0 })
			assert.is_true(api.toggle_annotation())

			assert.is_nil(by_note("single").annotation_extmark_id)
			assert.is_not_nil(by_note("range").annotation_extmark_id)
		end)

		it("toggle on 76 toggles the range, drawing it on its own line", function()
			vim.api.nvim_win_set_cursor(0, { 76, 0 })
			api.toggle_annotation()
			assert.is_nil(by_note("range").annotation_extmark_id)
			assert.is_not_nil(by_note("single").annotation_extmark_id)

			api.toggle_annotation()
			local range = by_note("range")
			assert.is_not_nil(range.annotation_extmark_id)
			assert.are.equal(70, display.get_extmark_line(bufnr, range.annotation_extmark_id))
		end)

		it("next / prev stops at 70, then 75", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			assert.are.equal(70, vim.api.nvim_win_get_cursor(0)[1])
			api.next()
			assert.are.equal(75, vim.api.nvim_win_get_cursor(0)[1])
			api.prev()
			assert.are.equal(70, vim.api.nvim_win_get_cursor(0)[1])
		end)

		it("resizing a range to one line makes it a single", function()
			api.annotate("range", { line1 = 70, line2 = 70 })

			local range = by_note("range")
			assert.are.equal(70, range.line)
			assert.is_nil(range.end_line)
			assert.are.same({}, rail(), "a single has no rail")
		end)

		it("keeps undo restoring a range after its note is edited", function()
			vim.cmd("let &undolevels = &undolevels")
			vim.api.nvim_win_set_cursor(0, { 78, 0 })
			vim.cmd("normal! 3dd")
			assert.are.equal(77, by_note("range").end_line)

			vim.api.nvim_win_set_cursor(0, { 70, 0 })
			api.annotate("range edited")
			vim.cmd("normal! u")

			local range = by_note("range edited")
			assert.are.equal(70, range.line)
			assert.are.equal(80, range.end_line)
		end)

		it("keeps undo restoring a collapsed range after its note is edited", function()
			api.annotate("small", { line1 = 20, line2 = 22 })
			vim.cmd("let &undolevels = &undolevels")
			vim.api.nvim_win_set_cursor(0, { 21, 0 })
			vim.cmd("normal! 2dd")
			assert.is_nil(by_note("small").end_line)

			vim.api.nvim_win_set_cursor(0, { 20, 0 })
			api.annotate("small edited")
			vim.cmd("normal! u")

			assert.are.equal(22, by_note("small edited").end_line)
		end)

		for _, case in ipairs({
			{
				name = "delete",
				run = function()
					vim.api.nvim_win_set_cursor(0, { 76, 0 })
					return api.delete()
				end,
			},
			{
				name = "delete_by_id",
				run = function()
					return api.delete_by_id(by_note("range").id)
				end,
			},
		}) do
			it(case.name .. " puts the bookmark back in its place when save fails", function()
				local store = require("haunt.store")
				local original_save = store.save
				store.save = function()
					return false
				end

				local ok = case.run()
				store.save = original_save

				assert.is_false(ok)
				local notes = vim
					.iter(api.get_bookmarks())
					:map(function(bookmark)
						return bookmark.note
					end)
					:totable()
				assert.are.same({ "range", "single" }, notes, "the older bookmark stays first")
			end)
		end

		it("rolls back a resize when save fails", function()
			local store = require("haunt.store")
			local original_save = store.save
			store.save = function()
				return false
			end

			local ok = api.annotate("range resized", { line1 = 70, line2 = 85 })
			store.save = original_save

			assert.is_false(ok)
			local range = by_note("range")
			assert.is_not_nil(range, "the old note is restored")
			assert.are.equal(80, range.end_line)
			local _, end_line = display.get_extmark_range(bufnr, range.extmark_id)
			assert.are.equal(80, end_line, "the tracking extmark is restored")
		end)
	end)

	describe("range rail", function()
		local bufnr, test_file

		--- The rail signs in the buffer, keyed by 1-based line.
		---@return table<number, string> rows
		local function rail()
			local rows = {}
			local marks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, { details = true })
			for _, mark in ipairs(marks) do
				if mark[4].sign_text then
					rows[mark[2] + 1] = vim.trim(mark[4].sign_text)
				end
			end
			return rows
		end

		before_each(function()
			local lines = {}
			for i = 1, 12 do
				lines[i] = "line " .. i
			end
			bufnr, test_file = helpers.create_test_buffer(lines)
			api.annotate("range", { line1 = 5, line2 = 8 })
			vim.api.nvim_win_set_cursor(0, { 7, 0 })
			api.annotate("single")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("draws the rail when a range is created", function()
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("delete on a covered line removes the rail", function()
			vim.api.nvim_win_set_cursor(0, { 6, 0 })
			assert.is_true(api.delete())
			assert.are.same({}, rail())
		end)

		it("delete of the nested single keeps the rail", function()
			vim.api.nvim_win_set_cursor(0, { 7, 0 })
			assert.is_true(api.delete())
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("delete_by_id removes the rail", function()
			local range = vim.iter(api.get_bookmarks()):find(function(bookmark)
				return bookmark.note == "range"
			end)
			assert.is_true(api.delete_by_id(range.id))
			assert.are.same({}, rail())
		end)

		it("clear removes the rail", function()
			assert.is_true(api.clear())
			assert.are.same({}, rail())
		end)

		it("clear_all removes the rail", function()
			local original_confirm = vim.fn.confirm
			vim.fn.confirm = function()
				return 1
			end
			local ok = api.clear_all()
			vim.fn.confirm = original_confirm

			assert.is_true(ok)
			assert.are.same({}, rail())
		end)

		--- Let the queued rail redraw run: it was scheduled before this callback.
		local function settle()
			local done = false
			vim.schedule(function()
				done = true
			end)
			vim.wait(1000, function()
				return done
			end)
		end

		--- Edit in normal mode as its own undo step, then let the rail redraw.
		---@param line number 1-based cursor line
		---@param keys string Normal mode keys
		local function edit(line, keys)
			vim.cmd("let &undolevels = &undolevels")
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			vim.cmd("normal! " .. keys)
			settle()
		end

		it("grows the rail when a line is opened inside the range", function()
			edit(6, "onew")
			assert.are.same({ [6] = "│", [7] = "│", [8] = "│", [9] = "╰" }, rail())
		end)

		it("does not grow the rail when a line is opened below its last line", function()
			edit(8, "onew")
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("shrinks the rail when a covered line is deleted", function()
			edit(6, "dd")
			assert.are.same({ [6] = "│", [7] = "╰" }, rail())
		end)

		it("shrinks the rail when the last line is deleted", function()
			edit(8, "dd")
			assert.are.same({ [6] = "│", [7] = "╰" }, rail())
		end)

		it("moves the rail with lines added above the range", function()
			edit(1, "Onew")
			assert.are.same({ [7] = "│", [8] = "│", [9] = "╰" }, rail())
		end)

		it("restores the rail on undo after dd inside the range", function()
			edit(6, "dd")
			edit(6, "u")
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("restores the rail on undo after every covered line is deleted", function()
			edit(5, "4dd")
			assert.are.same({}, rail())
			edit(5, "u")
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("keeps a range ending on the final line correct when that line is deleted", function()
			api.annotate("to the end", { line1 = 10, line2 = 12 })
			edit(12, "dd")
			local rows = rail()
			assert.are.equal("╰", rows[11])
			assert.is_nil(rows[12])
		end)

		it("draws the rail once for several edits in one turn", function()
			vim.api.nvim_buf_set_lines(bufnr, 5, 5, false, { "a" })
			vim.api.nvim_buf_set_lines(bufnr, 5, 5, false, { "b" })
			settle()
			assert.are.same({ [6] = "│", [7] = "│", [8] = "│", [9] = "│", [10] = "╰" }, rail())
		end)

		it("hiding all annotations hides the rail", function()
			assert.is_false(api.toggle_all_lines())
			assert.are.same({}, rail())
		end)

		it("hides the rail of a range without a note", function()
			local bare = require("haunt.persistence").create_bookmark(test_file, 10, nil, 11)
			display.render_bookmark(bufnr, bare, false)
			api.toggle_all_lines()
			assert.are.same({}, rail())
		end)

		it("showing all annotations again redraws the rail", function()
			api.toggle_all_lines()
			assert.is_true(api.toggle_all_lines())
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("keeps the rail hidden through edits and shows it where the range is now", function()
			api.toggle_all_lines()
			edit(6, "dd")
			assert.are.same({}, rail())

			api.toggle_all_lines()
			assert.are.same({ [6] = "│", [7] = "╰" }, rail())
		end)

		it("keeps the rail hidden through a reload", function()
			api.toggle_all_lines()
			api.reload()
			assert.are.same({}, rail())
		end)

		it("reload draws the rail again on the restored buffer", function()
			api.reload()
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)
	end)

	describe("range rail with reveal = cursor", function()
		local bufnr, test_file

		--- The rail signs in the buffer, keyed by 1-based line.
		---@return table<number, string> rows
		local function rail()
			local rows = {}
			local marks = vim.api.nvim_buf_get_extmarks(bufnr, display.get_namespace(), 0, -1, { details = true })
			for _, mark in ipairs(marks) do
				if mark[4].sign_text then
					rows[mark[2] + 1] = vim.trim(mark[4].sign_text)
				end
			end
			return rows
		end

		--- Let queued rail redraws run: they were scheduled before this callback.
		local function settle()
			local done = false
			vim.schedule(function()
				done = true
			end)
			vim.wait(1000, function()
				return done
			end)
		end

		--- Put the cursor on a line and fire CursorMoved, as the main loop would.
		---@param line number 1-based line
		local function move_to(line)
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })
		end

		before_each(function()
			require("haunt.config").setup({ range = { reveal = "cursor" } })
			local lines = {}
			for i = 1, 12 do
				lines[i] = "line " .. i
			end
			bufnr, test_file = helpers.create_test_buffer(lines)
			api.annotate("range", { line1 = 5, line2 = 8 })
			api.annotate("other", { line1 = 10, line2 = 11 })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("hides the rail while the cursor is outside every range", function()
			move_to(2)
			assert.are.same({}, rail())
		end)

		it("shows only the rail of the range holding the cursor", function()
			move_to(7)
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
			move_to(10)
			assert.are.same({ [11] = "╰" }, rail())
		end)

		it("counts the first line of a range as inside it", function()
			move_to(5)
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
		end)

		it("hides the rail again when the cursor leaves the range", function()
			move_to(7)
			move_to(9)
			assert.are.same({}, rail())
		end)

		it("hides the rail when leaving the buffer and shows it on return", function()
			move_to(7)
			local other = vim.api.nvim_create_buf(true, true)
			vim.api.nvim_set_current_buf(other)
			assert.are.same({}, rail())

			vim.api.nvim_set_current_buf(bufnr)
			settle()
			assert.are.same({ [6] = "│", [7] = "│", [8] = "╰" }, rail())
			vim.api.nvim_buf_delete(other, { force = true })
		end)

		it("follows the range after an edit", function()
			move_to(6)
			vim.cmd("normal! dd")
			settle()
			assert.are.same({ [6] = "│", [7] = "╰" }, rail())
			move_to(8)
			assert.are.same({}, rail())
		end)
	end)

	-- Regression: issue #99. Same stale-line class as #92, but on the quickfix
	-- path: get_quickfix_items read the module-level bookmarks table directly
	-- instead of going through get_bookmarks(), so it never synced from
	-- extmarks. :HauntQf jumped to the on-create line until something else
	-- (opening :HauntList, or a save) happened to sync as a side effect.
	describe("quickfix lines follow extmarks (issue #99)", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "line 1", "line 2", "line 3", "line 4" })
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("on line 3")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("reports the synced lnum after lines are inserted above", function()
			local store = require("haunt.store")

			-- Sanity check: quickfix points at the creation line
			local before = store.get_quickfix_items()
			assert.are.equal(1, #before)
			assert.are.equal(3, before[1].lnum)

			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new top 1", "new top 2" })

			local after = store.get_quickfix_items()
			assert.are.equal(1, #after)
			assert.are.equal(
				5,
				after[1].lnum,
				"quickfix lnum should follow the extmark after 2 lines are inserted above (was "
					.. tostring(after[1].lnum)
					.. ")"
			)
		end)

		it("does not require get_bookmarks to be called first", function()
			-- The bug's tell: opening the picker repaired quickfix as a side
			-- effect. Assert quickfix is correct on a cold read, with no
			-- get_bookmarks() call in between.
			local store = require("haunt.store")
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new top 1", "new top 2" })

			assert.are.equal(5, store.get_quickfix_items()[1].lnum)
		end)

		it("sorts by the synced line, not the stale one", function()
			local store = require("haunt.store")

			-- Second bookmark below the first, then push only the first one
			-- down past it so stale ordering and synced ordering disagree.
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			api.annotate("on line 4")

			vim.api.nvim_buf_set_lines(bufnr, 3, 3, false, { "pushed", "down" })

			local items = store.get_quickfix_items()
			assert.are.equal(2, #items)
			assert.is_true(items[1].lnum < items[2].lnum, "items must be sorted by current line")
			assert.are.equal(3, items[1].lnum)
			assert.are.equal(6, items[2].lnum)
		end)
	end)
end)
