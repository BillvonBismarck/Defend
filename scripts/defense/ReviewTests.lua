-- 第二次复审：三分支全域圆环、全部房间激活条件、三色状态与点选权限。
local T={}
function T.Register(case)
    case('REVIEW_TOWER_SLOT_REACH',function(t)
        local Scenarios=require('defense.Scenarios')
        local Map=require('defense.Map')
        local L=require('defense.Lattice')
        for _,seed in ipairs({1,97,20261012}) do
            local c=Scenarios.Get('polygon_expansion',{difficulty=3,seed=seed})
            local map=Map.New(c)
            for id in pairs(map.locked) do map:SetUnlocked(id,true) end
            local slotsByRoom={}
            for _,slot in ipairs(c.build_slots) do
                local owner=slot.owner_room_id or c.topology.main
                slotsByRoom[owner]=slotsByRoom[owner] or {}
                slotsByRoom[owner][#slotsByRoom[owner]+1]=slot
                t:Check(map:IsWalkable(slot.x,slot.y,0.65),'tower footprint walkable: '..slot.id)
            end
            for _,room in ipairs(c.topology.rooms) do
                local cx,cy=room.x*c.polygon_unit,room.y*c.polygon_unit
                local slots=slotsByRoom[room.id] or {}
                t:Equal(#slots,L.Spec(room.kind).slots,'preserve slot count: '..room.id)
                for i,slot in ipairs(slots) do
                    t:Check(map:IsInRegion(room.id,slot.x,slot.y),'slot inside owned room: '..slot.id)
                    t:Check(map:LineOfSight(slot.x,slot.y,cx,cy),'slot can see room traffic: '..slot.id)
                    local distance=math.sqrt((slot.x-cx)^2+(slot.y-cy)^2)
                    if room.kind=='hex' then
                        t:Check(distance<=c.towers.barricade.range,'short blocker reaches room traffic: '..slot.id)
                    elseif room.kind=='dodeca' then
                        t:Check(distance<=c.towers.repair_station.range,'repair station reaches core: '..slot.id)
                        if i<=6 then t:Check(distance<=c.towers.repulsor.range,'inner intercept reaches core route: '..slot.id) end
                    end
                    for j=1,i-1 do
                        local other=slots[j]
                        local spacing=math.sqrt((slot.x-other.x)^2+(slot.y-other.y)^2)
                        t:Check(spacing>1.3,'tower footprints distinct: '..slot.id..'/'..other.id)
                    end
                end
                if room.kind=='hex' then
                    t:Check((slots[1].x-slots[2].x)^2+(slots[1].y-slots[2].y)^2<c.towers.energy_station.range^2,
                        'energy station can support neighbor: '..room.id)
                end
            end
        end
    end)
    case('REVIEW_GLOBAL_RING',function(t)
        for level=1,5 do
            for _,seed in ipairs({1,97,194,901,20261012}) do
                local c=require('defense.Scenarios').Get('polygon_expansion',{difficulty=level,seed=seed})
                local graph,circle=c.topology,c.topology.global_ring
                t:Check(require('defense.Topology').Validate(graph),'geometry valid')
                t:Equal(#circle.rooms,24,'one complete middle-distance ring')
                local step=2*require('defense.Lattice').Inradius('hex')+2
                t:Near(circle.radius,4*step,'ring centerline is four room steps from core')
                local turns,neighbors=0,{}
                for _,id in ipairs(circle.rooms) do neighbors[id]={} end
                for _,link in ipairs(graph.links) do if link.global_ring then
                    neighbors[link.a][#neighbors[link.a]+1]=link.b
                    neighbors[link.b][#neighbors[link.b]+1]=link.a
                end end
                for i,id in ipairs(circle.rooms) do
                    t:Equal(#neighbors[id],2,'two actual passages at every circle node')
                    local a,b=graph.byId[id],graph.byId[circle.rooms[i%#circle.rooms+1]]
                    local delta=(math.atan(b.y,b.x)-math.atan(a.y,a.x)+math.pi)%(2*math.pi)-math.pi
                    turns=turns+delta
                end
                t:Near(math.abs(turns),2*math.pi,'circle winds once around core')
                local origin=circle.junctions.A
                local queue,seen,cursor={origin},{[origin]=true},1
                while cursor<=#queue do
                    local id=queue[cursor];cursor=cursor+1
                    for _,other in ipairs(neighbors[id]) do if not seen[other] then seen[other]=true;queue[#queue+1]=other end end
                end
                t:Check(seen[circle.junctions.B] and seen[circle.junctions.C],'A/B/C connect without central hub')
                t:Equal(#queue,#circle.rooms,'entire circle connected')
                t:Equal(#graph.rooms,1+3*(12+level*4),'map size profile retained')
            end
        end
    end)
    case('REVIEW_ANCHOR_ACTIVATION',function(t)
        local r=require('defense.Run').New{scenario_id='polygon_expansion'}
        r:FinishStory();r.pause_reasons={}
        local Rooms,Combat=require('defense.PolygonRooms'),require('defense.Combat')
        t:Check(r.anchors[r.config.topology.main].active,'core active by default')
        local count=0;for _ in pairs(r.anchors) do count=count+1 end
        t:Equal(count,#r.config.rooms+1,'every room has a teleport point')
        local empty
        for _,room in ipairs(r.rooms) do if room.role=='gate' then empty=room;break end end
        t:Check(not r.anchors[empty.id].active,'empty room starts inactive')
        r.player.x,r.player.y=empty.x,empty.y;Rooms.Update(r,Combat)
        t:Check(r.anchors[empty.id].active,'walk into empty gate activates point')
        local fought
        for _,room in ipairs(r.rooms) do if room.kind=='tri' and room.role~='gate' then fought=room;break end end
        fought.prerequisite=nil;fought.accessible=true;r.map:SetUnlocked(fought.id,true)
        r.player.x,r.player.y=fought.x,fought.y;Rooms.Update(r,Combat)
        t:Check(not r.anchors[fought.id].active,'occupied room stays inactive')
        for wave=1,3 do
            for _,enemy in ipairs(r.enemies) do if enemy.room_id==fought.id then enemy.hp=0;enemy.alive=false end end
            Rooms.Update(r,Combat)
            if wave<3 then t:Check(not r.anchors[fought.id].active,'remaining wave prevents early activation') end
        end
        t:Check(r.anchors[fought.id].active,'non-hex room activates after clearing enemies')
        local function activations()
            local n=0;for _,e in ipairs(r.events) do if e.kind=='AnchorActivated' and e.data.room_id==fought.id then n=n+1 end end;return n
        end
        local events=activations();Rooms.Update(r,Combat)
        t:Equal(activations(),events,'activation event never repeats')
    end)
    case('REVIEW_ANCHOR_THREE_COLORS',function(t)
        local r=require('defense.Run').New{scenario_id='polygon_expansion'}
        r:FinishStory();r.pause_reasons={}
        local A=require('defense.Anchors')
        local target=r.config.topology.districts.A.gate
        t:Equal(A.Status(r,target),'inactive','red: not activated')
        t:Equal(A.Status(r,r.config.topology.main),'blocked','orange: active current room')
        r.player.x,r.player.y=r.anchors[target].x,r.anchors[target].y
        require('defense.PolygonRooms').Update(r,require('defense.Combat'))
        r.player.x,r.player.y=0,4
        t:Equal(A.Status(r,target),'available','green: legal activated destination')
        r:Pause('map');t:Check(A.Teleport(r,target,'review2').ok,'real teleport succeeds')
        t:Equal(A.Status(r,r.config.topology.main),'blocked','orange: active but cooling down')
        t:Equal(A.Status(r,r.config.topology.districts.B.gate),'inactive','red remains red during cooldown')
    end)
    case('REVIEW_POSITION_SCOPE',function(t)
        local r=require('defense.Run').New{scenario_id='polygon_expansion'}
        r:FinishStory();r:OpenLogistics()
        local I=require('defense.Interaction')
        local slot=r.config.build_slots[1]
        t:Equal(I.SlotAtPoint(r,slot.x,slot.y),slot,'core selection remains valid')
        for _,remote in ipairs(r.config.build_slots) do if remote.owner_room_id then
            t:Equal(I.SlotAtPoint(r,remote.x,remote.y),nil,'remote selection rejected');break end end
    end)
end
return T
