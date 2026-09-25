local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Box = {}
Box.__index = Box

local activeBoxes = {}

local CORNERS = {
	Vector3.new(-1, -1, -1), -- 1
	Vector3.new( 1, -1, -1), -- 2
	Vector3.new(-1,  1, -1), -- 3
	Vector3.new( 1,  1, -1), -- 4
	Vector3.new(-1, -1,  1), -- 5
	Vector3.new( 1, -1,  1), -- 6
	Vector3.new(-1,  1,  1), -- 7
	Vector3.new( 1,  1,  1), -- 8
}

-- 12 edges connecting the corners above
local EDGES = {
	{1, 2}, {3, 4}, {5, 6}, {7, 8}, -- along X
	{1, 3}, {2, 4}, {5, 7}, {6, 8}, -- along Y
	{1, 5}, {2, 6}, {3, 7}, {4, 8}, -- along Z
}

function Box.new(cframe, color, size, thickness)
	local self = setmetatable({}, Box)

	self.CFrame = cframe
	self.Color = color or Color3.new(1, 1, 1)
	self.Size = size or Vector3.new(4, 4, 4)
	self.Thickness = thickness or 1
	self.Visible = true
	self.Adornee = nil -- optional: set to a part to follow its CFrame and Size

	self.Lines = {}
	for i = 1, #EDGES do
		local line = Drawing.new("Line")
		line.Color = self.Color
		line.Thickness = self.Thickness
		line.Visible = false
		self.Lines[i] = line
	end

	activeBoxes[self] = true
	return self
end

function Box:SetCFrame(cframe)
	self.CFrame = cframe
end

function Box:SetSize(size)
	self.Size = size
end

function Box:SetColor(color)
	self.Color = color
	for _, line in ipairs(self.Lines) do
		line.Color = color
	end
end

function Box:SetThickness(thickness)
	self.Thickness = thickness
	for _, line in ipairs(self.Lines) do
		line.Thickness = thickness
	end
end

function Box:SetVisible(visible)
	self.Visible = visible
	if not visible then
		for _, line in ipairs(self.Lines) do
			line.Visible = false
		end
	end
end

function Box:Update()
	if not self.Visible then
		return
	end

	-- Follow a part if one is attached
	if self.Adornee then
		if not self.Adornee.Parent then
			self:Destroy()
			return
		end
		self.CFrame = self.Adornee.CFrame
		self.Size = self.Adornee.Size
	end

	local half = self.Size / 2
	local cf = self.CFrame

	-- Transform each local corner by the CFrame (this applies rotation),
	-- then project it to the screen
	local screen = {}
	local onScreen = {}
	for i, sign in ipairs(CORNERS) do
		local worldPos = cf * (sign * half)
		screen[i], onScreen[i] = WorldToScreen(worldPos)
	end

	for i, edge in ipairs(EDGES) do
		local a, b = edge[1], edge[2]
		local line = self.Lines[i]

		if onScreen[a] and onScreen[b] then
			line.From = screen[a]
			line.To = screen[b]
			line.Color = self.Color
			line.Thickness = self.Thickness
			line.Visible = true
		else
			line.Visible = false
		end
	end
end

-- Returns true if a world position is inside the box (rotation included)
function Box:ContainsPoint(position)
	local localPos = self.CFrame:Inverse() * position
	local half = self.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- A character counts as intersecting if any of its parts' centers is inside the box
local function characterIntersects(self, character)
	for _, part in ipairs(character:GetChildren()) do
		if part.Position and self:ContainsPoint(part.Position) then
			return true
		end
	end
	return false
end

-- Returns an array of character models inside the box, plus an array of
-- the matching players (same order; NPCs have no player entry).
-- Pass true to also check NPCs (models with a Humanoid directly in workspace).
function Box:GetIntersectingCharacters(possibleCharacters)
	local characters = {}

	for _, character in ipairs(possibleCharacters) do
		if character:IsA("Model") and characterIntersects(self, character) then
			table.insert(characters, character)
		end
	end

	return characters
end

function Box:Destroy()
	activeBoxes[self] = nil
	for _, line in ipairs(self.Lines) do
		line:Remove()
	end
	self.Lines = {}
end

RunService.RenderStepped:Connect(function()
	for box in pairs(activeBoxes) do
		box:Update()
	end
end)

return Box
