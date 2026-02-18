local M = {}
local function has_parser()
	return #vim.api.nvim_get_runtime_file("parser/gox.*", false) > 0
end

function M.setup(opts)
	opts = opts or {}
	require("gox.treesitter").setup()
	if opts.lsp == nil or opts.lsp.enable ~= false then
		require("gox.lsp").setup(opts.lsp or {})
	end
end

return M
