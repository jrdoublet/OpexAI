// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* ROAD1Y-K : A* routier leger pour les paires de bus site-first.
 *
 * Constat du 02/11 (3 graines, 3 ans, route seule) : les candidats bus de
 * 96 a 192 tuiles sont les plus nombreux et les mieux estimes (profit median
 * 6-10 kGBP contre 4-5 kGBP sous 64), mais AUCUN n'est construit au-dela de 128 :
 * tous meurent en TRACEX, faute de voirie continue (BFS) et de L constructible.
 * AAA trace ces liaisons avec un vrai pathfinder.
 *
 * Ce solveur ne pose aucune AITestMode par voisin (cout mesure de ROAD100-16) :
 * il explore sur des predicats de tuile bon marche, puis valide le trace complet
 * arete par arete avec OpexRoadTraceBuildable. Une arete refusee est bannie et la
 * recherche relancee, au plus ROAD1Y_ASTAR_RETRIES fois, dans le meme budget de
 * noeuds. Appele uniquement a la construction (paires road1yBusSite), jamais dans
 * un try ; il peut donc durer plusieurs ticks sans risque. */

ROAD1Y_ASTAR_RETRIES <- 3;

function OpexRoad1yAStarTileOk(tile, banned)
{
  if (!AIMap.IsValidTile(tile)) return false;
  if (tile in banned) return false;
  if (AITile.IsWaterTile(tile) || AITile.IsStationTile(tile)) return false;
  if (AIRail.IsRailTile(tile) || AIRoad.IsRoadDepotTile(tile)) return false;
  if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) return false;
  return AIRoad.IsRoadTile(tile) || AITile.IsBuildable(tile);
}

/* Pente admise : plate, ou inclinee dans l'axe du deplacement (sans virage). */
function OpexRoad1yAStarSlopeOk(tile, alongX)
{
  local s = AITile.GetSlope(tile);
  if (s == AITile.SLOPE_FLAT) return 0;
  if (alongX && (s == AITile.SLOPE_NE || s == AITile.SLOPE_SW)) return 1;
  if (!alongX && (s == AITile.SLOPE_NW || s == AITile.SLOPE_SE)) return 1;
  return -1;
}

/* Une recherche : renvoie la liste d'aretes {from,to} de src a dst ou null.
 * budget.nodes est decremente par noeud developpe. */
function OpexRoad1yAStarSearch(src, srcFront, dst, dstFront, banned, budget, maxLen)
{
  local dirs = [AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0),
                AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1)];
  local stepX = AIMap.GetTileIndex(1, 0);
  local came = {};
  local gScore = {};
  local closed = {};
  local heap = OpexMinQueue();
  came.rawset(src, src);
  gScore.rawset(src, 0);
  heap.Insert(src, 2 * AIMap.DistanceManhattan(src, dst));
  while (heap.Count() > 0) {
    local cur = heap.Pop();
    if (cur in closed) continue;
    closed.rawset(cur, true);
    if (cur == dst) {
      local edges = [];
      local t = dst;
      while (t != src) {
        local p = came[t];
        edges.insert(0, { from = p, to = t });
        t = p;
      }
      return edges;
    }
    budget.nodes--;
    if (budget.nodes <= 0) return null;
    local g = gScore[cur];
    local prev = came[cur];
    local curFlat = AITile.GetSlope(cur) == AITile.SLOPE_FLAT;
    foreach (d in dirs) {
      local nxt = cur + d;
      if (nxt == prev || (nxt in closed)) continue;
      /* Sortie et entree des arrets traversants sur leur axe. */
      if (cur == src && !OpexRoadOnDtAxis(src, srcFront, nxt)) continue;
      if (nxt == dst && !OpexRoadOnDtAxis(dst, dstFront, cur)) continue;
      if (nxt == src) continue;
      local alongX = (d == stepX || d == -stepX);
      local cost = 0;
      if (nxt == dst) {
        cost = 1;
      } else {
        if (!OpexRoad1yAStarTileOk(nxt, banned)) continue;
        if (AIRoad.AreRoadTilesConnected(cur, nxt)) {
          cost = 1;
        } else {
          local slope = OpexRoad1yAStarSlopeOk(nxt, alongX);
          if (slope < 0) continue;
          cost = (AIRoad.IsRoadTile(nxt) ? 2 : 3) + 2 * slope;
        }
      }
      /* Virage : interdit sur une tuile en pente, penalise sinon. */
      if (cur != src && (nxt - cur) != (cur - prev)) {
        if (!curFlat) continue;
        cost += 1;
      }
      local ng = g + cost;
      if ((nxt in gScore) && gScore[nxt] <= ng) continue;
      if (ng > 3 * maxLen) continue;
      gScore.rawset(nxt, ng);
      came.rawset(nxt, cur);
      heap.Insert(nxt, ng + 2 * AIMap.DistanceManhattan(nxt, dst));
    }
  }
  return null;
}

/* Trace valide arete par arete, avec bannissement et relance. */
function OpexRoad1yAStarTrace(siteA, siteB, maxLen)
{
  local budget = { nodes = ROAD1Y_ASTAR * 1000 };
  local banned = {};
  local tries = 0;
  local reason = "BUDGET";
  while (tries <= ROAD1Y_ASTAR_RETRIES && budget.nodes > 0) {
    tries++;
    local trace = OpexRoad1yAStarSearch(siteA.tile, siteA.front, siteB.tile, siteB.front,
                                        banned, budget, maxLen);
    if (trace == null) { reason = budget.nodes > 0 ? "NO_PATH" : "BUDGET"; break; }
    if (trace.len() > maxLen) { reason = "LONG"; break; }
    local bad = null;
    foreach (edge in trace) {
      if (AIRoad.AreRoadTilesConnected(edge.from, edge.to)) continue;
      local ok = false;
      { local test = AITestMode(); ok = AIRoad.BuildRoad(edge.from, edge.to); }
      if (!ok) { bad = edge; break; }
    }
    if (bad == null) {
      if (DECISION_LOG) OpexDecide("ROAD1Y_ASTAR", "ok=1 a=" + siteA.tile + " b=" + siteB.tile
          + " d=" + AIMap.DistanceManhattan(siteA.tile, siteB.tile) + " len=" + trace.len()
          + " tries=" + tries + " left=" + budget.nodes);
      return trace;
    }
    reason = "UNBUILDABLE";
    local victim = (bad.to != siteB.tile) ? bad.to : bad.from;
    if (victim == siteA.tile) break;
    banned.rawset(victim, true);
  }
  if (DECISION_LOG) OpexDecide("ROAD1Y_ASTAR", "ok=0 a=" + siteA.tile + " b=" + siteB.tile
      + " d=" + AIMap.DistanceManhattan(siteA.tile, siteB.tile) + " reason=" + reason
      + " tries=" + tries + " left=" + budget.nodes);
  return null;
}
