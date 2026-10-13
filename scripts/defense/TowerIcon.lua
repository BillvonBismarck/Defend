local UI=require('urhox-libs/UI')
local Art=require('defense.TowerArt')
local Icon=UI.Widget:Extend('DefenseTowerIcon')
function Icon:Init(props)
    props.width,props.height=32,32;props.flexShrink=0;props.pointerEvents='none'
    UI.Widget.Init(self,props)
end
function Icon:Render(vg)
    local l=self:GetAbsoluteLayout()
    if l.w<=0 or l.h<=0 then return end
    Art.Draw(vg,l.x+l.w/2,l.y+l.h/2,self.props.towerType,32)
end
return Icon
