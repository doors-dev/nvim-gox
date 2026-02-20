# nvim-gox

Neovim support for **GoX**: Tree-sitter highlighting and GoX language-server integration for completion, diagnostics, go-to-definition, and refactors across both `.gox` and `.go` buffers.

## Features

- **Filetype**
  - Detects `*.gox` and sets `filetype=gox`.
- **LSP**
  - Configures and starts the GoX language server for `.gox` and `.go`.
- **Tree-sitter**
  - Installs/configures the `gox` Tree-sitter parser (and any required dependent parsers).

## Requirements

- Neovim **0.11.0+**
- `nvim-treesitter` on the **main** branch
- `git`
- `curl` or `wget` (Windows: PowerShell)
- `tar` for `.tar.gz` archives (Windows: PowerShell)
- `go`

> GoX proxies `gopls` functionality for both `.go` and `.gox` files, so any standalone `gopls` client must be disabled.

## How it works

On startup, the plugin can run a health check that:

1. Ensures required Tree-sitter parsers are installed (unless disabled).
2. Ensures `gox` and `gopls` are installed at the required versions (unless disabled or custom binaries are provided).
3. Enables the parser and language server.

> Actions are always confirmed before applying changes.  
> Language servers are installed into the plugin’s own directory.

## Commands

- `:GoxHealth` — run the health check.

## Installation and settings

### lazy.nvim

```lua
{
  "doors-dev/nvim-gox",
  config = function()
    -- setup is required
    require("gox").setup({
      -- everything is optional
      treesitter = {
        -- enable Tree-sitter setup (default: true)
        enabled = true,
        -- attach Tree-sitter to .go files (default: false)
        -- enable if you don't already have Go highlighting configured
        start_go = true,
      },
      lsp = {
        -- enable LSP setup (default: true)
        enabled = true,
      },
      -- override binaries (defaults to ones installed in the plugin directory)
      bin = {
        gox = "gox",
        go  = "go",
      },
    })
  end,
}
```

## Troubleshooting

- **You see a message about disabling standalone `gopls`**
  - GoX stops any separately configured `gopls` client because GoX runs `gopls` internally.
  - Disable your standalone `gopls` setup to avoid the message and duplicate configuration.

- **GoX can’t download/install tools**
  - Ensure you have: `git`, `curl`/`wget` (or PowerShell on Windows), and `tar`/`unzip` as appropriate.
  - Alternatively, set `opts.bin.gox` / `opts.bin.gopls` to use your system binaries.

- **Unsupported platform/arch for GoX release**
  - The built-in installer only supports: `linux/darwin/windows` and `amd64/arm64`.
  - Install `gox` manually and point `opts.bin.gox` at it.

## Related projects

- [GoX language server and library](https://github.com/doors-dev/gox)
- [Tree-sitter grammar](https://github.com/doors-dev/tree-sitter-gox)

