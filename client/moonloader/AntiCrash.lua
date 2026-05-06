script_name('EvolveAntiCrash')
script_version('1.1.0')
script_version_number(2)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory management')
script_moonloader(026)

local memory = require 'memory'

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_AVAILABLE = 0x8E4CB4   -- CStreaming::ms_memoryAvailable
local ADDR_STREAMING_MEM_USED      = 0x8E4CA8   -- CStreaming::ms_memoryUsed

-- Config
local STREAMING_MEMORY_MB   = 128               -- streaming memory limit (MB)
local CHECK_INTERVAL        = 500                -- memory check interval (ms)
local MEMORY_FREE_THRESHOLD = 0.88               -- force cleanup at 88% usage

-- Crash-prone zones: {x, y, radius}
local HEAVY_ZONES = {
    {2100, 1400, 300},  -- LV Auto Bazar
    {2200, 1300, 250},  -- LV Bridge South
    {2000, 1600, 250},  -- LV Bridge North
}

local initialized = false
local origStreamingMem = 0

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    setupStreamingMemory()
    initialized = true

    while true do
        wait(CHECK_INTERVAL)
        if isPlayerPlaying(PLAYER_HANDLE) then
            monitorStreaming()
        end
    end
end

function setupStreamingMemory()
    origStreamingMem = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local newMem = STREAMING_MEMORY_MB * 1024 * 1024
    if origStreamingMem < newMem then
        memory.setint32(ADDR_STREAMING_MEM_AVAILABLE, newMem, true)
        print(string.format('[AntiCrash] Streaming memory: %d MB -> %d MB',
            origStreamingMem / 1024 / 1024, STREAMING_MEMORY_MB))
    else
        print(string.format('[AntiCrash] Streaming memory already at %d MB',
            origStreamingMem / 1024 / 1024))
    end
end

function monitorStreaming()
    local memAvailable = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local memUsed = memory.getint32(ADDR_STREAMING_MEM_USED, true)

    if memAvailable <= 0 then return end

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

    local threshold = inHeavyZone and 0.80 or MEMORY_FREE_THRESHOLD

    if usage >= threshold then
        pcall(function()
            loadAllModelsNow()
        end)
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() and initialized and origStreamingMem > 0 then
        memory.setint32(ADDR_STREAMING_MEM_AVAILABLE, origStreamingMem, true)
    end
end
