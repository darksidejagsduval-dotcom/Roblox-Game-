--[[
	BaseballServer  (Script in ServerScriptService)
	Warren's Home Run Derby, version 3.
	Builds the whole stadium, runs the pitching machine, decides hits, keeps score,
	runs the bat shop, and saves everyone's baseballs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

---------------------------------------------------------------------
-- SETTINGS: try changing these numbers!
---------------------------------------------------------------------
local MAX_OUTS = 10          -- outs in one round
local FENCE_CENTER = 200     -- fence distance to center field (studs). 200 studs = 400 feet
local FENCE_CORNER = 165     -- fence distance down the lines. 165 studs = 330 feet
local FENCE_HEIGHT = 12      -- how tall the fence is
local FEET_PER_STUD = 2
local BALL_GRAVITY = 80      -- lower number = floatier, longer home runs
local SWING_WINDOW = 0.22    -- seconds of wiggle room on your swing timing
local POWER = 1              -- 1 = normal, 1.2 = super power for everyone
local CROWD_FILL = 0.45      -- how full the stands are (0 = empty, 1 = packed)

-- Baseballs you earn for hitting
local REWARD_CONTACT = 3     -- any ball you hit
local REWARD_WALL = 5        -- off the wall
local REWARD_HOMER = 15      -- home run
local REWARD_PERFECT = 5     -- extra for perfect timing
local BASE_LUCK = 0.15       -- 0.15 = 15% chance to DOUBLE what you earn

local PITCHES = {
	{ name = "FASTBALL",  mphMin = 90, mphMax = 99, time = 0.75, bend = Vector3.new(0, 0.6, 0) },
	{ name = "CHANGEUP",  mphMin = 78, mphMax = 85, time = 1.05, bend = Vector3.new(0, 1.8, 0) },
	{ name = "CURVEBALL", mphMin = 72, mphMax = 80, time = 0.95, bend = Vector3.new(3, 4, 0) },
}

-- THE SHOP. Add your own items by copying a line and changing it!
--   power  = how hard you hit (1.2 = 20% harder)
--   timing = how forgiving your swing is (1.1 = 10% easier)
--   luck   = chance to double your baseballs (0.35 = 35%)
local SHOP_ITEMS = {
	{ id = "wood",      name = "Wood Bat",         kind = "bat",  price = 0,     power = 1.00, timing = 1.00, color = Color3.fromRGB(181, 132, 82),  material = "Wood" },
	{ id = "metal",     name = "Metal Bat",        kind = "bat",  price = 75,    power = 1.08, timing = 1.05, color = Color3.fromRGB(195, 200, 210), material = "Metal" },
	{ id = "gold",      name = "Gold Bat",         kind = "bat",  price = 300,   power = 1.15, timing = 1.10, color = Color3.fromRGB(255, 200, 40),  material = "Metal" },
	{ id = "diamond",   name = "Diamond Bat",      kind = "bat",  price = 1000,  power = 1.22, timing = 1.15, color = Color3.fromRGB(120, 230, 255), material = "Glass" },
	{ id = "lava",      name = "Lava Bat",         kind = "bat",  price = 3000,  power = 1.30, timing = 1.22, color = Color3.fromRGB(255, 110, 30),  material = "Neon" },
	{ id = "galaxy",    name = "Galaxy Bat",       kind = "bat",  price = 10000, power = 1.40, timing = 1.30, color = Color3.fromRGB(170, 90, 255),  material = "ForceField" },
	{ id = "socks",     name = "Lucky Socks",      kind = "luck", price = 150,   luck = 0.25, color = Color3.fromRGB(80, 200, 120) },
	{ id = "clover",    name = "Four-Leaf Clover", kind = "luck", price = 800,   luck = 0.35, color = Color3.fromRGB(40, 180, 70) },
	{ id = "horseshoe", name = "Golden Horseshoe", kind = "luck", price = 2500,  luck = 0.50, color = Color3.fromRGB(255, 215, 0) },
}
---------------------------------------------------------------------

local ITEMS_BY_ID = {}
for _, item in SHOP_ITEMS do
	ITEMS_BY_ID[item.id] = item
end

local HOME = Vector3.new(0, 0, -30)              -- home plate
local MOUND = HOME + Vector3.new(0, 0, -30)      -- pitcher's mound
local MOUND_TOP = 0.8
local RELEASE = MOUND + Vector3.new(0, MOUND_TOP + 3.7, 4.3) -- end of the pitching machine's chute
local BOX_CENTER = HOME + Vector3.new(-4.5, 0, 0)
local BOX_SIZE = Vector3.new(4, 0.1, 6)
local LEAVE_SPOT = HOME + Vector3.new(-12, 3, 8) -- where you go when you leave the box
local PITCH_LEAD = 0.6   -- wind-up time before the ball flies
local TAKE_GRACE = 0.6   -- no swing by this long after the plate = pitch taken

local GRASS = Color3.fromRGB(70, 135, 55)
local GRASS_LIGHT = Color3.fromRGB(84, 152, 64)
local INFIELD_GRASS = Color3.fromRGB(88, 160, 68)
local DIRT = Color3.fromRGB(181, 130, 85)
local TRACK = Color3.fromRGB(160, 110, 70)
local WHITE = Color3.fromRGB(245, 245, 240)
local FENCE_GREEN = Color3.fromRGB(25, 70, 40)
local YELLOW = Color3.fromRGB(255, 210, 40)
local GOLD = Color3.fromRGB(255, 215, 0)
local SEAT_BLUE = Color3.fromRGB(35, 75, 160)
local SEAT_BLUE_DARK = Color3.fromRGB(28, 60, 130)
local CONCRETE = Color3.fromRGB(150, 150, 155)
local DARK = Color3.fromRGB(40, 40, 45)
local STEEL = Color3.fromRGB(170, 175, 185)
local MACHINE_YELLOW = Color3.fromRGB(255, 190, 30)
local RUBBER_BLACK = Color3.fromRGB(25, 25, 25)
local HOME_BLUE = Color3.fromRGB(30, 80, 200)
local AWAY_RED = Color3.fromRGB(190, 40, 40)
local SHIRT_COLORS = {
	Color3.fromRGB(220, 50, 50), Color3.fromRGB(40, 90, 220), Color3.fromRGB(250, 210, 40),
	Color3.fromRGB(60, 180, 80), Color3.fromRGB(240, 240, 240), Color3.fromRGB(250, 130, 30),
	Color3.fromRGB(150, 70, 200), Color3.fromRGB(30, 170, 170), Color3.fromRGB(30, 30, 35),
}
local SKIN_COLORS = {
	Color3.fromRGB(255, 220, 177), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36), Color3.fromRGB(96, 60, 35),
}

-- How far the fence is at an angle (0 = straight to center field, -45/45 = the foul lines)
local function fenceDistAt(deg)
	local t = math.clamp(math.abs(deg) / 45, 0, 1)
	return FENCE_CORNER + (FENCE_CENTER - FENCE_CORNER) * math.cos(t * math.pi / 2)
end

-- A spot on the field at an angle and distance from home plate
local function fieldPoint(deg, dist)
	local r = math.rad(deg)
	return HOME + Vector3.new(math.sin(r), 0, -math.cos(r)) * dist
end

---------------------------------------------------------------------
-- Remotes: how the server and players talk
-- (the folder goes into ReplicatedStorage at the very bottom of this script)
---------------------------------------------------------------------
local oldRemotes = ReplicatedStorage:FindFirstChild("Baseball")
if oldRemotes then
	oldRemotes:Destroy()
end

local remotes = Instance.new("Folder")
remotes.Name = "Baseball"

local function newRemote(className, name)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local PitchEvent = newRemote("RemoteEvent", "Pitch")
local SwingEvent = newRemote("RemoteEvent", "Swing")
local ResultEvent = newRemote("RemoteEvent", "Result")
local LeaveEvent = newRemote("RemoteEvent", "Leave")
local ShopFunction = newRemote("RemoteFunction", "Shop")

remotes:SetAttribute("Home", HOME)
remotes:SetAttribute("FenceCenter", FENCE_CENTER)
remotes:SetAttribute("MaxOuts", MAX_OUTS)
remotes:SetAttribute("BatterUserId", 0)
remotes:SetAttribute("BatterName", "")
remotes:SetAttribute("Outs", 0)
remotes:SetAttribute("Homers", 0)

---------------------------------------------------------------------
-- Build the stadium
---------------------------------------------------------------------
local function buildField()
	local oldField = workspace:FindFirstChild("BaseballField")
	if oldField then
		oldField:Destroy()
	end

	local field = Instance.new("Model")
	field.Name = "BaseballField"

	local function block(name, size, cframe, color, material, parent)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent or field
		return p
	end

	-- Flat ground paint you can walk over
	local function flat(name, size, cframe, color, material)
		local p = block(name, size, cframe, color, material)
		p.CanCollide = false
		p.CastShadow = false
		return p
	end

	-- A flat circle (like the mound or the dirt around home plate)
	local function disc(name, diameter, thickness, center, color, material, parent)
		local p = block(name, Vector3.new(thickness, diameter, diameter),
			CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, parent)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	local function addSign(part, face, text, color)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = color or WHITE
		label.Text = text
		label.Parent = gui
		gui.Parent = part
		return label
	end

	local function facingHome(pos)
		return CFrame.lookAt(pos, Vector3.new(HOME.X, pos.Y, HOME.Z))
	end

	-- Grass with mowing stripes
	block("Grass", Vector3.new(700, 1, 700), CFrame.new(HOME + Vector3.new(0, -0.4, -200)), GRASS, Enum.Material.Grass)
	for i = 0, 16, 2 do
		local z = -20 - i * 14 - 7
		flat("MowStripe", Vector3.new(560, 0.04, 14), CFrame.new(HOME + Vector3.new(0, 0.12, z)), GRASS_LIGHT, Enum.Material.Grass)
	end

	-- Infield
	local turn45 = CFrame.Angles(0, math.rad(45), 0)
	local baseGap = 45 / math.sqrt(2)
	local diamondCenter = HOME + Vector3.new(0, 0, -baseGap)
	flat("InfieldDirt", Vector3.new(54, 0.1, 54), CFrame.new(diamondCenter + Vector3.new(0, 0.15, 0)) * turn45, DIRT, Enum.Material.Sand)
	flat("InfieldGrass", Vector3.new(38, 0.1, 38), CFrame.new(diamondCenter + Vector3.new(0, 0.17, 0)) * turn45, INFIELD_GRASS, Enum.Material.Grass)
	local homeDirt = disc("HomeDirt", 26, 0.1, HOME + Vector3.new(0, 0.19, 0), DIRT, Enum.Material.Sand)
	homeDirt.CanCollide = false

	local bases = {
		FirstBase = HOME + Vector3.new(baseGap, 0, -baseGap),
		SecondBase = HOME + Vector3.new(0, 0, -2 * baseGap),
		ThirdBase = HOME + Vector3.new(-baseGap, 0, -baseGap),
	}
	for name, pos in bases do
		local base = block(name, Vector3.new(2.5, 0.3, 2.5), CFrame.new(pos + Vector3.new(0, 0.3, 0)) * turn45, WHITE)
		base.CanCollide = false
	end
	flat("HomePlate", Vector3.new(2.4, 0.06, 2.4), CFrame.new(HOME + Vector3.new(0, 0.26, 0)), WHITE)

	-- Chalk lines: batter's boxes and catcher's box
	local function chalkBox(center, sizeX, sizeZ)
		local w = 0.25
		local y = Vector3.new(0, 0.26, 0)
		flat("Chalk", Vector3.new(sizeX, 0.03, w), CFrame.new(center + y + Vector3.new(0, 0, -sizeZ / 2)), WHITE)
		flat("Chalk", Vector3.new(sizeX, 0.03, w), CFrame.new(center + y + Vector3.new(0, 0, sizeZ / 2)), WHITE)
		flat("Chalk", Vector3.new(w, 0.03, sizeZ), CFrame.new(center + y + Vector3.new(-sizeX / 2, 0, 0)), WHITE)
		flat("Chalk", Vector3.new(w, 0.03, sizeZ), CFrame.new(center + y + Vector3.new(sizeX / 2, 0, 0)), WHITE)
	end
	chalkBox(HOME + Vector3.new(-4.5, 0, 0), 4, 6)
	chalkBox(HOME + Vector3.new(4.5, 0, 0), 4, 6)
	chalkBox(HOME + Vector3.new(0, 0, 6.5), 4.5, 5)

	-- On-deck circles
	for _, side in { -1, 1 } do
		local circle = disc("OnDeckCircle", 5, 0.06, HOME + Vector3.new(side * 20, 0.14, 10), DIRT, Enum.Material.Sand)
		circle.CanCollide = false
	end

	-- Glowing batter's box (this is where you bat)
	local box = block("BattersBox", BOX_SIZE, CFrame.new(BOX_CENTER + Vector3.new(0, 0.3, 0)), YELLOW, Enum.Material.Neon)
	box.Transparency = 0.45
	box.CanCollide = false
	local boxSign = Instance.new("BillboardGui")
	boxSign.Size = UDim2.new(0, 220, 0, 50)
	boxSign.StudsOffset = Vector3.new(0, 6, 0)
	boxSign.AlwaysOnTop = true
	boxSign.MaxDistance = 120
	local boxSignText = Instance.new("TextLabel")
	boxSignText.Size = UDim2.new(1, 0, 1, 0)
	boxSignText.BackgroundTransparency = 1
	boxSignText.Font = Enum.Font.LuckiestGuy
	boxSignText.TextScaled = true
	boxSignText.TextColor3 = YELLOW
	boxSignText.Text = "BAT HERE"
	local boxSignStroke = Instance.new("UIStroke")
	boxSignStroke.Thickness = 3
	boxSignStroke.Parent = boxSignText
	boxSignText.Parent = boxSign
	boxSign.Parent = box

	-- Backstop net behind home plate
	local backstop = block("Backstop", Vector3.new(36, 14, 0.4), CFrame.new(HOME + Vector3.new(0, 7, 18)), DARK)
	backstop.Transparency = 0.65

	-- Mound
	disc("Mound", 16, 1, MOUND + Vector3.new(0, MOUND_TOP - 0.5, 0), DIRT, Enum.Material.Sand)
	block("PitchersRubber", Vector3.new(2.4, 0.2, 0.6), CFrame.new(MOUND + Vector3.new(0, MOUND_TOP + 0.05, 0.6)), WHITE)

	-- The pitching machine: "ROBO-PITCHER 3000"
	local machine = Instance.new("Model")
	machine.Name = "PitchingMachine"
	machine.Parent = field
	local top = MOUND + Vector3.new(0, MOUND_TOP, 0)
	block("Base", Vector3.new(4, 0.5, 4), CFrame.new(top + Vector3.new(0, 0.25, 0)), DARK, Enum.Material.Metal, machine)
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		local foot = top + Vector3.new(math.cos(a) * 1.5, 0.5, math.sin(a) * 1.5)
		local hip = top + Vector3.new(0, 3, 0)
		block("Leg", Vector3.new(0.3, 0.3, (hip - foot).Magnitude), CFrame.lookAt((foot + hip) / 2, hip),
			STEEL, Enum.Material.Metal, machine)
	end
	local body = block("Body", Vector3.new(3.4, 1.6, 2.2), CFrame.new(top + Vector3.new(0, 3.7, 0)),
		MACHINE_YELLOW, Enum.Material.Metal, machine)
	addSign(body, Enum.NormalId.Back, "ROBO-PITCHER 3000", DARK)
	disc("WheelLeft", 2.2, 0.7, top + Vector3.new(-1.25, 3.7, 1.5), RUBBER_BLACK, Enum.Material.SmoothPlastic, machine)
	disc("WheelRight", 2.2, 0.7, top + Vector3.new(1.25, 3.7, 1.5), RUBBER_BLACK, Enum.Material.SmoothPlastic, machine)
	local chute = block("Chute", Vector3.new(1.6, 0.9, 0.9), CFrame.new(top + Vector3.new(0, 3.7, 3.4)) * CFrame.Angles(0, math.rad(90), 0),
		STEEL, Enum.Material.Metal, machine)
	chute.Shape = Enum.PartType.Cylinder
	local hopper = disc("Hopper", 1.8, 1.6, top + Vector3.new(0, 5.3, -0.3), Color3.fromRGB(200, 230, 255), Enum.Material.Glass, machine)
	hopper.Transparency = 0.5
	for i = 1, 3 do
		local ball = block("HopperBall", Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(top + Vector3.new((i - 2) * 0.45, 4.9 + (i % 2) * 0.5, -0.3)), WHITE, Enum.Material.SmoothPlastic, machine)
		ball.Shape = Enum.PartType.Ball
	end
	local light = block("PitchLight", Vector3.new(0.7, 0.7, 0.7), CFrame.new(top + Vector3.new(1.3, 4.8, 0.6)),
		Color3.fromRGB(60, 255, 90), Enum.Material.Neon, machine)
	light.Shape = Enum.PartType.Ball

	-- Foul lines and foul poles
	for _, side in { -1, 1 } do
		local deg = 45 * side
		local dist = fenceDistAt(deg)
		local mid = fieldPoint(deg, dist / 2) + Vector3.new(0, 0.24, 0)
		flat("FoulLine", Vector3.new(0.5, 0.04, dist), CFrame.lookAt(mid, fieldPoint(deg, dist) + Vector3.new(0, 0.24, 0)), WHITE)
		block("FoulPole", Vector3.new(1.2, 50, 1.2), CFrame.new(fieldPoint(deg, dist) + Vector3.new(0, 25, 0)), YELLOW, Enum.Material.Neon)
	end

	-- Outfield wall, warning track, and distance signs
	local step = 2
	for deg = -45, 45 - step, step do
		local d1, d2 = fenceDistAt(deg), fenceDistAt(deg + step)
		local p1, p2 = fieldPoint(deg, d1), fieldPoint(deg + step, d2)
		local length = (p2 - p1).Magnitude + 0.5
		local mid = (p1 + p2) / 2
		local along = CFrame.lookAt(mid, mid + (p2 - p1))
		block("Fence", Vector3.new(1.5, FENCE_HEIGHT, length), along + Vector3.new(0, FENCE_HEIGHT / 2, 0), FENCE_GREEN)
		block("FenceTop", Vector3.new(1.7, 0.6, length), along + Vector3.new(0, FENCE_HEIGHT + 0.3, 0), YELLOW)

		local t1, t2 = fieldPoint(deg, d1 - 5), fieldPoint(deg + step, d2 - 5)
		local trackMid = (t1 + t2) / 2
		flat("WarningTrack", Vector3.new(10, 0.06, (t2 - t1).Magnitude + 0.6),
			CFrame.lookAt(trackMid, trackMid + (t2 - t1)) + Vector3.new(0, 0.16, 0), TRACK, Enum.Material.Sand)
	end
	for _, deg in { -45, -22, 0, 22, 45 } do
		local dist = fenceDistAt(deg)
		local pos = fieldPoint(deg, dist - 0.9) + Vector3.new(0, FENCE_HEIGHT / 2, 0)
		local board = block("DistanceSign", Vector3.new(9, 4, 0.2), facingHome(pos), FENCE_GREEN)
		addSign(board, Enum.NormalId.Front, tostring(math.floor(dist * FEET_PER_STUD / 5 + 0.5) * 5), YELLOW)
	end

	-- Batter's eye (dark wall in center field so you can see the pitch)
	block("BattersEye", Vector3.new(70, 36, 3), facingHome(fieldPoint(0, FENCE_CENTER + 10) + Vector3.new(0, 18, 0)), FENCE_GREEN)

	-- Turn off any other spawn points so everyone spawns in the dugout
	for _, obj in workspace:GetDescendants() do
		if obj:IsA("SpawnLocation") then
			obj.Enabled = false
		end
	end

	-- Dugouts: blue HOME dugout on the third base side (you spawn here), red VISITORS on first base side
	local function dugout(side, teamColor, title, isSpawn)
		local d = Vector3.new(math.sin(math.rad(45 * side)), 0, -math.cos(math.rad(45 * side)))
		local n = Vector3.new(side * 0.7071, 0, 0.7071)
		local center = HOME + d * 32 + n * 12
		local base = CFrame.lookAt(center, center - n) -- open side faces the field
		local back = block("DugoutBack", Vector3.new(18, 6, 0.6), base * CFrame.new(0, 3, 3), teamColor, Enum.Material.Concrete)
		addSign(back, Enum.NormalId.Front, title, WHITE)
		block("DugoutRoof", Vector3.new(19, 0.6, 7), base * CFrame.new(0, 6.3, 0.3), teamColor, Enum.Material.Metal)
		for _, x in { -9, 9 } do
			block("DugoutSide", Vector3.new(0.6, 6, 6.6), base * CFrame.new(x, 3, 0), CONCRETE, Enum.Material.Concrete)
		end
		block("Bench", Vector3.new(16, 1, 1.4), base * CFrame.new(0, 0.9, 2), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
		if isSpawn then
			local spawnPad = Instance.new("SpawnLocation")
			spawnPad.Name = "DugoutSpawn"
			spawnPad.Anchored = true
			spawnPad.Size = Vector3.new(16, 0.4, 3)
			spawnPad.CFrame = base * CFrame.new(0, 0.2, -1)
			spawnPad.Color = CONCRETE
			spawnPad.Material = Enum.Material.Concrete
			spawnPad.Neutral = true
			spawnPad.Duration = 0
			spawnPad.TopSurface = Enum.SurfaceType.Smooth
			spawnPad.Parent = field
		else
			block("DugoutFloor", Vector3.new(16, 0.4, 3), base * CFrame.new(0, 0.2, -1), CONCRETE, Enum.Material.Concrete)
		end
	end
	dugout(-1, HOME_BLUE, "HOME", true)
	dugout(1, AWAY_RED, "VISITORS", false)

	-- Stands full of fans
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = field
	local function addFan(pos)
		if math.random() > CROWD_FILL then
			return
		end
		local phase = math.random() * math.pi * 2
		local shirt = block("Fan", Vector3.new(1.3, 2, 1), CFrame.new(pos + Vector3.new(0, 1, 0)),
			SHIRT_COLORS[math.random(1, #SHIRT_COLORS)], Enum.Material.SmoothPlastic, crowd)
		local head = block("FanHead", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 2.5, 0)),
			SKIN_COLORS[math.random(1, #SKIN_COLORS)], Enum.Material.SmoothPlastic, crowd)
		head.Shape = Enum.PartType.Ball
		for _, part in { shirt, head } do
			part.CanCollide = false
			part.CastShadow = false
			part:SetAttribute("Phase", phase)
		end
	end

	local ROWS = 7
	for _, side in { -1, 1 } do
		local d = Vector3.new(math.sin(math.rad(45 * side)), 0, -math.cos(math.rad(45 * side)))
		local n = Vector3.new(side * 0.7071, 0, 0.7071)
		local start, finish = 8, 150
		local middle = (start + finish) / 2
		local orient = CFrame.lookAt(Vector3.zero, d)
		block("StandWall", Vector3.new(1, 4, finish - start), CFrame.new(HOME + d * middle + n * 20.5 + Vector3.new(0, 2, 0)) * orient, FENCE_GREEN)
		for k = 0, ROWS - 1 do
			local h = 2 + 2 * k
			local offset = 22 + 3 * k + 1.5
			block("Seats", Vector3.new(3, h, finish - start), CFrame.new(HOME + d * middle + n * offset + Vector3.new(0, h / 2, 0)) * orient,
				k % 2 == 0 and SEAT_BLUE or SEAT_BLUE_DARK)
			for a = start + 1.5, finish - 1.5, 2.2 do
				addFan(HOME + d * a + n * offset + Vector3.new(0, h, 0))
			end
		end
		-- Light towers behind the stands
		for _, a in { 45, 120 } do
			local base = HOME + d * a + n * 52
			disc("LightPole", 1.5, 70, base + Vector3.new(0, 35, 0), STEEL, Enum.Material.Metal)
			local lamp = block("Lights", Vector3.new(14, 7, 1.5),
				CFrame.lookAt(base + Vector3.new(0, 72, 0), fieldPoint(0, 90) + Vector3.new(0, 10, 0)), WHITE, Enum.Material.Neon)
			lamp.CastShadow = false
		end
	end
	local homeWidth = 56
	block("StandWall", Vector3.new(homeWidth, 4, 1), CFrame.new(HOME + Vector3.new(0, 2, 22.5)), FENCE_GREEN)
	for k = 0, ROWS - 1 do
		local h = 2 + 2 * k
		local z = 24 + 3 * k + 1.5
		block("Seats", Vector3.new(homeWidth, h, 3), CFrame.new(HOME + Vector3.new(0, h / 2, z)), k % 2 == 0 and SEAT_BLUE or SEAT_BLUE_DARK)
		for x = -homeWidth / 2 + 1.5, homeWidth / 2 - 1.5, 2.2 do
			addFan(HOME + Vector3.new(x, h, z))
		end
	end

	-- Big scoreboard in left-center field
	local boardPos = fieldPoint(-28, fenceDistAt(-28) + 45) + Vector3.new(0, 30, 0)
	local boardCFrame = facingHome(boardPos)
	local boardPart = block("Scoreboard", Vector3.new(64, 32, 2), boardCFrame, DARK, Enum.Material.SmoothPlastic)
	for _, x in { -20, 20 } do
		block("ScoreboardPost", Vector3.new(2, 14, 2), boardCFrame * CFrame.new(x, -23, 0), STEEL, Enum.Material.Metal)
	end
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Front
	boardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardGui.PixelsPerStud = 20
	boardGui.Parent = boardPart
	local function boardLine(y, color)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, y, 0)
		label.Size = UDim2.new(0.94, 0, 0.2, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = ""
		label.Parent = boardGui
		return label
	end
	local board = {
		title = boardLine(0.04, GOLD),
		batter = boardLine(0.28, WHITE),
		stats = boardLine(0.52, Color3.fromRGB(120, 230, 255)),
		last = boardLine(0.76, Color3.fromRGB(255, 160, 60)),
	}
	board.title.Text = "HOME RUN DERBY"
	board.last.Text = "LAST HIT: -"

	field.Parent = workspace
	return board
end

local board = buildField()

---------------------------------------------------------------------
-- Saving: baseballs, home runs, longest hit, and what you bought
---------------------------------------------------------------------
local store = nil
local storeOk, storeErr = pcall(function()
	store = DataStoreService:GetDataStore("HomeRunDerby_v1")
end)
if not storeOk then
	warn("[Baseball] Saving is OFF: " .. tostring(storeErr))
end

local profiles = {}  -- [Player] = their data
local canSave = {}   -- [Player] = true only if their data loaded OK (so we never wipe a save)
local warnedAboutSaving = false

local function defaultData()
	return { baseballs = 0, homers = 0, longest = 0, owned = { wood = true }, equipped = "wood" }
end

local function loadData(plr)
	local data = defaultData()
	if not store then
		return data, false
	end
	for _ = 1, 3 do
		local ok, saved = pcall(function()
			return store:GetAsync("player_" .. plr.UserId)
		end)
		if ok then
			if type(saved) == "table" then
				data.baseballs = tonumber(saved.baseballs) or 0
				data.homers = tonumber(saved.homers) or 0
				data.longest = tonumber(saved.longest) or 0
				if type(saved.owned) == "table" then
					for id, has in saved.owned do
						if ITEMS_BY_ID[id] and has then
							data.owned[id] = true
						end
					end
				end
				if type(saved.equipped) == "string" and data.owned[saved.equipped] then
					data.equipped = saved.equipped
				end
			end
			return data, true
		end
		if not warnedAboutSaving then
			warnedAboutSaving = true
			warn("[Baseball] Saving is OFF. To turn it on: publish the game, then Home > Game Settings > Security > "
				.. "turn on 'Enable Studio Access to API Services'. Error: " .. tostring(saved))
		end
		task.wait(1)
	end
	return data, false
end

local function saveData(plr)
	local data = profiles[plr]
	if not store or not data or not canSave[plr] then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("player_" .. plr.UserId, {
			baseballs = data.baseballs,
			homers = data.homers,
			longest = data.longest,
			owned = data.owned,
			equipped = data.equipped,
		})
	end)
	if not ok then
		warn("[Baseball] Could not save " .. plr.Name .. ": " .. tostring(err))
	end
end

local function luckFor(data)
	local luck = BASE_LUCK
	for id in data.owned do
		local item = ITEMS_BY_ID[id]
		if item and item.kind == "luck" and item.luck > luck then
			luck = item.luck
		end
	end
	return luck
end

local function batFor(plr)
	local data = profiles[plr]
	return ITEMS_BY_ID[data and data.equipped or "wood"] or ITEMS_BY_ID.wood
end

-- Copies a player's data to the leaderboard and to attributes the player's screen can read
local function syncPlayer(plr)
	local data = profiles[plr]
	local stats = plr:FindFirstChild("leaderstats")
	if not data or not stats then
		return
	end
	stats.Baseballs.Value = data.baseballs
	stats.Homers.Value = data.homers
	stats.Longest.Value = data.longest
	local owned = {}
	for id in data.owned do
		table.insert(owned, id)
	end
	plr:SetAttribute("Owned", table.concat(owned, ","))
	plr:SetAttribute("EquippedBat", data.equipped)
	plr:SetAttribute("Luck", luckFor(data))
end

-- Gives baseballs, with a lucky chance to double them
local function award(plr, amount)
	local data = profiles[plr]
	if not data or amount <= 0 then
		return 0, false
	end
	local lucky = math.random() < luckFor(data)
	if lucky then
		amount *= 2
	end
	data.baseballs += amount
	syncPlayer(plr)
	return amount, lucky
end

---------------------------------------------------------------------
-- Game state and the big scoreboard
---------------------------------------------------------------------
local batter = nil        -- the Player who is batting right now
local outs = 0
local homers = 0
local pitchCount = 0
local activePitch = nil
local nextPitchAt = 0
local savedMovement = nil -- the batter's normal walk speed, so we can give it back
local boardFlashToken = 0

local function updateScoreboard()
	remotes:SetAttribute("BatterUserId", batter and batter.UserId or 0)
	remotes:SetAttribute("BatterName", batter and batter.DisplayName or "")
	remotes:SetAttribute("Outs", outs)
	remotes:SetAttribute("Homers", homers)
	board.batter.Text = batter and ("AT BAT: " .. string.upper(batter.DisplayName)) or "STEP UP TO BAT!"
	board.stats.Text = string.format("HR %d     OUTS %d/%d", homers, outs, MAX_OUTS)
end

local function flashBoard()
	boardFlashToken += 1
	local token = boardFlashToken
	board.title.Text = "HOMERUN!!!"
	board.title.TextColor3 = Color3.fromRGB(255, 70, 70)
	task.delay(3.5, function()
		if token == boardFlashToken then
			board.title.Text = "HOME RUN DERBY"
			board.title.TextColor3 = GOLD
		end
	end)
end

local function sendResult(info)
	info.batterUserId = batter and batter.UserId or 0
	info.batterName = batter and batter.DisplayName or ""
	ResultEvent:FireAllClients(info)
end

local function addOut(plr)
	outs += 1
	updateScoreboard()
	if outs >= MAX_OUTS then
		nextPitchAt = math.max(nextPitchAt, os.clock() + 6)
		task.delay(2.5, function()
			if batter ~= plr then
				return
			end
			sendResult({
				kind = "ROUNDOVER",
				text = string.format("ROUND OVER! %d HOME RUN%s", homers, homers == 1 and "" or "S"),
			})
			outs = 0
			homers = 0
			updateScoreboard()
		end)
	end
end

-- Turns swing timing into a ball flight.
-- offset = how early (negative) or late (positive) the swing was, in seconds.
local function computeHit(offset, bat)
	local window = SWING_WINDOW * bat.timing
	local quality = 1 - math.abs(offset) / window -- 1 = perfect, 0 = barely touched it
	local speed = (80 + 85 * quality ^ 1.1 + math.random(-4, 4)) * POWER * bat.power
	local spread = 6 + 22 * (1 - quality)
	local launchDeg = math.clamp(26 + (math.random() * 2 - 1) * spread, 6, 60)
	-- Early swings pull the ball to left field, late swings go to right field
	local sprayDeg = (offset / window) * 50 + (math.random() * 2 - 1) * 6

	local launch = math.rad(launchDeg)
	local spray = math.rad(sprayDeg)
	local dir = Vector3.new(math.sin(spray), 0, -math.cos(spray))
	local vh = speed * math.cos(launch)
	local vy = speed * math.sin(launch)
	local h0 = 3
	local tLand = (vy + math.sqrt(vy * vy + 2 * BALL_GRAVITY * (h0 - 0.45))) / BALL_GRAVITY
	local carry = vh * tLand
	local fence = fenceDistAt(sprayDeg)

	local hit = {
		launchPos = HOME + Vector3.new(0, h0, 0),
		velocity = dir * vh + Vector3.new(0, vy, 0),
		gravity = BALL_GRAVITY,
		flightTime = tLand,
		distance = math.floor(carry * FEET_PER_STUD),
	}

	if math.abs(sprayDeg) > 45 then
		hit.kind = "FOUL"
		hit.flightTime = math.min(tLand, 2.5)
	elseif carry > fence then
		local tFence = fence / vh
		local heightAtFence = h0 + vy * tFence - 0.5 * BALL_GRAVITY * tFence * tFence
		if heightAtFence > FENCE_HEIGHT + 0.5 then
			hit.kind = "HOMER"
		else
			hit.kind = "WALL"
			hit.flightTime = tFence
			hit.distance = math.floor(fence * FEET_PER_STUD)
		end
	else
		hit.kind = "OUT"
	end
	return hit, quality
end

---------------------------------------------------------------------
-- Who is batting?
---------------------------------------------------------------------
local function inBox(plr, margin)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return false
	end
	local d = root.Position - BOX_CENTER
	return math.abs(d.X) <= BOX_SIZE.X / 2 + margin and math.abs(d.Z) <= BOX_SIZE.Z / 2 + margin and d.Y < 10
end

-- Batters stand still so a bump on the joystick doesn't walk them out of the box
local function lockBatter(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	savedMovement = {
		hum = hum,
		walkSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
		autoRotate = hum.AutoRotate,
	}
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.AutoRotate = false
end

local function unlockBatter()
	local s = savedMovement
	savedMovement = nil
	if s and s.hum.Parent then
		s.hum.WalkSpeed = s.walkSpeed
		s.hum.JumpPower = s.jumpPower
		s.hum.JumpHeight = s.jumpHeight
		s.hum.AutoRotate = s.autoRotate
	end
end

local function setBatter(plr)
	batter = plr
	outs = 0
	homers = 0
	nextPitchAt = os.clock() + 1.5
	local char = plr.Character
	if char then
		-- Stand in the box facing home plate
		local standAt = BOX_CENTER + Vector3.new(0, 3, 0)
		char:PivotTo(CFrame.lookAt(standAt, standAt + Vector3.new(1, 0, 0)))
		lockBatter(char)
	end
	updateScoreboard()
end

local function clearBatter()
	batter = nil
	unlockBatter()
	if activePitch then
		activePitch.resolved = true
		activePitch = nil
	end
	outs = 0
	homers = 0
	updateScoreboard()
end

LeaveEvent.OnServerEvent:Connect(function(plr)
	if plr ~= batter then
		return
	end
	clearBatter()
	local char = plr.Character
	if char then
		char:PivotTo(CFrame.lookAt(LEAVE_SPOT, HOME + Vector3.new(0, 3, 0)))
	end
end)

---------------------------------------------------------------------
-- Pitching and swinging
---------------------------------------------------------------------
local function throwPitch()
	local b = batter
	pitchCount += 1
	local pitchType = PITCHES[math.random(1, #PITCHES)]
	local startTime = workspace:GetServerTimeNow() + PITCH_LEAD
	local target = HOME + Vector3.new((math.random() - 0.5) * 1.4, 2.8 + (math.random() - 0.5) * 1.2, 0)
	local p = { id = pitchCount, batter = b, arrive = startTime + pitchType.time, resolved = false }
	activePitch = p

	PitchEvent:FireAllClients({
		id = p.id,
		batterUserId = b.UserId,
		startTime = startTime,
		duration = pitchType.time,
		startPos = RELEASE,
		endPos = target,
		bend = pitchType.bend,
		name = pitchType.name,
		mph = math.random(pitchType.mphMin, pitchType.mphMax),
	})

	while not p.resolved and workspace:GetServerTimeNow() < p.arrive + TAKE_GRACE do
		task.wait(0.05)
	end

	if not p.resolved then
		p.resolved = true
		nextPitchAt = os.clock() + 1.2
		sendResult({ kind = "TAKE", pitchId = p.id, text = "Taken - swing at the next one!" })
	end
	if activePitch == p then
		activePitch = nil
	end
end

SwingEvent.OnServerEvent:Connect(function(plr, pitchId, offset)
	local p = activePitch
	if not p or p.resolved or p.batter ~= plr or batter ~= plr or pitchId ~= p.id then
		return
	end
	if typeof(offset) ~= "number" or offset ~= offset then
		return
	end
	offset = math.clamp(offset, -2, 1)
	p.resolved = true

	local bat = batFor(plr)
	if math.abs(offset) > SWING_WINDOW * bat.timing then
		nextPitchAt = os.clock() + 1.6
		sendResult({
			kind = "WHIFF",
			pitchId = p.id,
			swung = true,
			text = offset < 0 and "STRIKE! Too early" or "STRIKE! Too late",
		})
		addOut(plr)
		return
	end

	local hit, quality = computeHit(offset, bat)
	hit.pitchId = p.id
	hit.swung = true
	local perfect = quality > 0.9

	local reward = REWARD_CONTACT
	if hit.kind == "HOMER" then
		reward = REWARD_HOMER
	elseif hit.kind == "WALL" then
		reward = REWARD_WALL
	end
	if perfect then
		reward += REWARD_PERFECT
	end
	hit.earned, hit.lucky = award(plr, reward)

	if hit.kind == "HOMER" then
		homers += 1
		local data = profiles[plr]
		if data then
			data.homers += 1
			data.longest = math.max(data.longest, hit.distance)
			syncPlayer(plr)
		end
		hit.text = string.format("%d FT%s", hit.distance, perfect and " - PERFECT!" or "")
		board.last.Text = string.format("LAST HIT: %d FT HOMER!", hit.distance)
		flashBoard()
		nextPitchAt = os.clock() + 4.5
		updateScoreboard()
		sendResult(hit)
	else
		if hit.kind == "FOUL" then
			hit.text = "FOUL BALL - out"
			board.last.Text = "LAST HIT: FOUL"
		elseif hit.kind == "WALL" then
			hit.text = "OFF THE WALL! So close - out"
			board.last.Text = "LAST HIT: OFF THE WALL"
		else
			hit.text = string.format("Caught at %d FT - out", hit.distance)
			board.last.Text = string.format("LAST HIT: %d FT", hit.distance)
		end
		nextPitchAt = os.clock() + 2.5
		sendResult(hit)
		addOut(plr)
	end
end)

---------------------------------------------------------------------
-- The shop
---------------------------------------------------------------------
ShopFunction.OnServerInvoke = function(plr, action, itemId)
	if action == "catalog" then
		return SHOP_ITEMS
	end
	local data = profiles[plr]
	if not data then
		return false, "Still loading your stuff..."
	end
	local item = type(itemId) == "string" and ITEMS_BY_ID[itemId] or nil
	if not item then
		return false, "That item doesn't exist"
	end

	if action == "buy" then
		if data.owned[item.id] then
			return false, "You already have it!"
		end
		if data.baseballs < item.price then
			return false, string.format("You need %d more baseballs", item.price - data.baseballs)
		end
		data.baseballs -= item.price
		data.owned[item.id] = true
		if item.kind == "bat" then
			data.equipped = item.id
		end
		syncPlayer(plr)
		return true, "You got the " .. item.name .. "!"
	elseif action == "equip" then
		if item.kind ~= "bat" or not data.owned[item.id] then
			return false, "You don't own that bat yet"
		end
		data.equipped = item.id
		syncPlayer(plr)
		return true, item.name .. " equipped!"
	end
	return false, "Unknown action"
end

---------------------------------------------------------------------
-- Players joining and leaving
---------------------------------------------------------------------
local function onPlayerAdded(plr)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, statName in { "Baseballs", "Homers", "Longest" } do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Parent = stats
	end
	stats.Parent = plr
	plr:SetAttribute("Owned", "wood")
	plr:SetAttribute("EquippedBat", "wood")
	plr:SetAttribute("Luck", BASE_LUCK)

	local data, loadedOk = loadData(plr)
	if plr.Parent == nil then
		return -- they left while we were loading
	end
	profiles[plr] = data
	canSave[plr] = loadedOk
	syncPlayer(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
	if plr.Character then
		task.defer(plr.LoadCharacter, plr) -- respawn them in the dugout
	end
end

Players.PlayerRemoving:Connect(function(plr)
	if plr == batter then
		clearBatter()
	end
	saveData(plr)
	profiles[plr] = nil
	canSave[plr] = nil
end)

game:BindToClose(function()
	local pending = 0
	for _, plr in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			saveData(plr)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.1)
	end
end)

---------------------------------------------------------------------
-- Main loops
---------------------------------------------------------------------
-- Watch the batter's box
task.spawn(function()
	while true do
		task.wait(0.2)
		if batter then
			if batter.Parent == nil or not inBox(batter, 4) then
				clearBatter()
			end
		else
			for _, plr in Players:GetPlayers() do
				if inBox(plr, 0) then
					setBatter(plr)
					break
				end
			end
		end
	end
end)

-- Throw pitches while someone is batting
task.spawn(function()
	while true do
		if batter and os.clock() >= nextPitchAt then
			throwPitch()
		else
			task.wait(0.2)
		end
	end
end)

-- Save everyone every minute, just in case
task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do
			task.spawn(saveData, plr)
		end
	end
end)

-- Everything is hooked up, so now players can see the remotes
updateScoreboard()
remotes.Parent = ReplicatedStorage
