# Wowloginner

Watches WoW and logs you back in if you get disconnected.

Setup (Windows, Python 3.10+):

    pip install -r requirements.txt
    python wowlogin.py setup     # account, password (stored in Windows Credential Manager), Wow.exe path
    python wowlogin.py capture   # saves templates of your login + character select screens
    python wowlogin.py run       # leave running

It only types credentials when it recognises the login screen image, never into the game world.
It stops after 5 attempts in 10 minutes to avoid account lockouts. Mouse to a screen corner aborts.
Automating input may violate your game's ToS; use at your own risk.

## GoldFarmAdvisor (WoW addon)

Copy the `GoldFarmAdvisor` folder into `World of Warcraft\_classic_era_\Interface\AddOns\` (or your version's AddOns folder), enable it, and type `/gfa`.
Needs Auctionator. Tabs: My recipes (best crafts), What to farm (gold per 10 min from your own looting), Recipes to learn (open your trainer first).

## RaidLeaderPro v2 (WoW addon)

Copy the `RaidLeaderPro` folder into your AddOns folder. `/rlp` opens the setup window: pick a boss, and for each mechanic choose who handles it, how they are told (whisper / raid warning / raid chat / screen), the instruction template and a spot. Then click **Ready & Pull** (validation, buff check, optional explainer / whisper briefing / loot rules / spot legend, countdown). Alerts, whispers, rotations, backups and the post-fight report run from that setup.

Also: fight HUD with manual fire buttons (`/rlp hud`), presets with export/import strings, role tags, spot manager, `/rlp verify`, `/rlp learn`, minimap button and keybinds. `/rlp` with an unknown word lists all commands.

Not implemented from the spec: co-leader config sync, undo/redo, proximity and debuff-stack/add-count triggers, auto raid-marking of affected players, TTS sounds, UI for mapping learned events (use `/rlp map`), "improved since last week" stats.

Boss data lives in `Data.lua`. Spell, yell and mob names are English-only and were written from memory (mechanics marked `?` in the window are the least certain), so run `/rlp verify` after a few kills and fix what never fired. The addon warns, whispers and logs only; it cannot make players move.
