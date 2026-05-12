script_name('VehicleAntiCrash')
script_version('2.0.0')
script_version_number(1)
script_author('Evolve RP')
script_description('Prevents crashes from invalid vehicle models streaming in')
script_moonloader(026)
script_properties('work-in-pause')

local memory = require 'memory'
local sampev = require 'samp.events'

-- GTA SA 1.0 US addresses
local MODEL_INFO_PTRS      = 0xA9B0C8  -- CModelInfo::ms_modelInfoPtrs[20000]
local STREAMING_INFO_BASE  = 0x8E4CC0  -- CStreaming::ms_aInfoForModel
local STREAMING_ENTRY_SIZE = 20
local MAX_MODEL_ID         = 19999

-- State
local failedModels = {}
local stats = { blocked = 0, total = 0 }

local function isModelValid(modelId)
    if modelId < 0 or modelId > MAX_MODEL_ID then
        return false
    end

    local infoPtr = memory.getuint32(MODEL_INFO_PTRS + modelId * 4)
    if infoPtr == 0 then
        return false
    end

    local streamBase = STREAMING_INFO_BASE + modelId * STREAMING_ENTRY_SIZE
    local cdSize = memory.getuint32(streamBase + 12)
    if cdSize == 0 then
        return false
    end

    return true
end

function sampev.onVehicleStreamIn(vehicleId, data)
    local modelId = data.type
    stats.total = stats.total + 1

    if failedModels[modelId] then
        stats.blocked = stats.blocked + 1
        return false
    end

    if not isModelValid(modelId) then
        failedModels[modelId] = true
        stats.blocked = stats.blocked + 1
        print(string.format('[VehicleAntiCrash] Blocked vehicle id=%d model=%d (invalid model)', vehicleId, modelId))
        return false
    end
end

function main()
    while not isSampAvailable() do wait(100) end
    wait(2000)

    sampAddChatMessage(
        '{FFCC00}[AntiCrash] {FFFFFF}v2.0 | Vehicle stream protection active',
        0xFFFFFFFF
    )
    print('[VehicleAntiCrash] v2.0.0 loaded')

    sampRegisterChatCommand('anticrash', function()
        sampAddChatMessage(
            string.format(
                '{FFCC00}[AntiCrash] {FFFFFF}Blocked: %d / %d vehicles | Failed models: %d',
                stats.blocked, stats.total, countTable(failedModels)
            ),
            0xFFFFFFFF
        )
    end)

    wait(-1)
end

function countTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
