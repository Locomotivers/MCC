#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#include <smlib>
#include <csgomorecolors>

#pragma newdecls required

#define PLUGIN_VERSION "1.1.1"

#define MCC_MAX_COLOR_LENGTH 32
#define MCC_MAX_CMD_LENGTH 32
#define MCC_MAX_FLAG_LENGTH 8

#define MCC_DEFAULT_COLOR "White"

#define MCC_SETCLIENTMODELCOLOR_SUCCESS 0
#define MCC_SETCLIENTMODELCOLOR_COLORNOTFOUND 1
#define MCC_SETCLIENTMODELCOLOR_COLORNOACCESS 2
#define MCC_SETCLIENTMODELCOLOR_INVALIDCLIENT 3

Handle g_hColorCookie;
ArrayList g_hColorsArray;
KeyValues g_hModelColorsKV;

bool g_bCookiesAreLoaded[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "Model Color Changer",
	author		= "Locomotiver, Ariistuujj", 
	description	= "Change player model colors",
	version		= PLUGIN_VERSION,
	url			= "GFLClan.com"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("mcolorchanger.phrases");
	
	CreateConVar("mcolorchanger_version", PLUGIN_VERSION, "Current version of Model Color Changer", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hColorCookie = RegClientCookie("mcolorchanger_color", "Client's preferred color", CookieAccess_Protected);
	
	RegConsoleCmd("sm_mccmenu", Command_MCCMenu, "Open the menu for changing your model color");
	RegConsoleCmd("sm_mccset", Command_MCCSet, "Change your model color");
	RegAdminCmd("sm_mccsetother", Command_MCCSetOther, ADMFLAG_CHEATS, "Change the model color of the target");
	RegAdminCmd("sm_mccreset", Command_MCCReset, ADMFLAG_CONFIG, "Reset the color config");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnMapStart()
{
	RefreshColors();
}

void RefreshColors()
{
	g_hColorsArray = new ArrayList(MCC_MAX_COLOR_LENGTH);
	
	char sColorsPath[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, sColorsPath, sizeof(sColorsPath), "configs/mcolorchanger/colors.txt");
	
	if (g_hModelColorsKV != null)
		delete g_hModelColorsKV;
	
	g_hModelColorsKV = new KeyValues("ModelColors");
	g_hModelColorsKV.ImportFromFile(sColorsPath);
	
	SMCParser hSMC = new SMCParser();
	
	hSMC.OnEnterSection = SMC_RefreshColors_NewSection;
	
	SMCError eSMCReturn = hSMC.ParseFile(sColorsPath);
	
	if (eSMCReturn != SMCError_Okay)
	{
		char sError[255];
		
		hSMC.GetErrorString(eSMCReturn, sError, sizeof(sError));
		
		if (sError[0] != '\0')
			LogError("%s", sError);
	}
	
	delete hSMC;
	
	SortADTArray(g_hColorsArray, Sort_Ascending, Sort_String);
}

public SMCResult SMC_RefreshColors_NewSection(SMCParser hSMC, const char[] sName, bool bQuotes)
{
	char sRootSection[MCC_MAX_COLOR_LENGTH];
	
	g_hModelColorsKV.GetSectionName(sRootSection, sizeof(sRootSection));
	
	if (!StrEqual(sName, sRootSection, false))
		g_hColorsArray.PushString(sName);
}

public void OnClientConnected(int iClient)
{
	g_bCookiesAreLoaded[iClient] = false;
}

public void OnClientCookiesCached(int iClient)
{
	if (IsValidClient(iClient))
	{
		char sColorCookieValue[MCC_MAX_COLOR_LENGTH];
		
		GetClientCookie(iClient, g_hColorCookie, sColorCookieValue, sizeof(sColorCookieValue));
		
		if (sColorCookieValue[0] == '\0')
			SetClientCookie(iClient, g_hColorCookie, MCC_DEFAULT_COLOR);
		
		g_bCookiesAreLoaded[iClient] = true;
	}
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (!g_bCookiesAreLoaded[iClient] && AreClientCookiesCached(iClient))
		OnClientCookiesCached(iClient);

	if (g_bCookiesAreLoaded[iClient])
		CreateTimer(3.0, Timer_PlayerSpawnDelay, iClient, TIMER_FLAG_NO_MAPCHANGE);
	else if (IsValidClient(iClient))
		CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COOKIESNOTLOADED");
	
	return Plugin_Continue;
}

public Action Timer_PlayerSpawnDelay(Handle hTimer, int iClient)
{
	if (IsValidClient(iClient))
	{
		char sColorCookieValue[MCC_MAX_COLOR_LENGTH];
	
		GetClientCookie(iClient, g_hColorCookie, sColorCookieValue, sizeof(sColorCookieValue));
	
		int iSCMCReturn = SetClientModelColor(iClient, sColorCookieValue);
		
		switch (iSCMCReturn)
		{
			case MCC_SETCLIENTMODELCOLOR_SUCCESS:
				CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_SETCOLOR", sColorCookieValue);
			
			case MCC_SETCLIENTMODELCOLOR_COLORNOTFOUND:
			{
				CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COLORNOTFOUND");
				SetClientCookie(iClient, g_hColorCookie, MCC_DEFAULT_COLOR);
			}

			case MCC_SETCLIENTMODELCOLOR_COLORNOACCESS:
			{
				CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COLORNOACCESS");
				SetClientCookie(iClient, g_hColorCookie, MCC_DEFAULT_COLOR);
			}
		}
	}
}


public Action Command_MCCMenu(int iClient, int iArgs)
{
	char sColorCookieValue[MCC_MAX_COLOR_LENGTH];
	Menu hColorSelectMenu = new Menu(MenuHandler_ColorSelect);

	hColorSelectMenu.SetTitle("%T", "MCC_MENU_COLORSELECT", iClient);
	GetClientCookie(iClient, g_hColorCookie, sColorCookieValue, sizeof(sColorCookieValue));
	
	if (!StrEqual(MCC_DEFAULT_COLOR, sColorCookieValue, false))
		hColorSelectMenu.AddItem(MCC_DEFAULT_COLOR, MCC_DEFAULT_COLOR);
	else
		hColorSelectMenu.AddItem(MCC_DEFAULT_COLOR, MCC_DEFAULT_COLOR, ITEMDRAW_DISABLED);
		
	char sColor[MCC_MAX_COLOR_LENGTH];
	int iColor;
	char sFlag[MCC_MAX_FLAG_LENGTH];
	
	for (int i; i < g_hColorsArray.Length; i++)
	{
		g_hColorsArray.GetString(i, sColor, sizeof(sColor));
		iColor = GetSectionSymbolOfColor(sColor);
		
		if (iColor != -1)
		{
			g_hModelColorsKV.JumpToKeySymbol(iColor);
			
			g_hModelColorsKV.GetString("flag", sFlag, sizeof(sFlag));
			
			g_hModelColorsKV.Rewind();
			
			if (HasPermission(iClient, "b") || HasPermission(iClient, sFlag))
			{
				if (!StrEqual(sColor, sColorCookieValue, false))
					hColorSelectMenu.AddItem(sColor, sColor);
				else
					hColorSelectMenu.AddItem(sColor, sColor, ITEMDRAW_DISABLED);
			}
		}
	}

	hColorSelectMenu.Display(iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int MenuHandler_ColorSelect(Menu hColorSelectMenu, MenuAction eAction, int iClient, int iItem)
{
	switch (eAction)
	{
		case MenuAction_Select:
		{
			char sItem[MCC_MAX_COLOR_LENGTH];
			
			hColorSelectMenu.GetItem(iItem, sItem, sizeof(sItem));
			
			int iSCMCReturn = SetClientModelColor(iClient, sItem);
			
			switch (iSCMCReturn)
			{
				case MCC_SETCLIENTMODELCOLOR_SUCCESS:
				{
					CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_SETCOLOR", sItem);
					SetClientCookie(iClient, g_hColorCookie, sItem);
				}
			}
		}
		case MenuAction_End:
		{
			delete hColorSelectMenu;
		}
	}
}

public Action Command_MCCSet(int iClient, int iArgs)
{	
	if (iArgs != 1)
	{
		char sCommandName[MCC_MAX_CMD_LENGTH];
	
		GetCmdArg(0, sCommandName, sizeof(sCommandName));
		CReplyToCommand(iClient, "%t %t", "MCC_MSG_TAG", "MCC_CMD_MCCSET_USAGE", sCommandName);
		
		return Plugin_Handled;
	}
	
	char sColor[MCC_MAX_COLOR_LENGTH];
	
	GetCmdArg(1, sColor, sizeof(sColor));

	int iSCMCReturn = SetClientModelColor(iClient, sColor);
	
	switch (iSCMCReturn)
	{
		case MCC_SETCLIENTMODELCOLOR_SUCCESS:
		{
			CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_SETCOLOR", sColor);
			SetClientCookie(iClient, g_hColorCookie, sColor);
		}
		
		case MCC_SETCLIENTMODELCOLOR_COLORNOTFOUND:
			CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COLORNOTFOUND");
		
		case MCC_SETCLIENTMODELCOLOR_COLORNOACCESS:
			CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COLORNOACCESS");
	}
	
	return Plugin_Handled;
}

public Action Command_MCCSetOther(int iClient, int iArgs)
{	
	if (iArgs != 2)
	{
		char sCommandName[MCC_MAX_CMD_LENGTH];
	
		GetCmdArg(0, sCommandName, sizeof(sCommandName));
		CReplyToCommand(iClient, "%t %t", "MCC_MSG_TAG", "MCC_CMD_MCCSETOTHER_USAGE", sCommandName);
		
		return Plugin_Handled;
	}
	
	int iTargetCount;
	char sTarget[MAX_NAME_LENGTH];
	int iTargetList[MAXPLAYERS + 1];
	char sTargetName[MAX_NAME_LENGTH];
	bool bTranslateTargetName;
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	iTargetCount = ProcessTargetString(sTarget, iClient, iTargetList, sizeof(sTarget), COMMAND_FILTER_ALIVE, sTargetName, sizeof(sTargetName), bTranslateTargetName);
	
	if (iTargetCount <= 0)
	{
		ReplyToTargetError(iClient, iTargetCount);
		
		return Plugin_Handled;
	}
	
	char sColor[MCC_MAX_COLOR_LENGTH];
	
	GetCmdArg(2, sColor, sizeof(sColor));
	
	int iSCMCReturn;
	
	for (int iTarget; iTarget < iTargetCount; iTarget++)
	{
		iSCMCReturn = SetClientModelColor(iTargetList[iTarget], sColor, false);
	
		switch (iSCMCReturn)
		{
			case MCC_SETCLIENTMODELCOLOR_SUCCESS:
			{
				CPrintToChat(iTargetList[iTarget], "%t %t", "MCC_MSG_TAG", "MCC_MSG_SETCOLOR", sColor);
				LogAction(iClient, iTargetList[iTarget], "\"%L\" set the model color of \"%L\" to %s", iClient, iTargetList[iTarget], sColor);	
			}
			
			case MCC_SETCLIENTMODELCOLOR_COLORNOTFOUND:
			{
				CPrintToChat(iClient, "%t %t", "MCC_MSG_TAG", "MCC_MSG_COLORNOTFOUND");
				
				return Plugin_Handled;
			}
		}
	}
	
	char sActivityTag[16];
	
	Format(sActivityTag, sizeof(sActivityTag), "%t ", "MCC_CMD_TAG");
	
	if (!bTranslateTargetName)
		ShowActivity2(iClient, sActivityTag, "%t", "MCC_CMD_MCCSETOTHER_ACTIVITY", sTargetName, sColor);
	else
		ShowActivity2(iClient, sActivityTag, "%t", "MCC_CMD_MCCSETOTHER_ACTIVITY_ML", sTargetName, sColor);
	
	return Plugin_Handled;
}

public Action Command_MCCReset (int iClient, int iArgs)
{
	RefreshColors();
	CReplyToCommand(iClient, "{GREEN} Successfully reset the color.");
	return Plugin_Handled;
}

int SetClientModelColor(int iClient, const char[] sColor, bool bCheckAccess = true)
{
	if (!IsValidClient(iClient, true, false))
		return MCC_SETCLIENTMODELCOLOR_INVALIDCLIENT;
	
	int iRed = 255;
	int iGreen = 255;
	int iBlue = 255;
	int iAlpha = 255;
	char sFlag[MCC_MAX_FLAG_LENGTH];
	
	if (!StrEqual(MCC_DEFAULT_COLOR, sColor, false))
	{
		int iColor = GetSectionSymbolOfColor(sColor);
		
		if (iColor == -1)
			return MCC_SETCLIENTMODELCOLOR_COLORNOTFOUND;
		
		g_hModelColorsKV.JumpToKeySymbol(iColor);
		
		iRed = g_hModelColorsKV.GetNum("red", iRed);
		iGreen = g_hModelColorsKV.GetNum("green", iGreen);
		iBlue = g_hModelColorsKV.GetNum("blue", iBlue);
		iAlpha = g_hModelColorsKV.GetNum("alpha", iAlpha);
		g_hModelColorsKV.GetString("flag", sFlag, sizeof(sFlag));
		
		g_hModelColorsKV.Rewind();
	}
	
	// if (!IsClientModelColorable(iClient))
	// 	return MCC_SETCLIENTMODELCOLOR_NOTCOLORABLE;
	
	if (bCheckAccess && (!HasPermission(iClient, "b") && !HasPermission(iClient, sFlag)))
		return MCC_SETCLIENTMODELCOLOR_COLORNOACCESS;
		
	SetEntityRenderMode(iClient, RENDER_NORMAL);
	SetEntityRenderColor(iClient, iRed, iGreen, iBlue, iAlpha);
	
	return MCC_SETCLIENTMODELCOLOR_SUCCESS;
}

int GetSectionSymbolOfColor(const char[] sColor)
{
	char sSectionName[MCC_MAX_COLOR_LENGTH];
	int iSectionSymbol = -1;
	
	if (g_hModelColorsKV.GotoFirstSubKey())
	{
		do
		{
			g_hModelColorsKV.GetSectionName(sSectionName, sizeof(sSectionName));
			
			if (StrEqual(sColor, sSectionName, false))
			{
				g_hModelColorsKV.GetSectionSymbol(iSectionSymbol);
				
				break;
			}
		}
		while (g_hModelColorsKV.GotoNextKey());
	}
	
	g_hModelColorsKV.Rewind();
	
	return iSectionSymbol;
}


stock bool IsValidClient(int iClient, bool bAllowBots = false, bool bAllowDead = true)
{
	if (!(1 <= iClient <= MaxClients) || !IsClientInGame(iClient) || (IsFakeClient(iClient) && !bAllowBots) || IsClientSourceTV(iClient) || IsClientReplay(iClient) || (!bAllowDead && !IsPlayerAlive(iClient)))
		return false;
		
	return true;
} 

stock bool HasPermission(int iClient, char[] sFlagString) 
{
	if (StrEqual(sFlagString, "")) 
		return true;
	
	AdminId eAdmin = GetUserAdmin(iClient);
	
	if (eAdmin == INVALID_ADMIN_ID)
		return false;
	
	int iFlags = ReadFlagString(sFlagString);

	if (CheckAccess(eAdmin, "", iFlags, true))
		return true;

	return false;
} 