/*
		Multiplayer Stunt Bonus detection by NaS (c) 2016
		
		This FS detects Stunts made with vehicles (Jumps) not only on the original Map but also on custom objects via ColAndreas.
		
		The ground detection method is unfinished tho, also it may not detect the exact time when a vehicle looses/regains ground contact.
		The FS creates a history for every player (position, rotation, speed) to calculate the rotation delta upon regaining ground contact.
		The history is made pretty efficient, no looping through it except for end-calculations!

		It detects the duration of a Stunt, No. of Saltos/Barrel Rolls, Turning Angle and total Distance.
		However sometimes Barrel Rolls/Saltos get mixed up because of the rotation snapping of SA.

		HAVE FUN!
		
		New: Stunt is showing for passengers too and the looping is a bit more efficient now
		
		PS: Suggestions regarding rotation processing are highly welcome!
		
		The Ground Detection is just basic atm, this is a test release so anyone can test it and give suggestions!
*/

#include <a_samp>
#define FOREACH_NO_PLAYERS
#define FOREACH_NO_BOTS
#include <foreach>
#include <ColAndreas>
#include <QuaternionStuff>

#define FILTERSCRIPT

// Config

#define MAX_HIST   			120
#define TIMER_INTERVAL      250

#define TEXT_DRAW_TIME      8000 // Time (ms) that the reward textdraw will be shown

#define MIN_STUNT_DUR       1000
#define MIN_STUNT_DIST      35.0

// Reward factors

#define MONEY_DUR       0.005 // Duration in ms (0.005$ per ms aka 5$ per s)
#define MONEY_DIST      2.0 // Distance in meters (2$ per meter)
#define MONEY_SALTO     100.0 // Num Saltos (100$ per salto)
#define MONEY_BARREL    100.0 // Num Barrel Rolls (100$ per barrel roll)
#define MONEY_TURN      100.0 // Turning Angle in degrees (1$ per degree)

// Script Variables, Arrays etc

enum E_HIST
{
	htTick,
	bool:htGroundContact,
	Float:htX,
	Float:htY,
	Float:htZ,
	Float:htrX,
	Float:htrY,
	Float:htrZ
};
new Hist[MAX_PLAYERS][MAX_HIST][E_HIST];
new HistNum[MAX_PLAYERS], HistCount[MAX_PLAYERS], HistVehicleID[MAX_PLAYERS], TDTick[MAX_PLAYERS], PlayerText:StuntText[MAX_PLAYERS];

new HistTimerID = -1;

new Iterator:it_Driver<MAX_PLAYERS>, Iterator:it_Passenger<MAX_PLAYERS>;

// Data

new const StuntVehicles[212] =
{
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,0,1,1,1,1,0,1,0,0,1,0,1,1,1,1,1,1,1,1,1,1,
	0,0,1,0,0,1,0,0,0,1,1,1,1,1,0,1,1,1,0,0,1,1,1,0,1,1,0,0,1,1,0,1,1,1,1,1,1,1,0,1,1,0,0,1,1,1,
	1,0,1,1,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
	0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,
	0,1,1,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,0,0,0,1,0,0
};

public OnFilterScriptInit()
{
	CA_Init();
	EnableStuntBonusForAll(0); // Just to make sure!
	
	for(new i = 0; i < MAX_PLAYERS; i ++)
	{
	    HistNum[i] = 0;
	    HistCount[i] = 0;
	    HistVehicleID[i] = -1;
	    TDTick[i] = 0;
	    
	    if(IsPlayerConnected(i) && !IsPlayerNPC(i))
		{
			CreateTD(i);
			
			switch(GetPlayerState(i))
			{
				case PLAYER_STATE_DRIVER: Iter_Add(it_Driver, i);
				case PLAYER_STATE_PASSENGER: Iter_Add(it_Passenger, i);
			}
		}
	}
	
	HistTimerID = SetTimer("HistTimer", TIMER_INTERVAL, 1);
	
	return 1;
}

public OnFilterScriptExit()
{
	if(HistTimerID != -1) KillTimer(HistTimerID);
	
	return 1;
}

public OnPlayerConnect(playerid)
{
	if(IsPlayerNPC(playerid)) return 1;
	
    HistNum[playerid] = 0;
	HistCount[playerid] = 0;
	HistVehicleID[playerid] = -1;
	TDTick[playerid] = 0;
	
	CreateTD(playerid);

	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if(IsPlayerNPC(playerid)) return 1;
    
    PlayerTextDrawDestroy(playerid, StuntText[playerid]);
    
    switch(GetPlayerState(playerid))
	{
		case PLAYER_STATE_DRIVER: if(Iter_Contains(it_Driver, playerid)) Iter_Remove(it_Driver, playerid);
		case PLAYER_STATE_PASSENGER: if(Iter_Contains(it_Passenger, playerid))Iter_Remove(it_Passenger, playerid);
	}
    
	return 1;
}

public OnPlayerStateChange(playerid, newstate, oldstate)
{
	if(newstate == PLAYER_STATE_DRIVER)
	{
	    if(Iter_Contains(it_Passenger, playerid)) Iter_Remove(it_Passenger, playerid);
	    Iter_Add(it_Driver, playerid);
	}
	else if(newstate == PLAYER_STATE_PASSENGER)
	{
	    if(Iter_Contains(it_Driver, playerid)) Iter_Remove(it_Driver, playerid);
	    Iter_Add(it_Passenger, playerid);
	}
	return 1;
}

forward HistTimer();
public HistTimer()
{
	new tick = GetTickCount();
	
	foreach(it_Passenger, playerid)
	{
	    if(TDTick[playerid] != 0 && tick - TDTick[playerid] > TEXT_DRAW_TIME)
	    {
	        PlayerTextDrawHide(playerid, StuntText[playerid]);
	        TDTick[playerid] = 0;
	    }
	}
	
	foreach(it_Driver, playerid)
	{
	    if(TDTick[playerid] != 0 && tick - TDTick[playerid] > TEXT_DRAW_TIME)
	    {
	        PlayerTextDrawHide(playerid, StuntText[playerid]);
	        TDTick[playerid] = 0;
	    }
	    
		new vid = GetPlayerVehicleID(playerid);
		
		if(!IsStuntVehicle(GetVehicleModel(vid)))
		{
		    if(HistCount[playerid] > 0) // This vehicle shouldnt be used for stunting - Reset Hist
		    {
		        HistNum[playerid] = 0;
			    HistCount[playerid] = 0;
			    HistVehicleID[playerid] = -1;
		    }
			continue;
		}
		
		if(vid != HistVehicleID[playerid]) // Switched vehicle without leaving - Reset Hist
		{
		    HistNum[playerid] = 0;
		    HistCount[playerid] = 0;
		    HistVehicleID[playerid] = vid;
		}
		
		new Float:X, Float:Y, Float:Z, Float:rW, Float:rX, Float:rY, Float:rZ;
		
		GetVehiclePos(vid, X, Y, Z);
		GetVehicleRotationQuat(vid, rW, rX, rY, rZ);
		QuatToEuler(rX, rY, rZ, rW, rX, rY, rZ);
		
		new gc = CheckVehicleGroundContact(X, Y, Z), cur = HistNum[playerid];
		
		Hist[playerid][cur][htTick] = tick;
		Hist[playerid][cur][htGroundContact] = gc == 1;
		Hist[playerid][cur][htX] = X;
		Hist[playerid][cur][htY] = Y;
		Hist[playerid][cur][htZ] = Z;
		Hist[playerid][cur][htrX] = rX;
		Hist[playerid][cur][htrY] = rY;
		Hist[playerid][cur][htrZ] = rZ;
		
		if(HistCount[playerid] > 1)
		{
			new prev = cur > 0 ? cur-1 : MAX_HIST-1;
			
			if(Hist[playerid][cur][htGroundContact] && !Hist[playerid][prev][htGroundContact]) // Re-gained ground contact
			{
			    new i = cur, dur, rXd, rYd, rZd, Float:dist;
			    for(new j = 0; j < HistCount[playerid]; j ++)
			    {
			        if(i == 0) i = HistCount[playerid] - 1;
			        else i --;
			        
					if(j > 0)
					{
					    rXd += floatangledist(rX, Hist[playerid][i][htrX]);
					    rYd += floatangledist(rY, Hist[playerid][i][htrY]);
					    rZd += floatangledist(rZ, Hist[playerid][i][htrZ]);
					    
					    dist += floatsqroot(floatpower(X - Hist[playerid][i][htX], 2) + floatpower(Y - Hist[playerid][i][htY], 2) + floatpower(Z - Hist[playerid][i][htZ], 2));
					}
					
					rX = Hist[playerid][i][htrX];
					rY = Hist[playerid][i][htrY];
					rZ = Hist[playerid][i][htrZ];
					
					X = Hist[playerid][i][htX];
					Y = Hist[playerid][i][htY];
					Z = Hist[playerid][i][htZ];

			        dur = tick - Hist[playerid][i][htTick];
			        
			        if(Hist[playerid][i][htGroundContact]) break;
				}

				new saltos = rXd/360, barrel = rYd/360, turn360 = rZd/360;

				if(dur > MIN_STUNT_DUR && dist > MIN_STUNT_DIST)
				{
				    new money = floatround(dur*MONEY_DUR + dist*MONEY_DIST + saltos*MONEY_SALTO + barrel*MONEY_BARREL + turn360*MONEY_TURN);
				    
				    new str[130];
					format(str, sizeof(str), "You performed a SUPER-STUNT~n~Duration: %ds, Saltos: %d, Barrel Rolls: %d, 360-Turns: %d, Distance: %.02fm~n~Reward: $%d", dur/1000, saltos, barrel, turn360, dist, money);
					
					PlayerTextDrawSetString(playerid, StuntText[playerid], str);
					PlayerTextDrawShow(playerid, StuntText[playerid]);
					TDTick[playerid] = tick;
					
					GivePlayerMoney(playerid, money);
					
					GetPlayerName(playerid, str, 25);
					format(str, sizeof(str), "%s performed a SUPER-STUNT~n~Duration: %ds, Saltos: %d, Barrel Rolls: %d, 360-Turns: %d, Distance: %.02fm", str, dur/1000, saltos, barrel, turn360, dist);
					
					foreach(it_Passenger, passengerid)
					{
					    if(GetPlayerVehicleID(passengerid) != vid) continue;
					    
					    PlayerTextDrawSetString(passengerid, StuntText[passengerid], str);
						PlayerTextDrawShow(passengerid, StuntText[passengerid]);
						TDTick[passengerid] = tick;
					}
				}
			}
		}
		
		HistNum[playerid] ++;
		if(HistNum[playerid] == MAX_HIST) HistNum[playerid] = 0; // Wrap around if reached maximum
		if(HistCount[playerid] < MAX_HIST) HistCount[playerid] ++; // Higher count until maximum
	}
	
	return 1;
}

CreateTD(playerid)
{
	StuntText[playerid] = CreatePlayerTextDraw(playerid, 320.0, 400.0, "_");
	PlayerTextDrawLetterSize(playerid, StuntText[playerid], 0.25, 0.75);
	PlayerTextDrawAlignment(playerid, StuntText[playerid], 2);
	PlayerTextDrawColor(playerid, StuntText[playerid], 0xFFFFFFFF);
	PlayerTextDrawBackgroundColor(playerid, StuntText[playerid], 0x000000FF);
	PlayerTextDrawUseBox(playerid, StuntText[playerid], 0);
	PlayerTextDrawSetShadow(playerid, StuntText[playerid], 0);
	PlayerTextDrawSetOutline(playerid, StuntText[playerid], 1);
	PlayerTextDrawFont(playerid, StuntText[playerid], 1);
	PlayerTextDrawSetProportional(playerid, StuntText[playerid], 1);

	return 1;
}

/*
Code for checking Ground Contact - TEST CODE! I know this is not considering different vehicle models or checking for ground correctly!
It checks the center of the vehicle, so may be not working perfectly - to be extended soon
*/
CheckVehicleGroundContact(Float:X, Float:Y, Float:Z) 
{
	new Float:cX, Float:cY, Float:cZ, ret;
	
	ret = CA_RayCastLine(X, Y, Z, X, Y, Z - 15.0, cX, cY, cZ);
	
	if(ret == 20000) return 0;
	
	if(Z - cZ > 1.2) return 0;
	
	return 1;
}

floatangledist(Float:alpha, Float:beta) // Ranging from 0 to 180 (INT), not directional (left/right) - To be made directional!
{
    new phi = floatround(floatabs(beta - alpha), floatround_floor) % 360;
    new distance = phi > 180 ? 360 - phi : phi;
    
    return distance;
}

IsStuntVehicle(modelid)
{
	if(modelid < 400 || modelid > 611) return 0;
	
	return StuntVehicles[modelid-400];
}

// --- EOF
