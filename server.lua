local RESOURCE = GetCurrentResourceName()

Config = Config or {}
Config.Debug = Config.Debug ~= false

local function dprint(...)
  if not Config.Debug then return end
  local t = {}
  for i=1,select("#", ...) do t[#t+1] = tostring(select(i, ...)) end
  print(("^3[%s]^7 %s"):format(RESOURCE, table.concat(t, " ")))
end

local function notify(src, title, description, ntype)
  if GetResourceState('ox_lib') == 'started' then
    TriggerClientEvent('ox_lib:notify', src, {
      title = title,
      description = description,
      type = ntype or 'inform'
    })
  else
    TriggerClientEvent('chat:addMessage', src, {
      color = {255,255,255},
      args = { title or 'Az-Death', description or '' }
    })
  end
end

-- Session store (simple & reliable)
local injuriesBySrc = {}

AddEventHandler("playerDropped", function()
  injuriesBySrc[source] = nil
end)

RegisterNetEvent("Az-Death:injury:sync", function(state)
  local src = source
  if type(state) ~= "table" then return end
  injuriesBySrc[src] = state
  dprint("sync from", src)
end)

-- Optional: allow server-side toggle if you want to call it from other scripts
RegisterCommand("injuries", function(src)
  if src == 0 then return end
  TriggerClientEvent("Az-Death:ui:togglePinned", src)
end, false)

RegisterCommand("injclear", function(src, args)
  local target = tonumber(args[1] or "")
  if src == 0 then
    if target then
      injuriesBySrc[target] = {}
      TriggerClientEvent("Az-Death:injury:set", target, {})
      print("Cleared injuries for", target)
    end
    return
  end

  if target then
    injuriesBySrc[target] = {}
    TriggerClientEvent("Az-Death:injury:set", target, {})
  else
    injuriesBySrc[src] = {}
    TriggerClientEvent("Az-Death:injury:set", src, {})
  end
end, false)


local function hasAzFramework()
  return GetResourceState('Az-Framework') == 'started'
end

local function tryChargeAzFramework(src, amount, reason)
  if not hasAzFramework() or not amount or amount <= 0 then return true end

  local attempts = {
    function() return exports['Az-Framework']:removeMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removeMoney(src, amount, 'bank', reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removePlayerMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:removePlayerMoney(src, amount, 'bank', reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:deductMoney(src, 'bank', amount, reason or 'Hospital treatment') end,
    function() return exports['Az-Framework']:deductMoney(src, amount, reason or 'Hospital treatment') end,
  }

  for _,fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok then
      if res == nil or res == true or res == 1 then return true end
      if type(res) == 'table' and (res.success == true or res.ok == true) then return true end
    end
  end

  return false
end

if lib and lib.callback then
  lib.callback.register('Az-Death:server:billHospital', function(source, kind)
    local amount = ((Config.Hospital or {}).VisitHealCost or 250)
    if tostring(kind) == 'checkin' then
      amount = ((Config.Hospital or {}).CheckInCost or 500)
    end

    if hasAzFramework() then
      local ok = tryChargeAzFramework(source, amount, 'Az-Death hospital treatment')
      if not ok then
        return false, ('You need $%s in the bank for treatment.'):format(amount)
      end
      return true, ('Charged $%s for treatment.'):format(amount)
    end

    return true, nil
  end)
end

local function playerHasMedPerm(src)
  local ok, job = pcall(function()
    return exports['Az-Framework']:getPlayerJob(src)
  end)
  if not ok then return false end
  for _,department in pairs(Config.MedDept or Config.EMSJobs or {}) do
    if job == department then return true end
  end
  return false
end


RegisterNetEvent('Az-Death:server:transportNearestPlayer', function(target)
  local src = source
  target = tonumber(target or '')
  if not target or GetPlayerPed(target) == 0 then
    notify(src, 'Hospital Transport', 'Invalid target player.', 'error')
    return
  end
  if not playerHasMedPerm(src) then
    notify(src, 'Hospital Transport', 'You do not have permission to transport patients.', 'error')
    return
  end

  local srcPed = GetPlayerPed(src)
  local targetPed = GetPlayerPed(target)
  if srcPed == 0 or targetPed == 0 then
    notify(src, 'Hospital Transport', 'Unable to find both players.', 'error')
    return
  end

  local a = GetEntityCoords(srcPed)
  local b = GetEntityCoords(targetPed)
  local dx,dy,dz = a.x-b.x, a.y-b.y, a.z-b.z
  local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
  if dist > 3.0 then
    notify(src, 'Hospital Transport', 'Move closer to the patient.', 'error')
    return
  end

  TriggerClientEvent('Az-Death:client:transportToHospital', target, 'EMS transport')
  notify(src, 'Hospital Transport', ('You transported player %s to the hospital.'):format(target), 'success')
end)

RegisterCommand('takehospital', function(src, args)
  if src == 0 then return end
  if not playerHasMedPerm(src) then
    notify(src, 'Hospital Transport', 'You do not have permission to use /takehospital.', 'error')
    return
  end

  local target = tonumber(args[1] or '')
  if not target or GetPlayerPed(target) == 0 then
    notify(src, 'Hospital Transport', 'Invalid target player ID.', 'error')
    return
  end

  TriggerClientEvent('Az-Death:client:transportToHospital', target, 'EMS transport')
  notify(src, 'Hospital Transport', ('You transported player %s to the hospital.'):format(target), 'success')
end, false)
