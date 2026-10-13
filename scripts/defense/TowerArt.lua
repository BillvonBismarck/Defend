-- 八类设施独立像素母版；每个 NanoVG 上下文加载一次，32/64px 整数倍显示。
local A={}
A.Order={'rapid','slow','area','repulsor','barricade','stakes','repair_station','energy_station'}
A.Paths={}
for _,kind in ipairs(A.Order) do A.Paths[kind]='image/defense/towers-v2/'..kind..'.png' end
local contexts={}
function A.Init(vg)
    if contexts[vg] then return end
    local images={}
    for _,kind in ipairs(A.Order) do
        images[kind]=nvgCreateImage(vg,A.Paths[kind],NVG_IMAGE_NEAREST)
        assert(images[kind]>0,'炮塔贴图加载失败:'..kind)
    end
    contexts[vg]=images
end
function A.Draw(vg,x,y,kind,size)
    if not contexts[vg] then A.Init(vg) end
    local image=contexts[vg][kind]
    if not image then return false end
    local d=size==32 and 32 or 64
    local left,top=math.floor(x-d/2),math.floor(y-d/2)
    nvgBeginPath(vg);nvgRect(vg,left,top,d,d)
    nvgFillPaint(vg,nvgImagePattern(vg,left,top,d,d,0,image,1));nvgFill(vg)
    return true
end
function A.Stop(vg)
    for _,image in pairs(contexts[vg] or {}) do nvgDeleteImage(vg,image) end
    contexts[vg]=nil
end
function A.LoadedCount(vg)
    local count=0;for _ in pairs(contexts[vg] or {}) do count=count+1 end
    return count
end
return A
