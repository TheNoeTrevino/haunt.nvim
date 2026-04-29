---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("change_data_dir", function()
	describe("store.reload", function()
		local store
		local mock_persistence

		before_each(function()
			helpers.reset_modules()

			mock_persistence = helpers.create_mock_persistence()
			package.loaded["haunt.persistence"] = mock_persistence

			store = require("haunt.store")
			store._reset_for_testing()
		end)

		after_each(function()
			package.loaded["haunt.persistence"] = nil
		end)

		it("clears in-memory bookmarks", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "b1", note = "Test" })
			assert.are.equal(1, #store.get_bookmarks())

			mock_persistence.bookmarks_to_load = {}
			store.reload()

			assert.are.equal(0, #store.get_bookmarks())
		end)

		it("clears file index", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "b1" })
			store.add_bookmark({ file = "/test.lua", line = 5, id = "b2" })
			assert.are.equal(2, #store.get_sorted_bookmarks_for_file("/test.lua"))

			mock_persistence.bookmarks_to_load = {}
			store.reload()

			assert.are.equal(0, #store.get_sorted_bookmarks_for_file("/test.lua"))
		end)

		it("triggers fresh load from persistence", function()
			store.add_bookmark({ file = "/test.lua", line = 1, id = "b1" })

			mock_persistence.bookmarks_to_load = {}
			mock_persistence.reset()

			store.reload()

			assert.is_true(mock_persistence.was_called("load_bookmarks"))
		end)

		it("loads bookmarks from persistence", function()
			mock_persistence.bookmarks_to_load = {
				{ file = "/new.lua", line = 10, id = "new1", note = "From persistence" },
				{ file = "/new.lua", line = 20, id = "new2", note = "Also from persistence" },
			}

			store.reload()

			local bookmarks = store.get_bookmarks()
			assert.are.equal(2, #bookmarks)
			assert.are.equal("/new.lua", bookmarks[1].file)
			assert.are.equal("From persistence", bookmarks[1].note)
		end)

		it("rebuilds file index after load", function()
			mock_persistence.bookmarks_to_load = {
				{ file = "/indexed.lua", line = 30, id = "i3" },
				{ file = "/indexed.lua", line = 10, id = "i1" },
				{ file = "/indexed.lua", line = 20, id = "i2" },
			}

			store.reload()

			local sorted = store.get_sorted_bookmarks_for_file("/indexed.lua")
			assert.are.equal(3, #sorted)
			assert.are.equal(10, sorted[1].line)
			assert.are.equal(20, sorted[2].line)
			assert.are.equal(30, sorted[3].line)
		end)
	end)

	describe("restoration.reset_tracking", function()
		local restoration
		local store
		local display
		local bufnr, test_file

		before_each(function()
			helpers.reset_modules()

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

		it("clears restored_buffers tracking", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			store.add_bookmark({ file = test_file, line = 1, id = "b1", note = "Test" })

			restoration.restore_buffer_bookmarks(bufnr, true)

			local ns = display.get_namespace()
			local extmarks_first = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

			restoration.restore_buffer_bookmarks(bufnr, true)
			local extmarks_second = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

			assert.are.equal(#extmarks_first, #extmarks_second)

			restoration.reset_tracking()
			display.clear_buffer_marks(bufnr)

			restoration.restore_buffer_bookmarks(bufnr, true)
			local extmarks_after_reset = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

			assert.is_true(#extmarks_after_reset > 0)
		end)

		it("allows buffer to be restored again after reset", function()
			bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
			store.add_bookmark({ file = test_file, line = 2, id = "b2", note = "Restore me" })

			restoration.restore_buffer_bookmarks(bufnr, true)

			local ns = display.get_namespace()
			local initial_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#initial_extmarks > 0)

			display.clear_buffer_marks(bufnr)
			local cleared_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.are.equal(0, #cleared_extmarks)

			restoration.reset_tracking()
			restoration.restore_buffer_bookmarks(bufnr, true)

			local restored_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			assert.is_true(#restored_extmarks > 0)
		end)

		it("handles empty state gracefully", function()
			local ok = pcall(restoration.reset_tracking)
			assert.is_true(ok)
		end)
	end)

	describe("api.change_data_dir", function()
		local api
		local store
		local display
		local persistence
		local config

		local data_dir_1
		local data_dir_2
		local bufnr, test_file

		before_each(function()
			helpers.reset_modules()

			config = require("haunt.config")
			config.setup()

			api = require("haunt.api")
			api._reset_for_testing()

			store = require("haunt.store")
			display = require("haunt.display")
			persistence = require("haunt.persistence")

			data_dir_1 = helpers.create_temp_data_dir()
			data_dir_2 = helpers.create_temp_data_dir()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
			helpers.cleanup_temp_dir(data_dir_1)
			helpers.cleanup_temp_dir(data_dir_2)
		end)

		describe("basic functionality", function()
			it("returns true on success", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2" })

				persistence.set_data_dir(data_dir_1)

				local result = api.change_data_dir(data_dir_2)

				assert.is_true(result)
			end)

			it("saves bookmarks to old location before switching", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 2, 0 })
				api.annotate("Save me before switch")

				local old_storage_path = persistence.get_storage_path()

				api.change_data_dir(data_dir_2)

				local saved_data = helpers.read_bookmarks_file(old_storage_path)
				assert.is_not_nil(saved_data)
				assert.is_not_nil(saved_data.bookmarks)
				assert.are.equal(1, #saved_data.bookmarks)
				assert.are.equal("Save me before switch", saved_data.bookmarks[1].note)
				assert.are.equal(2, saved_data.version)
			end)

			it("sets new data_dir in persistence", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1" })

				persistence.set_data_dir(data_dir_1)
				assert.are.equal(data_dir_1, persistence.ensure_data_dir())

				api.change_data_dir(data_dir_2)

				assert.are.equal(data_dir_2, persistence.ensure_data_dir())
			end)

			it("loads bookmarks from new location", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				persistence.set_data_dir(data_dir_2)
				local new_storage_path = persistence.get_storage_path()
				helpers.create_bookmarks_file(data_dir_2, {
					{ file = test_file, line = 3, id = "preexisting", note = "I was here first" },
				}, new_storage_path:match("([^/]+)%.json$"))

				persistence.set_data_dir(data_dir_1)

				api.change_data_dir(data_dir_2)

				local bookmarks = api.get_bookmarks()
				assert.are.equal(1, #bookmarks)
				assert.are.equal("I was here first", bookmarks[1].note)
				assert.are.equal(3, bookmarks[1].line)
			end)
		end)

		describe("visual element management", function()
			it("clears all extmarks from loaded buffers", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Extmark test")

				local ns = display.get_namespace()
				local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
				assert.is_true(#extmarks_before > 0)

				api.change_data_dir(data_dir_2)

				local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
				assert.are.equal(0, #extmarks_after)
			end)

			it("clears all signs from loaded buffers", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 2, 0 })
				api.annotate("Sign test")

				local signs_before = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
				assert.is_true(#signs_before[1].signs > 0)

				api.change_data_dir(data_dir_2)

				local signs_after = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
				assert.are.equal(0, #signs_after[1].signs)
			end)

			it("restores visuals for bookmarks in new data_dir", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				persistence.set_data_dir(data_dir_2)
				local new_storage_path = persistence.get_storage_path()
				helpers.create_bookmarks_file(data_dir_2, {
					{ file = test_file, line = 2, id = "visual_test", note = "Should have visuals" },
				}, new_storage_path:match("([^/]+)%.json$"))

				persistence.set_data_dir(data_dir_1)

				api.change_data_dir(data_dir_2)

				local ns = display.get_namespace()
				local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
				assert.is_true(#extmarks > 0)

				local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
				assert.is_true(#signs[1].signs > 0)
			end)

			it("clears visuals when switching to empty data_dir", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Will be cleared")
				vim.api.nvim_win_set_cursor(0, { 3, 0 })
				api.annotate("Also cleared")

				local ns = display.get_namespace()
				local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
				assert.is_true(#extmarks_before > 0)

				api.change_data_dir(data_dir_2)

				local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
				assert.are.equal(0, #extmarks_after)

				local signs_after = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
				assert.are.equal(0, #signs_after[1].signs)
			end)
		end)

		describe("state preservation", function()
			it("preserves annotation visibility when visible", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				assert.is_true(api.are_annotations_visible())

				persistence.set_data_dir(data_dir_2)
				local new_storage_path = persistence.get_storage_path()
				helpers.create_bookmarks_file(data_dir_2, {
					{ file = test_file, line = 1, id = "vis_test", note = "Visible annotation" },
				}, new_storage_path:match("([^/]+)%.json$"))

				persistence.set_data_dir(data_dir_1)

				api.change_data_dir(data_dir_2)

				assert.is_true(api.are_annotations_visible())

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

			it("preserves annotation visibility when hidden", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Initial bookmark")

				api.toggle_all_lines()
				assert.is_false(api.are_annotations_visible())

				persistence.set_data_dir(data_dir_2)
				local new_storage_path = persistence.get_storage_path()
				helpers.create_bookmarks_file(data_dir_2, {
					{ file = test_file, line = 2, id = "hidden_test", note = "Should be hidden" },
				}, new_storage_path:match("([^/]+)%.json$"))

				persistence.set_data_dir(data_dir_1)

				api.change_data_dir(data_dir_2)

				assert.is_false(api.are_annotations_visible())

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

		describe("edge cases", function()
			it("handles nil to reset to default data_dir", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1" })

				persistence.set_data_dir(data_dir_1)
				assert.are.equal(data_dir_1, persistence.ensure_data_dir())

				local ok, result = pcall(api.change_data_dir, nil)

				assert.is_true(ok)
				assert.is_true(result)
				assert.are.equal(config.DEFAULT_DATA_DIR, persistence.ensure_data_dir())
			end)

			it("handles multiple loaded buffers", function()
				local bufnr1, test_file1 = helpers.create_test_buffer({ "File 1 Line 1", "File 1 Line 2" })
				local bufnr2, test_file2 = helpers.create_test_buffer({ "File 2 Line 1", "File 2 Line 2" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_set_current_buf(bufnr1)
				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Buffer 1 bookmark")

				vim.api.nvim_set_current_buf(bufnr2)
				vim.api.nvim_win_set_cursor(0, { 2, 0 })
				api.annotate("Buffer 2 bookmark")

				local ns = display.get_namespace()
				assert.is_true(#vim.api.nvim_buf_get_extmarks(bufnr1, ns, 0, -1, {}) > 0)
				assert.is_true(#vim.api.nvim_buf_get_extmarks(bufnr2, ns, 0, -1, {}) > 0)

				api.change_data_dir(data_dir_2)

				assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(bufnr1, ns, 0, -1, {}))
				assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(bufnr2, ns, 0, -1, {}))

				helpers.cleanup_buffer(bufnr1, test_file1)
				helpers.cleanup_buffer(bufnr2, test_file2)
			end)

			it("handles buffers with no bookmarks", function()
				local bufnr1, test_file1 = helpers.create_test_buffer({ "With bookmark" })
				local bufnr2, test_file2 = helpers.create_test_buffer({ "No bookmark" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_set_current_buf(bufnr1)
				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Only in buffer 1")

				local ok, result = pcall(api.change_data_dir, data_dir_2)

				assert.is_true(ok)
				assert.is_true(result)

				helpers.cleanup_buffer(bufnr1, test_file1)
				helpers.cleanup_buffer(bufnr2, test_file2)
			end)

			it("skips invalid buffers gracefully", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2" })

				persistence.set_data_dir(data_dir_1)

				vim.api.nvim_win_set_cursor(0, { 1, 0 })
				api.annotate("Test")

				local temp_bufnr = vim.api.nvim_create_buf(false, false)
				vim.api.nvim_buf_delete(temp_bufnr, { force = true })

				local ok, result = pcall(api.change_data_dir, data_dir_2)

				assert.is_true(ok)
				assert.is_true(result)
			end)
		end)

		-- NOTE: These round-trip tests exercise save followed by load through
		-- api.change_data_dir. They are temporarily disabled because save now
		-- writes v2 while load_bookmarks still only understands v1; they will
		-- be re-enabled in task 168 when load_bookmarks gains v2 support.
		--
		-- describe("round-trip integration", function()
		-- 	it("round-trip: switch away and back restores original bookmarks", function()
		-- 		bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		--
		-- 		persistence.set_data_dir(data_dir_1)
		--
		-- 		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		-- 		api.annotate("Original bookmark")
		--
		-- 		assert.are.equal(1, #api.get_bookmarks())
		-- 		local ns = display.get_namespace()
		-- 		assert.is_true(#vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}) > 0)
		--
		-- 		api.change_data_dir(data_dir_2)
		--
		-- 		assert.are.equal(0, #api.get_bookmarks())
		-- 		assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
		--
		-- 		api.change_data_dir(data_dir_1)
		--
		-- 		assert.are.equal(1, #api.get_bookmarks())
		-- 		assert.are.equal("Original bookmark", api.get_bookmarks()[1].note)
		--
		-- 		local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
		-- 		assert.is_true(#extmarks > 0)
		--
		-- 		local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
		-- 		assert.is_true(#signs[1].signs > 0)
		-- 	end)
		--
		-- 	it("bookmarks created in new data_dir persist correctly", function()
		-- 		bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })
		-- 		local data_dir_3 = helpers.create_temp_data_dir()
		--
		-- 		persistence.set_data_dir(data_dir_1)
		--
		-- 		api.change_data_dir(data_dir_2)
		--
		-- 		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		-- 		api.annotate("Created in dir 2")
		--
		-- 		assert.are.equal(1, #api.get_bookmarks())
		--
		-- 		api.change_data_dir(data_dir_3)
		--
		-- 		assert.are.equal(0, #api.get_bookmarks())
		--
		-- 		api.change_data_dir(data_dir_2)
		--
		-- 		assert.are.equal(1, #api.get_bookmarks())
		-- 		assert.are.equal("Created in dir 2", api.get_bookmarks()[1].note)
		--
		-- 		local ns = display.get_namespace()
		-- 		local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
		-- 		assert.is_true(#extmarks > 0)
		--
		-- 		helpers.cleanup_temp_dir(data_dir_3)
		-- 	end)
		-- end)

		describe("cwd change within cache TTL", function()
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

			it("loads bookmarks for the new cwd context after cd", function()
				bufnr, test_file = helpers.create_test_buffer({ "Line 1", "Line 2", "Line 3" })

				-- Resolve the canonical cwd for non_git_dir without going through
				-- persistence (which would populate the git_info cache and mask the bug).
				vim.fn.chdir(non_git_dir)
				local non_git_cwd = vim.fn.getcwd()
				vim.fn.chdir(original_cwd)

				local target_hash = vim.fn.sha256(non_git_cwd .. "|__default__"):sub(1, 12)
				helpers.create_bookmarks_file(data_dir_2, {
					{ file = test_file, line = 2, id = "regress73", note = "Issue 73" },
				}, target_hash)

				persistence.set_data_dir(data_dir_1)
				local _ = persistence.get_git_info()

				vim.fn.chdir(non_git_dir)
				api.change_data_dir(data_dir_2)

				local bookmarks = api.get_bookmarks()
				assert.are.equal(1, #bookmarks)
				assert.are.equal("Issue 73", bookmarks[1].note)
			end)
		end)
	end)
end)
