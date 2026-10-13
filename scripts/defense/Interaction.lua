-- 日常交互只选当前房间内最近槽位；全域统计不授予远程交易权限。
local I = {}
function I.SlotAtPoint(run,x,y,radius)
    local room=run.map:RoomAt(run.player.x,run.player.y)
    if run.config.polygon_expansion and not room and run.map:IsInRegion('hall',run.player.x,run.player.y) then room=run.config.topology.main end
    if run.config.polygon_expansion and not room then return nil end
    local best,distance=nil,(radius or 0.9)^2
    for _,slot in ipairs(run.config.build_slots or {}) do
        local owner=slot.owner_room_id or (run.config.topology and run.config.topology.main) or 'core'
        if not run.config.polygon_expansion or owner==room then
            local d=(slot.x-x)^2+(slot.y-y)^2
            if d<=distance then best,distance=slot,d end
        end
    end
    return best
end
function I.NearestSlot(run)
    local room=run.map:RoomAt(run.player.x,run.player.y)
    if run.config.polygon_expansion then
        room=room or (run.map:IsInRegion('hall',run.player.x,run.player.y) and run.config.topology.main)
        if not room then return nil,math.huge,nil end
    else room=room or 'core' end
    local best,distance=nil,math.huge
    for _,slot in ipairs(run.config.build_slots or {}) do
        if (slot.owner_room_id or run.config.topology and run.config.topology.main or 'core')==room then
            local d=(slot.x-run.player.x)^2+(slot.y-run.player.y)^2
            if d<distance then best,distance=slot,d end
        end
    end
    return best,math.sqrt(distance),room
end
function I.Towers(run)
    local list={}
    for _,tower in ipairs(run.towers or {}) do if tower.hp>0 then list[#list+1]=tower end end
    return list
end
return I
