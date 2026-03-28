-- Az-Death/config.lua
-- Shared configuration. Loaded before client/server scripts via fxmanifest.

Config = Config or {}

-- Debug prints
Config.Debug = Config.Debug == true

-- NUI
Config.EnableNui = (Config.EnableNui ~= false)

-- Downed / respawn tuning (seconds)
-- These are common keys; your existing scripts may use any of these names.
Config.ReviveTime = Config.ReviveTime or 60          -- time until you can be revived / stabilized
Config.BleedoutTime = Config.BleedoutTime or 300    -- time until forced respawn/bleedout
Config.RespawnDelay = Config.RespawnDelay or 10     -- delay after choosing respawn

-- Optional early respawn (hold key)
Config.AllowEarlyRespawn = (Config.AllowEarlyRespawn ~= false)
Config.EarlyRespawnKey = Config.EarlyRespawnKey or 38 -- E
Config.EarlyRespawnHoldMs = Config.EarlyRespawnHoldMs or 2500

-- Hospital / respawn locations (use one or many)
-- If you already have a location system, these can be ignored by your scripts.
Config.RespawnLocations = Config.RespawnLocations or {
  {
    label = "Pillbox Medical",
    coords = vector3(306.39, -1433.61, 29.97),
    heading = 45.0
  }
}

-- Job/item permissions (optional)
Config.EMSJobs = Config.EMSJobs or { 'ambulance', 'ems', 'safd' }
Config.ReviveItem = Config.ReviveItem or 'medkit'    -- if your script uses items
Config.BandageItem = Config.BandageItem or 'bandage'

-- Framework hint (your scripts may ignore this)
-- Supported values: 'azfw', 'qb', 'esx', 'standalone'
Config.Framework = Config.Framework or 'azfw'


Config = Config or {}

Config.Debug = true
Config.EnableNui = true

-- Commands
Config.CommandInjuries = "injuries"
Config.CommandBackup   = "azinjuries"
Config.CommandClear    = "injuriesclear"

-- Reclaim /injuries from other scripts that register the same name
Config.RebindScheduleMs = { 0, 250, 1000, 3000, 8000, 15000 }
Config.RebindEveryMs = 30000

-- Injury tuning
Config.MaxWoundsPerRegion = 12
Config.MaxBleed = 8.0

-- Bleeding -> health loss (per second)
Config.BleedTickMs = 1000
Config.BleedHpPerSecondMin = 0
Config.BleedHpPerSecondMax = 6

-- Injury severity thresholds (0..100)
Config.Thresholds = {
  Limp         = 25,
  NoSprint     = 55,
  NoJump       = 70,

  AimPenalty   = 40,
  NoAim        = 80,

  HeadBlur     = 30,
  HeadBlackout = 75,

  TorsoSlow    = 40,
  TorsoNoSprint= 70,
}

-- Effects
Config.UseInjuredClipset = true
Config.InjuredClipset = "move_m@injured" -- limp animation set

-- Head blackout settings
Config.Blackout = {
  Enabled = true,
  CooldownMs = 12000,
  FadeOutMs = 400,
  RagMs = 1600,
  FadeInMs = 600,
}

-- Vehicle impact detection
Config.VehicleImpact = {
  Enabled = true,
  -- fallback detector triggers if health/armor drops while collision/ragdoll
  HealthDropPollMs = 150,
  MinDeltaToConsider = 2,
  CooldownMs = 750,
}

-- Ragdoll “stumble” from pain
Config.Stumble = {
  Enabled = true,
  CooldownMs = 8000,
  -- chance increases with severity
  BaseChance = 0.02, -- 2%
  MaxChance  = 0.12, -- 12%
}


-- Unified downed / hospital system
Config.MedDept = Config.MedDept or Config.EMSJobs or { 'ambulance', 'ems', 'safd' }

Config.Downed = Config.Downed or {
  Enabled = true,
  HealthOnDown = 110,
  ReviveHealth = 150,
  NotifyEMS = true,
  DisableFriendlyFire = true,
  DisableControls = true,
  DisableVehicleExit = true,
  PlayLoopAnim = true,
  AnimDict = 'dead',
  AnimName = 'dead_a',
}

Config.Hospital = Config.Hospital or {
  CheckInCost = 500,
  VisitHealCost = 250,
  TreatmentSeconds = 3,
  RespawnSeconds = 3,
  UseBankFirst = true,
}

Config.RespawnLocations = Config.RespawnLocations or {
  {
    label = 'Pillbox Medical',
    coords = vector3(329.28, -575.33, 43.28),
    heading = 160.0
  },
  {
    label = 'Sandy Shores Medical',
    coords = vector3(1841.81, 3668.18, 34.28),
    heading = 30.0
  },
  {
    label = 'Paleto Medical',
    coords = vector3(-252.52, 6334.64, 32.43),
    heading = 225.0
  }
}
