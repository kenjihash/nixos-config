return {
  -- Override LazyVim's markdown configuration for CommonMark compliance
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      -- Configure formatters for CommonMark compliance
      opts.formatters = opts.formatters or {}
      
      -- Configure prettier for CommonMark
      opts.formatters.prettier = {
        prepend_args = { 
          "--tab-width", "4",           -- 4-space indentation per CommonMark
          "--prose-wrap", "preserve",   -- Preserve line wrapping
          "--print-width", "100"        -- Reasonable line length
        },
      }
      
      -- Configure markdownlint-cli2 to use our CommonMark config
      opts.formatters["markdownlint-cli2"] = {
        args = { "--fix", "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc"), "$FILENAME" },
      }
      
      -- Use both formatters for comprehensive CommonMark formatting
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.markdown = { "markdownlint-cli2", "markdown-toc" }
      opts.formatters_by_ft["markdown.mdx"] = { "markdownlint-cli2", "markdown-toc" }
      
      return opts
    end,
  },
  
  -- Configure the markdown language server for CommonMark
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = {
          settings = {
            -- Configure marksman LSP for CommonMark
            marksman = {
              markdown = {
                -- Use CommonMark spec
                spec = "commonmark",
                -- Enable CommonMark extensions
                extensions = {
                  "strikethrough",
                  "table", 
                  "autolink",
                  "tasklist"
                }
              }
            }
          }
        }
      }
    }
  },
  
  -- Configure treesitter for better CommonMark parsing
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Ensure markdown parsers are installed
      vim.list_extend(opts.ensure_installed or {}, {
        "markdown",
        "markdown_inline",
        "html"  -- For inline HTML in CommonMark
      })
      return opts
    end,
  },
  
  -- Configure render-markdown for CommonMark rendering
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      -- CommonMark-compliant rendering
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
        style = "full",  -- Full width code blocks per CommonMark
      },
      heading = {
        sign = false,
        icons = {},
        width = "full",  -- Full width headings
      },
      bullet = {
        -- CommonMark bullet styles
        icons = { "•", "◦", "▸", "▹" },
        right_pad = 1,
        highlight = "RenderMarkdownBullet",
      },
      checkbox = {
        enabled = true,  -- Enable task lists (CommonMark extension)
        unchecked = {
          icon = "󰄱 ",
          highlight = "RenderMarkdownUnchecked",
        },
        checked = {
          icon = "󰱒 ",
          highlight = "RenderMarkdownChecked",
        },
      },
      -- CommonMark table support
      table = {
        style = "full",
        cell = "padded",
        border = {
          "┌", "┬", "┐",
          "├", "┼", "┤", 
          "└", "┴", "┘",
          "│", "─"
        },
      },
    },
  },
}