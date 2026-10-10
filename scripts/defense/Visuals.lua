-- 从原 Config.lua 精确提取的可复用视觉数据，不加载旧角色/技能/难度索引模块。
-- 仅保留原配色、猫表情、弹道风格和本模式所需敌人标识；不继承旧玩法数值。
local V = {}
V.COLORS = {
    bg = { 10, 8, 25, 255 }, bgGrid = { 30, 20, 60, 80 },
    neonBlue = { 0, 200, 255, 255 }, neonPurple = { 180, 50, 255, 255 }, neonPink = { 255, 50, 150, 255 },
    neonGreen = { 0, 255, 150, 255 }, neonOrange = { 255, 150, 0, 255 }, neonRed = { 255, 50, 50, 255 },
    neonYellow = { 255, 255, 50, 255 }, neonCyan = { 0, 255, 255, 255 }, white = { 255, 255, 255, 255 },
    hpBar = { 50, 255, 100, 255 }, expBar = { 100, 150, 255, 255 }, bullet = { 0, 255, 200, 255 },
    enemyNormal = { 255, 50, 50, 255 }, enemyElite = { 255, 150, 0, 255 }, enemyBoss = { 255, 50, 150, 255 },
}
V.CHARACTERS = { {
    id = "cat", name = "小猫咪", emoji = "😺",
    playerEmoji = { idle = "😺", move = "😸", hit = "🙀", overload = "😼", dead = "😿", shield = "😻" },
    bulletStyle = {
        normal = { emoji = "🐟", color = { 0, 230, 200 }, trailColor = { 0, 230, 200 }, glowColor = { 0, 255, 220, 50 }, size = 1.0 },
        pierce = { emoji = "⭐", color = { 200, 120, 255 }, trailColor = { 180, 80, 255 }, glowColor = { 200, 100, 255, 60 }, size = 1.15 },
        spread = { emoji = "💫", color = { 255, 140, 200 }, trailColor = { 255, 100, 180 }, glowColor = { 255, 150, 200, 50 }, size = 0.9 },
        ricochet = { emoji = "🐳", color = { 0, 200, 255 }, trailColor = { 0, 180, 255 }, glowColor = { 0, 220, 255, 60 }, size = 1.1 },
    },
} }
V.ENEMY_EMOJI = {
    normal = { "👾", "👻", "🤖", "💀" }, ranger = { "🏹", "🎯", "🔫" },
    charger = { "🦏", "🐗", "🐃" }, elite = { "👹", "🐉", "😈", "🦾" }, boss = { "🐙" },
}
V.ENEMY = { normal = { color = "enemyNormal" }, ranger = { color = "neonOrange" },
    charger = { color = "neonYellow" }, elite = { color = "enemyElite" }, boss = { color = "enemyBoss" } }
V.BOSSES = { { emoji = "👮‍♀️" }, { emoji = "👷‍♂️" }, { emoji = "👿" } }
V.SPECIAL_LOOT = { bomb = { emoji = "💣" }, coin = { emoji = "🪙" } }
return V
