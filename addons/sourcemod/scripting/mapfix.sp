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

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.1.0"
#define PLUGIN_NAME "[FoF] [HACK] [BADCODES] mapfix"

//#define DEBUG				true

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "A hacky fix to re-add some Source engine features removed from Fistful of Frags.",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_mapfix_fof"
};


new Handle:g_CachedTargetTrie = INVALID_HANDLE;

public OnPluginStart()
{
    CreateConVar("fof_mapfix_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    HookEvent("round_start", Event_RoundStart);

    RegAdminCmd("sm_teleport", Command_Test, ADMFLAG_VOTE, "[ADMIN] test");
    SetupTeleports();

}

public Action:Command_Test(client, args)
{
#if defined DEBUG
    PrintToServer("test3");
#endif
      

    return Plugin_Handled;
}

public OnAutoConfigsBuffered()
{
#if defined DEBUG
    PrintToServer("Hit OnAutoConfigsBuffered");
#endif
}

public OnEntityCreated(entity, const char[] classname)
{
#if defined DEBUG
    //PrintToServer("Hit OnEntityCreated (%d) -> %s", entity, classname);
#endif
    if(StrEqual(classname, "fof_teamplay"))
    {
        PrintToServer("Fix fof_teamplay spawn");
        ServerCommand("fof_sv_currentmode 2");
    }else if(StrEqual(classname, "fof_breakbad"))
    {
        PrintToServer("Fix fof_breakbad spawn");
        ServerCommand("fof_sv_currentmode 3");
    }else if(StrEqual(classname, "fof_elimination"))
    {
        PrintToServer("Fix fof_elimination spawn");
        ServerCommand("fof_sv_currentmode 4");
    }
}

public OnEntityDestroyed(entity)
{
#if defined DEBUG
    //PrintToServer("Hit OnEntityDestroyed (%d)", entity);
#endif
}

public Action:OnGetGameDescription(char gameDesc[64])
{
#if defined DEBUG
    PrintToServer("Hit OnGetGameDescription -> %s", gameDesc);
#endif
    return Plugin_Continue;
}

public Action:OnLevelInit(const char[] mapName, char mapEntities[2097152])
{
#if defined DEBUG
    PrintToServer("Hit OnLevelInit -> %s", mapName);
#endif
    return Plugin_Continue;
}

public OnMapStart()
{
#if defined DEBUG
    PrintToServer("Hit OnMapStart");
#endif

    SetupTeleports();

    PrecacheSound("weapons/gatling/gattling_fire1.wav", true );
    PrecacheSound("weapons/gatling/gattling_fire2.wav", true );
}
public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
#if defined DEBUG
    PrintToServer("Hit round_start");
#endif

    SetupTeleports();
}

public SetupTeleports()
{
    new ent = -1;
    decl String:target[50];

    //Cache info_teleport_destination entities
    if(g_CachedTargetTrie != INVALID_HANDLE) CloseHandle(g_CachedTargetTrie);
    g_CachedTargetTrie = CreateTrie();

    while( (ent = FindEntityByClassname(ent, "info_teleport_destination")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(ent, Prop_Data, "m_iName", target, sizeof(target));
        SetTrieValue(g_CachedTargetTrie, target, ent);

#if defined DEBUG
        PrintToServer("info_teleport_destination(%d) -> %s", ent, target);
#endif
    }

    //Add an ontouch event for every trigger_teleport
    decl Float:pos1[3], Float:pos2[3];
    while( (ent = FindEntityByClassname(ent, "trigger_teleport")) != INVALID_ENT_REFERENCE)
    {
        SDKHook(ent, SDKHook_StartTouchPost, TriggerTeleportStartTouch);

        GetEntPropString(ent, Prop_Data, "m_target", target, sizeof(target));
#if defined DEBUG
        PrintToServer("trigger_teleport(%d) -> %s", ent, target);
#endif
        //DispatchKeyValue(ent, "classname", "man_butt");
    }

}

public Action:TriggerTeleportStartTouch(trigger_teleport, client)
{
    //Only work for clients
    if ( !(1 <= client && client <= MaxClients) ) return Plugin_Continue;

    //Get cached info_teleport_destination but exit if it's not found
    decl String:targetname[50];
    new info_teleport_destination;
    GetEntPropString(trigger_teleport, Prop_Data, "m_target", targetname, sizeof(targetname));

    if( !GetTrieValue(g_CachedTargetTrie, targetname, info_teleport_destination)) return Plugin_Continue;

    //Pass this off to a timer as the teleport won't work on the same game frame
    new Handle:data;
    CreateDataTimer(0.0, DelayTeleport, data);
    WritePackCell(data, GetClientUserId(client));
    WritePackCell(data, info_teleport_destination);

#if defined DEBUG
    PrintToServer("teleport %d to %s (%d)", client, targetname, info_teleport_destination);
#endif

    return Plugin_Continue;
}

public Action:DelayTeleport(Handle:Timer, Handle:data)
{
    ResetPack(data);
    new client = GetClientOfUserId(ReadPackCell(data));
    new info_teleport_destination = ReadPackCell(data);

    //Exit if client is no longer in game
    if (client <= 0) return;

    decl Float:pos[3], Float:ang[3];
    GetEntPropVector(info_teleport_destination, Prop_Send, "m_vecOrigin", pos);
    GetEntPropVector(info_teleport_destination, Prop_Data, "m_angAbsRotation", ang);

    SetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", pos);
    SetEntPropVector(client, Prop_Data, "m_angAbsRotation", ang);
#if defined DEBUG
    PrintToServer("hit DelayTeleport (%d) %f %f %f", client, pos[0], pos[1], pos[2]);
#endif
}
