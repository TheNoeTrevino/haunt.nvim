# Changelog

## [1.2.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v1.1.0...v1.2.0) (2026-05-11)


### Features

* add hook registry and event definitions ([00052f9](https://github.com/TheNoeTrevino/haunt.nvim/commit/00052f96c6d2740433fcc8a943e87ca800034156))
* emit hook events from bookmark lifecycle ([727df1b](https://github.com/TheNoeTrevino/haunt.nvim/commit/727df1bbeb0ef99b549505684ec9a3b9cbd82d4e))
* **plugin:** register :HauntReload command ([1e33bb8](https://github.com/TheNoeTrevino/haunt.nvim/commit/1e33bb8d342b29ce5843850607e37f00388aaeed))
* **store:** expose loaded storage path ([3b48573](https://github.com/TheNoeTrevino/haunt.nvim/commit/3b48573bdea8f3a4fd9dc9379c3d3233bd093434))
* **watcher:** auto-reload bookmarks on branch checkout ([640694f](https://github.com/TheNoeTrevino/haunt.nvim/commit/640694f31f852dc2a42d8d97a4b5263932ac00da))


### Bug Fixes

* **api:** roll back state when save fails during delete ([25a45b4](https://github.com/TheNoeTrevino/haunt.nvim/commit/25a45b44dce13abd660b4b9d4c11a508e0a3b62b))
* **hooks:** unregister once-wrapper before invoking user callback ([4eac63b](https://github.com/TheNoeTrevino/haunt.nvim/commit/4eac63be35fc41ac6668bfbc8f3b1668300ef7c7))
* **store:** load_bookmarks error handling ([31a971e](https://github.com/TheNoeTrevino/haunt.nvim/commit/31a971e55e4c6858c1f9f4a4bedcb1b5596b8376))
* **watcher:** clear watched gitdir when handle is closed ([7006993](https://github.com/TheNoeTrevino/haunt.nvim/commit/7006993616811b104058e13779e1f415b979f316))

## [1.1.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v1.0.0...v1.1.0) (2026-05-04)


### Features

* shell commands dont block startup ([530aa8e](https://github.com/TheNoeTrevino/haunt.nvim/commit/530aa8e663c9bfd8be6cb7a37b115daba8a474a0))
* shell commands dont block startup ([04ab7a0](https://github.com/TheNoeTrevino/haunt.nvim/commit/04ab7a0f34bcf818431e85acdf33246e92f49168))

## [1.0.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.8.1...v1.0.0) (2026-05-03)


### ⚠ BREAKING CHANGES

* **persistence:** existing v1 bookmark files no longer load directly; users must run :HauntMigrate to upgrade them to v2.
* **persistence:** 
* **persistence:** 

### Features

* **api:** add reload() helper for in-memory refresh from disk ([fc77bf1](https://github.com/TheNoeTrevino/haunt.nvim/commit/fc77bf1aade3da4725dcbec3f1a92f05e3acae4e))
* **api:** flag out-of-project bookmarks as absolute ([8487c50](https://github.com/TheNoeTrevino/haunt.nvim/commit/8487c50cdf17bb3ed3066575191bd97741d9429b))
* atmoic writes for bookmarks ([cd8967d](https://github.com/TheNoeTrevino/haunt.nvim/commit/cd8967db4a20895730d5d19cc07aab180b5b16b6))
* handle crossing projects ([6d9cf9b](https://github.com/TheNoeTrevino/haunt.nvim/commit/6d9cf9bb95d5fef910f02537d53bc12f2167586e))
* **migration:** add migration module for v1→v2 upgrade ([9572798](https://github.com/TheNoeTrevino/haunt.nvim/commit/9572798aa54c1f4e9d66c71c1cb2e053dd886f18))
* **migration:** detect pending v1 storage and reload after migrate ([475f355](https://github.com/TheNoeTrevino/haunt.nvim/commit/475f355e2bfd63c73ff555722b4d2390edc36de6))
* **persistence:** key storage path by git root commit hash ([f212643](https://github.com/TheNoeTrevino/haunt.nvim/commit/f212643e391d6ef0a6499ec844f95a3255416c94))
* **persistence:** load v2 storage; v1 prompts :HauntMigrate ([637fc13](https://github.com/TheNoeTrevino/haunt.nvim/commit/637fc13af8f8a362f168c4d6065383bcd066cad9))
* **persistence:** write v2 storage format with relative paths ([06b81ae](https://github.com/TheNoeTrevino/haunt.nvim/commit/06b81ae45b3a1e43efd9a2329659d20a820e833b))
* **plugin:** register :HauntMigrate command ([4642b6a](https://github.com/TheNoeTrevino/haunt.nvim/commit/4642b6ad6dfc0c2fdbe7bf819fc1a72bf214e21f))
* **project:** add project module for root and id detection ([1671cbe](https://github.com/TheNoeTrevino/haunt.nvim/commit/1671cbe4cff721499a9170f8764fa2d1fd4c922e))
* **utils:** add project-relative path helpers ([7a11fa0](https://github.com/TheNoeTrevino/haunt.nvim/commit/7a11fa045f8070dc3791259cc4d25532d4cc8cc2))


### Bug Fixes

* cache not catching cwd changes ([35b7f7f](https://github.com/TheNoeTrevino/haunt.nvim/commit/35b7f7f6fe7d34024cec0424f0a56e38ce50a23c))
* incorrect migration notification ([ebf7ec9](https://github.com/TheNoeTrevino/haunt.nvim/commit/ebf7ec91b2bc2d0f764cdbfdd0470f7c2994c2c3))
* lazily create directory ([6ffcdcc](https://github.com/TheNoeTrevino/haunt.nvim/commit/6ffcdcc3af04f4fff277137ac2db8d06a58bbc79))
* migrate if autocmd not triggered ([2de8ccb](https://github.com/TheNoeTrevino/haunt.nvim/commit/2de8ccb74cfbd9d715a6f8f061e11be13fb66c40))
* notify on save_bookmarks failure ([c1342a1](https://github.com/TheNoeTrevino/haunt.nvim/commit/c1342a196aeb6a4587575c00b0992eaa7569db9b))
* **setup:** apply custom data_dir synchronously ([1db443e](https://github.com/TheNoeTrevino/haunt.nvim/commit/1db443e8dad2f1044f67832b7fb4ab97ccd7c9c3))
* track bookmark line through edits ([#72](https://github.com/TheNoeTrevino/haunt.nvim/issues/72)) ([5ca350c](https://github.com/TheNoeTrevino/haunt.nvim/commit/5ca350ce7002eb9baf09c0c64dd317c7f384c925))

## [0.8.1](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.8.0...v0.8.1) (2026-02-23)


### Bug Fixes

* use cache instead of fetching ([740d664](https://github.com/TheNoeTrevino/haunt.nvim/commit/740d664987fd13eadf31d05511ce4090ec149c7e))
* use cache instead of fetching ([8d82b88](https://github.com/TheNoeTrevino/haunt.nvim/commit/8d82b88d50049803966089ee85574c1a22fd89be))

## [0.8.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.7.1...v0.8.0) (2026-02-05)


### Features

* annotation suffix ([1cf404c](https://github.com/TheNoeTrevino/haunt.nvim/commit/1cf404c8c82bd91b6f7b1f180daea3ae0a247976))


### Bug Fixes

* delayed window closing ([adba00a](https://github.com/TheNoeTrevino/haunt.nvim/commit/adba00a563f439f21ab3acc17de8262aab6030f6))
* highlights getting wiped when colorscheme changes ([92986ea](https://github.com/TheNoeTrevino/haunt.nvim/commit/92986ea27b9562bc19cc3c00f3af5c330bb0af13))
* highlights getting wiped when colorscheme changes ([2f067c7](https://github.com/TheNoeTrevino/haunt.nvim/commit/2f067c76d16b06fc32df27e18c6072b25bc137cb))

## [0.7.1](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.7.0...v0.7.1) (2026-01-28)


### Performance Improvements

* replace blocking ui write with aync write ([ef5d2d3](https://github.com/TheNoeTrevino/haunt.nvim/commit/ef5d2d346797042c569a2f6555218adde3cac6bf))
* replace blocking ui write with aync write ([9f225a9](https://github.com/TheNoeTrevino/haunt.nvim/commit/9f225a99c69a08af0e2508eac83e3415a3f2aa27))

## [0.7.0](https://github.com/TheNoeTrevino/haunt.nvim/compare/v0.6.1...v0.7.0) (2026-01-25)


### Features

* opt out of branch scoped bookmarks ([2c20d9a](https://github.com/TheNoeTrevino/haunt.nvim/commit/2c20d9ad87cfb437b91d653a5f4e3a844eb592dc))
* opt out of branch scoped bookmarks ([91bac92](https://github.com/TheNoeTrevino/haunt.nvim/commit/91bac92f8610daf71432331358639bbf0cf489e9))

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
