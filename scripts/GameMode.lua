--- ============================================================================
--- 游戏运行模式标志
--- IsNetworkMode() 在离线态仍可能为 true（大厅启动后固定），
--- 因此离线判定必须用本模块的显式标志。
--- ============================================================================

local GameMode = {}

GameMode.offline = false

---@param offline boolean
function GameMode.SetOffline(offline)
    GameMode.offline = offline == true
    print("[GameMode] offline=" .. tostring(GameMode.offline)
        .. " networkMode=" .. tostring(IsNetworkMode and IsNetworkMode() or false))
end

---@return boolean
function GameMode.IsOffline()
    return GameMode.offline == true
end

--- 是否真正连上权威服务器（可走 IAP / 远程事件）
---@return boolean
function GameMode.IsOnlineSession()
    if GameMode.offline then return false end
    if not (IsNetworkMode and IsNetworkMode()) then return false end
    if IsServerMode and IsServerMode() then return true end
    local conn = network and network.GetServerConnection and network:GetServerConnection()
    return conn ~= nil
end

return GameMode
