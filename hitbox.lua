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
	self.Offset = Vector3.new(0, 0, 0) -- local-space offset: X = right, Y = up, Z = back (-Z = forward)
	self.Color = color or Color3.new(1, 1, 1)
	self.Size = size or Vector3.new(4, 4, 4)
	self.Thickness = thickness or 1
	self.Visible = true
	self.Adornee = nil -- optional: part to follow every frame
	self.MatchAdorneeSize = false -- if true, also copies the part's Size

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

-- offset is a Vector3 in the box's local space (relative to its rotation):
--   Vector3.new(0, 0, -5) -> 5 studs in front
--   Vector3.new(0, 3, 0)  -> 3 studs up
--   Vector3.new(3, 0, 0)  -> 3 studs to the right
function Box:SetOffset(offset)
	self.Offset = offset
end

-- Follow a part every frame (CFrame only unless matchSize is true)
function Box:Attach(part, matchSize)
	self.Adornee = part
	self.MatchAdorneeSize = matchSize or false
end

function Box:Detach()
	if self.Adornee then
		self.CFrame = self.Adornee.CFrame
	end
	self.Adornee = nil
end

local function dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

-- Returns the box's center and its three local axes in world space.
-- Built from RightVector/UpVector/LookVector instead of CFrame * Vector3,
-- so it doesn't depend on how the environment implements CFrame math.
function Box:GetAxes()
	local base = self.Adornee and self.Adornee.CFrame or self.CFrame

	local right = base.RightVector
	local up = base.UpVector
	local back = -base.LookVector

	local o = self.Offset
	local center = base.Position + right * o.X + up * o.Y + back * o.Z

	return center, right, up, back
end

function Box:SetSize(size)
	self.Size = size
end

function Box:ClientInHitbox()
	local character = Players.LocalPlayer.Character
	if not character then
		return false
	end
	return characterIntersects(self, character)
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

	if self.Adornee then
		if not self.Adornee.Parent then
			self:Destroy()
			return
		end
		self.CFrame = self.Adornee.CFrame
		if self.MatchAdorneeSize then
			self.Size = self.Adornee.Size
		end
	end

	local half = self.Size / 2
	local center, right, up, back = self:GetAxes()

	-- Build each corner from the box's own axes (this applies rotation),
	-- then project it to the screen
	local screen = {}
	local onScreen = {}
	for i, sign in ipairs(CORNERS) do
		local worldPos = center
			+ right * (sign.X * half.X)
			+ up * (sign.Y * half.Y)
			+ back * (sign.Z * half.Z)
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

-- Returns true if a world position is inside the box (rotation and offset included)
function Box:ContainsPoint(position)
	local center, right, up, back = self:GetAxes()
	local rel = position - center
	local half = self.Size / 2
	return math.abs(dot(rel, right)) <= half.X
		and math.abs(dot(rel, up)) <= half.Y
		and math.abs(dot(rel, back)) <= half.Z
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

-- Takes a table of possible character models and returns the ones inside the box
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

print("[HitboxLibrary] Functions were imported v 1.2")

_G.HitboxLibrary = Box

return Box
