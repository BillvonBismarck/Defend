-- 传送权威：UI 只提交目标与请求ID。主空间作为已激活中转站，跨群系须经主空间。
local Anchors = {}
function Anchors.Init(run)
    run.anchors, run.anchor_cooldown = {}, 0
    if run.config.polygon_expansion then
        run.anchors[run.config.topology.main] = { id = run.config.topology.main, district = "core", x = 0, y = 4, active = true }
        for _, def in ipairs(run.config.rooms) do
            if def.kind == "hex" then run.anchors[def.id] = { id = def.id, district = def.region_id, x = def.x, y = def.y, active = false } end
        end
    end
end
function Anchors.Activate(run, id)
    local anchor = run.anchors[id]
    if not anchor or anchor.active then return false end
    anchor.active = true
    run:Emit("AnchorActivated", { room_id = id, x = anchor.x, y = anchor.y })
    return true
end
function Anchors.Check(run, targetId)
    if not run.config.polygon_expansion then return false, "本场景未启用传送" end
    if run.ended or run.player.hp <= 0 or run.core.hp <= 0 then return false, "本局已结束" end
    if run.state ~= "PREPARATION" then return false, "仅战备期可传送" end
    if run.room_encounter then return false, "房间交战中不可传送" end
    for reason in pairs(run.pause_reasons) do if reason ~= "map" then return false, "请先关闭其它面板" end end
    if run.anchor_cooldown > 0 then return false, "传送冷却 " .. math.ceil(run.anchor_cooldown) .. "秒" end
    local sourceId = run.map:RoomAt(run.player.x, run.player.y) or
        (run.map:IsInRegion("hall", run.player.x, run.player.y) and run.config.topology.main)
    local source, target = run.anchors[sourceId], run.anchors[targetId]
    if not source or not source.active then return false, "请前往已激活锚点房间" end
    if not target or not target.active then return false, "目标锚点尚未激活" end
    if source.id == target.id then return false, "已在目标房间" end
    if source.district ~= target.district and source.district ~= "core" and target.district ~= "core" then return false, "跨群系请经主空间中转" end
    if not run.map:IsWalkable(target.x, target.y, run.player.radius) then return false, "目标落点不可通行" end
    return true, "传送 · 冷却20秒"
end
function Anchors.Teleport(run, targetId, requestId)
    if type(requestId) ~= "string" or requestId == "" then return { ok = false, reason = "缺少请求ID" } end
    local key = "anchor:" .. requestId
    if run.transactions[key] then return run.transactions[key] end
    local ok, reason = Anchors.Check(run, targetId)
    local result = { ok = ok, reason = reason, target_id = targetId, request_id = requestId }
    run.transactions[key], run.last_teleport = result, result
    if not ok then return result end
    local target = run.anchors[targetId]
    local fromX, fromY = run.player.x, run.player.y
    run:Emit("RecallStarted", { target_id = targetId, teleport = true })
    run.player.x, run.player.y, run.anchor_cooldown = target.x, target.y, 20
    run:Emit("Teleported", { target_id = targetId, x = target.x, y = target.y, from_x = fromX, from_y = fromY, cooldown = 20 })
    run:Emit("RecallCompleted", { target_id = targetId, x = target.x, y = target.y, teleport = true })
    return result
end
return Anchors
