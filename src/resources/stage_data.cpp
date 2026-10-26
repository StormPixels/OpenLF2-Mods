// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/stage_data.hpp"
#include "openlf2/resources/data_file.hpp"
#include "openlf2/detail/resources/scan_stream.hpp"
#include "openlf2/core/files.hpp"

namespace openlf2::stage_data {
namespace {
using scanning::ParseFailure;
using scanning::TokenStream;
constexpr std::size_t word_capacity = 200;
// `music:` is read into the phase record 0xe0 bytes before its first entry.
constexpr std::size_t music_capacity = 0xe0;
constexpr std::size_t max_diagnostics = 64;
constexpr std::size_t max_input = 4 * 1024 * 1024;

class Parser {
public:
    explicit Parser(std::string_view text) : stream_(text) {}

    StageList run() {
        while (!stream_.at_end()) {
            if (!stream_.word(word_, word_capacity)) break;
            if (word_ == "<stage>") stage();
        }
        return std::move(list_);
    }

    [[nodiscard]] std::size_t line() const { return stream_.line(); }

private:
    // Inside a block the original loops until its end word; at end of file it would repeat the
    // last word forever, so the port rejects the file instead.
    void next_in(std::string_view block) {
        if (!stream_.word(word_, word_capacity)) {
            throw ParseFailure{ErrorCode::format, "unterminated " + std::string(block) + " at end of file"};
        }
    }

    void note(std::string message) {
        if (list_.diagnostics.size() < max_diagnostics) {
            list_.diagnostics.push_back("line " + std::to_string(stream_.line()) + ": " + std::move(message));
        }
    }

    void read_int(std::int32_t& field) {
        if (stream_.integer(field) == TokenStream::Scan::mismatch) {
            note("`" + word_ + "` expects an integer; value left unchanged");
        }
    }

    // A word that names a stage: neither a `tag:` nor a `<tag>`.
    static bool plain_word(const std::string& word) {
        return !word.empty() && word.front() != '<' && word.back() != ':';
    }

    void stage() {
        bool expect_name = false;
        do {
            next_in("<stage>");
            if (expect_name) {
                expect_name = false;
                if (plain_word(word_)) {
                    for (auto& character : word_) if (character == '_') character = ' ';
                    current_stage().name = word_;
                    continue;
                }
            }
            if (current_ >= 0 && list_.stages[static_cast<std::size_t>(current_)]) {
                auto& stage = *list_.stages[static_cast<std::size_t>(current_)];
                if (word_ == "<boss>") stage.boss = true;
                else if (word_ == "bg:") read_int(stage.bg);
                else if (word_ == "end:") read_int(stage.end);
                else if (word_ == "next:") read_int(stage.next);
                else if (word_ == "type:") read_int(stage.type);
                else if (word_ == "ptype:") read_int(stage.ptype);
                else if (word_ == "xpos:") read_int(stage.xpos);
                else if (word_ == "facing:") read_int(stage.facing);
                else if (word_ == "mode:") read_int(stage.mode);
                else if (word_ == "respond:") read_int(stage.respond);
                else if (word_ == "hex:") read_int(stage.hex);
            }
            if (word_ == "id:") {
                std::int32_t id = current_;
                read_int(id);
                if (id < 0 || static_cast<std::size_t>(id) >= max_stages) {
                    throw ParseFailure{ErrorCode::unsupported, "stage id outside 0-199: " + std::to_string(id)};
                }
                current_ = id;
                // `id:` resets every phase and entry of the stage and the phase count.
                list_.stages[static_cast<std::size_t>(id)] = Stage{};
                expect_name = true;
            }
            if (word_ == "<phase>") phase();
        } while (word_ != "<stage_end>");
    }

    Stage& current_stage() {
        if (current_ < 0 || !list_.stages[static_cast<std::size_t>(current_)]) {
            throw ParseFailure{ErrorCode::unsupported, "<phase> before a stage `id:`"};
        }
        return *list_.stages[static_cast<std::size_t>(current_)];
    }

    Entry& current_entry(Phase& phase) {
        if (phase.entries.empty()) {
            throw ParseFailure{ErrorCode::unsupported, "`" + word_ + "` before the phase's first `id:`"};
        }
        return phase.entries.back();
    }

    void phase() {
        auto& stage = current_stage();
        if (stage.phases.size() >= max_phases) throw ParseFailure{ErrorCode::unsupported, "more than 100 phases"};
        stage.phases.emplace_back();
        auto& phase = stage.phases.back();
        // Entries not yet opened keep the x of the stage reset or of the latest `bound:`.
        std::int32_t unopened_x = 500;
        do {
            next_in("<phase>");
            if (word_ == "bound:") {
                read_int(phase.bound);
                unopened_x = phase.bound + 80;
                for (auto& entry : phase.entries) entry.x = unopened_x;
            }
            if (word_ == "id:") {
                if (phase.entries.size() >= max_entries) {
                    throw ParseFailure{ErrorCode::unsupported, "more than 60 entries in a phase"};
                }
                Entry entry;
                entry.x = unopened_x;
                phase.entries.push_back(entry);
                read_int(phase.entries.back().id);
            }
            if (word_ == "music:") {
                std::string music;
                if (stream_.word(music, music_capacity)) phase.music = std::move(music);
            }
            if (word_ == "x:") read_int(current_entry(phase).x);
            if (word_ == "hp:") read_int(current_entry(phase).hp);
            if (word_ == "times:") read_int(current_entry(phase).times);
            if (word_ == "reserve:") read_int(current_entry(phase).reserve);
            if (word_ == "<boss>") current_entry(phase).kind = EntryKind::boss;
            if (word_ == "join:") read_int(current_entry(phase).join);
            if (word_ == "join_reserve:") read_int(current_entry(phase).join_reserve);
            if (word_ == "<soldier>") {
                auto& entry = current_entry(phase);
                entry.kind = EntryKind::soldier;
                entry.times = 50;
            }
            if (word_ == "when_clear_goto_phase:") read_int(phase.when_clear_goto_phase);
            if (word_ == "when_clear_goto_stage:") read_int(phase.when_clear_goto_stage);
            if (word_ == "time:") read_int(phase.time);
            if (word_ == "team:") { std::int32_t team = 0; read_int(team); current_entry(phase).team = team; }
            if (word_ == "mp:") { std::int32_t mp = 0; read_int(mp); current_entry(phase).mp = mp; }
            if (word_ == "z:") { std::int32_t z = 0; read_int(z); current_entry(phase).z = z; }
            if (word_ == "fx:") { std::int32_t fx = 0; read_int(fx); current_entry(phase).fx = fx; }
            if (word_ == "pic:") read_int(current_entry(phase).pic);
            if (word_ == "ratio:") {
                if (stream_.real(current_entry(phase).ratio) == TokenStream::Scan::mismatch) {
                    note("`ratio:` expects a number; value left unchanged");
                }
            }
            if (word_ == "y:") read_int(current_entry(phase).y);
            if (word_ == "act:") read_int(current_entry(phase).act);
        } while (word_ != "<phase_end>");
    }

    TokenStream stream_;
    StageList list_;
    std::string word_;
    std::int32_t current_ = -1;
};

ScriptValue integer(std::int32_t value) { return ScriptValue{value}; }
}

Result<StageList> parse(std::string_view text) {
    Parser parser(text);
    try {
        return parser.run();
    } catch (const ParseFailure& failure) {
        return fail(failure.code, "line " + std::to_string(parser.line()) + ": " + failure.message);
    }
}

namespace {
std::vector<std::string> words_of(std::string_view text) {
    std::vector<std::string> words;
    std::string current;
    for (const char character : text) {
        if (character == ' ' || character == '\t' || character == '\r' || character == '\n') {
            if (!current.empty()) words.push_back(std::move(current));
            current.clear();
        } else {
            current += character;
        }
    }
    if (!current.empty()) words.push_back(std::move(current));
    return words;
}
std::int32_t number_of(const std::string& word) {
    std::int32_t value = 0;
    bool negative = false;
    std::size_t index = 0;
    if (index < word.size() && word[index] == '-') { negative = true; ++index; }
    for (; index < word.size() && word[index] >= '0' && word[index] <= '9' && value < 100000000; ++index) {
        value = value * 10 + (word[index] - '0');
    }
    return negative ? -value : value;
}
std::string spaced(std::string text) {
    for (auto& character : text) if (character == '_') character = ' ';
    return text;
}

// The `<stage_information>` blocks of LF2 Darkfiren's stage.dat. Keys: id name file pic small hex hidden respond
// bound facing effect oid, and <boss>. Words after a key up to the next key belong to it (a path or name is one word).
std::vector<Level> parse_levels(std::string_view text) {
    std::vector<Level> levels;
    const auto words = words_of(text);
    Level level;
    bool inside = false;
    for (std::size_t index = 0; index < words.size(); ++index) {
        const auto& word = words[index];
        if (word == "<stage_information>") { inside = true; level = Level{}; continue; }
        if (word == "<stage_information_end>") { if (inside && levels.size() < 20) levels.push_back(level); inside = false; continue; }
        if (!inside) continue;
        if (word == "<boss>") { level.boss = true; continue; }
        if (word.size() < 2 || word.back() != ':' || index + 1 >= words.size()) continue;
        const auto& value = words[index + 1];
        const auto key = word.substr(0, word.size() - 1);
        if (key == "id") level.id = number_of(value);
        else if (key == "name") level.name = spaced(value);
        else if (key == "file") level.file = value;
        else if (key == "pic") level.pic = value;
        else if (key == "small") level.small = value;
        else if (key == "hex") level.hex = number_of(value);
        else if (key == "hidden") level.hidden = number_of(value);
        else if (key == "respond") level.respond = number_of(value);
        else if (key == "bound") level.bound = number_of(value);
        else if (key == "facing") level.facing = number_of(value);
        else if (key == "effect") level.effect = number_of(value);
        else if (key == "oid" && level.oids.size() < 100) level.oids.push_back(number_of(value));
    }
    return levels;
}
}

Result<StageList> load(const ResourceSource& resources, std::string_view path) {
    auto bytes = read_data_text(resources, path, max_input);
    if (!bytes) return std::unexpected(bytes.error());
    const std::string_view text(bytes->data(), bytes->size());
    if (text.find("<stage_information>") == std::string_view::npos) {
        auto parsed = parse(text);
        if (!parsed) parsed.error().message = std::string(path) + ": " + parsed.error().message;
        return parsed;
    }
    // LF2 Darkfiren: a list of levels. Level L's file holds stages 0, 1, ...; they become stages L * 10 + id.
    StageList combined;
    combined.levels = parse_levels(text);
    for (const auto& level : combined.levels) {
        auto file = virtual_path(level.file);
        if (!file) { combined.diagnostics.push_back("level " + std::to_string(level.id) + ": bad file path"); continue; }
        auto stages = read_data_text(resources, *file, max_input);
        if (!stages) { combined.diagnostics.push_back("level " + std::to_string(level.id) + ": " + stages.error().message); continue; }
        auto parsed = parse(std::string_view(stages->data(), stages->size()));
        if (!parsed) { combined.diagnostics.push_back(*file + ": " + parsed.error().message); continue; }
        for (std::size_t id = 0; id < parsed->stages.size(); ++id) {
            if (!parsed->stages[id]) continue;
            const auto global = static_cast<std::size_t>(level.id) * 10 + id;
            if (level.id < 0 || id >= 10 || global >= max_stages) {
                combined.diagnostics.push_back(*file + ": stage " + std::to_string(id) + " does not fit level " + std::to_string(level.id));
                continue;
            }
            combined.stages[global] = std::move(parsed->stages[id]);
        }
        for (auto& note : parsed->diagnostics) {
            if (combined.diagnostics.size() < max_diagnostics) combined.diagnostics.push_back(*file + ": " + std::move(note));
        }
    }
    return combined;
}

ScriptValue to_script_value(const StageList& list) {
    ScriptTable stages;
    for (std::size_t id = 0; id < list.stages.size(); ++id) {
        if (!list.stages[id]) continue;
        ScriptTable phases;
        for (std::size_t index = 0; index < list.stages[id]->phases.size(); ++index) {
            const auto& phase = list.stages[id]->phases[index];
            ScriptTable entries;
            for (std::size_t position = 0; position < phase.entries.size(); ++position) {
                const auto& entry = phase.entries[position];
                ScriptTable fields{{"id", integer(entry.id)}, {"x", integer(entry.x)},
                    {"hp", integer(entry.hp)}, {"times", integer(entry.times)},
                    {"reserve", integer(entry.reserve)}, {"join", integer(entry.join)},
                    {"join_reserve", integer(entry.join_reserve)}, {"act", integer(entry.act)},
                    {"y", integer(entry.y)}, {"ratio", ScriptValue{entry.ratio}},
                    {"kind", integer(static_cast<std::int32_t>(entry.kind))}, {"pic", integer(entry.pic)}};
                if (entry.team) set_field(fields, "team", integer(*entry.team));
                if (entry.mp) set_field(fields, "mp", integer(*entry.mp));
                if (entry.z) set_field(fields, "z", integer(*entry.z));
                if (entry.fx) set_field(fields, "fx", integer(*entry.fx));
                set_field(entries, static_cast<std::int32_t>(position + 1), ScriptValue{std::move(fields)});
            }
            set_field(phases, static_cast<std::int32_t>(index),
                      ScriptValue{ScriptTable{{"bound", integer(phase.bound)}, {"music", ScriptValue{phase.music}},
                          {"when_clear_goto_phase", integer(phase.when_clear_goto_phase)},
                          {"when_clear_goto_stage", integer(phase.when_clear_goto_stage)}, {"time", integer(phase.time)},
                          {"entry_count", integer(static_cast<std::int32_t>(phase.entries.size()))},
                          {"entries", ScriptValue{std::move(entries)}}}});
        }
        set_field(stages, static_cast<std::int32_t>(id),
                  ScriptValue{ScriptTable{{"phase_count", integer(static_cast<std::int32_t>(list.stages[id]->phases.size()))},
                                          {"phases", ScriptValue{std::move(phases)}},
                                          {"name", ScriptValue{list.stages[id]->name}}, {"boss", integer(list.stages[id]->boss ? 1 : 0)},
                                          {"bg", integer(list.stages[id]->bg)}, {"end", integer(list.stages[id]->end)},
                                          {"next", integer(list.stages[id]->next)}, {"type", integer(list.stages[id]->type)},
                                          {"ptype", integer(list.stages[id]->ptype)}, {"xpos", integer(list.stages[id]->xpos)},
                                          {"facing", integer(list.stages[id]->facing)}, {"mode", integer(list.stages[id]->mode)},
                                          {"respond", integer(list.stages[id]->respond)}, {"hex", integer(list.stages[id]->hex)}}});
    }
    ScriptTable diagnostics;
    for (std::size_t index = 0; index < list.diagnostics.size(); ++index) {
        set_field(diagnostics, static_cast<std::int32_t>(index + 1), ScriptValue{list.diagnostics[index]});
    }
    ScriptTable levels;
    for (std::size_t index = 0; index < list.levels.size(); ++index) {
        const auto& level = list.levels[index];
        ScriptTable oids;
        for (std::size_t position = 0; position < level.oids.size(); ++position) {
            set_field(oids, static_cast<std::int32_t>(position + 1), integer(level.oids[position]));
        }
        ScriptTable fields{{"id", integer(level.id)}, {"name", ScriptValue{level.name}}, {"file", ScriptValue{level.file}},
            {"pic", ScriptValue{level.pic}}, {"small", ScriptValue{level.small}}, {"boss", integer(level.boss ? 1 : 0)},
            {"hex", integer(level.hex)}, {"hidden", integer(level.hidden)}, {"respond", integer(level.respond)},
            {"facing", integer(level.facing)}, {"effect", integer(level.effect)}, {"oids", ScriptValue{std::move(oids)}}};
        if (level.bound) set_field(fields, "bound", integer(*level.bound));
        set_field(levels, static_cast<std::int32_t>(index + 1), ScriptValue{std::move(fields)});
    }
    return ScriptValue{ScriptTable{{"stages", ScriptValue{std::move(stages)}}, {"levels", ScriptValue{std::move(levels)}},
                                   {"diagnostics", ScriptValue{std::move(diagnostics)}}}};
}
}
