local ADDON, RLP = ...
local Print = RLP.Print

BINDING_HEADER_RAIDLEADERPRO = "Raid Leader Pro"
BINDING_NAME_RLP_READYPULL = "Ready & Pull"
BINDING_NAME_RLP_MUTE = "Mute / unmute alerts"
BINDING_NAME_RLP_EXPLAIN = "Explain current boss"

local HELP = {
  "/rlp - setup window       /rlp hud - fight HUD",
  "/rlp pull [sec] - Ready & Pull (validation, checks, posts, countdown)",
  "/rlp check [say] - buffs, food, dead, offline",
  "/rlp explain [boss] [short|party|me] - post the boss explainer",
  "/rlp brief [force|status] - whisper briefing",
  "/rlp rules | setrules <text> - loot rules",
  "/rlp report [full|say] - last fight; /rlp offenders [boss]",
  "/rlp test <mechanic> - preview a mechanic on yourself",
  "/rlp mute - toggle alerts; /rlp cancel - cancel a pull",
  "/rlp preset save|load|delete <name>; /rlp swap <Old> <New>",
  "/rlp verify | learn | learned | map <n> <TEMPLATE> [who] | validate",
}

local function FindMech(arg)
  local boss = RLP.CurrentBoss()
  local l = arg:lower()
  for _, b in ipairs(boss and { boss } or RLP.AllBosses()) do
    for _, m in ipairs(RLP.Mechs(b)) do
      if m.name:lower():find(l, 1, true) then return m end
    end
  end
end

SLASH_RAIDLEADERPRO1 = "/rlp"
SLASH_RAIDLEADERPRO2 = "/raidleader"
SlashCmdList["RAIDLEADERPRO"] = function(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local db = RLP.db
  if cmd == "" or cmd == "ui" then RLP.ToggleUI()
  elseif cmd == "hud" then RLP.ToggleHUD()
  elseif cmd == "pull" then
    if rest ~= "" then RLP.Pull(rest) else RLP.ReadyPull() end
  elseif cmd == "cancel" then RLP.CancelPull() Print("Pull cancelled.")
  elseif cmd == "check" then RLP.Check(rest == "say", rest == "whisper")
  elseif cmd == "explain" or cmd == "strat" then
    local opts, name = { chan = "RAID" }, {}
    for w in rest:gmatch("%S+") do
      local l = w:lower()
      if l == "short" then opts.short = true elseif l == "party" then opts.chan = "PARTY" elseif l == "me" then opts.chan = "ME"
      else name[#name + 1] = w end
    end
    local b = #name > 0 and RLP.FindBoss(table.concat(name, " ")) or RLP.CurrentBoss()
    RLP.Explain(b, opts)
  elseif cmd == "brief" then
    if rest == "status" then RLP.BriefStatus()
    else
      local o = RLP.DeepCopy(db.brief)
      if rest == "force" then o.force = true end
      RLP.Brief(o)
    end
  elseif cmd == "rules" then RLP.Rules()
  elseif cmd == "setrules" then if rest ~= "" then db.rules = rest Print("Rules saved.") end
  elseif cmd == "report" then
    if rest == "say" then RLP.PostReport(false)
    else for _, l in ipairs(RLP.BuildReport(true)) do Print(l) end end
  elseif cmd == "offenders" then RLP.Offenders(rest)
  elseif cmd == "reset" then db.offenders, db.bossOff = {}, {} RLP.state.announced = {} Print("Cleared leaderboards and explainer memory.")
  elseif cmd == "test" then
    local m = FindMech(rest)
    if m then RLP.TestMech(m) else Print("No mechanic matching '" .. rest .. "'. Select the boss in /rlp first.") end
  elseif cmd == "mute" then RLP.SetMute(not db.mute)
  elseif cmd == "preset" then
    local sub, name = rest:match("^(%S+)%s*(.*)$")
    if sub == "save" then RLP.PresetSave(name)
    elseif sub == "load" then RLP.PresetLoad(name)
    elseif sub == "delete" then RLP.PresetDelete(name) Print("Deleted.")
    else
      local names = {}
      for n in pairs(db.presets) do names[#names + 1] = n end
      table.sort(names)
      Print("Presets: " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
    end
  elseif cmd == "swap" then
    local a, b = rest:match("^(%S+)%s+(%S+)$")
    if a then RLP.SwapPlayer(a, b) else Print("Usage: /rlp swap OldName NewName") end
  elseif cmd == "verify" then RLP.Verify()
  elseif cmd == "learn" then RLP.LearnToggle()
  elseif cmd == "learned" then RLP.Learned(rest)
  elseif cmd == "map" then
    local i, t, w = rest:match("^(%d+)%s+(%S+)%s*(.-)$")
    if i then RLP.Map(i, t, w) else Print("Usage: /rlp map <number> <TEMPLATE> [who]") end
  elseif cmd == "validate" then
    if #RLP.problems == 0 then Print("Data OK.") end
    for _, p in ipairs(RLP.problems) do Print("|cffff4040" .. p .. "|r") end
    local b = RLP.CurrentBoss()
    if b then RLP.ValidateReport(b) end
  else
    for _, l in ipairs(HELP) do Print(l) end
  end
end
