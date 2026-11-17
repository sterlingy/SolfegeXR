#include "yin_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <vector>

namespace godot {

static PackedFloat32Array flatten(const std::vector<solfege::PitchEstimate> &est) {
	PackedFloat32Array out;
	out.resize(static_cast<int64_t>(est.size()) * 4);
	float *w = out.ptrw();
	for (const auto &e : est) {
		*w++ = static_cast<float>(e.time);
		*w++ = e.frequency;
		*w++ = e.confidence;
		*w++ = e.rms;
	}
	return out;
}

PackedFloat32Array YinNative::analyze(const PackedFloat32Array &samples, double sample_rate, int hop) {
	solfege::Yin yin(sample_rate, hop);
	std::vector<solfege::PitchEstimate> est;
	yin.push(samples.ptr(), static_cast<size_t>(samples.size()), est);
	return flatten(est);
}

void YinNative::configure(double sample_rate, int hop) {
	stream_ = std::make_unique<solfege::Yin>(sample_rate, hop);
}

PackedFloat32Array YinNative::push(const PackedFloat32Array &samples) {
	if (!stream_) {
		return PackedFloat32Array();
	}
	std::vector<solfege::PitchEstimate> est;
	stream_->push(samples.ptr(), static_cast<size_t>(samples.size()), est);
	return flatten(est);
}

void YinNative::reset() {
	if (stream_) {
		stream_->reset();
	}
}

void YinNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("analyze", "samples", "sample_rate", "hop"), &YinNative::analyze, DEFVAL(128));
	ClassDB::bind_method(D_METHOD("configure", "sample_rate", "hop"), &YinNative::configure, DEFVAL(128));
	ClassDB::bind_method(D_METHOD("push", "samples"), &YinNative::push);
	ClassDB::bind_method(D_METHOD("reset"), &YinNative::reset);
}

}  // namespace godot
