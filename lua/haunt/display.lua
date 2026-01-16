---@class haunt.Display
local M = {}

-- Create namespace for haunt extmarks
M.namespace = vim.api.nvim_create_namespace('haunt')

--- Display configuration stored at module level
---@type table|nil
local display_config = nil

--- Default display configuration
---@class DisplayConfig
---@field sign string The icon to display for bookmarks (default: '󰃀')
---@field sign_hl string The highlight group for the sign text (default: 'DiagnosticInfo')
---@field virt_text_hl string The highlight group for virtual text annotations (default: 'Comment')
---@field line_hl string|nil The highlight group for the entire line (default: nil)
local DEFAULT_CONFIG = {
  sign = '󰃀',
  sign_hl = 'DiagnosticInfo',
  virt_text_hl = 'Comment',
  line_hl = nil,
}

--- Setup bookmark signs with vim.fn.sign_define()
--- Creates a "HauntBookmark" sign that can be reused for all bookmarks
---@param config? DisplayConfig Optional configuration table
---@return nil
function M.setup_signs(config)
  -- Merge user config with defaults
  config = config or {}
  display_config = vim.tbl_deep_extend('force', DEFAULT_CONFIG, config)

  -- Define the HauntBookmark sign
  -- This sign will be reused for all bookmarks in the plugin
  vim.fn.sign_define('HauntBookmark', {
    text = display_config.sign,
    texthl = display_config.sign_hl,
    linehl = display_config.line_hl or '',
  })
end

--- Get the current display configuration
---@return table config The current display configuration
function M.get_config()
  if not display_config then
    -- If setup_signs hasn't been called, return default config
    return vim.deepcopy(DEFAULT_CONFIG)
  end
  return vim.deepcopy(display_config)
end

--- Check if signs have been initialized
---@return boolean initialized True if setup_signs has been called
function M.is_initialized()
  return display_config ~= nil
end

--- Show annotation as virtual text at the end of a line
--- @param bufnr number Buffer number
--- @param line number 1-based line number
--- @param note string The annotation text to display
--- @return number extmark_id The ID of the created extmark
function M.show_annotation(bufnr, line, note)
  -- Get the configured highlight or use default
  local config = M.get_config()
  local hl_group = config.virt_text_hl or 'Comment'

  -- nvim_buf_set_extmark uses 0-based line numbers
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line - 1, 0, {
    virt_text = {{ " " .. note, hl_group }},
    virt_text_pos = "eol",
  })

  return extmark_id
end

--- Hide annotation by removing the extmark
--- @param bufnr number Buffer number
--- @param extmark_id number The extmark ID to remove
---@return boolean success True if hiding was successful, false otherwise
function M.hide_annotation(bufnr, extmark_id)
  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Try to delete extmark (may fail if extmark doesn't exist, which is OK)
  local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, extmark_id)
  return ok
end

--- Set a bookmark extmark for line tracking
--- Creates an extmark at the bookmark's line that will automatically move with text edits
--- This extmark is separate from the annotation extmark and is used purely for line tracking
---@param bufnr number Buffer number where the bookmark is located
---@param bookmark Bookmark The bookmark data structure
---@return number|nil extmark_id The created extmark ID, or nil if creation failed
function M.set_bookmark_mark(bufnr, bookmark)
  -- Validate inputs
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("haunt.nvim: set_bookmark_mark: invalid buffer number", vim.log.levels.ERROR)
    return nil
  end

  if type(bookmark) ~= "table" or type(bookmark.line) ~= "number" then
    vim.notify("haunt.nvim: set_bookmark_mark: invalid bookmark structure", vim.log.levels.ERROR)
    return nil
  end

  -- Convert from 1-based to 0-based indexing for nvim_buf_set_extmark
  local line = bookmark.line - 1

  -- Check if line is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line < 0 or line >= line_count then
    vim.notify(
      string.format("haunt.nvim: set_bookmark_mark: line %d out of bounds (buffer has %d lines)",
        bookmark.line, line_count),
      vim.log.levels.ERROR
    )
    return nil
  end

  -- Create extmark with right_gravity=false so it stays at the beginning of the line
  -- even when text is inserted at the start of the line
  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, line, 0, {
    -- Track line movements automatically
    right_gravity = false,
    -- This extmark is invisible - it's only for tracking the line position
  })

  if not ok then
    vim.notify(
      string.format("haunt.nvim: set_bookmark_mark: failed to create extmark: %s", tostring(extmark_id)),
      vim.log.levels.ERROR
    )
    return nil
  end

  return extmark_id
end

--- Get the current line number for an extmark
--- Queries the extmark position to find where it has moved to
--- This allows bookmarks to stay synced with the buffer as text is edited
---@param bufnr number Buffer number where the extmark is located
---@param extmark_id number The extmark ID to query
---@return number|nil line The current 1-based line number, or nil if extmark not found
function M.get_extmark_line(bufnr, extmark_id)
  -- Validate inputs
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("haunt.nvim: get_extmark_line: invalid buffer number", vim.log.levels.ERROR)
    return nil
  end

  if type(extmark_id) ~= "number" then
    vim.notify("haunt.nvim: get_extmark_line: invalid extmark ID", vim.log.levels.ERROR)
    return nil
  end

  -- Query extmark position
  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, M.namespace, extmark_id, {})

  if not ok then
    -- Extmark not found or other error
    return nil
  end

  -- pos is a tuple {row, col} where row is 0-indexed
  -- Convert to 1-based line number
  if type(pos) == "table" and type(pos[1]) == "number" then
    return pos[1] + 1
  end

  return nil
end

--- Delete a bookmark extmark
--- Removes the extmark from the buffer when a bookmark is deleted
---@param bufnr number Buffer number where the extmark is located
---@param extmark_id number The extmark ID to delete
---@return boolean success True if deletion was successful, false otherwise
function M.delete_bookmark_mark(bufnr, extmark_id)
  -- Validate inputs
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("haunt.nvim: delete_bookmark_mark: invalid buffer number", vim.log.levels.ERROR)
    return false
  end

  if type(extmark_id) ~= "number" then
    vim.notify("haunt.nvim: delete_bookmark_mark: invalid extmark ID", vim.log.levels.ERROR)
    return false
  end

  -- Delete the extmark
  local ok = pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, extmark_id)

  if not ok then
    vim.notify(
      string.format("haunt.nvim: delete_bookmark_mark: failed to delete extmark %d", extmark_id),
      vim.log.levels.WARN
    )
    return false
  end

  return true
end

--- Clear all bookmark extmarks from a buffer
--- Useful when reloading bookmarks or clearing all bookmarks
---@param bufnr number Buffer number to clear extmarks from
---@return boolean success True if clearing was successful, false otherwise
function M.clear_buffer_marks(bufnr)
  -- Validate input
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("haunt.nvim: clear_buffer_marks: invalid buffer number", vim.log.levels.ERROR)
    return false
  end

  -- Clear all extmarks in the namespace for this buffer
  local ok = pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)

  if not ok then
    vim.notify("haunt.nvim: clear_buffer_marks: failed to clear extmarks", vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Sign group name for organizing haunt signs
local SIGN_GROUP = "haunt_signs"

-- Debounce timers per buffer
local debounce_timers = {}

-- Debounce delay in milliseconds
local DEBOUNCE_DELAY = 100

--- Place a sign at a specific line in a buffer
---@param bufnr number Buffer number
---@param line number 1-based line number
---@param sign_id number Unique sign ID
function M.place_sign(bufnr, line, sign_id)
  vim.fn.sign_place(
    sign_id,
    SIGN_GROUP,
    "HauntBookmark",
    bufnr,
    { lnum = line, priority = 10 }
  )
end

--- Remove a sign from a buffer
---@param bufnr number Buffer number
---@param sign_id number Sign ID to remove
function M.unplace_sign(bufnr, sign_id)
  vim.fn.sign_unplace(SIGN_GROUP, {
    buffer = bufnr,
    id = sign_id
  })
end

--- Update bookmark signs based on current extmark positions
--- This is now a simple wrapper that delegates to the API layer
--- The API layer owns the synchronization logic to avoid circular dependencies
---@param bufnr number Buffer number
function M.update_bookmark_signs(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Delegate to API layer for synchronization
  local api = require('haunt.api')
  api.sync_extmark_positions(bufnr)
end

--- Get bookmarks for a specific buffer
--- Retrieves all bookmarks and filters them by buffer filepath
---@param bufnr number Buffer number
---@return table bookmarks Array of bookmarks for the buffer
local function get_buffer_bookmarks(bufnr)
  -- Validate buffer
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  -- Get buffer filepath (normalized to absolute)
  local filepath = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
  if filepath == "" then
    return {}
  end

  -- Get all bookmarks from API
  local api = require('haunt.api')
  local all_bookmarks = api.get_bookmarks()

  -- Filter bookmarks for this buffer
  local buffer_bookmarks = {}
  for _, bookmark in ipairs(all_bookmarks) do
    if bookmark.file == filepath then
      table.insert(buffer_bookmarks, bookmark)
    end
  end

  return buffer_bookmarks
end

--- Debounced update function
--- Cancels previous timer and schedules a new update
---@param bufnr number Buffer number
local function debounced_update(bufnr)
  -- Cancel existing timer for this buffer
  if debounce_timers[bufnr] then
    debounce_timers[bufnr]:stop()
    debounce_timers[bufnr]:close()
    debounce_timers[bufnr] = nil
  end

  -- Create new timer
  debounce_timers[bufnr] = vim.loop.new_timer()

  debounce_timers[bufnr]:start(DEBOUNCE_DELAY, 0, vim.schedule_wrap(function()
    -- Check if buffer is still valid
    if not vim.api.nvim_buf_is_valid(bufnr) then
      -- Clean up timer
      if debounce_timers[bufnr] then
        debounce_timers[bufnr]:close()
        debounce_timers[bufnr] = nil
      end
      return
    end

    -- Clean up timer
    if debounce_timers[bufnr] then
      debounce_timers[bufnr]:close()
      debounce_timers[bufnr] = nil
    end

    -- Update signs
    M.update_bookmark_signs(bufnr)
  end))
end

--- Setup autocmds for sign updates on text changes
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("haunt_sign_updates", { clear = true })

  -- Update signs on text changes (normal mode)
  vim.api.nvim_create_autocmd("TextChanged", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      debounced_update(args.buf)
    end,
    desc = "Update haunt bookmark signs on text changes"
  })

  -- Update signs on text changes (insert mode)
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      debounced_update(args.buf)
    end,
    desc = "Update haunt bookmark signs on text changes in insert mode"
  })

  -- Clean up timers when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      if debounce_timers[args.buf] then
        debounce_timers[args.buf]:stop()
        debounce_timers[args.buf]:close()
        debounce_timers[args.buf] = nil
      end
    end,
    desc = "Clean up haunt debounce timers on buffer delete"
  })
end

return M
