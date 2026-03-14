--[[
    Скрипт по дампу Neox Hub и дампу игры (Brainrot-стиль).
    UI: Kairo Library — https://github.com/Itzzavi335/Kairo-Ui-Library
    Запуск: вставить в executor и выполнить.
]]

-- Сервисы
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local CharacterAdded = LocalPlayer.CharacterAdded

-- Порядок редкости: лучший = первый (из дампов Tora / Rayfield)
local RARITY_ORDER = {"Godly", "Celestial", "Secret", "Mythic", "Legendary", "Epic", "Rare", "Common"}

-- Загрузка Kairo UI
local Kairo = loadstring(game:HttpGet("https://raw.githubusercontent.com/Itzzavi335/Kairo-Ui-Library/refs/heads/main/source.luau"))()

local Window = Kairo:CreateWindow({
    Title = "SkrilyaHub",
    Theme = "Crimson",
    Size = UDim2.fromOffset(560, 460),
    Center = true,
    Draggable = true,
    MinimizeKey = Enum.KeyCode.RightShift,
    Config = {
        Enabled = true,
        Folder = "MyScript",
        AutoLoad = true
    }
})

-- Координаты локаций (из дампа)
local LOCATIONS = {
    ["Celestial Area"] = Vector3.new(-24.31, 84.95, -2263.02),
    ["Secret Area"] = Vector3.new(38.02, 62.05, -1717.70),
    ["Common Area"] = Vector3.new(17.94, 12.26, -186.84),
    ["Rare Area"] = Vector3.new(5.56, 15.02, -317.94),
    ["Epic Area"] = Vector3.new(4.60, 15.02, -577.88),
    ["Godly Area"] = Vector3.new(-33.24, 185.33, -3005.78),
    ["Mythic Area"] = Vector3.new(40.00, 25.61, -1349.91),
    ["Legendry Area"] = Vector3.new(-24.79, 28.26, -968.88)
}

local SelectedLocation = nil

-- Состояния для циклов
local AutoBuySpeed1 = false
local AutoBuySpeed5 = false
local AutoBuySpeed10 = false
local AutoRebirthEnabled = false
local AntiRagdollEnabled = false
local NoclipEnabled = false
local FlyEnabled = false
local FlySpeed = 50
local FreezeEnabled = false
local SavedWalkSpeed = 16
local SavedJumpPower = 50

-- Remotes (подставь точные имена если отличаются)
local function getEvents()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then return nil end
    return events
end

local function getSpeedRemote()
    local events = getEvents()
    return events and events:FindFirstChild("Speed")
end
local function getRebirthRemote()
    local events = getEvents()
    return events and events:FindFirstChild("Rebirth")
end
local function getUpgradeRemote()
    local events = getEvents()
    return events and events:FindFirstChild("Upgrade")
end
local function getSellDialogueRemote()
    local events = getEvents()
    return events and events:FindFirstChild("SellDialogue")
end
local function getCarryRemote()
    local events = getEvents()
    return events and events:FindFirstChild("Carry")
end

-- Игровая структура (workspace.GameFolder из дампов)
local function getGameFolder()
    return workspace:FindFirstChild("GameFolder")
end
local function getBrainrotsFolder()
    local gf = getGameFolder()
    return gf and gf:FindFirstChild("Brainrots")
end
local function getGiveArea()
    local gf = getGameFolder()
    return gf and gf:FindFirstChild("GiveArea")
end
local function getPlotsFolder()
    local gf = getGameFolder()
    return gf and gf:FindFirstChild("Plots")
end
-- Участок игрока: атрибут Plot = имя модели участка в Plots
local function getMyPlot()
    local plotId = LocalPlayer:GetAttribute("Plot") or LocalPlayer.Name
    local plots = getPlotsFolder()
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot.Name == tostring(plotId) then return plot end
    end
    return plots:FindFirstChild(LocalPlayer.Name) or plots:GetChildren()[1]
end
-- Симуляция нажатия E для ProximityPrompt (из дампа Tora)
local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.15)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

-- ========== ГЛАВНАЯ ==========
local MainTab = Window:CreateTab("Главная", "rbxassetid://16932740082")
Window:AddParagraph(MainTab, "Добро пожаловать", "Скрипт собран по дампу игры и чужого хаба. RightShift — свернуть/развернуть окно.")
Window:AddButton(MainTab, "Проверка", "Тест уведомления", "rbxassetid://16932740082", function()
    Window:Notify({
        Title = "Скрипт",
        Description = "Работает",
        Content = "Remotes и пути взяты из дампа. Если что-то не срабатывает — проверь имена на сервере.",
        Color = Color3.fromRGB(200, 0, 50),
        Delay = 5
    })
end)

-- ========== ТЕЛЕПОРТ ==========
local TeleportTab = Window:CreateTab("Телепорт", "rbxassetid://16932740082")
Window:AddParagraph(TeleportTab, "Локации", "Выбери зону и нажми Телепорт.")
Window:AddDropdown(TeleportTab, "Локация", "Выбор зоны",
    {"Common Area", "Rare Area", "Epic Area", "Mythic Area", "Legendry Area", "Secret Area", "Godly Area", "Celestial Area"},
    false, "Common Area", function(value)
    SelectedLocation = value
end, "LocationDropdown")
Window:AddButton(TeleportTab, "Телепорт", "Перенести персонажа в выбранную локацию", "rbxassetid://16932740082", function()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local pos = SelectedLocation and LOCATIONS[SelectedLocation]
    if root and pos then
        root.CFrame = CFrame.new(pos)
        Window:Notify({
            Title = "Телепорт",
            Description = SelectedLocation,
            Content = "Перенос выполнен.",
            Color = Color3.fromRGB(0, 200, 80),
            Delay = 2
        })
    else
        Window:Notify({
            Title = "Ошибка",
            Description = "Телепорт",
            Content = "Нет персонажа или не выбрана локация.",
            Color = Color3.fromRGB(255, 80, 80),
            Delay = 3
        })
    end
end)

-- ========== ПОКУПКИ (Speed / Carry / Rebirth) ==========
local BuyTab = Window:CreateTab("Покупки", "rbxassetid://16932740082")
Window:AddParagraph(BuyTab, "Buy Speed", "Автопокупка скорости через ReplicatedStorage.Events.Speed.")
-- Speed: args [1] = "Speed", [2] = 1 (или 5, 10)
Window:AddToggle(BuyTab, "Auto Buy Speed +1", "Цикл InvokeServer(\"Speed\", 1)", false, function(state)
    AutoBuySpeed1 = state
    if state then
        task.spawn(function()
            local speed = getSpeedRemote()
            while AutoBuySpeed1 and speed do
                pcall(function() speed:InvokeServer("Speed", 1) end)
                task.wait(0.5)
            end
        end)
    end
end, "AutoBuySpeed1")
Window:AddToggle(BuyTab, "Auto Buy Speed +5", "Цикл InvokeServer Speed 5", false, function(state)
    AutoBuySpeed5 = state
    if state then
        task.spawn(function()
            local speed = getSpeedRemote()
            while AutoBuySpeed5 and speed do
                pcall(function() speed:InvokeServer("Speed", 5) end)
                task.wait(0.5)
            end
        end)
    end
end, "AutoBuySpeed5")
Window:AddToggle(BuyTab, "Auto Buy Speed +10", "Цикл InvokeServer Speed 10", false, function(state)
    AutoBuySpeed10 = state
    if state then
        task.spawn(function()
            local speed = getSpeedRemote()
            while AutoBuySpeed10 and speed do
                pcall(function() speed:InvokeServer("Speed", 10) end)
                task.wait(0.5)
            end
        end)
    end
end, "AutoBuySpeed10")
-- Rebirth: args [1] = "Rebirth"
Window:AddParagraph(BuyTab, "Rebirth", "Авто-ребёрт при возможности.")
Window:AddToggle(BuyTab, "Auto Rebirth", "Цикл InvokeServer(\"Rebirth\")", false, function(state)
    AutoRebirthEnabled = state
    if state then
        task.spawn(function()
            local rebirth = getRebirthRemote()
            while AutoRebirthEnabled and rebirth do
                pcall(function() rebirth:InvokeServer("Rebirth") end)
                task.wait(0.5)
            end
        end)
    end
end, "AutoRebirth")
-- Carry: InvokeServer("Carry") — из дампа 37e0f1a4862758f0 (Rayfield/KhSaeedHub)
Window:AddButton(BuyTab, "+1 Carry", "Купить переноску", "rbxassetid://16932740082", function()
    local carry = getCarryRemote()
    if carry then pcall(function() carry:InvokeServer("Carry") end) end
end)
-- Upgrade Base: InvokeServer() без аргументов — апгрейд базы (из того же дампа)
Window:AddButton(BuyTab, "Upgrade Base", "Events.Upgrade:InvokeServer() один раз", "rbxassetid://16932740082", function()
    local upgrade = getUpgradeRemote()
    if upgrade then pcall(function() upgrade:InvokeServer() end) end
end)

-- ========== ИГРОК (WalkSpeed, Noclip, Fly, Respawn...) ==========
local PlayerTab = Window:CreateTab("Игрок", "rbxassetid://16932740082")

-- Anti Ragdoll
Window:AddToggle(PlayerTab, "Anti Ragdoll (Anti Hit)", "Отключить ragdoll при ударе", false, function(state)
    AntiRagdollEnabled = state
    local function apply(character)
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not state)
            humanoid.BreakJointsOnDeath = false
        end
    end
    if LocalPlayer.Character then apply(LocalPlayer.Character) end
    CharacterAdded:Connect(apply)
end, "AntiRagdoll")
-- Freeze
Window:AddToggle(PlayerTab, "Freeze", "Закрепить персонажа", false, function(state)
    FreezeEnabled = state
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then root.Anchored = state end
end, "Freeze")
CharacterAdded:Connect(function(char)
    local root = char:WaitForChild("HumanoidRootPart", 5)
    if root then root.Anchored = FreezeEnabled end
end)

Window:AddSlider(PlayerTab, "Walk Speed", "Скорость ходьбы", 16, 500, 16, function(value)
    SavedWalkSpeed = value
    local char = LocalPlayer.Character
    local h = char and char:FindFirstChild("Humanoid")
    if h then h.WalkSpeed = value end
end, "WalkSpeed")
CharacterAdded:Connect(function(char)
    local h = char:WaitForChild("Humanoid", 5)
    if h then h.WalkSpeed = SavedWalkSpeed end
end)

Window:AddSlider(PlayerTab, "Jump Power", "Сила прыжка", 50, 500, 50, function(value)
    SavedJumpPower = value
    local char = LocalPlayer.Character
    local h = char and char:FindFirstChild("Humanoid")
    if h then h.JumpPower = value end
end, "JumpPower")
CharacterAdded:Connect(function(char)
    local h = char:WaitForChild("Humanoid", 5)
    if h then h.JumpPower = SavedJumpPower end
end)

Window:AddSlider(PlayerTab, "Гравитация", "Workspace.Gravity", 0, 196, 196, function(value)
    workspace.Gravity = value
end, "Gravity")

Window:AddInput(PlayerTab, "FOV", "Поле зрения камеры (число)", "70", function(value)
    local n = tonumber(value)
    if n and workspace.CurrentCamera then
        workspace.CurrentCamera.FieldOfView = n
    end
end, "FOV")

-- Noclip
Window:AddToggle(PlayerTab, "Noclip", "Проходить сквозь стены", false, function(state)
    NoclipEnabled = state
end, "Noclip")
RunService.Stepped:Connect(function()
    if not NoclipEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end)

-- Fly
Window:AddToggle(PlayerTab, "Fly", "Полёт (WASD + движение камеры)", false, function(state)
    FlyEnabled = state
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChild("Humanoid")
    if not root or not humanoid then return end
    if state then
        local bodyVel = Instance.new("BodyVelocity")
        bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bodyVel.Velocity = Vector3.zero
        bodyVel.Parent = root
        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root
        bodyVel:GetPropertyChangedSignal("Parent"):Connect(function()
            if bodyVel.Parent then return end
            bodyGyro:Destroy()
        end)
        bodyGyro:GetPropertyChangedSignal("Parent"):Connect(function()
            if bodyGyro.Parent then return end
            bodyVel:Destroy()
        end)
        local flyCon
        flyCon = RunService.Heartbeat:Connect(function()
            if not FlyEnabled or root.Parent ~= char then
                bodyVel:Destroy()
                bodyGyro:Destroy()
                flyCon:Disconnect()
                return
            end
            local cam = workspace.CurrentCamera
            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + (cam.CFrame.LookVector) end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - (cam.CFrame.LookVector) end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - (cam.CFrame.RightVector) end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + (cam.CFrame.RightVector) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.yAxis end
            if dir.Magnitude > 0 then
                dir = dir.Unit * FlySpeed
            end
            bodyVel.Velocity = dir
            bodyGyro.CFrame = cam.CFrame
        end)
    else
        local curChar = LocalPlayer.Character
        local curRoot = curChar and curChar:FindFirstChild("HumanoidRootPart")
        if curRoot then
            local bv = curRoot:FindFirstChildOfClass("BodyVelocity")
            local bg = curRoot:FindFirstChildOfClass("BodyGyro")
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
        end
    end
end, "Fly")
Window:AddSlider(PlayerTab, "Скорость полёта", "Fly speed", 10, 200, 50, function(value)
    FlySpeed = value
end, "FlySpeed")

Window:AddButton(PlayerTab, "Respawn", "Убить персонажа (респавн)", "rbxassetid://16932740082", function()
    local char = LocalPlayer.Character
    if char then char:BreakJoints() end
end)
Window:AddButton(PlayerTab, "Rejoin", "Вернуться на этот же сервер", "rbxassetid://16932740082", function()
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end)

-- ========== ИГРА (VIP двери и т.д.) ==========
local GameTab = Window:CreateTab("Игра", "rbxassetid://16932740082")
Window:AddParagraph(GameTab, "Обход", "Действия с объектами игры (из дампа).")
Window:AddButton(GameTab, "Удалить VIP стены", "Уничтожить VIPDoors в GameFolder", "rbxassetid://16932740082", function()
    local gameFolder = workspace:FindFirstChild("GameFolder")
    local vipDoors = gameFolder and gameFolder:FindFirstChild("VIPDoors")
    if vipDoors then
        vipDoors:Destroy()
        Window:Notify({
            Title = "Игра",
            Description = "VIP Doors",
            Content = "VIP стены удалены.",
            Color = Color3.fromRGB(0, 200, 80),
            Delay = 2
        })
    else
        Window:Notify({
            Title = "Игра",
            Description = "VIP Doors",
            Content = "VIPDoors не найден.",
            Color = Color3.fromRGB(255, 150, 0),
            Delay = 2
        })
    end
end)

-- ========== АВТО ФАРМ / АПГРЕЙД / ПРОДАЖА ==========
local FarmTab = Window:CreateTab("Фарм", "rbxassetid://16932740082")

-- ---- Автофарм: сбор по редкости (GameFolder.Brainrots + ProximityPrompt + E) ----
Window:AddParagraph(FarmTab, "Автофарм (сбор брейнротов)", "Телепорт к промптам в Brainrots по редкости, симуляция E. Лучшая редкость = Godly → Celestial → … → Common.")
local FarmRarity = "Godly"
Window:AddDropdown(FarmTab, "Фармить редкость", "Какую редкость собирать (Best = Godly)", {"Godly", "Celestial", "Secret", "Mythic", "Legendary", "Epic", "Rare", "Common"}, false, "Godly", function(value)
    FarmRarity = value
end, "FarmRarity")
local AutoFarmEnabled = false
Window:AddToggle(FarmTab, "Auto Farm", "Цикл: телепорт к промптам выбранной редкости и нажатие E", false, function(state)
    AutoFarmEnabled = state
    if not state then return end
    task.spawn(function()
        local brainrots = getBrainrotsFolder()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        while AutoFarmEnabled and brainrots and root and root.Parent do
            local rarityFolder = brainrots:FindFirstChild(FarmRarity)
            if rarityFolder then
                for _, desc in ipairs(rarityFolder:GetDescendants()) do
                    if not AutoFarmEnabled then break end
                    if desc:IsA("ProximityPrompt") then
                        local parent = desc.Parent
                        local pos = nil
                        if parent then
                            if parent:IsA("BasePart") then pos = parent.CFrame
                            elseif parent.GetPivot then pos = parent:GetPivot() end
                        end
                        if pos then
                            root.CFrame = pos
                            task.wait(0.2)
                            pressE()
                            task.wait(1.2)
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end, "AutoFarm")

-- ---- Выбор лучшего брейнрота, покупка/установка ----
Window:AddParagraph(FarmTab, "Лучший брейнрот и база", "Give Area = зона выдачи/установки. Участок берётся по атрибуту Plot или имени игрока.")
Window:AddButton(FarmTab, "Телепорт в Give Area", "Переместить персонажа к GiveArea (зона базы)", "rbxassetid://16932740082", function()
    local giveArea = getGiveArea()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if giveArea and hum then
        local pos = (giveArea.GetPivot and giveArea:GetPivot() or giveArea:IsA("BasePart") and giveArea.CFrame or nil)
        if pos then hum:MoveTo(pos.Position) else hum:MoveTo(giveArea.Position) end
        Window:Notify({
            Title = "Give Area",
            Description = "Телепорт",
            Content = "Перенос в зону базы.",
            Color = Color3.fromRGB(0, 200, 80),
            Delay = 2
        })
    else
        Window:Notify({
            Title = "Give Area",
            Description = "Ошибка",
            Content = "GiveArea или персонаж не найден.",
            Color = Color3.fromRGB(255, 80, 80),
            Delay = 2
        })
    end
end)
-- Экипировать лучший по редкости инструмент из Backpack
local function equipBestBrainrot()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if not backpack or not hum then return nil end
    local bestTool = nil
    local bestOrder = 999
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local r = tool:GetAttribute("Rarity") or tool:GetAttribute("rarity") or "Common"
            local idx = table.find(RARITY_ORDER, r) or 999
            if idx < bestOrder then bestOrder = idx; bestTool = tool end
        end
    end
    if bestTool then pcall(function() hum:EquipTool(bestTool) end) end
    return bestTool
end
Window:AddButton(FarmTab, "Экипировать лучший брейнрот", "Взять из Backpack инструмент с лучшей редкостью", "rbxassetid://16932740082", function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if not hum then return end
    local tool = equipBestBrainrot()
    Window:Notify({
        Title = "Экипировка",
        Description = tool and "Надет: " .. tool.Name or "Нет подходящего Tool в Backpack",
        Content = "",
        Color = tool and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(255, 150, 0),
        Delay = 2
    })
end)
-- Авто-постановка лучшего на базу: Give Area → свой участок → нажатие E у промптов
local AutoPlaceOnBaseEnabled = false
Window:AddToggle(FarmTab, "Auto ставить лучший на базу", "Цикл: Give Area → участок → экип лучшего → E у промптов на участке", false, function(state)
    AutoPlaceOnBaseEnabled = state
    if not state then return end
    task.spawn(function()
        local giveArea = getGiveArea()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChild("Humanoid")
        while AutoPlaceOnBaseEnabled and root and root.Parent do
            if giveArea and hum then
                local gp = giveArea.GetPivot and giveArea:GetPivot()
                if gp then hum:MoveTo(gp.Position) else hum:MoveTo(giveArea.Position) end
                task.wait(0.5)
            end
            local plot = getMyPlot()
            if plot then
                local pivot = plot.GetPivot and plot:GetPivot() or plot:FindFirstChild("HumanoidRootPart") and plot.HumanoidRootPart.CFrame
                if pivot then
                    root.CFrame = pivot * CFrame.new(0, 3, 0)
                    task.wait(0.3)
                end
                equipBestBrainrot()
                task.wait(0.2)
                for _, desc in ipairs(plot:GetDescendants()) do
                    if not AutoPlaceOnBaseEnabled then break end
                    if desc:IsA("ProximityPrompt") then
                        local parent = desc.Parent
                        local pos = nil
                        if parent then
                            if parent:IsA("BasePart") then pos = parent.CFrame
                            elseif parent.GetPivot then pos = parent:GetPivot() end
                        end
                        if pos then
                            root.CFrame = pos
                            task.wait(0.15)
                            pressE()
                            task.wait(0.8)
                        end
                    end
                end
            end
            task.wait(1.5)
        end
    end)
end, "AutoPlaceOnBase")

Window:AddParagraph(FarmTab, "Апгрейд и продажа", "Ниже: апгрейд слотов, продажа, выбор по имени/редкости/мутации.")

-- Список мозгов из ReplicatedStorage.Brainrots (названия моделей)
local brainrotNames = {"None"}
task.spawn(function()
    local brainrots = ReplicatedStorage:FindFirstChild("Brainrots")
    if brainrots then
        for _, child in ipairs(brainrots:GetChildren()) do
            if child:IsA("Folder") then
                for _, model in ipairs(child:GetChildren()) do
                    if model:IsA("Model") and not table.find(brainrotNames, model.Name) then
                        table.insert(brainrotNames, model.Name)
                    end
                end
            end
        end
    end
end)

-- Upgrade на базе: args [1] = номер слота (1, 2, ... 10). Апгрейд слотов с 1 по 10.
Window:AddParagraph(FarmTab, "Апгрейд на базе", "Events.Upgrade:InvokeServer(номер_слота). Слоты с 1 по 10.")
Window:AddButton(FarmTab, "Апгрейд слотов 1–10", "Вызов Upgrade:InvokeServer(1) ... InvokeServer(10) по очереди", "rbxassetid://16932740082", function()
    local upgrade = getUpgradeRemote()
    if not upgrade then
        Window:Notify({
            Title = "Апгрейд",
            Description = "Ошибка",
            Content = "Events.Upgrade не найден.",
            Color = Color3.fromRGB(255, 80, 80),
            Delay = 3
        })
        return
    end
    for slot = 1, 10 do
        pcall(function() upgrade:InvokeServer(slot) end)
        task.wait(0.08)
    end
    Window:Notify({
        Title = "Апгрейд",
        Description = "Слоты 1–10",
        Content = "Отправлено 10 апгрейдов.",
        Color = Color3.fromRGB(0, 200, 80),
        Delay = 2
    })
end)
Window:AddParagraph(FarmTab, "Повтор", "Для авто-апгрейда включи тоггл ниже (цикл слотов 1–10).")
local AutoUpgradeSlots1_10 = false
Window:AddToggle(FarmTab, "Auto апгрейд 1–10", "Цикл: слоты 1–10 раз в 2 сек", false, function(state)
    AutoUpgradeSlots1_10 = state
    if state then
        task.spawn(function()
            local upgrade = getUpgradeRemote()
            while AutoUpgradeSlots1_10 and upgrade do
                for slot = 1, 10 do
                    if not AutoUpgradeSlots1_10 then break end
                    pcall(function() upgrade:InvokeServer(slot) end)
                    task.wait(0.08)
                end
                task.wait(2)
            end
        end)
    end
end, "AutoUpgrade1_10")

-- Продажа: Events.SellDialogue — из дампа 37e0f1a4862758f0
Window:AddParagraph(FarmTab, "Продажа", "SellDialogue: InvokeServer(\"SellOne\"), \"SellAll\", или \"Sell\"..имя брейнрота.")
Window:AddButton(FarmTab, "Sell One", "Продать один (SellOne)", "rbxassetid://16932740082", function()
    local sell = getSellDialogueRemote()
    if sell then pcall(function() sell:InvokeServer("SellOne") end) end
end)
Window:AddButton(FarmTab, "Sell All", "Продать всё (SellAll)", "rbxassetid://16932740082", function()
    local sell = getSellDialogueRemote()
    if sell then pcall(function() sell:InvokeServer("SellAll") end) end
end)
local SellByName = ""
Window:AddInput(FarmTab, "Продать по имени", "Имя брейнрота → InvokeServer(\"Sell\"..имя)", "", function(value)
    SellByName = value
end, "SellByNameInput")
Window:AddButton(FarmTab, "Sell по имени", "Вызов SellDialogue:InvokeServer(\"Sell\"..имя)", "rbxassetid://16932740082", function()
    local sell = getSellDialogueRemote()
    if sell and #SellByName > 0 then
        pcall(function() sell:InvokeServer("Sell" .. SellByName) end)
    end
end)

Window:AddDropdown(FarmTab, "Brainrot (имя)", "Выбор по имени", brainrotNames, false, "None", function(value) end, "BrainrotName")
Window:AddDropdown(FarmTab, "Редкость", "Rarity", {"Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Celestial", "Godly"}, false, "Common", function(value) end, "RarityFarm")
Window:AddDropdown(FarmTab, "Мутация", "Mutation", {"Normal", "Gold", "Diamond", "Emerald", "Bloodmoon", "Rainbow", "Godly"}, false, "Normal", function(value) end, "MutationFarm")

-- ========== НАСТРОЙКИ ==========
local SettingsTab = Window:CreateTab("Настройки", "rbxassetid://16932740082")
Window:AddParagraph(SettingsTab, "Тема", "Смена темы интерфейса.")
Window:AddDropdown(SettingsTab, "Тема", "Выбор темы",
    {"Crimson", "Forest", "Ocean", "Purple", "Neon", "Default"}, false, "Crimson", function(value)
    Window:SetTheme(value)
    Window:Notify({
        Title = "Настройки",
        Description = "Тема: " .. value,
        Content = "",
        Color = Color3.fromRGB(100, 180, 255),
        Delay = 2
    })
end, "ThemeDropdown")

-- Уведомление при загрузке
Window:Notify({
    Title = "Скрипт загружен",
    Description = "Kairo UI",
    Content = "Собрано по дампу Neox + дампу игры. RightShift — свернуть окно.",
    Color = Color3.fromRGB(200, 0, 50),
    Delay = 5
})
