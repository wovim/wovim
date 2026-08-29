<h1 align="center">
  <img src="./logo.png" alt="wovim" width="120" height="120">

  wovim

  <a href="https://neovim.io/doc/">Documentation</a>
</h1>

<p align="center"><sub>Logo photo: <a href="https://www.flickr.com/photos/usfwspacific/25613160093/">barn owl, USFWS Pacific Region</a> (public domain)</sub></p>

[![Coverity Scan analysis](https://scan.coverity.com/projects/wovim-wovim/badge.svg)](https://scan.coverity.com/projects/wovim-wovim)
[![Downloads](https://img.shields.io/github/downloads/wovim/wovim/total.svg?maxAge=2592001)](https://github.com/wovim/wovim/releases/)

wovim is a fork of [Neovim](https://neovim.io/), tracking upstream, that seeks to aggressively refactor [Vim](https://www.vim.org/) in order to:

- Simplify maintenance and encourage [contributions](CONTRIBUTING.md)
- Split the work between multiple developers
- Enable [advanced UIs] without modifications to the core
- Maximize [extensibility](https://neovim.io/doc/user/api-ui-events.html#api-ui-events)

See the [Introduction](https://github.com/neovim/neovim/wiki/Introduction) wiki page and [Roadmap]
for more information.

Features
--------

- Modern [GUIs](https://github.com/neovim/neovim/wiki/Related-projects#gui)
- [API access](https://github.com/neovim/neovim/wiki/Related-projects#api-clients)
  from any language including C/C++, C#, Clojure, D, Elixir, Go, Haskell, Java/Kotlin,
  JavaScript/Node.js, Julia, Lisp, Lua, Perl, Python, Racket, Ruby, Rust
- Embedded, scriptable [terminal emulator](https://neovim.io/doc/user/terminal.html)
- Asynchronous [job control](https://github.com/neovim/neovim/pull/2247)
- [Shared data (shada)](https://github.com/neovim/neovim/pull/2506) among multiple editor instances
- [XDG base directories](https://github.com/neovim/neovim/pull/3470) support
- Compatible with most Vim plugins, including Ruby and Python plugins

See [`:help nvim-features`][nvim-features] for the full list, and [`:help news`][nvim-news] for noteworthy changes in the latest version!

Install from source
-------------------

See [BUILD.md](./BUILD.md) and [supported platforms](https://neovim.io/doc/user/support.html#supported-platforms) for details.

The build is CMake-based, but a Makefile is provided as a convenience.
After installing the dependencies, run the following command.
```bash
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
```

To install to a non-default location:
```bash
make CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_INSTALL_PREFIX=/full/path/
make install
```

CMake hints for inspecting the build:

- `cmake --build build --target help` lists all build targets.
- `build/CMakeCache.txt` (or `cmake -LAH build/`) contains the resolved values of all CMake variables.
- `build/compile_commands.json` shows the full compiler invocations for each translation unit.

Transitioning from Vim
--------------------

See [`:help nvim-from-vim`](https://neovim.io/doc/user/nvim.html#nvim-from-vim) for instructions.

Project layout
--------------

    ├─ cmake/           CMake utils
    ├─ cmake.config/    CMake defines
    ├─ cmake.deps/      subproject to fetch and build dependencies (optional)
    ├─ runtime/         plugins and docs
    ├─ src/nvim/        application source code (see src/nvim/README.md)
    │  ├─ api/          API subsystem
    │  ├─ eval/         Vimscript subsystem
    │  ├─ event/        event-loop subsystem
    │  ├─ generators/   code generation (pre-compilation)
    │  ├─ lib/          generic data structures
    │  ├─ lua/          Lua subsystem
    │  ├─ msgpack_rpc/  RPC subsystem
    │  ├─ os/           low-level platform code
    │  └─ tui/          built-in UI
    └─ test/            tests (see test/README.md)

License
-------

Neovim contributions since [b17d96][license-commit] are licensed under the
Apache 2.0 license, except for contributions copied from Vim (identified by the
`vim-patch` token). See [LICENSE.txt](./LICENSE.txt) for details.

[license-commit]: https://github.com/neovim/neovim/commit/b17d9691a24099c9210289f16afb1a498a89d803
[nvim-features]: https://neovim.io/doc/user/vim_diff.html#nvim-features
[nvim-news]: https://neovim.io/doc/user/news.html
[Roadmap]: https://neovim.io/roadmap/
[advanced UIs]: https://github.com/neovim/neovim/wiki/Related-projects#gui

<!-- vim: set tw=80: -->
