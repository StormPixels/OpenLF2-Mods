// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
// Private to the SDL adapter: which decoder an image's bytes need. A sprite's resource name decides for `.png` names, but the
// built-in pictures are asked for without an extension (pe/menu_clip, pe/menu_back3) while resource.dat or lf2_exe/ may hold a
// PNG for them, so the bytes themselves are looked at too.

#include <cstddef>
#include <cstring>

namespace openlf2 {
// True when `data` starts with the 8 byte PNG signature.
inline bool starts_with_png_signature(const char* data, std::size_t size) {
    constexpr unsigned char signature[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    return data != nullptr && size >= sizeof signature && std::memcmp(data, signature, sizeof signature) == 0;
}
}
