-- run with: :lua MiniDoc.generate() or :luafile scripts/minidoc.lua

local MiniDoc = require("mini.doc")
_G.MiniDoc = MiniDoc

-- define order for the docs
local files = {
	"lua/haunt/init.lua", -- Main module, introduction, TOC
	"lua/haunt/config.lua", -- Configuration options
	"lua/haunt/api.lua", -- Public API functions
	"lua/haunt/persistence.lua", -- Bookmark structure
	"lua/haunt/picker/init.lua", -- Picker integration
	"lua/haunt/sidekick.lua", -- Sidekick integration
	"plugin/haunt.lua", -- Commands
}

MiniDoc.generate(files, "doc/haunt.txt")
