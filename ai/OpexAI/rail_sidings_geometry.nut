// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* RAIL-SIDINGS: additive local construction on an existing private railway.
 * Tile paths specify boundary corners, not guessed left/right track masks.
 * No demolition, earthworks, continuous double track or historical P4 journal.
 */
function OpexRSBit(a, b, c)
{
  if (!AIMap.IsValidTile(a) || !AIMap.IsValidTile(b) || !AIMap.IsValidTile(c)
      || AIMap.DistanceManhattan(a, b) != 1 || AIMap.DistanceManhattan(b, c) != 1
      || a == c) return 0;
  local x = a - b; local y = c - b; local w = AIMap.GetMapSizeX();
  if (x > y) { local swap = x; x = y; y = swap; }
  if (x == -1 && y == 1) return AIRail.RAILTRACK_NE_SW;
  if (x == -w && y == w) return AIRail.RAILTRACK_NW_SE;
  if (x == -w && y == -1) return AIRail.RAILTRACK_NW_NE;
  if (x == 1 && y == w) return AIRail.RAILTRACK_SW_SE;
  if (x == -w && y == 1) return AIRail.RAILTRACK_NW_SW;
  if (x == -1 && y == w) return AIRail.RAILTRACK_NE_SE;
  return 0;
}

function OpexRSNo90(path)
{
  if (path == null || path.len() < 3) return false;
  local prior = 0;
  for (local i = 1; i < path.len() - 1; i++) {
    local bit = OpexRSBit(path[i-1], path[i], path[i+1]);
    if (bit == 0) return false;
    /* TrackCrossesTracks: X/Y and Upper,Lower/Left,Right. */
    if ((prior == 1 && bit == 2) || (prior == 2 && bit == 1)
        || ((prior & 12) != 0 && (bit & 48) != 0)
        || ((prior & 48) != 0 && (bit & 12) != 0)) return false;
    prior = bit;
  }
  return true;
}

/* Count physical distance, including the length of bridge/tunnel spans that
 * OpexV284Trace represents by two end tiles. */
function OpexRSRouteTiles(route)
{
  if(route==null || route.len()<2) return -1;
  local length=0;
  for(local i=1;i<route.len();i++)
    length+=AIMap.DistanceManhattan(route[i-1],route[i]);
  return length;
}

/* A bridge/tunnel may end immediately before the head of another span.
 * Neither portal is AIRail.IsRailTile. Admit ONLY the adjacent, forward-facing
 * portal of an owned, reciprocal, axial native span; never invent a rail edge.
 * Ordinary rail exits retain their old guard in the calling trace functions.
 * This topology read does not relax existing-route, PBS, No90 or exclusivity.
 */
function OpexRSAdjacentSpanExit(head,exit)
{
  if(!AIMap.IsValidTile(head) || !AIMap.IsValidTile(exit)
      || AIMap.DistanceManhattan(head,exit)!=1) return false;
  local bridge=AIBridge.IsBridgeTile(exit), tunnel=AITunnel.IsTunnelTile(exit);
  if(bridge==tunnel) return false;
  local other=bridge?AIBridge.GetOtherBridgeEnd(exit):AITunnel.GetOtherTunnelEnd(exit);
  if(!AIMap.IsValidTile(other)) return false;
  local owner=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
  if(AITile.GetOwner(head)!=owner || AITile.GetOwner(exit)!=owner
      || AITile.GetOwner(other)!=owner) return false;
  /* A company-owned ROAD bridge may also have native reciprocal heads.
   * Ownership and alignment alone cannot authorize a railway connection. */
  if(!AITile.HasTransportType(head,AITile.TRANSPORT_RAIL)
      || !AITile.HasTransportType(exit,AITile.TRANSPORT_RAIL)
      || !AITile.HasTransportType(other,AITile.TRANSPORT_RAIL)) return false;
  local span=AIMap.DistanceManhattan(exit,other);
  if(span<=1 || other-exit!=(exit-head)*span) return false;
  if(bridge) return AIBridge.IsBridgeTile(other)
      && AIBridge.GetOtherBridgeEnd(other)==exit;
  return AITunnel.IsTunnelTile(other)
      && AITunnel.GetOtherTunnelEnd(other)==exit;
}

/* V284Trace intentionally refuses every fork, including a harmless spur to
 * a depot or a dead end. For AUTO150 only, follow both directions of any
 * junction and accept a route iff exactly ONE simple connected path reaches
 * this line's sink. Exhaust the bounded search even after the first success:
 * stopping at the first path would silently pick an arbitrary shared track.
 * On ambiguity, exhaustion, loops or an unsupported bridge, fail closed.
 * No rail or signal is changed by this topology-only read. */
function OpexRSUniqueTrace(line)
{
  if(line==null || !("platformA" in line) || line.platformA==null) return null;
  local lead=OpexC41RailApproachLead(line.platformA,line.stationA);
  if(lead==null) return null;
  local paths=[{tiles=[line.stationA,lead],prev=line.stationA,cur=lead}];
  local offsets=[1,-1,AIMap.GetMapSizeX(),-AIMap.GetMapSizeX()];
  local found=null;local steps=0;
  while(paths.len()>0) {
    /* Truncation cannot certify uniqueness: do not accept a partial DFS. */
    if(steps>=4096 || paths.len()>256) return null;
    local state=paths.pop();steps++;
    local current=state.cur,previous=state.prev;
    if(current==line.stationB) {
      if(found!=null) return null;
      found=state.tiles;
      continue;
    }
    if(state.tiles.len()>=1200 || !AIMap.IsValidTile(current)
        || AITile.GetOwner(current)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF))
      return null;
    local choices=[];
    if(AIBridge.IsBridgeTile(current) || AITunnel.IsTunnelTile(current)) {
      local other=AIBridge.IsBridgeTile(current)?AIBridge.GetOtherBridgeEnd(current):
          AITunnel.GetOtherTunnelEnd(current);
      local span=AIMap.DistanceManhattan(current,other);
      if(span<=1) return null;
      local direction=(other-current)/span;
      if(AIMap.DistanceManhattan(previous,current)==1) {
        if(previous!=current-direction) return null;
        choices.append(other);
      } else {
        if(previous!=other) return null;
        local exit=current-direction;
        if(!AIMap.IsValidTile(exit)
            || (!AIRail.IsRailTile(exit) && !OpexRSAdjacentSpanExit(current,exit)))
          return null;
        choices.append(exit);
      }
    } else {
      foreach(delta in offsets) {
        local next=current+delta;
        if(!AIMap.IsValidTile(next) || AIMap.DistanceManhattan(current,next)!=1
            || next==previous || AIRail.IsRailDepotTile(next)
            || (!AIRail.IsRailTile(next) && !AIBridge.IsBridgeTile(next)
                && !AITunnel.IsTunnelTile(next))) continue;
        if(AIRail.AreTilesConnected(previous,current,next)
            && AIRail.AreTilesConnected(next,current,previous)) choices.append(next);
      }
    }
    foreach(next in choices) {
      local repeated=false;
      foreach(t in state.tiles) if(t==next) {repeated=true;break;}
      if(repeated) continue;
      if(!AIMap.IsValidTile(next)
          || AITile.GetOwner(next)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF))
        return null;
      local candidate=state.tiles.slice(0);candidate.append(next);
      paths.append({tiles=candidate,prev=current,cur=next});
      if(paths.len()>256) return null;
    }
  }
  if(found!=null && OpexRSExistingRouteIssue(found)=="OK") return found;
  return null;
}

/* Station/depot footprints and rail *pieces* have different terrain rules.
 * In particular BuildRailTrack accepts several slopes that a platform cannot.
 * This is only a cheap rejection filter: the exact bit must also pass the
 * engine in AITestMode, followed by full-plan/build-time verification. */
function OpexRSRailSite(tile)
{
  return AIMap.IsValidTile(tile) && AITile.IsBuildable(tile)
      && !AITile.IsHouseTile(tile) && !AITile.IsStationTile(tile)
      && !AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL)
      && !AITile.HasTransportType(tile, AITile.TRANSPORT_ROAD)
      && !AITile.HasTransportType(tile, AITile.TRANSPORT_WATER)
      && !AIBridge.IsBridgeTile(tile) && !AITunnel.IsTunnelTile(tile);
}

function OpexRSStationSite(tile)
{
  return OpexRSRailSite(tile) && AITile.GetSlope(tile)==AITile.SLOPE_FLAT;
}

function OpexRSDepotSite(tile)
{
  /* Keep the conservative depot footprint; the exact front and direction
   * are validated by BuildRailDepot in AITestMode. */
  return OpexRSStationSite(tile);
}

function OpexRSPlain(tile)
{
  return AIMap.IsValidTile(tile) && AIRail.IsRailTile(tile)
      && !AIRail.IsRailStationTile(tile) && !AIRail.IsRailDepotTile(tile)
      && !AIRail.IsLevelCrossingTile(tile) && !AIRail.IsRailWaypointTile(tile)
      && !AIBridge.IsBridgeTile(tile) && !AITunnel.IsTunnelTile(tile)
      && AITile.GetOwner(tile) == AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
}

function OpexRSPathPhysical(path)
{
  if (!OpexRSNo90(path)) return false;
  foreach (t in path)
    if (AITile.GetOwner(t) != AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)) return false;
  for (local i = 1; i < path.len()-1; i++)
    if (!AIRail.AreTilesConnected(path[i-1], path[i], path[i+1])
        || !AIRail.AreTilesConnected(path[i+1], path[i], path[i-1])) return false;
  return true;
}

/* Existing routes are traced by OpexV284Trace. Its representation legitimately
 * jumps from one bridge/tunnel portal to the other, unlike the new siding ops
 * which must remain adjacent and pass OpexRSPathPhysical. */
function OpexRSRealSpan(a,b)
{
  return (AIBridge.IsBridgeTile(a) && AIBridge.IsBridgeTile(b)
           && AIBridge.GetOtherBridgeEnd(a)==b && AIBridge.GetOtherBridgeEnd(b)==a)
      || (AITunnel.IsTunnelTile(a) && AITunnel.IsTunnelTile(b)
           && AITunnel.GetOtherTunnelEnd(a)==b && AITunnel.GetOtherTunnelEnd(b)==a);
}

function OpexRSExistingRouteIssue(route)
{
  if(route==null || route.len()<3) return "SHORT_ROUTE";
  foreach(t in route) {
    if(!AIMap.IsValidTile(t)
        || AITile.GetOwner(t)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF))
      return "OWNER";
  }
  local prior=0;
  for(local i=1;i<route.len()-1;i++) {
    local a=route[i-1];local b=route[i];local c=route[i+1];
    if(AIMap.DistanceManhattan(a,b)!=1 || AIMap.DistanceManhattan(b,c)!=1) {
      if(AIMap.DistanceManhattan(a,b)!=1 && !OpexRSRealSpan(a,b)) return "INVALID_SPAN";
      if(AIMap.DistanceManhattan(b,c)!=1 && !OpexRSRealSpan(b,c)) return "INVALID_SPAN";
      prior=0;
      continue;
    }
    local bit=OpexRSBit(a,b,c);
    if(bit==0) return "NO_BIT";
    if((prior==1 && bit==2) || (prior==2 && bit==1)
        || ((prior&12)!=0 && (bit&48)!=0)
        || ((prior&48)!=0 && (bit&12)!=0)) return "TRACK_CHANGE";
    if(!AIRail.AreTilesConnected(a,b,c) || !AIRail.AreTilesConnected(c,b,a))
      return "CONNECTION";
    prior=bit;
  }
  return "OK";
}

function OpexRSRailOps(path, first, last, budget = null)
{
  if (!OpexRSNo90(path)) return null;
  local ops = [];
  for (local i = first; i <= last; i++) {
    local tile = path[i]; local bit = OpexRSBit(path[i-1], tile, path[i+1]);
    local before = OpexRSPlain(tile) ? AIRail.GetRailTracks(tile) : 0;
    if (before == 0 && !OpexRSRailSite(tile)) return null;
    if (before != 0 && (before & bit) != 0) continue;
    local possible = false; local cost = 0;
    local key=tile+":"+bit;
    if(budget!=null && ("tested" in budget) && key in budget.tested) {
      possible=budget.tested[key].ok;cost=budget.tested[key].cost;
    } else {
      if(budget!=null) {
        if(budget.tests>=256) return null;
        budget.tests++;
      }
      local account = AIAccounting(); local test = AITestMode();
      possible = AIRail.BuildRailTrack(tile, bit); cost = account.GetCosts();
    }
    if (!possible) return null;
    ops.append({ kind = "rail", tile = tile, bit = bit, before = before,
                 after = before | bit, quote = cost, prev = path[i-1], next = path[i+1] });
  }
  return ops;
}

/* The station command always extends along positive X/Y, irrespective of
 * which end the train uses. This same footprint is checked before execution
 * and after an interrupted command, never inferred from a successful test. */
function OpexRSStationShape(op)
{
  if(typeof op!="table" || !("tile" in op) || !("direction" in op)
      || !("length" in op) || !("station" in op) || !("tiles" in op)
      || typeof op.tile!="integer" || typeof op.direction!="integer"
      || typeof op.length!="integer" || typeof op.station!="integer"
      || typeof op.tiles!="array" || op.length<2 || op.length>12
      || op.tiles.len()!=op.length || !AIMap.IsValidTile(op.tile)
      || !AIStation.IsValidStation(op.station)) return false;
  local step=op.direction==AIRail.RAILTRACK_NE_SW?1:
      (op.direction==AIRail.RAILTRACK_NW_SE?AIMap.GetMapSizeX():0);
  if(step==0) return false;
  for(local k=0;k<op.length;k++)
    if(typeof op.tiles[k]!="integer" || !AIMap.IsValidTile(op.tiles[k])
        || op.tiles[k]!=op.tile+k*step
        || AIMap.DistanceManhattan(op.tile,op.tiles[k])!=k) return false;
  return true;
}

/* A PBS may stand on a single curved track too. Testing the actual signal
 * command is the authority, not an axis-aligned three-tile approximation.
 * Keep a clear tile between its waiting point and the planned turnout. */
function OpexRSSourceTargets(route, rejects)
{
  local targets={};local oldSignal=null;
  local offsets=[1,-1,AIMap.GetMapSizeX(),-AIMap.GetMapSizeX()];
  for(local j=3;j<min(48,route.len()-3);j++) {
    local s=j-2;
    if(oldSignal==null && OpexRSPlain(route[s]) && OpexTileTrackCount(route[s])==1
        && OpexRSOldMainPBSReady(route,s,s-1,AIRail.SIGNALTYPE_PBS))
      oldSignal={kind="signal",tile=route[s],front=route[s-1],type=AIRail.SIGNALTYPE_PBS};
    if(oldSignal==null) {rejects.no_signal++;continue;}
    if(AIMap.DistanceManhattan(route[j-1],route[j])!=1
        || AIMap.DistanceManhattan(route[j],route[j+1])!=1
        || AIMap.DistanceManhattan(route[j+1],route[j+2])!=1
        || !OpexRSPlain(route[j]) || OpexTileTrackCount(route[j])!=1
        || AIRail.GetRailType(route[j])!=AIRail.GetCurrentRailType()) continue;
    /* A* can only enter a turnout from a vacant adjacent tile, and its
     * continuation is fixed by this old route. Discard impossible targets
     * before repeatedly steering the connector search towards them. This
     * is a necessary geometric filter; the rail command remains mandatory. */
    local approach=false;
    foreach(delta in offsets) {
      local near=route[j]+delta;
      if(!AIMap.IsValidTile(near)
          || AIMap.DistanceManhattan(route[j],near)!=1 || !OpexRSRailSite(near)) continue;
      local entrance=[near,route[j],route[j+1],route[j+2]];
      if(OpexRSNo90(entrance)) {approach=true;break;}
    }
    if(!approach) continue;
    targets.rawset(route[j],{index=j,signal=oldSignal});
  }
  return targets;
}

function OpexRSSourceDistance(tile, targets, distances = null)
{
  if(distances!=null && tile in distances) return distances[tile];
  local distance=1000;
  /* R32 measured 140505 versus R31 116457 opcodes on line18 when the
   * NoAI primitive was replaced with an interpreted inner arithmetic loop.
   * Keep the native primitive: only its measured cost decides. */
  foreach(t,_ in targets) distance=min(distance,AIMap.DistanceManhattan(tile,t));
  if(distances!=null) distances.rawset(tile,distance);
  return distance;
}

/* Search in actual X/Y space. A tile index difference is NOT a lateral
 * displacement: it can contain both X and Y components. Each candidate
 * explicitly includes the junction tile and both downstream old-route tiles.
 * Keep the search local (per station end), and never traverse existing rail
 * except at the single terminal junction. */
/* R52: all candidate paths are only geometric hypotheses.
 * No rail bit, station, owner, PBS or No90 guard may be bypassed. */
function OpexRSR52Knots(fromTile,toTile)
{
  local w=AIMap.GetMapSizeX(),h=AIMap.GetMapSizeY();
  local sx=AIMap.GetTileX(fromTile),sy=AIMap.GetTileY(fromTile);
  local tx=AIMap.GetTileX(toTile),ty=AIMap.GetTileY(toTile);
  local patterns=[[sx+ty*w],[tx+sy*w]];
  foreach(offset in [1,-1,2,-2,4,-4]) {
    local mx=sx+offset,my=sy+offset;
    if(mx>0 && mx<w-1) patterns.append([mx+sy*w,mx+ty*w]);
    if(my>0 && my<h-1) patterns.append([sx+my*w,tx+my*w]);
  }
  return patterns;
}

/* R52: add at most a short axial segment, never existing rail. The caller
 * separately checks No90 over the ENTIRE joined itinerary and tests every
 * complete track mask with OpexRSRailOps in native AITestMode. */
function OpexRSR52ExtendAxis(path,target,budget,bounds,forbidden,stopOps,maxLen)
{
  local current=path[path.len()-1],w=AIMap.GetMapSizeX();
  local sameX=AIMap.GetTileX(current)==AIMap.GetTileX(target);
  local sameY=AIMap.GetTileY(current)==AIMap.GetTileY(target);
  if(!sameX && !sameY) return false;
  local length=AIMap.DistanceManhattan(current,target);
  if(path.len()+length>maxLen) return false;
  local step=sameX?(target>current?w:-w):(target>current?1:-1);
  if(!("r52RailCache" in budget)) budget.r52RailCache <- {};
  for(local k=0;k<length;k++) {
    if(OpexOpsMeasureEnd(budget.mark)>=stopOps) return false;
    local next=path[path.len()-1]+step;
    if(!AIMap.IsValidTile(next)
        || AIMap.DistanceManhattan(path[path.len()-1],next)!=1
        || next in forbidden) return false;
    local x=AIMap.GetTileX(next),y=AIMap.GetTileY(next);
    if(x<bounds.minx || x>bounds.maxx || y<bounds.miny || y>bounds.maxy)
      return false;
    local repeated=false;
    foreach(t in path) if(t==next) {repeated=true;break;}
    if(repeated) return false;
    if(!(next in budget.r52RailCache))
      budget.r52RailCache.rawset(next,OpexRSRailSite(next));
    if(!budget.r52RailCache[next]) return false;
    path.append(next);
  }
  return true;
}

function OpexRSR52SourcePretrace(initial,end,route,rejects,berth,targets,budget,stopOps)
{
  local w=AIMap.GetMapSizeX(),h=AIMap.GetMapSizeY();
  local ex=AIMap.GetTileX(end),ey=AIMap.GetTileY(end);
  local bounds={minx=max(0,ex-24),maxx=min(w-1,ex+24),
                miny=max(0,ey-24),maxy=min(h-1,ey+24)};
  local forbidden={};foreach(t in berth) forbidden.rawset(t,true);
  local goals=AIList();goals.Sort(AIList.SORT_BY_VALUE,true);
  foreach(t,_ in targets) goals.AddItem(t,AIMap.DistanceManhattan(initial[2],t));
  local examined=0,testsBegin=budget.tests;
  foreach(goal,_ in goals) {
    if(examined>=6 || OpexOpsMeasureEnd(budget.mark)>=stopOps) break;
    examined++;
    local match=targets[goal],j=match.index;
    foreach(delta in [1,-1,w,-w]) {
      local near=goal+delta;
      if(!AIMap.IsValidTile(near)
          || AIMap.DistanceManhattan(near,goal)!=1
          || !OpexRSRailSite(near)
          || !OpexRSNo90([near,goal,route[j+1],route[j+2]])) continue;
      local patterns=OpexRSR52Knots(initial[2],near);
      foreach(knots in patterns) {
        if(OpexOpsMeasureEnd(budget.mark)>=stopOps) return null;
        local path=initial.slice(0),valid=true;
        foreach(pivot in knots) {
          if(!OpexRSR52ExtendAxis(path,pivot,budget,bounds,forbidden,
                                   stopOps,45)) {valid=false;break;}
        }
        if(!valid || !OpexRSR52ExtendAxis(path,near,budget,bounds,forbidden,
                                           stopOps,45)) continue;
        local finished=path.slice(0);
        finished.append(goal);finished.append(route[j+1]);finished.append(route[j+2]);
        if(!OpexRSNo90(finished)) {rejects.no90++;continue;}
        /* R52: actual native rail command proof, never a host-only shortcut. */
        if(budget.tests>=256 || budget.tests-testsBegin>=32) return null;
        if(finished.len()-4>32-(budget.tests-testsBegin)) continue;
        if(OpexOpsMeasureEnd(budget.mark)>=stopOps) return null;
        local ops=OpexRSRailOps(finished,2,finished.len()-3,budget);
        if(ops==null) {rejects.rail_test++;continue;}
        return {path=finished,ops=ops,joinIndex=j,oldSignal=match.signal};
      }
    }
  }
  return null;
}

function OpexRSR52LoopPretrace(route,first,last,trainTiles,lateral,budget)
{
  local w=AIMap.GetMapSizeX(),h=AIMap.GetMapSizeY();
  local start=route[first]+lateral,finish=route[last]+lateral;
  if(!AIMap.IsValidTile(start) || !AIMap.IsValidTile(finish)
      || AIMap.DistanceManhattan(route[first],start)!=1
      || AIMap.DistanceManhattan(route[last],finish)!=1
      || !OpexRSRailSite(start) || !OpexRSRailSite(finish)) return null;
  local bounds={minx=w-1,maxx=0,miny=h-1,maxy=0};
  for(local i=first;i<=last;i++) {
    local x=AIMap.GetTileX(route[i]),y=AIMap.GetTileY(route[i]);
    bounds.minx=min(bounds.minx,x);bounds.maxx=max(bounds.maxx,x);
    bounds.miny=min(bounds.miny,y);bounds.maxy=max(bounds.maxy,y);
  }
  bounds.minx=max(0,bounds.minx-8);bounds.maxx=min(w-1,bounds.maxx+8);
  bounds.miny=max(0,bounds.miny-8);bounds.maxy=min(h-1,bounds.maxy+8);
  local stopOps=60000;
  if("phaseLimit" in budget) stopOps=min(stopOps,budget.phaseLimit);
  local prepCap=min(stopOps,OpexOpsMeasureEnd(budget.mark)+1500);
  local maxPath=min(100,(last-first)*3+28);
  /* The same 48-test allowance also includes any failed direct native test
   * previously attempted by LoopAt before this pretrace. */
  local forbidden={};
  local testsBegin=("r52LoopTestsStart" in budget)
      ?budget.r52LoopTestsStart:budget.tests;
  foreach(knots in OpexRSR52Knots(start,finish)) {
    if(OpexOpsMeasureEnd(budget.mark)>=prepCap) return null;
    local path=[route[first-1],route[first],start],valid=true;
    foreach(pivot in knots) {
      if(!OpexRSR52ExtendAxis(path,pivot,budget,bounds,forbidden,
                               prepCap,maxPath-2)) {valid=false;break;}
    }
    if(!valid || !OpexRSR52ExtendAxis(path,finish,budget,bounds,forbidden,
                                       prepCap,maxPath-2)) continue;
    path.append(route[last]);path.append(route[last+1]);
    if(path.len()<trainTiles+8 || !OpexRSNo90(path)) continue;
    local joined=[route[first-2]];
    foreach(t in path) joined.append(t);
    joined.append(route[last+2]);
    if(!OpexRSNo90(joined)) continue;
    /* R52: no AITestMode rail command until this ENTIRE path is valid. */
    if(budget.tests>=256 || budget.tests-testsBegin>=48
        || OpexOpsMeasureEnd(budget.mark)>=prepCap) return null;
    if(path.len()-2>48-(budget.tests-testsBegin)) continue;
    local ops=OpexRSRailOps(path,1,path.len()-2,budget);
    if(ops!=null) return {path=path,ops=ops};
  }
  return null;
}

function OpexRSSourceConnector(end, outward, route, rejects, berth, targets, budget)
{
  /* Old standalone diagnostic probes pass the same seven arguments but
   * predate R34's phaseLimit field. Preserve their original 60k behaviour. */
  if(!("phaseLimit" in budget)) budget.phaseLimit <- 60000;
  local stationPrev=end-outward;
  if (!AIMap.IsValidTile(stationPrev) || !AIMap.IsValidTile(end)
      || AIMap.DistanceManhattan(stationPrev,end)!=1) return null;
  local initial = [stationPrev,end];
  /* Only the platform exit is axial. The following tile may already curve;
   * a compulsory second straight tile hid legal exits beside local obstacles. */
  for (local k=1;k<=1;k++) {
    local tile=end+k*outward;
    if (!OpexRSRailSite(tile) || AIMap.DistanceManhattan(initial[initial.len()-1],tile)!=1) {
      rejects.occupied++;return null;
    }
    initial.append(tile);
  }
  if (!OpexRSNo90(initial)) { rejects.no90++;return null; }
  if(targets.len()==0) return null;
  local offsets=[1,-1,AIMap.GetMapSizeX(),-AIMap.GetMapSizeX()];
  local paths=[initial];local visited={};local head=0;
  local testStart=budget.tests,nodeStart=budget.nodes;
  /* R43: distribute SOURCE searches across different viable station exits,
   * not a long A* for one unsuitable berth. A short candidate never gains
   * permission to build: the final entire path still uses the native bit
   * preflight and No90. The 45k / 60k global limits remain unchanged. */
  local beforeOps=OpexOpsMeasureEnd(budget.mark);
  local sourceAttemptLimit=min(budget.phaseLimit,beforeOps+13000);
  if(!("sourceRailSites" in budget)) budget.sourceRailSites <- {};
  local priorBits=[OpexRSBit(initial[0],initial[1],initial[2])];
  local open=AIList();open.Sort(AIList.SORT_BY_VALUE,true);
  open.AddItem(0,OpexRSSourceDistance(initial[2],targets,budget.distances)*100);
  local costs=[0];
  if(!("tested" in budget)) budget.tested <- {};
  local forbidden={};foreach(t in berth) forbidden.rawset(t,true);
  local ex=AIMap.GetTileX(end),ey=AIMap.GetTileY(end);
  /* R52: reserve at most 2.2k of this SAME 13k connector budget. */
  local pretraceCap=min(sourceAttemptLimit,beforeOps+2200);
  if(OpexOpsMeasureEnd(budget.mark)<pretraceCap) {
    local prepared=OpexRSR52SourcePretrace(initial,end,route,rejects,
        berth,targets,budget,pretraceCap);
    if(prepared!=null) return prepared;
  }
  /* R45: expand a bounded GEOMETRIC shortlist without invoking a heavyweight
   * AITestMode command for each INCOMPLETE A* branch. Every complete path must
   * still pass OpexRSNo90 and OpexRSRailOps, whose native BuildRailTrack tests
   * remain mandatory before any acceptance. There is NO map mutation here.
   * The phase/attempt opcode budget, 4096-node and 256-command caps persist. */
  while(!open.IsEmpty() && head<192 && budget.nodes<4096 && budget.tests<256
      && budget.tests-testStart<32
      && OpexOpsMeasureEnd(budget.mark)<budget.phaseLimit
      && OpexOpsMeasureEnd(budget.mark)<sourceAttemptLimit) {
    local id=open.Begin();open.RemoveItem(id);
    local path=paths[id];local cur=path[path.len()-1];
    head++;budget.nodes++;
    foreach(delta in offsets) {
      /* R34: do not let one phase-0 connector consume the 15k reserved
       * for the gap-5/6 fallback. The global cap remains 60k. */
      if(OpexOpsMeasureEnd(budget.mark)>=budget.phaseLimit) break;
      if(OpexOpsMeasureEnd(budget.mark)>=sourceAttemptLimit) break;
      local next=cur+delta;
      if (!AIMap.IsValidTile(next) || AIMap.DistanceManhattan(cur,next)!=1
          || next==path[path.len()-2]) continue;
      local repeated=false;foreach(t in path) if(t==next) {repeated=true;break;}
      if(repeated || next in forbidden) continue;
      if (next in targets) {
        local match=targets[next];local j=match.index;
        local finished=path.slice(0);
        finished.append(next);finished.append(route[j+1]);finished.append(route[j+2]);
        if (!OpexRSNo90(finished)) {rejects.no90++;continue;}
        /* This is the final existing-rail turnout; all preceding new tiles
         * were verified clear before they entered the search frontier. */
        local ops=OpexRSRailOps(finished,2,finished.len()-3,budget);
        if (ops==null) {rejects.rail_test++;continue;}
        if(DECISION_LOG) OpexDiagLog("RS_SOURCE_LOCAL_END result=FOUND"
            +" nodes_added="+(budget.nodes-nodeStart)
            +" tests_added="+(budget.tests-testStart)
            +" spent="+(OpexOpsMeasureEnd(budget.mark)-beforeOps)
            +" limit="+sourceAttemptLimit);
        return {path=finished,ops=ops,joinIndex=j,oldSignal=match.signal};
      }
      if(path.len()>=48) {rejects.occupied++;continue;}
      /* Recheck terrain only on the first encounter in this single unchanged
       * AITestMode-only planner invocation; negative results are also cached.
       * This cache never survives Save/Load or a physical command. */
      if(!(next in budget.sourceRailSites)) {
        if(!OpexRSRailSite(next)) {
          budget.sourceRailSites.rawset(next,false);
          rejects.occupied++;continue;
        }
        budget.sourceRailSites.rawset(next,true);
      }
      if(!budget.sourceRailSites[next]) {rejects.occupied++;continue;}
      if (abs(AIMap.GetTileX(next)-ex)>24 || abs(AIMap.GetTileY(next)-ey)>24) {
        rejects.offset++;continue;
      }
      local extended=path.slice(0);extended.append(next);
      local prevBit=priorBits[id];
      local priorBit=OpexRSBit(path[path.len()-2],cur,next);
      if(priorBit==0 || (prevBit==1 && priorBit==2)
          || (prevBit==2 && priorBit==1)
          || ((prevBit & 12)!=0 && (priorBit & 48)!=0)
          || ((prevBit & 48)!=0 && (priorBit & 12)!=0)) {
        rejects.no90++;continue;
      }
      /* Incremental last-two-bits check is equivalent to full prefix No90.
       * Reserve the complete No90 traversal for FINAL joined paths only. */
      local key=cur+":"+next+":"+priorBit;
      /* Terrain/site/No90 are necessary, never certificates of buildability.
       * On reaching a target, OpexRSRailOps verifies EVERY bit using native
       * AITestMode; a refused complete path stays refused. */
      local travel=costs[id]+100;
      if(priorBit>2) travel+=15;
      if ((key in visited) && visited[key]<=travel) continue;
      visited.rawset(key,travel);
      local nid=paths.len();paths.append(extended);
      costs.append(travel);priorBits.append(priorBit);
      open.AddItem(nid,travel+100*OpexRSSourceDistance(next,targets,budget.distances));
    }
  }
  if(DECISION_LOG) OpexDiagLog("RS_SOURCE_LOCAL_END result=NO_PATH"
      +" nodes_added="+(budget.nodes-nodeStart)
      +" tests_added="+(budget.tests-testStart)
      +" spent="+(OpexOpsMeasureEnd(budget.mark)-beforeOps)
      +" limit="+sourceAttemptLimit);
  return null;
}

function OpexRSSourcePlan(line, route, trainTiles, excludedSource = null)
{
  local p = line.platformA; local d = p.step;
  local lateral = abs(d) == 1 ? AIMap.GetMapSizeX() : 1;
  local station = AIStation.GetStationID(line.stationA);
  local oldBerth=[];
  local canonical=p.direction==AIRail.RAILTRACK_NE_SW?1:AIMap.GetMapSizeX();
  if(abs(d)!=canonical || p.length<trainTiles || p.length<2 || p.length>12
      || route.len()<6 || route[0]!=line.stationA) return null;
  local oldAnchor=d<0?p.anchor+(p.length-1)*d:p.anchor;
  for(local k=0;k<p.length;k++) {
    local tile=oldAnchor+k*canonical;oldBerth.append(tile);
    if(!AIRail.IsRailStationTile(tile) || AIStation.GetStationID(tile)!=station
        || AIRail.GetRailStationDirection(tile)!=p.direction
        || AITile.GetOwner(tile)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)
        || AIRail.GetRailType(tile)!=AIRail.GetCurrentRailType()) return null;
  }
  d=canonical;
  local rejects={short_berth=0,blocked_berth=0,no_egress=0,offset=0,no90=0,
                 occupied=0,rail_test=0,station_test=0,no_signal=0};
  local targets=OpexRSSourceTargets(route,rejects);
  local budget={nodes=0,candidates=0,tests=0,tested={},distances={},
                phaseLimit=60000,mark=OpexOpsMeasureBegin()};
  /* Without a proven old-main PBS, no connector can be accepted. Avoid
   * testing station footprints and rail commands for an impossible plan. */
  if(targets.len()==0) {
    if(DECISION_LOG) OpexDiagLog("RS_SOURCE_FAIL line="+line.lineId
        +" reason=NO_SIGNAL_TARGET no_signal="+rejects.no_signal);
    return null;
  }
  local footprints=[];
  /* A nearby berth variant rechecks most of the same terrain. This function
   * builds nothing: engine probes use AITestMode, so tile availability cannot
   * change during this call. Never keep the cache past this plan invocation. */
  local stationSites={},railSites={};
  local berthLength=max(2,trainTiles);
  /* Up to six tiles laterally and eight longitudinally. The authenticated
   * 442018 line-2 test found seven additional native-legal platforms with a
   * clear axial exit at gaps 5/6; none were in the former gap <=4 search.
   * Keep the original gap<=4 pool ahead of the new fallback candidates.
   * The engine enforces distant_join_stations and station_spread for the
   * explicit StationID. The platform length never shrinks with its offset. */
  /* 192 is the exact cardinality within radius<=12, gap<=6 and the original
   * shift<=8, both sides, with unique zero longitudinal shift. It is not an
   * engine-command or A* node cap (still 256 tests, 4096 nodes, 60k opcodes).
   * Shorter platforms apply their existing p.length+4 displacement bound. */
  /* R16/R17/R18 native: line24 exhausted its SOURCE budget before ONE
   * station test. Do not collect all radii first. Search progressively like
   * a human: rank the available platforms at each distance, actually test
   * them, and widen the radius only if no working connection was found.
   * The historical gap<=4 pass precedes the gap5/6 fallback, and the exact
   * 60k opcode/8 attempts/256 native-command caps are unchanged. */
  local best=null,bestCost=0,attempts=0;
  local r52SeenAnchors={};
  local r52RadiusOrder=[1,2,6,3,9,4,12,5,7,10,8,11];
  foreach(phase in [0,1]) {
  /* Reserve a final 15k of the exact same 60k cap for the wider gap5/6
   * fallback instead of ranking all 136 gap1..4 candidates after time is
   * already exhausted. The positive short-radius candidates still run first.
   * A new phase must not inherit untested phase-0 entries in its rank queue. */
  local phaseLimit=phase==0?45000:60000;
  budget.phaseLimit=phaseLimit;
  local ranked=AIList();ranked.Sort(AIList.SORT_BY_VALUE,true);
  if(phase==1 && (best!=null || attempts>=8 || budget.nodes>=4096
      || budget.tests>=256 || OpexOpsMeasureEnd(budget.mark)>=60000)) break;
  foreach(radius in r52RadiusOrder) {
  if(budget.candidates>=192 || budget.nodes>=4096
      || OpexOpsMeasureEnd(budget.mark)>=phaseLimit) break;
  for(local gap=1;gap<=min(6,radius) && budget.candidates<192 && budget.nodes<4096
      && OpexOpsMeasureEnd(budget.mark)<phaseLimit;gap++) {
    if(phase==0 && gap>4) continue;
    local displacement=radius-gap;
    if(displacement>min(8,p.length+4)) continue;
    foreach (side in [-1,1]) foreach (shiftSign in [1,-1]) {
    if(displacement==0 && shiftSign==-1) continue;
    if(budget.candidates>=192 || budget.nodes>=4096 || budget.tests>=256
        || OpexOpsMeasureEnd(budget.mark)>=phaseLimit) break;
    local shift=displacement*shiftSign;
    local anchor = oldAnchor + shift*d + side*gap*lateral;
    if(anchor in r52SeenAnchors) continue;
    r52SeenAnchors.rawset(anchor,true);
    budget.candidates++;
    if(excludedSource!=null && anchor==excludedSource.stationOp.tile) continue;
    /* R40: reject an unusable berth BEFORE spending up to 2*38 native
     * Manhattan calls to rank it. R34 native L18/L32/L43 spent most of the
     * SOURCE phases ranking footprints later rejected as blocked_berth.
     * Apply the exact SAME cached StationSite, slope and distance guards as
     * the native candidate loop below. The ranking of every legal berth is
     * byte-for-byte unchanged: no R32 interpreted Manhattan arithmetic or
     * speculative native BuildRailStation acceptance is introduced. */
    local firstTile=anchor,lastTile=anchor+(berthLength-1)*d;
    local berthUsable=true;
    for(local k=0;k<berthLength;k++) {
      local t=anchor+k*d;
      if(!(t in stationSites)) stationSites.rawset(t,OpexRSStationSite(t));
      if(!stationSites[t] || AIMap.DistanceManhattan(anchor,t)!=k
          || AIMap.DistanceManhattan(t,oldAnchor+(shift+k)*d)!=gap)
        {berthUsable=false;break;}
    }
    if(!berthUsable) {rejects.blocked_berth++;continue;}
    /* RS_SOURCE_EGRESS_PREFILTER: a legal station with neither axial exit
     * cannot possibly satisfy the unchanged SourceConnector entry guard.
     * The check is necessary, not a native BuildRailStation certificate. */
    local egressA=firstTile-d,egressB=lastTile+d;
    if(!(egressA in railSites)) railSites.rawset(egressA,OpexRSRailSite(egressA));
    if(!(egressB in railSites)) railSites.rawset(egressB,OpexRSRailSite(egressB));
    if(!railSites[egressA] && !railSites[egressB]) {
      rejects.no_egress++;continue;
    }
    /* Rank nearby usable coordinates, but NEVER scan the next radius before
     * trying this radius's candidates. Every actual candidate still undergoes
     * the unchanged native Station/No90/rail-bit preflight in the while loop. */
    local rank=OpexRSSourceDistance(firstTile,targets,budget.distances);
    rank=min(rank,OpexRSSourceDistance(lastTile,targets,budget.distances));
    local candidate=footprints.len();
    footprints.append({anchor=anchor,gap=gap,shift=shift});
    ranked.AddItem(candidate,rank*10+gap+abs(shift));
    }
  }
  while(!ranked.IsEmpty() && attempts<8 && budget.nodes<4096 && budget.tests<256
      && OpexOpsMeasureEnd(budget.mark)<phaseLimit) {
    local id=ranked.Begin();ranked.RemoveItem(id);
    local footprint=footprints[id],anchor=footprint.anchor,berth=[];
    local gap=footprint.gap,shift=footprint.shift;
    local clear=true;
    /* Same exact footprint, slope and separation checks as before, now only
     * for a shortlist entry considered in geometric rank order. */
    for(local k=0;k<berthLength;k++) {
      local t=anchor+k*d;berth.append(t);
      if(!(t in stationSites)) stationSites.rawset(t,OpexRSStationSite(t));
      if(!stationSites[t] || AIMap.DistanceManhattan(anchor,t)!=k
          || AIMap.DistanceManhattan(t,oldAnchor+(shift+k)*d)!=gap)
        {clear=false;break;}
    }
    if(!clear) {rejects.blocked_berth++;continue;}
    if(phase==1) {
      local outwardA=berth[0]-d,outwardB=berth[berth.len()-1]+d;
      if(!(outwardA in railSites)) railSites.rawset(outwardA,OpexRSRailSite(outwardA));
      if(!(outwardB in railSites)) railSites.rawset(outwardB,OpexRSRailSite(outwardB));
      if(!railSites[outwardA] && !railSites[outwardB]) {
        rejects.no_egress++;continue;
      }
    }
    attempts++;
    local feasible=false;local price=0;
    { local account=AIAccounting();local test=AITestMode();
      feasible=AIRail.BuildRailStation(anchor,p.direction,1,berthLength,station);
      price=account.GetCosts(); }
    if (!feasible) {rejects.station_test++;continue;}
    /* Prefer the end pointing out of the station; the opposite end is legal
     * only when the station can also be approached from that side. */
    local exitSign=route[1]-route[0]==d?1:-1;
    foreach (directionSign in [exitSign,-exitSign]) {
      local outward=directionSign*d;
      local end=directionSign==1?berth[berth.len()-1]:berth[0];
      local connector=OpexRSSourceConnector(end,outward,route,rejects,berth,targets,budget);
      if (connector==null) continue;
      local cost=price;foreach(op in connector.ops) cost+=max(0,op.quote);
      if(best!=null && cost>=bestCost) continue;
      if(DECISION_LOG) OpexDiagLog("RS_SOURCE_PLAN line="+line.lineId+" station="+station
          +" anchor="+anchor+" gap="+gap+" shift="+shift+" join="+connector.joinIndex
          +" nodes="+budget.nodes+" candidates="+budget.candidates);
      bestCost=cost;
      best={berth=berth,originalBerth=oldBerth,path=connector.path,joinIndex=connector.joinIndex,ops=connector.ops,
        stationOp={kind="station",tile=anchor,direction=p.direction,
                   length=berthLength,station=station,tiles=berth,quote=price},
        signals=[connector.oldSignal,{kind="signal",tile=end+outward,front=end,
                  type=AIRail.SIGNALTYPE_PBS}]};
    }
  }
  if(best!=null) return best;
  } // Search the next radius ONLY after this radius's native candidates.
  if(DECISION_LOG)
    OpexDiagLog("RS_SOURCE_PHASE line="+line.lineId+" phase="+phase+" candidates="
        +budget.candidates+" attempts="+attempts+" nodes="+budget.nodes
        +" opcodes="+OpexOpsMeasureEnd(budget.mark));
  }
  if(DECISION_LOG) OpexDiagLog("RS_SOURCE_FAIL line="+line.lineId
      +" short_berth="+rejects.short_berth+" blocked_berth="+rejects.blocked_berth
      +" no_egress="+rejects.no_egress
      +" offset="+rejects.offset+" no90="+rejects.no90
      +" occupied="+rejects.occupied+" rail_test="+rejects.rail_test
      +" station_test="+rejects.station_test+" no_signal="+rejects.no_signal
      +" nodes="+budget.nodes+" candidates="+budget.candidates+" tests="+budget.tests
      +" attempts="+attempts+" targets="+targets.len()
      +" source_opcodes="+OpexOpsMeasureEnd(budget.mark));
  return null;
}

/* A null result is intentionally fail-closed; the caller accumulates causal
 * rejection counters over all candidate windows, without new mutations. */
function OpexRSLoopReject(rejects, reason)
{
  if(rejects!=null) {
    if(!(reason in rejects)) rejects.rawset(reason,0);
    rejects[reason]++;
  }
  return null;
}

/* Existing mainline PBS sites are later removed/rebuilt by OpexRSPlan.
 * A signal already present (even of the requested type) cannot certify the
 * future rebuild: AITestMode never executes the planned RemoveSignal.
 * Accept only a connected single-bit site free of historical signals and a
 * successful actual engine test. Parallel rails are still tested at BUILD. */
function OpexRSOldMainPBSReady(route, index, frontIndex, signalType)
{
  if(route==null || index<=0 || index+1>=route.len()
      || (frontIndex!=index-1 && frontIndex!=index+1)) return false;
  local prev=route[index-1], tile=route[index], next=route[index+1];
  if(!OpexRSPlain(tile) || AIRail.GetRailType(tile)!=AIRail.GetCurrentRailType()
      || AIMap.DistanceManhattan(prev,tile)!=1
      || AIMap.DistanceManhattan(tile,next)!=1) return false;
  local track=OpexRSBit(prev,tile,next);
  if(track==0 || AIRail.GetRailTracks(tile)!=track) return false;
  if(AIRail.GetSignalType(tile,prev)!=AIRail.SIGNALTYPE_NONE
      || AIRail.GetSignalType(tile,next)!=AIRail.SIGNALTYPE_NONE) return false;
  local ok=false;
  { local test=AITestMode();
    ok=AIRail.BuildSignal(tile,route[frontIndex],signalType); }
  return ok;
}

/* Bounded directed rail search, not a translation of the existing track.
 * States remember their incoming tile: a valid tile is not necessarily a
 * valid rail *connection*. The first and last mainline pieces are genuine
 * switch commands; the intermediate route may bend or vary its lateral gap.
 * The open set and native tile/bit proof cache live only for this immutable
 * planning call. No cached result survives a map edit or Save/Load. */
function OpexRSLoopPath(route, first, last, trainTiles, lateral, preferredGap, rejects, budget)
{
  local end=route[last],start=route[first],w=AIMap.GetMapSizeX();
  local minx=AIMap.GetTileX(start),maxx=minx;
  local miny=AIMap.GetTileY(start),maxy=miny;
  for(local i=first;i<=last;i++) {
    minx=min(minx,AIMap.GetTileX(route[i]));maxx=max(maxx,AIMap.GetTileX(route[i]));
    miny=min(miny,AIMap.GetTileY(route[i]));maxy=max(maxy,AIMap.GetTileY(route[i]));
  }
  /* A human-sized local detour: the corridor is deliberately wider than
   * the historic parallel band, but a runaway search must fail closed. */
  local margin=8,maxPath=min(100,(last-first)*3+28);
  /* R42: the previous track mask is part of each A* state. A full No90
   * rescan on EVERY proposed extension repeated all native Manhattan calls
   * in its prefix; the exact full check remains at closure and acceptance. */
  local paths=[[route[first-1],start]],costs=[0],priorBits=[0];
  local open=AIList();open.Sort(AIList.SORT_BY_VALUE,true);
  open.AddItem(0,100*AIMap.DistanceManhattan(start,end));
  local seen={},offsets=[1,-1,w,-w],startNodes=budget.nodes;
  local startTests=("r52LoopTestsStart" in budget)
      ?budget.r52LoopTestsStart:budget.tests;
  while(!open.IsEmpty() && budget.nodes-startNodes<160
      && budget.tests-startTests<48 && budget.nodes<4000 && budget.tests<256
      && OpexOpsMeasureEnd(budget.mark)<60000
      && (!("phaseLimit" in budget) || OpexOpsMeasureEnd(budget.mark)<budget.phaseLimit)) {
    local id=open.Begin();open.RemoveItem(id);
    local path=paths[id],cur=path[path.len()-1],prev=path[path.len()-2];
    budget.nodes++;
    foreach(delta in offsets) {
      /* The outer guard alone could admit another expensive native probe
       * after a per-attempt or global cap was already exhausted. */
      local used=OpexOpsMeasureEnd(budget.mark);
      if(used>=60000 || (("phaseLimit" in budget) && used>=budget.phaseLimit)) break;
      local next=cur+delta;
      if(!AIMap.IsValidTile(next) || AIMap.DistanceManhattan(cur,next)!=1
          || next==prev) continue;
      if(cur==start && next!=start+lateral) continue;
      local duplicate=false;
      foreach(t in path) if(t==next) {duplicate=true;break;}
      if(duplicate || path.len()>=maxPath) continue;
      if(next!=end) {
        local x=AIMap.GetTileX(next),y=AIMap.GetTileY(next);
        if(x<minx-margin || x>maxx+margin || y<miny-margin || y>maxy+margin)
          continue;
        /* Terrain is unchanged throughout an AITestMode-only plan. Share
         * the existing per-plan cache with the direct path preflight; never
         * persist a tile proof across a real build, Save or Load. */
        if(!("railCache" in budget)) budget.railCache <- {};
        if(!(next in budget.railCache))
          budget.railCache.rawset(next,OpexRSRailSite(next));
        if(!budget.railCache[next]) continue;
      }
      local bit=OpexRSBit(prev,cur,next);
      if(bit==0) continue;
      /* Incremental No90 uses EXACTLY the same crossing pairs as
       * OpexRSNo90: priorBit is the mask at the previous path tile. It is
       * not a physical acceptance shortcut. */
      local priorBit=priorBits[id];
      if((priorBit==1 && bit==2) || (priorBit==2 && bit==1)
          || ((priorBit & 12)!=0 && (bit & 48)!=0)
          || ((priorBit & 48)!=0 && (bit & 12)!=0)) continue;
      local candidate=path.slice(0);candidate.append(next);
      if(next==end) {
        candidate.append(route[last+1]);
        if(candidate.len()<trainTiles+8 || !OpexRSNo90(candidate)) continue;
      }
      /* R52: no speculative BuildRailTrack on an incomplete frontier.
       * Native command authority remains OpexRSRailOps on complete paths. */
      if(next==end) {
        if(budget.tests>=256 || budget.tests-startTests>=48) break;
        /* Conservative cap: no more than the historical 48 native tests
         * are even attempted on one A* invocation. */
        if(candidate.len()-2>48-(budget.tests-startTests)) continue;
        local ops=OpexRSRailOps(candidate,1,candidate.len()-2,budget);
        if(ops!=null) return {path=candidate,ops=ops};
        continue;
      }
      local travel=costs[id]+100;
      if(bit>2) travel+=20;
      /* Prefer a useful second track rather than hugging the mainline;
       * never turn this preference into a geometrical veto. */
      if(preferredGap>1 && path.len()>3) {
        local nearest=preferredGap+1;
        for(local i=first;i<=last;i++)
          nearest=min(nearest,AIMap.DistanceManhattan(next,route[i]));
        if(nearest<preferredGap) travel+=25*(preferredGap-nearest);
      }
      local key=cur+":"+next;
      if(key in seen && seen[key]<=travel) continue;
      seen.rawset(key,travel);
      local nid=paths.len();paths.append(candidate);costs.append(travel);
      priorBits.append(bit);
      open.AddItem(nid,travel+100*AIMap.DistanceManhattan(next,end));
    }
  }
  /* A* with no opcode allowance has not ruled out a physical path. Keep
   * budget exhaustion distinguishable from a bounded real search failure. */
  if(OpexOpsMeasureEnd(budget.mark)>=60000
      || (("phaseLimit" in budget) && OpexOpsMeasureEnd(budget.mark)>=budget.phaseLimit))
    return OpexRSLoopReject(rejects,"PATH_BUDGET_EXHAUSTED");
  return OpexRSLoopReject(rejects,"PATH_SEARCH_EXHAUSTED");
}

/* Cheap exact subset of the search: parallel side tiles, possibly following
 * bends in the ORIGINAL mainline. A shifted curve is only a *candidate*:
 * No90 and native BuildRailTrack still decide whether it is connected.
 * This is NEVER the only geometry method; the directed path search handles
 * independent detours and variable lateral distances. */
function OpexRSLoopDirectPath(route, first, last, lateral, gap, cache = null)
{
  if(first<2 || last+2>=route.len() || gap<1 || gap>4) return null;
  /* A single planning invocation sees an immutable map: all its command
   * probes run under AITestMode. Cache terrain and mainline predicates only
   * within that invocation; never persist either through a build or Load. */
  if(cache==null) cache={plainCache={},railCache={}};
  if(!("plainCache" in cache)) cache.plainCache <- {};
  if(!("railCache" in cache)) cache.railCache <- {};
  local d=route[first+1]-route[first];
  if(abs(d)!=1 && abs(d)!=AIMap.GetMapSizeX()) return null;
  if(route[first]-route[first-1]!=d || route[last+1]-route[last]!=d) return null;
  local path=[route[first-1],route[first]];
  for(local k=1;k<gap;k++) {
    local tile=route[first]+k*lateral;
    if(!(tile in cache.railCache))
      cache.railCache.rawset(tile,OpexRSRailSite(tile));
    if(!cache.railCache[tile] || AIMap.DistanceManhattan(route[first],tile)!=k) return null;
    path.append(tile);
  }
  for(local i=first;i<=last;i++) {
    local oldTile=route[i];
    if(!(oldTile in cache.plainCache))
      cache.plainCache.rawset(oldTile,OpexRSPlain(oldTile));
    if(!cache.plainCache[oldTile]
        || AIMap.DistanceManhattan(oldTile,route[i+1])!=1) return null;
    local tile=route[i]+gap*lateral;
    if(!(tile in cache.railCache))
      cache.railCache.rawset(tile,OpexRSRailSite(tile));
    if(!cache.railCache[tile] || AIMap.DistanceManhattan(oldTile,tile)!=gap) return null;
    path.append(tile);
  }
  for(local k=gap-1;k>0;k--) {
    local tile=route[last]+k*lateral;
    if(!(tile in cache.railCache))
      cache.railCache.rawset(tile,OpexRSRailSite(tile));
    if(!cache.railCache[tile] || AIMap.DistanceManhattan(route[last],tile)!=k) return null;
    path.append(tile);
  }
  path.append(route[last]);path.append(route[last+1]);
  return OpexRSNo90(path)?path:null;
}

/* R84 TEST-ONLY: four orthogonal rail segments, bounded enumeration.
 * No A*, no topology mutation; the existing LoopAt/No90/RailOps/PBS/owner
 * must approve the whole route. A leg is >=1 tile and <=4 sideways; along
 * the mainline, travel <=18. Native 6500-attempt and 42k/60k remain strict. */
function OpexRSDogleg4(route,first,last,length,lateral,budget,r84Cap)
{
  if(route==null || budget==null || first<2 || last+2>=route.len()
      || OpexOpsMeasureEnd(budget.mark)>=r84Cap) return null;
  local r84Start=route[first],r84End=route[last],r84D=route[first+1]-r84Start;
  local r84W=AIMap.GetMapSizeX();
  if((abs(r84D)!=1 && abs(r84D)!=r84W)
      || route[first]-route[first-1]!=r84D
      || route[last+1]-route[last]!=r84D) return null;
  local r84Along=(abs(r84D)==1
      ?(AIMap.GetTileX(r84End)-AIMap.GetTileX(r84Start))
      :(AIMap.GetTileY(r84End)-AIMap.GetTileY(r84Start)))*(r84D>0?1:-1);
  local r84Side=(abs(r84D)==1
      ?(AIMap.GetTileY(r84End)-AIMap.GetTileY(r84Start))
      :(AIMap.GetTileX(r84End)-AIMap.GetTileX(r84Start)))*(lateral>0?1:-1);
  if(r84Along<2 || r84Along>18 || r84Side<1 || r84Side>3) return null;
  local r84Tries=0;
  for(local r84Out=r84Side+1;r84Out<=min(4,r84Side+3);r84Out++) {
    for(local r84Forward=r84Along-1;r84Forward>=1;r84Forward--) {
      if(r84Tries>=24 || OpexOpsMeasureEnd(budget.mark)>=r84Cap)
        return null;
      r84Tries++;
      local r84Back=r84Out-r84Side,r84Finish=r84Along-r84Forward;
      /* Exactly four legs: lateral, forward, reverse lateral, forward. */
      local r84Legs=[{delta=lateral,n=r84Out},
                     {delta=r84D,n=r84Forward},
                     {delta=-lateral,n=r84Back},
                     {delta=r84D,n=r84Finish}];
      local r84Path=[route[first-1],r84Start],r84Cur=r84Start,r84Good=true;
      foreach(r84Leg in r84Legs) {
        for(local r84J=0;r84J<r84Leg.n;r84J++) {
          local r84Next=r84Cur+r84Leg.delta;
          if(!AIMap.IsValidTile(r84Next)
              || AIMap.DistanceManhattan(r84Cur,r84Next)!=1) {
            r84Good=false;break;
          }
          r84Path.append(r84Next);r84Cur=r84Next;
        }
        if(!r84Good) break;
      }
      if(!r84Good || r84Cur!=r84End || r84Path.len()+1<length+8)
        continue;
      r84Path.append(route[last+1]);
      /* R90: return geometric proposal. Exactly unchanged OpexRSLoopAt
       * immediately checks OpexRSRailOps (RailSite/No90/AITestMode for
       * each tile), outer switch No90, PBS, depot, ownership and command
       * integrity. Do not spend scarce 1800 shaping opcodes duplicating
       * that entire native preflight before the 6500-attempt authority. */
      return r84Path;
    }
  }
  return null;
}

function OpexRSLoopAt(route, first, length, side, rejects = null, serviceDepot = -1, gap = 1, span = 0, budget = null, straightOnly = false, preparedDirect = null)
{
  /* In particular, do not enter expensive terrain, PBS and native-command
   * preflights when a previous A* has already spent this attempt allowance. */
  if(budget!=null && ("mark" in budget)) {
    local used=OpexOpsMeasureEnd(budget.mark);
    if(used>=60000 || (("phaseLimit" in budget) && used>=budget.phaseLimit))
      return OpexRSLoopReject(rejects,"PATH_BUDGET_EXHAUSTED");
  }
  local last = first+length+4+span;
  if (first < 2 || last+2 >= route.len())
    return OpexRSLoopReject(rejects,"WINDOW_BOUND");
  local d = route[first+1]-route[first],dLast=route[last+1]-route[last];
  if ((abs(d) != 1 && abs(d) != AIMap.GetMapSizeX())
      || (abs(dLast)!=1 && abs(dLast)!=AIMap.GetMapSizeX()))
    return OpexRSLoopReject(rejects,"CURVED_OR_BRIDGE");
  /* The branch begins/ends at a private single-piece mainline turnout.
   * Middle mainline tiles are deliberately unrestricted (curves, slopes,
   * bridges) because the pathfinder never builds on them. */
  if(route[first]-route[first-1]!=d || route[last+1]-route[last]!=d)
    return OpexRSLoopReject(rejects,"SWITCH_APPROACH");
  local lateral = side * (abs(d) == 1 ? AIMap.GetMapSizeX() : 1);
  /* The new branch's first curved rail is immediately adjacent to an OLD
   * mainline rail at first-1. The old V3g check ran OpexRSNo90 only on the
   * siding path starting at first-1; it never compared that old rail with
   * the NEW turnout. A native train consequently reverses at the turnout
   * even though both rail pieces and all AITestMode commands are valid.
   * Test the joined itinerary, rather than accepting two separately valid
   * rails that make a forbidden 90-degree pair at their boundary. */
  if(!OpexRSNo90([route[first-2],route[first-1],route[first],route[first]+lateral]))
    return OpexRSLoopReject(rejects,"SWITCH_OUTER_90");
  foreach(i in [first-1,first,first+1,last-1,last,last+1]) {
    local t = route[i];
    if (!OpexRSPlain(t) || OpexTileTrackCount(t) != 1
        || (i>0 && AIMap.DistanceManhattan(route[i-1],t)!=1))
      return OpexRSLoopReject(rejects,"MAIN_NOT_SIMPLE_FLAT");
  }
  if(!OpexRSOldMainPBSReady(route,last-1,last-2,AIRail.SIGNALTYPE_PBS_ONEWAY))
    return OpexRSLoopReject(rejects,"MAIN_PBS_PREFLIGHT");
  if(!OpexRSRailSite(route[first]+lateral))
    return OpexRSLoopReject(rejects,"SIDING_TERRAIN_OCCUPIED");
  if(budget==null) budget={nodes=0,tests=0,tested={},mark=OpexOpsMeasureBegin()};
  /* R52: one 48-test window shared by pretrace AND A*. */
  if("r52LoopTestsStart" in budget) budget.r52LoopTestsStart=budget.tests;
  else budget.r52LoopTestsStart <- budget.tests;
  local found=null;
  local direct=preparedDirect;
  if(direct==null) direct=OpexRSLoopDirectPath(route,first,last,lateral,gap,budget);
  if(direct!=null) {
    local directOps=OpexRSRailOps(direct,1,direct.len()-2,budget);
    if(directOps!=null) found={path=direct,ops=directOps};
  }
  if(found==null && !straightOnly)
    found=OpexRSR52LoopPretrace(route,first,last,length,lateral,budget);
  if(found==null && !straightOnly)
    found=OpexRSLoopPath(route,first,last,length,lateral,gap,rejects,budget);
  if(found==null) return null;
  local path=found.path,ops=found.ops;
  /* Also inspect the last original rail AFTER the exiting turnout. Neither
   * end rail is an interior piece of 'path'; checking only that path misses
   * a forbidden bend on the unchanged route directly outside the LOOP. */
  if(path.len()<4 || path[0]!=route[first-1] || path[1]!=route[first]
      || path[path.len()-2]!=route[last] || path[path.len()-1]!=route[last+1])
    return OpexRSLoopReject(rejects,"SWITCH_ROUTE_MISMATCH");
  local joined=[route[first-2]];
  foreach(tile in path) joined.append(tile);
  joined.append(route[last+2]);
  if(!OpexRSNo90(joined))
    return OpexRSLoopReject(rejects,"SWITCH_OUTER_90");
  /* Future new-side PBS is a real single-bit rail piece with an adjacent
   * forward tile, well clear of both turnouts. */
  local sidePBS=-1,sideFront=-1,sideBit=0;
  /* A two-gap turnout uses a lateral *curve* at path[3]. PBS must sit
   * on an actual straight segment after that approach. Search the
   * complete new branch rather than assuming a fixed index. */
  for(local k=3;k+4<path.len();k++) {
    if(path[k]-path[k-1]!=path[k+1]-path[k]) continue;
    local bit=OpexRSBit(path[k-1],path[k],path[k+1]);
    if(bit==0 || (bit & (bit-1))!=0) continue;
    /* R3 on an independent native save showed that flipping this to path[k-1]
     * prevents the opposite train from entering the siding altogether. Keep
     * the V3g facing while the remaining physical path failure is diagnosed. */
    sidePBS=path[k];sideFront=path[k+1];sideBit=bit;break;
  }
  if(sidePBS<0 || sideBit==0
      || AIMap.DistanceManhattan(sidePBS,sideFront)!=1)
    return OpexRSLoopReject(rejects,"SIDE_PBS_PREFLIGHT");
  /* Prefer a depot on the outer side of the passing rail for BOTH trains.
   * A single depot at the old SOURCE is not proof that trains returning along
   * either platform can actually enter it: site123 native v7/v10 demonstrated
   * that the two trains can alternate which one never gets serviced. Fall
   * back to the ORIGINAL depot only when no safe lateral footprint exists. */
  local depot=null;
  /* All candidate windows belong to the same untouched old corridor. The
   * planner proves depot reachability once and shares that read-only result. */
  local reuseDepot=(rejects!=null && "depotProof" in rejects)?rejects.depotProof:
      OpexRSDepotReachable(serviceDepot,route);
  local center=(2+path.len()-3)/2;
  for(local shift=0;shift<path.len() && depot==null && !reuseDepot;shift++) {
    foreach(sign in [1,-1]) {
      local index=center+shift*sign;
      if(index<4 || index>path.len()-5) continue;
      local sideTile=path[index];
      local depotTile=sideTile+lateral;
      if(!OpexRSDepotSite(depotTile) || AIMap.DistanceManhattan(sideTile,depotTile)!=1) continue;
      /* A curved parallel branch may exist, but attach the depot only to a
       * truly straight branch segment; never add a new crossing at a bend. */
      if(sideTile-path[index-1]!=path[index+1]-sideTile) continue;
      local straight=OpexRSBit(path[index-1],sideTile,path[index+1]);
      local curve=OpexRSBit(path[index-1],sideTile,depotTile);
      if(straight==0 || curve==0 || (straight&curve)!=0) continue;
      local spurOK=false;local spurCost=0;
      { local cost=AIAccounting();local test=AITestMode();
        spurOK=AIRail.BuildRailTrack(sideTile,curve); spurCost=cost.GetCosts(); }
      if(!spurOK) continue;
      local depotOK=false;local depotCost=0;
      { local cost=AIAccounting();local test=AITestMode();
        depotOK=AIRail.BuildRailDepot(depotTile,sideTile); depotCost=cost.GetCosts(); }
      if(!depotOK) continue;
      depot={kind="depot",tile=depotTile,front=sideTile,quote=depotCost,
        spur={kind="rail",tile=sideTile,bit=curve,before=straight,
              after=straight|curve,quote=spurCost,prev=path[index-1],next=depotTile}};
      break;
    }
  }
  if(depot==null) {
    if(!reuseDepot) {
      if(DECISION_LOG) OpexDiagLog("RS_LOOP reason=NO_SAFE_DEPOT first="+first+" last="+last);
      return OpexRSLoopReject(rejects,"DEPOT_FOOTPRINT_OR_PREFLIGHT");
    }
    if(DECISION_LOG) OpexDiagLog("RS_LOOP reason=REUSE_ORIGINAL_DEPOT depot="+serviceDepot
        +" first="+first+" last="+last);
  }
  /* Both mainline switches must be the last rail commands. Until then the
   * newly laid passing track remains isolated from the running line. The
   * depot and its branch are built BEFORE connecting these switches. */
  /* Do not accidentally consume siding rails as switches when a trackbit
   * already exists or the AITestMode op list was pruned. */
  if(ops.len()<3 || ops[0].kind!="rail" || ops[0].tile!=route[first]
      || ops[ops.len()-1].kind!="rail" || ops[ops.len()-1].tile!=route[last])
    return OpexRSLoopReject(rejects,"SWITCH_OP_MISMATCH");
  local firstSwitch=ops.remove(0);
  local lastSwitch=ops.remove(ops.len()-1);
  if(depot!=null) {
    ops.append(depot.spur);
    ops.append({kind="depot",tile=depot.tile,front=depot.front,quote=depot.quote});
  }
  ops.append(lastSwitch);ops.append(firstSwitch);
  return { first = first, last = last, path = path, ops = ops, lateral = lateral, gap=gap, span=span,
    depot = depot==null?null:{tile=depot.tile,front=depot.front,track=depot.spur.after},
    signals = [
      { kind = "signal", tile = route[last-1], front = route[last-2], type = AIRail.SIGNALTYPE_PBS_ONEWAY },
      { kind = "signal", tile = sidePBS, front = sideFront, type = AIRail.SIGNALTYPE_PBS_ONEWAY }
    ] };
}

/* One rejected full-plan PREFLIGHT may be caused by interaction between the
 * selected LOOP and the SOURCE/signal footprint. Permit ONE different first
 * passing loop, never the same failed site. All native safety tests still
 * apply to the alternative; this is not a geometry override. */
function OpexRSPlan(line, route = null, excludedLoop = null, excludedSource = null)
{
  if (route == null) route = OpexV284Trace(line);
  if (route == null || route.len() < 35 || route.len() > 1200) {
    OpexDiagLog("RS_PLAN line="+line.lineId+" reason=ROUTE length="+(route==null?-1:route.len()));return null;
  }
  local length16 = AIVehicle.GetLength(line.vehicles[0]);
  if (length16 <= 0 || length16 > line.platformA.length*16
      || length16 > line.platformB.length*16) return null;
  local length = (length16+15)/16;
  local source = OpexRSSourcePlan(line, route, length,excludedSource);
  if (source == null) {OpexDiagLog("RS_PLAN line="+line.lineId+" reason=SOURCE");return null;}
  /* Full existing-route verification is required before accepting any plan,
   * but has no safety effect when no SOURCE candidate exists at all. Defer
   * this expensive pass until a physical SOURCE plan has been discovered. */
  local physicalIssue=OpexRSExistingRouteIssue(route);
  if (physicalIssue!="OK") {
    OpexDiagLog("RS_PLAN line="+line.lineId+" reason=ROUTE_PHYSICAL length="+route.len()
        +" issue="+physicalIssue);return null;
  }
  /* A bridge/tunnel occupies two entries but many physical tiles. Siding
   * intervals must use physical distance, never the trace array index. The
   * source turnout is already an initial meeting point; find the next loop
   * near 100 travelled tiles, away from its construction footprint. */
  local distance=[0];
  for (local k=1;k<route.len();k++)
    distance.append(distance[k-1]+AIMap.DistanceManhattan(route[k-1],route[k]));
  local physicalLength=distance[distance.len()-1];
  local loops=[];local minFirst=source.joinIndex+length+8;
  local desired=distance[source.joinIndex]+95;
  /* Two trains require one meeting place. Place it near 100 tiles on normal
   * AUTO150 corridors, or near the middle on very long routes. Extra loops
   * are not bought merely because route length permits them. */
  if(physicalLength-distance[source.joinIndex]>250)
    desired=(distance[source.joinIndex]+physicalLength)/2;
  else if(desired>=physicalLength-length-12 && minFirst<distance.len()) {
    /* On 60-130-tile corridors, aiming a fixed 95 tiles after SOURCE can
     * place the target beyond the SINK. The actual legal corridor begins
     * AFTER source tail/switch clearance and ends BEFORE sink clearance.
     * Search its midpoint without relaxing any subsequent PBS/No90/native
     * command verification. An empty corridor still returns no loop. */
    local earliest=distance[minFirst],latest=physicalLength-length-13;
    if(earliest<latest) desired=(earliest+latest)/2;
  }
  local planMark=OpexOpsMeasureBegin();
  local loopBudget={nodes=0,tests=0,tested={},mark=planMark,plainCache={},railCache={}};
  while(desired<physicalLength-length-12 && loops.len()<1) {
    local loopRejects={depotProof=OpexRSDepotReachable(line.depot,route)};
    local center=-1;local bestDelta=1000000;
    for(local k=minFirst;k<route.len()-length-12;k++) {
      local delta=abs(distance[k]-desired);
      if(delta<bestDelta) {bestDelta=delta;center=k;}
    }
    if(center<0) break;
    local found=null;
    /* R52: use the SAME original minFirst and physical desired distance.
     * Screen entire eligible corridor for a CHEAP one-gap direct witness
     * BEFORE paying for a long A* near the old arbitrary center. No window
     * gains a PBS/No90/owner/rail/depots exemption: LoopAt still certifies.
     * Rank by abs(PHYSICAL distance - desired), not by smallest first index;
     * a source-near site may rank only if no closer legal direct candidate. */
    if(found==null && OpexOpsMeasureEnd(planMark)<12000) {
      local r52DirectRanked=AIList();r52DirectRanked.Sort(AIList.SORT_BY_VALUE,true);
      local r52DirectWindows=[];
      /* Keep the first screening pass in only the first 5.5k of the original
       * 12k cheap-direct preflight, and never expand the global 60k cap. */
      /* A coarse whole-corridor pass precedes finer residues. This avoids
       * spending the entire preflight quota on the earliest indices only. */
      local r52Reach=max(1,route.len()-length-9-minFirst);
      local r52Stride=max(1,(r52Reach+23)/24);
      for(local scanPhase=0;scanPhase<r52Stride
          && OpexOpsMeasureEnd(planMark)<5500;scanPhase++) {
      for(local first=minFirst+scanPhase;first+length+6<route.len()-3
          && OpexOpsMeasureEnd(planMark)<5500;first+=r52Stride) {
        local last=first+length+4;
        if(last+2>=route.len()) continue;
        local d=route[first+1]-route[first];
        if((abs(d)!=1 && abs(d)!=AIMap.GetMapSizeX())
            || route[first]-route[first-1]!=d
            || route[last+1]-route[last]!=d) continue;
        foreach(side in [-1,1]) {
          local lateral=side*(abs(d)==1?AIMap.GetMapSizeX():1);
          if(!OpexRSNo90([route[first-2],route[first-1],
                           route[first],route[first]+lateral])) continue;
          if(excludedLoop!=null && first==excludedLoop.first
              && lateral==excludedLoop.lateral
              && (!("span" in excludedLoop) || excludedLoop.span==0)) continue;
          local direct=OpexRSLoopDirectPath(route,first,last,lateral,1,loopBudget);
          if(direct==null) continue;
          local id=r52DirectWindows.len();
          r52DirectWindows.append({first=first,side=side,path=direct});
          /* Same desired physical target, with deterministic tie preference. */
          r52DirectRanked.AddItem(id,abs(distance[first]-desired)*100+(side==1?1:0));
        }
      }
      }
      while(!r52DirectRanked.IsEmpty() && found==null
          && OpexOpsMeasureEnd(planMark)<12000) {
        local id=r52DirectRanked.Begin();r52DirectRanked.RemoveItem(id);
        local candidate=r52DirectWindows[id];
        found=OpexRSLoopAt(route,candidate.first,length,candidate.side,
                           loopRejects,line.depot,1,0,loopBudget,true,candidate.path);
      }
    }
    /* Preselect plausible pairs across the physical target, rather than
     * letting the FIRST expensive A* consume all 60k opcodes. A straight
     * valid-sided corridor is a fast positive witness, not a veto on A*.
     * Try the closest such witnesses first, with native commands required
     * before accepting any plan. */
    /* Do not let one target near 100 tiles monopolize all testing. Short
     * train crossings can be much easier in the final quarter of an old
     * corridor (the historical line27 passes at first=122). Longer trains
     * benefit from more waiting room and therefore prefer span=8 first.
     * These are priority choices, never hard feasibility boundaries. */
    local centers=length<=3?[max(center,route.len()*3/4),center]:[center,route.len()*3/4];
    local spans=length<=3?[0,8,20]:[8,0,20];
    foreach(shortCenter in centers) {
    foreach(span in spans) {
    for(local offset=0;offset<=min(24,route.len()) && found==null
        && OpexOpsMeasureEnd(planMark)<12000;offset++) {
      foreach(sign in [1,-1]) {
        local first=shortCenter+offset*sign;
        if(first<minFirst || first+length+6>=route.len()-3) continue;
        foreach(gap in [1,2,3]) foreach(side in [-1,1]) {
          local d=route[first+1]-route[first];
          if(abs(d)!=1 && abs(d)!=AIMap.GetMapSizeX()) continue;
          local lateral=side*(abs(d)==1?AIMap.GetMapSizeX():1);
          /* Avoid costly direct-path/native tests for a switch the train
           * cannot traverse because its preceding OLD rail is a curve. */
          if(first<2 || !OpexRSNo90([route[first-2],route[first-1],
                                    route[first],route[first]+lateral])) continue;
          if(first+length+span+6>=route.len()-3) continue;
          local direct=OpexRSLoopDirectPath(route,first,first+length+4+span,
                                           lateral,gap,loopBudget);
          if(direct==null) continue;
          if(excludedLoop!=null && first==excludedLoop.first
              && lateral==excludedLoop.lateral && gap==excludedLoop.gap) continue;
          found=OpexRSLoopAt(route,first,length,side,loopRejects,line.depot,
                             gap,span,loopBudget,true,direct);
          if(found!=null) break;
        }
        if(found!=null) break;
      }
    }
    if(found!=null || OpexOpsMeasureEnd(planMark)>=12000) break;
    }
    if(found!=null || OpexOpsMeasureEnd(planMark)>=12000) break;
    }
    /* R60 only after unchanged original near/far LOOP preflight.
     * R53B first25 positive L18 is preserved. Screen at most one
     * expensive direct witness, then test it at +6500 opcodes.
     * No global cap or rail/PBS/No90 relaxation; original diverse
     * A* remains last fallback. */
    local r60Start=OpexOpsMeasureEnd(planMark);
    local r55CurvedCandidate=null;
    /* R55 TEST ONLY: prioritize a few short and distributed complete paths.
     * Screening is capped by the SAME planMark; total 60k, diverse 42k,
     * SOURCE 45k/60k and 13k, native tests 256/48 remain unchanged.
     * Shortlist is provisional until the original LoopAt verifies all rails,
     * two PBS signals, exclusive old track, depot and transaction geometry.
     */
    if(found==null && r60Start<26000) {
      local r55Direct=[],r55Seen={},r55SeenCount=0;
      local r55Focus=[minFirst,
                      max(minFirst,(minFirst+center)/2-(length+6)),
                      (minFirst+center)/2,center,
                      route.len()/2,(route.len()*3)/4];
      local r55Spans=length<=3?[0,8,20]:[8,0,20];
      /* Search nearby, intermediate and distant windows in successive waves;
       * never assume a 100-tile site or a simple parallel translation. */
      foreach(r55Delta in [2,10,0,4,8,6,12,16]) {
        foreach(r55Origin in r55Focus) {
          foreach(r55Sign in [1,-1]) {
            if(OpexOpsMeasureEnd(planMark)>=r60Start+3800 || r55SeenCount>=96) break;
            local r55First=r55Origin+r55Sign*r55Delta;
            if(r55First<minFirst || r55First+length+6>=route.len()-3) continue;
            local r55D=route[r55First+1]-route[r55First];
            if((abs(r55D)!=1 && abs(r55D)!=AIMap.GetMapSizeX())
                || route[r55First]-route[r55First-1]!=r55D) continue;
            foreach(r55Span in r55Spans) {
              local r55Last=r55First+length+4+r55Span;
              if(r55Last+2>=route.len()) continue;
              local r55Out=route[r55Last+1]-route[r55Last];
              if((abs(r55Out)!=1 && abs(r55Out)!=AIMap.GetMapSizeX())
                  || route[r55Last+1]-route[r55Last]!=r55Out) continue;
              foreach(r55Side in [-1,1]) {
                if(OpexOpsMeasureEnd(planMark)>=r60Start+3800 || r55SeenCount>=96) break;
                local r55Lateral=r55Side*(abs(r55D)==1?AIMap.GetMapSizeX():1);
                local r55Key=r55First+":"+r55Last+":"+r55Lateral;
                if(r55Key in r55Seen) continue;
                r55Seen.rawset(r55Key,true);
                r55SeenCount++;
                if(excludedLoop!=null && r55First==excludedLoop.first
                    && r55Lateral==excludedLoop.lateral
                    && (!("span" in excludedLoop) || r55Span==excludedLoop.span)) continue;
                if(!OpexRSNo90([route[r55First-2],route[r55First-1],
                      route[r55First],route[r55First]+r55Lateral])) continue;
                /* One whole alternative route, no speculative half-rail. */
                local r55Path=OpexRSLoopDirectPath(route,r55First,r55Last,
                                      r55Lateral,1,loopBudget);
                if(r55Path==null) {
                  /* A curved/obstructed mainline cannot be translated.
                   * Retain just one non-direct pair for an unchanged A*;
                   * this is a search opportunity, never an acceptance. */
                  if(r55CurvedCandidate==null
                      && OpexRSRailSite(route[r55First]+r55Lateral))
                    r55CurvedCandidate={first=r55First,side=r55Side,
                                        span=r55Span};
                  continue;
                }
                local r55Joined=[route[r55First-2]];
                foreach(r55Tile in r55Path) r55Joined.append(r55Tile);
                r55Joined.append(route[r55Last+2]);
                if(!OpexRSNo90(r55Joined)) continue;
                r55Direct.append({first=r55First,side=r55Side,
                                  span=r55Span,path=r55Path});
              }
            }
          }
        }
      }
      local r55Attempts=0,r55TriedFirst={};
      foreach(r55Candidate in r55Direct) {
        if(found!=null || r55Attempts>=2 || OpexOpsMeasureEnd(planMark)>=min(42000,r60Start+20000))
          break;
        /* Do not let both orientations of one turnout pair consume the
         * entire early window before testing another physical location. */
        local r55Pair=r55Candidate.first+":"+r55Candidate.span;
        if(r55Pair in r55TriedFirst) continue;
        r55TriedFirst.rawset(r55Pair,true);
        r55Attempts++;
        local r55AttemptCap=min(42000,OpexOpsMeasureEnd(planMark)+6500);
        loopBudget.phaseLimit <- r55AttemptCap;
        found=OpexRSLoopAt(route,r55Candidate.first,length,r55Candidate.side,
                 loopRejects,line.depot,1,r55Candidate.span,loopBudget,
                 true,r55Candidate.path);
        loopBudget.rawdelete("phaseLimit");
      }
      if(DECISION_LOG) OpexDiagLog("RS_R60_SHORTLIST line="+line.lineId
          +" checked="+r55SeenCount+" direct="+r55Direct.len()
          +" curved="+(r55CurvedCandidate!=null?1:0)
          +" attempts="+r55Attempts+" spent="+OpexOpsMeasureEnd(planMark)
          +" found="+(found!=null?1:0));
    }
    /* R84: use exactly one complete four-leg dogleg before the old fallback.
     * The parent early/direct phase remains untouched. This replaces the
     * expensive R82 single A* curved probe, not the original broader search. */
    if(found==null && r55CurvedCandidate!=null
        && OpexOpsMeasureEnd(planMark)<42000) {
      local r84Start=OpexOpsMeasureEnd(planMark);
      local r84AttemptCap=min(42000,r84Start+6500);
      /* Keep time for exact native RailOps/PBS/depot authority after shaping. */
      local r84ShapeCap=min(r84AttemptCap,r84Start+1800);
      local r84First=r55CurvedCandidate.first;
      local r84Last=r84First+length+4+r55CurvedCandidate.span;
      local r84D=route[r84First+1]-route[r84First];
      local r84Lateral=r55CurvedCandidate.side
          *(abs(r84D)==1?AIMap.GetMapSizeX():1);
      loopBudget.phaseLimit <- r84AttemptCap;
      local r84Path=OpexRSDogleg4(route,r84First,r84Last,length,
                                  r84Lateral,loopBudget,r84ShapeCap);
      local r84ShapeSpent=OpexOpsMeasureEnd(planMark)-r84Start;
      /* R92: recover the EXACT original R84 all-new-rail invariant AFTER
       * the 1800-opcode geometric shaping step, BEFORE any native RailOps.
       * OpexRSRailOps alone would permit an existing OWNED rail when before
       * != 0, which is not equivalent to OpexRSRailSite on all new tiles.
       * Fail closed under the SAME 6500/42000 phase limit, no new allowance. */
      local r92SiteOK=(r84Path!=null && typeof r84Path=="array"
                        && r84Path.len()>=length+8);
      local r92Sites=0,r92Reject=r92SiteOK?"NONE":"NO_PATH";
      if(r92SiteOK) {
        for(local r92K=2;r92K<r84Path.len()-2;r92K++) {
          if(OpexOpsMeasureEnd(planMark)>=r84AttemptCap) {
            r92SiteOK=false;r92Reject="SITE_BUDGET";break;
          }
          if(!OpexRSRailSite(r84Path[r92K])) {
            r92SiteOK=false;r92Reject="SITE_OCCUPIED";break;
          }
          r92Sites++;
        }
      }
      /* A single expensive engine query can overshoot its entry allowance;
       * never enter LoopAt when even the next budget check has expired. */
      if(r92SiteOK && OpexOpsMeasureEnd(planMark)<r84AttemptCap)
        found=OpexRSLoopAt(route,r84First,length,r55CurvedCandidate.side,
                 loopRejects,line.depot,1,r55CurvedCandidate.span,loopBudget,
                 true,r84Path);
      else if(r92SiteOK) r92Reject="NATIVE_BUDGET";
      if(DECISION_LOG) OpexDiagLog("RS_R92_DOGLEG line="+line.lineId
          +" first="+r84First+" last="+r84Last
          +" length="+(r84Path==null?0:r84Path.len())
          +" shaping="+r84ShapeSpent+" site_checks="+r92Sites
          +" site_ok="+(r92SiteOK?1:0)+" reason="+r92Reject
          +" spent="+OpexOpsMeasureEnd(planMark)
          +" found="+(found!=null?1:0));
      loopBudget.rawdelete("phaseLimit");
    }
    /* R38/R39 native route evidence: line16 has viable preliminary switch
     * envelopes about eight indices BEFORE the 100-tile target; line34 has
     * several about thirteen indices before it. Scanning the nearest 96
     * offsets sequentially exhausts 60k before the diverse sites get A*.
     * Try a bounded, distributed shortlist BEFORE that exhaustive fallback.
     * This is not an acceptance shortcut: the exact same LoopAt checks old
     * track ownership, No90 at both switch boundaries, native track bits,
     * directional PBS, original depot reachability and transaction geometry.
     * R39 demonstrated that a single long A* can consume the whole early
     * phase (one attempt on EACH of L16/L34). R41 enforces a separate 6500
     * opcode ceiling PER ATTEMPT, including the alternate route regions.
     * The private 42k phase still leaves budget for the old full fallback;
     * total 60k budget and 256 native tests never change. */
    if(found==null && OpexOpsMeasureEnd(planMark)<42000) {
      local probed={},diverseAttempts=0;
      loopBudget.phaseLimit <- 42000;
      local diverseSpans=length<=3?[0,8,20,36]:[8,20,0,36];
      foreach(focus in [center+4,center-12,center-8,route.len()/2]) {
        if(found!=null || diverseAttempts>=4 || OpexOpsMeasureEnd(planMark)>=42000) break;
        local attemptedAtFocus=false;
        for(local spread=0;spread<=4 && !attemptedAtFocus && found==null
            && OpexOpsMeasureEnd(planMark)<42000;spread++) {
          foreach(sign in [1,-1]) {
            local first=focus+spread*sign;
            if(first<minFirst || first+length+6>=route.len()-3) continue;
            local d=route[first+1]-route[first];
            if(abs(d)!=1 && abs(d)!=AIMap.GetMapSizeX()) continue;
            foreach(span in diverseSpans) {
              local last=first+length+4+span;
              if(last+2>=route.len()) continue;
              local dLast=route[last+1]-route[last];
              if((abs(dLast)!=1 && abs(dLast)!=AIMap.GetMapSizeX())
                  || route[first]-route[first-1]!=d
                  || route[last+1]-route[last]!=dLast) continue;
              local simple=true;
              foreach(k in [first-1,first,first+1,last-1,last,last+1])
                if(!OpexRSPlain(route[k]) || OpexTileTrackCount(route[k])!=1)
                  {simple=false;break;}
              if(!simple) continue;
              foreach(side in [-1,1]) {
                local lateral=side*(abs(d)==1?AIMap.GetMapSizeX():1);
                if(!OpexRSRailSite(route[first]+lateral)
                    || !OpexRSNo90([route[first-2],route[first-1],
                                     route[first],route[first]+lateral])) continue;
                local key=first+":"+last+":"+lateral;
                if(key in probed) continue;
                probed.rawset(key,true);
                if(excludedLoop!=null && first==excludedLoop.first
                    && lateral==excludedLoop.lateral
                    && (!("span" in excludedLoop) || span==excludedLoop.span)) continue;
                diverseAttempts++;
                attemptedAtFocus=true;
                local attemptCap=min(42000,OpexOpsMeasureEnd(planMark)+6500);
                loopBudget.phaseLimit=attemptCap;
                if(DECISION_LOG) OpexDiagLog("RS_LOOP_DIVERSE line="+line.lineId
                    +" first="+first+" last="+last+" side="+side
                    +" span="+span+" attempt="+diverseAttempts
                    +" budget="+OpexOpsMeasureEnd(planMark)+" attempt_cap="+attemptCap);
                local beforeNodes=loopBudget.nodes,beforeTests=loopBudget.tests;
                found=OpexRSLoopAt(route,first,length,side,loopRejects,line.depot,
                                   1,span,loopBudget);
                if(DECISION_LOG) OpexDiagLog("RS_LOOP_DIVERSE_END line="+line.lineId
                    +" first="+first+" last="+last+" side="+side
                    +" spent="+OpexOpsMeasureEnd(planMark)
                    +" nodes_added="+(loopBudget.nodes-beforeNodes)
                    +" tests_added="+(loopBudget.tests-beforeTests)
                    +" found="+(found!=null?1:0));
                loopBudget.phaseLimit=42000;
                break;
              }
              if(attemptedAtFocus) break;
            }
            if(attemptedAtFocus) break;
          }
        }
      }
      loopBudget.phaseLimit=60000;
    }
    /* Longer corridors have curved and sloped runs: search all bounded
     * positions near the physical target rather than ruling out a legal
     * passing loop because it lies >48 trace entries from one portal. */
    for(local offset=0;offset<=min(96,route.len()) && found==null
        && OpexOpsMeasureEnd(planMark)<60000;offset++) {
      foreach(sign in [1,-1]) {
        local first=center+offset*sign;
        if(first<minFirst || first+length+6>=route.len()-3) continue;
        /* Different pairs of mainline switches, not three copies of one
         * translated segment. Short, medium and longer passing intervals
         * share native tile/bit proofs on this same unchanged map. */
        foreach(span in [0,8,20,36]) foreach(side in [-1,1]) {
          if(OpexOpsMeasureEnd(planMark)>=60000) break;
          if(loops.len()==0 && excludedLoop!=null && first==excludedLoop.first) {
            local d=route[first+1]-route[first];
            local lateral=side*(abs(d)==1?AIMap.GetMapSizeX():1);
            if(lateral==excludedLoop.lateral
                && (!("span" in excludedLoop) || span==excludedLoop.span)) continue;
          }
          if(found!=null) break;
          found=OpexRSLoopAt(route,first,length,side,loopRejects,line.depot,1,span,loopBudget);
          if(found!=null) break;
        }
        if(found!=null) break;
      }
    }
    if(found==null) {
      OpexDiagLog("RS_PLAN line="+line.lineId+" reason=LOOP target_dist="+desired
          +" center="+center+" center_tile="+route[center]
          +" trace="+route.len()+" physical="+physicalLength
          +" bound="+( ("WINDOW_BOUND" in loopRejects) ? loopRejects.WINDOW_BOUND : 0 )
          +" axis="+( ("CURVED_OR_BRIDGE" in loopRejects) ? loopRejects.CURVED_OR_BRIDGE : 0 )
          +" main="+( ("MAIN_NOT_SIMPLE_FLAT" in loopRejects) ? loopRejects.MAIN_NOT_SIMPLE_FLAT : 0 )
          +" occupied="+( ("SIDING_TERRAIN_OCCUPIED" in loopRejects) ? loopRejects.SIDING_TERRAIN_OCCUPIED : 0 )
          +" rail="+( ("RAIL_PREFLIGHT_OR_NO90" in loopRejects) ? loopRejects.RAIL_PREFLIGHT_OR_NO90 : 0 )
          +" main_pbs="+( ("MAIN_PBS_PREFLIGHT" in loopRejects) ? loopRejects.MAIN_PBS_PREFLIGHT : 0 )
          +" side_pbs="+( ("SIDE_PBS_PREFLIGHT" in loopRejects) ? loopRejects.SIDE_PBS_PREFLIGHT : 0 )
          +" depot="+( ("DEPOT_FOOTPRINT_OR_PREFLIGHT" in loopRejects) ? loopRejects.DEPOT_FOOTPRINT_OR_PREFLIGHT : 0 )
          +" switch="+( ("SWITCH_OP_MISMATCH" in loopRejects) ? loopRejects.SWITCH_OP_MISMATCH : 0 )
          +" path="+( ("PATH_SEARCH_EXHAUSTED" in loopRejects) ? loopRejects.PATH_SEARCH_EXHAUSTED : 0 )
          +" path_budget="+( ("PATH_BUDGET_EXHAUSTED" in loopRejects) ? loopRejects.PATH_BUDGET_EXHAUSTED : 0 )
          +" nodes="+loopBudget.nodes+" tests="+loopBudget.tests
          +" opcodes="+OpexOpsMeasureEnd(planMark));
      return null;
    }
    loops.append(found);
    minFirst=found.last+length+9;
    desired=distance[found.first]+100;
  }
  if (loops.len() == 0) {
    OpexDiagLog("RS_PLAN line="+line.lineId+" reason=NO_PASSING_LOOP physical="+physicalLength);
    return null;
  }
  local doubleTiles = 0;
  foreach (loop in loops) doubleTiles += loop.last-loop.first+1;
  if (doubleTiles*2 >= physicalLength) return null;
  local signals = [];
  foreach (sig in source.signals) signals.append(sig);
  foreach (loop in loops) foreach (sig in loop.signals) signals.append(sig);
  local sink = null;
  for (local k = route.len()-2; k > max(loops[loops.len()-1].last+length+2, route.len()-12); k--) {
    if (OpexRSPlain(route[k]) && OpexTileTrackCount(route[k]) == 1
        && route[k]-route[k-1] == route[k+1]-route[k]
        && OpexRSOldMainPBSReady(route,k,k+1,AIRail.SIGNALTYPE_PBS)) {
      sink = { kind = "signal", tile = route[k], front = route[k+1], type = AIRail.SIGNALTYPE_PBS };
      break;
    }
  }
  /* R63: native L34 terminal mainline bends at each tile.
   * Retain original straight PBS search above. Curve candidates are only
   * checked with the EXISTING full native OpexRSOldMainPBSReady engine test,
   * never accepted by geometry alone. No demolition, ownership alteration,
   * 90-degree relaxation, or globally increased search budget. */
  if(sink==null) {
    local r63Mark=OpexOpsMeasureBegin();
    local r63Checked=0,r63Native=0;
    local r63Min=max(loops[loops.len()-1].last+length+2,route.len()-12);
    for(local k=route.len()-2;k>r63Min;k--) {
      if(r63Native>=3 || OpexOpsMeasureEnd(r63Mark)>=6500) break;
      if(!OpexRSPlain(route[k]) || OpexTileTrackCount(route[k])!=1
          || route[k]-route[k-1]==route[k+1]-route[k]) continue;
      r63Checked++;
      r63Native++;
      if(OpexRSOldMainPBSReady(route,k,k+1,AIRail.SIGNALTYPE_PBS)) {
        sink={kind="signal",tile=route[k],front=route[k+1],
              type=AIRail.SIGNALTYPE_PBS};
        break;
      }
    }
    if(DECISION_LOG) OpexDiagLog("RS_R63_SINK_CURVE line="+line.lineId
        +" checked="+r63Checked+" native="+r63Native
        +" ops="+OpexOpsMeasureEnd(r63Mark)
        +" found="+(sink!=null?1:0));
  }
  if (sink == null) {OpexDiagLog("RS_PLAN line="+line.lineId+" reason=SINK");return null;}
  signals.append(sink);
  local ops = [source.stationOp];
  foreach (op in source.ops) ops.append(op);
  foreach (loop in loops) foreach (op in loop.ops) ops.append(op);
  /* A signal inside a single section would make it an unsafe waiting point.
   * Remove existing signals only while the sole original train is parked. */
  for (local i = 1; i < route.len()-1; i++) {
    if (!OpexRSPlain(route[i])) continue;
    foreach (front in [route[i-1],route[i+1]]) {
      local signalType = AIRail.GetSignalType(route[i], front);
      if (signalType != AIRail.SIGNALTYPE_NONE)
        ops.append({kind="remove_signal",tile=route[i],front=front,before=signalType,quote=0});
    }
  }
  foreach (sig in signals) { sig.quote <- 0; ops.append(sig); }
  local quote = 0; foreach (op in ops) quote += max(0,op.quote);
  return { route=route, source=source, loops=loops, signals=signals, ops=ops,
           length16=length16, quote=quote+signals.len()*1000, doubleTiles=doubleTiles };
}

/* A depot's owner/type alone does not prove access. Follow oriented track
 * connections from its mouth; depot spurs and bridges are ordinary branches.
 * A bounded search may prove access, but exhaustion never grants it. */
function OpexRSDepotReachable(depot,route)
{
  if(!AIMap.IsValidTile(depot) || !AIRail.IsRailDepotTile(depot)
      || !AICompany.IsMine(AITile.GetOwner(depot))
      || AIRail.GetRailType(depot)!=AIRail.GetCurrentRailType()) return false;
  local front=AIRail.GetRailDepotFrontTile(depot),wanted={};
  foreach(t in route) wanted.rawset(t,true);
  local open=[{prev=depot,cur=front,prior=0}],seen={};local head=0;
  local offsets=[1,-1,AIMap.GetMapSizeX(),-AIMap.GetMapSizeX()];
  while(head<open.len() && head<256) {
    local s=open[head++],key=s.prev+":"+s.cur+":"+s.prior;
    if(key in seen) continue;
    seen.rawset(key,true);
    if(!AIMap.IsValidTile(s.cur) || !AICompany.IsMine(AITile.GetOwner(s.cur))) continue;
    if(AIBridge.IsBridgeTile(s.cur) || AITunnel.IsTunnelTile(s.cur)) {
      local other=AIBridge.IsBridgeTile(s.cur)?AIBridge.GetOtherBridgeEnd(s.cur):AITunnel.GetOtherTunnelEnd(s.cur);
      local span=AIMap.DistanceManhattan(s.cur,other);
      if(span<=1) continue;
      local direction=(other-s.cur)/span;
      if(s.prev==s.cur-direction) open.append({prev=s.cur,cur=other,prior=0});
      else if(s.prev==other) open.append({prev=s.cur,cur=s.cur-direction,prior=0});
      continue;
    }
    foreach(delta in offsets) {
      local next=s.cur+delta;
      if(!AIMap.IsValidTile(next) || AIMap.DistanceManhattan(s.cur,next)!=1
          || next==s.prev || (!AIRail.IsRailTile(next)
              && !AIBridge.IsBridgeTile(next) && !AITunnel.IsTunnelTile(next))) continue;
      if(!AIRail.AreTilesConnected(s.prev,s.cur,next)
          || !AIRail.AreTilesConnected(next,s.cur,s.prev)) continue;
      local bit=OpexRSBit(s.prev,s.cur,next);
      if(bit==0 || (s.prior==1 && bit==2) || (s.prior==2 && bit==1)
          || ((s.prior&12)!=0 && (bit&48)!=0)
          || ((s.prior&48)!=0 && (bit&12)!=0)) continue;
      if(s.cur in wanted && next in wanted) return true;
      if(!AIRail.IsRailDepotTile(next)) open.append({prev=s.cur,cur=next,prior=bit});
    }
  }
  return false;
}

/* Fail-closed proof for an untraceable other service. Spatially adjacent rail
 * is NOT a railway connection: adjacent foreign track (native line 1) and
 * adjacent independent OWN track (native line 27) both caused false vetoes.
 * Traverse oriented, actually connected rail triples instead. Seed every
 * known platform tile, each live vehicle and the depot, not merely the
 * service's preferred station lead; side branches can be shared in the middle.
 * Unknown platform layout, owners, bridge geometry or search exhaustion deny
 * the upgrade. Reaching even one used tile denies it conservatively, including
 * an X crossing whose separate trackbits cannot be distinguished cheaply. */
/* 2026-11-12 opcode fix. The oriented triple relation is symmetric (every
 * step is checked in both directions), so "a seed of the other service reaches
 * a used tile" is equivalent to "the corridor reaches that seed". Flood ONCE
 * from the corridor instead of once per untraceable service (native 442018:
 * 21 floods, 1 093 811 opcodes). `reach` holds every own tile that an oriented
 * path leaving the corridor arrives on; a depot counts only through its mouth.
 * Returns null (= proof unavailable, caller must refuse) on unknown owner,
 * degenerate bridge/tunnel or exhausted bound: never a partial table. */
RS_EXCL_STATS <- {floods=0,starts=0,states=0,ops=0,complete=false};

/* True when `tile` owns a rail piece leaving through the edge shared with its
 * neighbour `toward`. Adjacent rails whose trackbits do not touch that edge
 * are not connected. Depots open only at their mouth, bridge and tunnel
 * heads only at their axial entrance. */
function OpexRSEdgeOpen(tile,toward,offsets)
{
  if(AIRail.IsRailDepotTile(tile)) return toward==AIRail.GetRailDepotFrontTile(tile);
  if(AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
    local end=AIBridge.IsBridgeTile(tile)?AIBridge.GetOtherBridgeEnd(tile):AITunnel.GetOtherTunnelEnd(tile);
    local span=AIMap.DistanceManhattan(tile,end);
    /* Degenerate span: keep the start so that the flood refuses on it. */
    if(span<=1) return true;
    return toward==tile-(end-tile)/span;
  }
  foreach(delta in offsets) {
    local side=tile+delta;
    if(side!=toward && AIRail.AreTilesConnected(toward,tile,side)) return true;
  }
  return false;
}

function OpexRSCorridorReach(used)
{
  local me=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
  local w=AIMap.GetMapSizeX(),offsets=[1,-1,w,-w];
  local open=[],seen={},reach={},head=0;
  local mark=OpexOpsMeasureBegin();
  RS_EXCL_STATS.floods++; RS_EXCL_STATS.complete=false;
  /* Own tiles bordering the corridor: owner filter in one AIList pass. */
  local fringe=AITileList();
  foreach(u,_ in used) {
    foreach(delta in offsets) { local n=u+delta; if(!(n in used)) fringe.AddTile(n); }
    /* A span represented by its two heads is entered from the far head. */
    if(AIBridge.IsBridgeTile(u) || AITunnel.IsTunnelTile(u)) {
      local end=AIBridge.IsBridgeTile(u)?AIBridge.GetOtherBridgeEnd(u):AITunnel.GetOtherTunnelEnd(u);
      if(!AIMap.IsValidTile(end) || AIMap.DistanceManhattan(u,end)<=1) return null;
      if(!(end in used)) open.append([u,end]);
    }
  }
  fringe.Valuate(AITile.GetOwner); fringe.KeepValue(me);
  for(local n=fringe.Begin();!fringe.IsEnd();n=fringe.Next()) {
    if(!AIRail.IsRailTile(n) && !AIRail.IsRailDepotTile(n)
        && !AIBridge.IsBridgeTile(n) && !AITunnel.IsTunnelTile(n)) continue;
    foreach(delta in offsets) {
      local u=n-delta;
      /* The corridor tile must really own a track piece leaving toward n;
       * the n side is verified when the state is dequeued. */
      if(u in used && AIMap.DistanceManhattan(u,n)==1
          && OpexRSEdgeOpen(u,n,offsets)) open.append([u,n]);
    }
  }
  RS_EXCL_STATS.starts=open.len();
  while(head<open.len()) {
    /* Same bounds as the former per-service proof; exhaustion is never
     * interpreted as independence. */
    if(head>=4096 || ((head&15)==0 && OpexOpsMeasureEnd(mark)>=90000)) return null;
    local state=open[head++],previous=state[0],tile=state[1];
    local key=previous+":"+tile;
    if(key in seen) continue;
    seen.rawset(key,true);
    /* Paths continuing through the corridor restart from that used tile. */
    if(tile in used) continue;
    if(!AIMap.IsValidTile(tile) || AITile.GetOwner(tile)!=me) return null;
    if(AIRail.IsRailDepotTile(tile)) {
      if(previous==AIRail.GetRailDepotFrontTile(tile)) reach.rawset(tile,true);
      continue;
    }
    if(AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
      local end=AIBridge.IsBridgeTile(tile)?AIBridge.GetOtherBridgeEnd(tile):AITunnel.GetOtherTunnelEnd(tile);
      local span=AIMap.DistanceManhattan(tile,end);
      if(span<=1) return null;
      local step=(end-tile)/span;
      /* Lateral contact with a bridge head is neither an entrance nor a
       * connection: only the two real accesses record and traverse it. */
      if(previous==tile-step) {reach.rawset(tile,true);open.append([tile,end]);}
      else if(previous==end) {reach.rawset(tile,true);open.append([tile,tile-step]);}
      continue;
    }
    local entered=false;
    foreach(delta in offsets) {
      local next=tile+delta;
      /* Cheapest decisive test first; the conjunction is unchanged. */
      if(next==previous || !AIRail.AreTilesConnected(previous,tile,next)) continue;
      /* This tile owns a track piece touching the side we arrive from: the
       * arrival is a real connection, not mere adjacency. */
      entered=true;
      if(!AIMap.IsValidTile(next) || AIMap.DistanceManhattan(tile,next)!=1
          || AITile.GetOwner(next)!=me
          || (!AIRail.IsRailTile(next) && !AIRail.IsRailDepotTile(next)
              && !AIBridge.IsBridgeTile(next) && !AITunnel.IsTunnelTile(next))
          || !AIRail.AreTilesConnected(next,tile,previous)) continue;
      open.append([tile,next]);
    }
    if(entered) reach.rawset(tile,true);
  }
  RS_EXCL_STATS.states=head; RS_EXCL_STATS.ops=OpexOpsMeasureEnd(mark);
  RS_EXCL_STATS.complete=true;
  return reach;
}

/* A doubled line has two independently routed station/depot chains. A
 * primary-lane V284Trace cannot certify its secondary lane. Check the entire
 * SECOND platform footprint on both ends and its depot mouth against the
 * one complete, physically oriented reach. This proof is local to this call:
 * no result survives a change of track, owner, vehicle or Save/Load. */
function OpexRSSecondaryDisjoint(other,used,reach)
{
  if(!("stationA2" in other) || !("stationB2" in other)
      || !("platformA2" in other) || !("platformB2" in other)
      || !("depot2" in other) || typeof other.stationA2!="integer"
      || typeof other.stationB2!="integer" || typeof other.depot2!="integer"
      || !AIRail.IsRailDepotTile(other.depot2)
      || !AICompany.IsMine(AITile.GetOwner(other.depot2))
      || other.depot2 in used || other.depot2 in reach) return false;
  local front=AIRail.GetRailDepotFrontTile(other.depot2);
  if(!AIMap.IsValidTile(front) || !AICompany.IsMine(AITile.GetOwner(front))
      || front in used) return false;
  foreach(side in [0,1]) {
    local end=side==0?other.stationA2:other.stationB2;
    local p=side==0?other.platformA2:other.platformB2;
    if(!AIMap.IsValidTile(end) || !AIRail.IsRailStationTile(end)
        || !AICompany.IsMine(AITile.GetOwner(end))
        || end in used || end in reach) return false;
    local station=AIStation.GetStationID(end);
    if(p==null || typeof p!="table" || !("anchor" in p) || !("step" in p)
        || !("length" in p) || !AIStation.IsValidStation(station)
        || typeof p.anchor!="integer" || typeof p.step!="integer"
        || typeof p.length!="integer" || p.length<1 || p.length>12
        || (p.step!=1 && p.step!=AIMap.GetMapSizeX())) return false;
    for(local k=0;k<p.length;k++) {
      local tile=p.anchor+p.step*k;
      if(!AIMap.IsValidTile(tile) || !AIRail.IsRailStationTile(tile)
          || AIStation.GetStationID(tile)!=station
          || !AICompany.IsMine(AITile.GetOwner(tile))
          || tile in used || tile in reach) return false;
    }
  }
  return true;
}

function OpexRSNetworkDisjoint(other,used,reach)
{
  if(reach==null || typeof reach!="table") return false;
  local dual=("doubleTrack" in other) && other.doubleTrack==1;
  if(!("stationA" in other) || !("stationB" in other)
      || !("platformA" in other) || !("platformB" in other)
      || !("depot" in other) || typeof other.depot!="integer"
      || !AIRail.IsRailDepotTile(other.depot)
      || (("doubleTrack" in other) && other.doubleTrack!=0 && !dual)
      || (!dual && (("platformA2" in other) && other.platformA2!=null))
      || (!dual && (("platformB2" in other) && other.platformB2!=null))) return false;
  if(dual && !OpexRSSecondaryDisjoint(other,used,reach)) return false;
  /* The station tiles are the origin and end of OpexV284Trace: testing them
   * makes this proof at least as strict as the traced-route comparison. */
  if(typeof other.stationA!="integer" || typeof other.stationB!="integer"
      || other.stationA in used || other.stationA in reach
      || other.stationB in used || other.stationB in reach) return false;
  foreach(side in [0,1]) {
    local p=side==0?other.platformA:other.platformB;
    local station=AIStation.GetStationID(side==0?other.stationA:other.stationB);
    if(p==null || typeof p!="table" || !("anchor" in p) || !("step" in p)
        || !("length" in p) || !AIStation.IsValidStation(station)
        || typeof p.anchor!="integer" || typeof p.step!="integer"
        || typeof p.length!="integer"
        || p.length<1 || p.length>12
        || (p.step!=1 && p.step!=AIMap.GetMapSizeX())) return false;
    for(local k=0;k<p.length;k++) {
      local tile=p.anchor+p.step*k;
      if(!AIMap.IsValidTile(tile) || !AIRail.IsRailStationTile(tile)
          || AIStation.GetStationID(tile)!=station
          || !AICompany.IsMine(AITile.GetOwner(tile))
          || tile in used || tile in reach) return false;
    }
  }
  /* A train stranded off its nominal route must still block an intersecting
   * corridor, whatever its heading: any oriented arrival on its tile vetoes. */
  if(("vehicles" in other) && other.vehicles!=null) foreach(v in other.vehicles) {
    if(!AIVehicle.IsValidVehicle(v)) continue;
    local tile=AIVehicle.GetLocation(v);
    if(!AIMap.IsValidTile(tile) || !AICompany.IsMine(AITile.GetOwner(tile))
        || tile in used || tile in reach) return false;
    if(AIRail.IsRailDepotTile(tile)) {
      local front=AIRail.GetRailDepotFrontTile(tile);
      if(!AIMap.IsValidTile(front) || !AICompany.IsMine(AITile.GetOwner(front))
          || front in used) return false;
    } else if(!AIRail.IsRailTile(tile) && !AIBridge.IsBridgeTile(tile)
        && !AITunnel.IsTunnelTile(tile)) return false;
  }
  if(!AICompany.IsMine(AITile.GetOwner(other.depot)) || other.depot in reach) return false;
  local front=AIRail.GetRailDepotFrontTile(other.depot);
  if(!AIMap.IsValidTile(front) || !AICompany.IsMine(AITile.GetOwner(front))
      || front in used) return false;
  return true;
}

function OpexRSPhysical(plan)
{
  if (OpexRSExistingRouteIssue(plan.route)!="OK" || !OpexRSPathPhysical(plan.source.path)) return false;
  if(!OpexRSStationShape(plan.source.stationOp) || !OpexRSOpDone(plan.source.stationOp)) return false;
  if("originalBerth" in plan.source) foreach(tile in plan.source.originalBerth)
    if(!AIRail.IsRailStationTile(tile)
        || AIStation.GetStationID(tile)!=plan.source.stationOp.station
        || AIRail.GetRailStationDirection(tile)!=plan.source.stationOp.direction) return false;
  foreach (tile in plan.source.berth)
    if (!AIRail.IsRailStationTile(tile)
        || AIStation.GetStationID(tile) != plan.source.stationOp.station) return false;
  foreach (loop in plan.loops) {
    if (!OpexRSPathPhysical(loop.path)) return false;
    /* Backward-compatible Load of an already-frozen v2 traffic journal whose
     * loop predated auxiliary depots. New loops always carry this witness. */
    if(("depot" in loop) && loop.depot!=null) {
      local depot=loop.depot;
      if(!AIRail.IsRailDepotTile(depot.tile)
          || AIRail.GetRailDepotFrontTile(depot.tile)!=depot.front
          || AITile.GetOwner(depot.tile)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)
          || !OpexRSPlain(depot.front)
          || AIRail.GetRailTracks(depot.front)!=depot.track) return false;
    }
  }
  foreach (sig in plan.signals)
    if (AIRail.GetSignalType(sig.tile,sig.front) != sig.type) return false;
  return true;
}
