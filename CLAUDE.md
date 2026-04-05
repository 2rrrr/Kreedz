# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is
- AMX Mod X / Pawn code for a Counter-Strike 1.6 Kreedz server.
- Source plugins live in `src/scripting/`.
- Shared APIs and vendored AMXX/ReAPI includes live in `src/scripting/include/`.
- Runtime configs, data files, and native modules live under `assets/addons/amxmodx/`.
- Runtime dependencies called out in `README.md`: AMX Mod X 1.9+, ReGameDLL, ReAPI, and AmxxEasyHttp.

## Common commands
```bash
# Build one plugin
cd src/scripting
mkdir -p compiled
./amxxpc kz_core.sma -ocompiled/kz_core.amxx
```

```bash
# Build all plugins (non-interactive equivalent of compile.sh)
cd src/scripting
mkdir -p compiled
for f in *.sma; do ./amxxpc "$f" -o"compiled/${f%.sma}.amxx"; done
```

```bash
# Existing bulk-build helper (interactive: ends by opening less)
cd src/scripting
./compile.sh
```

- Compiled `.amxx` artifacts are gitignored.
- No automated test suite or lint configuration was found in the current tree. Validation is usually “compile the plugin(s) you changed” and then load them in a running AMX Mod X server.
- No repo-local HLDS/ReHLDS startup script was found. Run your local game server outside this repo, then copy/load the compiled `.amxx` files using the plugin lists in `assets/addons/amxmodx/configs/plugins-kz.ini` and `assets/addons/amxmodx/configs/plugins-map_manager.ini`.
- `README.md` still mentions `npm run build`, `npm run watch`, and `npm run pack`, but there is no `package.json` in the current repository state. Treat that section as stale unless Node tooling is restored.

## High-level architecture
- The main gameplay/timer plugin is `src/scripting/kz_core.sma`. It owns timer state, checkpoints, teleports, start/stop button detection, and exposes the core forwards/natives declared in `src/scripting/include/kreedz_api.inc`.
- Feature plugins extend the core by subscribing to those forwards instead of patching each other directly. Common examples are `kz_hud.sma`, `kz_menu.sma`, `kz_nchook.sma`, `kz_spec.sma`, and `kz_weapons.sma`.
- Command registration is standardized through `kz_register_cmd` in `src/scripting/include/kreedz_util.inc`. Adding a KZ command there automatically supports bare command, slash command, `say`, and `say_team` variants.
- SQL persistence is centered in `src/scripting/kz_sql_core.sma`, with the public contract in `src/scripting/include/kreedz_sql.inc`. It initializes core tables, resolves map/user IDs, and fires `kz_sql_initialized` / `kz_sql_data_recv` so dependent plugins can hydrate their own state.
- `migrations/base.sql` is not the full schema bootstrap; `kz_sql_core.sma` also creates the main tables at runtime.
- Player settings are a separate subsystem: `src/scripting/settings_core.sma` defines the option registry and change forwards in `src/scripting/include/settings_api.inc`, `kz_settings.sma` registers concrete player options, and `settings_mysql.sma` persists them to MySQL.
- Non-obvious rule: settings options are expected to be registered in `plugin_precache`, not `plugin_init`.
- `kz_menu.sma` is more than UI: it also opens its own SQL connection in `plugin_cfg()` and queries `kz_maps_metadata` for map tier/source data.
- Map voting is a parallel subsystem, not part of `kz_core`: `src/scripting/map_manager_core.sma` provides the map vote API in `src/scripting/include/map_manager.inc`, and addons such as `map_manager_scheduler.sma`, `map_manager_nomination.sma`, and `map_manager_rtv.sma` build on top of it.
- Load order matters. `assets/addons/amxmodx/configs/plugins-kz.ini` and `assets/addons/amxmodx/configs/plugins-map_manager.ini` define subsystem ordering, and several plugins depend on natives/forwards from earlier-loaded plugins.
- Multiple plugins independently parse `assets/addons/amxmodx/configs/kreedz.cfg` and create SQL connections during `plugin_cfg()`. If you change DB config behavior, check all consumers rather than assuming there is a single shared connection layer.
- `assets/addons/amxmodx/configs/kreedz.cfg` is the central runtime config for MySQL credentials and the records frontend URL; `assets/addons/amxmodx/configs/map_manager.cfg` configures the map voting stack.
