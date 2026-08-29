You can build wovim from [source](#install-from-source) in a few minutes.

---

- To start wovim, run `wovim`.
    - [Discover plugins](https://github.com/neovim/neovim/wiki/Related-projects#plugins).
- Before upgrading to a new version, **check [Breaking Changes](https://neovim.io/doc/user/news.html#news-breaking)** (tracked from upstream Neovim).
- For config (vimrc) see [the FAQ](https://neovim.io/doc/user/faq.html#faq-general).

---

Install from source
====================

wovim isn't packaged for any distro or package manager yet — building from source is the only supported path right now. See [BUILD.md](./BUILD.md) for details. If you have the [prerequisites](./BUILD.md#build-prerequisites) then building is easy:
```bash
make CMAKE_BUILD_TYPE=Release
sudo make install
```

For Unix-like systems this installs to `/usr/local`, while for Windows to `C:/Program Files`. Note, however, that this can complicate uninstallation. The following example avoids this by isolating an installation under `$HOME/wovim`:
```bash
rm -r build/  # clear the CMake cache
make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/wovim"
make install
export PATH="$HOME/wovim/bin:$PATH"
```

## Uninstall

There is a CMake target to _uninstall_ after `make install`:

```bash
sudo cmake --build build/ --target uninstall
```

Alternatively, just delete the `CMAKE_INSTALL_PREFIX` artifacts:

```bash
sudo rm /usr/local/bin/wovim
sudo rm -r /usr/local/share/nvim/
```
