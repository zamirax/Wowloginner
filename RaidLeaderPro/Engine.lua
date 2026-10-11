local ADDON, RLP = ...

local DEFAULTS = {
  enabled = true, mute = false,
  summary = false,        -- also post "Mechanic: names -> instruction" to raid for assigned mechanics
  autoExplain = true,     -- post the explainer when you target a boss out of combat
  autoPostReport = false, -- post top offenders to raid after each fight
  deathAlert = true,
  cap = 20, dedupe = 5, rate = 3,
  setups = {}, roles = {}, spots = { Yellow = 1, Orange = 2, Purple = 3, Green = 4, Silver = 5, Blue = 6, Red = 7 },
  presets = {}, offenders = {}, bossOff = {}, seen = {}, learn = false, learned = {}, custom = {},
  pull = { validate = true, check = true, whisperMissing = true, explain = false, brief = false, rules = false, markers = true, count = 10 },
  brief = { mode = "ALL", personal = true },
  explain = { short = false },
  rules = "Loot rules: not set yet. Leader: /rlp setrules <text>",
  minimapAngle = 210,
}

local state = { inCombat = false, boss = nil, phase = 1, start = 0, dead = {}, fails = {}, deaths = {}, lastHit = {}, cd = {}, count = {},
  rot = {}, pending = {}, warnedAt = {}, resp = {}, log = {}, hpFired = {}, timerNext = {}, announced = {}, informed = {}, acked = {}, firstFail = nil }
RLP.state = state

local function Merge(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then dst[k] = RLP.DeepCopy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" then Merge(dst[k], v) end
  end
end

local Short = RLP.Short
local function Print(...) RLP.Print(...) end

---------------------------------------------------------------- chat output
local function Chan(warn)
  if IsInRaid() then
    if warn and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return "RAID_WARNING" end
    return "RAID"
  elseif IsInGroup() then return "PARTY" end
end

function RLP.Say(msg, warn, forceChan)
  local ch = forceChan or Chan(warn)
  if not ch then Print(msg) return end
  while #msg > 250 do
    local cut = msg:sub(1, 250):match("^(.*) ") or msg:sub(1, 250)
    SendChatMessage(cut, ch)
    msg = (msg:sub(#cut + 1):gsub("^%s+", ""))
  end
  SendChatMessage(msg, ch)
end

function RLP.CanLead()
  return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function RLP.Warn(msg)
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  else
    Print(msg)
  end
  if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

function RLP.Log(text)
  local t = state.boss and (GetTime() - state.start) or 0
  table.insert(state.log, { t = t, text = text })
  if #state.log > 60 then table.remove(state.log, 1) end
  if RLP.OnLog then RLP.OnLog() end
end

---------------------------------------------------------------- outgoing queue (rate limit + dedupe + priority)
local Q, sentAt, tokens = {}, {}, 2

function RLP.Enqueue(kind, text, to, prio, ckey)
  local db = RLP.db
  local now = GetTime()
  ckey = ckey or (kind .. (to or "") .. text)
  if sentAt[ckey] and now - sentAt[ckey] < db.dedupe then return false end
  sentAt[ckey] = now
  Q[#Q + 1] = { kind = kind, text = text, to = to, prio = prio or 2 }
  return true
end

function RLP.QueueLength() return #Q end

local function Deliver(it)
  if it.kind == "WHISPER" then
    if it.to == UnitName("player") then RLP.Warn(it.text) else SendChatMessage(it.text, "WHISPER", nil, it.to) end
  elseif it.kind == "RW" then RLP.Say(it.text, true)
  elseif it.kind == "RAID" then RLP.Say(it.text, false)
  elseif it.kind == "PARTY" then SendChatMessage(it.text, "PARTY")
  elseif it.kind == "ME" then Print(it.text) end
end

local function Drain()
  tokens = math.min(tokens + RLP.db.rate * 0.25, 3)
  while tokens >= 1 and #Q > 0 do
    local best = 1
    for i = 2, #Q do if Q[i].prio < Q[best].prio then best = i end end
    local it = table.remove(Q, best)
    tokens = tokens - 1
    if not (it.kind == "WHISPER" and it.to ~= UnitName("player") and not RLP.Alive(it.to) and not it.force) then
      Deliver(it)
    end
  end
end

---------------------------------------------------------------- per-mechanic config
function RLP.Cfg(m)
  local s = RLP.db.setups[m.id] or {}
  local function p(k, d) if s[k] ~= nil then return s[k] end return d end
  local on = s.on
  if on == nil then on = not m.off end
  return { on = on, who = p("who", m.who), act = p("act", m.act), t = p("t", m.t), spot = p("spot", m.spot or ""),
    text = p("text", m.text), players = s.players or {}, backup = s.backup or {} }
end

function RLP.SetCfg(m, key, val)
  local db = RLP.db
  db.setups[m.id] = db.setups[m.id] or {}
  db.setups[m.id][key] = val
end

function RLP.IsConfigured(boss)
  for _, m in ipairs(RLP.Mechs(boss)) do if RLP.db.setups[m.id] then return true end end
  return false
end

function RLP.Texts(m, cfg, ctx)
  local tpl = RLP.Templates[cfg.t or ""]
  local s, w
  if cfg.t == "CUSTOM" or not tpl then s = cfg.text or m.name w = s else s, w = tpl[1], tpl[2] end
  local c = { spot = cfg.spot, spell = m.spell or m.name, target = ctx.target or ctx.affected, sec = ctx.sec, player = ctx.player,
    class = ctx.class, screen = ctx.screen }
  return RLP.Expand(s, c), RLP.Expand(w, c)
end

---------------------------------------------------------------- who resolution
local function InRoster(list)
  local out = {}
  for _, n in ipairs(list or {}) do if RLP.Entry(n) then out[#out + 1] = n end end
  return out
end

local function ByClass(spec)
  local out, set = {}, {}
  for c in spec:gmatch("[^,]+") do set[c:upper()] = true end
  for _, e in ipairs(RLP.Roster()) do if set[e.class or ""] then out[#out + 1] = e.name end end
  return out
end

local function ResolveOne(alt, m, cfg, affected)
  if alt == "EVERYONE" then return "ALL" end
  if alt == "AFFECTED" then return affected and { affected } or {} end
  if alt == "PLAYERS" then return InRoster(cfg.players) end
  if alt == "ROTATION" then return InRoster(cfg.players), true end
  if alt == "HEALERS" then
    local r = InRoster(RLP.db.roles.Healer)
    if #r > 0 then return r end
    return ByClass("PRIEST")
  end
  if alt == "TANKS" then
    local out = InRoster(RLP.db.roles.MT)
    for _, n in ipairs(InRoster(RLP.db.roles.OT)) do out[#out + 1] = n end
    if #out == 0 then
      for _, e in ipairs(RLP.Roster()) do if e.role == "MAINTANK" then out[#out + 1] = e.name end end
    end
    return out
  end
  local role = alt:match("^ROLE:(.+)$")
  if role then
    if role == "MT" and #InRoster(RLP.db.roles.MT) == 0 then
      for _, e in ipairs(RLP.Roster()) do if e.role == "MAINTANK" then return { e.name } end end
    end
    return InRoster(RLP.db.roles[role])
  end
  local cls = alt:match("^CLASS:(.+)$")
  if cls then return ByClass(cls) end
  local grp = alt:match("^GROUP:(%d)$")
  if grp then
    local out = {}
    for _, e in ipairs(RLP.Roster()) do if e.group == tonumber(grp) then out[#out + 1] = e.name end end
    return out
  end
  return {}
end

-- replace dead/offline assignees with the first live backup
local function ApplyBackup(list, backup)
  local out, used = {}, {}
  for _, n in ipairs(list) do used[n] = true end
  for _, n in ipairs(list) do
    if RLP.Alive(n) then out[#out + 1] = n
    else
      local pick
      for _, b in ipairs(backup or {}) do
        if not used[b] and RLP.Alive(b) then pick = b break end
      end
      if pick then
        used[pick] = true
        out[#out + 1] = pick
        RLP.Log("Assigned " .. n .. " dead -> backup " .. pick)
      else
        RLP.Log("Assigned " .. n .. " unavailable, no backup")
      end
    end
  end
  return out
end

-- returns "ALL" (broadcast) or a list of names, plus the next rotation name if any
function RLP.Resolve(spec, m, cfg, affected, peek)
  for alt in (spec or "EVERYONE"):gmatch("[^|]+") do
    local r, isRot = ResolveOne(alt, m, cfg, affected)
    if r == "ALL" then return "ALL" end
    if #r > 0 then
      if isRot and peek then return r end
      if isRot then
        local idx = state.rot[m.id] or 0
        local n = #r
        local picked, nextName
        for i = 1, n do
          local cand = r[((idx + i - 1) % n) + 1]
          if RLP.Alive(cand) then
            picked = cand
            if not peek then state.rot[m.id] = ((idx + i - 1) % n) + 1 end
            for j = 1, n - 1 do
              local nx = r[((idx + i - 1 + j) % n) + 1]
              if RLP.Alive(nx) and nx ~= cand then nextName = nx break end
            end
            break
          end
        end
        if picked then return { picked }, nextName end
        return {}
      end
      if peek then return r end
      return ApplyBackup(r, cfg.backup)
    end
  end
  return {}
end

---------------------------------------------------------------- firing
local ACTIONS = {
  WHISPER = { w = true }, RW = { rw = true }, RAID = { raid = true }, SCREEN = { screen = true },
  WHISPER_RW = { w = true, rw = true }, NONE = {},
}
RLP.ActionList = { { "WHISPER", "Whisper" }, { "RW", "Raid warning" }, { "RAID", "Raid chat" }, { "SCREEN", "On-screen only" },
  { "WHISPER_RW", "Whisper + RW" }, { "NONE", "Nothing (log)" } }

local function Out(ctx, kind, text, to, prio, ckey)
  if ctx.test then
    RLP.Print(string.format("[TEST %s%s] %s", kind, to and (" -> " .. to) or "", text))
  else
    RLP.Enqueue(kind, text, to, prio, ckey)
  end
end

function RLP.Fire(m, ctx)
  ctx = ctx or {}
  local db = RLP.db
  local cfg = RLP.Cfg(m)
  local now = GetTime()
  if ctx.manual then
    state.count[m.id] = (state.count[m.id] or 0) + 1
  elseif not ctx.test then
    if not db.enabled or db.mute or not cfg.on then return end
    if m.phase and state.phase ~= m.phase then return end
    if (state.count[m.id] or 0) >= (m.cap or db.cap) then return end
    local key = m.id .. ((cfg.who or ""):find("AFFECTED") and ("|" .. (ctx.affected or "")) or "")
    if state.cd[key] and now - state.cd[key] < (m.cd or 4) then return end
    state.cd[key] = now
    state.count[m.id] = (state.count[m.id] or 0) + 1
  end
  local recips, nextName = RLP.Resolve(cfg.who, m, cfg, ctx.affected)
  local act = ACTIONS[cfg.act or "NONE"] or ACTIONS.NONE
  local prio = m.crit and 1 or 2
  ctx.screen = false
  local short, whisper = RLP.Texts(m, cfg, ctx)
  RLP.Log(m.name .. (ctx.affected and (" [" .. ctx.affected .. "]") or "") .. ": " .. short)

  if recips == "ALL" then
    if act.rw then Out(ctx, "RW", short, nil, prio, "RW" .. m.id)
    elseif act.raid or act.w then Out(ctx, "RAID", short, nil, prio, "R" .. m.id) end
    if act.screen or not IsInGroup() then ctx.screen = true RLP.Warn((RLP.Texts(m, cfg, ctx))) end
  else
    if #recips == 0 and not ctx.test then RLP.Log(m.name .. ": nobody to notify") end
    if act.w then
      for _, n in ipairs(recips) do
        local e = RLP.Entry(n)
        ctx.player, ctx.class = n, e and e.class
        local _, w = RLP.Texts(m, cfg, ctx)
        if n == UnitName("player") and not ctx.test then RLP.Warn(w)
        else Out(ctx, "WHISPER", w, n, prio, "W" .. n .. m.id) end
      end
    end
    if act.rw then Out(ctx, "RW", short, nil, prio, "RW" .. m.id) end
    if act.raid then Out(ctx, "RAID", short, nil, prio, "R" .. m.id) end
    if act.screen then ctx.screen = true RLP.Warn((RLP.Texts(m, cfg, ctx))) end
    if nextName and act.w then Out(ctx, "WHISPER", "NEXT: " .. short, nextName, prio, "N" .. nextName .. m.id) end
    if db.summary and #recips > 0 and not act.rw and not act.raid then
      Out(ctx, "RAID", m.name .. ": " .. table.concat(recips, ", ") .. " -> " .. short, nil, 3, "S" .. m.id)
    end
    if ctx.affected and (cfg.who or ""):find("AFFECTED") then
      state.pending[m.id .. "|" .. ctx.affected] = { m = m, t = now }
      state.warnedAt[ctx.affected] = now
    end
  end
end

function RLP.TestMech(m)
  local me = UnitName("player")
  RLP.Fire(m, { test = true, affected = me })
end

---------------------------------------------------------------- fight tracking
local function IsGroupPlayer(flags)
  return flags and bit.band(flags, 0x400) ~= 0 and bit.band(flags, 0x7) ~= 0
end

local function InRaidInstance()
  local inside, kind = IsInInstance()
  return inside and kind == "raid"
end

local triggers

local function BuildTriggers(boss)
  local T = { cleuName = {}, cleuId = {}, yell = {}, emote = {}, hp = {}, timer = {} }
  for _, m in ipairs(RLP.Mechs(boss)) do
    if m.kind == "CLEU" then
      if m.spell then
        T.cleuName[m.ev] = T.cleuName[m.ev] or {}
        T.cleuName[m.ev][m.spell] = T.cleuName[m.ev][m.spell] or {}
        table.insert(T.cleuName[m.ev][m.spell], m)
      end
      if m.sid then
        T.cleuId[m.ev] = T.cleuId[m.ev] or {}
        T.cleuId[m.ev][m.sid] = T.cleuId[m.ev][m.sid] or {}
        table.insert(T.cleuId[m.ev][m.sid], m)
      end
    elseif m.kind == "YELL" then table.insert(T.yell, m)
    elseif m.kind == "EMOTE" then table.insert(T.emote, m)
    elseif m.kind == "HP" then table.insert(T.hp, m)
    elseif m.kind == "TIMER" then table.insert(T.timer, m) end
  end
  return T
end

local function Trip(m, ctx)
  if m.setPhase then state.phase = m.setPhase RLP.Log("Phase " .. m.setPhase) end
  RLP.Fire(m, ctx)
end

local function StartFight(boss)
  state.boss, state.start, state.phase = boss, GetTime(), 1
  state.dead, state.fails, state.deaths, state.lastHit, state.cd, state.count = {}, {}, {}, {}, {}, {}
  state.rot, state.pending, state.warnedAt, state.resp, state.log = {}, {}, {}, {}, {}
  state.hpFired, state.timerNext, state.firstFail = {}, {}, nil
  triggers = BuildTriggers(boss)
  RLP.Print("Engaged " .. boss.name)
  RLP.Log("Engaged " .. boss.name)
  if RLP.OnFightStart then RLP.OnFightStart(boss) end
end

local function MS(t) t = math.floor(t or 0) return string.format("%d:%02d", math.floor(t / 60), t % 60) end

function RLP.BuildReport(full)
  local b = state.lastFight
  if not b then return { "No fight recorded yet." } end
  local lines = {}
  lines[#lines + 1] = string.format("%s: %s in %s", b.name, b.killed and "KILL" or "WIPE/RESET", MS(b.duration))
  local rows = {}
  for player, spells in pairs(b.fails) do
    for spell, n in pairs(spells) do rows[#rows + 1] = { player, spell, n, b.warned[player] } end
  end
  table.sort(rows, function(x, y) return x[3] > y[3] end)
  for i = 1, math.min(#rows, full and 8 or 3) do
    lines[#lines + 1] = string.format("Avoidable: %s hit by %s x%d%s", rows[i][1], rows[i][2], rows[i][3], rows[i][4] and " (was warned)" or "")
  end
  if b.deaths[1] then
    lines[#lines + 1] = string.format("First death: %s at %s (%s)", b.deaths[1].name, MS(b.deaths[1].t), b.deaths[1].by or "?")
  end
  if full then
    if b.firstFail then lines[#lines + 1] = string.format("First avoidable hit: %s (%s) at %s", b.firstFail.name, b.firstFail.spell, MS(b.firstFail.t)) end
    for i = 2, math.min(#b.deaths, 8) do
      local d = b.deaths[i]
      lines[#lines + 1] = string.format("Died (%s): %s - %s", MS(d.t), d.name, d.by or "unknown")
    end
    for _, r in ipairs(b.resp) do
      lines[#lines + 1] = string.format("Response: %s %s cleared after %.0fs", r.who, r.mech, r.dt)
    end
    if b.assignedFails and #b.assignedFails > 0 then
      lines[#lines + 1] = "Assigned players who failed: " .. table.concat(b.assignedFails, ", ")
    end
  end
  if #rows == 0 and #b.deaths == 0 then lines[#lines + 1] = "No avoidable damage or deaths." end
  return lines
end

local function AssignedNames(boss)
  local set = {}
  for _, m in ipairs(RLP.Mechs(boss)) do
    local cfg = RLP.Cfg(m)
    if cfg.on and not (cfg.who or ""):find("^AFFECTED") and not (cfg.who or ""):find("^EVERYONE") then
      local r = RLP.Resolve(cfg.who, m, cfg, nil, true)
      if r ~= "ALL" then for _, n in ipairs(r) do set[n] = true end end
    end
  end
  return set
end

function RLP.EndFight(killed)
  local b = state.boss
  if not b then return end
  local assigned, af = AssignedNames(b), {}
  for p in pairs(state.fails) do if assigned[p] then af[#af + 1] = p end end
  for _, d in ipairs(state.deaths) do if assigned[d.name] then af[#af + 1] = d.name .. " (died)" end end
  state.lastFight = { name = b.name, killed = killed, duration = GetTime() - state.start, fails = state.fails, deaths = state.deaths,
    warned = RLP.DeepCopy(state.warnedAt), resp = state.resp, firstFail = state.firstFail, assignedFails = af }
  local db = RLP.db
  db.bossOff[b.name] = db.bossOff[b.name] or {}
  for player, spells in pairs(state.fails) do
    db.offenders[player] = db.offenders[player] or {}
    for spell, n in pairs(spells) do
      db.offenders[player][spell] = (db.offenders[player][spell] or 0) + n
      db.bossOff[b.name][player] = (db.bossOff[b.name][player] or 0) + n
    end
  end
  state.boss, triggers = nil, nil
  for _, line in ipairs(RLP.BuildReport(false)) do Print(line) end
  if db.autoPostReport and IsInGroup() then
    for _, line in ipairs(RLP.BuildReport(false)) do RLP.Enqueue("RAID", line, nil, 3) end
  end
  if RLP.OnFightEnd then RLP.OnFightEnd() end
end

local function OnPlayerDeath(name)
  if not state.boss then return end
  local db = RLP.db
  for _, role in ipairs({ "MT", "OT", "Interrupt" }) do
    for _, n in ipairs(db.roles[role] or {}) do
      if n == name and db.deathAlert then RLP.Warn(role .. " " .. name .. " DIED") RLP.Log(role .. " " .. name .. " died") end
    end
  end
  for _, m in ipairs(RLP.Mechs(state.boss)) do
    local cfg = RLP.Cfg(m)
    if cfg.on and #cfg.backup > 0 then
      local base = RLP.Resolve(cfg.who, m, cfg, nil, true)
      if base ~= "ALL" then
        for _, n in ipairs(base) do
          if n == name then
            for _, b in ipairs(cfg.backup) do
              if RLP.Alive(b) and b ~= name then
                RLP.Warn("Assigned " .. name .. " dead -> backup " .. b)
                RLP.Log("Assigned " .. name .. " dead -> backup " .. b .. " (" .. m.name .. ")")
                RLP.Enqueue("WHISPER", "BACKUP for " .. m.name, b, 1, "B" .. b .. m.id)
                break
              end
            end
          end
        end
      end
    end
  end
end

local function Learn(sName, ev, spellName)
  local db = RLP.db
  local b = state.boss
  local bucket = db.learned[b.name] or {}
  db.learned[b.name] = bucket
  local key = ev .. "|" .. spellName
  local e = bucket[key] or { ev = ev, spell = spellName, src = sName, n = 0 }
  e.n = e.n + 1
  bucket[key] = e
end

local function OnCombatLog()
  local _, ev, _, _, sName, sFlags, _, dGUID, dName, dFlags, _, a12, a13, _, a15 = CombatLogGetCurrentEventInfo()

  if not state.boss then
    if state.inCombat and InRaidInstance() then
      local b = RLP.mobIndex[sName or ""] or RLP.mobIndex[dName or ""]
      if b then StartFight(b) end
    end
    return
  end
  local boss = state.boss
  local db = RLP.db

  if ev == "UNIT_DIED" then
    if RLP.mobIndex[dName or ""] == boss then
      state.dead[dName] = true
      local done
      if boss.final then done = state.dead[boss.final]
      else
        done = true
        for _, m in ipairs(boss.mobs) do if not state.dead[m] then done = false end end
      end
      if done then RLP.EndFight(true) end
    elseif IsGroupPlayer(dFlags) and dGUID and dGUID:find("^Player") then
      local who = Short(dName)
      table.insert(state.deaths, { name = who, by = state.lastHit[who], t = GetTime() - state.start })
      OnPlayerDeath(who)
    end
    return
  end

  local isSpell = ev:sub(1, 6) == "SPELL_"
  local bossSource = RLP.mobIndex[sName or ""] == boss
  if isSpell and a13 and (bossSource or RLP.mobIndex[dName or ""] == boss) then
    db.seen[boss.name] = db.seen[boss.name] or {}
    db.seen[boss.name][a13] = (db.seen[boss.name][a13] or 0) + 1
    if db.learn and bossSource then Learn(sName, ev, a13) end
  end

  local isDamage = ev == "SPELL_DAMAGE" or ev == "SPELL_PERIODIC_DAMAGE" or ev == "RANGE_DAMAGE"
  if (isDamage or ev == "SWING_DAMAGE") and IsGroupPlayer(dFlags) then
    local who = Short(dName)
    local spell = isDamage and a13 or "melee"
    state.lastHit[who] = string.format("%s (%d)", spell, math.floor((isDamage and a15 or a12) or 0))
    if isDamage and boss.avoid then
      for _, s in ipairs(boss.avoid) do
        if s == a13 then
          state.fails[who] = state.fails[who] or {}
          state.fails[who][s] = (state.fails[who][s] or 0) + 1
          if not state.firstFail then state.firstFail = { name = who, spell = s, t = GetTime() - state.start } end
        end
      end
    end
    return
  end

  if not isSpell or not triggers then return end

  if ev == "SPELL_AURA_REMOVED" and dName then
    local who = Short(dName)
    for k, p in pairs(state.pending) do
      if p.m.spell == a13 and k == p.m.id .. "|" .. who then
        table.insert(state.resp, { who = who, mech = p.m.name, dt = GetTime() - p.t })
        state.pending[k] = nil
      end
    end
  end

  local byName = triggers.cleuName[ev] and triggers.cleuName[ev][a13]
  local byId = triggers.cleuId[ev] and triggers.cleuId[ev][a12]
  for _, list in ipairs({ byName or {}, byId or {} }) do
    for _, m in ipairs(list) do
      local cfg = RLP.Cfg(m)
      local affected = dName and Short(dName)
      if (cfg.who or ""):find("^AFFECTED") then
        if IsGroupPlayer(dFlags) then Trip(m, { affected = affected }) end
      else
        Trip(m, { affected = affected })
      end
    end
  end
end

function RLP.OnText(kind, text, npc)
  if not state.boss or not triggers or not text then return end
  local l = text:lower()
  if RLP.db.learn then
    local bucket = RLP.db.learned[state.boss.name] or {}
    RLP.db.learned[state.boss.name] = bucket
    bucket[kind .. "|" .. text:sub(1, 60)] = { ev = kind, spell = text:sub(1, 60), src = npc, n = 1 }
  end
  for _, m in ipairs(kind == "YELL" and triggers.yell or triggers.emote) do
    if l:find(m.pat, 1, true) then Trip(m, {}) end
  end
end

local function HealthPct(boss)
  local mob = boss.hpMob or boss.mobs[1]
  for _, e in ipairs(RLP.Roster()) do
    local u = e.unit .. "target"
    if UnitExists(u) and UnitName(u) == mob then
      local mx = UnitHealthMax(u)
      if mx and mx > 0 then return UnitHealth(u) / mx * 100 end
    end
  end
end

function RLP.NextTimer()
  if not state.boss or not triggers then return nil end
  local best
  local el = GetTime() - state.start
  for _, m in ipairs(triggers.timer) do
    local at = state.timerNext[m.id] or m.sec
    if at and (not best or at < best.at) then best = { m = m, at = at } end
  end
  if best then return best.m.name, best.at - el end
end

local function Tick()
  if not state.boss or not triggers then return end
  local el = GetTime() - state.start
  for _, m in ipairs(triggers.timer) do
    local at = state.timerNext[m.id] or m.sec
    if at and el >= at then
      Trip(m, {})
      state.timerNext[m.id] = m.every and (at + m.every) or false
    end
  end
  if #triggers.hp > 0 then
    local pct = HealthPct(state.boss)
    if pct then
      for _, m in ipairs(triggers.hp) do
        if not state.hpFired[m.id] and pct <= m.hp then
          state.hpFired[m.id] = true
          Trip(m, {})
        end
      end
    end
  end
  if RLP.OnTick then RLP.OnTick() end
end

---------------------------------------------------------------- manual / HUD helpers
function RLP.SkipPhase()
  state.phase = (state.phase or 1) + 1
  RLP.Log("Phase -> " .. state.phase)
end

function RLP.ManualFire(m)
  local t = UnitName("target")
  RLP.Fire(m, { manual = true, affected = t and Short(t) or UnitName("player") })
end

function RLP.SetMute(v)
  RLP.db.mute = v
  Print("Alerts " .. (v and "MUTED" or "ON"))
  if RLP.OnLog then RLP.OnLog() end
end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "COMBAT_LOG_EVENT_UNFILTERED",
  "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_ADDON", "CHAT_MSG_WHISPER",
  "PLAYER_TARGET_CHANGED", "PLAYER_LOGOUT" }) do f:RegisterEvent(e) end

f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    OnCombatLog()
  elseif event == "ADDON_LOADED" and a1 == ADDON then
    RaidLeaderPro_DB = RaidLeaderPro_DB or {}
    RLP.db = RaidLeaderPro_DB
    Merge(RLP.db, DEFAULTS)
    for _, r in ipairs(RLP.ROLES) do RLP.db.roles[r] = RLP.db.roles[r] or {} end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix("RLPRO") end
    C_Timer.NewTicker(0.25, Drain)
    C_Timer.NewTicker(0.5, Tick)
    RLP.Print(string.format("loaded. /rlp for the setup window%s.", #RLP.problems > 0 and (" |cffff4040(" .. #RLP.problems .. " data warnings: /rlp validate)|r") or ""))
    if RLP.OnLoaded then RLP.OnLoaded() end
  elseif not RLP.db then
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    state.inCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    state.inCombat = false
    C_Timer.After(5, function()
      if state.boss and not state.inCombat then RLP.EndFight(false) end
    end)
  elseif event == "CHAT_MSG_MONSTER_YELL" then
    RLP.OnText("YELL", a1, a2)
  elseif event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "CHAT_MSG_MONSTER_EMOTE" then
    RLP.OnText("EMOTE", a1, a2)
  elseif event == "CHAT_MSG_ADDON" then
    if a1 == "RLPRO" then
      local sender = Short(a4 or "")
      if a2 == "BRIEF" and sender ~= UnitName("player") then
        C_ChatInfo.SendAddonMessage("RLPRO", "ACK", "WHISPER", a4)
      elseif a2 == "ACK" then
        state.acked[sender] = true
        if RLP.OnLog then RLP.OnLog() end
      end
    end
  elseif event == "CHAT_MSG_WHISPER" then
    if a1 and a1:match("^%s*1%s*$") and RLP.Entry(Short(a2 or "")) then
      state.acked[Short(a2)] = true
      if RLP.OnLog then RLP.OnLog() end
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    local db = RLP.db
    if db.autoExplain and InRaidInstance() and IsInRaid() and RLP.CanLead() and not state.inCombat and not state.boss then
      local b = RLP.mobIndex[UnitName("target") or ""]
      if b and not state.announced[b.name] then RLP.Explain(b, { chan = "RAID", short = db.explain.short }) end
    end
    if RLP.OnTarget then RLP.OnTarget() end
  elseif event == "PLAYER_LOGOUT" then
    if RLP.SaveAuto then RLP.SaveAuto() end
  end
end)
