
# termpicker.nvim

![Demo](assets/demo.webm)

A Neovim plugin that integrates [termpicker][2] - a terminal-based color picker - directly into your editor workflow. Pick colors interactively using RGB, HSL, and CMYK sliders with live preview, then insert them into your code or copy to clipboard.

## Features

- **Interactive Color Picking**: Use termpicker's TUI with RGB, HSL, and CMYK sliders
- **Smart Color Detection**: Automatically detects existing colors in visual selections
- **Multiple Output Formats**: Supports HEX, RGB, HSL, CMYK, and ANSI color formats
- **Flexible Output Options**: Insert at cursor, replace selections, or copy to registers
- **Configurable Preview**: Customize sample text and background/foreground colors
- **Auto-Installation**: Automatically installs termpicker binary when first used
- **Multiple Installation Methods**: Supports Go installation and binary downloads

## Requirements

- A truecolor terminal (for best color preview experience)
- One of the following:
  - termpicker already installed on your system
  - Go 1.19+ (plugin will then auto-install termpicker using `go install`)

## Installation

### lazy.nvim

```lua
{
  "ChausseBenjamin/termpicker.nvim",
  config = true, -- Use default configuration
  -- Or customize with opts:
  -- opts = { starting_color = "#FF5733" }
  keys = {
    { "<C-g>", "<cmd>lua require('termpicker').pick()<cr>", desc = "Pick color", mode = { "n", "i", "x" } },
  },
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/ChausseBenjamin/termpicker.nvim" },
})

require('termpicker').setup()
```

## Configuration

```lua
require('termpicker').setup({
  -- Output destination: nil = insert at cursor, string = register name
  output = nil, -- e.g., '"' for default register, '+' for clipboard

  -- Initial color when starting the picker
  starting_color = '#7F7F7F',

  preview = {
    -- Text to preview colors with (nil uses termpicker default)
    text = nil, -- Default: "The quick brown fox jumps over the lazy dog"

    -- Background color when previewing foreground colors
    background = nil, -- Default: "#111a1f"

    -- Foreground color when previewing background colors
    foreground = nil, -- Default: "#ebcb88"
  },

  behaviour = {
    -- If true, starting_color overrides colors found in visual selections
    prefer_config_color = false,

    -- If true, preserve visual selections and use configured output method
    preserve_selection = false,
  },
})
```

## Usage

### Basic Keybinding

```lua
vim.keymap.set(
  { 'i', 'n', 'o', 'x' },
  "<C-g>",
  function()
    require('termpicker').pick()
  end,
  { desc = "Pick color" }
)
```

### Mode-Specific Behavior

- **Normal Mode**: Inserts color at cursor (or uses configured output method)
- **Insert Mode**: Inserts color at cursor and returns to insert mode
- **Visual Mode**: Replaces selection with picked color (uses selection as starting color if valid)

### Advanced Usage Examples

#### Copy to Yank Buffer Instead of Inserting

```lua
vim.keymap.set('n', '<leader>cy', function()
  require('termpicker').pick({ output = '"' })
end, { desc = "Pick color to yank buffer" })
```

#### Start with Specific Color

```lua
vim.keymap.set('n', '<leader>cr', function()
  require('termpicker').pick({ starting_color = '#FF0000' })
end, { desc = "Pick color starting from red" })
```

## Supported Color Formats

The plugin automatically detects and works with these color formats:

- **HEX**: `#FF5733`, `#f57`
- **RGB**: `rgb(255, 87, 51)`
- **HSL**: `hsl(9, 100%, 60%)`
- **CMYK**: `cmyk(0%, 66%, 80%, 0%)`
- **OKLCH**: `oklch(65.09% 0.203 29.23)`
- **ANSI**: `\X1B[38;2;255;87;51m` (foreground), `\X1B[48;2;255;87;51m` (background)

## Installation of termpicker Binary

The plugin will automatically prompt to install the termpicker binary when first used. It tries these methods in order:

1. **Go installation** (if Go is available): `go install github.com/ChausseBenjamin/termpicker@latest`
2. **Binary download**: Downloads pre-compiled binary for your platform

You can also manually install termpicker following it's instructions:

[https://github.com/ChausseBenjamin/termpicker?tab=readme-ov-file#installation][1]


## API Reference

### Functions

- `setup(opts)` - Configure the plugin
- `pick(opts)` - Open color picker with optional per-call configuration
- `pick_replace_selection(text, start_row, start_col, end_row, end_col, opts)` - Replace specific text range
- `termpicker_path()` - Get path to termpicker binary
- `install_termpicker()` - Install termpicker binary

### Configuration Types

See the type annotations in `lua/termpicker/init.lua` for detailed configuration options.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Related Projects

- [termpicker][2] - The underlying terminal color picker tool

[1]: https://github.com/ChausseBenjamin/termpicker?tab=readme-ov-file#installation
[2]: https://github.com/ChausseBenjamin/termpicker
