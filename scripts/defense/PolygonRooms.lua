-- 独立房间战斗实例：三角三波、六边两波不同小Boss、地区核心一波Boss。
-- 不创建 WaveDirector，不写 wave_id，不改变守核计数；失败沿用 Run 权威。
local Anchors = require("defense.Anchors")
local Rooms = {}
function Rooms.UpdateAccess(run)
    local index = {}
    for _, room in ipairs(run.rooms) do index[room.id] = room end
    for _, room in ipairs(run.rooms) do
        local parent = index[room.prerequisite]
        local accessible = not parent or parent.state == "cleared" or parent.state == "claimed"
            or room.state == "cleared" or room.state == "claimed"
        room.prerequisite_satisfied, room.accessible, room.unlocked = accessible, accessible, accessible
        local was = run.map.locked[room.id]
        run.map:SetUnlocked(room.id, accessible)
        if accessible and was then run:Emit("RoomUnlocked", { id = room.id, prerequisite = room.prerequisite }) end
    end
    for _, link in ipairs(run.config.topology.links) do
        if link.gate then
            local parent = index[link.a]
            local id = "gate_" .. link.id
            local opened = not parent or parent.state == "cleared" or parent.state == "claimed"
            local was = run.map.locked[id]
            run.map:SetUnlocked(id, opened)
            if opened and was then run:Emit("GateOpened", { gate_id = id, reason = "room_cleared" }) end
        end
    end
    return true
end
local function definition(run, id)
    for _, def in ipairs(run.config.rooms) do if def.id == id then return def end end
end
local function spawnWave(run, room, Combat)
    local def, wave = definition(run, room.id), room.encounter_wave
    local roles = room.kind == "hex" and { wave == 1 and "commander" or "siege", "advance", "ranged" }
        or room.kind == "dodeca" and { "final", "elite", "advance" } or { "advance", "advance", "ranged", "charger" }
    room.guard_ids = {}
    for i, role in ipairs(roles) do
        local angle = i * math.pi * 2 / #roles
        local x, y = room.x + math.cos(angle) * 3, room.y + math.sin(angle) * 3
        if not run.map:IsWalkable(x, y, run.config.enemies[role].radius) then x, y = room.x, room.y end
        local enemy = Combat.Spawn(run, { role = role, room_id = room.id, x = x, y = y,
            spawn_key = "encounter:" .. room.id .. ":" .. wave .. ":" .. i })
        if type(enemy) ~= "table" then
            run.technical_error = "房间守军生成失败:" .. room.id
            run:Pause("technical"); run:Emit("CombatError", { reason = run.technical_error }); return false
        end
        enemy.summon_disabled = true
        if room.kind == "hex" and i == 1 then enemy.hp, enemy.max_hp = 250 * run.config.enemy_scale, 250 * run.config.enemy_scale end
        room.guard_ids[#room.guard_ids + 1] = enemy.id
    end
    run:Emit("RoomActivated", { id = room.id, count = #room.guard_ids, tier = def.tier, encounter_wave = wave })
    return true
end
function Rooms.Update(run, Combat)
    if run.ended or run:IsPaused() then return end
    local current = run.map:RoomAt(run.player.x, run.player.y)
    run.current_room_id, run.active_rooms = current or run.config.topology.main, {}
    run.active_rooms[run.current_room_id] = true
    local count = 1
    for _, id in ipairs(run.map.neighbors[run.current_room_id] or {}) do
        if count >= 3 then break end
        if run.map.locked[id] ~= true then run.active_rooms[id], count = true, count + 1 end
    end
    for _, room in ipairs(run.rooms) do
        if room.accessible and room.state == "unvisited" and room.id == current then
            room.state, room.encounter_wave = "active", 1
            run.room_encounter = { room_id = room.id }
            run:Emit("RoomEncounterStarted", { room_id = room.id, waves = definition(run, room.id).encounter_waves, kind = room.kind })
            spawnWave(run, room, Combat)
        end
        if room.state == "active" then
            local alive = false
            for _, enemy in ipairs(run.enemies) do if enemy.alive and enemy.room_id == room.id then alive = true; break end end
            if not alive and #room.guard_ids > 0 and run:PendingHarmfulCount() == 0 then
                run:Emit("RoomBossWaveCleared", { room_id = room.id, encounter_wave = room.encounter_wave, kind = room.kind })
                if room.encounter_wave < definition(run, room.id).encounter_waves then
                    room.encounter_wave = room.encounter_wave + 1
                    spawnWave(run, room, Combat)
                else
                    room.state, run.room_encounter = "cleared", nil
                    run:Emit("RoomCleared", { id = room.id, tier = room.tier })
                    Anchors.Activate(run, room.id)
                    Rooms.UpdateAccess(run)
                    run:Emit("DefenseSiteAvailable", { room_id = room.id, reason = "room_cleared" })
                end
            end
        end
    end
end
return Rooms
