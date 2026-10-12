-- Carrega a Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Janela Principal (Sem sistema de Key)
local Window = Rayfield:CreateWindow({
    Name = "Nina Hub Oaklands",
    LoadingTitle = "Nina Hub Oaklands",
    LoadingSubtitle = "by Lane",
    ConfigurationSaving = { Enabled = false },
    Keybind = Enum.KeyCode.RightControl,
    KeySystem = false, -- Desativado
})

-- Abas da Interface
local ESPTab = Window:CreateTab("Ore ESP", "gem")
local ConfigTab = Window:CreateTab("Configuration", "settings")

-- Variáveis Globais e Sistema de Cache
local MAX_DISTANCE = 1500
local activeESPs = {}
local selectedOreTypes = {}
local availableOreTypes = {}
local registeredOresSet = {}
local MAX_SPEED = 200
local PlayerList = {}
local SelectedPlayer = nil

-- Variáveis de controle de velocidade
local speedEnabled = false
local currentSpeedValue = 16

-- Cache global para armazenar todos os minérios já mapeados no jogo
local cachedOres = {} -- Estrutura: { [Model] = OreName }

-- Função Atualizar Lista Player
local function UpdatePlayerList()
    table.clear(PlayerList)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then -- Tirar LocalPlayer da lista
            table.insert(PlayerList, player.Name)
        end
    end
end
UpdatePlayerList() -- Iniciar Lista pela primeira vez

-- Atualizar automaticamente quando alguém entra ou sai
Players.PlayerAdded:Connect(function()
    UpdatePlayerList()
end)

Players.PlayerRemoving:Connect(function()
    UpdatePlayerList()
end)

-- Função para registrar um minério na lista da UI
local function registerOreName(oreName)
    if type(oreName) == "string" and not registeredOresSet[oreName] then
        registeredOresSet[oreName] = true
        
        availableOreTypes = {}
        for ore, _ in pairs(registeredOresSet) do
            table.insert(availableOreTypes, ore)
        end
        table.sort(availableOreTypes)
        return true
    end
    return false
end

-- Varredura inicial no Workspace para alimentar o cache
local function scanAllOres()
    local newFound = false
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model") then
            local oreName = descendant:GetAttribute("OreName")
            if oreName then
                cachedOres[descendant] = oreName
                if registerOreName(oreName) then
                    newFound = true
                end
            end
        end
    end
    return newFound
end

scanAllOres()
if #availableOreTypes == 0 then
    availableOreTypes = {"No ores found yet"}
end

-- Toggle para ativar/desativar a velocidade personalizada (Movido para a aba de Config)
ConfigTab:CreateToggle({
    Name = "Enable WalkSpeed",
    CurrentValue = false,
    Flag = "SpeedToggle",
    Callback = function(Value)
        speedEnabled = Value
        local character = LocalPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = speedEnabled and currentSpeedValue or 16
            end
        end
    end,
})

-- Slider para definir a velocidade
ConfigTab:CreateSlider({
    Name = "Walk Speed",
    Range = {16, 100},
    Increment = 1,
    CurrentValue = 16,
    Flag = "WSSlider",
    Callback = function(Value)
        currentSpeedValue = Value
        if speedEnabled then
            local character = LocalPlayer.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.WalkSpeed = currentSpeedValue
                end
            end
        end
    end,
})

-- Mantém a velocidade ajustada ao renascer
LocalPlayer.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid")
    if speedEnabled then
        humanoid.WalkSpeed = currentSpeedValue
    else
        humanoid.WalkSpeed = 16
    end
end)

-- Dropdown de Seleção de Minérios
local OreDropdown = ESPTab:CreateDropdown({
    Name = "Select Ores",
    Options = availableOreTypes,
    CurrentOption = {},
    MultiSelection = true,
    Flag = "OreDropdownFlag",
    Callback = function(Option)
        selectedOreTypes = {}
        for _, ore in ipairs(Option) do
            selectedOreTypes[ore] = true
        end
    end,
})

-- Botão Refresh List (Força nova varredura e atualiza o cache)
ESPTab:CreateButton({
    Name = "Refresh List",
    Callback = function()
        if scanAllOres() then
            OreDropdown:Refresh(availableOreTypes, true)
            Rayfield:Notify({
                Title = "List Updated",
                Content = "New ores detected, cached and added to the list!",
                Duration = 3,
            })
        else
            Rayfield:Notify({
                Title = "List Checked",
                Content = "Cache updated. No new ore types found.",
                Duration = 3,
            })
        end
    end,
})

-- Escuta dinamicamente novos minérios carregados no mapa e guarda no cache imediatamente
Workspace.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Model") then
        task.wait(0.1)
        local oreName = descendant:GetAttribute("OreName")
        if oreName then
            cachedOres[descendant] = oreName
            if registerOreName(oreName) then
                OreDropdown:Refresh(availableOreTypes, true)
            end
        end
    end
end)

-- Remove do cache caso o minério seja destruído/minerado
Workspace.DescendantRemoving:Connect(function(descendant)
    if cachedOres[descendant] then
        cachedOres[descendant] = nil
        if activeESPs[descendant] then
            if activeESPs[descendant].billboard then
                activeESPs[descendant].billboard:Destroy()
            end
            activeESPs[descendant] = nil
        end
    end
end)

-- Slider de Distância
ESPTab:CreateSlider({
    Name = "Esp Distance",
    Range = {100, 5000},
    Increment = 50,
    CurrentValue = 1500,
    Flag = "DistanceSlider",
    Callback = function(Value)
        MAX_DISTANCE = Value
    end,
})

-- Toggle Principal do ESP
local espEnabled = false
ESPTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Flag = "ESPToggle",
    Callback = function(Value)
        espEnabled = Value
        if not espEnabled then
            for model, espData in pairs(activeESPs) do
                if espData.billboard then
                    espData.billboard:Destroy()
                end
                activeESPs[model] = nil
            end
        end
    end,
})

-- Funções do ESP
local function updateESP(model, targetPart, oreName, distance)
    local distanceText = string.format("[%s]\n[%d studs]", oreName, math.floor(distance))
    
    if not activeESPs[model] then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "DynamicOreESP"
        billboard.Size = UDim2.new(0, 140, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Adornee = targetPart

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 105, 180)
        textLabel.TextStrokeTransparency = 0
        textLabel.TextSize = 13
        textLabel.Font = Enum.Font.SourceSansBold
        textLabel.Text = distanceText
        textLabel.Parent = billboard

        billboard.Parent = targetPart
        activeESPs[model] = { billboard = billboard, label = textLabel }
    else
        activeESPs[model].label.Text = distanceText
    end
end

local function removeESP(model)
    if activeESPs[model] then
        if activeESPs[model].billboard then
            activeESPs[model].billboard:Destroy()
        end
        activeESPs[model] = nil
    end
end

-- Loop de Renderização utilizando o Cache Interno (Muito mais rápido e otimizado)
RunService.Heartbeat:Connect(function()
    if not espEnabled then return end
    
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    for model, oreName in pairs(cachedOres) do
        if model and model.Parent and selectedOreTypes[oreName] then
            local targetPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            
            if targetPart then
                local distance = (rootPart.Position - targetPart.Position).Magnitude
                
                if distance <= MAX_DISTANCE then
                    updateESP(model, targetPart, oreName, distance)
                else
                    removeESP(model)
                end
            else
                removeESP(model)
            end
        else
            removeESP(model)
        end
    end
end)
