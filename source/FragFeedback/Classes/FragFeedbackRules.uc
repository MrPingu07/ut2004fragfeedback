//=============================================================================
// FragFeedbackRules.uc
//
// Server-side kill hook for the FragFeedback mutator. GameInfo calls the
// GameRulesModifiers chain (GameInfo.ScoreKill -> GameRules.ScoreKill), which
// is exported and fully scriptable in UT2004 - safer than depending on the
// native Engine.Mutator.ScoreKill path. The Super call keeps every other
// mutator's rules intact (explicit chaining like BigHeadRules does).
//=============================================================================
class FragFeedbackRules extends GameRules;

/** The mutator that spawned this rules object. */
var FragFeedbackMutator MF;

function ScoreKill(Controller Killer, Controller Killed)
{
	if ( MF != None )
		MF.NotifyFrag(Killer, Killed);

	// never break the chains: vanilla behavior and other mutators keep going
	Super.ScoreKill(Killer, Killed);
}

defaultproperties
{
}
