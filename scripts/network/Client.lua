--- ============================================================================
--- 客户端网络层：就绪上报、余额请求、远程事件订阅
--- ============================================================================

local Shared = require("network.Shared")
local GameMode = require("GameMode")

local Client = {}

Client.gems = 0
Client.ready = false
Client.toast = nil
Client.toastTimer = 0

local started = false

local function getServerConn()
    if not network or not network.GetServerConnection then return nil end
    return network:GetServerConnection()
end

function Client.RequestBalance()
    if GameMode.IsOffline() then return end
    local conn = getServerConn()
    if not conn then
        print("[Client] RequestBalance 跳过: 未连上服务器")
        return
    end
    conn:SendRemoteEvent(Shared.EVENTS.REQUEST_BALANCE, true)
    print("[Client] 已请求余额")
end

function Client.MarkReady()
    if GameMode.IsOffline() then return end
    local conn = getServerConn()
    if not conn then return end
    conn:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true)
    Client.ready = true
    print("[Client] 已上报就绪")
end

---@param eventType string
---@param eventData VariantMap
function HandleIAPBalanceSync(eventType, eventData)
    local gems = 0
    if eventData["gems"] then
        gems = eventData["gems"]:GetInt()
    end
    Client.gems = gems
    Client.toast = "余额已更新"
    Client.toastTimer = 2.2
    print("[Client] 余额同步 gems=" .. tostring(gems))
end

---@param eventType string
---@param eventData VariantMap
function HandleIAPBalanceDirty(eventType, eventData)
    print("[Client] 收到 BALANCE_DIRTY，重新拉余额")
    Client.RequestBalance()
end

---@param eventType string
---@param eventData VariantMap
function HandleIAPServerDisconnected(eventType, eventData)
    print("[Client] 与服务器断开")
    Client.ready = false
end

function Client.Start()
    if started then return end
    if GameMode.IsOffline() then
        print("[Client] 离线模式，跳过网络层")
        return
    end
    if not (IsNetworkMode and IsNetworkMode()) then
        print("[Client] 非联网模式，跳过网络层")
        return
    end

    network:RegisterRemoteEvent(Shared.EVENTS.CLIENT_READY)
    network:RegisterRemoteEvent(Shared.EVENTS.REQUEST_BALANCE)
    network:RegisterRemoteEvent(Shared.EVENTS.BALANCE_SYNC)
    network:RegisterRemoteEvent(Shared.EVENTS.BALANCE_DIRTY)

    SubscribeToEvent(Shared.EVENTS.BALANCE_SYNC, "HandleIAPBalanceSync")
    SubscribeToEvent(Shared.EVENTS.BALANCE_DIRTY, "HandleIAPBalanceDirty")
    SubscribeToEvent("ServerDisconnected", "HandleIAPServerDisconnected")

    -- 轻量 Scene：IAP 不需要场景复制，但部分运行时路径依赖 scene 绑定
    if not Client._scene then
        local scene = Scene()
        scene:CreateComponent("Octree", LOCAL)
        Client._scene = scene
        local conn = getServerConn()
        if conn then
            conn.scene = scene
        end
    end

    Client.MarkReady()
    Client.RequestBalance()
    started = true
    print("[Client] 网络层已启动")
end

function Client.Stop()
    started = false
    Client.ready = false
    print("[Client] 网络层已停止")
end

function Client.Update(dt)
    if Client.toastTimer > 0 then
        Client.toastTimer = Client.toastTimer - dt
        if Client.toastTimer <= 0 then
            Client.toast = nil
        end
    end
end

return Client
