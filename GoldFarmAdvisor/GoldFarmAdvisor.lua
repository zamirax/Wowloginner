-- Gold Farm Advisor: Classic-style tradeskill API (Classic Era / Anniversary / Cata / MoP Classic).
local ADDON = "GoldFarmAdvisor"
local AH_CUT = 0.05      -- auction house cut
local IDLE_GAP = 90      -- seconds without loot before a farming run is considered over
local RUN_START = 30     -- seconds credited for the first kill of a run
local MIN_SECONDS = 120  -- ignore zones with less farming time than this

local db, me
local lastLoot, lastZone

local function Print(...) print("|cffffd100GFA:|r", ...) end

local function ItemID(link)
  return link and tonumber(link:match("item:(%d+)"))
end

local function Gold(copper)
  return string.format("%.1fg", (copper or 0) / 10000)
end

local function Name(id)
  return (GetItemInfo(id)) or ("item:" .. id)
end

---------------------------------------------------------------- prices
local function AHPrice(id)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if A and A.GetAuctionPriceByItemID then
    local ok, p = pcall(A.GetAuctionPriceByItemID, ADDON, id)
    if ok and p and p > 0 then return p end
  end
end

-- Value of a looted item: net AH price, else vendor price.
local function LootValue(id)
  local p = AHPrice(id)
  if p then return p * (1 - AH_CUT), true end
  local sell = select(11, GetItemInfo(id))
  if sell and sell > 0 then return sell, false end
  return 0, false
end

---------------------------------------------------------------- saved data
local function Init()
  GFA_DB = GFA_DB or {}
  db = GFA_DB
  db.recipes = db.recipes or {}   -- [char][profession] = list
  db.trainer = db.trainer or {}   -- [char] = list
  db.zones = db.zones or {}       -- [zone] = {seconds=, items={[id]=count}}
  local key = UnitName("player") .. "-" .. GetRealmName()
  db.recipes[key] = db.recipes[key] or {}
  db.trainer[key] = db.trainer[key] or {}
  me = { recipes = db.recipes[key], key = key }
end

---------------------------------------------------------------- known recipes
local function ScanTradeSkill()
  if not me or not GetNumTradeSkills then return end
  local prof = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end
  local list = {}
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    local id = name and kind ~= "header" and ItemID(GetTradeSkillItemLink(i))
    if id then
      local minMade, maxMade = GetTradeSkillNumMade(i)
      local reagents, ok = {}, true
      for r = 1, GetTradeSkillNumReagents(i) do
        local _, _, count = GetTradeSkillReagentInfo(i, r)
        local rid = ItemID(GetTradeSkillReagentItemLink(i, r))
        if not rid then ok = false break end
        reagents[#reagents + 1] = { rid, count }
      end
      if ok then
        list[#list + 1] = { name = name, id = id, kind = kind,
          made = ((minMade or 1) + (maxMade or 1)) / 2, reagents = reagents }
      end
    end
  end
  if #list > 0 then me.recipes[prof] = list end
end

local function CraftRows()
  local rows = {}
  for prof, list in pairs(me.recipes) do
    for _, r in ipairs(list) do
      local sale = AHPrice(r.id)
      local cost, missing = 0, false
      for _, re in ipairs(r.reagents) do
        local p = AHPrice(re[1])
        if not p then missing = true break end
        cost = cost + p * re[2]
      end
      if sale and not missing then
        local revenue = sale * r.made * (1 - AH_CUT)
        rows[#rows + 1] = { prof = prof, r = r, profit = revenue - cost, cost = cost, sale = sale }
      end
    end
  end
  table.sort(rows, function(a, b) return a.profit > b.profit end)
  return rows
end

---------------------------------------------------------------- farming tracker
local function ToPattern(s)
  s = s:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  s = s:gsub("%%s", "(.+)")
  s = s:gsub("%%d", "(%%d+)")
  return "^" .. s .. "$"
end

local PAT_MULTI = LOOT_ITEM_SELF_MULTIPLE and ToPattern(LOOT_ITEM_SELF_MULTIPLE)
local PAT_ONE = LOOT_ITEM_SELF and ToPattern(LOOT_ITEM_SELF)

local function OnLoot(msg)
  if not db then return end
  local link, count = msg:match(PAT_MULTI or "^$")
  if not link then
    link = msg:match(PAT_ONE or "^$")
    count = 1
  end
  local id = ItemID(link)
  if not id then return end
  local zone = GetRealZoneText()
  if not zone or zone == "" then return end
  local z = db.zones[zone] or { seconds = 0, items = {} }
  db.zones[zone] = z
  local now = GetTime()
  if lastLoot and lastZone == zone and now - lastLoot <= IDLE_GAP then
    z.seconds = z.seconds + (now - lastLoot)
  else
    z.seconds = z.seconds + RUN_START
  end
  lastLoot, lastZone = now, zone
  z.items[id] = (z.items[id] or 0) + tonumber(count)
end

local function FarmReport()
  local zones, items = {}, {}
  local used = {}
  for _, list in pairs(me.recipes) do
    for _, r in ipairs(list) do
      for _, re in ipairs(r.reagents) do used[re[1]] = true end
    end
  end
  for zone, z in pairs(db.zones) do
    if z.seconds >= MIN_SECONDS then
      local total, n = 0, 0
      for id, c in pairs(z.items) do
        local v = LootValue(id)
        total = total + v * c
        n = n + c
        items[#items + 1] = { id = id, zone = zone, count = c, secs = z.seconds,
          gold10 = v * c / z.seconds * 600, minEach = z.seconds / c / 60, used = used[id] }
      end
      zones[#zones + 1] = { zone = zone, gold10 = total / z.seconds * 600,
        hour = total / z.seconds * 3600, mins = z.seconds / 60 }
    end
  end
  table.sort(zones, function(a, b) return a.gold10 > b.gold10 end)
  table.sort(items, function(a, b) return a.gold10 > b.gold10 end)
  return zones, items
end

---------------------------------------------------------------- trainer recipes
local scanTip

local function TrainerReagents(i)
  scanTip = scanTip or CreateFrame("GameTooltip", "GFAScanTip", nil, "GameTooltipTemplate")
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetTrainerService(i)
  for n = 1, scanTip:NumLines() do
    local fs = _G["GFAScanTipTextLeft" .. n]
    local text = fs and fs:GetText()
    local rest = text and SPELL_REAGENTS and text:match("^" .. SPELL_REAGENTS .. "%s*(.+)$")
    if rest then
      local reagents, complete = {}, true
      for raw in rest:gmatch("[^,]+") do
        local part = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local nm, c = part:match("^(.-)%s*%((%d+)%)$")
        nm, c = nm or part, tonumber(c) or 1
        local _, link = GetItemInfo(nm)
        local id = ItemID(link)
        if id then reagents[#reagents + 1] = { id, c } else complete = false end
      end
      return reagents, complete
    end
  end
  return {}, true
end

local function ScanTrainer()
  if not me or not GetNumTrainerServices or not GetTrainerServiceItemLink then return end
  local list = {}
  for i = 1, GetNumTrainerServices() do
    local name, _, category = GetTrainerServiceInfo(i)
    local id = category == "available" and ItemID(GetTrainerServiceItemLink(i))
    if id then
      local reagents, complete = TrainerReagents(i)
      list[#list + 1] = { name = name, id = id, cost = GetTrainerServiceCost(i) or 0,
        reagents = reagents, complete = complete }
    end
  end
  db.trainer[me.key] = list
end

local function TrainerRows()
  local rows = {}
  for _, t in ipairs(db.trainer[me.key] or {}) do
    local sale = AHPrice(t.id)
    if sale then
      local cost, missing = 0, false
      for _, re in ipairs(t.reagents) do
        local p = AHPrice(re[1])
        if not p then missing = true break end
        cost = cost + p * re[2]
      end
      local known = t.complete and not missing
      local profit = sale * (1 - AH_CUT) - (known and cost or 0)
      rows[#rows + 1] = { t = t, profit = profit, known = known, sale = sale }
    end
  end
  table.sort(rows, function(a, b)
    if a.known ~= b.known then return a.known end
    return a.profit > b.profit
  end)
  return rows
end

---------------------------------------------------------------- report text
local function Report(tab)
  if not Auctionator or not Auctionator.API then
    return "|cffff4040Auctionator not found.|r Install/enable it and scan the auction house."
  end
  local out = {}
  local function add(...) out[#out + 1] = string.format(...) end

  if tab == "craft" then
    local rows = CraftRows()
    if #rows == 0 then
      return "No data yet. Open each of your profession windows once, and do an Auctionator scan at the auction house."
    end
    add("|cffffd100Best crafts you know (profit per craft, after AH cut)|r\n")
    for i = 1, math.min(25, #rows) do
      local x = rows[i]
      add("%d. %s [%s]  profit |cff40ff40%s|r  (cost %s)", i, Name(x.r.id), x.prof, Gold(x.profit), Gold(x.cost))
    end
  elseif tab == "farm" then
    local zones, items = FarmReport()
    if #zones == 0 then
      return "No farming data yet. Just go loot things: this tracks your loot automatically.\nNeeds at least 2 minutes of farming in a zone."
    end
    add("|cffffd100Zones by gold per 10 minutes (from your own looting)|r\n")
    for i = 1, math.min(8, #zones) do
      local z = zones[i]
      add("%d. %s: |cff40ff40%s|r per 10 min  (%s/hour, %.0f min tracked)", i, z.zone, Gold(z.gold10), Gold(z.hour), z.mins)
    end
    add("\n|cffffd100Best items to farm|r  (* = used in your recipes)\n")
    for i = 1, math.min(20, #items) do
      local x = items[i]
      add("%s%s - %s: 1 every %.1f min, %s per 10 min", x.used and "* " or "", Name(x.id), x.zone, x.minEach, Gold(x.gold10))
    end
  else
    local rows = TrainerRows()
    if #rows == 0 then
      return "No data yet. Visit your profession trainer (with Auctionator scanned) and reopen this tab."
    end
    add("|cffffd100Learnable now at your trainer, best money-makers first|r\n")
    for i = 1, math.min(25, #rows) do
      local x = rows[i]
      local payoff = ""
      if x.profit > 0 and x.t.cost > 0 then
        payoff = string.format(", pays off after %d crafts", math.ceil(x.t.cost / x.profit))
      end
      if x.known then
        add("%d. %s: profit |cff40ff40%s|r each, trains for %s%s", i, x.t.name, Gold(x.profit), Gold(x.t.cost), payoff)
      else
        add("%d. %s: sells %s (|cffff9040reagents unknown|r), trains for %s", i, x.t.name, Gold(x.sale), Gold(x.t.cost))
      end
    end
  end
  return table.concat(out, "\n")
end

---------------------------------------------------------------- window
local frame, currentTab
local function Refresh()
  if frame and frame:IsShown() and me then frame.text:SetText(Report(currentTab)) end
end

local function BuildFrame()
  frame = CreateFrame("Frame", "GFAFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 440)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  tinsert(UISpecialFrames, "GFAFrame")
  frame.TitleText:SetText("Gold Farm Advisor")

  local tabs = { { "craft", "My recipes" }, { "farm", "What to farm" }, { "learn", "Recipes to learn" } }
  for i, t in ipairs(tabs) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(130, 22)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 135, -30)
    b:SetText(t[2])
    b:SetScript("OnClick", function() currentTab = t[1]; Refresh() end)
  end

  local scroll = CreateFrame("ScrollFrame", "GFAScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -60)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local text = CreateFrame("Frame", nil, scroll)
  text:SetSize(500, 10)
  scroll:SetScrollChild(text)
  local fs = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOPLEFT")
  fs:SetWidth(500)
  fs:SetJustifyH("LEFT")
  frame.text = fs
  hooksecurefunc(fs, "SetText", function() text:SetHeight(fs:GetStringHeight() + 10) end)
end

local function Toggle()
  if not frame then BuildFrame() end
  if frame:IsShown() then frame:Hide() else frame:Show(); Refresh() end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRAINER_SHOW", "CHAT_MSG_LOOT" }) do
  ev:RegisterEvent(e)
end
currentTab = "craft"

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    Init()
    Print("loaded. Type /gfa to open.")
  elseif not db then
    return
  elseif event == "CHAT_MSG_LOOT" then
    OnLoot(arg1)
  elseif event == "TRAINER_SHOW" then
    ScanTrainer()
  else
    ScanTradeSkill()
  end
end)

SLASH_GFA1 = "/gfa"
SlashCmdList.GFA = function(msg)
  if msg == "reset" then
    db.zones = {}
    Print("farming data cleared.")
  else
    Toggle()
  end
end
