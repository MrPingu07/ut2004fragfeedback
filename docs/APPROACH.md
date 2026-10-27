# APPROACH — FragFeedback design document

## Goal

"GTA V-like frag feedback on screen" as **defined by the user** (this is
the redefinition that shaped v0.2): the GTA V postprocess kill feedback —
**the screen flashes with a colored (blue by default) full-screen effect
that quickly appears and slowly vanishes**. Version zero keeps the two
headline knobs requested for the GUI:

- **Color** — the flash color, freely as R/G/B 0..1 channels (default:
  cool cyan-blue 0.20 / 0.20 / 0.50)
- **Duration** — seconds from onset to fully gone (default: 0.5; GUI
  allows 0.10 – 15 s)

Both are exposed through the stock **[Configure Mutators]** page (PlayInfo),
exactly like the engine's own mutator settings are. Peak intensity is a
file-level `FlashIntensity` var (one `AddSetting` line away from the GUI if
wanted). The first prototype (letterbox bars + WASTED-style banner text)
was retired — the user clarified the target gesture was the *flash*; the
renaming of its class to `FragFeedbackFlash` mirrors that.

## Architecture (four classes)

```
FragFeedback package
├── FragFeedbackMutator  (server)  entry point + GUI config + flash proxies
├── FragFeedbackRules    (server)  GameInfo.ScoreKill hook (GameRules chain)
├── FragFeedbackFlash    (server+client, replicated)  proxy: config + trigger
└── FragFeedbackFlashInteraction (client)  PreRender hook: draws behind HUD
```

### Why a GameRules instead of the mutator's own ScoreKill

`Engine.Mutator` is native and its `ScoreKill` is not exposed as script.
`Engine.GameRules` is fully scriptable with a documented chained API
(`GameInfo.AddGameModifier`, `GameRules.ScoreKill(Killer, Killed)` +
`Super` chain; vanilla precedent: `UnrealGame.BigHeadRules`). The mutator
spawns one `FragFeedbackRules` in `PostBeginPlay` and registers it with
`Level.Game.AddGameModifier(...)`. Chain integrity with other mutators
(RespawnDelay, GTAThirdPerson, vanilla) is preserved by construction.

### Why a replicated flash proxy + local Interaction

The kill happens on the **server**, the screen lives on the **client**.
The proxy Actor carries replication; a client-only Interaction provides the
correct render layer. `HudOverlay` was the original render hook, but its
`Render` is called from `HUD.PostRender` **after** `DrawHud`, so the flash
covered the HUD. `Interaction.PreRender` runs after the world and **before**
the HUD and first-person weapon, which is the layer the effect wants.

1. `ModifyPlayer(Pawn)` — called for every (re)spawn — makes the mutator
   `Spawn(class'FragFeedbackFlash', PC)` with `Owner = the player's
   PlayerController`. One proxy per human; bots get none.
   `bOnlyRelevantToOwner=True` keeps it private to that player.
2. The mutator pushes the server-side configuration (Color channels,
   Duration, Intensity) into the proxy's vars; they replicate with the
   initial actor message (`reliable if (bNetInitial &&
   Role == ROLE_Authority)`). This is what makes the **GUI settings
   reachable on network clients** with zero extra plumbing.
3. Per frag, `FragFeedbackRules.ScoreKill` → `Mutator.NotifyFrag`, which
     - skips suicides, team kills (team games), bots;
   - calls the reliable remote `ClientShowFlash()` on the killer's proxy.
4. On the client, the proxy registers a local
   `FragFeedbackFlashInteraction` through
   `Player.InteractionMaster.AddInteraction` (`PostBeginPlay` for
   standalone/listen host, `PostNetBeginPlay` for network clients, bounded
   `Timer` retries while the Player/InteractionMaster is not ready).
5. The Interaction's `PreRender(Canvas)` calls the proxy's
   `DrawFlash(Canvas)` while
   `0 <= (TimeSeconds - SpawnAt) < FlashDuration`; `Destroyed` removes the
   Interaction again.

Alternatives that were rejected (still relevant for future work):
- *`PlayerController.ClientFlash()`* — the engine's own damage flash is a
  one-liner from the mutator path, but its duration/color are fixed by the
  engine's native implementation, killing the Duration/Color requirement.
- *LocalMessage* — the draw color/lifetime is nailed in message-class
  defaults, no per-player config channel.
- *HudOverlay* — simplest for replication, but always draws after the HUD;
  rejected once the effect had to sit behind it. Kept here as the reason
  the split proxy/Interaction design exists.
- *Custom HUD subclass* — would draw before `Super.PostRender`, but each
  gametype has a different HUD class; wrapping them all is more invasive.

## The visual: quick-in / slow-out screen flash

While the Duration window is open, `DrawFlash(Canvas)` draws **one
full-screen quad** (`Engine.WhiteTexture` 1×1) with
`C.Style = ERenderStyle.STY_Additive` in the configured color:

- **Attack (quick appear):** alpha ramps 0→1 linearly over
  `FClamp(0.10 * Duration, 0.08, 0.8 * Duration)` seconds — GTA flashes
  land fast, but never instantly snap.
- **Decay (slow vanish):** linear alpha = `1 - (t-attack)/(dur-attack)`,
  reaching zero exactly at `Duration`. Linear on purpose: predictable and
  the "slowly vanishes" feel the user described; a power/`exp` curve would
  be a one-line change if it ever feels too flat.
- **Peak intensity:** alpha is multiplied by `FlashIntensity` (0..1), so
  the whole effect is one variable's brightness knob.
- The canvas is fully save/restored around the draw (shared HUD canvas:
  Font/FontScale/Style/DrawColor/Z/Org/Clip/Cur/ColorModulate/bCenter/
  bNoSmooth/bRenderLevel) so no stock overlay inherits our state.

Timing constants sit in a named `const` block at the top of
`FragFeedbackFlash.uc` (`FlashInFrac`, `MinAttackTime`).

## Customization surface (v0.2)

| Setting | Where | Class var |
|---|---|---|
| Duration (0.10-15 s) | [Configure Mutators] | `DurationSec` |
| Color R/G/B (0-1) | [Configure Mutators] | `ColorR`, `ColorG`, `ColorB` |
| Peak intensity | UT2004.ini | `FlashIntensity` |

Ini section: `[FragFeedback.FragFeedbackMutator]` in `UT2004.ini`
(PlayInfo saves there natively, mirroring `RespawnDelay.RespawnDelay`).

Design rule observed throughout: **every tweakable is a `var() config`**
with engine-friendly extras strings (`"8;0.1:15.0"`), so any file-level
setting can graduate into the GUI in one `AddSetting` line.

## Console helper (v0 testing)

- `mutate fragfeedbacktest` — flash the screen immediately (no kill needed)

## Scope cuts in v0.2 (documented, cheap to add later)

- No own-death flash (clientblue V kills show the flash for you too); the
  replicated proxy is already per-player, a `Killed` branch in
  `NotifyFrag` is the whole change.
- No color presets dropdown (R/G/B edits are the general case; a
  `"Select"` preset row could be added like RespawnDelay's presets).
- No flash-granularity extras (screen-fade division, vignette, shake):
  the effect is deliberately one quad, per the clarified goal.

## Build/deploy pipeline

`tools/build.sh` (idempotent):
syncs `source/FragFeedback/Classes/*.uc` → `$UT2004_DIR/FragFeedback/Classes`
(wiping the target dir first so renamed/removed classes cannot linger),
fixes up `EditPackages` (adds `FragFeedback` once, collapses the duplicated
`GTAThirdPerson` lines found in this install), **deletes** the stale
compiled `System/FragFeedback.u` (this engine's `ucc make` can consider a
package up to date after class changes), runs `wine UCC.exe make`,
`wine UCC.exe exportcache FragFeedback.u`, and installs
`install/FragFeedback.int` into `System/`.

`tools/test.sh [map]` launches Instant-Action-like DM with the mutator:
`wine UT2004.exe <map>?game=DeathMatch?mutator=FragFeedback.FragFeedbackMutator`.

## Verification performed

- `ucc make` builds clean (0 errors / 0 warnings; force-rebuild verified
  after the class rename, see the `.u` string dump containing only
  `FragFeedbackFlash`).
- `ucc exportcache` regenerated the mutator `.ucl`.
- Headless `ucc server DM-Corrugation?...?mutator=FragFeedback.FragFeedbackMutator?MinPlayers=8`:
  mutator + rules register with the new defaults
  (`duration=0.50 s, color = 0.20,0.20,0.50 intensity = 0.80`), no runtime
  errors over boot and match start.
- Human screen test (flash pop/decay + GUI knobs): pending, via
  `tools/test.sh` or normal play; `mutate fragfeedbacktest` for a
  no-kill preview.
