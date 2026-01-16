local M = {}

-- Module-level configuration
local config = nil

--- Default configuration
---@class HauntConfig
---@field sign string The icon to display for bookmarks (default: '󰃀')
---@field sign_hl string The highlight group for the sign text (default: 'DiagnosticInfo')
---@field virt_text_hl string The highlight group for virtual text annotations (default: 'Comment')
---@field data_dir string|nil Custom data directory path (default: vim.fn.stdpath("data") .. "/haunt/")
local DEFAULT_CONFIG = {
  sign = '󰃀',
  sign_hl = 'DiagnosticInfo',
  virt_text_hl = 'Comment',
  data_dir = nil, -- Will use default from persistence layer if nil
}

-- Check if any bookmarks exist
-- This prevents unnecessary writes when there are no bookmarks
local function has_bookmarks()
  -- Check if API module is loaded and has bookmarks
  local api = package.loaded['haunt.api']
  if not api then
    return false
  end

  local bookmarks = api.get_bookmarks and api.get_bookmarks() or {}
  return #bookmarks > 0
end

-- Save all bookmarks
local function save_all_bookmarks()
  if not has_bookmarks() then
    return
  end

  -- Call persistence layer's save function
  local api = require('haunt.api')
  if api.save then
    api.save()
  end
end

-- Debounce timer for saving bookmarks after text changes
local save_timer = nil
local SAVE_DEBOUNCE_DELAY = 500 -- milliseconds

-- Debounced save function for text change events
local function debounced_save()
  -- Cancel existing timer
  if save_timer then
    save_timer:stop()
    save_timer:close()
    save_timer = nil
  end

  -- Create new timer
  save_timer = vim.loop.new_timer()
  save_timer:start(SAVE_DEBOUNCE_DELAY, 0, vim.schedule_wrap(function()
    -- Clean up timer
    if save_timer then
      save_timer:close()
      save_timer = nil
    end

    -- Save bookmarks
    save_all_bookmarks()
  end))
end

-- Setup autocmds for auto-saving bookmarks
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("haunt_autosave", { clear = true })

  -- Save bookmarks when buffer is hidden
  vim.api.nvim_create_autocmd("BufHidden", {
    group = augroup,
    pattern = "*",
    callback = function()
      save_all_bookmarks()
    end,
    desc = "Auto-save bookmarks when buffer is hidden",
  })

  -- Save all bookmarks before Vim exits
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    pattern = "*",
    callback = function()
      -- Cancel and clean up any pending debounce timer
      if save_timer then
        save_timer:stop()
        save_timer:close()
        save_timer = nil
      end

      save_all_bookmarks()
    end,
    desc = "Auto-save all bookmarks before Vim exits",
  })

  -- Save bookmarks after text changes (debounced)
  -- This handles bookmark line updates when text is edited
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = augroup,
    pattern = "*",
    callback = function()
      debounced_save()
    end,
    desc = "Auto-save bookmarks after text changes (handles line updates)",
  })
end

-- Setup user commands
function M.setup_commands()
  local api = require('haunt.api')

  -- HauntToggle: Toggle bookmark at current line
  vim.api.nvim_create_user_command('HauntToggle', function()
    api.toggle()
  end, {
    desc = 'Toggle bookmark at current line',
  })

  -- HauntAnnotate: Add/edit annotation for bookmark at current line
  vim.api.nvim_create_user_command('HauntAnnotate', function()
    api.annotate()
  end, {
    desc = 'Add or edit annotation for bookmark at current line',
  })

  -- HauntList: Open the picker to list all bookmarks
  vim.api.nvim_create_user_command('HauntList', function()
    local picker = require('haunt.picker')
    picker.show()
  end, {
    desc = 'List all bookmarks using Snacks.nvim picker',
  })

  -- HauntClear: Clear bookmark at current line
  vim.api.nvim_create_user_command('HauntClear', function()
    api.clear()
  end, {
    desc = 'Clear all bookmarks in current file',
  })

  -- HauntClearAll: Clear all bookmarks
  vim.api.nvim_create_user_command('HauntClearAll', function()
    api.clear_all()
  end, {
    desc = 'Clear all bookmarks in the project',
  })

  -- HauntNext: Jump to next bookmark
  vim.api.nvim_create_user_command('HauntNext', function()
    api.next()
  end, {
    desc = 'Jump to next bookmark in current buffer',
  })

  -- HauntPrev: Jump to previous bookmark
  vim.api.nvim_create_user_command('HauntPrev', function()
    api.prev()
  end, {
    desc = 'Jump to previous bookmark in current buffer',
  })
end

--- Setup function for haunt.nvim
--- Initializes the plugin with user configuration
---@param opts? HauntConfig Optional configuration table
function M.setup(opts)
  opts = opts or {}

  -- Merge user config with defaults
  config = vim.tbl_deep_extend('force', DEFAULT_CONFIG, opts)

  -- Setup custom data directory if provided
  if config.data_dir then
    local persistence = require('haunt.persistence')
    persistence.set_data_dir(config.data_dir)
  end

  -- Setup display layer with sign configuration
  local display = require('haunt.display')
  display.setup_signs({
    sign = config.sign,
    sign_hl = config.sign_hl,
    virt_text_hl = config.virt_text_hl,
  })

  -- Setup display autocmds for sign updates
  display.setup_autocmds()

  -- Setup autocmds for auto-saving
  M.setup_autocmds()

  -- Setup user commands
  M.setup_commands()

  -- Load bookmarks from persistence
  local api = require('haunt.api')
  api.load()
end

--- Get the current configuration
---@return table config The current configuration
function M.get_config()
  if not config then
    return vim.deepcopy(DEFAULT_CONFIG)
  end
  return vim.deepcopy(config)
end

--- Check if setup has been called
---@return boolean True if setup was called, false otherwise
function M.is_setup()
  return config ~= nil
end

return M
