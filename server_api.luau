local ServerHopAPI = {}

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService") -- Needed for JobId

-- Default configuration values
local config = {
    MaxRetries = 3, -- Maximum number of retries for HTTP requests
    RetryDelay = 15, -- Delay in seconds between retries for 429 errors
    ApiBaseUrl = "https://solvent.xvh.lol/v1/servers/", -- Default API endpoint
    SortOrder = nil, -- API default is Desc, nil means don't send param unless configured
    Limit = nil, -- API default is 10, nil means don't send param unless configured
    ExcludeFullGames = nil -- API default is true, nil means don't send param unless configured
}

local ALLOWED_LIMITS = {
    [10] = true,
    [25] = true,
    [50] = true,
    [100] = true
}
local ALLOWED_SORT_ORDERS = {
    Asc = true,
    Desc = true
}

--- Configures the ServerHopAPI module settings.
-- @param options table? A table containing configuration options.
--   - MaxRetries (number?): Maximum number of retries for HTTP requests (default: 3). Must be >= 0.
--   - RetryDelay (number?): Delay in seconds between retries for 429 errors (default: 15). Must be > 0.
--   - ApiBaseUrl (string?): The base URL for the server list API (default: "https://solvent.xvh.lol/v1/servers/").
--   - SortOrder (string?): API sort order ('Asc' or 'Desc'). Defaults to API default (Desc).
--   - Limit (number?): API limit (10, 25, 50, 100). Defaults to API default (10).
--   - ExcludeFullGames (boolean?): API flag to exclude full games. Defaults to API default (true).
function ServerHopAPI.Configure(options)
    if type(options) ~= "table" then
        return
    end

    if type(options.MaxRetries) == "number" and options.MaxRetries >= 0 then
        config.MaxRetries = math.floor(options.MaxRetries) -- Ensure integer
    end
    if type(options.RetryDelay) == "number" and options.RetryDelay > 0 then
        config.RetryDelay = options.RetryDelay
    end
    if type(options.ApiBaseUrl) == "string" then
        -- Basic check: ensure it's not empty and maybe ends with /
        if options.ApiBaseUrl ~= "" then
            config.ApiBaseUrl = options.ApiBaseUrl
            -- Ensure it ends with a slash for consistency
            if not string.sub(config.ApiBaseUrl, -1) == "/" then
                config.ApiBaseUrl = config.ApiBaseUrl .. "/"
            end
        else
            warn("ServerHopAPI.Configure: Invalid ApiBaseUrl value (cannot be empty).")
        end
    elseif options.ApiBaseUrl ~= nil then -- Warn if provided but not a string
        warn("ServerHopAPI.Configure: Invalid ApiBaseUrl value '" .. tostring(options.ApiBaseUrl) ..
                 "'. Must be a string.")
    end

    if options.SortOrder ~= nil then
        if ALLOWED_SORT_ORDERS[options.SortOrder] then
            config.SortOrder = options.SortOrder
        else
            warn("ServerHopAPI.Configure: Invalid SortOrder value '" .. tostring(options.SortOrder) ..
                     "'. Allowed: 'Asc', 'Desc'.")
        end
    end
    if options.Limit ~= nil then
        if ALLOWED_LIMITS[options.Limit] then
            config.Limit = options.Limit
        else
            warn("ServerHopAPI.Configure: Invalid Limit value '" .. tostring(options.Limit) ..
                     "'. Allowed: 10, 25, 50, 100.")
        end
    end
    if options.ExcludeFullGames ~= nil then
        if type(options.ExcludeFullGames) == "boolean" then
            config.ExcludeFullGames = options.ExcludeFullGames
        else
            warn("ServerHopAPI.Configure: Invalid ExcludeFullGames value '" .. tostring(options.ExcludeFullGames) ..
                     "'. Must be boolean.")
        end
    end
end

local function _shuffleTable(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

-- Private: Fetches and decodes server data with retry logic for 429 errors.
local function _fetchAndDecodeServerData(placeId)
    local currentTry = 0
    local baseUrl = config.ApiBaseUrl .. placeId -- Use configured base URL
    local queryParams = {}

    -- Add query parameters based on configuration if they are set
    if config.SortOrder then
        table.insert(queryParams, "sortOrder=" .. config.SortOrder)
    end
    if config.Limit then
        table.insert(queryParams, "limit=" .. config.Limit)
    end
    if config.ExcludeFullGames ~= nil then -- Check if explicitly set (true or false)
        table.insert(queryParams, "excludeFullGames=" .. tostring(config.ExcludeFullGames))
    end

    local requestUrl = baseUrl
    if #queryParams > 0 then
        requestUrl = requestUrl .. "?" .. table.concat(queryParams, "&")
    end

    while currentTry < config.MaxRetries do
        currentTry = currentTry + 1
        local success, response = pcall(function()
            return game:HttpGetAsync(requestUrl)
        end)

        if not success then
            warn("ServerHopAPI._fetchAndDecodeServerData: HTTP Get Failed (Try " .. currentTry .. "):", response)
            if currentTry >= config.MaxRetries then
                return nil,
                    "Failed to fetch server list after " .. config.MaxRetries .. " attempts: " .. tostring(response)
            end
            task.wait(1) -- Short wait before retry on general failure
        elseif type(response) == "string" and string.find(response, "HTTP 429") then
            warn("ServerHopAPI._fetchAndDecodeServerData: Received 429 Too Many Requests (Try " .. currentTry ..
                     "). Retrying in " .. config.RetryDelay .. " seconds...")
            if currentTry >= config.MaxRetries then
                return nil, "Failed to fetch server list due to rate limiting (429) after " .. config.MaxRetries ..
                    " attempts."
            end
            task.wait(config.RetryDelay)
        else
            -- Attempt to decode
            local decodeSuccess, data = pcall(function()
                return HttpService:JSONDecode(response)
            end)

            if not decodeSuccess then
                warn("ServerHopAPI._fetchAndDecodeServerData: JSON Decode Failed:", data) -- 'data' here is the error message
                return nil, "Failed to decode server list response: " .. tostring(data)
            end

            if not data or not data.data then
                warn("ServerHopAPI._fetchAndDecodeServerData: Decoded data is invalid or missing 'data' field:", data)
                return nil, "Server list response format is invalid."
            end

            -- Success
            return data.data, nil
        end
    end
    -- Should not be reached if config.MaxRetries > 0, but included for safety
    return nil, "Failed to fetch server list after " .. config.MaxRetries .. " attempts."
end

-- Private: Filters raw server data.
local function _filterServers(serverData)
    if not serverData then
        return {}
    end -- Return empty table if input is nil

    local currentJobId = RunService:IsStudio() and "STUDIO_JOB_ID" or game.JobId -- Handle Studio case
    local availableServers = {}
    for _, server in ipairs(serverData) do
        -- Basic validation of server object structure
        if type(server) == "table" and server.id and server.playing and server.maxPlayers and server.ping then
            -- Keep client-side check for currentJobId always.
            -- Keep client-side check for fullness as a fallback,
            -- even if ExcludeFullGames=true was sent to API.
            if server.id ~= currentJobId and server.playing < server.maxPlayers then
                table.insert(availableServers, {
                    id = server.id,
                    ping = server.ping,
                    playing = server.playing,
                    maxPlayers = server.maxPlayers
                })
            end
        else
            warn("ServerHopAPI._filterServers: Skipping invalid server entry:", server)
        end
    end
    return availableServers
end

-- Private: Sorts a list of servers.
local function _sortServers(serverList, compareFunc)
    -- Default sort: lowest ping first
    local defaultCompare = function(a, b)
        return a.ping < b.ping
    end
    table.sort(serverList, compareFunc or defaultCompare)
    return serverList -- Return the sorted list (modifies in place, but return for chaining)
end

--- Fetches the raw server data list from the API for the current place.
-- @return table? The raw array of server data objects, or nil if an error occurred.
-- @return string? An error message if the fetch or decode failed.
function ServerHopAPI.GetServerData()
    local placeId = game.PlaceId
    local data, err = _fetchAndDecodeServerData(placeId)
    if err then
        warn("ServerHopAPI.GetServerData: Error - ", err)
        return nil, err
    end
    return data -- Returns the raw data array
end

--- Fetches and filters the server list for the current place, returning servers that can be joined.
-- @return table? A list of available server objects {id, ping, playing, maxPlayers}, or nil if an error occurred.
-- @return string? An error message if fetching failed or no servers are available.
function ServerHopAPI.GetAvailableServers()
    local placeId = game.PlaceId
    local rawData, err = _fetchAndDecodeServerData(placeId)
    if err then
        warn("ServerHopAPI.GetAvailableServers: Error fetching data - ", err)
        return nil, err
    end

    local availableServers = _filterServers(rawData)

    if #availableServers == 0 then
        -- It's not necessarily an error, just no suitable servers found
        -- Return empty table and no error message in this specific case
        return {}, nil
    end

    return availableServers, nil
end

--- Fetches, filters, and sorts the server list for the current place.
-- @param sortFunc function? Optional comparison function for sorting. Defaults to sorting by lowest ping.
-- @return table? A sorted list of available server objects, or nil if an error occurred.
-- @return string? An error message if fetching failed. Returns nil error if list is empty but fetch succeeded.
function ServerHopAPI.GetSortedServerList(sortFunc)
    local availableServers, err = ServerHopAPI.GetAvailableServers()
    if err then
        -- Error already logged by GetAvailableServers if needed
        return nil, err
    end

    -- Even if availableServers is empty, sorting an empty table is safe.
    return _sortServers(availableServers, sortFunc), nil
end

--- Fetches available servers and returns the one with the lowest ping.
-- @return table? The server object with the lowest ping, or nil if none are available or an error occurred.
-- @return string? An error message if fetching failed.
function ServerHopAPI.GetLowestPingServer()
    local sortedServers, err = ServerHopAPI.GetSortedServerList(function(a, b)
        return a.ping < b.ping
    end)

    if err then
        return nil, err
    end

    if #sortedServers == 0 then
        return nil, nil -- No error, just no servers
    end

    return sortedServers[1], nil
end

--- Attempts to hop to a suitable server.
-- It prioritizes the 5 lowest ping servers and tries them in a random order.
-- @param player Player? The player to teleport. Defaults to LocalPlayer.
function ServerHopAPI.ServerHop(player)
    player = player or Players.LocalPlayer -- Use provided player or default to LocalPlayer
    if not player then
        warn("ServerHopAPI.hopServer: Player object not found.")
        return false, "Player object not found."
    end

    local availableServers, err = ServerHopAPI.GetAvailableServers()

    if err then
        warn("ServerHopAPI.hopServer: Failed to get available servers - ", err)
        return false, "Failed to get available servers: " .. err
    end

    if #availableServers == 0 then
        warn("ServerHopAPI.hopServer: No suitable servers found to hop to.")
        return false, "No suitable servers found."
    end

    -- Sort by lowest ping first to select the top candidates
    _sortServers(availableServers, function(a, b)
        return a.ping < b.ping
    end)

    -- Keep only the top 5 (or fewer if less than 5 available)
    local targetServers = {}
    for i = 1, math.min(5, #availableServers) do
        table.insert(targetServers, availableServers[i])
    end

    -- Shuffle the target servers to avoid everyone hitting the absolute lowest ping server first
    _shuffleTable(targetServers)

    local teleportSuccess = false
    local lastError = "No servers were attempted."

    for i, serverObj in ipairs(targetServers) do
        local tpSuccess, tpError = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId,
            serverObj.id, player)

        if tpSuccess then
            teleportSuccess = true
            break -- Exit loop on successful teleport initiation
        else
            lastError = tostring(tpError)
            warn("ServerHopAPI.hopServer: Failed to teleport to server " .. serverObj.id .. ": " .. lastError)
            -- Don't retry the same server immediately, move to the next one
            if i < #targetServers then
                task.wait(0.5) -- Short delay before trying the next server in the shuffled list
            end
        end
    end

    if not teleportSuccess then
        warn("ServerHopAPI.hopServer: Failed to teleport after trying " .. #targetServers ..
                 " potential servers. Last error: " .. lastError)
        return false, "Failed to teleport after trying available servers. Last error: " .. lastError
    end

    return true, nil -- Teleport initiated successfully
end

return ServerHopAPI
