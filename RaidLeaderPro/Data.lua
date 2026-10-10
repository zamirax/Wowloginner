-- Encounter data. Spell/mob names are matched against the combat log, so they must be the
-- English (enUS) client names. To add or fix a boss, edit only this file.
--
-- boss fields
--   name   display name            mobs   combat-log names that identify the fight
--   final  (optional) mob whose death ends the fight; default = every mob in `mobs` must die
--   tips   lines posted to raid chat by /rlp strat
--   avoid  spell names that damage players who should have moved (counted per player)
--   alerts { ev, spell, msg, [whisper], [player], [raid] }
--            ev       combat log event (SPELL_CAST_START, SPELL_AURA_APPLIED, SPELL_CAST_SUCCESS)
--            msg      shown on your screen; %s = affected player. Also sent to raid chat if raid=true
--            whisper  sent to the affected player (needs player=true)
--            player   only fire when the target is a member of your group
local _, RLP = ...

local function A(ev, spell, msg, opt)
  local a = { ev = ev, spell = spell, msg = msg }
  if opt then for k, v in pairs(opt) do a[k] = v end end
  return a
end

RLP.Raids = {
  { name = "Onyxia's Lair", bosses = {
    { name = "Onyxia", mobs = { "Onyxia" },
      tips = {
        "P1: tank her facing the wall, everyone else stay at her sides/behind - never in front.",
        "P2: she flies - spread out, kill whelps, avoid fireballs, run out of the Deep Breath line.",
        "P3: Fear Ward / Tremor Totem for Bellowing Roar. Melee stay behind, away from the tail.",
      },
      avoid = { "Deep Breath", "Tail Sweep", "Flame Breath" },
      alerts = {
        A("SPELL_CAST_START", "Deep Breath", "DEEP BREATH - MOVE OUT OF THE LINE!", { raid = true }),
        A("SPELL_CAST_START", "Bellowing Roar", "FEAR! Fear Ward / Tremor now", { raid = true }),
      } },
  } },

  { name = "Molten Core", bosses = {
    { name = "Lucifron", mobs = { "Lucifron" },
      tips = { "Decurse Lucifron's Curse, dispel Impending Doom. Kill the two adds fast / tank them apart." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Impending Doom", "Dispel Impending Doom on %s", { player = true }),
      } },
    { name = "Magmadar", mobs = { "Magmadar" },
      tips = { "Fear Ward / Tremor Totem for Panic. Hunters Tranq Shot every Frenzy. Never stand in the fire." },
      avoid = { "Lava Bomb" },
      alerts = {
        A("SPELL_CAST_START", "Panic", "FEAR! Fear Ward / Tremor now", { raid = true }),
        A("SPELL_AURA_APPLIED", "Frenzy", "FRENZY - TRANQ SHOT!", { raid = true }),
      } },
    { name = "Gehennas", mobs = { "Gehennas" },
      tips = { "Decurse Gehennas' Curse. Do NOT stand in Rain of Fire. Kill adds, tank boss away from them." },
      avoid = { "Rain of Fire" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Rain of Fire", "MOVE out of Rain of Fire, %s!", { player = true, whisper = "Rain of Fire on you - MOVE OUT!" }),
      } },
    { name = "Garr", mobs = { "Garr" },
      tips = { "Tank Firesworn adds away from raid and AWAY from Garr. Kill adds only when they are far from casters." },
      avoid = { "Eruption" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Magma Shackles", "Dispel Magma Shackles on %s", { player = true }),
      } },
    { name = "Shazzrah", mobs = { "Shazzrah" },
      tips = { "He blinks and Arcane Explosions. Casters stay out of melee range, purge Deaden Magic, no casters cluster." },
      alerts = {
        A("SPELL_CAST_SUCCESS", "Blink", "BLINK - tank re-pick, casters spread!", {}),
        A("SPELL_AURA_APPLIED", "Deaden Magic", "PURGE Deaden Magic!", { raid = true }),
      } },
    { name = "Baron Geddon", mobs = { "Baron Geddon" },
      tips = { "Living Bomb target RUNS OUT of the raid at once. When he casts Inferno everyone MOVES OUT (40yd)." },
      avoid = { "Inferno" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Living Bomb", "LIVING BOMB on %s - RUN OUT!", { player = true, raid = true, whisper = "YOU ARE THE BOMB - RUN AWAY FROM THE RAID NOW!" }),
        A("SPELL_CAST_START", "Inferno", "INFERNO - EVERYONE MOVE OUT!", { raid = true }),
      } },
    { name = "Sulfuron Harbinger", mobs = { "Sulfuron Harbinger" },
      tips = { "Interrupt Dark Mending on healers. Kill healers first, boss last. Kick Shadow Word: Pain adds." },
      alerts = {
        A("SPELL_CAST_START", "Dark Mending", "INTERRUPT Dark Mending!", { raid = true }),
      } },
    { name = "Golemagg the Incinerator", mobs = { "Golemagg the Incinerator" },
      tips = { "Two tanks, boss tank stays back. Keep distance from his dogs' Pyroclast Barrage. Heal the boss tank through Magma Splash." },
      avoid = { "Pyroclast Barrage" } },
    { name = "Majordomo Executus", mobs = { "Majordomo Executus" },
      tips = { "Pull adds into separate groups; no melee on Magic Reflection and no casters on Damage Shield - watch the buff." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Magic Reflection", "MAGIC REFLECTION - casters STOP, melee only!", { raid = true }),
        A("SPELL_AURA_APPLIED", "Damage Shield", "DAMAGE SHIELD - melee STOP, casters only!", { raid = true }),
      } },
    { name = "Ragnaros", mobs = { "Ragnaros" },
      tips = { "Tank in the middle, melee stay close. Wrath knocks the tank back, pick him up. On submerge kill Sons of Flame fast.",
               "Do NOT stand in the lava. Watch out for knockback near the water." },
      avoid = { "Lava Burst", "Elemental Fire" },
      alerts = {
        A("SPELL_CAST_START", "Wrath of Ragnaros", "KNOCKBACK - tank pick up!", {}),
      } },
  } },

  { name = "Blackwing Lair", bosses = {
    { name = "Razorgore the Untamed", mobs = { "Razorgore the Untamed" },
      tips = { "Mind Control Razorgore with the Orb and destroy the eggs. Kill Blackwing Mage/Legionnaire adds. Stop eggs only on call." },
      avoid = { "Conflagration" } },
    { name = "Vaelastrasz the Corrupt", mobs = { "Vaelastrasz the Corrupt" },
      tips = { "Burning Adrenaline player (not the tank) runs out of the raid and uses cooldowns. Healers keep the tank up." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Burning Adrenaline", "BURNING ADRENALINE on %s - RUN OUT!", { player = true, raid = true, whisper = "Burning Adrenaline - MOVE AWAY FROM THE RAID!" }),
      } },
    { name = "Broodlord Lashlayer", mobs = { "Broodlord Lashlayer" },
      tips = { "Tank with back to wall. Melee stand BEHIND the boss. Blast Wave hits everyone in melee - keep the tank up." },
      avoid = { "Blast Wave" } },
    { name = "Firemaw", mobs = { "Firemaw" },
      tips = { "Face him away from the raid. Shadow Flame is a cone: everybody stays behind him. Tank swaps on Flame Buffet stacks." },
      avoid = { "Shadow Flame" } },
    { name = "Ebonroc", mobs = { "Ebonroc" },
      tips = { "Face away from the raid. Tank swap on Shadow of Ebonroc (heal accordingly). Shadow Flame = stay behind him." },
      avoid = { "Shadow Flame" } },
    { name = "Flamegor", mobs = { "Flamegor" },
      tips = { "Face away from the raid. Hunters Tranq the Frenzy. Shadow Flame is a cone - stay behind." },
      avoid = { "Shadow Flame" },
      alerts = { A("SPELL_AURA_APPLIED", "Frenzy", "FRENZY - TRANQ SHOT!", { raid = true }) } },
    { name = "Chromaggus", mobs = { "Chromaggus" },
      tips = { "LOS every breath behind a pillar when you see the cast. Tranq Frenzy. Cure Brood Afflictions (decurse/dispel) or kill/avoid Time Lapse." },
      avoid = { "Incinerate", "Time Lapse", "Corrosive Acid", "Ignite Flesh", "Frost Burn" },
      alerts = {
        A("SPELL_CAST_START", "Incinerate", "BREATH: INCINERATE - LOS NOW!", { raid = true }),
        A("SPELL_CAST_START", "Time Lapse", "BREATH: TIME LAPSE - LOS NOW!", { raid = true }),
        A("SPELL_CAST_START", "Corrosive Acid", "BREATH: CORROSIVE ACID - LOS NOW!", { raid = true }),
        A("SPELL_CAST_START", "Ignite Flesh", "BREATH: IGNITE FLESH - LOS NOW!", { raid = true }),
        A("SPELL_CAST_START", "Frost Burn", "BREATH: FROST BURN - LOS NOW!", { raid = true }),
        A("SPELL_AURA_APPLIED", "Frenzy", "FRENZY - TRANQ SHOT!", { raid = true }),
      } },
    { name = "Nefarian", mobs = { "Nefarian" },
      tips = { "P1: kill drakonids, keep them off casters. P2: stay out of Shadow Flame cone. Fear Ward / Tremor for Bellowing Roar.",
               "Respond to the class call at once (shaman totems, druid stay stationary, etc.)." },
      avoid = { "Shadow Flame" },
      alerts = {
        A("SPELL_CAST_START", "Bellowing Roar", "FEAR! Fear Ward / Tremor now", { raid = true }),
      } },
  } },

  { name = "Zul'Gurub", bosses = {
    { name = "High Priestess Jeklik", mobs = { "High Priestess Jeklik" },
      tips = { "Kill bat riders, interrupt Great Heal. Stay out of the fire from her bombs." },
      avoid = { "Bomb" } },
    { name = "High Priest Venoxis", mobs = { "High Priest Venoxis" },
      tips = { "Phase 1: spread out and avoid poison clouds. Phase 2 (snake form): don't stand in the poison." },
      avoid = { "Poison Cloud" } },
    { name = "High Priestess Mar'li", mobs = { "High Priestess Mar'li" },
      tips = { "Kill the spiders quickly, avoid the poison. Interrupt drain life." } },
    { name = "High Priest Thekal", mobs = { "High Priest Thekal", "Zealot Lor'Khan", "Zealot Zath" },
      final = "High Priest Thekal",
      tips = { "Kill all three at about the same time. Dispel/fear immunity for Zealots. Burn the tiger phase." } },
    { name = "High Priestess Arlokk", mobs = { "High Priestess Arlokk" },
      tips = { "Mark target gets killed by panthers - kill the panthers. Stay out of stealth ranges." } },
    { name = "Bloodlord Mandokir", mobs = { "Bloodlord Mandokir" },
      tips = { "Do NOT MOVE when Threatening Gaze hits you. Resurrect the dead raptor once to avoid Chained Spirits." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Threatening Gaze", "GAZE on %s - DO NOT MOVE!", { player = true, raid = true, whisper = "THREATENING GAZE - STOP MOVING, DO NOT MOVE!" }),
      } },
    { name = "Jin'do the Hexxer", mobs = { "Jin'do the Hexxer" },
      tips = { "Kill Brain Wash and Healing Wards. Decurse Hex. Move out of the Delusions of Jin'do shades." },
      alerts = { A("SPELL_AURA_APPLIED", "Hex", "Decurse Hex on %s", { player = true }) } },
    { name = "Hakkar", mobs = { "Hakkar" },
      tips = { "Kill Priests to prevent Mind Control. Dispel Mind Control quickly. Decurse Cause Insanity and avoid Corrupted Blood." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Mind Control", "MIND CONTROL on %s - sheep / dispel!", { player = true, raid = true }),
        A("SPELL_AURA_APPLIED", "Blood Siphon", "Blood Siphon - Hakkar healing, kill the Blood Priests", { raid = true }),
      } },
  } },

  { name = "Ruins of Ahn'Qiraj", bosses = {
    { name = "Kurinnaxx", mobs = { "Kurinnaxx" },
      tips = { "Tank and spank. Tank away from Sand Traps. Avoid the Sand Trap puddle." },
      avoid = { "Sand Trap" } },
    { name = "General Rajaxx", mobs = { "General Rajaxx" },
      tips = { "Clear the waves first. Kill the boss at the end. Interrupt Thundercrash." } },
    { name = "Moam", mobs = { "Moam" },
      tips = { "Kill Mana Fiends and drain. Burn the boss at full mana. Healers keep up." } },
    { name = "Buru the Gorger", mobs = { "Buru the Gorger" },
      tips = { "Run from the egg when you have the Creeping Plague. Burn him down at 20%." } },
    { name = "Ayamiss the Hunter", mobs = { "Ayamiss the Hunter" },
      tips = { "P1: kill adds in the air. P2: tank on the ground and kill the Hive'Zara larva." },
      avoid = { "Stinger Spray" } },
    { name = "Ossirian the Unscarred", mobs = { "Ossirian the Unscarred" },
      tips = { "Pull him with the crystal. Use the crystals every 45s. Strong enrage between crystals." } },
  } },

  { name = "Temple of Ahn'Qiraj", bosses = {
    { name = "The Prophet Skeram", mobs = { "The Prophet Skeram" },
      tips = { "Kill each clone when it spawns. Interrupt Arcane Explosion and Fireball. Mind control gets sheeped." },
      avoid = { "Arcane Explosion" },
      alerts = { A("SPELL_AURA_APPLIED", "True Fulfillment", "TRUE FULFILLMENT on %s - sheep / dispel!", { player = true, raid = true }) } },
    { name = "The Bug Trio", mobs = { "Lord Kri", "Princess Yauj", "Vem" }, final = "Vem",
      tips = { "Kill Yauj first (fear), then Vem (stun/charge). Kri last (poison cloud) - stay out of the poison cloud." },
      avoid = { "Toxic Vapors", "Poison Cloud" } },
    { name = "Battleguard Sartura", mobs = { "Battleguard Sartura" },
      tips = { "Melee MOVE OUT when she Whirlwinds. Kill her guards first. Interrupt Silence." },
      avoid = { "Whirlwind" } },
    { name = "Fankriss the Unyielding", mobs = { "Fankriss the Unyielding" },
      tips = { "Kill worm spawns quickly. Tank away from boss for Mortal Wound swaps. Kill Spawn of Fankriss." } },
    { name = "Viscidus", mobs = { "Viscidus" },
      tips = { "Freeze him with frost damage, shatter with melee. Do NOT stand in Poison Bolt Volley range." },
      avoid = { "Poison Bolt Volley" } },
    { name = "Princess Huhuran", mobs = { "Princess Huhuran" },
      tips = { "Tank at the middle. Nature resistance. Tranq Frenzy. At 30% she berserks - burn her." },
      avoid = { "Noxious Poison" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Frenzy", "FRENZY - TRANQ SHOT!", { raid = true }),
        A("SPELL_AURA_APPLIED", "Berserk", "BERSERK - BURN HER DOWN!", { raid = true }),
      } },
    { name = "Twin Emperors", mobs = { "Emperor Vek'lor", "Emperor Vek'nilash" }, final = "Emperor Vek'lor",
      tips = { "Warlock-side tanking and melee-side tanking. Don't let them switch sides. Kill both at the same time." },
      avoid = { "Arcane Burst", "Blizzard" } },
    { name = "Ouro", mobs = { "Ouro" },
      tips = { "Move out of Sand Blast and Ground Rupture. Kill the mounds before they heal. Burn at 20%." },
      avoid = { "Sand Blast", "Ground Rupture" } },
    { name = "C'Thun", mobs = { "Eye of C'Thun", "C'Thun" }, final = "C'Thun",
      tips = { "P1: spread out, dodge Dark Glare. P2: kill Giant Claw tentacles, stomach groups kill their Flesh tentacle." },
      avoid = { "Dark Glare", "Eye Beam" } },
  } },

  { name = "Naxxramas", bosses = {
    { name = "Anub'Rekhan", mobs = { "Anub'Rekhan" },
      tips = { "Kite the adds. Impale hits in a line. When Locust Swarm is up, kite and avoid his tail." },
      avoid = { "Impale" } },
    { name = "Grand Widow Faerlina", mobs = { "Grand Widow Faerlina" },
      tips = { "Kill adds. Use Widow's Embrace when enraged. Don't stand in Rain of Fire." },
      avoid = { "Rain of Fire" } },
    { name = "Maexxna", mobs = { "Maexxna" },
      tips = { "Free webbed players quickly. Move away from Web Spray, kill spiderlings.",
               "Keep tank alive through Necrotic Poison." },
      alerts = {
        A("SPELL_CAST_START", "Web Spray", "WEB SPRAY - AOE heals!", { raid = true }),
      } },
    { name = "Noth the Plaguebringer", mobs = { "Noth the Plaguebringer" },
      tips = { "Decurse the Curse of the Plaguebringer. Kill adds, tank in the middle of the room." },
      alerts = { A("SPELL_AURA_APPLIED", "Curse of the Plaguebringer", "Decurse Curse of the Plaguebringer!", { raid = true }) } },
    { name = "Heigan the Unclean", mobs = { "Heigan the Unclean" },
      tips = { "Dance across the safe zone: move to the next safe section when the eruption pulses. In phase 2 stay in the platform." },
      avoid = { "Eruption", "Plague Cloud" } },
    { name = "Loatheb", mobs = { "Loatheb" },
      tips = { "Heal only during the Corrupted Mind window - never stack healing. Kill spores in order. Doom every 30s." },
      alerts = {
        A("SPELL_CAST_SUCCESS", "Inevitable Doom", "INEVITABLE DOOM - heal burst!", { raid = true }),
      } },
    { name = "Instructor Razuvious", mobs = { "Instructor Razuvious" },
      tips = { "Priests Mind Control the Understudies and use Taunt/Shield Wall. Kill the boss before Disrupting Shout." },
      avoid = { "Disrupting Shout" } },
    { name = "Gothik the Harvester", mobs = { "Gothik the Harvester" },
      tips = { "Split into two sides. Kill the necromancers before others. Keep your side alive." } },
    { name = "The Four Horsemen", mobs = { "Thane Korth'azz", "Lady Blaumeux", "Highlord Mograine", "Sir Zeliek" },
      tips = { "Rotate the marks - swap tanks at 3 stacks of Mark. Don't stack on Mograine's Holy Wrath.",
               "Kill in this order: Lady, Thane, Zeliek, Mograine." },
      avoid = { "Meteor", "Holy Wrath", "Shadow Bolt Volley" } },
    { name = "Patchwerk", mobs = { "Patchwerk" },
      tips = { "Heal the off-tank group. Kill before the berserk at 5%. Keep every tank healed through Hateful Strike." },
      avoid = { "Hateful Strike" } },
    { name = "Grobbulus", mobs = { "Grobbulus" },
      tips = { "Mutating Injection targets run to the outside and stay away. Stay out of Poison Clouds; keep the boss moving." },
      avoid = { "Poison Cloud", "Slime Spray" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Mutating Injection", "INJECTION on %s - RUN OUT!", { player = true, raid = true, whisper = "MUTATING INJECTION - RUN OUT OF THE RAID NOW!" }),
      } },
    { name = "Gluth", mobs = { "Gluth" },
      tips = { "Kite Zombie Chow, Decimate timing. Fear Ward / Tremor for Terrifying Roar. Don't stand in the front." },
      alerts = { A("SPELL_CAST_START", "Terrifying Roar", "FEAR! Fear Ward / Tremor now", { raid = true }) } },
    { name = "Thaddius", mobs = { "Thaddius", "Feugen", "Stalagg" }, final = "Thaddius",
      tips = { "Kill Feugen and Stalagg in the same moment. Switch sides on Polarity Shift. Stand with your own charge." },
      alerts = {
        A("SPELL_AURA_APPLIED", "Positive Charge", "+ POSITIVE: stand with the PLUS group!", { player = true, whisper = "You are POSITIVE (+). Stand with other + players." }),
        A("SPELL_AURA_APPLIED", "Negative Charge", "- NEGATIVE: stand with the MINUS group!", { player = true, whisper = "You are NEGATIVE (-). Stand with other - players." }),
        A("SPELL_CAST_START", "Polarity Shift", "POLARITY SHIFT - check your charge!", { raid = true }),
      } },
    { name = "Sapphiron", mobs = { "Sapphiron" },
      tips = { "Hide behind an Ice Block when he flies. Frost resistance. Stay out of Chill and Blizzard.",
               "Icebolt targets must stand where the block will cover the raid." },
      avoid = { "Chill", "Frost Breath", "Tail Sweep", "Blizzard" },
      alerts = {
        A("SPELL_CAST_START", "Frost Breath", "FROST BREATH - HIDE BEHIND ICE BLOCK!", { raid = true }),
        A("SPELL_AURA_APPLIED", "Icebolt", "ICEBOLT on %s", { player = true }),
      } },
    { name = "Kel'Thuzad", mobs = { "Kel'Thuzad" },
      tips = { "Do NOT stand in Shadow Fissures. Mana users run away on Detonate Mana. Interrupt Frost Blast.",
               "Chains of Kel'Thuzad - sheep or kill the controlled player." },
      avoid = { "Shadow Fissure", "Frost Blast" },
      alerts = {
        A("SPELL_AURA_APPLIED", "Detonate Mana", "DETONATE MANA on %s - RUN FROM RAID!", { player = true, raid = true, whisper = "DETONATE MANA - RUN AWAY FROM THE RAID!" }),
        A("SPELL_AURA_APPLIED", "Chains of Kel'Thuzad", "CHAINS on %s - sheep / free!", { player = true, raid = true }),
      } },
  } },
}
