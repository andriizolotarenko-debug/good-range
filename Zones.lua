-- Zones: where you can hit or heal from right now, for your class, form and role.
--
--   primary    (green) the range your role works from: melee for warriors, rogues, druids in
--              cat or bear form, Enhancement shamans and non-Holy paladins; shots for hunters;
--              spells and wands for casters and healers; heals (or buffs) on friendly targets
--   secondary  (blue, with its own badge) a range you could also use right now: CHARGE, THROW,
--              SHOOT, WAND, a hunter's MELEE ... Only abilities you can use at this moment count:
--              enough rage or mana, the right form, out of combat if the ability needs it, the
--              right weapon equipped, off cooldown
--   dead       (red) a gap below the furthest range you have (a hunter's 5-8 yd)
--   far        (grey) beyond everything
--
-- Spell IDs are Classic rank 1 (Classic Era, Anniversary and WoW: Forever share them). The
-- yards come from the game for the rank you know, so talents and Forever's own changes count;
-- the yards written here are only used when the client reports none (Classic clients can answer
-- 0 for weapon shots).
local _, ns = ...

local Zones = {}
ns.Zones = Zones

Zones.MELEE = 5

-- every badge text, so the badge can be as wide as the longest
Zones.LABELS = { "MELEE", "RANGED", "CHARGE", "THROW", "SHOOT", "JUDGE", "SHOCK", "HEAL", "BUFF",
  "DEAD ZONE", "OUT OF RANGE", "FRIENDLY" }

local function ids(min, max, ...)
  local out = {}
  for _, id in ipairs({ ... }) do out[#out + 1] = { id, min, max } end
  return out
end

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, e in ipairs(list) do out[#out + 1] = e end
  end
  return out
end

local SHOOT = ids(8, 30, 2480, 7918, 7919)   -- Shoot Bow, Shoot Gun, Shoot Crossbow
local THROW = ids(8, 30, 2764)
local WAND = ids(0, 30, 5019)

-- Entries: { role, tag, spells = { {id, min, max}, ... }, forms = { cat = true, ... } (optional) }.
-- An entry whose role is your primary role is green, any other one blue with its tag.
-- primary: a role, or a function(ctx) -> role. help: heals for friendly targets.
Zones.CLASS = {
  HUNTER = { primary = "ranged", harm = {
    -- Auto Shot, Arcane Shot, Serpent Sting, Concussive Shot, Aimed Shot, Multi-Shot
    { "ranged", "RANGED", ids(8, 35, 75, 3044, 1978, 5116, 19434, 2643) },
  } },
  WARRIOR = { primary = "melee", harm = {
    { "charge", "CHARGE", ids(8, 25, 100, 20252) },   -- Charge, Intercept
    { "throw", "THROW", THROW },
    { "shoot", "SHOOT", SHOOT },
  } },
  ROGUE = { primary = "melee", harm = {
    { "throw", "THROW", THROW },
    { "shoot", "SHOOT", SHOOT },
  } },
  MAGE = { primary = "ranged", harm = {
    -- Frostbolt, Arcane Missiles, Scorch; Fireball, Pyroblast; Fire Blast
    { "ranged", "RANGED", join(ids(0, 30, 116, 5143, 2948), ids(0, 35, 133, 11366), ids(0, 20, 2136)) },
    { "ranged", "RANGED", WAND },   -- a wand counts with the spells
  } },
  WARLOCK = { primary = "ranged", harm = {
    -- Shadow Bolt, Immolate, Corruption, Searing Pain, Curse of Agony
    { "ranged", "RANGED", ids(0, 30, 686, 348, 172, 5676, 980) },
    { "ranged", "RANGED", WAND },   -- a wand counts with the spells
  } },
  PRIEST = { primary = "ranged", harm = {
    -- Smite, Mind Blast, Shadow Word: Pain, Holy Fire; Mind Flay
    { "ranged", "RANGED", join(ids(0, 30, 585, 8092, 589, 14914), ids(0, 20, 15407)) },
    { "ranged", "RANGED", WAND },   -- a wand counts with the spells
  }, help = ids(0, 40, 2050, 2054, 2060, 2061, 139, 17) },   -- heals, Renew, PW:Shield
  DRUID = {
    primary = function(ctx) return (ctx.form == "cat" or ctx.form == "bear") and "melee" or "ranged" end,
    harm = {
      -- Wrath, Moonfire, Starfire, Insect Swarm, Entangling Roots, Faerie Fire (caster forms)
      { "ranged", "RANGED", ids(0, 30, 5176, 8921, 2912, 5570, 339, 770), forms = { caster = true, moonkin = true } },
      { "charge", "CHARGE", ids(8, 25, 16979), forms = { bear = true } },   -- Feral Charge
    },
    help = ids(0, 40, 5185, 774, 8936),   -- Healing Touch, Rejuvenation, Regrowth
  },
  SHAMAN = {
    -- Enhancement (most talent points in tree 2) fights in melee, the others cast
    primary = function(ctx) return ctx.mainTree == 2 and "melee" or "ranged" end,
    harm = {
      { "ranged", "RANGED", ids(0, 30, 403, 421) },              -- Lightning Bolt, Chain Lightning
      { "shock", "SHOCK", ids(0, 20, 8042, 8050, 8056) },        -- Earth, Flame, Frost Shock
    },
    help = ids(0, 40, 331, 8004, 1064),   -- Healing Wave, Lesser Healing Wave, Chain Heal
  },
  -- Holy (most talent points in tree 1) heals and casts from range, the others fight in melee
  -- Retail-only classes: no Classic spell list, just their role
  DEATHKNIGHT = { primary = "melee" },
  DEMONHUNTER = { primary = "melee" },
  MONK = { primary = "melee" },
  EVOKER = { primary = "ranged" },
  PALADIN = { primary = function(ctx) return ctx.mainTree == 1 and "ranged" or "melee" end, harm = {
    { "judge", "JUDGE", ids(0, 10, 20271) },                       -- Judgement
    { "ranged", "RANGED", join(ids(0, 30, 879, 24275), ids(0, 20, 20473)) },   -- Exorcism, HoW, Holy Shock
  }, help = join(ids(0, 40, 635, 19750), ids(0, 20, 20473)) },     -- Holy Light, Flash of Light, Holy Shock
}

-- One entry's spells you know, as { name, id, min, max, fromGame }.
local function knownSpells(spells, ctx)
  local out = {}
  for _, e in ipairs(spells) do
    local base = ctx.getInfo(e[1])
    local mine = base and ctx.known[base.name]
    if mine then
      local info = ctx.getInfo(mine)
      local max = info and info.maxRange or 0
      if max > Zones.MELEE then
        out[#out + 1] = { base.name, mine, info.minRange or 0, max, true }
      else
        out[#out + 1] = { base.name, mine, e[2], e[3], false }
      end
    end
  end
  return out
end

-- Spans { min, max, kind, label } for a target, in priority order (primary first), and the
-- class spells it looked at (for /rp list).
-- ctx: class, hostile, known (name -> spellID), getInfo(id), usable(id) -> ok, noPower,
-- ready(id) -> off cooldown, form, mainTree, primaryRole (a client-wide override, e.g. from
-- the Retail spec), generic = { harm = intervals, help = intervals } for classes without a list.
function Zones.build(ctx)
  local def = Zones.CLASS[ctx.class]
  local spans, diag = {}, {}

  if not ctx.hostile then
    -- friendly target: your heals are the working range (HEAL); without any, your helpful
    -- spells (BUFF)
    local work, label = {}, "HEAL"
    for _, s in ipairs(def and def.help and knownSpells(def.help, ctx) or {}) do
      work[#work + 1] = { s[3], s[4] }
      diag[#diag + 1] = s
    end
    if #work == 0 then work, label = ctx.generic.help, "BUFF" end
    for _, r in ipairs(Zones.merge(work)) do spans[#spans + 1] = { r[1], r[2], "primary", label } end
    return spans, diag
  end

  local primary = ctx.primaryRole
  if not primary then
    primary = def and def.primary or "ranged"
    if type(primary) == "function" then primary = primary(ctx) end
  end

  local secondary = {}
  local anyKnown = false
  for _, entry in ipairs(def and def.harm or {}) do
    local role, tag, list = entry[1], entry[2], entry[3]
    local spells = knownSpells(list, ctx)
    if #spells > 0 then anyKnown = true end
    local formOk = not entry.forms or entry.forms[ctx.form or "caster"]
    for _, s in ipairs(spells) do
      local ok, noPower = ctx.usable(s[2])
      -- the primary range shows even short of mana; anything else only when usable right now
      local available
      if role == primary then
        available = formOk and (ok or noPower) and true or false
      else
        available = formOk and ok and ctx.ready(s[2]) and true or false
      end
      s[6] = available
      diag[#diag + 1] = s
      if available then
        local span = { s[3], s[4], role == primary and "primary" or "secondary", tag }
        if role == primary then spans[#spans + 1] = span else secondary[#secondary + 1] = span end
      end
    end
  end

  if not anyKnown then
    -- no class list for this client (Retail): every harmful spell counts as ranged
    for _, r in ipairs(ctx.generic.harm) do
      local span = { r[1], r[2], primary == "ranged" and "primary" or "secondary", "RANGED" }
      if primary == "ranged" then spans[#spans + 1] = span else secondary[#secondary + 1] = span end
    end
  end

  -- melee: your auto attack is always there, and it is always marked (blue for ranged roles,
  -- even where your spells also reach)
  table.insert(spans, 1, { 0, Zones.MELEE, primary == "melee" and "primary" or "secondary", "MELEE" })
  for _, s in ipairs(secondary) do spans[#spans + 1] = s end
  -- several spells often give the same span: keep one
  local seen, out = {}, {}
  for _, sp in ipairs(spans) do
    local key = table.concat(sp, ",")
    if not seen[key] then seen[key] = true; out[#out + 1] = sp end
  end
  return out, diag
end

-- Your own zones on enemies (Settings > Zones): the zones in a row from 0 yd, as
-- { { kind, to, show, label }, ... } with one entry per kind (primary, secondary, dead). A zone
-- runs from the previous one's end to its own; out of range starts where the last one ends. A zone
-- with show off keeps its place and its badge but is drawn grey, like out of range.
Zones.SET_MAX = 50   -- the furthest a zone you set can end

local KINDS = { "primary", "secondary", "dead" }

-- The list for what spans give now (Auto, as the start of your own). Every kind is in it: one
-- spans don't give is empty and off (the dead zone right after the first zone, others last).
function Zones.partition(spans)
  local edges = { 0 }
  for _, s in ipairs(spans) do
    edges[#edges + 1] = math.min(s[1], Zones.SET_MAX)
    edges[#edges + 1] = math.min(s[2], Zones.SET_MAX)
  end
  table.sort(edges)
  local list, seen = {}, {}
  for i = 2, #edges do
    local a, b = edges[i - 1], edges[i]
    if b > a then
      local kind, label = Zones.at((a + b) / 2, spans)
      if kind == "far" then break end
      local last = list[#list]
      if last and (last.kind == kind or seen[kind]) then
        last.to = b   -- the same kind again: one zone per kind, so the one before takes it
      else
        seen[kind] = true
        list[#list + 1] = { kind = kind, to = b, show = true, label = label }
      end
    end
  end
  local reach = list[#list] and list[#list].to or 0
  local first = list[1] and list[1].label
  for _, kind in ipairs(KINDS) do
    if not seen[kind] then
      local label = kind == "dead" and "DEAD ZONE"
        or (first ~= "MELEE" and kind == "secondary" and "MELEE" or "RANGED")
      local z = { kind = kind, to = reach, show = false, label = label }
      if kind == "dead" and list[1] then
        z.to = list[1].to
        table.insert(list, 2, z)
      else
        list[#list + 1] = z
      end
    end
  end
  return list
end

-- Spans for a list (see Zones.partition).
function Zones.fromList(list)
  local out, from = {}, 0
  for _, z in ipairs(list) do
    if z.to > from then out[#out + 1] = { from, z.to, z.show and z.kind or "far", z.label } end
    from = math.max(from, z.to)
  end
  return out
end

-- Gives an empty zone i some room (up to 3 yd) from the zone after it, or before it at the end.
function Zones.widen(list, i)
  local from = i > 1 and list[i - 1].to or 0
  if list[i].to > from then return end
  local up = Zones.SET_MAX
  for k = i + 1, #list do
    if list[k].to > from then up = list[k].to; break end
  end
  local a = math.min(3, up - from)
  if a > 0 then
    list[i].to = from + a
    for k = i + 1, #list do list[k].to = math.max(list[k].to, list[i].to) end
    return
  end
  local down = 0
  for k = i - 1, 1, -1 do
    if list[k].to < from then down = list[k].to; break end
  end
  local start = from - math.min(3, from - down)
  for k = 1, i - 1 do list[k].to = math.min(list[k].to, start) end
end

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

-- d in yd -> kind, label. The first span that covers d wins (melee, then primary, then
-- secondary); a gap below your furthest reach is the dead zone, beyond it you are out of range.
function Zones.at(d, spans)
  local reach, hit = 0, nil
  for _, s in ipairs(spans) do
    if s[2] > reach then reach = s[2] end
    if not hit and d >= s[1] and d <= s[2] then hit = s end
  end
  if hit then return hit[3], hit[4] end
  if d < reach then return "dead", "DEAD ZONE" end
  return "far", "OUT OF RANGE"
end

return Zones
