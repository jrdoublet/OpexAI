// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* SIDINGS V2: the opt-in freight branch of EXPAND. Evaluation owns nothing;
 * selection alone opens an existing V284, upgrade or SIDINGS transaction.
 * All monetary comparisons use additional carried cargo and full cash tied
 * up, including replacement stock (no anticipated sale finances a purchase).
 */
function OpexRSExpandOwns(line)
{
  return line!=null && ("mode" in line) && line.mode=="rail"
      && ("kind" in line) && line.kind=="freight"
      && ("vehicles" in line) && line.vehicles!=null && line.vehicles.len()==1
      && line.trains==1 && !OpexRSProtected(line)
      && !("railLoopV3Txn" in line) && !("railLoopV3Clone" in line)
      && !("railPair" in line) && !("doubleGrowDirectional" in line)
      && (!("railLoop" in line) || line.railLoop==0);
}

function OpexRSExpandLog(line,option,reason,offer=null)
{
  if(!DECISION_LOG) return;
  local detail=offer==null?"":" cost="+offer.cost+" margin="+offer.margin.tointeger()
      +" delta_monthly="+offer.delta.tointeger()+" reserve="+offer.reserve
      +" score="+offer.score;
  OpexDiagLog("RS_EXPAND line="+line.lineId+" option="+option+" reason="+reason+detail);
}

/* Bounded, non-mutating exposure funnel. A geometry preflight only matters
 * economically when a line has passed these independent admission gates.
 * Keep live station stock distinct from historical peaks in the receipts. */
function OpexRSExpandGateLog(line,stage,reason,economics=null)
{
  if(!DECISION_LOG) return;
  local detail="";
  if(economics!=null && ("waiting" in economics) && ("capacity" in economics))
    detail+=" live="+economics.waiting+" train_capacity="+economics.capacity
        +" two_train_need="+(2*economics.capacity);
  if(("lastWaitingA" in line) && ("lastWaitingADate" in line))
    detail+=" observed_peak="+line.lastWaitingA+" observed_day="+line.lastWaitingADate;
  OpexDiagLog("RS_EXPAND_GATE line="+line.lineId+" stage="+stage+" reason="+reason+detail);
}

/* GetIndustryID(tile) only recognises certain tiles of a multi-tile mine.
 * Existing rail lines persist AIIndustry.GetLocation(), which can be a
 * different footprint tile: the site123 native SAV exhibited exactly this
 * mismatch (line.originA=22021, direct ID invalid, active coal production).
 * Recover solely by an EXACT unique saved industry location, live positive
 * production of the correct cargo, and the owned source station nearby.
 * Never use a nearest-neighbour industry or a cargo-stock guess. */
function OpexRSOriginIndustry(line)
{
  if(!("originA" in line) || !AIMap.IsValidTile(line.originA)
      || !("stationA" in line) || !AIMap.IsValidTile(line.stationA)
      || !("cargo" in line)) return -1;
  local direct=AIIndustry.GetIndustryID(line.originA);
  if(AIIndustry.IsValidIndustry(direct)) return direct;
  if(AIMap.DistanceManhattan(line.originA,line.stationA)>12
      || !AIStation.IsValidStation(AIStation.GetStationID(line.stationA))
      || !AICompany.IsMine(AITile.GetOwner(line.stationA))) return -1;
  local candidate=-1,matches=0,examined=0;
  foreach(id,_ in AIIndustryList()) {
    examined++;
    /* Bounded even when extra NewGRFs add many industries. */
    if(examined>1024) return -1;
    if(!AIIndustry.IsValidIndustry(id)
        || AIIndustry.GetLocation(id)!=line.originA
        || AIIndustry.GetLastMonthProduction(id,line.cargo)<=0) continue;
    candidate=id;matches++;
    if(matches>1) return -1;
  }
  if(matches!=1) return -1;
  if(DECISION_LOG) OpexDiagLog("RS_SOURCE_RECOVER line="+line.lineId
      +" origin="+line.originA+" industry="+candidate
      +" examined="+examined+" matching="+matches);
  return candidate;
}

function OpexRSOriginIndustryCached(line)
{
  if (("originA" in line) && ("railGrowIndustry" in line)
      && AIIndustry.IsValidIndustry(line.railGrowIndustry)
      && AIIndustry.GetLocation(line.railGrowIndustry) == line.originA) {
    return line.railGrowIndustry;
  }
  local industry = OpexRSOriginIndustry(line);
  if (AIIndustry.IsValidIndustry(industry)) line.rawset("railGrowIndustry", industry);
  return industry;
}

/* Coherent, deliberately cautious model for every alternative. Current
 * production/rating cap demand; waiting stock is not recurring production.
 * C41 supplies speed/acceleration and dwell. Revenue per additional unit is
 * capped by observed gross per unit of current service capacity. */
function OpexRSProductionDriftMean(ratingPct,months)
{
  if(AIGameSettings.IsValid("economy.type") && AIGameSettings.GetValue("economy.type")!=1) return 1.0;
  local drift=ratingPct>80?(4.0/6.0):(ratingPct>60?(1.0/3.0):(-1.0/3.0));
  drift=drift*0.135/22.0;
  local factor=1.0,sum=0.0;
  for(local t=0;t<months;t++) {factor*=1.0+drift;sum+=factor;}
  return months>0?sum/months:1.0;
}

function OpexRSExpandMargin(line,economics,loco,wagon,number,add,infrastructure,efficiency=1.0)
{
  local vehicle=line.vehicles[0],oldNumber=AIVehicle.GetNumWagons(vehicle)-1;
  local oldLoco=OpexV257Engine(AIVehicle.GetEngineType(vehicle),line.cargo,false);
  if(oldLoco==null || loco==null || wagon==null || number<1 || oldNumber<1) return null;
  local industry=OpexRSOriginIndustry(line);
  local station=AIStation.GetStationID(line.stationA);
  if(!AIIndustry.IsValidIndustry(industry) || !AIStation.IsValidStation(station)) return null;
  local production=AIIndustry.GetLastMonthProduction(industry,line.cargo);
  local rating=AIStation.GetCargoRating(station,line.cargo);
  if(production<=0 || rating<=0) return null;
  local offered=production*rating/100.0;
  local distance=("routeDistance" in line)?line.routeDistance:line.distance;
  local oldSpeed=OpexRailEffectiveSpeed(oldLoco,wagon,oldNumber,distance);
  local speed=OpexRailEffectiveSpeed(loco,wagon,number,distance);
  if(oldSpeed<=0 || speed<=0 || distance<=0) return null;
  local days=distance/(0.036*speed),oldDays=distance/(0.036*oldSpeed);
  local dwell=OpexRailStationDwellDays(wagon);
  local current=economics.capacity*30.0/(2*oldDays+dwell);
  local target=number*wagon.capacity*30.0/(2*days+dwell);
  local after=add?(current+target)*efficiency:target;
  /* rail_sidings_trigger=1 : une rame de plus divise l'intervalle de ramassage. Le gain de note
   * est celui du bareme (OpexStationRatingForHeadway) entre le cycle actuel et sa moitie, ajoute a
   * la note OBSERVEE ; la production reste celle du mois dernier. Seul l'ajout de rame en profite. */
  local offeredAfter=offered;
  if(add && RS_ECONOMIC_TRIGGER) {
    local cycle=2*oldDays+dwell;
    local gain=OpexStationRatingForHeadway(cycle/2.0)-OpexStationRatingForHeadway(cycle);
    local ratingAfter=rating+(gain>0?gain:0);
    if(ratingAfter>100) ratingAfter=100;
    offeredAfter=production*ratingAfter/100.0;
    /* rail_sidings_trigger=2 : economie smooth (industry_cmd.cpp) -- chaque mois, 1 chance sur 22
     * de varier de 3 a 23 % (moyenne 13,5 %), a la hausse 2 fois sur 3 si plus de 60 % du cargo est
     * transporte (5 sur 6 au-dela de 80 %), a la baisse 2 fois sur 3 sinon. La note sert de
     * substitut au taux transporte ; production moyenne sur l'horizon de remboursement (4 ans). */
    if(RS_TRIGGER_GROWTH) {
      offered=offered*OpexRSProductionDriftMean(rating,48);
      offeredAfter=offeredAfter*OpexRSProductionDriftMean(ratingAfter,48);
    }
  }
  /* NoAI's min() takes integers. These monthly capacities are fractional:
   * preserve their precision instead of truncating demand or crashing. */
  local before=current<offered?current:offered,carried=after<offeredAfter?after:offeredAfter;
  local delta=carried-before;
  if(delta<=0 || before<=0) {
    if(DECISION_LOG)
      OpexDiagLog("RS_MARGIN line="+line.lineId+" reason=NO_ADDITIONAL_CARGO"
          +" current="+current+" target="+target
          +" offered="+offered+" after="+after);
    return null;
  }
  local oldRunning=AIVehicle.GetRunningCost(vehicle);
  if(oldRunning<0) return null;
  local gross=economics.profit+oldRunning;
  if(("lastRevenue" in line) && line.lastRevenue>0 && line.lastRevenue<gross)
    gross=line.lastRevenue;
  local income=AICargo.GetCargoIncome(line.cargo,line.distance,
      OpexCeilDiv(days+number*wagon.capacity*15.0/offered,1));
  local cap=gross/(12.0*before),unit=income<cap?income:cap;
  local running=loco.runningCost+number*wagon.runningCost-(add?0:oldRunning);
  local stock=loco.price+number*wagon.price;
  local cost=(stock+infrastructure).tointeger();
  local reserve=max(5000,(infrastructure/5).tointeger());
  local margin=12*delta*unit-running;
  /* Full purchase and risk allowance. A wagon replacement keeps the
   * three-year cash payback; an added train with its infrastructure
   * (direct train, SIDINGS, doubling) gets four years: the track outlives
   * the 5-10 year horizon and near misses (12.6k/yr for 47k) were vetoed. */
  local payback=add?4:3;
  if(margin<=0 || cost+reserve>payback*margin
      || AICompany.GetBankBalance(AICompany.COMPANY_SELF)<cost+reserve) {
    if(DECISION_LOG)
      OpexDiagLog("RS_MARGIN line="+line.lineId+" reason=PAYBACK_OR_CASH"
          +" margin="+margin.tointeger()+" cost="+cost+" reserve="+reserve
          +" cash="+AICompany.GetBankBalance(AICompany.COMPANY_SELF)
          +" delta="+delta.tointeger()+" efficiency="+efficiency);
    return null;
  }
  return {cost=cost,reserve=reserve,margin=margin,delta=delta,
      before=before,after=carried,stock=stock,score=margin/(cost+reserve),
      loco=loco,wagon=wagon,number=number};
}

/* Existing freight SINK must accept the exact cargo on the actual game tick.
 * City development can remove GOODS acceptance while the physical station
 * remains unchanged. A historical rating or an industry ID is no certificate
 * of acceptance; reject only new secondary-train/infrastructure investment.
 * This is read-only and used only behind the rail_sidings opt-in arbiter. */
function OpexRSSecondaryDestinationAccepts(line)
{
  if(line==null || !("stationB" in line) || !("cargo" in line)
      || line.stationB==null || !AIMap.IsValidTile(line.stationB)
      || !AICargo.IsValidCargo(line.cargo)) return false;
  local station=AIStation.GetStationID(line.stationB);
  if(station<0 || !AIStation.IsValidStation(station)) return false;
  return AICargoList_StationAccepting(station).HasItem(line.cargo);
}

function OpexRSExpandBetter(left,right)
{
  if(left==null) return right;
  if(right==null) return left;
  /* A cheaper wagon which serves at least as much marginal demand dominates
   * an infrastructure purchase. Otherwise compare the same net cash yield. */
  if(left.option=="WAGON" && left.cost<=right.cost && left.delta>=right.delta) return left;
  if(right.option=="WAGON" && right.cost<=left.cost && right.delta>=left.delta) return right;
  return right.score>left.score?right:left;
}

function OpexRSDirectRoute(line)
{
  if(!("doubleTrack" in line) || line.doubleTrack!=1
      || !("depot2" in line) || line.depot2==null || !AIRail.IsRailDepotTile(line.depot2)
      || !("platformA2" in line) || !("platformB2" in line)
      || line.platformA2==null || line.platformB2==null
      || !("stationA2" in line) || !("stationB2" in line)) return null;
  if(!OpexV233LPlatformReady(line.platformA2,AIStation.GetStationID(line.stationA))
      || !OpexV233LPlatformReady(line.platformB2,AIStation.GetStationID(line.stationB))) return null;
  local secondary={platformA=line.platformA2,stationA=line.stationA2,stationB=line.stationB2};
  local route=OpexRSUniqueTrace(secondary);
  if(route==null || !OpexRSDepotReachable(line.depot2,route)) return null;
  return route;
}

/* No dates, quotas, pending state, line fields or journal are written here.
 * AITestMode probes are allowed; actual construction is Execute's job. */
function OpexRSExpandEvaluate(owner,line,year)
{
  local result={best=null,reason="NO_SAFE_RETURN",geometry=false};
  if(!OpexRSExpandOwns(line) || (("scrapping" in line) && line.scrapping)
      || !("depot" in line) || !("originA" in line)
      || !("platformA" in line) || !("platformB" in line)
      || line.platformA==null || line.platformB==null || !AIRail.IsRailDepotTile(line.depot)
      || OpexV163Wagons2(line)>0) return result;
  local vehicle=line.vehicles[0];
  if(OpexRSSignature(vehicle)=="" || AIVehicle.GetAgeLeft(vehicle)<730
      || (owner._vehiclesToRetire!=null && vehicle in owner._vehiclesToRetire)) return result;
  local economics=OpexRSEconomicSignal(line);
  if(!economics.ok) {
    result.reason=economics.reason;
    OpexRSExpandGateLog(line,"SIGNAL",result.reason,economics);
    return result;
  }
  local number=AIVehicle.GetNumWagons(vehicle)-1;
  if(number<1 || AIEngine.GetCapacity(AIVehicle.GetEngineType(vehicle))>0) return result;
  local wagonId=AIVehicle.GetWagonEngineType(vehicle,1);
  if(!AIEngine.IsWagon(wagonId) || !AIEngine.IsBuildable(wagonId)
      || AIEngine.GetCargoType(wagonId)!=line.cargo) return result;
  for(local k=1;k<=number;k++) if(AIVehicle.GetWagonEngineType(vehicle,k)!=wagonId) return result;
  local wagon=OpexV257Engine(wagonId,line.cargo,true);
  local loco=OpexV257Engine(AIVehicle.GetEngineType(vehicle),line.cargo,false);
  if(wagon==null || loco==null || !AIEngine.IsBuildable(loco.id)) return result;
  if(OpexRSWagonAlternative(owner,line,economics)) {
    local kDec=(ESTIM_UNIFIE & 4)!=0?OpexC69ComputeKDec().K_dec:-1;
    local targetNumber=number+1;
    local equipment=null;
    if(RAIL_GROW) { // rail_fill retire le 20/11
      local fillPlan=OpexRailFillPlan(line,vehicle,wagon,number,
          OpexRailNominalMaxWagons(OpexV284Limit(line)));
      if(fillPlan!=null) {
        targetNumber=fillPlan.number;
        equipment=fillPlan.equipment;
      }
    }
    if(equipment==null)
      equipment=OpexV284Equipment(line,vehicle,wagon,targetNumber,false,economics.waiting,kDec);
    if(equipment!=null) {
      local newLoco=OpexV257Engine(equipment.engine,line.cargo,false);
      local offer=OpexRSExpandMargin(line,economics,newLoco,wagon,targetNumber,false,0);
      if(offer!=null) {
        offer.option <- "WAGON";offer.equipment <- equipment;
        result.best=offer;OpexRSExpandLog(line,"WAGON","FEASIBLE",offer);
      } else OpexRSExpandLog(line,"WAGON","MARGINAL_RETURN_OR_CASH");
    }
  } else OpexRSExpandLog(line,"WAGON","LIMIT_TRACTION_OR_SELECTOR_GUARD");
  /* The SIGNAL gate already requires a full trainload of backlog. Asking for
   * TWO live trainloads vetoed 70 lines in the 5x5 fix3 pilot before any
   * pricing; the margin model (production x rating cap) decides instead. */
  if(economics.backlog<economics.capacity && !RS_ECONOMIC_TRIGGER) {
    result.reason="NO_SECOND_TRAIN_DEMAND_OR_SLOT";
    OpexRSExpandGateLog(line,"DEMAND","NO_SECOND_TRAIN_DEMAND",economics);
    return result;
  }
  if(!OpexRailVehicleSlotAvailable()) {
    result.reason="NO_SECOND_TRAIN_DEMAND_OR_SLOT";
    OpexRSExpandGateLog(line,"FLEET","NO_VEHICLE_SLOT",economics);
    return result;
  }
  if(!OpexRSSecondaryDestinationAccepts(line)) {
    result.reason="DESTINATION_NOT_ACCEPTING_CARGO";
    OpexRSExpandGateLog(line,"DESTINATION",result.reason,economics);
    return result;
  }
  /* No arbitrary 50%-of-existing-revenue payback veto before routing:
   * the full model below prices incremental monthly volume/frequency,
   * actual equipment, infrastructure, opex, reserve and three-year payback.
   * Its production/rating cap remains the conservative input, not a promise
   * of any future station-rating improvement. */
  if(("doubleTrack" in line) && line.doubleTrack==1) {
    local direct=OpexRSDirectRoute(line);
    local offer=direct==null?null:OpexRSExpandMargin(line,economics,loco,wagon,number,true,0);
    if(offer!=null) {
      offer.option <- "TRAIN";result.best=OpexRSExpandBetter(result.best,offer);
      OpexRSExpandLog(line,"TRAIN","FEASIBLE",offer);
    } else OpexRSExpandLog(line,"TRAIN","INFRASTRUCTURE_OR_MARGIN");
    return result;
  }
  OpexRSExpandLog(line,"TRAIN","SINGLE_TRACK_NEEDS_WORKS");
  /* rail_sidings_trigger=1 : sans le veto du stock, chaque ligne atteignait le traceur de route
   * et le planificateur (181 k opcodes par scan contre 10 k, smoke du 17/11) avant d'etre refusee
   * par la marge. Si une seconde rame ne se rembourse pas meme avec une infrastructure GRATUITE,
   * ni evitement ni doublement ne le peut : on s'arrete avant toute trace, attente de 180 jours. */
  if(RS_ECONOMIC_TRIGGER && result.best==null
      && OpexRSExpandMargin(line,economics,loco,wagon,number,true,0,0.85)==null) {
    result.reason="PRECHECK_MARGIN";result.geometry=true;
    OpexRSExpandLog(line,"SIDINGS","PRECHECK_MARGIN");
    return result;
  }
  if(!OpexRSEligible(owner,line)) {result.reason="SHARED_STATION_OR_TRANSACTION";return result;}
  local route=OpexV284Trace(line);
  if(route==null) route=OpexRSUniqueTrace(line);
  if(route==null) {result.reason="ROUTE_UNTRACEABLE";return result;}
  /* A proof of exclusivity matters when an additional infrastructure offer
   * can actually be admitted. A route with no SOURCE plan and no profitable
   * DOUBLE option must not spend opcodes proving a future construction that
   * cannot occur. Recheck before every viable offer; never cache across calls. */
  local exclusiveKnown=false,exclusive=false;
  local railTiles=OpexRSRouteTiles(route);
  /* The planner verifies SOURCE, LOOP, PBS, ownership and full-train length.
   * A previous fixed 150-tile admission barrier rejected even physically
   * plausible 80-140-tile corridors before any native safety check. Bound
   * this cheap prefilter by consist length and a real geometric allowance.
   * Keep the existing 60k plan and 180k scan opcode budgets unchanged. */
  local minimumSidingRoute=max(60,4*((AIVehicle.GetLength(vehicle)+15)/16)+36);
  if(railTiles>=minimumSidingRoute && (!(line.lineId in RS_REJECT_UNTIL)
      || AIDate.GetCurrentDate()>=RS_REJECT_UNTIL[line.lineId])) {
    local plan=OpexRSPlan(line,route);
    if(plan!=null && !OpexRSBuildPreflight(plan)) {
      /* A second complete combination changes both the berth and the loop;
       * never retry the identical rejected plan or bypass engine rejection. */
      plan=OpexRSPlan(line,route,plan.loops[0],plan.source);
      if(plan!=null && !OpexRSBuildPreflight(plan)) plan=null;
    }
    if(plan!=null) {
      local offer=OpexRSExpandMargin(line,economics,loco,wagon,number,true,plan.quote,0.85);
      if(offer!=null) {
        if(!exclusiveKnown) {exclusive=OpexRSCorridorExclusive(owner,line,route);exclusiveKnown=true;}
        if(!exclusive) {result.reason="SHARED_OR_UNPROVEN_CORRIDOR";return result;}
        offer.option <- "SIDINGS";offer.plan <- plan;offer.railTiles <- railTiles;
        offer.economics <- economics;result.best=OpexRSExpandBetter(result.best,offer);
        OpexRSExpandLog(line,"SIDINGS","FEASIBLE",offer);
      } else OpexRSExpandLog(line,"SIDINGS","MARGINAL_RETURN_OR_CASH");
    } else {result.geometry=true;OpexRSExpandLog(line,"SIDINGS","NO_COMPLETE_SAFE_PLAN");}
  } else {
    if(DECISION_LOG) OpexDiagLog("RS_ROUTE_GATE line="+line.lineId
        +" route_tiles="+railTiles+" minimum="+minimumSidingRoute
        +" cooldown="+((line.lineId in RS_REJECT_UNTIL)?RS_REJECT_UNTIL[line.lineId]:-1));
    OpexRSExpandLog(line,"SIDINGS",
        railTiles<minimumSidingRoute?"SHORT_ROUTE":"GEOMETRY_COOLDOWN");
  }
  /* The existing resumable full-double planner remains responsible for its
   * final route. This is a planning offer, not a buildability certificate.
   * It must win despite its full route/station/depot cost and risk reserve. */
  if(RAIL_DOUBLE_OFF) OpexRSExpandLog(line,"DOUBLE","DISABLED");
  else if(line.loco.id==loco.id && line.wagons==number
      && line.cargo in owner._catalog.wagonByCargo
      && owner._catalog.wagonByCargo[line.cargo].id==wagon.id
      && owner._railSearch==null && (owner._abandonedPairs==null
      || !(OpexRailUpgradeRejectKey(line.lineId) in owner._abandonedPairs))) {
    local infrastructure=railTiles*owner._catalog.costTrackPerTile
        +2*line.platformLength*owner._catalog.costStation
        +AIRail.GetBuildCost(AIRail.GetCurrentRailType(),AIRail.BT_DEPOT);
    local offer=OpexRSExpandMargin(line,economics,loco,wagon,number,true,infrastructure);
    if(offer!=null) {
      if(!exclusiveKnown) {exclusive=OpexRSCorridorExclusive(owner,line,route);exclusiveKnown=true;}
      if(!exclusive) {result.reason="SHARED_OR_UNPROVEN_CORRIDOR";return result;}
      local prep=OpexPrepareUpgradeSearch(line,HARD_ITERATION_CAP);
      if(prep.ok) {
        offer.option <- "DOUBLE";offer.prep <- prep;
        result.best=OpexRSExpandBetter(result.best,offer);
        OpexRSExpandLog(line,"DOUBLE","SEARCH_REQUIRED",offer);
      } else OpexRSExpandLog(line,"DOUBLE",prep.reason);
    } else OpexRSExpandLog(line,"DOUBLE","MARGINAL_RETURN_OR_CASH");
  } else OpexRSExpandLog(line,"DOUBLE","SEARCH_BUSY_OR_COOLDOWN");
  return result;
}

function OpexRSExpandExecute(owner,line,offer)
{
  if(!OpexRSIdle(owner) || AICompany.GetBankBalance(AICompany.COMPANY_SELF)<offer.cost+offer.reserve)
    return false;
  if((offer.option=="SIDINGS" || offer.option=="DOUBLE" || offer.option=="TRAIN")
      && !OpexRSSecondaryDestinationAccepts(line)) {
    if(DECISION_LOG) OpexDiagLog("RS_EXPAND_GATE line="+line.lineId
        +" stage=DESTINATION reason=DESTINATION_NOT_ACCEPTING_AT_EXECUTE");
    return false;
  }
  if(offer.option=="SIDINGS") return OpexRSExecute(owner,line,offer);
  if(offer.option=="DOUBLE") {owner._startRailUpgradeSearch(line,offer.prep);return true;}
  if(offer.option=="TRAIN") {
    if(!OpexRailVehicleSlotAvailable() || OpexRSDirectRoute(line)==null) return false;
    /* Use the normal builder, but the same stock that was actually priced. */
    if(line.loco.id!=offer.loco.id || line.wagons!=offer.number
        || !(line.cargo in owner._catalog.wagonByCargo)
        || owner._catalog.wagonByCargo[line.cargo].id!=offer.wagon.id) return false;
    local built=OpexBuildSecondTrain(owner._catalog,line);
    if(!built.ok) return false;
    line.vehicles.append(built.train);line.trains=line.vehicles.len();line.vehCount<-line.trains;
    owner._saveProjection=null;return true;
  }
  if(offer.option!="WAGON") return false;
  /* Reuse the V284 transaction and its physical verification/rollback. */
  if(owner._v284State==null) owner._v284State={nextDate=0,dates={},loops={},pending=null};
  local state=owner._v284State,date=AIDate.GetCurrentDate(),v=line.vehicles[0];
  local equipment=offer.equipment;
  local waitDays=max(120,min(730,(2*line.distance/(0.036*equipment.speed)).tointeger()+60));
  state.nextDate=date+30;state.dates.rawset(line.lineId,date+90);
  state.pending={lineId=line.lineId,vehicle=v,newVehicle=-1,
    engine=equipment.engine,wagon=offer.wagon.id,wagons=offer.number,
    oldWagons=AIVehicle.GetNumWagons(v)-1,add=false,loopPlan=null,
    speedMilli=(equipment.speed*1000).tointeger(),oldSpeedMilli=(equipment.oldSpeed*1000).tointeger(),
    phase="approach",deadline=date+waitDays,before=null,depot=line.depot,
    waiting=AIStation.GetCargoWaiting(AIStation.GetStationID(line.stationA),line.cargo),cashBefore=0};
  owner._saveProjection=null;return true;
}

function OpexRSExpand(owner,year)
{
  if(!RAIL_SIDINGS_SHADOW || RS_LEGACY_HOLD || !SAVE_FULL_STATE
      || !OpexRSNoLegacyLocks() || owner._catalog==null || owner._lines==null) return false;
  foreach(id,j in RS_JOURNAL) if(j.phase!="RUN" && j.phase!="HOLD") return true;
  if(!OpexRSIdle(owner) || (V233L_STATE!=null && V233L_STATE.pending!=null)) return false;
  local date=AIDate.GetCurrentDate(),count=owner._lines.len();
  if(count==0 || date<RS_NEXT_SCAN) return false;
  RS_NEXT_SCAN=date+30;
  local first=RS_SCAN_CURSOR%count,examined=0,traversed=0,best=null,bestLine=null;
  local mark=OpexOpsMeasureBegin();
  for(local i=0;i<count && examined<4 && OpexOpsMeasureEnd(mark)<180000;i++) {
    local line=owner._lines[(first+i)%count];
    traversed++;
    if(!OpexRSExpandOwns(line)) {
      if(DECISION_LOG && line!=null && ("mode" in line) && line.mode=="rail"
          && ("kind" in line) && line.kind=="freight")
        OpexDiagLog("RS_EXPAND_SKIP line="+line.lineId+" reason=NOT_OWNED");
      continue;
    }
    examined++;RS_SCAN_CURSOR=(first+i+1)%count;
    if(owner._v284State!=null && line.lineId in owner._v284State.dates
        && date<owner._v284State.dates[line.lineId]) continue;
    local oldType=AIRail.GetCurrentRailType();
    if(("depot" in line) && AIRail.IsRailDepotTile(line.depot))
      AIRail.SetCurrentRailType(AIRail.GetRailType(line.depot));
    local evaluated=OpexRSExpandEvaluate(owner,line,year);
    AIRail.SetCurrentRailType(oldType);
    if(evaluated.geometry) RS_REJECT_UNTIL.rawset(line.lineId,date+180);
    if(evaluated.best==null) {OpexRSExpandLog(line,"NONE",evaluated.reason);continue;}
    if(best==null || evaluated.best.score>best.score) {best=evaluated.best;bestLine=line;}
  }
  if(DECISION_LOG)
    OpexDiagLog("RS_EXPAND_SCAN year="+year+" game_day="+date
        +" cursor_before="+first+" cursor_after="+RS_SCAN_CURSOR
        +" traversed="+traversed+" examined="+examined
        +" scan_ops="+OpexOpsMeasureEnd(mark)
        +" best="+(best!=null?best.option:"NONE"));
  if(best==null) return false;
  local oldType=AIRail.GetCurrentRailType();AIRail.SetCurrentRailType(AIRail.GetRailType(bestLine.depot));
  local executed=OpexRSExpandExecute(owner,bestLine,best);
  AIRail.SetCurrentRailType(oldType);
  OpexRSExpandLog(bestLine,best.option,executed?"SELECT":"STALE_OR_EXECUTION_REFUSED",best);
  return executed;
}

/* The provisional full-double quote never authorizes building. Reprice the
 * resolved route with real engine commands and recheck demand/exclusivity
 * before the legacy executor can touch a tile. No extra persisted state. */
function OpexRSDoubleReady(owner,state)
{
  local line=state.line;
  if(!OpexRSEligible(owner,line) || state.search.path==false || state.search.path==null) return false;
  local route=OpexRSUniqueTrace(line);
  if(route==null || !OpexRSCorridorExclusive(owner,line,route)) return false;
  local tiles=OpexResolveSearchTiles(state.search),structures=OpexResolveSearchStructures(state.search);
  if(tiles==null || tiles.len()<3 || !OpexJoinPathIsDedicated(tiles)) return false;
  local a=OpexMatchPlan(state.prep.dualA,tiles[0]);
  local b=OpexMatchPlan(state.prep.dualB,tiles[tiles.len()-1]);
  if(a==null || b==null) return false;
  local ok=false,price=0;
  {
    local account=AIAccounting();local test=AITestMode();
    ok=AIRail.BuildRailStation(a.anchor,a.direction,1,a.length,state.prep.stationIdA)
        && AIRail.BuildRailStation(b.anchor,b.direction,1,b.length,state.prep.stationIdB)
        && OpexBuildTrack(tiles,structures)==0;
    price=account.GetCosts();
  }
  if(!ok) return false;
  price+=AIRail.GetBuildCost(AIRail.GetCurrentRailType(),AIRail.BT_DEPOT)+5000;
  local economics=OpexRSEconomicSignal(line);
  if(!economics.ok || (economics.waiting<2*economics.capacity && !RS_ECONOMIC_TRIGGER)) return false;
  local wagon=owner._catalog.wagonByCargo[line.cargo];
  local offer=OpexRSExpandMargin(line,economics,line.loco,wagon,line.wagons,true,price);
  return offer!=null;
}
