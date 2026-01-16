---@class haunt.Persistence
local M = {}

-- Module-level custom data directory configuration
local custom_data_dir = nil

--- Gets the git root directory for the current working directory
---@return string|nil git_root The git repository root path, or nil if not in a git repo
local function get_git_root()
  local git_dir = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return git_dir
end

--- Gets the current git branch name
---@return string|nil branch The current git branch name, or nil if not in a git repo
local function get_git_branch()
  -- Use --show-current which returns empty string for detached HEAD and repos with no commits
  -- This is more appropriate than --abbrev-ref HEAD which returns "HEAD" for detached state
  local branch = vim.fn.systemlist("git branch --show-current")[1]
  if vim.v.shell_error ~= 0 then
    return nil
  end
  -- Return nil for empty string (detached HEAD or no commits)
  if branch == "" then
    return nil
  end
  return branch
end

--- Set custom data directory
---@param dir string|nil Custom data directory path
function M.set_data_dir(dir)
  custom_data_dir = dir
end

--- Ensures the haunt data directory exists
---@return string data_dir The haunt data directory path
function M.ensure_data_dir()
  local data_dir = custom_data_dir or (vim.fn.stdpath("data") .. "/haunt/")
  vim.fn.mkdir(data_dir, "p")
  return data_dir
end

--- Get git repository information for the current working directory
--- @return { root: string|nil, branch: string|nil }
--- Returns a table with:
---   - root: absolute path to git repository root, or nil if not in a git repo
---   - branch: name of current branch, or nil if not in a git repo, detached HEAD, or no commits
function M.get_git_info()
  local result = {
    root = get_git_root(),
    branch = get_git_branch(),
  }
  return result
end

--- Generates a storage path for the current git repository and branch
--- Uses an 8-character SHA256 hash of "repo_root|branch" for the filename
---@return string|nil path The full path to the storage file, or nil if not in a git repo
function M.get_storage_path()
  local repo_root = get_git_root()
  if not repo_root then
    vim.notify("haunt.nvim: Not in a git repository", vim.log.levels.WARN)
    return nil
  end

  local branch = get_git_branch()
  if not branch then
    vim.notify("haunt.nvim: Could not determine git branch", vim.log.levels.WARN)
    return nil
  end

  -- Create hash key from repo_root and branch
  local key = repo_root .. "|" .. branch

  -- Generate 8-character hash using SHA256
  local hash = vim.fn.sha256(key):sub(1, 8)

  -- Ensure data directory exists
  local data_dir = M.ensure_data_dir()

  -- Return full path to storage file
  return data_dir .. hash .. ".json"
end

--- Save bookmarks to JSON file
---@param bookmarks table Array of bookmark tables to save
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return boolean success True if save was successful, false otherwise
function M.save_bookmarks(bookmarks, filepath)
  -- Validate input
  if type(bookmarks) ~= "table" then
    vim.notify("haunt.nvim: save_bookmarks: bookmarks must be a table", vim.log.levels.ERROR)
    return false
  end

  -- Get storage path
  local storage_path = filepath or M.get_storage_path()
  if not storage_path then
    vim.notify("haunt.nvim: save_bookmarks: could not determine storage path", vim.log.levels.ERROR)
    return false
  end

  -- Ensure storage directory exists
  M.ensure_data_dir()

  -- Create data structure with version
  local data = {
    version = 1,
    bookmarks = bookmarks
  }

  -- Encode to JSON
  local ok, json_str = pcall(vim.json.encode, data)
  if not ok then
    vim.notify("haunt.nvim: save_bookmarks: JSON encoding failed: " .. tostring(json_str), vim.log.levels.ERROR)
    return false
  end

  -- Write to file
  local write_ok = pcall(vim.fn.writefile, {json_str}, storage_path)
  if not write_ok then
    vim.notify("haunt.nvim: save_bookmarks: failed to write file: " .. storage_path, vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Load bookmarks from JSON file
---@param filepath? string Optional custom file path (defaults to git-based path)
---@return table bookmarks Array of bookmarks, or empty table if file doesn't exist or on error
function M.load_bookmarks(filepath)
  -- Get storage path
  local storage_path = filepath or M.get_storage_path()
  if not storage_path then
    vim.notify("haunt.nvim: load_bookmarks: could not determine storage path", vim.log.levels.WARN)
    return {}
  end

  -- Check if file exists
  if vim.fn.filereadable(storage_path) == 0 then
    -- File doesn't exist, return empty table (not an error)
    return {}
  end

  -- Read file
  local ok, lines = pcall(vim.fn.readfile, storage_path)
  if not ok then
    vim.notify("haunt.nvim: load_bookmarks: failed to read file: " .. storage_path, vim.log.levels.ERROR)
    return {}
  end

  -- Join lines into single string
  local json_str = table.concat(lines, "\n")

  -- Decode JSON
  local decode_ok, data = pcall(vim.json.decode, json_str)
  if not decode_ok then
    vim.notify("haunt.nvim: load_bookmarks: JSON decoding failed: " .. tostring(data), vim.log.levels.ERROR)
    return {}
  end

  -- Validate structure
  if type(data) ~= "table" then
    vim.notify("haunt.nvim: load_bookmarks: invalid data structure (not a table)", vim.log.levels.ERROR)
    return {}
  end

  -- Validate version field
  if not data.version then
    vim.notify("haunt.nvim: load_bookmarks: missing version field", vim.log.levels.WARN)
    return {}
  end

  -- Check version compatibility
  if data.version ~= 1 then
    vim.notify("haunt.nvim: load_bookmarks: unsupported version: " .. tostring(data.version), vim.log.levels.ERROR)
    return {}
  end

  -- Validate bookmarks field
  if type(data.bookmarks) ~= "table" then
    vim.notify("haunt.nvim: load_bookmarks: invalid bookmarks field (not a table)", vim.log.levels.ERROR)
    return {}
  end

  return data.bookmarks
end

--- Bookmark structure
--- @class Bookmark
--- @field file string Absolute path to file
--- @field line number 1-based line number
--- @field note string|nil Optional annotation text
--- @field id string Unique bookmark identifier
--- @field extmark_id number|nil Extmark ID for line tracking

--- Create a new bookmark
--- @param file string Absolute path to the file
--- @param line number 1-based line number
--- @param note? string Optional annotation text
--- @return Bookmark bookmark A new bookmark table
function M.create_bookmark(file, line, note)
  -- Validate inputs
  assert(type(file) == "string" and file ~= "", "file must be a non-empty string")
  assert(type(line) == "number" and line >= 1, "line must be a positive number")
  assert(note == nil or type(note) == "string", "note must be nil or a string")

  -- Generate unique ID using SHA256 hash of file + line + timestamp
  local timestamp = tostring(vim.loop.hrtime())
  local id_key = file .. tostring(line) .. timestamp
  local id = vim.fn.sha256(id_key):sub(1, 16) -- 16 chars for uniqueness

  return {
    file = file,
    line = line,
    note = note,
    id = id,
    extmark_id = nil, -- Will be set by display layer
  }
end

--- Validate a bookmark structure
--- @param bookmark any The value to validate
--- @return boolean valid True if the bookmark structure is valid
function M.is_valid_bookmark(bookmark)
  -- Check that bookmark is a table
  if type(bookmark) ~= "table" then
    return false
  end

  -- Check required fields
  if type(bookmark.file) ~= "string" or bookmark.file == "" then
    return false
  end

  if type(bookmark.line) ~= "number" or bookmark.line < 1 then
    return false
  end

  if type(bookmark.id) ~= "string" or bookmark.id == "" then
    return false
  end

  -- Check optional fields (if present, must be correct type)
  if bookmark.note ~= nil and type(bookmark.note) ~= "string" then
    return false
  end

  if bookmark.extmark_id ~= nil and type(bookmark.extmark_id) ~= "number" then
    return false
  end

  return true
end

return M
