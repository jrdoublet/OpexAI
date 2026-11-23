// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* Geometrie de l'ancien DOUBLE-GROW (reglage retire le 18/11), conservee pour RAIL-LOOP :
 * trace primaire exact, verification et virages. Requiert builder_rail et rail_pair_geometry.
 */

/* Refuser les traces approximatives : OpexTraceTrackTiles peut s'arreter sur
 * un autre quai du meme StationID et choisit la premiere branche trouvee.
 * V271 impose la sortie exacte et refuse les embranchements ambigus. */
function OpexDoubleGrowPrimaryRoute(line)
{
  local planA = line.platformA;
  local planB = line.platformB;
  if (planA == null || planB == null || !("lead" in planA) ||
      !("station_exit" in planA) || !("station_exit" in planB) ||
      !("lead" in planB) || !("anchor" in planA) ||
      !("anchor" in planB) || !("step" in planA) ||
      !("step" in planB) || !("length" in planA) ||
      !("length" in planB) || !("direction" in planA) ||
      !("direction" in planB)) return null;
  if (planA.length < 2 || planB.length < 2 ||
      AIMap.DistanceManhattan(planA.station_exit, planA.lead) != 1 ||
      AIMap.DistanceManhattan(planB.station_exit, planB.lead) != 1 ||
      AIStation.GetStationID(planA.station_exit) != AIStation.GetStationID(line.stationA) ||
      AIStation.GetStationID(planB.station_exit) != AIStation.GetStationID(line.stationB)) return null;
  local route = OpexV271TraceTrackTiles(planA.station_exit, planA.lead,
                                      planB.station_exit, true);
  if (route == null || route.len() < 36 ||
      route[0] != planA.station_exit || route[1] != planA.lead ||
      route[route.len() - 2] != planB.lead ||
      route[route.len() - 1] != planB.station_exit) return null;
  return route;
}

/* Verifie AUSSI les structures : AreTilesConnected ne s'applique pas aux
 * deux extremites non adjacentes d'un pont ou d'un tunnel. Aucun usage de
 * la presence des signaux comme preuve de connectivite. */
function OpexDoubleGrowVerifyRoute(tiles, planA, planB)
{
  if (tiles == null || tiles.len() < 3 || planA == null || planB == null ||
      tiles[0] != planA.station_exit || tiles[tiles.len() - 1] != planB.station_exit)
    return false;
  local own = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
  foreach (plan in [planA, planB]) {
    for (local j = 0; j < plan.length; j++) {
      local t = plan.anchor + j * plan.step;
      if (!AIRail.IsRailStationTile(t) || AITile.GetOwner(t) != own) return false;
    }
  }
  local last = tiles.len() - 1;
  if (!OpexRailEndConnected(tiles[0], tiles[1], tiles[2], "A") ||
      !OpexRailEndConnected(tiles[last], tiles[last - 1], tiles[last - 2], "B"))
    return false;
  for (local i = 1; i < last; i++) {
    local prev = tiles[i - 1];
    local cur = tiles[i];
    local next = tiles[i + 1];
    if (!AIMap.IsValidTile(cur) || AITile.GetOwner(cur) != own) return false;
    local dPrev = AIMap.DistanceManhattan(prev, cur);
    local dNext = AIMap.DistanceManhattan(cur, next);
    if (dPrev > 1) {
      if (!(AIBridge.IsBridgeTile(cur) && AIBridge.GetOtherBridgeEnd(cur) == prev) &&
          !(AITunnel.IsTunnelTile(cur) && AITunnel.GetOtherTunnelEnd(cur) == prev))
        return false;
    } else if (dNext > 1) {
      if (!(AIBridge.IsBridgeTile(cur) && AIBridge.GetOtherBridgeEnd(cur) == next) &&
          !(AITunnel.IsTunnelTile(cur) && AITunnel.GetOtherTunnelEnd(cur) == next))
        return false;
    } else if (!AIRail.AreTilesConnected(prev, cur, next)) return false;
  }
  return true;
}

/* La geometrie V190 suit chaque coude. Verifier en plus les couples de
 * trackbits (OpenTTD forbid_90_deg) qui peuvent etre physiquement joints
 * mais inaccessibles par le pathfinder des trains. Les sauts d'ouvrage
 * interrompent la comparaison des couples de tuiles adjacentes. */
function OpexDoubleGrowTurnsSafe(tiles)
{
  local previousBit = 0;
  for (local i = 1; i < tiles.len() - 1; i++) {
    local bit = OpexV190Fix2TrackBit(tiles[i - 1], tiles[i], tiles[i + 1]);
    if (bit == 0) {
      if (AIMap.DistanceManhattan(tiles[i - 1], tiles[i]) == 1 &&
          AIMap.DistanceManhattan(tiles[i], tiles[i + 1]) == 1) return false;
      previousBit = 0;
      continue;
    }
    if ((previousBit == 1 && bit == 2) || (previousBit == 2 && bit == 1) ||
        ((previousBit == 4 || previousBit == 8) && (bit == 16 || bit == 32)) ||
        ((previousBit == 16 || previousBit == 32) && (bit == 4 || bit == 8)))
      return false;
    previousBit = bit;
  }
  return true;
}

