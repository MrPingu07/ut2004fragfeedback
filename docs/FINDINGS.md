# FINDINGS — FragFeedback research notes

Environment, toolchain and engine observations gathered while building the
mutator. Everything below was verified directly against the local game copy
in `/home/jdmr/Juegos/UT2004/` (not from memory or third-party lore).

> Rework note (v0.1 → v0.2): the first build rendered a letterbox + big
> WASTED-style banner, because "GTA V-like" was read as the death-frame
> gesture. The user clarified it means the **blue kill flash**; the class
> was renamed `FragFeedbackBanner` → `FragFeedbackFlash` and its code
> reduced to a single full-screen additive quad. The research that only
> concerned fonts/letterbox is kept below (it is still useful for any
> future text overlay), clearly marked as such.

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
  - **Not usable for a behind-the-HUD effect**: in `HUD.PostRender`,
    `Overlays[i].Render(Canvas)` (line 325) runs after `DrawHud(Canvas)`
    (line 322), so an overlay always covers the HUD.
- `Engine.Interaction`: `PreRender(Canvas)` is called right after the world
  is rendered but **before the HUD and the first-person weapon**;
  `PostRender(Canvas)` runs after the HUD. Registered client-side through
  `Player.InteractionMaster.AddInteraction(Name, Player)` (or a global
  interaction without the Player), and removed with `RemoveInteraction`.
  - Only interactions with `bVisible=True` are rendered.
  - It is an Object, not an Actor: it cannot be replicated itself. The
    client must create it locally (our replicated flash proxy does this).
- `Engine.LocalMessage` (`ClientReceive`) could spawn client visuals too,
  but carries no per-player configuration channels (only int Switch + PRI
  objects); rejected for our "arbitrary color + duration" requirement.
- **Decision: replicated `FragFeedbackFlash` Actor + local
  `FragFeedbackFlashInteraction`** (the proxy was renamed from the
  prototype's `FragFeedbackBanner`; it used to be a `HudOverlay`).
  The Actor (`RemoteRole=ROLE_SimulatedProxy`,
  `bOnlyRelevantToOwner=True`, `Owner` = the player's PlayerController) is
  spawned by the server mutator in `ModifyPlayer` and pushed one-shot per
  kill through a reliable server→client remote call (`ClientShowFlash`).
  On the client it registers the Interaction, whose `PreRender` calls the
  proxy's `DrawFlash` — giving the flash a layer behind the HUD.

## Canvas primitives used (from the exported `Engine.Canvas`)

- `FontScaleX/FontScaleY` are the UT2004 ("gam") additions that scale
  `DrawText` — (banner-era note: used for the big text; the current flash
  makes no fonts calls at all, and the canvas is fully save/restored
  around each draw).
- `DrawTile(Texture'Engine.WhiteTexture', ...)` for the flash quad; the
  full effect is one quad drawn with `C.Style =
  ERenderStyle.STY_Additive` and the fade envelope carried by the
  DrawColor alpha byte — stock engine texture and stock blend path, no
  custom materials needed.
- Shared-canvas courtesy: the Interaction `PreRender` canvas is the same
  one the HUD and first-person weapon draw on immediately afterwards, so
  `DrawFlash(Canvas)` must restore every canvas property it touches
  (Font, FontScaleX/Y, Style, DrawColor, Z, OrgX/Y, ClipX/Y, CurX/Y,
  CurYL, ColorModulate, bCenter, bNoSmooth, bRenderLevel) — done in
  `FragFeedbackFlash.DrawFlash`.

## Fonts available in this installation (banner-era research, kept for the record)

*(Only relevant to the retired v0.1 banner or any future text overlay; the
flash draws no text.)*

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
- Font selection in v0.1 was a *client-side ini* choice (`BannerFontName`,
  `VictimFontName`); the flash needs no fonts at all.

## Networking notes

- The flash proxy replicates its configuration bundle under
  `reliable if (bNetInitial && Role == ROLE_Authority)` and the per-kill
  trigger under `reliable if (Role == ROLE_Authority) ClientShowFlash`
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
- The visual itself on screen (flash pop/decay); smoke tests
  exercised the server path (spawn + registration + config propagation) and
  `tools/test.sh` starts the game in DM with the mutator for eyeballing.

## Localized language note

This install's `Language=ute` (= Spanish flavor controls?) with
`SystemLocalized/` folder present; our `.int` is English-only, English
strings are also inlined as class defaults, so nothing breaks. Additional
`.det/.est/...` files can be authored later by copying the int.
