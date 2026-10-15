-- Run from the repository root:
-- MERMAID_PREVIEW_MODE=ascii nvim --headless -u NONE -i NONE -l users/kenjihash/nvim/tests/mermaid.lua
-- Add MERMAID_TEST_IMAGE=1 to also test Chromium conversion and remote PNG transfer.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
vim.g.mapleader = " "
local spec = dofile(root .. "/lua/plugins/snacks.lua")[1]
require("snacks").setup(spec.opts)

local function run()
  assert(not Snacks.image.config.doc.enabled, "Automatic image rendering must stay off")
  assert(not package.loaded["config.mermaid"], "Preview module must load on demand")
  local M = require("config.mermaid")
  assert(M.mode == (vim.env.MERMAID_PREVIEW_MODE == "ascii" and "ascii" or "image"), "Session preference ignored")
  M.mode = "ascii"
  local buf = vim.api.nvim_get_current_buf()
  local source = {
    "# Diagrams",
    "",
    "```mermaid",
    "graph LR",
    "  A[First] --> B[Target]",
    "```",
    "",
    "Outside any diagram.",
    "",
    "~~~~mermaid",
    "sequenceDiagram",
    "Alice->>Bob: Hello",
    "~~~~",
    "",
    "> ```mermaid",
    "> graph TD",
    ">   Quoted --> Diagram",
    "> ```",
    "",
    "```mermaid",
    "graph LR",
    "  Big[" .. string.rep("VeryWideLabel", 12) .. "]",
    "```",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modified = false
  local win = vim.api.nvim_get_current_win()
  local ns = vim.api.nvim_create_namespace("mermaid_preview")
  local function marks()
    return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  end
  local notifications = {}
  vim.notify = function(message)
    notifications[#notifications + 1] = message
  end
  local terminal = Snacks.image.terminal
  terminal.detect = function()
    error("ASCII mode must never probe terminal graphics")
  end
  local system = vim.system
  local runs, last_width = 0, nil
  vim.system = function(cmd, opts, cb)
    if cmd[1] == "mermaid-ascii" then
      runs = runs + 1
      last_width = tonumber(cmd[4])
      assert(cmd[2] == "--ascii", "Mobile previews must use plain ASCII")
    end
    return system(cmd, opts, cb)
  end
  local function preview(row)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { row, 0 })
    M.preview()
  end
  local function inline(row, expected)
    preview(row)
    assert(
      vim.wait(5000, function()
        return #marks() == 1
      end, 10),
      "No inline ASCII preview: " .. vim.inspect(notifications)
    )
    assert(vim.api.nvim_get_current_win() == win, "Inline preview stole focus")
    local mark = marks()[1]
    local text = vim.inspect(mark[4].virt_lines)
    assert(text:find(expected, 1, true), "Rendered the wrong Mermaid block: " .. text)
    assert(mark[2] >= row - 1, "Preview must be below its source block")
  end
  vim.wait(100)
  inline(4, "First")
  local rendered = runs
  preview(5)
  assert(
    vim.wait(2000, function()
      return #marks() == 0
    end, 10),
    "Preview key did not toggle off"
  )
  inline(4, "First")
  assert(runs == rendered, "Identical previews should reuse cached text")
  M.close()
  inline(11, "Alice")
  M.close()
  inline(16, "Quoted")
  M.toggle_mode()
  assert(#marks() == 0 and M.mode == "image", "Mode switch did not clear inline text")
  assert(runs == rendered + 2, "Mode switch rendered automatically")
  M.toggle_mode()
  inline(4, "First")
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# Edited" })
  assert(
    vim.wait(2000, function()
      return #marks() == 0
    end, 10),
    "Editing did not clear stale preview"
  )
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { source[1] })
  vim.bo[buf].modified = false

  preview(8)
  assert(
    vim.wait(2000, function()
      return tostring(notifications[#notifications]):find("Mermaid fenced code block", 1, true) ~= nil
    end, 10),
    "Missing warning outside a Mermaid block"
  )
  assert(#marks() == 0, "Rendered outside a block")

  vim.cmd("vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 35)
  vim.wo.number, vim.wo.numberwidth, vim.wo.signcolumn = true, 4, "yes"
  vim.wait(100)
  inline(4, "First")
  local info = vim.fn.getwininfo(win)[1]
  assert(last_width == math.max(1, info.width - info.textoff - 2), "Renderer ignored current window gutters")
  M.close()
  preview(21)
  assert(
    vim.wait(5000, function()
      return vim.api.nvim_get_current_win() ~= win
    end, 10),
    "Wide diagram needs a float"
  )
  local float = vim.api.nvim_get_current_win()
  vim.wait(100)
  assert(vim.api.nvim_win_is_valid(float), "Float was closed by its own resize event")
  assert(vim.api.nvim_win_get_config(float).relative == "editor", "Expected a floating fallback")
  assert(not vim.wo.wrap and not vim.bo.modifiable, "Wide float must preserve alignment and be read-only")
  assert(vim.fn.maparg("q", "n") ~= "", "Wide float needs a close key")
  M.toggle_mode()
  assert(not vim.api.nvim_win_is_valid(float), "Mode switch left the fallback open")
  M.toggle_mode()

  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "  A[Pending] --> B[Target]" })
  local pending, killed
  vim.system = function(cmd, opts, cb)
    assert(cmd[1] == "mermaid-ascii" and opts.stdin:find("Pending", 1, true))
    pending = cb
    return {
      kill = function()
        killed = true
      end,
    }
  end
  preview(4)
  assert(vim.wait(2000, function()
    return pending ~= nil
  end, 10))
  M.toggle_mode()
  assert(killed, "Mode switch did not cancel the pending renderer")
  pending({ code = 0, stdout = "stale result", stderr = "" })
  vim.wait(100)
  assert(#marks() == 0, "Canceled renderer displayed stale text")
  vim.system = system

  -- Validate the image path without depending on a live terminal UI.
  local env = { supported = true, placeholders = true, remote = false }
  terminal.detect = function(cb)
    cb({ terminal = "ghostty" })
  end
  terminal.env = function()
    return env
  end
  local placement = Snacks.image.placement
  local placement_new = placement.new
  local closed, received = false, nil
  placement.new = function(image_buf, src, opts)
    assert(image_buf == buf and src:match("%.mmd$"))
    received = opts
    return {
      close = function()
        closed = true
      end,
    }
  end
  preview(4)
  assert(
    vim.wait(2000, function()
      return received ~= nil
    end, 10),
    "Image mode did not create a placement"
  )
  assert(received.inline and not received.conceal, "Image must be inline without hiding source")
  assert(env.remote, "SSH image previews must transfer bytes, not filenames")
  assert(received.max_width == math.max(1, info.width - info.textoff - 2))
  preview(5)
  assert(
    vim.wait(2000, function()
      return closed
    end, 10),
    "Image toggle did not close its placement"
  )
  placement.new = placement_new

  if vim.env.MERMAID_TEST_IMAGE == "1" then
    local requests = {}
    terminal.write = function(data)
      requests[#requests + 1] = data
    end
    preview(4)
    assert(
      vim.wait(35000, function()
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, placement.ns, 0, -1, { details = true })) do
          if mark[4].virt_lines then
            return true
          end
        end
        return false
      end, 25),
      "Real inline image placement failed: " .. vim.inspect(notifications)
    )
    local data = table.concat(requests)
    assert(data:find("t=d", 1, true), "PNG bytes were not sent over the terminal protocol")
    assert(not data:find("t=f", 1, true), "Image used a server-side file path")
    M.close()
    assert(#vim.api.nvim_buf_get_extmarks(buf, placement.ns, 0, -1, {}) == 0, "Image cleanup left placeholder marks")
  end
  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { source[5] })
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source), "Previews changed source text")
  print(
    "PASS: inline ASCII, toggle/cache, source edits, narrow-window float, cancellation, session preference and remote image placement"
      .. (vim.env.MERMAID_TEST_IMAGE == "1" and "; real PNG conversion and byte transfer" or "")
  )
end

local ok, err = pcall(run)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
