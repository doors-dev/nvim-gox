local M = {}
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
