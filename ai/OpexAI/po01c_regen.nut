// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* PO-01C: ephemeral reactive batch, private producers, selective publication. */
/* Opcodes per call, across ticks if needed (about 4 ticks, < 1 day). The hook runs once
 * per main-loop pass (~44 ticks measured), so 4000 left a batch at ~26 k ops/day. */
const PO01C_SLICE_OPS = 40000;
/* One resume gets 30k before propagation. Step can start a second unit near
 * 40k: target <70k plus one indivisible operation, not a hard API-call bound.
 * Only Step writes the mark, immediately before resume; never persisted. */
const PO01C_WORK_OPS = 30000;
PO01C_WORK_MARK <- null;
/* Transient diagnostic only, never part of Save/Load. Allocated only on logging. */
PO01C_WHERE <- null;
function OpexPO01CWhere(gen, site, idx)
{
  if (DECISION_LOG) {
    if (PO01C_WHERE == null) PO01C_WHERE = { gen = "", site = "", idx = -1 };
    PO01C_WHERE.gen = gen;
    PO01C_WHERE.site = site;
    PO01C_WHERE.idx = idx;
  }
}

function OpexPO01CUnitEnd(mark, phase, unit, gen, site)
{
  if (!DECISION_LOG) return;
  local ops = OpexOpsMeasureEnd(mark);
  if (ops > PO01C_SLICE_OPS) OpexDecide("PO01C_UNIT", "phase=" + phase
      + " mode=" + unit + " gen=" + gen + " site=" + site + " idx=-1 ops=" + ops);
}

/* Expressions keep historical evaluation order inside table literals. Only the
 * logged branch calls these wrappers; no extra yield or historical computation. */
function OpexPO01CLoggedTopK(all, count, mode)
{
  if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", mode + ":OpexTopK", -1);
  return OpexTopK(all, count);
}

function OpexPO01CLoggedBands(all)
{
  if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", "rail:OpexBands", -1);
  return OpexBands(all);
}
function OpexPO01CModeEnabled(mode)
{
  if (mode == "air") return MODE_AIR;
  if (mode == "rail") return MODE_RAIL;
  if (mode == "road") return MODE_ROAD && ROAD_BUILD_ENABLED;
  if (mode == "water") return MODE_WATER;
  return true;
}

function OpexPO01CEmptyGenerated(projects)
{
  return { projects = [], rail = null, road = null, airPlan = null, waterPlan = null,
      airPlans = [], waterPlans = [], freightCargo = projects.freightCargo };
}

/* EB-14 only: physically bounded Manhattan bands, independent for each cargo.
 * No edits to the mechanically generated historical PO01C producers are needed.
 * The maximum is the actual map span, never the old railMax=200. */
function OpexEB14RailBand(units, kind, cargo, low, high, minDistance, span)
{
  if (low < minDistance) low = minDistance;
  if (high > span) high = span;
  if (low <= high) units.append({ kind = kind, cargo = cargo, low = low, high = high,
      examined = 0, inBand = 0, evaluated = 0, produced = 0 });
}

function OpexEB14RailUnits(catalog)
{
  local units = [], durable = [], fast = [];
  local span = OpexMapManhattanSpan();
  local minPax = OpexCatalogBounds(catalog).railMin;
  local cargoOrder = OpexFreightCargoOrder(catalog);
  local bounds = OpexCatalogBounds(catalog);
  local railSpeed = bounds.vRail > 0 ? bounds.vRail : 1;
  local ticksPerDay = bounds.ticksPerDay > 0 ? bounds.ticksPerDay : 74;
  local daysPerTile = OpexDaysPerTile(railSpeed, ticksPerDay);
  foreach (cargo in cargoOrder) {
    if (catalog.locoByCargoWagons != null && !(cargo in catalog.locoByCargoWagons)) continue;
    /* Evaluate the income curve at three travel times derived from the CURRENT
     * train speed, once per cargo. Compare tariff per Manhattan tile: OpenTTD
     * multiplies the tariff by distance, and a raw 220-vs-80 fare would
     * otherwise label even a highly perishable cargo as long-distance. */
    local days80 = (80.0 * daysPerTile + 4.0).tointeger();
    local days140 = (140.0 * daysPerTile + 4.0).tointeger();
    local days220 = (220.0 * daysPerTile + 4.0).tointeger();
    local income80 = AICargo.GetCargoIncome(cargo, 80, days80);
    local income140 = AICargo.GetCargoIncome(cargo, 140, days140);
    local income220 = AICargo.GetCargoIncome(cargo, 220, days220);
    local mediumTariff = income80 / 80.0;
    if (income140 / 140.0 > mediumTariff) mediumTariff = income140 / 140.0;
    if (mediumTariff > 0 && income220 / 220.0 < mediumTariff * 0.70)
      fast.append(cargo);
    else durable.append(cargo);
  }
  /* The first work units are valuable long-lived freight, then time-sensitive
   * freight, then independent passenger opportunities. No near-first policy. */
  foreach (cargo in durable) OpexEB14RailBand(units, "freight", cargo, 196, 256, 0, span);
  foreach (cargo in fast) OpexEB14RailBand(units, "freight", cargo, 72, 160, 0, span);
  if (catalog.paxCargo >= 0 && !PAX_AIR_FIRST_RAIL_OFF)
    OpexEB14RailBand(units, "pax", catalog.paxCargo, 140, 256, minPax, span);

  foreach (cargo in durable) {
    OpexEB14RailBand(units, "freight", cargo, 128, 195, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 257, 512, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 64, 127, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 0, 63, 0, span);
  }
  foreach (cargo in fast) {
    OpexEB14RailBand(units, "freight", cargo, 161, 195, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 40, 71, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 196, 256, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 0, 39, 0, span);
    OpexEB14RailBand(units, "freight", cargo, 257, 512, 0, span);
  }
  if (catalog.paxCargo >= 0 && !PAX_AIR_FIRST_RAIL_OFF) {
    OpexEB14RailBand(units, "pax", catalog.paxCargo, 80, 139, minPax, span);
    OpexEB14RailBand(units, "pax", catalog.paxCargo, 257, 512, minPax, span);
    OpexEB14RailBand(units, "pax", catalog.paxCargo, 0, 79, minPax, span);
  }
  local lo = 513, hi = 1024;
  while (lo <= span) {
    foreach (cargo in durable) OpexEB14RailBand(units, "freight", cargo, lo, hi, 0, span);
    foreach (cargo in fast) OpexEB14RailBand(units, "freight", cargo, lo, hi, 0, span);
    if (catalog.paxCargo >= 0 && !PAX_AIR_FIRST_RAIL_OFF)
      OpexEB14RailBand(units, "pax", catalog.paxCargo, lo, hi, minPax, span);
    lo = hi + 1;
    hi = hi * 2;
  }
  /* V233L remains the authority for fed-factory GOOD exports, with its
   * frozen 150..300 window, site preflight and source cursor. */
  if (V233_LONG_GOOD > 0) {
    local good = OpexV233LGoodCargo();
    if (good >= 0 && good in catalog.producers)
      units.append({ kind = "v233", cargo = good, low = 150, high = 300,
          examined = -1, inBand = -1, evaluated = -1, produced = 0 });
  }
  return units;
}

/* A single resumable unit: distance is tested before the expensive economics,
 * station search and pathfinder preparation. Each band has its own spatial
 * search radius; never build a grid whose cell size is the whole map span. */
function OpexEB14RailScan(s, unit, out, stats)
{
  local catalog = s.eb14Catalog, lines = s.lines;
  if (unit.kind == "pax" && PAX_AIR_FIRST_RAIL_OFF) return;
  if (unit.kind == "pax") {
    local towns = catalog.towns, cargo = catalog.paxCargo, produced = [], served = [];
    local mail = V207_RAIL_MAIL && catalog.mailCargo >= 0
        && (catalog.mailCargo in catalog.wagonByCargo);
    local mails = [], airTowns = {};
    if (V275_RAIL_PAX_MM & 1) foreach (line in lines) {
      if (("mode" in line) && line.mode == "air"
          && (!("scrapping" in line) || !line.scrapping)) {
        airTowns.rawset(line.originA, true);
        airTowns.rawset(line.originB, true);
      }
    }
    foreach (i, town in towns) {
      if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
      local monthly = AITown.GetLastMonthProduction(town.id, cargo);
      if (monthly <= 0 && town.pop > 0) monthly = (town.pop * 22) / 100;
      produced.append(monthly);
      served.append(OpexOriginService(lines, town.tile));
      if (mail) {
        local mp = AITown.GetLastMonthProduction(town.id, catalog.mailCargo);
        mails.append(mp > 0 ? mp : 0);
      }
    }
    local grid = OpexSpatialGrid();
    grid.Build(towns, unit.high);
    local cache = clone ::OpexSitableCache;
    local cover = V216_COVER;
    local context = { used = false, now = AIDate.GetCurrentDate(),
        diagnostics = s.paxDiagnostics, cover = {
        ownMonth = cover.ownMonth, advQuarter = cover.advQuarter,
        own = cover.own, adv = clone cover.adv, cache = clone cover.cache } };
    for (local a = 0; a < towns.len(); a++) {
      if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
      local neighbors = grid.GetCandidatesFor(a);
      foreach (b in neighbors) {
        if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
        unit.examined++;
        local distance = AIMap.DistanceManhattan(towns[a].tile, towns[b].tile);
        if (distance < unit.low || distance > unit.high) continue;
        unit.inBand++;
        stats.pairsTotal++;
        if (served[a] != null || served[b] != null
            || (V275_RAIL_PAX_MM & 1) && ((towns[a].tile in airTowns) || (towns[b].tile in airTowns))) {
          stats.pairsOriginServed++;
          continue;
        }
        local aId = towns[a].id, bId = towns[b].id;
        if (aId > bId) { local swap = aId; aId = bId; bId = swap; }
        if (("pax|" + cargo + "|" + aId + "|" + bId) in s.abandoned) continue;
        local part = V207_RAIL_PAX_SHARE_PCT > 0 ? V207_RAIL_PAX_SHARE_PCT : TOWN_CATCHMENT_SHARE_PCT;
        local monthly = ((produced[a] + produced[b]) * part) / 100;
        local secondary = mail ? { cargo = catalog.mailCargo,
            monthly = ((mails[a] + mails[b]) * part) / 100 } : null;
        local box = { value = null };
        unit.evaluated++;
        local child = OpexPO01CMakePaxCandidate(box, cache, context, catalog, "pax", cargo,
            towns[a].tile, towns[b].tile, monthly, false, stats, false, null, null, secondary);
        while (child.getstatus() != "dead") {
          resume child;
          if (child.getstatus() != "dead") yield null;
        }
        if (box.value != null) {
          box.value.srcTown <- towns[a].id;
          box.value.dstTown <- towns[b].id;
          out.append(box.value);
          unit.produced++;
        }
      }
    }
    ::OpexSitableCache = cache;
    if (V216_PROBE && context.used) V216_COVER = context.cover;
    return;
  }
  local cargo = unit.cargo, industries = catalog.industries;
  local sinks = cargo in catalog.acceptors ? catalog.acceptors[cargo] : [];
  local townSinks = cargo in catalog.townAcceptors ? catalog.townAcceptors[cargo] : [];
  local sources = cargo in catalog.producers ? catalog.producers[cargo] : [];
  local serviceCache = {};
  foreach (si in sources) {
    if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
    local source = industries[si];
    if (OPEX_LEVEL_LIMITS && OpexIndustryPrimaryRivalServed(source.id, source.tile)) continue;
    local monthly = AIIndustry.GetLastMonthProduction(source.id, cargo);
    if (monthly <= 0) continue;
    /* A V233L factory is treated by the historical producer, separately.
     * The row test is identical to OpexV233LSource's first admission guard
     * and avoids replaying its costly source scan on every EB14 band. */
    if (V233_LONG_GOOD > 0 && SAVE_FULL_STATE && V233L_STATE != null
        && AICargo.GetCargoLabel(cargo) == "GOOD"
        && (source.id in V233L_STATE.rows)) continue;
    local ss = OpexOriginService(lines, source.tile);
    foreach (di in sinks) {
      if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
      if (di == si) continue;
      unit.examined++;
      local sink = industries[di];
      local distance = AIMap.DistanceManhattan(source.tile, sink.tile);
      if (distance < unit.low || distance > unit.high) continue;
      unit.inBand++;
      local key = "freight|" + cargo + "|" + source.id + "|" + sink.id;
      if (key in s.abandoned) continue;
      stats.pairsTotal++;
      local sd = OpexOriginService(lines, sink.tile);
      local v179Keep = ss == null && sd != null;
      if (!v179Keep && (ss != null || sd != null)) {
        stats.pairsOriginServed++;
        continue;
      }
      local transformer = ("isTransformer" in sink) && sink.isTransformer;
      unit.evaluated++;
      local candidate = OpexMakeCandidate(catalog, "freight", cargo, source.tile,
          sink.tile, monthly, false, stats, transformer);
      if (candidate != null) {
        if (v179Keep) candidate.v179DestServed <- 1;
        out.append(candidate);
        unit.produced++;
      }
    }
    foreach (town in townSinks) {
      if (OpexOpsMeasureEnd(PO01C_WORK_MARK) >= PO01C_WORK_OPS) yield null;
      unit.examined++;
      local distance = AIMap.DistanceManhattan(source.tile, town.tile);
      if (distance < unit.low || distance > unit.high) continue;
      unit.inBand++;
      local key = "freight|" + cargo + "|" + source.id + "|t" + town.id;
      if (key in s.abandoned) continue;
      stats.pairsTotal++;
      if (!(town.id in serviceCache))
        serviceCache.rawset(town.id, OpexOriginService(lines, town.tile));
      if (ss != null || serviceCache[town.id] != null) {
        stats.pairsOriginServed++;
        continue;
      }
      unit.evaluated++;
      local candidate = OpexMakeCandidate(catalog, "freight", cargo, source.tile,
          town.tile, monthly, false, stats);
      if (candidate != null) {
        candidate.dstTown <- town.id;
        out.append(candidate);
        unit.produced++;
      }
    }
  }
}

/* Provenance causale de l'offre RAIL. Les champs restent dans le payload
 * transitoire (pas dans Save/Load), pour suivre la MEME proposition depuis
 * sa bande jusqu'a sa tentative et sa construction physique. Aucune influence
 * sur score, top-K ou capital ; les panneaux ne sont emis qu'avec probes=258. */
function OpexEB14RailTraceSign(name)
{
  if (!EB14_PROGRESSIVE || !DECISION_LOG || !DEBUG_SIGNS
      || EB14_TRACE_SIGN_COUNT >= 120 || name.len() > 31) return;
  local type = name.slice(0, 2);
  if (!(type in EB14_TRACE_SIGN_TYPES)) return;
  /* Ne jamais laisser les nombreuses selections economiques masquer les
   * publications tardives ni les constructions physiques. */
  local cap = type == "E4" ? 48 : (type == "E5" ? 48 : 24);
  if (EB14_TRACE_SIGN_TYPES[type] >= cap) return;
  EB14_TRACE_SIGN_TYPES[type]++;
  local n = EB14_TRACE_SIGN_COUNT;
  EB14_TRACE_SIGN_COUNT++;
  OpexSign(AIMap.GetTileIndex(3 + (n % 12), 3 + (n / 12)), name);
}

function OpexEB14RailTraceProject(project, phase, rank, lineId = -1)
{
  if (!EB14_PROGRESSIVE || !DECISION_LOG || project == null
      || !("payload" in project) || project.payload == null) return;
  local p = project.payload;
  if (!("eb14Low" in p) || !("eb14High" in p)) return;
  OpexDecide("EB14_PROJECT", "phase=" + phase + " rank=" + rank
      + " line=" + lineId + " kind=" + p.kind + " cargo=" + p.cargo
      + " low=" + p.eb14Low + " high=" + p.eb14High
      + " src=" + p.src + " dst=" + p.dst + " dist=" + p.distance
      + " capital=" + p.capital + " profit=" + p.profitAnnual);
  if (!DEBUG_SIGNS) return;
  local key = OpexProjectAttemptKey(project);
  if (phase == "selected") {
    if (key in EB14_TRACE_SELECTED) return;
    EB14_TRACE_SELECTED.rawset(key, true);
    OpexEB14RailTraceSign("E6|" + p.cargo + "|" + p.eb14Low + "|" + p.eb14High
        + "|" + p.src + "|" + p.dst);
  } else if (phase == "built") {
    OpexEB14RailTraceSign("E5|" + lineId + "|" + p.cargo + "|" + p.eb14Low
        + "|" + p.eb14High + "|" + p.src + "|" + p.dst);
  }
}

function OpexEB14RailTraceSelection(funded)
{
  if (!EB14_PROGRESSIVE || !DECISION_LOG || funded == null) return;
  foreach (rank, project in funded) {
    if (project != null && project.mode == "rail"
        && ("payload" in project) && project.payload != null
        && ("eb14Low" in project.payload)
        && !(OpexProjectAttemptKey(project) in EB14_TRACE_SELECTED))
      OpexEB14RailTraceProject(project, "selected", rank);
  }
}

/* Only new, still live RAIL projects are appended to the current portfolio.
 * The later ordinary PO01C final merge receives the accumulated rail set. */
function OpexEB14RailPublish(owner, s, generated, unit, candidates, stats)
{
  if (owner._projects == null || !("candidateGroups" in owner._projects)) return;
  local live = owner._lines, abandoned = owner._abandonedPairs;
  local ctx = OpexIncrRevalidateIndexContext(live);
  local newProjects = [];
  foreach (candidate in OpexTopK(candidates, TOP_K)) {
    local project = OpexProjectFromCandidate(candidate);
    if (project == null || !OpexCandidateStillValidIndexed(project, live, abandoned, ctx)) continue;
    local key = OpexProjectKeyFor(project);
    if (key in s.eb14Published) continue;
    /* Marquage uniquement pour l'essai causal, jamais pour le banc economique
     * normal EB14 ON (probes=2) : pas de deux allocations par candidat. */
    if (unit.kind != "v233" && DECISION_LOG && DEBUG_SIGNS) {
      candidate.eb14Low <- unit.low;
      candidate.eb14High <- unit.high;
    }
    s.eb14Published.rawset(key, true);
    generated.projects.append(project);
    newProjects.append(project);
    generated.rail.candidates.append(candidate);
  }
  generated.rail.all += candidates.len();
  generated.rail["best"] = OpexTopK(generated.rail.candidates, TOP_K);
  generated.rail.bands = OpexBands(generated.rail.candidates);
  generated.rail.stats = stats;
  if (unit.kind != "pax") generated.freightCargo = unit.cargo;
  if (DECISION_LOG) OpexDecide("EB14_RAIL", "phase=band_done kind=" + unit.kind
      + " cargo=" + unit.cargo + " low=" + unit.low + " high=" + unit.high
      + " examined=" + unit.examined + " in_band=" + unit.inBand
      + " evaluated=" + unit.evaluated + " produced=" + candidates.len()
      + " admitted=" + newProjects.len() + " total=" + generated.projects.len());
  if (DECISION_LOG && DEBUG_SIGNS)
    OpexEB14RailTraceSign("E4|" + unit.cargo + "|" + (unit.kind == "pax" ? "P" : (unit.kind == "v233" ? "V" : "F"))
        + "|" + unit.low + "|" + unit.high + "|" + candidates.len()
        + "|" + newProjects.len());
  if (newProjects.len() == 0) {
    OpexEB14JournalRecordUnit(owner, unit, s.snapshot, candidates.len(), 0);
    return;
  }
  /* The first RAIL project may be published before the final layer merge.
   * Install only the refreshed RAIL fields, and only if nobody has replaced
   * their source since the snapshot. Engines/site contracts then agree. */
  foreach (layer in s.layers) if (layer == "engines.rail") {
    foreach (field in OpexPO01CLayerFields(layer)) {
      if (owner._catalog[field] == s.initial[field])
        owner._catalog[field] = s.catalog[field];
    }
  }
  /* Other modes retain their currently published groups, even if they changed
   * while the generator was suspended. Revalidate again at final selection. */
  local projects = clone owner._projects;
  projects.stats = clone owner._projects.stats;
  local winners = {};
  local scratch = { modeCandidates = 0, modeAlternatives = 0 };
  foreach (key, group in projects.candidateGroups) {
    local groupProjects = typeof group == "array" ? group : [group];
    foreach (project in groupProjects) {
      if (project != null && (project.mode != "rail"
          || OpexCandidateStillValidIndexed(project, live, abandoned, ctx)))
        OpexProjectRememberAll(winners, project, scratch);
    }
  }
  foreach (project in newProjects) OpexProjectRememberAll(winners, project, scratch);
  projects.candidateGroups = winners;
  projects.rail = generated.rail;
  projects.freightCargo = generated.freightCargo;
  OpexProjectsRecountGroups(projects);
  owner._projects = OpexReselectProjects(projects, OpexAvailableCapital(), abandoned, live);
  owner._ranked = owner._projects.rail;
  /* Le journal est diagnostique : aucune bande n'est sautee apres Load
   * tant que ses offres n'ont pas ete reconstituees et reestimees. */
  OpexEB14JournalRecordUnit(owner, unit, s.snapshot,
      candidates.len(), newProjects.len());
}

function OpexEB14GenerateRail(owner, s)
{
  ::OpexSitableCache = {};
  local generated = OpexPO01CEmptyGenerated(s.seed);
  local stats = OpexRailCandidateStats();
  generated.rail = { all = 0, candidates = [], best = [],
      bands = [0, 0, 0, 0], stats = stats, opcodes = 0, profile = null };
  local catalog = clone s.catalog;
  catalog.bounds = clone OpexCatalogBounds(s.catalog);
  catalog.bounds.railMax = OpexMapManhattanSpan();
  s.eb14Catalog <- catalog;
  s.eb14Published <- {};
  local units = OpexEB14RailUnits(s.catalog);
  foreach (index, unit in units) {
    if (DECISION_LOG) OpexPO01CWhere("OpexEB14GenerateRail",
        "rail:" + unit.kind + ":" + unit.low + "-" + unit.high, index);
    local candidates = [];
    if (unit.kind == "v233") {
      local child = OpexPO01CFreightCandidates(s.catalog, s.lines, candidates, stats,
          s.abandoned, null, null, unit.cargo);
      while (child.getstatus() != "dead") { resume child; yield null; }
    } else {
      local child = OpexEB14RailScan(s, unit, candidates, stats);
      while (child.getstatus() != "dead") { resume child; yield null; }
    }
    /* Leave the portfolio writer alone while its other regeneration owns it. */
    while (owner._activeWorker != null && owner._activeWorker.kind == "regen_candidates")
      yield null;
    OpexEB14RailPublish(owner, s, generated, unit, candidates, stats);
    yield null;
  }
  s.outputs.rawset("rail", generated);
  s.seed.freightCargo = generated.freightCargo;
}

function OpexEB14RailFilterLive(generated, lines, abandoned)
{
  local ctx = OpexIncrRevalidateIndexContext(lines);
  local kept = [], candidates = [];
  foreach (project in generated.projects) {
    if (!OpexCandidateStillValidIndexed(project, lines, abandoned, ctx)) continue;
    kept.append(project);
    candidates.append(project.payload);
  }
  generated.projects = kept;
  generated.rail.candidates = candidates;
  generated.rail["best"] = OpexTopK(candidates, TOP_K);
  generated.rail.bands = OpexBands(candidates);
}

function OpexPO01CRoadSoloPaxGenerator(catalog, lines, out, stats, abandonedPairs = null)
{
  if (!ROAD100_SOLO_PAX || ROAD100_SITE_FIRST || catalog == null) return;
  local cargo = catalog.paxCargo;
  if (cargo < 0 || !(cargo in catalog.roadEngineByCargo)) return;
  local towns = catalog.towns;
  local ranked = [];
  local coverage = AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP);
  foreach (i, town in towns) {
    yield null;
    if ((!ROAD1Y_PAX_SITES && OpexTownBusPaxServed(lines, town.id))
        || OpexTownRoadLineCount(lines, town.tile) >= 4) continue;
    if (ROAD1Y_PAX_SITES) {
      foreach (site in OpexBusDistrictSites(town, cargo, coverage))
        ranked.append({ index = i, id = town.id, site = site, captured = site.monthly, totalMonthly = site.monthly });
    } else {
      local monthly = AITown.GetLastMonthProduction(town.id, cargo);
      if (monthly <= 0 && town.pop > 0) monthly = (town.pop * 15) / 100;
      if (monthly <= 0) continue;
      local houses = ("houses" in town && town.houses > 0) ? town.houses : (town.pop / 25);
      if (houses < 1) houses = 1;
      local pct = (10 * 100) / houses;
      if (pct > 86) pct = 86;
      if (pct < 1) pct = 1;
      local captured = (monthly * pct) / 100;
      if (captured < 1) continue;
      ranked.append({ index = i, id = town.id, site = null, captured = captured, totalMonthly = monthly });
    }
  }
  ranked.sort(OpexRoad100SortTownDemand);
  if (ROAD1Y_PAX_SITES && (ROAD1Y_BUS_FIXES & 8) != 0) {
    local diverse = [], counts = {};
    foreach (item in ranked) {
      local count = item.id in counts ? counts[item.id] : 0;
      if (count >= 2) continue;
      counts[item.id] <- count + 1;
      diverse.append(item);
    }
    ranked = diverse;
  }
  local n = ranked.len();
  if (n > 40) n = 40;
  local examined = 0;
  local positive = 0;
  for (local a = 0; a < n; a++) {
    yield null;
    local found = 0;
    for (local b = a + 1; b < n && found < 12; b++) {
      local src = ranked[a];
      local dst = ranked[b];
      if (src.id == dst.id) continue;
      examined++;
      if (C69_BOTTLENECK_PROBE) OpexC73RecordExamined("road", 1);
      local townA = towns[src.index];
      local townB = towns[dst.index];
      local tileA = ROAD1Y_PAX_SITES ? src.site.tile : townA.tile;
      local tileB = ROAD1Y_PAX_SITES ? dst.site.tile : townB.tile;
      if (OpexRoadPairServed(lines, tileA, tileB)) continue;
      local distance = AIMap.DistanceManhattan(tileA, tileB);
      if (ROAD1Y_NEXT > 0 && distance < ROAD1Y_NEXT) continue;
      if (ROAD1Y_PAX_SITES && (ROAD1Y_BUS_FIXES & 4) != 0 && distance < 30) continue;
      if (!OpexRoadDistanceAllowed(catalog, distance, stats)) continue;
      if (abandonedPairs != null) {
        local idA = src.id;
        local idB = dst.id;
        if (idA > idB) { local swapId = idA; idA = idB; idB = swapId; }
        local pairKey = "pax|" + cargo + "|" + idA + "|" + idB;
        if (!ROAD1Y_PAX_SITES && pairKey in abandonedPairs) continue;
      }
      stats.pairsInBand++;
      local monthly = ROAD1Y_PAX_SITES
          ? (src.captured + dst.captured)
          : (ROAD100_INTERCITY_SITE_FLEET ? (src.totalMonthly + dst.totalMonthly) : (src.captured + dst.captured));
      local candidate = OpexMakeRoadCandidate(catalog, "pax", cargo, tileA,
          tileB, src.id, dst.id, distance, monthly, stats, false,
          ROAD100_INTERCITY_SITE_FLEET ? 30 : 0);
      if (candidate != null) {
        if (ROAD1Y_PAX_SITES && src.site != null && dst.site != null) {
          candidate.siteA <- src.site;
          candidate.siteB <- dst.site;
          candidate.road1yBusSite <- true;
          if (abandonedPairs != null && OpexAbandonedPairKey(candidate) in abandonedPairs) continue;
          if (DECISION_LOG) OpexDecide("BUS_DISTRICT_CAND", "town_a=" + src.id
              + " town_b=" + dst.id + " site_a=" + tileA + " site_b=" + tileB
              + " distance=" + distance + " monthly=" + monthly
              + " profit=" + candidate.profitAnnual + " roi=" + candidate.roi);
        }
        if (ROAD100_INTERCITY_SITE_FLEET) {
          candidate.road100FleetCap <- 30;
          candidate.road100IntercitySiteFleet <- true;
        }
        out.append(candidate);
        positive++;
        found++;
      }
    }
  }
  if (DECISION_LOG) {
    OpexDecide("ROAD100_PAX_GEN", "towns=" + n + " examined=" + examined
        + " positive=" + positive + " kept_total=" + out.len());
  }
}

function OpexPO01CRoadTownBusGenerator(catalog, lines, out, stats, abandonedPairs = null)
{
  if (!ROAD100_TOWN_BUS || catalog == null) return;
  local cargo = catalog.paxCargo;
  if (cargo < 0 || !(cargo in catalog.roadEngineByCargo)) return;
  local nTowns = 0;
  local nPositive = 0;
  local nInBand = 0;
  local width = AIMap.GetMapSizeX();
  local height = AIMap.GetMapSizeY();
  foreach (town in catalog.towns) {
    yield null;
    if (OpexTownBusPaxServed(lines, town.id) || OpexTownRoadLineCount(lines, town.tile) >= 4)
      continue;
    local monthly = AITown.GetLastMonthProduction(town.id, cargo);
    if (monthly <= 0 && town.pop > 0) monthly = (town.pop * 15) / 100;
    if (monthly <= 0) continue;
    local houses = ("houses" in town && town.houses > 0) ? town.houses : town.pop / 25;
    if (houses < 1) houses = 1;
    local pct = (20 * 100) / houses;
    if (pct > 86) pct = 86;
    if (pct < 1) pct = 1;
    local captured = (monthly * pct) / 100;
    if (captured < 1) continue;
    local cx = AIMap.GetTileX(town.tile);
    local cy = AIMap.GetTileY(town.tile);
    local ends = null;
    for (local axis = 0; axis < 2 && ends == null; axis++) {
      local ax = cx - (axis == 0 ? 5 : 0);
      local bx = cx + (axis == 0 ? 5 : 0);
      local ay = cy - (axis == 1 ? 5 : 0);
      local by = cy + (axis == 1 ? 5 : 0);
      if (ax < 0 || ay < 0 || bx >= width || by >= height) continue;
      local src = AIMap.GetTileIndex(ax, ay);
      local dst = AIMap.GetTileIndex(bx, by);
      if (AITile.GetClosestTown(src) != town.id || AITile.GetClosestTown(dst) != town.id)
        continue;
      ends = { src = src, dst = dst };
    }
    if (ends == null) continue;
    nTowns++;
    if (OpexRoadPairServed(lines, ends.src, ends.dst)) continue;
    local distance = AIMap.DistanceManhattan(ends.src, ends.dst);
    if (!OpexRoadDistanceAllowed(catalog, distance, stats)) continue;
    nInBand++;
    if (abandonedPairs != null) {
      local pairKey = "pax|" + cargo + "|" + town.id + "|" + town.id;
      if (pairKey in abandonedPairs) continue;
    }
    stats.pairsInBand++;
    if (C69_BOTTLENECK_PROBE) OpexC73RecordExamined("road", 1);
    local candidate = OpexMakeRoadCandidate(catalog, "pax", cargo, ends.src,
        ends.dst, town.id, town.id, distance, captured, stats, false,
        ROAD100_PAX_FLEET_CAP);
    if (candidate != null) {
      if (ROAD100_PAX_FLEET_CAP > 0)
        candidate.road100FleetCap <- ROAD100_PAX_FLEET_CAP;
      out.append(candidate);
      nPositive++;
    }
  }
  if (DECISION_LOG) {
    OpexDecide("ROAD100_TOWN_GEN", "towns=" + nTowns + " in_band=" + nInBand
        + " positive=" + nPositive + " kept_total=" + out.len());
  }
}

function OpexPO01CGenerateMode(owner, s, mode)
{
  if (EB14_PROGRESSIVE && mode == "rail") {
    local progressive = OpexEB14GenerateRail(owner, s);
    while (progressive.getstatus() != "dead") { resume progressive; yield null; }
    return;
  }
  if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", "before_first_yield", -1);
  local generated = OpexPO01CEmptyGenerated(s.seed);
  local all = [];
  local stats = null;
  local iterator = null;
  if (mode == "rail") {
    ::OpexSitableCache = {};
    stats = OpexRailCandidateStats();
    if (!PAX_AIR_FIRST_RAIL_OFF) {
      iterator = OpexPO01CPaxCandidates(s.catalog, s.lines, all, stats, s.abandoned,
          null, null, null, PAX_BAND_ALL, null, -1, s.paxDiagnostics);
      while (iterator.getstatus() != "dead") { resume iterator; yield null; }
    }
    if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", "rail:OpexFreightCargoOrder", -1);
    local cargoOrder = OpexFreightCargoOrder(s.catalog);
    local start = -1;
    for (local i = 0; i < cargoOrder.len(); i++) {
      if (cargoOrder[i] == generated.freightCargo) start = i;
    }
    for (local offset = 0; offset < cargoOrder.len(); offset++) {
      if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", "rail:freight_generator", offset);
      local cargo = cargoOrder[start >= 0 ? (start + offset) % cargoOrder.len() : offset];
      local previousCount = all.len();
      iterator = OpexPO01CFreightCandidates(s.catalog, s.lines, all, stats, s.abandoned,
          null, null, cargo);
      while (iterator.getstatus() != "dead") { resume iterator; yield null; }
      if (all.len() > previousCount) { generated.freightCargo = cargo; break; }
    }
    generated.rail = { all = all.len(), candidates = all,
        best = DECISION_LOG ? OpexPO01CLoggedTopK(all, TOP_K, mode) : OpexTopK(all, TOP_K),
        bands = DECISION_LOG ? OpexPO01CLoggedBands(all) : OpexBands(all), stats = stats, opcodes = 0, profile = null };
  } else if (mode == "road") {
    stats = { pairsInBand = 0, noMonthly = 0, noEngine = 0, townRejected = 0,
        townAcceptancePrefiltered = 0, economicsUnavailable = 0, profitTooLow = 0,
        profitNonPositive = 0, profitBelowFloorKept = 0, accepted = 0,
        roadDistanceShort = 0, roadDistanceLong = 0 };
    if (s.catalog.roadType >= 0) {
      if (ROAD1Y_DIST_BANDS) {
        /* ROAD1Y : meme ordre de bandes que la voie synchrone. La bande est
         * reposee a chaque reprise : un autre generateur peut tourner entre deux. */
        for (local band = 0; band < ROAD1Y_DIST_BAND_LIMITS.len(); band++) {
          local before = all.len();
          ROAD1Y_DIST_BAND = band;
          iterator = OpexPO01CRoadFreightCandidates(s.catalog, s.lines, all, stats, s.abandoned,
              null, generated.freightCargo);
          while (iterator.getstatus() != "dead") {
            ROAD1Y_DIST_BAND = band;
            resume iterator;
            ROAD1Y_DIST_BAND = -1;
            yield null;
          }
          ROAD1Y_DIST_BAND = -1;
          if (all.len() > before) break;
        }
      } else {
        ROAD1Y_DIST_BAND = -1;
        iterator = OpexPO01CRoadFreightCandidates(s.catalog, s.lines, all, stats, s.abandoned,
            null, generated.freightCargo);
        while (iterator.getstatus() != "dead") { resume iterator; yield null; }
      }
      /* ROAD100-7 opt-in : la publication PO01C remplace tous les projets
       * ROAD. Il faut donc inclure les bus site-first dans CE producteur.
       * Le generateur rend la main a chaque paire prefiltree. */
      if (ROAD100_SITE_FIRST) {
        iterator = OpexRoad100SiteFirstGenerator(s.catalog, s.lines, all, stats, s.abandoned);
        while (iterator.getstatus() != "dead") { resume iterator; yield null; }
      }
      if (PFIX_PO01C_ROAD_PAX) {
        if (ROAD100_SOLO_PAX && !ROAD100_SITE_FIRST) {
          iterator = OpexPO01CRoadSoloPaxGenerator(s.catalog, s.lines, all, stats, s.abandoned);
          while (iterator.getstatus() != "dead") { resume iterator; yield null; }
        }
        if (ROAD100_TOWN_BUS) {
          iterator = OpexPO01CRoadTownBusGenerator(s.catalog, s.lines, all, stats, s.abandoned);
          while (iterator.getstatus() != "dead") { resume iterator; yield null; }
        }
      }
      /* ROAD100-27 : le MEME iterateur cote sync et PO01C. Le cout
       * unitaire du preflight reste atomique ; yield entre couples. */
      if (ROAD100_MAIL_INTERTOWN) {
        iterator = OpexRoad100MailIntertownGenerator(
            s.catalog, s.lines, all, stats, s.abandoned);
        while (iterator.getstatus() != "dead") { resume iterator; yield null; }
      }
      /* ROAD100-29: meme generateur passif que la voie synchrone.
       * Ne publie aucun candidat et rend la main entre paires/sources. */
      if (ROAD100_PAX_INTERCITY_ROOTS) {
        iterator = OpexRoad100PaxRootsShadowGenerator(s.catalog);
        while (iterator.getstatus() != "dead") { resume iterator; yield null; }
      }
    }
    generated.road = { all = all.len(), candidates = all,
        best = DECISION_LOG ? OpexPO01CLoggedTopK(all, ROAD_TOP_K, mode) : OpexTopK(all, ROAD_TOP_K),
        stats = stats, opcodes = 0, profile = null };
    if (MULTI1_ROAD_CARGO_SHADOW == 1)
      OpexMulti1RoadCargoShadowArm(s.catalog, s.lines, s.abandoned, generated.freightCargo, all);
  } else if (mode == "water") {
    iterator = OpexPO01CWaterPlans(s.catalog, s.lines, generated.waterPlans);
    while (iterator.getstatus() != "dead") { resume iterator; yield null; }
    generated.waterPlan = generated.waterPlans.len() > 0 ? generated.waterPlans[0] : null;
    foreach (plan in generated.waterPlans) {
      yield null;
      local project = OpexProjectFromWater(s.catalog, plan, 0);
      if (project != null) generated.projects.append(project);
    }
  }
  foreach (candidateIndex, candidate in all) {
    yield null;
    if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", mode + ":project_filter", candidateIndex);
    if (OpexAbandonedPairKey(candidate) in s.abandoned) continue;
    if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", mode + ":OpexProjectFromCandidate", candidateIndex);
    local project = OpexProjectFromCandidate(candidate);
    if (project != null) generated.projects.append(project);
  }
  s.outputs.rawset(mode, generated);
  if (mode == "rail") s.seed.freightCargo = generated.freightCargo;
  if (DECISION_LOG) OpexPO01CWhere("OpexPO01CGenerateMode", "after_last_yield", -1);
}

/* AIR keeps its existing cursor protocol; nested generators only split the
 * atomic site/hub scans within each call. Null results use a separate box. */
function OpexPO01CGenerateAir(s)
{
  local best = null;
  while (!("done" in s.airCursor) || !s.airCursor.done) {
    local result = { value = null };
    local iterator = OpexPO01CAirPlans(result, s.catalog, s.lines, 0, s.airPlans,
        s.abandoned, PAX_BAND_ALL, -1, s.airCursor, PO01C_SLICE_OPS,
        AIController.GetTick() + 5);
    while (iterator.getstatus() != "dead") {
      /* Other AIR planners can run between checkpoints. Restore the same
       * cursor-owned C121 state that Prepare binds on synchronous entry. */
      if ("c121PlanPerf" in s.airCursor) C121_AIR_PLAN_PERF = s.airCursor.c121PlanPerf;
      if ("c121EndpointCache" in s.airCursor) C121_AIR_ENDPOINT_CACHE = s.airCursor.c121EndpointCache;
      resume iterator;
      yield null; // PO01C_CHECKPOINT
    }
    best = result.value;
  }
  local generated = OpexPO01CEmptyGenerated(s.seed);
  generated.airPlans = s.airPlans;
  generated.airPlan = best;
  foreach (plan in s.airPlans) {
    yield null; // PO01C_CHECKPOINT
    local project = OpexProjectFromAir(s.catalog, plan, 0);
    if (project != null) generated.projects.append(project);
  }
  s.outputs.rawset("air", generated);
}

function OpexPO01CCopyLines(lines)
{
  local copied = [];
  foreach (line in lines) {
    local record = clone line;
    if (("vehicles" in record) && record.vehicles != null) record.vehicles = clone record.vehicles;
    foreach (key in ["platformA", "platformB"])
      if ((key in record) && record[key] != null) record[key] = clone record[key];
    copied.append(record);
  }
  return copied;
}

/* Conservative topology records, not a lossy hash. Unknown baseline rebuilds.
 * AIR vehicle counts are retained for its hub/capacity guards. */
function OpexPO01CLineState(lines)
{
  local state = { rail = "", road = "", air = "", water = "", airRail = "" };
  foreach (line in lines) {
    local mode = ("mode" in line) ? line.mode : "rail";
    if (!(mode in state)) continue;
    local record = "|";
    foreach (key in ["lineId", "originA", "originB", "stationA", "stationB",
        "cargo", "srcTown", "dstTown", "scrapping", "deadStreak", "platformLength"])
      record += key + "=" + ((key in line) ? line[key].tostring() : "-") + ";";
    if (mode == "air" && ("vehicles" in line) && line.vehicles != null)
      record += "vehicles=" + line.vehicles.len();
    foreach (key in ["platformA", "platformB"]) {
      if (!(key in line) || line[key] == null) continue;
      foreach (field in ["direction", "length", "anchor", "step"])
        if (field in line[key]) record += key + "." + field + "=" + line[key][field] + ";";
    }
    state[mode] += record;
    if (mode == "air") state.airRail += "|" + line.originA + "," + line.originB
        + "," + (("scrapping" in line) && line.scrapping ? 1 : 0);
  }
  return state;
}

function OpexPO01CLinesAffect(owner, state, mode)
{
  local old = owner._po01cLineState;
  if (old == null || mode == "fleet") return true;
  if (mode == "road") return old.rail != state.rail || old.road != state.road;
  if (mode == "rail") return old.rail != state.rail
      || ((V275_RAIL_PAX_MM & 1) && old.airRail != state.airRail);
  return old[mode] != state[mode];
}

function OpexPO01CAirPending(owner)
{
  foreach (task in owner._taskQueue)
    if (task.name == "catalog" && ("c78AirRebuild" in task)
        && task.c78AirRebuild != null) return true;
  return false;
}

function OpexPO01CLayerFields(layer)
{
  if (layer == "towns") return ["towns", "townAcceptors"];
  if (layer == "industries") return ["industries", "producers", "acceptors"];
  if (layer == "engines.rail") return ["railType", "loco", "railLocos", "wagonByCargo",
      "locoByCargoWagons", "locoByCargoWagonsDist", "wagonChoicesByCargo", "platformLength", "maxTrainLength",
      "railCoverage", "freightTrainMultiplier", "costTrackPerTile", "costStation",
      "costRailDepot", "costRailSignal"];
  if (layer == "engines.road") return ["roadType", "roadEngineByCargo",
      "roadEngineChoicesByCargo", "maxRoadVehiclePrice", "costRoadPerTile",
      "costRoadBusStop", "costRoadTruckStop", "costRoadDepot"];
  if (layer == "engines.water") return ["ships", "maxShipPrice", "costDock", "costWaterDepot"];
  if (layer == "engines.air") return ["airport", "plane", "airCombos", "airPlaneChoicesByAirport"];
  return [];
}

function OpexPO01CLayerIterator(catalog, layer)
{
  if (layer == "towns") return OpexPO01CTowns(catalog);
  if (layer == "industries") return OpexPO01CIndustries(catalog);
  if (layer == "engines.rail") return OpexPO01CRail(catalog);
  if (layer == "engines.road") return OpexPO01CRoad(catalog);
  if (layer == "engines.air") return OpexPO01CAir(catalog);
  if (layer == "engines.water") return OpexPO01CWater(catalog);
  return null;
}

function OpexPO01CConsumed(owner, mode, layer)
{
  if (!(mode in owner._c76ModeConsumed)) return 0;
  local consumed = owner._c76ModeConsumed[mode];
  return layer in consumed ? consumed[layer] : 0;
}

/* Capture before any producer; defer only AIR, never the land/water lot.
 * C78 retains ownership of AIR while in flight. Its own AC06 publication will
 * cover AIR's revisions; no timeout fallback and no synchronous reconstruction. */
function OpexPO01CStart(owner)
{
  if (PO02_INDEPENDENT_EXPIRY >= 2) return OpexPO02Start(owner);
  local snapshot = OpexAC06CaptureRevisionNumbers(owner);
  local state = OpexPO01CLineState(owner._lines);
  local modes = [], coveredModes = [], layers = [], dirty = {};
  local airPending = OpexPO01CAirPending(owner);
  foreach (mode in ["rail", "road", "water", "fleet", "air"]) {
    local needed = false;
    foreach (layer in owner._c76GetModeDeps(mode)) {
      if (OpexAC06SnapshotLayer(snapshot, layer) <= OpexPO01CConsumed(owner, mode, layer)) continue;
      if (layer == "lines" && !OpexPO01CLinesAffect(owner, state, mode)) continue;
      needed = true;
    }
    if (needed && mode == "air" && airPending) continue;
    if (PO02_INDEPENDENT_EXPIRY && !needed && OpexPO01CModeEnabled(mode)
        && !(mode == "air" && airPending)) {
      local now = AIDate.GetCurrentDate();
      local lastPub = (mode in PO02_LAST_PUBLISH_DATE) ? PO02_LAST_PUBLISH_DATE[mode] : 0;
      local ttl = (mode == "water") ? 90 : 30;
      if (lastPub == 0) {
        PO02_LAST_PUBLISH_DATE[mode] = now;
      } else if (now - lastPub >= ttl) {
        needed = true;
      }
    }
    coveredModes.append(mode);
    if (!needed || !OpexPO01CModeEnabled(mode)) continue;
    modes.append(mode);
    foreach (layer in owner._c76GetModeDeps(mode)) {
      if (layer != "lines" && OpexAC06SnapshotLayer(snapshot, layer)
          > OpexPO01CConsumed(owner, mode, layer)) dirty.rawset(layer, true);
    }
  }
  /* EB-3 : le bootstrap AIR peut durer presque toute l'annee. Pendant ce
   * temps, explorer uniquement le RAIL demande par EB-14, sans acquitter les
   * autres familles ni appliquer leur catalogue partiellement initialise. */
  if (EB3_RAIL_FIRST_YEAR_PREFETCH && STAGED_BOOTSTRAP
      && owner._generationStage < OPEX_STAGE_COMPLETE) {
    local railDirty = false;
    foreach (mode in modes) if (mode == "rail") railDirty = true;
    if (!railDirty) return null;
    modes = ["rail"];
    coveredModes = ["rail"];
    dirty = {};
    foreach (layer in owner._c76GetModeDeps("rail")) {
      if (layer == "lines") continue;
      if (OpexAC06SnapshotLayer(snapshot, layer)
          > OpexPO01CConsumed(owner, "rail", layer)) dirty.rawset(layer, true);
    }
  }
  if (modes.len() == 0) return null;
  foreach (layer in ["engines.rail", "towns", "industries", "engines.air", "engines.water", "engines.road"])
    if (layer in dirty) layers.append(layer);
  local catalog = clone owner._catalog;
  catalog.bounds = clone OpexCatalogBounds(catalog);
  local initial = {};
  foreach (layer in layers) foreach (field in OpexPO01CLayerFields(layer))
    initial.rawset(field, owner._catalog[field]);
  return { snapshot = snapshot, modes = modes, coveredModes = coveredModes, layers = layers,
      lineState = state, initial = initial, layerCursor = 0, modeCursor = 0,
      iterator = null, outputs = {}, catalog = catalog,
      seed = { freightCargo = owner._projects.freightCargo },
      lines = OpexPO01CCopyLines(owner._lines), abandoned = clone owner._abandonedPairs,
      airCursor = {}, airPlans = [], modeOps = {}, totalOps = 0, slices = 0, maxDays = 0,
      paxDiagnostics = DECISION_LOG ? { coverRebuilds = 0, sitableFills = 0 } : null,
      startTick = AIController.GetTick(), startDate = AIDate.GetCurrentDate() };
}

/* PO-02b: separate opt-in path. The historical mode 0/1 loops stay intact. */
function OpexPO02Cause(now, lastPub, since, fresh, onlyLines, count)
{
  if (!onlyLines || count == 0 || lastPub <= 0 || now < lastPub || since > now) return "dirty";
  if (since > 0 && now - since >= PO02_MAX_DEFER) return "forced_max";
  if (now - lastPub >= fresh) return "ttl";
  return "deferred";
}

function OpexPO02Members(projects, mode)
{
  local members = {};
  if (projects == null || !("candidateGroups" in projects) || projects.candidateGroups == null) return members;
  foreach (key, entry in projects.candidateGroups) {
    local list = typeof entry == "array" ? entry : [entry];
    foreach (project in list)
      if (project != null && project.mode == mode) members.rawset(project, true);
  }
  return members;
}

/* Publication clears only reports for modes whose output actually completed. */
function OpexPO02Published(modes)
{
  foreach (mode in modes) {
    if (mode in PO02_DEFER_SINCE) PO02_DEFER_SINCE[mode] = 0;
  }
  PO02_RETRY = null;
}

function OpexPO02DeferDue(mode, now)
{
  local since = (mode in PO02_DEFER_SINCE) ? PO02_DEFER_SINCE[mode] : 0;
  local lastPub = (mode in PO02_LAST_PUBLISH_DATE) ? PO02_LAST_PUBLISH_DATE[mode] : 0;
  if (since <= 0 || lastPub <= 0 || now < lastPub || since > now || !(mode in PO02_MIN_FRESH)) return 0;
  local due = lastPub + PO02_MIN_FRESH[mode];
  if (since + PO02_MAX_DEFER < due) due = since + PO02_MAX_DEFER;
  return due;
}

function OpexPO02AnyDeferDue()
{
  local now = AIDate.GetCurrentDate();
  foreach (mode in ["road", "water", "fleet"]) {
    if (!OpexPO01CModeEnabled(mode)) continue;
    if (PO02_DEFER_SINCE[mode] <= 0) continue;
    local due = OpexPO02DeferDue(mode, now);
    if (due <= 0 || now >= due) return true;
  }
  return false;
}

/* Mode 3 only: true when the unacknowledged lines revision belongs solely to
 * actively deferred modes (not yet due), preventing spurious _dispatchCatalog
 * C78/full rebuilds and _po01cPending stalls during the deferral window. */
function OpexPO02LinesDeferredOnly(owner)
{
  local now = AIDate.GetCurrentDate();
  local hasDeferred = false;
  foreach (mode in ["road", "water", "fleet"]) {
    if (!OpexPO01CModeEnabled(mode)) continue;
    if (PO02_DEFER_SINCE[mode] <= 0) continue;
    local due = OpexPO02DeferDue(mode, now);
    if (due <= 0 || now >= due) return false;
    hasDeferred = true;
  }
  if (!hasDeferred) return false;
  if (PO02_RETRY != null && now < PO02_RETRY.until
      && owner._projects != null && PO02_RETRY.projects == owner._projects
      && PO02_RETRY.groups == owner._projects.candidateGroups
      && PO02_RETRY.airPending == OpexPO01CAirPending(owner)) {
    local snapshot = OpexAC06CaptureRevisionNumbers(owner);
    local same = true;
    foreach (key, revision in snapshot)
      if (PO02_RETRY.snapshot[key] != revision) same = false;
    if (same) return true;
  }
  local linesRev = owner._c76Revisions.lines;
  foreach (mode in ["air", "rail", "road", "water", "fleet"]) {
    if (!OpexPO01CModeEnabled(mode)) continue;
    if (OpexPO01CConsumed(owner, mode, "lines") >= linesRev) continue;
    if (!(mode in PO02_DEFER_SINCE) || PO02_DEFER_SINCE[mode] <= 0) return false;
  }
  return true;
}

function OpexPO02Log(owner, s, phase)
{
  if (!DECISION_LOG) return;
  foreach (mode, d in s.po02Decisions) {
    // C78 may have taken AIR ownership after Start; it is not our publication.
    if (mode == "air" && OpexPO01CAirPending(owner)) continue;
    local after = OpexPO02Members(owner._projects, mode);
    local retained = 0;
    foreach (project, unused in d.before) if (project in after) retained++;
    OpexDecide("PO02_DECISION", "setting=" + PO02_INDEPENDENT_EXPIRY
        + " batch=" + s.startTick + " phase=" + phase + " mode=" + mode
        + " cause=" + d.cause + " age=" + d.age + " layers=" + d.layers
        + " deferSince=" + d.deferSince
        + " defer_days=" + (d.deferSince > 0 ? AIDate.GetCurrentDate() - d.deferSince : 0)
        + " ops_mode=" + (mode in s.modeOps ? s.modeOps[mode] : 0)
        + " candidats_avant=" + d.before.len() + " publies=" + (after.len() - retained)
        + " evinces=" + (d.before.len() - retained) + " retained=" + retained);
  }
}

function OpexPO02Start(owner)
{
  local snapshot = OpexAC06CaptureRevisionNumbers(owner);
  local now = AIDate.GetCurrentDate();
  if (PO02_RETRY != null && now < PO02_RETRY.until && PO02_RETRY.projects == owner._projects
      && PO02_RETRY.groups == owner._projects.candidateGroups
      && PO02_RETRY.airPending == OpexPO01CAirPending(owner)) {
    local same = true;
    foreach (key, revision in snapshot)
      if (PO02_RETRY.snapshot[key] != revision) same = false;
    if (same) return null;
  }
  PO02_RETRY = null;
  local decisions = {}, retryDate = now + PO02_MAX_DEFER;
  local state = OpexPO01CLineState(owner._lines);
  local modes = [], coveredModes = [], layers = [], dirty = {};
  local airPending = OpexPO01CAirPending(owner);
  local railOnly = EB3_RAIL_FIRST_YEAR_PREFETCH && STAGED_BOOTSTRAP
      && owner._generationStage < OPEX_STAGE_COMPLETE;
  foreach (mode in ["rail", "road", "water", "fleet", "air"]) {
    // Bootstrap must not create reports for modes excluded from this lot.
    if (railOnly && mode != "rail") continue;
    local needed = false;
    local onlyLines = true, reasonLayers = "";
    local outstanding = (mode in PO02_DEFER_SINCE) && PO02_DEFER_SINCE[mode] > 0;
    foreach (layer in owner._c76GetModeDeps(mode)) {
      if (OpexAC06SnapshotLayer(snapshot, layer) <= OpexPO01CConsumed(owner, mode, layer)) continue;
      // RAIL can publish its shared signature while ROAD remains deferred.
      // Do not acknowledge that outstanding ROAD revision without producing it.
      if (layer == "lines" && !outstanding && !OpexPO01CLinesAffect(owner, state, mode)) continue;
      needed = true;
      if (layer != "lines") onlyLines = false;
      reasonLayers += (reasonLayers == "" ? "" : ",") + layer;
    }
    if (outstanding && !needed) PO02_DEFER_SINCE[mode] = 0;
    if (needed && mode == "air" && airPending) continue;
    // Observe other selected modes without changing their historical cadence.
    if (DECISION_LOG && needed && OpexPO01CModeEnabled(mode) && !(mode in PO02_MIN_FRESH)) {
      local lastPub = PO02_LAST_PUBLISH_DATE[mode];
      decisions.rawset(mode, { cause = "dirty", age = lastPub > 0 ? now - lastPub : -1,
          layers = reasonLayers, deferSince = 0, before = OpexPO02Members(owner._projects, mode) });
    }
    if (needed && OpexPO01CModeEnabled(mode) && (mode in PO02_MIN_FRESH)) {
      local lastPub = PO02_LAST_PUBLISH_DATE[mode];
      local age = lastPub > 0 ? now - lastPub : -1;
      local since = PO02_DEFER_SINCE[mode];
      local members = OpexPO02Members(owner._projects, mode);
      local cause = OpexPO02Cause(now, lastPub, since, PO02_MIN_FRESH[mode],
          onlyLines, members.len());
      local deferred = cause == "deferred";
      if (deferred && since == 0) since = now;
      if (DECISION_LOG) decisions.rawset(mode, { cause = cause, age = age,
          layers = reasonLayers, deferSince = since, before = members });
      if (deferred && PO02_INDEPENDENT_EXPIRY == 3) {
        PO02_DEFER_SINCE[mode] = since;
        local due = lastPub + PO02_MIN_FRESH[mode];
        if (since + PO02_MAX_DEFER < due) due = since + PO02_MAX_DEFER;
        if (due < retryDate) retryDate = due;
        // Neither merge nor acknowledge this mode, including its aliases.
        continue;
      }
    }
    coveredModes.append(mode);
    if (!needed || !OpexPO01CModeEnabled(mode)) continue;
    modes.append(mode);
    foreach (layer in owner._c76GetModeDeps(mode)) {
      if (layer != "lines" && OpexAC06SnapshotLayer(snapshot, layer)
          > OpexPO01CConsumed(owner, mode, layer)) dirty.rawset(layer, true);
    }
  }
  /* EB-3 : le bootstrap AIR peut durer presque toute l'annee. Pendant ce
   * temps, explorer uniquement le RAIL demande par EB-14, sans acquitter les
   * autres familles ni appliquer leur catalogue partiellement initialise. */
  if (EB3_RAIL_FIRST_YEAR_PREFETCH && STAGED_BOOTSTRAP
      && owner._generationStage < OPEX_STAGE_COMPLETE) {
    local railDirty = false;
    foreach (mode in modes) if (mode == "rail") railDirty = true;
    if (!railDirty) return null;
    modes = ["rail"];
    coveredModes = ["rail"];
    dirty = {};
    foreach (layer in owner._c76GetModeDeps("rail")) {
      if (layer == "lines") continue;
      if (OpexAC06SnapshotLayer(snapshot, layer)
          > OpexPO01CConsumed(owner, "rail", layer)) dirty.rawset(layer, true);
    }
  }
  if (modes.len() == 0) {
    if (PO02_INDEPENDENT_EXPIRY == 3) {
      PO02_RETRY = { snapshot = snapshot, until = retryDate, projects = owner._projects,
          groups = owner._projects.candidateGroups,
          airPending = airPending };
      if (DECISION_LOG) OpexPO02Log(owner, { po02Decisions = decisions,
          modeOps = {}, startTick = AIController.GetTick() }, "deferred_only");
    }
    return null;
  }
  foreach (layer in ["engines.rail", "towns", "industries", "engines.air", "engines.water", "engines.road"])
    if (layer in dirty) layers.append(layer);
  local catalog = clone owner._catalog;
  catalog.bounds = clone OpexCatalogBounds(catalog);
  local initial = {};
  foreach (layer in layers) foreach (field in OpexPO01CLayerFields(layer))
    initial.rawset(field, owner._catalog[field]);
  return { po02Decisions = decisions, snapshot = snapshot, modes = modes, coveredModes = coveredModes, layers = layers,
      lineState = state, initial = initial, layerCursor = 0, modeCursor = 0,
      iterator = null, outputs = {}, catalog = catalog,
      seed = { freightCargo = owner._projects.freightCargo },
      lines = OpexPO01CCopyLines(owner._lines), abandoned = clone owner._abandonedPairs,
      airCursor = {}, airPlans = [], modeOps = {}, totalOps = 0, slices = 0, maxDays = 0,
      paxDiagnostics = DECISION_LOG ? { coverRebuilds = 0, sitableFills = 0 } : null,
      startTick = AIController.GetTick(), startDate = AIDate.GetCurrentDate() };
}

function OpexPO01CAcknowledge(owner, s)
{
  foreach (mode in s.coveredModes) {
    local aliases = [mode];
    if (mode == "rail" || mode == "road") {
      aliases.append(mode + "_pax"); aliases.append(mode + "_freight");
    }
    foreach (alias in aliases) {
      if (!(alias in owner._c76ModeConsumed)) owner._c76ModeConsumed.rawset(alias, {});
      local consumed = owner._c76ModeConsumed[alias];
      local sumRev = 0;
      foreach (layer in owner._c76GetModeDeps(alias)) {
        local covered = OpexAC06SnapshotLayer(s.snapshot, layer);
        local old = layer in consumed ? consumed[layer] : 0;
        consumed.rawset(layer, covered > old ? covered : old);
        sumRev += consumed[layer];
      }
      owner._c76ModeConsumedRevision.rawset(alias, sumRev);
    }
  }
  if (PO02_INDEPENDENT_EXPIRY >= 2) OpexPO02Published(s.modes);
  /* A shared revision is acknowledged only after EVERY consumer covers it.
   * Never read current revisions here (AC06 v2). */
  if (PO02_INDEPENDENT_EXPIRY) {
    local now = AIDate.GetCurrentDate();
    foreach (mode in s.modes) {
      if (mode in PO02_LAST_PUBLISH_DATE) PO02_LAST_PUBLISH_DATE[mode] = now;
    }
  }
  foreach (layer in ["towns", "industries", "lines", "engines.rail", "engines.road", "engines.air", "engines.water"]) {
    local covered = OpexAC06SnapshotLayer(s.snapshot, layer);
    foreach (mode in ["air", "rail", "road", "water", "fleet"]) {
      if (!OpexPO01CModeEnabled(mode)) continue;
      foreach (dep in owner._c76GetModeDeps(mode)) if (dep == layer) {
        local consumed = OpexPO01CConsumed(owner, mode, layer);
        if (consumed < covered) covered = consumed;
      }
    }
    local ack = owner._c76AckRevisions;
    if (layer == "towns" || layer == "industries" || layer == "lines") {
      if (covered > ack[layer]) ack[layer] = covered;
    } else {
      local mode = layer.slice(8);
      if (covered > ack.engines[mode]) ack.engines[mode] = covered;
    }
  }
  /* Do not erase AIR's baseline when that mode was deferred. */
  if (owner._po01cLineState == null) owner._po01cLineState = { rail = "?", road = "?", air = "?", water = "?", airRail = "?" };
  foreach (mode in s.coveredModes) if (mode != "fleet") {
    owner._po01cLineState[mode] = s.lineState[mode];
    if (mode == "rail") owner._po01cLineState.airRail = s.lineState.airRail;
  }
}

function OpexPO01CPublish(owner, s)
{
  /* C78 can start even after our final AIR slice. It keeps write ownership. */
  if (OpexPO01CAirPending(owner)) {
    for (local i = s.modes.len() - 1; i >= 0; i--)
      if (s.modes[i] == "air") s.modes.remove(i);
    for (local i = s.coveredModes.len() - 1; i >= 0; i--)
      if (s.coveredModes[i] == "air") s.coveredModes.remove(i);
  }
  /* Merge into the LATEST portfolio. Other modes and special alternatives
   * remain owned by their current producers. No catalogue object replacement. */
  local projects = clone owner._projects;
  projects.stats = clone owner._projects.stats;
  foreach (mode in s.modes) {
    if (mode == "fleet") {
      local po02FleetMark = PO02_INDEPENDENT_EXPIRY >= 2 ? OpexOpsMeasureBegin() : null;
      local fleet = [];
      local fleetMark = DECISION_LOG ? OpexOpsMeasureBegin() : null;
      owner._resizeAirFleets(AIDate.GetYear(AIDate.GetCurrentDate()), fleet);
      if (DECISION_LOG) OpexPO01CUnitEnd(fleetMark, "publish", "fleet", "OpexPO01CPublish", "resizeAirFleets");
      local generated = { projects = [] };
      foreach (entry in fleet) {
        local project = OpexProjectFromFleet(entry);
        if (project != null) generated.projects.append(project);
      }
      OpexPO01CMerge(projects, generated, "fleet");
      if (PO02_INDEPENDENT_EXPIRY >= 2) s.modeOps.rawset("fleet",
          ("fleet" in s.modeOps ? s.modeOps.fleet : 0) + OpexOpsMeasureEnd(po02FleetMark));
    } else if (mode in s.outputs) {
      if (EB14_PROGRESSIVE && mode == "rail")
        OpexEB14RailFilterLive(s.outputs[mode], owner._lines, owner._abandonedPairs);
      OpexPO01CMerge(projects, s.outputs[mode], mode);
    }
  }
  local selectionMark = DECISION_LOG ? OpexOpsMeasureBegin() : null;
  owner._projects = OpexReselectProjects(projects, OpexAvailableCapital(), owner._abandonedPairs, owner._lines);
  if (DECISION_LOG) OpexPO01CUnitEnd(selectionMark, "publish", "all", "OpexPO01CPublish", "OpexReselectProjects");
  owner._ranked = owner._projects.rail;
  foreach (layer in s.layers) {
    if (layer == "engines.air" && OpexPO01CAirPending(owner)) continue;
    foreach (field in OpexPO01CLayerFields(layer)) {
      /* A concurrent refresh wins over our older copy. */
      if (owner._catalog[field] == s.initial[field]) owner._catalog[field] = s.catalog[field];
    }
  }
  if (PO02_INDEPENDENT_EXPIRY >= 2 && DECISION_LOG) OpexPO02Log(owner, s, "publish");
  OpexPO01CAcknowledge(owner, s);
}

/* Same merge as OpexApplyGeneratedModeProjects, with ONE final selection for
 * the whole lot. Calling that helper per mode would repeat the costly filter. */
function OpexPO01CMerge(projects, generated, mode)
{
  local winners = {};
  local scratch = { modeCandidates = 0, modeAlternatives = 0 };
  foreach (key, entry in projects.candidateGroups) {
    local list = typeof entry == "array" ? entry : [entry];
    foreach (project in list) {
      if (project != null && (project.mode != mode
          || (mode != "fleet" && OpexProjectIsPersistentSpecial(project))))
        OpexProjectRememberAll(winners, project, scratch);
    }
  }
  foreach (project in generated.projects) OpexProjectRememberAll(winners, project, scratch);
  projects.candidateGroups = winners;
  if (mode == "rail") { projects.rail = generated.rail; projects.freightCargo = generated.freightCargo; }
  else if (mode == "road") { projects.road = generated.road; projects.freightCargo = generated.freightCargo; }
  else if (mode == "water") { projects.waterPlan = generated.waterPlan; projects.waterPlans = generated.waterPlans; }
  else if (mode == "air") { projects.airPlan = generated.airPlan; projects.airPlans = generated.airPlans; }
  OpexProjectsRecountGroups(projects);
}

function OpexPO01CLog(owner, s, phase)
{
  if (!DECISION_LOG) return;
  local modes = "", layers = "";
  foreach (mode in s.modes) modes += (modes == "" ? "" : ",") + mode;
  foreach (layer in s.layers) layers += (layers == "" ? "" : ",") + layer;
  local a = owner._c76AckRevisions;
  OpexDecide("PO01C_BATCH", "phase=" + phase + " modes=" + modes + " layers=" + layers
      + " ops=" + s.totalOps + " slices=" + s.slices + " ticks=" + (AIController.GetTick() - s.startTick)
      + " days=" + (AIDate.GetCurrentDate() - s.startDate) + " max_slice_days=" + s.maxDays
      + " cover_rebuilds=" + (s.paxDiagnostics != null ? s.paxDiagnostics.coverRebuilds : 0)
      + " sitable_fills=" + (s.paxDiagnostics != null ? s.paxDiagnostics.sitableFills : 0)
      + " ack_towns=" + a.towns + " ack_industries=" + a.industries + " ack_lines=" + a.lines
      + " ack_air=" + a.engines.air + " ack_rail=" + a.engines.rail
      + " ack_road=" + a.engines.road + " ack_water=" + a.engines.water);
  if (phase == "begin") OpexDecide("PO01C_SNAPSHOT", "towns=" + s.snapshot.towns
      + " industries=" + s.snapshot.industries + " lines=" + s.snapshot.lines
      + " air=" + s.snapshot.engines_air + " rail=" + s.snapshot.engines_rail
      + " road=" + s.snapshot.engines_road + " water=" + s.snapshot.engines_water);
}

function OpexPO02AnyModeExpired(owner)
{
  if (PO02_INDEPENDENT_EXPIRY == 3) return OpexPO02AnyDeferDue();
  if (PO02_INDEPENDENT_EXPIRY >= 2) return false;
  if (!PO02_INDEPENDENT_EXPIRY) return false;
  local now = AIDate.GetCurrentDate();
  local airPending = OpexPO01CAirPending(owner);
  foreach (mode in ["rail", "road", "water", "fleet", "air"]) {
    if (!OpexPO01CModeEnabled(mode)) continue;
    if (mode == "air" && airPending) continue;
    local lastPub = (mode in PO02_LAST_PUBLISH_DATE) ? PO02_LAST_PUBLISH_DATE[mode] : 0;
    local ttl = (mode == "water") ? 90 : 30;
    if (lastPub > 0 && now - lastPub >= ttl) return true;
  }
  return false;
}

function OpexPO01CStep(owner)
{
  local tick = AIController.GetTick();
  if (tick == owner._po01cLastTick || AIController.GetOpsTillSuspend() < 4000) return false;
  /* EB-14 : ne pas attendre la fin du scan C78 (jusqu'a un an observe en 3x3),
   * qui retardait tout premier train de 1971 a 1972. La premiere construction
   * AIR doit deja exister avant qu'une tranche RAIL puisse concourir.
   * Tant que l'annee de demarrage n'est pas achevee, C78 garde toutes les
   * tranches pour ne pas devier la flotte AIR (canary juillet 1970 : perte).
   * A partir de l'annee suivante, un seul tick sur 16 peut donner 40k
   * opcodes a PO01C. Les autres
   * 15 ticks privilegient strictement AIR : aucun rail ne peut prendre en
   * boucle toutes les tranches C78, a la difference de V149. Cette borne
   * est experimentale ; compter et comparer les ticks/opcodes en smoke. */
  if (EB14_PROGRESSIVE && OpexPO01CAirPending(owner)) {
    if (!owner._airBuilt) return false;
    if (EB3_RAIL_FIRST_YEAR_PREFETCH
        && AIDate.GetYear(AIDate.GetCurrentDate()) == owner._startYear) {
      /* Un pas tous les 64 ticks pour preserver le scan AIR 1970. Le RAIL
       * decouvert est mis en cache ; C121 interdit encore son financement. */
      if ((tick % 64) != 0) return false;
    } else if (AIDate.GetYear(AIDate.GetCurrentDate()) <= owner._startYear
        || (tick % 16) != 0) return false;
  }
  owner._po01cLastTick = tick;
  if (owner._c76ForceReloadRegen || owner._portfolioInvalidated) {
    if (owner._po01cJob != null) owner._po01cPending = true;
    owner._po01cJob = null;
    return false;
  }
  if (owner._projects == null || owner._catalog == null || owner._c76Revisions == null
      || owner._c76AckRevisions == null || (STAGED_BOOTSTRAP && owner._generationStage < OPEX_STAGE_COMPLETE
          && !(EB3_RAIL_FIRST_YEAR_PREFETCH && owner._airBuilt
              && AIDate.GetYear(AIDate.GetCurrentDate()) == owner._startYear))) return false;
  if (owner._po01cJob == null) {
    local po02Expired = PO02_INDEPENDENT_EXPIRY && OpexPO02AnyModeExpired(owner);
    if (!owner._po01cPending && !po02Expired) return false;
    owner._po01cJob = OpexPO01CStart(owner);
    if (owner._po01cJob == null) {
      owner._po01cPending = owner._c76AnyLayerChanged();
      return false;
    }
    owner._po01cPending = false;
    OpexPO01CLog(owner, owner._po01cJob, "begin");
    return true;
  }
  local s = owner._po01cJob;
  local mark = OpexOpsMeasureBegin();
  local date = AIDate.GetCurrentDate();
  local phase = "layer";
  local unit = s.modeCursor < s.modes.len() ? s.modes[s.modeCursor] : "none";
  if (s.layerCursor < s.layers.len()) {
    unit = s.layers[s.layerCursor];
    if (s.iterator == null) s.iterator = OpexPO01CLayerIterator(s.catalog, s.layers[s.layerCursor]);
  } else if (s.modeCursor < s.modes.len()) {
    phase = "mode";
    local mode = s.modes[s.modeCursor];
    if (mode == "fleet") { s.modeCursor++; }
    else if (mode == "air") {
      if (OpexPO01CAirPending(owner)) {
        /* C78 may have started after our snapshot. Release the non-AIR lot;
         * do not let its last unit hold all completed modes indefinitely. */
        s.iterator = null;
        s.modes.remove(s.modeCursor);
        for (local i = s.coveredModes.len() - 1; i >= 0; i--)
          if (s.coveredModes[i] == "air") s.coveredModes.remove(i);
        for (local i = s.layers.len() - 1; i >= 0; i--)
          if (s.layers[i] == "engines.air") s.layers.remove(i);
        return true;
      }
      if (s.iterator == null) s.iterator = OpexPO01CGenerateAir(s);
    } else if (s.iterator == null) s.iterator = OpexPO01CGenerateMode(owner, s, mode);
  } else {
    phase = "publish";
    if (owner._activeWorker != null && owner._activeWorker.kind == "regen_candidates") return false;
    OpexPO01CPublish(owner, s);
    if (DECISION_LOG) OpexPO01CUnitEnd(mark, phase, "all", "OpexPO01CPublish", "whole_publish");
    owner._po01cJob = null;
    if (owner._c76AnyLayerChanged()) owner._po01cPending = true;
  }
  if (s.iterator != null) {
    if (DECISION_LOG) {
      local largest = null;
      while (s.iterator.getstatus() != "dead" && OpexOpsMeasureEnd(mark) < PO01C_SLICE_OPS) {
        /* Seed each unit: no stale rail site when another mode starts. Nested
         * generators overwrite this only after entering their own work. */
        OpexPO01CWhere(phase == "layer" ? "OpexPO01CLayerIterator"
            : (unit == "air" ? "OpexPO01CGenerateAir" : "OpexPO01CGenerateMode"), "before_first_yield", -1);
        local unitMark = OpexOpsMeasureBegin();
        PO01C_WORK_MARK = unitMark;
        resume s.iterator;
        local unitOps = OpexOpsMeasureEnd(unitMark);
        if (unitOps > PO01C_SLICE_OPS && (largest == null || unitOps > largest.ops))
          largest = { gen = PO01C_WHERE.gen, site = PO01C_WHERE.site,
              idx = PO01C_WHERE.idx, ops = unitOps };
      }
      if (largest != null) OpexDecide("PO01C_UNIT", "phase=" + phase + " mode=" + unit
          + " gen=" + largest.gen + " site=" + largest.site + " idx=" + largest.idx
          + " ops=" + largest.ops);
    } else {
      while (s.iterator.getstatus() != "dead" && OpexOpsMeasureEnd(mark) < PO01C_SLICE_OPS) {
        PO01C_WORK_MARK = OpexOpsMeasureBegin();
        resume s.iterator;
      }
    }
    if (s.iterator.getstatus() == "dead") {
      s.iterator = null;
      if (phase == "layer") s.layerCursor++; else s.modeCursor++;
    }
  }
  local ops = OpexOpsMeasureEnd(mark);
  if (phase == "mode") {
    s.modeOps.rawset(unit, (unit in s.modeOps ? s.modeOps[unit] : 0) + ops);
    if (unit in s.outputs) {
      local generated = s.outputs[unit];
      if (unit == "rail") generated.rail.opcodes = s.modeOps[unit];
      if (unit == "road") generated.road.opcodes = s.modeOps[unit];
      local count = generated.projects.len();
      foreach (project in generated.projects)
        project.planningOpcodes <- count > 0 ? s.modeOps[unit] / count : s.modeOps[unit];
    }
  }
  local days = AIDate.GetCurrentDate() - date;
  if (days > s.maxDays) s.maxDays = days;
  s.totalOps += ops; s.slices++;
  if (DECISION_LOG) OpexDecide("PO01C_SLICE", "phase=" + phase + " ops=" + ops
      + " ticks=" + (AIController.GetTick() - tick) + " days=" + days);
  if (owner._po01cJob == null) {
    OpexPO01CLog(owner, s, "publish");
    if (C39_INVALIDATION_PROBE) owner._c76RecordRegen("split", s.totalOps, s.maxDays,
        AIDate.GetYear(AIDate.GetCurrentDate()), "reactive");
  } else if (DECISION_LOG && s.slices % 200 == 0) {
    OpexPO01CLog(owner, s, "progress");
  }
  return true;
}
