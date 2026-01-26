---@toc_entry Hook Registry
---@tag haunt-hooks
---@text
--- # Hook Registry ~
---
--- The hook registry allows external plugins and users to listen to
--- bookmark lifecycle events. Register callbacks to react when bookmarks
--- are created, deleted, updated, or navigated.
---
--- Available events (from `require("haunt.hook_events")`):
--- - `onCreate`: fired after a bookmark is successfully created
--- - `onDelete`: fired after a bookmark is successfully deleted
--- - `onUpdate`: fired after a bookmark annotation is updated
--- - `onNavigation`: fired after jumping to a bookmark via next/prev
---
--- Example:
--- >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---
---   hooks.register(events.onCreate, function(ctx)
---     print("Created bookmark:", ctx.bookmark.id)
---   end)
--- <

---@class HooksModule
---@field on fun(event: HauntEvent, fn: fun(ctx: table)): boolean
---@field off fun(event: HauntEvent, fn: fun(ctx: table)): boolean
---@field once fun(event: HauntEvent, fn: fun(ctx: table)): boolean
---@field clear fun(event: HauntEvent): number
---@field has fun(event: HauntEvent): boolean
---@field list fun(event: HauntEvent): fun(ctx: table)[]
---@field emit fun(event: HauntEvent, ctx: table): number, boolean
---@field _reset_for_testing fun()

---@class BookmarkCreatedContext
---@field bookmark Bookmark
---@field bufnr number
---@field file string
---@field line number

---@class BookmarkDeletedContext
---@field bookmark Bookmark
---@field bufnr number
---@field file string
---@field line number

---@class BookmarkUpdatedContext
---@field bookmark Bookmark
---@field bufnr number
---@field old_note string|nil
---@field new_note string|nil
---@field old_group string|nil
---@field new_group string|nil
---@field old_tags string[]|nil
---@field new_tags string[]|nil

---@class NavigationContext
---@field bookmark Bookmark
---@field bufnr number
---@field direction "next"|"prev"
---@field from_line number
---@field to_line number

---@type HooksModule
---@diagnostic disable-next-line: missing-fields
local M = {}

---@private
---@type table<HauntEvent, function[]>
local event_handlers = {}

--- Register a callback for a bookmark lifecycle event.
---
--- Callbacks receive a context table with event-specific data.
--- Callbacks are wrapped in pcall - errors won't break core functionality.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@param fn fun(ctx: table) Callback function receiving context table
---@return boolean success True if callback was registered successfully
---
---@usage >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---   hooks.register(events.onCreate, function(ctx)
---     print("Bookmark at " .. ctx.file .. ":" .. ctx.line)
---   end)
--- <
function M.on(event, fn)
	if type(fn) ~= "function" then
		vim.notify("haunt.hooks: must register a function", vim.log.levels.ERROR)
		return false
	end
	event_handlers[event] = event_handlers[event] or {}
	table.insert(event_handlers[event], fn)
	return true
end

--- Register a callback that runs only once, then removes itself.
---
--- The callback will be invoked the first time the event fires,
--- then automatically unregistered. Useful for one-time setup or
--- initialization logic.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@param fn fun(ctx: table) Callback function receiving context table
---@return boolean success True if callback was registered successfully
---
---@usage >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---   hooks.once(events.onCreate, function(ctx)
---     print("First bookmark created!")
---   end)
--- <
function M.once(event, fn)
	if type(fn) ~= "function" then
		vim.notify("haunt.hooks: must register a function", vim.log.levels.ERROR)
		return false
	end

	local wrapper
	wrapper = function(ctx)
		fn(ctx)
		M.off(event, wrapper)
	end

	return M.on(event, wrapper)
end

--- Unregister a previously registered callback.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@param fn function The exact function reference that was registered
---@return boolean success True if the callback was found and removed
---
---@usage >lua
---   local events = require("haunt.hook_events")
---   local my_callback = function(ctx) ... end
---   hooks.register(events.onCreate, my_callback)
---   hooks.unregister(events.onCreate, my_callback)
--- <
function M.off(event, fn)
	if not event_handlers[event] then
		vim.notify("haunt.hooks: function not found in hooks", vim.log.levels.INFO)
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

--- Remove all callbacks registered for an event.
---
--- Clears all listeners for the specified event. Useful for cleanup,
--- reloads, or resetting event handlers.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@return number count Number of callbacks that were removed
---
---@usage >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---   local removed = hooks.clear(events.onCreate)
---   print("Removed " .. removed .. " callbacks")
--- <
function M.clear(event)
	local count = 0
	if event_handlers[event] then
		count = #event_handlers[event]
		event_handlers[event] = nil
	end
	return count
end

--- Check whether an event has any registered callbacks.
---
--- Returns true if at least one callback is registered for the event,
--- false otherwise.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@return boolean has_callbacks True if event has registered callbacks
---
---@usage >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---   if hooks.has(events.onCreate) then
---     print("onCreate has listeners")
---   end
--- <
function M.has(event)
	return event_handlers[event] ~= nil and #event_handlers[event] > 0
end

--- Get all callbacks registered for an event.
---
--- Returns a reference to the callback table for the event.
--- Useful for debugging, introspection, or tooling.
---
--- Note: This returns a direct reference to the event_handlers.
--- Modifying the returned table will affect the hook system.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@return fun(ctx: table)[] callbacks Array of registered callback functions
---
---@usage >lua
---   local hooks = require("haunt.hooks")
---   local events = require("haunt.hook_events")
---   local callbacks = hooks.list(events.onCreate)
---   print("onCreate has " .. #callbacks .. " callbacks")
--- <
function M.list(event)
	return event_handlers[event] or {}
end

--- Emit an event to all registered callbacks.
---
--- This is called internally by haunt.nvim at lifecycle points.
--- User callbacks are wrapped in pcall to prevent errors from
--- breaking core functionality.
---
---@param event HauntEvent Event from require("haunt.hook_events")
---@param ctx table Context data passed to callbacks
---@return number total Total number of callbacks invoked
---@return boolean all_succeeded True if all callbacks succeeded without errors
function M.emit(event, ctx)
	if not event_handlers[event] then
		return 0, true
	end
	local total = 0
	local all_succeeded = true
	for _, fn in ipairs(event_handlers[event]) do
		total = total + 1
		local ok, err = pcall(fn, ctx)
		if not ok then
			all_succeeded = false
			vim.notify("haunt.nvim: hook error with event [" .. event .. "]: \n" .. tostring(err), vim.log.levels.WARN)
		end
	end
	return total, all_succeeded
end

--- Reset event handlers for testing purposes only
---@private
function M._reset_for_testing()
	event_handlers = {}
end

return M
