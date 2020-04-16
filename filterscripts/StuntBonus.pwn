/*
		Multiplayer Stunt Bonus detection by NaS (c) 2016
		
		This FS detects Stunts made with vehicles (Jumps) not only on the original Map but also on custom objects via ColAndreas.
		
		The ground detection method is unfinished, it may also not detect the exact time when a vehicle looses/regains ground contact.
		The FS creates a history for every player (position, rotation, speed) to calculate the rotation delta upon regaining ground contact.
		Besides raycasting while in vehicles, the "heavy" code is only performed when an actual stunt is done.

		It detects the duration of a Stunt, No. of Saltos/Barrel Rolls, Turning Angle and total Distance.
		Theres also a combo system, change COMBO_TIME to 0 in case you don't want it.
		Sometimes Barrel Rolls/Saltos get mixed up because of the rotation snapping of SA. Or I didn't find the perfect algorithm yet.
		
		The Stunts a driver does are showing for passengers too (without rewarding of course).
		
		The maximum duration of a stunt (in ms) is limited to (MAX_HIST / TIMER_INTERVAL), however a higher MAX_HIST will not affect the performance much.
		This limits eventual farming methods to a certain level. If you find any efficient ways to trick the Rewards, please let me know.

		- HAVE FUN!
*/

#include <a_samp>
#define FOREACH_NO_PLAYERS
#define FOREACH_NO_BOTS
#define _FOREACH_NO_TEST
#include <foreach>
#include <ColAndreas>
#include <rotations> // 1.2.0

#define FILTERSCRIPT

// Config

#define MAX_HIST   			400
#define TIMER_INTERVAL      150

#define TEXT_DRAW_TIME      8000 // Time (ms) that the reward textdraw will be shown
#define COMBO_TIME          10000 // Max Time between two Stunts to combo up

#define MIN_STUNT_DUR       1000
#define MIN_STUNT_DIST      30.0
#define MAX_SPEED           520.0 // m/s - may need some tweaking for falling?

// Reward factors

#define MONEY_DUR       0.005 // Duration (0.001 = 1$ per s)
#define MONEY_DIST      1.0 // Distance ($ per meter)
#define MONEY_SALTO     60.0 // Num Saltos ($ per salto)
#define MONEY_BARREL    70.0 // Num Barrel Rolls ($ per barrel roll)
#define MONEY_TURN      40.0 // 360 Turns ($ per turn)
#define MONEY_COMBO_MUL 10.0 // Combos (multiplier for Combo Num - per continous stunt so don't set it too high!)

//#define ccmp(%1) (strcmp(cmdtext,%1,true)==0) // For test CMDs

new static const GCRayMatrix[] = // Ray "Matrix" for determining Ground Contact, 1 = right, -1 = left, 0 = center (Multiplicators for vehicle sizes)
{
    // Corners Up
    1, 1, 1,
    -1, -1, 1,
    1, -1, 1,
    -1, 1, 1,
    // Corners Down
    1, 1, -1,
    -1, -1, -1,
    1, -1, -1,
    -1, 1, -1,
    /*// Mid Sides Up
    0, 1, 1,
    1, 0, 1,
	0, -1, 1,
	-1, 0, 1,
	// Mid Sides Down
    0, 1, -1,
    1, 0, -1,
	0, -1, -1,
	-1, 0, -1,*/
	// Center Down/Up
	0, 0, 1,
	0, 0, -1
};

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
new HistNum[MAX_PLAYERS], HistCount[MAX_PLAYERS], HistVehicleID[MAX_PLAYERS], TDTick[MAX_PLAYERS], PlayerText:StuntText[MAX_PLAYERS], StuntCombo[MAX_PLAYERS], StuntMoney[MAX_PLAYERS], LastStunt[MAX_PLAYERS];

new HistTimerID = -1, HistTimerTick;

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

forward Float:floatangledistdir(Float:firstAngle, Float:secondAngle); // Improved angle distance function - directional
Float:floatangledistdir(Float:firstAngle, Float:secondAngle)
{
	new Float:difference = secondAngle - firstAngle;
	while(difference < -180.0) difference += 360.0;
	while(difference > 180.0) difference -= 360.0;
	return difference;
}

public OnFilterScriptInit()
{
	CA_Init();
	EnableStuntBonusForAll(0); // Just to make sure!
	
	new tick = GetTickCount();
	HistTimerTick = tick;
	
	for(new i = 0; i < MAX_PLAYERS; i ++)
	{
	    HistNum[i] = 0;
	    HistCount[i] = 0;
	    HistVehicleID[i] = -1;
	    TDTick[i] = 0;
	    StuntCombo[i] = 0;
	    StuntMoney[i] = 0;
	    LastStunt[i] = tick - COMBO_TIME;
	    
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
	
	HistTimerID = SetTimer("HistTimer", 30, 1);
	
	return 1;
}

public OnFilterScriptExit()
{
	if(HistTimerID != -1) KillTimer(HistTimerID);
	HistTimerID = -1;

	for(new i = 0; i < MAX_PLAYERS; i ++) if(IsPlayerConnected(i)) OnPlayerDisconnect(i, 0);
	
	return 1;
}

public OnPlayerConnect(playerid)
{
	if(IsPlayerNPC(playerid)) return 1;
	
    HistNum[playerid] = 0;
	HistCount[playerid] = 0;
	HistVehicleID[playerid] = -1;
	TDTick[playerid] = 0;
	StuntCombo[playerid] = 0;
	StuntMoney[playerid] = 0;
	LastStunt[playerid] = GetTickCount() - COMBO_TIME;
	
	CreateTD(playerid);

	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if(IsPlayerNPC(playerid)) return 1;
    
    PlayerTextDrawDestroy(playerid, StuntText[playerid]);

	Iter_Remove(it_Driver, playerid);
	Iter_Remove(it_Passenger, playerid);
    
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
	if(tick - HistTimerTick < TIMER_INTERVAL) return 1; // More stable timer
	
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
	    
		new vid = GetPlayerVehicleID(playerid), mid = GetVehicleModel(vid);
		
		if(!IsStuntVehicle(mid)) // This vehicle shouldnt be used for stunting - Reset Hist
		{
		    if(HistCount[playerid] > 0) 
		    {
		        HistNum[playerid] = 0;
			    HistCount[playerid] = 0;
			    HistVehicleID[playerid] = -1;
			    StuntCombo[playerid] = 0;
			    StuntMoney[playerid] = 0;
		    }
			continue;
		}
		
		if(vid != HistVehicleID[playerid]) // Switched vehicle without leaving - Reset Hist
		{
		    HistNum[playerid] = 0;
		    HistCount[playerid] = 0;
		    HistVehicleID[playerid] = vid;
		    StuntCombo[playerid] = 0;
		    StuntMoney[playerid] = 0;
		}
		
		new Float:X, Float:Y, Float:Z, Float:rW, Float:rX, Float:rY, Float:rZ;
		
		GetVehiclePos(vid, X, Y, Z);
		GetVehicleRotationQuat(vid, rW, rX, rY, rZ);
		
		new gc = CheckVehicleGroundContact(mid, X, Y, Z, rW, rX, rY, rZ), cur = HistNum[playerid];

		GetEulerFromQuat(rW, rX, rY, rZ, rX, rY, rZ, euler_samp);
		
		if(gc == -1) // Touched water - Reset Hist
		{
		    if(HistCount[playerid] > 0)
		    {
		        HistNum[playerid] = 0;
			    HistCount[playerid] = 0;
			    HistVehicleID[playerid] = -1;
			    StuntCombo[playerid] = 0;
			    StuntMoney[playerid] = 0;
		    }
			continue;
		}
		
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
			    new i = cur, dur, Float:rXd, Float:rYd, Float:rZd, Float:dist, Float:distc;

			    if(floatsqroot(floatpower(Hist[playerid][prev][htX] - Hist[playerid][i][htX], 2) + floatpower(Hist[playerid][prev][htY] - Hist[playerid][i][htY], 2) + floatpower(Hist[playerid][prev][htZ] - Hist[playerid][i][htZ], 2)) < MAX_SPEED / (1000.0 / TIMER_INTERVAL)) // Unrealistic distance (more than 100 m/s or teleport)
			    {
				    for(new j = 0; j < HistCount[playerid]; j ++)
				    {
				        if(i == 0) i = HistCount[playerid] - 1; // Wrap
				        else i --;

						if(j > 0)
						{
						    rXd += floatangledistdir(rX, Hist[playerid][i][htrX]);
						    rYd += floatangledistdir(rY, Hist[playerid][i][htrY]);
						    rZd += floatangledistdir(rZ, Hist[playerid][i][htrZ]);

						    distc = floatsqroot(floatpower(X - Hist[playerid][i][htX], 2) + floatpower(Y - Hist[playerid][i][htY], 2) + floatpower(Z - Hist[playerid][i][htZ], 2));

						    if(distc > MAX_SPEED / (1000.0 / TIMER_INTERVAL)) // Unrealistic distance (more than 110 m/s or teleport)
							{
							    dist = 0.0;
							    break;
							}

							dist += distc;
						}

				        dur = tick - Hist[playerid][i][htTick];

				        if(Hist[playerid][i][htGroundContact]) break;

	                    rX = Hist[playerid][i][htrX];
						rY = Hist[playerid][i][htrY];
						rZ = Hist[playerid][i][htrZ];

						X = Hist[playerid][i][htX];
						Y = Hist[playerid][i][htY];
						Z = Hist[playerid][i][htZ];
					}

					new Float:saltos = (rXd < 0.0 ? -rXd : rXd)/360.0, Float:barrel = (rYd < 0.0 ? -rYd : rYd)/360.0, Float:turn360 = (rZd < 0.0 ? -rZd : rZd)/360.0;

					if(dur >= MIN_STUNT_DUR && dist > MIN_STUNT_DIST)
					{
					    new money;

						if(tick - LastStunt[playerid] > COMBO_TIME)
						{
						    money = floatround(dur*MONEY_DUR + dist*MONEY_DIST + saltos*MONEY_SALTO + barrel*MONEY_BARREL + turn360*MONEY_TURN);
							StuntCombo[playerid] = 1;
							StuntMoney[playerid] = money;
						}
						else
						{
						    StuntCombo[playerid] ++;
						    money = floatround(dur*MONEY_DUR + dist*MONEY_DIST + saltos*MONEY_SALTO + barrel*MONEY_BARREL + turn360*MONEY_TURN + StuntCombo[playerid]*MONEY_COMBO_MUL);
							StuntMoney[playerid] += money;
						}

						LastStunt[playerid] = tick;

					    new str[175];
						if(StuntCombo[playerid] <= 1) format(str, sizeof(str), "SUPER-STUNT~n~~w~Duration: %ds~n~Saltos: %.1f, Barrel Rolls: %.1f, 360-Turns: %.1f~n~Distance: %.02fm~n~Reward: $%d", dur/1000, saltos, barrel, turn360, dist, money);
						else format(str, sizeof(str), "SUPER-STUNT~n~~w~Duration: %ds~n~Saltos: %.1f, Barrel Rolls: %.1f, 360-Turns: %.1f~n~Distance: %.02fm~n~Stunt-Combo: %d~n~Total Reward: $%d", dur/1000, saltos, barrel, turn360, dist, StuntCombo[playerid], StuntMoney[playerid]);

						PlayerTextDrawSetString(playerid, StuntText[playerid], str);
						PlayerTextDrawShow(playerid, StuntText[playerid]);
						TDTick[playerid] = tick;

						GivePlayerMoney(playerid, money);

						GetPlayerName(playerid, str, 25);
						if(StuntCombo[playerid] <= 1) format(str, sizeof(str), "%s performed a SUPER-STUNT~n~~~w~Duration: %ds~n~Saltos: %.1f, Barrel Rolls: %.1f, 360-Turns: %.1f~n~Distance: %.02fm", str, dur/1000, saltos, barrel, turn360, dist);
						else format(str, sizeof(str), "%s performed a SUPER-STUNT~n~~w~Duration: %ds~n~Saltos: %.1f, Barrel Rolls: %.1f, 360-Turns: %.1f~n~Distance: %.02fm~n~Stunt-Combo: %d", str, dur/1000, saltos, barrel, turn360, dist, StuntCombo[playerid]);

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
		}
		
		HistNum[playerid] ++;
		if(HistNum[playerid] == MAX_HIST) HistNum[playerid] = 0; // Wrap around if reached maximum
		if(HistCount[playerid] < MAX_HIST) HistCount[playerid] ++; // Higher count until maximum
	}
	
	HistTimerTick = tick;
	
	return 1;
}

CreateTD(playerid)
{
	StuntText[playerid] = CreatePlayerTextDraw(playerid, 320.0, 360.0, "_");
	PlayerTextDrawLetterSize(playerid, StuntText[playerid], 0.35, 1.08);
	PlayerTextDrawAlignment(playerid, StuntText[playerid], 2);
	PlayerTextDrawColor(playerid, StuntText[playerid], 0x666666FF);
	PlayerTextDrawBackgroundColor(playerid, StuntText[playerid], 0x000000FF);
	PlayerTextDrawUseBox(playerid, StuntText[playerid], 0);
	PlayerTextDrawSetShadow(playerid, StuntText[playerid], 0);
	PlayerTextDrawSetOutline(playerid, StuntText[playerid], 1);
	PlayerTextDrawFont(playerid, StuntText[playerid], 1);
	PlayerTextDrawSetProportional(playerid, StuntText[playerid], 1);

	return 1;
}

/*
Code for checking Ground Contact - Works with a matrix, point projection and the vehicle sizes. May get further improvements soon
*/
CheckVehicleGroundContact(model, Float:X, Float:Y, Float:Z, Float:rW, Float:rX, Float:rY, Float:rZ)
{
	new Float:sX, Float:sY, Float:sZ, ret, Float:cX, Float:cY, Float:cZ;
	
	GetVehicleModelInfo(model, VEHICLE_MODEL_INFO_SIZE, sX, sY, sZ);

	sX *= 0.57;
	sY *= 0.57;
	sZ *= 0.57;

	for(new i = 0; i < sizeof(GCRayMatrix); i += 3)
	{
	    point_rot_by_quat(sX * GCRayMatrix[i], sY * GCRayMatrix[i+1], sZ * GCRayMatrix[i+2], rW, -rX, -rY, -rZ, cX, cY, cZ);

	    ret = CA_RayCastLine(X, Y, Z, cX + X, cY + Y, cZ + Z, cX, cY, cZ);

		if(ret == WATER_OBJECT) return -1;

  		if(ret != 0) return 1;
	}
	
	return 0;
}

quat_mult(Float:qw, Float:qx, Float:qy, Float:qz, Float:rw, Float:rx, Float:ry, Float:rz, &Float:retw, &Float:retx, &Float:rety, &Float:retz)
{
    retw = (rw*qw - rx*qx - ry*qy - rz*qz);
    retx = (rw*qx + rx*qw - ry*qz + rz*qy);
    rety = (rw*qy + rx*qz + ry*qw - rz*qx);
    retz = (rw*qz - rx*qy + ry*qx + rz*qw);
    
    return 1;
}

point_rot_by_quat(Float:x, Float:y, Float:z, Float:qw, Float:qx, Float:qy, Float:qz, &Float:retx, &Float:rety, &Float:retz) // Quite efficient, no trig. functions at all! For a vehicle quat, invert qx, qy, qz - Converted from Python to PAWN (No author known)
{
	new Float:retw;

    quat_mult(qw, qx, qy, qz, 0.0, x, y, z, retw, retx, rety, retz);
    quat_mult(retw, retx, rety, retz, qw, -qx, -qy, -qz, retw, retx, rety, retz);

    return 1;
}

IsStuntVehicle(modelid)
{
	if(modelid < 400 || modelid > 611) return 0;
	
	return StuntVehicles[modelid-400];
}

// --- EOF
