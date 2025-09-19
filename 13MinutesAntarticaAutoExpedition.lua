-- Load Rayfield UI
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInput = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- UI Window
local Window = Rayfield:CreateWindow({
    Name = "Auto Expedition By JosephStarling",
    LoadingTitle = "Auto Expedition 13 Minute",
    LoadingSubtitle = "by JosephStarling",
    Theme = "Purple",
    KeySystem = false
})

-- Waypoints
local Waypoints = {
    Spawn = CFrame.new(0, 0, 0), -- ganti sesuai koordinat spawn
    SouthPole = CFrame.new(11001.9, 551.5, 103),
    WaterRefill = CFrame.new(-6043.26, -153.62, -60.18)
}

-- State
local isRunning = false
local loopCount = 0
local targetLoops = 0 -- 0 = infinite
local autoClickTask = nil
local autoJumpTask = nil

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
    task.wait(60)
    VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
end)

-- Teleport normal
local function TeleportTo(cf)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    hrp.CFrame = cf
end

-- Teleport aman (3x biar render map dulu, anti void)
local function SafeTeleport(cf)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    for i = 1, 3 do
        hrp.CFrame = cf + Vector3.new(0, i * 2, 0) -- tiap step sedikit lebih tinggi
        task.wait(0.3) -- jeda biar map sempat render
    end
end

-- Auto left click setiap 1 menit
local function StartAutoClick()
    if autoClickTask then return end
    autoClickTask = task.spawn(function()
        while isRunning do
            VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.1)
            VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            task.wait(60)
        end
    end)
end

local function StopAutoClick()
    if autoClickTask then
        task.cancel(autoClickTask)
        autoClickTask = nil
    end
end

-- Auto Jump (jalan terus sampai stop)
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
    if autoJumpTask then
        task.cancel(autoJumpTask)
        autoJumpTask = nil
    end
end

-- Tekan tombol "2" sekali
local function PressTwo()
    VirtualInput:SendKeyEvent(true, Enum.KeyCode.Two, false, game)
    task.wait(0.1)
    VirtualInput:SendKeyEvent(false, Enum.KeyCode.Two, false, game)
end

-- Expedition Flow
local function RunExpedition()
    isRunning = true
    loopCount = 0

    task.spawn(function()
        while isRunning do
            loopCount += 1
            Rayfield:Notify({
                Title = "Expedition Loop",
                Content = "Loop #" .. loopCount .. " started",
                Duration = 5
            })

            -- Step 1: SafeTeleport ke South Pole
            SafeTeleport(Waypoints.SouthPole)

            -- Step 2: Auto Jump + Tekan "2" + AutoClick
            StartAutoJump()
            PressTwo()
            StartAutoClick()

            -- Step 3: Tunggu sampai deteksi "South Pole"
            local reached = false
            while isRunning and not reached do
                for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                    if gui:IsA("TextLabel") and gui.Visible and gui.Text and gui.Text:find("You have made it to") then
                        if gui.Text:find("South Pole") then
                            reached = true
                            break
                        end
                    end
                end
                task.wait(0.5)
            end

            -- Step 4: Stop auto jump setelah sampai
            StopAutoJump()
            if not isRunning then break end

            -- Step 5: Respawn
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
            LocalPlayer.CharacterAdded:Wait()

            -- Step 6: Tunggu 3 detik di spawn
            task.wait(3)

            -- Step 7: Teleport ke Water Refill + Auto Jump 1 menit
            SafeTeleport(Waypoints.WaterRefill)
            StartAutoJump()
            task.wait(60)
            StopAutoJump()

            -- Step 8: Teleport balik ke Spawn
            task.wait(2)
            TeleportTo(Waypoints.Spawn)
            task.wait(2)

            -- Step 9: Cek loop
            if targetLoops > 0 and loopCount >= targetLoops then
                Rayfield:Notify({
                    Title = "Expedition Complete",
                    Content = "Completed " .. loopCount .. " loops.",
                    Duration = 5
                })
                isRunning = false
                break
            end
        end
        StopAutoClick()
        StopAutoJump()
    end)
end

local function StopExpedition()
    isRunning = false
    StopAutoClick()
    StopAutoJump()
    Rayfield:Notify({
        Title = "Expedition Stopped",
        Content = "Stopped by user.",
        Duration = 5
    })
end

-- UI Controls
local expeditionTab = Window:CreateTab("Auto Expedition")

expeditionTab:CreateToggle({
    Name = "Start Expedition",
    CurrentValue = false,
    Callback = function(value)
        if value then RunExpedition() else StopExpedition() end
    end
})

expeditionTab:CreateInput({
    Name = "Loop Count (0 = infinite)",
    PlaceholderText = "0",
    RemoveTextAfterFocusLost = false,
    Callback = function(value)
        local num = tonumber(value)
        if num and num >= 0 then
            targetLoops = num
        else
            Rayfield:Notify({
                Title = "Warning",
                Content = "Loop count must be >= 0",
                Duration = 5
            })
        end
    end
})
