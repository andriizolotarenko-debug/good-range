-- Range Probe: distance to the target from range checks, shown on a sliding range tape.
-- The tape's colours come from your spellbook: blue melee, green shoot / cast / heal, grey dead.
-- Optional detail lines show the raw bracket, estimates A and B and the true distance.
local _, ns = ...

local issecret = issecretvalue or function() return false end
local TICK = 0.05
local YD_TO_M = 0.9144
local MELEE = 5

ns.DEFAULTS = {
  width = 280, height = 40, fontSize = 30, ppy = 57, strip = true,
  unlocked = false, details = false, log = false, noPos = false, meters = false,
}

local db
local est = ns.Estimator.new()
local groups = {}        -- ascending by range: { range, harmItem, friendItem, interact, spells }
local zones = { harm = { work = {} }, help = { work = {} } }
local meleeCandidates = {}   -- harmful spells of melee reach; a real range check proves one
local meleeProven = {}       -- spellID -> true once it answered a range check on an enemy
local secrets = { spell = 0, item = 0, speed = 0 }
local targetSpeedSecret = false

local function say(msg) print("|cff66ccffRange Probe|r " .. msg) end

-- Checkers --------------------------------------------------------------------------------

local function group(range)
  for _, g in ipairs(groups) do
    if g.range == range then return g end
  end
  local g = { range = range, spells = {} }
  groups[#groups + 1] = g
  return g
end

local function itemReady(id)
  return C_Item.IsItemDataCachedByID(id) and C_Item.GetItemInfo(id) ~= nil
end

local function pickItem(ids)
  for _, id in ipairs(ids) do
    if itemReady(id) then return id end
    C_Item.RequestLoadItemDataByID(id)
  end
end

local function spellbookSpells()
  local out = {}
  local bank = Enum.SpellBookSpellBank.Player
  for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
    if info and not info.shouldHide then
      for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
        if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive
            and not item.isOffSpec and item.spellID then
          out[#out + 1] = item.spellID
        end
      end
    end
  end
  return out
end

-- Sorted, merged copy of { {a, b}, ... }.
local function merge(list)
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

local INTERACT = { [3] = 8, [4] = 28 }
local INTERACT_RACE = { Tauren = { [3] = 6, [4] = 25 }, Scourge = { [3] = 7, [4] = 27 } }

local function build()
  wipe(groups)
  for range, ids in pairs(ns.HARM_ITEMS) do group(range).harmItem = pickItem(ids) end
  for range, ids in pairs(ns.FRIEND_ITEMS) do group(range).friendItem = pickItem(ids) end
  local _, race = UnitRace("player")
  for index, range in pairs(INTERACT_RACE[race] or INTERACT) do group(range).interact = index end

  local harmWork, helpWork = {}, {}
  wipe(meleeCandidates)
  for _, id in ipairs(spellbookSpells()) do
    local info = C_Spell.GetSpellInfo(id)
    if info then
      local min, max = info.minRange or 0, info.maxRange or 0
      -- A spell with a minimum range says "false" up close too, so it can't bound the bracket.
      if max > 0 and min == 0 then table.insert(group(max).spells, id) end
      -- Zones. Melee abilities report no range, like self-centred AoEs, so they are only
      -- candidates until a range check on an enemy answers for one (see probeMelee).
      local harmful, helpful = C_Spell.IsSpellHarmful(id), C_Spell.IsSpellHelpful(id)
      if harmful and max <= MELEE then
        meleeCandidates[#meleeCandidates + 1] = id
      elseif harmful then
        harmWork[#harmWork + 1] = { min, max }
      elseif helpful and max > 0 then
        helpWork[#helpWork + 1] = { min, max }
      end
    end
  end
  local melee = false
  for _, id in ipairs(meleeCandidates) do
    if meleeProven[id] then melee = true end
  end
  zones.harm = { melee = melee, work = merge(harmWork) }
  zones.help = { melee = false, work = merge(helpWork) }

  for i = #groups, 1, -1 do
    local g = groups[i]
    if not g.harmItem and not g.friendItem and not g.interact and #g.spells == 0 then
      table.remove(groups, i)
    end
  end
  table.sort(groups, function(a, b) return a.range < b.range end)
end

local rebuildPending
local function rebuildSoon()
  if rebuildPending then return end
  rebuildPending = true
  C_Timer.After(1, function() rebuildPending = false; build() end)
end

-- true / false / nil (unknown) for one range step.
local function check(g, unit, hostile, restricted)
  local item = hostile and g.harmItem or g.friendItem
  if item and not restricted then
    local v = C_Item.IsItemInRange(item, unit)
    if issecret(v) then
      secrets.item = secrets.item + 1
    else
      g.last = v and "item" or "item-"
      return v and true or false
    end
  end
  if g.interact and not restricted then
    local v = CheckInteractDistance(unit, g.interact)
    if not issecret(v) then
      g.last = v and "interact" or "interact-"
      return v and true or false
    end
  end
  for _, id in ipairs(g.spells) do
    local v = C_Spell.IsSpellInRange(id, unit)
    if issecret(v) then
      secrets.spell = secrets.spell + 1
    elseif v ~= nil then
      g.last = (v and "spell " or "spell- ") .. id
      return v
    end
  end
  g.last = nil
  return nil
end

local function measure(unit, hostile)
  local restricted = InCombatLockdown() and not hostile
  local hi
  local outs = {}
  for _, g in ipairs(groups) do
    local r = check(g, unit, hostile, restricted)
    g.result = r
    if r == true and not hi then hi = g.range end
    if r == false then outs[#outs + 1] = g.range end
  end
  local lo = 0
  for _, r in ipairs(outs) do
    if (not hi or r < hi) and r > lo then lo = r end
  end
  return lo, hi
end

local function speedOf(unit)
  local v = GetUnitSpeed(unit)
  if v == nil then return nil end
  if issecret(v) then
    secrets.speed = secrets.speed + 1
    targetSpeedSecret = true
    return nil
  end
  return v
end

local function playerPos()
  if db and db.noPos then return nil end   -- behave as in a dungeon
  local y, x = UnitPosition("player")
  if not y or issecret(y) or issecret(x) then return nil end
  return x, y
end

local function truth(unit)
  local y1, x1, _, i1 = UnitPosition("player")
  local y2, x2, _, i2 = UnitPosition(unit)
  if not y1 or not y2 then return nil end
  if issecret(y1) or issecret(y2) or issecret(x1) or issecret(x2) or issecret(i1) or issecret(i2) then
    return nil
  end
  if i1 ~= i2 then return nil end
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Zones -------------------------------------------------------------------------------------

-- A spell with melee reach that gives a range answer on an enemy is a melee ability.
local function probeMelee(unit)
  if zones.harm.melee then return end
  for _, id in ipairs(meleeCandidates) do
    local v = C_Spell.IsSpellInRange(id, unit)
    if not issecret(v) and v ~= nil then
      meleeProven[id] = true
      zones.harm.melee = true
      return
    end
  end
end

local hostileTarget = true

-- d in yd. Melee wins up close for classes that have melee abilities.
local function zoneAt(d)
  local z = hostileTarget and zones.harm or zones.help
  if z.melee and d <= MELEE then return "melee" end
  for _, r in ipairs(z.work) do
    if d >= r[1] and d <= r[2] then return "work" end
    if r[1] > d then break end
  end
  return "dead"
end

-- UI ----------------------------------------------------------------------------------------

local tape = ns.Tape.New(UIParent)
local root = tape.root
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self) self:StartMoving() end)
root:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  db.pos = { point, rel, x, y }
end)
root:Hide()

local line1 = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
line1:SetPoint("TOP", root, "BOTTOM", 0, -16)
local line2 = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
line2:SetPoint("TOP", line1, "BOTTOM", 0, -1)

local function place()
  root:ClearAllPoints()
  if db.pos then
    root:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  elseif TargetFrame then
    root:SetPoint("TOP", TargetFrame, "BOTTOM", -20, 4)
  else
    root:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  end
end

local function conv(v) return db.meters and v * YD_TO_M or v end

local function fmt(v)
  if not v then return "?" end
  return ("%.1f"):format(conv(v))
end

local function bracketText(lo, hi)
  local unitName = db.meters and "m" or "yd"
  if not hi then return (">%s %s"):format(fmt(lo), unitName) end
  return ("%s-%s %s"):format(fmt(lo), fmt(hi), unitName)
end

-- the tape works in display units; zones are in yd
local function displayZoneAt(d)
  return zoneAt(db.meters and d / YD_TO_M or d)
end
tape:SetZones(displayZoneAt)

function ns.ApplyLayout()
  if not db then return end
  tape.unitName = db.meters and "m" or "yd"
  tape:SetLayout(db.width, db.height, db.fontSize, db.ppy, db.strip)
  tape:SetUnlocked(db.unlocked)
  line1:SetShown(db.details)
  line2:SetShown(db.details)
  ns.RefreshShown()
end

-- Tick: estimation at 20 Hz on a hidden driver frame -----------------------------------------

local goal, goalLabel        -- what the tape slides towards (display units) and its label
local shown                  -- what the tape shows now
local acc, clock = 0, 0
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local dt = acc
  acc = 0
  clock = clock + dt
  local unit = "target"
  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end
  hostileTarget = hostile
  if hostile then probeMelee(unit) end

  local lo, hi = measure(unit, hostile)
  local ts = speedOf(unit)
  local sp = (speedOf("player") or 0) + (ts or 0)
  local px, py = playerPos()
  -- An unknown target speed counts as standing; the next crossing corrects a wrong guess.
  local c = est:update(clock, dt, lo, hi, sp, px, py, not ts or ts < 0.1)
  local a, b = est:valueA(clock, lo, hi), est:valueB(lo, hi)

  if b then
    goal = conv(b)
    goalLabel = tostring(math.floor(goal))
  else
    goal = conv(lo)
    goalLabel = math.floor(goal) .. "+"
  end

  if db.details then
    local real = truth(unit)
    line1:SetText(("%s   A %s   B %s"):format(bracketText(lo, hi), fmt(a), fmt(b)))
    line2:SetText(("%s   B by %s   speed %.1f%s"):format(real and ("true " .. fmt(real)) or "true ?",
      est:mode() == "pos" and "position" or "rate", sp,
      targetSpeedSecret and " (target speed hidden)" or ""))
  end

  if c and db.log then
    if c.errA then
      say(("%s %s  A %s (err %.1f)  B %s (err %.1f)  mid err %s  speed %.1f"):format(
        c.dir < 0 and "in" or "out", fmt(c.at), fmt(c.a), conv(c.errA), fmt(c.b), conv(c.errB),
        c.mid and ("%.1f"):format(conv(math.abs(c.mid - c.at))) or "?", sp))
    else
      say(("%s %s  (first crossing on this target)"):format(c.dir < 0 and "in" or "out", fmt(c.at)))
    end
  end
end)

-- Drawing: every frame, the tape glides towards the latest estimate.
root:SetScript("OnUpdate", function(_, elapsed)
  if not goal then
    if not db.unlocked then return end
    goal, goalLabel = conv(21.4), tostring(math.floor(conv(21.4)))   -- sample while unlocked
  end
  shown = shown and shown + (goal - shown) * math.min(1, elapsed * 14) or goal
  tape:Draw(shown, goalLabel ~= tostring(math.floor(goal)) and goalLabel or tostring(math.floor(shown)))
end)

function ns.RefreshShown()
  local has = UnitExists("target") and not UnitIsDeadOrGhost("target")
  driver:SetShown(has)
  root:SetShown(has or (db and db.unlocked))
end

-- Commands ----------------------------------------------------------------------------------

local function printStats()
  local s = est.stats
  if s.n == 0 then
    say("no measured crossings yet. Run at a target until its bracket changes twice.")
    return
  end
  say(("%d crossings. Mean error: middle of bracket %.2f, A %.2f, B %.2f %s. Worst: A %.1f, B %.1f.")
    :format(s.n, conv(s.midn > 0 and s.mid / s.midn or 0), conv(s.a / s.n), conv(s.b / s.n),
      db.meters and "m" or "yd", conv(s.amax), conv(s.bmax)))
end

local function zoneText(z)
  local parts = {}
  if z.melee then parts[#parts + 1] = "melee 0-" .. MELEE end
  for _, r in ipairs(z.work) do parts[#parts + 1] = ("work %g-%g"):format(r[1], r[2]) end
  return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function printList()
  say(("%d range steps. Secret results so far: spell %d, item %d, speed %d. Own position: %s.")
    :format(#groups, secrets.spell, secrets.item, secrets.speed, playerPos() and "yes" or "hidden"))
  say("zones on enemies: " .. zoneText(zones.harm) .. "; on friends: " .. zoneText(zones.help))
  for _, g in ipairs(groups) do
    local parts = {}
    if g.harmItem then parts[#parts + 1] = "harm item " .. g.harmItem end
    if g.friendItem then parts[#parts + 1] = "friend item " .. g.friendItem end
    if g.interact then parts[#parts + 1] = "interact " .. g.interact end
    if #g.spells > 0 then parts[#parts + 1] = #g.spells .. " spells" end
    local r = g.result == true and "|cff4dff59in|r" or g.result == false and "|cffff4433out|r" or "-"
    print(("  %3d yd  %s  %s  %s"):format(g.range, r, table.concat(parts, ", "), g.last or ""))
  end
end

SLASH_RANGEPROBE1 = "/rp"
SlashCmdList.RANGEPROBE = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "stats" then
    printStats()
  elseif msg == "reset" then
    est:resetStats()
    say("stats cleared")
  elseif msg == "list" then
    printList()
  elseif msg == "" or msg == "config" or msg == "options" then
    ns.OpenOptions()
  else
    say("/rp opens the options.  /rp stats | reset | list")
  end
end

function ns.ResetPosition()
  db.pos = nil
  place()
end

function ns.OnNoPosChanged()
  est:reset()
  est:resetStats()
end

-- Events ------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RangeProbeDB = RangeProbeDB or {}
    db = RangeProbeDB
    for k, v in pairs(ns.DEFAULTS) do
      if db[k] == nil then db[k] = v end
    end
    ns.db = db
    place()
    build()
    ns.CreateOptions(db)
    ns.ApplyLayout()
  elseif not db then
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    est:reset()
    targetSpeedSecret = false
    goal, shown = nil, nil
    if UnitExists("target") then
      local hostile = UnitCanAttack("player", "target")
      hostileTarget = issecret(hostile) or hostile
    end
    ns.RefreshShown()
  else
    rebuildSoon()
  end
end)

-- A target that dies stays targeted; hide the tape then.
C_Timer.NewTicker(0.5, function() if db then ns.RefreshShown() end end)
