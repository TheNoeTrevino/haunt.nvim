---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.restoration", function()
	local restoration
	local store
	local display
	local bufnr, test_file

	before_each(function()
		helpers.reset_modules()

		-- Setup real modules (integration style)
		local config = require("haunt.config")
		config.setup()

		store = require("haunt.store")
		store._reset_for_testing()

		display = require("haunt.display")
		restoration = require("haunt.restoration")
	end)

	after_each(function()
		helpers.cleanup_buffer(bufnr, test_file)
	end)

	describe("restore_buffer_bookmarks", function()
		it("restores bookmarks for buffer", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			-- Add bookmarks to store
			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "First" })
			store.add_bookmark({ file = test_file, line = 3, id = "b3", note = "Third" })

			local success = restoration.restore_buffer_bookmarks(bufnr, true)

			assert.is_true(success)

			-- Check that extmarks were created
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#extmarks > 0)
		end)

		it("creates signs for bookmarks", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 2, id = "b2", note = "Test" })

			restoration.restore_buffer_bookmarks(bufnr, true)

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.is_true(#signs > 0)
			assert.is_true(#signs[1].signs > 0)
		end)

		it("shows annotations when annotations_visible is true", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Visible note" })

			restoration.restore_buffer_bookmarks(bufnr, true)

			-- Check for virtual text extmarks
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

			local has_virt_text = false
			for _, mark in ipairs(extmarks) do
				if mark[4] and mark[4].virt_text then
					has_virt_text = true
					break
				end
			end
			assert.is_true(has_virt_text)
		end)

		it("hides annotations when annotations_visible is false", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Hidden note" })

			restoration.restore_buffer_bookmarks(bufnr, false)

			-- Check that no virtual text extmarks exist
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

			local annotation_count = 0
			for _, mark in ipairs(extmarks) do
				if mark[4] and mark[4].virt_text then
					annotation_count = annotation_count + 1
				end
			end
			assert.are.equal(0, annotation_count)
		end)

		it("skips buffers with no bookmarks", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			-- No bookmarks added

			local success = restoration.restore_buffer_bookmarks(bufnr, true)

			assert.is_true(success)

			-- No extmarks should exist
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.are.equal(0, #extmarks)
		end)

		it("is idempotent - calling twice doesn't create duplicates", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Test" })

			restoration.restore_buffer_bookmarks(bufnr, true)
			local ns = display.get_namespace()
			local extmarks_first = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

			-- Call again
			restoration.restore_buffer_bookmarks(bufnr, true)
			local extmarks_second = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

			-- Should have same number of extmarks
			assert.are.equal(#extmarks_first, #extmarks_second)
		end)

		it("returns true for invalid buffer", function()
			-- Should return true (skip gracefully) for special buffers
			local result = restoration.restore_buffer_bookmarks(99999, true)
			assert.is_true(result)
		end)

		it("returns true for unnamed buffer", function()
			local unnamed_bufnr = vim.api.nvim_create_buf(false, false)

			local result = restoration.restore_buffer_bookmarks(unnamed_bufnr, true)

			assert.is_true(result)
			vim.api.nvim_buf_delete(unnamed_bufnr, { force = true })
		end)

		it("handles bookmarks in file not matching buffer", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			-- Add bookmark for different file
			store.add_bookmark({ file = "/other/file.lua", line = 1, id = "other" })

			local success = restoration.restore_buffer_bookmarks(bufnr, true)

			assert.is_true(success)

			-- No extmarks for this buffer
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.are.equal(0, #extmarks)
		end)

		it("updates bookmark extmark_id after restoration", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			local bookmark = { file = test_file, line = 2, id = "b2", note = "Test" }
			store.add_bookmark(bookmark)

			-- extmark_id should be nil before restoration
			local bookmarks_before = store.get_all_raw()
			assert.is_nil(bookmarks_before[1].extmark_id)

			restoration.restore_buffer_bookmarks(bufnr, true)

			-- extmark_id should be set after restoration
			local bookmarks_after = store.get_all_raw()
			assert.is_not_nil(bookmarks_after[1].extmark_id)
		end)
	end)

	describe("cleanup_buffer_tracking", function()
		it("allows re-restoration after cleanup", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Test" })

			-- First restoration
			restoration.restore_buffer_bookmarks(bufnr, true)

			-- Cleanup tracking
			restoration.cleanup_buffer_tracking(bufnr)

			-- Clear extmarks to simulate buffer reload
			display.clear_buffer_marks(bufnr)

			-- Should be able to restore again
			restoration.restore_buffer_bookmarks(bufnr, true)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#extmarks > 0)
		end)

		it("handles cleanup of non-tracked buffer", function()
			-- Should not error
			local ok = pcall(restoration.cleanup_buffer_tracking, 99999)
			assert.is_true(ok)
		end)
	end)

	describe("multiple bookmarks", function()
		it("restores all bookmarks in buffer", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "First" })
			store.add_bookmark({ file = test_file, line = 3, id = "b3", note = "Third" })
			store.add_bookmark({ file = test_file, line = 5, id = "b5", note = "Fifth" })

			restoration.restore_buffer_bookmarks(bufnr, true)

			-- Should have signs at all three lines
			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.are.equal(3, #signs[1].signs)
		end)

		it("restores bookmarks without notes (sign only)", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 2, id = "b2" }) -- No note

			restoration.restore_buffer_bookmarks(bufnr, true)

			-- Should have sign
			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.are.equal(1, #signs[1].signs)

			-- Should not have virtual text annotation
			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

			local annotation_count = 0
			for _, mark in ipairs(extmarks) do
				if mark[4] and mark[4].virt_text then
					annotation_count = annotation_count + 1
				end
			end
			assert.are.equal(0, annotation_count)
		end)
	end)

	describe("error handling", function()
		it("handles buffer becoming invalid during restoration", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Test" })

			-- Delete buffer before restoration completes (simulated by using invalid bufnr)
			-- We can't easily simulate mid-restoration deletion, so test with already-invalid
			vim.api.nvim_buf_delete(bufnr, { force = true })

			local ok, result = pcall(restoration.restore_buffer_bookmarks, bufnr, true)

			-- Should not throw, just return true (skip)
			assert.is_true(ok)
			assert.is_true(result)

			-- Prevent cleanup error
			bufnr = nil
		end)
	end)
end)
