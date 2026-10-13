-- 浮窗只保存草案；类型、位置选择均不交易，确认时仍由 Economy 重验。
local UI=require('urhox-libs/UI')
local Art=require('defense.UIArt')
local Theme=require('defense.Theme')
local Economy=require('defense.Economy')
local TowerModules=require('defense.TowerModules')
local C=Theme.C
local P={}
local function label(value,c)
    return UI.Label{text=value or '',fontFamily='pixel',fontSize=13.5,fontColor=c or C.text,
        width='100%',whiteSpace='normal',maxLines=8,flexShrink=1}
end
local function dirty(view) view.modeKey='__dirty';view.dirty=true end
function P.Reset(view) view.placementType=nil;view.placementSlot=nil end
function P.SelectType(view,kind)
    if not view.run.config.towers[kind] then return end
    view.placementType,view.placementSlot=kind,nil
    dirty(view)
end
function P.SelectPosition(view,slot)
    if not view.placementType then return false end
    view.placementSlot=slot
    dirty(view)
    return slot~=nil
end
function P.Check(view)
    if not view.placementType then return false,'先在浮窗选择炮塔种类' end
    if not view.placementSlot then return false,'再点击当前房间内的槽位' end
    return Economy.Check(view.run,'build',view.placementSlot.id,view.placementType)
end
function P.Confirm(view)
    local ok=P.Check(view)
    if not ok then return false end
    local slot=view.placementSlot
    view:Action('transaction',{action='build',slot=slot.id,type=view.placementType})
    for _,tower in ipairs(view.run.towers) do
        if tower.slot_id==slot.id and tower.hp>0 then
            view.placementSlot=nil;dirty(view);return true
        end
    end
    return false
end
function P.Build(view)
    local run=view.run
    view.overlay:SetStyle({backgroundColor={0,0,0,0},pointerEvents='box-none'})
    view.placementSurface=UI.Widget{position='absolute',left=0,right=0,top=0,bottom=0,pointerEvents='auto',
        onClick=function(_,event)
            if event then view:Action('placement_position',{x=event.x,y=event.y}) end
        end}
    view.overlay:AddChild(view.placementSurface)
    local w,h=UI.GetViewportSize()
    local panel=Art.Frame({position='absolute',right=0,top=math.min(140,h*0.22),
        width=math.min(340,w*0.4),height=h*0.72,padding=12,gap=8,backgroundColor=C.panel,pointerEvents='auto'},view)
    view.overlayContent=panel;view.overlay:AddChild(panel)
    panel:AddChild(label('炮台布防',C.cyan))
    panel:AddChild(label('① 选种类  ② 点场景位置\n③ 在此确认放置',C.dim))
    local content=UI.ScrollView{width='100%',flexGrow=1,flexBasis=0,gap=6,scrollY=true}
    panel:AddChild(content)
    view.placementBalance=label('',Theme.Gold);content:AddChild(view.placementBalance)
    require('defense.ProtoView').OpenButtons(view,content)
    local types=UI.Panel{width='100%',flexDirection='row',flexWrap='wrap',gap=6}
    view.placementTypes={}
    content:AddChild(types)
    for _,kind in ipairs(run.config.facility_order or {'rapid','slow','area'}) do
        local def=run.config.towers[kind]
        local button=view:Button(def.name..' · '..def.cost,function() P.SelectType(view,kind) end,
            view.placementType==kind and 'success' or 'secondary')
        button:SetStyle({height=48,minWidth=90,flexGrow=1,flexBasis=120})
        button:SetText('')
        local caption=label(def.name..' · '..def.cost)
        caption:SetStyle({width='auto',flexGrow=1,flexBasis=0,minWidth=0,maxLines=2})
        button:AddChild(UI.Panel{width='100%',height='100%',flexDirection='row',alignItems='center',gap=4,
            pointerEvents='none',children={require('defense.TowerIcon'){towerType=kind},caption}})
        types:AddChild(button)
        view.placementTypes[kind]=button
    end
    view.placementStatus=label('',C.warn);content:AddChild(view.placementStatus)
    if view.placementType then
        local slot=view.placementSlot or {x=run.player.x,y=run.player.y}
        content:AddChild(label(require('defense.ProtoView').AttributesText(TowerModules.Attributes(run,
            {type=view.placementType,upgrade_count=0,hp=1,x=slot.x,y=slot.y}),run),C.dim))
    end
    local slot=view.placementSlot
    local tower
    for _,t in ipairs(run.towers) do if slot and t.slot_id==slot.id and t.hp>0 then tower=t;break end end
    if tower then
        content:AddChild(label(run.config.towers[tower.type].name..' · 耐久 '..math.floor(tower.hp)..'/'..tower.max_hp))
        content:AddChild(view:TransactionButton('upgrade',slot.id,nil,'升级'))
        content:AddChild(view:TransactionButton('repair_tower',slot.id,nil,'修复设施 +80 / 20资金'))
        content:AddChild(view:TransactionButton('demolish',slot.id,nil,'拆除设施'))
        local Proto=require('defense.ProtoView')
        if run.config.sanctuary_expansion then
            for _,id in ipairs({'reach','focus'}) do
                content:AddChild(view:TransactionButton('branch',slot.id,id,run.config.branches[id].name..' · 20星砂'))
            end
        end
        for id,owned in pairs(run.module_inventory or {}) do
            local def=Proto.Definitions(run)[id]
            if owned and def then content:AddChild(view:TransactionButton('module',slot.id,id,'安装 '..def.name)) end
        end
    end
    content:AddChild(view:TransactionButton('repair',nil,nil,'核心修复 +200 / 40资金'))
    content:AddChild(view:TransactionButton('heal',nil,nil,'角色治疗 +25 / 20资金'))
    view.placementConfirm=view:Button('确认放置',function() P.Confirm(view) end,'primary')
    panel:AddChild(view.placementConfirm)
    panel:AddChild(view:Button('取消 / 继续战备',function() view:Action('close_logistics') end))
    P.Refresh(view)
end
function P.Refresh(view)
    view.placementBalance:SetText('资金 '..math.floor(view.run.currency)..' · 星砂 '..math.floor(view.run.exploration_currency or 0))
    local ok,reason=P.Check(view)
    view.placementConfirm:SetDisabled(not ok)
    view.placementStatus:SetText((view.placementSlot and '已选 '..view.placementSlot.id..'\n' or '')..
        (ok and '位置已选中，确认后扣费放置' or reason)..
        (view.latestNotice~='' and '\n'..view.latestNotice or ''))
    for _,binding in ipairs(view.transactionButtons) do
        local allowed,why=Economy.Check(view.run,binding.action,binding.slot,binding.towerType)
        binding.button:SetDisabled(not allowed);binding.reason:SetText(allowed and '' or why)
    end
end
return P
