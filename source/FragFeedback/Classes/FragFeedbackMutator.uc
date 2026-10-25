//=============================================================================
// FragFeedbackMutator.uc
//
// GTA V-style frag feedback for UT2004: when *you* frag an enemy, your screen
// does the GTA postprocess feedback - a full-screen colored flash (blue by
// default) that quickly appears and slowly vanishes. The Color (RGB 0-1) and
// Duration (seconds) are exposed to the [Configure Mutators] GUI through the
// PlayInfo system (the same mechanism RespawnDelay uses in this install), so
// they are tunable from the game's own mutator screen without editing any
// file.
//
// Class layout (rationale in docs/APPROACH.md):
//
//   FragFeedbackMutator  (this class, server side)
//     - entry point required by the mutator lists (see the note at the top of
//       Engine.Mutator: "ucc dumpint" / "ucc exportcache" generate the .int
//       and .ucl cache entries)
//     - owns the GUI variables (PlayInfo) and pushes them into each player's
//       flash proxy at spawn time
//
//   FragFeedbackRules    (Engine.GameRules subclass, server side)
//     - hooks GameInfo.ScoreKill(Killer, Killed) chained via Super so the
//       vanilla rules and other mutators keep working
//
//   FragFeedbackFlash    (Engine.HudOverlay subclass, one per human player)
//     - replicated proxy that lives where the player's screen lives; it draws
//       the full-screen colored flash (quick in, slow out)
//
// Console helper (instant action / listen server):
//   mutate fragfeedbacktest     show the flash without killing anyone
//
// The canonical source of these files lives in the project repository and is
// synced into /home/jdmr/Juegos/UT2004/FragFeedback/Classes by tools/build.sh
// (Windows edition of the game running through Wine; see README.md and
// docs/FINDINGS.md).
//=============================================================================
class FragFeedbackMutator extends Mutator
	config(UT2004);

// ---------------------------------------------------------------------------
// Configuration - exposed to the [Configure Mutators] GUI (PlayInfo)
// ---------------------------------------------------------------------------

/** Total seconds from flash onset to fully gone. */
var() config float DurationSec;

/** Flash color channels: 0.0 (black) .. 1.0 (full). Default GTA-ish blue. */
var() config float ColorR;
var() config float ColorG;
var() config float ColorB;

// ---------------------------------------------------------------------------
// Configuration - file level (UT2004.ini, section [FragFeedback.FragFeedbackMutator])
// ---------------------------------------------------------------------------

/** Peak brightness of the flash (applied through the alpha channel). */
var() config float FlashIntensity;

// ---------------------------------------------------------------------------
// Localization (FragFeedback.int; defaults duplicated below so the mutator
// still works if the int ever goes missing)
// ---------------------------------------------------------------------------

var() localized string FlashGroup;			// page header in the mutator GUI
var() localized string DurationDisplayText;	// name of the duration field
var() localized string DurationDescText;	// tooltip of the duration field
var() localized string ColorRDisplayText;
var() localized string ColorRDescText;
var() localized string ColorGDisplayText;
var() localized string ColorGDescText;
var() localized string ColorBDisplayText;
var() localized string ColorBDescText;
var() localized string MsgTestShown;		// confirm the fake test flash

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

/** One flash proxy per human player (parallel array, Owner = that player). */
var array<FragFeedbackFlash> Flashes;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

function PostBeginPlay()
{
	local FragFeedbackRules GR;

	Super.PostBeginPlay();

	if ( Level.Game == None )
		return;

	// ScoreKill is noticed through a dedicated GameRules modifier: the
	// GameInfo -> GameRulesModifiers chain is exported and fully scriptable.
	GR = Spawn(class'FragFeedbackRules');
	if ( GR != None )
	{
		GR.MF = Self;
		Level.Game.AddGameModifier(GR);
	}
	else
		log("FragFeedbackMutator: could not spawn FragFeedbackRules", 'FragFeedback');

	log("FragFeedback enabled: duration="$DurationSec@"s, color ="
		@ ColorR$","$ColorG$","$ColorB@"intensity ="@FlashIntensity, 'FragFeedback');
}

// ---------------------------------------------------------------------------
// Player setup: every (re)spawn of a human gets a persistent HUD proxy with
// the server configuration replicated into it. Bots don't get one (no screen).
// ---------------------------------------------------------------------------

function ModifyPlayer(Pawn Other)
{
	Super.ModifyPlayer(Other);

	if ( PlayerController(Other.Controller) != None )
		SpawnFlash(PlayerController(Other.Controller));
}

function FragFeedbackFlash GetFlashFor(PlayerController PC)
{
	local int i;

	for ( i = 0; i < Flashes.Length; i++ )
		if ( Flashes[i] != None && Flashes[i].Owner == PC )
			return Flashes[i];
	return None;
}

function FragFeedbackFlash SpawnFlash(PlayerController PC)
{
	local FragFeedbackFlash F;

	if ( PC == None )
		return None;

	F = GetFlashFor(PC);
	if ( F != None )
		return F;

	F = Spawn(class'FragFeedbackFlash', PC);	// Owner = that player's PC
	if ( F == None )
	{
		log("FragFeedbackMutator: flash spawn failed for "$PC, 'FragFeedback');
		return None;
	}
	F.FlashDuration	= DurationSec;
	F.ColorR		= ColorR;
	F.ColorG		= ColorG;
	F.ColorB		= ColorB;
	F.FlashIntensity	= FlashIntensity;

	Flashes[Flashes.Length] = F;
	return F;
}

// ---------------------------------------------------------------------------
// Kill event (driven by FragFeedbackRules.ScoreKill)
// ---------------------------------------------------------------------------

function NotifyFrag(Controller Killer, Controller Killed)
{
	local PlayerController	PC;
	local FragFeedbackFlash	F;

	if ( Level.Game == None || Level.Game.bGameEnded )
		return;
	if ( Killer == None || Killed == None || Killer == Killed )
		return;

	// no flash for team kills in team games
	if ( Level.Game.bTeamGame
		&& Killer.PlayerReplicationInfo != None && Killed.PlayerReplicationInfo != None
		&& Killer.PlayerReplicationInfo.Team != None
		&& Killer.PlayerReplicationInfo.Team == Killed.PlayerReplicationInfo.Team )
		return;

	// only humans have screens; bots draw nothing
	PC = PlayerController(Killer);
	if ( PC == None )
		return;

	F = SpawnFlash(PC);
	if ( F != None )
		F.ClientShowFlash();
}

/** A leaving player drops their proxy so it never leaks. */
function NotifyLogout(Controller Exiting)
{
	local int i;

	for ( i = 0; i < Flashes.Length; i++ )
	{
		if ( Flashes[i] != None && Flashes[i].Owner == Exiting )
		{
			Flashes[i].Destroy();
			Flashes.Remove(i, 1);
		}
	}

	Super.NotifyLogout(Exiting);
}

// ---------------------------------------------------------------------------
// Console helper
// ---------------------------------------------------------------------------

function Mutate(string MutateString, PlayerController Sender)
{
	local FragFeedbackFlash F;

	if ( Sender != None && MutateString ~= "fragfeedbacktest" )
	{
		F = SpawnFlash(Sender);
		if ( F != None )
		{
			F.ClientShowFlash();
			Sender.ClientMessage(MsgTestShown);
		}
		return;
	}

	Super.Mutate(MutateString, Sender);
}

// ---------------------------------------------------------------------------
// Mutator GUI (PlayInfo - "Configure" button after picking the mutator).
// Property names MUST match the config vars above exactly (PlayInfo natively
// validates them against the class). Extras format: "<decimals>;<min>:<max>".
// ---------------------------------------------------------------------------

static function FillPlayInfo(PlayInfo PlayInfo)
{
	Super.FillPlayInfo(PlayInfo);	// always begin with the parent

	PlayInfo.AddSetting(default.FlashGroup, "DurationSec",
		default.DurationDisplayText, 0, 1, "Text", "8;0.1:15.0");

	PlayInfo.AddSetting(default.FlashGroup, "ColorR",
		default.ColorRDisplayText, 0, 2, "Text", "8;0.0:1.0");

	PlayInfo.AddSetting(default.FlashGroup, "ColorG",
		default.ColorGDisplayText, 0, 3, "Text", "8;0.0:1.0");

	PlayInfo.AddSetting(default.FlashGroup, "ColorB",
		default.ColorBDisplayText, 0, 4, "Text", "8;0.0:1.0");
}

static function string GetDisplayText(string PropName)
{
	return "";
}

static event string GetDescriptionText(string PropName)
{
	if ( PropName ~= "DurationSec" )
		return default.DurationDescText;
	if ( PropName ~= "ColorR" )
		return default.ColorRDescText;
	if ( PropName ~= "ColorG" )
		return default.ColorGDescText;
	if ( PropName ~= "ColorB" )
		return default.ColorBDescText;

	return "";
}

// ---------------------------------------------------------------------------
// Defaults (FragFeedback.int overrides them; see source docs)
// ---------------------------------------------------------------------------

defaultproperties
{
	// GUI
	DurationSec=0.500000
	ColorR=0.200000
	ColorG=0.200000
	ColorB=0.500000

	// file level
	FlashIntensity=0.800000

	// mutator GUI strings (localized again in FragFeedback.int)
	FlashGroup="Frag Feedback"
	DurationDisplayText="Duration (seconds)"
	DurationDescText="Total seconds the colored screen flash takes from its quick onset to fully gone, after each of your frags."
	ColorRDisplayText="Color R (0-1)"
	ColorRDescText="Red channel of the flash. GTA-ish blue default is 0.15 / 0.45 / 1.00; a red flash would be 0.9 / 0.05 / 0.05."
	ColorGDisplayText="Color G (0-1)"
	ColorGDescText="Green channel of the flash."
	ColorBDisplayText="Color B (0-1)"
	ColorBDescText="Blue channel of the flash."
	MsgTestShown="FragFeedback: fake flash displayed."

	// engine wiring
	bAddToServerPackages=True
}
