local ADDON, RLP = ...
_G.RaidLeaderPro = RLP

RLP.ICONS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "X", "Skull" }
RLP.ROLES = { "MT", "OT", "Healer", "Interrupt", "Decurse", "Dispel", "Purge", "Tranq", "CC", "Banish" }

local function Short(n) return (n or ""):gsub("%-.*$", "") end
RLP.Short = function(n) return (Short(n)) end

function RLP.Print(...) print("|cffff8000RLP:|r", ...) end

---------------------------------------------------------------- templates
-- { short (raid warning / screen), whisper }. Keep every template to ~6 words.
RLP.Templates = {
  MOVE    = { "MOVE {icon}{spot}", "{icon} MOVE to {spot}" },
  MOVEOUT = { "MOVE OUT NOW", "MOVE OUT NOW" },
  OUTLINE = { "MOVE OUT OF LINE", "MOVE OUT OF LINE" },
  RUNOUT  = { "{target} RUN OUT", "RUN OUT of raid" },
  STACK   = { "STACK on {target}", "STACK on {target}" },
  SPREAD  = { "SPREAD OUT", "SPREAD OUT" },
  STOP    = { "{target} STOP moving", "STOP MOVING {icon}" },
  DISPEL  = { "DISPEL {target}", "DISPEL {target} NOW" },
  DECURSE = { "DECURSE {target}", "DECURSE {target} NOW" },
  DEPOISON = { "DEPOISON {target}", "DEPOISON {target} NOW" },
  DEMAGIC = { "DEMAGIC {target}", "DEMAGIC {target} NOW" },
  PURGE   = { "PURGE NOW", "PURGE {target} NOW" },
  TAUNT   = { "TAUNT NOW", "TAUNT NOW" },
  KICK    = { "INTERRUPT {spell}", "YOU: INTERRUPT {spell}" },
  CD      = { "USE COOLDOWNS NOW", "USE COOLDOWNS NOW" },
  LOS     = { "LOS behind {spot}", "LOS behind {spot}" },
  JUMP    = { "JUMP NOW", "JUMP NOW" },
  DROP    = { "DROP IT NOW", "DROP IT NOW" },
  CLICK   = { "CLICK {spell}", "CLICK {spell} NOW" },
  SWAP    = { "SWAP TANKS NOW", "SWAP TANKS NOW" },
  BOMB    = { "{target} BOMB: RUN OUT", "{icon} Bomb: run to {spot}" },
  TRANQ   = { "TRANQ SHOT NOW", "TRANQ SHOT NOW" },
  FEAR    = { "FEAR: WARD / TREMOR NOW", "FEAR: WARD / TREMOR NOW" },
  KNOCK   = { "KNOCKBACK: PICK UP", "KNOCKBACK: PICK UP" },
  HEAL    = { "HEAL {target}", "HEAL {target} NOW" },
  NOHEAL  = { "DON'T HEAL {target}", "DON'T HEAL {target}" },
  REZ     = { "REZ THE SPIRIT", "REZ THE SPIRIT" },
  AOE     = { "AOE HEALS NOW", "AOE HEALS NOW" },
  BURN    = { "BURN IT DOWN", "BURN IT DOWN" },
  SHEEP   = { "SHEEP {target}", "SHEEP {target} NOW" },
  FREE    = { "FREE {target}", "FREE {target} NOW" },
  ICE     = { "HIDE BEHIND ICE BLOCK", "HIDE BEHIND ICE BLOCK" },
  PLUS    = { "STAND WITH PLUS", "You are +: STAND WITH PLUS" },
  MINUS   = { "STAND WITH MINUS", "You are -: STAND WITH MINUS" },
  CUSTOM  = { "", "" },
}
RLP.TemplateOrder = { "MOVE", "MOVEOUT", "OUTLINE", "RUNOUT", "STACK", "SPREAD", "STOP", "DISPEL", "DECURSE", "DEPOISON", "DEMAGIC",
  "PURGE", "TAUNT", "KICK", "CD", "LOS", "JUMP", "DROP", "CLICK", "SWAP", "BOMB", "TRANQ", "FEAR", "KNOCK", "HEAL", "NOHEAL",
  "REZ", "AOE", "BURN", "SHEEP", "FREE", "ICE", "PLUS", "MINUS", "CUSTOM" }

local TRAILING = { to = 1, behind = 1, on = 1, at = 1, ["in"] = 1, from = 1, with = 1 }

local function Clean(s)
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  while true do
    local head, last = s:match("^(.*)%s(%S+)$")
    if head and TRAILING[last:lower()] then s = head else break end
  end
  return s
end

-- spot value: "" | "icon:N" | "MARK" | name of a spot in db.spots
function RLP.SpotParts(spot)
  if not spot or spot == "" then return nil, "" end
  local n = spot:match("^icon:(%d)$")
  if n then n = tonumber(n) return n, RLP.ICONS[n] end
  if spot == "MARK" then return nil, "marked target" end
  local db = RLP.db
  return db and db.spots[spot], spot
end

-- ctx: spot, spell, target, sec, player, class, screen
function RLP.Expand(text, ctx)
  ctx = ctx or {}
  local icon, label = RLP.SpotParts(ctx.spot)
  local iconText = ""
  if icon then
    iconText = ctx.screen and ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon .. ":16|t") or ("{rt" .. icon .. "}")
  end
  local vals = { icon = iconText, spot = label or "", spell = ctx.spell or "", target = ctx.target or "",
    sec = ctx.sec or "", player = ctx.player or "", class = ctx.class or "" }
  local s = text:gsub("{(%a+)}", function(k) return vals[k] end)
  return Clean(s)
end

function RLP.WordCount(s)
  local n = 0
  for _ in s:gmatch("%S+") do n = n + 1 end
  return n
end

---------------------------------------------------------------- mechanics normalisation + validation
local EVENTS = { SPELL_CAST_START = 1, SPELL_CAST_SUCCESS = 1, SPELL_AURA_APPLIED = 1, SPELL_AURA_REFRESH = 1,
  SPELL_AURA_REMOVED = 1, SPELL_DAMAGE = 1, SPELL_PERIODIC_DAMAGE = 1, SPELL_HEAL = 1, SPELL_DISPEL = 1,
  SPELL_INTERRUPT = 1, UNIT_DIED = 1 }
RLP.problems = {}

local function Problem(msg) table.insert(RLP.problems, msg) end

function RLP.NormalizeMech(boss, m)
  m.boss = boss
  m.name = m.name or m.spell or m.pat or (m.hp and (m.hp .. "% health")) or (m.sec and (m.sec .. "s timer")) or "?"
  m.id = boss.name .. "|" .. m.name
  if m.sig == nil then m.sig = true end
  if not m.who then m.who = (m.kind == "CLEU" and m.ev == "SPELL_AURA_APPLIED") and "AFFECTED" or "EVERYONE" end
  if not m.act then
    if m.who == "EVERYONE" then m.act = "RW"
    elseif m.who == "AFFECTED" and m.crit then m.act = "WHISPER_RW"
    else m.act = "WHISPER" end
  end
  if m.t == "CUSTOM" and not m.text then m.text = m.name end
end

function RLP.ValidateMech(boss, m)
  local where = boss.name .. " / " .. tostring(m.name) .. ": "
  if not RLP.Templates[m.t or ""] then Problem(where .. "unknown template " .. tostring(m.t)) end
  local tpl = RLP.Templates[m.t or ""]
  if tpl then
    for i = 1, 2 do
      local txt = (m.t == "CUSTOM") and (m.text or "") or tpl[i]
      if RLP.WordCount(txt) > 6 then Problem(where .. "template longer than 6 words") end
    end
  end
  if m.kind == "CLEU" then
    if not EVENTS[m.ev or ""] then Problem(where .. "unknown event " .. tostring(m.ev)) end
    if not m.spell and not m.sid then Problem(where .. "no spell") end
  elseif m.kind == "YELL" or m.kind == "EMOTE" then
    if not m.pat or m.pat == "" then Problem(where .. "no text") end
  elseif m.kind == "HP" then
    if not tonumber(m.hp) then Problem(where .. "bad health %") end
  elseif m.kind == "TIMER" then
    if not tonumber(m.sec) then Problem(where .. "bad seconds") end
  else
    Problem(where .. "unknown kind " .. tostring(m.kind))
  end
end

RLP.mobIndex, RLP.nameIndex = {}, {}
for _, raid in ipairs(RLP.Raids) do
  for _, boss in ipairs(raid.bosses) do
    boss.raid = raid.name
    boss.mech = boss.mech or {}
    if not boss.mobs or #boss.mobs == 0 then Problem(boss.name .. ": no mobs") end
    for _, m in ipairs(boss.mobs or {}) do RLP.mobIndex[m] = boss end
    RLP.nameIndex[boss.name:lower()] = boss
    for _, m in ipairs(boss.mech) do
      RLP.NormalizeMech(boss, m)
      RLP.ValidateMech(boss, m)
    end
  end
end

-- built-in mechanics + any the leader mapped with /rlp map
function RLP.Mechs(boss)
  local list = {}
  for _, m in ipairs(boss.mech) do list[#list + 1] = m end
  local c = RLP.db and RLP.db.custom[boss.name]
  if c then
    for _, m in ipairs(c) do
      if not m.id then RLP.NormalizeMech(boss, m) end
      list[#list + 1] = m
    end
  end
  return list
end

function RLP.AllBosses()
  local t = {}
  for _, raid in ipairs(RLP.Raids) do for _, b in ipairs(raid.bosses) do t[#t + 1] = b end end
  return t
end

function RLP.FindBoss(arg)
  if not arg or arg == "" then return nil end
  local l = arg:lower()
  if RLP.nameIndex[l] then return RLP.nameIndex[l] end
  for k, b in pairs(RLP.nameIndex) do if k:find(l, 1, true) then return b end end
end

---------------------------------------------------------------- roster
local roster, rosterAt

function RLP.Roster(force)
  local now = GetTime()
  if roster and not force and now - rosterAt < 1 then return roster end
  local t = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, rank, sub, _, _, file, _, online, dead, role = GetRaidRosterInfo(i)
      if name then t[#t + 1] = { name = Short(name), unit = "raid" .. i, class = file, group = sub, online = online, dead = dead, role = role, rank = rank } end
    end
  else
    local units = { "player" }
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    for _, u in ipairs(units) do
      if UnitExists(u) then
        local _, file = UnitClass(u)
        t[#t + 1] = { name = Short(UnitName(u)), unit = u, class = file, group = 1, online = UnitIsConnected(u), dead = UnitIsDeadOrGhost(u) }
      end
    end
  end
  roster, rosterAt = t, now
  return t
end

function RLP.Entry(name)
  for _, e in ipairs(RLP.Roster()) do if e.name == name then return e end end
end

function RLP.Alive(name)
  local e = RLP.Entry(name)
  if not e then return false end
  if UnitIsConnected and not UnitIsConnected(e.unit) then return false end
  return not UnitIsDeadOrGhost(e.unit)
end

function RLP.ClassColor(class)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
  return "|cffffffff"
end

---------------------------------------------------------------- serialisation (safe: no loadstring)
local function ser(v, depth)
  local t = type(v)
  if t == "number" then return tostring(v)
  elseif t == "boolean" then return v and "T" or "F"
  elseif t == "string" then return '"' .. (v:gsub('[\\"]', "\\%0")) .. '"'
  elseif t == "table" and depth < 8 then
    local parts = {}
    for k, val in pairs(v) do
      if type(k) == "string" or type(k) == "number" then
        parts[#parts + 1] = ser(k, depth + 1) .. "=" .. ser(val, depth + 1)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "F"
end

function RLP.Serialize(v) return "RLP1:" .. ser(v, 0) end

function RLP.Deserialize(str)
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  if str:sub(1, 5) ~= "RLP1:" then return nil, "not an RLP export string" end
  local s, pos = str:sub(6), 1
  local value
  local function skip() pos = s:find("%S", pos) or #s + 1 end
  function value(depth)
    if depth > 8 then error("too deep") end
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local t = {}
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        local k = value(depth + 1)
        skip()
        if s:sub(pos, pos) ~= "=" then error("expected =") end
        pos = pos + 1
        t[k] = value(depth + 1)
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then error("expected , or }") end
      end
    elseif c == '"' then
      local out = {}
      pos = pos + 1
      while true do
        local ch = s:sub(pos, pos)
        if ch == "" then error("unterminated string") end
        if ch == "\\" then out[#out + 1] = s:sub(pos + 1, pos + 1) pos = pos + 2
        elseif ch == '"' then pos = pos + 1 break
        else out[#out + 1] = ch pos = pos + 1 end
      end
      return table.concat(out)
    elseif c == "T" then pos = pos + 1 return true
    elseif c == "F" then pos = pos + 1 return false
    else
      local num = s:match("^-?%d+%.?%d*", pos)
      if not num then error("bad value at " .. pos) end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local ok, res = pcall(value, 0)
  if not ok then return nil, tostring(res) end
  return res
end

function RLP.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, val in pairs(v) do t[k] = RLP.DeepCopy(val) end
  return t
end
