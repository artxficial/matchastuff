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


----------------------------------------------------- QTE methods

local LastIndicatorPosition = nil
local BlockBecameVisibleAt = 0

local function DoBlockBar(Indicator, Target)
    local IsAligned, Distance = AreUIObjectsAligned(Indicator, Target)
    
    local BlockBecameVisibleAt = QTE_UI.BlockingQTE.LastVisibleTime
    local BlockDebounce = QTE_UI.BlockingQTE.Debounce
    if BlockBecameVisibleAt and (tick() - BlockBecameVisibleAt) < 0.1 then  
        -- print("Thats too fast")
        return
    end

    local Cooldown = tick() < QTE_UI.BlockingQTE.Debounce

    if IsAligned and not Cooldown then 
        QTE_UI.BlockingQTE.Debounce = tick() + 1
		print("just pressed the key", Distance) 
        PressKey(32)
        BlockBecameVisibleAt = nil
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

local function DoMagicQTE(SlotsFolder, PiecesFolder)
    -- Get the filtered table of pairs [Piece] = Slot
    local NumberToProcess, RunePairs = GetRunePairs(SlotsFolder:GetChildren(), PiecesFolder:GetChildren())
        
    for piece, slot in pairs(RunePairs) do        
        -- Get the live names from memory for verification
        local pieceName = GetName(piece.Address)
        local slotName = GetName(slot.Address)
        NumberToProcess -= 1 

        print(string.format("Process this pair #%d || Piece: %s (Address: 0x%X)\n  Slot:  %s (Address: 0x%X)", NumberToProcess, tostring(pieceName), piece.Address, tostring(slotName), slot.Address))
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

            if QTE_Type == "BlockingQTE" then
                local Indicator = Data.Indicator
                local Target = Data.Target 
                DoBlockBar(Indicator, Target)
            elseif QTE_Type == "MagicQTE" then
                local SlotsFolder = Data.RuneSlots
                local PiecesFolder = Data.RunePieces

                DoMagicQTE(SlotsFolder, PiecesFolder)
            end
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
