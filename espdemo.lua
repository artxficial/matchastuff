local URL = "https://raw.githubusercontent.com/artxficial/matchastuff/main/esp_utility.lua"
local ImportESP = pcall(function()
    loadstring(game:HttpGet(URL))()
end)

local CategoryConfiguration = {
        Generator = {
            Color = Color3.fromRGB(170, 85, 255),
            Objects = {},
            Visible = true, 
        },
        Battery = {
            Color = Color3.fromRGB(220, 232, 93),
            Objects = {},
            Visible = true, 
        },
        Trap = {
            Color = Color3.fromRGB(232, 102, 100),
            Objects = {},
            Visible = true, 
        },
        Minion = {
            Color = Color3.fromRGB(130, 55, 55),
            Objects = {},
            Visible = false, 
        },
        Killer = {
            Color = Color3.fromRGB(255, 150, 150),
            Objects = {},
            Visible = true, 
        },
        FuseBox = {
            Color = Color3.fromRGB(87, 119, 122),
            Objects = {},
            Visible = true, 
    }
}

local PathToThings = game.Workspace.IGNORE

local function GetFilteredTable()

	-- Needed to move categories outside of here to be accessed globally 
	-- This makes sure no old objects are in the list
	for CategoryName, Data in CategoryConfiguration do 
		Data.Objects = {}
	end

    if not game.Workspace.MAPS["GAME MAP"] then
        return {}
    end
	
    local PathToGenerators = game.Workspace.MAPS["GAME MAP"].Generators
    local PathToFuseBoxes = game.Workspace.MAPS["GAME MAP"].FuseBoxes

    for _, generatorModel in PathToGenerators:GetChildren() do
        if generatorModel.PrimaryPart then
            table.insert(CategoryConfiguration.Generator.Objects, generatorModel.PrimaryPart)
        end
    end

    local KillerModel = game.Workspace.PLAYERS.KILLER:FindFirstChildWhichIsA("Model")
    if KillerModel and KillerModel:FindFirstChild("Hitbox") then
        if KillerModel.Name ~= game.Players.LocalPlayer.Name then  
            table.insert(CategoryConfiguration.Killer.Objects, KillerModel.Hitbox)
        end
    end

    if PathToFuseBoxes then 
        for _, FuseBoxModel in PathToFuseBoxes:GetChildren() do 
          local IsCompleted = FuseBoxModel:GetAttribute("Inserted")

		-- ESP_Utility only checks if objects are destroyed but if they arent and you dont want them to appear
		-- in the next rescan cycle then you can do this OR you can add a visiblity toggle to its callback ( See generator callback )
          if IsCompleted then 
				local Tracker = ESP_Utility.TrackersToUpdate[FuseBoxModel.PrimaryPart.Address]
				if Tracker then 
					Tracker:Destroy()
				end
                continue
			end
          table.insert(CategoryConfiguration.FuseBox.Objects, FuseBoxModel.PrimaryPart)
        end
    end
  
    local PotentialObjects = {}
    local ValidChildren = {
            ["Trap"] = "Trap",
            ["Battery"] = "Joint",
            ["Minion"] = "HumanoidRootPart",
        }  

    for _, item in PathToThings:GetChildren() do
        local NameMatches = ValidChildren[item.Name]
        if not NameMatches then 
            continue 
        end 

        local IsTransparent = (item.Transparency == 1)
        if IsTransparent then
            continue
        end

        local ClassName = item.ClassName
        local IsPart = (ClassName == "Part")
        if IsPart then
            continue
        end

        local IsMesh = (ClassName == "MeshPart") and (item.MeshId ~= "rbxassetid://131427085502355")
        if IsMesh then
            continue
        end

        table.insert(PotentialObjects, item)
    end

    for _, item in PotentialObjects do

        for CategoryName, ChildToLookFor in ValidChildren do
            local FoundChild = item:FindFirstChild(ChildToLookFor)
            if FoundChild then
                if ChildToLookFor == "HumanoidRootPart" then
                    if item.Name ~= "Minion" and #item:GetChildren() ~= 5 then
                        continue
                    end
                end

                local PrimaryPart = item.PrimaryPart
                table.insert(CategoryConfiguration[CategoryName].Objects, PrimaryPart or item)
            end
        end
    end

    return CategoryConfiguration
end

local function ScanWorkspace()
    local Categories = GetFilteredTable()

    for CategoryName, Table in Categories do
        for _, Instance in Table.Objects do
            if not Instance or not Instance.Address then
                continue
            end

            local DisplayName = CategoryName

            local Tracker = ESP_Utility.NewTracker(Instance, DisplayName, Table.Color)
            if not Tracker then
                continue
            end

            if Table.Visible == false then  
                Tracker:Destroy()
                -- print(CategoryName, " is toggled off")
                continue
            end
                
            if CategoryName == "Generator" then
              Tracker.Drawings.Square.Visible = false
              local GeneratorProg = 0 
              local ProgressFunction = function()
                local genModel = Instance.Parent
                if not genModel then
					Tracker:Destroy()
                    return ""
                end
                    
                local progress = genModel:GetAttribute("Progress") or 0
                        
				-- Happens only once and notifies when a generator was finished
                if progress == 100 and Tracker.Visible == true then notify("A generator was completed", "", 3) end -- Notifies is a generator was finished 
                        
                if progress == 100 then Tracker.Visible = false return "" end -- Hides tracker when finished

                return string.format("Progress: %d%%", progress)
              end

              Tracker:AddText("Progress", Color3.fromRGB(120, 255, 120), "Progress: 0%", ProgressFunction)
            elseif CategoryName == "Killer" then 
                local Character = Instance.Parent 
                if not Character then continue end 

                local PlayerName = Character.Name
                local KillerType = Character:GetAttribute("Character") or ""
                Tracker:ChangeText("Name", string.format("%s [%s]", PlayerName, KillerType))
            end
        end
    end
end


local function BuildESPSection(Tab)
	local Section = Tab:Section("ESP", "Left")

	for CategoryName, Data in CategoryConfiguration do 
		local ButtonID = CategoryName.."ESP"
        local StateChanged = function(state)
           --print(CategoryName.. ": " .. tostring(state))
			Data.Visible = state
            ScanWorkspace()
        end
        local ToggleButton = Section:Toggle(ButtonID, CategoryName .. " ESP", true, StateChanged)
	end
end

local function InitMatchaTab()
	-- Create the tab
    local Tab = UI.AddTab("Bite By Night", function(tab)
        -- ESP Section
		BuildESPSection(tab)
    end)

    for CategoryName, Data in CategoryConfiguration do  
        Data.Visible = UI.GetValue(CategoryName.."ESP")
    end
end
InitMatchaTab()


task.spawn(function()
    while true do
        ScanWorkspace()
        task.wait(1.25)
    end
end)
