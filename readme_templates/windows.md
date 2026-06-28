# {{PRODUCT_NAME}} for Windows

This archive contains the {{EDITION}} of Addivox for Windows.
{{DEMO_LIMITATIONS}}
Full documentation is available here:
https://rrwick.github.io/Addivox/

After unzipping this archive, you should see several {{PRODUCT_NAME}} files:
`{{EXE_NAME}}`, `{{CLAP_NAME}}` and `{{VST3_NAME}}`.

You do not need to install every file. `{{EXE_NAME}}` is the standalone version, which runs by itself. The other files are plugin formats, which are loaded inside a DAW such as Ableton Live, Cubase or REAPER.


### Standalone app

`{{EXE_NAME}}` is self-contained. Move it anywhere convenient and optionally create a shortcut to it. You can then open {{PRODUCT_NAME}} by double-clicking the executable or shortcut. Addivox for Windows is not code-signed, so Windows SmartScreen or antivirus software may warn you the first time you open it.

For live playing, the standalone application may need a low-latency Windows audio driver. ASIO is usually recommended when available. See the Addivox documentation for more details.


### Plugins

Copy the plugin files you need to the matching folder below.

| File | Format | Per-user install location | All-users install location | Example DAWs |
| --- | --- | --- | --- | --- |
| `{{VST3_NAME}}` | VST3 | `%LOCALAPPDATA%\Programs\Common\VST3` | `C:\Program Files\Common Files\VST3` | Ableton Live, Cubase, REAPER, Studio One |
| `{{CLAP_NAME}}` | CLAP | `%LOCALAPPDATA%\Programs\Common\CLAP` | `C:\Program Files\Common Files\CLAP` | Bitwig Studio, REAPER |

For VST3, copy the complete `{{VST3_NAME}}` directory, not just the file inside it. For CLAP, copy the `{{CLAP_NAME}}` file.

If you are not sure which plugin format to install, start with `{{VST3_NAME}}` for most modern DAWs. Use `{{CLAP_NAME}}` if your DAW supports CLAP and you prefer that format.

After copying plugins, quit and reopen your DAW. Some DAWs scan new plugins automatically. Others have a plugin manager or preferences page where you can rescan plugins. If you installed more than one format, your DAW may show {{PRODUCT_NAME}} more than once, for example as both a VST3 and a CLAP plugin.


### Windows compatibility

{{PRODUCT_NAME}} is built as a 64-bit Windows app/plugin. It is developed and tested on Windows 11 but should also work on Windows 10.

Very old versions of Windows, 32-bit DAWs and 32-bit plugin formats are not supported.
