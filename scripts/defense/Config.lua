-- 固定据点防守 V0.2：继承已验证基线，新增公共交互 P 原型候选。
-- C02 核心坐标固定；Q16–Q21 临时采用写在 decisions，不冒充最终定稿。
-- 可复用外观独立于旧角色/技能索引，规则模块仍不引入引擎依赖。
local Original = require("defense.Visuals")
local Cat = Original.CHARACTERS[1]
local C = {
    version = "defense-0.2.0",
    title = "固定据点防守",
    map_size = { w = 64, h = 48 },
    coordinate_scale = 1, -- 逻辑格；表现层单独转换为像素，三维迁移时 1 格 = 1 米。
    core_position = { x = 32, y = 21 },
    core_max_hp = 1000,
    core_radius = 1.6,
    player_spawn = { x = 30, y = 27 },
    recall_position = { x = 32, y = 6 },
    character = { id = Cat.id, name = Cat.name, emoji = Cat.emoji, states = Cat.playerEmoji, bullets = Cat.bulletStyle },
    player = { hp = 100, radius = 0.35, speed = 4.5, damage = 12, interval = 0.42, range = 7.5,
        emoji = Cat.emoji, weight = 1, bullet_speed = 19,
        active_damage = 0, active_radius = 4.5, active_range = 4.5, active_distance = 3, active_cooldown = 8 },
    reactions = { delay = 0.7, radius = 2.5, damage = 40, initial_hits = 4, slow_cap = 0.5,
        summary_duration = 2, summary_limit = 2, history_limit = 64 },
    -- R38 原型机会只替换 advance 名额；横向偏移在同入口合法半径内，绝不按玩家动作生成答案。
    opportunities = { first_wave = 3, lane_offset = 0.45, explosive_gap = 9 },
    currency = 60,
    preparation_duration = 15,
    attack_duration = 60, -- 清波奖励基准秒数；不是战斗超时上限。
    warning_duration = 8,
    recall_duration = 1.5,
    return_warning_distance = 13,
    batch_interval = 0.8,
    alive_soft_limit = 80,
    attack_warning = 0.7,
    max_step = 0.05,
    portals = {
        W = { x = 17, y = 21, name = "西路" },
        E = { x = 47, y = 21, name = "东路" },
        S = { x = 32, y = 35, name = "南路" },
    },
    build_slots = {
        { id = "T1", x = 27, y = 14 }, { id = "T2", x = 37, y = 14 },
        { id = "T3", x = 27, y = 28 }, { id = "T4", x = 37, y = 28 },
    },
    walkable_regions = {
        { id = "hall", x1 = 21, y1 = 10, x2 = 43, y2 = 32 },
        { id = "logistics", x1 = 25, y1 = 2, x2 = 39, y2 = 8 },
        { id = "north_corridor", x1 = 30, y1 = 7, x2 = 34, y2 = 11 },
        { id = "west_corridor", x1 = 13, y1 = 19, x2 = 22, y2 = 23 },
        { id = "east_corridor", x1 = 42, y1 = 19, x2 = 51, y2 = 23 },
        { id = "south_corridor", x1 = 30, y1 = 31, x2 = 34, y2 = 39 },
        { id = "A1", x1 = 2, y1 = 15, x2 = 14, y2 = 27 },
        { id = "A2", x1 = 2, y1 = 2, x2 = 14, y2 = 10 },
        { id = "A_corridor", x1 = 6, y1 = 9, x2 = 10, y2 = 16 },
        { id = "B1", x1 = 50, y1 = 15, x2 = 62, y2 = 27 },
        { id = "B2", x1 = 50, y1 = 2, x2 = 62, y2 = 10 },
        { id = "B_corridor", x1 = 54, y1 = 9, x2 = 58, y2 = 16 },
        { id = "C1", x1 = 25, y1 = 38, x2 = 39, y2 = 47 },
        { id = "C2", x1 = 45, y1 = 38, x2 = 61, y2 = 47 },
        { id = "C_corridor", x1 = 38, y1 = 41, x2 = 46, y2 = 45 },
    },
    obstacles = {
        { x1 = 24, y1 = 20, x2 = 27, y2 = 23 },
        { x1 = 37, y1 = 19, x2 = 40, y2 = 22 },
    },
    rooms = {
        { id = "A1", x = 8, y = 21, tier = 1, unlock = "A2" },
        { id = "A2", x = 8, y = 6, tier = 2, prerequisite = "A1" },
        { id = "B1", x = 56, y = 21, tier = 1, unlock = "B2" },
        { id = "B2", x = 56, y = 6, tier = 2, prerequisite = "B1" },
        { id = "C1", x = 32, y = 43, tier = 1, unlock = "C2" },
        { id = "C2", x = 53, y = 43, tier = 2, prerequisite = "C1" },
    },
    enemies = {
        advance = { name = "推进怪", hp = 20, speed = 1.2, radius = 0.34, damage = 5, interval = 1.1, xp = 2, gold = 1 },
        ranged = { name = "远射怪", hp = 14, speed = 1, radius = 0.32, damage = 8, core_damage = 4, interval = 1.8, xp = 2, gold = 1 },
        charger = { name = "冲锋怪", hp = 30, speed = 1.5, radius = 0.38, damage = 15, interval = 2.5, xp = 2, gold = 1 },
        elite = { name = "破阵精英", hp = 250, speed = 0.95, radius = 0.55, damage = 20, interval = 1.5, xp = 10, gold = 8 },
        commander = { name = "统领", hp = 800, speed = 0.65, radius = 0.8, damage = 25, interval = 2, xp = 30, gold = 30 },
        siege = { name = "攻城统领", hp = 1300, speed = 0.6, radius = 0.85, damage = 30, interval = 2, xp = 30, gold = 30 },
        final = { name = "终局统领", hp = 2000, speed = 0.55, radius = 0.9, damage = 35, interval = 2, xp = 30, gold = 30 },
    },
    towers = {
        rapid = { name = "速射塔", cost = 80, upgrade = 60, hp = 150, range = 8, interval = 0.65, damage = 8 },
        slow = { name = "减速塔", cost = 90, upgrade = 70, hp = 150, range = 5.5, interval = 1.5,
            damage = 2, slow = 0.65, slow_amount = 0.35, slow_duration = 2 },
        area = { name = "范围塔", cost = 110, upgrade = 80, hp = 150, range = 7.5, interval = 1.8, damage = 16, splash = 2.1 },
    },
    builds = {
        { id = "single", name = "精准拦截", description = "穿透火力与无伤击退，决定拦截和引爆方向" },
        { id = "area", name = "范围清场", description = "范围弹头与无伤击退，利用密集队列但留意近核爆炸" },
        { id = "control", name = "控制协防", description = "减速弹头与无伤击退，换路回防和资金取舍" },
    },
    decisions = {
        Q01 = "当前 UrhoX 单机；继承原作键鼠WASD/方向键与VirtualControls触屏摇杆，空格/主动按钮击退；真机待验。",
        Q02 = "默认完整 20 波；5 波为显式教学测试，不承诺 18–22 分钟实测达标。",
        Q03 = "按候选三路六据点四槽回城实现，未升级为最终确认。",
        Q04 = "新模式复用原Particle/GameAudio与其性能表现工具；原单例战斗循环不接入，守核规则单独实现并可无引擎测试。",
        Q05 = "普通怪按入口轮转分配，每批每入口 1 只，0.8 秒；W16 W=0 E=2 S=4 暂定；软上限统计全波存活含召唤；逐单位延期。",
        Q06 = "本配置缺失伤害/周期为临时初值；统领范围攻击，攻城统领加定向冲击；最多召唤3次每次3只，Boss减速减半。",
        Q07 = "房间通道矩形从原图推定为灰盒；连续边界闭区间，圆形半径检测；核心攻击终点使用实际1.6格，不强凑11格。",
        Q08 = "WARNING允许移动探索，不允许后勤或回城；离战备、移动、受击均取消回城；距离13格末8秒警告。",
        Q09 = "治疗封顶、满血禁用、不限次数；两次升级同价；损坏指hp低于满值，拆除返0，否则累计成本向下取整50%；塔不阻挡移动，摧毁后可重建；减速取最强。",
        Q10 = "先初始化部署再开场；每局节点去重、持久seen用于回看；重试开场3秒/终局4秒/收束5秒短版；回看完整且恢复原暂停，终局演出后重给8秒预警。",
        Q11 = "每5波仅记录本地阶段完成，不虚构永久数值奖励；同帧死亡不发清波奖励；通关记录与下一章解锁，下一章内容未制作。",
        Q12 = "初始等级1，经验为未消费余额；固定候选池加前置/满级过滤；补齐为恢复25生命/资金15/主动技冷却归零三种不同ID；据点领取即时经验。",
        Q13 = "此次用户已明确沿用原作NanoVG战场、霓虹emoji UI与VirtualControls；Board统一绘制而非另开粒子渲染。叙事、成品分镜配音预算仍未定。",
        Q14 = "独立命名空间保存阶段/章节/演出记录、表现设置与最后一局少量事实战报；不添加中途续局，不碰旧profile/gamesave；WASM刷新不保证持久化。",
        Q15 = "按依赖渐进批次，不虚构工期、FPS或设备预算。",
        Q16 = "V0.2 原型临时采用无伤击退4.5格/3格/8秒及死亡0.7秒/2.5格/40友伤爆炸；全部起始方案自带击退。",
        Q17 = "中心距离含目标圆半径判断爆炸，LOS检测两圆心；危险圈读取同策略。位移按3/max(1,weight)，直线扫掠遇墙柱停止不滑墙；重物与锚定如实提示。",
        Q18 = "减速以百分比来源声明，先cap50%再Boss半效；同实体来源刷新2秒、异源独立期限、最强不相乘；塔连续LOS半径5.5刷新，升级/协同沿旧范围加成。",
        Q19 = "本局全部未结有害反应含守军阻挡清波，不将守军加进活怪计数；同槽全部反应提交后失败优先，退出清旧队列与局身份。",
        Q20 = "W3替一个advance，W4–5至少两名额后续每波不同入口/队列位置与横向落点；不改原20波总量/Boss。W3–5首个升级面板保护范围候选，未发生升级不赠能力。",
        Q21 = "按实际事件保存阶段/局末最近1–2条链、至多16条详情片段及真实支出/修复；首次只提示属性可关闭，不推断玩家理解；匿名人类试玩与迁移人数待真实测试。",
    },
}

-- 原作战场标识拷贝映射（不改 Original）；爆炸 advance 加稳定危险标记，不换隐藏角色。
C.enemy_emoji = {
    advance = Original.ENEMY_EMOJI.normal, ranged = Original.ENEMY_EMOJI.ranger,
    charger = Original.ENEMY_EMOJI.charger, elite = Original.ENEMY_EMOJI.elite,
    commander = { Original.BOSSES[1].emoji }, siege = { Original.BOSSES[2].emoji },
    final = { Original.BOSSES[3].emoji },
}
C.explosive_marker = Original.SPECIAL_LOOT.bomb.emoji
C.bullet_emoji = Cat.bulletStyle
for role, def in pairs(C.enemies) do
    def.emoji = C.enemy_emoji[role][1]
    def.team, def.damageable, def.movable, def.anchored = "enemy", true, true, false
    def.weight = (role == "elite" and 1.5) or ((role == "commander" or role == "siege" or role == "final") and 3) or 1
end

-- R16 原表为唯一编辑输入；队列由 WaveDirector 派生。
local rows = {
    { "W",18,0 }, { "E",24,0 }, { "S",30,0 }, { "WE",36,0 }, { "S",24,1 },
    { "WS",42,0 }, { "ES",48,1 }, { "WE",54,0 }, { "WS",60,1 }, { "WE",36,0,"commander","E" },
    { "WES",64,0 }, { "WES",70,1 }, { "WES",76,1 }, { "WES",82,2 }, { "WES",45,0,"siege","S" },
    { "WES",90,1 }, { "WES",96,2 }, { "WES",102,2 }, { "WES",108,2 }, { "WES",54,0,"final","S" },
}
C.waves = {}
for i, row in ipairs(rows) do
    local portals = {}
    for ch in row[1]:gmatch(".") do portals[#portals + 1] = ch end
    C.waves[i] = { wave_id = i, active_portals = portals, ordinary = row[2], elite_count = row[3],
        boss_type = row[4], boss_portal = row[5], reward = 12,
        portal_offsets = i == 16 and { W = 0, E = 2, S = 4 } or { W = 0, E = 0, S = 0 } }
end
return C
