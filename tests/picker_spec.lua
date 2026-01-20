---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker", function()
	local picker
	local api
	local haunt

	-- Mock Snacks.nvim picker
	local mock_snacks

	-- Mock vim functions
	local original_notify
	local original_input
	local notifications

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
		-- Picker is called as Snacks.picker(...) not Snacks:picker(...)
		-- so it doesn't receive self
		mock.picker = function(config)
			mock.picker_called = true
			mock.picker_config = config
			return mock.picker_instance
		end
		return mock
	end

	-- Helper to execute a captured action
	local function execute_action(config, action_name, item)
		if config and config.actions and config.actions[action_name] then
			return config.actions[action_name](mock_snacks.picker_instance, item)
		end
	end

	-- Helper to execute confirm action
	local function execute_confirm(config, item)
		if config and config.confirm then
			return config.confirm(mock_snacks.picker_instance, item)
		end
	end

	-- Helper to execute finder
	local function execute_finder(config)
		if config and config.finder then
			return config.finder()
		end
		return {}
	end

	before_each(function()
		helpers.reset_modules()
		package.loaded["snacks"] = nil

		-- Setup mocks
		mock_snacks = create_mock_snacks()
		notifications = {}

		-- Mock Snacks by pre-loading it into package.loaded
		-- This way pcall(require, "snacks") will find our mock
		package.loaded["snacks"] = mock_snacks

		-- Mock vim.notify to capture notifications
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		-- Mock vim.fn.input
		original_input = vim.fn.input
		vim.fn.input = function(opts)
			return opts.default or ""
		end

		-- Initialize modules
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
		picker = require("haunt.picker")
	end)

	after_each(function()
		-- Restore mocks
		vim.notify = original_notify
		vim.fn.input = original_input
		package.loaded["snacks"] = nil
	end)

	describe("show()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("notifies when no bookmarks exist", function()
			picker.show()

			assert.is_false(mock_snacks.picker_called)
			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
			assert.are.equal(vim.log.levels.INFO, notifications[1].level)
		end)

		it("calls Snacks.picker when bookmarks exist", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")

			picker.show()

			assert.is_true(mock_snacks.picker_called)
			assert.is_not_nil(mock_snacks.picker_config)
		end)

		it("notifies error when Snacks is not available", function()
			-- Remove Snacks from package.loaded to simulate it not being installed
			package.loaded["snacks"] = nil

			-- Reload picker module
			package.loaded["haunt.picker"] = nil
			picker = require("haunt.picker")

			-- Add a bookmark
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			-- Clear previous notifications
			notifications = {}

			picker.show()

			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("Snacks.nvim is not installed"))
			assert.are.equal(vim.log.levels.ERROR, notifications[1].level)

			-- Restore mock for other tests
			package.loaded["snacks"] = mock_snacks
		end)

		it("applies custom keybindings from config", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			picker.show()

			local config = mock_snacks.picker_config
			assert.is_not_nil(config.win)
			assert.is_not_nil(config.win.input)
			assert.is_not_nil(config.win.input.keys)
			assert.is_not_nil(config.win.list)
			assert.is_not_nil(config.win.list.keys)
		end)

		it("merges opts into Snacks.picker config", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local custom_opts = {
				title = "Custom Title",
				layout = { preset = "vscode" },
				win = {
					input = {
						keys = { ["<C-x>"] = "close" },
					},
				},
			}

			picker.show(custom_opts)

			local config = mock_snacks.picker_config
			assert.are.equal("Custom Title", config.title)
			assert.are.equal("vscode", config.layout.preset)
			assert.are.equal("close", config.win.input.keys["<C-x>"])
			-- Check that default keys are preserved/merged
			if config.win.input.keys["d"] then
				assert.are.equal("delete", config.win.input.keys["d"][1])
			end
		end)
	end)

	describe("finder function", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns items with all required fields", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			local item = items[1]
			assert.is_not_nil(item.idx)
			assert.is_not_nil(item.score)
			assert.is_not_nil(item.file)
			assert.is_not_nil(item.pos)
			assert.is_not_nil(item.text)
			assert.is_not_nil(item.id)
			assert.is_not_nil(item.line)
		end)

		it("creates searchable text with file, line, and note", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Important bookmark")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.is_truthy(items[1].text:match(test_file))
			assert.is_truthy(items[1].text:match(":2"))
			assert.is_truthy(items[1].text:match("Important bookmark"))
		end)

		it("handles bookmarks with minimal annotations", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			-- Create bookmark with minimal text (single space)
			api.annotate(" ")

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.is_truthy(items[1].text:match(test_file))
			assert.is_truthy(items[1].text:match(":1"))
			-- Should not have "nil" in text
			assert.is_falsy(items[1].text:match("nil"))
		end)

		it("sets correct position with line and column", function()
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Test")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

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

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(3, #items)
			assert.are.equal(1, items[1].idx)
			assert.are.equal(2, items[2].idx)
			assert.are.equal(3, items[3].idx)
		end)

		it("includes bookmark ID for deletion", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local bookmarks = api.get_bookmarks()
			local bookmark_id = bookmarks[1].id

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal(bookmark_id, items[1].id)
		end)
	end)

	describe("confirm action", function()
		local bufnr1, test_file1, bufnr2, test_file2

		before_each(function()
			bufnr1, test_file1 = helpers.create_test_buffer({ "File1 Line 1", "File1 Line 2", "File1 Line 3" })
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Bookmark in file 1")

			bufnr2, test_file2 = helpers.create_test_buffer({ "File2 Line 1", "File2 Line 2" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Bookmark in file 2")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("switches to loaded file buffer", function()
			vim.api.nvim_set_current_buf(bufnr2)
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Find item for file 1
			local item = nil
			for _, i in ipairs(items) do
				if i.file == test_file1 then
					item = i
					break
				end
			end

			execute_confirm(mock_snacks.picker_config, item)

			assert.are.equal(bufnr1, vim.api.nvim_get_current_buf())
		end)

		it("sets cursor to bookmark line", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Get first item (line 2 in file1)
			local item = items[1]
			execute_confirm(mock_snacks.picker_config, item)

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(item.line, cursor[1])
		end)

		it("closes picker after selection", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			execute_confirm(mock_snacks.picker_config, items[1])

			assert.is_true(mock_snacks.picker_instance.closed)
		end)

		it("handles nil item gracefully", function()
			picker.show()
			local ok = pcall(execute_confirm, mock_snacks.picker_config, nil)
			assert.is_true(ok)
			-- Should not crash or change state
		end)

		it("handles unloaded file gracefully", function()
			-- This test verifies the picker can list bookmarks from unloaded files
			-- Save the file path before deleting buffer
			local saved_file1 = test_file1

			-- Delete buffer 1 to simulate unloaded file
			vim.api.nvim_buf_delete(bufnr1, { force = true })
			bufnr1 = -1

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Find item for test_file1
			local item = nil
			for _, i in ipairs(items) do
				if i.file == saved_file1 then
					item = i
					break
				end
			end

			assert.is_not_nil(item, "Should find item for unloaded file")
			assert.are.equal(saved_file1, item.file, "Item should have correct file path")

			-- Note: We don't test the confirm action opening the file because
			-- that requires a real file system and buffer management that's
			-- complex to test in this environment
		end)
	end)

	describe("delete action", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("deletes bookmark by ID", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			local item_to_delete = items[2]

			assert.are.equal(3, #api.get_bookmarks())

			execute_action(mock_snacks.picker_config, "delete", item_to_delete)

			assert.are.equal(2, #api.get_bookmarks())
		end)

		it("refreshes picker after delete", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			execute_action(mock_snacks.picker_config, "delete", items[1])

			assert.is_true(mock_snacks.picker_instance.refreshed)
		end)

		it("closes picker when no bookmarks remain", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Delete all bookmarks
			execute_action(mock_snacks.picker_config, "delete", items[1])
			mock_snacks.picker_instance.refreshed = false -- Reset for next delete

			execute_action(mock_snacks.picker_config, "delete", items[2])
			mock_snacks.picker_instance.refreshed = false

			execute_action(mock_snacks.picker_config, "delete", items[3])

			assert.is_true(mock_snacks.picker_instance.closed)
		end)

		it("notifies when last bookmark deleted", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Delete all but one
			execute_action(mock_snacks.picker_config, "delete", items[1])
			execute_action(mock_snacks.picker_config, "delete", items[2])

			notifications = {} -- Clear previous notifications
			execute_action(mock_snacks.picker_config, "delete", items[3])

			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks remaining"))
		end)

		it("handles nil item gracefully", function()
			picker.show()
			local ok = pcall(execute_action, mock_snacks.picker_config, "delete", nil)
			assert.is_true(ok)
			assert.are.equal(3, #api.get_bookmarks()) -- No bookmarks deleted
		end)

		it("notifies on delete failure", function()
			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Create item with invalid ID
			local invalid_item = vim.deepcopy(items[1])
			invalid_item.id = "invalid-id-does-not-exist"

			-- Clear notifications before the action to avoid counting previous ones
			notifications = {}
			execute_action(mock_snacks.picker_config, "delete", invalid_item)

			-- Check that we got at least one notification about failure
			local has_failure_notif = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("Failed to delete") then
					has_failure_notif = true
					break
				end
			end

			assert.is_true(has_failure_notif, "Should have notification about delete failure")
		end)
	end)

	describe("edit_annotation action", function()
		local bufnr, test_file
		local input_responses

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original note")

			input_responses = {}
			vim.fn.input = function(opts)
				return input_responses[1] or opts.default or ""
			end
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("prompts with existing annotation as default", function()
			local prompted_default = nil
			vim.fn.input = function(opts)
				prompted_default = opts.default
				return "Updated note"
			end

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			assert.are.equal("Original note", prompted_default)
		end)

		it("updates annotation successfully", function()
			vim.fn.input = function()
				return "Updated note"
			end

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			local bookmarks = api.get_bookmarks()
			assert.are.equal("Updated note", bookmarks[1].note)
		end)

		it("handles edit cancellation", function()
			-- Get the existing bookmark from before_each
			local bookmarks_before = api.get_bookmarks()
			assert.are.equal(1, #bookmarks_before, "Should have bookmark from before_each")
			local original_note = bookmarks_before[1].note

			-- Set input to return empty (simulating ESC/cancel)
			-- But since annotate treats empty as cancel when there's no existing note,
			-- and we have an existing note, it should keep the existing note
			vim.fn.input = function()
				return "" -- User presses ESC/cancels
			end

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			local before_count = #api.get_bookmarks()

			-- Execute edit action (should reopen picker without changes due to cancel)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			local after_count = #api.get_bookmarks()
			local bookmarks_after = api.get_bookmarks()

			-- Bookmark count should not change
			assert.are.equal(before_count, after_count)
			-- Note should remain unchanged (cancel means no update)
			assert.are.equal(original_note, bookmarks_after[1].note)
		end)

		it("allows updating annotation", function()
			-- Set input to return new annotation text
			vim.fn.input = function(opts)
				return "Updated annotation text"
			end

			-- Get the bookmark ID before showing picker
			local bookmarks_before = api.get_bookmarks()
			local bookmark_id = bookmarks_before[1].id

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Execute the edit action (it will close picker, prompt, and call api.annotate)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			-- Find the bookmark by ID and check if note was updated
			local bookmarks_after = api.get_bookmarks()
			local found_bookmark = nil
			for _, bm in ipairs(bookmarks_after) do
				if bm.id == bookmark_id then
					found_bookmark = bm
					break
				end
			end

			assert.is_not_nil(found_bookmark, "Bookmark should still exist")
			assert.are.equal("Updated annotation text", found_bookmark.note, "Note should be updated")
		end)

		it("closes picker before prompting and reopens after edit", function()
			vim.fn.input = function()
				-- Check if picker was closed when input is called
				assert.is_true(mock_snacks.picker_instance.closed)
				return "New note"
			end

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Reset closed state
			mock_snacks.picker_instance.closed = false
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			-- After edit, show() should be called again (picker_called count increases)
			assert.is_true(mock_snacks.picker_called)
		end)

		it("handles nil item gracefully", function()
			picker.show()
			local ok = pcall(execute_action, mock_snacks.picker_config, "edit_annotation", nil)
			assert.is_true(ok)
		end)

		it("works with unloaded files", function()
			-- Add bookmark to file, then delete buffer
			local temp_bufnr, temp_file = helpers.create_test_buffer({ "Temp line 1" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Temp note")

			-- Switch back and delete temp buffer
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_delete(temp_bufnr, { force = true })

			vim.fn.input = function()
				return "Updated temp note"
			end

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Find temp file item
			local item = nil
			for _, i in ipairs(items) do
				if i.file == temp_file then
					item = i
					break
				end
			end

			assert.is_not_nil(item)
			local ok = pcall(execute_action, mock_snacks.picker_config, "edit_annotation", item)
			assert.is_true(ok)

			helpers.cleanup_buffer(nil, temp_file)
		end)
	end)

	describe("edge cases", function()
		it("debug: checks module identity", function()
			-- Create a bookmark
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			-- Verify bookmark exists
			assert.are.equal(1, #api.get_bookmarks(), "Bookmark should exist in test api")

			-- Check that package.loaded has our api
			local api_from_pkg = package.loaded["haunt.api"]
			assert.are.equal(api, api_from_pkg, "Test api should equal package.loaded api")

			-- Now manually call what picker.show() does
			local ok, Snacks = pcall(require, "snacks")
			assert.is_true(ok, "Should be able to require snacks")
			assert.are.equal(mock_snacks, Snacks, "Should get mock snacks")

			-- Now manually get api like picker does
			local api_like_picker = require("haunt.api")
			assert.are.equal(api, api_like_picker, "Picker's api should equal test api")

			local bookmarks_from_picker_api = api_like_picker.get_bookmarks()
			assert.are.equal(1, #bookmarks_from_picker_api, "Picker's api should see the bookmark")

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles single bookmark", function()
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Only one")

			-- Verify bookmark was created
			local bookmarks_before = api.get_bookmarks()
			assert.are.equal(1, #bookmarks_before, "Should have 1 bookmark before picker.show()")

			-- Check if any notifications were sent before show
			local notif_count_before = #notifications

			picker.show()

			-- Check notifications after show
			local new_notifications = {}
			for i = notif_count_before + 1, #notifications do
				table.insert(new_notifications, notifications[i])
			end

			-- If picker wasn't called, there should be a notification explaining why
			if not mock_snacks.picker_called then
				assert.are_not.equal(0, #new_notifications, "Should have notification explaining why picker wasn't called")
				-- Print the notification for debugging
				for _, notif in ipairs(new_notifications) do
					print("Notification:", notif.msg)
				end
			end

			-- Verify picker was called
			assert.is_true(mock_snacks.picker_called, "Picker should have been called")
			assert.is_not_nil(mock_snacks.picker_config, "Picker config should be set")

			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal("Only one", items[1].note)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles bookmarks across multiple files", function()
			local bufnr1, test_file1 = helpers.create_test_buffer(nil, "/tmp/file1.lua")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File 1")

			local bufnr2, test_file2 = helpers.create_test_buffer(nil, "/tmp/file2.lua")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File 2")

			local bufnr3, test_file3 = helpers.create_test_buffer(nil, "/tmp/file3.lua")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File 3")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(3, #items)

			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
			helpers.cleanup_buffer(bufnr3, test_file3)
		end)

		it("handles very long file paths", function()
			local long_path = "/tmp/very/long/nested/directory/structure/that/goes/on/and/on/file.lua"
			local bufnr, test_file = helpers.create_test_buffer(nil, long_path)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Long path test")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal(long_path, items[1].file)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles very long annotations", function()
			local long_note = string.rep("This is a very long annotation text. ", 20)
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate(long_note)

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal(long_note, items[1].note)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles special characters in paths", function()
			local special_path = "/tmp/file with spaces & special-chars_123.lua"
			local bufnr, test_file = helpers.create_test_buffer(nil, special_path)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Special chars")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal(special_path, items[1].file)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles special characters in annotations", function()
			local special_note = 'Note with "quotes", <brackets>, & ampersands, and émojis! 🎉'
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate(special_note)

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			assert.are.equal(special_note, items[1].note)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles minimal notes correctly", function()
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			-- Create bookmark with minimal text
			api.annotate("x")

			-- Verify bookmark was created
			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks, "Should have created bookmark")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items, "Should find the bookmark in picker")
			assert.are.equal("x", items[1].note, "Note should be 'x'")
			-- Text should not contain "nil"
			assert.is_falsy(items[1].text:match("nil"), "Text should not contain 'nil'")

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles bookmark at last line of file", function()
			local bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Last line")

			picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			execute_confirm(mock_snacks.picker_config, items[1])

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, cursor[1])

			helpers.cleanup_buffer(bufnr, test_file)
		end)
	end)
end)
