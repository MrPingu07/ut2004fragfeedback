//=============================================================================
// FragFeedbackRules.uc
//
// Server-side kill and damage hook for the FragFeedback mutator. GameInfo
// calls the GameRulesModifiers chain (GameInfo.ScoreKill/NetDamage ->
// GameRules.ScoreKill/NetDamage), which is exported and fully scriptable in
// UT2004 - safer than depending on the native Engine.Mutator paths. The Super
// calls keep every other mutator's rules intact (explicit chaining like
// BigHeadRules does).
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

function int NetDamage(int OriginalDamage, int Damage, pawn injured,
	pawn instigatedBy, vector HitLocation, out vector Momentum,
	class<DamageType> DamageType)
{
	// chain normally first: the returned value is the actual damage after
	// other mutators/rules have had their say
	Damage = Super.NetDamage(OriginalDamage, Damage, injured, instigatedBy,
		HitLocation, Momentum, DamageType);

	if ( MF != None )
		MF.NotifyDamage(injured, Damage, instigatedBy);

	return Damage;
}

defaultproperties
{
}
