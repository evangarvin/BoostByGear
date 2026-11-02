-- BoostByGear by GARV (V3.3 — "Liquid Glass")
-- Core boost/gear logic: unchanged from Stable V1.0 (V3.2 only adds guards).
-- UI: Liquid Glass iOS-26-inspired theme — ultra-low-opacity glass panes,
-- hairline molded edges, full capsule rounding, neon holographic readouts.
-- NOTE: CSP's app UI layer cannot blur the 3D scene behind a window; the glass
-- effect is approximated with translucent layering + sheen + edge highlights.
--
-- V3.3 CHANGE — THE WINDOW BUG:
--  * update(dt) is now script.update(dt). CSP only drives the legacy global
--    form while the app window is on screen (observed in-game while building
--    the sibling DriftAlign app, V3.3 there): with the window closed the
--    limiter stopped being applied, the car sat at the last gear's wastegate
--    with no UI to undo it, and the V3.2 hotkey went dead. script.update runs
--    for the whole session, so the switch — and the hotkey — now behave as
--    documented whether the window is open or not. Nothing else changed.
--
-- V3.2 CHANGES — QUALITY OF LIFE:
--  * The master switch is REMEMBERED: once BOOST CONTROL is on it stays on
--    across sessions and lobbies until you switch it off ([SETTINGS] ACTIVE
--    in config.ini). A toast tells you when the limiter comes back on.
--  * HOTKEY: bind a key or a wheel/gamepad button to toggle the limiter from
--    the bottom row. CSP stores the binding in controls.ini; it works while
--    the window is closed and a toast confirms each toggle.
--  * applyBoost() nil-guards the car and only calls ac.setTurboBoost when the
--    running CSP build actually exposes it — CSP's public API has no such
--    function, so the call raised a Lua error on every active frame. Cars
--    with no turbo, or a turbo AC doesn't let apps adjust, now say so in the
--    status capsule instead of silently doing nothing.
--  * Honest window semantics: CSP keeps calling script.update() while the
--    window is hidden (default LAZY mode; see V3.3 — the global form did
--    not), so the switch — not the window — decides whether boost is
--    limited. ac.onRelease still restores full boost when the script itself
--    unloads (session end, CSP reload).
--
-- V3.1 CHANGES — REVIEW FIXES:
--  * SAFETY: ac.onRelease restores 100% boost if the app unloads while the
--    limiter is active — closing the window mid-session used to leave the car
--    clamped at the last per-gear target with no UI left to undo it. The same
--    handler flushes unsaved slider changes to config.ini.
--  * ACTUAL readout is honest on cars whose max boost isn't 1.0 bar: the %
--    and colour ramp are normalised against the session's observed peak boost
--    (car.turboBoost is BAR, not a 0-1 fraction), and the raw pressure is
--    shown next to the label. Cars topping out at 1.0 bar read as before.
--  * update() nil-guards the car (no more errors on loading screens).
--  * Master-switch animation is framerate-independent.

------------------------------------------------------------------------------
-- CORE LOGIC (V1.0 — V3.2 adds only guards, the hotkey poll and a toast)
------------------------------------------------------------------------------
local boostActive = false -- Master switch (V3.2: restored from config.ini below)

-- Default Settings (Percent)
local gear1 = 50
local gear2 = 60
local gear3 = 70
local gear4 = 100
local gear5 = 100

local currentTarget = 50
local currentGear = 0

-- V3.2: toast helper — safe on CSP builds without ui.toast / ui.Icons
local function uiIcon(name)
    local ok, icon = pcall(function() return ui.Icons[name] end)
    if ok and icon ~= nil then return icon end
    return nil
end
local ICON_ON  = uiIcon('Confirm') or uiIcon('Settings')
local ICON_OFF = uiIcon('Cancel') or uiIcon('Settings')

local function notify(message, isOn)
    if type(ui.toast) ~= 'function' then return end
    pcall(ui.toast, isOn and ICON_ON or ICON_OFF, message)
end

-- V3.2: physics-only car fields, read defensively (older builds may lack them)
local function readTurboInfo(car)
    return car.turboCount, car.adjustableTurbo
end

-- V3.2: if the switch came back ON from the previous session, say so once —
-- after a couple of seconds with a car, so it isn't lost on the loading screen
local restoreNotice = false
local restoreTimer  = 0

-- V3.2: optional hotkey (ac.ControlButton); created once config is loaded
local toggleHotkey    = nil
local hotkeyWidgetOk  = true
local setActive                 -- defined with the config code further down

function script.update(dt)
    -- V3.2: hotkey toggle — polled here so it works with the window closed
    -- (V3.3: script.update, not the global update — see the header)
    if toggleHotkey ~= nil and toggleHotkey:pressed() then
        setActive(not boostActive, true)
    end

    -- Only run logic if the "Active" box is checked
    if boostActive then
        local car = ac.getCar(0)
        if car == nil then return end  -- V3.1: loading screens have no car yet
        currentGear = car.gear -- 0=N, 1=1st, 2=2nd, etc.

        -- Decide boost based on gear
        if currentGear <= 1 then
            currentTarget = gear1 -- Handles Neutral (0) & Reverse (-1) too
        elseif currentGear == 2 then
            currentTarget = gear2
        elseif currentGear == 3 then
            currentTarget = gear3
        elseif currentGear == 4 then
            currentTarget = gear4
        else
            currentTarget = gear5 -- 5th gear and anything higher
        end

        -- Apply the Boost
        applyBoost(currentTarget)

        -- V3.2: one-time "still on from last session" reminder
        if restoreNotice then
            restoreTimer = restoreTimer + (tonumber(dt) or 0)
            if restoreTimer >= 2 then
                restoreNotice = false
                notify('Boost by Gear: limiter is still ON from your last session', true)
            end
        end
    end
end

function applyBoost(valInt)
    local car = ac.getCar(0)
    if car == nil then return end  -- V3.2: onRelease can fire with no car left
    local valDecimal = valInt / 100

    -- Force both systems (Wastegate + Generic)
    if car.adjustableTurbo then
        ac.setTurboWastegate(valDecimal)
    end
    -- V3.2: CSP's public API only documents setTurboWastegate; call the generic
    -- setter only if this build has it instead of erroring every frame
    if type(ac.setTurboBoost) == 'function' then
        ac.setTurboBoost(valDecimal)
    end
end

------------------------------------------------------------------------------
-- AUTO-SAVE / AUTO-LOAD — ac.INIConfig (UNCHANGED from V2.0)
------------------------------------------------------------------------------
local CONFIG_FILE = (type(__dirname) == 'string' and __dirname
    or (ac.getFolder(ac.FolderID.ACApps) .. '/lua/BoostByGear')) .. '/config.ini'

local config = ac.INIConfig.load(CONFIG_FILE)

local function sanitizeBoost(v, fallback)
    v = tonumber(v) or fallback
    v = math.clamp(v, 0, 100)
    return math.floor(v / 10 + 0.5) * 10  -- same snap-to-10s rule as the sliders
end

gear1 = sanitizeBoost(config:get('BOOST_PER_GEAR', 'GEAR_1', gear1), 50)
gear2 = sanitizeBoost(config:get('BOOST_PER_GEAR', 'GEAR_2', gear2), 60)
gear3 = sanitizeBoost(config:get('BOOST_PER_GEAR', 'GEAR_3', gear3), 70)
gear4 = sanitizeBoost(config:get('BOOST_PER_GEAR', 'GEAR_4', gear4), 100)
gear5 = sanitizeBoost(config:get('BOOST_PER_GEAR', 'GEAR_5', gear5), 100)

-- V3.2: the master switch is remembered too (stored as 1/0 so a hand edit of
-- "true"/"false" can't accidentally read as ON)
boostActive   = (tonumber(config:get('SETTINGS', 'ACTIVE', 0)) or 0) ~= 0
restoreNotice = boostActive

local saved1, saved2, saved3, saved4, saved5 = gear1, gear2, gear3, gear4, gear5
local savedActive = boostActive

local function saveConfig()
    config:set('BOOST_PER_GEAR', 'GEAR_1', gear1)
    config:set('BOOST_PER_GEAR', 'GEAR_2', gear2)
    config:set('BOOST_PER_GEAR', 'GEAR_3', gear3)
    config:set('BOOST_PER_GEAR', 'GEAR_4', gear4)
    config:set('BOOST_PER_GEAR', 'GEAR_5', gear5)
    config:set('SETTINGS', 'ACTIVE', boostActive and 1 or 0)
    config:save(CONFIG_FILE)
    saved1, saved2, saved3, saved4, saved5 = gear1, gear2, gear3, gear4, gear5
    savedActive = boostActive
end

local function configDirty()
    return gear1 ~= saved1 or gear2 ~= saved2 or gear3 ~= saved3
        or gear4 ~= saved4 or gear5 ~= saved5 or boostActive ~= savedActive
end

-- V3.2: the one place that flips the master switch — used by the UI capsule
-- and the hotkey. Saves straight away: a toggle is a one-off event, not a drag.
function setActive(state, viaHotkey)
    state = state and true or false
    if state == boostActive then return end
    boostActive   = state
    restoreNotice = false
    if not boostActive then
        applyBoost(100) -- Reset to normal (100%) if turned off (as in V1.0)
    end
    saveConfig()
    if viaHotkey then
        notify(boostActive and 'Boost by Gear: limiter ON'
            or 'Boost by Gear: limiter OFF — full boost', boostActive)
    end
end

-- V3.2: HOTKEY. CSP keeps the binding in controls.ini under this ID; the user
-- assigns it from the HOTKEY row. No default key, so nothing can clash.
if type(ac.ControlButton) == 'function' then
    local ok, btn = pcall(ac.ControlButton, 'BoostByGear/Toggle boost control')
    if ok and btn ~= nil then
        toggleHotkey = btn
        pcall(function() btn:setAlwaysActive(true) end) -- usable in pits/pause too
    end
end

-- V3.1: if the script unloads while the limiter is active (window closed,
-- session change, CSP reload) the last wastegate clamp would stay applied to
-- the car with no UI left to undo it. Restore full boost, and flush any
-- slider change the debounced auto-save hadn't written yet.
if type(ac.onRelease) == 'function' then
    ac.onRelease(function()
        if boostActive then applyBoost(100) end
        if configDirty() then saveConfig() end
    end)
end

------------------------------------------------------------------------------
-- LIQUID GLASS THEME
-- All colors allocated ONCE at load — zero per-frame rgbm garbage.
------------------------------------------------------------------------------
local FONT_MAIN = ui.DWriteFont("fonts/StackSansText-Bold.ttf")
local FONT_GEAR = ui.DWriteFont("fonts/Manrope-Bold.ttf")

-- Glass pane layers (true glassmorphism: ultra-low opacity, scene shows through)
local C_GLASS_BASE  = rgbm(0.03, 0.05, 0.09, 0.35)  -- cool-tinted pane
local C_GLASS_SHEEN = rgbm(1, 1, 1, 0.045)          -- upper-half light wash
local C_EDGE_OUT    = rgbm(1, 1, 1, 0.40)           -- razor-thin outer edge
local C_EDGE_IN     = rgbm(1, 1, 1, 0.07)           -- soft inner molded edge
local C_EDGE_TOP    = rgbm(1, 1, 1, 0.60)           -- top light-catch line

-- Readout surfaces: NO solid fills — translucent tracks only
local C_TRACK       = rgbm(1, 1, 1, 0.06)
local C_TRACK_EDGE  = rgbm(1, 1, 1, 0.18)
local C_TRACK_HOVER = rgbm(1, 1, 1, 0.10)
local C_TRACK_ACT   = rgbm(1, 1, 1, 0.14)

-- Neon holographic accents
local NEON_CYAN     = rgbm(0.30, 0.95, 1.00, 1)
local NEON_CYAN_LO  = rgbm(0.30, 0.95, 1.00, 0.22) -- halo pass
local NEON_GREEN    = rgbm(0.35, 1.00, 0.55, 1)
local NEON_GREEN_LO = rgbm(0.35, 1.00, 0.55, 0.22)
local NEON_AMBER    = rgbm(1.00, 0.80, 0.25, 1)
local NEON_RED      = rgbm(1.00, 0.28, 0.35, 1)
local C_PILL_ON     = rgbm(0.35, 1.00, 0.55, 0.10)
local C_PILL_WARN   = rgbm(1.00, 0.80, 0.25, 0.10)  -- V3.2: "can't limit this car"

local C_TEXT        = rgbm(1, 1, 1, 1)
local C_TEXT_DIM    = rgbm(0.75, 0.80, 0.90, 0.55)  -- cool frosted dim
local C_GHOST_FILL  = rgbm(1, 1, 1, 0.22)           -- inactive gear bars

-- Layout metrics — fluid contours: heavy rounding everywhere
local PAD      = 10
local LEFT_PAD = 8
local PANEL_R  = 18
local BASE_W   = 340
local WIN_W    = BASE_W + PAD * 2
local WIN_H    = 494  -- V3.2: +22 for the HOTKEY row (manifest SIZE matches)

-- Helpers
local function remap(v, lo, hi, nlo, nhi)
    if lo == hi then return nlo end
    return nlo + (v - lo) * (nhi - nlo) / (hi - lo)
end

local lerpScratch = rgbm(0, 0, 0, 1)  -- reused, consumed immediately by draw calls
local function colorLerp(a, b, t)
    t = math.clamp(t, 0, 1)
    lerpScratch.r = a.r + (b.r - a.r) * t
    lerpScratch.g = a.g + (b.g - a.g) * t
    lerpScratch.b = a.b + (b.b - a.b) * t
    lerpScratch.mult = a.mult + (b.mult - a.mult) * t
    return lerpScratch
end

local textCache = {}
local function measureCached(textStr, size, font)
    local key = textStr .. "|" .. size .. "|" .. (font == FONT_GEAR and "g" or "m")
    local m = textCache[key]
    if not m then
        ui.pushDWriteFont(font or FONT_MAIN)
        m = ui.measureDWriteText(textStr, size)
        ui.popDWriteFont()
        textCache[key] = m
    end
    return m
end

local function rectFilled(x1, y1, x2, y2, col, r)
    ui.drawRectFilled(vec2(math.floor(x1) + 0.5, math.floor(y1) + 0.5),
        vec2(math.floor(x2) + 0.5, math.floor(y2) + 0.5), col, r or 0, ui.CornerFlags.All)
end

local function rectStroke(x1, y1, x2, y2, col, r, thickness)
    ui.drawRect(vec2(math.floor(x1) + 0.5, math.floor(y1) + 0.5),
        vec2(math.floor(x2) + 0.5, math.floor(y2) + 0.5), col, r or 0, ui.CornerFlags.All, thickness or 1)
end

-- A sheet of liquid glass: base pane + rounded upper sheen + double hairline
-- edge + top light-catch. 5 draw calls, all batched by ImGui — negligible cost.
local function glassPanel(x1, y1, x2, y2, r)
    rectFilled(x1, y1, x2, y2, C_GLASS_BASE, r)
    ui.drawRectFilled(vec2(x1 + 1, y1 + 1), vec2(x2 - 1, y1 + (y2 - y1) * 0.42),
        C_GLASS_SHEEN, r - 1, ui.CornerFlags.Top)
    rectStroke(x1, y1, x2, y2, C_EDGE_OUT, r, 1)            -- razor outer edge
    rectStroke(x1 + 1.5, y1 + 1.5, x2 - 1.5, y2 - 1.5, C_EDGE_IN, r - 2, 1)
    ui.drawLine(vec2(x1 + r, y1 + 1), vec2(x2 - r, y1 + 1), C_EDGE_TOP, 1)
end

-- Neon capsule fill with floating-glow halo (2 draw calls)
local function neonFill(x1, y1, x2, y2, core, halo, r)
    rectFilled(x1 - 1.5, y1 - 1.5, x2 + 1.5, y2 + 1.5, halo, r + 2)
    rectFilled(x1, y1, x2, y2, core, r)
end

-- Boost colour ramp: neon green → amber → red (thresholds unchanged from V2)
local function boostFillColor(actualPct, targetPct)
    if targetPct <= 0 then return NEON_GREEN end
    local r = actualPct / targetPct
    if r < 0.85 then
        return NEON_GREEN
    elseif r <= 1.02 then
        return colorLerp(NEON_GREEN, NEON_AMBER, remap(r, 0.85, 1.02, 0, 1))
    else
        return colorLerp(NEON_AMBER, NEON_RED, remap(r, 1.02, 1.15, 0, 1))
    end
end

local haloScratch = rgbm(0, 0, 0, 0.22)  -- reused halo tint for dynamic colours
local function haloOf(c)
    haloScratch.r, haloScratch.g, haloScratch.b = c.r, c.g, c.b
    return haloScratch
end

local toggleAnim = 0  -- UI-only animation state for the master switch

-- V3.1: car.turboBoost is pressure in BAR, not a 0-1 fraction — on anything
-- other than a 1.0-bar car the old ACTUAL% (boost*100) ran off-scale against
-- the wastegate-% target and pegged the ramp red. Normalising by the session's
-- observed peak makes ACTUAL "% of this car's max boost", which is what the
-- wastegate target actually commands. Starts at 1.0 so ≤1-bar cars behave
-- exactly as before; grows the first time the car proves it boosts higher.
local peakBoost = 1.0

------------------------------------------------------------------------------
-- DRAW
------------------------------------------------------------------------------
function drawUI()
    -- Safety Init (unchanged from V1.0)
    if not gear1 then gear1 = 50 end
    if not gear2 then gear2 = 60 end
    if not gear3 then gear3 = 70 end
    if not gear4 then gear4 = 100 end
    if not gear5 then gear5 = 100 end

    local car = ac.getCar(0)
    if car == nil then return end

    ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(0, 0))
    ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(8, 5))
    ui.pushDWriteFont(FONT_MAIN)

    -- Display-only reads (do not touch logic variables)
    local liveGear = car.gear
    local gearStr = tostring(liveGear)
    if liveGear == 0 then gearStr = "N" end
    if liveGear == -1 then gearStr = "R" end

    local dispTarget
    if liveGear <= 1 then dispTarget = gear1
    elseif liveGear == 2 then dispTarget = gear2
    elseif liveGear == 3 then dispTarget = gear3
    elseif liveGear == 4 then dispTarget = gear4
    else dispTarget = gear5 end

    local boostBar = car.turboBoost
    if boostBar > peakBoost then peakBoost = boostBar end
    local actualPct = math.floor(boostBar / peakBoost * 100)  -- V3.1: % of observed max

    -- Panel geometry
    local px0, px1 = PAD, WIN_W - PAD
    local cx0, cx1 = px0 + LEFT_PAD + 6, px1 - 14
    local contentW = cx1 - cx0

    -- LIQUID GLASS PANE
    glassPanel(px0, PAD, px1, WIN_H - PAD, PANEL_R)

    -- HEADER
    ui.dwriteDrawText("BOOST BY GEAR", 14, vec2(cx0, 19), C_TEXT)
    local titleM = measureCached("BOOST BY GEAR", 14)
    ui.dwriteDrawText("by GARV", 10, vec2(cx0 + titleM.x + 8, 23), C_TEXT_DIM)
    neonFill(cx0, 38, cx0 + 46, 40, NEON_CYAN, NEON_CYAN_LO, 1)  -- glowing accent

    -- Status capsule (transparent glass, neon edge when live)
    local statusStr = boostActive and "ACTIVE" or "DISABLED"
    local statusCol = boostActive and NEON_GREEN or C_TEXT_DIM
    local pillFill  = boostActive and C_PILL_ON or C_TRACK
    local pillEdge  = boostActive and NEON_GREEN or C_TRACK_EDGE
    -- V3.2: warn when this car's boost can't actually be limited — no turbo at
    -- all, or a turbo AC doesn't expose as adjustable (and no generic setter)
    if boostActive then
        local infoOk, turboCount, adjustable = pcall(readTurboInfo, car)
        if infoOk then
            if turboCount == 0 then
                statusStr = "NO TURBO"
            elseif not adjustable and type(ac.setTurboBoost) ~= 'function' then
                statusStr = "TURBO LOCKED"
            end
            if statusStr ~= "ACTIVE" then
                statusCol, pillFill, pillEdge = NEON_AMBER, C_PILL_WARN, NEON_AMBER
            end
        end
    end
    local sM = measureCached(statusStr, 12)
    local pillW = sM.x + 20
    rectFilled(cx1 - pillW, 14, cx1, 34, pillFill, 10)
    rectStroke(cx1 - pillW, 14, cx1, 34, pillEdge, 10, 1)
    ui.dwriteDrawText(statusStr, 12, vec2(cx1 - pillW + 10, 18), statusCol)

    -- Hairline separator
    rectFilled(px0 + 6, 44, px1 - 6, 45, C_EDGE_IN, 0)

    -- GEAR + READOUTS BLOCK (holographic neon)
    local gy = 56
    ui.dwriteDrawText("GEAR", 11, vec2(cx0 + 8, gy), C_TEXT_DIM)
    ui.pushDWriteFont(FONT_GEAR)
    local gM = measureCached(gearStr, 64, FONT_GEAR)
    ui.dwriteDrawText(gearStr, 64, vec2(cx0 + 32 - gM.x / 2, gy + 10), NEON_CYAN)
    ui.popDWriteFont()

    ui.dwriteDrawText("TARGET", 11, vec2(cx0 + 116, gy + 6), C_TEXT_DIM)
    ui.dwriteDrawText(string.format("%d%%", dispTarget), 28, vec2(cx0 + 116, gy + 22), C_TEXT)

    ui.dwriteDrawText("ACTUAL", 11, vec2(cx0 + 216, gy + 6), C_TEXT_DIM)
    -- V3.1: raw pressure readout — always honest regardless of normalisation
    ui.dwriteDrawText(string.format("%.2f bar", boostBar), 9, vec2(cx0 + 266, gy + 8), C_TEXT_DIM)
    ui.dwriteDrawText(string.format("%d%%", actualPct), 28, vec2(cx0 + 216, gy + 22),
        boostFillColor(actualPct, dispTarget))

    -- BOOST GAUGE — poured glass capsule, neon fill, floating glow
    local by0, by1 = 142, 164
    local capR = (by1 - by0) / 2
    rectFilled(cx0, by0, cx1, by1, C_TRACK, capR)
    rectStroke(cx0, by0, cx1, by1, C_TRACK_EDGE, capR, 1)
    local fillPct = math.clamp(actualPct / 100, 0, 1)
    if fillPct > 0.02 then
        local fc = boostFillColor(actualPct, dispTarget)
        neonFill(cx0 + 2, by0 + 2, cx0 + 2 + (contentW - 4) * fillPct, by1 - 2, fc, haloOf(fc), capR - 2)
    end
    -- Target cap tick — glowing crystal marker
    local tickX = cx0 + contentW * math.clamp(dispTarget / 100, 0, 1)
    rectFilled(tickX - 2.5, by0 - 5, tickX + 2.5, by1 + 5, NEON_CYAN_LO, 3)
    rectFilled(tickX - 1, by0 - 4, tickX + 1, by1 + 4, NEON_CYAN, 1)

    -- PER-GEAR MINI CAPSULES
    local gearVals = { gear1, gear2, gear3, gear4, gear5 }
    local activeIdx
    if liveGear <= 1 then activeIdx = 1
    elseif liveGear >= 5 then activeIdx = 5
    else activeIdx = liveGear end

    local gby0, gby1 = 178, 214
    local cellW = contentW / 5
    for i = 1, 5 do
        local bx0 = cx0 + (i - 1) * cellW + 4
        local bx1 = bx0 + cellW - 8
        rectFilled(bx0, gby0, bx1, gby1, C_TRACK, 9)
        rectStroke(bx0, gby0, bx1, gby1, (i == activeIdx) and NEON_CYAN or C_TRACK_EDGE, 9, (i == activeIdx) and 1.5 or 1)
        local fh = (gby1 - gby0 - 6) * math.clamp(gearVals[i] / 100, 0, 1)
        if fh > 2 then
            if i == activeIdx then
                neonFill(bx0 + 3, gby1 - 3 - fh, bx1 - 3, gby1 - 3, NEON_GREEN, NEON_GREEN_LO, 6)
            else
                rectFilled(bx0 + 3, gby1 - 3 - fh, bx1 - 3, gby1 - 3, C_GHOST_FILL, 6)
            end
        end
        local numStr = (i == 5) and "5+" or tostring(i)
        local nM = measureCached(numStr, 10)
        ui.dwriteDrawText(numStr, 10, vec2((bx0 + bx1) / 2 - nM.x / 2, gby1 + 4),
            (i == activeIdx) and NEON_CYAN or C_TEXT_DIM)
    end

    -- SLIDERS — glass capsules with neon grabs
    ui.dwriteDrawText("BOOST PER GEAR", 11, vec2(cx0, 238), C_TEXT_DIM)

    ui.pushStyleVar(ui.StyleVar.FrameRounding, 11)
    ui.pushStyleVar(ui.StyleVar.GrabRounding, 11)
    ui.pushStyleVar(ui.StyleVar.FrameBorderSize, 1)
    ui.pushStyleColor(ui.StyleColor.FrameBg, C_TRACK)
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, C_TRACK_HOVER)
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, C_TRACK_ACT)
    ui.pushStyleColor(ui.StyleColor.SliderGrab, NEON_CYAN)
    ui.pushStyleColor(ui.StyleColor.SliderGrabActive, NEON_CYAN)
    ui.pushStyleColor(ui.StyleColor.Border, C_TRACK_EDGE)
    ui.pushStyleColor(ui.StyleColor.Text, C_TEXT)

    local sliderX = cx0 + 10
    local sliderW = cx1 - sliderX

    -- 1st Gear (logic + snapping unchanged)
    if activeIdx == 1 then neonFill(cx0, 259, cx0 + 3, 277, NEON_CYAN, NEON_CYAN_LO, 1) end
    ui.setCursor(vec2(sliderX, 256))
    ui.setNextItemWidth(sliderW)
    gear1 = ui.slider('##g1', gear1, 0, 100, '1st Gear: %.0f%%')
    gear1 = math.floor(gear1 / 10 + 0.5) * 10 -- Snap to 10s

    -- 2nd Gear
    if activeIdx == 2 then neonFill(cx0, 289, cx0 + 3, 307, NEON_CYAN, NEON_CYAN_LO, 1) end
    ui.setCursor(vec2(sliderX, 286))
    ui.setNextItemWidth(sliderW)
    gear2 = ui.slider('##g2', gear2, 0, 100, '2nd Gear: %.0f%%')
    gear2 = math.floor(gear2 / 10 + 0.5) * 10

    -- 3rd Gear
    if activeIdx == 3 then neonFill(cx0, 319, cx0 + 3, 337, NEON_CYAN, NEON_CYAN_LO, 1) end
    ui.setCursor(vec2(sliderX, 316))
    ui.setNextItemWidth(sliderW)
    gear3 = ui.slider('##g3', gear3, 0, 100, '3rd Gear: %.0f%%')
    gear3 = math.floor(gear3 / 10 + 0.5) * 10

    -- 4th Gear
    if activeIdx == 4 then neonFill(cx0, 349, cx0 + 3, 367, NEON_CYAN, NEON_CYAN_LO, 1) end
    ui.setCursor(vec2(sliderX, 346))
    ui.setNextItemWidth(sliderW)
    gear4 = ui.slider('##g4', gear4, 0, 100, '4th Gear: %.0f%%')
    gear4 = math.floor(gear4 / 10 + 0.5) * 10

    -- 5th Gear
    if activeIdx == 5 then neonFill(cx0, 379, cx0 + 3, 397, NEON_CYAN, NEON_CYAN_LO, 1) end
    ui.setCursor(vec2(sliderX, 376))
    ui.setNextItemWidth(sliderW)
    gear5 = ui.slider('##g5', gear5, 0, 100, '5th+ Gear: %.0f%%')
    gear5 = math.floor(gear5 / 10 + 0.5) * 10

    ui.popStyleColor(7)
    ui.popStyleVar(3)

    -- Hairline separator
    rectFilled(px0 + 6, 412, px1 - 6, 413, C_EDGE_IN, 0)

    -- MASTER SWITCH (same logic as V1.0 checkbox — liquid glass toggle capsule)
    local ty = 424
    ui.setCursor(vec2(cx0, ty))
    ui.invisibleButton('##master', vec2(200, 26))
    local hovered = ui.itemHovered()
    if ui.itemClicked() then
        setActive(not boostActive, false) -- V3.2: shared path (restores 100% + saves)
    end

    -- V3.1: dt-based easing (12/s ≈ the old 0.2/frame at 60 fps) so the switch
    -- slides at the same speed on any refresh rate
    local uiState = ac.getUI and ac.getUI() or nil
    local uiDt = (uiState and uiState.dt) or 0.0166
    toggleAnim = toggleAnim + ((boostActive and 1 or 0) - toggleAnim) * math.min(1, 12 * uiDt)
    local trackCol = colorLerp(hovered and C_TRACK_HOVER or C_TRACK, NEON_GREEN_LO, toggleAnim)
    rectFilled(cx0, ty + 2, cx0 + 46, ty + 24, trackCol, 11)
    rectStroke(cx0, ty + 2, cx0 + 46, ty + 24, colorLerp(C_TRACK_EDGE, NEON_GREEN, toggleAnim), 11, 1)
    ui.drawCircleFilled(vec2(cx0 + 13 + 20 * toggleAnim, ty + 13), 8, C_TEXT, 16)
    ui.dwriteDrawText("BOOST CONTROL", 13, vec2(cx0 + 58, ty + 5),
        boostActive and C_TEXT or C_TEXT_DIM)

    -- V3.2: HOTKEY ROW — CSP's own binding widget dressed as a glass capsule.
    -- Click it, press a key / wheel / gamepad button; hover + Delete to unbind.
    local hy = ty + 34
    ui.dwriteDrawText("HOTKEY", 11, vec2(cx0, hy + 5), C_TEXT_DIM)
    if toggleHotkey ~= nil and hotkeyWidgetOk then
        ui.pushStyleVar(ui.StyleVar.FrameRounding, 11)
        ui.pushStyleVar(ui.StyleVar.FrameBorderSize, 1)
        ui.pushStyleColor(ui.StyleColor.Button, C_TRACK)
        ui.pushStyleColor(ui.StyleColor.ButtonHovered, C_TRACK_HOVER)
        ui.pushStyleColor(ui.StyleColor.ButtonActive, C_TRACK_ACT)
        ui.pushStyleColor(ui.StyleColor.Border, C_TRACK_EDGE)
        ui.pushStyleColor(ui.StyleColor.Text, C_TEXT)
        ui.setCursor(vec2(cx0 + 58, hy))
        hotkeyWidgetOk = pcall(toggleHotkey.control, toggleHotkey,
            vec2(cx1 - cx0 - 58, 22), nil, 'Click to bind a key or button')
        ui.popStyleColor(5)
        ui.popStyleVar(2)
    else
        ui.dwriteDrawText(toggleHotkey == nil and "needs a newer CSP build"
            or "binding widget unavailable", 11, vec2(cx0 + 58, hy + 5), C_TEXT_DIM)
    end

    ui.popDWriteFont()
    ui.popStyleVar(2)

    -- AUTO-SAVE (UNCHANGED from V2.0): write config.ini only when a value
    -- actually changed AND the mouse button is up — never per-frame.
    if configDirty() and not ui.mouseDown(ui.MouseButton.Left) then
        saveConfig()
    end

    -- AUTO_RESIZE sizing anchor
    ui.setCursor(vec2(WIN_W, WIN_H))
end
