script_name('EvolveAntiCrash')
script_version('1.3.0')
script_version_number(4)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory limiter for low VRAM GPUs')
script_moonloader(026)

local memory = require 'memory'

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_AVAILABLE = 0x8E4CB4   -- CStreaming::ms_memoryAvailable
local ADDR_STREAMING_MEM_USED      = 0x8E4CA8   -- CStreaming::ms_memoryUsed

-- Config (tuned for GT 1030 / 2GB VRAM / 8GB RAM)
-- EvolveClient.asi constantly overrides the streaming limit to ~2535MB.
-- We cannot reliably cap it at the address level, so instead we monitor
-- absolute usage and force cleanup when it gets too high.
local MAX_USAGE_MB         = 384                 -- force cleanup when usage exceeds this (MB)
local MAX_USAGE_HEAVY_MB   = 256                 -- lower threshold in crash-prone zones (MB)
local CHECK_INTERVAL       = 100                 -- check every 100ms for faster response

-- Crash-prone zones: {x, y, radius}
local HEAVY_ZONES = {
    {2100, 1400, 300},  -- LV Auto Bazar
    {2200, 1300, 250},  -- LV Bridge South
    {2000, 1600, 250},  -- LV Bridge North
}

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    local currentMem = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local currentMB = math.floor(currentMem / 1024 / 1024)
    print(string.format('[AntiCrash] v1.3.0 loaded. Streaming limit: %d MB. Cleanup at: %d MB (normal) / %d MB (heavy zones)',
        currentMB, MAX_USAGE_MB, MAX_USAGE_HEAVY_MB))

    while true do
        wait(CHECK_INTERVAL)
        if isPlayerPlaying(PLAYER_HANDLE) then
            monitorStreaming()
        end
    end
end

function monitorStreaming()
    local memUsed = memory.getint32(ADDR_STREAMING_MEM_USED, true)
    if memUsed <= 0 then return end

    local usedMB = memUsed / 1024 / 1024

    -- Determine threshold based on player location
    local threshold = MAX_USAGE_MB
    local px, py, pz = getCharCoordinates(playerPed)
    for _, zone in ipairs(HEAVY_ZONES) do
        local dx = px - zone[1]
        local dy = py - zone[2]
        if (dx * dx + dy * dy) < (zone[3] * zone[3]) then
            threshold = MAX_USAGE_HEAVY_MB
            break
        end
    end

    if usedMB >= threshold then
        pcall(function()
            loadAllModelsNow()
        end)
    end
end
