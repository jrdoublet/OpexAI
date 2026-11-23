// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* Opt-in SIDINGS dispatcher. Persistent primitive journal, independent of P2/P4.
 * PBS in the engine owns reservations and tail release; observations below
 * NEVER grant a movement across a red signal or force a train to reverse.
 */
RS_JOURNAL <- {};
RS_NEXT_SCAN <- 0;
RS_LEGACY_HOLD <- false;
RS_RELOADED <- false;
RS_TRAFFIC_TICK <- 0;
/* Performance-only, deliberately NON-persistent. An unsuccessful geometric
 * plan owns no rail, train or journal: after an AI Load it may be reconsidered
 * safely. Avoid rebuilding the same impossible search every month. */
RS_REJECT_UNTIL <- {};
/* Bounded, non-persistent round-robin cursor. Calendar-modulo-line-count
 * repeatedly examined the same four eligible lines while later profitable
 * candidates were never visited (native r29). No physical ownership depends
 * on this cursor, so a Load may safely restart at zero. */
RS_SCAN_CURSOR <- 0;

function OpexRSProtected(line)
{
  /* A malformed legacy journal can no longer identify its exact originals.
   * Fence EVERY rail line until the uncertainty is resolved outside the AI;
   * guessing a line/vehicle from an ID would permit an irreversible sale. */
  return line != null && (("railSidings" in line)
      || (RS_LEGACY_HOLD && ("mode" in line) && line.mode=="rail"));
}

function OpexRSVehicleProtected(vehicle)
{
  /* INVALID_HOLD intentionally forgets a/b. A C52 ticket can predate Load:
   * a failed identity proof must prevent even unrelated rail retirement,
   * rather than relying on the lost VehicleID. */
  if(RS_LEGACY_HOLD && AIVehicle.IsValidVehicle(vehicle)
      && AIVehicle.GetVehicleType(vehicle)==AIVehicle.VT_RAIL) return true;
  foreach (id,j in RS_JOURNAL)
    if (vehicle == j.a || vehicle == j.b) return true;
  return false;
}

function OpexRSSignature(v)
{
  if (!AIVehicle.IsValidVehicle(v) || !AIVehicle.IsPrimaryVehicle(v)
      || AIVehicle.GetVehicleType(v) != AIVehicle.VT_RAIL) return "";
  local s = AIVehicle.GetEngineType(v)+":"+AIVehicle.GetUnitNumber(v)+":"
      +AIVehicle.GetLength(v)+":"+AIVehicle.GetGroupID(v);
  for (local k=0;k<AIVehicle.GetNumWagons(v);k++)
    s += ":"+AIVehicle.GetWagonEngineType(v,k);
  return s;
}

/* A station order refers to a StationID, not its first tile: OpenTTD 15.3's
 * GetOrderDestination() picks the first station tile, which changes when a
 * parallel platform is built. Never persist that transient tile as identity.
 * This is deliberately separate from the vehicle consist signature.
 * Empty means unknown/invalid: construction and replacement must HOLD.
 * Script orders exclude implicit servicing orders (NoAI API contract). */
function OpexRSOrders(v, ignore = -1)
{
  if (!AIVehicle.IsValidVehicle(v) || !AIVehicle.IsPrimaryVehicle(v)
      || AIVehicle.GetVehicleType(v)!=AIVehicle.VT_RAIL) return "";
  local count=AIOrder.GetOrderCount(v);
  if(count<=0 || ignore>=count) return "";
  local s="v2|"+count+"|";
  if(ignore>=0) s="v2|"+(count-1)+"|";
  for(local i=0;i<count;i++) {
    if(i==ignore) continue;
    if(!AIOrder.IsValidVehicleOrder(v,i) || AIOrder.IsVoidOrder(v,i)) return "";
    if(AIOrder.IsConditionalOrder(v,i)) {
      s+="C:"+AIOrder.GetOrderJumpTo(v,i)+":"+AIOrder.GetOrderCondition(v,i)
          +":"+AIOrder.GetOrderCompareFunction(v,i)+":"+AIOrder.GetOrderCompareValue(v,i)+";";
      continue;
    }
    local kind=""; local destination=-1;
    if(AIOrder.IsGotoStationOrder(v,i)) {
      local tile=AIOrder.GetOrderDestination(v,i);
      if(!AIMap.IsValidTile(tile) || !AIRail.IsRailStationTile(tile)
          || !AICompany.IsMine(AITile.GetOwner(tile))) return "";
      destination=AIStation.GetStationID(tile);
      if(!AIStation.IsValidStation(destination)) return "";
      kind="S";
    } else if(AIOrder.IsGotoDepotOrder(v,i)
        && (AIOrder.GetOrderFlags(v,i)&AIOrder.OF_GOTO_NEAREST_DEPOT)!=0) {
      /* Service-at-nearest-depot: no fixed destination tile by contract. */
      destination=-1; kind="N";
    } else if(AIOrder.IsGotoDepotOrder(v,i)) {
      local tile=AIOrder.GetOrderDestination(v,i);
      if(!AIMap.IsValidTile(tile) || !AIRail.IsRailDepotTile(tile)
          || !AICompany.IsMine(AITile.GetOwner(tile))) return "";
      destination=tile; kind="D";
    } else if(AIOrder.IsGotoWaypointOrder(v,i)) {
      local tile=AIOrder.GetOrderDestination(v,i);
      if(!AIMap.IsValidTile(tile) || !AICompany.IsMine(AITile.GetOwner(tile))) return "";
      destination=tile; kind="W";
    } else return "";
    s+=kind+":"+destination+":"+AIOrder.GetOrderFlags(v,i);
    if(kind=="S") s+=":"+AIOrder.GetStopLocation(v,i);
    if(kind=="S" || kind=="D") s+=":"+AIOrder.GetOrderRefit(v,i);
    s+=";";
  }
  return s;
}

function OpexRSJournalV2(j)
{
  return typeof j=="table" && ("version" in j) && j.version==2
      && ("orders" in j) && typeof j.orders=="string"
      && j.orders.len()>3 && j.orders.slice(0,3)=="v2|"
      && ("lineId" in j) && typeof j.lineId=="integer"
      && ("phase" in j) && typeof j.phase=="string"
      && ("a" in j) && typeof j.a=="integer"
      && ("b" in j) && typeof j.b=="integer"
      && ("sigA" in j) && typeof j.sigA=="string"
      && ("sigB" in j) && typeof j.sigB=="string"
      && ("cursor" in j) && typeof j.cursor=="integer" && j.cursor>=0
      && ("pending" in j) && (j.pending==null || typeof j.pending=="table")
      /* R57 WAIT is persistent only with one owned clone and no command intent. */
      && (j.phase!="WAIT_A_TAIL_CLEAR" || (j.b>=0 && j.pending==null))
      && ("depot" in j) && typeof j.depot=="integer"
      && ("railType" in j) && typeof j.railType=="integer"
      && ("plan" in j) && typeof j.plan=="table"
      && ("ops" in j.plan) && typeof j.plan.ops=="array"
      && j.cursor<=j.plan.ops.len()
      && ("route" in j.plan) && typeof j.plan.route=="array"
      && ("source" in j.plan) && typeof j.plan.source=="table"
      && ("loops" in j.plan) && typeof j.plan.loops=="array"
      && ("signals" in j.plan) && typeof j.plan.signals=="array"
      && ("length16" in j.plan) && typeof j.plan.length16=="integer"
      && ("trainPrice" in j) && typeof j.trainPrice=="integer"
      && ("reserve" in j) && typeof j.reserve=="integer"
      && ("spent" in j) && typeof j.spent=="integer"
      && ("deadline" in j) && typeof j.deadline=="integer"
      && ("reason" in j) && typeof j.reason=="string"
      && ("admission" in j) && typeof j.admission=="string"
      && ("loaded" in j) && typeof j.loaded=="bool"
      && ("costKnown" in j) && typeof j.costKnown=="bool"
      && ("sourceStation" in j) && typeof j.sourceStation=="integer"
      && ("sinkStation" in j) && typeof j.sinkStation=="integer"
      && ("cargo" in j) && typeof j.cargo=="integer"
      && ("positions" in j) && typeof j.positions=="table"
      && ("lastMotion" in j) && typeof j.lastMotion=="table"
      && ("deliveries" in j) && typeof j.deliveries=="table"
      && ("visits" in j) && typeof j.visits=="table"
      && ("lastObserve" in j) && typeof j.lastObserve=="integer";
}

function OpexRSPlanSafe(plan)
{
  if(typeof plan!="table" || !("route" in plan) || typeof plan.route!="array"
      || plan.route.len()<3 || !("source" in plan) || typeof plan.source!="table"
      || !("loops" in plan) || typeof plan.loops!="array"
      || !("signals" in plan) || typeof plan.signals!="array"
      || !("ops" in plan) || typeof plan.ops!="array"
      || !("length16" in plan) || typeof plan.length16!="integer"
      || plan.length16<=0 || !("path" in plan.source)
      || typeof plan.source.path!="array" || plan.source.path.len()<3
      || !("berth" in plan.source) || typeof plan.source.berth!="array"
      || !("stationOp" in plan.source) || typeof plan.source.stationOp!="table"
      || !("station" in plan.source.stationOp)
      || typeof plan.source.stationOp.station!="integer"
      || plan.source.berth.len()==0 || plan.loops.len()==0
      || plan.ops.len()==0) return false;
  foreach(t in plan.route)
    if(typeof t!="integer" || !AIMap.IsValidTile(t)) return false;
  foreach(t in plan.source.path)
    if(typeof t!="integer" || !AIMap.IsValidTile(t)) return false;
  foreach(t in plan.source.berth)
    if(typeof t!="integer" || !AIMap.IsValidTile(t)) return false;
  if(!OpexRSStationShape(plan.source.stationOp)
      || plan.source.berth.len()!=plan.source.stationOp.tiles.len()
      || plan.source.berth.len()*16<plan.length16) return false;
  for(local k=0;k<plan.source.berth.len();k++)
    if(plan.source.berth[k]!=plan.source.stationOp.tiles[k]) return false;
  if("originalBerth" in plan.source) {
    if(typeof plan.source.originalBerth!="array") return false;
    foreach(t in plan.source.originalBerth)
      if(typeof t!="integer" || !AIMap.IsValidTile(t)) return false;
  }
  foreach(op in plan.ops) {
    if(typeof op!="table" || !("kind" in op) || typeof op.kind!="string"
        || !("tile" in op) || typeof op.tile!="integer"
        || !AIMap.IsValidTile(op.tile)) return false;
    if(op.kind=="rail") {
      if(!("before" in op) || !("after" in op) || !("bit" in op)
          || typeof op.before!="integer" || typeof op.after!="integer"
          || typeof op.bit!="integer") return false;
      if(op.before<0 || op.before>63 || op.after<0 || op.after>63
          || (op.bit!=1 && op.bit!=2 && op.bit!=4 && op.bit!=8
              && op.bit!=16 && op.bit!=32)
          || (op.before & op.bit)!=0 || op.after!=(op.before | op.bit))
        return false;
    } else if(op.kind=="station") {
      if(!OpexRSStationShape(op)) return false;
    } else if(op.kind=="depot" || op.kind=="signal" || op.kind=="remove_signal") {
      if(!("front" in op) || typeof op.front!="integer"
          || !AIMap.IsValidTile(op.front)) return false;
      if(op.kind=="signal" && (!("type" in op) || typeof op.type!="integer"
          || op.type==AIRail.SIGNALTYPE_NONE))
        return false;
      if(op.kind=="remove_signal"
          && (!("before" in op) || typeof op.before!="integer"
              || op.before==AIRail.SIGNALTYPE_NONE)) return false;
    } else return false;
  }
  foreach(loop in plan.loops) {
    if(typeof loop!="table" || !("first" in loop) || !("last" in loop)
        || !("path" in loop) || typeof loop.path!="array" || loop.path.len()<3
        || typeof loop.first!="integer" || typeof loop.last!="integer") return false;
    if(loop.first<0 || loop.last>=plan.route.len() || loop.first>=loop.last)
      return false;
    foreach(t in loop.path)
      if(typeof t!="integer" || !AIMap.IsValidTile(t)) return false;
    if(("depot" in loop) && loop.depot!=null
        && (typeof loop.depot!="table" || !("tile" in loop.depot)
            || !("front" in loop.depot) || !("track" in loop.depot))) return false;
    if(("depot" in loop) && loop.depot!=null
        && (typeof loop.depot.tile!="integer"
            || typeof loop.depot.front!="integer"
            || !AIMap.IsValidTile(loop.depot.tile)
            || !AIMap.IsValidTile(loop.depot.front))) return false;
  }
  foreach(sig in plan.signals)
    if(typeof sig!="table" || !("tile" in sig) || !("front" in sig)
        || !("type" in sig) || typeof sig.tile!="integer"
        || typeof sig.type!="integer" || sig.type==AIRail.SIGNALTYPE_NONE
        || typeof sig.front!="integer" || !AIMap.IsValidTile(sig.tile)
        || !AIMap.IsValidTile(sig.front)) return false;
  return true;
}

/* Never dereference an incomplete saved journal. Keep a durable, non-runnable
 * HOLD witness and block future selection rather than guessing a v1/v2 plan. */
function OpexRSInvalidHold(id, reason)
{
  RS_LEGACY_HOLD=true;
  AILog.Warning("RS_BUILD event=HOLD reason="+reason+" id="+id);
  return {version=0,lineId=typeof id=="integer"?id:-1,phase="HOLD",
    reason=reason,a=-1,b=-1,cursor=0,spent=0,pending=null};
}

function OpexRSLog(j, event, extra = "")
{
  OpexDiagLog("RS_BUILD event="+event+" line="+j.lineId+" phase="+j.phase
      +" a="+j.a+" b="+j.b+" cursor="+j.cursor+" spent="+j.spent+" "+extra);
}

function OpexRSHold(j, reason)
{
  j.phase="HOLD"; j.reason=reason; OpexRSLog(j,"HOLD",reason);
}

/* Only our journalled insertion may be ignored in the commercial order
 * signature. Verify its exact position, destination and stop-in-depot flag;
 * another changed commercial order must still fail closed. */
function OpexRSParkTemporaryOrders(j, position)
{
  if(j.phase!="PARK" || position<0 || !AIVehicle.IsValidVehicle(j.a)
      || !AIOrder.IsValidVehicleOrder(j.a,position)
      || !AIOrder.IsGotoDepotOrder(j.a,position)
      || AIOrder.GetOrderDestination(j.a,position)!=j.depot
      || (AIOrder.GetOrderFlags(j.a,position)&AIOrder.OF_STOP_IN_DEPOT)==0)
    return false;
  return OpexRSOrders(j.a,position)==j.orders;
}

function OpexRSParkOrdersValid(j)
{
  if(OpexRSOrders(j.a)==j.orders) return true;
  if(j.phase!="PARK") return false;
  if(("parkPosition" in j) && OpexRSParkTemporaryOrders(j,j.parkPosition))
    return true;
  return j.pending!=null && ("kind" in j.pending) && j.pending.kind=="park"
      && ("position" in j.pending)
      && OpexRSParkTemporaryOrders(j,j.pending.position);
}

/* Exact depot parking, no track mutation while a vehicle is in motion.
 * SendVehicleToDepot can refuse, and toggles an existing depot diversion.
 * InsertOrder + SkipToOrder instead targets the known line depot explicitly.
 * Its commercial orders are restored before BUILD/CloneVehicle. */
function OpexRSParkStep(j)
{
  local v=j.a; local day=AIDate.GetCurrentDate();
  if(!AIRail.IsRailDepotTile(j.depot)
      || !AICompany.IsMine(AITile.GetOwner(j.depot))
      || AIRail.GetRailType(j.depot)!=j.railType) {
    OpexRSHold(j,"PARK_DEPOT_CHANGED");return;
  }
  if(AIVehicle.IsStoppedInDepot(v)) {
    if(AIVehicle.GetLocation(v)!=j.depot) {
      OpexRSHold(j,"PARK_WRONG_DEPOT");return;
    }
    if(j.parkPosition>=0) {
      if(!OpexRSParkTemporaryOrders(j,j.parkPosition)) {
        OpexRSHold(j,"PARK_TEMP_ORDER_CHANGED");return;
      }
      j.pending={kind="park",vehicle=v,action="remove",position=j.parkPosition};
      if(!AIOrder.RemoveOrder(v,j.parkPosition)) {
        OpexRSHold(j,"PARK_REMOVE_FAILED_"+AIError.GetLastErrorString());return;
      }
      j.parkPosition=-1;j.pending=null;
    }
    if(OpexRSOrders(v)!=j.orders) {OpexRSHold(j,"PARK_RESTORE_ORDERS");return;}
    j.phase="BUILD";OpexRSLog(j,"PARKED","depot="+j.depot);
    return;
  }
  if(day>j.deadline) {OpexRSHold(j,"PARK_TIMEOUT");return;}
  if(j.parkPosition>=0) {
    if(!OpexRSParkTemporaryOrders(j,j.parkPosition)) {
      OpexRSHold(j,"PARK_TEMP_ORDER_CHANGED");return;
    }
    /* A valid active temporary stop order is left alone until arrival. */
    if(AIOrder.ResolveOrderPosition(v,AIOrder.ORDER_CURRENT)==j.parkPosition)
      return;
    if(day<j.parkNextDate) return;
    j.pending={kind="park",vehicle=v,action="skip",position=j.parkPosition};
    local routed=AIOrder.SkipToOrder(v,j.parkPosition);
    j.pending=null;j.parkNextDate=day+30;j.parkAttempts++;
    if(!routed) OpexRSLog(j,"PARK_SKIP_REFUSED",AIError.GetLastErrorString());
    if(j.parkAttempts>=3 && !routed) OpexRSHold(j,"PARK_SKIP_EXHAUSTED");
    return;
  }
  if(j.parkRequested) {
    /* Do not toggle a depot diversion already accepted by the engine. */
    if(AIOrder.IsGotoDepotOrder(v,AIOrder.ORDER_CURRENT)) return;
    if(day<j.parkNextDate) return;
    j.parkRequested=false;
  }
  if(day<j.parkNextDate) return;
  if(j.parkAttempts>=3) {OpexRSHold(j,"PARK_DISPATCH_EXHAUSTED");return;}
  if(OpexRSOrders(v)!=j.orders) {OpexRSHold(j,"PARK_ORDERS_CHANGED");return;}
  j.parkAttempts++;
  if(j.parkAttempts==1) {
    j.pending={kind="park",vehicle=v,action="direct"};
    local direct=AIVehicle.SendVehicleToDepot(v);
    if(direct) {
      j.parkRequested=true;j.parkNextDate=day+60;j.pending=null;
      OpexRSLog(j,"PARK_SENT","method=automatic");return;
    }
    local error=AIError.GetLastErrorString();
    j.pending=null;
    OpexRSLog(j,"PARK_REFUSED","method=automatic error="+error);
    /* A failed command must not cancel an already-active depot order. */
    if(AIOrder.IsGotoDepotOrder(v,AIOrder.ORDER_CURRENT)) {
      j.parkRequested=true;j.parkNextDate=day+60;return;
    }
  }
  local position=AIOrder.ResolveOrderPosition(v,AIOrder.ORDER_CURRENT);
  if(position==AIOrder.ORDER_INVALID || position<0
      || !AIOrder.IsValidVehicleOrder(v,position)) {
    j.parkNextDate=day+30;OpexRSLog(j,"PARK_RETRY","no_current_order");return;
  }
  j.pending={kind="park",vehicle=v,action="insert",position=position};
  if(!AIOrder.InsertOrder(v,position,j.depot,AIOrder.OF_STOP_IN_DEPOT)) {
    local error=AIError.GetLastErrorString();
    j.pending=null;j.parkNextDate=day+30;
    OpexRSLog(j,"PARK_RETRY","insert="+error);return;
  }
  j.parkPosition=position;
  if(!OpexRSParkTemporaryOrders(j,position)) {
    OpexRSHold(j,"PARK_INSERT_IDENTITY");return;
  }
  j.pending={kind="park",vehicle=v,action="skip",position=position};
  local routed=AIOrder.SkipToOrder(v,position);
  j.pending=null;j.parkNextDate=day+30;
  if(routed) OpexRSLog(j,"PARK_SENT","method=temporary depot="+j.depot);
  else OpexRSLog(j,"PARK_SKIP_REFUSED",AIError.GetLastErrorString());
}

function OpexRSIdle(owner)
{
  return owner._railExpansion == null
      && owner._railSearch == null
      && owner._v257Pending == null
      && (owner._v284State == null || owner._v284State.pending == null);
}

/* Economic admission for an EXISTING freight service. This is deliberately
 * independent of the old read-only P0 shadow study. The live station stock
 * is authoritative; the annual observation can bridge a loading-day dip,
 * but only when recent AND some stock is still waiting today. */
function OpexRSEconomicSignal(line)
{
  local v=line.vehicles[0];
  /* lastProfit only exists after a full yearly report: a line opened in
   * 1970 was vetoed for all of 1971 (5x5 pilot: 312 NO_PROFIT rejections).
   * From April on, an annualized positive profit of the current year is an
   * equally observed signal; a negative or absent one still vetoes. */
  local profit=("lastProfit" in line)?line.lastProfit:0;
  if(profit<=0 && AIVehicle.IsValidVehicle(v)) {
    local month=AIDate.GetMonth(AIDate.GetCurrentDate());
    local current=AIVehicle.GetProfitThisYear(v);
    if(month>=4 && current>0) profit=current*12/month;
  }
  if (profit<=0)
    return {ok=false,reason="NO_PROFIT"};
  local capacity=AIVehicle.GetCapacity(v,line.cargo);
  local station=AIStation.GetStationID(line.stationA);
  if(capacity<=0 || !AIStation.IsValidStation(station))
    return {ok=false,reason="NO_CAPACITY_OR_STATION"};
  local waiting=AIStation.GetCargoWaiting(station,line.cargo);
  local backlog=waiting;
  local day=AIDate.GetCurrentDate();
  if(("lastWaitingADate" in line) && ("lastWaitingA" in line)
      && day>=line.lastWaitingADate && day-line.lastWaitingADate<=370
      && waiting>=max(1,(capacity/3).tointeger()))
    backlog=max(backlog,line.lastWaitingA);
  /* rail_sidings_trigger=1 : le stock en attente n'est plus un veto. Une seule rame en plein
   * chargement vide la gare a chaque passage ; la note de gare (delai depuis le dernier ramassage)
   * plafonne alors le flux, et c'est la marge (OpexRSExpandMargin) qui juge la seconde rame. */
  if(backlog<capacity && !RS_ECONOMIC_TRIGGER)
    return {ok=false,reason="NO_BACKLOG",waiting=waiting,capacity=capacity};
  return {ok=true,reason="READY",waiting=waiting,capacity=capacity,
    backlog=backlog,profit=profit};
}

/* Only veto SIDINGS for a wagon that V284 or the V233 input path could
 * actually select NOW. Read-only: do not initialize timers, consume a quota
 * or mutate the pending state while comparing alternatives. */
function OpexRSWagonAlternative(owner, line, economics)
{
  if(V284_RAIL_GROWTH<=0 && V233_LONG_GOOD<=0 && !RAIL_GROW) return false;
  if(!SAVE_FULL_STATE || owner._catalog==null || owner._lines==null
      || owner._v257Pending!=null || owner._railExpansion!=null
      || (owner._railSearch!=null && owner._railSearch.kind=="upgrade")) return false;
  local date=AIDate.GetCurrentDate(),state=owner._v284State;
  if(state!=null && (state.pending!=null
      || ((line.lineId in state.dates) && date<state.dates[line.lineId]))) return false;
  local normal=false;
  /* RAIL-GROW : porte de caisse propre (rail_fill retire le 20/11). */
  if(RAIL_GROW) {
    normal=OpexAvailableCapital()>=RAIL_FILL_RESERVE+10000
        && !(("railGrowStop" in line) && date<line.railGrowStop)
        && (state==null || date>=state.nextDate);
  } else {
    normal=V284_RAIL_GROWTH>0
        && AIDate.GetYear(date)>=OPEX_START_YEAR+V284_RAIL_GROWTH
        && OpexAvailableCapital()>=1000000
        && (state==null || date>=state.nextDate);
  }
  local v233=V233_LONG_GOOD>0 && V233L_STATE!=null
      && V233L_STATE.pending==null && OpexV233LInputTarget(line);
  if(!normal && !v233) return false;
  local v=line.vehicles[0];
  if(!AIVehicle.IsValidVehicle(v) || AIVehicle.GetVehicleType(v)!=AIVehicle.VT_RAIL
      || AIVehicle.GetNumWagons(v)<2
      || AIEngine.GetCapacity(AIVehicle.GetEngineType(v))>0
      || OpexV163Wagons2(line)>0
      || (owner._vehiclesToRetire!=null && (v in owner._vehiclesToRetire))) return false;
  local length=OpexV284Limit(line),number=AIVehicle.GetNumWagons(v)-1;
  if(number>=OpexRailNominalMaxWagons(length)
      || AIVehicle.GetLength(v)+8>length*16) return false;
  local wagonId=AIVehicle.GetWagonEngineType(v,1);
  if(!AIEngine.IsWagon(wagonId) || !AIEngine.IsBuildable(wagonId)
      || AIEngine.GetCargoType(wagonId)!=line.cargo) return false;
  for(local k=1;k<=number;k++)
    if(AIVehicle.GetWagonEngineType(v,k)!=wagonId) return false;
  local wagon=OpexV257Engine(wagonId,line.cargo,true);
  if(wagon==null || wagon.capacity<=0 || economics.waiting<wagon.capacity) return false;
  if(normal && RAIL_GROW) {
    local cap=AIVehicle.GetCapacity(v,line.cargo);
    if(cap<=0 || !OpexRailGrowWants(line,v,wagon,number,economics.waiting,cap)) normal=false;
  }
  if(v233 && !OpexV233LBacklog(line,economics.waiting,wagon.capacity)) v233=false;
  if(!normal && !v233) return false;
  local kDec=(ESTIM_UNIFIE & 4)!=0 ? OpexC69ComputeKDec().K_dec : -1;
  local equipment=OpexV284Equipment(line,v,wagon,number+1,false,economics.waiting,kDec);
  if(equipment==null) return false;
  /* V233's non-mutating profitability/capital test is required when V284
   * itself is unavailable. InputMargin mutates cooldowns: never call it. */
  if(!normal && (ESTIM_UNIFIE & 4)==0) {
    local loco=OpexV257Engine(equipment.engine,line.cargo,false);
    if(loco==null || OpexV233LFleetMargin(line,v,false,loco,number+1)==null) return false;
  }
  return true;
}

function OpexRSEligible(owner,line)
{
  if (OpexRSProtected(line) || line == null || !("mode" in line) || line.mode != "rail"
      || !("kind" in line) || line.kind != "freight" || !("vehicles" in line)
      || line.vehicles==null || line.vehicles.len()!=1 || line.trains!=1 || !("platformA" in line)
      || !("platformB" in line) || line.platformA==null || line.platformB==null
      || (("scrapping" in line) && line.scrapping)
      || (("doubleTrack" in line) && line.doubleTrack!=0)
      || (("railLoop" in line) && line.railLoop!=0)
      || ("railLoopV3Txn" in line) || ("railLoopV3Clone" in line)
      || ("railPair" in line) || ("doubleGrowDirectional" in line)
      || (("rsRetryDate" in line) && AIDate.GetCurrentDate()<line.rsRetryDate)
      || !AIRail.IsRailDepotTile(line.depot)) return false;
  local v=line.vehicles[0];
  if (OpexRSSignature(v)=="" || AIVehicle.GetAgeLeft(v)<730
      || (owner._vehiclesToRetire!=null && (v in owner._vehiclesToRetire))) return false;
  /* Existing station sharing would invalidate exclusive construction occupancy. */
  local a=AIStation.GetStationID(line.stationA); local b=AIStation.GetStationID(line.stationB);
  foreach (other in owner._lines) {
    if (other==line || !("mode" in other) || other.mode!="rail") continue;
    if (AIStation.GetStationID(other.stationA)==a || AIStation.GetStationID(other.stationB)==a
        || AIStation.GetStationID(other.stationA)==b || AIStation.GetStationID(other.stationB)==b) return false;
  }
  return true;
}

/* Les prototypes P1/P3 posaient des panneaux-verrous RS_P1_/RS_P3_ ; aucun code
 * n'en pose plus et les panneaux restent un canal de mesure, jamais une entree de
 * decision (test_signs_default_off). Point d'extension conserve, toujours vrai. */
function OpexRSNoLegacyLocks()
{
  return true;
}

/* A different line may reuse a physical section without sharing stations.
 * Changing its PBS signals while our first locomotive is parked would be
 * destructive. Reject the entire upgrade BEFORE laying the first rail. */
function OpexRSCorridorExclusive(owner,line,route)
{
  local used={},reach=null,reachDone=false;
  foreach(t in route) used.rawset(t,true);
  foreach(other in owner._lines) {
    if(other==line || !("mode" in other) || other.mode!="rail") continue;
    if(("depot" in other) && ("depot" in line) && other.depot==line.depot) return false;
    /* One corridor-side flood per decision, recomputed at every call: no
     * state survives a build, removal, ownership change or Save/Load. */
    if(!reachDone) {reach=OpexRSCorridorReach(used);reachDone=true;}
    /* A foreign-service train on the corridor, or on a branch really
     * connected to it, vetoes even when that service's nominal route traces
     * as disjoint (the trace fallback below cannot see a stranded train). */
    if(("vehicles" in other) && other.vehicles!=null)
      foreach(v in other.vehicles) {
        if(!AIVehicle.IsValidVehicle(v)) continue;
        local at=AIVehicle.GetLocation(v);
        if(at in used || (reach!=null && at in reach)) return false;
      }
    /* The reach proof subsumes the trace: a traced route starts on the
     * service's station tile and follows the same symmetric triples, so a
     * shared tile would put that station tile in `reach`. Tracing 45 services
     * cost 587 655 opcodes natively; trace only when the proof is unavailable
     * (unsupported layout, flood refused) or negative. */
    if(OpexRSNetworkDisjoint(other,used,reach)) continue;
    /* A primary-route fallback cannot certify a DOUBLE service's second
     * lane. Any unknown or connected secondary witness remains a veto. */
    if(("doubleTrack" in other) && other.doubleTrack!=0) return false;
    local otherRoute=OpexV284Trace(other);
    /* A branched line can share track in the MIDDLE even when its stations
     * and current vehicles are elsewhere. Untraceable != disjoint. */
    if(otherRoute==null) return false;
    foreach(t in otherRoute) if(t in used) return false;
  }
  return true;
}

/* Execute only the selected EXPAND offer. The v2 journal, park fallback,
 * commands and Save/Load ownership are unchanged. */
function OpexRSExecute(owner,line,offer)
{
  if(!RAIL_SIDINGS_SHADOW || RS_LEGACY_HOLD || !OpexRSIdle(owner) || !OpexRSEligible(owner,line)
      || !OpexRSSecondaryDestinationAccepts(line)
      || !OpexRSCorridorExclusive(owner,line,offer.plan.route)
      || !OpexRSBuildPreflight(offer.plan) || !OpexRailVehicleSlotAvailable()) return false;
  local v=line.vehicles[0],plan=offer.plan,price=offer.stock.tointeger(),reserve=offer.reserve;
  local orders=OpexRSOrders(v);
  if(orders=="") {OpexRSExpandLog(line,"SIDINGS","ORDERS_UNSUPPORTED");return false;}
  if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)<offer.cost+reserve) return false;
  local j={version=2,lineId=line.lineId,phase="PARK",reason="",a=v,b=-1,
    sigA=OpexRSSignature(v),sigB="",orders=orders,depot=line.depot,
    railType=AIRail.GetRailType(line.depot),plan=plan,cursor=0,pending=null,
    spent=0,costKnown=true,deadline=AIDate.GetCurrentDate()+365,
    parkPosition=-1,parkAttempts=0,parkNextDate=0,parkRequested=false,
    lastObserve=-1,positions={},deliveries={},visits={},lastMotion={},
    sourceStation=AIStation.GetStationID(line.stationA),sinkStation=AIStation.GetStationID(line.stationB),
    cargo=line.cargo,trainPrice=price,reserve=reserve,admission="UNKNOWN",loaded=false};
  RS_JOURNAL.rawset(line.lineId,j); line.railSidings <- line.lineId;
  owner._saveProjection=null;
  OpexRSLog(j,"SELECT","length="+offer.railTiles+" quote="+offer.cost+" loops="+plan.loops.len()
      +" margin="+offer.margin.tointeger()+" delta_monthly="+offer.delta.tointeger());
  OpexRSParkStep(j);
  return true;
}

function OpexRSOpDone(op)
{
  if(op.kind=="rail") return OpexRSPlain(op.tile) && AIRail.GetRailTracks(op.tile)==op.after;
  if(op.kind=="station") {
    if(!OpexRSStationShape(op)) return false;
    foreach(t in op.tiles)
      if(!AIRail.IsRailStationTile(t) || AIStation.GetStationID(t)!=op.station
          || AIRail.GetRailStationDirection(t)!=op.direction
          || AITile.GetOwner(t)!=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)) return false;
    return true;
  }
  if(op.kind=="depot") return AIRail.IsRailDepotTile(op.tile)
      && AIRail.GetRailDepotFrontTile(op.tile)==op.front
      && AITile.GetOwner(op.tile)==AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
  if(op.kind=="signal") return AIRail.GetSignalType(op.tile,op.front)==op.type;
  if(op.kind=="remove_signal") return AIRail.GetSignalType(op.tile,op.front)==AIRail.SIGNALTYPE_NONE;
  return false;
}

/* The exact BEFORE image is proof that an interrupted BuildRail* command
 * did not run. Any third state is ambiguous and must HOLD without replay. */
function OpexRSOpBefore(op)
{
  if(op.kind=="rail") {
    local tracks=OpexRSPlain(op.tile)?AIRail.GetRailTracks(op.tile):0;
    return tracks==op.before && (tracks!=0 || OpexRSRailSite(op.tile));
  }
  if(op.kind=="station") {
    if(!OpexRSStationShape(op)) return false;
    foreach(t in op.tiles) if(!OpexRSStationSite(t)) return false;
    return true;
  }
  if(op.kind=="depot") return OpexRSDepotSite(op.tile);
  if(op.kind=="signal") return AIRail.GetSignalType(op.tile,op.front)==AIRail.SIGNALTYPE_NONE;
  if(op.kind=="remove_signal") return AIRail.GetSignalType(op.tile,op.front)==op.before;
  return false;
}

function OpexRSSameOp(a,b)
{
  if(typeof a!="table" || typeof b!="table" || !("kind" in a) || !("kind" in b)
      || !("tile" in a) || !("tile" in b) || a.kind!=b.kind || a.tile!=b.tile) return false;
  if(a.kind=="rail") return ("bit" in a) && ("bit" in b) && a.bit==b.bit
      && ("before" in a) && ("before" in b) && a.before==b.before
      && ("after" in a) && ("after" in b) && a.after==b.after;
  if(a.kind=="station") {
    if(!OpexRSStationShape(a) || !OpexRSStationShape(b)
        || a.station!=b.station || a.length!=b.length || a.direction!=b.direction) return false;
    for(local k=0;k<a.tiles.len();k++) if(a.tiles[k]!=b.tiles[k]) return false;
    return true;
  }
  return ("front" in a) && ("front" in b) && a.front==b.front
      && (a.kind!="signal" || (("type" in a) && ("type" in b) && a.type==b.type))
      && (a.kind!="remove_signal" || (("before" in a) && ("before" in b) && a.before==b.before));
}

/* Persist the pre-clone fleet set. On Load, a newly created vehicle may be
 * adopted only if it is the UNIQUE new owned primary rail train and has the
 * complete expected physical consist / orders, stopped in our depot. */
function OpexRSRailFleet()
{
  local result={};
  foreach(v,_ in AIVehicleList())
    if(AIVehicle.IsValidVehicle(v) && AIVehicle.IsPrimaryVehicle(v)
        && AIVehicle.GetVehicleType(v)==AIVehicle.VT_RAIL)
      result.rawset(v,true);
  return result;
}

function OpexRSCloneMatch(j,v)
{
  if(!AIVehicle.IsValidVehicle(v) || !AIVehicle.IsPrimaryVehicle(v)
      || AIVehicle.GetVehicleType(v)!=AIVehicle.VT_RAIL
      || !AIVehicle.IsStoppedInDepot(v) || AIVehicle.GetLocation(v)!=j.depot
      || OpexRSOrders(v)!=j.orders
      || AIVehicle.GetEngineType(v)!=AIVehicle.GetEngineType(j.a)
      || AIVehicle.GetGroupID(v)!=AIVehicle.GetGroupID(j.a)
      || AIVehicle.GetLength(v)!=AIVehicle.GetLength(j.a)
      || AIVehicle.GetNumWagons(v)!=AIVehicle.GetNumWagons(j.a)) return false;
  for(local k=0;k<AIVehicle.GetNumWagons(v);k++)
    if(AIVehicle.GetWagonEngineType(v,k)!=AIVehicle.GetWagonEngineType(j.a,k)) return false;
  return true;
}

function OpexRSAdoptClone(owner,line,j,v)
{
  if(line.vehicles.len()!=1 || line.vehicles[0]!=j.a) return false;
  foreach(other in owner._lines) if(other!=line && ("vehicles" in other))
    foreach(owned in other.vehicles) if(owned==v) return false;
  j.b=v; j.sigB=OpexRSSignature(v);
  line.vehicles.append(v); line.trains=line.vehicles.len(); line.vehCount<-line.trains;
  owner._saveProjection=null; j.pending=null; j.phase="START_A";
  OpexRSLog(j,"CLONE_RECOVERED","vehicle="+v);
  return true;
}

/* A r30 natural plan passed SOURCE and LOOP, then failed this last gate with
 * only 'PREFLIGHT'. Emit the FIRST exact rejecting guard; never accept a plan
 * because the engine test fails or because an overlay predicts future rails. */
function OpexRSPreflightReject(reason, op = null)
{
  local detail=op==null?"":" kind="+op.kind+" tile="+op.tile;
  OpexDiagLog("RS_PREFLIGHT reason="+reason+detail);
  return false;
}

function OpexRSBuildPreflight(plan)
{
  if(!OpexRSPlanSafe(plan)) return OpexRSPreflightReject("PLAN_SHAPE");
  if(OpexRSExistingRouteIssue(plan.route)!="OK") return OpexRSPreflightReject("EXISTING_ROUTE");
  if(!OpexRSNo90(plan.source.path)) return OpexRSPreflightReject("SOURCE_NO90");
  local tracks={};local occupied={};
  foreach(op in plan.ops) {
    if(op.kind=="signal" || op.kind=="remove_signal") continue;
    if(op.kind=="rail") {
      if(op.tile in occupied) return OpexRSPreflightReject("RAIL_OVERLAPS_FOOTPRINT",op);
      local before=(op.tile in tracks)?tracks[op.tile]:
          (OpexRSPlain(op.tile)?AIRail.GetRailTracks(op.tile):0);
      if(before!=op.before) return OpexRSPreflightReject("RAIL_BEFORE_MASK",op);
      if(before==0 && !OpexRSRailSite(op.tile)) return OpexRSPreflightReject("RAIL_TERRAIN",op);
      local ok=false;
      { local test=AITestMode();ok=AIRail.BuildRailTrack(op.tile,op.bit); }
      if(!ok) return OpexRSPreflightReject("RAIL_ENGINE_TEST",op);
      tracks.rawset(op.tile,op.after);
    } else if(op.kind=="station") {
      if(!OpexRSOpBefore(op)) return OpexRSPreflightReject("STATION_FOOTPRINT",op);
      foreach(t in op.tiles) {
        if(t in occupied || t in tracks) return OpexRSPreflightReject("STATION_OVERLAPS_RAIL",op);
        occupied.rawset(t,true);
      }
      local ok=false;
      { local test=AITestMode();
        ok=AIRail.BuildRailStation(op.tile,op.direction,1,op.length,op.station); }
      if(!ok) return OpexRSPreflightReject("STATION_ENGINE_TEST",op);
    } else if(op.kind=="depot") {
      if(op.tile in occupied || op.tile in tracks || !OpexRSDepotSite(op.tile))
        return OpexRSPreflightReject("DEPOT_FOOTPRINT",op);
      local ok=false;
      { local test=AITestMode();ok=AIRail.BuildRailDepot(op.tile,op.front); }
      if(!ok) return OpexRSPreflightReject("DEPOT_ENGINE_TEST",op);
      occupied.rawset(op.tile,true);
    }
  }
  foreach(sig in plan.signals) {
    if(sig.tile in occupied) return OpexRSPreflightReject("SIGNAL_OVERLAPS_FOOTPRINT",sig);
    local mask=(sig.tile in tracks)?tracks[sig.tile]:
        (OpexRSPlain(sig.tile)?AIRail.GetRailTracks(sig.tile):0);
    if(mask==0 || (mask & (mask-1))!=0
        || AIMap.DistanceManhattan(sig.tile,sig.front)!=1)
      return OpexRSPreflightReject("SIGNAL_MASK_OR_FRONT",sig);
    /* Future single-track signals are tested by BuildStep once their rails
     * really exist. Existing tracks can already be checked by the engine. */
    if(!(sig.tile in tracks)) {
      local ok=false;
      { local test=AITestMode();ok=AIRail.BuildSignal(sig.tile,sig.front,sig.type); }
      if(!ok && AIRail.GetSignalType(sig.tile,sig.front)!=sig.type)
        return OpexRSPreflightReject("SIGNAL_ENGINE_TEST",sig);
    }
  }
  return true;
}

function OpexRSBuildStep(j)
{
  if(j.cursor>=j.plan.ops.len()) { j.phase="VERIFY"; return; }
  local opMark=OpexOpsMeasureBegin();
  /* PARK can take months. Recheck the entire additive footprint before the
   * first mutation, including rail/depot sites which depend on earlier ops.
   * AITestMode does not install those earlier ops: use an explicit track
   * overlay for their BEFORE masks, never pretend the test changed the map. */
  if(j.cursor==0 && !OpexRSBuildPreflight(j.plan)) {
    OpexRSHold(j,"NETWORK_PREFLIGHT_CHANGED");return;
  }
  local op=j.plan.ops[j.cursor];
  if(op.kind=="station" && !OpexRSOpBefore(op)) {
    OpexRSHold(j,"STATION_FOOTPRINT_CHANGED");return;
  }
  if(OpexRSOpDone(op)) { OpexRSHold(j,"UNOWNED_PREEXISTING_COMMAND_RESULT"); return; }
  if(op.kind=="remove_signal" && AIRail.GetSignalType(op.tile,op.front)!=op.before) {
    OpexRSHold(j,"SIGNAL_CHANGED");return;
  }
  if(op.kind=="signal" && AIRail.GetSignalType(op.tile,op.front)!=AIRail.SIGNALTYPE_NONE) {
    OpexRSHold(j,"SIGNAL_OCCUPIED");return;
  }
  if(op.kind=="rail") {
    local current=OpexRSPlain(op.tile)?AIRail.GetRailTracks(op.tile):0;
    if(current!=op.before || (current==0 && !OpexRSRailSite(op.tile))) {
      OpexRSHold(j,"TERRAIN_CHANGED"); return;
    }
  }
  if(op.kind=="depot" && !OpexRSDepotSite(op.tile)) {
    OpexRSHold(j,"DEPOT_SITE_CHANGED");return;
  }
  if(AICompany.GetBankBalance(AICompany.COMPANY_SELF)<j.trainPrice+j.reserve+max(0,op.quote)) {
    /* RS-CASH-WAIT : une penurie de caisse est transitoire. Un HOLD laissait la
     * seule rame arretee au depot pour toute la partie (3 HOLD sur 10 chantiers,
     * porte B master). Attendre la caisse, borne a 180 jours, puis HOLD. */
    if(OpexRSCashWait(j)) return;
    OpexRSHold(j,"CASH_BEFORE_"+op.kind);return;
  }
  local testOK=false;
  { local test=AITestMode();
    if(op.kind=="rail") testOK=AIRail.BuildRailTrack(op.tile,op.bit);
    else if(op.kind=="station") testOK=AIRail.BuildRailStation(op.tile,op.direction,1,op.length,op.station);
    else if(op.kind=="depot") testOK=AIRail.BuildRailDepot(op.tile,op.front);
    else if(op.kind=="signal") testOK=AIRail.BuildSignal(op.tile,op.front,op.type);
    else if(op.kind=="remove_signal") testOK=AIRail.RemoveSignal(op.tile,op.front);
  }
  if(!testOK) {OpexRSHold(j,"PREFLIGHT_"+op.kind+"_"+AIError.GetLastErrorString());return;}
  /* Intent is in the Save graph before a command can suspend the VM. */
  j.pending=op;
  OpexRSLog(j,"ATTEMPT","kind="+op.kind+" tile="+op.tile+" before="
      +(op.kind=="rail"?op.before:0)+" bit="+(op.kind=="rail"?op.bit:0)
      +" expected_after="+(op.kind=="rail"?op.after:0)
      +" front="+(("front" in op)?op.front:-1)
      +" quote="+op.quote+" journal="+j.cursor);
  local account=AIAccounting(); local ok=false;
  if(op.kind=="rail") ok=AIRail.BuildRailTrack(op.tile,op.bit);
  else if(op.kind=="station") ok=AIRail.BuildRailStation(op.tile,op.direction,1,op.length,op.station);
  else if(op.kind=="depot") ok=AIRail.BuildRailDepot(op.tile,op.front);
  else if(op.kind=="signal") ok=AIRail.BuildSignal(op.tile,op.front,op.type);
  else if(op.kind=="remove_signal") ok=AIRail.RemoveSignal(op.tile,op.front);
  local nativeError=ok?"OK":AIError.GetLastErrorString();
  local paid=account.GetCosts();
  local done=OpexRSOpDone(op);
  local mask=OpexRSPlain(op.tile)?AIRail.GetRailTracks(op.tile):-1;
  j.spent+=paid;
  OpexRSLog(j,"OP_RESULT","kind="+op.kind+" tile="+op.tile
      +" journal="+j.cursor+" native="+ok+" error="+nativeError
      +" paid="+paid+" after_mask="+mask+" physical="+done
      +" opcodes="+OpexOpsMeasureEnd(opMark));
  if(!ok || !done) { OpexRSHold(j,"BUILD_"+op.kind+"_"+nativeError); return; }
  j.cursor++; j.pending=null;
  OpexRSLog(j,"BUILT","kind="+op.kind+" tile="+op.tile);
}

function OpexRSObserve(j)
{
  local day=AIDate.GetCurrentDate();
  if(j.lastObserve==day) return;
  j.lastObserve=day;
  foreach(v in [j.a,j.b]) {
    local tile=AIVehicle.GetLocation(v); local load=AIVehicle.GetCargoLoad(v,j.cargo);
    local station=AIRail.IsRailStationTile(tile)?AIStation.GetStationID(tile):-1;
    if(!(v in j.positions)) {
      j.positions.rawset(v,{tile=tile,load=load,station=station});
      j.lastMotion.rawset(v,day);
      if(!(v in j.deliveries)) j.deliveries.rawset(v,0);
      if(!(v in j.visits)) j.visits.rawset(v,0);
    }
    local prior=j.positions[v];
    if(tile!=prior.tile) j.lastMotion[v]=day;
    if(station==j.sinkStation && prior.load>load) {
      j.deliveries[v]+=prior.load-load;
      OpexRSLog(j,"DELIVERY","vehicle="+v+" cargo="+(prior.load-load)+" total="+j.deliveries[v]);
    }
    if(station==j.sourceStation && prior.station!=station) j.visits[v]++;
    /* A full-loader waiting at source is not declared deadlocked. */
    if(day-j.lastMotion[v]>180 && station!=j.sourceStation) {
      OpexRSHold(j,"NO_MOTION_180D_vehicle="+v); return;
    }
    j.positions[v]={tile=tile,load=load,station=station};
    if(DECISION_LOG) OpexRSLog(j,"POSITION","day="+day+" vehicle="+v+" tile="+tile+" load="+load
        +" speed="+AIVehicle.GetCurrentSpeed(v));
  }
}

/* Service existing SIDINGS trains without changing their commercial orders.
 * OpenTTD may fail to find an automatic servicing route despite the default
 * 150-day interval. SendVehicleToDepotForServicing adds only a transient
 * engine-owned depot diversion; it is a toggle, so never issue it twice while
 * an earlier diversion is active. The journal records the intent before the
 * engine command, and an interrupted command deliberately remains HOLD.
 * Limit to empty trains to avoid losing a full coal load en route. */
function OpexRSService(j)
{
  if(j.phase!="RUN" || j.pending!=null) return;
  /* A scheduled depot service order belongs to the complete shared order
   * list; OpenTTD will execute it when needed. Never dispatch a competing
   * transient depot order from the sidings observer. */
  if(("serviceOrder" in j) && j.serviceOrder) return;
  if(!("nextService" in j)) j.rawset("nextService",{});
  local day=AIDate.GetCurrentDate();
  foreach(v in [j.a,j.b]) {
    if(!AIVehicle.IsValidVehicle(v) || !AIVehicle.IsPrimaryVehicle(v)
        || AIVehicle.GetVehicleType(v)!=AIVehicle.VT_RAIL
        || AIVehicle.IsInDepot(v)
        || AIVehicle.GetCargoLoad(v,j.cargo)>0
        || (v in j.nextService && day<j.nextService[v])) continue;
    local reliability=AIVehicle.GetReliability(v);
    if(reliability<0 || reliability>=55) {
      j.nextService.rawset(v,day+45);
      continue;
    }
    if(AIOrder.IsGotoDepotOrder(v,AIOrder.ORDER_CURRENT)) {
      j.nextService.rawset(v,day+45);
      continue;
    }
    j.pending={kind="service",vehicle=v,day=day};
    OpexRSLog(j,"SERVICE_ATTEMPT","vehicle="+v+" reliability="+reliability);
    local sent=AIVehicle.SendVehicleToDepotForServicing(v);
    if(!sent) OpexRSLog(j,"SERVICE_REFUSED","vehicle="+v
        +" error="+AIError.GetLastErrorString());
    else OpexRSLog(j,"SERVICE_SENT","vehicle="+v+" reliability="+reliability);
    j.nextService.rawset(v,day+(sent?150:45));
    j.pending=null;
    return; // at most one service command per AI iteration
  }
}

/* The service depot belongs to this railway and was proven reachable before
 * construction. First normalize both station orders to pass intermediate
 * stations without stopping; older saved trains (site123) have OF_NONE and
 * OpenTTD accumulates implicit station visits on every lap. Retain the
 * source's FULL_LOAD bits. Then install conditional depot service BEFORE
 * cloning, so both trains share the exact same three explicit orders.
 * A single persistent intent covers all order mutations: any interrupted or
 * partially applied mutation resolves to HOLD on Load, never an unsafe retry. */
RS_SERVICE_FLAGS <- AIOrder.OF_SERVICE_IF_NEEDED | AIOrder.OF_GOTO_NEAREST_DEPOT
    | AIOrder.OF_NON_STOP_INTERMEDIATE;

function OpexRSInstallServiceOrder(j)
{
  if(!("serviceOrder" in j)) j.rawset("serviceOrder",false);
  if(j.serviceOrder) return true;
  if(j.phase!="BUY" || j.b!=-1 || !AIVehicle.IsStoppedInDepot(j.a)
      || AIVehicle.GetLocation(j.a)!=j.depot
      || AIOrder.GetOrderCount(j.a)!=2 || OpexRSOrders(j.a)!=j.orders
      || !AIRail.IsRailDepotTile(j.depot)
      || !AIOrder.AreOrderFlagsValid(j.depot,RS_SERVICE_FLAGS)) {
    OpexRSHold(j,"SERVICE_ORDER_PREFLIGHT");
    return false;
  }
  j.pending={kind="service_order",before=j.orders,depot=j.depot};
  OpexRSLog(j,"ATTEMPT","kind=service_order depot="+j.depot);
  /* Native 150301 SAV: after SIDINGS works the reused original depot was
   * unreachable; both trains kept a fixed-depot service order as current
   * order for years with PathfinderLost set, wandering and stopping at
   * every station crossed (reliability 0 %, 91 breakdowns). Normalize the
   * two station orders to non-stop-intermediate (keeping load flags) and
   * service at the NEAREST reachable depot: OpenTTD skips that order when
   * no depot is reachable instead of losing the train. */
  for(local i=0;i<2;i++) {
    local flags=AIOrder.GetOrderFlags(j.a,i);
    if((flags&AIOrder.OF_NON_STOP_INTERMEDIATE)==0
        && !AIOrder.SetOrderFlags(j.a,i,flags|AIOrder.OF_NON_STOP_INTERMEDIATE)) {
      OpexRSHold(j,"SERVICE_ORDER_NONSTOP_"+AIError.GetLastErrorString());
      return false;
    }
  }
  if(!AIOrder.AppendOrder(j.a,j.depot,RS_SERVICE_FLAGS)) {
    OpexRSHold(j,"SERVICE_ORDER_APPEND_"+AIError.GetLastErrorString());
    return false;
  }
  local updated=OpexRSOrders(j.a);
  if(updated=="" || AIOrder.GetOrderCount(j.a)!=3
      || !AIOrder.IsGotoDepotOrder(j.a,2)
      || (AIOrder.GetOrderFlags(j.a,2)&AIOrder.OF_SERVICE_IF_NEEDED)==0
      || (AIOrder.GetOrderFlags(j.a,2)&AIOrder.OF_GOTO_NEAREST_DEPOT)==0) {
    OpexRSHold(j,"SERVICE_ORDER_UNVERIFIED");
    return false;
  }
  j.orders=updated;j.serviceOrder=true;j.pending=null;
  OpexRSLog(j,"SERVICE_ORDER_INSTALLED","depot="+j.depot+" count=3");
  return false; // separate the order command and the subsequent clone
}

/* Read-only per-AI-iteration telemetry for the crossing audit. The engine,
 * not this observer, owns PBS reservations and actual wagon positions.
 * A tail-clearance inference needs a length margin AND continued progress;
 * this log alone never certifies a PBS reservation or a wagon's own tile. */
function OpexRSHeadIndex(plan,tile)
{
  for(local i=0;i<plan.route.len();i++)
    if(plan.route[i]==tile) return {index=i,branch="M"};
  foreach(loop in plan.loops)
    for(local i=2;i<loop.path.len()-2;i++)
      if(loop.path[i]==tile) return {index=loop.first+i-2,branch="S"};
  return {index=-1,branch="?"};
}

/* R57 TEST ONLY: remote sink and spatial bound, no tail/PBS GO. */
function OpexRSR57RemoteTailBound(j)
{
  if(!RAIL_SIDINGS_SHADOW || !OpexRSJournalV2(j)
      || (j.phase!="WAIT_A_TAIL_CLEAR" && j.phase!="START_B")
      || j.pending!=null || j.a<0 || j.b<0
      || !AIVehicle.IsValidVehicle(j.a) || !AIVehicle.IsValidVehicle(j.b)
      || !AIVehicle.IsStoppedInDepot(j.b)
      || AIVehicle.GetLocation(j.b)!=j.depot
      || AIVehicle.IsStoppedInDepot(j.a)
      || AIVehicle.GetState(j.a)!=AIVehicle.VS_RUNNING
      || !AIStation.IsValidStation(j.sourceStation)
      || !AIStation.IsValidStation(j.sinkStation)
      || j.sourceStation==j.sinkStation) return false;
  local len=AIVehicle.GetLength(j.a);
  if(len<=0 || len!=AIVehicle.GetLength(j.b)
      || len>j.plan.length16) return false;
  local at=AIVehicle.GetLocation(j.a);
  if(!AIMap.IsValidTile(at) || !AIRail.IsRailStationTile(at)
      || AIStation.GetStationID(at)!=j.sinkStation
      || !AICompany.IsMine(AITile.GetOwner(at))) return false;
  /* Run the expensive signature/order check only for a plausible remote
   * sink witness; OpexRSTick has already checked them for every iteration. */
  if(OpexRSSignature(j.a)!=j.sigA || OpexRSSignature(j.b)!=j.sigB
      || OpexRSOrders(j.a)!=j.orders || OpexRSOrders(j.b)!=j.orders)
    return false;
  if(!("originalBerth" in j.plan.source)
      || typeof j.plan.source.originalBerth!="array"
      || j.plan.source.originalBerth.len()==0
      || !("joinIndex" in j.plan.source)
      || typeof j.plan.source.joinIndex!="integer"
      || j.plan.source.joinIndex<0
      || j.plan.source.joinIndex>=j.plan.route.len()) return false;
  local margin=2*((len+15)/16)+4;
  local index=OpexRSHeadIndex(j.plan,at);
  if(index.index>=0 && index.index<=j.plan.source.joinIndex+margin)
    return false;
  if(!AIMap.IsValidTile(j.depot)
      || AIMap.DistanceManhattan(at,j.depot)<=margin) return false;
  foreach(t in j.plan.source.originalBerth) {
    if(!AIMap.IsValidTile(t) || !AIRail.IsRailStationTile(t)
        || AIStation.GetStationID(t)!=j.sourceStation
        || AIMap.DistanceManhattan(at,t)<=margin) return false;
  }
  foreach(t in j.plan.source.berth) {
    if(!AIMap.IsValidTile(t) || !AIRail.IsRailStationTile(t)
        || AIStation.GetStationID(t)!=j.sourceStation
        || AIMap.DistanceManhattan(at,t)<=margin) return false;
  }
  foreach(t in j.plan.source.path)
    if(!AIMap.IsValidTile(t) || AIMap.DistanceManhattan(at,t)<=margin)
      return false;
  foreach(loop in j.plan.loops) {
    if(!("path" in loop) || typeof loop.path!="array"
        || loop.path.len()<3) return false;
    foreach(t in loop.path)
      if(!AIMap.IsValidTile(t) || AIMap.DistanceManhattan(at,t)<=margin)
        return false;
  }
  return true;
}

function OpexRSTrace(j)
{
  if(!RS_TRAFFIC_TRACE || j.plan.loops.len()==0 || j.b<0) return;
  local aTile=AIVehicle.GetLocation(j.a),bTile=AIVehicle.GetLocation(j.b);
  local a=OpexRSHeadIndex(j.plan,aTile),b=OpexRSHeadIndex(j.plan,bTile);
  local near=false;
  foreach(loop in j.plan.loops)
    if((a.index>=loop.first-14 && a.index<=loop.last+14)
        || (b.index>=loop.first-14 && b.index<=loop.last+14)) near=true;
  if(!near) return;
  OpexDiagLog("RS_TRAFFIC loop="+j.lineId+" tick="+RS_TRAFFIC_TICK
      +" day="+AIDate.GetCurrentDate()+" a="+j.a+" at="+aTile
      +" ai="+a.index+" ab="+a.branch+" av="+AIVehicle.GetCurrentSpeed(j.a)
      +" b="+j.b+" bt="+bTile+" bi="+b.index+" bb="+b.branch
      +" bv="+AIVehicle.GetCurrentSpeed(j.b)+" length16="+j.plan.length16);
}

function OpexRSRemainingQuote(j)
{
  local total=0;
  for(local i=j.cursor;i<j.plan.ops.len();i++)
    if(("quote" in j.plan.ops[i]) && j.plan.ops[i].quote>0) total+=j.plan.ops[i].quote;
  return total;
}

/* true = keep waiting for cash (logged at most monthly); false = deadline passed. */
function OpexRSCashWait(j)
{
  local day=AIDate.GetCurrentDate();
  if(!("cashWaitUntil" in j)) { j.cashWaitUntil <- day+180; j.cashWaitLog <- -1; }
  if(day>j.cashWaitUntil) return false;
  if(j.cashWaitLog<0 || day-j.cashWaitLog>=30) { j.cashWaitLog=day; OpexRSLog(j,"CASH_WAIT","until="+j.cashWaitUntil); }
  return true;
}

/* RS-UNBUILT-RELEASE : un HOLD avant toute mutation (cursor 0, aucune depense,
 * aucune rame clonee ni commande en vol) n'a rien a proteger. L'identite et les
 * ordres commerciaux de la rame d'origine sont reverifies ; l'arret temporaire au
 * depot est retire, la rame repart et la ligne redevient ordinaire, avec un an de
 * delai avant une nouvelle offre SIDINGS. Tout autre HOLD reste inchange. */
function OpexRSReleaseUnbuiltHolds(owner)
{
  local released=[];
  foreach(id,j in RS_JOURNAL) {
    if(j.phase!="HOLD" || !OpexRSJournalV2(j) || j.cursor!=0 || j.spent!=0 || j.b!=-1
        || j.pending!=null || !AIVehicle.IsValidVehicle(j.a) || OpexRSSignature(j.a)!=j.sigA) continue;
    local line=null; foreach(item in owner._lines) if(item.lineId==id) {line=item;break;}
    if(line==null) continue;
    local v=j.a;
    if(("parkPosition" in j) && j.parkPosition>=0) {
      local p=j.parkPosition;
      if(!AIOrder.IsValidVehicleOrder(v,p) || !AIOrder.IsGotoDepotOrder(v,p)
          || AIOrder.GetOrderDestination(v,p)!=j.depot || OpexRSOrders(v,p)!=j.orders) continue;
      if(!AIOrder.RemoveOrder(v,p)) continue;
      j.parkPosition=-1;
    }
    if(OpexRSOrders(v)!=j.orders) continue;
    if(AIVehicle.IsStoppedInDepot(v) && !AIVehicle.StartStopVehicle(v)) continue;
    released.append(id);
    if("railSidings" in line) line.rawdelete("railSidings");
    line.rsRetryDate <- AIDate.GetCurrentDate()+365;
    OpexRSLog(j,"RELEASED_UNBUILT","reason="+j.reason);
  }
  /* RS-BUILT-RESTART : reseau complet et physiquement verifie, mais aucune rame
   * clonee (HOLD a l'achat). La rame d'origine repart sur ses ordres commerciaux ;
   * la ligne reste sous journal HOLD (protegee), une seule fois. */
  foreach(id,j in RS_JOURNAL) {
    if(j.phase!="HOLD" || !OpexRSJournalV2(j) || j.cursor!=j.plan.ops.len() || j.b!=-1
        || j.pending!=null || ("restarted" in j) || !AIVehicle.IsValidVehicle(j.a)
        || OpexRSSignature(j.a)!=j.sigA || OpexRSOrders(j.a)!=j.orders
        || !AIVehicle.IsStoppedInDepot(j.a) || AIVehicle.GetLocation(j.a)!=j.depot) continue;
    local previousType=AIRail.GetCurrentRailType(); AIRail.SetCurrentRailType(j.railType);
    local physical=OpexRSPhysical(j.plan);
    AIRail.SetCurrentRailType(previousType);
    if(!physical) continue;
    j.restarted <- true;
    if(AIVehicle.StartStopVehicle(j.a)) OpexRSLog(j,"RESTARTED_BUILT","reason="+j.reason);
  }
  foreach(id in released) RS_JOURNAL.rawdelete(id);
  if(released.len()>0) owner._saveProjection=null;
}

function OpexRSTick(owner)
{
  RS_TRAFFIC_TICK++;
  if(RS_RELOADED) { OpexRSReconcile(owner); RS_RELOADED=false; }
  foreach(id,j in RS_JOURNAL) {
    if(j.phase=="HOLD") continue;
    if(!OpexRSJournalV2(j)) {OpexRSHold(j,"LEGACY_OR_INVALID_ORDER_JOURNAL");RS_LEGACY_HOLD=true;continue;}
    local line=null; foreach(item in owner._lines) if(item.lineId==id) {line=item;break;}
    if(line==null || OpexRSSignature(j.a)!=j.sigA
        || (OpexRSOrders(j.a)!=j.orders && !OpexRSParkOrdersValid(j))
        || (j.b>=0 && (OpexRSSignature(j.b)!=j.sigB || OpexRSOrders(j.b)!=j.orders))) {
      OpexRSHold(j,"IDENTITY_OR_ORDERS"); continue;
    }
    if(j.phase=="RUN" && j.pending!=null) {
      OpexRSHold(j,"RUN_UNRESOLVED_COMMAND");continue;
    }
    /* OFF is effective even for trains already in RUN: preserve both trains,
     * rails and orders, but stop SIDINGS control/observations immediately.
     * OpenTTD's PBS continues to govern their ordinary physical movement. */
    if(!RAIL_SIDINGS_SHADOW) { OpexRSHold(j,"OFF_DURING_WORK"); continue; }
    if(j.phase=="RUN") {
      /* Observe external track/signal/depot edits while in service. This
       * checks rail connectivity, not hidden engine reservations. */
      if(!("lastPhysical" in j)) j.lastPhysical <- -1;
      if(j.lastPhysical<0 || AIDate.GetCurrentDate()-j.lastPhysical>=30) {
        if(!OpexRSPhysical(j.plan)) {OpexRSHold(j,"RUN_NETWORK_CHANGED");continue;}
        j.lastPhysical=AIDate.GetCurrentDate();
      }
      OpexRSTrace(j);
      OpexRSObserve(j);
      if(j.phase=="RUN") OpexRSService(j);
      continue;
    }
    if(j.pending!=null) { OpexRSHold(j,"UNRESOLVED_COMMAND"); continue; }
    if(j.phase=="PARK") {
      OpexRSParkStep(j);
      continue;
    }
    if(j.phase=="WAIT_A_TAIL_CLEAR") {
      /* B must remain stopped inside OUR depot; unknown means HOLD. No new
       * mutator is allowed until the ORIGINAL reaches the remote sink. */
      if(!AIVehicle.IsStoppedInDepot(j.b) || AIVehicle.GetLocation(j.b)!=j.depot) {
        OpexRSHold(j,"R57_WAIT_B_NOT_PARKED");continue;
      }
      if(!OpexRSR57RemoteTailBound(j)) continue;
      if(!OpexRSPhysical(j.plan)) {
        OpexRSHold(j,"R57_WAIT_NETWORK");continue;
      }
      j.phase="START_B"; j.admission="R57_REMOTE_SINK_SPATIAL_ONLY";
      OpexRSLog(j,"R57_SINK_BOUNDED","source_tail_tick_certified=0");
    }
    if(!AIVehicle.IsStoppedInDepot(j.a) && j.phase!="START_B") { OpexRSHold(j,"ORIGINAL_NOT_PARKED");continue; }
    local previousType=AIRail.GetCurrentRailType(); AIRail.SetCurrentRailType(j.railType);
    if(j.phase=="BUILD") {
      if(j.cursor==0 && !OpexRSCorridorExclusive(owner,line,j.plan.route))
        OpexRSHold(j,"CORRIDOR_CHANGED_BEFORE_BUILD");
      else if(j.cursor==0 && AICompany.GetBankBalance(AICompany.COMPANY_SELF)
          <j.trainPrice+j.reserve+OpexRSRemainingQuote(j))
        OpexRSHold(j,"CASH_BEFORE_FIRST_MUTATION");
      else OpexRSBuildStep(j);
    }
    else if(j.phase=="VERIFY") {
      if(!OpexRSPhysical(j.plan)) OpexRSHold(j,"PHYSICAL_ROUTE_OR_PBS");
      else { j.phase="BUY"; OpexRSLog(j,"NETWORK_READY","single="+(j.plan.route.len()-j.plan.doubleTiles)); }
    } else if(j.phase=="BUY") {
      local physical=OpexRSPhysical(j.plan),slot=OpexRailVehicleSlotAvailable();
      local cash=AICompany.GetBankBalance(AICompany.COMPANY_SELF)>=j.trainPrice+j.reserve;
      /* Caisse ou creneau de flotte : transitoires, attente bornee. */
      if(physical && (!slot || !cash) && OpexRSCashWait(j)) {}
      else if(!physical || !slot || !cash)
        OpexRSHold(j,"BUY_ADMISSION_"+(!physical?"PHYSICAL":(!slot?"SLOT":"CASH")));
      else if(OpexRSInstallServiceOrder(j)) {
        j.pending={kind="buy",beforeVehicles=OpexRSRailFleet()};
        OpexRSLog(j,"ATTEMPT","kind=buy");
        local account=AIAccounting();
        local train=AIVehicle.CloneVehicle(j.depot,j.a,true);
        j.spent+=account.GetCosts();
        if(!AIVehicle.IsValidVehicle(train)) OpexRSHold(j,"CLONE_REFUSED");
        else {
          j.b=train; j.sigB=OpexRSSignature(train); j.pending=null;
          if(AIVehicle.GetLength(train)>j.plan.length16 || OpexRSOrders(train)!=j.orders) OpexRSHold(j,"CLONE_MISMATCH");
          else { line.vehicles.append(train); line.trains=line.vehicles.len();line.vehCount<-line.trains;
            owner._saveProjection=null; j.phase="START_A"; }
        }
      }
    } else if(j.phase=="START_B" && !OpexRSR57RemoteTailBound(j)) {
      /* Never rely on a prior tick or a saved admission string. */
      j.phase="WAIT_A_TAIL_CLEAR"; j.admission="UNKNOWN";
    } else if(j.phase=="START_A" || j.phase=="START_B") {
      local v=j.phase=="START_A"?j.a:j.b;
      if(!OpexRSPhysical(j.plan) || !AIVehicle.IsStoppedInDepot(v)) OpexRSHold(j,"DEPARTURE_ADMISSION");
      else {
        j.admission=v==j.a?"R57_WAIT_REMOTE_SINK":"R57_REMOTE_SINK_SPATIAL_ONLY";
        j.pending={kind="start",vehicle=v};
        if(!AIVehicle.StartStopVehicle(v)) OpexRSHold(j,"START_REFUSED");
        else { j.pending=null;j.phase=v==j.a?"WAIT_A_TAIL_CLEAR":"RUN";OpexRSLog(j,"STARTED","vehicle="+v); }
      }
    }
    AIRail.SetCurrentRailType(previousType);
  }
  OpexRSReleaseUnbuiltHolds(owner);
}

/* Save/Load never restore an observation as a reservation. Physical PBS
 * remains engine-owned, including full-consist clearance during Load. */
function OpexRSLoad(data)
{
  RS_JOURNAL={}; RS_RELOADED=false;
  if(data!=null && typeof data!="table") {
    RS_JOURNAL.rawset(-1,OpexRSInvalidHold(-1,"LOAD_ROOT_INVALID"));
    RS_RELOADED=true;return;
  }
  RS_LEGACY_HOLD=data!=null && typeof data=="table"
      && (("railSidingsP2" in data) || ("railSidingsP4R70" in data));
  if(RS_LEGACY_HOLD)
    RS_JOURNAL.rawset(-1,OpexRSInvalidHold(-1,"LOAD_OLD_JOURNAL"));
  if(data==null || typeof data!="table" || !("railSidingsRuntime" in data)) return;
  local saved=data.railSidingsRuntime;
  if(typeof saved!="table") {
    RS_JOURNAL.rawset(-1,OpexRSInvalidHold(-1,"LOAD_RUNTIME_INVALID"));
    RS_RELOADED=true;return;
  }
  foreach(id,j in saved) {
    if(!OpexRSJournalV2(j) || j.lineId!=id || !OpexRSPlanSafe(j.plan))
      RS_JOURNAL.rawset(id,OpexRSInvalidHold(id,"LOAD_JOURNAL_INVALID_OR_LEGACY"));
    else RS_JOURNAL.rawset(id,j);
  }
  RS_RELOADED=true;
}

/* Incomplete commands never get blindly repeated. Every resolution either
 * consumes a verified physical AFTER image, establishes the exact BEFORE
 * image and retries via normal preflight, or leaves a durable HOLD. */
function OpexRSReconcilePending(owner,line,j)
{
  local intent=j.pending;
  if(intent==null) return true;
  if(!("kind" in intent) || typeof intent.kind!="string") return false;
  if(j.phase=="BUILD" && j.cursor<j.plan.ops.len()) {
    local op=j.plan.ops[j.cursor];
    if(!OpexRSSameOp(intent,op)) return false;
    if(OpexRSOpDone(op)) {
      j.cursor++;j.pending=null;j.costKnown=false;
      OpexRSLog(j,"RECOVER_AFTER","kind="+op.kind+" tile="+op.tile);
      return true;
    }
    if(OpexRSOpBefore(op)) {
      j.pending=null;
      OpexRSLog(j,"RECOVER_BEFORE","kind="+op.kind+" tile="+op.tile);
      return true;
    }
    return false;
  }
  if(j.phase=="PARK" && intent.kind=="park" && ("vehicle" in intent)
      && intent.vehicle==j.a && ("action" in intent)) {
    if(intent.action=="direct") {
      /* A depot order already active proves that SendVehicleToDepot ran.
       * Otherwise its uncertain outcome must not be toggled by a retry. */
      if(!AIOrder.IsGotoDepotOrder(j.a,AIOrder.ORDER_CURRENT)
          && !AIVehicle.IsStoppedInDepot(j.a)) return false;
      j.parkRequested=true;j.parkNextDate=AIDate.GetCurrentDate()+60;
    } else if((intent.action=="insert" || intent.action=="skip")
        && ("position" in intent) && typeof intent.position=="integer") {
      if(OpexRSParkTemporaryOrders(j,intent.position)) {
        j.parkPosition=intent.position;
        j.parkNextDate=AIDate.GetCurrentDate()+30;
      } else if(intent.action!="insert" || OpexRSOrders(j.a)!=j.orders) return false;
    } else if(intent.action=="remove" && ("position" in intent)
        && typeof intent.position=="integer") {
      if(OpexRSOrders(j.a)==j.orders && AIVehicle.IsStoppedInDepot(j.a)
          && AIVehicle.GetLocation(j.a)==j.depot) j.parkPosition=-1;
      else if(!OpexRSParkTemporaryOrders(j,intent.position)) return false;
    } else return false;
    j.pending=null;OpexRSLog(j,"RECOVER_PARK","action="+intent.action);
    return true;
  }
  if(j.phase=="BUY" && intent.kind=="buy" && ("beforeVehicles" in intent)
      && typeof intent.beforeVehicles=="table" && j.b==-1) {
    local before=intent.beforeVehicles;
    if(!(j.a in before) || line.vehicles.len()!=1 || line.vehicles[0]!=j.a
        || !OpexRSPhysical(j.plan)) return false;
    local newTrain=-1;
    foreach(v,_ in OpexRSRailFleet()) {
      if(v in before) continue;
      if(newTrain!=-1 || !OpexRSCloneMatch(j,v)) return false;
      newTrain=v;
    }
    if(newTrain>=0) return OpexRSAdoptClone(owner,line,j,newTrain);
    j.pending=null;OpexRSLog(j,"RECOVER_BEFORE","kind=buy");
    return true;
  }
  if((j.phase=="START_A" || j.phase=="START_B")
      && intent.kind=="start" && ("vehicle" in intent)) {
    local v=j.phase=="START_A"?j.a:j.b;
    if(intent.vehicle!=v || !OpexRSPhysical(j.plan)) return false;
    if(AIVehicle.IsStoppedInDepot(v) && AIVehicle.GetLocation(v)==j.depot) {
      j.pending=null;
      if(v==j.b) { j.phase="WAIT_A_TAIL_CLEAR"; j.admission="UNKNOWN"; }
      OpexRSLog(j,"RECOVER_BEFORE","kind=start vehicle="+v);
      return true;
    }
    /* StartStop is a toggle: never replay it after Load. If B is moving,
     * no per-wagon/tick evidence reconstructs its historical admission;
     * resolve uncertainty as HOLD, preserving both physical trains. */
    if(v==j.b) return false;
    if(AIVehicle.IsValidVehicle(v) && AIVehicle.GetState(v)==AIVehicle.VS_RUNNING) {
      j.pending=null; j.phase="WAIT_A_TAIL_CLEAR";
      j.admission="UNKNOWN";
      OpexRSLog(j,"RECOVER_AFTER","kind=start vehicle="+v);
      return true;
    }
  }
  return false;
}

function OpexRSReconcile(owner)
{
  foreach(id,j in RS_JOURNAL) {
    if(!OpexRSJournalV2(j)) {
      RS_LEGACY_HOLD=true;
      /* A corrupt journal still fences its identifiable line against
       * unrelated builders/vehicle retirement; never create a new plan. */
      if(owner._lines!=null && typeof id=="integer")
        foreach(item in owner._lines) if(item.lineId==id) item.railSidings<-id;
      if(j.phase!="HOLD") OpexRSHold(j,"LOAD_LEGACY_OR_INVALID_ORDER_JOURNAL");
      continue;
    }
    j.admission="UNKNOWN"; j.positions={};j.lastMotion={};
    /* r12-r16 v2 journals predate lastPhysical. Squirrel '=' cannot
     * introduce a new table slot: rawset is mandatory on real Load. */
    j.lastObserve=-1;j.rawset("lastPhysical",-1);j.loaded=true;
    if(!("parkPosition" in j)) j.rawset("parkPosition",-1);
    if(!("parkAttempts" in j)) j.rawset("parkAttempts",0);
    if(!("parkNextDate" in j)) j.rawset("parkNextDate",0);
    if(!("parkRequested" in j)) j.rawset("parkRequested",false);
    local line=null;
    if(owner._lines!=null) foreach(item in owner._lines) if(item.lineId==id){line=item;break;}
    if(line==null) {OpexRSHold(j,"LOAD_LINE_MISSING");continue;}
    line.railSidings<-id;
    if(j.phase=="HOLD") continue;
    /* Resolve effective OFF before any pending Build/Buy/Start reconciliation
     * can adopt a clone or schedule another operation after Load. */
    if(!RAIL_SIDINGS_SHADOW) {OpexRSHold(j,"OFF_DURING_WORK");continue;}
    if(OpexRSSignature(j.a)!=j.sigA
        || (OpexRSOrders(j.a)!=j.orders && !OpexRSParkOrdersValid(j))
        || (j.b>=0 && (OpexRSSignature(j.b)!=j.sigB || OpexRSOrders(j.b)!=j.orders))) {
      OpexRSHold(j,"LOAD_IDENTITY");continue;
    }
    if(j.pending!=null) {
      if(!OpexRSReconcilePending(owner,line,j)) {
        OpexRSHold(j,"LOAD_COMMAND_UNCERTAIN_NO_REPLAY");continue;
      }
    }
    if((j.phase=="RUN" || j.phase=="VERIFY" || j.phase=="BUY"
        || j.phase=="START_A" || j.phase=="START_B"
        || j.phase=="WAIT_A_TAIL_CLEAR")
        && !OpexRSPhysical(j.plan)) OpexRSHold(j,"LOAD_NETWORK");
    else OpexRSLog(j,"RECONCILED","observed_reservations=UNKNOWN");
  }
}

/* Engine AutoRenew events are the provenance for remapping, not a raw ID
 * match. Shape, group, orders and maximum length must still match. */
function OpexRSAutoreplaced(oldVehicle,newVehicle)
{
  foreach(id,j in RS_JOURNAL) {
    if(oldVehicle!=j.a && oldVehicle!=j.b) continue;
    local valid=OpexRSJournalV2(j) && OpexRSSignature(newVehicle)!=""
        && OpexRSOrders(newVehicle)==j.orders
        && AIVehicle.GetLength(newVehicle)<=j.plan.length16;
    if(oldVehicle==j.a) {j.a=newVehicle;j.sigA=OpexRSSignature(newVehicle);}
    else {j.b=newVehicle;j.sigB=OpexRSSignature(newVehicle);}
    j.admission="UNKNOWN";
    if(!valid || j.phase!="RUN") OpexRSHold(j,"AUTORENEW_REVALIDATION");
    else OpexRSLog(j,"AUTORENEW");
  }
}
