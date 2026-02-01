# ipynb-render.nvim

Editable .ipynb view in Neovim: open a notebook and edit only cell inputs in a single buffer.

## Requirements
- Neovim
- Python 3
- `pip install nbformat`

## Install (lazy.nvim)
```lua
{
  "tyryuy/ipynb-render-nvim",
  ft = { "ipynb" },
  config = function()
    require("ipynb_render").setup({
      -- python_cmd = "python3",
      -- auto_open = true,
    })
  end,
}
```

## Usage

Open a `.ipynb` file and the buffer is transformed into an editable notebook view.

Commands:
- `:IpynbOpen` open current `.ipynb` in notebook view
- `:IpynbCellAddAbove`
- `:IpynbCellAddBelow`
- `:IpynbCellDelete`
- `:IpynbCellMoveUp`
- `:IpynbCellMoveDown`
- `:IpynbCellToggleType`

Save:
- `:write` writes back to `.ipynb` while preserving notebook metadata.

## Code Highlight
Code cells use Vim's syntax files based on notebook metadata (`language_info.name` or `kernelspec.language`).
The buffer syntax is set to that language, and markdown cells are masked to keep them unhighlighted.
If highlighting is missing, ensure `:syntax enable` and that the language syntax file exists.
