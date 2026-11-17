// SolfegeApp pitch detector: YIN (de Cheveigné & Kawahara 2002).
//
// Plain C++17 with no Godot types, so this one file compiles to:
//   - native code (GDExtension: Windows/Android/XR), via yin_native.cpp
//   - WebAssembly (Emscripten), to replace web/pitch_worklet.js later
// Same parameters as the JS worklet and the GDScript YinDetector, so scoring
// is identical everywhere.
#pragma once

#include <cstddef>
#include <vector>

namespace solfege {

struct PitchEstimate {
	double time;       // seconds: end of the analyzed span
	float frequency;   // Hz
	float confidence;  // 0..1
	float rms;         // input loudness
};

class Yin {
public:
	static constexpr int kTargetRate = 24000;
	static constexpr int kWindow = 512;
	static constexpr int kHop = 128;
	static constexpr float kMinHz = 70.0f;
	static constexpr float kMaxHz = 1200.0f;
	static constexpr float kThreshold = 0.15f;

	explicit Yin(double input_rate, int hop = kHop);

	// Streaming: feed input-rate samples; returns estimates produced (appended to out).
	void push(const float *samples, size_t count, std::vector<PitchEstimate> &out);
	void reset();

	double analysis_rate() const { return rate_; }

private:
	PitchEstimate analyze_at(const float *x, double time);

	int decim_;
	double rate_;
	int hop_;
	int tau_min_;
	int tau_max_;
	int span_;
	std::vector<float> ring_;   // doubled ring buffer: any span is contiguous
	std::vector<float> diff_;
	int write_ = 0;
	int filled_ = 0;
	int since_hop_ = 0;
	float accum_ = 0.0f;
	int accum_n_ = 0;
	long long decimated_count_ = 0;
};

}  // namespace solfege
