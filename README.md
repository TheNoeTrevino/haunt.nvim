# `haunt.nvim` 👻

![IMG_0236(1)](https://github.com/user-attachments/assets/de341829-817b-4276-8e72-bb6bf61261b1)


Hear the ghosts tell you where you were, and why you were there.

Bring back the past with haunt.nvim!

Annotate your codebase with ghost text. Search through the history that _you_ choose.

Keep your mental overhead to a minimum and never repeatedly rummage through your codebase again.

<!--toc:start-->
- [`haunt.nvim` 👻](#hauntnvim-👻)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Usage](#usage)
    - [API](#api)
    - [User Commands](#user-commands)
  - [Integrations](#integrations)
    - [Picker (snacks.nvim / telescope.nvim)](#picker-snacksnvim--telescopenvim)
    - [sidekick.nvim](#sidekicknvim)
    - [Git](#git)
    - [Project-Specific Bookmarks](#project-specific-bookmarks)
  - [Why?](#why)
  - [Acknowledgements](#acknowledgements)
  - [Similar Plugins](#similar-plugins)
<!--toc:end-->


## Features

- Virtual text annotations
  * Keep your personal notes in your code without modifying the actual files
- Git integration
  * annotations are tied to a git branch. Keep different notes for different branches
- Jump around using your hauntings
- Search through your bookmarks with `snacks.nvim` or `telescope.nvim`
- Use `sidekick.nvim` to send your annotations to your favorite cli tool. Have a robot purge you of your hauntings!
- Populate the quickfix list with your bookmarks when you want a simple jump list
- Though the examples don't show this, this plugin was deisgned to ease the navigation of massive codebases through semantic markings
- Super fast, and does its best to have as little computations, and load time, as possible. I get around .6ms ;)

## Requirements

- Neovim 0.11 - virtual text
- [snacks.nvim](https://github.com/folke/snacks.nvim) - picker integration. _(optional)_
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - picker integration. _(optional)_
- [sidekick.nvim](https://github.com/folke/sidekick.nvim) - 'AI' integration (and a cli tool of your choice). _(optional)_

## Installation

``` lua
return {
  "TheNoeTrevino/haunt.nvim",
  -- default config: change to your liking, or remove it to use defaults
  ---@class HauntConfig
  opts = {
    sign = "󱙝",
    sign_hl = "DiagnosticInfo",
    virt_text_hl = "HauntAnnotation",
    annotation_prefix = " 󰆉 ",
    line_hl = nil,
    virt_text_pos = "eol",
    data_dir = nil,
    picker = "auto", -- "auto", "snacks", or "telescope"
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

    -- quickfix 
    map("n", prefix .. "q", function()
       haunt.to_quickfix()
    end, { desc = "Send Hauntings to QF Lix (buffer)" })

    map("n", prefix .. "Q", function()
      haunt.to_quickfix({ current_buffer = true })
    end, { desc = "Send Hauntings to QF Lix (all)" })

    -- yank
    map("n", prefix .. "y", function()
      haunt.yank_locations({current_buffer = true})
    end, { desc = "Send Hauntings to Clipboard (buffer)" })

    map("n", prefix .. "Y", function()
      haunt.yank_locations()
    end, { desc = "Send Hauntings to Clipboard (all)" })

  end,
}
```

## Usage

### API

https://github.com/user-attachments/assets/717ccc85-a14f-4dff-b496-b448750c33e1

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

-- Delete annotation on the current line
haunt.delete()

-- Jump to the next/prev annotation in the buffer
haunt.next()
haunt.prev()

-- Open the bookmark picker.
--
-- Displays all bookmarks in an interactive picker.
-- Supports Snacks.nvim and Telescope.nvim (configurable via `picker` option).
-- Allows jumping to, deleting, or editing bookmark annotations.
-- see :h haunt-picker for more info
haunt_picker.show()
haunt_picker.show({ layout = { preset = "vscode" } }) -- Snacks options
haunt_picker.show({ prompt_title = "My Bookmarks" })  -- Telescope options

-- Get bookmark locations formatted for sidekick.nvim.
-- Returns bookmarks in sidekick-compatible format:
-- `- @/{path} :L{line} - "{note}"`
-- see :h haunt-sidekick for more info, and the sidekick section below
haunt_sk.get_locations()
haunt_sk.get_locations({current_buffer = true})

--- Change the data directory and reload all bookmarks.
---
--- Saves current bookmarks to the old data_dir, clears all visual elements,
--- then loads bookmarks from the new location and restores visuals.
--- This is useful for autocommands that need to switch bookmark contexts.
haunt.change_data_dir("~/projects/myproject/.bookmarks/")
haunt.change_data_dir(nil) -- reset to default
```

### User Commands

Or you can use the user commands: 
`HauntAnnotate`
`HauntClear`
`HauntClearAll`
`HauntDelete`
`HauntList`
`HauntNext`
`HauntPrev`
`HauntQf`
`HauntQfAll`
`HauntChangeDataDir [path]`

It should be pretty obvious what these do.

If you wanna script something with this plugin, take a look at `:h haunt`.
I tried my best to expose as many useful functions as possible.

## Integrations 

### Picker (snacks.nvim / telescope.nvim)

Search, edit, and delete annotations from the picker using `snacks.nvim` or `telescope.nvim`.

https://github.com/user-attachments/assets/da112d01-b0bc-445d-8d60-edc324c5f31b

By default, haunt.nvim uses `"auto"` mode which tries Snacks first, then Telescope, then falls back to `vim.ui.select`.

You can explicitly choose your picker:

``` lua
return {
  "TheNoeTrevino/haunt.nvim",
  opts = {
    -- Choose your picker: "auto", "snacks", or "telescope"
    picker = "auto",
    -- Customize picker keybindings (works for both Snacks and Telescope)
    picker_keys = {
      delete = {
        key = "d",
        mode = { "n" },
      },
      edit_annotation = {
        key = "a",
        mode = { "n" },
      },
    },
  },
}
```

**Picker actions:**
- `<CR>`: Jump to the selected bookmark
- `d` (normal mode): Delete the selected bookmark
- `a` (normal mode): Edit the bookmark's annotation

### sidekick.nvim

Send the position of your annotations to your favorite CLI tool through sidekick

https://github.com/user-attachments/assets/390c7301-757c-4248-9623-0300ff872376

Add this to your sidekick configuration:

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

### Git
Keep your annotations scoped to your branches.

https://github.com/user-attachments/assets/1d2b996c-b0be-459c-9ff0-63e7a1ebb936

### Project-Specific Bookmarks
Use `change_data_dir` to scope bookmarks per project/directory:

``` lua
vim.api.nvim_create_autocmd("DirChanged", {
  callback = function()
    local project_bookmarks = vim.fn.getcwd() .. "/.bookmarks/"
    require("haunt.api").change_data_dir(project_bookmarks)
  end,
})
```

## Why?

I have tried all the bookmarking plugins out there, and none of them really fit my workflow.
The specific issues I kept having were: 
- Why is there a mark/bookmark here? Did I do that on purpose? Oh whatever...
- I wish I could fuzzy search the _semantic meaning of the mark_ that I would have in my head.
- I want to send the marks, with my annotations, to my AI assistant to help me with my daily workflow.
- On massive codebases, I wish these marks had a 'why' to them. 

The closest alternative I found was vim-bookmarks, but it is semi-broken, and the last commit was 5 years ago.
Time for modern alternative!

I hope this helps others with the same issues.

## Acknowledgements

- folke for snacks.nvim and sidekick.nvim. I use these plugins hundreds of times a day and they are amazing
  * The API was extremely easy to work with. I also stole his CI/CD for my tests
- nvim-telescope team for telescope.nvim
- echasnovski for the mini.docs template. Having a way to automatically generate documentation from annotations
  is a lifesaver
  
## Similar Plugins

- [harpoon.nvim](https://github.com/ThePrimeagen/harpoon)
- [spelunk.nvim](https://github.com/EvWilson/spelunk.nvim)
- [marks.nvim](https://github.com/chentoast/marks.nvim)
- [vim-bookmarks](https://github.com/MattesGroeger/vim-bookmarks)

<details>

<summary>Possible Improvement</summary>

- [ ] Users should be able to toggle notification. add a 'notify' option to config.
this can take in a boolean, or a logging level. then, in the program, we can use
a custom logger that uses vim.notify. we are gonna wanna use closure to store the log level and avoid recomputes
- [ ] Integration for fzf-lua?

</details>
