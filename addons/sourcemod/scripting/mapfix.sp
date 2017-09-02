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
#include <smlib>

#define PLUGIN_VERSION "1.1.1"
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

    SetupTeleports();
}


public OnEntityCreated(entity, const char[] classname)
{
    //Check for the creating of game mode entities and switch fof_sv_currentmode to the correct gamemode
    //This will let you play multiple gamemodes on the same server.
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

public OnMapStart()
{
    FixSlotLimits();
    SetupTeleports();
    FixCvarBounds();

    //I use this for my plugins that use the custom gatling gun weapon_smg1 entity
    PrecacheSound("weapons/gatling/gattling_fire1.wav", true );
    PrecacheSound("weapons/gatling/gattling_fire2.wav", true );
}
public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    SetupTeleports();
}

public FixCvarBounds()
{
    //Some cvars are blocked from being changed in game;  this will remove
    //those bounds so they can be modified like in any other game.

    new Handle:cvar;
    new String:cvars[][] = {
        "fof_sv_ghost_town",
        "fof_sv_maxteams",
        "fof_sv_pickup_maxweight",
        "fof_sv_recoilamount",
        "fof_sv_speedpenalty",
        "fof_sv_teambalance_allowed",
        "fof_sv_viewspring",
        "fof_sv_wcrate_regentime",
        "sv_gravity",
    };

    for(new i=0; i < sizeof(cvars); i++)
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
}

public FixSlotLimits()
{
    //Normally you can only run 12 slot maps with < 16 players And 32 slot maps
    //with > 20 players This is checked with a "func_brush" entity with a
    //"targetname" of "slots_12" and "slots_32".  This function finds these
    //entities and renames them or names an entity so that the map can be
    //played regardless.  MaxClients holds the maxplayers server variable.

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

public RemoveSlots12()
{
    new ent = Entity_FindByName("slots_12", "func_brush");

    if (ent != INVALID_ENT_REFERENCE)
    {
        //slots_12 found
        PrintToServer("[MapFix] remove slots_12");
        Entity_SetName(ent, "blanked");
    }

}

public AddSlots12()
{
    new ent = Entity_Create("func_brush");
    Entity_SetName(ent, "slots_12");
    PrintToServer("[MapFix] add slots_12");
}

public AddSlots32()
{
    new ent = Entity_Create("func_brush");
    Entity_SetName(ent, "slots_32");
    PrintToServer("[MapFix] add slots_32");
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

    }

    //Add an ontouch event for every trigger_teleport
    decl Float:pos1[3], Float:pos2[3];
    while( (ent = FindEntityByClassname(ent, "trigger_teleport")) != INVALID_ENT_REFERENCE)
    {
        SDKHook(ent, SDKHook_StartTouchPost, TriggerTeleportStartTouch);
        GetEntPropString(ent, Prop_Data, "m_target", target, sizeof(target));
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
}
