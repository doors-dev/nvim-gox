local Tool = require("gox.tool").Tool

local Gopls = {}
Gopls.__index = Gopls
setmetatable(Gopls, { __index = Tool })

Gopls.name = "gopls"

function Gopls.new(opt, version)
  local self = Tool.new(opt, version)
  return setmetatable(self, Gopls)
end

function Gopls:install()
  local bin_dir = self:install_dir()
  self:run("go", { "install", "golang.org/x/tools/gopls@" .. self.version }, {
    GOBIN = bin_dir,
  })
end

return Gopls

