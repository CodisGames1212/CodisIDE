# CodisSerial — native USB/serial GDExtension

CodisIDE uploads sketches through **plugins** (`res://CodisIDE/scripts/upload/`).
One of those plugins, `SerialUploader`, talks to a native driver named
`CodisSerial`. This folder contains that driver's source.

You do **not** need it to use the IDE: the project runs cleanly without it and
`SerialUploader` simply hides itself. It exists because Godot core has no
serial-port API, so real USB uploads — especially **Android USB On-The-Go** —
must go through native code.

## What it provides

| GDScript call | Purpose |
| --- | --- |
| `CodisSerial.list_ports()` | Enumerate serial ports (`COM*`, `/dev/ttyUSB*`, …) |
| `CodisSerial.open(port, baud)` | Open a port |
| `CodisSerial.write(bytes)` | Write raw bytes |
| `CodisSerial.read(max_bytes)` | Read available bytes |
| `CodisSerial.close()` | Close the port |
| `CodisSerial.flash(fqbn, port, payload)` | Flash a compiled image (bootloader hook) |

When present, CodisIDE shows the **“USB / Serial (native driver)”** backend in
the Upload menu and Settings ▸ Upload.

## Building (Windows)

From the repository root, run `scripts/build_all.bat`. This builds Windows
debug/release with MSVC, Linux x86_64 debug/release with WSL, and Android
arm64/arm32 debug/release with the configured Windows-host NDK. The build also
packages the finished binaries into `dist/codis_serial_artifacts.zip`. CMake
generates and links the checked-out `godot-cpp` bindings automatically.

The extension libraries are written under `addons/codis_serial/bin/` using
the filenames in `codis_serial.gdextension.example`.

## Building (Linux)

Run `bash scripts/build_local.sh` from WSL or a Linux host with CMake, Ninja, a
C++ compiler, and Python installed to build both debug and release libraries.

## Building (Android, USB OTG)

```bash
export ANDROID_NDK_ROOT=/path/to/android-ndk
bash scripts/build_android.sh
```

By default this builds `arm64-v8a` and `armeabi-v7a`; set `ANDROID_ABIS` to a
space-separated ABI list to select other supported Android ABIs.

## Building (macOS)

On a Mac with Xcode command-line tools, run `bash scripts/build_macos.sh`. It creates
a universal arm64/x86_64 release library by default; set `MACOS_ARCHS` to change
the architecture list. macOS builds cannot be produced on Windows because the
Apple SDK and linker are required.

> **Android USB note.** `list_ports()/open()` work out of the box on Linux
> desktop and on rooted/`tty`-exposed devices. On stock Android, USB serial
> requires the **Android USB Host API** (`UsbManager`, `UsbDeviceConnection`),
> reached from C++ through JNI. Wire that into `CodisSerial::open()` /
> `list_ports()` using the app's `ANativeActivity` — the method signatures
> above are the only contract the GDScript side cares about, so the Java side
> is free to change.

## Enabling

After building the desired platform libraries:

```bash
mv addons/codis_serial/codis_serial.gdextension.example \
   addons/codis_serial/codis_serial.gdextension
```

Restart the editor. `SerialUploader.is_available()` now returns true and the
backend appears in the IDE.