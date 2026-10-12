-- Minimap button (LibDataBroker + LibDBIcon) and the Retail addon compartment entry: both open
-- the settings window. Skipped when the libraries are absent.
local _, ns = ...

local ICON = "Interface\\AddOns\\GoodRange\\media\\icon"

function ns.InitMinimap(db)
  if not LibStub then return end
  local LDB = LibStub("LibDataBroker-1.1", true)
  local Icon = LibStub("LibDBIcon-1.0", true)
  if not LDB or not Icon then return end

  local launcher = LDB:NewDataObject("GoodRange", {
    type = "launcher",
    label = "Good Range",
    icon = ICON,
    OnClick = function() ns.ToggleOptions() end,
    OnTooltipShow = function(tip)
      tip:AddLine("Good Range")
      tip:AddLine("Click: settings \194\183 Drag: move", 0.6, 0.6, 0.6)
    end,
  })
  db.minimap = db.minimap or { hide = false }
  Icon:Register("GoodRange", launcher, db.minimap)
  ns.MinimapIcon = Icon
end

function ns.ShowMinimapButton(on)
  if not ns.MinimapIcon then return end
  ns.db.minimap.hide = not on
  if on then ns.MinimapIcon:Show("GoodRange") else ns.MinimapIcon:Hide("GoodRange") end
end

-- Retail: Addon compartment (the addon list button by the minimap)
function GoodRange_OnAddonCompartmentClick()
  ns.ToggleOptions()
end
