---@toc_entry Picker Types
---@tag haunt-picker-types
---@text
--- # Picker Types ~
---
--- Shared type definitions for picker implementations.

---@class PickerItem
---@field idx number Index in the bookmark list
---@field score number Score for sorting (same as idx)
---@field file string Absolute file path
---@field relpath string Relative file path (cached)
---@field filename string Filename only (cached)
---@field pos number[] Position as {line, col}
---@field text string Formatted display text
---@field note string|nil Annotation text if present
---@field id string Unique bookmark identifier
---@field line number 1-based line number

---@class PickerModule
---@field show fun(opts?: table): boolean Show the picker
---@field is_available fun(): boolean Check if the picker backend is available
---@field set_picker_module fun(module: table) Set parent module reference for reopening

---@class PickerRouter
---@field show fun(opts?: table) Show the bookmark picker

---@class EditAnnotationContext
---@field item PickerItem The bookmark item to edit
---@field close_picker fun() Function to close the current picker
---@field reopen_picker fun() Function to reopen the picker after edit

return {}
