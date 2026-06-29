# Addivox-build

Private release/build tooling for Addivox.

This repository is expected to sit next to the main Addivox repository:

```text
Addivox_repos/
  Addivox/
  Addivox-build/
```

`build_mac.sh` reads source files, Xcode projects, docs, and the `iPlug2` submodule from `../Addivox`, while all generated release artifacts are written under this repository's `build/` directory.


## macOS release build

```sh
sudo ./build_mac.sh
sudo ./build_mac.sh --clean
sudo ./build_mac.sh --install
sudo ./build_mac.sh --sign_and_notarize
```

The script accepts `ADDIVOX_REPO_DIR` if the main repository is not checked out at `../Addivox`:

```sh
sudo ADDIVOX_REPO_DIR=/path/to/Addivox ./build_mac.sh
```

Main outputs:

- `build/dist/full/`
- `build/dist/demo/`
- `build/Addivox_v*_macOS.zip`
- `build/Addivox_v*_macOS.sha256`
- `build/AddivoxDemo_v*_macOS.zip`
- `build/AddivoxDemo_v*_macOS.sha256`
- `build/mac-release/logs/`


## Windows release build

Run from Git Bash on Windows:

```sh
./build_windows.sh
./build_windows.sh --clean
./build_windows.sh --install
```

The script builds full and demo variants of the x64 Release standalone, VST3, and CLAP targets, then creates versioned distribution ZIP files. It locates MSBuild through Visual Studio's `vswhere.exe`. Set `PLATFORM_TOOLSET` to override the default `v145` toolset. This private release script passes `/p:PlatformToolset=...` to MSBuild, so that value overrides the public `../Addivox/Addivox/projects/*.vcxproj` files, which currently default to `v143` for broader Visual Studio 2022 compatibility.

Main outputs:

- `build/dist/full/windows/Addivox.exe`
- `build/dist/full/windows/Addivox.vst3/`
- `build/dist/full/windows/Addivox.clap`
- `build/dist/demo/windows/AddivoxDemo.exe`
- `build/dist/demo/windows/AddivoxDemo.vst3/`
- `build/dist/demo/windows/AddivoxDemo.clap`
- `build/Addivox_v*_Windows.zip`
- `build/Addivox_v*_Windows.sha256`
- `build/AddivoxDemo_v*_Windows.zip`
- `build/AddivoxDemo_v*_Windows.sha256`
- `build/windows-release/logs/`
