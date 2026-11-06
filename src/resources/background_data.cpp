// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/background_data.hpp"
#include "openlf2/resources/data_file.hpp"
#include "openlf2/detail/resources/scan_stream.hpp"

namespace openlf2::background_data {
namespace {
using scanning::ParseFailure;
using scanning::TokenStream;
constexpr std::size_t word_capacity = 100;
constexpr std::size_t max_diagnostics = 64;
constexpr std::size_t max_input = 1024 * 1024;

class Parser {
public:
    explicit Parser(std::string_view text) : stream_(text) {}

    Background run() {
        bool first = true;
        while (!stream_.at_end()) {
            // At EOF the previous word is evaluated again, as in the original loop.
            if (!stream_.word(word_, word_capacity) && first) {
                throw ParseFailure{ErrorCode::format, "background description contains no words"};
            }
            first = false;
            scanning::add_token_checksum(data_.token_checksum, word_);
            if (word_ == "name:") name();
            else if (word_ == "width:") read_int(data_.width);
            else if (word_ == "zboundary:") read_pair(data_.zboundary);
            else if (word_ == "perspective:") {
                if (read_int(data_.perspective[0])) read_int(data_.perspective[1]);
            } else if (word_ == "shadow:") shadow();
            else if (word_ == "layer:") layer();
            else if (word_ == "opoint:") opoint();
            else if (word_ == "frame:") team_frame();
            else if (word_ == "quest:") quest();
            else if (word_ != "layer_end" && word_ != "opoint_end:" && word_ != "frame_end:" && word_ != "quest_end:") note("ignored word `" + word_ + "`");
        }
        return std::move(data_);
    }

    [[nodiscard]] std::size_t line() const { return stream_.line(); }

private:
    void note(std::string message) {
        if (data_.diagnostics.size() < max_diagnostics) {
            data_.diagnostics.push_back("line " + std::to_string(stream_.line()) + ": " +
                                        std::move(message));
        }
    }
    bool read_int(std::int32_t& field) {
        const auto result = stream_.integer(field);
        if (result == TokenStream::Scan::mismatch) {
            note("`" + word_ + "` expects an integer; value left unchanged");
        }
        return result == TokenStream::Scan::value;
    }
    bool read_int(std::optional<std::int32_t>& field) {
        std::int32_t value = field.value_or(0);
        if (!read_int(value)) return false;
        field = value;
        return true;
    }
    void read_pair(std::array<std::optional<std::int32_t>, 2>& fields) {
        if (read_int(fields[0])) read_int(fields[1]);
    }

    void name() {
        std::string value;
        if (!stream_.word(value, word_capacity)) return;
        if (value.size() > 29) value.resize(29);
        for (auto& character : value) {
            if (character == '_') character = ' ';
        }
        data_.name = std::move(value);
    }

    // `%s %s %d %d`: path, a discarded word (`shadowsize:` in the files), width, height.
    void shadow() {
        std::string path;
        std::string ignored;
        if (!stream_.word(path, 40)) return;
        data_.shadow = std::move(path);
        if (!stream_.word(ignored, word_capacity)) return;
        read_pair(data_.shadow_size);
    }

    void layer() {
        if (data_.layers.size() == max_layers) {
            throw ParseFailure{ErrorCode::unsupported, "more than 1000 background layers"};
        }
        auto& layer = data_.layers.emplace_back();
        if (!stream_.word(layer.path, 30)) unterminated();
        next_word();
        while (word_ != "layer_end") {
            if (word_ == "transparency:") read_int(layer.transparency);
            else if (word_ == "width:") read_int(layer.width);
            else if (word_ == "x:") read_int(layer.x);
            else if (word_ == "y:") read_int(layer.y);
            else if (word_ == "height:") read_int(layer.height);
            else if (word_ == "rect:") {
                // The original converts the field even when the read fails.
                read_int(layer.color);
                layer.color = convert_rgb565(layer.color);
            } else if (word_ == "rect32:") read_int(layer.color);
            else if (word_ == "loop:") read_int(layer.loop);
            else if (word_ == "cc:") read_int(layer.cc);
            else if (word_ == "c1:") read_int(layer.c1);
            else if (word_ == "c2:") read_int(layer.c2);
            else if (word_ == "respond:") read_int(layer.respond);
            else if (word_ == "state:") read_int(layer.state);
            else note("ignored layer word `" + word_ + "`");
            next_word();
        }
    }

    // LF2 Darkfiren: `key: value` words up to `opoint_end:`. The keys still count for the checksum (nothing reads a
    // background's checksum), the values do not. Opoints beyond the fiftieth are read and dropped.
    void opoint() {
        Opoint item;
        next_opoint_word();
        while (word_ != "opoint_end:") {
            scanning::add_token_checksum(data_.token_checksum, word_);
            if (word_ == "oid:") read_int(item.oid);
            else if (word_ == "action:") read_int(item.action);
            else if (word_ == "x:") read_int(item.x);
            else if (word_ == "y:") read_int(item.y);
            else if (word_ == "z:") read_int(item.z);
            else if (word_ == "dvx:") read_int(item.dvx);
            else if (word_ == "dvy:") read_int(item.dvy);
            else if (word_ == "dvz:") read_int(item.dvz);
            else if (word_ == "facing:") read_int(item.facing);
            else if (word_ == "team:") read_int(item.team);
            else if (word_ == "hp:") read_int(item.hp);
            else if (word_ == "mp:") read_int(item.mp);
            else if (word_ == "effect:") read_int(item.effect);
            else if (word_ == "arest:") read_int(item.arest);
            else note("ignored opoint word `" + word_ + "`");
            next_opoint_word();
        }
        if (data_.opoints.size() < max_opoints) data_.opoints.push_back(item);
        else note("opoint beyond the fiftieth dropped");
    }
    // LF2 Darkfiren `frame:` ... `frame_end:`: `key: value` words (`pic:` takes a path). As for opoints the keys
    // count for the checksum and the values do not. Frames beyond the fiftieth are read and dropped.
    void team_frame() {
        TeamFrame item;
        next_block_word("frame:");
        while (word_ != "frame_end:") {
            scanning::add_token_checksum(data_.token_checksum, word_);
            if (word_ == "pic:") {
                std::string path;
                if (!stream_.word(path, 60)) unterminated_block("frame:");
                item.path = std::move(path);
            }
            else if (word_ == "team:") read_int(item.team);
            else if (word_ == "type:") read_int(item.type);
            else if (word_ == "x:") read_int(item.x);
            else if (word_ == "y:") read_int(item.y);
            else if (word_ == "w:") read_int(item.w);
            else if (word_ == "h:") read_int(item.h);
            else if (word_ == "dx:") read_int(item.dx);
            else if (word_ == "dy:") read_int(item.dy);
            else if (word_ == "facing:") read_int(item.facing);
            else if (word_ == "respond:") read_int(item.respond);
            else if (word_ == "wait:") read_int(item.wait);
            else if (word_ == "effect:") read_int(item.effect);
            else if (word_ == "cc:") read_int(item.cc);
            else if (word_ == "c1:") read_int(item.c1);
            else if (word_ == "c2:") read_int(item.c2);
            else note("ignored frame word `" + word_ + "`");
            next_block_word("frame:");
        }
        if (data_.team_frames.size() < max_team_frames) data_.team_frames.push_back(std::move(item));
        else note("team bar frame beyond the fiftieth dropped");
    }

    // LF2 Darkfiren `quest:` ... `quest_end:` (up to 5 per background; the rest is read and dropped).
    void quest() {
        Quest item;
        next_block_word("quest:");
        while (word_ != "quest_end:") {
            scanning::add_token_checksum(data_.token_checksum, word_);
            if (word_ == "sound:") {
                std::string path;
                if (!stream_.word(path, 60)) unterminated_block("quest:");
                item.sound = std::move(path);
            }
            else if (word_ == "type:") read_int(item.type);
            else if (word_ == "respond:") read_int(item.respond);
            else if (word_ == "amount:") read_int(item.amount);
            else if (word_ == "start:") read_int(item.start);
            else if (word_ == "recover:") read_int(item.recover);
            else if (word_ == "times:") read_int(item.times);
            else if (word_ == "bound:") read_int(item.bound);
            else if (word_ == "fall:") read_int(item.fall);
            else if (word_ == "next:") read_int(item.next);
            else note("ignored quest word `" + word_ + "`");
            next_block_word("quest:");
        }
        if (data_.quests.size() < max_quests) data_.quests.push_back(std::move(item));
        else note("quest beyond the fifth dropped");
    }
    [[noreturn]] static void unterminated_block(const char* what) {
        throw ParseFailure{ErrorCode::format, std::string("unterminated ") + what + " at end of file"};
    }
    void next_block_word(const char* what) {
        if (!stream_.word(word_, word_capacity)) unterminated_block(what);
    }
    void next_opoint_word() {
        if (!stream_.word(word_, word_capacity)) {
            throw ParseFailure{ErrorCode::format, "unterminated opoint: at end of file"};
        }
    }

    // The layer loop never tests EOF in the original, which would loop forever.
    void next_word() {
        if (!stream_.word(word_, word_capacity)) unterminated();
    }
    [[noreturn]] static void unterminated() {
        throw ParseFailure{ErrorCode::format, "unterminated layer: at end of file"};
    }

    TokenStream stream_;
    Background data_;
    std::string word_;
};

ScriptValue integer(std::int32_t value) { return ScriptValue{value}; }

void set_pair(ScriptTable& target, std::string key, const std::array<std::optional<std::int32_t>, 2>& values) {
    ScriptTable pair;
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (values[index]) set_field(pair, static_cast<std::int32_t>(index + 1), integer(*values[index]));
    }
    set_field(target, std::move(key), ScriptValue{std::move(pair)});
}
}

std::int32_t convert_rgb565(std::int32_t value) {
    const auto red = (value >> 11) & 0x1f;
    const auto green = (value >> 5) & 0x3f;
    const auto blue = value & 0x1f;
    return ((red * 0x200 + green) * 0x80 + blue) * 8 + 0x070707;
}

Result<Background> parse(std::string_view text) {
    Parser parser(text);
    try {
        return parser.run();
    } catch (const ParseFailure& failure) {
        return fail(failure.code, "line " + std::to_string(parser.line()) + ": " + failure.message);
    }
}

Result<Background> load(const ResourceSource& resources, std::string_view path) {
    auto bytes = read_data_text(resources, path, max_input);
    if (!bytes) return std::unexpected(bytes.error());
    auto parsed = parse(std::string_view(bytes->data(), bytes->size()));
    if (!parsed) parsed.error().message = std::string(path) + ": " + parsed.error().message;
    return parsed;
}

ScriptValue to_script_value(const Background& background) {
    ScriptTable layers;
    for (std::size_t index = 0; index < background.layers.size(); ++index) {
        const auto& layer = background.layers[index];
        set_field(layers, static_cast<std::int32_t>(index + 1),
                  ScriptValue{ScriptTable{{"path", ScriptValue{layer.path}},
                      {"transparency", integer(layer.transparency)}, {"width", integer(layer.width)},
                      {"x", integer(layer.x)}, {"y", integer(layer.y)},
                      {"height", integer(layer.height)}, {"color", integer(layer.color)},
                      {"loop", integer(layer.loop)}, {"cc", integer(layer.cc)},
                      {"c1", integer(layer.c1)}, {"c2", integer(layer.c2)},
                      {"respond", integer(layer.respond)}, {"state", integer(layer.state)}}});
    }
    ScriptTable opoints;
    for (std::size_t index = 0; index < background.opoints.size(); ++index) {
        const auto& item = background.opoints[index];
        ScriptTable entry{{"oid", integer(item.oid)}, {"action", integer(item.action)},
                          {"x", integer(item.x)}, {"y", integer(item.y)}, {"z", integer(item.z)},
                          {"dvx", integer(item.dvx)}, {"dvy", integer(item.dvy)}, {"dvz", integer(item.dvz)},
                          {"facing", integer(item.facing)}, {"team", integer(item.team)},
                          {"effect", integer(item.effect)}, {"arest", integer(item.arest)}};
        if (item.hp) set_field(entry, "hp", integer(*item.hp));
        if (item.mp) set_field(entry, "mp", integer(*item.mp));
        set_field(opoints, static_cast<std::int32_t>(index + 1), ScriptValue{std::move(entry)});
    }
    ScriptTable team_frames;
    for (std::size_t index = 0; index < background.team_frames.size(); ++index) {
        const auto& item = background.team_frames[index];
        set_field(team_frames, static_cast<std::int32_t>(index + 1),
                  ScriptValue{ScriptTable{{"path", ScriptValue{item.path}}, {"team", integer(item.team)},
                      {"type", integer(item.type)}, {"x", integer(item.x)}, {"y", integer(item.y)},
                      {"w", integer(item.w)}, {"h", integer(item.h)}, {"dx", integer(item.dx)},
                      {"dy", integer(item.dy)}, {"facing", integer(item.facing)},
                      {"respond", integer(item.respond)}, {"wait", integer(item.wait)},
                      {"effect", integer(item.effect)}, {"cc", integer(item.cc)},
                      {"c1", integer(item.c1)}, {"c2", integer(item.c2)}}});
    }
    ScriptTable quests;
    for (std::size_t index = 0; index < background.quests.size(); ++index) {
        const auto& item = background.quests[index];
        set_field(quests, static_cast<std::int32_t>(index + 1),
                  ScriptValue{ScriptTable{{"sound", ScriptValue{item.sound}}, {"type", integer(item.type)},
                      {"respond", integer(item.respond)}, {"amount", integer(item.amount)},
                      {"start", integer(item.start)}, {"recover", integer(item.recover)},
                      {"times", integer(item.times)}, {"bound", integer(item.bound)},
                      {"fall", integer(item.fall)}, {"next", integer(item.next)}}});
    }
    ScriptTable diagnostics;
    for (std::size_t index = 0; index < background.diagnostics.size(); ++index) {
        set_field(diagnostics, static_cast<std::int32_t>(index + 1), ScriptValue{background.diagnostics[index]});
    }
    ScriptTable result{{"perspective", ScriptValue{ScriptTable{{1, integer(background.perspective[0])},
                                                               {2, integer(background.perspective[1])}}}},
                       {"layers", ScriptValue{std::move(layers)}},
                       {"opoints", ScriptValue{std::move(opoints)}},
                       {"team_frames", ScriptValue{std::move(team_frames)}},
                       {"quests", ScriptValue{std::move(quests)}},
                       {"token_checksum", integer(background.token_checksum)},
                       {"diagnostics", ScriptValue{std::move(diagnostics)}}};
    if (background.name) set_field(result, "name", ScriptValue{*background.name});
    if (background.width) set_field(result, "width", integer(*background.width));
    if (background.shadow) set_field(result, "shadow", ScriptValue{*background.shadow});
    set_pair(result, "zboundary", background.zboundary);
    set_pair(result, "shadow_size", background.shadow_size);
    return ScriptValue{std::move(result)};
}
}
