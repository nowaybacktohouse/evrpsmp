script_name('EvolveAntiCrash')
script_version('1.7.0')
script_version_number(8)
script_author('Evolve RP')
script_description('Anti-crash: process memory monitor with streaming cleanup')
script_moonloader(026)

local memory = require 'memory'
local ffi = require 'ffi'
local font_flag = require('moonloader').font_flag

-- Windows API for process memory monitoring
ffi.cdef[[
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef void* HANDLE;
    typedef size_t SIZE_T;

    typedef struct {
        DWORD  cb;
        DWORD  PageFaultCount;
        SIZE_T PeakWorkingSetSize;
        SIZE_T WorkingSetSize;
        SIZE_T QuotaPeakPagedPoolUsage;
        SIZE_T QuotaPagedPoolUsage;
        SIZE_T QuotaPeakNonPagedPoolUsage;
        SIZE_T QuotaNonPagedPoolUsage;
        SIZE_T PagefileUsage;
        SIZE_T PeakPagefileUsage;
    } PROCESS_MEMORY_COUNTERS;

    HANDLE GetCurrentProcess();
    BOOL K32GetProcessMemoryInfo(HANDLE hProcess, PROCESS_MEMORY_COUNTERS* ppsmemCounters, DWORD cb);
]]

-- GTA SA internal functions (1.0 US)
ffi.cdef[[
    typedef void (__cdecl *void_func_t)();
]]
local removeAllUnused = ffi.cast('void_func_t', 0x40CF80)
local removeLeastUsed = ffi.cast('void_func_t', 0x40CFD0)

-- Config (tuned for GT 1030 / 2GB VRAM / 8GB RAM)
-- Using process working set (actual RAM usage) as metric
local CLEANUP_THRESHOLD_MB = 2100      -- start cleanup at 2100 MB working set
local CLEANUP_HEAVY_MB     = 1800      -- lower threshold in heavy zones
local CRITICAL_THRESHOLD_MB = 2500     -- aggressive cleanup
local TOTAL_RAM_MB         = 8140      -- total system RAM
local CHECK_INTERVAL       = 200

-- GUI config
local GUI_ENABLED          = false
local GUI_X                = 10
local GUI_Y                = 450
local GUI_WIDTH            = 240
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
local lastWorkingSetMB = 0
local lastPeakMB = 0
local lastThreshold = CLEANUP_THRESHOLD_MB
local lastZoneName = ''
local cleanupCount = 0
local lastCleanupTime = 0
local pmc = ffi.new('PROCESS_MEMORY_COUNTERS')
local hProcess = ffi.C.GetCurrentProcess()

function getWorkingSet()
    pmc.cb = ffi.sizeof(pmc)
    if ffi.C.K32GetProcessMemoryInfo(hProcess, pmc, pmc.cb) ~= 0 then
        return tonumber(pmc.WorkingSetSize), tonumber(pmc.PeakWorkingSetSize)
    end
    return 0, 0
end

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(100) end
    wait(3000)

    guiFont = renderCreateFont('Arial', 10, font_flag.BOLD + font_flag.SHADOW)
    guiFontSmall = renderCreateFont('Arial', 8, font_flag.SHADOW)

    sampRegisterChatCommand('crashmon', cmdToggleGui)

    local ws, peak = getWorkingSet()
    print(string.format('[AntiCrash] v1.7.0 loaded. /crashmon to toggle GUI. Working set: %d MB. Cleanup at: %d / %d / %d MB',
        math.floor(ws / 1024 / 1024), CLEANUP_THRESHOLD_MB, CLEANUP_HEAVY_MB, CRITICAL_THRESHOLD_MB))

    while true do
        wait(CHECK_INTERVAL)
        if isPlayerPlaying(PLAYER_HANDLE) then
            monitorMemory()
        end
    end
end

function cmdToggleGui()
    GUI_ENABLED = not GUI_ENABLED
    if GUI_ENABLED then
        sampAddChatMessage('[AntiCrash] {00FF00}Monitor ON', 0xFFFFCC00)
    else
        sampAddChatMessage('[AntiCrash] {FF4444}Monitor OFF', 0xFFFFCC00)
    end
end

function doCleanup(aggressive)
    pcall(function()
        -- Free unused streaming models
        removeAllUnused()

        if aggressive then
            for i = 1, 20 do
                removeLeastUsed()
            end
        end

        -- Mark vehicle models as no longer needed (allows engine to unload them)
        for modelId = 400, 611 do
            if hasModelLoaded(modelId) then
                markModelAsNoLongerNeeded(modelId)
            end
        end
    end)
    cleanupCount = cleanupCount + 1
    lastCleanupTime = os.clock()
end

function monitorMemory()
    local ws, peak = getWorkingSet()
    if ws <= 0 then return end

    lastWorkingSetMB = ws / 1024 / 1024
    lastPeakMB = peak / 1024 / 1024

    -- Determine threshold based on player location
    lastThreshold = CLEANUP_THRESHOLD_MB
    lastZoneName = ''
    local px, py, pz = getCharCoordinates(playerPed)
    for _, zone in ipairs(HEAVY_ZONES) do
        local dx = px - zone[1]
        local dy = py - zone[2]
        if (dx * dx + dy * dy) < (zone[3] * zone[3]) then
            lastThreshold = CLEANUP_HEAVY_MB
            lastZoneName = zone[4]
            break
        end
    end

    if lastWorkingSetMB >= CRITICAL_THRESHOLD_MB then
        doCleanup(true)
    elseif lastWorkingSetMB >= lastThreshold then
        doCleanup(false)
    end
end

function renderDraw()
    if not GUI_ENABLED or not guiFont then return end

    local wsMB = math.floor(lastWorkingSetMB)
    local peakMB = math.floor(lastPeakMB)
    local threshold = lastThreshold

    -- Background
    renderDrawBox(GUI_X, GUI_Y, GUI_WIDTH, 82, 0xAA000000)

    -- Title
    renderFontDrawText(guiFont, 'AntiCrash v1.7', GUI_X + 4, GUI_Y + 2, 0xFFFFCC00)

    -- Memory usage color
    local usageColor = 0xFF00FF00  -- green
    if wsMB >= CRITICAL_THRESHOLD_MB then
        usageColor = 0xFFFF0000
    elseif wsMB >= threshold then
        usageColor = 0xFFFF8800
    elseif wsMB >= threshold * 0.85 then
        usageColor = 0xFFFFFF00
    end

    -- Working set text
    renderFontDrawText(guiFontSmall,
        string.format('RAM: %d MB / %d MB (cap: %d)', wsMB, TOTAL_RAM_MB, threshold),
        GUI_X + 4, GUI_Y + 16, 0xFFCCCCCC)

    -- Progress bar (relative to total RAM)
    local barX = GUI_X + 4
    local barY = GUI_Y + 30
    local barW = GUI_WIDTH - 8
    local fillRatio = math.min(wsMB / TOTAL_RAM_MB, 1.0)

    renderDrawBox(barX, barY, barW, GUI_BAR_HEIGHT, 0xFF333333)
    renderDrawBox(barX, barY, barW * fillRatio, GUI_BAR_HEIGHT, usageColor)

    -- Threshold marker
    local thresholdPos = barX + barW * (threshold / TOTAL_RAM_MB)
    renderDrawBox(thresholdPos, barY, 2, GUI_BAR_HEIGHT, 0xFFFFFFFF)

    -- Peak marker
    local peakPos = barX + barW * math.min(peakMB / TOTAL_RAM_MB, 1.0)
    renderDrawBox(peakPos, barY, 2, GUI_BAR_HEIGHT, 0xFFFF4444)

    -- Peak text
    renderFontDrawText(guiFontSmall,
        string.format('Peak: %d MB', peakMB),
        GUI_X + 4, GUI_Y + 47, 0xFF888888)

    -- Zone info
    local zoneText = lastZoneName ~= '' and ('{FFAA00}Zone: ' .. lastZoneName) or '{888888}No heavy zone'
    renderFontDrawText(guiFontSmall, zoneText, GUI_X + 4, GUI_Y + 58, 0xFFCCCCCC)

    -- Cleanup counter
    local cleanupText = string.format('Cleanups: %d', cleanupCount)
    if os.clock() - lastCleanupTime < 1.0 then
        cleanupText = cleanupText .. ' {FF4444}[CLEANING]'
    end
    renderFontDrawText(guiFontSmall, cleanupText, GUI_X + 4, GUI_Y + 69, 0xFF888888)
end

function onD3DPresent()
    renderDraw()
end
