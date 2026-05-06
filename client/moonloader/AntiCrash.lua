script_name('EvolveAntiCrash')
script_version('1.5.0')
script_version_number(6)
script_author('Evolve RP')
script_description('Anti-crash: streaming memory cleanup with GUI monitor')
script_moonloader(026)

local memory = require 'memory'
local ffi = require 'ffi'
local font_flag = require('moonloader').font_flag

-- GTA SA memory addresses (1.0 US)
local ADDR_STREAMING_MEM_AVAILABLE = 0x8E4CB4
local ADDR_STREAMING_MEM_USED      = 0x8E4CA8

-- GTA SA internal functions (1.0 US, __cdecl)
ffi.cdef[[
    typedef void (__cdecl *void_func_t)();
]]
local removeAllUnused = ffi.cast('void_func_t', 0x40CF80)
local removeLeastUsed = ffi.cast('void_func_t', 0x40CFD0)

-- Config
local MAX_USAGE_MB         = 384
local MAX_USAGE_HEAVY_MB   = 256
local CRITICAL_USAGE_MB    = 512
local CHECK_INTERVAL       = 150

-- GUI config
local GUI_ENABLED          = true       -- toggle with F10
local GUI_X                = 10
local GUI_Y                = 450
local GUI_WIDTH            = 220
local GUI_BAR_HEIGHT       = 14

-- Crash-prone zones: {x, y, radius, name}
local HEAVY_ZONES = {
    {2100, 1400, 300, 'LV Auto Bazar'},
    {2200, 1300, 250, 'LV Bridge S'},
    {2000, 1600, 250, 'LV Bridge N'},
}

-- State
local guiFont = nil
local guiFontSmall = nil
local lastUsedMB = 0
local lastLimitMB = 0
local lastThreshold = MAX_USAGE_MB
local lastZoneName = ''
local cleanupCount = 0
local lastCleanupTime = 0

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    guiFont = renderCreateFont('Arial', 10, font_flag.BOLD + font_flag.SHADOW)
    guiFontSmall = renderCreateFont('Arial', 8, font_flag.SHADOW)

    print(string.format('[AntiCrash] v1.5.0 loaded. GUI: F10 toggle. Cleanup at: %d / %d / %d MB',
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
    local memAvail = memory.getint32(ADDR_STREAMING_MEM_AVAILABLE, true)
    if memUsed <= 0 then return end

    lastUsedMB = memUsed / 1024 / 1024
    lastLimitMB = memAvail / 1024 / 1024

    -- Determine threshold and zone
    lastThreshold = MAX_USAGE_MB
    lastZoneName = ''
    local px, py, pz = getCharCoordinates(playerPed)
    for _, zone in ipairs(HEAVY_ZONES) do
        local dx = px - zone[1]
        local dy = py - zone[2]
        if (dx * dx + dy * dy) < (zone[3] * zone[3]) then
            lastThreshold = MAX_USAGE_HEAVY_MB
            lastZoneName = zone[4]
            break
        end
    end

    if lastUsedMB >= CRITICAL_USAGE_MB then
        pcall(function()
            removeAllUnused()
            for i = 1, 10 do
                removeLeastUsed()
            end
        end)
        cleanupCount = cleanupCount + 1
        lastCleanupTime = os.clock()
    elseif lastUsedMB >= lastThreshold then
        pcall(function()
            removeAllUnused()
        end)
        cleanupCount = cleanupCount + 1
        lastCleanupTime = os.clock()
    end

    -- Toggle GUI with F10
    if isKeyJustPressed(0x79) then
        GUI_ENABLED = not GUI_ENABLED
    end
end

function renderDraw()
    if not GUI_ENABLED or not guiFont then return end

    local usedMB = math.floor(lastUsedMB)
    local limitMB = math.floor(lastLimitMB)
    local threshold = lastThreshold

    -- Background
    renderDrawBox(GUI_X, GUI_Y, GUI_WIDTH, 72, 0xAA000000)

    -- Title
    renderFontDrawText(guiFont, 'AntiCrash v1.5', GUI_X + 4, GUI_Y + 2, 0xFFFFCC00)

    -- Streaming usage
    local usageColor = 0xFF00FF00  -- green
    if usedMB >= CRITICAL_USAGE_MB then
        usageColor = 0xFFFF0000  -- red
    elseif usedMB >= threshold then
        usageColor = 0xFFFF8800  -- orange
    elseif usedMB >= threshold * 0.75 then
        usageColor = 0xFFFFFF00  -- yellow
    end

    renderFontDrawText(guiFontSmall,
        string.format('Stream: %d / %d MB (cap: %d)', usedMB, limitMB, threshold),
        GUI_X + 4, GUI_Y + 16, 0xFFCCCCCC)

    -- Progress bar
    local barX = GUI_X + 4
    local barY = GUI_Y + 30
    local barW = GUI_WIDTH - 8
    local fillRatio = math.min(usedMB / math.max(CRITICAL_USAGE_MB, 1), 1.0)

    renderDrawBox(barX, barY, barW, GUI_BAR_HEIGHT, 0xFF333333)
    renderDrawBox(barX, barY, barW * fillRatio, GUI_BAR_HEIGHT, usageColor)

    -- Threshold marker
    local thresholdPos = barX + barW * (threshold / CRITICAL_USAGE_MB)
    renderDrawBox(thresholdPos, barY, 2, GUI_BAR_HEIGHT, 0xFFFFFFFF)

    -- Zone info
    local zoneText = lastZoneName ~= '' and ('{FFAA00}Zone: ' .. lastZoneName) or '{888888}No heavy zone'
    renderFontDrawText(guiFontSmall, zoneText, GUI_X + 4, GUI_Y + 47, 0xFFCCCCCC)

    -- Cleanup counter
    local cleanupText = string.format('Cleanups: %d', cleanupCount)
    if os.clock() - lastCleanupTime < 1.0 then
        cleanupText = cleanupText .. ' {FF4444}[CLEANING]'
    end
    renderFontDrawText(guiFontSmall, cleanupText, GUI_X + 4, GUI_Y + 58, 0xFF888888)
end

function onD3DPresent()
    renderDraw()
end
