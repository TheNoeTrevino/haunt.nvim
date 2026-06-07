-- ===========================================================================
-- haunt.nvim - Bookmark management for Neovim
--
-- MIT License. See LICENSE file for details.
-- ===========================================================================

---@tag haunt.nvim
---@tag haunt
---@toc_entry Introduction
---@toc

---@text
--- # Introduction ~
---
--- haunt.nvim is a powerful and elegant bookmark management plugin for Neovim.
--- It allows you to mark important lines in your code, navigate between them
--- effortlessly, and add contextual annotations - all persisted per git branch.
---
--- Features:
---   - Smart bookmarking with a single command
---   - Quick navigation between bookmarks
---   - Rich annotations displayed as virtual text
---   - Git-aware persistence (per repository and branch)
---   - Visual indicators (customizable signs and inline annotations)
---   - Automatic line tracking as you edit
---   - Zero configuration required
---
--- # Quick Start ~
---                                                           *haunt-quickstart*
---
--- After installation, haunt.nvim works out of the box with sensible defaults.
---
--- Basic usage: >lua
---   -- Add an annotation (creates bookmark if needed)
---   require('haunt.api').annotate()
---
---   -- Navigate to the next bookmark
---   require('haunt.api').next()
---
---   -- Navigate to the previous bookmark
---   require('haunt.api').prev()
---
---   -- Toggle annotation visibility
---   require('haunt.api').toggle_annotation()
---
---   -- Delete bookmark at current line
---   require('haunt.api').delete()
---
---   -- Clear all bookmarks in current file
---   require('haunt.api').clear()
--- <
---
--- Or use the provided commands: >vim
---   :HauntAnnotate
---   :HauntNext
---   :HauntPrev
---   :HauntToggle
---   :HauntDelete
---   :HauntList
---   :HauntClear
---   :HauntClearAll
---   :HauntQf
---   :HauntQfAll
---   :HauntMigrate          " Migrate legacy v1 bookmark file to v2 format
--- <
---
--- # Recommended Keymaps ~
---                                                             *haunt-keymaps*
--- >lua
---   -- Toggle bookmark annotation visibility
---   vim.keymap.set('n', 'mm', function() require('haunt.api').toggle_annotation() end,
---     { desc = "Toggle bookmark annotation" })
---
---   -- Navigate bookmarks
---   vim.keymap.set('n', 'mn', function() require('haunt.api').next() end,
---     { desc = "Next bookmark" })
---   vim.keymap.set('n', 'mp', function() require('haunt.api').prev() end,
---     { desc = "Previous bookmark" })
---
---   -- Annotate bookmark
---   vim.keymap.set('n', 'ma', function() require('haunt.api').annotate() end,
---     { desc = "Annotate bookmark" })
---
---   -- Delete bookmark
---   vim.keymap.set('n', 'md', function() require('haunt.api').delete() end,
---     { desc = "Delete bookmark" })
---
---   -- Clear bookmarks
---   vim.keymap.set('n', 'mc', function() require('haunt.api').clear() end,
---     { desc = "Clear bookmarks in file" })
---   vim.keymap.set('n', 'mC', function() require('haunt.api').clear_all() end,
---     { desc = "Clear all bookmarks" })
---
---   -- List bookmarks
---   vim.keymap.set('n', 'ml', function() require('haunt.picker').show() end,
---     { desc = "List bookmarks" })
--- <
---
--- # Persistence ~
---                                                          *haunt-persistence*
---
--- Bookmarks are saved automatically as JSON, one file per (project,
--- branch). The storage path is:
--- >
---   ~/.local/share/nvim/haunt/<hash>.json   (or your custom `data_dir`)
--- <
---
--- where `<hash>` is `sha256(project_id | branch)` truncated to 12 chars
--- and `project_id` is, in order of preference:
---
---   1. Git root commit hash (`git rev-list --max-parents=0 HEAD`)
---   2. Git repository top-level path
---   3. Current working directory
---
--- Inside the JSON, file paths are stored *relative* to the project root.
--- Bookmarks for files outside the project (e.g. `~/.config/nvim/init.lua`
--- while you're working in another repo) are stored with absolute paths
--- and an `absolute: true` flag, so they stay scoped to the project where
--- they were created.
---
--- Because keying is by root commit (not by the absolute repo path on
--- this machine), forks and clones of the same project share the same
--- bookmark file. Combined with relative paths, the file is portable
--- across machines and checkouts.
---
--- Auto-save fires on text changes (debounced) and on Neovim exit.
--- Per-branch storage means each git branch keeps its own bookmark set.
---
--- # Sharing Bookmarks ~
---                                                              *haunt-sharing*
---
--- Because the bookmark file is portable, you can share it across
--- machines or with teammates. Two common workflows:
---
--- Team sharing via git: ~
---
--- Commit the bookmark file to your repo so teammates pick up the same
--- hauntings. Either copy the existing file into the repo:
--- >sh
---   cp ~/.local/share/nvim/haunt/<hash>.json <repo>/.haunts.json
--- <
---
--- Or set `data_dir` to a path inside the repo so the file lives there
--- by default, then commit:
--- >lua
---   require("haunt").setup({
---     data_dir = vim.fn.getcwd() .. "/.haunts/",
---   })
--- <
---
--- Personal sync across machines: ~
---
--- Point `data_dir` at a NAS mount or a private git repo so your
--- bookmarks follow you across machines without leaking into the
--- project's shared git history. NFS over Tailscale works well:
--- >lua
---   require("haunt").setup({ data_dir = "/mnt/nas/haunt/" })
--- <
---
--- Or a private git repo cloned locally:
--- >lua
---   require("haunt").setup({
---     data_dir = vim.fn.expand("~/haunt-bookmarks/"),
---   })
--- <
---
--- For folder-sync tools (Dropbox, Syncthing, iCloud), be aware that
--- writes are non-atomic — concurrent writes from multiple machines
--- can produce sync-conflict copies. Git-based sync is safer.
---
--- # Migrating from v1 ~
---                                                            *haunt-migration*
---
--- v1 bookmark files (absolute paths, repo-path-keyed filename) are not
--- auto-loaded. On startup, haunt.nvim auto-migrates the current
--- project's v1 file to v2: it writes the v2 file at the new storage
--- path and renames the old file to `<old>.v1.bak`. Nothing is deleted.
---
--- For projects where automatic migration didn't run (or to retry
--- explicitly), invoke `:HauntMigrate` from inside the project.
---
--- # Troubleshooting ~
---                                                       *haunt-troubleshooting*
---
--- Bookmarks not persisting: ~
---
--- haunt.nvim derives a stable project identifier with the following
--- fallback chain:
---   1. Git root commit hash (`git rev-list --max-parents=0 HEAD`)
---   2. Git repository top-level path
---   3. Current working directory
--- The storage filename is `sha256(project_id | branch)`. If you switch
--- between these tiers (e.g. add a first commit to a new repo) the file
--- name will change, which can look like "lost" bookmarks.
---
--- Signs not showing: ~
---
--- 1. Verify signs are enabled in your terminal/GUI
--- 2. Check if another plugin is using the sign column
--- 3. Ensure your colorscheme defines the highlight groups
---
--- Bookmarks at wrong lines after editing: ~
---
--- This shouldn't happen as bookmarks use extmarks that track line changes.
--- If it does occur, save your bookmarks and restart Neovim.
---
--- Picker not working: ~
---
--- The picker supports Snacks.nvim (https://github.com/folke/snacks.nvim)
--- and Telescope.nvim (https://github.com/nvim-telescope/telescope.nvim).
--- Install one via your plugin manager, or configure which to use via
--- the `picker` option: "snacks", "telescope", or "auto" (default).

---@class HauntModule
---@field _has_potential_bookmarks fun(): boolean
---@field _ensure_initialized fun()
---@field _setup_restoration_autocmd fun()
---@field setup_autocmds fun()
---@field setup fun(opts?: HauntConfig)
---@field get_config fun(): HauntConfig
---@field is_setup fun(): boolean

---@private
---@type HauntModule
---@diagnostic disable-next-line: missing-fields
local M = {}

local config = require("haunt.config")

-- Track initialization state
---@type boolean
local _initialized = false

function M._ensure_initialized()
	if _initialized then
		return
	end
	_initialized = true

	local display = require("haunt.display")
	display.setup_signs(config.get())
end

---@private
function M._setup_restoration_autocmd()
	require("haunt.project").setup_autocmds()
	M.setup_autocmds()

	local augroup = vim.api.nvim_create_augroup("haunt_restore", { clear = true })
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = augroup,
		callback = function(args)
			M._ensure_initialized()
			require("haunt.api").restore_buffer_bookmarks(args.buf)
		end,
		desc = "Restore bookmark visuals when buffers are opened",
	})

	-- Clean up restoration tracking when buffers are deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		callback = function(args)
			require("haunt.api").cleanup_buffer_tracking(args.buf)
		end,
		desc = "Clean up bookmark restoration tracking",
	})

	-- Restore bookmarks for already-loaded buffers (they missed BufReadPost)
	M._ensure_initialized()
	local api = require("haunt.api")
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			api.restore_buffer_bookmarks(bufnr)
		end
	end

	require("haunt.migration").ensure_done()

	-- Auto-reload bookmarks on branch checkout (watches <gitdir>/HEAD).
	require("haunt.watcher").start()
end

-- Check if any bookmarks exist
-- This prevents unnecessary writes when there are no bookmarks
local function has_bookmarks()
	-- Use the API's has_bookmarks function which handles loading state properly
	local api = require("haunt.api")
	return api.has_bookmarks()
end

---@private
function M.setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("haunt_autosave", { clear = true })

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		pattern = "*",
		callback = function()
			require("haunt.watcher").stop()

			if not has_bookmarks() then
				return
			end

			local store = require("haunt.store")
			store.save()
		end,
		desc = "Auto-save all bookmarks before Vim exits",
	})

	vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		group = augroup,
		callback = function()
			vim.schedule(function()
				require("haunt.api").refresh_above_annotations()
			end)
		end,
		desc = "Re-wrap above annotations to fit new window width",
	})
end

--- Setup function for haunt.nvim.
---
--- Initializes the plugin with user configuration. This is optional -
--- haunt.nvim works with zero configuration using sensible defaults.
---
---@param opts? HauntConfig Optional configuration table. See |HauntConfig|.
---
---@usage >lua
---   -- Use defaults (no setup required)
---   require('haunt.api').annotate()
---
---   -- Or customize with setup
---   require('haunt').setup({
---     sign = '',
---     sign_hl = 'DiagnosticInfo',
---     virt_text_hl = 'Comment',
---   })
--- <
function M.setup(opts)
	config.setup(opts)

	local user_config = config.get()
	if user_config.data_dir then
		require("haunt.persistence").set_data_dir(user_config.data_dir)
	end

	-- Defer migration off the startup path. Readers gate on migration.ensure_done()
	-- (see persistence.load_bookmarks), so this is purely a latency optimization —
	-- if a reader fires before this scheduled callback runs, the reader runs the
	-- migration synchronously itself.
	vim.schedule(function()
		require("haunt.migration").auto_migrate()
	end)
end

--- Get the current configuration.
---
---@return HauntConfig config The current configuration
function M.get_config()
	return config.get()
end

--- Check if setup has been called.
---
---@return boolean is_setup True if setup has been called, false otherwise
function M.is_setup()
	return config.is_setup()
end

return M
