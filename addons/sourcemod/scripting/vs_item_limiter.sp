#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>


public Plugin myinfo = {
	name        = "VsItemLimiter",
	author      = "Confogl Team",
	description = "The plugin limits the number of items that can be on the map",
	version     = "build0000",
	url         = "https://github.com/TouchMe-Inc/l4d2_vs_item_limiter/"
}


/*
 * Weapon ids.
 */
#define WEPID_MOLOTOV 13
#define WEPID_PIPE_BOMB 14
#define WEPID_PAIN_PILLS 15
#define WEPID_ADRENALINE 23
#define WEPID_VOMITJAR 25


enum
{
	ITEMID_PAIN_PILLS = 0,
	ITEMID_ADRENALINE,
	ITEMID_PIPE_BOMB,
	ITEMID_MOLOTOV,
	ITEMID_VOMIT_JAR,
	ITEMID_SIZE
};

enum
{
	ITEMNAME_SHORT = 0,
	ITEMNAME_MODEL,
	ITEMNAME_SIZE
};

enum struct ItemTracking
{
	int entity;
	float origin[3];
	float angle[3];
}

char g_sItemNames[ITEMID_SIZE][ITEMNAME_SIZE][] =
{
	{
		"pain_pills",
		"painpills",
	},
	{
		"adrenaline",
		"adrenaline"
	},
	{
		"pipe_bomb",
		"pipebomb"
	},
	{
		"molotov",
		"molotov"
	},
	{
		"vomitjar",
		"bile_flask"
	}
};


int g_iItemLimits[ITEMID_SIZE] = {0, ...}; /**< Current item limits array */

ConVar
	g_cvItemTracking = null,
	g_cvItemLimits[ITEMID_SIZE] = {null, ...} // CVAR Handle Array for item limits
;

Handle g_hItems[ITEMID_SIZE] = {null, ...}; // ADT Array Handle for actual item spawns

Handle g_hItemClassList = null;


public void OnPluginStart()
{
	// Create name translation trie.
	FillItemClassList(g_hItemClassList = CreateTrie());

	g_cvItemTracking = CreateConVar("sm_item_tracking", "0", "Keep item spawns the same on both rounds", _, true, 0.0, true, 1.0);

	// Create itemlimit cvars.
	char sConVarName[64], sConVarDescription[256];

	for (int iItemId = 0; iItemId < ITEMID_SIZE; iItemId ++)
	{
		FormatEx(sConVarName, sizeof(sConVarName), "sm_item_%s_limit", g_sItemNames[iItemId][ITEMNAME_SHORT]);
		FormatEx(sConVarDescription, sizeof(sConVarDescription), "Limits the number of %s on each map. -1: no limit; >=0: limit to cvar value", g_sItemNames[iItemId][ITEMNAME_SHORT]);

		g_cvItemLimits[iItemId] = CreateConVar(sConVarName, "-1", sConVarDescription);
	}

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	// Create item spawns array.
	for (int iItemId = 0; iItemId < ITEMID_SIZE; iItemId ++) {
		g_hItems[iItemId] = CreateArray(sizeof(ItemTracking));
	}
}

void FillItemClassList(Handle hItemList)
{
	char szClassName[64];

	for (int i = 0; i < ITEMID_SIZE; i ++)
	{
		FormatEx(szClassName, sizeof(szClassName), "weapon_%s", g_sItemNames[i][ITEMNAME_SHORT]);
		SetTrieValue(hItemList, szClassName, i);

		FormatEx(szClassName, sizeof(szClassName), "weapon_%s_spawn", g_sItemNames[i][ITEMNAME_SHORT]);
		SetTrieValue(hItemList, szClassName, i);
	}
}

void Event_RoundStart(Event event, const char[] sEventName, bool bDontBroadcast) {
	CreateTimer(1.0, Timer_ItemLimite, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_ItemLimite(Handle hTimer)
{
	if (InSecondHalfOfRound())
	{
		if (GetConVarBool(g_cvItemTracking))
		{
			RestoreItems();
		}

		else
		{
			FindItems();
			RemoveExcessItems();
		}
	}

	else
	{
		for (int i = 0; i < ITEMID_SIZE; i++)
		{
			ClearArray(g_hItems[i]);
			g_iItemLimits[i] = GetConVarInt(g_cvItemLimits[i]);
		}

		FindItems();
		RemoveExcessItems();
	}

	return Plugin_Stop;
}

void FindItems()
{
	ItemTracking item;

	int iEntityCount = GetEntityCount();

	for (int iEnt = (MaxClients + 1); iEnt <= iEntityCount; iEnt ++)
	{
		if (!IsValidEdict(iEnt)) {
			continue;
		}

		int iIndex = GetItemIdFromEntity(iEnt);

		if (iIndex == -1) {
			continue;
		}
		
		item.entity = iEnt;
		GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", item.origin);
		GetEntPropVector(iEnt, Prop_Send, "m_angRotation", item.angle);

		PushArrayArray(g_hItems[iIndex], item, sizeof(item));
	}
}

void RemoveExcessItems()
{
	ItemTracking item;

	for (int iIndex = 0; iIndex < ITEMID_SIZE; iIndex++)
	{
		if (g_iItemLimits[iIndex] < 0) {
			continue;
		}

		while (GetArraySize(g_hItems[iIndex]) > g_iItemLimits[iIndex])
		{
			int iItemIndex = GetRandomInt(0, (GetArraySize(g_hItems[iIndex]) - 1));

			GetArrayArray(g_hItems[iIndex], iItemIndex, item, sizeof(item));

			if (IsValidEdict(item.entity)) {
				RemoveEntity(item.entity);
			}

			RemoveFromArray(g_hItems[iIndex], iItemIndex);
		}
	}
}

void RestoreItems()
{
	int iEntityCount = GetEntityCount();

	for (int iEnt = (MaxClients + 1); iEnt <= iEntityCount; iEnt ++)
	{
		if (!IsValidEdict(iEnt)) {
			continue;
		}

		int iIndex = GetItemIdFromEntity(iEnt);

		if (iIndex >= 0) {
			RemoveEntity(iEnt);
		}
	}

	ItemTracking item;

	char sModelname[PLATFORM_MAX_PATH];

	for (int iItemId = 0; iItemId < ITEMID_SIZE; iItemId ++)
	{
		FormatEx(sModelname, sizeof(sModelname), "models/w_models/weapons/w_eq_%s.mdl", g_sItemNames[iItemId][ITEMNAME_MODEL]);

		int iArraySize = GetArraySize(g_hItems[iItemId]);
		int iWeaponId = GetWeaponIdFromItemId(iItemId);

		for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
		{
			GetArrayArray(g_hItems[iItemId], iIndex, item, sizeof(item));

			CreateItem(iWeaponId, sModelname, item.origin, item.angle);
		}
	}
}

int CreateItem(int iWeaponId, const char[] sModelName, float vOrigin[3], float vAngle[3])
{
	int iItem = CreateEntityByName("weapon_spawn");

	if (iItem == -1) {
		return -1;
	}

	SetEntProp(iItem, Prop_Send, "m_weaponID", iWeaponId);
	SetEntityModel(iItem, sModelName);
	DispatchKeyValue(iItem, "count", "1");
	TeleportEntity(iItem, vOrigin, vAngle, NULL_VECTOR);
	DispatchSpawn(iItem);
	SetEntityMoveType(iItem, MOVETYPE_NONE);

	return iItem;
}

int GetItemIdFromEntity(int entity)
{
	char classname[64]; GetEdictClassname(entity, classname, sizeof(classname));

	int iIndex;

	if (GetTrieValue(g_hItemClassList, classname, iIndex)) {
		return iIndex;
	}

	if (strcmp(classname, "weapon_spawn") == 0 || strcmp(classname, "weapon_item_spawn") == 0) {
		return GetItemIdFromWeaponId(GetEntProp(entity, Prop_Send, "m_weaponID"));
	}

	return -1;
}

int GetWeaponIdFromItemId(int iItemId)
{
	switch (iItemId)
	{
		case ITEMID_PAIN_PILLS: return WEPID_PAIN_PILLS;
		case ITEMID_ADRENALINE: return WEPID_ADRENALINE;
		case ITEMID_PIPE_BOMB: return WEPID_PIPE_BOMB;
		case ITEMID_MOLOTOV: return WEPID_MOLOTOV;
		case ITEMID_VOMIT_JAR: return WEPID_VOMITJAR;
	}

	return -1;
}

int GetItemIdFromWeaponId(int iWeaponId)
{
	switch (iWeaponId)
	{
		case WEPID_VOMITJAR: return ITEMID_VOMIT_JAR;
		case WEPID_PIPE_BOMB: return ITEMID_PIPE_BOMB;
		case WEPID_MOLOTOV: return ITEMID_MOLOTOV;
		case WEPID_PAIN_PILLS: return ITEMID_PAIN_PILLS;
		case WEPID_ADRENALINE: return ITEMID_ADRENALINE;
	}

	return -1;
}

bool InSecondHalfOfRound() {
	return view_as<bool>(GameRules_GetProp("m_bInSecondHalfOfRound"));
}
