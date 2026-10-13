-- Native GPU and actual UI dispatch. All fixture changes stay in validation instances.
local R=require('defense.Runtime')
local UI=require('urhox-libs/UI')
local Combat=require('defense.Combat')
local Rooms=require('defense.PolygonRooms')
local Anchors=require('defense.Anchors')
local scene=QA_SCENE
local function click(x,y)
    local data={x=x,y=y,button=MOUSEB_LEFT,pointerId=201,pointerType='touch'}
    UI.HandlePointerDown(UI.PointerEvent.new('PointerDown',data))
    UI.HandlePointerUp(UI.PointerEvent.new('PointerUp',data))
end
local function anchorClick(id)
    local map=R.GetView().mapOverview
    local ox,oy,s=require('defense.PolygonMapView').Transform(R.GetRun(),map:GetAbsoluteLayout(),false,map.zoom,map.panX,map.panY)
    local a=R.GetRun().anchors[id]
    click((ox+a.x*s)*UI.GetScale(),(oy+a.y*s)*UI.GetScale())
end
local gateId,foughtId,walkPath,walkIndex,targetSlot
V.atFrame(5,function()
    local v=R.GetView();v:NewRun(20,false,'polygon_expansion')
    local r=R.GetRun();r:FinishStory();r:Resume('focus')
    r.preparation_remaining=300 -- QA traversal allowance only.
    gateId=r.config.topology.districts.A.gate
    V.assert(r.anchors[r.config.topology.main].active,'core is active from creation')
    local ring=r.config.topology.global_ring
    V.assert(ring and #ring.rooms==24,'global circular perimeter exists')
    V.assert(ring.junctions.A and ring.junctions.B and ring.junctions.C,'all three major branches attached')
end)
V.atFrame(12,function()
    local r,v=R.GetRun(),R.GetView()
    if scene=='map' or scene=='activation' then
        local target=r.anchors[gateId]
        walkPath=r.map:Path(r.player.x,r.player.y,target.x,target.y,r.player.radius)
        walkIndex=1
        V.assert(walkPath~=nil,'real movement route to empty room exists')
    elseif scene=='towers' or scene=='stress' or scene=='tactical' then
        r.currency=5000;r.exploration_currency=120;r:OpenLogistics()
        local kinds=require('defense.TowerArt').Order
        local count=0
        for _,slot in ipairs(r.config.build_slots) do if not slot.owner_room_id then
            count=count+1
            local result=r:Transact('build',slot.id,kinds[(count-1)%#kinds+1],'review2-tower-'..count)
            V.assert(result.ok,'real transaction creates independent facility '..count)
            if (scene=='towers' or scene=='tactical') and count==#kinds then break end
        end end
        r:Resume('logistics')
        if scene=='towers' or scene=='tactical' then
            if scene=='towers' then
                local positions={{-6,-1},{-2,-1},{2,-1},{6,-1},{-6,6},{-2,6},{2,6},{6,6}}
                for i,t in ipairs(r.towers) do t.x,t.y=positions[i][1],positions[i][2] end
            else
                local defs=r.config.towers
                V.assert(#r.towers==8,'all eight tower kinds built at unchanged real slots')
                for _,tower in ipairs(r.towers) do
                    V.assert(r.map:LineOfSight(tower.x,tower.y,r.core.x,r.core.y),'core slot has real line of sight')
                    if tower.type=='repair_station' then
                        V.assert((tower.x-r.core.x)^2+(tower.y-r.core.y)^2<=defs.repair_station.range^2,
                            'repair tower reaches damaged core')
                    end
                end
                r.core.hp=r.core.max_hp-40
                Combat.Update(r,0.05,{})
                V.assert(r.core.hp>r.core.max_hp-40,'repair station actually repairs core')
                local aided=false
                for _,tower in ipairs(r.towers) do
                    if tower.type~='energy_station' and require('defense.TowerModules').Attributes(r,tower).energy_received>0 then aided=true end
                end
                V.assert(aided,'energy station actually accelerates a neighboring tower')
            end
            r.drops={{id=100001,kind='gold',emoji='🪙',x=-3,y=3,alive=true,radius=0.1,amount=5},
                {id=100002,kind='xp',emoji='💠',x=3,y=3,alive=true,radius=0.1,amount=5}}
            r:Pause('gallery')
        else
            local remote
            for _,room in ipairs(r.rooms) do if room.kind=='hex' and #room.defense_slots>=3 then remote=room;break end end
            remote.state='cleared';r.map:SetUnlocked(remote.id,true)
            r.player.x,r.player.y=remote.x,remote.y;r:OpenLogistics()
            for _,id in ipairs(remote.defense_slots) do
                if #r.towers>=12 then break end
                r:Transact('build',id,'rapid','review2-remote-'..id)
            end
            r:Resume('logistics');r.player.x,r.player.y=0,4
            V.assert(#r.towers==12,'all twelve facility places filled')
            r.player.hp,r.player.max_hp,r.core.hp,r.core.max_hp=100000,100000,100000,100000
            r.player.attack_cd=1000
            v:Action('wave');r:StartAttack()
            for i=1,80 do
                local e=Combat.Spawn(r,{role=({'advance','ranged','charger','elite'})[(i-1)%4+1],portal='S',
                    x=(i%9-4)*1.5,y=4+math.floor((i-1)/9)*0.4-2,wave_id=r.wave_id})
                if type(e)=='table' then e.hp,e.max_hp=10000,10000 end
            end
        end
    elseif scene=='placement' or scene=='placement_confirm' then
        r.currency=1000;v:Action('logistics')
        for _,slot in ipairs(r.config.build_slots) do
            if not slot.owner_room_id and slot.x<0 and slot.y>0 then targetSlot=slot end
        end
        V.assert(targetSlot~=nil,'visible placement slot exists')
    end
end)
-- Spread traversal across real frames instead of a long synchronous QA callback.
for frame=15,398 do
    V.atFrame(frame,function()
        if not walkPath or not walkPath[walkIndex] then return end
        local r,p=R.GetRun(),walkPath[walkIndex]
        local dx,dy=p.x-r.player.x,p.y-r.player.y
        if dx*dx+dy*dy<0.2^2 then walkIndex=walkIndex+1;return end
        local distance=math.sqrt(dx*dx+dy*dy)
        r:Update(0.03,{x=dx/distance,y=dy/distance})
    end)
end
V.atFrame(400,function()
    local r,v=R.GetRun(),R.GetView()
    if scene=='map' or scene=='activation' then
        V.assert(r.anchors[gateId].active,'walking through empty room actually activates point')
        V.assert(r.room_encounter==nil,'empty room does not create phantom combat')
        r.player.x,r.player.y=0,4
        if scene=='map' then v:Action('map')
        else
            foughtId='S-A-3'
            for _,room in ipairs(r.rooms) do if room.id==foughtId then
                room.accessible=true;room.prerequisite=nil;r.map:SetUnlocked(room.id,true)
                r.player.x,r.player.y=room.x,room.y;break end end
            Rooms.Update(r,Combat)
            V.assert(r.room_encounter~=nil and not r.anchors[foughtId].active,'occupied non-hex room stays inactive')
            for wave=1,3 do
                for _,enemy in ipairs(r.enemies) do
                    if enemy.alive and enemy.room_id==foughtId then Combat.DamageEnemy(r,enemy,100000,'review2-clear') end
                end
                Rooms.Update(r,Combat)
                if wave<3 then V.assert(not r.anchors[foughtId].active,'remaining enemies delay activation') end
            end
            V.assert(r.anchors[foughtId].active,'clearing all waves activates non-hex point')
            V.assert(r.room_encounter==nil,'cleared room releases encounter')
            while r.player.experience>=require('defense.Progression').Threshold(r.player.level) do
                if not r:CheckUpgrade() then break end
                r:ChooseUpgrade(r.options[1].id)
            end
            r.player.x,r.player.y=0,4
            v:Action('map')
        end
    end
end)
V.atFrame((scene=='map' or scene=='activation') and 450 or 40,function()
    local r,v=R.GetRun(),R.GetView()
    if scene=='map' or scene=='activation' then
        V.assert(v.modeKey=='map','global map is visible')
        V.assert(Anchors.Status(r,gateId)=='available','entered point is green')
        V.assert(Anchors.Status(r,r.config.topology.main)=='blocked','active source is orange')
        V.assert(Anchors.Status(r,r.config.topology.districts.B.gate)=='inactive','unvisited empty point is red')
        if scene=='activation' then
            anchorClick(gateId)
            V.assert(r.last_teleport and r.last_teleport.ok,'real touch on green point teleports')
            V.assert(Anchors.Status(r,r.config.topology.main)=='blocked','cooldown makes active core orange')
        end
    elseif scene=='placement' or scene=='placement_confirm' then
        V.assert(v.placementTypes.rapid:GetNumChildren()>0,'real placement button contains individual texture icon')
        local b=v.placementTypes.rapid
        local l=b:GetAbsoluteLayout();click((l.x+l.w/2)*UI.GetScale(),(l.y+l.h/2)*UI.GetScale())
        V.assert(v.placementType=='rapid','nested texture icon preserves button hit test')
    end
end)
V.atFrame(55,function()
    if scene~='placement' and scene~='placement_confirm' then return end
    local r,v=R.GetRun(),R.GetView()
    local dpr=math.max(1,graphics:GetDPR())
    local ox,oy,s=R.GetBoard():GetTransform(graphics:GetWidth()/dpr,graphics:GetHeight()/dpr)
    click((ox+targetSlot.x*s)*dpr,(oy+targetSlot.y*s)*dpr)
    V.assert(v.placementSlot and v.placementSlot.id==targetSlot.id,'real touch selects world position')
    V.assert(#r.towers==0 and r.currency==1000,'draft does not build or charge')
end)
V.atFrame(70,function()
    if scene~='placement' and scene~='placement_confirm' then return end
    local v=R.GetView()
    V.assert(R.GetBoard().placementSlot==v.placementSlot,'four corner frame follows selected position')
    V.assert(not v.placementConfirm.props.disabled,'valid draft enables confirmation')
    if scene=='placement_confirm' then
        local l=v.placementConfirm:GetAbsoluteLayout()
        click((l.x+l.w/2)*UI.GetScale(),(l.y+l.h/2)*UI.GetScale())
        local r=R.GetRun()
        V.assert(#r.towers==1 and r.towers[1].type=='rapid','confirmation builds selected textured tower')
        V.assert(r.currency==1000-r.config.towers.rapid.cost,'confirmation charges exactly once')
        V.assert(not require('defense.Placement').Confirm(v),'duplicate confirmation cannot spend twice')
    end
end)
V.atFrame(QA_FINISH or 170,function()
    local r,v=R.GetRun(),R.GetView()
    V.assert(not r.pause_reasons.technical,'no technical failure')
    local ui=UI.GetNVGContext()
    if scene=='placement' or scene=='placement_confirm' then V.assert(require('defense.TowerArt').LoadedCount(ui)==8,'all eight UI textures cached once') end
    if scene=='stress' then V.assert(r:AliveCount()>50,'stress load stays active') end
    local towers=0;for _,t in ipairs(r.towers) do if t.hp>0 then towers=towers+1 end end
    print('[Review3QA] '..require('cjson').encode({scene=scene,rooms=#r.config.topology.rooms,
        ring_rooms=#r.config.topology.global_ring.rooms,enemies=r:AliveCount(),towers=towers,mode=v.modeKey,
        performance=R.GetPerformanceSnapshot(),viewport={graphics:GetWidth(),graphics:GetHeight()}}))
    V.finish()
end)
