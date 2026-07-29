return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      preset = "default",
      ["<Tab>"] = {
        function(cmp)
          if cmp.is_visible() then
            return cmp.accept()
          elseif vim.snippet.active({ direction = 1 }) then
            return vim.snippet.jump(1)
          else
            return cmp.fallback()
          end
        end,
        "snippet_forward",
        "fallback",
      },
      ["<S-Tab>"] = {
        function(cmp)
          if cmp.is_visible() then
            return cmp.select_prev()
          elseif vim.snippet.active({ direction = -1 }) then
            return vim.snippet.jump(-1)
          else
            return cmp.fallback()
          end
        end,
        "snippet_backward",
        "fallback",
      },
      ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<CR>"] = { "accept", "fallback" },
      ["<C-e>"] = { "hide", "fallback" },
      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-u>"] = { "scroll_documentation_up", "fallback" },
      ["<C-d>"] = { "scroll_documentation_down", "fallback" },
    },
    accept = {
      auto_brackets = {
        enabled = true,
      },
    },
    trigger = {
      signature_help = {
        enabled = true,
      },
    },
  },
}
