# Contributing

> Development happens at https://git.thenoetrevino.com/noe.trevino/haunt.nvim.
> GitHub is a read-only mirror. Please open issues and pull requests there.

First of all, thank you for considering contributing to this project!

## Git Workflow

1. Fork the repository
2. Create your feature/bugfix branch: `git checkout -b feature-123/your-feature`
   a. The 123 numbers should represent the issue you are working on.
3. When committing, use the [conventional commit format](https://www.conventionalcommits.org/en/v1.0.0/).

- You can use the `git log` for examples of previous commit messages.
- Please try to have an understandable and followable commit history, open a new branch (don't PR changes from your main to the repository's main).

4. Open a PR to main

## Config for Local Development

Point to your local clone, this is with lazy.nvim:

```lua
return {
  dir = "~/haunt.nvim",
  ---@class HauntConfig
  opts = {
  ....
}
```

## Module Structure and Their Representations

`api.lua` - Main user facing API. If something is specifically meant for user consumption, it should go here.

`config.lua` - Any configuration options go here

`display.lua` - Logic having to do with displaying/hiding anything: signs, annotations, highlights

`init.lua` - Responsible for bootstrapping the plugin with as little overhead as possible

`navigation.lua` - Moving between annotations.

`persistence.lua` - Disk storage of bookmarks. This is the 'outside of neovim' module

`project.lua` - Project root, branch, and project-id detection, with cached git lookups/logic.

`picker.lua` - Picker integrations, currently that is [snacks.nvim](https://github.com/folke/snacks.nvim) and [telescope](https://github.com/nvim-telescope/telescope.nvim). We have each picker implement the `PickerModule` interface. This makes referencing the different picker much easier, and only gives us what we need. Unfortunately, each picker has a different `opts` structure. Which means we can't really type the `opts` well in `picker.show(opts?)`. Oh well.

`store.lua` - In memory operations on bookmarks

`sidekick.lua` - [Sidekick.nvim](https://github.com/folke/sidekick.nvim) integration

`restoration.lua` - Restoring annotations on buffer load

`utils.lua` - various helper functions.

`watcher.lua` - watching for changed in the `.git/HEAD` for event driven git branch updates.

Adhere to these separations as much as possible.

## Bookmark Positions: Read Through the Funnel

A bookmark's line number lives in two places, and they disagree:

- The **extmark** in the buffer is the truth while that buffer is loaded. Neovim
  moves it for you on every edit.
- `bookmark.line` is a **snapshot**. It is only authoritative for persistence and
  for buffers that aren't loaded (no extmark to ask).

So if you read `bookmark.line` straight off the store, you get wherever the
bookmark was when it was created, not where it is now. This was the cause of #72, #92, and
#99

The fix is `synced_bookmarks()` in `store.lua`. It is private, it loads and
syncs from extmarks unconditionally, and **every** public accessor goes through
it. If you're adding a getter to the store, read from `synced_bookmarks()` please, not
from the `bookmarks` array.

## Testing

If you are making significant changes, please consider adding tests.
We use [busted](https://github.com/lunarmodules/busted) for testing.

To run tests locally, you can use:

```bash
./scripts/test
```

You must run this script before opening a PR. It will save everyone time
