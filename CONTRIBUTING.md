# Contributing

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

``` lua
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
`persistence.lua` - Disk storage of bookmarks, and git caching logic. This is the 'outside of neovim' module
`picker.lua` - Picker integrations, currently that is only [snacks.nvim](https://github.com/folke/snacks.nvim). 
`sidekick.lua` - [Sidekick.nvim](https://github.com/folke/sidekick.nvim) integration 
`restoration.lua` - Restoring annotations on buffer load
`store.lua` - In memory operations on bookmarks
`utils.lua` - various helper functions.

Adhere to these separations as much as possible.

## Testing 

If you are making significant changes, please consider adding tests.
We use [busted](https://github.com/lunarmodules/busted) for testing.

To run tests locally, you can use:
```bash
./scripts/test
```

You must run this script before opening a PR. It will save everyone time
