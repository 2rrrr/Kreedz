//
// GCLJS
//

#if defined _gcljs_included
	#endinput
#endif
#define _gcljs_included

#define GC_MAX_PLAYERS 33
#define GCLJS_CONFIG_NAME "gcljs"

#define CHAT_PREFIX    "!w[!gGC!w]"
#define CONSOLE_PREFIX "[GC]"

#define MAX_STRAFES        20
#define MAX_EDGE           32.0
#define MAX_JUMP_FRAMES    200 // for frame based arrays
#define MAX_BHOP_FRAMES    8
#define MAX_GSTRAFE_FRAMES 8

#define HUD_GRAPH_MAX_CHARS 128

#define SOUND_PATH_TIER_1 "gcljs/impressive.wav"
#define SOUND_PATH_TIER_2 "gcljs/perfect.wav"
#define SOUND_PATH_TIER_3 "gcljs/godlike.wav"
#define SOUND_PATH_TIER_4 "gcljs/ownage.wav"
#define SOUND_PATH_TIER_5 "gcljs/wrecker.wav"

#define GC_FLOAT_NAN               (Float:0xffffffff)
#define GC_FLOAT_INFINITY          (Float:0x7f800000)
#define GC_FLOAT_NEGATIVE_INFINITY (Float:0xff800000)

#define GC_DUCK_HEIGHT_CHANGE 18.0
// NOTE: 4.0 isn't randomly chosen. roughly the max speed you can
//  go up a ladder is 400u/s aka 4 units per frame at 100fps.
// HACK: TODO: find real ladder z height with an engine trace!
#define GC_OFFSET_TOLERANCE_LDJ 4.0
#define GC_OFFSET_TOLERANCE_BJ 1.5

#define GC_REPLAY_DIR "addons/amxmodx/data/gcljs_replays/"
#define GC_REPLAY_EXT "gcljrp"
#define GC_REPLAY_IDENT "GCLJ"
#define GC_REPLAY_MAGIC 0x6c115
#define GC_REPLAY_VERSION 1

// ""enum struct""
/*
Drawbacks of enum structs:

enum Test
{
	Float:Position[3],
	Float:LAST_POSITION[3]
}

new struct[Test];

This only sets the first element of LAST_POSITION:
	struct[LAST_POSITION] = struct[Position]

This generates a run time memory access error:
	new Float:array[3];
	array = struct[LAST_POSITION];

This generates the same error:
	struct[LAST_POSITION] = array;

However, this works perfectly:
	struct[LAST_POSITION] = {1.0, 2.0, 3.0};

Need to use helper functions to set and get arrays.
*/
enum JumpType
{
	// unprintable jumptypes. only for tracking
	JUMPTYPE_NONE,
	
	JUMPTYPE_DD, // double duck with FOG > 8
	JUMPTYPE_GS, // groundstrafe: double duck with FOG <= 8
	
	// printable jumptypes
	JUMPTYPE_LJ,  // longjump
	// TODO: highjump!?
	JUMPTYPE_CJ,  // countjump
	JUMPTYPE_DCJ, // double countjump
	JUMPTYPE_MCJ, // multi countjump
	JUMPTYPE_SCJ, // standup countjump
	JUMPTYPE_WJ,  // weirdjump
	JUMPTYPE_LDJ, // ladderjump
	JUMPTYPE_BH,  // bunnyhop
	JUMPTYPE_DBH, // ducked bunnyhop
	JUMPTYPE_SBJ, // standup bunnyjump
	JUMPTYPE_SLJ, // standup longjump
};

enum JumpTier
{
	JUMPTIER_0,
	JUMPTIER_1,
	JUMPTIER_2,
	JUMPTIER_3,
	JUMPTIER_4,
	JUMPTIER_5,
	JUMPTIER_MAX_DIST,
};

enum JumpDir
{
	JUMPDIR_FORWARDS,
	JUMPDIR_BACKWARDS,
	JUMPDIR_LEFT,
	JUMPDIR_RIGHT,
}

enum StrafeType
{
	STRAFETYPE_OVERLAP,         // IN_MOVELEFT and IN_MOVERIGHT are overlapping and sidespeed is 0
	STRAFETYPE_NONE,            // IN_MOVELEFT and IN_MOVERIGHT are both not pressed and sidespeed is 0
	
	STRAFETYPE_LEFT,            // only IN_MOVELEFT is down and sidespeed isn't 0.
	STRAFETYPE_OVERLAP_LEFT,    // IN_MOVELEFT and IN_MOVERIGHT are overlapping, but sidespeed is smaller than 0 (not 0)
	STRAFETYPE_NONE_LEFT,       // IN_MOVELEFT and IN_MOVERIGHT are both not pressed and sidespeed is smaller than 0 (not 0)
	
	STRAFETYPE_RIGHT,           // only IN_MOVERIGHT is down and sidespeed isn't 0.
	STRAFETYPE_OVERLAP_RIGHT,   // IN_MOVELEFT and IN_MOVERIGHT are overlapping, but sidespeed is bigger than 0 (not 0)
	STRAFETYPE_NONE_RIGHT,      // IN_MOVELEFT and IN_MOVERIGHT are both not pressed and sidespeed is bigger than 0 (not 0)
};

enum JumpBeamColour
{
	JUMPBEAM_NEUTRAL, // speed stays the same
	JUMPBEAM_LOSS,    // speed loss
	JUMPBEAM_GAIN,  // speed gain
	JUMPBEAM_DUCK,   // duck key down
};

enum OptionType
{
	OPT_FIRST,
	OPT_ENABLE_PLUGIN = 0,
	OPT_ENABLE_SOUNDS,
	OPT_ENABLE_FAILSTAT_SOUNDS,
	OPT_SHOW_SPEED,
	OPT_SHOW_HUD_GRAPH,
	OPT_SHOW_HUD_STRAFE_STATS,
	OPT_SHOW_HUD_JUMP_STATS,
	OPT_HUD_STATS_VERTICAL,
	OPT_SHOW_JUMP_BEAM,
	OPT_SHOW_VEER_BEAM,
	OPT_CLEAR_HUD_BEAM_ON_TP,
	OPT_JUMP_INFO_X,
	OPT_JUMP_INFO_Y,
	OPT_STRAFE_GRAPH_X,
	OPT_STRAFE_GRAPH_Y,
	OPT_STRAFE_STATS_X,
	OPT_STRAFE_STATS_Y,
	OPT_SPEED_X,
	OPT_SPEED_Y,
	OPT_COUNT,
};

enum OptionTag
{
	OPT_TAG_INTEGER,
	OPT_TAG_FLOAT,
};

enum Option
{
	OP_NAME[128], // cvar name
	OP_DEFAULT_VALUE[32],
	OP_DESCRIPTION[128],
	OP_MIN,
	OP_MAX,
	OptionType:OP_OPTION_TYPE, // for checking if g_cvars index matches the OptionType enum: g_cvars[OPT_SHOW_VEER_BEAM][OP_OPTION_TYPE] == OPT_SHOW_VEER_BEAM
	OptionTag:OP_TAG,
	OP_VALUE, // integer
	OP_CVAR, // the actual cvar handle
};

enum FrameData
{
	Float:FD_ORIGIN[3],
	Float:FD_VELOCITY[3],
	Float:FD_ANGLES[3],
	Float:FD_WISHMOVE[3], // TODO: does this include maxspeed?
	Float:FD_STAMINA,
	FD_BUTTONS,
	FD_FLAGS,
	FD_MOVETYPE,
	// TODO: include weapon
};

enum ReplayTally
{
	RT_FRAMEINDEX,
	RT_FRAMECOUNT,
};

enum PlayerData
{
	USERCMD_COUNT,
	TIME_MSEC,
	FRAMETIME_MSEC,
	
	FRAMES_ON_GROUND,
	FRAMES_IN_AIR,
	Float:ANGLE_SPEED[3],
	Float:LAST_ANGLE_SPEED[3],
	Float:LAST_GROUND_POS[3], // last position where the player left the ground.
	bool:LAST_GROUND_POS_WALKED_OFF,
	bool:LANDED_DUCKED,
	
	bool:SPEED_SHOW_PRESPEED,
	PRESPEED_FOG,
	Float:PRESPEED_STAMINA,
	
	Float:JUMP_GROUND[3],
	Float:JUMP_POS[3],
	Float:JUMP_ANGLES[3],
	Float:JUMP_VELOCITY[3],
	Float:LAND_POS[3],
	
	FWD_RELEASE_FRAME,
	JUMP_FRAME,
	bool:TRACKING_JUMP,
	bool:FAILED_JUMP,
	
	LADDER_ENTITY,
	Float:LADDER_NORMAL[3],
	Float:LADDER_MINS[3],
	Float:LADDER_MAXS[3],
	
	// Jump data
	JumpType:JUMP_TYPE,
	JumpType:LAST_JUMP_TYPE,
	JumpDir:JUMP_DIR,
	Float:JUMP_DISTANCE,
	Float:JUMP_XJ_DISTANCE,
	Float:JUMP_PRESPEED,
	Float:JUMP_MAXSPEED,
	Float:JUMP_WEAPONSPEED,
	Float:JUMP_LOSS,
	Float:JUMP_VEER,
	Float:JUMP_AIRPATH,
	Float:JUMP_SYNC,
	Float:JUMP_POTENCY,
	Float:JUMP_EDGE,
	Float:JUMP_EDGES[8], // four 2d vectors
	Float:JUMP_LAND_EDGE,
	Float:JUMP_BLOCK_DIST,
	Float:JUMP_HEIGHT,
	Float:JUMP_JUMPOFF_ANGLE,
	JUMP_START_MSEC,
	JUMP_AIRTIME,
	JUMP_FWD_RELEASE,
	JUMP_OVERLAP,
	JUMP_DEADAIR,
	JUMP_WEAPON,
	
	// strafes!
	STRAFE_COUNT,
	Float:STRAFE_SYNC[MAX_STRAFES],
	Float:STRAFE_GAIN[MAX_STRAFES],
	Float:STRAFE_LOSS[MAX_STRAFES],
	Float:STRAFE_MAX[MAX_STRAFES],
	STRAFE_FRAME[MAX_STRAFES],
	STRAFE_AIRTIME[MAX_STRAFES],
	STRAFE_OVERLAP[MAX_STRAFES],
	STRAFE_DEADAIR[MAX_STRAFES],
	Float:STRAFE_AVG_GAIN[MAX_STRAFES],
	Float:STRAFE_AVG_EFFICIENCY[MAX_STRAFES],
	Float:STRAFE_PEAK_EFFICIENCY[MAX_STRAFES],
	
	// TODO: use replay data for these!
	StrafeType:STRAFE_GRAPH[MAX_JUMP_FRAMES],
	Float:MOUSE_GRAPH[MAX_JUMP_FRAMES],
	DUCK_GRAPH[MAX_JUMP_FRAMES],
};

enum ReplayHeader
{
	RP_IDENT, // GCLJ
	RP_MAGIC, // 0x6cl15
	PlayerData:RP_PLAYERDATA[PlayerData],
};

enum HudAndBeamData
{
	HBD_FRAMES,
	Float:HBD_JUMP_BEAM_X[MAX_JUMP_FRAMES],
	Float:HBD_JUMP_BEAM_Y[MAX_JUMP_FRAMES],
	JumpBeamColour:HBD_JUMP_BEAM_COLOUR[MAX_JUMP_FRAMES],
	Float:VEERBEAM_START[3],
	Float:VEERBEAM_END[3],
	HUD_TOP_STRING[512],
	HUD_MLEFT_STRING[512],
	HUD_MRIGHT_STRING[512],
	HUD_STRAFESTAT_STRING[512],
	HBD_TIMESTAMP_MSEC,
};

enum
{
	MODEL_T_NAME_BYTES = 64,
	MODEL_T_NEEDLOAD_BYTES = 4,
	MODEL_T_TYPE_BYTES = 4,
	MODEL_T_NUMFRAMES_BYTES = 4,
	MODEL_T_SYNCTYPE_BYTES = 4,
	MODEL_T_FLAGS_BYTES = 4,
	MODEL_T_MINS_BYTES = 12,
	MODEL_T_MAXS_BYTES = 12,
};

enum
{
	MODEL_T_NAME_OFFSET      = 0,
	MODEL_T_NEEDLOAD_OFFSET  = MODEL_T_NAME_OFFSET      + MODEL_T_NAME_BYTES,
	MODEL_T_TYPE_OFFSET      = MODEL_T_NEEDLOAD_OFFSET  + MODEL_T_NEEDLOAD_BYTES,
	MODEL_T_NUMFRAMES_OFFSET = MODEL_T_TYPE_OFFSET      + MODEL_T_TYPE_BYTES,
	MODEL_T_SYNCTYPE_OFFSET  = MODEL_T_NUMFRAMES_OFFSET + MODEL_T_NUMFRAMES_BYTES,
	MODEL_T_FLAGS_OFFSET     = MODEL_T_SYNCTYPE_OFFSET  + MODEL_T_SYNCTYPE_BYTES,
	MODEL_T_MINS_OFFSET      = MODEL_T_FLAGS_OFFSET     + MODEL_T_FLAGS_BYTES,
	MODEL_T_MAXS_OFFSET      = MODEL_T_MINS_OFFSET      + MODEL_T_MINS_BYTES,
};

/**
 * Check if player is overlapping their MOVERIGHT and MOVELEFT buttons.
 *
 * @param x					Buttons;
 * @return 					True if overlapping, false otherwise.
 */
stock bool:IsOverlapping(buttons, JumpDir:jumpDir)
{
	if (jumpDir == JUMPDIR_FORWARDS || jumpDir == JUMPDIR_BACKWARDS)
	{
		return (buttons & IN_MOVERIGHT) && (buttons & IN_MOVELEFT);
	}
	// else if (jumpDir == JUMPDIR_LEFT || jumpDir == JUMPDIR_RIGHT)
	return (buttons & IN_FORWARD) && (buttons & IN_BACK);
}

/**
 * Checks if the player is not holding down their MOVERIGHT and MOVELEFT buttons.
 *
 * @param x					Buttons.
 * @return 					True if they're not holding either, false otherwise.
 */
stock bool:IsDeadAirtime(buttons, JumpDir:jumpDir)
{
	if (jumpDir == JUMPDIR_FORWARDS || jumpDir == JUMPDIR_BACKWARDS)
	{
		return (!(buttons & IN_MOVERIGHT) && !(buttons & IN_MOVELEFT));
	}
	// else if (jumpDir == JUMPDIR_LEFT || jumpDir == JUMPDIR_RIGHT)
	return (!(buttons & IN_FORWARD) && !(buttons & IN_BACK));
}

/**
 * Checks if vector normal is axially aligned. Normal doesn't have to be normalised.
 *
 * @param normal			Normal to check.
 * @return 					True if the normal is axially aligned, otherwise false.
 */
stock bool:IsNormalAxial(const Float:normal[3])
{
	new max = floatabs(normal[0]) > floatabs(normal[1]) ? 0 : 1;
	max = floatabs(normal[max]) > floatabs(normal[2]) ? max : 2;
	return IsRoughlyEqual(floatabs(normal[(max + 1) % 3]), 0.0, 0.00001)
		&& IsRoughlyEqual(floatabs(normal[(max + 2) % 3]), 0.0, 0.00001);
}

/**
 * Traces a hull between 2 positions.
 *
 * @param pos1				Position 1.
 * @param pos2				Position 2
 * @param result			Trace endpoint.
 * @return 					True on success, false otherwise.
 */
stock bool:TraceBlock(const Float:pos1[3], const Float:pos2[3], Float:result[3])
{
	engfunc(EngFunc_TraceHull, pos1, pos2, IGNORE_MONSTERS, HULL_HEAD, 0, 0);
	
	new Float:fraction;
	new Float:normal[3];
	get_tr2(0, TR_Fraction, fraction);
	get_tr2(0, TR_vecPlaneNormal, normal);
	get_tr2(0, TR_vecEndPos, result);
	if (fraction != 1.0 && fraction != 0.0 && IsNormalAxial(normal))
	{
		return true;
	}
	
	return false;
}

/**
 * Checks if a float is within a range inclusively
 *
 * @param number			Float to check.
 * @param min				Minimum range.
 * @param max				Maximum range.
 * @return 					True on success, false otherwise.
 */
stock bool:IsFloatInRange(Float:number, Float:min, Float:max)
{
	return number >= min && number <= max;
}

/**
 * Checks if a float is within a range exclusively
 *
 * @param number			Float to check.
 * @param min				Minimum range.
 * @param max				Maximum range.
 * @return 					True on success, false otherwise.
 */
stock bool:IsFloatInRangeExclusive(Float:number, Float:min, Float:max)
{
	return number > min && number < max;
}

/**
 * Compares how close 2 floats are.
 *
 * @param z1				Float 1
 * @param z2				Float 2
 * @param tolerance			How close the floats have to be to return true.
 * @return 					True on success, false otherwise.
 */
stock bool:IsRoughlyEqual(Float:z1, Float:z2, Float:tolerance)
{
	return IsFloatInRange(z1 - z2, -tolerance, tolerance);
}

/**
 * Keeps the yaw angle within the range of -180 to 180.
 *
 * @param angle				Angle.
 * @return 					Normalised angle.
 */
stock Float:NormaliseYaw(Float:yaw)
{
	if (yaw <= -180.0)
	{
		yaw += 360.0;
	}
	
	if (yaw > 180.0)
	{
		yaw -= 360.0;
	}
	
	return yaw;
}

stock Float:CalculateGain(Float:wishdirAng, Float:wishspeed, Float:accel, Float:initialSpeed)
{
	new Float:wishdir[2];
	wishdir[0] = floatcos(wishdirAng);
	wishdir[1] = floatsin(wishdirAng);
	
	new Float:wishspd = wishspeed;
	if (wishspd > 30.0)
	{
		wishspd = 30.0;
	}
	
	new Float:velocity[2];
	velocity[0] = initialSpeed;
	
	new Float:currentspeed = velocity[0] * wishdir[0] + velocity[1] * wishdir[1];
	
	new Float:addspeed = wishspd - currentspeed;
	if (addspeed <= 0.0)
	{
		return 0.0;
	}
	new Float:frametime;
	global_get(glb_frametime, frametime);
	new Float:accelspeed = accel * wishspeed * frametime;
	if (accelspeed > addspeed)
	{
		accelspeed = addspeed;
	}
	
	for (new i = 0; i < 2; i++)
	{
		velocity[i] += accelspeed * wishdir[i];
	}
	new Float:newSpeed = VectorLengthXY(velocity);
	new Float:result = newSpeed - initialSpeed;
	return result;
}

stock ToggleCVar(cvar)
{
	set_pcvar_num(cvar, !get_pcvar_num(cvar));
}

stock IncrementCvar(cvar, min, max)
{
	new newValue = (get_pcvar_num(cvar) + 1);
	if (newValue > max)
	{
		newValue = min;
	}
	set_pcvar_num(cvar, newValue);
}

stock TE_SendBeamPoints(client,
	spriteIndex,
	startPos[3], endPos[3],
	red, green, blue, brightness,
	width = 10,
	life = 20,
	startingFrame = 0,
	frameRate = 0,
	noiseAmplitude = 0,
	scrollSpeed = 0)
{
	message_begin(MSG_ONE, SVC_TEMPENTITY, .player = client);
	write_byte(TE_BEAMPOINTS);
	write_coord(startPos[0]);
	write_coord(startPos[1]);
	write_coord(startPos[2]);
	write_coord(endPos[0]);
	write_coord(endPos[1]);
	write_coord(endPos[2]);
	write_short(spriteIndex);
	write_byte(startingFrame);
	write_byte(frameRate); // frame rate in 0.1's
	write_byte(life); // life in 0.1's
	write_byte(width); // line width in 0.1's
	write_byte(noiseAmplitude); // noise amplitude in 0.01's
	write_byte(red);
	write_byte(green);
	write_byte(blue);
	write_byte(brightness);
	write_byte(scrollSpeed); // scroll speed in 0.1's
	message_end();
}

// from https://github.com/HLTAS/hlstrafe
stock Float:CalcOptimalWishdirYaw(Float:airMaxWishspeed, Float:airaccelerate, Float:groundMaxspeed, Float:frametime, const Float:velocity[])
{
	new Float:horizontalSpeed = VectorLengthXY(velocity);
	new Float:accelspeed = airaccelerate * groundMaxspeed * frametime;
	
	new Float:result = 0.0;
	if (accelspeed <= 0.0)
	{
		result = xs_deg2rad(180.0);
	}
	Float:CalculateGain(Float:wishdirAng, Float:wishspeed, Float:accel, Float:initialSpeed)
	{
		new Float:wishdir[2];
		wishdir[0] = floatcos(wishdirAng);
		wishdir[1] = floatsin(wishdirAng);
		
		new Float:wishspd = wishspeed;
		if (wishspd > 30.0)
		{
			wishspd = 30.0;
		}
		
		new Float:velocity[2];
		velocity[0] = initialSpeed;
		
		new Float:currentspeed = velocity[0] * wishdir[0] + velocity[1] * wishdir[1];
		
		new Float:addspeed = wishspd - currentspeed;
		if (addspeed <= 0.0)
		{
			return 0.0;
		}
		new Float:frametime;
		global_get(glb_frametime, frametime);
		new Float:accelspeed = accel * wishspeed * frametime;
		if (accelspeed > addspeed)
		{
			accelspeed = addspeed;
		}
		
		for (new i = 0; i < 2; i++)
		{
			velocity[i] += accelspeed * wishdir[i];
		}
		new Float:newSpeed = VectorLengthXY(velocity);
		new Float:result = newSpeed - initialSpeed;
		return result;
	}
	
	else if (horizontalSpeed > 0.0)
	{
		new Float:tmp = airMaxWishspeed - accelspeed;
		if (tmp <= 0.0)
		{
			result = xs_deg2rad(90.0);
		}
		else if (tmp < horizontalSpeed)
		{
			result = floatacos(tmp / horizontalSpeed, radian);
		}
	}
	
	return result;
}

stock RegisterChatAndConsoleCmd(const cmd[], const conCmd[], const function[], flags=-1, const info[]="", FlagManager=-1)
{
	new sayCmd[128];
	formatex(sayCmd, charsmax(sayCmd), "say /%s", cmd);
	register_concmd(sayCmd, function, flags, info, FlagManager);
	register_concmd(conCmd, function, flags, info, FlagManager);
}

stock GetPlayerFeetPosition(client, Float:result[])
{
	new Float:temp[3];
	entity_get_vector(client, EV_VEC_origin, temp);
	result[0] = temp[0];
	result[1] = temp[1];
	result[2] = temp[2];
	if (entity_get_int(client, EV_INT_flags) & FL_DUCKING)
	{
		result[2] -= 18.0;
	}
	else
	{
		result[2] -= 36.0;
	}
}

stock GetPlayerAngles(client, Float:result[])
{
	new Float:temp[3];
	pev(client, pev_v_angle, temp);
	result[0] = temp[0];
	result[1] = temp[1];
	result[2] = temp[2];
}

stock GetPlayerVelocity(client, Float:result[])
{
	new Float:temp[3];
	entity_get_vector(client, EV_VEC_velocity, temp);
	result[0] = temp[0];
	result[1] = temp[1];
	result[2] = temp[2];
}

stock SetPlayerAngles(client, Float:angles[])
{
	set_pev(client, pev_angles, angles);
	set_pev(client, pev_fixangle, 1);
}

stock Float:SetPlayerPosition(client, Float:feetPos[])
{
	new Float:origin[3];
	origin[0] = feetPos[0];
	origin[1] = feetPos[1];
	origin[2] = feetPos[2];
	if (entity_get_int(client, EV_INT_flags) & FL_DUCKING)
	{
		origin[2] += 18.0;
	}
	else
	{
		origin[2] += 36.0;
	}
	
	engfunc(EngFunc_SetOrigin, client, origin);
}

// NOTE: size of origin, velocity and result must be at least 3
stock GetRealLandingOrigin(Float:landGroundZ, const Float:origin[], const Float:velocity[], Float:result[])
{
	if ((origin[2] - landGroundZ) == 0.0)
	{
		PDCopyVector(origin, result);
		return;
	}
	
	// this is like this because it works
	new Float:frametime;
	global_get(glb_frametime, frametime);
	new Float:verticalDistance = origin[2] - (origin[2] + velocity[2] * frametime);
	new Float:fraction = (origin[2] - landGroundZ) / verticalDistance;
	
	new Float:addDistance[3];
	PDCopyVector(velocity, addDistance);
	xs_vec_mul_scalar(addDistance, frametime * fraction, addDistance);
	
	xs_vec_add(origin, addDistance, result);
}

Float:VectorLengthXY(const Float:vector[])
{
	return floatsqroot(vector[0] * vector[0] + vector[1] * vector[1]);
}

Float:VectorDistanceXY(const Float:vec1[], const Float:vec2[])
{
	new Float:temp[3];
	xs_vec_sub(vec1, vec2, temp);
	return VectorLengthXY(temp);
}

stock CenterPrint(client, format[], any:...)
{
	new message[512];
	vformat(message, charsmax(message), format, 3);
	
	engfunc(EngFunc_ClientPrintf, client, 1, message);
}

stock PDCopyVector(const Float:source[], Float:destination[])
{
	destination[0] = source[0];
	destination[1] = source[1];
	destination[2] = source[2];
}

stock BytesToCell(array[])
{
	return ((array[0]) | (array[1] << 8) | (array[2] << 16) | (array[3] << 24));
}
