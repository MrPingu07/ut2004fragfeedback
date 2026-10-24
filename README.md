# FragFeedback — GTA V-style frag feedback for Unreal Tournament 2004

A UT2004 mutator that reacts to every frag **you** score with a GTA V
"WASTED"-style screen treatment: cinematic letterbox bars slide in, and a
big bold banner pops with your chosen text and the fragged player's name.

**Version zero is built to be customized from the game's own GUI:** the
banner **Color** (R/G/B channels, 0–1) and **Duration** (seconds) are
exposed to the stock **[Configure Mutators]** page — no file editing
required. Everything else (banner text, victim line, fonts, letterbox) is
already a config var too, so those can be tuned in `UT2004.ini` or promoted
to the GUI with one line each.

---

## What you get on screen

| Element | Default |
|---|---|
| Letterbox bars (top/bottom, slide-in/out) | black, ~10 % of screen height |
| Banner text | `WASTED` in bold condensed Impact-style font |
| Banner color | GTA V red (R 0.72 / G 0.10 / B 0.12) |
| Banner treatment | 8-way black outline + drop shadow + scale pop-in |
| Subtitle | `You fragged <victim name>` |
| Lifetime | 3 seconds (fade-in 12 %, hold, fade-out last 30 %) |

Team kills and suicides stay silent (feedback is for earned frags).
The feedback is private to the killer's screen — other players see nothing.

## The mutator in action

1. Go to **Instant Action** (or a server setup screen), pick **Mutators**,
   select **GTA V Frag Feedback** and press **[Configure Mutators]**.
2. Set **Duration (seconds)** and **Color R/G/B (0–1)**.
   - Red GTA banner: 0.72 / 0.10 / 0.12
   - Gold: 1.0 / 0.8 / 0.0 —
   - White: 1.0 / 1.0 / 1.0
3. Play. On every frag: bars slide, banner pops, victim's name appears.

Console helpers (Instant Action / listen server):

```
mutate fragfeedbacktest     # show the banner without fragging anyone
mutate fragfeedbackstatus   # print the current duration and color
```

## File-level settings (optional, `UT2004.ini`)

```ini
[FragFeedback.FragFeedbackMutator]
BannerText="WASTED"                  ; whatever text you want
VictimFormat="You fragged %1"        ; empty string disables the line
ShowBars=True                        ; letterbox bars on/off
BannerFontName="2K4Fonts.Impact32"   ; resolved on the client machine
VictimFontName="2K4Fonts.Verdana14"
```

The GUI variables are stored in the same section
(`DurationSec`, `ColorR`, `ColorG`, `ColorB`) — same file, same style as
your other mutators (see `[RespawnDelay.RespawnDelay]`, section style also used by GTAThirdPerson).

## Install (already done on this machine)

Build tool: `tools/build.sh` — idempotent; run it after every source change.

```bash
cd /home/jdmr/Proyectos/ut2004fragfeedback
tools/build.sh            # compiles + installs into /home/jdmr/Juegos/UT2004
tools/test.sh DM-Corrugation   # eyeball test: DM with the mutator forced on
```

What lands in `$UT2004_DIR`:

| File | Place | Role |
|---|---|---|
| `FragFeedback/Classes/*.uc` | game root | UnrealScript source (for `ucc make`) |
| `System/FragFeedback.u` | compiled package | do not edit |
| `System/FragFeedback.ucl` | mutator cache | found by the mutator lists |
| `System/FragFeedback.int` | localization | mutator list entry + GUI strings |
| `UT2004.ini [Editor.EditorEngine]` | `EditPackages=FragFeedback` (once) | compile pipeline |

Manual test run (no script):

```bash
cd /home/jdmr/Juegos/UT2004/System
wine UT2004.exe "DM-Corrugation?game=DeathMatch?mutator=FragFeedback.FragFeedbackMutator"
```

## Multilingual / network notes

- The `.int` is English; strings are also baked into class defaults, so the
  mutator never breaks without it. Extra language files can be added later
  (`.det`, `.est`, …) copying the int's structure.
- For network play, `bAddToServerPackages=True` auto-registers the package;
  remote clients still need the `.u` (via redirect server or by copying
  `System/FragFeedback.u` manually).
- Settings changed in the GUI take effect at the next map load (each match
  re-spawns the mutator and the proxies; standard PlayInfo behavior).

## Project layout

```
source/FragFeedback/Classes/
    FragFeedbackMutator.uc   server-side mutator: GUI config, kill routing
    FragFeedbackRules.uc     GameRules hook (ScoreKill chain, other-mutator-safe)
    FragFeedbackBanner.uc    replicated HudOverlay: letterbox + banner + subtitle
install/FragFeedback.int
tools/build.sh
tools/test.sh
docs/FINDINGS.md             environment + engine research (verified locally)
docs/APPROACH.md             architecture + design decisions + scope cuts
```

## Roadmap (after v0)

- Own-death banner (the GTA classic "WASTED" when YOU die).
- GUI presets dropdown for colors (engine supports `Select` render type).
- Kill-streak escalation (double-kill variants) using the same proxy.
- Fully per-player local overrides (`[FragFeedback.*]` client config).

## Development notes / troubleshooting

- The game copy is the **Windows edition running through Wine**
  (`wine UCC.exe`, `wine UT2004.exe`); see `docs/FINDINGS.md`.
- `Bus` noise: wine prints `fixme:winediag` lines; the build filters them.
- If the mutator list doesn't show the mutator, check that
  `System/FragFeedback.ucl` and the `[Public] Object=` line in
  `System/FragFeedback.int` are present (build script handles both).
- Server `ucc server` crash (`UdpGamespyQuery ... Assertion failed, line
  58`) is a **pre-existing install issue** (Epic's port-swap watchdog +
  dead GameSpy masters); workaround and details in docs/FINDINGS.md.
- The banner uses fonts that only exist inside the stock GUI packages;
  fallbacks are hard-coded (`UT2003Fonts.FontEurostile37`, then the engine
  default font), and the font names are per-machine ini settings.
