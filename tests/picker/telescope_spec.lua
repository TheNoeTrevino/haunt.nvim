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

	describe("show() with Telescope installed", function()
		local bufnr, test_file
		local mock
		local telescope_modules = {
			"telescope",
			"telescope.pickers",
			"telescope.finders",
			"telescope.config",
			"telescope.actions",
			"telescope.actions.state",
			"telescope.pickers.entry_display",
			"telescope.utils",
		}

		-- Install a minimal fake Telescope that records what haunt passes to it
		local function install_mock_telescope()
			local m = { new_calls = {}, transform_calls = {} }
			package.loaded["telescope"] = {}
			package.loaded["telescope.pickers"] = {
				new = function(opts, defaults)
					table.insert(m.new_calls, { opts = opts, defaults = defaults })
					return {
						find = function()
							m.opened = true
						end,
					}
				end,
			}
			package.loaded["telescope.finders"] = {
				new_table = function(t)
					return t
				end,
			}
			package.loaded["telescope.config"] = {
				values = {
					generic_sorter = function()
						return "sorter"
					end,
					grep_previewer = function()
						return "previewer"
					end,
				},
			}
			package.loaded["telescope.actions"] = { select_default = { replace = function() end }, close = function() end }
			package.loaded["telescope.actions.state"] = {
				get_selected_entry = function()
					return m.selected
				end,
			}
			package.loaded["telescope.pickers.entry_display"] = {
				create = function()
					return function(items)
						local parts = {}
						for _, item in ipairs(items) do
							table.insert(parts, item[1])
						end
						return table.concat(parts, "|"), {}
					end
				end,
			}
			package.loaded["telescope.utils"] = {
				transform_path = function(opts, path)
					-- Like Telescope's "truncate", which reads the open picker's layout
					if not m.opened then
						error("transform_path called before the picker window exists")
					end
					table.insert(m.transform_calls, { opts = opts, path = path })
					return "TRANSFORMED:" .. vim.fn.fnamemodify(path, ":t")
				end,
			}
			return m
		end

		---@return string display The rendered display string of the first entry
		local function first_display()
			local call = mock.new_calls[1]
			local merged = vim.tbl_extend("force", call.defaults, call.opts)
			local entry = merged.finder.entry_maker(merged.finder.results[1])
			return (entry.display(entry))
		end

		before_each(function()
			mock = install_mock_telescope()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
			for _, name in ipairs(telescope_modules) do
				package.loaded[name] = nil
			end
		end)

		it("passes user opts to Telescope as picker opts, not as defaults", function()
			local user_mappings = function()
				return true
			end
			telescope_picker.show({ attach_mappings = user_mappings })

			local call = mock.new_calls[1]
			assert.are.equal(user_mappings, call.opts.attach_mappings)
			assert.are_not.equal(user_mappings, call.defaults.attach_mappings)
			assert.is_function(call.defaults.attach_mappings)
		end)

		it("formats the file path with Telescope transform_path", function()
			local opts = { path_display = { "tail" } }
			telescope_picker.show(opts)

			local display = first_display()
			assert.truthy(display:find("TRANSFORMED:", 1, true))
			assert.are.same({ "tail" }, mock.transform_calls[1].opts.path_display)
			assert.are.equal(test_file, mock.transform_calls[1].path)
		end)

		it("reopens with the same opts after editing", function()
			local original_input = vim.fn.input
			vim.fn.input = function()
				return "Updated note"
			end
			local reopened_with = nil
			telescope_picker.set_picker_module({
				show = function(o)
					reopened_with = o
				end,
			})

			telescope_picker.show({ prompt_title = "Custom" })
			local call = mock.new_calls[1]
			local maps = {}
			call.defaults.attach_mappings(1, function(_, key, fn)
				maps[key] = fn
			end)
			mock.selected = { value = call.defaults.finder.results[1] }
			maps["a"](1)
			vim.fn.input = original_input

			assert.are.equal("Custom", reopened_with.prompt_title)
		end)

		it("formats each path once, so the drawn path matches the measured width", function()
			-- Like Telescope's "smart", which returns a different string on each call
			local calls = 0
			package.loaded["telescope.utils"].transform_path = function()
				calls = calls + 1
				return "PATH" .. calls
			end

			telescope_picker.show()
			local first = first_display()
			local second = first_display()

			assert.are.equal(1, calls)
			assert.are.equal(first, second)
			assert.truthy(first:find("PATH1", 1, true))
		end)

		it("still shows the note in the display", function()
			telescope_picker.show()
			assert.truthy(first_display():find("Test note", 1, true))
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
