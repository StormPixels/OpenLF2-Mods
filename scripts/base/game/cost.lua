-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's cost mode: every team has one pool of cost; a beaten fighter costs its price. While the pool is
-- still above 0 the fighter comes back (with hp and mp cut down when what is left does not cover its price); at 0
-- the team is out. settings come from mode_layout.cost_settings: {kind = price of an unlisted fighter, pools =
-- choices for the menu, groups = {[id] = price}}. Compatible with Lua 5.1/LuaJIT.
local cost = {}

-- teams: set of team numbers that take part. Returns nil without a pool.
function cost.create(pool, settings, teams)
    if not pool or pool <= 0 then return nil end
    local pools = {}
    for team in pairs(teams) do pools[team] = pool end
    return {pool = pools, start = pool, default = settings.kind or 100, groups = settings.groups or {}, out = {},
        randoms = settings.randoms or {}, shuffle = settings.shuffle == true, kill_team = settings.team == 1,
        y = settings.y, dy = settings.dy}
end

-- A fighter's own `cost:` in its dat's <bmp_begin> (record.data.header.cost) wins over the mode file's groups and `kind:`
-- (readme/mode dat.txt, as in the u17 pack).
function cost.price(self, id, record)
    local data = type(record) == "table" and record.data
    local header = type(data) == "table" and data.header
    local raw = type(header) == "table" and header.cost
    if type(raw) == "table" then raw = raw[1] end
    local own = tonumber(raw)
    if own and own > 0 then return own end
    return self.groups[id] or self.default
end

-- A fighter of `team` with record `id` was beaten. Returns "respawn" and the part (0 to 1) of its hp and mp it comes
-- back with, or "out" when the pool is spent (the team has lost).
-- `record` is the fighter's record (its own `cost:`); `held` is the highest price it has had so far: a transformation to a
-- dearer fighter raises the price, one to a cheaper fighter does not lower it.
function cost.beaten(self, team, id, record, held)
    if self.pool[team] == nil or self.out[team] then return "out", 0 end
    local price = cost.price(self, id, record)
    if held and held > price then price = held end
    local left = self.pool[team] - price
    if left <= 0 then
        self.pool[team] = 0
        self.out[team] = true
        return "out", 0
    end
    self.pool[team] = left
    return "respawn", left >= price and 1 or left / price
end

-- Respawn shuffle: the id a fighter who chose Random comes back as. It is taken from the first `random:` list of the
-- settings that holds its id (else the first list), never its own id and, as far as the list allows, not one a
-- living fighter already has. `taken` is the set of ids in use; draw(n) gives 0 to n - 1. Returns nil with no list.
function cost.shuffle_id(self, id, taken, draw)
    local group
    for _, list in ipairs(self.randoms) do
        for _, member in ipairs(list) do if member == id then group = list end end
        if group then break end
    end
    group = group or self.randoms[1]
    if not group then return nil end
    local fresh, other = {}, {}
    for _, member in ipairs(group) do
        if member ~= id then
            other[#other + 1] = member
            if not taken[member] then fresh[#fresh + 1] = member end
        end
    end
    local pool = #fresh > 0 and fresh or other
    if #pool == 0 then return nil end
    return pool[draw(#pool) + 1]
end

-- COM backup (LF2 Darkfiren `mark com as backup`, u17 exe 0x4606C0): computers marked in the menu do not fight; they are
-- the line of fighters a human of their team comes back as, while Respawn shuffle is on (Versus only). `list` holds
-- {team =, id =} in slot order.
function cost.set_backups(self, list)
    self.backups, self.backup_used, self.backup_taken, self.backup_count = list, {}, {}, {}
    for _, entry in ipairs(list) do self.backup_count[entry.team] = (self.backup_count[entry.team] or 0) + 1 end
end

-- The backup the human fighter `index` (item 0 to 9) of `team` comes back as, or nil. Each backup is used once for the
-- team; once this human has had as many as the team has, the team's backups are free again (and he starts over).
function cost.backup_for(self, index, team)
    local list = self.backups
    if not list or index >= 10 or not self.backup_count[team] then return nil end
    local taken = self.backup_taken[index] or 0
    if taken == self.backup_count[team] then
        for _, entry in ipairs(list) do if entry.team == team then self.backup_used[entry] = nil end end
        taken = 0
    end
    self.backup_taken[index] = taken
    for _, entry in ipairs(list) do
        if entry.team == team and not self.backup_used[entry] then
            self.backup_used[entry] = true
            self.backup_taken[index] = taken + 1
            return entry
        end
    end
    return nil
end

-- A team with cost left, or one that never had a pool, is not beaten yet.
function cost.standing(self, team)
    return self.pool[team] ~= nil and not self.out[team]
end

-- The team with the most cost left, -1 on a tie (who wins when the time is up).
function cost.leader(self)
    local best, best_team, tied
    for team, left in pairs(self.pool) do
        if best == nil or left > best then best, best_team, tied = left, team, false
        elseif left == best then tied = true end
    end
    return (best == nil or tied) and -1 or best_team
end

return cost
