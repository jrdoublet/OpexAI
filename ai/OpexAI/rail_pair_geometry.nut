// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* Traces surs V271b (9403c73), conserves apres le retrait de RAIL-PAIR (18/11) pour V284 et RAIL-LOOP. */
V271_LAST_TRACE_ISSUE <- "";
V271_LAST_TRACE_DETAIL <- "";

/* Repli strict pour les gares B ayant plusieurs tuiles jointes au meme ID.
 * V284 refuse une bifurcation vers un autre quai de B, meme lorsque notre
 * sortie B est identifiee et que tous les autres choix terminent dans B.
 * Les aiguillages vers une VRAIE voie restent interdits. Le detail de refus
 * rend observables les ponts, tunnels, depots et sorties de gare ambigues. */
function OpexV271TraceJoinedDestination(start, lead, target)
{
  local visited = {};
  local route = [start, lead];
  local previous = start;
  local current = lead;
  local targetId = AIStation.GetStationID(target);
  local company = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
  local offsets = [1, -1, AIMap.GetMapSizeX(), -AIMap.GetMapSizeX()];
  for (local step = 0; step < 2000; step++) {
    if (current == target) return route;
    if (current in visited) { V271_LAST_TRACE_ISSUE = "cycle"; return null; }
    visited.rawset(current, true);
    if (AITile.GetOwner(current) != company) {
      V271_LAST_TRACE_ISSUE = "foreign_tile"; return null;
    }
    local next = null;
    if (AIBridge.IsBridgeTile(current) || AITunnel.IsTunnelTile(current)) {
      local bridge = AIBridge.IsBridgeTile(current);
      local other = bridge ? AIBridge.GetOtherBridgeEnd(current) : AITunnel.GetOtherTunnelEnd(current);
      if (!AIMap.IsValidTile(other)) { V271_LAST_TRACE_ISSUE = "structure_end"; return null; }
      local span = AIMap.DistanceManhattan(current, other);
      if (span <= 1) { V271_LAST_TRACE_ISSUE = "structure_span"; return null; }
      local direction = (other - current) / span;
      if (AIMap.DistanceManhattan(previous, current) == 1) {
        if (previous != current - direction) {
          V271_LAST_TRACE_ISSUE = "structure_axis_entry"; return null;
        }
        next = other;
      } else {
        if (previous != other) { V271_LAST_TRACE_ISSUE = "structure_axis_exit"; return null; }
        next = current - direction;
        if (!AIMap.IsValidTile(next)) {
          V271_LAST_TRACE_ISSUE = "structure_exit_invalid"; return null;
        }
        /* AIRail.IsRailTile exclut les tuiles de gare et les tetes
         * d'ouvrages. Autoriser la sortie directement sur NOTRE quai B,
         * et sur une autre tete de structure sur le meme axe. */
        if (!AIRail.IsRailTile(next) && !(next == target && AIRail.IsRailStationTile(next))
            && !AIBridge.IsBridgeTile(next) && !AITunnel.IsTunnelTile(next)) {
          V271_LAST_TRACE_ISSUE = "structure_exit_rail";
          V271_LAST_TRACE_DETAIL = "current=" + current + " other=" + other + " next=" + next
              + " target=" + target + " station=" + (AIRail.IsRailStationTile(next) ? 1 : 0)
              + " depot=" + (AIRail.IsRailDepotTile(next) ? 1 : 0)
              + " owner=" + AITile.GetOwner(next);
          return null;
        }
      }
    } else {
      foreach (offset in offsets) {
        local tile = current + offset;
        if (!AIMap.IsValidTile(tile) || AIMap.DistanceManhattan(current, tile) != 1
            || tile == previous || AIRail.IsRailDepotTile(tile)) continue;
        if (!AIRail.IsRailTile(tile) && !AIBridge.IsBridgeTile(tile)
            && !AITunnel.IsTunnelTile(tile)) continue;
        if (!AIRail.AreTilesConnected(previous, current, tile)) continue;
        /* Les autres quais d'une meme gare B ne menent pas vers une autre
         * ligne : ils ne doivent pas rendre ambigu le chemin vers NOTRE B. */
        if (tile != target && AIRail.IsRailStationTile(tile)
            && AIStation.GetStationID(tile) == targetId) continue;
        if (next != null) { V271_LAST_TRACE_ISSUE = "junction"; return null; }
        next = tile;
      }
    }
    if (next == null) { V271_LAST_TRACE_ISSUE = "dead_end"; return null; }
    previous = current;
    current = next;
    route.append(current);
  }
  V271_LAST_TRACE_ISSUE = "length_limit";
  return null;
}

/* Reutiliser le traceur V284 : un ouvrage doit etre traverse dans son axe,
 * toute ambiguite/branche/cycle retourne null et seule la destination exacte
 * est acceptee. Le traceur V271b historique pouvait retourner un prefixe. */
function OpexV271TraceTrackTiles(startStationTile, leadTile, endStationTile, crossStructures = false)
{
  V271_LAST_TRACE_ISSUE = "invalid_start";
  V271_LAST_TRACE_DETAIL = "";
  if (!AIMap.IsValidTile(startStationTile) || !AIMap.IsValidTile(leadTile)
      || !AIMap.IsValidTile(endStationTile)
      || (!AIRail.IsRailTile(leadTile) && !AIBridge.IsBridgeTile(leadTile)
          && !AITunnel.IsTunnelTile(leadTile))
      || AIMap.DistanceManhattan(startStationTile, leadTile) != 1) return null;
  local route = OpexV284Trace({ stationA = startStationTile, stationB = endStationTile,
      platformA = { station_exit = startStationTile, lead = leadTile } });
  if (route == null || route.len() < 3 || route[route.len() - 1] != endStationTile) {
    V271_LAST_TRACE_ISSUE = "v284_strict";
    route = OpexV271TraceJoinedDestination(startStationTile, leadTile, endStationTile);
  }
  if (route == null || route.len() < 3 || route[route.len() - 1] != endStationTile) return null;
  if (!crossStructures) foreach (tile in route)
    if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
      V271_LAST_TRACE_ISSUE = "structure_not_allowed"; return null;
    }
  V271_LAST_TRACE_ISSUE = "";
  return route;
}

