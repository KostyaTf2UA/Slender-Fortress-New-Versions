#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "axle"
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#pragma newdecls required

#define MODEL_NPC "models/bots/headless_hatman.mdl"
#define ANIM_MOVE 50
#define ANIM_IDLE 37
#define ANIM_AIR  50

Handle g_hMyNextBotPointer;
Handle g_hGetLocomotionInterface;
Handle g_hGetBodyInterface;

Handle g_hGetGroundNormal;
Handle g_hRun;
Handle g_hApproach;
Handle g_hFaceTowards;
Handle g_hResetSequence;
Handle g_hGetStepHeight;
Handle g_hGetGravity;
Handle g_hStudioFrameAdvance;
Handle g_hShouldCollideWith;

Handle g_hGetSolidMask;
Handle g_hGetHullWidth;
Handle g_hGetStandHullHeight;
Handle g_hGetHullMins;
Handle g_hGetHullMaxs;
Handle g_hGetHullHeight;
Handle g_hGetCrouchHullHeight;
Handle g_hGetCollisionGroup;

Handle g_hGetGroundSpeed;
Handle g_hGetVectors;
Handle g_hGetGroundMotionVector;
Handle g_hGetMaxAcceleration;

Handle g_hLookupPoseParameter;
Handle g_hSetPoseParameter;
//Handle g_hGetPoseParameter;

//NPC Formation like TFBots!
//Disgusting
float vecGoal[3];

int g_m_bResolveCollisionsOffset;
int g_studioHdrOffset;

ArrayList gBots;

public Plugin myinfo = 
{
	name = "[TF2] Linux Pathing Tests", 
	author = PLUGIN_AUTHOR, 
	description = "A plugin to test Valve's Pathfollowing system w/o an extension", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart()
{
	RegAdminCmd("sm_npc", test, ADMFLAG_ROOT);
	RegAdminCmd("sm_npcgoal", test2, ADMFLAG_ROOT);
	gBots = new ArrayList();
	Handle hConf = LoadGameConfigFile("tfnextbot");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseAnimating::StudioFrameAdvance");
	if ((g_hStudioFrameAdvance = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create SDKCall for CBaseAnimating::StudioFrameAdvance offset!");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::ResetSequence");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_hResetSequence = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create SDKCall for CBaseAnimating::ResetSequence signature!");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseEntity::MyNextBotPointer");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_hMyNextBotPointer = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create SDKCall for CBaseEntity::MyNextBotPointer offset!");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "INextBot::GetLocomotionInterface");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_hGetLocomotionInterface = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for INextBot::GetLocomotionInterface!");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "INextBot::GetBodyInterface");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_hGetBodyInterface = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for INextBot::GetBodyInterface!");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "NextBotGroundLocomotion::Run");
	if ((g_hRun = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for NextBotGroundLocomotion::Run!");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "NextBotGroundLocomotion::Approach");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	if ((g_hApproach = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for NextBotGroundLocomotion::Approach!");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "NextBotGroundLocomotion::FaceTowards");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	if ((g_hFaceTowards = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for NextBotGroundLocomotion::FaceTowards!");
	
	
	//https://github.com/Andersso/SM-WeaponModels/blob/master/scripting/weaponmodels/entitydata.sp
	//explains how we retrieves this
	g_studioHdrOffset = GameConfGetOffset(hConf, "Animating_StudioHdr");
	if (g_studioHdrOffset == -1)SetFailState("Failed to get offset of Animating_StudioHdr");
	int lightingOriginOffset = FindSendPropInfo("CBaseAnimating", "m_hLightingOrigin");
	g_studioHdrOffset += lightingOriginOffset;
	
	int iOffset = GameConfGetOffset(hConf, "CTFBaseBossLocomotion::GetStepHeight");
	if (iOffset == -1)SetFailState("Failed to get offset of CTFBaseBossLocomotion::GetStepHeight");
	g_hGetStepHeight = DHookCreate(iOffset, HookType_Raw, ReturnType_Float, ThisPointer_Address, NextBotGroundLocomotion_GetStepHeight);
	
	iOffset = GameConfGetOffset(hConf, "NextBotGroundLocomotion::GetGravity");
	if (iOffset == -1)SetFailState("Failed to get offset of NextBotGroundLocomotion::GetGravity");
	g_hGetGravity = DHookCreate(iOffset, HookType_Raw, ReturnType_Float, ThisPointer_Address, NextBotGroundLocomotion_GetGravity);
	
	iOffset = GameConfGetOffset(hConf, "IBody::GetSolidMask");
	if (iOffset == -1)SetFailState("Failed to get offset of IBody::GetSolidMask");
	g_hGetSolidMask = DHookCreate(iOffset, HookType_Raw, ReturnType_Int, ThisPointer_Address, IBody_GetSolidMask);
	
	iOffset = GameConfGetOffset(hConf, "NextBotGroundLocomotion::GetGroundNormal");
	if (iOffset == -1)SetFailState("Failed to get offset of NextBotGroundLocomotion::GetGroundNormal");
	g_hGetGroundNormal = DHookCreate(iOffset, HookType_Raw, ReturnType_VectorPtr, ThisPointer_Address, NextBotGroundLocomotion_GetGroundNormal);
	
	iOffset = GameConfGetOffset(hConf, "NextBotGroundLocomotion::ShouldCollideWith");
	if (iOffset == -1)SetFailState("Failed to get offset of NextBotGroundLocomotion::ShouldCollideWith");
	g_hShouldCollideWith = DHookCreate(iOffset, HookType_Raw, ReturnType_Bool, ThisPointer_Address, NextBotGroundLocomotion_ShouldCollideWith);
	DHookAddParam(g_hShouldCollideWith, HookParamType_CBaseEntity);
	
	iOffset = GameConfGetOffset(hConf, "IBody::GetHullWidth");
	if (iOffset == -1)SetFailState("Failed to get offset of IBody::GetHullWidth");
	g_hGetHullWidth = DHookCreate(iOffset, HookType_Raw, ReturnType_Float, ThisPointer_Address, IBody_GetHullWidth);
	
	iOffset = GameConfGetOffset(hConf, "IBody::GetStandHullHeight");
	if (iOffset == -1)SetFailState("Failed to get offset of IBody::GetStandHullHeight");
	g_hGetStandHullHeight = DHookCreate(iOffset, HookType_Raw, ReturnType_Float, ThisPointer_Address, IBody_GetStandHullHeight);
	
	//Put into gamedata config
	g_hGetMaxAcceleration = DHookCreate(
		GameConfGetOffset(hConf, "ILocomotion::GetMaxAcceleration"), 
		HookType_Raw, ReturnType_Float, ThisPointer_Address, ILocomotion_GetMaxAcceleration);
	
	g_hGetHullMins = DHookCreate(GameConfGetOffset(hConf, "IBody::GetHullMins"), 
		HookType_Raw, ReturnType_VectorPtr, ThisPointer_Address, IBody_GetHullMins);
	
	g_hGetHullMaxs = DHookCreate(GameConfGetOffset(hConf, "IBody::GetHullMaxs"), 
		HookType_Raw, ReturnType_VectorPtr, ThisPointer_Address, IBody_GetHullMaxs);
	g_hGetHullHeight = DHookCreate(GameConfGetOffset(hConf, "IBody::GetHullHeight"), 
		HookType_Raw, ReturnType_Float, ThisPointer_Address, IBody_GetHullHeight);
	g_hGetCrouchHullHeight = DHookCreate(GameConfGetOffset(hConf, "IBody::GetCrouchHullHeight"), 
		HookType_Raw, ReturnType_Float, ThisPointer_Address, IBody_GetCrouchHullHeight);
	g_hGetCollisionGroup = DHookCreate(GameConfGetOffset(hConf, "IBody::GetCollisionGroup"), 
		HookType_Raw, ReturnType_Int, ThisPointer_Address, IBody_GetCollisionGroup);
	
	//ILocomotion::GetGroundSpeed()
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "ILocomotion::GetGroundSpeed");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	if ((g_hGetGroundSpeed = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for ILocomotion::GetGroundSpeed!");
	
	//ILocomotion::GetGroundMotionVector()
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "ILocomotion::GetGroundMotionVector");
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	if ((g_hGetGroundMotionVector = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for ILocomotion::GetGroundMotionVector!");
	
	//CBaseEntity::GetVectors(Vector*, Vector*, Vector*)
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseEntity::GetVectors");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	if ((g_hGetVectors = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Virtual Call for CBaseEntity::GetVectors!");
	
	//SetPoseParameter( CStudioHdr *pStudioHdr, int iParameter, float flValue );
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::SetPoseParameter");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	if ((g_hSetPoseParameter = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Call for CBaseAnimating::SetPoseParameter");
	
	//GetPoseParameter( int iParameter )
	//  StartPrepSDKCall(SDKCall_Entity);
	//  PrepSDKCall_SetSignature(SDKLibrary_Server, "\x55\x8B\xEC\x56\x8B\xF1\x57\x80\xBE\x41\x03\x00\x00\x00\x75\x2A\x83\xBE\x6C\x04\x00\x00\x00\x75\x2A\xE8\x2A\x2A\x2A\x2A\x85\xC0\x74\x2A\x8B\xCE\xE8\x2A\x2A\x2A\x2A\x8B\xBE\x6C\x04\x00\x00", 47);
	//  PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	//  PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	//  if((g_hGetPoseParameter = EndPrepSDKCall()) == INVALID_HANDLE) SetFailState("Failed to create Call for CBaseAnimating::GetPoseParameter");
	
	//LookupPoseParameter( CStudioHdr *pStudioHdr, const char *szName );
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::LookupPoseParameter");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_hLookupPoseParameter = EndPrepSDKCall()) == INVALID_HANDLE)SetFailState("Failed to create Call for CBaseAnimating::LookupPoseParameter");
	g_m_bResolveCollisionsOffset = FindSendPropInfo("CTFBaseBoss", "m_lastHealthPercentage")
	 + GameConfGetOffset(hConf, "m_bResolveCollisions");
	delete hConf;
}

public void OnMapStart()
{
	PrecacheModel(MODEL_NPC);
}


public Action test2(int client, int args) {
	int len = gBots.Length;
	GetAimPos(client, vecGoal);
	for (int i = 0; i < len; i++) {
		int npc = EntRefToEntIndex(gBots.Get(i));
		if (IsValidEntity(npc)) {
			PrintToServer(" PluginBot_Approach: %d", npc);
			PluginBot_Approach(npc, vecGoal);
		}
	}
	return Plugin_Handled;
	
}

public Action test(int client, int args)
{
	float vecPos[3], vecAng[3];
	GetAimPos(client, vecPos);
	GetClientEyeAngles(client, vecAng);
	vecAng[0] = 0.0;
	GetAimPos(client, vecGoal);
	
	int npc = CreateEntityByName("base_boss"); //We use base_boss because it's movement is smooth regardless of the clients network settings.
	DispatchKeyValueVector(npc, "origin", vecPos);
	DispatchKeyValueVector(npc, "angles", vecAng);
	DispatchKeyValue(npc, "model", MODEL_NPC);
	DispatchKeyValue(npc, "modelscale", "0.7");
	DispatchKeyValue(npc, "health", "100");
	
	SetEntProp(npc, Prop_Send, "m_usSolidFlags", 2); //FSOLID_CUSTOMBOXTEST
	SetEntProp(npc, Prop_Data, "m_usSolidFlags", 2); //FSOLID_CUSTOMBOXTEST
	
	DispatchSpawn(npc);
	ActivateEntity(npc);
	DispatchKeyValue(npc, "speed", "900.0");
	//SetEntProp(npc, Prop_Data, "m_speed", 900);
	
	//ResolvePlayerCollisions, by default base_boss will push nearby players away like the mvm tank, this disables that.
	SetEntData(npc, 
		g_m_bResolveCollisionsOffset, 
		false, 4, true);
	//SetEntData(npc, FindSendPropInfo("CTFBaseBoss", "m_lastHealthPercentage") + 24, false, 4, true);
	
	//float pos[3];
	// NavArea area = TheNavMesh.GetNearestNavArea_Vec(vecPos);
	// area.GetCenter(pos);
	
	GetClientAbsOrigin(client, vecGoal);
	
	
	
	Address pLoco = GetLocomotionInterface(npc);
	DHookRaw(g_hShouldCollideWith, true, pLoco); //Don't need to collide with anything but world
	DHookRaw(g_hGetStepHeight, true, pLoco); //The default step height on a base_boss is 1000.0 and this causes it to be able to climb HUGE gaps, limit it to 18.0
	DHookRaw(g_hGetGravity, true, pLoco); //The default gravity on base_boss is too big and causes it to fall onto the ground way too fast.
	DHookRaw(g_hGetGroundNormal, true, pLoco); //The default base_boss rotates itself to the ground normal, this prevents that.
	DHookRaw(g_hGetMaxAcceleration, true, pLoco); //We want to accelerate faster than by default.
	
	Address pBody = GetBodyInterface(npc);
	DHookRaw(g_hGetHullMins, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetHullMaxs, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetHullWidth, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetSolidMask, true, pBody); //The default mask causes base_boss to fall through some things players could walk on.
	DHookRaw(g_hGetStandHullHeight, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetCrouchHullHeight, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetHullHeight, true, pBody); //Fixes the NPC getting stuck so much
	DHookRaw(g_hGetCollisionGroup, true, pBody); //Fixes the NPC getting stuck so much
	SDKHook(npc, SDKHook_ThinkPost, OnBotThink);
	gBots.Push(EntIndexToEntRef(npc));
	return Plugin_Handled;
}

//Does the 9way leg movement, reverse engineered from CHeadlessHatmanBody::Update
public void OnBotThink(int iEntity)
{
	Address pLocomotion = GetLocomotionInterface(iEntity);
	if (pLocomotion == Address_Null) {
		return;
	}
	//Needed to make the npc move
	PluginBot_Approach(iEntity, vecGoal);
	SDKCall(g_hRun, pLocomotion);
	Address pStudioHdr = view_as<Address>(GetEntData(iEntity, g_studioHdrOffset));
	
	int m_iMoveX = SDKCall(g_hLookupPoseParameter, iEntity, pStudioHdr, "move_x");
	int m_iMoveY = SDKCall(g_hLookupPoseParameter, iEntity, pStudioHdr, "move_y");
	
	if (m_iMoveX < 0 || m_iMoveY < 0)
		return;
	
	int iSequence = GetEntProp(iEntity, Prop_Send, "m_nSequence");
	
	if (!(GetEntityFlags(iEntity) & FL_ONGROUND))
	{
		if (iSequence != ANIM_AIR)
		{
			//Set animation.
			SDKCall(g_hResetSequence, iEntity, ANIM_AIR);
		}
		
		return;
	}
	
	float flGroundSpeed = SDKCall(g_hGetGroundSpeed, pLocomotion);
	if (flGroundSpeed <= 0.01)
	{
		SDKCall(g_hSetPoseParameter, iEntity, pStudioHdr, m_iMoveX, 0.0);
		SDKCall(g_hSetPoseParameter, iEntity, pStudioHdr, m_iMoveY, 0.0);
		
		if (iSequence != ANIM_IDLE)
		{
			//Set animation.
			SDKCall(g_hResetSequence, iEntity, ANIM_IDLE);
		}
	}
	else
	{
		if (iSequence != ANIM_MOVE)
		{
			//Set animation.
			SDKCall(g_hResetSequence, iEntity, ANIM_MOVE);
		}
		
		float vecForward[3], vecRight[3], vecUp[3];
		SDKCall(g_hGetVectors, iEntity, vecForward, vecRight, vecUp);
		
		float vecMotion[3];
		SDKCall(g_hGetGroundMotionVector, pLocomotion, vecMotion);
		
		SDKCall(g_hSetPoseParameter, iEntity, pStudioHdr, m_iMoveX, GetVectorDotProduct(vecMotion, vecForward));
		SDKCall(g_hSetPoseParameter, iEntity, pStudioHdr, m_iMoveY, GetVectorDotProduct(vecMotion, vecRight));
	}
	
	float m_flGroundSpeed = GetEntPropFloat(iEntity, Prop_Data, "m_flGroundSpeed");
	if (m_flGroundSpeed != 0.0)
	{
		float flReturnValue = clamp(flGroundSpeed / m_flGroundSpeed, -4.0, 12.0);
		
		SetEntPropFloat(iEntity, Prop_Send, "m_flPlaybackRate", flReturnValue);
	}
	
	//Advances the animation
	SDKCall(g_hStudioFrameAdvance, iEntity);
	
	//  float flPlaybackRate = GetEntPropFloat(iEntity, Prop_Send, "m_flPlaybackRate");
	//  PrintToServer("m_nSequence %i m_flPlaybackRate %f m_flGroundSpeed %f", iSequence, flPlaybackRate, flGroundSpeed);
}

//My PathFinding stuff the only thing useful for you is g_hApproach and g_hFaceTowards
//which will make the NPC approach and rotate towards a certain position and you'll be using this for moving the NPC.
public void PluginBot_Approach(int bot_entidx, const float vec[3])
{
	Address pLocomotion = GetLocomotionInterface(bot_entidx);
	
	SDKCall(g_hApproach, pLocomotion, vec, 0.1);
	SDKCall(g_hFaceTowards, pLocomotion, vec);
	
	float vecMyPos[3];
	GetEntPropVector(bot_entidx, Prop_Data, "m_vecAbsOrigin", vecMyPos);
	
	float flDistance = GetVectorDistance(vecGoal, vecMyPos);
	if (flDistance <= 30.0)
	{
		float vecDirection[3];
		vecDirection[0] = GetRandomFloat(-1.0, 1.0);
		vecDirection[1] = GetRandomFloat(-1.0, 1.0);
		vecDirection[2] = 0.0;
		
		ScaleVector(vecDirection, 2000.0);
		
		AddVectors(vecMyPos, vecDirection, vecMyPos);
		
	}
}

public bool PluginBot_IsTraverSable(int bot_entidx, int other_entidx)
{
	return true;
}

public float clamp(float a, float b, float c)
{
	return (a > c ? c : (a < b ? b : a));
}

public MRESReturn IBody_GetHullWidth(Address pThis, Handle hReturn, Handle hParams)
{
	//  PrintToServer("GetHullWidth %f", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, 26.0);
	return MRES_Supercede;
}

public MRESReturn IBody_GetStandHullHeight(Address pThis, Handle hReturn, Handle hParams)
{
	//  PrintToServer("GetStandHullHeight %f", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, 68.0);
	return MRES_Supercede;
}

public MRESReturn IBody_GetHullHeight(Address pThis, Handle hReturn, Handle hParams)
{
	//  PrintToServer("GetHullHeight %f", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, 68.0);
	return MRES_Supercede;
}

public MRESReturn IBody_GetCrouchHullHeight(Address pThis, Handle hReturn, Handle hParams)
{
	//  PrintToServer("GetCrouchHullHeight %f", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, 32.0);
	return MRES_Supercede;
}

public MRESReturn IBody_GetCollisionGroup(Address pThis, Handle hReturn, Handle hParams)
{
	//PrintToServer("GetCollisionGroup %i", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, 0);
	return MRES_Supercede;
	//return MRES_Ignored
}

public MRESReturn IBody_GetHullMins(Address pThis, Handle hReturn, Handle hParams)
{
	//  float vecReturn[3];
	//  DHookGetReturnVector(hReturn, vecReturn);
	
	//  PrintToServer("GetHullMins %f %f %f", vecReturn[0], vecReturn[1], vecReturn[2]);
	
	DHookSetReturnVector(hReturn, view_as<float>( { -13.0, -13.0, 0.0 } ));
	return MRES_Supercede;
}

public MRESReturn IBody_GetHullMaxs(Address pThis, Handle hReturn, Handle hParams)
{
	//  float vecReturn[3];
	//  DHookGetReturnVector(hReturn, vecReturn);
	
	//  PrintToServer("GetHullMaxs %f %f %f", vecReturn[0], vecReturn[1], vecReturn[2]);
	
	DHookSetReturnVector(hReturn, view_as<float>( { 13.0, 13.0, 68.0 } ));
	return MRES_Supercede;
}

public MRESReturn IBody_GetSolidMask(Address pThis, Handle hReturn, Handle hParams)
{
	//  PrintToServer("GetSolidMask 0x%x", DHookGetReturn(hReturn));
	
	DHookSetReturn(hReturn, MASK_NPCSOLID | MASK_PLAYERSOLID);
	return MRES_Supercede;
}

public MRESReturn ILocomotion_GetMaxAcceleration(Address pThis, Handle hReturn, Handle hParams)
{
	DHookSetReturn(hReturn, 500.0);
	return MRES_Supercede;
}

public MRESReturn NextBotGroundLocomotion_GetStepHeight(Address pThis, Handle hReturn, Handle hParams)
{
	DHookSetReturn(hReturn, 18.0);
	return MRES_Supercede;
}

public MRESReturn NextBotGroundLocomotion_ShouldCollideWith(Address pThis, Handle hReturn, Handle hParams)
{
	DHookSetReturn(hReturn, false);
	return MRES_Supercede;
}

public MRESReturn NextBotGroundLocomotion_GetGravity(Address pThis, Handle hReturn, Handle hParams)
{
	DHookSetReturn(hReturn, 800.0);
	return MRES_Supercede;
}

public MRESReturn NextBotGroundLocomotion_GetGroundNormal(Address pThis, Handle hReturn, Handle hParams)
{
	DHookSetReturnVector(hReturn, view_as<float>( { 0.0, 0.0, 1.0 } ));
	return MRES_Supercede;
}

public Address GetLocomotionInterface(int index)
{
	Address pNB = SDKCall(g_hMyNextBotPointer, index);
	return SDKCall(g_hGetLocomotionInterface, pNB);
}

public Address GetBodyInterface(int index)
{
	Address pNB = SDKCall(g_hMyNextBotPointer, index);
	return SDKCall(g_hGetBodyInterface, pNB);
}

stock bool GetAimPos(int client, float vecPos[3])
{
	float StartOrigin[3], Angles[3];
	GetClientEyeAngles(client, Angles);
	GetClientEyePosition(client, StartOrigin);
	
	Handle TraceRay = TR_TraceRayFilterEx(StartOrigin, Angles, MASK_NPCSOLID | MASK_PLAYERSOLID, RayType_Infinite, ExcludeFilter, client);
	if (TR_DidHit(TraceRay))
	{
		TR_GetEndPosition(vecPos, TraceRay);
	}
	vecPos[2] += 90.0;
	delete TraceRay;
}

public bool ExcludeFilter(int entityhit, int mask, any entity)
{
	if (entityhit > MaxClients && entityhit != entity)
	{
		return true;
	}
	
	return false;
} 