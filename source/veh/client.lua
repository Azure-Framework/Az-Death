local effectActive = false            -- Indicates if the screen effect is active
local blackoutActive = false          -- Indicates if blackout effect is active
local currentAccidentLevel = 0        -- Current accident level
local wasInCar = false
local oldBodyDamage = 0.0
local oldSpeed = 0.0
local currentDamage = 0.0
local currentSpeed = 0.0
local vehicle
local disableControls = false

local function isCar(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)
    return (vehicleClass >= 0 and vehicleClass <= 7) or 
           (vehicleClass >= 9 and vehicleClass <= 12) or 
           (vehicleClass >= 17 and vehicleClass <= 20)
end 

local function notify(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(text)
    DrawNotification(false, false)
end

RegisterNetEvent("crashEffect")
AddEventHandler("crashEffect", function(countDown, accidentLevel)
    if not effectActive or (accidentLevel > currentAccidentLevel) then
        currentAccidentLevel = accidentLevel
        disableControls = true
        effectActive = true
        blackoutActive = true
        DoScreenFadeOut(100)
        Wait(Config.BlackoutTime)
        DoScreenFadeIn(250)
        blackoutActive = false

        -- Start screen effects
        StartScreenEffect('PeyoteEndOut', 0, true)
        StartScreenEffect('Dont_tazeme_bro', 0, true)
        StartScreenEffect('MP_race_crash', 0, true)
    
        while countDown > 0 do
            if countDown > (3.5 * accidentLevel)   then 
                ShakeGameplayCam("MEDIUM_EXPLOSION_SHAKE", (accidentLevel * Config.ScreenShakeMultiplier))
            end 
            Wait(750)
            countDown = countDown - 1

            if countDown < Config.TimeLeftToEnableControls and disableControls then
                disableControls = false
            end
            
            if countDown <= 1 then
                StopScreenEffect('PeyoteEndOut')
                StopScreenEffect('Dont_tazeme_bro')
                StopScreenEffect('MP_race_crash')
            end
        end
        currentAccidentLevel = 0
        effectActive = false
    end
end)

Citizen.CreateThread(function()
	while true do
        Citizen.Wait(10)
        
        vehicle = GetVehiclePedIsIn(PlayerPedId(-1), false)
        if DoesEntityExist(vehicle) and (wasInCar or isCar(vehicle)) then
            wasInCar = true
            oldSpeed = currentSpeed
            oldBodyDamage = currentDamage
            currentDamage = GetVehicleBodyHealth(vehicle)
            currentSpeed = GetEntitySpeed(vehicle) * 2.23

            if currentDamage ~= oldBodyDamage then
                if not effectActive and currentDamage < oldBodyDamage then
                    if (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel5 or
                       (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel5
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel5, 5)

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel4 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel4
                    then
                        TriggerEvent("crashEffect", Config.EffectTimeLevel4, 4)
                        oldBodyDamage = currentDamage

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel3 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel3
                    then   
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel3, 3)
                        
                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel2 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel2
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel2, 2)

                    elseif (oldBodyDamage - currentDamage) >= Config.BlackoutDamageRequiredLevel1 or
                           (oldSpeed - currentSpeed) >= Config.BlackoutSpeedRequiredLevel1
                    then
                        oldBodyDamage = currentDamage
                        TriggerEvent("crashEffect", Config.EffectTimeLevel1, 1)
                    end
                end
            end
        elseif wasInCar then
            wasInCar = false
            currentDamage = 0
            oldBodyDamage = 0
            currentSpeed = 0
            oldSpeed = 0
        end
            
        if disableControls and Config.DisableControlsOnBlackout then
            -- Controls to disable while player is on blackout
			DisableControlAction(0, 71, true) -- Vehicle forward
			DisableControlAction(0, 72, true) -- Vehicle backwards
			DisableControlAction(0, 63, true) -- Vehicle turn left
			DisableControlAction(0, 64, true) -- Vehicle turn right
			DisableControlAction(0, 75, true) -- Disable exit vehicle
		end
	end
end)
