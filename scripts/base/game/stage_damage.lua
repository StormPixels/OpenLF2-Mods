-- LF2 Darkfiren stage damage modifier (data\stage\dmg.dat, `<stage_dmg_dec>` blocks; AI5).
-- The rules come from sd_global.damage_rules(path) and are kept in state.stage_damage_rules by stage.lua while a stage with a
-- `file:` tag runs (nothing in other modes). stage_damage.apply is the one hook combat.lua calls on every hit's damage.
--
-- Behaviour read from the Darkfiren exe (update 17), with the readme tags:
--   * the blocks are tried in file order and only the FIRST block that matches is used (no multiplying);
--   * a block with decrease <= 0 or team <= 0 is skipped (the numbers are used raw, the readme's "team 1~5" is not checked);
--   * `team:` is the team of the ATTACKER object (the object that owns the hit: the fighter, the ball, the weapon), and
--     `type:` / `id:` are its object type (0 character, 1/2 weapons, 3 ball, 4 baseball, 5 prisoner, 6 drink) and its id; an empty
--     list matches everything;
--   * the damage becomes `decrease` percent of itself (decrease 50 = half), rounded to the nearest whole (half up);
--   * it is applied to the damage before drain, gain and the HP subtraction (combat.lua calls this where the <stats> scaling is);
--   * `bound: 1` leaves a friendly-fire hit (victim in the attacker's team) at full damage, any other bound applies the block to it.
--     [BELUM PASTI] The readme says the opposite (1 = friendly fire follows the decrease); this follows the code as read.
local stage_damage = {}

local function cdiv(a, b) -- C division: truncates toward zero
    local q = a / b
    return q < 0 and math.ceil(q) or math.floor(q)
end

-- Percent of the first matching rule, or nil. `attacker` and `victim` are the items (state.items entries).
function stage_damage.percent(rules, attacker, victim)
    if not rules or not attacker then return nil end
    local team, record = attacker.team, attacker.record
    for _, rule in ipairs(rules) do
        if (rule.decrease or 0) > 0 and (rule.team or 0) > 0 and team == rule.team
           and (rule.type_count == 0 or (record and rule.types[record.kind]))
           and (rule.id_count == 0 or (record and rule.ids[record.id])) then
            if rule.bound == 1 and victim and victim.team == team then
                -- friendly fire stays untouched under bound 1; the next block is tried like the original's loop
            else
                return rule.decrease
            end
        end
    end
    return nil
end

-- The damage after the stage's modifier (damage unchanged when no rule applies).
local function item_of(object) -- combat.lua passes its wrappers (.value is the state.items entry); an item itself has .record
    if not object then return nil end
    if object.record then return object end
    return object.value
end

function stage_damage.apply(state, attacker, victim, damage)
    local rules = state and state.stage_damage_rules
    if not rules then return damage end
    local percent = stage_damage.percent(rules, item_of(attacker), item_of(victim))
    if not percent or percent == 100 then return damage end
    local product = damage * percent
    local quotient = cdiv(product, 100)
    if product - quotient * 100 >= 50 then quotient = quotient + 1 end
    return quotient
end

return stage_damage
