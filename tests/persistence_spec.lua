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

		describe("cache invalidation on cwd change", function()
			local original_cwd
			local non_git_dir

			before_each(function()
				original_cwd = vim.fn.getcwd()
				non_git_dir = helpers.create_temp_data_dir()
			end)

			after_each(function()
				vim.fn.chdir(original_cwd)
				helpers.cleanup_temp_dir(non_git_dir)
			end)

			it("re-fetches git info when cwd changes", function()
				local primed = persistence.get_git_info()
				assert.is_string(primed.root)

				vim.fn.chdir(non_git_dir)

				local fresh = persistence.get_git_info()
				assert.is_nil(fresh.root)
				assert.is_nil(fresh.branch)
			end)

			it("get_storage_path reflects fresh git info after cwd change", function()
				local path_in_repo = persistence.get_storage_path()

				vim.fn.chdir(non_git_dir)

				local path_after_cd = persistence.get_storage_path()
				assert.are_not.equal(path_in_repo, path_after_cd)
			end)

			it("returns cached info when cwd is unchanged", function()
				local first = persistence.get_git_info()
				local second = persistence.get_git_info()
				assert.are.equal(first.root, second.root)
				assert.are.equal(first.branch, second.branch)
			end)
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

		describe("per_branch_bookmarks config", function()
			local config

			before_each(function()
				config = require("haunt.config")
			end)

			it("uses different paths when per_branch_bookmarks is true vs false", function()
				config.setup({ per_branch_bookmarks = true })
				local path_with_branch = persistence.get_storage_path()

				helpers.reset_modules()
				persistence = require("haunt.persistence")
				config = require("haunt.config")

				config.setup({ per_branch_bookmarks = false })
				local path_without_branch = persistence.get_storage_path()

				assert.are_not.equal(path_with_branch, path_without_branch)
			end)

			it("returns consistent path when per_branch_bookmarks is false", function()
				config.setup({ per_branch_bookmarks = false })
				local path1 = persistence.get_storage_path()
				local path2 = persistence.get_storage_path()
				assert.are.equal(path1, path2)
			end)

			it("defaults to per_branch_bookmarks = true", function()
				local default_config = config.get()
				assert.is_true(default_config.per_branch_bookmarks)
			end)
		end)

		describe("project_id keying", function()
			local project_mock = require("tests.helpers.project_mock")
			local config

			before_each(function()
				config = require("haunt.config")
			end)

			after_each(function()
				project_mock.restore()
			end)

			it("returns the same path for the same mocked project_id", function()
				config.setup({ per_branch_bookmarks = true })
				project_mock.set({ root = "/fake/root", branch = "main", project_id = "fixed-project-id" })

				local path1 = persistence.get_storage_path()
				local path2 = persistence.get_storage_path()
				assert.are.equal(path1, path2)
			end)

			it("returns a different path when project_id changes", function()
				config.setup({ per_branch_bookmarks = true })

				project_mock.set({ root = "/fake/root", branch = "main", project_id = "project-a" })
				local path_a = persistence.get_storage_path()

				project_mock.set({ root = "/fake/root", branch = "main", project_id = "project-b" })
				local path_b = persistence.get_storage_path()

				assert.are_not.equal(path_a, path_b)
			end)

			it("produces different paths for different branches when project_id is constant", function()
				config.setup({ per_branch_bookmarks = true })

				project_mock.set({ root = "/fake/root", branch = "main", project_id = "fixed-project-id" })
				local path_main = persistence.get_storage_path()

				project_mock.set({ root = "/fake/root", branch = "feature/foo", project_id = "fixed-project-id" })
				local path_feature = persistence.get_storage_path()

				assert.are_not.equal(path_main, path_feature)
			end)

			it("ignores branch when per_branch_bookmarks is false", function()
				config.setup({ per_branch_bookmarks = false })

				project_mock.set({ root = "/fake/root", branch = "main", project_id = "fixed-project-id" })
				local path_main = persistence.get_storage_path()

				project_mock.set({ root = "/fake/root", branch = "feature/foo", project_id = "fixed-project-id" })
				local path_feature = persistence.get_storage_path()

				assert.are.equal(path_main, path_feature)
			end)
		end)
	end)

	describe("ensure_data_dir", function()
		it("creates and returns valid directory", function()
			local data_dir = persistence.ensure_data_dir()
			assert.are.equal(1, vim.fn.isdirectory(data_dir))
		end)
	end)

	describe("lazy directory creation", function()
		local temp_dir

		before_each(function()
			temp_dir = vim.fn.tempname() .. "_haunt_lazy/"
			persistence.set_data_dir(temp_dir)
		end)

		after_each(function()
			persistence.set_data_dir(nil)
			helpers.cleanup_temp_dir(temp_dir)
		end)

		it("get_storage_path does not create the data dir", function()
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
			persistence.get_storage_path()
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
		end)

		it("load_bookmarks does not create the data dir", function()
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
			local loaded = persistence.load_bookmarks()
			assert.are.equal(0, #loaded)
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
		end)

		it("save_bookmarks with empty list does not create the data dir", function()
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
			assert.is_true(persistence.save_bookmarks({}))
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
		end)

		it("save_bookmarks with non-empty list creates the data dir", function()
			assert.are.equal(0, vim.fn.isdirectory(temp_dir))
			local bookmarks = { persistence.create_bookmark("/tmp/lazy.lua", 1, "Note") }
			assert.is_true(persistence.save_bookmarks(bookmarks))
			assert.are.equal(1, vim.fn.isdirectory(temp_dir))
		end)
	end)

	describe("set_data_dir", function()
		after_each(function()
			persistence.set_data_dir(nil)
		end)

		it("expands tilde to home directory", function()
			local home = vim.fn.expand("~")
			persistence.set_data_dir("~/test_haunt_dir/")

			local result = persistence.ensure_data_dir()
			assert.are.equal(home .. "/test_haunt_dir/", result)

			vim.fn.delete(home .. "/test_haunt_dir", "rf")
		end)

		it("adds trailing slash if missing", function()
			local temp_dir = vim.fn.tempname() .. "_haunt_test"
			persistence.set_data_dir(temp_dir)

			local result = persistence.ensure_data_dir()
			assert.are.equal(temp_dir .. "/", result)

			vim.fn.delete(temp_dir, "rf")
		end)

		it("preserves trailing slash if present", function()
			local temp_dir = vim.fn.tempname() .. "_haunt_test/"
			persistence.set_data_dir(temp_dir)

			local result = persistence.ensure_data_dir()
			assert.are.equal(temp_dir, result)

			vim.fn.delete(temp_dir, "rf")
		end)

		it("resets to default when passed nil", function()
			local config = require("haunt.config")
			local temp_dir = vim.fn.tempname() .. "_haunt_test/"
			persistence.set_data_dir(temp_dir)

			assert.are.equal(temp_dir, persistence.ensure_data_dir())

			persistence.set_data_dir(nil)

			assert.are.equal(config.DEFAULT_DATA_DIR, persistence.ensure_data_dir())
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
			{
				desc = "absolute as string",
				bookmark = { file = "/test.lua", line = 1, id = "abc", absolute = "yes" },
				valid = false,
			},
		}

		-- Positive cases for the optional `absolute` field
		local absolute_field_cases = {
			{
				desc = "absolute = true",
				bookmark = { file = "/test.lua", line = 1, id = "abc", absolute = true },
			},
			{
				desc = "absolute = false",
				bookmark = { file = "/test.lua", line = 1, id = "abc", absolute = false },
			},
			{
				desc = "absolute missing",
				bookmark = { file = "/test.lua", line = 1, id = "abc" },
			},
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

		for _, case in ipairs(absolute_field_cases) do
			it("accepts bookmark with " .. case.desc, function()
				assert.is_true(persistence.is_valid_bookmark(case.bookmark))
			end)
		end
	end)

	describe("save_bookmarks / load_bookmarks", function()
		local test_file
		local project_mock = require("tests.helpers.project_mock")

		--- Read the saved JSON back as a raw table.
		---@param path string
		---@return table data
		local function read_raw(path)
			local lines = vim.fn.readfile(path)
			local json_str = table.concat(lines, "\n")
			return vim.json.decode(json_str)
		end

		before_each(function()
			-- Inject a stable project root so v2 save+load round-trips resolve
			-- consistently regardless of where the test runs.
			project_mock.set({ root = "/tmp", branch = "main", project_id = "tmp" })

			local test_dir = vim.fn.stdpath("data") .. "/haunt/test/"
			vim.fn.mkdir(test_dir, "p")
			test_file = test_dir .. "test_" .. os.time() .. ".json"
		end)

		after_each(function()
			project_mock.restore()
			if test_file and vim.fn.filereadable(test_file) == 1 then
				vim.fn.delete(test_file)
			end
		end)

		it("saves bookmarks to disk in v2 format", function()
			local bookmarks = {
				persistence.create_bookmark("/tmp/file1.lua", 10, "First"),
				persistence.create_bookmark("/tmp/file2.lua", 20, "Second"),
				persistence.create_bookmark("/tmp/file3.lua", 30),
			}

			local save_ok = persistence.save_bookmarks(bookmarks, test_file)
			assert.is_true(save_ok)
			assert.are.equal(1, vim.fn.filereadable(test_file))

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal(3, #data.bookmarks)
			assert.are.equal(bookmarks[1].line, data.bookmarks[1].line)
			assert.are.equal(bookmarks[1].note, data.bookmarks[1].note)
			assert.are.equal(bookmarks[1].id, data.bookmarks[1].id)
		end)

		it("round-trips bookmarks through save and load", function()
			local bookmarks = {
				persistence.create_bookmark("/tmp/file1.lua", 10, "First"),
				persistence.create_bookmark("/tmp/file2.lua", 20, "Second"),
				persistence.create_bookmark("/tmp/file3.lua", 30),
			}

			local save_ok = persistence.save_bookmarks(bookmarks, test_file)
			assert.is_true(save_ok)

			local loaded = persistence.load_bookmarks(test_file)
			assert.is_table(loaded)
			assert.are.equal(3, #loaded)

			for i = 1, 3 do
				assert.are.equal(bookmarks[i].file, loaded[i].file)
				assert.are.equal(bookmarks[i].line, loaded[i].line)
				assert.are.equal(bookmarks[i].note, loaded[i].note)
				assert.are.equal(bookmarks[i].id, loaded[i].id)
			end
		end)

		it("returns empty table for non-existent file", function()
			local loaded = persistence.load_bookmarks("/nonexistent/path.json")
			assert.is_table(loaded)
			assert.are.equal(0, #loaded)
		end)

		it("does not create a file for an empty bookmark list", function()
			local save_ok = persistence.save_bookmarks({}, test_file)
			assert.is_true(save_ok)
			assert.are.equal(0, vim.fn.filereadable(test_file))

			local loaded = persistence.load_bookmarks(test_file)
			assert.is_table(loaded)
			assert.are.equal(0, #loaded)
		end)

		it("deletes an existing file when saving an empty list", function()
			local bookmarks = {
				persistence.create_bookmark("/tmp/file1.lua", 10, "First"),
			}
			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))
			assert.are.equal(1, vim.fn.filereadable(test_file))

			assert.is_true(persistence.save_bookmarks({}, test_file))
			assert.are.equal(0, vim.fn.filereadable(test_file))
		end)

		it("round-trips large bookmark sets (100 bookmarks)", function()
			local bookmarks = {}
			for i = 1, 100 do
				table.insert(
					bookmarks,
					persistence.create_bookmark("/tmp/file" .. i .. ".lua", i, i % 2 == 0 and ("Note " .. i) or nil)
				)
			end

			local save_ok = persistence.save_bookmarks(bookmarks, test_file)
			assert.is_true(save_ok)

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal(100, #data.bookmarks)

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(100, #loaded)
			for i = 1, 100 do
				assert.are.equal(bookmarks[i].file, loaded[i].file)
				assert.are.equal(bookmarks[i].line, loaded[i].line)
				assert.are.equal(bookmarks[i].id, loaded[i].id)
			end
		end)

		it("returns false and notifies when writefile reports I/O failure", function()
			local bookmarks = {
				persistence.create_bookmark("/tmp/file1.lua", 10, "First"),
			}

			local original_writefile = vim.fn.writefile
			vim.fn.writefile = function()
				return -1
			end

			local original_notify = vim.notify
			local notify_calls = {}
			vim.notify = function(msg, level, opts)
				table.insert(notify_calls, { msg = msg, level = level, opts = opts })
			end

			local ok, err = pcall(persistence.save_bookmarks, bookmarks, test_file)

			vim.fn.writefile = original_writefile
			vim.notify = original_notify

			assert.is_true(ok, "save_bookmarks raised: " .. tostring(err))
			assert.is_false(err)

			local saw_failure = false
			for _, call in ipairs(notify_calls) do
				if call.msg and call.msg:find("failed to write", 1, true) then
					assert.are.equal(vim.log.levels.ERROR, call.level)
					saw_failure = true
					break
				end
			end
			assert.is_true(saw_failure, "expected a failure notify when writefile returns -1")
		end)
	end)

	describe("v2 storage format", function()
		local project_mock = require("tests.helpers.project_mock")
		local test_file

		--- Read the saved JSON back as a raw table.
		---@param path string
		---@return table data
		local function read_raw(path)
			local lines = vim.fn.readfile(path)
			local json_str = table.concat(lines, "\n")
			return vim.json.decode(json_str)
		end

		before_each(function()
			local test_dir = vim.fn.stdpath("data") .. "/haunt/test/"
			vim.fn.mkdir(test_dir, "p")
			test_file = test_dir .. "test_v2_" .. os.time() .. "_" .. math.random(1, 1000000) .. ".json"
		end)

		after_each(function()
			project_mock.restore()
			if test_file and vim.fn.filereadable(test_file) == 1 then
				vim.fn.delete(test_file)
			end
		end)

		it("rewrites in-project absolute paths as relative on disk", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1", note = "First" },
				{ file = "/fake/proj/lib/util.lua", line = 5, id = "id2" },
			}

			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal("src/main.lua", data.bookmarks[1].file)
			-- absolute is omitted (or false-equivalent) for in-project bookmarks
			assert.is_true(data.bookmarks[1].absolute == nil or data.bookmarks[1].absolute == false)
			assert.are.equal("lib/util.lua", data.bookmarks[2].file)
		end)

		it("preserves absolute path for bookmarks flagged absolute=true", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bookmarks = {
				{ file = "/etc/hosts", line = 1, id = "abs1", absolute = true },
			}

			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal("/etc/hosts", data.bookmarks[1].file)
			assert.is_true(data.bookmarks[1].absolute)
		end)

		it("defensively flags out-of-project bookmarks as absolute on save", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			-- No `absolute` flag set on the bookmark — save should detect it
			-- lies outside the project and flag it absolute defensively rather
			-- than producing a nonsense relative path.
			local bookmarks = {
				{ file = "/etc/hosts", line = 1, id = "stray1" },
			}

			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal("/etc/hosts", data.bookmarks[1].file)
			assert.is_true(data.bookmarks[1].absolute)
		end)

		it("strips runtime-only extmark fields from the saved data", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bookmarks = {
				{
					file = "/fake/proj/src/main.lua",
					line = 10,
					id = "id1",
					extmark_id = 42,
					annotation_extmark_id = 99,
				},
			}

			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local data = read_raw(test_file)
			assert.is_nil(data.bookmarks[1].extmark_id)
			assert.is_nil(data.bookmarks[1].annotation_extmark_id)
		end)

		it("flags absolute when project_root is unavailable", function()
			project_mock.set({ root = nil, branch = nil, project_id = "noroot" })

			local bookmarks = {
				{ file = "/some/path/file.lua", line = 1, id = "noroot" },
			}

			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local data = read_raw(test_file)
			assert.are.equal(2, data.version)
			assert.are.equal("/some/path/file.lua", data.bookmarks[1].file)
			assert.is_true(data.bookmarks[1].absolute)
		end)
	end)

	describe("v2 load", function()
		local project_mock = require("tests.helpers.project_mock")
		local original_notify
		local notify_calls
		local test_file

		before_each(function()
			-- Capture vim.notify calls so version-related warnings can be asserted.
			notify_calls = {}
			original_notify = vim.notify
			vim.notify = function(msg, level, opts)
				table.insert(notify_calls, { msg = msg, level = level, opts = opts })
			end

			local test_dir = vim.fn.stdpath("data") .. "/haunt/test/"
			vim.fn.mkdir(test_dir, "p")
			test_file = test_dir .. "test_v2_load_" .. os.time() .. "_" .. math.random(1, 1000000) .. ".json"
		end)

		after_each(function()
			vim.notify = original_notify
			project_mock.restore()
			if test_file and vim.fn.filereadable(test_file) == 1 then
				vim.fn.delete(test_file)
			end
		end)

		--- Hand-write a JSON file with arbitrary contents.
		---@param path string
		---@param data table
		local function write_json(path, data)
			vim.fn.writefile({ vim.json.encode(data) }, path)
		end

		it("resolves v2 relative paths to absolute on load", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			-- Save with relative paths produced from in-project absolute paths.
			local bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1", note = "First" },
				{ file = "/fake/proj/lib/util.lua", line = 5, id = "id2" },
			}
			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(2, #loaded)
			assert.are.equal("/fake/proj/src/main.lua", loaded[1].file)
			assert.are.equal(10, loaded[1].line)
			assert.are.equal("First", loaded[1].note)
			assert.are.equal("/fake/proj/lib/util.lua", loaded[2].file)
			assert.are.equal(5, loaded[2].line)
		end)

		it("preserves absolute path and flag when bookmark is absolute=true", function()
			project_mock.set({ root = "/fake/proj", branch = "main", project_id = "fake" })

			local bookmarks = {
				{ file = "/etc/hosts", line = 1, id = "abs1", absolute = true },
			}
			assert.is_true(persistence.save_bookmarks(bookmarks, test_file))

			local loaded = persistence.load_bookmarks(test_file)
			assert.are.equal(1, #loaded)
			assert.are.equal("/etc/hosts", loaded[1].file)
			assert.is_true(loaded[1].absolute)
		end)

		it("rejects v1 storage with a notify and returns nil", function()
			-- Hand-write a v1 file. load_bookmarks should refuse to load it
			-- and direct the user to :HauntMigrate without crashing.
			write_json(test_file, {
				version = 1,
				bookmarks = {
					{ file = "/some/path/file.lua", line = 1, id = "v1id" },
				},
			})

			local loaded = persistence.load_bookmarks(test_file)
			assert.is_nil(loaded)

			-- File must NOT be deleted by load_bookmarks.
			assert.are.equal(1, vim.fn.filereadable(test_file))

			local saw_v1_warning = false
			for _, call in ipairs(notify_calls) do
				if type(call.msg) == "string" and call.msg:match("v1 bookmark storage") and call.msg:match(":HauntMigrate") then
					assert.are.equal(vim.log.levels.WARN, call.level)
					saw_v1_warning = true
				end
			end
			assert.is_true(saw_v1_warning)
		end)

		it("warns and returns nil when version field is missing", function()
			write_json(test_file, {
				bookmarks = {
					{ file = "/some/path/file.lua", line = 1, id = "noversion" },
				},
			})

			local loaded = persistence.load_bookmarks(test_file)
			assert.is_nil(loaded)

			local saw_missing_version = false
			for _, call in ipairs(notify_calls) do
				if type(call.msg) == "string" and call.msg:match("missing version field") then
					assert.are.equal(vim.log.levels.WARN, call.level)
					saw_missing_version = true
				end
			end
			assert.is_true(saw_missing_version)
		end)

		it("warns when relative paths are loaded without a project root", function()
			project_mock.set({ root = nil, branch = nil, project_id = "fallback" })

			write_json(test_file, {
				version = 2,
				bookmarks = {
					{ file = "src/main.lua", line = 10, id = "rel1" },
				},
			})

			local loaded = persistence.load_bookmarks(test_file)
			-- Bookmark survives the load (we don't crash) but file stays
			-- as the stored relative string since we cannot resolve it.
			assert.are.equal(1, #loaded)
			assert.are.equal("src/main.lua", loaded[1].file)

			local saw_no_root_warning = false
			for _, call in ipairs(notify_calls) do
				if type(call.msg) == "string" and call.msg:match("cannot resolve relative paths") then
					assert.are.equal(vim.log.levels.WARN, call.level)
					saw_no_root_warning = true
				end
			end
			assert.is_true(saw_no_root_warning)
		end)

		it("rejects unsupported versions with an error", function()
			write_json(test_file, {
				version = 99,
				bookmarks = {},
			})

			local loaded = persistence.load_bookmarks(test_file)
			assert.is_nil(loaded)

			local saw_unsupported = false
			for _, call in ipairs(notify_calls) do
				if type(call.msg) == "string" and call.msg:match("unsupported version") then
					assert.are.equal(vim.log.levels.ERROR, call.level)
					saw_unsupported = true
				end
			end
			assert.is_true(saw_unsupported)
		end)
	end)
end)
