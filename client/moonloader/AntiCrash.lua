script_name('EvolveAntiCrash')
script_version('1.4.0')
script_version_number(5)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory cleanup for low VRAM GPUs')
script_moonloader(026)

local memory = require 'memory'
local ffi = require 'ffi'

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_USED = 0x8E4CA8   -- CStreaming::ms_memoryUsed

-- GTA SA internal functions (1.0 US, __cdecl)
ffi.cdef[[
    typedef void (__cdecl *void_func_t)();
]]
-- CStreaming::RemoveAllUnusedModels - frees models with 0 references
local removeAllUnused = ffi.cast('void_func_t', 0x40CF80)
-- CStreaming::RemoveLeastUsedModel - frees the single least recently used model
local removeLeastUsed = ffi.cast('void_func_t', 0x40CFD0)

-- Config (tuned for GT 1030 / 2GB VRAM / 8GB RAM)
local MAX_USAGE_MB         = 384       -- start cleanup when usage exceeds this
local MAX_USAGE_HEAVY_MB   = 256       -- lower threshold in crash-prone zones
local CRITICAL_USAGE_MB    = 512       -- aggressive cleanup above this
local CHECK_INTERVAL       = 150       -- check every 150ms

-- Crash-prone zones: {x, y, radius}
local HEAVY_ZONES = {
    {2100, 1400, 300},  -- LV Auto Bazar
    {2200, 1300, 250},  -- LV Bridge South
    {2000, 1600, 250},  -- LV Bridge North
}

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    print(string.format('[AntiCrash] v1.4.0 loaded. Cleanup at: %d MB / %d MB (heavy) / %d MB (critical)',
        MAX_USAGE_MB, MAX_USAGE_HEAVY_MB, CRITICAL_USAGE_MB))

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

    if usedMB >= CRITICAL_USAGE_MB then
        -- Critical: aggressively free memory
        pcall(function()
            removeAllUnused()
            for i = 1, 10 do
                removeLeastUsed()
            end
        end)
    elseif usedMB >= threshold then
        -- Normal cleanup: free unused models
        pcall(function()
            removeAllUnused()
        end)
    end
end
