-- Zones: where you can hit or heal from, per class.
--
-- Each class lists the abilities that define its working range (rank 1 spell IDs from Classic,
-- which WoW: Forever uses). The ranges themselves are read from the game for the rank you know,
-- so Forever's own changes and range talents count. Utility spells with odd ranges (Hunter's
-- Mark at 100 yd, buffs) are left out on purpose, or they would paint over the dead zone.
-- Melee (0-5 yd) is always marked and wins over everything else. A gap below your longest reach
-- (a hunter's 5-8 yd before Auto Shot starts) is the dead zone; past your longest reach you are
-- out of range.
local _, ns = ...

local Zones = {}
ns.Zones = Zones

Zones.MELEE = 5

local SHOOT = { 2480, 7918, 7919 }   -- Shoot Bow, Shoot Gun, Shoot Crossbow
local THROW = 2764
local WAND = 5019

-- { spellID, min, max }: harm on enemies, help on friends. The yards are the Classic base
-- ranges, used only when the client reports none for a spell you know (Classic clients can
-- answer 0 for Auto Shot and other weapon-based shots).
local function shots(max, ...)
  local out = {}
  for _, id in ipairs({ ... }) do out[#out + 1] = { id, 8, max } end
  return out
end

local function spells(max, ...)
  local out = {}
  for _, id in ipairs({ ... }) do out[#out + 1] = { id, 0, max } end
  return out
end

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, e in ipairs(list) do out[#out + 1] = e end
  end
  return out
end

Zones.CLASS = {
  -- Auto Shot, Arcane Shot, Serpent Sting, Concussive Shot, Aimed Shot, Multi-Shot
  HUNTER = { harm = shots(35, 75, 3044, 1978, 5116, 19434, 2643) },
  -- Charge, Intercept; Throw and Shoot Bow / Gun / Crossbow
  WARRIOR = { harm = join(shots(25, 100, 20252), shots(30, THROW, SHOOT[1], SHOOT[2], SHOOT[3])) },
  ROGUE = { harm = shots(30, THROW, SHOOT[1], SHOOT[2], SHOOT[3]) },
  -- Frostbolt, Missiles, Scorch, wand; Fireball, Pyroblast; Fire Blast; Arcane Intellect
  MAGE = { harm = join(spells(30, 116, 5143, 2948, WAND), spells(35, 133, 11366), spells(20, 2136)),
    help = spells(30, 1459) },
  -- Shadow Bolt, Immolate, Corruption, Searing Pain, Curse of Agony, wand
  WARLOCK = { harm = spells(30, 686, 348, 172, 5676, 980, WAND) },
  -- Smite, Mind Blast, SW:Pain, Holy Fire, wand; Mind Flay; heals and PW:Shield
  PRIEST = { harm = join(spells(30, 585, 8092, 589, 14914, WAND), spells(20, 15407)),
    help = spells(40, 2050, 2054, 2060, 2061, 139, 17) },
  -- Wrath, Moonfire, Starfire, Insect Swarm, Entangling Roots, Faerie Fire; heals
  DRUID = { harm = spells(30, 5176, 8921, 2912, 5570, 339, 770), help = spells(40, 5185, 774, 8936) },
  -- Lightning Bolt, Chain Lightning; Earth, Flame, Frost Shock; heals
  SHAMAN = { harm = join(spells(30, 403, 421), spells(20, 8042, 8050, 8056)), help = spells(40, 331, 8004, 1064) },
  -- Exorcism, Hammer of Wrath; Holy Shock; Judgement, Hammer of Justice; heals
  PALADIN = { harm = join(spells(30, 879, 24275), spells(20, 20473), spells(10, 20271, 853)),
    help = join(spells(40, 635, 19750), spells(20, 20473)) },
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

-- The listed spells you know, as { name, min, max, fromGame } (the game's ranges for your rank,
-- or the defaults when it reports none). known: name -> spellID of your spellbook.
function Zones.known(list, known, getInfo)
  local out = {}
  for _, e in ipairs(list or {}) do
    local base = getInfo(e[1])
    local mine = base and known[base.name]
    if mine then
      local info = getInfo(mine)
      local max = info and info.maxRange or 0
      if max > Zones.MELEE then
        out[#out + 1] = { base.name, info.minRange or 0, max, true }
      else
        out[#out + 1] = { base.name, e[2], e[3], false }
      end
    end
  end
  return out
end

-- Merged working intervals of those spells, or nil if you know none of them.
function Zones.fromList(list, known, getInfo)
  local work = {}
  for _, s in ipairs(Zones.known(list, known, getInfo)) do work[#work + 1] = { s[2], s[3] } end
  return #work > 0 and Zones.merge(work) or nil
end

-- d in yd; work: merged intervals. -> "melee", "work", "dead" (a gap you can still reach past)
-- or "far" (beyond everything).
function Zones.at(d, work)
  if d <= Zones.MELEE then return "melee" end
  for _, r in ipairs(work) do
    if d >= r[1] and d <= r[2] then return "work" end
    if r[1] > d then return "dead" end
  end
  return "far"
end

return Zones
