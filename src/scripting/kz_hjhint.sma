#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <xs>
#include <reapi>

#define VERSION "1.0"
#define MAX_PLAYERS 32

#define HJ_THRESHOLD_DEFAULT 70.0
#define PROXIMITY_LIMIT_DEFAULT 120.0

#define HJ_DRAW_INTERVAL_DEFAULT 0.01
#define HJ_RECALC_INTERVAL_DEFAULT 0.01
#define HJ_RECALC_MOVE_DEFAULT 4.0
#define HJ_RECALC_YAW_DEFAULT 2.0
#define HJ_STEP_LEN_DEFAULT 2.0

new g_spriteLaser;

new bool:g_bKzHint[MAX_PLAYERS + 1], bool:g_bKzDebug[MAX_PLAYERS + 1], bool:g_bHintVisible[MAX_PLAYERS + 1];
new Float:g_vecHintStart[MAX_PLAYERS + 1][3], Float:g_vecHintEnd[MAX_PLAYERS + 1][3];
new g_iHintR[MAX_PLAYERS + 1], g_iHintG[MAX_PLAYERS + 1];

new Float:g_vecLastCalcOrigin[MAX_PLAYERS + 1][3], Float:g_fLastCalcYaw[MAX_PLAYERS + 1];
new Float:g_fNextDraw[MAX_PLAYERS + 1], Float:g_fNextRecalc[MAX_PLAYERS + 1], Float:g_fNextDebugPrint[MAX_PLAYERS + 1];

new g_pCvarDrawInterval, g_pCvarRecalcInterval, g_pCvarRecalcMove, g_pCvarRecalcYaw;
new g_pCvarProximity, g_pCvarThreshold, g_pCvarStepLen;

public plugin_init()
{
    register_plugin("KZ Highjump Hint", VERSION, "Gemini");

    register_clcmd("say /kzhint", "cmd_ToggleKzHint");
    register_clcmd("say /kzdebug", "cmd_ToggleKzDebug");

    // ReAPI PostThink provides smoother scheduling than set_task when server FPS is high.
    RegisterHookChain(RG_CBasePlayer_PostThink, "Hook_PostThink");

    g_pCvarDrawInterval = register_cvar("kz_hjh_draw_interval", "0.01");
    g_pCvarRecalcInterval = register_cvar("kz_hjh_recalc_interval", "0.01");
    g_pCvarRecalcMove = register_cvar("kz_hjh_recalc_move", "4.0");
    g_pCvarRecalcYaw = register_cvar("kz_hjh_recalc_yaw", "2.0");
    g_pCvarProximity = register_cvar("kz_hjh_proximity", "120.0");
    g_pCvarThreshold = register_cvar("kz_hjh_threshold", "70.0");
    g_pCvarStepLen = register_cvar("kz_hjh_step_len", "2.0");
}

public plugin_precache()
{
    g_spriteLaser = precache_model("sprites/zbeam4.spr");
}

public client_putinserver(id)
{
    g_bKzHint[id] = true;
    g_bKzDebug[id] = false;
    g_bHintVisible[id] = false;

    g_fNextDraw[id] = 0.0;
    g_fNextRecalc[id] = 0.0;
    g_fNextDebugPrint[id] = 0.0;
}

public client_disconnected(id)
{
    g_bKzHint[id] = false;
    g_bKzDebug[id] = false;
    g_bHintVisible[id] = false;

    g_fNextDraw[id] = 0.0;
    g_fNextRecalc[id] = 0.0;
    g_fNextDebugPrint[id] = 0.0;
}

public cmd_ToggleKzHint(id)
{
    g_bKzHint[id] = !g_bKzHint[id];
    if (!g_bKzHint[id]) {
        g_bHintVisible[id] = false;
    }
    client_print(id, print_chat, "[AMXX] KZ Edge Hint is now %s.", g_bKzHint[id] ? "ON" : "OFF");
    return PLUGIN_HANDLED;
}

public cmd_ToggleKzDebug(id)
{
    g_bKzDebug[id] = !g_bKzDebug[id];
    g_fNextDebugPrint[id] = 0.0;
    client_print(id, print_chat, "[AMXX] KZ Debug is now %s.", g_bKzDebug[id] ? "ON" : "OFF");
    return PLUGIN_HANDLED;
}

public Hook_PostThink(id)
{
    if (!is_user_alive(id) || !g_bKzHint[id]) {
        return;
    }

    if (!(get_entvar(id, var_flags) & FL_ONGROUND)) {
        g_bHintVisible[id] = false;
        return;
    }

    new Float:drawInterval = get_pcvar_float(g_pCvarDrawInterval);
    new Float:recalcInterval = get_pcvar_float(g_pCvarRecalcInterval);
    new Float:recalcMove = get_pcvar_float(g_pCvarRecalcMove);
    new Float:recalcYaw = get_pcvar_float(g_pCvarRecalcYaw);
    if (drawInterval < 0.005) drawInterval = HJ_DRAW_INTERVAL_DEFAULT;
    if (recalcInterval < 0.005) recalcInterval = HJ_RECALC_INTERVAL_DEFAULT;
    if (recalcMove < 0.1) recalcMove = HJ_RECALC_MOVE_DEFAULT;
    if (recalcYaw < 0.1) recalcYaw = HJ_RECALC_YAW_DEFAULT;

    new Float:now = get_gametime();
    if (now < g_fNextDraw[id]) {
        return;
    }
    g_fNextDraw[id] = now + drawInterval;

    new Float:vOrigin[3], Float:vAngles[3];
    get_entvar(id, var_origin, vOrigin);
    get_entvar(id, var_v_angle, vAngles);
    new Float:fYaw = vAngles[1];

    new bool:bNeedRecalc = (now >= g_fNextRecalc[id]);
    if (!bNeedRecalc && get_distance_f(vOrigin, g_vecLastCalcOrigin[id]) >= recalcMove) {
        bNeedRecalc = true;
    }
    if (!bNeedRecalc && FloatAngleDelta(fYaw, g_fLastCalcYaw[id]) >= recalcYaw) {
        bNeedRecalc = true;
    }

    if (bNeedRecalc) {
        xs_vec_copy(vOrigin, g_vecLastCalcOrigin[id]);
        g_fLastCalcYaw[id] = fYaw;
        g_fNextRecalc[id] = now + recalcInterval;

        g_bHintVisible[id] = ComputeHint(
            id,
            vOrigin,
            fYaw,
            g_vecHintStart[id],
            g_vecHintEnd[id],
            g_iHintR[id],
            g_iHintG[id]
        );
    }

    if (g_bHintVisible[id]) {
        DrawHintBeam(id, g_vecHintStart[id], g_vecHintEnd[id], g_iHintR[id], g_iHintG[id]);
    }
}

stock Float:FloatAngleDelta(Float:a, Float:b)
{
    new Float:d = floatabs(a - b);
    while (d > 180.0) {
        d -= 360.0;
    }
    return floatabs(d);
}

stock KzDebugDrawLine(id, const Float:vStart[3], const Float:vEnd[3], r, g, b, life, width)
{
    if (!g_bKzDebug[id]) return;

    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, vStart[0]);
    engfunc(EngFunc_WriteCoord, vStart[1]);
    engfunc(EngFunc_WriteCoord, vStart[2]);
    engfunc(EngFunc_WriteCoord, vEnd[0]);
    engfunc(EngFunc_WriteCoord, vEnd[1]);
    engfunc(EngFunc_WriteCoord, vEnd[2]);
    write_short(g_spriteLaser);
    write_byte(0);
    write_byte(0);
    write_byte(life);
    write_byte(width);
    write_byte(0);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(200);
    write_byte(0);
    message_end();
}

stock KzDebugDrawPoint(id, const Float:vPos[3], r, g, b)
{
    if (!g_bKzDebug[id]) return;

    new Float:vStart[3], Float:vEnd[3];
    xs_vec_copy(vPos, vStart);
    xs_vec_copy(vPos, vEnd);
    vStart[2] -= 2.0;
    vEnd[2] += 2.0;
    KzDebugDrawLine(id, vStart, vEnd, r, g, b, 2, 3);
}

stock KzDebugMsg(id, const fmt[], any:...)
{
    if (!g_bKzDebug[id]) return;

    new Float:now = get_gametime();
    if (now < g_fNextDebugPrint[id]) return;
    g_fNextDebugPrint[id] = now + 0.20;

    new msg[190];
    vformat(msg, charsmax(msg), fmt, 3);
    client_print(id, print_chat, "[KZDBG] %s", msg);
}

stock DrawHintBeam(id, const Float:vStart[3], const Float:vEnd[3], r, g)
{
    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, vStart[0]);
    engfunc(EngFunc_WriteCoord, vStart[1]);
    engfunc(EngFunc_WriteCoord, vStart[2]);
    engfunc(EngFunc_WriteCoord, vEnd[0]);
    engfunc(EngFunc_WriteCoord, vEnd[1]);
    engfunc(EngFunc_WriteCoord, vEnd[2]);
    write_short(g_spriteLaser);
    write_byte(0);
    write_byte(0);
    write_byte(1);
    write_byte(2);
    write_byte(0);
    write_byte(r);
    write_byte(g);
    write_byte(0);
    write_byte(255);
    write_byte(0);
    message_end();
}

stock bool:TraceGroundAtDist(
    id,
    tr,
    const Float:vGroundPoint[3],
    const Float:vStepDir[3],
    Float:dist,
    Float:probeUp,
    Float:probeDown,
    Float:vProbeBase[3],
    Float:vHitPoint[3],
    Float:vHitNormal[3],
    &Float:fraction
)
{
    new Float:vStep[3], Float:vProbe[3], Float:vProbeDown[3];
    xs_vec_mul_scalar(vStepDir, dist, vStep);
    xs_vec_add(vGroundPoint, vStep, vProbeBase);

    xs_vec_copy(vProbeBase, vProbe);
    vProbe[2] += probeUp;
    xs_vec_copy(vProbe, vProbeDown);
    vProbeDown[2] -= probeDown;

    engfunc(EngFunc_TraceLine, vProbe, vProbeDown, IGNORE_MONSTERS, id, tr);
    get_tr2(tr, TR_flFraction, fraction);
    if (fraction >= 1.0) {
        return false;
    }

    get_tr2(tr, TR_vecEndPos, vHitPoint);
    get_tr2(tr, TR_vecPlaneNormal, vHitNormal);
    return true;
}

stock bool:ComputeHint(id, const Float:vOrigin[3], Float:fYaw, Float:vBeamStart[3], Float:vBeamEnd[3], &clrR, &clrG)
{
    const Float:PROBE_UP_Z = 24.0;
    const Float:PROBE_DOWN_Z = 160.0;
    const Float:PLANE_CHANGE_DOT = 0.97;
    const Float:EDGE_DROP_Z = 1.5;

    new Float:fStepLen = get_pcvar_float(g_pCvarStepLen);
    new Float:fProximity = get_pcvar_float(g_pCvarProximity);
    new Float:fThreshold = get_pcvar_float(g_pCvarThreshold);
    if (fStepLen < 0.5) fStepLen = HJ_STEP_LEN_DEFAULT;
    if (fProximity < 16.0) fProximity = PROXIMITY_LIMIT_DEFAULT;
    if (fThreshold < 1.0) fThreshold = HJ_THRESHOLD_DEFAULT;

    new Float:vYawAngles[3], Float:vViewDir[3];
    vYawAngles[0] = 0.0;
    vYawAngles[1] = fYaw;
    vYawAngles[2] = 0.0;
    angle_vector(vYawAngles, ANGLEVECTOR_FORWARD, vViewDir);
    vViewDir[2] = 0.0;
    if (xs_vec_len(vViewDir) < 0.01) return false;
    xs_vec_normalize(vViewDir, vViewDir);

    new tr = create_tr2();
    new Float:fraction;

    // 1) Ground under player's feet.
    new Float:vGroundStart[3], Float:vGroundEnd[3], Float:vGroundPoint[3], Float:vGroundNormal[3];
    xs_vec_copy(vOrigin, vGroundStart);
    vGroundStart[2] += 2.0;
    xs_vec_copy(vGroundStart, vGroundEnd);
    vGroundEnd[2] -= 96.0;

    engfunc(EngFunc_TraceLine, vGroundStart, vGroundEnd, IGNORE_MONSTERS, id, tr);
    get_tr2(tr, TR_flFraction, fraction);
    if (fraction >= 1.0) {
        KzDebugMsg(id, "no_ground frac=%.2f", fraction);
        free_tr2(tr);
        return false;
    }

    get_tr2(tr, TR_vecPlaneNormal, vGroundNormal);
    if (vGroundNormal[2] < 0.2) {
        KzDebugMsg(id, "reject_ground normal_z=%.2f", vGroundNormal[2]);
        free_tr2(tr);
        return false;
    }
    get_tr2(tr, TR_vecEndPos, vGroundPoint);

    // 2) March on standing plane along projected view direction.
    new Float:vStepDir[3], Float:vNormPart[3];
    xs_vec_mul_scalar(vGroundNormal, xs_vec_dot(vViewDir, vGroundNormal), vNormPart);
    xs_vec_sub(vViewDir, vNormPart, vStepDir);
    if (xs_vec_len(vStepDir) < 0.01) {
        KzDebugMsg(id, "reject_stepdir len<0.01");
        free_tr2(tr);
        return false;
    }
    xs_vec_normalize(vStepDir, vStepDir);

    new Float:vUphillDir[3];
    vUphillDir[0] = 0.0 - (vGroundNormal[0] * vGroundNormal[2]);
    vUphillDir[1] = 0.0 - (vGroundNormal[1] * vGroundNormal[2]);
    vUphillDir[2] = 1.0 - (vGroundNormal[2] * vGroundNormal[2]);
    if (xs_vec_len(vUphillDir) > 0.01) {
        xs_vec_normalize(vUphillDir, vUphillDir);
    }

    if (g_bKzDebug[id]) {
        new Float:vDbgEnd[3], Float:vTmp[3];
        KzDebugDrawPoint(id, vGroundPoint, 0, 255, 255);
        xs_vec_mul_scalar(vStepDir, 16.0, vTmp);
        xs_vec_add(vGroundPoint, vTmp, vDbgEnd);
        KzDebugDrawLine(id, vGroundPoint, vDbgEnd, 255, 255, 0, 2, 2);
    }

    new bool:bFoundEdge = false, bool:bPlaneBoundary = false, bool:bSuppressUphillBoundary = false;
    new Float:vEdgePoint[3], Float:vAirPoint[3], Float:vPrevPoint[3], Float:vPrevNormal[3], Float:vCurrPoint[3], Float:vCurrNormal[3];
    xs_vec_copy(vGroundPoint, vPrevPoint);
    xs_vec_copy(vGroundNormal, vPrevNormal);
    xs_vec_copy(vGroundPoint, vCurrPoint);
    xs_vec_copy(vGroundNormal, vCurrNormal);

    new maxSteps = floatround(fProximity / fStepLen, floatround_floor);
    for (new i = 1; i <= maxSteps; i++) {
        new Float:dist = float(i) * fStepLen;
        new Float:vProbeBase[3], Float:vHitPoint[3], Float:vHitNormal[3];
        new bool:bHit = TraceGroundAtDist(
            id, tr, vGroundPoint, vStepDir, dist, PROBE_UP_Z, PROBE_DOWN_Z,
            vProbeBase, vHitPoint, vHitNormal, fraction
        );

        if (!bHit) {
            // Refine ground->air edge location between [dist-fStepLen, dist].
            new Float:low = dist - fStepLen, Float:high = dist;
            new Float:vLowPoint[3], Float:vLowNormal[3];
            xs_vec_copy(vPrevPoint, vLowPoint);
            xs_vec_copy(vPrevNormal, vLowNormal);

            for (new r = 0; r < 3; r++) {
                new Float:mid = (low + high) * 0.5;
                new Float:vMidBase[3], Float:vMidPoint[3], Float:vMidNormal[3];
                new bool:bMidHit = TraceGroundAtDist(
                    id, tr, vGroundPoint, vStepDir, mid, PROBE_UP_Z, PROBE_DOWN_Z,
                    vMidBase, vMidPoint, vMidNormal, fraction
                );

                if (bMidHit) {
                    low = mid;
                    xs_vec_copy(vMidPoint, vLowPoint);
                    xs_vec_copy(vMidNormal, vLowNormal);
                } else {
                    high = mid;
                    xs_vec_copy(vMidBase, vAirPoint);
                }
            }

            xs_vec_copy(vLowPoint, vEdgePoint);
            xs_vec_copy(vLowNormal, vPrevNormal);
            xs_vec_copy(vLowPoint, vPrevPoint);
            bFoundEdge = true;
            bPlaneBoundary = false;
            break;
        }

        xs_vec_copy(vHitPoint, vCurrPoint);
        xs_vec_copy(vHitNormal, vCurrNormal);

        new Float:fDeltaZ = vCurrPoint[2] - vPrevPoint[2];
        new Float:fNormalDot = xs_vec_dot(vPrevNormal, vCurrNormal);

        if (fNormalDot < PLANE_CHANGE_DOT) {
            if (vGroundNormal[2] < 0.99
                && vCurrNormal[2] > (vPrevNormal[2] + 0.02)
                && xs_vec_dot(vStepDir, vUphillDir) > 0.15) {
                bSuppressUphillBoundary = true;
                break;
            }
            // Standing on flat/less-steep side and facing into an uphill slope boundary: suppress.
            if (vCurrNormal[2] < (vPrevNormal[2] - 0.02) && fDeltaZ > EDGE_DROP_Z) {
                bSuppressUphillBoundary = true;
                break;
            }
            // Refine plane-boundary transition using normal-change condition.
            new Float:lowB = dist - fStepLen, Float:highB = dist;
            new Float:vLowPointB[3], Float:vLowNormalB[3], Float:vHighPointB[3], Float:vHighNormalB[3];
            xs_vec_copy(vPrevPoint, vLowPointB);
            xs_vec_copy(vPrevNormal, vLowNormalB);
            xs_vec_copy(vCurrPoint, vHighPointB);
            xs_vec_copy(vCurrNormal, vHighNormalB);

            for (new r2 = 0; r2 < 3; r2++) {
                new Float:midB = (lowB + highB) * 0.5;
                new Float:vMidBaseB[3], Float:vMidPointB[3], Float:vMidNormalB[3];
                new bool:bMidHitB = TraceGroundAtDist(
                    id, tr, vGroundPoint, vStepDir, midB, PROBE_UP_Z, PROBE_DOWN_Z,
                    vMidBaseB, vMidPointB, vMidNormalB, fraction
                );

                if (!bMidHitB) {
                    highB = midB;
                    continue;
                }

                if (xs_vec_dot(vPrevNormal, vMidNormalB) < PLANE_CHANGE_DOT) {
                    highB = midB;
                    xs_vec_copy(vMidPointB, vHighPointB);
                    xs_vec_copy(vMidNormalB, vHighNormalB);
                } else {
                    lowB = midB;
                    xs_vec_copy(vMidPointB, vLowPointB);
                    xs_vec_copy(vMidNormalB, vLowNormalB);
                }
            }

            xs_vec_copy(vLowPointB, vEdgePoint);
            xs_vec_copy(vHighPointB, vAirPoint);
            xs_vec_copy(vLowNormalB, vPrevNormal);
            xs_vec_copy(vHighNormalB, vCurrNormal);
            bFoundEdge = true;
            bPlaneBoundary = true;
            break;
        }

        if (fDeltaZ < -EDGE_DROP_Z) {
            // Refine step-down transition by bisection on Z drop.
            new Float:lowS = dist - fStepLen, Float:highS = dist;
            new Float:vLowPointS[3], Float:vLowNormalS[3], Float:vHighPointS[3], Float:vHighNormalS[3];
            xs_vec_copy(vPrevPoint, vLowPointS);
            xs_vec_copy(vPrevNormal, vLowNormalS);
            xs_vec_copy(vCurrPoint, vHighPointS);
            xs_vec_copy(vCurrNormal, vHighNormalS);
            new Float:targetZ = vPrevPoint[2] - EDGE_DROP_Z;

            for (new r3 = 0; r3 < 3; r3++) {
                new Float:midS = (lowS + highS) * 0.5;
                new Float:vMidBaseS[3], Float:vMidPointS[3], Float:vMidNormalS[3];
                new bool:bMidHitS = TraceGroundAtDist(
                    id, tr, vGroundPoint, vStepDir, midS, PROBE_UP_Z, PROBE_DOWN_Z,
                    vMidBaseS, vMidPointS, vMidNormalS, fraction
                );
                if (!bMidHitS) {
                    highS = midS;
                    continue;
                }

                if (vMidPointS[2] <= targetZ) {
                    highS = midS;
                    xs_vec_copy(vMidPointS, vHighPointS);
                    xs_vec_copy(vMidNormalS, vHighNormalS);
                } else {
                    lowS = midS;
                    xs_vec_copy(vMidPointS, vLowPointS);
                    xs_vec_copy(vMidNormalS, vLowNormalS);
                }
            }

            xs_vec_copy(vLowPointS, vEdgePoint);
            xs_vec_copy(vHighPointS, vAirPoint);
            xs_vec_copy(vLowNormalS, vPrevNormal);
            xs_vec_copy(vHighNormalS, vCurrNormal);
            bFoundEdge = true;
            bPlaneBoundary = (vCurrNormal[2] < 0.99);
            break;
        }

        if (vCurrNormal[2] < 0.2) {
            xs_vec_copy(vPrevPoint, vEdgePoint);
            xs_vec_copy(vCurrPoint, vAirPoint);
            bFoundEdge = true;
            bPlaneBoundary = true;
            break;
        }

        xs_vec_copy(vCurrPoint, vPrevPoint);
        xs_vec_copy(vCurrNormal, vPrevNormal);
    }

    if (bSuppressUphillBoundary) {
        KzDebugMsg(id, "suppress_uphill_boundary");
        free_tr2(tr);
        return false;
    }

    if (!bFoundEdge || get_distance_f(vGroundPoint, vEdgePoint) > fProximity) {
        if (!bFoundEdge) KzDebugMsg(id, "no_edge within %.0f", fProximity);
        free_tr2(tr);
        return false;
    }

    // 3) Reliable edge direction only.
    new Float:vParallel[3], Float:vWallNormal[3];
    new bool:bGotWallNormal = false, bool:bReliableParallel = false;
    new Float:vWallStart[3], Float:vWallEnd[3], Float:vWallStep[3];
    xs_vec_mul_scalar(vStepDir, 14.0, vWallStep);

    for (new s = 0; s < 4; s++) {
        new Float:h = (s == 0) ? 4.0 : ((s == 1) ? 8.0 : ((s == 2) ? 14.0 : 22.0));
        xs_vec_add(vEdgePoint, vWallStep, vWallStart);
        xs_vec_sub(vEdgePoint, vWallStep, vWallEnd);
        vWallStart[2] = vEdgePoint[2] - h;
        vWallEnd[2] = vWallStart[2];

        engfunc(EngFunc_TraceLine, vWallStart, vWallEnd, IGNORE_MONSTERS, id, tr);
        get_tr2(tr, TR_flFraction, fraction);
        if (fraction < 1.0) {
            get_tr2(tr, TR_vecPlaneNormal, vWallNormal);
            if (xs_vec_len(vWallNormal) > 0.1 && floatabs(vWallNormal[2]) < 0.35) {
                bGotWallNormal = true;
                break;
            }
        }
    }

    if (bGotWallNormal) {
        xs_vec_cross(vPrevNormal, vWallNormal, vParallel);
        bReliableParallel = (xs_vec_len(vParallel) > 0.01);
    } else if (bPlaneBoundary) {
        xs_vec_cross(vPrevNormal, vCurrNormal, vParallel);
        bReliableParallel = (xs_vec_len(vParallel) > 0.01);
    }

    if (!bReliableParallel) {
        KzDebugMsg(id, "suppress_unreliable_parallel type=%d wall=%d", bPlaneBoundary, bGotWallNormal);
        free_tr2(tr);
        return false;
    }
    xs_vec_normalize(vParallel, vParallel);

    // 4) Drop: test both sides across edge.
    new Float:vDropStart[3], Float:vDropEnd[3], Float:vDropGround[3];
    new Float:vAcross[3], Float:vAcrossStep[3];
    xs_vec_cross(vParallel, vPrevNormal, vAcross);
    if (xs_vec_len(vAcross) < 0.01) {
        xs_vec_copy(vStepDir, vAcross);
    } else {
        xs_vec_normalize(vAcross, vAcross);
    }

    new bool:bGotDrop = false;
    new bestSide = 0;
    new Float:fDropDist = -9999.0;
    for (new side = 0; side < 2; side++) {
        new Float:sign = (side == 0) ? 1.0 : -1.0;
        xs_vec_mul_scalar(vAcross, sign * 6.0, vAcrossStep);
        xs_vec_add(vEdgePoint, vAcrossStep, vDropStart);
        vDropStart[2] += 2.0;
        xs_vec_copy(vDropStart, vDropEnd);
        vDropEnd[2] -= 800.0;

        engfunc(EngFunc_TraceLine, vDropStart, vDropEnd, IGNORE_MONSTERS, id, tr);
        get_tr2(tr, TR_flFraction, fraction);
        if (fraction >= 1.0) continue;

        get_tr2(tr, TR_vecEndPos, vDropGround);
        new Float:thisDrop = vEdgePoint[2] - vDropGround[2];
        if (!bGotDrop || thisDrop > fDropDist) {
            bGotDrop = true;
            fDropDist = thisDrop;
            bestSide = side;
        }
    }

    if (!bGotDrop) {
        KzDebugMsg(id, "drop_miss both_sides");
        free_tr2(tr);
        return false;
    }

    if (!bPlaneBoundary && fDropDist <= 0.5) {
        KzDebugMsg(id, "tiny_drop=%.2f reject", fDropDist);
        free_tr2(tr);
        return false;
    }
    if (!bPlaneBoundary && vPrevNormal[2] < 0.99 && fDropDist < 5.0) {
        KzDebugMsg(id, "slope_small_drop=%.2f reject", fDropDist);
        free_tr2(tr);
        return false;
    }

    clrR = (fDropDist >= fThreshold) ? 255 : 0;
    clrG = (fDropDist >= fThreshold) ? 0 : 255;

    new Float:vBeamCenter[3], Float:vBeamHalf[3];
    xs_vec_copy(vEdgePoint, vBeamCenter);
    xs_vec_mul_scalar(vParallel, 10.0, vBeamHalf);
    xs_vec_sub(vBeamCenter, vBeamHalf, vBeamStart);
    xs_vec_add(vBeamCenter, vBeamHalf, vBeamEnd);

    if (g_bKzDebug[id]) {
        KzDebugDrawPoint(id, vEdgePoint, 255, 200, 0);
        KzDebugDrawPoint(id, vAirPoint, 255, 80, 80);
        KzDebugDrawPoint(id, vBeamCenter, 255, 255, 255);
        KzDebugDrawLine(id, vBeamStart, vBeamEnd, 120, 120, 255, 2, 2);
        KzDebugMsg(id, "dir par(%.2f %.2f %.2f) n1(%.2f %.2f %.2f) n2(%.2f %.2f %.2f) type=%d wall=%d drop=%.1f side=%d", vParallel[0], vParallel[1], vParallel[2], vPrevNormal[0], vPrevNormal[1], vPrevNormal[2], vCurrNormal[0], vCurrNormal[1], vCurrNormal[2], bPlaneBoundary, bGotWallNormal, fDropDist, bestSide);
    }

    free_tr2(tr);
    return true;
}
