--- ============================================================================
--- emoji 英雄战斗 - 数值配置表
--- ============================================================================

local Config = {}

-- 设计分辨率（竖屏）
Config.DESIGN_W = 720
Config.DESIGN_H = 1280

-- 游戏世界（设计像素坐标系）
Config.WORLD_SIZE = 12000 -- 游戏世界大小（正方形，面积9倍）

-- 赛博朋克配色
Config.COLORS = {
    bg           = { 10, 8, 25, 255 },       -- 深暗紫背景
    bgGrid       = { 30, 20, 60, 80 },       -- 背景网格
    neonBlue     = { 0, 200, 255, 255 },     -- 霓虹蓝
    neonPurple   = { 180, 50, 255, 255 },    -- 霓虹紫
    neonPink     = { 255, 50, 150, 255 },    -- 霓虹粉
    neonGreen    = { 0, 255, 150, 255 },     -- 霓虹绿
    neonOrange   = { 255, 150, 0, 255 },     -- 霓虹橙
    neonRed      = { 255, 50, 50, 255 },     -- 霓虹红
    neonYellow   = { 255, 255, 50, 255 },    -- 霓虹黄
    neonCyan     = { 0, 255, 255, 255 },     -- 霓虹青
    white        = { 255, 255, 255, 255 },
    hpBar        = { 50, 255, 100, 255 },    -- 血条绿
    hpBarBg      = { 40, 20, 20, 200 },      -- 血条背景
    expBar       = { 100, 150, 255, 255 },   -- 经验条蓝
    overloadBar  = { 255, 150, 0, 255 },     -- 过载条橙
    playerBody   = { 0, 200, 255, 255 },     -- 玩家主体
    playerGlow   = { 0, 200, 255, 60 },      -- 玩家光晕
    enemyNormal  = { 255, 50, 50, 255 },     -- 普通敌人
    enemyElite   = { 255, 150, 0, 255 },     -- 精英敌人
    enemyBoss    = { 255, 50, 150, 255 },    -- BOSS
    bullet       = { 0, 255, 200, 255 },     -- 子弹
    xpChip       = { 100, 255, 100, 255 },   -- 经验芯片
    skillBg      = { 20, 15, 40, 240 },      -- 技能面板背景
}

-- 玩家属性
Config.PLAYER = {
    radius = 18,                 -- 玩家半径（设计像素）
    baseHp = 35,
    baseAtk = 6,
    baseSpeed = 280,             -- 像素/秒
    baseCritRate = 0.05,         -- 5% 暴击率
    critDamage = 2.0,            -- 暴击伤害倍率
    attackInterval = 0.5,        -- 自动攻击间隔（秒）
    attackRange = 350,           -- 攻击范围（像素）
    magnetRange = 80,            -- 磁吸拾取范围
    invincibleTime = 0.8,       -- 受击无敌时间（加长）
}

-- 子弹属性
Config.BULLET = {
    speed = 600,                 -- 子弹速度（像素/秒）
    radius = 9,                  -- 子弹半径
    lifetime = 1.5,              -- 子弹存活时间
}

-- 掉落物
Config.LOOT = {
    radius = 6,
    magnetSpeed = 500,           -- 磁吸速度
    baseExp = 2,                 -- 基础经验值
    -- 特殊掉落概率（敌人死亡时随机判定）
    heartChance = 0.04,          -- 4% 掉红心（回复生命）
    magnetChance = 0.03,         -- 3% 掉磁铁（临时扩大磁吸范围）
    bombChance = 0.012,          -- 1.2% 掉炸弹（全屏清怪，Boss免疫）
    coinChance = 0.36,           -- 36% 掉金币（额外经验）
}

-- 特殊掉落物配置
Config.SPECIAL_LOOT = {
    heart  = { emoji = "❤️",  radius = 10, healPercent = 0.15 },           -- 回复15%最大生命
    magnet = { emoji = "🧲", radius = 10, duration = 5.0, range = 400 },  -- 5秒超大磁吸
    bomb   = { emoji = "💣", radius = 12, damage = 999 },                 -- 全屏清怪
    coin   = { emoji = "🪙", radius = 8,  expMulti = 3, goldValue = 1 },  -- 3倍经验芯片 + 1局外金币
    gift   = { emoji = "🎁", radius = 14 },                               -- 广告礼物盒
}

-- 礼物盒（广告激励）
Config.GIFT_BOX = {
    dropChance = 0.008,          -- 0.8% 极低掉率
    waveCooldown = 5,            -- 每5波最多掉落1个
    adExpReward = 200,           -- 看广告基础经验值
    adExpPerWave = 20,           -- 看广告每波额外经验（实际=base+wave×perWave）
    giveUpExpReward = 20,        -- 放弃基础经验值
    giveUpExpPerWave = 2,        -- 放弃每波额外经验（实际=base+wave×perWave）
}

-- 升级经验公式: 等级 × 20
Config.LEVEL = {
    maxLevel = 9999,  -- 无上限
    expFormula = function(level) return level * 20 end,
    hpGrowth = 0.03,             -- 每级生命 +3%
    atkGrowth = 0.03,            -- 每级攻击 +3%
    critGrowth = 0.002,          -- 每级暴击率 +0.2%
}

-- 过载系统
Config.OVERLOAD = {
    killsToFull = 100,           -- 击杀100只满过载
    duration = 5.0,              -- 过载持续5秒
    atkMultiplier = 2.0,         -- 攻击翻倍
    speedBonus = 0.3,            -- 移速+30%
    cooldownReduction = 0.5,     -- 冷却减半
}

-- 毕业Build系统
Config.GRADUATION = {
    DRONE_COLLISION_DMG = 2,           -- 无人机碰撞基础伤害
    DRONE_COLLISION_TICK = 0.25,       -- 碰撞检测间隔（秒）
    DRONE_MAX_LEVEL_GRAD = 6,          -- 毕业后无人机上限（3→6）
    MAX3_UPGRADED = 4,                 -- 毕业后上限3→4
    MAX5_UPGRADED = 7,                 -- 毕业后上限5→7
    ULTIMATE_HEAL_INV_TIME = 10.0,     -- 终极选项A：无敌时间
    ULTIMATE_RAGE_TIME = 20.0,         -- 终极选项B：狂暴时间
    ULTIMATE_RAGE_ATK_MULT = 3.0,      -- 终极选项B：攻击倍率
}

-- 毕业解锁：跨角色射弹加成类技能
Config.GRADUATION_WEAPON_SKILLS = { "multi_shot", "piercing", "combo_hit", "palm_wave", "leaf_pierce", "leaf_homing" }
-- 毕业解锁：跨角色有CD触发的技能（真专属技能不在此列表：cat_scratch/shield/thumb_up/clone_strike/leaf_storm/elephant_stomp）
Config.GRADUATION_CD_SKILLS = { "grenade", "bean_sprout", "grab_smash", "xmas_tree", "charm_enemy", "slow_rider", "otto_box", "otto_sprint" }

-- 难度预设
Config.DIFFICULTY = {
    {
        id = "easy",   name = "简单", icon = "🟢", desc = "敌人较弱，适合新手",
        enemyHpMult = 0.7, enemyAtkMult = 0.6, enemySpeedMult = 0.9,
        spawnMult = 0.8, expMult = 1.3, goldMult = 1.2,
        scoreWeight = 0.5,  -- 排行榜分数系数
    },
    {
        id = "normal", name = "普通", icon = "🟡", desc = "标准难度，均衡体验",
        enemyHpMult = 1.0, enemyAtkMult = 1.0, enemySpeedMult = 1.0,
        spawnMult = 1.0, expMult = 1.0, goldMult = 1.0,
        scoreWeight = 1.0,
    },
    {
        id = "hard",   name = "困难", icon = "🔴", desc = "敌人凶猛，经验丰富",
        enemyHpMult = 1.5, enemyAtkMult = 1.4, enemySpeedMult = 1.15,
        spawnMult = 1.3, expMult = 0.8, goldMult = 1.5,
        scoreWeight = 1.8,
    },
    {
        id = "nightmare", name = "噩梦", icon = "💀", desc = "极限挑战，噩梦降临",
        enemyHpMult = 2.2, enemyAtkMult = 2.0, enemySpeedMult = 1.3,
        spawnMult = 1.6, expMult = 0.6, goldMult = 2.0,
        scoreWeight = 3.0,
    },
}
Config.currentDiffIdx = 2  -- 默认"普通"（1-based索引）

--- 获取当前难度配置
function Config.GetDifficulty()
    return Config.DIFFICULTY[Config.currentDiffIdx] or Config.DIFFICULTY[2]
end

-- 波次系统
Config.WAVE = {
    interval = 30,               -- 每30秒一波
    baseEnemyCount = 5,          -- 初始每波5只
    countGrowth = 2,             -- 每波多2只
    maxEnemiesAlive = 60,        -- 同屏最大敌人数
    coeffGrowth = 0.08,          -- 每波系数增长8%
    spawnRadius = 700,           -- 敌人在玩家周围多远生成
    spawnMinRadius = 500,        -- 最小生成距离
    bossInterval = 10,           -- 每10波出Boss
}

-- ============================================================================
-- 角色定义
-- ============================================================================

--- 角色列表
Config.CHARACTERS = {
    {
        id = "cat",
        name = "小猫咪",
        desc = "灵敏敏捷，弹幕高手",
        emoji = "😺",           -- 选人界面展示用
        color = { 0, 200, 255 },   -- 主题色：青蓝
        -- 基础属性倍率（相对于 Config.PLAYER 的乘数）
        stats = {
            hp = 0.9,           -- 血量略低
            atk = 1.0,
            speed = 1.1,        -- 移速较快
            critRate = 1.2,     -- 暴击率较高
        },
        -- 角色专属技能 ID
        exclusiveSkills = { "multi_shot", "piercing", "crit_up", "fire_rate", "cat_scratch" },
        signatureSkill  = "cat_scratch",   -- 真专属：跨角色符文不能授予此技能
        -- 子弹风格
        bulletStyle = {
            normal   = { emoji = "🐟", color = { 0, 230, 200 },   trailColor = { 0, 230, 200 },   glowColor = { 0, 255, 220, 50 },  size = 1.0 },
            pierce   = { emoji = "⭐", color = { 200, 120, 255 }, trailColor = { 180, 80, 255 },  glowColor = { 200, 100, 255, 60 }, size = 1.15 },
            spread   = { emoji = "💫", color = { 255, 140, 200 }, trailColor = { 255, 100, 180 }, glowColor = { 255, 150, 200, 50 }, size = 0.9 },
            ricochet = { emoji = "🐳", color = { 0, 200, 255 },   trailColor = { 0, 180, 255 },   glowColor = { 0, 220, 255, 60 },  size = 1.1 },
        },
        -- 状态 emoji
        playerEmoji = {
            idle = "😺", move = "😸", hit  = "🙀",
            overload = "😼", dead = "😿", shield = "😻",
        },
        -- 游戏结束文案
        deathText = "小猫倒下了",
        deathSub  = "下次一定能行喵！",
        victoryText = "大获全胜！",
        victorySub  = "BOSS已被小猫击败喵~",
        restartText = "再来一局喵~",
    },
    {
        id = "bean",
        name = "黄豆勇士",
        desc = "生命顽强，爆炸专家",
        emoji = "😆",
        color = { 255, 210, 50 },  -- 主题色：金黄
        stats = {
            hp = 1.3,           -- 血量较高
            atk = 1.1,          -- 攻击略高
            speed = 0.9,        -- 移速较慢
            critRate = 0.8,     -- 暴击率较低
        },
        exclusiveSkills = { "grenade", "shield", "hp_up", "hp_regen", "bean_sprout" },
        signatureSkill  = "bean_sprout",
        bulletStyle = {
            normal   = { emoji = "🫘", color = { 255, 210, 50 },  trailColor = { 255, 200, 40 },  glowColor = { 255, 220, 60, 50 },  size = 1.05 },
            pierce   = { emoji = "🌟", color = { 255, 160, 30 },  trailColor = { 255, 140, 0 },   glowColor = { 255, 180, 50, 60 },  size = 1.2 },
            spread   = { emoji = "✨", color = { 255, 240, 120 }, trailColor = { 255, 220, 80 },  glowColor = { 255, 240, 130, 50 }, size = 0.9 },
            ricochet = { emoji = "🧨", color = { 255, 180, 0 },   trailColor = { 255, 160, 0 },   glowColor = { 255, 200, 30, 60 },  size = 1.1 },
        },
        playerEmoji = {
            idle = "😆", move = "😄", hit  = "😵",
            overload = "🤩", dead = "💀", shield = "😎",
        },
        deathText = "黄豆碎了",
        deathSub  = "下次再战！豆力全开！",
        victoryText = "豆气冲天！",
        victorySub  = "BOSS被黄豆碾碎啦！",
        restartText = "再豆一局！",
    },
    -- ---------- 角色3：猴子 ----------
    {
        id = "monkey",
        name = "灵猴大圣",
        desc = "极速连击，闪避大师",
        emoji = "🐵",
        color = { 255, 140, 50 },   -- 主题色：橙色
        stats = {
            hp = 0.8,           -- 血量较低
            atk = 0.9,          -- 攻击略低
            speed = 1.35,       -- 移速最快
            critRate = 1.0,
        },
        exclusiveSkills = { "combo_hit", "dodge_roll", "clone_strike", "speed_burst", "big_bullet" },
        signatureSkill  = "clone_strike",
        bulletStyle = {
            normal   = { emoji = "🍌", color = { 255, 200, 50 },  trailColor = { 255, 180, 30 },  glowColor = { 255, 210, 60, 50 },  size = 0.95 },
            pierce   = { emoji = "🔥", color = { 255, 100, 20 },  trailColor = { 255, 80, 0 },    glowColor = { 255, 120, 30, 60 },  size = 1.1 },
            spread   = { emoji = "🍿", color = { 255, 220, 150 }, trailColor = { 255, 200, 120 }, glowColor = { 255, 230, 160, 50 }, size = 0.85 },
            ricochet = { emoji = "📣", color = { 255, 140, 0 },   trailColor = { 255, 120, 0 },   glowColor = { 255, 160, 20, 60 },  size = 1.05 },
        },
        playerEmoji = {
            idle = "🐵", move = "🐒", hit  = "🙈",
            overload = "🙉", dead = "🙊", shield = "🐵",
        },
        deathText = "猴子摔下来了",
        deathSub  = "大圣还会归来！",
        victoryText = "齐天大胜！",
        victorySub  = "BOSS被猴哥一棒打飞！",
        restartText = "再战一回合！",
    },
    -- ---------- 角色4：手 ----------
    {
        id = "hand",
        name = "无敌巨掌",
        desc = "力大无穷，范围碾压",
        emoji = "🤚",
        color = { 220, 80, 220 },  -- 主题色：紫粉
        stats = {
            hp = 1.1,           -- 血量较高
            atk = 1.3,          -- 攻击最高
            speed = 0.8,        -- 移速最慢
            critRate = 0.9,
        },
        exclusiveSkills = { "palm_wave", "grab_smash", "finger_flick", "iron_fist", "thumb_up" },
        signatureSkill  = "thumb_up",
        bulletStyle = {
            normal   = { emoji = "👊", color = { 220, 100, 220 }, trailColor = { 200, 80, 200 },  glowColor = { 230, 110, 230, 50 }, size = 1.1 },
            pierce   = { emoji = "🫴", color = { 255, 60, 180 },  trailColor = { 240, 40, 160 },  glowColor = { 255, 80, 200, 60 },  size = 1.25 },
            spread   = { emoji = "✋", color = { 200, 150, 255 }, trailColor = { 180, 130, 240 }, glowColor = { 210, 160, 255, 50 }, size = 0.95 },
            ricochet = { emoji = "🤘", color = { 180, 80, 255 },  trailColor = { 160, 60, 240 },  glowColor = { 190, 100, 255, 60 }, size = 1.1 },
        },
        playerEmoji = {
            idle = "🤚", move = "✊", hit  = "✌",
            overload = "👋", dead = "👌", shield = "🤞",
        },
        deathText = "巨掌倒下了",
        deathSub  = "下次用更大的力量！",
        victoryText = "一掌定乾坤！",
        victorySub  = "BOSS被拍成肉饼啦！",
        restartText = "再拍一局！",
    },
    -- ---------- 角色5：叶子 ----------
    {
        id = "leaf",
        name = "自然之灵",
        desc = "冰霜控制，自然之力",
        emoji = "🍃",
        color = { 60, 200, 80 },   -- 主题色：自然绿
        stats = {
            hp = 1.0,
            atk = 0.95,
            speed = 1.05,
            critRate = 1.0,
        },
        exclusiveSkills = { "leaf_pierce", "leaf_homing", "xmas_tree", "clover_luck", "leaf_storm" },
        signatureSkill  = "leaf_storm",
        bulletStyle = {
            normal   = { emoji = "🍃", color = { 60, 200, 80 },   trailColor = { 40, 180, 60 },   glowColor = { 80, 220, 100, 50 }, size = 1.0 },
            pierce   = { emoji = "🌿", color = { 30, 160, 60 },   trailColor = { 20, 140, 40 },   glowColor = { 50, 180, 80, 60 },  size = 1.15 },
            spread   = { emoji = "🍂", color = { 200, 150, 50 },  trailColor = { 180, 130, 30 },  glowColor = { 220, 170, 70, 50 }, size = 0.9 },
            ricochet = { emoji = "🍁", color = { 220, 100, 40 },  trailColor = { 200, 80, 20 },   glowColor = { 240, 120, 60, 60 }, size = 1.1 },
        },
        playerEmoji = {
            idle = "🍃", move = "🌿", hit  = "🍂",
            overload = "🌸", dead = "🥀", shield = "🍀",
        },
        deathText = "叶子枯萎了",
        deathSub  = "春风吹又生！",
        victoryText = "万物复苏！",
        victorySub  = "BOSS被自然之力净化啦！",
        restartText = "再绽放一次！",
    },
    -- ---------- 角色6：OTTO♿ 召唤师 ----------
    {
        id = "otto",
        name = "OTTO♿",
        desc = "召唤大军，以众克敌",
        emoji = "♿",
        color = { 100, 180, 255 },   -- 主题色：天蓝
        stats = {
            hp = 1.2,           -- 血量较高（坐轮椅需要肉）
            atk = 0.85,         -- 攻击较低（靠召唤物输出）
            speed = 0.85,       -- 移速较慢
            critRate = 0.9,
        },
        exclusiveSkills = { "elephant_stomp", "charm_enemy", "slow_rider", "otto_box", "otto_sprint" },
        signatureSkill  = "otto_box",
        bulletStyle = {
            normal   = { emoji = "💫", color = { 100, 180, 255 }, trailColor = { 80, 160, 240 },  glowColor = { 120, 200, 255, 50 }, size = 1.0 },
            pierce   = { emoji = "⚡", color = { 0, 200, 255 },   trailColor = { 0, 180, 240 },   glowColor = { 0, 220, 255, 60 },  size = 1.15 },
            spread   = { emoji = "✨", color = { 180, 140, 255 }, trailColor = { 160, 120, 240 }, glowColor = { 200, 160, 255, 50 }, size = 0.9 },
            ricochet = { emoji = "🥟", color = { 60, 200, 80 },   trailColor = { 40, 180, 60 },   glowColor = { 80, 220, 100, 60 }, size = 1.1 },
        },
        playerEmoji = {
            idle = "♿", move = "🔄", hit  = "⛔",
            overload = "🔆", dead = "🚫", shield = "🔰",
        },
        deathText = "OTTO倒下了",
        deathSub  = "召唤师永不言败！",
        victoryText = "召唤大胜！",
        victorySub  = "BOSS被大军碾碎啦！",
        restartText = "再召一局！",
    },
}

--- 通过 ID 查找技能定义
function Config.FindSkill(skillId)
    for _, s in ipairs(Config.SKILLS) do
        if s.id == skillId then return s end
    end
    return nil
end

--- 通过 ID 查找角色定义
function Config.GetCharacter(charId)
    for _, ch in ipairs(Config.CHARACTERS) do
        if ch.id == charId then return ch end
    end
    return Config.CHARACTERS[1]  -- 默认小猫
end

-- ============================================================================
-- Boss 定义：7 个职业系列 Boss
-- 每 10 波出现一个，按顺序轮换
-- 每个 Boss 有 3 个技能，其中一个是大招（使用后自眩晕 5 秒）
-- Boss 无接触伤害，仅通过技能造成伤害
-- ============================================================================
Config.BOSSES = {
    -- Boss 1: 警察（波次 10）
    {
        id = "police",
        name = "巡逻警官",
        emoji = "👮‍♀️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 60, 120, 255 },     -- 警蓝色
        skills = {
            -- 技能1: 警笛弹幕 —— 向玩家扇形射击 5 发子弹
            {
                name = "警笛弹幕",
                icon = "🚨",
                interval = 3.0,
                type = "shoot_fan",
                bulletCount = 5,
                bulletSpeed = 260,
                damage = 8,
                spreadAngle = 0.8,     -- 扇形角度（弧度）
            },
            -- 技能2: 追击封锁 —— 向玩家连续射出 3 发追踪弹
            {
                name = "追击封锁",
                icon = "🔒",
                interval = 5.0,
                type = "shoot_burst",
                bulletCount = 3,
                bulletSpeed = 220,
                damage = 6,
                burstDelay = 0.2,
            },
            -- 技能3 (大招): 全域通缉 —— 360° 散射 16 发，使用后眩晕 5 秒
            {
                name = "全域通缉",
                icon = "⚠️",
                interval = 12.0,
                type = "shoot_radial",
                bulletCount = 16,
                bulletSpeed = 200,
                damage = 12,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 2: 工人（波次 20）
    {
        id = "worker",
        name = "重装工头",
        emoji = "👷‍♂️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 255, 180, 30 },     -- 工程黄
        skills = {
            -- 技能1: 砖块投掷 —— 向玩家丢 1 个慢速大范围砖块
            {
                name = "砖块投掷",
                icon = "🧱",
                interval = 2.5,
                type = "shoot_target",
                bulletCount = 1,
                bulletSpeed = 180,
                damage = 10,
                bulletRadius = 12,
            },
            -- 技能2: 钻头冲刺 —— 短距离冲向玩家
            {
                name = "钻头冲刺",
                icon = "⛏️",
                interval = 6.0,
                type = "dash",
                dashSpeed = 400,
                dashDuration = 0.5,
                damage = 15,
                dashRadius = 50,
            },
            -- 技能3 (大招): 建筑崩塌 —— 在周围随机落下 12 个碎石
            {
                name = "建筑崩塌",
                icon = "🏗️",
                interval = 14.0,
                type = "area_rain",
                count = 12,
                damage = 14,
                radius = 35,
                spawnRange = 250,
                fallDuration = 0.8,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 3: 厨师（波次 30）
    {
        id = "chef",
        name = "地狱厨神",
        emoji = "👨‍🍳",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 255, 100, 50 },     -- 火焰橙
        skills = {
            -- 技能1: 飞刀投射 —— 快速向玩家射 2 发飞刀
            {
                name = "飞刀投射",
                icon = "🔪",
                interval = 2.0,
                type = "shoot_burst",
                bulletCount = 2,
                bulletSpeed = 320,
                damage = 7,
                burstDelay = 0.15,
            },
            -- 技能2: 火焰喷射 —— 扇形近距离火焰
            {
                name = "火焰喷射",
                icon = "🔥",
                interval = 5.0,
                type = "shoot_fan",
                bulletCount = 8,
                bulletSpeed = 240,
                damage = 5,
                spreadAngle = 1.2,
            },
            -- 技能3 (大招): 致命料理 —— 放出大锅，在自身周围创建毒圈持续伤害
            {
                name = "致命料理",
                icon = "🍳",
                interval = 13.0,
                type = "area_circle",
                damage = 4,
                radius = 150,
                duration = 3.0,
                tickInterval = 0.5,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 4: 程序员（波次 40）
    {
        id = "programmer",
        name = "代码狂魔",
        emoji = "👨‍💻",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 0, 220, 180 },      -- 终端绿
        skills = {
            -- 技能1: Bug 弹幕 —— 向玩家射出 3 发散射 Bug
            {
                name = "Bug弹幕",
                icon = "🐛",
                interval = 2.5,
                type = "shoot_fan",
                bulletCount = 3,
                bulletSpeed = 280,
                damage = 9,
                spreadAngle = 0.5,
            },
            -- 技能2: 递归炸弹 —— 发射 1 颗炸弹，落地后分裂成 4 颗小弹
            {
                name = "递归炸弹",
                icon = "💥",
                interval = 6.0,
                type = "shoot_split",
                bulletSpeed = 200,
                damage = 8,
                splitCount = 4,
                splitSpeed = 220,
                splitDamage = 5,
            },
            -- 技能3 (大招): 蓝屏死机 —— 全屏 16 发 + 随机 8 发散射
            {
                name = "蓝屏死机",
                icon = "💻",
                interval = 15.0,
                type = "shoot_radial",
                bulletCount = 24,
                bulletSpeed = 180,
                damage = 11,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 5: 消防员（波次 50）
    {
        id = "firefighter",
        name = "烈焰战士",
        emoji = "👨‍🚒",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 255, 60, 30 },      -- 消防红
        skills = {
            -- 技能1: 水枪喷射 —— 连续射出 4 发直线水弹
            {
                name = "水枪喷射",
                icon = "🚿",
                interval = 2.0,
                type = "shoot_burst",
                bulletCount = 4,
                bulletSpeed = 300,
                damage = 7,
                burstDelay = 0.12,
            },
            -- 技能2: 消防斧冲击 —— 冲刺攻击
            {
                name = "消防斧冲击",
                icon = "🪓",
                interval = 5.5,
                type = "dash",
                dashSpeed = 450,
                dashDuration = 0.4,
                damage = 18,
                dashRadius = 45,
            },
            -- 技能3 (大招): 灭世大火 —— 在周围落下 15 个火球
            {
                name = "灭世大火",
                icon = "☄️",
                interval = 14.0,
                type = "area_rain",
                count = 15,
                damage = 13,
                radius = 30,
                spawnRange = 280,
                fallDuration = 0.7,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 6: 吸血鬼（波次 60）
    {
        id = "vampire",
        name = "暗夜伯爵",
        emoji = "🧛‍♀️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 180, 30, 80 },      -- 暗红
        skills = {
            -- 技能1: 蝙蝠群 —— 扇形发射 6 颗蝙蝠弹
            {
                name = "蝙蝠群",
                icon = "🦇",
                interval = 2.5,
                type = "shoot_fan",
                bulletCount = 6,
                bulletSpeed = 260,
                damage = 9,
                spreadAngle = 1.0,
            },
            -- 技能2: 暗影传送 —— 瞬移到玩家附近并释放近距离弹幕
            {
                name = "暗影传送",
                icon = "🌑",
                interval = 6.0,
                type = "blink_attack",
                blinkRange = 160,
                bulletCount = 8,
                bulletSpeed = 200,
                damage = 7,
            },
            -- 技能3 (大招): 鲜血狂宴 —— 360° 散射 20 发 + 吸血回复
            {
                name = "鲜血狂宴",
                icon = "🩸",
                interval = 13.0,
                type = "shoot_radial",
                bulletCount = 20,
                bulletSpeed = 190,
                damage = 10,
                healPercent = 0.05,    -- 释放后回复 5% 血量
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 7: 绅士（波次 70）
    {
        id = "gentleman",
        name = "暗影绅士",
        emoji = "🤵‍♂️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 120, 80, 200 },     -- 贵族紫
        skills = {
            -- 技能1: 扑克飞弹 —— 向玩家精准射出 3 发高速扑克牌
            {
                name = "扑克飞弹",
                icon = "🃏",
                interval = 2.0,
                type = "shoot_burst",
                bulletCount = 3,
                bulletSpeed = 340,
                damage = 10,
                burstDelay = 0.1,
            },
            -- 技能2: 魔术消失 —— 传送后在原地留下 4 发弹幕
            {
                name = "魔术消失",
                icon = "🎩",
                interval = 5.5,
                type = "blink_attack",
                blinkRange = 160,
                bulletCount = 4,
                bulletSpeed = 220,
                damage = 8,
            },
            -- 技能3 (大招): 终极礼花 —— 多波次散射 (3波 × 12发)
            {
                name = "终极礼花",
                icon = "🎆",
                interval = 14.0,
                type = "shoot_radial",
                bulletCount = 36,
                bulletSpeed = 170,
                damage = 9,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 8: 科学家（波次 80）
    {
        id = "scientist",
        name = "疯狂博士",
        emoji = "🧑‍🔬",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 0, 255, 150 },      -- 辐射绿
        skills = {
            -- 技能1: 试管投射 —— 向玩家连续射出 3 发毒液弹
            {
                name = "试管投射",
                icon = "🧪",
                interval = 2.5,
                type = "shoot_burst",
                bulletCount = 3,
                bulletSpeed = 290,
                damage = 11,
                burstDelay = 0.18,
            },
            -- 技能2: 基因裂变 —— 发射 1 颗大弹，落地分裂成 6 颗小弹
            {
                name = "基因裂变",
                icon = "🧬",
                interval = 5.5,
                type = "shoot_split",
                bulletSpeed = 210,
                damage = 10,
                splitCount = 6,
                splitSpeed = 240,
                splitDamage = 6,
            },
            -- 技能3 (大招): 核聚变 —— 自身周围毒圈 + 360° 散射 28 发
            {
                name = "核聚变",
                icon = "☢️",
                interval = 15.0,
                type = "shoot_radial",
                bulletCount = 28,
                bulletSpeed = 190,
                damage = 12,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 9: 海盗船长（波次 90）
    {
        id = "pirate",
        name = "深海船长",
        emoji = "🏴‍☠️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 50, 100, 180 },     -- 深海蓝
        skills = {
            -- 技能1: 加农炮 —— 扇形射出 7 发炮弹
            {
                name = "加农炮",
                icon = "💣",
                interval = 3.0,
                type = "shoot_fan",
                bulletCount = 7,
                bulletSpeed = 240,
                damage = 10,
                spreadAngle = 1.0,
            },
            -- 技能2: 船锚冲击 —— 高速冲向玩家
            {
                name = "船锚冲击",
                icon = "⚓",
                interval = 6.0,
                type = "dash",
                dashSpeed = 480,
                dashDuration = 0.5,
                damage = 20,
                dashRadius = 55,
            },
            -- 技能3 (大招): 暴风骤雨 —— 在玩家周围落下 18 个炮弹
            {
                name = "暴风骤雨",
                icon = "🌊",
                interval = 14.0,
                type = "area_rain",
                count = 18,
                damage = 14,
                radius = 35,
                spawnRange = 300,
                fallDuration = 0.7,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 10: DJ（波次 100）
    {
        id = "dj",
        name = "电音狂魔",
        emoji = "🎧",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 255, 50, 255 },     -- 荧光紫
        skills = {
            -- 技能1: 音波冲击 —— 向玩家扇形射出 5 发高速音符
            {
                name = "音波冲击",
                icon = "🎵",
                interval = 2.0,
                type = "shoot_fan",
                bulletCount = 5,
                bulletSpeed = 320,
                damage = 10,
                spreadAngle = 0.6,
            },
            -- 技能2: 低音重炮 —— 传送到玩家附近并释放环形弹幕
            {
                name = "低音重炮",
                icon = "🔊",
                interval = 5.5,
                type = "blink_attack",
                blinkRange = 170,
                bulletCount = 10,
                bulletSpeed = 220,
                damage = 8,
            },
            -- 技能3 (大招): 终极混音 —— 360° 散射 32 发 + 持续音波圈
            {
                name = "终极混音",
                icon = "🎶",
                interval = 13.0,
                type = "shoot_radial",
                bulletCount = 32,
                bulletSpeed = 200,
                damage = 11,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 11: 外科医生（波次 110）
    {
        id = "doctor",
        name = "暗黑医师",
        emoji = "👨‍⚕️",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 200, 255, 200 },    -- 医疗绿
        skills = {
            -- 技能1: 注射针 —— 向玩家连射 4 发毒针
            {
                name = "注射针",
                icon = "💉",
                interval = 2.5,
                type = "shoot_burst",
                bulletCount = 4,
                bulletSpeed = 300,
                damage = 9,
                burstDelay = 0.12,
            },
            -- 技能2: 瘟疫扩散 —— 在自身周围制造持续毒圈
            {
                name = "瘟疫扩散",
                icon = "🦠",
                interval = 7.0,
                type = "area_circle",
                damage = 5,
                radius = 160,
                duration = 3.5,
                tickInterval = 0.5,
                isUltimate = false,
            },
            -- 技能3 (大招): 起死回生 —— 360° 散射 24 发 + 回复 8% 血量
            {
                name = "起死回生",
                icon = "🏥",
                interval = 14.0,
                type = "shoot_radial",
                bulletCount = 24,
                bulletSpeed = 180,
                damage = 10,
                healPercent = 0.08,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 12: 忍者（波次 120）
    {
        id = "ninja",
        name = "暗影忍者",
        emoji = "🥷",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 80, 30, 120 },      -- 暗紫
        skills = {
            -- 技能1: 手里剑 —— 扇形射出 4 发高速飞镖
            {
                name = "手里剑",
                icon = "🌀",
                interval = 1.8,
                type = "shoot_fan",
                bulletCount = 4,
                bulletSpeed = 360,
                damage = 9,
                spreadAngle = 0.5,
            },
            -- 技能2: 影分身 —— 连续传送 2 次，每次留下一圈弹幕
            {
                name = "影分身",
                icon = "💨",
                interval = 5.0,
                type = "blink_attack",
                blinkRange = 160,
                bulletCount = 6,
                bulletSpeed = 250,
                damage = 7,
            },
            -- 技能3 (大招): 千本樱 —— 落下 20 朵致命樱花
            {
                name = "千本樱",
                icon = "🌸",
                interval = 13.0,
                type = "area_rain",
                count = 20,
                damage = 13,
                radius = 28,
                spawnRange = 260,
                fallDuration = 0.6,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 13: 机器人（波次 130）
    {
        id = "robot",
        name = "歼灭者T-X",
        emoji = "🤖",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 200, 200, 220 },    -- 钢铁银
        skills = {
            -- 技能1: 激光扫射 —— 向玩家连续射出 5 发激光
            {
                name = "激光扫射",
                icon = "⚡",
                interval = 2.0,
                type = "shoot_burst",
                bulletCount = 5,
                bulletSpeed = 350,
                damage = 8,
                burstDelay = 0.1,
            },
            -- 技能2: 火箭弹 —— 发射 1 颗火箭弹，落地分裂成 8 颗碎片
            {
                name = "火箭弹",
                icon = "🚀",
                interval = 6.0,
                type = "shoot_split",
                bulletSpeed = 220,
                damage = 12,
                splitCount = 8,
                splitSpeed = 260,
                splitDamage = 7,
            },
            -- 技能3 (大招): 终极歼灭 —— 360° 散射 40 发
            {
                name = "终极歼灭",
                icon = "💥",
                interval = 15.0,
                type = "shoot_radial",
                bulletCount = 40,
                bulletSpeed = 210,
                damage = 13,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
    -- Boss 14: 魔王（波次 140）—— 终极 Boss
    {
        id = "demon_king",
        name = "深渊魔王",
        emoji = "👿",
        radius = 36,
        baseHp = 2000,
        speed = 75,
        expDrop = 100,
        color = { 200, 20, 20 },      -- 血红
        skills = {
            -- 技能1: 地狱火扇 —— 扇形射出 8 发烈焰弹
            {
                name = "地狱火扇",
                icon = "🔥",
                interval = 2.5,
                type = "shoot_fan",
                bulletCount = 8,
                bulletSpeed = 280,
                damage = 12,
                spreadAngle = 1.2,
            },
            -- 技能2: 暗影冲锋 —— 极速冲刺 + 传送后留弹幕
            {
                name = "暗影冲锋",
                icon = "👹",
                interval = 5.0,
                type = "dash",
                dashSpeed = 520,
                dashDuration = 0.55,
                damage = 22,
                dashRadius = 60,
            },
            -- 技能3 (大招): 末日审判 —— 周围落 22 颗陨石 + 360° 散射 30 发
            {
                name = "末日审判",
                icon = "☄️",
                interval = 14.0,
                type = "area_rain",
                count = 22,
                damage = 15,
                radius = 38,
                spawnRange = 320,
                fallDuration = 0.65,
                isUltimate = true,
                stunDuration = 5.0,
            },
        },
    },
}

--- 根据波次号获取 Boss 定义
--- @param waveNum number 当前波次号
--- @return table|nil Boss 定义（nil 表示本波无 Boss）
function Config.GetBossForWave(waveNum)
    if waveNum % Config.WAVE.bossInterval ~= 0 then return nil end
    local bossIndex = (waveNum / Config.WAVE.bossInterval)
    -- 循环轮换（超过7个后从头来，系数更高）
    local idx = ((bossIndex - 1) % #Config.BOSSES) + 1
    return Config.BOSSES[idx]
end

-- 通用技能 ID（所有角色共享）
Config.SHARED_SKILLS = { "atk_drone", "atk_up", "speed_up", "magnet", "knockback" }

-- 敌人 emoji（每种类型一组随机 emoji）
Config.ENEMY_EMOJI = {
    normal  = { "👾", "👻", "🤖", "💀" },      -- 普通怪
    fast    = { "🦇", "⚡", "🐍", "🐺" },      -- 速敏怪
    tank    = { "🐻", "🦍", "🐂", "🪨" },      -- 坦克怪
    swarm   = { "🐜", "🪲", "🦟", "🐛" },      -- 蜂群小怪
    charger = { "🦏", "🐗", "🐃" },            -- 冲锋怪
    ghost   = { "👻", "🫥", "💨" },             -- 幽灵怪
    shaman  = { "🧙", "🔮", "☠️" },            -- 巫师怪
    ranger  = { "🏹", "🎯", "🔫" },            -- 远程怪
    elite   = { "👹", "🐉", "😈", "🦾" },      -- 精英怪
    boss    = { "🐙" },                         -- BOSS（实际由 BOSSES 定义覆盖）
}

-- 敌人基础属性
Config.ENEMY = {
    normal = {
        radius = 14,
        baseHp = 16,
        baseAtk = 3,
        speed = 100,
        expDrop = 2,
        color = "enemyNormal",
    },
    fast = {
        radius = 10,
        baseHp = 8,
        baseAtk = 2,
        speed = 180,
        expDrop = 2,
        color = "enemyNormal",
    },
    tank = {
        radius = 22,
        baseHp = 40,
        baseAtk = 5,
        speed = 60,
        expDrop = 4,
        color = "enemyElite",
    },
    -- 蜂群小怪：极小、极弱、极快，成群出现
    swarm = {
        radius = 8,
        baseHp = 5,
        baseAtk = 1,
        speed = 160,
        expDrop = 1,
        color = "neonGreen",
    },
    -- 冲锋怪：停顿蓄力后高速冲刺，高伤
    charger = {
        radius = 18,
        baseHp = 24,
        baseAtk = 8,
        speed = 50,           -- 基础慢速，冲刺时 ×4
        expDrop = 3,
        color = "neonYellow",
    },
    -- 幽灵怪：随机闪现传送，难以命中
    ghost = {
        radius = 12,
        baseHp = 12,
        baseAtk = 4,
        speed = 70,
        expDrop = 3,
        color = "neonCyan",
    },
    -- 巫师怪：远距离环绕，周期性突进
    shaman = {
        radius = 14,
        baseHp = 20,
        baseAtk = 6,
        speed = 80,
        expDrop = 4,
        color = "neonPurple",
    },
    -- 远程怪：保持距离，发射弹幕
    ranger = {
        radius = 12,
        baseHp = 14,
        baseAtk = 5,
        speed = 90,
        expDrop = 3,
        color = "neonOrange",
        shootInterval = 2.0,     -- 射击间隔
        shootRange = 250,        -- 射击距离
        keepDistance = 180,       -- 保持距离
        bulletSpeed = 280,       -- 弹幕速度
    },
    elite = {
        radius = 20,
        baseHp = 100,
        baseAtk = 8,
        speed = 90,
        expDrop = 10,
        color = "enemyElite",
    },
    boss = {
        radius = 40,
        baseHp = 600,
        baseAtk = 16,
        speed = 70,
        expDrop = 40,
        color = "enemyBoss",
    },
}

-- 技能定义
Config.SKILLS = {
    -- 武器类
    {
        id = "atk_drone",
        name = "攻击无人机",
        desc = "召唤蓝色无人机自动攻击",
        icon = "🛸",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 0.5, interval = 1.0 },
    },
    {
        -- 需要飞行遗物 1 级以上才能出现在技能池
        -- 最大等级由 RelicSystem.GetGreenDroneMaxLevel() 动态决定
        id = "atk_drone_green",
        name = "绿色无人机",
        desc = "更大轨道的绿色无人机，碰撞伤害=100%子弹，远程=50%蓝色",
        icon = "🛩️",
        type = "weapon",
        maxLevel = 3,  -- 运行时被 RelicSystem.GetGreenDroneMaxLevel() 覆盖
        effect = { baseDmg = 0.25, interval = 1.0 },
    },
    {
        id = "grenade",
        name = "手雷",
        desc = "碰敌即炸+击退，升级连投",
        icon = "💣",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 2.0, interval = 5.0, radius = 80 },
    },
    {
        id = "shield",
        name = "力场护盾",
        desc = "定期生成护盾抵挡伤害",
        icon = "🛡️",
        type = "defense",
        maxLevel = 3,
        effect = { interval = 10.0, charges = 1 },
    },
    {
        id = "hp_regen",
        name = "生命恢复",
        desc = "每秒恢复生命值",
        icon = "💚",
        type = "defense",
        maxLevel = 3,
        effect = { regenPercent = 0.01 },
    },
    -- 属性加成类
    {
        id = "atk_up",
        name = "攻击提升",
        desc = "全局攻击+10%",
        icon = "⚔️",
        type = "passive",
        maxLevel = 5,
        effect = { atkBonus = 0.10 },
    },
    {
        id = "hp_up",
        name = "生命提升",
        desc = "全局生命+10%",
        icon = "❤️",
        type = "passive",
        maxLevel = 5,
        effect = { hpBonus = 0.10 },
    },
    {
        id = "speed_up",
        name = "移速提升",
        desc = "全局移速+5%",
        icon = "👟",
        type = "passive",
        maxLevel = 5,
        effect = { speedBonus = 0.05 },
    },
    {
        id = "crit_up",
        name = "暴击提升",
        desc = "暴击率+5%",
        icon = "🎯",
        type = "passive",
        maxLevel = 5,
        effect = { critBonus = 0.05 },
    },
    {
        id = "magnet",
        name = "磁力增强",
        desc = "拾取范围+30%",
        icon = "🧲",
        type = "passive",
        maxLevel = 3,
        effect = { magnetBonus = 0.30 },
    },
    {
        id = "fire_rate",
        name = "射速提升",
        desc = "攻击间隔-15%",
        icon = "🔥",
        type = "passive",
        maxLevel = 3,
        effect = { fireRateBonus = 0.15 },
    },
    {
        id = "multi_shot",
        name = "多重射击",
        desc = "同时发射额外子弹",
        icon = "🔫",
        type = "weapon",
        maxLevel = 3,
        effect = { extraBullets = 1 },
    },
    {
        id = "piercing",
        name = "穿透弹",
        desc = "子弹可穿透敌人",
        icon = "💠",
        type = "weapon",
        maxLevel = 3,
        effect = { pierceCount = 1 },
    },
    {
        id = "ricochet",
        name = "弹射弹",
        desc = "子弹命中后弹射至附近敌人",
        icon = "🔀",
        type = "weapon",
        maxLevel = 3,
        effect = { bounceCount = 1 },
    },
    -- ======== 猫咪专属新技能 ========
    {
        id = "cat_scratch",
        name = "星爆猫爪",
        desc = "200%范围星爆，连击积攒，爆红心叠攻速",
        icon = "⭐",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 2.4, interval = 3.0, radius = 180, heartChance = 0.20, atkSpeedBuff = 0.05, buffDuration = 5.0 },
    },
    -- ======== 黄豆专属新技能 ========
    {
        id = "bean_sprout",
        name = "豆芽陷阱",
        desc = "种下豆芽，踩到大范围爆炸",
        icon = "🌱",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 1.5, interval = 4.0, maxTraps = 3 },
    },
    -- ======== 猴子专属技能 ========
    {
        id = "combo_hit",
        name = "连击拳",
        desc = "子弹命中后弹射至附近敌人",
        icon = "👊",
        type = "weapon",
        maxLevel = 3,
        effect = { bounceCount = 1 },
    },
    {
        id = "dodge_roll",
        name = "闪避翻滚",
        desc = "移速+7%，暴击率+2%",
        icon = "💨",
        type = "passive",
        maxLevel = 5,
        effect = { speedBonus = 0.07, critBonus = 0.02 },
    },
    {
        id = "clone_strike",
        name = "分身打击",
        desc = "召唤分身发射射弹，继承弹幕加成",
        icon = "🐒",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 0.2, interval = 0.6 },
    },
    {
        id = "speed_burst",
        name = "极速爆发",
        desc = "攻击间隔-20%",
        icon = "⚡",
        type = "passive",
        maxLevel = 3,
        effect = { fireRateBonus = 0.20 },
    },
    -- ======== 手专属技能 ========
    {
        id = "palm_wave",
        name = "掌风波",
        desc = "子弹可穿透敌人",
        icon = "🌊",
        type = "weapon",
        maxLevel = 3,
        effect = { pierceCount = 1 },
    },
    {
        id = "grab_smash",
        name = "太极拳",
        desc = "化劲：消除来袭敌弹并释放6倍掌风波",
        icon = "🫴",
        type = "weapon",
        maxLevel = 3,
        effect = {
            detectRadius = 50,      -- 检测玩家周围多大范围内的敌弹
            baseCooldown = 10.0,    -- 基础冷却（每10秒最多触发次数 = level）
            dmgMultiplier = 6.0,    -- 基础子弹伤害的倍数
            waveSpeed = 500,        -- 掌风波飞行速度
            waveGrowRate = 8.0,     -- 掌风波每秒膨胀倍率
            waveMaxScale = 5.0,     -- 掌风波最大膨胀倍数
        },
    },
    {
        id = "finger_flick",
        name = "弹指神功",
        desc = "暴击率+6%",
        icon = "👆",
        type = "passive",
        maxLevel = 5,
        effect = { critBonus = 0.06 },
    },
    {
        id = "iron_fist",
        name = "铁拳",
        desc = "全局攻击+12%",
        icon = "🥊",
        type = "passive",
        maxLevel = 5,
        effect = { atkBonus = 0.12 },
    },
    -- ======== 手专属新技能 ========
    {
        id = "thumb_up",
        name = "点赞弹幕",
        desc = "瞄准弹幕连射，受子弹与散射加成",
        icon = "👍",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 0.6, interval = 3.5, bulletCount = 4 },
    },
    -- ======== 猴子专属新技能 ========
    {
        id = "big_bullet",
        name = "巨弹强袭",
        desc = "2%概率发射3倍大子弹，附加敌人最大生命0.2%伤害",
        icon = "🎯",
        type = "passive",
        maxLevel = 5,
        effect = { bigBulletChance = 0.02 },
    },
    -- ======== 通用加成新技能 ========
    {
        id = "knockback",
        name = "击退冲击",
        desc = "子弹命中5%概率击退敌人0.2秒",
        icon = "💥",
        type = "passive",
        maxLevel = 3,
        effect = { knockbackChance = 0.05 },
    },
    -- ======== 叶子专属技能 ========
    {
        id = "leaf_pierce",
        name = "藤蔓穿刺",
        desc = "子弹+2穿透（上限3层）",
        icon = "🌿",
        type = "weapon",
        maxLevel = 3,
        effect = { pierceCount = 2 },
    },
    {
        id = "leaf_homing",
        name = "自然追踪",
        desc = "25%概率子弹0.3s后追踪敌人",
        icon = "🍁",
        type = "passive",
        maxLevel = 3,
        effect = { homingChance = 0.25 },
    },
    {
        id = "xmas_tree",
        name = "圣诞之树",
        desc = "召唤圣诞树环绕，发射冰弹冻结敌人",
        icon = "🎄",
        type = "weapon",
        maxLevel = 3,
        effect = { baseDmg = 1.0, interval = 0.5, orbitRadius = 100, iceBulletInterval = 1.5 },
    },
    {
        id = "clover_luck",
        name = "四叶幸运",
        desc = "掉落物品概率+15%",
        icon = "🍀",
        type = "passive",
        maxLevel = 3,
        effect = { lootBonus = 0.15 },
    },
    {
        id = "leaf_storm",
        name = "霜瑟风暴",
        desc = "冰霜风暴AoE，对范围内全体敌人造成1/3伤害并叠加冰冻",
        icon = "🌨️",
        type = "weapon",
        maxLevel = 3,
        effect = { radius = 130 },
    },
    -- ======== OTTO专属技能 ========
    {
        id = "elephant_stomp",
        name = "大象踩背",
        desc = "2%射击概率召唤大象(10s)，每秒AoE踩踏1.5倍伤害",
        icon = "🐘",
        type = "weapon",
        maxLevel = 5,
        effect = {
            summonChance = 0.02,    -- 2% 射击时召唤
            duration = 10.0,        -- 大象存活10秒
            dmgMultiplier = 1.5,    -- AoE伤害 = 1.5 × 子弹伤害
            stompInterval = 1.0,    -- 每秒踩踏一次
            stompRadius = 120,      -- 踩踏AoE范围
            moveSpeed = 120,        -- 大象移动速度
        },
    },
    {
        id = "charm_enemy",
        name = "我喜欢你你喜欢我",
        desc = "击杀敌人时魅惑，上限=等级，近战6次/秒，远程射魅惑弹",
        icon = "❤",
        type = "passive",
        maxLevel = 3,
        effect = {
            maxCharmed = 1,             -- 每级上限+1（实际=等级）
        },
    },
    {
        id = "slow_rider",
        name = "慢行者",
        desc = "发射骑马子弹锁定敌人，制造旋风每秒2次伤害",
        icon = "🐎",
        type = "weapon",
        maxLevel = 5,
        effect = {
            interval = 4.0,         -- 发射间隔
            dmgPerTick = 1.0,       -- 旋风每次伤害 = 1× 子弹伤害
            tickRate = 2.0,         -- 每秒命中2次
            lockDuration = 5.0,     -- 锁定持续5秒
            whirlRadius = 60,       -- 旋风影响范围
            horseSpeed = 300,       -- 马子弹飞行速度
        },
    },
    {
        id = "otto_box",
        name = "盒子",
        desc = "每5s部署/拆除盒子，复制僚机技能，伤害50%，上限=等级",
        icon = "📦",
        type = "passive",
        maxLevel = 3,
        effect = {
            maxBoxes = 1,           -- 每级+1（实际=等级）
            dmgRatio = 0.5,         -- 伤害减半
            placeRadius = 60,       -- 放置在玩家附近的范围
            mimicInterval = 2.0,    -- 模仿技能间隔
        },
    },
    {
        id = "otto_sprint",
        name = "冲刺",
        desc = "移速+15%，可叠加（上限3层=45%）",
        icon = "🦽",
        type = "passive",
        maxLevel = 3,
        effect = {
            speedBonus = 0.15,      -- 每级移速+15%
        },
    },
}

-- ============================================================================
-- ID 序号索引系统
-- 为每个类型分配稳定的 _id（数字序号），建立反查表，支持保底 fallback。
-- 即使删除某个定义，旧存档中的 _id 只会命中保底而不会崩溃。
-- ============================================================================

--- 角色 _id 索引
Config._CHAR_BY_ID = {}
Config._CHAR_BY_SID = {}
for i, ch in ipairs(Config.CHARACTERS) do
    ch._id = i
    Config._CHAR_BY_ID[i] = ch
    Config._CHAR_BY_SID[ch.id] = ch
end

--- 通过 _id 查找角色（保底第一个）
---@param numId number
---@return table
function Config.GetCharacterById(numId)
    return Config._CHAR_BY_ID[numId] or Config.CHARACTERS[1]
end

--- Boss _id 索引
Config._BOSS_BY_ID = {}
Config._BOSS_BY_SID = {}
for i, boss in ipairs(Config.BOSSES) do
    boss._id = i
    Config._BOSS_BY_ID[i] = boss
    Config._BOSS_BY_SID[boss.id] = boss
end

--- 通过 _id 查找 Boss（保底第一个）
---@param numId number
---@return table
function Config.GetBossById(numId)
    return Config._BOSS_BY_ID[numId] or Config.BOSSES[1]
end

--- 通过字符串 id 查找 Boss（保底第一个）
---@param sid string
---@return table
function Config.GetBossBySid(sid)
    return Config._BOSS_BY_SID[sid] or Config.BOSSES[1]
end

--- 技能 _id 索引
Config._SKILL_BY_ID = {}
Config._SKILL_BY_SID = {}
for i, sk in ipairs(Config.SKILLS) do
    sk._id = i
    Config._SKILL_BY_ID[i] = sk
    Config._SKILL_BY_SID[sk.id] = sk
end

--- 通过 _id 查找技能（保底 nil，技能删除后跳过即可）
---@param numId number
---@return table|nil
function Config.GetSkillById(numId)
    return Config._SKILL_BY_ID[numId]
end

--- 通过字符串 id 查找技能（带保底）
---@param sid string
---@return table|nil
function Config.GetSkillBySid(sid)
    return Config._SKILL_BY_SID[sid]
end

--- 敌人类型 _id 索引（按固定顺序分配稳定序号）
Config._ENEMY_TYPE_ORDER = { "normal", "fast", "tank", "swarm", "charger", "ghost", "shaman", "ranger", "elite", "boss" }
Config._ENEMY_BY_ID = {}
Config._ENEMY_ID_MAP = {}   -- typeName → _id
for i, typeName in ipairs(Config._ENEMY_TYPE_ORDER) do
    local def = Config.ENEMY[typeName]
    if def then
        def._id = i
        def._typeName = typeName
        Config._ENEMY_BY_ID[i] = def
        Config._ENEMY_ID_MAP[typeName] = i
    end
end

--- 通过 _id 查找敌人定义（保底 normal）
---@param numId number
---@return table def
---@return string type_name
function Config.GetEnemyById(numId)
    local def = Config._ENEMY_BY_ID[numId]
    if def then return def, def._typeName end
    return Config.ENEMY.normal, "normal"
end

return Config
