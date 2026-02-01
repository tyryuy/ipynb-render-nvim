vim.api.nvim_create_user_command("IpynbRender", function(opts)
  require("ipynb_render").render_current({
    open = opts.args ~= "" and opts.args or nil,
  })
end, {
  nargs = "?",
  complete = "file",
  desc = "Render current .ipynb into a scratch view buffer",
})
