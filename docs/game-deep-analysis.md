# Emoji幸存者 - 深度解析文档

> 本文档对 `/workspace/scripts/` 目录下的完整游戏系统进行深度剖析，涵盖所有实体数据、管理机制、词条系统和触发逻辑链。

---

## 目录

1. [架构总览](#1-架构总览)
2. [角色系统完整数据](#2-角色系统完整数据)
3. [敌人系统完整数据](#3-敌人系统完整数据)
4. [Boss系统完整数据](#4-boss系统完整数据)
5. [技能系统完整数据](#5-技能系统完整数据)
6. [符文系统完整数据](#6-符文系统完整数据)
7. [符文共鸣系统](#7-符文共鸣系统)
8. [图腾背包系统](#8-图腾背包系统)
9. [遗物永久升级系统](#9-遗物永久升级系统)
10. [波次调度系统](#10-波次调度系统)
11. [实体管理架构](#11-实体管理架构)
12. [触发逻辑链完整图谱](#12-触发逻辑链完整图谱)
13. [数值公式汇总](#13-数值公式汇总)

---

## 1. 架构总览

### 1.1 游戏类型
- **类型**: 吸血鬼幸存者（Vampire Survivors）式 Roguelite
- **渲染**: 纯 NanoVG 2D 矢量渲染（所有实体为 Lua table + nvgText/nvgBeginPath）
- **坐标系**: 设计分辨率 720×1280（竖屏），世界尺寸 12000×12000 像素

### 1.2 核心文件结构

| 文件路径 | 职责 | 行数级别 |
|---------|------|---------|
| `scripts/Config.lua` | 全局数值配置（唯一数据源） | ~1666 |
| `scripts/main.lua` | 状态机总调度（13个游戏状态） | 大 |
| `scripts/battle/BattleScene.lua` | 战斗循环协调器 | 中 |
| `scripts/battle/Player.lua` | 玩家实体逻辑 | 中 |
| `scripts/battle/Enemy.lua` | 敌人对象池 + AI | 大 |
| `scripts/battle/Skill.lua` | 技能运行时逻辑 | 大 |
| `scripts/battle/Wave.lua` | 波次调度与敌人生成 | 中 |
| `scripts/battle/RuneEffects.lua` | 符文触发运行时 | 大 |
| `scripts/meta/RuneSystem.lua` | 14颗符文定义 | 中 |
| `scripts/meta/RuneResonance.lua` | 6组双符文共鸣 | 小 |
| `scripts/meta/TotemSystem.lua` | 图腾背包系统 | 中 |
| `scripts/meta/RelicSystem.lua` | 永久升级系统 | 小 |
| `scripts/meta/SkinSystem.lua` | 皮肤装饰系统 | 小 |

### 1.3 设计模式

| 模式 | 应用位置 | 说明 |
|------|---------|------|
| **对象池** | Enemy, Projectile, EnemyBullet, Loot, DamageNumber, Particle | 预分配 table 复用避免 GC |
| **空间哈希** | Enemy碰撞, RuneEffects AOE | Cantor配对网格(cellSize=200px) |
| **safeCall** | BattleScene.Update | pcall 包裹子系统防单模块崩溃 |
| **状态机** | main.lua(13状态), Boss技能(CD轮转) | 枚举式有限状态机 |
| **帧预算** | Skill.lua FRAME_COLLISION_BUDGET=2000 | 防单帧碰撞检测过载 |
| **帧级守卫** | RuneEffects._frameGuard | 防同帧重复触发 |

---

## 2. 角色系统完整数据

### 2.1 基础属性（Config.PLAYER）

| 属性 | 值 | 说明 |
|------|-----|------|
| radius | 18 | 碰撞半径(px) |
| baseHp | 35 | 基础生命 |
| baseAtk | 6 | 基础攻击 |
| baseSpeed | 280 | 移速(px/s) |
| baseCritRate | 0.05 | 暴击率5% |
| critDamage | 2.0 | 暴击伤害倍率 |
| attackInterval | 0.5 | 攻击间隔(s) |
| attackRange | 350 | 攻击范围(px) |
| magnetRange | 80 | 磁吸范围(px) |
| invincibleTime | 0.8 | 受击无敌(s) |

### 2.2 六大角色定义

| # | ID | 名称 | Emoji | HP倍率 | ATK倍率 | SPD倍率 | CRIT倍率 | 定位 |
|---|-----|------|-------|--------|---------|---------|----------|------|
| 1 | cat | 小猫咪 | 😺 | 0.9 | 1.0 | 1.1 | 1.2 | 弹幕高手 |
| 2 | bean | 黄豆勇士 | 😆 | 1.3 | 1.1 | 0.9 | 0.8 | 爆炸坦克 |
| 3 | monkey | 灵猴大圣 | 🐵 | 0.8 | 0.9 | 1.35 | 1.0 | 极速闪避 |
| 4 | hand | 无敌巨掌 | 🤚 | 1.1 | 1.3 | 0.8 | 0.9 | 力量碾压 |
| 5 | leaf | 自然之灵 | 🍃 | 1.0 | 0.95 | 1.05 | 1.0 | 冰霜控制 |
| 6 | otto | OTTO♿ | ♿ | 1.2 | 0.85 | 0.85 | 0.9 | 召唤大军 |

### 2.3 角色专属技能池

| 角色 | 专属技能 (exclusiveSkills) | 真专属 (signatureSkill) |
|------|--------------------------|----------------------|
| cat | multi_shot, piercing, crit_up, fire_rate, **cat_scratch** | cat_scratch |
| bean | grenade, shield, hp_up, hp_regen, **bean_sprout** | bean_sprout |
| monkey | combo_hit, dodge_roll, **clone_strike**, speed_burst, big_bullet | clone_strike |
| hand | palm_wave, **grab_smash**, finger_flick, iron_fist, **thumb_up** | thumb_up |
| leaf | leaf_pierce, leaf_homing, xmas_tree, clover_luck, **leaf_storm** | leaf_storm |
| otto | **elephant_stomp**, charm_enemy, slow_rider, **otto_box**, otto_sprint | otto_box |

> **真专属（signatureSkill）**：毕业跨角色符文不会授予此技能。

### 2.4 通用技能池

所有角色共享：`atk_drone`, `atk_up`, `speed_up`, `magnet`, `knockback`

### 2.5 子弹风格系统

每角色有 4 种子弹外观变体：

| 变体 | 触发条件 | 视觉特征 |
|------|---------|---------|
| normal | 默认 | 基础颜色+标准大小 |
| pierce | 穿透弹 | 高亮色+大1.15倍 |
| spread | 散射弹 | 柔和色+小0.9倍 |
| ricochet | 弹射弹 | 对比色+大1.1倍 |

### 2.6 角色状态 Emoji

每角色有 6 个状态 Emoji：`idle`, `move`, `hit`, `overload`, `dead`, `shield`

---

## 3. 敌人系统完整数据

### 3.1 九大敌人类型

| # | 类型 | Emoji池 | 半径 | HP | ATK | 速度 | 经验 | 特殊机制 |
|---|------|---------|------|-----|-----|------|------|---------|
| 1 | normal | 👾👻🤖💀 | 14 | 16 | 3 | 100 | 2 | 直线追踪 |
| 2 | fast | 🦇⚡🐍🐺 | 10 | 8 | 2 | 180 | 2 | 高速追踪 |
| 3 | tank | 🐻🦍🐂🪨 | 22 | 40 | 5 | 60 | 4 | 高血量慢速 |
| 4 | swarm | 🐜🪲🦟🐛 | 8 | 5 | 1 | 160 | 1 | 成群出现 |
| 5 | charger | 🦏🐗🐃 | 18 | 24 | 8 | 50→200 | 3 | 蓄力冲刺(速度×4) |
| 6 | ghost | 👻🫥💨 | 12 | 12 | 4 | 70 | 3 | 随机闪现 |
| 7 | shaman | 🧙🔮☠️ | 14 | 20 | 6 | 80 | 4 | 环绕+突进 |
| 8 | ranger | 🏹🎯🔫 | 12 | 14 | 5 | 90 | 3 | 保持距离射击 |
| 9 | elite | 👹🐉😈🦾 | 20 | 100 | 8 | 90 | 10 | 精英词缀 |

### 3.2 远程怪(ranger)特有参数

| 参数 | 值 | 说明 |
|------|-----|------|
| shootInterval | 2.0s | 射击间隔 |
| shootRange | 250px | 射击距离 |
| keepDistance | 180px | 保持距离 |
| bulletSpeed | 280px/s | 弹幕速度 |

### 3.3 冲锋怪(charger)行为状态机

```
idle(50px/s) → 蓄力(停顿) → 冲刺(200px/s=50×4) → 冷却 → idle
```

状态字段：`chargeState`, `chargeDirX`, `chargeDirY`, `dashCooldown`

### 3.4 幽灵怪(ghost)行为

```
普通移动(70px/s) → blinkTimer到期 → 随机传送 → 继续移动
```

状态字段：`blinkTimer`

### 3.5 精英怪(elite)词缀系统

| 词缀ID | 名称 | 效果 |
|--------|------|------|
| aura_heal | 治愈光环 | 周期性治愈周围友军 |
| aura_speed | 加速光环 | 加速周围友军移速 |
| shield | 护盾 | 额外护盾层(shieldHp/shieldMaxHp) |
| enrage | 狂暴 | HP低于阈值时进入狂暴状态 |

字段：`eliteMod`, `shieldHp`, `shieldMaxHp`, `eliteAuraTimer`, `enraged`

### 3.6 敌人冰冻系统

| 参数 | 值 | 说明 |
|------|-----|------|
| freezeStacks | 累计叠层 | 决定减速程度 |
| freezeTimer | 冰冻计时 | 冰冻持续时间 |
| freezeImmunityCD | 7s | 被冻后免疫冷却 |
| freezeCount | 已冻次数 | 用于免疫判断 |
| freezeDecayTimer | 2s | 冰冻层自然衰减 |

### 3.7 敌人对象结构

```lua
Enemy = {
    -- 基础属性
    x, y,                    -- 位置
    hp, maxHp,               -- 生命
    atk,                     -- 攻击力
    speed,                   -- 移动速度
    radius,                  -- 碰撞半径
    expDrop,                 -- 经验掉落
    typeName,                -- 类型名
    alive,                   -- 存活标记
    hitFlash,                -- 受击闪白
    emoji,                   -- 显示emoji
    
    -- 行为系统
    behaviorTimer,           -- 行为计时器
    behaviorPhase,           -- 行为阶段
    dashCooldown,            -- 冲刺冷却
    
    -- 冰冻系统
    freezeStacks, freezeTimer, freezeImmunityCD, freezeCount, freezeDecayTimer,
    
    -- 击退系统
    knockbackTimer, knockbackDirX, knockbackDirY,
    
    -- Boss专属
    isBoss, bossDef, bossSkillTimers[], bossStunTimer, bossDashing, bossBurstQueue[],
}
```

---

## 4. Boss系统完整数据

### 4.1 Boss通用属性

| 属性 | 值 | 说明 |
|------|-----|------|
| radius | 36 | 碰撞半径 |
| baseHp | 2000 | 基础生命 |
| speed | 75 | 移动速度 |
| expDrop | 100 | 经验掉落 |
| 出现间隔 | 每10波 | 轮换14个Boss |

### 4.2 完整Boss列表

| # | ID | 名称 | Emoji | 波次 | 技能1 | 技能2 | 大招 |
|---|-----|------|-------|------|-------|-------|------|
| 1 | police | 巡逻警官 | 👮‍♀️ | 10 | 警笛弹幕(扇形5发) | 追击封锁(连射3发) | 全域通缉(360°16发) |
| 2 | worker | 重装工头 | 👷‍♂️ | 20 | 砖块投掷(慢速大弹) | 钻头冲刺(dash) | 建筑崩塌(12碎石rain) |
| 3 | chef | 地狱厨神 | 👨‍🍳 | 30 | 飞刀投射(快速2发) | 火焰喷射(扇形8发) | 致命料理(毒圈3s) |
| 4 | programmer | 代码狂魔 | 👨‍💻 | 40 | Bug弹幕(扇形3发) | 递归炸弹(分裂4) | 蓝屏死机(360°24发) |
| 5 | firefighter | 烈焰战士 | 👨‍🚒 | 50 | 水枪喷射(连射4发) | 消防斧冲击(dash) | 灭世大火(15火球rain) |
| 6 | vampire | 暗夜伯爵 | 🧛‍♀️ | 60 | 蝙蝠群(扇形6发) | 暗影传送(blink+8发) | 鲜血狂宴(360°20发+吸血5%) |
| 7 | gentleman | 暗影绅士 | 🤵‍♂️ | 70 | 扑克飞弹(连射3发) | 魔术消失(blink+4发) | 终极礼花(360°36发) |
| 8 | scientist | 疯狂博士 | 🧑‍🔬 | 80 | 试管投射(连射3发) | 基因裂变(分裂6) | 核聚变(360°28发) |
| 9 | pirate | 深海船长 | 🏴‍☠️ | 90 | 加农炮(扇形7发) | 船锚冲击(dash) | 暴风骤雨(18炮弹rain) |
| 10 | dj | 电音狂魔 | 🎧 | 100 | 音波冲击(扇形5发) | 低音重炮(blink+10发) | 终极混音(360°32发) |
| 11 | doctor | 暗黑医师 | 👨‍⚕️ | 110 | 注射针(连射4发) | 瘟疫扩散(毒圈3.5s) | 起死回生(360°24发+吸血8%) |
| 12 | ninja | 暗影忍者 | 🥷 | 120 | 手里剑(扇形4发) | 影分身(blink+6发) | 千本樱(20樱花rain) |
| 13 | robot | 歼灭者T-X | 🤖 | 130 | 激光扫射(连射5发) | 火箭弹(分裂8) | 终极歼灭(360°40发) |
| 14 | demon_king | 深渊魔王 | 👿 | 140 | 地狱火扇(扇形8发) | 暗影冲锋(dash) | 末日审判(22陨石rain+30发) |

### 4.3 Boss技能类型字典

| 技能类型 | 描述 | 关键参数 |
|---------|------|---------|
| shoot_fan | 扇形弹幕 | bulletCount, spreadAngle, bulletSpeed, damage |
| shoot_burst | 连发弹幕 | bulletCount, burstDelay, bulletSpeed, damage |
| shoot_radial | 360°散射 | bulletCount, bulletSpeed, damage |
| shoot_split | 分裂弹 | bulletSpeed, damage, splitCount, splitSpeed, splitDamage |
| shoot_target | 瞄准射击 | bulletCount, bulletSpeed, damage, bulletRadius |
| area_rain | 区域落弹 | count, damage, radius, spawnRange, fallDuration |
| area_circle | 持续毒圈 | damage, radius, duration, tickInterval |
| dash | 冲刺 | dashSpeed, dashDuration, damage, dashRadius |
| blink_attack | 传送+弹幕 | blinkRange, bulletCount, bulletSpeed, damage |

### 4.4 Boss行为规则

1. **无接触伤害** - Boss仅通过技能造成伤害
2. **大招自眩晕** - 使用 isUltimate 技能后自我眩晕 5 秒（stunDuration=5.0）
3. **循环轮换** - 超过14个Boss后从头循环，系数持续增长
4. **血量缩放** - baseHp × (1 + waveCoeff)，waveCoeff = wave × 0.08

---

## 5. 技能系统完整数据

### 5.1 技能分类

| 类型 | 数量 | 说明 |
|------|------|------|
| weapon | 16 | 主动武器/召唤物 |
| defense | 2 | 护盾/回血 |
| passive | 14 | 被动属性加成 |

### 5.2 完整技能表

#### 武器类 (weapon)

| ID | 名称 | Icon | 等级上限 | 核心效果 | 所属角色 |
|----|------|------|---------|---------|---------|
| atk_drone | 攻击无人机 | 🛸 | 3 | dmg=50%ATK, 间隔1s | 通用 |
| atk_drone_green | 绿色无人机 | 🛩️ | 3(动态) | dmg=25%ATK, 间隔1s, 大轨道 | 遗物解锁 |
| grenade | 手雷 | 💣 | 3 | dmg=200%ATK, 间隔5s, r=80 | bean |
| multi_shot | 多重射击 | 🔫 | 3 | 额外子弹+1/级 | cat |
| piercing | 穿透弹 | 💠 | 3 | 穿透+1/级 | cat |
| ricochet | 弹射弹 | 🔀 | 3 | 弹射+1/级 | 通用 |
| cat_scratch | 星爆猫爪 | ⭐ | 3 | 200%范围爆,间隔3s,r=180,心20%,攻速buff | cat(真专属) |
| bean_sprout | 豆芽陷阱 | 🌱 | 3 | 150%dmg,间隔4s,上限3陷阱 | bean(真专属) |
| combo_hit | 连击拳 | 👊 | 3 | 弹射+1/级 | monkey |
| clone_strike | 分身打击 | 🐒 | 3 | 20%dmg,间隔0.6s,继承弹幕 | monkey(真专属) |
| palm_wave | 掌风波 | 🌊 | 3 | 穿透+1/级 | hand |
| grab_smash | 太极拳 | 🫴 | 3 | 消弹→6倍掌风波,CD10s,波速500 | hand |
| thumb_up | 点赞弹幕 | 👍 | 3 | 60%dmg,间隔3.5s,4发连射 | hand(真专属) |
| xmas_tree | 圣诞之树 | 🎄 | 3 | 100%dmg,环绕r=100,冰弹间隔1.5s | leaf |
| leaf_storm | 霜瑟风暴 | 🌨️ | 3 | AOE r=130,1/3伤害+叠冰冻 | leaf(真专属) |
| elephant_stomp | 大象踩背 | 🐘 | 5 | 2%射击召唤,10s,1.5×dmg/s,r=120 | otto |
| slow_rider | 慢行者 | 🐎 | 5 | 间隔4s,骑马锁定5s,旋风2次/s | otto |

#### 防御类 (defense)

| ID | 名称 | Icon | 等级上限 | 核心效果 |
|----|------|------|---------|---------|
| shield | 力场护盾 | 🛡️ | 3 | 间隔10s,每次1层 |
| hp_regen | 生命恢复 | 💚 | 3 | 每秒回复1%maxHP |

#### 被动类 (passive)

| ID | 名称 | Icon | 等级上限 | 每级效果 | 所属角色 |
|----|------|------|---------|---------|---------|
| atk_up | 攻击提升 | ⚔️ | 5 | ATK+10% | 通用 |
| hp_up | 生命提升 | ❤️ | 5 | HP+10% | bean |
| speed_up | 移速提升 | 👟 | 5 | SPD+5% | 通用 |
| crit_up | 暴击提升 | 🎯 | 5 | 暴击率+5% | cat |
| magnet | 磁力增强 | 🧲 | 3 | 磁吸范围+30% | 通用 |
| fire_rate | 射速提升 | 🔥 | 3 | 攻击间隔-15% | cat |
| knockback | 击退冲击 | 💥 | 3 | 5%概率击退0.2s | 通用 |
| dodge_roll | 闪避翻滚 | 💨 | 5 | SPD+7%,暴击+2% | monkey |
| speed_burst | 极速爆发 | ⚡ | 3 | 攻击间隔-20% | monkey |
| finger_flick | 弹指神功 | 👆 | 5 | 暴击率+6% | hand |
| iron_fist | 铁拳 | 🥊 | 5 | ATK+12% | hand |
| big_bullet | 巨弹强袭 | 🎯 | 5 | 2%发射3倍大弹+0.2%maxHP伤害 | monkey |
| leaf_pierce | 藤蔓穿刺 | 🌿 | 3 | 穿透+2(上限3层) | leaf |
| leaf_homing | 自然追踪 | 🍁 | 3 | 25%概率追踪 | leaf |
| clover_luck | 四叶幸运 | 🍀 | 3 | 掉率+15% | leaf |
| charm_enemy | 魅惑 | ❤ | 3 | 击杀魅惑,上限=等级 | otto |
| otto_box | 盒子 | 📦 | 3 | 复制僚机,dmg50%,上限=等级 | otto(真专属) |
| otto_sprint | 冲刺 | 🦽 | 3 | SPD+15%/级(上限45%) | otto |

### 5.3 毕业Build系统

**触发条件**: 收集完当前角色所有专属技能后解锁跨职业技能池。

| 参数 | 值 | 说明 |
|------|-----|------|
| DRONE_MAX_LEVEL_GRAD | 6 | 无人机等级上限3→6 |
| MAX3_UPGRADED | 4 | 上限3的技能→4 |
| MAX5_UPGRADED | 7 | 上限5的技能→7 |
| ULTIMATE_HEAL_INV_TIME | 10s | 终极选项A：无敌 |
| ULTIMATE_RAGE_TIME | 20s | 终极选项B：狂暴 |
| ULTIMATE_RAGE_ATK_MULT | 3.0 | 终极选项B：攻击×3 |

**毕业解锁技能池**:
- 武器类: multi_shot, piercing, combo_hit, palm_wave, leaf_pierce, leaf_homing
- CD技能类: grenade, bean_sprout, grab_smash, xmas_tree, charm_enemy, slow_rider, otto_box, otto_sprint

---

## 6. 符文系统完整数据

### 6.1 系统参数

| 参数 | 值 | 说明 |
|------|-----|------|
| DROP_CHANCE | 0.05 (5%) | Boss击杀掉落概率 |
| MAX_EQUIPPED | 2 | 同时装备上限 |
| 符文总数 | 14 | 与14个Boss 1:1对应 |

### 6.2 完整符文数据表

| # | ID | 名称 | 对应Boss | 触发条件 | 核心效果 | 冷却 |
|---|-----|------|---------|---------|---------|------|
| 1 | rune_police | 警戒反射 | 警察 | 受击时 | 3s SPD+40%, 攻速+25% | 4s |
| 2 | rune_worker | 钢铁壁垒 | 工人 | 每6s | 叠护盾层(最多3层), 抵挡致命伤 | 6s |
| 3 | rune_chef | 饕餮盛宴 | 厨师 | 暴击时 | 40%概率回血8%+下次必暴击 | 3s |
| 4 | rune_programmer | 递归循环 | 程序员 | 击杀时 | 15%概率链式闪电(4弹,80%ATK+30%减速2s) | 2s |
| 5 | rune_firefighter | 浴火重生 | 消防员 | HP<35% | 3s无敌+AOE(120%ATK, r=120) | 15s |
| 6 | rune_vampire | 血族契约 | 吸血鬼 | 被动/击杀 | 满血ATK+25%; 击杀15%概率回5%HP | 无 |
| 7 | rune_gentleman | 完美主义 | 绅士 | 未受击 | 2s未受击:dmg+80%+穿透+2; 5s:额外击退 | 受击重置 |
| 8 | rune_scientist | 裂变弹头 | 科学家 | 穿透时 | 40%概率分裂2弹(75%dmg) | 无 |
| 9 | rune_pirate | 夺宝奇兵 | 海盗 | 击杀/Boss杀 | Boss杀+80%金; 每15杀召唤宝箱 | 20s(宝箱) |
| 10 | rune_dj | 节拍风暴 | DJ | 每3s | AOE击退+100%ATK+40%减速2s, r=180 | 3s |
| 11 | rune_doctor | 急救协议 | 医生 | HP<35% | 回血40%HP+3s减伤50% | 15s |
| 12 | rune_ninja | 影分身术 | 忍者 | 暴击时 | 40%概率召唤分身(8s,100%ATK,最多2) | 无 |
| 13 | rune_robot | 超频核心 | 机器人 | 每8杀 | 攻速×3,dmg+80%,5s; 无机:下5发+50% | 击杀计数 |
| 14 | rune_demon_king | 深渊王权 | 魔王 | 击杀叠层 | 叠影(最多30),满→爆发300%ATK+全属性+1%/层10s | 满层触发 |

### 6.3 符文触发类型分类

| 触发类型 | 符文 |
|---------|------|
| **OnHit** (受击) | police |
| **OnKill** (击杀) | programmer, vampire(部分), pirate, robot, demon_king |
| **OnCrit** (暴击) | chef, ninja |
| **OnShoot** (射击) | scientist |
| **Passive/Periodic** (被动/定时) | worker, vampire(部分), gentleman, dj |
| **LowHP** (低血量) | firefighter, doctor |

---

## 7. 符文共鸣系统

### 7.1 系统机制

- **触发条件**: 同时装备特定2颗符文
- **检测方式**: 排序后的键对索引（sorted key pair）
- **共鸣数量**: 6组

### 7.2 完整共鸣效果表

| # | ID | 名称 | 组合符文 | 共鸣效果 |
|---|-----|------|---------|---------|
| 1 | flame_rebirth | 炎之重生 | firefighter + vampire | 火焰触发额外+20%HP回复; 击杀回血概率×2 |
| 2 | phantom_storm | 幻影风暴 | ninja + dj | 分身释放迷你AOE(50%范围, 60%伤害) |
| 3 | iron_medic | 钢铁医官 | worker + doctor | 护盾满层→回15%HP; 医生CD-5s |
| 4 | shadow_fission | 暗影裂变 | demon_king + scientist | 深渊爆发额外+8颗分裂弹(60%ATK) |
| 5 | thunder_loot | 雷电掠夺 | programmer + pirate | 链式闪电击杀→100%掉金; 宝箱阈值-5 |
| 6 | overclock_perfect | 超频完美 | robot + gentleman | 超频期间完美伤害翻倍; 完美层级时间减半 |

---

## 8. 图腾背包系统

### 8.1 系统参数

| 参数 | 值 |
|------|-----|
| MAX_INVENTORY | 600 |
| MAX_EQUIPPED | 3 |
| 稀有度 | 4级: junk(75%) / normal(20%) / rare(4.5%) / legendary(0.5%) |

### 8.2 图腾类型

| 大类 | 子类型 | 说明 |
|------|--------|------|
| stat | hp, atk, spd, crit, fire_rate, hp_regen, loot | 属性加成 |
| skill | atk_up, speed_up, magnet, knockback, atk_drone | 技能等级+1 |
| special | cross_class | 跨职业技能池 |

### 8.3 图腾数值表 (按稀有度)

| 属性 | junk | normal | rare | legendary |
|------|------|--------|------|-----------|
| hp | +10 | +30 | +80 | +150 |
| atk | +2 | +5 | +15 | +30 |
| spd | +10 | +25 | +60 | +100 |
| crit | +2% | +5% | +12% | +25% |
| fire_rate | -3% | -8% | -15% | -25% |
| hp_regen | +0.2%/s | +0.5%/s | +1%/s | +2%/s |
| loot | +5% | +12% | +25% | +50% |

### 8.4 合成系统

**规则**: 3个相同稀有度 → 1个更高稀有度（junk→normal→rare→legendary）

---

## 9. 遗物永久升级系统

### 9.1 遗物列表

| # | ID | 名称 | 每级效果 | 费用公式 |
|---|-----|------|---------|---------|
| 1 | strength | 力量 | ATK+0.2% | 2^(lv+1) |
| 2 | agility | 敏捷 | 暴击率+0.2% | 2^(lv+1) |
| 3 | vitality | 体力 | HP+0.25% | 2^(lv+1) |
| 4 | speed | 速度 | 攻击间隔-0.5%, SPD+0.5% | 2^(lv+1) |
| 5 | luck | 幸运 | 掉率+1% | 2^(lv+1) |
| 6 | armor | 护甲 | 减伤+0.3% | 2^(lv+1) |
| 7 | exp_boost | 经验 | 经验获取+0.3% | 2^(lv+1) |
| 8 | magnet | 磁力 | 磁吸范围+1% | 2^(lv+1) |
| 9 | guardian | 守护者 | 每波护盾层(减伤至1) | 1000^(lv+1) |
| 10 | flight | 飞行 | 解锁绿色无人机技能 | 1000^(lv+1) |

### 9.2 应用时机

```
BattleScene.Init() → RelicSystem.ApplyBonusesToPlayer() → Player.RecalcStats()
```

---

## 10. 波次调度系统

### 10.1 基础参数

| 参数 | 值 | 说明 |
|------|-----|------|
| interval | 30s | 波次间隔 |
| baseEnemyCount | 5 | 初始每波 |
| countGrowth | +2/波 | 线性增长 |
| maxEnemiesAlive | 60 | 同屏上限 |
| coeffGrowth | 0.08 | 每波系数+8% |
| spawnRadius | 700px | 生成距离 |
| spawnMinRadius | 500px | 最小距离 |
| bossInterval | 10波 | Boss间隔 |

### 10.2 波次敌人构成梯度 (WAVE_TIERS)

| 梯度 | 波次范围 | 敌人类型构成 |
|------|---------|------------|
| Tier 1 | 1-2 | 100% normal |
| Tier 2 | 3-4 | normal + fast(少量) |
| Tier 3 | 5-7 | normal + fast + tank + swarm |
| Tier 4 | 8-9 | 全类型出现, elite(5%) |
| Tier 5 | 10-12 | 全类型, elite(10%), charger/ghost增加 |
| Tier 6 | 13+ | 全类型, elite(18%), 所有高级怪高比例 |

### 10.3 难度缩放公式

```lua
waveCoeff = 1.0 + (waveNum - 1) * Config.WAVE.coeffGrowth
-- wave 1: 1.0, wave 10: 1.72, wave 20: 2.52

enemyHP = baseHp * waveCoeff * difficulty.enemyHpMult
enemyATK = baseAtk * waveCoeff * difficulty.enemyAtkMult
enemySPD = speed * waveCoeff^0.5 * difficulty.enemySpeedMult  -- 速度开方缓增
```

### 10.4 难度预设倍率

| 难度 | HP倍率 | ATK倍率 | SPD倍率 | 生成倍率 | 经验倍率 | 金币倍率 | 分数权重 |
|------|--------|---------|---------|---------|---------|---------|---------|
| 简单🟢 | 0.7 | 0.6 | 0.9 | 0.8 | 1.3 | 1.2 | 0.5 |
| 普通🟡 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 |
| 困难🔴 | 1.5 | 1.4 | 1.15 | 1.3 | 0.8 | 1.5 | 1.8 |
| 噩梦💀 | 2.2 | 2.0 | 1.3 | 1.6 | 0.6 | 2.0 | 3.0 |

---

## 11. 实体管理架构

### 11.1 对象池模式

所有游戏实体使用**对象池**管理，避免频繁创建/销毁产生 GC 压力：

```
┌─────────────────────────────────────────────────┐
│                 Object Pool                      │
├─────────────────────────────────────────────────┤
│  Pool Array (pre-allocated)                     │
│  ┌─────┬─────┬─────┬─────┬─────┐             │
│  │ [1] │ [2] │ [3] │ ... │ [N] │             │
│  └─────┴─────┴─────┴─────┴─────┘             │
│                                                 │
│  Active Count: activeCount                      │
│  前 activeCount 个元素 = 活跃实体              │
│  后续元素 = 空闲/待回收                        │
│                                                 │
│  Spawn: pool[++activeCount] = init(...)         │
│  Recycle: swap(dying, pool[activeCount--])      │
└─────────────────────────────────────────────────┘
```

### 11.2 六大对象池

| 对象池 | 管理文件 | 预分配数 | 说明 |
|--------|---------|---------|------|
| Enemy | battle/Enemy.lua | 60+ | 所有敌人(含Boss) |
| Projectile (玩家子弹) | battle/Skill.lua | 100+ | 玩家射出的弹幕 |
| EnemyBullet (敌弹) | battle/Enemy.lua | 200+ | Boss/远程怪弹幕 |
| Loot (掉落物) | battle/BattleScene.lua | 100+ | 经验/金币/特殊物 |
| DamageNumber | battle/BattleScene.lua | 50+ | 浮动伤害数字 |
| Particle | battle/BattleScene.lua | 100+ | 视觉粒子效果 |

### 11.3 空间哈希碰撞系统

```
┌─────────────────────────────────────────┐
│          SpatialHash (cellSize=200)      │
├─────────────────────────────────────────┤
│  哈希函数: Cantor配对                    │
│  key = ((cx+cy)*(cx+cy+1))/2 + cy      │
│                                         │
│  Insert: 将实体注册到所属网格           │
│  Query(x, y, radius):                   │
│    计算覆盖的网格范围                    │
│    遍历相关网格中的实体                  │
│    距离检测 < radius → 命中             │
│                                         │
│  每帧重建 (Enemy池)                     │
│  持久复用 (Skill.lua 减少GC)            │
└─────────────────────────────────────────┘
```

### 11.4 实体生命周期

```
┌──────┐     ┌───────┐     ┌────────┐     ┌─────────┐     ┌─────────┐
│ Pool │ ──→ │ Spawn │ ──→ │ Active │ ──→ │ Update  │ ──→ │ Recycle │
│(idle)│     │(init) │     │ (live) │     │ (logic) │     │ (reset) │
└──────┘     └───────┘     └────────┘     └─────────┘     └─────────┘
                                               │
                                               ▼
                                    ┌─────────────────────┐
                                    │ SpatialHash.Insert  │
                                    │ Collision Detection │
                                    │ Damage / Effects    │
                                    └─────────────────────┘
```

### 11.5 BattleScene 主循环 (safeCall 架构)

```lua
function BattleScene.Update(dt)
    safeCall("Wave",        Wave.Update, dt)
    safeCall("Enemy",       Enemy.UpdateAll, dt)
    safeCall("Player",      Player.Update, dt)
    safeCall("Skill",       Skill.Update, dt)
    safeCall("RuneEffects", RuneEffects.Update, dt, enemies)
    safeCall("Collision",   CollisionCheck, dt)
    safeCall("Loot",        Loot.Update, dt)
    safeCall("Particle",    Particle.Update, dt)
end
```

> safeCall = pcall 包裹，任意子系统崩溃不会中断主循环

---

## 12. 触发逻辑链完整图谱

### 12.1 伤害计算链

```
玩家射击
  │
  ├→ 基础伤害 = baseAtk × charStats.atk × (1 + atkBonuses)
  │     ├→ 遗物加成: strength × 0.002
  │     ├→ 技能加成: atk_up × 0.10/级, iron_fist × 0.12/级
  │     ├→ 图腾加成: equipped_totem.atk
  │     └→ 过载加成: ×2.0 (if overloaded)
  │
  ├→ 暴击判定
  │     ├→ 暴击率 = baseCritRate × charStats.critRate + 技能/遗物/图腾加成
  │     ├→ 暴击伤害 = damage × critDamage(2.0)
  │     └→ 触发 OnCrit 钩子 → chef符文 / ninja符文
  │
  ├→ 命中敌人
  │     ├→ 穿透检查: pierceCount > 0 → 继续飞行
  │     │     └→ scientist符文: 40%概率分裂2弹
  │     ├→ 弹射检查: bounceCount > 0 → 寻找最近敌人
  │     ├→ 击退检查: knockback技能 5%/级概率
  │     └→ 冰冻叠加: leaf_storm/xmas_tree → freezeStacks++
  │
  └→ 敌人死亡
        ├→ 触发 OnKill 钩子
        │     ├→ programmer符文: 15%链式闪电
        │     ├→ vampire符文: 15%回5%HP
        │     ├→ pirate符文: 计数→宝箱
        │     ├→ robot符文: 计数→超频
        │     ├→ demon_king符文: 叠影层
        │     └→ charm_enemy技能: 魅惑
        │
        ├→ 掉落物生成
        │     ├→ 经验芯片(100%)
        │     ├→ 金币(36%)
        │     ├→ 红心(4%)
        │     ├→ 磁铁(3%)
        │     ├→ 炸弹(1.2%)
        │     └→ 礼物盒(0.8%, 5波CD)
        │
        └→ 过载充能: killCount++, if >= 100 → 过载5s
```

### 12.2 受击逻辑链

```
敌人接触/Boss弹幕命中玩家
  │
  ├→ 无敌检查: invincibleTimer > 0 → 忽略
  │
  ├→ 护盾检查
  │     ├→ shield技能层 > 0 → 消耗1层, 不扣血
  │     ├→ worker符文层 > 0 → 消耗1层, 不扣血
  │     └→ guardian遗物层 > 0 → 伤害减至1
  │
  ├→ 伤害计算
  │     ├→ 减伤 = armor遗物 × 0.003/级
  │     ├→ doctor符文buff: 额外减伤50%
  │     └→ finalDmg = rawDmg × (1 - reduction)
  │
  ├→ HP更新 → 触发 OnHit 钩子
  │     └→ police符文: 3s SPD+40%, 攻速+25% (CD4s)
  │
  ├→ 低血量检查 (HP < 35% maxHP)
  │     ├→ firefighter符文: 3s无敌 + AOE (CD15s)
  │     └→ doctor符文: 回40%HP + 3s减伤50% (CD15s)
  │
  ├→ gentleman符文重置: noHitTimer = 0
  │
  └→ 设置无敌帧: invincibleTimer = 0.8s
```

### 12.3 符文 OnKill 触发链（帧级预算）

```
Enemy.Die()
  │
  ├→ RuneEffects.OnKill(enemy)
  │     │
  │     ├→ 帧守卫检查: onKillBudget <= 0 → 跳过
  │     │   (每帧最多处理 8 次 OnKill)
  │     │
  │     ├→ rune_programmer (递归循环)
  │     │     └→ 15% → 链式闪电4弹, 每弹80%ATK
  │     │         └→ [共鸣] thunder_loot: 击杀→100%掉金, 宝箱阈值-5
  │     │
  │     ├→ rune_vampire (血族契约)
  │     │     └→ 15% → 回5%HP
  │     │         └→ [共鸣] flame_rebirth: 回血概率×2
  │     │
  │     ├→ rune_pirate (夺宝奇兵)
  │     │     └→ killCount++, if >= 15 → 召唤宝箱 (CD20s)
  │     │         └→ [共鸣] thunder_loot: 阈值15→10
  │     │
  │     ├→ rune_robot (超频核心)
  │     │     └→ killCount++, if >= 8 → 超频5s
  │     │         └→ [共鸣] overclock_perfect: 完美伤害翻倍
  │     │
  │     └→ rune_demon_king (深渊王权)
  │           └→ shadowStacks++, if >= 30 → 爆发300%ATK
  │               └→ [共鸣] shadow_fission: +8颗分裂弹
  │
  └→ onKillBudget--
```

### 12.4 符文 OnCrit 触发链

```
Bullet hits enemy (isCrit = true)
  │
  └→ RuneEffects.OnCrit(enemy, damage)
        │
        ├→ rune_chef (饕餮盛宴) [CD3s]
        │     └→ 40% → 回8%HP + 下次必暴击flag
        │
        └→ rune_ninja (影分身术)
              └→ 40% → 召唤分身(8s, 100%ATK, max 2)
                  └→ [共鸣] phantom_storm: 分身释放迷你AOE
```

### 12.5 符文 Periodic/Passive 更新链 (每帧)

```
RuneEffects.Update(dt, enemies)
  │
  ├→ rune_worker: shieldTimer -= dt, if <= 0 → addShield (max 3)
  │     └→ [共鸣] iron_medic: 满3层→回15%HP
  │
  ├→ rune_gentleman: noHitTimer += dt
  │     ├→ >= 2s: perfectTier=1 → dmg+80%, pierce+2
  │     ├→ >= 5s: perfectTier=2 → 额外击退
  │     └→ [共鸣] overclock_perfect: 层级时间减半(1s/2.5s)
  │
  ├→ rune_dj: beatTimer -= dt, if <= 0 → AOE(r=180, 100%ATK, 击退+40%减速)
  │     └→ [共鸣] phantom_storm: 分身也释放此AOE(50%范围)
  │
  ├→ rune_vampire: (被动) 满血时ATK+25%
  │     └→ [共鸣] flame_rebirth: fire触发额外+20%HP回复
  │
  └→ rune_demon_king: (被动) 叠层影响UI显示, 10s buff倒计时
```

### 12.6 过载系统逻辑链

```
每次击杀 → killCount++
  │
  ├→ killCount >= 100 (OVERLOAD.killsToFull)
  │     │
  │     ├→ 激活过载 5s
  │     │     ├→ ATK × 2.0
  │     │     ├→ SPD + 30%
  │     │     └→ 所有CD × 0.5
  │     │
  │     ├→ 切换 playerEmoji → "overload"
  │     │
  │     └→ killCount = 0 (重置)
  │
  └→ 过载结束 → 恢复原始属性
```

### 12.7 技能选择逻辑链

```
玩家升级 (exp >= threshold)
  │
  ├→ 进入 SKILL_SELECT 状态
  │
  ├→ 构建技能池
  │     ├→ 当前角色 exclusiveSkills (未满级)
  │     ├→ Config.SHARED_SKILLS (未满级)
  │     ├→ [毕业后] GRADUATION_WEAPON_SKILLS + GRADUATION_CD_SKILLS
  │     ├→ [跨职业符文] 其他角色非signatureSkill
  │     └→ 排除已满级技能
  │
  ├→ 随机抽取 3 个选项展示
  │
  └→ 玩家选择 → 技能等级+1 → RecalcStats()
```

---

## 13. 数值公式汇总

### 13.1 升级经验公式

```lua
expToNextLevel = currentLevel × 20
```

### 13.2 每级属性成长

| 属性 | 每级增长 |
|------|---------|
| HP | +3% |
| ATK | +3% |
| 暴击率 | +0.2% |

### 13.3 最终属性计算

```lua
finalHP = Config.PLAYER.baseHp 
    × charStats.hp                    -- 角色倍率
    × (1 + level × 0.03)             -- 等级成长
    × (1 + hp_up × 0.10)             -- 技能加成
    × (1 + relic_vitality × 0.0025)  -- 遗物加成
    + totem_hp_bonus                  -- 图腾加成(加法)

finalATK = Config.PLAYER.baseAtk
    × charStats.atk
    × (1 + level × 0.03)
    × (1 + atk_up × 0.10 + iron_fist × 0.12)
    × (1 + relic_strength × 0.002)
    × (overloaded ? 2.0 : 1.0)
    × (vampire_rune_fullHP ? 1.25 : 1.0)
    + totem_atk_bonus

finalSPD = Config.PLAYER.baseSpeed
    × charStats.speed
    × (1 + speed_up × 0.05 + otto_sprint × 0.15 + dodge_roll × 0.07)
    × (1 + relic_speed × 0.005)
    × (overloaded ? 1.3 : 1.0)
    × (police_rune_buff ? 1.4 : 1.0)
    + totem_spd_bonus

finalCritRate = Config.PLAYER.baseCritRate
    × charStats.critRate
    + level × 0.002
    + crit_up × 0.05
    + finger_flick × 0.06
    + dodge_roll × 0.02
    + relic_agility × 0.002
    + totem_crit_bonus

finalAttackInterval = Config.PLAYER.attackInterval
    × (1 - fire_rate × 0.15)
    × (1 - speed_burst × 0.20)
    × (1 - relic_speed × 0.005)
    × (overloaded ? 0.5 : 1.0)
    × (robot_rune_overclock ? 0.33 : 1.0)
    × (police_rune_buff ? 0.75 : 1.0)
    × (1 - totem_fire_rate_bonus)
```

### 13.4 伤害减免公式

```lua
damageReduction = relic_armor × 0.003 + (doctor_rune_buff ? 0.50 : 0)
finalDamage = rawDamage × (1 - damageReduction)
-- 最低伤害为 1（guardian遗物效果）
```

### 13.5 掉落物概率公式

```lua
finalDropChance = baseChance × (1 + clover_luck × 0.15) × (1 + relic_luck × 0.01) × (1 + totem_loot_bonus)
```

### 13.6 经验获取公式

```lua
finalExp = baseExp × (1 + relic_exp_boost × 0.003) × difficulty.expMult
```

### 13.7 Boss血量缩放

```lua
bossHP = bossDef.baseHp × (1 + (waveNum - 1) × 0.08) × difficulty.enemyHpMult
```

---

## 附录A: 完整掉落物配置

| 类型 | Emoji | 半径 | 基础概率 | 效果 |
|------|-------|------|---------|------|
| 经验芯片 | (颜色圆点) | 6 | 100% | baseExp=2 |
| 金币 | 🪙 | 8 | 36% | 3倍经验+1局外金币 |
| 红心 | ❤️ | 10 | 4% | 回复15%maxHP |
| 磁铁 | 🧲 | 10 | 3% | 5s磁吸范围400px |
| 炸弹 | 💣 | 12 | 1.2% | 全屏999伤害(Boss免疫) |
| 礼物盒 | 🎁 | 14 | 0.8% | 广告奖励(5波CD) |

## 附录B: 性能质量等级

游戏支持5级画质自动降级（FPS监控）：

| 等级 | 粒子 | 拖尾 | 光晕 | 伤害数字 |
|------|------|------|------|---------|
| Ultra | 全开 | 全长 | 全亮 | 全显示 |
| High | 80% | 短尾 | 亮度降 | 全显示 |
| Medium | 50% | 更短 | 减半 | 抽样 |
| Low | 30% | 极短 | 关闭 | 抽样 |
| Minimal | 关闭 | 关闭 | 关闭 | 关键才显示 |

## 附录C: 皮肤系统

- 12 套皮肤（每角色2套），纯装饰
- 重写 `playerEmoji` 和 `bulletStyle`
- 解锁方式: 金币购买 / 广告观看(adUnlock)

---

*文档生成时间: 2026-06-02*
*数据源: /workspace/scripts/ 全目录*
