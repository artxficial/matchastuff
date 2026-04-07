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
