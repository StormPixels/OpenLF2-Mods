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
    return {pool = pools, start = pool, default = settings.kind or 100, groups = settings.groups or {}, out = {}}
end

function cost.price(self, id)
    return self.groups[id] or self.default
end

-- A fighter of `team` with record `id` was beaten. Returns "respawn" and the part (0 to 1) of its hp and mp it comes
-- back with, or "out" when the pool is spent (the team has lost).
function cost.beaten(self, team, id)
    if self.pool[team] == nil or self.out[team] then return "out", 0 end
    local price = cost.price(self, id)
    local left = self.pool[team] - price
    if left <= 0 then
        self.pool[team] = 0
        self.out[team] = true
        return "out", 0
    end
    self.pool[team] = left
    return "respawn", left >= price and 1 or left / price
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
