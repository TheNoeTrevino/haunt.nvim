---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.migration", function()
	local migration
	local persistence
	local config
	local project_mock = require("tests.helpers.project_mock")

	-- Real captured items.
	local notifications
	local original_notify

	-- Per-test fake fixtures.
	local fake_data_dir
	local fake_project_root
	local fake_project_id
	local fake_branch

	--- Compute the v1 path the same way migration.lua does internally.
	---@param project_root string
	---@param branch string|nil
	---@param data_dir string
	---@param per_branch boolean
	local function v1_path_for(project_root, branch, data_dir, per_branch)
		if not per_branch then
			return data_dir .. vim.fn.sha256(project_root):sub(1, 12) .. ".json"
		end
		local b = branch or "__default__"
		local key = project_root .. "|" .. b
		return data_dir .. vim.fn.sha256(key):sub(1, 12) .. ".json"
	end

	--- Compute the v2 path the same way persistence.get_storage_path does internally.
	---@param project_id string
	---@param branch string|nil
	---@param data_dir string
	---@param per_branch boolean
	local function v2_path_for(project_id, branch, data_dir, per_branch)
		if not per_branch then
			return data_dir .. vim.fn.sha256(project_id):sub(1, 12) .. ".json"
		end
		local b = branch or "__default__"
		local key = project_id .. "|" .. b
		return data_dir .. vim.fn.sha256(key):sub(1, 12) .. ".json"
	end

	--- Write a JSON file as the given table.
	---@param path string
	---@param tbl table
	local function write_json(path, tbl)
		local json_str = vim.json.encode(tbl)
		vim.fn.writefile({ json_str }, path)
	end

	--- Read a JSON file back as a table.
	---@param path string
	---@return table data
	local function read_json(path)
		local lines = vim.fn.readfile(path)
		local json_str = table.concat(lines, "\n")
		return vim.json.decode(json_str)
	end

	--- Find a captured notification whose message contains `needle`.
	---@param needle string
	---@return table|nil entry
	local function find_notification(needle)
		for _, n in ipairs(notifications) do
			if type(n.msg) == "string" and n.msg:find(needle, 1, true) then
				return n
			end
		end
		return nil
	end

	--- Return the 1-based index of the first captured notification whose
	--- message contains `needle`, or nil if none found. Used to assert
	--- ordering of notifies (e.g. "starting migration" must precede
	--- "migration successful").
	---@param needle string
	---@return integer|nil index
	local function index_of_notification(needle)
		for i, n in ipairs(notifications) do
			if type(n.msg) == "string" and n.msg:find(needle, 1, true) then
				return i
			end
		end
		return nil
	end

	before_each(function()
		helpers.reset_modules()
		package.loaded["haunt.migration"] = nil

		config = require("haunt.config")
		config.setup({ per_branch_bookmarks = true })

		persistence = require("haunt.persistence")
		migration = require("haunt.migration")

		-- Create a hermetic temp data dir.
		fake_data_dir = vim.fn.tempname() .. "_haunt_migration_test/"
		vim.fn.mkdir(fake_data_dir, "p")

		fake_project_root = "/fake/proj"
		fake_project_id = "rootcommit-abcdef"
		fake_branch = "main"

		project_mock.set({
			root = fake_project_root,
			branch = fake_branch,
			project_id = fake_project_id,
		})

		persistence.set_data_dir(fake_data_dir)

		-- Capture vim.notify calls.
		notifications = {}
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
	end)

	after_each(function()
		project_mock.restore()
		if persistence then
			persistence.set_data_dir(nil)
		end

		vim.notify = original_notify

		if fake_data_dir and vim.fn.isdirectory(fake_data_dir) == 1 then
			vim.fn.delete(fake_data_dir, "rf")
		end
	end)

	it("migrates v1 file with all in-project bookmarks to v2", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		assert.are_not.equal(old_path, new_path)

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1", note = "First" },
				{ file = "/fake/proj/lib/util.lua", line = 5, id = "id2" },
			},
		})

		migration.migrate_current_project()

		assert.are.equal(1, vim.fn.filereadable(new_path))
		local data = read_json(new_path)
		assert.are.equal(2, data.version)
		assert.are.equal(2, #data.bookmarks)
		assert.are.equal("src/main.lua", data.bookmarks[1].file)
		assert.is_nil(data.bookmarks[1].absolute)
		assert.are.equal("lib/util.lua", data.bookmarks[2].file)
		assert.is_nil(data.bookmarks[2].absolute)

		-- Old file renamed, backup exists.
		assert.are.equal(0, vim.fn.filereadable(old_path))
		assert.are.equal(1, vim.fn.filereadable(old_path .. ".v1.bak"))

		-- Both the start and success notifies must fire, in order, and the
		-- success notify must reference the backup path.
		local start = find_notification("starting migration")
		assert.is_not_nil(start)
		assert.are.equal(vim.log.levels.INFO, start.level)
		assert.is_not_nil(start.msg:find(old_path .. ".v1.bak", 1, true))

		local success = find_notification("migration successful")
		assert.is_not_nil(success)
		assert.are.equal(vim.log.levels.INFO, success.level)
		assert.is_not_nil(success.msg:find("2 bookmarks", 1, true))
		assert.is_not_nil(success.msg:find(old_path .. ".v1.bak", 1, true))

		local start_idx = index_of_notification("starting migration")
		local success_idx = index_of_notification("migration successful")
		assert.is_not_nil(start_idx)
		assert.is_not_nil(success_idx)
		assert.is_true(start_idx < success_idx)
	end)

	it("preserves out-of-project bookmarks with absolute=true", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "in1" },
				{ file = "/etc/hosts", line = 1, id = "out1" },
			},
		})

		migration.migrate_current_project()

		local data = read_json(new_path)
		assert.are.equal(2, data.version)
		assert.are.equal(2, #data.bookmarks)

		-- In-project bookmark.
		assert.are.equal("src/main.lua", data.bookmarks[1].file)
		assert.is_nil(data.bookmarks[1].absolute)

		-- Out-of-project bookmark preserved with absolute=true.
		assert.are.equal("/etc/hosts", data.bookmarks[2].file)
		assert.is_true(data.bookmarks[2].absolute)

		assert.is_not_nil(find_notification("1 relative, 1 absolute"))
	end)

	it("aborts when v2 file already exists at new path", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
			},
		})
		write_json(new_path, {
			version = 2,
			bookmarks = {
				{ file = "existing.lua", line = 1, id = "preexisting" },
			},
		})

		migration.migrate_current_project()

		-- Old file untouched (still v1).
		assert.are.equal(1, vim.fn.filereadable(old_path))
		assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))
		local old_data = read_json(old_path)
		assert.are.equal(1, old_data.version)

		-- New v2 file unchanged (still has the pre-existing entry).
		local new_data = read_json(new_path)
		assert.are.equal(1, #new_data.bookmarks)
		assert.are.equal("preexisting", new_data.bookmarks[1].id)

		-- Saw the refusal notify with the new actionable wording.
		local refusal = find_notification("cannot migrate")
		assert.is_not_nil(refusal)
		assert.are.equal(vim.log.levels.ERROR, refusal.level)
		-- Both paths must appear in the message so the user can act.
		assert.is_not_nil(refusal.msg:find(old_path, 1, true))
		assert.is_not_nil(refusal.msg:find(new_path, 1, true))

		-- We aborted before announcing migration — the start notify must
		-- NOT have fired (otherwise users see a misleading "starting
		-- migration" followed immediately by an error).
		assert.is_nil(find_notification("starting migration"))
		assert.is_nil(find_notification("migration successful"))
	end)

	it("is a no-op (info-level) when no v1 file exists at old path", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		-- Sanity: nothing on disk to start.
		assert.are.equal(0, vim.fn.filereadable(old_path))
		assert.are.equal(0, vim.fn.filereadable(new_path))

		migration.migrate_current_project()

		assert.are.equal(0, vim.fn.filereadable(old_path))
		assert.are.equal(0, vim.fn.filereadable(new_path))
		assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))

		local n = find_notification("no v1 file found")
		assert.is_not_nil(n)
		assert.are.equal(vim.log.levels.INFO, n.level)

		-- Bailed out before the migration body — no start/success notifies.
		assert.is_nil(find_notification("starting migration"))
		assert.is_nil(find_notification("migration successful"))
	end)

	it("aborts when file at old path is not version=1", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		-- Seed a v2 file at the OLD path - migration should refuse to touch it.
		write_json(old_path, {
			version = 2,
			bookmarks = {
				{ file = "src/main.lua", line = 1, id = "v2-already" },
			},
		})

		migration.migrate_current_project()

		-- Old file untouched.
		assert.are.equal(1, vim.fn.filereadable(old_path))
		assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))
		-- New path was NOT created.
		assert.are.equal(0, vim.fn.filereadable(new_path))

		local err = find_notification("expected version=1")
		assert.is_not_nil(err)
		assert.are.equal(vim.log.levels.ERROR, err.level)
	end)

	it("warns and aborts when not in a git repo", function()
		project_mock.set({ root = nil, branch = nil, project_id = "fallback" })

		-- Compute what the path WOULD be if there were a repo, so we can verify
		-- nothing got written there either.
		local hypothetical_old = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		write_json(hypothetical_old, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
			},
		})

		migration.migrate_current_project()

		-- Old file remains untouched (no rename, no backup).
		assert.are.equal(1, vim.fn.filereadable(hypothetical_old))
		assert.are.equal(0, vim.fn.filereadable(hypothetical_old .. ".v1.bak"))

		local warn = find_notification("not in a git repo")
		assert.is_not_nil(warn)
		assert.are.equal(vim.log.levels.WARN, warn.level)
	end)

	it("strips runtime-only extmark fields when migrating", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{
					file = "/fake/proj/src/main.lua",
					line = 10,
					id = "id1",
					note = "kept",
					extmark_id = 123,
					annotation_extmark_id = 456,
				},
			},
		})

		migration.migrate_current_project()

		local data = read_json(new_path)
		assert.are.equal(1, #data.bookmarks)
		assert.are.equal("src/main.lua", data.bookmarks[1].file)
		assert.are.equal(10, data.bookmarks[1].line)
		assert.are.equal("id1", data.bookmarks[1].id)
		assert.are.equal("kept", data.bookmarks[1].note)
		assert.is_nil(data.bookmarks[1].extmark_id)
		assert.is_nil(data.bookmarks[1].annotation_extmark_id)
	end)

	it("aborts cleanly when rename of v1 to backup fails", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
		local new_path = persistence.get_storage_path()

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
			},
		})

		-- Force fs_rename to fail. libuv returns false (no error) on failure.
		local original_rename = vim.uv.fs_rename
		vim.uv.fs_rename = function()
			return false, "EACCES: permission denied", "EACCES"
		end

		-- api.reload must NOT be invoked on the failure path.
		local api = require("haunt.api")
		local original_reload = api.reload
		local reload_calls = 0
		api.reload = function()
			reload_calls = reload_calls + 1
			return true
		end

		local ok, err = pcall(migration.migrate_current_project)

		vim.uv.fs_rename = original_rename
		api.reload = original_reload

		assert.is_true(ok, "migrate_current_project raised: " .. tostring(err))

		-- v1 still in place (rename failed, so it was never moved).
		assert.are.equal(1, vim.fn.filereadable(old_path))
		assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))

		-- v2 must have been cleaned up so we don't enter dual-state.
		assert.are.equal(0, vim.fn.filereadable(new_path))

		-- ERROR notify, not WARN+success.
		local fail = find_notification("migration aborted")
		assert.is_not_nil(fail)
		assert.are.equal(vim.log.levels.ERROR, fail.level)
		assert.is_not_nil(fail.msg:find(old_path .. ".v1.bak", 1, true))

		assert.is_nil(find_notification("migration successful"))
		assert.are.equal(0, reload_calls)

		-- A subsequent auto_migrate must NOT trip the dual-state guard,
		-- since v2 was cleaned up. Restore rename so the retry can succeed.
		migration._reset_for_testing()
		notifications = {}
		migration.auto_migrate()

		assert.is_nil(find_notification("cannot migrate"))
		assert.are.equal(1, vim.fn.filereadable(new_path))
		assert.are.equal(1, vim.fn.filereadable(old_path .. ".v1.bak"))
	end)

	it("calls api.reload after a successful migration", function()
		local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)

		write_json(old_path, {
			version = 1,
			bookmarks = {
				{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
			},
		})

		-- Replace api.reload with a counter so we can assert it was invoked
		-- exactly once after the success notify. Restore on teardown.
		local api = require("haunt.api")
		local original_reload = api.reload
		local reload_calls = 0
		api.reload = function()
			reload_calls = reload_calls + 1
			return true
		end

		local ok, err = pcall(migration.migrate_current_project)

		api.reload = original_reload

		assert.is_true(ok, "migrate_current_project raised: " .. tostring(err))
		assert.are.equal(1, reload_calls)
		-- Sanity: success notify was emitted (so reload happened in the
		-- success path, not the error path).
		local success = find_notification("migration successful")
		assert.is_not_nil(success)
		assert.is_not_nil(success.msg:find("1 bookmarks", 1, true))
	end)

	describe("auto_migrate", function()
		before_each(function()
			-- Each auto_migrate test starts with a clean session table so
			-- the dual-state once-per-session guard doesn't leak state.
			migration._reset_for_testing()
		end)

		it("calls migrate_current_project when only v1 exists", function()
			local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
			local new_path = persistence.get_storage_path()

			assert.are_not.equal(old_path, new_path)

			write_json(old_path, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})

			migration.auto_migrate()

			-- Migration ran: v2 file written, v1 backed up.
			assert.are.equal(1, vim.fn.filereadable(new_path))
			assert.are.equal(0, vim.fn.filereadable(old_path))
			assert.are.equal(1, vim.fn.filereadable(old_path .. ".v1.bak"))

			-- Saw the start and success notifies from migrate_current_project.
			assert.is_not_nil(find_notification("starting migration"))
			assert.is_not_nil(find_notification("migration successful"))
		end)

		it("emits ERROR with both paths when v1 and v2 both exist", function()
			local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
			local new_path = persistence.get_storage_path()

			write_json(old_path, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})
			write_json(new_path, {
				version = 2,
				bookmarks = {
					{ file = "src/main.lua", line = 10, id = "v2id" },
				},
			})

			migration.auto_migrate()

			-- Migration did NOT run: v1 untouched, no backup, v2 unchanged.
			assert.are.equal(1, vim.fn.filereadable(old_path))
			assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))
			local v2_data = read_json(new_path)
			assert.are.equal(1, #v2_data.bookmarks)
			assert.are.equal("v2id", v2_data.bookmarks[1].id)

			local refusal = find_notification("cannot migrate")
			assert.is_not_nil(refusal)
			assert.are.equal(vim.log.levels.ERROR, refusal.level)
			assert.is_not_nil(refusal.msg:find(old_path, 1, true))
			assert.is_not_nil(refusal.msg:find(new_path, 1, true))

			-- migrate_current_project's start notify must NOT have fired.
			assert.is_nil(find_notification("starting migration"))
		end)

		it("dual-state ERROR notify is idempotent per session", function()
			local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
			local new_path = persistence.get_storage_path()

			write_json(old_path, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})
			write_json(new_path, {
				version = 2,
				bookmarks = {
					{ file = "src/main.lua", line = 10, id = "v2id" },
				},
			})

			migration.auto_migrate()
			migration.auto_migrate()

			-- Only ONE ERROR notify in total.
			local count = 0
			for _, n in ipairs(notifications) do
				if type(n.msg) == "string" and n.msg:find("cannot migrate", 1, true) then
					count = count + 1
				end
			end
			assert.are.equal(1, count)
		end)

		it("_reset_for_testing allows the dual-state ERROR to fire again", function()
			local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
			local new_path = persistence.get_storage_path()

			write_json(old_path, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})
			write_json(new_path, {
				version = 2,
				bookmarks = {
					{ file = "src/main.lua", line = 10, id = "v2id" },
				},
			})

			migration.auto_migrate()
			notifications = {}
			migration._reset_for_testing()
			migration.auto_migrate()

			assert.is_not_nil(find_notification("cannot migrate"))
		end)

		it("is silent when no v1 file exists at the old path", function()
			-- Don't seed any old file.
			migration.auto_migrate()

			assert.are.equal(0, #notifications)
		end)

		it("is silent when not in a git repo", function()
			-- Seed a hypothetical v1 file so we know silence is driven by
			-- the project.root nil check, not by absence of a file.
			local hypothetical_old = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)
			write_json(hypothetical_old, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})

			project_mock.set({ root = nil, branch = nil, project_id = "/tmp/cwd" })

			migration.auto_migrate()

			assert.are.equal(0, #notifications)
			-- Old file remains untouched.
			assert.are.equal(1, vim.fn.filereadable(hypothetical_old))
			assert.are.equal(0, vim.fn.filereadable(hypothetical_old .. ".v1.bak"))
		end)

		describe("haunt.setup() integration", function()
			local custom_data_dir
			local v1_path
			local v2_path

			before_each(function()
				-- Restore the real ensure_data_dir so set_data_dir drives the
				-- path; the outer before_each pins it to fake_data_dir.
				persistence.ensure_data_dir = original_ensure_data_dir

				custom_data_dir = vim.fn.tempname() .. "_haunt_setup/"
				vim.fn.mkdir(custom_data_dir, "p")
				v1_path = v1_path_for(fake_project_root, fake_branch, custom_data_dir, true)
				v2_path = v2_path_for(fake_project_id, fake_branch, custom_data_dir, true)

				write_json(v1_path, {
					version = 1,
					bookmarks = {
						{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
					},
				})
			end)

			after_each(function()
				persistence.set_data_dir(nil)
				if custom_data_dir and vim.fn.isdirectory(custom_data_dir) == 1 then
					vim.fn.delete(custom_data_dir, "rf")
				end
			end)

			it("runs synchronously from haunt.setup() at the configured data_dir", function()
				assert.are_not.equal(v1_path, v2_path)

				require("haunt").setup({
					data_dir = custom_data_dir,
					per_branch_bookmarks = true,
				})

				-- setup() must finish migration before returning — no
				-- vim.schedule, no UIEnter, no waiting.
				assert.are.equal(0, vim.fn.filereadable(v1_path))
				assert.are.equal(1, vim.fn.filereadable(v1_path .. ".v1.bak"))
				assert.are.equal(1, vim.fn.filereadable(v2_path))

				local data = read_json(v2_path)
				assert.are.equal(2, data.version)
				assert.are.equal(1, #data.bookmarks)
				assert.are.equal("src/main.lua", data.bookmarks[1].file)

				-- The "v1 bookmark storage detected — run :HauntMigrate" warning
				-- in persistence.load_bookmarks must not fire on the post-setup()
				-- path: setup() migrates first, so any later store.load reads v2.
				assert.is_nil(find_notification("v1 bookmark storage detected"))
			end)

			it("is idempotent across the setup() and UIEnter-fallback paths", function()
				require("haunt").setup({
					data_dir = custom_data_dir,
					per_branch_bookmarks = true,
				})

				assert.are.equal(1, vim.fn.filereadable(v1_path .. ".v1.bak"))
				assert.are.equal(1, vim.fn.filereadable(v2_path))
				assert.is_not_nil(find_notification("migration successful"))

				local v2_mtime_before = vim.fn.getftime(v2_path)
				local v2_data_before = read_json(v2_path)
				local notifications_after_setup = #notifications

				-- Second auto_migrate must early-return: no new notifies, no
				-- rewrite of v2, no resurrection of v1.
				migration.auto_migrate()

				assert.are.equal(notifications_after_setup, #notifications)
				assert.are.equal(0, vim.fn.filereadable(v1_path))
				assert.are.equal(1, vim.fn.filereadable(v1_path .. ".v1.bak"))
				assert.are.equal(v2_mtime_before, vim.fn.getftime(v2_path))
				assert.are.same(v2_data_before, read_json(v2_path))
			end)
		end)

		it("is silent when old_path == new_path", function()
			local old_path = v1_path_for(fake_project_root, fake_branch, fake_data_dir, true)

			-- Seed a v1 file at the old path.
			write_json(old_path, {
				version = 1,
				bookmarks = {
					{ file = "/fake/proj/src/main.lua", line = 10, id = "id1" },
				},
			})

			-- Force new storage path to equal old path (simulates project_id
			-- falling back to repo path).
			local original_get_storage_path = persistence.get_storage_path
			persistence.get_storage_path = function()
				return old_path
			end

			migration.auto_migrate()

			persistence.get_storage_path = original_get_storage_path

			assert.are.equal(0, #notifications)
			-- v1 file untouched (no migration attempted).
			assert.are.equal(1, vim.fn.filereadable(old_path))
			assert.are.equal(0, vim.fn.filereadable(old_path .. ".v1.bak"))
		end)
	end)
end)
