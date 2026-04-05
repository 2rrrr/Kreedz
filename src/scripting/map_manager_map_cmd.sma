#include <amxmodx>
#include <map_manager>
#include <sqlx>
#include <kreedz_sql>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Map Manager: Map Command"
#define VERSION "0.1.0"
#define AUTHOR "Codex"

#pragma semicolon 1

const MIN_SEARCH_LENGTH = 2;
const MAP_CHANGE_DELAY = 3;
const TASK_DELAYED_CHANGE = 420510;
const DIFFICULTY_LEN = 64;

new Array:g_aMapsList = Invalid_Array;
new Trie:g_tMapDifficulties = Invalid_Trie;
new bool:g_bSqlReady;
new g_sPrefix[48];
new g_sCurMap[MAPNAME_LENGTH];
new g_iMaxPlayers;
new g_sPendingMap[MAPNAME_LENGTH];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION + VERSION_HASH, AUTHOR);

    register_clcmd("say", "clcmd_say");
    register_clcmd("say_team", "clcmd_say");
    register_dictionary("mapmanager.txt");

    g_tMapDifficulties = TrieCreate();
    g_iMaxPlayers = get_maxplayers();
    get_mapname(g_sCurMap, charsmax(g_sCurMap));
}

public plugin_end()
{
    if(g_tMapDifficulties != Invalid_Trie) {
        TrieDestroy(g_tMapDifficulties);
    }
}

public plugin_natives()
{
    set_module_filter("module_filter_handler");
    set_native_filter("native_filter_handler");
}

public module_filter_handler(const library[], LibType:type)
{
    if(equal(library, "kreedz_sql")) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public native_filter_handler(const native_func[], index, trap)
{
    if(equal(native_func, "kz_sql_get_tuple")) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public plugin_cfg()
{
    mapm_get_prefix(g_sPrefix, charsmax(g_sPrefix));
}

public kz_sql_initialized()
{
    g_bSqlReady = true;
    query_map_difficulties();
}

public mapm_maplist_loaded(Array:maplist, const nextmap[])
{
    g_aMapsList = maplist;

    if(g_bSqlReady) {
        query_map_difficulties();
    }
}

public mapm_maplist_unloaded()
{
    g_aMapsList = Invalid_Array;

    if(g_tMapDifficulties != Invalid_Trie) {
        TrieClear(g_tMapDifficulties);
    }
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
    if(strlen(map_query) < MIN_SEARCH_LENGTH) {
        new exact_index = mapm_get_map_index(map_query);
        if(exact_index != INVALID_MAP_INDEX || equali(map_query, g_sCurMap)) {
            change_map(id, map_query);
            return;
        }

        client_print_color(
            id,
            print_team_default,
            "%s^1 No exact map found. Use at least^3 %d^1 letters for search.",
            g_sPrefix,
            MIN_SEARCH_LENGTH
        );
        return;
    }

    new Array:result_list = ArrayCreate(MAPNAME_LENGTH, 1);
    new result_count;

    if(containi(g_sCurMap, map_query) != -1) {
        ArrayPushString(result_list, g_sCurMap);
        result_count++;
    }

    if(g_aMapsList != Invalid_Array) {
        new map_index = 0;
        new map_info[MapStruct];
        while((map_index = find_similar_map(map_index, map_query)) != INVALID_MAP_INDEX) {
            ArrayGetArray(g_aMapsList, map_index, map_info);

            if(!is_map_in_result_list(result_list, map_info[Map])) {
                ArrayPushString(result_list, map_info[Map]);
                result_count++;
            }
            map_index++;
        }
    }

    if(result_count == 1) {
        new map_name[MAPNAME_LENGTH];
        ArrayGetString(result_list, 0, map_name, charsmax(map_name));
        change_map(id, map_name);
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
    new map_name[MAPNAME_LENGTH], item_name[MAPNAME_LENGTH + DIFFICULTY_LEN + 16];

    for(new i = 0; i < result_count; i++) {
        ArrayGetString(result_list, i, map_name, charsmax(map_name));
        format_map_menu_item(map_name, item_name, charsmax(item_name));
        menu_additem(menu, item_name);
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

    new map_name[MAPNAME_LENGTH], item_info[4], item_name[MAPNAME_LENGTH + DIFFICULTY_LEN + 16], access, callback;
    menu_item_getinfo(menu, item, access, item_info, charsmax(item_info), item_name, charsmax(item_name), callback);
    trim_bracket(item_name);
    copy(map_name, charsmax(map_name), item_name);
    menu_destroy(menu);

    if(!can_use_map_cmd(id)) {
        return PLUGIN_HANDLED;
    }

    if(mapm_get_map_index(map_name) == INVALID_MAP_INDEX && !equali(map_name, g_sCurMap)) {
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

bool:is_map_in_result_list(Array:result_list, map[])
{
    new existing_map[MAPNAME_LENGTH];
    for(new i = 0, size = ArraySize(result_list); i < size; i++) {
        ArrayGetString(result_list, i, existing_map, charsmax(existing_map));
        if(equali(existing_map, map)) {
            return true;
        }
    }
    return false;
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

query_map_difficulties()
{
    if(!g_bSqlReady || g_tMapDifficulties == Invalid_Trie) {
        return;
    }

    TrieClear(g_tMapDifficulties);
    SQL_ThreadQuery(
        kz_sql_get_tuple(),
        "@on_map_difficulties_loaded",
        "SELECT `map_name`, COALESCE(NULLIF(TRIM(`map_tier_simen`), ''), NULLIF(TRIM(`map_tier_rush`), ''), 'Unknown') FROM `kz_maps_metadata`;"
    );
}

public @on_map_difficulties_loaded(QueryState, Handle:hQuery, error[], error_code, data[], data_len, Float:query_time)
{
    if(QueryState == TQUERY_CONNECT_FAILED || QueryState == TQUERY_QUERY_FAILED) {
        log_amx("Map difficulty query failed [%d]: %s", error_code, error);
        SQL_FreeHandle(hQuery);
        return PLUGIN_HANDLED;
    }

    if(g_tMapDifficulties == Invalid_Trie) {
        SQL_FreeHandle(hQuery);
        return PLUGIN_HANDLED;
    }

    new map_name[MAPNAME_LENGTH], difficulty[DIFFICULTY_LEN];
    while(SQL_MoreResults(hQuery)) {
        SQL_ReadResult(hQuery, 0, map_name, charsmax(map_name));
        SQL_ReadResult(hQuery, 1, difficulty, charsmax(difficulty));
        normalize_difficulty(difficulty, charsmax(difficulty));
        TrieSetString(g_tMapDifficulties, map_name, difficulty);
        SQL_NextRow(hQuery);
    }

    SQL_FreeHandle(hQuery);
    return PLUGIN_HANDLED;
}

format_map_menu_item(const map_name[], item_name[], item_len)
{
    new difficulty[DIFFICULTY_LEN];
    get_map_difficulty(map_name, difficulty, charsmax(difficulty));
    formatex(item_name, item_len, "%s[\y%s\w]", map_name, difficulty);
}

get_map_difficulty(const map_name[], difficulty[], difficulty_len)
{
    if(g_tMapDifficulties != Invalid_Trie && TrieGetString(g_tMapDifficulties, map_name, difficulty, difficulty_len)) {
        normalize_difficulty(difficulty, difficulty_len);
        return;
    }

    copy(difficulty, difficulty_len, "Unknown");
}

normalize_difficulty(difficulty[], difficulty_len)
{
    trim(difficulty);

    if(!difficulty[0]) {
        copy(difficulty, difficulty_len, "Unknown");
    }
}

change_map(id, map[])
{
    new name[32];
    get_user_name(id, name, charsmax(name));

    if(task_exists(TASK_DELAYED_CHANGE)) {
        remove_task(TASK_DELAYED_CHANGE);
    }

    copy(g_sPendingMap, charsmax(g_sPendingMap), map);

    client_print_color(
        0,
        id,
        "%s^3 %s^1 selected^3 %s^1. Changing map in^3 %d^1 seconds.",
        g_sPrefix,
        name,
        map,
        MAP_CHANGE_DELAY
    );
    log_amx("%s scheduled map change to %s using /map", name, map);
    set_task(float(MAP_CHANGE_DELAY), "task_delayed_changelevel", TASK_DELAYED_CHANGE);
}

public task_delayed_changelevel()
{
    if(!g_sPendingMap[0]) {
        return;
    }

    server_cmd("changelevel %s", g_sPendingMap);
}
