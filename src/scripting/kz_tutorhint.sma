#include <amxmodx>
#include <fakemeta>
#include <sqlx>

#include <kreedz_sql>
#include <kreedz_util>

#define PLUGIN  "[Kreedz] Tutor Hint"
#define VERSION __DATE__
#define AUTHOR  "2rrrr / Codex"

#if !defined IN_SCORE
	#define IN_SCORE (1<<15)
#endif

#define TUTOR_COLOR_YELLOW (1<<3)

enum _:MapMetaStruct {
	eMapCreator[64],
	eMapCreatorCountry[32],
	eMapTierSimen[32],
	eMapTierRush[32],
	eMapType[32],
	eMapLength[32]
};

enum _:PersonalBestStruct {
	bool:pbLoaded,
	bool:pbLoading,
	bool:pbHasPro,
	bool:pbHasNub,
	Float:pbProTime,
	Float:pbNubTime,
	pbNubCp,
	pbNubTp
};

new bool:g_bTabPressed[MAX_PLAYERS + 1];
new g_msgTutorText;
new g_msgTutorClose;

new g_szMapName[64];
new g_MapMetaInfo[MapMetaStruct];

new g_UserPb[MAX_PLAYERS + 1][PersonalBestStruct];

new bool:g_bSqlReady;

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	g_msgTutorText = get_user_msgid("TutorText");
	g_msgTutorClose = get_user_msgid("TutorClose");

	if (!g_msgTutorText || !g_msgTutorClose) {
		server_print("[Kreedz Tutor Hint] TutorText/TutorClose message not found.");
	}

	get_mapname(g_szMapName, charsmax(g_szMapName));
	resetMapMetadata();

	register_forward(FM_CmdStart, "fw_CmdStart");
}

public client_putinserver(id) {
	g_bTabPressed[id] = false;
	resetPersonalBest(id);
}

public client_disconnected(id) {
	g_bTabPressed[id] = false;
	resetPersonalBest(id);
}

public kz_sql_initialized() {
	g_bSqlReady = true;
	queryMapMetadata();
}

public kz_sql_data_recv(id) {
	queryPersonalBest(id);
}

public fw_CmdStart(id, uc_handle, seed) {
	if (!is_user_connected(id)) {
		return FMRES_IGNORED;
	}

	if (!g_msgTutorText || !g_msgTutorClose) {
		return FMRES_IGNORED;
	}

	new buttons = get_uc(uc_handle, UC_Buttons);
	new bool:bNowPressed = (buttons & IN_SCORE) != 0;

	if (bNowPressed && !g_bTabPressed[id]) {
		g_bTabPressed[id] = true;
		queryPersonalBest(id);
		ShowTutorTip(id);
	}
	else if (!bNowPressed && g_bTabPressed[id]) {
		g_bTabPressed[id] = false;
		HideTutorTip(id);
	}

	return FMRES_IGNORED;
}

ShowTutorTip(id) {
	new szPro[32], szNub[64], szText[512];

	if (g_UserPb[id][pbHasPro] && g_UserPb[id][pbProTime] > 0.0) {
		formatTimeClock(g_UserPb[id][pbProTime], szPro, charsmax(szPro));
	}
	else {
		copy(szPro, charsmax(szPro), "N/A");
	}

	if (g_UserPb[id][pbHasNub] && g_UserPb[id][pbNubTime] > 0.0) {
		new szNubTime[32];
		formatTimeClock(g_UserPb[id][pbNubTime], szNubTime, charsmax(szNubTime));
		formatex(szNub, charsmax(szNub), "%s [%d CP | %d TP]",
			szNubTime, g_UserPb[id][pbNubCp], g_UserPb[id][pbNubTp]);
	}
	else {
		copy(szNub, charsmax(szNub), "N/A");
	}

	formatex(szText, charsmax(szText), "\
Map: %s | by %s[%s]^n\
Tier: %s(Simen) | %s(Rush)^n\
Type: %s | Length: %s^n^n\
PB(PRO): %s^n\
PB(NUB): %s",
		g_szMapName,
		g_MapMetaInfo[eMapCreator],
		g_MapMetaInfo[eMapCreatorCountry],
		g_MapMetaInfo[eMapTierSimen],
		g_MapMetaInfo[eMapTierRush],
		g_MapMetaInfo[eMapType],
		g_MapMetaInfo[eMapLength],
		szPro,
		szNub);

	message_begin(MSG_ONE_UNRELIABLE, g_msgTutorText, _, id);
	write_string(szText);
	write_byte(0);
	write_short(0);
	write_short(0);
	write_short(TUTOR_COLOR_YELLOW);
	message_end();
}

HideTutorTip(id) {
	message_begin(MSG_ONE_UNRELIABLE, g_msgTutorClose, _, id);
	message_end();
}

queryPersonalBest(id) {
	if (!g_bSqlReady || !is_user_connected(id) || is_user_bot(id)) {
		return;
	}

	if (g_UserPb[id][pbLoading]) {
		return;
	}

	new userId = kz_sql_get_user_uid(id);
	new mapId = kz_sql_get_map_uid();

	if (userId <= 0 || mapId <= 0) {
		return;
	}

	new szQuery[768], szData[1];
	formatex(szQuery, charsmax(szQuery), "\
SELECT \
	(SELECT `time` FROM `kz_records` WHERE `user_id` = %d AND `map_id` = %d AND `weapon` = 6 AND `aa` = 0 AND `is_pro_record` = 1 ORDER BY `time` ASC LIMIT 1),\
	(SELECT `time` FROM `kz_records` WHERE `user_id` = %d AND `map_id` = %d AND `weapon` = 6 AND `aa` = 0 AND `is_pro_record` = 0 ORDER BY `time` ASC LIMIT 1),\
	(SELECT `cp` FROM `kz_records` WHERE `user_id` = %d AND `map_id` = %d AND `weapon` = 6 AND `aa` = 0 AND `is_pro_record` = 0 ORDER BY `time` ASC LIMIT 1),\
	(SELECT `tp` FROM `kz_records` WHERE `user_id` = %d AND `map_id` = %d AND `weapon` = 6 AND `aa` = 0 AND `is_pro_record` = 0 ORDER BY `time` ASC LIMIT 1);",
		userId, mapId,
		userId, mapId,
		userId, mapId,
		userId, mapId);

	g_UserPb[id][pbLoading] = true;
	szData[0] = id;
	SQL_ThreadQuery(kz_sql_get_tuple(), "@onPersonalBestLoaded", szQuery, szData, sizeof szData);
}

queryMapMetadata() {
	if (!g_bSqlReady) {
		return;
	}

	new szQuery[768];
	formatex(szQuery, charsmax(szQuery), "\
SELECT \
HEX(CONVERT(COALESCE(`map_creator`, 'Unknown') USING gbk)),\
HEX(CONVERT(COALESCE(`map_creator_country`, 'Unknown') USING gbk)),\
HEX(CONVERT(COALESCE(`map_tier_simen`, 'Unknown') USING gbk)),\
HEX(CONVERT(COALESCE(`map_tier_rush`, 'Unknown') USING gbk)),\
HEX(CONVERT(COALESCE(`map_type`, 'Unknown') USING gbk)),\
HEX(CONVERT(COALESCE(`map_length`, 'Unknown') USING gbk))\
FROM `kz_maps_metadata` WHERE `map_name` = '%s' LIMIT 1;",
		g_szMapName);

	SQL_ThreadQuery(kz_sql_get_tuple(), "@onMapMetadataLoaded", szQuery);
}

@onMapMetadataLoaded(QueryState, Handle:hQuery, szError[], iError, szData[], iLen, Float:fQueryTime) {
	switch (QueryState) {
		case TQUERY_CONNECT_FAILED, TQUERY_QUERY_FAILED: {
			UTIL_LogToFile(MYSQL_LOG, "ERROR", "onMapMetadataLoaded",
				"[%d] %s (%.2f sec)", iError, szError, fQueryTime);
			SQL_FreeHandle(hQuery);
			return PLUGIN_HANDLED;
		}
	}

	if (SQL_NumResults(hQuery) > 0) {
		new szHexCreator[129], szHexCountry[129], szHexTierSimen[65], szHexTierRush[65], szHexType[65], szHexLength[65];
		SQL_ReadResult(hQuery, 0, szHexCreator, charsmax(szHexCreator));
		SQL_ReadResult(hQuery, 1, szHexCountry, charsmax(szHexCountry));
		SQL_ReadResult(hQuery, 2, szHexTierSimen, charsmax(szHexTierSimen));
		SQL_ReadResult(hQuery, 3, szHexTierRush, charsmax(szHexTierRush));
		SQL_ReadResult(hQuery, 4, szHexType, charsmax(szHexType));
		SQL_ReadResult(hQuery, 5, szHexLength, charsmax(szHexLength));

		decodeHexString(szHexCreator, g_MapMetaInfo[eMapCreator], charsmax(g_MapMetaInfo[eMapCreator]));
		decodeHexString(szHexCountry, g_MapMetaInfo[eMapCreatorCountry], charsmax(g_MapMetaInfo[eMapCreatorCountry]));
		decodeHexString(szHexTierSimen, g_MapMetaInfo[eMapTierSimen], charsmax(g_MapMetaInfo[eMapTierSimen]));
		decodeHexString(szHexTierRush, g_MapMetaInfo[eMapTierRush], charsmax(g_MapMetaInfo[eMapTierRush]));
		decodeHexString(szHexType, g_MapMetaInfo[eMapType], charsmax(g_MapMetaInfo[eMapType]));
		decodeHexString(szHexLength, g_MapMetaInfo[eMapLength], charsmax(g_MapMetaInfo[eMapLength]));

		normalizeField(g_MapMetaInfo[eMapCreator], charsmax(g_MapMetaInfo[eMapCreator]));
		normalizeField(g_MapMetaInfo[eMapCreatorCountry], charsmax(g_MapMetaInfo[eMapCreatorCountry]));
		normalizeField(g_MapMetaInfo[eMapTierSimen], charsmax(g_MapMetaInfo[eMapTierSimen]));
		normalizeField(g_MapMetaInfo[eMapTierRush], charsmax(g_MapMetaInfo[eMapTierRush]));
		normalizeField(g_MapMetaInfo[eMapType], charsmax(g_MapMetaInfo[eMapType]));
		normalizeField(g_MapMetaInfo[eMapLength], charsmax(g_MapMetaInfo[eMapLength]));
	}

	SQL_FreeHandle(hQuery);
	return PLUGIN_HANDLED;
}

@onPersonalBestLoaded(QueryState, Handle:hQuery, szError[], iError, szData[], iLen, Float:fQueryTime) {
	new id = szData[0];
	g_UserPb[id][pbLoading] = false;

	switch (QueryState) {
		case TQUERY_CONNECT_FAILED, TQUERY_QUERY_FAILED: {
			UTIL_LogToFile(MYSQL_LOG, "ERROR", "onPersonalBestLoaded",
				"[%d] %s (%.2f sec)", iError, szError, fQueryTime);
			SQL_FreeHandle(hQuery);
			return PLUGIN_HANDLED;
		}
	}

	g_UserPb[id][pbHasPro] = false;
	g_UserPb[id][pbHasNub] = false;
	g_UserPb[id][pbNubCp] = 0;
	g_UserPb[id][pbNubTp] = 0;
	g_UserPb[id][pbProTime] = 0.0;
	g_UserPb[id][pbNubTime] = 0.0;

	if (SQL_NumResults(hQuery) > 0) {
		if (!SQL_IsNull(hQuery, 0)) {
			g_UserPb[id][pbHasPro] = true;
			g_UserPb[id][pbProTime] = Float:SQL_ReadResult(hQuery, 0);
		}

		if (!SQL_IsNull(hQuery, 1)) {
			g_UserPb[id][pbHasNub] = true;
			g_UserPb[id][pbNubTime] = Float:SQL_ReadResult(hQuery, 1);
			g_UserPb[id][pbNubCp] = SQL_IsNull(hQuery, 2) ? 0 : SQL_ReadResult(hQuery, 2);
			g_UserPb[id][pbNubTp] = SQL_IsNull(hQuery, 3) ? 0 : SQL_ReadResult(hQuery, 3);
		}
	}

	g_UserPb[id][pbLoaded] = true;

	if (is_user_connected(id) && g_bTabPressed[id]) {
		ShowTutorTip(id);
	}

	SQL_FreeHandle(hQuery);
	return PLUGIN_HANDLED;
}

resetMapMetadata() {
	copy(g_MapMetaInfo[eMapCreator], charsmax(g_MapMetaInfo[eMapCreator]), "Unknown");
	copy(g_MapMetaInfo[eMapCreatorCountry], charsmax(g_MapMetaInfo[eMapCreatorCountry]), "Unknown");
	copy(g_MapMetaInfo[eMapTierSimen], charsmax(g_MapMetaInfo[eMapTierSimen]), "Unknown");
	copy(g_MapMetaInfo[eMapTierRush], charsmax(g_MapMetaInfo[eMapTierRush]), "Unknown");
	copy(g_MapMetaInfo[eMapType], charsmax(g_MapMetaInfo[eMapType]), "Unknown");
	copy(g_MapMetaInfo[eMapLength], charsmax(g_MapMetaInfo[eMapLength]), "Unknown");
}

resetPersonalBest(id) {
	g_UserPb[id][pbLoaded] = false;
	g_UserPb[id][pbLoading] = false;
	g_UserPb[id][pbHasPro] = false;
	g_UserPb[id][pbHasNub] = false;
	g_UserPb[id][pbProTime] = 0.0;
	g_UserPb[id][pbNubTime] = 0.0;
	g_UserPb[id][pbNubCp] = 0;
	g_UserPb[id][pbNubTp] = 0;
}

normalizeField(szField[], iLen) {
	trim(szField);

	if (!szField[0]) {
		copy(szField, iLen, "Unknown");
	}
}

decodeHexString(const szHex[], szOut[], outLen) {
	new iHexLen = strlen(szHex);
	new iOut = 0;

	if (iHexLen <= 0) {
		szOut[0] = 0;
		return;
	}

	for (new i = 0; i + 1 < iHexLen && iOut < outLen; i += 2) {
		new hi = hexCharToInt(szHex[i]);
		new lo = hexCharToInt(szHex[i + 1]);

		if (hi < 0 || lo < 0) {
			break;
		}

		szOut[iOut++] = (hi << 4) | lo;
	}

	szOut[iOut] = 0;
}

hexCharToInt(ch) {
	if (ch >= '0' && ch <= '9') {
		return ch - '0';
	}
	if (ch >= 'A' && ch <= 'F') {
		return ch - 'A' + 10;
	}
	if (ch >= 'a' && ch <= 'f') {
		return ch - 'a' + 10;
	}

	return -1;
}

formatTimeClock(Float:fTime, szBuffer[], iLen) {
	new iMin = floatround(fTime / 60.0, floatround_floor);
	new iSec = floatround(fTime - (iMin * 60.0), floatround_floor);
	new iCS = floatround((fTime - (iMin * 60.0 + iSec)) * 100.0, floatround_floor);

	if (iCS < 0) {
		iCS = 0;
	}

	formatex(szBuffer, iLen, "%02d:%02d:%02d", iMin, iSec, iCS);
}
