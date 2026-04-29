---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")
local project_mock = require("tests.helpers.project_mock")

describe("haunt.project", function()
	local project

	before_each(function()
		helpers.reset_modules()
		package.loaded["haunt.project"] = nil
		project = require("haunt.project")
	end)

	describe("get_info", function()
		it("returns a table with root, branch, and project_id", function()
			local info = project.get_info()
			assert.is_table(info)

			local root_t = type(info.root)
			assert.is_true(root_t == "string" or root_t == "nil")

			local branch_t = type(info.branch)
			assert.is_true(branch_t == "string" or branch_t == "nil")

			assert.is_string(info.project_id)
			assert.is_true(#info.project_id > 0)
		end)

		it("caches results within TTL (returns same identity)", function()
			local info1 = project.get_info()
			local info2 = project.get_info()
			-- Same table identity proves the cache returned the same object
			assert.are.equal(info1, info2)
		end)

		it("re-fetches after TTL expiration", function()
			-- First call populates the cache
			local info1 = project.get_info()
			assert.is_table(info1)

			-- Mock vim.uv.hrtime to advance past the 5s TTL
			local orig_hrtime = vim.uv.hrtime
			local advanced = orig_hrtime() + (10 * 1e9) -- advance by 10 seconds (in nanoseconds)
			---@diagnostic disable-next-line: duplicate-set-field
			vim.uv.hrtime = function()
				return advanced
			end

			local info2 = project.get_info()

			-- Restore
			vim.uv.hrtime = orig_hrtime

			-- After TTL expiration, get_info should have re-fetched and produced a NEW table
			assert.are_not.equal(info1, info2)
			-- Both should still be valid info tables
			assert.is_table(info2)
			assert.is_string(info2.project_id)
		end)

		it("falls back gracefully when git is not available", function()
			-- Save original
			local orig_systemlist = vim.fn.systemlist

			-- Mock git failure: redirect any command to a shell command that exits 127.
			-- Running `vim.fn.systemlist` actually executes the command, so vim.v.shell_error
			-- is set authentically (it is read-only and can't be assigned directly).
			---@diagnostic disable-next-line: duplicate-set-field
			vim.fn.systemlist = function(_)
				return orig_systemlist("exit 127")
			end

			-- Reload module so the warning-shown flag is reset and any cache is cleared
			package.loaded["haunt.project"] = nil
			local p = require("haunt.project")

			local ok, info = pcall(p.get_info)

			-- Restore before asserting so a failure doesn't leak the mock
			vim.fn.systemlist = orig_systemlist

			assert.is_true(ok)
			assert.is_table(info)
			assert.is_string(info.project_id)
			assert.is_true(#info.project_id > 0)
		end)
	end)

	describe("invalidate", function()
		it("forces get_info to re-resolve on next call", function()
			project_mock.set({ root = "/proj/before", branch = "main", project_id = "id-before" })

			local info1 = project.get_info()
			assert.are.equal("/proj/before", info1.root)

			project_mock.set({ root = "/proj/after", branch = "main", project_id = "id-after" })

			local info2 = project.get_info()
			assert.are_not.equal(info1, info2)
			assert.are.equal("/proj/after", info2.root)
		end)
	end)

	describe("setup_autocmds", function()
		local function fire(event)
			vim.api.nvim_exec_autocmds(event, { modeline = false })
		end

		--- Inject info, fire `event` to invalidate the cache, inject new info,
		--- and assert the next `get_info` call returns the new values.
		local function assert_event_invalidates(event)
			project.setup_autocmds()
			project_mock.set({ root = "/proj/before", branch = "main", project_id = "id-before" })

			local info1 = project.get_info()
			assert.are.equal("/proj/before", info1.root)

			fire(event)
			project_mock.set({ root = "/proj/after", branch = "main", project_id = "id-after" })

			local info2 = project.get_info()
			assert.are.equal("/proj/after", info2.root)
		end

		it("invalidates cache on DirChanged", function()
			assert_event_invalidates("DirChanged")
		end)

		it("invalidates cache on FocusGained", function()
			assert_event_invalidates("FocusGained")
		end)

		it("invalidates cache on VimResume", function()
			assert_event_invalidates("VimResume")
		end)

		it("is idempotent — calling twice does not double-register the autocmd", function()
			project.setup_autocmds()
			project.setup_autocmds()

			project_mock.set({ root = "/proj/before", branch = "main", project_id = "id-before" })
			local info1 = project.get_info()
			assert.are.equal("/proj/before", info1.root)

			fire("DirChanged")
			project_mock.set({ root = "/proj/after", branch = "main", project_id = "id-after" })

			local info2 = project.get_info()
			assert.are.equal("/proj/after", info2.root)
		end)
	end)
end)
