local ADDON, RLP = ...
local state = RLP.state
local Short = RLP.Short
local Print = RLP.Print

---------------------------------------------------------------- current boss
function RLP.CurrentBoss()
  return state.boss or RLP.selectedBoss or RLP.mobIndex[UnitName("target") or ""]
end

---------------------------------------------------------------- consumable / buff check
local function Units()
  return RLP.Roster(true)
end

function RLP.Check(post, whisper)
  local have = { PRIEST = false, DRUID = false, MAGE = false }
  local roster = Units()
  for _, e in ipairs(roster) do if have[e.class] ~= nil then have[e.class] = true end end
  local cats = { flask = {}, food = {}, fort = {}, mark = {}, int = {}, offline = {}, dead = {} }
  local lacks = {}
  local function lack(name, cat, text) table.insert(cats[cat], name) lacks[name] = lacks[name] or {} table.insert(lacks[name], text) end
  for _, e in ipairs(roster) do
    local u, name = e.unit, e.name
    if not UnitIsConnected(u) then table.insert(cats.offline, name)
    elseif UnitIsDeadOrGhost(u) then table.insert(cats.dead, name)
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
      if not flask and elixirs < 2 then lack(name, "flask", "flask/elixirs") end
      if not food then lack(name, "food", "food") end
      if have.PRIEST and not fort then lack(name, "fort", "Fortitude") end
      if have.DRUID and not mark then lack(name, "mark", "Mark of the Wild") end
      if have.MAGE and UnitPowerType(u) == 0 and not int then lack(name, "int", "Arcane Intellect") end
    end
  end
  local out = {}
  local function add(label, list) if #list > 0 then out[#out + 1] = label .. ": " .. table.concat(list, ", ") end end
  add("Offline", cats.offline) add("Dead", cats.dead) add("No flask/2 elixirs", cats.flask) add("No food", cats.food)
  add("No Fortitude", cats.fort) add("No Mark of the Wild", cats.mark) add("No Arcane Intellect", cats.int)
  local ok = #out == 0
  if ok then out[1] = "Everyone is buffed and alive." end
  for _, line in ipairs(out) do
    if post then RLP.Enqueue("RAID", line, nil, 3) else Print(line) end
  end
  if whisper then
    for name, list in pairs(lacks) do
      if name ~= UnitName("player") then RLP.Enqueue("WHISPER", "RLP: missing " .. table.concat(list, ", "), name, 3) end
    end
  end
  return ok
end

---------------------------------------------------------------- setup validation
function RLP.Validate(boss)
  local problems = {}
  if not boss then return { "No boss selected." } end
  local mechs = RLP.Mechs(boss)
  local sig = {}
  for _, m in ipairs(mechs) do
    local cfg = RLP.Cfg(m)
    if cfg.on then
      local who = cfg.who or ""
      if not who:find("^AFFECTED") and not who:find("^EVERYONE") then
        local r = RLP.Resolve(who, m, cfg, nil, true)
        if r ~= "ALL" then
          if #r == 0 then
            problems[#problems + 1] = m.name .. ": nobody assigned"
          end
          for _, n in ipairs(cfg.players) do
            if not RLP.Entry(n) then problems[#problems + 1] = n .. " is not in the raid (" .. m.name .. ")"
            elseif not RLP.Alive(n) then problems[#problems + 1] = n .. " dead/offline (" .. m.name .. ")" end
          end
          if who:find("ROLE:MT") and #r == 0 then problems[#problems + 1] = "No MT set for " .. m.name end
          local key = (m.ev or m.kind) .. "|" .. tostring(m.spell or m.pat or m.hp or m.sec)
          sig[key] = sig[key] or {}
          for _, n in ipairs(r) do
            if sig[key][n] and sig[key][n] ~= m.name then
              problems[#problems + 1] = n .. " assigned to both " .. sig[key][n] .. " and " .. m.name
            end
            sig[key][n] = m.name
          end
        end
      end
    end
  end
  return problems
end

function RLP.ValidateReport(boss)
  local p = RLP.Validate(boss)
  if #p == 0 then Print("Setup OK for " .. (boss and boss.name or "?")) else
    for _, line in ipairs(p) do Print("|cffff4040" .. line .. "|r") end
  end
  return p
end

---------------------------------------------------------------- explainer
local function MechSummary(m)
  local cfg = RLP.Cfg(m)
  local _, w = RLP.Texts(m, cfg, { target = "target" })
  local who = cfg.who or ""
  local suffix = ""
  if not who:find("^AFFECTED") and not who:find("^EVERYONE") then
    local r = RLP.Resolve(who, m, cfg, nil, true)
    if r ~= "ALL" and #r > 0 then suffix = " -> " .. table.concat(r, ", ") end
  end
  local line = m.name .. ": " .. w .. suffix
  if #line > 100 then line = line:sub(1, 97) .. "..." end
  return line
end

function RLP.ExplainLines(boss, short)
  local lines = {}
  local mechs = {}
  for _, m in ipairs(RLP.Mechs(boss)) do
    if m.sig and RLP.Cfg(m).on then mechs[#mechs + 1] = m end
  end
  if #mechs == 0 then
    for _, t in ipairs(boss.tips) do lines[#lines + 1] = #t > 100 and (t:sub(1, 97) .. "...") or t end
  else
    local lastPhase
    for i, m in ipairs(mechs) do
      if short and #lines >= 3 then break end
      if m.phase and m.phase ~= lastPhase then lines[#lines + 1] = "Phase " .. m.phase .. ":" lastPhase = m.phase end
      lines[#lines + 1] = string.format("%d) %s", i, MechSummary(m))
    end
  end
  return lines
end

-- opts: chan = "RAID" | "PARTY" | "ME", short = bool
function RLP.Explain(boss, opts)
  boss = boss or RLP.CurrentBoss()
  if not boss then Print("Target a boss or pick one in the window first.") return end
  opts = opts or {}
  local kind = opts.chan or "RAID"
  if kind ~= "ME" and not IsInGroup() then kind = "ME" end
  local lines = RLP.ExplainLines(boss, opts.short)
  RLP.Enqueue(kind, "== " .. boss.name .. " ==", nil, 3, "X" .. GetTime())
  for i, l in ipairs(lines) do RLP.Enqueue(kind, l, nil, 3, "X" .. GetTime() .. i) end
  state.announced[boss.name] = true
end

function RLP.Strat(arg)
  local b = (arg and arg ~= "") and RLP.FindBoss(arg) or RLP.CurrentBoss()
  if not b then Print("No boss found. Target one or use /rlp strat <boss>.") return end
  RLP.Explain(b, { chan = "RAID" })
end

function RLP.Rules() RLP.Enqueue("RAID", RLP.db.rules, nil, 3, "RULES" .. GetTime()) end

---------------------------------------------------------------- whisper briefing
local function Assignments(boss, name)
  local items = {}
  for _, m in ipairs(RLP.Mechs(boss)) do
    local cfg = RLP.Cfg(m)
    if cfg.on then
      local who = cfg.who or ""
      local mine = false
      if who:find("^AFFECTED") then mine = false
      elseif not who:find("^EVERYONE") then
        local r = RLP.Resolve(who, m, cfg, nil, true)
        if r ~= "ALL" then for _, n in ipairs(r) do if n == name then mine = true end end end
      end
      if mine then
        local _, w = RLP.Texts(m, cfg, { target = "target", player = name })
        local spot = cfg.spot ~= "" and (" @" .. select(2, RLP.SpotParts(cfg.spot))) or ""
        items[#items + 1] = m.name .. ": " .. w .. spot
      end
    end
  end
  return items
end

function RLP.Brief(opts)
  opts = opts or RLP.db.brief
  local boss = RLP.CurrentBoss()
  if not IsInGroup() then Print("Not in a group.") return end
  local me = UnitName("player")
  local sent = 0
  for _, e in ipairs(RLP.Roster(true)) do
    if e.name ~= me then
      local key = e.name .. "|" .. (boss and boss.name or "")
      local skip = (state.informed[key] and not opts.force) or (opts.mode == "UNACKED" and state.acked[e.name])
      local items = boss and Assignments(boss, e.name) or {}
      if opts.mode == "ASSIGNED" and #items == 0 then skip = true end
      if not skip then
        local text
        if opts.personal and boss and #items > 0 then
          text = "RLP " .. boss.name .. " - " .. table.concat(items, "; ")
          if #text > 250 then text = text:sub(1, 247) .. "..." end
        else
          text = 'RLP: you may get whispers in fights, e.g. "{rt5} Bomb: run to Yellow". Just follow them. Reply 1.'
        end
        RLP.Enqueue("WHISPER", text, e.name, 3, "BR" .. e.name .. (opts.force and GetTime() or ""))
        state.informed[key] = true
        sent = sent + 1
      end
    end
  end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage("RLPRO", "BRIEF", IsInRaid() and "RAID" or "PARTY")
  end
  Print("Briefing queued for " .. sent .. " players.")
end

function RLP.BriefStatus()
  local missing, total = {}, 0
  for _, e in ipairs(RLP.Roster(true)) do
    if e.name ~= UnitName("player") then
      total = total + 1
      if not state.acked[e.name] then missing[#missing + 1] = e.name end
    end
  end
  Print(string.format("Acknowledged: %d/%d", total - #missing, total))
  if #missing > 0 then Print("Not acked: " .. table.concat(missing, ", ")) end
end

---------------------------------------------------------------- spot legend / markers
function RLP.SpotLegend(boss)
  boss = boss or RLP.CurrentBoss()
  if not boss then return end
  local used, lines = {}, {}
  for _, m in ipairs(RLP.Mechs(boss)) do
    local cfg = RLP.Cfg(m)
    if cfg.on and cfg.spot ~= "" and not used[cfg.spot] and cfg.spot ~= "MARK" then
      used[cfg.spot] = true
      local icon, label = RLP.SpotParts(cfg.spot)
      lines[#lines + 1] = (icon and ("{rt" .. icon .. "} ") or "") .. label .. " = " .. m.name
    end
  end
  for _, l in ipairs(lines) do RLP.Enqueue("RAID", l, nil, 3, "SL" .. l) end
  return #lines
end

---------------------------------------------------------------- pull timer + one-click Ready & Pull
function RLP.CancelPull() state.pullToken = (state.pullToken or 0) + 1 end

function RLP.Countdown(sec)
  sec = tonumber(sec) or 10
  state.pullToken = (state.pullToken or 0) + 1
  local token = state.pullToken
  local function tick(n)
    if token ~= state.pullToken then return end
    if n <= 0 then RLP.Enqueue("RW", "PULL NOW!", nil, 1, "PULL" .. GetTime()) return end
    if n == sec or n == 10 or n == 5 or n <= 3 then RLP.Enqueue("RW", "Pull in " .. n, nil, 1, "PT" .. n .. token) end
    C_Timer.After(1, function() tick(n - 1) end)
  end
  tick(sec)
end

function RLP.Pull(sec)
  RLP.Check(false)
  RLP.Countdown(sec)
end

function RLP.ReadyPull()
  local p = RLP.db.pull
  local boss = RLP.CurrentBoss()
  if p.validate and boss then
    local probs = RLP.ValidateReport(boss)
    if #probs > 0 then Print("Fix the problems above, or press Ready & Pull again to pull anyway.")
      if not state.pullWarned then state.pullWarned = true C_Timer.After(15, function() state.pullWarned = false end) return end
    end
  end
  state.pullWarned = false
  if p.check then RLP.Check(true, p.whisperMissing) end
  if p.explain and boss then RLP.Explain(boss, { chan = "RAID", short = RLP.db.explain.short }) end
  if p.brief then RLP.Brief() end
  if p.rules then RLP.Rules() end
  if p.markers and boss then RLP.SpotLegend(boss) end
  RLP.Countdown(p.count)
end

---------------------------------------------------------------- roles
function RLP.AutoAssign()
  local db = RLP.db
  local fills = {
    Healer = "PRIEST", Decurse = "MAGE,DRUID", Dispel = "PRIEST,PALADIN", Purge = "PRIEST,SHAMAN", Tranq = "HUNTER",
    Interrupt = "ROGUE,MAGE", CC = "MAGE", Banish = "WARLOCK",
  }
  local changed = {}
  for role, classes in pairs(fills) do
    if #(db.roles[role] or {}) == 0 then
      local set = {}
      for c in classes:gmatch("[^,]+") do set[c] = true end
      for _, e in ipairs(RLP.Roster(true)) do
        if set[e.class or ""] then table.insert(db.roles[role], e.name) changed[role] = true end
      end
    end
  end
  for _, e in ipairs(RLP.Roster(true)) do
    if e.role == "MAINTANK" and #db.roles.MT == 0 then table.insert(db.roles.MT, e.name) changed.MT = true end
    if e.role == "MAINASSIST" and #db.roles.OT == 0 then table.insert(db.roles.OT, e.name) changed.OT = true end
  end
  local list = {}
  for r in pairs(changed) do list[#list + 1] = r end
  Print(#list > 0 and ("Auto-assigned roles: " .. table.concat(list, ", ")) or "Nothing to fill - all roles already set (or no matching players).")
end

function RLP.SwapPlayer(a, b)
  local db, n = RLP.db, 0
  local function sub(list)
    for i, v in ipairs(list or {}) do if v == a then list[i] = b n = n + 1 end end
  end
  for _, s in pairs(db.setups) do sub(s.players) sub(s.backup) end
  for _, l in pairs(db.roles) do sub(l) end
  Print(string.format("Replaced %s with %s in %d places.", a, b, n))
end

function RLP.ResetBoss(boss)
  for _, m in ipairs(RLP.Mechs(boss)) do RLP.db.setups[m.id] = nil end
  Print("Reset " .. boss.name .. " to defaults.")
end

---------------------------------------------------------------- presets
local function Snapshot()
  return { setups = RLP.DeepCopy(RLP.db.setups), roles = RLP.DeepCopy(RLP.db.roles), spots = RLP.DeepCopy(RLP.db.spots) }
end

function RLP.PresetSave(name)
  if not name or name == "" then return end
  RLP.db.presets[name] = Snapshot()
  Print("Saved preset '" .. name .. "'.")
end

function RLP.PresetApply(data)
  local db = RLP.db
  db.setups = RLP.DeepCopy(data.setups or {})
  db.roles = RLP.DeepCopy(data.roles or {})
  for _, r in ipairs(RLP.ROLES) do db.roles[r] = db.roles[r] or {} end
  if data.spots then db.spots = RLP.DeepCopy(data.spots) end
  -- warn about named players who are not in the raid
  local missing, seen = {}, {}
  local function chk(list)
    for _, n in ipairs(list or {}) do
      if not seen[n] and not RLP.Entry(n) then seen[n] = true missing[#missing + 1] = n end
    end
  end
  for _, s in pairs(db.setups) do chk(s.players) chk(s.backup) end
  for _, l in pairs(db.roles) do chk(l) end
  if #missing > 0 then Print("Not in raid: " .. table.concat(missing, ", ") .. "  (use /rlp swap Old New)") end
end

function RLP.PresetLoad(name)
  local p = RLP.db.presets[name]
  if not p then Print("No preset '" .. tostring(name) .. "'.") return end
  RLP.PresetApply(p)
  Print("Loaded preset '" .. name .. "'.")
  if RLP.RefreshUI then RLP.RefreshUI() end
end

function RLP.PresetDelete(name) RLP.db.presets[name] = nil end

function RLP.PresetExport(name)
  return RLP.Serialize(name and RLP.db.presets[name] or Snapshot())
end

function RLP.PresetImport(str, name)
  local data, err = RLP.Deserialize(str)
  if not data then Print("Import failed: " .. tostring(err)) return false end
  if type(data.setups) ~= "table" then Print("Import failed: no setups in string") return false end
  RLP.db.presets[name or "imported"] = data
  RLP.PresetLoad(name or "imported")
  return true
end

function RLP.SaveAuto()
  local db = RLP.db
  if next(db.setups) then db.presets["auto " .. date("%Y-%m-%d")] = Snapshot() end
end

---------------------------------------------------------------- reports / leaderboards
function RLP.PostReport(full)
  for _, line in ipairs(RLP.BuildReport(full)) do RLP.Enqueue("RAID", line, nil, 3) end
end

function RLP.Offenders(bossName)
  local rows = {}
  if bossName and bossName ~= "" then
    local b = RLP.FindBoss(bossName)
    local src = b and RLP.db.bossOff[b.name]
    if not src then Print("No data for that boss.") return end
    for p, n in pairs(src) do rows[#rows + 1] = { p, n } end
  else
    for p, spells in pairs(RLP.db.offenders) do
      local total = 0
      for _, n in pairs(spells) do total = total + n end
      rows[#rows + 1] = { p, total }
    end
  end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  if #rows == 0 then Print("No avoidable damage recorded yet.") return end
  for i = 1, math.min(#rows, 10) do Print(string.format("%d. %s - %d avoidable hits", i, rows[i][1], rows[i][2])) end
end

---------------------------------------------------------------- verify / learn / map
function RLP.Verify()
  local any = false
  for _, boss in ipairs(RLP.AllBosses()) do
    local seen = RLP.db.seen[boss.name]
    if seen then
      for _, m in ipairs(RLP.Mechs(boss)) do
        if m.kind == "CLEU" and m.spell and not seen[m.spell] then
          Print(string.format("|cffff4040%s: '%s' never seen in combat log|r", boss.name, m.spell))
          any = true
        end
      end
    end
  end
  if not any then Print("Every mechanic on bosses you have fought has been seen. (Bosses not fought yet cannot be checked.)") end
end

function RLP.LearnToggle()
  local db = RLP.db
  db.learn = not db.learn
  Print("Learn mode " .. (db.learn and "ON: fight a boss, then /rlp learned" or "OFF"))
end

function RLP.Learned(bossName)
  local b = (bossName and bossName ~= "") and RLP.FindBoss(bossName) or RLP.CurrentBoss()
  local bucket = b and RLP.db.learned[b.name]
  if not bucket then Print("Nothing learned yet. /rlp learn, then fight.") return end
  state.learnedList = {}
  for _, e in pairs(bucket) do state.learnedList[#state.learnedList + 1] = e end
  table.sort(state.learnedList, function(x, y) return x.n > y.n end)
  state.learnedBoss = b
  for i = 1, math.min(#state.learnedList, 30) do
    local e = state.learnedList[i]
    Print(string.format("%d. [%s] %s (x%d, %s)", i, e.ev, e.spell, e.n, e.src or "?"))
  end
  Print("Map one with: /rlp map <number> <TEMPLATE> [who]   e.g. /rlp map 3 DISPEL AFFECTED")
end

function RLP.Map(index, tmpl, who)
  local e = state.learnedList and state.learnedList[tonumber(index) or 0]
  local b = state.learnedBoss
  if not e or not b then Print("Run /rlp learned first, then pick a number.") return end
  tmpl = (tmpl or ""):upper()
  if not RLP.Templates[tmpl] then Print("Unknown template. Templates: " .. table.concat(RLP.TemplateOrder, " ")) return end
  local m = { t = tmpl, who = who ~= "" and who or "EVERYONE", sig = true }
  if e.ev == "YELL" or e.ev == "EMOTE" then m.kind, m.pat, m.name = e.ev, e.spell:lower(), e.spell
  else m.kind, m.ev, m.spell = "CLEU", e.ev, e.spell end
  RLP.db.custom[b.name] = RLP.db.custom[b.name] or {}
  table.insert(RLP.db.custom[b.name], m)
  RLP.NormalizeMech(b, m)
  Print("Added mechanic '" .. m.name .. "' to " .. b.name .. ".")
  if RLP.RefreshUI then RLP.RefreshUI() end
end
