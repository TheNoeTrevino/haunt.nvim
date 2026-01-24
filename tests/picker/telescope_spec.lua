---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker.telescope", function()
	local telescope_picker
	local api
	local haunt

	-- Mock vim functions
	local original_notify
	local notifications

	before_each(function()
		helpers.reset_modules()
		package.loaded["telescope"] = nil
		notifications = {}

		-- Mock vim.notify to capture notifications
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		-- Initialize modules
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
		telescope_picker = require("haunt.picker.telescope")
	end)

	after_each(function()
		vim.notify = original_notify
		package.loaded["telescope"] = nil
	end)

	describe("is_available()", function()
		it("returns false when Telescope is not installed", function()
			assert.is_false(telescope_picker.is_available())
		end)

		-- Note: Testing with real Telescope would require installing it
		-- These tests focus on the unavailable case
	end)

	describe("show()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns false when Telescope is not available", function()
			local result = telescope_picker.show()
			assert.is_false(result)
		end)

		it("does not notify when Telescope is not available", function()
			-- The show() function just returns false, doesn't notify
			-- Notification is handled by the parent picker module
			telescope_picker.show()
			assert.are.equal(0, #notifications)
		end)
	end)

	describe("set_picker_module()", function()
		it("accepts a module reference without error", function()
			local ok = pcall(telescope_picker.set_picker_module, { show = function() end })
			assert.is_true(ok)
		end)
	end)
end)

-- Integration tests with mock Telescope would require extensive mocking
-- of telescope.pickers, telescope.finders, telescope.config, etc.
-- These are better tested manually or with actual Telescope installed.
