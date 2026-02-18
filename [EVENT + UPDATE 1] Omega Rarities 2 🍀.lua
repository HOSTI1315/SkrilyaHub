--[[
  Game Automation Script (single file)
  Run in executor. Toggles: Auto Snowflakes, Auto Snow, Auto Upgrade, Auto Runes, etc.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- VirtualInputManager (executor-only): nil if not available
local VirtualInputManager
do
	local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
	if ok and vim then VirtualInputManager = vim end
end

-- ---------------------------------------------------------------------------
-- Init: Events, DataController, Replica, refs (safe)
-- ---------------------------------------------------------------------------
local Events = ReplicatedStorage:WaitForChild("Events", 30)
local RS = ReplicatedStorage
local Packages = RS:WaitForChild("Packages", 10)
local DataController, Replica, Data

local function safeInit()
	local ok, err = pcall(function()
		if Packages and Packages:FindFirstChild("Knit") then
			local Knit = require(Packages.Knit)
			DataController = Knit.GetController and Knit.GetController("DataController")
			if DataController then
				if DataController.waitForData then
					DataController:waitForData()
				end
				Replica = DataController.getReplica and DataController:getReplica()
				Data = Replica and Replica.Data
			end
		end
	end)
	if not ok then
		warn("[GameAutomation] Init warning:", err)
	end
	return Events ~= nil
end

if not safeInit() then
	warn("[GameAutomation] Events not found. Retrying...")
	task.wait(3)
	Events = ReplicatedStorage:WaitForChild("Events", 60)
end

if not Events then
	error("[GameAutomation] ReplicatedStorage.Events not found.")
end

-- Re-get replica after wait (game may load later)
local function getData()
	if DataController and DataController.getReplica then
		Replica = DataController:getReplica()
		Data = Replica and Replica.Data
	end
	return Data
end

-- Lazy refs (wait when first used)
local function getGame()
	return workspace:FindFirstChild("Game")
end

local function getSnowFolder()
	local g = getGame()
	if not g then return nil, nil, nil end
	local snow = g:FindFirstChild("Snow")
	if not snow then return nil, nil, nil end
	return snow, snow:FindFirstChild("SnowZone"), snow:FindFirstChild("SnowBalls")
end

local function getTeleporters()
	local g = getGame()
	if not g then return nil end
	local tp = g:FindFirstChild("Teleporter")
	if not tp then return nil end
	return tp:FindFirstChild("Teleporters")
end

local function getRunesButtons()
	local g = getGame()
	if not g then return nil end
	local buttons = g:FindFirstChild("Buttons")
	if not buttons then return nil end
	return buttons:FindFirstChild("Runes")
end

-- Snow block config by name (for ResetSnow:FireServer(config))
local SnowBlocksByName = {}
local SnowModule = nil
local function getSnowBlocksConfig()
	if next(SnowBlocksByName) then return SnowBlocksByName end
	local ok, snowMod = pcall(function()
		return Packages and require(Packages:FindFirstChild("Snow"))
	end)
	if ok and snowMod then
		SnowModule = snowMod
		if snowMod.blocks then
			for _, block in ipairs(snowMod.blocks) do
				if block.Name then
					SnowBlocksByName[block.Name] = block
				end
			end
		end
	end
	if not next(SnowBlocksByName) then
		SnowBlocksByName["Normal"]  = { Name = "Normal",  Earnings = 1  }
		SnowBlocksByName["Golden"]  = { Name = "Golden",  Earnings = 5  }
		SnowBlocksByName["Rainbow"] = { Name = "Rainbow", Earnings = 25 }
		SnowBlocksByName["Frozen"]  = { Name = "Frozen",  Earnings = 150}
	end
	return SnowBlocksByName
end

-- Collection radius from game (Snow2Upgrades_4). Uses Replica Data.
-- Optional multiplier: if state.SnowRadiusMultiplier > 1 we use it for route/coverage only (not sent to server).
local function getSnowCollectRadius(useMultiplier)
	local base = 2.5
	getData()
	if SnowModule and SnowModule.getRadius and Data then
		local ok, r = pcall(function() return SnowModule.getRadius(Data) end)
		if ok and type(r) == "number" and r > 0 then base = r end
	end
	local mult = 1
	if useMultiplier and state and type(state.SnowRadiusMultiplier) == "number" and state.SnowRadiusMultiplier > 0 then
		mult = state.SnowRadiusMultiplier
	end
	return base * mult
end

-- Build list of snowball entries {part, config, pos, earnings} and order by: value (Frozen > Rainbow > Golden > Normal), then coverage, then distance.
-- "Maximum and below" = prefer highest Snow value first (Frozen x150, Rainbow x25, Golden x5, Normal x1).
local function getSnowballsOrderedByEfficiency(snowBalls, fromPos, radius)
	getSnowBlocksConfig()
	local list = {}
	for _, part in ipairs(snowBalls:GetChildren()) do
		if part:IsA("BasePart") and part.Parent then
			local pos = part.Position
			local config = SnowBlocksByName[part.Name] or SnowBlocksByName["Normal"]
			local earnings = (type(config.Earnings) == "number") and config.Earnings or 1
			list[#list + 1] = { part = part, config = config, pos = pos, earnings = earnings }
		end
	end
	-- For each entry, count how many other balls are within radius of this ball's position (cover count)
	for i, entry in ipairs(list) do
		local p = entry.pos
		entry.coverCount = 0
		for j, other in ipairs(list) do
			if i ~= j and (other.pos - p).Magnitude <= radius then
				entry.coverCount = entry.coverCount + 1
			end
		end
	end
	-- Sort: 1) higher earnings first (Frozen 150 > Rainbow 25 > Golden 5 > Normal 1), 2) more coverage, 3) closer
	table.sort(list, function(a, b)
		if a.earnings ~= b.earnings then return a.earnings > b.earnings end
		if a.coverCount ~= b.coverCount then return a.coverCount > b.coverCount end
		local da = (a.pos - fromPos).Magnitude
		local db = (b.pos - fromPos).Magnitude
		return da < db
	end)
	return list
end

-- ---------------------------------------------------------------------------
-- Big number parser (suffixes K, M, B, T, Qd, Oc, De, QdDe, UVt, etc.)
-- Returns (coefficient, exponent) for comparison: a > b iff (exp_a > exp_b) or (exp_a == exp_b and coef_a > coef_b)
-- ---------------------------------------------------------------------------
local BIG_NUM_EXP = {
	[""] = 0, ["K"] = 3, ["M"] = 6, ["B"] = 9, ["T"] = 12,
	["Qa"] = 15, ["Qi"] = 18, ["Sx"] = 21, ["Sp"] = 24, ["Oc"] = 27, ["No"] = 30,
	["Dc"] = 33, ["UnD"] = 36, ["DoD"] = 39, ["TrD"] = 42, ["QaD"] = 45, ["QiD"] = 48,
	["SxD"] = 51, ["SpD"] = 54, ["OcD"] = 57, ["NoD"] = 60,
	["Vg"] = 63, ["UnV"] = 66, ["DoV"] = 69, ["TrV"] = 72, ["QaV"] = 75, ["QiV"] = 78,
	["SxV"] = 81, ["SpV"] = 84, ["OcV"] = 87, ["NoV"] = 90,
	["Tg"] = 93, ["UnT"] = 96, ["DoT"] = 99, ["TrT"] = 102, ["QaT"] = 105, ["QiT"] = 108,
	["SxT"] = 111, ["SpT"] = 114, ["OcT"] = 117, ["NoT"] = 120,
	["De"] = 33, ["DDe"] = 36, ["TDe"] = 39, ["QdDe"] = 42, ["Qn"] = 18, ["Qd"] = 15,
	["Vt"] = 96, ["UVt"] = 99, ["TVt"] = 102, ["QdVt"] = 105,
	["SpDe"] = 57, ["OcDe"] = 60, ["NoDe"] = 63,
	["UnDe"] = 36, ["DoDe"] = 39, ["TrDe"] = 42, ["QaDe"] = 45, ["QiDe"] = 48, ["SxDe"] = 51,
}
local function parseBigNum(s)
	if not s or type(s) ~= "string" then return 0, 0 end
	s = s:gsub("%s+", ""):gsub(",", "")
	-- Scientific notation: 2.62e129
	local coef, expSci = s:match("^([%d%.]+)[eE]%+?(%d+)$")
	if coef and expSci then
		return tonumber(coef) or 0, tonumber(expSci) or 0
	end
	-- Number + suffix: 8.62QdDe or 0 or 100B
	local coefStr, suffix = s:match("^([%d%.]+)([%a]*)$")
	local coef = tonumber(coefStr or s)
	if not coef then return 0, 0 end
	local exp = BIG_NUM_EXP[suffix or ""]
	if exp then return coef, exp end
	-- Try two-part suffix (e.g. Qd + De)
	for part = #(suffix or ""), 1, -1 do
		local a, b = (suffix or ""):sub(1, part), (suffix or ""):sub(part + 1)
		local ea, eb = BIG_NUM_EXP[a], BIG_NUM_EXP[b]
		if ea and eb then return coef, ea + eb end
	end
	return coef, 0
end
local function bigNumGreater(coefA, expA, coefB, expB)
	if expA ~= expB then return expA > expB end
	return (coefA or 0) > (coefB or 0)
end

-- ---------------------------------------------------------------------------
-- State: toggles and intervals
-- ---------------------------------------------------------------------------
local state = {
	AutoSnowflakes = false,
	AutoSnow = false,
	AutoSnowMode = "zone", -- "zone" | "teleport" | "walk"
	AutoUpgrade = false,
	AutoRunes = false,
	AutoDroppers = false,
	AutoPassive = false,
	SnowflakeInterval = 0.12,
	SnowTeleportInterval = 0.35,
	UpgradeInterval = 5,
	RuneDebounce = 1.2,
	DropperInterval = 8,
	PassiveInterval = 60,
	SingleUpgradeInterval = 1, -- per-upgrade toggle (Rayfield-style) interval in seconds
	RunesToFarm = {}, -- empty = all; else {"Slime", "Snow", ...}
	SnowStepDelay = 0.08, -- delay after each snow move (low = vacuum mode, no stop)
	WalkSpeed = 16,
	SnowRadiusMultiplier = 1, -- route/coverage only (1 = game radius; >1 = consider more balls "in range" for next target)
	SnowExtendedCollect = false, -- experimental: after move, FireServer ResetSnow for all balls in (radius * multiplier)
	AntiAFK = false,
	AntiAFKInterval = 30, -- seconds between activity nudges
	AntiAFKMethod = "rotate", -- "rotate" | "jump" | "camera" | "virtualinput"
	-- When several movement features are on: "parallel" = all run at once (may fight); "rotate" = time-slice (Snow N sec, then Runes N sec, then Droppers N sec)
	MovementMode = "rotate",
	MovementSlotDuration = 30, -- seconds per feature in rotate mode
	AutoRebirthComets = false,
	CometsRebirthIntervalMinutes = 10, -- input: minutes between Comets rebirth
	AutoRebirthStardust = false, -- only when New Production > Actual Production
	AutoRebirthFrost = false,
	FrostRebirthIntervalMinutes = 10,
}
local runLoops = {} -- task refs to cancel when toggling off

local function stopLoop(name)
	if runLoops[name] then
		task.cancel(runLoops[name])
		runLoops[name] = nil
	end
end

local function applyWalkSpeed()
	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if humanoid and type(state.WalkSpeed) == "number" then
		humanoid.WalkSpeed = math.clamp(state.WalkSpeed, 0, 500)
	end
end

-- ---------------------------------------------------------------------------
-- Auto Snowflakes Click
-- ---------------------------------------------------------------------------
local function startAutoSnowflakes()
	stopLoop("Snowflakes")
	local Click = Events:FindFirstChild("Click")
	if not Click then return end
	runLoops["Snowflakes"] = task.spawn(function()
		while state.AutoSnowflakes do
			pcall(function() Click:FireServer() end)
			task.wait(state.SnowflakeInterval)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Teleport helper (set HRP CFrame)
-- ---------------------------------------------------------------------------
local function teleportTo(cframe)
	local char = LocalPlayer.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return false end
	hrp.CFrame = typeof(cframe) == "CFrame" and cframe or CFrame.new(cframe)
	return true
end

-- Walk to position using Humanoid:MoveTo; returns when close or timeout.
local function walkTo(targetPos, timeoutSeconds)
	local char = LocalPlayer.Character
	if not char then return false end
	local humanoid = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not hrp:IsA("BasePart") then return false end
	local radius = getSnowCollectRadius()
	local goal = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
	humanoid:MoveTo(goal)
	local t0 = os.clock()
	while state.AutoSnow and (os.clock() - t0) < (timeoutSeconds or 8) do
		if (hrp.Position - goal).Magnitude <= math.max(radius, 2) then
			return true
		end
		task.wait(0.15)
	end
	return (hrp.Position - goal).Magnitude <= radius + 3
end

-- ---------------------------------------------------------------------------
-- Movement: one-step functions (for both parallel loops and coordinator)
-- ---------------------------------------------------------------------------
local function runOneSnowStep()
	local snow, snowZone, snowBalls = getSnowFolder()
	if not snow or not snowZone then return end
	if state.AutoSnowMode == "zone" then
		teleportTo(snowZone.Position + Vector3.new(0, 3, 0))
		task.wait(2)
		return
	end
	if not snowBalls then task.wait(1) return end
	local radiusForRoute = getSnowCollectRadius(true)
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local fromPos = (hrp and hrp:IsA("BasePart")) and hrp.Position or snowZone.Position
	local ordered = getSnowballsOrderedByEfficiency(snowBalls, fromPos, radiusForRoute)
	if #ordered == 0 then task.wait(0.2) return end
	local entry = ordered[1]
	if not (entry.part and entry.part.Parent) then return end
	local targetPos = entry.pos + Vector3.new(0, 2, 0)
	if state.AutoSnowMode == "teleport" then
		teleportTo(targetPos)
	else
		walkTo(entry.pos, 8)
	end
	if state.SnowExtendedCollect then
		getSnowBlocksConfig()
		local extendedRadius = getSnowCollectRadius(true)
		local ResetSnow = Events:FindFirstChild("ResetSnow")
		if ResetSnow and hrp then
			for _, part in ipairs(snowBalls:GetChildren()) do
				if part:IsA("BasePart") and part.Parent and (part.Position - hrp.Position).Magnitude <= extendedRadius then
					local config = SnowBlocksByName[part.Name] or SnowBlocksByName["Normal"]
					pcall(function() ResetSnow:FireServer(config) end)
					task.wait(0.05)
				end
			end
		end
	end
	task.wait(state.SnowStepDelay or 0.08)
end

local function runOneRunesStep()
	local runesFolder = getRunesButtons()
	if not runesFolder then return end
	local filter = state.RunesToFarm
	local visitAll = not filter or type(filter) ~= "table" or #filter == 0
	for _, btn in ipairs(runesFolder:GetChildren()) do
		if not state.AutoRunes then return end
		local shouldVisit = visitAll
		if not shouldVisit then
			for _, name in ipairs(filter) do
				if btn.Name == name then shouldVisit = true break end
			end
		end
		if shouldVisit then
			local touch = btn:FindFirstChild("Touch")
			local status = btn:FindFirstChild("Status")
			local part = (touch and touch:IsA("BasePart")) and touch or (status and status:IsA("BasePart")) and status
			if part then
				teleportTo(part.Position + Vector3.new(0, 6, 0))
				task.wait(state.RuneDebounce)
			end
		end
	end
	task.wait(0.5)
end

local function runOneDroppersStep()
	local g = getGame()
	if not g then return end
	local fire, meteor = g:FindFirstChild("Fire"), g:FindFirstChild("Meteor")
	local sell = (fire and fire:FindFirstChild("Sell")) or (meteor and meteor:FindFirstChild("Sell"))
	if sell and sell:IsA("BasePart") then
		teleportTo(sell.Position + Vector3.new(0, 2, 0))
	end
	task.wait(state.DropperInterval)
end

local function runSnowForSeconds(sec)
	local t0 = os.clock()
	while state.AutoSnow and (os.clock() - t0) < sec do
		runOneSnowStep()
	end
end

local function runRunesForSeconds(sec)
	local t0 = os.clock()
	while state.AutoRunes and (os.clock() - t0) < sec do
		runOneRunesStep()
	end
end

local function runDroppersForSeconds(sec)
	local t0 = os.clock()
	while state.AutoDroppers and (os.clock() - t0) < sec do
		runOneDroppersStep()
	end
end

-- ---------------------------------------------------------------------------
-- Auto Snow: teleport to snow world, then zone or per-ball
-- ---------------------------------------------------------------------------
local function ensureSnowWorld()
	getData()
	if Data and Data.World == 2 then return true end
	local tps = getTeleporters()
	if not tps then return false end
	-- Find teleporter that goes to snow world (often by name; adjust if game uses different names)
	for _, child in ipairs(tps:GetChildren()) do
		local name = child.Name
		if type(name) == "string" and (name:lower():find("snow") or name:lower():find("frost") or name == "2") then
			local ok = pcall(function()
				return Events:FindFirstChild("Teleport") and Events.Teleport:InvokeServer(name)
			end)
			if ok then
				task.wait(1.5)
				return true
			end
		end
	end
	return false
end

local function startMovementCoordinator()
	stopLoop("Movement")
	stopLoop("Snow")
	stopLoop("Runes")
	stopLoop("Droppers")
	runLoops["Movement"] = task.spawn(function()
		while state.AutoSnow or state.AutoRunes or state.AutoDroppers do
			local slot = math.max(10, state.MovementSlotDuration or 30)
			if state.AutoSnow then runSnowForSeconds(slot) end
			if state.AutoRunes then runRunesForSeconds(slot) end
			if state.AutoDroppers then runDroppersForSeconds(slot) end
			task.wait(0.5)
		end
	end)
end

local function stopMovementCoordinator()
	stopLoop("Movement")
end

local function startMovementFeature(name)
	if state.MovementMode == "rotate" then
		stopLoop("Snow")
		stopLoop("Runes")
		stopLoop("Droppers")
		startMovementCoordinator()
	else
		if name == "Snow" then ensureSnowWorld(); startAutoSnow()
		elseif name == "Runes" then startAutoRunes()
		elseif name == "Droppers" then startAutoDroppers()
		end
	end
end

local function stopMovementFeature(name)
	if name == "Snow" then stopLoop("Snow")
	elseif name == "Runes" then stopLoop("Runes")
	elseif name == "Droppers" then stopLoop("Droppers")
	end
	if state.MovementMode == "rotate" and not state.AutoSnow and not state.AutoRunes and not state.AutoDroppers then
		stopMovementCoordinator()
	end
end

-- Restart all movement (e.g. when changing MovementMode)
local function restartMovementFeatures()
	stopLoop("Snow")
	stopLoop("Runes")
	stopLoop("Droppers")
	stopMovementCoordinator()
	if state.AutoSnow then ensureSnowWorld(); startMovementFeature("Snow") end
	if state.AutoRunes then startMovementFeature("Runes") end
	if state.AutoDroppers then startMovementFeature("Droppers") end
end

local function startAutoSnow()
	stopLoop("Snow")
	runLoops["Snow"] = task.spawn(function()
		while state.AutoSnow do
			runOneSnowStep()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Upgrade (Max)
-- ---------------------------------------------------------------------------
local function startAutoUpgrade()
	stopLoop("Upgrade")
	local Upgrade = Events:FindFirstChild("Upgrade")
	if not Upgrade then return end
	runLoops["Upgrade"] = task.spawn(function()
		while state.AutoUpgrade do
			pcall(function() Upgrade:FireServer("Max", true) end)
			task.wait(state.UpgradeInterval)
		end
	end)
end

-- All upgrade folders: under Game.Upgrades or Game.UpgradeTree (same UI: SurfaceGui.ScrollingFrame rows)
local UPGRADE_FOLDERS_UNDER_UPGRADES = {
	"AutomationsUpgrades", "CometsUpgrades", "DiamondsUpgrades", "Fire2Upgrades", "FireUpgrades",
	"FrostUpgrades", "LevelUpgrades", "SlimeUpgrades", "Snow2Upgrades", "SnowUpgrades",
	"SnowflakesUpgrades", "StardustUpgrades", "WaterUpgrades"
}
local UPGRADE_FOLDERS_UNDER_TREE = { "SnowflakesTree" }


local function isColorReddish(c)
	if not c or type(c.R) ~= "number" then return false end
	local r, g, b = c.R, c.G or 0, c.B or 0
	return r > 0.5 and r > g and r > b
end

-- ---------------------------------------------------------------------------
-- Skip upgrade? true = не слать (maxed, кнопки скрыты, или красная = не хватает валюты)
-- baseName = "Upgrades" | "UpgradeTree", folderName = folder, rowIndex = 1-based
-- ---------------------------------------------------------------------------
local function isUpgradeRowMaxed(baseName, folderName, rowIndex)
	local g = getGame()
	if not g then return nil end
	local root = g:FindFirstChild(baseName)
	local folder = root and root:FindFirstChild(folderName)
	local sg = folder and folder:FindFirstChild("SurfaceGui")
	local scroll = sg and sg:FindFirstChild("ScrollingFrame")
	if not scroll then return nil end
	local children = scroll:GetChildren()
	local row = children[rowIndex]
	if not row then return nil end
	local costObj = row:FindFirstChild("Cost")
	local costLabel = costObj and (costObj:FindFirstChild("Cost") or costObj)
	local costText = costLabel and costLabel.Text or ""
	if costText and costText:find("Maxed") then return true end
	local buy = row:FindFirstChild("Buy")
	local buyMax = row:FindFirstChild("BuyMax")
	if buy and buy.Visible == false and buyMax and buyMax.Visible == false then return true end
	-- Красная кнопка/цена = не хватает валюты, запрос бесполезен
	if costLabel and costLabel:IsA("GuiObject") and isColorReddish(costLabel.TextColor3) then return true end
	if buy and buy.Visible and buy:IsA("GuiObject") and isColorReddish(buy.BackgroundColor3) then return true end
	if buyMax and buyMax.Visible and buyMax:IsA("GuiObject") and isColorReddish(buyMax.BackgroundColor3) then return true end
	return false
end

-- Parse upgradeId -> baseName, folderName, rowIndex (nil if not a known upgrade row id)
local function getUpgradeRowLocation(upgradeId)
	local numStr = upgradeId:match("_(%d+)$")
	if not numStr then return nil, nil, nil end
	local rowIndex = tonumber(numStr)
	local prefix = upgradeId:match("^(.+)_")
	if not prefix then return nil, nil, nil end
	for _, name in ipairs(UPGRADE_FOLDERS_UNDER_TREE) do
		if prefix == name then return "UpgradeTree", name, rowIndex end
	end
	for _, name in ipairs(UPGRADE_FOLDERS_UNDER_UPGRADES) do
		if prefix == name then return "Upgrades", name, rowIndex end
	end
	return nil, nil, nil
end

-- All upgrade IDs (for config restore: start loops for enabled toggles)
local UPGRADE_IDS = {}
do
	local function add(prefix, n) for i = 1, n do UPGRADE_IDS[#UPGRADE_IDS + 1] = prefix .. "_" .. i end end
	add("SlimeUpgrades", 4); add("LevelUpgrades", 4); add("Snow2Upgrades", 4); add("SnowUpgrades", 5)
	add("CometsUpgrades", 5); add("StardustUpgrades", 6); add("FrostUpgrades", 7); add("SnowflakesUpgrades", 6)
	add("SnowflakesTree", 14)
end

-- ---------------------------------------------------------------------------
-- Auto single upgrade (loop FireServer(id, true) every 1s)
-- For any id that maps to Upgrades/UpgradeTree row: skip if UI shows Maxed
-- ---------------------------------------------------------------------------
local function startAutoUpgradeId(upgradeId)
	local key = "Upgrade_" .. tostring(upgradeId)
	stopLoop(key)
	local Upgrade = Events:FindFirstChild("Upgrade")
	if not Upgrade then return end
	local baseName, folderName, rowIndex = getUpgradeRowLocation(upgradeId)

	runLoops[key] = task.spawn(function()
		while state[key] do
			local skip = false
			if baseName and folderName and rowIndex then
				if isUpgradeRowMaxed(baseName, folderName, rowIndex) then
					skip = true
				end
			end
			if not skip then
				pcall(function() Upgrade:FireServer(upgradeId, true) end)
			end
			task.wait(state.SingleUpgradeInterval or 1)
		end
	end)
end

-- Rune names for dropdown (same as in game Buttons.Runes)
local RUNE_NAMES = {"Slime", "Fire", "Water", "Snow", "Snowflakes", "Frost", "Stardust", "Comets", "Meteors", "Plasma", "1M Event"}

-- ---------------------------------------------------------------------------
-- Auto Runes: teleport above each rune button (filter by RunesToFarm), slight height so button triggers
-- ---------------------------------------------------------------------------
local function startAutoRunes()
	stopLoop("Runes")
	runLoops["Runes"] = task.spawn(function()
		while state.AutoRunes do
			runOneRunesStep()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Droppers (teleport to Sell)
-- ---------------------------------------------------------------------------
local function startAutoDroppers()
	stopLoop("Droppers")
	runLoops["Droppers"] = task.spawn(function()
		while state.AutoDroppers do
			runOneDroppersStep()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Passive (InvokeServer periodically)
-- ---------------------------------------------------------------------------
local function startAutoPassive()
	stopLoop("Passive")
	local AutoPassive = Events:FindFirstChild("AutoPassive")
	if not AutoPassive then return end
	runLoops["Passive"] = task.spawn(function()
		while state.AutoPassive do
			pcall(function() AutoPassive:InvokeServer() end)
			task.wait(state.PassiveInterval)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Rebirth Comets (Reset:FireServer("Comets") every N minutes)
-- ---------------------------------------------------------------------------
local function startAutoRebirthComets()
	stopLoop("RebirthComets")
	local Reset = Events:FindFirstChild("Reset")
	if not Reset then return end
	runLoops["RebirthComets"] = task.spawn(function()
		while state.AutoRebirthComets do
			local min = tonumber(state.CometsRebirthIntervalMinutes) or 10
			min = math.max(1, math.min(999, min))
			task.wait(min * 60)
			if not state.AutoRebirthComets then break end
			pcall(function() Reset:FireServer("Comets") end)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Rebirth Frost (Reset:FireServer("Frost") every N minutes)
-- ---------------------------------------------------------------------------
local function startAutoRebirthFrost()
	stopLoop("RebirthFrost")
	local Reset = Events:FindFirstChild("Reset")
	if not Reset then return end
	runLoops["RebirthFrost"] = task.spawn(function()
		while state.AutoRebirthFrost do
			local min = tonumber(state.FrostRebirthIntervalMinutes) or 10
			min = math.max(1, math.min(999, min))
			task.wait(min * 60)
			if not state.AutoRebirthFrost then break end
			pcall(function() Reset:FireServer("Frost") end)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Auto Rebirth Stardust (only when New Production > Actual Production)
-- Parse workspace.Game.Boards.Stardust.SurfaceGui.Info.Gain Text
-- ---------------------------------------------------------------------------
local function getStardustActualAndNew()
	local g = getGame()
	if not g then return nil, nil, nil, nil end
	local boards = g:FindFirstChild("Boards")
	local stardust = boards and boards:FindFirstChild("Stardust")
	local sg = stardust and stardust:FindFirstChild("SurfaceGui")
	local info = sg and sg:FindFirstChild("Info")
	local gain = info and info:FindFirstChild("Gain")
	local label = gain and (gain:FindFirstChild("Text") or gain)
	local text = label and label.Text or (gain and gain.Text)
	if not text or type(text) ~= "string" then return nil, nil, nil, nil end
	text = text:gsub("<[^>]+>", " ")
	local actualStr = text:match("Actual%s+Production%s*:%s*([%d%.eE%+%-]+%s*[%a]*)") or text:match("Actual Production:%s*([%d%.eE%+%-]*)") or "0"
	local newStr = text:match("New%s+Production%s*:%s*([%d%.eE%+%-]+%s*[%a]*)") or text:match("New Production:%s*([%d%.eE%+%-]*)") or "0"
	actualStr = actualStr:gsub("%s+", "")
	newStr = newStr:gsub("%s+", "")
	local ac, ae = parseBigNum(actualStr)
	local nc, ne = parseBigNum(newStr)
	return ac, ae, nc, ne
end

local function startAutoRebirthStardust()
	stopLoop("RebirthStardust")
	local Reset = Events:FindFirstChild("Reset")
	if not Reset then return end
	runLoops["RebirthStardust"] = task.spawn(function()
		while state.AutoRebirthStardust do
			task.wait(2)
			if not state.AutoRebirthStardust then break end
			local ac, ae, nc, ne = getStardustActualAndNew()
			if ac ~= nil and ae ~= nil and nc ~= nil and ne ~= nil and bigNumGreater(nc, ne, ac, ae) then
				pcall(function() Reset:FireServer("Stardust") end)
				task.wait(5)
			end
		end
	end)
end

local function pressKey(keyCode, duration)
	if not VirtualInputManager or not VirtualInputManager.SendKeyEvent then return false end
	local d = duration or 0.1
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, nil)
		task.wait(d)
		VirtualInputManager:SendKeyEvent(false, keyCode, false, nil)
	end)
	return true
end

local function performAntiAFKNudge()
	local method = (state and state.AntiAFKMethod) or "rotate"
	if method == "virtualinput" then
		-- Only VirtualInputManager Space (like VirtualInputExample), no fallback
		pressKey(Enum.KeyCode.Space, 0.08)
	elseif method == "jump" then
		-- Prefer VirtualInputManager (Space) so game sees real "jump" input
		if pressKey(Enum.KeyCode.Space, 0.08) then
			-- nothing else needed
		else
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChild("Humanoid")
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Jump = true
				task.defer(function()
					if humanoid and humanoid.Parent then humanoid.Jump = false end
				end)
			end
			if hrp and hrp:IsA("BasePart") then
				local v = hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
				local up = Vector3.new(v.X, v.Y + 28, v.Z)
				pcall(function() hrp.AssemblyLinearVelocity = up end)
				pcall(function() hrp.Velocity = up end)
			end
		end
	elseif method == "camera" then
		local cam = workspace.CurrentCamera
		if cam then
			local old = cam.CFrame
			cam.CFrame = old * CFrame.Angles(math.rad(2), 0, 0)
			task.wait(0.06)
			cam.CFrame = old
		end
	else
		-- rotate (default): slight character turn and back
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local cf = hrp.CFrame
			hrp.CFrame = cf * CFrame.Angles(0, math.rad(2), 0)
			task.wait(0.08)
			hrp.CFrame = cf
		end
	end
end

local function startAntiAFK()
	stopLoop("AntiAFK")
	runLoops["AntiAFK"] = task.spawn(function()
		while state.AntiAFK do
			task.wait(state.AntiAFKInterval or 30)
			if not state.AntiAFK then break end
			pcall(performAntiAFKNudge)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- GUI (Kairo UI Library)
-- ---------------------------------------------------------------------------
local Kairo
local Window
local guiCreated = false

local saveConfigRef = nil

local TOGGLE_ACTIONS = {
	AutoSnowflakes = { start = startAutoSnowflakes, stop = function() stopLoop("Snowflakes") end },
	AutoSnow = { start = function() ensureSnowWorld(); startMovementFeature("Snow") end, stop = function() stopMovementFeature("Snow") end },
	AutoUpgrade = { start = startAutoUpgrade, stop = function() stopLoop("Upgrade") end },
	AutoRunes = { start = function() startMovementFeature("Runes") end, stop = function() stopMovementFeature("Runes") end },
	AutoDroppers = { start = function() startMovementFeature("Droppers") end, stop = function() stopMovementFeature("Droppers") end },
	AutoPassive = { start = startAutoPassive, stop = function() stopLoop("Passive") end },
	AntiAFK = { start = startAntiAFK, stop = function() stopLoop("AntiAFK") end },
	AutoRebirthComets = { start = startAutoRebirthComets, stop = function() stopLoop("RebirthComets") end },
	AutoRebirthStardust = { start = startAutoRebirthStardust, stop = function() stopLoop("RebirthStardust") end },
	AutoRebirthFrost = { start = startAutoRebirthFrost, stop = function() stopLoop("RebirthFrost") end },
}

local function applyToggle(key, enabled)
	state[key] = enabled
	if saveConfigRef then pcall(saveConfigRef) end
	local action = TOGGLE_ACTIONS[key]
	if action then
		if enabled then action.start() else action.stop() end
	end
end

local function createGui()
	if guiCreated then return Window end
	local ok, err = pcall(function()
		Kairo = loadstring(game:HttpGet("https://raw.githubusercontent.com/Itzzavi335/Kairo-Ui-Library/refs/heads/main/source.luau"))()
		Window = Kairo:CreateWindow({
			Title = "SkrilyaHub",
			Theme = "Crimson",
			Size = UDim2.fromOffset(520, 480),
			Center = true,
			Draggable = true,
			MinimizeKey = Enum.KeyCode.RightShift,
			Config = {
				Enabled = true,
				Folder = "GameAutomation",
				AutoLoad = true
			}
		})

		local function saveConfig()
			if Window and Window.SaveConfig then
				pcall(Window.SaveConfig, Window, "Default", state)
			end
		end

		local function applyLoadedConfig(data)
			if not data or type(data) ~= "table" then return end
			for k, v in pairs(data) do
				state[k] = v
			end
			applyToggle("AutoSnowflakes", state.AutoSnowflakes)
			applyToggle("AutoSnow", state.AutoSnow)
			applyToggle("AutoUpgrade", state.AutoUpgrade)
			applyToggle("AutoRunes", state.AutoRunes)
			applyToggle("AutoDroppers", state.AutoDroppers)
			applyToggle("AutoPassive", state.AutoPassive)
			applyToggle("AntiAFK", state.AntiAFK)
			applyToggle("AutoRebirthComets", state.AutoRebirthComets)
			applyToggle("AutoRebirthStardust", state.AutoRebirthStardust)
			applyToggle("AutoRebirthFrost", state.AutoRebirthFrost)
			-- Restore per-upgrade toggles: start loop for each enabled
			for _, upgradeId in ipairs(UPGRADE_IDS) do
				local key = "Upgrade_" .. upgradeId
				if state[key] then
					startAutoUpgradeId(upgradeId)
				else
					stopLoop(key)
				end
			end
			applyWalkSpeed()
			restartMovementFeatures()
		end

		local MainTab = Window:CreateTab("Main", "rbxassetid://16932740082")
		local SnowTab = Window:CreateTab("Snow", "rbxassetid://16932740082")
		local RunesTab = Window:CreateTab("Runes", "rbxassetid://16932740082")
		local RebirthTab = Window:CreateTab("Rebirth", "rbxassetid://16932740082")
		local UpgradesTab = Window:CreateTab("Upgrades", "rbxassetid://16932740082")
		local SettingsTab = Window:CreateTab("Settings", "rbxassetid://16932740082")

		-- Main: quick toggles and global actions
		Window:AddParagraph(MainTab, "Automation", "RightShift to minimize. Details in Snow / Runes / Settings tabs.")

		Window:AddToggle(MainTab, "Auto Snowflakes", "Click Snowflakes board", state.AutoSnowflakes, function(enabled)
			applyToggle("AutoSnowflakes", enabled)
		end, "AutoSnowflakes")
		Window:AddToggle(MainTab, "Auto Snow", "Collect snowballs", state.AutoSnow, function(enabled)
			applyToggle("AutoSnow", enabled)
		end, "AutoSnow")
		Window:AddToggle(MainTab, "Auto Upgrade", "Buy Max upgrades periodically", state.AutoUpgrade, function(enabled)
			applyToggle("AutoUpgrade", enabled)
		end, "AutoUpgrade")
		Window:AddToggle(MainTab, "Auto Runes", "Farm rune buttons", state.AutoRunes, function(enabled)
			applyToggle("AutoRunes", enabled)
		end, "AutoRunes")
		Window:AddToggle(MainTab, "Auto Droppers", "Stay near Sell zone", state.AutoDroppers, function(enabled)
			applyToggle("AutoDroppers", enabled)
		end, "AutoDroppers")
		Window:AddToggle(MainTab, "Auto Passive", "AutoPassive periodically", state.AutoPassive, function(enabled)
			applyToggle("AutoPassive", enabled)
		end, "AutoPassive")
		Window:AddToggle(MainTab, "Anti-AFK", "Don't kick for inactivity", state.AntiAFK, function(enabled)
			applyToggle("AntiAFK", enabled)
		end, "AntiAFK")

		Window:AddParagraph(MainTab, "Actions", "Reset below. Teleport to Snow World is in Snow tab.")
		Window:AddInput(MainTab, "Reset name", "e.g. Frost, Reborns, Planet", "Frost", function(value)
			state.ResetName = (value and #value > 0) and value or "Frost"
			if saveConfigRef then pcall(saveConfigRef) end
		end, "ResetName")
		Window:AddButton(MainTab, "Do Reset", "Fire Reset with the name above", nil, function()
			local name = state.ResetName or "Frost"
			local Reset = Events:FindFirstChild("Reset")
			if Reset then
				pcall(function() Reset:FireServer(name) end)
				if Window and Window.Notify then
					Window:Notify({ Title = "Reset", Description = name, Content = "Reset requested.", Delay = 2 })
				end
			end
		end)

		-- Snow tab: all snow-related
		Window:AddParagraph(SnowTab, "Snow", "Collect snowballs. Mode and delays below.")
		Window:AddToggle(SnowTab, "Auto Snow", "Collect snowballs (zone / teleport / walk)", state.AutoSnow, function(enabled)
			applyToggle("AutoSnow", enabled)
		end, "AutoSnow")
		Window:AddDropdown(SnowTab, "Snow mode", "Zone = stand. Teleport = instant. Walk = MoveTo.", {"zone", "teleport", "walk"}, false, state.AutoSnowMode, function(value)
			state.AutoSnowMode = value
			if saveConfigRef then pcall(saveConfigRef) end
		end, "SnowMode")
		Window:AddSlider(SnowTab, "Snow step delay (x0.01 s)", "Pause after each move. Low = vacuum", 3, 30, 8, function(value)
			state.SnowStepDelay = value / 100
		end, "SnowStepDelay")
		Window:AddSlider(SnowTab, "Snow radius multiplier (x0.1)", "Route: 10=1.0, 20=2.0", 10, 25, 10, function(value)
			state.SnowRadiusMultiplier = value / 10
		end, "SnowRadiusMultiplier")
		Window:AddToggle(SnowTab, "Snow extended collect (experimental)", "FireServer for balls in extended radius", state.SnowExtendedCollect, function(enabled)
			state.SnowExtendedCollect = enabled
		end, "SnowExtendedCollect")
		Window:AddSlider(SnowTab, "Snowflake click (x0.01 s)", "Delay between Click:FireServer", 5, 50, 12, function(value)
			state.SnowflakeInterval = value / 100
		end, "SnowflakeInterval")
		Window:AddSlider(SnowTab, "Snow teleport (x0.01 s)", "Legacy teleport delay", 20, 80, 35, function(value)
			state.SnowTeleportInterval = value / 100
		end, "SnowTeleportInterval")
		Window:AddButton(SnowTab, "Teleport to Snow World", "Go to snow world", nil, function()
			ensureSnowWorld()
			if Window and Window.Notify then Window:Notify({ Title = "Snow", Description = "Teleport attempted", Content = "", Delay = 2 }) end
		end)

		-- Runes tab: runes and their settings
		Window:AddParagraph(RunesTab, "Runes", "Which runes to farm. None selected = all runes.")
		Window:AddToggle(RunesTab, "Auto Runes", "Teleport above each rune button", state.AutoRunes, function(enabled)
			applyToggle("AutoRunes", enabled)
		end, "AutoRunes")
		Window:AddSlider(RunesTab, "Rune teleport delay (x0.1 s)", "Pause at each rune button", 5, 30, 12, function(value)
			state.RuneDebounce = value / 10
		end, "RuneDebounce")
		for _, runeName in ipairs(RUNE_NAMES) do
			local inList = state.RunesToFarm and type(state.RunesToFarm) == "table" and table.find(state.RunesToFarm, runeName) ~= nil
			Window:AddToggle(RunesTab, "  " .. runeName, "Farm this rune", inList, function(enabled)
				if not state.RunesToFarm or type(state.RunesToFarm) ~= "table" then state.RunesToFarm = {} end
				if enabled then
					if table.find(state.RunesToFarm, runeName) == nil then
						table.insert(state.RunesToFarm, runeName)
					end
				else
					local i = table.find(state.RunesToFarm, runeName)
					if i then table.remove(state.RunesToFarm, i) end
				end
			end, "RunesToFarm_" .. runeName)
		end

		-- Rebirth tab: Comets and Stardust auto-rebirth
		Window:AddParagraph(RebirthTab, "Auto Rebirth", "Comets: Reset every N minutes. Stardust: only when New Production > Actual Production.")
		Window:AddToggle(RebirthTab, "Auto Rebirth Comets", "Reset:FireServer(\"Comets\") every N minutes", state.AutoRebirthComets, function(enabled)
			applyToggle("AutoRebirthComets", enabled)
		end, "AutoRebirthComets")
		Window:AddInput(RebirthTab, "Comets interval (minutes)", "Minutes between Comets rebirth, e.g. 10", tostring(state.CometsRebirthIntervalMinutes or 10), function(value)
			local n = tonumber(value)
			if n and n >= 1 and n <= 999 then
				state.CometsRebirthIntervalMinutes = n
			end
			if saveConfigRef then pcall(saveConfigRef) end
		end, "CometsRebirthIntervalMinutes")
		Window:AddToggle(RebirthTab, "Auto Rebirth Stardust", "Reset when New Production > Actual (Gain board)", state.AutoRebirthStardust, function(enabled)
			applyToggle("AutoRebirthStardust", enabled)
		end, "AutoRebirthStardust")
		Window:AddToggle(RebirthTab, "Auto Rebirth Frost", "Reset:FireServer(\"Frost\") every N minutes", state.AutoRebirthFrost, function(enabled)
			applyToggle("AutoRebirthFrost", enabled)
		end, "AutoRebirthFrost")
		Window:AddInput(RebirthTab, "Frost interval (minutes)", "Minutes between Frost rebirth, e.g. 10", tostring(state.FrostRebirthIntervalMinutes or 10), function(value)
			local n = tonumber(value)
			if n and n >= 1 and n <= 999 then
				state.FrostRebirthIntervalMinutes = n
			end
			if saveConfigRef then pcall(saveConfigRef) end
		end, "FrostRebirthIntervalMinutes")

		-- Upgrades tab: per-upgrade toggles (Rayfield-style, same API)
		Window:AddParagraph(UpgradesTab, "Farm Slime", "Auto buy max for one upgrade every 1s. Same as Omega Rarities Hub.")

		local function addUpgradeToggle(name, upgradeId, flag)
			state["Upgrade_" .. upgradeId] = false
			Window:AddToggle(UpgradesTab, name, "Upgrade:FireServer(\"" .. upgradeId .. "\", true) every 1s", false, function(enabled)
				state["Upgrade_" .. upgradeId] = enabled
				if enabled then
					startAutoUpgradeId(upgradeId)
				else
					stopLoop("Upgrade_" .. upgradeId)
				end
			end, flag)
		end

		addUpgradeToggle("Auto Slime Multiplier", "SlimeUpgrades_1", "SlimeUpgrades_1")
		addUpgradeToggle("Auto Slime Multiplier 2", "SlimeUpgrades_2", "SlimeUpgrades_2")
		addUpgradeToggle("Auto Slime Luck", "SlimeUpgrades_3", "SlimeUpgrades_3")
		addUpgradeToggle("Auto Slime XP Multiplier", "SlimeUpgrades_4", "SlimeUpgrades_4")

		Window:AddParagraph(UpgradesTab, "Farm XP Upgrades", "Level upgrades.")

		addUpgradeToggle("Auto Farm XP Upgrade", "LevelUpgrades_1", "LevelUpgrades_1")
		addUpgradeToggle("More Luck Upgrade", "LevelUpgrades_2", "LevelUpgrades_2")
		addUpgradeToggle("Auto Farm Roll Faster", "LevelUpgrades_3", "LevelUpgrades_3")
		addUpgradeToggle("Auto Farm XP Upgrade 2", "LevelUpgrades_4", "LevelUpgrades_4")

		Window:AddParagraph(UpgradesTab, "Farm Snow (Snow2)", "Capacity, Speed, Luck, Range. Toggle = FireServer(id, true) every 1s (buy max).")

		addUpgradeToggle("Auto Snow2 Capacity", "Snow2Upgrades_1", "Snow2Upgrades_1")
		addUpgradeToggle("Auto Snow2 Speed", "Snow2Upgrades_2", "Snow2Upgrades_2")
		addUpgradeToggle("Auto Snow2 Luck", "Snow2Upgrades_3", "Snow2Upgrades_3")
		addUpgradeToggle("Auto Snow2 Range", "Snow2Upgrades_4", "Snow2Upgrades_4")

		Window:AddParagraph(UpgradesTab, "Farm Snow (Snow)", "Snow upgrades 1–5. Toggle = FireServer(id, true) every 1s (buy max).")

		addUpgradeToggle("Auto Snow Upgrade 1", "SnowUpgrades_1", "SnowUpgrades_1")
		addUpgradeToggle("Auto Snow Upgrade 2", "SnowUpgrades_2", "SnowUpgrades_2")
		addUpgradeToggle("Auto Snow Upgrade 3", "SnowUpgrades_3", "SnowUpgrades_3")
		addUpgradeToggle("Auto Snow Upgrade 4", "SnowUpgrades_4", "SnowUpgrades_4")
		addUpgradeToggle("Auto Snow Upgrade 5", "SnowUpgrades_5", "SnowUpgrades_5")

		Window:AddParagraph(UpgradesTab, "Farm Comets", "Comets rune upgrades. Upgrade:FireServer(id, true) every 1s.")
		addUpgradeToggle("Auto Comets Upgrade 1", "CometsUpgrades_1", "CometsUpgrades_1")
		addUpgradeToggle("Auto Comets Upgrade 2", "CometsUpgrades_2", "CometsUpgrades_2")
		addUpgradeToggle("Auto Comets Upgrade 3", "CometsUpgrades_3", "CometsUpgrades_3")
		addUpgradeToggle("Auto Comets Upgrade 4", "CometsUpgrades_4", "CometsUpgrades_4")
		addUpgradeToggle("Auto Comets Upgrade 5", "CometsUpgrades_5", "CometsUpgrades_5")

		Window:AddParagraph(UpgradesTab, "Farm Stardust", "Stardust upgrades. Upgrade:FireServer(id, true) every 1s.")
		addUpgradeToggle("Auto Stardust Upgrade 1", "StardustUpgrades_1", "StardustUpgrades_1")
		addUpgradeToggle("Auto Stardust Upgrade 2", "StardustUpgrades_2", "StardustUpgrades_2")
		addUpgradeToggle("Auto Stardust Upgrade 3", "StardustUpgrades_3", "StardustUpgrades_3")
		addUpgradeToggle("Auto Stardust Upgrade 4", "StardustUpgrades_4", "StardustUpgrades_4")
		addUpgradeToggle("Auto Stardust Upgrade 5", "StardustUpgrades_5", "StardustUpgrades_5")
		addUpgradeToggle("Auto Stardust Upgrade 6", "StardustUpgrades_6", "StardustUpgrades_6")

		Window:AddParagraph(UpgradesTab, "Farm Frost", "Frost rebirth upgrades. Upgrade:FireServer(id, true) every 1s.")
		for i = 1, 7 do
			addUpgradeToggle("Auto Frost Upgrade " .. i, "FrostUpgrades_" .. i, "FrostUpgrades_" .. i)
		end

		Window:AddParagraph(UpgradesTab, "Farm Snowflakes", "Snowflakes upgrades (Click already in Main). Upgrade:FireServer(id, true) every 1s.")
		for i = 1, 6 do
			addUpgradeToggle("Auto Snowflakes Upgrade " .. i, "SnowflakesUpgrades_" .. i, "SnowflakesUpgrades_" .. i)
		end

		Window:AddParagraph(UpgradesTab, "Snowflakes Tree", "Skill tree. Upgrade:FireServer(id, true) = buy max. 1–14.")
		for i = 1, 14 do
			addUpgradeToggle("Auto Snowflakes Tree " .. i, "SnowflakesTree_" .. i, "SnowflakesTree_" .. i)
		end

		-- Settings tab: global intervals, WalkSpeed, Anti-AFK method
		Window:AddParagraph(SettingsTab, "General", "WalkSpeed and intervals for Main toggles.")

		Window:AddSlider(SettingsTab, "Player WalkSpeed", "Movement speed (0 = game default)", 0, 200, 16, function(value)
			state.WalkSpeed = value
			applyWalkSpeed()
		end, "WalkSpeed")

		Window:AddSlider(SettingsTab, "Upgrade interval (s)", "Seconds between Upgrade Max", 2, 30, 5, function(value)
			state.UpgradeInterval = value
		end, "UpgradeInterval")
		Window:AddSlider(SettingsTab, "Dropper interval (s)", "Seconds between Sell teleports", 3, 20, 8, function(value)
			state.DropperInterval = value
		end, "DropperInterval")
		Window:AddSlider(SettingsTab, "Passive interval (s)", "Seconds between AutoPassive", 30, 120, 60, function(value)
			state.PassiveInterval = value
		end, "PassiveInterval")

		Window:AddParagraph(SettingsTab, "Movement (Snow / Runes / Droppers)", "When several are on: Parallel = all at once. Rotate = time-slice (no conflict).")
		Window:AddDropdown(SettingsTab, "Movement mode", "Parallel = all run together (may fight). Rotate = Snow N sec, then Runes N sec, then Droppers N sec.", {"parallel", "rotate"}, false, state.MovementMode or "rotate", function(value)
			state.MovementMode = value
			restartMovementFeatures()
			if saveConfigRef then pcall(saveConfigRef) end
		end, "MovementMode")
		Window:AddSlider(SettingsTab, "Rotate slot (s)", "Seconds per feature in Rotate mode", 15, 120, 30, function(value)
			state.MovementSlotDuration = value
		end, "MovementSlotDuration")

		Window:AddParagraph(SettingsTab, "Anti-AFK", "Toggle is on Main tab. Here: method and interval.")
		Window:AddDropdown(SettingsTab, "Anti-AFK method", "Rotate / Jump / Camera / VirtualInput (Space key via executor).", {"rotate", "jump", "camera", "virtualinput"}, false, state.AntiAFKMethod or "rotate", function(value)
			state.AntiAFKMethod = value
			if saveConfigRef then pcall(saveConfigRef) end
		end, "AntiAFKMethod")
		Window:AddSlider(SettingsTab, "Anti-AFK interval (s)", "Seconds between nudges", 15, 120, 30, function(value)
			state.AntiAFKInterval = value
		end, "AntiAFKInterval")

		Window:Notify({
			Title = "Game Automation",
			Description = "Loaded",
			Content = "RightShift = minimize. Config: Save/Load via Kairo.",
			Color = Color3.fromRGB(200, 0, 50),
			Delay = 5
		})

		saveConfigRef = saveConfig

		-- Load saved config and apply to state + loops (Kairo may not call callbacks on load)
		pcall(function()
			local _, data = Window:LoadConfig("Default")
			if data and type(data) == "table" then
				applyLoadedConfig(data)
			end
		end)
	end)
	if not ok then
		warn("[GameAutomation] Kairo UI failed to load:", err)
		return nil
	end
	guiCreated = true
	state.ResetName = state.ResetName or "Frost"
	return Window
end

-- ---------------------------------------------------------------------------
-- WalkSpeed: apply on load and when character (re)spawns
-- ---------------------------------------------------------------------------
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	applyWalkSpeed()
end)
if LocalPlayer.Character then applyWalkSpeed() end

-- ---------------------------------------------------------------------------
-- Entry
-- ---------------------------------------------------------------------------
task.defer(function()
	createGui()
end)

print("[GameAutomation] Loaded. Kairo UI — RightShift to minimize.")
