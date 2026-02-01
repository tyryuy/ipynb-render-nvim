# ipynb-render.nvim (MVP)

Render a .ipynb file into a readable scratch buffer in Neovim.

## Requirements
- Neovim
- Python 3
- `pip install nbformat`

## Install (lazy.nvim)
```lua
{
  "YOUR_GITHUB_NAME/ipynb-render.nvim",
  cmd = { "IpynbRender" },
  config = function()
    require("ipynb_render").setup({
      -- python_cmd = "python3",
      -- split = "vsplit",
      -- view_filetype = "markdown",
    })
  end,
}
```

## Usage

Open a .ipynb file and run:

```
:IpynbRender
```

Navigation in the view buffer:

- `]]` next cell
- `[[` previous cell
