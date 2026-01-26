---@alias HauntEvent "onCreate"|"onDelete"|"onUpdate"|"onNavigation"

---@class HauntEvents
---@field onCreate "onCreate"
---@field onDelete "onDelete"
---@field onUpdate "onUpdate"
---@field onNavigation "onNavigation"

---@type HauntEvents
local M = {
	onCreate = "onCreate",
	onDelete = "onDelete",
	onUpdate = "onUpdate",
	onNavigation = "onNavigation",
}

return M
