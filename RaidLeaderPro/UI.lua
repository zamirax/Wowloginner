local ADDON, RLP = ...
local state = RLP.state
local Print = RLP.Print

local UI = {}
RLP.UI = UI

local BACKDROP = { bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local function Panel(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0, 0, 0, 0.92)
  f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  if title then
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 12, -10)
    t:SetText(title)
    f.title = t
  end
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", -2, -2)
  f:Hide()
  return f
end

local function Button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function InCombatBlock()
  if state.inCombat then Print("Setup is locked in combat.") return true end
end

---------------------------------------------------------------- dropdowns
local ddCount = 0
local function Dropdown(parent, width, items, get, set)
  ddCount = ddCount + 1
  local f = CreateFrame("Frame", "RLPDD" .. ddCount, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(f, width)
  local function list() return type(items) == "function" and items() or items end
  function f:Refresh()
    local cur = get()
    local label = ""
    for _, it in ipairs(list()) do if it.value == cur then label = it.label end end
    UIDropDownMenu_SetText(self, label)
  end
  UIDropDownMenu_Initialize(f, function(_, level)
    for _, it in ipairs(list()) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.value, info.checked = it.label, it.value, (get() == it.value)
      info.func = function()
        if InCombatBlock() then return end
        set(it.value)
        f:Refresh()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  return f
end

local menuFrame
local function Menu(entries)
  menuFrame = menuFrame or CreateFrame("Frame", "RLPContextMenu", UIParent, "UIDropDownMenuTemplate")
  EasyMenu(entries, menuFrame, "cursor", 0, 0, "MENU")
end

StaticPopupDialogs["RLP_PROMPT"] = {
  text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self, data)
    local eb = self.editBox or self.EditBox
    if data and eb then data(eb:GetText()) end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    local data = p.data
    if data then data(self:GetText()) end
    p:Hide()
  end,
}

local function Prompt(text, fn) StaticPopup_Show("RLP_PROMPT", text, nil, fn) end

---------------------------------------------------------------- text box (export / import)
local textBox
local function TextBox(title, text, onAccept)
  if not textBox then
    textBox = Panel("RLPTextBox", 520, 330, title)
    local sf = CreateFrame("ScrollFrame", "RLPTextBoxScroll", textBox, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -40) sf:SetPoint("BOTTOMRIGHT", -34, 44)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true) eb:SetFontObject(ChatFontNormal) eb:SetWidth(460) eb:SetAutoFocus(false) eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() textBox:Hide() end)
    sf:SetScrollChild(eb)
    textBox.edit = eb
    textBox.ok = Button(textBox, "Import", 90, function()
      if textBox.accept then textBox.accept(eb:GetText()) end
      textBox:Hide()
    end)
    textBox.ok:SetPoint("BOTTOMRIGHT", -14, 12)
  end
  textBox.title:SetText(title)
  textBox.edit:SetText(text or "")
  textBox.accept = onAccept
  textBox.ok:SetShown(onAccept ~= nil)
  textBox:Show()
  textBox.edit:HighlightText()
  textBox.edit:SetFocus()
end

---------------------------------------------------------------- player picker
local picker
-- list: ordered array of names edited in place. onChange() runs after each toggle.
function UI.Pick(title, list, onChange)
  if InCombatBlock() then return end
  if not picker then
    picker = Panel("RLPPicker", 560, 320, title)
    picker.btns = {}
    picker.hint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.hint:SetPoint("BOTTOMLEFT", 14, 12)
  end
  picker.title:SetText(title)
  picker.hint:SetText("Click to add/remove. The number is the rotation order.")
  local roster = RLP.Roster(true)
  local function paint()
    for i, e in ipairs(roster) do
      local b = picker.btns[i]
      local idx
      for j, n in ipairs(list) do if n == e.name then idx = j end end
      b:SetText((idx and (idx .. ". ") or "") .. RLP.ClassColor(e.class) .. e.name .. "|r")
      b:SetAlpha(idx and 1 or 0.55)
    end
  end
  for i, e in ipairs(roster) do
    local b = picker.btns[i]
    if not b then
      b = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
      b:SetSize(128, 22)
      b:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 134, -38 - math.floor((i - 1) / 4) * 24)
      picker.btns[i] = b
    end
    b:Show()
    b:SetScript("OnClick", function()
      local at
      for j, n in ipairs(list) do if n == e.name then at = j end end
      if at then table.remove(list, at) else table.insert(list, e.name) end
      paint()
      if onChange then onChange() end
    end)
  end
  for i = #roster + 1, #picker.btns do picker.btns[i]:Hide() end
  paint()
  picker:Show()
end

---------------------------------------------------------------- option lists
local function WhoItems()
  return {
    { value = "AFFECTED", label = "Affected player" }, { value = "EVERYONE", label = "Everyone" },
    { value = "PLAYERS", label = "Specific players" }, { value = "ROTATION", label = "Rotation list" },
    { value = "TANKS", label = "All tanks" }, { value = "HEALERS", label = "All healers" },
    { value = "ROLE:MT", label = "Role: MT" }, { value = "ROLE:OT", label = "Role: OT" },
    { value = "ROLE:Dispel|HEALERS", label = "Role: Dispel" }, { value = "ROLE:Decurse|CLASS:MAGE,DRUID", label = "Role: Decurse" },
    { value = "ROLE:Interrupt|CLASS:ROGUE,MAGE", label = "Role: Interrupt" }, { value = "ROLE:Tranq|CLASS:HUNTER", label = "Role: Tranq" },
    { value = "ROLE:CC|CLASS:MAGE", label = "Role: CC" }, { value = "ROLE:Purge|CLASS:PRIEST,SHAMAN", label = "Role: Purge" },
    { value = "CLASS:PRIEST", label = "Class: Priest" }, { value = "CLASS:MAGE", label = "Class: Mage" },
    { value = "CLASS:WARLOCK", label = "Class: Warlock" }, { value = "CLASS:HUNTER", label = "Class: Hunter" },
    { value = "CLASS:ROGUE", label = "Class: Rogue" }, { value = "CLASS:SHAMAN", label = "Class: Shaman" },
    { value = "CLASS:DRUID", label = "Class: Druid" }, { value = "CLASS:PALADIN", label = "Class: Paladin" },
    { value = "CLASS:WARRIOR", label = "Class: Warrior" },
    { value = "GROUP:1", label = "Group 1" }, { value = "GROUP:2", label = "Group 2" }, { value = "GROUP:3", label = "Group 3" },
    { value = "GROUP:4", label = "Group 4" }, { value = "GROUP:5", label = "Group 5" }, { value = "GROUP:6", label = "Group 6" },
    { value = "GROUP:7", label = "Group 7" }, { value = "GROUP:8", label = "Group 8" },
  }
end

-- unknown "who" strings from data files still display
local function WhoLabel(v)
  for _, it in ipairs(WhoItems()) do if it.value == v then return it.label end end
  return v
end

local function ActionItems()
  local t = {}
  for _, a in ipairs(RLP.ActionList) do t[#t + 1] = { value = a[1], label = a[2] } end
  return t
end

local function TemplateItems()
  local t = {}
  for _, id in ipairs(RLP.TemplateOrder) do
    local tpl = RLP.Templates[id]
    t[#t + 1] = { value = id, label = id == "CUSTOM" and "Custom text" or (id .. ": " .. tpl[1]) }
  end
  return t
end

local function SpotItems()
  local t = { { value = "", label = "(none)" }, { value = "MARK", label = "Player's marker" } }
  for i, n in ipairs(RLP.ICONS) do t[#t + 1] = { value = "icon:" .. i, label = "{" .. n .. "}" } end
  local names = {}
  for n in pairs(RLP.db.spots) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do t[#t + 1] = { value = n, label = n } end
  return t
end

---------------------------------------------------------------- boss page
local main, rows, selected
local ROW_H = 30

local function PreviewText(m)
  local cfg = RLP.Cfg(m)
  local short, whisper = RLP.Texts(m, cfg, { target = "<player>", player = "<player>", screen = true })
  local who = cfg.who or ""
  local isWhisper = (cfg.act == "WHISPER" or cfg.act == "WHISPER_RW") and not who:find("^EVERYONE")
  return (isWhisper and "W: " or "") .. (isWhisper and whisper or short)
end

local function UpdateStatus()
  if not main or not selected then return end
  local probs = RLP.Validate(selected)
  if #probs == 0 then
    main.light:SetText("|cff40ff40Ready: setup OK|r")
  else
    main.light:SetText("|cffff4040" .. #probs .. " problem(s): |r" .. probs[1] .. (#probs > 1 and (" (+" .. (#probs - 1) .. ")") or ""))
  end
  local n, total = 0, 0
  for _, b in ipairs(RLP.AllBosses()) do total = total + 1 if RLP.IsConfigured(b) then n = n + 1 end end
  main.progress:SetText(string.format("%d/%d bosses configured", n, total))
end

local function RefreshRow(r)
  local m = r.m
  if not m then return end
  local cfg = RLP.Cfg(m)
  r.check:SetChecked(cfg.on)
  r.name:SetText((m.unsure and "|cffffd100?|r " or "") .. m.name)
  r.who:Refresh() r.act:Refresh() r.tmpl:Refresh() r.spot:Refresh()
  UIDropDownMenu_SetText(r.who, WhoLabel(cfg.who))
  local needs = (cfg.who == "PLAYERS" or cfg.who == "ROTATION")
  r.pick:SetShown(needs)
  r.pick:SetText("(" .. #cfg.players .. ")")
  r.bk:SetShown(needs or (cfg.who or ""):find("ROLE") ~= nil or cfg.who == "TANKS" or cfg.who == "HEALERS")
  r.bk:SetText("Bk" .. (#cfg.backup > 0 and ("(" .. #cfg.backup .. ")") or ""))
  r.prev:SetText(PreviewText(m))
end

local function RefreshAll()
  if not main then return end
  for _, r in ipairs(rows) do if r.m then RefreshRow(r) end end
  UpdateStatus()
end
RLP.RefreshUI = RefreshAll

local function BuildRow(i)
  local r = CreateFrame("Frame", nil, main.page)
  r:SetSize(800, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.check:SetSize(22, 22) r.check:SetPoint("LEFT", 0, 0)
  r.check:SetScript("OnClick", function(self)
    if InCombatBlock() then self:SetChecked(not self:GetChecked()) return end
    RLP.SetCfg(r.m, "on", self:GetChecked() and true or false)
    RefreshAll()
  end)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 26, 0) r.name:SetWidth(104) r.name:SetJustifyH("LEFT")
  r.who = Dropdown(r, 78, WhoItems, function() return r.m and RLP.Cfg(r.m).who end,
    function(v) RLP.SetCfg(r.m, "who", v) RefreshAll() end)
  r.who:SetPoint("LEFT", 118, -2)
  r.pick = Button(r, "(0)", 36, function() UI.Pick(r.m.name .. ": players", (function()
    local s = RLP.db.setups[r.m.id] or {} RLP.db.setups[r.m.id] = s s.players = s.players or {} return s.players end)(), RefreshAll) end)
  r.pick:SetPoint("LEFT", 262, 0)
  r.bk = Button(r, "Bk", 40, function() UI.Pick(r.m.name .. ": backups", (function()
    local s = RLP.db.setups[r.m.id] or {} RLP.db.setups[r.m.id] = s s.backup = s.backup or {} return s.backup end)(), RefreshAll) end)
  r.bk:SetPoint("LEFT", 302, 0)
  r.act = Dropdown(r, 76, ActionItems, function() return r.m and RLP.Cfg(r.m).act end,
    function(v) RLP.SetCfg(r.m, "act", v) RefreshAll() end)
  r.act:SetPoint("LEFT", 330, -2)
  r.tmpl = Dropdown(r, 100, TemplateItems, function() return r.m and RLP.Cfg(r.m).t end,
    function(v)
      RLP.SetCfg(r.m, "t", v)
      if v == "CUSTOM" and not RLP.Cfg(r.m).text then
        Prompt("Custom text for " .. r.m.name .. " (max 6 words)", function(txt)
          RLP.SetCfg(r.m, "text", txt) RefreshAll() end)
      end
      RefreshAll()
    end)
  r.tmpl:SetPoint("LEFT", 440, -2)
  r.spot = Dropdown(r, 68, SpotItems, function() return r.m and RLP.Cfg(r.m).spot end,
    function(v) RLP.SetCfg(r.m, "spot", v) RefreshAll() end)
  r.spot:SetPoint("LEFT", 566, -2)
  r.prev = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.prev:SetPoint("LEFT", 690, 0) r.prev:SetWidth(180) r.prev:SetJustifyH("LEFT")
  r.test = Button(r, "Test", 40, function() RLP.TestMech(r.m) end)
  r.test:SetPoint("LEFT", 872, 0)
  return r
end

function UI.ShowBoss(boss)
  selected = boss
  RLP.selectedBoss = boss
  if not main then return end
  main.bossName:SetText(boss.name .. "  |cff888888(" .. boss.raid .. ")|r")
  local mechs = RLP.Mechs(boss)
  for i = 1, math.max(#mechs, #rows) do
    if i <= #mechs then
      rows[i] = rows[i] or BuildRow(i)
      rows[i].m = mechs[i]
      rows[i]:Show()
      RefreshRow(rows[i])
    elseif rows[i] then
      rows[i].m = nil
      rows[i]:Hide()
    end
  end
  main.empty:SetShown(#mechs == 0)
  UpdateStatus()
end

---------------------------------------------------------------- tree
local expanded = {}

local function RebuildTree()
  local y = 0
  main.treeBtns = main.treeBtns or {}
  local idx = 0
  local function btn()
    idx = idx + 1
    local b = main.treeBtns[idx]
    if not b then
      b = CreateFrame("Button", nil, main.tree)
      b:SetSize(150, 18)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 2, 0)
      b:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
      main.treeBtns[idx] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:Show()
    y = y + 18
    return b
  end
  for _, raid in ipairs(RLP.Raids) do
    local h = btn()
    local n = 0
    for _, b in ipairs(raid.bosses) do if RLP.IsConfigured(b) then n = n + 1 end end
    h.text:SetText((expanded[raid.name] and "- " or "+ ") .. "|cffffd100" .. raid.name .. "|r " .. n .. "/" .. #raid.bosses)
    h:SetScript("OnClick", function() expanded[raid.name] = not expanded[raid.name] RebuildTree() end)
    if expanded[raid.name] then
      for _, boss in ipairs(raid.bosses) do
        local b = btn()
        b.text:SetText("   " .. (RLP.IsConfigured(boss) and "|cff40ff40*|r " or "") .. boss.name)
        b:SetScript("OnClick", function() UI.ShowBoss(boss) RebuildTree() end)
      end
    end
  end
  for i = idx + 1, #main.treeBtns do main.treeBtns[i]:Hide() end
  main.tree:SetHeight(math.max(y, 1))
end

---------------------------------------------------------------- roles / spots / settings windows
local rolesWin
local function ShowRoles()
  if not rolesWin then
    rolesWin = Panel("RLPRoles", 330, 60 + 28 * math.ceil(#RLP.ROLES / 2), "Roles")
    rolesWin.btns = {}
    for i, role in ipairs(RLP.ROLES) do
      local b = Button(rolesWin, role, 150, function()
        UI.Pick(role .. " players", RLP.db.roles[role], function() rolesWin:Refresh() end)
      end)
      b:SetPoint("TOPLEFT", 12 + ((i - 1) % 2) * 156, -40 - math.floor((i - 1) / 2) * 28)
      rolesWin.btns[role] = b
    end
    local fill = Button(rolesWin, "Auto-fill from raid", 150, function() RLP.AutoAssign() rolesWin:Refresh() end)
    fill:SetPoint("BOTTOMLEFT", 12, 10)
    function rolesWin:Refresh()
      for role, b in pairs(self.btns) do b:SetText(role .. " (" .. #RLP.db.roles[role] .. ")") end
      RefreshAll()
    end
  end
  rolesWin:Refresh()
  rolesWin:Show()
end

local spotsWin
local function ShowSpots()
  if not spotsWin then
    spotsWin = Panel("RLPSpots", 330, 360, "Spots")
    spotsWin.rows = {}
    local add = Button(spotsWin, "New spot", 100, function()
      Prompt("Name of the new spot", function(name)
        if name and name ~= "" then RLP.db.spots[name] = RLP.db.spots[name] or false spotsWin:Refresh() end
      end)
    end)
    add:SetPoint("BOTTOMLEFT", 12, 10)
    function spotsWin:Refresh()
      local names = {}
      for n in pairs(RLP.db.spots) do names[#names + 1] = n end
      table.sort(names)
      for i, n in ipairs(names) do
        local r = self.rows[i]
        if not r then
          r = CreateFrame("Frame", nil, self)
          r:SetSize(300, 26)
          r:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 26)
          r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          r.label:SetPoint("LEFT", 0, 0)
          r.dd = Dropdown(r, 70, function()
            local t = { { value = 0, label = "(none)" } }
            for k, ic in ipairs(RLP.ICONS) do t[#t + 1] = { value = k, label = ic } end
            return t
          end, function() return RLP.db.spots[r.spot] or 0 end,
            function(v) RLP.db.spots[r.spot] = v ~= 0 and v or false end)
          r.dd:SetPoint("LEFT", 90, -2)
          r.del = Button(r, "X", 24, function() RLP.db.spots[r.spot] = nil spotsWin:Refresh() end)
          r.del:SetPoint("LEFT", 250, 0)
          self.rows[i] = r
        end
        r.spot = n
        r.label:SetText(n)
        r:Show()
        r.dd:Refresh()
      end
      for i = #names + 1, #self.rows do self.rows[i]:Hide() end
    end
  end
  spotsWin:Refresh()
  spotsWin:Show()
end

local settingsWin
local function ShowSettings()
  if not settingsWin then
    settingsWin = Panel("RLPSettings", 340, 440, "Settings")
    local db = RLP.db
    local y = 36
    local function check(label, tbl, key)
      local c = CreateFrame("CheckButton", nil, settingsWin, "UICheckButtonTemplate")
      c:SetPoint("TOPLEFT", 10, -y)
      c:SetSize(24, 24)
      local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      t:SetPoint("LEFT", 28, 0) t:SetText(label)
      c:SetChecked(tbl[key])
      c:SetScript("OnClick", function(self) tbl[key] = self:GetChecked() and true or false end)
      y = y + 24
    end
    local function header(text)
      local t = settingsWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      t:SetPoint("TOPLEFT", 14, -y - 4) t:SetText(text)
      y = y + 24
    end
    header("Alerts")
    check("Engine enabled", db, "enabled")
    check("Mute all alerts", db, "mute")
    check("Raid summary for assigned mechanics", db, "summary")
    check("Alert when MT / OT / Interrupt dies", db, "deathAlert")
    check("Post top offenders after each fight", db, "autoPostReport")
    check("Auto-explain when targeting a boss", db, "autoExplain")
    check("Short explainer (3 lines)", db.explain, "short")
    header("Ready & Pull steps")
    check("Validate setup", db.pull, "validate")
    check("Buff / consumable check", db.pull, "check")
    check("Whisper players what they lack", db.pull, "whisperMissing")
    check("Post the explainer", db.pull, "explain")
    check("Whisper briefing", db.pull, "brief")
    check("Post loot rules", db.pull, "rules")
    check("Post spot legend", db.pull, "markers")
    local cnt = Button(settingsWin, "Countdown: " .. db.pull.count .. "s", 130, function(self)
      db.pull.count = db.pull.count == 10 and 15 or (db.pull.count == 15 and 5 or 10)
      self:SetText("Countdown: " .. db.pull.count .. "s")
    end)
    cnt:SetPoint("TOPLEFT", 14, -y - 4)
    local br = Button(settingsWin, "Briefing: " .. db.brief.mode, 150, function(self)
      local order = { ALL = "ASSIGNED", ASSIGNED = "UNACKED", UNACKED = "ALL" }
      db.brief.mode = order[db.brief.mode] or "ALL"
      self:SetText("Briefing: " .. db.brief.mode)
    end)
    br:SetPoint("LEFT", cnt, "RIGHT", 8, 0)
  end
  settingsWin:Show()
end

---------------------------------------------------------------- main window
local function BuildMain()
  main = Panel("RaidLeaderProFrame", 1090, 560, "Raid Leader Pro")
  main:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "RaidLeaderProFrame")

  main.tree = CreateFrame("Frame", nil, main)
  local sf = CreateFrame("ScrollFrame", "RLPTreeScroll", main, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -40) sf:SetSize(160, 440)
  main.tree:SetSize(150, 400)
  sf:SetScrollChild(main.tree)

  main.bossName = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  main.bossName:SetPoint("TOPLEFT", 200, -40)
  main.light = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  main.light:SetPoint("TOPLEFT", 200, -62)
  main.progress = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  main.progress:SetPoint("TOPRIGHT", -40, -14)

  local heads = { { "Mechanic", 226 }, { "Who", 330 }, { "Action", 540 }, { "Instruction", 650 }, { "Spot", 775 }, { "Message preview", 890 } }
  for _, h in ipairs(heads) do
    local t = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", h[2] - 20, -88)
    t:SetText(h[1])
  end

  main.page = CreateFrame("Frame", nil, main)
  main.page:SetPoint("TOPLEFT", 200, -104)
  main.page:SetSize(880, 330)
  rows = {}
  main.empty = main:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  main.empty:SetPoint("TOP", main.page, "TOP", 0, -40)
  main.empty:SetText("No configurable mechanics for this boss yet.\nUse /rlp learn then /rlp learned to add some.")
  main.empty:Hide()

  local y = 14
  local function bottom(text, w, fn, anchor)
    local b = Button(main, text, w, fn)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", 200, y) end
    return b
  end
  local b1 = bottom("Ready & Pull", 100, function() RLP.ReadyPull() end)
  local b2 = bottom("Explain", 70, function()
    local b = selected
    Menu({
      { text = "Explain: " .. (b and b.name or "?"), isTitle = true, notCheckable = true },
      { text = "Post to Raid (full)", notCheckable = true, func = function() RLP.Explain(b, { chan = "RAID" }) end },
      { text = "Post to Raid (short)", notCheckable = true, func = function() RLP.Explain(b, { chan = "RAID", short = true }) end },
      { text = "Post to Party", notCheckable = true, func = function() RLP.Explain(b, { chan = "PARTY" }) end },
      { text = "Preview to me", notCheckable = true, func = function() RLP.Explain(b, { chan = "ME" }) end },
    })
  end, b1)
  local b3 = bottom("Briefing", 70, function()
    Menu({
      { text = "Whisper briefing", isTitle = true, notCheckable = true },
      { text = "Send (mode: " .. RLP.db.brief.mode .. ")", notCheckable = true, func = function() RLP.Brief() end },
      { text = "Force re-send to everyone", notCheckable = true, func = function() RLP.Brief({ mode = "ALL", personal = RLP.db.brief.personal, force = true }) end },
      { text = "Who has acknowledged?", notCheckable = true, func = function() RLP.BriefStatus() end },
    })
  end, b2)
  local b4 = bottom("Check", 60, function() RLP.Check(false) end, b3)
  local b5 = bottom("Presets", 70, function()
    local entries = { { text = "Presets", isTitle = true, notCheckable = true },
      { text = "Save current as...", notCheckable = true, func = function() Prompt("Preset name", function(n) RLP.PresetSave(n) end) end } }
    local names = {}
    for n in pairs(RLP.db.presets) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      entries[#entries + 1] = { text = n, notCheckable = true, hasArrow = true, menuList = {
        { text = "Load", notCheckable = true, func = function() RLP.PresetLoad(n) RebuildTree() end },
        { text = "Export", notCheckable = true, func = function() TextBox("Export '" .. n .. "'", RLP.PresetExport(n)) end },
        { text = "Delete", notCheckable = true, func = function() RLP.PresetDelete(n) end },
      } }
    end
    entries[#entries + 1] = { text = "Export current", notCheckable = true, func = function() TextBox("Export current setup", RLP.PresetExport()) end }
    entries[#entries + 1] = { text = "Import string...", notCheckable = true, func = function()
      TextBox("Paste export string", "", function(str)
        Prompt("Name for imported preset", function(n) RLP.PresetImport(str, n ~= "" and n or "imported") RebuildTree() end)
      end)
    end }
    Menu(entries)
  end, b4)
  local b6 = bottom("Roles", 55, ShowRoles, b5)
  local b7 = bottom("Spots", 55, ShowSpots, b6)
  local b8 = bottom("Settings", 65, ShowSettings, b7)
  local b9 = bottom("HUD", 45, function() RLP.ToggleHUD() end, b8)
  local b10 = bottom("Auto-assign", 85, function() RLP.AutoAssign() RefreshAll() end, b9)
  local b11 = bottom("Reset boss", 80, function()
    if selected and not InCombatBlock() then RLP.ResetBoss(selected) UI.ShowBoss(selected) RebuildTree() end
  end, b10)
  local y2 = 40
  main.note = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  main.note:SetPoint("BOTTOMLEFT", 200, 42)
  main.note:SetText("|cffffd100?|r = spell/yell not verified in game (/rlp verify). Messages are max ~6 words. The addon warns, whispers and logs only.")

  RebuildTree()
  local first = RLP.Raids[1].bosses[1]
  UI.ShowBoss(first)
end

function RLP.ToggleUI()
  if not main then BuildMain() main:Show() return end
  main:SetShown(not main:IsShown())
  if main:IsShown() then RefreshAll() end
end

function RLP.SelectBoss(boss)
  if not main then BuildMain() end
  UI.ShowBoss(boss)
  main:Show()
end

function RLP.OnTarget()
  if main and main:IsShown() then
    local b = RLP.mobIndex[UnitName("target") or ""]
    if b and b ~= selected then UI.ShowBoss(b) end
  end
end

---------------------------------------------------------------- HUD
local hud
local function BuildHUD()
  hud = Panel("RLPHud", 250, 330, nil)
  hud:ClearAllPoints()
  hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
  hud:SetFrameStrata("MEDIUM")
  hud.head = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hud.head:SetPoint("TOPLEFT", 10, -8)
  hud.next = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hud.next:SetPoint("TOPLEFT", 10, -26)
  hud.log = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hud.log:SetPoint("TOPLEFT", 10, -44) hud.log:SetWidth(230) hud.log:SetJustifyH("LEFT") hud.log:SetJustifyV("TOP") hud.log:SetHeight(110)
  hud.mech = {}
  hud.mute = Button(hud, "Mute", 55, function() RLP.SetMute(not RLP.db.mute) end)
  hud.mute:SetPoint("BOTTOMLEFT", 8, 8)
  hud.skip = Button(hud, "Skip phase", 80, function() RLP.SkipPhase() end)
  hud.skip:SetPoint("LEFT", hud.mute, "RIGHT", 4, 0)
end

local function HudRefresh()
  if not hud or not hud:IsShown() then return end
  local boss = state.boss or RLP.CurrentBoss()
  hud.head:SetText((boss and boss.name or "No boss") .. (state.boss and ("  P" .. (state.phase or 1)) or "") .. (RLP.db.mute and "  |cffff4040MUTED|r" or ""))
  local name, left = RLP.NextTimer()
  hud.next:SetText(name and string.format("Next: %s in %ds", name, math.floor(math.max(0, left))) or "")
  local lines = {}
  for i = math.max(1, #state.log - 6), #state.log do
    local e = state.log[i]
    lines[#lines + 1] = string.format("%d:%02d %s", math.floor(e.t / 60), math.floor(e.t) % 60, e.text)
  end
  hud.log:SetText(table.concat(lines, "\n"))
  hud.mute:SetText(RLP.db.mute and "Unmute" or "Mute")
  if boss then
    local mechs = RLP.Mechs(boss)
    for i = 1, math.max(#mechs, #hud.mech) do
      local m = mechs[i]
      if m and i <= 8 then
        local b = hud.mech[i]
        if not b then
          b = Button(hud, "", 118, nil)
          b:SetPoint("TOPLEFT", 8 + ((i - 1) % 2) * 122, -160 - math.floor((i - 1) / 2) * 24)
          hud.mech[i] = b
        end
        b.m = m
        b:SetScript("OnClick", function() RLP.ManualFire(b.m) end)
        b:SetText(m.name:sub(1, 16))
        b:Show()
      elseif hud.mech[i] then
        hud.mech[i]:Hide()
      end
    end
  end
end

function RLP.ToggleHUD()
  if not hud then BuildHUD() end
  hud:SetShown(not hud:IsShown())
  HudRefresh()
end

RLP.OnLog = HudRefresh
RLP.OnTick = HudRefresh
RLP.OnFightStart = function()
  if not hud then BuildHUD() end
  hud:Show()
  HudRefresh()
end

---------------------------------------------------------------- minimap button
local function BuildMinimap()
  local b = CreateFrame("Button", "RLPMinimapButton", Minimap)
  b:SetSize(28, 28)
  b:SetFrameStrata("MEDIUM")
  local tex = b:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\Icons\\Ability_Warrior_RallyingCry")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local function place()
    local a = math.rad(RLP.db.minimapAngle or 210)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
  end
  place()
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      RLP.db.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then RLP.ToggleHUD()
    elseif IsShiftKeyDown() then RLP.ReadyPull()
    else RLP.ToggleUI() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Raid Leader Pro")
    GameTooltip:AddLine("Click: setup window", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: Ready & Pull", 1, 1, 1)
    GameTooltip:AddLine("Right-click: fight HUD", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

RLP.OnLoaded = function() BuildMinimap() end
