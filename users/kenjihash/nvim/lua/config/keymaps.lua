-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Tab completion for blink.cmp and Copilot
vim.keymap.set("i", "<Tab>", function()
  -- If blink.cmp is available and has completions
  if package.loaded["blink.cmp"] then
    local blink = require("blink.cmp")
    if blink.is_visible() then
      return blink.accept()
    end
  end
  
  -- If Copilot suggestion is available
  if package.loaded["copilot.suggestion"] then
    local copilot = require("copilot.suggestion")
    if copilot.is_visible() then
      return copilot.accept()
    end
  end
  
  -- If in a snippet, jump to next placeholder
  if vim.snippet.active({ direction = 1 }) then
    return vim.snippet.jump(1)
  end
  
  -- Otherwise, insert a regular tab
  return "\t"
end, { expr = true, silent = true, desc = "Accept completion or insert tab" })

-- Shift+Tab for previous snippet placeholder or previous completion
vim.keymap.set("i", "<S-Tab>", function()
  -- If blink.cmp is available and has completions
  if package.loaded["blink.cmp"] then
    local blink = require("blink.cmp")
    if blink.is_visible() then
      return blink.select_prev()
    end
  end
  
  -- If in a snippet, jump to previous placeholder
  if vim.snippet.active({ direction = -1 }) then
    return vim.snippet.jump(-1)
  end
  
  -- Otherwise, do nothing
  return ""
end, { expr = true, silent = true, desc = "Previous completion or snippet placeholder" })
