local T={}
function T.Register(case)
    case('ROOM_STREAM_NETWORK',function(t)
        local Scenarios=require('defense.Scenarios')
        local Topology=require('defense.Topology')
        for level=1,5 do
            for _,seed in ipairs({97,194,20261012}) do
                local c=Scenarios.Get('polygon_expansion',{difficulty=level,seed=seed})
                t:Check(Topology.Validate(c.topology),'valid large map')
                t:Equal(#c.topology.rooms,1+3*(12+level*4),'room count profile')
                t:Check(c.topology.stats.loops>=3,'three or more real closed loops')
                local branches=0
                for _,r in ipairs(c.topology.rooms) do if r.degree>=3 then branches=branches+1 end end
                t:Check(branches>3,'multiple branches outside main room')
            end
        end
    end)
    case('ROOM_STREAM_NEAREST',function(t)
        local r=require('defense.Run').New{scenario_id='polygon_expansion',seed=20261012}
        r:FinishStory()
        local I=require('defense.Interaction')
        local slot,d=I.NearestSlot(r)
        t:Check(slot~=nil,'main room has nearest slot')
        for _,s in ipairs(r.config.build_slots) do
            if not s.owner_room_id then t:Check(d*d<=(s.x-r.player.x)^2+(s.y-r.player.y)^2+0.00001,'nearest local result') end
        end
        r.player.x,r.player.y=slot.x,slot.y
        t:Equal(I.NearestSlot(r).id,slot.id,'walking changes selection')
        require('defense.PolygonRooms').Update(r,require('defense.Combat'))
        local count=0;for _ in pairs(r.active_rooms) do count=count+1 end
        t:Equal(count,1,'only current room active')
        t:Equal(#r.enemies,0,'no remote room content preloaded')
        local link=r.config.topology.links[1]
        local a,b=r.config.topology.byId[link.a],r.config.topology.byId[link.b]
        local corridor=require('defense.Lattice').Corridor(a,link.aPort,b,link.bPort,link.length)
        r.player.x,r.player.y=(corridor.x1+corridor.x2)*r.config.polygon_unit/2,(corridor.y1+corridor.y2)*r.config.polygon_unit/2
        t:Equal(I.NearestSlot(r),nil,'corridor cannot target distant main slots')
        local geometry=r.map --[[@as table]]
        t:Check(geometry:ResidentRoom(r.player.x,r.player.y)==link.a or geometry:ResidentRoom(r.player.x,r.player.y)==link.b,'corridor residency follows its endpoints')
    end)
    case('ROOM_STREAM_QUERY_BUDGET',function(t)
        local c=require('defense.Scenarios').Get('polygon_expansion',{difficulty=5,seed=20261012})
        local map=require('defense.Map').New(c) --[[@as table]]
        local queries=map.edgeIndex:Query(-1,3,1,5)
        t:Check(#queries<20,'local narrow phase ignores remote edges')
        local total=0
        debug.sethook(function() total=total+1000 end,'',1000)
        local ok,err=pcall(function()
            for _=1,120 do
                assert(map:LineOfSight(0,4,0,4.02,0.48))
                map:Move(0,4,0.01,0.01,0.48)
            end
        end)
        local stopHook=debug.sethook --[[@as fun()]]
        stopHook()
        t:Check(ok,tostring(err))
        t:Check(total<1500000,'local movement instruction budget')
    end)
end
return T
