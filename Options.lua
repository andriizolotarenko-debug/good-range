-- Settings: a small window you can drag around (/goodrange, /gr), so the tape stays visible while you tune it.
-- While the window is open the display is unlocked (shown with a sample value without a target,
-- and draggable, or nudged by the offset sliders over a nameplate); closing it locks it again.
-- Options > AddOns > Good Range only opens this window.
local _, ns = ...

local W = 640
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
-- key: a setting in ns.db, or { get, set } for one kept elsewhere
-- show(v): the value's text; apply(): what a change redraws (default: the layout)
local function slider(parent, text, y, key, min, max, step, x, w, show, apply)
  x, w = x or 12, w or W - 80
  show = show or function(v) return tostring(math.floor(v + 0.5)) end
  apply = apply or ns.ApplyLayout
  local get, set
  if type(key) == "table" then
    get, set = key[1], key[2]
  else
    get, set = function() return ns.db[key] end, function(v) ns.db[key] = v end
  end
  label(parent, text, x + 4, y)
  local function changed(v)
    v = math.floor(v / step + 0.5) * step
    if get() ~= v then
      set(v)
      apply()
    end
  end
  local s, template = ns.API.CreateFrameFrom("Frame", nil, parent, { "MinimalSliderWithSteppersTemplate" })
  if template and s.Init then
    -- Retail / Forever: the slider with arrows used by the game's own settings
    s:SetPoint("TOPLEFT", x, y - 16)
    s:SetSize(w, 20)   -- room on the right for the value
    local formatters = {
      [MinimalSliderWithSteppersMixin.Label.Right] = show,
    }
    s:Init(get(), min, max, (max - min) / step, formatters)
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v) changed(v) end, s)
    s.Refresh = function(self) self:SetValue(get()) end
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
    value:SetText(show(v))
    changed(v)
  end)
  bar.Refresh = function(self) self:SetValue(get()); value:SetText(show(get())) end
  return bar
end

-- The game's colour picker on c ({ r, g, b }), live; Cancel puts the old colour back.
local function pickColor(c, set)
  local r, g, b = c[1], c[2], c[3]
  local function picked() set(ColorPickerFrame:GetColorRGB()) end
  local function cancelled() set(r, g, b) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, swatchFunc = picked, cancelFunc = cancelled })
  else
    -- older clients: the picker's fields, then show it
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = picked, cancelled
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
  end
  ColorPickerFrame:Raise()
end

local function fontName(path)
  for _, f in ipairs(ns.Tape.FONTS) do
    if f[1] == path then return f[2] end
  end
  return "Custom"
end

local SHARE_URL = "https://www.curseforge.com/wow/addons/good-range-target-distance-range-finder"
local SHARE_TEXT = "Good Range shows the exact distance to your target in yards: " .. SHARE_URL

-- the target's name when it is a friendly player, to whisper the link to
local function friendlyTarget()
  local ok, name = pcall(function()
    if UnitIsPlayer("target") and not UnitCanAttack("player", "target") then return GetUnitName("target", true) end
  end)
  if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
end

-- Whisper: ask for a name (the friendly target's to start with), then open the chat box with the
-- whisper written out; the player sends it with Enter.
local function whisperLink(name)
  name = name and strtrim(name) or ""
  local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  if name ~= "" and open then open("/w " .. name .. " " .. SHARE_TEXT) end
end

local function popupEditBox(dialog)
  return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

StaticPopupDialogs.GOODRANGE_WHISPER = {
  text = "Whisper the Good Range link to:",
  button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
  hasEditBox = true,
  OnShow = function(self, name)
    local eb = popupEditBox(self)
    eb:SetText(name or "")
    eb:SetFocus()
  end,
  OnAccept = function(self) whisperLink(popupEditBox(self):GetText()) end,
  EditBoxOnEnterPressed = function(eb)
    whisperLink(eb:GetText())
    eb:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

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
  local function refresh()
    for _, c in ipairs(controls) do c:Refresh() end
  end
  local y = -34
  local y0 = y
  -- two columns: the look on the left, sizes and the nameplate on the right; sharing below both
  local COL = (W - 36) / 2
  local LX, RX = 14, 14 + COL + 8

  -- two pages, picked by the tabs at the top left: the look and place, and the zones
  local pages, tabs = {}, {}
  local function showPage(name)
    db.page = name
    for n, pg in pairs(pages) do
      pg:SetShown(n == name)
      if n == name then win:SetHeight(pg.height) end
    end
    for n, t in pairs(tabs) do
      if n == name then t:LockHighlight() else t:UnlockHighlight() end
    end
    for _, c in ipairs(controls) do c:Refresh() end   -- "Auto now" follows the target
  end
  for i, t in ipairs({ { "display", "Display" }, { "zones", "Zones" } }) do
    local pg = CreateFrame("Frame", nil, win)
    pg:SetAllPoints()
    pages[t[1]] = pg
    local tab = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    tab:SetSize(100, 22)
    tab:SetPoint("TOPLEFT", 12 + (i - 1) * 104, y - 1)
    tab:SetText(t[2])
    tab:SetScript("OnClick", function() showPage(t[1]) end)
    tabs[t[1]] = tab
  end

  controls[#controls + 1] = checkbox(win, "Minimap button", W - 14 - 120 - 16 - 120, y,
    function() return not (db.minimap and db.minimap.hide) end,
    function(v) ns.ShowMinimapButton(v) end)
  StaticPopupDialogs.GOODRANGE_RESET = {
    text = "Reset Good Range's position, sizes, font, colours and zones to the defaults?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function() ns.ResetDefaults(); refresh() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  reset:SetSize(120, 22)
  reset:SetPoint("TOPRIGHT", -14, y - 1)
  reset:SetText("Reset Defaults")
  reset:SetScript("OnClick", function() StaticPopup_Show("GOODRANGE_RESET") end)

  local page = pages.display

  -- left: display, clickable previews two to a row: the sliding tape, the number with a zone
  -- badge and the number alone
  local ly = y - 42
  label(page, "Display", LX + 2, ly)
  ly = ly - 18
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
      tile.preview:SetLayout(mode == "tape" and 116 or 90, 26, (mode == "label" or mode == "badge") and 18 or 22, 20,
        db.font, mode)
      tile.preview:Draw(21.4, "21")
      -- the label's badge hangs off the number's left: centre the pair, not the number
      local shift = mode == "label" and (tile.preview.badgeW + tile.preview.badgeGap) / 2 or 0
      tile.preview.root:ClearAllPoints()
      tile.preview.root:SetPoint("CENTER", tile, "CENTER", shift, 7)
    end
  end
  local modes = { { "tape", "Tape" }, { "label", "Label + Number" }, { "badge", "Label" }, { "number", "Number" } }
  local tileW = (COL - 12) / 2
  for i, m in ipairs(modes) do
    local tile = CreateFrame("Button", nil, page)
    tile:SetSize(tileW, 78)
    tile:SetPoint("TOPLEFT", LX + (i - 1) % 2 * (tileW + 12), ly - math.floor((i - 1) / 2) * 90)
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

  -- font: step through the list with arrows
  ly = ly - 14 - 90 * math.ceil(#modes / 2)
  label(page, "Font", LX + 2, ly)
  local fontText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fontText:SetPoint("TOP", page, "TOPLEFT", LX + COL / 2, ly - 20)
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
  for _, side in ipairs({ { "<", -1, LX }, { ">", 1, LX + COL - 28 } }) do
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(28, 22)
    b:SetPoint("TOPLEFT", side[3], ly - 16)
    b:SetText(side[1])
    b:SetScript("OnClick", function() stepFont(side[2]) end)
  end
  controls[#controls + 1] = { Refresh = function() fontText:SetText(fontName(db.font)) end }

  ly = ly - 62
  label(page, "Show", LX + 2, ly)
  ly = ly - 18
  local function shownWhen(text, key, x, yy)
    controls[#controls + 1] = checkbox(page, text, x, yy,
      function() return db[key] end, function(v) db[key] = v; ns.RefreshShown() end)
  end
  shownWhen("In combat", "inCombat", LX - 2, ly)
  shownWhen("Out of combat", "outOfCombat", LX + COL / 2, ly)
  ly = ly - 26
  shownWhen("Enemy target", "enemy", LX - 2, ly)
  shownWhen("Friendly target", "friendly", LX + COL / 2, ly)
  ly = ly - 30

  -- left: the focus label, off by default; one look, its own size and place
  if ns.HAS_FOCUS then
    ly = ly - 14
    label(page, "Focus target", LX + 2, ly)
    ly = ly - 18
    controls[#controls + 1] = checkbox(page, "Range to your focus", LX - 2, ly,
      function() return db.focus end, function(v) db.focus = v; ns.ApplyLayout() end,
      "A small label with the distance to your focus, coloured by your zones like the main display. "
        .. "Drag it anywhere while this window is open.")
    ly = ly - 30
    controls[#controls + 1] = slider(page, "Scale", ly, "focusScale", 50, 200, 5, LX - 2, COL - 50)
    ly = ly - 44
  end

  -- right: sizes
  local ry = y - 42
  local function sized(text, key, min, max, step)
    controls[#controls + 1] = slider(page, text, ry, key, min, max, step, RX - 2, COL - 50)
    ry = ry - 44
  end
  sized("Width", "width", 100, 1000, 10)
  sized("Height", "height", 20, 160, 1)
  sized("Font size", "fontSize", 20, 96, 1)
  sized("Ruler Scale", "ppy", 10, 40, 1)
  sized("Label size", "badgeScale", 50, 200, 5)

  -- right: over the target's nameplate, nudged by two offsets
  ry = ry - 14
  label(page, "Nameplate attach", RX, ry)
  ry = ry - 18
  controls[#controls + 1] = checkbox(page, "Above the target's nameplate", RX - 2, ry,
    function() return db.nameplate end, function(v) db.nameplate = v; ns.ApplyLayout() end,
    "The display hangs over your target's nameplate and moves with it. When the target has no "
      .. "nameplate (nameplates off, or the target too far or off screen) it stays where you put it.")
  ry = ry - 30
  sized("Offset X", "plateX", -150, 150, 1)
  sized("Offset Y", "plateY", -200, 150, 1)

  -- below both: share the CurseForge link, copied from a box or whispered to a friend
  y = math.min(ly, ry) - 18
  label(page, "Share with a friend", LX + 2, y)
  y = y - 20
  local link = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
  link:SetSize(W - 2 * LX - 2 * (90 + 8) - 6, 22)
  link:SetPoint("TOPLEFT", LX + 6, y)
  link:SetAutoFocus(false)
  link:SetText(SHARE_URL)
  link:SetCursorPosition(0)
  -- read only: any typing puts the link back
  link:SetScript("OnTextChanged", function(self, user)
    if user then self:SetText(SHARE_URL); self:HighlightText() end
  end)
  link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  link:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", link, "BOTTOMLEFT", -4, -3)
  local copy = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  copy:SetSize(90, 22)
  copy:SetPoint("LEFT", link, "RIGHT", 8, 0)
  copy:SetText("Copy")
  copy:SetScript("OnClick", function()
    link:SetFocus()
    link:HighlightText()
    -- the game can't write to the clipboard: select the link for the player's own copy keys
    hint:SetText(((IsMacClient and IsMacClient()) and "Cmd" or "Ctrl") .. "+C copies the link")
  end)
  local whisper = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  whisper:SetSize(90, 22)
  whisper:SetPoint("LEFT", copy, "RIGHT", 8, 0)
  whisper:SetText("Whisper")
  whisper:SetScript("OnClick", function() StaticPopup_Show("GOODRANGE_WHISPER", nil, nil, friendlyTarget()) end)
  y = y - 22 - 18
  page.height = -y + 12

  -- the Zones page: per zone its colour, and on enemies a range of your own instead of the
  -- one from your spells; the dead zone can be switched off
  page = pages.zones
  local zy = y0 - 42
  label(page, "Zones", LX + 2, zy)
  local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", LX + 2, zy - 18)
  note:SetWidth(W - 2 * LX)
  note:SetJustifyH("LEFT")
  note:SetText("Auto: from your class, spec and spells. Ranges you set count on enemies; heals and buffs "
    .. "on friendly targets always come from your spells.")
  zy = zy - 46
  local function swatch(kind, text, x, yy)
    local sw = CreateFrame("Button", nil, page)
    sw:SetSize(18, 18)
    sw:SetPoint("TOPLEFT", x, yy)
    local edge = sw:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.8, 0.8, 0.8, 1)
    local fill = sw:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(1, 1, 1, 1)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    fs:SetText(text)
    sw.Refresh = function()
      local c = ns.Tape.COLORS[kind]
      fill:SetVertexColor(c[1], c[2], c[3])
    end
    sw:SetScript("OnClick", function()
      pickColor(ns.Tape.COLORS[kind], function(r, g, b)
        db.colors[kind] = { r, g, b }
        ns.ApplyLayout()
        showMode()
        sw:Refresh()
      end)
    end)
    sw:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Click to pick the colour", 1, 1, 1)
      GameTooltip:Show()
    end)
    sw:SetScript("OnLeave", GameTooltip_Hide)
    controls[#controls + 1] = sw
  end
  local function yards(v) return math.floor(v + 0.5) .. " yd" end
  -- one zone: its colour, Auto (and Show for the dead zone), and From / To while not on Auto
  local function zoneRow(kind, text, canHide)
    local z = db.zones[kind]
    swatch(kind, text, LX + 2, zy)
    local range = CreateFrame("Frame", nil, page)
    range:SetAllPoints()
    local function showRange() range:SetShown(not z.auto and z.show ~= false) end
    local function changed() showRange(); ns.OnZonesChanged() end
    local x = LX + 2 + 150
    if canHide then
      controls[#controls + 1] = checkbox(page, "Show", x, zy + 3,
        function() return z.show end, function(v) z.show = v; changed() end,
        "Off: no dead zone; a gap below your furthest reach reads out of range.")
      x = x + 90
    end
    -- what Auto gives now; turning Auto off starts the sliders there
    local now = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    now:SetPoint("TOPLEFT", x + 80, zy - 2)
    local function showNow()
      local from, to = ns.AutoRange(kind)
      now:SetText(from and ("Auto now: %g-%g yd"):format(from, to) or "Auto now: none")
    end
    local auto = checkbox(page, "Auto", x, zy + 3,
      function() return z.auto end,
      function(v)
        z.auto = v
        local from, to = ns.AutoRange(kind)
        if not v and from then
          z.from, z.to = math.min(45, math.floor(from + 0.5)), math.min(45, math.floor(to + 0.5))
          for _, s in ipairs(range.sliders) do s:Refresh() end
        end
        changed()
      end,
      "On: from your class, spec, spells and talents. Off: the range you set below, starting from "
        .. "what Auto gives now.")
    controls[#controls + 1] = auto
    controls[#controls + 1] = { Refresh = function() showRange(); showNow() end }
    range.sliders = {}
    zy = zy - 26
    for i, edge in ipairs({ "from", "to" }) do
      range.sliders[i] = slider(range, i == 1 and "From" or "To", zy, {
        function() return z[edge] end, function(v) z[edge] = v end,
      }, 0, 45, 1, (i == 1 and LX or RX) - 2, COL - 50, yards, ns.OnZonesChanged)
      controls[#controls + 1] = range.sliders[i]
    end
    zy = zy - 50
  end
  zoneRow("primary", "Your range")
  zoneRow("secondary", "Other range")
  zoneRow("dead", "Dead zone", true)
  swatch("far", "Out of range", LX + 2, zy)
  local farNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  farNote:SetPoint("TOPLEFT", LX + 2 + 150, zy - 3)
  farNote:SetText("Beyond everything, and friendly players you can't heal or buff.")
  zy = zy - 34
  page.height = -zy + 12

  -- the display is unlocked exactly while this window is open
  win:SetScript("OnShow", function()
    for _, c in ipairs(controls) do c:Refresh() end
    db.unlocked = true
    ns.ApplyLayout()
  end)
  showPage(db.page == "zones" and "zones" or "display")
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
