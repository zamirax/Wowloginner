local _, RLP = ...

local frame

local BUTTONS = {
  { "Check", function() RLP.Check(false) end },
  { "Post Check", function() RLP.Check(true) end },
  { "Pull 10", function() RLP.Pull(10) end },
  { "Cancel Pull", function() RLP.CancelPull() end },
  { "Strat", function() RLP.Strat() end },
  { "Loot Rules", function() RLP.Rules() end },
  { "Report", function() RLP.PostReport() end },
  { "Offenders", function() RLP.Offenders() end },
}

local function Build()
  frame = CreateFrame("Frame", "RaidLeaderProFrame", UIParent, "BackdropTemplate")
  frame:SetSize(180, 40 + 26 * #BUTTONS)
  frame:SetPoint("CENTER", 300, 0)
  frame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  title:SetText("Raid Leader Pro")
  for i, b in ipairs(BUTTONS) do
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(150, 22)
    btn:SetPoint("TOP", 0, -26 - 26 * (i - 1))
    btn:SetText(b[1])
    btn:SetScript("OnClick", b[2])
  end
end

function RLP.ToggleUI()
  if not frame then Build() return end
  frame:SetShown(not frame:IsShown())
end
