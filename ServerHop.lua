local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ServerHop = {}

local PlaceID = game.PlaceId
local AllIDs = {}
local maxTeleports = getgenv().SmartHop and 10 or 5

-- Validate PlaceID
if not PlaceID or PlaceID == 0 then
    notify("Error", "Invalid PlaceID! Cannot hop servers.", 10)
    PlaceID = 1 -- Set a default to prevent errors
end

local function loadServerList()
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile("NotSameServers.json"))
    end)
    if ok and data then
        for _, id in ipairs(data) do
            AllIDs[tostring(id)] = true
        end
    else
        writefile("NotSameServers.json", HttpService:JSONEncode({}))
    end
end

local function saveServerList()
    local list = {}
    for id in pairs(AllIDs) do
        table.insert(list, id)
    end
    writefile("NotSameServers.json", HttpService:JSONEncode(list))
end

local function isNewServer(ID)
    -- Clear old servers if list is too big (reset after 100 servers)
    local serverCount = 0
    for _ in pairs(AllIDs) do
        serverCount = serverCount + 1
    end
    
    if serverCount > 100 then
        AllIDs = {} -- Reset the list
        saveServerList()
        if getgenv().DebugMode then
            print("[DEBUG] Reset server list (was", serverCount, "servers)")
        end
    end
    
    return not AllIDs[ID]
end

local function teleport(ID)
    AllIDs[ID] = true
    saveServerList()
    Stats.ServersVisited = Stats.ServersVisited + 1
    
    -- Multiple teleport attempts with different methods
    local success = false
    
    -- Method 1: Standard teleport
    local s1, e1 = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, ID, LocalPlayer)
        success = true
    end)
    
    if not success then
        wait(1)
        -- Method 2: Async teleport
        local s2, e2 = pcall(function()
            local teleportOptions = Instance.new("TeleportOptions")
            teleportOptions.ServerInstanceId = ID
            TeleportService:TeleportAsync(PlaceID, {LocalPlayer}, teleportOptions)
            success = true
        end)
    end
    
    if not success then
        wait(1)
        -- Method 3: Force teleport
        local s3, e3 = pcall(function()
            game:GetService("TeleportService"):Teleport(PlaceID)
            success = true
        end)
    end
    
    return success
end
local function getServers(cursor)
    local url = 'https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100'
    if cursor then url = url .. "&cursor=" .. cursor end
    
    local success, result = pcall(function()
        return game:HttpGet(url)
    end)
    
    if success then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(result)
        end)
        if ok then
            return data
        end
    end
    
    -- Fallback if API fails
    notify("API Error", "Server list unavailable, using fallback", 2)
    return nil
end

function ServerHop._serverHop()
    if getgenv().DebugMode then
        print("[DEBUG] Starting server hop...")
        print("[DEBUG] Current JobId:", game.JobId)
    end
    
    notify("Server Hop", "Finding new server...", 3)
    loadServerList()
    
    -- Get current server ID to avoid rejoining
    local currentJobId = game.JobId
    
    -- Method 1: Try teleport with server list
    local success = false
    local attempts = 0
    local cursor = nil
    
    while attempts < 10 and not success do
        local site = getServers(cursor)
        if not site or not site.data then
            if getgenv().DebugMode then
                print("[DEBUG] Failed to get server list")
            end
            break 
        end
        
        cursor = site.nextPageCursor
        
        -- Sort servers by player count
        local servers = site.data
        table.sort(servers, function(a, b) 
            return tonumber(a.playing or 0) < tonumber(b.playing or 0) 
        end)
        
        if getgenv().DebugMode then
            print("[DEBUG] Found", #servers, "servers")
        end
        
        for _, server in ipairs(servers) do
            local id = tostring(server.id)
            -- More lenient server filtering
            if id ~= currentJobId and 
               tonumber(server.playing) < tonumber(server.maxPlayers) then
                
                -- Prioritize low player servers but don't exclude others
                local isLowPop = tonumber(server.playing) < 15
                if not isLowPop and attempts > 5 then
                    -- After 5 attempts, accept any server
                    isLowPop = true
                end
                
                if isLowPop and isNewServer(id) then
                    AllIDs[id] = true
                    saveServerList()
                    Stats.ServersVisited = Stats.ServersVisited + 1
                    
                    notify("Teleporting", "Joining server with " .. server.playing .. "/" .. server.maxPlayers .. " players", 2)
                    
                    if getgenv().DebugMode then
                        print("[DEBUG] Attempting to join server:", id, "Players:", server.playing)
                    end
                    
                    -- Try multiple teleport methods
                    local teleported = false
                    
                    -- Method 1: Direct teleport
                    local s1, e1 = pcall(function()
                        TeleportService:TeleportToPlaceInstance(PlaceID, id, LocalPlayer)
                        teleported = true
                    end)
                    
                    if getgenv().DebugMode and not s1 then
                        print("[DEBUG] Method 1 failed:", e1)
                    end
                    
                    if not teleported then
                        wait(1)
                        -- Method 2: With teleport options
                        local s2, e2 = pcall(function()
                            local teleportOptions = Instance.new("TeleportOptions")
                            teleportOptions.ServerInstanceId = id
                            TeleportService:TeleportAsync(PlaceID, {LocalPlayer}, teleportOptions)
                            teleported = true
                        end)
                        
                        if getgenv().DebugMode and not s2 then
                            print("[DEBUG] Method 2 failed:", e2)
                        end
                    end
                    
                    if teleported then
                        success = true
                        wait(5) -- Give more time for teleport to process
                        break
                    end
                    
                    wait(0.5) -- Small delay between attempts
                end
            end
        end
        
        attempts = attempts + 1
        
        if not cursor or cursor == "null" then
            break
        end
    end
    

function ServerHop.Hop()
    if not success then
        notify("Server Hop", "Using fallback teleport method...", 3)
        
        if getgenv().DebugMode then
            print("[DEBUG] All server list methods failed, using fallback")
        end
        
        -- Save current progress
        local finalDiamond = tonumber(DiamondCount.Text) or 0
        
        -- Try queue teleport
        if syn and syn.queue_on_teleport then
            syn.queue_on_teleport(game:HttpGet("https://raw.githubusercontent.com/YOUR_SCRIPT_URL"))
        elseif queue_on_teleport then
            queue_on_teleport(game:HttpGet("https://raw.githubusercontent.com/YOUR_SCRIPT_URL"))
        end
        
        -- Simple rejoin to random server
        local s = pcall(function()
            TeleportService:Teleport(PlaceID, LocalPlayer)
        end)
        
        if not s then
            -- Last resort: Server browser teleport
            pcall(function()
                game:GetService("TeleportService"):TeleportAsync(PlaceID, {LocalPlayer})
            end)
        end
        
        wait(5)
    end
    
    -- If still here after 5 seconds, force shutdown and rejoin
    if not success then
        notify("Force Hop", "Forcing game restart...", 2)
        
        if getgenv().DebugMode then
            print("[DEBUG] All teleport methods failed, forcing restart")
        end
        
        wait(2)
        LocalPlayer:Kick("Rejoining for better server...")
        wait(1)
        game:Shutdown()
    end
end
end

function ServerHop.ForceHop()
    notify("Server Hop", "Initiating forced server hop...", 2)
    
    if getgenv().DebugMode then
        print("[DEBUG] forceServerHop called")
    end
    
    -- Save data before hop
    pcall(function()
        local data = {
            diamonds = tonumber(DiamondCount.Text) or 0,
            servers = Stats.ServersVisited,
            time = tick() - Stats.StartTime
        }
        writefile("FarmProgress.json", HttpService:JSONEncode(data))
    end)
    
    -- Queue script for next server (replace with your actual script URL)
    local scriptURL = "scripturlhere" -- IMPORTANT: Add your script URL
    
    if syn and syn.queue_on_teleport then
        syn.queue_on_teleport(string.format([[
            repeat wait() until game:IsLoaded()
            wait(3)
            loadstring(game:HttpGet("%s"))()
        ]], scriptURL))
    elseif queue_on_teleport then
        queue_on_teleport(string.format([[
            repeat wait() until game:IsLoaded()
            wait(3)
            loadstring(game:HttpGet("%s"))()
        ]], scriptURL))
    end
    
    wait(0.5)
    
    -- Try server hop first
    local hopped = false
    local hopSuccess, hopError = pcall(function()
        serverHop()
        hopped = true
    end)
    
    if getgenv().DebugMode and not hopSuccess then
        print("[DEBUG] serverHop failed:", hopError)
    end
    
    if hopped then
        wait(10) -- Wait for teleport to process
    end
    
    -- Check if still in same server by checking JobId
    task.wait(2)
    local stillHere = true
    
    -- If still in same server after waiting, force rejoin
    if stillHere then
        notify("Force Rejoin", "Server hop failed, forcing rejoin...", 2)
        wait(1)
        
        -- Method 1: Teleport to same place (random server)
        local s1, e1 = pcall(function()
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end)
        
        if getgenv().DebugMode and not s1 then
            print("[DEBUG] Force rejoin method 1 failed:", e1)
        end
        
        wait(5)
        
        -- Method 2: Kick and rejoin
        if game.JobId == game.JobId then -- Still here
            LocalPlayer:Kick("Auto-rejoining to new server...")
        end
    end
end

return ServerHop
