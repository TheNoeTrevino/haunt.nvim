---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.hooks", function()
	local hooks
	local api

	before_each(function()
		helpers.reset_modules()
		hooks = require("haunt.hooks")
		api = require("haunt.api")
		local config = require("haunt.config")
		config.setup()
		hooks._reset_for_testing()
		api._reset_for_testing()
	end)

	describe("register", function()
		it("registers a callback for an event", function()
			local called = false
			hooks.on_create(function()
				called = true
			end)

			hooks.emit_create({})
			assert.is_true(called)
		end)

		it("allows multiple callbacks for same event", function()
			local call_count = 0
			hooks.on_create(function()
				call_count = call_count + 1
			end)
			hooks.on_create(function()
				call_count = call_count + 1
			end)

			hooks.emit_create({})
			assert.are.equal(2, call_count)
		end)

		it("does not register non-functions", function()
			hooks.on_create("not a function")
			-- should not error when emitting
			hooks.emit_create({})
		end)
	end)

	describe("unregister", function()
		it("removes a registered callback", function()
			local called = false
			local callback = function()
				called = true
			end

			hooks.on_create(callback)
			hooks.off_create(callback)

			hooks.emit_create({})
			assert.is_false(called)
		end)

		it("returns true when callback found and removed", function()
			local callback = function() end
			hooks.on_create(callback)

			local result = hooks.off_create(callback)
			assert.is_true(result)
		end)

		it("returns false when callback not found", function()
			local callback = function() end

			local result = hooks.off_create(callback)
			assert.is_false(result)
		end)
	end)

	describe("emit", function()
		it("passes context to callbacks", function()
			local received_ctx = nil
			hooks.on_create(function(ctx)
				received_ctx = ctx
			end)

			local test_ctx = { bookmark = { id = "test123" }, bufnr = 1 }
			hooks.emit_create(test_ctx)

			assert.is_not_nil(received_ctx)
			assert.are.equal("test123", received_ctx.bookmark.id)
			assert.are.equal(1, received_ctx.bufnr)
		end)

		it("catches errors in callbacks without breaking", function()
			local second_called = false

			hooks.on_create(function()
				error("intentional test error")
			end)
			hooks.on_create(function()
				second_called = true
			end)

			-- should not throw, and second callback should still run
			hooks.emit_create({})
			assert.is_true(second_called)
		end)
	end)

	describe("once", function()
		it("fires callback only once across multiple emits", function()
			local call_count = 0
			hooks.once_create(function()
				call_count = call_count + 1
			end)

			hooks.emit_create({})
			hooks.emit_create({})
			hooks.emit_create({})
			assert.are.equal(1, call_count)
		end)

		it("passes context to the once callback", function()
			local received_ctx = nil
			hooks.once_create(function(ctx)
				received_ctx = ctx
			end)

			hooks.emit_create({ bookmark = { id = "once-test" } })
			assert.is_not_nil(received_ctx)
			assert.are.equal("once-test", received_ctx.bookmark.id)
		end)

		it("does not interfere with regular on callbacks", function()
			local once_count = 0
			local on_count = 0

			hooks.once_create(function()
				once_count = once_count + 1
			end)
			hooks.on_create(function()
				on_count = on_count + 1
			end)

			hooks.emit_create({})
			hooks.emit_create({})

			assert.are.equal(1, once_count)
			assert.are.equal(2, on_count)
		end)
	end)

	describe("integration with api", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits bookmark_created when annotating", function()
			local received_ctx = nil
			hooks.on_create(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test annotation")

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmark)
			assert.are.equal(1, received_ctx.line)
			assert.are.equal(bufnr, received_ctx.bufnr)
		end)

		it("emits bookmark_deleted when deleting", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test annotation")

			hooks.on_delete(function(ctx)
				received_ctx = ctx
			end)

			api.delete()

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmark)
			assert.are.equal(1, received_ctx.line)
		end)

		it("emits bookmark_updated when updating annotation", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("original note")

			hooks.on_update(function(ctx)
				received_ctx = ctx
			end)

			api.annotate("updated note")

			assert.is_not_nil(received_ctx)
			assert.are.equal("original note", received_ctx.old_note)
			assert.are.equal("updated note", received_ctx.new_note)
		end)

		it("emits bookmark_deleted when using delete_by_id", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test note")

			local bookmarks = api.get_bookmarks()
			assert.are.equal(1, #bookmarks)

			hooks.on_delete(function(ctx)
				received_ctx = ctx
			end)

			api.delete_by_id(bookmarks[1].id)

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmark)
			assert.are.equal(1, received_ctx.line)
		end)

		it("once_create fires only on first bookmark creation", function()
			local call_count = 0
			hooks.once_create(function()
				call_count = call_count + 1
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("first note")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("second note")

			assert.are.equal(1, call_count)
		end)

		it("once_delete fires only on first bookmark deletion", function()
			local call_count = 0

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("note 2")

			hooks.once_delete(function()
				call_count = call_count + 1
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.delete()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.delete()

			assert.are.equal(1, call_count)
		end)
	end)

	describe("integration with navigation", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits navigation event on next", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("bookmark 2")

			hooks.on_navigation(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()

			assert.is_not_nil(received_ctx)
			assert.are.equal("next", received_ctx.direction)
			assert.are.equal(1, received_ctx.from_line)
			assert.are.equal(3, received_ctx.to_line)
		end)

		it("emits navigation event on prev", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("bookmark 2")

			hooks.on_navigation(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.prev()

			assert.is_not_nil(received_ctx)
			assert.are.equal("prev", received_ctx.direction)
			assert.are.equal(3, received_ctx.from_line)
			assert.are.equal(1, received_ctx.to_line)
		end)

		it("once_navigation fires only on first navigation", function()
			local call_count = 0

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("bookmark 1")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("bookmark 2")

			hooks.once_navigation(function()
				call_count = call_count + 1
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.next()
			api.next()

			assert.are.equal(1, call_count)
		end)
	end)

	describe("onToggle", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onToggle when hiding annotation", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test note")

			hooks.on_toggle(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.toggle_annotation()

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmark)
			assert.are.equal(bufnr, received_ctx.bufnr)
			assert.is_false(received_ctx.visible)
		end)

		it("emits onToggle when showing annotation", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test note")

			-- hide first
			api.toggle_annotation()

			hooks.on_toggle(function(ctx)
				received_ctx = ctx
			end)

			-- show again
			api.toggle_annotation()

			assert.is_not_nil(received_ctx)
			assert.is_true(received_ctx.visible)
		end)
	end)

	describe("onToggleAll", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onToggleAll with visibility state and count", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("note 2")

			hooks.on_toggle_all(function(ctx)
				received_ctx = ctx
			end)

			-- toggle all off (starts visible, so first toggle hides)
			api.toggle_all_lines()

			assert.is_not_nil(received_ctx)
			assert.is_false(received_ctx.visible)
			assert.are.equal(2, received_ctx.count)
		end)

		it("emits onToggleAll when showing all", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")

			-- hide all first
			api.toggle_all_lines()

			hooks.on_toggle_all(function(ctx)
				received_ctx = ctx
			end)

			-- show all again
			api.toggle_all_lines()

			assert.is_not_nil(received_ctx)
			assert.is_true(received_ctx.visible)
		end)
	end)

	describe("onPreSave and onPostSave", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onPreSave before saving", function()
			local received_ctx = nil

			hooks.on_pre_save(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test note")

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmarks)
			assert.is_number(received_ctx.count)
			assert.is_false(received_ctx.async)
		end)

		it("emits onPostSave after saving", function()
			local received_ctx = nil

			hooks.on_post_save(function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("test note")

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmarks)
			assert.is_number(received_ctx.count)
			assert.is_true(received_ctx.success)
			assert.is_false(received_ctx.async)
		end)

		it("onPreSave context contains bookmarks being saved", function()
			local pre_save_bookmarks = nil

			hooks.on_pre_save(function(ctx)
				pre_save_bookmarks = ctx.bookmarks
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("first note")

			assert.is_not_nil(pre_save_bookmarks)
			assert.is_true(#pre_save_bookmarks >= 1)
		end)

		it("onPostSave context contains bookmarks that were saved", function()
			local post_save_bookmarks = nil

			hooks.on_post_save(function(ctx)
				post_save_bookmarks = ctx.bookmarks
			end)

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("first note")

			assert.is_not_nil(post_save_bookmarks)
			assert.is_true(#post_save_bookmarks >= 1)
		end)
	end)

	describe("onLoad", function()
		it("emits onLoad when bookmarks are loaded", function()
			-- Reset modules to get a fresh store that hasn't loaded yet
			helpers.reset_modules()
			hooks = require("haunt.hooks")
			api = require("haunt.api")
			local config = require("haunt.config")
			config.setup()
			hooks._reset_for_testing()

			local received_ctx = nil

			hooks.on_load(function(ctx)
				received_ctx = ctx
			end)

			-- Force a load (store._loaded is false after fresh require)
			api.load()

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmarks)
			assert.is_number(received_ctx.count)
		end)
	end)

	describe("onRestore", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onRestore when buffer bookmarks are restored", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("restore me")

			-- Reset restoration tracking so we can trigger it again
			local restoration = require("haunt.restoration")
			restoration.cleanup_buffer_tracking(bufnr)

			-- Clear extmarks so restoration thinks it needs to restore
			local display = require("haunt.display")
			display.clear_buffer_marks(bufnr)

			hooks.on_restore(function(ctx)
				received_ctx = ctx
			end)

			api.restore_buffer_bookmarks(bufnr)

			assert.is_not_nil(received_ctx)
			assert.are.equal(bufnr, received_ctx.bufnr)
			assert.is_string(received_ctx.file)
			assert.are.equal(1, received_ctx.count)
		end)
	end)

	describe("onClear", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onClear when clearing file bookmarks", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("note 2")

			hooks.on_clear(function(ctx)
				received_ctx = ctx
			end)

			api.clear()

			assert.is_not_nil(received_ctx)
			assert.is_string(received_ctx.file)
			assert.are.equal(2, received_ctx.count)
			assert.are.equal(2, #received_ctx.bookmarks)
		end)

		it("also emits onDelete for each bookmark during clear", function()
			local delete_count = 0

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("note 2")

			hooks.on_delete(function()
				delete_count = delete_count + 1
			end)

			api.clear()

			assert.are.equal(2, delete_count)
		end)
	end)

	describe("onClearAll", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onClearAll when clearing all bookmarks", function()
			local received_ctx = nil

			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("note 1")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("note 2")

			hooks.on_clear_all(function(ctx)
				received_ctx = ctx
			end)

			-- Stub confirm to auto-accept
			local original_confirm = vim.fn.confirm
			vim.fn.confirm = function()
				return 1
			end

			api.clear_all()

			vim.fn.confirm = original_confirm

			assert.is_not_nil(received_ctx)
			assert.are.equal(2, received_ctx.count)
			assert.is_not_nil(received_ctx.bookmarks)
		end)
	end)

	describe("onDataDirChange", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("emits onDataDirChange when switching data directory", function()
			local received_ctx = nil
			local temp_dir = helpers.create_temp_data_dir()

			hooks.on_data_dir_change(function(ctx)
				received_ctx = ctx
			end)

			api.change_data_dir(temp_dir)

			assert.is_not_nil(received_ctx)
			assert.are.equal(temp_dir, received_ctx.new_dir)
			assert.is_string(received_ctx.old_dir)

			-- Reset back to default
			api.change_data_dir(nil)
			helpers.cleanup_temp_dir(temp_dir)
		end)

		it("emits onDataDirChange with nil new_dir when resetting", function()
			local received_ctx = nil
			local temp_dir = helpers.create_temp_data_dir()

			api.change_data_dir(temp_dir)

			hooks.on_data_dir_change(function(ctx)
				received_ctx = ctx
			end)

			api.change_data_dir(nil)

			assert.is_not_nil(received_ctx)
			assert.is_nil(received_ctx.new_dir)
			assert.is_string(received_ctx.old_dir)

			helpers.cleanup_temp_dir(temp_dir)
		end)
	end)
end)
