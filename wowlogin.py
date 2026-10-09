#!/usr/bin/env python3
"""WoW auto-relogin: watches the game and logs you back in if you get disconnected.

Commands:
  python wowlogin.py setup     save account name, password (OS vault), game path
  python wowlogin.py capture   take a template image of a screen (login / charselect)
  python wowlogin.py run       watch forever and log back in
"""
import json
import subprocess
import sys
import time
from getpass import getpass
from pathlib import Path

import keyring
import psutil
import pyautogui
import pygetwindow

APP = Path(__file__).parent
CONFIG = APP / "config.json"
LOGIN_IMG = APP / "login_screen.png"
CHAR_IMG = APP / "charselect_screen.png"
SERVICE = "wowlogin"

POLL_SECONDS = 2
COOLDOWN_SECONDS = 25        # wait after an attempt before trying again
MAX_ATTEMPTS = 5             # per window below, protects against account lockout
ATTEMPT_WINDOW = 600
PAUSE_AFTER_LIMIT = 600

pyautogui.FAILSAFE = True    # slam the mouse into a screen corner to abort


def load_config():
    if not CONFIG.exists():
        sys.exit("No config yet. Run: python wowlogin.py setup")
    return json.loads(CONFIG.read_text())


def setup():
    cfg = {
        "account": input("WoW account name/email: ").strip(),
        "exe": input(r'Path to launch WoW (e.g. C:\...\Wow.exe), blank = don\'t auto-launch: ').strip(),
        "process": input("Process name [Wow.exe]: ").strip() or "Wow.exe",
        "window_title": input("Window title contains [World of Warcraft]: ").strip() or "World of Warcraft",
    }
    keyring.set_password(SERVICE, cfg["account"], getpass("Password (hidden): "))
    CONFIG.write_text(json.dumps(cfg, indent=2))
    print("Saved. Password is in your OS credential vault, not in config.json.")
    print("Next: python wowlogin.py capture")


def capture():
    cfg = load_config()
    for name, path in (("LOGIN screen", LOGIN_IMG), ("CHARACTER SELECT screen", CHAR_IMG)):
        input(f"\nGet the game to the {name} and press Enter here (you have 5s to switch windows)... ")
        time.sleep(5)
        print("Drag nothing: capturing a fixed, distinctive area in the middle of the screen.")
        w, h = pyautogui.size()
        # A distinctive chunk: centered box. Replace the PNG by hand with a tighter crop if matching is flaky.
        pyautogui.screenshot(region=(w // 3, h // 3, w // 3, h // 3)).save(path)
        print(f"Saved {path.name}")
    print("\nTip: crop the PNGs to something unique to those screens (e.g. the Login button) for best results.")


def game_window(cfg):
    for win in pygetwindow.getAllWindows():
        if cfg["window_title"].lower() in win.title.lower() and win.width > 0:
            return win
    return None


def game_running(cfg):
    return any((p.info["name"] or "").lower() == cfg["process"].lower()
               for p in psutil.process_iter(["name"]))


def on_screen(img):
    if not img.exists():
        return False
    try:
        return pyautogui.locateOnScreen(str(img), confidence=0.8) is not None
    except pyautogui.ImageNotFoundException:
        return False


def do_login(cfg, win):
    password = keyring.get_password(SERVICE, cfg["account"])
    if not password:
        sys.exit("Password missing from vault. Re-run setup.")
    try:
        win.activate()
    except Exception:
        pass
    time.sleep(0.5)
    pyautogui.hotkey("ctrl", "a"); pyautogui.press("backspace")
    pyautogui.write(cfg["account"], interval=0.03)
    pyautogui.press("tab")
    pyautogui.hotkey("ctrl", "a"); pyautogui.press("backspace")
    pyautogui.write(password, interval=0.03)
    pyautogui.press("enter")


def run():
    cfg = load_config()
    if not LOGIN_IMG.exists():
        sys.exit("No login_screen.png. Run: python wowlogin.py capture")
    attempts = []
    last_action = 0.0
    print("Watching WoW. Ctrl+C to stop. Mouse to a screen corner = emergency abort.")
    while True:
        time.sleep(POLL_SECONDS)
        now = time.time()
        if now - last_action < COOLDOWN_SECONDS:
            continue

        if not game_running(cfg):
            if cfg["exe"]:
                print("Game not running, launching...")
                subprocess.Popen([cfg["exe"]])
                last_action = now
            continue

        win = game_window(cfg)
        if win is None:
            continue

        if on_screen(CHAR_IMG):
            print("Character select -> entering world")
            pyautogui.press("enter")
            last_action = now
        elif on_screen(LOGIN_IMG):
            attempts = [t for t in attempts if now - t < ATTEMPT_WINDOW]
            if len(attempts) >= MAX_ATTEMPTS:
                print(f"{MAX_ATTEMPTS} attempts in {ATTEMPT_WINDOW}s, pausing to avoid lockout.")
                time.sleep(PAUSE_AFTER_LIMIT)
                attempts.clear()
                continue
            print("Login screen detected -> logging in")
            do_login(cfg, win)
            attempts.append(now)
            last_action = now


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"setup": setup, "capture": capture, "run": run}.get(cmd, lambda: print(__doc__))()
