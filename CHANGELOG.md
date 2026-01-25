# Changelog

## [0.6.1](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.6.0...v0.6.1) (2026-01-25)


### Bug Fixes

* **persistence:** use commit hash for detached HEAD states ([8c259d9](https://github.com/TheNoeTrevino/haunt.nvim/commit/8c259d9bc62bd8c38ea6aeaed34be78d6e972168))
* **persistence:** use commit hash for detached HEAD states ([e982389](https://github.com/TheNoeTrevino/haunt.nvim/commit/e982389438f4904251f148f21b61149a9d2bdcaa))

## [0.6.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.5.0...v0.6.0) (2026-01-24)


### Features

* **picker:** add fzf-lua picker implementation ([30a3f9d](https://github.com/TheNoeTrevino/haunt.nvim/commit/30a3f9d86e201ad08a56cc35fde50d38a404a139))
* **picker:** add shared type definitions for picker interface ([4ca196f](https://github.com/TheNoeTrevino/haunt.nvim/commit/4ca196f4a81a511b20f02397408ef4d9f64cd64a))
* **telescope:** add documentation ([c2be0a5](https://github.com/TheNoeTrevino/haunt.nvim/commit/c2be0a5296d1489b73f47b688d19750fdb22f88d))
* **telescope:** add nain logic ([d82b87b](https://github.com/TheNoeTrevino/haunt.nvim/commit/d82b87b54c7706c2742c09b72cecd4f2a974912c))
* **telescope:** add nvim-web-devicon for telescope ([ef817b4](https://github.com/TheNoeTrevino/haunt.nvim/commit/ef817b49e0c45c88fb635b50e340266711992de7))
* **telescope:** add picker option ([3723fdd](https://github.com/TheNoeTrevino/haunt.nvim/commit/3723fdd383e2bb5fca0ebf5c73f973c1210c571b))
* **telescope:** split test ([9f36da8](https://github.com/TheNoeTrevino/haunt.nvim/commit/9f36da8e339f1a2ac0a5704f51e4824aaacdc8c5))
* **telescope:** update the inline style ([20ce805](https://github.com/TheNoeTrevino/haunt.nvim/commit/20ce8056aa0370728f0dec30a5c0710f4a12a525))


### Bug Fixes

* luacats diagnostics ([ddfa503](https://github.com/TheNoeTrevino/haunt.nvim/commit/ddfa50389fb75720f272e8238ab9369031f77d3f))


### Performance Improvements

* **picker:** cache path computations in build_picker_items ([46fd17e](https://github.com/TheNoeTrevino/haunt.nvim/commit/46fd17efac0fdb3696aba447ae2b08cfa97a0d64))

## [0.5.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.4.2...v0.5.0) (2026-01-23)


### Features

* add :HauntChangeDataDir user command ([84af480](https://github.com/TheNoeTrevino/haunt.nvim/commit/84af4808e84e864e14f822ce2444ddd9b64c3178))
* add change data dir during usage ([9ea50db](https://github.com/TheNoeTrevino/haunt.nvim/commit/9ea50db8c791fc63f3fb3953308fcd581ee690a4))
* **picker:** fall back to vim.ui.select if snacks.nvim is not available ([af0201b](https://github.com/TheNoeTrevino/haunt.nvim/commit/af0201b392b8f7dfb57cf6692da0e30ae5643a09))
* **picker:** fallback to vim.ui.select if snacks.nvim unavailable ([29a1080](https://github.com/TheNoeTrevino/haunt.nvim/commit/29a1080e7937d1de8cafe41f5f3f8de338fb8647))


### Bug Fixes

* add stackable .setups ([58c02e0](https://github.com/TheNoeTrevino/haunt.nvim/commit/58c02e0806ece378c8b0af7ae2627dea61a54a32))
* expand tilde and ensure trailing slash in set_data_dir ([208bc58](https://github.com/TheNoeTrevino/haunt.nvim/commit/208bc582dc9df96ee986bad7d1711feccf3bf20f))
* self assign workflow ([fc7ee83](https://github.com/TheNoeTrevino/haunt.nvim/commit/fc7ee83ae10bf8a5e48fd529ea8c06b318666105))
* self assign workflow ([cb6f0f2](https://github.com/TheNoeTrevino/haunt.nvim/commit/cb6f0f2492f18d734464d6aeee8334d6c0a3266d))
* **text:** check if vim.ui.select fallback is triggered properly ([92f25dc](https://github.com/TheNoeTrevino/haunt.nvim/commit/92f25dcc893009c077ed8d143135ab0a82cf5954))

## [0.4.2](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.4.1...v0.4.2) (2026-01-21)


### Bug Fixes

* ci ([5ca1ae7](https://github.com/TheNoeTrevino/haunt.nvim/commit/5ca1ae7d729a5e810d4f73cde6220792f7363884))
* ci ([bcb835e](https://github.com/TheNoeTrevino/haunt.nvim/commit/bcb835e9ab5898f567b1e9bb618f6c8dd9979c4b))
* readme ([0a53693](https://github.com/TheNoeTrevino/haunt.nvim/commit/0a53693991b9956ec4879d03fc1e755b621d3c16))
* stylua ([31c744c](https://github.com/TheNoeTrevino/haunt.nvim/commit/31c744c1761bc9a01df613269d6a2d0ef48d5719))

## [0.4.1](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.4.0...v0.4.1) (2026-01-21)


### Bug Fixes

* auto assign when its author ([ae2f00a](https://github.com/TheNoeTrevino/haunt.nvim/commit/ae2f00a145a709dacbce4d69653525bac4801a7b))
* remove duplicate function definitions ([b9ea1bd](https://github.com/TheNoeTrevino/haunt.nvim/commit/b9ea1bda4dc1aff727723db4830dd36d4e958f73))

## [0.4.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.3.0...v0.4.0) (2026-01-21)


### Features

* allow passing opts to picker.show to customize Snacks.picker ([14cdb15](https://github.com/TheNoeTrevino/haunt.nvim/commit/14cdb15d20127af933516588ae3b1546861c7134))

## [0.3.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.2.0...v0.3.0) (2026-01-21)


### Features

* add quickfix user commands ([6b9333c](https://github.com/TheNoeTrevino/haunt.nvim/commit/6b9333c9a74276e8cbffad4760acd39fb2412dd7))


### Bug Fixes

* [toggle](2026-01-23_toggle.md) quickfix when sent to quickfix ([209eef0](https://github.com/TheNoeTrevino/haunt.nvim/commit/209eef0a3c91f9391a91a7af26fde87d673fadd4))

## [0.2.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.1.0...v0.2.0) (2026-01-21)


### Features

* add quickfix list integration ([1961275](https://github.com/TheNoeTrevino/haunt.nvim/commit/19612753fdb5e91d778b1a4e28541195580a7016))
* add quickfix list integration ([1daa1c2](https://github.com/TheNoeTrevino/haunt.nvim/commit/1daa1c2827f26cfe91fbb03bad925939d3c19ae4))
* expose quickfix integration via api ([312fec9](https://github.com/TheNoeTrevino/haunt.nvim/commit/312fec9b984eddf8a529b1760a36fc64517d3557))
