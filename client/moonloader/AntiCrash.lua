script_name('EvolveAntiCrash')
script_version('1.2.0')
script_version_number(3)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory limiter for low VRAM GPUs')
script_moonloader(026)

local memory = require 'memory'

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_AVAILABLE = 0x8E4CB4   -- CStreaming::ms_memoryAvailable
local ADDR_STREAMING_MEM_USED      = 0x8E4CA8   -- CStreaming::ms_memoryUsed

-- Config (tuned for GT 1030 / 2GB VRAM / 8GB RAM)
local MAX_STREAMING_MEMORY_MB = 512              -- cap streaming at 512MB (EvolveClient sets ~2535MB which is way too much for GT 1030)
local CHECK_INTERVAL          = 400              -- memory check interval (ms)
local MEMORY_FREE_THRESHOLD   = 0.85             -- force cleanup at 85% usage

-- Crash-prone zones: {x, y, radius}
local HEAVY_ZONES = {
    {2100, 1400, 300},  -- LV Auto Bazar
    {2200, 1300, 250},  -- LV Bridge South
    {2000, 1600, 250},  -- LV Bridge North
}

local initialized = false

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    capStreamingMemory()
    initialized = true

    while true do
        wait(CHECK_INTERVAL)
        if isPlayerPlaying(PLAYER_HANDLE) then
            monitorStreaming()
        end
    end
end

function capStreamingMemory()
    local currentMem = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local currentMB = math.floor(currentMem / 1024 / 1024)
    local capBytes = MAX_STREAMING_MEMORY_MB * 1024 * 1024

    if currentMem > capBytes then
        memory.setint32(ADDR_STREAMING_MEM_AVAILABLE, capBytes, true)
        print(string.format('[AntiCrash] Streaming memory capped: %d MB -> %d MB (GPU: GT 1030, 2GB VRAM)',
            currentMB, MAX_STREAMING_MEMORY_MB))
    else
        print(string.format('[AntiCrash] Streaming memory OK: %d MB (cap: %d MB)',
            currentMB, MAX_STREAMING_MEMORY_MB))
    end
end

function monitorStreaming()
    local memAvailable = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local memUsed = memory.getint32(ADDR_STREAMING_MEM_USED, true)

    if memAvailable <= 0 then return end

    -- Re-apply cap in case something resets it
    local capBytes = MAX_STREAMING_MEMORY_MB * 1024 * 1024
    if memAvailable > capBytes then
        memory.setint32(ADDR_STREAMING_MEM_AVAILABLE, capBytes, true)
        memAvailable = capBytes
    end

    local usage = memUsed / memAvailable

    -- Check if near heavy zone for lower threshold
    local inHeavyZone = false
    local px, py, pz = getCharCoordinates(playerPed)
    for _, zone in ipairs(HEAVY_ZONES) do
        local dx = px - zone[1]
        local dy = py - zone[2]
        if (dx * dx + dy * dy) < (zone[3] * zone[3]) then
            inHeavyZone = true
            break
        end
    end

    local threshold = inHeavyZone and 0.75 or MEMORY_FREE_THRESHOLD

    if usage >= threshold then
        pcall(function()
            loadAllModelsNow()
        end)
    end
end
