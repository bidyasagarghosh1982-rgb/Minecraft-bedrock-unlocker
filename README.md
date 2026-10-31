# Minecraft Bedrock — Setup & Online Play Doctor

A single Windows batch file that installs, checks and repairs **Minecraft for Windows**
(the Bedrock edition you download from the Microsoft Store / Xbox app) so that
sign-in and **online multiplayer actually work**.

```
release/Minecraft-Bedrock-Setup.bat   <- the whole tool, one file, nothing to install
release/README.txt                    <- download notes + SHA-256
```

---

## What this is not

This repository used to be described as a "trial unlocker". That part is gone, on purpose.

There is **no "online fix", no crack, no patched DLL and no licence bypass** in here, and
this tool will not add one. Turning a Store trial into the full game requires a real
Microsoft account that owns Minecraft — Microsoft verifies that entitlement on their
servers every time you sign in, which is exactly why a cracked copy can play single player
but hangs on "Signing in…" / "Unable to connect to world" when you try to play online.
No client-side patch changes that, and shipping one would be piracy.

If you want the full experience with working multiplayer, the honest route is:

* **Buy Minecraft for Windows** on the Microsoft Store (or through the Xbox app), or
* use **Minecraft: Bedrock Edition** on a platform you already own it for, or
* play **Minecraft: Java Edition** (also purchasable, separate game), or
* play the free **Minecraft: Bedrock Edition trial** offline — single player only, by design.

This tool's job is to make the *legitimate* copy work properly, and to tell you exactly
which piece of your PC is breaking online play when it doesn't.

---

## Usage

1. Download [`release/Minecraft-Bedrock-Setup.bat`](release/Minecraft-Bedrock-Setup.bat).
2. Right-click → **Run as administrator** (or just double-click; the tool offers to elevate).
3. Pick a number from the menu.

Windows SmartScreen may warn about an unknown publisher — the file is plain text
(batch + embedded PowerShell), so you can read every line before running it. Right-click →
Edit opens it in Notepad.

Requires Windows 10 version 2004 (build 19041) or newer, which is the minimum for
Minecraft for Windows anyway.

---

## Menu

| # | Action | What it does |
|---|--------|--------------|
| 1 | Full health check | Windows build, installed game + licence status, Xbox components, Xbox services, DNS/TCP reachability to Microsoft & Xbox Live, hosts file, IPv6/Teredo, proxy, VPN, clock skew, network profile |
| 2 | Install from the Microsoft Store | Opens the official *Minecraft for Windows* product page (Store id `9NBLGGH2JHXJ`) |
| 3 | Fix online play | Starts Xbox services, flushes DNS, enables Teredo client mode when you have no IPv6, removes hosts-file blocks (with a backup), removes Minecraft *block* firewall rules, resyncs the clock, opens Settings → Gaming → Xbox Networking |
| 4 | Repair Minecraft | Backs up `LocalState` (your worlds) to the Desktop, then resets the app package — the equivalent of Settings → Apps → Minecraft → Advanced options → Reset |
| 5 | Launch Minecraft | Starts the game through its AppsFolder identity |
| 6 | Clean reinstall | Optional world backup, removes the package, reopens the Store page |
| 7 | Save report | Writes a timestamped diagnostic report to your Desktop |

Menu 1 prints PASS/WARN/FAIL per check; menu 7 saves the same thing to disk so you can
paste it when asking for help.

---

## The usual reasons Minecraft "works but can't play online"

Roughly in order of how often they're the answer:

1. **The account doesn't own the game** (trial, or a different Microsoft account than the
   one that bought it). Sign in with the same account in the Store, the Xbox app and Minecraft.
2. **Not signed in to Xbox Live** — `Microsoft.XboxIdentityProvider` or
   `Microsoft.GamingServices` missing/broken. Reinstall the Xbox app from the Store.
3. **Xbox services stopped** — `XblAuthManager`, `XboxNetApiSvc`, `GamingServices`.
4. **Strict NAT** — no IPv6 and no working Teredo, or a router without UPnP.
   Forward UDP `88`, `3074`, `500`, `3544`, `4500`.
5. **hosts file or a "telemetry blocker"** blocking `xboxlive.com` / `*.live.com`.
6. **VPN / proxy / DNS filter** intercepting Xbox Live traffic — turn it off while playing.
7. **Wrong system clock** — breaks certificate validation during sign-in.
8. **Firewall set to block on a "Public" network profile** — set home networks to Private.
9. **Family settings** — child accounts need multiplayer allowed by the parent.
10. **A modified/sideloaded package** — package status is not `Ok`; reinstall from the Store.

---

## Notes

* Every repair that touches something destructive asks first, and the two that can lose
  data (hosts file, reset/reinstall) keep a backup.
* Nothing is uploaded anywhere. The only outbound calls are DNS lookups, TCP probes to
  port 443, and a `HEAD` request to `login.live.com` to compare your clock.
* Tested logic paths: Windows 10 22H2, Windows 11 23H2/24H2, x64 and ARM64.
  If a cmdlet isn't available on your build it is skipped with a warning instead of failing.

## License

MIT — see `LICENSE`.
