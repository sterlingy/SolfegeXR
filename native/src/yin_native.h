// Godot binding for the YIN detector. Exposed to GDScript as class "YinNative".
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <memory>

#include "yin.h"

namespace godot {

class YinNative : public RefCounted {
	GDCLASS(YinNative, RefCounted)

public:
	// Offline: analyze a whole buffer. Returns [time, hz, conf, rms] * n, flat.
	PackedFloat32Array analyze(const PackedFloat32Array &samples, double sample_rate, int hop);

	// Streaming (native mic input later): configure once, then push blocks.
	void configure(double sample_rate, int hop);
	PackedFloat32Array push(const PackedFloat32Array &samples);
	void reset();

protected:
	static void _bind_methods();

private:
	std::unique_ptr<solfege::Yin> stream_;
};

}  // namespace godot
