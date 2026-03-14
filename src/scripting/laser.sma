#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>

#define VERSION "1.0"
#define MAX_PLAYERS 32
#define TASKID_LASERPAINT 1337
#define TASK_INTERVAL_LASERPAINT 0.1

new g_spriteLaser;

new bool:g_bShotBeam[MAX_PLAYERS + 1], bool:g_bLaserPaint[MAX_PLAYERS + 1];
new g_vecLastLaser[MAX_PLAYERS + 1][3];

new const g_LazerColors[7][3] = {
    {255, 255, 255},
    {255,   0,   0},
    {  0, 255,   0},
    {  0,   0, 255},
    {255, 255,   0},
    {  0, 255, 255},
    {255,   0, 255}
};

new const GUN_NAMES[][] = {
    "weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10", "weapon_aug",
    "weapon_elite", "weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil",
    "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp", "weapon_mp5navy",
    "weapon_m249", "weapon_m3", "weapon_m4a1", "weapon_tmp", "weapon_g3sg1",
    "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90"
};

public plugin_init()
{
    register_plugin("Colorful Shotbeam & Lazer Paint", VERSION, "Gemini");

    register_clcmd("say /shotbeam", "cmd_ToggleShotBeam");
    register_clcmd("+laser", "cmd_LaserOn");
    register_clcmd("-laser", "cmd_LaserOff");

    for (new i = 0; i < sizeof(GUN_NAMES); i++) {
        RegisterHam(Ham_Weapon_PrimaryAttack, GUN_NAMES[i], "fw_Weapon_PrimaryAttack_Post", 1);
    }

    set_task(TASK_INTERVAL_LASERPAINT, "Task_LaserPaint", TASKID_LASERPAINT, "", 0, "b");
}

public plugin_precache()
{
    g_spriteLaser = precache_model("sprites/zbeam4.spr");
}

public client_putinserver(id)
{
    g_bShotBeam[id] = true;
    g_bLaserPaint[id] = false;
}

public client_disconnected(id)
{
    g_bShotBeam[id] = false;
    g_bLaserPaint[id] = false;
}

public cmd_ToggleShotBeam(id)
{
    g_bShotBeam[id] = !g_bShotBeam[id];
    client_print(id, print_chat, "[AMXX] Colorful Shot Beam is now %s.", g_bShotBeam[id] ? "ON" : "OFF");
    return PLUGIN_HANDLED;
}

public fw_Weapon_PrimaryAttack_Post(ent)
{
    new id = get_pdata_cbase(ent, 41, 4);
    if (id < 1 || id > MAX_PLAYERS || !is_user_alive(id) || !g_bShotBeam[id]) {
        return;
    }

    new vStart[3], vEnd[3];
    get_user_origin(id, vStart, 1);
    get_user_origin(id, vEnd, 3);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(vStart[0]);
    write_coord(vStart[1]);
    write_coord(vStart[2]);
    write_coord(vEnd[0]);
    write_coord(vEnd[1]);
    write_coord(vEnd[2]);
    write_short(g_spriteLaser);
    write_byte(0);
    write_byte(0);
    write_byte(8);
    write_byte(15);
    write_byte(0);
    write_byte(random_num(50, 255));
    write_byte(random_num(50, 255));
    write_byte(random_num(50, 255));
    write_byte(200);
    write_byte(0);
    message_end();
}

public Task_LaserPaint()
{
    new players[MAX_PLAYERS], pnum, id;
    get_players(players, pnum, "a");

    for (new i = 0; i < pnum; i++) {
        id = players[i];
        if (g_bLaserPaint[id]) {
            Handle_LaserPaint(id);
        }
    }
}

public cmd_LaserOn(id)
{
    if (!is_user_alive(id)) {
        return PLUGIN_HANDLED;
    }

    g_bLaserPaint[id] = true;
    get_user_origin(id, g_vecLastLaser[id], 3);
    return PLUGIN_HANDLED;
}

public cmd_LaserOff(id)
{
    g_bLaserPaint[id] = false;
    return PLUGIN_HANDLED;
}

public Handle_LaserPaint(id)
{
    new currentOrigin[3];
    get_user_origin(id, currentOrigin, 3);

    if (get_distance(g_vecLastLaser[id], currentOrigin) <= 3) {
        return;
    }

    new colorIdx = random_num(0, sizeof(g_LazerColors) - 1);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(g_vecLastLaser[id][0]);
    write_coord(g_vecLastLaser[id][1]);
    write_coord(g_vecLastLaser[id][2]);
    write_coord(currentOrigin[0]);
    write_coord(currentOrigin[1]);
    write_coord(currentOrigin[2]);
    write_short(g_spriteLaser);
    write_byte(0);
    write_byte(0);
    write_byte(250);
    write_byte(10);
    write_byte(0);
    write_byte(g_LazerColors[colorIdx][0]);
    write_byte(g_LazerColors[colorIdx][1]);
    write_byte(g_LazerColors[colorIdx][2]);
    write_byte(255);
    write_byte(0);
    message_end();

    g_vecLastLaser[id] = currentOrigin;
}
