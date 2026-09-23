--- ============================================================================
--- 联机共享协议：远程事件名 + 云变量 key
--- ============================================================================

local Shared = {}

Shared.EVENTS = {
    CLIENT_READY    = "IAPClientReady",
    REQUEST_BALANCE = "IAPRequestBalance",
    BALANCE_SYNC    = "IAPBalanceSync",
    BALANCE_DIRTY   = "IAPBalanceDirty",
}

--- 钻石的云变量 / 货币 key（与发货 delivery.key 对齐）
Shared.GEMS_KEY = "gems"

return Shared
