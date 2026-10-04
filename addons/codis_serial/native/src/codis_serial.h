#pragma once
#include <cstdint>

// CodisSerial — native serial-port driver for CodisIDE.
//
// Godot core exposes no serial-port API, so uploading over USB (including
// Android USB On-The-Go) needs a native module. This GDExtension implements the
// interface the GDScript `SerialUploader` looks for:
//
//   list_ports() -> PackedStringArray
//   open(port: String, baud: int) -> bool
//   write(data: PackedByteArray) -> int
//   read(max_bytes: int) -> PackedByteArray
//   close() -> void
//   is_open() -> bool
//   flash(fqbn: String, port: String, payload: PackedByteArray) -> bool
//
// `flash()` is the hook for a real bootloader implementation (STK500 for AVR,
// esptool protocol for ESP). The stub below documents where that goes.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class CodisSerial : public RefCounted {
	GDCLASS(CodisSerial, RefCounted)

	intptr_t _fd = -1;
	int _baud = 115200;

protected:
	static void _bind_methods();

public:
	CodisSerial();
	~CodisSerial();

	PackedStringArray list_ports() const;
	bool open(const String &p_port, int p_baud = 115200);
	int write(const PackedByteArray &p_data);
	PackedByteArray read(int p_max_bytes = 1024);
	void close();
	bool is_open() const;
	bool flash(const String &p_fqbn, const String &p_port, const PackedByteArray &p_payload);
};

} // namespace godot
