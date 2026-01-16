-- haunt.nvim plugin loader
-- This file is automatically sourced by Neovim when the plugin is installed

-- Prevent loading twice
if vim.g.loaded_haunt == 1 then
  return
end
vim.g.loaded_haunt = 1

-- Optional: Auto-setup with defaults for zero-config usage
-- Users can still call require('haunt').setup() with custom config to override
vim.defer_fn(function()
  -- Only auto-setup if user hasn't already called setup
  local haunt = require('haunt')

  -- Check if setup has already been called
  if not haunt.is_setup() then
    -- User hasn't called setup() yet, so initialize with defaults
    -- This ensures basic functionality works out of the box
    haunt.setup()
  end
end, 0)
