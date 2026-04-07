local OffsetsJSON = game:HttpGet("https://offsets.ntgetwritewatch.workers.dev/offsets.json")
local HttpService = game:GetService("HttpService")
local Offsets = HttpService:JSONDecode(OffsetsJSON)

local function IsScreenGuiEnabled(ScreenGui)
    if not ScreenGui then return end 

    local Status = memory_read("byte", ScreenGui.Address + Offsets.ScreenGuiEnabled)
    local ScreenGuiEnabled = tonumber(Status) ~= 0
    -- print("SCREEN VISIBLE: ", Status, ScreenGuiEnabled)
    return ScreenGuiEnabled
end

local function PressKey(Keycode)
    keypress(Keycode)
		task.wait(math.random(20,40) * 0.001)
		keyrelease(Keycode)
end

local function InputFromText(Text)
    local Keycode = string.byte(Text)
    keypress(Keycode)
    task.wait()
    keyrelease(Keycode)
    return "Pressed ".. Keycode.."/"..Text
end

local function BruteForceColor(Address, Range)
    Range = Range or 1024
    print(string.format("--- Starting Brute Force Scan: %X ---", Address))
    for offset = 0, Range, 4 do
        local r = memory_read("float", Address + offset)
        local g = memory_read("float", Address + offset + 4)
        local b = memory_read("float", Address + offset + 8)

        -- Guard against nil returns first
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then

			local isInvalid = (r < 0.0001 or r > 1) or (g < 0.0001 or g > 1) or (b < 0.0001 or b > 1)


            if not isInvalid then
                local isPureWhite = (r == 1 and g == 1 and b == 1)

                if not isPureWhite then
                    print(string.format("VALID COLOR FOUND [0x%X] -> R:%.3f G:%.3f B:%.3f", offset, r, g, b))
                end
            end
        end
    end
    print("--- Scan Complete ---")
end

local function GetTextColor(Address)
    if not Address or Address == 0 then return nil end
	local TextColorOffset = 0xE70
	
    local r = memory_read("float", Address + TextColorOffset)
    local g = memory_read("float", Address + TextColorOffset + 4)
    local b = memory_read("float", Address + TextColorOffset + 8)

    return Color3.new(r, g, b)
end

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

    -- 1. Manually calculate centers
    local centerAX = posA.X + (sizeA.X / 2)
    local centerAY = posA.Y + (sizeA.Y / 2)
    
    local centerBX = posB.X + (sizeB.X / 2)
    local centerBY = posB.Y + (sizeB.Y / 2)

    -- 2. Manually calculate differences (Offsets)
    local diffX = centerAX - centerBX
    local diffY = centerAY - centerBY

    -- 3. Distance formula: square root of (a^2 + b^2)
    local distance = math.sqrt(diffX^2 + diffY^2)

    -- 4. Overlap Check (Standard AABB)
    local isAligned = (math.abs(diffX) < (sizeA.X + sizeB.X) / 2) and (math.abs(diffY) < (sizeA.Y + sizeB.Y) / 2)
  
    return isAligned
end
