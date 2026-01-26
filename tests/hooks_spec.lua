---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.hooks", function()
	local hooks
	local events
	local api

	before_each(function()
		helpers.reset_modules()
		hooks = require("haunt.hooks")
		events = require("haunt.hook_events")
		api = require("haunt.api")
		local config = require("haunt.config")
		config.setup()
		hooks._reset_for_testing()
		api._reset_for_testing()
	end)

	describe("register", function()
		it("registers a callback for an event", function()
			local called = false
			hooks.on(events.onCreate, function()
				called = true
			end)

			hooks.emit(events.onCreate, {})
			assert.is_true(called)
		end)

		it("allows multiple callbacks for same event", function()
			local call_count = 0
			hooks.on(events.onCreate, function()
				call_count = call_count + 1
			end)
			hooks.on(events.onCreate, function()
				call_count = call_count + 1
			end)

			hooks.emit(events.onCreate, {})
			assert.are.equal(2, call_count)
		end)

		it("does not register non-functions", function()
			hooks.on(events.onCreate, "not a function")
			-- should not error when emitting
			hooks.emit(events.onCreate, {})
		end)
	end)

	describe("unregister", function()
		it("removes a registered callback", function()
			local called = false
			local callback = function()
				called = true
			end

			hooks.on(events.onCreate, callback)
			hooks.off(events.onCreate, callback)

			hooks.emit(events.onCreate, {})
			assert.is_false(called)
		end)

		it("returns true when callback found and removed", function()
			local callback = function() end
			hooks.on(events.onCreate, callback)

			local result = hooks.off(events.onCreate, callback)
			assert.is_true(result)
		end)

		it("returns false when callback not found", function()
			local callback = function() end

			local result = hooks.off(events.onCreate, callback)
			assert.is_false(result)
		end)

		it("returns false for unregistered event", function()
			local callback = function() end

			local result = hooks.off("nonexistent_event", callback)
			assert.is_false(result)
		end)
	end)

	describe("emit", function()
		it("passes context to callbacks", function()
			local received_ctx = nil
			hooks.on(events.onCreate, function(ctx)
				received_ctx = ctx
			end)

			local test_ctx = { bookmark = { id = "test123" }, bufnr = 1 }
			hooks.emit(events.onCreate, test_ctx)

			assert.is_not_nil(received_ctx)
			assert.are.equal("test123", received_ctx.bookmark.id)
			assert.are.equal(1, received_ctx.bufnr)
		end)

		it("catches errors in callbacks without breaking", function()
			local second_called = false

			hooks.on(events.onCreate, function()
				error("intentional test error")
			end)
			hooks.on(events.onCreate, function()
				second_called = true
			end)

			-- should not throw, and second callback should still run
			hooks.emit(events.onCreate, {})
			assert.is_true(second_called)
		end)

		it("does nothing for unregistered events", function()
			-- should not error
			hooks.emit("nonexistent_event", {})
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
			hooks.on(events.onCreate, function(ctx)
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

			hooks.on(events.onDelete, function(ctx)
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

			hooks.on(events.onUpdate, function(ctx)
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

			hooks.on(events.onDelete, function(ctx)
				received_ctx = ctx
			end)

			api.delete_by_id(bookmarks[1].id)

			assert.is_not_nil(received_ctx)
			assert.is_not_nil(received_ctx.bookmark)
			assert.are.equal(1, received_ctx.line)
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

			hooks.on(events.onNavigation, function(ctx)
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

			hooks.on(events.onNavigation, function(ctx)
				received_ctx = ctx
			end)

			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.prev()

			assert.is_not_nil(received_ctx)
			assert.are.equal("prev", received_ctx.direction)
			assert.are.equal(3, received_ctx.from_line)
			assert.are.equal(1, received_ctx.to_line)
		end)
	end)
end)
