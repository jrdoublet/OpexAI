<!--
Maintainer note (remove before publishing): set the release date when 1.0.0
is published (PUB-43/PUB-44).
-->

# Changelog

All notable changes to OpexAI are documented in this file. Version numbers
follow [Semantic Versioning](https://semver.org): the major version changes
when savegames of the previous version can no longer be loaded.

## [1.0.0] - unreleased

First public release. Internal AI version 9 (`GetVersion`); requires OpenTTD 15
or later (AI API 15).

### Features

- Multimodal company: railways, road vehicles (buses and trucks), aircraft and
  ships. Each mode can be switched off in the settings.
- Route selection that compares candidates across modes by expected return on
  investment, within the money available to the company.
- Construction of stations, track, roads, airports, docks and depots, followed
  by vehicle purchases and fleet growth on existing lines.
- Savegame support: the AI state is stored in the savegame and restored on
  load.
- Several OpexAI companies can share a game; they are named "OpexAI",
  "OpexAI #2", "OpexAI #3" and so on.
- No dependency on AI libraries from Online Content.

### Settings

- Seven player settings: `difficulty`, `use_trains`, `use_road_vehicles`,
  `use_aircraft`, `use_ships`, `show_signs` and `log_level`. See the
  [user guide](docs/user/README.md#settings).
- No debug signs on the map and no decision log by default.
- Difficulty levels Easy, Medium, Hard (default) and Custom control fair-play
  rules towards other companies; they are not an economic handicap.

### Known limitations

- Tested only in the temperate climate, on maps from 256x256 to 1024x1024
  tiles, starting in 1970, with default OpenGFX vehicles and no NewGRFs.
- Savegames from development versions earlier than 1.0.0 cannot be loaded.
