# git_snoop.nvim

A Neovim plugin for viewing git file history with advanced diffing and blame features, allowing you to scroll through commits and see how files evolved over time.

## Features

- 📜 View complete git history for the current file using `git log --oneline --follow`
- 🔍 Side-by-side diff view with vim diff mode
- 👀 Interactive navigation through commit history with hjkl keys
- 🔍 Toggle between diff view and blame mode with detailed author information
- 📝 Syntax highlighting for all supported file types
- ⌨️ Intuitive keybindings and customizable mappings
- 🚀 Fast and responsive interface

## Requirements

- Neovim >= 0.7.0
- Git
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
{
  'va-ji/git_snoop.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim'
  },
  config = function()
    require('git_snoop').setup({
      mappings = {
        file_history = '<leader>gh',      -- Show file history
      }
    })
  end,
  cmd = { 'GitSnoopFile' },  -- Lazy load on command
  keys = {
    { '<leader>gh', desc = 'Git file history' },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'va-ji/git_snoop.nvim',
  requires = {
    'nvim-lua/plenary.nvim'
  },
  config = function()
    require('git_snoop').setup({
      mappings = {
        file_history = '<leader>gh',
      }
    })
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'va-ji/git_snoop.nvim'
```

Then in your init.lua:
```lua
require('git_snoop').setup({
  mappings = {
    file_history = '<leader>gh',
  }
})
```

## Usage

### Commands

- `:GitSnoopFile` - Show git history for the current file

### Default Keymaps (when configured)

- `<leader>gh` - Show file history

### Navigation Keys (in diff view)

- `j` or `l` - Next commit (older)
- `k` or `h` - Previous commit (newer)
- `b` - Toggle blame mode (shows author and date for each line)
- `q` - Close diff view

### In Diff View

The plugin opens a side-by-side diff view where you can:
- Navigate through commit history using hjkl keys
- See live diff highlighting between current file and historical versions
- Toggle blame mode to see detailed authorship information
- View syntax highlighting for all supported file types

## Configuration

```lua
require('git_snoop').setup({
  mappings = {
    file_history = '<leader>gh',      -- Custom keymap for file history
  }
})
```

### Default Configuration

```lua
{
  mappings = {
    file_history = nil,  -- No default mapping, set your own
  }
}
```

## How it works

1. **File History**: Uses `git log --oneline --follow <file>` to track the file through renames and moves
2. **Diff View**: Creates a side-by-side diff using Vim's built-in diff mode
3. **Historical Content**: Fetches historical versions using `git show <commit>:<file>`
4. **Blame Mode**: Uses `git blame --line-porcelain` to show detailed authorship information
5. **Syntax Highlighting**: Maintains proper syntax highlighting for historical file versions

## Example Workflow

1. Open a file in Neovim
2. Press `<leader>gh` (or run `:GitSnoopFile`)
3. Navigate through commits using hjkl keys in the diff view
4. Toggle blame mode with `b` to see author information
5. Press `q` to close the diff view
