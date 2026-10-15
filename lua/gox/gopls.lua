local Tool = require("gox.tool").Tool

local Gopls = {}
Gopls.__index = Gopls
setmetatable(Gopls, { __index = Tool })

Gopls.name = "gopls"

function Gopls.new(opt, version)
  local self = Tool.new(opt, version)
  return setmetatable(self, Gopls)
end

function Gopls:install(dir)
  local go = vim.fn.expand(self.opt.bin.go or "go")
  self:run(go, { "install", "golang.org/x/tools/gopls@" .. self.version }, {
    GOBIN = dir,
  })
end

return Gopls

