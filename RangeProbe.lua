-- Range Probe: throwaway test of how closely the distance to the target can be estimated.
-- Next to the target frame: the estimate (B) coloured by zone, and below it the raw bracket,
-- A, B and the true distance when the game gives positions (party members in the open world).
local _, ns = ...

local issecret = issecretvalue or function() return false end
local TICK = 0.05
local YD_TO_M = 0.9144

local db
local est = ns.Estimator.new()
local groups = {}        -- ascending by range: { range, harmItem, friendItem, interact, spells }
local zoneSpells = {}    -- { id, min, max, harmful, helpful }
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

local INTERACT = { [3] = 8, [4] = 28 }
local INTERACT_RACE = { Tauren = { [3] = 6, [4] = 25 }, Scourge = { [3] = 7, [4] = 27 } }

local function build()
  wipe(groups)
  wipe(zoneSpells)
  for range, ids in pairs(ns.HARM_ITEMS) do group(range).harmItem = pickItem(ids) end
  for range, ids in pairs(ns.FRIEND_ITEMS) do group(range).friendItem = pickItem(ids) end
  local _, race = UnitRace("player")
  for index, range in pairs(INTERACT_RACE[race] or INTERACT) do group(range).interact = index end
  for _, id in ipairs(spellbookSpells()) do
    local info = C_Spell.GetSpellInfo(id)
    if info then
      local min, max = info.minRange or 0, info.maxRange or 0
      local z = { id = id, min = min, max = max,
        harmful = C_Spell.IsSpellHarmful(id), helpful = C_Spell.IsSpellHelpful(id) }
      if z.harmful or z.helpful then zoneSpells[#zoneSpells + 1] = z end
      -- A spell with a minimum range says "false" up close too, so it can't bound the bracket.
      if max > 0 and min == 0 then table.insert(group(max).spells, id) end
    end
  end
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

-- "work": something reaches, "dead": too close for what has a minimum range and nothing else
-- reaches, "far": nothing reaches.
local function zone(unit, hostile, d)
  local minNeeded = 0
  local any = false
  for _, z in ipairs(zoneSpells) do
    if (hostile and z.harmful) or (not hostile and z.helpful) then
      local v = C_Spell.IsSpellInRange(z.id, unit)
      if not issecret(v) then
        if v == true then any = true end
        if z.min > minNeeded then minNeeded = z.min end
      end
    end
  end
  if any then return "work" end
  if d and minNeeded > 0 and d < minNeeded then return "dead" end
  return "far"
end

local COLORS = { work = { 0.3, 1, 0.35 }, dead = { 1, 0.25, 0.2 }, far = { 0.6, 0.6, 0.6 } }

-- UI ----------------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "RangeProbeFrame", UIParent)
frame:SetSize(170, 46)
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  db.pos = { point, rel, x, y }
end)
frame:Hide()

local big = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
big:SetPoint("TOPLEFT")
local line1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
line1:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, -2)
local line2 = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -1)

local function place()
  frame:ClearAllPoints()
  if db.pos then
    frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  elseif TargetFrame then
    frame:SetPoint("LEFT", TargetFrame, "RIGHT", 4, 6)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
  end
end

local function u(v)
  if not v then return "?" end
  return db.meters and v * YD_TO_M or v
end

local function fmt(v)
  if not v then return "?" end
  return ("%.1f"):format(u(v))
end

local function bracketText(lo, hi)
  local unitName = db.meters and "m" or "yd"
  if not hi then return (">%s %s"):format(fmt(lo), unitName) end
  return ("%s-%s %s"):format(fmt(lo), fmt(hi), unitName)
end

-- Tick --------------------------------------------------------------------------------------

local acc = 0
local clock = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local dt = acc
  acc = 0
  clock = clock + dt
  local unit = "target"
  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end

  local lo, hi = measure(unit, hostile)
  local ts = speedOf(unit)
  local sp = (speedOf("player") or 0) + (ts or 0)
  local px, py = playerPos()
  -- An unknown target speed counts as standing; the next crossing corrects a wrong guess.
  local c = est:update(clock, dt, lo, hi, sp, px, py, not ts or ts < 0.1)
  local a, b = est:valueA(clock, lo, hi), est:valueB(lo, hi)
  local real = truth(unit)

  local z = zone(unit, hostile, b)
  local col = COLORS[z]
  if b then
    big:SetText(("~%s %s"):format(fmt(b), db.meters and "m" or "yd"))
  else
    big:SetText(bracketText(lo, hi))
  end
  big:SetTextColor(col[1], col[2], col[3])
  line1:SetText(("%s   A %s   B %s"):format(bracketText(lo, hi), fmt(a), fmt(b)))
  line2:SetText(("%s   B by %s   speed %.1f%s"):format(real and ("true " .. fmt(real)) or "true ?",
    est:mode() == "pos" and "position" or "rate", sp,
    targetSpeedSecret and " (target speed hidden)" or ""))

  if c and db.log then
    if c.errA then
      say(("%s %s  A %s (err %.1f)  B %s (err %.1f)  mid err %s  speed %.1f"):format(
        c.dir < 0 and "in" or "out", fmt(c.at), fmt(c.a), u(c.errA), fmt(c.b), u(c.errB),
        c.mid and ("%.1f"):format(u(math.abs(c.mid - c.at))) or "?", sp))
    else
      say(("%s %s  (first crossing on this target)"):format(c.dir < 0 and "in" or "out", fmt(c.at)))
    end
  end
end)

local function refreshShown()
  if UnitExists("target") and not UnitIsDeadOrGhost("target") then frame:Show() else frame:Hide() end
end

-- Commands ----------------------------------------------------------------------------------

local function printStats()
  local s = est.stats
  if s.n == 0 then
    say("no measured crossings yet. Run at a target until its bracket changes twice.")
    return
  end
  say(("%d crossings. Mean error: middle of bracket %.2f, A %.2f, B %.2f %s. Worst: A %.1f, B %.1f.")
    :format(s.n, u(s.midn > 0 and s.mid / s.midn or 0), u(s.a / s.n), u(s.b / s.n),
      db.meters and "m" or "yd", u(s.amax), u(s.bmax)))
end

local function printList()
  say(("%d range steps, %d zone spells. Secret results so far: spell %d, item %d, speed %d. Own position: %s.")
    :format(#groups, #zoneSpells, secrets.spell, secrets.item, secrets.speed, playerPos() and "yes" or "hidden"))
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
  if msg == "log" then
    db.log = not db.log
    say("crossing log " .. (db.log and "on" or "off"))
  elseif msg == "stats" then
    printStats()
  elseif msg == "reset" then
    est:resetStats()
    say("stats cleared")
  elseif msg == "list" then
    printList()
  elseif msg == "m" or msg == "yd" then
    db.meters = msg == "m"
    say("units: " .. (db.meters and "metres" or "yards"))
  elseif msg == "home" then
    db.pos = nil
    place()
  else
    say("/rp log | stats | reset | list | m | yd | home   (Shift+drag moves the readout)")
  end
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
    if db.log == nil then db.log = true end
    place()
    build()
    refreshShown()
  elseif not db then
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    est:reset()
    targetSpeedSecret = false
    refreshShown()
  else
    rebuildSoon()
  end
end)

-- A target that dies stays targeted; hide the readout then.
C_Timer.NewTicker(0.5, function() if db then refreshShown() end end)
