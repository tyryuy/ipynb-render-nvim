local M = {}

M.opts = {
  python_cmd = "python3",
  view_filetype = "markdown",
  split = "vsplit", -- "tabnew" なども可
  show_errors = true,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

local function find_python_script()
  local files = vim.api.nvim_get_runtime_file("python/ipynb_render.py", false)
  return files and files[1] or nil
end

local function systemlist(cmd)
  -- list形式で渡すとシェル解釈を避けられる
  return vim.fn.systemlist(cmd)
end

local function create_view_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = M.opts.view_filetype
  vim.bo[buf].readonly = true

  -- MVP: セル間ジャンプ（# ==== Cell ... ==== を検索）
  vim.keymap.set("n", "]]", function()
    vim.fn.search("^# ==== Cell", "W")
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "[[", function()
    vim.fn.search("^# ==== Cell", "bW")
  end, { buffer = buf, silent = true })

  return buf
end

function M.render_current(params)
  params = params or {}
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("No file path for current buffer", vim.log.levels.WARN)
    return
  end
  if not path:match("%.ipynb$") then
    vim.notify("Not an .ipynb file: " .. path, vim.log.levels.WARN)
    return
  end

  local script = find_python_script()
  if not script then
    vim.notify("python/ipynb_render.py not found in runtimepath", vim.log.levels.ERROR)
    return
  end

  local cmd = { M.opts.python_cmd, script, path }
  local out = systemlist(cmd)

  -- systemlist は失敗時も出力を返すことがあるので、v:shell_error を見る
  if vim.v.shell_error ~= 0 then
    local msg = table.concat(out, "\n")
    vim.notify("ipynb render failed:\n" .. msg, vim.log.levels.ERROR)
    return
  end

  local buf = create_view_buffer(out)
  vim.cmd(M.opts.split)
  vim.api.nvim_win_set_buf(0, buf)
end

return M
