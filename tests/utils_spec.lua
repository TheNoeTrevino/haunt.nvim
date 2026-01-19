---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.utils", function()
	local utils

	before_each(function()
		helpers.reset_modules()
		utils = require("haunt.utils")
	end)

	describe("normalize_filepath", function()
		it("returns empty string for empty input", function()
			local result = utils.normalize_filepath("")
			assert.are.equal("", result)
		end)

		it("converts relative path to absolute", function()
			local result = utils.normalize_filepath("lua/haunt/utils.lua")
			assert.is_truthy(result:match("^/"))
		end)

		it("returns absolute path unchanged (preserves structure)", function()
			local absolute = "/home/user/project/file.lua"
			local result = utils.normalize_filepath(absolute)
			assert.are.equal(absolute, result)
		end)

		it("returns consistent results for same input", function()
			local path = "some/relative/path.lua"
			local result1 = utils.normalize_filepath(path)
			local result2 = utils.normalize_filepath(path)
			assert.are.equal(result1, result2)
		end)

		it("handles paths with special characters", function()
			local path = "/tmp/file with spaces.lua"
			local result = utils.normalize_filepath(path)
			assert.are.equal(path, result)
		end)

		it("handles dot-prefixed paths", function()
			local result = utils.normalize_filepath("./relative/path.lua")
			assert.is_truthy(result:match("^/"))
			assert.is_falsy(result:match("^%./"))
		end)
	end)

	describe("validate_buffer_for_bookmarks", function()
		local bufnr, test_file

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("accepts valid normal buffer", function()
			bufnr, test_file = helpers.create_test_buffer()

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_true(valid)
			assert.is_nil(err)
		end)

		it("rejects invalid buffer number", function()
			local valid, err = utils.validate_buffer_for_bookmarks(99999)

			assert.is_false(valid)
			assert.are.equal("Invalid buffer", err)
		end)

		it("rejects unnamed buffer", function()
			bufnr = vim.api.nvim_create_buf(false, false)

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.are.equal("Cannot bookmark unnamed buffer", err)
		end)

		-- Terminal buffer test removed: can't set buftype="terminal" in headless mode

		it("rejects help buffer", function()
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/test_help")
			vim.bo[bufnr].buftype = "help"

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.is_truthy(err:match("special buffers"))
		end)

		it("rejects nofile buffer", function()
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/test_nofile")
			vim.bo[bufnr].buftype = "nofile"

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.is_truthy(err:match("special buffers"))
		end)

		it("rejects non-modifiable buffer", function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.bo[bufnr].modifiable = false

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.are.equal("Cannot bookmark read-only buffer", err)

			-- Restore for cleanup
			vim.bo[bufnr].modifiable = true
		end)

		it("rejects protocol scheme buffers (term://)", function()
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, "term://localhost:1234")

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.is_truthy(err:match("protocol schemes"))
		end)

		it("rejects fugitive:// scheme", function()
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, "fugitive:///path/to/repo/.git//abc123")

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.is_truthy(err:match("protocol schemes"))
		end)

		it("rejects oil:// scheme", function()
			bufnr = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(bufnr, "oil:///home/user/projects")

			local valid, err = utils.validate_buffer_for_bookmarks(bufnr)

			assert.is_false(valid)
			assert.is_truthy(err:match("protocol schemes"))
		end)
	end)

	describe("ensure_buffer_for_file", function()
		local test_file

		before_each(function()
			test_file = vim.fn.tempname() .. ".lua"
			-- Create the file so it can be loaded
			vim.fn.writefile({ "test content" }, test_file)
		end)

		after_each(function()
			-- Clean up any buffers for this file
			local bufnr = vim.fn.bufnr(test_file)
			if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
			vim.fn.delete(test_file)
		end)

		it("creates buffer for file not yet loaded", function()
			local bufnr, err = utils.ensure_buffer_for_file(test_file)

			assert.is_not_nil(bufnr)
			assert.is_nil(err)
			assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
			assert.is_true(vim.api.nvim_buf_is_loaded(bufnr))
		end)

		it("returns existing buffer for already loaded file", function()
			-- First load
			local bufnr1, _ = utils.ensure_buffer_for_file(test_file)
			-- Second load
			local bufnr2, _ = utils.ensure_buffer_for_file(test_file)

			assert.are.equal(bufnr1, bufnr2)
		end)

		it("loads buffer if exists but not loaded", function()
			-- Create buffer without loading
			local bufnr = vim.fn.bufadd(test_file)
			assert.is_false(vim.api.nvim_buf_is_loaded(bufnr))

			local result_bufnr, err = utils.ensure_buffer_for_file(test_file)

			assert.is_nil(err)
			assert.are.equal(bufnr, result_bufnr)
			assert.is_true(vim.api.nvim_buf_is_loaded(result_bufnr))
		end)
	end)
end)
