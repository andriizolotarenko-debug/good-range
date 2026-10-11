-- Zones: where you can hit or heal from, per class.
--
-- Each class lists the abilities that define its working range (rank 1 spell IDs from Classic,
-- which WoW: Forever uses). The ranges themselves are read from the game for the rank you know,
-- so Forever's own changes and range talents count. Utility spells with odd ranges (Hunter's
-- Mark at 100 yd, buffs) are left out on purpose, or they would paint over the dead zone.
-- Melee (0-5 yd) is always marked and wins over everything else.
local _, ns = ...

local Zones = {}
ns.Zones = Zones

Zones.MELEE = 5

local SHOOT = { 2480, 7918, 7919 }   -- Shoot Bow, Shoot Gun, Shoot Crossbow
local THROW = 2764
local WAND = 5019

-- harm: on enemies, help: on friends
Zones.CLASS = {
  HUNTER = { harm = { 75, 3044, 1978, 5116, 19434, 2643 } },  -- Auto Shot, Arcane, Serpent, Concussive, Aimed, Multi
  WARRIOR = { harm = { 100, 20252, THROW, SHOOT[1], SHOOT[2], SHOOT[3] } },  -- Charge, Intercept, ranged weapon
  ROGUE = { harm = { THROW, SHOOT[1], SHOOT[2], SHOOT[3] } },
  MAGE = { harm = { 116, 133, 5143, 2136, 2948, 11366, WAND }, help = { 1459 } },  -- Frostbolt, Fireball, AM, Fire Blast, Scorch, Pyro; Arcane Int
  WARLOCK = { harm = { 686, 348, 172, 5676, 980, WAND } },  -- Shadow Bolt, Immolate, Corruption, Searing Pain, CoA
  PRIEST = { harm = { 585, 8092, 589, 15407, 14914, WAND },  -- Smite, Mind Blast, SW:P, Mind Flay, Holy Fire
    help = { 2050, 2054, 2060, 2061, 139, 17 } },             -- Lesser Heal, Heal, Greater, Flash, Renew, PW:S
  DRUID = { harm = { 5176, 8921, 2912, 5570, 339, 770 },     -- Wrath, Moonfire, Starfire, Insect Swarm, Roots, FF
    help = { 5185, 774, 8936 } },                           -- Healing Touch, Rejuvenation, Regrowth
  SHAMAN = { harm = { 403, 421, 8042, 8050, 8056 },          -- Lightning Bolt, Chain Lightning, shocks
    help = { 331, 8004, 1064 } },                           -- Healing Wave, Lesser HW, Chain Heal
  PALADIN = { harm = { 20271, 879, 24275, 20473, 853 },      -- Judgement, Exorcism, HoW, Holy Shock, HoJ
    help = { 635, 19750, 20473 } },                         -- Holy Light, Flash of Light, Holy Shock
}

-- Sorted, merged copy of { {a, b}, ... }.
function Zones.merge(list)
  table.sort(list, function(x, y) return x[1] < y[1] end)
  local out = {}
  for _, r in ipairs(list) do
    local top = out[#out]
    if top and r[1] <= top[2] then
      if r[2] > top[2] then top[2] = r[2] end
    else
      out[#out + 1] = { r[1], r[2] }
    end
  end
  return out
end

-- known: name -> spellID of every spell in your spellbook. getInfo: C_Spell.GetSpellInfo.
-- Returns the merged working intervals of the listed spells you know, or nil if you know none.
function Zones.fromList(ids, known, getInfo)
  if not ids then return nil end
  local work, any = {}, false
  for _, id in ipairs(ids) do
    local base = getInfo(id)
    local mine = base and known[base.name]
    local info = mine and getInfo(mine)
    if info and (info.maxRange or 0) > Zones.MELEE then
      any = true
      work[#work + 1] = { info.minRange or 0, info.maxRange }
    end
  end
  return any and Zones.merge(work) or nil
end

-- d in yd; work: merged intervals.
function Zones.at(d, work)
  if d <= Zones.MELEE then return "melee" end
  for _, r in ipairs(work) do
    if d >= r[1] and d <= r[2] then return "work" end
    if r[1] > d then break end
  end
  return "dead"
end

return Zones
