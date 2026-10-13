-- 全域大环：三个主分支以 120 度连接同一圈房间；去掉主空间后仍能环行 A/B/C。
-- 真实碰撞设计（u）：六边房 r=5.196，环边走廊2，中心步长 s=2r+2。
--                     B
--                 /---o---\
--                o    |    o
--               /     核    \
--           C--o----/   \----o--A
--               \           /
--                o---------o
-- 每条圆环边由三个等步长房间段构成；三条通路接在相隔120度的顶点。
-- 多边形拼成圆环外形，端口仍严格使用引擎约定六方向，不画假连接线。
local L=require('defense.Lattice')
local Random=require('defense.Random')
local Ring={}
function Ring.Generate(seed,difficulty,options)
    local plan=options.plan
    local rng=Random.New(seed or 20261012)
    local axis=30+(rng:Index(3)-1)*60
    local step=2*L.Inradius('hex')+2
    -- 每条边四段、全环24房：比原18房环外移一个房间节距，仍保留核心到环的可行走辐条。
    local edgeSegments=4
    local radius=edgeSegments*step
    local g={version='three-branch-ring-v1',seed=seed,difficulty=difficulty,rooms={},links={},byId={},
        districts={},anchors={},degraded={},steps=0,maxSteps=options.max_steps or 8000,linkSeq=0,
        main='D0',global_ring={rooms={},junctions={},radius=radius}}
    local function room(id,kind,x,y,rotation,district,role)
        local r={id=id,kind=kind,x=x,y=y,rotation=rotation or 0,district=district,role=role,
            ports=L.PortNormals(kind,rotation or 0),used={},degree=0,slots=L.Spec(kind).slots,slot_kind=L.Spec(kind).slot_kind}
        g.rooms[#g.rooms+1]=r;g.byId[id]=r
        if district~='core' then g.districts[district].rooms[#g.districts[district].rooms+1]=id end
        return r
    end
    local function connect(a,b,extra)
        local dir=L.Norm(math.deg(math.atan(b.y-a.y,b.x-a.x)))
        local pa,pb=L.PortIndexFacing(a,dir),L.PortIndexFacing(b,L.Norm(dir+180))
        assert(pa and pb and not a.used[pa] and not b.used[pb],'大环端口冲突:'..a.id..'/'..b.id)
        local length=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)-L.Inradius(a.kind)-L.Inradius(b.kind)
        assert(L.LegalCorridorLength(length),'大环连接长度越界')
        g.linkSeq=g.linkSeq+1
        local link={id='L'..g.linkSeq,a=a.id,b=b.id,aPort=pa,bPort=pb,length=length}
        for k,v in pairs(extra or {}) do link[k]=v end
        a.used[pa],b.used[pb]=link.id,link.id;a.degree,b.degree=a.degree+1,b.degree+1
        g.links[#g.links+1]=link
        return link
    end
    local districts={'A','B','C'}
    for i,id in ipairs(districts) do g.districts[id]={rooms={},direction=L.Norm(axis+(i-1)*120),
        portIndex=i,loops=1,gates=0,boss_waves=plan.boss_waves,loops_wanted=1,hex=0} end
    local main=room('D0','dodeca',0,0,0,'core','main')
    -- 同一外圈24房：每两条六边形边归一个主分支，顶点为三分支的连接站。
    for edge=0,5 do
        local a,b=math.rad(axis+edge*60),math.rad(axis+(edge+1)*60)
        local ax,ay,bx,by=radius*math.cos(a),radius*math.sin(a),radius*math.cos(b),radius*math.sin(b)
        for j=0,edgeSegments-1 do
            local index=edge*edgeSegments+j+1
            local district=districts[math.floor((index-1)/(2*edgeSegments))+1]
            local r=room('O'..index,'hex',ax+(bx-ax)*j/edgeSegments,ay+(by-ay)*j/edgeSegments,0,district,'ring')
            r.ring=true;r.empty=index%2==0
            g.global_ring.rooms[#g.global_ring.rooms+1]=r.id
        end
    end
    local ringCount=#g.global_ring.rooms
    for i=1,ringCount do
        local r,nextRoom=g.byId['O'..i],g.byId['O'..(i%ringCount+1)]
        connect(r,nextRoom,{global_ring=true,loop=i==ringCount})
        r.access_from={'O'..((i+ringCount-2)%ringCount+1),nextRoom.id}
    end
    -- 径向五段精确接到外圈顶点。斜段略长，保证两间三角房不相交；
    -- 三条直段补足总径向距离，每段走廊仍在[2,4]u。
    local diagonalLength=3.6
    local radialLength=(radius-L.Inradius('dodeca')-3*L.Inradius('tri')-4*L.Inradius('hex')-diagonalLength)/3
    assert(L.LegalCorridorLength(diagonalLength) and L.LegalCorridorLength(radialLength),'径向走廊长度越界')
    for index,district in ipairs(districts) do
        local d=g.districts[district]
        local dir=d.direction
        local parent=main
        for offset,kind in ipairs({'tri','hex','tri','hex'}) do
            local stepDir=dir+(offset==2 and 60 or offset==3 and -60 or 0)
            local port=L.PortIndexFacing(parent,L.Norm(stepDir))
            local length=(offset==2 or offset==3) and diagonalLength or radialLength
            local candidate=L.Place(parent,port,kind,length,offset==1 and 'T-'..district or 'S-'..district..'-'..offset)
            local r=room(candidate.id,kind,candidate.x,candidate.y,candidate.rotation,district,offset==1 and 'gate' or 'spoke')
            r.empty=offset==1
            connect(parent,r);parent=r
            if offset==1 then d.gate=r.id end
        end
        local junction=g.byId['O'..((index-1)*2*edgeSegments+1)]
        connect(parent,junction);junction.access_from[#junction.access_from+1]=parent.id
        g.global_ring.junctions[district]=junction.id
        d.junction=junction.id
    end
    -- 地区核心放在大环另一个顶点外侧；普通房只向环外生长，不割断大环。
    local function place(parent,kind,id,district,preferred)
        local ports={}
        for i,dir in ipairs(parent.ports) do if not parent.used[i] then ports[#ports+1]=i end end
        table.sort(ports,function(a,b)
            local da,db=L.AngleGap(parent.ports[a],preferred),L.AngleGap(parent.ports[b],preferred)
            if math.abs(da-db)>0.001 then return da<db end
            return a<b
        end)
        for _,length in ipairs({3,2.5,3.5,2,4}) do
            for _,port in ipairs(ports) do
                g.steps=g.steps+1
                local c=L.Place(parent,port,kind,length,id)
                local ok=true
                for _,other in ipairs(g.rooms) do if L.RoomsOverlap(c,other,L.MinGap) then ok=false;break end end
                local back=L.PortIndexFacing(c,L.Norm(parent.ports[port]+180))
                local corridor=L.Corridor(parent,port,c,back,length)
                if ok then
                    for _,other in ipairs(g.rooms) do if L.CorridorHitsRoom(corridor,other,parent.id,id) then ok=false;break end end
                end
                if ok then
                    local r=room(id,kind,c.x,c.y,c.rotation,district,'branch')
                    connect(parent,r);return r
                end
            end
        end
    end
    for i,district in ipairs(districts) do
        local d=g.districts[district]
        local outward=L.Norm(d.direction+60)
        local anchor=g.byId['O'..((i-1)*2*edgeSegments+edgeSegments+1)]
        local core=assert(place(anchor,'dodeca','D-'..district,district,outward),'地区核心无合法位置')
        core.role='district_core';d.core=core.id
        local tail=core
        for index=1,plan.rooms-13 do
            local kind=index%3==0 and 'tri' or 'hex'
            tail=assert(place(tail,kind,'R-'..district..'-'..index,district,outward),'环外分支生成失败')
        end
        d.normalRooms=plan.rooms-13
    end
    -- 锁只放环外：保留一圈真实连接，不用单向锁把三分支间的环路切断。
    local gateCount=0
    for _,link in ipairs(g.links) do
        if gateCount<plan.gates and g.byId[link.b].role=='branch' then
            link.gate,link.gate_state=true,'locked';gateCount=gateCount+1
            local d=g.districts[g.byId[link.b].district];d.gates=d.gates+1
        end
    end
    for _,r in ipairs(g.rooms) do
        if r.kind=='hex' then g.anchors[#g.anchors+1]=r.id;g.districts[r.district].hex=g.districts[r.district].hex+1 end
    end
    g.stats={rooms=#g.rooms,links=#g.links,steps=g.steps,hex=#g.anchors,loops=#g.links-#g.rooms+1,
        gates=gateCount,dodeca=4,enemy_scale=plan.enemy_scale,boss_waves=plan.boss_waves}
    return g
end
return Ring
