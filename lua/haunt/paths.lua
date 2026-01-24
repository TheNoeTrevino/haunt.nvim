-- lua/haunt/paths.lua
-- Path conversion utilities for relative/absolute paths

local M = {}

--- Convert absolute path to relative (from project root)
--- @param absolute_path string Absolute file path
--- @param project_root string|nil Project root directory
--- @return string relative_path Path relative to project root, or normalized absolute
function M.to_relative(absolute_path, project_root)
	if not absolute_path then
		return ""
	end

	if not project_root then
		return M.normalize_home(absolute_path)
	end

	-- Expand both paths to absolute
	absolute_path = vim.fn.fnamemodify(absolute_path, ":p")
	project_root = vim.fn.fnamemodify(M.expand_home(project_root), ":p")

	-- Check if file is within project
	if vim.startswith(absolute_path, project_root) then
		local relative = absolute_path:sub(#project_root + 1)

		-- Remove leading slash
		if relative:sub(1, 1) == "/" or relative:sub(1, 1) == "\\" then
			relative = relative:sub(2)
		end

		return relative
	end

	-- File outside project - return normalized absolute
	return M.normalize_home(absolute_path)
end

--- Convert relative path to absolute
--- @param relative_path string Relative or absolute path
--- @param project_root string|nil Project root directory
--- @return string absolute_path Absolute file path
function M.to_absolute(relative_path, project_root)
	if not relative_path or relative_path == "" then
		return ""
	end

	-- Already absolute (starts with / or ~ or C:\ on Windows)
	if relative_path:sub(1, 1) == "/" or relative_path:sub(1, 1) == "~" or relative_path:match("^%a:") then -- Windows drive letter
		return vim.fn.fnamemodify(M.expand_home(relative_path), ":p")
	end

	-- Relative to project root
	if project_root then
		local full_path = M.expand_home(project_root) .. "/" .. relative_path
		return vim.fn.fnamemodify(full_path, ":p")
	end

	-- No project root, treat as relative to cwd
	return vim.fn.fnamemodify(relative_path, ":p")
end

--- Replace /home/user or /Users/user with ~
--- @param path string Path to normalize
--- @return string normalized_path
function M.normalize_home(path)
	if not path or path == "" then
		return ""
	end

	local home = vim.fn.expand("~")
	if vim.startswith(path, home) then
		return "~" .. path:sub(#home + 1)
	end

	return path
end

--- Expand ~ to full home path
--- @param path string Path that may contain ~
--- @return string expanded_path
function M.expand_home(path)
	if not path or path == "" then
		return ""
	end

	if path:sub(1, 1) == "~" then
		return vim.fn.expand("~") .. path:sub(2)
	end

	return path
end

--- Check if file exists
--- @param path string File path to check
--- @return boolean exists
function M.file_exists(path)
	if not path or path == "" then
		return false
	end

	local expanded = M.expand_home(path)
	return vim.fn.filereadable(expanded) == 1
end

--- Normalize path separators (for cross-platform compatibility)
--- @param path string Path to normalize
--- @return string normalized_path
function M.normalize_separators(path)
	if not path then
		return ""
	end

	-- Convert backslashes to forward slashes
	return path:gsub("\\", "/")
end

return M
