# Addivox-build

Private release/build tooling for Addivox.

This repository is expected to sit next to the main Addivox repository:

```text
Addivox_repos/
  Addivox/
  Addivox-build/
```

`build_mac.sh` reads source files, Xcode projects, docs, and the `iPlug2` submodule from `../Addivox`, while all generated release artifacts are written under this repository's `build/` directory.

## Documentation build

```sh
./build_docs.sh
```

`build_docs.sh` builds the MkDocs source from `../Addivox/docs` and writes the generated site to `docs/`.

The script accepts `ADDIVOX_REPO_DIR` if the main repository is not checked out at `../Addivox`:

```sh
ADDIVOX_REPO_DIR=/path/to/Addivox ./build_docs.sh
```

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
- `build/AddivoxDemo_v*_macOS.zip`
- `build/mac-release/logs/`

## Windows release build

Run from Git Bash on Windows:

```sh
./build_windows.sh
./build_windows.sh --clean
./build_windows.sh --install
```

The script builds the x64 Release standalone, VST3, and CLAP targets. It locates
MSBuild through Visual Studio's `vswhere.exe`; set `PLATFORM_TOOLSET` to override
the default `v145` toolset.

Main outputs:

- `build/dist/full/windows/Addivox.exe`
- `build/dist/full/windows/Addivox.vst3/`
- `build/dist/full/windows/Addivox.clap`
- `build/dist/full/windows/factory_patches/`
- `build/windows-release/logs/`
