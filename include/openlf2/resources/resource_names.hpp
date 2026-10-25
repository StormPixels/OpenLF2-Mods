// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/ports/resources.hpp"
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace openlf2 {
// LF2 Darkfiren no longer carries its bitmaps inside lf2.exe: `data/resource.dat` lists them as files.
// Keyed by the file name without extension in upper case (the original resource name), valued by the
// normalized virtual path. Empty when the game has no readable resource.dat.
using ResourceNames = std::map<std::string, std::string, std::less<>>;
ResourceNames load_resource_names(const ResourceSource& resources);
// Files that may hold the executable bitmap resource `name` (upper case), most specific first:
// the resource.dat entry, where Darkfiren keeps the bitmaps resource.dat does not list, then the
// `lf2_exe/` folder written by tools/extract_lf2_exe.py. The executable itself is the caller's last resort.
std::vector<std::string> bitmap_candidates(std::string_view name, const ResourceNames& names);
// The `id:` values of the block `<name>` ... `<name>_end` of a data file (LF2 Darkfiren's mode4.dat `<random>`),
// at most 100; empty when the file or the block is missing.
std::vector<int> block_ids(const ResourceSource& resources, std::string_view path, std::string_view block);
// LF2 Darkfiren's background modes of the background at `row` of the catalog (the position in data.txt's list):
// `data/bg_mode.dat` names the file (`bg: row`, `file: data\\bg\\lf.dat`), whose `<mode>` blocks become one line
// each, as tab separated `key=value` pairs. Keys that may repeat (id, oid, drop, respond, arest, fall, wait) are
// joined with commas; the first of any other key wins. Empty when the background has no modes.
std::string background_mode_lines(const ResourceSource& resources, int row);
// A numeric scalar of `data/system.dat` such as `spark_w: 99` (LF2 Darkfiren), if present.
std::optional<int> system_number(const ResourceSource& resources, std::string_view key);
// The recording version and key digits of `lf2_exe/recording.txt` (line 1: version, line 2: digits).
Result<std::pair<std::string, std::int32_t>> read_recording_file(const ResourceSource& resources);
}
