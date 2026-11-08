// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/object_data.hpp"
#include "openlf2/resources/data_file.hpp"
#include "openlf2/detail/resources/scan_stream.hpp"
#include <algorithm>
#include <array>
#include <span>

namespace openlf2::object_data {
namespace {
using scanning::ParseFailure;
using scanning::TokenStream;
using scanning::wrapping_add;
using scanning::wrapping_subtract;
constexpr std::size_t token_capacity = 200;
constexpr std::size_t max_diagnostics = 256;
constexpr std::size_t max_input = 4 * 1024 * 1024;

// Darkfiren tag name (without the trailing colon) and the key scripts see.
struct TagKey {
    std::string_view tag;
    std::string_view key;
};
constexpr TagKey same(std::string_view name) { return {name, name}; }

constexpr std::array itr_tags{same("dvz"), same("drain"), same("gain"), same("recover"), same("dbdefend"),
    same("spark"), same("cover"), same("z"), same("dx"), same("dy"), same("dz"), same("delay"),
    same("poison"), same("confus"), same("weak"), same("manacle"), same("join"), same("mimic"),
    same("bound"), same("facing"), same("sound")};
constexpr std::array itr_pair_tags{same("catchingact"), same("caughtact"), same("pickingact"), same("pickedact")};
constexpr std::array strength_tags{same("dvz"), same("drain"), same("gain"), same("spark"), same("recover"),
    same("dbdefend"), same("z"), same("sound"), same("cover"), same("caughtact"), same("selfinjury"),
    same("decrease")};
constexpr std::array body_tags{same("zwidth"), same("respond")};
constexpr std::array opoint_tags{same("hp"), same("mp"), same("team"), same("z"), same("dvz"), same("reserve"),
    same("effect"), same("centerx"), same("centery"), same("centerz"), same("framea"), same("attacking"),
    same("pic"), same("join"), same("join_reserve"), same("join_pic")};
constexpr std::array bpoint_tags{same("w"), same("h"), same("rect"), same("respond")};
constexpr std::array cpoint_tags{same("z"), same("faction"), same("baction"), same("uzaction"), same("dzaction"),
    same("respond"), same("drain"), same("gain"), same("recover"), same("throwz")};
constexpr std::array cpoint_pair_tags{same("catchingact"), same("caughtact"), same("pickingact"), same("pickedact")};
constexpr std::array ppoint_tags{same("kind"), same("x"), same("y"), same("z")};
constexpr std::array frame_tags{same("dx"), same("dy"), same("dz"), same("hp"), same("chp"), same("cmp"),
    same("caught"), same("loop"), same("amount"), same("shadow"), same("bound"), TagKey{"centerz", "center_z"},
    same("respond"), same("cover"), same("attacking"), same("caughtact"), same("music")};
constexpr std::array hold_tags{TagKey{"hold_a", "a"}, TagKey{"hold_d", "d"}, TagKey{"hold_j", "j"},
    TagKey{"hold_f", "f"}, TagKey{"hold_b", "b"}, TagKey{"hold_uz", "uz"}, TagKey{"hold_dz", "dz"}};
// hit_aj/hit_jj/hit_aa are the pdk-control names of the same slots as hit_Faj/hit_Uaj/hit_Daj (docs/txt/exe/frame.txt).
// They are kept under their own keys (aj, jj, aa): which name applies depends on the `dicontrol` flag of the background
// mode, so the script side chooses (decision of AI2, discussion round 3).
constexpr std::array hit_ext_tags{TagKey{"hit_f", "f"}, TagKey{"hit_b", "b"}, TagKey{"hit_uz", "uz"},
    TagKey{"hit_dz", "dz"}, TagKey{"hit_g", "g"}, TagKey{"hit_Faj", "Faj"}, TagKey{"hit_Uaj", "Uaj"},
    TagKey{"hit_Daj", "Daj"}, TagKey{"hit_aj", "aj"}, TagKey{"hit_jj", "jj"}, TagKey{"hit_aa", "aa"}};
// <bmp_begin> tags. The data mixes `name: v` and `name v`, so the colon is optional here.
constexpr std::array header_int_tags{same("heavy_walking_frame_rate"), same("heavy_running_frame_rate"),
    same("hidden"), same("random"), same("kind"), same("ratio"), same("use_ai"), same("drop"), same("bound"),
    same("shadow"), same("shadowsize"), same("effect"), same("start_frame"), same("cost"), same("respond"),
    same("pic"), same("frame_0mp"), same("small_x"), same("small_y"), same("property")};
constexpr std::array header_text_tags{same("shadow_pic"), same("frame"), same("bars"), same("smallb"),
    same("smallc"), same("smalld"), same("smallp"), same("smallt"), same("hidden_head"), same("hidden_small"),
    same("sound1"), same("sound2")};
constexpr std::array header_list_tags{same("walking_frame"), same("running_frame"),
    same("heavy_walking_frame"), same("heavy_running_frame")};

constexpr std::array stats_tags{same("bleed_hp"), same("attacking"), same("regen_hp"), same("regen_mp"),
    same("regen_dhp"), same("defend"), same("normal_attack1"), same("normal_attack2"), same("jump_attack"),
    same("run_attack"), same("dash_attack"), same("light_throw"), same("heavy_throw"), same("sky_light_throw"),
    same("run_heavy_throw"), same("weapon_drink"), same("respond"), same("recmp"), same("max_mp"), same("ohp"),
    same("omp"), same("reserve"), same("phase"), same("caught"), same("caughtact"), same("bound"), same("y"),
    same("weaponact")};
constexpr std::array armor_int_tags{same("type"), same("ratio"), same("decrease"), same("mp"), same("fall"),
    same("bdefend"), same("injury"), same("spark"), same("delay"), same("hp"), same("recover"),
    same("facing"), same("action")};
constexpr std::array armor_text_tags{same("sound1"), same("sound2")};
// Repeated tags that build a list: `id: 1 id: 2` -> ids = {1, 2}.
constexpr std::array armor_repeat_tags{TagKey{"id", "ids"}, TagKey{"state", "states"}, TagKey{"effect", "effects"}};
// `frame: first last` may repeat; every occurrence becomes one group.
constexpr std::array armor_group_tags{TagKey{"frame", "frames"}};
constexpr std::array piece_head_tags{same("team")};
constexpr std::array piece_tags{same("act"), same("framea"), same("dvx"), same("dvy"), same("dvz"), same("oid"),
    same("amount")};
constexpr std::array sound_set_tags{same("bg"), same("mode")};
constexpr std::array sound_text_tags{TagKey{"weapon_hit_sound", "weapon_hit"},
    TagKey{"weapon_drop_sound", "weapon_drop"}, TagKey{"weapon_broken_sound", "weapon_broken"}};
constexpr std::array skin_head_int_tags{same("random")};
constexpr std::array skin_head_text_tags{same("sound")};
constexpr std::array skin_int_tags{same("offset"), same("respond")};
constexpr std::array skin_text_tags{same("head"), same("small"), same("smallb"), same("smallt")};
constexpr std::array command_int_tags{same("bound"), same("type"), same("respond"), same("hp"), same("mp"),
    same("team"), same("times")};
constexpr std::array command_repeat_tags{TagKey{"mode", "modes"}, TagKey{"action", "actions"}};

constexpr std::array phase_int_tags{same("respond"), same("oid"), same("pic_x"), same("pic_y"), same("start_x"),
    same("start_y"), same("rect"), same("row"), same("centerx"), same("centery"), same("w"), same("h"),
    same("bound"), same("caughtact"), same("pickedact"), same("hidden")};
constexpr std::array phase_text_tags{same("sound1"), same("sound2"), same("pic")};
constexpr std::array phase_repeat_tags{TagKey{"id", "ids"}};
// Fields of the bar blocks and of their layers (one table: layers use a subset of the block tags).
constexpr std::array bar_int_tags{same("type"), same("x"), same("y"), same("w"), same("h"), same("dx"), same("dy"),
    same("facing"), same("effect"), same("amount"), same("loop"), same("respond"), same("bound"),
    same("transparency"), same("max"), same("cc"), same("c1"), same("c2"), same("centerx"), same("cover"),
    same("mp"), same("start_frame"), same("end_frame"), same("throwx")};
constexpr std::array bar_text_tags{same("pic")};
constexpr std::array bar_repeat_tags{TagKey{"team", "teams"}};
constexpr std::array count_int_tags{same("x"), same("y"), same("type"), same("max"), same("respond"),
    same("facing"), same("loop")};
constexpr std::array count_flex_tags{same("pic")};
constexpr std::array team_flag_int_tags{TagKey{"team_flag_x", "x"}, TagKey{"team_flag_y", "y"}};
constexpr std::array team_flag_text_tags{TagKey{"team0_flag", "team0"}, TagKey{"team1_flag", "team1"},
    TagKey{"team2_flag", "team2"}, TagKey{"team3_flag", "team3"}, TagKey{"team4_flag", "team4"},
    TagKey{"team5_flag", "team5"}};
constexpr std::array name_int_tags{same("respond"), same("name_x"), same("name_y"), same("x"), same("y"),
    same("hexf"), same("hexb")};
constexpr std::array name_text_tags{same("name")};

// A later occurrence of the same tag replaces the earlier one, like the original's overwrite.
void put(Extras& target, std::string_view key, ExtraItem::Kind kind, std::vector<std::int32_t> values,
         std::string text = {}) {
    for (auto& item : target) {
        if (item.key == key) {
            item.kind = kind;
            item.values = std::move(values);
            item.text = std::move(text);
            return;
        }
    }
    target.push_back(ExtraItem{std::string(key), kind, std::move(values), std::move(text), {}});
}

class Parser {
public:
    explicit Parser(std::string_view text) : stream_(text) {}

    ObjectData run() {
        bool first = true;
        while (!stream_.at_end()) {
            // At EOF the previous token is evaluated again, as in the original loop.
            if (!stream_.word(token_, token_capacity) && first) {
                throw ParseFailure{ErrorCode::format, "object data contains no tokens"};
            }
            first = false;
            add_checksum();
            if (token_ == "<bmp_begin>") header();
            else if (token_ == "<weapon_strength_list>") strength_list();
            else if (token_ == "<frame>") frame();
            else if (token_ == "<stats>") stats_block();
            else if (token_ == "<armor>") armor_block();
            else if (token_ == "<weapon_piece>") weapon_piece_block();
            else if (token_ == "<sound>") sound_block();
            else if (token_ == "<pic>") skin_block();
            else if (token_ == "<command>") command_block();
            else if (token_ == "<phase>") phase_block();
            else if (token_ == "<hp_bar>") bar_block(display().hp_bar, "<hp_bar_end>", max_display_layers);
            else if (token_ == "<mp_bar>") bar_block(display().mp_bar, "<mp_bar_end>", max_display_layers);
            else if (token_ == "<minibar>") bar_block(display().minibar, "<minibar_end>", 50);
            else if (token_ == "<bossbar>") bar_block(display().bossbar, "<bossbar_end>", 50);
            else if (token_ == "<effect>") bar_block(display().effect, "<effect_end>", max_display_layers);
            else if (token_ == "<menu_face>") bar_block(display().menu_face, "<menu_face_end>", 30);
            else if (token_ == "<stats_count>") stats_count_block();
            else if (token_ == "<team_flag>") team_flag_block();
            else if (token_ == "<name>") name_block("<name_end>");
            else if (token_ == "<n>") name_block("<n_end>");
            else if (token_ != "<bmp_end>" && token_ != "<frame_end>" &&
                     token_ != "<weapon_strength_list_end>") {
                note("ignored top-level token `" + token_ + "`");
            }
        }
        for (std::int32_t index = 0; index < frame_count; ++index) {
            const auto& frame = data_.frames[static_cast<std::size_t>(index)];
            if (frame.defined && !find_picture(data_, frame.picture)) {
                note("frame " + std::to_string(index) + " picture " +
                     std::to_string(frame.picture) + " is outside every sprite sheet");
            }
        }
        return std::move(data_);
    }

    [[nodiscard]] std::size_t line() const { return stream_.line(); }

private:
    void add_checksum() { scanning::add_token_checksum(data_.token_checksum, token_); }

    void note(std::string message) {
        if (data_.diagnostics.size() < max_diagnostics) {
            data_.diagnostics.push_back("line " + std::to_string(stream_.line()) + ": " +
                                        std::move(message));
        } else if (data_.diagnostics.size() == max_diagnostics) {
            data_.diagnostics.emplace_back("further diagnostics omitted");
        }
    }

    // Inner loops never test EOF in the original, which would loop forever.
    void next_token(std::string_view section) {
        if (!stream_.word(token_, token_capacity)) unterminated(section);
    }
    [[noreturn]] static void unterminated(std::string_view section) {
        throw ParseFailure{ErrorCode::format, "unterminated " + std::string(section) + " at end of file"};
    }
    std::string read_word(std::string_view section, std::size_t capacity) {
        std::string value;
        if (!stream_.word(value, capacity)) unterminated(section);
        return value;
    }

    bool read_int(std::int32_t& field) {
        const auto result = stream_.integer(field);
        if (result == TokenStream::Scan::mismatch) {
            note("`" + token_ + "` expects an integer; value left unchanged");
        }
        return result == TokenStream::Scan::value;
    }
    void read_int(std::optional<std::int32_t>& field) {
        std::int32_t value = field.value_or(0);
        if (read_int(value)) field = value;
    }
    void read_real(std::optional<double>& field) {
        double value = 0;
        const auto result = stream_.real(value);
        if (result == TokenStream::Scan::value) field = value;
        else if (result == TokenStream::Scan::mismatch) {
            note("`" + token_ + "` expects a number; value left unchanged");
        }
    }

    // Name of the current token without its trailing colon; empty if it has none and one is required.
    [[nodiscard]] std::string_view tag_name(bool colon_optional) const {
        std::string_view name = token_;
        if (!name.empty() && name.back() == ':') name.remove_suffix(1);
        else if (!colon_optional) return {};
        return name;
    }
    [[nodiscard]] static const TagKey* find_tag(std::span<const TagKey> table, std::string_view name) {
        for (const auto& entry : table) {
            if (entry.tag == name) return &entry;
        }
        return nullptr;
    }
    // Integer-valued Darkfiren tag. Returns false when the token is not in `table`.
    bool extra_int(Extras& target, std::span<const TagKey> table, bool colon_optional = false) {
        const auto name = tag_name(colon_optional);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t value = 0;
        if (read_int(value)) put(target, entry->key, ExtraItem::Kind::integer, {value});
        return true;
    }
    // `tag: left [right]`: the second number is optional, so it is only taken when present.
    bool extra_pair(Extras& target, std::span<const TagKey> table) {
        const auto name = tag_name(false);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t first = 0;
        if (!read_int(first)) return true;
        std::vector<std::int32_t> values{first};
        std::int32_t second = 0;
        if (stream_.integer(second) == TokenStream::Scan::value) values.push_back(second);
        put(target, entry->key, ExtraItem::Kind::list, std::move(values));
        return true;
    }
    bool extra_text(Extras& target, std::span<const TagKey> table, std::string_view section) {
        const auto name = tag_name(true);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        put(target, entry->key, ExtraItem::Kind::text, {}, read_word(section, 300));
        return true;
    }
    // `tag: v` repeated: every occurrence appends to one list.
    bool extra_repeat(Extras& target, std::span<const TagKey> table) {
        const auto name = tag_name(false);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t value = 0;
        if (!read_int(value)) return true;
        for (auto& item : target) {
            if (item.key == entry->key && item.kind == ExtraItem::Kind::list) {
                item.values.push_back(value);
                return true;
            }
        }
        target.push_back(ExtraItem{std::string(entry->key), ExtraItem::Kind::list, {value}, {}, {}});
        return true;
    }
    // `tag: v` repeated: every occurrence adds one value to a set (duplicates collapse), at most `cap` values.
    bool extra_set(Extras& target, std::span<const TagKey> table, std::size_t cap) {
        const auto name = tag_name(false);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t value = 0;
        if (!read_int(value)) return true;
        ExtraItem* item = nullptr;
        for (auto& existing : target) {
            if (existing.key == entry->key && existing.kind == ExtraItem::Kind::set) item = &existing;
        }
        if (!item) {
            target.push_back(ExtraItem{std::string(entry->key), ExtraItem::Kind::set, {}, {}, {}});
            item = &target.back();
        }
        if (std::find(item->values.begin(), item->values.end(), value) != item->values.end()) return true;
        if (item->values.size() >= cap) note("more than " + std::to_string(cap) + " `" + token_ + "` values; extra value ignored");
        else item->values.push_back(value);
        return true;
    }
    // `tag: first [second]` repeated: every occurrence appends one group.
    bool extra_group(Extras& target, std::span<const TagKey> table) {
        const auto name = tag_name(false);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t first = 0;
        if (!read_int(first)) return true;
        std::vector<std::int32_t> group{first};
        std::int32_t second = 0;
        if (stream_.integer(second) == TokenStream::Scan::value) group.push_back(second);
        for (auto& item : target) {
            if (item.key == entry->key && item.kind == ExtraItem::Kind::groups) {
                item.groups.push_back(std::move(group));
                return true;
            }
        }
        ExtraItem item{std::string(entry->key), ExtraItem::Kind::groups, {}, {}, {}};
        item.groups.push_back(std::move(group));
        target.push_back(std::move(item));
        return true;
    }
    // Number if the value parses as one, otherwise the word itself.
    bool extra_flex(Extras& target, std::span<const TagKey> table, std::string_view section) {
        const auto name = tag_name(false);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t value = 0;
        const auto result = stream_.integer(value);
        if (result == TokenStream::Scan::value) put(target, entry->key, ExtraItem::Kind::integer, {value});
        else put(target, entry->key, ExtraItem::Kind::text, {}, read_word(section, 300));
        return true;
    }
    bool bar_field(Extras& target, std::string_view section) {
        return extra_int(target, bar_int_tags) || extra_text(target, bar_text_tags, section) ||
               extra_repeat(target, bar_repeat_tags);
    }
    // Reads one `layer:` record. Returns false when the block's own end token was reached first.
    // The `#comment` after the layer number may span several words and names the layer's purpose.
    bool read_layer(Extras& layer, std::string_view section, std::string_view block_end) {
        std::int32_t index = 0;
        if (stream_.integer(index) == TokenStream::Scan::value) put(layer, "layer", ExtraItem::Kind::integer, {index});
        std::string comment;
        bool in_comment = false;
        for (;;) {
            next_token(section);
            if (token_ == "layer_end" || token_ == "layer_end:") break;
            if (token_ == block_end) {
                if (!comment.empty()) put(layer, "comment", ExtraItem::Kind::text, {}, comment);
                return false;
            }
            const bool is_tag = token_.back() == ':';
            if (token_.front() == '#' || (in_comment && !is_tag)) {
                in_comment = true;
                if (!comment.empty()) comment += ' ';
                comment += token_.front() == '#' ? token_.substr(1) : token_;
                continue;
            }
            in_comment = false;
            if (!bar_field(layer, section)) note("ignored layer token `" + token_ + "`");
        }
        if (!comment.empty()) put(layer, "comment", ExtraItem::Kind::text, {}, comment);
        return true;
    }
    void bar_block(std::optional<DisplayBlock>& target, std::string_view block_end, std::size_t max_layers) {
        const std::string section = token_;
        DisplayBlock result;
        next_token(section);
        while (token_ != block_end) {
            if (token_ == "layer:") {
                Extras layer;
                const bool closed = read_layer(layer, section, block_end);
                if (result.layers.size() < max_layers) result.layers.push_back(std::move(layer));
                else note("more than " + std::to_string(max_layers) + " layers in " + section + "; extra layer ignored");
                if (!closed) break;
            } else if (!bar_field(result.fields, section)) note("ignored " + section + " token `" + token_ + "`");
            next_token(section);
        }
        target = std::move(result);
    }
    Display& display() {
        if (!data_.display) data_.display = Display{};
        return *data_.display;
    }
    void stats_count_block() {
        std::vector<Extras> entries;
        block("<stats_count_end>", [&] {
            if (token_ != "count:") return false;
            Extras entry;
            block("count_end:", [&] {
                return extra_int(entry, count_int_tags) || extra_flex(entry, count_flex_tags, "count:");
            });
            if (entries.size() < max_stats_counts) entries.push_back(std::move(entry));
            else note("more than " + std::to_string(max_stats_counts) + " stats_count entries; extra ignored");
            return true;
        });
        display().stats_count = std::move(entries);
    }
    void team_flag_block() {
        Extras fields;
        block("<team_flag_end>", [&] {
            return extra_int(fields, team_flag_int_tags) || extra_text(fields, team_flag_text_tags, "<team_flag>");
        });
        display().team_flag = std::move(fields);
    }
    // The notes call this block <n>; the sample data spells it <name>. Both are accepted.
    void name_block(std::string_view block_end) {
        Extras fields;
        block(block_end, [&] {
            return extra_int(fields, name_int_tags) || extra_text(fields, name_text_tags, "<name>");
        });
        display().name = std::move(fields);
    }
    void phase_block() {
        Extras fields;
        block("<phase_end>", [&] {
            return extra_int(fields, phase_int_tags) || extra_text(fields, phase_text_tags, "<phase>") ||
                   extra_repeat(fields, phase_repeat_tags);
        });
        for (auto& item : fields) {
            if (item.key == "ids" && item.values.size() > max_phase_ids) {
                note("more than " + std::to_string(max_phase_ids) + " phase ids; extra ids ignored");
                item.values.resize(max_phase_ids);
            }
        }
        data_.phase = std::move(fields);
    }

    // `tag: count v1 .. vcount`
    bool extra_list(Extras& target, std::span<const TagKey> table) {
        const auto name = tag_name(true);
        const auto* entry = name.empty() ? nullptr : find_tag(table, name);
        if (!entry) return false;
        std::int32_t count = 0;
        if (!read_int(count)) return true;
        if (count < 0 || count > static_cast<std::int32_t>(max_header_list)) {
            note("`" + token_ + "` count outside 0-" + std::to_string(max_header_list) + ": " +
                 std::to_string(count));
            return true;
        }
        std::vector<std::int32_t> values;
        for (std::int32_t index = 0; index < count; ++index) {
            std::int32_t value = 0;
            if (!read_int(value)) break;
            values.push_back(value);
        }
        put(target, entry->key, ExtraItem::Kind::list, std::move(values));
        return true;
    }

    struct PendingSheet {
        std::optional<std::int32_t> width, height, columns, rows;
    };

    void finish_sheet() {
        auto& sheet = data_.sheets.back();
        // Bounds keep cell arithmetic within 32 bits; they exceed every original sheet.
        const auto require = [&](const std::optional<std::int32_t>& value, std::string_view key) {
            if (!value || *value < 1 || *value > 8192) {
                throw ParseFailure{ErrorCode::unsupported,
                                   "sprite sheet " + sheet.path + " needs " + std::string(key) + " in 1-8192"};
            }
            return *value;
        };
        sheet.cell_width = require(pending_.width, "w:");
        sheet.cell_height = require(pending_.height, "h:");
        sheet.columns = require(pending_.columns, "row:");
        sheet.rows = require(pending_.rows, "col:");
        if (std::int64_t{sheet.columns} * sheet.rows > max_sheet_cells) {
            throw ParseFailure{ErrorCode::unsupported,
                               "sprite sheet " + sheet.path + " exceeds 500 cells"};
        }
        std::int32_t first = 0;
        for (std::size_t index = 0; index + 1 < data_.sheets.size(); ++index) {
            first += data_.sheets[index].columns * data_.sheets[index].rows;
        }
        sheet.first_picture = first;
        pending_ = {};
    }

    void sheet_field(std::optional<std::int32_t> PendingSheet::*field) {
        if (data_.sheets.empty()) {
            note("`" + token_ + "` before the first sprite sheet is ignored");
            std::optional<std::int32_t> ignored;
            read_int(ignored);
            return;
        }
        read_int(pending_.*field);
    }

    void stats_block() {
        Extras fields;
        block("<stats_end>", [&] { return extra_int(fields, stats_tags); });
        data_.stats = std::move(fields);
    }

    void armor_block() {
        Extras fields;
        block("<armor_end>", [&] {
            return extra_int(fields, armor_int_tags) || extra_text(fields, armor_text_tags, "<armor>") ||
                   extra_repeat(fields, armor_repeat_tags) || extra_group(fields, armor_group_tags);
        });
        data_.armor = std::move(fields);
    }

    void weapon_piece_block() {
        WeaponPiece result;
        block("<weapon_piece_end>", [&] {
            if (extra_int(result.fields, piece_head_tags)) return true;
            if (token_ != "piece:") return false;
            std::int32_t index = 0;
            if (!read_int(index)) return true;
            Extras piece;
            block("piece_end:", [&] { return extra_int(piece, piece_tags); });
            if (index < 1 || index > static_cast<std::int32_t>(result.pieces.size())) {
                note("weapon piece number outside 1-5: " + std::to_string(index));
            } else result.pieces[static_cast<std::size_t>(index - 1)] = std::move(piece);
            return true;
        });
        data_.weapon_piece = std::move(result);
    }

    // Weapon sounds per background and background mode (readme `sound.txt`): up to 100 `bound:` .. `bound_end:`
    // entries. `bg:` and `mode:` may repeat (up to 100 values each) and become sets; an entry matches when the current
    // bg is in `bg` and the current mode is in `mode`. Anything outside a `bound:` entry is not part of the format.
    void sound_block() {
        data_.sound_list.clear();
        block("<sound_end>", [&] {
            if (token_ != "bound:") return false;
            Extras entry;
            block("bound_end:", [&] {
                return extra_set(entry, sound_set_tags, max_sound_values) ||
                       extra_text(entry, sound_text_tags, "bound:");
            });
            if (data_.sound_list.size() < max_sound_entries) data_.sound_list.push_back(std::move(entry));
            else note("more than " + std::to_string(max_sound_entries) + " sound entries; extra entry ignored");
            return true;
        });
    }

    void skin_block() {
        Skins result;
        block("<pic_end>", [&] {
            if (extra_int(result.fields, skin_head_int_tags) ||
                extra_text(result.fields, skin_head_text_tags, "<pic>")) return true;
            if (token_ != "pic:") return false;
            // The notes' template writes a bare `pic:`; the sample data numbers each skin.
            std::int32_t number = 0;
            Extras skin;
            if (stream_.integer(number) == TokenStream::Scan::value) put(skin, "pic", ExtraItem::Kind::integer, {number});
            block("pic_end:", [&] {
                return extra_int(skin, skin_int_tags) || extra_text(skin, skin_text_tags, "pic:");
            });
            if (result.entries.size() < max_skins) result.entries.push_back(std::move(skin));
            else note("more than " + std::to_string(max_skins) + " skins; extra skin ignored");
            return true;
        });
        data_.skins = std::move(result);
    }

    void command_block() {
        block("<command_end>", [&] {
            if (token_ != "command:") return false;
            Extras entry;
            block("command_end:", [&] {
                return extra_int(entry, command_int_tags) || extra_repeat(entry, command_repeat_tags);
            });
            if (data_.command.size() < max_commands) data_.command.push_back(std::move(entry));
            else note("more than " + std::to_string(max_commands) + " commands; extra command ignored");
            return true;
        });
    }

    void header() {
        constexpr std::string_view section = "<bmp_begin>";
        auto& movement = data_.movement;
        for (;;) {
            next_token(section);
            if (token_ == "<bmp_end>") {
                if (!data_.sheets.empty()) finish_sheet();
                return;
            }
            if (token_.starts_with("file")) {
                if (!data_.sheets.empty()) finish_sheet();
                if (data_.sheets.size() == max_sheets) {
                    throw ParseFailure{ErrorCode::unsupported, "more than ten sprite sheets"};
                }
                SpriteSheet sheet;
                sheet.declared_range = token_.substr(4);
                sheet.path = read_word(section, 40);
                data_.sheets.push_back(std::move(sheet));
            } else if (token_ == "head:") data_.head = read_word(section, 40);
            else if (token_ == "small:") data_.small = read_word(section, 36);
            else if (token_ == "name:") data_.name = read_word(section, 60);
            else if (token_ == "walking_frame_rate") read_int(movement.walking_frame_rate);
            else if (token_ == "walking_speed") read_real(movement.walking_speed);
            else if (token_ == "walking_speedz") read_real(movement.walking_speedz);
            else if (token_ == "running_frame_rate") read_int(movement.running_frame_rate);
            else if (token_ == "running_speed") read_real(movement.running_speed);
            else if (token_ == "running_speedz") read_real(movement.running_speedz);
            else if (token_ == "heavy_walking_speed") read_real(movement.heavy_walking_speed);
            else if (token_ == "heavy_walking_speedz") read_real(movement.heavy_walking_speedz);
            else if (token_ == "heavy_running_speed") read_real(movement.heavy_running_speed);
            else if (token_ == "heavy_running_speedz") read_real(movement.heavy_running_speedz);
            else if (token_ == "jump_height") read_real(movement.jump_height);
            else if (token_ == "jump_distance") read_real(movement.jump_distance);
            else if (token_ == "jump_distancez") read_real(movement.jump_distancez);
            else if (token_ == "dash_height") read_real(movement.dash_height);
            else if (token_ == "dash_distance") read_real(movement.dash_distance);
            else if (token_ == "dash_distancez") read_real(movement.dash_distancez);
            else if (token_ == "rowing_height") read_real(movement.rowing_height);
            else if (token_ == "rowing_distance") read_real(movement.rowing_distance);
            else if (token_ == "w:") sheet_field(&PendingSheet::width);
            else if (token_ == "h:") sheet_field(&PendingSheet::height);
            else if (token_ == "row:") sheet_field(&PendingSheet::columns);
            else if (token_ == "col:") sheet_field(&PendingSheet::rows);
            // The weapon values keep their 2.0a place in `weapon`; Darkfiren's contract also lists them in `header`.
            else if (token_ == "weapon_hp:") {
                if (read_int(data_.weapon_hp)) put(data_.header, "weapon_hp", ExtraItem::Kind::integer, {data_.weapon_hp});
            } else if (token_ == "weapon_drop_hurt:") {
                if (read_int(data_.weapon_drop_hurt)) {
                    put(data_.header, "weapon_drop_hurt", ExtraItem::Kind::integer, {data_.weapon_drop_hurt});
                }
            } else if (token_ == "weapon_hit_sound:") {
                data_.weapon_hit_sound = read_word(section, 300);
                put(data_.header, "weapon_hit_sound", ExtraItem::Kind::text, {}, *data_.weapon_hit_sound);
            } else if (token_ == "weapon_drop_sound:") {
                data_.weapon_drop_sound = read_word(section, 300);
                put(data_.header, "weapon_drop_sound", ExtraItem::Kind::text, {}, *data_.weapon_drop_sound);
            } else if (token_ == "weapon_broken_sound:") {
                data_.weapon_broken_sound = read_word(section, 300);
                put(data_.header, "weapon_broken_sound", ExtraItem::Kind::text, {}, *data_.weapon_broken_sound);
            }
            else if (extra_int(data_.header, header_int_tags, true) ||
                     extra_text(data_.header, header_text_tags, section) ||
                     extra_list(data_.header, header_list_tags)) {
            } else note("ignored header token `" + token_ + "`");
        }
    }

    // Returns true when the token named an itr/strength field.
    bool interaction_field(Interaction& target) {
        if (token_ == "kind:") read_int(target.kind);
        else if (token_ == "x:") read_int(target.area.x);
        else if (token_ == "y:") read_int(target.area.y);
        else if (token_ == "w:") read_int(target.area.width);
        else if (token_ == "h:") read_int(target.area.height);
        else if (token_ == "dvx:") read_int(target.dvx);
        else if (token_ == "dvy:") read_int(target.dvy);
        else if (token_ == "fall:") read_int(target.fall);
        else if (token_ == "arest:") read_int(target.arest);
        else if (token_ == "vrest:") read_int(target.vrest);
        else if (token_ == "respond:") read_int(target.respond);
        else if (token_ == "bdefend:") read_int(target.bdefend);
        else if (token_ == "injury:") read_int(target.injury);
        else if (token_ == "zwidth:") read_int(target.zwidth);
        else if (token_ == "effect:") read_int(target.effect);
        else return false;
        return true;
    }

    void strength_list() {
        constexpr std::string_view section = "<weapon_strength_list>";
        std::int32_t entry = 0;
        next_token(section);
        while (token_ != "<weapon_strength_list_end>") {
            if (token_ == "entry:") {
                const auto name_slot = entry;
                if (read_int(entry)) {
                    if (entry < 0 || entry >= static_cast<std::int32_t>(strength_entries)) {
                        throw ParseFailure{ErrorCode::unsupported,
                                           "weapon strength entry outside 0-9: " + std::to_string(entry)};
                    }
                    if (name_slot > 5) {
                        throw ParseFailure{ErrorCode::unsupported,
                                           "weapon strength name slot overlaps sprite paths"};
                    }
                    data_.strengths[static_cast<std::size_t>(name_slot)].name = read_word(section, 30);
                    data_.strengths[static_cast<std::size_t>(entry)].referenced = true;
                }
            } else {
                // The original's only fields here are dvx..zwidth; kind/x/y/w/h are not keys.
                const bool geometry = token_ == "kind:" || token_ == "x:" || token_ == "y:" ||
                                      token_ == "w:" || token_ == "h:";
                auto& values = data_.strengths[static_cast<std::size_t>(entry)].values;
                if (geometry || !(interaction_field(values) || extra_int(values.extra, strength_tags))) {
                    note("ignored weapon strength token `" + token_ + "`");
                }
            }
            next_token(section);
        }
    }

    template <typename Handler> void block(std::string_view end, Handler handler) {
        const std::string section = token_;
        next_token(section);
        while (token_ != end) {
            if (!handler()) note("ignored " + section + " token `" + token_ + "`");
            next_token(section);
        }
    }

    bool object_point(ObjectPoint& point) {
        if (token_ == "kind:") read_int(point.kind);
        else if (token_ == "x:") read_int(point.x);
        else if (token_ == "y:") read_int(point.y);
        else if (token_ == "action:") read_int(point.action);
        else if (token_ == "dvx:") read_int(point.dvx);
        else if (token_ == "dvy:") read_int(point.dvy);
        else if (token_ == "oid:") read_int(point.oid);
        else if (token_ == "facing:") read_int(point.facing);
        else return extra_int(point.extra, opoint_tags);
        return true;
    }

    bool catch_point(CatchPoint& point) {
        if (token_ == "kind:") read_int(point.kind);
        else if (token_ == "x:") read_int(point.x);
        else if (token_ == "y:") read_int(point.y);
        else if (token_ == "injury:" || token_ == "fronthurtact:") read_int(point.injury);
        else if (token_ == "cover:" || token_ == "backhurtact:") read_int(point.cover);
        else if (token_ == "vaction:") read_int(point.vaction);
        else if (token_ == "aaction:") read_int(point.aaction);
        else if (token_ == "jaction:") read_int(point.jaction);
        else if (token_ == "taction:") read_int(point.taction);
        else if (token_ == "daction:") read_int(point.daction);
        else if (token_ == "throwvx:") read_int(point.throwvx);
        else if (token_ == "throwvy:") read_int(point.throwvy);
        else if (token_ == "throwvz:") read_int(point.throwvz);
        else if (token_ == "hurtable:") read_int(point.hurtable);
        else if (token_ == "throwinjury:") read_int(point.throwinjury);
        else if (token_ == "decrease:") read_int(point.decrease);
        else if (token_ == "dircontrol:") read_int(point.dircontrol);
        else return extra_int(point.extra, cpoint_tags) || extra_pair(point.extra, cpoint_pair_tags);
        return true;
    }

    bool weapon_point(WeaponPoint& point) {
        if (token_ == "kind:") read_int(point.kind);
        else if (token_ == "x:") read_int(point.x);
        else if (token_ == "y:") read_int(point.y);
        else if (token_ == "weaponact:") read_int(point.weaponact);
        else if (token_ == "attacking:") read_int(point.attacking);
        else if (token_ == "cover:") read_int(point.cover);
        else if (token_ == "dvx:") read_int(point.dvx);
        else if (token_ == "dvy:") read_int(point.dvy);
        else if (token_ == "dvz:") read_int(point.dvz);
        else return false;
        return true;
    }

    bool interaction_block_field(Interaction& target) {
        if (interaction_field(target)) return true;
        if (token_ == "catchingact:" || token_ == "caughtact:") {
            // LF2 2.0a writes two numbers, Darkfiren's readme one; the second is taken only when it is there, without a
            // diagnostic. The values are also kept exactly as written under `catchingact` / `caughtact`.
            const bool catching = token_ == "catchingact:";
            if (extra_pair(target.extra, itr_pair_tags)) {
                auto& slots = catching ? target.catching_actions : target.caught_actions;
                for (const auto& item : target.extra) {
                    if (item.key != (catching ? "catchingact" : "caughtact")) continue;
                    if (!item.values.empty()) slots[0] = item.values[0];
                    if (item.values.size() > 1) slots[1] = item.values[1];
                }
            }
        } else if (token_ == "pickingact:" || token_ == "pickedact:") {
            // Legacy slots keep the 2.0a behavior; Darkfiren's left/right pair is exposed as well.
            const bool picking = token_ == "pickingact:";
            if (extra_pair(target.extra, itr_pair_tags) && !target.extra.empty()) {
                for (const auto& item : target.extra) {
                    if (item.key == (picking ? "pickingact" : "pickedact") && !item.values.empty()) {
                        target.catching_actions[picking ? 0 : 1] = item.values.front();
                    }
                }
            }
        } else return extra_int(target.extra, itr_tags);
        return true;
    }

    template <typename Item> static Rectangle bounds(const std::vector<Item>& items) {
        Rectangle result{items.front().area.x, items.front().area.y,
                         wrapping_add(items.front().area.width, items.front().area.x),
                         wrapping_add(items.front().area.height, items.front().area.y)};
        for (std::size_t index = 1; index < items.size(); ++index) {
            const auto& area = items[index].area;
            result.x = std::min(result.x, area.x);
            result.y = std::min(result.y, area.y);
            result.width = std::max(result.width, wrapping_add(area.width, area.x));
            result.height = std::max(result.height, wrapping_add(area.height, area.y));
        }
        result.width = wrapping_subtract(result.width, result.x);
        result.height = wrapping_subtract(result.height, result.y);
        return result;
    }

    void frame() {
        constexpr std::string_view section = "<frame>";
        std::int32_t index = 0;
        if (stream_.integer(index) != TokenStream::Scan::value) {
            throw ParseFailure{ErrorCode::unsupported, "<frame> without a frame number"};
        }
        if (index < 0 || index >= frame_count) {
            throw ParseFailure{ErrorCode::unsupported, "frame number outside 0-" + std::to_string(frame_count - 1) + ": " + std::to_string(index)};
        }
        auto& frame = data_.frames[static_cast<std::size_t>(index)];
        if (frame.defined) note("frame " + std::to_string(index) + " redefined; earlier fields kept");
        frame.name = read_word(section, 20);
        frame.defined = true;
        frame.interactions.clear();
        frame.bodies.clear();
        frame.sounds.clear();
        frame.opoints.clear();
        frame.bpoints.clear();
        next_token(section);
        while (token_ != "<frame_end>") {
            if (token_ == "pic:") read_int(frame.picture);
            else if (token_ == "state:") read_int(frame.state);
            else if (token_ == "wait:") read_int(frame.wait);
            else if (token_ == "next:") read_int(frame.next);
            else if (token_ == "dvx:") read_int(frame.dvx);
            else if (token_ == "dvy:") read_int(frame.dvy);
            else if (token_ == "dvz:") read_int(frame.dvz);
            else if (token_ == "centerx:") read_int(frame.center_x);
            else if (token_ == "centery:") read_int(frame.center_y);
            else if (token_ == "hit_a:") read_int(frame.hits[0]);
            else if (token_ == "hit_d:") read_int(frame.hits[1]);
            else if (token_ == "hit_j:") read_int(frame.hits[2]);
            else if (token_ == "hit_Fa:") read_int(frame.hits[3]);
            else if (token_ == "hit_Ua:") read_int(frame.hits[4]);
            else if (token_ == "hit_Da:") read_int(frame.hits[5]);
            else if (token_ == "hit_Fj:") read_int(frame.hits[6]);
            else if (token_ == "hit_Uj:") read_int(frame.hits[7]);
            else if (token_ == "hit_Dj:") read_int(frame.hits[8]);
            else if (token_ == "hit_ja:") read_int(frame.hits[9]);
            else if (token_ == "mp:") read_int(frame.mp);
            else if (token_ == "sound:") {
                auto path = read_word(section, 300);
                if (frame.sounds.size() == max_frame_sounds) {
                    throw ParseFailure{ErrorCode::unsupported,
                                       "more than " + std::to_string(max_frame_sounds) + " sound entries in a frame"};
                }
                frame.sounds.push_back(std::move(path));
            } else if (token_ == "opoint:") {
                if (frame.opoints.size() == max_object_points) {
                    throw ParseFailure{ErrorCode::unsupported,
                                       "more than " + std::to_string(max_object_points) + " opoint blocks in a frame"};
                }
                auto& point = frame.opoints.emplace_back();
                block("opoint_end:", [&] { return object_point(point); });
            } else if (token_ == "bpoint:") {
                if (frame.bpoints.size() == max_body_points) {
                    throw ParseFailure{ErrorCode::unsupported,
                                       "more than " + std::to_string(max_body_points) + " bpoint blocks in a frame"};
                }
                auto& point = frame.bpoints.emplace_back();
                block("bpoint_end:", [&] {
                    if (token_ == "x:") read_int(point.x);
                    else if (token_ == "y:") read_int(point.y);
                    else return extra_int(point.extra, bpoint_tags);
                    return true;
                });
            } else if (token_ == "ppoint:") {
                // At most one per frame; a repeated block replaces the earlier one.
                Extras fields;
                block("ppoint_end:", [&] { return extra_int(fields, ppoint_tags); });
                frame.ppoint = std::move(fields);
            } else if (token_ == "cpoint:") block("cpoint_end:", [&] { return catch_point(frame.cpoint); });
            else if (token_ == "wpoint:") block("wpoint_end:", [&] { return weapon_point(frame.wpoint); });
            else if (token_ == "itr:") {
                // Five records in LF2 2.0a; Darkfiren raised the limit to 100.
                if (frame.interactions.size() == max_frame_blocks) {
                    throw ParseFailure{ErrorCode::unsupported,
                                       "more than " + std::to_string(max_frame_blocks) + " itr blocks in a frame"};
                }
                auto& interaction = frame.interactions.emplace_back();
                block("itr_end:", [&] { return interaction_block_field(interaction); });
            } else if (token_ == "bdy:") {
                if (frame.bodies.size() == max_frame_blocks) {
                    throw ParseFailure{ErrorCode::unsupported,
                                       "more than " + std::to_string(max_frame_blocks) + " bdy blocks in a frame"};
                }
                auto& body = frame.bodies.emplace_back();
                block("bdy_end:", [&] {
                    if (token_ == "kind:") read_int(body.kind);
                    else if (token_ == "x:") read_int(body.area.x);
                    else if (token_ == "y:") read_int(body.area.y);
                    else if (token_ == "w:") read_int(body.area.width);
                    else if (token_ == "h:") read_int(body.area.height);
                    else return extra_int(body.extra, body_tags);
                    return true;
                });
            } else if (extra_int(frame.extra, frame_tags) || extra_int(frame.hold, hold_tags) ||
                       extra_int(frame.hit_ext, hit_ext_tags)) {
            } else note("ignored frame token `" + token_ + "`");
            next_token(section);
        }
        // The single-record keys of LF2 2.0a mirror the first block of each list.
        if (!frame.sounds.empty()) frame.sound = frame.sounds.front();
        if (!frame.opoints.empty()) frame.opoint = frame.opoints.front();
        if (!frame.bpoints.empty()) frame.bpoint = frame.bpoints.front();
        if (!frame.interactions.empty()) frame.interaction_bounds = bounds(frame.interactions);
        if (!frame.bodies.empty()) frame.body_bounds = bounds(frame.bodies);
    }

    TokenStream stream_;
    ObjectData data_;
    std::string token_;
    PendingSheet pending_;
};

ScriptValue integer(std::int32_t value) { return ScriptValue{value}; }
ScriptValue text(std::string value) { return ScriptValue{std::move(value)}; }
ScriptValue table(ScriptTable fields) { return ScriptValue{std::move(fields)}; }

void set_optional(ScriptTable& target, std::string key, const std::optional<std::int32_t>& value) {
    if (value) set_field(target, std::move(key), integer(*value));
}
void set_optional(ScriptTable& target, std::string key, const std::optional<double>& value) {
    if (value) set_field(target, std::move(key), ScriptValue{*value});
}
void set_optional(ScriptTable& target, std::string key, const std::optional<std::string>& value) {
    if (value) set_field(target, std::move(key), text(*value));
}

ScriptValue extra_value(const ExtraItem& item) {
    if (item.kind == ExtraItem::Kind::text) return text(item.text);
    if (item.kind == ExtraItem::Kind::set) {
        ScriptTable members;
        for (const auto value : item.values) set_field(members, value, ScriptValue{true});
        return table(std::move(members));
    }
    if (item.kind == ExtraItem::Kind::integer) return integer(item.values.empty() ? 0 : item.values.front());
    if (item.kind == ExtraItem::Kind::groups) {
        ScriptTable outer;
        for (std::size_t group = 0; group < item.groups.size(); ++group) {
            ScriptTable inner;
            for (std::size_t index = 0; index < item.groups[group].size(); ++index) {
                set_field(inner, static_cast<std::int32_t>(index + 1), integer(item.groups[group][index]));
            }
            set_field(outer, static_cast<std::int32_t>(group + 1), table(std::move(inner)));
        }
        return table(std::move(outer));
    }
    ScriptTable list;
    for (std::size_t index = 0; index < item.values.size(); ++index) {
        set_field(list, static_cast<std::int32_t>(index + 1), integer(item.values[index]));
    }
    return table(std::move(list));
}

void append_extras(ScriptTable& target, const Extras& extras) {
    for (const auto& item : extras) set_field(target, item.key, extra_value(item));
}

ScriptValue extras_table(const Extras& extras) {
    ScriptTable result;
    append_extras(result, extras);
    return table(std::move(result));
}

ScriptValue object_point_value(const ObjectPoint& o) {
    ScriptTable result{{"kind", integer(o.kind)}, {"x", integer(o.x)}, {"y", integer(o.y)},
                       {"action", integer(o.action)}, {"dvx", integer(o.dvx)},
                       {"dvy", integer(o.dvy)}, {"oid", integer(o.oid)},
                       {"facing", integer(o.facing)}};
    append_extras(result, o.extra);
    return table(std::move(result));
}

ScriptValue body_point_value(const BodyPoint& b) {
    ScriptTable result{{"x", integer(b.x)}, {"y", integer(b.y)}};
    append_extras(result, b.extra);
    return table(std::move(result));
}

ScriptValue rectangle(const Rectangle& area) {
    return table({{"x", integer(area.x)}, {"y", integer(area.y)},
                  {"width", integer(area.width)}, {"height", integer(area.height)}});
}
ScriptValue pair(const std::array<std::int32_t, 2>& values) {
    return table({{1, integer(values[0])}, {2, integer(values[1])}});
}
ScriptTable interaction_fields(const Interaction& value) {
    ScriptTable result{{"kind", integer(value.kind)}, {"x", integer(value.area.x)},
            {"y", integer(value.area.y)}, {"width", integer(value.area.width)},
            {"height", integer(value.area.height)}, {"dvx", integer(value.dvx)},
            {"dvy", integer(value.dvy)}, {"fall", integer(value.fall)},
            {"arest", integer(value.arest)}, {"vrest", integer(value.vrest)},
            {"respond", integer(value.respond)}, {"effect", integer(value.effect)},
            {"catching_actions", pair(value.catching_actions)},
            {"caught_actions", pair(value.caught_actions)}, {"bdefend", integer(value.bdefend)},
            {"injury", integer(value.injury)}, {"zwidth", integer(value.zwidth)}};
    append_extras(result, value.extra);
    return result;
}

ScriptValue frame_value(const Frame& frame) {
    static constexpr std::array<std::string_view, 10> hit_names{
        "a", "d", "j", "Fa", "Ua", "Da", "Fj", "Uj", "Dj", "ja"};
    ScriptTable hits;
    for (std::size_t index = 0; index < hit_names.size(); ++index) {
        set_field(hits, std::string(hit_names[index]), integer(frame.hits[index]));
    }
    const auto& c = frame.cpoint;
    const auto& w = frame.wpoint;
    ScriptTable catch_point{{"kind", integer(c.kind)}, {"x", integer(c.x)}, {"y", integer(c.y)},
        {"injury", integer(c.injury)}, {"cover", integer(c.cover)},
        {"vaction", integer(c.vaction)}, {"aaction", integer(c.aaction)},
        {"jaction", integer(c.jaction)}, {"daction", integer(c.daction)},
        {"taction", integer(c.taction)}, {"throwvx", integer(c.throwvx)},
        {"throwvy", integer(c.throwvy)}, {"hurtable", integer(c.hurtable)},
        {"decrease", integer(c.decrease)}, {"dircontrol", integer(c.dircontrol)}};
    set_optional(catch_point, "throwinjury", c.throwinjury);
    set_optional(catch_point, "throwvz", c.throwvz);
    append_extras(catch_point, c.extra);
    ScriptTable interactions;
    for (std::size_t index = 0; index < frame.interactions.size(); ++index) {
        set_field(interactions, static_cast<std::int32_t>(index + 1),
                  table(interaction_fields(frame.interactions[index])));
    }
    ScriptTable bodies;
    for (std::size_t index = 0; index < frame.bodies.size(); ++index) {
        const auto& body = frame.bodies[index];
        set_field(bodies, static_cast<std::int32_t>(index + 1),
                  table([&] {
                      ScriptTable fields{{"kind", integer(body.kind)}, {"x", integer(body.area.x)},
                                         {"y", integer(body.area.y)}, {"width", integer(body.area.width)},
                                         {"height", integer(body.area.height)}};
                      append_extras(fields, body.extra);
                      return fields;
                  }()));
    }
    ScriptTable result{{"name", text(frame.name)}, {"picture", integer(frame.picture)},
        {"state", integer(frame.state)}, {"wait", integer(frame.wait)},
        {"next", integer(frame.next)}, {"dvx", integer(frame.dvx)}, {"dvy", integer(frame.dvy)},
        {"dvz", integer(frame.dvz)}, {"center_x", integer(frame.center_x)},
        {"center_y", integer(frame.center_y)}, {"mp", integer(frame.mp)},
        {"hits", table(std::move(hits))},
        {"opoint", object_point_value(frame.opoint)},
        {"bpoint", body_point_value(frame.bpoint)},
        {"cpoint", table(std::move(catch_point))},
        {"wpoint", table({{"kind", integer(w.kind)}, {"x", integer(w.x)}, {"y", integer(w.y)},
                          {"weaponact", integer(w.weaponact)}, {"attacking", integer(w.attacking)},
                          {"cover", integer(w.cover)}, {"dvx", integer(w.dvx)},
                          {"dvy", integer(w.dvy)}, {"dvz", integer(w.dvz)}})},
        {"interactions", table(std::move(interactions))}, {"bodies", table(std::move(bodies))},
        {"interaction_bounds", rectangle(frame.interaction_bounds)},
        {"body_bounds", rectangle(frame.body_bounds)}};
    set_optional(result, "sound", frame.sound);
    append_extras(result, frame.extra);
    if (!frame.hold.empty()) set_field(result, "hold", extras_table(frame.hold));
    if (!frame.hit_ext.empty()) set_field(result, "hit_ext", extras_table(frame.hit_ext));
    if (frame.ppoint) set_field(result, "ppoint", extras_table(*frame.ppoint));
    if (!frame.opoints.empty()) {
        ScriptTable list;
        for (std::size_t index = 0; index < frame.opoints.size(); ++index) {
            set_field(list, static_cast<std::int32_t>(index + 1), object_point_value(frame.opoints[index]));
        }
        set_field(result, "opoints", table(std::move(list)));
    }
    if (!frame.bpoints.empty()) {
        ScriptTable list;
        for (std::size_t index = 0; index < frame.bpoints.size(); ++index) {
            set_field(list, static_cast<std::int32_t>(index + 1), body_point_value(frame.bpoints[index]));
        }
        set_field(result, "bpoints", table(std::move(list)));
    }
    if (!frame.sounds.empty()) {
        ScriptTable list;
        for (std::size_t index = 0; index < frame.sounds.size(); ++index) {
            set_field(list, static_cast<std::int32_t>(index + 1), text(frame.sounds[index]));
        }
        set_field(result, "sounds", table(std::move(list)));
    }
    return table(std::move(result));
}
}

Result<ObjectData> parse(std::string_view text) {
    Parser parser(text);
    try {
        return parser.run();
    } catch (const ParseFailure& failure) {
        return fail(failure.code, "line " + std::to_string(parser.line()) + ": " + failure.message);
    }
}

Result<ObjectData> load(const ResourceSource& resources, std::string_view path) {
    auto bytes = read_data_text(resources, path, max_input);
    if (!bytes) return std::unexpected(bytes.error());
    auto parsed = parse(std::string_view(bytes->data(), bytes->size()));
    if (!parsed) parsed.error().message = std::string(path) + ": " + parsed.error().message;
    return parsed;
}

std::optional<PictureCell> find_picture(const ObjectData& data, std::int32_t picture) {
    for (std::size_t index = 0; index < data.sheets.size(); ++index) {
        const auto& sheet = data.sheets[index];
        const auto cell = std::int64_t{picture} - sheet.first_picture;
        if (cell < 0 || cell >= std::int64_t{sheet.columns} * sheet.rows) continue;
        const auto column = static_cast<std::int32_t>(cell % sheet.columns);
        const auto row = static_cast<std::int32_t>(cell / sheet.columns);
        return PictureCell{index, {column * (sheet.cell_width + 1), row * (sheet.cell_height + 1),
                                   sheet.cell_width, sheet.cell_height}};
    }
    return std::nullopt;
}

ScriptValue to_script_value(const ObjectData& data) {
    ScriptTable movement;
    const auto& m = data.movement;
    set_optional(movement, "walking_frame_rate", m.walking_frame_rate);
    set_optional(movement, "walking_speed", m.walking_speed);
    set_optional(movement, "walking_speedz", m.walking_speedz);
    set_optional(movement, "running_frame_rate", m.running_frame_rate);
    set_optional(movement, "running_speed", m.running_speed);
    set_optional(movement, "running_speedz", m.running_speedz);
    set_optional(movement, "heavy_walking_speed", m.heavy_walking_speed);
    set_optional(movement, "heavy_walking_speedz", m.heavy_walking_speedz);
    set_optional(movement, "heavy_running_speed", m.heavy_running_speed);
    set_optional(movement, "heavy_running_speedz", m.heavy_running_speedz);
    set_optional(movement, "jump_height", m.jump_height);
    set_optional(movement, "jump_distance", m.jump_distance);
    set_optional(movement, "jump_distancez", m.jump_distancez);
    set_optional(movement, "dash_height", m.dash_height);
    set_optional(movement, "dash_distance", m.dash_distance);
    set_optional(movement, "dash_distancez", m.dash_distancez);
    set_optional(movement, "rowing_height", m.rowing_height);
    set_optional(movement, "rowing_distance", m.rowing_distance);

    ScriptTable weapon{{"hp", integer(data.weapon_hp)}, {"drop_hurt", integer(data.weapon_drop_hurt)}};
    set_optional(weapon, "hit_sound", data.weapon_hit_sound);
    set_optional(weapon, "drop_sound", data.weapon_drop_sound);
    set_optional(weapon, "broken_sound", data.weapon_broken_sound);

    ScriptTable sheets;
    for (std::size_t index = 0; index < data.sheets.size(); ++index) {
        const auto& sheet = data.sheets[index];
        set_field(sheets, static_cast<std::int32_t>(index + 1),
                  table({{"path", text(sheet.path)}, {"declared_range", text(sheet.declared_range)},
                         {"first_picture", integer(sheet.first_picture)},
                         {"cell_width", integer(sheet.cell_width)},
                         {"cell_height", integer(sheet.cell_height)},
                         {"columns", integer(sheet.columns)}, {"rows", integer(sheet.rows)}}));
    }

    ScriptTable strengths;
    for (std::size_t index = 0; index < data.strengths.size(); ++index) {
        const auto& strength = data.strengths[index];
        if (!strength.referenced && !strength.name) continue;
        auto fields = interaction_fields(strength.values);
        set_optional(fields, "name", strength.name);
        set_field(strengths, static_cast<std::int32_t>(index), table(std::move(fields)));
    }

    ScriptTable frames;
    for (std::size_t index = 0; index < data.frames.size(); ++index) {
        if (data.frames[index].defined) {
            set_field(frames, static_cast<std::int32_t>(index), frame_value(data.frames[index]));
        }
    }

    ScriptTable diagnostics;
    for (std::size_t index = 0; index < data.diagnostics.size(); ++index) {
        set_field(diagnostics, static_cast<std::int32_t>(index + 1), text(data.diagnostics[index]));
    }

    ScriptTable result{{"name", text(data.name)}, {"head", text(data.head)},
        {"movement", table(std::move(movement))}, {"weapon", table(std::move(weapon))},
        {"sheets", table(std::move(sheets))}, {"strengths", table(std::move(strengths))},
        {"frames", table(std::move(frames))}, {"token_checksum", integer(data.token_checksum)},
        {"diagnostics", table(std::move(diagnostics))}};
    set_optional(result, "small", data.small);
    if (!data.header.empty()) set_field(result, "header", extras_table(data.header));
    if (data.stats) set_field(result, "stats", extras_table(*data.stats));
    if (data.armor) set_field(result, "armor", extras_table(*data.armor));
    if (data.weapon_piece) {
        ScriptTable pieces;
        append_extras(pieces, data.weapon_piece->fields);
        for (std::size_t index = 0; index < data.weapon_piece->pieces.size(); ++index) {
            if (data.weapon_piece->pieces[index]) {
                set_field(pieces, static_cast<std::int32_t>(index + 1), extras_table(*data.weapon_piece->pieces[index]));
            }
        }
        set_field(result, "weapon_piece", table(std::move(pieces)));
    }
    if (!data.sound_list.empty()) {
        ScriptTable list;
        for (std::size_t index = 0; index < data.sound_list.size(); ++index) {
            set_field(list, static_cast<std::int32_t>(index + 1), extras_table(data.sound_list[index]));
        }
        set_field(result, "sound_list", table(std::move(list)));
    }
    if (data.skins) {
        ScriptTable skins;
        append_extras(skins, data.skins->fields);
        for (std::size_t index = 0; index < data.skins->entries.size(); ++index) {
            set_field(skins, static_cast<std::int32_t>(index + 1), extras_table(data.skins->entries[index]));
        }
        set_field(result, "skins", table(std::move(skins)));
    }
    if (data.phase) set_field(result, "phase", extras_table(*data.phase));
    if (data.display) {
        const auto& shown = *data.display;
        ScriptTable display;
        const auto bar = [&](const char* key, const std::optional<DisplayBlock>& block) {
            if (!block) return;
            ScriptTable fields;
            append_extras(fields, block->fields);
            if (!block->layers.empty()) {
                ScriptTable layers;
                for (std::size_t index = 0; index < block->layers.size(); ++index) {
                    set_field(layers, static_cast<std::int32_t>(index + 1), extras_table(block->layers[index]));
                }
                set_field(fields, "layers", table(std::move(layers)));
            }
            set_field(display, key, table(std::move(fields)));
        };
        bar("hp_bar", shown.hp_bar);
        bar("mp_bar", shown.mp_bar);
        bar("minibar", shown.minibar);
        bar("bossbar", shown.bossbar);
        bar("effect", shown.effect);
        bar("menu_face", shown.menu_face);
        if (shown.stats_count) {
            ScriptTable counts;
            for (std::size_t index = 0; index < shown.stats_count->size(); ++index) {
                set_field(counts, static_cast<std::int32_t>(index + 1), extras_table((*shown.stats_count)[index]));
            }
            set_field(display, "stats_count", table(std::move(counts)));
        }
        if (shown.team_flag) set_field(display, "team_flag", extras_table(*shown.team_flag));
        if (shown.name) set_field(display, "name", extras_table(*shown.name));
        set_field(result, "display", table(std::move(display)));
    }
    if (!data.command.empty()) {
        ScriptTable list;
        for (std::size_t index = 0; index < data.command.size(); ++index) {
            set_field(list, static_cast<std::int32_t>(index + 1), extras_table(data.command[index]));
        }
        set_field(result, "command", table(std::move(list)));
    }
    return table(std::move(result));
}
}
