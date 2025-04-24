# Solvent Server Hop API Wrapper (Roblox Executors)

A Luau module designed for use within Roblox script executors to interact with the Solvent server list API (`solvent.xvh.lol`), facilitating server discovery and hopping.

**Disclaimer:** This script is intended for use in Roblox script execution environments. Use responsibly and at your own risk.

## Features

- Fetch raw server list data for the current place.
- Filter server lists to find joinable servers (non-full, not the current server).
- Sort server lists based on custom criteria (default: lowest ping).
- Easily find the server with the lowest ping.
- Initiate server hops to suitable servers with configurable retry logic and randomization.
- Configurable API query parameters (`sortOrder`, `limit`, `excludeFullGames`).
- Configurable HTTP request retry behavior (`MaxRetries`, `RetryDelay`).
- Configurable API endpoint (`ApiBaseUrl`).

## Installation / Loading

1. Copy the entire content of the `server_api.luau` script.
2. Paste and execute the script content within your chosen Roblox script executor.
3. Alternatively, use your executor's `loadstring` function:

   ```lua
   local ServerHopAPI = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/xvht/Lua_ServerAPI/refs/heads/main/server_api.luau"))()
   ```

   The script returns the `ServerHopAPI` table when executed.

## Configuration

You can configure the module's behavior using the `Configure` function _before_ calling other API functions.

```lua
ServerHopAPI.Configure({
    MaxRetries = 5,       -- Default: 3. Max HTTP request retries.
    RetryDelay = 10,      -- Default: 15. Seconds to wait after a 429 error.
    ApiBaseUrl = "https://your.custom.api/v1/servers/", -- Default: "https://solvent.xvh.lol/v1/servers/"
    SortOrder = "Asc",    -- Default: nil (API uses 'Desc'). 'Asc' or 'Desc'.
    Limit = 50,           -- Default: nil (API uses 10). 10, 25, 50, or 100.
    ExcludeFullGames = false -- Default: nil (API uses true). true or false.
})
```

- **`MaxRetries`** (number, >= 0): How many times to retry an HTTP request if it fails (including 429 errors). Default: `3`.
- **`RetryDelay`** (number, > 0): How many seconds to wait before retrying after receiving a 429 (Too Many Requests) error. Default: `15`.
- **`ApiBaseUrl`** (string?): The base URL for the server list API. Must end with `/`. Default: `"https://solvent.xvh.lol/v1/servers/"`.
- **`SortOrder`** (string?, `'Asc'` or `'Desc'`): The order in which the API should return servers. If `nil` (default), the parameter is not sent, and the API defaults to `'Desc'`.
- **`Limit`** (number?, `10`, `25`, `50`, `100`): The maximum number of servers the API should return. If `nil` (default), the parameter is not sent, and the API defaults to `10`.
- **`ExcludeFullGames`** (boolean?): Whether the API should exclude full servers from the results. If `nil` (default), the parameter is not sent, and the API defaults to `true`. Set explicitly to `true` or `false` to override the API default.

## API Reference

### `ServerHopAPI.Configure(options: table?)`

Configures the module settings. See the [Configuration](#configuration) section for details on the `options` table.

### `ServerHopAPI.GetServerData()`

Fetches the raw server data list from the API for the current place.

- **Returns:**
  - `table?`: The raw array of server data objects from the API, or `nil` on error.
  - `string?`: An error message if the fetch or decode failed.

### `ServerHopAPI.GetAvailableServers()`

Fetches and filters the server list, returning servers that are not full and not the current server instance.

- **Returns:**
  - `table?`: A list of available server objects `{id: string, ping: number, playing: number, maxPlayers: number}`, or `nil` if a fetch error occurred. Returns an empty table `{}` if the fetch succeeded but no suitable servers were found.
  - `string?`: An error message if fetching failed.

### `ServerHopAPI.GetSortedServerList(sortFunc: function?)`

Fetches, filters, and sorts the list of available servers.

- **Parameters:**
  - `sortFunc` (optional `function`): A comparison function `(a, b)` that returns `true` if server `a` should come before server `b`. Defaults to sorting by lowest ping (`a.ping < b.ping`).
- **Returns:**
  - `table?`: A sorted list of available server objects, or `nil` if a fetch error occurred. Returns an empty table `{}` if the fetch succeeded but no suitable servers were found.
  - `string?`: An error message if fetching failed.

### `ServerHopAPI.GetLowestPingServer()`

Fetches available servers and returns the one with the lowest ping.

- **Returns:**
  - `table?`: The server object `{id, ping, playing, maxPlayers}` with the lowest ping, or `nil` if none are available or an error occurred.
  - `string?`: An error message if fetching failed.

### `ServerHopAPI.ServerHop(player: Player?)`

Attempts to teleport a player to a suitable server. It prioritizes the 5 lowest ping servers (fetched using default API settings unless configured otherwise) and tries teleporting to one of them in a random order.

- **Parameters:**
  - `player` (optional `Player`): The player to teleport. Defaults to `game.Players.LocalPlayer`.
- **Returns:**
  - `boolean`: `true` if the teleport was successfully initiated, `false` otherwise.
  - `string?`: An error message if fetching servers failed, no suitable servers were found, or the teleport attempt failed.

## Usage Examples

**1. Find and warn about the lowest ping server:**

```lua
local lowestPingServer, err = ServerHopAPI.GetLowestPingServer()

if err then
    warn("Error getting lowest ping server:", err)
elseif lowestPingServer then
    warn("Lowest ping server found - ID:", lowestPingServer.id, "Ping:", lowestPingServer.ping, "Players:", lowestPingServer.playing .. "/" .. lowestPingServer.maxPlayers)
else
    warn("No available servers found.")
end
```

**2. Hop the Local Player to a low-ping server:**

```lua
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Optional: Configure first
ServerHopAPI.Configure({ Limit = 100, ExcludeFullGames = true })

warn("Attempting server hop...")
local success, message = ServerHopAPI.ServerHop(player)

if success then
    warn("Server hop initiated!") -- Note: Teleport might still fail later
else
    warn("Server hop failed:", message)
end
```

\*\*3. Get servers sorted by player count (highest first) and
