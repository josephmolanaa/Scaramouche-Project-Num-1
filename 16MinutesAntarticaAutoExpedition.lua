-- Load Rayfield UI
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInput = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

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

-- UI Window
local Window = Rayfield:CreateWindow({
    Name = "Auto Expedition By Scaramouche",
    LoadingTitle = "Auto Expedition 16 Minute",
    LoadingSubtitle = "by Scaramouche",
    Theme = "Dark",
    KeySystem = false
})

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
-- AUTO REJOIN (tidak diubah)
-- ==============================
local function AttemptRejoin()
    if not autoRejoinEnabled or disconnectSent then return end
    disconnectSent = true
    SendWebhookSync("🔄 Disconnect — Auto Rejoin", "Player **" .. LocalPlayer.Name .. "** disconnect / keluar dari server.\nReconnecting ke server yang sama...\nLoop terakhir: **#" .. loopCount .. "**", 16776960)
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
                SendWebhookSync("❌ Crash / Koneksi Putus", "Player **" .. LocalPlayer.Name .. "** kehilangan koneksi.\nLoop terakhir: **#" .. tostring(loopCount) .. "**", 16711680)
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
-- TELEPORT, AUTO CLICK, AUTO JUMP, dll (sama seperti sebelumnya)
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
        UpdateStatus("Step 2 — South Pole", string.format("🚀 Teleport #%d ke South Pole (Y+%d)...", i, extraY))
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
        UpdateStatus(stepName, string.format("⏳ %02d:%02d tersisa\nLoop #%d", mins, secs, loopCount))
        if secs == 0 and mins > 0 then
            Rayfield:Notify({ Title = stepName, Content = string.format("⏳ %d menit tersisa (Loop #%d)", mins, loopCount), Duration = 8 })
        end
        task.wait(1)
    end
end

-- ==============================
-- EXPEDITION FLOW (BAGIAN YANG DIUBAH)
-- ==============================
local expeditionThread = nil

local function RunExpedition()
    if isRunning then
        Rayfield:Notify({ Title = "⚠️ Sudah Berjalan", Content = "Expedition sudah aktif!", Duration = 4 })
        return
    end

    isRunning = true
    disconnectSent = false
    getgenv().AutoExpedition.isRunning = true

    expeditionThread = task.spawn(function()
        while isRunning do
            loopCount += 1
            getgenv().AutoExpedition.loopCount = loopCount

            Rayfield:Notify({ Title = "Expedition Dimulai", Content = "Loop #" .. loopCount, Duration = 5 })
            UpdateStatus("Expedition Running", "Loop #" .. loopCount .. " — Mulai proses...")

            -- STEP 1: Water Refill
            Rayfield:Notify({ Title = "Step 1 — Water Refill", Content = "16 menit farming...", Duration = 6 })
            UpdateStatus("Step 1 — Water Refill", "🚀 Teleport ke Water Refill...")
            SafeTeleport(Waypoints.WaterRefill)
            StartAutoJump()
            PressTwo()
            StartAutoClick()
            CountdownWait(978, "Step 1 — Water Refill")
            StopAutoJump()
            StopAutoClick()
            if not isRunning then break end

            -- STEP 2: South Pole
            Rayfield:Notify({ Title = "Step 2 — South Pole", Content = "3x Teleport ke South Pole...", Duration = 5 })
            UpdateStatus("Step 2 — South Pole", "🚀 Memulai 3x teleport...")
            SafeTeleportSouthPole()
            if not isRunning then break end

            -- STEP 3: Wait 5s
            Rayfield:Notify({ Title = "Step 3 — Menunggu", Content = "Tunggu 5 detik...", Duration = 5 })
            CountdownWait(5, "Step 3 — Menunggu")
            if not isRunning then break end

            -- STEP 4: Respawn
            Rayfield:Notify({ Title = "Step 4 — Respawn", Content = "Respawn sekarang!", Duration = 5 })
            UpdateStatus("Step 4 — Respawn", "💀 Respawn...")
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
            LocalPlayer.CharacterAdded:Wait()
            if not isRunning then break end

            -- ==================== NOTIFIKASI WEBHOOK SETIAP 10 LOOP ====================
            if loopCount % 10 == 0 then
                SendWebhook(
                    "🏆 Milestone Expedition",
                    "Player **" .. LocalPlayer.Name .. "** telah menyelesaikan **" .. loopCount .. " loop**!\n\n" ..
                    "Target loop: **" .. (targetLoops == 0 and "Infinite" or targetLoops) .. "**\n" ..
                    "Auto Rejoin: **" .. (autoRejoinEnabled and "AKTIF" or "NONAKTIF") .. "**",
                    3066993  -- Warna hijau
                )
                Rayfield:Notify({
                    Title = "🏆 Milestone!",
                    Content = "Webhook dikirim — " .. loopCount .. " loop tercapai!",
                    Duration = 6
                })
            end

            -- Cek target loop
            if targetLoops > 0 and loopCount >= targetLoops then
                Rayfield:Notify({ Title = "✅ Expedition Selesai", Content = "Selesai " .. loopCount .. " loop.", Duration = 10 })
                UpdateStatus("✅ Expedition Selesai", "Selesai " .. loopCount .. " loop!")
                SendWebhook("✅ Expedition Selesai", "Player **" .. LocalPlayer.Name .. "** menyelesaikan **" .. loopCount .. " loop**!", 3066993)
                isRunning = false
                getgenv().AutoExpedition.isRunning = false
                break
            end

            Rayfield:Notify({ Title = "🔁 Loop", Content = "Mengulang dari Step 1...", Duration = 3 })
            UpdateStatus("Loop #" .. loopCount, "🔁 Mengulang dari awal...")
        end

        -- Cleanup
        StopAutoClick()
        StopAutoJump()
        isRunning = false
        getgenv().AutoExpedition.isRunning = false
        expeditionThread = nil
        UpdateStatus("Status", "⏹ Expedition dihentikan.")
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
    Rayfield:Notify({ Title = "Expedition Stopped", Content = "Dihentikan oleh user.", Duration = 5 })
    UpdateStatus("Status", "⏹ Expedition dihentikan oleh user.")
end

-- ==================== UI (sama seperti sebelumnya) ====================
local expeditionTab = Window:CreateTab("Auto Expedition")
expeditionTab:CreateSection("Status")
countdownLabel = expeditionTab:CreateParagraph({ Title = "Status", Content = "⏹ Expedition belum dijalankan\nTekan toggle untuk mulai" })

expeditionTab:CreateSection("Controls")
expeditionTab:CreateToggle({
    Name = "Start Expedition",
    CurrentValue = isRunning,
    Callback = function(value)
        if value then RunExpedition() else StopExpedition() end
    end
})

expeditionTab:CreateToggle({
    Name = "🔄 Enable Auto Rejoin",
    CurrentValue = autoRejoinEnabled,
    Callback = function(value)
        autoRejoinEnabled = value
        getgenv().AutoExpedition.autoRejoinEnabled = value
        Rayfield:Notify({ Title = "Auto Rejoin", Content = value and "✅ Dinyalakan" or "❌ Dimatikan", Duration = 4 })
    end
})

expeditionTab:CreateInput({
    Name = "Loop Count (0 = infinite)",
    PlaceholderText = tostring(targetLoops),
    RemoveTextAfterFocusLost = false,
    Callback = function(value)
        local num = tonumber(value)
        if num and num >= 0 then
            targetLoops = num
            getgenv().AutoExpedition.targetLoops = num
            Rayfield:Notify({ Title = "Loop Updated", Content = "Target loop: " .. (num == 0 and "Infinite" or tostring(num)), Duration = 4 })
        else
            Rayfield:Notify({ Title = "Warning", Content = "Masukkan angka >= 0", Duration = 5 })
        end
    end
})

-- Webhook Tab (sama)
local webhookTab = Window:CreateTab("🔔 Webhook")
webhookTab:CreateSection("Konfigurasi")
webhookTab:CreateInput({
    Name = "Discord Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Callback = function(value)
        webhookURL = value
        getgenv().AutoExpedition.webhookURL = value
        if value ~= "" then
            Rayfield:Notify({ Title = "Webhook Disimpan", Content = "URL tersimpan!", Duration = 4 })
        end
    end
})

webhookTab:CreateButton({
    Name = "🧪 Test Webhook",
    Callback = function()
        if webhookURL == "" then
            Rayfield:Notify({ Title = "Error", Content = "Isi Webhook URL dulu!", Duration = 4 })
            return
        end
        SendWebhook("🧪 Test Webhook Berhasil", "✅ Webhook terhubung!\nPlayer: **" .. LocalPlayer.Name .. "**", 65280)
        Rayfield:Notify({ Title = "✅ Test Dikirim", Content = "Cek channel Discord kamu!", Duration = 5 })
    end
})

-- Camps Tab (sama seperti asli)
local campsTab = Window:CreateTab("🏕️ Camps")
campsTab:CreateSection("Teleport ke Camp")
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
    campsTab:CreateButton({
        Name = camp.name,
        Callback = function()
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = camp.cframe
                Rayfield:Notify({ Title = "Teleport Berhasil", Content = "Berhasil teleport ke " .. camp.name, Duration = 3 })
            end
        end
    })
end

-- ==================== AUTO RESUME ====================
if getgenv().AutoExpedition.isRunning then
    Rayfield:Notify({ Title = "🔄 Auto Rejoined!", Content = "Melanjutkan expedition dari Loop #" .. loopCount, Duration = 8 })
    task.wait(2)
    RunExpedition()
end

Rayfield:Notify({ Title = "Auto Expedition", Content = "Script siap! Auto Rejoin " .. (autoRejoinEnabled and "✅ ON" or "❌ OFF"), Duration = 6 })
