# Third-Party Components and Licensing Inventory (OpexAI)

Project license decision (2026-11-22): **GNU General Public License v3.0 or later**
(`SPDX-License-Identifier: GPL-3.0-or-later`), `Copyright (C) 2026 jrdoublet`.
See [LICENSE](LICENSE) for the full text of the GNU General Public License version 3.

---

## PUB-05 : bloquant GPL v3 levé / GPL v3 Publication Blocker Resolved (2026-11-23)

> **RESOLVED (PUB-05, branch `pub05b-astar-nov23`, 2026-11-23).**
>
> Until PUB-05, the 5 files under `ai/OpexAI/pathfinder_v90/` (`aystar.nut`,
> `binary_heap.nut`, `rail.nut`, `v129.nut`, `v296.nut` — 2,343 lines total)
> and the `OpexBinaryHeapV90` class instantiated by `ai/OpexAI/road1y_astar.nut`
> were derived from OpenTTD NoAI libraries licensed under GPL version 2 only
> (`GPL-2.0-only`), which cannot be distributed together with `GPL-3.0-or-later`
> code.
>
> PUB-05 removed `ai/OpexAI/pathfinder_v90/` entirely (commit `7afd3ccb`) and
> replaced it with a rail A* and a priority queue written from scratch
> (clean room: written without reading the removed code or the NoAI
> libraries, from OpexAI's own callers, its tests and the official NoAI API):
>
> - `ai/OpexAI/rail_path/rail_path.nut` — `OpexRailPath`, factory
>   `OpexNewRailPathfinder()` (rail A*, used by `builder_rail.nut` and
>   `probe_v307.nut`);
> - `ai/OpexAI/rail_path/min_queue.nut` — `OpexMinQueue`, a priority queue on
>   the native `AIList`, which replaces `OpexBinaryHeapV90` in
>   `road1y_astar.nut`.
>
> Both files are own code under `GPL-3.0-or-later`
> (`Copyright (C) 2026 jrdoublet`). **OpexAI no longer contains any
> `GPL-2.0-only` code**; all 111 `.nut` files under `ai/OpexAI/` carry the
> `GPL-3.0-or-later` SPDX header.

---

## 1. Attribution Notice (for repository and BaNaNaS `readme.txt`)

### Current state (after PUB-05)

OpexAI contains no code derived from third-party works. Its source files are all
own code under `GPL-3.0-or-later`.

### Former third-party code in OpexAI (resolved by PUB-05)

- **Graph.AyStar v4, Queue.BinaryHeap v1, Pathfinder.Rail v1**
  (Copyright (C) 2008-2009 OpenTTD NoAI Developers Team,
  <https://www.openttd.org>) — **`GPL-2.0-only`**.
  Modified copies formerly in `ai/OpexAI/pathfinder_v90/` (`aystar.nut`,
  `binary_heap.nut`, `rail.nut`, and derived optimisations `v129.nut` and
  `v296.nut`: renamed classes `OpexAyStarV90`, `OpexBinaryHeapV90`,
  `OpexRailPathFinderV90`, `OpexBinaryHeapV129`, `OpexAyStarV129`,
  `OpexRailPathFinderV129`, `OpexRailPathFinderV296`), as well as
  `OpexBinaryHeapV90` used in `ai/OpexAI/road1y_astar.nut`.
  **Removed in PUB-05** (`7afd3ccb`, 2026-11-23) and replaced by the independent
  `ai/OpexAI/rail_path/rail_path.nut` (`OpexRailPath`) and
  `ai/OpexAI/rail_path/min_queue.nut` (`OpexMinQueue`).

### Former third-party dependencies in OpexAI (resolved before PUB-02)

- **Pathfinder.Rail v1 runtime BaNaNaS import (`import("pathfinder.rail", ...)`
  and `OpexRailPathfinderCheckerV90`)** — **Removed in PUB-03** (`6de205c0`,
  2026-11-19). OpexAI no longer imports any external BaNaNaS library at runtime.
- **SuperLib v41 (`Town::TownRatingAllowStationBuilding`)** by Zuu (Leif Linse,
  `GPL-2.0-only`) — **Replaced in PUB-04** (`855f474d`, 2026-11-19).
  `OpexTownRatingAllowStation` in `ai/OpexAI/candidates.nut:780-802` is now an
  independent implementation from OpenTTD's observable town council rating rule
  and contains no SuperLib code.
- **MinchinWeb's MetaLibrary v11** by W. Minchin — **Removed on 2026-09-21**
  (`7c194d2`). OpexAI no longer imports or uses any code from MetaLibrary.

### Benchmark opponents (no code in OpexAI)

OpexAI was developed and benchmarked against, but contains no code from:

- **AAAHogEx** (v115) by Rei Ishibashi (`GPL-3.0`), downloaded from BaNaNaS for
  benchmarks (never tracked in Git). The 140 identical lines >= 45 chars noted
  in the 2026-11-19 audit come exclusively from shared OpenTTD NoAI library
  code (`Pathfinder.Rail` / `Graph.AyStar`) or standard NoAI API idioms; comments
  mentioning AAAHogEx refer to documented algorithmic ideas or cost parameters,
  not copied code.
- **AdmiralAI** by Yexo (`GPL-2.0-or-later`) and **trAIns**, used as historical
  benchmark opponents (never tracked in Git).

---

## 2. Re-verified Component Inventory (Audit §2.2 updated 2026-11-22)

Every component from `docs/agy_specs/PUBLICATION_AUDIT_20261119.md` §2.2 has
been re-verified against the working tree on 2026-11-22 (then 114 `.nut` files under
`ai/OpexAI/`: 109 own `.nut` files + 5 files in `ai/OpexAI/pathfinder_v90/`). Updated
on 2026-11-23 for PUB-05: 111 own `.nut` files (109 at the top level + 2 in
`ai/OpexAI/rail_path/`), none derived from third-party code:

| Component | Location | Tracked in Git | License Verified | Origin / Author | Usage by OpexAI | Compatible with GPL v3 (`GPL-3.0-or-later`)? | Action / Public Repo Status |
|---|---|---|---|---|---|---|---|
| **`pathfinder_v90/aystar.nut`, `binary_heap.nut`, `rail.nut`** | Formerly `ai/OpexAI/pathfinder_v90/` (3 files, 987 lines) | Removed | Header `GPLv2`; OpenTTD NoAI `license.txt` is verbatim GPL v2 without "or later" (`GPL-2.0-only`) | OpenTTD NoAI Developers Team (`smatz`, `truebrain`, 2009) | **RESOLVED (PUB-05, `7afd3ccb`, 2026-11-23)**: directory removed; replaced by the independent `rail_path/rail_path.nut` | **YES** (no derived code left) | Nothing to publish (removed) |
| **`pathfinder_v90/v129.nut`, `v296.nut`** | Formerly `ai/OpexAI/pathfinder_v90/` (2 files, 1,356 lines) | Removed | Header `derived from ... GPLv2` (`GPL-2.0-only`) | OpexAI, derived from `OpexAyStarV90` / `OpexBinaryHeapV90` / `OpexRailPathFinderV90` | **RESOLVED (PUB-05, 2026-11-23)**: the default rail A* is now `OpexRailPath` (`rail_path/rail_path.nut`, factory `OpexNewRailPathfinder()`), written from scratch | **YES** (no derived code left) | Nothing to publish (removed) |
| **`OpexBinaryHeapV90` in road A\*** | Formerly `ai/OpexAI/pathfinder_v90/binary_heap.nut`, called by `ai/OpexAI/road1y_astar.nut` | Removed | `OpexBinaryHeapV90` was `GPL-2.0-only`; `road1y_astar.nut` is own code (`GPL-3.0-or-later`) | OpenTTD NoAI Developers Team (heap) / OpexAI (`road1y_astar.nut`) | **RESOLVED (PUB-05, 2026-11-23)**: `road1y_astar.nut` now uses `OpexMinQueue` (`rail_path/min_queue.nut`, native `AIList`) | **YES** | Publish (own code) |
| **`rail_path/rail_path.nut`, `rail_path/min_queue.nut`** | `ai/OpexAI/rail_path/` (2 files) | Yes | Own code, `GPL-3.0-or-later` SPDX header | jrdoublet / OpexAI (PUB-05, 2026-11-23), written from scratch | Rail A* (`OpexRailPath`) and native priority queue (`OpexMinQueue`) | **YES** | Publish |
| **SuperLib-41 `Town::TownRatingAllowStationBuilding`** | Formerly adapted in `ai/OpexAI/candidates.nut:780-802` (`OpexTownRatingAllowStation`) | Yes (`candidates.nut`) | SuperLib-41 is `GPL-2.0-only` (`ai/library/SuperLib-41/main.nut:6-7`) | Zuu (Leif Linse); rewritten independently in OpexAI | **RESOLVED (PUB-04, `855f474d`, 2026-11-19)**: rewritten from OpenTTD's town rating rule; 0 SuperLib lines remain | **YES** (clean independent implementation under `GPL-3.0-or-later`) | Publish (`candidates.nut` carries `GPL-3.0-or-later`) |
| **`Pathfinder.Rail v1` external BaNaNaS import** | Formerly `ai/OpexAI/main.nut:28` & `OpexRailPathfinderCheckerV90` in `pathfinder_v90/rail.nut` | Removed | `GPL-2.0-only` (OpenTTD NoAI) | OpenTTD NoAI Developers Team | **RESOLVED (PUB-03, `6de205c0`, 2026-11-19)**: `import("pathfinder.rail", ...)` and dead checker class removed | **YES** (no longer imported or referenced) | Do not publish external dependency (removed) |
| **AAAHogEx-115** | `ai/AAAHogEx-115/` (local disk only, excluded by `.gitignore:12-13`) | **Never** (0 tracked files) | `GPL-3.0` (`ai/AAAHogEx-115/license.txt`) | Rei Ishibashi | **Benchmark opponent only** (downloaded from BaNaNaS by CI); no copied code in OpexAI | N/A (not part of OpexAI) | **No**: never version; CI downloads from BaNaNaS |
| **AdmiralAI** | Absent from disk (excluded by `.gitignore:13`) | **Never** (0 tracked files) | `GPL-2.0-or-later` (`docs/admiralai_evaluation.md:7`) | Yexo | Historical benchmark opponent only; no code in OpexAI | N/A | **No** |
| **trAIns** | Downloaded from BaNaNaS by `sweeps/bench.py` (pinned md5) | **Never** | — | — | Historical benchmark opponent only; no code in OpexAI | N/A | **No** |
| **ParameterisedAI** | `ai/ParameterisedAI/` (4 files) | Yes (4 files) | `GPL-2.0` (`ai/ParameterisedAI/LICENSE`) | Michal Charemza | None: legacy benchmark harness fixture (`17d61e85`) | N/A (not used by OpexAI) | **No**: laboratory harness only |
| **SuperLib-41 (library copies)** | `ai/library/SuperLib-41/`, `content_download/ai/library/SuperLib-41/` | Yes (26 + 26 files) | `GPL-2.0-only` (`main.nut:6-7`, `license.txt`) | Zuu (Leif Linse) | None: not imported by OpexAI (harness only) | N/A (not used by OpexAI) | **No**: laboratory harness only |
| **MinchinWeb's MetaLibrary 11** | `ai/library/MinchinWeb_s_MetaLibrary-11/`, `content_download/ai/library/MinchinWeb_s_MetaLibrary-11/` | Yes (21 + 21 files) | MinchinWeb's MetaLibrary License v.9 (permissive with attribution, `license.txt:7-15`) | W. Minchin | None: removed from OpexAI on 2026-09-21 (`7c194d2`) | N/A (not used by OpexAI) | **No**: laboratory harness only |
| **Queue.SortedList-3** | `ai/library/Queue.SortedList-3/`, `content_download/ai/library/Queue.SortedList-3/` | Yes (3 + 3 files) | `GPL-2.0` (`license.txt`) | Xarick | None: not imported by OpexAI (harness only) | N/A (not used by OpexAI) | **No**: laboratory harness only |
| **Queue.FibonacciHeap-3** | `ai/library/Queue.FibonacciHeap-3/` (3 files), `ai_libraries/51554648-Queue.FibonacciHeap-3.tar` | Yes (3 files + 1 `.tar`) | `GPL-2.0` (`license.txt`) | OpenTTD NoAI Developers Team | Benchmark harness only (`sweeps/bench.py:143`); not imported by OpexAI | N/A (not used by OpexAI) | **No**: laboratory harness only |
| **`Graph.AyStar-4`, `Pathfinder.Rail-1`, `Queue.BinaryHeap-1` (`.tar`)** | `ai_libraries/` (`4752412a-Graph.AyStar-4.tar`, `5046524c-Pathfinder.Rail-1.tar`, `51554248-Queue.BinaryHeap-1.tar`) | Yes (3 `.tar` files) | `GPL-2.0` | OpenTTD NoAI Developers Team | Benchmark harness archives for opponent AIs (OpexAI's former vendor copies in `pathfinder_v90/` were removed by PUB-05) | N/A (harness archives) | **No**: laboratory harness only |
| **`TrainLineAI`, `TrainLineAI-segmented`, `CatalogProbe`** | `ai/TrainLineAI/`, `ai/TrainLineAI-segmented/`, `ai/CatalogProbe/` | Yes (2 + 2 + 2 files) | Own project code (`jrdoublet`) | Project laboratory | Historical Phase 0 / diagnostic AIs; not used by OpexAI | N/A | **No**: laboratory only |
| **`src/trainlineai_schema.py`, `src/opexai_schema.py`, `src/opexai_info.nut.in`** | `src/` | Yes (3 files) | Own project code (`jrdoublet`, `GPL-3.0-or-later` for `opexai_info.nut.in`) | Project laboratory | `trainlineai_schema.py` is Phase 0; `opexai_schema.py` + `opexai_info.nut.in` (PUB-21) generate `ai/OpexAI/info.nut` and public/developer profiles | **YES** | `src/` remains in the laboratory; generated `info.nut` / `settings.nut` ship in the public profile |
