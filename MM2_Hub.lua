--[[
  SkrilyaHub — Murder Mystery 2 (PlaceId 142823291)
  Single-file FluentPlus hub.

  FluentPlus:
    • Default: HttpGet (portable).
    • Set USE_LOCAL_FLUENT = true and FLUENT_LOCAL_PATH if your executor supports readfile().

  Про «телепортировать чужую модельку и убить без подхода»:
  С клиента нельзя надёжно задать CFrame чужого персонажа на сервере — убийства в MM2
  валидируются сервером. Скрипты «подлететь и ударить» двигают только твой HRP.
]]

local USE_LOCAL_FLUENT = false
local FLUENT_LOCAL_PATH = "C:\\Users\\User\\Desktop\\SkrilyaHub\\FluentPlus-main\\Beta.lua"

-- =============================================================================
-- bootstrap
-- =============================================================================
if not game:IsLoaded() then
	game.Loaded:Wait()
end

if game.PlaceId ~= 142823291 then
	warn("[MM2 Hub] Wrong PlaceId — load in Murder Mystery 2 only.")
	return
end

local function loadLuaSource(isLocal, pathOrUrl)
	if isLocal then
		local rf = readfile or (syn and syn.io and syn.io.read) or nil
		if rf then
			return rf(pathOrUrl)
		end
		warn("[MM2 Hub] readfile not available; falling back to HttpGet.")
	end
	return game:HttpGet(pathOrUrl, true)
end

local fluentSource = USE_LOCAL_FLUENT and loadLuaSource(true, FLUENT_LOCAL_PATH)
	or loadLuaSource(false, "https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua")

local Fluent = loadstring(fluentSource)()

local SaveManager = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
	true
))()

local InterfaceManager = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
	true
))()

-- =============================================================================
-- services & remotes
-- =============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Gameplay = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay")
local Remotes = {
	PlayerDataChanged = Gameplay:WaitForChild("PlayerDataChanged"),
	CoinCollected = Gameplay:WaitForChild("CoinCollected"),
	RoundStart = Gameplay:WaitForChild("RoundStart"),
	RoundEndFade = Gameplay:WaitForChild("RoundEndFade"),
}

local state = {
	unloaded = false,
	-- До первого RoundStart не считаем раунд активным (иначе бой/подбор гана в лобби).
	roundActive = false,
	bagFull = false,
	playerData = {},
	coinType = "Coin",
	farmSpeed = 30,
	connections = {},
	espPlayerConns = {},
	activeTween = nil,
	lastInnocentGunGrab = 0,
}

local function track(conn)
	table.insert(state.connections, conn)
	return conn
end

track(Remotes.PlayerDataChanged.OnClientEvent:Connect(function(data)
	if type(data) == "table" then
		state.playerData = data
	end
end))

track(Remotes.RoundStart.OnClientEvent:Connect(function()
	state.roundActive = true
	state.bagFull = false
	state.lastInnocentGunGrab = 0
end))

track(Remotes.RoundEndFade.OnClientEvent:Connect(function()
	state.roundActive = false
end))

-- =============================================================================
-- character
-- =============================================================================
local function getCharacter()
	return LocalPlayer.Character
end

local function getHumanoid()
	local ch = getCharacter()
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function getHRP()
	local ch = getCharacter()
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

-- =============================================================================
-- map / coins / roles
-- =============================================================================
-- Only coins under the active round map (MapID). Scanning any Model with CoinContainer
-- can pick lobby/template maps and teleport you to ~10k studs → server kick "Invalid position".
local function getActiveMapModel()
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("MapID") ~= nil then
			return child
		end
	end
	return nil
end

local function getCoinContainer()
	local map = getActiveMapModel()
	if not map then
		return nil
	end
	return map:FindFirstChild("CoinContainer")
end

-- Реальный раунд на карте: и флаг с сервера, и модель с MapID (в лобби между играми обычно нет карты).
local function isInActiveRoundMap()
	return state.roundActive and getActiveMapModel() ~= nil
end

local MAX_FARM_MOVE_STUDS = 2200
local MAX_UTILITY_TELEPORT_STUDS = 10000
local MAX_INNOCENT_FLEE_STUDS = 12000
-- Бой / подбор пистолета: длинные прыжки к цели (иначе не «долетает» до мардерa/жертвы)
local MAX_COMBAT_APPROACH_STUDS = 20000
local MAX_GUN_DROP_GRAB_STUDS = 20000

local function isFiniteNumber(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e6
end

local function isValidWorldPosition(pos)
	return isFiniteNumber(pos.X) and isFiniteNumber(pos.Y) and isFiniteNumber(pos.Z)
end

local function withinMoveRange(fromPos, toPos, maxStuds)
	if not isValidWorldPosition(fromPos) or not isValidWorldPosition(toPos) then
		return false
	end
	return (toPos - fromPos).Magnitude <= maxStuds
end

local function findMurderer()
	for _, plr in Players:GetPlayers() do
		if plr.Backpack:FindFirstChild("Knife") then
			return plr
		end
	end
	for _, plr in Players:GetPlayers() do
		local ch = plr.Character
		if ch and ch:FindFirstChild("Knife") then
			return plr
		end
	end
	for name, entry in pairs(state.playerData) do
		if type(entry) == "table" and entry.Role == "Murderer" then
			local p = Players:FindFirstChild(name)
			if p then
				return p
			end
		end
	end
	return nil
end

local function findSheriff()
	for _, plr in Players:GetPlayers() do
		if plr.Backpack:FindFirstChild("Gun") then
			return plr
		end
	end
	for _, plr in Players:GetPlayers() do
		local ch = plr.Character
		if ch and ch:FindFirstChild("Gun") then
			return plr
		end
	end
	for name, entry in pairs(state.playerData) do
		if type(entry) == "table" and entry.Role == "Sheriff" then
			local p = Players:FindFirstChild(name)
			if p then
				return p
			end
		end
	end
	return nil
end

local function roleOfPlayer(plr)
	if plr == findMurderer() then
		return "Murderer"
	end
	if plr == findSheriff() then
		return "Sheriff"
	end
	return "Innocent"
end

local function getLocalRole()
	local char = getCharacter()
	local bp = LocalPlayer.Backpack
	if (char and char:FindFirstChild("Knife")) or bp:FindFirstChild("Knife") then
		return "Murderer"
	end
	if (char and char:FindFirstChild("Gun")) or bp:FindFirstChild("Gun") then
		return "Sheriff"
	end
	return "Innocent"
end

local function getMurdererRootPosition()
	local m = findMurderer()
	if not m or m == LocalPlayer then
		return nil
	end
	local ch = m.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

-- Nearest coin; if avoidMurder and murderPos set, prefer coins outside murderAvoidStuds of murderer.
local function findNearestCoin(container, coinId, rootPos, murderPos, murderAvoidStuds, avoidMurder)
	local bestSafe, bestSafeDist = nil, math.huge
	local bestAny, bestAnyDist = nil, math.huge
	for _, v in container:GetChildren() do
		if v:IsA("BasePart") then
			local vis = v:FindFirstChild("CoinVisual")
			local touch = v:FindFirstChild("TouchInterest")
			if vis and touch and v:GetAttribute("CoinID") == coinId then
				if vis:IsA("MeshPart") or vis:IsA("BasePart") then
					local dPlayer = (v.Position - rootPos).Magnitude
					if dPlayer > MAX_FARM_MOVE_STUDS then
						-- ignore far/junk parts (anti invalid position)
					elseif dPlayer < bestAnyDist then
						bestAnyDist = dPlayer
						bestAny = v
					end
					local okMurder = true
					if avoidMurder and murderPos and murderAvoidStuds > 0 then
						local dm = (v.Position - murderPos).Magnitude
						okMurder = dm >= murderAvoidStuds
					end
					if okMurder and dPlayer <= MAX_FARM_MOVE_STUDS and dPlayer < bestSafeDist then
						bestSafeDist = dPlayer
						bestSafe = v
					end
				end
			end
		end
	end
	if bestSafe then
		return bestSafe, bestSafeDist
	end
	if avoidMurder and murderPos then
		return nil, math.huge
	end
	return bestAny, bestAnyDist
end

local function equipTool(toolName)
	local char = getCharacter()
	if not char then
		return nil
	end
	local t = char:FindFirstChild(toolName) or LocalPlayer.Backpack:FindFirstChild(toolName)
	if t and t.Parent == LocalPlayer.Backpack then
		t.Parent = char
	end
	return char:FindFirstChild(toolName)
end

local function stabTowardsTarget(targetChar)
	local knife = equipTool("Knife")
	if not knife then
		return false
	end
	local myRoot = getHRP()
	local theirRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if not myRoot or not theirRoot then
		return false
	end
	local delta = myRoot.Position - theirRoot.Position
	local mag = delta.Magnitude
	if mag < 1e-2 then
		return false
	end
	local targetPos = theirRoot.Position + delta.Unit * 2.2
	if not withinMoveRange(myRoot.Position, targetPos, MAX_COMBAT_APPROACH_STUDS) then
		return false
	end
	myRoot.CFrame = CFrame.new(targetPos, theirRoot.Position)
	local stab = knife:FindFirstChild("Stab")
	if stab and stab:IsA("RemoteEvent") then
		for _ = 1, 3 do
			stab:FireServer("Down")
		end
		return true
	end
	return false
end

local function shootAtMurderer()
	local gun = equipTool("Gun")
	if not gun then
		return false
	end
	local murder = findMurderer()
	if not murder or murder == LocalPlayer then
		return false
	end
	local mch = murder.Character
	local mhum = mch and mch:FindFirstChildOfClass("Humanoid")
	local mroot = mch and mch:FindFirstChild("HumanoidRootPart")
	if not mhum or mhum.Health <= 0 or not mroot then
		return false
	end
	local myRoot = getHRP()
	if myRoot then
		local aimCF = mroot.CFrame * CFrame.new(0, 0, -4)
		if withinMoveRange(myRoot.Position, aimCF.Position, MAX_COMBAT_APPROACH_STUDS) then
			myRoot.CFrame = aimCF
		end
	end
	local chGun = getCharacter()
	gun = (chGun and chGun:FindFirstChild("Gun")) or gun
	if not gun then
		return false
	end
	local knifeLocal = gun:FindFirstChild("KnifeLocal")
	if knifeLocal then
		local createBeam = knifeLocal:FindFirstChild("CreateBeam")
		local rf = createBeam and createBeam:FindFirstChild("RemoteFunction")
		if rf and rf:IsA("RemoteFunction") then
			local pos = mroot.Position
			local anyOk = false
			for _ = 1, 6 do
				local ok = pcall(function()
					rf:InvokeServer(1, pos, "AH2")
				end)
				if ok then
					anyOk = true
				end
				task.wait(0.065)
			end
			return anyOk
		end
	end
	if gun:IsA("Tool") then
		pcall(function()
			gun:Activate()
		end)
	end
	return false
end

-- В игре GunDrop часто Model с Handle / PrimaryPart, а не один BasePart — иначе подбор никогда не срабатывает.
local function findGunDropBasePart()
	local g = workspace:FindFirstChild("GunDrop", true)
	if not g then
		return nil
	end
	if g:IsA("BasePart") then
		return g
	end
	if g:IsA("Model") then
		if g.PrimaryPart then
			return g.PrimaryPart
		end
		local h = g:FindFirstChild("Handle")
		if h and h:IsA("BasePart") then
			return h
		end
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") then
				return d
			end
		end
	end
	return nil
end

local function hasGunEquippedOrPack()
	local ch = getCharacter()
	local bp = LocalPlayer.Backpack
	return (ch and ch:FindFirstChild("Gun")) ~= nil or bp:FindFirstChild("Gun") ~= nil
end

local function tryGrabGunDrop()
	local gunPart = findGunDropBasePart()
	local hrp = getHRP()
	if not gunPart or not hrp then
		return false
	end
	local dest = gunPart.CFrame * CFrame.new(0, 2.2, 0)
	if not withinMoveRange(hrp.Position, dest.Position, MAX_GUN_DROP_GRAB_STUDS) then
		return false
	end
	local back = hrp.CFrame
	for attempt = 1, 4 do
		hrp.CFrame = dest
		task.wait(0.2)
		if hasGunEquippedOrPack() then
			equipTool("Gun")
			return true
		end
		task.wait(0.25)
	end
	hrp.CFrame = back
	return false
end

local function innocentFleeSurvivalSpot()
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local mpos = getMurdererRootPosition()
	local p = hrp.Position
	if mpos then
		local away = p - mpos
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1 then
			p = p + away.Unit * 22
		else
			p = p + Vector3.new(20, 0, 0)
		end
	end
	local map = getActiveMapModel()
	local highY = p.Y + 78
	if map then
		local pivotY = map:GetPivot().Position.Y
		highY = math.clamp(math.max(highY, pivotY + 65), 40, 520)
	else
		highY = math.clamp(highY, 40, 520)
	end
	local target = Vector3.new(p.X, highY, p.Z)
	return CFrame.new(target)
end

local function tryInnocentGrabGunDropThrottled()
	if not isInActiveRoundMap() then
		return
	end
	if hasGunEquippedOrPack() then
		return
	end
	if not findGunDropBasePart() then
		return
	end
	local now = os.clock()
	if now - state.lastInnocentGunGrab < 0.9 then
		return
	end
	state.lastInnocentGunGrab = now
	tryGrabGunDrop()
end

local function runInnocentFullBagSurvival()
	if not isInActiveRoundMap() then
		return
	end
	if hasGunEquippedOrPack() then
		return
	end
	if findGunDropBasePart() then
		tryInnocentGrabGunDropThrottled()
		return
	end
	local hrp = getHRP()
	local mpos = getMurdererRootPosition()
	if hrp and mpos and hrp.Position.Y > mpos.Y + 38 then
		return
	end
	local cf = innocentFleeSurvivalSpot()
	if cf and hrp then
		teleportHRPTo(cf, MAX_INNOCENT_FLEE_STUDS)
	end
end

local function shouldSheriffShoot()
	if not isInActiveRoundMap() then
		return false
	end
	if getLocalRole() ~= "Sheriff" then
		return false
	end
	if state.bagFull then
		return true
	end
	local e = state.playerData[LocalPlayer.Name]
	if type(e) ~= "table" or not e.Role then
		return false
	end
	local r = e.Role
	return r == "Innocent" or r == "Hero"
end

local function nearestEnemyForMurderer()
	local myRoot = getHRP()
	if not myRoot then
		return nil
	end
	local bestPlr, bestDist = nil, math.huge
	for _, plr in Players:GetPlayers() do
		if plr ~= LocalPlayer then
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root then
				local d = (root.Position - myRoot.Position).Magnitude
				if d < bestDist then
					bestDist = d
					bestPlr = plr
				end
			end
		end
	end
	return bestPlr
end

local function cancelFarmTween()
	if state.activeTween then
		state.activeTween:Cancel()
		state.activeTween = nil
	end
end

local function tweenHRPTo(targetCF, duration, maxMoveStuds)
	maxMoveStuds = maxMoveStuds or MAX_FARM_MOVE_STUDS
	local hrp = getHRP()
	if not hrp or duration <= 0 then
		return false
	end
	if not withinMoveRange(hrp.Position, targetCF.Position, maxMoveStuds) then
		return false
	end
	cancelFarmTween()
	local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = targetCF })
	state.activeTween = tw
	tw:Play()
	return true
end

local function teleportHRPTo(targetCF, maxMoveStuds)
	maxMoveStuds = maxMoveStuds or MAX_FARM_MOVE_STUDS
	cancelFarmTween()
	local hrp = getHRP()
	if not hrp then
		return false
	end
	if not withinMoveRange(hrp.Position, targetCF.Position, maxMoveStuds) then
		return false
	end
	hrp.CFrame = targetCF
	return true
end

local function teleportAbove(cf)
	return cf * CFrame.new(0, 3, 0)
end

local function findLobbyCFrame()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	if lobby:IsA("SpawnLocation") then
		return lobby.CFrame
	end
	for _, d in lobby:GetDescendants() do
		if d:IsA("SpawnLocation") then
			return d.CFrame
		end
	end
	return nil
end

-- =============================================================================
-- Fluent UI (Options must exist before ESP / remotes that read toggles)
-- =============================================================================
local Window = Fluent:CreateWindow({
	Title = "SkrilyaHub",
	SubTitle = "Murder Mystery 2",
	TabWidth = 140,
	Size = UDim2.fromOffset(600, 480),
	Acrylic = false,
	Theme = "Dark",
	MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
	Main = Window:AddTab({ Title = "Main", Icon = "circle" }),
	Visual = Window:AddTab({ Title = "Visual", Icon = "eye" }),
	Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
	Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

do
	Tabs.Main:AddSection("Coin farm")

	Tabs.Main:AddDropdown("CoinType", {
		Title = "Coin / token ID",
		Description = "Must match event coin attribute (e.g. SnowToken).",
		Values = { "SnowToken", "Coin", "Candy", "Heart" },
		Default = 1,
	})

	Tabs.Main:AddDropdown("FarmMode", {
		Title = "Farm movement",
		Values = { "Tween", "Teleport" },
		Default = 1,
	})

	Tabs.Main:AddToggle("AutoFarm", {
		Title = "Auto farm coins",
		Description = "Uses CoinContainer on the active map; respects round state.",
		Default = false,
	})

	Tabs.Main:AddSlider("FarmSpeed", {
		Title = "Tween speed divisor",
		Description = "Higher = slower tween (distance / speed).",
		Default = 25,
		Min = 5,
		Max = 80,
		Rounding = 0,
	})

	Tabs.Main:AddToggle("ResetOnFullBag", {
		Title = "Reset when bag full",
		Description = "Sets humanoid health to 0 when selected coin type hits max (respawn).",
		Default = false,
	})

	Tabs.Main:AddSection("Farm safety & combat")

	Tabs.Main:AddToggle("AvoidMurderWhileFarming", {
		Title = "Avoid murderer while farming",
		Description = "Skip coins too close to the murderer (not applied if you are the murderer).",
		Default = true,
	})

	Tabs.Main:AddSlider("MurderAvoidStuds", {
		Title = "Murder avoid radius (studs)",
		Default = 40,
		Min = 12,
		Max = 90,
		Rounding = 0,
	})

	Tabs.Main:AddToggle("AutoCombatAfterFullBag", {
		Title = "After full bag: hunt / survival",
		Description = "Sheriff / hero: shoot murderer (multi beam). Murderer: stab. Innocent: grab GunDrop or flee above map, then shoot if you have gun.",
		Default = true,
	})

	Tabs.Main:AddSection("Misc")

	Tabs.Main:AddButton({
		Title = "Grab dropped gun (once)",
		Description = "Teleport to GunDrop briefly if it exists.",
		Callback = function()
			local part = findGunDropBasePart()
			local hrp = getHRP()
			if part and hrp then
				local dest = part.CFrame * CFrame.new(0, 2, 0)
				if not withinMoveRange(hrp.Position, dest.Position, MAX_GUN_DROP_GRAB_STUDS) then
					return
				end
				local back = hrp.CFrame
				hrp.CFrame = dest
				task.wait(0.45)
				if not hasGunEquippedOrPack() then
					hrp.CFrame = back
				end
			end
		end,
	})
end

do
	Tabs.Visual:AddSection("ESP")

	Tabs.Visual:AddToggle("EspMurder", { Title = "ESP Murderer", Default = false })
	Tabs.Visual:AddToggle("EspSheriff", { Title = "ESP Sheriff", Default = false })
	Tabs.Visual:AddToggle("EspInnocent", { Title = "ESP Innocents", Default = false })
	Tabs.Visual:AddToggle("EspRoleNames", { Title = "Role names (billboard)", Default = false })
	Tabs.Visual:AddToggle("EspGunDrop", { Title = "Highlight dropped gun", Default = false })

	Tabs.Visual:AddSlider("EspFill", {
		Title = "ESP fill transparency",
		Default = 0.75,
		Min = 0.3,
		Max = 0.95,
		Rounding = 2,
	})
end

do
	Tabs.Teleport:AddSection("Locations")

	Tabs.Teleport:AddButton({
		Title = "Teleport to lobby spawns",
		Callback = function()
			local cf = findLobbyCFrame()
			if cf then
				teleportHRPTo(cf * CFrame.new(0, 5, 0), MAX_UTILITY_TELEPORT_STUDS)
			else
				Fluent:Notify({ Title = "Teleport", Content = "Lobby / SpawnLocation not found.", Duration = 4 })
			end
		end,
	})

	Tabs.Teleport:AddButton({
		Title = "Teleport to nearest coin (now)",
		Callback = function()
			local cc = getCoinContainer()
			local hrp = getHRP()
			if not cc or not hrp then
				return
			end
			local role = getLocalRole()
			local avoidMurder = Options.AvoidMurderWhileFarming.Value and role ~= "Murderer"
			local mPos = avoidMurder and getMurdererRootPosition() or nil
			local coin = select(
				1,
				findNearestCoin(cc, state.coinType, hrp.Position, mPos, Options.MurderAvoidStuds.Value, avoidMurder)
			)
			if coin then
				teleportHRPTo(teleportAbove(coin.CFrame), MAX_FARM_MOVE_STUDS)
			end
		end,
	})

	Tabs.Teleport:AddDropdown("TpPlayer", {
		Title = "Teleport to player",
		Values = { "(none)" },
		Default = 1,
	})

	Tabs.Teleport:AddButton({
		Title = "Go to selected player",
		Callback = function()
			local name = Options.TpPlayer.Value
			if type(name) ~= "string" or name == "" or name == "(none)" then
				return
			end
			local plr = Players:FindFirstChild(name)
			local hrp = getHRP()
			if not plr or not hrp then
				return
			end
			local ch = plr.Character
			local th = ch and ch:FindFirstChild("HumanoidRootPart")
			if th then
				teleportHRPTo(th.CFrame * CFrame.new(0, 3, 0), MAX_UTILITY_TELEPORT_STUDS)
			end
		end,
	})
end

local THEME_NAMES = {
	"Dark",
	"Darker",
	"AMOLED",
	"Light",
	"Balloon",
	"SoftCream",
	"Aqua",
	"Amethyst",
	"Rose",
	"Midnight",
	"Forest",
	"Sunset",
	"Ocean",
	"Emerald",
	"Sapphire",
	"Cloud",
	"Grape",
	"Bloody",
}

do
	Tabs.Settings:AddSection("QoL")

	Tabs.Settings:AddToggle("AntiAfk", { Title = "Anti AFK", Default = true })

	Tabs.Settings:AddButton({
		Title = "Copy JobId",
		Callback = function()
			if setclipboard then
				setclipboard(game.JobId)
				Fluent:Notify({ Title = "Clipboard", Content = "JobId copied.", Duration = 3 })
			else
				Fluent:Notify({ Title = "Clipboard", Content = "setclipboard not available.", Duration = 3 })
			end
		end,
	})

	Tabs.Settings:AddDropdown("UiTheme", {
		Title = "Fluent theme",
		Values = THEME_NAMES,
		Default = 1,
	})

	Options.UiTheme:OnChanged(function()
		pcall(function()
			Fluent:SetTheme(Options.UiTheme.Value)
		end)
	end)

	Tabs.Settings:AddButton({
		Title = "Unload script",
		Description = "Disconnects loops and destroys UI.",
		Callback = function()
			if state.unloaded then
				return
			end
			state.unloaded = true
			cancelFarmTween()
			for _, c in state.connections do
				pcall(function()
					c:Disconnect()
				end)
			end
			state.connections = {}
			for plr, c in pairs(state.espPlayerConns) do
				pcall(function()
					c:Disconnect()
				end)
				state.espPlayerConns[plr] = nil
			end
			for _, plr in Players:GetPlayers() do
				local ch = plr.Character
				if ch then
					local h = ch:FindFirstChild("MM2Hub_ESP")
					if h then
						h:Destroy()
					end
					local head = ch:FindFirstChild("Head")
					if head then
						local b = head:FindFirstChild("MM2Hub_RoleBillboard")
						if b then
							b:Destroy()
						end
					end
				end
			end
			for _, d in workspace:GetDescendants() do
				if d.Name == "MM2Hub_GunHL" and d:IsA("Highlight") then
					d:Destroy()
				end
			end
			pcall(function()
				Fluent:Destroy()
			end)
		end,
	})
end

local function refreshPlayerDropdown()
	pcall(function()
		local names = {}
		for _, plr in Players:GetPlayers() do
			if plr ~= LocalPlayer then
				table.insert(names, plr.Name)
			end
		end
		if #names == 0 then
			table.insert(names, "(none)")
		end
		local dd = Options.TpPlayer
		if dd and type(dd.SetValues) == "function" then
			dd:SetValues(names)
		end
		if dd and type(dd.SetValue) == "function" and names[1] then
			dd:SetValue(names[1])
		end
	end)
end

refreshPlayerDropdown()

-- =============================================================================
-- ESP (after Options)
-- =============================================================================
local ESP_HIGHLIGHT = "MM2Hub_ESP"
local ESP_BILLBOARD = "MM2Hub_RoleBillboard"
local ESP_GUN = "MM2Hub_GunHL"

local function destroyRoleBillboard(char)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local b = head:FindFirstChild(ESP_BILLBOARD)
	if b then
		b:Destroy()
	end
end

local function updateRoleBillboard(char, role, enabled)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	if not enabled then
		destroyRoleBillboard(char)
		return
	end
	local gui = head:FindFirstChild(ESP_BILLBOARD)
	local tl
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = ESP_BILLBOARD
		gui.Size = UDim2.new(0, 120, 0, 32)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = head
		gui.Parent = head
		tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.TextScaled = true
		tl.Font = Enum.Font.SourceSansBold
		tl.TextStrokeTransparency = 0.4
		tl.Parent = gui
	else
		tl = gui:FindFirstChildOfClass("TextLabel")
	end
	if tl then
		if role == "Murderer" then
			tl.TextColor3 = Color3.fromRGB(255, 60, 60)
		elseif role == "Sheriff" then
			tl.TextColor3 = Color3.fromRGB(80, 170, 255)
		else
			tl.TextColor3 = Color3.fromRGB(120, 255, 120)
		end
		if tl.Text ~= role then
			tl.Text = role
		end
	end
end

local function ensureHighlight(char, color, show)
	local h = char:FindFirstChild(ESP_HIGHLIGHT)
	if not show then
		if h then
			h:Destroy()
		end
		return
	end
	if not h then
		h = Instance.new("Highlight")
		h.Name = ESP_HIGHLIGHT
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = char
	end
	local ft = Options.EspFill.Value
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = ft
	h.OutlineTransparency = math.clamp(ft + 0.1, 0, 1)
end

local function clearAllEsp()
	for _, plr in Players:GetPlayers() do
		local ch = plr.Character
		if ch then
			local h = ch:FindFirstChild(ESP_HIGHLIGHT)
			if h then
				h:Destroy()
			end
			destroyRoleBillboard(ch)
		end
	end
	for _, d in workspace:GetDescendants() do
		if d.Name == ESP_GUN and d:IsA("Highlight") then
			d:Destroy()
		end
	end
end

local function espShouldShowFor(plr)
	local murder = findMurderer()
	local sheriff = findSheriff()
	local isMurder = plr == murder
	local isSheriff = plr == sheriff
	local innocent = not isMurder and not isSheriff

	if isMurder and Options.EspMurder.Value then
		return true, Color3.fromRGB(255, 50, 50), "Murderer"
	end
	if isSheriff and Options.EspSheriff.Value then
		return true, Color3.fromRGB(60, 150, 255), "Sheriff"
	end
	if innocent and Options.EspInnocent.Value then
		return true, Color3.fromRGB(80, 255, 120), "Innocent"
	end
	return false, nil, roleOfPlayer(plr)
end

local espAcc = 0
local ESP_INTERVAL = 0.12

local function refreshEspStep(dt)
	if state.unloaded then
		return
	end
	espAcc = espAcc + dt
	if espAcc < ESP_INTERVAL then
		return
	end
	espAcc = 0

	local anyEsp = Options.EspMurder.Value
		or Options.EspSheriff.Value
		or Options.EspInnocent.Value
		or Options.EspRoleNames.Value
		or Options.EspGunDrop.Value

	if not anyEsp then
		clearAllEsp()
		return
	end

	for _, plr in Players:GetPlayers() do
		if plr ~= LocalPlayer then
			local ch = plr.Character
			if ch then
				local show, color, role = espShouldShowFor(plr)
				if color then
					ensureHighlight(ch, color, true)
				else
					ensureHighlight(ch, Color3.new(), false)
				end
				updateRoleBillboard(ch, role, Options.EspRoleNames.Value)
			end
		end
	end

	if Options.EspGunDrop.Value then
		local part = findGunDropBasePart()
		if part then
			local hl = part:FindFirstChild(ESP_GUN)
			if not hl then
				hl = Instance.new("Highlight")
				hl.Name = ESP_GUN
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.FillColor = Color3.fromRGB(255, 255, 100)
				hl.OutlineColor = Color3.fromRGB(255, 200, 0)
				hl.FillTransparency = 0.45
				hl.Parent = part
			end
		end
	else
		for _, d in workspace:GetDescendants() do
			if d.Name == ESP_GUN and d:IsA("Highlight") then
				d:Destroy()
			end
		end
	end
end

local function hookEspPlayer(plr)
	if state.espPlayerConns[plr] then
		return
	end
	state.espPlayerConns[plr] = plr.CharacterAdded:Connect(function()
		task.wait(0.15)
		espAcc = ESP_INTERVAL
	end)
end

for _, plr in Players:GetPlayers() do
	hookEspPlayer(plr)
end

track(Players.PlayerAdded:Connect(function(plr)
	hookEspPlayer(plr)
	refreshPlayerDropdown()
end))

track(Players.PlayerRemoving:Connect(function(plr)
	local c = state.espPlayerConns[plr]
	if c then
		c:Disconnect()
		state.espPlayerConns[plr] = nil
	end
end))

track(RunService.Heartbeat:Connect(function(dt)
	refreshEspStep(dt)
end))

track(LocalPlayer.Idled:Connect(function()
	if Options.AntiAfk.Value and not state.unloaded then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.zero)
		end)
	end
end))

-- =============================================================================
-- CoinCollected: bag full + optional reset (single handler)
-- =============================================================================
track(Remotes.CoinCollected.OnClientEvent:Connect(function(coinType, current, max)
	local cur, mx = tonumber(current), tonumber(max)
	if coinType == state.coinType and cur and mx then
		state.bagFull = cur >= mx
	end
	if Options.ResetOnFullBag.Value and coinType == state.coinType and cur and mx and cur >= mx then
		local hum = getHumanoid()
		if hum then
			hum.Health = 0
		end
	end
end))

-- =============================================================================
-- Save / interface managers
-- =============================================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("SkrilyaHub")
SaveManager:SetFolder("SkrilyaHub/MM2")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- =============================================================================
-- options sync
-- =============================================================================
Options.CoinType:OnChanged(function()
	state.coinType = Options.CoinType.Value
end)
state.coinType = Options.CoinType.Value

Options.FarmSpeed:OnChanged(function(v)
	state.farmSpeed = math.max(1, v)
end)
state.farmSpeed = Options.FarmSpeed.Value

track(Players.PlayerRemoving:Connect(refreshPlayerDropdown))

-- =============================================================================
-- farm loop
-- =============================================================================
task.spawn(function()
	while not state.unloaded do
		task.wait()
		if not Options.AutoFarm.Value or not state.roundActive or state.bagFull then
			-- wait
		else
			local cc = getCoinContainer()
			local hrp = getHRP()
			if cc and hrp then
				local role = getLocalRole()
				local avoidMurder = Options.AvoidMurderWhileFarming.Value and role ~= "Murderer"
				local mPos = avoidMurder and getMurdererRootPosition() or nil
				local coin, dist = findNearestCoin(
					cc,
					state.coinType,
					hrp.Position,
					mPos,
					Options.MurderAvoidStuds.Value,
					avoidMurder
				)
				if coin then
					local target = teleportAbove(coin.CFrame)
					if Options.FarmMode.Value == "Teleport" then
						if teleportHRPTo(target, MAX_FARM_MOVE_STUDS) then
							local start = os.clock()
							while coin.Parent and coin:FindFirstChild("TouchInterest") and not state.unloaded do
								if os.clock() - start > 5 then
									break
								end
								task.wait()
							end
						else
							task.wait(0.25)
						end
					else
						local dur = math.clamp(dist / state.farmSpeed, 0.08, 12)
						if tweenHRPTo(target, dur, MAX_FARM_MOVE_STUDS) then
							local start = os.clock()
							while coin.Parent and coin:FindFirstChild("TouchInterest") and not state.unloaded do
								if os.clock() - start > 15 then
									break
								end
								task.wait()
							end
							cancelFarmTween()
						else
							task.wait(0.25)
						end
					end
				end
			end
		end
	end
end)

-- =============================================================================
-- Combat: невинный подбирает GunDrop без ожидания полного мешка; шериф/герой стреляют;
-- мардер режет при полном мешке; невинный с полным мешком — убежать, если нет дропа.
-- =============================================================================
task.spawn(function()
	while not state.unloaded do
		task.wait(0.34)
		if not Options.AutoCombatAfterFullBag.Value or not isInActiveRoundMap() then
			-- idle (лобби / конец раунда / карта ещё не загружена)
		else
			local hum = getHumanoid()
			if hum and hum.Health > 0 then
				local role = getLocalRole()
				if role == "Innocent" then
					tryInnocentGrabGunDropThrottled()
				end
				if shouldSheriffShoot() then
					shootAtMurderer()
				elseif role == "Murderer" and state.bagFull then
					local victim = nearestEnemyForMurderer()
					if victim and victim.Character then
						stabTowardsTarget(victim.Character)
					end
				elseif role == "Innocent" and state.bagFull then
					runInnocentFullBagSurvival()
				end
			end
		end
	end
end)

Window:SelectTab(1)

Fluent:Notify({
	Title = "SkrilyaHub MM2",
	Content = "Loaded. Configure Save in Settings if needed.",
	Duration = 6,
})

SaveManager:LoadAutoloadConfig()
