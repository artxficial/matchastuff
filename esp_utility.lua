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

local BasePartTypes = {
	["Part"] = "BasePart",
	["MeshPart"] = "BasePart",
	["UnionOperation"] = "BasePart",
	["Model"] = "Model",
}

local function IsValidObject(Object)
	if type(Object) == "userdata" and Object and Object.ClassName then 
		local Type = BasePartTypes[Object.ClassName]
		return Type
	end

	return nil
end

local function GetObjectFromModel(Model)
	local CommonNames = {"HumanoidRootPart","Root", "RootPart", "Core"}


	-- 1. Try to find a standard Root Part first
	local Children = Model:GetChildren()

	for _, Name in CommonNames do
		for _, Child in Children do
			-- Convert the current child's name to lowercase for comparison
			if string.lower(Child.Name) == string.lower(Name) and BasePartTypes[Child.ClassName] == "BasePart" then
				return Child
			end
		end
	end

	-- 2. If its a model try its PrimaryPart
	if Model.ClassName == "Model" then 
		local PrimaryPart = Model.PrimaryPart
		return PrimaryPart
	end

	-- 3. Fallback: Find the largest part by volume
	local LargestPart = nil
	local MaxVolume = 0

	for _, Child in Model:GetChildren() do	
		if BasePartTypes[Child.ClassName] then
			-- Volume = Size.X * Size.Y * Size.Z
			local Volume = Child.Size.X * Child.Size.Y * Child.Size.Z
			if Volume > MaxVolume then
				MaxVolume = Volume
				LargestPart = Child
			end
		end
	end

	return LargestPart
end

function ESP_Utility.NewTracker(Object, CustomName, Color)
	local ObjectType = IsValidObject(Object)
	if not ObjectType then 
		warn("[ERROR] The tracker only accepts models, baseparts, meshparts, or unions. || Received: ", Object) 
		return 
	end 


	if ObjectType == "Model" then 
		--	print("[MODEL] Model received")
		local Model = Object
		CustomName = CustomName or Object.Name
		Object = GetObjectFromModel(Model)
		if Object == nil then 
			warn(string.format("[ERROR] Could not add Model: %s because it had no valid parts inside of it", Model.Name)) 
			return
		end 
	end

	if TrackersToUpdate[Object.Address] then
		--	print("Already exists")
		return TrackersToUpdate[Object.Address]
	end

	local self = setmetatable({}, ESP_Utility)
	self.Name = CustomName or Object.Name
	self.Object = Object
	self.Color = Color or Color3.fromRGB(255,255,255)
	self.Drawings = {}
	self.ObjectType = ObjectType

	self:BuildVisualTracker()

	TrackersToUpdate[Object.Address] = self
	return self
end


function ESP_Utility:_IsAlive()
	if not self.Object or not self.Object.Parent then 
		return false 
	else 
		return true
	end
end

function ESP_Utility:_Get2D_Bounds()
	-- 1. Logic for Non-Models (Dynamic/Rotating)
	if self.ObjectType ~= "Model" then
		local cf, size = self.Object.CFrame, self.Object.Size
		local half = size / 2
		local corners = {
			cf * Vector3.new(-half.X, -half.Y, -half.Z),
			cf * Vector3.new(half.X, -half.Y, -half.Z),
			cf * Vector3.new(half.X, -half.Y, half.Z),
			cf * Vector3.new(-half.X, -half.Y, half.Z),
			cf * Vector3.new(-half.X, half.Y, -half.Z),
			cf * Vector3.new(half.X, half.Y, -half.Z),
			cf * Vector3.new(half.X, half.Y, half.Z),
			cf * Vector3.new(-half.X, half.Y, half.Z),
		}

		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge

		for _, worldPos in ipairs(corners) do
			local screenPos, onScreen = WorldToScreen(worldPos)

			-- STRICT CHECK: If even ONE corner is off-screen, hide the whole thing
			if not onScreen then 
				return nil 
			end

			minX = math.min(minX, screenPos.X)
			minY = math.min(minY, screenPos.Y)
			maxX = math.max(maxX, screenPos.X)
			maxY = math.max(maxY, screenPos.Y)
		end

		return minX, minY, maxX, maxY
	end

	-- 2. "Model" Logic (Static/Non-Rotating Box)
	local Position = self.Object.Position
	local Size = self.Object.Size

	local ScreenCenter, CenterVisible = WorldToScreen(Position)
	local ScreenTop, TopVisible = WorldToScreen(Position + Vector3.new(0, Size.Y / 2, 0))

	if not CenterVisible or not TopVisible then 
		return nil 
	end

	local Height = math.abs(ScreenCenter.Y - ScreenTop.Y) * 5
	local Width = Height * 1.2

	local MinX = ScreenCenter.X - (Width / 2)
	local MaxX = ScreenCenter.X + (Width / 2)
	local MinY = ScreenCenter.Y - (Height / 2)
	local MaxY = ScreenCenter.Y + (Height / 2)

	return MinX, MinY, MaxX, MaxY
end




function ESP_Utility:_GetDistance()
	local Character = game.Players.LocalPlayer.Character
	if not Character then return 0 end 

	local HRP = Character.HumanoidRootPart
	if not HRP.Parent then return 0 end 

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
	if not self:_IsAlive() or not self.ObjectType then 
		self:Destroy()
		return 
	end 

	local min_x, min_y, max_x, max_y = self:_Get2D_Bounds()
	local Hidden = false

	for DrawingName, Data in pairs(self.Drawings) do
		-- 1. Identify the actual Drawing object
		local DrawingObject = (type(Data) == "table" and Data.Drawing) or Data

		-- 2. Ensure it's actually a Drawing object (they have a 'Visible' property)
		if not min_x then 
			DrawingObject.Visible = false
			Hidden = true
		else
			if DrawingName == "Square" and self.ObjectType == "Model" then continue end 
			DrawingObject.Visible = true
		end
	end

	if Hidden then return end 

	local boxWidth = max_x - min_x
	self.Session = {
		CenterX = min_x + (boxWidth / 2),
		TopY = min_y
	}


	-- Update Square
	local Square = self.Drawings["Square"]
	Square.Position = Vector2.new(min_x, min_y)
	Square.Size = Vector2.new(boxWidth, max_y - min_y)

	-- Update texts
	for Key, Data in pairs(self.Drawings) do
		if string.find(Key, "Text") then
			local DrawingObject = Data.Drawing
			local Callback = Data.Function
			local Index = Data.Index

			if Callback then
				DrawingObject.Text = Callback()
			end

			self:_SetTextPosition(DrawingObject, Index) 
		end
	end

end


function ESP_Utility:_CreateSquare()
	local NewSquare = Drawing.new("Square")
	NewSquare.Size = Vector2.new(10,10)
	NewSquare.Color = self.Color
	NewSquare.Filled = false
	if self.ObjectType == "Model" then NewSquare.Visible = false end 
	self.Drawings["Square"] = NewSquare

end

function ESP_Utility:AddText(Reference, Color, Value, Callback)
	if self.Drawings[Reference.."Text"] then return end 

	local textCount = 0
	for k, _ in pairs(self.Drawings) do
		if string.find(k, "Text") then
			textCount = textCount + 1
		end
	end

	local NewText = Drawing.new("Text")
	NewText.Text = Value or "Provide a value (3rd arg) or callback (4th arg)"
	NewText.Center = true
	NewText.Outline = true 
	NewText.Color = Color or Color3.fromRGB(200,200,200)
	self.Drawings[Reference.."Text"] = {
		Drawing = NewText,
		Function = Callback or nil,
		Index = textCount,
	}
end

function ESP_Utility:BuildVisualTracker()
	self:_CreateSquare()

	self:AddText("Distance", nil, "ok", function() 
		return "["..math.floor(self:_GetDistance()).."m]" 
	end)

	local NameString = self.Name..(self.ObjectType == "Model" and " [MODEL]" or "")
	self:AddText("Name", self.Color, NameString)

end

function ESP_Utility:Destroy()
	TrackersToUpdate[self.Object.Address] = nil

	for Name, Drawing in pairs(self.Drawings) do
		if type(Drawing) == "table" then 
			Drawing.Drawing:Remove()
		else
			Drawing:Remove()
		end
	end

	for key, value in self do 
		self[key] = nil
	end
	setmetatable(self, nil)
end

UpdateThread = RunService.RenderStepped:Connect(function(dt)
	for i, v in TrackersToUpdate do 
		v:_Update()
	end 
end)

notify("ESP thread started", "ESP_Utility", 3)
_G.ESP_Utility = ESP_Utility
return ESP_Utility
