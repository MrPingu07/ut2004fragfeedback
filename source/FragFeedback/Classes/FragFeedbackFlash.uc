//=============================================================================
// FragFeedbackFlash.uc
//
// The on-screen part of the FragFeedback mutator: the GTA V-style screen
// flashes. An Actor proxy spawned by the server mutator with Owner = the
// player's PlayerController, so it replicates only to that player
// (bOnlyRelevantToOwner) and its server->client remote calls land exactly on
// their screen. It carries two independent effects: the frag flash and the
// damage flash, each with its own duration, color and intensity.
//
// Data flow:
//   server mutator (PostBeginPlay config)  -> replicated initial vars at spawn
//   server mutator (ScoreKill)             -> reliable remote call
//                                             ClientShowFlash()
//   server mutator (NetDamage)             -> reliable remote call
//                                             ClientShowDamageFlash()
//   client                                  -> local Interaction PreRender
//                                             -> DrawFlash/DrawDamageFlash
//                                                full-screen quad for the
//                                                effect's Duration window
//
// The flash must render *behind* the HUD, so this class does not use
// HudOverlay (its Render runs after HUD.DrawHud). Instead, TryAttach registers
// a FragFeedbackFlashInteraction on the owning player; the engine calls its
// PreRender before the HUD and the first-person weapon.
//
// Each effect is deliberately minimal (per the user's definition of "GTA
// V-like feedback"):
//
//   a full-screen colored quad drawn STY_Additive with the effect's color
//   that *quickly appears* (alpha ramps up over an attack window, ~10% of
//   the duration) and *slowly vanishes* (linear decay for the rest).
//
// Colors and Durations are configured from the [Configure Mutators] GUI on
// FragFeedbackMutator and arrive here as replicated values; peak intensity
// is a file-level (UT2004.ini) setting per effect.
//=============================================================================
class FragFeedbackFlash extends Actor
	config(UT2004);

// ---------------------------------------------------------------------------
// Server configuration (replicated with the initial actor message)
// ---------------------------------------------------------------------------

/** Total seconds the flash takes from onset to fully gone. */
var float FlashDuration;

/** Flash color channels, 0.0 .. 1.0. Default: the GTA-ish blue. */
var float ColorR;
var float ColorG;
var float ColorB;

/** Peak brightness of the frag flash (applied through the alpha channel). */
var float FlashIntensity;

/** Damage flash: total seconds from onset to fully gone (0 = disabled). */
var float DamageDuration;

/** Damage flash color channels, 0.0 .. 1.0. Default: mostly transparent red. */
var float DamageColorR;
var float DamageColorG;
var float DamageColorB;

/** Peak brightness of the damage flash (applied through the alpha channel). */
var float DamageFlashIntensity;

// ---------------------------------------------------------------------------
// Machine local state
// ---------------------------------------------------------------------------

/** TimeSeconds the frag flash started; 0 = inactive. */
var transient float SpawnAt;

/** TimeSeconds the damage flash started; 0 = inactive. */
var transient float DamageSpawnAt;

/** Vanilla ScreenFlashes has been switched off on this client. */
var transient bool bDisabledVanillaFlashes;

/** Client-side render hook (created locally, one per proxy). */
var transient FragFeedbackFlashInteraction FlashInteraction;

/** Attachment bookkeeping (bounded retries). */
var transient int AttachTries;

// envelope: quick rise, slow linear fall (fractions of FlashDuration)
const FlashInFrac = 0.10;	// alpha ramp-in window
const MinAttackTime = 0.08;	// even a 0.5 s flash pops in fast (seconds)

// ---------------------------------------------------------------------------
// Replication
// ---------------------------------------------------------------------------

replication
{
	// server -> client: initial configuration bundle
	reliable if ( bNetInitial && (Role == ROLE_Authority) )
		FlashDuration, ColorR, ColorG, ColorB, FlashIntensity,
		DamageDuration, DamageColorR, DamageColorG, DamageColorB,
		DamageFlashIntensity;

	// server -> client: one-shot triggers (owner-only actor)
	reliable if ( Role == ROLE_Authority )
		ClientShowFlash, ClientShowDamageFlash;

	// server -> client: periodic authoritative settings refresh (every 10 s)
	reliable if ( Role == ROLE_Authority )
		ClientApplyConfig;
}

// ---------------------------------------------------------------------------
// Server->client trigger
// ---------------------------------------------------------------------------

simulated function ClientShowFlash()
{
	if ( Level.NetMode == NM_DedicatedServer )
		return;

	SpawnAt = Level.TimeSeconds;
}

simulated function ClientShowDamageFlash()
{
	if ( Level.NetMode == NM_DedicatedServer )
		return;

	DamageSpawnAt = Level.TimeSeconds;
}

/**
 * Periodically called by the server mutator (every 10 seconds) to re-apply
 * the authoritative configuration on the client. Initial values still arrive
 * with the actor's bNetInitial bundle; this keeps them enforced afterwards.
 */
simulated function ClientApplyConfig(float NewFlashDuration,
	float NewColorR, float NewColorG, float NewColorB, float NewFlashIntensity,
	float NewDamageDuration, float NewDamageColorR, float NewDamageColorG,
	float NewDamageColorB, float NewDamageFlashIntensity)
{
	if ( Level.NetMode == NM_DedicatedServer )
		return;

	FlashDuration		= NewFlashDuration;
	ColorR			= NewColorR;
	ColorG			= NewColorG;
	ColorB			= NewColorB;
	FlashIntensity		= NewFlashIntensity;
	DamageDuration		= NewDamageDuration;
	DamageColorR		= NewDamageColorR;
	DamageColorG		= NewDamageColorG;
	DamageColorB		= NewDamageColorB;
	DamageFlashIntensity	= NewDamageFlashIntensity;
}

// ---------------------------------------------------------------------------
// Render-hook attachment (three cases)
//   NM_Standalone / listen-server host : PostBeginPlay (local Player exists)
//   network client                     : PostNetBeginPlay
//   early or missing InteractionMaster : bounded Timer retries
// ---------------------------------------------------------------------------

simulated event PostBeginPlay()
{
	if ( Level.NetMode == NM_DedicatedServer )
		return;	// server role only: no screen to attach to

	TryAttach();
}

simulated event PostNetBeginPlay()
{
	TryAttach();
}

simulated function TryAttach()
{
	local PlayerController			PC;
	local FragFeedbackFlashInteraction	I;

	if ( FlashInteraction != None || Level.NetMode == NM_DedicatedServer )
		return;

	PC = PlayerController(Owner);
	if ( PC == None || PC.Player == None || PC.Player.InteractionMaster == None )
	{
		AttachTries += 1;
		if ( AttachTries <= 10 )
			SetTimer(0.25, true);
		return;
	}

	// This mutator replaces the stock damage flash; switch the client's
	// ScreenFlashes option off so the two effects do not stack.
	DisableVanillaScreenFlashes(PC);

	// Local Interaction: the engine feeds it PreRender() right after the
	// world is drawn and before HUD.PostRender (unlike HudOverlay, whose
	// Render runs after DrawHud and therefore covers the HUD).
	I = FragFeedbackFlashInteraction(
		PC.Player.InteractionMaster.AddInteraction(
			"FragFeedback.FragFeedbackFlashInteraction", PC.Player));
	if ( I == None )
	{
		AttachTries += 1;
		if ( AttachTries <= 10 )
			SetTimer(0.25, true);
		return;
	}

	I.Flash = Self;
	FlashInteraction = I;
}

/**
 * Switch the client's vanilla ScreenFlashes option off (UT2004.ini, the same
 * ini key the stock Game Settings checkbox writes). The mutator's damage
 * flash is the replacement, so leaving the vanilla one on would double the
 * effect. The write is local to each client and persists like a GUI change.
 */
simulated function DisableVanillaScreenFlashes(PlayerController PC)
{
	if ( bDisabledVanillaFlashes || PC == None )
		return;

	PC.ConsoleCommand("set ini:Engine.Engine.ViewportManager ScreenFlashes False");
	bDisabledVanillaFlashes = True;
}

simulated function Timer()
{
	SetTimer(0.0, false);		// one-shot poll
	if ( FlashInteraction == None )
		TryAttach();
}

simulated function Destroyed()
{
	if ( FlashInteraction != None )
	{
		FlashInteraction.Cleanup();
		FlashInteraction = None;
	}

	Super.Destroyed();
}

// ---------------------------------------------------------------------------
// Rendering (called from FragFeedbackFlashInteraction.PreRender)
// ---------------------------------------------------------------------------

simulated function DrawFlash(Canvas C)
{
	DrawFlashLayer(C, SpawnAt, FlashDuration, ColorR, ColorG, ColorB, FlashIntensity);
}

simulated function DrawDamageFlash(Canvas C)
{
	DrawFlashLayer(C, DamageSpawnAt, DamageDuration,
		DamageColorR, DamageColorG, DamageColorB, DamageFlashIntensity);
}

simulated function DrawFlashLayer(Canvas C, float StartAt, float Duration,
	float R, float G, float B, float Intensity)
{
	local float	Elapsed, Alpha, AttackTime;
	local Font	OldFont;
	local float OldSX, OldSY, OldOrgX, OldOrgY, OldClipX, OldClipY, OldCurX, OldCurY, OldCurYL;
	local byte	OldStyle, OldZ;
	local color	OldColor;
	local Plane OldColorModulate;
	local bool	OldCenter, OldNoSmooth, OldRenderLevel;

	if ( Level.NetMode == NM_DedicatedServer || StartAt <= 0.0 )
		return;

	Elapsed = Level.TimeSeconds - StartAt;
	if ( Duration <= 0.0 || Elapsed < 0.0 || Elapsed >= Duration )
		return;

	// envelope: quick ramp-up, slow linear decline to zero at Duration
	AttackTime = FClamp(FlashInFrac * Duration, MinAttackTime, Duration * 0.8);
	if ( Elapsed < AttackTime )
		Alpha = Elapsed / AttackTime;
	else if ( Elapsed < Duration )
		Alpha = 1.0 - (Elapsed - AttackTime) / (Duration - AttackTime);
	else
		return;

	Alpha = FClamp(Alpha, 0.0, 1.0) * FClamp(Intensity, 0.0, 1.0);
	if ( Alpha <= 0.01 )
		return;

	// remember this shared canvas's state, we are about to paint it over
	OldFont			= C.Font;
	OldSX			= C.FontScaleX;
	OldSY			= C.FontScaleY;
	OldStyle		= C.Style;
	OldColor		= C.DrawColor;
	OldZ			= C.Z;
	OldOrgX			= C.OrgX;
	OldOrgY			= C.OrgY;
	OldClipX		= C.ClipX;
	OldClipY		= C.ClipY;
	OldCurX			= C.CurX;
	OldCurY			= C.CurY;
	OldCurYL		= C.CurYL;
	OldColorModulate	= C.ColorModulate;
	OldCenter		= C.bCenter;
	OldNoSmooth		= C.bNoSmooth;
	OldRenderLevel		= C.bRenderLevel;

	// the flash: full-screen additive quad in the configured color
	C.Style		= ERenderStyle.STY_Additive;
	C.SetDrawColor(ChannelByte(R), ChannelByte(G), ChannelByte(B),
		int(255.0 * Alpha));
	C.SetPos(0.0, 0.0);
	C.DrawTile(Texture'Engine.WhiteTexture', C.ClipX, C.ClipY, 0.0, 0.0, 1.0, 1.0);

	// HUD shared canvas: hand it back exactly as we found it
	C.Font			= OldFont;
	C.FontScaleX	= OldSX;
	C.FontScaleY	= OldSY;
	C.Style			= OldStyle;
	C.DrawColor		= OldColor;
	C.Z				= OldZ;
	C.OrgX			= OldOrgX;
	C.OrgY			= OldOrgY;
	C.ClipX			= OldClipX;
	C.ClipY			= OldClipY;
	C.CurX			= OldCurX;
	C.CurY			= OldCurY;
	C.CurYL			= OldCurYL;
	C.ColorModulate	= OldColorModulate;
	C.bCenter		= OldCenter;
	C.bNoSmooth		= OldNoSmooth;
	C.bRenderLevel	= OldRenderLevel;
}

/** Round a 0.0-1.0 channel float to a color byte. */
simulated function byte ChannelByte(float Channel)
{
	return byte(FClamp(Channel, 0.0, 1.0) * 255.0 + 0.5);
}

// ---------------------------------------------------------------------------
// Defaults: passive Actor defaults plus sane network behavior for a
// per-player proxy; live values arrive replicated from the mutator
// ---------------------------------------------------------------------------

defaultproperties
{
	FlashDuration=0.500000
	ColorR=0.200000
	ColorG=0.200000
	ColorB=0.500000
	FlashIntensity=0.800000
	DamageDuration=0.500000
	DamageColorR=0.750000
	DamageColorG=0.000000
	DamageColorB=0.000000
	DamageFlashIntensity=0.300000

	// tiny passive screen quad
	RemoteRole=ROLE_SimulatedProxy
	bOnlyRelevantToOwner=True
	bHidden=True
	bStatic=False
	bCollideActors=False
	bBlockActors=False
	bBlockKarma=False
	bBlockPlayers=False
	bNoDelete=False
	bNetTemporary=False
	bAlwaysRelevant=False
	bReplicateMovement=False
	DrawType=DT_None
}
