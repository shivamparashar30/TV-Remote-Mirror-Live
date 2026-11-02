# Laptop ↔ TV

Everything here talks to the TV over your home Wi-Fi using ADB. No cables, no root,
nothing installed on the TV for the remote itself.

## One-time setup

**On the TV:** Settings → Device Preferences → About → press OK on **Build** seven times.
Go back → **Developer options** → turn on **USB debugging** *and* **Network/ADB debugging**
(Mi TVs list both).

**On this Mac:** make sure it is on the *same Wi-Fi* as the TV, then:

```bash
cd ~/Documents/TV/laptop-remote
./tv connect              # finds the TV by itself; accept "Allow USB debugging?" on
                          # the TV and tick "Always allow"
./tv probe                # should print the model, Android version and RAM
```

(`./tv connect 192.168.x.x` still works if you want to name the address, and `./tv find`
lists everything on the network serving ADB.)

The IP is remembered in `.tv-state.json`. **You only ever do this once.** The TV's address is a
DHCP lease and the router does move it — it was `192.168.0.115`, it is now `192.168.0.102` — but
`./tv remote` checks the remembered address first and, if nothing answers, rescans the subnet,
identifies the TV by its model (`MiTV-AXSO2`) so it cannot latch onto your phone, and saves the
new address. A background check repeats that every 20 s while the remote runs, so the page keeps
working through a lease change without a restart.

That is also why the service can start before the TV does: with the TV off it serves the page
anyway and connects when the TV comes on.

It also records the TV's **MAC address** (`68:39:43:3d:3b:87`), which never changes. That is only
used for diagnosis, and it is the difference between a useful message and a useless one:

```
The TV is on the network at 192.168.0.102 (68:39:43:3d:3b:87) but it is not accepting ADB on 5555.
That is what standby looks like - turn the TV on and try again.
```

**Android closes the ADB port in standby.** This is normal and it is the most likely reason the
remote suddenly stops responding: the TV is still on the network and still answers ARP, but
nothing is listening on 5555, and `adb devices` is left showing `offline`. Turning the TV on
fixes it; the sweep clears the stale `offline` entry on the way through. Only if the MAC is
absent from the network entirely does it tell you to go and check Developer options.

## The remote, always on (no terminal)

```bash
./service.sh install
```

Installs it as a macOS login service. It starts at login, restarts itself if it crashes, and
from then on you just open the page on your phone — nothing to type, no Terminal window to keep
open, no `./tv remote` first.

```
    phone / tablet   http://shivam-macbook-air.local:8787     <- bookmark this one
    same, by IP      http://192.168.0.109:8787
    on this Mac      http://localhost:8787
```

**Bookmark the `.local` address, not the IP.** Your router hands out IPs by DHCP and they move —
this Mac was `192.168.0.116` and is now `.109`. The `.local` name follows the Mac whatever its
IP is, and iPhones resolve it natively on the same Wi-Fi. On the phone: open it in Safari once,
then Share → **Add to Home Screen**. It opens fullscreen, like an app.

| | |
|---|---|
| `./service.sh install` | start now and at every login |
| `./service.sh status` | running? on what address? which app is on the TV? |
| `./service.sh restart` | after editing `tvctl.py` or `ui.html` — re-syncs, then reloads |
| `./service.sh logs` | follow the log (`~/Library/Logs/tvremote.log`) |
| `./service.sh uninstall` | stop it and remove it |

**The Mac has to be awake.** It is the only machine that can reach the TV, so if it is asleep the
page will not load. Lid closed on power is fine *if* you stop it sleeping:

```bash
sudo pmset -c disablesleep 1     # stays awake on AC, even with the lid shut
sudo pmset -c disablesleep 0     # undo
```

On battery, let it sleep — the service comes back by itself when the Mac wakes.

**It does not run out of this folder.** macOS refuses launchd agents access to `~/Documents`
(TCC), so the agent would die with `Operation not permitted`. `install` copies `tv`, `tvctl.py`
and `ui.html` into `~/Library/Application Support/tvremote`, which is not protected, and runs
them from there. This folder stays the source of truth — edit here, then `./service.sh restart`.

## Running it by hand instead

```bash
./tv remote           # reachable from any device on your Wi-Fi
./tv remote --local   # this Mac only
```

It prints two addresses:

```
  on this Mac      http://localhost:8787
  phone / tablet   http://192.168.0.116:8787
```

Open the second one on your phone, tablet or another laptop on the same Wi-Fi and you get the
same remote there. The page is laid out for a phone already. macOS asks to allow incoming
connections the first time — say Allow.

While it runs, anyone on your Wi-Fi can control the TV. That is usually fine at home; `--local`
turns it off, and Ctrl-C stops the server entirely.

Two tabs.

**Remote** — D-pad, volume, playback, your installed apps as buttons, and a quick text box.

**Touchpad & typing** — a pad that *is* the TV screen, with a picture of the TV behind it:

| Gesture | What it does |
|---|---|
| Click | Taps that exact spot on the TV (`input tap`) |
| Drag | Swipes from where you pressed to where you released |
| Scroll wheel | Scrolls the TV |
| Refresh now / Pause | The pad goes live automatically when you open the tab |

Under the pad: **Back, Home, Vol −, Mute, Vol +**, so you do not have to switch tabs for the
things you reach for constantly. The tab bar stays pinned to the top as you scroll.

**Why it is about 1 fps.** The TV itself needs ~1.2 s to PNG-encode a 1920x1080 frame — it is
CPU-bound on a 2 GB Amlogic chip, and no ADB trick gets around it (a persistent `adb shell` made
no difference at all). So captures run **continuously in a background thread** and the browser is
served the newest one instantly: `/screen.png` answers in **0.003 s** instead of 1.2-1.7 s, and your
clicks never wait for a screenshot. The picture still only updates about once a second.
For real-time video use **Open mirror** (scrcpy), which uses the hardware H.264 encoder.

**Apps that block capture.** Netflix, Prime Video and HDMI inputs refuse screen capture at the OS
level — `screencap` returns 0 bytes. The pad detects this and says so instead of showing a frozen
old frame. Your clicks still reach the app; you just cannot see it. Use the Remote tab's D-pad there.

Android TV has no mouse cursor, so a relative trackpad would have nothing to move; mapping the pad
to screen coordinates is what actually works here. Verified on this TV: a click at pad position
(0.607, 0.761) taps (1166, 822) and launches the app under it.

The big type box has **Send** and **Send + OK** (types, then presses OK to submit).

Your Mac keyboard drives it directly: arrows move, <kbd>⏎</kbd> is OK, <kbd>⌫</kbd> is Back,
<kbd>H</kbd> is Home, <kbd>+</kbd>/<kbd>−</kbd> volume, <kbd>M</kbd> mute, <kbd>space</kbd> play/pause.

It keeps one long-lived `adb shell` open, so a keypress lands in milliseconds rather than
the ~200ms a fresh `adb` call costs.

## Seeing the TV on your laptop

```bash
./tv mirror
```

Opens the TV's screen in a window (scrcpy). Click with the mouse, type with the keyboard.
Netflix, Prime Video, Live TV and HDMI inputs appear black — those apps block capture at the
hardware level. That is the TV protecting the content, not a fault here.

## Mirroring the *laptop* onto the TV

Different direction, different technology — ADB can't do it. Two options:

| | How | Quality |
|---|---|---|
| **AirPlay** (recommended) | Install **AirScreen** from the Play Store on the TV and open it once. Your Mac then sees the TV in Control Centre → Screen Mirroring, like an Apple TV. | Full desktop, audio, best |
| **Google Cast** | Mi TVs have Chromecast built in. In Chrome: ⋮ → Cast → choose the TV → *Cast desktop*. | Fine for a tab, laggier for the desktop |

macOS cannot use the TV's own "Mi Screen Mirroring" / Miracast — that is a Windows and
Android protocol.

## Typing: what it can and cannot do

`tv type` and both text boxes use `input text`, which goes to whatever field currently has
**focus** on the TV. That means it works in app search boxes, password fields and login forms —
and does nothing on Google TV's own home search, which is voice-driven. Focus the field first.

## Everything else

```bash
./tv apps                 # list the TV's apps
./tv open netflix         # launch one by name
./tv key HOME DOWN OK     # send remote keys
./tv type "stranger things"
./tv url https://www.netflix.com/title/80057281
./tv shot screen.png      # screenshot the TV
./tv shell "pm list packages -d"
./tv off                  # close the ADB port when you're done
```

## Why this is not deployed to Vercel (or anywhere else)

The remote is not a website. It is a thin UI over `adb` commands that run **on this Mac**, which
is the only machine that can reach the TV at `192.168.0.115`. Hosting it in the cloud cannot work:

- a Vercel function has no `adb` binary and no route to your home network, so every button fails;
- hosting only the UI there is worse — an HTTPS page is blocked by browsers from calling
  `http://192.168.0.116`, so it could not even talk to your Mac.

Running it on the Mac and opening the LAN address is the version that actually works, and it is
faster too, since nothing leaves your house. "Deploying" it here means `./service.sh install` —
it runs on the Mac without you, which is the part that was actually annoying.

If you want the remote with the **Mac switched off**, nothing in this folder can give you that;
ADB has to run on a machine on your network. The options are an always-on box (a Raspberry Pi on
the LAN running this same script), or, for basic D-pad and volume only, Google's own
**Google TV** app on your phone, which talks to the TV directly over Wi-Fi and needs no Mac —
but gives you none of the touchpad, app grid or typing here.

**If you ever want it from outside the house**, the answer is a private tunnel, not public
hosting: install [Tailscale](https://tailscale.com) on the Mac and your phone, and use the Mac's
`100.x.y.z` address instead. Never port-forward 8787 or 5555 to the internet — both give full
control of the TV.

## Security

Port 5555 is plaintext and gives full control of the TV to anything on your network.
It is fine while you are working, but run `./tv off` and switch Developer options back off
when you are done. Never forward that port through your router.
