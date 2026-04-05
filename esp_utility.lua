local ESP_Utility = {}
local TrackersToUpdate = {}
local UpdateThread = nil
ESP_Utility.__index = ESP_Utility

local RunService = game:GetService("RunService")

local function magnitude(p1, p2)
    local dx = p2.X - p1.X
    local dy = p2.Y - p1.Y
    local dz = p2.Z - p1.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local ClassTypeMap = {
    ["MeshPart"] = "Single",
    ["UnionOperation"] = "Single",
    ["Part"] = "Single",
}

function ESP_Utility.NewTracker(Object, Color)
	if TrackersToUpdate[Object.Address] then
	--	print("Already exists")
		return
	end

    local self = setmetatable({}, ESP_Utility)
    self.Name = Object.Name
	  self.Object = Object
	  self.Color = Color or Color3.fromRGB(255,255,255)
	  self.Drawings = {}
    
    self.ObjectType = self:_GetObjectType()
    self:BuildVisualTracker()

    TrackersToUpdate[Object.Address] = self
    return self
end

function ESP_Utility:_GetObjectType()
    local Object = self.Object
    
    if not Object or not Object.ClassName then 
        warn("[ERROR] Invalid object reference || Received: ", Object) 
        return nil 
    end

    local Category = ClassTypeMap[Object.ClassName]

    if Category then
        return Category
    end

	if Object.ClassName == "Model" then 
		warn("[ERROR] This does not support passing a model directly yet. I would recommend using the built in RegisterModel function or passing in a PrimaryPart || Received: " .. Object.ClassName)
	else
		warn("[ERROR] The tracker only accepts baseparts, meshparts, or unions. || Received: " .. Object.ClassName)
	end

    return nil
end

function ESP_Utility:_IsAlive()
    if not self.Object or not self.Object.Parent then 
      return false 
    else 
      return true
    end
end

function ESP_Utility:_Get2D_Bounds()
    local ObjectCFrame = self.Object.CFrame
    local HalfSize = self.Object.Size / 2
    
    local CornerOffsets = {
        Vector3.new(-HalfSize.X, -HalfSize.Y, -HalfSize.Z),
        Vector3.new(HalfSize.X, -HalfSize.Y, -HalfSize.Z),
        Vector3.new(HalfSize.X, -HalfSize.Y, HalfSize.Z),
        Vector3.new(-HalfSize.X, -HalfSize.Y, HalfSize.Z),
        Vector3.new(-HalfSize.X, HalfSize.Y, -HalfSize.Z),
        Vector3.new(HalfSize.X, HalfSize.Y, -HalfSize.Z),
        Vector3.new(HalfSize.X, HalfSize.Y, HalfSize.X),
        Vector3.new(-HalfSize.X, HalfSize.Y, HalfSize.Z),
    }
    
    local MinX, MinY = math.huge, math.huge
    local MaxX, MaxY = -math.huge, -math.huge
    local AnyCornerVisible = false
    
    for _, Offset in ipairs(CornerOffsets) do
        local ScreenPoint, IsOnScreen = WorldToScreen(ObjectCFrame * Offset)
        
        if IsOnScreen then
            AnyCornerVisible = true
            if ScreenPoint.X < MinX then MinX = ScreenPoint.X end
            if ScreenPoint.Y < MinY then MinY = ScreenPoint.Y end
            if ScreenPoint.X > MaxX then MaxX = ScreenPoint.X end
            if ScreenPoint.Y > MaxY then MaxY = ScreenPoint.Y end
        end
    end
    
    -- Only return coordinates if at least part of the object is in view
    if not AnyCornerVisible then return nil end
    
    return MinX, MinY, MaxX, MaxY
end

function ESP_Utility:_GetDistance()
  local Character = game.Players.LocalPlayer.Character
  if not Character then return 0 end 

  local HRP = Character.HumanoidRootPart
  
  return magnitude(HRP.Position, self.Object.Position)
end

function ESP_Utility:_SetTextPosition(DrawingObject, Index)
    local Session = self.Session
    local LineSpacing = 14 -- Pixels between each line
    local Padding = 10     -- Initial gap from the top of the box
    
    local FinalY = Session.TopY - Padding - (Index * LineSpacing)
    
    DrawingObject.Position = Vector2.new(Session.CenterX, FinalY)
end


function ESP_Utility:_Update()
    if not self:_IsAlive() or not self.ObjectType or self.ObjectType == "Model" then 
        self:Destroy()
        return 
    end 

    local min_x, min_y, max_x, max_y = self:_Get2D_Bounds()

    if not min_x then
        for _, Drawing in self.Drawings do Drawing.Visible = false end
        return
    end

    local boxWidth = max_x - min_x
    self.Session = {
        CenterX = min_x + (boxWidth / 2),
        TopY = min_y
    }

    for _, Drawing in self.Drawings do Drawing.Visible = true end

    -- Update Square
    local Square = self.Drawings["Square"]
    Square.Position = Vector2.new(min_x, min_y)
    Square.Size = Vector2.new(boxWidth, max_y - min_y)

	local NameText = self.Drawings["NameText"]
    self:_SetTextPosition(NameText, 1)
    
    local DistanceText = self.Drawings["DistanceText"]
    DistanceText.Text = math.floor(self:_GetDistance()).."m"
    self:_SetTextPosition(DistanceText, 0)
end


function ESP_Utility:_CreateText()
    local NameText = Drawing.new("Text")
    NameText.Text = self.Object.Name
    NameText.Center = true
    NameText.Outline = true
    NameText.Color = self.Color
    
    local DistanceText = Drawing.new("Text")
    DistanceText.Text = "???m"
    DistanceText.Center = true 
   	DistanceText.Outline = true
    DistanceText.Color = self.Color
    
    self.Drawings["NameText"] = NameText
    self.Drawings["DistanceText"] = DistanceText
end

function ESP_Utility:_CreateSquare()
  local NewSquare = Drawing.new("Square")
  NewSquare.Size = Vector2.new(10,10)
  NewSquare.Color = self.Color
	NewSquare.Filled = false
  self.Drawings["Square"] = NewSquare
end

function ESP_Utility:BuildVisualTracker()
  self:_CreateText()
  self:_CreateSquare()
end

function ESP_Utility:Destroy()
	TrackersToUpdate[self.Object.Address] = nil
	
	for Name, Drawing in pairs(self.Drawings) do 
		Drawing:Remove()
	end

	self.Drawings = {}

	setmetatable(self, nil)
end

UpdateThread = RunService.RenderStepped:Connect(function(dt)
    for i, v in TrackersToUpdate do 
      v:_Update()
    end 
end)


return ESP_Utility



