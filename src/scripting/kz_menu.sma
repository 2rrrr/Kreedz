#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <reapi>

#include <kreedz_api>
#include <kreedz_util>
#include <kreedz_sql>
#include <settings_api>

native bool:kz_can_undo_gocheck(id);

#define USE_MAP_MANAGER_INTERGRATION

#if defined USE_MAP_MANAGER_INTERGRATION
	#include <map_manager>
#endif

#define PLUGIN 	 	"[Kreedz] Menu"
#define VERSION 	__DATE__
#define AUTHOR	 	"ggv (Edited by 2rrrr)"

enum OptionsEnum {
    optIntMkeyBehavior,
};

new g_Options[OptionsEnum];

enum UserDataStruct {
	ud_mkeyBehavior,
};

new g_UserData[MAX_PLAYERS + 1][UserDataStruct];
new bool:g_bMainMenuOpened[MAX_PLAYERS + 1];

enum _:MapTierStruct {
    eMapSource[16],
    eMapTierSimen[64],
    eMapTierRush[64],
    eMapTierDisplay[64]
}

new g_MapTierInfo[MapTierStruct]
new g_szMapName[128]

enum _:ConnectionStruct {
	eHostName[64],
	eUser[64],
	ePassWord[64],
	eDataBase[64]
};

new g_ConnInfo[ConnectionStruct];

new Handle:SQL_Tuple
new Handle:SQL_Connection

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	kz_register_cmd("menu", "cmdMainMenu");
	// dlya dalbichey
	kz_register_cmd("ьутг", "cmdMainMenu");
	
	register_clcmd("jointeam", "cmdMkeyHandler");
	register_clcmd("chooseteam", "cmdMkeyHandler");

	RegisterHookChain(RG_CBasePlayer_ResetMaxSpeed, "HookResetMaxSpeed", 1);

	register_dictionary("kreedz_lang.txt");
	register_dictionary("common.txt");

	bindOptions();
}

public plugin_cfg() {
	new szCfgDir[256];
	get_configsdir(szCfgDir, charsmax(szCfgDir));

	format(szCfgDir, charsmax(szCfgDir), "%s/kreedz.cfg", szCfgDir);

	loadConfig(szCfgDir);

	new szError[512], iError;
	SQL_Tuple = SQL_MakeDbTuple(g_ConnInfo[eHostName], g_ConnInfo[eUser], g_ConnInfo[ePassWord], g_ConnInfo[eDataBase]);
	SQL_Connection = SQL_Connect(SQL_Tuple, iError, szError, charsmax(szError));
	
	if (SQL_Connection == Empty_Handle) {
		UTIL_LogToFile(MYSQL_LOG, "ERROR", "plugin_cfg", "[%d] %s", iError, szError);
		set_fail_state(szError);
	}

	SQL_SetCharset(SQL_Tuple, "utf8");
	
	SQL_FreeHandle(SQL_Connection);

	initMapTier();
}

loadConfig(szFileName[]) {
	if (!file_exists(szFileName)) return;
	
	new szData[256];
	new hFile = fopen(szFileName, "rt");

	while (hFile && !feof(hFile)) {
		fgets(hFile, szData, charsmax(szData));
		trim(szData);
		
		// Skip Comment and Empty Lines
		if (containi(szData, ";") > -1 || equal(szData, "") || equal(szData, "//", 2))
			continue;
		
		static szKey[64], szValue[64];

		strtok(szData, szKey, 63, szValue, 63, '=');

		trim(szKey);
		trim(szValue);
		remove_quotes(szValue);

		if (equal(szKey, "kz_sql_hostname"))
			copy(g_ConnInfo[eHostName], charsmax(g_ConnInfo[eHostName]), szValue);
		else if (equal(szKey, "kz_sql_username"))
			copy(g_ConnInfo[eUser], charsmax(g_ConnInfo[eUser]), szValue);
		else if (equal(szKey, "kz_sql_password"))
			copy(g_ConnInfo[ePassWord], charsmax(g_ConnInfo[ePassWord]), szValue);
		else if (equal(szKey, "kz_sql_database"))
			copy(g_ConnInfo[eDataBase], charsmax(g_ConnInfo[eDataBase]), szValue);
	}
	
	if (hFile) {
		fclose(hFile);
	}
}

initMapTier() {
	new szQuery[512];
	get_mapname(g_szMapName, charsmax(g_szMapName));

	formatex(szQuery, 511, "\
SELECT map_source, map_tier_simen, map_tier_rush FROM `kz_maps_metadata` WHERE `map_name` = '%s';\
		", g_szMapName);
	SQL_ThreadQuery(SQL_Tuple, "@initMapTierHandler", szQuery);
}

bindOptions() {
	g_Options[optIntMkeyBehavior] = find_option_by_name("mkey_behavior");
}

public OnCellValueChanged(id, optionId, newValue) {
	if (optionId == g_Options[optIntMkeyBehavior]) {
		g_UserData[id][ud_mkeyBehavior] = newValue;
	}
}

public client_putinserver(id) {
	g_UserData[id][ud_mkeyBehavior] = 0;
	g_bMainMenuOpened[id] = false;
}

public client_disconnected(id) {
	g_bMainMenuOpened[id] = false;
}

public kz_timer_start_post(id) {
	RefreshMainMenuIfOpened(id);
}

public kz_timer_pause_post(id) {
	RefreshMainMenuIfOpened(id);
}

public kz_noclip_post(id) {
	RefreshMainMenuIfOpened(id);
}

public HookResetMaxSpeed(id) {
	if (is_user_alive(id) && kz_get_timer_state(id) == TIMER_ENABLED) {
		RefreshMainMenuIfOpened(id);
	}

	return HC_CONTINUE;
}

RefreshMainMenuIfOpened(id) {
	if (!is_user_connected(id) || !g_bMainMenuOpened[id])
		return;

	menu_cancel(id);
	cmdMainMenu(id);
}

//
// Commands
//

public cmdMkeyHandler(id) {
	switch (g_UserData[id][ud_mkeyBehavior]) {
		case 1: amxclient_cmd(id, "ct");
		default: {
			cmdMainMenu(id);
		}
	}

	return PLUGIN_HANDLED;
}

public cmdMainMenu(id) {
	if (!is_user_connected(id)) return PLUGIN_HANDLED;

	new szMsg[256], szWeaponName[32], szRunType[8], szRunStatus[64];

	new szTime[64];
	new iCpNum = kz_get_cp_num(id);
	new iTpNum = kz_get_tp_num(id);
	new iWeaponRank = kz_get_min_rank(id);
	new bool:bPauseEnabled = kz_get_timer_state(id) == TIMER_PAUSED;
	new bool:bNoclipEnabled = !!kz_in_noclip(id);

	kz_get_weapon_name(iWeaponRank, szWeaponName, charsmax(szWeaponName));
	copy(szRunType, charsmax(szRunType), iTpNum > 0 ? "NUB" : "PRO");

	if (iWeaponRank == WPN_USP || iWeaponRank == -1) {
		copy(szRunStatus, charsmax(szRunStatus), szRunType);
	} else {
		formatex(szRunStatus, charsmax(szRunStatus), "%s | %s", szRunType, szWeaponName);
	}

	get_time("%Y/%m/%d - %H:%M:%S", szTime, 63);

	formatex(szMsg, charsmax(szMsg), "\
	    \r#awsl ><  \y%s^n\
	    \dMap \y%s\w(\d%s\w)^n\
	    \dTier %s^n^n\
	    \rKZ Menu\w",
	    szTime,
	    g_szMapName, g_MapTierInfo[eMapSource],
	    g_MapTierInfo[eMapTierDisplay]);

	new iMenu = menu_create(szMsg, "MainMenu_Handler");

	formatex(szMsg, charsmax(szMsg), "%L - [\r#%d\w]", id, "MAINMENU_CP", iCpNum);
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L - [\r#%d\w] \y%s\w^n", id, "MAINMENU_TP", iTpNum, szRunStatus);
	menu_additem(iMenu, szMsg);

	if (bPauseEnabled) {
		formatex(szMsg, charsmax(szMsg), "%L - [\yON\w]", id, "MAINMENU_PAUSE");
	} else {
		formatex(szMsg, charsmax(szMsg), "%L - [\rOFF\w]", id, "MAINMENU_PAUSE");
	}
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L^n", id, "MAINMENU_START");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "MAINMENU_STUCK");
	menu_additem(iMenu, szMsg);

	if (kz_can_undo_gocheck(id)) {
		formatex(szMsg, charsmax(szMsg), "\yUnGocheck^n");
	} else {
		formatex(szMsg, charsmax(szMsg), "\dUnGocheck^n");
	}
	menu_additem(iMenu, szMsg);

	if (bNoclipEnabled) {
		formatex(szMsg, charsmax(szMsg), "%L - [\yON\w]", id, "MAINMENU_NOCLIP");
	} else {
		formatex(szMsg, charsmax(szMsg), "%L - [\rOFF\w]", id, "MAINMENU_NOCLIP");
	}
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L^n", id, "MAINMENU_SPEC");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "MAINMENU_INVIS");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "MAINMENU_LJS");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L^n", id, "MAINMENU_SETTINGS");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "MAINMENU_MUTE");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L^n", id, "MAINMENU_WEAPONS");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "\rStop Timer");
	menu_additem(iMenu, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "BACK");
	menu_setprop(iMenu, MPROP_BACKNAME, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "MORE");
	menu_setprop(iMenu, MPROP_NEXTNAME, szMsg);

	formatex(szMsg, charsmax(szMsg), "%L", id, "EXIT");
	menu_setprop(iMenu, MPROP_EXITNAME, szMsg);

	g_bMainMenuOpened[id] = true;
	menu_display(id, iMenu);

	return PLUGIN_HANDLED;
}

public MainMenu_Handler(id, menu, item) {
	g_bMainMenuOpened[id] = false;
	menu_destroy(menu);

	if (item == MENU_EXIT)
		return PLUGIN_HANDLED;

	new bool:bReopenMainMenu = true;

	switch(item) {
		case 0: amxclient_cmd(id, "cp");
		case 1: amxclient_cmd(id, "tp");
		case 2: amxclient_cmd(id, "p");
		case 3: amxclient_cmd(id, "start");
		case 4: amxclient_cmd(id, "stuck");
		case 5: amxclient_cmd(id, "ungocheck");
		case 6: amxclient_cmd(id, "nc");
		case 7: amxclient_cmd(id, "ct");
		case 8: {
			amxclient_cmd(id, "invis");
			bReopenMainMenu = false;
		}
		case 9: {
			amxclient_cmd(id, "say", "/ljsmenu");
			bReopenMainMenu = false;
		}
		case 10: {
			amxclient_cmd(id, "settings");
			bReopenMainMenu = false;
		}
		case 11: amxclient_cmd(id, "mute");
		case 12: amxclient_cmd(id, "weapons");
		case 13: amxclient_cmd(id, "stop");
		default: return PLUGIN_HANDLED;
	}

	if (bReopenMainMenu && is_user_connected(id)) {
		new iCurrentMenu, iNewMenu;
		player_menu_info(id, iCurrentMenu, iNewMenu);

		if (iNewMenu > -1) {
			menu_cancel(id);
		}

		cmdMainMenu(id);
	}

	return PLUGIN_HANDLED;
}

@initMapTierHandler(QueryState, Handle:hQuery, szError[], iError, szData[], iLen, Float:fQueryTime) {
	switch (QueryState) {
		case TQUERY_CONNECT_FAILED, TQUERY_QUERY_FAILED: {
			UTIL_LogToFile(MYSQL_LOG, "ERROR", "initMapTierHandler", "[%d] %s (%.2f sec)", iError, szError, fQueryTime);
			SQL_FreeHandle(hQuery);
			
			return PLUGIN_HANDLED;
		}
	}

	if (SQL_NumResults(hQuery) > 0) {
		SQL_ReadResult(hQuery, 0, g_MapTierInfo[eMapSource], 15);
		SQL_ReadResult(hQuery, 1, g_MapTierInfo[eMapTierSimen], 63);
		SQL_ReadResult(hQuery, 2, g_MapTierInfo[eMapTierRush], 63);
	}

	if (equali(g_MapTierInfo[eMapSource], "cr")) {
    	g_MapTierInfo[eMapSource] = "CSKZCN";
	} else if (equali(g_MapTierInfo[eMapSource], "unknown")) {
   		g_MapTierInfo[eMapSource] = "Unknown";
	} else {
    	strtoupper(g_MapTierInfo[eMapSource]);
    }
    
	new szTierSelected[64];
	copy(szTierSelected, charsmax(szTierSelected), g_MapTierInfo[eMapTierSimen]);
	trim(szTierSelected);

	if (!szTierSelected[0] || equali(szTierSelected, "Unknown")) {
		copy(szTierSelected, charsmax(szTierSelected), g_MapTierInfo[eMapTierRush]);
		trim(szTierSelected);
	}

	if (!szTierSelected[0] || equali(szTierSelected, "Unknown")) {
		format(g_MapTierInfo[eMapTierDisplay], charsmax(g_MapTierInfo[eMapTierDisplay]), "\dUnknown");
	} else {
		format(g_MapTierInfo[eMapTierDisplay], charsmax(g_MapTierInfo[eMapTierDisplay]), "\y%s", szTierSelected);
	}

	SQL_FreeHandle(hQuery);
	return PLUGIN_HANDLED;
}

#if defined USE_MAP_MANAGER_INTERGRATION

public mapm_vote_canceled() {
	openMenuAfterVote();
}

public mapm_vote_finished() {
	openMenuAfterVote();
}

openMenuAfterVote() {
	for (new id = 1; id <= MAX_PLAYERS; ++id) {
		if (!is_user_alive(id) || is_user_bot(id)) continue;

		amxclient_cmd(id, "menu");
	}
}

#endif
