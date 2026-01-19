---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.display", function()
	local display
	---@class haunt.Persistence
	local persistence
	---@class haunt.Config
	local config

	before_each(function()
		helpers.reset_modules()
		display = require("haunt.display")
		persistence = require("haunt.persistence")
		config = require("haunt.config")
		config.setup() -- Initialize with defaults
	end)

	describe("setup_signs", function()
		it("initializes display module", function()
			assert.is_true(display.is_initialized())
		end)

		it("uses default config values", function()
			local cfg = display.get_config()
			assert.are.equal("󱙝", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)

		local custom_configs = {
			{ field = "sign", value = "🔖" },
			{ field = "sign_hl", value = "WarningMsg" },
			{ field = "line_hl", value = "CursorLine" },
			{ field = "virt_text_hl", value = "Comment" },
		}

		for _, case in ipairs(custom_configs) do
			it("accepts custom " .. case.field, function()
				config.setup({ [case.field] = case.value })
				local cfg = display.get_config()
				assert.are.equal(case.value, cfg[case.field])
			end)
		end
	end)

	describe("show_annotation / hide_annotation", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("creates extmark with correct properties", function()
			local extmark_id = display.show_annotation(bufnr, 2, "Test note")

			assert.is_number(extmark_id)
			assert.is_true(extmark_id > 0)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
			local found = false
			for _, mark in ipairs(extmarks) do
				if mark[1] == extmark_id then
					found = true
					assert.is_not_nil(mark[4].virt_text)
				end
			end
			assert.is_true(found)
		end)

		it("removes extmark on hide", function()
			local extmark_id = display.show_annotation(bufnr, 2, "Test note")
			display.hide_annotation(bufnr, extmark_id)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			local found = false
			for _, mark in ipairs(extmarks) do
				if mark[1] == extmark_id then
					found = true
				end
			end
			assert.is_false(found)
		end)
	end)

	describe("set_bookmark_mark / get_extmark_line / delete_bookmark_mark", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("creates extmark at correct line", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			assert.not_nil(bookmark)
			---@cast bookmark -nil

			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)
			assert.not_nil(extmark_id)
			---@cast extmark_id -nil

			assert.is_number(extmark_id)
			assert.is_true(extmark_id > 0)

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(3, line)
		end)

		it("tracks line movement on insert above", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			assert.not_nil(bookmark)
			---@cast bookmark -nil

			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)
			assert.not_nil(extmark_id)
			---@cast extmark_id -nil

			-- Insert line above
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "New Line" })

			local new_line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(4, new_line)
		end)

		it("tracks line movement on delete above", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)

			-- Insert then delete
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "New Line" })
			vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(3, line)
		end)

		it("deletes extmark successfully", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)

			local delete_ok = display.delete_bookmark_mark(bufnr, extmark_id)
			assert.is_true(delete_ok)

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.is_nil(line)
		end)
	end)

	describe("clear_buffer_marks", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("clears all extmarks from buffer", function()
			local b1 = persistence.create_bookmark("test.lua", 1)
			local b2 = persistence.create_bookmark("test.lua", 2)
			local b3 = persistence.create_bookmark("test.lua", 3)

			local e1 = display.set_bookmark_mark(bufnr, b1)
			local e2 = display.set_bookmark_mark(bufnr, b2)
			local e3 = display.set_bookmark_mark(bufnr, b3)

			assert.is_not_nil(e1)
			assert.is_not_nil(e2)
			assert.is_not_nil(e3)

			local clear_ok = display.clear_buffer_marks(bufnr)
			assert.is_true(clear_ok)

			assert.is_nil(display.get_extmark_line(bufnr, e1))
			assert.is_nil(display.get_extmark_line(bufnr, e2))
			assert.is_nil(display.get_extmark_line(bufnr, e3))
		end)
	end)

	describe("place_sign / unplace_sign", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("places sign at correct line", function()
			display.place_sign(bufnr, 2, 100)

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.is_true(#signs > 0)
			assert.is_true(#signs[1].signs > 0)

			local found = false
			for _, sign in ipairs(signs[1].signs) do
				if sign.id == 100 then
					found = true
					assert.are.equal(2, sign.lnum)
					assert.are.equal("HauntBookmark", sign.name)
				end
			end
			assert.is_true(found)
		end)

		it("removes sign on unplace", function()
			display.place_sign(bufnr, 2, 100)
			display.unplace_sign(bufnr, 100)

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			local found = false
			if #signs > 0 and #signs[1].signs > 0 then
				for _, sign in ipairs(signs[1].signs) do
					if sign.id == 100 then
						found = true
					end
				end
			end
			assert.is_false(found)
		end)
	end)
end)
