-- Settings: a small window you can drag around (/goodrange, /gr), so the tape stays visible while you tune it.
-- While the window is open the display is unlocked (shown with a sample value without a target,
-- and draggable, or nudged by the offset sliders over a nameplate); closing it locks it again.
-- Options > AddOns > Good Range only opens this window.
local _, ns = ...

local W = 340
local win

local function label(parent, text, x, y, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function checkbox(parent, text, x, y, get, set, tooltip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)
  local t = cb.Text or cb.text
  if t then t:SetText("") end
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetText(text)
  cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
  if tooltip then
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(text, 1, 1, 1)
      GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
  end
  cb.Refresh = function(self) self:SetChecked(get()) end
  return cb
end

-- x, w: left edge and slider width (default: the full window width)
local function slider(parent, text, y, key, min, max, step, x, w)
  x, w = x or 12, w or W - 80
  label(parent, text, x + 4, y)
  local function changed(v)
    v = math.floor(v / step + 0.5) * step
    if ns.db[key] ~= v then
      ns.db[key] = v
      ns.ApplyLayout()
    end
  end
  local s, template = ns.API.CreateFrameFrom("Frame", nil, parent, { "MinimalSliderWithSteppersTemplate" })
  if template and s.Init then
    -- Retail / Forever: the slider with arrows used by the game's own settings
    s:SetPoint("TOPLEFT", x, y - 16)
    s:SetSize(w, 20)   -- room on the right for the value
    local formatters = {
      [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return tostring(math.floor(v + 0.5)) end,
    }
    s:Init(ns.db[key], min, max, (max - min) / step, formatters)
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v) changed(v) end, s)
    s.Refresh = function(self) self:SetValue(ns.db[key]) end
    return s
  end
  -- older clients: the classic options slider and a value label
  s:Hide()
  local bar = ns.API.CreateFrameFrom("Slider", nil, parent, { "OptionsSliderTemplate", "UISliderTemplate" })
  bar:SetPoint("TOPLEFT", x + 6, y - 20)
  bar:SetSize(w - 10, 16)
  bar:SetOrientation("HORIZONTAL")
  bar:SetMinMaxValues(min, max)
  bar:SetValueStep(step)
  if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
  for _, k in ipairs({ "Low", "High", "Text" }) do
    local fs = bar[k] or (bar:GetName() and _G[bar:GetName() .. k])
    if fs then fs:SetText("") end
  end
  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  value:SetPoint("LEFT", bar, "RIGHT", 10, 0)
  bar:SetScript("OnValueChanged", function(_, v)
    value:SetText(tostring(math.floor(v + 0.5)))
    changed(v)
  end)
  bar.Refresh = function(self) self:SetValue(ns.db[key]); value:SetText(tostring(ns.db[key])) end
  return bar
end

local function fontName(path)
  for _, f in ipairs(ns.Tape.FONTS) do
    if f[1] == path then return f[2] end
  end
  return "Custom"
end

local function build()
  local db = ns.db
  local template
  win, template = ns.API.CreateFrameFrom("Frame", "GoodRangeOptions", UIParent,
    { "DefaultPanelFlatTemplate", "BasicFrameTemplateWithInset" })
  win:SetWidth(W)
  win:SetFrameStrata("DIALOG")
  win:SetToplevel(true)
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.winPos = { point, rel, x, y }
  end)
  if db.winPos then
    win:SetPoint(db.winPos[1], UIParent, db.winPos[2], db.winPos[3], db.winPos[4])
  else
    win:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
  end
  if win.SetTitle then
    win:SetTitle("Good Range")
  elseif win.TitleContainer then
    win.TitleContainer.TitleText:SetText("Good Range")
  else
    local title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:ClearAllPoints()
    title:SetPoint("TOP", 0, -5)
    title:SetText("Good Range")
  end
  if not template or not (win.NineSlice or win.Bg or win.Inset) then
    -- no panel art from a template: a plain dark backing
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
  end
  if not win.CloseButton then
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
  end
  table.insert(UISpecialFrames, "GoodRangeOptions")   -- Esc closes it

  local controls = {}
  local y = -34

  controls[#controls + 1] = checkbox(win, "Minimap button", 12, y,
    function() return not (db.minimap and db.minimap.hide) end,
    function(v) ns.ShowMinimapButton(v) end)
  local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  reset:SetSize(110, 22)
  reset:SetPoint("TOPRIGHT", -14, y - 1)
  reset:SetText("Reset position")
  reset:SetScript("OnClick", function() ns.ResetPosition() end)

  -- display: clickable previews, two to a row: the sliding tape, the number with a zone badge and
  -- the number alone
  y = y - 36
  label(win, "Display", 16, y)
  y = y - 18
  local tiles = {}
  local sample = { { 8, 35, "primary", "RANGED" }, { 0, 5, "secondary", "MELEE" } }   -- a hunter
  local function sampleZone(d) return ns.Zones.at(d, sample) end
  local function showMode()
    for mode, tile in pairs(tiles) do
      local on = db.display == mode
      for _, edge in ipairs(tile.edges) do
        if on then edge:SetColorTexture(1, 0.82, 0, 1) else edge:SetColorTexture(0.4, 0.4, 0.4, 0.8) end
      end
      tile.caption:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7)
      tile.preview:SetLayout(mode == "tape" and 116 or 90, 26, mode == "label" and 18 or 22, 20, db.font, mode)
      tile.preview:Draw(21.4, "21")
      -- the label's badge hangs off the number's left: centre the pair, not the number
      local shift = mode == "label" and (tile.preview.badgeW + tile.preview.badgeGap) / 2 or 0
      tile.preview.root:ClearAllPoints()
      tile.preview.root:SetPoint("CENTER", tile, "CENTER", shift, 7)
    end
  end
  local modes = { { "tape", "Tape" }, { "label", "Label" }, { "number", "Number" } }
  for i, m in ipairs(modes) do
    local tile = CreateFrame("Button", nil, win)
    tile:SetSize((W - 40) / 2, 78)
    tile:SetPoint("TOPLEFT", 14 + (i - 1) % 2 * ((W - 40) / 2 + 12), y - math.floor((i - 1) / 2) * 90)
    local bg = tile:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.03, 0.6)
    tile.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
      local t = tile:CreateTexture(nil, "BORDER")
      t:SetPoint(e[1])
      t:SetPoint(e[2])
      if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
      tile.edges[#tile.edges + 1] = t
    end
    tile.caption = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.caption:SetPoint("BOTTOM", 0, 5)
    tile.caption:SetText(m[2])
    tile.preview = ns.Tape.New(tile)
    tile.preview:SetZones(sampleZone)
    tile.preview.root:Show()
    tile:SetScript("OnClick", function()
      db.display = m[1]
      showMode()
      ns.ApplyLayout()
    end)
    tiles[m[1]] = tile
  end
  controls[#controls + 1] = { Refresh = showMode }

  y = y - 2 - 90 * math.ceil(#modes / 2)
  controls[#controls + 1] = slider(win, "Width", y, "width", 100, 1000, 10)
  y = y - 44
  controls[#controls + 1] = slider(win, "Height", y, "height", 20, 160, 1)
  y = y - 44
  controls[#controls + 1] = slider(win, "Font size", y, "fontSize", 20, 96, 1)
  y = y - 44
  controls[#controls + 1] = slider(win, "Scale (pixels per yard)", y, "ppy", 15, 100, 1)
  y = y - 44
  controls[#controls + 1] = slider(win, "Badge size (label look, %)", y, "badgeScale", 50, 200, 5)

  -- font: step through the list with arrows
  y = y - 48
  label(win, "Font", 16, y)
  local fontText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fontText:SetPoint("TOP", win, "TOP", 0, y - 20)
  local function stepFont(dir)
    local list, at = ns.Tape.FONTS, 1
    for i, f in ipairs(list) do
      if f[1] == db.font then at = i end
    end
    db.font = list[(at - 1 + dir) % #list + 1][1]
    fontText:SetText(fontName(db.font))
    ns.ApplyLayout()
    showMode()
  end
  for _, side in ipairs({ { "<", -1, "LEFT", 14 }, { ">", 1, "RIGHT", -14 } }) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(28, 22)
    b:SetPoint("TOP" .. side[3], win, "TOP" .. side[3], side[4], y - 16)
    b:SetText(side[1])
    b:SetScript("OnClick", function() stepFont(side[2]) end)
  end
  controls[#controls + 1] = { Refresh = function() fontText:SetText(fontName(db.font)) end }

  y = y - 50
  label(win, "Show", 16, y, "GameFontNormalSmall")
  y = y - 16
  local function shownWhen(text, key, x, yy)
    controls[#controls + 1] = checkbox(win, text, x, yy,
      function() return db[key] end, function(v) db[key] = v; ns.RefreshShown() end)
  end
  shownWhen("In combat", "inCombat", 12, y)
  shownWhen("Out of combat", "outOfCombat", W / 2, y)
  y = y - 26
  shownWhen("Enemy target", "enemy", 12, y)
  shownWhen("Friendly target", "friendly", W / 2, y)

  -- over the target's nameplate, nudged by two offsets side by side
  y = y - 30
  controls[#controls + 1] = checkbox(win, "Above the target's nameplate", 12, y,
    function() return db.nameplate end, function(v) db.nameplate = v; ns.ApplyLayout() end,
    "The display hangs over your target's nameplate and moves with it. When the target has no "
      .. "nameplate (nameplates off, or the target too far or off screen) it stays where you put it.")
  y = y - 30
  local half = (W - 24) / 2
  controls[#controls + 1] = slider(win, "Nameplate offset X", y, "plateX", -150, 150, 1, 12, half - 46)
  controls[#controls + 1] = slider(win, "Nameplate offset Y", y, "plateY", -50, 150, 1, 12 + half, half - 46)
  win:SetHeight(-y + 52)

  -- the display is unlocked exactly while this window is open
  win:SetScript("OnShow", function()
    for _, c in ipairs(controls) do c:Refresh() end
    db.unlocked = true
    ns.ApplyLayout()
  end)
  win:SetScript("OnHide", function()
    db.unlocked = false
    ns.ApplyLayout()
  end)
  win:Hide()
end

function ns.CreateOptions()
  -- Options > AddOns > Good Range: a plain panel with a button to the window (clients with the new
  -- Settings UI). A canvas, not a list of settings: the Options search reads every list entry,
  -- and reading one made by an addon taints the search, so the game then blocked Blizzard's own
  -- settings it found (typing "nameplates") and blamed Good Range.
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Good Range")
  local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  note:SetText("A small window you can move, so the display stays in view while you tune it.")
  local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  open:SetSize(180, 24)
  open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
  open:SetText("Open settings window")
  open:SetScript("OnClick", function()
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    ns.OpenOptions()
  end)
  Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "Good Range"))
end

function ns.OpenOptions()
  if not win then build() end
  win:Show()
  win:Raise()
end

function ns.ToggleOptions()
  if win and win:IsShown() then win:Hide() else ns.OpenOptions() end
end
