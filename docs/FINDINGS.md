# FINDINGS — FragFeedback research notes

Environment, toolchain and engine observations gathered while building the
mutator. Everything below was verified directly against the local game copy
in `/home/jdmr/Juegos/UT2004/` (not from memory or third-party lore).

## The game copy

- `/home/jdmr/Juegos/UT2004/` is the **Windows edition** of UT2004
  (`UT2004.exe`, `System/*.dll`, no Linux binaries; `SystemARM64/` is empty).
- It runs through **Wine** on this machine (wine-staging 11.20). Verified:
  `wine UCC.exe` executes fine and produces normal UnrealScript tool output.
  Build noise to ignore: Wine prints `fixme:winediag` lines to stderr; the
  build script filters them.
- Existing custom mutators already in place: `RespawnDelay` and
  `GTAThirdPerson` (plus older extras: `UT2341Weapons_*`, `InvasionProv1_7`,
  `ClassicDom`, `cDOM*`, `UTClassicCannon`, `AssaultBP`, `Outsider`,
  `StreamlineFX`). Both user mutators were used as living references for
  install + GUI patterns.

## Build toolchain (works through Wine)

| Step | Command (run inside `System/`) | Output |
|---|---|---|
| sources | `$UT/FragFeedback/Classes/*.uc` (+ `EditPackages=FragFeedback` under `[Editor.EditorEngine]` in `UT2004.ini`) | — |
| compile | `wine UCC.exe make` | `System/FragFeedback.u` |
| mutator cache | `wine UCC.exe exportcache FragFeedback.u` | `System/FragFeedback.ucl` |
| localization | hand-written `install/FragFeedback.int` → `System/FragFeedback.int` | mutator-list entry via the `[Public] Object=(...)` line + GUI strings |

- `ucc batchexport <Pkg> Class uc <dir>` works and was used to disassemble
  stock packages (`Engine`, `UnrealGame`, `XGame`, `RespawnDelay`,
  `XInterface`, `IpDrv`) into `.uc` sources. This is the primary research
  technique used for everything engine-related in this document (exports left
  in `$UT/export*` folders, safe to delete).
- First build of FragFeedback compiled with **0 errors / 0 warnings**.

## `UT2004.ini` [Editor.EditorEngine] condition before cleanup

`EditPackages=GTAThirdPerson` was listed **10 times** (accumulated by earlier
brute-force builds). The build tool collapses duplicates (keeps one) and
appends `EditPackages=FragFeedback` exactly once, right after the last
`EditPackages=` line.

## How the [Configure Mutators] GUI actually works (PlayInfo)

- `Engine.PlayInfo` (exported) is a **native** class holding
  `Settings[{ThisProp, SettingName, DisplayName, Description, Grouping, Data,
  Value, RenderType(EPlayInfoType: PIT_Check/PIT_Select/PIT_Text/PIT_Custom),
  Weight, bMPOnly, bAdvanced, bGlobal, bStruct, ArrayDim}]`.
- Objects expose settings via the `static function FillPlayInfo(PlayInfo
  Info)` override and the call
  `static function FillPlayInfo(PlayInfo Info)` and call
  `PlayInfo.AddSetting(Group, PropertyName, DisplayName, SecLevel, Weight,
  RenderType, Extras, ExtraPrivs, bMPOnly, bAdvanced)`.
- **RenderType strings observed in vanilla exports** (`UnrealGame` package):
  - `"Check"`  → checkbox (bool)
  - `"Text"`   → numeric/string edit; the `Extras` string is
    `"<decimals>;<min>:<max>"`, e.g. `"8;0.1:3.5"` for a float 0.1..3.5,
    `"3;0:32"` for an int 0..32
  - `"Select"` → dropdown; `Extras` is a `value;Label;value;Label` pair list
    (values as exact float strings like `5.000000` re-match the ini value)
- Display names/tooltips are provided by the mod itself via
  `GetDisplayText(name)` returning `default.<Var>DisplayText` and
  `static event string GetDescriptionText(string PropName)` (both proven in
  this install by `RespawnDelay`, which ships a single GUI dropdown using
  this exact pattern; vanilla `DeathMatch.uc:1720+` confirms overrides chain
  through `Super.GetDescriptionText`).
- PlayInfo natively saves values into the ini section named
  `[<Package>.<ObjectClass>]` (`RespawnDelay.RespawnDelay`,
  `GTAThirdPerson.GTAThirdPersonMutator` are visible in the inis) — so
  `config(UT2004)` is the right storage class declaration. Verified sections
  in this install's `UT2004.ini` / `GTAThirdPerson.ini`.

## Kill-event hooks: Mutator vs GameRules

- `Engine.Mutator` is native; the export shows the script-side hook set but
  **no `ScoreKill`** (it lives inside the native part).
- `Engine.GameRules` is **fully scriptable** and exports the whole chain:
  `GameInfo.ScoreKill(Killer, Killed)` → `GameRulesModifiers.ScoreKill(...)`
  with explicit `NextGameRules.ScoreKill` chaining; vanilla precedent
  `UnrealGame.BigHeadRules` (`function ScoreKill(Controller Killer,
  Controller Killed)` + `Super/NextGameRules` call). Registered with
  `GameInfo.AddGameModifier(GameRules)` (exported `GameInfo.uc:914`).
- Decision: **FragFeedbackRules extends GameRules** spawns from the mutator
  and chains `Super.ScoreKill`. No dependence on the opaque native Mutator
  hook.

## Rendering HUD from a mutator: options inspected

- `Engine.HudOverlay`: an Actor whose only job is to be drawn by the HUD.
  `HUD.AddHudOverlay(Overlay)` appends it and calls `Overlay.Render(Canvas)`
  from `HUD.PostRender` and the smaller overlay render pass (exported
  `HUD.uc:883` and surrounding code); `RemoveHudOverlay` exists, and
  `HudOverlay.Destroyed` removes itself from the attached HUD.
  - Defaults are local-only (`RemoteRole=ROLE_None`) — a subclass must set
    `RemoteRole=ROLE_SimulatedProxy` to reach network clients.
- `Engine.Interaction` / `InteractionMaster.AddInteraction(...)` can also
  draw HUD on the client, but requires the client machine to run the
  registration code itself (fine through a replicated proxy, but
  HudOverlay is the engine-blessed, narrower path).
- `Engine.LocalMessage` (`ClientReceive`) could spawn client visuals too,
  but carries no per-player configuration channels (only int Switch + PRI
  objects); rejected for our "arbitrary color + duration" requirement.
- **Decision: replicated `HudOverlay`** class `FragFeedbackBanner`
  (`RemoteRole=ROLE_SimulatedProxy`, `bOnlyRelevantToOwner=True`,
  `Owner` = the player's PlayerController), spawned by the server mutator in
  `ModifyPlayer`, pushed one-shot per kill through a reliable
  server→client remote call (`ClientShowBanner`).

## Canvas primitives used (from the exported `Engine.Canvas`)

- `FontScaleX/FontScaleY` are the UT2004 ("gam") additions that scale
  `DrawText` — GTA-style big text. **Measurement caveat**: metrics
  (`TextSize`) were measured with scale forced to 1.0; all scaling math is
  done script-side and applied (`W*S`, `H*S`), so both possible native
  interpretations of `TextSize` under a non-1 scale give identical results.
- `DrawTile(Texture'Engine.WhiteTexture', ...)` for solid rectangles
  (letterbox bars); `Engine.WhiteTexture` is present in `Engine.u`.
- `C.Style = ERenderStyle.STY_Alpha` enables per-color alpha (the letterbox
  fade envelope is implemented with alpha only, no screen fade hacks).
- Text outline/shadow is layered `C.DrawText` (8-way outline + a longer
  down-right drop shadow), matching the GTA V "WASTED" poster look.

## Fonts available in this installation

- There are **no standalone `UT2003Fonts.u` / `2K4Fonts.u` package files**,
  yet vanilla code (`Engine.int` HUD font names, `UT2LargeFont`,
  `fntUT2K4Medium`) references `UT2003Fonts.FontEurostileXY` and
  `2K4Fonts.VerdanaNN` and works in-game. The font objects physically live
  inside `GUI2K4.u` / `XInterface.u` / `Engine.u`; `DynamicLoadObject`
  resolves the same string names at runtime, exactly as vanilla code does
  (verified by string-searching the packages).
- Candidates verified present for this mod:
  - `2K4Fonts.Impact32` — bold condensed, closest GTA/"WASTED" feel →
    default banner font
  - `UT2003Fonts.FontEurostile37` — fallback in code
  - `2K4Fonts.Verdana14` — default subtitle font (Engine.Canvas.default.Font
    as last resort)
- Font selection is a *client-side ini* choice (`BannerFontName`,
  `VictimFontName`) since the font must resolve on the rendering machine.

## Networking notes

- The banner proxy replicates its configuration bundle under
  `reliable if (bNetInitial && Role == ROLE_Authority)` and the per-kill
  trigger under `reliable if (Role == ROLE_Authority) ClientShowBanner`
  (standard UT2004 remote-call shape; the engine executes these locally on
  listen/standalone hosts and forwards them to owners on network clients).
- `Mutator.bAddToServerPackages=True` auto-adds the package to the server
  package map at load (`Engine.Mutator.PreBeginPlay` path), reducing
  package-mismatch errors; remote clients joining an internet/LAN server
  will additionally need the `.u` (redirect or manual copy).

## Environment landmines found during testing (pre-existing, not ours)

- **GameSpy is dead**: `UdpGamespyUplink: Failed to resolve master server
  address`; community replacement masters (333networks, openspy, frag-net…)
  are configured in this install but offline/unreachable in our run.
- **`UdpGamespyQuery.PreBeginPlay` assert crash** when running `ucc server`
  with a custom `port=N`: the port-swap watchdog trips
  (`OldQueryPortNumber` in `UT2004.ini` vs `GamePort+10`). Baseline run
  **without** any mutator reproduces it. Workaround used for testing:
  `bRestartServerOnPortSwap=False`; afterwards the dedicated server boots
  clean with FragFeedback attached.
- `xWebAdmin … BindPort: bind failed` (port 7779 busy) — harmless for our
  tests.
- Wine prints `getaddrinfo failed` noise each resolution attempt.

## What could NOT be verified without a human at the screen

- The in-game **[Configure Mutators] page look & feel** (the PlayInfo flow
  is identical to the user's own working RespawnDelay, so risk is low).
- The visual itself on screen (banner pop, letterbox slide); smoke tests
  exercised the server path (spawn + registration + config propagation) and
  `tools/test.sh` starts the game in DM with the mutator for eyeballing.

## Localized language note

This install's `Language=ute` (= Spanish flavor controls?) with
`SystemLocalized/` folder present; our `.int` is English-only, English
strings are also inlined as class defaults, so nothing breaks. Additional
`.det/.est/...` files can be authored later by copying the int.
