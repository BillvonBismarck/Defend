-- R08–R10/B04–B05/R02：模拟层重验后勤权限，服务费不返，重复请求返回原结果。
local E = {}
local Expansion = require("defense.Expansion")
local Reactions = require("defense.Reactions")
local TowerModules = require("defense.TowerModules")

---@param run table
local function findSlot(run, slotId)
    for _, slot in ipairs(run.config.build_slots) do if slot.id == slotId then return slot end end
end

---@param run table
local function findTower(run, slotId)
    -- 摧毁的设施不遮蔽同槽存活设施，也不占全局存活名额。
    local dead, deadIndex
    for index, tower in ipairs(run.towers) do
        if tower.slot_id == slotId then
            if tower.hp > 0 then return tower, index end
            dead, deadIndex = tower, index
        end
    end
    return dead, deadIndex
end

---@param run table
local function findRoom(run, roomId)
    for _, room in ipairs(run.rooms) do if room.id == roomId then return room end end
end

-- 纯读取迁移：旧 total_spend 全为基造/升级支出，保持其精确返款结果。
---@param run table
---@param tower table
local function spending(run, tower)
    local definition = run.config.towers[tower.type] --[[@as table?]]
    local total = tower.total_spend or ((definition and definition.cost or 0)
        + (definition and definition.upgrade or 0) * (tower.upgrade_count or 0))
    local build = tower.build_spend
    local upgrade = tower.upgrade_spend
    if build == nil and upgrade == nil then
        build = math.min(total, definition and definition.cost or total)
        upgrade = total - build
    elseif build == nil then build = math.max(0, total - upgrade)
    elseif upgrade == nil then upgrade = math.max(0, total - build) end
    return build, upgrade, tower.service_spend or 0
end

---@param run table
---@param tower table
local function normalizeSpending(run, tower)
    tower.build_spend, tower.upgrade_spend, tower.service_spend = spending(run, tower)
    tower.total_spend = tower.build_spend + tower.upgrade_spend
    tower.module_revision = tower.module_revision or 0
    local slot = findSlot(run, tower.slot_id)
    if slot then
        tower.owner_room_id = slot.owner_room_id
        tower.activation_region_id = slot.activation_region_id
    end
end

---@param run table
---@param tower table|nil
local function snapshot(run, tower)
    if not tower then return nil end
    local build, upgrade, service = spending(run, tower)
    return { id = tower.entity_id or tower.id, tower_id = tower.entity_id or tower.id,
        slot_id = tower.slot_id, type = tower.type, x = tower.x, y = tower.y,
        owner_room_id = tower.owner_room_id, activation_region_id = tower.activation_region_id,
        hp = tower.hp, max_hp = tower.max_hp, attack_cd = tower.attack_cd,
        upgrade_count = tower.upgrade_count, module_id = tower.module_id, module_revision = tower.module_revision or 0,
        build_spend = build, upgrade_spend = upgrade, service_spend = service, total_spend = build + upgrade,
        branch_id = tower.branch_id, sand_spend = tower.sand_spend or 0, attributes = TowerModules.Attributes(run, tower) }
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

---@param run table
function E.Check(run, action, slotId, towerType)
    if run.ended then return false, "本局已结束" end
    if run.state ~= "PREPARATION" then return false, "仅战备期可操作" end
    if not run.pause_reasons.logistics then return false, "请先打开后勤面板" end
    if action == "repair" then
        if run.repair_uses >= 3 then return false, "修复次数已用尽（3/3）" end
        if run.core.hp >= run.core.max_hp then return false, "核心耐久已满" end
        if run.currency < 40 then return false, "需要40资金" end
        return true, "修复200耐久", 40
    elseif action == "heal" then
        if run.player.hp >= run.player.max_hp then return false, "角色生命已满" end
        if run.currency < 20 then return false, "需要20资金" end
        return true, "治疗25生命", 20
    end
    local slot = findSlot(run, slotId)
    if not slot then return false, "无效建造槽" end
    local tower = findTower(run, slotId)
    if action == "build" then
        if tower and tower.hp > 0 then return false, "该槽位已占用" end
        if type(slot.x) ~= "number" or type(slot.y) ~= "number" or slot.x ~= slot.x or slot.y ~= slot.y
            or math.abs(slot.x) == math.huge or math.abs(slot.y) == math.huge then return false, "无效槽位坐标" end
        if slot.owner_room_id then
            if not TowerModules.Enabled(run) then return false, "本场景未启用外围部署" end
            local room = findRoom(run, slot.owner_room_id)
            if not room then return false, "无效槽位所属房间" end
            if room.state ~= "cleared" and room.state ~= "claimed" then return false, "房间未清空，不能部署" end
            if not slot.activation_region_id then return false, "外围槽位缺少激活区域" end
        end
        if TowerModules.Enabled(run) then
            local alive = 0
            for _, facility in ipairs(run.towers) do if facility.hp > 0 then alive = alive + 1 end end
            if alive >= (run.config.max_alive_towers or 6) then return false, "存活设施已达全局上限" end
        end
        local d = run.config.towers[towerType] --[[@as table?]]
        if not d then return false, "无效设施类型" end
        if Expansion.Enabled(run) and run.exploration_currency < (d.sand_cost or 0) then return false, "星砂不足，需要" .. tostring(d.sand_cost) end
        if run.currency < d.cost then return false, "资金不足，需要" .. d.cost end
        return true, "建造" .. d.name, d.cost
    elseif action == "upgrade" then
        if not tower or tower.hp <= 0 then return false, "该槽位没有可升级设施" end
        if tower.upgrade_count >= 2 then return false, "设施已达升级上限" end
        local price = run.config.towers[tower.type].upgrade
        if run.currency < price then return false, "资金不足，需要" .. price end
        return true, "升级设施", price
    elseif action == "branch" then
        if not Expansion.Enabled(run) then return false, "本场景未启用升级分支" end
        if not tower or tower.hp <= 0 or tower.upgrade_count < 1 then return false, "先升级一次设施" end
        if tower.branch_id then return false, "分支不可逆，已选择" end
        if not run.config.branches[towerType] then return false, "无效分支" end
        if run.exploration_currency < 20 then return false, "需要20星砂" end
        return true, "不可逆选择分支 / 20星砂", 0
    elseif action == "repair_tower" then
        if not tower or tower.hp <= 0 or tower.hp >= tower.max_hp then return false, "没有可修复的存活设施" end
        if run.currency < 20 then return false, "需要20资金" end
        return true, "修复80设施耐久", 20
    elseif action == "module" then
        if not TowerModules.Enabled(run) then return false, "本场景未启用模块" end
        if not tower or tower.hp <= 0 then return false, "该槽位没有可安装模块设施" end
        local module = TowerModules.Find(run, towerType)
        if not module then return false, "无效模块" end
        if not (run.module_inventory or {})[towerType] then return false, "该模块尚未解锁" end
        if module.tower_type ~= tower.type then return false, "模块与设施类型不匹配" end
        if tower.module_id == towerType then return false, "该模块已安装" end
        local price = tower.module_id and TowerModules.ChangeCost or 0
        if run.currency < price then return false, "资金不足，需要" .. price end
        return true, price == 0 and "首次安装模块免费" or "更换模块", price
    elseif action == "demolish" then
        if not tower then return false, "该槽位为空" end
        return true, tower.hp < tower.max_hp and "损坏设施拆除不返款" or "返还基造与升级支出50%（服务费不返）", 0
    end
    return false, "未知交易"
end

---@param run table
function E.Transact(run, action, slotId, towerType, requestId)
    if type(requestId) ~= "string" or requestId == "" then return { ok = false, reason = "缺少请求ID" } end
    -- 与 module_choice:/room_claim: 使用不同命名空间；原始 request_id 保持事件/API兼容。
    local key = "economy:" .. requestId
    local existing = run.transactions[key]
    if existing then return existing end
    local ok, reason, price = E.Check(run, action, slotId, towerType)
    local tower, index = findTower(run, slotId)
    local result = { ok = ok, reason = reason, action = action, request_id = requestId, id = requestId,
        price = price or 0, fee = price or 0, slot_id = slotId, tower_type = towerType,
        module_id = action == "module" and towerType or nil, currency_before = run.currency,
        sand_before = run.exploration_currency, sand_spend = 0, actual_repair = 0, actual_heal = 0, refund = 0, run_id = run.run_id, before = snapshot(run, tower) }
    if tower then result.tower_id = tower.entity_id or tower.id end
    if ok then
        run.currency = run.currency - (price or 0)
        if action == "repair" then
            local previous = run.core.hp
            run.core.hp = math.min(run.core.max_hp, run.core.hp + 200)
            result.actual_repair = run.core.hp - previous
            result.core_hp, result.before_hp = run.core.hp, previous
            run.repair_uses = run.repair_uses + 1
            result.before, result.after = { hp = previous }, { hp = run.core.hp }
        elseif action == "heal" then
            local previous = run.player.hp
            run.player.hp = math.min(run.player.max_hp, run.player.hp + 25)
            result.actual_heal = run.player.hp - previous
            result.player_hp, result.before_hp = run.player.hp, previous
            result.before, result.after = { hp = previous }, { hp = run.player.hp }
        elseif action == "build" then
            if index then table.remove(run.towers, index) end
            local slot = findSlot(run, slotId)
            local d = run.config.towers[towerType]
            if Expansion.Enabled(run) then
                result.sand_spend = d.sand_cost or 0
                run.exploration_currency = run.exploration_currency - result.sand_spend
            end
            local id = run.next_entity_id
            run.next_entity_id = id + 1
            local built = { id = id, entity_id = id, slot_id = slotId, type = towerType, x = slot.x, y = slot.y,
                owner_room_id = slot.owner_room_id, activation_region_id = slot.activation_region_id,
                sand_spend = result.sand_spend, module_revision = 0, build_spend = price, upgrade_spend = 0, service_spend = 0,
                hp = d.hp, max_hp = d.hp, radius = 0.65, upgrade_count = 0, total_spend = price, attack_cd = 0,
                team = "player", anchored = true, movable = false, damageable = true, weight = 100, slowable = false }
            Reactions.Sync(run, built)
            run.towers[#run.towers + 1] = built
            result.tower_id, result.after = built.entity_id, snapshot(run, built)
        elseif action == "upgrade" then
            normalizeSpending(run, tower)
            tower.upgrade_count = tower.upgrade_count + 1
            tower.upgrade_spend = tower.upgrade_spend + price
            tower.total_spend = tower.build_spend + tower.upgrade_spend
            tower.max_hp = tower.max_hp + 40
            tower.hp = math.min(tower.max_hp, tower.hp + 40)
            result.upgrade_count, result.after = tower.upgrade_count, snapshot(run, tower)
        elseif action == "branch" then
            tower.branch_id = towerType
            result.sand_spend = 20
            run.exploration_currency = run.exploration_currency - 20
            tower.sand_spend = (tower.sand_spend or 0) + 20
            result.after = snapshot(run, tower)
        elseif action == "repair_tower" then
            local before = tower.hp
            tower.hp = math.min(tower.max_hp, tower.hp + 80)
            result.actual_repair = tower.hp - before
            result.after = snapshot(run, tower)
        elseif action == "module" then
            normalizeSpending(run, tower)
            tower.module_id = towerType
            tower.module_revision = tower.module_revision + 1
            tower.service_spend = tower.service_spend + price
            result.module_revision, result.service_spend = tower.module_revision, tower.service_spend
            result.after = snapshot(run, tower)
            -- 横向分支不改 hp、attack_cd、upgrade_count；服务支出永不进入 total_spend。
        elseif action == "demolish" then
            local build, upgrade = spending(run, tower)
            result.refund = tower.hp < tower.max_hp and 0 or math.floor((build + upgrade) * 0.5)
            run.currency = run.currency + result.refund
            table.remove(run.towers, index)
        end
    else result.after = snapshot(run, tower) end
    result.sand_after = run.exploration_currency
    result.currency_after, result.repair_uses = run.currency, run.repair_uses
    if ok then
        if action == "repair" then result.reason = "修复核心" .. tostring(result.actual_repair) .. "耐久（实际）"
        elseif action == "heal" then result.reason = "治疗角色" .. tostring(result.actual_heal) .. "生命（实际）"
        elseif action == "demolish" then result.reason = "拆除实际返款" .. tostring(result.refund) end
    end
    run.transactions[key] = result
    run.last_transaction = result
    run:Emit("TransactionResolved", result)
    if ok and action == "module" then
        local kind = result.before.module_id and "ModuleChanged" or "ModuleInstalled"
        run:Emit(kind, copy(result))
    end
    return result
end
return E
