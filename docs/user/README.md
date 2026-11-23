# OpexAI user guide

This guide applies to OpexAI 1.0.0.

## Requirements

- **OpenTTD 15 or later.** OpexAI uses AI API version 15, so OpenTTD 14 and
  older cannot list or load it. It was developed and tested with OpenTTD 15.3.
- No AI libraries need to be installed: OpexAI does not import any library
  from Online Content.

## Installation

### From Online Content (BaNaNaS)

1. Start OpenTTD and click **Check Online Content** in the main menu.
2. Search for **OpexAI**; the content type is *AI*.
3. Tick OpexAI and click **Download**.

The game installs the AI and it becomes available immediately.

### Manual installation

1. Download `OpexAI` from the [Releases page](https://github.com/jrdoublet/OpexAI/releases), or
   from the BaNaNaS website.
2. Put the archive in the `ai` folder of your OpenTTD user directory. OpenTTD
   reads `.tar` archives directly; you can also extract it so that you get an
   `OpexAI` folder that contains `info.nut` and `main.nut`. Usual locations:
   - Windows: `Documents\OpenTTD\ai\`
   - macOS: `~/Documents/OpenTTD/ai/`
   - Linux: `~/.local/share/openttd/ai/` (older installations may use
     `~/.openttd/ai/`)
3. Restart OpenTTD, or rescan the AIs (`rescan_ai` in the console).

### Choosing OpexAI for a game

Open **AI Settings** (main menu, or *AI/Game Script Settings* in a running
game), select a computer player slot and pick **OpexAI**. Use **Configure** to
change its settings before the company starts.

## Settings

OpexAI has seven settings. They are read when the AI starts and when a saved
game is loaded. They cannot be changed while the AI is running, so choose them
before the company starts.

| Setting | Values | Default | Effect |
|---|---|---|---|
| `difficulty` | Easy (0), Medium (1), Hard (2), Custom (3) | Hard | Play style, see [Difficulty](#difficulty). |
| `use_trains` | on / off | on | Build railways and trains. |
| `use_road_vehicles` | on / off | on | Build bus and truck services. |
| `use_aircraft` | on / off | on | Build airports and aircraft. |
| `use_ships` | on / off | on | Build docks and ships. |
| `show_signs` | on / off | off | Place debug signs on the map. Useful only for investigating the AI's behaviour. |
| `log_level` | Off (0), Summary (1), Decisions (2) | Off | Amount of information written to the *AI Debug* window. |

Notes:

- When a transport mode is switched off, OpexAI neither searches for nor builds
  routes of that mode.
- With `log_level` set to Off, OpexAI still reports warnings and errors. In
  version 1.0.0, Summary and Decisions enable the same decision log; the two
  levels may be separated in a later version.

## Difficulty

The difficulty setting controls how OpexAI behaves towards other companies. **It
is not an economic handicap:** the lower levels do not slow down construction or
cap the number of lines; they only rule out some ways of competing with other
companies.

- **Hard (default):** full play, without anticompetitive actions.
- **Medium:** as Hard, with additional courtesy rules. OpexAI does not take
  the last airport place of a town where a single other company already has an
  airport (except in the largest towns), does not compete for a primary
  industry already served by another company, and does not place debug signs,
  even when `show_signs` is on.
- **Easy:** as Medium, and OpexAI also never builds an airport in a town where
  another company already has one, and avoids stations whose catchment area
  overlaps that of another company's station.
- **Custom:** removes the restrictions above and allows anticompetitive
  actions such as buying exclusive transport rights. In version 1.0.0 the
  purchase of exclusive transport rights is disabled, so Custom does not buy
  them.

A difficulty level that also weakens the AI economically may be added in a
later version.

## Savegames and multiplayer

- OpexAI saves its state in the savegame and resumes after loading.
- Savegames made with development versions earlier than 1.0.0 cannot be
  loaded with OpexAI 1.0.0.
- Several OpexAI companies can play in the same game. The first company is
  named "OpexAI", the next ones "OpexAI #2", "OpexAI #3" and so on.
- In multiplayer games, AI players run on the server.

## Known limitations

- OpexAI has been tested only in the **temperate** climate, on maps from
  256x256 to 1024x1024 tiles, starting in 1970, with the default OpenGFX
  vehicles and without NewGRFs. Other climates, much smaller or larger maps,
  other start years and vehicle NewGRFs have not been tested and may give poor
  results or unexpected behaviour.
- Easy and Medium are courtesy levels, not weaker opponents (see
  [Difficulty](#difficulty)).
- Settings cannot be changed during a running game (see [Settings](#settings)).

## Reporting a problem

Open an issue on the [issue tracker](https://github.com/jrdoublet/OpexAI/issues) with:

- the OpexAI and OpenTTD versions;
- the climate, map size and start year, and the list of NewGRFs, if any;
- if possible, a savegame and the contents of the *AI Debug* window, with
  `log_level` set to Decisions.
