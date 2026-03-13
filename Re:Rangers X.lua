local g = getgenv and getgenv() or _G
if g.SkrilyaHubLoaded then
	return
end
g.SkrilyaHubLoaded = true

print("ver. 1315")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- executor HTTP helper (syn.request / http.request / request ...)
local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local LocalPlayer = Players.LocalPlayer

-- Ждём загрузки игры
repeat task.wait(0.1) until game:IsLoaded()
task.wait(1)
local lpWait = 0
while not LocalPlayer and lpWait < 100 do
	task.wait(0.1)
	LocalPlayer = Players.LocalPlayer
	lpWait = lpWait + 1
end
pcall(function()
	LocalPlayer:WaitForChild("PlayerGui", 30)
end)
pcall(function()
	ReplicatedStorage:WaitForChild("Remote", 15)
end)
task.wait(0.5)

-- Автоперезапуск при телепорте в другое лобби: подставь сырую ссылку на этот скрипт (raw GitHub/Pastebin и т.д.)
local SCRIPT_RELOAD_URL = ""
local queueteleport = (function()
	local g = getgenv()
	if type(g.queue_on_teleport) == "function" then return g.queue_on_teleport end
	if g.syn and type(g.syn.queue_on_teleport) == "function" then return g.syn.queue_on_teleport end
	if g.fluxus and type(g.fluxus.queue_on_teleport) == "function" then return g.fluxus.queue_on_teleport end
	return nil
end)()

-- Load FluentPlus + SaveManager + InterfaceManager
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ============ REMOTES CACHE ============
local RS = ReplicatedStorage

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function killLightingBlur()
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst:IsA("BlurEffect") or inst:IsA("DepthOfFieldEffect") then
			inst.Enabled = false
			inst:Destroy()
		end
	end
end

-- разово при запуске
killLightingBlur()

-- если игра попытается снова создать эффекты в Lighting
Lighting.ChildAdded:Connect(function(child)
	if child:IsA("BlurEffect") or child:IsA("DepthOfFieldEffect") then
		task.defer(function()
			child.Enabled = false
			child:Destroy()
		end)
	end
end)

-- ============ SHARED GAME DATA (CRAFTING / LEVELS / ITEMS) ============
local Shared = RS:FindFirstChild("Shared")
local CraftingRecipes, GameWorldLevels, ItemsInfo, GetData = nil, nil, nil, nil

-- Прямой доступ к Player_Data без зависимости от Game (во избежание конфликта с глобальным DataModel Game)
local function getPlayerDataRaw()
	local pdRoot = RS:FindFirstChild("Player_Data")
	if not pdRoot or not LocalPlayer then return nil end
	return pdRoot:FindFirstChild(LocalPlayer.Name)
end

pcall(function()
	if not Shared then return end
	local Info = Shared:WaitForChild("Info", 10)
	if not Info then return end

	-- Те же пути, что использует UI крафта: см. ReplicatedStorage.UIS.Crafting.Crafting
	CraftingRecipes = require(Info:WaitForChild("CraftingRecipes"))
	ItemsInfo = require(Info:WaitForChild("Items"))

	local GameWorld = Info:WaitForChild("GameWorld")
	GameWorldLevels = require(GameWorld:WaitForChild("Levels"))

	-- Модуль-агрегатор методов GetItemStats/GetUnitStats и т.п.
	GetData = require(Shared:WaitForChild("GetData"))
end)

-- ============ EVO + GEARS FARM STATE ============
local EvoFarm = {
	CraftingRecipes = CraftingRecipes,
	Levels = GameWorldLevels,
	GetData = GetData,
	ItemsInfo = ItemsInfo,
	Targets = {
		EvoItems = {},
		Gears = {},
	},
	Config = nil, -- будет заполнен при загрузке/сохранении
	GlobalNeed = {}, -- суммарная потребность по материалам (текущий круг крафта)
	TotalNeed = {}, -- BaseNeed * craftsTotal (общий список на все крафты)
	NeedCount = {},  -- текущая глобальная нехватка (globalLacking) = max(0, GlobalNeed - have)
	DropIndex = {},
	StageRoute = {},
	CurrentStageIndex = 1,
	StagesState = {}, -- строковый ключ стадии -> 0/1
	MatchCounter = 0, -- счётчик матчей для периодического пересчёта маршрута
	StatusLabel = nil, -- параграф статуса в UI
}

-- Списки крафтовых целей (эво-материалы и гиры) по ItemsInfo
local function buildEvoFarmTargets()
	local evoItems, gears = {}, {}
	if not ItemsInfo or type(ItemsInfo) ~= "table" then
		return { EvoItems = evoItems, Gears = gears }
	end

	for name, data in pairs(ItemsInfo) do
		if type(data) == "table" then
			if data.Iscraft and data.Type == "Material" then
				table.insert(evoItems, name)
			elseif data.Iscraft and data.Type == "Gear" then
				table.insert(gears, name)
			end
		end
	end

	table.sort(evoItems)
	table.sort(gears)

	return {
		EvoItems = evoItems,
		Gears = gears,
	}
end

pcall(function()
	EvoFarm.Targets = buildEvoFarmTargets()
end)

-- ============ EVO FARM CONFIG (файл) ============
local EVO_FARM_FILE = "SkrilyaHub_Config/SkrilyaHub_EvoFarm.json"

local function loadEvoFarmConfig()
	-- отдельный FileIO, чтобы не зависеть от порядка объявления getFileIO ниже
	local g = getgenv and getgenv() or _G
	local rf = (g.syn and g.syn.readfile) or (g.readfile) or readfile
	local iof = (g.syn and g.syn.isfile) or (g.isfile) or isfile
	if type(rf) ~= "function" or type(iof) ~= "function" then
		return { targets = {}, stages = {} }
	end
	if not iof(EVO_FARM_FILE) then
		return { targets = {}, stages = {} }
	end
	local ok, data = pcall(function()
		local raw = rf(EVO_FARM_FILE)
		if not raw or #raw == 0 then return {} end
		return HttpService:JSONDecode(raw)
	end)
	data = (ok and data and type(data) == "table") and data or {}
	if type(data.targets) ~= "table" then data.targets = {} end
	if type(data.stages) ~= "table" then data.stages = {} end
	-- craftsTotal: 0/nil = infinite; craftsCompleted: сколько уже нафармлено
	if type(data.craftsTotal) ~= "number" then data.craftsTotal = 1 end
	if type(data.craftsCompleted) ~= "number" then data.craftsCompleted = 0 end
	return data
end

local function saveEvoFarmConfig(cfg)
	local g = getgenv and getgenv() or _G
	local wf = (g.syn and g.syn.writefile) or (g.writefile) or writefile
	local iof = (g.syn and g.syn.isfile) or (g.isfile) or isfile
	local mkdir = (g.syn and g.syn.makefolder) or (g.makefolder) or makefolder
	local isdir = (g.syn and g.syn.isfolder) or (g.isfolder) or isfolder
	if type(wf) ~= "function" then return false end
	pcall(function()
		local dir = EVO_FARM_FILE:match("^(.+)/[^/]+$")
		if dir and type(mkdir) == "function" and type(isdir) == "function" and not isdir(dir) then
			mkdir(dir)
		end
		wf(EVO_FARM_FILE, HttpService:JSONEncode(cfg or {}))
	end)
	return true
end

EvoFarm.Config = loadEvoFarmConfig()
EvoFarm.StagesState = EvoFarm.Config.stages or {}

local function updateEvoFarmStatus()
	local label = EvoFarm.StatusLabel
	if not (label and label.SetDesc) then
		return
	end

	local totalNeed, totalLacking = 0, 0
	for matName, needTotal in pairs(EvoFarm.GlobalNeed or {}) do
		if type(needTotal) == "number" and needTotal > 0 then
			totalNeed += needTotal
			local missing = 0
			if EvoFarm.NeedCount and type(EvoFarm.NeedCount[matName]) == "number" then
				missing = math.max(0, EvoFarm.NeedCount[matName])
			else
				missing = needTotal
			end
			totalLacking += missing
		end
	end

	local desc
	local craftsTotal = tonumber(EvoFarm.Config and EvoFarm.Config.craftsTotal) or 0
	local craftsCompleted = tonumber(EvoFarm.Config and EvoFarm.Config.craftsCompleted) or 0
	local craftPart = ""
	if craftsTotal > 0 then
		craftPart = string.format(" | Craft %d/%d", craftsCompleted, craftsTotal)
	end

	if totalNeed <= 0 then
		desc = "Idle" .. craftPart
	else
		local farmed = math.max(0, totalNeed - totalLacking)
		if farmed > totalNeed then farmed = totalNeed end
		-- Список конкретных материалов, которые сейчас фармятся
		local currentNames = {}
		local step = EvoFarm.StageRoute and EvoFarm.StageRoute[EvoFarm.CurrentStageIndex]

		local function pushMat(matName)
			if #currentNames >= 3 then return end
			local missing = EvoFarm.NeedCount and EvoFarm.NeedCount[matName]
			if not (missing and missing > 0) then return end
			local meta = getItemMeta and getItemMeta(matName) or nil
			local display = (meta and meta.DisplayName) or matName
			table.insert(currentNames, string.format("%s (%d)", tostring(display), missing))
		end

		if step and step.materials then
			for matName in pairs(step.materials) do
				pushMat(matName)
				if #currentNames >= 3 then break end
			end
		end

		-- Если по текущей карте нет активных материалов, показываем любые нужные
		if #currentNames == 0 then
			for matName, missing in pairs(EvoFarm.NeedCount or {}) do
				if missing and missing > 0 then
					pushMat(matName)
					if #currentNames >= 3 then break end
				end
			end
		end

		local nowPart = (#currentNames > 0) and (" | Now: " .. table.concat(currentNames, ", ")) or ""
		desc = string.format("Farm %d / %d items%s%s", farmed, totalNeed, nowPart, craftPart)
	end

	label:SetDesc(desc)
end

-- Текстовый отчёт по EvoFarm для вебхука: "Ресурс (have/need) ✅"
local function buildEvoFarmProgressTextForWebhook(maxLines)
	maxLines = maxLines or 10
	if not EvoFarm or not EvoFarm.GlobalNeed or not next(EvoFarm.GlobalNeed) then
		return nil
	end

	local lines = {}
	for matName, needTotal in pairs(EvoFarm.GlobalNeed) do
		if type(needTotal) == "number" and needTotal > 0 then
			local missing = EvoFarm.NeedCount and tonumber(EvoFarm.NeedCount[matName]) or needTotal
			missing = math.max(0, missing)
			local have = needTotal - missing
			if have < 0 then have = 0 end

			local meta = getItemMeta and getItemMeta(matName) or nil
			local display = (meta and meta.DisplayName) or matName
			local doneMark = (missing <= 0) and " ✅" or ""
			table.insert(lines, string.format("%s (%d/%d)%s", tostring(display), have, needTotal, doneMark))
		end
	end

	table.sort(lines)

	if #lines == 0 then
		return nil
	end

	if #lines > maxLines then
		local extra = #lines - maxLines
		while #lines > maxLines do
			table.remove(lines)
		end
		table.insert(lines, string.format("... and %d more", extra))
	end

	return table.concat(lines, "\n")
end

-- ============ RECIPE RESOLVER ============
local function accumulateRequirements(targetName, multiplier, needCount, visited)
	if not CraftingRecipes or not targetName then return end
	visited = visited or {}

	-- защита от циклов
	if visited[targetName] then
		return
	end
	visited[targetName] = true

	local recipe = CraftingRecipes[targetName]
	if recipe and type(recipe.Requirement) == "table" then
		for ingName, ingCount in pairs(recipe.Requirement) do
			if type(ingName) == "string" and type(ingCount) == "number" and ingCount > 0 then
				accumulateRequirements(ingName, ingCount * multiplier, needCount, visited)
			end
		end
	else
		-- базовый материал
		local current = needCount[targetName] or 0
		needCount[targetName] = current + multiplier
	end

	visited[targetName] = nil
end

-- targetsConfig: { [targetName] = wantedCount }, возвращает базовую суммарную потребность по материалам
local function resolveTargetsToNeedCount(targetsConfig)
	local needCount = {}
	if not targetsConfig or type(targetsConfig) ~= "table" then
		return needCount
	end

	for name, wanted in pairs(targetsConfig) do
		if type(name) == "string" and type(wanted) == "number" and wanted > 0 then
			accumulateRequirements(name, wanted, needCount, {})
		end
	end

	return needCount
end

-- ============ DROP INDEX BUILDER ============
local function buildDropIndex()
	local index = {}
	if not GameWorldLevels or type(GameWorldLevels) ~= "table" then
		return index
	end

	for worldKey, levels in pairs(GameWorldLevels) do
		if type(levels) == "table" then
			for levelKey, levelData in pairs(levels) do
				if type(levelData) == "table" and type(levelData.Items) == "table" then
					local waveName = levelData.Wave or levelKey
					local modeHint = "Story"
					if tostring(levelKey):find("_RangerStage") or tostring(waveName):find("_RangerStage") then
						modeHint = "Ranger Stage"
					elseif tostring(levelKey):find("Raid") or tostring(waveName):find("Raid") then
						modeHint = "Raids Stage"
					end
					for _, drop in ipairs(levelData.Items) do
						if type(drop) == "table" and type(drop.Name) == "string" then
							local list = index[drop.Name]
							if not list then
								list = {}
								index[drop.Name] = list
							end
							table.insert(list, {
								world = worldKey,
								levelKey = levelKey,
								levelName = levelData.Name or levelKey,
								modeHint = modeHint,
								dropRate = drop.DropRate or 0,
								min = drop.MinDrop or 0,
								max = drop.MaxDrop or 0,
								layoutOrder = levelData.LayoutOrder or 0,
							})
						end
					end
				end
			end
		end
	end

	return index
end

-- ============ STAGE ROUTE BUILDER ============
local function getItemMeta(name)
	if not ItemsInfo or type(ItemsInfo) ~= "table" then return nil end
	return ItemsInfo[name]
end

local function hasChallengeObtain(meta)
	if not meta or type(meta.ObtainFrom) ~= "table" then return false end
	for _, src in ipairs(meta.ObtainFrom) do
		if src == "Challenge" then
			return true
		end
	end
	return false
end

local function isMaterialAutoFarmable(matName, dropIndex)
	dropIndex = dropIndex or EvoFarm.DropIndex
	if not dropIndex then return false end
	local drops = dropIndex[matName]
	if not drops or #drops == 0 then
		return false
	end
	local meta = getItemMeta(matName)
	if hasChallengeObtain(meta) then
		-- Challenge-ресурсы игрок фармит сам
		return false
	end
	return true
end

local function buildStageRoute(needCount, dropIndex)
	local stageMaterials = {} -- stageKey -> { world, levelKey, mode, layoutOrder, materials = {}, expectedBase = 0 }

	for itemName, missing in pairs(needCount) do
		if missing > 0 then
			if not isMaterialAutoFarmable(itemName, dropIndex) then
				-- пропускаем неподдерживаемые материалы (Challenge/без дропа)
				continue
			end
			local drops = dropIndex[itemName]
			if drops and #drops > 0 then
				for _, info in ipairs(drops) do
					local stageKey = tostring(info.world) .. "|" .. tostring(info.levelKey)
					local entry = stageMaterials[stageKey]
					if not entry then
						entry = {
							world = info.world,
							levelKey = info.levelKey,
							mode = info.modeHint,
							layoutOrder = info.layoutOrder or 0,
							materials = {},
							expectedBase = 0,
						}
						stageMaterials[stageKey] = entry
					end
					entry.materials[itemName] = true
					local expected = (info.dropRate or 0) * (((info.min or 0) + (info.max or 0)) / 2)
					entry.expectedBase = (entry.expectedBase or 0) + expected
				end
			end
		end
	end

	local route = {}
	for _, entry in pairs(stageMaterials) do
		local matsCount = 0
		for _ in pairs(entry.materials) do
			matsCount += 1
		end
		local score = (entry.expectedBase or 0) + matsCount * 10
		table.insert(route, {
			mode = entry.mode,
			world = entry.world,
			chapter = entry.levelKey,
			layoutOrder = entry.layoutOrder,
			key = tostring(entry.mode) .. "_" .. tostring(entry.world) .. "_" .. tostring(entry.levelKey),
			materials = entry.materials,
			score = score,
		})
	end

	table.sort(route, function(a, b)
		if (a.score or 0) ~= (b.score or 0) then
			return (a.score or 0) > (b.score or 0)
		end
		if a.mode ~= b.mode then
			return tostring(a.mode) < tostring(b.mode)
		end
		if a.world ~= b.world then
			return tostring(a.world) < tostring(b.world)
		end
		return (a.layoutOrder or 0) < (b.layoutOrder or 0)
	end)

	return route
end

-- Обновить NeedCount, DropIndex и StageRoute по текущим целям конфига
local function rebuildEvoFarmFromConfig()
	if not EvoFarm.Config then
		EvoFarm.Config = { targets = {}, stages = {} }
	end
	local targets = EvoFarm.Config.targets or {}
	-- базовая суммарная потребность по материалам (с учётом вложенных рецептов)
	local baseNeed = resolveTargetsToNeedCount(targets)
	EvoFarm.BaseNeed = baseNeed

	if not EvoFarm.DropIndex or next(EvoFarm.DropIndex) == nil then
		EvoFarm.DropIndex = buildDropIndex()
	end

	-- отфильтровать только автофармовые материалы (есть дроп, нет Challenge)
	local globalNeed = {}
	for matName, count in pairs(baseNeed) do
		if type(matName) == "string" and type(count) == "number" and count > 0 then
			if isMaterialAutoFarmable(matName, EvoFarm.DropIndex) then
				globalNeed[matName] = count
			end
		end
	end
	EvoFarm.GlobalNeed = globalNeed

	-- общий список: BaseNeed * craftsTotal (0 = infinite, нет общего списка)
	local craftsTotalNum = tonumber(EvoFarm.Config and EvoFarm.Config.craftsTotal) or 1
	local totalNeedMap = {}
	if craftsTotalNum > 0 then
		for matName, count in pairs(baseNeed) do
			if type(matName) == "string" and type(count) == "number" and count > 0 then
				totalNeedMap[matName] = count * craftsTotalNum
			end
		end
	end
	EvoFarm.TotalNeed = totalNeedMap

	-- первоначальная глобальная нехватка (NeedCount) по инвентарю
	local function initialRecalc()
		local needCount = {}
		local pd = getPlayerDataRaw()
		if pd then
			local itemsFolder = pd:FindFirstChild("Items")
			if itemsFolder then
				for matName, needTotal in pairs(EvoFarm.GlobalNeed or {}) do
					local have = 0
					local item = itemsFolder:FindFirstChild(matName)
					if item and item:FindFirstChild("Amount") and item.Amount:IsA("ValueBase") then
						have = tonumber(item.Amount.Value) or 0
					end
					local lacking = math.max(0, (needTotal or 0) - have)
					needCount[matName] = lacking
				end
			end
		end
		-- если по каким-то причинам данные игрока недоступны, считаем, что не хватает всего GlobalNeed
		if not next(needCount) then
			for matName, needTotal in pairs(EvoFarm.GlobalNeed or {}) do
				if type(needTotal) == "number" and needTotal > 0 then
					needCount[matName] = needTotal
				end
			end
		end
		EvoFarm.NeedCount = needCount
	end

	initialRecalc()

	-- построить маршрут по текущему globalLacking
	EvoFarm.StageRoute = buildStageRoute(EvoFarm.NeedCount or {}, EvoFarm.DropIndex)
	EvoFarm.CurrentStageIndex = 1

	-- Инициализировать состояния стадий (0) для нового маршрута
	local stagesState = EvoFarm.Config.stages or {}
	for _, step in ipairs(EvoFarm.StageRoute) do
		if step.key then
			if stagesState[step.key] ~= 0 and stagesState[step.key] ~= 1 then
				stagesState[step.key] = 0
			end
		end
	end
	EvoFarm.Config.stages = stagesState
	EvoFarm.StagesState = stagesState
	saveEvoFarmConfig(EvoFarm.Config)
	updateEvoFarmStatus()
end

-- Выбор целей из UI: selectedTargets = { [name] = wantedCount }
local function setEvoFarmTargets(selectedTargets)
	EvoFarm.Config = EvoFarm.Config or { targets = {}, stages = {} }
	EvoFarm.Config.targets = selectedTargets or {}
	-- при смене целей сбрасываем прогресс стадий
	EvoFarm.Config.stages = {}
	rebuildEvoFarmFromConfig()
end

local function wfc(parent, name, timeout)
	return parent:WaitForChild(name, timeout or 10)
end

local Remote
local function getRemote()
	if Remote then return Remote end
	local R = wfc(RS, "Remote")
	local Server = wfc(R, "Server")
	local OnGame = wfc(Server, "OnGame")
	local Voting = wfc(OnGame, "Voting")
	Remote = {
		PlayRoomEvent = wfc(wfc(Server, "PlayRoom"), "Event"),
		SpeedGamepass = wfc(R, "SpeedGamepass"),
		LobbyPortal = wfc(wfc(Server, "Lobby"), "PortalEvent"),
		LobbyDaily = wfc(wfc(Server, "Lobby"), "DailyRewards"),
		LobbyCode = wfc(wfc(Server, "Lobby"), "Code"),
		ClaimBp = wfc(wfc(R, "Events"), "ClaimBp"),
		EventClaimBp = wfc(wfc(R, "Events"), "EventClaimBp"),
		SettingEvent = wfc(wfc(Server, "Settings"), "Setting_Event"),
		Merchant = wfc(wfc(Server, "Gameplay"), "Merchant"),
		Raid_Shop = wfc(wfc(Server, "Gameplay"), "Raid_Shop"),
		JJK_RaidShop = wfc(wfc(Server, "Gameplay"), "JJK_RaidShop"),
		Calamity_Shop = wfc(wfc(Server, "Gameplay"), "Calamity_Shop"),
		UnitsGacha = wfc(wfc(Server, "Gambling"), "UnitsGacha"),
		SelectRateUpBanner = wfc(wfc(Server, "Gambling"), "SelectRateUpBanner"),
		RerollTrait = wfc(wfc(Server, "Gambling"), "RerollTrait"),
		RestartMatch = wfc(OnGame, "RestartMatch"),
		VotePlaying = wfc(Voting, "VotePlaying"),
		VoteRetry = wfc(Voting, "VoteRetry"),
		VoteNext = wfc(Voting, "VoteNext"),
		Units = {
			Deployment = wfc(wfc(Server, "Units"), "Deployment"),
			Equip = wfc(wfc(Server, "Units"), "Equip"),
			UnEquip = wfc(wfc(Server, "Units"), "UnEquip"),
			UnEquipAll = wfc(wfc(Server, "Units"), "UnEquipAll"),
			EquipBest = wfc(wfc(Server, "Units"), "EquipBest"),
			Feed = wfc(wfc(Server, "Units"), "Feed"),
			UnitsEvolve = wfc(wfc(Server, "Units"), "UnitsEvolve"),
			LimitBreaks = wfc(wfc(Server, "Units"), "LimitBreaks"),
			EvolveTier = wfc(wfc(Server, "Units"), "EvolveTier"),
			RemoveEvolveTier = wfc(wfc(Server, "Units"), "RemoveEvolveTier"),
			UpgradeCollectionSize = wfc(wfc(Server, "Units"), "UpgradeCollectionSize"),
			AutoPlay = wfc(wfc(Server, "Units"), "AutoPlay"),
		},
	}
	return Remote
end

-- ============ GAME API: ROOM ============
local Game = {}

function Game.EnterMode(modeName, doStart)
	local r = getRemote()
	r.PlayRoomEvent:FireServer(modeName)
	if doStart then
		task.wait(0.6)
		r.PlayRoomEvent:FireServer("Start")
	end
end

function Game.EnterDungeon(options)
	options = options or { Difficulty = "Normal", DebuffCount = 0, ActiveDebuffs = {} }
	getRemote().PlayRoomEvent:FireServer("Dungeon", options)
end

function Game.EnterGrailDungeon(difficulty)
	getRemote().PlayRoomEvent:FireServer("GrailDungeon", { Difficulty = difficulty or "Easy" })
end

function Game.EnterInfinityCastle(floor)
	getRemote().PlayRoomEvent:FireServer("Infinity-Castle", { Floor = floor or 1 })
end

function Game.EnterBossEvent(difficulty)
	getRemote().PlayRoomEvent:FireServer("Boss-Event", { Difficulty = difficulty or "Normal" })
end

function Game.EnterSBR()
	getRemote().PlayRoomEvent:FireServer("SBR", { CreateRaidRoom = true })
end

function Game.CreateRoom(kind)
	local r = getRemote()
	if kind == "challenge" then
		r.PlayRoomEvent:FireServer("Create", { CreateChallengeRoom = true })
	elseif kind == "raid" then
		r.PlayRoomEvent:FireServer("Create", { CreateRaidRoom = true })
	else
		r.PlayRoomEvent:FireServer("Create")
	end
end

function Game.StartGame()
	getRemote().PlayRoomEvent:FireServer("Start")
end

function Game.LeaveRoom()
	getRemote().PlayRoomEvent:FireServer("Leave")
end

function Game.RemoveRoom()
	getRemote().PlayRoomEvent:FireServer("Remove")
end

function Game.JoinRoom(roomFolder)
	if roomFolder and roomFolder.Parent then
		getRemote().PlayRoomEvent:FireServer("Join-Room", { Room = roomFolder })
	end
end

function Game.SetSpeed(speed)
	getRemote().SpeedGamepass:FireServer(math.clamp(speed or 1, 1, 3))
end

-- Текущая скорость в матче (1, 2 или 3) — по дампу: ReplicatedStorage.Values.Game.GameSpeed
function Game.GetGameSpeed()
	local values = RS:FindFirstChild("Values")
	local gameFolder = values and values:FindFirstChild("Game")
	local gameSpeed = gameFolder and gameFolder:FindFirstChild("GameSpeed")
	if gameSpeed and gameSpeed:IsA("ValueBase") then
		return tonumber(gameSpeed.Value) or 1
	end
	return nil
end

-- Есть ли геймпасс на x3 скорость — по дампу: Player_Data[player].Gamepass["3x Game Speed"].Value
function Game.HasSpeedGamepass3x(plr)
	local pd = Game.GetPlayerData(plr)
	if not pd then return false end
	local gp = pd:FindFirstChild("Gamepass")
	if not gp then return false end
	local speed3 = gp:FindFirstChild("3x Game Speed")
	return speed3 and speed3:IsA("ValueBase") and speed3.Value == true
end

-- Включён ли автоплей — по дампу: Player_Data[player].Data.AutoPlay.Value
function Game.IsAutoPlayEnabled(plr)
	local pd = Game.GetPlayerData(plr)
	if not pd then return false end
	local data = pd:FindFirstChild("Data")
	if not data then return false end
	local autoPlay = data:FindFirstChild("AutoPlay")
	return autoPlay and autoPlay:IsA("ValueBase") and autoPlay.Value == true
end

function Game.SetRoomMode(mode)
	getRemote().PlayRoomEvent:FireServer("Change-Mode", { Mode = mode })
end

function Game.SetRoomWorld(worldName)
	getRemote().PlayRoomEvent:FireServer("Change-World", { World = worldName })
end

function Game.SetRoomChapter(chapterName)
	getRemote().PlayRoomEvent:FireServer("Change-Chapter", { Chapter = chapterName })
end

function Game.SetRoomDifficulty(difficulty)
	getRemote().PlayRoomEvent:FireServer("Change-Difficulty", { Difficulty = difficulty })
end

function Game.ToggleFriendOnly()
	getRemote().PlayRoomEvent:FireServer("Change-FriendOnly")
end

function Game.GetRoomList()
	local PlayRoom = RS:FindFirstChild("PlayRoom")
	if not PlayRoom then return {} end
	local list = {}
	for _, room in ipairs(PlayRoom:GetChildren()) do
		if room:FindFirstChild("Submit") and room.Submit.Value == true then
			table.insert(list, room)
		end
	end
	return list
end

-- In lobby = no Yen on LocalPlayer; in game = LocalPlayer.Yen exists
local function isInLobby()
	return not LocalPlayer:FindFirstChild("Yen")
end

-- Геймпассы в лобби (Auto Trait Reroll, Fast Star)
local function applyLobbyGamepasses()
	if not isInLobby() then return end
	local pd = RS:FindFirstChild("Player_Data")
	if not pd then return end
	pd = pd:FindFirstChild(LocalPlayer.Name)
	if not pd then return end
	local gp = pd:FindFirstChild("Gamepass")
	if not gp then return end
	local names = {"Auto Trait Reroll", "Fast Star"}
	for _, name in ipairs(names) do
		local v = gp:FindFirstChild(name)
		if v and v:IsA("ValueBase") then
			v.Value = true
			print("[SkrilyaHub] Set " .. name .. " = true")
		end
	end
end

task.spawn(function()
	task.wait(2)
	if isInLobby() then
		local pd = RS:WaitForChild("Player_Data", 10)
		if pd and pd:FindFirstChild(LocalPlayer.Name) then
			applyLobbyGamepasses()
		end
	end
end)

-- ============ RANGER STAGE AUTOFARM ============
local RANGER_PROGRESS_FILE = "SkrilyaHub_Config/SkrilyaHub_RangerProgress.json"
local RANGER_WORLDS = { "Namek", "Naruto", "OnePiece", "SAO", "TokyoGhoul", "JJK" }
local RANGER_DISPLAY_TO_INTERNAL = {
	["Voocha Village"] = "OnePiece",
	["Green Planet"] = "Namek",
	["Leaf Village"] = "Naruto",
	["Ghoul City"] = "TokyoGhoul",
	["Virtual Sword"] = "SAO",
	["Tokyo City"] = "JJK",
}
local RANGER_INTERNAL_TO_DISPLAY = {}
for display, internal in pairs(RANGER_DISPLAY_TO_INTERNAL) do
	RANGER_INTERNAL_TO_DISPLAY[internal] = display
end

local ROMAN_TO_NUM = { I = 1, II = 2, III = 3, IV = 4 }
local NUM_TO_ROMAN = { [1] = "I", [2] = "II", [3] = "III", [4] = "IV" }

local function getFileIO()
	local g = getgenv and getgenv() or _G
	local rf = (g.syn and g.syn.readfile) or (g.readfile) or readfile
	local wf = (g.syn and g.syn.writefile) or (g.writefile) or writefile
	local iof = (g.syn and g.syn.isfile) or (g.isfile) or isfile
	local mkdir = (g.syn and g.syn.makefolder) or (g.makefolder) or makefolder
	local isdir = (g.syn and g.syn.isfolder) or (g.isfolder) or isfolder
	return rf, wf, iof, mkdir, isdir
end

local RangerProgressConfig = {}
function RangerProgressConfig.Load()
	local rf, _, iof = getFileIO()
	if type(rf) ~= "function" or type(iof) ~= "function" then
		return {}
	end
	if not iof(RANGER_PROGRESS_FILE) then
		return {}
	end
	local ok, data = pcall(function()
		local raw = rf(RANGER_PROGRESS_FILE)
		if not raw or #raw == 0 then return {} end
		return HttpService:JSONDecode(raw)
	end)
	return (ok and data and type(data) == "table") and data or {}
end

function RangerProgressConfig.Save(data)
	local _, wf, iof, mkdir, isdir = getFileIO()
	if type(wf) ~= "function" then return false end
	pcall(function()
		local dir = RANGER_PROGRESS_FILE:match("^(.+)/[^/]+$")
		if dir and type(mkdir) == "function" and type(isdir) == "function" and not isdir(dir) then
			mkdir(dir)
		end
		wf(RANGER_PROGRESS_FILE, HttpService:JSONEncode(data or {}))
	end)
	return true
end

function RangerProgressConfig.Reset()
	return RangerProgressConfig.Save({})
end

function RangerProgressConfig.GetCompleted(key)
	local data = RangerProgressConfig.Load()
	return (data[key] == 1) and 1 or 0
end

function RangerProgressConfig.SetCompleted(key, value)
	local data = RangerProgressConfig.Load()
	data[key] = (value == 1) and 1 or 0
	RangerProgressConfig.Save(data)
end

-- Подгрузить конфиг при инжекте, чтобы помнить что уже пройдено
pcall(function() RangerProgressConfig.Load() end)

local function findStageLabelRecursive(obj)
	if not obj then return nil end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		local t = obj.Text or ""
		local displayMap, roman = t:match("^(.+) %- Ranger Stage (I|II|III|IV)$")
		if displayMap and roman and RANGER_DISPLAY_TO_INTERNAL[displayMap:gsub("^%s+", ""):gsub("%s+$", "")] then
			return t
		end
	end
	for _, child in ipairs(obj:GetChildren()) do
		local found = findStageLabelRecursive(child)
		if found then return found end
	end
	return nil
end

function Game.GetCurrentRangerStage()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return nil end
	local hud = gui:FindFirstChild("HUD")
	if not hud then return nil end
	local inGame = hud:FindFirstChild("InGame")
	if not inGame then return nil end
	local main = inGame:FindFirstChild("Main")
	if not main then return nil end
	local gameInfo = main:FindFirstChild("GameInfo")
	if not gameInfo then return nil end
	local gamemode = gameInfo:FindFirstChild("Gamemode")
	if not gamemode then return nil end
	local modeLabel = gamemode:FindFirstChild("Label")
	if not modeLabel or not modeLabel:IsA("TextLabel") then return nil end
	local modeText = (modeLabel.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if modeText ~= "Ranger Stage" then return nil end
	local fullText = findStageLabelRecursive(gameInfo) or findStageLabelRecursive(main) or findStageLabelRecursive(inGame)
	if not fullText then return nil end
	local displayMap, roman = fullText:match("^(.+) %- Ranger Stage (I|II|III|IV)$")
	displayMap = displayMap and displayMap:gsub("^%s+", ""):gsub("%s+$", "") or nil
	if not displayMap or not roman then return nil end
	local world = RANGER_DISPLAY_TO_INTERNAL[displayMap]
	local chapterNum = ROMAN_TO_NUM[roman]
	if not world or not chapterNum then return nil end
	return {
		inRangerMode = true,
		displayKey = fullText,
		world = world,
		chapterNum = chapterNum,
	}
end

function Game.BuildRangerDisplayKey(world, chapterNum)
	local display = RANGER_INTERNAL_TO_DISPLAY[world]
	local roman = NUM_TO_ROMAN[chapterNum]
	if not display or not roman then return nil end
	return display .. " - Ranger Stage " .. roman
end

-- Fallback: read world/chapter from ReplicatedStorage.Values.Game (when HUD is hidden, e.g. rewards screen)
function Game.GetCurrentRangerStageFromValues()
	local values = RS:FindFirstChild("Values")
	local gameFolder = values and values:FindFirstChild("Game")
	if not gameFolder then return nil end
	local gamemode = gameFolder:FindFirstChild("Gamemode")
	local worldVal = gameFolder:FindFirstChild("World")
	local levelVal = gameFolder:FindFirstChild("Level")
	if not gamemode or not worldVal or not levelVal or not gamemode:IsA("StringValue") then return nil end
	local modeText = (gamemode.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if modeText ~= "Ranger Stage" then return nil end
	local world = (worldVal.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local level = (levelVal.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local chNum = level:match("_RangerStage(%d+)$")
	chNum = chNum and tonumber(chNum)
	if not world or not chNum then return nil end
	if not table.find(RANGER_WORLDS, world) then return nil end
	local displayKey = Game.BuildRangerDisplayKey(world, chNum)
	if not displayKey then return nil end
	return { world = world, chapterNum = chNum, displayKey = displayKey }
end

local function getRangerChapterCount(world)
	return (world == "JJK") and 4 or 3
end

local function getNextRangerStage()
	local config = RangerProgressConfig.Load()
	for _, world in ipairs(RANGER_WORLDS) do
		local maxCh = getRangerChapterCount(world)
		for ch = 1, maxCh do
			local key = Game.BuildRangerDisplayKey(world, ch)
			if key and (config[key] or 0) == 0 then
				return world, ch, key
			end
		end
	end
	return nil, nil, nil
end

local function isRangerCycleComplete()
	local w, ch = getNextRangerStage()
	return w == nil
end

function Game.EnterRangerStage(world, chapterNum)
	local r = getRemote()
	r.PlayRoomEvent:FireServer("Create")
	task.wait(0.6)
	r.PlayRoomEvent:FireServer("Change-Mode", { Mode = "Ranger Stage" })
	task.wait(0.1)
	r.PlayRoomEvent:FireServer("Change-World", { World = world })
	task.wait(0.1)
	local chapterName = world .. "_RangerStage" .. tostring(chapterNum)
	r.PlayRoomEvent:FireServer("Change-Chapter", { Chapter = chapterName })
	task.wait(0.1)
	r.PlayRoomEvent:FireServer("Submit")
	task.wait(0.2)
	r.PlayRoomEvent:FireServer("Start")
end

local rangerAutofarmEnabled = false
local rangerAutofarmCurrentStage = nil
local rangerAutofarmRewardsGuard = nil
local rangerAutofarmLoop = nil

-- ============ EVO FARM AUTOFARM STATE ============
local evoAutofarmEnabled = false
local evoAutofarmRewardsGuard = nil

local function getCurrentStageForEvo()
	local values = RS:FindFirstChild("Values")
	local gameFolder = values and values:FindFirstChild("Game")
	if not gameFolder then return nil end
	local worldVal = gameFolder:FindFirstChild("World")
	local levelVal = gameFolder:FindFirstChild("Level")
	if not worldVal or not levelVal then return nil end
	local world = tostring(worldVal.Value or "")
	local level = tostring(levelVal.Value or "")
	return {
		world = world,
		levelKey = level,
	}
end

local function recalcNeedCountFromInventory()
	if not EvoFarm.GlobalNeed or not next(EvoFarm.GlobalNeed) then
		return
	end
	local pd = getPlayerDataRaw()
	if not pd then return end
	local itemsFolder = pd:FindFirstChild("Items")
	if not itemsFolder then return end

	local needCount = {}
	for matName, needTotal in pairs(EvoFarm.GlobalNeed or {}) do
		if needTotal > 0 then
			local have = 0
			local item = itemsFolder:FindFirstChild(matName)
			if item and item:FindFirstChild("Amount") and item.Amount:IsA("ValueBase") then
				have = tonumber(item.Amount.Value) or 0
			end
			local newNeed = math.max(0, (needTotal or 0) - have)
			needCount[matName] = newNeed
		end
	end
	EvoFarm.NeedCount = needCount
	updateEvoFarmStatus()
end

local function getDropsForStage(world, levelKey)
	if not EvoFarm.Levels or type(EvoFarm.Levels) ~= "table" then return {} end
	local levels = EvoFarm.Levels[world]
	if not levels then return {} end
	local levelData = levels[levelKey]
	if not levelData or type(levelData.Items) ~= "table" then return {} end
	return levelData.Items
end

local function isStageStillUsefulForEvo(world, levelKey)
	if not EvoFarm.NeedCount or not next(EvoFarm.NeedCount) then
		return false
	end
	for _, drop in ipairs(getDropsForStage(world, levelKey)) do
		if type(drop) == "table" and type(drop.Name) == "string" then
			if EvoFarm.NeedCount[drop.Name] and EvoFarm.NeedCount[drop.Name] > 0 then
				return true
			end
		end
	end
	return false
end

local function getStageKeyFromStep(step)
	if not step or not step.mode then return nil end
	return tostring(step.mode) .. "_" .. tostring(step.world) .. "_" .. tostring(step.chapter)
end

local function isEvoStageCycleComplete()
	for _, step in ipairs(EvoFarm.StageRoute or {}) do
		local key = getStageKeyFromStep(step)
		if key then
			local v = EvoFarm.StagesState[key]
			if v ~= 1 then
				return false
			end
		end
	end
	return true
end

local function resetEvoStagesState()
	for _, step in ipairs(EvoFarm.StageRoute or {}) do
		local key = getStageKeyFromStep(step)
		if key then
			EvoFarm.StagesState[key] = 0
		end
	end
	if EvoFarm.Config then
		EvoFarm.Config.stages = EvoFarm.StagesState
		saveEvoFarmConfig(EvoFarm.Config)
	end
end

local function enterEvoStage(step)
	if not step then return end
	-- Ranger Stage или Story/другие режимы через PlayRoom
	if step.mode == "Ranger Stage" and step.world and step.chapter then
		-- есть специализированная функция
		local chNum = tonumber(tostring(step.chapter):match("_RangerStage(%d+)$")) or 1
		Game.EnterRangerStage(step.world, chNum)
		return
	end

	-- универсальный вход через создание комнаты
	Game.CreateRoom()
	task.wait(0.5)
	Game.SetRoomMode(step.mode or "Story")
	if step.world then
		Game.SetRoomWorld(step.world)
	end
	if step.chapter then
		Game.SetRoomChapter(step.chapter)
	end
	task.wait(0.3)
	Game.SubmitRoom()
	task.wait(0.2)
	Game.StartGame()
end

local function connectEvoRewardsCallback(rewardsUI)
	if evoAutofarmRewardsGuard then
		evoAutofarmRewardsGuard:Disconnect()
		evoAutofarmRewardsGuard = nil
	end
	evoAutofarmRewardsGuard = rewardsUI:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not rewardsUI.Enabled or not evoAutofarmEnabled then return end
		task.defer(function()
			task.wait(0.1)
			if not evoAutofarmEnabled then return end

			local isWon = false
			local isDefeat = false
			pcall(function()
				local main = rewardsUI:FindFirstChild("Main")
				local left = main and main:FindFirstChild("LeftSide")
				local gs = left and left:FindFirstChild("GameStatus")
				local raw = (gs and gs:IsA("TextLabel")) and (gs.Text or "") or ""
				if raw:lower():find("won") or raw:find("WON") then isWon = true end
				if raw:lower():find("defeat") or raw:find("DEFEAT") or raw:lower():find("game over") then isDefeat = true end
			end)
			if isDefeat then return end

			recalcNeedCountFromInventory()

			-- периодически пересобираем маршрут с учётом актуального globalLacking
			EvoFarm.MatchCounter = (EvoFarm.MatchCounter or 0) + 1
			if EvoFarm.MatchCounter % 4 == 0 then
				if not EvoFarm.DropIndex or next(EvoFarm.DropIndex) == nil then
					EvoFarm.DropIndex = buildDropIndex()
				end
				EvoFarm.StageRoute = buildStageRoute(EvoFarm.NeedCount or {}, EvoFarm.DropIndex)
				if EvoFarm.CurrentStageIndex > #EvoFarm.StageRoute then
					EvoFarm.CurrentStageIndex = 1
				end
			end

			local step = EvoFarm.StageRoute[EvoFarm.CurrentStageIndex]
			if not step then
				evoAutofarmEnabled = false
				return
			end
			local stageKey = getStageKeyFromStep(step)

			local useful = false
			if step.world and step.chapter then
				useful = isStageStillUsefulForEvo(step.world, step.chapter)
			end

			if useful then
				-- остаёмся на карте
				Game.VoteRetry()
				return
			end

			-- помечаем стадию как завершённую в этом круге
			if stageKey then
				EvoFarm.StagesState[stageKey] = 1
				if EvoFarm.Config then
					EvoFarm.Config.stages = EvoFarm.StagesState
					saveEvoFarmConfig(EvoFarm.Config)
				end
			end

			-- если текущая цель закрыта по NeedCount, расширяем GlobalNeed ещё на один круг
			local allDone = true
			for _, need in pairs(EvoFarm.NeedCount or {}) do
				if need > 0 then
					allDone = false
					break
				end
			end
			if allDone then
				local craftsTotal = tonumber(EvoFarm.Config and EvoFarm.Config.craftsTotal) or 0
				local craftsCompleted = (tonumber(EvoFarm.Config and EvoFarm.Config.craftsCompleted) or 0) + 1
				EvoFarm.Config.craftsCompleted = craftsCompleted
				saveEvoFarmConfig(EvoFarm.Config)

				if craftsTotal > 0 and craftsCompleted >= craftsTotal then
					setEvoAutofarmEnabled(false)
					updateEvoFarmStatus()
					Fluent:Notify({
						Title = "Evo Farm",
						Content = "Complete: " .. tostring(craftsCompleted) .. "/" .. tostring(craftsTotal) .. " crafts",
						Duration = 5,
					})
					Game.LeaveRoom()
					return
				end

				-- добавляем ещё одну "копию" целей в глобальную потребность
				if EvoFarm.BaseNeed then
					if not EvoFarm.DropIndex or next(EvoFarm.DropIndex) == nil then
						EvoFarm.DropIndex = buildDropIndex()
					end
					for matName, count in pairs(EvoFarm.BaseNeed) do
						if type(count) == "number" and count > 0 and isMaterialAutoFarmable(matName, EvoFarm.DropIndex) then
							local cur = EvoFarm.GlobalNeed[matName] or 0
							EvoFarm.GlobalNeed[matName] = cur + count
						end
					end
					-- пересчитываем нехватку и маршрут уже под следующий круг крафта
					recalcNeedCountFromInventory()
					EvoFarm.StageRoute = buildStageRoute(EvoFarm.NeedCount or {}, EvoFarm.DropIndex)
					EvoFarm.CurrentStageIndex = 1
					resetEvoStagesState()
					updateEvoFarmStatus()
				end
			end

			-- если круг по стадиям завершён, сбрасываем его
			if isEvoStageCycleComplete() then
				resetEvoStagesState()
			end

			-- двигаемся к следующему шагу маршрута
			EvoFarm.CurrentStageIndex = EvoFarm.CurrentStageIndex + 1
			if EvoFarm.CurrentStageIndex > #EvoFarm.StageRoute then
				EvoFarm.CurrentStageIndex = 1
			end

			Game.LeaveRoom()
			task.spawn(function()
				task.wait(1)
				if not evoAutofarmEnabled then return end
				enterEvoStage(EvoFarm.StageRoute[EvoFarm.CurrentStageIndex])
			end)
		end)
	end)
end

local function setupEvoRewardsHook()
	if evoAutofarmRewardsGuard then
		evoAutofarmRewardsGuard:Disconnect()
		evoAutofarmRewardsGuard = nil
	end
	if not evoAutofarmEnabled then return end
	if not LocalPlayer then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local rewardsUI = gui:FindFirstChild("RewardsUI") or gui:FindFirstChild("ResultUI")
	if rewardsUI then
		connectEvoRewardsCallback(rewardsUI)
	else
		task.spawn(function()
			rewardsUI = gui:WaitForChild("RewardsUI", 15) or gui:WaitForChild("ResultUI", 5)
			if rewardsUI and evoAutofarmEnabled and not evoAutofarmRewardsGuard then
				connectEvoRewardsCallback(rewardsUI)
			end
		end)
	end
end

local function setEvoAutofarmEnabled(enabled)
	evoAutofarmEnabled = enabled == true
	if not evoAutofarmEnabled then
		if evoAutofarmRewardsGuard then
			evoAutofarmRewardsGuard:Disconnect()
			evoAutofarmRewardsGuard = nil
		end
		return
	end

	-- если маршрута ещё нет, пытаемся собрать его из конфига
	if (not EvoFarm.StageRoute) or (#EvoFarm.StageRoute == 0) then
		rebuildEvoFarmFromConfig()
	end
	if #EvoFarm.StageRoute == 0 then
		evoAutofarmEnabled = false
		return
	end

	setupEvoRewardsHook()

	-- старт с первой стадии маршрута, только из лобби
	task.spawn(function()
		while evoAutofarmEnabled and not isInLobby() do
			task.wait(2)
		end
		if not evoAutofarmEnabled then return end
		EvoFarm.CurrentStageIndex = 1
		enterEvoStage(EvoFarm.StageRoute[EvoFarm.CurrentStageIndex])
	end)
end

local function connectRangerRewardsCallback(rewardsUI)
	if rangerAutofarmRewardsGuard then
		rangerAutofarmRewardsGuard:Disconnect()
		rangerAutofarmRewardsGuard = nil
	end
	rangerAutofarmRewardsGuard = rewardsUI:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not rewardsUI.Enabled or not rangerAutofarmEnabled then return end
		task.defer(function()
			task.wait(0.05)
			if not rangerAutofarmEnabled then return end
			local isWon = false
			local isDefeat = false
			pcall(function()
				local main = rewardsUI:FindFirstChild("Main")
				local left = main and main:FindFirstChild("LeftSide")
				local gs = left and left:FindFirstChild("GameStatus")
				local raw = (gs and gs:IsA("TextLabel")) and (gs.Text or "") or ""
				if raw:lower():find("won") or raw:find("WON") then isWon = true end
				if raw:lower():find("defeat") or raw:find("DEFEAT") or raw:lower():find("game over") then isDefeat = true end
			end)
			if isDefeat then return end
			if not isWon and not rangerAutofarmCurrentStage then return end
			if not isWon then isWon = true end
			local displayKey = nil
			local world, ch = nil, nil
			local stage = Game.GetCurrentRangerStage()
			if stage and stage.displayKey then
				displayKey = stage.displayKey
				world, ch = stage.world, stage.chapterNum
			elseif rangerAutofarmCurrentStage then
				world = rangerAutofarmCurrentStage.world
				ch = rangerAutofarmCurrentStage.chapterNum
				displayKey = Game.BuildRangerDisplayKey(world, ch)
			else
				stage = Game.GetCurrentRangerStageFromValues()
				if stage and stage.displayKey then
					displayKey = stage.displayKey
					world, ch = stage.world, stage.chapterNum
				end
			end
			if displayKey and world and ch then
				RangerProgressConfig.SetCompleted(displayKey, 1)
				local maxCh = getRangerChapterCount(world)
				if ch < maxCh then
					Game.VoteNext()
					rangerAutofarmCurrentStage = { world = world, chapterNum = ch + 1 }
				else
					Game.LeaveRoom()
					rangerAutofarmCurrentStage = nil
					if isRangerCycleComplete() then
						RangerProgressConfig.Reset()
						Fluent:Notify({ Title = "Ranger Autofarm", Content = "Cycle complete. Restarting...", Duration = 4 })
					end
					task.spawn(function()
						task.wait(1)
						if not rangerAutofarmEnabled then return end
						local nextWorld, nextCh, _ = getNextRangerStage()
						if nextWorld and nextCh then
							rangerAutofarmCurrentStage = { world = nextWorld, chapterNum = nextCh }
							Game.EnterRangerStage(nextWorld, nextCh)
						end
					end)
				end
			end
		end)
	end)
end

local function setupRangerRewardsHook()
	if rangerAutofarmRewardsGuard then
		rangerAutofarmRewardsGuard:Disconnect()
		rangerAutofarmRewardsGuard = nil
	end
	if not rangerAutofarmEnabled then return end
	if not LocalPlayer then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local rewardsUI = gui:FindFirstChild("RewardsUI") or gui:FindFirstChild("ResultUI")
	if rewardsUI then
		connectRangerRewardsCallback(rewardsUI)
	else
		task.spawn(function()
			rewardsUI = gui:WaitForChild("RewardsUI", 15) or gui:WaitForChild("ResultUI", 5)
			if rewardsUI and rangerAutofarmEnabled and not rangerAutofarmRewardsGuard then
				connectRangerRewardsCallback(rewardsUI)
			end
		end)
	end
end

-- Auto Join state
local autoJoinEnabled = false
local autoJoinFilter = { mode = "Story", world = nil, chapter = nil, difficulty = nil }
local autoJoinConnection = nil

function Game.SetAutoJoin(enabled, filter)
	autoJoinEnabled = enabled == true
	if filter then
		autoJoinFilter.mode = filter.mode or autoJoinFilter.mode
		autoJoinFilter.world = filter.world
		autoJoinFilter.chapter = filter.chapter
		autoJoinFilter.difficulty = filter.difficulty
	end
	if autoJoinConnection then
		autoJoinConnection:Disconnect()
		autoJoinConnection = nil
	end
	if not autoJoinEnabled then return end
	task.spawn(function()
		while autoJoinEnabled do
			if not autoJoinEnabled then break end
			if not isInLobby() then task.wait(2) continue end
			local mode = autoJoinFilter.mode
			if mode == "Fate" then
				Game.EnterMode("Fate Mode", true)
				task.wait(5)
			else
				local list = Game.GetRoomList()
				for _, room in ipairs(list) do
					if not autoJoinEnabled then break end
					if mode and room:FindFirstChild("Mode") and room.Mode.Value ~= mode then continue end
					if autoJoinFilter.world and room:FindFirstChild("World") and room.World.Value ~= autoJoinFilter.world then continue end
					if autoJoinFilter.chapter and room:FindFirstChild("Chapter") and room.Chapter.Value ~= autoJoinFilter.chapter then continue end
					if autoJoinFilter.difficulty and room:FindFirstChild("Difficulty") and room.Difficulty.Value ~= autoJoinFilter.difficulty then continue end
					Game.JoinRoom(room)
					task.wait(5)
					break
				end
			end
			task.wait(2)
		end
	end)
end

function Game.CreateChallengeRoom()
	getRemote().PlayRoomEvent:FireServer("Create", { CreateChallengeRoom = true })
end

function Game.SubmitRoom()
	getRemote().PlayRoomEvent:FireServer("Submit")
end

-- ============ GAME API: MATCH ============
function Game.SetSetting(name, value)
	getRemote().SettingEvent:FireServer(name, value)
end

-- Auto Next + Auto Replay: одна очередь — сначала Next, потом Replay (если оба включены)
local autoNextEnabled = false
local autoRetryEnabled = false
local rewardsVoteGuard = nil

local function updateRewardsVoteConnection()
	if rewardsVoteGuard then
		rewardsVoteGuard:Disconnect()
		rewardsVoteGuard = nil
	end
	if not autoNextEnabled and not autoRetryEnabled then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local rewardsUI = gui:FindFirstChild("RewardsUI")
	if not rewardsUI then return end
	rewardsVoteGuard = rewardsUI:GetPropertyChangedSignal("Enabled"):Connect(function()
		if rewardsUI.Enabled ~= true then return end
		task.defer(function()
			task.wait(0.05)
			if autoNextEnabled then
				Game.VoteNext()
			end
			if autoRetryEnabled then
				task.wait(0.1)
				Game.VoteRetry()
			end
		end)
	end)
end

function Game.SetAutoNext(enabled)
	Game.SetSetting("Auto Next", enabled == true)
	autoNextEnabled = enabled == true
	updateRewardsVoteConnection()
end

function Game.SetAutoRetry(enabled)
	autoRetryEnabled = enabled == true
	updateRewardsVoteConnection()
end
function Game.SetAutoVoteStart(v) Game.SetSetting("Auto Vote Start", v == true) end
function Game.SetAutoSetMaxSpeed(v) Game.SetSetting("Auto Set Max Speed", v == true) end

function Game.VotePlaying()
	getRemote().VotePlaying:FireServer()
end

function Game.VoteRetry()
	getRemote().VoteRetry:FireServer()
end

function Game.VoteNext()
	getRemote().VoteNext:FireServer()
end

function Game.RestartMatch()
	getRemote().RestartMatch:FireServer()
end

function Game.ToggleAutoPlay()
	getRemote().Units.AutoPlay:FireServer()
end

local rewardsUIGuard = nil
function Game.SetAutoLeave(enabled)
	if rewardsUIGuard then rewardsUIGuard:Disconnect() end
	if not enabled then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local rewardsUI = gui:FindFirstChild("RewardsUI")
	if rewardsUI then
		rewardsUIGuard = rewardsUI:GetPropertyChangedSignal("Enabled"):Connect(function()
			if rewardsUI.Enabled == true then
				pcall(function()
					if RS:FindFirstChild("VipServerId") then
						local R = RS:FindFirstChild("Remote")
						local Client = R and R:FindFirstChild("Client")
						local TB = Client and Client:FindFirstChild("TeleportBack")
						if TB then TB:FireServer() end
					else
						TeleportService:Teleport(game.PlaceId, LocalPlayer)
					end
				end)
			end
		end)
	end
end

-- ============ GAME API: LOBBY ============
function Game.PortalStart()
	getRemote().LobbyPortal:FireServer("Start")
end

function Game.PortalLeave()
	getRemote().LobbyPortal:FireServer("Leave")
end

function Game.PortalCancel()
	getRemote().LobbyPortal:FireServer("Cancel")
end

function Game.ClaimDailyReward(day)
	getRemote().LobbyDaily:FireServer("Claim", day or 1)
end

function Game.RedeemCode(code)
	if code and #code > 0 then
		getRemote().LobbyCode:FireServer(code)
	end
end

function Game.ClaimBattlepassAll()
	getRemote().ClaimBp:FireServer("Claim All")
end

function Game.ClaimEventBattlepassAll()
	getRemote().EventClaimBp:FireServer("Claim All")
end

-- Открытие UI по дампу (см. DUMP_FINDINGS.md). Merchant открывается сервером — пробуем только .Enabled
function Game.TryOpenMerchant()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local m = gui and gui:FindFirstChild("Merchant")
	if m then m.Enabled = true return true end
	return false
end

function Game.TryOpenBattlePass()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local bp = gui and gui:FindFirstChild("BattlePass")
	if bp then bp.Enabled = true return true end
	return false
end

function Game.TryOpenEventBattlePass()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local ebp = gui and gui:FindFirstChild("EventBattlePass")
	if ebp then ebp.Enabled = true return true end
	return false
end

function Game.TryOpenRaidShop()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local s = gui and gui:FindFirstChild("Raid_Shop")
	if s then s.Enabled = true return true end
	return false
end

function Game.TryOpenJJKRaidShop()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local s = gui and gui:FindFirstChild("JJK_Raid_Shop")
	if s then s.Enabled = true return true end
	return false
end

function Game.TryOpenCalamityShop()
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local s = gui and gui:FindFirstChild("Calamity_Shop")
	if s then s.Enabled = true return true end
	return false
end

-- Открыть Traits с выбранным юнитом (unitFolder из Collection). По дампу: Traits.Enabled + UnitFolder.Value
function Game.OpenTraitsUI(unitFolder)
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return false end
	local traits = gui:FindFirstChild("Traits")
	local main = traits and traits:FindFirstChild("Main")
	local base = main and main:FindFirstChild("Base")
	if not base then return false end
	local uf = base:FindFirstChild("UnitFolder")
	if uf and unitFolder then uf.Value = unitFolder end
	traits.Enabled = true
	return true
end

-- Открыть Collection (опционально режим Mode). Для Traits с юнитом лучше OpenTraitsUI(unitFolder).
function Game.OpenCollection(mode)
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local col = gui and gui:FindFirstChild("Collection")
	if not col then return false end
	local modeVal = col:FindFirstChild("Mode")
	if modeVal and mode then modeVal.Value = mode end
	col.Enabled = true
	return true
end

-- ============ GAME API: MERCHANT / SUMMON ============
function Game.BuyMerchantItem(itemName, amount)
	getRemote().Merchant:FireServer(itemName, amount or 1)
end

function Game.BuyRaidShopItem(itemName, amount)
	getRemote().Raid_Shop:FireServer(itemName, amount or 1)
end

function Game.BuyJJKRaidShopItem(itemName, amount)
	getRemote().JJK_RaidShop:FireServer(itemName, amount or 1)
end

function Game.BuyCalamityShopItem(itemName, amount)
	getRemote().Calamity_Shop:FireServer(itemName, amount or 1)
end

function Game.SelectBanner(bannerId)
	getRemote().SelectRateUpBanner:FireServer(bannerId)
end

-- UnitsGacha:FireServer("10x"|"1x", "Standard"|bannerName, { Rare = true, Epic = true } for delete rarities)
function Game.Summon(count, bannerName, deleteRaritiesTable)
	getRemote().UnitsGacha:FireServer(count or "1x", bannerName or "Standard", deleteRaritiesTable or {})
end

function Game.SellLastUnit()
	getRemote().UnitsGacha:FireServer("Selling")
end

-- ============ GAME API: UNITS ============
function Game.GetPlayerData(plr)
	plr = plr or LocalPlayer
	if typeof(plr) == "string" then plr = Players:FindFirstChild(plr) or plr end
	if not plr or not plr:FindFirstChild("DataLoaded", true) then return nil end
	local pd = RS:FindFirstChild("Player_Data")
	if not pd then return nil end
	return pd:FindFirstChild(plr.Name)
end

function Game.GetUnitsList(plr)
	local data = Game.GetPlayerData(plr)
	if not data or not data:FindFirstChild("Collection") then return {} end
	local list = {}
	for _, child in ipairs(data.Collection:GetChildren()) do
		if child:IsA("Folder") and child:FindFirstChild("Tag") then
			table.insert(list, child)
		end
	end
	return list
end

function Game.DeployUnit(unitFolder, autoInGame)
	if not unitFolder or not unitFolder.Parent then return end
	if autoInGame then
		getRemote().Units.Deployment:FireServer(unitFolder, true)
	else
		getRemote().Units.Deployment:FireServer(unitFolder)
	end
end

function Game.EquipUnit(unitFolder)
	if unitFolder then getRemote().Units.Equip:FireServer(unitFolder) end
end

function Game.UnEquipUnit(unitFolder)
	if unitFolder then getRemote().Units.UnEquip:FireServer(unitFolder) end
end

function Game.UnEquipAllUnits()
	getRemote().Units.UnEquipAll:FireServer()
end

function Game.EquipBest()
	local list = Game.GetUnitsList()
	local arr = {}
	for _, folder in ipairs(list) do
		local tag = folder:FindFirstChild("Tag") and folder.Tag.Value
		local dmg = (folder:FindFirstChild("Damage") and folder:FindFirstChild("AttackCooldown")) and (folder.Damage.Value / math.max(0.001, folder.AttackCooldown.Value)) or 0
		if tag then
			table.insert(arr, { Serial = tag, DMG = dmg, Names = folder.Name })
		end
	end
	table.sort(arr, function(a, b) return a.DMG > b.DMG end)
	Game.UnEquipAllUnits()
	task.wait(0.2)
	getRemote().Units.EquipBest:FireServer(arr)
end

function Game.FeedUnit(unitFolder, items)
	if unitFolder and items and type(items) == "table" then
		getRemote().Units.Feed:FireServer(unitFolder, items)
	end
end

function Game.EvolveUnit(unitTag)
	if unitTag then getRemote().Units.UnitsEvolve:FireServer(unitTag) end
end

function Game.LimitBreak(unitFolder, max)
	if unitFolder then
		getRemote().Units.LimitBreaks:FireServer(unitFolder, max == true)
	end
end

function Game.EvolveTier(unitTag, tier)
	if unitTag and tier then getRemote().Units.EvolveTier:FireServer(unitTag, tier) end
end

function Game.RemoveEvolveTier(unitTag)
	if unitTag then getRemote().Units.RemoveEvolveTier:FireServer(unitTag) end
end

function Game.UpgradeCollectionSize()
	getRemote().Units.UpgradeCollectionSize:FireServer()
end

-- ============ GAME API: WEBHOOK ============
local webhookEnabled = false
local webhookUrl = ""
local webhookDiscordId = ""
local webhookRewardsGuard = nil

-- Secret units/items for ping (internal names from game data + text "Secret"/"[Secret]")
local SECRET_UNIT_NAMES = {
	-- tier_list + DampGame Units
	Ace = true, Archer = true, Ishtar = true, Enkidu = true, ["Fire Fist"] = true,
	["Knight King Alter"] = true, ["Saber Alter"] = true, Gilgamesh = true, Shirou = true, Jeanne = true, Kiritsugu = true,
	["Silver Reaper"] = true, ["Silver Reaper (OWL)"] = true, ["Crimson Owl"] = true, ["Kishou_Arima:Evo"] = true,
	Shadowborne = true, ["Blood Queen"] = true, Shadow = true, ["Shadow (Atomic)"] = true,
	["Judo Preist"] = true, Ayanokoji = true, Lullaby = true, ["Lullaby (Domination)"] = true, ["Pride (Sun)"] = true,
	["Ura (Kai)"] = true, ["Shin (Reverse)"] = true, ["The Almighty"] = true, ["Ichigoat (True)"] = true,
	["Hana (True Release)"] = true, ["Flame Captain"] = true, ["Shadow Knight"] = true, ["Shadow Commander"] = true,
	["Shadow Monarch (Evo)"] = true, Zookeeper = true, ["Virtual Swordsman (Stardust)"] = true,
	["Virtual Swordsman (King)"] = true, ["Virtual Sniper"] = true, ["Aldebo (Seduction)"] = true,
	["Demo (Hellflames)"] = true, Gappy = true, ["Gravity Priest"] = true, ["Priest of Heaven (Ascended)"] = true,
	Artist = true, Toru = true, ["The Strongest"] = true, ["The Strongest (Void)"] = true, ["Curse King"] = true,
	["Curse King (Shrine)"] = true, Yoka = true, ["Yoka (Stardust)"] = true, Frieren = true, Lucci = true,
	Koromu = true, ["Koromu (Zaphkel)"] = true, Dracula = true, ["Dracula (Restriction)"] = true,
	["Pumpkin Queen"] = true, ["Pumpkin Queen (Explosive)"] = true, ["Skeleton King"] = true,
	["Skeleton King (Skull Guitar)"] = true, Homoro = true, ["Homoro (Time Witch)"] = true,
	["War Girl"] = true, ["War Girl (Arsenal)"] = true, ["The Fear"] = true, ["The Fear (Volt Ring)"] = true,
	Jiji = true, Cloud = true, Tidus = true, Bartolomeo = true, ["Shoru (Noble)"] = true,
	["Fairy Queen"] = true, ["Celestial Mage"] = true, ["Dark Sorcerer"] = true,
	["Perfect Soldier"] = true, ["Confident Soldier"] = true, Professor = true,
	Bunny = true, ["Bunny (Full Moon)"] = true, ["Omega Dragonlord"] = true, ["Prodigy Ascendant"] = true,
	["Primal Fusion"] = true, ["Perfect Bio-Android"] = true, ["Gigi (Evil)"] = true,
	["Ice General"] = true, ["Chainsaw Devil"] = true, ["Control Devil"] = true,
	["Fingernail Saint (Fourth Form)"] = true, ["Skeleton Knight"] = true, ["Griffin (Heavenly Feather)"] = true,
	Berserker = true, ["Falcon of Darkness"] = true, ["Falcon of Darkness (Darkness Merged)"] = true,
}

function Game.SetWebhook(enabled, url)
	webhookEnabled = enabled == true
	if url then webhookUrl = url end
	if webhookRewardsGuard then
		webhookRewardsGuard:Disconnect()
		webhookRewardsGuard = nil
	end
	if not webhookEnabled then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local rewardsUI = gui:FindFirstChild("RewardsUI")
	if rewardsUI then
		webhookRewardsGuard = rewardsUI:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not rewardsUI.Enabled or not webhookEnabled or #webhookUrl < 10 then return end
			task.defer(function()
				task.wait(0.4)
				local timeStr = "—"
				local statusStr = "—"
				local modeStr = "—"
				local mapStr = "—"
				local totalGold = "—"
				local totalGems = "—"
				local rewardParts = {}
				local hasSecretDrop = false
				pcall(function()
					if not LocalPlayer then return end
					local main = rewardsUI:FindFirstChild("Main")
					if not main then return end
					local left = main:FindFirstChild("LeftSide")
					if not left then return end

					-- Mode, World, Chapter (карта)
					local modeLabel = left:FindFirstChild("Mode")
					local worldLabel = left:FindFirstChild("World")
					local chapterLabel = left:FindFirstChild("Chapter")
					if modeLabel and modeLabel:IsA("TextLabel") then
						modeStr = (modeLabel.Text or ""):gsub("^%s+", ""):gsub("%s+$", "") or "—"
					end
					if worldLabel and worldLabel:IsA("TextLabel") and chapterLabel and chapterLabel:IsA("TextLabel") then
						local w = (worldLabel.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
						local c = (chapterLabel.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
						mapStr = (#w > 0 and #c > 0) and (w .. " • " .. c) or w or c or "—"
					end

					local tt = left:FindFirstChild("TotalTime")
					if tt and tt:IsA("TextLabel") then
						local raw = tt.Text or ""
						timeStr = raw:match("(%d+:%d+:%d+)$") or raw
					end

					local gs = left:FindFirstChild("GameStatus")
					if gs and gs:IsA("TextLabel") then
						local raw = gs.Text or ""
						if raw:find("WON") then
							statusStr = "WON"
						elseif raw:find("DEFEAT") then
							statusStr = "DEFEAT"
						else
							statusStr = raw
						end
					end

					local rewards = left:FindFirstChild("Rewards")
					local list = rewards and rewards:FindFirstChild("ItemsList")
					if list then
						for _, child in ipairs(list:GetChildren()) do
							if child:IsA("UIGridLayout") or child:IsA("UICorner") then continue end
							local frame = child:FindFirstChild("Frame")
							local itemFrame = frame and frame:FindFirstChild("ItemFrame")
							local info = itemFrame and itemFrame:FindFirstChild("Info")
							if info then
								local nameLabel = info:FindFirstChild("ItemsNames")
								local amountLabel = info:FindFirstChild("DropAmonut")
								if nameLabel and amountLabel and nameLabel:IsA("TextLabel") and amountLabel:IsA("TextLabel") then
									local txt = nameLabel.Text or "?"
									local amt = amountLabel.Text or "?"
									table.insert(rewardParts, string.format("• %s × %s", txt, amt))
									if not hasSecretDrop then
										if (txt and (txt:lower():find("secret") or txt:find("%[Secret%]"))) or (child.Name and SECRET_UNIT_NAMES[child.Name]) then
											hasSecretDrop = true
										end
									end
								end
							end
						end
					end

					local pg = LocalPlayer:FindFirstChild("PlayerGui")
					local hud = pg and pg:FindFirstChild("HUD")
					local menu = hud and hud:FindFirstChild("MenuFrame")
					local leftSide = menu and menu:FindFirstChild("LeftSide")
					local lfFrame = leftSide and leftSide:FindFirstChild("Frame")
					if lfFrame then
						local goldLabel = lfFrame:FindFirstChild("Gold") and lfFrame.Gold:FindFirstChild("Numbers")
						local gemsLabel = lfFrame:FindFirstChild("Gems") and lfFrame.Gems:FindFirstChild("Numbers")
						if goldLabel and goldLabel:IsA("TextLabel") then totalGold = goldLabel.Text or totalGold end
						if gemsLabel and gemsLabel:IsA("TextLabel") then totalGems = gemsLabel.Text or totalGems end
					end
				end)

				local formattedRewards = "```\n" .. (#rewardParts > 0 and table.concat(rewardParts, "\n") or "Empty") .. "\n```"
				local playerName = LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name) or "?"

				local evoFarmText = buildEvoFarmProgressTextForWebhook(12)

				local embedColor = (statusStr == "WON") and 3066993 or 15158332
				local statusEmoji = (statusStr == "WON") and "🏆" or "💀"
				local matchInfoValue = string.format("```\n%-14s %-8s %s\n%-14s %-8s %s\n```\n**Mode:** %s\n**Map:** %s", "Player", "Result", "Time", playerName, statusStr, timeStr, modeStr, mapStr)
				local embed = {
					title = "Re:Rangers X — Match Result",
					color = embedColor,
					fields = {
						{ name = "Match Info", value = matchInfoValue, inline = false },
						{ name = "Rewards", value = formattedRewards, inline = false },
						{ name = "Economy", value = string.format("Gems: `%s`  Gold: `%s`", tostring(totalGems), tostring(totalGold)), inline = false },
					},
					footer = { text = "SkrilyaHub • " .. os.date("%d.%m.%Y %H:%M:%S") }
				}
				if evoFarmText and #evoFarmText > 0 then
					table.insert(embed.fields, { name = "Evo Farm Progress", value = "```\n" .. evoFarmText .. "\n```", inline = false })
				end
				local content = (hasSecretDrop and webhookDiscordId and #webhookDiscordId > 0) and ("<@" .. webhookDiscordId .. ">") or nil
				Game.SendWebhookMessage(content, embed)
			end)
		end)
	end
end

function Game.SendWebhookMessage(content, embed)
	if not webhookEnabled or not webhookUrl or #webhookUrl < 10 then return end
	if type(httprequest) ~= "function" then return end
	pcall(function()
		local payload = {}
		if content and #tostring(content) > 0 then
			payload.content = tostring(content)
		end
		if embed and type(embed) == "table" then
			payload.embeds = { embed }
		end
		if not payload.content and not payload.embeds then
			payload.content = "Test"
		end
		httprequest({
			Url = webhookUrl,
			Body = HttpService:JSONEncode(payload),
			Method = "POST",
			Headers = {
				["content-type"] = "application/json"
			}
		})
	end)
end

-- ============ FLUENT PLUS UI ============
local Window = Fluent:CreateWindow({
	Title = "SkrilyaHub",
	SubTitle = "Re:Rangers X",
	TabWidth = 160,
	Size = UDim2.fromOffset(580, 520),
	Acrylic = true,
	Theme = "Dark",
	MinimizeKey = Enum.KeyCode.RightShift
})
if Fluent.GUI and Fluent.GUI:IsA("ScreenGui") then
	Fluent.GUI.DisplayOrder = 99999
end

local Tabs = {
	Auto = Window:AddTab({ Title = "Auto", Icon = "play" }),
Shop = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
	Webhook = Window:AddTab({ Title = "Webhook", Icon = "mail" }),
	Misc = Window:AddTab({ Title = "Misc", Icon = "users" }),
	Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- ---- Constants ----
local MODES = { "Fate", "Story", "Ranger Stage", "Raids Stage", "Infinite Stage" }
local WORLDS = { "Namek", "Naruto", "OnePiece", "SAO", "TokyoGhoul", "Dungeon", "BattleArena", "KurumiBossEvent", "JJK", "Calamity" }
local DIFFICULTIES = { "Normal", "Hard", "Easy" }
local CHAPTERS = { "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5" }
local RAID_WORLDS = { "JJKRaid" }
local RAID_CHAPTERS = { "JJK_Raid_Chapter1", "JJK_Raid_Chapter2" }

local function getWorldOptionsForMode(mode)
	if mode == "Fate" then return { "—" } end
	if mode == "Raids Stage" then return RAID_WORLDS end
	return WORLDS
end
local function getChapterOptionsForMode(mode)
	if mode == "Fate" then return { "—" } end
	if mode == "Raids Stage" then return RAID_CHAPTERS end
	return CHAPTERS
end

local autoChallengesEnabled = false
local autoRaidEnabled = false

-- ---- Auto tab: Auto Join section ----
do
	local s = Tabs.Auto:AddSection("Auto Join", "play")
	s:AddParagraph({ Title = "Auto Join", Content = "Fate / Raid / Story — при смене Mode меняются World и Chapter." })
	local ModeDropdown = s:AddDropdown("AutoMode", { Title = "Mode", Values = MODES, Multi = false, Default = "Story" })
	ModeDropdown:OnChanged(function(v)
		autoJoinFilter.mode = v
		local worlds = getWorldOptionsForMode(v)
		local chapters = getChapterOptionsForMode(v)
		if Options.AutoWorld and Options.AutoWorld.SetValues then Options.AutoWorld:SetValues(worlds) Options.AutoWorld:SetValue(worlds[1]) end
		if Options.AutoChapter and Options.AutoChapter.SetValues then Options.AutoChapter:SetValues(chapters) Options.AutoChapter:SetValue(chapters[1]) end
	end)
	s:AddDropdown("AutoWorld", { Title = "World (Story/Raid)", Values = WORLDS, Multi = false, Default = "Namek" }):OnChanged(function(v) autoJoinFilter.world = (v ~= "—") and v or nil end)
	s:AddDropdown("AutoChapter", { Title = "Chapter (Story/Raid)", Values = CHAPTERS, Multi = false, Default = "Chapter 1" }):OnChanged(function(v) autoJoinFilter.chapter = (v ~= "—") and v or nil end)
	s:AddDropdown("AutoDiff", { Title = "Difficulty", Values = DIFFICULTIES, Multi = false, Default = "Normal" }):OnChanged(function(v) autoJoinFilter.difficulty = v end)
	s:AddToggle("AutoJoinToggle", { Title = "Enable Auto Join", Default = false }):OnChanged(function(enabled)
		autoJoinFilter.mode = Options.AutoMode.Value or "Story"
		autoJoinFilter.world = Options.AutoWorld.Value
		autoJoinFilter.chapter = Options.AutoChapter.Value
		autoJoinFilter.difficulty = Options.AutoDiff.Value or "Normal"
		if autoJoinFilter.world == "—" then autoJoinFilter.world = nil end
		if autoJoinFilter.chapter == "—" then autoJoinFilter.chapter = nil end
		Game.SetAutoJoin(enabled, autoJoinFilter)
	end)
end

-- ---- Auto tab: Auto Challenges section ----
do
	local s = Tabs.Auto:AddSection("Auto Challenges", "repeat")
	s:AddParagraph({ Title = "Auto Challenges", Content = "Create challenge room and start." })
	s:AddToggle("AutoChallengesToggle", { Title = "Auto Challenges", Default = false }):OnChanged(function(enabled)
		autoChallengesEnabled = enabled == true
		if not autoChallengesEnabled then return end
		task.spawn(function()
			while autoChallengesEnabled do
				if not isInLobby() then task.wait(2) continue end
				if Options.AutoMode.Value == "Fate" then
					Game.EnterMode("Fate Mode", true)
				else
					Game.CreateChallengeRoom()
					task.wait(0.5)
					Game.SetRoomMode(Options.AutoMode.Value or "Story")
					Game.SetRoomWorld(Options.AutoWorld.Value)
					Game.SetRoomChapter(Options.AutoChapter.Value)
					Game.SetRoomDifficulty(Options.AutoDiff.Value)
					task.wait(0.3)
					Game.SubmitRoom()
					task.wait(0.2)
					Game.StartGame()
				end
				task.wait(3)
			end
		end)
	end)
end

-- ---- Auto tab: Match Automation section ----
do
	local s = Tabs.Auto:AddSection("Match Automation", "gamepad-2")
	s:AddParagraph({ Title = "Match Automation", Content = "After-match and in-match options." })
	s:AddToggle("AutoRetry", { Title = "Auto Replay", Default = false }):OnChanged(function(v) Game.SetAutoRetry(v) end)
	s:AddToggle("AutoNext", { Title = "Auto Next", Default = false }):OnChanged(function(v) Game.SetAutoNext(v) end)
	s:AddToggle("AutoLeave", { Title = "Auto Leave", Default = false }):OnChanged(function(v) Game.SetAutoLeave(v) end)
	s:AddToggle("AutoVoteStart", { Title = "Auto Start (Vote Skip)", Default = false }):OnChanged(function(v) Game.SetAutoVoteStart(v) end)
	s:AddToggle("AutoPlay", { Title = "Auto Play", Default = false }):OnChanged(function() Game.ToggleAutoPlay() end)
	s:AddToggle("AutoSetMaxSpeed", { Title = "Auto Set Max Speed", Default = false }):OnChanged(function(v) Game.SetAutoSetMaxSpeed(v) end)
	s:AddButton({ Title = "State: Speed / 3x / AutoPlay", Description = "Show current speed, 3x gamepass, autoplay", Callback = function()
		local speed = Game.GetGameSpeed()
		local has3x = Game.HasSpeedGamepass3x()
		local autoPlay = Game.IsAutoPlayEnabled()
		local speedStr = (speed and (speed .. "x") or "?")
		local str = "Speed: " .. speedStr .. " | 3x gamepass: " .. (has3x and "yes" or "no") .. " | AutoPlay: " .. (autoPlay and "on" or "off")
		Fluent:Notify({ Title = "Match state", Content = str, Duration = 4 })
	end })
end

-- ---- Auto tab: Auto Raid section ----
do
	local s = Tabs.Auto:AddSection("Auto Raid", "swords")
	s:AddParagraph({ Title = "Auto Raid", Content = "Create raid room and start (JJKRaid)." })
	s:AddDropdown("AutoRaidWorld", { Title = "Raid World", Values = RAID_WORLDS, Multi = false, Default = "JJKRaid" })
	s:AddDropdown("AutoRaidChapter", { Title = "Raid Chapter", Values = RAID_CHAPTERS, Multi = false, Default = "JJK_Raid_Chapter1" })
	s:AddDropdown("AutoRaidDiff", { Title = "Raid Difficulty", Values = DIFFICULTIES, Multi = false, Default = "Normal" })
	s:AddToggle("AutoRaidToggle", { Title = "Enable Auto Raid", Default = false }):OnChanged(function(enabled)
		autoRaidEnabled = enabled == true
		if not autoRaidEnabled then return end
		task.spawn(function()
			while autoRaidEnabled do
				if not isInLobby() then task.wait(2) continue end
				local rw = Options.AutoRaidWorld.Value or "JJKRaid"
				local rc = Options.AutoRaidChapter.Value or "JJK_Raid_Chapter1"
				local rd = Options.AutoRaidDiff.Value or "Normal"
				Game.CreateRoom("raid")
				task.wait(0.6)
				Game.SetRoomMode("Raids Stage")
				Game.SetRoomWorld(rw)
				Game.SetRoomChapter(rc)
				Game.SetRoomDifficulty(rd)
				task.wait(0.3)
				Game.SubmitRoom()
				task.wait(0.2)
				Game.StartGame()
				task.wait(5)
			end
		end)
	end)
end

-- ---- Auto tab: Evo Farm section ----
do
	local s = Tabs.Auto:AddSection("Evo Farm", "target")
	s:AddParagraph({
		Title = "Evo & Gears Farm",
		Content = "Select evo items/gears to craft and auto-farm required materials (Ranger Stage / Challenge / Story).",
	})

	local evoItemsList = (EvoFarm.Targets and EvoFarm.Targets.EvoItems) or {}
	local gearsList = (EvoFarm.Targets and EvoFarm.Targets.Gears) or {}

	_G.EvoFarmSelectedTargets = _G.EvoFarmSelectedTargets or { EvoItems = {}, Gears = {} }

	local statusParagraph = s:AddParagraph({
		Title = "Status",
		Content = "Idle",
	})
	EvoFarm.StatusLabel = statusParagraph

	s:AddDropdown("EvoFarm_EvoItems", {
		Title = "Evo Materials (Multi)",
		Values = evoItemsList,
		Multi = true,
		Default = {},
	}):OnChanged(function(val)
		local selected = {}
		for name, isOn in next, val or {} do
			if isOn then
				selected[name] = 1
			end
		end
		_G.EvoFarmSelectedTargets.EvoItems = selected
	end)

	s:AddDropdown("EvoFarm_Gears", {
		Title = "Gears (Multi)",
		Values = gearsList,
		Multi = true,
		Default = {},
	}):OnChanged(function(val)
		local selected = {}
		for name, isOn in next, val or {} do
			if isOn then
				selected[name] = 1
			end
		end
		_G.EvoFarmSelectedTargets.Gears = selected
	end)

	if _G.EvoFarmCraftsTotal == nil then
		local cfgTotal = tonumber(EvoFarm.Config and EvoFarm.Config.craftsTotal)
		_G.EvoFarmCraftsTotal = (cfgTotal ~= nil and cfgTotal >= 0) and cfgTotal or 1
	end
	s:AddSlider("EvoFarm_CraftsTotal", {
		Title = "Crafts to farm",
		Description = "How many crafts (0 = infinite)",
		Min = 0,
		Max = 999,
		Default = _G.EvoFarmCraftsTotal,
		Rounding = 1,
	}):OnChanged(function(val)
		local intVal = math.max(0, math.floor(tonumber(val) or 1))
		_G.EvoFarmCraftsTotal = intVal
		-- принудительно вернуть в слайдер целое значение
		if Options and Options.EvoFarm_CraftsTotal and Options.EvoFarm_CraftsTotal.SetValue then
			Options.EvoFarm_CraftsTotal:SetValue(intVal)
		end
	end)

	s:AddButton({
		Title = "Build Evo Route",
		Description = "Rebuild farm route from selected targets",
		Callback = function()
			local targets = {}
			for name, wanted in pairs(_G.EvoFarmSelectedTargets.EvoItems or {}) do
				targets[name] = tonumber(wanted) or 1
			end
			for name, wanted in pairs(_G.EvoFarmSelectedTargets.Gears or {}) do
				targets[name] = tonumber(wanted) or 1
			end
			local craftsTotal = math.max(0, math.floor(tonumber(_G.EvoFarmCraftsTotal) or 1))
			EvoFarm.Config = EvoFarm.Config or { targets = {}, stages = {} }
			EvoFarm.Config.craftsTotal = craftsTotal
			EvoFarm.Config.craftsCompleted = 0
			setEvoFarmTargets(targets)
			Fluent:Notify({
				Title = "Evo Farm",
				Content = "Route rebuilt for " .. tostring(#EvoFarm.StageRoute) .. " stages. Crafts: " .. (craftsTotal == 0 and "∞" or tostring(craftsTotal)),
				Duration = 3,
			})
		end,
	})

	s:AddToggle("EvoFarmToggle", {
		Title = "Enable Evo Farm Autofarm",
		Default = false,
	}):OnChanged(function(enabled)
		setEvoAutofarmEnabled(enabled)
	end)
end

-- ---- Auto tab: Ranger Stage Autofarm section ----
local rangerAutofarmStatusLabel = nil
do
	local s = Tabs.Auto:AddSection("Ranger Stage Autofarm", "repeat")
	s:AddParagraph({ Title = "Ranger Stage Autofarm", Content = "Farm all maps. Ch1–Ch3 via Next, after Ch3 teleport to next world. Config loads on inject. Disable Auto Next/Leave — autofarm handles them." })
	rangerAutofarmStatusLabel = s:AddParagraph({ Title = "Current", Content = "Idle" })
	s:AddToggle("RangerAutofarmToggle", { Title = "Enable Ranger Autofarm", Default = false }):OnChanged(function(enabled)
		rangerAutofarmEnabled = enabled == true
		setupRangerRewardsHook()
		if not rangerAutofarmEnabled then
			rangerAutofarmCurrentStage = nil
			if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
				rangerAutofarmStatusLabel:SetDesc("Idle")
			end
			return
		end
		rangerAutofarmLoop = task.spawn(function()
			while rangerAutofarmEnabled do
				if not isInLobby() then
					task.wait(2)
					continue
				end
				local world, ch, displayKey = getNextRangerStage()
				if not world then
					if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
						rangerAutofarmStatusLabel:SetDesc("Cycle complete, waiting...")
					end
					task.wait(3)
					continue
				end
				if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
					rangerAutofarmStatusLabel:SetDesc(displayKey or (world .. " Ch." .. tostring(ch)))
				end
				rangerAutofarmCurrentStage = { world = world, chapterNum = ch }
				Game.EnterRangerStage(world, ch)
				task.wait(5)
			end
		end)
	end)
	s:AddButton({ Title = "Reset Routes", Description = "Clear progress config and start fresh", Callback = function()
		RangerProgressConfig.Reset()
		rangerAutofarmCurrentStage = nil
		if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
			rangerAutofarmStatusLabel:SetDesc("Config reset")
		end
		Fluent:Notify({ Title = "Ranger Autofarm", Content = "Progress config cleared", Duration = 2 })
	end })
	s:AddButton({ Title = "Simulate End of Cycle (Test)", Description = "Mark all stages complete — next win will trigger restart", Callback = function()
		local data = {}
		for _, world in ipairs(RANGER_WORLDS) do
			local maxCh = getRangerChapterCount(world)
			for ch = 1, maxCh do
				local key = Game.BuildRangerDisplayKey(world, ch)
				if key then data[key] = 1 end
			end
		end
		RangerProgressConfig.Save(data)
		rangerAutofarmCurrentStage = nil
		if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
			rangerAutofarmStatusLabel:SetDesc("Simulated end of cycle")
		end
		Fluent:Notify({ Title = "Ranger Autofarm", Content = "All stages marked complete. Win current stage to test restart.", Duration = 4 })
	end })
end

-- ---- Shop tab ----
local RARITIES = { "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local BANNERS = { "Standard", "Rateup" }
-- Постоянный список айтемов магазина (не сбрасывается)
local MERCHANT_ITEMS = { "Cursed Finger", "Dr. Megga Punk", "Green Bean", "Onigiri", "Perfect Stats Key", "Ramen", "Ranger Crystal", "Rubber Fruit", "Soul Fragments", "Stat Boosters", "Stats Key", "Trait Reroll" }
local merchantItems = table.clone(MERCHANT_ITEMS)
_G.MerchantSelectedItems = {}
_G.DeleteRarities = {}

do
	local s = Tabs.Shop:AddSection("Auto Merchant", "shopping-cart")
	s:AddParagraph({ Title = "Auto Merchant", Content = "Refresh items, select items, enable to buy max." })
	local function rebuildMerchantSelectedFromOptions()
		local arr = {}
		local opt = Options.MerchantItems
		local val = opt and opt.Value or nil
		for k, v in next, val or {} do
			if v then
				table.insert(arr, k)
			end
		end
		_G.MerchantSelectedItems = arr
	end

	s:AddDropdown("MerchantItems", { Title = "Select Items", Description = "Items to buy", Values = merchantItems, Multi = true, Default = {} }):OnChanged(function(_)
		rebuildMerchantSelectedFromOptions()
	end)
	s:AddButton({ Title = "Refresh Items", Description = "Merge current shop items into list", Callback = function()
		local seen = {}
		for _, n in ipairs(merchantItems) do seen[n] = true end
		local pd = Game.GetPlayerData()
		if pd and pd:FindFirstChild("Merchant") then
			for _, child in ipairs(pd.Merchant:GetChildren()) do
				if not seen[child.Name] then
					seen[child.Name] = true
					table.insert(merchantItems, child.Name)
				end
			end
		end
		if Options.MerchantItems and Options.MerchantItems.SetValues then
			-- сохраняем текущий выбор (из конфига) и перекидываем его на новый список айтемов
			local prevSelected = {}
			for _, name in ipairs(_G.MerchantSelectedItems or {}) do
				prevSelected[name] = true
			end
			Options.MerchantItems:SetValues(merchantItems)
			Options.MerchantItems:SetValue(prevSelected)
			rebuildMerchantSelectedFromOptions()
		end
		Fluent:Notify({ Title = "Merchant", Content = (#merchantItems > 0 and ("Loaded " .. #merchantItems .. " items") or "No merchant data"), Duration = 2 })
	end })
	s:AddToggle("AutoMerchantToggle", { Title = "Enable Auto Merchant", Default = false }):OnChanged(function(enabled)
		_G.AutoMerchantEnabled = enabled
		if not enabled then return end
		task.spawn(function()
			while _G.AutoMerchantEnabled do
				local pd = Game.GetPlayerData()
				if pd and pd:FindFirstChild("Merchant") then
					for _, itemName in ipairs(_G.MerchantSelectedItems or {}) do
						local item = pd.Merchant:FindFirstChild(itemName)
						if item and item:FindFirstChild("Quantity") then
							local q = item.Quantity.Value - (item:FindFirstChild("BuyAmount") and item.BuyAmount.Value or 0)
							if q > 0 then Game.BuyMerchantItem(itemName, q) end
						end
					end
				end
				task.wait(1)
			end
		end)
	end)
end

-- Auto Raid Shop, JJK Raid Shop, Calamity Shop (фиксированные списки, меняются только лимиты)
local RAID_SHOP_ITEMS = { "Cursed Finger", "Corpse Rib Cage", "Gyro's Steel Ball", "Dr. Megga Punk", "Stats Key", "Soul Fragments", "Gourmet Meal", "Trait Reroll", "Perfect Stats Key" }
local JJK_RAID_SHOP_ITEMS = { "Soul Fragments", "Perfect Stats Key", "Cursed Finger", "Gorodo", "King's Shrine", "Trait Reroll", "Dr. Megga Punk", "Stats Key" }
local CALAMITY_SHOP_ITEMS = { "Strongest Seal", "Cursed Finger", "Stats Key", "Perfect Stats Key", "Cursed Ring", "Soul Fragments", "Trait Reroll", "Dr. Megga Punk" }
_G.RaidShopSelectedItems = {}
_G.JJKRaidShopSelectedItems = {}
_G.CalamityShopSelectedItems = {}

local function buildShopSection(shopKey, shopFolderName, itemsList, selectedKey, buyFunc, title, desc)
	local s = Tabs.Shop:AddSection(title, "shopping-bag")
	s:AddParagraph({ Title = title, Content = desc })
	local function rebuildSelected(opt)
		local arr = {}
		local val = opt and opt.Value or nil
		for k, v in next, val or {} do
			if v then table.insert(arr, k) end
		end
		_G[selectedKey] = arr
	end

	local optName = shopKey .. "Items"
	local dropdown = s:AddDropdown(optName, { Title = "Select Items", Values = itemsList, Multi = true, Default = {} })
	dropdown:OnChanged(function() rebuildSelected(Options[optName]) end)

	local toggleName = "Auto" .. shopKey .. "Toggle"
	s:AddToggle(toggleName, { Title = "Enable Auto " .. title, Default = false }):OnChanged(function(enabled)
		_G[toggleName] = enabled
		if not enabled then return end
		task.spawn(function()
			while _G[toggleName] do
				local pd = Game.GetPlayerData()
				local shop = pd and pd:FindFirstChild(shopFolderName)
				if shop then
					for _, itemName in ipairs(_G[selectedKey] or {}) do
						local item = shop:FindFirstChild(itemName)
						if item and item:FindFirstChild("Quantity") then
							local qMax = item.Quantity.Value
							local qMaxNum = tonumber(qMax)
							if not qMaxNum then qMaxNum = 999 end
							local bought = item:FindFirstChild("BuyAmount") and (tonumber(item.BuyAmount.Value) or 0) or 0
							local q = math.max(0, qMaxNum - bought)
							if q > 0 then buyFunc(itemName, q) end
						end
					end
				end
				task.wait(1)
			end
		end)
	end)
end

buildShopSection("RaidShop", "Raid_Shop", RAID_SHOP_ITEMS, "RaidShopSelectedItems", Game.BuyRaidShopItem, "Auto Raid Shop", "Raid Currency. Select items, enable to buy max.")
buildShopSection("JJKRaidShop", "JJK_Raid_Shop", JJK_RAID_SHOP_ITEMS, "JJKRaidShopSelectedItems", Game.BuyJJKRaidShopItem, "Auto JJK Raid Shop", "Cursed Scrolls. Select items, enable to buy max.")
buildShopSection("CalamityShop", "Calamity_Shop", CALAMITY_SHOP_ITEMS, "CalamityShopSelectedItems", Game.BuyCalamityShopItem, "Auto Calamity Shop", "Cursed Essence. Select items, enable to buy max.")

do
	local s = Tabs.Shop:AddSection("Auto Summon", "sparkles")
	s:AddParagraph({ Title = "Auto Summon", Content = "Select banner, rarities to delete, enable for 10x loop." })
	s:AddButton({ Title = "Refresh Banners", Description = "Load banners", Callback = function()
		Fluent:Notify({ Title = "Banners", Content = "Banners refreshed", Duration = 2 })
	end })
	s:AddDropdown("BannerSelect", { Title = "Banner", Values = BANNERS, Multi = false, Default = "Standard" }):OnChanged(function(v) _G.SelectedBanner = v end)
	s:AddDropdown("DeleteRarities", { Title = "Delete Rarities", Description = "Auto-sell these rarities after pull", Values = RARITIES, Multi = true, Default = {} }):OnChanged(function(val)
		local arr = {}
		for k, v in next, val or {} do if v then table.insert(arr, k) end end
		_G.DeleteRarities = arr
	end)
	s:AddToggle("AutoSummonToggle", { Title = "Enable Auto Summon", Default = false }):OnChanged(function(enabled)
		_G.AutoSummonEnabled = enabled
		if not enabled then return end
		task.spawn(function()
			while _G.AutoSummonEnabled do
				local deleteTbl = {}
				for _, r in ipairs(_G.DeleteRarities or {}) do deleteTbl[r] = true end
				Game.Summon("10x", _G.SelectedBanner or "Standard", deleteTbl)
				task.wait(1.5)
			end
		end)
	end)
end

-- ---- Webhook tab ----
do
	local s = Tabs.Webhook:AddSection("Discord Webhook", "mail")
	s:AddParagraph({ Title = "Discord Webhook", Content = "When enabled, sends match result and rewards on RewardsUI.Enabled. Discord ID pings you when a Secret drop is detected." })
	s:AddToggle("WebhookEnable", { Title = "Enable Webhook", Default = false }):OnChanged(function(v) Game.SetWebhook(v, webhookUrl) end)
	s:AddInput("WebhookURL", { Title = "Webhook URL", Default = "https://discord.com/api/webhooks/...", Placeholder = "Discord webhook URL", Callback = function(v) webhookUrl = v Game.SetWebhook(webhookEnabled, v) end })
	s:AddInput("WebhookDiscordID", { Title = "Discord ID (optional)", Default = "", Placeholder = "123456789 — ping on Secret drop", Callback = function(v) webhookDiscordId = (v and tostring(v):gsub("%s+", "")) or "" end })
	s:AddButton({ Title = "Send Test Message", Description = "Send a test message", Callback = function()
		Game.SendWebhookMessage("SkrilyaHub - Test message")
		Fluent:Notify({ Title = "Webhook", Content = "Test sent", Duration = 2 })
	end })
end

-- ---- Misc: коды и BP ----
local VALID_CODES = { "SorryAboutEvo", "OOPSRAMEN", "SORRYFORBUGS!", "SORRYFORDELAYS", "GHOULHUNT", "RERELEASE!!!" }

-- ---- Misc tab ----
local VALID_CODES = {}
do
	local s = Tabs.Misc:AddSection("Codes & Battlepass", "gift")
	s:AddParagraph({ Title = "Codes & Battlepass", Content = "Redeem codes (from remote list), claim BP and Event BP." })
	s:AddButton({ Title = "Redeem All Codes", Description = "Redeem all active codes from remote list", Callback = function()
		local ok, body = pcall(function()
			return game:HttpGet("https://raw.githubusercontent.com/HOSTI1315/SkrilyaHub/refs/heads/main/Code.txt")
		end)
		local codes = {}
		if ok and type(body) == "string" and #body > 0 then
			for code in body:gmatch("%S+") do
				table.insert(codes, code)
			end
		end
		if #codes == 0 then
			Fluent:Notify({ Title = "Codes", Content = "No active codes.", Duration = 2 })
			return
		end
		for _, code in ipairs(codes) do
			Game.RedeemCode(code)
			task.wait(0.8)
		end
		Fluent:Notify({ Title = "Codes", Content = "Redeemed " .. #codes .. " codes", Duration = 2 })
	end })
	s:AddButton({ Title = "Claim Battlepass All", Description = "Claim all BP rewards", Callback = function() Game.ClaimBattlepassAll() end })
	s:AddButton({ Title = "Claim Event BP All", Description = "Claim all Event BP rewards", Callback = function() Game.ClaimEventBattlepassAll() end })
end

-- ---- SaveManager & InterfaceManager (Settings tab) ----
SaveManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetFolder("SkrilyaHub_Config")
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("SkrilyaHub")
SaveManager:BuildConfigSection(Tabs.Settings)
InterfaceManager:BuildInterfaceSection(Tabs.Settings)

local function applyConfigState()
	task.defer(function()
		local opts = Fluent.Options
		if not opts then return end
		local mode = (opts.AutoMode and opts.AutoMode.Value) or "Story"
		local worlds = getWorldOptionsForMode(mode)
		local chapters = getChapterOptionsForMode(mode)
		if opts.AutoWorld and opts.AutoWorld.SetValues then opts.AutoWorld:SetValues(worlds) opts.AutoWorld:SetValue(opts.AutoWorld.Value or worlds[1]) end
		if opts.AutoChapter and opts.AutoChapter.SetValues then opts.AutoChapter:SetValues(chapters) opts.AutoChapter:SetValue(opts.AutoChapter.Value or chapters[1]) end
		if opts.AutoJoinToggle and opts.AutoJoinToggle.Value then
			autoJoinFilter.mode = mode
			autoJoinFilter.world = opts.AutoWorld and opts.AutoWorld.Value
			autoJoinFilter.chapter = opts.AutoChapter and opts.AutoChapter.Value
			autoJoinFilter.difficulty = (opts.AutoDiff and opts.AutoDiff.Value) or "Normal"
			if autoJoinFilter.world == "—" then autoJoinFilter.world = nil end
			if autoJoinFilter.chapter == "—" then autoJoinFilter.chapter = nil end
			Game.SetAutoJoin(true, autoJoinFilter)
		end
		if opts.AutoChallengesToggle and opts.AutoChallengesToggle.Value then
			autoChallengesEnabled = true
			task.spawn(function()
				while autoChallengesEnabled do
					if not isInLobby() then task.wait(2) continue end
					if (opts.AutoMode and opts.AutoMode.Value) == "Fate" then Game.EnterMode("Fate Mode", true)
					else
						Game.CreateChallengeRoom()
						task.wait(0.5)
						Game.SetRoomMode(opts.AutoMode and opts.AutoMode.Value or "Story")
						Game.SetRoomWorld(opts.AutoWorld and opts.AutoWorld.Value)
						Game.SetRoomChapter(opts.AutoChapter and opts.AutoChapter.Value)
						Game.SetRoomDifficulty(opts.AutoDiff and opts.AutoDiff.Value)
						task.wait(0.3)
						Game.SubmitRoom()
						task.wait(0.2)
						Game.StartGame()
					end
					task.wait(3)
				end
			end)
		end
		if opts.AutoRaidToggle and opts.AutoRaidToggle.Value then
			autoRaidEnabled = true
			task.spawn(function()
				while autoRaidEnabled do
					if not isInLobby() then task.wait(2) continue end
					local rw = (opts.AutoRaidWorld and opts.AutoRaidWorld.Value) or "JJKRaid"
					local rc = (opts.AutoRaidChapter and opts.AutoRaidChapter.Value) or "JJK_Raid_Chapter1"
					local rd = (opts.AutoRaidDiff and opts.AutoRaidDiff.Value) or "Normal"
					Game.CreateRoom("raid")
					task.wait(0.6)
					Game.SetRoomMode("Raids Stage")
					Game.SetRoomWorld(rw)
					Game.SetRoomChapter(rc)
					Game.SetRoomDifficulty(rd)
					task.wait(0.3)
					Game.SubmitRoom()
					task.wait(0.2)
					Game.StartGame()
					task.wait(5)
				end
			end)
		end
		if opts.AutoRetry and opts.AutoRetry.Value then Game.SetAutoRetry(true) end
		if opts.AutoNext and opts.AutoNext.Value then Game.SetAutoNext(true) end
		if opts.AutoLeave and opts.AutoLeave.Value then Game.SetAutoLeave(true) end
		if opts.AutoVoteStart and opts.AutoVoteStart.Value then Game.SetAutoVoteStart(true) end
		if opts.AutoSetMaxSpeed and opts.AutoSetMaxSpeed.Value then Game.SetAutoSetMaxSpeed(true) end
		if opts.AutoMerchantToggle and opts.AutoMerchantToggle.Value then
			_G.AutoMerchantEnabled = true
			_G.MerchantSelectedItems = {}
			if Options.MerchantItems and Options.MerchantItems.Value then
				for k, v in next, Options.MerchantItems.Value do
					if v then table.insert(_G.MerchantSelectedItems, k) end
				end
			end
			task.spawn(function()
				while _G.AutoMerchantEnabled do
					local pd = Game.GetPlayerData()
					if pd and pd:FindFirstChild("Merchant") then
						for _, itemName in ipairs(_G.MerchantSelectedItems or {}) do
							local item = pd.Merchant:FindFirstChild(itemName)
							if item and item:FindFirstChild("Quantity") then
								local q = item.Quantity.Value - (item:FindFirstChild("BuyAmount") and item.BuyAmount.Value or 0)
								if q > 0 then Game.BuyMerchantItem(itemName, q) end
							end
						end
					end
					task.wait(1)
				end
			end)
		end
		if opts.AutoRaidShopToggle and opts.AutoRaidShopToggle.Value then
			_G.AutoRaidShopToggle = true
			_G.RaidShopSelectedItems = {}
			if opts.RaidShopItems and opts.RaidShopItems.Value then
				for k, v in next, opts.RaidShopItems.Value do if v then table.insert(_G.RaidShopSelectedItems, k) end end
			end
			task.spawn(function()
				while _G.AutoRaidShopToggle do
					local pd = Game.GetPlayerData()
					if pd and pd:FindFirstChild("Raid_Shop") then
						for _, itemName in ipairs(_G.RaidShopSelectedItems or {}) do
							local item = pd.Raid_Shop:FindFirstChild(itemName)
							if item and item:FindFirstChild("Quantity") then
								local qMaxNum = tonumber(item.Quantity.Value) or 999
								local bought = (item:FindFirstChild("BuyAmount") and tonumber(item.BuyAmount.Value)) or 0
								local q = math.max(0, qMaxNum - bought)
								if q > 0 then Game.BuyRaidShopItem(itemName, q) end
							end
						end
					end
					task.wait(1)
				end
			end)
		end
		if opts.AutoJJKRaidShopToggle and opts.AutoJJKRaidShopToggle.Value then
			_G.AutoJJKRaidShopToggle = true
			_G.JJKRaidShopSelectedItems = {}
			if opts.JJKRaidShopItems and opts.JJKRaidShopItems.Value then
				for k, v in next, opts.JJKRaidShopItems.Value do if v then table.insert(_G.JJKRaidShopSelectedItems, k) end end
			end
			task.spawn(function()
				while _G.AutoJJKRaidShopToggle do
					local pd = Game.GetPlayerData()
					if pd and pd:FindFirstChild("JJK_Raid_Shop") then
						for _, itemName in ipairs(_G.JJKRaidShopSelectedItems or {}) do
							local item = pd.JJK_Raid_Shop:FindFirstChild(itemName)
							if item and item:FindFirstChild("Quantity") then
								local qMaxNum = tonumber(item.Quantity.Value) or 999
								local bought = (item:FindFirstChild("BuyAmount") and tonumber(item.BuyAmount.Value)) or 0
								local q = math.max(0, qMaxNum - bought)
								if q > 0 then Game.BuyJJKRaidShopItem(itemName, q) end
							end
						end
					end
					task.wait(1)
				end
			end)
		end
		if opts.AutoCalamityShopToggle and opts.AutoCalamityShopToggle.Value then
			_G.AutoCalamityShopToggle = true
			_G.CalamityShopSelectedItems = {}
			if opts.CalamityShopItems and opts.CalamityShopItems.Value then
				for k, v in next, opts.CalamityShopItems.Value do if v then table.insert(_G.CalamityShopSelectedItems, k) end end
			end
			task.spawn(function()
				while _G.AutoCalamityShopToggle do
					local pd = Game.GetPlayerData()
					if pd and pd:FindFirstChild("Calamity_Shop") then
						for _, itemName in ipairs(_G.CalamityShopSelectedItems or {}) do
							local item = pd.Calamity_Shop:FindFirstChild(itemName)
							if item and item:FindFirstChild("Quantity") then
								local qMaxNum = tonumber(item.Quantity.Value) or 999
								local bought = (item:FindFirstChild("BuyAmount") and tonumber(item.BuyAmount.Value)) or 0
								local q = math.max(0, qMaxNum - bought)
								if q > 0 then Game.BuyCalamityShopItem(itemName, q) end
							end
						end
					end
					task.wait(1)
				end
			end)
		end
		if opts.AutoSummonToggle and opts.AutoSummonToggle.Value then
			_G.AutoSummonEnabled = true
			_G.SelectedBanner = (opts.BannerSelect and opts.BannerSelect.Value) or "Standard"
			_G.DeleteRarities = {}
			if opts.DeleteRarities and opts.DeleteRarities.Value then
				for k, v in next, opts.DeleteRarities.Value do if v then table.insert(_G.DeleteRarities, k) end end
			end
			task.spawn(function()
				while _G.AutoSummonEnabled do
					local deleteTbl = {}
					for _, r in ipairs(_G.DeleteRarities or {}) do deleteTbl[r] = true end
					Game.Summon("10x", _G.SelectedBanner or "Standard", deleteTbl)
					task.wait(1.5)
				end
			end)
		end
		if opts.WebhookEnable and opts.WebhookEnable.Value then
			local whUrl = (opts.WebhookURL and opts.WebhookURL.Value) or webhookUrl
			if whUrl and #whUrl > 10 then webhookEnabled = true webhookUrl = whUrl Game.SetWebhook(true, whUrl) end
		end
		if opts.WebhookDiscordID and opts.WebhookDiscordID.Value then
			webhookDiscordId = (tostring(opts.WebhookDiscordID.Value or ""):gsub("%s+", "")) or ""
		end
		if opts.AutoTraitReroll and opts.AutoTraitReroll.Value then
			_G.AutoTraitRerollEnabled = true
			autoTraitRerollConnection = RunService.Heartbeat:Connect(function() task.wait(1.2) runAutoTraitReroll() end)
		end
		if opts.RangerAutofarmToggle and opts.RangerAutofarmToggle.Value then
			rangerAutofarmEnabled = true
			setupRangerRewardsHook()
			task.spawn(function()
				while rangerAutofarmEnabled do
					if not isInLobby() then task.wait(2) continue end
					local world, ch, displayKey = getNextRangerStage()
					if not world then task.wait(3) continue end
					if rangerAutofarmStatusLabel and rangerAutofarmStatusLabel.SetDesc then
						rangerAutofarmStatusLabel:SetDesc(displayKey or (world .. " Ch." .. tostring(ch)))
					end
					rangerAutofarmCurrentStage = { world = world, chapterNum = ch }
					Game.EnterRangerStage(world, ch)
					task.wait(5)
				end
			end)
		end
	end)
end

SaveManager:LoadAutoloadConfig()
task.spawn(function()
	task.wait(1.5)
	applyConfigState()
end)

Fluent:Notify({ Title = "SkrilyaHub", Content = "Loaded. Auto / Shop / Webhook / Misc / Settings.", Duration = 4 })

-- Автоперезапуск при телепорте (как Infinite Yield): в новом лобби скрипт подгрузится сам
local teleportQueued = false
if LocalPlayer and LocalPlayer.OnTeleport then
	LocalPlayer.OnTeleport:Connect(function(_state)
		if teleportQueued then return end
		if type(queueteleport) ~= "function" or not SCRIPT_RELOAD_URL or #SCRIPT_RELOAD_URL < 10 then return end
		teleportQueued = true
		queueteleport("loadstring(game:HttpGet('" .. SCRIPT_RELOAD_URL:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'))()")
	end)
end

-- Export for UI
_G.SkrilyaHub = Game
