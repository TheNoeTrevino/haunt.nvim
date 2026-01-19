---@class UtilsModule
---@field normalize_filepath fun(path: string): string
---@field validate_buffer_for_bookmarks fun(bufnr: number): boolean, string|nil
---@field ensure_buffer_for_file fun(filepath: string): number|nil, string|nil

---@type UtilsModule
---@diagnostic disable-next-line: missing-fields
local M = {}

--- Normalize a file path to absolute form
--- Ensures consistent path representation for comparisons
---@param path string The file path to normalize
---@return string normalized_path The absolute file path
function M.normalize_filepath(path)
	if path == "" then
		return ""
	end
	return vim.fn.fnamemodify(path, ":p")
end

--- Validate that a buffer can have bookmarks
--- Checks for empty filepath, special buffers, buffer types, and modifiable status
---@param bufnr number Buffer number to validate
---@return boolean valid True if buffer can have bookmarks
---@return string|nil error_msg Error message if validation fails
function M.validate_buffer_for_bookmarks(bufnr)
	-- Check if buffer exists and is valid
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false, "Invalid buffer"
	end

	-- Get buffer filepath
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	-- Check if buffer has a name
	if filepath == "" then
		return false, "Cannot bookmark unnamed buffer"
	end

	-- Check buffer type (only normal files can have bookmarks)
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" then
		return false, "Cannot bookmark special buffers (terminal, help, etc.)"
	end

	-- Check if buffer is modifiable
	if not vim.bo[bufnr].modifiable then
		return false, "Cannot bookmark read-only buffer"
	end

	-- Check for special buffer schemes (term://, fugitive://, etc.)
	if filepath:match("^%w+://") then
		return false, "Cannot bookmark special buffers (protocol schemes)"
	end

	return true, nil
end

--- Ensure a buffer exists and is loaded for a file path
--- Creates the buffer if it doesn't exist and loads it
---@param filepath string The file path to get/create a buffer for
---@return number|nil bufnr The buffer number, or nil if failed
---@return string|nil error_msg Error message if validation fails
function M.ensure_buffer_for_file(filepath)
	local bufnr = vim.fn.bufnr(filepath)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(filepath)
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, "Failed to create buffer for file: " .. filepath
	end

	vim.fn.bufload(bufnr)

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil, "Failed to load buffer for file: " .. filepath
	end

	return bufnr, nil
end

return M
