// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* Dimensionnement des rames fret de RAIL-GROW (rail_grow, defaut 1 depuis le 17/11).
 *
 * Constat du 04/11 (docs/cloud_capacite-rame_20261104.md) :
 *  - les rames Opex sont dimensionnees sur la demande OBSERVEE, elle-meme
 *    plafonnee par la rame courante (V257, V284 : `carried <= captured`
 *    ou `captured` est le fret deja livre) : une rame courte justifie une
 *    rame courte, et V257 departage les ex aequo par le prix -> raccourcit ;
 *  - un quai de 4 cases porte 7 wagons, la mediane en service est 3.
 *
 * RAIL-GROW reutilise la transaction V284 (approche du depot, construction,
 * copie des ordres, adoption) ; la taille visee est la production REELLE de
 * l'industrie x note cible 75 % sur un cycle et demi, bornee par le quai, et
 * une rame remplie n'est plus revue par V257 (drapeau railFill).
 * Traction : la meme regle que V284 (aucune perte de vitesse) ; si aucune
 * locomotive ne tient la vitesse, la taille descend jusqu'a +1 wagon.
 * Historique : le reglage rail_fill (porte 250 kGBP / deux ans) a ete retire
 * le 20/11 (porte A echec, subsume par RAIL-GROW) ; les noms RAIL_FILL_* et
 * OpexRailFill* restent ceux du code partage. */

RAIL_FILL_TARGET_RATING <- 75;   // % : une rame toujours en chargement a la source
RAIL_FILL_CYCLES <- 3;           // numerateur : 3/2 cycle de cargaison par rame
RAIL_FILL_RESERVE <- 50000;      // meme reserve que la revalidation V284 au depot

function OpexRailFillLog(line, fields)
{
  if (DECISION_LOG) OpexDecide("RFILL", "line=" + line.lineId + " " + fields);
}

/* RAIL-GROW (rail_grow=1, defaut 0) : offre mensuelle reelle de la gare amont, non censuree par
 * la rame en service : production de l'industrie a la note cible, partagee a parts egales entre
 * les gares qui captent cette industrie (concurrent ou seconde gare). */
function OpexRailGrowIndustry(line)
{
  /* line.originA est l'emplacement de l'industrie (coin nord), rarement une de ses tuiles :
   * AIIndustry.GetIndustryID(originA) est alors invalide (porte A v1 : aucun wagon ajoute).
   * OpexRSOriginIndustry retrouve l'industrie par son emplacement exact ; le resultat est
   * garde sur la ligne et revalide a chaque lecture. */
  if (("railGrowIndustry" in line) && AIIndustry.IsValidIndustry(line.railGrowIndustry)
      && AIIndustry.GetLocation(line.railGrowIndustry) == line.originA) return line.railGrowIndustry;
  local industry = OpexRSOriginIndustry(line);
  if (AIIndustry.IsValidIndustry(industry)) line.rawset("railGrowIndustry", industry);
  return industry;
}

function OpexRailGrowProduction(line)
{
  local industry = OpexRailGrowIndustry(line);
  if (!AIIndustry.IsValidIndustry(industry)) return -1;
  return AIIndustry.GetLastMonthProduction(industry, line.cargo);
}

function OpexRailGrowMonthly(line)
{
  local production = OpexRailGrowProduction(line);
  if (production <= 0) return 0.0;
  local industry = OpexRailGrowIndustry(line);
  local stations = AIIndustry.GetAmountOfStationsAround(industry);
  if (stations < 1) stations = 1;
  return production.tofloat() * RAIL_FILL_TARGET_RATING / (100.0 * stations);
}

/* RAIL-GROW : l'offre reelle d'un cycle et demi depasse ce que la rame emporte par voyage. Sans
 * ce test, tout stock d'un wagon a la gare (etat normal juste avant le retour de la rame)
 * ajouterait un wagon par trimestre jusqu'au bout du quai. */
function OpexRailGrowWants(line, vehicle, wagon, number, waiting, capacity)
{
  /* Deux rames pleines a quai : preuve directe, meme si l'industrie est partagee ou inconnue. */
  if (capacity > 0 && waiting >= 2 * capacity) return true;
  local current = OpexV257Engine(AIVehicle.GetEngineType(vehicle), line.cargo, false);
  if (current == null || wagon == null || wagon.capacity <= 0) return false;
  local distance = ("routeDistance" in line) ? line.routeDistance : line.distance;
  local speed = OpexRailEffectiveSpeed(current, wagon, number, distance);
  if (speed <= 0) return false;
  local cycleDays = 2.0 * distance.tofloat() / (0.036 * speed);
  local units = OpexRailGrowMonthly(line) * cycleDays * RAIL_FILL_CYCLES / (2.0 * 30.0);
  return units > number * wagon.capacity;
}

/* RAIL-GROW, journal de decision seulement : premier motif qui ecarte chaque ligne fret a une
 * rame du balayage V284, dans l'ordre de ses gardes. Lecture seule. */
function OpexRailGrowDiag(owner, state, date, kDec)
{
  local counts = { lines = 0, no_profit = 0, quota = 0, no_wait = 0, at_limit = 0, stopped = 0,
                   no_want = 0, ok = 0, other = 0 };
  local mark = OpexOpsMeasureBegin();
  local details = 0;
  foreach (line in owner._lines) {
    if (!("mode" in line) || line.mode != "rail" || !("kind" in line) || line.kind != "freight"
        || !("platformLength" in line) || !("depot" in line) || !("distance" in line)
        || line.vehicles.len() != 1 || line.trains != 1) continue;
    counts.lines++;
    if (!("lastProfit" in line) || line.lastProfit <= 0) { counts.no_profit++; continue; }
    if ((line.lineId in state.dates) && date < state.dates[line.lineId]) { counts.quota++; continue; }
    local vehicle = line.vehicles[0];
    if (OpexRSProtected(line) || line.depot == null || !AIRail.IsRailDepotTile(line.depot)
        || !AIVehicle.IsValidVehicle(vehicle) || (("railLoop" in line) && line.railLoop == 1)) {
      counts.other++; continue;
    }
    local number = AIVehicle.GetNumWagons(vehicle) - 1;
    if (number < 1) { counts.other++; continue; }
    local wagonId = AIVehicle.GetWagonEngineType(vehicle, 1);
    local station = AIStation.GetStationID(line.stationA);
    if (!AIEngine.IsWagon(wagonId) || !AIStation.IsValidStation(station)) { counts.other++; continue; }
    local waiting = AIStation.GetCargoWaiting(station, line.cargo);
    local capacity = AIVehicle.GetCapacity(vehicle, line.cargo);
    local wagon = OpexV257Engine(wagonId, line.cargo, true);
    local maxWagons = OpexRailNominalMaxWagons(OpexV284Limit(line));
    local tag = "";
    if (wagon == null || capacity <= 0 || waiting < wagon.capacity) { counts.no_wait++; tag = "no_wait"; }
    else if (number >= maxWagons) { counts.at_limit++; continue; }
    else if (("railGrowStop" in line) && date < line.railGrowStop) { counts.stopped++; continue; }
    else if (!OpexRailGrowWants(line, vehicle, wagon, number, waiting, capacity)) { counts.no_want++; tag = "no_want"; }
    else { counts.ok++; tag = "ok"; }
    if (tag != "no_wait" && details < 3) {
      details++;
      local industry = OpexRailGrowIndustry(line);
      OpexDecide("RGROW_LINE", "line=" + line.lineId + " state=" + tag + " waiting=" + waiting
          + " capacity=" + capacity + " wagons=" + number + " max=" + maxWagons
          + " industry=" + industry + " production=" + OpexRailGrowProduction(line)
          + " stations=" + (AIIndustry.IsValidIndustry(industry) ? AIIndustry.GetAmountOfStationsAround(industry) : -1)
          + " monthly=" + OpexRailGrowMonthly(line).tointeger() + " distance=" + line.distance);
    }
  }
  OpexDecide("RGROW_SCAN", "cash=" + OpexAvailableCapital() + " lines=" + counts.lines
      + " no_profit=" + counts.no_profit + " quota=" + counts.quota + " no_wait=" + counts.no_wait
      + " at_limit=" + counts.at_limit + " stopped=" + counts.stopped + " no_want=" + counts.no_want
      + " ok=" + counts.ok + " other=" + counts.other + " diag_ops=" + OpexOpsMeasureEnd(mark));
}

/* RAIL-GROW : la rame unique d'une ligne fret peut encore recevoir des wagons sur son quai.
 * railGrowStop date un refus de traction : la ligne retrouve alors les autres leviers (ligne
 * soeur, boucle) au lieu d'attendre un wagon impossible. */
function OpexRailGrowCanFill(line)
{
  if (line == null || !("kind" in line) || line.kind != "freight"
      || !("platformLength" in line) || !("wagons" in line)
      || !("vehicles" in line) || line.vehicles == null || line.vehicles.len() != 1) return false;
  if (("railGrowStop" in line) && AIDate.GetCurrentDate() < line.railGrowStop) return false;
  return line.wagons < OpexRailNominalMaxWagons(OpexV284Limit(line));
}

/* Wagons vises : fret capte a la note cible pendant 1,5 cycle aller-retour,
 * pour qu'une rame reste en chargement pendant que la precedente roule
 * (note de prise en charge) sans attendre indefiniment un plein. */
function OpexRailFillTarget(line, wagon, number, maxWagons, speed)
{
  local production = OpexRailGrowProduction(line);
  if (production <= 0 || wagon.capacity <= 0 || speed <= 0) return number + 1;
  local distance = ("routeDistance" in line) ? line.routeDistance : line.distance;
  local cycleDays = 2.0 * distance.tofloat() / (0.036 * speed);
  if (cycleDays < 1) cycleDays = 1;
  local monthly = OpexRailGrowMonthly(line);
  local units = monthly * cycleDays * RAIL_FILL_CYCLES / (2.0 * 30.0);
  local target = OpexCeilDiv(units, wagon.capacity);
  if (target < number + 1) target = number + 1;
  if (target > maxWagons) target = maxWagons;
  return target;
}

/* Plus grande taille <= cible qu'une locomotive tient sans perte de vitesse
 * et que la caisse paie avec la reserve V284. null = garder le +1 historique. */
function OpexRailFillPlan(line, vehicle, wagon, number, maxWagons, waiting = 0, kDec = -1)
{
  local current = OpexV257Engine(AIVehicle.GetEngineType(vehicle), line.cargo, false);
  if (current == null) return null;
  local distance = ("routeDistance" in line) ? line.routeDistance : line.distance;
  local speed = OpexRailEffectiveSpeed(current, wagon, number, distance);
  local target = OpexRailFillTarget(line, wagon, number, maxWagons, speed);
  for (local n = target; n > number + 1; n -= (RAIL_GROW && n - number > 3 ? (n - number) / 2 : 1)) {
    local equipment = PFIX_V284_GROW_SCORE
        ? OpexV284Equipment(line, vehicle, wagon, n, false, waiting, kDec)
        : OpexV284Equipment(line, vehicle, wagon, n);
    if (equipment == null) continue;
    local loco = OpexV257Engine(equipment.engine, line.cargo, false);
    if (loco == null) continue;
    local price = loco.price + n * wagon.price;
    if (OpexAvailableCapital() < price + RAIL_FILL_RESERVE) continue;
    OpexRailFillLog(line, "action=plan old_wagons=" + number + " target=" + target
        + " chosen=" + n + " max=" + maxWagons
        + " production=" + OpexRailGrowProduction(line)
        + " speed=" + speed.tointeger() + " new_speed=" + equipment.speed.tointeger()
        + " price=" + price);
    return { number = n, equipment = equipment };
  }
  OpexRailFillLog(line, "action=fallback_plus_one old_wagons=" + number
      + " target=" + target + " max=" + maxWagons);
  return null;
}
