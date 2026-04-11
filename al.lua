local OffsetsJSON = game:HttpGet("https://offsets.ntgetwritewatch.workers.dev/offsets.json")
local HttpService = game:GetService("HttpService")
local Offsets = HttpService:JSONDecode(OffsetsJSON)

local PlayerGui = game.Players.LocalPlayer.PlayerGui
local CombatScreenGui = PlayerGui.Combat

local QTE_UI = {
	["BlockingQTE"] = {
		["QTE_Container"] = CombatScreenGui.Block,
		["Indicator"] = CombatScreenGui.Block.Inset.Indicator, 		-- what needs to align
		["Target"] =  CombatScreenGui.Block.Inset.Dodge,				-- where it needs to align
		["LastVisibleTime"] = nil,
		["Debounce"] = 0
	},
	["MagicQTE"] = {
		["QTE_Container"] = CombatScreenGui.MagicQTE,
		["RuneSlots"] = CombatScreenGui.MagicQTE.RuneSlots, 		-- RuneSlots
		["RunePieces"] =  CombatScreenGui.MagicQTE.Bag,			-- Rune pieces
		["LastVisibleTime"] = nil,
		["Debounce"] = 0,
	}
}


----------------------------------------------------- Input stuff
local function PressKey(Keycode)
	keypress(Keycode)
	task.wait(math.random(20,40) * 0.001)
	keyrelease(Keycode)
end

----------------------------------------------------- Memory reading

local function IsScreenGuiEnabled(ScreenGui)
	if not ScreenGui then return end 

	local Status = memory_read("byte", ScreenGui.Address + Offsets.ScreenGuiEnabled)
	local ScreenGuiEnabled = tonumber(Status) ~= 0
	return ScreenGuiEnabled
end

local function IsFrameVisible(Frame)
	if not Frame then return end 

	local Status = memory_read("byte", Frame.Address + Offsets.FrameVisible)
	local IsVisible = tonumber(Status) ~= 0
	return IsVisible
end

local function GetTextColor(TextLabel)
	local Address = TextLabel and TextLabel.Address 
	if not Address or Address == 0 then return nil end
	local TextColorOffset = 0xE70

	local r = memory_read("float", Address + TextColorOffset)
	local g = memory_read("float", Address + TextColorOffset + 4)
	local b = memory_read("float", Address + TextColorOffset + 8)

	return Color3.new(r, g, b)
end

local function GetName(Address)
	if not Address then return end 
	local namePointer = memory_read("uintptr_t", Address + Offsets.Name)
	local name = memory_read("string", namePointer)
	return name
end


----------------------------------------------------- Helpers

local function ColorsMatch(Color3_A, Color3_B)
	Tolerance = 0.1 

	if not Color3_A or not Color3_B then return false end

	local rDiff = math.abs(Color3_A.R - Color3_B.R)
	local gDiff = math.abs(Color3_A.G - Color3_B.G)
	local bDiff = math.abs(Color3_A.B - Color3_B.B)

	return (rDiff <= Tolerance and gDiff <= Tolerance and bDiff <= Tolerance)
end

local function AreUIObjectsAligned(ObjectA, ObjectB)
	local posA, sizeA = ObjectA.AbsolutePosition, ObjectA.AbsoluteSize
	local posB, sizeB = ObjectB.AbsolutePosition, ObjectB.AbsoluteSize

	local centerAX = posA.X + (sizeA.X / 2)
	local centerAY = posA.Y + (sizeA.Y / 2)

	local centerBX = posB.X + (sizeB.X / 2)
	local centerBY = posB.Y + (sizeB.Y / 2)

	local diffX = centerAX - centerBX
	local diffY = centerAY - centerBY

	local Distance = math.sqrt(diffX^2 + diffY^2)

	local isAligned = (math.abs(diffX) < (sizeA.X + sizeB.X) / 2) and (math.abs(diffY) < (sizeA.Y + sizeB.Y) / 2)

	return isAligned, Distance
end

local Dragging = false
local Mouse = game.Players.LocalPlayer:GetMouse()
local function _DragDebug()
	local DragText = Drawing.new("Text")
	DragText.Center = true
	DragText.Outline = true
	DragText.Size = 20 -- Optional: make it readable
	DragText.Color = Color3.fromRGB(255, 255, 255)

	while Dragging do
		local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
		local IsPressed = ismouse1pressed()        
		DragText.Text = string.format("Dragging Active | M1: %s", IsPressed and "PRESSED" or "RELEASED")        
		DragText.Color = IsPressed and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 255, 255)        
		DragText.Position = MousePosition + Vector2.new(0, 30)

		task.wait(0.01)
	end

	DragText:Remove()
end

local MAX_X, MAX_Y = 1920, 1080

local function IsValid(Pos)
	return Pos 
		and (Pos.X == Pos.X) -- NaN check
		and Pos.X > 0 and Pos.X < MAX_X 
		and Pos.Y > 0 and Pos.Y < MAX_Y
end

local function ApplyVariance(Pos, Amount)
	if not Amount or Amount <= 0 then return Pos end
	local offsetX = math.random(-Amount, Amount)
	local offsetY = math.random(-Amount, Amount)
	return Vector2.new(Pos.X + offsetX, Pos.Y + offsetY)
end


local function ClickAndDragTo(StartPosition, NewPosition, Duration, Variance)
	local ActualStart = ApplyVariance(StartPosition, Variance)
	local ActualEnd = ApplyVariance(NewPosition, Variance)


	if not IsValid(ActualStart) or not IsValid(ActualEnd) then
		return 
	end 

	Dragging = true 
	task.spawn(_DragDebug)

	mousemoveabs(ActualStart.X, ActualStart.Y)
	task.wait(0.01)
	mousemoverel(math.random(1,5), math.random(1,5))

	--    notify("i just told it to press", "ok", 3)
	mouse1press()
	task.wait(0.05)

	--    notify("Should highlight blue", "ok", 3)

	-- Drag Logic
	if not Duration or Duration <= 0 then
		mousemoveabs(ActualEnd.X, ActualEnd.Y)
	else
		local TotalDelta = ActualEnd - ActualStart
		local StartTime = tick()

		while tick() - StartTime < Duration do
			local Elapsed = tick() - StartTime
			local Progress = math.clamp(Elapsed / Duration, 0, 1)

			local TargetPos = ActualStart + (TotalDelta * Progress)
			mousemoveabs(TargetPos.X, TargetPos.Y)

			task.wait() 
		end
		--        mousemoveabs(ActualEnd.X, ActualEnd.Y)
	end

	task.wait(0.05)
	mouse1release()
	Dragging = false
end

local function GetCenter(GuiObject)
	local Pos = GuiObject.AbsolutePosition
	local Size = GuiObject.AbsoluteSize
	-- Center = TopLeft + (TotalSize / 2)
	return Vector2.new(Pos.X + (Size.X / 2), Pos.Y + (Size.Y / 2))
end

----------------------------------------------------- QTE methods

local LastIndicatorPosition = nil

local function DoBlockBar(Indicator, Target)
	local IsAligned, Distance = AreUIObjectsAligned(Indicator, Target)

	-- Method for detecting new run by @haru_ty
	local IndicatorPositionX = memory_read('float', Indicator.Address + Offsets.FramePositionX)
	if IndicatorPositionX < 0.1 then  
		--print("Thats too fast")
		return
	end

	local Cooldown = tick() < QTE_UI.BlockingQTE.Debounce

	if IsAligned and not Cooldown then 
		QTE_UI.BlockingQTE.Debounce = tick() + 1
		print("just pressed space", Distance) 
		PressKey(32)
		QTE_UI.BlockingQTE.LastVisibleTime = nil
	end
end

local function GetRunePairs(Slots, Pieces)
	local SlotLookup = {}
	local FinalPairs = {}
	local NumberToProcess = 0

	if #Pieces == 0 then return NumberToProcess, {} end 
	-- 1. Index available Slots
	for _, slot in Slots do
		local sName = GetName(slot.Address)
		if sName and sName ~= "UIGridLayout" then
			SlotLookup[sName] = slot
		end
	end
	-- 2. Build the Pair table
	for _, piece in Pieces do
		local pName = GetName(piece.Address)

		-- Only proceed if it's NOT already slotted
		if pName ~= "Slotted" then
			NumberToProcess += 1
			local matchedSlot = SlotLookup[pName]
			if matchedSlot then
				FinalPairs[piece] = matchedSlot
				-- print("DEBUG: Paired", pName)
			end
		end
	end

	return NumberToProcess, FinalPairs
end

local MagicThread = false
local StartAfter = nil

local function DoMagicQTE(SlotsFolder, PiecesFolder)
	-- Get the filtered table of pairs [Piece] = Slot
	local NumberToProcess, RunePairs = GetRunePairs(SlotsFolder:GetChildren(), PiecesFolder:GetChildren())

	for piece, slot in pairs(RunePairs) do        
		--  local pieceName = GetName(piece.Address)
		--  local slotName = GetName(slot.Address)
		-- NumberToProcess -= 1 
		--print(string.format("Process this pair #%d || Piece: %s (Address: 0x%X)\n  Slot:  %s (Address: 0x%X)", NumberToProcess, tostring(pieceName), piece.Address, tostring(slotName), slot.Address))
		local IsThreadActive = (MagicThread == true) 
		if not IsThreadActive then
			MagicThread = true 
			local CenterPiecePosition = GetCenter(piece)
			local CenterSlotPosition = GetCenter(slot)
			ClickAndDragTo(CenterPiecePosition, CenterSlotPosition, 0.03, 5)
			MagicThread = false
			break
			-- start the mouse thread 
		end
	end

end


----------------------------------------------------- Combat thread

local function CombatLoop()
	while true do 
		for QTE_Type, Data in QTE_UI do 
			local QTE_Visible = IsFrameVisible(Data.QTE_Container)
			if not QTE_Visible then continue end

			if not Data.LastVisibleTime then  
				Data.LastVisibleTime = tick()
			end
			task.spawn(function()
				if QTE_Type == "BlockingQTE" then
					local Indicator = Data.Indicator
					local Target = Data.Target 
					DoBlockBar(Indicator, Target)
				elseif QTE_Type == "MagicQTE" then
					local SlotsFolder = Data.RuneSlots
					local PiecesFolder = Data.RunePieces
					DoMagicQTE(SlotsFolder, PiecesFolder)
				end
			end)
		end
		task.wait(0.01)
	end
end

----------------------------------------------------- Checking in-combat


local function GetCombatStatus()
	local CharacterName = PlayerGui.HUD.Holder.CharacterName.PlrName
	local TextColor = GetTextColor(CharacterName)
	local inCombatColor = Color3.new(1,0.65,0.65)

	if ColorsMatch(TextColor, inCombatColor) then 
		return true 
	end

	return false 
end

local InCombat = false
local CombatThread = nil

print("[ARCANE LINEAGE] Thread started")

-- Detecting whether player is in combat or not 
task.spawn(function()
	while true do
		local CurrentlyInCombat = GetCombatStatus()

		if CurrentlyInCombat and not InCombat then
			-- ENTER COMBAT
			InCombat = true
			notify("Combat Started", "ArcaneStuff", 3)
			print("[ARCANE LINEAGE] In combat")

			if not CombatThread then
				CombatThread = task.spawn(CombatLoop)
			end

		elseif not CurrentlyInCombat and InCombat then
			-- EXIT COMBAT
			InCombat = false
			notify("Out of Combat", "ArcaneStuff", 3)
			print("[ARCANE LINEAGE] Out of combat")
			if CombatThread then 
				task.cancel(CombatThread)
				CombatThread = nil
			end
		end

		task.wait(0.5) 
	end
end)
