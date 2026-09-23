--- ============================================================================
--- 充值商城 - 纯 NanoVG 弹层
--- ============================================================================

local GameMode = require("GameMode")
local I18n = require("utils.I18n")

local RechargeShop = {}

RechargeShop.visible = false
RechargeShop.status = ""
RechargeShop.products = {}
RechargeShop.notice = ""

local backBtn = { x = 0, y = 0, w = 0, h = 0 }
local productBtns = {}

local function getShopLib()
    if GameMode.IsOffline() then return nil, "offline" end
    if not GameMode.IsOnlineSession() then return nil, "offline" end
    local ok, Shop = pcall(require, "urhox-libs/Shop")
    if not ok or type(Shop) ~= "table" or not Shop.getProducts then
        return nil, "shop_lib"
    end
    return Shop, nil
end

local function getClientNet()
    if GameMode.IsOffline() then return nil end
    if not GameMode.IsOnlineSession() then return nil end
    local ok, Client = pcall(require, "network.Client")
    if ok then return Client end
    return nil
end

local function refreshProducts()
    RechargeShop.products = {}
    RechargeShop.notice = ""
    local Shop, reason = getShopLib()
    if not Shop then
        if reason == "offline" then
            RechargeShop.notice = I18n.t("iap_need_online")
        else
            RechargeShop.notice = I18n.t("iap_unavailable")
        end
        return
    end

    local platform = type(GetPlatform) == "function" and GetPlatform() or ""
    ---@diagnostic disable-next-line: undefined-global
    local hasEmbed = (type(HasAppArg) == "function" and HasAppArg("embed")) or false
    if platform ~= "Android" and platform ~= "iOS" then
        RechargeShop.notice = I18n.t("iap_need_taptap")
    elseif not hasEmbed then
        RechargeShop.notice = I18n.t("iap_need_taptap")
    end

    local products = Shop.getProducts()
    if not products or #products == 0 then
        RechargeShop.notice = I18n.t("iap_no_products")
        return
    end
    RechargeShop.products = products
end

function RechargeShop.Open()
    RechargeShop.visible = true
    refreshProducts()
    local Client = getClientNet()
    if Client and Client.RequestBalance then
        Client.RequestBalance()
    end
    print("[RechargeShop] 打开商品数=" .. tostring(#RechargeShop.products)
        .. " notice=" .. tostring(RechargeShop.notice))
end

function RechargeShop.Close()
    RechargeShop.visible = false
end

local function buyProduct(skuId)
    local Shop = getShopLib()
    if not Shop or not Shop.purchase then
        RechargeShop.status = I18n.t("iap_unavailable")
        return
    end
    RechargeShop.status = I18n.t("iap_purchasing")
    Shop.purchase(skuId, function(result)
        if result and result.ok then
            RechargeShop.status = I18n.t("iap_pay_launched")
        else
            local msg = result and (result.message or result.error) or "unknown"
            RechargeShop.status = I18n.t("iap_buy_fail") .. " " .. tostring(msg)
        end
    end)
end

---@param vg any
---@param fontId number
---@param viewW number
---@param viewH number
function RechargeShop.Render(vg, fontId, viewW, viewH)
    if not RechargeShop.visible then return end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, viewW, viewH)
    nvgFillColor(vg, nvgRGBA(6, 4, 16, 220))
    nvgFill(vg)

    local panelW, panelH = viewW - 48, viewH - 160
    local px, py = 24, 80
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 18)
    nvgFillColor(vg, nvgRGBA(18, 14, 40, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 210, 80, 160))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFaceId(vg, fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(255, 230, 100, 255))
    nvgText(vg, viewW / 2, py + 36, I18n.t("iap_title"))

    local Client = getClientNet()
    local gems = (Client and Client.gems) or 0
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 255))
    nvgText(vg, viewW / 2, py + 72, I18n.t("iap_balance", gems))

    if Client and Client.toast then
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(120, 255, 180, 255))
        nvgText(vg, viewW / 2, py + 96, Client.toast)
    end

    backBtn = { x = px + 16, y = py + 16, w = 110, h = 40 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backBtn.x, backBtn.y, backBtn.w, backBtn.h, 10)
    nvgFillColor(vg, nvgRGBA(40, 30, 70, 230))
    nvgFill(vg)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(220, 220, 255, 255))
    nvgText(vg, backBtn.x + backBtn.w / 2, backBtn.y + backBtn.h / 2, I18n.t("shop_back"))

    productBtns = {}
    local startY = py + 120
    if RechargeShop.notice ~= "" and #RechargeShop.products == 0 then
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 180, 120, 255))
        nvgText(vg, viewW / 2, startY + 40, RechargeShop.notice)
    else
        local cardH = 92
        for i, p in ipairs(RechargeShop.products) do
            local cy = startY + (i - 1) * (cardH + 12)
            local card = { x = px + 20, y = cy, w = panelW - 40, h = cardH, sku = p.sku_id }
            productBtns[#productBtns + 1] = card
            nvgBeginPath(vg)
            nvgRoundedRect(vg, card.x, card.y, card.w, card.h, 14)
            nvgFillColor(vg, nvgRGBA(30, 22, 60, 230))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 200, 255, 140))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            local gift = 0
            if p.delivery then
                for _, d in ipairs(p.delivery) do
                    if d.key == "gems" then gift = gift + (tonumber(d.amount) or 0) end
                end
            end
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, card.x + 20, card.y + 32, p.name or p.sku_id)
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(180, 220, 255, 220))
            nvgText(vg, card.x + 20, card.y + 62, I18n.t("iap_gift", gift))

            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 24)
            nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
            nvgText(vg, card.x + card.w - 24, card.y + card.h / 2, "¥" .. tostring(p.price or 0))
        end
        if RechargeShop.notice ~= "" then
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 180, 120, 220))
            nvgText(vg, viewW / 2, py + panelH - 56, RechargeShop.notice)
        end
    end

    if RechargeShop.status ~= "" then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(160, 255, 200, 255))
        nvgText(vg, viewW / 2, py + panelH - 28, RechargeShop.status)
    end
end

---@param dx number
---@param dy number
---@return boolean
function RechargeShop.HandleTouch(dx, dy)
    if not RechargeShop.visible then return false end
    if dx >= backBtn.x and dx <= backBtn.x + backBtn.w
        and dy >= backBtn.y and dy <= backBtn.y + backBtn.h then
        RechargeShop.Close()
        return true
    end
    for _, card in ipairs(productBtns) do
        if dx >= card.x and dx <= card.x + card.w and dy >= card.y and dy <= card.y + card.h then
            buyProduct(card.sku)
            return true
        end
    end
    return true
end

return RechargeShop
