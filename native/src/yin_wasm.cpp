// Plain C interface to the YIN detector for WebAssembly (no JS glue, no
// Emscripten runtime): the web pitch worklet instantiates yin.wasm directly.
//
//   handle = yin_create(sample_rate, hop)
//   in     = yin_input(handle)          // float* to write up to YIN_BLOCK samples
//   count  = yin_push(handle, n)        // analyze n samples from `in`
//   out    = yin_output(handle)         // count x [time, hz, confidence, rms]
//
// Built only for the web (tools/build_wasm.sh); the GDExtension uses yin.h directly.
#ifdef __EMSCRIPTEN__

#include <cstdint>
#include <vector>

#include "yin.h"

namespace {
constexpr int kBlock = 4096;  // max samples per push

struct Handle {
	solfege::Yin yin;
	float input[kBlock];
	std::vector<float> output;
	std::vector<solfege::PitchEstimate> scratch;
	Handle(double rate, int hop) : yin(rate, hop) {}
};
}  // namespace

extern "C" {

__attribute__((used)) void *yin_create(double sample_rate, int hop) {
	return new Handle(sample_rate, hop);
}

__attribute__((used)) float *yin_input(void *h) {
	return static_cast<Handle *>(h)->input;
}

__attribute__((used)) int yin_block_size() {
	return kBlock;
}

__attribute__((used)) int yin_push(void *h, int n) {
	auto *s = static_cast<Handle *>(h);
	s->scratch.clear();
	if (n > kBlock) n = kBlock;
	s->yin.push(s->input, static_cast<size_t>(n), s->scratch);
	s->output.resize(s->scratch.size() * 4);
	for (size_t i = 0; i < s->scratch.size(); ++i) {
		s->output[i * 4 + 0] = static_cast<float>(s->scratch[i].time);
		s->output[i * 4 + 1] = s->scratch[i].frequency;
		s->output[i * 4 + 2] = s->scratch[i].confidence;
		s->output[i * 4 + 3] = s->scratch[i].rms;
	}
	return static_cast<int>(s->scratch.size());
}

__attribute__((used)) float *yin_output(void *h) {
	return static_cast<Handle *>(h)->output.data();
}

__attribute__((used)) void yin_destroy(void *h) {
	delete static_cast<Handle *>(h);
}

}  // extern "C"

#endif  // __EMSCRIPTEN__
