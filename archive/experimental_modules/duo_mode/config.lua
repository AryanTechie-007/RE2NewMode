--[[
    Resident Evil 2: Duo Mode
    config.lua - Core configuration and tunable constants
]]

local config = {}

-- General Settings
config.enabled = true
config.debug_mode = true
config.log_verbose = true

-- Distance & Locomotion Tunables
config.follow_distance_min = 1.2      -- Distance (meters) to stop and idle
config.follow_distance_walk = 3.5     -- Distance (meters) to walk
config.follow_distance_run = 7.0      -- Distance (meters) to sprint
config.rubber_band_distance = 15.0    -- Distance to trigger fallback teleport if off-screen
config.rear_offset = 1.5              -- Offset distance behind leader for target waypoint

-- Combat Tunables
config.companion_max_hp = 1000
config.bleed_out_time = 45.0          -- Seconds companion can remain downed before Game Over
config.burst_fire_interval = 1.2      -- Seconds between companion shots
config.combat_detection_range = 10.0  -- Meters to scan for enemies in cover mode
config.aim_cone_angle = 60.0          -- Forward cone in degrees to acquire targets

-- Stealth & Acoustic Tunables
config.licker_detection_radius = 18.0 -- Meters to detect Lickers and clamp speed to walk
config.licker_max_stick_magnitude = 0.45

-- UI & Controls
config.command_wheel_key = 0x54       -- 'T' Key (0x54) - Rebound from Middle Mouse to prevent camera reset conflict!
config.command_wheel_key_alt = 0x47   -- 'G' Key (0x47) - Alternative hotkey option
config.command_wheel_gamepad_btn = 0x0200 -- RB / R1 button flag
config.time_scale_slowdown = 0.4      -- Timescale while command wheel is held (40% speed)

-- Audio Bridge
config.audio_enabled = true
config.master_voice_volume = 1.0
config.saferoom_idle_dialogue_delay = 5.0 -- Seconds in safe room before idle banter fires

-- Preload Asset Paths
config.preload_prefabs = {
    claire_body = "natives/x64/objectroot/survivor/player/pl1000.pfb",
    leon_body   = "natives/x64/objectroot/survivor/player/pl0000.pfb",
    sls60       = "natives/x64/objectroot/weapon/wp1000/wp1000.pfb",
    gm79        = "natives/x64/objectroot/weapon/wp1200/wp1200.pfb",
    jmb_hp3     = "natives/x64/objectroot/weapon/wp1100/wp1100.pfb",
    w870        = "natives/x64/objectroot/weapon/wp0100/wp0100.pfb"
}

return config
