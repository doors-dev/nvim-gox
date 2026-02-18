local M = {}

local function register()
	local parsers = require("nvim-treesitter.parsers")
	parsers.gox = {
		install_info = {
			url = "https://github.com/doors-dev/tree-sitter-gox",
			files = { "src/parser.c", "src/scanner.c" },
			queries = "queries",
		},
	}
end

local required = { "go", "html", "css", "javascript", "gox" }
local function collect_missing(installed)
	local missing = {}
	for _, lang in ipairs(required) do
		if not vim.tbl_contains(installed, lang) then
			table.insert(missing, lang)
		end
	end
	return missing
end

function M.setup()
	if not pcall(require, "nvim-treesitter") then
		return
	end
	vim.api.nvim_create_autocmd('User', {
		pattern = 'TSUpdate',
		callback = register
	})
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "gox",
		callback = function(e)
			pcall(vim.treesitter.start, e.buf, "gox")
		end,
	})
	local ts = require("nvim-treesitter")
	local installed = ts.get_installed()
	local missing = collect_missing(installed)
	if #missing == 0 then
		return
	end
	local msg = ("Missing required Tree-sitter parsers: %s\nInstall now?"):format(table.concat(missing, ", "))
	vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
		if choice == "Install" then
			ts.install(missing)
		end
	end)
	vim.api.nvim_create_user_command("GoxTSInstall", function()
		local ts = require("nvim-treesitter")
		local installed = ts.get_installed()
		local missing = collect_missing(installed)
		if #missing == 0 then
			vim.notify("All required Tree-sitter parsers are already installed")
			return
		end
		ts.install(missing)
	end, {})
end

return M
