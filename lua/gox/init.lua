local M = {}
local function has_parser()
	return #vim.api.nvim_get_runtime_file("parser/gox.*", false) > 0
end

function M.setup(opts)
	opts = opts or {}
	local ts = require("gox.ts")
	local lsp = require("gox.lsp")
	ts.setup(opts)
	lsp.setup(opts)
	vim.api.nvim_create_user_command("GoxHealth", function()
		ts.health(function()
			lsp.health(function()
				vim.notify("GoX: Health check complete.", vim.log.levels.INFO)
			end)
		end)
	end, {})
end

return M
