//=============================================================================
// FragFeedbackFlashInteraction.uc
//
// Client-side render hook for the FragFeedback screen flash.
//
// Why this class exists: HudOverlay.Render is called by HUD.PostRender *after*
// DrawHud, so anything a HudOverlay draws lands on top of the HUD. The engine
// calls Interaction.PreRender right after the world is rendered and *before*
// the HUD (and the first-person weapon), which is the layer this effect wants.
//
// The Interaction is a plain Object (not an Actor) and is created locally by
// FragFeedbackFlash on the client that owns the flash proxy. It only forwards
// PreRender to that proxy's DrawFlash/DrawDamageFlash; configuration and the
// per-event triggers still replicate through the Actor.
//=============================================================================
class FragFeedbackFlashInteraction extends Interaction;

/** The replicated flash proxy this interaction renders. */
var FragFeedbackFlash Flash;

// ---------------------------------------------------------------------------
// Render hook: runs before the HUD draws anything
// ---------------------------------------------------------------------------

function PreRender(Canvas C)
{
	if ( Flash != None )
	{
		Flash.DrawFlash(C);
		Flash.DrawDamageFlash(C);
	}
}

// ---------------------------------------------------------------------------
// Detach when the proxy actor is destroyed
// ---------------------------------------------------------------------------

function Cleanup()
{
	if ( Master != None )
		Master.RemoveInteraction(Self);

	Flash = None;
	Master = None;
}

defaultproperties
{
	// InteractionMaster only calls PreRender/PostRender on visible interactions
	bVisible=True
	bActive=False
	bRequiresTick=False
}
