# OpexAI

OpexAI is an artificial intelligence (AI) company for [OpenTTD](https://www.openttd.org).
It plays as a computer-controlled transport company and can use all four transport
modes: railways, road vehicles (buses and trucks), aircraft and ships.

## What it does

- Looks for transport opportunities between towns and industries on the map.
- Compares candidate routes across modes by their expected return on investment.
- Builds stations, tracks, roads, airports, docks and depots, then buys vehicles.
- Grows the fleets of existing lines while keeping spending within the money
  available to the company.
- Stores its state in the savegame, so a saved game can be loaded and continued.

Each transport mode can be switched off in the AI settings. See the
[user guide](docs/user/README.md) for details.

## Requirements

- OpenTTD 15 or later (AI API version 15). OpexAI was developed and tested with
  OpenTTD 15.3; older OpenTTD versions cannot load it.
- No additional AI libraries are required.

## Installation

**From inside the game (recommended):** open *Online Content* from the main menu,
search for "OpexAI" among the AIs, select it and download it.

**Manually:** download the release archive from the
[Releases page](https://github.com/jrdoublet/OpexAI/releases) and place it in the `ai` folder of
your OpenTTD user directory. Full instructions are in the
[user guide](docs/user/README.md#installation).

To use it, open *AI Settings* from the main menu, select an AI slot and choose
OpexAI.

## Documentation

- [User guide](docs/user/README.md): installation, settings, difficulty and
  known limitations.
- [Changelog](CHANGELOG.md).

## Reporting problems

Please open an issue on the [issue tracker](https://github.com/jrdoublet/OpexAI/issues). Include
the OpexAI and OpenTTD versions, the map settings and, if possible, a savegame
and the AI debug log (*AI Debug* window).

## License

Copyright (C) 2026 jrdoublet

OpexAI is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version (SPDX: `GPL-3.0-or-later`).

OpexAI is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for the full text.

### Third-party code

OpexAI contains no third-party code. See [THIRD_PARTY.md](THIRD_PARTY.md) for the
history of the components it no longer uses.

## Credits

- Author: jrdoublet.
- OpenTTD and its AI (NoAI) scripting interface: the OpenTTD team and
  contributors, <https://www.openttd.org>.
