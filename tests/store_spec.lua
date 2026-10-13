---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.store", function()
	local store
	local mock_persistence

	before_each(function()
		helpers.reset_modules()

		-- Create and inject mock persistence
		mock_persistence = helpers.create_mock_persistence()
		package.loaded["haunt.persistence"] = mock_persistence

		store = require("haunt.store")
		store._reset_for_testing()
	end)

	after_each(function()
		package.loaded["haunt.persistence"] = nil
	end)

	describe("add_bookmark", function()
		it("adds bookmark to store", function()
			local bookmark = { file = "/test.lua", line = 10, id = "test1", note = "Test" }

			store.add_bookmark(bookmark)

			local bookmarks = store.get_bookmarks()
			assert.are.equal(1, #bookmarks)
			assert.are.equal("/test.lua", bookmarks[1].file)
		end)

		it("adds multiple bookmarks", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 2, id = "test2" })
			store.add_bookmark({ file = "/test.lua", line = 3, id = "test3" })

			local bookmarks = store.get_bookmarks()
			assert.are.equal(3, #bookmarks)
		end)

		it("maintains sorted index by line number", function()
			-- Add out of order
			store.add_bookmark({ file = "/test.lua", line = 5, id = "test3" })
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 3, id = "test2" })

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(3, #sorted)
			assert.are.equal(1, sorted[1].line)
			assert.are.equal(3, sorted[2].line)
			assert.are.equal(5, sorted[3].line)
		end)
	end)

	describe("remove_bookmark", function()
		it("removes bookmark from store", function()
			local bookmark = { file = "/test.lua", line = 10, id = "test1" }
			store.add_bookmark(bookmark)

			local success = store.remove_bookmark(bookmark)

			assert.is_true(success)
			assert.are.equal(0, #store.get_bookmarks())
		end)

		it("returns false for non-existent bookmark", function()
			local bookmark = { file = "/test.lua", line = 10, id = "nonexistent" }

			local success = store.remove_bookmark(bookmark)

			assert.is_false(success)
		end)

		it("removes from file index", function()
			local bookmark = { file = "/test.lua", line = 10, id = "test1" }
			store.add_bookmark(bookmark)

			store.remove_bookmark(bookmark)

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(0, #sorted)
		end)

		it("removes correct bookmark when multiple exist", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 2, id = "test2" })
			store.add_bookmark({ file = "/test.lua", line = 3, id = "test3" })

			store.remove_bookmark({ file = "/test.lua", line = 2, id = "test2" })

			local bookmarks = store.get_bookmarks()
			assert.are.equal(2, #bookmarks)

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(1, sorted[1].line)
			assert.are.equal(3, sorted[2].line)
		end)
	end)

	describe("remove_bookmark_at_index", function()
		it("removes bookmark at valid index", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 2, id = "test2" })

			local removed = store.remove_bookmark_at_index(1)

			assert.is_not_nil(removed)
			assert.are.equal("test1", removed.id)
			assert.are.equal(1, #store.get_bookmarks())
		end)

		it("returns nil for invalid index", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })

			assert.is_nil(store.remove_bookmark_at_index(0))
			assert.is_nil(store.remove_bookmark_at_index(5))
			assert.is_nil(store.remove_bookmark_at_index(-1))
		end)
	end)

	describe("find_by_id", function()
		it("finds existing bookmark", function()
			store.add_bookmark({ file = "/test.lua", line = 10, id = "target" })
			store.add_bookmark({ file = "/test.lua", line = 20, id = "other" })

			local bookmark = store.find_by_id("target")

			assert.is_not_nil(bookmark)
			assert.are.equal("target", bookmark.id)
		end)

		it("returns nil for non-existent ID", function()
			store.add_bookmark({ file = "/test.lua", line = 10, id = "exists" })

			assert.is_nil(store.find_by_id("nonexistent"))
		end)
	end)

	describe("get_bookmark_at_line", function()
		it("finds bookmark at specific file and line", function()
			store.add_bookmark({ file = "/test.lua", line = 10, id = "target" })
			store.add_bookmark({ file = "/test.lua", line = 20, id = "other" })
			store.add_bookmark({ file = "/other.lua", line = 10, id = "different_file" })

			local bookmark, index = store.get_bookmark_at_line("/test.lua", 10)

			assert.is_not_nil(bookmark)
			assert.are.equal("target", bookmark.id)
			assert.is_number(index)
		end)

		it("returns nil when no bookmark at line", function()
			store.add_bookmark({ file = "/test.lua", line = 10, id = "test1" })

			local bookmark, index = store.get_bookmark_at_line("/test.lua", 5)

			assert.is_nil(bookmark)
			assert.is_nil(index)
		end)

		it("returns nil for empty filepath", function()
			local bookmark, index = store.get_bookmark_at_line("", 10)

			assert.is_nil(bookmark)
			assert.is_nil(index)
		end)

		it("distinguishes between files", function()
			store.add_bookmark({ file = "/a.lua", line = 10, id = "file_a" })
			store.add_bookmark({ file = "/b.lua", line = 10, id = "file_b" })

			local bookmark_a = store.get_bookmark_at_line("/a.lua", 10)
			local bookmark_b = store.get_bookmark_at_line("/b.lua", 10)

			assert.are.equal("file_a", bookmark_a.id)
			assert.are.equal("file_b", bookmark_b.id)
		end)
	end)

	describe("get_sorted_bookmarks_for_file", function()
		it("returns empty table for file with no bookmarks", function()
			local sorted = store.get_sorted_bookmarks_for_file("/nonexistent.lua")

			assert.is_table(sorted)
			assert.are.equal(0, #sorted)
		end)

		it("returns bookmarks in sorted order", function()
			store.add_bookmark({ file = "/test.lua", line = 30, id = "test3" })
			store.add_bookmark({ file = "/test.lua", line = 10, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 20, id = "test2" })

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")

			assert.are.equal(3, #sorted)
			assert.are.equal(10, sorted[1].line)
			assert.are.equal(20, sorted[2].line)
			assert.are.equal(30, sorted[3].line)
		end)

		it("only returns bookmarks for specified file", function()
			store.add_bookmark({ file = "/a.lua", line = 1, id = "a1" })
			store.add_bookmark({ file = "/b.lua", line = 1, id = "b1" })
			store.add_bookmark({ file = "/a.lua", line = 2, id = "a2" })

			local sorted = store.get_sorted_bookmarks_for_file("/a.lua")

			assert.are.equal(2, #sorted)
			for _, bm in ipairs(sorted) do
				assert.are.equal("/a.lua", bm.file)
			end
		end)
	end)

	describe("clear_file_bookmarks", function()
		it("removes all bookmarks for file", function()
			store.add_bookmark({ file = "/target.lua", line = 1, id = "t1" })
			store.add_bookmark({ file = "/target.lua", line = 2, id = "t2" })
			store.add_bookmark({ file = "/other.lua", line = 1, id = "o1" })

			local removed = store.clear_file_bookmarks("/target.lua")

			assert.are.equal(2, #removed)
			assert.are.equal(1, #store.get_bookmarks())
			assert.are.equal(0, #store.get_sorted_bookmarks_for_file("/target.lua"))
		end)

		it("returns empty table when file has no bookmarks", function()
			local removed = store.clear_file_bookmarks("/nonexistent.lua")

			assert.is_table(removed)
			assert.are.equal(0, #removed)
		end)
	end)

	describe("clear_all_bookmarks", function()
		it("removes all bookmarks", function()
			store.add_bookmark({ file = "/a.lua", line = 1, id = "a1" })
			store.add_bookmark({ file = "/b.lua", line = 1, id = "b1" })
			store.add_bookmark({ file = "/c.lua", line = 1, id = "c1" })

			local count = store.clear_all_bookmarks()

			assert.are.equal(3, count)
			assert.are.equal(0, #store.get_bookmarks())
		end)

		it("clears file index", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "t1" })
			store.add_bookmark({ file = "/test.lua", line = 2, id = "t2" })

			store.clear_all_bookmarks()

			assert.are.equal(0, #store.get_sorted_bookmarks_for_file("/test.lua"))
		end)

		it("returns 0 when no bookmarks", function()
			local count = store.clear_all_bookmarks()

			assert.are.equal(0, count)
		end)
	end)

	describe("get_bookmarks", function()
		it("returns deep copy", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1", note = "original" })

			local bookmarks = store.get_bookmarks()
			bookmarks[1].note = "modified"

			local bookmarks2 = store.get_bookmarks()
			assert.are.equal("original", bookmarks2[1].note)
		end)

		it("returns empty table when no bookmarks", function()
			local bookmarks = store.get_bookmarks()

			assert.is_table(bookmarks)
			assert.are.equal(0, #bookmarks)
		end)
	end)

	describe("get_all_raw", function()
		it("returns direct reference (not a copy)", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1", note = "original" })

			local bookmarks = store.get_all_raw()
			bookmarks[1].note = "modified"

			local bookmarks2 = store.get_all_raw()
			assert.are.equal("modified", bookmarks2[1].note)
		end)
	end)

	describe("has_bookmarks", function()
		it("returns false when empty", function()
			assert.is_false(store.has_bookmarks())
		end)

		it("returns true when bookmarks exist", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })

			assert.is_true(store.has_bookmarks())
		end)
	end)

	describe("save", function()
		it("delegates to persistence", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })

			local success = store.save()

			assert.is_true(success)
			assert.is_true(mock_persistence.was_called("save_bookmarks"))
		end)

		it("passes current bookmarks to persistence", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "test1" })
			store.add_bookmark({ file = "/test.lua", line = 2, id = "test2" })

			store.save()

			assert.is_not_nil(mock_persistence.saved_bookmarks)
			assert.are.equal(2, #mock_persistence.saved_bookmarks)
		end)

		it("tracks the original line when a new line is inserted at the bookmark's position (issue #72)", function()
			-- Reproduces the exact scenario from issue #72: bookmark on line N,
			-- user inserts a line at line N (e.g. `O` to open a comment line
			-- above), so the original code shifts to line N+1. The bookmark
			-- must follow the original code, not stay pinned to N (which now
			-- holds the new comment line). Requires the tracking extmark to
			-- have right_gravity=true; with right_gravity=false the extmark
			-- left-anchors and stays on the inserted line.
			local display = require("haunt.display")

			local tmpfile = vim.fn.tempname() .. ".lua"
			local bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, tmpfile)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"line 1",
				"line 2",
				"target",
				"line 4",
			})

			local extmark_id = display.set_bookmark_mark(bufnr, { line = 3 })
			assert.is_not_nil(extmark_id)

			store.add_bookmark({
				file = tmpfile,
				line = 3,
				id = "gravity_test",
				extmark_id = extmark_id,
			})

			vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { "-- new comment" })

			store.save()

			local current_line = display.get_extmark_line(bufnr, extmark_id)
			vim.api.nvim_buf_delete(bufnr, { force = true })

			assert.are.equal(
				4,
				current_line,
				"extmark should have moved to line 4 (where 'target' lives now), not stayed on line 3 (the new comment)"
			)
			assert.are.equal(
				4,
				mock_persistence.saved_bookmarks[1].line,
				"persisted line should reflect 'target's new position"
			)
		end)

		it("syncs bookmark.line from the tracking extmark before persisting", function()
			-- The visual extmark moves with edits, but bookmark.line is never
			-- reassigned after creation. Without this sync, the file on disk
			-- pins the bookmark to its original line forever — exactly what
			-- issue #72 reports. Save must pull the current extmark position
			-- and write that, so a reload places the bookmark where the user
			-- last saw it visually.
			local display = require("haunt.display")

			local tmpfile = vim.fn.tempname() .. ".lua"
			local bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, tmpfile)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"line 1",
				"line 2",
				"line 3",
				"line 4",
				"line 5",
				"line 6",
			})

			local extmark_id = display.set_bookmark_mark(bufnr, { line = 5 })
			assert.is_not_nil(extmark_id)

			store.add_bookmark({
				file = tmpfile,
				line = 5,
				id = "drift_test",
				extmark_id = extmark_id,
			})

			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new 1", "new 2", "new 3" })
			assert.are.equal(8, display.get_extmark_line(bufnr, extmark_id))

			store.save()

			vim.api.nvim_buf_delete(bufnr, { force = true })

			assert.is_not_nil(mock_persistence.saved_bookmarks)
			assert.are.equal(1, #mock_persistence.saved_bookmarks)
			assert.are.equal(
				8,
				mock_persistence.saved_bookmarks[1].line,
				"expected save to capture the extmark's current line, not the stale bookmark.line"
			)
		end)
	end)

	-- Issue #108: range bookmarks sync their end line as well as their start.
	describe("range sync", function()
		local display, bufnr, tmpfile

		before_each(function()
			display = require("haunt.display")
			tmpfile = vim.fn.tempname() .. ".lua"
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, tmpfile)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three", "four", "five", "six" })

			local extmark_id = display.set_bookmark_mark(bufnr, { line = 2, end_line = 4 })
			store.add_bookmark({
				file = tmpfile,
				line = 2,
				end_line = 4,
				id = "range",
				extmark_id = extmark_id,
			})
		end)

		after_each(function()
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("saves the tracked range, not the range it was created with", function()
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new top" })

			store.save()

			local saved = mock_persistence.saved_bookmarks[1]
			assert.are.equal(3, saved.line)
			assert.are.equal(5, saved.end_line)
		end)

		it("collapses to one line when every line of the range is deleted", function()
			vim.api.nvim_buf_set_lines(bufnr, 1, 4, false, {})

			local bookmark = store.get_bookmarks()[1]
			assert.are.equal(2, bookmark.line)
			assert.is_nil(bookmark.end_line)
		end)

		it("gets its range back when the deletion is undone", function()
			vim.cmd("let &undolevels = &undolevels")
			vim.cmd("normal! 2G3dd")
			-- A read while the range is gone syncs it down to one line.
			assert.is_nil(store.get_bookmarks()[1].end_line)

			vim.cmd("normal! u")

			local bookmark = store.get_bookmarks()[1]
			assert.are.equal(2, bookmark.line)
			assert.are.equal(4, bookmark.end_line)
		end)
	end)

	describe("load", function()
		it("loads bookmarks from persistence", function()
			mock_persistence.bookmarks_to_load = {
				{ file = "/loaded.lua", line = 5, id = "loaded1" },
				{ file = "/loaded.lua", line = 10, id = "loaded2" },
			}

			-- Reset to clear loaded state
			helpers.reset_modules()
			package.loaded["haunt.persistence"] = mock_persistence
			store = require("haunt.store")

			local success = store.load()

			assert.is_true(success)
			assert.are.equal(2, #store.get_bookmarks())
		end)

		it("rebuilds file index after load", function()
			mock_persistence.bookmarks_to_load = {
				{ file = "/test.lua", line = 30, id = "t3" },
				{ file = "/test.lua", line = 10, id = "t1" },
				{ file = "/test.lua", line = 20, id = "t2" },
			}

			helpers.reset_modules()
			package.loaded["haunt.persistence"] = mock_persistence
			store = require("haunt.store")
			store.load()

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(10, sorted[1].line)
			assert.are.equal(20, sorted[2].line)
			assert.are.equal(30, sorted[3].line)
		end)

		it("only loads once", function()
			mock_persistence.bookmarks_to_load = {
				{ file = "/test.lua", line = 1, id = "t1" },
			}

			helpers.reset_modules()
			package.loaded["haunt.persistence"] = mock_persistence
			store = require("haunt.store")

			store.load()
			store.load()
			store.load()

			local load_calls = mock_persistence.get_calls("load_bookmarks")
			assert.are.equal(1, #load_calls)
		end)
	end)

	describe("file-based indexing (integration)", function()
		-- These tests verify the full indexing behavior

		it("handles multiple files independently", function()
			store.add_bookmark({ file = "/a.lua", line = 1, id = "a1" })
			store.add_bookmark({ file = "/a.lua", line = 3, id = "a3" })
			store.add_bookmark({ file = "/b.lua", line = 2, id = "b2" })
			store.add_bookmark({ file = "/b.lua", line = 4, id = "b4" })

			local sorted_a = store.get_sorted_bookmarks_for_file("/a.lua")
			local sorted_b = store.get_sorted_bookmarks_for_file("/b.lua")

			assert.are.equal(2, #sorted_a)
			assert.are.equal(2, #sorted_b)
			assert.are.equal(1, sorted_a[1].line)
			assert.are.equal(3, sorted_a[2].line)
			assert.are.equal(2, sorted_b[1].line)
			assert.are.equal(4, sorted_b[2].line)
		end)

		it("cleans up empty file entries from index", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "t1" })
			store.remove_bookmark({ file = "/test.lua", line = 1, id = "t1" })

			-- Internal state should be clean (verified by no errors on subsequent operations)
			store.add_bookmark({ file = "/test.lua", line = 2, id = "t2" })

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(1, #sorted)
			assert.are.equal(2, sorted[1].line)
		end)

		it("handles rapid add/remove cycles", function()
			for i = 1, 100 do
				store.add_bookmark({ file = "/test.lua", line = i, id = "t" .. i })
			end

			for i = 1, 50 do
				store.remove_bookmark({ file = "/test.lua", line = i * 2, id = "t" .. (i * 2) })
			end

			local remaining = store.get_bookmarks()
			assert.are.equal(50, #remaining)

			local sorted = store.get_sorted_bookmarks_for_file("/test.lua")
			assert.are.equal(50, #sorted)

			-- Verify sorting is maintained
			for i = 2, #sorted do
				assert.is_true(sorted[i].line > sorted[i - 1].line)
			end
		end)
	end)
end)
