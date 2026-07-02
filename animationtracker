local Url = "https://offsets.imtheo.lol/Offsets.json"
local HttpService = game:GetService("HttpService")
local response = game:HttpGet(Url)
local offsets = HttpService:JSONDecode(response).Offsets

local KnownOffsets = {
    ["AnimationId"] = offsets.Misc.AnimationId,
    ["ClassDescriptor"] = offsets.Instance.ClassDescriptor, -- const
    ["ClassDescriptorToClassName"] = offsets.Instance.ClassName, -- const
    ["Name"] = offsets.Instance.Name, -- const
    ["TimePosition"] = offsets.AnimationTrack.TimePosition,
    ["ActiveAnimations"] = offsets.Animator.ActiveAnimations, -- const
    -- Node Structure
    ["NodeNext"] = 0x10,
}

local function GetAnimatorAddress(Character)
    if not Character or Character.Address == 0 then return nil end

    local Humanoid = Character:FindFirstChild("Humanoid")
    if not Humanoid then return nil end

    local Animator = Humanoid:FindFirstChild("Animator")
    return Animator and Animator.Address or nil
end

local function GetPlayingAnimationTracks(Character)
    local AnimatorAddress = GetAnimatorAddress(Character)
    if not AnimatorAddress then 
        print("Failed to resolve Animator.")
        return 
    end

    -- This is the address of the head of the linked list of active animations
    local ListHead_Ptr = memory_read("uintptr_t", AnimatorAddress + KnownOffsets.ActiveAnimations)
    if not ListHead_Ptr or ListHead_Ptr == 0 then
        return 
    end

    -- When you read the pointer at the head, you get the first node in the list (or the head itself if the list is empty)
    local firstNode = memory_read("uintptr_t", ListHead_Ptr)
    if not firstNode or firstNode == 0 or firstNode == ListHead_Ptr then 
--        print(string.format("[Head: 0x%X] ---> EMPTY LIST", ListHead_Ptr))
        return {}
    end

    local AnimationTracks = {}
    local currentNode = firstNode
    local foundCount = 0

    local visualPath = string.format("[Head: 0x%X] -> [Node 1: 0x%X]", ListHead_Ptr, firstNode)
  --  print(visualPath)

   while currentNode and currentNode ~= 0 and currentNode ~= ListHead_Ptr do
        local nextNode = memory_read("uintptr_t", currentNode)
        
        -- If the next node is the head, this current node is the tail/sentinel and won't hold a track
        if nextNode == ListHead_Ptr then
    --        print(string.format("   |__ [Tail Node 0x%X] End of list reached. Loops back to Head.", currentNode))
           --  print(string.format("   ---> [Head: 0x%X] (Loop Completed)", ListHead_Ptr))
            break
        end

        -- The first node (AnimationTrack) has a pointer to the next node at offset 0x10
        local track = memory_read("uintptr_t", currentNode + KnownOffsets.NodeNext)
        
        if track then
            foundCount = foundCount + 1
            AnimationTracks[foundCount] = track
 --           print(string.format("   |__ [Node 0x%X] holds AnimationTrack: 0x%X", currentNode, track))
        end

        if foundCount >= 50 then 
            print("   |__ [MAX CAP REACHED]")
            break 
        end

        if nextNode == 0 or not nextNode then
--         print("   ---> [NULL] (End of List)")
        else
            -- -- print(string.format("   ---> [Next Node: 0x%X]", nextNode))
        end

        currentNode = nextNode
    end

    return AnimationTracks
end

local function ExtractAnimationTrackInfo(AnimationTrackAddress)
    if not AnimationTrackAddress or AnimationTrackAddress == 0 then return nil end

    local NamePtr = memory_read("uintptr_t", AnimationTrackAddress + KnownOffsets.Name)
    local Name = memory_read("string", NamePtr)
    local AnimationId = memory_read("int", AnimationTrackAddress + KnownOffsets.AnimationId)
    local TimePosition = memory_read("float", AnimationTrackAddress + KnownOffsets.TimePosition)

    return {
        Address = AnimationTrackAddress,
        Name = Name,
        AnimationId = AnimationId,
        TimePosition = TimePosition
    }
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(callback)
    table.insert(self._listeners, callback)
    return {
        Disconnect = function()
            for i = 1, #self._listeners do
                if self._listeners[i] == callback then
                    table.remove(self._listeners, i)
                    break
                end
            end
        end
    }
end

function Signal:Fire(...)
    for i = 1, #self._listeners do
        self._listeners[i](...)
    end
end


local AnimationTracker = {}
AnimationTracker.__index = AnimationTracker

function AnimationTracker.new()
    local self = setmetatable({}, AnimationTracker)
    
    self.AnimationAdded = Signal.new()
    self.AnimationRemoved = Signal.new()
    
    self._cachedTracks = {}
    
    return self
end

function AnimationTracker:Update(character)
    local tracksPlaying = GetPlayingAnimationTracks(character)
    if not tracksPlaying then return end

    local currentAddresses = {}

    for i = 1, #tracksPlaying do
        local address = tracksPlaying[i]
        currentAddresses[address] = true

        if not self._cachedTracks[address] then
            local info = ExtractAnimationTrackInfo(address)
            if info then
                self._cachedTracks[address] = info
                self.AnimationAdded:Fire(info)
            end
        end
    end

    for address, cachedInfo in next, self._cachedTracks do
        if not currentAddresses[address] then
            self.AnimationRemoved:Fire(cachedInfo)
            self._cachedTracks[address] = nil
        end
    end
end

print("[AnimationTracker] Functions were imported, use Tracker:Update() in a loop")

_G.AnimationTracker = AnimationTracker
return AnimationTracker

