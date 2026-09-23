--- ============================================================================
--- Headless 服务端：只承载内购发货 + 余额查询
--- ============================================================================

local Shared = require("network.Shared")

---@diagnostic disable-next-line: undefined-global
local cjson = cjson
---@diagnostic disable-next-line: undefined-global
local Shop = Shop
---@diagnostic disable-next-line: undefined-global
local serverCloud = serverCloud
---@diagnostic disable-next-line: undefined-global
local network = network

local Server = {}

local function sendBalance(conn, userId)
    if not conn or not conn.IsConnected or not conn:IsConnected() then return end
    if not serverCloud or not serverCloud.money then
        print("[Server] serverCloud.money 不可用，无法查余额")
        return
    end
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            if not conn:IsConnected() then return end
            local gems = 0
            if type(moneys) == "table" then
                gems = tonumber(moneys[Shared.GEMS_KEY] or moneys.gems or 0) or 0
            end
            local vm = VariantMap()
            vm["gems"] = Variant(gems)
            conn:SendRemoteEvent(Shared.EVENTS.BALANCE_SYNC, true, vm)
            print("[Server] 推送余额 userId=" .. tostring(userId) .. " gems=" .. tostring(gems))
        end,
        error = function(code, reason)
            print("[Server] 查余额失败 userId=" .. tostring(userId)
                .. " err=" .. tostring(reason) .. " code=" .. tostring(code))
        end,
    })
end

---@param eventType string
---@param eventData VariantMap
function HandleIAPClientReady(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    if not conn then return end
    local userId = conn:GetIdentity()
    print("[Server] 客户端就绪 userId=" .. tostring(userId))
    sendBalance(conn, userId)
end

---@param eventType string
---@param eventData VariantMap
function HandleIAPRequestBalance(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    if not conn then return end
    local userId = conn:GetIdentity()
    sendBalance(conn, userId)
end

function Server.Start()
    ---@diagnostic disable-next-line: undefined-global
    local maxPlayers = SERVER_MAX_PLAYERS
    ---@diagnostic disable-next-line: undefined-global
    local registered = SERVER_REGISTERED_PLAYERS
    print("[Server] headless IAP 服务启动 maxPlayers="
        .. tostring(maxPlayers) .. " registered="
        .. tostring(registered))

    network:RegisterRemoteEvent(Shared.EVENTS.CLIENT_READY)
    network:RegisterRemoteEvent(Shared.EVENTS.REQUEST_BALANCE)
    network:RegisterRemoteEvent(Shared.EVENTS.BALANCE_SYNC)
    network:RegisterRemoteEvent(Shared.EVENTS.BALANCE_DIRTY)

    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleIAPClientReady")
    SubscribeToEvent(Shared.EVENTS.REQUEST_BALANCE, "HandleIAPRequestBalance")

    if not Shop or not Shop.onDeliver then
        print("[Server] Shop.onDeliver 不可用，跳过发货注册")
        return
    end

    Shop.onDeliver(function(ctx)
        local productJson = ctx.productJson or "{}"
        local product = {}
        if cjson then
            local okDecode, decoded = pcall(cjson.decode, productJson)
            if okDecode and type(decoded) == "table" then
                product = decoded
            end
        end
        local delivery = product.delivery or {}
        local userId = ctx.userId
        local orderId = ctx.orderId
        local conn = ctx.conn

        print("[Server] onDeliver product=" .. tostring(ctx.productId)
            .. " orderId=" .. tostring(orderId)
            .. " userId=" .. tostring(userId)
            .. " items=" .. tostring(#delivery))

        if not serverCloud then
            print("[Server] 发货失败: serverCloud 不可用")
            return
        end

        local batch = serverCloud:BatchCommit("IAP 发货: " .. tostring(ctx.productId))
        for _, item in ipairs(delivery) do
            local key = item.key
            local amount = tonumber(item.amount) or 0
            if type(key) == "string" and key ~= "" and amount > 0 then
                batch:MoneyAdd(userId, key, amount)
            end
        end

        batch:Commit({ orderId = orderId }, {
            ok = function()
                print("[Server] 发货成功: orderId=" .. tostring(orderId)
                    .. " userId=" .. tostring(userId))
                if conn and conn.IsConnected and conn:IsConnected() then
                    sendBalance(conn, userId)
                    local vm = VariantMap()
                    vm["gems"] = Variant(-1)
                    conn:SendRemoteEvent(Shared.EVENTS.BALANCE_DIRTY, true, vm)
                end
            end,
            err = function(code, msg)
                print("[Server] 发货失败: orderId=" .. tostring(orderId)
                    .. " err=" .. tostring(msg) .. " code=" .. tostring(code))
            end,
        })
    end)
end

function Server.Stop()
    print("[Server] headless IAP 服务停止")
end

return Server
