#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <fakemeta_stocks>
#include <engine>
#include <xs>
#include <fun>
#include <cellarray>

#include <reapi>

#define CC_COLORS_TYPE CC_COLORS_SHORT
#include <cromchat>

#pragma semicolon 1
#pragma ctrlchar '\'

#define PLUGIN "GameChaos's Longjumps"
#define VERSION "2.0.0dev"
#define AUTHOR "GameChaos"

#if defined DEBUG
#define DEBUG_CHAT(%1) ChatPrint(%1);
#define DEBUG_CONSOLE(%1) ClientAndSpecsPrintConsole(%1);
#else
#define DEBUG_CHAT(%1)
#define DEBUG_CONSOLE(%1)
#endif

// Speed/FOG HUD: use a dedicated classic HUD channel to avoid dhud ghosting.
const SPEED_HUD_CHANNEL = 5;
const Float:SPEED_HUD_HOLDTIME = 0.10;
// Move right-side strafe stats slightly to upper-right.
const Float:HUD_STRAFESTATS_SHIFT_X = 0.06;
const Float:HUD_STRAFESTATS_SHIFT_Y = -0.07;

#if defined(USE_SQL)
#include <sqlx>
#include <geoip>
#endif

#include <gcljs>

new g_szJumpTypes[JumpType][16] = {
	"NONE",
	"DD",
	"GS",
	"LJ",
	"CJ",
	"DCJ",
	"MCJ",
	"SCJ",
	"WJ",
	"LDJ",
	"BH",
	"DBH",
	"SBJ",
	"SLJ",
};

new g_szStrafeTypeChar[StrafeType] = {
	'0', // STRAFETYPE_OVERLAP
	'~', // STRAFETYPE_NONE
	
	'<', // STRAFETYPE_LEFT
	'1', // STRAFETYPE_OVERLAP_LEFT
	'2', // STRAFETYPE_NONE_LEFT
	
	'>', // STRAFETYPE_RIGHT
	'1', // STRAFETYPE_OVERLAP_RIGHT
	'2', // STRAFETYPE_NONE_RIGHT
};

new bool:g_jumpTypePrintable[JumpType] = {
	false, // JUMPTYPE_NONE,
	false, // double duck with FOG > 8
	false, // groundstrafe: double duck with FOG <= 8
	
	true, // longjump
	true, // countjump
	true, // double countjump
	true, // multi countjump
	true, // standup countjump
	true, // weirdjump
	true, // ladderjump
	true, // ducked bunnyhop
	true, // bunnyhop
	true, // standup bunnyjump
	true, // standup longjump
};

new g_jumpDirString[JumpDir][16] = {
	"Forwards",
	"Backwards",
	"Sideways",
	"Sideways"
};

new g_jumpDirForwardButton[JumpDir] = {
	IN_FORWARD,
	IN_BACK,
	IN_MOVELEFT,
	IN_MOVERIGHT,
};

new g_jumpDirLeftButton[JumpDir] = {
	IN_MOVELEFT,
	IN_MOVERIGHT,
	IN_BACK,
	IN_FORWARD,
};

new g_jumpDirRightButton[JumpDir] = {
	IN_MOVERIGHT,
	IN_MOVELEFT,
	IN_FORWARD,
	IN_BACK,
};

new g_weaponNames[31][16] = {
	"None",       // CSW_NONE            0
	"P228",       // CSW_P228            1
	"Shield?",    // CSW_GLOCK           2  // Unused by game, See CSW_GLOCK18.
	"Scout",      // CSW_SCOUT           3
	"HE Grenade", // CSW_HEGRENADE       4
	"XM1014",     // CSW_XM1014          5
	"C4",         // CSW_C4              6
	"MAC-10",     // CSW_MAC10           7
	"AUG",        // CSW_AUG             8
	"Smoke",      // CSW_SMOKEGRENADE    9
	"Elites",     // CSW_ELITE           10
	"Five-seveN", // CSW_FIVESEVEN       11
	"UMP45",      // CSW_UMP45           12
	"SG 550",     // CSW_SG550           13
	"Galil",      // CSW_GALIL           14
	"Famas",      // CSW_FAMAS           15
	"USP",        // CSW_USP             16
	"Glock",      // CSW_GLOCK18         17
	"AWP",        // CSW_AWP             18
	"MP5",        // CSW_MP5NAVY         19
	"M249",       // CSW_M249            20
	"M3",         // CSW_M3              21
	"M4A1",       // CSW_M4A1            22
	"TMP",        // CSW_TMP             23
	"G3SG1",      // CSW_G3SG1           24
	"Flashbang",  // CSW_FLASHBANG       25
	"Deagle",     // CSW_DEAGLE          26
	"SG 552",     // CSW_SG552           27
	"AK-47",      // CSW_AK47            28
	"Knife",      // CSW_KNIFE           29
	"P-90"        // CSW_P90             30
	// CSW_VEST            31  // Custom
	// CSW_VESTHELM        32  // Custom
	// CSW_SHIELDGUN       99
	// CSW_LAST_WEAPON     CSW_P90
};

new g_hudBeamData[GC_MAX_PLAYERS][HudAndBeamData];

new g_pd[GC_MAX_PLAYERS][PlayerData];

// circular buffer of frames.
new g_replay[GC_MAX_PLAYERS][MAX_JUMP_FRAMES][FrameData];
new g_replayTally[GC_MAX_PLAYERS][ReplayTally];

new g_preJumpGround[GC_MAX_PLAYERS];

new g_beamSprite;

new g_cvars[OPT_COUNT][Option] = {
	{"gcljs_enable",                   "1", "Enable plugin",               0, 1, OPT_ENABLE_PLUGIN},
	{"gcljs_enable_sounds",            "1", "Enable sounds",               0, 1, OPT_ENABLE_SOUNDS},
	{"gcljs_enable_failstat_sounds",   "0", "Enable failstat sounds",      0, 1, OPT_ENABLE_FAILSTAT_SOUNDS},
	{"gcljs_enable_speed",             "1", "Show speed",                  0, 1, OPT_SHOW_SPEED},
	{"gcljs_show_hud_graph",           "1", "Show graph in HUD",           0, 1, OPT_SHOW_HUD_GRAPH},
	{"gcljs_show_hud_strafe_stats",    "1", "Show strafe stats in HUD",    0, 1, OPT_SHOW_HUD_STRAFE_STATS},
	{"gcljs_show_hud_jump_stats",      "1", "Show jump stats in HUD",      0, 1, OPT_SHOW_HUD_JUMP_STATS},
	{"gcljs_hud_stats_vertical",       "0", "Format HUD stats vertically", 0, 1, OPT_HUD_STATS_VERTICAL},
	{"gcljs_show_jump_beam",           "0", "Show jump beam",              0, 1, OPT_SHOW_JUMP_BEAM},
	{"gcljs_show_veer_beam",           "0", "Show veer beam",              0, 1, OPT_SHOW_VEER_BEAM},
	{"gcljs_clear_hud_and_beam_on_tp", "0", "Clear HUD & beam on tp",      0, 1, OPT_CLEAR_HUD_BEAM_ON_TP},
	{"gcljs_hud_jump_info_x",          "-1.0", "Jump info X",    _:(-1.0), _:(1.0), OPT_JUMP_INFO_X,    OPT_TAG_FLOAT},
	{"gcljs_hud_jump_info_y",          "0.1",  "Jump info Y",    _:(-1.0), _:(1.0), OPT_JUMP_INFO_Y,    OPT_TAG_FLOAT},
	{"gcljs_hud_strafe_graph_x",       "-1.0", "Strafe graph X", _:(-1.0), _:(1.0), OPT_STRAFE_GRAPH_X, OPT_TAG_FLOAT},
	{"gcljs_hud_strafe_graph_y",       "0.2",  "Strafe graph Y", _:(-1.0), _:(1.0), OPT_STRAFE_GRAPH_Y, OPT_TAG_FLOAT},
	{"gcljs_hud_strafe_stats_x",       "0.6",  "Strafe stats X", _:(-1.0), _:(1.0), OPT_STRAFE_STATS_X, OPT_TAG_FLOAT},
	{"gcljs_hud_strafe_stats_y",       "0.5",  "Strafe stats Y", _:(-1.0), _:(1.0), OPT_STRAFE_STATS_Y, OPT_TAG_FLOAT},
	{"gcljs_hud_speed_x",              "-1.0", "Hud speed X",    _:(-1.0), _:(1.0), OPT_SPEED_X,        OPT_TAG_FLOAT},
	{"gcljs_hud_speed_y",              "0.7",  "Hud speed Y",    _:(-1.0), _:(1.0), OPT_SPEED_Y,        OPT_TAG_FLOAT}
};

new g_options[GC_MAX_PLAYERS][OPT_COUNT];
new g_cvarMinDist[JumpType][JumpTier];
new g_cvarAiraccelerate;
new g_cvarSaveReplays; // TODO: this is only temporary!

#if defined USE_SQL

new Handle:g_sqlTuple;
new g_cvarGcljsSqlHost;
new g_cvarGcljsSqlUser;
new g_cvarGcljsSqlPass;
new g_cvarGcljsSqlDb;
new g_createJumpQueryTable[1024];
new g_createStatQueryTable[512] = "CREATE TABLE IF NOT EXISTS `strafedata` (`id` INT AUTO_INCREMENT PRIMARY KEY, `jumpid` INT, `num` INT(11), `sync` FLOAT, `gain` FLOAT, `loss` FLOAT, `max` FLOAT, `air` INT(11),`overlap` INT(11), `deadair` INT(11), `avggain` FLOAT, `avgeff` INT(11), `maxeff` INT(11))";

#endif

#if defined DEBUG
#include "gcljs/debug.sma"
#endif

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_forward(FM_CmdStart, "CmdStart");
	register_forward(FM_StartFrame, "StartFrame");
	register_forward(FM_PlayerPreThink, "PlayerPreThink");
	register_forward(FM_PlayerPostThink, "PlayerPostThink");

	RegisterHookChain(RG_PM_Move, "Hook_PM_MovePre");
	RegisterHookChain(RG_PM_Jump, "Hook_PM_JumpPre");
	RegisterHookChain(RG_PM_Jump, "Hook_PM_JumpPost", .post = true);
	RegisterHookChain(RG_PM_LadderMove, "Hook_PM_LadderMovePre");

	for (new i = 0; i < GC_MAX_PLAYERS; i++)
	{
		g_preJumpGround[i] = -1;
	}
	
	RegisterChatAndConsoleCmd("gcspeed", "gcljs_gcspeed", "CommandGCspeed", .info = "Toggle speed panel");
	RegisterChatAndConsoleCmd("jumpbeam", "gcljs_jumpbeam", "CommandJumpBeam", .info = "Toggle jump beam.");
	RegisterChatAndConsoleCmd("veerbeam", "gcljs_veerbeam", "CommandVeerBeam", .info = "Toggle veer beam.");
	RegisterChatAndConsoleCmd("gcljs", "gcljs_options", "CommandOptions", .info = "Personalise your options.");
	
	RegisterChatAndConsoleCmd("gcljs_savedefaults", "gcljs_savedefaults", "CommandSaveDefaults", ADMIN_CVAR, "Save cvars.");
	RegisterChatAndConsoleCmd("gcljs_defaults", "gcljs_defaults", "CommandDefaults", ADMIN_CVAR, "Show options menu.");
	
	for (new OptionType:i = OptionType:0; i < OPT_COUNT; i++)
	{
		if (g_cvars[i][OP_OPTION_TYPE] != i)
		{
			new buffer[256];
			formatex(buffer, charsmax(buffer), "cvar %s stored type doesn't match enum type!", g_cvars[i][OP_NAME]);
			set_fail_state(buffer);
		}
		g_cvars[i][OP_CVAR] = register_cvar(g_cvars[i][OP_NAME], g_cvars[i][OP_DEFAULT_VALUE]);
	}
	// TODO: make this a for loop lmao
	//  and after/or make this a cfg file instead of cvars
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_0]        = register_cvar("gcljs_lj_min_dist_tier0", "210.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_1]        = register_cvar("gcljs_lj_min_dist_tier1", "245.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_2]        = register_cvar("gcljs_lj_min_dist_tier2", "250.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_3]        = register_cvar("gcljs_lj_min_dist_tier3", "253.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_4]        = register_cvar("gcljs_lj_min_dist_tier4", "255.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_5]        = register_cvar("gcljs_lj_min_dist_tier5", "257.0");
	g_cvarMinDist[JUMPTYPE_LJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_lj_max_dist", "270.0");
	
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_0]        = register_cvar("gcljs_cj_min_dist_tier0", "220.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_1]        = register_cvar("gcljs_cj_min_dist_tier1", "253.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_2]        = register_cvar("gcljs_cj_min_dist_tier2", "257.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_3]        = register_cvar("gcljs_cj_min_dist_tier3", "263.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_4]        = register_cvar("gcljs_cj_min_dist_tier4", "267.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_5]        = register_cvar("gcljs_cj_min_dist_tier5", "270.0");
	g_cvarMinDist[JUMPTYPE_CJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_cj_max_dist", "280.0");
	
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_0]        = register_cvar("gcljs_dcj_min_dist_tier0", "220.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_1]        = register_cvar("gcljs_dcj_min_dist_tier1", "255.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_2]        = register_cvar("gcljs_dcj_min_dist_tier2", "265.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_3]        = register_cvar("gcljs_dcj_min_dist_tier3", "268.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_4]        = register_cvar("gcljs_dcj_min_dist_tier4", "272.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_5]        = register_cvar("gcljs_dcj_min_dist_tier5", "275.0");
	g_cvarMinDist[JUMPTYPE_DCJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_dcj_max_dist", "285.0");
	
	for (new JumpTier:i = JumpTier:0; i < JumpTier; i++)
	{
		g_cvarMinDist[JUMPTYPE_MCJ][i] = g_cvarMinDist[JUMPTYPE_DCJ][i];
	}
	
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_0]        = register_cvar("gcljs_scj_min_dist_tier0", "220.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_1]        = register_cvar("gcljs_scj_min_dist_tier1", "253.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_2]        = register_cvar("gcljs_scj_min_dist_tier2", "257.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_3]        = register_cvar("gcljs_scj_min_dist_tier3", "263.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_4]        = register_cvar("gcljs_scj_min_dist_tier4", "267.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_5]        = register_cvar("gcljs_scj_min_dist_tier5", "270.0");
	g_cvarMinDist[JUMPTYPE_SCJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_scj_max_dist", "280.0");
	
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_0]        = register_cvar("gcljs_wj_min_dist_tier0", "220.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_1]        = register_cvar("gcljs_wj_min_dist_tier1", "255.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_2]        = register_cvar("gcljs_wj_min_dist_tier2", "265.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_3]        = register_cvar("gcljs_wj_min_dist_tier3", "268.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_4]        = register_cvar("gcljs_wj_min_dist_tier4", "272.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_5]        = register_cvar("gcljs_wj_min_dist_tier5", "275.0");
	g_cvarMinDist[JUMPTYPE_WJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_wj_max_dist", "285.0");
	
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_0]        = register_cvar("gcljs_ldj_min_dist_tier0", "110.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_1]        = register_cvar("gcljs_ldj_min_dist_tier1", "160.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_2]        = register_cvar("gcljs_ldj_min_dist_tier2", "170.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_3]        = register_cvar("gcljs_ldj_min_dist_tier3", "175.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_4]        = register_cvar("gcljs_ldj_min_dist_tier4", "185.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_5]        = register_cvar("gcljs_ldj_min_dist_tier5", "190.0");
	g_cvarMinDist[JUMPTYPE_LDJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_ldj_max_dist", "220.0");
	
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_0]        = register_cvar("gcljs_bh_min_dist_tier0", "200.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_1]        = register_cvar("gcljs_bh_min_dist_tier1", "230.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_2]        = register_cvar("gcljs_bh_min_dist_tier2", "235.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_3]        = register_cvar("gcljs_bh_min_dist_tier3", "240.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_4]        = register_cvar("gcljs_bh_min_dist_tier4", "243.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_5]        = register_cvar("gcljs_bh_min_dist_tier5", "246.0");
	g_cvarMinDist[JUMPTYPE_BH][JUMPTIER_MAX_DIST] = register_cvar("gcljs_bh_max_dist", "260.0");
	
	// NOTE: idk what good distance for duckbhop are
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_0]        = register_cvar("gcljs_dbh_min_dist_tier0", "150.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_1]        = register_cvar("gcljs_dbh_min_dist_tier1", "210.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_2]        = register_cvar("gcljs_dbh_min_dist_tier2", "215.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_3]        = register_cvar("gcljs_dbh_min_dist_tier3", "220.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_4]        = register_cvar("gcljs_dbh_min_dist_tier4", "225.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_5]        = register_cvar("gcljs_dbh_min_dist_tier5", "228.0");
	g_cvarMinDist[JUMPTYPE_DBH][JUMPTIER_MAX_DIST] = register_cvar("gcljs_dbh_max_dist", "260.0");
	
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_0]        = register_cvar("gcljs_sbj_min_dist_tier0", "200.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_1]        = register_cvar("gcljs_sbj_min_dist_tier1", "230.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_2]        = register_cvar("gcljs_sbj_min_dist_tier2", "235.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_3]        = register_cvar("gcljs_sbj_min_dist_tier3", "240.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_4]        = register_cvar("gcljs_sbj_min_dist_tier4", "245.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_5]        = register_cvar("gcljs_sbj_min_dist_tier5", "248.0");
	g_cvarMinDist[JUMPTYPE_SBJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_sbj_max_dist", "260.0");
	
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_0]        = register_cvar("gcljs_slj_min_dist_tier0", "210.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_1]        = register_cvar("gcljs_slj_min_dist_tier1", "247.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_2]        = register_cvar("gcljs_slj_min_dist_tier2", "252.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_3]        = register_cvar("gcljs_slj_min_dist_tier3", "255.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_4]        = register_cvar("gcljs_slj_min_dist_tier4", "257.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_5]        = register_cvar("gcljs_slj_min_dist_tier5", "259.0");
	g_cvarMinDist[JUMPTYPE_SLJ][JUMPTIER_MAX_DIST] = register_cvar("gcljs_slj_max_dist", "280.0");
	
	g_cvarAiraccelerate = get_cvar_pointer("sv_airaccelerate");
	
	g_cvarSaveReplays = register_cvar("gcljs_save_replays", "0");

#if defined USE_SQL
	g_cvarGcljsSqlHost = register_cvar("gcljs_sql_host", "");
	g_cvarGcljsSqlUser = register_cvar("gcljs_sql_user", "");
	g_cvarGcljsSqlPass = register_cvar("gcljs_sql_pass", "", FCVAR_PROTECTED);
	g_cvarGcljsSqlDb = register_cvar("gcljs_sql_db", "");
	
	set_task(1.0, "SQL_ConnectHandle");
	
#endif

#if defined DEBUG
	plugin_init_debug();
#endif
}

public plugin_cfg()
{
	AutoExecConfig(.name = GCLJS_CONFIG_NAME);
	
	for (new client = 0; client < GC_MAX_PLAYERS; client++)
	{
		for (new OptionType:i = OptionType:0; i < OPT_COUNT; i++)
		{
			if (g_cvars[i][OP_TAG] == OPT_TAG_INTEGER)
			{
				g_options[client][i] = GetDefaultOptionInt(i);
			}
			else if (g_cvars[i][OP_TAG] == OPT_TAG_FLOAT)
			{
				g_options[client][i] = _:GetDefaultOptionFloat(i);
			}
		}
	}
}

public plugin_precache()
{
	precache_sound(SOUND_PATH_TIER_1);
	precache_sound(SOUND_PATH_TIER_2);
	precache_sound(SOUND_PATH_TIER_3);
	precache_sound(SOUND_PATH_TIER_4);
	precache_sound(SOUND_PATH_TIER_5);
	
	g_beamSprite = precache_model("sprites/zbeam2.spr");
}

public client_putinserver(client)
{
	g_replayTally[client][RT_FRAMEINDEX] = 0;
	g_replayTally[client][RT_FRAMECOUNT] = 0;
	
	g_pd[client][USERCMD_COUNT] = 0;
	g_pd[client][TIME_MSEC] = 0;
	g_preJumpGround[client] = -1;
	
	PDResetJumpData(g_pd[client]);
}

#if defined USE_SQL

public SQL_ConnectHandle()
{
	new host[64];
	new user[64];
	new pass[64];
	new db[64];
	get_pcvar_string(g_cvarGcljsSqlHost, host, charsmax(host));
	get_pcvar_string(g_cvarGcljsSqlUser, user, charsmax(user));
	get_pcvar_string(g_cvarGcljsSqlPass, pass, charsmax(pass));
	get_pcvar_string(g_cvarGcljsSqlDb, db, charsmax(db));
	
	SQL_SetAffinity("mysql");
	
	g_sqlTuple = SQL_MakeDbTuple(host, user, pass, db);
	
	// pawn doesn't like long strings for some reason :(
	static bool:formatted = false;
	if (!formatted)
	{
		formatex(g_createJumpQueryTable, charsmax(g_createJumpQueryTable), "%s %s",
			"CREATE TABLE IF NOT EXISTS `jumpdata` (`id` INT AUTO_INCREMENT PRIMARY KEY, `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP, `steamid` VARCHAR(64) NOT NULL, `name` VARCHAR(64), `country` varchar(6) NOT NULL, `failed` TINYINT(1), `type` INT(11), `dist` FLOAT, `xjdist` FLOAT, `block` FLOAT, `hasblock` TINYINT(1), `edge` FLOAT, `hasedge` TINYINT(1), `landedge` FLOAT, `veer` FLOAT,",
			"`fwdrelease` FLOAT, `sync` FLOAT, `maxspeed` FLOAT, `prespeed` FLOAT, `overlap` FLOAT, `deadair` FLOAT,`jofangle` FLOAT, `airpath` FLOAT, `strafes` INT(11), `airtime` FLOAT, `direction` VARCHAR(255), `fog` FLOAT, `hasfog` TINYINT(1), `height` FLOAT, `hasstamina` TINYINT(1), `stamina` FLOAT, `loss` FLOAT, `potency` FLOAT)");
		formatted = true;
	}
	// Get last MAX id from jumpdata to save strafes
	SQL_ThreadQuery(g_sqlTuple, "PostQuery", g_createJumpQueryTable);
	SQL_ThreadQuery(g_sqlTuple, "PostQuery", g_createStatQueryTable);

	return PLUGIN_CONTINUE;
}

public PostJumpAndStrafeData(failState, Handle:query, error[], errcode, pd[PlayerData], dataSize)
{
	if (failState == TQUERY_CONNECT_FAILED || failState == TQUERY_QUERY_FAILED)
	{
		set_fail_state("%s Jumpdata query failed: %s", CONSOLE_PREFIX, error);
		return PLUGIN_CONTINUE;
	}
	
	if (errcode)
	{
		log_amx("%s Error on jumpdata query: %s", CONSOLE_PREFIX, error);
		return PLUGIN_CONTINUE;
	}
	else
	{
		if (SQL_NumResults(query))
		{
			new jumpid = SQL_ReadResult(query, 0);
			// Insert Strafe data into db
			static strafeQuery[512];
			new strafeCount = min(pd[STRAFE_COUNT] + 1, MAX_STRAFES);
			for (new strafe; strafe <= strafeCount; strafe++)
			{
				formatex(strafeQuery, sizeof(strafeQuery), "INSERT INTO strafedata (jumpid, num, sync, gain, loss, max, air, overlap, deadair, avggain, avgeff, maxeff) VALUES (%i, %i, %f, %f, %f, %f, %i, %i, %i, %f, %i, %i)",
					jumpid, strafe + 1,
					pd[STRAFE_SYNC][strafe], pd[STRAFE_GAIN][strafe],
					pd[STRAFE_LOSS][strafe], pd[STRAFE_MAX][strafe],
					pd[STRAFE_AIRTIME][strafe], pd[STRAFE_OVERLAP][strafe],
					pd[STRAFE_DEADAIR][strafe], Float:pd[STRAFE_AVG_GAIN][strafe],
					floatround(pd[STRAFE_AVG_EFFICIENCY][strafe]), floatround(pd[STRAFE_PEAK_EFFICIENCY][strafe]));
				
				SQL_ThreadQuery(g_sqlTuple, "PostQuery", strafeQuery);
			}
		}
	}
	SQL_FreeHandle(query);
	return PLUGIN_CONTINUE;
}

public PostQuery(failState, Handle:query, error[], errcode, data[], dataSize)
{
	if (failState == TQUERY_CONNECT_FAILED || failState == TQUERY_QUERY_FAILED)
	{
		// HACK HACK(sitka): damn ugly fix for the mysql socket path problem i cannot solve, but hey IT WORKS for now
		new mapName[64];
		get_mapname(mapName, sizeof(mapName));
		server_cmd("changelevel %s", mapName);
		return set_fail_state("%s Query failed: %s", CONSOLE_PREFIX, error);
	}
	
	if (errcode)
	{
		log_amx("%s Error on query: %s", CONSOLE_PREFIX, error);
		return PLUGIN_CONTINUE;
	}
	else
	{
		if (SQL_NumResults(query))
		{
			SQL_ReadResult(query, 0);
		}
	}
	SQL_FreeHandle(query);
	return PLUGIN_CONTINUE;
}

#endif

public CommandGCspeed(client, args)
{
	g_options[client][OPT_SHOW_SPEED] = !GetOptionInt(client, OPT_SHOW_SPEED);
	
	return PLUGIN_HANDLED;
}

public CommandJumpBeam(client, args)
{
	g_options[client][OPT_SHOW_JUMP_BEAM] = !GetOptionInt(client, OPT_SHOW_JUMP_BEAM);
	
	return PLUGIN_HANDLED;
}

public CommandVeerBeam(client, args)
{
	g_options[client][OPT_SHOW_VEER_BEAM] = !GetOptionInt(client, OPT_SHOW_VEER_BEAM);
	
	return PLUGIN_HANDLED;
}

public CommandOptions(client, args)
{
	ShowMenuOptions(client);
	return PLUGIN_HANDLED;
}

public CommandSaveDefaults(client, args)
{
	if (get_user_flags(client) & ADMIN_CVAR)
	{
		SaveDefaults();
	}
	ChatPrint(client, "%s Saved all cvars!", CHAT_PREFIX);
	return PLUGIN_HANDLED;
}

public CommandDefaults(client, args)
{
	if (get_user_flags(client) & ADMIN_CVAR)
	{
		ShowMenuDefaults(client);
	}
	return PLUGIN_HANDLED;
}

ShowMenuDefaults(client, page = 0)
{
	new menu = menu_create("\\gGCLJS Client Defaults", "MenuHandlerDefaults");
	
	menu_additem(menu, "\\rSave defaults", "", 0);
	
	new text[64];
	for (new OptionType:i = OPT_FIRST; i < OPT_COUNT; i++)
	{
		if (g_cvars[i][OP_TAG] == OPT_TAG_INTEGER)
		{
			if (g_cvars[i][OP_MIN] == 0 && g_cvars[i][OP_MAX] == 1)
			{
				formatex(text, charsmax(text), "%s: %s", g_cvars[i][OP_DESCRIPTION], GetDefaultOptionInt(i) ? "\\yYes" : "\\rNo");
			}
			else
			{
				formatex(text, charsmax(text), "%s: %i", g_cvars[i][OP_DESCRIPTION], GetDefaultOptionInt(i));
			}
		}
		else if (g_cvars[i][OP_TAG] == OPT_TAG_FLOAT)
		{
			// -1 is hud centre
			if (GetDefaultOptionFloat(i) == -1.0)
			{
				formatex(text, charsmax(text), "%s: \\yCentre", g_cvars[i][OP_DESCRIPTION]);
			}
			else
			{
				formatex(text, charsmax(text), "%s: \\y%.2f", g_cvars[i][OP_DESCRIPTION], GetDefaultOptionFloat(i) + 0.0001);
			}
		}
		menu_additem(menu, text, "", 0);
	}
	menu_display(client, menu, page);
}

public MenuHandlerDefaults(client, menu, item)
{
	if (item == 0)
	{
		SaveDefaults();
		ChatPrint(client, "%s Saved all cvars!", CHAT_PREFIX);
		ShowMenuDefaults(client);
	}
	else
	{
		new OptionType:type = OptionType:(item - 1);
		if (type >= OPT_FIRST && type < OPT_COUNT)
		{
			if (g_cvars[type][OP_TAG] == OPT_TAG_INTEGER)
			{
				IncrementCvar(g_cvars[type][OP_CVAR], g_cvars[type][OP_MIN], g_cvars[type][OP_MAX]);
			}
			else if (g_cvars[type][OP_TAG] == OPT_TAG_FLOAT)
			{
				new Float:newValue = (get_pcvar_float(g_cvars[type][OP_CVAR]) + 0.05);
				
				if (newValue < Float:g_cvars[type][OP_MIN]
					|| newValue > Float:g_cvars[type][OP_MAX]) // wrap around and fix negative values
				{
					newValue = Float:g_cvars[type][OP_MIN];
				}
				else if (Float:g_cvars[type][OP_MIN] == -1.0
					&& newValue < 0.0)
				{
					newValue = 0.0;
				}
				set_pcvar_float(g_cvars[type][OP_CVAR], newValue);
			}
			ShowMenuDefaults(client, item / 7);
		}
	}
	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

ShowMenuOptions(client, page = 0)
{
	new menu = menu_create("\\gGCLJS Player Options", "MenuHandlerOptions");
	
	new text[64];
	for (new OptionType:i = OPT_FIRST; i < OPT_COUNT; i++)
	{
		if (g_cvars[i][OP_TAG] == OPT_TAG_INTEGER)
		{
			if (g_cvars[i][OP_MIN] == 0 && g_cvars[i][OP_MAX] == 1)
			{
				formatex(text, charsmax(text), "%s: %s", g_cvars[i][OP_DESCRIPTION], GetOptionInt(client, i) ? "\\yYes" : "\\rNo");
			}
			else
			{
				formatex(text, charsmax(text), "%s: %i", g_cvars[i][OP_DESCRIPTION], GetOptionInt(client, i));
			}
		}
		else if (g_cvars[i][OP_TAG] == OPT_TAG_FLOAT)
		{
			// -1 is hud centre
			if (GetOptionFloat(client, i) == -1.0)
			{
				formatex(text, charsmax(text), "%s: \\yCentre", g_cvars[i][OP_DESCRIPTION]);
			}
			else
			{
				formatex(text, charsmax(text), "%s: \\y%.2f", g_cvars[i][OP_DESCRIPTION], GetOptionFloat(client, i) + 0.0001);
			}
		}
		menu_additem(menu, text, "", 0);
	}
	menu_display(client, menu, page);
}

public MenuHandlerOptions(client, menu, item)
{
	new OptionType:type = OptionType:item;
	if (type >= OPT_FIRST && type < OPT_COUNT)
	{
		if (g_cvars[type][OP_TAG] == OPT_TAG_INTEGER)
		{
			g_options[client][type] = GetOptionInt(client, type) + 1;
			if (GetOptionInt(client, type) > g_cvars[type][OP_MAX])
			{
				g_options[client][type] = g_cvars[type][OP_MIN];
			}
		}
		else if (g_cvars[type][OP_TAG] == OPT_TAG_FLOAT)
		{
			// increment by 0.05
			new Float:newValue = GetOptionFloat(client, type) + 0.05;
			if (newValue < Float:g_cvars[type][OP_MIN]
				|| newValue > Float:g_cvars[type][OP_MAX]) // wrap around and fix negatives
			{
				newValue = Float:g_cvars[type][OP_MIN];
			}
			else if (Float:g_cvars[type][OP_MIN] == -1.0
					 && newValue < 0.0)
			{
				newValue = 0.0;
			}
			g_options[client][type] = _:newValue;
		}
		ShowMenuOptions(client, item / 7);
	}
	menu_destroy(menu);
	return PLUGIN_HANDLED;
}

public Hook_PM_MovePre(const playerIndex)
{
	new client = playerIndex;
	if (client < 1 || client >= GC_MAX_PLAYERS)
	{
		return HC_CONTINUE;
	}

	g_pd[client][LADDER_ENTITY] = 0;
	g_pd[client][LADDER_MAXS][2] = _:GC_FLOAT_INFINITY;

	return HC_CONTINUE;
}

public Hook_PM_JumpPre(const playerIndex)
{
	new client = playerIndex;
	if (client < 1 || client >= GC_MAX_PLAYERS)
	{
		return HC_CONTINUE;
	}

	g_preJumpGround[client] = get_pmove(pm_onground);

	return HC_CONTINUE;
}

public Hook_PM_JumpPost(const playerIndex)
{
	new client = playerIndex;
	if (client < 1 || client >= GC_MAX_PLAYERS)
	{
		return HC_CONTINUE;
	}

	new onground = get_pmove(pm_onground);
	
	if (!(g_preJumpGround[client] != -1 && onground == -1))
	{
		return HC_CONTINUE;
	}
	
	new buttons = get_entvar(client, var_button);
	new usercmd = get_pmove(pm_cmd);
	if (usercmd)
	{
		buttons = get_ucmd(usercmd, ucmd_buttons);
	}
	
	new fd[FrameData];
	// get previous frame, current frame doesn't have proper data yet.
	GetReplayFrame(client, fd, 1);
	
	new bool:sbj = ((fd[FD_FLAGS] & FL_DUCKING
	&& !(buttons & IN_DUCK))
		|| (g_pd[client][LANDED_DUCKED] && !(buttons & IN_DUCK)));
	new bool:duckbhop = fd[FD_FLAGS] & FL_DUCKING && buttons & IN_DUCK;
	new Float:groundOffset = fd[FD_ORIGIN][2] - g_pd[client][LAST_GROUND_POS][2];
	new JumpType:jumpType = JUMPTYPE_NONE;
	if (g_pd[client][FRAMES_ON_GROUND] <= MAX_BHOP_FRAMES)
	{
		// NOTE: the -2.0 is an arbitrary value. it was chosen cos bhop blocks go slightly down when bhopping on them.
		// TODO: doublecheck this
		if (g_pd[client][LAST_GROUND_POS_WALKED_OFF] && groundOffset <= -2.0)
		{
			jumpType = JUMPTYPE_WJ;
		}
		else
		{
			// TODO: afterjump stats
			if (g_pd[client][JUMP_TYPE] == JUMPTYPE_DD)
			{
				if (sbj)
				{
					jumpType = JUMPTYPE_SCJ;
				}
				else
				{
					jumpType = JUMPTYPE_CJ;
				}
			}
			else if (g_pd[client][JUMP_TYPE] == JUMPTYPE_GS)
			{
				if (g_pd[client][LAST_JUMP_TYPE] == JUMPTYPE_GS)
				{
					jumpType = JUMPTYPE_MCJ;
				}
				else if (g_pd[client][LAST_JUMP_TYPE] == JUMPTYPE_DD)
				{
					jumpType = JUMPTYPE_DCJ;
				}
			}
			else if (g_pd[client][JUMP_TYPE] == JUMPTYPE_LDJ)
			{
				// prevent jumps from ladders counting as bhops.
				jumpType = JUMPTYPE_WJ;
			}
			else
			{
				if (sbj)
				{
					if (g_pd[client][LAST_GROUND_POS_WALKED_OFF]
						&& groundOffset == 0.0)
					{
						jumpType = JUMPTYPE_SLJ;
					}
					else
					{
						jumpType = JUMPTYPE_SBJ;
					}
				}
				else if (duckbhop)
				{
					jumpType = JUMPTYPE_DBH;
				}
				else
				{
					jumpType = JUMPTYPE_BH;
				}
			}
		}
	}
	else
	{
		jumpType = JUMPTYPE_LJ;
	}
	
	if (jumpType != JUMPTYPE_NONE)
	{
		new lastLastFrame = GetReplayFrameIndex(client, 2);
		// set jump velocity so that PM_PreventMegaBunnyJumping gets accounted for
		get_pmove(pm_velocity, fd[FD_VELOCITY]);
		OnPlayerJumped(g_pd[client], jumpType, fd, g_replay[client][lastLastFrame]);
	}
	
	PDCopyVector(fd[FD_ORIGIN], g_pd[client][LAST_GROUND_POS]);
	g_pd[client][LAST_GROUND_POS_WALKED_OFF] = false;

	return HC_CONTINUE;
}

public Hook_PM_LadderMovePre(const pLadder, const playerIndex)
{
	new client = playerIndex;
	if (client < 1 || client >= GC_MAX_PLAYERS)
	{
		return HC_CONTINUE;
	}
	if (!pLadder)
	{
		return HC_CONTINUE;
	}

	g_pd[client][LADDER_MAXS][2] = _:GC_FLOAT_INFINITY;

	new maxEntities = global_get(glb_maxEntities);
	if (pLadder > 0
		&& pLadder <= maxEntities
		&& is_entity(pLadder))
	{
		new Float:absmin[3];
		new Float:absmax[3];
		get_entvar(pLadder, var_absmin, absmin);
		get_entvar(pLadder, var_absmax, absmax);
		PDCopyVector(absmin, g_pd[client][LADDER_MINS]);
		PDCopyVector(absmax, g_pd[client][LADDER_MAXS]);

		new Float:normal[3];
		normal[0] = 0.0;
		normal[1] = 0.0;
		normal[2] = 1.0;
		PDCopyVector(normal, g_pd[client][LADDER_NORMAL]);
	}
	
	g_pd[client][LADDER_ENTITY] = pLadder;

	return HC_CONTINUE;
}

public CmdStart(client, ucHandle)
{
	g_pd[client][USERCMD_COUNT]++;
	g_pd[client][FRAMETIME_MSEC] = get_uc(ucHandle, UC_Msec);
	g_pd[client][TIME_MSEC] += g_pd[client][FRAMETIME_MSEC];
	
	if (!is_user_alive(client))
	{
		return;
	}
	
	if (!GetOptionInt(client, OPT_ENABLE_PLUGIN))
	{
		return;
	}
	
	// TODO: what to do about this? actual frame data gets
	//  updated in postthink, so functions that get called between this
	//  and postthink can very easily have invalid data if the
	//  programmer isn't careful.
	g_replayTally[client][RT_FRAMEINDEX]++;
	g_replayTally[client][RT_FRAMECOUNT]++;
	
	g_replayTally[client][RT_FRAMECOUNT] = min(g_replayTally[client][RT_FRAMECOUNT], MAX_JUMP_FRAMES);
	if (g_replayTally[client][RT_FRAMEINDEX] >= MAX_JUMP_FRAMES)
	{
		g_replayTally[client][RT_FRAMEINDEX] = 0;
	}
	
	new frameIndex = GetReplayFrameIndex(client);
	get_uc(ucHandle, UC_ForwardMove, g_replay[client][frameIndex][FD_WISHMOVE][0]);
	get_uc(ucHandle, UC_SideMove, g_replay[client][frameIndex][FD_WISHMOVE][1]);
	get_uc(ucHandle, UC_UpMove, g_replay[client][frameIndex][FD_WISHMOVE][2]);
}

public PlayerPostThink(client)
{
	if (!is_user_alive(client))
	{
		// reset when player isn't alive to avoid discontinuity
		g_replayTally[client][RT_FRAMECOUNT] = 0;
		g_replayTally[client][RT_FRAMEINDEX] = 0;
		return;
	}
	
	// framedata
	{
		new frameIndex = GetReplayFrameIndex(client);
		
		GetPlayerFeetPosition(client, g_replay[client][frameIndex][FD_ORIGIN]);
		GetPlayerVelocity(client, g_replay[client][frameIndex][FD_VELOCITY]);
		GetPlayerAngles(client, g_replay[client][frameIndex][FD_ANGLES]);
		g_replay[client][frameIndex][FD_STAMINA] = _:entity_get_float(client, EV_FL_fuser2);
		g_replay[client][frameIndex][FD_BUTTONS] = entity_get_int(client, EV_INT_button);
		g_replay[client][frameIndex][FD_FLAGS] = entity_get_int(client, EV_INT_flags);
		g_replay[client][frameIndex][FD_MOVETYPE] = pev(client, pev_movetype);
	}
	
	// last button and velocity etc might act weird if there aren't enough frames recorded.
	if (g_replayTally[client][RT_FRAMECOUNT] < 3)
	{
		DEBUG_CHAT(client, "not enough frames recorded for jump %i", g_replayTally[client][RT_FRAMECOUNT])
		return;
	}
	
	new fd[FrameData];
	new lastFd[FrameData];
	GetReplayFrame(client, fd);
	GetReplayFrame(client, lastFd, 1);
	
	for (new i = 0; i < 3; i++)
	{
		new FrameData:elem = FD_ANGLES + FrameData:i;
		g_pd[client][ANGLE_SPEED][i] = _:NormaliseYaw(GetReplayElemF(client, elem, 0) - GetReplayElemF(client, elem, 1));
		g_pd[client][LAST_ANGLE_SPEED][i] = _:NormaliseYaw(GetReplayElemF(client, elem, 1) - GetReplayElemF(client, elem, 2));
	}
	
	new flags = entity_get_int(client, EV_INT_flags);
	if (flags & FL_ONGROUND)
	{
#if defined DEBUG
		if (!g_pd[client][FRAMES_ON_GROUND])
		{
			DEBUG_CONSOLE(client, "[%i] FIA: %i\n", g_pd[client][USERCMD_COUNT], g_pd[client][FRAMES_IN_AIR])
		}
#endif
		g_pd[client][FRAMES_IN_AIR] = 0;
		g_pd[client][FRAMES_ON_GROUND]++;
	}
	else if (fd[FD_MOVETYPE] != MOVETYPE_FLY)
	{
#if defined DEBUG
		if (!g_pd[client][FRAMES_IN_AIR])
		{
			DEBUG_CONSOLE(client, "[%i] FOG: %i\n", g_pd[client][USERCMD_COUNT], g_pd[client][FRAMES_ON_GROUND])
		}
#endif
		g_pd[client][FRAMES_IN_AIR]++;
		g_pd[client][FRAMES_ON_GROUND] = 0;
	}
	
	if (GetOptionInt(client, OPT_SHOW_SPEED))
	{
		new Float:speed = VectorLengthXY(fd[FD_VELOCITY]);
		new Float:xOffset = GetOptionFloat(client, OPT_SPEED_X);
		new Float:yOffset = GetOptionFloat(client, OPT_SPEED_Y);
		new speedText[128];
		formatex(speedText, charsmax(speedText), "%.2f", speed);
		if (g_pd[client][SPEED_SHOW_PRESPEED])
		{
			if (g_pd[client][PRESPEED_FOG] <= MAX_BHOP_FRAMES
				&& g_pd[client][PRESPEED_FOG] >= 0)
			{
				format(speedText, charsmax(speedText), "%s\n(%.2f)\nFOG: %i",
					speedText, g_pd[client][JUMP_PRESPEED], g_pd[client][PRESPEED_FOG]);
			}
			else
			{
				format(speedText, charsmax(speedText), "%s\n(%.2f)", speedText, g_pd[client][JUMP_PRESPEED]);
			}
		}
		set_hudmessage(255, 255, 255, xOffset, yOffset, 0, 0.0, SPEED_HUD_HOLDTIME, 0.0, 0.0, SPEED_HUD_CHANNEL);
		show_hudmessage(client, "%s", speedText);
	}
	
	// LJ stuff
	if (!GetOptionInt(client, OPT_ENABLE_PLUGIN))
	{
		return;
	}
	
	if (g_pd[client][FRAMES_IN_AIR] == 1)
	{
		if (!xs_vec_equal(g_pd[client][LAST_GROUND_POS], lastFd[FD_ORIGIN]))
		{
			PDCopyVector(lastFd[FD_ORIGIN], g_pd[client][LAST_GROUND_POS]);
			g_pd[client][LAST_GROUND_POS_WALKED_OFF] = true;
		}
	}
	
	new bool:forwardReleased = (lastFd[FD_BUTTONS] & g_jumpDirForwardButton[g_pd[client][JUMP_DIR]])
		&& !(fd[FD_BUTTONS] & g_jumpDirForwardButton[g_pd[client][JUMP_DIR]]);
	if (forwardReleased)
	{
		g_pd[client][FWD_RELEASE_FRAME] = g_pd[client][USERCMD_COUNT];
	}
	
	if (fd[FD_MOVETYPE] == MOVETYPE_WALK && lastFd[FD_MOVETYPE] == MOVETYPE_FLY
		&& !g_pd[client][TRACKING_JUMP])
	{
		OnPlayerJumped(g_pd[client], JUMPTYPE_LDJ, fd, lastFd);
	}
	
	TrackJump(client, g_pd[client], fd, lastFd);
	
	if (g_pd[client][FRAMES_ON_GROUND] == 1)
	{
		OnPlayerLanded(client, g_pd[client], fd, lastFd);
	}
	
	new modulo = g_pd[client][USERCMD_COUNT] % 20;
	new Float:elapsed = float(g_pd[client][TIME_MSEC] - g_hudBeamData[client][HBD_TIMESTAMP_MSEC]) / 1000.0;
	if (elapsed < 3.0)
	{
		new Float:strafeGraphX = GetOptionFloat(client, OPT_STRAFE_GRAPH_X);
		new Float:strafeGraphY = GetOptionFloat(client, OPT_STRAFE_GRAPH_Y);
		new Float:time = 2.0;
		new bool:showHudGraph = !!GetOptionInt(client, OPT_SHOW_HUD_GRAPH);
		new bool:showHudStrafeStats = !!GetOptionInt(client, OPT_SHOW_HUD_STRAFE_STATS);
		new bool:showHudJumpStats = !!GetOptionInt(client, OPT_SHOW_HUD_JUMP_STATS);
		
		if (modulo == 0 && showHudJumpStats)
		{
			new Float:jumpInfoX = GetOptionFloat(client, OPT_JUMP_INFO_X);
			new Float:jumpInfoY = GetOptionFloat(client, OPT_JUMP_INFO_Y);
			set_hudmessage(255, 255, 255, jumpInfoX, jumpInfoY, 0, 0.0, time, .channel = 1);
			ClientAndSpecsHudmessage(client, "%s", g_hudBeamData[client][HUD_TOP_STRING]);
		}
		else if (modulo == 5 && showHudGraph)
		{
			set_hudmessage(255, 0, 0, strafeGraphX, strafeGraphY, 0, 0.0, time, .channel = 2);
			ClientAndSpecsHudmessage(client, "%s", g_hudBeamData[client][HUD_MLEFT_STRING]);
		}
		else if (modulo == 10 && showHudGraph)
		{
			set_hudmessage(0, 255, 255, strafeGraphX, strafeGraphY, 0, 0.0, time, .channel = 3);
			ClientAndSpecsHudmessage(client, "%s", g_hudBeamData[client][HUD_MRIGHT_STRING]);
		}
			else if (modulo == 15 && showHudStrafeStats)
			{
				new Float:strafeStatsX = GetOptionFloat(client, OPT_STRAFE_STATS_X) + HUD_STRAFESTATS_SHIFT_X;
				new Float:strafeStatsY = GetOptionFloat(client, OPT_STRAFE_STATS_Y) + HUD_STRAFESTATS_SHIFT_Y;
				strafeStatsX = floatclamp(strafeStatsX, -1.0, 1.0);
				strafeStatsY = floatclamp(strafeStatsY, -1.0, 1.0);
				set_hudmessage(0, 255, 255, strafeStatsX, strafeStatsY, 0, 0.0, time, .channel = 4);
				ClientAndSpecsHudmessage(client, "%s", g_hudBeamData[client][HUD_STRAFESTAT_STRING]);
			}
	}
	
	if (elapsed < 10.0 && modulo == 0)
	{
		new life = 2;
		if (GetOptionInt(client, OPT_SHOW_VEER_BEAM))
		{
			new beamEnd[3];
			beamEnd[0] = floatround(g_hudBeamData[client][VEERBEAM_END][0]);
			beamEnd[1] = floatround(g_hudBeamData[client][VEERBEAM_START][1]);
			beamEnd[2] = floatround(g_hudBeamData[client][VEERBEAM_END][2]);
			new jumpPos[3];
			new landPos[3];
			for (new i = 0; i < 3; i++)
			{
				jumpPos[i] = floatround(g_hudBeamData[client][VEERBEAM_START][i]);
				landPos[i] = floatround(g_hudBeamData[client][VEERBEAM_END][i]);
			}
			
			new alpha = 127;
			TE_SendBeamPoints(client, g_beamSprite, jumpPos, landPos, 255, 255, 255, alpha, .life = life);
			// x axis
			TE_SendBeamPoints(client, g_beamSprite, jumpPos, beamEnd, 255, 0, 0, alpha, .life = life);
			// y axis
			TE_SendBeamPoints(client, g_beamSprite, landPos, beamEnd, 0, 255, 0, alpha, .life = life);
		}
		
		if (GetOptionInt(client, OPT_SHOW_JUMP_BEAM))
		{
			new beamPos[3];
			new lastBeamPos[3];
			beamPos[0] = floatround(g_hudBeamData[client][VEERBEAM_START][0]);
			beamPos[1] = floatround(g_hudBeamData[client][VEERBEAM_START][1]);
			beamPos[2] = floatround(g_hudBeamData[client][VEERBEAM_START][2], floatround_ceil);
			// only draw every 2nd frame of data. this makes the beam smoother and reduces flicker.
			for (new i = 1; i < g_hudBeamData[client][HBD_FRAMES]; i += 2)
			{
				// make sure to draw the last point as well!
				if (i + 2 == g_hudBeamData[client][HBD_FRAMES])
				{
					i = g_hudBeamData[client][HBD_FRAMES] - 1;
				}
				
				lastBeamPos = beamPos;
				beamPos[0] = floatround(g_hudBeamData[client][HBD_JUMP_BEAM_X][i]);
				beamPos[1] = floatround(g_hudBeamData[client][HBD_JUMP_BEAM_Y][i]);
				
				new colour[3] = {255, 255, 0};
				if (g_hudBeamData[client][HBD_JUMP_BEAM_COLOUR][i] == JUMPBEAM_LOSS)
				{
					colour = {255, 0, 0};
				}
				else if (g_hudBeamData[client][HBD_JUMP_BEAM_COLOUR][i] == JUMPBEAM_GAIN)
				{
					colour = {0, 255, 0};
				}
				else if (g_hudBeamData[client][HBD_JUMP_BEAM_COLOUR][i] == JUMPBEAM_DUCK)
				{
					colour = {255, 0, 255};
				}
				
				TE_SendBeamPoints(client, g_beamSprite, lastBeamPos, beamPos, colour[0], colour[1], colour[2], 255, .life = life);
			}
		}
	}
}

public PlayerPreThink(client)
{
	if (!is_user_alive(client))
	{
		return;
	}
	
	if (!GetOptionInt(client, OPT_ENABLE_PLUGIN))
	{
		return;
	}
	
#if defined DEBUG
	PlayerPreThinkDebug(client);
#endif
	new buttons = entity_get_int(client, EV_INT_button);
	new oldButtons = entity_get_int(client, EV_INT_oldbuttons);
	
	new fd[FrameData];
	new lastFd[FrameData];
	// NOTE(GameChaos): tracking new frame has already started, get previous frame and the one before that
	GetReplayFrame(client, fd, 1);
	GetReplayFrame(client, lastFd, 2);
	
	if (!(buttons & IN_DUCK)
		&& oldButtons & IN_DUCK
		&& !(fd[FD_FLAGS] & FL_DUCKING))
	{
		new Float:startpos[3];
		new Float:endpos[3];
		PDCopyVector(fd[FD_ORIGIN], startpos);
		
		startpos[2] += 36.0 + GC_DUCK_HEIGHT_CHANGE;
		endpos = startpos;
		endpos[2] += GC_DUCK_HEIGHT_CHANGE;
		
		engfunc(EngFunc_TraceHull, startpos, endpos, IGNORE_MONSTERS, HULL_HEAD, 0, 0);
		
		new Float:fraction;
		get_tr2(0, TR_Fraction, fraction);
		if (fraction == 1.0)
		{
			// double ducked!
			PDCopyVector(lastFd[FD_ORIGIN], g_pd[client][LAST_GROUND_POS]);
			g_pd[client][LAST_GROUND_POS_WALKED_OFF] = false;
			if (g_pd[client][FRAMES_ON_GROUND] > MAX_GSTRAFE_FRAMES)
			{
				OnPlayerJumped(g_pd[client], JUMPTYPE_DD, fd, lastFd);
			}
			else
			{
				OnPlayerJumped(g_pd[client], JUMPTYPE_GS, fd, lastFd);
			}
		}
	}
}

GetOptionInt(client, OptionType:type)
{
	new result = 0;
	if (type >= OPT_FIRST && type < OPT_COUNT)
	{
		result = g_options[client][type];
	}
	return result;
}

Float:GetOptionFloat(client, OptionType:type)
{
	return Float:GetOptionInt(client, type);
}

GetDefaultOptionData_(OptionType:type)
{
	new result = 0;
	if (type >= OPT_FIRST && type < OPT_COUNT)
	{
		result = get_pcvar_num(g_cvars[type][OP_CVAR]);
	}
	else
	{
		new buffer[256];
		formatex(buffer, charsmax(buffer), "Option type %i is out of bounds!", type);
		set_fail_state(buffer);
	}
	return result;
}

GetDefaultOptionInt(OptionType:type)
{
	new result = GetDefaultOptionData_(type);
	if (g_cvars[type][OP_TAG] == OPT_TAG_INTEGER)
	{
		result = get_pcvar_num(g_cvars[type][OP_CVAR]);
	}
	else
	{
		new buffer[256];
		formatex(buffer, charsmax(buffer),
			"GetDefaultOptionInt() called on \"%s\" which isn't an int.",
				 g_cvars[type][OP_NAME]);
		set_fail_state(buffer);
	}
	return result;
}

Float:GetDefaultOptionFloat(OptionType:type)
{
	new Float:result = Float:GetDefaultOptionData_(type);
	if (g_cvars[type][OP_TAG] == OPT_TAG_FLOAT)
	{
		result = get_pcvar_float(g_cvars[type][OP_CVAR]);
	}
	else
	{
		new buffer[256];
		formatex(buffer, charsmax(buffer),
			"GetDefaultOptionFloat() called on \"%s\" which isn't a float.",
				 g_cvars[type][OP_NAME]);
		set_fail_state(buffer);
	}
	return result;
}

SaveDefaults()
{
	new szConfigPath[128];
	get_localinfo("amxx_configsdir", szConfigPath, charsmax(szConfigPath));
	format(szConfigPath, charsmax(szConfigPath), "%s/%s", szConfigPath, GCLJS_CONFIG_NAME);
	
	if (file_exists(szConfigPath))
	{
		delete_file(szConfigPath);
		AutoExecConfig(.name = GCLJS_CONFIG_NAME);
	}
}

ClientAndSpecsPrintChat(client, const format[], any:... )
{
	static message[1024];
	vformat(message, charsmax(message), format, 3);
	ChatPrint(client, message);
	
	for (new spec = 0; spec < GC_MAX_PLAYERS; spec++)
	{
		if (spec == client
			|| !is_user_connected(spec)
			|| is_user_bot(spec)
			|| is_user_alive(spec))
		{
			continue;
		}
		
		if (pev(spec, pev_iuser2) == client)
		{
			ChatPrint(spec, message);
		}
	}
}

ClientAndSpecsPrintConsole(client, const format[], any:... )
{
	static message[1024];
	vformat(message, charsmax(message), format, 3);
	message_begin(MSG_ONE, SVC_PRINT, .player = client);
	write_string(message);
	message_end();
	
	for (new spec = 0; spec < GC_MAX_PLAYERS; spec++)
	{
		if (spec == client
			|| !is_user_connected(spec)
			|| is_user_bot(spec)
			|| is_user_alive(spec))
		{
			continue;
		}
		
		if (pev(spec, pev_iuser2) == client)
		{
			message_begin(MSG_ONE, SVC_PRINT, .player = spec);
			write_string(message);
			message_end();
		}
	}
}

ClientAndSpecsHudmessage(client, const format[], any:... )
{
	static message[1024];
	vformat(message, charsmax(message), format, 3);
	show_hudmessage(client, message);
	
	for (new spec = 0; spec < GC_MAX_PLAYERS; spec++)
	{
		if (spec == client
			|| !is_user_connected(spec)
			|| is_user_bot(spec)
			|| is_user_alive(spec))
		{
			continue;
		}
		
		if (pev(spec, pev_iuser2) == client)
		{
			show_hudmessage(spec, message);
		}
	}
}

stock GetReplayFrameIndex(client, relativeIndex = 0)
{
	new rewindAmount = min(min(relativeIndex, g_replayTally[client][RT_FRAMECOUNT]), MAX_JUMP_FRAMES - 1);
	new index = g_replayTally[client][RT_FRAMEINDEX] - rewindAmount;
	if (index < 0)
	{
		index += MAX_JUMP_FRAMES;
	}
	return index;
}

// returns framedata that corresponds to g_replayTally[client][RT_FRAMEINDEEX] - relativeIndex, (and some more logic for wrapping and bounds checking)
stock GetReplayFrame(client, out[FrameData], relativeIndex = 0)
{
	new index = GetReplayFrameIndex(client, relativeIndex);
	out = g_replay[client][index];
}

stock GetReplayElem(client, FrameData:variable, relativeIndex = 0)
{
	new index = GetReplayFrameIndex(client, relativeIndex);
	new result = g_replay[client][index][variable];
	return result;
}

stock Float:GetReplayElemF(client, FrameData:variable, relativeIndex = 0)
{
	new index = GetReplayFrameIndex(client, relativeIndex);
	new Float:result = Float:(g_replay[client][index][variable]);
	return result;
}

PDResetJumpData(pd[PlayerData])
{
	// NOTE: only resets things that need to be reset
	for (new i = 0; i < 3; i++)
	{
		pd[JUMP_POS][i] = _:0.0;
		pd[LAND_POS][i] = _:0.0;
	}
	pd[TRACKING_JUMP] = false;
	pd[FAILED_JUMP] = false;
	
	// Jump data
	// NOTE: don't reset JUMP_TYPE or LAST_JUMP_TYPE
	pd[JUMP_MAXSPEED] = _:0.0;
	pd[JUMP_WEAPONSPEED] = _:0.0;
	pd[JUMP_LOSS] = _:0.0;
	pd[JUMP_SYNC] = _:0.0;
	pd[JUMP_POTENCY] = _:0.0;
	pd[JUMP_EDGE] = _:0.0;
	pd[JUMP_BLOCK_DIST] = _:0.0;
	pd[JUMP_HEIGHT] = _:0.0;
	pd[JUMP_AIRTIME] = 0;
	pd[JUMP_OVERLAP] = 0;
	pd[JUMP_DEADAIR] = 0;
	pd[JUMP_AIRPATH] = _:0.0;
	pd[JUMP_WEAPON] = -1;
	
	pd[STRAFE_COUNT] = 0;
	for (new i = 0; i < MAX_STRAFES; i++)
	{
		pd[STRAFE_SYNC][i] = _:0.0;
		pd[STRAFE_GAIN][i] = _:0.0;
		pd[STRAFE_LOSS][i] = _:0.0;
		pd[STRAFE_MAX][i] = _:0.0;
		pd[STRAFE_FRAME][i] = 0;
		pd[STRAFE_AIRTIME][i] = 0;
		pd[STRAFE_OVERLAP][i] = 0;
		pd[STRAFE_DEADAIR][i] = 0;
		pd[STRAFE_AVG_GAIN][i] = _:0.0;
		pd[STRAFE_AVG_EFFICIENCY][i] = _:0.0;
		pd[STRAFE_PEAK_EFFICIENCY][i] = _:GC_FLOAT_NEGATIVE_INFINITY;
	}
}

bool:IsWishspeedMovingLeft(Float:forwardspeed, Float:sidespeed, JumpDir:jumpDir)
{
	if (jumpDir == JUMPDIR_FORWARDS)
	{
		return sidespeed < 0.0;
	}
	else if (jumpDir == JUMPDIR_BACKWARDS)
	{
		return sidespeed > 0.0;
	}
	else if (jumpDir == JUMPDIR_LEFT)
	{
		return forwardspeed < 0.0;
	}
	// else if (jumpDir == JUMPDIR_RIGHT)
	return forwardspeed > 0.0;
}

bool:IsWishspeedMovingRight(Float:forwardspeed, Float:sidespeed, JumpDir:jumpDir)
{
	if (jumpDir == JUMPDIR_FORWARDS)
	{
		return sidespeed > 0.0;
	}
	else if (jumpDir == JUMPDIR_BACKWARDS)
	{
		return sidespeed < 0.0;
	}
	else if (jumpDir == JUMPDIR_LEFT)
	{
		return forwardspeed > 0.0;
	}
	// else if (jumpDir == JUMPDIR_RIGHT)
	return forwardspeed < 0.0;
}

bool:IsNewStrafe(pd[PlayerData])
{
	new lastSpeed = xs_fsign(pd[LAST_ANGLE_SPEED][1]);
	new speed = xs_fsign(pd[ANGLE_SPEED][1]);
	return ((speed > 0.0 && lastSpeed <= 0.0)
	       || (speed < 0.0 && lastSpeed >= 0.0))
	       && pd[JUMP_AIRTIME] != 1;
}

TrackJump(client, pd[PlayerData], fd[FrameData], lastFd[FrameData])
{
	if (!pd[TRACKING_JUMP])
	{
		return;
	}
	
	new frameIndex = pd[JUMP_AIRTIME]++;
	
	// Jump validation
	new Float:frametime = float(pd[FRAMETIME_MSEC]) / 1000.0;
	new Float:sv_gravity = get_cvar_float("sv_gravity");
	new Float:fallAcceleration = fd[FD_VELOCITY][2] - lastFd[FD_VELOCITY][2];
	new Float:expectedFallAccel = -(sv_gravity * frametime);
	new bool:isValidFallAccel = IsFloatInRange(fallAcceleration - expectedFallAccel, -0.0001, 0.0001);
	if (pd[FRAMES_IN_AIR] < 2)
	{
		// last frame was on ground
		isValidFallAccel = true;
	}
	// TODO: these jump invalidation checks are a little bit messy, fix.
	// crusty teleport detection
	{
		new Float:posDelta[3];
		xs_vec_sub(fd[FD_ORIGIN], lastFd[FD_ORIGIN], posDelta);
		
		new Float:moveLength = xs_vec_len(posDelta);
		// maxvelocity * ~vectorlen(1, 1, 1)
		new Float:maxMoveDistance = get_cvar_float("sv_maxvelocity") * 1.74;
		if (moveLength > maxMoveDistance * frametime)
		{
			DEBUG_CHAT(client, "jump invalidated: Movelength: %f frametime %f", moveLength, frametime)
			PDResetJumpData(g_pd[client]);
			if (GetDefaultOptionInt(OPT_CLEAR_HUD_BEAM_ON_TP) != 0)
			{
				g_hudBeamData[client][HBD_TIMESTAMP_MSEC] = -10000;
			}
			pd[TRACKING_JUMP] = false;
		}
	}
	
	new Float:playerGravity = get_user_gravity(client);
	if (pd[JUMP_TYPE] == JUMPTYPE_NONE)
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, jump type was none")
	}
	else if (!g_jumpTypePrintable[pd[JUMP_TYPE]])
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, jump type wasn't printable")
	}
	else if (playerGravity != 1.0)
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, player gravity wasn't 1.0: %f", playerGravity)
	}
	else if (!isValidFallAccel)
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, player had invalid fall acceleration: %f (%f - %f), expected %f",\
			fallAcceleration, fd[FD_VELOCITY][2], lastFd[FD_VELOCITY][2], sv_gravity * frametime)
	}
	else if (fd[FD_MOVETYPE] != MOVETYPE_WALK
		&& fd[FD_MOVETYPE] != MOVETYPE_FLY)
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, player had invalid movetype %i", fd[FD_MOVETYPE])
	}
	else if (pd[JUMP_AIRTIME] < 10 && pd[FRAMES_ON_GROUND])
	{
		pd[TRACKING_JUMP] = false;
		DEBUG_CHAT(client, "jump invalidated, jump airtime too small.")
	}
	
	if (!pd[TRACKING_JUMP])
	{
		PDResetJumpData(g_pd[client]);
		return;
	}
	
	// make sure the jump z velocity is broadly correct.
	//  difference isn't abs'd intentionally.
	if (fd[FD_VELOCITY][2] - pd[JUMP_VELOCITY][2] > sv_gravity * frametime + 2.0)
	{
		// add back roughly the gravity of the last frame. (accurate if frametime doesn't fluctuate)
		pd[JUMP_VELOCITY][2] = _:(fd[FD_VELOCITY][2] + sv_gravity * frametime);
	}
	
	
	new Float:speed = VectorLengthXY(fd[FD_VELOCITY]);
	if (speed > pd[JUMP_MAXSPEED])
	{
		pd[JUMP_MAXSPEED] = _:speed;
	}
	
	new Float:weaponspeed = get_user_maxspeed(client);
	new weapon = get_user_weapon(client);
	if (weaponspeed > pd[JUMP_WEAPONSPEED]
		|| (weapon != pd[JUMP_WEAPON] && pd[JUMP_WEAPONSPEED] <= weaponspeed))
	{
		pd[JUMP_WEAPONSPEED] = _:weaponspeed;
		pd[JUMP_WEAPON] = weapon;
	}
	
	new Float:lastSpeed = VectorLengthXY(lastFd[FD_VELOCITY]);
	if (speed > lastSpeed)
	{
		pd[JUMP_SYNC]++;
	}
	else if (speed < lastSpeed)
	{
		pd[JUMP_LOSS] += lastSpeed - speed;
	}
	
	new Float:height = fd[FD_ORIGIN][2] - pd[JUMP_POS][2];
	if (height > pd[JUMP_HEIGHT])
	{
		pd[JUMP_HEIGHT] = _:height;
	}
	
	if (IsOverlapping(fd[FD_BUTTONS], pd[JUMP_DIR]))
	{
		pd[JUMP_OVERLAP]++;
	}
	
	if (IsDeadAirtime(fd[FD_BUTTONS], pd[JUMP_DIR]))
	{
		pd[JUMP_DEADAIR]++;
	}
	
	// strafestats!
	if (pd[STRAFE_COUNT] + 1 < MAX_STRAFES)
	{
		if (IsNewStrafe(pd))
		{
			pd[STRAFE_COUNT]++;
			pd[STRAFE_FRAME][pd[STRAFE_COUNT]] = frameIndex;
		}
		
		new strafe = pd[STRAFE_COUNT];
		
		if (pd[JUMP_AIRTIME] == 1)
		{
			pd[STRAFE_FRAME][strafe] = 0;
		}
		
		pd[STRAFE_AIRTIME][strafe]++;
		
		if (speed > lastSpeed)
		{
			pd[STRAFE_SYNC][strafe] += 1.0;
			pd[STRAFE_GAIN][strafe] += speed - lastSpeed;
		}
		else if (speed < lastSpeed)
		{
			pd[STRAFE_LOSS][strafe] += lastSpeed - speed;
		}
		
		if (speed > pd[STRAFE_MAX][strafe])
		{
			pd[STRAFE_MAX][strafe] = _:speed;
		}
		
		if (IsOverlapping(fd[FD_BUTTONS], pd[JUMP_DIR]))
		{
			pd[STRAFE_OVERLAP][strafe]++;
		}
		
		if (IsDeadAirtime(fd[FD_BUTTONS], pd[JUMP_DIR]))
		{
			pd[STRAFE_DEADAIR][strafe]++;
		}
		
		// efficiency & potency!
		{
			new Float:maxWishspeed = 30.0;
			new Float:airaccelerate = get_pcvar_float(g_cvarAiraccelerate);
			new Float:maxspeed = get_user_maxspeed(client);
			if (fd[FD_FLAGS] & FL_DUCKING)
			{
				maxspeed *= 0.333;
			}
			
			new Float:yawdiff = floatabs(pd[ANGLE_SPEED][1]);
			new Float:perfectYawDiff = yawdiff;
			new Float:perfectYaw = 0.0;
			{
				new Float:accelspeed = airaccelerate * maxspeed * frametime;
				if (accelspeed > maxWishspeed)
				{
					accelspeed = maxWishspeed;
				}
				new Float:addspeed = maxWishspeed - accelspeed;
				if (lastSpeed >= maxWishspeed)
				{
					perfectYawDiff = xs_rad2deg(floatasin(accelspeed / lastSpeed, radian));
					perfectYaw = floatacos(addspeed / lastSpeed, radian);
				}
				else
				{
					perfectYawDiff = 0.0;
				}
			}
			new Float:efficiency = 100.0;
			if (perfectYawDiff != 0.0)
			{
				efficiency = (yawdiff - perfectYawDiff) / perfectYawDiff * 100.0 + 100.0;
			}
			new Float:potency = 0.0;
			new Float:optimalGain = CalculateGain(perfectYaw, maxspeed, airaccelerate, lastSpeed);
			new Float:actualGain = floatmax(0.0, speed - lastSpeed);
			// DEBUG_CONSOLE(client, "[%i] optimal gain: %f + %f, actual gain: %f (%f) (ang: %f %f)\n", pd[JUMP_AIRTIME], lastSpeed, optimalGain, actualGain, speed - lastSpeed, perfectYaw, floatabs(yawdiff))
			if (optimalGain > 0.0)
			{
				potency = (actualGain / optimalGain) * 100.0;
			}
			
			pd[STRAFE_AVG_EFFICIENCY][strafe] += efficiency;
			if (efficiency > pd[STRAFE_PEAK_EFFICIENCY][strafe])
			{
				pd[STRAFE_PEAK_EFFICIENCY][strafe] = _:efficiency;
			}
			pd[JUMP_POTENCY] += potency;
			
			// DEBUG_CONSOLE(client, "%i %f %f %f %f %f\n", strafe, (yawdiff - perfectYawDiff), fd[FD_WISHMOVE][1], yawdiff, perfectYawDiff, speed)
		}
	}
	
	if (frameIndex < MAX_JUMP_FRAMES)
	{
		// strafe type and mouse graph
		new StrafeType:strafeType = STRAFETYPE_NONE;
		
		new bool:moveLeft = !!(fd[FD_BUTTONS] & g_jumpDirLeftButton[pd[JUMP_DIR]]);
		new bool:moveRight = !!(fd[FD_BUTTONS] & g_jumpDirRightButton[pd[JUMP_DIR]]);
		
		new bool:velLeft = IsWishspeedMovingLeft(fd[FD_WISHMOVE][0], fd[FD_WISHMOVE][1], pd[JUMP_DIR]);
		new bool:velRight = IsWishspeedMovingRight(fd[FD_WISHMOVE][0], fd[FD_WISHMOVE][1], pd[JUMP_DIR]);
		new bool:velIsZero = !velLeft && !velRight;
		
		if (moveLeft && !moveRight && velLeft)
		{
			strafeType = STRAFETYPE_LEFT;
		}
		else if (moveRight && !moveLeft && velRight)
		{
			strafeType = STRAFETYPE_RIGHT;
		}
		else if (moveRight && !moveLeft && velRight)
		{
			strafeType = STRAFETYPE_LEFT;
		}
		else if (moveRight && moveLeft && velIsZero)
		{
			strafeType = STRAFETYPE_OVERLAP;
		}
		else if (moveRight && moveLeft && velLeft)
		{
			strafeType = STRAFETYPE_OVERLAP_LEFT;
		}
		else if (moveRight && moveLeft && velRight)
		{
			strafeType = STRAFETYPE_OVERLAP_RIGHT;
		}
		else if (!moveRight && !moveLeft && velIsZero)
		{
			strafeType = STRAFETYPE_NONE;
		}
		else if (!moveRight && !moveLeft && velLeft)
		{
			strafeType = STRAFETYPE_NONE_LEFT;
		}
		else if (!moveRight && !moveLeft && velRight)
		{
			strafeType = STRAFETYPE_NONE_RIGHT;
		}
		
		pd[STRAFE_GRAPH][frameIndex] = _:strafeType;
		new Float: yawDiff = fd[FD_ANGLES][1] - lastFd[FD_ANGLES][1];
		if (yawDiff > 180.0)
		{
			yawDiff -= 360.0;
		}
		if (yawDiff < -180.0)
		{
			yawDiff += 360.0;
		}
		pd[MOUSE_GRAPH][max(frameIndex - 1, 0)] = _:yawDiff;
		pd[DUCK_GRAPH][frameIndex] = !!(fd[FD_FLAGS] & FL_DUCKING);
	}
	// check for failstat after jump tracking is done
	new Float:duckedPos[3];
	PDCopyVector(fd[FD_ORIGIN], duckedPos);
	if (!(fd[FD_FLAGS] & FL_DUCKING))
	{
		duckedPos[2] += GC_DUCK_HEIGHT_CHANGE;
	}
	
	// failstat if there's absolutely no way we can land on level ground.
	new Float:offsetToleranceDown = 0.0001;
	if (pd[JUMP_TYPE] == JUMPTYPE_LDJ)
	{
		offsetToleranceDown = GC_OFFSET_TOLERANCE_LDJ;
	}
	else if (pd[JUMP_TYPE] == JUMPTYPE_BH
		|| pd[JUMP_TYPE] == JUMPTYPE_DBH
		|| pd[JUMP_TYPE] == JUMPTYPE_SBJ)
	{
		// don't let players bhop to lower ground!
		offsetToleranceDown = GC_OFFSET_TOLERANCE_BJ;
	}
	if (pd[JUMP_GROUND][2] > duckedPos[2] + offsetToleranceDown)
	{
		DEBUG_CHAT(client, "jump invalid cos z is too low: jumpGroundZ: %f duckedPosZ: %f",\
			pd[JUMP_GROUND][2], duckedPos[2])
		OnPlayerFailstat(client, pd);
	}
	
	// airpath.
	// NOTE: Track airpath after failstatPD has been saved, so
	// we don't track the last frame of failstats. That should
	// happen inside of FinishTrackingJump, because we need the real landing position.
	if (!pd[FRAMES_ON_GROUND])
	{
		// NOTE: there's a special case for landing frame.
		new Float:delta[3];
		xs_vec_sub(fd[FD_ORIGIN], lastFd[FD_ORIGIN], delta);
		pd[JUMP_AIRPATH] += VectorLengthXY(delta);
	}
}

OnPlayerFailstat(client, pd[PlayerData])
{
	// get frame just before "landing"
	// TODO: airtime on noduck failstats is still too high (same as ducked), fix!!!
	new fd[FrameData];
	new frameBeforeLand = 0;
	for (;
		 frameBeforeLand < g_replayTally[client][RT_FRAMECOUNT];
		 frameBeforeLand++)
	{
		GetReplayFrame(client, fd, frameBeforeLand);
		if (fd[FD_ORIGIN][2] > pd[JUMP_GROUND][2])
		{
			break;
		}
	}
	new lastFd[FrameData];
	GetReplayFrame(client, lastFd, frameBeforeLand + 1);
	
	pd[FAILED_JUMP] = true;
	
	new Float:gravity = get_cvar_float("sv_gravity") * get_user_gravity(client);
	new Float:frametime = float(pd[FRAMETIME_MSEC]) / 1000.0;
	new Float:fixedVelocity[3];
	PDCopyVector(fd[FD_VELOCITY], fixedVelocity);
	if (pd[FRAMES_ON_GROUND])
	{
		// fix zero velocity when on ground
		fixedVelocity[2] = lastFd[FD_VELOCITY][2] - gravity * frametime;
	}
	fixedVelocity[2] += gravity * 0.5 * frametime;
	
	// fix incorrect distance when ducking / unducking at the right time
	new Float:lastPosition[3];
	PDCopyVector(lastFd[FD_ORIGIN], lastPosition);
	new bool:lastDucking = !!(lastFd[FD_FLAGS] & FL_DUCKING);
	new bool:ducking = !!(fd[FD_FLAGS] & FL_DUCKING);
	if (!lastDucking && ducking)
	{
		lastPosition[2] += GC_DUCK_HEIGHT_CHANGE;
	}
	else if (lastDucking && !ducking)
	{
		lastPosition[2] -= GC_DUCK_HEIGHT_CHANGE;
	}
	
	DEBUG_CHAT(1, "jump z %f lastz %f currentz %f", pd[JUMP_GROUND][2], lastPosition[2], fd[FD_ORIGIN][2])
	GetRealLandingOrigin(pd[JUMP_GROUND][2], lastPosition, fixedVelocity, pd[LAND_POS]);
	pd[JUMP_DISTANCE] = _:(VectorDistanceXY(pd[JUMP_POS], pd[LAND_POS]));
	pd[JUMP_XJ_DISTANCE] = _:floatmax(floatabs(pd[JUMP_POS][0] - pd[LAND_POS][0]), floatabs(pd[JUMP_POS][1] - pd[LAND_POS][1]));
	if (pd[JUMP_TYPE] != JUMPTYPE_LDJ)
	{
		pd[JUMP_DISTANCE] += 32.0;
		pd[JUMP_XJ_DISTANCE] += 32.0;
	}
	
	FinishTrackingJump(pd, lastFd);
	if (GetOptionInt(client, OPT_ENABLE_SOUNDS) && GetOptionInt(client, OPT_ENABLE_FAILSTAT_SOUNDS))
	{
		PlayJumpSound(client, pd[JUMP_TYPE], pd[JUMP_DISTANCE]);
	}
	PrintStats(client, pd, g_hudBeamData[client]);
	PDResetJumpData(pd);
}

OnPlayerJumped(pd[PlayerData], JumpType:jumpType, fd[FrameData], lastFd[FrameData])
{
	pd[LAST_JUMP_TYPE] = _:pd[JUMP_TYPE];
	PDResetJumpData(pd);
	pd[JUMP_TYPE] = _:jumpType;
	
	pd[TRACKING_JUMP] = g_jumpTypePrintable[jumpType];
	
	pd[PRESPEED_FOG] = pd[FRAMES_ON_GROUND];
	pd[PRESPEED_STAMINA] = _:fd[FD_STAMINA];
	pd[SPEED_SHOW_PRESPEED] = true;
	
	DEBUG_CHAT(1, "jump type: %s last jump type: %s", g_szJumpTypes[jumpType], g_szJumpTypes[pd[LAST_JUMP_TYPE]])
	
	// jump direction
	if (VectorLengthXY(fd[FD_VELOCITY]) > 0.0)
	{
		new Float:velDir = xs_atan2(fd[FD_VELOCITY][1], fd[FD_VELOCITY][0], degrees);
		new Float:dir = NormaliseYaw(fd[FD_ANGLES][1] - velDir);
		
		pd[JUMP_DIR] = _:JUMPDIR_FORWARDS;
		if (IsFloatInRange(dir, 45.0, 135.0))
		{
			pd[JUMP_DIR] = _:JUMPDIR_RIGHT;
		}
		if (IsFloatInRange(dir, -135.0, -45.0))
		{
			pd[JUMP_DIR] = _:JUMPDIR_LEFT;
		}
		else if (dir > 135.0 || dir < -135.0)
		{
			pd[JUMP_DIR] = _:JUMPDIR_BACKWARDS;
		}
	}
	
	pd[JUMP_START_MSEC] = pd[TIME_MSEC];
	if (jumpType != JUMPTYPE_LDJ)
	{
		pd[JUMP_FRAME] = pd[USERCMD_COUNT];
		PDCopyVector(fd[FD_ORIGIN], pd[JUMP_POS]);
		PDCopyVector(fd[FD_ANGLES], pd[JUMP_ANGLES]);
		PDCopyVector(fd[FD_VELOCITY], pd[JUMP_VELOCITY]);
		
		pd[JUMP_PRESPEED] = _:VectorLengthXY(fd[FD_VELOCITY]);
	}
	else
	{
		// TODO: does this leave out the first frame of TrackJump?
		// NOTE: FOG doesn't make sense on ladderjumps
		pd[PRESPEED_FOG] = -1;
		pd[JUMP_FRAME] = pd[USERCMD_COUNT] - 1;
		PDCopyVector(lastFd[FD_ORIGIN], pd[JUMP_POS]);
		PDCopyVector(lastFd[FD_ANGLES], pd[JUMP_ANGLES]);
		PDCopyVector(lastFd[FD_VELOCITY], pd[JUMP_VELOCITY]);
		pd[JUMP_START_MSEC] -= pd[FRAMETIME_MSEC] * 2;
		
		pd[JUMP_PRESPEED] = _:VectorLengthXY(lastFd[FD_VELOCITY]);
	}
	
	PDCopyVector(pd[JUMP_POS], pd[JUMP_GROUND]);
	
	if (jumpType == JUMPTYPE_LDJ)
	{
		// fix jump ground
		if (pd[JUMP_GROUND][2] > pd[LADDER_MAXS][2])
		{
			pd[JUMP_GROUND][2] = pd[LADDER_MAXS][2];
		}
	}
	
	{ 
		new Float:basePos[3];
		PDCopyVector(pd[JUMP_GROUND], basePos);
		// move origin to the bottom of HULL_HEAD and 2 units down, so we can touch the side of the lj blocks
		basePos[2] += GC_DUCK_HEIGHT_CHANGE - 2.0;
		
		for (new i = 0; i < 8; i += 2)
		{
			// +x, +y, -x, +y
			new blockAxis = (i / 2) % 2;
			new blockDir = 1 - (i / 4) * 2;
			new Float:startPos[3];
			new Float:endPos[3];
			endPos = basePos;
			startPos = basePos;
			startPos[blockAxis] += float(blockDir) * MAX_EDGE;
			
			new Float:jumpEdge[3];
			
			new x = i;
			new y = i + 1;
			new bool:gotEdge = false;
			if (pd[JUMP_TYPE] == JUMPTYPE_LDJ)
			{
				endPos[blockAxis] -= float(blockDir) * 1.0;
				gotEdge = TraceBlock(endPos, startPos, jumpEdge);
			}
			else
			{
				gotEdge = TraceBlock(startPos, endPos, jumpEdge);
			}
			
			if (gotEdge)
			{
				pd[JUMP_EDGES][x] = jumpEdge[0];
				pd[JUMP_EDGES][y] = jumpEdge[1];
			}
			else
			{
				// huh?
				pd[JUMP_EDGES][x] = GC_FLOAT_INFINITY;
				pd[JUMP_EDGES][y] = GC_FLOAT_INFINITY;
			}
		}
	}
}

PlayJumpSound(client, JumpType:jumpType, Float:distance)
{
	if (distance >= get_pcvar_float(g_cvarMinDist[jumpType][JUMPTIER_5]))
	{
		client_cmd(client, "speak %s", SOUND_PATH_TIER_5);
	}
	else if (distance >= get_pcvar_float(g_cvarMinDist[jumpType][JUMPTIER_4]))
	{
		client_cmd(client, "speak %s", SOUND_PATH_TIER_4);
	}
	else if (distance >= get_pcvar_float(g_cvarMinDist[jumpType][JUMPTIER_3]))
	{
		client_cmd(client, "speak %s", SOUND_PATH_TIER_3);
	}
	else if (distance >= get_pcvar_float(g_cvarMinDist[jumpType][JUMPTIER_2]))
	{
		client_cmd(client, "speak %s", SOUND_PATH_TIER_2);
	}
	else if (distance >= get_pcvar_float(g_cvarMinDist[jumpType][JUMPTIER_1]))
	{
		client_cmd(client, "speak %s", SOUND_PATH_TIER_1);
	}
}

OnPlayerLanded(client, pd[PlayerData], fd[FrameData], lastFd[FrameData])
{
	pd[SPEED_SHOW_PRESPEED] = false;
	pd[LANDED_DUCKED] = !!(fd[FD_FLAGS] & FL_DUCKING);
	
	if (!pd[TRACKING_JUMP]
		|| pd[JUMP_TYPE] == JUMPTYPE_NONE
		|| !g_jumpTypePrintable[pd[JUMP_TYPE]])
	{
		DEBUG_CHAT(client, "invalid jump: tracking jump: %i jumptype: %s printable: %i", pd[TRACKING_JUMP], g_szJumpTypes[pd[JUMP_TYPE]], g_jumpTypePrintable[pd[JUMP_TYPE]])
		PDResetJumpData(pd);
		return;
	}
	
	// NOTE: HACK!!
	// TODO: properly find the correct start height of ladderjumps with an engine trace!
	// TODO: should tolerance be exactly 0 when on ground, aka a plain old x == y check?
	new Float:offsetToleranceUp = 0.0001;
	new Float:offsetToleranceDown = 0.02;
	if (pd[JUMP_TYPE] == JUMPTYPE_LDJ)
	{
		offsetToleranceUp = GC_OFFSET_TOLERANCE_LDJ;
		offsetToleranceDown = GC_OFFSET_TOLERANCE_LDJ;
	}
	else if (pd[JUMP_TYPE] == JUMPTYPE_BH
		|| pd[JUMP_TYPE] == JUMPTYPE_DBH
		|| pd[JUMP_TYPE] == JUMPTYPE_SBJ)
	{
		// don't let players bhop to lower ground!
		offsetToleranceDown = GC_OFFSET_TOLERANCE_BJ;
	}
	
	// second check for failstats. other one is in TrackJump()
	if (!IsFloatInRange(pd[JUMP_GROUND][2],
		fd[FD_ORIGIN][2] - offsetToleranceDown,
		fd[FD_ORIGIN][2] + offsetToleranceUp))
	{
		DEBUG_CHAT(client, "jump invalid cos offset in z: jumpPosZ: %f posZ: %f tolerance: (%f:%f)",\
			pd[JUMP_GROUND][2], fd[FD_ORIGIN][2], fd[FD_ORIGIN][2] - offsetToleranceDown, fd[FD_ORIGIN][2] + offsetToleranceUp)
		return;
	}
	DEBUG_CHAT(client, "jump offset %f zspeed: %f", fd[FD_ORIGIN][2] - pd[JUMP_GROUND][2], pd[JUMP_VELOCITY][2])
	
	// get land position
	new Float:landOrigin[3];
	new Float:fixedVelocity[3];
	new Float:airOrigin[3];
	
	// fix incorrect landing distance
	new Float:lastPosition[3];
	PDCopyVector(lastFd[FD_ORIGIN], lastPosition);
	new bool:lastDucking = !!(lastFd[FD_FLAGS] & FL_DUCKING);
	new bool:ducking = !!(fd[FD_FLAGS] & FL_DUCKING);
	if (!lastDucking && ducking)
	{
		lastPosition[2] += GC_DUCK_HEIGHT_CHANGE;
	}
	else if (lastDucking && !ducking)
	{
		lastPosition[2] -= GC_DUCK_HEIGHT_CHANGE;
	}
	
	new Float:gravity = get_cvar_float("sv_gravity") * get_user_gravity(client);
	new Float:frametime = float(pd[FRAMETIME_MSEC]) / 1000.0;
	new isBugged = lastPosition[2] - fd[FD_ORIGIN][2] <= 2.0;
	if (isBugged)
	{
		PDCopyVector(fd[FD_VELOCITY], fixedVelocity);
		// NOTE: The 0.5 here removes half the gravity in a tick, because
		// in pmove code half the gravity is applied before movement calculation and the other half after it's finished.
		// We're trying to fix a bug that happens in the middle of movement code.
		fixedVelocity[2] = lastFd[FD_VELOCITY][2] - gravity * 0.5 * frametime;
		PDCopyVector(lastPosition, airOrigin);
	}
	else
	{
		// NOTE: calculate current frame's z velocity
		new Float:tempVel[3];
		PDCopyVector(fd[FD_VELOCITY], tempVel);
		tempVel[2] = lastFd[FD_VELOCITY][2] - gravity * 0.5 * frametime;
		// NOTE: calculate velocity after the current frame.
		fixedVelocity = tempVel;
		fixedVelocity[2] -= gravity * frametime;
		// NOTE: calculate position where the player was before they were snapped to the ground
		xs_vec_mul_scalar(tempVel, frametime, tempVel);
		xs_vec_add(lastPosition, tempVel, airOrigin);
	}
	
	// Check if jump height simulated from the jump pos
	//  matches up with actual jump offset.
	{
		new Float:jumpImpulse = pd[JUMP_VELOCITY][2];
		new Float:jumpDuration = float(pd[TIME_MSEC] - pd[JUMP_START_MSEC]) / 1000.0;
		// NOTE(GameChaos): Pretty hacky, haven't dove deep into the
		//  maths, this is just a rough estimate really.
		if (pd[JUMP_TYPE] == JUMPTYPE_LDJ)
		{
			// ladderjumps are weird
			jumpDuration -= frametime;
		}
		else if (!isBugged)
		{
			jumpDuration += frametime;
		}
		new Float:expectedOffset = jumpImpulse * jumpDuration + 0.5 * -gravity * (jumpDuration * jumpDuration);
		if (fd[FD_FLAGS] & FL_DUCKING)
		{
			expectedOffset += GC_DUCK_HEIGHT_CHANGE;
		}
		new Float:realOffset = airOrigin[2] - pd[JUMP_POS][2];
		new Float:tolerance = lastFd[FD_VELOCITY][2] * frametime - 1.0;
		if (expectedOffset - realOffset < tolerance)
		{
			DEBUG_CHAT(client, "HIT TOLERANCE %f", tolerance)
			DEBUG_CHAT(client, "INVALID JUMP %f %f Expected offset: %f, real offset: %f", pd[JUMP_VELOCITY][2], jumpDuration, expectedOffset, realOffset)
			PDResetJumpData(pd);
			return;
		}
	}
	
	new Float:landingZ = fd[FD_ORIGIN][2];
	GetRealLandingOrigin(landingZ, airOrigin, fixedVelocity, landOrigin);
	PDCopyVector(landOrigin, pd[LAND_POS]);
	
	pd[JUMP_DISTANCE] = _:(VectorDistanceXY(pd[JUMP_POS], pd[LAND_POS]));
	if (isBugged)
	{
		pd[JUMP_XJ_DISTANCE] = _:floatmax(floatabs(pd[JUMP_POS][0] - pd[LAND_POS][0]), floatabs(pd[JUMP_POS][1] - pd[LAND_POS][1]));
	}
	else
	{
		pd[JUMP_XJ_DISTANCE] = _:floatmax(floatabs(pd[JUMP_POS][0] - fd[FD_ORIGIN][0]), floatabs(pd[JUMP_POS][1] - fd[FD_ORIGIN][1]));
	}
	if (pd[JUMP_TYPE] != JUMPTYPE_LDJ)
	{
		pd[JUMP_DISTANCE] += 32.0;
		pd[JUMP_XJ_DISTANCE] += 32.0;
	}
	
	new Float:minDistance = get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_0]);
	new Float:maxDistance = get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_MAX_DIST]);
	if (IsFloatInRange(pd[JUMP_DISTANCE], minDistance, maxDistance))
	{
		FinishTrackingJump(pd, lastFd);
		if (GetOptionInt(client, OPT_ENABLE_SOUNDS))
		{
			PlayJumpSound(client, pd[JUMP_TYPE], pd[JUMP_DISTANCE]);
		}
		
		PrintStats(client, pd, g_hudBeamData[client]);
		
		if (get_pcvar_bool(g_cvarSaveReplays))
		{
			SaveReplay(client, pd);
		}
	}
	else
	{
		DEBUG_CHAT(client, "Jump distance not in range (%f-%f): %f", minDistance, maxDistance, pd[JUMP_DISTANCE])
	}
	PDResetJumpData(pd);
}

SaveReplay(client, pd[PlayerData])
{
	if (!dir_exists(GC_REPLAY_DIR))
	{
		mkdir(GC_REPLAY_DIR);
	}
	
	new steamid[64];
	get_user_authid(client, steamid, charsmax(steamid));
	xs_replace_char(steamid, charsmax(steamid), ':', '_');
	replace(steamid, charsmax(steamid), "STEAM_0", "STEAM_1");
	
	new outDir[128];
	format(outDir, charsmax(outDir), "%s/%s", GC_REPLAY_DIR, steamid);
	if (!dir_exists(outDir))
	{
		mkdir(outDir);
	}
	
	new time[64];
	get_time("%Y-%d-%m_%H.%M.%S", time, charsmax(time));
	new replayPath[128];
	format(replayPath, charsmax(replayPath), "%s/%s_%s_%s_%.3f_%.4f.%s",
		outDir,
		time,
		steamid,
		g_szJumpTypes[pd[JUMP_TYPE]],
		400.0 > pd[JUMP_BLOCK_DIST] > 0.0 ? pd[JUMP_BLOCK_DIST] : 0.0,
		pd[JUMP_DISTANCE],
		GC_REPLAY_EXT
	);
	
	new file = fopen(replayPath, "wb");
	if (file)
	{
		fwrite_blocks(file, GC_REPLAY_IDENT, strlen(GC_REPLAY_IDENT), BLOCK_CHAR);
		fwrite(file, GC_REPLAY_MAGIC, BLOCK_INT);
		fwrite(file, GC_REPLAY_VERSION, BLOCK_INT);
		
		fwrite_blocks(file, pd[LAST_GROUND_POS], sizeof(pd[LAST_GROUND_POS]), BLOCK_INT);
		fwrite(file, pd[LAST_GROUND_POS_WALKED_OFF], BLOCK_INT);
		fwrite(file, pd[LANDED_DUCKED], BLOCK_INT);
		fwrite(file, pd[PRESPEED_FOG], BLOCK_INT);
		fwrite(file, pd[PRESPEED_STAMINA], BLOCK_INT);
		fwrite_blocks(file, pd[JUMP_POS], sizeof(pd[JUMP_POS]), BLOCK_INT);
		fwrite_blocks(file, pd[JUMP_ANGLES], sizeof(pd[JUMP_ANGLES]), BLOCK_INT);
		fwrite_blocks(file, pd[JUMP_VELOCITY], sizeof(pd[JUMP_VELOCITY]), BLOCK_INT);
		fwrite_blocks(file, pd[LAND_POS], sizeof(pd[LAND_POS]), BLOCK_INT);
		fwrite_blocks(file, pd[LAND_POS], sizeof(pd[LAND_POS]), BLOCK_INT);
		fwrite(file, pd[FWD_RELEASE_FRAME], BLOCK_INT);
		fwrite(file, pd[JUMP_FRAME], BLOCK_INT);
		fwrite(file, pd[JUMP_TYPE], BLOCK_INT);
		fwrite(file, pd[LAST_JUMP_TYPE], BLOCK_INT);
		fwrite(file, pd[JUMP_DIR], BLOCK_INT);
		fwrite(file, pd[JUMP_DISTANCE], BLOCK_INT);
		fwrite(file, pd[JUMP_XJ_DISTANCE], BLOCK_INT);
		fwrite(file, pd[JUMP_PRESPEED], BLOCK_INT);
		fwrite(file, pd[JUMP_MAXSPEED], BLOCK_INT);
		fwrite(file, pd[JUMP_WEAPONSPEED], BLOCK_INT);
		fwrite(file, pd[JUMP_LOSS], BLOCK_INT);
		fwrite(file, pd[JUMP_VEER], BLOCK_INT);
		fwrite(file, pd[JUMP_AIRPATH], BLOCK_INT);
		fwrite(file, pd[JUMP_SYNC], BLOCK_INT);
		fwrite(file, pd[JUMP_POTENCY], BLOCK_INT);
		fwrite(file, pd[JUMP_EDGE], BLOCK_INT);
		fwrite(file, pd[JUMP_LAND_EDGE], BLOCK_INT);
		fwrite(file, pd[JUMP_BLOCK_DIST], BLOCK_INT);
		fwrite(file, pd[JUMP_HEIGHT], BLOCK_INT);
		fwrite(file, pd[JUMP_JUMPOFF_ANGLE], BLOCK_INT);
		fwrite(file, pd[JUMP_START_MSEC], BLOCK_INT);
		fwrite(file, pd[JUMP_AIRTIME], BLOCK_INT);
		fwrite(file, pd[JUMP_FWD_RELEASE], BLOCK_INT);
		fwrite(file, pd[JUMP_OVERLAP], BLOCK_INT);
		fwrite(file, pd[JUMP_DEADAIR], BLOCK_INT);
		fwrite(file, pd[JUMP_WEAPON], BLOCK_INT);
		fwrite(file, pd[STRAFE_COUNT], BLOCK_INT);
		
		// TODO: compression
		fwrite(file, g_replayTally[client][RT_FRAMECOUNT], BLOCK_INT);
		for (new i = g_replayTally[client][RT_FRAMECOUNT] - 1;
			i >= 0;
			i--)
		{
			new fd[FrameData];
			GetReplayFrame(client, fd, i);
			fwrite_blocks(file, fd[FrameData:0], sizeof(fd), BLOCK_INT);
		}
		fclose(file);
	}
}

FinishTrackingJump(pd[PlayerData], lastFd[FrameData])
{
	// finish up stats:
	new Float:xAxisVeer = floatabs(pd[LAND_POS][0] - pd[JUMP_POS][0]);
	new Float:yAxisVeer = floatabs(pd[LAND_POS][1] - pd[JUMP_POS][1]);
	pd[JUMP_VEER] = _:floatmin(xAxisVeer, yAxisVeer);
	
	pd[JUMP_FWD_RELEASE] = pd[FWD_RELEASE_FRAME] - pd[JUMP_FRAME];
	pd[JUMP_SYNC] = _:((Float:pd[JUMP_SYNC]) / float(_:pd[JUMP_AIRTIME]) * 100.0);
	pd[JUMP_POTENCY] = _:(pd[JUMP_POTENCY] / float(pd[JUMP_AIRTIME]));
	
	for (new strafe; strafe < pd[STRAFE_COUNT] + 1; strafe++)
	{
		// average gain
		pd[STRAFE_AVG_GAIN][strafe] = _:(pd[STRAFE_GAIN][strafe] / pd[STRAFE_AIRTIME][strafe]);
		
		// efficiency!
		pd[STRAFE_AVG_EFFICIENCY][strafe] /= float(pd[STRAFE_AIRTIME][strafe]);
		
		// sync
		
		if (pd[STRAFE_AIRTIME][strafe] != 0.0)
		{
			pd[STRAFE_SYNC][strafe] = _:(pd[STRAFE_SYNC][strafe] / float(pd[STRAFE_AIRTIME][strafe]) * 100.0);
		}
		else
		{
			pd[STRAFE_SYNC][strafe] = _:0.0;
		}
	}
	
	// airpath!
	{
		new Float:delta[3];
		xs_vec_sub(pd[LAND_POS], lastFd[FD_ORIGIN], delta);
		pd[JUMP_AIRPATH] += VectorLengthXY(delta);
		if (pd[JUMP_TYPE] != JUMPTYPE_LDJ)
		{
			pd[JUMP_AIRPATH] = _:(pd[JUMP_AIRPATH] / (pd[JUMP_DISTANCE] - 32.0));
		}
		else
		{
			pd[JUMP_AIRPATH] = _:(pd[JUMP_AIRPATH] / (pd[JUMP_DISTANCE]));
		}
	}
	
	// Calculate block distance and jumpoff edge
	{
		new blockAxis = floatabs(pd[LAND_POS][1] - pd[JUMP_POS][1]) > floatabs(pd[LAND_POS][0] - pd[JUMP_POS][0]);
		new blockDir = xs_fsign(pd[JUMP_POS][blockAxis] - pd[LAND_POS][blockAxis]);
		
		new Float:endPos[3];
		PDCopyVector(pd[LAND_POS], endPos);
		endPos[2] += GC_DUCK_HEIGHT_CHANGE - 2.0;
		
		new Float:startPos[3];
		startPos = endPos;
		startPos[blockAxis] -= (pd[LAND_POS][blockAxis] - pd[JUMP_POS][blockAxis]) / 2.0;
		
		// extend land origin, so if we fail within MAX_EDGE units of the block we can still get the block distance.
		endPos[blockAxis] -= float(blockDir) * MAX_EDGE;
		
		pd[JUMP_LAND_EDGE] = MAX_EDGE;
		pd[JUMP_EDGE] = -1.0;
		pd[JUMP_BLOCK_DIST] = -1.0;
		new Float:landEdge[3];
		if (TraceBlock(startPos, endPos, landEdge))
		{
			// 0.03125 is to make blocks accurate. the measured distance with
			//  engine trace is usually integer block distance - 0.0625 (0.03125*2), for example 255-0.0625, but
			//  the player isn't able to land a <255 lj on most 255 lj blocks (kz_longjumps2 blocks included).
			//  to clarify: the real physical distance of most blocks is their integer distance as measured
			//  in hammer. some blocks can be landed on from closer (0.03125 units) like 230 block on kz_longjumps2.
			pd[JUMP_LAND_EDGE] = _:((landEdge[blockAxis] - pd[LAND_POS][blockAxis]) * float(blockDir));
			pd[JUMP_LAND_EDGE] -= 0.03125;
		}
		
		new edgeInd = ((blockDir + 1) + blockAxis) * 2 + blockAxis;
		new Float:jumpEdge = pd[JUMP_EDGES][edgeInd];
		
		if (jumpEdge != GC_FLOAT_INFINITY)
		{
			pd[JUMP_EDGE] = (pd[JUMP_POS][blockAxis] - jumpEdge) * float(blockDir);
			
			if (pd[JUMP_LAND_EDGE] != MAX_EDGE)
			{
				pd[JUMP_BLOCK_DIST] = _:(floatabs(landEdge[blockAxis] - jumpEdge));
				if (pd[JUMP_TYPE] != JUMPTYPE_LDJ)
				{
					pd[JUMP_BLOCK_DIST] += 32.0625;
				}
				// round block distance to 1/2048, as that is nearly the precision limit of goldsrc's map size,
				//  add 1/2048, to avoid block distances such as 251.899 being shown to the player.
				pd[JUMP_BLOCK_DIST] = floatround(pd[JUMP_BLOCK_DIST] * 2048.0) / 2048.0 + (1.0 / 2048.0);
			}
			
			if (pd[JUMP_TYPE] != JUMPTYPE_LDJ)
			{
				pd[JUMP_EDGE] -= 0.03125;
			}
			else
			{
				// ladder edge faces the other way!
				pd[JUMP_EDGE] += 0.03125;
			}
		}
	}
	
	// jumpoff angle!
	{
		new Float:airpathDir[3];
		xs_vec_sub(pd[LAND_POS], pd[JUMP_POS], airpathDir);
		xs_vec_normalize(airpathDir, airpathDir);
		
		new Float:airpathAngles[3];
		EF_VecToAngles(airpathDir, airpathAngles);
		new Float:airpathYaw = NormaliseYaw(airpathAngles[1]);
		
		// Fix bugs with -180 to 180 transitions
		if (floatabs(airpathYaw - pd[JUMP_ANGLES]) > 180.0)
		{
			airpathYaw += 360.0;
		}
		
		pd[JUMP_JUMPOFF_ANGLE] = _:NormaliseYaw(airpathYaw - pd[JUMP_ANGLES][1]);
	}
}

PrintStats(client, pd[PlayerData], hudBeamData[HudAndBeamData])
{
	hudBeamData[HBD_FRAMES] = min(pd[JUMP_AIRTIME], MAX_JUMP_FRAMES - 1);
	for (new i = 0; i < hudBeamData[HBD_FRAMES]; i++)
	{
		new lastFd[FrameData];
		new fd[FrameData];
		GetReplayFrame(client, lastFd, hudBeamData[HBD_FRAMES] - i);
		GetReplayFrame(client, fd, hudBeamData[HBD_FRAMES] - 1 - i);
		hudBeamData[HBD_JUMP_BEAM_X][i] = _:fd[FD_ORIGIN][0];
		hudBeamData[HBD_JUMP_BEAM_Y][i] = _:fd[FD_ORIGIN][1];
		hudBeamData[HBD_JUMP_BEAM_COLOUR][i] = _:JUMPBEAM_NEUTRAL;
		
		new Float:lastSpeed = VectorLengthXY(lastFd[FD_VELOCITY]);
		new Float:speed = VectorLengthXY(fd[FD_VELOCITY]);
		if (speed > lastSpeed)
		{
			hudBeamData[HBD_JUMP_BEAM_COLOUR][i] = _:JUMPBEAM_GAIN;
		}
		else if (speed < lastSpeed)
		{
			hudBeamData[HBD_JUMP_BEAM_COLOUR][i] = _:JUMPBEAM_LOSS;
		}
		
		if (fd[FD_FLAGS] & FL_DUCKING)
		{
			hudBeamData[HBD_JUMP_BEAM_COLOUR][i] = _:JUMPBEAM_DUCK;
		}
	}
	
	// make sure the last frame in the jump beam has the correct position!
	if (pd[JUMP_AIRTIME] < MAX_JUMP_FRAMES)
	{
		hudBeamData[HBD_JUMP_BEAM_X][hudBeamData[HBD_FRAMES]] = _:pd[LAND_POS][0];
		hudBeamData[HBD_JUMP_BEAM_Y][hudBeamData[HBD_FRAMES]] = _:pd[LAND_POS][1];
	}
	
	for (new i = 0; i < 3; i++)
	{
		hudBeamData[VEERBEAM_START][i] = _:pd[JUMP_POS][i];
		hudBeamData[VEERBEAM_END][i] = _:pd[LAND_POS][i];
	}
	
	new fwdRelease[32] = "";
	if (pd[JUMP_FWD_RELEASE] == 0)
	{
		formatex(fwdRelease, charsmax(fwdRelease), "Fwd: !g0");
	}
	else if (abs(pd[JUMP_FWD_RELEASE]) > 16)
	{
		formatex(fwdRelease, charsmax(fwdRelease), "Fwd: !nNo");
	}
	else if (pd[JUMP_FWD_RELEASE] > 0)
	{
		formatex(fwdRelease, charsmax(fwdRelease), "Fwd: !w+%i", pd[JUMP_FWD_RELEASE]);
	}
	else
	{
		formatex(fwdRelease, charsmax(fwdRelease), "Fwd: !w%i", pd[JUMP_FWD_RELEASE]);
	}
	
	new edge[32] = "";
	new chatEdge[32] = "";
	new bool:hasEdge = false;
	if (pd[JUMP_EDGE] >= 0.0 && pd[JUMP_EDGE] < MAX_EDGE)
	{
		formatex(edge, charsmax(edge), "Edge: %.4f", pd[JUMP_EDGE]);
		formatex(chatEdge, charsmax(chatEdge), "Edge: !n%.2f", pd[JUMP_EDGE]);
		hasEdge = true;
	}
	
	new block[32] = "";
	new bool:hasBlock = false;
	if (IsFloatInRange(pd[JUMP_BLOCK_DIST],
		get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_0]), get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_MAX_DIST])))
	{
		formatex(block, charsmax(block), "Block: %.3f", pd[JUMP_BLOCK_DIST]);
		hasBlock = true;
	}
	
	new landEdge[32] = "";
	new bool:hasLandEdge = false;
	if (floatabs(pd[JUMP_LAND_EDGE]) < MAX_EDGE)
	{
		formatex(landEdge, charsmax(landEdge), "Land Edge: %.4f", pd[JUMP_LAND_EDGE]);
		hasLandEdge = true;
	}
	
	new fog[32];
	new bool:hasFOG = false;
	if (pd[PRESPEED_FOG] <= MAX_BHOP_FRAMES
		&& pd[PRESPEED_FOG] >= 0)
	{
		formatex(fog, charsmax(fog), "FOG: %i", pd[PRESPEED_FOG]);
		hasFOG = true;
	}
	
	new stamina[32];
	new bool:hasStamina = false;
	if (pd[PRESPEED_STAMINA] != 0.0)
	{
		formatex(stamina, charsmax(stamina), "Stamina: %.1f", pd[PRESPEED_STAMINA]);
		hasStamina = true;
	}
	
	new weapon[32];
	new bool:printWeapon = false;
	if ((0 <= pd[JUMP_WEAPON] < sizeof(g_weaponNames)) && pd[JUMP_WEAPONSPEED] != 250.0)
	{
		formatex(weapon, charsmax(weapon), "!w(%s) ", g_weaponNames[pd[JUMP_WEAPON]]);
		printWeapon = true;
	}
	
	new chatStats[1024 char];
	format(chatStats, charsmax(chatStats), "%s !w%s%s: !n%.4f %s!w[%s%sVeer: !n%.2f!w | %s!w | Sync: !n%.1f!w | Max: !n%.1f!w]",
		CHAT_PREFIX,
		pd[FAILED_JUMP] ? "FAILED " : "",
		g_szJumpTypes[pd[JUMP_TYPE]],
		pd[JUMP_DISTANCE],
		weapon,
		chatEdge,
		hasEdge ? " !w| " : "",
		pd[JUMP_VEER],
		fwdRelease,
		pd[JUMP_SYNC],
		pd[JUMP_MAXSPEED]
	);
	
	ClientAndSpecsPrintChat(client, chatStats);

	// Print high tier jumps to chat only Tier4 and Tier5
	new player[32];
	get_user_name(client, player, sizeof(player));

	new chatStatsAll[1024];
	format(chatStatsAll, charsmax(chatStatsAll), "%s !g%s!w jumped !w%s%s: !n%.4f %s!w[%s%sVeer: !n%.2f!w | %s!w | Sync: !n%.1f!w | Max: !n%.1f!w] !n%s!w",
		CHAT_PREFIX,
		player,
		pd[FAILED_JUMP] ? "FAILED " : "",
		g_szJumpTypes[pd[JUMP_TYPE]],
		pd[JUMP_DISTANCE],
		weapon,
		chatEdge,
		hasEdge ? " !w| " : "",
		pd[JUMP_VEER],
		fwdRelease,
		pd[JUMP_SYNC],
		pd[JUMP_MAXSPEED],
		pd[FAILED_JUMP] ? "" : block // Not very sure if this works tbh
	);
	
#if 0
	// NOTE(sitka): Noticed this will spam alot when propane is playing, very annoying player
	if (pd[JUMP_DISTANCE] >= get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_4]))
	{
		for (new i = 1; i <= get_maxplayers(); i++)
		{
			if (!is_user_connected(i) || i == client)
			{
				continue;
			}
			
			CC_SendMessage(i, chatStatsAll);
			// client_cmd(i, "speak %s", SOUND_PATH_TIER_4);
		}
	}
	else
#endif
	if (pd[JUMP_DISTANCE] >= get_pcvar_float(g_cvarMinDist[pd[JUMP_TYPE]][JUMPTIER_5]))
	{
		for (new i = 1; i <= get_maxplayers(); i++)
		{
			if (!is_user_connected(i) || i == client)
			{
				continue;
			}
			
			CC_SendMessage(i, chatStatsAll);
			client_cmd(i, "speak %s", SOUND_PATH_TIER_5);
		}
	}
	
	new consoleStats[1024 char];
	formatex(consoleStats, charsmax(consoleStats), "\n[GC] %s%s: %.5f (XJ: %.5f) [%s%s%s%sVeer: %.4f | %s | Sync: %.2f | Max: %.3f]\n",
		pd[FAILED_JUMP] ? "FAILED " : "",
		g_szJumpTypes[pd[JUMP_TYPE]],
		pd[JUMP_DISTANCE],
		pd[JUMP_XJ_DISTANCE],
		block,
		hasBlock ? " | " : "",
		edge,
		hasEdge ? " | " : "",
		pd[JUMP_VEER],
		fwdRelease,
		pd[JUMP_SYNC],
		pd[JUMP_MAXSPEED]
	);
	
	format(consoleStats, charsmax(consoleStats), "%s[%s%sPre: %.4f | OL/DA: %i/%i | Jumpoff Angle: %.3f | Airpath: %.4f | Strafes: %i | Airtime: %i]\n",
		consoleStats,
		landEdge,
		hasLandEdge ? " | " : "",
		pd[JUMP_PRESPEED],
		pd[JUMP_OVERLAP],
		pd[JUMP_DEADAIR],
		pd[JUMP_JUMPOFF_ANGLE],
		pd[JUMP_AIRPATH],
		pd[STRAFE_COUNT] + 1,
		pd[JUMP_AIRTIME]
	);

	CC_RemoveColors(consoleStats, charsmax(consoleStats));
	ClientAndSpecsPrintConsole(client, consoleStats);
	
	formatex(consoleStats, charsmax(consoleStats), "[%s%s%sJump Direction: %s | %s%sHeight: %.4f%s%s | Loss: %.2f | Potency: %.2f]\n",
		printWeapon ? "Weapon: " : "",
		weapon,
		printWeapon ? " | " : "",
		g_jumpDirString[pd[JUMP_DIR]],
		fog,
		hasFOG ? " | " : "",
		pd[JUMP_HEIGHT],
		hasStamina ? " | " : "",
		stamina,
		pd[JUMP_LOSS],
		pd[JUMP_POTENCY]
	);
	
	CC_RemoveColors(consoleStats, charsmax(consoleStats));
	ClientAndSpecsPrintConsole(client, consoleStats);
	
	new len = 0;
#if defined USE_SQL
	new authid[64];
	get_user_authid(client, authid, charsmax(authid));
	
	new unescapedName[32];
	get_user_name(client, unescapedName, charsmax(unescapedName));
	new name[64];
	SQL_QuoteString(Empty_Handle, name, charsmax(name), unescapedName);
	
	new ip[16];
	get_user_ip(client, ip, charsmax(ip) - 1, 1);
	
	new country[3];
	if (contain(ip, "192.168.") != -1)
	{
		format(country, charsmax(country), "??");
	}
	else
	{
		geoip_code2_ex(ip, country);
	}
	
	new statQuery[1024];
	len = formatex(statQuery[len], charsmax(statQuery) - len, "INSERT INTO jumpdata (steamid, name, country, failed, type, dist, xjdist, block, hasblock, edge, hasedge, landEdge, veer, fwdrelease, sync, maxspeed, prespeed, overlap, deadair, jofangle, airpath, strafes, airtime, direction, fog, hasfog, height, hasstamina, stamina, loss, potency) VALUES ");
	len += formatex(statQuery[len], charsmax(statQuery) - len, "('%s', '%s', '%s', %i, %i, %f, %f, %f, %i, %f, %i, %f, %f, %i, %f, %f, %f, %i, %i, %f, %f, %i, %i, '%s', %i, %i, %f, %i, %f, %f, %f) RETURNING id",
		authid,
		name,
		country,
		pd[FAILED_JUMP] ? 1 : 0,
		pd[JUMP_TYPE],
		pd[JUMP_DISTANCE],
		pd[JUMP_XJ_DISTANCE],
		pd[JUMP_BLOCK_DIST],
		hasBlock ? 1 : 0,
		pd[JUMP_EDGE],
		hasEdge ? 1 : 0,
		pd[JUMP_LAND_EDGE],
		pd[JUMP_VEER],
		pd[JUMP_FWD_RELEASE],
		pd[JUMP_SYNC],
		pd[JUMP_MAXSPEED],
		pd[JUMP_PRESPEED],
		pd[JUMP_OVERLAP],
		pd[JUMP_DEADAIR],
		pd[JUMP_JUMPOFF_ANGLE],
		pd[JUMP_AIRPATH],
		pd[STRAFE_COUNT] + 1,
		pd[JUMP_AIRTIME],
		g_jumpDirString[pd[JUMP_DIR]],
		pd[PRESPEED_FOG],
		hasFOG ? 1 : 0,
		pd[JUMP_HEIGHT],
		hasStamina ? 1 : 0,
		pd[PRESPEED_STAMINA],
		pd[JUMP_LOSS],
		pd[JUMP_POTENCY]);
	
	SQL_ThreadQuery(g_sqlTuple, "PostJumpAndStrafeData", statQuery, pd[PlayerData:0], sizeof(pd));
	
#endif
	
	ClientAndSpecsPrintConsole(client, "\n #.  Sync   Gain   Loss  Max   Air  OL/DA AvgGain Distance  AvgEff%% (MaxEff%%)\n");
	for (new strafe; strafe <= pd[STRAFE_COUNT] && strafe < MAX_STRAFES; strafe++)
	{
		new strafeFd[FrameData];
		new nextStrafeFd[FrameData];
		// NOTE: intentionally get 1 frame before this strafe's start!
		GetReplayFrame(client, strafeFd, pd[JUMP_AIRTIME] - pd[STRAFE_FRAME][strafe]);
		if (strafe < pd[STRAFE_COUNT] && strafe + 1 < MAX_STRAFES)
		{
			// NOTE: intentionally get 1 frame before this strafe's start!
			GetReplayFrame(client, nextStrafeFd, pd[JUMP_AIRTIME] - pd[STRAFE_FRAME][strafe + 1]);
		}
		else
		{
			GetReplayFrame(client, nextStrafeFd, 0);
		}
		
		new Float:strafeOffset[3];
		xs_vec_sub(strafeFd[FD_ORIGIN], nextStrafeFd[FD_ORIGIN], strafeOffset);
		strafeOffset[2] = 0.0;
		new Float:jumpNormal[3];
		xs_vec_sub(pd[JUMP_POS], pd[LAND_POS], jumpNormal);
		jumpNormal[2] = 0.0;
		xs_vec_normalize(jumpNormal, jumpNormal);
		
		new Float:strafeDistance = xs_vec_dot(jumpNormal, strafeOffset) / float(pd[STRAFE_AIRTIME][strafe]);
		
		ClientAndSpecsPrintConsole(client, "%2i. %5.1f%% %6.2f %6.2f  %5.1f %3i %2i/%-2i    %3.2f      %-5.2f   %3i%% (%i%%)\n",
			strafe + 1,
			pd[STRAFE_SYNC][strafe],
			pd[STRAFE_GAIN][strafe],
			pd[STRAFE_LOSS][strafe],
			pd[STRAFE_MAX][strafe],
			pd[STRAFE_AIRTIME][strafe],
			pd[STRAFE_OVERLAP][strafe],
			pd[STRAFE_DEADAIR][strafe],
			pd[STRAFE_AVG_GAIN][strafe],
			strafeDistance,
			floatround(pd[STRAFE_AVG_EFFICIENCY][strafe]),
			floatround(pd[STRAFE_PEAK_EFFICIENCY][strafe])
		);
	}
	
	// hud text
	new moveLeftGraph[HUD_GRAPH_MAX_CHARS] = "";
	new moveRightGraph[HUD_GRAPH_MAX_CHARS] = "";
	new mouseGraphLeft[HUD_GRAPH_MAX_CHARS] = "";
	new mouseGraphRight[HUD_GRAPH_MAX_CHARS] = "";
	new duckGraph[HUD_GRAPH_MAX_CHARS] = "";
	
	for (new i = 0; i < pd[JUMP_AIRTIME] && i < MAX_JUMP_FRAMES; i++)
	{
		new StrafeType:strafeTypeLeft = pd[STRAFE_GRAPH][i];
		new StrafeType:strafeTypeRight = pd[STRAFE_GRAPH][i];
		
		if (strafeTypeLeft == STRAFETYPE_RIGHT
			|| strafeTypeLeft == STRAFETYPE_NONE_RIGHT
			|| strafeTypeLeft == STRAFETYPE_OVERLAP_RIGHT)
		{
			strafeTypeLeft = STRAFETYPE_NONE;
		}
		
		if (strafeTypeRight == STRAFETYPE_LEFT
			|| strafeTypeRight == STRAFETYPE_NONE_LEFT
			|| strafeTypeRight == STRAFETYPE_OVERLAP_LEFT)
		{
			strafeTypeRight = STRAFETYPE_NONE;
		}
		
		format(moveLeftGraph, charsmax(moveLeftGraph), "%s%c", moveLeftGraph, g_szStrafeTypeChar[strafeTypeLeft]);
		format(moveRightGraph, charsmax(moveRightGraph), "%s%c", moveRightGraph, g_szStrafeTypeChar[strafeTypeRight]);
		
		if (pd[MOUSE_GRAPH][i] == 0.0)
		{
			format(mouseGraphLeft, charsmax(mouseGraphLeft), "%s%c", mouseGraphLeft, g_szStrafeTypeChar[STRAFETYPE_NONE]);
			format(mouseGraphRight, charsmax(mouseGraphRight), "%s%c", mouseGraphRight, g_szStrafeTypeChar[STRAFETYPE_NONE]);
		}
		else if (pd[MOUSE_GRAPH][i] < 0.0)
		{
			format(mouseGraphLeft, charsmax(mouseGraphLeft), "%s%c", mouseGraphLeft, g_szStrafeTypeChar[STRAFETYPE_NONE]);
			format(mouseGraphRight, charsmax(mouseGraphRight), "%s%s", mouseGraphRight, "$");
		}
		else if (pd[MOUSE_GRAPH][i] > 0.0)
		{
			format(mouseGraphLeft, charsmax(mouseGraphLeft), "%s%c", mouseGraphLeft, '$');
			format(mouseGraphRight, charsmax(mouseGraphRight), "%s%c", mouseGraphRight, g_szStrafeTypeChar[STRAFETYPE_NONE]);
		}
		
		format(duckGraph, charsmax(duckGraph), "%s%c", duckGraph, pd[DUCK_GRAPH][i] ? 'C' : g_szStrafeTypeChar[STRAFETYPE_NONE]);
	}
	
	formatex(hudBeamData[HUD_TOP_STRING], charsmax(hudBeamData[HUD_TOP_STRING]), "%s%s: %.5f (XJ: %.5f)\n[%s%sPre: %.2f | OL/DA: %i/%i | Jumpoff Angle: %.2f]\n[Airpath: %.4f | Strafes: %i | Loss: %.2f | Potency: %.2f]",
		pd[FAILED_JUMP] ? "FAILED " : "",
		g_szJumpTypes[pd[JUMP_TYPE]],
		pd[JUMP_DISTANCE],
		pd[JUMP_XJ_DISTANCE],
		block,
		hasBlock ? " | " : "",
		pd[JUMP_PRESPEED],
		pd[JUMP_OVERLAP],
		pd[JUMP_DEADAIR],
		pd[JUMP_JUMPOFF_ANGLE],
		pd[JUMP_AIRPATH],
		pd[STRAFE_COUNT] + 1,
		pd[JUMP_LOSS],
		pd[JUMP_POTENCY]
	);
	
	if (GetOptionInt(client, OPT_HUD_STATS_VERTICAL))
	{
		// probably very slow, but lmao who cares, right...?
		replace_string(hudBeamData[HUD_TOP_STRING], charsmax(hudBeamData[HUD_TOP_STRING]), " | ", "\n");
		replace_string(hudBeamData[HUD_TOP_STRING], charsmax(hudBeamData[HUD_TOP_STRING]), "[", "");
		replace_string(hudBeamData[HUD_TOP_STRING], charsmax(hudBeamData[HUD_TOP_STRING]), "]", "");
	}
	
	// hud messages have a max character limit of ~68, until the line wraps.
	//  cut off the start of the hud message for a max of 68 characters per line
	//  NOTE: first 3 chars are used up by "..."
	new startChar = pd[JUMP_AIRTIME] - 65;
	startChar = clamp(startChar, 0, HUD_GRAPH_MAX_CHARS - 1);
	new ellipsis[16] = "";
	if (startChar != 0)
	{
		ellipsis = "...";
	}
	formatex(hudBeamData[HUD_MLEFT_STRING], charsmax(hudBeamData[HUD_MLEFT_STRING]),
		"%s%s\n%s%s", ellipsis, moveLeftGraph[startChar], ellipsis, mouseGraphLeft[startChar]
	);
	formatex(hudBeamData[HUD_MRIGHT_STRING], charsmax(hudBeamData[HUD_MRIGHT_STRING]),
		"%s%s\n%s%s\n%s%s", ellipsis, moveRightGraph[startChar], ellipsis, mouseGraphRight[startChar], ellipsis, duckGraph[startChar]
	);
	
	len = 0;
	len = formatex(hudBeamData[HUD_STRAFESTAT_STRING], charsmax(hudBeamData[HUD_STRAFESTAT_STRING]) - len,
		"%s", "X. Sync Gain Loss Max Air OL/DA AvgEff (MaxEff)\n"
	);
	for (new strafe; strafe <= pd[STRAFE_COUNT] && strafe < MAX_STRAFES; strafe++)
	{
		len += formatex(hudBeamData[HUD_STRAFESTAT_STRING][len], charsmax(hudBeamData[HUD_STRAFESTAT_STRING]) - len,
			"%i. %4.0f%% %4.0f %5.1f %4.0f %3i %i/%i %3i%% (%i%%)\n",
			strafe + 1,
			pd[STRAFE_SYNC][strafe],
			pd[STRAFE_GAIN][strafe],
			pd[STRAFE_LOSS][strafe],
			pd[STRAFE_MAX][strafe],
			pd[STRAFE_AIRTIME][strafe],
			pd[STRAFE_OVERLAP][strafe],
			pd[STRAFE_DEADAIR][strafe],
			floatround(pd[STRAFE_AVG_EFFICIENCY][strafe]),
			floatround(pd[STRAFE_PEAK_EFFICIENCY][strafe])
		);
		if (len >= charsmax(hudBeamData[HUD_STRAFESTAT_STRING]) - 1)
		{
			break;
		}
	}
	
	hudBeamData[HBD_TIMESTAMP_MSEC] = g_pd[client][TIME_MSEC];
	
	xs_replace_char(moveLeftGraph, charsmax(moveLeftGraph), g_szStrafeTypeChar[STRAFETYPE_LEFT], '$');
	xs_replace_char(moveRightGraph, charsmax(moveRightGraph), g_szStrafeTypeChar[STRAFETYPE_RIGHT], '$');
	xs_replace_char(duckGraph, charsmax(duckGraph), 'C', '$');
	
	ClientAndSpecsPrintConsole(client, "\nStrafe keys:\nL: %s\nR: %s\n", moveLeftGraph, moveRightGraph);
	ClientAndSpecsPrintConsole(client, "Mouse movement:\nL: %s\nR: %s\n", mouseGraphLeft, mouseGraphRight);
	ClientAndSpecsPrintConsole(client, "Duck:\nD: %s\n\n", duckGraph);
}
