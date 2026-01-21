---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.telescope", function()
	local telescope_mod
	local api
	local haunt

	-- Mock telescope modules
	local mock_telescope
	local mock_pickers
	local mock_finders
	local mock_actions
	local mock_action_state
	local mock_previewers
	local mock_conf
	local mock_entry_display

	-- Mock vim functions
	local original_notify
	local original_input
	local notifications

	-- Captured picker state
	local picker_state

	-- Create mock telescope
	local function create_mock_telescope()
		picker_state = {
			created = false,
			finder = nil,
			attach_mappings_fn = nil,
			selected_entry = nil,
			closed = false,
			mappings = {},
		}

		-- Mock entry_display
		mock_entry_display = {
			create = function()
				return function(items)
					local result = {}
					for _, item in ipairs(items) do
						if type(item) == "table" then
							table.insert(result, item[1] or "")
						else
							table.insert(result, item or "")
						end
					end
					return table.concat(result, " ")
				end
			end,
		}

		-- Mock actions
		mock_actions = {
			close = function(prompt_bufnr)
				picker_state.closed = true
			end,
			select_default = {
				replace = function(self, fn)
					picker_state.select_default_fn = fn
				end,
			},
		}

		-- Mock action_state
		mock_action_state = {
			get_selected_entry = function()
				return picker_state.selected_entry
			end,
		}

		-- Mock previewers
		mock_previewers = {
			vim_buffer_cat = {
				new = function()
					return {}
				end,
			},
		}

		-- Mock conf
		mock_conf = {
			generic_sorter = function()
				return {}
			end,
		}

		-- Mock finders
		mock_finders = {
			new_table = function(opts)
				picker_state.finder_opts = opts
				return opts
			end,
		}

		-- Mock pickers
		mock_pickers = {
			new = function(opts, config)
				picker_state.created = true
				picker_state.opts = opts
				picker_state.config = config

				-- Call attach_mappings to capture the mappings
				if config.attach_mappings then
					local map = function(mode, key, fn)
						picker_state.mappings[key] = { mode = mode, fn = fn }
					end
					config.attach_mappings(0, map)
				end

				return {
					find = function() end,
				}
			end,
		}

		-- Main telescope mock
		mock_telescope = {}

		return mock_telescope
	end

	-- Helper to execute a captured mapping
	local function execute_mapping(key)
		if picker_state.mappings[key] then
			picker_state.mappings[key].fn()
		end
	end

	-- Helper to execute default select action
	local function execute_select_default()
		if picker_state.select_default_fn then
			picker_state.select_default_fn()
		end
	end

	-- Helper to get finder results
	local function get_finder_results()
		if picker_state.finder_opts and picker_state.finder_opts.results then
			return picker_state.finder_opts.results
		end
		return {}
	end

	-- Helper to make entry from bookmark
	local function make_entry(bookmark)
		if picker_state.finder_opts and picker_state.finder_opts.entry_maker then
			return picker_state.finder_opts.entry_maker(bookmark)
		end
		return nil
	end

	before_each(function()
		helpers.reset_modules()

		-- Clear telescope-related packages
		package.loaded["telescope"] = nil
		package.loaded["telescope.pickers"] = nil
		package.loaded["telescope.finders"] = nil
		package.loaded["telescope.actions"] = nil
		package.loaded["telescope.actions.state"] = nil
		package.loaded["telescope.previewers"] = nil
		package.loaded["telescope.config"] = nil
		package.loaded["telescope.pickers.entry_display"] = nil

		-- Setup mocks
		mock_telescope = create_mock_telescope()
		notifications = {}

		-- Mock telescope modules
		package.loaded["telescope"] = mock_telescope
		package.loaded["telescope.pickers"] = mock_pickers
		package.loaded["telescope.finders"] = mock_finders
		package.loaded["telescope.actions"] = mock_actions
		package.loaded["telescope.actions.state"] = mock_action_state
		package.loaded["telescope.previewers"] = mock_previewers
		package.loaded["telescope.config"] = { values = mock_conf }
		package.loaded["telescope.pickers.entry_display"] = mock_entry_display

		-- Mock vim.notify
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
		telescope_mod = require("haunt.telescope")
	end)

	after_each(function()
		-- Restore mocks
		vim.notify = original_notify
		vim.fn.input = original_input
		package.loaded["telescope"] = nil
		package.loaded["telescope.pickers"] = nil
		package.loaded["telescope.finders"] = nil
		package.loaded["telescope.actions"] = nil
		package.loaded["telescope.actions.state"] = nil
		package.loaded["telescope.previewers"] = nil
		package.loaded["telescope.config"] = nil
		package.loaded["telescope.pickers.entry_display"] = nil
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
			telescope_mod.show()

			assert.is_false(picker_state.created)
			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
			assert.are.equal(vim.log.levels.INFO, notifications[1].level)
		end)

		it("creates picker when bookmarks exist", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")

			telescope_mod.show()

			assert.is_true(picker_state.created)
			assert.is_not_nil(picker_state.config)
		end)

		it("notifies error when telescope is not available", function()
			-- Remove telescope from package.loaded
			package.loaded["telescope"] = nil

			-- Reload telescope module
			package.loaded["haunt.telescope"] = nil
			telescope_mod = require("haunt.telescope")

			-- Add a bookmark
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			-- Clear previous notifications
			notifications = {}

			telescope_mod.show()

			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("telescope.nvim is not installed"))
			assert.are.equal(vim.log.levels.ERROR, notifications[1].level)

			-- Restore mock for other tests
			package.loaded["telescope"] = mock_telescope
		end)

		it("sets correct picker title", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			telescope_mod.show()

			assert.are.equal("Hauntings", picker_state.config.prompt_title)
		end)

		it("registers delete and edit_annotation mappings", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			telescope_mod.show()

			-- Default keys from config
			assert.is_not_nil(picker_state.mappings["d"])
			assert.is_not_nil(picker_state.mappings["a"])
		end)
	end)

	describe("finder", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns bookmarks as results", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			telescope_mod.show()
			local results = get_finder_results()

			assert.are.equal(1, #results)
		end)

		it("creates entries with required fields", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			assert.is_not_nil(entry.value)
			assert.is_not_nil(entry.ordinal)
			assert.is_not_nil(entry.file)
			assert.is_not_nil(entry.line)
			assert.is_not_nil(entry.id)
			assert.is_not_nil(entry.filename)
			assert.is_not_nil(entry.lnum)
		end)

		it("includes note in ordinal for searching", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Important bookmark")

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			assert.is_truthy(entry.ordinal:match("Important bookmark"))
		end)

		it("returns multiple bookmarks", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")

			telescope_mod.show()
			local results = get_finder_results()

			assert.are.equal(3, #results)
		end)
	end)

	describe("select action", function()
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

		it("closes picker on selection", function()
			vim.api.nvim_set_current_buf(bufnr2)
			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			picker_state.selected_entry = entry
			execute_select_default()

			assert.is_true(picker_state.closed)
		end)

		it("handles nil selection gracefully", function()
			telescope_mod.show()
			picker_state.selected_entry = nil

			local ok = pcall(execute_select_default)
			assert.is_true(ok)
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

		it("deletes selected bookmark", function()
			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[2])

			assert.are.equal(3, #api.get_bookmarks())

			picker_state.selected_entry = entry
			execute_mapping("d")

			assert.are.equal(2, #api.get_bookmarks())
		end)

		it("closes picker after delete", function()
			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			picker_state.selected_entry = entry
			execute_mapping("d")

			assert.is_true(picker_state.closed)
		end)

		it("notifies when last bookmark deleted", function()
			telescope_mod.show()
			local results = get_finder_results()

			-- Delete all bookmarks
			for _, bookmark in ipairs(results) do
				local entry = make_entry(bookmark)
				picker_state.selected_entry = entry
				execute_mapping("d")
			end

			local has_no_remaining_notif = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("No bookmarks remaining") then
					has_no_remaining_notif = true
					break
				end
			end

			assert.is_true(has_no_remaining_notif)
		end)

		it("handles nil selection gracefully", function()
			telescope_mod.show()
			picker_state.selected_entry = nil

			local ok = pcall(execute_mapping, "d")
			assert.is_true(ok)
			assert.are.equal(3, #api.get_bookmarks())
		end)
	end)

	describe("edit_annotation action", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original note")
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

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			picker_state.selected_entry = entry
			execute_mapping("a")

			assert.are.equal("Original note", prompted_default)
		end)

		it("updates annotation", function()
			vim.fn.input = function()
				return "Updated note"
			end

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			picker_state.selected_entry = entry
			execute_mapping("a")

			local bookmarks = api.get_bookmarks()
			assert.are.equal("Updated note", bookmarks[1].note)
		end)

		it("closes picker before prompting", function()
			local closed_during_input = false
			vim.fn.input = function()
				closed_during_input = picker_state.closed
				return "New note"
			end

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			picker_state.selected_entry = entry
			execute_mapping("a")

			assert.is_true(closed_during_input)
		end)

		it("handles nil selection gracefully", function()
			telescope_mod.show()
			picker_state.selected_entry = nil

			local ok = pcall(execute_mapping, "a")
			assert.is_true(ok)
		end)
	end)

	describe("edge cases", function()
		it("handles single bookmark", function()
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Only one")

			telescope_mod.show()

			assert.is_true(picker_state.created)
			local results = get_finder_results()
			assert.are.equal(1, #results)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles bookmarks across multiple files", function()
			local bufnr1, test_file1 = helpers.create_test_buffer(nil, "/tmp/file1.lua")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File 1")

			local bufnr2, test_file2 = helpers.create_test_buffer(nil, "/tmp/file2.lua")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("File 2")

			telescope_mod.show()
			local results = get_finder_results()

			assert.are.equal(2, #results)

			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("handles special characters in annotations", function()
			local special_note = 'Note with "quotes", <brackets>, & ampersands'
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate(special_note)

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			assert.are.equal(special_note, entry.note)

			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("handles very long annotations", function()
			local long_note = string.rep("This is a very long annotation text. ", 20)
			local bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate(long_note)

			telescope_mod.show()
			local results = get_finder_results()
			local entry = make_entry(results[1])

			assert.are.equal(long_note, entry.note)

			helpers.cleanup_buffer(bufnr, test_file)
		end)
	end)
end)
