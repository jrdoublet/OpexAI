// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* V190-FIX2 (reglage v190_fix_directional retire le 18/11) : primitives de pose et de
 * signalisation PBS_ONEWAY conservees pour RAIL-LOOP (rail_loop.nut). Tout echec est
 * fail-closed et annule les seuls changements de la fonction appelante. */

function OpexV190Fix2Rollback(placedRails, placedSignals)
{
  for (local s = placedSignals.len() - 1; s >= 0; s--) {
    AIRail.RemoveSignal(placedSignals[s].tile, placedSignals[s].front);
  }
  for (local k = placedRails.len() - 1; k >= 0; k--) {
    local rec = placedRails[k];
    AIRail.RemoveRail(rec.prev, rec.cur, rec.next);
  }
}

/* Le moteur filtre les virages a 90 deg entre DEUX cases adjacentes avec
 * pf.forbid_90_deg=1 (defaut de nos duels). AreTilesConnected ne le fait PAS.
 * Masques OpenTTD 15.3 track_type.h / track_data.h :
 * X=1, Y=2, UPPER=4, LOWER=8, LEFT=16, RIGHT=32 ;
 * X croise Y ; UPPER/LOWER croisent LEFT/RIGHT.
 * Deduction d'un unique track pour un trajet prev-cur-next, y compris sur
 * un aiguillage qui porte plusieurs rails. 0 = trajet illisible. */
function OpexV190Fix2TrackBit(prev, cur, next)
{
  if (!AIMap.IsValidTile(prev) || !AIMap.IsValidTile(cur) ||
      !AIMap.IsValidTile(next) ||
      AIMap.DistanceManhattan(prev, cur) != 1 ||
      AIMap.DistanceManhattan(cur, next) != 1 || prev == next) return 0;
  local ax = AIMap.GetTileX(prev) - AIMap.GetTileX(cur);
  local ay = AIMap.GetTileY(prev) - AIMap.GetTileY(cur);
  local bx = AIMap.GetTileX(next) - AIMap.GetTileX(cur);
  local by = AIMap.GetTileY(next) - AIMap.GetTileY(cur);
  if (ay == 0 && by == 0 && ax == -bx) return 1; // X : E-W
  if (ax == 0 && bx == 0 && ay == -by) return 2; // Y : N-S
  if ((ax == -1 && by == -1) || (bx == -1 && ay == -1)) return 4;  // UPPER : W-N
  if ((ax == 1 && by == 1) || (bx == 1 && ay == 1)) return 8;     // LOWER : E-S
  if ((ay == -1 && bx == 1) || (by == -1 && ax == 1)) return 16;  // LEFT : N-E
  if ((ax == -1 && by == 1) || (bx == -1 && ay == 1)) return 32;  // RIGHT : W-S
  return 0;
}

/* Renvoie null pour une entree PBS sur structure ou courbe incertaine.
 * Aucun repli en PBS bidirectionnel, qui autoriserait le contre-sens. */
function OpexV190Fix2PlaceSignal(tiles, index, toward, placedSignals)
{
  if (index <= 1 || index >= tiles.len() - 2) return false;
  local tile = tiles[index];
  local prev = tiles[index - 1];
  local next = tiles[index + 1];
  /* AIRail.front est le cote vers lequel REGARDE le signal, donc celui
   * d'ou approche la locomotive. Voie1 croissante : arrivee depuis prev ;
   * voie2 decroissante : arrivee depuis next. */
  local front = toward > 0 ? prev : next;
  if (!AIMap.IsValidTile(tile) || AIMap.DistanceManhattan(prev, tile) != 1 ||
      AIMap.DistanceManhattan(tile, next) != 1 ||
      AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile) ||
      !AIRail.IsRailTile(tile) || AIRail.IsRailStationTile(tile) ||
      OpexTileTrackCount(tile) != 1 ||
      !AIRail.AreTilesConnected(prev, tile, next) ||
      AIRail.GetSignalType(tile, prev) != AIRail.SIGNALTYPE_NONE ||
      AIRail.GetSignalType(tile, next) != AIRail.SIGNALTYPE_NONE) return false;
  if (!("SIGNALTYPE_PBS_ONEWAY" in AIRail) ||
      !AIRail.BuildSignal(tile, front, AIRail.SIGNALTYPE_PBS_ONEWAY)) return false;
  if (AIRail.GetSignalType(tile, front) != AIRail.SIGNALTYPE_PBS_ONEWAY) {
    AIRail.RemoveSignal(tile, front);
    return false;
  }
  placedSignals.append({ tile = tile, front = front });
  return true;
}

/* Un obstacle ponctuel (pont, courbe, rail non signalable) ne doit pas
 * condamner tous les PBS : chercher un candidat dans le bloc de longueur
 * spacing, sans rapprocher les signaux consecutifs sous ce minimum. */
function OpexV190Fix2PlaceSignalWindow(tiles, start, end, step, toward,
                                      placedSignals)
{
  for (local k = start; step > 0 ? k <= end : k >= end; k += step) {
    if (OpexV190Fix2PlaceSignal(tiles, k, toward, placedSignals)) return k;
  }
  return -1;
}

