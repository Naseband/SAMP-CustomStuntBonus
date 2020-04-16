SA-MP Custom Stunt Bonuses by NaS (c) 2016

This is a small Filterscript for SAMP which introduces Stunt Bonuses (Jumps only, no 2-wheel/wheelie Stunts) to the Multiplayer World.
Those are natively existing (EnableStuntBonusForPlayer/All), however they only work on the original map and are highly abusive if there are custom objects.
Also the Server cannot know if the player is using a moneyhack or actually stunting.

With this script, stunts can be performed anywhere, as long as the objects are added to CA's collision world.

Until now, the Script is able to detect the Jump's duration, distance, Saltos, Barrel Rolls and 360 Turns, and also features Stunt-Combos.
Passengers of stunting drivers will also see a message about the stunt, but receive no reward.

Config defines and most of the functions are explained inside the script.


To run this script, you need the foreach include, the ColAndreas plugin and the rotations.inc include by Nero_3D.

Credits:

Thanks to everyone who contributed to foreach, ColAndreas and rotations.inc.
