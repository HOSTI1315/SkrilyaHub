print("v3FankBich")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- executor HTTP helper (syn.request / http.request / request ...)
local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local LocalPlayer = Players.LocalPlayer

-- Ждём загрузки игры (как Infinite Yield)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Автоперезапуск при телепорте в другое лобби: подставь сырую ссылку на этот скрипт (raw GitHub/Pastebin и т.д.)
local SCRIPT_RELOAD_URL = "https://raw.githubusercontent.com/HOSTI1315/SkrilyaHub/refs/heads/main/Re%3ARangers%20X.lua"
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
						Fluent:Notify({ Title = "Ranger Autofarm", Content = "Cycle complete. Config reset.", Duration = 4 })
					else
						task.spawn(function()
							local waitCount = 0
							while not isInLobby() and waitCount < 30 do
								task.wait(0.2)
								waitCount = waitCount + 1
							end
							if not rangerAutofarmEnabled then return end
							local nextWorld, nextCh, _ = getNextRangerStage()
							if nextWorld and nextCh then
								rangerAutofarmCurrentStage = { world = nextWorld, chapterNum = nextCh }
								Game.EnterRangerStage(nextWorld, nextCh)
							end
						end)
					end
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
			elseif mode == "Dungeon" then
				Game.EnterDungeon({ Difficulty = autoJoinFilter.difficulty or "Normal" })
				task.wait(0.6)
				Game.StartGame()
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
local webhookRewardsGuard = nil

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
				local totalGold = "—"
				local totalGems = "—"
				local rewardParts = {}
				pcall(function()
					-- RewardsUI.Main.LeftSide.*
					local main = rewardsUI:FindFirstChild("Main")
					if not main then return end
					local left = main:FindFirstChild("LeftSide")
					if not left then return end

					-- Время: TotalTime.Text = "Total Time: 00:00:22"
					local tt = left:FindFirstChild("TotalTime")
					if tt and tt:IsA("TextLabel") then
						local raw = tt.Text or ""
						timeStr = raw:match("(%d+:%d+:%d+)$") or raw
					end

					-- Статус: GameStatus.Text ~= "~ WON" / "~ DEFEAT"
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

					-- Награды: Rewards.ItemsList.*
					local rewards = left:FindFirstChild("Rewards")
					local list = rewards and rewards:FindFirstChild("ItemsList")
					if not list then return end

					for _, child in ipairs(list:GetChildren()) do
						-- пропускаем layout / corner
						if child:IsA("UIGridLayout") or child:IsA("UICorner") then
							continue
						end

						local frame = child:FindFirstChild("Frame")
						local itemFrame = frame and frame:FindFirstChild("ItemFrame")
						local info = itemFrame and itemFrame:FindFirstChild("Info")
						if info then
							local nameLabel = info:FindFirstChild("ItemsNames")
							local amountLabel = info:FindFirstChild("DropAmonut")
							if nameLabel and amountLabel and nameLabel:IsA("TextLabel") and amountLabel:IsA("TextLabel") then
								local name = nameLabel.Text or "?"
								local amt = amountLabel.Text or ""
								table.insert(rewardParts, string.format("%s x%s", name, amt))
							end
						end
					end

					-- Текущие балансы (HUD.MenuFrame.LeftSide.Frame.*.Numbers)
					local pg = LocalPlayer:FindFirstChild("PlayerGui")
					local hud = pg and pg:FindFirstChild("HUD")
					local menu = hud and hud:FindFirstChild("MenuFrame")
					local leftSide = menu and menu:FindFirstChild("LeftSide")
					local lfFrame = leftSide and leftSide:FindFirstChild("Frame")
					if lfFrame then
						local goldFrame = lfFrame:FindFirstChild("Gold")
						local gemsFrame = lfFrame:FindFirstChild("Gems")
						local goldLabel = goldFrame and goldFrame:FindFirstChild("Numbers")
						local gemsLabel = gemsFrame and gemsFrame:FindFirstChild("Numbers")
						if goldLabel and goldLabel:IsA("TextLabel") then
							totalGold = goldLabel.Text or totalGold
						end
						if gemsLabel and gemsLabel:IsA("TextLabel") then
							totalGems = gemsLabel.Text or totalGems
						end
					end
				end)

				local rewardsBlock
				if #rewardParts > 0 then
					rewardsBlock = table.concat(rewardParts, "\n")
				else
					rewardsBlock = "—"
				end

				-- Формируем человекочитаемый отчёт как на референсе
				local lines = {}
				table.insert(lines, "Re:Rangers X — Match Result")
				table.insert(lines, "")
				table.insert(lines, "Player: " .. (LocalPlayer.DisplayName or LocalPlayer.Name))
				table.insert(lines, "Result: " .. statusStr)
				table.insert(lines, "Duration: " .. timeStr)
				table.insert(lines, "")
				table.insert(lines, "Rewards:")
				table.insert(lines, rewardsBlock)
				table.insert(lines, "")
				table.insert(lines, "Currencies:")
				table.insert(lines, "Gold: " .. tostring(totalGold))
				table.insert(lines, "Gems: " .. tostring(totalGems))
				table.insert(lines, "")
				table.insert(lines, "SkrilyaHub • " .. os.date("%Y-%m-%d %H:%M:%S"))

				local content = table.concat(lines, "\n")
				Game.SendWebhookMessage(content)
			end)
		end)
	end
end

function Game.SendWebhookMessage(content)
	if not webhookEnabled or not webhookUrl or #webhookUrl < 10 then return end
	if type(httprequest) ~= "function" then return end
	pcall(function()
		httprequest({
			Url = webhookUrl,
			Body = HttpService:JSONEncode({ content = content or "Test" }),
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
	Fluent.GUI.DisplayOrder = 5
end

local Tabs = {
	Auto = Window:AddTab({ Title = "Auto", Icon = "play" }),
	Traits = Window:AddTab({ Title = "INF Traits", Icon = "monitor" }),
	Shop = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
	Webhook = Window:AddTab({ Title = "Webhook", Icon = "mail" }),
	Misc = Window:AddTab({ Title = "Misc", Icon = "users" }),
	Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- ---- Constants ----
local MODES = { "Fate", "Story", "Ranger Stage", "Raids Stage", "Dungeon", "Infinite Stage" }
local WORLDS = { "Namek", "Naruto", "OnePiece", "SAO", "TokyoGhoul", "Dungeon", "BattleArena", "KurumiBossEvent", "JJK", "Calamity" }
local DIFFICULTIES = { "Normal", "Hard", "Easy" }
local CHAPTERS = { "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5" }
local RAID_WORLDS = { "JJKRaid" }
local RAID_CHAPTERS = { "JJK_Raid_Chapter1", "JJK_Raid_Chapter2" }

local function getWorldOptionsForMode(mode)
	if mode == "Fate" or mode == "Dungeon" then return { "—" } end
	if mode == "Raids Stage" then return RAID_WORLDS end
	return WORLDS
end
local function getChapterOptionsForMode(mode)
	if mode == "Fate" or mode == "Dungeon" then return { "—" } end
	if mode == "Raids Stage" then return RAID_CHAPTERS end
	return CHAPTERS
end

local autoChallengesEnabled = false
local autoRaidEnabled = false

-- ---- Auto tab: Auto Join section ----
do
	local s = Tabs.Auto:AddSection("Auto Join", "play")
	s:AddParagraph({ Title = "Auto Join", Content = "Fate / Raid / Dungeon / Story — при смене Mode меняются World и Chapter." })
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
	s:AddButton({ Title = "Vote Retry", Description = "Vote retry", Callback = function() Game.VoteRetry() end })
	s:AddButton({ Title = "Vote Next", Description = "Vote next", Callback = function() Game.VoteNext() end })
	s:AddButton({ Title = "Restart Match", Description = "Restart current match", Callback = function() Game.RestartMatch() end })
	s:AddButton({ Title = "State: Speed / 3x / AutoPlay", Description = "Show current speed, 3x gamepass, autoplay", Callback = function()
		local speed = Game.GetGameSpeed()
		local has3x = Game.HasSpeedGamepass3x()
		local autoPlay = Game.IsAutoPlayEnabled()
		local speedStr = (speed and (speed .. "x") or "?")
		local str = "Speed: " .. speedStr .. " | 3x gamepass: " .. (has3x and "yes" or "no") .. " | AutoPlay: " .. (autoPlay and "on" or "off")
		Fluent:Notify({ Title = "Match state", Content = str, Duration = 4 })
	end })
end

-- ---- Auto tab: Lobby section ----
do
	local s = Tabs.Auto:AddSection("Lobby", "home")
	s:AddParagraph({ Title = "Lobby", Content = "Portal and daily." })
	s:AddButton({ Title = "Portal Start", Description = "Enter portal", Callback = function() Game.PortalStart() end })
	s:AddButton({ Title = "Claim Daily Reward", Description = "Claim daily reward", Callback = function() Game.ClaimDailyReward() end })
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
end

-- ---- Shop tab ----
local RARITIES = { "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local BANNERS = { "Standard", "Rateup" }
local merchantItems = {}
_G.MerchantSelectedItems = {}
_G.DeleteRarities = {}

do
	local s = Tabs.Shop:AddSection("Auto Merchant", "shopping-cart")
	s:AddParagraph({ Title = "Auto Merchant", Content = "Refresh items, select items, enable to buy max." })
	s:AddDropdown("MerchantItems", { Title = "Select Items", Description = "Items to buy", Values = merchantItems, Multi = true, Default = {} }):OnChanged(function(val)
		local arr = {}
		for k, v in next, val or {} do if v then table.insert(arr, k) end end
		_G.MerchantSelectedItems = arr
	end)
	s:AddButton({ Title = "Refresh Items", Description = "Load merchant item list", Callback = function()
		table.clear(merchantItems)
		local pd = Game.GetPlayerData()
		if pd and pd:FindFirstChild("Merchant") then
			for _, child in ipairs(pd.Merchant:GetChildren()) do
				table.insert(merchantItems, child.Name)
			end
		end
		if Options.MerchantItems and Options.MerchantItems.SetValues then
			Options.MerchantItems:SetValues(merchantItems)
			Options.MerchantItems:SetValue({})
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
	s:AddParagraph({ Title = "Discord Webhook", Content = "When enabled, sends 'Победил', time and rewards on RewardsUI.Enabled." })
	s:AddToggle("WebhookEnable", { Title = "Enable Webhook", Default = false }):OnChanged(function(v) Game.SetWebhook(v, webhookUrl) end)
	s:AddInput("WebhookURL", { Title = "Webhook URL", Default = "https://discord.com/api/webhooks/...", Placeholder = "Discord webhook URL", Callback = function(v) webhookUrl = v Game.SetWebhook(webhookEnabled, v) end })
	s:AddButton({ Title = "Send Test Message", Description = "Send a test message", Callback = function()
		Game.SendWebhookMessage("SkrilyaHub - Test message")
		Fluent:Notify({ Title = "Webhook", Content = "Test sent", Duration = 2 })
	end })
end

-- ---- Misc: коды и BP ----
local VALID_CODES = { "SorryAboutEvo", "OOPSRAMEN", "SORRYFORBUGS!", "SORRYFORDELAYS", "GHOULHUNT", "RERELEASE!!!" }

-- ---- INF Traits tab ----
local autoTraitRerollConnection = nil
local function runAutoTraitReroll()
	if not _G.AutoTraitRerollEnabled then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local traits = gui:FindFirstChild("Traits")
	if not traits or not traits.Enabled then return end
	local main = traits:FindFirstChild("Main")
	local base = main and main:FindFirstChild("Base")
	if not base then return end
	local unitFolderObj = base:FindFirstChild("UnitFolder")
	if not unitFolderObj or not unitFolderObj.Value then return end
	local unitFolder = unitFolderObj.Value
	local primary = unitFolder:FindFirstChild("PrimaryTrait") and unitFolder.PrimaryTrait.Value
	local secondary = unitFolder:FindFirstChild("SecondaryTrait") and unitFolder.SecondaryTrait.Value
	if not primary then primary = "" end
	if not secondary then secondary = "" end
	pcall(function()
		getRemote().RerollTrait:FireServer(unitFolder, "Reroll", "Main", "Shards", { primary, secondary })
	end)
end

-- ---- INF Traits tab (continue) ----
do
	local s = Tabs.Traits:AddSection("Traits", "monitor")
	s:AddToggle("InstantTraits", { Title = "Instant Traits", Default = false }):OnChanged(function() end)
	s:AddToggle("AutoTraitReroll", { Title = "Auto Trait Reroll", Default = false }):OnChanged(function(enabled)
		_G.AutoTraitRerollEnabled = enabled == true
		if autoTraitRerollConnection then
			autoTraitRerollConnection:Disconnect()
			autoTraitRerollConnection = nil
		end
		if not _G.AutoTraitRerollEnabled then return end
		autoTraitRerollConnection = RunService.Heartbeat:Connect(function()
			task.wait(1.2)
			runAutoTraitReroll()
		end)
	end)
end

-- ---- Misc tab ----
local VALID_CODES = { "SorryAboutEvo", "OOPSRAMEN", "SORRYFORBUGS!", "SORRYFORDELAYS", "GHOULHUNT", "RERELEASE!!!" }
do
	local s = Tabs.Misc:AddSection("Codes & Battlepass", "gift")
	s:AddParagraph({ Title = "Codes & Battlepass", Content = "Redeem codes, claim BP and Event BP." })
	s:AddInput("RedeemCodeInput", { Title = "Redeem Code", Default = "", Placeholder = "Enter code to redeem", Callback = function(v) _G.RedeemCodeValue = v end })
	s:AddButton({ Title = "Redeem Code", Description = "Redeem entered code", Callback = function() Game.RedeemCode(_G.RedeemCodeValue) end })
	s:AddDropdown("KnownCodesDropdown", { Title = "Known Codes", Values = VALID_CODES, Multi = false, Default = VALID_CODES[1] }):OnChanged(function(code) Game.RedeemCode(code) end)
	s:AddButton({ Title = "Redeem All Codes", Description = "Redeem all known codes (with delay)", Callback = function()
		for _, code in ipairs(VALID_CODES) do
			Game.RedeemCode(code)
			task.wait(0.8)
		end
		Fluent:Notify({ Title = "Codes", Content = "Redeemed " .. #VALID_CODES .. " codes", Duration = 2 })
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
			if opts.MerchantItems and opts.MerchantItems.Value then
				for k, v in next, opts.MerchantItems.Value do if v then table.insert(_G.MerchantSelectedItems, k) end end
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
task.spawn(function() task.wait(0.3) applyConfigState() end)

Fluent:Notify({ Title = "SkrilyaHub", Content = "Loaded. Auto / INF Traits / Shop / Webhook / Misc / Settings.", Duration = 4 })

-- Автоперезапуск при телепорте (как Infinite Yield): в новом лобби скрипт подгрузится сам
local teleportQueued = false
LocalPlayer.OnTeleport:Connect(function(_state)
	if teleportQueued then return end
	if type(queueteleport) ~= "function" or not SCRIPT_RELOAD_URL or #SCRIPT_RELOAD_URL < 10 then return end
	teleportQueued = true
	queueteleport("loadstring(game:HttpGet('" .. SCRIPT_RELOAD_URL:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'))()")
end)

-- Export for UI
_G.SkrilyaHub = Game
