# APPROACH — FragFeedback design document

## Goal

"GTA V-like feedback on screen" as **defined by the user**: the GTA V
postprocess feedback — **the screen flashes with a colored full-screen
effect that quickly appears and slowly vanishes**. There are two independent
effects with their own settings:

- **Frag feedback** — fires when you frag an enemy. Default color is the
  GTA-ish cool cyan-blue; default duration 0.5 s.
- **Damage feedback** — fires when you take damage. Default color is a
  mostly transparent red; default duration 0.5 s, matching the frag flash.

Each effect has its own **Color** (R/G/B 0..1) and **Duration** (seconds,
0.0 – 15.0) through the stock **[Configure Mutators]** page (PlayInfo),
exactly like the engine's own mutator settings. A duration of **0**
functionally disables that effect. Peak intensity is a file-level var per
effect (`FlashIntensity`, `DamageFlashIntensity`), one `AddSetting` line
away from the GUI if wanted.

The first prototype (letterbox bars + WASTED-style banner text) was retired
— the user clarified the target gesture was the *flash*; the renaming of its
class to `FragFeedbackFlash` mirrors that.

## Architecture (four classes)

```
FragFeedback package
├── FragFeedbackMutator  (server)  entry point + GUI config + flash proxies
├── FragFeedbackRules    (server)  ScoreKill + NetDamage hooks (GameRules chain)
├── FragFeedbackFlash    (server+client, replicated)  proxy: config + triggers
└── FragFeedbackFlashInteraction (client)  PreRender hook: draws behind HUD
```

### Why GameRules instead of the mutator's own hooks

`Engine.Mutator` is native and its `ScoreKill`/damage hooks are not exposed
as script. `Engine.GameRules` is fully scriptable with a documented chained
API (`GameInfo.AddGameModifier`, `GameRules.ScoreKill(Killer, Killed)`,
`GameRules.NetDamage(...)` + `Super` chain; vanilla precedent:
`UnrealGame.BigHeadRules` and `XGame.VampireGameRules`). The mutator spawns
one `FragFeedbackRules` in `PostBeginPlay` and registers it with
`Level.Game.AddGameModifier(...)`. Chain integrity with other mutators
(RespawnDelay, GTAThirdPerson, vanilla) is preserved by construction.

- `ScoreKill(Killer, Killed)` → `NotifyFrag` → frag flash on the killer.
- `NetDamage(OriginalDamage, Damage, injured, instigatedBy, ...)` →
  chains through `Super.NetDamage` first, then notifies `NotifyDamage` of
  the actual (possibly modified) damage, so gameplay is untouched and
  damage prevented by another rule does not flash.

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
2. The mutator pushes **both** server-side configuration sets (frag and
   damage Color channels, Duration, Intensity) into the proxy's vars; they
   replicate with the initial actor message (`reliable if (bNetInitial &&
   Role == ROLE_Authority)`). In addition, the mutator's 10-second `Timer`
   calls the reliable `ClientApplyConfig(...)` remote on every proxy, so
   the server re-enforces the authoritative values periodically even if a
   client missed the initial bundle. This is what makes the **GUI settings
   reachable and authoritative on network clients**.
3. Per frag, `FragFeedbackRules.ScoreKill` → `Mutator.NotifyFrag`, which
   skips suicides, team kills (team games), bots, and calls the reliable
   remote `ClientShowFlash()` on the killer's proxy.
4. Per damage event, `FragFeedbackRules.NetDamage` →
   `Mutator.NotifyDamage`, which skips zero/negative damage and bots, and
   calls the reliable remote `ClientShowDamageFlash()` on the injured
   player's proxy.
5. On the client, the proxy registers a local
   `FragFeedbackFlashInteraction` through
   `Player.InteractionMaster.AddInteraction` (`PostBeginPlay` for
   standalone/listen host, `PostNetBeginPlay` for network clients, bounded
   `Timer` retries while the Player/InteractionMaster is not ready). At the
   same point it runs `set ini:Engine.Engine.ViewportManager ScreenFlashes
   False`, mirroring the stock Game Settings checkbox so the vanilla damage
   flash does not stack with the mutator's damage flash.
6. The Interaction's `PreRender(Canvas)` calls the proxy's
   `DrawFlash(Canvas)` and `DrawDamageFlash(Canvas)` while each effect's
   `0 <= (TimeSeconds - start) < Duration` window is open; `Destroyed`
   removes the Interaction again. The two windows are independent, so a
   frag and a hit can overlap.

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

Each active effect draws **one full-screen quad** (`Engine.WhiteTexture`
1×1) with `C.Style = ERenderStyle.STY_Additive` in its configured color.
Both effects share the `DrawFlashLayer` helper and therefore the same
quick-in / slow-out envelope:

- **Attack (quick appear):** alpha ramps 0→1 linearly over
  `FClamp(0.10 * Duration, 0.08, 0.8 * Duration)` seconds — GTA flashes
  land fast, but never instantly snap.
- **Decay (slow vanish):** linear alpha = `1 - (t-attack)/(dur-attack)`,
  reaching zero exactly at `Duration`. Linear on purpose: predictable and
  the "slowly vanishes" feel the user described; a power/`exp` curve would
  be a one-line change if it ever feels too flat.
- **Peak intensity:** alpha is multiplied by the effect's intensity
  (`FlashIntensity` or `DamageFlashIntensity`, 0..1). The damage default is
  deliberately low (0.3), giving the requested mostly transparent red hit
  tint.
- The canvas is fully save/restored around the draw (shared HUD canvas:
  Font/FontScale/Style/DrawColor/Z/Org/Clip/Cur/ColorModulate/bCenter/
  bNoSmooth/bRenderLevel) so no stock overlay inherits our state.

Timing constants sit in a named `const` block at the top of
`FragFeedbackFlash.uc` (`FlashInFrac`, `MinAttackTime`).

## Customization surface

| Effect | Setting | Where | Class var |
|---|---|---|---|
| Frag | Duration (0-15 s, 0 disables) | [Configure Mutators] | `DurationSec` |
| Frag | Color R/G/B (0-1) | [Configure Mutators] | `ColorR`, `ColorG`, `ColorB` |
| Frag | Peak intensity | UT2004.ini | `FlashIntensity` |
| Damage | Duration (0-15 s, 0 disables) | [Configure Mutators] | `DamageDurationSec` |
| Damage | Color R/G/B (0-1) | [Configure Mutators] | `DamageColorR`, `DamageColorG`, `DamageColorB` |
| Damage | Peak intensity | UT2004.ini | `DamageFlashIntensity` |

Defaults: frag 0.5 s blue (0.20 / 0.20 / 0.50, intensity 0.8); damage 0.5 s
red (0.75 / 0.0 / 0.0, intensity 0.3). The two groups appear as separate
pages in the [Configure Mutators] screen.

Ini section: `[FragFeedback.FragFeedbackMutator]` in `UT2004.ini`
(PlayInfo saves there natively, mirroring `RespawnDelay.RespawnDelay`).

Design rule observed throughout: **every tweakable is a `var() config`**
with engine-friendly extras strings (`"8;0.0:15.0"`), so any file-level
setting can graduate into the GUI in one `AddSetting` line.

## Vanilla ScreenFlashes override

The stock engine damage flash is controlled by the client option
`ScreenFlashes` (Game Settings → *Screen Flashes*; ini key
`ini:Engine.Engine.ViewportManager ScreenFlashes`). Since the mutator's
damage feedback replaces it, the client-side flash proxy issues the same
console command the GUI uses to set it to `False` when it attaches. This is
a local, persistent config write on each client, exactly like changing the
checkbox by hand; re-enable it if the mutator is later removed.

## Console helpers

- `mutate fragfeedbacktest` — show the frag flash immediately (no kill needed)
- `mutate fragfeedbackdamagetest` — show the damage flash immediately

## Scope cuts (documented, cheap to add later)

- No dedicated own-death treatment (the damage flash also fires on the
  killing blow, but there is no separate "you died" color/curve).
- No color presets dropdown (R/G/B edits are the general case; a
  `"Select"` preset row could be added like RespawnDelay's presets).
- No flash-granularity extras (screen-fade division, vignette, shake):
  each effect is deliberately one quad, per the clarified goal.

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

- `ucc make` builds clean (0 errors / 0 warnings) after the damage-feedback
  and separate-settings changes.
- `ucc exportcache` regenerated the mutator `.ucl`.
- Headless `ucc server DM-Corrugation?...?mutator=FragFeedback.FragFeedbackMutator?MinPlayers=8`
  run after the change: the mutator logs both bundles (`frag duration=0.50 s,
  color = ..., intensity = 0.80; damage duration=0.50 s, color =
  0.75,0.00,0.00 intensity = 0.30`) and boots through match start with no
  runtime errors. The periodic refresh path is exercised by the running
  server (10-second timer) without errors.
- Human screen test (both flash envelopes, GUI groups, duration=0 disable,
  ScreenFlashes override): pending, via `tools/test.sh` or normal play; the
  two `mutate` helpers preview each flash.
