--- ============================================================================
--- 皮肤系统 - 角色 Emoji 外观替换（纯装饰，无属性加成）
--- 每角色 2 套替代皮肤，金币或广告解锁
--- ============================================================================

local SkinSystem = {}

-- ============================================================================
-- 皮肤定义（12个，每角色 2 套替代皮肤）
-- 每个皮肤完整覆盖 playerEmoji + bulletStyle
-- ============================================================================

SkinSystem.SKINS = {
    -- ────────── 小猫咪 ──────────
    {
        id       = "cat_shadow",
        charId   = "cat",
        name     = "暗影猫",
        icon     = "😼",
        price    = 800,
        adUnlock = true,
        playerEmoji = {
            idle = "🐱", move = "😼", hit = "😾",
            overload = "🙀", dead = "💀", shield = "😺",
        },
        bulletStyle = {
            normal   = { emoji = "🌙", color = {140,80,220},  trailColor = {120,60,200},  glowColor = {160,100,240,50}, size = 1.0 },
            pierce   = { emoji = "💜", color = {180,50,255},  trailColor = {160,30,240},  glowColor = {200,70,255,60},  size = 1.15 },
            spread   = { emoji = "🔮", color = {200,100,255}, trailColor = {180,80,240},  glowColor = {220,120,255,50}, size = 0.9 },
            ricochet = { emoji = "🌀", color = {100,50,200},  trailColor = {80,30,180},   glowColor = {120,70,220,60},  size = 1.1 },
        },
    },
    {
        id       = "cat_love",
        charId   = "cat",
        name     = "恋爱猫",
        icon     = "😻",
        price    = 1200,
        adUnlock = false,
        playerEmoji = {
            idle = "😻", move = "😽", hit = "😿",
            overload = "😸", dead = "🙀", shield = "😺",
        },
        bulletStyle = {
            normal   = { emoji = "💗", color = {255,100,150}, trailColor = {255,80,130},  glowColor = {255,120,170,50}, size = 1.0 },
            pierce   = { emoji = "💘", color = {255,50,100},  trailColor = {240,30,80},   glowColor = {255,70,120,60},  size = 1.15 },
            spread   = { emoji = "💕", color = {255,150,200}, trailColor = {255,130,180},  glowColor = {255,170,220,50}, size = 0.9 },
            ricochet = { emoji = "💝", color = {220,60,120},  trailColor = {200,40,100},  glowColor = {240,80,140,60},  size = 1.1 },
        },
    },

    -- ────────── 黄豆勇士 ──────────
    {
        id       = "bean_cool",
        charId   = "bean",
        name     = "墨镜豆",
        icon     = "😎",
        price    = 800,
        adUnlock = true,
        playerEmoji = {
            idle = "😎", move = "🤩", hit = "😵",
            overload = "🥳", dead = "💀", shield = "🤓",
        },
        bulletStyle = {
            normal   = { emoji = "🌟", color = {255,230,50},  trailColor = {255,210,30},  glowColor = {255,240,70,50},  size = 1.05 },
            pierce   = { emoji = "💥", color = {255,160,0},   trailColor = {255,140,0},   glowColor = {255,180,30,60},  size = 1.2 },
            spread   = { emoji = "🎆", color = {255,200,80},  trailColor = {255,180,60},  glowColor = {255,220,100,50}, size = 0.9 },
            ricochet = { emoji = "💣", color = {255,100,0},   trailColor = {240,80,0},    glowColor = {255,120,20,60},  size = 1.1 },
        },
    },
    {
        id       = "bean_chef",
        charId   = "bean",
        name     = "大厨豆",
        icon     = "🍳",
        price    = 1500,
        adUnlock = false,
        playerEmoji = {
            idle = "😋", move = "😄", hit = "🤢",
            overload = "🤤", dead = "🫠", shield = "😏",
        },
        bulletStyle = {
            normal   = { emoji = "🍳", color = {255,200,80},  trailColor = {240,180,60},  glowColor = {255,220,100,50}, size = 1.05 },
            pierce   = { emoji = "🔪", color = {200,200,210}, trailColor = {180,180,190}, glowColor = {220,220,230,60}, size = 1.2 },
            spread   = { emoji = "🍕", color = {255,180,50},  trailColor = {240,160,30},  glowColor = {255,200,70,50},  size = 0.9 },
            ricochet = { emoji = "🍖", color = {200,120,60},  trailColor = {180,100,40},  glowColor = {220,140,80,60},  size = 1.1 },
        },
    },

    -- ────────── 灵猴大圣 ──────────
    {
        id       = "monkey_fruit",
        charId   = "monkey",
        name     = "水果猴王",
        icon     = "🍌",
        price    = 1000,
        adUnlock = true,
        playerEmoji = {
            idle = "🍌", move = "🍑", hit = "🍋",
            overload = "🍊", dead = "🥝", shield = "🍎",
        },
        bulletStyle = {
            normal   = { emoji = "🍌", color = {255,220,80},  trailColor = {255,200,50},  glowColor = {255,240,100,50}, size = 0.95 },
            pierce   = { emoji = "🍍", color = {220,180,50},  trailColor = {200,160,30},  glowColor = {240,200,70,60},  size = 1.1 },
            spread   = { emoji = "🍒", color = {220,50,60},   trailColor = {200,30,40},   glowColor = {240,70,80,50},   size = 0.85 },
            ricochet = { emoji = "🥥", color = {180,140,100},  trailColor = {160,120,80},  glowColor = {200,160,120,60}, size = 1.05 },
        },
    },
    {
        id       = "monkey_cyber",
        charId   = "monkey",
        name     = "赛博猴",
        icon     = "🤖",
        price    = 1500,
        adUnlock = false,
        playerEmoji = {
            idle = "🤖", move = "🦾", hit = "🦿",
            overload = "🔋", dead = "💥", shield = "🔰",
        },
        bulletStyle = {
            normal   = { emoji = "⚡", color = {0,255,200},   trailColor = {0,240,180},   glowColor = {0,255,220,50},   size = 0.95 },
            pierce   = { emoji = "💠", color = {0,200,255},   trailColor = {0,180,240},   glowColor = {0,220,255,60},   size = 1.1 },
            spread   = { emoji = "🔷", color = {50,150,255},  trailColor = {30,130,240},  glowColor = {70,170,255,50},  size = 0.85 },
            ricochet = { emoji = "💿", color = {180,220,255}, trailColor = {160,200,240}, glowColor = {200,240,255,60}, size = 1.05 },
        },
    },

    -- ────────── 无敌巨掌 ──────────
    {
        id       = "hand_rock",
        charId   = "hand",
        name     = "摇滚之手",
        icon     = "🤘",
        price    = 800,
        adUnlock = true,
        playerEmoji = {
            idle = "🤘", move = "🤟", hit = "👎",
            overload = "🤙", dead = "✊", shield = "🤝",
        },
        bulletStyle = {
            normal   = { emoji = "🎸", color = {255,50,50},   trailColor = {240,30,30},   glowColor = {255,70,70,50},   size = 1.1 },
            pierce   = { emoji = "🔊", color = {255,100,0},   trailColor = {240,80,0},    glowColor = {255,120,20,60},  size = 1.25 },
            spread   = { emoji = "🎵", color = {255,80,180},  trailColor = {240,60,160},  glowColor = {255,100,200,50}, size = 0.95 },
            ricochet = { emoji = "🥁", color = {200,50,150},  trailColor = {180,30,130},  glowColor = {220,70,170,60},  size = 1.1 },
        },
    },
    {
        id       = "hand_magic",
        charId   = "hand",
        name     = "魔法之手",
        icon     = "🪄",
        price    = 1500,
        adUnlock = false,
        playerEmoji = {
            idle = "🖐️", move = "🤚", hit = "✋",
            overload = "👏", dead = "🫶", shield = "🤲",
        },
        bulletStyle = {
            normal   = { emoji = "✨", color = {180,120,255}, trailColor = {160,100,240}, glowColor = {200,140,255,50}, size = 1.1 },
            pierce   = { emoji = "🌈", color = {255,150,200}, trailColor = {240,130,180}, glowColor = {255,170,220,60}, size = 1.25 },
            spread   = { emoji = "💎", color = {100,200,255}, trailColor = {80,180,240},  glowColor = {120,220,255,50}, size = 0.95 },
            ricochet = { emoji = "🃏", color = {255,200,50},  trailColor = {240,180,30},  glowColor = {255,220,70,60},  size = 1.1 },
        },
    },

    -- ────────── 自然之灵 ──────────
    {
        id       = "leaf_sakura",
        charId   = "leaf",
        name     = "樱花之灵",
        icon     = "🌸",
        price    = 1000,
        adUnlock = true,
        playerEmoji = {
            idle = "🌸", move = "💮", hit = "🥀",
            overload = "🌺", dead = "🍂", shield = "🌷",
        },
        bulletStyle = {
            normal   = { emoji = "🌸", color = {255,150,180}, trailColor = {255,130,160}, glowColor = {255,170,200,50}, size = 1.0 },
            pierce   = { emoji = "🌺", color = {255,80,120},  trailColor = {240,60,100},  glowColor = {255,100,140,60}, size = 1.15 },
            spread   = { emoji = "💮", color = {255,200,220}, trailColor = {255,180,200}, glowColor = {255,220,240,50}, size = 0.9 },
            ricochet = { emoji = "🌷", color = {220,50,100},  trailColor = {200,30,80},   glowColor = {240,70,120,60},  size = 1.1 },
        },
    },
    {
        id       = "leaf_ice",
        charId   = "leaf",
        name     = "冰晶之叶",
        icon     = "❄️",
        price    = 1200,
        adUnlock = false,
        playerEmoji = {
            idle = "❄️", move = "🧊", hit = "💧",
            overload = "🌨️", dead = "💦", shield = "🌊",
        },
        bulletStyle = {
            normal   = { emoji = "❄️", color = {150,220,255}, trailColor = {130,200,240}, glowColor = {170,240,255,50}, size = 1.0 },
            pierce   = { emoji = "🧊", color = {100,180,255}, trailColor = {80,160,240},  glowColor = {120,200,255,60}, size = 1.15 },
            spread   = { emoji = "💎", color = {180,230,255}, trailColor = {160,210,240}, glowColor = {200,250,255,50}, size = 0.9 },
            ricochet = { emoji = "🌀", color = {80,200,255},  trailColor = {60,180,240},  glowColor = {100,220,255,60}, size = 1.1 },
        },
    },

    -- ────────── OTTO♿ ──────────
    {
        id       = "otto_golden",
        charId   = "otto",
        name     = "黄金战车",
        icon     = "🏆",
        price    = 1000,
        adUnlock = true,
        playerEmoji = {
            idle = "🏆", move = "🥇", hit = "🥈",
            overload = "👑", dead = "🥉", shield = "🎖️",
        },
        bulletStyle = {
            normal   = { emoji = "🪙", color = {255,210,50},  trailColor = {255,190,30},  glowColor = {255,230,70,50},  size = 1.0 },
            pierce   = { emoji = "⭐", color = {255,180,0},   trailColor = {240,160,0},   glowColor = {255,200,20,60},  size = 1.15 },
            spread   = { emoji = "✨", color = {255,240,100}, trailColor = {255,220,80},  glowColor = {255,255,120,50}, size = 0.9 },
            ricochet = { emoji = "💰", color = {255,200,50},  trailColor = {240,180,30},  glowColor = {255,220,70,60},  size = 1.1 },
        },
    },
    {
        id       = "otto_mecha",
        charId   = "otto",
        name     = "机甲OTTO",
        icon     = "🦿",
        price    = 2000,
        adUnlock = false,
        playerEmoji = {
            idle = "🦿", move = "🦾", hit = "⚙️",
            overload = "🔧", dead = "🔩", shield = "🛡️",
        },
        bulletStyle = {
            normal   = { emoji = "🚀", color = {100,200,255}, trailColor = {80,180,240},  glowColor = {120,220,255,50}, size = 1.0 },
            pierce   = { emoji = "💠", color = {50,150,255},  trailColor = {30,130,240},  glowColor = {70,170,255,60},  size = 1.15 },
            spread   = { emoji = "🔩", color = {180,190,200}, trailColor = {160,170,180}, glowColor = {200,210,220,50}, size = 0.9 },
            ricochet = { emoji = "⚙️", color = {150,160,180}, trailColor = {130,140,160}, glowColor = {170,180,200,60}, size = 1.1 },
        },
    },
}

-- ============================================================================
-- 索引表（模块加载时构建）
-- ============================================================================

--- skinId → 定义
SkinSystem._BY_ID = {}
--- charId → { skinDef, skinDef, ... }
SkinSystem._BY_CHAR = {}

for _, skin in ipairs(SkinSystem.SKINS) do
    SkinSystem._BY_ID[skin.id] = skin
    if not SkinSystem._BY_CHAR[skin.charId] then
        SkinSystem._BY_CHAR[skin.charId] = {}
    end
    table.insert(SkinSystem._BY_CHAR[skin.charId], skin)
end

-- ============================================================================
-- 查询函数
-- ============================================================================

--- 根据 skinId 获取皮肤定义
---@param skinId string
---@return table|nil
function SkinSystem.GetSkin(skinId)
    return SkinSystem._BY_ID[skinId]
end

--- 获取指定角色的所有可用皮肤
---@param charId string
---@return table[] 皮肤定义数组（不含默认皮肤）
function SkinSystem.GetSkinsForChar(charId)
    return SkinSystem._BY_CHAR[charId] or {}
end

--- 获取所有皮肤
---@return table[]
function SkinSystem.GetAllSkins()
    return SkinSystem.SKINS
end

--- 获取皮肤总数
---@return number
function SkinSystem.GetTotalCount()
    return #SkinSystem.SKINS
end

--- 统计已拥有的皮肤数
---@param ownedSkins table { [skinId]=true }
---@return number
function SkinSystem.GetOwnedCount(ownedSkins)
    local count = 0
    for _ in pairs(ownedSkins or {}) do
        count = count + 1
    end
    return count
end

return SkinSystem
