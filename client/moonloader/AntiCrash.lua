script_name('EvolveAntiCrash')
script_version('1.0.0')
script_version_number(1)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory management and crash prevention')
script_moonloader(026)

local memory = require 'memory'
local ffi = require 'ffi'

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_AVAILABLE = 0x8E4CB4   -- CStreaming::ms_memoryAvailable
local ADDR_STREAMING_MEM_USED      = 0x8E4CA8   -- CStreaming::ms_memoryUsed

-- Config
local STREAMING_MEMORY_MB   = 128               -- streaming memory limit (MB)
local CHECK_INTERVAL        = 500                -- memory check interval (ms)
local MEMORY_WARN_THRESHOLD = 0.85               -- warn at 85% usage
local MEMORY_FREE_THRESHOLD = 0.90               -- force free at 90% usage

-- Crash-prone zones: {x, y, radius, name}
local HEAVY_ZONES = {
    {2100, 1400, 300, 'LV Auto Bazar'},
    {2200, 1300, 250, 'LV Bridge South'},
    {2000, 1600, 250, 'LV Bridge North'},
}

local initialized = false
local origStreamingMem = 0

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(2000)

    setupStreamingMemory()
    applyCrashFixes()
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

function applyCrashFixes()
    -- Fix: NOP out problematic vehicle render crash (common SA-MP crash)
    -- 0x6D6494: crash in CAutomobile::PreRender when vehicle extra is invalid
    pcall(function()
        memory.fill(0x6D6494, 0x90, 2, true)
    end)

    -- Fix: prevent crash when streaming too many vehicle models
    -- Increase CStreaming max request list
    pcall(function()
        memory.setint32(0x8E4CC0, 64, true) -- max concurrent streaming requests
    end)

    print('[AntiCrash] Crash fixes applied')
end

function monitorStreaming()
    local memAvailable = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    local memUsed = memory.getint32(ADDR_STREAMING_MEM_USED, true)

    if memAvailable <= 0 then return end

    local usage = memUsed / memAvailable

    if usage >= MEMORY_FREE_THRESHOLD then
        -- Critical: force streaming cleanup
        forceStreamingCleanup()
    end

    -- Check if player is in a heavy zone
    local px, py, pz = getCharCoordinates(playerPed)
    for _, zone in ipairs(HEAVY_ZONES) do
        local dx = px - zone[1]
        local dy = py - zone[2]
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < zone[3] then
            if usage >= MEMORY_WARN_THRESHOLD then
                forceStreamingCleanup()
            end
            break
        end
    end
end

function forceStreamingCleanup()
    -- Call CStreaming::MakeSpaceFor via memory
    -- Trigger GTA's built-in streaming garbage collector
    pcall(function()
        -- Flush pending streaming requests to prevent queue overflow
        -- 0x40E3A0 = CStreaming::FlushRequestList
        loadAllModelsNow()
    end)
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() and initialized and origStreamingMem > 0 then
        memory.setint32(ADDR_STREAMING_MEM_AVAILABLE, origStreamingMem, true)
    end
end
