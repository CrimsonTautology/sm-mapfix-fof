/**
 * vim: set ts=4 :
 * =============================================================================
 * mapfix_fof
 * A hacky fix to re-add some Source engine features removed from Fistful of Frags
 * Use this at your own risk.
 *
 * Copyright 2015 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#define PLUGIN_VERSION "1.10.0"
#define PLUGIN_NAME "[FoF] [HACK] [BADCODES] mapfix"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "A hacky fix to re-add some Source engine features removed from Fistful of Frags.",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm-mapfix-fof"
};


Handle g_CachedTargetTrie = INVALID_HANDLE;
Handle g_Cvar_Timelimit = INVALID_HANDLE;
Handle g_Cvar_BotSlotpct = INVALID_HANDLE;

bool g_AutoFlipTimelimit = true;
bool g_AutoFlipBotSlotpct = true;

public void OnPluginStart()
{
    CreateConVar(
            "fof_mapfix_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY |
            FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    HookEvent("round_start", Event_RoundStart);

    g_Cvar_Timelimit = FindConVar("mp_timelimit");
    HookConVarChange(g_Cvar_Timelimit, OnTimelimitChanged);

    g_Cvar_BotSlotpct = FindConVar("fof_sv_bot_slotpct");
    HookConVarChange(g_Cvar_BotSlotpct, OnBotSlotpctChanged);

    SetupTeleports();
}


public void OnEntityCreated(int entity, const char[] classname)
{
    // check for the creating of game mode entities and switch
    // fof_sv_currentmode to the correct gamemode.  This will let you play
    // multiple gamemodes on the same server.
    if(StrEqual(classname, "fof_teamplay"))
    {
        PrintToServer("[MapFix] change mode for fof_teamplay spawn");
        ServerCommand("fof_sv_currentmode 2");
    }else if(StrEqual(classname, "fof_breakbad"))
    {
        PrintToServer("[MapFix] change mode for fof_breakbad spawn");
        ServerCommand("fof_sv_currentmode 3");
    }else if(StrEqual(classname, "fof_elimination"))
    {
        PrintToServer("[MapFix] change mode for fof_elimination spawn");
        ServerCommand("fof_sv_currentmode 4");
    }

}

public void OnMapStart()
{
    FixSlotLimits();
    SetupTeleports();
    FixCvarBounds();

    // I use this for my plugins that use the custom gatling gun weapon_smg1
    // entity
    PrecacheSound("weapons/gatling/gattling_fire1.wav", true );
    PrecacheSound("weapons/gatling/gattling_fire2.wav", true );

    // reset mp_timelimit and fof_sv_bot_slotpct autoflip checker
    g_AutoFlipTimelimit = true;
    g_AutoFlipBotSlotpct = true;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    SetupTeleports();
}

public void OnTimelimitChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    // if in Team Shootout FoF no longer lets you have a mp_timelimit greater
    // than 20;  this will attempt to fix that.

    // skip if we already did the autoflip
    if (!g_AutoFlipTimelimit) return;

    if (StrEqual(newValue, "20")) {
        PrintToServer("[MapFix] prevent auto change to mp_timelimit; reset to \"%s\"", oldValue);
        SetConVarString(convar, oldValue);
        g_AutoFlipTimelimit = false;
    }

}

public void OnBotSlotpctChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    // prevent bots from being turned on

    // skip if we already did the autoflip
    if (!g_AutoFlipBotSlotpct) return;

    if (StrEqual(newValue, "0.300000")) {
        PrintToServer("[MapFix] prevent auto change to fof_sv_bot_slotpct; reset to \"%s\"", oldValue);
        SetConVarString(convar, oldValue);
        g_AutoFlipBotSlotpct = false;
    }

}

public void FixCvarBounds()
{
    // some cvars are blocked from being changed in game;  this will remove
    // those bounds so they can be modified like in any other game.

    Handle cvar;
    char cvars[][] = {
        "fof_sv_ghost_town",
        "fof_sv_pickup_maxweight",
        "fof_sv_teambalance_allowed",
        "fof_sv_wcrate_regentime",
        "mp_timelimit",
    };

    for(int i=0; i < sizeof(cvars); i++)
    {
        cvar = FindConVar(cvars[i]);

        if (cvar != INVALID_HANDLE)
        {
            SetConVarBounds(cvar, ConVarBound_Upper, false);
            SetConVarBounds(cvar, ConVarBound_Lower, false);
            PrintToServer("[MapFix] remove bounds on \"%s\"", cvars[i]);
            CloseHandle(cvar);

        } else {
            PrintToServer("[MapFix] Warning: could not find cvar \"%s\"", cvars[i]);
        }
    }

    // block cvars from changing

    // block class system
    cvar = FindConVar("fof_sv_tp_classes");
    SetConVarBounds(cvar, ConVarBound_Upper, true, 0.0);
    SetConVarBounds(cvar, ConVarBound_Lower, true, 0.0);

    // block forced autobalance
    cvar = FindConVar("fof_sv_teambalance_allowed");
    SetConVarBounds(cvar, ConVarBound_Upper, true, 0.0);
    SetConVarBounds(cvar, ConVarBound_Lower, true, 0.0);

}

public void FixSlotLimits()
{
    // normally you can only run 12 slot maps with < 16 players And 32 slot
    // maps with > 20 players This is checked with a "func_brush" entity with a
    // "targetname" of "slots_12" and "slots_32".  This function finds these
    // entities and renames them or names an entity so that the map can be
    // played regardless.  MaxClients holds the maxplayers server variable.

    if (MaxClients < 16)
    {
        AddSlots12();
    } else if (MaxClients >= 16 && MaxClients <= 20)
    {
        RemoveSlots12();
    } else if (MaxClients > 20)
    {
        RemoveSlots12();
        AddSlots32();
    }
}

public void RemoveSlots12()
{
    int ent = Entity_FindByName("slots_12", "func_brush");

    if (ent != INVALID_ENT_REFERENCE)
    {
        // slots_12 found
        PrintToServer("[MapFix] remove slots_12");
        Entity_SetName(ent, "blanked");
    }

}

public void AddSlots12()
{
    int ent = Entity_Create("func_brush");
    Entity_SetName(ent, "slots_12");
    PrintToServer("[MapFix] add slots_12");
}

public void AddSlots32()
{
    int ent = Entity_Create("func_brush");
    Entity_SetName(ent, "slots_32");
    PrintToServer("[MapFix] add slots_32");
}

public void SetupTeleports()
{
    int ent = -1;
    char target[50];

    // cache info_teleport_destination entities
    if(g_CachedTargetTrie != INVALID_HANDLE) CloseHandle(g_CachedTargetTrie);
    g_CachedTargetTrie = CreateTrie();

    while( (ent = FindEntityByClassname(ent, "info_teleport_destination")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(ent, Prop_Data, "m_iName", target, sizeof(target));
        SetTrieValue(g_CachedTargetTrie, target, ent);

    }

    // add an ontouch event for every trigger_teleport
    while( (ent = FindEntityByClassname(ent, "trigger_teleport")) != INVALID_ENT_REFERENCE)
    {
        SDKHook(ent, SDKHook_StartTouchPost, TriggerTeleportStartTouch);
        GetEntPropString(ent, Prop_Data, "m_target", target, sizeof(target));
    }

}

public Action TriggerTeleportStartTouch(int trigger_teleport, int client)
{
    // only work for clients
    if ( !(1 <= client && client <= MaxClients) ) return Plugin_Continue;

    // get cached info_teleport_destination but exit if it's not found
    char targetname[50];
    int info_teleport_destination;
    GetEntPropString(trigger_teleport, Prop_Data, "m_target", targetname, sizeof(targetname));

    if( !GetTrieValue(g_CachedTargetTrie, targetname, info_teleport_destination)) return Plugin_Continue;

    // pass this off to a timer as the teleport won't work on the same game frame
    Handle data;
    CreateDataTimer(0.0, DelayTeleport, data);
    WritePackCell(data, GetClientUserId(client));
    WritePackCell(data, info_teleport_destination);

    return Plugin_Continue;
}

public Action DelayTeleport(Handle Timer, Handle data)
{
    ResetPack(data);
    int client = GetClientOfUserId(ReadPackCell(data));
    int info_teleport_destination = ReadPackCell(data);

    // exit if client is no longer in game
    if (client <= 0) return;

    float pos[3], ang[3];
    GetEntPropVector(info_teleport_destination, Prop_Send, "m_vecOrigin", pos);
    GetEntPropVector(info_teleport_destination, Prop_Data, "m_angAbsRotation", ang);

    SetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", pos);
    SetEntPropVector(client, Prop_Data, "m_angAbsRotation", ang);
}
