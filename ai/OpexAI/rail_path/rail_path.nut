// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* PUB-05b : A* ferroviaire d'OpexAI, ecrit de zero pour la publication sous GPL v3.
 *
 * Conception independante, a partir des appelants d'OpexAI (builder_rail.nut, task_rail.nut,
 * rail_loop.nut, v233_long_good.nut, probe_v307.nut), des contrats des tests sweeps/ et de
 * l'API NoAI d'OpenTTD 15 (AIList, AITile, AIRail, AIRoad, AIBridge, AITunnel, AIMap).
 * Aucune bibliotheque NoAI de recherche de chemin n'y est reprise.
 *
 * INTERFACE (utilisee par les appelants)
 *   local pf = OpexNewRailPathfinder();
 *   pf.cost.<champ> = valeur;            table simple, champs listes dans le constructeur
 *   pf._v214RouteDist = d;               facultatif : distance du trajet complet (recherche
 *                                        segmentee) pour la regle du coude serre
 *   pf.SetGuide(table);                  facultatif : couloir guide de la sonde V307
 *   pf._sourceStructs = false;           facultatif : aucun ouvrage ne part d'un lead source
 *                                        (sonde inverse V294f : relu a l'envers, ce serait un
 *                                        saut d'arrivee refuse par OpexRailPathGeometryIssue)
 *   pf.InitializePath(sources, goals, ignored);
 *       sources : [lead, station_exit] ou [lead, station_exit, approach] ; une source de
 *                 segment [front, previous] peut avoir previous a plus d'une tuile (sortie
 *                 d'un pont ou d'un tunnel deja choisi) : front repart alors tout droit.
 *                 [front, previous, avant, true, avant2] : les cases d'avant du prefixe
 *                 donnent la direction d'arrivee (interdit des 90 degres, coude serre) mais
 *                 ne sont pas rendues. Un lead source occupe (rail, maison, eau) est ignore.
 *       goals   : [lead, station_exit] ; le chemin rendu finit par lead puis station_exit.
 *       ignored : tuiles que la voie ne doit ni occuper ni enjamber.
 *   pf.FindPath(n)  -> false (pas fini), null (file vide : aucun chemin sous max_cost),
 *                      ou le dernier noeud du chemin. Reprenable : appeler de nouveau
 *                      reprend exactement ou la tranche precedente s'est arretee.
 *   pf.LastConsumed()           iterations (retraits de la file) du dernier FindPath.
 *   pf.FrontierAlternatives(k)  k meilleurs noeuds ouverts distincts (coupure de segment),
 *                               sans modifier la file : ni source, ni sortie d'ouvrage, ni
 *                               boucle, pieces sur sol plat verifiees (points 6 et 13).
 *   pf.TraceCost(tiles)         cout d'un trace donne avec la meme fonction de cout.
 *   Noeud rendu : GetTile(), GetParent(), GetCost(), GetDirection().
 *   Chaine rendue : [approach,] station_exit A, lead A, ..., lead B, station_exit B.
 *
 * CHOIX DE CONCEPTION
 * 1. L'opcode est la ressource rare (ai/OpexAI/CLAUDE.md). La boucle chaude ne cree aucun
 *    objet Squirrel et n'appelle aucune fonction de rappel : les noeuds sont quatre tableaux
 *    paralleles (tuile, parent, g, code) et l'objet chemin n'est construit qu'une fois, a la
 *    fin. La file ouverte est une AIList triee par valeur croissante : insertion et retrait
 *    sont faits en C++ (quelques opcodes chacun).
 * 2. Departage des egalites : l'identifiant d'un noeud dans la file est l'oppose de son
 *    indice. AIList range a valeur egale par identifiant croissant, donc le noeud le plus
 *    recent sort le premier (LIFO). Sur un plateau de f egal (terrain degage, heuristique
 *    exacte) la recherche avance en profondeur vers le but au lieu d'elargir un front.
 * 3. Une seule table par tuile (_tab) porte, dans un entier : la classe de la tuile
 *    (constructible, route, bloquee, interdite), sa pente utile, l'heuristique ponderee et
 *    les etats deja developpes. Une tuile coute donc ses appels d'API une seule fois par
 *    recherche ; ensuite une lecture de table suffit au voisinage, a l'heuristique et a la
 *    fermeture.
 * 4. Etat d'un noeud = (tuile, deux derniers pas, coude en attente). Les deux derniers pas
 *    decident de l'interdit des virages a 90 degres et du cout de sortie de diagonale ; le pas
 *    d'avant ne compte que pour le coude serre (droite, coin, droite), d'ou un seul bit
 *    "coude en attente". Au plus 20 etats par tuile, fermes separement : la fermeture est
 *    exacte pour la fonction de cout (un etat en attente n'est domine que par le meme etat
 *    sans attente, qui le ferme aussi). La recherche peut donc revenir sur une tuile dans un
 *    autre sens quand le premier mene a une impasse (abords d'un quai, couloir etroit).
 * 5. Couts de pas precalcules : une table de 512 entrees (code du noeud x pas suivant) donne
 *    -1 pour un pas interdit (demi-tour, 90 degres) ou le cout du morceau de voie pose sur la
 *    tuile quittee : tuile droite ou diagonale, sortie de diagonale (V214_RAIL_TURN_COST,
 *    entree gratuite), coude serre droite-coin-droite (V214_RAIL_TIGHT_TURN_COST, ramene a
 *    100 sous 40 tuiles de trajet). A V214_RAIL_TURN_COST = 0, chaque changement de 45 degres
 *    paie cost.turn. La boucle chaude fait une lecture de tableau au lieu de comparaisons.
 *    Les tables sont partagees entre recherches de memes couts (OPEX_RAIL_PATH_TABLES) :
 *    les construire coute environ dix mille opcodes, une fois par jeu de couts.
 * 6. Validite des morceaux : sur une tuile constructible et plate, toute piece de voie est
 *    en principe posable et la recherche n'en teste aucune. Sur une pente, une cote ou une
 *    route, la piece exacte (precedente, courante, suivante) est verifiee par AIRail.BuildRail
 *    sous AITestMode : fondations, passages a niveau et demi-tuiles de cote sont juges par le
 *    jeu lui-meme. Exceptions au sol plat (sol sous le tablier d'un pont, qui reste MP_CLEAR et
 *    constructible ; arbre que la ville refuse d'abattre) : le chemin retenu rejoue ses pieces
 *    sur sol plat ; une piece refusee (hors manque d'argent) rend sa tuile testee et la
 *    recherche repart de zero, OPEX_RP_MAX_RESTARTS fois au plus. Cout : une commande de
 *    test par tuile plate du chemin, une fois par recherche.
 *    Les tuiles de rail existantes, gares et depots sont bloquees : la voie ne fusionne
 *    jamais avec une autre (OpexJoinPathIsDedicated l'exige pour la voie 2).
 * 7. Pente : un morceau DROIT monte ou descend dans l'axe d'une pente inclinee, et dans les
 *    deux axes sur un coin leve seul ou une pente raide (fondation inclinee) ; c'est lui qui
 *    paie cost.slope. Diagonales et autres pentes recoivent une fondation plate. Passage a
 *    niveau : cost.level_crossing sur la tuile de route.
 * 8. Ponts : cherches quand la tuile droit devant n'est pas constructible (eau, rail, route,
 *    maison...) ou est une cote. La premiere tuile d'atterrissage constructible est testee par
 *    AIBridge.BuildBridge (deux essais au plus), avec le type que la pose choisira (le plus
 *    rapide), resultat garde par (tuile, sens). Tunnels : cherches quand la tuile courante est
 *    une pente inclinee dans le sens de marche ; AITunnel.GetOtherTunnelEnd donne l'autre
 *    bout, AITunnel.BuildTunnel le valide. Aucun ouvrage ne part d'une route (la tete la
 *    detruirait) ni n'atterrit ailleurs que sur un sol constructible. Cout d'un ouvrage de len
 *    pas : len * (cost.tile + cost.*_per_tile), plus *_ex par pas au-dela de 7 et *_ex2
 *    au-dela de 11, plus le pas d'entree (sortie de diagonale, coude serre) ; sous guide, le
 *    meme facteur que les pas ordinaires. Un pont n'enjambe ni n'atteint une tuile interdite ;
 *    un tunnel passe dessous et seule sa sortie est controlee. La sortie d'un ouvrage repart
 *    tout droit et ne peut pas etre le lead B (OpexRailPathGeometryIssue refuse ce saut).
 * 9. Heuristique : cout octile minimal (cost.tile par pas droit, deux diagonales par pas
 *    oblique), multipliee par cost.astar_weight_pct / 100 et mise en cache par tuile. Pour
 *    plusieurs buts, soit B le rectangle englobant des leads d'arrivee et tc la tuile ramenee
 *    dans B (coordonnees bornees) : |x - gx| = dx + |xc - gx| pour tout lead g de B, donc
 *    min Manhattan(t) = Manhattan(t, B) + min Manhattan(tc), EXACT, avec une table par case
 *    de B remplie a la demande (une boucle sur les leads par case, puis une lecture). La
 *    distance max minimale est minoree par max(dx + min|xc - gx|, dy + min|yc - gy|), deux
 *    tables par axe. h garde le gradient lateral vers le lead le plus proche, sans appel
 *    natif par tuile. Admissibilite a 100 % : un pas isole qui change de sens coute une
 *    diagonale D au lieu de T, donc le cout jusqu'au lead peut etre l'octile moins (T - D) ;
 *    le but est la sortie de quai, un pas de plus qui coute au moins D >= T - D (deux
 *    diagonales >= une droite), donc h minore le cout restant. Si deux diagonales coutaient
 *    moins qu'une droite, h = Manhattan * D. Sous guide (sonde V307, x0,5 dans le couloir),
 *    h n'est plus minorant : la sonde suit le couloir en glouton, c'est voulu. Mesure
 *    (smoke rail seul, graine 42) : le
 *    rectangle seul economisait ~40 % d'opcodes par iteration mais, sans gradient lateral,
 *    une sonde V294f (manh 190) epuisait son plafond de 300 iterations la ou les minima
 *    exacts (deux AIList.Valuate par tuile, ~150 opcodes) trouvaient en 208.
 * 10. max_cost borne g, pas f. Un chemin ne repasse jamais par une de ses tuiles : quand
 *    une tuile deja developpee est retiree dans un autre etat, ses ancetres sont remontes
 *    tant que leur g reste au-dessus du plus petit g ayant ferme cette tuile (les g
 *    croissent strictement le long d'une chaine), ce qui borne la remontee a la boucle
 *    eventuelle.
 * 11. Rien n'est sauvegarde : AIList n'est pas serialisable et persist.nut abandonne une
 *    recherche en cours a la sauvegarde. Aucune fermeture, aucune fonction anonyme.
 * 12. Arrivee : retirer le lead B ne termine pas la recherche. Chaque sortie de quai permise
 *    depuis l'etat du lead (interdits, coude serre, route, pente, guide, max_cost, piece
 *    testee hors sol plat) devient un noeud de la file a f = g + pas final ; la recherche
 *    finit quand le premier sort. Le dernier pas compte donc comme les autres et deux etats
 *    d'arrivee, ou deux quais partageant un lead, sont departages par le cout complet.
 * 13. Coupure de segment : FrontierAlternatives ne rend ni une source (aucun progres), ni une
 *    sortie d'ouvrage (le segment suivant repartirait d'un saut que la pose ne relie pas), ni
 *    un noeud qui repasse sur une tuile de ses ancetres (meme remontee que le point 10), ni
 *    un noeud dont une piece sur sol plat est refusee (point 6). */

const OPEX_RP_LAND = 1;          /* constructible : terrain nu, arbres, champs, cote */
const OPEX_RP_ROAD = 2;          /* route : passage a niveau valide par commande */
const OPEX_RP_PLAIN = 4;         /* constructible et plat : toute piece y est posable */
const OPEX_RP_GUIDE = 32;        /* couloir guide de la sonde V307 */
const OPEX_RP_COAST = 64;        /* table des tuiles : cote, un pont peut passer par-dessus */
const OPEX_RP_STRUCT = 64;       /* code de noeud : sortie de pont ou de tunnel */
const OPEX_RP_FORBID = 128;      /* table des tuiles : interdite par l'appelant, bout de quai */
const OPEX_RP_EXIT = 128;        /* code de noeud : sortie de quai, chemin complet (point 12) */
const OPEX_RP_CLOSED = 4294967040; /* bits 8 a 31 : etats deja developpes sur la tuile */
const OPEX_RP_H_SHIFT = 32;      /* bits 32 et plus : heuristique ponderee */
/* Taille maximale (cases) du rectangle des buts tabule ; au-dela, rectangle seul (minorant).
 * 64 x 64 couvre les quais d'une ville a STATION_SEARCH_RADIUS = 30 ; les cases sont
 * remplies a la demande, seule l'allocation depend de la taille. */
const OPEX_RP_BOX_CELLS = 4096;
/* Relances au plus apres une piece refusee sur sol plat (point 6). */
const OPEX_RP_MAX_RESTARTS = 3;

/* Noeud du chemin rendu, construit une seule fois a la fin de la recherche. */
class OpexRailPathNode
{
  _up = null;
  _tile = -1;
  _cost = 0;
  _dir = -1;

  constructor(up, tile, cost, dir)
  {
    this._up = up;
    this._tile = tile;
    this._cost = cost;
    this._dir = dir;
  }

  function GetTile() { return this._tile; }
  function GetParent() { return this._up; }
  function GetCost() { return this._cost; }
  /* Pas d'entree : 0 = +x, 1 = -x, 2 = +y, 3 = -y. */
  function GetDirection() { return this._dir; }
}

class OpexRailPath
{
  cost = null;
  _v214RouteDist = -1;
  _guide = null;
  _sourceStructs = true;

  _args = null;
  _unplain = null;
  _restarts = 0;
  _mx = 0;
  _offs = null;
  _tile = null;
  _par = null;
  _g = null;
  _code = null;
  _open = null;
  _tab = null;
  _gFirst = null;
  _goalExits = null;
  _goalCount = 0;
  _gx = null;
  _gy = null;
  _boxW = 0;
  _cellM = null;
  _minA = null;
  _minB = null;
  _goalMinX = 0;
  _goalMaxX = 0;
  _goalMinY = 0;
  _goalMaxY = 0;
  _trans = null;
  _next = null;
  _bitOf = null;
  _closeOf = null;
  _slopeInfo = null;
  _bridgeAt = null;
  _bridgeType = null;
  _tunnelAt = null;
  _aW = 0;
  _bW = 0;
  _costTile = 100;
  _costDiag = 70;
  _costTurn = 50;
  _costSlope = 100;
  _costCrossing = 500;
  _bridgePer = 150;
  _bridgeEx = 0;
  _bridgeEx2 = 0;
  _tunnelPer = 120;
  _tunnelEx = 0;
  _tunnelEx2 = 0;
  _maxBridge = 6;
  _maxTunnel = 6;
  _maxCost = 2000000000;
  _v214Turn = 0;
  _v214Tight = 0;
  _finished = false;
  _result = null;
  _consumed = 0;
  _nPops = 0;
  _nProbes = 0;
  _nTests = 0;
  _nBridgeTests = 0;
  _nTunnelTests = 0;
  _nStructs = 0;
  _nScans = 0;
  _nScanSteps = 0;
  _nOps = 0;
  _nStructOk = 0;
  _nStructBad = 0;
  _initOps = 0;

  constructor()
  {
    /* Valeurs par defaut ; builder_rail.nut (OpexV294ApplyRailCosts) en fixe la plupart.
     * Les longueurs d'ouvrage comptent les deux tetes. Un champ inconnu fait echouer
     * l'affectation (table sans emplacement), ce qui attrape les fautes de frappe. */
    this.cost = {
      tile = 100,
      diagonal_tile = 70,
      turn = 50,
      slope = 100,
      level_crossing = 500,
      bridge_per_tile = 150,
      bridge_per_tile_ex = 0,
      bridge_per_tile_ex2 = 0,
      tunnel_per_tile = 120,
      tunnel_per_tile_ex = 0,
      tunnel_per_tile_ex2 = 0,
      max_bridge_length = 6,
      max_tunnel_length = 6,
      max_cost = 2000000000,
      astar_weight_pct = V91_ASTAR_WEIGHT_PCT,
    };
  }

  function SetGuide(guide)
  {
    this._guide = guide;
  }

  function LastConsumed()
  {
    return this._consumed;
  }

  function InitializePath(sources, goals, ignored = [])
  {
    local mark = DECISION_LOG ? OpexOpsMeasureBegin() : null;
    this._args = [sources, goals, ignored];
    this._unplain = {};
    this._restarts = 0;
    this._ResetCounters();
    this._Init();
    if (mark != null) this._initOps = OpexOpsMeasureEnd(mark);
  }

  /* Corps de l'initialisation, rejoue a l'identique par une relance (point 6). */
  function _Init()
  {
    local sources = this._args[0];
    local goals = this._args[1];
    local ignored = this._args[2];
    /* Reglages V214 lus une fois par recherche, avant tout cout. */
    this._v214Turn = V214_RAIL_TURN_COST;
    this._v214Tight = V214_RAIL_TIGHT_TURN_COST;
    if (this._v214RouteDist < 0) this._v214RouteDist = this._RouteDistance(sources, goals);
    if (this._v214RouteDist >= 0 && this._v214RouteDist < 40 && this._v214Tight > 100) this._v214Tight = 100;
    this._Prepare();
    local tab = this._tab;
    local mx = this._mx;

    /* Les leads des plans restent libres, meme listes dans ignored ou sur le bout de quai d'un
     * autre plan : ce sont les extremites du chemin. Une tuile deja occupee reste bloquee par
     * _Probe. */
    local leads = {};
    foreach (node in sources) leads[node[0]] <- true;
    foreach (node in goals) leads[node[0]] <- true;
    if (ignored != null) {
      foreach (t in ignored) {
        if (!(t in leads)) tab[t] <- OPEX_RP_FORBID;
      }
    }

    this._gx = [];
    this._gy = [];
    foreach (node in goals) {
      local lead = node[0];
      local ex = node[1];
      local dir = this._DirIndex(ex - lead);
      if (dir < 0) continue;
      if (!(lead in this._goalExits)) {
        this._goalExits[lead] <- [];
        local x = lead % mx;
        local y = lead / mx;
        if (this._goalCount == 0 || x < this._goalMinX) this._goalMinX = x;
        if (this._goalCount == 0 || x > this._goalMaxX) this._goalMaxX = x;
        if (this._goalCount == 0 || y < this._goalMinY) this._goalMinY = y;
        if (this._goalCount == 0 || y > this._goalMaxY) this._goalMaxY = y;
        this._goalCount++;
        this._gx.push(x);
        this._gy.push(y);
      }
      this._goalExits[lead].push(ex);
      this._goalExits[lead].push(dir);
      /* Le bout de quai sera la gare : la voie n'y passe jamais. */
      if (!(ex in leads)) tab[ex] <- OPEX_RP_FORBID;
    }

    /* Tables de l'heuristique (point 9), remplies a la demande par _Probe. */
    local w = this._goalMaxX - this._goalMinX + 1;
    local hh = this._goalMaxY - this._goalMinY + 1;
    this._boxW = w;
    if (this._goalCount > 1 && w * hh <= OPEX_RP_BOX_CELLS) {
      this._cellM = array(w * hh, -1);
      this._minA = array(w, -1);
      this._minB = array(hh, -1);
    }

    /* Pieces refusees sur sol plat par un chemin precedent (point 6) : tuiles testees. */
    foreach (t, unused in this._unplain) {
      if (t in tab) continue;
      tab[t] <- this._Probe(t) & ~OPEX_RP_PLAIN;
    }

    this._open = AIList();
    this._open.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
    foreach (node in sources) {
      local lead = node[0];
      local prev = node[1];
      local dist = AIMap.DistanceManhattan(prev, lead);
      if (dist < 1) continue;
      local d1 = this._DirIndex((lead - prev) / dist);
      if (d1 < 0 || prev + this._offs[d1] * dist != lead) continue;
      /* Lead occupe (rail existant, maison, eau) : poser depuis lui ferait un aiguillage sur
       * une autre voie ou echouerait. Les leads ne sont jamais interdits (voir plus haut). */
      local e = (lead in tab) ? tab[lead] : this._Probe(lead);
      if ((e & 3) == 0) continue;
      local d0 = d1;
      local dm = d1;
      local up = 0;
      if (dist == 1 && node.len() >= 4 && node[3] == true) {
        /* Source de segment : les cases d'avant du prefixe fixent l'etat d'arrivee (interdit
         * des 90 degres, coude serre) ; elles sont deja posees au prefixe, donc non rendues. */
        local da = this._DirIndex(prev - node[2]);
        if (da >= 0 && da != (d1 ^ 1)) {
          d0 = da;
          dm = da;
          if (node.len() >= 5 && node[4] != null) {
            local db = this._DirIndex(node[2] - node[4]);
            if (db >= 0 && db != (da ^ 1)) dm = db;
          }
        }
      } else if (dist == 1 && V233_LONG_GOOD > 0 && node.len() >= 3 && node[2] != null) {
        /* Approche (V233) : vrai grand-parent, pour que le premier pas respecte l'interdit des
         * 90 degres ; elle ouvre le chemin rendu, que v233_long_good.nut retire ensuite. */
        local approach = node[2];
        local da = this._DirIndex(prev - approach);
        if (da >= 0 && da != (d1 ^ 1)) {
          d0 = da;
          dm = da;
          up = this._AddNode(approach, 0, 0, da);
          if (!(approach in leads)) tab[approach] <- OPEX_RP_FORBID;
        }
      }
      local root = this._AddNode(prev, up, 0, d0);
      if (!(prev in leads)) tab[prev] <- OPEX_RP_FORBID;
      local code = (dist > 1) ? (OPEX_RP_STRUCT | (d1 << 4) | (d1 << 2) | d1)
                              : ((dm << 4) | (d0 << 2) | d1);
      local m = this._AddNode(lead, root, 0, code);
      this._open.AddItem(-m, e >> OPEX_RP_H_SHIFT);
    }
  }

  function FindPath(iterations)
  {
    this._consumed = 0;
    if (this._finished) return this._result;
    if (this._open == null) return null;
    if (iterations < 1) iterations = 1;
    local mark = DECISION_LOG ? OpexOpsMeasureBegin() : null;
    local open = this._open;
    local tiles = this._tile;
    local pars = this._par;
    local gs = this._g;
    local codes = this._code;
    local tab = this._tab;
    local gFirst = this._gFirst;
    local goals = this._goalExits;
    local trans = this._trans;
    local nexts = this._next;
    local bitOf = this._bitOf;
    local closeOf = this._closeOf;
    local offs = this._offs;
    local maxCost = this._maxCost;
    local guided = this._guide != null;
    local srcStruct = this._sourceStructs;
    /* Tests de pose (pentes, routes, ponts, tunnels) : jamais de construction reelle. */
    local testMode = AITestMode();
    local pops = 0;
    while (pops < iterations) {
      local id = open.Begin();
      if (id >= 0) {
        /* Identifiants toujours negatifs : file vide, tout l'atteignable sous max_cost est vu. */
        this._finished = true;
        this._result = null;
        break;
      }
      open.RemoveItem(id);
      pops++;
      local n = -id;
      local c = codes[n];
      /* Sortie de quai : le chemin complet le moins cher sort ici (point 12). Une relance
       * (point 6) remplace toutes les tables : la tranche s'arrete la. */
      if (c >= OPEX_RP_EXIT) {
        this._Complete(n);
        break;
      }
      local t = tiles[n];
      local ent = tab[t];
      if ((ent & bitOf[c]) != 0) continue;
      local g = gs[n];
      if ((ent & OPEX_RP_CLOSED) == 0) {
        gFirst[t] <- g;
      } else {
        local gf = gFirst[t];
        if (g < gf) {
          gFirst[t] = g;
        } else {
          /* Anti-boucle : un ancetre sur t a un g >= gf ; au-dessous, inutile de remonter. */
          local a = pars[n];
          local steps = 0;
          while (a > 0 && gs[a] >= gf && tiles[a] != t) {
            a = pars[a];
            steps++;
          }
          this._nScans++;
          this._nScanSteps += steps;
          if (a > 0 && tiles[a] == t) continue;
        }
      }
      tab[t] = ent | closeOf[c];

      local d1 = c & 3;
      local cb = c << 2;
      local cc0 = (c & 15) << 2;
      /* Tuile plate et constructible, ou tete de sortie d'ouvrage : aucun test de pose. */
      local free = (ent & OPEX_RP_PLAIN) | (c & OPEX_RP_STRUCT);
      local pt = -1;
      local extra = 0;
      local extraStraight = 0;
      if (free == 0) {
        pt = tiles[pars[n]];
        /* Bits 3-4 : axes ou la voie droite monte (point 7) ; want = axe du pas d'entree. */
        local ax = (ent >> 3) & 3;
        local want = (d1 >> 1) + 1;
        if ((ent & 3) == OPEX_RP_ROAD) extra = this._costCrossing;
        else if (ax == want && (g > 0 || srcStruct)) this._TryTunnel(n, t, c, g);
        if ((ax & want) != 0) extraStraight = this._costSlope;
      }
      foreach (dn in nexts[c]) {
        local nt = t + offs[dn];
        local e2 = (nt in tab) ? tab[nt] : this._Probe(nt);
        /* Obstacle, route ou cote devant : pont tente tout droit (point 8). */
        if ((e2 & (OPEX_RP_LAND | OPEX_RP_COAST)) != OPEX_RP_LAND) {
          if (dn == d1 && free < OPEX_RP_STRUCT && (ent & 3) != OPEX_RP_ROAD && (g > 0 || srcStruct))
            this._TryBridge(n, t, c, g);
          if ((e2 & 3) == 0) continue;
        }
        local cc = cc0 | dn;
        if ((e2 & bitOf[cc]) != 0) continue;
        local ng = g + trans[cb + dn];
        if (free == 0) {
          this._nTests++;
          if (!AIRail.BuildRail(pt, t, nt)) continue;
          ng += extra;
          if (dn == d1) ng += extraStraight;
        }
        if (guided) ng = ((e2 & OPEX_RP_GUIDE) != 0) ? g + (ng - g) / 2 : g + (ng - g) * 2;
        if (ng > maxCost) continue;
        local m = tiles.len();
        tiles.push(nt);
        pars.push(n);
        gs.push(ng);
        codes.push(cc);
        open.AddItem(-m, ng + (e2 >> OPEX_RP_H_SHIFT));
      }
      if (t in goals) this._PushExits(n, t, c, g, free, pt, extra, extraStraight);
    }
    if (!this._finished) this._CompleteAtHead();
    this._consumed = pops;
    this._nPops += pops;
    if (mark != null) this._nOps += OpexOpsMeasureEnd(mark);
    if (!this._finished) return false;
    this._LogEnd(this._result == null ? "NOPA" : "OK");
    this._open = null;
    return this._result;
  }

  /* Noeuds ouverts encore valides, du meilleur au moins bon, un par (tuile, pas d'entree),
   * filtres comme le dit le point 13. Parcours de l'AIList sans retrait : la file reste
   * intacte. L'appelant n'en garde que quelques-uns : maxAlternatives borne les chaines
   * materialisees. */
  function FrontierAlternatives(maxAlternatives)
  {
    local out = [];
    local open = this._open;
    if (open == null) return out;
    local seen = {};
    local testMode = AITestMode();
    for (local id = open.Begin(); !open.IsEnd() && out.len() < maxAlternatives; id = open.Next()) {
      local n = -id;
      local c = this._code[n];
      if (c >= OPEX_RP_EXIT || (c & OPEX_RP_STRUCT) != 0 || this._g[n] == 0) continue;
      local t = this._tile[n];
      local ent = this._tab[t];
      if ((ent & this._bitOf[c]) != 0) continue;
      local key = t * 4 + (c & 3);
      if (key in seen) continue;
      if (this._Revisits(n, t, ent)) continue;
      if (this._PlainFailures(n).len() > 0) continue;
      seen[key] <- true;
      out.push(this._Materialize(n));
    }
    this._LogEnd("CUT");
    return out;
  }

  /* Cout d'un trace complet (sonde V307) avec les memes regles que FindPath, sans guide ni
   * validation : sortie de quai -> lead gratuit (g = 0 a la source), entree d'ouvrage par le
   * meme pas que _PushStruct. -1 si le trace est vide ou contient un saut non aligne.
   * Reinitialise l'instance : a appeler sur une instance neuve, jamais en cours de recherche. */
  function TraceCost(tiles)
  {
    if (tiles == null || tiles.len() == 0) return -1;
    this._v214Turn = V214_RAIL_TURN_COST;
    this._v214Tight = V214_RAIL_TIGHT_TURN_COST;
    if (AIMap.DistanceManhattan(tiles[0], tiles[tiles.len() - 1]) < 40 && this._v214Tight > 100) this._v214Tight = 100;
    this._guide = null;
    this._Prepare();
    local total = 0;
    local code = -1;
    for (local i = 1; i < tiles.len(); i++) {
      local a = tiles[i - 1];
      local b = tiles[i];
      local dist = AIMap.DistanceManhattan(a, b);
      if (dist == 0) continue;
      if (dist > 1) {
        local d = this._DirIndex((b - a) / dist);
        if (d < 0 || a + this._offs[d] * dist != b) return -1;
        local enter = (code < 0) ? this._costTile : this._trans[(code << 2) + d];
        if (enter < 0) enter = this._costTile + this._v214Tight;
        total += enter + this._StructCost(dist, AITunnel.GetOtherTunnelEnd(a) != b);
        code = OPEX_RP_STRUCT | (d << 4) | (d << 2) | d;
        continue;
      }
      local dn = this._DirIndex(b - a);
      if (dn < 0) return -1;
      if (code < 0) {
        code = (dn << 4) | (dn << 2) | dn;
        continue;
      }
      local step = this._trans[(code << 2) + dn];
      if (step < 0) step = this._costTile + this._v214Tight;
      if ((code & OPEX_RP_STRUCT) == 0) {
        local e = (a in this._tab) ? this._tab[a] : this._Probe(a);
        if ((e & 3) == OPEX_RP_ROAD) step += this._costCrossing;
        if (dn == (code & 3) && ((e >> 3) & ((dn >> 1) + 1)) != 0) step += this._costSlope;
      }
      total += step;
      code = ((code & 15) << 2) | dn;
    }
    return total;
  }

  /* ---- interne ---- */

  function _Prepare()
  {
    local mx = AIMap.GetMapSizeX();
    this._mx = mx;
    this._offs = [1, -1, mx, -mx];
    local cost = this.cost;
    this._costTile = cost.tile;
    this._costDiag = cost.diagonal_tile;
    this._costTurn = cost.turn;
    this._costSlope = cost.slope;
    this._costCrossing = cost.level_crossing;
    this._bridgePer = cost.bridge_per_tile;
    this._bridgeEx = cost.bridge_per_tile_ex;
    this._bridgeEx2 = cost.bridge_per_tile_ex2;
    this._tunnelPer = cost.tunnel_per_tile;
    this._tunnelEx = cost.tunnel_per_tile_ex;
    this._tunnelEx2 = cost.tunnel_per_tile_ex2;
    this._maxBridge = cost.max_bridge_length;
    this._maxTunnel = cost.max_tunnel_length;
    this._maxCost = cost.max_cost;
    /* Octile : un pas oblique (une paire de diagonales) coute au plus deux droites. */
    local diag2 = 2 * this._costDiag;
    if (diag2 > 2 * this._costTile) diag2 = 2 * this._costTile;
    local w = cost.astar_weight_pct;
    if (w < 0) w = 0;
    if (diag2 >= this._costTile) {
      /* h = M * (D2 - T) + C * (2T - D2), M = Manhattan, C = distance max (point 9). */
      this._aW = (diag2 - this._costTile) * w / 100;
      this._bW = (2 * this._costTile - diag2) * w / 100;
    } else {
      /* Deux diagonales moins cheres qu'une droite : chaque pas coute au moins une diagonale. */
      this._aW = this._costDiag * w / 100;
      this._bW = 0;
    }
    if (this._slopeInfo == null) this._BuildSlopeInfo();
    this._BuildTables();
    this._tile = [-1];
    this._par = [0];
    this._g = [0];
    this._code = [0];
    this._tab = {};
    this._gFirst = {};
    this._goalExits = {};
    this._goalCount = 0;
    this._gx = null;
    this._gy = null;
    this._cellM = null;
    this._minA = null;
    this._minB = null;
    this._bridgeAt = {};
    this._bridgeType = {};
    this._tunnelAt = {};
    this._open = null;
    this._finished = false;
    this._result = null;
    this._consumed = 0;
  }

  /* Compteurs du journal RAIL_PATH : une recherche par InitializePath, relances comprises. */
  function _ResetCounters()
  {
    this._nPops = 0;
    this._nProbes = 0;
    this._nTests = 0;
    this._nBridgeTests = 0;
    this._nTunnelTests = 0;
    this._nStructs = 0;
    this._nScans = 0;
    this._nScanSteps = 0;
    this._nOps = 0;
    this._nStructOk = 0;
    this._nStructBad = 0;
  }

  /* Pente -> classe constructible + plat (bit 4) + axes ou la voie droite monte (8 = X,
   * 16 = Y). Pente inclinee : son axe seulement (et un tunnel possible). Coin leve seul ou
   * pente raide : fondation inclinee pour la voie droite dans les deux axes. Deux coins
   * opposes ou trois coins leves : fondation plate. */
  function _BuildSlopeInfo()
  {
    local info = array(32, OPEX_RP_LAND);
    info[AITile.SLOPE_FLAT] = OPEX_RP_LAND | OPEX_RP_PLAIN;
    info[AITile.SLOPE_NE] = OPEX_RP_LAND | 8;
    info[AITile.SLOPE_SW] = OPEX_RP_LAND | 8;
    info[AITile.SLOPE_NW] = OPEX_RP_LAND | 16;
    info[AITile.SLOPE_SE] = OPEX_RP_LAND | 16;
    info[AITile.SLOPE_N] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_E] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_S] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_W] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_STEEP_N] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_STEEP_E] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_STEEP_S] = OPEX_RP_LAND | 24;
    info[AITile.SLOPE_STEEP_W] = OPEX_RP_LAND | 24;
    this._slopeInfo = info;
  }

  /* Code de noeud : bit 6 = sortie d'ouvrage, bits 4-5 = avant-dernier pas precedent,
   * bits 2-3 = pas precedent (d0), bits 0-1 = pas d'entree (d1). Pas : 0 = +x, 1 = -x,
   * 2 = +y, 3 = -y ; l'oppose de d est d ^ 1. */
  function _BuildTables()
  {
    local T = this._costTile;
    local D = this._costDiag;
    local turn = this._costTurn;
    local vt = this._v214Turn;
    local tight = this._v214Tight;
    local key = T + "/" + D + "/" + turn + "/" + vt + "/" + tight;
    /* Global modifie depuis une methode : le prefixe :: est obligatoire. */
    if (::OPEX_RAIL_PATH_TABLES == null) ::OPEX_RAIL_PATH_TABLES = {};
    local cache = ::OPEX_RAIL_PATH_TABLES;
    if (key in cache) {
      local cached = cache[key];
      this._trans = cached[0];
      this._next = cached[1];
      this._bitOf = cached[2];
      this._closeOf = cached[3];
      return;
    }
    local trans = array(512, -1);
    local nexts = array(128);
    local bitOf = array(128, 0);
    local closeOf = array(128, 0);
    for (local c = 0; c < 64; c++) {
      local dm1 = (c >> 4) & 3;
      local d0 = (c >> 2) & 3;
      local d1 = c & 3;
      /* Bits de fermeture : 8 + (d0, d1) pour un etat sans coude en attente, 24 + (d1, cote de
       * d0) pour un etat en attente ; l'emplacement (oppose de d1, d1), impossible, sert de
       * marque aux sorties d'ouvrage. */
      local own = 1 << (8 + (c & 15));
      local pend = (d0 != d1) ? (1 << (24 + d1 * 2 + (d0 & 1))) : 0;
      local pending = (dm1 == d0 && d0 != d1);
      local marker = 1 << (8 + (((d1 ^ 1) << 2) | d1));
      local list = [];
      if (d0 != (d1 ^ 1) && dm1 != (d0 ^ 1)) {
        for (local dn = 0; dn < 4; dn++) {
          if (dn == (d1 ^ 1)) continue;
          /* Interdit des virages a 90 degres : jamais l'oppose du pas d'avant une diagonale. */
          if (d0 != d1 && dn == (d0 ^ 1)) continue;
          local step = (dn == d1) ? T : D;
          if (dn != d0) step += (vt > 0) ? ((d0 != d1) ? vt : 0) : turn;
          if (tight > 0 && dm1 == d0 && d0 != d1 && dn == d1) step += tight;
          trans[(c << 2) + dn] = step;
          list.push(dn);
        }
      }
      nexts[c] = list;
      bitOf[c] = pending ? pend : own;
      closeOf[c] = pending ? pend : (own | pend);
      /* Sortie d'ouvrage : tout droit seulement, sans piece sur la tuile (la tete porte la
       * voie), donc sans test, sans pente ni passage a niveau. Le passage droit ordinaire ne
       * la domine pas sur une pente ou une route : etats fermes separement, par sa marque. */
      local s = c | OPEX_RP_STRUCT;
      if (dm1 == d1 && d0 == d1) {
        trans[(s << 2) + d1] = T;
        nexts[s] = [d1];
        bitOf[s] = marker;
        closeOf[s] = marker;
      } else {
        nexts[s] = [];
      }
    }
    this._trans = trans;
    this._next = nexts;
    this._bitOf = bitOf;
    this._closeOf = closeOf;
    /* Lecture seule apres construction : partagees sans copie. */
    cache[key] <- [trans, nexts, bitOf, closeOf];
  }

  function _DirIndex(step)
  {
    if (step == 1) return 0;
    if (step == -1) return 1;
    if (step == this._mx) return 2;
    if (step == -this._mx) return 3;
    return -1;
  }

  function _RouteDistance(sources, goals)
  {
    local best = -1;
    foreach (s in sources) {
      foreach (g in goals) {
        local d = AIMap.DistanceManhattan(s[0], g[0]);
        if (best < 0 || d < best) best = d;
      }
    }
    return best;
  }

  function _AddNode(tile, up, g, code)
  {
    local m = this._tile.len();
    this._tile.push(tile);
    this._par.push(up);
    this._g.push(g);
    this._code.push(code);
    return m;
  }

  /* Classe, pente utile et heuristique d'une tuile, calculees une fois par recherche. */
  function _Probe(t)
  {
    this._nProbes++;
    local e = 0;
    if (AITile.IsBuildable(t)) {
      local s = AITile.GetSlope(t);
      e = (s >= 0 && s < 32) ? this._slopeInfo[s] : OPEX_RP_LAND;
      /* Un bout de route a un seul sens est "constructible" mais refuse le rail. */
      if (AIRoad.IsRoadTile(t)) e = OPEX_RP_ROAD | (e & 24);
      /* Cote (jamais plate) : posable parfois, mais un pont peut aussi la survoler. */
      else if ((e & OPEX_RP_PLAIN) == 0 && AITile.IsCoastTile(t)) e = e | OPEX_RP_COAST;
    } else if (AIRoad.IsRoadTile(t)) {
      local s = AITile.GetSlope(t);
      e = OPEX_RP_ROAD | (((s >= 0 && s < 32) ? this._slopeInfo[s] : 0) & 24);
    } else {
      this._tab[t] <- 0;
      return 0;
    }
    if (this._guide != null && (t in this._guide)) e = e | OPEX_RP_GUIDE;
    /* Distance au rectangle des leads d'arrivee (un point pour un seul but), puis, pour
     * plusieurs buts, complement exact depuis la case ramenee dans le rectangle (point 9). */
    local mx = this._mx;
    local x = t % mx;
    local y = t / mx;
    local x0 = this._goalMinX;
    local y0 = this._goalMinY;
    local xc = x;
    local yc = y;
    local dx = 0;
    local dy = 0;
    if (x < x0) { dx = x0 - x; xc = x0; } else if (x > this._goalMaxX) { dx = x - this._goalMaxX; xc = this._goalMaxX; }
    if (y < y0) { dy = y0 - y; yc = y0; } else if (y > this._goalMaxY) { dy = y - this._goalMaxY; yc = this._goalMaxY; }
    local hm = dx + dy;
    local hc = (dx > dy) ? dx : dy;
    local cells = this._cellM;
    if (cells != null) {
      local ix = xc - x0;
      local iy = yc - y0;
      local k = ix + iy * this._boxW;
      local cm = cells[k];
      if (cm < 0) {
        cm = this._CellMin(xc, yc);
        cells[k] = cm;
      }
      hm += cm;
      local ma = this._minA[ix];
      if (ma < 0) {
        ma = this._AxisMin(this._gx, xc);
        this._minA[ix] = ma;
      }
      local mb = this._minB[iy];
      if (mb < 0) {
        mb = this._AxisMin(this._gy, yc);
        this._minB[iy] = mb;
      }
      local cx = dx + ma;
      local cy = dy + mb;
      hc = (cx > cy) ? cx : cy;
    }
    e = e | ((hm * this._aW + hc * this._bW) << OPEX_RP_H_SHIFT);
    this._tab[t] <- e;
    return e;
  }

  /* Manhattan minimale de la case (xc, yc) du rectangle aux leads : une fois par case. */
  function _CellMin(xc, yc)
  {
    local gx = this._gx;
    local gy = this._gy;
    local best = abs(xc - gx[0]) + abs(yc - gy[0]);
    for (local i = 1; i < gx.len(); i++) {
      local d = abs(xc - gx[i]) + abs(yc - gy[i]);
      if (d < best) best = d;
    }
    return best;
  }

  function _AxisMin(coords, v)
  {
    local best = abs(v - coords[0]);
    for (local i = 1; i < coords.len(); i++) {
      local d = abs(v - coords[i]);
      if (d < best) best = d;
    }
    return best;
  }

  /* Lead d'arrivee developpe (point 12) : une sortie de quai par plan, comme un pas ordinaire
   * (interdits, coude serre, route, pente, guide, max_cost ; piece testee hors sol plat).
   * Jamais depuis une sortie d'ouvrage : saut d'arrivee refuse par la pose. */
  function _PushExits(n, t, c, g, free, pt, extra, extraStraight)
  {
    if ((c & OPEX_RP_STRUCT) != 0) return;
    local exits = this._goalExits[t];
    local cb = c << 2;
    local cc0 = (c & 15) << 2;
    local d1 = c & 3;
    for (local i = 0; i < exits.len(); i += 2) {
      local ex = exits[i];
      local dir = exits[i + 1];
      local step = this._trans[cb + dir];
      if (step < 0) continue;
      local ng = g + step;
      if (free == 0) {
        this._nTests++;
        if (!AIRail.BuildRail(pt, t, ex)) continue;
        ng += extra;
        if (dir == d1) ng += extraStraight;
      }
      if (this._guide != null) ng = (ex in this._guide) ? g + (ng - g) / 2 : g + (ng - g) * 2;
      if (ng > this._maxCost) continue;
      local m = this._AddNode(ex, n, ng, OPEX_RP_EXIT | cc0 | dir);
      this._open.AddItem(-m, ng);
    }
  }

  /* Une sortie de quai en tete de file finit la recherche dans la tranche en cours : une
   * coupure de segment juste apres le lead ne la perd pas. */
  function _CompleteAtHead()
  {
    local open = this._open;
    if (open == null || open.IsEmpty()) return;
    local id = open.Begin();
    if (id >= 0 || this._code[-id] < OPEX_RP_EXIT) return;
    open.RemoveItem(id);
    this._Complete(-id);
  }

  /* Chemin complet en m : pieces sur sol plat rejouees (point 6), puis resultat, ou relance
   * avec les tuiles refusees desormais testees. Sous l'AITestMode de FindPath. */
  function _Complete(m)
  {
    local bad = this._PlainFailures(m);
    if (bad.len() > 0 && this._restarts < OPEX_RP_MAX_RESTARTS) {
      this._restarts++;
      foreach (t in bad) this._unplain[t] <- true;
      this._Init();
      return;
    }
    this._finished = true;
    this._result = this._Materialize(m);
    if (DECISION_LOG) this._CheckStructs(m);
  }

  /* Tuiles plates de la chaine finissant en m dont la piece (precedente, courante, suivante)
   * est refusee. Ni les tetes ni les sorties d'ouvrage (pas de piece), ni les tuiles deja
   * testees pendant la recherche. Le manque d'argent n'est pas un obstacle. */
  function _PlainFailures(m)
  {
    local out = [];
    local tiles = this._tile;
    local pars = this._par;
    local codes = this._code;
    local tab = this._tab;
    local nx = tiles[m];
    local nxc = codes[m];
    local b = pars[m];
    while (b > 0) {
      local a = pars[b];
      if (a <= 0) break;
      local tb = tiles[b];
      local cb = codes[b];
      if (((cb | nxc) & OPEX_RP_STRUCT) == 0 && (tb in tab) && (tab[tb] & OPEX_RP_PLAIN) != 0) {
        this._nTests++;
        if (!AIRail.BuildRail(tiles[a], tb, nx) && AIError.GetLastError() != AIError.ERR_NOT_ENOUGH_CASH) {
          out.push(tb);
        }
      }
      nx = tb;
      nxc = cb;
      b = a;
    }
    return out;
  }

  /* Le noeud n (tuile t, pas encore retire) repasse-t-il sur t ? Meme remontee bornee que
   * FindPath (point 10) : ses ancetres ont tous passe ce garde a leur retrait. */
  function _Revisits(n, t, ent)
  {
    if ((ent & OPEX_RP_CLOSED) == 0) return false;
    local gf = this._gFirst[t];
    local a = this._par[n];
    while (a > 0 && this._g[a] >= gf) {
      if (this._tile[a] == t) return true;
      a = this._par[a];
    }
    return false;
  }

  function _Materialize(m)
  {
    local chain = [];
    for (local a = m; a > 0; a = this._par[a]) chain.push(a);
    local node = null;
    for (local i = chain.len() - 1; i >= 0; i--) {
      local a = chain[i];
      node = OpexRailPathNode(node, this._tile[a], this._g[a], this._code[a] & 3);
    }
    return node;
  }

  /* Journal seulement : rejoue chaque ouvrage du chemin rendu comme la pose le deduira
   * (tunnel si GetOtherTunnelEnd relie les bouts, pont sinon), sous le mode test de FindPath.
   * Un echec ici signale un ecart entre la recherche et la pose. */
  function _CheckStructs(m)
  {
    for (local b = m; b > 0; b = this._par[b]) {
      local a = this._par[b];
      if (a <= 0 || this._par[a] <= 0) continue;
      local ta = this._tile[a];
      local tb = this._tile[b];
      local len = AIMap.DistanceManhattan(ta, tb);
      if (len < 2) continue;
      local tunnel = AITunnel.GetOtherTunnelEnd(ta) == tb;
      local ok = false;
      if (tunnel) {
        ok = AITunnel.BuildTunnel(AIVehicle.VT_RAIL, ta);
      } else {
        local bridge = this._BridgeType(len + 1);
        ok = bridge >= 0 && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge, ta, tb);
      }
      if (ok) {
        this._nStructOk++;
      } else {
        OpexDecide("RAIL_PATH_STRUCT", "bad a=" + ta + " b=" + tb + " kind=" + (tunnel ? "tunnel" : "bridge")
                   + " err=" + AIError.GetLastError() + " tun_ba=" + (AITunnel.GetOtherTunnelEnd(tb) == ta ? 1 : 0)
                   + " slope_a=" + AITile.GetSlope(ta) + " slope_b=" + AITile.GetSlope(tb)
                   + " z_a=" + AITile.GetMinHeight(ta) + " z_b=" + AITile.GetMinHeight(tb));
        this._nStructBad++;
      }
    }
  }

  function _StructCost(len, isBridge)
  {
    local step = len * (isBridge ? this._bridgePer : this._tunnelPer) + (len - 1) * this._costTile;
    if (len > 7) step += (len - 7) * (isBridge ? this._bridgeEx : this._tunnelEx);
    if (len > 11) step += (len - 11) * (isBridge ? this._bridgeEx2 : this._tunnelEx2);
    return step;
  }

  function _TryBridge(n, t, c, g)
  {
    local d1 = c & 3;
    local key = t * 4 + d1;
    local far = -1;
    if (key in this._bridgeAt) {
      far = this._bridgeAt[key];
    } else {
      far = this._FindBridge(t, d1);
      this._bridgeAt[key] <- far;
    }
    if (far >= 0) this._PushStruct(n, t, far, c, g, true);
  }

  /* Premier atterrissage constructible droit devant ; deux essais de pont au plus. */
  function _FindBridge(t, d1)
  {
    local tab = this._tab;
    local off = this._offs[d1];
    local mx = this._mx;
    local row = t / mx;
    local alongX = d1 < 2;
    local tries = 0;
    for (local k = 1; k + 1 <= this._maxBridge; k++) {
      local h = t + off * k;
      if (!AIMap.IsValidTile(h) || (alongX && h / mx != row)) return -1;
      if (h in tab) {
        local e = tab[h];
        if ((e & OPEX_RP_FORBID) != 0) return -1;
        if (k == 1 || (e & OPEX_RP_LAND) == 0) continue;
      } else if (k == 1 || !AITile.IsBuildable(h)) {
        continue;
      }
      local bridge = this._BridgeType(k + 1);
      if (bridge < 0) continue;
      this._nBridgeTests++;
      if (AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge, t, h)) {
        /* La pose deduit un tunnel quand GetOtherTunnelEnd relie les deux bouts (chemin
         * lu dans un sens ou dans l'autre) : ce pont-la serait pose en tunnel. */
        if (AITunnel.GetOtherTunnelEnd(t) != h && AITunnel.GetOtherTunnelEnd(h) != t) return h;
        continue;
      }
      tries++;
      if (tries >= 2) return -1;
    }
    return -1;
  }

  function _BridgeType(len)
  {
    if (len in this._bridgeType) return this._bridgeType[len];
    local list = AIBridgeList_Length(len);
    local bridge = -1;
    if (!list.IsEmpty()) {
      /* Le type que la pose choisira (OpexBuildTrack) : le test juge le meme pont, caisse
       * comprise. Une fois par longueur et par recherche. */
      OpexBridgeSortBySpeed(list);
      bridge = list.Begin();
    }
    this._bridgeType[len] <- bridge;
    return bridge;
  }

  function _TryTunnel(n, t, c, g)
  {
    local far = -1;
    if (t in this._tunnelAt) {
      far = this._tunnelAt[t];
    } else {
      far = this._FindTunnel(t);
      this._tunnelAt[t] <- far;
    }
    if (far < 0) return;
    local dist = AIMap.DistanceManhattan(t, far);
    if (far == t + this._offs[c & 3] * dist) this._PushStruct(n, t, far, c, g, false);
  }

  function _FindTunnel(t)
  {
    local far = AITunnel.GetOtherTunnelEnd(t);
    if (!AIMap.IsValidTile(far)) return -1;
    local dist = AIMap.DistanceManhattan(t, far);
    if (dist < 2 || dist + 1 > this._maxTunnel) return -1;
    if ((far in this._tab) && (this._tab[far] & OPEX_RP_FORBID) != 0) return -1;
    this._nTunnelTests++;
    if (!AITunnel.BuildTunnel(AIVehicle.VT_RAIL, t)) return -1;
    /* Chemin relu a l'envers (sonde inverse V294f) : la pose part de far. */
    if (AITunnel.GetOtherTunnelEnd(far) != t) return -1;
    return far;
  }

  /* Ouvrage de t a far : la tete t est droite dans le sens d'entree, la sortie repart droit. */
  function _PushStruct(n, t, far, c, g, isBridge)
  {
    local d1 = c & 3;
    local len = AIMap.DistanceManhattan(t, far);
    local e2 = (far in this._tab) ? this._tab[far] : this._Probe(far);
    /* Atterrissage sur sol constructible seulement : ni route (la tete la detruirait), ni
     * occupant, ni tuile interdite. */
    if ((e2 & OPEX_RP_LAND) == 0) return;
    local ng = g + this._trans[(c << 2) + d1] + this._StructCost(len, isBridge);
    /* Couloir guide : meme facteur que les pas ordinaires, selon la tuile d'arrivee. */
    if (this._guide != null) ng = ((e2 & OPEX_RP_GUIDE) != 0) ? g + (ng - g) / 2 : g + (ng - g) * 2;
    if (ng > this._maxCost) return;
    local cc = OPEX_RP_STRUCT | (d1 << 4) | (d1 << 2) | d1;
    if ((e2 & this._bitOf[cc]) != 0) return;
    local m = this._AddNode(far, n, ng, cc);
    this._open.AddItem(-m, ng + (e2 >> OPEX_RP_H_SHIFT));
    this._nStructs++;
  }

  function _LogEnd(outcome)
  {
    if (!DECISION_LOG) return;
    OpexDecide("RAIL_PATH", "out=" + outcome + " pops=" + this._nPops
        + " nodes=" + (this._tile.len() - 1) + " probes=" + this._nProbes
        + " tests=" + this._nTests + " bridges=" + this._nBridgeTests
        + " tunnels=" + this._nTunnelTests + " structs=" + this._nStructs
        + " scans=" + this._nScans + " scan_steps=" + this._nScanSteps
        + " goals=" + this._goalCount + " ops=" + this._nOps + " init_ops=" + this._initOps
        + " struct_ok=" + this._nStructOk + " struct_bad=" + this._nStructBad
        + " restarts=" + this._restarts);
  }
}

/* Fabrique unique des appelants (builder_rail.nut, probe_v307.nut). */
function OpexNewRailPathfinder()
{
  return OpexRailPath();
}
