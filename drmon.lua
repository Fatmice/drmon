-- modifiable variables
local reactorSide			= "back"
local monitorSide			= "left"
local outputFluxGate		= "flow_gate_3"
local inputFluxGate			= "flow_gate_4"
local deployMitigation		= "top"

 -- important constants
local maxTemperature		= 8000		-- temperature to emergency stop
local targetTemperature		= 7950		-- temperature to hold reactor at
local safeTemperature		= 3500		-- temperature to restart reactor after emergency stop
local reactorFactor			= 1			-- This is reactorFactor from brand3055 config
local targetStrength		= 25		-- lower = more efficient, but less safe
local targetSatPercent		= 10		-- recommended 10 at minimum
local lowestSatPercent		= 5			-- recommended 5 at minimum
local lowestFieldPercent	= 10		-- recommended 10 at minimum
local refuelTargetPercent	= 5			-- Tickle the dragon
local activateOnCharged		= 1

-- please leave things untouched from here on
os.loadAPI("lib/f")

local version				= "0.26"

-- toggleable via the monitor, use our algorithm to achieve our target field strength or let the user tweak it
local autoInputGate			= 1
local curInputGate			= 222000

-- working constants
local tempFactor			= math.min((targetTemperature / 10000) * 50, 99)
local radiationPressure		= (tempFactor * tempFactor * tempFactor * tempFactor) / (100 - tempFactor)
local temperatureOffset		= 444.7		-- DO NOT Change!
local expoAdjustments		= 650
local fineAdjustments		= 25
local underCount			= 0
local overCount				= 0
local saveTrigger			= 0

-- auto output gate control
local autoOutputGate		= 1			-- 1 = auto, 0 = manual
local fuelPercent

-- monitor
local mon, monitor, monX, monY

-- peripherals
local reactor
local fluxgate
local inputfluxgate

-- reactor information
local ri

-- last performed action
local action			= "None since reboot"
local emergencyCharge	= false
local emergencyTemp		= false
local newReactorChecked	= false

-- wrap the peripherals
monitor					= peripheral.wrap(monitorSide)
reactor					= peripheral.wrap(reactorSide)
inputfluxgate			= peripheral.wrap(inputFluxGate)
fluxgate				= peripheral.wrap(outputFluxGate)

if monitor == nil then
	error("No valid monitor was found")
end

if fluxgate == nil then
	error("No valid fluxgate was found")
end

if reactor == nil then
	error("No valid reactor was found")
end

if inputfluxgate == nil then
	error("No valid flux gate was found")
end

monX, monY = monitor.getSize()
mon = {}
mon.monitor, mon.X, mon.Y = monitor, monX, monY

-- set up monitor and disable cursor blink
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.clear()

-- create a hidden buffer (same size as monitor)
local win = window.create(monitor, 1, 1, monX, monY)
win.setVisible(false)

-- redirect all drawing to the buffer instead of directly to the monitor
mon.monitor = win

-- write settings to config file
function save_config()
	local sw = fs.open("config.txt", "w")
	sw.writeLine(version)
	sw.writeLine(autoInputGate)
	sw.writeLine(curInputGate)
	sw.writeLine(expoAdjustments)
	sw.writeLine(fineAdjustments)
	sw.close()
end

-- read settings from file
function load_config()
	local sr		= fs.open("config.txt", "r")
	version			= sr.readLine()
	autoInputGate	= tonumber(sr.readLine())
	curInputGate	= tonumber(sr.readLine())
	expoAdjustments	= tonumber(sr.readLine())
	fineAdjustments	= tonumber(sr.readLine())
	sr.close()
end

-- 1st time? save our settings, if not, load our settings
if fs.exists("config.txt") == false then
	save_config()
else
	load_config()
end

function buttons()
	while true do
	-- button handler
	local event, side, xPos, yPos = os.pullEvent("monitor_touch")

	----------------------------------------------------------------
	-- OUTPUT GATE: manual controls + AU/MA toggle on row 8
	----------------------------------------------------------------
	-- 2-4 = -1000, 6-9 = -10000, 10-12 = -100000
	-- 17-19 = +100000, 21-23 = +10000, 25-27 = +1000
	-- 14-15 = AU/MA toggle
	if yPos == 8 then
		-- toggle auto / manual for OUTPUT gate
		if xPos == 14 or xPos == 15 then
			if autoOutputGate == 1 then
				autoOutputGate = 0
		else
			autoOutputGate = 1
		end
		-- manual adjustments only when in MA mode
		elseif autoOutputGate == 0 then
			local cFlow = fluxgate.getSignalLowFlow()
			if xPos >= 2 and xPos <= 4 then
				cFlow = cFlow - 1000
			elseif xPos >= 6 and xPos <= 9 then
				cFlow = cFlow - 10000
			elseif xPos >= 10 and xPos <= 12 then
				cFlow = cFlow - 100000
			elseif xPos >= 17 and xPos <= 19 then
				cFlow = cFlow + 100000
			elseif xPos >= 21 and xPos <= 23 then
				cFlow = cFlow + 10000
			elseif xPos >= 25 and xPos <= 27 then
				cFlow = cFlow + 1000
			end
			fluxgate.setSignalLowFlow(cFlow)
		end
	end

	----------------------------------------------------------------
	-- INPUT GATE: existing manual controls + AU/MA toggle
	----------------------------------------------------------------
	-- 2-4 = -1000, 6-9 = -10000, 10-12 = -100000
	-- 17-19 = +100000, 21-23 = +10000, 25-27 = +1000
	if yPos == 10 and autoInputGate == 0 and xPos ~= 14 and xPos ~= 15 then
		if xPos >= 2 and xPos <= 4 then
			curInputGate = curInputGate - 1000
		elseif xPos >= 6 and xPos <= 9 then
			curInputGate = curInputGate - 10000
		elseif xPos >= 10 and xPos <= 12 then
			curInputGate = curInputGate - 100000
		elseif xPos >= 17 and xPos <= 19 then
			curInputGate = curInputGate + 100000
		elseif xPos >= 21 and xPos <= 23 then
			curInputGate = curInputGate + 10000
		elseif xPos >= 25 and xPos <= 27 then
			curInputGate = curInputGate + 1000
		end
		inputfluxgate.setSignalLowFlow(curInputGate)
		save_config()
	end

	-- input gate toggle
	if yPos == 10 and (xPos == 14 or xPos == 15) then
		if autoInputGate == 1 then
			autoInputGate = 0
		else
			autoInputGate = 1
		end
		save_config()
	end

  end
end

function drawButtons(y)
	-- 2-4 = -1000, 6-9 = -10000, 10-12 = -100000
	-- 17-19 = +100000, 21-23 = +10000, 25-27 = +1000

	f.draw_text(mon, 2,  y, " < ",  colors.white, colors.gray)
	f.draw_text(mon, 6,  y, " <<",  colors.white, colors.gray)
	f.draw_text(mon, 10, y, "<<<",  colors.white, colors.gray)

	f.draw_text(mon, 17, y, ">>>",  colors.white, colors.gray)
	f.draw_text(mon, 21, y, ">> ",  colors.white, colors.gray)
	f.draw_text(mon, 25, y, " > ",  colors.white, colors.gray)
end

function update()
	while true do

		f.clear(mon)

		ri = reactor.getReactorInfo()

		-- print out all the infos from .getReactorInfo() to term

		if ri == nil then
			error("reactor has an invalid setup")
		end

		for k, v in pairs(ri) do
			print(k .. ": " .. tostring(v))
		end
		print("Output Gate: ", fluxgate.getSignalLowFlow())
		print("Input Gate: ", inputfluxgate.getSignalLowFlow())

		-- monitor output

		local statusColor = colors.red

		if ri.status == "running" or ri.status == "charged" then
			statusColor = colors.green
		elseif ri.status == "cold" then
			statusColor = colors.gray
		elseif ri.status == "charging" or ri.status == "warming_up" then
			statusColor = colors.orange
		end

		f.draw_text_lr(mon, 2, 2, 1, "Reactor Status",
					   string.upper(ri.status),
					   colors.white, statusColor, colors.black)

		f.draw_text_lr(mon, 2, 4, 1, "Generation",
					   f.format_int(ri.generationRate) .. " fe/t",
					   colors.white, colors.lime, colors.black)

		local tempColor = colors.red
		if ri.temperature <= 5000 then tempColor = colors.green end
		if ri.temperature >= 5000 and ri.temperature <= 6500 then tempColor = colors.orange end
		f.draw_text_lr(mon, 2, 6, 1, "Temperature",
					   f.format_int(ri.temperature) .. "C",
					   colors.white, tempColor, colors.black)

		f.draw_text_lr(mon, 2, 7, 1, "Output Gate",
					   f.format_int(fluxgate.getSignalLowFlow()) .. " rf/t",
					   colors.white, colors.blue, colors.black)

		-- OUTPUT GATE AU/MA indicator + buttons
		if autoOutputGate == 1 then
			f.draw_text(mon, 14, 8, "AU", colors.white, colors.gray)
			-- no manual buttons in auto mode
		else
			f.draw_text(mon, 14, 8, "MA", colors.white, colors.gray)
			drawButtons(8)
		end

		f.draw_text_lr(mon, 2, 9, 1, "Input Gate",
					   f.format_int(inputfluxgate.getSignalLowFlow()) .. " rf/t",
					   colors.white, colors.blue, colors.black)

		if autoInputGate == 1 then
			f.draw_text(mon, 14, 10, "AU", colors.white, colors.gray)
		else
			f.draw_text(mon, 14, 10, "MA", colors.white, colors.gray)
			drawButtons(10)
		end

		local satPercent
		satPercent = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000) * 0.01

		f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation",
					   satPercent .. "%", colors.white, colors.white, colors.black)
		f.progress_bar(mon, 2, 12, mon.X - 2, satPercent, 100, colors.blue, colors.gray)

		local fieldPercent, fieldColor
		fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000) * 0.01

		fieldColor = colors.red
		if fieldPercent >= 50 then fieldColor = colors.green end
		if fieldPercent < 50 and fieldPercent > 30 then fieldColor = colors.orange end

		if autoInputGate == 1 then
			f.draw_text_lr(mon, 2, 14, 1, "Field Strength T:" .. targetStrength,
						   fieldPercent .. "%", colors.white, fieldColor, colors.black)
		else
			f.draw_text_lr(mon, 2, 14, 1, "Field Strength",
						   fieldPercent .. "%", colors.white, fieldColor, colors.black)
		end
		f.progress_bar(mon, 2, 15, mon.X - 2, fieldPercent, 100, fieldColor, colors.gray)

		local fuelColor
		fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000) * 0.01

		fuelColor = colors.red
		if fuelPercent >= 70 then fuelColor = colors.green end
		if fuelPercent < 70 and fuelPercent > 30 then fuelColor = colors.orange end

		f.draw_text_lr(mon, 2, 17, 1, "Fuel ",
					   fuelPercent .. "%", colors.white, fuelColor, colors.black)
		f.draw_text(mon, 7,17, ri.fuelConversionRate .. " nB/t", colors.white, colors.black)
		f.progress_bar(mon, 2, 18, mon.X - 2, fuelPercent, 100, fuelColor, colors.gray)

		f.draw_text_lr(mon, 2, 19, 1, "Action ",
					   action, colors.gray, colors.gray, colors.black)

		print("Emergency Charge: " .. tostring(emergencyCharge))
		print("Emergency Temp: " .. tostring(emergencyTemp))
		----------------------------------------------------------------
		-- ACTUAL REACTOR INTERACTION
		----------------------------------------------------------------
		if emergencyCharge == true and ri.status == "stopping" then
			if fieldPercent >= targetStrength and satPercent >= targetSatPercent and ri.temperature >= 2000 then
				reactor.activateReactor()
				emergencyCharge = false
			else
				reactor.chargeReactor()
			end
		end

		-- are we charging? open the floodgates
		if ri.status == "charging" or ri.status == "warming_up" then
			inputfluxgate.setSignalLowFlow(900000)
			emergencyCharge = false
		end

		-- are we stopping from a emergency shutdown and our temp is better? activate
		if emergencyTemp == true and (ri.status == "stopping" or ri.status == "cold") and ri.temperature < safeTemperature then
			if ri.failSafe and satPercent >= 99 then
				reactor.toggleFailSafe()
			end
				reactor.activateReactor()
				emergencyTemp = false
		end

		-- are we charged? lets activate
		if (ri.status == "charged" or (ri.status == "warming_up" and ri.temperature >= 2000)) and activateOnCharged == 1 then
			if ri.failSafe and satPercent >= 99 then
				reactor.toggleFailSafe()
			end
				reactor.activateReactor()
		end

		-- are we on? regulate the input fluxgate to our target field strength
		-- or set it to our saved setting since we are on manual
		if ri.status == "running" or ri.status == "stopping" then
			if autoInputGate == 1 then
				curInputGate = ri.fieldDrainRate / (1 - (targetStrength / 100))
				print("Target Gate: " .. curInputGate)
				inputfluxgate.setSignalLowFlow(curInputGate)
			else
				inputfluxgate.setSignalLowFlow(curInputGate)
			end
		end

		----------------------------------------------------------------
		-- AUTO OUTPUT GATE LOGIC
		----------------------------------------------------------------
		if autoOutputGate == 1 and ri.status == "running" then
			------ Find the current fuel conversion factor
			local conversionLeveL = ((ri.fuelConversion / ri.maxFuelConversion) * 1.3) - 0.3
			local radiativeHeat = -(((conversionLeveL - 1) * radiationPressure) + (1000 * conversionLeveL))

			------ Solve depressed cubic for zero
			------ https://uniteasy.com/post/1287/
			local coefficient1 =  radiativeHeat - temperatureOffset
			local coefficient2 = -(100 * coefficient1)
			local r1 = -(coefficient2 / 2)
			local r2 = (coefficient2 * coefficient2) / 4
			local r3 = (coefficient1 * coefficient1 * coefficient1) / 27
			------ Need to do this nonsense due to C implementation of the power function returning NaN for negative number
			function root(number, exponent)
				if number >= 0 then
					return number ^ (exponent)
				else
					return -((math.abs(number)) ^ (exponent))
				end
			end
			local radicant1 = r1 + root((r2 + r3), (1 / 2))
			local radicant2 = r1 - root((r2 + r3), (1 / 2))
			local zero = root(radicant1, (1 / 3)) + root(radicant2, (1 / 3))

			------ Find corresponding saturation
			local percent = 1 - (zero / 99)
			local desiredSaturation = math.floor(percent * ri.maxEnergySaturation)
			local desiredCoreSaturation = desiredSaturation / ri.maxEnergySaturation
			local differenceInSaturation = ri.energySaturation - desiredSaturation
			local scale = differenceInSaturation / desiredSaturation
			local normalizationFactor =  differenceInSaturation / (ri.maxEnergySaturation - desiredSaturation)

			------ Find corresponding generation
			local maxGeneration = (ri.maxEnergySaturation / 1000) * reactorFactor * 1.5 * 10 * (conversionLeveL * 2 + 1)
			local desiredGeneration = (1 - desiredCoreSaturation) * maxGeneration

			------ Find the corresponding output with respect to the current saturation
			local desiredFlow = 0
			local coarseAdjustments = 0
			if satPercent > targetSatPercent then
				coarseAdjustments = scale * normalizationFactor * math.exp(-scale) + 1
				desiredFlow = desiredGeneration * coarseAdjustments
				--print("adjustment1: " ..  coarseAdjustments)
			else
				coarseAdjustments = - (scale * normalizationFactor * math.exp(-normalizationFactor)) + 1
				desiredFlow = desiredGeneration * coarseAdjustments
				--print("adjustment2: " .. coarseAdjustments)
			end

			------ Keep temperature near targetTemperature while staying above targetSatPercent
			local setFlow = fluxgate.getSignalLowFlow() or 0
			local epsilon = (ri.temperature - targetTemperature) / targetTemperature

			if math.abs(epsilon * 10000) <= 5 then
				expoAdjustments = math.abs(desiredFlow - desiredGeneration) * math.exp(epsilon)
				desiredFlow = desiredFlow - expoAdjustments
				--print("desiredFlow1: " .. desiredFlow)
			else
				expoAdjustments = math.min(math.abs(desiredFlow - desiredGeneration) * (1 - math.abs(epsilon)), 10000)
				desiredFlow = desiredFlow - expoAdjustments
				--print("desiredFlow2: " .. desiredFlow)
			end
			--print("expoAdjustments: " .. expoAdjustments)
			--print("desiredGeneration: " .. desiredGeneration)

			if math.abs(epsilon * 1000000) > 1 then
				if ri.temperature <= targetTemperature then
					underCount = underCount + 1
					if math.mod(underCount,6) == 5 then
						fineAdjustments = fineAdjustments - 1
					end
					print("underCount: " .. underCount)
					overCount = 0
				else
					overCount = overCount + 1
					if math.mod(overCount,6) == 5 then
						fineAdjustments = fineAdjustments + 1
					end
					print("overCount: " .. overCount)
					underCount = 0
				end
			end
			setFlow = (desiredFlow - fineAdjustments)
			fluxgate.setSignalLowFlow(setFlow)
			print("epsilon: " .. (epsilon * 1000000))
			print("fineAdjustments: " .. fineAdjustments)
			print("SetFlow: " .. setFlow)
			saveTrigger = saveTrigger + 1
			if saveTrigger > 599 then
				save_config()
				saveTrigger = 0
			end
		end

		----------------------------------------------------------------
		-- Reactor Calculations
		-- Reactor performance:	https://www.desmos.com/calculator/avlmj7nqpb
		-- Net production:	https://www.desmos.com/calculator/jyd8ptuij3
		----------------------------------------------------------------

		----------------------------------------------------------------
		-- SAFEGUARDS
		----------------------------------------------------------------
		-- out of fuel, kill it
		if fuelPercent <= refuelTargetPercent and ri.status == "running" then
			reactor.stopReactor()
			action = "Fuel below " .. refuelTargetPercent .."%, refuel"
		end

		-- field strength is too dangerous, kill and try and charge it before it blows
		if fieldPercent <= lowestFieldPercent and ri.status == "running" then
			action = "Field Str < " .. lowestFieldPercent .. "%"
			reactor.stopReactor()
			reactor.chargeReactor()
			emergencyCharge = true
		end

		-- core saturation is too dangerous, kill and try and charge it before it blows
		if satPercent <= lowestSatPercent and ri.status == "running" then
			action = "Core Sat < " .. lowestSatPercent .. "%"
			reactor.stopReactor()
			reactor.chargeReactor()
			emergencyCharge = true
		end

		-- temperature too high, kill it and activate it when its cool
		if ri.temperature > maxTemperature then
			reactor.stopReactor()
			action = "Temp > " .. maxTemperature
			emergencyTemp = true
		end

		-- blow up? Place a cardboard box
		if ri.status == "beyond_hope" then
			action = "Reactor Meltdown! Mitigation deployed!"
			redstone.setOutput(deployMitigation, true)
			sleep(1)
			redstone.setOutput(deployMitigation, false)
		else
			redstone.setOutput(deployMitigation, false)
		end

		-- flip buffer
		win.setVisible(true)
		win.redraw()
		win.setVisible(false)

		----------------------------------------------------------------
		-- NEW REACTOR CHECK (run once per boot)
		----------------------------------------------------------------
		if (not newReactorChecked) then
			-- brand-new core: 100% fuel remaining
			if fuelPercent >= 99.9 then
				fluxgate.setSignalLowFlow(3000000)
				inputfluxgate.setSignalLowFlow(222000)
				curInputGate = 222000        -- also reset manual input setting
				autoInputGate = 1
				autoOutputGate = 1
			end
			newReactorChecked = true
		end
		if ri.status == "cooling" or ri.status == "stopping" or ri.status == "cold" then
			cFlow = 3000000
			fluxgate.setSignalLowFlow(cFlow)
			newReactorChecked = false
			if (not ri.failSafe) and ri.temperature <= 3000 and satPercent >= 99 then
				reactor.toggleFailSafe()
			end
		end
		if ri.status == "cold" then
			inputfluxgate.setSignalLowFlow(0)
		end

		sleep(0.1)
	end
end

parallel.waitForAny(buttons, update)
