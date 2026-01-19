# `haunt.nvim`

Hear the ghosts of where you’ve been...

Annotate your code base with ghost text, search through the history of your files.

Bring back the past with haunt.nvim!

TODO: add a little photo of a ghost and a programmer

## Features

- Virtual text annotations
  * Keep your personal notes in your code without modifying the actual files
- Git integration
  * annotations are tied to a git branch. Keep different notes for different branches
- Search through your bookmarks with `snacks.nvim` (Telescope and fzf.lua support coming soon)
- Send your bookmarks to `sidekick.nvim` so your favorite cli tool can help purge you of your hauntings

## Requirements

- what ever neovim version first introduced virtual text, or whatever we use
- [snacks.nvim](https://github.com/folke/snacks.nvim) for picker integration. _(optional)_
- [sidekick.nvim](https://github.com/folke/sidekick.nvim) for AI integration (and a cli tool of your choice). _(optional)_

## Installation

TODO: users should be able to toggle notification. add a 'notify' option to config.
this can take in a boolean, or a logging level. then, in the program, we can use
a custom logger that uses vim.notify. we are gonna wanna use closure to store the log level and avoid recomputes
``` lua
return {
  "TheNoeTrevino/haunt.nvim",
  opts = {
    -- default config: change to your liking, or remove it to use defaults
    ---@class HauntConfig
    sign = "󱙝",
    sign_hl = "DiagnosticInfo",
    virt_text_hl = "HauntAnnotation",
    annotation_prefix = " 󰆉 ",
    line_hl = nil,
    virt_text_pos = "eol",
    data_dir = nil,
    picker_keys = {
      delete = { key = "d", mode = { "n" } },
      edit_annotation = { key = "a", mode = { "n" } },
    },
  },
  -- recommended keymaps, with a helpful prefix alias
  init = function()
    local haunt = require("haunt.api")
    local haunt_picker = require("haunt.picker")
    local map = vim.keymap.set
    local prefix = "<leader>h"

    -- annotations
    map("n", prefix .. "a", function()
      haunt.annotate()
    end, { desc = "Annotate" })

    map("n", prefix .. "t", function()
      haunt.toggle_annotation()
    end, { desc = "Toggle annotation" })

    map("n", prefix .. "T", function()
      haunt.toggle_all_lines()
    end, { desc = "Toggle all annotations" })

    map("n", prefix .. "d", function()
      haunt.delete()
    end, { desc = "Delete bookmark" })

    map("n", prefix .. "C", function()
      haunt.clear_all()
    end, { desc = "Delete all bookmarks" })

    -- move
    map("n", prefix .. "p", function()
      haunt.prev()
    end, { desc = "Previous bookmark" })

    map("n", prefix .. "n", function()
      haunt.next()
    end, { desc = "Next bookmark" })

    -- picker
    map("n", prefix .. "l", function()
      haunt_picker.show()
    end, { desc = "Show Picker" })
  end,
}
```

## Usage

By default, haunt.nvim provides ***no default keymaps***. You will have to set them up yourself. See the installation section for an example.
The installation section includes some recommended keymaps to get you started.
You can also just use the user commands, which we will talk about later.

Here are the exposed API functions you should know about:

``` lua
local haunt = require("haunt.api")
local haunt_picker = require("haunt.picker")
local haunt_sk = require("haunt.sidekick")

-- See `:h haunt-api` for more info on each function
-- Annotate the current line with a ghost text annotation,
-- or edit the annotation if it already exists
haunt.annotate()

-- Toggle visibility of the current annotation
haunt.toggle_annotation()

-- Toggle visibility of the all annotations
haunt.toggle_all_lines()

-- Remove all annotations in the workspace. Good for when you finish up a subtask
haunt.clear_all()

-- Delete the current annotation
haunt.delete()

-- Jump to the next/prev annotation in the buffer
haunt.next()
haunt.prev()

-- Currently only supports snacks.nvim
-- Open the bookmark picker.
--
-- Displays all bookmarks in an interactive picker powered by Snacks.nvim.
-- Allows jumping to, deleting, or editing bookmark annotations.
-- see :h haunt-picker for more info, and the snacks section below
haunt_picker.show()

-- Get bookmark locations formatted for sidekick.nvim.
-- Returns bookmarks in sidekick-compatible format:
-- `- @/{path} :L{line} - "{note}"`
-- see :h haunt-sidekick for more info, and the sidekick section below
haunt_sk.get_locations()
haunt_sk.get_locations({current_buffer = true})
```
TODO: add youtube video of usage!

## Integrations 

### snacks.nvim

Edit and delete annotations from the picker using `snacks.nvim`:

TODO: insert gif of this!

``` lua
return {
  "TheNoeTrevino/haunt.nvim",
  opts = {
    picker_keys = {
      delete = {
        key = "d",
        mode = { "n" },
      },
    }
    edit_annotation = {
      key = "a",
      mode = { "n" },
    },
  },
}
```

### sidekick.nvim

TODO: insert gif of this!

``` lua

local haunt_sk = require("haunt.sidekick")
return {
  "folke/sidekick.nvim",
  cmd = "Sidekick",
  ---@class sidekick.Config
  opts = {
    cli = {
      prompts = {
        haunt_all = function()
          return haunt_sk.get_locations()
        end,
        haunt_buffer = function()
          return haunt_sk.get_locations({ current_buffer = true })
        end,
      },
    }
  }
}
```
