--- Picker Integration for Haunt.nvim
---
--- This module implements a picker source for Snacks.nvim that displays all
--- bookmarks across files in the current repository/branch.
---
--- Features:
--- - Lists all bookmarks with file paths, line numbers, and annotations
--- - Jump to bookmarks with <CR>
--- - Delete bookmarks with the 'delete' action
--- - Edit bookmark annotations with the 'edit_annotation' action
--- - Automatically refreshes picker after modifications
--- - Handles cases where Snacks.nvim is not installed
---
--- Usage:
---   local picker = require('haunt.picker')
---   picker.show()  -- Opens the picker with all bookmarks
---
--- Integration with Snacks.nvim:
---   The picker uses Snacks.nvim's picker API to provide a consistent
---   user experience with other Snacks pickers. Items are formatted with
---   syntax highlighting and the picker supports custom actions.
---
---@class haunt.Picker
local M = {}

-- Constants for picker display
local LOCATION_WIDTH = 50 -- Width for file path and line number display
local NOTE_PREVIEW_LENGTH = 60 -- Maximum length for annotation preview

-- Required modules (loaded lazily)
local api = nil

--- Lazy load required modules
local function ensure_modules()
  if not api then
    api = require('haunt.api')
  end
end

--- Execute a callback with buffer context temporarily switched
--- Switches to the target buffer, sets cursor position, executes callback, then restores
---@param bufnr number Target buffer number
---@param line number Line number to set cursor to
---@param callback function Function to execute in the target buffer context
---@return any The return value of the callback
local function with_buffer_context(bufnr, line, callback)
  -- Save current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()
  local cursor_saved = vim.api.nvim_win_get_cursor(current_win)

  -- Temporarily switch to the target buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Move cursor to the bookmark line
  vim.api.nvim_win_set_cursor(current_win, { line, 0 })

  -- Execute the callback
  local result = callback()

  -- Restore cursor and buffer
  vim.api.nvim_set_current_buf(current_bufnr)
  if vim.api.nvim_buf_is_valid(current_bufnr) then
    vim.api.nvim_win_set_cursor(current_win, cursor_saved)
  end

  return result
end

--- Open the bookmark picker using Snacks.nvim
--- Displays all bookmarks with actions to open, delete, or edit annotations
---@return nil
function M.show()
  ensure_modules()

  -- Check if Snacks is available
  local ok, Snacks = pcall(require, 'snacks')
  if not ok then
    vim.notify('haunt.nvim: Snacks.nvim is not installed', vim.log.levels.ERROR)
    return
  end

  -- Get all bookmarks
  local bookmarks = api.get_bookmarks()

  if #bookmarks == 0 then
    vim.notify('haunt.nvim: No bookmarks found', vim.log.levels.INFO)
    return
  end

  -- Format bookmarks as picker items
  local items = {}
  for i, bookmark in ipairs(bookmarks) do
    table.insert(items, {
      idx = i,
      score = i,
      file = bookmark.file,
      line = bookmark.line,
      note = bookmark.note,
      text = string.format('%s:%d%s',
        vim.fn.fnamemodify(bookmark.file, ':~:.'),
        bookmark.line,
        bookmark.note and (' - ' .. bookmark.note) or ''
      ),
    })
  end

  -- Create picker with custom actions
  Snacks.picker({
    items = items,
    format = function(item)
      local ret = {}

      -- Get relative file path (relative to cwd)
      local relative_path = vim.fn.fnamemodify(item.file, ':~:.')

      -- Get file extension for icon lookup
      local extension = vim.fn.fnamemodify(item.file, ':e')

      -- Get icon and icon highlight using Snacks.util.icon
      -- This will work with both mini.icons and nvim-web-devicons
      local icon, icon_hl = Snacks.util.icon(extension, "filetype")

      -- Use a default file icon if none found
      if not icon or icon == "" then
        icon = "󰈔"
        icon_hl = "Normal"
      end

      -- Add icon with fixed width alignment (3 characters)
      ret[#ret + 1] = { Snacks.picker.util.align(icon, 3), icon_hl }
      ret[#ret + 1] = { " " }

      -- Format the file path with line number
      local location = string.format("%s:%d", relative_path, item.line)

      -- Add location with appropriate width and truncation
      ret[#ret + 1] = {
        Snacks.picker.util.align(location, LOCATION_WIDTH, { truncate = true }),
        "SnacksPickerFile"
      }

      -- Add annotation preview if it exists
      if item.note and item.note ~= "" then
        ret[#ret + 1] = { " " }

        -- Limit annotation preview to avoid overwhelming the display
        local note_preview = item.note
        if #note_preview > NOTE_PREVIEW_LENGTH then
          note_preview = note_preview:sub(1, NOTE_PREVIEW_LENGTH) .. "..."
        end

        ret[#ret + 1] = { note_preview, "SnacksPickerComment" }
      end

      return ret
    end,
    confirm = function(picker, item)
      if not item then return end
      picker:close()

      -- Open the file
      local bufnr = vim.fn.bufnr(item.file)
      if bufnr == -1 then
        -- File not loaded, open it
        vim.cmd('edit ' .. vim.fn.fnameescape(item.file))
      else
        -- File already loaded, switch to it
        vim.cmd('buffer ' .. bufnr)
      end

      -- Jump to the line
      vim.api.nvim_win_set_cursor(0, { item.line, 0 })

      -- Center the cursor
      vim.cmd('normal! zz')
    end,
    actions = {
      -- Delete bookmark action
      delete = function(picker, item)
        if not item then return end

        -- Open the file in a buffer if not already open
        local bufnr = vim.fn.bufnr(item.file)
        if bufnr == -1 then
          -- Create a temporary buffer for the file
          bufnr = vim.fn.bufadd(item.file)
          vim.fn.bufload(bufnr)
        end

        -- Use helper to execute toggle in the buffer context
        local success = with_buffer_context(bufnr, item.line, function()
          return api.toggle()
        end)

        if success then
          -- Refresh the picker to show updated list
          local updated_bookmarks = api.get_bookmarks()
          if #updated_bookmarks == 0 then
            -- Close picker if no bookmarks left
            picker:close()
            return
          end

          -- Update picker items
          local new_items = {}
          for i, bookmark in ipairs(updated_bookmarks) do
            table.insert(new_items, {
              idx = i,
              score = i,
              file = bookmark.file,
              line = bookmark.line,
              note = bookmark.note,
              text = string.format('%s:%d%s',
                vim.fn.fnamemodify(bookmark.file, ':~:.'),
                bookmark.line,
                bookmark.note and (' - ' .. bookmark.note) or ''
              ),
            })
          end

          picker.list.items = new_items
          picker:find()
        else
          vim.notify('haunt.nvim: Failed to delete bookmark', vim.log.levels.WARN)
        end
      end,

      -- Edit annotation action
      edit_annotation = function(picker, item)
        if not item then return end

        -- Prompt for new annotation
        local default_text = item.note or ''

        -- Close picker temporarily to show input prompt clearly
        picker:close()

        local annotation = vim.fn.input({
          prompt = 'Annotation: ',
          default = default_text,
        })

        -- If user cancelled (ESC), annotation will be empty string
        -- Only proceed if something was entered or if clearing existing annotation
        if annotation == '' and default_text == '' then
          -- User cancelled with no existing annotation, reopen picker
          M.show()
          return
        end

        -- Open the file in a buffer if not already open
        local bufnr = vim.fn.bufnr(item.file)
        if bufnr == -1 then
          bufnr = vim.fn.bufadd(item.file)
          vim.fn.bufload(bufnr)
        end

        -- Use helper to execute annotate in the buffer context
        with_buffer_context(bufnr, item.line, function()
          api.annotate(annotation)
        end)

        -- Reopen the picker with updated data
        M.show()
      end,
    },
  })
end

return M
