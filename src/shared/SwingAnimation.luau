--[[
	SwingAnimation  (ModuleScript in ReplicatedStorage)
	Warren's Home Run Derby: the batting swing, made in code.
	Script 2 (BaseballClient) uses this to swing the batter on every player's screen.

	The poses are right below. Change the numbers to change how the swing looks!
	Everything is measured from the batter's HumanoidRootPart (the invisible box in the
	middle of every avatar). The hands are put ON the bat first, then the arms and legs
	bend to reach them, so both hands stay on the bat the whole swing. R15 avatars only.
]]

local Swing = {}
local rad = math.rad

-- Size of the avatar these poses were made for. Bigger or smaller avatars get scaled.
local STANDARD_ARM = 1.76
local STANDARD_LEG = 1.81
local HAND_SPREAD = 0.3 -- how far each hand sits from the middle of the grip, along the bat
local ARM_HINGE = Vector3.new(1, 0, 0) -- elbows bend toward the front
local LEG_HINGE = Vector3.new(-1, 0, 0) -- knees bend toward the back

--[[
	POSES. Change these numbers to change how the swing looks!
	Directions are from the batter's point of view while they stand in the box facing the plate:
	x+ = toward the catcher, x- = toward the pitcher, y+ = up, z- = toward the plate.

	hipYaw / torsoYaw  turn the hips / the chest (+ turns toward the pitcher)
	lean / side        tip the chest forward (-) / tilt the shoulders (- drops the back shoulder)
	drop / shift       sink the hips (bends the knees) / slide the hips (- = toward the pitcher)
	grip               where the hands are (studs from the middle of the batter)
	batYaw / batPitch  where the bat points: yaw 0 = at the plate, 90 = at the pitcher,
	                   -90 = at the catcher. pitch 90 = straight up
	front / back       move each foot;  frontYaw / backYaw turn each foot (+ = toward the pitcher)
	backHeel           lift the back heel (the "squish the bug" pivot)
	lookYaw/lookPitch  where the eyes look (same directions as batYaw)
	rPole / lPole      which way each elbow points
]]
Swing.STANCE = {
	hipYaw = -5, torsoYaw = -10, lean = -12, side = 0, drop = 0.3, shift = 0.1,
	grip = Vector3.new(0.75, 0.35, -1.1), batYaw = -90, batPitch = 53,
	front = Vector3.new(-0.45, 0, 0), frontYaw = 0, back = Vector3.new(0.45, 0, 0), backYaw = 0, backHeel = 0,
	lookYaw = 88, lookPitch = -3,
	rPole = Vector3.new(0.5, -1, 0.4), lPole = Vector3.new(-1, -0.5, -1),
}
-- Load: as the pitch comes, the hands go back and the front leg lifts
Swing.LOAD = {
	hipYaw = -15, torsoYaw = -12, lean = -12, side = 0, drop = 0.25, shift = 0.2,
	grip = Vector3.new(1.05, 0.45, -1), batYaw = -95, batPitch = 53,
	front = Vector3.new(-0.6, 0.35, 0.05), frontYaw = -5, back = Vector3.new(0.45, 0, 0), backYaw = 0, backHeel = 0,
	lookYaw = 88, lookPitch = -3,
	rPole = Vector3.new(0.6, -1, 0.4), lPole = Vector3.new(1, -0.5, -1),
}
-- Stride: the front foot lands toward the pitcher. Ready to swing!
Swing.PLANT = {
	hipYaw = 0, torsoYaw = -20, lean = -14, side = 0, drop = 0.4, shift = -0.1,
	grip = Vector3.new(0.95, 0.3, -1), batYaw = -99, batPitch = 41,
	front = Vector3.new(-1.05, 0, -0.05), frontYaw = 25, back = Vector3.new(0.45, 0, 0), backYaw = 0, backHeel = 0,
	lookYaw = 85, lookPitch = -8,
	rPole = Vector3.new(0.6, -1, 0.4), lPole = Vector3.new(-1, -0.5, -1),
}
-- Launch: the hips fire, the hands drop into the slot, the bat lags behind
Swing.LAUNCH = {
	hipYaw = 30, torsoYaw = -15, lean = -10, side = -6, drop = 0.45, shift = -0.25,
	grip = Vector3.new(0.3, -0.4, -1.2), batYaw = -111, batPitch = 30,
	front = Vector3.new(-1.05, 0, -0.05), frontYaw = 25, back = Vector3.new(0.4, 0.05, 0), backYaw = 30, backHeel = 15,
	lookYaw = 40, lookPitch = -20,
	rPole = Vector3.new(0, -1, 1), lPole = Vector3.new(-0.3, -1, 0),
}
-- Contact: hips open, the bat is flat over the plate, front arm straight
Swing.CONTACT = {
	hipYaw = 55, torsoYaw = -5, lean = -10, side = -12, drop = 0.45, shift = -0.3,
	grip = Vector3.new(-0.6, -0.45, -1.15), batYaw = -9, batPitch = 4,
	front = Vector3.new(-1.05, 0, -0.05), frontYaw = 25, back = Vector3.new(0.35, 0.12, -0.05), backYaw = 65, backHeel = 30,
	lookYaw = 5, lookPitch = -30,
	rPole = Vector3.new(0.5, -0.5, 0), lPole = Vector3.new(0, -0.5, -1),
}
-- Extension: both arms reach out toward the field
Swing.EXTEND = {
	hipYaw = 80, torsoYaw = 10, lean = -12, side = -8, drop = 0.4, shift = -0.3,
	grip = Vector3.new(-1.3, -0.05, -0.3), batYaw = 81, batPitch = 3,
	front = Vector3.new(-1.05, 0, -0.05), frontYaw = 25, back = Vector3.new(0.3, 0.18, -0.1), backYaw = 80, backHeel = 40,
	lookYaw = 60, lookPitch = -5,
	rPole = Vector3.new(0.5, 0, -1), lPole = Vector3.new(0, 0, 0.5),
}
-- Finish: the bat wraps around behind the front shoulder
Swing.FINISH = {
	hipYaw = 95, torsoYaw = 35, lean = -5, side = 0, drop = 0.35, shift = -0.3,
	grip = Vector3.new(-0.7, 0.9, 0.2), batYaw = 249, batPitch = -30,
	front = Vector3.new(-1.05, 0, -0.05), frontYaw = 25, back = Vector3.new(0.25, 0.2, -0.1), backYaw = 85, backHeel = 45,
	lookYaw = 80, lookPitch = 5,
	rPole = Vector3.new(0.5, 0, -1), lPole = Vector3.new(0.5, 0, 1),
}
-- Same as STANCE, but the bat came all the way around (so it doesn't spin backward)
local STANCE_AROUND = table.clone(Swing.STANCE)
STANCE_AROUND.batYaw += 360

-- The swing, starting from wherever the batter was when they clicked.
-- ease: how that part speeds up or slows down ("in" = speeds up, "out" = slows down)
Swing.SWING_KEYS = {
	{ time = 0.00 },
	{ time = 0.05, pose = Swing.LAUNCH, ease = "in" },
	{ time = 0.10, pose = Swing.CONTACT, ease = "linear" },
	{ time = 0.17, pose = Swing.EXTEND, ease = "linear" },
	{ time = 0.32, pose = Swing.FINISH, ease = "out" },
	{ time = 0.60, pose = Swing.FINISH, ease = "linear" },
	{ time = 0.95, pose = STANCE_AROUND, ease = "inout" },
}
Swing.SWING_TIME = 0.95
Swing.CONTACT_TIME = 0.10

-- Getting ready while the pitch comes in (times are from when the ball leaves the machine)
Swing.PREP_KEYS = {
	{ time = -0.35, pose = Swing.STANCE },
	{ time = -0.10, pose = Swing.LOAD, ease = "inout" },
	{ time = 0.15, pose = Swing.PLANT, ease = "inout" },
}

local function ease(kind, a)
	if kind == "in" then
		return a * a
	elseif kind == "out" then
		return 1 - (1 - a) * (1 - a)
	elseif kind == "linear" then
		return a
	end
	return a * a * (3 - 2 * a)
end

function Swing.blend(a, b, alpha)
	local out = {}
	for key, value in a do
		out[key] = value + (b[key] - value) * alpha
	end
	return out
end

-- Where the batter is at time t in a list of keys. startPose fills in a key with no pose.
function Swing.sample(keys, t, startPose)
	if t <= keys[1].time then
		return keys[1].pose or startPose
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.time then
			local alpha = (t - a.time) / (b.time - a.time)
			return Swing.blend(a.pose or startPose, b.pose or startPose, ease(b.ease, alpha))
		end
	end
	return keys[#keys].pose or startPose
end

-- Which way something points, from yaw/pitch in degrees
local function direction(yaw, pitch)
	return (CFrame.Angles(0, rad(yaw), 0) * CFrame.Angles(rad(pitch), 0, 0)).LookVector
end

-- A frame for one bone: its Y axis runs back up the bone, its X axis is the hinge
local function boneFrame(bone, hinge)
	local y = -bone.Unit
	local x = hinge - y * hinge:Dot(y)
	if x.Magnitude < 1e-5 then
		x = Vector3.new(y.Y, -y.X, 0)
		if x.Magnitude < 1e-5 then
			x = Vector3.new(1, 0, 0)
		end
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

-- Bends a 3-joint limb (shoulder-elbow-wrist or hip-knee-ankle) so the end part
-- (hand or foot) lands on endCF. pole = which way the elbow/knee should point.
local function solveLimb(parentCF, j1, j2, j3, endCF, pole, hingeRest)
	local S = (parentCF * j1.C0).Position
	local W = (endCF * j3.C1).Position
	local a = j2.C0.Position - j1.C1.Position
	local b = j3.C0.Position - j2.C1.Position
	local L1, L2 = a.Magnitude, b.Magnitude
	local toW = W - S
	local dist = toW.Magnitude
	local u = if dist > 1e-4 then toW / dist else Vector3.new(0, -1, 0)
	local d = math.clamp(dist, math.abs(L1 - L2) + 1e-3, L1 + L2 - 1e-3)
	local along = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(L1 * L1 - along * along, 0))
	local p = pole - u * pole:Dot(u)
	if p.Magnitude < 1e-4 then
		p = Vector3.new(0, 0, 1) - u * u.Z
	end
	p = p.Unit
	local E = S + u * along + p * h
	local Wr = S + u * d
	local hinge = p:Cross(u)
	local R1 = boneFrame(E - S, hinge) * boneFrame(a, hingeRest):Inverse()
	local R2 = boneFrame(Wr - E, hinge) * boneFrame(b, hingeRest):Inverse()
	local part1 = CFrame.new(S - R1 * j1.C1.Position) * R1
	local part2 = CFrame.new(E - R2 * j2.C1.Position) * R2
	local endRot = endCF.Rotation
	local part3 = CFrame.new(Wr - endRot * j3.C1.Position) * endRot
	j1.Transform = (j1.C0:Inverse() * parentCF:Inverse() * part1 * j1.C1).Rotation
	j2.Transform = (j2.C0:Inverse() * part1:Inverse() * part2 * j2.C1).Rotation
	j3.Transform = (j3.C0:Inverse() * part2:Inverse() * part3 * j3.C1).Rotation
	return part3, E, Wr
end

-- A hand holding the bat: the bat goes through the fist, the fingers wrap the rest of the way
-- (fingers = roughly which way the forearm points)
local function handFrame(center, dir, fingers)
	fingers -= dir * fingers:Dot(dir)
	if fingers.Magnitude < 1e-4 then
		fingers = Vector3.new(0, -1, 0) - dir * -dir.Y
	end
	local y = -fingers.Unit
	local z = -dir
	return CFrame.fromMatrix(center, y:Cross(z), y, z)
end

-- Measures the avatar once: its size, and where its feet normally are
function Swing.measure(j)
	local lower = j.root.C0 * j.root.C1:Inverse()
	local function restFoot(hip, knee, ankle)
		return lower * hip.C0 * hip.C1:Inverse() * knee.C0 * knee.C1:Inverse() * ankle.C0 * ankle.C1:Inverse()
	end
	local arm = (j.rElbow.C0.Position - j.rShoulder.C1.Position).Magnitude
		+ (j.rWrist.C0.Position - j.rElbow.C1.Position).Magnitude
	local leg = (j.rKnee.C0.Position - j.rHip.C1.Position).Magnitude
		+ (j.rAnkle.C0.Position - j.rKnee.C1.Position).Magnitude
	local armScale = arm / STANDARD_ARM
	local legScale = leg / STANDARD_LEG
	return {
		scale = (armScale + legScale) / 2,
		legScale = legScale,
		rFoot = restFoot(j.rHip, j.rKnee, j.rAnkle),
		lFoot = restFoot(j.lHip, j.lKnee, j.lAnkle),
	}
end

-- Poses the whole body. j = the 15 R15 joints, rig = Swing.measure(j), p = a pose.
-- Returns where each hand ended up (the bat is welded to the right one).
function Swing.apply(j, rig, p)
	local root = CFrame.new(p.shift * rig.legScale, -p.drop * rig.legScale, 0) * CFrame.Angles(0, rad(p.hipYaw), 0)
	j.root.Transform = root
	local lowerCF = j.root.C0 * root * j.root.C1:Inverse()
	local waist = CFrame.Angles(0, rad(p.torsoYaw), 0) * CFrame.Angles(rad(p.lean), 0, 0) * CFrame.Angles(0, 0, rad(p.side))
	j.waist.Transform = waist
	local upperCF = lowerCF * j.waist.C0 * waist * j.waist.C1:Inverse()

	-- Head: keep the eyes on the ball (a neck can only turn so far)
	local rel = upperCF.Rotation:Inverse() * direction(p.lookYaw, p.lookPitch)
	local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -rad(80), rad(80))
	local pitch = math.clamp(math.asin(math.clamp(rel.Y, -1, 1)), -rad(50), rad(50))
	j.neck.Transform = j.neck.C0.Rotation:Inverse() * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * j.neck.C1.Rotation

	-- Arms: both hands on the bat. First guess, then again with the hands lined up
	-- with the forearms so the wrists don't bend in weird ways.
	local dir = direction(p.batYaw, p.batPitch)
	local grip = p.grip * rig.scale
	local rCenter = grip + dir * HAND_SPREAD
	local lCenter = grip - dir * HAND_SPREAD
	local rHand = handFrame(rCenter, dir, rCenter - (upperCF * j.rShoulder.C0).Position)
	local lHand = handFrame(lCenter, dir, lCenter - (upperCF * j.lShoulder.C0).Position)
	local _, rElbow, rWrist = solveLimb(upperCF, j.rShoulder, j.rElbow, j.rWrist, rHand, p.rPole, ARM_HINGE)
	local _, lElbow, lWrist = solveLimb(upperCF, j.lShoulder, j.lElbow, j.lWrist, lHand, p.lPole, ARM_HINGE)
	rHand = handFrame(rCenter, dir, rWrist - rElbow)
	lHand = handFrame(lCenter, dir, lWrist - lElbow)
	local rightHand = solveLimb(upperCF, j.rShoulder, j.rElbow, j.rWrist, rHand, p.rPole, ARM_HINGE)
	local leftHand = solveLimb(upperCF, j.lShoulder, j.lElbow, j.lWrist, lHand, p.lPole, ARM_HINGE)

	-- Legs: the feet stay planted (or step) while the hips turn
	local function foot(rest, offset, footYaw, heel)
		local lift = math.sin(rad(heel)) * 0.45 * rig.legScale
		return CFrame.new(rest.Position + offset * rig.legScale + Vector3.new(0, lift, 0))
			* CFrame.Angles(0, rad(footYaw), 0) * CFrame.Angles(-rad(heel), 0, 0) * rest.Rotation
	end
	local lFoot = foot(rig.lFoot, p.front, p.frontYaw, 0)
	local rFoot = foot(rig.rFoot, p.back, p.backYaw, p.backHeel)
	solveLimb(lowerCF, j.lHip, j.lKnee, j.lAnkle, lFoot, lFoot.LookVector + Vector3.new(-0.3, 0, 0), LEG_HINGE)
	solveLimb(lowerCF, j.rHip, j.rKnee, j.rAnkle, rFoot, rFoot.LookVector + Vector3.new(0.3, 0, 0), LEG_HINGE)
	return rightHand, leftHand, rHand, lHand
end

-- Puts every joint back to normal
function Swing.reset(j)
	for _, joint in j do
		joint.Transform = CFrame.new()
	end
end

Swing.HAND_SPREAD = HAND_SPREAD
return Swing
