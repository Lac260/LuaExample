# LuaExample
Roblox LUA Example

```-- [[ VARIALBES ]] --
-- SERVICES --
local TweenService = game:GetService("TweenService")

-- CONSTANTS --
local Module = {}
local Door = {}

local Event = require(script.Event)
local Scheduler = require(script.Scheduler)

local AdditionalFallback = 1

local DefaultMovementTime = 2
local DefaultTimerDelay = 5
local DefaultPreMovementDelay = 0
local DefaultPostMovementDelay = 0
local DefaultEasingStyle = Enum.EasingStyle.Linear
local DefaultEasingDirection = Enum.EasingDirection.Out
local DefaultStartOpened = false

local Mode = {Toggle = 1, Timed = 2}

-- VARIABLES --

-- [[ FUNCTIONS ]] --
-- CONSTRUCTOR --
function Module.new(doors, mode, startOpened, config, callbacks)
	mode = mode or Mode.Toggle
	startOpened = startOpened or DefaultStartOpened
	config = config or {}

	local stages = ParseDoors(doors)
	local cfg = ParseConfig(mode, config)
	local events = SetupCallbacks(callbacks)

	local self = setmetatable({
		_isOpen = false,
		_isMoving = false,
		_stages = stages,
		_config = cfg,
		_callbacks = events
	}, Door)

	-- Instant door opening (does not fire callbacks)
	if startOpened == true then
		OpenDoor(self, true)
	end

	return self
end

-- AUTOMATIC DOOR FUNCTIONS --
function Door:Trigger()
	if self._isMoving then return end
	self._isMoving = true

	local mode = self._config.Mode
	if mode == Mode.Toggle then
		if self._isOpen then
			CloseDoor(self)
		else
			OpenDoor(self)
		end
	elseif mode == Mode.Timed then
		OpenDoor(self)
	end
end

-- OPEN/CLOSE FUNCTIONS --
function OpenDoor(context, instant, textLabel)
	instant = instant or false

	-- Only allow it to move when it's not already moving and not within the same state
	if not context._isOpen then
		context._callbacks.DoorOpening:Fire()
		MoveDoors(context, function(targets) return targets._open end, true, instant)
	end
	if textLabel then
		textLabel.Text = "Open"
	end
end

function CloseDoor(context)
	-- Only allow it to move when it's not already moving and not within the same state
	if context._isOpen then
		context._callbacks.DoorClosing:Fire()
		MoveDoors(context, function(targets) return targets._close end, false, false)
		
	end
end

-- UTIL FUNCTIONS --
function MoveDoors(context, targetFunc, doOpen, inst)
	-- Iterate all stages and create the schedulers
	local function startScheduler(num, instant)
		-- Find the scheduler from the given number
		local scheduler = Scheduler.new()

		if instant ~= true then
			-- Wait for the pre movement delay
			wait(context._config.Config[num].PreMovementDelay)
		end

		-- Add the tweens to the scheduler and start listening
		local events = MoveStage(context._stages[num], context._config.Mode, context._config.Config[num], targetFunc, instant)

		scheduler:AddEvents(events)

		-- When the sheduler is finished run this function
		scheduler.OnFinish:Connect(function()
			-- Disconnect the event
			scheduler.OnFinish:DisconnectAll()

			-- Fire the door open/closed callback
			if doOpen then
				context._callbacks.DoorOpened:Fire()
			else
				context._callbacks.DoorClosed:Fire()
			end

			-- Wait for the post movement delay
			if instant ~= true then
				wait(context._config.Config[num].PostMovementDelay)
			end

			-- Get the next scheduler number, if this doesn't exist we're on the last stage		
			local n = doOpen and num + 1 or num - 1
			local isLast = context._stages[n] == nil

			if isLast then
				-- If we're on the last stage, then finish execution
				context._isOpen = doOpen
				context._isMoving = false
			else
				-- If we're not on the last stage, trigger the next stage to run
				startScheduler(n, instant)
			end
		end)

		scheduler:Start(context._config.Config[num].MovementTime + AdditionalFallback)
	end

	-- Give the signal to start the first scheduler, 
	-- reason we run it in a thread is to not block execution in the main script
	spawn(function() startScheduler(doOpen and 1 or #context._stages, inst) end)
end

function MoveStage(doors, mode, config, targetFunc, instant)
	local events = {}

	-- Calculate the tween info
	local tweenInfo = GetTweenInfo(mode, config)

	-- Iterate all doors and apply the tweening to them
	for j, door in pairs(doors) do
		local model = door._model
		local target = targetFunc(door._targets)
		if instant == true then
			model.PrimaryPart.CFrame = target.CFrame
		else
			local tween = TweenService:Create(model.PrimaryPart, tweenInfo, {CFrame = target.CFrame})
			table.insert(events, tween.Completed)
			tween:Play()
		end
	end

	return events
end

function TweenDoor(model, target, info)
	return 
end

function GetTweenInfo(mode, config)
	if mode == Mode.Toggle then
		return TweenInfo.new(config.MovementTime, config.EasingStyle, config.EasingDirection, 0, false, 0)
	elseif mode == Mode.Timed then
		if config.TimerDelay >= 0 then
			return TweenInfo.new(config.MovementTime, config.EasingStyle, config.EasingDirection, 0, true, config.TimerDelay)
		else
			return TweenInfo.new(config.MovementTime, config.EasingStyle, config.EasingDirection, 0, true, 0)
		end
	end
end

-- PARSING FUNCTIONS --
function ParseDoors(doors)
	local tbl = {}

	local doorKeys = {}
	for _, door in pairs(doors) do
		doorKeys[door.Model] = true
	end

	for _, door in pairs(doors) do
		-- Validate the model of the door
		local model = door.Model
		if model == nil or (not model:IsA("Model") and not model:IsA("BasePart")) then
			error("Model of a door must be either a Model or a BasePart in order to work.")
		end

		if model:IsA("BasePart") then
			-- If the model is a part we wrap it inside of a model and set it as the primary part
			-- Create a new instance with the same name of the part that was given.
			local m = Instance.new("Model")
			m.Name = model.Name
			m.Parent = model.Parent

			-- Reassign object structure
			model.Parent = m
			m.PrimaryPart = model
			model = m
		else
			-- However if the model is just a regular model we must make sure it's PrimaryPart is set
			if model.PrimaryPart == nil then
				error("The model must have a PrimaryPart assigned to it")
			end

			-- Unanchor all parts in the model and weldconstraint them to the root part
			WeldRecursive(doorKeys, model, model.PrimaryPart)
		end

		-- Validate the movement targets
		local open = door.OpenTarget
		local close = door.CloseTarget

		-- If it is a part alter the name so we can use it
		-- and remove it from the workspace structure into memory
		open.CanCollide = false
		open.Transparency = 1
		open.Parent = nil

		-- If it is a part alter the name so we can use it
		-- and remove it from the workspace structure into memory
		close.CanCollide = false
		close.Transparency = 1
		close.Parent = nil

		-- Validate door stage
		local stage = door.Stage or 1

		-- Add the door to the new table ready for use
		if tbl[stage] == nil then tbl[stage] = {} end
		local stg = tbl[stage]
		table.insert(stg, {
			_model = model,
			_targets = {_open = open, _close = close}
		})
	end

	-- The stages are already in order and properly defined,
	-- therefore we can clear the table from any gaps
	-- and return the table to a sequential form
	return Filter(tbl, function(i, v) return v ~= nil end, true)
end

function Filter(tbl, predicate, assoc)
	assoc = assoc or false
	local values = {}
	for index, value in pairs(tbl) do
		local search = predicate(index, value)
		if (search == true) then
			if assoc then
				table.insert(values, value)
			else
				values[index] = value
			end
		end
	end
	return values
end

function ParseConfig(mode, config)
	local cfg = {
		Mode = mode,
		Config = {}
	}

	for _,scfg in pairs(config) do
		cfg.Config[scfg.Stage] = {
			MovementTime = scfg.MovementTime or DefaultMovementTime,
			TimerDelay = scfg.TimerDelay or DefaultTimerDelay,
			PreMovementDelay = scfg.PreMovementDelay or DefaultPreMovementDelay,
			PostMovementDelay = scfg.PostMovementDelay or DefaultPostMovementDelay,
			EasingStyle = scfg.EasingStyle or DefaultEasingStyle,
			EasingDirection = scfg.EasingDrection or DefaultEasingDirection
		}
	end

	return cfg
end

function SetupCallbacks(callbacks)
	local events = {
		DoorOpening = Event.new(),
		DoorClosing = Event.new(),
		StageOpened = Event.new(),
		StageClosed = Event.new(),
		DoorOpened = Event.new(),
		DoorClosed = Event.new()
	}

	for name, func in pairs(callbacks) do
		local event = events[name]
		if event ~= nil then
			event:Connect(function(...)
				func(...)
			end)
		end
	end

	return events
end

function WeldRecursive(doors, parent, weldTo)
	for _, inst in pairs(parent:GetChildren()) do
		if inst ~= weldTo then
			if inst:IsA("BasePart") then
				local c = Instance.new("WeldConstraint")
				c.Part0 = inst
				c.Part1 = weldTo
				c.Parent = inst

				inst.Anchored = false
			elseif inst:IsA("Model") then
				if doors[inst] == true then
					assert(inst.PrimaryPart ~= nil, "Door '" .. inst:GetFullName() .. "' is missing a PrimaryPart.")

					local c = Instance.new("WeldConstraint")
					c.Part0 = inst.PrimaryPart
					c.Part1 = weldTo
					c.Parent = inst.PrimaryPart

					inst.PrimaryPart.Anchored = false
				else
					WeldRecursive(doors, inst, weldTo)
				end
			end
		end
	end
end

-- [[ INITIALIZATION ]] --
Door.__index = Door
Module.Modes = Mode
return Module```
