---@toc_entry Commands
---@tag haunt-commands
---@text
--- # Commands ~
---
--- haunt.nvim provides the following user commands:
---
--- `:HauntToggle` - Toggle bookmark annotation visibility
--- `:HauntAnnotate [text]` - Add or edit annotation for bookmark at cursor
--- `:HauntDelete` - Delete bookmark at current line
--- `:HauntNext` - Jump to next bookmark
--- `:HauntPrev` - Jump to previous bookmark
--- `:HauntList` - Open interactive picker to browse all bookmarks
--- `:HauntClear` - Clear all bookmarks in current buffer
--- `:HauntClearAll` - Clear all bookmarks across all files
---

-- haunt.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is installed

-- Prevent loading twice
if vim.g.loaded_haunt == 1 then
  return
end
vim.g.loaded_haunt = 1

-- Create lightweight command wrappers that lazy-load on use
local commands = {
  HauntToggle = { fn = 'toggle', desc = 'Toggle bookmark annotation visibility' },
  HauntAnnotate = { fn = 'annotate', desc = 'Add/edit annotation', has_args = true },
  HauntClear = { fn = 'clear', desc = 'Clear bookmarks in current file' },
  HauntClearAll = { fn = 'clear_all', desc = 'Clear all bookmarks' },
  HauntNext = { fn = 'next', desc = 'Jump to next bookmark' },
  HauntPrev = { fn = 'prev', desc = 'Jump to previous bookmark' },
  HauntDelete = { fn = 'delete', desc = 'Delete bookmark at current line' },
}

for name, info in pairs(commands) do
  vim.api.nvim_create_user_command(name, function(opts)
    if info.has_args and opts.args ~= "" then
      require('haunt.api')[info.fn](opts.args)
    else
      require('haunt.api')[info.fn]()
    end
  end, { desc = info.desc, nargs = info.has_args and '?' or 0 })
end

-- Special case for HauntList (uses picker)
vim.api.nvim_create_user_command('HauntList', function()
  require('haunt.picker').show()
end, { desc = 'List all bookmarks' })

-- Deferred restoration setup (only if bookmarks exist)
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      local haunt = require('haunt')
      if haunt._has_potential_bookmarks() then
        haunt._setup_restoration_autocmd()
      end
    end)
  end,
})
