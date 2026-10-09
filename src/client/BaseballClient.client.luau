--[[
	BaseballClient  (LocalScript in StarterPlayer > StarterPlayerScripts)
	Warren's Home Run Derby, version 5.
	Draws the balls, swings the bat (full body: stride, hip turn, back-foot pivot, two hands
	on the bat), runs the camera, the shop, the baseball counter, the ROBO-PITCHER arm,
	the outfielders (run, catch, dive, throw), the crowd, and the HOMERUNNNN show.
	Knows if you're on a computer, a phone/tablet, or a console and sets the controls to match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local Debris = game:GetService("Debris")

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
-- A swing animation from the Toolbox (0 = use the built-in swing).
-- How: Toolbox > search "baseball swing" > insert one > click it > copy the number
-- from AnimationId (rbxassetid://THIS_NUMBER) and put it here. It has to be an R15 animation.
local SWING_ANIMATION_ID = 0
-- Sound IDs from the Toolbox (0 = no sound)
local HOMER_SOUND_ID = 0   -- plays on every home run
local HIT_SOUND_ID = 0     -- the crack of the bat
local CROWD_SOUND_ID = 0   -- the crowd cheering
-- Whoosh when you swing ("" = no whoosh). If Output ever says this sound failed, set it to "".
local SWING_SOUND = "rbxasset://sounds/swordslash.wav"
local SHOW_STRIKE_ZONE = true   -- glowing box at the plate while you bat
local SHOW_TIMING_METER = true  -- the bar at the bottom that shows when to swing
---------------------------------------------------------------------

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Baseball")
local PitchEvent = remotes:WaitForChild("Pitch")
local SwingEvent = remotes:WaitForChild("Swing")
local ResultEvent = remotes:WaitForChild("Result")
local LeaveEvent = remotes:WaitForChild("Leave")
local ShopFunction = remotes:WaitForChild("Shop")
local baseballsValue = player:WaitForChild("leaderstats"):WaitForChild("Baseballs")

local function waitForAttribute(name)
	local value = remotes:GetAttribute(name)
	while value == nil do
		remotes.AttributeChanged:Wait()
		value = remotes:GetAttribute(name)
	end
	return value
end

local HOME = waitForAttribute("Home")
local MOUND = waitForAttribute("Mound")
local FENCE_DIST = waitForAttribute("FenceCenter")
local SWING_WINDOW = waitForAttribute("SwingWindow")
local PITCH_LEAD = waitForAttribute("PitchLead")
-- Camera spot behind home plate, looking out at the pitching machine
local BAT_SPOT = HOME + Vector3.new(2, 6.5, 15)
local BAT_LOOK = MOUND + Vector3.new(0, 4, 0)

-- Ask the server what's in the shop
local catalog = {}
for _ = 1, 5 do
	local ok, result = pcall(function()
		return ShopFunction:InvokeServer("catalog")
	end)
	if ok and type(result) == "table" then
		catalog = result
		break
	end
	task.wait(1)
end
local ITEMS = {}
for _, item in catalog do
	ITEMS[item.id] = item
end

---------------------------------------------------------------------
-- The swing lives in its own ModuleScript: ReplicatedStorage > SwingAnimation
---------------------------------------------------------------------
local Swing: any = nil
do
	-- Looks for a ModuleScript named SwingAnimation (and notices one that's the wrong kind of script)
	local function findSwingModule()
		local wrongKind = nil
		for _, obj in ReplicatedStorage:GetDescendants() do
			if obj.Name == "SwingAnimation" then
				if obj:IsA("ModuleScript") then
					return obj, nil
				end
				wrongKind = wrongKind or obj
			end
		end
		return nil, wrongKind
	end
	local started = os.clock()
	local module, wrongKind = findSwingModule()
	while not module and os.clock() - started < 5 do
		task.wait(0.25)
		module, wrongKind = findSwingModule()
	end
	if module then
		local ok, result = pcall(require, module)
		-- Make sure nothing important got deleted while changing the poses
		local good = ok and type(result) == "table" and type(result.STANCE) == "table"
			and type(result.SWING_KEYS) == "table" and type(result.PREP_KEYS) == "table"
			and type(result.SWING_TIME) == "number" and type(result.HAND_SPREAD) == "number"
		if good then
			for _, name in { "apply", "sample", "blend", "measure", "reset" } do
				if type(result[name]) ~= "function" then
					good = false
				end
			end
		end
		if good then
			Swing = result
		elseif not ok then
			warn("[Baseball] The SwingAnimation script has an error: " .. tostring(result) .. ". The batter will just hold the bat.")
		else
			warn("[Baseball] The SwingAnimation script is missing something (did a line get deleted?). The batter will just hold the bat.")
		end
	elseif wrongKind then
		warn(string.format("[Baseball] SwingAnimation is a %s, but it has to be a ModuleScript. In ReplicatedStorage click + > ModuleScript, "
			.. "name it SwingAnimation, paste Script 3 into it, and delete the %s.", wrongKind.ClassName, wrongKind.ClassName))
	else
		warn("[Baseball] Can't find the SwingAnimation ModuleScript in ReplicatedStorage (is it named exactly SwingAnimation?). "
			.. "The batter will hold the bat but won't swing. Add Script 3 to fix it.")
	end
end
local SWING_TIME = (Swing and tonumber(Swing.SWING_TIME)) or 0.95
local HAND_SPREAD = (Swing and tonumber(Swing.HAND_SPREAD)) or 0.3

---------------------------------------------------------------------
-- Computer, phone/tablet, or console?
---------------------------------------------------------------------
local mode = "computer"
local MODE_INFO = {
	computer = { badge = "COMPUTER", color = Color3.fromRGB(60, 140, 255) },
	mobile = { badge = "MOBILE", color = Color3.fromRGB(60, 190, 90) },
	console = { badge = "CONSOLE", color = Color3.fromRGB(170, 90, 255) },
}

-- What kind of device has these buttons?
local function modeFromDevice()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "mobile"
	end
	if (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled) or GuiService:IsTenFootInterface() then
		return "console"
	end
	return "computer"
end

-- What did the player just touch? (nil = doesn't tell us anything)
local function modeFromInput(inputType)
	if inputType == Enum.UserInputType.Touch then
		return "mobile"
	elseif string.find(inputType.Name, "Gamepad") then
		return "console"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "computer"
	end
	return nil
end

---------------------------------------------------------------------
-- Screen helpers
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BaseballGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- stay out of the Roblox buttons and phone notches
end)
gui.Parent = player:WaitForChild("PlayerGui")

-- Everything sits in one frame that shrinks on small screens and grows on big ones
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.new(0.5, 0, 0.5, 0)
root.Size = UDim2.new(1, 0, 1, 0)
root.BackgroundTransparency = 1
root.Active = false
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function updateScale()
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.3)
	uiScale.Scale = s
	root.Size = UDim2.new(1 / s, 0, 1 / s, 0)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

local GREEN = Color3.fromRGB(60, 170, 80)
local BLUE = Color3.fromRGB(50, 120, 220)
local GRAY = Color3.fromRGB(90, 95, 110)
local RED = Color3.fromRGB(200, 60, 60)
local GOLD = Color3.fromRGB(255, 215, 0)
local PANEL = Color3.fromRGB(20, 25, 40)

local function addCorner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = obj
	return c
end

local function addStroke(obj, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Parent = obj
	return s
end

local function makeLabel(parent, name, size, position, font, maxTextSize)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = ""
	addStroke(l, 3)
	if maxTextSize then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = maxTextSize
		limit.Parent = l
	end
	l.Parent = parent
	return l
end

local function makeButton(parent, name, text, size, position, color)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.LuckiestGuy
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	addCorner(b)
	addStroke(b, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	b.Parent = parent
	return b
end

local fades = {} -- [label] = the fade-out tweens still running on it

local function fadeOut(label, seconds)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local info = TweenInfo.new(seconds)
	local tweens = { TweenService:Create(label, info, { TextTransparency = 1 }) }
	if stroke then
		table.insert(tweens, TweenService:Create(stroke, info, { Transparency = 1 }))
	end
	fades[label] = tweens
	tweens[1].Completed:Connect(function()
		if fades[label] == tweens then
			fades[label] = nil
		end
	end)
	for _, tween in tweens do
		tween:Play()
	end
end

local function fadeIn(label)
	-- Stop a fade-out that's still going, or it would hide the new text
	local tweens = fades[label]
	if tweens then
		fades[label] = nil
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
end

local function playSound(id, volume)
	if id == 0 or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = if type(id) == "number" then "rbxassetid://" .. id else id
	sound.Volume = volume or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 12)
end

---------------------------------------------------------------------
-- Screen: status, messages, and the big HOMERUN text
---------------------------------------------------------------------
local statusLabel = makeLabel(root, "Status", UDim2.new(0.6, 0, 0, 34), UDim2.new(0.5, 0, 0, 26), nil, 30)
local pitchLabel = makeLabel(root, "Pitch", UDim2.new(0.45, 0, 0, 28), UDim2.new(0.5, 0, 0, 60), nil, 26)
pitchLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
local messageLabel = makeLabel(root, "Message", UDim2.new(0.6, 0, 0, 52), UDim2.new(0.5, 0, 0.22, 0), nil, 44)
local statsLabel = makeLabel(root, "HitStats", UDim2.new(0.6, 0, 0, 30), UDim2.new(0.5, 0, 0.22, 46), Enum.Font.GothamBold, 26)
statsLabel.TextColor3 = Color3.fromRGB(150, 230, 255)

local homerLabel = makeLabel(root, "Homer", UDim2.new(0.95, 0, 0.22, 0), UDim2.new(0.5, 0, 0.42, 0), Enum.Font.LuckiestGuy)
homerLabel.Visible = false
homerLabel:FindFirstChildOfClass("UIStroke").Thickness = 6
local homerScale = Instance.new("UIScale")
homerScale.Parent = homerLabel
local homerSub = makeLabel(root, "HomerSub", UDim2.new(0.75, 0, 0.07, 0), UDim2.new(0.5, 0, 0.56, 0))
homerSub.Visible = false
local homerExtra = makeLabel(root, "HomerExtra", UDim2.new(0.6, 0, 0.055, 0), UDim2.new(0.5, 0, 0.63, 0), Enum.Font.LuckiestGuy)
homerExtra.Visible = false
homerExtra.TextColor3 = GOLD

local messageToken = 0
local function showMessage(text, color)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color
	fadeIn(messageLabel)
	task.delay(2.2, function()
		if token == messageToken then
			fadeOut(messageLabel, 0.4)
		end
	end)
end

local statsToken = 0
local function showStats(text)
	statsToken += 1
	local token = statsToken
	statsLabel.Text = text
	fadeIn(statsLabel)
	task.delay(3.2, function()
		if token == statsToken then
			fadeOut(statsLabel, 0.5)
		end
	end)
end

-- Which device you're on, top right
local modeBadge = Instance.new("TextLabel")
modeBadge.Name = "ModeBadge"
modeBadge.AnchorPoint = Vector2.new(0.5, 0)
modeBadge.Position = UDim2.new(0.5, 0, 0, 80)
modeBadge.Size = UDim2.new(0, 130, 0, 28)
modeBadge.Font = Enum.Font.GothamBold
modeBadge.TextScaled = true
modeBadge.TextColor3 = Color3.new(1, 1, 1)
modeBadge.BackgroundTransparency = 0.15
addCorner(modeBadge, UDim.new(1, 0))
do -- (setup-only pieces go inside do...end so they don't use up the script's 200 local variables)
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingTop = UDim.new(0, 5)
	badgePad.PaddingBottom = UDim.new(0, 5)
	badgePad.PaddingLeft = UDim.new(0, 10)
	badgePad.PaddingRight = UDim.new(0, 10)
	badgePad.Parent = modeBadge
end
modeBadge.Parent = root

-- Controls help at the bottom
local hintLabel = makeLabel(root, "Hint", UDim2.new(0.8, 0, 0, 24), UDim2.new(0.5, 0, 1, -22), Enum.Font.GothamBold, 22)
hintLabel.TextColor3 = Color3.fromRGB(230, 230, 230)

---------------------------------------------------------------------
-- Screen: baseball counter (left side)
---------------------------------------------------------------------
local counter = Instance.new("Frame")
counter.Name = "BaseballCounter"
counter.Size = UDim2.new(0, 180, 0, 48)
counter.Position = UDim2.new(0, 16, 0.3, 0)
counter.BackgroundColor3 = PANEL
counter.BackgroundTransparency = 0.2
addCorner(counter)
counter.Parent = root
local counterScale = Instance.new("UIScale")
counterScale.Parent = counter

do
	local ballIcon = Instance.new("Frame")
	ballIcon.AnchorPoint = Vector2.new(0, 0.5)
	ballIcon.Size = UDim2.new(0, 32, 0, 32)
	ballIcon.Position = UDim2.new(0, 8, 0.5, 0)
	ballIcon.BackgroundColor3 = Color3.fromRGB(250, 250, 245)
	addCorner(ballIcon, UDim.new(1, 0))
	local stitches = addStroke(ballIcon, 3)
	stitches.Color = Color3.fromRGB(220, 40, 40)
	ballIcon.Parent = counter
end

local countLabel = makeLabel(counter, "Count", UDim2.new(1, -58, 0.75, 0), UDim2.new(0, 50, 0.5, 0), Enum.Font.LuckiestGuy, 32)
countLabel.AnchorPoint = Vector2.new(0, 0.5)
countLabel.TextXAlignment = Enum.TextXAlignment.Left

local function refreshCount()
	countLabel.Text = tostring(baseballsValue.Value)
end
refreshCount()

local function showEarned(amount, lucky, golden)
	local pop = makeLabel(root, "Earned", UDim2.new(0, 260, 0, 36), UDim2.new(0, 330, 0.3, 24), Enum.Font.LuckiestGuy)
	pop.Text = "+" .. amount .. (if golden then "  GOLDEN!" else "") .. (if lucky then "  LUCKY x2!" else "")
	pop.TextColor3 = (lucky or golden) and GOLD or Color3.new(1, 1, 1)
	TweenService:Create(pop, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 330, 0.3, -30) }):Play()
	task.delay(0.6, fadeOut, pop, 0.8)
	Debris:AddItem(pop, 1.6)

	counterScale.Scale = (lucky or golden) and 1.4 or 1.2
	TweenService:Create(counterScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------------
-- Screen: buttons (they work with mouse, touch, and controllers)
---------------------------------------------------------------------
local shopButton = makeButton(root, "ShopButton", "SHOP", UDim2.new(0, 180, 0, 52), UDim2.new(0, 16, 0.3, 58), GREEN)
local leaveButton = makeButton(root, "LeaveButton", "LEAVE BOX", UDim2.new(0, 180, 0, 44), UDim2.new(0, 16, 0.3, 120), GRAY)
leaveButton.Visible = false

local swingButton = makeButton(root, "SwingButton", "SWING", UDim2.new(0, 210, 0, 210), UDim2.new(1, -30, 1, -30), RED)
swingButton.AnchorPoint = Vector2.new(1, 1)
swingButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
swingButton.Visible = false

---------------------------------------------------------------------
-- Screen: the timing meter (when to swing)
---------------------------------------------------------------------
local METER_EARLY = 0.7 -- the meter starts this many seconds before the ball reaches the plate
local METER_LATE = 0.3  -- ...and ends this long after
local meter = Instance.new("Frame")
meter.Name = "TimingMeter"
meter.AnchorPoint = Vector2.new(0.5, 1)
meter.Position = UDim2.new(0.5, 0, 1, -52)
meter.Size = UDim2.new(0, 440, 0, 26)
meter.BackgroundColor3 = PANEL
meter.BackgroundTransparency = 0.15
meter.Visible = false
addCorner(meter, UDim.new(1, 0))
addStroke(meter, 2).Color = Color3.fromRGB(255, 255, 255)
meter.Parent = root

local function meterX(secondsFromPlate)
	return math.clamp((secondsFromPlate + METER_EARLY) / (METER_EARLY + METER_LATE), 0, 1)
end

local hitZone = Instance.new("Frame")
hitZone.AnchorPoint = Vector2.new(0.5, 0.5)
hitZone.Position = UDim2.new(meterX(0), 0, 0.5, 0)
hitZone.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
hitZone.BackgroundTransparency = 0.25
hitZone.BorderSizePixel = 0
addCorner(hitZone, UDim.new(1, 0))
hitZone.Parent = meter
local perfectZone = Instance.new("Frame")
perfectZone.AnchorPoint = Vector2.new(0.5, 0.5)
perfectZone.Position = UDim2.new(meterX(0), 0, 0.5, 0)
perfectZone.BackgroundColor3 = GOLD
perfectZone.BorderSizePixel = 0
perfectZone.Parent = meter
local meterBall = Instance.new("Frame")
meterBall.AnchorPoint = Vector2.new(0.5, 0.5)
meterBall.Size = UDim2.new(0, 22, 0, 22)
meterBall.Position = UDim2.new(0, 0, 0.5, 0)
meterBall.BackgroundColor3 = Color3.new(1, 1, 1)
meterBall.Visible = false
addCorner(meterBall, UDim.new(1, 0))
addStroke(meterBall, 2).Color = Color3.fromRGB(220, 40, 40)
meterBall.Parent = meter
local swingTick = Instance.new("Frame")
swingTick.AnchorPoint = Vector2.new(0.5, 0.5)
swingTick.Size = UDim2.new(0, 5, 1, 12)
swingTick.BorderSizePixel = 0
swingTick.Visible = false
swingTick.Parent = meter
local meterLabel = makeLabel(meter, "MeterLabel", UDim2.new(0, 160, 0, 22), UDim2.new(0.5, 0, 0, -16), Enum.Font.LuckiestGuy, 20)

local function batTiming()
	local item = ITEMS[player:GetAttribute("EquippedBat") or "wood"]
	return item and item.timing or 1
end

local function refreshMeterZones()
	local window = SWING_WINDOW * batTiming()
	local span = METER_EARLY + METER_LATE
	hitZone.Size = UDim2.new(2 * window / span, 0, 1, -6)
	perfectZone.Size = UDim2.new(math.max(2 * 0.1 * window / span, 0.012), 0, 1, -6)
end
refreshMeterZones()

---------------------------------------------------------------------
-- Screen: round summary
---------------------------------------------------------------------
local roundPanel = Instance.new("Frame")
roundPanel.Name = "RoundSummary"
roundPanel.AnchorPoint = Vector2.new(0.5, 0.5)
roundPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
roundPanel.Size = UDim2.new(0, 460, 0, 250)
roundPanel.BackgroundColor3 = PANEL
roundPanel.BackgroundTransparency = 0.05
roundPanel.Visible = false
addCorner(roundPanel, UDim.new(0, 18))
addStroke(roundPanel, 3).Color = GOLD
roundPanel.Parent = root
do
	local roundTitle = makeLabel(roundPanel, "Title", UDim2.new(0.9, 0, 0, 50), UDim2.new(0.5, 0, 0, 40), Enum.Font.LuckiestGuy)
	roundTitle.Text = "ROUND OVER!"
	roundTitle.TextColor3 = GOLD
end
local roundLines = {}
for i = 1, 3 do
	roundLines[i] = makeLabel(roundPanel, "Line" .. i, UDim2.new(0.85, 0, 0, 34), UDim2.new(0.5, 0, 0, 85 + i * 42), Enum.Font.FredokaOne)
end
local roundScale = Instance.new("UIScale")
roundScale.Parent = roundPanel

local roundToken = 0
local function showRoundSummary(info)
	roundToken += 1
	local token = roundToken
	roundLines[1].Text = string.format("HOME RUNS: %d     HITS: %d", info.homers or 0, info.hits or 0)
	roundLines[2].Text = string.format("LONGEST: %s", (info.longest or 0) > 0 and (info.longest .. " FT") or "-")
	roundLines[3].Text = string.format("BASEBALLS: +%d", info.earned or 0)
	roundPanel.Visible = true
	roundScale.Scale = 0.3
	TweenService:Create(roundScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(5, function()
		if token == roundToken then
			roundPanel.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Screen: the shop window
---------------------------------------------------------------------
local shopFrame = Instance.new("Frame")
shopFrame.Name = "Shop"
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
shopFrame.Size = UDim2.new(0.92, 0, 0.82, 0)
shopFrame.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
shopFrame.Visible = false
addCorner(shopFrame, UDim.new(0, 16))
addStroke(shopFrame, 3).Color = Color3.fromRGB(80, 90, 130)
do
	local shopLimit = Instance.new("UISizeConstraint")
	shopLimit.MaxSize = Vector2.new(780, 560)
	shopLimit.Parent = shopFrame
end
shopFrame.Parent = root

do
	local shopTitle = makeLabel(shopFrame, "Title", UDim2.new(0.5, 0, 0, 40), UDim2.new(0, 16, 0, 30), Enum.Font.LuckiestGuy, 40)
	shopTitle.AnchorPoint = Vector2.new(0, 0.5)
	shopTitle.TextXAlignment = Enum.TextXAlignment.Left
	shopTitle.Text = "BAT SHOP"
end

local luckLabel = makeLabel(shopFrame, "Luck", UDim2.new(0.6, 0, 0, 22), UDim2.new(0, 16, 0, 62), nil, 20)
luckLabel.AnchorPoint = Vector2.new(0, 0.5)
luckLabel.TextXAlignment = Enum.TextXAlignment.Left
luckLabel.TextColor3 = GOLD

local closeButton = makeButton(shopFrame, "Close", "X", UDim2.new(0, 44, 0, 44), UDim2.new(1, -10, 0, 10), RED)
closeButton.AnchorPoint = Vector2.new(1, 0)

local list = Instance.new("ScrollingFrame")
list.Name = "Items"
list.Position = UDim2.new(0, 12, 0, 82)
list.Size = UDim2.new(1, -24, 1, -122)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = shopFrame
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 190, 0, 170)
grid.CellPadding = UDim2.new(0, 10, 0, 10)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list

-- How far the shop scrolls. Worked out by hand because Roblox's automatic
-- version gets it wrong when the screen is shrunk for phones.
local function refreshCanvas()
	list.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y / math.max(uiScale.Scale, 0.01) + 12)
end
grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
uiScale:GetPropertyChangedSignal("Scale"):Connect(refreshCanvas)
refreshCanvas()

local toastLabel = makeLabel(shopFrame, "Toast", UDim2.new(1, -24, 0, 26), UDim2.new(0.5, 0, 1, -20), nil, 22)

local toastToken = 0
local function showToast(text, color)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color
	fadeIn(toastLabel)
	task.delay(2.5, function()
		if token == toastToken then
			fadeOut(toastLabel, 0.4)
		end
	end)
end

local function ownedSet()
	local owned = {}
	for id in string.gmatch(player:GetAttribute("Owned") or "", "[^,]+") do
		owned[id] = true
	end
	return owned
end

-- A little bar that shows how good a bat is
local function statBar(card, y, label, amount, color)
	local text = makeLabel(card, label .. "Label", UDim2.new(0, 70, 0, 16), UDim2.new(0, 10, 0, y), Enum.Font.GothamBold, 14)
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = label
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0, 0.5)
	back.Position = UDim2.new(0, 80, 0, y)
	back.Size = UDim2.new(1, -92, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(15, 18, 30)
	addCorner(back, UDim.new(1, 0))
	back.Parent = card
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(math.clamp(amount, 0.04, 1), 0, 1, 0)
	fill.BackgroundColor3 = color
	addCorner(fill, UDim.new(1, 0))
	fill.Parent = back
end

local cardButtons = {}
local firstCardButton = nil

local function refreshShop()
	local owned = ownedSet()
	local equipped = player:GetAttribute("EquippedBat")
	for id, button in cardButtons do
		local item = ITEMS[id]
		if item.kind == "bat" and equipped == id then
			button.Text = "EQUIPPED"
			button.BackgroundColor3 = GRAY
		elseif owned[id] then
			button.Text = item.kind == "bat" and "EQUIP" or "OWNED"
			button.BackgroundColor3 = item.kind == "bat" and BLUE or GRAY
		else
			button.Text = "BUY " .. item.price
			button.BackgroundColor3 = baseballsValue.Value >= item.price and GREEN or RED
		end
	end
	luckLabel.Text = string.format("Your lucky x2 chance: %d%%", math.floor((player:GetAttribute("Luck") or 0.15) * 100 + 0.5))
	refreshMeterZones()
end

local shopBusy = false
local function onCardPressed(item)
	if shopBusy then
		return
	end
	local action
	if not ownedSet()[item.id] then
		action = "buy"
	elseif item.kind == "bat" and player:GetAttribute("EquippedBat") ~= item.id then
		action = "equip"
	else
		return
	end
	shopBusy = true
	local ok, success, msg = pcall(function()
		return ShopFunction:InvokeServer(action, item.id)
	end)
	shopBusy = false
	if not ok then
		showToast("Shop hiccup - try again", RED)
		return
	end
	showToast(msg or "", success and GREEN or RED)
end

for index, item in catalog do
	local card = Instance.new("Frame")
	card.Name = item.id
	card.LayoutOrder = index
	card.BackgroundColor3 = Color3.fromRGB(40, 48, 70)
	addCorner(card)

	local nameLabel = makeLabel(card, "ItemName", UDim2.new(1, -12, 0, 26), UDim2.new(0.5, 0, 0, 20), Enum.Font.LuckiestGuy, 24)
	nameLabel.Text = item.name

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.new(0.5, 0, 0, 50)
	swatch.Size = item.kind == "bat" and UDim2.new(0.8, 0, 0, 14) or UDim2.new(0, 26, 0, 26)
	swatch.BackgroundColor3 = item.color
	addCorner(swatch, UDim.new(1, 0))
	swatch.Parent = card

	if item.kind == "bat" then
		statBar(card, 78, "POWER", (item.power - 0.9) / 0.55, Color3.fromRGB(255, 120, 60))
		statBar(card, 98, "TIMING", (item.timing - 0.9) / 0.45, Color3.fromRGB(90, 200, 255))
	else
		local infoLabel = makeLabel(card, "Info", UDim2.new(1, -12, 0, 38), UDim2.new(0.5, 0, 0, 88), nil, 20)
		infoLabel.Text = string.format("Lucky x2 chance: %d%%", math.floor(item.luck * 100 + 0.5))
	end

	local button = makeButton(card, "Action", "", UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 1, -48), GREEN)
	button.Activated:Connect(function()
		onCardPressed(item)
	end)
	cardButtons[item.id] = button
	if index == 1 then
		firstCardButton = button
	end
	card.Parent = list
end

if #catalog == 0 then
	showToast("The shop couldn't load. Try rejoining.", RED)
end

local function setShopOpen(open)
	shopFrame.Visible = open
	refreshShop()
	if open and mode == "console" and firstCardButton then
		GuiService.SelectedObject = firstCardButton
	elseif not open and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(shopFrame) then
		GuiService.SelectedObject = nil
	end
end

shopButton.Activated:Connect(function()
	setShopOpen(not shopFrame.Visible)
end)
closeButton.Activated:Connect(function()
	setShopOpen(false)
end)

baseballsValue.Changed:Connect(function()
	refreshCount()
	refreshShop()
end)
player.AttributeChanged:Connect(refreshShop)
refreshShop()

---------------------------------------------------------------------
-- The strike zone (only you see it, only while you bat)
---------------------------------------------------------------------
local zoneParts = {}
do
	local zone = Instance.new("Model")
	zone.Name = "StrikeZone"
	local left, right, bottom, top = -1, 1, 2.1, 3.5
	local bars = {
		{ Vector3.new(right - left, 0.06, 0.06), Vector3.new(0, bottom, 0) },
		{ Vector3.new(right - left, 0.06, 0.06), Vector3.new(0, top, 0) },
		{ Vector3.new(0.06, top - bottom, 0.06), Vector3.new(left, (top + bottom) / 2, 0) },
		{ Vector3.new(0.06, top - bottom, 0.06), Vector3.new(right, (top + bottom) / 2, 0) },
	}
	for _, bar in bars do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 255, 255)
		p.Size = bar[1]
		p.CFrame = CFrame.new(HOME + bar[2])
		p.Transparency = 1
		p.Parent = zone
		table.insert(zoneParts, p)
	end
	zone.Parent = workspace
end

local function showStrikeZone(on)
	for _, p in zoneParts do
		p.Transparency = if on and SHOW_STRIKE_ZONE then 0.55 else 1
	end
end

---------------------------------------------------------------------
-- Camera: behind the plate while you bat, follows the ball when you hit it
---------------------------------------------------------------------
local batting = false
local currentPitch = nil -- the pitch you can swing at right now
local followBall = nil
local holdLookPos = nil
local holdLookUntil = 0
local shakeUntil = 0
local camLook = BAT_LOOK
local fadedChars = {} -- [character] = true while we've faded them out of the batting view

local function fadeCharacter(char, amount)
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = amount
		end
	end
end

-- Other players standing between the camera and the plate fade so you can see the pitch
local function fadeBlockers(on)
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if plr ~= player and char then
			local root = char:FindFirstChild("HumanoidRootPart")
			local blocking = on and root ~= nil and math.abs(root.Position.X - HOME.X) < 6
				and root.Position.Z > HOME.Z + 1 and root.Position.Z < BAT_SPOT.Z + 3
			if blocking then
				fadeCharacter(char, 0.8)
				fadedChars[char] = true
			elseif fadedChars[char] then
				fadeCharacter(char, 0)
				fadedChars[char] = nil
			end
		end
	end
end

local function cameraStep(dt)
	local now = os.clock()
	local target = BAT_LOOK
	local following = false
	if followBall and followBall.Parent then
		target = followBall.Position
		following = true
	elseif holdLookPos and now < holdLookUntil then
		target = holdLookPos
		following = true
	end
	camLook = camLook:Lerp(target, math.min(1, dt * (if following then 12 else 4)))
	local distance = (camLook - BAT_SPOT).Magnitude
	local fovGoal = if following then math.clamp(70 - (distance - 50) * 0.12, 32, 70) else 70
	camera.FieldOfView += (fovGoal - camera.FieldOfView) * math.min(1, dt * 3)
	local cf = CFrame.lookAt(BAT_SPOT, camLook)
	if now < shakeUntil then
		cf *= CFrame.Angles((math.random() - 0.5) * 0.03, (math.random() - 0.5) * 0.03, 0)
	end
	camera.CFrame = cf
	camera.Focus = CFrame.new(camLook)
	fadeBlockers(true)
	-- If you were zoomed all the way in, Roblox hid your body. Show it while you bat.
	local char = player.Character
	if char then
		for _, part in char:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
	end
end

local function setTouchControls(on)
	pcall(function()
		GuiService.TouchControlsEnabled = on
	end)
end

-- Shows the right buttons and help for computer / phone / console
local function applyMode()
	local info = MODE_INFO[mode]
	modeBadge.Text = info.badge
	modeBadge.BackgroundColor3 = info.color
	local isMobile = mode == "mobile"
	swingButton.Visible = batting and isMobile
	setTouchControls(not (batting and isMobile))
	if mode == "computer" then
		shopButton.Text = "SHOP [E]"
		leaveButton.Text = "LEAVE [Q]"
		hintLabel.Text = if batting then "CLICK or SPACE = swing  |  Q = leave box  |  E = shop" else "Walk into the glowing box to bat  |  E = shop"
	elseif mode == "console" then
		shopButton.Text = "SHOP (Y)"
		leaveButton.Text = "LEAVE (B)"
		hintLabel.Text = if batting then "R2 or A = swing  |  B = leave box  |  Y = shop" else "Walk into the glowing box to bat  |  Y = shop"
	else
		shopButton.Text = "SHOP"
		leaveButton.Text = "LEAVE BOX"
		hintLabel.Text = if batting then "Tap SWING when the ball reaches the plate!" else "Walk into the glowing box to bat"
	end
	-- Bigger buttons for fingers, smaller cards so the shop fits a phone
	shopButton.Size = if isMobile then UDim2.new(0, 210, 0, 66) else UDim2.new(0, 180, 0, 52)
	leaveButton.Size = if isMobile then UDim2.new(0, 210, 0, 58) else UDim2.new(0, 180, 0, 44)
	leaveButton.Position = if isMobile then UDim2.new(0, 16, 0.3, 134) else UDim2.new(0, 16, 0.3, 120)
	grid.CellSize = if isMobile then UDim2.new(0, 170, 0, 160) else UDim2.new(0, 190, 0, 170)
end

local function setMode(newMode)
	if newMode and newMode ~= mode then
		mode = newMode
		applyMode()
	end
end

mode = modeFromDevice()
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	setMode(modeFromInput(inputType))
end)

local function setBatting(on)
	if on == batting then
		return
	end
	batting = on
	leaveButton.Visible = on
	meter.Visible = on and SHOW_TIMING_METER
	showStrikeZone(on)
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
		camLook = BAT_LOOK
		RunService:BindToRenderStep("BaseballCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)
		local how = if mode == "mobile" then "Tap SWING" elseif mode == "console" then "Press R2" else "Click or press SPACE"
		showMessage(how .. " when the ball reaches the plate!", Color3.new(1, 1, 1))
	else
		RunService:UnbindFromRenderStep("BaseballCamera")
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		currentPitch = nil
		followBall = nil
		holdLookPos = nil
		fadeBlockers(false)
	end
	applyMode()
end

local function refreshHud()
	local batterId = remotes:GetAttribute("BatterUserId") or 0
	local outs = remotes:GetAttribute("Outs") or 0
	local homers = remotes:GetAttribute("Homers") or 0
	local hits = remotes:GetAttribute("Hits") or 0
	local streak = remotes:GetAttribute("Streak") or 0
	local maxOuts = remotes:GetAttribute("MaxOuts") or 10
	local streakText = if streak >= 2 then string.format("   STREAK x%d!", streak) else ""
	if batterId == 0 then
		statusLabel.Text = "HOME RUN DERBY - walk into the glowing box to bat!"
		pitchLabel.Text = ""
	elseif batterId == player.UserId then
		statusLabel.Text = string.format("OUTS %d/%d     HOME RUNS %d     HITS %d%s", outs, maxOuts, homers, hits, streakText)
	else
		statusLabel.Text = string.format("%s is batting - OUTS %d/%d   HOME RUNS %d   HITS %d%s",
			remotes:GetAttribute("BatterName") or "Someone", outs, maxOuts, homers, hits, streakText)
	end
end

remotes.AttributeChanged:Connect(function()
	refreshHud()
	setBatting(remotes:GetAttribute("BatterUserId") == player.UserId)
end)
applyMode()
refreshHud()
setBatting(remotes:GetAttribute("BatterUserId") == player.UserId)

local function leaveBox()
	if batting then
		LeaveEvent:FireServer()
	end
end
leaveButton.Activated:Connect(leaveBox)

---------------------------------------------------------------------
-- The bat (everyone's screen draws it in the batter's hand)
---------------------------------------------------------------------
-- Pieces measured from the knob end of the bat. The right (top) hand holds it TOP_HAND studs up.
local TOP_HAND = 0.45 + HAND_SPREAD
local BAT_PIECES = {
	{ name = "Knob", from = 0, to = 0.1, thick = 0.42 },
	{ name = "Handle", from = 0.08, to = 1.5, thick = 0.2 },
	{ name = "Taper", from = 1.4, to = 2.05, thick = 0.3 },
	{ name = "Barrel", from = 1.95, to = 3.3, thick = 0.42 },
}
local BAT_TIP = 3.3

local visualBat = nil
local visualBatHand = nil
local visualBatStyle = nil
local batTrail = nil

local function removeVisualBat()
	if visualBat then
		visualBat:Destroy()
	end
	visualBat, visualBatHand, visualBatStyle, batTrail = nil, nil, nil, nil
end

local function batMaterial(name)
	local ok, material = pcall(function()
		return Enum.Material[name]
	end)
	return ok and material or Enum.Material.Wood
end

local function updateVisualBat(batterPlayer, char)
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then
		removeVisualBat()
		return
	end
	local style = batterPlayer:GetAttribute("EquippedBat") or "wood"
	if visualBat and visualBat.Parent and visualBatHand == hand and visualBatStyle == style then
		return
	end
	removeVisualBat()

	local item = ITEMS[style] or ITEMS.wood
	local color = item and item.color or Color3.fromRGB(181, 132, 82)
	local material = batMaterial(item and item.material or "Wood")
	local r15 = hand.Name == "RightHand"

	local model = Instance.new("Model")
	model.Name = "VisualBat"
	local function piece(name, shape, length, thick, centerFromKnob)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = if shape == Enum.PartType.Ball then Vector3.new(thick, thick, thick) else Vector3.new(length, thick, thick)
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = hand.CFrame
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = p
		if r15 then
			-- The bat goes straight through the fist (out the thumb side)
			weld.C0 = CFrame.new(0, 0, -(centerFromKnob - TOP_HAND)) * CFrame.Angles(0, math.rad(90), 0)
		else
			-- R6 avatars: the bat sticks out of the bottom of the arm
			weld.C0 = CFrame.new(0, -1, -(centerFromKnob - TOP_HAND)) * CFrame.Angles(0, math.rad(90), 0)
		end
		weld.Parent = p
		p.Parent = model
		return p
	end
	local barrel
	for _, info in BAT_PIECES do
		local p = piece(info.name, Enum.PartType.Cylinder, info.to - info.from, info.thick, (info.from + info.to) / 2)
		if info.name == "Barrel" then
			barrel = p
		end
	end
	piece("EndCap", Enum.PartType.Ball, 0, 0.42, BAT_TIP)

	-- A streak behind the barrel while swinging
	local barrelCenter = (BAT_PIECES[4].from + BAT_PIECES[4].to) / 2
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(2.0 - barrelCenter, 0, 0)
	a0.Parent = barrel
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(BAT_TIP - barrelCenter, 0, 0)
	a1.Parent = barrel
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Enabled = false
	trail.Parent = barrel
	model.Parent = workspace

	visualBat, visualBatHand, visualBatStyle, batTrail = model, hand, style, trail
end

---------------------------------------------------------------------
-- The swing: who's swinging, and what pose they're in right now
---------------------------------------------------------------------
local swingStates = {}  -- [userId] = { time = when the swing started, from = the pose it started from }
local prepPitches = {}  -- [userId] = { startTime, arrive } for the pitch coming at that batter
local posed = {}        -- the batter we're posing: { char, joints, rig }

local JOINT_LIST = {
	{ "root", "LowerTorso", "Root" }, { "waist", "UpperTorso", "Waist" }, { "neck", "Head", "Neck" },
	{ "rShoulder", "RightUpperArm", "RightShoulder" }, { "rElbow", "RightLowerArm", "RightElbow" }, { "rWrist", "RightHand", "RightWrist" },
	{ "lShoulder", "LeftUpperArm", "LeftShoulder" }, { "lElbow", "LeftLowerArm", "LeftElbow" }, { "lWrist", "LeftHand", "LeftWrist" },
	{ "rHip", "RightUpperLeg", "RightHip" }, { "rKnee", "RightLowerLeg", "RightKnee" }, { "rAnkle", "RightFoot", "RightAnkle" },
	{ "lHip", "LeftUpperLeg", "LeftHip" }, { "lKnee", "LeftLowerLeg", "LeftKnee" }, { "lAnkle", "LeftFoot", "LeftAnkle" },
}

-- New Roblox places build avatars with AnimationConstraint joints; older ones use Motor6D.
-- Both work the same way for us (we read C0/C1 and set Transform).
local function findJoint(part, name)
	for _, child in part:GetChildren() do
		if child.Name == name and (child:IsA("AnimationConstraint") or child:IsA("Motor6D")) then
			return child
		end
	end
	return nil
end

-- Finds all 15 joints of an R15 avatar (nil for R6 avatars or if it hasn't loaded yet)
local function getJoints(char)
	local joints = {}
	for _, info in JOINT_LIST do
		local part = char:FindFirstChild(info[2])
		local joint = part and findJoint(part, info[3])
		if not joint then
			return nil
		end
		joints[info[1]] = joint
	end
	return joints
end

local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The batter's pose right now: swinging, getting ready for a pitch, or waiting with a little bat waggle
local function poseFor(userId: number, now: number): any
	local s = swingStates[userId]
	if s then
		local t = now - s.time
		if t < Swing.SWING_TIME then
			return Swing.sample(Swing.SWING_KEYS, t, s.from)
		end
		swingStates[userId] = nil
	end
	local p = prepPitches[userId]
	if p then
		local afterPlate = now - p.arrive
		if afterPlate < 0.35 then
			return Swing.sample(Swing.PREP_KEYS, now - p.startTime)
		elseif afterPlate < 0.8 then
			local held = Swing.sample(Swing.PREP_KEYS, p.arrive + 0.35 - p.startTime)
			return Swing.blend(held, Swing.STANCE, smooth((afterPlate - 0.35) / 0.45))
		end
		prepPitches[userId] = nil
	end
	local waggle = Swing.blend(Swing.STANCE, Swing.STANCE, 0)
	waggle.batYaw += math.sin(now * 2.2) * 4
	waggle.grip += Vector3.new(0, math.sin(now * 2.2 + 1) * 0.03, 0)
	return waggle
end

local disableSwing -- (filled in below) turns the swing off if the SwingAnimation script breaks

local function startSwing(userId)
	local now = workspace:GetServerTimeNow()
	local from = nil
	if Swing then
		local ok, pose = pcall(poseFor, userId, now)
		if ok and type(pose) == "table" then
			from = table.clone(pose)
			-- Right after a swing the bat has come all the way around. Count it from the front again
			-- so the next swing doesn't spin the bat backward through the batter.
			if type(from.batYaw) == "number" and from.batYaw > 180 then
				from.batYaw -= 360
			end
		else
			disableSwing(pose)
		end
	end
	swingStates[userId] = { time = now, from = from }
	prepPitches[userId] = nil
end

-- Optional Toolbox swing animation (only your own avatar loads it; Roblox shows it to everyone)
local animTrack = nil
local animTrackChar = nil
local animFailed = SWING_ANIMATION_ID == 0

local function animationFailed(reason)
	if not animFailed then
		animFailed = true
		warn("[Baseball] The swing animation " .. tostring(SWING_ANIMATION_ID) .. " didn't work (" .. reason
			.. "). Using the built-in swing instead. Try a different animation, or set SWING_ANIMATION_ID back to 0.")
	end
end

local function getSwingTrack()
	if animFailed then
		return nil
	end
	local char = player.Character
	if animTrack and animTrackChar == char then
		return animTrack
	end
	animTrack, animTrackChar = nil, char
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(SWING_ANIMATION_ID)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		animationFailed("it wouldn't load")
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	animTrack = track
	return track
end

local function playSwingAnimation()
	local track = getSwingTrack()
	if not track then
		return
	end
	track:Play(0.05)
	task.delay(1.5, function()
		if track.Length == 0 then
			animationFailed("it never loaded - it might not be allowed in this game")
		end
	end)
end

-- Is the batter's Toolbox animation moving them right now? Then we leave their body alone.
local function swingAnimationPlaying(batterPlayer, char)
	if SWING_ANIMATION_ID == 0 then
		return false
	end
	if batterPlayer == player then
		return animTrack ~= nil and animTrack.IsPlaying and animTrack.Length > 0
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		local anim = track.Animation
		if anim and string.find(anim.AnimationId, tostring(SWING_ANIMATION_ID), 1, true) then
			return true
		end
	end
	return false
end

local function releasePose()
	if posed.joints and Swing then
		pcall(Swing.reset, posed.joints)
	end
	posed = {}
end

-- If a number got typed wrong in the SwingAnimation script, the game keeps going:
-- the batter just holds the bat, and Output says what happened (once).
disableSwing = function(err)
	if Swing then
		warn("[Baseball] The SwingAnimation script has a problem: " .. tostring(err)
			.. ". The batter will just hold the bat. (Check the numbers you changed in Script 3.)")
		releasePose()
		Swing = nil
	end
end

RunService.Stepped:Connect(function()
	local batterId = remotes:GetAttribute("BatterUserId") or 0
	local batterPlayer = batterId ~= 0 and Players:GetPlayerByUserId(batterId) or nil
	local char = batterPlayer and batterPlayer.Character
	if not batterPlayer or not char then
		removeVisualBat()
		releasePose()
		return
	end
	updateVisualBat(batterPlayer, char)

	local now = workspace:GetServerTimeNow()
	if posed.char ~= char or (not posed.joints and os.clock() - (posed.lastTry or 0) > 1) then
		releasePose()
		local joints = getJoints(char)
		local rig = nil
		if joints and Swing then
			local ok, result = pcall(Swing.measure, joints)
			if ok then
				rig = result
			else
				disableSwing(result)
			end
		end
		posed = { char = char, joints = joints, rig = rig, lastTry = os.clock() }
	end
	local s = swingStates[batterId]
	if batTrail then
		batTrail.Enabled = s ~= nil and now - s.time < 0.4
	end
	if not Swing or not posed.joints or not posed.rig or not posed.joints.root.Parent then
		return -- no swing script, R6 avatar, or still loading: the bat just stays in the hand
	end
	if swingAnimationPlaying(batterPlayer, char) then
		return
	end
	local ok, err = pcall(function()
		Swing.apply(posed.joints, posed.rig, poseFor(batterId, now))
	end)
	if not ok then
		disableSwing(err)
	end
end)

---------------------------------------------------------------------
-- The ROBO-PITCHER arm and light, and the crowd
---------------------------------------------------------------------
-- Roblox loads far-away parts a little at a time, so we look these up when they show up
-- instead of waiting for them.
local LIGHT_READY = Color3.fromRGB(60, 255, 90)
local LIGHT_FIRE = Color3.fromRGB(255, 50, 50)

local stadium = nil
local machineInfo = nil
local lastMachineLookup = 0
local armPitch = nil -- { startTime, golden } of the last pitch

local function findMachine()
	stadium = stadium or workspace:FindFirstChild("BaseballField")
	local machine = stadium and stadium:FindFirstChild("PitchingMachine")
	local arm = machine and machine:FindFirstChild("Arm")
	local light = machine and machine:FindFirstChild("PitchLight")
	local pivotCF = machine and machine:GetAttribute("PivotCF")
	if not (arm and light and typeof(pivotCF) == "CFrame") then
		return
	end
	local parts = {}
	for _, part in arm:GetChildren() do
		local offset = part:GetAttribute("ArmOffset")
		if part:IsA("BasePart") and typeof(offset) == "CFrame" then
			table.insert(parts, { part = part, offset = offset })
		end
	end
	if #parts == 0 then
		return
	end
	machineInfo = {
		light = light,
		pivotCF = pivotCF,
		armLength = machine:GetAttribute("ArmLength") or 2.9,
		ballLead = machine:GetAttribute("BallLead") or 0.55,
		releaseDeg = machine:GetAttribute("ReleaseDeg") or 8,
		restDeg = machine:GetAttribute("RestDeg") or -180,
		parts = parts,
	}
end

-- Arm angle (degrees) at time T from when the ball leaves. 0 = arm straight up.
-- It creeps back during the wind-up, whips over the top, lets go, and follows through.
local function armAngle(T)
	local m = machineInfo
	local rest = m.restDeg
	local release = m.releaseDeg
	if T < -PITCH_LEAD or T >= 0.35 then
		return rest + math.sin(os.clock() * 1.5) * 3
	elseif T < -0.16 then
		local a = smooth((T + PITCH_LEAD) / math.max(PITCH_LEAD - 0.16, 0.01))
		return rest + 70 * a
	elseif T < 0 then
		local u = (T + 0.16) / 0.16
		return rest + 70 + (release - rest - 70) * u * u
	end
	local v = T / 0.35
	return release + (rest + 360 - release) * (1 - (1 - v) * (1 - v))
end

local function cupPosition(angle)
	local m = machineInfo
	return (m.pivotCF * CFrame.Angles(math.rad(angle), 0, 0)) * Vector3.new(0, m.armLength, m.ballLead)
end

local cheerParts, cheerHomes, cheerPhases, cheerHops, cheerMoved = {}, {}, {}, {}, {}
local cheerUntil = 0
local cheering = false

local function startCheer(seconds, landPos)
	stadium = stadium or workspace:FindFirstChild("BaseballField")
	local crowdFolder = stadium and stadium:FindFirstChild("Crowd")
	if not crowdFolder then
		return
	end
	if not cheering then
		table.clear(cheerParts)
		table.clear(cheerHomes)
		table.clear(cheerPhases)
		table.clear(cheerHops)
		table.clear(cheerMoved)
		for _, part in crowdFolder:GetChildren() do
			if part:IsA("BasePart") then
				local phase = part:GetAttribute("Phase") or 0
				local distance = if landPos then (part.Position - landPos).Magnitude else math.huge
				-- Everyone near the ball jumps, plus every third fan everywhere else
				-- (a fan's shirt and head share a Phase, so they always jump together)
				if distance < 150 or math.floor(phase * 1000) % 3 == 0 then
					table.insert(cheerParts, part)
					table.insert(cheerHomes, part.CFrame)
					table.insert(cheerPhases, phase)
					-- Fans right where the ball landed go crazy
					table.insert(cheerHops, 1.6 * (1 + 2 * math.max(0, 1 - distance / 45)))
				end
			end
		end
	end
	cheerUntil = os.clock() + seconds
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()

	-- Pitching machine
	local m = machineInfo
	if (not m or not m.light.Parent or not m.parts[1].part.Parent) and now - lastMachineLookup > 1 then
		lastMachineLookup = now
		machineInfo = nil
		findMachine()
		m = machineInfo
	end
	if m then
		local T = if armPitch then workspace:GetServerTimeNow() - armPitch.startTime else -99
		local spin = m.pivotCF * CFrame.Angles(math.rad(armAngle(T)), 0, 0)
		for _, info in m.parts do
			info.part.CFrame = spin * info.offset
		end
		local windingUp = T >= -PITCH_LEAD and T < 0
		local blinkOn = windingUp and math.floor(now * 12) % 2 == 0
		m.light.Color = if blinkOn then (if armPitch.golden then GOLD else LIGHT_FIRE) else LIGHT_READY
	end

	-- Crowd jumping
	if now < cheerUntil then
		cheering = true
		for i, home in cheerHomes do
			local hop = math.max(0, math.sin(now * 14 + cheerPhases[i])) * cheerHops[i]
			cheerMoved[i] = home + Vector3.new(0, hop, 0)
		end
		pcall(function()
			workspace:BulkMoveTo(cheerParts, cheerMoved, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	elseif cheering then
		cheering = false
		pcall(function()
			workspace:BulkMoveTo(cheerParts, cheerHomes, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end

	-- Timing meter: the white ball slides toward the green zone
	local p = currentPitch
	if batting and p and meter.Visible then
		local fromPlate = workspace:GetServerTimeNow() - p.arrive
		meterBall.Visible = fromPlate > -METER_EARLY - 0.2 and fromPlate < METER_LATE + 0.2
		meterBall.Position = UDim2.new(meterX(fromPlate), 0, 0.5, 0)
	else
		meterBall.Visible = false
	end
end)

---------------------------------------------------------------------
-- The outfielders: they run, catch, dive, and throw. The server sends a plan with every
-- ball they go after, and every player's screen moves them the same way.
---------------------------------------------------------------------
-- (It's all inside one function because a script can only have 200 local variables,
-- and this one is almost full. Only startFielderPlay comes out.)
local startFielderPlay = (function()
	local RUN_STRIDE = 7      -- studs for two running steps
	local READY_CROUCH = 0.2  -- how low they get while a pitch is on its way
	local rad = math.rad

	local fielders = {}      -- [index] = one fielder: model, pieces, where he waits, which way he faces
	local fielderPlays = {}  -- [index] = { plan, start, ball } for the play that fielder is making
	local lastFielderLookup = -99
	local fieldersReady = 0  -- 1 while a pitch is on its way (everybody gets in ready position)

	local function findFielders()
		stadium = stadium or workspace:FindFirstChild("BaseballField")
		local folder = stadium and stadium:FindFirstChild("Fielders")
		if not folder then
			return
		end
		for _, model in folder:GetChildren() do
			local index = model:GetAttribute("Index")
			local home = model:GetAttribute("Home")
			if typeof(index) == "number" and typeof(home) == "Vector3" then
				local pieces = {}
				local gloveOffset = CFrame.new(0, -1.85, -0.15)
				for _, part in model:GetChildren() do
					local limb = part:GetAttribute("Limb")
					local offset = part:GetAttribute("Offset")
					if part:IsA("BasePart") and type(limb) == "string" and typeof(offset) == "CFrame" then
						table.insert(pieces, { part = part, limb = limb, offset = offset })
						if part.Name == "Glove" then
							gloveOffset = offset
						end
					end
				end
				local old = fielders[index]
				fielders[index] = {
					model = model,
					home = home,
					hipHeight = model:GetAttribute("HipHeight") or 2,
					shoulder = model:GetAttribute("Shoulder") or Vector3.new(1.45, 1.75, 0),
					hip = model:GetAttribute("Hip") or Vector3.new(0.5, 0, 0),
					gloveOffset = gloveOffset,
					pieces = pieces,
					facing = old and old.facing,
					ready = old and old.ready or 0,
				}
			end
		end
	end

	-- Where a fielder stands, t seconds into a play. (Same math as fielderSpotAt in BaseballServer.)
	local function fielderSpotAt(plan, t)
		if t < plan.runAt then
			return plan.from
		elseif t < plan.arriveAt then
			return plan.from:Lerp(plan.runTo, (t - plan.runAt) / (plan.arriveAt - plan.runAt))
		elseif plan.diveAt and t < plan.actAt then
			return plan.runTo:Lerp(plan.diveTo, math.clamp((t - plan.diveAt) / (plan.actAt - plan.diveAt), 0, 1))
		elseif t < plan.backAt then
			return plan.standAt
		elseif t < plan.homeAt then
			return plan.standAt:Lerp(plan.home, (t - plan.backAt) / (plan.homeAt - plan.backAt))
		end
		return plan.home
	end

	-- Turns an arm that hangs straight down so it points at a spot in the world
	local function pointArm(shoulderCF, target)
		local dir = shoulderCF.Rotation:Inverse() * (target - shoulderCF.Position)
		if dir.Magnitude < 0.01 then
			return CFrame.identity
		end
		dir = dir.Unit
		local down = Vector3.new(0, -1, 0)
		local axis = down:Cross(dir)
		if axis.Magnitude < 1e-4 then
			return if dir.Y > 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.identity
		end
		return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(down:Dot(dir), -1, 1)))
	end

	-- A quick up-and-down from 0 to 1 and back, centered on time 0
	local function bump(t, before, after)
		if t < 0 then
			return smooth((t + before) / before)
		end
		return 1 - smooth(t / after)
	end

	-- How a fielder looks right now. Returns where his 5 pivots are (body, arms, legs),
	-- and where a ball sits in his glove and in his throwing hand.
	local function poseFielder(f, play, now, dt)
		local plan = play and play.plan
		local t = if play then now - play.start else 0
		local active = plan ~= nil and t < plan.homeAt
		local ground = f.home
		local want = HOME - f.home       -- which way he wants to face (home plate)
		local rise, lean = 0, 0           -- hips up (+) or down (-); lean forward (-) or back (+) in degrees
		local spread = 0                  -- feet apart (degrees), for the ready crouch
		local legL, legR = 0, 0           -- legs forward (+) or back (-), degrees
		local armL = CFrame.Angles(rad(12), 0, rad(-10)) -- glove arm (left)
		local armR = CFrame.Angles(rad(12), 0, rad(10))  -- throwing arm (right)
		local reachFor, reach = nil, 0    -- reach the glove toward this spot (reach 0 to 1)
		local runAmount, runPhase = 0, 0
		local diving = false
		local stepping = false            -- the legs are already set (the throw's step)

		if not active then
			-- Waiting at his spot. When a pitch is on its way: ready position!
			f.ready += (fieldersReady - f.ready) * math.min(1, dt * 5)
			rise = -READY_CROUCH * f.ready
			lean = -14 * f.ready
			armL = CFrame.Angles(rad(12 + 30 * f.ready), 0, rad(-10))
			armR = CFrame.Angles(rad(12 + 30 * f.ready), 0, rad(10))
		else
			f.ready = 0
			ground = fielderSpotAt(plan, t)
			local toCatch = t - plan.actAt -- negative = the ball isn't there yet
			if t >= plan.runAt and t < plan.arriveAt then
				local run = plan.runTo - plan.from
				want = run
				runAmount = 1
				runPhase = run.Magnitude * (t - plan.runAt) / (plan.arriveAt - plan.runAt) / RUN_STRIDE * 2 * math.pi
			elseif t >= plan.backAt then
				local back = plan.home - plan.standAt
				want = back
				runAmount = 0.6
				runPhase = back.Magnitude * (t - plan.backAt) / (plan.homeAt - plan.backAt) / RUN_STRIDE * 2 * math.pi
			elseif toCatch > 0.15 then
				want = plan.throwTo - ground -- turn and throw it in
			else
				want = plan.ballPos - ground -- eyes on the ball
				if Vector3.new(want.X, 0, want.Z).Magnitude < 0.5 then
					want = HOME - ground
				end
			end

			if plan.action == "DIVE" and plan.diveAt and t >= plan.diveAt and t < plan.actAt + 1 then
				-- Fly through the air, land flat on his belly, then hop back up
				diving = true
				want = plan.diveTo - plan.runTo
				local u = math.clamp((t - plan.diveAt) / (plan.actAt - plan.diveAt), 0, 1)
				local down = if t < plan.actAt + 0.6 then smooth(u) else 1 - smooth((t - plan.actAt - 0.6) / 0.4)
				lean = -85 * down
				rise = (0.55 - f.hipHeight) * down + (if t < plan.actAt then math.sin(u * math.pi) * 0.9 else 0)
				legL, legR = -12 * down, -25 * down
				armL = CFrame.Angles(rad(12 + 158 * down), 0, rad(-10 + 6 * down))
				armR = CFrame.Angles(rad(12 + 158 * down), 0, rad(10 - 6 * down))
				runAmount = 0
				-- reach for the ball, and keep the glove there a moment after the catch
				reachFor = plan.ballPos
				reach = if t < plan.actAt then smooth(u) else 1 - smooth((t - plan.actAt) / 0.4)
			elseif plan.action == "FIELD" then
				-- Bend down and scoop it up
				if toCatch > -0.35 and toCatch < 0.25 then
					local c = bump(toCatch, 0.35, 0.25)
					rise, lean = -1 * c, -55 * c
					reachFor, reach = plan.ballPos, c
				end
			elseif toCatch > -0.4 and toCatch < 0.4 then
				-- Reach out for it, and keep the glove there a moment after the catch
				reachFor, reach = plan.ballPos, bump(toCatch, 0.35, 0.3)
				local height = plan.ballPos.Y - f.home.Y
				local top = height - (f.hipHeight + f.shoulder.Y + 1.2) -- how high he has to jump
				if top > 0 then
					-- Jump up and snag it (a big jump for a LEAP, a little hop for a high one)
					local u = (toCatch + 0.4) / 0.8
					local jump = 4 * u * (1 - u)
					rise = top * jump
					legL, legR = 25 * jump, -10 * jump
				elseif plan.action == "SHOESTRING" or height < 2.5 then
					-- Get down low
					local c = bump(toCatch, 0.35, 0.4)
					local low = if plan.action == "SHOESTRING" then 1 else 0.6
					rise, lean = -low * c, -50 * low * c
				end
			end

			-- Got it: hold the glove up in front of his chest
			if toCatch >= 0 and t < plan.throwAt - 0.35 and not diving then
				armL = CFrame.Angles(rad(12), 0, rad(-10)):Lerp(CFrame.Angles(rad(75), 0, rad(25)), smooth(toCatch / 0.25))
			end

			-- The throw back in: wind up, step, and fire it over the top
			local throwT = t - plan.throwAt
			if throwT > -0.35 and throwT < 0.45 then
				local angle
				if throwT < -0.08 then
					angle = -170 * smooth((throwT + 0.35) / 0.27)
				elseif throwT < 0.12 then
					angle = -170 - 130 * (throwT + 0.08) / 0.2
				else
					angle = 60 * (1 - smooth((throwT - 0.12) / 0.33))
				end
				armR = CFrame.Angles(rad(angle), 0, rad(8))
				armL = CFrame.Angles(rad(85 - 55 * smooth(throwT / 0.2)), 0, rad(-5)) -- glove points at the target
				local step = bump(throwT, 0.35, 0.45)
				legL, legR = 22 * step, -22 * step
				rise = -f.hipHeight * (1 - math.cos(rad(22 * step)))
				lean = if throwT < 0 then 6 * step else -16 * step
				stepping = true
			end
		end

		-- The legs don't have knees, so to get down low he steps his feet apart
		local bend = 0
		if rise < 0 and not diving and not stepping then
			bend = math.deg(math.acos(math.clamp(1 + rise / f.hipHeight, -1, 1)))
		end
		if runAmount > 0 then
			-- Running: legs and arms swing, and the hips dip so a foot stays on the grass
			local swing = math.sin(runPhase) * runAmount
			local stride = 45 * swing + bend
			legL, legR = legL + stride, legR - stride
			armL = CFrame.Angles(rad(10 - 50 * swing), 0, rad(-8))
			armR = CFrame.Angles(rad(10 + 50 * swing), 0, rad(8))
			lean += -12 * runAmount
			rise = math.max(rise, 0) - f.hipHeight * (1 - math.cos(rad(stride)))
		elseif not active then
			spread = bend -- the ready crouch: feet wide
		else
			legL, legR = legL + bend, legR - bend -- a lunge, glove foot forward
		end

		-- Turn smoothly toward where he wants to face
		local flat = Vector3.new(want.X, 0, want.Z)
		if flat.Magnitude > 0.01 then
			flat = flat.Unit
			if not f.facing or diving then
				f.facing = flat
			else
				local turned = f.facing:Lerp(flat, math.min(1, dt * 10))
				f.facing = if turned.Magnitude > 0.01 then turned.Unit else flat
			end
		end
		local facing = f.facing or Vector3.new(0, 0, 1)

		-- Leaning tips the whole body, legs too. Tip the legs back so the feet stay on the grass.
		-- (Not in a dive: then he's flying, legs and all.)
		if not diving then
			legL, legR = legL - lean, legR - lean
		end

		local hipPos = ground + Vector3.new(0, f.hipHeight + rise, 0)
		local hips = CFrame.lookAt(hipPos, hipPos + facing) * CFrame.Angles(rad(lean), 0, 0)
		local sh, hp = f.shoulder, f.hip
		local leftShoulder = hips * CFrame.new(-sh.X, sh.Y, sh.Z)
		if reachFor and reach > 0 then
			armL = armL:Lerp(pointArm(leftShoulder, reachFor), reach)
		end
		local frames = {
			Body = hips,
			LeftArm = leftShoulder * armL,
			RightArm = hips * CFrame.new(sh.X, sh.Y, sh.Z) * armR,
			LeftLeg = hips * CFrame.new(-hp.X, hp.Y, hp.Z) * CFrame.Angles(rad(legL), 0, rad(-spread)),
			RightLeg = hips * CFrame.new(hp.X, hp.Y, hp.Z) * CFrame.Angles(rad(legR), 0, rad(spread)),
		}
		local glove = (frames.LeftArm * f.gloveOffset * CFrame.new(0, 0, -0.5)).Position
		local hand = (frames.RightArm * CFrame.new(0, -1.95, 0)).Position
		return frames, glove, hand
	end

	-- A fielder is going after this ball. He takes it once he catches it or picks it up.
	local function startFielderPlay(plan, start, ball)
		local old = fielderPlays[plan.index]
		if old and old.ball and old.ball ~= ball then
			old.ball:Destroy() -- he never finished the last play (that ball's gone now)
		end
		fielderPlays[plan.index] = { plan = plan, start = start, ball = ball }
	end

	local fielderParts, fielderCFrames = {}, {}
	local warnedPose = false
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		if now - lastFielderLookup > 2 then
			lastFielderLookup = now
			findFielders()
		end
		local serverNow = workspace:GetServerTimeNow()
		fieldersReady = if armPitch and serverNow > armPitch.startTime - PITCH_LEAD - 0.3
			and serverNow < armPitch.startTime + 1.5 then 1 else 0

		-- Move everybody
		table.clear(fielderParts)
		table.clear(fielderCFrames)
		for index, f in fielders do
			if f.model.Parent then
				local ok, frames, glove, hand = pcall(poseFielder, f, fielderPlays[index], now, dt)
				if ok then
					f.glove, f.hand = glove, hand
					for _, info in f.pieces do
						local frame = frames[info.limb]
						if frame then
							table.insert(fielderParts, info.part)
							table.insert(fielderCFrames, frame * info.offset)
						end
					end
				elseif not warnedPose then
					warnedPose = true -- (say it once, not every frame)
					warn("[Baseball] The outfielders got stuck: " .. tostring(frames))
				end
			end
		end
		if #fielderParts > 0 then
			pcall(function()
				workspace:BulkMoveTo(fielderParts, fielderCFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end

		-- The ball, once a fielder has it: in the glove, into the throwing hand, then thrown to second base
		for index, play in fielderPlays do
			local plan = play.plan
			local t = now - play.start
			local ball = play.ball
			if ball and ball.Parent and t >= plan.actAt then
				local f = fielders[index]
				local holding = plan.standAt + Vector3.new(0, 3.5, 0) -- (in case this screen can't see the fielder)
				if t >= plan.throwAt + plan.throwTime then
					ball:Destroy()
					play.ball = nil
				elseif t >= plan.throwAt then
					play.releasePos = play.releasePos or (f and f.hand) or holding
					local from = play.releasePos
					local u = (t - plan.throwAt) / plan.throwTime
					local arc = (plan.throwTo - from).Magnitude * 0.06
					ball.Position = from:Lerp(plan.throwTo, u) + Vector3.new(0, 4 * arc * u * (1 - u), 0)
				elseif t >= plan.throwAt - 0.3 then
					ball.Position = (f and f.hand) or holding
				else
					ball.Position = (f and f.glove) or plan.ballPos
				end
			end
			if t > plan.homeAt and not (play.ball and play.ball.Parent) then
				fielderPlays[index] = nil
			end
		end
	end)

	return startFielderPlay
end)()

---------------------------------------------------------------------
-- Balls
---------------------------------------------------------------------
local balls = {} -- pitch id -> the ball for that pitch

local function makeBall(trailColor, golden)
	local ball = Instance.new("Part")
	ball.Name = "Baseball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.85, 0.85, 0.85)
	ball.Color = if golden then GOLD else Color3.fromRGB(250, 250, 245)
	ball.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	if trailColor then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.3, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.3, 0)
		a1.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.4
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), trailColor)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Parent = ball
	end
	if golden then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 40
		sparkle.Lifetime = NumberRange.new(0.3, 0.5)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.35, 0)
		sparkle.Color = ColorSequence.new(GOLD)
		sparkle.LightEmission = 1
		sparkle.Parent = ball
	end
	ball.Parent = workspace
	return ball
end

local function curvePoint(a, b, c, t)
	return a:Lerp(b, t):Lerp(b:Lerp(c, t), t)
end

PitchEvent.OnClientEvent:Connect(function(data)
	local ball = makeBall(Color3.fromRGB(220, 220, 220), data.golden)
	ball.Position = data.startPos
	balls[data.id] = ball
	armPitch = { startTime = data.startTime, golden = data.golden }
	prepPitches[data.batterUserId] = { startTime = data.startTime, arrive = data.startTime + data.duration }

	local control = (data.startPos + data.endPos) / 2 + data.bend
	if data.batterUserId == player.UserId then
		followBall = nil -- stop watching the last hit; here comes the next pitch
		holdLookPos = nil
		currentPitch = { id = data.id, startTime = data.startTime, arrive = data.startTime + data.duration, swung = false }
		swingTick.Visible = false
		meterLabel.Text = ""
	end
	pitchLabel.Text = string.format("%d MPH %s%s", data.mph, data.name, if data.golden then "  -  GOLDEN BALL!" else "")
	pitchLabel.TextColor3 = if data.golden then GOLD else (data.color or Color3.fromRGB(255, 220, 120))

	local wobble = data.wobble or 0
	local seed = data.id * 1.7
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if balls[data.id] ~= ball then
			conn:Disconnect() -- it got hit, the flying ball takes over
			return
		end
		local T = workspace:GetServerTimeNow() - data.startTime
		local alpha = T / data.duration
		if alpha < 0 then
			-- still in the machine's cup during the wind-up
			ball.Position = if machineInfo then cupPosition(armAngle(T)) else data.startPos
		elseif alpha <= 1 then
			local pos = curvePoint(data.startPos, control, data.endPos, alpha)
			if wobble > 0 then
				local fade = alpha * (1 - alpha) * 4
				pos += Vector3.new(math.sin(T * 23 + seed) * wobble * fade, math.cos(T * 17 + seed * 2) * wobble * 0.7 * fade, 0)
			end
			ball.Position = pos
		elseif alpha < 1.4 then
			-- missed it: keep flying past the plate
			ball.Position = data.endPos + (data.endPos - control) * 2 * (alpha - 1)
		else
			conn:Disconnect()
			balls[data.id] = nil
			ball:Destroy()
		end
	end)
end)

-- A glowing ring and the distance where a home run came down
local function landingMarker(pos, distance)
	local ring = Instance.new("Part")
	ring.Name = "LandingSpot"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 6, 6)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 0.35
	ring.Parent = workspace
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(0, 200, 0, 60)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = true
	sign.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Text = distance .. " FT"
	addStroke(label, 3)
	label.Parent = sign
	sign.Parent = ring
	TweenService:Create(ring, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.2, 12, 12) }):Play()
	Debris:AddItem(ring, 4.2)
end

local function contactBurst(pos, color)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.Position = pos
	holder.Parent = workspace
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(12, 22)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Size = NumberSequence.new(0.5, 0)
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Parent = holder
	sparks:Emit(24)
	Debris:AddItem(holder, 1)
end

local function flyBall(info)
	local pitchBall = balls[info.pitchId]
	if pitchBall then
		pitchBall:Destroy()
		balls[info.pitchId] = nil
	end

	local batterPlayer = Players:GetPlayerByUserId(info.batterUserId)
	local batItem = ITEMS[batterPlayer and batterPlayer:GetAttribute("EquippedBat") or "wood"]
	local trailColor = if info.golden then GOLD elseif batItem then batItem.color else Color3.fromRGB(255, 210, 60)
	local ball = makeBall(trailColor, info.golden)
	ball.Position = info.launchPos
	contactBurst(info.launchPos, trailColor)
	playSound(HIT_SOUND_ID, 1)
	local mine = info.batterUserId == player.UserId and batting
	if mine then
		followBall = ball
	end

	-- After it lands: one bounce (off the wall it bounces back), then it rests.
	-- (When an outfielder is chasing it, the server works out the bounce so he knows where it stops.)
	local T = info.flightTime
	local g = info.gravity
	local landPos = info.launchPos + info.velocity * T + Vector3.new(0, -0.5 * g * T * T, 0)
	local bounceVel, bounceTime = info.bounceVel, info.bounceTime
	if typeof(bounceVel) ~= "Vector3" or type(bounceTime) ~= "number" then
		local landVel = info.velocity + Vector3.new(0, -g * T, 0)
		if info.kind == "WALL" then
			bounceVel = Vector3.new(-landVel.X * 0.25, math.max(math.abs(landVel.Y) * 0.3, 6), -landVel.Z * 0.25)
			-- falls all the way down to the warning track
			local h = landPos.Y - 0.45
			bounceTime = (bounceVel.Y + math.sqrt(bounceVel.Y * bounceVel.Y + 2 * g * math.max(h, 0))) / g
		else
			bounceVel = Vector3.new(landVel.X * 0.3, math.abs(landVel.Y) * 0.3, landVel.Z * 0.3)
			bounceTime = 2 * bounceVel.Y / g
		end
	end

	-- An outfielder is going after it: once he catches it (or picks it up), it's his
	local plan = if type(info.fielding) == "table" then info.fielding else nil
	local start = os.clock()
	if plan then
		startFielderPlay(plan, start, ball)
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		if not ball.Parent then
			conn:Disconnect() -- (a fielder threw it in, or a new play took over)
			if followBall == ball then
				followBall = nil
			end
			return
		end
		if not (plan and elapsed >= plan.actAt) then
			if elapsed <= T then
				ball.Position = info.launchPos + info.velocity * elapsed + Vector3.new(0, -0.5 * g * elapsed * elapsed, 0)
			elseif info.kind ~= "FOUL" then
				local b = math.min(elapsed - T, bounceTime)
				ball.Position = landPos + bounceVel * b + Vector3.new(0, -0.5 * g * b * b, 0)
			end
		end
		if mine and followBall == ball and elapsed > T + 0.3 then
			followBall = nil
			holdLookPos = ball.Position
			holdLookUntil = os.clock() + 1.1
		end
		if plan then
			if elapsed > math.max(T + 0.3, plan.actAt) then
				conn:Disconnect() -- the fielder has the ball now
			end
		elseif elapsed > T + bounceTime + 1.5 then
			conn:Disconnect()
			if followBall == ball then
				followBall = nil
			end
			ball:Destroy()
		end
	end)
	if info.kind == "HOMER" and info.landPos then
		task.delay(T, landingMarker, info.landPos, info.distance)
	end
end

---------------------------------------------------------------------
-- HOMERUNNNNNNNN!!!
---------------------------------------------------------------------
local function firework(pos, color)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = pos
	holder.Parent = workspace

	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(40, 70)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(1.2, 1.8)
	sparks.Drag = 2
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Size = NumberSequence.new(5, 0)
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Parent = holder
	sparks:Emit(90)
	Debris:AddItem(holder, 3)
end

-- Paper confetti falling down your screen
local function confetti()
	for _ = 1, 50 do
		local bit = Instance.new("Frame")
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Size = UDim2.new(0, math.random(8, 14), 0, math.random(14, 22))
		bit.Position = UDim2.new(math.random(), 0, 0, -30)
		bit.Rotation = math.random(0, 360)
		bit.BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1)
		bit.BorderSizePixel = 0
		bit.ZIndex = 5
		bit.Parent = root
		local fall = TweenInfo.new(1.6 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(bit, fall, {
			Position = UDim2.new(bit.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1, 40),
			Rotation = bit.Rotation + math.random(-360, 360),
		}):Play()
		Debris:AddItem(bit, 3)
	end
end

local celebrateToken = 0
local function celebrate(info)
	celebrateToken += 1
	local token = celebrateToken
	local mine = info.batterUserId == player.UserId

	homerSub.Text = string.format("%s - %s", info.batterName, info.text)
	local extras = {}
	if info.streak and info.streak >= 2 then
		table.insert(extras, string.format("%d IN A ROW!", info.streak))
	end
	if info.golden then
		table.insert(extras, "GOLDEN BALL!")
	end
	if mine and info.firstHomer then
		table.insert(extras, "YOUR FIRST HOME RUN!")
	elseif mine and info.newBest then
		table.insert(extras, "NEW PERSONAL BEST!")
	end
	homerExtra.Text = table.concat(extras, "  ")
	homerExtra.Visible = #extras > 0
	homerLabel.Text = "HOMERUN"
	homerLabel.Rotation = 0
	homerLabel.Visible = true
	homerSub.Visible = true
	homerScale.Scale = 0.2
	TweenService:Create(homerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	if mine then
		shakeUntil = os.clock() + 0.6
		confetti()
	end
	startCheer(4, info.landPos)
	playSound(HOMER_SOUND_ID, 1)
	playSound(CROWD_SOUND_ID, 0.8)

	for i = 1, 8 do
		local angle = math.rad(math.random(-40, 40))
		local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local pos = HOME + dir * (FENCE_DIST + math.random(-10, 40)) + Vector3.new(0, math.random(50, 90), 0)
		task.delay(i * 0.18, firework, pos, Color3.fromHSV(math.random(), 0.8, 1))
	end

	task.spawn(function()
		local start = os.clock()
		local extraNs = 0
		while token == celebrateToken and os.clock() - start < 3.6 do
			local t = os.clock() - start
			-- Add one more N every 0.06 seconds: HOMERUNNNNNNNNNNNNNN!!!
			local wanted = math.min(14, math.floor(t / 0.06))
			if wanted > extraNs then
				extraNs = wanted
				homerLabel.Text = "HOMERUN" .. string.rep("N", extraNs) .. (extraNs >= 14 and "!!!" or "")
			end
			homerLabel.TextColor3 = Color3.fromHSV((t * 1.2) % 1, 0.9, 1)
			homerLabel.Rotation = if t < 1.2 then (math.random() - 0.5) * 6 else 0
			RunService.RenderStepped:Wait()
		end
		if token == celebrateToken then
			homerLabel.Visible = false
			homerSub.Visible = false
			homerExtra.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Results from the server
---------------------------------------------------------------------
local RESULT_COLORS = {
	WHIFF = Color3.fromRGB(255, 80, 80),
	FOUL = Color3.fromRGB(255, 160, 60),
	WALL = Color3.fromRGB(255, 230, 90),
	OUT = Color3.fromRGB(235, 235, 235),
	HIT = Color3.fromRGB(110, 235, 120),
	TAKE = Color3.fromRGB(180, 180, 180),
	ROUNDOVER = Color3.fromRGB(90, 220, 255),
}

-- Where your swing landed on the timing meter
local function showSwingTiming(offset, hitKind)
	local window = SWING_WINDOW * batTiming()
	swingTick.Position = UDim2.new(meterX(offset), 0, 0.5, 0)
	swingTick.Visible = true
	local quality = 1 - math.abs(offset) / window
	if hitKind == "WHIFF" then
		swingTick.BackgroundColor3 = RED
		meterLabel.Text = if offset < 0 then "TOO EARLY" else "TOO LATE"
		meterLabel.TextColor3 = RED
	elseif quality > 0.9 then
		swingTick.BackgroundColor3 = GOLD
		meterLabel.Text = "PERFECT!"
		meterLabel.TextColor3 = GOLD
	else
		swingTick.BackgroundColor3 = Color3.new(1, 1, 1)
		meterLabel.Text = if offset < 0 then "A LITTLE EARLY" else "A LITTLE LATE"
		meterLabel.TextColor3 = Color3.new(1, 1, 1)
	end
end

ResultEvent.OnClientEvent:Connect(function(info)
	local mine = info.batterUserId == player.UserId
	if currentPitch and currentPitch.id == info.pitchId then
		currentPitch = nil
	end
	-- Other players see the batter swing (your own swing already started when you clicked)
	if info.swung and not mine then
		startSwing(info.batterUserId)
	end
	if mine and info.swung and typeof(info.offset) == "number" then
		showSwingTiming(info.offset, info.kind)
	end
	if info.launchPos then
		flyBall(info)
		local who = if mine then "" else info.batterName .. ":  "
		showStats(string.format("%sEXIT VELO %d MPH  |  LAUNCH %d°  |  %d FT", who, info.exitVelo or 0, info.launchDeg or 0, info.distance or 0))
	end

	-- When an outfielder is chasing it, wait until he catches it (or it drops) to say what happened
	local function reveal()
		if mine and (info.earned or 0) > 0 then
			showEarned(info.earned, info.lucky, info.golden)
		end
		if info.kind == "HOMER" then
			celebrate(info)
			return
		end
		local text = info.text
		if not mine and info.batterName ~= "" then
			text = info.batterName .. ": " .. text
		end
		showMessage(text, if info.hitType then RESULT_COLORS.HIT else (RESULT_COLORS[info.kind] or Color3.new(1, 1, 1)))
		if info.kind == "ROUNDOVER" and mine then
			showRoundSummary(info)
		end
		-- The crowd goes wild for a great catch (or a triple)
		if info.caught == "DIVE" or info.caught == "LEAP" or info.atWall or info.hitType == "TRIPLE" then
			startCheer(2.5, if type(info.fielding) == "table" then info.fielding.ballPos else nil)
		end
	end
	if type(info.revealAt) == "number" and info.revealAt > 0 then
		task.delay(info.revealAt, reveal)
	else
		reveal()
	end
end)

---------------------------------------------------------------------
-- Swinging: mouse click, SPACE or F on a keyboard, R2 or A on a controller,
-- tap or the SWING button on a phone/tablet
---------------------------------------------------------------------
local function trySwing()
	if not batting then
		return
	end
	local p = currentPitch
	local now = workspace:GetServerTimeNow()
	if p and now < p.startTime then
		return -- the ball hasn't been thrown yet, so wait for it
	end
	local s = swingStates[player.UserId]
	if s and now - s.time < SWING_TIME * 0.75 then
		return -- still finishing the last swing
	end

	startSwing(player.UserId)
	playSwingAnimation()
	playSound(SWING_SOUND, 0.6)
	if not p or p.swung then
		return -- practice swing, no pitch to hit
	end
	local offset = now - p.arrive -- negative = early, positive = late
	if offset > 0.5 then
		return
	end
	p.swung = true
	SwingEvent:FireServer(p.id, offset)
end

local function toggleShop()
	setShopOpen(not shopFrame.Visible)
end

-- Is the player typing in chat? (The new chat box doesn't count as a "focused TextBox".)
local chatBar = nil
local function typingInChat()
	if UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	if not (chatBar and chatBar.Parent) then
		pcall(function()
			chatBar = game:GetService("TextChatService"):FindFirstChildOfClass("ChatInputBarConfiguration")
		end)
	end
	return chatBar ~= nil and chatBar.IsFocused
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local inputType = input.UserInputType
	local key = input.KeyCode
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		if not gameProcessed and not shopFrame.Visible then
			trySwing()
		end
	elseif inputType == Enum.UserInputType.Keyboard then
		if typingInChat() then
			return
		end
		if key == Enum.KeyCode.Space then
			trySwing() -- (Space always looks "used" because Roblox uses it for jumping)
		elseif gameProcessed then
			return
		elseif key == Enum.KeyCode.F then
			trySwing()
		elseif key == Enum.KeyCode.E then
			toggleShop()
		elseif key == Enum.KeyCode.Q then
			leaveBox()
		end
	elseif string.find(inputType.Name, "Gamepad") then
		if key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.ButtonA then
			if not shopFrame.Visible then
				trySwing()
			end
		elseif key == Enum.KeyCode.ButtonY then
			toggleShop()
		elseif key == Enum.KeyCode.ButtonB then
			if shopFrame.Visible then
				setShopOpen(false)
			else
				leaveBox()
			end
		end
	end
end)

-- Swing the moment your finger touches the button (not when it lifts off)
swingButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		trySwing()
	end
end)
