-- lua/haunt/root.lua
-- Project root detection with LazyVim integration

local M = {}

--- Get config with safe defaults
local function get_config()
	local ok, haunt_config = pcall(require, "haunt.config")
	if not ok or not haunt_config.options then
		-- Return safe defaults if config not available
		return {
			respect_lazyvim = true,
			respect_lsp = true,
			markers = {
				".git",
				".projectroot",
				"pyproject.toml",
				"Cargo.toml",
				"package.json",
				"go.mod",
				"Makefile",
			},
			custom_fn = nil,
		}
	end

	return haunt_config.options.root_detection
		or {
			respect_lazyvim = true,
			respect_lsp = true,
			markers = { ".git" },
			custom_fn = nil,
		}
end

--- Detect project root for a buffer
--- @param bufnr number Buffer number (0 for current)
--- @return string|nil root_dir The detected root directory (normalized with ~)
--- @return string method The detection method used
function M.detect(bufnr)
	bufnr = bufnr or 0
	local config = get_config()

	-- Priority 1: Custom function
	if config.custom_fn then
		local root = config.custom_fn(bufnr)
		if root then
			return M.normalize_path(root), "custom"
		end
	end

	-- Priority 2: LazyVim
	if config.respect_lazyvim and vim.g.root_spec then
		local root = M.detect_lazyvim(bufnr)
		if root then
			return M.normalize_path(root), "lazyvim"
		end
	end

	-- Priority 3: LSP
	if config.respect_lsp then
		local root = M.detect_lsp(bufnr)
		if root then
			return M.normalize_path(root), "lsp"
		end
	end

	-- Priority 4: Markers
	local root = M.detect_markers(bufnr, config.markers)
	if root then
		return M.normalize_path(root), "markers"
	end

	-- Priority 5: CWD fallback
	return M.normalize_path(vim.fn.getcwd()), "cwd"
end

--- Detect root using LazyVim's root detection
--- @param bufnr number Buffer number
--- @return string|nil root_dir
function M.detect_lazyvim(bufnr)
	local ok, lazyvim_util = pcall(require, "lazyvim.util")
	if not ok then
		return nil
	end

	local ok2, root = pcall(function()
		return lazyvim_util.root.get({ normalize = true })
	end)

	return ok2 and root or nil
end

--- Detect root using LSP
--- @param bufnr number Buffer number
--- @return string|nil root_dir
function M.detect_lsp(bufnr)
	-- Try new API first (Neovim 0.10+)
	local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
	if not ok then
		-- Fallback to old API
		clients = vim.lsp.get_active_clients({ bufnr = bufnr })
	end

	for _, client in ipairs(clients) do
		if client.config and client.config.root_dir then
			return client.config.root_dir
		end
	end

	return nil
end

--- Detect root using file markers
--- @param bufnr number Buffer number
--- @param markers table List of marker files/directories
--- @return string|nil root_dir
function M.detect_markers(bufnr, markers)
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" or filepath == nil then
		filepath = vim.fn.getcwd()
	else
		filepath = vim.fn.fnamemodify(filepath, ":p:h")
	end

	for _, marker in ipairs(markers) do
		-- Check for directory marker
		local dir = vim.fn.finddir(marker, filepath .. ";")
		if dir ~= "" then
			return vim.fn.fnamemodify(dir, ":p:h")
		end

		-- Check for file marker
		local file = vim.fn.findfile(marker, filepath .. ";")
		if file ~= "" then
			return vim.fn.fnamemodify(file, ":p:h")
		end
	end

	return nil
end

--- Normalize path: expand to absolute and replace home with ~
--- @param path string|nil Path to normalize
--- @return string|nil normalized_path
function M.normalize_path(path)
	if not path or path == "" then
		return nil
	end

	-- Expand to absolute path
	path = vim.fn.fnamemodify(path, ":p")

	-- Replace home directory with ~
	local home = vim.fn.expand("~")
	if vim.startswith(path, home) then
		path = "~" .. path:sub(#home + 1)
	end

	-- Remove trailing slash
	if path:sub(-1) == "/" then
		path = path:sub(1, -2)
	end

	return path
end

return M
