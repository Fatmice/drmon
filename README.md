
![](examples/2.jpg)
> *status*: currently stable, writing documentation


# drmon
Monitor and failsafe automation for your draconic reactor

### what is this
This is a computercraft LUA script that monitors everything about a draconic reactor, with a couple features to help keep it from exploding
NB: This is for Minecraft 1.21.1. You will need to edit references within the code for any version higher to reflect any changes made to Draconic Evolution past its 1.21.1 release.


### tutorial
You can find a very well made youtube tutorial on how to set this up
* [1](https://www.youtube.com/watch?v=jBgXRTL9EkE), by [Brandon3055](https://www.youtube.com/@Brandon3055)
* [2](https://www.youtube.com/watch?v=r9pRXcwtEGk), by [zzApotheosis](https://www.youtube.com/@zzApotheosis)
* [3](https://www.youtube.com/watch?v=nOoDNpVh2ww), by [To Asgaard](https://www.youtube.com/@ToAsgaard)
* [4](https://www.youtube.com/watch?v=8rBhQP1xqEU) , by [The MindCrafters](https://www.youtube.com/channel/UCf2wEy4_BbYpAQcgvN26OaQ)
* [5](https://www.youtube.com/watch?v=-BM9F3Bz-9w), by [direwolf20](https://www.youtube.com/@direwolf20)
* [6](https://www.youtube.com/watch?v=RSQ-GDJgAKk), by [Lashmak](https://www.youtube.com/@Lashmak)
* [7](https://www.youtube.com/watch?v=poKzJBhZoVM), by [JaviHerobrine](https://www.youtube.com/@JaviHerobrine)
* [8](https://www.youtube.com/watch?v=zrIOkNlaLiQ), by [ShaneyFangzz](https://www.youtube.com/@ShaneyFangzz)


### features
* uses a 3x3 advanced computer touchscreen monitor to interact with your reactor
* automated regulation of the input gate for the targeted field strength of 25%
  * adjustable
* immediate shutdown and charge upon your field strength going below 10%
  * adjustable
  * reactor will activate upon a successful charge
* immediate shutdown when your temperature goes above 8000C
  * adjustable
  * reactor will activate upon temperature cooling down to 3500C
    * adjustable
* easily tweak your output flux gate via touchscreen buttons
  * +/-100k, 10k, and 1k increments

### requirements
* one fully setup draconic reactor with fuel
* 1 advanced computer
* 9 advanced monitors
* 3 wired modems, wireless will not work
* a bunch of network cable

### installation
* Injector at the bottom. Stabilizers on the 4 ordinals. They need to be at least 6 blocks away from the core.
* Attach a flux gate to the injector at the bottom and at least one more flux gate to the stabilizers.
* Attach an advanced computer to the back of a free stabilize. To one of the side, either left or right, attach the 9 advanced monitor
  * Optional: You can attach a redstone triggered device to the top of the computer that can wrap up the reactor in the event of a metldown. An example is the Advanced Clicker from Just Dire Things setup with cardboard boxes from Mekanism.
* Attach wired modems to the bottom of the computer and flux gates
* After wiring them up with network cable, right click on each to add it to the network.
* Take note of the flow_gate_# associated with the injector (input) and stabilizer (output) that have the flux gates. 
* Install this code via running the install script using these commands :

```
> wget https://raw.githubusercontent.com/Fatmice/drmon/refs/heads/master/install.lua install
> install
```
* modify `startup` to alter any variables holding the flow_gate_# for input and output, you'll find them at the top of the file
```
> startup
```
* you should see stats in your term, and on your monitor once the reactor is valid and has fuel in it.

### upgrading to the latest version
* right click your computer
* hold ctrl+t until you get a `>`

```
> install
> startup
```

### known issues
* For Minecraft 1.21.1, if you use shaders, then the reactor core will not show up once you place it down. You will probably will need a [shader fix](https://www.curseforge.com/minecraft/mc-mods/draconic-evolution-render-patcher)
