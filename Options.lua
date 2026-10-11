-- Options > AddOns > Range Probe: tape size, font, scale, unlock to move, and test switches.
local _, ns = ...

local category

local function slider(cat, key, name, min, max, step, tooltip, db)
  local setting = Settings.RegisterProxySetting(cat, "RANGEPROBE_" .. key:upper(), "number", name,
    ns.DEFAULTS[key], function() return db[key] end, function(v) db[key] = v; ns.ApplyLayout() end)
  local options = Settings.CreateSliderOptions(min, max, step)
  options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
  Settings.CreateSlider(cat, setting, options, tooltip)
end

local function checkbox(cat, key, name, tooltip, db, after)
  local setting = Settings.RegisterProxySetting(cat, "RANGEPROBE_" .. key:upper(), "boolean", name,
    ns.DEFAULTS[key], function() return db[key] end,
    function(v) db[key] = v; if after then after(v) end; ns.ApplyLayout() end)
  Settings.CreateCheckbox(cat, setting, tooltip)
end

function ns.CreateOptions(db)
  local cat, layout = Settings.RegisterVerticalLayoutCategory("Range Probe")
  category = cat

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Range tape"))
  checkbox(cat, "unlocked", "Unlock to move",
    "Shows the tape even without a target. Drag it anywhere, then untick to lock it.", db)
  layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Reset",
    function() ns.ResetPosition() end, "Puts the tape back above your character.", true))
  slider(cat, "width", "Width", 80, 1000, 10, "Width of the tape.", db)
  slider(cat, "height", "Height", 12, 160, 1, "Height of the tape. Ticks and the needle scale with it.", db)
  slider(cat, "fontSize", "Font size", 12, 48, 1, "Size of the distance on top of the tape.", db)
  local fontSetting = Settings.RegisterProxySetting(cat, "RANGEPROBE_FONT", "string", "Font",
    ns.DEFAULTS.font, function() return db.font end, function(v) db.font = v; ns.ApplyLayout() end)
  Settings.CreateDropdown(cat, fontSetting, function()
    local c = Settings.CreateControlTextContainer()
    for _, f in ipairs(ns.Tape.FONTS) do c:Add(f[1], f[2]) end
    return c:GetData()
  end, "Font of the distance.")
  slider(cat, "ppy", "Scale", 20, 100, 1, "Pixels per yard: higher spreads the ticks out.", db)
  checkbox(cat, "strip", "Zone strip", "A thin coloured line under the ticks.", db)
  checkbox(cat, "meters", "Metres", "Show metres instead of yards.", db)

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Testing"))
  checkbox(cat, "details", "Show estimate details",
    "Lines under the tape: raw bracket, estimates A and B, true distance when the game gives it.", db)
  checkbox(cat, "log", "Log crossings to chat",
    "Each time the target crosses a range step, print how far off A and B were.", db)
  checkbox(cat, "noPos", "Ignore own position",
    "Estimate as in a dungeon, where the game hides your position. Clears the stats.", db,
    function() ns.OnNoPosChanged() end)

  Settings.RegisterAddOnCategory(cat)
end

function ns.OpenOptions()
  if category then Settings.OpenToCategory(category:GetID()) end
end
