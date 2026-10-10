local ADDON, RLP = ...

local DEFAULTS = {
  raidChat = true,    -- post alerts flagged raid=true to raid chat (needs lead/assist for raid warning)
  whisper = true,     -- whisper affected players
  autoStrat = true,   -- post a boss's strategy once when you target it out of combat
  sound = true,
  rules = "Loot rules: not set yet. Leader: /rlp setrules <text>",
  offenders = {},     -- lifetime [playerName][spell] = hits, across all fights
}

local db
local state = { inCombat = false, boss = nil, dead = {}, start = 0, fails = {}, deaths = {}, lastHit = {}, cd = {}, announced = {}, pullToken = 0 }
RLP.state = state

local mobIndex, nameIndex = {}, {}
for _, raid in ipairs(RLP.Raids) do
  for _, boss in ipairs(raid.bosses) do
    boss.raid = raid.name
    for _, m in ipairs(boss.mobs) do mobIndex[m] = boss end
    nameIndex[boss.name:lower()] = boss
  end
end

---------------------------------------------------------------- output
local function Print(...) print("|cffff8000RLP:|r", ...) end
RLP.Print = Print

local function Chan(warn)
  if IsInRaid() then
    if warn and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return "RAID_WARNING" end
    return "RAID"
  elseif IsInGroup() then
    return "PARTY"
  end
end

local function Say(msg, warn)
  local ch = Chan(warn)
  if not ch then Print(msg) return end
  while #msg > 250 do
    local cut = msg:sub(1, 250):match("^(.*) ") or msg:sub(1, 250)
    SendChatMessage(cut, ch)
    msg = msg:sub(#cut + 1):gsub("^%s+", "")
  end
  SendChatMessage(msg, ch)
end
RLP.Say = Say

local function Warn(msg)
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  else
    Print(msg)
  end
  if db.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function InRaidInstance()
  local inInstance, kind = IsInInstance()
  return inInstance and kind == "raid"
end

local function CanLead()
  return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

---------------------------------------------------------------- fight tracking
local function StartFight(boss)
  state.boss = boss
  state.start = GetTime()
  state.dead, state.fails, state.deaths, state.lastHit, state.cd = {}, {}, {}, {}, {}
  Print("Engaged " .. boss.name)
end

local function BuildReport()
  local lines, b = {}, state.lastFight
  if not b then return { "No fight recorded yet." } end
  lines[#lines + 1] = string.format("%s: %s in %d:%02d", b.name, b.killed and "KILL" or "WIPE/RESET", b.duration / 60, b.duration % 60)
  local rows = {}
  for player, spells in pairs(b.fails) do
    for spell, n in pairs(spells) do rows[#rows + 1] = { player, spell, n } end
  end
  table.sort(rows, function(x, y) return x[3] > y[3] end)
  for i = 1, math.min(#rows, 8) do
    lines[#lines + 1] = string.format("Avoidable: %s hit by %s x%d", rows[i][1], rows[i][2], rows[i][3])
  end
  for i = 1, math.min(#b.deaths, 8) do
    local d = b.deaths[i]
    lines[#lines + 1] = string.format("Died (%d:%02d): %s - %s", d.t / 60, d.t % 60, d.name, d.by or "unknown")
  end
  if #rows == 0 and #b.deaths == 0 then lines[#lines + 1] = "No avoidable damage or deaths recorded." end
  return lines
end
RLP.BuildReport = BuildReport

local function EndFight(killed)
  local b = state.boss
  if not b then return end
  state.lastFight = { name = b.name, killed = killed, duration = GetTime() - state.start, fails = state.fails, deaths = state.deaths }
  for player, spells in pairs(state.fails) do
    db.offenders[player] = db.offenders[player] or {}
    for spell, n in pairs(spells) do db.offenders[player][spell] = (db.offenders[player][spell] or 0) + n end
  end
  state.boss = nil
  for _, line in ipairs(BuildReport()) do Print(line) end
end

---------------------------------------------------------------- combat log
local function IsGroupPlayer(flags)
  return flags and bit.band(flags, 0x400) ~= 0 and bit.band(flags, 0x7) ~= 0
end

local function Trigger(a, dName, dFlags)
  local who = dName and dName:gsub("%-.*$", "") or "?"
  if a.player and not IsGroupPlayer(dFlags) then return end
  local key = a.spell .. (a.player and who or "")
  local now = GetTime()
  if state.cd[key] and now - state.cd[key] < 4 then return end
  state.cd[key] = now
  local text = a.msg:gsub("%%s", who)
  Warn(text)
  if a.raid and db.raidChat and CanLead() then Say(text, true) end
  if a.whisper and a.player and db.whisper and who ~= UnitName("player") then
    SendChatMessage(a.whisper, "WHISPER", nil, dName)
  elseif a.whisper and a.player and who == UnitName("player") then
    Warn(a.whisper)
  end
end

local function OnCombatLog()
  local _, ev, _, _, sName, _, _, dGUID, dName, dFlags, _, a12, a13, _, a15 = CombatLogGetCurrentEventInfo()

  if not state.boss then
    if state.inCombat and InRaidInstance() then
      local b = mobIndex[sName] or mobIndex[dName]
      if b then StartFight(b) end
    end
    return
  end
  local boss = state.boss

  if ev == "UNIT_DIED" then
    if mobIndex[dName] == boss then
      state.dead[dName] = true
      local done
      if boss.final then done = state.dead[boss.final]
      else
        done = true
        for _, m in ipairs(boss.mobs) do if not state.dead[m] then done = false end end
      end
      if done then EndFight(true) end
    elseif IsGroupPlayer(dFlags) and UnitIsPlayer and dGUID and dGUID:find("^Player") then
      local who = dName:gsub("%-.*$", "")
      table.insert(state.deaths, { name = who, by = state.lastHit[who], t = GetTime() - state.start })
    end
    return
  end

  local isDamage = ev == "SPELL_DAMAGE" or ev == "SPELL_PERIODIC_DAMAGE" or ev == "RANGE_DAMAGE"
  if (isDamage or ev == "SWING_DAMAGE") and IsGroupPlayer(dFlags) then
    local who = dName:gsub("%-.*$", "")
    local spell = isDamage and a13 or "melee"
    state.lastHit[who] = string.format("%s (%d)", spell, (isDamage and a15 or a12) or 0)
    if isDamage and boss.avoid then
      for _, s in ipairs(boss.avoid) do
        if s == a13 then
          state.fails[who] = state.fails[who] or {}
          state.fails[who][s] = (state.fails[who][s] or 0) + 1
        end
      end
    end
    return
  end

  if boss.alerts and (ev == "SPELL_CAST_START" or ev == "SPELL_CAST_SUCCESS" or ev == "SPELL_AURA_APPLIED") then
    for _, a in ipairs(boss.alerts) do
      if a.ev == ev and a.spell == a13 then Trigger(a, dName, dFlags) end
    end
  end
end

---------------------------------------------------------------- strategy
local function FindBoss(arg)
  if arg and arg ~= "" then
    local l = arg:lower()
    if nameIndex[l] then return nameIndex[l] end
    for k, b in pairs(nameIndex) do if k:find(l, 1, true) then return b end end
    return nil
  end
  return state.boss or mobIndex[UnitName("target") or ""]
end

function RLP.Strat(arg)
  local b = FindBoss(arg)
  if not b then Print("No boss found. Target one or use /rlp strat <boss name>.") return end
  Say("== " .. b.name .. " ==")
  for _, t in ipairs(b.tips) do Say(t) end
  state.announced[b.name] = true
end

function RLP.Rules() Say(db.rules) end

---------------------------------------------------------------- consumable / buff check
local function Units()
  local t = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do t[#t + 1] = "raid" .. i end
  else
    t[1] = "player"
    for i = 1, GetNumSubgroupMembers() do t[#t + 1] = "party" .. i end
  end
  return t
end

local function Join(list) return #list > 0 and table.concat(list, ", ") or nil end

function RLP.Check(post)
  local missing = { flask = {}, food = {}, fort = {}, mark = {}, int = {}, offline = {}, dead = {} }
  local have = { PRIEST = false, DRUID = false, MAGE = false }
  local units = Units()
  for _, u in ipairs(units) do
    local _, class = UnitClass(u)
    if have[class] ~= nil then have[class] = true end
  end
  for _, u in ipairs(units) do
    local name = UnitName(u)
    if name then
      if not UnitIsConnected(u) then
        table.insert(missing.offline, name)
      elseif UnitIsDeadOrGhost(u) then
        table.insert(missing.dead, name)
      else
        local flask, elixirs, food, fort, mark, int = false, 0, false, false, false, false
        for i = 1, 40 do
          local n = UnitBuff(u, i)
          if not n then break end
          if n:find("Flask") then flask = true
          elseif n:find("Elixir") or n:find("Juju") or n:find("Zanza") then elixirs = elixirs + 1 end
          if n:find("Well Fed") then food = true end
          if n:find("Fortitude") then fort = true end
          if n:find("of the Wild") then mark = true end
          if n:find("Arcane Intellect") or n:find("Arcane Brilliance") then int = true end
        end
        if not flask and elixirs < 2 then table.insert(missing.flask, name) end
        if not food then table.insert(missing.food, name) end
        if have.PRIEST and not fort then table.insert(missing.fort, name) end
        if have.DRUID and not mark then table.insert(missing.mark, name) end
        if have.MAGE and UnitPowerType(u) == 0 and not int then table.insert(missing.int, name) end
      end
    end
  end
  local out = {}
  local function add(label, list) local j = Join(list) if j then out[#out + 1] = label .. ": " .. j end end
  add("Offline", missing.offline)
  add("Dead", missing.dead)
  add("No flask/2 elixirs", missing.flask)
  add("No food", missing.food)
  add("No Fortitude", missing.fort)
  add("No Mark of the Wild", missing.mark)
  add("No Arcane Intellect", missing.int)
  if #out == 0 then out[1] = "Everyone is buffed and alive." end
  for _, line in ipairs(out) do
    if post then Say(line) else Print(line) end
  end
  return #out == 1 and out[1] == "Everyone is buffed and alive."
end

---------------------------------------------------------------- pull timer
function RLP.CancelPull()
  state.pullToken = state.pullToken + 1
end

function RLP.Pull(sec)
  sec = tonumber(sec) or 10
  state.pullToken = state.pullToken + 1
  local token = state.pullToken
  RLP.Check(false)
  local function tick(n)
    if token ~= state.pullToken then return end
    if n <= 0 then
      Say("PULL NOW!", true)
      return
    end
    if n == sec or n == 10 or n <= 5 then Say("Pull in " .. n, n == sec) end
    C_Timer.After(1, function() tick(n - 1) end)
  end
  tick(sec)
end

---------------------------------------------------------------- shame / report
function RLP.PostReport()
  for _, line in ipairs(BuildReport()) do Say(line) end
end

function RLP.Offenders()
  local rows = {}
  for player, spells in pairs(db.offenders) do
    local total = 0
    for _, n in pairs(spells) do total = total + n end
    rows[#rows + 1] = { player, total }
  end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  if #rows == 0 then Print("No avoidable damage recorded yet.") return end
  for i = 1, math.min(#rows, 10) do Print(string.format("%d. %s - %d avoidable hits", i, rows[i][1], rows[i][2])) end
end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    OnCombatLog()
  elseif event == "ADDON_LOADED" and arg1 == ADDON then
    RLP_DB = RLP_DB or {}
    db = RLP_DB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    RLP.db = db
    Print("loaded. /rlp for commands.")
  elseif event == "PLAYER_REGEN_DISABLED" then
    state.inCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    state.inCombat = false
    -- boss still alive a few seconds after we left combat = wipe or reset
    C_Timer.After(5, function()
      if state.boss and not state.inCombat then EndFight(false) end
    end)
  elseif event == "PLAYER_TARGET_CHANGED" then
    if db and db.autoStrat and InRaidInstance() and IsInRaid() and CanLead() and not state.inCombat then
      local b = mobIndex[UnitName("target") or ""]
      if b and not state.announced[b.name] then RLP.Strat(b.name) end
    end
  end
end)

---------------------------------------------------------------- slash
local HELP = {
  "/rlp ui - show the control panel",
  "/rlp check [say] - flask/food/buff/dead/offline check (say = post to raid)",
  "/rlp pull [sec] - run the check, then countdown and PULL (default 10)",
  "/rlp cancel - cancel a pull timer",
  "/rlp strat [boss] - post the boss strategy (default: target)",
  "/rlp rules - post loot rules; /rlp setrules <text> to change them",
  "/rlp report [say] - last fight: avoidable damage and deaths",
  "/rlp offenders - lifetime avoidable-damage leaderboard; /rlp reset to clear",
  "/rlp toggle raidChat|whisper|autoStrat|sound",
}

SLASH_RAIDLEADERPRO1 = "/rlp"
SLASH_RAIDLEADERPRO2 = "/raidleader"
SlashCmdList["RAIDLEADERPRO"] = function(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "check" then RLP.Check(rest == "say")
  elseif cmd == "pull" then RLP.Pull(rest)
  elseif cmd == "cancel" then RLP.CancelPull() Print("Pull cancelled.")
  elseif cmd == "strat" then RLP.Strat(rest)
  elseif cmd == "rules" then RLP.Rules()
  elseif cmd == "setrules" then if rest ~= "" then db.rules = rest Print("Rules saved.") end
  elseif cmd == "report" then
    if rest == "say" then RLP.PostReport() else for _, l in ipairs(BuildReport()) do Print(l) end end
  elseif cmd == "offenders" then RLP.Offenders()
  elseif cmd == "reset" then db.offenders = {} state.announced = {} Print("Cleared leaderboard and strat memory.")
  elseif cmd == "toggle" then
    if DEFAULTS[rest] ~= nil and type(DEFAULTS[rest]) == "boolean" then
      db[rest] = not db[rest]
      Print(rest .. " = " .. tostring(db[rest]))
    else
      Print("Options: raidChat, whisper, autoStrat, sound")
    end
  elseif cmd == "ui" then RLP.ToggleUI()
  else for _, l in ipairs(HELP) do Print(l) end end
end
