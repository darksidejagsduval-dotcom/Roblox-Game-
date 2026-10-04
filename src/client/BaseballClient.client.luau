--[[
	BaseballClient  (LocalScript in StarterPlayer > StarterPlayerScripts)
	Warren's Home Run Derby, version 3.
	Draws the ball, animates the swing, runs the camera, the shop, the baseball
	counter, the pitching machine, the crowd, and the HOMERUNNNN show.
	Works with mouse, keyboard, and touch screens.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- Optional: put a sound ID from the Toolbox here to play on every home run (0 = no sound)
local HOMER_SOUND_ID = 0

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
local FENCE_DIST = waitForAttribute("FenceCenter")
-- Camera spot behind home plate, looking out at the pitching machine
local BAT_VIEW = CFrame.lookAt(HOME + Vector3.new(1.5, 6, 14), HOME + Vector3.new(0, 3, -30))

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
-- Screen helpers
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BaseballGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromRGB(60, 170, 80)
local BLUE = Color3.fromRGB(50, 120, 220)
local GRAY = Color3.fromRGB(90, 95, 110)
local RED = Color3.fromRGB(200, 60, 60)
local GOLD = Color3.fromRGB(255, 215, 0)

local function addCorner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = obj
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

local function fadeOut(label, seconds)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local info = TweenInfo.new(seconds)
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
end

local function fadeIn(label)
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
end

---------------------------------------------------------------------
-- Screen: status, messages, and the big HOMERUN text
---------------------------------------------------------------------
local statusLabel = makeLabel(gui, "Status", UDim2.new(0.55, 0, 0, 34), UDim2.new(0.5, 0, 0, 64), nil, 30)
local pitchLabel = makeLabel(gui, "Pitch", UDim2.new(0.4, 0, 0, 26), UDim2.new(0.5, 0, 0, 100), nil, 26)
pitchLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
local messageLabel = makeLabel(gui, "Message", UDim2.new(0.56, 0, 0, 52), UDim2.new(0.5, 0, 0.24, 0), nil, 44)

local homerLabel = makeLabel(gui, "Homer", UDim2.new(0.95, 0, 0.22, 0), UDim2.new(0.5, 0, 0.42, 0), Enum.Font.LuckiestGuy)
homerLabel.Visible = false
homerLabel:FindFirstChildOfClass("UIStroke").Thickness = 6
local homerScale = Instance.new("UIScale")
homerScale.Parent = homerLabel
local homerSub = makeLabel(gui, "HomerSub", UDim2.new(0.7, 0, 0.07, 0), UDim2.new(0.5, 0, 0.56, 0))
homerSub.Visible = false

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

---------------------------------------------------------------------
-- Screen: baseball counter (left side)
---------------------------------------------------------------------
local counter = Instance.new("Frame")
counter.Name = "BaseballCounter"
counter.Size = UDim2.new(0, 180, 0, 48)
counter.Position = UDim2.new(0, 16, 0, 124)
counter.BackgroundColor3 = Color3.fromRGB(20, 25, 40)
counter.BackgroundTransparency = 0.2
addCorner(counter)
counter.Parent = gui
local counterScale = Instance.new("UIScale")
counterScale.Parent = counter

local ballIcon = Instance.new("Frame")
ballIcon.AnchorPoint = Vector2.new(0, 0.5)
ballIcon.Size = UDim2.new(0, 32, 0, 32)
ballIcon.Position = UDim2.new(0, 8, 0.5, 0)
ballIcon.BackgroundColor3 = Color3.fromRGB(250, 250, 245)
addCorner(ballIcon, UDim.new(1, 0))
local stitches = addStroke(ballIcon, 3)
stitches.Color = Color3.fromRGB(220, 40, 40)
ballIcon.Parent = counter

local countLabel = makeLabel(counter, "Count", UDim2.new(1, -58, 0.75, 0), UDim2.new(0, 50, 0.5, 0), Enum.Font.LuckiestGuy, 32)
countLabel.AnchorPoint = Vector2.new(0, 0.5)
countLabel.TextXAlignment = Enum.TextXAlignment.Left

local function refreshCount()
	countLabel.Text = tostring(baseballsValue.Value)
end
refreshCount()

local function showEarned(amount, lucky)
	local pop = makeLabel(gui, "Earned", UDim2.new(0, 230, 0, 36), UDim2.new(0, 320, 0, 148), Enum.Font.LuckiestGuy)
	pop.Text = "+" .. amount .. (lucky and "  LUCKY x2!" or "")
	pop.TextColor3 = lucky and GOLD or Color3.new(1, 1, 1)
	TweenService:Create(pop, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 320, 0, 96) }):Play()
	task.delay(0.6, fadeOut, pop, 0.8)
	Debris:AddItem(pop, 1.6)

	counterScale.Scale = lucky and 1.4 or 1.2
	TweenService:Create(counterScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------------
-- Screen: buttons (they work with mouse AND touch)
---------------------------------------------------------------------
local shopButton = makeButton(gui, "ShopButton", "SHOP", UDim2.new(0, 180, 0, 52), UDim2.new(0, 16, 0, 182), GREEN)
local leaveButton = makeButton(gui, "LeaveButton", "LEAVE BOX", UDim2.new(0, 180, 0, 44), UDim2.new(0, 16, 0, 244), GRAY)
leaveButton.Visible = false

local swingButton = makeButton(gui, "SwingButton", "SWING", UDim2.new(0, 120, 0, 120), UDim2.new(1, -24, 0.5, 0), RED)
swingButton.AnchorPoint = Vector2.new(1, 0.5)
swingButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
swingButton.Visible = false

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
local shopLimit = Instance.new("UISizeConstraint")
shopLimit.MaxSize = Vector2.new(760, 540)
shopLimit.Parent = shopFrame
shopFrame.Parent = gui

local shopTitle = makeLabel(shopFrame, "Title", UDim2.new(0.5, 0, 0, 40), UDim2.new(0, 16, 0, 30), Enum.Font.LuckiestGuy, 40)
shopTitle.AnchorPoint = Vector2.new(0, 0.5)
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Text = "BAT SHOP"

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
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = shopFrame
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 190, 0, 160)
grid.CellPadding = UDim2.new(0, 10, 0, 10)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list

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

local function describe(item)
	if item.kind == "luck" then
		return string.format("Lucky x2 chance: %d%%", math.floor(item.luck * 100 + 0.5))
	end
	if item.price == 0 then
		return "Your starter bat"
	end
	return string.format("Power +%d%%\nTiming +%d%%",
		math.floor((item.power - 1) * 100 + 0.5), math.floor((item.timing - 1) * 100 + 0.5))
end

local function ownedSet()
	local owned = {}
	for id in string.gmatch(player:GetAttribute("Owned") or "", "[^,]+") do
		owned[id] = true
	end
	return owned
end

local cardButtons = {}

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

	local infoLabel = makeLabel(card, "Info", UDim2.new(1, -12, 0, 38), UDim2.new(0.5, 0, 0, 86), nil, 20)
	infoLabel.Text = describe(item)

	local button = makeButton(card, "Action", "", UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 1, -48), GREEN)
	button.Activated:Connect(function()
		onCardPressed(item)
	end)
	cardButtons[item.id] = button
	card.Parent = list
end

if #catalog == 0 then
	showToast("The shop couldn't load. Try rejoining.", RED)
end

shopButton.Activated:Connect(function()
	shopFrame.Visible = not shopFrame.Visible
	refreshShop()
end)
closeButton.Activated:Connect(function()
	shopFrame.Visible = false
end)

baseballsValue.Changed:Connect(function()
	refreshCount()
	refreshShop()
end)
player.AttributeChanged:Connect(refreshShop)
refreshShop()

---------------------------------------------------------------------
-- Camera: behind the plate while you bat, follows the ball when you hit it
---------------------------------------------------------------------
local batting = false
local currentPitch = nil -- the pitch you can swing at right now
local followBall = nil
local shakeUntil = 0

local function cameraStep()
	local cf = BAT_VIEW
	if followBall and followBall.Parent then
		cf = CFrame.lookAt(BAT_VIEW.Position, followBall.Position)
	end
	if os.clock() < shakeUntil then
		cf = cf * CFrame.Angles((math.random() - 0.5) * 0.03, (math.random() - 0.5) * 0.03, 0)
	end
	camera.CFrame = cf
end

local function setBatting(on)
	if on == batting then
		return
	end
	batting = on
	swingButton.Visible = on
	leaveButton.Visible = on
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep("BaseballCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)
		local how = UserInputService.TouchEnabled and "Tap SWING" or "Click or press SPACE"
		showMessage(how .. " when the ball reaches the plate!", Color3.new(1, 1, 1))
	else
		RunService:UnbindFromRenderStep("BaseballCamera")
		camera.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		currentPitch = nil
		followBall = nil
	end
end

local function refreshHud()
	local batterId = remotes:GetAttribute("BatterUserId") or 0
	local outs = remotes:GetAttribute("Outs") or 0
	local homers = remotes:GetAttribute("Homers") or 0
	local maxOuts = remotes:GetAttribute("MaxOuts") or 10
	if batterId == 0 then
		statusLabel.Text = "HOME RUN DERBY - walk into the glowing box to bat!"
		pitchLabel.Text = ""
	elseif batterId == player.UserId then
		statusLabel.Text = string.format("OUTS %d/%d     HOME RUNS %d", outs, maxOuts, homers)
	else
		statusLabel.Text = string.format("%s is batting - OUTS %d/%d   HOME RUNS %d",
			remotes:GetAttribute("BatterName") or "Someone", outs, maxOuts, homers)
	end
end

remotes.AttributeChanged:Connect(function()
	refreshHud()
	setBatting(remotes:GetAttribute("BatterUserId") == player.UserId)
end)
refreshHud()
setBatting(remotes:GetAttribute("BatterUserId") == player.UserId)

leaveButton.Activated:Connect(function()
	LeaveEvent:FireServer()
end)

---------------------------------------------------------------------
-- The bat and the swing animation (for R15 avatars, the Roblox default)
---------------------------------------------------------------------
-- Each pose is in degrees.
--   waist  = twist the upper body (+ turns toward the pitcher)
--   rYaw / rPitch / rRoll / rElbow = right arm,  lYaw / lPitch / lElbow = left arm
--   neck   = turn the head
-- Change these numbers to change how the swing looks!
local STANCE = { waist = -10, rYaw = -30, rPitch = 40, rRoll = 0, rElbow = 150, lYaw = -45, lPitch = 70, lElbow = 90, neck = 85 }
local SWING_KEYS = {
	{ time = 0.00, pose = STANCE },
	-- load: hands start forward, bat drops in behind you
	{ time = 0.07, pose = { waist = 10, rYaw = -80, rPitch = 80, rRoll = -60, rElbow = 60, lYaw = -50, lPitch = 85, lElbow = 50, neck = 70 } },
	-- contact: hips and shoulders open, arms and bat level out over the plate
	{ time = 0.14, pose = { waist = 40, rYaw = -40, rPitch = 90, rRoll = 0, rElbow = 5, lYaw = -60, lPitch = 90, lElbow = 5, neck = -10 } },
	-- follow-through: bat wraps around behind your front shoulder
	{ time = 0.32, pose = { waist = 70, rYaw = 47, rPitch = 107, rRoll = 70, rElbow = 90, lYaw = 30, lPitch = 110, lElbow = 80, neck = -30 } },
	-- back to your stance
	{ time = 0.85, pose = STANCE },
}
local SWING_TIME = 0.85

local swingStarts = {} -- [userId] = when that player's swing started

local function poseAt(elapsed)
	for i = 1, #SWING_KEYS - 1 do
		local a, b = SWING_KEYS[i], SWING_KEYS[i + 1]
		if elapsed <= b.time then
			local alpha = (elapsed - a.time) / (b.time - a.time)
			alpha = alpha * alpha * (3 - 2 * alpha) -- smooth in and out
			local pose = {}
			for key, value in a.pose do
				pose[key] = value + (b.pose[key] - value) * alpha
			end
			return pose
		end
	end
	return STANCE
end

local function getJoints(char)
	local function motor(partName, jointName)
		local part = char:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint and joint:IsA("Motor6D") then
			return joint
		end
		return nil
	end
	return {
		waist = motor("UpperTorso", "Waist"),
		rShoulder = motor("RightUpperArm", "RightShoulder"),
		rElbow = motor("RightLowerArm", "RightElbow"),
		lShoulder = motor("LeftUpperArm", "LeftShoulder"),
		lElbow = motor("LeftLowerArm", "LeftElbow"),
		neck = motor("Head", "Neck"),
	}
end

local function applyPose(joints, pose)
	local rad = math.rad
	if joints.waist then
		joints.waist.Transform = CFrame.Angles(0, rad(pose.waist), 0)
	end
	if joints.rShoulder then
		joints.rShoulder.Transform = CFrame.Angles(0, rad(pose.rYaw), 0)
			* CFrame.Angles(rad(pose.rPitch), 0, 0)
			* CFrame.Angles(0, rad(pose.rRoll), 0)
	end
	if joints.rElbow then
		joints.rElbow.Transform = CFrame.Angles(rad(pose.rElbow), 0, 0)
	end
	if joints.lShoulder then
		joints.lShoulder.Transform = CFrame.Angles(0, rad(pose.lYaw), 0) * CFrame.Angles(rad(pose.lPitch), 0, 0)
	end
	if joints.lElbow then
		joints.lElbow.Transform = CFrame.Angles(rad(pose.lElbow), 0, 0)
	end
	if joints.neck then
		joints.neck.Transform = CFrame.Angles(0, rad(pose.neck), 0)
	end
end

-- The bat in the batter's hand. Every player's screen draws it, so everyone sees it.
local visualBat = nil
local visualBatHand = nil
local visualBatStyle = nil

local function removeVisualBat()
	if visualBat then
		visualBat:Destroy()
	end
	visualBat, visualBatHand, visualBatStyle = nil, nil, nil
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
	-- The bat sticks straight out of the top of your fist
	local fist = hand.Name == "RightHand" and 0.35 or -0.6

	local model = Instance.new("Model")
	model.Name = "VisualBat"
	local function piece(name, length, thickness, centerY)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(length, thickness, thickness)
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
		weld.C0 = CFrame.new(0, centerY, 0) * CFrame.Angles(0, 0, math.rad(90))
		weld.Parent = p
		p.Parent = model
	end
	piece("Handle", 1.9, 0.28, fist - 0.95)
	piece("Barrel", 2.5, 0.5, fist - 1.9 - 1.25)
	model.Parent = workspace

	visualBat, visualBatHand, visualBatStyle = model, hand, style
end

local posedChar = nil
local posedJoints = nil

RunService.Stepped:Connect(function()
	local batterId = remotes:GetAttribute("BatterUserId") or 0
	local batterPlayer = batterId ~= 0 and Players:GetPlayerByUserId(batterId) or nil
	local char = batterPlayer and batterPlayer.Character
	if not batterPlayer or not char then
		removeVisualBat()
		posedChar = nil
		return
	end
	updateVisualBat(batterPlayer, char)

	if char ~= posedChar or not (posedJoints.rShoulder and posedJoints.rShoulder.Parent) then
		posedChar = char
		posedJoints = getJoints(char)
	end

	local pose = STANCE
	local started = swingStarts[batterId]
	if started then
		local elapsed = os.clock() - started
		if elapsed < SWING_TIME then
			pose = poseAt(elapsed)
		else
			swingStarts[batterId] = nil
		end
	end
	applyPose(posedJoints, pose)
end)

---------------------------------------------------------------------
-- The pitching machine (spinning wheels + a light that flashes before each pitch)
-- and the crowd (they jump when someone hits a home run)
---------------------------------------------------------------------
-- Roblox loads far-away parts a little at a time, so we look these up when they show up
-- instead of waiting for them.
local LIGHT_READY = Color3.fromRGB(60, 255, 90)
local LIGHT_FIRE = Color3.fromRGB(255, 50, 50)

local stadium = nil
local machineParts = nil
local lastMachineLookup = 0
local wheelAngle = 0
local wheelsFastUntil = 0
local lightBlinkUntil = 0

local function findMachine()
	stadium = stadium or workspace:FindFirstChild("BaseballField")
	local machine = stadium and stadium:FindFirstChild("PitchingMachine")
	local left = machine and machine:FindFirstChild("WheelLeft")
	local right = machine and machine:FindFirstChild("WheelRight")
	local light = machine and machine:FindFirstChild("PitchLight")
	if left and right and light then
		machineParts = { left = left, right = right, light = light, leftHome = left.CFrame, rightHome = right.CFrame }
	end
end

local cheerParts, cheerHomes, cheerPhases = {}, {}, {}
local cheerUntil = 0
local cheering = false

local function startCheer(seconds)
	stadium = stadium or workspace:FindFirstChild("BaseballField")
	local crowdFolder = stadium and stadium:FindFirstChild("Crowd")
	if not crowdFolder then
		return
	end
	if not cheering then
		table.clear(cheerParts)
		table.clear(cheerHomes)
		table.clear(cheerPhases)
		for _, part in crowdFolder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(cheerParts, part)
				table.insert(cheerHomes, part.CFrame)
				table.insert(cheerPhases, part:GetAttribute("Phase") or 0)
			end
		end
	end
	cheerUntil = os.clock() + seconds
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()

	-- Pitching machine
	local m = machineParts
	if (not m or not m.left.Parent or not m.right.Parent or not m.light.Parent) and now - lastMachineLookup > 1 then
		lastMachineLookup = now
		machineParts = nil
		findMachine()
		m = machineParts
	end
	if m then
		wheelAngle += dt * (if now < wheelsFastUntil then 35 else 4)
		m.left.CFrame = m.leftHome * CFrame.Angles(wheelAngle, 0, 0)
		m.right.CFrame = m.rightHome * CFrame.Angles(-wheelAngle, 0, 0)
		local blinkOn = now < lightBlinkUntil and math.floor(now * 12) % 2 == 0
		m.light.Color = if blinkOn then LIGHT_FIRE else LIGHT_READY
	end

	-- Crowd jumping
	if now < cheerUntil then
		cheering = true
		local moved = table.create(#cheerParts)
		for i, home in cheerHomes do
			local hop = math.max(0, math.sin(now * 14 + cheerPhases[i])) * 1.6
			moved[i] = home + Vector3.new(0, hop, 0)
		end
		pcall(function()
			workspace:BulkMoveTo(cheerParts, moved, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	elseif cheering then
		cheering = false
		pcall(function()
			workspace:BulkMoveTo(cheerParts, cheerHomes, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end
end)

---------------------------------------------------------------------
-- Balls
---------------------------------------------------------------------
local balls = {} -- pitch id -> the ball for that pitch

local function makeBall(withTrail)
	local ball = Instance.new("Part")
	ball.Name = "Baseball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = Color3.fromRGB(250, 250, 245)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	if withTrail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.4
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 210, 60))
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Parent = ball
	end
	ball.Parent = workspace
	return ball
end

local function curvePoint(a, b, c, t)
	return a:Lerp(b, t):Lerp(b:Lerp(c, t), t)
end

PitchEvent.OnClientEvent:Connect(function(data)
	local ball = makeBall(false)
	ball.Position = data.startPos
	balls[data.id] = ball

	local control = (data.startPos + data.endPos) / 2 + data.bend
	if data.batterUserId == player.UserId then
		currentPitch = { id = data.id, startTime = data.startTime, arrive = data.startTime + data.duration, swung = false }
	end
	pitchLabel.Text = string.format("%d MPH %s", data.mph, data.name)

	-- Machine winds up: light blinks red, wheels spin fast
	local windUp = math.max(0, data.startTime - workspace:GetServerTimeNow())
	lightBlinkUntil = os.clock() + windUp
	wheelsFastUntil = os.clock() + windUp + 0.8

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if balls[data.id] ~= ball then
			conn:Disconnect() -- it got hit, the flying ball takes over
			return
		end
		local alpha = (workspace:GetServerTimeNow() - data.startTime) / data.duration
		if alpha < 0 then
			ball.Position = data.startPos
		elseif alpha <= 1 then
			ball.Position = curvePoint(data.startPos, control, data.endPos, alpha)
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

local function flyBall(info)
	local pitchBall = balls[info.pitchId]
	if pitchBall then
		pitchBall:Destroy()
		balls[info.pitchId] = nil
	end

	local ball = makeBall(true)
	ball.Position = info.launchPos
	if info.batterUserId == player.UserId and batting then
		followBall = ball
	end

	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		local t = math.min(elapsed, info.flightTime)
		ball.Position = info.launchPos + info.velocity * t + Vector3.new(0, -0.5 * info.gravity * t * t, 0)
		if elapsed > info.flightTime + 1.2 then
			conn:Disconnect()
			if followBall == ball then
				followBall = nil
			end
			ball:Destroy()
		end
	end)
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

local celebrateToken = 0
local function celebrate(info)
	celebrateToken += 1
	local token = celebrateToken

	homerSub.Text = string.format("%s - %s", info.batterName, info.text)
	homerLabel.Text = "HOMERUN"
	homerLabel.Rotation = 0
	homerLabel.Visible = true
	homerSub.Visible = true
	homerScale.Scale = 0.2
	TweenService:Create(homerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	if info.batterUserId == player.UserId then
		shakeUntil = os.clock() + 0.6
	end
	startCheer(3.5)

	if HOMER_SOUND_ID ~= 0 then
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. HOMER_SOUND_ID
		sound.Volume = 1
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 15)
	end

	for i = 1, 8 do
		local angle = math.rad(math.random(-40, 40))
		local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local pos = HOME + dir * (FENCE_DIST + math.random(-10, 30)) + Vector3.new(0, math.random(40, 75), 0)
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
	TAKE = Color3.fromRGB(180, 180, 180),
	ROUNDOVER = Color3.fromRGB(90, 220, 255),
}

ResultEvent.OnClientEvent:Connect(function(info)
	local mine = info.batterUserId == player.UserId
	if currentPitch and currentPitch.id == info.pitchId then
		currentPitch = nil
	end
	-- Other players see the batter swing (your own swing already started when you clicked)
	if info.swung and not mine then
		swingStarts[info.batterUserId] = os.clock()
	end
	if info.launchPos then
		flyBall(info)
	end
	if mine and (info.earned or 0) > 0 then
		showEarned(info.earned, info.lucky)
	end
	if info.kind == "HOMER" then
		celebrate(info)
	else
		local text = info.text
		if not mine and info.batterName ~= "" then
			text = info.batterName .. ": " .. text
		end
		showMessage(text, RESULT_COLORS[info.kind] or Color3.new(1, 1, 1))
	end
end)

---------------------------------------------------------------------
-- Swinging: mouse click, SPACE or F on a keyboard, tap or the SWING button on a phone/tablet
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
	local started = swingStarts[player.UserId]
	if started and os.clock() - started < SWING_TIME then
		return -- still finishing the last swing
	end

	swingStarts[player.UserId] = os.clock()
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		if not gameProcessed then
			trySwing()
		end
	elseif inputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if (key == Enum.KeyCode.Space or key == Enum.KeyCode.F) and UserInputService:GetFocusedTextBox() == nil then
			trySwing()
		end
	end
end)

swingButton.Activated:Connect(trySwing)
