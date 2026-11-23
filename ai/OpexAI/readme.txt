OpexAI - an AI for OpenTTD
==========================

Version: 1.0.0 (AI version 9)
Author:  jrdoublet
URL:
License: GNU General Public License, version 3 or later (GPL-3.0-or-later)


Description
-----------

OpexAI is a computer-controlled transport company. It can use railways,
road vehicles (buses and trucks), aircraft and ships. It compares possible
routes across these modes by their expected return on investment, builds the
selected lines and grows their fleets within the money available to the
company. Its state is stored in the savegame.


Requirements
------------

- OpenTTD 15 or later (AI API version 15). Tested with OpenTTD 15.3.
- No AI libraries need to be installed.


Settings
--------

difficulty         Easy / Medium / Hard (default) / Custom.
                   Controls fair-play rules towards other companies. Easy
                   and Medium add courtesy rules; they do not slow down
                   construction or cap the number of lines. Custom allows
                   anticompetitive actions; in 1.0.0 the purchase of
                   exclusive transport rights is disabled.
use_trains         Build railways (default: on).
use_road_vehicles  Build bus and truck services (default: on).
use_aircraft       Build airports and aircraft (default: on).
use_ships          Build docks and ships (default: on).
show_signs         Show debug signs on the map (default: off).
log_level          AI log verbosity: Off (default) / Summary / Decisions.
                   In 1.0.0, Summary and Decisions produce the same log.

Settings are read when the AI starts or a savegame is loaded; they cannot
be changed while the AI is running.


Known limitations
-----------------

- Tested only in the temperate climate, on maps from 256x256 to 1024x1024
  tiles, starting in 1970, with default OpenGFX vehicles and no NewGRFs.
- Easy and Medium are courtesy levels, not weaker opponents.
- Savegames from development versions earlier than 1.0.0 cannot be loaded.


License
-------

Copyright (C) 2026 jrdoublet

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details: <https://www.gnu.org/licenses/>.


Third-party code
----------------

OpexAI contains no third-party code. Its rail pathfinder (rail_path/) was
written from scratch for OpexAI; it replaces earlier modified copies of
OpenTTD NoAI libraries, which were removed.


Credits
-------

- Author: jrdoublet.
- OpenTTD and its AI scripting interface: the OpenTTD team and contributors,
  <https://www.openttd.org>.
