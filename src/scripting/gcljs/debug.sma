
plugin_init_debug()
{
	register_concmd("setpos", "CommandSetpos");
	register_concmd("say /setpos", "CommandSetpos");
	register_concmd("getpos", "CommandGetpos");
	register_concmd("say /getpos", "CommandGetpos");
	register_concmd("tracetest", "CommandTracetest");
	register_concmd("say /tracetest", "CommandTracetest");
}

public CommandSetpos(client, args)
{
	if (!is_user_alive(client))
	{
		return PLUGIN_HANDLED;
	}
	
	if (read_argc() != 7)
	{
		client_print(client, print_chat, "Invalid number of arguments %i. Expected 6!", read_argc());
		return PLUGIN_HANDLED;
	}
	new args[256];
	read_args(args, charsmax(args));
	
	new szOrigin[3][16];
	new szAngles[3][16];
	parse(args, szOrigin[0], charsmax(szOrigin[]), szOrigin[1], charsmax(szOrigin[]), szOrigin[2], charsmax(szOrigin[]),
		szAngles[0], charsmax(szAngles[]), szAngles[1], charsmax(szAngles[]), szAngles[2], charsmax(szAngles[]));
	
	new Float:origin[3];
	new Float:angles[3];
	for (new i = 0; i < 3; i++)
	{
		origin[i] = floatstr(szOrigin[i]);
		angles[i] = floatstr(szAngles[i]);
	}
	
	SetPlayerPosition(client, origin);
	SetPlayerAngles(client, angles);
	
	return PLUGIN_HANDLED;
}

public CommandGetpos(client, args)
{
	if (!is_user_alive(client))
	{
		return PLUGIN_HANDLED;
	}
	new currentFrame = GetReplayFrameIndex(client, 1);
	client_print(client, print_console, "setpos %.8f %.8f %.8f %f %f %f",
		g_replay[client][currentFrame][FD_ORIGIN][0], g_replay[client][currentFrame][FD_ORIGIN][1], g_replay[client][currentFrame][FD_ORIGIN][2],
		g_replay[client][currentFrame][FD_ANGLES][0], g_replay[client][currentFrame][FD_ANGLES][1], g_replay[client][currentFrame][FD_ANGLES][2]);
	return PLUGIN_HANDLED;
}

public CommandTracetest(client, args)
{
	if (!is_user_alive(client))
	{
		return PLUGIN_HANDLED;
	}
	
	if (read_argc() != 7)
	{
		client_print(client, print_chat, "Invalid number of arguments %i. Expected 6!", read_argc());
		return PLUGIN_HANDLED;
	}
	
	new args[256];
	read_args(args, charsmax(args));
	
	new szEndPos[3][16];
	new szStartPos[3][16];
	parse(args, szEndPos[0], charsmax(szEndPos[]), szEndPos[1], charsmax(szEndPos[]), szEndPos[2], charsmax(szEndPos[]),
		  szStartPos[0], charsmax(szStartPos[]), szStartPos[1], charsmax(szStartPos[]), szStartPos[2], charsmax(szStartPos[]));
	
	new Float:startPos[3];
	new Float:endPos[3];
	for (new i = 0; i < 3; i++)
	{
		endPos[i] = floatstr(szEndPos[i]);
		startPos[i] = endPos[i] + floatstr(szStartPos[i]);
	}
	
	engfunc(EngFunc_TraceHull, startPos, endPos, IGNORE_MONSTERS, HULL_HEAD, 0, 0);
	new Float:fraction;
	new Float:normal[3];
	new Float:hitPos[3];
	get_tr2(0, TR_Fraction, fraction);
	get_tr2(0, TR_vecPlaneNormal, normal);
	get_tr2(0, TR_vecEndPos, hitPos);
	client_print(client, print_console, "fraction: %.4f; normal (%.4f %.4f %.4f); hitpos (%.4f %.4f %.4f); startpos (%.4f %.4f %.4f)",
				 fraction, normal[0], normal[1], normal[2],
				 hitPos[0], hitPos[1], hitPos[2], startPos[0], startPos[1], startPos[2]);
	
	return PLUGIN_HANDLED;
}

PlayerPreThinkDebug(client)
{
	new currentFrame = GetReplayFrameIndex(client, 1);
	CenterPrint(client, "%.5f %.5f %.5f\n%.5f %.5f %.5f\r\nMovetype: %i Tracking jump: %i\nFIA: %i\nFOG: %i\nTime: %i Frametime: %i Cmds: %i",
		g_replay[client][currentFrame][FD_ORIGIN][0], g_replay[client][currentFrame][FD_ORIGIN][1], g_replay[client][currentFrame][FD_ORIGIN][2],
		g_replay[client][currentFrame][FD_ANGLES][0], g_replay[client][currentFrame][FD_ANGLES][1], g_replay[client][currentFrame][FD_ANGLES][2],
		g_replay[client][currentFrame][FD_MOVETYPE], g_pd[client][TRACKING_JUMP],
		g_pd[client][FRAMES_IN_AIR], g_pd[client][FRAMES_ON_GROUND], g_pd[client][TIME_MSEC], g_pd[client][FRAMETIME_MSEC], g_pd[client][USERCMD_COUNT]);
}
