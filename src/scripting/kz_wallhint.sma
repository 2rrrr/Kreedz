#include <amxmodx>
#include <fakemeta>

#define PLUGIN  "KZ Wall Touch Hint"
#define VERSION "1.1"
#define AUTHOR  "Codex"

#define MAX_PLAYERS 32

#define DIR_LEFT  0
#define DIR_RIGHT 1
#define DIR_HEAD  2
#define DIR_COUNT 3

#define DMGTYPE_HINT (1<<0) // DMG_CRUSH

#define SIDE_NONE  0
#define SIDE_LEFT  1
#define SIDE_RIGHT 2

new g_msgDamage;

new Float:g_lastCheckTime[MAX_PLAYERS + 1];
new Float:g_lastHintTime[MAX_PLAYERS + 1][DIR_COUNT];
new g_lastSideChoice[MAX_PLAYERS + 1];

new g_cvarCheckInterval;
new g_cvarHintInterval;
new g_cvarTraceDist;
new g_cvarTouchFrac;
new g_cvarUpNormalDot;
new g_cvarSourceDist;
new g_cvarHeadTraceDist;
new g_cvarHeadTouchFrac;
new g_cvarHeadProbeOffset;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Use post-think so collision state is final for this frame.
    register_forward(FM_PlayerPostThink, "fw_PlayerPostThink");
    g_msgDamage = get_user_msgid("Damage");

    g_cvarCheckInterval = register_cvar("kz_wh_check_interval", "0.03");
    g_cvarHintInterval = register_cvar("kz_wh_hint_interval", "0.08");
    g_cvarTraceDist = register_cvar("kz_wh_trace_dist", "2.0");
    g_cvarTouchFrac = register_cvar("kz_wh_touch_frac", "0.20");
    g_cvarUpNormalDot = register_cvar("kz_wh_up_normal_dot", "0.75");
    g_cvarSourceDist = register_cvar("kz_wh_source_dist", "100.0");
    g_cvarHeadTraceDist = register_cvar("kz_wh_head_trace_dist", "3.0");
    g_cvarHeadTouchFrac = register_cvar("kz_wh_head_touch_frac", "0.40");
    g_cvarHeadProbeOffset = register_cvar("kz_wh_head_probe_offset", "8.0");
}

public client_putinserver(id)
{
    reset_player_state(id);
}

public client_disconnected(id)
{
    reset_player_state(id);
}

public fw_PlayerPostThink(id)
{
    if (!is_user_alive(id)) {
        return FMRES_IGNORED;
    }

    // Only show wall hint while player is in air.
    if (pev(id, pev_flags) & FL_ONGROUND) {
        clear_hint_times(id);
        return FMRES_IGNORED;
    }

    // Disable hint while surfing on slope planes.
    if (is_user_surfing(id)) {
        clear_hint_times(id);
        return FMRES_IGNORED;
    }

    new Float:now = get_gametime();
    new Float:checkInterval = get_pcvar_float(g_cvarCheckInterval);
    if (checkInterval < 0.005) {
        checkInterval = 0.03;
    }

    if (now - g_lastCheckTime[id] < checkInterval) {
        return FMRES_IGNORED;
    }
    g_lastCheckTime[id] = now;

    new Float:hintInterval = get_pcvar_float(g_cvarHintInterval);
    if (hintInterval < checkInterval) {
        hintInterval = checkInterval;
    }

    new Float:traceDist = get_pcvar_float(g_cvarTraceDist);
    if (traceDist < 0.2) {
        traceDist = 0.2;
    }

    new Float:touchFrac = get_pcvar_float(g_cvarTouchFrac);
    if (touchFrac < 0.001) {
        touchFrac = 0.001;
    } else if (touchFrac > 1.0) {
        touchFrac = 1.0;
    }

    new Float:upNormalDot = get_pcvar_float(g_cvarUpNormalDot);
    if (upNormalDot < 0.1) {
        upNormalDot = 0.1;
    } else if (upNormalDot > 0.99) {
        upNormalDot = 0.99;
    }

    new Float:sourceDist = get_pcvar_float(g_cvarSourceDist);
    if (sourceDist < 16.0) {
        sourceDist = 16.0;
    }

    new Float:headTraceDist = get_pcvar_float(g_cvarHeadTraceDist);
    if (headTraceDist < 0.5) {
        headTraceDist = 0.5;
    } else if (headTraceDist > 16.0) {
        headTraceDist = 16.0;
    }

    new Float:headTouchFrac = get_pcvar_float(g_cvarHeadTouchFrac);
    if (headTouchFrac < 0.01) {
        headTouchFrac = 0.01;
    } else if (headTouchFrac > 1.0) {
        headTouchFrac = 1.0;
    }

    new Float:headProbeOffset = get_pcvar_float(g_cvarHeadProbeOffset);
    if (headProbeOffset < 2.0) {
        headProbeOffset = 2.0;
    } else if (headProbeOffset > 24.0) {
        headProbeOffset = 24.0;
    }

    new Float:origin[3];
    new Float:viewAngles[3];
    new Float:fwd[3];
    new Float:right[3];
    pev(id, pev_origin, origin);
    pev(id, pev_v_angle, viewAngles);
    viewAngles[0] = 0.0;
    viewAngles[2] = 0.0;

    engfunc(EngFunc_MakeVectors, viewAngles);
    global_get(glb_v_forward, fwd);
    global_get(glb_v_right, right);

    new hull = (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
    new tr = create_tr2();

    new bool:leftTouch;
    new bool:rightTouch;
    detect_front_side_touches(id, tr, hull, origin, fwd, right, traceDist, touchFrac, leftTouch, rightTouch);
    new bool:headTouch = is_head_touch(
        id, tr, origin, fwd, right, headTraceDist, headTouchFrac, headProbeOffset, upNormalDot
    );

    if (leftTouch) {
        send_hint_if_needed(id, DIR_LEFT, now, hintInterval, sourceDist, origin, right, fwd);
    } else {
        g_lastHintTime[id][DIR_LEFT] = 0.0;
    }

    if (rightTouch) {
        send_hint_if_needed(id, DIR_RIGHT, now, hintInterval, sourceDist, origin, right, fwd);
    } else {
        g_lastHintTime[id][DIR_RIGHT] = 0.0;
    }

    if (headTouch) {
        send_hint_if_needed(id, DIR_HEAD, now, hintInterval, sourceDist, origin, right, fwd);
    } else {
        g_lastHintTime[id][DIR_HEAD] = 0.0;
    }

    free_tr2(tr);
    return FMRES_IGNORED;
}

stock reset_player_state(id)
{
    g_lastCheckTime[id] = 0.0;
    g_lastSideChoice[id] = SIDE_NONE;
    clear_hint_times(id);
}

stock clear_hint_times(id)
{
    for (new i = 0; i < DIR_COUNT; i++) {
        g_lastHintTime[id][i] = 0.0;
    }
}

stock send_hint_if_needed(
    id,
    dir,
    Float:now,
    Float:hintInterval,
    Float:sourceDist,
    const Float:origin[3],
    const Float:right[3],
    const Float:fwd[3]
)
{
    if (now - g_lastHintTime[id][dir] < hintInterval) {
        return;
    }
    g_lastHintTime[id][dir] = now;

    new Float:src[3];
    switch (dir) {
        case DIR_LEFT: {
            src[0] = origin[0] - right[0] * sourceDist;
            src[1] = origin[1] - right[1] * sourceDist;
            src[2] = origin[2] - right[2] * sourceDist;
        }
        case DIR_RIGHT: {
            src[0] = origin[0] + right[0] * sourceDist;
            src[1] = origin[1] + right[1] * sourceDist;
            src[2] = origin[2] + right[2] * sourceDist;
        }
        case DIR_HEAD: {
            // Head touch should show as "front" indicator.
            src[0] = origin[0] + fwd[0] * sourceDist;
            src[1] = origin[1] + fwd[1] * sourceDist;
            src[2] = origin[2] + fwd[2] * sourceDist;
        }
    }

    send_damage_hud(id, src);
}

stock detect_front_side_touches(
    id,
    tr,
    hull,
    const Float:origin[3],
    const Float:fwd[3],
    const Float:right[3],
    Float:traceDist,
    Float:touchFrac,
    &bool:leftTouch,
    &bool:rightTouch
)
{
    leftTouch = false;
    rightTouch = false;

    new Float:leftBestFrac = 2.0;
    new Float:rightBestFrac = 2.0;

    // Front half
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, -0.85, 1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, -0.40, 1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.00, 1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.40, 1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.85, 1.0, leftBestFrac, rightBestFrac);
    // Rear half
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, -0.85, -1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, -0.40, -1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.00, -1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.40, -1.0, leftBestFrac, rightBestFrac);
    collect_side_probe(id, tr, hull, origin, fwd, right, traceDist, touchFrac, 0.85, -1.0, leftBestFrac, rightBestFrac);

    new bool:hasLeft = (leftBestFrac < 2.0);
    new bool:hasRight = (rightBestFrac < 2.0);
    if (!hasLeft && !hasRight) {
        return;
    }

    if (hasLeft && !hasRight) {
        leftTouch = true;
        g_lastSideChoice[id] = SIDE_LEFT;
        return;
    }

    if (!hasLeft && hasRight) {
        rightTouch = true;
        g_lastSideChoice[id] = SIDE_RIGHT;
        return;
    }

    // Both sides found: keep only one side by stronger/closer contact.
    const Float:EPS = 0.0005;
    if (leftBestFrac + EPS < rightBestFrac) {
        leftTouch = true;
        g_lastSideChoice[id] = SIDE_LEFT;
        return;
    }
    if (rightBestFrac + EPS < leftBestFrac) {
        rightTouch = true;
        g_lastSideChoice[id] = SIDE_RIGHT;
        return;
    }

    // Perfect tie: use horizontal movement first, then last side memory.
    new Float:vel[3];
    pev(id, pev_velocity, vel);
    new Float:sideVel = vec_dot(vel, right);
    if (sideVel > 0.10) {
        rightTouch = true;
        g_lastSideChoice[id] = SIDE_RIGHT;
        return;
    }
    if (sideVel < -0.10) {
        leftTouch = true;
        g_lastSideChoice[id] = SIDE_LEFT;
        return;
    }

    if (g_lastSideChoice[id] == SIDE_RIGHT) {
        rightTouch = true;
    } else {
        leftTouch = true;
        g_lastSideChoice[id] = SIDE_LEFT;
    }
}

stock collect_side_probe(
    id,
    tr,
    hull,
    const Float:origin[3],
    const Float:fwd[3],
    const Float:right[3],
    Float:traceDist,
    Float:touchFrac,
    Float:lateralWeight,
    Float:forwardSign,
    &Float:leftBestFrac,
    &Float:rightBestFrac
)
{
    new Float:hitFrac;
    new side = probe_front_side(
        id, tr, hull, origin, fwd, right, traceDist, touchFrac, lateralWeight, forwardSign, hitFrac
    );

    if (side == SIDE_LEFT && hitFrac < leftBestFrac) {
        leftBestFrac = hitFrac;
    } else if (side == SIDE_RIGHT && hitFrac < rightBestFrac) {
        rightBestFrac = hitFrac;
    }
}

stock probe_front_side(
    id,
    tr,
    hull,
    const Float:origin[3],
    const Float:fwd[3],
    const Float:right[3],
    Float:traceDist,
    Float:touchFrac,
    Float:lateralWeight,
    Float:forwardSign,
    &Float:hitFrac
)
{
    hitFrac = 1.0;

    new Float:dir[3];
    dir[0] = fwd[0] * forwardSign + right[0] * lateralWeight;
    dir[1] = fwd[1] * forwardSign + right[1] * lateralWeight;
    dir[2] = 0.0;
    if (!vec_normalize_2d(dir)) {
        return SIDE_NONE;
    }

    new Float:end[3];
    end[0] = origin[0] + dir[0] * traceDist;
    end[1] = origin[1] + dir[1] * traceDist;
    end[2] = origin[2];
    engfunc(EngFunc_TraceHull, origin, end, IGNORE_MONSTERS, hull, id, tr);

    if (!is_true_contact(tr, touchFrac)) {
        return SIDE_NONE;
    }

    if (get_tr2(tr, TR_AllSolid) || get_tr2(tr, TR_StartSolid)) {
        hitFrac = 0.0;
    } else {
        get_tr2(tr, TR_flFraction, hitFrac);
    }

    new Float:normal[3];
    get_tr2(tr, TR_vecPlaneNormal, normal);
    if (floatabs(normal[2]) > 0.70) {
        return SIDE_NONE;
    }

    new Float:hitPos[3];
    get_tr2(tr, TR_vecEndPos, hitPos);

    new Float:toHit[3];
    toHit[0] = hitPos[0] - origin[0];
    toHit[1] = hitPos[1] - origin[1];
    toHit[2] = 0.0;

    const Float:SIDE_SPLIT = 0.03;
    new Float:sidePos = vec_dot(toHit, right);
    if (sidePos > SIDE_SPLIT) {
        return SIDE_RIGHT;
    }
    if (sidePos < -SIDE_SPLIT) {
        return SIDE_LEFT;
    }

    new Float:normalSide = vec_dot(normal, right);
    if (normalSide > 0.02) {
        return SIDE_LEFT;
    }
    if (normalSide < -0.02) {
        return SIDE_RIGHT;
    }

    // Strict side fallback for perfect center hit.
    if (lateralWeight > 0.01) {
        return SIDE_RIGHT;
    }
    if (lateralWeight < -0.01) {
        return SIDE_LEFT;
    }

    new Float:vel[3];
    pev(id, pev_velocity, vel);
    new Float:sideVel = vec_dot(vel, right);
    if (sideVel > 0.10) {
        return SIDE_RIGHT;
    }
    if (sideVel < -0.10) {
        return SIDE_LEFT;
    }

    return (g_lastSideChoice[id] == SIDE_RIGHT) ? SIDE_RIGHT : SIDE_LEFT;
}

stock bool:is_head_touch(
    id,
    tr,
    const Float:origin[3],
    const Float:fwd[3],
    const Float:right[3],
    Float:traceDist,
    Float:touchFrac,
    Float:probeOffset,
    Float:upNormalDot
)
{
    new Float:absmax[3];
    pev(id, pev_absmax, absmax);

    new Float:topZ = absmax[2] - 0.1;
    new Float:start[3];
    start[2] = topZ;

    start[0] = origin[0];
    start[1] = origin[1];
    if (probe_head_point(id, tr, start, traceDist, touchFrac, upNormalDot)) return true;

    start[0] = origin[0] + right[0] * probeOffset;
    start[1] = origin[1] + right[1] * probeOffset;
    if (probe_head_point(id, tr, start, traceDist, touchFrac, upNormalDot)) return true;

    start[0] = origin[0] - right[0] * probeOffset;
    start[1] = origin[1] - right[1] * probeOffset;
    if (probe_head_point(id, tr, start, traceDist, touchFrac, upNormalDot)) return true;

    start[0] = origin[0] + fwd[0] * probeOffset;
    start[1] = origin[1] + fwd[1] * probeOffset;
    if (probe_head_point(id, tr, start, traceDist, touchFrac, upNormalDot)) return true;

    start[0] = origin[0] - fwd[0] * probeOffset;
    start[1] = origin[1] - fwd[1] * probeOffset;
    if (probe_head_point(id, tr, start, traceDist, touchFrac, upNormalDot)) return true;

    return false;
}

stock bool:probe_head_point(
    id,
    tr,
    const Float:start[3],
    Float:traceDist,
    Float:touchFrac,
    Float:upNormalDot
)
{
    new Float:end[3];
    end[0] = start[0];
    end[1] = start[1];
    end[2] = start[2] + traceDist;
    engfunc(EngFunc_TraceLine, start, end, IGNORE_MONSTERS, id, tr);

    if (get_tr2(tr, TR_AllSolid) || get_tr2(tr, TR_StartSolid)) {
        return true;
    }

    new Float:fraction;
    get_tr2(tr, TR_flFraction, fraction);
    if (fraction >= 1.0 || fraction > touchFrac) {
        return false;
    }

    new Float:normal[3];
    get_tr2(tr, TR_vecPlaneNormal, normal);
    return (normal[2] <= -upNormalDot);
}

stock bool:is_user_surfing(id)
{
    new Float:origin[3], Float:dest[3];
    pev(id, pev_origin, origin);

    dest[0] = origin[0];
    dest[1] = origin[1];
    dest[2] = origin[2] - 1.0;

    new tr = create_tr2();
    new hull = (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
    engfunc(EngFunc_TraceHull, origin, dest, IGNORE_MONSTERS, hull, id, tr);

    new Float:fraction;
    get_tr2(tr, TR_flFraction, fraction);
    if (fraction >= 1.0) {
        free_tr2(tr);
        return false;
    }

    new Float:planeNormal[3];
    get_tr2(tr, TR_vecPlaneNormal, planeNormal);

    free_tr2(tr);
    return (planeNormal[2] <= 0.7);
}

stock bool:is_true_contact(tr, Float:touchFrac)
{
    if (get_tr2(tr, TR_AllSolid) || get_tr2(tr, TR_StartSolid)) {
        return true;
    }

    new Float:fraction;
    get_tr2(tr, TR_flFraction, fraction);
    return (fraction < 1.0 && fraction <= touchFrac);
}

stock bool:vec_normalize_2d(Float:v[3])
{
    new Float:len = floatsqroot(v[0] * v[0] + v[1] * v[1]);
    if (len < 0.0001) {
        return false;
    }

    v[0] /= len;
    v[1] /= len;
    v[2] = 0.0;
    return true;
}

stock Float:vec_dot(const Float:a[3], const Float:b[3])
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

stock send_damage_hud(id, const Float:source[3])
{
    message_begin(MSG_ONE_UNRELIABLE, g_msgDamage, _, id);
    write_byte(0);             // armor damage
    write_byte(1);             // health damage (>0 required for indicator)
    write_long(DMGTYPE_HINT);
    engfunc(EngFunc_WriteCoord, source[0]);
    engfunc(EngFunc_WriteCoord, source[1]);
    engfunc(EngFunc_WriteCoord, source[2]);
    message_end();
}
