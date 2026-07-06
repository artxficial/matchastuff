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
    ["Animation"] = offsets.AnimationTrack.Animation,
    -- Node Structure
    ["NodeNext"] = 0x10,
}

local function GetAnimatorAddress(Character)
    if not Character or Character.Address == 0 then return nil end

    local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
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
        -- 1. Read the track data from the current node first
        local track = memory_read("uintptr_t", currentNode + KnownOffsets.NodeNext)
        
        if track then
            foundCount = foundCount + 1
            AnimationTracks[foundCount] = track
         --   print(string.format("   |__ [Node 0x%X] holds AnimationTrack: 0x%X", currentNode, track))
        end

        if foundCount >= 50 then 
        --    print("   |__ [MAX CAP REACHED]")
            break 
        end

        -- 2. Look ahead to see where we go next
        local nextNode = memory_read("uintptr_t", currentNode)
        
        if nextNode == ListHead_Ptr then
         --   print(string.format("   |__ [Node 0x%X] next node is Head. Traversal complete.", currentNode))
         --   print(string.format("   ---> [Head: 0x%X] (Loop Completed)", ListHead_Ptr))
            break -- Safe to exit now; we fully processed currentNode
        elseif nextNode == 0 or not nextNode then
         --   print("   ---> [NULL] (End of List)")
            break
        else
         --   print(string.format("   ---> [Next Node: 0x%X]", nextNode))
        end

        currentNode = nextNode
    end

    return AnimationTracks
end

local function GetTimePosition(AnimationTrackAddress)
    if not AnimationTrackAddress or AnimationTrackAddress == 0 then return nil end
    
    local TimePosition = memory_read("float", AnimationTrackAddress + KnownOffsets.TimePosition)
    
    return TimePosition
end

local function ExtractAnimationTrackInfo(AnimationTrackAddress)
    if not AnimationTrackAddress or AnimationTrackAddress == 0 then return nil end

    local Animation = memory_read("uintptr_t", AnimationTrackAddress + KnownOffsets.Animation)
    local AnimationIdPointer = memory_read("uintptr_t", Animation + KnownOffsets.AnimationId)
    local AnimationId = memory_read("string", AnimationIdPointer)

    local NamePtr = memory_read("uintptr_t", AnimationTrackAddress + KnownOffsets.Name)
    local Name = memory_read("string", NamePtr)
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
    self.AnimationUpdated = Signal.new()
    self.AnimationRemoved = Signal.new()
    
    self._cachedTracks = {} 
    self._threads = {}      
    self._threadTokens = {} -- Tracks unique IDs for thread versions
    
    return self
end

-- Internal method to loop and fire updates for a specific track
function AnimationTracker:_startTrackingTimePosition(trackInfo)
    local trackAddress = trackInfo.Address

    -- Force-kill any dangling thread for this address before making a new one
    if self._threads[trackAddress] then
        task.cancel(self._threads[trackAddress])
        self._threads[trackAddress] = nil
    end

    -- Create or increment a token unique to this specific thread generation
    local currentToken = (self._threadTokens[trackAddress] or 0) + 1
    self._threadTokens[trackAddress] = currentToken

    self._threads[trackAddress] = task.spawn(function()
        while true do
            -- 1. Lifecycle Check: Kill if cache cleared or if a newer thread took over the address
            if not self._cachedTracks[trackAddress] or self._threadTokens[trackAddress] ~= currentToken then
                break
            end

            local currentTime = GetTimePosition(trackAddress)
            if not currentTime then 
                break 
            end

            -- Update the cached info table with the freshest position
            trackInfo.TimePosition = currentTime
            
            -- Fire the update signal out to your listeners
            self.AnimationUpdated:Fire(trackInfo, currentTime)

            task.wait(0.05) -- 20Hz stream rate
        end

        -- 2. Post-loop Cleanup: Strip reference if this specific thread finished on its own
        if self._threadTokens[trackAddress] == currentToken then
            self._threads[trackAddress] = nil
            self._threadTokens[trackAddress] = nil
        end
    end)
end

function AnimationTracker:GetPlayingAnimations()
    local animationList = {}
    
    for address, cachedInfo in pairs(self._cachedTracks) do
        -- Dynamically read the latest TimePosition to guarantee 100% accuracy
        local currentPosition = GetTimePosition(address) or cachedInfo.TimePosition
        
        table.insert(animationList, {
            Address = cachedInfo.Address,
            Name = cachedInfo.Name,
            AnimationId = cachedInfo.AnimationId,
            TimePosition = currentPosition
        })
    end
    
    return animationList
end

function AnimationTracker:Update(character)
    local tracksPlaying = GetPlayingAnimationTracks(character)
    if not tracksPlaying then return end

    local currentAddresses = {}

    -- Track processing
    for i = 1, #tracksPlaying do
        local address = tracksPlaying[i]
        currentAddresses[address] = true

        if not self._cachedTracks[address] then
            local info = ExtractAnimationTrackInfo(address)
            if info then
                self._cachedTracks[address] = info
                self.AnimationAdded:Fire(info)
                self:_startTrackingTimePosition(info)
            end
        end
    end

    -- Cleanup processing
    for address, cachedInfo in next, self._cachedTracks do
        if not currentAddresses[address] then
            -- Force terminate the thread handle immediately
            local thread = self._threads[address]
            if thread then
                task.cancel(thread)
                self._threads[address] = nil
            end

            -- Fire event and completely scrub cache/token references
            self._threadTokens[address] = nil
            self.AnimationRemoved:Fire(cachedInfo)
            self._cachedTracks[address] = nil
        end
    end
end

print("[AnimationTracker] Functions were imported, use Tracker:Update() in a loop")

_G.AnimationTracker = AnimationTracker
return AnimationTracker

