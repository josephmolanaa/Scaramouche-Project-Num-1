-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInput = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- Mock Rayfield to intercept Notify calls seamlessly
local Rayfield = {
    Notify = function(self, data)
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = data.Title or "Notification",
                Text = data.Content or "",
                Duration = data.Duration or 5
            })
        end)
    end
}

-- ==================== AUTO REJOIN SETUP ====================
local PlaceId = game.PlaceId
local JobId = game.JobId

getgenv().AutoExpedition = getgenv().AutoExpedition or {
    isRunning = false,
    loopCount = 0,
    targetLoops = 0,
    webhookURL = "",
    autoRejoinEnabled = true
}

-- ==================== TOTAL EXPEDITION TRACKING ====================
local function GetInGameExpeditions()
    local myUserIdStr = tostring(LocalPlayer.UserId)
    
    -- Mencari folder RankBillboards% di Workspace
    for _, obj in ipairs(workspace:GetChildren()) do
        if string.find(obj.Name, "RankBillboards") then
            -- Mencari BillboardGui yang namanya sama dengan UserId kita
            local myBillboard = obj:FindFirstChild(myUserIdStr)
            if myBillboard then
                local frame = myBillboard:FindFirstChild("Frame")
                if frame then
                    -- Teks berisi statistik ada di TextLabel bernama "Premium"
                    local premiumLbl = frame:FindFirstChild("Premium")
                    if premiumLbl and premiumLbl:IsA("TextLabel") then
                        local num = string.match(premiumLbl.Text, "Expeditions?:%s*(%d+)")
                        if num then
                            return num
                        end
                    end
                end
            end
        end
    end
    
    -- Fallback ke leaderstats standar jika leaderboard belum termuat
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local exp = leaderstats:FindFirstChild("Expeditions") or leaderstats:FindFirstChild("Expedition")
        if exp then return exp.Value end
    end
    
    return "Getting Data..."
end

-- Waypoints
local Waypoints = {
    SouthPole = CFrame.new(11001.9, 551.5, 103),
    WaterRefill = CFrame.new(-6043.26, -153.62, -60.18)
}

-- State
local isRunning = false
local loopCount = getgenv().AutoExpedition.loopCount
local targetLoops = getgenv().AutoExpedition.targetLoops
local webhookURL = getgenv().AutoExpedition.webhookURL
local autoRejoinEnabled = getgenv().AutoExpedition.autoRejoinEnabled

getgenv().AutoExpedition.isRunning = false

local autoClickTask = nil
local autoJumpTask = nil
local countdownLabel = nil
local disconnectSent = false

-- ==============================
-- HELPER: Update Status Paragraph
-- ==============================
local function UpdateStatus(title, content)
    if not countdownLabel then return end
    countdownLabel:Set({ Title = title, Content = content })
end

-- ==============================
-- WEBHOOK
-- ==============================
local function GetHttpFn()
    local fn = nil
    pcall(function() if syn and syn.request then fn = syn.request end end)
    if fn then return fn end
    pcall(function() if http and http.request then fn = http.request end end)
    if fn then return fn end
    pcall(function() if typeof(request) == "function" then fn = request end end)
    return fn
end

local function BuildWebhookBody(title, description, color)
    local ok, body = pcall(function()
        return HttpService:JSONEncode({
            embeds = {{
                title = title,
                description = description,
                color = color or 16711680,
                footer = { text = "Auto Expedition by Scaramouche • " .. LocalPlayer.Name },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        })
    end)
    return ok and body or nil
end

local function SendWebhook(title, description, color)
    if webhookURL == "" then return end
    local body = BuildWebhookBody(title, description, color)
    if not body then return end

    task.spawn(function()
        local fn = GetHttpFn()
        if fn then
            pcall(fn, { Url = webhookURL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        else
            pcall(function() HttpService:PostAsync(webhookURL, body, Enum.HttpContentType.ApplicationJson) end)
        end
    end)
end

local function SendWebhookSync(title, description, color)
    if webhookURL == "" then return end
    local body = BuildWebhookBody(title, description, color)
    if not body then return end

    local fn = GetHttpFn()
    if fn then
        pcall(fn, { Url = webhookURL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    else
        pcall(function() HttpService:PostAsync(webhookURL, body, Enum.HttpContentType.ApplicationJson) end)
    end
end

-- ==============================
-- AUTO REJOIN
-- ==============================
local function AttemptRejoin()
    if not autoRejoinEnabled or disconnectSent then return end
    disconnectSent = true
    SendWebhookSync("🔄 Disconnect — Auto Rejoin", "Player **" .. LocalPlayer.Name .. "** disconnect / out of server.\nReconnecting to the same server...\nLast Loop: **#" .. loopCount .. "**", 16776960)
    task.wait(1.5)
    pcall(function() TeleportService:TeleportToPlaceInstance(PlaceId, JobId) end)
end

Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then AttemptRejoin() end
end)

pcall(function() game:BindToClose(function() AttemptRejoin() end) end)

-- Heartbeat Monitor
local lastHeartbeat = tick()
RunService.Heartbeat:Connect(function() lastHeartbeat = tick() end)

task.spawn(function()
    while true do
        task.wait(1)
        if tick() - lastHeartbeat > 8 then
            if not disconnectSent and webhookURL ~= "" then
                disconnectSent = true
                SendWebhookSync("❌ Crash / Disconnect", "Player **" .. LocalPlayer.Name .. "** Out of connection.\nLast Loop: **#" .. tostring(loopCount) .. "**", 16711680)
            end
            if autoRejoinEnabled then
                pcall(function() TeleportService:TeleportToPlaceInstance(PlaceId, JobId) end)
            end
            break
        end
    end
end)

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
    task.wait(60)
    VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
end)

-- ==============================
-- TELEPORT, AUTO CLICK, AUTO JUMP, dll
-- ==============================
local function SafeTeleport(cf)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    for i = 1, 3 do
        hrp.CFrame = cf + Vector3.new(0, i * 2, 0)
        task.wait(0.3)
    end
end

local function SafeTeleportSouthPole()
    local sp = Waypoints.SouthPole
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    local baseY = sp.Y
    local ySteps = {5, 10, 15}
    for i, extraY in ipairs(ySteps) do
        hrp.CFrame = CFrame.new(sp.X, baseY + extraY, sp.Z)
        UpdateStatus("Step 2 — South Pole", string.format("🚀 Teleport #%d to South Pole (Y+%d)...", i, extraY))
        task.wait(0.5)
    end
end

local function StartAutoClick()
    if autoClickTask then return end
    autoClickTask = task.spawn(function()
        while isRunning do
            pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
            task.wait(0.1)
            pcall(function() VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
            task.wait(60)
        end
    end)
end

local function StopAutoClick()
    if autoClickTask then task.cancel(autoClickTask) autoClickTask = nil end
end

local function StartAutoJump()
    if autoJumpTask then return end
    autoJumpTask = task.spawn(function()
        while isRunning do
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial ~= Enum.Material.Air then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            task.wait(1)
        end
    end)
end

local function StopAutoJump()
    if autoJumpTask then task.cancel(autoJumpTask) autoJumpTask = nil end
end

local function PressTwo()
    pcall(function() VirtualInput:SendKeyEvent(true, Enum.KeyCode.Two, false, game) end)
    task.wait(0.1)
    pcall(function() VirtualInput:SendKeyEvent(false, Enum.KeyCode.Two, false, game) end)
end

local function CountdownWait(totalSeconds, stepName)
    local endTime = tick() + totalSeconds
    while isRunning and tick() < endTime do
        local remaining = math.ceil(endTime - tick())
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        UpdateStatus(stepName, string.format("⏳ %02d:%02d Left\nLoop #%d", mins, secs, loopCount))
        if secs == 0 and mins > 0 then
            Rayfield:Notify({ Title = stepName, Content = string.format("⏳ %d minutes Left (Loop #%d)", mins, loopCount), Duration = 8 })
        end
        task.wait(1)
    end
end

-- ==============================
-- EXPEDITION FLOW
-- ==============================
local expeditionThread = nil

local function RunExpedition()
    if isRunning then
        Rayfield:Notify({ Title = "⚠️ Running", Content = "Expedition is already active!", Duration = 4 })
        return
    end

    isRunning = true
    disconnectSent = false
    getgenv().AutoExpedition.isRunning = true

    expeditionThread = task.spawn(function()
        while isRunning do
            loopCount += 1
            getgenv().AutoExpedition.loopCount = loopCount

            Rayfield:Notify({ Title = "Expedition Started", Content = "Loop #" .. loopCount, Duration = 5 })
            UpdateStatus("Expedition Running", "Loop #" .. loopCount .. " — Starting process...")

            -- STEP 1: Water Refill
            Rayfield:Notify({ Title = "Step 1 — Water Refill", Content = "13.45 menit farming...", Duration = 6 })
            UpdateStatus("Step 1 — Water Refill", "🚀 Teleport to Water Refill...")
            SafeTeleport(Waypoints.WaterRefill)
            StartAutoJump()
            PressTwo()
            StartAutoClick()
            CountdownWait(840, "Step 1 — Water Refill")
            StopAutoJump()
            StopAutoClick()
            if not isRunning then break end

            -- STEP 2: South Pole
            Rayfield:Notify({ Title = "Step 2 — South Pole", Content = "3x Teleport to South Pole...", Duration = 5 })
            UpdateStatus("Step 2 — South Pole", "🚀 Starting 3x teleport...")
            SafeTeleportSouthPole()
            if not isRunning then break end

            -- STEP 3: Wait 5s
            Rayfield:Notify({ Title = "Step 3 — Waiting", Content = "Waiting for 5 seconds...", Duration = 5 })
            CountdownWait(5, "Step 3 — Waiting")
            if not isRunning then break end

            -- STEP 4: Respawn
            Rayfield:Notify({ Title = "Step 4 — Respawn", Content = "Respawning now!", Duration = 5 })
            UpdateStatus("Step 4 — Respawn", "💀 Respawn...")
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
            LocalPlayer.CharacterAdded:Wait()
            if not isRunning then break end

            -- ==================== NOTIFIKASI WEBHOOK ====================
            if loopCount % 5 == 0 then
                local currentTotal = GetInGameExpeditions()
                SendWebhook(
                    "🏆 Milestone Expedition",
                    "Player **" .. LocalPlayer.Name .. "** has reached **" .. tostring(currentTotal) .. " Total Expedition**!\n\n" ..
                    "Loop Right Now: **" .. loopCount .. "**\n" ..
                    "Target loop: **" .. (targetLoops == 0 and "Infinite" or targetLoops) .. "**\n" ..
                    "Auto Rejoin: **" .. (autoRejoinEnabled and "ACTIVE" or "INACTIVE") .. "**",
                    3066993  -- Warna hijau
                )
                Rayfield:Notify({ Title = "🏆 Milestone!", Content = "Webhook sent — " .. loopCount .. " loop reached!", Duration = 6 })
            end

            if targetLoops > 0 and loopCount >= targetLoops then
                Rayfield:Notify({ Title = "✅ Expedition Finished", Content = "Finished " .. loopCount .. " loop.", Duration = 10 })
                UpdateStatus("✅ Expedition Finished", "Finished " .. loopCount .. " loop!")
                SendWebhook("✅ Expedition Selesai", "Player **" .. LocalPlayer.Name .. "** menyelesaikan **" .. loopCount .. " loop**!", 3066993)
                isRunning = false
                getgenv().AutoExpedition.isRunning = false
                break
            end

            Rayfield:Notify({ Title = "🔁 Loop", Content = "🔁 Starting from Step 1...", Duration = 3 })
            UpdateStatus("Loop #" .. loopCount, "🔁 Starting from Step 1...")
        end

        StopAutoClick()
        StopAutoJump()
        isRunning = false
        getgenv().AutoExpedition.isRunning = false
        expeditionThread = nil
        UpdateStatus("Status", "⏹ Expedition stopped.")
    end)
end

local function StopExpedition()
    isRunning = false
    getgenv().AutoExpedition.isRunning = false
    StopAutoClick()
    StopAutoJump()
    if expeditionThread then
        task.cancel(expeditionThread)
        expeditionThread = nil
    end
    Rayfield:Notify({ Title = "Expedition Stopped", Content = "Stopped by user.", Duration = 5 })
    UpdateStatus("Status", "⏹ Expedition stopped by user.")
end

-- ==================== MODERN UI BUILDER ====================
local Theme = {
    Background = Color3.fromRGB(15, 18, 26),
    SidebarBg = Color3.fromRGB(12, 14, 20),
    Accent = Color3.fromRGB(0, 180, 220),
    ItemBg = Color3.fromRGB(25, 29, 38),
    ItemHover = Color3.fromRGB(30, 35, 45),
    TextLight = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(130, 135, 145),
    ToggleOn = Color3.fromRGB(0, 180, 220),
    ToggleOff = Color3.fromRGB(40, 45, 55)
}

local existingUI = CoreGui:FindFirstChild("AutoExpModernUI")
if existingUI then existingUI:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoExpModernUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

-- Main Container
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 340)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -170)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

-- Topbar
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 30)
Topbar.BackgroundTransparency = 1
Topbar.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Auto Expedition | Version 1.0.1"
TitleLabel.TextColor3 = Theme.Accent
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Topbar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -30, 0, 0)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X" -- Berubah jadi huruf K
CloseBtn.TextColor3 = Theme.TextDim
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Parent = Topbar
CloseBtn.MouseButton1Click:Connect(function() 
    MainFrame.Visible = false -- Hanya menyembunyikan UI (Hide), script tetap jalan
end)
CloseBtn.MouseEnter:Connect(function() CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80) end)
CloseBtn.MouseLeave:Connect(function() CloseBtn.TextColor3 = Theme.TextDim end)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -60, 0, 0)
MinBtn.BackgroundTransparency = 1
MinBtn.Text = "—"
MinBtn.TextColor3 = Theme.TextDim
MinBtn.Font = Enum.Font.Gotham
MinBtn.TextSize = 14
MinBtn.Parent = Topbar
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    MainFrame.Size = minimized and UDim2.new(0, 500, 0, 30) or UDim2.new(0, 500, 0, 340)
    for _, child in ipairs(MainFrame:GetChildren()) do
        if child ~= Topbar and child:IsA("GuiObject") then child.Visible = not minimized end
    end
end)

-- Sidebar Background
local SidebarBg = Instance.new("Frame")
SidebarBg.Size = UDim2.new(0, 140, 1, -30)
SidebarBg.Position = UDim2.new(0, 0, 0, 30)
SidebarBg.BackgroundColor3 = Theme.SidebarBg
SidebarBg.BorderSizePixel = 0
SidebarBg.Parent = MainFrame

local SidebarCorner = Instance.new("UICorner")
SidebarCorner.CornerRadius = UDim.new(0, 8)
SidebarCorner.Parent = SidebarBg

local SidebarTopCover = Instance.new("Frame")
SidebarTopCover.Size = UDim2.new(0, 140, 0, 10)
SidebarTopCover.Position = UDim2.new(0, 0, 0, 30)
SidebarTopCover.BackgroundColor3 = Theme.SidebarBg
SidebarTopCover.BorderSizePixel = 0
SidebarTopCover.Parent = MainFrame

local SidebarRightCover = Instance.new("Frame")
SidebarRightCover.Size = UDim2.new(0, 10, 1, -30)
SidebarRightCover.Position = UDim2.new(0, 130, 0, 30)
SidebarRightCover.BackgroundColor3 = Theme.SidebarBg
SidebarRightCover.BorderSizePixel = 0
SidebarRightCover.Parent = MainFrame

-- Sidebar Content
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 140, 1, -30)
Sidebar.Position = UDim2.new(0, 0, 0, 30)
Sidebar.BackgroundTransparency = 1
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarList = Instance.new("UIListLayout")
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Padding = UDim.new(0, 2)
SidebarList.Parent = Sidebar
local SidebarPadding = Instance.new("UIPadding", Sidebar)
SidebarPadding.PaddingTop = UDim.new(0, 10)
SidebarPadding.PaddingLeft = UDim.new(0, 5)
SidebarPadding.PaddingRight = UDim.new(0, 5)

-- Content Area
local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -140, 1, -30)
ContentArea.Position = UDim2.new(0, 140, 0, 30)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local currentTabBtn = nil
local currentContainer = nil

-- UI Components Builder
local function CreateTab(name, icon)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 32)
    Btn.BackgroundColor3 = Theme.ItemBg
    Btn.BackgroundTransparency = 1
    Btn.Text = "  " .. icon .. "  " .. name
    Btn.TextColor3 = Theme.TextDim
    Btn.Font = Enum.Font.GothamSemibold
    Btn.TextSize = 13
    Btn.TextXAlignment = Enum.TextXAlignment.Left
    Btn.Parent = Sidebar
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)

    local Highlight = Instance.new("Frame")
    Highlight.Size = UDim2.new(0, 3, 0, 18)
    Highlight.Position = UDim2.new(0, 0, 0.5, -9)
    Highlight.BackgroundColor3 = Theme.Accent
    Highlight.BorderSizePixel = 0
    Highlight.Visible = false
    Highlight.Parent = Btn
    Instance.new("UICorner", Highlight).CornerRadius = UDim.new(1, 0)

    local Container = Instance.new("ScrollingFrame")
    Container.Size = UDim2.new(1, -20, 1, -20)
    Container.Position = UDim2.new(0, 10, 0, 10)
    Container.BackgroundTransparency = 1
    Container.ScrollBarThickness = 2
    Container.ScrollBarImageColor3 = Theme.Accent
    Container.Visible = false
    Container.Parent = ContentArea

    local Layout = Instance.new("UIListLayout")
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Padding = UDim.new(0, 8)
    Layout.Parent = Container

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, 0, 0, 40)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = name
    TitleLabel.TextColor3 = Theme.TextLight
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 22
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = Container

    Btn.MouseButton1Click:Connect(function()
        if currentContainer then currentContainer.Visible = false end
        if currentTabBtn then 
            currentTabBtn.BackgroundTransparency = 1
            currentTabBtn.TextColor3 = Theme.TextDim
            currentTabBtn:FindFirstChild("Frame").Visible = false
        end
        
        Container.Visible = true
        Btn.BackgroundTransparency = 0
        Btn.TextColor3 = Theme.TextLight
        Highlight.Visible = true
        
        currentContainer = Container
        currentTabBtn = Btn
    end)

    if not currentContainer then
        Container.Visible = true
        Btn.BackgroundTransparency = 0
        Btn.TextColor3 = Theme.TextLight
        Highlight.Visible = true
        currentContainer = Container
        currentTabBtn = Btn
    end

    Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Container.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 10)
    end)

    return Container
end

local function AddParagraph(parent, title, content)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 65)
    Frame.BackgroundColor3 = Theme.ItemBg
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local Txt = Instance.new("TextLabel")
    Txt.Size = UDim2.new(1, -20, 1, -10)
    Txt.Position = UDim2.new(0, 10, 0, 5)
    Txt.BackgroundTransparency = 1
    Txt.TextColor3 = Theme.TextDim
    Txt.Text = title .. "\n" .. content
    Txt.TextWrapped = true
    Txt.TextXAlignment = Enum.TextXAlignment.Left
    Txt.TextYAlignment = Enum.TextYAlignment.Top
    Txt.Font = Enum.Font.Gotham
    Txt.TextSize = 12
    Txt.Parent = Frame

    return { Set = function(self, data) Txt.Text = (data.Title or title) .. "\n" .. (data.Content or content) end }
end

local function AddToggle(parent, text, subtext, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 45)
    Frame.BackgroundColor3 = Theme.ItemBg
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(1, -70, 0, 20)
    Lbl.Position = UDim2.new(0, 12, 0, 5)
    Lbl.BackgroundTransparency = 1
    Lbl.TextColor3 = Theme.TextLight
    Lbl.Text = text
    Lbl.Font = Enum.Font.GothamSemibold
    Lbl.TextSize = 13
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = Frame

    local SubLbl = Instance.new("TextLabel")
    SubLbl.Size = UDim2.new(1, -70, 0, 15)
    SubLbl.Position = UDim2.new(0, 12, 0, 23)
    SubLbl.BackgroundTransparency = 1
    SubLbl.TextColor3 = Theme.TextDim
    SubLbl.Text = subtext or ""
    SubLbl.Font = Enum.Font.Gotham
    SubLbl.TextSize = 11
    SubLbl.TextXAlignment = Enum.TextXAlignment.Left
    SubLbl.Parent = Frame

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 36, 0, 20)
    Btn.Position = UDim2.new(1, -48, 0.5, -10)
    Btn.BackgroundColor3 = default and Theme.ToggleOn or Theme.ToggleOff
    Btn.Text = ""
    Btn.Parent = Frame
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(1, 0)

    local Indicator = Instance.new("Frame")
    Indicator.Size = UDim2.new(0, 14, 0, 14)
    Indicator.Position = default and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Indicator.Parent = Btn
    Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)

    local state = default
    Btn.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(Btn, TweenInfo.new(0.2), {BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff}):Play()
        TweenService:Create(Indicator, TweenInfo.new(0.2), {Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)}):Play()
        callback(state)
    end)
end

local function AddInput(parent, text, defaultVal, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 45)
    Frame.BackgroundColor3 = Theme.ItemBg
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(0, 120, 1, 0)
    Lbl.Position = UDim2.new(0, 12, 0, 0)
    Lbl.BackgroundTransparency = 1
    Lbl.TextColor3 = Theme.TextLight
    Lbl.Text = text
    Lbl.Font = Enum.Font.GothamSemibold
    Lbl.TextSize = 13
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = Frame

    local Box = Instance.new("TextBox")
    Box.Size = UDim2.new(1, -145, 0, 26)
    Box.Position = UDim2.new(0, 135, 0.5, -13)
    Box.BackgroundColor3 = Theme.Background
    Box.TextColor3 = Theme.TextLight
    Box.PlaceholderText = "Type here..."
    Box.Text = defaultVal or ""
    Box.Font = Enum.Font.Gotham
    Box.TextSize = 12
    Box.TextXAlignment = Enum.TextXAlignment.Left
    Box.ClearTextOnFocus = false
    Box.ClipsDescendants = true
    Box.Parent = Frame
    Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 4)
    local Padding = Instance.new("UIPadding", Box)
    Padding.PaddingLeft = UDim.new(0, 8)
    Padding.PaddingRight = UDim.new(0, 8)

    Box.FocusLost:Connect(function() callback(Box.Text) end)
    return Box
end

local function AddButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 35)
    Btn.BackgroundColor3 = Theme.ItemBg
    Btn.TextColor3 = Theme.TextLight
    Btn.Text = text
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = 13
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)
    
    Btn.MouseEnter:Connect(function() TweenService:Create(Btn, TweenInfo.new(0.2), {BackgroundColor3 = Theme.ItemHover}):Play() end)
    Btn.MouseLeave:Connect(function() TweenService:Create(Btn, TweenInfo.new(0.2), {BackgroundColor3 = Theme.ItemBg}):Play() end)
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

-- ==================== POPULATING TABS ====================
local mainTab = CreateTab("Expedition", "▶️")
countdownLabel = AddParagraph(mainTab, "Status Tracker", "⏹ Expedition not started\nPress toggle to start")
AddToggle(mainTab, "Start Expedition", "Auto farming & teleport", isRunning, function(val)
    if val then RunExpedition() else StopExpedition() end
end)
AddToggle(mainTab, "Auto Rejoin", "Auto rejoin when DC", autoRejoinEnabled, function(val)
    autoRejoinEnabled = val
    getgenv().AutoExpedition.autoRejoinEnabled = val
    Rayfield:Notify({ Title = "Auto Rejoin", Content = val and "✅ Enabled" or "❌ Disabled", Duration = 4 })
end)
AddInput(mainTab, "Limit Loop", tostring(targetLoops), function(val)
    local num = tonumber(val)
    if num and num >= 0 then
        targetLoops = num
        getgenv().AutoExpedition.targetLoops = num
        Rayfield:Notify({ Title = "Loop Updated", Content = "Target loop: " .. (num == 0 and "Infinite" or tostring(num)), Duration = 4 })
    end
end)

local webTab = CreateTab("Webhook", "🔔")
AddParagraph(webTab, "Discord Notifications", "Insert webhook URL to receive reports per 5 loops & disconnect.")
local WebhookInputBox = AddInput(webTab, "Webhook URL", webhookURL, function(val)
    if val and val ~= "" then
        webhookURL = val
        getgenv().AutoExpedition.webhookURL = val
        Rayfield:Notify({ Title = "Saved", Content = "Webhook successfully connected!", Duration = 4 })
    end
end)
AddButton(webTab, "🧪 Test Bot Webhook", function()
    if webhookURL == "" then return Rayfield:Notify({ Title = "Error", Content = "Please enter a webhook URL first!", Duration = 4 }) end
    SendWebhook("🧪 Test Webhook Successful", "✅ Webhook connected!\nPlayer: **" .. LocalPlayer.Name .. "**", 65280)
    Rayfield:Notify({ Title = "Test Sent", Content = "Check your Discord channel!", Duration = 5 })
end)
AddButton(webTab, "🗑️ Delete Webhook", function()
    webhookURL = ""
    getgenv().AutoExpedition.webhookURL = ""
    WebhookInputBox.Text = ""
    Rayfield:Notify({ Title = "Deleted", Content = "Webhook URL deleted.", Duration = 4 })
end)

local campTab = CreateTab("Teleport", "🏕️")
local Camps = {
    { name = "🏕️ Camp 1", cframe = CFrame.new(-(4236.6 - (114 + 404)), 227.4, 723.6 - (106 + 382)) },
    { name = "🏕️ Camp 2", cframe = CFrame.new(1789.7, 107.8, -137) },
    { name = "🏕️ Camp 2.5", cframe = CFrame.new(5635.53, 341.25, 92.76) },
    { name = "🏕️ Camp 3", cframe = CFrame.new(5892.1, 323.4, -20.3) },
    { name = "🏕️ Camp 4", cframe = CFrame.new(8992.2, 598, 102.6) },
    { name = "🚩 South Pole", cframe = CFrame.new(11001.9, 551.5, 103) },
    { name = "💧 Water Refill", cframe = CFrame.new(-6043.26, -153.62, -60.18) },
}
for _, camp in ipairs(Camps) do
    AddButton(campTab, camp.name, function()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = camp.cframe end
    end)
end

local statsTab = CreateTab("Statistic", "📊")
local totalLbl = AddParagraph(statsTab, "Server Data", "Loading data from server...")
task.spawn(function()
    while task.wait(2) do
        local currentStats = GetInGameExpeditions()
        totalLbl:Set({ Content = "Total success: **" .. tostring(currentStats) .. "** Expeditions." })
    end
end)
AddButton(statsTab, "🔄 Refresh Data", function()
    local currentStats = GetInGameExpeditions()
    totalLbl:Set({ Content = "Total success: **" .. tostring(currentStats) .. "** Expeditions." })
end)

-- Toggle UI Hotkey (Tombol K)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Kalau pencet K di keyboard, UI bakal sembunyi/muncul
    if not gameProcessed and input.KeyCode == Enum.KeyCode.K then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- Auto Resume Support
if getgenv().AutoExpedition.isRunning then
    Rayfield:Notify({ Title = "🔄 Auto Rejoined!", Content = "Resuming expedition...", Duration = 8 })
    task.wait(2)
    RunExpedition()
end

Rayfield:Notify({ Title = "Loaded", Content = "Modern UI by Scaramouche ready to use!", Duration = 6 })