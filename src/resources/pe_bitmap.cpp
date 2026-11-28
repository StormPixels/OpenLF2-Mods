// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/installer.hpp"
#include "openlf2/core/binary.hpp"
#include "openlf2/resources/bitmap.hpp"
#include <optional>
#include <vector>

namespace openlf2 {
namespace {
class PeResources {
public:
    explicit PeResources(std::span<const char> bytes) : file_(bytes) {
        if (file_.text(0, 2) != "MZ") throw FormatError("not a PE executable");
        const std::size_t pe = file_.u32(0x3c);
        file_.slice(pe, 24);
        file_.slice(pe, 24 + std::size_t{file_.u16(pe + 20)});
        if (file_.text(pe, 4) != std::string("PE\0\0", 4) || file_.u16(pe + 24) != 0x10b ||
            file_.u16(pe + 20) < 120) throw FormatError("expected PE32 optional header");
        sections_ = pe + 24 + file_.u16(pe + 20);
        section_count_ = file_.u16(pe + 6);
        file_.slice(sections_, section_count_ * 40);
        image_base_ = file_.u32(pe + 24 + 28);
        const auto resource_rva = file_.u32(pe + 24 + 112);
        resource_size_ = file_.u32(pe + 24 + 116);
        root_ = file_offset(resource_rva, resource_size_);
    }
    // The DIB (header, palette, pixels) of a named bitmap resource.
    std::span<const char> bitmap(std::string_view requested) const {
        const auto type = child(0, 2, {});
        const auto name = child(type, std::nullopt, requested);
        const auto language = first_language(name);
        const BinaryView entry(resource_view(language, 16));
        const std::size_t size = entry.u32(4);
        return file_.slice(file_offset(entry.u32(0), size), size);
    }
    // The data of the first resource of `type` (RT_GROUP_ICON is 14), whatever its name and language.
    std::span<const char> first_resource(std::uint32_t type) const {
        const auto language = first_target(child(0, type, {}));
        return entry_data(first_target(language));
    }
    // The data of the RT_ICON resource with this id.
    std::span<const char> icon_resource(std::uint32_t id) const {
        const auto language = child(child(0, 3, {}), id, {});
        return entry_data(first_target(language));
    }
    // The virtual address of a file offset inside a section, if any.
    std::optional<std::uint32_t> address_of(std::size_t offset) const {
        for (std::size_t index = 0; index < section_count_; ++index) {
            const auto section = sections_ + index * 40;
            const std::size_t raw = file_.u32(section + 20);
            const std::size_t raw_size = file_.u32(section + 16);
            if (offset >= raw && offset - raw < raw_size) {
                return static_cast<std::uint32_t>(image_base_ + file_.u32(section + 12) + (offset - raw));
            }
        }
        return std::nullopt;
    }
    // Initialized data at a virtual address (backed by the file, not zero-filled BSS).
    std::span<const char> data(std::uint32_t address, std::size_t size) const {
        if (address < image_base_) throw FormatError("address below the image base");
        return file_.slice(file_offset(address - image_base_, size), size);
    }
private:
    std::size_t file_offset(std::uint32_t rva, std::size_t size) const {
        for (std::size_t index = 0; index < section_count_; ++index) {
            const auto section = sections_ + index * 40;
            const auto start = file_.u32(section + 12);
            const auto raw_size = file_.u32(section + 16);
            file_.slice(file_.u32(section + 20), raw_size);
            if (rva >= start && rva - start <= raw_size && size <= raw_size - (rva - start)) {
                const std::size_t offset = std::size_t{file_.u32(section + 20)} + (rva - start);
                file_.slice(offset, size);
                return offset;
            }
        }
        throw FormatError("resource RVA outside backed PE sections");
    }
    std::span<const char> resource_view(std::size_t offset, std::size_t size) const {
        if (offset > resource_size_ || size > resource_size_ - offset) {
            throw FormatError("resource directory offset outside section");
        }
        return file_.slice(root_ + offset, size);
    }
    std::size_t child(std::size_t directory, std::optional<std::uint32_t> id,
                      std::string_view name) const {
        const BinaryView header(resource_view(directory, 16));
        const std::size_t count = header.u16(12) + header.u16(14);
        const BinaryView entries(resource_view(directory + 16, count * 8));
        for (std::size_t index = 0; index < count; ++index) {
            const auto key = entries.u32(index * 8);
            bool matches = id && key == *id;
            if (!id && (key & 0x80000000U) != 0) {
                const std::size_t name_offset = key & 0x7fffffffU;
                const auto length = BinaryView(resource_view(name_offset, 2)).u16(0);
                const BinaryView letters(resource_view(name_offset + 2, std::size_t{length} * 2));
                matches = length == name.size();
                for (std::size_t letter = 0; matches && letter < length; ++letter) {
                    matches = letters.u16(letter * 2) == static_cast<unsigned char>(name[letter]);
                }
            }
            if (matches) {
                const auto target = entries.u32(index * 8 + 4);
                if ((target & 0x80000000U) == 0) throw FormatError("expected resource directory");
                return target & 0x7fffffffU;
            }
        }
        throw FormatError("named bitmap resource not found: " + std::string(name));
    }
    std::size_t first_target(std::size_t directory) const {
        const BinaryView header(resource_view(directory, 16));
        if (header.u16(12) + header.u16(14) == 0) throw FormatError("empty resource directory");
        return BinaryView(resource_view(directory + 16, 8)).u32(4) & 0x7fffffffU;
    }
    std::span<const char> entry_data(std::size_t offset) const {
        const BinaryView entry(resource_view(offset, 16));
        const std::size_t size = entry.u32(4);
        return file_.slice(file_offset(entry.u32(0), size), size);
    }
    std::size_t first_language(std::size_t directory) const {
        const BinaryView header(resource_view(directory, 16));
        // The pinned binary uses one language per bitmap. Reject ambiguous variants.
        if (header.u16(12) != 0 || header.u16(14) != 1) throw FormatError("ambiguous bitmap language");
        const auto target = BinaryView(resource_view(directory + 16, 8)).u32(4);
        if ((target & 0x80000000U) != 0) throw FormatError("expected resource data entry");
        return target;
    }
    BinaryView file_;
    std::size_t sections_ = 0;
    std::size_t section_count_ = 0;
    std::uint32_t image_base_ = 0;
    std::size_t root_ = 0;
    std::size_t resource_size_ = 0;
};
// A top-down tight 24-bit pixel buffer (B, G, R per pixel, bottom row first) as a BMP file.
Bytes bmp_file(std::size_t width, std::size_t height, const std::vector<std::uint8_t>& pixels) {
    const std::size_t stride = (width * 3 + 3) & ~std::size_t{3};
    const std::size_t image = stride * height;
    Bytes out(54 + image, 0);
    const auto put32 = [&](std::size_t at, std::uint32_t value) {
        for (std::size_t i = 0; i < 4; ++i) out[at + i] = static_cast<char>((value >> (8 * i)) & 0xff);
    };
    out[0] = 'B'; out[1] = 'M';
    put32(2, static_cast<std::uint32_t>(out.size())); put32(10, 54); put32(14, 40);
    put32(18, static_cast<std::uint32_t>(width)); put32(22, static_cast<std::uint32_t>(height));
    out[26] = 1; out[28] = 24; put32(34, static_cast<std::uint32_t>(image));
    for (std::size_t row = 0; row < height; ++row) {
        for (std::size_t i = 0; i < width * 3; ++i) out[54 + row * stride + i] = static_cast<char>(pixels[row * width * 3 + i]);
    }
    return out;
}
// The DIB of an icon image (BITMAPINFOHEADER, palette, XOR pixels, AND mask) drawn over `background` (0xRRGGBB).
Bytes icon_dib_to_bmp(std::span<const char> dib, std::uint32_t background) {
    const BinaryView view(dib);
    const std::size_t header = view.u32(0);
    const std::size_t width = view.u32(4), height = std::size_t{view.u32(8)} / 2;
    const std::size_t bits = view.u16(14);
    if (header < 40 || view.u32(16) != 0 || width < 1 || width > 256 || height < 1 || height > 256 ||
        (bits != 1 && bits != 4 && bits != 8 && bits != 24 && bits != 32)) throw FormatError("unsupported icon image");
    std::size_t palette = view.u32(32);
    if (palette == 0 && bits <= 8) palette = std::size_t{1} << bits;
    if (palette > 256) throw FormatError("icon palette too large");
    const std::size_t pixels_at = header + palette * 4;
    const std::size_t stride = ((width * bits + 31) / 32) * 4;
    const std::size_t mask_at = pixels_at + stride * height, mask_stride = ((width + 31) / 32) * 4;
    view.slice(pixels_at, stride * height);
    const bool has_mask = dib.size() >= mask_at + mask_stride * height;
    bool any_alpha = false;
    if (bits == 32) {
        for (std::size_t i = 0; i < width * height && !any_alpha; ++i) any_alpha = view.u8(pixels_at + (i / width) * stride + (i % width) * 4 + 3) != 0;
    }
    const int back[3] = {static_cast<int>((background >> 16) & 0xff), static_cast<int>((background >> 8) & 0xff), static_cast<int>(background & 0xff)};
    std::vector<std::uint8_t> out(width * height * 3);
    for (std::size_t row = 0; row < height; ++row) {
        for (std::size_t x = 0; x < width; ++x) {
            int blue = 0, green = 0, red = 0, alpha = 255;
            const std::size_t line = pixels_at + row * stride;
            if (bits == 32) {
                blue = view.u8(line + x * 4); green = view.u8(line + x * 4 + 1); red = view.u8(line + x * 4 + 2);
                if (any_alpha) alpha = view.u8(line + x * 4 + 3);
            } else if (bits == 24) {
                blue = view.u8(line + x * 3); green = view.u8(line + x * 3 + 1); red = view.u8(line + x * 3 + 2);
            } else {
                std::size_t index = 0;
                if (bits == 8) index = view.u8(line + x);
                else if (bits == 4) index = (view.u8(line + x / 2) >> ((x % 2) ? 0 : 4)) & 0xf;
                else index = (view.u8(line + x / 8) >> (7 - x % 8)) & 1;
                if (index >= palette) index = 0;
                blue = view.u8(header + index * 4); green = view.u8(header + index * 4 + 1); red = view.u8(header + index * 4 + 2);
            }
            if (has_mask && !(bits == 32 && any_alpha) && ((view.u8(mask_at + row * mask_stride + x / 8) >> (7 - x % 8)) & 1)) alpha = 0;
            const std::size_t at = (row * width + x) * 3;
            out[at] = static_cast<std::uint8_t>((blue * alpha + back[2] * (255 - alpha)) / 255);
            out[at + 1] = static_cast<std::uint8_t>((green * alpha + back[1] * (255 - alpha)) / 255);
            out[at + 2] = static_cast<std::uint8_t>((red * alpha + back[0] * (255 - alpha)) / 255);
        }
    }
    return bmp_file(width, height, out);
}
}
Bytes placeholder_icon(std::uint32_t background) {
    constexpr std::size_t size = 32;
    std::vector<std::uint8_t> pixels(size * size * 3);
    for (std::size_t y = 0; y < size; ++y) {
        for (std::size_t x = 0; x < size; ++x) {
            const bool border = x >= 4 && x < size - 4 && y >= 4 && y < size - 4 && (x < 6 || x >= size - 6 || y < 6 || y >= size - 6);
            const std::uint32_t color = border ? 0xa0a0c0u : background;
            const std::size_t at = (y * size + x) * 3;
            pixels[at] = static_cast<std::uint8_t>(color & 0xff);
            pixels[at + 1] = static_cast<std::uint8_t>((color >> 8) & 0xff);
            pixels[at + 2] = static_cast<std::uint8_t>((color >> 16) & 0xff);
        }
    }
    return bmp_file(size, size, pixels);
}
Result<Bytes> executable_icon(std::span<const char> executable, std::uint32_t background) {
    if (executable.size() > 64 * 1024 * 1024) return fail(ErrorCode::limit, "PE file exceeds limit");
    try {
        const PeResources pe(executable);
        const BinaryView group(pe.first_resource(14));
        const std::size_t count = group.u16(4);
        int best_score = -1;
        std::span<const char> best;
        for (std::size_t i = 0; i < count && i < 64; ++i) {
            const std::size_t entry = 6 + i * 14;
            const int width = group.u8(entry) == 0 ? 256 : group.u8(entry);
            const int bits = group.u16(entry + 6);
            std::span<const char> image;
            try { image = pe.icon_resource(group.u16(entry + 12)); } catch (const FormatError&) { continue; }
            if (image.size() < 8 || static_cast<unsigned char>(image[0]) == 0x89) continue;  // PNG-compressed: not decoded
            // 32 to 64 pixels suit the picker best, then smaller ones, then larger ones.
            const int rank = width >= 32 && width <= 64 ? 1000 + width : width < 32 ? width : 500 - width;
            const int score = rank * 64 + bits;
            if (score > best_score) { best_score = score; best = image; }
        }
        if (best_score < 0) return fail(ErrorCode::format, "no usable icon in the executable");
        return icon_dib_to_bmp(best, background);
    } catch (const FormatError& error) {
        return fail(ErrorCode::format, error.what());
    }
}
Result<Bytes> executable_data(std::span<const char> executable, std::uint32_t address, std::size_t size) {
    if (executable.size() > 64 * 1024 * 1024) return fail(ErrorCode::limit, "PE file exceeds limit");
    try {
        const auto data = PeResources(executable).data(address, size);
        return Bytes(data.begin(), data.end());
    } catch (const FormatError& error) {
        return fail(ErrorCode::format, error.what());
    }
}
Result<std::pair<std::string, std::int32_t>> scan_recording_constants(std::span<const char> executable) {
    if (executable.size() > 64 * 1024 * 1024) return fail(ErrorCode::limit, "PE file exceeds limit");
    constexpr std::size_t minimum_run = 1000;
    constexpr std::size_t version_distance = 0x764;  // 0x44d7a0 - 0x44d03c in v2.0a, the same in Darkfiren
    std::size_t found_start = 0, found_size = 0;
    int runs = 0;
    for (std::size_t index = 0; index < executable.size();) {
        std::size_t end = index;
        while (end < executable.size() && executable[end] >= '0' && executable[end] <= '9') ++end;
        if (end - index >= minimum_run) { ++runs; found_start = index; found_size = end - index; }
        index = end + 1;
    }
    if (runs != 1) return fail(ErrorCode::format, "expected one recording key in the executable, found " + std::to_string(runs));
    if (found_start < version_distance) return fail(ErrorCode::format, "recording key too close to the file start");
    try {
        const PeResources pe(executable);
        if (!pe.address_of(found_start)) return fail(ErrorCode::format, "recording key is outside the PE sections");
    } catch (const FormatError& error) { return fail(ErrorCode::format, error.what()); }
    const BinaryView view(executable);
    return std::pair{std::string(executable.data() + found_start, found_size),
                     static_cast<std::int32_t>(view.u32(found_start - version_distance))};
}
Result<Bytes> bitmap_resource(std::span<const char> executable, std::string_view name) {
    if (executable.size() > 64 * 1024 * 1024) return fail(ErrorCode::limit, "PE file exceeds limit");
    std::span<const char> dib;
    try { dib = PeResources(executable).bitmap(name); }
    catch (const FormatError& error) { return fail(ErrorCode::format, error.what()); }
    auto converted = bitmap::from_dib(dib);
    if (!converted) converted.error().message = "pe/" + std::string(name) + ": " + converted.error().message;
    return converted;
}
}
