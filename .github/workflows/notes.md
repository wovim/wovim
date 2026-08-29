```
${NVIM_VERSION}
```

## Release notes

- [Changelog](https://github.com/wovim/wovim/commit/${NVIM_COMMIT}) (fixes + features)
- [News](./runtime/doc/news.txt) (`:help news` in Nvim)

## Install

### Windows

#### Zip

1. Download **wovim-win64.zip** (or **wovim-win-arm64.zip** for ARM)
2. Extract the zip
3. Run `wovim.exe` in your terminal

#### MSI

1. Download **wovim-win64.msi** (or **wovim-win-arm64.msi** for ARM)
2. Run the MSI
3. Run `wovim.exe` in your terminal

Note: On Windows "Server" you may need to [install `vcruntime*.dll`](https://neovim.io/doc/install/#windows).

### macOS (x86_64)

1. Download **wovim-macos-x86_64.tar.gz**
2. Run `xattr -c ./wovim-macos-x86_64.tar.gz` (to avoid "unknown developer" warning)
3. Extract: `tar xzvf wovim-macos-x86_64.tar.gz`
4. Run `./wovim-macos-x86_64/bin/wovim`

### macOS (arm64)

1. Download **wovim-macos-arm64.tar.gz**
2. Run `xattr -c ./wovim-macos-arm64.tar.gz` (to avoid "unknown developer" warning)
3. Extract: `tar xzvf wovim-macos-arm64.tar.gz`
4. Run `./wovim-macos-arm64/bin/wovim`

### Linux (x86_64)

If your system does not have the required glibc version, try the (unsupported) [builds for older glibc](https://github.com/neovim/neovim-releases).

#### AppImage

1. Download **wovim-linux-x86_64.appimage**
2. Run `chmod u+x wovim-linux-x86_64.appimage && ./wovim-linux-x86_64.appimage`
   - If your system does not have FUSE you can [extract the appimage](https://github.com/AppImage/AppImageKit/wiki/FUSE#type-2-appimage):
     ```bash
     ./wovim-linux-x86_64.appimage --appimage-extract
     ./squashfs-root/usr/bin/wovim
     ```

#### Tarball

1. Download **wovim-linux-x86_64.tar.gz**
2. Extract: `tar xzvf wovim-linux-x86_64.tar.gz`
3. Run `./wovim-linux-x86_64/bin/wovim`

### Linux (arm64)

#### AppImage

1. Download **wovim-linux-arm64.appimage**
2. Run `chmod u+x wovim-linux-arm64.appimage && ./wovim-linux-arm64.appimage`
   - If your system does not have FUSE you can [extract the appimage](https://github.com/AppImage/AppImageKit/wiki/FUSE#type-2-appimage):
     ```bash
     ./wovim-linux-arm64.appimage --appimage-extract
     ./squashfs-root/usr/bin/wovim
     ```

#### Tarball

1. Download **wovim-linux-arm64.tar.gz**
2. Extract: `tar xzvf wovim-linux-arm64.tar.gz`
3. Run `./wovim-linux-arm64/bin/wovim`
