return {
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        enabled = true,
        convert = { notify = true },
        doc = {
          enabled = false,
          inline = false,
        },
      },
    },
    keys = {
      {
        "<leader>mp",
        function()
          require("config.mermaid").preview()
        end,
        ft = { "markdown", "markdown.mdx" },
        desc = "Toggle inline Mermaid preview",
      },
      {
        "<leader>mm",
        function()
          require("config.mermaid").toggle_mode()
        end,
        ft = { "markdown", "markdown.mdx" },
        desc = "Switch Mermaid image/ASCII mode",
      },
    },
  },
}
