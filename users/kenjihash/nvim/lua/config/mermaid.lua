local M = { mode = vim.env.MERMAID_PREVIEW_MODE == "ascii" and "ascii" or "image" }

local ns = vim.api.nvim_create_namespace("mermaid_preview")
local active
local watched = {}
local ascii_cache = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Mermaid preview" })
end

function M.close()
  local previous = active
  active = nil
  if not previous then
    return
  end
  if previous.process then
    previous.process:kill(15)
  end
  if previous.image then
    previous.image:close()
  end
  if previous.hover then
    Snacks.image.doc.hover_close()
  end
  if previous.float and vim.api.nvim_win_is_valid(previous.float) then
    vim.api.nvim_win_close(previous.float, true)
  end
  if vim.api.nvim_buf_is_valid(previous.buf) then
    vim.api.nvim_buf_clear_namespace(previous.buf, ns, 0, -1)
  end
end

function M.toggle_mode()
  M.close()
  M.mode = M.mode == "image" and "ascii" or "image"
  notify("Mode: " .. M.mode .. " (Space mp to preview)")
end

local function watch(buf)
  if watched[buf] then
    return
  end
  watched[buf] = true
  local function clear()
    local previous = active
    if previous and previous.buf == buf then
      vim.schedule(function()
        if active == previous then
          M.close()
        end
      end)
    end
  end
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = clear,
    on_detach = function()
      watched[buf] = nil
      clear()
    end,
  })
end

local function usable_width(win)
  local info = vim.fn.getwininfo(win)[1]
  return math.max(1, info.width - info.textoff - 2)
end

local function alive(state)
  return active == state
    and vim.api.nvim_buf_is_valid(state.buf)
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_buf(state.win) == state.buf
    and vim.api.nvim_buf_get_changedtick(state.buf) == state.tick
end

local function show_float(state, lines, width)
  if vim.api.nvim_get_current_win() ~= state.win then
    return M.close()
  end
  width = math.min(width, math.max(1, vim.o.columns - 4))
  local height = math.min(#lines, math.max(1, vim.o.lines - 6))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  state.float = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Mermaid · ASCII (scroll to view) ",
    title_pos = "center",
  })
  vim.wo[state.float].wrap = false
  vim.wo[state.float].spell = false
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close, { buffer = buf, silent = true, desc = "Close Mermaid preview" })
  end
  vim.keymap.set("n", "<leader>mp", M.preview, { buffer = buf, desc = "Toggle Mermaid preview" })
  vim.keymap.set("n", "<leader>mm", M.toggle_mode, { buffer = buf, desc = "Switch Mermaid image/ASCII mode" })
end

local function show_ascii(state, output)
  local lines = vim.split(output:gsub("\r\n", "\n"):gsub("\n$", ""), "\n", { plain = true })
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  if width > state.width then
    return show_float(state, lines, width)
  end
  vim.api.nvim_buf_set_extmark(state.buf, ns, state.range[3] - 1, 0, {
    virt_lines = vim.tbl_map(function(line)
      return { { line, "Normal" } }
    end, lines),
    virt_lines_above = false,
  })
end

local function render_ascii(state, diagram)
  local key = vim.fn.sha256(diagram.content .. "\n" .. state.width)
  if ascii_cache[key] then
    return show_ascii(state, ascii_cache[key])
  end
  if vim.fn.executable("mermaid-ascii") ~= 1 then
    M.close()
    return notify("mermaid-ascii is not installed or is missing from PATH.", vim.log.levels.ERROR)
  end
  state.process = vim.system(
    { "mermaid-ascii", "--ascii", "--max-width", tostring(state.width) },
    { stdin = diagram.content, text = true, timeout = 10000 },
    vim.schedule_wrap(function(result)
      state.process = nil
      if not alive(state) then
        return
      end
      if result.code ~= 0 or vim.trim(result.stdout or "") == "" then
        M.close()
        return notify(
          vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "ASCII rendering failed.",
          vim.log.levels.ERROR
        )
      end
      ascii_cache[key] = result.stdout
      show_ascii(state, result.stdout)
    end)
  )
end

local function render_image(state, diagram)
  local terminal = Snacks.image.terminal
  terminal.detect(function()
    if not alive(state) then
      return
    end
    local env = terminal.env()
    -- Image mode is used over SSH. Send PNG bytes, never a server-side path,
    -- including when an attached multiplexer did not inherit SSH variables.
    env.remote = true
    if not env.supported then
      M.close()
      return notify(
        "Image mode needs a graphics-capable terminal. In Ghostty, launch with SNACKS_GHOSTTY=true; use ASCII mode over Mosh.",
        vim.log.levels.WARN
      )
    end
    if not env.placeholders then
      if
        vim.api.nvim_get_current_win() == state.win
        and vim.deep_equal(vim.api.nvim_win_get_cursor(state.win), state.cursor)
      then
        state.hover = true
        Snacks.image.hover()
      else
        M.close()
      end
      return
    end
    state.image = Snacks.image.placement.new(state.buf, diagram.src, {
      pos = diagram.pos,
      range = diagram.range,
      inline = true,
      conceal = false,
      type = "chart",
      max_width = state.width,
      max_height = math.max(1, math.min(30, vim.api.nvim_win_get_height(state.win) - 4)),
    })
  end)
end

function M.preview()
  if active and active.float == vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(active.win) then
    vim.api.nvim_set_current_win(active.win)
  end
  local previous = active
  M.close()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  if ft ~= "markdown" and ft ~= "markdown.mdx" then
    return notify("Open a Markdown buffer to preview a Mermaid block.", vim.log.levels.WARN)
  end
  local win = vim.api.nvim_get_current_win()
  local state = {
    buf = buf,
    win = win,
    mode = M.mode,
    cursor = vim.api.nvim_win_get_cursor(win),
    tick = vim.api.nvim_buf_get_changedtick(buf),
    width = usable_width(win),
    height = vim.api.nvim_win_get_height(win),
  }
  active = state
  watch(buf)
  -- Both renderers use Snacks' Markdown queries to select exactly the same block.
  Snacks.image.doc.find(buf, function(images)
    if not alive(state) then
      return
    end
    local diagram
    for _, image in ipairs(images) do
      if
        image.type == "chart"
        and image.content
        and state.cursor[1] >= image.range[1]
        and state.cursor[1] <= image.range[3]
      then
        diagram = image
        break
      end
    end
    if not diagram then
      M.close()
      return notify("Place the cursor inside a Mermaid fenced code block.", vim.log.levels.WARN)
    end
    state.range = diagram.range
    if previous and previous.buf == buf and previous.mode == M.mode and vim.deep_equal(previous.range, state.range) then
      return M.close()
    end
    if M.mode == "image" then
      render_image(state, diagram)
    else
      render_ascii(state, diagram)
    end
  end, { from = state.cursor[1], to = state.cursor[1] + 1 })
end

local group = vim.api.nvim_create_augroup("mermaid_preview", { clear = true })
vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
  group = group,
  callback = function(event)
    if active and vim.api.nvim_win_is_valid(active.win) then
      if
        event.event == "VimResized"
        or usable_width(active.win) ~= active.width
        or vim.api.nvim_win_get_height(active.win) ~= active.height
      then
        M.close()
      end
    end
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(event)
    local previous = active
    if previous and (tonumber(event.match) == previous.win or tonumber(event.match) == previous.float) then
      vim.schedule(function()
        if active == previous then
          M.close()
        end
      end)
    end
  end,
})

return M
