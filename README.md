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

## RaidLeaderPro (WoW addon)

Copy the `RaidLeaderPro` folder into your AddOns folder and type `/rlp` (or `/rlp ui` for a button panel).
Pull timer with a pre-pull buff check, boss strategy posts, on-screen/raid/whisper alerts for key mechanics (Living Bomb, Mandokir gaze, Thaddius charges, Chromaggus breaths, ...), and a per-fight report of avoidable damage and deaths plus a lifetime leaderboard.
Boss data lives in `Data.lua`; spell/mob names are matched in English, and were written from memory, so check them in-game and fix any that don't fire.
An addon cannot make players avoid mechanics. It warns, tells them what to do, and records who failed.
