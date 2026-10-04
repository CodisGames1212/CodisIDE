#include "register_types.h"

#include "codis_serial.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>

using namespace godot;

// Kept alive for the lifetime of the module so the singleton registration is
// valid. `SerialUploader` prefers the singleton but also falls back to
// ClassDB.instantiate("CodisSerial"), so the registration below is optional.
static CodisSerial *singleton = nullptr;

void initialize_codis_serial_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(CodisSerial);

	// Expose it as `Engine.get_singleton("CodisSerial")` for convenience.
	singleton = memnew(CodisSerial);
	Engine::get_singleton()->register_singleton("CodisSerial", singleton);
}

void uninitialize_codis_serial_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("CodisSerial");
	if (singleton) {
		memdelete(singleton);
		singleton = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT codis_serial_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_codis_serial_module);
	init_obj.register_terminator(uninitialize_codis_serial_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
