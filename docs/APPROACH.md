# APPROACH — FragFeedback design document

## Goal

 представляют"GTA V-like frag feedback on screen for UT2004", where **version
 zero is already built around customization**: the two headline knobs
 requested for the GUI are

- **Color** — the banner text color (freely as R/G/B 0..1 channels)
- **Duration** — how long the whole feedback stays on screen

Both are exposed through the stock **[Configure Mutators]** page (PlayInfo),
exactly like the engine's own mutator settings are. Everything else (banner
text, subtitle text, fonts, letterbox on/off) is deliberately handled as
file-level settings in v0 and is already shaped as the same `var() config`
pattern so promoting any of them into the GUI later is a four-line change
(`static FillPlayInfo` + localization keys).

## Architecture (three classes)

```
FragFeedback package
├── FragFeedbackMutator  (server)  entry point + GUI config + banner proxies
├── FragFeedbackRules    (server)  GameInfo.ScoreKill hook (GameRules chain)
└── FragFeedbackBanner   (server+client, replicated)  the on-screen visual
```

### Why a GameRules instead of the mutator's own ScoreKill

`Engine.Mutator` is native and its `ScoreKill` is not exposed as script.
`Engine.GameRules` is fully scriptable with a documented chained API
(`GameInfo.AddGameModifier`, `GameRules.ScoreKill(Killer, Killed)` +
`Super` chain; vanilla precedent: `UnrealGame.BigHeadRules`). The mutator
spawns one `FragFeedbackRules` in `PostBeginPlay` and registers it with
`Level.Game.AddGameModifier(...)`. Chain integrity with other mutators
(RespawnDelay, GTAThirdPerson, vanilla) is preserved by construction.

### Why a replicated HudOverlay proxy (not LocalMessage, not Interaction)

The kill happens on the **server**, the screen lives on the **client**:

1. `ModifyPlayer(Pawn)` — called for every (re)spawn — makes the mutator
   `Spawn(class'FragFeedbackBanner', PC)` with `Owner = the player's
   PlayerController`. One proxy per human; bots get none.
   `bOnlyRelevantToOwner=True` keeps it private to that player.
2. The mutator pushes the server-side configuration (Color channels,
   Duration, texts) into the proxy's vars; they replicate with the initial
   actor message (`reliable if (bNetInitial && Role == ROLE_Authority)`).
   This is what makes the **GUI settings reachable on network clients**
   with zero extra plumbing.
3. Per frag, `FragFeedbackRules.ScoreKill` → `Mutator.NotifyFrag`:
     - skips suicides, team kills (team games), bots;
   - calls the reliable remote `ClientShowBanner(victimName)` on the
     killer's proxy.
4. On the client, the proxy attaches itself to `PlayerController.MyHUD`
   via `HUD.AddHudOverlay` (`PostBeginPlay` for standalone/listen host,
   `PostNetBeginPlay` for network clients, bounded `Timer` retries in
   between), and `Render(Canvas)` runs while
   `0 <= (TimeSeconds - ShowAt) < BannerDuration`.

Rejection rationale:
- *LocalMessage* — fixed draw color/lifetime comes from message-class
  defaults; arbitrary per-user color+duration would need encoding hacks.
- *Interaction* — works, but needs client-side self-registration and pulls
  in input handling; HudOverlay is the narrower engine-blessed HUD hook.
- *Plain user-message spam* — no control over size, position, animation.

## The visual (GTA V "WASTED" treatment, applied to a frag)

For the configured Duration window (default 3 s), the banner is composed
purely of canvas primitives:

1. **Letterbox bars** — black top/bottom bars at 10.5 % of screen height,
   sliding in like the GTA V wasted screen and sliding back out at the end
   of the window (fade envelope: alpha 0→1 in 12 % of the duration, 1→0
   over the last 30 %).
2. **Banner text** (default `"WASTED"`, `2K4Fonts.Impact32`) — glyph height
   ≈ 13 % of screen height, horizontally centered, slight lift above
   center; **scale pop-in** (1.5× → 1.0× ease-out over 0.3 s) plus a heavy
   GTA-style treatment: 8-direction black outline (2-6 px, scaled with the
   glyph height) + long down-right drop shadow + the configured color fill.
3. **Subtitle** (default format `"You fragged %1"`, `2K4Fonts.Verdana14`)
   — small near-white line under the banner with the fragged player's name;
   an empty format disables it.

Timing/threshold constants are named `const`s in one block at the top of
`FragFeedbackBanner.uc` (HeightFrac, gaps, fade fractions, pop time).

## Customization surface (v0)

| Setting | Where | Class var |
|---|---|---|
| Duration (0.5-15 s) | [Configure Mutators] | `DurationSec` |
| Color R/G/B (0-1) | [Configure Mutators] | `ColorR`, `ColorG`, `ColorB` |
| Banner text | UT2004.ini | `BannerText` |
| Subtitle / victim line | UT2004.ini | `VictimFormat` (`%1` = victim name) |
| Letterbox bars on/off | UT2004.ini | `ShowBars` |
| Banner / subtitle fonts | UT2004.ini | `BannerFontName`, `VictimFontName` |

Inis section: `[FragFeedback.FragFeedbackMutator]` in `UT2004.ini`
(PlayInfo saves there natively, mirroring `RespawnDelay.RespawnDelay`).

Design rule observed throughout: **every tweakable is a `var() config`**
with engine-friendly extras strings (`"8;0.5:15.0"`), so any file-level
setting can graduate into the GUI in one `AddSetting` line.

## Console helpers (own testing)

- `mutate fragfeedbacktest` — show the banner immediately (no kill needed)
- `mutate fragfeedbackstatus` — print duration + RGB channels (0-255)

## Scope cuts in v0 (documented, cheap to add later)

- No own-death banner ("WASTED for you") — the same proxy is already
  replicated per-player; a `ClientShowBanner`-style self-call on death is a
  two-line addition in `FragFeedbackRules` (`Killed` instead of `Killer`).
- No multiplayer-visible broadcast (feedback stays private to the killer,
  which is what "frag feedback" means).
- No color presets dropdown (the R/G/B edits are the general case; a
  `"Select"` preset row could be added like RespawnDelay's presets).
- No grayscale/desaturation pass (UT2004's pipeline makes it hacky; the
  letterbox+banner is the recognizable GTA gesture).

## Build/deploy pipeline

`tools/build.sh` (idempotent):
syncs `source/FragFeedback/Classes/*.uc` → `$UT2004_DIR/FragFeedback/Classes`,
fixes up `EditPackages` (adds `FragFeedback` once, collapses the duplicated
`GTAThirdPerson` lines found in this install), runs `wine UCC.exe make`,
`wine UCC.exe exportcache FragFeedback.u`, and installs
`install/FragFeedback.int` into `System/`.

`tools/test.sh [map]` launches Instant-Action-like DM with the mutator:
`wine UT2004.exe <map>?game=DeathMatch?mutator=FragFeedback.FragFeedbackMutator`.

## Verification performed

- `ucc make` builds clean (0 errors / 0 warnings on the first pass).
- `ucc exportcache` generated the mutator `.ucl` entry; the `.int` mirrors
  the `Object=` convention used by the install's existing working mutators.
- Headless `ucc server DM-Corrugation?...?mutator=FragFeedback.FragFeedbackMutator`
  with `MinPlayers=8`: mutator and rules register, no runtime errors over a
  full match (see docs/FINDINGS.md for the pre-existing GameSpy noise).
- Human screen test: pending, via `tools/test.sh` (banner pop, letterbox
  slide, color/duration change from the mutator screen),
  `mutate fragfeedbacktest` for a no-kill preview.
