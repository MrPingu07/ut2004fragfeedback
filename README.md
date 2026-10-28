# FragFeedback — GTA V-style feedback for Unreal Tournament 2004

A UT2004 mutator with two GTA V-style screen-flash effects:

- **Frag feedback** — when **you** score a frag, your **whole screen
  flashes** in a color (blue by default) that **quickly appears and slowly
  vanishes**.
- **Damage feedback** — when **you take damage**, a second, separate flash
  (mostly transparent red by default) does the same.

No letters, no bars — just the colored screen flashes. Both effects have
independent **Duration** and **Color (R/G/B)** settings exposed to the
stock **[Configure Mutators]** page, so everything is tunable from the
game's own GUI without editing files. Either duration can be set to **0**
to disable that effect entirely.

Peak brightness is a file-level config var for each effect
(`FlashIntensity` and `DamageFlashIntensity`) for ini tweaks.

> History: the first prototype (letterbox + WASTED banner) was replaced in
> v0.2 after a review round where the goal was clarified: "GTA V-like"
> meant the blue screen-flash postprocess effect, not the death banner.
> The damage flash, separate per-effect settings and periodic server
> re-enforcement arrived in v1.2.

---

## What you get on screen

| Element | Frag feedback | Damage feedback |
|---|---|---|
| Trigger | you frag an enemy | you take damage |
| Effect | full-screen additive quad in the configured color | same |
| Layer | behind the HUD and first-person weapon (Interaction.PreRender) | same |
| Onset | quick ramp-up (~10 % of the duration, >= 0.08 s) | same |
| Decay | slow linear fade to zero at the configured duration | same |
| Default color | cool cyan-blue: R 0.20 / G 0.20 / B 0.50 | transparent red: R 0.75 / G 0.00 / B 0.00 |
| Default duration | 0.50 seconds (GUI allows 0 – 15 s) | 0.50 seconds (GUI allows 0 – 15 s) |
| Default peak intensity | 0.8 (`FlashIntensity`) | 0.3 (`DamageFlashIntensity`) |

Team kills and suicides stay silent for the frag flash. The feedback is
private to the affected player's screen — other players see nothing.

While the mutator is active it also switches the stock UT2004
**ScreenFlashes** option off (the client's `ScreenFlashes=False` ini value),
because the new damage feedback replaces the vanilla damage flash and the
two would otherwise stack.

## The mutator in action

1. Go to **Instant Action** (or a server setup screen), pick **Mutators**,
   select **GTA V Frag Feedback** and press **[Configure Mutators]**.
2. Set the two independent groups:
   - **Frag Feedback** — *Duration (seconds)* and *Color R/G/B (0–1)*.
   - **Damage Feedback** — *Duration (seconds)* and *Color R/G/B (0–1)*.
3. Set any duration to **0** to disable that effect.
4. Play. Frag → blue flash pops in and drains away; take a hit → red flash
   does the same. Both can overlap without cancelling each other.

Color examples (same values work for either group):

- Default frag (cool cyan-blue): 0.20 / 0.20 / 0.50
- Default damage (transparent red): 0.75 / 0.00 / 0.00
- Red: 0.9 / 0.05 / 0.05
- Green: 0.1 / 0.9 / 0.1
- White: 1.0 / 1.0 / 1.0

Console helpers (Instant Action / listen server):

```
mutate fragfeedbacktest        # show the frag flash without fragging anyone
mutate fragfeedbackdamagetest  # show the damage flash without being hit
```

## File-level settings (optional, `UT2004.ini`)

```ini
[FragFeedback.FragFeedbackMutator]
DurationSec=0.500000
ColorR=0.200000
ColorG=0.200000
ColorB=0.500000
FlashIntensity=0.800000          ; frag peak brightness (0-1)
DamageDurationSec=0.500000
DamageColorR=0.750000
DamageColorG=0.000000
DamageColorB=0.000000
DamageFlashIntensity=0.300000    ; damage peak brightness (0-1)
```

A duration of `0.000000` disables that effect. Same section the GUI writes
to; same style as your other mutators.

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
- Proxy configuration (frag and damage color/duration/intensity) is
  replicated initially **and re-sent by the server every 10 seconds**, so
  clients always converge on the server's authoritative values. The effects
  themselves render client-side from those values.
- When a client first attaches its flash proxy, it runs the local equivalent
  of the stock Game Settings checkbox:
  `set ini:Engine.Engine.ViewportManager ScreenFlashes False`. Like a GUI
  change, this persists in that client's `UT2004.ini`; re-enable Screen
  Flashes manually if you later stop using the mutator.

## Project layout

```
source/FragFeedback/Classes/
    FragFeedbackMutator.uc   server-side mutator: GUI config, frag/damage routing
    FragFeedbackRules.uc     GameRules hooks (ScoreKill + NetDamage, chain-safe)
    FragFeedbackFlash.uc     replicated flash proxy: config + triggers + drawing
    FragFeedbackFlashInteraction.uc
                             client Interaction: draws the flashes behind the HUD
install/FragFeedback.int
tools/build.sh
tools/test.sh
docs/FINDINGS.md             environment + engine research (verified locally)
docs/APPROACH.md             architecture + design decisions + scope cuts
```

## Roadmap

- Own-death flash (the GTA V "you died" blue treatment when YOU die).
- GUI presets dropdown for colors (engine supports `Select` render type).
- Intensity promoted to the GUI (one `AddSetting` line per effect).
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
