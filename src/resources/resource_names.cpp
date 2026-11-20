// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/resource_names.hpp"
#include "openlf2/core/files.hpp"
#include "openlf2/resources/data_file.hpp"
#include <array>
#include <cstdint>

namespace openlf2 {
namespace {
std::string_view trim(std::string_view text) {
    while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) text.remove_prefix(1);
    while (!text.empty() && (text.back() == ' ' || text.back() == '\t' || text.back() == '\r')) text.remove_suffix(1);
    return text;
}
std::string upper_stem(std::string_view path) {
    if (const auto slash = path.find_last_of("/\\"); slash != std::string_view::npos) path.remove_prefix(slash + 1);
    if (const auto dot = path.rfind('.'); dot != std::string_view::npos) path = path.substr(0, dot);
    std::string name(path);
    for (auto& character : name) {
        if (character >= 'a' && character <= 'z') character = static_cast<char>(character - ('a' - 'A'));
    }
    return name;
}
std::string lower(std::string_view text) {
    std::string result(text);
    for (auto& character : result) {
        if (character >= 'A' && character <= 'Z') character = static_cast<char>(character + ('a' - 'A'));
    }
    return result;
}
bool digits(std::string_view text) {
    if (text.empty()) return false;
    for (const char character : text) if (character < '0' || character > '9') return false;
    return true;
}
}

// The bitmaps of the executable in the order readme `resource dat.txt` fixes ("do not change the order of these files"):
// the n-th `pic:` line of resource.dat belongs to the n-th name, whatever the file is called.
constexpr std::array<std::string_view, 48> builtin_names{
    "LF2_CURSOR", "MENU_CLIP", "MENU_CLIP2", "MENU_CLIP3", "MENU_CLIP4", "MENU_CLIP5", "MENU_CLIP6", "BG_RANDOM",
    "BG_FRAME", "SLOGAN", "ENDING", "CS2", "CS3", "CS4", "CS5", "CS6", "WORDS0", "WORDS1", "WORDS2", "WORDS3",
    "WORDS4", "WORDS5", "PAUSE", "DEMO", "SCORE_BOARD1", "SCORE_BOARD2", "SCORE_BOARD3", "SCORE_BOARD4", "WIN_ALIVE",
    "WIN_DEAD", "LOSE_DEAD", "LOSE_ALIVE", "CHARMENU", "CM1", "CM2", "CM3", "CM4", "CM5", "CMA", "CMA2", "CMC", "CMC2",
    "RFACE", "SPARK", "BATTLEMODE", "BATTLETROOPS", "INFORMATION", "LOADING"};

ResourceNames load_resource_names(const ResourceSource& resources) {
    ResourceNames names;
    auto text = read_data_text(resources, "data/resource.dat", 1024 * 1024);
    if (!text) return names;
    const std::string_view all(text->data(), text->size());
    // First pass: by position, as the executable does. A `pic:` line whose path cannot be used still takes its place.
    // Second pass: lines beyond the built-in list, and every file name that is not already a name, are also kept under
    // the file name without extension (how earlier OpenLF2 versions matched, and the only way for extra entries).
    std::vector<std::pair<std::string, std::string>> by_stem;
    std::size_t position = 0;
    for (std::size_t start = 0; start < all.size();) {
        auto end = all.find('\n', start);
        if (end == std::string_view::npos) end = all.size();
        const auto line = trim(all.substr(start, end - start));
        start = end + 1;
        if (!line.starts_with("pic:")) continue;
        const auto value = trim(line.substr(4));
        const auto slot = position++;
        auto path = virtual_path(value);
        if (!path) continue;
        if (slot < builtin_names.size()) names.emplace(std::string(builtin_names[slot]), *path);  // the first of equal names wins
        by_stem.emplace_back(upper_stem(value), std::move(*path));
    }
    for (auto& [stem, path] : by_stem) names.emplace(std::move(stem), std::move(path));
    return names;
}

std::vector<std::string> bitmap_candidates(std::string_view name, const ResourceNames& names) {
    std::vector<std::string> paths;
    if (const auto found = names.find(name); found != names.end()) paths.push_back(found->second);
    // Darkfiren moved the bitmaps its resource.dat does not list.
    if (name.starts_with("MENU_BACK") && digits(name.substr(9))) paths.push_back("sprite/menu/" + std::string(name.substr(9)) + ".bmp");
    else if (name == "MENU_WAIT") paths.push_back("sprite/loading/menu_wait.bmp");
    else if (name == "BARS") paths.push_back("sprite/frame/bars.bmp");
    else if (name == "FRAME") paths.push_back("sprite/frame/default/frame.bmp");
    else if (name.starts_with("BACK99_")) paths.push_back("bg/sys/lor/" + lower(name) + ".bmp");
    else if (name == "SHADOW1") paths.push_back("bg/sys/lor/s.bmp");
    paths.push_back("lf2_exe/" + lower(name) + ".bmp");
    paths.push_back("lf2_exe/" + lower(name) + ".png");
    return paths;
}

std::vector<int> block_ids(const ResourceSource& resources, std::string_view path, std::string_view block) {
    std::vector<int> ids;
    auto text = read_data_text(resources, path, 1024 * 1024);
    if (!text) return ids;
    const std::string opening = "<" + std::string(block) + ">";
    const std::string closing = "<" + std::string(block) + "_end>";
    const std::string_view all(text->data(), text->size());
    bool inside = false;
    for (std::size_t start = 0; start < all.size() && ids.size() < 100;) {
        auto end = all.find('\n', start);
        if (end == std::string_view::npos) end = all.size();
        const auto line = trim(all.substr(start, end - start));
        start = end + 1;
        if (line == opening) { inside = true; continue; }
        if (line == closing) { if (inside) break; continue; }
        if (!inside || !line.starts_with("id:")) continue;
        const auto value = trim(line.substr(3));
        int number = 0;
        std::size_t used = 0;
        while (used < value.size() && value[used] >= '0' && value[used] <= '9' && used < 6) number = number * 10 + (value[used++] - '0');
        if (used > 0) ids.push_back(number);
    }
    return ids;
}

std::string background_mode_lines(const ResourceSource& resources, int row) {
    auto index = read_data_text(resources, "data/bg_mode.dat", 1024 * 1024);
    if (!index) return {};
    std::string file;
    {
        const std::string_view all(index->data(), index->size());
        bool inside = false, found = false;
        for (std::size_t start = 0; start < all.size();) {
            auto end = all.find('\n', start);
            if (end == std::string_view::npos) end = all.size();
            const auto line = trim(all.substr(start, end - start));
            start = end + 1;
            if (line == "<bg_information>") { inside = true; found = false; continue; }
            if (line == "<bg_information_end>") { inside = false; if (found && !file.empty()) break; file.clear(); continue; }
            if (!inside) continue;
            if (line.starts_with("bg:")) {
                int number = 0;
                const auto value = trim(line.substr(3));
                std::size_t used = 0;
                while (used < value.size() && value[used] >= '0' && value[used] <= '9' && used < 6) number = number * 10 + (value[used++] - '0');
                found = used > 0 && number == row;
            } else if (line.starts_with("file:")) {
                file = std::string(trim(line.substr(5)));
            }
        }
        if (!found || file.empty()) return {};
    }
    auto text = read_data_text(resources, file, 1024 * 1024);
    if (!text) return {};
    static constexpr std::string_view repeated[] = {"id", "oid", "drop", "respond", "arest", "fall", "wait"};
    const std::string_view all(text->data(), text->size());
    std::string result;
    std::vector<std::pair<std::string, std::string>> mode;
    int modes = 0;
    // A mode block is a stream of `key:` words, each followed by its value words; several pairs may share a line.
    const auto add = [&](const std::string& key, const std::string& value) {
        bool joins = false;
        for (const auto name : repeated) if (key == name) joins = true;
        for (auto& entry : mode) {
            if (entry.first != key) continue;
            if (joins) entry.second += ',' + value;
            return;
        }
        mode.emplace_back(key, value);
    };
    const auto flush = [&] {
        if (!mode.empty() && modes < 100) {
            ++modes;
            for (std::size_t item = 0; item < mode.size(); ++item) {
                if (item != 0) result += '\t';
                result += mode[item].first + '=' + mode[item].second;
            }
            result += '\n';
        }
        mode.clear();
    };
    bool inside = false;
    std::string key, value;
    const auto close_pair = [&] {
        if (!key.empty()) add(key, std::string(trim(value)));
        key.clear();
        value.clear();
    };
    for (std::size_t start = 0; start < all.size();) {
        auto end = all.find('\n', start);
        if (end == std::string_view::npos) end = all.size();
        const auto line = trim(all.substr(start, end - start));
        start = end + 1;
        if (line == "<mode>") { inside = true; mode.clear(); key.clear(); value.clear(); continue; }
        if (line == "<mode_end>") { if (inside) { close_pair(); flush(); } inside = false; continue; }
        if (!inside) continue;
        for (std::size_t position = 0; position < line.size();) {
            while (position < line.size() && (line[position] == ' ' || line[position] == '\t')) ++position;
            const auto word_start = position;
            while (position < line.size() && line[position] != ' ' && line[position] != '\t') ++position;
            if (word_start == position) break;
            const auto word = line.substr(word_start, position - word_start);
            if (word.size() > 1 && word.back() == ':' && word.front() != '<') {
                close_pair();
                key = lower(word.substr(0, word.size() - 1));
            } else if (!key.empty()) {
                if (!value.empty()) value += ' ';
                value += word;
            }
        }
    }
    return result;
}

std::optional<int> system_number(const ResourceSource& resources, std::string_view key) {
    auto text = read_data_text(resources, "data/system.dat", 1024 * 1024);
    if (!text) return std::nullopt;
    const std::string_view all(text->data(), text->size());
    for (std::size_t start = 0; start < all.size();) {
        auto end = all.find('\n', start);
        if (end == std::string_view::npos) end = all.size();
        auto line = trim(all.substr(start, end - start));
        start = end + 1;
        if (!line.starts_with(key)) continue;
        line = trim(line.substr(key.size()));
        if (line.empty() || line.front() != ':') continue;
        line = trim(line.substr(1));
        int value = 0;
        std::size_t used = 0;
        while (used < line.size() && line[used] >= '0' && line[used] <= '9' && used < 6) value = value * 10 + (line[used++] - '0');
        if (used > 0) return value;
    }
    return std::nullopt;
}

Result<std::pair<std::string, std::int32_t>> read_recording_file(const ResourceSource& resources) {
    auto bytes = resources.read("lf2_exe/recording.txt");
    if (!bytes) return std::unexpected(bytes.error());
    const std::string_view all(bytes->data(), bytes->size());
    const auto first = all.find('\n');
    if (first == std::string_view::npos) return fail(ErrorCode::format, "lf2_exe/recording.txt needs two lines");
    const auto version_text = trim(all.substr(0, first));
    auto rest = all.substr(first + 1);
    const auto second = rest.find('\n');
    const auto key = trim(second == std::string_view::npos ? rest : rest.substr(0, second));
    if (!digits(version_text) || version_text.size() > 10 || key.size() < 1000 || key.size() > 1346 || !digits(key)) {
        return fail(ErrorCode::format, "lf2_exe/recording.txt: expected a decimal version and the key digits");
    }
    return std::pair{std::string(key), static_cast<std::int32_t>(std::stoul(std::string(version_text)))};
}
}
