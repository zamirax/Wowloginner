-- Encounter data (English client). Edit only this file to add or fix bosses.
--
-- boss: name, mobs (combat-log names), final (mob whose death ends the fight; default all mobs),
--       tips (fallback explainer lines), avoid (spells that count as avoidable damage), mech (mechanics)
--
-- mechanic constructors (all take  trigger, label/template, options):
--   A(event, spell, tmpl, opt)   combat log: SPELL_CAST_START / SPELL_CAST_SUCCESS / SPELL_AURA_APPLIED ...
--   Y(text, name, tmpl, opt)     boss yell containing text
--   E(text, name, tmpl, opt)     boss emote containing text
--   H(pct, name, tmpl, opt)      boss health <= pct
--   T(sec, name, tmpl, opt)      seconds after pull (opt.every = repeat interval)
-- options
--   who    AFFECTED | EVERYONE | PLAYERS | ROTATION | HEALERS | TANKS | ROLE:x | CLASS:A,B | GROUP:n
--          alternatives separated by | are tried in order (first non-empty wins)
--   act    WHISPER | RW | RAID | SCREEN | WHISPER_RW | NONE      tmpl  template id (Util.lua)
--   text   default text when tmpl = CUSTOM   spot  default spot   sid  spell id (preferred over name)
--   sig    shown in the explainer (default true)   crit  critical priority   off  disabled by default
--   phase  only fires in this phase   setPhase  entering this trigger starts that phase
--   cap    max firings per fight   cd  seconds between firings   unsure  name not verified in game
local _, RLP = ...

local function K(kind) return function(a, b, t, o)
  o = o or {}
  o.kind, o.t = kind, t
  if kind == "CLEU" then o.ev, o.spell = a, b
  elseif kind == "YELL" or kind == "EMOTE" then o.pat, o.name = a:lower(), b
  elseif kind == "HP" then o.hp, o.name = a, b
  else o.sec, o.name = a, b end
  return o
end end
local A_ = K("CLEU")
local function A(ev, spell, t, o) return A_(ev, spell, t, o) end
local Y_, E_, H_, T_ = K("YELL"), K("EMOTE"), K("HP"), K("TIMER")
local function Y(p, n, t, o) return Y_(p, n, t, o) end
local function E(p, n, t, o) return E_(p, n, t, o) end
local function H(p, n, t, o) return H_(p, n, t, o) end
local function T(s, n, t, o) return T_(s, n, t, o) end

local APP, CAST, START = "SPELL_AURA_APPLIED", "SPELL_CAST_SUCCESS", "SPELL_CAST_START"
local TRANQ = "ROLE:Tranq|CLASS:HUNTER"
local DISPEL = "ROLE:Dispel|HEALERS"
local DECURSE = "ROLE:Decurse|CLASS:MAGE,DRUID"

RLP.Raids = {
  { name = "Onyxia's Lair", bosses = {
    { name = "Onyxia", mobs = { "Onyxia" },
      tips = { "P1: tank at the wall, all others at her sides, never in front.", "P2: spread, kill whelps, leave the Deep Breath line.", "P3: Fear Ward / Tremor, melee behind." },
      avoid = { "Deep Breath", "Tail Sweep", "Flame Breath" },
      mech = {
        E("deep breath", "Deep Breath", "OUTLINE", { who = "EVERYONE", act = "RW", crit = true, unsure = true }),
        Y("meaningless exertion", "Phase 2", "SPREAD", { who = "EVERYONE", act = "RW", setPhase = 2, sig = false, unsure = true }),
        Y("another lesson", "Phase 3", "FEAR", { who = "EVERYONE", act = "RW", setPhase = 3, sig = false, unsure = true }),
        A(START, "Bellowing Roar", "FEAR", { who = "EVERYONE", act = "RW", crit = true }),
      } },
  } },

  { name = "Molten Core", bosses = {
    { name = "Lucifron", mobs = { "Lucifron" },
      tips = { "Decurse Lucifron's Curse, dispel Impending Doom. Tank the adds apart." },
      mech = { A(APP, "Impending Doom", "DISPEL", { who = DISPEL }) } },
    { name = "Magmadar", mobs = { "Magmadar" },
      tips = { "Fear Ward / Tremor for Panic. Tranq every Frenzy. Never stand in fire." },
      avoid = { "Lava Bomb" },
      mech = {
        A(START, "Panic", "FEAR", { who = "EVERYONE", act = "RW", crit = true }),
        A(APP, "Frenzy", "TRANQ", { who = TRANQ, cd = 8 }),
      } },
    { name = "Gehennas", mobs = { "Gehennas" },
      tips = { "Decurse the curse. Move out of Rain of Fire. Tank the adds away." },
      avoid = { "Rain of Fire" },
      mech = { A(APP, "Rain of Fire", "MOVEOUT", { who = "AFFECTED", cd = 6 }) } },
    { name = "Garr", mobs = { "Garr" },
      tips = { "Tank Firesworn far from Garr and the raid, never kill them near casters." },
      avoid = { "Eruption" },
      mech = { A(APP, "Magma Shackles", "DISPEL", { who = DISPEL }) } },
    { name = "Shazzrah", mobs = { "Shazzrah" },
      tips = { "He blinks and Arcane Explosions. Casters stay out of melee, purge Deaden Magic." },
      mech = {
        A(CAST, "Blink", "TAUNT", { who = "ROLE:MT|TANKS", act = "WHISPER" }),
        A(APP, "Deaden Magic", "PURGE", { who = "ROLE:Purge|CLASS:PRIEST,SHAMAN", cd = 6 }),
      } },
    { name = "Baron Geddon", mobs = { "Baron Geddon" },
      tips = { "Living Bomb target runs out. Everyone moves out on Inferno." },
      avoid = { "Inferno" },
      mech = {
        A(APP, "Living Bomb", "BOMB", { who = "AFFECTED", act = "WHISPER_RW", crit = true, spot = "Yellow" }),
        A(START, "Inferno", "MOVEOUT", { who = "EVERYONE", act = "RW", crit = true }),
      } },
    { name = "Sulfuron Harbinger", mobs = { "Sulfuron Harbinger" },
      tips = { "Interrupt Dark Mending. Kill healers first, boss last." },
      mech = { A(START, "Dark Mending", "KICK", { who = "ROTATION", act = "WHISPER_RW", crit = true }) } },
    { name = "Golemagg the Incinerator", mobs = { "Golemagg the Incinerator" },
      tips = { "Two tanks; boss tank stays back. Keep range from Pyroclast Barrage." },
      avoid = { "Pyroclast Barrage" }, mech = {} },
    { name = "Majordomo Executus", mobs = { "Majordomo Executus" },
      tips = { "Pull adds in groups. No casters on Magic Reflection, no melee on Damage Shield." },
      mech = {
        A(APP, "Magic Reflection", "CUSTOM", { who = "EVERYONE", act = "RW", text = "CASTERS STOP: REFLECT" }),
        A(APP, "Damage Shield", "CUSTOM", { who = "EVERYONE", act = "RW", text = "MELEE STOP: SHIELD" }),
      } },
    { name = "Ragnaros", mobs = { "Ragnaros" },
      tips = { "Tank mid, melee close. Wrath knocks the tank back. Kill Sons of Flame." },
      avoid = { "Lava Burst", "Elemental Fire" },
      mech = { A(START, "Wrath of Ragnaros", "KNOCK", { who = "ROLE:MT|TANKS", act = "WHISPER" }) } },
  } },

  { name = "Blackwing Lair", bosses = {
    { name = "Razorgore the Untamed", mobs = { "Razorgore the Untamed" },
      tips = { "MC Razorgore with the orb, destroy eggs. Kill the adds." },
      avoid = { "Conflagration" }, mech = {} },
    { name = "Vaelastrasz the Corrupt", mobs = { "Vaelastrasz the Corrupt" },
      tips = { "Burning Adrenaline player (not tank) runs out and uses cooldowns." },
      mech = { A(APP, "Burning Adrenaline", "BOMB", { who = "AFFECTED", act = "WHISPER_RW", crit = true, spot = "Yellow" }) } },
    { name = "Broodlord Lashlayer", mobs = { "Broodlord Lashlayer" },
      tips = { "Tank with back to wall, melee behind. Blast Wave hits melee." },
      avoid = { "Blast Wave" }, mech = {} },
    { name = "Firemaw", mobs = { "Firemaw" },
      tips = { "Face him away. Shadow Flame is a cone: stay behind. Swap on Flame Buffet." },
      avoid = { "Shadow Flame" }, mech = {} },
    { name = "Ebonroc", mobs = { "Ebonroc" },
      tips = { "Face him away. Swap tank on Shadow of Ebonroc. Stay behind." },
      avoid = { "Shadow Flame" }, mech = {} },
    { name = "Flamegor", mobs = { "Flamegor" },
      tips = { "Face him away. Tranq Frenzy. Stay behind the cone." },
      avoid = { "Shadow Flame" },
      mech = { A(APP, "Frenzy", "TRANQ", { who = TRANQ, cd = 8 }) } },
    { name = "Chromaggus", mobs = { "Chromaggus" },
      tips = { "LOS every breath behind a pillar. Tranq Frenzy. Cure Brood Afflictions." },
      avoid = { "Incinerate", "Time Lapse", "Corrosive Acid", "Ignite Flesh", "Frost Burn" },
      mech = {
        A(START, "Incinerate", "LOS", { who = "EVERYONE", act = "RW", crit = true, name = "Breath: Incinerate" }),
        A(START, "Time Lapse", "LOS", { who = "EVERYONE", act = "RW", crit = true, name = "Breath: Time Lapse" }),
        A(START, "Corrosive Acid", "LOS", { who = "EVERYONE", act = "RW", crit = true, name = "Breath: Corrosive Acid" }),
        A(START, "Ignite Flesh", "LOS", { who = "EVERYONE", act = "RW", crit = true, name = "Breath: Ignite Flesh" }),
        A(START, "Frost Burn", "LOS", { who = "EVERYONE", act = "RW", crit = true, name = "Breath: Frost Burn" }),
        A(APP, "Frenzy", "TRANQ", { who = TRANQ, cd = 8 }),
      } },
    { name = "Nefarian", mobs = { "Nefarian" },
      tips = { "P1 kill drakonids. P2 stay out of Shadow Flame. Fear Ward / Tremor. Obey class calls." },
      avoid = { "Shadow Flame" },
      mech = {
        A(START, "Bellowing Roar", "FEAR", { who = "EVERYONE", act = "RW", crit = true }),
        H(20, "20% burn", "BURN", { who = "EVERYONE", act = "RW", phase = nil }),
      } },
  } },

  { name = "Zul'Gurub", bosses = {
    { name = "High Priestess Jeklik", mobs = { "High Priestess Jeklik" },
      tips = { "Kill bat riders, interrupt Great Heal, stay out of bomb fire." }, avoid = { "Bomb" }, mech = {} },
    { name = "High Priest Venoxis", mobs = { "High Priest Venoxis" },
      tips = { "Spread, avoid poison clouds. Snake phase: avoid poison." }, avoid = { "Poison Cloud" }, mech = {} },
    { name = "High Priestess Mar'li", mobs = { "High Priestess Mar'li" },
      tips = { "Kill spiders quickly, interrupt drain life." }, mech = {} },
    { name = "High Priest Thekal", mobs = { "High Priest Thekal", "Zealot Lor'Khan", "Zealot Zath" }, final = "High Priest Thekal",
      tips = { "Kill all three at about the same time." }, mech = {} },
    { name = "High Priestess Arlokk", mobs = { "High Priestess Arlokk" },
      tips = { "Marked player is hunted by panthers - kill them." }, mech = {} },
    { name = "Bloodlord Mandokir", mobs = { "Bloodlord Mandokir" },
      tips = { "DO NOT MOVE when Threatening Gaze hits you. Rez the spirit." },
      mech = {
        A(APP, "Threatening Gaze", "STOP", { who = "AFFECTED", act = "WHISPER_RW", crit = true }),
      } },
    { name = "Jin'do the Hexxer", mobs = { "Jin'do the Hexxer" },
      tips = { "Kill Brain Wash and Healing Wards. Decurse Hex." },
      mech = { A(APP, "Hex", "DECURSE", { who = DECURSE }) } },
    { name = "Hakkar", mobs = { "Hakkar" },
      tips = { "Kill priests to stop Mind Control. Dispel and sheep controlled players." },
      mech = { A(APP, "Mind Control", "SHEEP", { who = "ROLE:CC|CLASS:MAGE", crit = true }) } },
  } },

  { name = "Ruins of Ahn'Qiraj", bosses = {
    { name = "Kurinnaxx", mobs = { "Kurinnaxx" }, tips = { "Tank and spank. Avoid Sand Traps." }, avoid = { "Sand Trap" }, mech = {} },
    { name = "General Rajaxx", mobs = { "General Rajaxx" }, tips = { "Clear the waves, then kill the General." }, mech = {} },
    { name = "Moam", mobs = { "Moam" }, tips = { "Kill Mana Fiends, burn at full mana." }, mech = {} },
    { name = "Buru the Gorger", mobs = { "Buru the Gorger" }, tips = { "Run from the egg while he chases you. Burn at 20%." }, mech = {} },
    { name = "Ayamiss the Hunter", mobs = { "Ayamiss the Hunter" }, tips = { "P1 kill adds in the air. P2 tank on the ground." }, avoid = { "Stinger Spray" }, mech = {} },
    { name = "Ossirian the Unscarred", mobs = { "Ossirian the Unscarred" }, tips = { "Use crystals to weaken him; he enrages between them." }, mech = {} },
  } },

  { name = "Temple of Ahn'Qiraj", bosses = {
    { name = "The Prophet Skeram", mobs = { "The Prophet Skeram" },
      tips = { "Kill clones, interrupt Arcane Explosion, sheep mind controlled players." }, avoid = { "Arcane Explosion" },
      mech = { A(APP, "True Fulfillment", "SHEEP", { who = "ROLE:CC|CLASS:MAGE", crit = true }) } },
    { name = "The Bug Trio", mobs = { "Lord Kri", "Princess Yauj", "Vem" }, final = "Vem",
      tips = { "Kill Yauj, then Vem, then Kri. Stay out of poison." }, avoid = { "Toxic Vapors", "Poison Cloud" }, mech = {} },
    { name = "Battleguard Sartura", mobs = { "Battleguard Sartura" },
      tips = { "Melee leave during Whirlwind. Kill her guards." }, avoid = { "Whirlwind" }, mech = {} },
    { name = "Fankriss the Unyielding", mobs = { "Fankriss the Unyielding" }, tips = { "Kill worm spawns. Swap tanks on Mortal Wound." }, mech = {} },
    { name = "Viscidus", mobs = { "Viscidus" }, tips = { "Freeze with frost, shatter with melee." }, avoid = { "Poison Bolt Volley" }, mech = {} },
    { name = "Princess Huhuran", mobs = { "Princess Huhuran" },
      tips = { "Nature resist. Tranq Frenzy. Burn her at 30%." }, avoid = { "Noxious Poison" },
      mech = {
        A(APP, "Frenzy", "TRANQ", { who = TRANQ, cd = 8 }),
        A(APP, "Berserk", "BURN", { who = "EVERYONE", act = "RW", crit = true }),
      } },
    { name = "Twin Emperors", mobs = { "Emperor Vek'lor", "Emperor Vek'nilash" }, final = "Emperor Vek'lor",
      tips = { "Do not let them swap sides. Kill both together." }, avoid = { "Arcane Burst", "Blizzard" }, mech = {} },
    { name = "Ouro", mobs = { "Ouro" }, tips = { "Leave Sand Blast and Ground Rupture. Burn at 20%." }, avoid = { "Sand Blast", "Ground Rupture" }, mech = {} },
    { name = "C'Thun", mobs = { "Eye of C'Thun", "C'Thun" }, final = "C'Thun",
      tips = { "P1 spread, dodge Dark Glare. P2 kill claw tentacles." }, avoid = { "Dark Glare", "Eye Beam" }, mech = {} },
  } },

  { name = "Naxxramas", bosses = {
    { name = "Anub'Rekhan", mobs = { "Anub'Rekhan" }, tips = { "Kite adds. Impale hits in a line." }, avoid = { "Impale" }, mech = {} },
    { name = "Grand Widow Faerlina", mobs = { "Grand Widow Faerlina" }, tips = { "Kill adds. Stay out of Rain of Fire." }, avoid = { "Rain of Fire" },
      mech = { A(APP, "Rain of Fire", "MOVEOUT", { who = "AFFECTED", cd = 6 }) } },
    { name = "Maexxna", mobs = { "Maexxna" }, tips = { "Free webbed players. Heal through Web Spray." },
      mech = { A(START, "Web Spray", "AOE", { who = "ROLE:Healer|HEALERS", act = "WHISPER" }) } },
    { name = "Noth the Plaguebringer", mobs = { "Noth the Plaguebringer" }, tips = { "Decurse the curse, kill adds." },
      mech = { A(APP, "Curse of the Plaguebringer", "CUSTOM", { who = DECURSE, text = "DECURSE the raid", cd = 8 }) } },
    { name = "Heigan the Unclean", mobs = { "Heigan the Unclean" }, tips = { "Dance across the safe zones. P2 stay on the platform." },
      avoid = { "Eruption", "Plague Cloud" }, mech = {} },
    { name = "Loatheb", mobs = { "Loatheb" }, tips = { "Heal only in the Corrupted Mind window. Doom every 30s." },
      mech = { A(CAST, "Inevitable Doom", "CUSTOM", { who = "ROLE:Healer|HEALERS", act = "WHISPER", text = "DOOM: HEAL NOW", cd = 10 }) } },
    { name = "Instructor Razuvious", mobs = { "Instructor Razuvious" }, tips = { "Priests MC the Understudies and taunt." },
      avoid = { "Disrupting Shout" }, mech = {} },
    { name = "Gothik the Harvester", mobs = { "Gothik the Harvester" }, tips = { "Two sides; kill casters first." }, mech = {} },
    { name = "The Four Horsemen", mobs = { "Thane Korth'azz", "Lady Blaumeux", "Highlord Mograine", "Sir Zeliek" },
      tips = { "Rotate tanks on Mark stacks. Kill Lady, Thane, Zeliek, Mograine." }, avoid = { "Meteor", "Holy Wrath", "Shadow Bolt Volley" }, mech = {} },
    { name = "Patchwerk", mobs = { "Patchwerk" }, tips = { "Heal the off-tank group through Hateful Strike." }, avoid = { "Hateful Strike" }, mech = {} },
    { name = "Grobbulus", mobs = { "Grobbulus" }, tips = { "Injection targets run out. Avoid clouds, keep boss moving." },
      avoid = { "Poison Cloud", "Slime Spray" },
      mech = {
        A(APP, "Mutating Injection", "BOMB", { who = "AFFECTED", act = "WHISPER_RW", crit = true, spot = "Yellow" }),
        A(APP, "Mutating Injection", "DISPEL", { who = DISPEL, name = "Injection dispel", sig = false, off = true, unsure = true }),
      } },
    { name = "Gluth", mobs = { "Gluth" }, tips = { "Kite Zombie Chow. Fear Ward / Tremor for the roar." },
      mech = { A(START, "Terrifying Roar", "FEAR", { who = "EVERYONE", act = "RW", crit = true }) } },
    { name = "Thaddius", mobs = { "Thaddius", "Feugen", "Stalagg" }, final = "Thaddius",
      tips = { "Kill Feugen and Stalagg together. Stand with your own charge." },
      mech = {
        A(APP, "Positive Charge", "PLUS", { who = "AFFECTED", act = "WHISPER", cap = 80, cd = 20 }),
        A(APP, "Negative Charge", "MINUS", { who = "AFFECTED", act = "WHISPER", cap = 80, cd = 20 }),
        A(START, "Polarity Shift", "CUSTOM", { who = "EVERYONE", act = "RW", text = "POLARITY: CHECK CHARGE" }),
      } },
    { name = "Sapphiron", mobs = { "Sapphiron" }, tips = { "Hide behind ice blocks. Leave Chill and Blizzard." },
      avoid = { "Chill", "Frost Breath", "Tail Sweep", "Blizzard" },
      mech = {
        A(START, "Frost Breath", "ICE", { who = "EVERYONE", act = "RW", crit = true }),
        A(APP, "Icebolt", "CUSTOM", { who = "AFFECTED", act = "WHISPER", text = "ICEBOLT: STAND IN SAFE SPOT", cd = 8 }),
      } },
    { name = "Kel'Thuzad", mobs = { "Kel'Thuzad" }, tips = { "Avoid Shadow Fissures. Mana users run out on Detonate Mana." },
      avoid = { "Shadow Fissure", "Frost Blast" },
      mech = {
        A(APP, "Detonate Mana", "RUNOUT", { who = "AFFECTED", act = "WHISPER_RW", crit = true }),
        A(APP, "Detonate Mana", "NOHEAL", { who = "ROLE:Healer|HEALERS", act = "WHISPER", name = "Detonate: no heal", sig = false }),
        A(APP, "Chains of Kel'Thuzad", "SHEEP", { who = "ROLE:CC|CLASS:MAGE", crit = true }),
      } },
  } },
}
