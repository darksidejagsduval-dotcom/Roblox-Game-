--[[
	BaseballServer  (Script in ServerScriptService)
	Warren's Home Run Derby, version 4.
	Builds the whole stadium (bigger field, outfield bleachers full of fans), runs the
	ROBO-PITCHER 4000 arm machine and its pitch screen, decides hits, keeps score,
	runs the bat shop, and saves everyone's baseballs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")

---------------------------------------------------------------------
-- SETTINGS: try changing these numbers!
---------------------------------------------------------------------
local MAX_OUTS = 10          -- outs in one round
local FEET_PER_STUD = 1.5    -- 1 stud = 1.5 feet (version 3 was 2, so the field is 1.33x bigger now)
local FENCE_CENTER = 267     -- fence distance to center field (studs). 267 studs = 400 feet
local FENCE_CORNER = 220     -- fence distance down the lines. 220 studs = 330 feet
local FENCE_HEIGHT = 16      -- how tall the outfield wall is (16 studs = 24 feet)
local BALL_GRAVITY = 80      -- lower number = floatier, longer home runs
local SWING_WINDOW = 0.22    -- seconds of wiggle room on your swing timing
local POWER = 1              -- 1 = normal, 1.2 = super power for everyone
local CROWD_FILL = 0.45      -- how full the stands are (0 = empty, 1 = packed)
local NIGHT_GAME = false     -- true = play under the night sky
local GOLDEN_CHANCE = 0.08   -- chance a pitch is a GOLDEN BALL (0.08 = 8%)
local GOLDEN_MULTIPLIER = 3  -- golden balls pay this many times more

-- Baseballs you earn for hitting
local REWARD_CONTACT = 3     -- any ball you hit
local REWARD_WALL = 5        -- off the wall
local REWARD_HOMER = 15      -- home run
local REWARD_PERFECT = 5     -- extra for perfect timing
local REWARD_STREAK = 5      -- extra for each home run in a row after the first
local BASE_LUCK = 0.15       -- 0.15 = 15% chance to DOUBLE what you earn

-- The pitches the machine can throw. weight = how often (bigger = more often).
-- bend pushes the middle of the pitch's path, so the ball curves.
-- (-X breaks away from the batter, +Y floats then drops.) wobble = knuckleball dance.
local PITCHES = {
	{ name = "FASTBALL",    mphMin = 90, mphMax = 96,  time = 0.75, bend = Vector3.new(0, 0.8, 0),    weight = 4, color = Color3.fromRGB(255, 95, 80) },
	{ name = "HEATER",      mphMin = 98, mphMax = 104, time = 0.66, bend = Vector3.new(0, 0.5, 0),    weight = 1, color = Color3.fromRGB(255, 45, 45) },
	{ name = "CHANGEUP",    mphMin = 78, mphMax = 85,  time = 1.05, bend = Vector3.new(0, 2.6, 0),    weight = 2, color = Color3.fromRGB(110, 230, 120) },
	{ name = "CURVEBALL",   mphMin = 72, mphMax = 80,  time = 0.95, bend = Vector3.new(-1.5, 4.5, 0), weight = 2, color = Color3.fromRGB(90, 170, 255) },
	{ name = "SLIDER",      mphMin = 83, mphMax = 89,  time = 0.85, bend = Vector3.new(-3.5, 1, 0),   weight = 2, color = Color3.fromRGB(190, 120, 255) },
	{ name = "SINKER",      mphMin = 88, mphMax = 93,  time = 0.80, bend = Vector3.new(1.2, 0.2, 0),  weight = 1, color = Color3.fromRGB(255, 170, 60) },
	{ name = "KNUCKLEBALL", mphMin = 65, mphMax = 72,  time = 1.15, bend = Vector3.new(0, 1.6, 0),    weight = 1, color = Color3.fromRGB(240, 240, 240), wobble = 0.6 },
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

-- The field is 1.33x bigger than version 3, so hits fly 1.155x faster.
-- That keeps home runs exactly as easy as before. (Don't change this one.)
local HIT_SPEED_SCALE = math.sqrt(267 / 200)
local EXIT_VELO_PER_SPEED = 0.68 -- turns hit speed into the "EXIT VELO" MPH on the screen

local HOME = Vector3.new(0, 0, 120)              -- home plate
local MOUND = HOME + Vector3.new(0, 0, -40)      -- pitcher's mound (60.5 feet away)
local MOUND_TOP = 1
local BASE_DIST = 60                             -- 90 feet between bases
local BOX_CENTER = HOME + Vector3.new(-4.5, 0, 0)
local BOX_SIZE = Vector3.new(4, 0.1, 6)
local STAND_SPOT = HOME + Vector3.new(-3.6, 3, 0) -- where the batter stands (the swing is made for this spot)
local LEAVE_SPOT = HOME + Vector3.new(-14, 3, 10) -- where you go when you leave the box
local PITCH_LEAD = 0.6   -- wind-up time before the ball flies
local TAKE_GRACE = 0.6   -- no swing by this long after the plate = pitch taken

-- The ROBO-PITCHER 4000: an arm that spins around an axle and flings the ball
local PIVOT_HEIGHT = 3.6 -- axle height above the mound
local ARM_LENGTH = 2.9   -- axle to the ball cup
local BALL_LEAD = 0.55   -- the ball sits this far in front of the cup
local RELEASE_DEG = 8    -- arm angle when the ball lets go (0 = straight up)
local REST_DEG = -180    -- arm angle while it waits (pointing down)
local PIVOT_CF = CFrame.new(MOUND + Vector3.new(0, MOUND_TOP + PIVOT_HEIGHT, 0))
local RELEASE = PIVOT_CF * (CFrame.Angles(math.rad(RELEASE_DEG), 0, 0) * Vector3.new(0, ARM_LENGTH, BALL_LEAD))

-- Outfield bleachers (behind the wall, both sides of the batter's eye)
local BLEACHER_FROM_DEG = 11
local BLEACHER_TO_DEG = 44
local BLEACHER_ROWS = 9
local ROW_DEPTH = 3
local ROW_RISE = 2.2
local BLEACHER_GAP = 1
local BLEACHER_BASE = FENCE_HEIGHT - 2
local EYE_DIST = FENCE_CENTER + 8
local EYE_WIDTH = 80
local EYE_HEIGHT = 40
local EYE_HALF_DEG = math.deg(math.atan((EYE_WIDTH / 2) / EYE_DIST))

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
local SEAT_RED = Color3.fromRGB(170, 40, 45)
local SEAT_RED_DARK = Color3.fromRGB(140, 32, 38)
local CONCRETE = Color3.fromRGB(150, 150, 155)
local DARK = Color3.fromRGB(40, 40, 45)
local STEEL = Color3.fromRGB(170, 175, 185)
local MACHINE_YELLOW = Color3.fromRGB(255, 190, 30)
local MACHINE_ORANGE = Color3.fromRGB(255, 120, 30)
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
local AD_TEXTS = { "HOME RUN DERBY", "HIT IT HERE!", "ROBO-PITCHER 4000", "GO BIG!", "BAT SHOP OPEN", "WARREN'S BALLPARK" }

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

-- Middle of row k of the outfield bleachers, at an angle
local function bleacherRowDist(deg, k)
	return fenceDistAt(deg) + BLEACHER_GAP + ROW_DEPTH * (k + 0.5)
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
remotes:SetAttribute("Mound", MOUND)
remotes:SetAttribute("FenceCenter", FENCE_CENTER)
remotes:SetAttribute("FeetPerStud", FEET_PER_STUD)
remotes:SetAttribute("MaxOuts", MAX_OUTS)
remotes:SetAttribute("SwingWindow", SWING_WINDOW)
remotes:SetAttribute("PitchLead", PITCH_LEAD)
remotes:SetAttribute("BatterUserId", 0)
remotes:SetAttribute("BatterName", "")
remotes:SetAttribute("Outs", 0)
remotes:SetAttribute("Homers", 0)
remotes:SetAttribute("Streak", 0)

---------------------------------------------------------------------
-- Sky and sunshine
---------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = if NIGHT_GAME then 20.6 else 16.4
	Lighting.Brightness = if NIGHT_GAME then 1.2 else 2.6
	Lighting.OutdoorAmbient = if NIGHT_GAME then Color3.fromRGB(120, 125, 155) else Color3.fromRGB(135, 130, 120)
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.GlobalShadows = true

	local function effect(className, name)
		local obj = Lighting:FindFirstChildOfClass(className)
		if not obj then
			obj = Instance.new(className)
			obj.Name = name
			obj.Parent = Lighting
		end
		return obj
	end
	local atmosphere = effect("Atmosphere", "DerbyAtmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 190, 170)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	local bloom = effect("BloomEffect", "DerbyBloom")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.6
	local color = effect("ColorCorrectionEffect", "DerbyColor")
	color.Saturation = 0.12
	color.Contrast = 0.06
	local rays = effect("SunRaysEffect", "DerbySunRays")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	-- Blurry far-away stuff would hide the scoreboard, so turn that off
	for _, obj in Lighting:GetChildren() do
		if obj:IsA("DepthOfFieldEffect") then
			obj.Enabled = false
		end
	end
end
setupLighting()

---------------------------------------------------------------------
-- Build the stadium
---------------------------------------------------------------------
local partCount = 0

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
		partCount += 1
		return p
	end

	-- Flat ground paint you can walk over
	local function flat(name, size, cframe, color, material)
		local p = block(name, size, cframe, color, material)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		return p
	end

	-- Decorations nobody needs to bump into (saves the game some work)
	local function decor(p)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		return p
	end

	-- A flat circle (like the mound or the dirt around home plate)
	local function disc(name, diameter, thickness, center, color, material, parent)
		local p = block(name, Vector3.new(thickness, diameter, diameter),
			CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, parent)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	local function addSign(part, face, text, color, pixelsPerStud)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = pixelsPerStud or 20
		gui.LightInfluence = 0.3
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
	block("Grass", Vector3.new(1000, 1, 700), CFrame.new(HOME + Vector3.new(0, -0.4, -230)), GRASS, Enum.Material.Grass)
	for i = 0, 16, 2 do
		local z = -24 - i * 16 - 8
		flat("MowStripe", Vector3.new(600, 0.04, 16), CFrame.new(HOME + Vector3.new(0, 0.12, z)), GRASS_LIGHT, Enum.Material.Grass)
	end

	-- Infield dirt: the big curved arc behind the bases (built from thin wedges)
	local ARC_RADIUS = 63 -- 95 feet from the mound
	for deg = -72, 72, 6 do
		local dir = Vector3.new(math.sin(math.rad(deg)), 0, -math.cos(math.rad(deg)))
		local center = MOUND + dir * (ARC_RADIUS / 2) + Vector3.new(0, 0.13, 0)
		flat("InfieldArc", Vector3.new(2 * ARC_RADIUS * math.tan(math.rad(3)) + 0.8, 0.1, ARC_RADIUS),
			CFrame.lookAt(center, center + dir), DIRT, Enum.Material.Sand)
	end

	-- Base paths, infield grass, home plate circle
	local turn45 = CFrame.Angles(0, math.rad(45), 0)
	local baseGap = BASE_DIST / math.sqrt(2)
	local diamondCenter = HOME + Vector3.new(0, 0, -baseGap)
	flat("InfieldDirt", Vector3.new(BASE_DIST + 12, 0.1, BASE_DIST + 12), CFrame.new(diamondCenter + Vector3.new(0, 0.16, 0)) * turn45, DIRT, Enum.Material.Sand)
	flat("InfieldGrass", Vector3.new(BASE_DIST - 9, 0.1, BASE_DIST - 9), CFrame.new(diamondCenter + Vector3.new(0, 0.19, 0)) * turn45, INFIELD_GRASS, Enum.Material.Grass)
	local homeDirt = disc("HomeDirt", 22, 0.1, HOME + Vector3.new(0, 0.22, 0), DIRT, Enum.Material.Sand)
	decor(homeDirt).CastShadow = false

	local bases = {
		FirstBase = HOME + Vector3.new(baseGap, 0, -baseGap),
		SecondBase = HOME + Vector3.new(0, 0, -2 * baseGap),
		ThirdBase = HOME + Vector3.new(-baseGap, 0, -baseGap),
	}
	for name, pos in bases do
		decor(block(name, Vector3.new(2.5, 0.3, 2.5), CFrame.new(pos + Vector3.new(0, 0.35, 0)) * turn45, WHITE))
	end
	-- Home plate: a square plus a turned square makes the 5-sided shape
	flat("HomePlate", Vector3.new(2.4, 0.06, 1.2), CFrame.new(HOME + Vector3.new(0, 0.3, -0.6)), WHITE)
	flat("HomePlate", Vector3.new(1.7, 0.06, 1.7), CFrame.new(HOME + Vector3.new(0, 0.3, 0)) * turn45, WHITE)

	-- Chalk lines: batter's boxes and catcher's box
	local function chalkBox(center, sizeX, sizeZ)
		local w = 0.25
		local y = Vector3.new(0, 0.29, 0)
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
		decor(disc("OnDeckCircle", 5, 0.06, HOME + Vector3.new(side * 26, 0.14, 14), DIRT, Enum.Material.Sand)).CastShadow = false
	end

	-- Glowing batter's box (this is where you bat) and a light beam so you can find it
	local box = block("BattersBox", BOX_SIZE, CFrame.new(BOX_CENTER + Vector3.new(0, 0.32, 0)), YELLOW, Enum.Material.Neon)
	box.Transparency = 0.45
	decor(box)
	local beam = block("BatBeam", Vector3.new(40, 3.4, 3.4), CFrame.new(BOX_CENTER + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		YELLOW, Enum.Material.Neon)
	beam.Shape = Enum.PartType.Cylinder
	beam.Transparency = 0.82
	beam.CastShadow = false
	decor(beam)
	local boxSign = Instance.new("BillboardGui")
	boxSign.Size = UDim2.new(0, 220, 0, 50)
	boxSign.StudsOffset = Vector3.new(0, 6, 0)
	boxSign.AlwaysOnTop = true
	boxSign.MaxDistance = 160
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

	-- Backstop net behind home plate, with a padded wall
	local backstop = block("Backstop", Vector3.new(50, 16, 0.4), CFrame.new(HOME + Vector3.new(0, 8, 24)), DARK)
	backstop.Transparency = 0.7
	block("BackstopPad", Vector3.new(50, 4, 1), CFrame.new(HOME + Vector3.new(0, 2, 24.6)), HOME_BLUE, Enum.Material.Fabric)

	-- Mound
	disc("Mound", 14, MOUND_TOP, MOUND + Vector3.new(0, MOUND_TOP / 2, 0), DIRT, Enum.Material.Sand)
	block("PitchersRubber", Vector3.new(2.4, 0.2, 0.6), CFrame.new(MOUND + Vector3.new(0, MOUND_TOP + 0.05, 2.4)), WHITE)

	---------------------------------------------------------------------
	-- ROBO-PITCHER 4000: an arm machine with a pitch screen
	---------------------------------------------------------------------
	local machine = Instance.new("Model")
	machine.Name = "PitchingMachine"
	machine.Parent = field
	local top = MOUND + Vector3.new(0, MOUND_TOP, 0)
	local machineBase = block("Base", Vector3.new(5, 0.6, 4.4), CFrame.new(top + Vector3.new(0, 0.3, -0.2)), DARK, Enum.Material.DiamondPlate, machine)
	addSign(machineBase, Enum.NormalId.Back, "ROBO-PITCHER 4000", YELLOW, 40)
	local towerHeight = PIVOT_HEIGHT - 0.6 + 0.5 -- from the top of the base to just above the axle
	for _, x in { -1.4, 1.4 } do
		block("Tower", Vector3.new(0.5, towerHeight, 1.4), CFrame.new(top + Vector3.new(x, 0.6 + towerHeight / 2, 0)),
			MACHINE_YELLOW, Enum.Material.Metal, machine)
	end
	local axle = block("Axle", Vector3.new(3.4, 0.8, 0.8), PIVOT_CF, STEEL, Enum.Material.Metal, machine)
	axle.Shape = Enum.PartType.Cylinder
	local motor = block("Motor", Vector3.new(1.2, 1.5, 1.5), PIVOT_CF * CFrame.new(2.25, 0, 0), DARK, Enum.Material.Metal, machine)
	addSign(motor, Enum.NormalId.Back, "4000", MACHINE_YELLOW, 40)
	local light = block("PitchLight", Vector3.new(0.7, 0.7, 0.7), PIVOT_CF * CFrame.new(2.25, 1.15, 0),
		Color3.fromRGB(60, 255, 90), Enum.Material.Neon, machine)
	light.Shape = Enum.PartType.Ball
	-- Ball hopper with a feed tube down to where the arm picks up the ball
	local hopper = block("Hopper", Vector3.new(1.6, 1.4, 1.6), CFrame.new(top + Vector3.new(-2.6, 2.6, -1.2)),
		Color3.fromRGB(200, 230, 255), Enum.Material.Glass, machine)
	hopper.Transparency = 0.5
	for i = 1, 3 do
		local ball = block("HopperBall", Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(top + Vector3.new(-2.6 + (i - 2) * 0.4, 2.3 + (i % 2) * 0.4, -1.2)), WHITE, Enum.Material.SmoothPlastic, machine)
		ball.Shape = Enum.PartType.Ball
	end
	local feedStart = top + Vector3.new(-2.6, 1.9, -1.2)
	local feedEnd = top + Vector3.new(-0.5, 0.9, -0.6)
	block("FeedTube", Vector3.new(0.5, 0.5, (feedEnd - feedStart).Magnitude), CFrame.lookAt((feedStart + feedEnd) / 2, feedEnd),
		STEEL, Enum.Material.Metal, machine)
	block("HopperLeg", Vector3.new(0.3, 1.9, 0.3), CFrame.new(top + Vector3.new(-2.6, 0.95, -1.2)), STEEL, Enum.Material.Metal, machine)

	-- The arm. Every arm part remembers where it sits on the arm (ArmOffset),
	-- so each player's screen can spin the arm around the axle.
	local armModel = Instance.new("Model")
	armModel.Name = "Arm"
	armModel.Parent = machine
	local restSpin = PIVOT_CF * CFrame.Angles(math.rad(REST_DEG), 0, 0)
	local function armPart(name, size, offset, color, material)
		local p = block(name, size, restSpin * offset, color, material, armModel)
		p:SetAttribute("ArmOffset", offset)
		p.CastShadow = false
		return decor(p)
	end
	armPart("ArmBeam", Vector3.new(0.45, ARM_LENGTH + 0.3, 0.45), CFrame.new(0, ARM_LENGTH / 2, 0), MACHINE_ORANGE, Enum.Material.Metal)
	armPart("ArmStripe", Vector3.new(0.5, ARM_LENGTH * 0.7, 0.12), CFrame.new(0, ARM_LENGTH / 2, 0.2), Color3.fromRGB(255, 240, 90), Enum.Material.Neon)
	armPart("Cup", Vector3.new(0.95, 0.5, 0.95), CFrame.new(0, ARM_LENGTH, 0), DARK, Enum.Material.Metal)
	armPart("Counterweight", Vector3.new(1, 1.1, 0.9), CFrame.new(0, -1.3, 0), DARK, Enum.Material.DiamondPlate)
	machine:SetAttribute("PivotCF", PIVOT_CF)
	machine:SetAttribute("ArmLength", ARM_LENGTH)
	machine:SetAttribute("BallLead", BALL_LEAD)
	machine:SetAttribute("RestDeg", REST_DEG)
	machine:SetAttribute("ReleaseDeg", RELEASE_DEG)

	-- Pitch screen: shows what's coming and how fast
	local screenPos = MOUND + Vector3.new(6.5, MOUND_TOP + 5.2, 1)
	block("ScreenPost", Vector3.new(0.5, 5.2, 0.5), CFrame.new(MOUND + Vector3.new(6.5, MOUND_TOP + 1.6, 1.3)), STEEL, Enum.Material.Metal, machine)
	local screen = block("Screen", Vector3.new(7, 4.2, 0.4), CFrame.lookAt(screenPos, screenPos + Vector3.new(0, 0, 1)), DARK, Enum.Material.SmoothPlastic, machine)
	local screenGui = Instance.new("SurfaceGui")
	screenGui.Face = Enum.NormalId.Front
	screenGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	screenGui.PixelsPerStud = 30
	screenGui.LightInfluence = 0
	screenGui.Brightness = 1.5
	screenGui.Parent = screen
	local function screenLabel(y, height, font, color)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, y, 0)
		label.Size = UDim2.new(0.92, 0, height, 0)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = ""
		label.Parent = screenGui
		return label
	end
	local screenLabels = {
		name = screenLabel(0.05, 0.3, Enum.Font.LuckiestGuy, YELLOW),
		speed = screenLabel(0.36, 0.42, Enum.Font.Arcade, Color3.fromRGB(120, 255, 140)),
		info = screenLabel(0.8, 0.16, Enum.Font.GothamBold, WHITE),
	}
	machine.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- every player always gets the machine

	-- Foul lines and foul poles
	for _, side in { -1, 1 } do
		local deg = 45 * side
		local dist = fenceDistAt(deg)
		local mid = fieldPoint(deg, dist / 2) + Vector3.new(0, 0.28, 0)
		flat("FoulLine", Vector3.new(0.5, 0.04, dist), CFrame.lookAt(mid, fieldPoint(deg, dist) + Vector3.new(0, 0.28, 0)), WHITE)
		local polePos = fieldPoint(deg, dist + 0.5)
		decor(block("FoulPole", Vector3.new(1.4, 70, 1.4), CFrame.new(polePos + Vector3.new(0, 35, 0)), YELLOW, Enum.Material.Neon))
	end

	-- Outfield wall, warning track, and ads
	local step = 2
	local adIndex = 0
	for deg = -45, 45 - step, step do
		local d1, d2 = fenceDistAt(deg), fenceDistAt(deg + step)
		local p1, p2 = fieldPoint(deg, d1), fieldPoint(deg + step, d2)
		local length = (p2 - p1).Magnitude + 0.5
		local mid = (p1 + p2) / 2
		local along = CFrame.lookAt(mid, mid + (p2 - p1))
		local fence = block("Fence", Vector3.new(1.5, FENCE_HEIGHT, length), along + Vector3.new(0, FENCE_HEIGHT / 2, 0), FENCE_GREEN, Enum.Material.Fabric)
		block("FenceTop", Vector3.new(1.7, 0.6, length), along + Vector3.new(0, FENCE_HEIGHT + 0.3, 0), YELLOW)
		local index = (deg + 45) / step
		if index % 5 == 2 and math.abs(deg) > 6 then
			adIndex += 1
			local ad = addSign(fence, Enum.NormalId.Right, AD_TEXTS[(adIndex - 1) % #AD_TEXTS + 1], YELLOW, 8)
			ad.Size = UDim2.new(0.9, 0, 0.3, 0)
			ad.Position = UDim2.new(0.05, 0, 0.12, 0)
		end

		local t1, t2 = fieldPoint(deg, d1 - 7), fieldPoint(deg + step, d2 - 7)
		local trackMid = (t1 + t2) / 2
		flat("WarningTrack", Vector3.new(13, 0.06, (t2 - t1).Magnitude + 0.6),
			CFrame.lookAt(trackMid, trackMid + (t2 - t1)) + Vector3.new(0, 0.17, 0), TRACK, Enum.Material.Sand)
	end
	for _, deg in { -45, -22, 0, 22, 45 } do
		local dist = fenceDistAt(deg)
		local pos = fieldPoint(deg, dist - 0.9) + Vector3.new(0, FENCE_HEIGHT * 0.62, 0)
		local board = block("DistanceSign", Vector3.new(10, 4.5, 0.2), facingHome(pos), FENCE_GREEN)
		addSign(board, Enum.NormalId.Front, tostring(math.floor(dist * FEET_PER_STUD / 5 + 0.5) * 5), YELLOW)
	end

	-- Batter's eye (dark wall in center field so you can see the pitch) and flags on top
	local eye = block("BattersEye", Vector3.new(EYE_WIDTH, EYE_HEIGHT, 3), facingHome(fieldPoint(0, EYE_DIST) + Vector3.new(0, EYE_HEIGHT / 2, 0)), FENCE_GREEN, Enum.Material.Fabric)
	eye.CastShadow = false
	for i, x in { -20, 0, 20 } do
		local base = (eye.CFrame * CFrame.new(x, EYE_HEIGHT / 2, 0)).Position
		decor(block("FlagPole", Vector3.new(0.5, 16, 0.5), CFrame.new(base + Vector3.new(0, 8, 0)), STEEL, Enum.Material.Metal))
		local flagColors = { HOME_BLUE, WHITE, AWAY_RED }
		decor(block("Flag", Vector3.new(6, 3.5, 0.15), eye.CFrame.Rotation + base + Vector3.new(0, 14, 0) + eye.CFrame.RightVector * 3,
			flagColors[i], Enum.Material.Fabric))
	end

	-- Remove any other spawn points so everyone spawns in the dugout
	-- (the Baseplate template's spawn pad would stick out of center field)
	for _, obj in workspace:GetDescendants() do
		if obj:IsA("SpawnLocation") then
			obj:Destroy()
		end
	end

	-- Dugouts: blue HOME dugout on the third base side (you spawn here), red VISITORS on first base side
	local function dugout(side, teamColor, title, isSpawn)
		local d = Vector3.new(math.sin(math.rad(45 * side)), 0, -math.cos(math.rad(45 * side)))
		local n = Vector3.new(side * 0.7071, 0, 0.7071)
		local center = HOME + d * 42 + n * 14
		local base = CFrame.lookAt(center, center - n) -- open side faces the field
		local back = block("DugoutBack", Vector3.new(20, 6, 0.6), base * CFrame.new(0, 3, 3), teamColor, Enum.Material.Concrete)
		addSign(back, Enum.NormalId.Front, title, WHITE)
		block("DugoutRoof", Vector3.new(21, 0.6, 7), base * CFrame.new(0, 6.3, 0.3), teamColor, Enum.Material.Metal)
		for _, x in { -10, 10 } do
			block("DugoutSide", Vector3.new(0.6, 6, 6.6), base * CFrame.new(x, 3, 0), CONCRETE, Enum.Material.Concrete)
		end
		block("Bench", Vector3.new(18, 1, 1.4), base * CFrame.new(0, 0.9, 2), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
		if isSpawn then
			local spawnPad = Instance.new("SpawnLocation")
			spawnPad.Name = "DugoutSpawn"
			spawnPad.Anchored = true
			spawnPad.Size = Vector3.new(18, 0.4, 3)
			spawnPad.CFrame = base * CFrame.new(0, 0.2, -1)
			spawnPad.Color = CONCRETE
			spawnPad.Material = Enum.Material.Concrete
			spawnPad.Neutral = true
			spawnPad.Duration = 0
			spawnPad.TopSurface = Enum.SurfaceType.Smooth
			spawnPad.Parent = field
			partCount += 1
		else
			block("DugoutFloor", Vector3.new(18, 0.4, 3), base * CFrame.new(0, 0.2, -1), CONCRETE, Enum.Material.Concrete)
		end
	end
	dugout(-1, HOME_BLUE, "HOME", true)
	dugout(1, AWAY_RED, "VISITORS", false)

	-- Fans! Each fan is a shirt and a head. They face the field.
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = field
	local fieldMiddle = HOME + Vector3.new(0, 0, -70)
	local function addFan(pos)
		if math.random() > CROWD_FILL then
			return
		end
		local phase = math.random() * math.pi * 2
		local facing = CFrame.lookAt(pos, Vector3.new(fieldMiddle.X, pos.Y, fieldMiddle.Z)).Rotation
		local shirt = block("Fan", Vector3.new(1.3, 2, 1), facing + pos + Vector3.new(0, 1, 0),
			SHIRT_COLORS[math.random(1, #SHIRT_COLORS)], Enum.Material.SmoothPlastic, crowd)
		local head = block("FanHead", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 2.5, 0)),
			SKIN_COLORS[math.random(1, #SKIN_COLORS)], Enum.Material.SmoothPlastic, crowd)
		head.Shape = Enum.PartType.Ball
		for _, part in { shirt, head } do
			decor(part)
			part.CastShadow = false
			part:SetAttribute("Phase", phase)
		end
	end

	-- Stands along the foul lines
	local ROWS = 7
	for _, side in { -1, 1 } do
		local d = Vector3.new(math.sin(math.rad(45 * side)), 0, -math.cos(math.rad(45 * side)))
		local n = Vector3.new(side * 0.7071, 0, 0.7071)
		local start, finish = 14, 205
		local middle = (start + finish) / 2
		local orient = CFrame.lookAt(Vector3.zero, d)
		block("StandWall", Vector3.new(1, 4, finish - start), CFrame.new(HOME + d * middle + n * 22.5 + Vector3.new(0, 2, 0)) * orient, FENCE_GREEN)
		for k = 0, ROWS - 1 do
			local h = 2 + 2 * k
			local offset = 24 + 3 * k + 1.5
			block("Seats", Vector3.new(3, h, finish - start), CFrame.new(HOME + d * middle + n * offset + Vector3.new(0, h / 2, 0)) * orient,
				k % 2 == 0 and SEAT_BLUE or SEAT_BLUE_DARK)
			for a = start + 1.5, finish - 1.5, 2.4 do
				addFan(HOME + d * a + n * offset + Vector3.new(0, h, 0))
			end
		end
		-- Light towers behind the stands
		for _, a in { 70, 170 } do
			local base = HOME + d * a + n * 62
			decor(disc("LightPole", 1.6, 90, base + Vector3.new(0, 45, 0), STEEL, Enum.Material.Metal))
			local lamp = block("Lights", Vector3.new(16, 8, 1.5),
				CFrame.lookAt(base + Vector3.new(0, 92, 0), fieldPoint(0, 120) + Vector3.new(0, 10, 0)), WHITE, Enum.Material.Neon)
			lamp.CastShadow = false
			decor(lamp)
		end
	end
	local homeWidth = 90
	block("StandWall", Vector3.new(homeWidth, 4, 1), CFrame.new(HOME + Vector3.new(0, 2, 27.5)), FENCE_GREEN)
	for k = 0, ROWS - 1 do
		local h = 2 + 2 * k
		local z = 29 + 3 * k + 1.5
		block("Seats", Vector3.new(homeWidth, h, 3), CFrame.new(HOME + Vector3.new(0, h / 2, z)), k % 2 == 0 and SEAT_BLUE or SEAT_BLUE_DARK)
		for x = -homeWidth / 2 + 1.5, homeWidth / 2 - 1.5, 2.4 do
			addFan(HOME + Vector3.new(x, h, z))
		end
	end

	-- Outfield bleachers: home runs land in the crowd!
	for _, side in { -1, 1 } do
		local stepDeg = 3
		local a0 = BLEACHER_FROM_DEG
		while a0 < BLEACHER_TO_DEG - 0.01 do
			local a1 = math.min(a0 + stepDeg, BLEACHER_TO_DEG)
			for k = 0, BLEACHER_ROWS - 1 do
				local h = BLEACHER_BASE + ROW_RISE * (k + 1)
				local p1 = fieldPoint(side * a0, bleacherRowDist(side * a0, k))
				local p2 = fieldPoint(side * a1, bleacherRowDist(side * a1, k))
				local mid = (p1 + p2) / 2
				block("Bleachers", Vector3.new(ROW_DEPTH, h, (p2 - p1).Magnitude + 0.4),
					CFrame.lookAt(mid, mid + (p2 - p1)) + Vector3.new(0, h / 2, 0), k % 2 == 0 and SEAT_RED or SEAT_RED_DARK)
			end
			-- back wall
			local backK = BLEACHER_ROWS
			local w1 = fieldPoint(side * a0, bleacherRowDist(side * a0, backK) - 1)
			local w2 = fieldPoint(side * a1, bleacherRowDist(side * a1, backK) - 1)
			local wallH = BLEACHER_BASE + ROW_RISE * BLEACHER_ROWS + 5
			local wmid = (w1 + w2) / 2
			block("BleacherWall", Vector3.new(1, wallH, (w2 - w1).Magnitude + 0.4),
				CFrame.lookAt(wmid, wmid + (w2 - w1)) + Vector3.new(0, wallH / 2, 0), FENCE_GREEN, Enum.Material.Concrete)
			a0 = a1
		end
		for k = 0, BLEACHER_ROWS - 1 do
			local h = BLEACHER_BASE + ROW_RISE * (k + 1)
			local dist = bleacherRowDist(side * BLEACHER_FROM_DEG, k)
			local stepAngle = math.deg(2.4 / dist)
			for a = BLEACHER_FROM_DEG + stepAngle / 2, BLEACHER_TO_DEG - stepAngle / 2, stepAngle do
				addFan(fieldPoint(side * a, bleacherRowDist(side * a, k)) + Vector3.new(0, h, 0))
			end
		end
	end

	-- Big scoreboard in left-center field, up above the bleachers
	local bleacherTop = BLEACHER_BASE + ROW_RISE * BLEACHER_ROWS + 5
	local function bigBoard(deg, name, width, height)
		local dist = bleacherRowDist(deg, BLEACHER_ROWS) + 10
		local centerY = bleacherTop + 4 + height / 2
		local boardCFrame = facingHome(fieldPoint(deg, dist) + Vector3.new(0, centerY, 0))
		local boardPart = block(name, Vector3.new(width, height, 2), boardCFrame, DARK, Enum.Material.SmoothPlastic)
		local frame = block(name .. "Frame", Vector3.new(width + 2, height + 2, 1.5), boardCFrame * CFrame.new(0, 0, 0.5), STEEL, Enum.Material.Metal)
		frame.CastShadow = false
		for _, x in { -width / 3, width / 3 } do
			local postHeight = centerY - height / 2
			block(name .. "Post", Vector3.new(2, postHeight, 2), boardCFrame * CFrame.new(x, -height / 2 - postHeight / 2, 0.5), STEEL, Enum.Material.Metal)
		end
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 16
		gui.LightInfluence = 0
		gui.Brightness = 1.4
		gui.Parent = boardPart
		return gui
	end
	local function boardLine(gui, y, height, color)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, y, 0)
		label.Size = UDim2.new(0.94, 0, height, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = ""
		label.Parent = gui
		return label
	end
	local scoreGui = bigBoard(-27, "Scoreboard", 70, 36)
	local board = {
		title = boardLine(scoreGui, 0.04, 0.2, GOLD),
		batter = boardLine(scoreGui, 0.28, 0.2, WHITE),
		stats = boardLine(scoreGui, 0.52, 0.2, Color3.fromRGB(120, 230, 255)),
		last = boardLine(scoreGui, 0.76, 0.2, Color3.fromRGB(255, 160, 60)),
	}
	board.title.Text = "HOME RUN DERBY"
	board.last.Text = "LAST HIT: -"

	local leaderGui = bigBoard(27, "LeaderBoard", 56, 30)
	local leaders = {
		title = boardLine(leaderGui, 0.05, 0.22, GOLD),
		lines = {
			boardLine(leaderGui, 0.32, 0.19, WHITE),
			boardLine(leaderGui, 0.54, 0.19, WHITE),
			boardLine(leaderGui, 0.76, 0.19, WHITE),
		},
	}
	leaders.title.Text = "LONGEST HOME RUNS"
	leaders.lines[1].Text = "BE THE FIRST!"

	field.Parent = workspace
	return board, leaders, screenLabels, beam, boxSign
end

local board, leaderBoard, machineScreen, batBeam, batSign = buildField()
print(string.format("[Baseball] Stadium built with %d parts", partCount))

local function setScreen(name, speed, info, color)
	machineScreen.name.Text = name
	machineScreen.name.TextColor3 = color or YELLOW
	machineScreen.speed.Text = speed
	machineScreen.info.Text = info
end
setScreen("ROBO-PITCHER", "READY", "STEP INTO THE BOX!")

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
-- Game state and the big scoreboards
---------------------------------------------------------------------
local batter = nil        -- the Player who is batting right now
local outs = 0
local homers = 0
local streak = 0          -- home runs in a row
local roundEarned = 0
local roundLongest = 0
local pitchCount = 0
local activePitch = nil
local nextPitchAt = 0
local savedMovement = nil -- the batter's normal walk speed, so we can give it back
local boardFlashToken = 0
local topHomers = {}      -- longest home runs since the server started: { name, distance }
local roundId = 0         -- changes every time a round starts, so old timers can tell
local afterRound          -- (filled in below) gives the box to a friend who's waiting

local function updateScoreboard()
	remotes:SetAttribute("BatterUserId", batter and batter.UserId or 0)
	remotes:SetAttribute("BatterName", batter and batter.DisplayName or "")
	remotes:SetAttribute("Outs", outs)
	remotes:SetAttribute("Homers", homers)
	remotes:SetAttribute("Streak", streak)
	board.batter.Text = batter and ("AT BAT: " .. string.upper(batter.DisplayName)) or "STEP UP TO BAT!"
	board.stats.Text = string.format("HR %d     OUTS %d/%d", homers, outs, MAX_OUTS)
	batBeam.Transparency = if batter then 1 else 0.82
	batSign.Enabled = batter == nil
end

local function updateLeaders()
	for i, line in leaderBoard.lines do
		local entry = topHomers[i]
		line.Text = if entry then string.format("%d. %s  %d FT", i, string.upper(entry.name), entry.distance) else ""
	end
end

local function recordHomer(name, distance)
	table.insert(topHomers, { name = name, distance = distance })
	table.sort(topHomers, function(a, b)
		return a.distance > b.distance
	end)
	while #topHomers > 3 do
		table.remove(topHomers)
	end
	updateLeaders()
end

local function flashBoard(text, color)
	boardFlashToken += 1
	local token = boardFlashToken
	board.title.Text = text
	board.title.TextColor3 = color
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
	streak = 0
	updateScoreboard()
	if outs >= MAX_OUTS then
		nextPitchAt = math.max(nextPitchAt, os.clock() + 7)
		local thisRound = roundId
		task.delay(2.5, function()
			if batter ~= plr or roundId ~= thisRound then
				return
			end
			sendResult({
				kind = "ROUNDOVER",
				text = string.format("ROUND OVER! %d HOME RUN%s", homers, homers == 1 and "" or "S"),
				homers = homers,
				longest = roundLongest,
				earned = roundEarned,
			})
			outs = 0
			homers = 0
			streak = 0
			roundEarned = 0
			roundLongest = 0
			roundId += 1
			updateScoreboard()
			afterRound(plr)
		end)
	end
end

-- How high the stuff past the outfield wall is at an angle and distance
-- (the bleachers, the batter's eye, or plain grass)
local function standsHeightAt(deg, dist)
	local a = math.abs(deg)
	local fence = fenceDistAt(deg)
	if a >= BLEACHER_FROM_DEG and a <= BLEACHER_TO_DEG and dist >= fence then
		local k = math.floor((dist - fence - BLEACHER_GAP) / ROW_DEPTH)
		if k < BLEACHER_ROWS then
			return BLEACHER_BASE + ROW_RISE * (math.max(k, 0) + 1)
		elseif k == BLEACHER_ROWS then
			return BLEACHER_BASE + ROW_RISE * BLEACHER_ROWS + 5 -- the back wall
		end
	end
	if a <= EYE_HALF_DEG and math.abs(dist - EYE_DIST) <= 1.5 then
		return EYE_HEIGHT
	end
	return 0.45
end

-- Turns swing timing into a ball flight.
-- offset = how early (negative) or late (positive) the swing was, in seconds.
local function computeHit(offset, bat)
	local window = SWING_WINDOW * bat.timing
	local quality = math.clamp(1 - math.abs(offset) / window, 0, 1) -- 1 = perfect, 0 = barely touched it
	local rawSpeed = 80 + 85 * quality ^ 1.1 + math.random(-4, 4)
	local speed = rawSpeed * POWER * bat.power * HIT_SPEED_SCALE
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
	local launchPos = HOME + Vector3.new(0, h0, 0)
	local velocity = dir * vh + Vector3.new(0, vy, 0)

	local hit = {
		launchPos = launchPos,
		velocity = velocity,
		gravity = BALL_GRAVITY,
		flightTime = tLand,
		distance = math.floor(carry * FEET_PER_STUD),
		exitVelo = math.floor(rawSpeed * bat.power * POWER * EXIT_VELO_PER_SPEED + 0.5),
		launchDeg = math.floor(launchDeg + 0.5),
	}

	if math.abs(sprayDeg) > 45 then
		hit.kind = "FOUL"
		hit.flightTime = math.min(tLand, 6)
	elseif carry > fence then
		local tFence = fence / vh
		local heightAtFence = h0 + vy * tFence - 0.5 * BALL_GRAVITY * tFence * tFence
		if heightAtFence > FENCE_HEIGHT + 0.5 then
			hit.kind = "HOMER"
			-- Find where it comes down: in the bleachers, off the batter's eye, or out of the park
			local t = tFence
			while t < tLand do
				t += 1 / 120
				local pos = launchPos + velocity * t + Vector3.new(0, -0.5 * BALL_GRAVITY * t * t, 0)
				local flatDist = Vector3.new(pos.X - HOME.X, 0, pos.Z - HOME.Z).Magnitude
				if pos.Y <= standsHeightAt(sprayDeg, flatDist) then
					break
				end
			end
			t = math.min(t, tLand)
			hit.flightTime = t
			hit.landPos = launchPos + velocity * t + Vector3.new(0, -0.5 * BALL_GRAVITY * t * t, 0)
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
	roundId += 1
	outs = 0
	homers = 0
	streak = 0
	roundEarned = 0
	roundLongest = 0
	nextPitchAt = os.clock() + 1.5
	local char = plr.Character
	if char then
		-- Stand in the box facing home plate
		char:PivotTo(CFrame.lookAt(STAND_SPOT, STAND_SPOT + Vector3.new(1, 0, 0)))
		lockBatter(char)
	end
	setScreen("ROBO-PITCHER", "READY", "BATTER UP: " .. string.upper(plr.DisplayName))
	updateScoreboard()
end

local function clearBatter()
	batter = nil
	roundId += 1
	unlockBatter()
	if activePitch then
		activePitch.resolved = true
		activePitch = nil
	end
	outs = 0
	homers = 0
	streak = 0
	setScreen("ROBO-PITCHER", "READY", "STEP INTO THE BOX!")
	updateScoreboard()
end

-- After a round, a friend waiting by the box gets the next turn
afterRound = function(plr)
	for _, other in Players:GetPlayers() do
		if other ~= plr and inBox(other, 3) then
			clearBatter()
			local char = plr.Character
			if char then
				char:PivotTo(CFrame.lookAt(LEAVE_SPOT, HOME + Vector3.new(0, 3, 0)))
			end
			return
		end
	end
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
local totalWeight = 0
for _, pitch in PITCHES do
	totalWeight += pitch.weight or 1
end

local function pickPitch()
	local roll = math.random() * totalWeight
	for _, pitch in PITCHES do
		roll -= pitch.weight or 1
		if roll <= 0 then
			return pitch
		end
	end
	return PITCHES[1]
end

local function throwPitch()
	local b = batter
	pitchCount += 1
	local pitchType = pickPitch()
	local golden = math.random() < GOLDEN_CHANCE
	local mph = math.random(pitchType.mphMin, pitchType.mphMax)
	local startTime = workspace:GetServerTimeNow() + PITCH_LEAD
	local target = HOME + Vector3.new((math.random() - 0.5) * 1.4, 2.8 + (math.random() - 0.5) * 1.2, 0)
	local p = { id = pitchCount, batter = b, arrive = startTime + pitchType.time, resolved = false, golden = golden }
	activePitch = p

	setScreen(pitchType.name, tostring(mph) .. " MPH",
		if golden then string.format("GOLDEN BALL! x%d", GOLDEN_MULTIPLIER) else "PITCH #" .. pitchCount,
		if golden then GOLD else pitchType.color)

	PitchEvent:FireAllClients({
		id = p.id,
		batterUserId = b.UserId,
		startTime = startTime,
		duration = pitchType.time,
		startPos = RELEASE,
		endPos = target,
		bend = pitchType.bend,
		wobble = pitchType.wobble or 0,
		name = pitchType.name,
		color = pitchType.color,
		mph = mph,
		golden = golden,
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
			offset = offset,
			text = offset < 0 and "STRIKE! Too early" or "STRIKE! Too late",
		})
		addOut(plr)
		return
	end

	local hit, quality = computeHit(offset, bat)
	hit.pitchId = p.id
	hit.swung = true
	hit.offset = offset
	hit.golden = p.golden
	local perfect = quality > 0.9
	hit.perfect = perfect

	local reward = REWARD_CONTACT
	if hit.kind == "HOMER" then
		streak += 1
		reward = REWARD_HOMER + REWARD_STREAK * (streak - 1)
	elseif hit.kind == "WALL" then
		reward = REWARD_WALL
	end
	if perfect then
		reward += REWARD_PERFECT
	end
	if p.golden then
		reward *= GOLDEN_MULTIPLIER
	end
	hit.earned, hit.lucky = award(plr, reward)
	roundEarned += hit.earned

	if hit.kind == "HOMER" then
		homers += 1
		hit.streak = streak
		roundLongest = math.max(roundLongest, hit.distance)
		local data = profiles[plr]
		if data then
			if data.homers == 0 then
				hit.firstHomer = true
			elseif hit.distance > data.longest then
				hit.newBest = true
			end
			data.homers += 1
			data.longest = math.max(data.longest, hit.distance)
			syncPlayer(plr)
		end
		hit.text = string.format("%d FT%s", hit.distance, perfect and " - PERFECT!" or "")
		board.last.Text = string.format("LAST HIT: %d FT HOMER!", hit.distance)
		flashBoard(if streak >= 2 then string.format("%d IN A ROW!!!", streak) else "HOMERUN!!!", Color3.fromRGB(255, 70, 70))
		recordHomer(plr.DisplayName, hit.distance)
		setScreen("HOME RUN!", string.format("%d FT", hit.distance), string.format("EXIT VELO %d MPH", hit.exitVelo), GOLD)
		nextPitchAt = os.clock() + math.max(4.5, math.min(hit.flightTime, 6) + 1)
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
		nextPitchAt = os.clock() + math.max(2.5, math.min(hit.flightTime, 6) + 0.8)
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
