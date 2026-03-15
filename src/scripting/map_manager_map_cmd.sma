#include <amxmodx>
#include <map_manager>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Map Manager: Map Command"
#define VERSION "0.1.0"
#define AUTHOR "Codex"

#pragma semicolon 1

const MIN_SEARCH_LENGTH = 4;

new Array:g_aMapsList = Invalid_Array;
new g_sPrefix[48];
new g_sCurMap[MAPNAME_LENGTH];
new g_iMaxPlayers;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION + VERSION_HASH, AUTHOR);

    register_clcmd("say", "clcmd_say");
    register_clcmd("say_team", "clcmd_say");
    register_dictionary("mapmanager.txt");

    g_iMaxPlayers = get_maxplayers();
    get_mapname(g_sCurMap, charsmax(g_sCurMap));
}

public plugin_cfg()
{
    mapm_get_prefix(g_sPrefix, charsmax(g_sPrefix));
}

public mapm_maplist_loaded(Array:maplist, const nextmap[])
{
    g_aMapsList = maplist;
}

public mapm_maplist_unloaded()
{
    g_aMapsList = Invalid_Array;
}

public clcmd_say(id)
{
    new text[190];
    read_args(text, charsmax(text));
    remove_quotes(text);
    trim(text);

    if(!text[0]) {
        return PLUGIN_CONTINUE;
    }

    new command[16], map_query[MAPNAME_LENGTH];
    strtok(text, command, charsmax(command), map_query, charsmax(map_query), ' ');

    if(!equali(command, "/map")) {
        return PLUGIN_CONTINUE;
    }

    trim(map_query);
    strtolower(map_query);

    if(!map_query[0]) {
        client_print_color(id, print_team_default, "%s^1 Usage:^3 /map <mapname>", g_sPrefix);
        return PLUGIN_HANDLED;
    }

    if(containi(map_query, " ") != -1) {
        client_print_color(id, print_team_default, "%s^1 Invalid map name.", g_sPrefix);
        return PLUGIN_HANDLED;
    }

    if(!can_use_map_cmd(id)) {
        return PLUGIN_HANDLED;
    }

    handle_map_change_request(id, map_query);
    return PLUGIN_HANDLED;
}

handle_map_change_request(id, map_query[])
{
    new map_index = mapm_get_map_index(map_query);
    if(map_index != INVALID_MAP_INDEX) {
        change_map(id, map_query);
        return;
    }

    if(strlen(map_query) < MIN_SEARCH_LENGTH) {
        client_print_color(
            id,
            print_team_default,
            "%s^1 No exact map found. Use at least^3 %d^1 letters for search.",
            g_sPrefix,
            MIN_SEARCH_LENGTH
        );
        return;
    }

    if(g_aMapsList == Invalid_Array) {
        client_print_color(id, print_team_default, "%s^1 Map list is not loaded yet.", g_sPrefix);
        return;
    }

    new Array:result_list = ArrayCreate(1, 1);
    new result_count;

    map_index = 0;
    while((map_index = find_similar_map(map_index, map_query)) != INVALID_MAP_INDEX) {
        ArrayPushCell(result_list, map_index);
        result_count++;
        map_index++;
    }

    if(result_count == 1) {
        map_index = ArrayGetCell(result_list, 0);
        new map_info[MapStruct];
        ArrayGetArray(g_aMapsList, map_index, map_info);
        change_map(id, map_info[Map]);
    } else if(result_count > 1) {
        show_search_results_menu(id, result_list, result_count);
    } else {
        client_print_color(id, print_team_default, "%s^1 Map not found:^3 %s", g_sPrefix, map_query);
    }

    ArrayDestroy(result_list);
}

show_search_results_menu(id, Array:result_list, result_count)
{
    new menu = menu_create("Select map to change:", "search_results_handler");
    new map_info[MapStruct], map_index;

    for(new i; i < result_count; i++) {
        map_index = ArrayGetCell(result_list, i);
        ArrayGetArray(g_aMapsList, map_index, map_info);
        menu_additem(menu, map_info[Map]);
    }

    new text[64];
    formatex(text, charsmax(text), "%L", id, "MAPM_MENU_BACK");
    menu_setprop(menu, MPROP_BACKNAME, text);
    formatex(text, charsmax(text), "%L", id, "MAPM_MENU_NEXT");
    menu_setprop(menu, MPROP_NEXTNAME, text);
    formatex(text, charsmax(text), "%L", id, "MAPM_MENU_EXIT");
    menu_setprop(menu, MPROP_EXITNAME, text);

    menu_display(id, menu);
}

public search_results_handler(id, menu, item)
{
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new map_name[MAPNAME_LENGTH], item_info[4], access, callback;
    menu_item_getinfo(menu, item, access, item_info, charsmax(item_info), map_name, charsmax(map_name), callback);
    menu_destroy(menu);

    if(!can_use_map_cmd(id)) {
        return PLUGIN_HANDLED;
    }

    if(mapm_get_map_index(map_name) == INVALID_MAP_INDEX) {
        client_print_color(id, print_team_default, "%s^1 Map is no longer available:^3 %s", g_sPrefix, map_name);
        return PLUGIN_HANDLED;
    }

    change_map(id, map_name);
    return PLUGIN_HANDLED;
}

bool:can_use_map_cmd(id)
{
    if(get_user_flags(id) & ADMIN_MAP) {
        return true;
    }

    if(count_players_without_replay_bots() <= 1) {
        return true;
    }

    client_print_color(
        id,
        print_team_default,
        "%s^1 Only admins can use^3 /map^1 when more than one player is online.",
        g_sPrefix
    );
    return false;
}

count_players_without_replay_bots()
{
    new count;

    for(new i = 1; i <= g_iMaxPlayers; i++) {
        if(!is_user_connected(i) || is_user_hltv(i)) {
            continue;
        }

        if(is_replay_bot(i)) {
            continue;
        }

        count++;
    }

    return count;
}

bool:is_replay_bot(id)
{
    // kz_rush_pubbot uses fake clients, so bot check is enough for exclusion.
    return bool:is_user_bot(id);
}

find_similar_map(start_index, query[])
{
    new map_info[MapStruct];
    new end = ArraySize(g_aMapsList);

    for(new i = start_index; i < end; i++) {
        ArrayGetArray(g_aMapsList, i, map_info);
        if(containi(map_info[Map], query) != -1) {
            return i;
        }
    }

    return INVALID_MAP_INDEX;
}

change_map(id, map[])
{
    if(equali(map, g_sCurMap)) {
        client_print_color(id, print_team_default, "%s^1 Current map is already^3 %s^1.", g_sPrefix, map);
        return;
    }

    new name[32];
    get_user_name(id, name, charsmax(name));

    client_print_color(0, id, "%s^3 %s^1 changed map to^3 %s^1.", g_sPrefix, name, map);
    log_amx("%s changed map to %s using /map", name, map);
    server_cmd("changelevel %s", map);
}
