// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/core/result.hpp"
#include <string_view>

namespace openlf2 {
class ResourceSource {
public:
    virtual ~ResourceSource() = default;
    virtual Result<Bytes> read(std::string_view path) const = 0;
    // LF2 Darkfiren: stores `text` as the game file `path` (the saves file). Sources that cannot be written (an installer)
    // keep this default, and the caller falls back to its own storage.
    virtual Result<void> write(std::string_view, std::string_view) const {
        return fail(ErrorCode::unsupported, "this game data cannot be written");
    }
};
}
