local font       = draw.CreateFont("Verdana", 14, 600)
local fontLarge  = draw.CreateFont("Verdana", 18, 800)
local fontHuge   = draw.CreateFont("Verdana", 28, 900)

local CFG = {
    distances = {
        lockon    = 450,
        beambreak = 540,
        splash    = 160
    },
    zones = {
        danger   = {min = 0,   max = 160},
        optimal  = {min = 160, max = 400},
        caution  = {min = 400, max = 500},
        critical = {min = 500, max = 540}
    },
    colors = {
        danger     = {255, 50, 50, 255},
        caution    = {255, 180, 40, 255},
        optimal    = {40, 255, 120, 255},
        beam       = {80, 180, 255, 200},
        white      = {255, 255, 255, 255},
        hudBg      = {0, 0, 0, 200},
        hudBorder  = {255, 255, 255, 150}
    }
}

local STATE = {
    me           = nil,
    target       = nil,
    distToTarget = 0,
    zoneStatus   = "",
    zoneColor    = nil,
    nearestClass = "",
    nearestEnemy = 0,
    threatLvl    = 0
}

local function cloneVec(v)
    return Vector3(v.x, v.y, v.z)
end

local function getClassName(classNum)
    local names = {
        [1] = "Scout",     [2] = "Sniper", [3] = "Soldier",
        [4] = "Demoman",   [5] = "Medic",  [6] = "Heavy",
        [7] = "Pyro",      [8] = "Spy",    [9] = "Engineer"
    }
    return names[classNum] or "Unknown"
end

local function getActiveHealTarget()
    if not STATE.me or not STATE.me:IsAlive() then
        return nil
    end

    local weapon = STATE.me:GetPropEntity("m_hActiveWeapon")
    if not weapon or not weapon:IsValid() then
        return nil
    end
    if not weapon:IsMedigun() then
        return nil
    end

    local target = weapon:GetPropEntity("m_hHealingTarget")
    if not target or not target:IsValid() then
        return nil
    end
    if not target:IsAlive() then
        return nil
    end

    return target
end

local function UPDATE()
    STATE.me = entities.GetLocalPlayer()
    if not STATE.me or not STATE.me:IsAlive() then
        STATE.target       = nil
        STATE.zoneStatus   = ""
        STATE.nearestClass = ""
        STATE.nearestEnemy = 0
        STATE.threatLvl    = 0
        return
    end

    local mePos   = STATE.me:GetAbsOrigin()
    local meTeam  = STATE.me:GetTeamNumber()

    STATE.target = getActiveHealTarget()

    if STATE.target then
        local targetPos   = STATE.target:GetAbsOrigin()
        local diff        = cloneVec(mePos) - cloneVec(targetPos)
        STATE.distToTarget = diff:Length()

        if STATE.distToTarget < CFG.zones.danger.max then
            STATE.zoneStatus = "TOO CLOSE"
            STATE.zoneColor = CFG.colors.danger
        elseif STATE.distToTarget > CFG.zones.critical.min then
            STATE.zoneStatus = "BEAM BREAKING"
            STATE.zoneColor = CFG.colors.danger
        elseif STATE.distToTarget > CFG.zones.caution.min then
            STATE.zoneStatus = "STRETCHING"
            STATE.zoneColor = CFG.colors.caution
        else
            STATE.zoneStatus = "OPTIMAL"
            STATE.zoneColor = CFG.colors.optimal
        end
    else
        STATE.zoneStatus = "NO TARGET"
        STATE.zoneColor = CFG.colors.caution
        return
    end

    STATE.nearestEnemy = 9999
    STATE.nearestClass = ""
    STATE.threatLvl = 0

    local enemyTeam = (meTeam == 2) and 3 or 2
    local allPlayers = entities.FindByClass("CTFPlayer")

    for _, enemy in ipairs(allPlayers) do
        if not enemy:IsAlive() then
            goto continue
        end

        if enemy:GetTeamNumber() ~= enemyTeam then
            goto continue
        end

        local ePos   = enemy:GetAbsOrigin()
        local diff   = cloneVec(ePos) - cloneVec(mePos)
        local dist   = diff:Length()

        if dist < STATE.nearestEnemy then
            STATE.nearestEnemy = dist
            STATE.nearestClass = getClassName(enemy:GetPropInt("m_iClass"))
        end

        if dist < 500 and STATE.threatLvl < 0.3 then
            STATE.threatLvl = 0.3
        end

        ::continue::
    end
end

local function worldToScreen(worldPos)
    return client.WorldToScreen(worldPos)
end

local function drawWorldCircle(center, radius, r, g, b, a, segments)
    segments = segments or 32
    local prevScreen = nil

    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2
        local px = center.x + math.cos(angle) * radius
        local py = center.y + math.sin(angle) * radius
        local pz = center.z
        local screen = worldToScreen(Vector3(px, py, pz))

        if screen then
            if prevScreen then
                draw.Color(r, g, b, a)
                draw.Line(prevScreen[1], prevScreen[2], screen[1], screen[2])
            end
            prevScreen = screen
        else
            prevScreen = nil
        end
    end
end

local function drawHUD()
    local sw, sh = draw.GetScreenSize()
    local hudW = 340
    local hudH = 80
    local hudX = math.floor((sw - hudW) / 2)
    local hudY = 50

    draw.Color(CFG.colors.hudBg[1], CFG.colors.hudBg[2], CFG.colors.hudBg[3], CFG.colors.hudBg[4])
    draw.FilledRect(hudX, hudY, hudX + hudW, hudY + hudH)

    draw.Color(CFG.colors.hudBorder[1], CFG.colors.hudBorder[2], CFG.colors.hudBorder[3], CFG.colors.hudBorder[4])
    draw.OutlinedRect(hudX, hudY, hudX + hudW, hudY + hudH)

    if not STATE.target or not STATE.target:IsAlive() then
        draw.SetFont(fontLarge)
        local noTargetText = "NO HEAL TARGET"
        local ntw, nth = draw.GetTextSize(noTargetText)
        draw.Color(CFG.colors.white[1], CFG.colors.white[2], CFG.colors.white[3], 255)
        draw.Text(math.floor(sw / 2 - ntw / 2), hudY + 12, noTargetText)

        draw.SetFont(font)
        local equipText = "Equip Medigun and heal a teammate"
        local etw, eth = draw.GetTextSize(equipText)
        draw.Color(200, 200, 200, 200)
        draw.Text(math.floor(sw / 2 - etw / 2), hudY + 42, equipText)
        return
    end

    local targetName = STATE.target:GetName() or "Unknown"

    draw.SetFont(fontLarge)
    local line1 = targetName .. "  |  " .. string.format("%.0f HU", STATE.distToTarget)
    local line1W, _ = draw.GetTextSize(line1)
    draw.Color(255, 255, 255, 255)
    draw.Text(math.floor(sw / 2 - line1W / 2), hudY + 8, line1)

    draw.SetFont(fontHuge)
    local line2 = STATE.zoneStatus
    local line2W, _ = draw.GetTextSize(line2)
    draw.Color(STATE.zoneColor[1], STATE.zoneColor[2], STATE.zoneColor[3], 255)
    draw.Text(math.floor(sw / 2 - line2W / 2), hudY + 30, line2)

    draw.SetFont(font)
    local line3 = ""
    if STATE.nearestEnemy < 9999 then
        line3 = "Threat: " .. STATE.nearestClass .. " (" .. string.format("%.0f HU", STATE.nearestEnemy) .. ")"
    else
        line3 = "No threats nearby"
    end

    local line3Color = CFG.colors.white
    if STATE.threatLvl > 0.2 then
        line3Color = CFG.colors.caution
    end

    local line3W, _ = draw.GetTextSize(line3)
    draw.Color(line3Color[1], line3Color[2], line3Color[3], 220)
    draw.Text(math.floor(sw / 2 - line3W / 2), hudY + 62, line3)
end

local function onDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    if not STATE.me or not STATE.me:IsAlive() then
        drawHUD()
        return
    end

    drawHUD()

    if not STATE.target or not STATE.target:IsAlive() then
        return
    end

    local mePos     = STATE.me:GetAbsOrigin()
    local targetPos = STATE.target:GetAbsOrigin()

    local lineColor = CFG.colors.beam
    if STATE.zoneColor then
        lineColor = STATE.zoneColor
    end

    local meScreen     = worldToScreen(mePos)
    local targetScreen = worldToScreen(targetPos)

    if meScreen and targetScreen then
        draw.Color(lineColor[1], lineColor[2], lineColor[3], 160)
        draw.Line(meScreen[1], meScreen[2], targetScreen[1], targetScreen[2])
    end

    drawWorldCircle(targetPos, CFG.distances.lockon,
        lineColor[1], lineColor[2], lineColor[3], 80)
end

callbacks.Register("CreateMove", "medicPosTick", UPDATE)
callbacks.Register("Draw", "medicPosDraw", onDraw)
