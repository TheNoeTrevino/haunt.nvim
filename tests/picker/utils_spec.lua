---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker.utils", function()
	local utils
	local api
	local haunt

	before_each(function()
		helpers.reset_modules()

		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
		utils = require("haunt.picker.utils")
	end)

	describe("build_picker_items()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns empty table for no bookmarks", function()
			local items = utils.build_picker_items({})
			assert.are.equal(0, #items)
		end)

		it("returns items with all required fields", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			local item = items[1]
			assert.is_not_nil(item.idx)
			assert.is_not_nil(item.score)
			assert.is_not_nil(item.file)
			assert.is_not_nil(item.relpath)
			assert.is_not_nil(item.filename)
			assert.is_not_nil(item.pos)
			assert.is_not_nil(item.text)
			assert.is_not_nil(item.id)
			assert.is_not_nil(item.line)
		end)

		it("caches relpath and filename", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			local item = items[1]
			-- relpath should be the relative path
			assert.are.equal(vim.fn.fnamemodify(item.file, ":."), item.relpath)
			-- filename should be just the filename
			assert.are.equal(vim.fn.fnamemodify(item.file, ":t"), item.filename)
		end)

		it("creates searchable text with file, line, and note", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Important bookmark")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			assert.is_truthy(items[1].text:match(test_file))
			assert.is_truthy(items[1].text:match(":2"))
			assert.is_truthy(items[1].text:match("Important bookmark"))
		end)

		it("sets correct position with line and column", function()
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Test")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			assert.are.equal(3, items[1].pos[1])
			assert.are.equal(0, items[1].pos[2])
			assert.are.equal(3, items[1].line)
		end)

		it("returns multiple bookmarks with correct indices", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(3, #items)
			assert.are.equal(1, items[1].idx)
			assert.are.equal(2, items[2].idx)
			assert.are.equal(3, items[3].idx)
		end)

		it("includes bookmark ID", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local bookmarks = api.get_bookmarks()
			local bookmark_id = bookmarks[1].id
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			assert.are.equal(bookmark_id, items[1].id)
		end)

		it("handles bookmarks without notes", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("x")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			assert.are.equal(1, #items)
			-- Text should not contain "nil"
			assert.is_falsy(items[1].text:match("nil"))
		end)
	end)

	describe("jump_to_bookmark()", function()
		local bufnr1, test_file1, bufnr2, test_file2

		before_each(function()
			bufnr1, test_file1 = helpers.create_test_buffer({ "File1 Line 1", "File1 Line 2", "File1 Line 3" })
			bufnr2, test_file2 = helpers.create_test_buffer({ "File2 Line 1", "File2 Line 2" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("switches to loaded file buffer", function()
			vim.api.nvim_set_current_buf(bufnr2)

			local item = { file = test_file1, line = 2 }
			utils.jump_to_bookmark(item)

			assert.are.equal(bufnr1, vim.api.nvim_get_current_buf())
		end)

		it("sets cursor to bookmark line", function()
			local item = { file = test_file1, line = 2 }
			utils.jump_to_bookmark(item)

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(2, cursor[1])
		end)

		it("handles nil item gracefully", function()
			local ok = pcall(utils.jump_to_bookmark, nil)
			assert.is_true(ok)
		end)
	end)

	describe("with_buffer_context()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("executes callback in buffer context", function()
			local callback_bufnr = nil
			utils.with_buffer_context(bufnr, 2, function()
				callback_bufnr = vim.api.nvim_get_current_buf()
			end)

			assert.are.equal(bufnr, callback_bufnr)
		end)

		it("returns callback result", function()
			local result = utils.with_buffer_context(bufnr, 1, function()
				return "test_result"
			end)

			assert.are.equal("test_result", result)
		end)

		it("clamps line to valid range", function()
			-- Line 100 doesn't exist, should clamp to last line (3)
			local ok = pcall(utils.with_buffer_context, bufnr, 100, function() end)
			assert.is_true(ok)
		end)
	end)

	describe("get_api()", function()
		it("returns the api module", function()
			local api_module = utils.get_api()
			assert.is_not_nil(api_module)
			assert.is_not_nil(api_module.get_bookmarks)
		end)
	end)

	describe("get_haunt()", function()
		it("returns the haunt module", function()
			local haunt_module = utils.get_haunt()
			assert.is_not_nil(haunt_module)
			assert.is_not_nil(haunt_module.get_config)
		end)
	end)

	describe("handle_edit_annotation()", function()
		local bufnr, test_file
		local original_input
		local close_called, reopen_called

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			original_input = vim.fn.input
			close_called = false
			reopen_called = false
		end)

		after_each(function()
			vim.fn.input = original_input
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("calls close_picker before prompting", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			-- Mock input to return a new annotation
			vim.fn.input = function()
				-- At this point, close should have been called
				assert.is_true(close_called)
				return "New annotation"
			end

			utils.handle_edit_annotation({
				item = items[1],
				close_picker = function()
					close_called = true
				end,
				reopen_picker = function()
					reopen_called = true
				end,
			})

			assert.is_true(close_called)
			assert.is_true(reopen_called)
		end)

		it("updates the bookmark annotation", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original")

			local bookmarks = api.get_bookmarks()
			local items = utils.build_picker_items(bookmarks)

			-- Mock input to return a new annotation
			vim.fn.input = function()
				return "Updated annotation"
			end

			utils.handle_edit_annotation({
				item = items[1],
				close_picker = function()
					close_called = true
				end,
				reopen_picker = function()
					reopen_called = true
				end,
			})

			-- Check that the annotation was updated
			local updated_bookmarks = api.get_bookmarks()
			assert.are.equal("Updated annotation", updated_bookmarks[1].note)
		end)

		it("reopens picker without saving when cancelled with no existing annotation", function()
			-- Create a mock item with no annotation (simulating a bookmark without note)
			local mock_item = {
				idx = 1,
				score = 1,
				file = test_file,
				relpath = vim.fn.fnamemodify(test_file, ":."),
				filename = vim.fn.fnamemodify(test_file, ":t"),
				pos = { 1, 0 },
				text = test_file .. ":1",
				note = nil, -- No existing annotation
				id = "mock-id",
				line = 1,
			}

			-- Mock input to return empty (simulating cancel)
			vim.fn.input = function()
				return ""
			end

			utils.handle_edit_annotation({
				item = mock_item,
				close_picker = function()
					close_called = true
				end,
				reopen_picker = function()
					reopen_called = true
				end,
			})

			assert.is_true(close_called)
			assert.is_true(reopen_called)
		end)

		it("handles nil item gracefully", function()
			utils.handle_edit_annotation({
				item = nil,
				close_picker = function()
					close_called = true
				end,
				reopen_picker = function()
					reopen_called = true
				end,
			})

			-- Should not call close or reopen
			assert.is_false(close_called)
			assert.is_false(reopen_called)
		end)
	end)
end)
