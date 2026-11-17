#include "yin.h"

#include <algorithm>
#include <cmath>

namespace solfege {

Yin::Yin(double input_rate, int hop) {
	decim_ = std::max(1, static_cast<int>(std::lround(input_rate / kTargetRate)));
	rate_ = input_rate / decim_;
	hop_ = std::max(1, hop);
	tau_min_ = std::max(2, static_cast<int>(std::floor(rate_ / kMaxHz)));
	tau_max_ = static_cast<int>(std::ceil(rate_ / kMinHz));
	span_ = kWindow + tau_max_ + 2;
	ring_.assign(static_cast<size_t>(span_) * 2, 0.0f);
	diff_.assign(static_cast<size_t>(tau_max_) + 2, 0.0f);
}

void Yin::reset() {
	std::fill(ring_.begin(), ring_.end(), 0.0f);
	write_ = filled_ = since_hop_ = accum_n_ = 0;
	accum_ = 0.0f;
	decimated_count_ = 0;
}

void Yin::push(const float *samples, size_t count, std::vector<PitchEstimate> &out) {
	for (size_t i = 0; i < count; ++i) {
		accum_ += samples[i];
		if (++accum_n_ < decim_) {
			continue;
		}
		const float s = accum_ / decim_;
		accum_ = 0.0f;
		accum_n_ = 0;
		ring_[write_] = s;
		ring_[write_ + span_] = s;
		write_ = (write_ + 1) % span_;
		++decimated_count_;
		if (filled_ < span_) {
			++filled_;
		}
		// The first analysis happens once the buffer is full; then every hop.
		if (filled_ == span_ && (decimated_count_ == span_ || ++since_hop_ >= hop_)) {
			since_hop_ = 0;
			out.push_back(analyze_at(&ring_[write_], decimated_count_ / rate_));
		}
	}
}

PitchEstimate Yin::analyze_at(const float *x, double time) {
	double sum_sq = 0.0;
	for (int i = 0; i < kWindow; ++i) {
		sum_sq += static_cast<double>(x[i]) * x[i];
	}
	const float rms = static_cast<float>(std::sqrt(sum_sq / kWindow));

	// Difference function.
	float *d = diff_.data();
	for (int tau = 1; tau <= tau_max_; ++tau) {
		float acc = 0.0f;
		const float *a = x;
		const float *b = x + tau;
		for (int i = 0; i < kWindow; ++i) {
			const float delta = a[i] - b[i];
			acc += delta * delta;
		}
		d[tau] = acc;
	}
	// Cumulative mean normalized difference.
	d[0] = 1.0f;
	double running = 0.0;
	for (int tau = 1; tau <= tau_max_; ++tau) {
		running += d[tau];
		d[tau] = running > 0.0 ? static_cast<float>(d[tau] * tau / running) : 1.0f;
	}
	// Absolute threshold, then walk down to the local minimum.
	int tau = -1;
	for (int t = tau_min_; t < tau_max_; ++t) {
		if (d[t] < kThreshold) {
			while (t + 1 < tau_max_ && d[t + 1] < d[t]) {
				++t;
			}
			tau = t;
			break;
		}
	}
	if (tau < 0) {
		tau = tau_min_;
		for (int t = tau_min_ + 1; t < tau_max_; ++t) {
			if (d[t] < d[tau]) {
				tau = t;
			}
		}
	}
	// Parabolic interpolation.
	double better = tau;
	if (tau > 1 && tau < tau_max_) {
		const double a = d[tau - 1], b = d[tau], c = d[tau + 1];
		const double denom = a + c - 2.0 * b;
		if (denom != 0.0) {
			better = tau + (a - c) / (2.0 * denom);
		}
	}
	PitchEstimate e;
	e.time = time;
	e.frequency = static_cast<float>(rate_ / better);
	e.confidence = std::clamp(1.0f - d[tau], 0.0f, 1.0f);
	e.rms = rms;
	return e;
}

}  // namespace solfege
