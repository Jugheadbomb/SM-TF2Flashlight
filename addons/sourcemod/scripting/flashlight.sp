#include <sourcemod>
#include <clientprefs>
#include <sdkhooks>
#include <tf2_stocks>

#pragma semicolon 1
#pragma newdecls required

#define TF_MAXPLAYERS 33

ConVar g_cvWidth;
ConVar g_cvLength;

ConVar g_cvToggleSound;
char g_sToggleSound[PLATFORM_MAX_PATH];

Cookie g_hCookie;

enum struct Player
{
	bool bFlashlight;
	int iDynamicEnt;
	int iSpotlightEnt;
}

Player g_Player[TF_MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[TF2] Flashlight",
	author = "Jughead",
	description = "Allows toggling flashlight through +attack3 button",
	version = "1.0",
	url = "https://steamcommunity.com/profiles/76561198241665788"
};

public void OnPluginStart()
{
	g_hCookie = new Cookie("tf2_flashlight", "", CookieAccess_Private);
	RegConsoleCmd("sm_flashlight", Command_Toggle, "Toggle flashlight on/off");

	g_cvWidth = CreateConVar("sm_flashlight_width", "512", "Flashlight width");
	g_cvLength = CreateConVar("sm_flashlight_length", "1024", "Flashlight length");
	g_cvToggleSound = CreateConVar("sm_flashlight_sound", "flashlight/flashlight.wav", "Flashlight toggle sound");
	g_cvToggleSound.AddChangeHook(ToggleSound_Changed);

	AutoExecConfig(true);

	HookEvent("player_spawn", Event_KillFlashlight);
	HookEvent("player_team", Event_KillFlashlight);
	HookEvent("player_death", Event_KillFlashlight);
}

public void ToggleSound_Changed(ConVar convar, const char[] sOldValue, const char[] sNewValue)
{
	OnConfigsExecuted();
}

public void OnConfigsExecuted()
{
	g_cvToggleSound.GetString(g_sToggleSound, sizeof(g_sToggleSound));

	// Might be late but uhh...
	if (g_sToggleSound[0])
		PrecacheSound(g_sToggleSound);
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			Flashlight_Toggle(i, false);
}

public void Event_KillFlashlight(Event hEvent, const char[] cName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	Flashlight_Toggle(iClient, false);
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (StrEqual(sClassname, "spotlight_end") || StrEqual(sClassname, "beam"))
		SDKHook(iEntity, SDKHook_SetTransmit, Flashlight_SpotlightTransmit);
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!Flashlight_GetCookie(iClient))
		return Plugin_Continue;

	int iOldButtons = GetEntProp(iClient, Prop_Data, "m_nOldButtons");
	if (!(iOldButtons & IN_ATTACK3) && (iButtons & IN_ATTACK3))
		Flashlight_Toggle(iClient, !g_Player[iClient].bFlashlight, true);

	return Plugin_Continue;
}

public Action Command_Toggle(int iClient, int iArgs)
{
	if (iClient == 0)
		return Plugin_Handled;

	bool bEnabled = Flashlight_GetCookie(iClient);

	if (IsPlayerAlive(iClient))
		Flashlight_Toggle(iClient, !bEnabled, true);

	Flashlight_SetCookie(iClient, !bEnabled);
	PrintToChat(iClient, "\x07%s[SM] Flashlight %sabled", bEnabled ? "E17100" : "E19F00", bEnabled ? "dis" : "en");
	return Plugin_Handled;
}

void Flashlight_Toggle(int iClient, bool bState, bool bSound = false)
{
	g_Player[iClient].bFlashlight = bState;
	if (bSound && g_sToggleSound[0])
		EmitSoundToClient(iClient, g_sToggleSound);
		//EmitSoundToAll(g_sToggleSound, iClient, SNDCHAN_STATIC, SNDLEVEL_DRYER);

	int iEntity;
	if (bState)
	{
		float flEyePos[3];
		GetClientEyePosition(iClient, flEyePos);

		iEntity = CreateEntityByName("light_dynamic");
		DispatchKeyValueFloat(iEntity, "spotlight_radius", g_cvWidth.FloatValue);
		DispatchKeyValueFloat(iEntity, "distance", g_cvLength.FloatValue);
		DispatchKeyValue(iEntity, "_inner_cone", "41");
		DispatchKeyValue(iEntity, "_cone", "41");
		DispatchSpawn(iEntity);
		ActivateEntity(iEntity);

		SetVariantString("!activator");
		AcceptEntityInput(iEntity, "SetParent", iClient);
		AcceptEntityInput(iEntity, "TurnOn");
		TeleportEntity(iEntity, flEyePos, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("OnUser1 !self:Kill::0.1:1");
		AcceptEntityInput(iEntity, "AddOutput");

		g_Player[iClient].iDynamicEnt = EntIndexToEntRef(iEntity);
		SDKHook(iEntity, SDKHook_SetTransmit, Flashlight_DynamicTransmit);

		iEntity = CreateEntityByName("point_spotlight");
		DispatchKeyValueFloat(iEntity, "spotlightwidth", g_cvWidth.FloatValue <= 102.3 ? g_cvWidth.FloatValue : 102.3); // 102.3 is max width for spotlight
		DispatchKeyValueFloat(iEntity, "spotlightlength", g_cvLength.FloatValue);
		DispatchSpawn(iEntity);
		ActivateEntity(iEntity);

		SetVariantString("!activator");
		AcceptEntityInput(iEntity, "SetParent", iClient);
		AcceptEntityInput(iEntity, "LightOn");
		TeleportEntity(iEntity, flEyePos, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("OnUser1 !self:Kill::0.1:1");
		AcceptEntityInput(iEntity, "AddOutput");

		g_Player[iClient].iSpotlightEnt = EntIndexToEntRef(iEntity);

		SDKHook(iClient, SDKHook_PreThink, Flashlight_Think);
	}
	else
	{
		iEntity = EntRefToEntIndex(g_Player[iClient].iDynamicEnt);
		if (iEntity > MaxClients)
		{
			AcceptEntityInput(iEntity, "TurnOff");
			AcceptEntityInput(iEntity, "FireUser1");
		}

		iEntity = EntRefToEntIndex(g_Player[iClient].iSpotlightEnt);
		if (iEntity > MaxClients) 
		{
			AcceptEntityInput(iEntity, "LightOff");
			AcceptEntityInput(iEntity, "FireUser1");
		}

		SDKUnhook(iClient, SDKHook_PreThink, Flashlight_Think);
	}
}

public Action Flashlight_DynamicTransmit(int iEntity, int iOther)
{
	// Transmit only to owner
	if (EntRefToEntIndex(g_Player[iOther].iDynamicEnt) != iEntity)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action Flashlight_SpotlightTransmit(int iEntity, int iOther)
{
	// Get initial spotlight entity
	int iSpotlight = GetEntPropEnt(iEntity, Prop_Data, "m_hOwnerEntity");
	if (iSpotlight == -1)
		return Plugin_Continue;

	// Find owner of initial spotlight entity
	int iOwner = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (EntRefToEntIndex(g_Player[i].iSpotlightEnt) == iSpotlight)
		{
			iOwner = i;
			break;
		}
	}

	if (iOwner == -1)
		return Plugin_Continue;

	if (TF2_IsPlayerInCondition(iOwner, TFCond_Cloaked))
		return Plugin_Handled;

	if (iOwner == iOther)
	{
		if (!GetEntProp(iOwner, Prop_Send, "m_nForceTauntCam") || !GetEntProp(iOwner, Prop_Send, "m_iObserverMode"))
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

// Used to fix angles of flashlight
public void Flashlight_Think(int iClient)
{
	int iEntity = EntRefToEntIndex(g_Player[iClient].iDynamicEnt);
	if (iEntity > MaxClients)
		TeleportEntity(iEntity, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 0.0 }), NULL_VECTOR);

	iEntity = EntRefToEntIndex(g_Player[iClient].iSpotlightEnt);
	if (iEntity > MaxClients)
	{
		float flEyeAng[3], flAbsAng[3];
		GetClientEyeAngles(iClient, flEyeAng);
		GetClientAbsAngles(iClient, flAbsAng);
		SubtractVectors(flEyeAng, flAbsAng, flEyeAng);
		TeleportEntity(iEntity, NULL_VECTOR, flEyeAng, NULL_VECTOR);
	}
}

bool Flashlight_GetCookie(int iClient)
{
	char sValue[8];
	g_hCookie.Get(iClient, sValue, sizeof(sValue));
	if (sValue[0] && !StringToInt(sValue))
		return false;

	return true;
}

void Flashlight_SetCookie(int iClient, bool bState)
{
	char sValue[8];
	IntToString(view_as<int>(bState), sValue, sizeof(sValue));
	g_hCookie.Set(iClient, sValue);
}