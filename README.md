# CodisIDE

CodisIDE is a Godot-based embedded development environment for Arduino-style firmware workflows. It combines a lightweight IDE UI, board and library management, compile and upload tooling, serial monitoring, and optional local/online AI assistance in one project.

The project is designed to feel like a cross-platform maker IDE while keeping a Godot editor-first workflow. It includes a Godot editor plugin so the IDE can be launched directly from the editor, plus native serial extension support for real board communication on desktop and mobile targets.

## Highlights

- Code editor for sketches and project files
- Board selection and library management
- Compile and upload workflows for connected devices
- Serial monitor and serial plotter views
- Offline-first AI workflow with local model support and cloud providers
- Godot editor plugin to open the app data folder or launch the IDE
- Native addon support for serial and platform-specific integrations
- CMake-based build pipeline for desktop and Android artifacts

## Project goal

CodisIDE aims to provide a practical, self-contained workflow for hardware projects:

- manage sketches, boards, and libraries
- compile firmware from the same app
- upload over serial or other supported backends
- inspect runtime output and device logs
- optionally use AI to help with code generation and debugging

## Repository layout

```text
.
├── addons/
│   ├── codis_ide/              # Godot plugin that adds IDE launcher entries
│   └── codis_serial/           # Native serial GDExtension and related docs
├── android/                    # Android-specific build scaffolding
├── build/                      # Generated CMake build outputs
├── CodisIDE/                   # Main Godot project source for the IDE UI and scripts
│   ├── assets/
│   ├── scenes/
│   ├── scripts/
│   └── tests/
├── scripts/                    # Build and packaging automation scripts
├── CMakeLists.txt              # Top-level CMake project definition
├── project.godot               # Godot project configuration
├── export_presets.cfg          # Export setup for packaged builds
├── build.bat                   # Build helper script
├── new.bat                     # Quick project bootstrap helper
├── icon.svg                    # Project icon
├── README.md                   # This file
└── dist/                       # Built package artifacts
```

## Main runtime components

- `CodisIDE/scripts/IDE.gd` — central app manager and filesystem setup
- `CodisIDE/scripts/main_control.gd` — main IDE window, tabs, menus, and actions
- `CodisIDE/scripts/code_editor.gd` — editor behavior and sketch handling
- `CodisIDE/scripts/upload/` — upload backend implementations
- `CodisIDE/scripts/ai/` — AI provider integrations and model access
- `addons/codis_ide/plugin.gd` — editor plugin that can launch the IDE from Godot
- `addons/codis_serial/` — native serial backend for true USB/serial support

## Features in practice

### IDE workflow

The app keeps its data under a user-facing directory such as:

- `Documents/CodisGames/CodisIDE` on desktop
- `user://CodisGames/CodisIDE` when a sandboxed/mobile environment is required

This folder stores:

- `Codes/` for sketch files
- `Boards/` for board metadata and related assets
- `Libraries/` for library content
- `AI/Models/` for downloaded models
- `Saves/` for persistent app data

### Upload and hardware support

CodisIDE includes upload backend abstractions so it can work with different protocols and native integrations. The serial extension is optional but useful for real hardware flashing and port enumeration where the Godot core engine lacks native serial support.

### AI assistance

The project supports both:

- local inference via local model endpoints
- cloud providers such as Gemini/OpenAI-compatible services

This makes the app usable in offline-first local workflows or cloud-backed development setups.

## Build and run

### Requirements

- Godot 4.7.2 (CI pins the editor and matching export templates)
- CMake and Ninja for native builds
- A C++ toolchain for your platform
- For Windows native builds: Visual Studio 2022 C++ tools
- For Android builds: Android NDK and related build setup

### Run the project in Godot

1. Open the repository root in Godot.
2. Import the project or open `project.godot`.
3. Run the main scene from the Godot editor.

### Native build scripts

The repository includes scripts for common build paths:

- `build.bat` — primary Windows build entry
- `scripts/build_windows.ps1` — Windows MSVC build helper
- `scripts/build_local.sh` — local Linux build helper
- `scripts/build_android.sh` — Android native build helper
- `scripts/build_macos.sh` — macOS build helper

The CMake project is flexible and auto-discovers native source trees under the `src`, `modules`, `addons`, and `thirdparty` areas when present.

## Notes on native addons

The project is intentionally structured to support both pure Godot scripting and native extensions. The serial add-on lives under `addons/codis_serial/` and is designed to provide Godot-facing APIs for port discovery, device access, and flashing flows when a native driver is present.

## Cross-platform builds

The GitHub Actions workflow builds CodisIDE on every push to `main`, pull request,
and manual run. Its SCons build matrix is adapted from
[godot-plus-plus](https://github.com/nikoladevelops/godot-plus-plus).
The existing app and serial extension sources are preserved.

| Target | App artifact | Native serial |
| --- | --- | --- |
| Windows x86_64 | EXE and PCK | Yes |
| Linux x86_64 | Executable and PCK | Yes |
| macOS Intel + Apple Silicon | Universal app ZIP, unsigned | Yes |
| Android arm64 | Unsigned APK | Device-node backend; requires OS access |
| iOS arm64 | Xcode project ZIP | No |
| Web | HTML, JavaScript, WASM and PCK | No |

Download artifacts from the repository's Actions tab. Push a `v*` tag to publish
all successful app artifacts as a GitHub Release. iOS artifacts require an Apple
team, provisioning and signing in Xcode before installation. Replace the
`REPLACEME0` team placeholder in the generated Xcode project with your Apple team. Android release
APKs require signing before installation. macOS packages are unsigned and not
notarized. Web needs an HTTP server; browser sandboxes restrict local tools,
filesystem access and serial devices. Export support does not imply full desktop
firmware compilation/upload functionality on sandboxed platforms.

Clone with `git clone --recurse-submodules` to fetch the pinned godot-cpp bindings.
Build the native extension in `addons/codis_serial/native` using SCons, for example:

```sh
python -m pip install scons==4.8.1
python -m SCons platform=linux arch=x86_64 target=template_debug api_version=4.7
python -m SCons platform=linux arch=x86_64 target=template_release api_version=4.7
```

Use the matching Godot 4.7.2 editor/export templates and configure the Android SDK
in Godot for Android exports. The `ci_export.py` helper prepares a **disposable
checkout** (it removes optional Ziva editor tooling) and exports the chosen preset:

```sh
python scripts/ci_export.py Linux --godot /path/to/godot
```

Ziva is optional editor tooling. Its large platform binaries are excluded from
source control and runtime packages. To enable it locally, install its dependencies
and copy `ziva_agent.gdextension.example` to `ziva_agent.gdextension`.

## License

MIT; see [LICENSE](LICENSE). Bundled third-party addons and godot-cpp retain their
own licenses.
