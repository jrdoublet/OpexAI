// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* RAIL-LONG v2 (reglage retire le 18/11) : une transaction V284 de croissance v2 restauree
 * d'une ancienne sauvegarde reste reconnue pour etre annulee proprement. */

function OpexRailLongV2FleetPending(owner)
{
  return owner != null && owner._v284State != null
      && ("pending" in owner._v284State) && owner._v284State.pending != null
      && ("railLongV2" in owner._v284State.pending)
      && owner._v284State.pending.railLongV2;
}

