--[[
	RunAnimation  (LocalScript in StarterPlayer > StarterPlayerScripts)
	Warren's Home Run Derby: a baseball sprint for every player.
	Lean forward, knees up, arms pumping, a little bounce.

	It's made in code (no animation ID), so it always works in your game.
	Every player's screen moves every runner, so everybody sees everybody sprint.
	Walking slowly still uses the normal Roblox walk. R15 avatars only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

---------------------------------------------------------------------
-- SETTINGS: try changing these numbers!
---------------------------------------------------------------------
local START_SPEED = 8   -- the sprint starts when you're going faster than this (studs per second)
local FULL_SPEED = 14   -- ...and is all the way on at this speed
local STRIDE = 7        -- studs for two steps (bigger = slower, longer steps)
local LEG_SWING = 48    -- how far the legs swing forward and back (degrees)
local KNEE_KICK = 85    -- how high the back foot kicks up behind you
local ARM_PUMP = 55     -- how far the arms pump forward and back
local ELBOW_BEND = 85   -- how bent the elbows are
local LEAN = 12         -- lean forward (degrees)
local HIP_TWIST = 8     -- hips and shoulders twist a little each step
local BOUNCE = 0.15     -- up and down bounce (studs)
---------------------------------------------------------------------

local rad = math.rad
local TWO_PI = math.pi * 2

local JOINT_LIST = {
	{ "root", "LowerTorso", "Root" }, { "waist", "UpperTorso", "Waist" }, { "neck", "Head", "Neck" },
	{ "rShoulder", "RightUpperArm", "RightShoulder" }, { "rElbow", "RightLowerArm", "RightElbow" },
	{ "lShoulder", "LeftUpperArm", "LeftShoulder" }, { "lElbow", "LeftLowerArm", "LeftElbow" },
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

-- Finds the joints of an R15 avatar (nil for R6 avatars or if it hasn't loaded yet)
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

-- How bent the knee is: most bent while that leg swings forward (the foot kicks up behind)
local function knee(t)
	local swing = math.max(0, math.cos(t - 0.4))
	return -(25 + KNEE_KICK * swing * swing), swing
end

-- The running pose at step-phase theta (0 to 2*pi = two steps).
-- Angles are degrees in the avatar's own directions:
-- +X turns a leg or arm forward, a knee bends with -X, +Y turns toward the left.
local function runPose(theta)
	local s = math.sin(theta)
	local leftKnee, leftSwing = knee(theta)
	local rightKnee, rightSwing = knee(theta + math.pi)
	return {
		root = CFrame.new(0, BOUNCE * (0.4 - math.cos(2 * theta)), 0) * CFrame.Angles(0, rad(-HIP_TWIST * s), 0),
		waist = CFrame.Angles(0, rad(2 * HIP_TWIST * s), 0) * CFrame.Angles(rad(-LEAN), 0, 0),
		neck = CFrame.Angles(0, rad(-HIP_TWIST * s), 0) * CFrame.Angles(rad(LEAN * 0.6), 0, 0),
		lHip = CFrame.Angles(rad(LEG_SWING * s), 0, 0),
		rHip = CFrame.Angles(rad(-LEG_SWING * s), 0, 0),
		lKnee = CFrame.Angles(rad(leftKnee), 0, 0),
		rKnee = CFrame.Angles(rad(rightKnee), 0, 0),
		lAnkle = CFrame.Angles(rad(-20 * leftSwing + 5), 0, 0),
		rAnkle = CFrame.Angles(rad(-20 * rightSwing + 5), 0, 0),
		-- arms swing opposite to the legs
		lShoulder = CFrame.Angles(rad(-ARM_PUMP * s), 0, 0) * CFrame.Angles(0, 0, rad(-6)),
		rShoulder = CFrame.Angles(rad(ARM_PUMP * s), 0, 0) * CFrame.Angles(0, 0, rad(6)),
		lElbow = CFrame.Angles(rad(ELBOW_BEND - 15 * s), 0, 0),
		rElbow = CFrame.Angles(rad(ELBOW_BEND + 15 * s), 0, 0),
	}
end

-- Who's batting right now? (They stand still in the box, so leave them alone)
local function batterUserId()
	local folder = ReplicatedStorage:FindFirstChild("Baseball")
	return folder and folder:GetAttribute("BatterUserId") or 0
end

local runners = {} -- [character] = { joints, phase, weight }
local lastCleanup = 0

RunService.Stepped:Connect(function(_, dt)
	dt = math.min(dt, 0.1)
	local batterId = batterUserId()
	-- forget characters that are gone (respawned or left the game)
	if os.clock() - lastCleanup > 5 then
		lastCleanup = os.clock()
		for char in runners do
			if not char.Parent then
				runners[char] = nil
			end
		end
	end
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum then
			continue
		end
		local state = runners[char]
		if not state then
			state = { joints = getJoints(char), phase = 0, weight = 0, lastTry = os.clock() }
			runners[char] = state
		elseif not state.joints and os.clock() - state.lastTry > 1 then
			state.joints = getJoints(char)
			state.lastTry = os.clock()
		end
		local joints = state.joints
		if not joints or not joints.root.Parent then
			continue
		end
		if plr.UserId == batterId then
			state.weight = 0 -- the batter belongs to the swing script
			continue
		end

		-- How fast are they going across the ground?
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local onGround = math.abs(velocity.Y) < 4 and not hum.Sit and hum.Health > 0
		local goal = 0
		if onGround then
			goal = math.clamp((speed - START_SPEED) / (FULL_SPEED - START_SPEED), 0, 1)
		end
		state.weight += (goal - state.weight) * math.min(1, dt * 8)
		state.phase = (state.phase + TWO_PI * speed * dt / STRIDE) % TWO_PI
		if state.weight < 0.01 then
			continue -- the normal Roblox animation is in charge
		end

		-- Mix our sprint on top of whatever Roblox's own animation did this frame
		local pose = runPose(state.phase)
		for name, rotation in pose do
			local joint = joints[name]
			local c0 = joint.C0.Rotation
			local target = c0:Inverse() * rotation * c0
			joint.Transform = joint.Transform:Lerp(target, state.weight)
		end
	end
end)
