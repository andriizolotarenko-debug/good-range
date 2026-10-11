-- Settings: a small window you can drag around (/rp), so the tape stays visible while you tune it.
-- Closing the window locks the tape again. Options > AddOns > Range Probe only opens this window.
local _, ns = ...

local W = 300
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

local function slider(parent, text, y, key, min, max, step)
  label(parent, text, 16, y)
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
    s:SetPoint("TOPLEFT", 12, y - 16)
    s:SetSize(W - 40, 20)
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
  bar:SetPoint("TOPLEFT", 18, y - 20)
  bar:SetSize(W - 90, 16)
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
  win, template = ns.API.CreateFrameFrom("Frame", "RangeProbeOptions", UIParent,
    { "DefaultPanelFlatTemplate", "BasicFrameTemplateWithInset" })
  win:SetSize(W, 600)
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
    win:SetTitle("Range Probe")
  elseif win.TitleContainer then
    win.TitleContainer.TitleText:SetText("Range Probe")
  else
    local title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:ClearAllPoints()
    title:SetPoint("TOP", 0, -5)
    title:SetText("Range Probe")
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
  table.insert(UISpecialFrames, "RangeProbeOptions")   -- Esc closes it

  local controls = {}
  local y = -34

  controls[#controls + 1] = checkbox(win, "Unlock to move", 12, y,
    function() return db.unlocked end,
    function(v) db.unlocked = v; ns.ApplyLayout() end,
    "Shows the tape without a target so you can drag it. Locks again when this window closes.")
  local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  reset:SetSize(110, 22)
  reset:SetPoint("TOPRIGHT", -14, y - 1)
  reset:SetText("Reset position")
  reset:SetScript("OnClick", function() ns.ResetPosition() end)

  y = y - 36
  controls[#controls + 1] = slider(win, "Width", y, "width", 100, 1000, 10)
  y = y - 44
  controls[#controls + 1] = slider(win, "Height", y, "height", 20, 160, 1)
  y = y - 44
  controls[#controls + 1] = slider(win, "Font size", y, "fontSize", 20, 96, 1)
  y = y - 44
  controls[#controls + 1] = slider(win, "Scale (pixels per yard)", y, "ppy", 15, 100, 1)

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
  controls[#controls + 1] = checkbox(win, "Range tape", 12, y,
    function() return db.tape end, function(v) db.tape = v; ns.ApplyLayout() end,
    "Off: no ruler; the distance gets a Melee / Ranged / Dead Zone badge instead.")
  controls[#controls + 1] = checkbox(win, "Zone strip", 150, y,
    function() return db.strip end, function(v) db.strip = v; ns.ApplyLayout() end)

  y = y - 34
  label(win, "Show", 16, y, "GameFontNormalSmall")
  y = y - 16
  local function shownWhen(text, key, x, yy)
    controls[#controls + 1] = checkbox(win, text, x, yy,
      function() return db[key] end, function(v) db[key] = v; ns.RefreshShown() end)
  end
  shownWhen("In combat", "inCombat", 12, y)
  shownWhen("Out of combat", "outOfCombat", 150, y)
  y = y - 26
  shownWhen("Enemy target", "enemy", 12, y)
  shownWhen("Friendly target", "friendly", 150, y)

  y = y - 36
  label(win, "Testing", 16, y, "GameFontNormalSmall")
  y = y - 16
  controls[#controls + 1] = checkbox(win, "Show estimate details", 12, y,
    function() return db.details end, function(v) db.details = v; ns.ApplyLayout() end,
    "Lines under the tape: raw bracket, estimates A and B, true distance when the game gives it.")
  y = y - 26
  controls[#controls + 1] = checkbox(win, "Log crossings to chat", 12, y,
    function() return db.log end, function(v) db.log = v end,
    "Each time the target crosses a range step, print how far off A and B were.")

  win:SetScript("OnShow", function()
    for _, c in ipairs(controls) do c:Refresh() end
  end)
  -- closing the window locks the tape again
  win:SetScript("OnHide", function()
    if db.unlocked then
      db.unlocked = false
      ns.ApplyLayout()
    end
  end)
  win:Hide()
end

function ns.CreateOptions()
  -- Options > AddOns > Range Probe: a pointer to the window (clients with the new Settings UI)
  if not (Settings and Settings.RegisterVerticalLayoutCategory and CreateSettingsButtonInitializer) then
    return
  end
  local cat, layout = Settings.RegisterVerticalLayoutCategory("Range Probe")
  layout:AddInitializer(CreateSettingsButtonInitializer("Range Probe", "Open settings window", function()
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    ns.OpenOptions()
  end, "A small window you can move, so the tape stays in view while you tune it.", true))
  Settings.RegisterAddOnCategory(cat)
end

function ns.OpenOptions()
  if not win then build() end
  win:Show()
  win:Raise()
end
