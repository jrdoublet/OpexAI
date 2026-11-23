// Generated public settings from ai/OpexAI/settings.nut and src/opexai_info.nut.in.
OPEX_SETTING_DEFAULTS <- {
  multi1_road_priority = 0,
  multi1_air_over_rail = 0,
  multi1_road_detour = 0,
  eb2_new_station_fallback = 0,
  rail_consist_pct = 100,
  n75_multi_cargo = 2,
  po01c_regen_split = 1,
  v278_air_lazy_sites = 2,
  v279_reselect_memo = 3,
  air_fleet_yield_rightsize = 0,
  front_pax2_bounded_overlap = 0,
  rail_cargo_opportunity_rank = 0,
  rail_long_value_rank = 0,
  multi1_road_cargo_shadow = 0,
  front_pax1_bounds_probe = 0,
  probes = 0,
  v286_rail_flow_probe = 0,
  c75_year_ledger_skip = 0,
  c75_bypass_ledger_skip = 0,
  save_full_state = 1,
  opex_difficulty = 2,
  fair_play_courtesy = 0,
  po02_independent_expiry = 3,
  c121_air_project_realization_adaptive = 1,
  road1y_load_orders = 1,
  mode_air = 1,
  mode_rail = 1,
  mode_road = 1,
  mode_water = 1,
  road100_solo_pax = 1,
  road100_town_bus = 0,
  road100_road_batch = 0,
  road100_freight_diversity = 1,
  road100_freight_cargo_origin = 0,
  road100_batch_roi_15 = 0,
  road100_pax_live_filter = 0,
  road100_pax_berth_balance = 0,
  road100_pax_double_berths = 0,
  road100_mail_intertown = 0,
  road100_pax_intercity_roots = 0,
  road100_pax_producer_units = 0,
  road100_pax_initial_berth_fleet = 0,
  road100_segmented_corridor = 0,
  road100_sparse_corridor = 0,
  road100_long_market_probe = 0,
  road100_portal_stitch = 0,
  road100_pax_graph_bridge = 0,
  road100_town_voirie = 0,
  road100_pax_fleet_cap = 0,
  road100_town_roi_post = 0,
  road100_intercity_site_fleet = 0,
  road100_site_first = 0,
  road100_joined_stops = 0,
  road100_multicatchment = 0,
  road1y_dist_bands = 1,
  road1y_fleet = 4,
  road1y_bus_fixes = 0,
  road1y_spread_stops = 2,
  road1y_extra_stops = 2,
  road1y_fleet_unlock = 0,
  road1y_long_v3 = 1,
  road1y_astar = 4,
  road1y_gap = 12,
  road1y_mail_on_pax = 1,
  road1y_weak = 15,
  road1y_next = 64,
  road1y_mail2 = 5,
  road1y_mail2_years = 3,
  road1y_next3 = 56,
  road1y_pax_min = 0,
  road1y_freight = 12,
  road1y_truck_fleet = 1,
  road1y_pax_sites = 1,
  road1y_pax_economy = 0,
  road1y_pax_refleet = 0,
  road100_wait_fleet = 0,
  road100_site_window = 0,
  road100_site_near = 0,
  road100_detour = 0,
  road100_tour = 0,
  road100_pax_portfolio = 0,
  v269_rail_late_relax = 5,
  dist_bornes_v276_freight = 0,
  estim_unifie = 31,
  dist_bornes_unified = 0,
  eb14_progressive = 3,
  v233_long_good = 1,
  v233l_constructibilite = 0,
  v233_site_funnel = 1,
  v233_funnel_center_test = 1,
  v284_rail_growth = 3,
  v307_long_probe = 0,
  v307_probe_year = 0,
  v307_sites = 0,
  rail_depot_cost = 0,
  c67_terrain_map = 0,
  v131_town_clearance = 0,
  v207_rail_pax_share_pct = 0,
  v207_rail_mail = 0,
  v207_rail_pax_joined_stops = 0,
  v207_rail_pax_site_rank_pct = 0,
  v275_rail_pax_mm = 15,
  v250_rights = 0,
  v276_cand_slices = 3,
  v259_bridge_renew = 0,
  v277_air_pub_fast = 3,
  air_site_ranked = 1,
  air_site_funnel = 1,
  pax_air_first = 0,
  air_load_min_pct = 0,
  road100_long_intercity = 0,
  road100_long_build = 0,
  invest_stall = 0,
  rail_loop = 1,
  rail_sidings = 0,
  rail_sidings_trigger = 0,
  rail_stale_abandon = 0,
  rail_double_offer = 0,
  rail_engine_value = 5,
  rail_consist_headroom_pct = 100,
  rail_grow = 1,
  pfix_road1y_weak_fix = 0,
  pfix_po01c_road_pax = 0,
  pfix_v284_grow_score = 0,
  pfix_v257_origin_industry = 0,
  pfix_po01c_abandon_ack = 0,
  pfix_catalog_mode_cut = 0,
};

function OpexGetSetting(name)
{
  // OpenTTD 15.3 ScriptInfo::GetSettingDefaultValue returns -1 for an absent name.
  local value = AIController.GetSetting(name);
  if (value != -1) return value;
  if (name == "opex_difficulty") return AIController.GetSetting("difficulty");
  if (name == "mode_rail") return AIController.GetSetting("use_trains");
  if (name == "mode_road") return AIController.GetSetting("use_road_vehicles");
  if (name == "mode_air") return AIController.GetSetting("use_aircraft");
  if (name == "mode_water") return AIController.GetSetting("use_ships");
  if (name == "probes") {
    local signs = AIController.GetSetting("show_signs");
    local level = AIController.GetSetting("log_level");
    return (signs == 1 ? 2 : 0) | (level == 2 ? 256 : (level == 1 ? 4 : 0));
  }
  return OPEX_SETTING_DEFAULTS[name];
}

function OpexDiagLog(msg)
{
  if (DECISION_LOG) AILog.Info(msg);
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* Canonical developer settings loader. src/opexai_schema.py generates the public
 * copy with OpexGetSetting: public aliases and schema defaults for absent names.
 * Keep the decision logic here, shared by both generated profiles. */

/* Entier signe 32 bits : bits 0..30, max 2147483647.
 *   1 = toutes les sondes, 2 = panneaux, 4 = ancien alias journal,
 *   8/16/32/64/128 = groupes historiques, 256 = journal seul.
 *   512..1073741824 = canaux dedies. Le bit d'un canal individuel ne doit
 *   allumer aucun canal voisin ni forcer DECISION_LOG.
 * Les groupes historiques continuent a allumer leur ensemble et le journal. */
function OpexProbeEnabled(bit, legacyGroup = 0)
{
  return (OPEX_PROBE_MASK & (bit | legacyGroup)) != 0;
}

/* Niveau 0..3. Sur OpenTTD <= 13.4, script.settings_profile (0 facile, 1 moyen,
 * 2 difficile ; 3 personnalise existait hors menu) fait foi. Sur 14/15.3 le
 * reglage a disparu : opex_difficulty, dont les quatre valeurs valent 2, est
 * le niveau. Un banc qui ne le passe pas joue donc en difficile. */
function OpexResolveDifficulty()
{
  if (AIGameSettings.IsValid("script.settings_profile")) {
    local profile = AIGameSettings.GetValue("script.settings_profile");
    if (profile == null || profile < 0) return 0;
    if (profile > 3) return 3;
    return profile;
  }
  local value = OpexGetSetting("opex_difficulty");
  if (value == null || value < 0) return 2;
  if (value > 3) return 3;
  return value;
}

/* C65 passe 2 & regroupement macro-politiques : lecture unique des reglages.
 * Fonction libre : n'affecte que des globales. Les mutations d'instance
 * restent dans Start(), juste apres l'appel. */
function OpexLoadSettings()
{
  AIR_LOAD_MIN_PCT = OpexGetSetting("air_load_min_pct");
  if (AIR_LOAD_MIN_PCT == null || AIR_LOAD_MIN_PCT < 0) AIR_LOAD_MIN_PCT = 0;
  if (AIR_LOAD_MIN_PCT > 100) AIR_LOAD_MIN_PCT = 100;
  /* Le masque doit etre initialise avant la toute premiere sonde AIR. */
  local probes = OpexGetSetting("probes");
  if (probes < 0) probes = 2;
  if ((probes & 1) != 0) probes = 2147483647;
  OPEX_PROBE_MASK = probes;
  RS_TRAFFIC_TRACE = true; // isolated native witness
  AIR_FLOTTE1_SHADOW = OpexProbeEnabled(8388608);
  PO01C_REGEN_SPLIT = OpexGetSetting("po01c_regen_split") != 0;
  /* V276/V278 (defaut auto depuis le 20/10, decision utilisateur) : qualifies ensemble a 1024x1024
   * seulement (portes A +631 k et B +1,11 M), sans gain mesure a 256x256 ; actifs des 1024x1024 tuiles. */
  local bigMap = AIMap.GetMapSizeX() * AIMap.GetMapSizeY() >= 1024 * 1024;
  local v278 = OpexGetSetting("v278_air_lazy_sites");
  V278_AIR_LAZY_SITES = v278 == 1 || (v278 == 2 && bigMap);
  /* V277/V279 (defaut auto depuis le 20/10, decision utilisateur) : qualifies a 1024x1024 par V287
   * (porte B +680 k, porte A +237 k non significative) ; negatifs a 256x256 (banc PC -195 k, 6/14).
   * 3 = auto : 1 des 1024x1024 tuiles, 0 sinon. */
  local v279 = OpexGetSetting("v279_reselect_memo");
  V279_RESELECT_MEMO = (v279 == 3) ? (bigMap ? 1 : 0) : v279;
  /* --- 1. Systeme et persistance --- */
  DEBUG_SIGNS = (probes & 2) != 0;
  DECISION_LOG = (probes & 508) != 0;
  PORTFOLIO_LOG = DECISION_LOG;
  SAVE_FULL_STATE = OpexGetSetting("save_full_state") != 0;
  OPEX_DIFFICULTY = OpexResolveDifficulty();
  OPEX_LEVEL_LIMITS = !OpexLevelAllows("encroach_rival_catchment") || !OpexLevelAllows("compete_primary_industry")
      || !OpexLevelAllows("airport_rival_town") || !OpexLevelAllows("preempt_last_airport_slot");
  FAIR_PLAY_COURTESY = OpexGetSetting("fair_play_courtesy") == 1;
  if (FAIR_PLAY_COURTESY) OPEX_LEVEL_LIMITS = true;
  PO02_INDEPENDENT_EXPIRY = OpexGetSetting("po02_independent_expiry");
  if (PO02_INDEPENDENT_EXPIRY < 0 || PO02_INDEPENDENT_EXPIRY > 3) PO02_INDEPENDENT_EXPIRY = 3;

  /* --- 2. Interrupteurs de mode et options rail --- */

  // V166 : interrupteurs de mode conserves pour les bancs monomodes.
  MODE_AIR = OpexGetSetting("mode_air") != 0;
  MODE_RAIL = OpexGetSetting("mode_rail") != 0;
  MODE_ROAD = OpexGetSetting("mode_road") != 0;
  MODE_WATER = OpexGetSetting("mode_water") != 0;
  ROAD1Y_LOAD_ORDERS = OpexGetSetting("road1y_load_orders") == 1;
  local multi1RoadPriority = OpexGetSetting("multi1_road_priority");
  MULTI1_ROAD_PRIORITY = (multi1RoadPriority == 1 || multi1RoadPriority == 2) ? multi1RoadPriority : 0;
  local multi1AirOverRail = OpexGetSetting("multi1_air_over_rail");
  MULTI1_AIR_OVER_RAIL = (multi1AirOverRail == 1 || multi1AirOverRail == 2) ? multi1AirOverRail : 0;
  local multi1RoadDetour = OpexGetSetting("multi1_road_detour");
  MULTI1_ROAD_DETOUR = (multi1RoadDetour == 1 || multi1RoadDetour == 2) ? multi1RoadDetour : 0;
  MULTI1_ROAD_CARGO_SHADOW = OpexGetSetting("multi1_road_cargo_shadow") == 1 ? 1 : 0;
  MULTI1_ROAD_CARGO_PENDING = null;
  MULTI1_ROAD_CARGO_LAST_MONTH = -1;
  local p3AirFleetYield = OpexGetSetting("air_fleet_yield_rightsize");
  P3_AIR_FLEET_YIELD = (p3AirFleetYield == 1 || p3AirFleetYield == 2) ? p3AirFleetYield : 0;
  P3_AIR_FLEET_WINDOWS = {};
  local fp2Overlap = OpexGetSetting("front_pax2_bounded_overlap");
  FRONT_PAX2_BOUNDED_OVERLAP = (fp2Overlap == 1 || fp2Overlap == 2) ? fp2Overlap : 0;
  local p2Opportunity = OpexGetSetting("rail_cargo_opportunity_rank");
  P2_RAIL_CARGO_OPPORTUNITY_RANK = (p2Opportunity == 1 || p2Opportunity == 2) ? p2Opportunity : 0;
  P2_OPPORTUNITY_STAMP = 0;
  // V261 point 6 : couper aussi les modes que la partie interdit aux IA ou dont le plafond vaut 0.
  if (MODE_AIR && !OpexModeAllowedByGame("air")) MODE_AIR = false;
  if (MODE_RAIL && !OpexModeAllowedByGame("rail")) MODE_RAIL = false;
  if (MODE_ROAD && !OpexModeAllowedByGame("road")) MODE_ROAD = false;
  if (MODE_WATER && !OpexModeAllowedByGame("water")) MODE_WATER = false;
  /* Mode unique seulement : les bus autonomes avaient cannibalise AIR en multimodal. */
  ROAD100_SOLO_PAX = OpexGetSetting("road100_solo_pax") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_TOWN_BUS = OpexGetSetting("road100_town_bus") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_ROAD_BATCH = OpexGetSetting("road100_road_batch") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_TOWN_VOIRIE = OpexGetSetting("road100_town_voirie") == 1
      && ROAD100_TOWN_BUS;
  ROAD100_TOWN_ROI_POST = OpexGetSetting("road100_town_roi_post") == 1
      && ROAD100_TOWN_BUS && ROAD100_TOWN_VOIRIE;
  ROAD100_INTERCITY_SITE_FLEET = OpexGetSetting("road100_intercity_site_fleet") == 1
      && ROAD100_SOLO_PAX;
  ROAD100_SITE_FIRST = OpexGetSetting("road100_site_first") == 1
      && ROAD100_SOLO_PAX;
  ROAD100_JOINED_STOPS = OpexGetSetting("road100_joined_stops") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_MULTICATCHMENT = OpexGetSetting("road100_multicatchment") == 1
      && ROAD100_SITE_FIRST;
  /* ROAD1Y : uniquement route seule, meme condition de modes que ROAD100_SOLO_PAX.
   * Hors route seule, chaque variable reprend la valeur de origin/master. */
  local road1yRoadOnly = MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  if (!road1yRoadOnly) ROAD1Y_LOAD_ORDERS = false;
  ROAD1Y_DIST_BANDS = OpexGetSetting("road1y_dist_bands") == 1;
  if (!road1yRoadOnly) ROAD1Y_DIST_BANDS = false;
  ROAD_MAX_TRACE_TILES = ROAD1Y_DIST_BANDS ? 128 : 48;
  ROAD1Y_FLEET = OpexGetSetting("road1y_fleet");
  if (ROAD1Y_FLEET < 0) ROAD1Y_FLEET = 0;
  if (ROAD1Y_FLEET > 16) ROAD1Y_FLEET = 16;
  if (!road1yRoadOnly) ROAD1Y_FLEET = 0;
  ROAD1Y_PAX_ECONOMY = OpexGetSetting("road1y_pax_economy") == 1;
  if (!road1yRoadOnly) ROAD1Y_PAX_ECONOMY = false;
  ROAD1Y_PAX_REFLEET = OpexGetSetting("road1y_pax_refleet") == 1;
  if (!road1yRoadOnly) ROAD1Y_PAX_REFLEET = false;
  ROAD1Y_SPREAD_STOPS = OpexGetSetting("road1y_spread_stops");
  if (ROAD1Y_SPREAD_STOPS < 0) ROAD1Y_SPREAD_STOPS = 0;
  if (ROAD1Y_SPREAD_STOPS > 4) ROAD1Y_SPREAD_STOPS = 4;
  if (!road1yRoadOnly) ROAD1Y_SPREAD_STOPS = 0;
  ROAD1Y_MAIL_ON_PAX = OpexGetSetting("road1y_mail_on_pax") == 1;
  if (!road1yRoadOnly) ROAD1Y_MAIL_ON_PAX = false;
  ROAD1Y_WEAK = OpexGetSetting("road1y_weak");
  if (ROAD1Y_WEAK < 0 || ROAD1Y_WEAK > 30) ROAD1Y_WEAK = 0;
  if (!road1yRoadOnly) ROAD1Y_WEAK = 0;
  ROAD1Y_NEXT = OpexGetSetting("road1y_next");
  if (ROAD1Y_NEXT < 0 || ROAD1Y_NEXT > 192) ROAD1Y_NEXT = 0;
  if (!road1yRoadOnly) ROAD1Y_NEXT = 0;
  ROAD1Y_MAIL2 = OpexGetSetting("road1y_mail2");
  if (ROAD1Y_MAIL2 < 0 || ROAD1Y_MAIL2 > 25) ROAD1Y_MAIL2 = 0;
  if (!road1yRoadOnly) ROAD1Y_MAIL2 = 0;
  ROAD1Y_MAIL2_YEARS = OpexGetSetting("road1y_mail2_years");
  if (ROAD1Y_MAIL2_YEARS < 0 || ROAD1Y_MAIL2_YEARS > 20) ROAD1Y_MAIL2_YEARS = 0;
  if (!road1yRoadOnly) ROAD1Y_MAIL2_YEARS = 0;
  ROAD1Y_NEXT3 = OpexGetSetting("road1y_next3");
  if (ROAD1Y_NEXT3 < 0 || ROAD1Y_NEXT3 > 96) ROAD1Y_NEXT3 = 0;
  if (!road1yRoadOnly) ROAD1Y_NEXT3 = 0;
  ROAD1Y_PAX_MIN = OpexGetSetting("road1y_pax_min");
  if (ROAD1Y_PAX_MIN < 0 || ROAD1Y_PAX_MIN > 100) ROAD1Y_PAX_MIN = 0;
  if (!road1yRoadOnly) ROAD1Y_PAX_MIN = 0;
  ROAD1Y_FREIGHT = OpexGetSetting("road1y_freight");
  if (ROAD1Y_FREIGHT < 0 || ROAD1Y_FREIGHT > 30) ROAD1Y_FREIGHT = 0;
  if (!road1yRoadOnly) ROAD1Y_FREIGHT = 0;
  ROAD1Y_TRUCK_FLEET = OpexGetSetting("road1y_truck_fleet");
  if (ROAD1Y_TRUCK_FLEET < 0 || ROAD1Y_TRUCK_FLEET > 1) ROAD1Y_TRUCK_FLEET = 0;
  if (!road1yRoadOnly) ROAD1Y_TRUCK_FLEET = 0;
  ROAD1Y_FLEET_UNLOCK = OpexGetSetting("road1y_fleet_unlock");
  if (ROAD1Y_FLEET_UNLOCK < 0 || ROAD1Y_FLEET_UNLOCK > 15) ROAD1Y_FLEET_UNLOCK = 0;
  if (!road1yRoadOnly) ROAD1Y_FLEET_UNLOCK = 0;
  ROAD1Y_DIST_BAND_LIMITS = [[64, 128], [32, 63], [7, 31]];
  /* ROAD1Y-G : trace 192 pour le PAX (bande -1, BFS, L) sans reordonner
   * les bandes fret. La premiere bande non vide reste 64-128.
   * Hors route seule le trace reste 48.
   * bus_districts_overrides.nut lit ROAD_MAX_TRACE_TILES dans des fonctions,
   * pas au require ; main.nut appelle OpexLoadBusDistrictSettings() (qui fait
   * ce require) au chargement avant Start() / OpexLoadSettings(). */
  ROAD1Y_LONG_V3 = OpexGetSetting("road1y_long_v3");
  if (ROAD1Y_LONG_V3 != 1) ROAD1Y_LONG_V3 = 0;
  if (!road1yRoadOnly) ROAD1Y_LONG_V3 = 0;
  ROAD1Y_ASTAR = OpexGetSetting("road1y_astar");
  if (ROAD1Y_ASTAR < 0 || ROAD1Y_ASTAR > 16) ROAD1Y_ASTAR = 0;
  if (!road1yRoadOnly) ROAD1Y_ASTAR = 0;
  ROAD1Y_GAP = OpexGetSetting("road1y_gap");
  if (ROAD1Y_GAP < 0 || ROAD1Y_GAP > 30) ROAD1Y_GAP = 0;
  if (!road1yRoadOnly) ROAD1Y_GAP = 0;
  if (ROAD1Y_LONG_V3 == 1 && ROAD1Y_DIST_BANDS)
    ROAD_MAX_TRACE_TILES = 192;

  ROAD100_WAIT_FLEET = OpexGetSetting("road100_wait_fleet") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_SITE_WINDOW = OpexGetSetting("road100_site_window") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_SITE_NEAR = OpexGetSetting("road100_site_near") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_DETOUR = OpexGetSetting("road100_detour") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_TOUR = OpexGetSetting("road100_tour") == 1
      && ROAD100_SOLO_PAX;
  ROAD100_LONG_INTERCITY = OpexGetSetting("road100_long_intercity") == 1
      && ROAD100_SITE_FIRST;
  ROAD100_LONG_BUILD = OpexGetSetting("road100_long_build") == 1
      && ROAD100_LONG_INTERCITY;
  ROAD100_SEGMENTED_CORRIDOR = OpexGetSetting("road100_segmented_corridor") == 1
      && ROAD100_LONG_BUILD && MODE_ROAD && !MODE_AIR
      && !MODE_RAIL && !MODE_WATER;
  ROAD100_SPARSE_CORRIDOR = OpexGetSetting("road100_sparse_corridor") == 1
      && ROAD100_LONG_BUILD && !ROAD100_SEGMENTED_CORRIDOR
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_LONG_MARKET_PROBE = OpexGetSetting("road100_long_market_probe") == 1
      && ROAD100_LONG_BUILD && MODE_ROAD && !MODE_AIR
      && !MODE_RAIL && !MODE_WATER;
  ROAD100_PORTAL_STITCH = OpexGetSetting("road100_portal_stitch") == 1
      && ROAD100_SPARSE_CORRIDOR && ROAD100_LONG_BUILD
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_GRAPH_BRIDGE = OpexGetSetting("road100_pax_graph_bridge") == 1
      && ROAD100_LONG_BUILD && !ROAD100_SEGMENTED_CORRIDOR
      && !ROAD100_SPARSE_CORRIDOR && !ROAD100_PORTAL_STITCH
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_PORTFOLIO = OpexGetSetting("road100_pax_portfolio") == 1
      && ROAD100_SITE_FIRST && !ROAD100_JOINED_STOPS && !ROAD100_LONG_BUILD;
  ROAD100_FREIGHT_DIVERSITY = OpexGetSetting("road100_freight_diversity") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_FREIGHT_CARGO_ORIGIN = OpexGetSetting("road100_freight_cargo_origin") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_BATCH_ROI_15 = OpexGetSetting("road100_batch_roi_15") == 1
      && ROAD100_ROAD_BATCH;
  ROAD100_PAX_LIVE_FILTER = OpexGetSetting("road100_pax_live_filter") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_BERTH_BALANCE = OpexGetSetting("road100_pax_berth_balance") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_DOUBLE_BERTHS = OpexGetSetting("road100_pax_double_berths") == 1
      && !ROAD100_PAX_BERTH_BALANCE
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  local road100MailMode = OpexGetSetting("road100_mail_intertown");
  ROAD100_MAIL_INTERTOWN = road100MailMode >= 1
      && ROAD100_SITE_FIRST && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_MAIL_LONG_EXISTING = ROAD100_MAIL_INTERTOWN && road100MailMode == 2;
  ROAD100_PAX_INTERCITY_ROOTS = OpexGetSetting("road100_pax_intercity_roots") == 1
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_PRODUCER_UNITS = OpexGetSetting("road100_pax_producer_units") == 1
      && ROAD100_SITE_FIRST && !ROAD100_MULTICATCHMENT
      && !ROAD100_LONG_BUILD
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_INITIAL_BERTH_FLEET =
      OpexGetSetting("road100_pax_initial_berth_fleet") == 1
      && ROAD100_PAX_PRODUCER_UNITS && ROAD100_PAX_PORTFOLIO
      && !ROAD100_PAX_DOUBLE_BERTHS && !ROAD100_PAX_BERTH_BALANCE
      && MODE_ROAD && !MODE_AIR && !MODE_RAIL && !MODE_WATER;
  ROAD100_PAX_ROOTS_LAST_YEAR = -1;
  local road100FleetCap = OpexGetSetting("road100_pax_fleet_cap");
  ROAD100_PAX_FLEET_CAP = ROAD100_TOWN_BUS && road100FleetCap == 8 ? 8 : 0;
  V216_PROBE = OpexProbeEnabled(536870912);
  V211_RIVALS = OpexProbeEnabled(1073741824);
  local lateRelax = OpexGetSetting("v269_rail_late_relax");
  DIST_BORNES_V276_FREIGHT = OpexGetSetting("dist_bornes_v276_freight") == 1;
  DIST_BORNES_UNIFIED = OpexGetSetting("dist_bornes_unified") == 1;
  ESTIM_UNIFIE = OpexGetSetting("estim_unifie");
  /* Experiment: leave the historical C121 scanner untouched OFF. */
  if ((ESTIM_UNIFIE & 1) != 0) {
    require("air_economics_c121_fullscan.nut");
    ::OpexC121ChooseRoutePlane <- OpexC121ChooseRoutePlaneFullScan;
  }
  ESTIM16_RAIL_SCORE_TRACES = 0;
  foreach (m, k in ESTIM_K_R_PRIOR) ESTIM_K_R[m] = k;
  local railGrowth = OpexGetSetting("v284_rail_growth");
  V233_LONG_GOOD = OpexGetSetting("v233_long_good") == 1 ? 1 : 0;
  V233L_CONSTRUCT = OpexGetSetting("v233l_constructibilite");
  if (V233L_CONSTRUCT == null || V233L_CONSTRUCT < 0 || V233L_CONSTRUCT > 2) V233L_CONSTRUCT = 0;
  V233_SITE_FUNNEL = OpexGetSetting("v233_site_funnel") == 1 ? 1 : 0;
  V233_FUNNEL_CENTER_TEST = OpexGetSetting("v233_funnel_center_test") == 0 ? 0 : 1;
  if (railGrowth != null && railGrowth >= 0 && railGrowth <= 10) V284_RAIL_GROWTH = railGrowth;
  local v307Probe = OpexGetSetting("v307_long_probe");
  V307_LONG_PROBE = (v307Probe != null && v307Probe > 0 && v307Probe <= 9) ? v307Probe : 0;
  V309_IDLE_PROBE = OpexProbeEnabled(67108864);
  FRONT_PAX1_CLAMP_PROBE = OpexGetSetting("front_pax1_bounds_probe") == 1;
  local v307Year = OpexGetSetting("v307_probe_year");
  V307_PROBE_YEAR = (v307Year != null && v307Year > 0 && v307Year <= 9) ? v307Year : 0;
  V286_FLOW_PROBE = OpexGetSetting("v286_rail_flow_probe") == 1;
  V286_FLOW_LAST_DAY = -1;
  V286_FLOW_CURSOR = 0;
  V308_CARTO_PROBE = OpexProbeEnabled(134217728) ? 1 : 0;
  V307_ABND_AUTOPSY = OpexProbeEnabled(268435456);
  local v307Sites = OpexGetSetting("v307_sites");
  V307_SITES = (v307Sites >= 1 && v307Sites <= 3) ? v307Sites : 0;
  V269_RAIL_LATE_RELAX = (lateRelax != null && lateRelax > 0 && lateRelax <= 9) ? lateRelax : 0;
  INVEST_STALL = OpexGetSetting("invest_stall") == 1;
  RAIL_LOOP = OpexGetSetting("rail_loop") == 1;
  /* rail_fill retire le 20/11 (subsume par RAIL_GROW). */
  local railGrow = OpexGetSetting("rail_grow");
  RAIL_GROW = railGrow != null && railGrow >= 1;
  RAIL_GROW_FIRST = railGrow != null && railGrow == 2;
  INVEST_STALL_LAST_MONTH = INVEST_STALL ? INVEST_STALL_SAVED_MONTH : -1;
  INVEST_STALL_SAVED_MONTH = -1;
  local v207Share = OpexGetSetting("v207_rail_pax_share_pct");
  V207_RAIL_PAX_SHARE_PCT = (v207Share != null && v207Share >= 0 && v207Share <= 100) ? v207Share : 0;
  V207_RAIL_MAIL = OpexGetSetting("v207_rail_mail") != 0;
  local v207Stops = OpexGetSetting("v207_rail_pax_joined_stops");
  V207_RAIL_PAX_JOINED_STOPS = (v207Stops != null && v207Stops >= 0 && v207Stops <= 4) ? v207Stops : 0;
  local v207Rank = OpexGetSetting("v207_rail_pax_site_rank_pct");
  V207_RAIL_PAX_SITE_RANK_PCT = (v207Rank != null && v207Rank >= 0 && v207Rank <= 100) ? v207Rank : 0;
  local v275 = OpexGetSetting("v275_rail_pax_mm");
  V275_RAIL_PAX_MM = (v275 != null && v275 >= 0 && v275 <= 15) ? v275 : 0;
  /* V275 bit 8 (defaut 15 depuis le 20/10, decision utilisateur) : reglage selon le mode.
   * Sans aerien, paquet qualifie en rail seul (portes A +635 k et B +791 k) : bits 1/2/4 et,
   * si les reglages V207 sont a leur defaut, part 40 + courrier + 2 arrets joints. Avec
   * l'aerien, masque ramene a 0 : le paquet y perd a 3 ans (-71 k) et le bras sobre y est
   * neutre (+0,2 k), donc le comportement multimodal reste celui d'avant V275. */
  if (V275_RAIL_PAX_MM & 8) {
    if (MODE_AIR) {
      V275_RAIL_PAX_MM = 0;
    } else if (V207_RAIL_PAX_SHARE_PCT == 0 && !V207_RAIL_MAIL && V207_RAIL_PAX_JOINED_STOPS == 0) {
      V207_RAIL_PAX_SHARE_PCT = 40;
      V207_RAIL_MAIL = true;
      V207_RAIL_PAX_JOINED_STOPS = 2;
    }
  }
  local rights = OpexGetSetting("v250_rights");
  if (rights == null || rights < 0 || rights > 4) rights = 0;
  /* V250 entiere reservee au niveau 3 (personnalise) : geste anticoncurrentiel. */
  if (!OpexLevelAllows("v250_rights")) rights = 0;
  V250_RIGHTS = rights;
  local v259Renew = OpexGetSetting("v259_bridge_renew");
  V259_BRIDGE_RENEW = (v259Renew != null && v259Renew == 1) ? 1 : 0;
  local v277Pub = OpexGetSetting("v277_air_pub_fast");
  if (v277Pub == 3) v277Pub = AIMap.GetMapSizeX() * AIMap.GetMapSizeY() >= 1024 * 1024 ? 1 : 0;
  V277_AIR_PUB_FAST = (v277Pub != null && v277Pub >= 0 && v277Pub <= 2) ? v277Pub : 0;
  /* V294f est fige a 300 iterations, sans nouveau reglage experimental. */
  local p1LongRank = OpexGetSetting("rail_long_value_rank");
  P1_RAIL_LONG_VALUE_RANK = (p1LongRank == 1 || p1LongRank == 2) ? p1LongRank : 0;
  RAIL_SIDINGS_SHADOW = OpexGetSetting("rail_sidings") == 1;
  RS_ECONOMIC_TRIGGER = OpexGetSetting("rail_sidings_trigger") >= 1;
  RS_TRIGGER_GROWTH = OpexGetSetting("rail_sidings_trigger") == 2;
  RAIL_STALE_ABANDON = OpexGetSetting("rail_stale_abandon") == 1;
  RAIL_DOUBLE_OFF = OpexGetSetting("rail_double_offer") == 1;
  local railEngineValue = OpexGetSetting("rail_engine_value");
  RAIL_ENGINE_VALUE = (railEngineValue != null && railEngineValue > 0) ? railEngineValue : 0;
  local railHeadroom = OpexGetSetting("rail_consist_headroom_pct");
  RAIL_CONSIST_HEADROOM_PCT = (railHeadroom != null && railHeadroom > 0) ? railHeadroom : 0;

  // V246 : paquets adoptes figes ; les interrupteurs de mode restent actifs.
  ROAD_BUILD_ENABLED = MODE_ROAD;
  // Repli interne avant l'amorcage plat, qui le desactive plus bas.
  STAGED_BOOTSTRAP = true;

  /* --- 3. Calibrations physiques et options reelles --- */

  RAIL_FAILURE_AUDIT = OpexProbeEnabled(2097152, 32);

  /* --- 4. Canaux de diagnostic dedies et groupes historiques --- */

  // 1. Couts de construction (dedie 512, groupe 64).
  local probeCost = OpexProbeEnabled(512, 64);
  RAIL_COST_PROBE = probeCost;
  AIR_COST_PROBE = probeCost;
  ROAD_COST_PROBE = probeCost;

  // 2. Ordonnanceur (dedie 1024), boucle (2048), spans (4096), groupe 8.
  local probeScheduler = OpexProbeEnabled(1024, 8);
  PROBE_LOOP_OPS = OpexProbeEnabled(2048, 8);
  PROBE_SPAN_TRACE = OpexProbeEnabled(4096, 8);
  PROBE_EVENT_BACKLOG = (OPEX_PROBE_MASK & 8) != 0;
  PROBE_SELECT_REJECT = OpexProbeEnabled(8192, 16);
  if (PROBE_EVENT_BACKLOG) {
    EVENT_BACKLOG_CALLS = 0;
    EVENT_BACKLOG_EVENTS = 0;
    EVENT_BACKLOG_MAX_BURST = 0;
    EVENT_BACKLOG_OPS_TOTAL = 0;
    EVENT_BACKLOG_OPS_MAX = 0;
    EVENT_BACKLOG_MONTH = -1;
  }
  OPCODE_EXACT_SITE_NAME = null;
  C41_SLACK_LEDGER = probeScheduler;
  C41_MONTHLY_BUSY_LEDGER = probeScheduler;
  C41_STALENESS_LEDGER = probeScheduler;
  C41_OPPORTUNITY_LEDGER = probeScheduler;
  C41_ADMISSION_LEDGER = probeScheduler;
  C39_PASS_CLOCK_LEDGER = probeScheduler;
  C41_RAIL_SLICE_LEDGER = probeScheduler;
  V95_SCHED_IDLE_LEDGER = probeScheduler;

  // 3. Profils routiers (bit 8) : pax, freight, town sinks
  local probeCandRoad = (OPEX_PROBE_MASK & 8) != 0;
  C41_ROAD_CANDIDATE_PROFILE = probeCandRoad;
  C41_ROAD_FREIGHT_PROFILE = probeCandRoad;
  C41_ROAD_FREIGHT_TOWN_PROFILE = probeCandRoad;

  // 4. Candidats rail (dedie 16384, groupe 8).
  local probeCandRail = OpexProbeEnabled(16384, 8);
  C41_RAIL_PORTFOLIO_PROFILE = probeCandRail;
  C41_RAIL_CANDIDATE_PROFILE = probeCandRail;
  C41_RAIL_PAX_PROFILE = probeCandRail;
  C41_RAIL_PAX_CANDIDATE_PROFILE = probeCandRail;
  C41_RAIL_PAX_ECONOMICS_PROFILE = probeCandRail;
  C41_RAIL_PAX_SPEED_PROFILE = probeCandRail;
  C41_RAIL_PAX_SPEED_DETAIL_PROFILE = probeCandRail;
  C41_RAIL_PAX_CRUISE_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_CANDIDATE_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_ECONOMICS_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_ECONOMICS_DETAIL_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_ECONOMICS_SETUP_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_ECONOMICS_CONSIST_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_CRUISE_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_SPEED_DETAIL_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_EFFECTIVE_SPEED_PROFILE = probeCandRail;
  C41_RAIL_FREIGHT_TOWN_GUARDS_PROFILE = probeCandRail;

  // 5. Catalogue (dedie 32768, groupe 8).
  local probeCat = OpexProbeEnabled(32768, 8);
  C39_INVALIDATION_PROBE = probeCat;
  C39_DECISION_DELTA_PROBE = probeCat;
  C39_AIR_REASON_PROBE = probeCat;
  C41_REVISION_PROBE = probeCat;
  if (C39_INVALIDATION_PROBE) OpexC76Reset();

  // 6. Recherche rail (bit 32) : domination, fallthrough, projects cadence
  local probeRailSearch = (OPEX_PROBE_MASK & 32) != 0;
  C41_RAIL_DOMINATION_PROBE = probeRailSearch;
  C41_PROJECTS_FALLTHROUGH_PROBE = probeRailSearch;
  C39_PROJECTS_CADENCE_PROBE = probeRailSearch;

  // 7. Vehicules perdus (dedie 65536, groupe 128).
  local probeLost = OpexProbeEnabled(65536, 128);
  C41_RAIL_LOST_TOPOLOGY_PROBE = probeLost;
  C41_RAIL_LOST_PHYSICAL_PROBE = probeLost;
  C41_RAIL_LOST_CONNECTIVITY_PROBE = probeLost;
  C41_RAIL_LOST_PROBE = probeLost;
  C41_VEHICLE_LOST_PROBE = probeLost;

  // 8. Portefeuille (dedie 131072, groupe 128).
  local probePort = OpexProbeEnabled(131072, 128);
  C49_SCARCITY_LEDGER = probePort;
  C50_CHRONOLOGY_PROBE = probePort;
  if (C50_CHRONOLOGY_PROBE) {
    OpexC50ResetNonExpansionLedger();
  }
  C63_INVEST_PROBE = probePort;
  if (C63_INVEST_PROBE) OpexC63ResetLedger();
  ::OpexCalibratedProfit <- OpexC70Profit;
  if ((ESTIM_UNIFIE & 17) != 0) ::OpexCalibratedProfit <- OpexEstimProfit;
  C69_BOTTLENECK_PROBE = probePort;
  C75_YEAR_LEDGER_SKIP = OpexGetSetting("c75_year_ledger_skip") == 1;
  C75_BYPASS_LEDGER_SKIP = OpexGetSetting("c75_bypass_ledger_skip") == 1;
  /* Amorcage plat : sans etapes, chaque regeneration apres chantier prend le
   * chemin incremental C121 au lieu d'un OpexBuildProjects complet synchrone. */
  STAGED_BOOTSTRAP = false;
  C121_CATALOG_FIRST_YEAR_ACTIVE = false;
  C121_AIR_FIRST_LIVE_GROWTH_PHASE_YEARS = 4;
  C121_AIR_FIRST_LIVE_STATE = {};
  C121_AIR_FIRST_LIVE_OPS = 0;
  C121_AIR_FIRST_LIVE_SAMPLES = 0;
  {
    C121_CATALOG_CACHE.clear();
    C121_AIR_ENDPOINT_CACHE = null;
    OpexC121InvalidateEndpointGeometry();
    C121_CATALOG_TOWN_REV.clear();
    C121_CATALOG_TOWN_POP.clear();
    C121_CATALOG_TOWN_PROD.clear();
    C121_CATALOG_TOWN_CURSOR = 0;
    C121_CATALOG_TOWN_BATCH_DATE = -1;
    C121_CATALOG_AIRPORT_PRICES.clear();
    C121_CATALOG_AIRPORT_REV.clear();
    C121_CATALOG_STATION_REV.clear();
    C121_CATALOG_STATION_LINES.clear();
    C121_CATALOG_HUB_LEARN_REV.clear();
    C121_CATALOG_AIRPORT_LEARN_REV.clear();
    C121_CATALOG_ARM_LEARN_REV.clear();
    C121_CATALOG_TOWN_PRIORITY.clear();
  }
  C121_AIR_PROJECT_REALIZATION_ADAPTIVE = OpexGetSetting("c121_air_project_realization_adaptive") != 0;
  AIR_P0_DIRECT_REALIZATION_ACTIVE = false;
  C121_AIR_P0_DIRECT_FACTOR.hubsite = 1.0;
  C121_AIR_P0_DIRECT_FACTOR.hubhub = 1.0;
  C121_AIR_PRESSURE_ACCUM = null;
  C121_AIR_PRESSURE_PREV = null;
  C122_AIR_REGIME_SHADOW = OpexProbeEnabled(262144, 16);
  C122_AIR_THREAT_PROBE = OpexProbeEnabled(524288, 16);
  C122_AIR_THREAT_WATCH.clear();
  C122_AIR_THREAT_SEQ = 0;
  C121_AIR_ENGINE_CAPACITY_OBS.clear();
  C121_AIR_REALIZATION_FACTOR.newpair = 1.0;
  C121_AIR_REALIZATION_FACTOR.hubsite = 1.0;
  C121_AIR_REALIZATION_FACTOR.hubhub = 1.0;
  C117_AIR_LAST_DATE = -1;
  C117_AIR_LINE_STATE = {};
  C117_AIR_VEHICLE_STATE = {};
  {
    C69_BUILD_DATES = [];
    C69_PENDING_FOLLOWUPS = [];
    C69_BUILD_PASS_COUNT = 0;
    C69_LAST_AFFORDABLE = null;
    C69_LAST_KDEC_DATA = null;
    C69_CACHED_KDEC_DATE = -1;
    C69_CACHED_KDEC_VALUE = 0;
    C69_PLANE_CHOICE_CALLS = 0;
    C69_PLANE_CHOICE_DIFFER_ROI = 0;
    C69_PLANE_CHOICE_DIFFER_C69 = 0;
    if (C69_BOTTLENECK_PROBE) {
      OpexC73ResetLedger();
      C80_MARGINAL_FLOOR_LEDGER = { discards = 0, discard_profit = 0 };
      C80_AIR_INC_COUNTS.full = 0;
      C80_AIR_INC_COUNTS.targeted = 0;
      C80_AIR_INC_COUNTS.none = 0;
    }
  }
  {
    OpexC75BypassResetYearLedger();
  }
  {
    C75_PASS_DATES = [];
    OpexC75ResetYearLedger();
  }
  MONTHLY_FUNNEL = probePort;
  TENSION_PROBE = probePort;
  if (TENSION_PROBE) {
    PORTFOLIO_LOG = true;
  }
  PORTFOLIO_REFRESH_PROBE = probePort;
  C55_ORIGIN_RELAX_PROBE = probePort;
  if (C55_ORIGIN_RELAX_PROBE) {
    C55_ORIGIN_RELAX_LEDGER = {
      candidates_seen = 0, rejected_total = 0, both_served = 0, one_served = 0,
      one_served_pax = 0, one_served_freight = 0, duplicate_exact = 0,
      total_candidates_seen = 0, total_rejected_total = 0, total_both_served = 0,
      total_one_served = 0, total_one_served_pax = 0, total_one_served_freight = 0,
      total_duplicate_exact = 0,
    };
  }
  C55_PAX_TRACE_PROBE = probePort;
  if (C55_PAX_TRACE_PROBE) {
    C55_PAX_TRACE_LEDGER = {
      revalidated = 0, origin_blocked = 0,
      total_revalidated = 0, total_origin_blocked = 0,
    };
  }
  C60_TOWN_RATING_PROBE = probePort;
  if (C60_TOWN_RATING_PROBE) {
    C60_TOWN_RATING_LEDGER = {
      checks = 0, none = 0, ok = 0, very_poor = 0, appalling = 0,
      by_mode = {
        road = { checks = 0, refused = 0 },
        rail = { checks = 0, refused = 0 },
        air = { checks = 0, refused = 0 }
      }
    };
  }

  // 9. Evenements (dedie 1048576, groupe 128).
  local probeEvents = OpexProbeEnabled(1048576, 128);
  C52_AUTOREPLACE_LOG = probeEvents;
  if (C52_AUTOREPLACE_LOG) {
    C52_AUTOREPLACE_LEDGER = {
      events = 0, remap_line_vehicles = 0, remap_line_vehicle = 0, remap_scrap_vehicles = 0,
      untracked = 0, rail = 0, road = 0, air = 0, water = 0, unknown = 0,
      line_rail = 0, line_road = 0, line_air = 0, line_water = 0,
      total_events = 0, total_remap_line_vehicles = 0, total_remap_line_vehicle = 0,
      total_remap_scrap_vehicles = 0, total_untracked = 0,
      total_rail = 0, total_road = 0, total_air = 0, total_water = 0, total_unknown = 0,
    };
  }
  C52_EVENT_EXPOSURE_PROBE = probeEvents;
  if (C52_EVENT_EXPOSURE_PROBE) {
    local c52EventFields = [
      "vehicle_crashed", "crashed_train", "crashed_other", "vehicle_waiting_in_depot",
      "industry_open", "industry_close", "town_founded", "engine_available", "vehicle_lost",
      "subsidy_offer", "subsidy_offer_expired", "subsidy_awarded", "subsidy_expired",
      "vehicle_autoreplaced", "vehicle_unprofitable", "vehicle_unprofitable_distinct",
      "aircraft_dest_too_far", "station_first_vehicle", "road_reconstruction", "engine_preview",
      "exclusive_transport_rights", "other",
    ];
    local c52EventTotals = {};
    foreach (field in c52EventFields) c52EventTotals.rawset(field, 0);
    C52_EVENT_EXPOSURE_LEDGER = {
      fields = c52EventFields, totals = c52EventTotals, unprofitable_vehicles = {},
      vehicle_crashed = 0, crashed_train = 0, crashed_other = 0, vehicle_waiting_in_depot = 0,
      industry_open = 0, industry_close = 0, town_founded = 0, engine_available = 0,
      vehicle_lost = 0, subsidy_offer = 0, subsidy_offer_expired = 0, subsidy_awarded = 0,
      subsidy_expired = 0, vehicle_autoreplaced = 0, vehicle_unprofitable = 0,
      vehicle_unprofitable_distinct = 0, aircraft_dest_too_far = 0, station_first_vehicle = 0,
      road_reconstruction = 0, engine_preview = 0, exclusive_transport_rights = 0, other = 0,
    };
  }
  C52_CRASH_LOG = probeEvents;
  C52_UNPROFITABLE_LOG = probeEvents;
  C52_STATION_FIRST_VEHICLE_LOG = probeEvents;
  C56_TASK_TRACE = probeEvents;
  if (C56_TASK_TRACE) C56_LOOP_TICK_COUNT = 0;
  AIR_FLEET_PROBE = probeEvents;
  AIR_CATCHMENT_PROBE = probeEvents;
  EQUIPMENT_ROI_PROBE = probeEvents;
  C54_VEHICLE_ORDERS_PROBE = probeEvents;
  C78_SLOT_INTERCEPT_PROBE = probePort;

  /* --- 5. Pistes formellement abandonnees / constantes neutres verrouillees --- */
  /* R7 : zero global conserve ; le reglage defensif C121 ne retablit pas de plancher positif. */
  PORTFOLIO_FLOOR_PCT = 0;
  C67_TERRAIN_MAP = OpexGetSetting("c67_terrain_map") != 0;
  C67_WATER_EXPOSURE = OpexProbeEnabled(4194304, 64);
  C67_SLACK_HOOK = C67_TERRAIN_MAP || C67_WATER_EXPOSURE;
  /* C77 corrige est permanent et repose sur le socle du double registre. */
  C41_RAIL_LOST_SIGNAL_REPAIR = false;
  C41_RAIL_LOST_JUNCTION_REPAIR = false;
  local n75MultiCargo = OpexGetSetting("n75_multi_cargo");
  N75_MULTI_CARGO = (n75MultiCargo >= 1 && n75MultiCargo <= 2) ? n75MultiCargo : 0;
  N75_MC_LAST_MONTH = (N75_MULTI_CARGO > 0) ? N75_MC_SAVED_MONTH : -1;
  N75_MC_SAVED_MONTH = -1;
  local airSiteFunnel = OpexGetSetting("air_site_funnel");
  AIR_SITE_FUNNEL = (airSiteFunnel == 1) ? 1 : 0;
  if (AIR_SITE_FUNNEL > 0) OpexAirFunnelInstall();
  AIR_SITE_RANKED = OpexGetSetting("air_site_ranked") == 1 ? 1 : 0;
  if (AIR_SITE_RANKED > 0) {
    require("air_site_ranked.nut");
    OpexAirRankedInstall();
  }
  local eb2Fallback = OpexGetSetting("eb2_new_station_fallback");
  EB2_NEW_STATION_FALLBACK = (eb2Fallback != null && eb2Fallback > 0) ? 1 : 0;
  local railConsist = OpexGetSetting("rail_consist_pct");
  RAIL_CONSIST_PCT = (railConsist != null && railConsist > 100 && railConsist <= 400) ? railConsist : 100;
  V217_LAST_MONTH = -1;
  local v276 = OpexGetSetting("v276_cand_slices");
  V276_CAND_SLICES = (v276 == 3) ? (bigMap ? 2 : 0) : v276;
  V276_CATALOG_TASK = null;
  V276_CARGO_YEAR = -1;
  V276_CARGO_MONTH = -1;
  V276_CARGO_ORDER = null;
  AIR0310_SITE_VALIDITY_STATE = null;
  RAIL_DEPOT_COST = OpexGetSetting("rail_depot_cost") != 0;
  V131_TOWN_CLEARANCE = OpexGetSetting("v131_town_clearance") != 0;
  AIR_MAX_DISTANCE = 0;
  TRANSIT_COST_PERMILLE = 0;
  INFRA_AMORT_PCT = 0;
  PORTFOLIO_MAX_BATCH = 1;
  AIR_FLEET_BUFFER = 0;
  local eb14Mode = OpexGetSetting("eb14_progressive");
  EB14_PROGRESSIVE = eb14Mode >= 1;
  EB14_AIR_ROAD_YEAR_GUARD = eb14Mode >= 2;
  EB3_RAIL_FIRST_YEAR_PREFETCH = eb14Mode == 3;
  EB14_INITIAL_RAIL_JOB = false;
  EB14_TRACE_SIGN_COUNT = 0;
  EB14_TRACE_SIGN_TYPES = { E4 = 0, E5 = 0, E6 = 0 };
  EB14_TRACE_SELECTED = {};
  /* EB-14 ne force pas V278 sur 256x256 : son classement AIR popA*popB
   * est independant, et sa qualification historique concerne 1024x1024.
   * Respecter l'option v278_air_lazy_sites et l'auto du monde courant. */
  /* AIR doit etre reellement permis par la partie, cf. V261 ci-dessus. */
  local paxAirFirst = OpexGetSetting("pax_air_first");
  /* Bit 4 : seules les nouvelles navettes aeroportuaires sont admises pour
   * RAIL/ROUTE voyageurs, avec verification physique et preuve par ville. */
  PAX_AIR_FIRST_FEEDER_ONLY = MODE_AIR && (paxAirFirst & 4) != 0;
  PAX_AIR_FIRST_RAIL_OFF = MODE_AIR && ((paxAirFirst & 1) != 0
      || PAX_AIR_FIRST_FEEDER_ONLY);
  PAX_AIR_FIRST_AIR_UNBOUNDED = MODE_AIR && (paxAirFirst & 2) != 0;
  PFIX_ROAD1Y_WEAK_FIX = OpexGetSetting("pfix_road1y_weak_fix") == 1;
  PFIX_PO01C_ROAD_PAX = OpexGetSetting("pfix_po01c_road_pax") == 1;
  PFIX_V284_GROW_SCORE = OpexGetSetting("pfix_v284_grow_score") == 1;
  PFIX_V257_ORIGIN_INDUSTRY = OpexGetSetting("pfix_v257_origin_industry") == 1;
  PFIX_PO01C_ABANDON_ACK = OpexGetSetting("pfix_po01c_abandon_ack") == 1;
  PFIX_CATALOG_MODE_CUT = OpexGetSetting("pfix_catalog_mode_cut") == 1;
}

/* Read once before class instantiation: Squirrel forbids replacing class methods later. */
function OpexLoadBusDistrictSettings()
{
  PO02_INDEPENDENT_EXPIRY = OpexGetSetting("po02_independent_expiry");
  if (PO02_INDEPENDENT_EXPIRY < 0 || PO02_INDEPENDENT_EXPIRY > 3) PO02_INDEPENDENT_EXPIRY = 3;
  /* Appele au chargement, avant Start : MODE_* n'est pas encore pose. */
  FAIR_PLAY_COURTESY = OpexGetSetting("fair_play_courtesy") == 1;
  local road1yRoadOnly = OpexGetSetting("mode_road") != 0
      && OpexGetSetting("mode_air") == 0
      && OpexGetSetting("mode_rail") == 0
      && OpexGetSetting("mode_water") == 0;
  ROAD1Y_BUS_FIXES = OpexGetSetting("road1y_bus_fixes");
  if (ROAD1Y_BUS_FIXES < 0 || ROAD1Y_BUS_FIXES > 13) ROAD1Y_BUS_FIXES = 0;
  if (!road1yRoadOnly) ROAD1Y_BUS_FIXES = 0;
  ROAD1Y_EXTRA_STOPS = OpexGetSetting("road1y_extra_stops");
  if (ROAD1Y_EXTRA_STOPS < 0) ROAD1Y_EXTRA_STOPS = 0;
  if (ROAD1Y_EXTRA_STOPS > 3) ROAD1Y_EXTRA_STOPS = 3;
  if (!road1yRoadOnly) ROAD1Y_EXTRA_STOPS = 0;
  ROAD1Y_PAX_SITES = OpexGetSetting("road1y_pax_sites") == 1;
  if (!road1yRoadOnly) ROAD1Y_PAX_SITES = false;
  ROAD1Y_SPREAD_STOPS = OpexGetSetting("road1y_spread_stops");
  if (ROAD1Y_SPREAD_STOPS < 0) ROAD1Y_SPREAD_STOPS = 0;
  if (ROAD1Y_SPREAD_STOPS > 4) ROAD1Y_SPREAD_STOPS = 4;
  if (!road1yRoadOnly) ROAD1Y_SPREAD_STOPS = 0;
  ROAD1Y_MAIL_ON_PAX = OpexGetSetting("road1y_mail_on_pax") == 1;
  if (!road1yRoadOnly) ROAD1Y_MAIL_ON_PAX = false;
  ROAD1Y_WEAK = OpexGetSetting("road1y_weak");
  if (ROAD1Y_WEAK < 0 || ROAD1Y_WEAK > 30) ROAD1Y_WEAK = 0;
  if (!road1yRoadOnly) ROAD1Y_WEAK = 0;
  ROAD1Y_NEXT = OpexGetSetting("road1y_next");
  if (ROAD1Y_NEXT < 0 || ROAD1Y_NEXT > 192) ROAD1Y_NEXT = 0;
  if (!road1yRoadOnly) ROAD1Y_NEXT = 0;
  ROAD1Y_MAIL2 = OpexGetSetting("road1y_mail2");
  if (ROAD1Y_MAIL2 < 0 || ROAD1Y_MAIL2 > 25) ROAD1Y_MAIL2 = 0;
  if (!road1yRoadOnly) ROAD1Y_MAIL2 = 0;
  ROAD1Y_MAIL2_YEARS = OpexGetSetting("road1y_mail2_years");
  if (ROAD1Y_MAIL2_YEARS < 0 || ROAD1Y_MAIL2_YEARS > 20) ROAD1Y_MAIL2_YEARS = 0;
  if (!road1yRoadOnly) ROAD1Y_MAIL2_YEARS = 0;
  ROAD1Y_NEXT3 = OpexGetSetting("road1y_next3");
  if (ROAD1Y_NEXT3 < 0 || ROAD1Y_NEXT3 > 96) ROAD1Y_NEXT3 = 0;
  if (!road1yRoadOnly) ROAD1Y_NEXT3 = 0;
  PFIX_ROAD1Y_WEAK_FIX = OpexGetSetting("pfix_road1y_weak_fix") == 1;
  PFIX_PO01C_ROAD_PAX = OpexGetSetting("pfix_po01c_road_pax") == 1;
  PFIX_V284_GROW_SCORE = OpexGetSetting("pfix_v284_grow_score") == 1;
  PFIX_V257_ORIGIN_INDUSTRY = OpexGetSetting("pfix_v257_origin_industry") == 1;
  PFIX_PO01C_ABANDON_ACK = OpexGetSetting("pfix_po01c_abandon_ack") == 1;
  PFIX_CATALOG_MODE_CUT = OpexGetSetting("pfix_catalog_mode_cut") == 1;
  ROAD1Y_PAX_MIN = OpexGetSetting("road1y_pax_min");
  if (ROAD1Y_PAX_MIN < 0 || ROAD1Y_PAX_MIN > 100) ROAD1Y_PAX_MIN = 0;
  if (!road1yRoadOnly) ROAD1Y_PAX_MIN = 0;
  ROAD1Y_FREIGHT = OpexGetSetting("road1y_freight");
  if (ROAD1Y_FREIGHT < 0 || ROAD1Y_FREIGHT > 30) ROAD1Y_FREIGHT = 0;
  if (!road1yRoadOnly) ROAD1Y_FREIGHT = 0;
  ROAD1Y_TRUCK_FLEET = OpexGetSetting("road1y_truck_fleet");
  if (ROAD1Y_TRUCK_FLEET < 0 || ROAD1Y_TRUCK_FLEET > 1) ROAD1Y_TRUCK_FLEET = 0;
  if (!road1yRoadOnly) ROAD1Y_TRUCK_FLEET = 0;
  { // Definitions also needed for saved markers after ON -> OFF.
    require("bus_districts.nut");
    require("bus_districts_overrides.nut");
  }
}
