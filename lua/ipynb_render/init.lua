local M = {}

M.opts = {
  python_cmd = "python3",
  view_filetype = "ipynb",
  show_errors = true,
  auto_open = true,
}

M.ns = vim.api.nvim_create_namespace("ipynb_render")
M.state = {}
M.syntax_initialized = {}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  if M._setup_done then
    return
  end
  M._setup_done = true

  if M.opts.auto_open then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "ipynb",
      callback = function(args)
        require("ipynb_render").open_buffer(args.buf)
      end,
    })
  end

  vim.api.nvim_create_user_command("IpynbOpen", function()
    require("ipynb_render").open_buffer(0)
  end, { desc = "Open .ipynb as editable notebook buffer" })

  vim.api.nvim_create_user_command("IpynbCellAddAbove", function()
    require("ipynb_render").cell_add("above")
  end, { desc = "Add cell above" })

  vim.api.nvim_create_user_command("IpynbCellAddBelow", function()
    require("ipynb_render").cell_add("below")
  end, { desc = "Add cell below" })

  vim.api.nvim_create_user_command("IpynbCellDelete", function()
    require("ipynb_render").cell_delete()
  end, { desc = "Delete current cell" })

  vim.api.nvim_create_user_command("IpynbCellMoveUp", function()
    require("ipynb_render").cell_move(-1)
  end, { desc = "Move cell up" })

  vim.api.nvim_create_user_command("IpynbCellMoveDown", function()
    require("ipynb_render").cell_move(1)
  end, { desc = "Move cell down" })

  vim.api.nvim_create_user_command("IpynbCellToggleType", function()
    require("ipynb_render").cell_toggle_type()
  end, { desc = "Toggle cell type" })

  if vim.bo.filetype == "ipynb" then
    require("ipynb_render").open_buffer(0)
  end
end

local function find_python_script()
  local files = vim.api.nvim_get_runtime_file("python/ipynb_render.py", false)
  return files and files[1] or nil
end

local function system(cmd, input)
  return vim.fn.system(cmd, input)
end

local function notify_err(msg)
  if M.opts.show_errors then
    vim.notify(msg, vim.log.levels.ERROR)
  end
end

local function normalize_source(src)
  if type(src) == "table" then
    return table.concat(src, "")
  end
  return src or ""
end

local function split_lines(text)
  if text == "" then
    return { "" }
  end
  return vim.split(text, "\n", { plain = true })
end

local function get_range(buf, mark_id)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, mark_id, { details = true })
  local row = pos[1]
  local details = pos[3]
  return row, details.end_row
end

local function set_range_mark(buf, start_row, end_row)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, start_row, 0, {
    end_row = end_row,
    end_col = 0,
    right_gravity = false,
    end_right_gravity = true,
  })
end

local function set_header_mark(buf, row, text)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
    virt_lines = { { { text, "Comment" } } },
    virt_lines_above = true,
  })
end

local function set_output_mark(buf, row)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
    virt_lines = {
      { { "", "Normal" } },
      { { "[ output ]", "NonText" } },
    },
    virt_lines_above = false,
  })
end

local function clear_marks(buf, ids)
  for _, id in ipairs(ids) do
    if id then
      pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, id)
    end
  end
end

local function refresh_decorations(buf)
  local st = M.state[buf]
  if not st then
    return
  end
  for i, cell in ipairs(st.cells) do
    clear_marks(buf, { cell.header_id, cell.output_id })
    local start_row, end_row = get_range(buf, cell.range_id)
    cell.header_id = set_header_mark(buf, start_row, string.format("---- Cell %d (%s) ----", i, cell.cell.cell_type))
    local out_row = math.max(start_row, end_row - 1)
    cell.output_id = set_output_mark(buf, out_row)
  end
end

local function ensure_syntax(buf)
  if M.syntax_initialized[buf] then
    return
  end
  local st = M.state[buf]
  if not st then
    return
  end
  local lang = st.lang or "python"
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! syntax include @ipynb_code syntax/" .. lang .. ".vim")
  end)
  M.syntax_initialized[buf] = true
end

local function clear_syntax_regions(buf)
  local st = M.state[buf]
  if not st or not st.syntax_regions then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    for _, name in ipairs(st.syntax_regions) do
      vim.cmd("silent! syntax clear " .. name)
    end
  end)
  st.syntax_regions = {}
end

local function refresh_syntax(buf)
  local st = M.state[buf]
  if not st then
    return
  end
  ensure_syntax(buf)
  clear_syntax_regions(buf)

  local regions = {}
  vim.api.nvim_buf_call(buf, function()
    for i, cell in ipairs(st.cells) do
      if cell.cell.cell_type == "code" then
        local start_row, end_row = get_range(buf, cell.range_id)
        local start_line = start_row + 1
        local end_line = end_row
        if end_line >= start_line then
          local name = "ipynbCodeCell" .. i
          local start_pat = "\\%>" .. (start_line - 1) .. "l"
          local end_pat = "\\%<" .. (end_line + 1) .. "l"
          vim.cmd(
            string.format(
              "syntax region %s start=/%s/ end=/%s/ contains=@ipynb_code keepend",
              name,
              start_pat,
              end_pat
            )
          )
          table.insert(regions, name)
        end
      end
    end
  end)
  st.syntax_regions = regions
end

local function current_cell_index(buf)
  local st = M.state[buf]
  if not st then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for i, cell in ipairs(st.cells) do
    local start_row, end_row = get_range(buf, cell.range_id)
    if row >= start_row and row < end_row then
      return i
    end
  end
  -- If cursor is on separator, pick nearest previous cell
  for i = #st.cells, 1, -1 do
    local start_row = get_range(buf, st.cells[i].range_id)
    if row >= start_row then
      return i
    end
  end
  return nil
end

local function read_notebook(path)
  local script = find_python_script()
  if not script then
    notify_err("python/ipynb_render.py not found in runtimepath")
    return nil
  end
  local cmd = { M.opts.python_cmd, script, "read", path }
  local out = system(cmd)
  if vim.v.shell_error ~= 0 then
    notify_err("ipynb read failed:\n" .. out)
    return nil
  end
  return vim.json.decode(out)
end

local function write_notebook(path, notebook)
  local script = find_python_script()
  if not script then
    notify_err("python/ipynb_render.py not found in runtimepath")
    return false
  end
  local input = vim.json.encode(notebook)
  local cmd = { M.opts.python_cmd, script, "write", path }
  local out = system(cmd, input)
  if vim.v.shell_error ~= 0 then
    notify_err("ipynb write failed:\n" .. out)
    return false
  end
  return true
end

function M.open_buffer(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if vim.b[bufnr].ipynb_loaded then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or not path:match("%.ipynb$") then
    return
  end

  local notebook = read_notebook(path)
  if not notebook then
    return
  end

  vim.b[bufnr].ipynb_loaded = true
  vim.bo[bufnr].filetype = M.opts.view_filetype
  vim.bo[bufnr].modifiable = true

  local lines = {}
  local cells = {}
  local specs = {}
  local row = 0
  for _, cell in ipairs(notebook.cells or {}) do
    local src = normalize_source(cell.source)
    local cell_lines = split_lines(src)
    for _, l in ipairs(cell_lines) do
      table.insert(lines, l)
    end
    table.insert(lines, "") -- separator line

    local start_row = row
    local end_row = row + #cell_lines
    table.insert(specs, {
      cell = cell,
      start_row = start_row,
      end_row = end_row,
    })

    row = end_row + 1
  end

  if #lines == 0 then
    lines = { "" }
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  for _, spec in ipairs(specs) do
    local range_id = set_range_mark(bufnr, spec.start_row, spec.end_row)
    table.insert(cells, {
      cell = spec.cell,
      range_id = range_id,
      header_id = nil,
      output_id = nil,
    })
  end

  local lang = "python"
  local md = notebook.metadata or {}
  if type(md.language_info) == "table" and md.language_info.name then
    lang = md.language_info.name
  elseif type(md.kernelspec) == "table" and md.kernelspec.language then
    lang = md.kernelspec.language
  end

  M.state[bufnr] = { notebook = notebook, cells = cells, lang = lang, syntax_regions = {} }
  refresh_decorations(bufnr)
  refresh_syntax(bufnr)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      require("ipynb_render").save_buffer(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function()
      refresh_decorations(bufnr)
      refresh_syntax(bufnr)
    end,
  })
end

function M.save_buffer(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local st = M.state[bufnr]
  if not st then
    return
  end

  local new_cells = {}
  for _, cell in ipairs(st.cells) do
    local start_row, end_row = get_range(bufnr, cell.range_id)
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
    local text = table.concat(lines, "\n")
    local c = cell.cell
    c.source = text
    if c.cell_type == "code" then
      c.outputs = c.outputs or {}
      if c.execution_count == nil then
        c.execution_count = vim.NIL
      end
    end
    table.insert(new_cells, c)
  end

  st.notebook.cells = new_cells
  local path = vim.api.nvim_buf_get_name(bufnr)
  if write_notebook(path, st.notebook) then
    vim.bo[bufnr].modified = false
  end
end

function M.cell_add(where)
  local buf = vim.api.nvim_get_current_buf()
  local st = M.state[buf]
  if not st then
    return
  end
  local idx = current_cell_index(buf)
  if not idx then
    return
  end

  local target = st.cells[idx]
  local start_row, end_row = get_range(buf, target.range_id)
  local insert_row = where == "above" and start_row or (end_row + 1)

  local new_cell = {
    cell_type = "code",
    metadata = {},
    source = "",
    outputs = {},
    execution_count = vim.NIL,
  }
  local new_lines = { "", "" } -- one blank line + separator
  vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, new_lines)

  local range_id = set_range_mark(buf, insert_row, insert_row + 1)
  local entry = {
    cell = new_cell,
    range_id = range_id,
    header_id = nil,
    output_id = nil,
  }

  if where == "above" then
    table.insert(st.cells, idx, entry)
  else
    table.insert(st.cells, idx + 1, entry)
  end

  refresh_decorations(buf)
  refresh_syntax(buf)
end

function M.cell_delete()
  local buf = vim.api.nvim_get_current_buf()
  local st = M.state[buf]
  if not st then
    return
  end
  local idx = current_cell_index(buf)
  if not idx then
    return
  end

  local cell = st.cells[idx]
  local start_row, end_row = get_range(buf, cell.range_id)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local delete_end = math.min(end_row + 1, line_count)

  vim.api.nvim_buf_set_lines(buf, start_row, delete_end, false, {})
  clear_marks(buf, { cell.range_id, cell.header_id, cell.output_id })
  table.remove(st.cells, idx)

  refresh_decorations(buf)
  refresh_syntax(buf)
end

function M.cell_move(delta)
  local buf = vim.api.nvim_get_current_buf()
  local st = M.state[buf]
  if not st then
    return
  end
  local idx = current_cell_index(buf)
  if not idx then
    return
  end

  local new_idx = idx + delta
  if new_idx < 1 or new_idx > #st.cells then
    return
  end

  local cell = st.cells[idx]
  local start_row, end_row = get_range(buf, cell.range_id)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local block_end = math.min(end_row + 1, line_count)
  local block_lines = vim.api.nvim_buf_get_lines(buf, start_row, block_end, false)

  vim.api.nvim_buf_set_lines(buf, start_row, block_end, false, {})

  local target = st.cells[new_idx]
  local target_start, target_end = get_range(buf, target.range_id)
  local insert_row = delta < 0 and target_start or (target_end + 1)

  vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, block_lines)

  table.remove(st.cells, idx)
  table.insert(st.cells, new_idx, cell)

  refresh_decorations(buf)
  refresh_syntax(buf)
end

function M.cell_toggle_type()
  local buf = vim.api.nvim_get_current_buf()
  local st = M.state[buf]
  if not st then
    return
  end
  local idx = current_cell_index(buf)
  if not idx then
    return
  end

  local cell = st.cells[idx].cell
  if cell.cell_type == "code" then
    cell.cell_type = "markdown"
    cell.outputs = nil
    cell.execution_count = nil
  else
    cell.cell_type = "code"
    cell.outputs = cell.outputs or {}
    cell.execution_count = cell.execution_count or vim.NIL
  end

  refresh_decorations(buf)
  refresh_syntax(buf)
end

return M
