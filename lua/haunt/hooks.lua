---@toc_entry Hook Registry
---@tag haunt-hooks
---@text
--- # Hook Registry ~
---
--- The hook registry allows external plugins and users to listen to
--- bookmark lifecycle events. Register typed callbacks to react when
--- bookmarks are created, deleted, updated, navigated, saved, loaded,
--- or restored.
---
--- Each event provides typed methods: `on_<event>()` to register,
--- `once_<event>()` for one-shot callbacks, `off_<event>()` to
--- unregister, and `emit_<event>()` to fire (used internally).
---
--- Available methods:
--- - `on_create`: fired after a bookmark is successfully created
--- - `on_delete`: fired after a bookmark is successfully deleted
--- - `on_update`: fired after a bookmark annotation is updated
--- - `on_navigation`: fired after jumping to a bookmark via next/prev
--- - `on_toggle`: fired after a single bookmark's annotation visibility is toggled
--- - `on_toggle_all`: fired after all annotations are toggled globally
--- - `on_pre_save`: fired before bookmarks are persisted to disk
--- - `on_post_save`: fired after bookmarks are persisted to disk
--- - `on_load`: fired after bookmarks are loaded from disk
--- - `on_restore`: fired after a buffer's bookmark visuals are restored
--- - `on_clear`: fired after all bookmarks in the current file are cleared
--- - `on_clear_all`: fired after all bookmarks in the project are cleared
--- - `on_data_dir_change`: fired after the data directory is switched
---
--- Example:
--- >lua
---   local hooks = require("haunt.hooks")
---
---   hooks.on_create(function(ctx)
---     print("Created bookmark:", ctx.bookmark.id)
---   end)
--- <

--- Context passed to `on_create` callbacks.
--- Fired after a bookmark is successfully created and persisted.
---@class BookmarkCreatedContext
---@field bookmark Bookmark The newly created bookmark with its assigned ID, extmark, and sign
---@field bufnr number Buffer number where the bookmark was created
---@field file string Normalized absolute file path of the bookmarked file
---@field line number 1-based line number where the bookmark was placed

--- Context passed to `on_delete` callbacks.
--- Fired after a bookmark is successfully removed from the store and persisted.
--- Also fired once per bookmark during `clear()` and `clear_all()` operations.
---@class BookmarkDeletedContext
---@field bookmark Bookmark The bookmark that was deleted (visual elements already cleaned up)
---@field bufnr number|nil Buffer number where the bookmark existed (nil if buffer not loaded)
---@field file string Normalized absolute file path of the deleted bookmark
---@field line number 1-based line number where the bookmark was located

--- Context passed to `on_update` callbacks.
--- Fired after a bookmark's annotation text is changed and persisted.
---@class BookmarkUpdatedContext
---@field bookmark Bookmark The bookmark after the update (reflects new annotation state)
---@field bufnr number Buffer number where the bookmark exists
---@field file string Normalized absolute file path of the updated bookmark
---@field line number 1-based line number of the updated bookmark
---@field old_note string|nil The previous annotation text (nil if bookmark had no annotation)
---@field new_note string The new annotation text that was applied

--- Context passed to `on_navigation` callbacks.
--- Fired after jumping to a bookmark via `next()` or `prev()`.
---@class NavigationContext
---@field bookmark Bookmark The bookmark that was navigated to
---@field bufnr number Buffer number of the current buffer
---@field file string Normalized absolute file path of the current buffer
---@field direction "next"|"prev" The navigation direction that was requested
---@field from_line number 1-based line number the cursor was on before the jump
---@field to_line number 1-based line number the cursor jumped to

--- Context passed to `on_toggle` callbacks.
--- Fired after a single bookmark's annotation visibility is toggled.
---@class ToggleContext
---@field bookmark Bookmark The bookmark whose annotation was toggled
---@field bufnr number Buffer number where the toggle occurred
---@field file string Normalized absolute file path of the toggled bookmark
---@field line number 1-based line number of the toggled bookmark
---@field visible boolean Whether the annotation is now visible (true = shown, false = hidden)

--- Context passed to `on_toggle_all` callbacks.
--- Fired after all annotations are toggled globally via `toggle_all_lines()`.
---@class ToggleAllContext
---@field visible boolean The new global annotation visibility state (true = shown, false = hidden)
---@field count number Number of bookmarks that were actually toggled (excludes bookmarks without notes or in unloaded buffers)

--- Context passed to `on_pre_save` callbacks.
--- Fired before bookmarks are written to disk. Useful for logging or validation.
---@class PreSaveContext
---@field bookmarks Bookmark[] The full bookmarks array about to be saved (direct reference, do not mutate)
---@field count number Total number of bookmarks being saved
---@field async boolean True if this is an asynchronous save (autosave), false for synchronous saves

--- Context passed to `on_post_save` callbacks.
--- Fired after bookmarks are written to disk (or the write attempt completes).
---@class PostSaveContext
---@field bookmarks Bookmark[] The bookmarks that were just saved (direct reference, do not mutate)
---@field count number Total number of bookmarks that were saved
---@field success boolean Whether the save operation succeeded
---@field async boolean True if this was an asynchronous save (autosave), false for synchronous saves

--- Context passed to `on_load` callbacks.
--- Fired after bookmarks are loaded from disk into memory.
---@class LoadContext
---@field bookmarks Bookmark[] The bookmarks that were loaded (direct reference, do not mutate)
---@field count number Total number of bookmarks loaded

--- Context passed to `on_restore` callbacks.
--- Fired after a buffer's bookmark visuals (extmarks, signs, annotations) are restored.
---@class RestoreContext
---@field bufnr number Buffer number that had its bookmarks restored
---@field file string Normalized absolute file path of the restored buffer
---@field bookmarks Bookmark[] The bookmarks that were restored in this buffer
---@field count number Number of bookmarks restored in this buffer

--- Context passed to `on_clear` callbacks.
--- Fired after all bookmarks in a single file are cleared via `clear()`.
--- Individual `on_delete` events are also fired for each bookmark before this event.
---@class ClearContext
---@field bufnr number Buffer number of the file that was cleared
---@field file string Normalized absolute file path that was cleared
---@field bookmarks Bookmark[] The bookmarks that were cleared (already removed from store)
---@field count number Number of bookmarks that were cleared

--- Context passed to `on_clear_all` callbacks.
--- Fired after all bookmarks across the project are cleared via `clear_all()`.
--- Individual `on_delete` events are also fired for each bookmark before this event.
---@class ClearAllContext
---@field bookmarks Bookmark[] All bookmarks that were cleared (already removed from store)
---@field count number Total number of bookmarks that were cleared

--- Context passed to `on_data_dir_change` callbacks.
--- Fired after the data directory is switched and bookmarks are reloaded.
---@class DataDirChangeContext
---@field new_dir string|nil The new data directory path (nil means reset to default)
---@field old_dir string The previous data directory path

---@class HooksModule
---@field on_create fun(fn: fun(ctx: BookmarkCreatedContext)): boolean
---@field once_create fun(fn: fun(ctx: BookmarkCreatedContext)): boolean
---@field off_create fun(fn: fun(ctx: BookmarkCreatedContext)): boolean
---@field emit_create fun(ctx: BookmarkCreatedContext): number, boolean
---@field on_delete fun(fn: fun(ctx: BookmarkDeletedContext)): boolean
---@field once_delete fun(fn: fun(ctx: BookmarkDeletedContext)): boolean
---@field off_delete fun(fn: fun(ctx: BookmarkDeletedContext)): boolean
---@field emit_delete fun(ctx: BookmarkDeletedContext): number, boolean
---@field on_update fun(fn: fun(ctx: BookmarkUpdatedContext)): boolean
---@field once_update fun(fn: fun(ctx: BookmarkUpdatedContext)): boolean
---@field off_update fun(fn: fun(ctx: BookmarkUpdatedContext)): boolean
---@field emit_update fun(ctx: BookmarkUpdatedContext): number, boolean
---@field on_navigation fun(fn: fun(ctx: NavigationContext)): boolean
---@field once_navigation fun(fn: fun(ctx: NavigationContext)): boolean
---@field off_navigation fun(fn: fun(ctx: NavigationContext)): boolean
---@field emit_navigation fun(ctx: NavigationContext): number, boolean
---@field on_toggle fun(fn: fun(ctx: ToggleContext)): boolean
---@field once_toggle fun(fn: fun(ctx: ToggleContext)): boolean
---@field off_toggle fun(fn: fun(ctx: ToggleContext)): boolean
---@field emit_toggle fun(ctx: ToggleContext): number, boolean
---@field on_toggle_all fun(fn: fun(ctx: ToggleAllContext)): boolean
---@field once_toggle_all fun(fn: fun(ctx: ToggleAllContext)): boolean
---@field off_toggle_all fun(fn: fun(ctx: ToggleAllContext)): boolean
---@field emit_toggle_all fun(ctx: ToggleAllContext): number, boolean
---@field on_pre_save fun(fn: fun(ctx: PreSaveContext)): boolean
---@field once_pre_save fun(fn: fun(ctx: PreSaveContext)): boolean
---@field off_pre_save fun(fn: fun(ctx: PreSaveContext)): boolean
---@field emit_pre_save fun(ctx: PreSaveContext): number, boolean
---@field on_post_save fun(fn: fun(ctx: PostSaveContext)): boolean
---@field once_post_save fun(fn: fun(ctx: PostSaveContext)): boolean
---@field off_post_save fun(fn: fun(ctx: PostSaveContext)): boolean
---@field emit_post_save fun(ctx: PostSaveContext): number, boolean
---@field on_load fun(fn: fun(ctx: LoadContext)): boolean
---@field once_load fun(fn: fun(ctx: LoadContext)): boolean
---@field off_load fun(fn: fun(ctx: LoadContext)): boolean
---@field emit_load fun(ctx: LoadContext): number, boolean
---@field on_restore fun(fn: fun(ctx: RestoreContext)): boolean
---@field once_restore fun(fn: fun(ctx: RestoreContext)): boolean
---@field off_restore fun(fn: fun(ctx: RestoreContext)): boolean
---@field emit_restore fun(ctx: RestoreContext): number, boolean
---@field on_clear fun(fn: fun(ctx: ClearContext)): boolean
---@field once_clear fun(fn: fun(ctx: ClearContext)): boolean
---@field off_clear fun(fn: fun(ctx: ClearContext)): boolean
---@field emit_clear fun(ctx: ClearContext): number, boolean
---@field on_clear_all fun(fn: fun(ctx: ClearAllContext)): boolean
---@field once_clear_all fun(fn: fun(ctx: ClearAllContext)): boolean
---@field off_clear_all fun(fn: fun(ctx: ClearAllContext)): boolean
---@field emit_clear_all fun(ctx: ClearAllContext): number, boolean
---@field on_data_dir_change fun(fn: fun(ctx: DataDirChangeContext)): boolean
---@field once_data_dir_change fun(fn: fun(ctx: DataDirChangeContext)): boolean
---@field off_data_dir_change fun(fn: fun(ctx: DataDirChangeContext)): boolean
---@field emit_data_dir_change fun(ctx: DataDirChangeContext): number, boolean
---@field _reset_for_testing fun()
local M = {}

local hook_events = require("haunt.hook_events")

---@private
---@type table<string, boolean>
local valid_events = {}
for _, event_name in pairs(hook_events) do
	valid_events[event_name] = true
end

---@private
---@param event string
---@return boolean
local function is_valid_event(event)
	return valid_events[event] == true
end

---@private
---@type table<HauntEvent, function[]>
local event_handlers = {}

---@private
local function _on(event, fn)
	if not is_valid_event(event) then
		vim.notify("haunt.hooks: unknown event '" .. tostring(event) .. "'", vim.log.levels.ERROR)
		return false
	end
	if type(fn) ~= "function" then
		vim.notify("haunt.hooks: must register a function", vim.log.levels.ERROR)
		return false
	end
	event_handlers[event] = event_handlers[event] or {}
	table.insert(event_handlers[event], fn)
	return true
end

---@private
local function _off(event, fn)
	if not is_valid_event(event) then
		vim.notify("haunt.hooks: unknown event '" .. tostring(event) .. "'", vim.log.levels.ERROR)
		return false
	end
	if not event_handlers[event] then
		return false
	end
	for i, callback in ipairs(event_handlers[event]) do
		if callback == fn then
			table.remove(event_handlers[event], i)
			return true
		end
	end
	return false
end

---@private
local function _once(event, fn)
	if type(fn) ~= "function" then
		vim.notify("haunt.hooks: must register a function", vim.log.levels.ERROR)
		return false
	end
	local wrapper
	wrapper = function(ctx)
		fn(ctx)
		_off(event, wrapper)
	end
	return _on(event, wrapper)
end

---@private
local function _emit(event, ctx)
	if not event_handlers[event] then
		return 0, true
	end
	local handlers = { unpack(event_handlers[event]) }
	local total = 0
	local all_succeeded = true
	for _, fn in ipairs(handlers) do
		total = total + 1
		local ok, err = pcall(fn, ctx)
		if not ok then
			all_succeeded = false
			vim.notify("haunt.nvim: hook error with event [" .. event .. "]: \n" .. tostring(err), vim.log.levels.WARN)
		end
	end
	return total, all_succeeded
end

--- Register a callback for the `on_create` event.
---
--- Usage: >lua
---   local hooks = require("haunt.hooks")
---   hooks.on_create(function(ctx)
---     print("Created:", ctx.bookmark.id, "at line", ctx.line)
---   end)
--- <
---@param fn fun(ctx: BookmarkCreatedContext)
---@return boolean success
function M.on_create(fn)
	return _on("on_create", fn)
end

--- Register a one-shot callback for the `on_create` event.
---@param fn fun(ctx: BookmarkCreatedContext)
---@return boolean success
function M.once_create(fn)
	return _once("on_create", fn)
end

--- Unregister a callback from the `on_create` event.
---@param fn fun(ctx: BookmarkCreatedContext)
---@return boolean success
function M.off_create(fn)
	return _off("on_create", fn)
end

--- Emit the `on_create` event to all registered callbacks.
---@param ctx BookmarkCreatedContext
---@return number total
---@return boolean all_succeeded
function M.emit_create(ctx)
	return _emit("on_create", ctx)
end

--- Register a callback for the `on_delete` event.
---@param fn fun(ctx: BookmarkDeletedContext)
---@return boolean success
function M.on_delete(fn)
	return _on("on_delete", fn)
end

--- Register a one-shot callback for the `on_delete` event.
---@param fn fun(ctx: BookmarkDeletedContext)
---@return boolean success
function M.once_delete(fn)
	return _once("on_delete", fn)
end

--- Unregister a callback from the `on_delete` event.
---@param fn fun(ctx: BookmarkDeletedContext)
---@return boolean success
function M.off_delete(fn)
	return _off("on_delete", fn)
end

--- Emit the `on_delete` event to all registered callbacks.
---@param ctx BookmarkDeletedContext
---@return number total
---@return boolean all_succeeded
function M.emit_delete(ctx)
	return _emit("on_delete", ctx)
end

--- Register a callback for the `on_update` event.
---@param fn fun(ctx: BookmarkUpdatedContext)
---@return boolean success
function M.on_update(fn)
	return _on("on_update", fn)
end

--- Register a one-shot callback for the `on_update` event.
---@param fn fun(ctx: BookmarkUpdatedContext)
---@return boolean success
function M.once_update(fn)
	return _once("on_update", fn)
end

--- Unregister a callback from the `on_update` event.
---@param fn fun(ctx: BookmarkUpdatedContext)
---@return boolean success
function M.off_update(fn)
	return _off("on_update", fn)
end

--- Emit the `on_update` event to all registered callbacks.
---@param ctx BookmarkUpdatedContext
---@return number total
---@return boolean all_succeeded
function M.emit_update(ctx)
	return _emit("on_update", ctx)
end

--- Register a callback for the `on_navigation` event.
---@param fn fun(ctx: NavigationContext)
---@return boolean success
function M.on_navigation(fn)
	return _on("on_navigation", fn)
end

--- Register a one-shot callback for the `on_navigation` event.
---@param fn fun(ctx: NavigationContext)
---@return boolean success
function M.once_navigation(fn)
	return _once("on_navigation", fn)
end

--- Unregister a callback from the `on_navigation` event.
---@param fn fun(ctx: NavigationContext)
---@return boolean success
function M.off_navigation(fn)
	return _off("on_navigation", fn)
end

--- Emit the `on_navigation` event to all registered callbacks.
---@param ctx NavigationContext
---@return number total
---@return boolean all_succeeded
function M.emit_navigation(ctx)
	return _emit("on_navigation", ctx)
end

--- Register a callback for the `on_toggle` event.
---@param fn fun(ctx: ToggleContext)
---@return boolean success
function M.on_toggle(fn)
	return _on("on_toggle", fn)
end

--- Register a one-shot callback for the `on_toggle` event.
---@param fn fun(ctx: ToggleContext)
---@return boolean success
function M.once_toggle(fn)
	return _once("on_toggle", fn)
end

--- Unregister a callback from the `on_toggle` event.
---@param fn fun(ctx: ToggleContext)
---@return boolean success
function M.off_toggle(fn)
	return _off("on_toggle", fn)
end

--- Emit the `on_toggle` event to all registered callbacks.
---@param ctx ToggleContext
---@return number total
---@return boolean all_succeeded
function M.emit_toggle(ctx)
	return _emit("on_toggle", ctx)
end

--- Register a callback for the `on_toggle_all` event.
---@param fn fun(ctx: ToggleAllContext)
---@return boolean success
function M.on_toggle_all(fn)
	return _on("on_toggle_all", fn)
end

--- Register a one-shot callback for the `on_toggle_all` event.
---@param fn fun(ctx: ToggleAllContext)
---@return boolean success
function M.once_toggle_all(fn)
	return _once("on_toggle_all", fn)
end

--- Unregister a callback from the `on_toggle_all` event.
---@param fn fun(ctx: ToggleAllContext)
---@return boolean success
function M.off_toggle_all(fn)
	return _off("on_toggle_all", fn)
end

--- Emit the `on_toggle_all` event to all registered callbacks.
---@param ctx ToggleAllContext
---@return number total
---@return boolean all_succeeded
function M.emit_toggle_all(ctx)
	return _emit("on_toggle_all", ctx)
end

--- Register a callback for the `on_pre_save` event.
---@param fn fun(ctx: PreSaveContext)
---@return boolean success
function M.on_pre_save(fn)
	return _on("on_pre_save", fn)
end

--- Register a one-shot callback for the `on_pre_save` event.
---@param fn fun(ctx: PreSaveContext)
---@return boolean success
function M.once_pre_save(fn)
	return _once("on_pre_save", fn)
end

--- Unregister a callback from the `on_pre_save` event.
---@param fn fun(ctx: PreSaveContext)
---@return boolean success
function M.off_pre_save(fn)
	return _off("on_pre_save", fn)
end

--- Emit the `on_pre_save` event to all registered callbacks.
---@param ctx PreSaveContext
---@return number total
---@return boolean all_succeeded
function M.emit_pre_save(ctx)
	return _emit("on_pre_save", ctx)
end

--- Register a callback for the `on_post_save` event.
---@param fn fun(ctx: PostSaveContext)
---@return boolean success
function M.on_post_save(fn)
	return _on("on_post_save", fn)
end

--- Register a one-shot callback for the `on_post_save` event.
---@param fn fun(ctx: PostSaveContext)
---@return boolean success
function M.once_post_save(fn)
	return _once("on_post_save", fn)
end

--- Unregister a callback from the `on_post_save` event.
---@param fn fun(ctx: PostSaveContext)
---@return boolean success
function M.off_post_save(fn)
	return _off("on_post_save", fn)
end

--- Emit the `on_post_save` event to all registered callbacks.
---@param ctx PostSaveContext
---@return number total
---@return boolean all_succeeded
function M.emit_post_save(ctx)
	return _emit("on_post_save", ctx)
end

--- Register a callback for the `on_load` event.
---@param fn fun(ctx: LoadContext)
---@return boolean success
function M.on_load(fn)
	return _on("on_load", fn)
end

--- Register a one-shot callback for the `on_load` event.
---@param fn fun(ctx: LoadContext)
---@return boolean success
function M.once_load(fn)
	return _once("on_load", fn)
end

--- Unregister a callback from the `on_load` event.
---@param fn fun(ctx: LoadContext)
---@return boolean success
function M.off_load(fn)
	return _off("on_load", fn)
end

--- Emit the `on_load` event to all registered callbacks.
---@param ctx LoadContext
---@return number total
---@return boolean all_succeeded
function M.emit_load(ctx)
	return _emit("on_load", ctx)
end

--- Register a callback for the `on_restore` event.
---@param fn fun(ctx: RestoreContext)
---@return boolean success
function M.on_restore(fn)
	return _on("on_restore", fn)
end

--- Register a one-shot callback for the `on_restore` event.
---@param fn fun(ctx: RestoreContext)
---@return boolean success
function M.once_restore(fn)
	return _once("on_restore", fn)
end

--- Unregister a callback from the `on_restore` event.
---@param fn fun(ctx: RestoreContext)
---@return boolean success
function M.off_restore(fn)
	return _off("on_restore", fn)
end

--- Emit the `on_restore` event to all registered callbacks.
---@param ctx RestoreContext
---@return number total
---@return boolean all_succeeded
function M.emit_restore(ctx)
	return _emit("on_restore", ctx)
end

--- Register a callback for the `on_clear` event.
---@param fn fun(ctx: ClearContext)
---@return boolean success
function M.on_clear(fn)
	return _on("on_clear", fn)
end

--- Register a one-shot callback for the `on_clear` event.
---@param fn fun(ctx: ClearContext)
---@return boolean success
function M.once_clear(fn)
	return _once("on_clear", fn)
end

--- Unregister a callback from the `on_clear` event.
---@param fn fun(ctx: ClearContext)
---@return boolean success
function M.off_clear(fn)
	return _off("on_clear", fn)
end

--- Emit the `on_clear` event to all registered callbacks.
---@param ctx ClearContext
---@return number total
---@return boolean all_succeeded
function M.emit_clear(ctx)
	return _emit("on_clear", ctx)
end

--- Register a callback for the `on_clear_all` event.
---@param fn fun(ctx: ClearAllContext)
---@return boolean success
function M.on_clear_all(fn)
	return _on("on_clear_all", fn)
end

--- Register a one-shot callback for the `on_clear_all` event.
---@param fn fun(ctx: ClearAllContext)
---@return boolean success
function M.once_clear_all(fn)
	return _once("on_clear_all", fn)
end

--- Unregister a callback from the `on_clear_all` event.
---@param fn fun(ctx: ClearAllContext)
---@return boolean success
function M.off_clear_all(fn)
	return _off("on_clear_all", fn)
end

--- Emit the `on_clear_all` event to all registered callbacks.
---@param ctx ClearAllContext
---@return number total
---@return boolean all_succeeded
function M.emit_clear_all(ctx)
	return _emit("on_clear_all", ctx)
end

--- Register a callback for the `on_data_dir_change` event.
---@param fn fun(ctx: DataDirChangeContext)
---@return boolean success
function M.on_data_dir_change(fn)
	return _on("on_data_dir_change", fn)
end

--- Register a one-shot callback for the `on_data_dir_change` event.
---@param fn fun(ctx: DataDirChangeContext)
---@return boolean success
function M.once_data_dir_change(fn)
	return _once("on_data_dir_change", fn)
end

--- Unregister a callback from the `on_data_dir_change` event.
---@param fn fun(ctx: DataDirChangeContext)
---@return boolean success
function M.off_data_dir_change(fn)
	return _off("on_data_dir_change", fn)
end

--- Emit the `on_data_dir_change` event to all registered callbacks.
---@param ctx DataDirChangeContext
---@return number total
---@return boolean all_succeeded
function M.emit_data_dir_change(ctx)
	return _emit("on_data_dir_change", ctx)
end

--- Reset event handlers for testing purposes only
---@private
function M._reset_for_testing()
	event_handlers = {}
end

return M
