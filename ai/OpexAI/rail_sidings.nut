// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* RAIL-SIDINGS P0, read-only prototype (2026-11-08).
 * The emitted footprint is NOT a connected siding nor a circulation certificate.
 * No rail, signal, station, order or vehicle command may be added here until
 * native bidirectional crossing, identity and Save/Load gates are passed.
 * Only invoked with rail_sidings=1; no persistent fields, no transactions.
 */

/* Conservative geometric envelope. A straight neighboring band is necessary,
 * but not sufficient: switches, 90-degree turns and PBS are NOT certified. */
function OpexRailSidingsFootprint(tiles, first, useful, side)
{
  if (tiles == null || useful < 2 || first < 2 || first + useful >= tiles.len() - 2)
    return false;
  local xStep = AIMap.GetTileIndex(1, 0);
  local yStep = AIMap.GetTileIndex(0, 1);
  local axial = tiles[first + 1] - tiles[first];
  local lateral = 0;
  if (axial == xStep || axial == -xStep) lateral = side * yStep;
  else if (axial == yStep || axial == -yStep) lateral = side * xStep;
  else return false;
  for (local i = first; i < first + useful; i++) {
    local t = tiles[i];
    if (i > 0 && tiles[i] - tiles[i - 1] != axial) return false;
    if (i + 1 >= tiles.len() || tiles[i + 1] - t != axial) return false;
    if (!AIRail.IsRailTile(t) || AIRail.IsRailDepotTile(t)
        || AIRail.IsRailStationTile(t) || AIBridge.IsBridgeTile(t)
        || AITunnel.IsTunnelTile(t)) return false;
    if (!AIRail.AreTilesConnected(tiles[i - 1], t, tiles[i + 1])) return false;
    local freeTile = t + lateral;
    if (!AIMap.IsValidTile(freeTile) || !AITile.IsBuildable(freeTile)
        || AITile.GetSlope(freeTile) != AITile.SLOPE_FLAT) return false;
  }
  return true;
}

/* Find an envelope near a target distance; the 100-tile interval is a search
 * hypothesis, never a reason to buy rails. Bound the work to +/-12 locations. */
function OpexRailSidingsWindow(tiles, target, useful)
{
  for (local offset = 0; offset <= 12; offset++) {
    foreach (sign in [1, -1]) {
      local first = target + sign * offset;
      if (OpexRailSidingsFootprint(tiles, first, useful, 1))
        return { first = first, last = first + useful - 1, side = 1 };
      if (OpexRailSidingsFootprint(tiles, first, useful, -1))
        return { first = first, last = first + useful - 1, side = -1 };
    }
  }
  return null;
}

function OpexRailSidingsCandidate(line)
{
  if (line == null || !("mode" in line) || line.mode != "rail"
      || !("kind" in line) || line.kind != "freight"
      || !("trains" in line) || line.trains != 1
      || !("vehicles" in line) || line.vehicles == null || line.vehicles.len() != 1
      || !("lastProfit" in line) || typeof line.lastProfit != "integer" || line.lastProfit <= 0
      || !("lastWaitingA" in line) || typeof line.lastWaitingA != "integer" || line.lastWaitingA < 120
      || !("platformLength" in line) || typeof line.platformLength != "integer" || line.platformLength < 2
      || !("platformA" in line) || line.platformA == null
      || !("platformB" in line) || line.platformB == null
      || !("stationA" in line) || !("stationB" in line)
      || !("doubleTrack" in line) || line.doubleTrack != 0
      || (("scrapping" in line) && line.scrapping)
      || (("railLoop" in line) && line.railLoop != 0)
      || ("railLoopV3Txn" in line) || ("railLoopV3Clone" in line)
      || ("railPair" in line) || ("doubleGrowDirectional" in line)) return null;
  local vehicle = line.vehicles[0];
  if (!AIVehicle.IsValidVehicle(vehicle)) return null;
  local length16 = AIVehicle.GetLength(vehicle);
  if (length16 <= 0 || length16 > line.platformLength * 16) return null;
  if (!("lead" in line.platformA) || line.platformA.lead == null
      || !AIMap.IsValidTile(line.platformA.lead) || !AIMap.IsValidTile(line.stationA)
      || !AIMap.IsValidTile(line.stationB)) return null;
  local route = OpexTraceTrackTiles(line.stationA, line.platformA.lead, line.stationB);
  if (route == null || route.len() < 12 || route.len() > 400) return null;
  local dstId = AIStation.GetStationID(line.stationB);
  if (!AIStation.IsValidStation(dstId)
      || AIStation.GetStationID(route[route.len() - 1]) != dstId) return null;
  /* One additional train must fit fully between both switches. A physical
   * vehicle length is observed here; switch clearance remains unverified. */
  local useful = max(8, (length16 + 15) / 16 + 4);
  local nearSource = OpexRailSidingsWindow(route, 10, useful);
  local intermediate = null;
  if (route.len() > 125)
    intermediate = OpexRailSidingsWindow(route, 100, useful);
  return { routeLength = route.len(), useful = useful, trainLength16 = length16,
           source = nearSource, middle = intermediate };
}

/* No-op when probes are off. No runtime state kept: re-evaluate after Load,
 * and switching rail_sidings back to 0 has no side effects to reconcile. */
function OpexRailSidingsStudy(owner, year)
{
  if (!RAIL_SIDINGS_SHADOW || !DECISION_LOG || owner == null || owner._lines == null)
    return;
  local inspected = 0;
  local shortlisted = 0;
  foreach (line in owner._lines) {
    if (inspected >= 12) break;
    if (line == null || !("mode" in line) || line.mode != "rail") continue;
    inspected++;
    local plan = OpexRailSidingsCandidate(line);
    if (plan == null) continue;
    shortlisted++;
    OpexDecide("RAIL_SIDINGS", "phase=shadow year=" + year
        + " line=" + (("lineId" in line) ? line.lineId : -1)
        + " route=" + plan.routeLength + " useful=" + plan.useful
        + " train16=" + plan.trainLength16
        + " source=" + (plan.source != null ? plan.source.first : -1)
        + " middle=" + (plan.middle != null ? plan.middle.first : -1)
        + " state=UNCERTIFIED");
  }
  OpexDecide("RAIL_SIDINGS", "phase=summary year=" + year
      + " inspected=" + inspected + " candidates=" + shortlisted
      + " build=0 clone=0 state=HOLD");
}
