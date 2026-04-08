local URL = "https://raw.githubusercontent.com/artxficial/matchastuff/main/esp_utility.lua"
local ImportESP = pcall(function()
    loadstring(game:HttpGet(URL))()
end)

local PathToThings = game.Workspace.IGNORE

local function GetFilteredTable()
    if not game.Workspace.MAPS["GAME MAP"] then
        return {}
    end

    local PathToGenerators = game.Workspace.MAPS["GAME MAP"].Generators
    local PathToFuseBoxes = game.Workspace.MAPS["GAME MAP"].FuseBoxes

    local Categories = {
        Generator = {
            Color = Color3.fromRGB(170, 85, 255),
            Objects = {},
        },
        Battery = {
            Color = Color3.fromRGB(220, 232, 93),
            Objects = {},
        },
        Trap = {
            Color = Color3.fromRGB(232, 102, 100),
            Objects = {},
        },
        Minion = {
            Color = Color3.fromRGB(130, 55, 55),
            Objects = {},
        },
        Killer = {
            Color = Color3.fromRGB(255, 150, 150),
            Objects = {},
        },
        FuseBox = {
            Color = Color3.fromRGB(87, 119, 122),
            Objects = {},
        }
    }

    for _, generatorModel in PathToGenerators:GetChildren() do
        if generatorModel.PrimaryPart then
            table.insert(Categories.Generator.Objects, generatorModel.PrimaryPart)
        end
    end

    local KillerModel = game.Workspace.PLAYERS.KILLER:FindFirstChildWhichIsA("Model")
    if KillerModel and KillerModel:FindFirstChild("Hitbox") then
        table.insert(Categories.Killer.Objects, KillerModel.Hitbox)
    end

    if PathToFuseBoxes then 
        for _, FuseBoxModel in PathToFuseBoxes:GetChildren() do 
          local IsCompleted = FuseBoxModel:GetAttribute("Inserted")
          if IsCompleted then continue end   
          table.insert(Categories.FuseBox.Objects, FuseBoxModel.PrimaryPart)
        end
    end
  
    local PotentialObjects = {}

    for _, item in PathToThings:GetChildren() do
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
        local ValidChildren = {
            ["Trap"] = "Trap",
            ["Battery"] = "Joint",
            ["Minion"] = "HumanoidRootPart",
        }

        for CategoryName, ChildToLookFor in ValidChildren do
            local FoundChild = item:FindFirstChild(ChildToLookFor)
            if FoundChild then
                if ChildToLookFor == "HumanoidRootPart" then
                    if item.Name ~= "Minion" and #item:GetChildren() ~= 5 then
                        continue
                    end
                end

                local PrimaryPart = item.PrimaryPart
                table.insert(Categories[CategoryName].Objects, PrimaryPart or item)
            end
        end
    end

    return Categories
end

task.spawn(function()
    while true do
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
                    
                if CategoryName == "Generator" then
                  Tracker.Drawings.Square.Visible = false
                  
                  local ProgressFunction = function()
                    local genModel = Instance.Parent
                    if not genModel then
                        return ""
                    end
                        
                    local progress = genModel:GetAttribute("Progress") or 0
                            
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

        task.wait(2.5)
    end
end)
