#!/usr/bin/env bash
#
# tools/test.sh - launch a quick instant-action DM match with the mutator
# forced on, for visual verification (Wine).
#
set -euo pipefail

UTDIR="${UT2004_DIR:-/home/jdmr/Juegos/UT2004}"
MAP="${1:-DM-Corrugation}"

cd "$UTDIR/System"
exec wine UT2004.exe "$MAP?game=DeathMatch?mutator=FragFeedback.FragFeedbackMutator"
