-- 非角色辅助标识沿用原资源；玩家/敌人始终交给真实 Emoji 字体渲染。
local G={}
local contexts={}
local icons={core='image/defense/ui_icon_core_darktech_20261007.png',
    turret='image/defense/ui_icon_turret_darktech_20261007.png'}
local sprites={['💎']='core',
    ['🔫']='turret',['❄️']='turret',['💣']='turret',['🌀']='turret',['🛡️']='turret',['🔱']='turret',['🛠️']='turret',['⚡']='turret'}
local badges={['⚓']='锚',['💥']='爆',
    ['🐟']='•',['⭐']='•',['💫']='•',['🐳']='•',['🔴']='•'}
function G.Init(vg)
    if contexts[vg] then return end
    local images={}
    for key,path in pairs(icons) do images[key]=nvgCreateImage(vg,path,NVG_IMAGE_NEAREST) end
    contexts[vg]=images
end
function G.Draw(vg,x,y,value,size,color)
    local images=contexts[vg]; if not images then return false end
    local kind=sprites[value];local img=kind and images[kind]
    if img and img>0 then
        local d=math.max(16,size)
        nvgSave(vg);nvgIntersectScissor(vg,x-d/2,y-d/2,d,d)
        nvgBeginPath(vg);nvgRect(vg,x-d/2,y-d/2,d,d)
        nvgFillPaint(vg,nvgImagePattern(vg,x-d/2,y-d/2,kind=='cat' and d*3 or d,kind=='cat' and d*3 or d,0,img,1))
        nvgFill(vg);nvgRestore(vg);return true
    end
    local caption=badges[value]
    if caption then
        nvgFontFace(vg,'sans');nvgFontSize(vg,math.max(12,size*0.75))
        nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE);nvgFillColor(vg,color)
        nvgText(vg,x,y,caption);return true
    end
    return false
end
function G.Stop(vg)
    for _,image in pairs(contexts[vg] or {}) do if image>0 then nvgDeleteImage(vg,image) end end
    contexts[vg]=nil
end
return G
