---@alias HauntEvent "on_create"|"on_delete"|"on_update"|"on_navigation"|"on_toggle"|"on_toggle_all"|"on_pre_save"|"on_post_save"|"on_load"|"on_restore"|"on_clear"|"on_clear_all"|"on_data_dir_change"

---@class HauntEvents
---@field on_create "on_create"
---@field on_delete "on_delete"
---@field on_update "on_update"
---@field on_navigation "on_navigation"
---@field on_toggle "on_toggle"
---@field on_toggle_all "on_toggle_all"
---@field on_pre_save "on_pre_save"
---@field on_post_save "on_post_save"
---@field on_load "on_load"
---@field on_restore "on_restore"
---@field on_clear "on_clear"
---@field on_clear_all "on_clear_all"
---@field on_data_dir_change "on_data_dir_change"

---@type HauntEvents
local M = {
	on_create = "on_create",
	on_delete = "on_delete",
	on_update = "on_update",
	on_navigation = "on_navigation",
	on_toggle = "on_toggle",
	on_toggle_all = "on_toggle_all",
	on_pre_save = "on_pre_save",
	on_post_save = "on_post_save",
	on_load = "on_load",
	on_restore = "on_restore",
	on_clear = "on_clear",
	on_clear_all = "on_clear_all",
	on_data_dir_change = "on_data_dir_change",
}

return M
