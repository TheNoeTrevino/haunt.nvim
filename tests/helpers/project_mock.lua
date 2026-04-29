--- Test helper for injecting fake project info into haunt.project.
---
--- haunt.project caches `{root, branch, project_id}` and exposes only
--- `get_info()` to production code. Tests need to control those values
--- without a real git repository, so this module pokes the cache via the
--- module's documented test-only seam (`project._test_set_info`).
---
--- Usage:
---     local project_mock = require("tests.helpers.project_mock")
---
---     project_mock.set({ root = "/tmp", branch = "main", project_id = "x" })
---     -- ... assertions ...
---     project_mock.restore()
---
--- Or scoped:
---     project_mock.with({ root = "/tmp", branch = "main", project_id = "x" }, function()
---       -- ... assertions ...
---     end)

local M = {}

---@param info ProjectInfo
function M.set(info)
	require("haunt.project")._test_set_info(info)
end

--- Drop the injected info; the next `get_info` call will shell out to git.
function M.restore()
	require("haunt.project").invalidate()
end

--- Run `fn` with the given project info injected, restoring on exit.
---@param info ProjectInfo
---@param fn fun()
function M.with(info, fn)
	M.set(info)
	local ok, err = pcall(fn)
	M.restore()
	if not ok then
		error(err)
	end
end

return M
