---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.persistence", function()
	local persistence

	before_each(function()
		helpers.reset_modules()
		persistence = require("haunt.persistence")
	end)

	describe("get_git_info", function()
		it("returns a table", function()
			local git_info = persistence.get_git_info()
			assert.is_table(git_info)
		end)

		it("has root as string or nil", function()
			local git_info = persistence.get_git_info()
			local root_type = type(git_info.root)
			assert.is_true(root_type == "string" or root_type == "nil")
		end)

		it("has branch as string or nil", function()
			local git_info = persistence.get_git_info()
			local branch_type = type(git_info.branch)
			assert.is_true(branch_type == "string" or branch_type == "nil")
		end)
	end)

	describe("get_storage_path", function()
		it("returns a valid path", function()
			local path = persistence.get_storage_path()
			assert.is_not_nil(path)
			assert.is_string(path)
		end)

	it("matches hash.json pattern", function()
		local path = persistence.get_storage_path()
		local hash = path:match("([0-9a-f]+)%.json$")
		assert.is_not_nil(hash)
		assert.are.equal(12, #hash)
	end)

		it("returns consistent path across calls", function()
			local path1 = persistence.get_storage_path()
			local path2 = persistence.get_storage_path()
			assert.are.equal(path1, path2)
		end)
	end)

	describe("ensure_data_dir", function()
		it("creates and returns valid directory", function()
			local data_dir = persistence.ensure_data_dir()
			assert.are.equal(1, vim.fn.isdirectory(data_dir))
		end)
	end)

	describe("create_bookmark", function()
		it("creates bookmark with all fields", function()
			local bookmark = persistence.create_bookmark("/tmp/test.lua", 42, "Test note")

			assert.is_table(bookmark)
			assert.are.equal("/tmp/test.lua", bookmark.file)
			assert.are.equal(42, bookmark.line)
			assert.are.equal("Test note", bookmark.note)
			assert.is_string(bookmark.id)
			assert.is_true(#bookmark.id > 0)
			assert.is_nil(bookmark.extmark_id)
		end)

		it("creates bookmark without note", function()
			local bookmark = persistence.create_bookmark("/tmp/test.lua", 10)
			assert.is_nil(bookmark.note)
		end)

		it("generates unique IDs", function()
			local b1 = persistence.create_bookmark("/tmp/test.lua", 1)
			local b2 = persistence.create_bookmark("/tmp/test.lua", 1)
			assert.are_not.equal(b1.id, b2.id)
		end)
	end)

	describe("is_valid_bookmark", function()
		local valid_cases = {
			{ desc = "full bookmark", bookmark = { file = "/test.lua", line = 1, id = "abc", note = "note" }, valid = true },
			{ desc = "without note", bookmark = { file = "/test.lua", line = 1, id = "abc" }, valid = true },
		}

		local invalid_cases = {
			{ desc = "nil", bookmark = nil, valid = false },
			{ desc = "empty table", bookmark = {}, valid = false },
			{ desc = "empty file", bookmark = { file = "", line = 1, id = "abc" }, valid = false },
			{ desc = "line < 1", bookmark = { file = "/test.lua", line = 0, id = "abc" }, valid = false },
			{ desc = "empty id", bookmark = { file = "/test.lua", line = 1, id = "" }, valid = false },
		}

		for _, case in ipairs(valid_cases) do
			it("accepts " .. case.desc, function()
				assert.is_true(persistence.is_valid_bookmark(case.bookmark))
			end)
		end

		for _, case in ipairs(invalid_cases) do
			it("rejects " .. case.desc, function()
				assert.is_false(persistence.is_valid_bookmark(case.bookmark))
			end)
		end
	end)

	describe("save_bookmarks / load_bookmarks", function()
		local test_file

		before_each(function()
			local test_dir = vim.fn.stdpath("data") .. "/haunt/test/"
			vim.fn.mkdir(test_dir, "p")
			test_file = test_dir .. "test_" .. os.time() .. ".json"
		end)

		after_each(function()
			if test_file and vim.fn.filereadable(test_file) == 1 then
				vim.fn.delete(test_file)
			end
		end)

		it("saves and loads bookmarks correctly", function()
			local bookmarks = {
				persistence.create_bookmark("/tmp/file1.lua", 10, "First"),
				persistence.create_bookmark("/tmp/file2.lua", 20, "Second"),
				persistence.create_bookmark("/tmp/file3.lua", 30),
			}

			local save_ok = persistence.save_bookmarks(bookmarks, test_file)
			assert.is_true(save_ok)
			assert.are.equal(1, vim.fn.filereadable(test_file))

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(3, #loaded)
			assert.are.equal(bookmarks[1].file, loaded[1].file)
			assert.are.equal(bookmarks[1].line, loaded[1].line)
			assert.are.equal(bookmarks[1].note, loaded[1].note)
			assert.are.equal(bookmarks[1].id, loaded[1].id)
		end)

		it("returns empty table for non-existent file", function()
			local loaded = persistence.load_bookmarks("/nonexistent/path.json")
			assert.is_table(loaded)
			assert.are.equal(0, #loaded)
		end)

		it("handles empty bookmark list", function()
			local save_ok = persistence.save_bookmarks({}, test_file)
			assert.is_true(save_ok)

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(0, #loaded)
		end)

		it("handles large bookmark sets (100 bookmarks)", function()
			local bookmarks = {}
			for i = 1, 100 do
				table.insert(bookmarks, persistence.create_bookmark("/tmp/file" .. i .. ".lua", i, i % 2 == 0 and ("Note " .. i) or nil))
			end

			local save_ok = persistence.save_bookmarks(bookmarks, test_file)
			assert.is_true(save_ok)

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(100, #loaded)

			for i = 1, 100 do
				assert.are.equal(bookmarks[i].file, loaded[i].file)
				assert.are.equal(bookmarks[i].line, loaded[i].line)
				assert.are.equal(bookmarks[i].id, loaded[i].id)
			end
		end)
	end)
end)
