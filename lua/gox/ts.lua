local M = {
	attached_gox = false
}

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


function M.health(cb)
	if not M.enabled then
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local ok, ts = pcall(require, "nvim-treesitter")
	if not ok then
		vim.notify(
			"GoX: nvim-treesitter is not installed. Install it or disable Tree-sitter in GoX config.",
			vim.log.levels.WARN
		)
		return
	end
	local installed = ts.get_installed()
	local missing = collect_missing(installed)
	if not M.attached_gox and not vim.tbl_contains(missing, "gox") then
		M.attached_gox = true
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "gox",
			callback = function(e)
				vim.treesitter.start(e.buf, "gox")
				if M.indent then
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
				if M.fold then
					vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
					vim.wo.foldmethod = 'expr'
					vim.wo.foldenable = true
					vim.wo.foldlevel = 99
					vim.wo.foldlevelstart = 99
				end
			end,
		})
	end
	if #missing == 0 then
		if type(cb) == "function" then
			cb()
		end
		return
	end
	local msg = ("GoX: Missing required Tree-sitter parsers: %s. Install now?"):format(table.concat(missing, ", "))
	vim.ui.select({ "Install", "Cancel" }, { prompt = msg }, function(choice)
		if choice == "Install" then
			ts.install(missing)
		else
			vim.notify(
				"GoX: Required Tree-sitter parsers were not installed. Tree-sitter features may be incomplete.",
				vim.log.levels.WARN
			)
		end
		if type(cb) == "function" then
			cb()
		end
	end)
end

function M.setup(opts)
	M.enabled = vim.tbl_get(opts, "treesitter", "enabled") ~= false
	M.indent = vim.tbl_get(opts, "treesitter", "indent") ~= false
	M.fold = vim.tbl_get(opts, "treesitter", "fold") ~= false
	local startGo = vim.tbl_get(opts, "treesitter", "start_go") == true
	if not M.enabled then
		return
	end
	vim.api.nvim_create_autocmd('User', {
		pattern = 'TSUpdate',
		callback = register
	})
	if startGo then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "go",
			callback = function(e)
				vim.treesitter.start(e.buf, "go")
				if M.indent then
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
				if M.fold then
					vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
					vim.wo.foldmethod = 'expr'
					vim.wo.foldenable = true
					vim.wo.foldlevel = 99
					vim.wo.foldlevelstart = 99
				end
			end,
		})
	end
	M.health()
end

return M
