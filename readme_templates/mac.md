# {{PRODUCT_NAME}} for macOS

This archive contains the {{EDITION}} of Addivox for macOS.
{{DEMO_LIMITATIONS}}
Full documentation is available here:
https://rrwick.github.io/Addivox/


## Included files

- `{{APP_NAME}}` - standalone application
- `{{COMPONENT_NAME}}` - Audio Unit v2 plugin
- `{{VST_NAME}}` - VST2 plugin
- `{{VST3_NAME}}` - VST3 plugin
- `{{CLAP_NAME}}` - CLAP plugin

You do not need to install every file. `{{APP_NAME}}` is the standalone version, which runs by itself and also contains the Audio Unit v3 plugin. The other files are additional plugin formats, which are loaded inside a DAW such as Logic Pro, GarageBand or Ableton Live.


## Standalone application

Copy `{{APP_NAME}}` to your Mac's main `/Applications` folder. In Finder, this is usually shown as **Applications** in the sidebar. macOS may ask for an administrator password when you copy the app there. You can then open {{PRODUCT_NAME}} from Launchpad, Spotlight or Finder.

If macOS shows a warning the first time you open {{PRODUCT_NAME}}, try right-clicking `{{APP_NAME}}` and choosing **Open**. macOS may then ask you to confirm that you want to open it.


## Audio Unit v3

The Audio Unit v3 version of {{PRODUCT_NAME}} is inside `{{APP_NAME}}`. This is normal for AUv3 plugins on macOS: the app acts as a container for a small app extension, and macOS makes that extension available to compatible DAWs.

To install the AUv3 version, copy `{{APP_NAME}}` to the main `/Applications` folder. This is the system-wide Applications folder, not a folder named `Applications` inside your home folder. There is no separate AUv3 file to copy into `Library/Audio/Plug-Ins`. After installing the app, quit and reopen your DAW. If {{PRODUCT_NAME}} does not appear, open `{{APP_NAME}}` once, then quit and reopen your DAW again.

Do not remove `{{APP_NAME}}` after the AUv3 plugin appears in your DAW. If you move the app to a different location or delete it, macOS may no longer be able to find the AUv3 plugin.


## Plugins

Copy the plugin files you need to the matching folder below. The `~` symbol means your home folder.

| File | Format | Install location | Example DAWs |
| --- | --- | --- | --- |
| `{{APP_NAME}}` | Audio Unit v3 | `/Applications` | Logic Pro, GarageBand, MainStage |
| `{{COMPONENT_NAME}}` | Audio Unit v2 | `~/Library/Audio/Plug-Ins/Components/` | Logic Pro, GarageBand, Ableton Live, REAPER |
| `{{VST3_NAME}}` | VST3 | `~/Library/Audio/Plug-Ins/VST3/` | Ableton Live, Cubase, REAPER, Studio One |
| `{{VST_NAME}}` | VST2 | `~/Library/Audio/Plug-Ins/VST/` | Ableton Live, REAPER |
| `{{CLAP_NAME}}` | CLAP | `~/Library/Audio/Plug-Ins/CLAP/` | Bitwig Studio, REAPER |

If you are not sure which plugin format to install, start with `{{APP_NAME}}` for Logic Pro, GarageBand or MainStage, and `{{VST3_NAME}}` for most other modern DAWs. `{{COMPONENT_NAME}}` and `{{VST_NAME}}` are mainly useful for older DAWs.

The `Library` folder inside your home folder is hidden by default. To open one of these folders in Finder:

1. Open Finder.
2. Choose **Go** > **Go to Folder...** from the menu bar.
3. Paste the install location from the table above.
4. Press Return.
5. Create the folder if it does not already exist, then copy the {{PRODUCT_NAME}} plugin file into it.

After copying plugins, quit and reopen your DAW. Some DAWs scan new plugins automatically. Others have a plugin manager or preferences page where you can rescan plugins. If you installed more than one format, your DAW may show {{PRODUCT_NAME}} more than once, for example as both an Audio Unit and a VST3.


## Intel and Apple Silicon Macs

{{PRODUCT_NAME}} is built as a 64-bit macOS app/plugin and is intended to work on both older Intel Macs and newer Apple Silicon Macs. There is no separate Intel download or Apple Silicon download; use the same files from this archive.

All of the included formats can be used on Intel or Apple Silicon Macs, provided your DAW supports that plugin format:

- `{{APP_NAME}}`
- `{{COMPONENT_NAME}}`
- `{{VST3_NAME}}`
- `{{VST_NAME}}`
- `{{CLAP_NAME}}`

On an Intel Mac, use {{PRODUCT_NAME}} normally. On an Apple Silicon Mac, {{PRODUCT_NAME}} can run natively in Apple Silicon DAWs. It can also be used from Intel-only DAWs running under Rosetta, provided the DAW supports the plugin format you installed.

{{PRODUCT_NAME}} requires macOS 10.13 High Sierra or newer. Very old 32-bit DAWs and 32-bit plugin formats are not supported.
