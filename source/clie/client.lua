local InjuryCfg      = Config.Injury or {}
local InjuriesByZone = {}
local overlayPinned  = false
local wasDead        = false

-- fall tracking
local lastFallTime   = 0

-- bleeding
local bleedingLevel  = 0 -- 0–3
local bleedingActive = false
local nextBleedTick  = 0

-- hospital
local isBeingTreated = false

local function dbg(...)
    if InjuryCfg.Debug then
        print('[az_injury]', ...)
    end
end

local BoneMap = {
    [31086] = { zone = 'Head',      label = 'Skull' },
    [31085] = { zone = 'Head',      label = 'Head' },
    [39317] = { zone = 'Head',      label = 'Neck' },

    [24816] = { zone = 'Torso',     label = 'Lower spine' },
    [24817] = { zone = 'Torso',     label = 'Mid spine' },
    [24818] = { zone = 'Torso',     label = 'Upper spine' },
    [11816] = { zone = 'Torso',     label = 'Pelvis' },

    [18905] = { zone = 'Left Arm',  label = 'Hand' },
    [6286]  = { zone = 'Left Arm',  label = 'Forearm' },
    [45509] = { zone = 'Left Arm',  label = 'Upper arm' },

    [57005] = { zone = 'Right Arm', label = 'Hand' },
    [28422] = { zone = 'Right Arm', label = 'Forearm' },
    [40269] = { zone = 'Right Arm', label = 'Upper arm' },

    [14201] = { zone = 'Left Leg',  label = 'Foot' },
    [36864] = { zone = 'Left Leg',  label = 'Calf' },
    [58271] = { zone = 'Left Leg',  label = 'Thigh' },

    [52301] = { zone = 'Right Leg', label = 'Foot' },
    [65245] = { zone = 'Right Leg', label = 'Calf' },
    [51826] = { zone = 'Right Leg', label = 'Thigh' }
}

local function fallbackZoneFromBone(bone)
    if bone == 31086 or bone == 31085 or bone == 39317 then
        return 'Head'
    elseif bone == 24816 or bone == 24817 or bone == 24818 or bone == 11816 then
        return 'Torso'
    end
    return 'Torso'
end

local function getZoneAndBoneLabel(bone)
    local info = BoneMap[bone]
    if info then
        return info.zone, info.label
    end
    return fallbackZoneFromBone(bone), ('Bone #%d'):format(bone or -1)
end

local function makeHashSet(list)
    local t = {}
    for _, name in ipairs(list or {}) do
        t[GetHashKey(name)] = true
    end
    return t
end

local meleeSet   = makeHashSet(Config.InjuryMeleeWeapons   or {})
local fallSet    = makeHashSet(Config.InjuryFallWeapons    or {})
local vehicleSet = makeHashSet(Config.InjuryVehicleWeapons or {})

local explosionSet = makeHashSet({
    'WEAPON_GRENADE','WEAPON_STICKYBOMB','WEAPON_PROXMINE',
    'WEAPON_RPG','WEAPON_HOMINGLAUNCHER','WEAPON_GRENADELAUNCHER',
    'WEAPON_EXPLOSION','WEAPON_HELI_CRASH'
})

local fireSet = makeHashSet({
    'WEAPON_MOLOTOV','WEAPON_FIRE','WEAPON_FLARE',
    'WEAPON_FLAREGUN','WEAPON_PETROLCAN'
})

local taserSet = makeHashSet({
    'WEAPON_STUNGUN','WEAPON_STUNGUN_MP'
})

local gasSet = makeHashSet({
    'WEAPON_SMOKEGRENADE'
})

local envSet = makeHashSet({
    'WEAPON_DROWNING','WEAPON_DROWNING_IN_VEHICLE',
    'WEAPON_EXHAUSTION','WEAPON_BARBED_WIRE'
})

local animalSet = makeHashSet({
    'WEAPON_ANIMAL','WEAPON_COUGAR'
})

local GROUP_MELEE      = GetHashKey('GROUP_MELEE')
local GROUP_PISTOL     = GetHashKey('GROUP_PISTOL')
local GROUP_SMG        = GetHashKey('GROUP_SMG')
local GROUP_RIFLE      = GetHashKey('GROUP_RIFLE')
local GROUP_MG         = GetHashKey('GROUP_MG')
local GROUP_SHOTGUN    = GetHashKey('GROUP_SHOTGUN')
local GROUP_SNIPER     = GetHashKey('GROUP_SNIPER')
local GROUP_HEAVY      = GetHashKey('GROUP_HEAVY')
local GROUP_THROWN     = GetHashKey('GROUP_THROWN')
local GROUP_PETROLCAN  = GetHashKey('GROUP_PETROLCAN')

local function notify(title, msg, ntype)
    if InjuryCfg.UseOxLibNotify and lib and lib.notify then
        lib.notify({
            title       = title or 'Injury',
            description = msg or '',
            type        = ntype or 'inform',
            duration    = InjuryCfg.NotifyDuration or 6000
        })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName((title and (title .. ' ~n~') or '') .. (msg or ''))
        EndTextCommandThefeedPostTicker(false, false)
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then
            goto continue
        end

        local _, _, vz = table.unpack(GetEntityVelocity(ped))
        if vz < -6.0 and IsPedOnFoot(ped) and not IsPedInAnyVehicle(ped, false) then
            if IsPedRagdoll(ped) or HasEntityCollidedWithAnything(ped) then
                lastFallTime = GetGameTimer()
            end
        end

        ::continue::
    end
end)

local function classifyDamage(ped, weaponHash, attacker)
    local now   = GetGameTimer()
    local group = GetWeapontypeGroup(weaponHash)

    dbg('classifyDamage', weaponHash, group)

    -- VEHICLE
    local viaVehicle = false
    if vehicleSet[weaponHash] then
        viaVehicle = true
    elseif attacker and attacker ~= 0 then
        if IsEntityAVehicle(attacker) then
            viaVehicle = true
        elseif IsEntityAPed(attacker) and IsPedInAnyVehicle(attacker, false) then
            viaVehicle = true
        end
    end
    if viaVehicle then
        return 'Vehicle collision'
    end

    -- FALL / ENV
    if fallSet[weaponHash] then
        return 'Fall injury'
    end

    if envSet[weaponHash] then
        if weaponHash == GetHashKey('WEAPON_DROWNING') or weaponHash == GetHashKey('WEAPON_DROWNING_IN_VEHICLE') then
            return 'Drowning'
        elseif weaponHash == GetHashKey('WEAPON_EXHAUSTION') then
            return 'Exhaustion'
        elseif weaponHash == GetHashKey('WEAPON_BARBED_WIRE') then
            return 'Lacerations'
        else
            return 'Environmental trauma'
        end
    end

    if (now - lastFallTime) < 3000 then
        return 'Fall injury'
    end

    -- TASER
    if taserSet[weaponHash] then
        return 'Taser'
    end

    -- EXPLOSIONS
    if explosionSet[weaponHash] or group == GROUP_THROWN or group == GROUP_HEAVY then
        return 'Explosion injury'
    end

    -- FIRE / BURNS
    if fireSet[weaponHash] or group == GROUP_PETROLCAN or IsEntityOnFire(ped) then
        return 'Burns'
    end

    -- GAS / SMOKE
    if gasSet[weaponHash] then
        return 'Gas / smoke inhalation'
    end

    -- ANIMALS
    if animalSet[weaponHash] then
        return 'Animal attack'
    end

    -- MELEE / BLUNT
    if meleeSet[weaponHash] or group == GROUP_MELEE or weaponHash == GetHashKey('WEAPON_UNARMED') then
        return 'Blunt trauma'
    end

    -- FIREARMS (GSW)
    if group == GROUP_PISTOL or group == GROUP_SMG or group == GROUP_RIFLE
       or group == GROUP_MG or group == GROUP_SHOTGUN or group == GROUP_SNIPER then
        return 'Gunshot wound'
    end

    return 'Trauma'
end


-- SEVERITY

local function severityFromHealth(health)
    local ped = PlayerPedId()
    local maxHealth = GetEntityMaxHealth(ped)
    health = math.max(0, health)
    local pct = health / math.max(1, maxHealth)

    if pct <= 0.25 then
        return 'Critical', 3
    elseif pct <= 0.55 then
        return 'Severe', 2
    elseif pct <= 0.8 then
        return 'Moderate', 1
    else
        return 'Minor', 0
    end
end


-- BLEEDING

local function getBleedingLevel()
    return bleedingLevel or 0
end

local function addBleeding(extraLevel)
    if not (InjuryCfg.Bleeding and InjuryCfg.Bleeding.enabled) then return end
    extraLevel = extraLevel or 1
    bleedingLevel = math.min(3, bleedingLevel + extraLevel)
    bleedingActive = true
    local baseInt = InjuryCfg.Bleeding.baseInterval or 8000
    nextBleedTick  = GetGameTimer() + baseInt
    dbg('Bleeding level now', bleedingLevel)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(250)

        if not bleedingActive or not (InjuryCfg.Bleeding and InjuryCfg.Bleeding.enabled) then
            goto continue
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedFatallyInjured(ped) then
            goto continue
        end

        local now = GetGameTimer()
        if now >= nextBleedTick and bleedingLevel > 0 then
            local baseInt = InjuryCfg.Bleeding.baseInterval or 8000
            local minInt  = InjuryCfg.Bleeding.minInterval or 3500
            local interval = math.max(minInt, baseInt - (bleedingLevel-1) * 1500)
            nextBleedTick = now + interval

            local baseDmg = InjuryCfg.Bleeding.baseDamage or 4
            local perLvl  = InjuryCfg.Bleeding.perLevelDamage or 3
            local dmg     = baseDmg + (bleedingLevel-1) * perLvl

            local hp = GetEntityHealth(ped)
            local newHp = hp - dmg
            if newHp < 5 then newHp = 5 end
            SetEntityHealth(ped, newHp)

            dbg('Bleeding tick', bleedingLevel, 'hp', hp, '->', newHp)
        end

        ::continue::
    end
end)


-- INJURY STORAGE + UI

local function addInjury(zone, boneLabel, injuryType, details, severityLevel)
    InjuriesByZone[zone] = InjuriesByZone[zone] or { zone = zone, wounds = {} }

    table.insert(InjuriesByZone[zone].wounds, {
        type     = injuryType,
        details  = details or '',
        bone     = boneLabel or nil,
        severity = severityLevel or 0,
        time     = GetGameTimer()
    })

    -- start bleeding on open/bloody injuries
    if injuryType == 'Gunshot wound'
    or injuryType == 'Lacerations'
    or injuryType == 'Explosion injury'
    or injuryType == 'Animal attack'
    then
        local bleedAdd = 1
        if severityLevel >= 2 then bleedAdd = 2 end
        if severityLevel >= 3 then bleedAdd = 3 end
        addBleeding(bleedAdd)
    end

    local display = boneLabel and (zone .. ' — ' .. boneLabel) or zone
    notify('Injury', injuryType .. ' — ' .. display, 'error')
end

local function clearAllInjuries()
    InjuriesByZone = {}
    local ped = PlayerPedId()
    ResetPedMovementClipset(ped, 0.0)
    ResetPedStrafeClipset(ped)
    ResetPedWeaponMovementClipset(ped)

    SendNUIMessage({
        type      = 'injury:update',
        injuries  = {},
        dead      = false,
        pinned    = overlayPinned,
        showAlive = InjuryCfg.ShowOverlayWhenAlive,
        showDead  = InjuryCfg.ShowOverlayWhenDowned,
        bleeding  = { active = false, level = 0 }
    })
end

local function injuriesToUiArray()
    local out = {}
    for _, zoneData in pairs(InjuriesByZone) do
        local entry = { zone = zoneData.zone, wounds = {} }
        for _, w in ipairs(zoneData.wounds) do
            table.insert(entry.wounds, {
                type    = w.type,
                details = w.details,
                bone    = w.bone
            })
        end
        table.insert(out, entry)
    end
    return out
end

local function pushInjuriesToUi()
    if not InjuryCfg.Enabled then return end
    local ped = PlayerPedId()
    local isDead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

    SendNUIMessage({
        type      = 'injury:update',
        injuries  = injuriesToUiArray(),
        dead      = isDead,
        pinned    = overlayPinned,
        showAlive = InjuryCfg.ShowOverlayWhenAlive,
        showDead  = InjuryCfg.ShowOverlayWhenDowned,
        bleeding  = { active = bleedingActive, level = bleedingLevel }
    })
end


-- MOVEMENT / LIMP / RAGDOLL FROM LEG DAMAGE

local function getMaxSeverityForZone(zone)
    local z = InjuriesByZone[zone]
    if not z then return 0 end
    local max = 0
    for _, w in ipairs(z.wounds) do
        if (w.severity or 0) > max then
            max = w.severity or 0
        end
    end
    return max
end

Citizen.CreateThread(function()
    local limpApplied       = false
    local collapseCooldown  = 0
    local limpAnim          = 'move_m@injured'

    while true do
        Citizen.Wait(0)

        if not InjuryCfg.Enabled then
            if limpApplied then
                ResetPedMovementClipset(PlayerPedId(), 0.0)
                limpApplied = false
            end
            goto continue
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedFatallyInjured(ped) then
            if limpApplied then
                ResetPedMovementClipset(ped, 0.0)
                limpApplied = false
            end
            goto continue
        end

        local legSeverity = math.max(
            getMaxSeverityForZone('Left Leg'),
            getMaxSeverityForZone('Right Leg')
        )

        if legSeverity > 0 then
            -- Limp for any leg injury above minor
            if not limpApplied and legSeverity >= 1 then
                RequestAnimSet(limpAnim)
                while not HasAnimSetLoaded(limpAnim) do
                    Citizen.Wait(5)
                end
                SetPedMovementClipset(ped, limpAnim, 1.0)
                limpApplied = true
            end

            -- Severe+ => disable sprint/jump/crouch
            if legSeverity >= 2 then
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 36, true) -- crouch
            end

            -- Critical => occasional collapse
            if legSeverity >= 3 then
                local now = GetGameTimer()
                if now > collapseCooldown and IsPedOnFoot(ped)
                   and not IsPedRagdoll(ped) then
                    SetPedToRagdoll(ped, 3500, 3500, 0, false, false, false)
                    collapseCooldown = now + 15000
                end
            end
        else
            if limpApplied then
                ResetPedMovementClipset(ped, 0.0)
                limpApplied = false
            end
        end

        ::continue::
    end
end)


-- DAMAGE EVENT: CEventNetworkEntityDamage
-- args[1] victim, args[2] attacker, args[6] died bool, args[7] weaponHash

AddEventHandler('gameEventTriggered', function(name, args)
    if not InjuryCfg.Enabled then return end
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim     = args[1]
    local attacker   = args[2]
    local isFatal    = (args[6] == 1 or args[4] == 1)
    local weaponHash = args[7] or 0

    local ped = PlayerPedId()
    if victim ~= ped then return end

    dbg('Damage event', 'victim', victim, 'attacker', attacker, 'weapon', weaponHash, 'fatal', isFatal)

    local boneHit, bone = GetPedLastDamageBone(ped)
    local zone, boneLabel = 'Torso', 'Unknown'
    if boneHit then
        zone, boneLabel = getZoneAndBoneLabel(bone)
    end

    local injuryType = classifyDamage(ped, weaponHash, attacker)
    local health     = GetEntityHealth(ped)
    local sevLabel, sevLevel = severityFromHealth(health)

    local details
    if injuryType == 'Gunshot wound' then
        details = ('Gunshot wound (%s)'):format(sevLabel)
    elseif injuryType == 'Blunt trauma' then
        details = ('Blunt trauma (%s)'):format(sevLabel)
    elseif injuryType == 'Vehicle collision' then
        if zone == 'Left Leg' or zone == 'Right Leg' or zone == 'Left Arm' or zone == 'Right Arm' then
            details = ('Vehicle collision — possible fracture (%s)'):format(sevLabel)
        else
            details = ('Vehicle collision (%s)'):format(sevLabel)
        end
    elseif injuryType == 'Fall injury' then
        if zone == 'Left Leg' or zone == 'Right Leg' then
            details = ('Fall injury — possible leg fracture (%s)'):format(sevLabel)
        else
            details = ('Fall injury (%s)'):format(sevLabel)
        end
    elseif injuryType == 'Explosion injury' then
        details = ('Explosion injury (%s)'):format(sevLabel)
    elseif injuryType == 'Burns' then
        details = ('Burns (%s)'):format(sevLabel)
    elseif injuryType == 'Gas / smoke inhalation' then
        details = ('Gas / smoke inhalation (%s)'):format(sevLabel)
    elseif injuryType == 'Taser' then
        details = 'Taser exposure'
    elseif injuryType == 'Drowning' then
        details = 'Drowning / near-drowning'
    elseif injuryType == 'Lacerations' then
        details = ('Lacerations (%s)'):format(sevLabel)
    elseif injuryType == 'Animal attack' then
        details = ('Animal attack (%s)'):format(sevLabel)
    elseif injuryType == 'Exhaustion' then
        details = 'Exhaustion / overexertion'
    elseif injuryType == 'Environmental trauma' then
        details = ('Environmental trauma (%s)'):format(sevLabel)
    else
        details = ('Trauma (%s)'):format(sevLabel)
    end

    addInjury(zone, boneLabel, injuryType, details, sevLevel)
    pushInjuriesToUi()
end)


-- DEATH / REVIVE (clear injuries on revive)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(750)

        if not InjuryCfg.Enabled then goto continue end

        local ped = PlayerPedId()
        local isDead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

        if isDead and not wasDead then
            wasDead = true
            pushInjuriesToUi()
        elseif (not isDead) and wasDead then
            wasDead = false
            bleedingLevel  = 0
            bleedingActive = false
            nextBleedTick  = 0
            clearAllInjuries()
        end

        ::continue::
    end
end)


-- HOSPITAL TREATMENT

local function countInjuries()
    local wounds = 0
    local sevSum = 0
    for _, zoneData in pairs(InjuriesByZone) do
        for _, w in ipairs(zoneData.wounds) do
            wounds = wounds + 1
            sevSum = sevSum + (w.severity or 0)
        end
    end
    return wounds, sevSum
end

local function startHospitalTreatment(hospital)
    if isBeingTreated then return end

    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        notify('Hospital', 'You must be revived before treatment.', 'error')
        return
    end

    local woundCount, sevSum = countInjuries()
    local bleedLvl = getBleedingLevel()

    if woundCount == 0 and bleedLvl <= 0 then
        notify('Hospital', 'No injuries that require treatment.', 'inform')
        return
    end

    local tCfg = InjuryCfg.Treatment or {}
    local seconds = (tCfg.baseSeconds or 10)
        + woundCount * (tCfg.perWoundSeconds or 4)
        + sevSum * (tCfg.perSeveritySeconds or 3)

    if bleedLvl > 0 then
        seconds = seconds + (tCfg.extraBleedingSeconds or 10)
    end

    isBeingTreated = true
    local label = ('Receiving treatment (%s)'):format(hospital.name or 'Hospital')

    local success = true
    if lib and lib.progressCircle then
        success = lib.progressCircle({
            duration     = seconds * 1000,
            position     = 'bottom',
            label        = label,
            useWhileDead = false,
            canCancel    = true,
            disable      = { car = true, move = true, combat = true, mouse = false }
        })
    else
        notify('Hospital', label, 'inform')
        local finish = GetGameTimer() + seconds * 1000
        while GetGameTimer() < finish do
            Citizen.Wait(250)
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
                success = false
                break
            end
        end
    end

    if success then
        local maxHealth = GetEntityMaxHealth(ped)
        SetEntityHealth(ped, maxHealth)
        ClearPedBloodDamage(ped)

        bleedingLevel  = 0
        bleedingActive = false
        nextBleedTick  = 0
        clearAllInjuries()

        notify('Hospital', 'Your injuries have been treated.', 'success')
    else
        notify('Hospital', 'Treatment cancelled.', 'error')
    end

    isBeingTreated = false
end

Citizen.CreateThread(function()
    local textShown = false

    while true do
        Citizen.Wait(0)

        if not (InjuryCfg.Hospitals and #InjuryCfg.Hospitals > 0) then
            goto continue
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end
        local coords = GetEntityCoords(ped)

        local nearestH = nil
        local nearestDist = 9999.0
        for _, h in ipairs(InjuryCfg.Hospitals) do
            local dist = #(coords - h.coords)
            if dist < (h.radius or 4.0) and dist < nearestDist then
                nearestDist = dist
                nearestH = h
            end
        end

        if nearestH then
            if not textShown and lib and lib.showTextUI then
                lib.showTextUI(('[E] Check in at %s'):format(nearestH.name or 'hospital'))
                textShown = true
            end

            if IsControlJustReleased(0, InjuryCfg.HospitalKey or 38) then
                if lib and lib.hideTextUI then lib.hideTextUI() end
                textShown = false
                startHospitalTreatment(nearestH)
            end
        else
            if textShown and lib and lib.hideTextUI then
                lib.hideTextUI()
                textShown = false
            end
        end

        ::continue::
    end
end)


-- /injuries toggle + external events

RegisterCommand(InjuryCfg.ToggleCommand or 'injuries', function()
    overlayPinned = not overlayPinned
    pushInjuriesToUi()
end, false)

RegisterKeyMapping(
    InjuryCfg.ToggleCommand or 'injuries',
    'Toggle injury overlay',
    'keyboard',
    InjuryCfg.ToggleKey or 'F7'
)

RegisterNetEvent('az_injury:clear', function()
    bleedingLevel  = 0
    bleedingActive = false
    nextBleedTick  = 0
    clearAllInjuries()
end)

RegisterNetEvent('az_injury:pushUi', function()
    pushInjuriesToUi()
end)





-- client.lua  (NUI med prop prompt, pool-based search + expanded med prop list)

-----------------------------------
-- CONFIG
-----------------------------------

local MedConfig = {
    interactionRange = 1.8,   -- distance for E to work
    searchRadius     = 3.0,   -- max distance to consider a prop "nearby"
    useDuration      = 5500,  -- ms to "use" the prop
    healAmount       = 35,    -- HP restored
    cooldown         = 12000, -- ms between uses per player
    useWhileDead     = false, -- block if dead
    debug            = true,  -- toggle F8 prints + 3D markers
}

-- BIG list of medical-style props:
-- vanilla medstations, health packs, med bags, hospital / morgue props, trolleys, etc.
local MedicalProps = {
    -- Your original ones
    { model = `prop_medstation_01`,          label = 'Wall Medical Station (Green)'   },
    { model = `prop_medstation_02`,          label = 'Wall Medical Station (Red)'     },
    { model = `prop_medstation_03`,          label = 'Wall Medical Station (White)'   },
    { model = `prop_medstation_04`,          label = 'Wall Medical Station (Blue)'    },
    { model = `prop_ld_health_pack`,         label = 'First Aid Kit'                  },

    -- Common med kit / crate props
    { model = `xm_prop_x17_bag_med_01a`,     label = 'Portable Medkit Bag'            }, -- small med bag
    { model = `xm_prop_smug_crate_s_medical`,label = 'Medical Supply Crate'           }, -- medical crate

    -- Hospital / EMS trolleys
    { model = `v_med_trolley`,               label = 'Medical Trolley'                }, -- used in med loot scripts
    { model = `v_med_trolley2`,              label = 'Medical Trolley (Equipment)'    }, -- variant
    { model = `v_med_cor_cemtrolly`,         label = 'Coroner Trolley'                }, -- morgue trolley
    { model = `v_med_cor_cemtrolly2`,        label = 'Coroner Trolley 2'              }, -- second variant

    -- Bottles / meds / cooler
    { model = `v_med_bottles1`,              label = 'Medical Bottles 1'              }, -- med bottles
    { model = `v_med_bottles2`,              label = 'Medical Bottles 2'              },
    { model = `v_med_bottles3`,              label = 'Medical Bottles 3'              },
    { model = `v_med_beaker`,                label = 'Medical Beaker'                 }, -- lab beaker
    { model = `v_med_cooler`,                label = 'Medical Cooler'                 }, -- fridge/cooler

    -- Beds, benches & tables (good for hospitals)
    { model = `v_med_bed1`,                  label = 'Hospital Bed 1'                 }, -- hospital bed props
    { model = `v_med_bed2`,                  label = 'Hospital Bed 2'                 },
    { model = `v_med_bedtable`,              label = 'Bedside Table'                  },
    { model = `v_med_bench1`,                label = 'Medical Bench 1'                },
    { model = `v_med_bench2`,                label = 'Medical Bench 2'                },
    { model = `v_med_benchcentr`,            label = 'Medical Bench (Center)'         },
    { model = `v_med_benchset1`,             label = 'Medical Bench Set'              },
    { model = `v_med_bigtable`,              label = 'Large Medical Table'            },
    { model = `v_med_hosptable`,             label = 'Hospital Table'                 }, -- exam / work table

    -- Hospital seating / headwall
    { model = `v_med_hospseating1`,          label = 'Hospital Seating'               }, -- waiting area seating
    { model = `v_med_hospheadwall1`,         label = 'Hospital Bed Headwall'          }, -- wall with outlets

    -- Coroner / morgue furniture
    { model = `v_med_cor_autopsytbl`,        label = 'Autopsy Table'                  }, -- coroner
    { model = `v_med_cor_ceilingmonitor`,    label = 'Ceiling Monitor'                },
    { model = `v_med_cor_cembin`,            label = 'Biohazard Bin'                  },
    { model = `v_med_cor_chemical`,          label = 'Chemical Station'               },
    { model = `v_med_cor_emblmtable`,        label = 'Embalming Table'                },
    { model = `v_med_cor_fileboxa`,          label = 'Coroner File Box'               },
    { model = `v_med_cor_filingcab`,         label = 'Medical Filing Cabinet'         },
    { model = `v_med_cor_largecupboard`,     label = 'Medical Cupboard'               },
    { model = `v_med_cor_lightbox`,          label = 'X-ray Lightbox'                 },
    { model = `v_med_cor_medstool`,          label = 'Medical Stool'                  },
    { model = `v_med_cor_minifridge`,        label = 'Mini Medical Fridge'            },
    { model = `v_med_cor_papertowels`,       label = 'Paper Towel Dispenser'          },
    { model = `v_med_cor_photocopy`,         label = 'Coroner Copier'                 },
    { model = `v_med_cor_tvstand`,           label = 'Medical TV Stand'               },
    { model = `v_med_cor_wallunita`,         label = 'Medical Wall Unit'              },

    -- General lab / exam equipment
    { model = `v_med_centrifuge1`,           label = 'Centrifuge 1'                   }, -- lab gear
    { model = `v_med_centrifuge2`,           label = 'Centrifuge 2'                   },
    { model = `v_med_examlight`,             label = 'Exam Light'                     }, -- overhead exam light
    { model = `v_med_fumesink`,              label = 'Fume Sink'                      }, -- fume hood sink
    { model = `v_med_metalfume`,             label = 'Metal Fume Hood'                }, -- metal fume extractor
    { model = `v_med_gastank`,               label = 'Gas Tank'                       }, -- oxygen tank etc.
    { model = `v_med_hazmatscan`,            label = 'Hazmat Scanner'                 }, -- hazmat scanner
    { model = `v_med_bl_fan_base`,           label = 'Laboratory Fan Base'            }, -- lab fan base

    -- Small hospital items
    { model = `v_med_bin`,                   label = 'Medical Bin'                    }, -- trash / sharps bin
    { model = `v_med_latexgloveboxblue`,     label = 'Box of Gloves'                  }, -- glove box
    { model = `v_med_medwastebin`,           label = 'Medical Waste Bin'              }, -- biohazard bin
}

-----------------------------------
-- LOOKUP TABLE FOR MODELS
-----------------------------------

local ModelLookup = {}
for _, entry in ipairs(MedicalProps) do
    ModelLookup[entry.model] = entry
end

-----------------------------------
-- STATE
-----------------------------------

local currentEntity, currentData = nil, nil
local lastUseTime   = 0
local usingMedProp  = false
local lastDebugTime = 0

-----------------------------------
-- HELPERS
-----------------------------------

local function isPedDead(ped)
    return IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
end

local function sendMedPrompt(visible, name, subtitle)
    SendNUIMessage({
        type     = 'medprompt:update',
        visible  = visible,
        name     = name or 'Medical Supplies',
        subtitle = subtitle or 'Press E to use'
    })
end

local function clearMedPrompt()
    sendMedPrompt(false)
end

local function dprint(msg)
    if not MedConfig.debug then return end
    print(('[MedDebug] %s'):format(msg))
end

-----------------------------------
-- FIND CLOSEST MED PROP (POOL)
-----------------------------------

local function findClosestMedProp()
    local ped     = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local objects = GetGamePool('CObject')
    local bestEntity, bestData
    local bestDist = MedConfig.searchRadius + 0.001

    for _, obj in ipairs(objects) do
        if DoesEntityExist(obj) then
            local model = GetEntityModel(obj)
            local data  = ModelLookup[model]

            if data then
                local oCoords = GetEntityCoords(obj)

                local dx = pCoords.x - oCoords.x
                local dy = pCoords.y - oCoords.y
                local dz = pCoords.z - oCoords.z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                if dist < bestDist then
                    bestDist   = dist
                    bestEntity = obj
                    bestData   = data
                end

                -- Draw a marker on all med props when debugging
                if MedConfig.debug then
                    DrawMarker(
                        25,
                        oCoords.x, oCoords.y, oCoords.z + 0.1,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.18, 0.18, 0.18,
                        0, 255, 0, 180,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end
    end

    if MedConfig.debug and GetGameTimer() - lastDebugTime > 2000 then
        lastDebugTime = GetGameTimer()
        if bestEntity then
            dprint(('Nearest med prop: %s (dist=%.2f)'):format(bestData.label, bestDist))
        else
            dprint('No med prop found near player')
        end
    end

    if bestEntity then
        return bestEntity, bestData, bestDist
    end

    return nil, nil, nil
end

-----------------------------------
-- USE MEDICAL PROP
-----------------------------------

local function useMedicalProp(entity, data)
    if usingMedProp then return end

    local ped = PlayerPedId()
    if not MedConfig.useWhileDead and isPedDead(ped) then
        dprint('Blocked use because ped is dead')
        return
    end

    local now = GetGameTimer()
    if now - lastUseTime < MedConfig.cooldown then
        BeginTextCommandPrint('STRING')
        AddTextComponentSubstringPlayerName('You recently used medical supplies. Please wait.')
        EndTextCommandPrint(2000, true)
        dprint('Blocked use because of cooldown')
        return
    end

    usingMedProp = true
    lastUseTime  = now
    clearMedPrompt()

    if DoesEntityExist(entity) then
        local oCoords = GetEntityCoords(entity)
        TaskTurnPedToFaceCoord(ped, oCoords.x, oCoords.y, oCoords.z, 600)
        Wait(600)
    end

    local duration  = MedConfig.useDuration
    local cancelled = false

    dprint(('Starting treatment at %s, duration %d ms'):format(data.label, duration))

    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)

    local start = GetGameTimer()
    while GetGameTimer() - start < duration do
        Wait(0)

        if IsControlJustPressed(0, 73) or isPedDead(ped) then
            cancelled = true
            break
        end
    end

    ClearPedTasks(ped)

    if not cancelled and not isPedDead(ped) then
        local maxHealth     = GetEntityMaxHealth(ped)
        local currentHealth = GetEntityHealth(ped)
        local healAmount    = MedConfig.healAmount
        local newHealth     = math.min(maxHealth, currentHealth + healAmount)

        SetEntityHealth(ped, newHealth)

        TriggerEvent('az_medical:usedMedProp', {
            model     = data.model,
            label     = data.label,
            heal      = healAmount,
            entity    = entity,
            position  = GetEntityCoords(ped),
            timestamp = GetGameTimer()
        })

        dprint(('Finished treatment, healed %d HP'):format(healAmount))

        BeginTextCommandPrint('STRING')
        AddTextComponentSubstringPlayerName('You have treated some of your wounds.')
        EndTextCommandPrint(2000, true)
    else
        dprint('Treatment cancelled or ped died during treatment')

        BeginTextCommandPrint('STRING')
        AddTextComponentSubstringPlayerName('Treatment cancelled.')
        EndTextCommandPrint(1500, true)
    end

    usingMedProp = false
end

-----------------------------------
-- MAIN LOOP
-----------------------------------

CreateThread(function()
    while true do
        local sleep = 600
        local ped   = PlayerPedId()

        if not usingMedProp and not isPedDead(ped) then
            local entity, data, dist = findClosestMedProp()

            if entity and dist <= MedConfig.interactionRange then
                sleep = 0

                if entity ~= currentEntity or data ~= currentData then
                    currentEntity = entity
                    currentData   = data

                    dprint(('Showing NUI prompt for %s (dist=%.2f)'):format(data.label, dist))
                    sendMedPrompt(true, data.label, 'Press E to use')
                end

                if IsControlJustReleased(0, 38) then -- E
                    dprint('E pressed while near med prop')
                    useMedicalProp(entity, data)
                end
            else
                if currentEntity ~= nil then
                    dprint('No longer near med prop, hiding prompt')
                    currentEntity = nil
                    currentData   = nil
                    clearMedPrompt()
                end
            end
        else
            if currentEntity ~= nil then
                dprint('Using med prop or dead, clearing prompt')
                currentEntity = nil
                currentData   = nil
                clearMedPrompt()
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    clearMedPrompt()
end)

-----------------------------------
-- BLIPS FOR MEDICAL PROPS
-----------------------------------

local PropBlips = {}

-----------------------------------
-- BLIPS FOR MEDICAL PROPS
-----------------------------------

local MedBlips = {}
local function makeCoordKey(coords)
    return string.format("%.1f_%.1f_%.1f",
        coords.x, coords.y, coords.z)
end

-----------------------------------
-- BLIPS FOR MEDICAL PROPS (DEBUG)
-----------------------------------

-- one blip per coordinate key
local MedBlips = {}

local function makeCoordKey(coords)
    return string.format('%.1f_%.1f_%.1f', coords.x, coords.y, coords.z)
end

CreateThread(function()
    print('[az_injury] Med blip thread started')

    local discoverRadius = 300.0
    local firstScanPrint = false

    while true do
        local ped = PlayerPedId()

        if DoesEntityExist(ped) then
            local pCoords = GetEntityCoords(ped)
            local objects = GetGamePool('CObject') or {}
            local poolSize = #objects

            if not firstScanPrint then
                print(('[az_injury] First scan, CObject pool size: %d'):format(poolSize))
                firstScanPrint = true
            end

            for _, obj in ipairs(objects) do
                if DoesEntityExist(obj) then
                    local model = GetEntityModel(obj)
                    local data  = ModelLookup[model]   -- from MedicalProps

                    if data then
                        local coords = GetEntityCoords(obj)
                        local dist   = #(coords - pCoords)

                        if dist <= discoverRadius then
                            local key = makeCoordKey(coords)

                            if not MedBlips[key] then
                                local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

                                SetBlipSprite(blip, 61)          -- hospital icon
                                SetBlipDisplay(blip, 4)
                                SetBlipScale(blip, 0.7)
                                SetBlipColour(blip, 2)           -- green
                                SetBlipAsShortRange(blip, false) -- always visible

                                BeginTextCommandSetBlipName('STRING')
                                AddTextComponentSubstringPlayerName(data.label or 'Medical')
                                EndTextCommandSetBlipName(blip)

                                MedBlips[key] = blip
                                print(('[az_injury] Created medical blip at %.1f %.1f %.1f (%s)')
                                    :format(coords.x, coords.y, coords.z, data.label or 'Medical'))
                            end
                        end
                    end
                end
            end
        else
            if not firstScanPrint then
                print('[az_injury] Med blip thread: ped does not exist yet')
            end
        end

        Wait(10000)
    end
end)
