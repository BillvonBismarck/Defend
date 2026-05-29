# Emoji幸存者 - 项目设计文档

> 用途：完整记录所有变量名（含中文简称）及参数值，用于复现项目和数值调整。
> 工作流：用户修改本文档中的参数 → AI 检查变更内容 → 实装到代码中。

---

## 1. 项目架构

```
scripts/
├── main.lua                 # 主入口：初始化、状态机、渲染循环
├── Config.lua               # 数值配置表（所有可调参数集中于此）
├── battle/
│   ├── BattleScene.lua      # 战斗场景管理：状态机、回调分发
│   ├── Player.lua           # 玩家：属性、移动、攻击、升级、毕业Build
│   ├── Enemy.lua            # 敌人：对象池、AI行为、Boss技能执行
│   ├── EnemyBullet.lua      # 敌人弹幕：直线弹、扇形弹、环形弹、分裂弹、区域攻击
│   ├── Projectile.lua       # 玩家子弹：对象池、穿透、弹射、拖尾特效
│   ├── Loot.lua             # 掉落物：经验芯片、特殊掉落（❤️🧲💣🪙🎁）
│   ├── Skill.lua            # 技能系统：随机抽取、主动技能更新（无人机/手雷/分身等）
│   └── Wave.lua             # 波次管理：刷怪节奏、波次系数、阵容表
├── ui/
│   ├── HUD.lua              # 战斗HUD：血条、经验条、过载条、Boss血条、技能冷却
│   ├── SkillSelect.lua      # 技能选择UI：3选1卡牌、毕业终极奖励
│   ├── GiftAd.lua           # 礼物盒广告弹窗：看广告/放弃
│   └── DamageNumber.lua     # 飘字系统：伤害数字、经验提示、暴击
└── fx/
    ├── Particle.lua         # 粒子特效：击中、死亡、升级、冲击波、闪光
    └── GameAudio.lua        # 音频系统：BGM、音效池（8通道）
```

---

## 2. Config.lua 完整参数表

### 2.1 设计分辨率（designResolution / 设计分辨率）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.DESIGN_W` | 设计宽度 | 720 | 竖屏设计宽度（像素） |
| `Config.DESIGN_H` | 设计高度 | 1280 | 竖屏设计高度（像素） |
| `Config.WORLD_SIZE` | 世界大小 | 4000 | 正方形游戏世界边长（设计像素） |

### 2.2 玩家属性（PLAYER / 玩家）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.PLAYER.radius` | 玩家半径 | 18 | 碰撞半径（设计像素） |
| `Config.PLAYER.baseHp` | 基础血量 | 35 | 初始最大生命值 |
| `Config.PLAYER.baseAtk` | 基础攻击 | 6 | 初始攻击力 |
| `Config.PLAYER.baseSpeed` | 基础移速 | 280 | 像素/秒 |
| `Config.PLAYER.baseCritRate` | 基础暴击率 | 0.05 | 5% |
| `Config.PLAYER.critDamage` | 暴击倍率 | 2.0 | 暴击伤害 = 攻击 × 此值 |
| `Config.PLAYER.attackInterval` | 攻击间隔 | 0.5 | 自动攻击间隔（秒） |
| `Config.PLAYER.attackRange` | 攻击范围 | 350 | 自动锁定最近敌人的范围（像素） |
| `Config.PLAYER.magnetRange` | 磁吸范围 | 80 | 经验芯片自动吸取半径（像素） |
| `Config.PLAYER.invincibleTime` | 无敌时间 | 0.8 | 受击后无敌持续（秒） |

### 2.3 子弹属性（BULLET / 子弹）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.BULLET.speed` | 子弹速度 | 600 | 像素/秒 |
| `Config.BULLET.radius` | 子弹半径 | 9 | 碰撞半径（像素） |
| `Config.BULLET.lifetime` | 子弹寿命 | 1.5 | 存活时间（秒） |

### 2.4 掉落物（LOOT / 掉落）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.LOOT.radius` | 掉落半径 | 6 | 碰撞半径（像素） |
| `Config.LOOT.magnetSpeed` | 磁吸速度 | 500 | 被吸引时的飞行速度 |
| `Config.LOOT.baseExp` | 基础经验 | 2 | 每个经验芯片的经验值 |
| `Config.LOOT.heartChance` | 红心掉率 | 0.04 | 4%（回复生命） |
| `Config.LOOT.magnetChance` | 磁铁掉率 | 0.03 | 3%（临时扩大磁吸） |
| `Config.LOOT.bombChance` | 炸弹掉率 | 0.02 | 2%（全屏清怪） |
| `Config.LOOT.coinChance` | 金币掉率 | 0.36 | 36%（额外经验） |

### 2.5 特殊掉落物（SPECIAL_LOOT / 特殊掉落）

| 变量名 | 中文简称 | emoji | radius | 效果参数 |
|--------|---------|-------|--------|---------|
| `SPECIAL_LOOT.heart` | 红心 | ❤️ | 10 | `healPercent = 0.15`（回复15%最大HP） |
| `SPECIAL_LOOT.magnet` | 磁铁 | 🧲 | 10 | `duration = 5.0, range = 400` |
| `SPECIAL_LOOT.bomb` | 炸弹 | 💣 | 12 | `damage = 999`（全屏清怪） |
| `SPECIAL_LOOT.coin` | 金币 | 🪙 | 8 | `expMulti = 3`（3倍经验） |
| `SPECIAL_LOOT.gift` | 礼物盒 | 🎁 | 14 | 触发广告弹窗 |

### 2.6 礼物盒 / 广告激励（GIFT_BOX / 礼物盒）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.GIFT_BOX.dropChance` | 掉落概率 | 0.008 | 0.8% 极低掉率 |
| `Config.GIFT_BOX.waveCooldown` | 波次冷却 | 5 | 每5波最多掉落1个 |
| `Config.GIFT_BOX.adExpReward` | 广告基础经验 | 200 | 看广告基础经验值 |
| `Config.GIFT_BOX.adExpPerWave` | 广告每波增量 | 20 | 每波额外经验 |
| `Config.GIFT_BOX.giveUpExpReward` | 放弃基础经验 | 20 | 放弃基础经验值 |
| `Config.GIFT_BOX.giveUpExpPerWave` | 放弃每波增量 | 2 | 每波额外经验 |

> **经验公式**: `实际奖励 = 基础值 + 当前波次 × 每波增量`
> 例：第10波看广告 = 200 + 10×20 = 400 EXP；第10波放弃 = 20 + 10×2 = 40 EXP

### 2.7 升级系统（LEVEL / 等级）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.LEVEL.maxLevel` | 最大等级 | 9999 | 无上限 |
| `Config.LEVEL.expFormula` | 升级经验公式 | `level × 20` | 每级所需经验 |
| `Config.LEVEL.hpGrowth` | 每级血量成长 | 0.03 | +3%/级 |
| `Config.LEVEL.atkGrowth` | 每级攻击成长 | 0.03 | +3%/级 |
| `Config.LEVEL.critGrowth` | 每级暴击成长 | 0.002 | +0.2%/级 |

### 2.8 过载系统（OVERLOAD / 过载）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.OVERLOAD.killsToFull` | 满载击杀数 | 100 | 击杀100只触发过载 |
| `Config.OVERLOAD.duration` | 过载持续 | 5.0 | 秒 |
| `Config.OVERLOAD.atkMultiplier` | 攻击倍率 | 2.0 | 攻击翻倍 |
| `Config.OVERLOAD.speedBonus` | 移速加成 | 0.3 | +30% |
| `Config.OVERLOAD.cooldownReduction` | 冷却缩减 | 0.5 | 技能冷却减半 |

### 2.9 毕业Build系统（GRADUATION / 毕业）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.GRADUATION.DRONE_COLLISION_DMG` | 无人机碰撞伤害 | 2 | 基础碰撞伤害 |
| `Config.GRADUATION.DRONE_COLLISION_TICK` | 碰撞检测间隔 | 0.25 | 秒 |
| `Config.GRADUATION.DRONE_MAX_LEVEL_GRAD` | 毕业后无人机上限 | 6 | 原3→6 |
| `Config.GRADUATION.MAX3_UPGRADED` | 上限3→4 | 4 | 毕业后 maxLevel 3→4 |
| `Config.GRADUATION.MAX5_UPGRADED` | 上限5→7 | 7 | 毕业后 maxLevel 5→7 |
| `Config.GRADUATION.ULTIMATE_HEAL_INV_TIME` | 终极治疗无敌时间 | 10.0 | 选项A |
| `Config.GRADUATION.ULTIMATE_RAGE_TIME` | 终极狂暴时间 | 20.0 | 选项B |
| `Config.GRADUATION.ULTIMATE_RAGE_ATK_MULT` | 终极狂暴攻击倍率 | 3.0 | 选项B |

### 2.10 波次系统（WAVE / 波次）

| 变量名 | 中文简称 | 当前值 | 说明 |
|--------|---------|--------|------|
| `Config.WAVE.interval` | 波次间隔 | 30 | 每30秒一波 |
| `Config.WAVE.baseEnemyCount` | 初始敌人数 | 5 | 第一波生成5只 |
| `Config.WAVE.countGrowth` | 每波增长 | 2 | 每波多生成2只 |
| `Config.WAVE.maxEnemiesAlive` | 同屏上限 | 60 | 最大敌人数 |
| `Config.WAVE.coeffGrowth` | 系数增长 | 0.08 | 每波属性系数+8% |
| `Config.WAVE.spawnRadius` | 生成距离上限 | 700 | 玩家周围最大距离 |
| `Config.WAVE.spawnMinRadius` | 生成距离下限 | 500 | 玩家周围最小距离 |
| `Config.WAVE.bossInterval` | Boss间隔 | 10 | 每10波出Boss |

### 2.11 敌人基础属性（ENEMY / 敌人）

| 类型 | 中文名 | radius | baseHp | baseAtk | speed | expDrop | 特殊属性 |
|------|--------|--------|--------|---------|-------|---------|---------|
| `normal` | 普通怪 | 14 | 16 | 3 | 100 | 2 | - |
| `fast` | 速敏怪 | 10 | 8 | 2 | 180 | 2 | - |
| `tank` | 坦克怪 | 22 | 40 | 5 | 60 | 4 | - |
| `swarm` | 蜂群怪 | 8 | 5 | 1 | 160 | 1 | 成群生成 |
| `charger` | 冲锋怪 | 18 | 24 | 8 | 50 | 3 | 冲刺时×4速 |
| `ghost` | 幽灵怪 | 12 | 12 | 4 | 70 | 3 | 随机闪现 |
| `shaman` | 巫师怪 | 14 | 20 | 6 | 80 | 4 | 环绕突进 |
| `ranger` | 远程怪 | 12 | 14 | 5 | 90 | 3 | `shootInterval=2.0, shootRange=250, keepDistance=180, bulletSpeed=280` |
| `elite` | 精英怪 | 20 | 100 | 8 | 90 | 10 | 每波必出1只 |

> **属性公式**: 实际值 = 基础值 × 波次系数（`waveCoeff = 1.0 + waveNum × 0.08`）

### 2.12 Boss 列表

| 序号 | ID | 名称 | emoji | 波次 | baseHp | speed | expDrop | 技能1 | 技能2 | 大招 |
|------|-----|------|-------|------|--------|-------|---------|-------|-------|------|
| 1 | `police` | 巡逻警官 | 👮‍♀️ | 10 | 800 | 65 | 50 | 警笛弹幕(5发扇形) | 追击封锁(3发连射) | 全域通缉(16发环形) |
| 2 | `worker` | 重装工头 | 👷‍♂️ | 20 | 1200 | 55 | 60 | 砖块投掷(大范围) | 钻头冲刺(冲锋) | 建筑崩塌(12落石) |
| 3 | `chef` | 地狱厨神 | 👨‍🍳 | 30 | 1600 | 70 | 70 | 飞刀投射(2连射) | 火焰喷射(8发扇形) | 致命料理(毒圈) |
| 4 | `programmer` | 代码狂魔 | 👨‍💻 | 40 | 2000 | 75 | 80 | Bug弹幕(3发扇形) | 递归炸弹(分裂4) | 蓝屏死机(24发环形) |
| 5 | `firefighter` | 烈焰战士 | 👨‍🚒 | 50 | 2500 | 60 | 90 | 水枪喷射(4连射) | 消防斧冲击(冲锋) | 灭世大火(15落火) |
| 6 | `vampire` | 暗夜伯爵 | 🧛‍♀️ | 60 | 3000 | 80 | 100 | 蝙蝠群(6发扇形) | 暗影传送(瞬移弹幕) | 鲜血狂宴(20发+5%回血) |
| 7 | `gentleman` | 暗影绅士 | 🤵‍♂️ | 70 | 3500 | 85 | 120 | 扑克飞弹(3连射) | 魔术消失(瞬移弹幕) | 终极礼花(36发环形) |
| 8 | `scientist` | 疯狂博士 | 🧑‍🔬 | 80 | 4000 | 70 | 130 | 试管投射(3连射) | 基因裂变(分裂6) | 核聚变(28发环形) |
| 9 | `pirate` | 深海船长 | 🏴‍☠️ | 90 | 4500 | 75 | 140 | 加农炮(7发扇形) | 船锚冲击(冲锋) | 暴风骤雨(18落炮) |
| 10 | `dj` | 电音狂魔 | 🎧 | 100 | 5000 | 85 | 150 | 音波冲击(5发扇形) | 低音重炮(瞬移弹幕) | 终极混音(32发环形) |
| 11 | `doctor` | 暗黑医师 | 👨‍⚕️ | 110 | 5500 | 65 | 160 | 注射针(4连射) | 瘟疫扩散(毒圈) | 起死回生(24发+8%回血) |
| 12 | `ninja` | 暗影忍者 | 🥷 | 120 | 6000 | 100 | 170 | 手里剑(4发扇形) | 影分身(瞬移弹幕) | 千本樱(20落樱) |
| 13 | `robot` | 歼灭者T-X | 🤖 | 130 | 7000 | 60 | 180 | 激光扫射(5连射) | 火箭弹(分裂8) | 终极歼灭(40发环形) |
| 14 | `demon_king` | 深渊魔王 | 👿 | 140 | 8000 | 75 | 200 | 地狱火扇(8发扇形) | 暗影冲锋(冲锋) | 末日审判(22落陨石) |

> Boss 循环轮换：超过14个后从头开始，但波次系数更高。
> 所有 Boss 大招使用后自眩晕 `stunDuration = 5.0` 秒。
> Boss 无接触伤害，仅通过技能造成伤害。

### 2.13 角色定义（CHARACTERS / 角色）

| ID | 名称 | emoji | 主题色 | HP倍率 | ATK倍率 | 速度倍率 | 暴击倍率 | 专属技能 |
|----|------|-------|--------|--------|---------|---------|---------|---------|
| `cat` | 小猫咪 | 😺 | 青蓝(0,200,255) | 0.9 | 1.0 | 1.1 | 1.2 | multi_shot, piercing, crit_up, fire_rate, cat_scratch |
| `bean` | 黄豆勇士 | 😆 | 金黄(255,210,50) | 1.3 | 1.1 | 0.9 | 0.8 | grenade, shield, hp_up, hp_regen, bean_sprout |
| `monkey` | 灵猴大圣 | 🐵 | 橙色(255,140,50) | 0.8 | 0.9 | 1.35 | 1.0 | combo_hit, dodge_roll, clone_strike, speed_burst, big_bullet |
| `hand` | 无敌巨掌 | 🤚 | 紫粉(220,80,220) | 1.1 | 1.3 | 0.8 | 0.9 | palm_wave, grab_smash, finger_flick, iron_fist, thumb_up |
| `leaf` | 自然之灵 | 🍃 | 自然绿(60,200,80) | 1.0 | 0.95 | 1.05 | 1.0 | leaf_pierce, leaf_homing, xmas_tree, clover_luck, leaf_storm |
| `otto` | OTTO♿ | ♿ | 天蓝(100,180,255) | 1.2 | 0.85 | 0.85 | 0.9 | elephant_stomp, charm_enemy, slow_rider, otto_box, otto_sprint |

> **解锁条件**：`cat`、`bean`、`hand` 默认解锁；`monkey`、`leaf`、`otto` 需要完成 rep 链接解锁。

### 2.13.1 角色子弹贴图（bulletStyle）

每个角色有 4 种子弹风格，根据弹道类型自动切换：

| 角色 | normal（普通） | pierce（穿透） | spread（散射） | ricochet（弹射） |
|------|---------------|---------------|---------------|-----------------|
| 😺 小猫咪 | 🐟 青绿 | ⭐ 紫色 | 💫 粉色 | 🐳 青蓝 |
| 😆 黄豆勇士 | 🫘 金黄 | 🌟 橙色 | ✨ 淡黄 | 🧨 深橙 |
| 🐵 灵猴大圣 | 🍌 金色 | 🔥 红橙 | 🍿 淡橙 | 📣 橙色 |
| 🤚 无敌巨掌 | 👊 紫粉 | 🫴 亮粉 | ✋ 淡紫 | 🤘 紫色 |
| 🍃 自然之灵 | 🍃 绿色 | 🌿 深绿 | 🍂 秋黄 | 🍁 枫红 |
| ♿ OTTO | 💫 天蓝 | ⚡ 青蓝 | ✨ 淡紫 | 🥟 绿色 |

### 2.13.2 角色状态贴图（playerEmoji）

角色在不同状态下显示不同 emoji：

| 角色 | idle（待机） | move（移动） | hit（受伤） | overload（狂暴） | dead（死亡） | shield（护盾） |
|------|------------|------------|-----------|----------------|------------|--------------|
| 😺 小猫咪 | 😺 | 😸 | 🙀 | 😼 | 😿 | 😻 |
| 😆 黄豆勇士 | 😆 | 😄 | 😵 | 🤩 | 😵‍💫 | 😎 |
| 🐵 灵猴大圣 | 🐵 | 🐒 | 🙈 | 🙉 | 🙊 | 🐵 |
| 🤚 无敌巨掌 | 🤚 | ✊ | ✌ | 👋 | 👌 | 🤞 |
| 🍃 自然之灵 | 🍃 | 🌿 | 🍂 | 🌸 | 🥀 | 🍀 |
| ♿ OTTO | ♿ | 🚾 | 🛐 | ㊙️ | ⁉️ | 🔰 |

### 2.14 技能定义（SKILLS / 技能）

#### 通用技能（所有角色共享）

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `atk_drone` | 攻击无人机 | 🛸 | weapon | 3 | `baseDmg=0.5, interval=1.0` |
| `atk_up` | 攻击提升 | ⚔️ | passive | 5 | `atkBonus=0.10`（每级+10%） |
| `speed_up` | 移速提升 | 👟 | passive | 5 | `speedBonus=0.05`（每级+5%） |
| `magnet` | 磁力增强 | 🧲 | passive | 3 | `magnetBonus=0.30`（每级+30%） |
| `ricochet` | 弹射弹 | 🔀 | weapon | 3 | `bounceCount=1`（与穿透互斥） |

#### 猫咪专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `multi_shot` | 多重射击 | 🔫 | weapon | 3 | `extraBullets=1` |
| `piercing` | 穿透弹 | 💠 | weapon | 3 | `pierceCount=1`（与弹射互斥） |
| `crit_up` | 暴击提升 | 🎯 | passive | 5 | `critBonus=0.05` |
| `fire_rate` | 射速提升 | 🔥 | passive | 3 | `fireRateBonus=0.15` |
| `cat_scratch` | 星爆猫爪 | 🐾 | weapon | 3 | `baseDmg=2.4, interval=3.0, radius=180, heartChance=0.20, atkSpeedBuff=0.05, buffDuration=5.0`（范围200%，每次CD积攒level轮，每0.3s释放一轮，无敌时积攒最多3×level轮；20%爆红心，叠加+5%攻速5s） |

#### 黄豆专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `grenade` | 手雷 | 💣 | weapon | 3 | `baseDmg=2.0, interval=5.0, radius=80`（碰敌即炸+击退，等级=同时投掷数量） |
| `shield` | 力场护盾 | 🛡️ | defense | 3 | `interval=10.0, charges=1` |
| `hp_up` | 生命提升 | ❤️ | passive | 5 | `hpBonus=0.10` |
| `hp_regen` | 生命恢复 | 💚 | defense | 3 | `regenPercent=0.01` |
| `bean_sprout` | 豆芽陷阱 | 🌱 | weapon | 3 | `baseDmg=1.5, interval=4.0, maxTraps=3`（检测半径30不变，伤害范围半径翻倍） |

#### 猴子专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `combo_hit` | 连击拳 | 👊 | weapon | 3 | `extraBullets=1` |
| `dodge_roll` | 闪避翻滚 | 💨 | passive | 5 | `speedBonus=0.07, critBonus=0.02`（每级+7%移速+2%暴击） |
| `clone_strike` | 分身打击 | 🐒 | weapon | 3 | `baseDmg=0.2, interval=0.6` |
| `speed_burst` | 极速爆发 | ⚡ | passive | 3 | `fireRateBonus=0.20` |
| `big_bullet` | 巨弹强袭 | 🎯 | passive | 5 | `bigBulletChance=0.02`（2%概率发射3倍大子弹） |

#### 巨掌专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `palm_wave` | 掌风波 | 🌊 | weapon | 3 | `pierceCount=1`（与弹射互斥） |
| `grab_smash` | 太极拳 | 🫴 | weapon | 3 | `detectRadius=50, baseCooldown=10.0, dmgMultiplier=6.0, waveSpeed=500, waveGrowRate=8.0, waveMaxScale=5.0`（被动：消除来袭敌弹并释放穿透暴击掌风波，等级=每10秒最大触发次数） |
| `finger_flick` | 弹指神功 | 👆 | passive | 5 | `critBonus=0.06` |
| `iron_fist` | 铁拳 | 🥊 | passive | 5 | `atkBonus=0.12` |
| `thumb_up` | 点赞弹幕 | 👍 | weapon | 3 | `baseDmg=0.6, interval=3.5, bulletCount=4`（弹量=4+2×level+extraBullets散射加成，每0.3s连射level轮，第一颗瞄准最近敌人，受穿透/弹射加成） |

#### 叶子专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `leaf_pierce` | 藤蔓穿刺 | 🌿 | weapon | 3 | `pierceCount=2`（每级+2穿透，上限3层） |
| `leaf_homing` | 自然追踪 | 🍁 | passive | 3 | `homingChance=0.25`（25%概率子弹0.3s后追踪敌人） |
| `xmas_tree` | 圣诞之树 | 🎄 | weapon | 3 | `baseDmg=1.0, interval=0.5, orbitRadius=100, iceBulletInterval=1.5`（召唤圣诞树环绕，发射冰弹冻结敌人） |
| `clover_luck` | 四叶幸运 | 🍀 | passive | 3 | `lootBonus=0.15`（每级+15%掉落物品概率） |
| `leaf_storm` | 霜瑟风暴 | 🌨️ | weapon | 3 | `radius=130`（冰霜风暴AoE，对范围内全体敌人造成1/3伤害并叠加冰冻） |

#### OTTO专属

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `elephant_stomp` | 大象踩背 | 🐘 | weapon | 5 | `summonChance=0.02, duration=10.0, dmgMultiplier=1.5, stompInterval=1.0, stompRadius=80, moveSpeed=60`（2%射击概率召唤大象，每秒AoE踩踏） |
| `charm_enemy` | 我喜欢你你喜欢我 | ❤ | passive | 3 | `maxCharmed=1`（击杀触发魅惑，上限=等级，近战6次/秒，远程射魅惑弹） |
| `slow_rider` | 慢行者 | 🐎 | weapon | 5 | `interval=4.0, dmgPerTick=1.0, tickRate=2.0, lockDuration=5.0, whirlRadius=60, horseSpeed=300`（骑马子弹锁定敌人，制造旋风伤害） |
| `otto_box` | 盒子 | 📦 | weapon | 3 | `maxBoxes=1, dmgRatio=0.5, mimicInterval=2.0`（在场地固定部署盒子，永久存在，复制僚机技能环绕盒子，伤害50%，上限=等级） |
| `otto_sprint` | 冲刺 | 🦽 | passive | 3 | `speedBonus=0.15`（被动移速+15%/级，可叠加3层=45%） |

#### 通用加成技能

| ID | 名称 | icon | 类型 | maxLevel | 效果参数 |
|----|------|------|------|----------|---------|
| `knockback` | 击退冲击 | 💥 | passive | 3 | `knockbackChance=0.05`（子弹命中5%概率击退敌人0.2秒） |

#### 技能总表（按功能分类，含关键字段）

按功能将所有技能分为四大类。`类型` = Config.SKILLS 中的 type 字段；`真专属` = signatureSkill，毕业跨角色符文不可授予。

##### 子弹加成类 — 直接增强主武器子弹属性

| ID | 名称 | icon | 所属角色 | 类型 | 真专属 | maxLevel | 关键字段 | 互斥 |
|----|------|------|---------|------|--------|----------|---------|------|
| `multi_shot` | 多重射击 | 🔫 | 猫咪 | weapon | - | 3 | `extraBullets=1`/级 | - |
| `piercing` | 穿透弹 | 💠 | 猫咪 | weapon | - | 3 | `pierceCount=1`/级 | ricochet |
| `ricochet` | 弹射弹 | 🔀 | 通用 | weapon | - | 3 | `bounceCount=1`/级 | piercing/palm_wave |
| `combo_hit` | 连击拳 | 👊 | 猴子 | weapon | - | 3 | `bounceCount=1`/级 | - |
| `palm_wave` | 掌风波 | 🌊 | 巨掌 | weapon | - | 3 | `pierceCount=1`/级 | ricochet |
| `leaf_pierce` | 藤蔓穿刺 | 🌿 | 叶子 | weapon | - | 3 | `pierceCount=2`/级，上限3层 | - |
| `leaf_homing` | 自然追踪 | 🍁 | 叶子 | passive | - | 3 | `homingChance=0.25`/级 | - |
| `big_bullet` | 巨弹强袭 | 🎯 | 猴子 | passive | - | 5 | `bigBulletChance=0.02`/级 | - |
| `fire_rate` | 射速提升 | 🔥 | 猫咪 | passive | - | 3 | `fireRateBonus=0.15`/级 | - |
| `speed_burst` | 极速爆发 | ⚡ | 猴子 | passive | - | 3 | `fireRateBonus=0.20`/级 | - |
| `thumb_up` | 点赞弹幕 | 👍 | 巨掌 | weapon | **是** | 3 | `baseDmg=0.6, interval=3.5, bulletCount=4+2×level+extraBullets` | - |

##### 僚机类 — 召唤独立攻击实体环绕/跟随

| ID | 名称 | icon | 所属角色 | 类型 | 真专属 | maxLevel | 关键字段 | 备注 |
|----|------|------|---------|------|--------|----------|---------|------|
| `atk_drone` | 攻击无人机 | 🛸 | 通用 | weapon | - | 3 | `baseDmg=0.5, interval=1.0` | 蓝色环绕激光 |
| `atk_drone_green` | 绿色无人机 | 🛩️ | 通用 | weapon | - | 3(动态) | `baseDmg=0.25, interval=1.0` | 需飞行遗物≥1，maxLevel=遗物等级+3 |
| `xmas_tree` | 圣诞之树 | 🎄 | 叶子 | weapon | - | 3 | `baseDmg=1.0, interval=0.5, orbitRadius=100, iceBulletInterval=1.5` | 环绕+冰弹冻结 |
| `clone_strike` | 分身打击 | 🐒 | 猴子 | weapon | **是** | 3 | `baseDmg=0.2, interval=0.6` | 射击分身，继承弹幕加成 |
| `elephant_stomp` | 大象踩背 | 🐘 | OTTO | weapon | - | 5 | `summonChance=0.02, duration=10.0, dmgMultiplier=1.5, stompRadius=120` | 2%射击召唤，每秒AoE |
| `charm_enemy` | 我喜欢你你喜欢我 | ❤ | OTTO | passive | - | 3 | `maxCharmed=等级` | 击杀触发魅惑（详见§10） |
| `otto_box` | 盒子 | 📦 | OTTO | passive | **是** | 3 | `maxBoxes=等级, dmgRatio=0.5, mimicInterval=2.0` | 部署固定点，复制僚机技能 |

> **盒子与僚机的关系**：`otto_box` 会复制 `atk_drone`/`xmas_tree`/`clone_strike` 以 50% 伤害在盒子位置施放。

##### 副武器类 — 独立CD的额外攻击手段

| ID | 名称 | icon | 所属角色 | 类型 | 真专属 | maxLevel | 关键字段 | 备注 |
|----|------|------|---------|------|--------|----------|---------|------|
| `cat_scratch` | 星爆猫爪 | ⭐ | 猫咪 | weapon | **是** | 3 | `baseDmg=2.4, interval=3.0, radius=180, heartChance=0.20` | 200%范围星爆，积攒连击，20%爆红心 |
| `grenade` | 手雷 | 💣 | 黄豆 | weapon | - | 3 | `baseDmg=2.0, interval=5.0, radius=80` | 碰敌即炸+击退，等级=同时投掷数 |
| `bean_sprout` | 豆芽陷阱 | 🌱 | 黄豆 | weapon | **是** | 3 | `baseDmg=1.5, interval=4.0, maxTraps=3` | 检测半径30，伤害范围翻倍 |
| `grab_smash` | 太极拳 | 🫴 | 巨掌 | weapon | - | 3 | `detectRadius=50, baseCooldown=10.0, dmgMultiplier=6.0` | 被动弹反：消敌弹→暴击掌风波 |
| `slow_rider` | 慢行者 | 🐎 | OTTO | weapon | - | 5 | `interval=4.0, lockDuration=5.0, whirlRadius=60, horseSpeed=300` | 骑马子弹锁定→旋风2次/秒 |
| `leaf_storm` | 霜瑟风暴 | 🌨️ | 叶子 | weapon | **是** | 3 | `radius=130` | 冰霜AoE，1/3伤害+叠加冰冻 |

##### 属性/生存类 — 防御、生存、数值增幅

| ID | 名称 | icon | 所属角色 | 类型 | maxLevel | 关键字段 | 备注 |
|----|------|------|---------|------|----------|---------|------|
| `atk_up` | 攻击提升 | ⚔️ | 通用 | passive | 5 | `atkBonus=0.10`/级 | - |
| `speed_up` | 移速提升 | 👟 | 通用 | passive | 5 | `speedBonus=0.05`/级 | - |
| `magnet` | 磁力增强 | 🧲 | 通用 | passive | 3 | `magnetBonus=0.30`/级 | - |
| `knockback` | 击退冲击 | 💥 | 通用 | passive | 3 | `knockbackChance=0.05`/级 | 命中击退0.2秒 |
| `crit_up` | 暴击提升 | 🎯 | 猫咪 | passive | 5 | `critBonus=0.05`/级 | - |
| `hp_up` | 生命提升 | ❤️ | 黄豆 | passive | 5 | `hpBonus=0.10`/级 | - |
| `hp_regen` | 生命恢复 | 💚 | 黄豆 | defense | 3 | `regenPercent=0.01`/级 | - |
| `shield` | 力场护盾 | 🛡️ | 黄豆 | defense | 3 | `interval=10.0, charges=1`/级 | - |
| `dodge_roll` | 闪避翻滚 | 💨 | 猴子 | passive | 5 | `speedBonus=0.07, critBonus=0.02`/级 | 双属性复合 |
| `finger_flick` | 弹指神功 | 👆 | 巨掌 | passive | 5 | `critBonus=0.06`/级 | - |
| `iron_fist` | 铁拳 | 🥊 | 巨掌 | passive | 5 | `atkBonus=0.12`/级 | - |
| `clover_luck` | 四叶幸运 | 🍀 | 叶子 | passive | 3 | `lootBonus=0.15`/级 | - |
| `otto_sprint` | 冲刺 | 🦽 | OTTO | passive | 3 | `speedBonus=0.15`/级 | 叠加上限3层=45% |

##### 毕业跨角色解锁池

| 池 | 配置字段 | 包含技能 |
|----|---------|---------|
| 射弹加成 | `GRADUATION_WEAPON_SKILLS` | multi_shot, piercing, combo_hit, palm_wave, leaf_pierce, leaf_homing |
| CD触发 | `GRADUATION_CD_SKILLS` | grenade, bean_sprout, grab_smash, xmas_tree, charm_enemy, slow_rider, otto_box, otto_sprint |
| 不可跨角色 | signatureSkill | cat_scratch, bean_sprout, clone_strike, thumb_up, leaf_storm, otto_box（标记`真专属`的技能） |

> **注**: `shield`（护盾）不在毕业池中，仅黄豆自带。

### 2.15 赛博朋克配色（COLORS / 配色）

| 变量名 | 中文简称 | RGBA值 |
|--------|---------|--------|
| `COLORS.bg` | 深暗紫背景 | (10, 8, 25, 255) |
| `COLORS.bgGrid` | 背景网格 | (30, 20, 60, 80) |
| `COLORS.neonBlue` | 霓虹蓝 | (0, 200, 255, 255) |
| `COLORS.neonPurple` | 霓虹紫 | (180, 50, 255, 255) |
| `COLORS.neonPink` | 霓虹粉 | (255, 50, 150, 255) |
| `COLORS.neonGreen` | 霓虹绿 | (0, 255, 150, 255) |
| `COLORS.neonOrange` | 霓虹橙 | (255, 150, 0, 255) |
| `COLORS.neonRed` | 霓虹红 | (255, 50, 50, 255) |
| `COLORS.neonYellow` | 霓虹黄 | (255, 255, 50, 255) |
| `COLORS.neonCyan` | 霓虹青 | (0, 255, 255, 255) |
| `COLORS.hpBar` | 血条绿 | (50, 255, 100, 255) |
| `COLORS.expBar` | 经验条蓝 | (100, 150, 255, 255) |
| `COLORS.overloadBar` | 过载条橙 | (255, 150, 0, 255) |
| `COLORS.enemyBoss` | Boss色 | (255, 50, 150, 255) |

---

## 3. 战斗状态机（BattleScene.state）

| 常量 | 值 | 中文名 | 说明 |
|------|----|--------|------|
| `STATE_PLAYING` | 1 | 战斗中 | 正常游戏 |
| `STATE_SKILL_SELECT` | 2 | 技能选择 | 升级时暂停，3选1 |
| `STATE_PAUSED` | 3 | 暂停 | 手动暂停 |
| `STATE_GAME_OVER` | 4 | 游戏结束 | 玩家死亡 |
| `STATE_VICTORY` | 5 | 胜利 | 通关（击败最终Boss） |
| `STATE_GRADUATION` | 6 | 毕业Build | 毕业阶段 |
| `STATE_GIFT_AD` | 7 | 广告礼物 | 礼物盒弹窗 |
| `STATE_ULTIMATE` | 8 | 终极奖励 | 毕业终极选择 |

---

## 4. 关键运行时变量

### 4.1 Player 运行时状态

| 变量名 | 中文简称 | 说明 |
|--------|---------|------|
| `Player.x / Player.y` | 坐标 | 世界坐标位置 |
| `Player.hp / Player.maxHp` | 当前/最大血量 | 实时生命值 |
| `Player.atk` | 攻击力 | 经过等级和技能加成后的值 |
| `Player.speed` | 移速 | 经过加成后的值 |
| `Player.critRate` | 暴击率 | 经过加成后的值 |
| `Player.level / Player.exp` | 等级/经验 | 当前进度 |
| `Player.expToNext` | 升级经验 | 当前等级所需总经验 |
| `Player.kills` | 击杀数 | 总击杀统计 |
| `Player.overloadKills` | 过载进度 | 当前击杀计数（满100触发） |
| `Player.overloadActive` | 过载激活 | 是否处于过载状态 |
| `Player.attackInterval` | 实际攻击间隔 | 经过技能加成后 |
| `Player.extraBullets` | 额外子弹数 | 多重射击技能 |
| `Player.pierceCount` | 穿透次数 | 穿透弹技能 |
| `Player.bounceCount` | 弹射次数 | 弹射弹技能 |
| `Player.shieldCharges` | 护盾层数 | 力场护盾 |
| `Player.graduationPhase` | 毕业阶段 | 0=未毕业, 1=已毕业, 2=已领终极 |
| `Player.skills` | 技能表 | `{ skill_id = level }` |
| `Player.charId` | 角色ID | 当前选择的角色 |

### 4.2 Wave 运行时状态

| 变量名 | 中文简称 | 说明 |
|--------|---------|------|
| `Wave.waveNum` | 波次号 | 当前波次编号 |
| `Wave.timer` | 波次计时器 | 距下波剩余时间 |
| `Wave.totalTime` | 战斗总时间 | 秒（用于HUD显示MM:SS） |
| `Wave.waveCoeff` | 波次系数 | `1.0 + waveNum × 0.08` |
| `Wave.bossAlive` | Boss存活 | 当前是否有Boss |
| `Wave.gameOver` | 通关标记 | 最终Boss被击杀 |

### 4.3 Enemy 运行时状态

| 变量名 | 中文简称 | 说明 |
|--------|---------|------|
| `Enemy.active` | 活跃敌人列表 | 对象池管理 |
| `Enemy.currentBoss` | 当前Boss引用 | Boss敌人对象 |
| `Enemy.currentBossDef` | 当前Boss定义 | Config中的Boss定义 |

---

## 5. 波次阵容表（WAVE_TIERS）

| 波次范围 | 怪物组成 |
|---------|---------|
| 1~2 | 普通怪 100% |
| 3~4 | 普通怪 65%, 速敏 35% |
| 5~6 | 普通 30%, 速敏 20%, 蜂群 18%, 坦克 15%, 远程 17% |
| 7~9 | 普通 20%, 速敏 17%, 蜂群 13%, 坦克 10%, 冲锋 13%, 幽灵 12%, 远程 15% |
| 10~12 | 全怪种 + 巫师 12% + 精英 10% |
| 13+ | 精英 18% 最高权重，全怪种高强度 |

---

## 6. UI 布局参数

### 6.1 GiftAd 弹窗布局

| 变量名 | 中文简称 | 当前值 |
|--------|---------|--------|
| `PANEL_W` | 面板宽度 | 440 |
| `PANEL_H` | 面板高度 | 400 |
| `BTN_W` | 按钮宽度 | 340 |
| `BTN_H` | 按钮高度 | 68 |
| `BTN_GAP` | 按钮间距 | 20 |
| emoji 字号 | - | 76 |
| 标题字号 | - | 28 |
| 副标题字号 | - | 18 |
| 广告按钮字号 | - | 24 |
| 放弃按钮字号 | - | 20 |

### 6.2 SkillSelect 卡牌布局

| 变量名 | 中文简称 | 值（代码内 local 常量） |
|--------|---------|--------|
| `CARD_W` | 卡牌宽度 | 见 SkillSelect.lua |
| `CARD_H` | 卡牌高度 | 见 SkillSelect.lua |
| `CARD_GAP` | 卡牌间距 | 见 SkillSelect.lua |

### 6.3 HUD Boss 区域

| 参数 | 中文简称 | 当前值 |
|------|---------|--------|
| Boss技能图标大小 | skSize | 36 |
| Boss技能图标间距 | skGap | 8 |
| Boss技能字号 | - | 18 |
| Boss名称字体 | zpix | 白边黑字，左对齐叠加在血条上 |

---

## 7. 广告 SDK 集成

```lua
-- 流程：礼物盒拾取 → 弹窗 → 选择看广告/放弃
-- 看广告：调用 sdk:ShowRewardVideoAd(callback)
--   成功 → BattleScene.ResolveGift(true)
--   失败 → 模拟成功，同样 BattleScene.ResolveGift(true)
-- 放弃 → BattleScene.ResolveGift(false)
```

---

## 8. 音效列表（GameAudio）

| SFX名称 | 用途 |
|---------|------|
| `shoot` | 玩家射击 |
| `explosion` | 爆炸（手雷/炸弹） |
| `levelup` | 升级 |
| `player_hurt` | 玩家受伤 |
| `pickup` | 拾取物品 |
| `enemy_die` | 敌人死亡 |
| `boss_warning` | Boss出现警告 |

---

## 9. 如何使用本文档修改数值

1. 在本文档中找到要修改的参数，修改"当前值"列
2. 告知 AI："我修改了设计文档，请检查变更并实装"
3. AI 会对比文档与 Config.lua 的差异，将变更应用到代码中

### 修改示例

```
原始：Config.PLAYER.baseHp = 35
修改：Config.PLAYER.baseHp = 50
效果：玩家初始血量从35提升到50
```

> 注意：部分参数在 Config.lua 之外的文件中（如 HUD 布局常量在 HUD.lua 中），
> 文档已标注所在文件，AI 会根据标注找到正确文件修改。

---

## 10. 魅惑机制详解（charm_enemy）

> **技能名称**: 我喜欢你你喜欢我 ❤  
> **所属角色**: OTTO♿  
> **技能类型**: passive  
> **最大等级**: 3

### 10.1 核心规则

| 规则 | 说明 |
|------|------|
| 魅惑上限 | = 技能等级（1级=1只，2级=2只，3级=3只） |
| 触发条件 | 击杀任意非Boss、非已魅惑的敌人时自动触发 |
| Boss免疫 | Boss不可被魅惑 |

### 10.2 触发流程

```
击杀敌人
  ↓
Skill.TryCharmOnKill(enemy) 判定
  ├── Boss → 跳过
  ├── 已魅惑 → 跳过
  └── 可魅惑 ↓
      ↓
敌人恢复满血 → 标记 charmed + charmedInvincible
  ↓
触发淘汰判定：检索所有非召唤的魅惑敌人
  ├── 数量 ≤ 上限 → 全部保留
  └── 数量 > 上限 → 按 maxHP 降序排列，保留前N只，其余正常死亡
      ↓
被淘汰的魅惑敌人：取消魅惑标记 → 标记死亡 → 播放死亡特效
```

### 10.3 魅惑敌人状态

被魅惑的敌人拥有以下状态：

| 标记 | 值 | 效果 |
|------|-----|------|
| `charmed` | true | 标记为友方，跳过普通AI |
| `charmedInvincible` | true | 不可被玩家子弹/技能伤害 |
| `charmedIsSummon` | false/true | 是否为召唤产物（不占用魅惑上限） |

**魅惑敌人不可被瞄准**：玩家子弹、僚机、技能的索敌逻辑跳过 `charmed=true` 的敌人。

### 10.4 魅惑敌人行为

魅惑敌人的AI由 `Skill.lua` 的 charm_enemy Update 块控制，按敌人类型区分行为：

#### 索敌规则（所有类型通用）

- 目标：距离自身最近的、血量 > 0 的、未被魅惑的单个敌人
- 无有效目标时：原地待命

#### 近战类（除 ranger 外所有类型）

| 参数 | 值 | 说明 |
|------|-----|------|
| 移动 | 追向目标 | 使用自身 speed 属性 |
| 攻击频率 | 6次/秒 | `charmTickInterval = 1/6` |
| 攻击伤害 | 自身 atk | `math.floor(ce.atk)` |
| 攻击范围 | 自身 radius + 目标 radius + 10 | 接触判定 |
| 攻击目标 | 范围内所有非魅惑、血量>0的敌人 | AoE |

#### 远程类（ranger）

| 参数 | 值 | 说明 |
|------|-----|------|
| 移动 | 保持距离（keepDistance） | 太近则后退，太远则追近 |
| 射击间隔 | `shootInterval`（默认2.0s） | 来自敌人类型定义 |
| 射击范围 | `shootRange`（默认250） | 超出范围不射击 |
| 弹速 | `bulletSpeed`（默认280） | 来自敌人类型定义 |
| 弹幕外观 | 💗 粉色 | `{255, 100, 200}` |

#### 魅惑子弹（charmedBullet）

| 属性 | 说明 |
|------|------|
| 标记 | `charmedBullet = true` |
| 碰撞目标 | 仅碰撞非魅惑、血量>0的敌人 |
| 无视阻挡 | 跳过 blocker 碰撞检测 |
| 不伤友方 | 跳过玩家碰撞检测 |
| 击杀处理 | 触发 HandleKills → 可连锁魅惑新敌人 |

### 10.5 召唤类敌人的魅惑（预留）

> 当前版本尚无召唤类敌人（summoner），但基础设施已就位。

- 被魅惑的召唤类敌人所召唤的单位也自动被魅惑
- 召唤产物的 `charmedIsSummon = true`，**不占用魅惑上限**
- 淘汰判定时只计算 `charmedIsSummon = false` 的敌人

### 10.6 代码位置索引

| 功能 | 文件 | 函数/位置 |
|------|------|----------|
| 魅惑AI行为 | `Skill.lua` | charm_enemy Update 块（~1107行） |
| 击杀触发魅惑 | `Skill.lua` | `Skill.TryCharmOnKill()` |
| HandleKills调用 | `BattleScene.lua` | `HandleKills()` |
| 魅惑子弹碰撞 | `EnemyBullet.lua` | `EnemyBullet.Update()` charmedBullet 分支 |
| 跳过普通AI | `Enemy.lua` | Update 循环中 `if e.charmed then goto continue` |
| 技能配置 | `Config.lua` | `SKILLS.charm_enemy` |

---

## 11. 遗物系统（RelicSystem）

> **定义文件**: `scripts/meta/RelicSystem.lua`  
> **存档接口**: `SaveData.lua` → `SyncMetaToCloud()` / `OnCloudScoreReady()`  
> **用途**: 局外永久养成。通过局内金币🪙购买升级，提供跨局永久加成。

### 11.1 遗物列表

| ID | 名称 | 图标 | 费用基数 | 效果 |
|----|------|------|---------|------|
| `strength` | 力量遗物 | ⚔️ | 2 | 每级全局攻击 +0.2% |
| `agility` | 敏捷遗物 | 🎯 | 2 | 每级暴击率 +0.2% |
| `vitality` | 生命遗物 | ❤️ | 2 | 每级基础生命 +0.25% |
| `speed` | 速度遗物 | ⚡ | 2 | 每级攻击间隔 -0.5%，移速 +0.5% |
| `guardian` | 守护遗物 | 🛡️ | 1000 | 每波开始获得 N 次护卫充能（N=等级），单次受伤降为1 |
| `flight` | 飞行遗物 | 🛸 | 1000 | 解锁绿色无人机，等级上限 = 遗物等级+3（需≥1级） |

### 11.2 费用公式

```
cost = base ^ (currentLevel + 1)
```

| 基数 | 类型 | 升级费用示例 |
|------|------|-------------|
| base=2 | 普通遗物 (strength/agility/vitality/speed) | Lv0→1: 2, Lv1→2: 4, Lv2→3: 8, Lv3→4: 16, Lv4→5: 32 ... |
| base=1000 | 特殊遗物 (guardian/flight) | Lv0→1: 1000, Lv1→2: 1000000（极难） |

### 11.3 加成机制（ApplyBonusesToPlayer）

战斗开始时由 `BattleScene.Init → Player.Init` 之后调用，写入 Player 专属字段：

| 遗物 | Player 字段 | 公式 |
|------|------------|------|
| strength | `relicAtkBonus` | `0.002 × level`（百分比乘算） |
| agility | `relicCritBonus` | `0.002 × level`（百分比加算） |
| vitality | `relicHpBonus` | `0.0025 × level`（百分比乘算） |
| speed | `relicFireRateBonus` | `0.005 × level`（攻击间隔减少比例） |
| speed | `relicSpeedBonus` | `0.005 × level`（移速增加比例） |
| guardian | `guardianMaxCharges` | `= level`（每波充能上限） |
| flight | 绿色无人机等级上限 | `GetGreenDroneMaxLevel() = level + 3`（需 level≥1） |

### 11.4 云端存储

| 项目 | 存储方式 | 云端 key | 同步策略 |
|------|---------|---------|---------|
| 遗物等级 | `SetInt` → `iscores` | `CLOUD_KEY_RELIC_PREFIX .. relicId` | `math.max(local, cloud)` 取较高值 |

- 使用 `SetInt` / `iscores` 存储，值类型始终是 number，不存在 JSON 自动解码问题
- 同步策略为**取最大值合并**，保证玩家不会丢失升级进度

---

## 12. 图腾系统（TotemSystem）

> **定义文件**: `scripts/meta/TotemSystem.lua`  
> **存档接口**: `SaveData.lua` → `SyncMetaToCloud()` / `OnCloudScoreReady()`  
> **用途**: 局外养成+装备系统。Boss击杀掉落图腾，可合成、出售、装备，提供开局加成。

### 12.1 稀有度定义

| 稀有度 | 常量 | 中文名 | 掉落权重 | 出售价格 | 颜色 RGB |
|--------|------|--------|---------|---------|---------|
| `junk` | RARITY.JUNK | 垃圾 | 60 (60%) | 10🪙 | (140, 140, 140) |
| `normal` | RARITY.NORMAL | 普通 | 30 (30%) | 100🪙 | (180, 180, 180) |
| `rare` | RARITY.RARE | 稀有 | 9 (9%) | 1000🪙 | (80, 160, 255) |
| `legendary` | RARITY.LEGENDARY | 罕见 | 1 (1%) | 10000🪙 | (255, 160, 30) |

### 12.2 类型定义

图腾分为 3 大类共 10 种类型：

#### 数值类（stat）

| typeId | 名称 | 图标 | 效果 |
|--------|------|------|------|
| `hp` | 生命 | ❤️ | 初始HP增加 |
| `atk` | 攻击 | ⚔️ | 初始ATK增加 |
| `spd` | 速度 | 👟 | 初始SPD增加 |

#### 技能类（skill）

| typeId | 名称 | 图标 | 效果 |
|--------|------|------|------|
| `atk_up` | 攻击提升 | ⚔️ | 开局携带一级攻击提升 |
| `speed_up` | 移速提升 | 👟 | 开局携带一级移速提升 |
| `magnet` | 磁力增强 | 🧲 | 开局携带一级磁力增强 |
| `knockback` | 击退冲击 | 💥 | 开局携带一级击退冲击 |
| `atk_drone` | 攻击无人机 | 🛸 | 开局携带一级攻击无人机 |

#### 特殊类（special）

| typeId | 名称 | 图标 | 效果 |
|--------|------|------|------|
| `cross_class` | 异界天赋 | 🌀 | 未毕业即可学习其他角色技能 |

### 12.3 各稀有度可掉落类型池

| 稀有度 | 可掉落类型 |
|--------|-----------|
| junk | hp, atk, spd |
| normal | hp, atk, spd, atk_up, speed_up, magnet, knockback |
| rare | hp, atk, spd, atk_drone |
| legendary | hp, atk, spd, cross_class |

### 12.4 数值表（稀有度 × 类型 → 加成值）

仅数值类（stat）使用此表，技能类固定返回1（=1级），特殊类返回0。

| 稀有度 | hp | atk | spd |
|--------|-----|------|------|
| junk | +5 | +1 | +10 |
| normal | +15 | +3 | +30 |
| rare | +50 | +10 | +80 |
| legendary | +150 | +30 | +200 |

### 12.5 背包与装备限制

| 参数 | 值 |
|------|-----|
| `MAX_INVENTORY` | 600 个 |
| `MAX_EQUIPPED` | 3 个 |

### 12.6 合成系统

**规则**: 3 个同稀有度图腾合成为 1 个新图腾，新图腾类型从目标稀有度的类型池中随机抽取。

| 概率 | 结果 | 备注 |
|------|------|------|
| 50% | 稀有度升一级 | junk→normal, normal→rare, rare→legendary |
| 40% | 稀有度不变 | 保持原稀有度 |
| 10% | 稀有度降一级 | normal→junk, rare→normal（junk 不降级） |

- **罕见（legendary）不可合成**
- 合成前需检查 `CanSynthesize(rarity, count)`: 非罕见 且 数量 ≥ 3

### 12.7 装备加成计算（CalcEquippedBonuses）

战斗开始时读取已装备图腾，返回五个值：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| `hpFlat` | number | 所有数值类 hp 图腾的加成总和 |
| `atkFlat` | number | 所有数值类 atk 图腾的加成总和 |
| `spdFlat` | number | 所有数值类 spd 图腾的加成总和 |
| `skillTotems` | table | 技能类图腾的 typeId 列表（开局自动学习这些技能1级） |
| `hasCrossClass` | boolean | 是否装备了异界天赋图腾（未毕业可跨职业学技能） |

### 12.8 云端存储

| 项目 | 存储方式 | 云端 key | 数据格式 |
|------|---------|---------|---------|
| 图腾背包 | `Set` → `values` | `CLOUD_KEY_TOTEMS_V2` | 聚合计数 JSON：`{"hp_junk":42, "atk_normal":5, ...}` |
| 已装备图腾 | `Set` → `values` | `CLOUD_KEY_EQUIPPED_V2` | 数组 JSON：`[{"typeId":"hp","rarity":"rare"}, ...]` |

**聚合编码**：
- `AggregateTotems(totems)`: 将 `[{typeId, rarity}, ...]` 聚合为 `{"hp_junk":N, ...}` 计数表
- `ExpandTotems(counts)`: 从计数表展开为图腾数组，使用 `VALID_TOTEM_KEYS` 验证合法性

**同步策略**：本地优先（local-authoritative）
- 本地有数据 → 保留本地，不使用云端
- 本地为空 → 从云端恢复

**⚠️ 类型注意**：`Set` 存储的 table/数组会被引擎自动 JSON 编解码，读取时 `values[key]` 可能是 `table` 也可能是 `string`，代码需同时处理两种类型（已在 SaveData.lua 修复）
