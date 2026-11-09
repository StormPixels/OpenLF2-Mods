// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include <algorithm>
#include <cstdint>

namespace openlf2 {
class FrameClock {
public:
    static constexpr std::uint32_t normal_step = 33; // about 30.3 frames per second
    static constexpr std::uint32_t fast_step = 3;    // F5 fast mode, requested by scripts
    static constexpr std::uint32_t max_lag = 100;
    static constexpr std::uint32_t max_sleep = 5;

    // `normal` and `fast` are the milliseconds between frames (LF2 Darkfiren: system.dat fps_value and fps_value_f5);
    // a 0 is taken as the original's value.
    explicit FrameClock(std::uint32_t now, std::uint32_t normal = normal_step, std::uint32_t fast = fast_step)
        : scheduled_(now), normal_(normal == 0 ? normal_step : normal), fast_(fast == 0 ? fast_step : fast) {}

    // At most one frame per call, as each original loop iteration runs at most one.
    [[nodiscard]] bool due(std::uint32_t now, bool fast = false) {
        const auto step = current_step(fast);
        if (now - scheduled_ <= step) return false;
        const auto lag = std::max(max_lag, step * 2);
        if (now - scheduled_ > lag) scheduled_ = now - lag;
        scheduled_ += step;
        return true;
    }
    // Milliseconds the original sleeps before checking again (0 means poll immediately).
    [[nodiscard]] std::uint32_t sleep_ms(std::uint32_t now, bool fast = false) const {
        const auto step = current_step(fast);
        const auto wait = static_cast<std::int32_t>(scheduled_ - now + step);
        return wait <= 0 ? 0 : std::min(static_cast<std::uint32_t>(wait), max_sleep);
    }

    // LF2 Darkfiren slow motion at the end of a round: `extra` milliseconds are added to the frame step, the normal and
    // the F5 one alike (system.dat slow_power; the Darkfiren developer: it affects all modes and the F5 timer); 0 returns
    // to the normal steps.
    void set_slow(std::uint32_t extra) { slow_ = extra; }
private:
    std::uint32_t current_step(bool fast) const { return (fast ? fast_ : normal_) + slow_; }
    std::uint32_t scheduled_;
    std::uint32_t slow_ = 0;
    std::uint32_t normal_;
    std::uint32_t fast_;
};
}
