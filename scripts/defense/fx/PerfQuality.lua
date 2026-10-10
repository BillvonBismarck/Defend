--- ============================================================================
--- PerfQuality.lua — 性能档位管理
--- 五档性能控制，从最低到最高逐步开启渲染特效。
---
--- 档位说明：
---   1 省电   — 无拖尾、无粒子、无冲击波、无闪光、无辉光
---   2 流畅   — 无拖尾、粒子减半、无冲击波、无闪光、无辉光
---   3 均衡   — 短拖尾、粒子正常、有冲击波、无闪光、无辉光
---   4 精致   — 全拖尾、粒子全量、有冲击波、有闪光、无辉光
---   5 全量   — 全拖尾、粒子全量、有冲击波、有闪光、有辉光
--- ============================================================================

local PerfQuality = {}

-- 档位定义表
local LEVELS = {
    -- 1 省电
    {
        label_zh      = "省电",  label_en = "Low",
        trailEnabled   = false,   -- 子弹拖尾
        particleScale  = 0,       -- 粒子数量系数（0=禁用, 1=全量）
        shockwaveEnabled = false, -- SpawnShockWave
        flashEnabled   = false,   -- SpawnFlash
        glowEnabled    = false,   -- Bloom 辉光
    },
    -- 2 流畅
    {
        label_zh      = "流畅",  label_en = "Smooth",
        trailEnabled   = false,
        particleScale  = 0.4,
        shockwaveEnabled = false,
        flashEnabled   = false,
        glowEnabled    = false,
    },
    -- 3 均衡
    {
        label_zh      = "均衡",  label_en = "Balanced",
        trailEnabled   = true,
        trailLenMult   = 0.5,     -- 拖尾长度系数（仅 trailEnabled=true 时有效）
        particleScale  = 1.0,
        shockwaveEnabled = true,
        flashEnabled   = false,
        glowEnabled    = false,
    },
    -- 4 精致
    {
        label_zh      = "精致",  label_en = "High",
        trailEnabled   = true,
        trailLenMult   = 1.0,
        particleScale  = 1.0,
        shockwaveEnabled = true,
        flashEnabled   = true,
        glowEnabled    = false,
    },
    -- 5 全量
    {
        label_zh      = "全量",  label_en = "Ultra",
        trailEnabled   = true,
        trailLenMult   = 1.0,
        particleScale  = 1.0,
        shockwaveEnabled = true,
        flashEnabled   = true,
        glowEnabled    = true,
    },
}

--- 当前档位（1-5）
PerfQuality.level = 3  -- 默认均衡

--- 设置档位（1-5）
---@param lvl number
function PerfQuality.SetLevel(lvl)
    lvl = math.max(1, math.min(5, math.floor(lvl)))
    PerfQuality.level = lvl
end

--- 获取当前档位配置
---@return table
function PerfQuality.Get()
    return LEVELS[PerfQuality.level]
end

--- 当前是否启用拖尾
function PerfQuality.TrailEnabled()
    return LEVELS[PerfQuality.level].trailEnabled
end

--- 当前拖尾长度系数（1.0 = 全量，0.5 = 一半）
function PerfQuality.TrailLenMult()
    return LEVELS[PerfQuality.level].trailLenMult or 1.0
end

--- 当前粒子数量系数（0~1）
function PerfQuality.ParticleScale()
    return LEVELS[PerfQuality.level].particleScale
end

--- 当前是否启用冲击波
function PerfQuality.ShockwaveEnabled()
    return LEVELS[PerfQuality.level].shockwaveEnabled
end

--- 当前是否启用屏幕闪光
function PerfQuality.FlashEnabled()
    return LEVELS[PerfQuality.level].flashEnabled
end

--- 当前是否启用辉光/Bloom
function PerfQuality.GlowEnabled()
    return LEVELS[PerfQuality.level].glowEnabled
end

--- 获取所有档位标签（供 UI 遍历）
---@param lang string|nil  "zh" 或 "en"，默认 "zh"
---@return table  string[]
function PerfQuality.GetLabels(lang)
    local t = {}
    local key = (lang == "en") and "label_en" or "label_zh"
    for i, lv in ipairs(LEVELS) do
        t[i] = lv[key]
    end
    return t
end

return PerfQuality
