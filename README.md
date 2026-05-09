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
- `build/AddivoxDemo_v*_macOS.zip`
- `build/mac-release/logs/`

