-- === SkrilyaHub Main Script ===
wait(10)

-- === Конфигурация ===
-- Дефолтные значения
local config = {
    AutoStartStory        = {"S", 1, 1, 1},    -- {Mode, Level, Difficulty}
    KillAura = {
        OffsetY     = 0,
        HoverRadius = 5,
        HoverSpeed  = 2,
        GroundOffsetY = 3,
    },
    KeyUse = {                           -- последовательность нажатий
        {Enum.KeyCode.ButtonX, 4},
        {Enum.KeyCode.Z,       1},
        {Enum.KeyCode.ButtonX, 4},
        {Enum.KeyCode.ButtonX, 1},
        {Enum.KeyCode.ButtonX, 4},
        {Enum.KeyCode.C,       1},
    },
    AutoReplay            = true,         -- автоматическое повторение
    AutoNext              = false,        -- перейти к следующему уровню
    AutoLeave             = false,
    ClaimQuest            = true,
    Webhook = {
            Enable = false,
            URL = "https://your.webhook.link/here"
    },
}

-- Переопределение из getgenv().UserConfig
if getgenv().UserConfig then
    for k, v in pairs(getgenv().UserConfig) do
        if typeof(v) == "table" and typeof(config[k]) == "table" then
            for subKey, subVal in pairs(v) do
                config[k][subKey] = subVal
            end
        else
            config[k] = v
        end
    end
end

-- Получаем сервисы
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Переменные игрока и GUI
local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local placeId   = game.PlaceId

-- Флаги
local shouldPressKeys = false

-- === Создаём свой ScreenGui ===
local gui = Instance.new("ScreenGui")
gui.Name           = "SkrilyaHubOverlay"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = playerGui

local blackFrame = Instance.new("Frame")
blackFrame.Size            = UDim2.new(1,0,1,0)
blackFrame.Position        = UDim2.new(0,0,0,0)
blackFrame.BackgroundColor3= Color3.new(0,0,0)
blackFrame.BorderSizePixel = 0
blackFrame.Parent          = gui

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder           = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
listLayout.Padding             = UDim.new(0,10)
listLayout.Parent              = blackFrame

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1,0,0,60)
title.BackgroundTransparency = 1
title.Text                   = "SkrilyaHub"
title.TextColor3             = Color3.new(1,1,1)
title.Font                   = Enum.Font.GothamBlack
title.TextScaled             = true
title.LayoutOrder            = 1
title.Parent                 = blackFrame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name                   = "ToggleBlackScreenButton"
toggleBtn.Size                   = UDim2.new(0,180,0,40)
toggleBtn.Position               = UDim2.new(0.5,-90,1,-50)
toggleBtn.AnchorPoint            = Vector2.new(0.5,0)
toggleBtn.BackgroundColor3       = Color3.fromRGB(50,50,50)
toggleBtn.BorderSizePixel        = 0
toggleBtn.BackgroundTransparency = 0.2
toggleBtn.Text                   = "On/Off Black Screen"
toggleBtn.Font                   = Enum.Font.GothamBold
toggleBtn.TextSize               = 18
toggleBtn.TextColor3             = Color3.new(1,1,1)
toggleBtn.Parent                 = gui

local isBlackVisible = true
toggleBtn.MouseButton1Click:Connect(function()
    isBlackVisible = not isBlackVisible
    blackFrame.Visible = isBlackVisible
end)
toggleBtn.MouseEnter:Connect(function()
    toggleBtn.BackgroundTransparency = 0
end)
toggleBtn.MouseLeave:Connect(function()
    toggleBtn.BackgroundTransparency = 0.2
end)

local orderCounter = 2
local function addGrayText(text)
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1,-40,0,25)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = Color3.fromRGB(180,180,180)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 20
    lbl.TextXAlignment         = Enum.TextXAlignment.Center
    lbl.LayoutOrder            = orderCounter
    lbl.Parent                 = blackFrame
    orderCounter = orderCounter + 1
end

local function safeGet(path)
    local ok,val = pcall(function() return path.Text end)
    return ok and val or "N/A"
end

-- Конфиг сохранения/загрузки (если нужно)
local configName = "SkrilyaHub_Config.json"

if placeId == 17850641257 then
    -- 1) Сохраняем Gems/Gold/Trait
    local function getInventoryCountByName(targetName)
        local window = playerGui:FindFirstChild("Window")
        if not window then return "N/A" end
    
        local inventory = window:FindFirstChild("Inventory")
        if not inventory then return "N/A" end
    
        local frame4 = inventory.Frame and inventory.Frame:FindFirstChild("Frame4")
        if not frame4 then return "N/A" end
    
        local frame1 = frame4:FindFirstChild("Frame1")
        if not frame1 then return "N/A" end
    
        local scrolling = frame1:FindFirstChild("Scrolling")
        if not scrolling then return "N/A" end
    
        for _, item in ipairs(scrolling:GetChildren()) do
            if item:IsA("Frame") then
                local block = item:FindFirstChild("Frame")
                if block then
                    local nameLabel = block:FindFirstChild("BlockName")
                    if nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text == targetName then
                        local numLabel = block:FindFirstChild("Number")
                        if numLabel and numLabel:IsA("TextLabel") then
                            return numLabel.Text
                        end
                    end
                end
            end
        end
    
        return "N/A"
    end

    -- === Безопасное получение текста из вложенного элемента UI ===
    local function safeGetText(...)
        local args = {...}
        local parent = table.remove(args, 1)
        for i, name in ipairs(args) do
            if not parent or not parent:FindFirstChild(name) then
                return "N/A"
            end
            parent = parent[name]
        end
        if parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox") then
            return parent.Text
        else
            return "N/A"
        end
    end

    local data = {
        Gems        = safeGetText(playerGui, "ScreenGui", "Frame", "Gems", "Gems", "TextLabel"),
        Gold        = safeGetText(playerGui, "ScreenGui", "Frame", "Gems", "Gold", "TextLabel"),
        Ticket      = getInventoryCountByName("Ticket"),
        TraitReroll = getInventoryCountByName("Trait Reroll"),
    }
    writefile(configName, HttpService:JSONEncode(data))
    addGrayText("Gems: "  .. data.Gems)
    addGrayText("Gold: "  .. data.Gold)
    addGrayText("Trait Reroll: " .. data.TraitReroll)
    addGrayText("Tickets: "      .. data.Ticket)
    addGrayText("Config saved")

    local function ClaimAvailableQuests()
        if not config.ClaimQuest then return end
    
        for i = 0, 4 do -- Daily quests
            local args = { "Daily", i }
            pcall(function()
                ReplicatedStorage.Event.Quest:FireServer(unpack(args))
            end)
            task.wait(0.1)
        end
    
        for i = 0, 7 do -- Weekly quests
            local args = { "Weekly", i }
            pcall(function()
                ReplicatedStorage.Event.Quest:FireServer(unpack(args))
            end)
            task.wait(0.1)
        end
    
        print("[SkrilyaHub] Квесты собраны.(Наверное)")
    end
    
    ClaimAvailableQuests()

    -- 2) Запускаем автостарт + Ready спустя 2 секунды
    task.delay(2, function()
        local function AutoStartAndReady()
            -- Вычисляем текст режима по config.AutoStartStory[1]
            local modeKey  = config.AutoStartStory[1]
            local modeMap  = { S = "Story", R = "Raid", I = "Inf", Inf = "Inf", Infinity = "Inf" }
            local modeText = modeMap[tostring(modeKey)] or tostring(modeKey)

            -- a) Создаём комнату
            local argsCreate = {
                [1] = "Create",
                [2] = modeText,
                [3] = config.AutoStartStory[2],
                [4] = config.AutoStartStory[3],
                [5] = config.AutoStartStory[4],
                [6] = true,
            }
            ReplicatedStorage.Event.JoinRoom:FireServer(unpack(argsCreate))
            task.wait(0.5)

            -- b) Телепортируемся
            local argsTeleport = {
                [1] = "TeleGameplay",
                [2] = modeText,
                [3] = config.AutoStartStory[2],
                [4] = config.AutoStartStory[3],
                [5] = config.AutoStartStory[4],
                [6] = true,
            }
            ReplicatedStorage.Event.JoinRoom:FireServer(unpack(argsTeleport))

            -- c) Ждём RoomUi и нажимаем Ready
            local roomUi = playerGui:WaitForChild("RoomUi", 10)
            if not roomUi then
                warn("[SkrilyaHub] RoomUi не появился")
                return
            end
            local readyFrame = roomUi:FindFirstChild("Ready")
            if readyFrame and readyFrame.Frame and readyFrame.Frame:FindFirstChild("StartButton") then
                local btn = readyFrame.Frame.StartButton
                local ls  = btn:FindFirstChild("Butom") and btn.Butom:FindFirstChild("LocalScript")
                local ev  = ls and ls:FindFirstChild("RemoteEvent")
                if ev then ev:FireServer() end
            end
        end

        AutoStartAndReady()
    end)
else
        -- === Безопасное получение текста из вложенного элемента UI ===
    local function safeGetText(...)
        local args = {...}
        local parent = table.remove(args, 1)
        for i, name in ipairs(args) do
            if not parent or not parent:FindFirstChild(name) then
                return "N/A"
            end
            parent = parent[name]
        end
        if parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox") then
            return parent.Text
        else
            return "N/A"
        end
    end

    -- Здесь загрузка конфиг-файла для любых других placeId
    if isfile(configName) then
        local loaded = HttpService:JSONDecode(readfile(configName))
        addGrayText("Loaded from config:")
        addGrayText("Gems: "  .. (loaded.Gems or "N/A"))
        addGrayText("Gold: "  .. (loaded.Gold or "N/A"))
        addGrayText("Trait Reroll: " .. (loaded.TraitReroll or "N/A"))
        addGrayText("Tickets: "      .. (loaded.Ticket or "N/A"))
    else
        addGrayText("Config not found")
    end
end

-- === Auto kill aura + авто-перезапуск или Next ===
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

-- читаем из конфига
local offsetY       = config.KillAura.OffsetY
local hoverRadius   = config.KillAura.HoverRadius
local hoverSpeed    = config.KillAura.HoverSpeed
local restartInterval = config.RestartIfNoMobsAfter

-- Нажимаем Ready с максимум 3 попыток, затем пропускаем
do
    local attempts = 0
    local success = false

    while attempts < 3 do
        attempts = attempts + 1

        -- Проверяем, что GUI точно существует
        local roomUi = playerGui:FindFirstChild("RoomUi")
        local readyFrame = roomUi and roomUi:FindFirstChild("Ready")
        local btn = readyFrame and readyFrame.Frame and readyFrame.Frame:FindFirstChild("StartButton")
        local ls  = btn and btn:FindFirstChild("Butom") and btn.Butom:FindFirstChild("LocalScript")
        local ev  = ls and ls:FindFirstChild("RemoteEvent")

        if ev then
            local ok, err = pcall(function()
                ev:FireServer()
            end)
            if ok then
                success = true
                break
            end
        end

        -- Если не получилось, ждём секунду и пробуем снова
        task.wait(2)
    end

    if not success then
        warn("[SkrilyaHub] Не удалось нажать кнопку Ready после 3 попыток, пропуск...")
    end
end

-- создаём «платформу» под игроком
local platform = Instance.new("Part")
platform.Size        = Vector3.new(15,1,15)
platform.Anchored    = true
platform.CanCollide  = false
platform.Transparency= 0.5
platform.Parent      = workspace
RunService.Heartbeat:Connect(function()
    platform.CFrame = hrp.CFrame * CFrame.new(0, -2, 0)
end)

-- поиск ближайшего моба
-- === ПОИСК ЖИВОГО МОБА ===
local function getClosestMob()
    for _, mob in ipairs(workspace.Enemy.Mob:GetChildren()) do
        if mob:IsA("Model")
        and mob:FindFirstChild("Humanoid")
        and mob:FindFirstChild("HumanoidRootPart")
        and mob.Humanoid.Health > 0 then
            return mob
        end
    end
    return nil
end

-- === РЕЙКАСТ ПО ЗЕМЛЕ ===
local function getGroundYAtPosition(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {workspace}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = true

    local origin = pos + Vector3.new(0, 10, 0)
    local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), rayParams)
    return (result and result.Position.Y) or pos.Y
end

-- === ПЕРЕМЕЩЕНИЕ НА ЗЕМЛЮ У МОБА ===
local function flyToTarget(pos)
    -- разблокируем физику
    character.Humanoid.PlatformStand = false
    character.Humanoid.Sit = false
    hrp.Anchored = false

    -- телепорт на 2 юнита над землёй
    local groundY = getGroundYAtPosition(pos)
    hrp.CFrame = CFrame.new(pos.X, groundY + 2, pos.Z)
end

-- === ВРАЩЕНИЕ ВОКРУГ ЦЕЛИ ===
local function orbitAround(targetPart, stopSignal)
    local angle = 0
    local radius = config.KillAura.HoverRadius or 5
    local speed  = config.KillAura.HoverSpeed   or 2

    return RunService.Heartbeat:Connect(function(dt)
        if stopSignal.stop or not targetPart.Parent then
            stopSignal.conn:Disconnect()
            return
        end
        angle = angle + dt * speed
        local offset = Vector3.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)
        local pos = targetPart.Position + offset
        local y   = getGroundYAtPosition(pos) + 2
        hrp.CFrame = CFrame.new(Vector3.new(pos.X, y, pos.Z), 
                                Vector3.new(targetPart.Position.X, y, targetPart.Position.Z))
    end)
end


-- нажатие клавиш по конфигу
local function pressKey(keyCode, duration)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, nil)
    task.wait(duration or 0.1)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, nil)
end

local function pressKeysSequence()
    while true do
        if shouldPressKeys then
            for _, keyData in ipairs(config.KeyUse) do
                for i = 1, keyData[2] do
                    pressKey(keyData[1])
                    task.wait(0.1)
                end
            end
        end
        task.wait(0.5)
    end
end

task.spawn(pressKeysSequence)

-- главный цикл фарма
task.spawn(function()
    noMobsTime = 0

    while true do
        local mob = getClosestMob()
        if mob then
            shouldPressKeys = false
            noMobsTime = 0

            print("👉 Летим к мобу:", mob.Name)
            flyToTarget(mob.HumanoidRootPart.Position)
            task.wait(0.3)
            print("✅ Прилетели")
            
            shouldPressKeys = true

            local stopSignal = { stop = false }
            local orbitConn = orbitAround(mob.HumanoidRootPart, stopSignal)

            repeat
                task.wait(0.2)
            until mob.Humanoid.Health <= 0 or not mob.Parent

            stopSignal.stop = true
            orbitConn:Disconnect()

            shouldPressKeys = false

            -- Infinity Mode
            local modeKey = tostring(config.AutoStartStory[1]):upper()
            if modeKey == "I" or modeKey == "INF" or modeKey == "INFINITY" then
                local roomUi = playerGui:WaitForChild("RoomUi", 2)
                local nextF  = roomUi and roomUi:FindFirstChild("NextF")
                if nextF then
                    pcall(function()
                        nextF.Frame.StartButton.Ready.LocalScript.RemoteEvent:FireServer()
                    end)
                end
            end
        else
            noMobsTime += 0.2
        end

        task.wait(0.2)
    end
end)

-- === Настройка вебхука ===
local HttpService = game:GetService("HttpService")
local webhookConfig = getgenv().UserConfig and getgenv().UserConfig.Webhook or {}
local webhookURL = webhookConfig.URL
local webhookEnabled = webhookConfig.Enable

local function sendWebhookEmbed(title, description, fields)
    if not webhookEnabled or not webhookURL or webhookURL == "" then return end

    local embed = {
        title = title,
        description = description,
        color = 0x00FF99,
        fields = fields,
        footer = {
            text = "SkrilyaHub",
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    local request = (syn and syn.request) or http and http.request or http_request or (fluxus and fluxus.request) or request
    if request then
        request({
            Url = webhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                embeds = {embed}
            })
        })
    end
end

-- === Отправка результатов матча ===
local function reportMatchResults(winUI)
    if not winUI then return end

    local frame = winUI:FindFirstChild("Frame")
    if not frame then return end

    local prog = frame:FindFirstChild("progmain")
    if not prog then return end

    if not winUI then return end

    local frame = winUI:WaitForChild("Frame", 2)
    local prog = frame:WaitForChild("progmain", 2)

    local username = player.Name .. " (@" .. player.DisplayName .. ")"
    local lvlData = prog:FindFirstChild("lvl") and prog.lvl:FindFirstChild("Level")
    local level = lvlData and lvlData:FindFirstChild("OnLevel")
    local xpBar = lvlData and lvlData:FindFirstChild("ExpLoad")
    local xpGain = lvlData and lvlData:FindFirstChild("Exp")
    local playtime = prog:FindFirstChild("time") and prog.time:FindFirstChild("playtime")
    local victoryLabel = prog:FindFirstChild("victory")
    local rewards = prog:FindFirstChild("reward") and prog.reward:FindFirstChild("ScrollingFrame")

    local fields = {
        {
            name = "👤 User",
            value = "`" .. username .. "`",
            inline = false
        },
        {
            name = "📈 Level",
            value = string.format(
                "%s [%s] %s exp",
                level and level.Text or "?",
                xpBar and xpBar.Text or "?",
                xpGain and xpGain.Text or "?"
            ),
            inline = false
        },
        {
            name = "⌛ Playtime",
            value = playtime and playtime.Text or "N/A",
            inline = false
        },
        {
            name = "🏆 Result",
            value = (victoryLabel and victoryLabel:IsA("TextLabel") and victoryLabel.Text ~= "" and victoryLabel.Text) or "UNKNOWN",
            inline = false
        }
    }

    if rewards then
        local rewardMap = {}
    
        for _, item in ipairs(rewards:GetChildren()) do
            local amountLabel = item:FindFirstChild("TextLabel")
            local amountText = amountLabel and amountLabel.Text or "x?"
    
            local name = nil
    
            -- 1. Из WorldModel
            local block = item:FindFirstChild("BlockImage")
            if block and block:FindFirstChild("WorldModel") then
                local worldModel = block.WorldModel
                for _, obj in ipairs(worldModel:GetChildren()) do
                    name = obj.Name
                    break
                end
            end
    
            -- 2. Из дочерних объектов (например, Gems и т.п.)
            if not name then
                for _, obj in ipairs(item:GetChildren()) do
                    if obj:IsA("UIGradient") or obj:IsA("UICorner") or obj:IsA("UIStroke") then
                        if obj.Name ~= "UIStroke" and obj.Name ~= "UIGradient" and obj.Name ~= "UICorner" then
                            name = obj.Name
                            break
                        end
                    end
                end
            end
    
            -- 3. Группировка
            if name then
                local amount = tonumber(amountText:match("x(%d+)")) or 1
                rewardMap[name] = (rewardMap[name] or 0) + amount
            end
        end
    
        -- 4. Создание строк для Discord
        local rewardLines = {}
        for itemName, totalAmount in pairs(rewardMap) do
            table.insert(rewardLines, string.format("x%d %s", totalAmount, itemName))
        end
    
        if #rewardLines > 0 then
            table.insert(fields, {
                name = "🎁 Rewards",
                value = table.concat(rewardLines, "\n"),
                inline = false
            })
        end
    
        -- 5. Обновление конфига: прибавляем награды
        local configFile = "SkrilyaHub_Config.json"
        local currentData = {}
    
        if isfile(configFile) then
            local ok, result = pcall(function()
                return HttpService:JSONDecode(readfile(configFile))
            end)
            if ok and typeof(result) == "table" then
                currentData = result
            end
        end
    
        for name, value in pairs(rewardMap) do
            local configKeyMap = {
                ["Gems"] = "Gems",
                ["Gold"] = "Gold",
                ["Ticket"] = "Ticket",
                ["Trait Reroll"] = "TraitReroll"
            }
        
            local key = configKeyMap[name]
            if key then
                -- Удаляем x, запятые, пробелы и берём только цифры
                local clean = tostring(currentData[key] or ""):gsub(",", ""):match("%d+")
                local old = tonumber(clean) or 0
                currentData[key] = tostring(old + value)
            end
        end

        writefile(configFile, HttpService:JSONEncode(currentData))
        print("[SkrilyaHub] Примерно обновлены значения в конфиге:", currentData)
    end

    sendWebhookEmbed("🎮 Match Results", "Вот результаты последней игры:", fields)
end

-- === Хук на появление UI Win ===

local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
playerGui.ChildAdded:Connect(function(child)
    if child.Name == "Win" or child.Name == "Lost" then
        task.delay(1, function()
            reportMatchResults(child)

            -- авто-нажатие Next / Replay / Lobby
            local remote = game:GetService("ReplicatedStorage").Events.WinEvent.Buttom
            if remote and remote:IsA("RemoteEvent") then
                if config.AutoNext then
                    remote:FireServer("NextLv")
                elseif config.AutoReplay then
                    remote:FireServer("RPlay")
                elseif config.AutoLeave then
                    remote:FireServer("RLobby")
                end
            end
        end)
    end
end)

-- Удаление текстур и декалей
local function removeTextures(root)
    for _, c in pairs(root:GetDescendants()) do
        if c:IsA("Texture") or c:IsA("Decal") then
            c:Destroy()
        end
    end
end

local function simplifyToGrayCubes(root)
    for _, obj in pairs(root:GetDescendants()) do
        if obj:IsA("Texture") or obj:IsA("Decal") or obj:IsA("SurfaceAppearance") then
            obj:Destroy()
        elseif obj:IsA("SpecialMesh") or obj:IsA("FileMesh") or obj:IsA("MeshPart") then
            if obj:IsA("MeshPart") then
                local cube = Instance.new("Part")
                cube.Size       = obj.Size
                cube.CFrame     = obj.CFrame
                cube.Anchored   = obj.Anchored
                cube.CanCollide = obj.CanCollide
                cube.Parent     = obj.Parent
                obj:Destroy()
            else
                obj:Destroy()
            end
        elseif obj:IsA("BasePart") then
            obj.Material    = Enum.Material.Plastic
            obj.Color       = Color3.fromRGB(128, 128, 128)
            obj.Reflectance = 0
            obj.Transparency= 0
            obj.Shape       = Enum.PartType.Block
        end
    end
end

removeTextures(workspace)
simplifyToGrayCubes(workspace)

print("[SkrilyaHub] Конфигурация загружена успешно.")
