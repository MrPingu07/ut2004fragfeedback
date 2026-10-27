# FragFeedback — GTA V-style frag feedback for Unreal Tournament 2004

A UT2004 mutator that reacts to every frag **you** score with the GTA V
postprocess kill feedback: your **whole screen flashes** in a color (blue
by default) that **quickly appears and slowly vanishes**. No letters, no
bars — just the colored screen flash, exactly the gesture GTA V teaches.

**Version zero is built to be customized from the game's own GUI:** the
flash **Color** (R/G/B channels, 0–1) and **Duration** (seconds) are
exposed to the stock **[Configure Mutators]** page — no file editing
required. Peak intensity is also a config var (`FlashIntensity`) for ini
tweaks and is one line away from the GUI.

> History: the first prototype (letterbox + WASTED banner) was replaced in
> v0.2 after a review round where the goal was clarified: "GTA V-like"
> meant the blue screen-flash postprocess effect, not the death banner.

---

## What you get on screen

| Element | Default |
|---|---|
| Effect | full-screen additive quad in the configured color |
| Layer | behind the HUD and first-person weapon (Interaction.PreRender) |
| Onset | quick ramp-up (~10 % of the duration, >= 0.08 s) |
| Decay | slow linear fade to zero at the configured duration |
| Color | cool cyan-blue: R 0.20 / G 0.20 / B 0.50 |
| Duration | 0.50 seconds by default (GUI allows 0.10 – 15 s) |
| Peak intensity | 0.8 (file level: `FlashIntensity`) |

Team kills and suicides stay silent. The feedback is private to the
killer's screen — other players see nothing.

## The mutator in action

1. Go to **Instant Action** (or a server setup screen), pick **Mutators**,
   select **GTA V Frag Feedback** and press **[Configure Mutators]**.
2. Set **Duration (seconds)** and **Color R/G/B (0–1)**.
   - Default (cool cyan-blue): 0.20 / 0.20 / 0.50 —
   - Red: 0.9 / 0.05 / 0.05 —
   - Green: 0.1 / 0.9 / 0.1 —
   - White: 1.0 / 1.0 / 1.0
3. Play. Frag → flash pops in, then drains away over Duration.

Console helper (Instant Action / listen server):

```
mutate fragfeedbacktest      # show the flash without fragging anyone
```

## File-level settings (optional, `UT2004.ini`)

```ini
[FragFeedback.FragFeedbackMutator]
DurationSec=0.500000
ColorR=0.200000
ColorG=0.200000
ColorB=0.500000
FlashIntensity=0.800000      ; peak brightness (0-1), dim to taste
```

Same section the GUI writes to; same style as your other mutators.

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

## Network notes

- `bAddToServerPackages=True` auto-registers the package; remote clients
  joining an internet/LAN server will additionally need the `.u` (via
  redirect server or by copying `System/FragFeedback.u` manually).
- Settings changed in the GUI take effect at the next map load (each match
  re-spawns the mutator and the proxies; standard PlayInfo behavior).
- Proxy configuration (color/duration/intensity) is replicated; the effect
  itself renders client-side from replicated values.

## Project layout

```
source/FragFeedback/Classes/
    FragFeedbackMutator.uc   server-side mutator: GUI config, kill routing
    FragFeedbackRules.uc     GameRules hook (ScoreKill chain, other-mutator-safe)
    FragFeedbackFlash.uc     replicated flash proxy: config + trigger
    FragFeedbackFlashInteraction.uc
                             client Interaction: draws the flash behind the HUD
install/FragFeedback.int
tools/build.sh
tools/test.sh
docs/FINDINGS.md             environment + engine research (verified locally)
docs/APPROACH.md             architecture + design decisions + scope cuts
```

## Roadmap (after v0)

- Own-death flash (the GTA V "you died" blue treatment when YOU die).
- GUI presets dropdown for colors (engine supports `Select` render type).
- Intensity promoted to the GUI (one `AddSetting` line).
- Per-weapon tints, kill-streak escalation intensities.

## Development notes / troubleshooting

- The game copy is the **Windows edition running through Wine**
  (`wine UCC.exe`, `wine UT2004.exe`); see `docs/FINDINGS.md`.
- `ucc make` in this engine build can consider a rebuilt package "up to
  date" even after class changes (a class rename did it); the build script
  deletes the old `.u` first to force a clean recompile.
- If the mutator list doesn't show the mutator, check that
  `System/FragFeedback.ucl` and the `[Public] Object=` line in
  `System/FragFeedback.int` are present (build script handles both).
- The flash uses `Engine.WhiteTexture` + `STY_Additive`, both stock engine
  assets/paths — no custom textures needed.
- Server `ucc server` crash (`UdpGamespyQuery ... Assertion failed, line
  58`) is a **pre-existing install issue** (Epic's port-swap watchdog +
  dead GameSpy masters); workaround and details in docs/FINDINGS.md.
