---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")
local project_mock = require("tests.helpers.project_mock")

describe("haunt.watcher", function()
	local watcher

	before_each(function()
		helpers.reset_modules()
		watcher = require("haunt.watcher")
	end)

	after_each(function()
		watcher.stop()
		project_mock.restore()
	end)

	describe("start", function()
		it("returns false when not in a git repo", function()
			-- Force `git rev-parse --absolute-git-dir` to fail by running it from /tmp.
			local original_cwd = vim.fn.getcwd()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			vim.cmd("cd " .. tmp)

			local started = watcher.start()

			vim.cmd("cd " .. original_cwd)
			vim.fn.delete(tmp, "rf")

			assert.is_false(started)
		end)

		it("does not throw when called repeatedly", function()
			local ok, err = pcall(function()
				watcher.start()
				watcher.start()
				watcher.start()
			end)
			assert.is_true(ok, "watcher.start raised: " .. tostring(err))
		end)
	end)

	describe("stop", function()
		it("is safe to call without prior start", function()
			local ok, err = pcall(watcher.stop)
			assert.is_true(ok, "watcher.stop raised: " .. tostring(err))
		end)

		it("is idempotent", function()
			watcher.start()
			local ok, err = pcall(function()
				watcher.stop()
				watcher.stop()
			end)
			assert.is_true(ok, "double stop raised: " .. tostring(err))
		end)
	end)

	describe("_check_and_reload", function()
		it("is a no-op when no storage path has been stamped", function()
			-- Fresh store has no stamped path, so even if branches differ
			-- the watcher must not fire reload.
			local store = require("haunt.store")
			store._reset_for_testing()
			assert.is_nil(store.get_loaded_storage_path())

			local api = require("haunt.api")
			local original_reload = api.reload
			local reload_called = false
			api.reload = function()
				reload_called = true
				return true
			end

			local ok, err = pcall(watcher._check_and_reload)

			api.reload = original_reload

			assert.is_true(ok, "_check_and_reload raised: " .. tostring(err))
			assert.is_false(reload_called)
		end)

		it("does not reload when current storage path matches the stamped path", function()
			project_mock.set({ root = "/proj", branch = "main", project_id = "p-id" })

			-- Force the store to stamp itself by calling load(). Reset first to
			-- make sure load() actually runs (otherwise it short-circuits on _loaded).
			local store = require("haunt.store")
			store._reset_for_testing()
			package.loaded["haunt.store"] = nil
			store = require("haunt.store")
			store.load()

			local stamped = store.get_loaded_storage_path()
			assert.is_string(stamped)

			local api = require("haunt.api")
			local original_reload = api.reload
			local reload_called = false
			api.reload = function()
				reload_called = true
				return true
			end

			-- Same project_mock still in effect → same storage path → no reload.
			local ok, err = pcall(watcher._check_and_reload)

			api.reload = original_reload

			assert.is_true(ok, "_check_and_reload raised: " .. tostring(err))
			assert.is_false(reload_called)
		end)
	end)

	describe("_check_storage_and_reload", function()
		local tmpdir
		local storage_path
		local store
		local api
		local original_reload
		local original_get_loaded_storage_path
		local reload_reasons

		--- Drive the watcher against a real file on disk, with `api.reload`
		--- stubbed so we observe the decision instead of tearing down buffers.
		local function arrange(path)
			store = require("haunt.store")
			api = require("haunt.api")

			original_get_loaded_storage_path = store.get_loaded_storage_path
			store.get_loaded_storage_path = function()
				return path
			end

			reload_reasons = {}
			original_reload = api.reload
			api.reload = function(reason)
				table.insert(reload_reasons, reason)
				return true
			end
		end

		local function write_storage(contents)
			vim.fn.writefile({ contents }, storage_path)
		end

		before_each(function()
			tmpdir = vim.fn.tempname() .. "_haunt_storage_watch/"
			vim.fn.mkdir(tmpdir, "p")
			storage_path = tmpdir .. "abc123def456.json"
		end)

		after_each(function()
			if store and original_get_loaded_storage_path then
				store.get_loaded_storage_path = original_get_loaded_storage_path
			end
			if api and original_reload then
				api.reload = original_reload
			end
			store, api, original_reload, original_get_loaded_storage_path = nil, nil, nil, nil

			if tmpdir and vim.fn.isdirectory(tmpdir) == 1 then
				vim.fn.delete(tmpdir, "rf")
			end
		end)

		it("is a no-op when no storage path has been stamped", function()
			arrange(nil)

			local ok, err = pcall(watcher._check_storage_and_reload)

			assert.is_true(ok, "_check_storage_and_reload raised: " .. tostring(err))
			assert.are.equal(0, #reload_reasons)
		end)

		it("does not reload for a file that matches the synced stamp", function()
			arrange(storage_path)
			write_storage('{"version":2,"bookmarks":[]}')
			watcher.mark_synced(storage_path)

			watcher._check_storage_and_reload()

			assert.are.equal(0, #reload_reasons)
		end)

		it("does not reload when neither a file nor a stamp exists", function()
			-- Steady state after `clear_all`: save deletes the file and
			-- mark_synced stamps nil. Must not fire.
			arrange(storage_path)
			watcher.mark_synced(storage_path)

			watcher._check_storage_and_reload()

			assert.are.equal(0, #reload_reasons)
		end)

		it("reloads with reason 'external_write' when the file changes underneath us", function()
			arrange(storage_path)
			write_storage('{"version":2,"bookmarks":[]}')
			watcher.mark_synced(storage_path)

			-- A different byte length is detected regardless of mtime
			-- granularity, so this assertion holds on filesystems that
			-- report whole-second mtimes (e.g. some Docker volume drivers).
			write_storage('{"version":2,"bookmarks":[{"file":"a.lua","line":1,"note":"bug","id":"x"}]}')

			watcher._check_storage_and_reload()

			assert.are.same({ "external_write" }, reload_reasons)
		end)

		it("reloads when a file appears where we had no stamp", function()
			-- The CLI's first write into a project whose bookmarks were emptied.
			arrange(storage_path)
			watcher.mark_synced(storage_path)
			write_storage('{"version":2,"bookmarks":[]}')

			watcher._check_storage_and_reload()

			assert.are.same({ "external_write" }, reload_reasons)
		end)

		it("reloads when the file is deleted underneath us", function()
			arrange(storage_path)
			write_storage('{"version":2,"bookmarks":[]}')
			watcher.mark_synced(storage_path)

			vim.fn.delete(storage_path)

			watcher._check_storage_and_reload()

			assert.are.same({ "external_write" }, reload_reasons)
		end)

		it("re-stamps after reloading so the same write does not fire twice", function()
			arrange(storage_path)
			write_storage('{"version":2,"bookmarks":[]}')
			watcher.mark_synced(storage_path)

			write_storage('{"version":2,"bookmarks":[{"file":"a.lua","line":1,"note":"bug","id":"x"}]}')

			-- fs_event routinely reports a single logical write more than once.
			watcher._check_storage_and_reload()
			watcher._check_storage_and_reload()

			assert.are.same({ "external_write" }, reload_reasons)
		end)
	end)
end)
