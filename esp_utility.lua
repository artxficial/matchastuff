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

function ESP_Utility:_SetTextPosition(DrawingObject, Y_Offset)
	local Session = self.Session
	local FontSize = DrawingObject.Size or 20
	local Padding = 5

	local textLength = 0 
	for line in string.gmatch(DrawingObject.Text, "[^\n]+") do
		local length = #line
		if length > textLength then
			textLength = length
		end
	end


	-- 1. Manual X Centering 
	-- We approximate width: Average char is about half the height wide

	local estimatedWidth = textLength * (FontSize * 0.45) 
	local manualCenterX = Session.CenterX - (estimatedWidth / 2)

	-- 2. Upward Y Calculation
	-- As Y_Offset increases (0, 1, 5, 6), this value gets smaller (higher on screen)
	local FinalY = Session.TopY - Padding - ((Y_Offset + 1) * FontSize)

	-- 3. Apply Position
	DrawingObject.Center = false 
	DrawingObject.Position = Vector2.new(manualCenterX, FinalY)
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

			self:_SetTextPosition(DrawingObject, Data.Y_Offset) 
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

function ESP_Utility:AddText(Reference, Color, Value, Callback, CustomIndex)
	local keyName = Reference .. "Text"
	if self.Drawings[keyName] then return end

	if not self.DrawingOrder then
		self.DrawingOrder = {}
	end

	-- 1. Calculate the NEW item's line count first
	local currentText = tostring((Callback and Callback()) or Value or "")
	local _, newlineCount = string.gsub(currentText, "\n", "")
	local currentLineCount = newlineCount + 1

	-- 2. Calculate the Start Offset by summing the HEIGHT (LineCount) of previous items
	local totalLineHeightSoFar = 0
	for _, existingKey in self.DrawingOrder do
		local data = self.Drawings[existingKey]
		if data and data.LineCount then
			totalLineHeightSoFar = totalLineHeightSoFar + data.LineCount
			--print("TOTAL SO FAR: ", totalLineHeightSoFar, existingKey)
		end
	end

	-- 3. Assign the offset
	local assignedOffset = CustomIndex or totalLineHeightSoFar + currentLineCount - 1

	-- 4. Create drawing
	local NewText = Drawing.new("Text")
	NewText.Text = currentText
	NewText.Center = false
	NewText.Outline = true
	NewText.Color = Color or Color3.fromRGB(200, 200, 200)

	-- 5. Store both the Offset (where it starts) and the LineCount (how big it is)
	self.Drawings[keyName] = {
		Drawing = NewText,
		Function = Callback or nil,
		Y_Offset = assignedOffset,
		LineCount = currentLineCount -- CRITICAL: Store this so the NEXT item knows where to start
	}

	table.insert(self.DrawingOrder, keyName)
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
