-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local function markdown_defaults(buf)
  local ft = vim.bo[buf].filetype
  if ft ~= "markdown" and ft ~= "markdown.mdx" then
    return
  end
  vim.diagnostic.enable(false, { bufnr = buf })
  vim.opt_local.spell = false
end

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("markdown_defaults", { clear = true }),
  callback = function(event)
    markdown_defaults(event.buf)
  end,
  desc = "Disable diagnostics and spelling in Markdown buffers",
})

markdown_defaults(vim.api.nvim_get_current_buf())
