local M = {}


local function init()
	local Gopls     = require("gox.gopls")
	local gopls     = Gopls.new({}, "v0.21.1")
	local goplsPath = gopls:resolve_path()
	if goplsPath == "" then
		local msg = "Golang language server is not installed. Please install or provide alternate path."
		vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
			if choice == "Install" then
				gopls:ensure()
				init()
			end
		end)
		return
	end

	local Goxls     = require("gox.goxls")
	local gox     = Goxls.new({}, "v0.0.41")
	local goxPath = gox:resolve_path()
	if goxPath == "" then
		local msg = "GoX language server is not installed. Please install or provide alternate path."
		vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
			if choice == "Install" then
				gox:ensure()
				init()
			end
		end)
		return
	end

	vim.lsp.config('gox', {
		cmd = { goxPath, "srv", "-gopls", goplsPath },
		filetypes = { "go", "gomod", "gowork", "gosum", "gox" },
		root_markers = { "go.work", "go.mod", ".git" },
	})
	vim.lsp.enable('gox')
end

function M.setup(opts)
	init()
end

return M
