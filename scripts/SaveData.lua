--- ============================================================================
--- 存档系统 - 昵称、游戏存档、历史最高分、图腾背包、云同步
--- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson  -- 引擎内置全局变量，无需 require

local TotemSystem = require("meta.TotemSystem")
local RuneSystem  = require("meta.RuneSystem")
local SkinSystem  = require("meta.SkinSystem")

-- clientCloud 是引擎注入的全局变量，可能在本模块加载后才就绪
-- 因此不在顶部缓存，改用函数动态获取
---@diagnostic disable-next-line: undefined-global
local function getClientCloud() return clientCloud end

local SaveData = {}

-- 文件名
local PROFILE_FILE = "profile.json"
local GAMESAVE_FILE = "gamesave.json"

-- 内存数据
SaveData.nickname = nil             -- 玩家昵称
SaveData.highScores = {}            -- Top3 { {wave, kills, charId, timeStr, level}, ... }
SaveData.repUnlocked = false        -- 是否已通过 Rep 链接解锁角色（一次性解锁全部）
SaveData.adUnlockedChars = {}       -- 通过看广告单独解锁的角色 { [charId]=true }

-- ============================================================
-- 局外养成数据
-- ============================================================
SaveData.metaGold    = 0    -- 局外金币总量
SaveData.relicLevels = {}   -- { [relicId] = level }，默认0未解锁
SaveData.adGoldCount = 0    -- 今日已看广告次数（上限10次）
SaveData.adGoldDate  = ""   -- 今日日期key，用于每日重置

-- 图腾系统数据（新版 v2）
SaveData.highestWave    = 0    -- 历史最高波次（全局最高）
SaveData.totems         = {}   -- 背包: { {typeId, rarity}, ... } 最多600个
SaveData.equippedTotems = {}   -- 已装备: { {typeId, rarity}, ... } 最多3个

-- 符文系统数据
SaveData.ownedRunes    = {}   -- { [runeId]=true } 已拥有的符文
SaveData.equippedRunes = {}   -- { runeId, runeId } 已装备的符文（最多2个）

-- 皮肤系统数据
SaveData.ownedSkins    = {}   -- { [skinId]=true } 已拥有的皮肤
SaveData.equippedSkins = {}   -- { [charId]=skinId } 各角色当前装备的皮肤

-- 本局获得的图腾（临时，用于结算屏显示）
SaveData.sessionTotems = {}
-- 本局获得的符文（临时，用于结算屏显示）
SaveData.sessionRunes = {}

-- 图腾数据是否被本次会话主动修改过（用于区分"合法清空"和"异常清空"）
SaveData._totemsDirty = false

-- 每日挑战名人堂 { {dateKey, rank, nickname, wave}, ... }
SaveData.hallOfFame = {}

-- 云端 Key
local CLOUD_KEY_META_GOLD    = "meta_gold"
local CLOUD_KEY_RELIC_PREFIX = "relic_"
local CLOUD_KEY_AD_COUNT     = "ad_gold_count"
local CLOUD_KEY_AD_DATE      = "ad_gold_date"
local CLOUD_KEY_HIGHEST_WAVE = "highest_wave"
local CLOUD_KEY_TOTEMS_V2    = "totems_v2"       -- 图腾背包（JSON聚合计数）
local CLOUD_KEY_EQUIPPED_V2  = "equipped_v2"      -- 已装备图腾（JSON数组）
local CLOUD_KEY_NICKNAME     = "nickname"          -- 昵称
local CLOUD_KEY_ACHIEVEMENTS = "achievements"      -- 成就位掩码
local CLOUD_KEY_RUNES        = "runes_v1"          -- 符文（JSON: 已拥有runeId列表）
local CLOUD_KEY_EQUIPPED_RUNES = "equipped_runes_v1" -- 已装备符文（JSON数组）
local CLOUD_KEY_SKINS          = "skins_v1"          -- 皮肤（JSON: 已拥有skinId列表）
local CLOUD_KEY_EQUIPPED_SKINS = "equipped_skins_v1" -- 已装备皮肤（JSON: {charId=skinId}）
local RELIC_IDS = { "strength", "agility", "vitality", "speed", "luck", "armor", "exp_boost", "magnet", "guardian", "flight" }

--- 获取今日日期 Key（天数，整数，每天变化）
local function TodayKey()
    return tostring(math.floor(os.time() / 86400))
end

-- ============================================================================
-- 随机昵称生成器
-- ============================================================================

local ADJECTIVES = {
    "勇敢", "无敌", "闪亮", "暴走", "元气",
    "快乐", "酷炫", "幸运", "狂野", "超级",
    "神秘", "暗影", "闪电", "烈焰", "冰霜",
    "星光", "疾风", "钢铁", "暴风", "极速",
}

local NOUNS = {
    "猫猫", "勇士", "大王", "英雄", "小萌新",
    "挑战者", "幸存者", "战神", "忍者", "骑士",
    "猎人", "法师", "剑客", "玩家", "高手",
}

--- 生成随机昵称
---@return string
function SaveData.GenerateNickname()
    local adj = ADJECTIVES[math.random(#ADJECTIVES)]
    local noun = NOUNS[math.random(#NOUNS)]
    return adj .. noun
end

-- ============================================================================
-- Profile (昵称 + 历史最高分 + 图腾)
-- ============================================================================

--- 将运行时图腾列表打包为紧凑存档格式
--- 运行时: { {typeId="hp", rarity="junk"}, ... }
--- 存档:   { {id=1, r=1}, ... }
---@param list table[] 运行时图腾列表
---@return table[] packed 紧凑列表
function SaveData._packTotemList(list)
    local packed = {}
    local skipped = 0
    for i, t in ipairs(list) do
        local numId = TotemSystem.GetTypeNumId(t.typeId)
        local rarIdx = TotemSystem.GetRarityIndex(t.rarity)
        if numId and rarIdx then
            packed[#packed + 1] = { id = numId, r = rarIdx }
        else
            skipped = skipped + 1
            print("[SaveData] WARN _packTotemList: invalid entry #" .. i
                  .. " typeId=" .. tostring(t.typeId) .. " rarity=" .. tostring(t.rarity)
                  .. " numId=" .. tostring(numId) .. " rarIdx=" .. tostring(rarIdx))
        end
    end
    if skipped > 0 then
        print("[SaveData] WARN _packTotemList: " .. skipped .. "/" .. #list .. " entries skipped")
    end
    return packed
end

--- 将存档格式还原为运行时格式（兼容旧字符串格式）
--- 安全策略：遇到无法解析的条目会打印警告；若全部失败则返回空表并打印严重告警
---@param list table[] 存档列表（可能是新格式或旧格式）
---@return table[] unpacked 运行时图腾列表
function SaveData._unpackTotemList(list)
    if type(list) ~= "table" then
        print("[SaveData] WARN _unpackTotemList: input is not a table, got " .. type(list))
        return {}
    end
    local unpacked = {}
    local skipped = 0
    local rarityOrder = TotemSystem.GetRarityOrder() -- {"junk","normal","rare","legendary"}
    for i, t in ipairs(list) do
        if type(t) ~= "table" then
            skipped = skipped + 1
            print("[SaveData] WARN _unpackTotemList: entry #" .. i .. " is not a table, got " .. type(t))
        elseif t.id and t.r then
            -- 新格式 {id=1, r=1}
            local typeId = TotemSystem.GetTypeById(t.id)
            local rarity = rarityOrder[t.r]
            if typeId and rarity then
                unpacked[#unpacked + 1] = { typeId = typeId, rarity = rarity }
            else
                skipped = skipped + 1
                print("[SaveData] WARN _unpackTotemList: invalid id/r at #" .. i
                      .. " id=" .. tostring(t.id) .. " r=" .. tostring(t.r)
                      .. " typeId=" .. tostring(typeId) .. " rarity=" .. tostring(rarity))
            end
        elseif t.typeId and t.rarity then
            -- 旧格式 {typeId="hp", rarity="junk"} → 直接使用（向后兼容）
            local validTypeId = TotemSystem.ValidateTypeId(t.typeId)
            if validTypeId then
                unpacked[#unpacked + 1] = { typeId = validTypeId, rarity = t.rarity }
            else
                skipped = skipped + 1
                print("[SaveData] WARN _unpackTotemList: unknown typeId at #" .. i
                      .. " typeId=" .. tostring(t.typeId))
            end
        else
            skipped = skipped + 1
            print("[SaveData] WARN _unpackTotemList: unrecognized format at #" .. i)
        end
    end
    if skipped > 0 then
        print("[SaveData] WARN _unpackTotemList: " .. skipped .. "/" .. #list
              .. " entries skipped, " .. #unpacked .. " valid")
    end
    if #list > 0 and #unpacked == 0 then
        print("[SaveData] CRITICAL _unpackTotemList: ALL " .. #list
              .. " entries failed to parse! Returning empty list — potential data loss!")
    end
    return unpacked
end

--- 加载玩家档案
function SaveData.LoadProfile()
    if not cjson then
        print("[SaveData] LoadProfile: cjson not available, skipped")
        return
    end
    if not fileSystem:FileExists(PROFILE_FILE) then
        print("[SaveData] LoadProfile: " .. PROFILE_FILE .. " not found, skipped")
        return
    end

    local file = File(PROFILE_FILE, FILE_READ)
    if not file:IsOpen() then
        print("[SaveData] LoadProfile: failed to open " .. PROFILE_FILE .. " for reading")
        return
    end

    local rawStr = file:ReadString()
    file:Close()
    print("[SaveData] LoadProfile: raw JSON length=" .. #rawStr)

    local ok2, data = pcall(cjson.decode, rawStr)
    if not ok2 then
        print("[SaveData] LoadProfile: JSON decode FAILED: " .. tostring(data))
        return
    end
    if not data then
        print("[SaveData] LoadProfile: decoded data is nil")
        return
    end

    -- 诊断：打印存档中图腾原始数据
    local rawTotems = data.totems or {}
    local rawEquipped = data.equippedTotems or {}
    print("[SaveData] LoadProfile: raw totems count=" .. (type(rawTotems) == "table" and #rawTotems or "N/A")
          .. " raw equipped count=" .. (type(rawEquipped) == "table" and #rawEquipped or "N/A")
          .. " metaGold=" .. tostring(data.metaGold)
          .. " highestWave=" .. tostring(data.highestWave))

    if ok2 and data then
        SaveData.nickname = data.nickname
        SaveData.highScores = data.highScores or {}
        SaveData.repUnlocked = data.repUnlocked or false
        SaveData.adUnlockedChars = data.adUnlockedChars or {}

        -- 局外养成数据
        SaveData.metaGold    = data.metaGold    or 0
        SaveData.relicLevels = data.relicLevels or {}
        SaveData.adGoldCount = data.adGoldCount or 0
        SaveData.adGoldDate  = data.adGoldDate  or ""
        -- 最高波次
        SaveData.highestWave = data.highestWave or 0

        -- 新版图腾系统（v3紧凑格式 + 旧格式兼容）
        SaveData.totems         = SaveData._unpackTotemList(rawTotems)
        SaveData.equippedTotems = SaveData._unpackTotemList(rawEquipped)

        -- 诊断：打印解包后图腾数量
        print("[SaveData] LoadProfile: after unpack totems=" .. #SaveData.totems
              .. " equipped=" .. #SaveData.equippedTotems)

        -- 符文系统
        SaveData.ownedRunes = data.ownedRunes or {}
        SaveData.equippedRunes = data.equippedRunes or {}
        -- 校验：确保 equippedRunes 中的ID都在 ownedRunes 中
        for i = #SaveData.equippedRunes, 1, -1 do
            local rid = SaveData.equippedRunes[i]
            if not SaveData.ownedRunes[rid] or not RuneSystem.GetRune(rid) then
                table.remove(SaveData.equippedRunes, i)
                print("[SaveData] WARN: removed invalid equipped rune: " .. tostring(rid))
            end
        end
        while #SaveData.equippedRunes > RuneSystem.MAX_EQUIPPED do
            table.remove(SaveData.equippedRunes)
        end

        -- 每日挑战名人堂
        SaveData.hallOfFame = data.hallOfFame or {}

        -- 皮肤系统
        SaveData.ownedSkins = data.ownedSkins or {}
        SaveData.equippedSkins = data.equippedSkins or {}
        -- 校验：确保装备的皮肤确实拥有且存在
        for charId, skinId in pairs(SaveData.equippedSkins) do
            if not SaveData.ownedSkins[skinId] or not SkinSystem.GetSkin(skinId) then
                SaveData.equippedSkins[charId] = nil
                print("[SaveData] WARN: removed invalid equipped skin: " .. tostring(skinId) .. " for " .. charId)
            end
        end

        -- ── 旧存档兼容：检测旧符文数据并迁移 ──
        if data.unlockedRunes and not data.totems then
            local refundTotal = 0
            local RUNE_COSTS = {
                rune_atk_up = 5000, rune_speed_up = 5000, rune_magnet = 5000,
                rune_knockback = 5000, rune_drone = 10000, rune_cross_class = 100000,
            }
            for runeId, unlocked in pairs(data.unlockedRunes) do
                if unlocked and RUNE_COSTS[runeId] then
                    refundTotal = refundTotal + RUNE_COSTS[runeId]
                end
            end
            if refundTotal > 0 then
                SaveData.metaGold = SaveData.metaGold + refundTotal
                print("[SaveData] Old rune data migrated, refunded " .. refundTotal .. " gold")
            end
            SaveData.totems = {}
            SaveData.equippedTotems = {}
        end
    end

    -- 每日广告计数重置
    if SaveData.adGoldDate ~= TodayKey() then
        SaveData.adGoldCount = 0
        SaveData.adGoldDate  = TodayKey()
    end

    -- 加载完毕，重置 dirty 标记（加载不算主动修改）
    SaveData._totemsDirty = false
end

--- 保存玩家档案
--- 安全策略：内存图腾全空但存档中有图腾时，保留存档中的图腾字段，其余数据正常保存
function SaveData.SaveProfile()
    if not cjson then return end

    -- ── 图腾数据丢失保护 ──
    -- 如果内存图腾全空，检查存档是否有旧数据需要保留
    local packedTotems   = SaveData._packTotemList(SaveData.totems)
    local packedEquipped = SaveData._packTotemList(SaveData.equippedTotems)

    if #packedTotems == 0 and #packedEquipped == 0 and (not SaveData._totemsDirty) and fileSystem:FileExists(PROFILE_FILE) then
        local checkFile = File(PROFILE_FILE, FILE_READ)
        if checkFile:IsOpen() then
            local okC, oldData = pcall(cjson.decode, checkFile:ReadString())
            checkFile:Close()
            if okC and oldData then
                local oldInv = type(oldData.totems) == "table" and #oldData.totems or 0
                local oldEq  = type(oldData.equippedTotems) == "table" and #oldData.equippedTotems or 0
                if oldInv + oldEq > 0 then
                    -- 内存为空但存档有数据 → 保留存档中的图腾字段
                    packedTotems   = oldData.totems
                    packedEquipped = oldData.equippedTotems
                    print("[SaveData] WARN SaveProfile: memory totems=0 but save has "
                          .. (oldInv + oldEq) .. " — preserving old totem data in save")
                end
            end
        end
    end

    local data = {
        nickname = SaveData.nickname,
        highScores = SaveData.highScores,
        repUnlocked = SaveData.repUnlocked,
        adUnlockedChars = SaveData.adUnlockedChars,
        -- 局外养成数据
        metaGold    = SaveData.metaGold,
        relicLevels = SaveData.relicLevels,
        adGoldCount = SaveData.adGoldCount,
        adGoldDate  = SaveData.adGoldDate,
        -- 图腾系统（v3: 紧凑 _id 格式）
        highestWave     = SaveData.highestWave,
        totems          = packedTotems,
        equippedTotems  = packedEquipped,
        -- 符文系统
        ownedRunes     = SaveData.ownedRunes,
        equippedRunes  = SaveData.equippedRunes,
        -- 皮肤系统
        ownedSkins     = SaveData.ownedSkins,
        equippedSkins  = SaveData.equippedSkins,
        -- 每日挑战名人堂
        hallOfFame     = SaveData.hallOfFame,
    }

    local jsonStr = cjson.encode(data)
    print("[SaveData] SaveProfile: memory totems=" .. #SaveData.totems
          .. " equipped=" .. #SaveData.equippedTotems
          .. " packed=" .. #packedTotems
          .. " packedEq=" .. #packedEquipped
          .. " dirty=" .. tostring(SaveData._totemsDirty)
          .. " jsonLen=" .. #jsonStr)

    local file = File(PROFILE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
    else
        print("[SaveData] CRITICAL SaveProfile: failed to open " .. PROFILE_FILE .. " for writing!")
    end
end

--- 是否需要设置昵称（首次进入游戏）
---@return boolean
function SaveData.NeedsNickname()
    return SaveData.nickname == nil or SaveData.nickname == ""
end

--- 设置昵称并保存（含云同步）
---@param name string
function SaveData.SetNickname(name)
    SaveData.nickname = name
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
end

--- 添加高分记录（保留Top3）
---@param wave number
---@param kills number
---@param charId string
---@param timeStr string
---@param level number
---@return number|nil 排名(1-3)，nil表示未入榜
function SaveData.AddHighScore(wave, kills, charId, timeStr, level)
    local entry = {
        wave = wave,
        kills = kills,
        charId = charId,
        timeStr = timeStr,
        level = level,
    }

    table.insert(SaveData.highScores, entry)

    -- 排序：波次优先，击杀次之
    table.sort(SaveData.highScores, function(a, b)
        if a.wave ~= b.wave then return a.wave > b.wave end
        return a.kills > b.kills
    end)

    -- 只保留 Top3
    while #SaveData.highScores > 3 do
        table.remove(SaveData.highScores)
    end

    -- 返回排名
    for i, hs in ipairs(SaveData.highScores) do
        if hs == entry then
            SaveData.SaveProfile()
            return i
        end
    end

    SaveData.SaveProfile()
    return nil
end

-- ============================================================================
-- 游戏存档（进行中的游戏状态）
-- ============================================================================

--- 是否存在游戏存档
---@return boolean
function SaveData.HasGameSave()
    if not cjson then return false end
    if not fileSystem:FileExists(GAMESAVE_FILE) then return false end
    local file = File(GAMESAVE_FILE, FILE_READ)
    if not file:IsOpen() then return false end
    local content = file:ReadString()
    file:Close()
    return content ~= nil and content ~= ""
end

--- 保存当前游戏状态
---@param Player table Player 模块
---@param Wave table Wave 模块
---@param Skill table Skill 模块
---@param Loot table Loot 模块
function SaveData.SaveGame(Player, Wave, Skill, Loot)
    if not cjson then return end

    local data = {
        version = 1,

        -- Player 核心状态
        player = {
            charId = Player.charId,
            x = Player.x,
            y = Player.y,
            hp = Player.hp,
            maxHp = Player.maxHp,
            level = Player.level,
            exp = Player.exp,
            expToNext = Player.expToNext,
            kills = Player.kills,
            skills = Player.skills,

            -- 过载
            overloadKills = Player.overloadKills,
            overloadActive = Player.overloadActive,
            overloadTimer = Player.overloadTimer,

            -- 攻击
            attackTimer = Player.attackTimer,
            attackInterval = Player.attackInterval,
            extraBullets = Player.extraBullets,
            pierceCount = Player.pierceCount,
            bounceCount = Player.bounceCount,

            -- 防御
            invTimer = Player.invTimer,
            guardianCharges = Player.guardianCharges,
            shieldCharges = Player.shieldCharges,
            shieldTimer = Player.shieldTimer,
            shieldInterval = Player.shieldInterval,
            regenRate = Player.regenRate,

            -- 毕业
            graduationPhase = Player.graduationPhase,
            droneCollisionDmg = Player.droneCollisionDmg,
            rageActive = Player.rageActive,
            rageTimer = Player.rageTimer,

            -- 技能被动加成
            atkBonus = Player.atkBonus,
            hpBonus = Player.hpBonus,
            speedBonus = Player.speedBonus,
            critBonus = Player.critBonus,
            magnetBonus = Player.magnetBonus,
            fireRateBonus = Player.fireRateBonus,
            knockbackChance = Player.knockbackChance,
            knockbackForce = Player.knockbackForce,
            bigBulletChance = Player.bigBulletChance,
            homingChance = Player.homingChance,
            lootBonus = Player.lootBonus,
        },

        -- Wave 状态
        wave = {
            waveNum = Wave.waveNum,
            timer = Wave.timer,
            totalTime = Wave.totalTime,
            waveCoeff = Wave.waveCoeff,
            bossAlive = Wave.bossAlive,
            spawnTimer = Wave.spawnTimer,
        },

        -- Skill 完整状态（计时器 + 运行时实体）
        skill = Skill.ExportState(),

        -- Loot 状态
        loot = {
            magnetBoostTimer = Loot.magnetBoostTimer,
            magnetBoostRange = Loot.magnetBoostRange,
            lastGiftWave = Loot.lastGiftWave,
        },
    }

    local file = File(GAMESAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
        print("[SaveData] Game saved at wave " .. Wave.waveNum)
    end
end

--- 读取游戏存档
---@return table|nil 存档数据或 nil
function SaveData.LoadGame()
    if not cjson then return nil end
    if not fileSystem:FileExists(GAMESAVE_FILE) then return nil end

    local file = File(GAMESAVE_FILE, FILE_READ)
    if not file:IsOpen() then return nil end

    local ok2, data = pcall(cjson.decode, file:ReadString())
    file:Close()

    if ok2 and type(data) == "table" and data.version == 1 then
        return data
    end

    return nil
end

--- 将存档数据应用到游戏模块
---@param data table 存档数据
---@param Player table
---@param Wave table
---@param Skill table
---@param Loot table
function SaveData.ApplyToGame(data, Player, Wave, Skill, Loot)
    if not data then return end

    -- Player
    local p = data.player
    if p then
        Player.charId = p.charId
        Player.x = p.x
        Player.y = p.y
        Player.hp = p.hp
        Player.maxHp = p.maxHp
        Player.level = p.level
        Player.exp = p.exp
        Player.expToNext = p.expToNext
        Player.kills = p.kills
        Player.skills = p.skills or {}

        Player.overloadKills = p.overloadKills or 0
        Player.overloadActive = p.overloadActive or false
        Player.overloadTimer = p.overloadTimer or 0

        Player.attackTimer = p.attackTimer or 0
        Player.attackInterval = p.attackInterval or 0
        Player.extraBullets = p.extraBullets or 0
        Player.pierceCount = p.pierceCount or 0
        Player.bounceCount = p.bounceCount or 0

        Player.invTimer = p.invTimer or 0
        Player.guardianCharges = p.guardianCharges or 0
        Player.shieldCharges = p.shieldCharges or 0
        Player.shieldTimer = p.shieldTimer or 0
        Player.shieldInterval = p.shieldInterval or 0
        Player.regenRate = p.regenRate or 0

        Player.graduationPhase = p.graduationPhase or 0
        Player.droneCollisionDmg = p.droneCollisionDmg or 0
        Player.rageActive = p.rageActive or false
        Player.rageTimer = p.rageTimer or 0

        Player.atkBonus = p.atkBonus or 0
        Player.hpBonus = p.hpBonus or 0
        Player.speedBonus = p.speedBonus or 0
        Player.critBonus = p.critBonus or 0
        Player.magnetBonus = p.magnetBonus or 0
        Player.fireRateBonus = p.fireRateBonus or 0
        Player.knockbackChance = p.knockbackChance or 0
        Player.knockbackForce = p.knockbackForce or 0
        Player.bigBulletChance = p.bigBulletChance or 0
        Player.homingChance = p.homingChance or 0
        Player.lootBonus = p.lootBonus or 0

        -- 重新关联角色定义
        local Config = require("Config")
        Player.charDef = Config.GetCharacter(Player.charId)

        -- 重算派生属性
        Player.RecalcStats()
        -- 恢复存档血量（RecalcStats 可能会截断 hp）
        Player.hp = math.min(p.hp, Player.maxHp)
    end

    -- Wave
    local w = data.wave
    if w then
        Wave.waveNum = w.waveNum or 0
        Wave.timer = w.timer or 0
        Wave.totalTime = w.totalTime or 0
        Wave.waveCoeff = w.waveCoeff or 1.0
        Wave.bossAlive = w.bossAlive or false
        Wave.spawnTimer = w.spawnTimer or 0
    end

    -- Skill 完整状态恢复（计时器 + 运行时实体）
    Skill.ImportState(data.skill)

    -- Loot
    local l = data.loot
    if l then
        Loot.magnetBoostTimer = l.magnetBoostTimer or 0
        Loot.magnetBoostRange = l.magnetBoostRange or 0
        Loot.lastGiftWave = l.lastGiftWave or -99
    end
end

--- 删除游戏存档
function SaveData.DeleteSave()
    if fileSystem:FileExists(GAMESAVE_FILE) then
        local file = File(GAMESAVE_FILE, FILE_WRITE)
        if file:IsOpen() then
            file:WriteString("")
            file:Close()
        end
        print("[SaveData] Game save deleted")
    end
end

--- 解锁 Rep 角色
function SaveData.UnlockRep()
    SaveData.repUnlocked = true
    SaveData.SaveProfile()
    -- 成就：全角色解锁检查
    local okA, Ach = pcall(require, "Achievement")
    if okA and Ach and Ach.CheckAllCharsUnlocked then
        Ach.CheckAllCharsUnlocked()
    end
end

-- 角色解锁条件表：wave=N 表示通关第N波解锁，"ad"表示广告/评价解锁，nil表示初始解锁
SaveData.UNLOCK_CONDITIONS = {
    cat    = nil,      -- 初始解锁
    bean   = 3,        -- 通关第3波解锁
    monkey = 5,        -- 通关第5波解锁
    hand   = 10,       -- 通关第10波解锁
    leaf   = "ad",     -- 广告/评价解锁
    otto   = "ad",     -- 广告/评价解锁
}

--- 检查角色是否已解锁
---@param charId string
---@return boolean
function SaveData.IsCharUnlocked(charId)
    local cond = SaveData.UNLOCK_CONDITIONS[charId]
    if cond == nil then
        return true  -- 初始解锁
    elseif cond == "ad" then
        return SaveData.repUnlocked or (SaveData.adUnlockedChars[charId] == true)
    elseif type(cond) == "number" then
        -- 波次解锁：历史最高波 >= 要求波次
        return SaveData.highestWave >= cond
    end
    return true
end

--- 获取角色解锁条件描述文本
---@param charId string
---@return string
function SaveData.GetUnlockText(charId)
    local cond = SaveData.UNLOCK_CONDITIONS[charId]
    if cond == nil then
        return ""
    elseif cond == "ad" then
        return "解锁方式：评价 / 看广告"
    elseif type(cond) == "number" then
        return "通关第" .. cond .. "波解锁"
    end
    return ""
end

--- 获取角色解锁条件类型
---@param charId string
---@return string "free"|"wave"|"ad"
function SaveData.GetUnlockType(charId)
    local cond = SaveData.UNLOCK_CONDITIONS[charId]
    if cond == nil then return "free"
    elseif cond == "ad" then return "ad"
    elseif type(cond) == "number" then return "wave"
    end
    return "free"
end

--- 通过看广告解锁单个角色
---@param charId string
function SaveData.UnlockCharByAd(charId)
    SaveData.adUnlockedChars[charId] = true
    SaveData.SaveProfile()
    print("[SaveData] Ad-unlocked character: " .. charId)
    -- 成就：全角色解锁检查
    local okA, Ach = pcall(require, "Achievement")
    if okA and Ach and Ach.CheckAllCharsUnlocked then
        Ach.CheckAllCharsUnlocked()
    end
end

--- 解锁所有角色（Alt+P 作弊用）
function SaveData.UnlockAll()
    SaveData.repUnlocked = true
    SaveData.SaveProfile()
    print("[SaveData] All characters unlocked!")
end

-- ============================================================================
-- 局外养成 - Meta Gold 工具函数
-- ============================================================================

--- 增加局外金币并保存（同步云端）
---@param amount number
function SaveData.AddMetaGold(amount)
    SaveData.metaGold = SaveData.metaGold + amount
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    -- 成就：金币累计检查（延迟 require 避免循环依赖）
    local okA, Ach = pcall(require, "Achievement")
    if okA and Ach and Ach.CheckGold then
        Ach.CheckGold(amount)
    end
end

--- 消费局外金币（成功返回 true）
---@param amount number
---@return boolean
function SaveData.SpendMetaGold(amount)
    if SaveData.metaGold < amount then return false end
    SaveData.metaGold = SaveData.metaGold - amount
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 升级遗物（扣费 + 保存 + 云同步）
---@param relicId string
---@param cost number 已验证的花费
function SaveData.UpgradeRelic(relicId, cost)
    SaveData.metaGold = SaveData.metaGold - cost
    SaveData.relicLevels[relicId] = (SaveData.relicLevels[relicId] or 0) + 1
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    -- 成就：遗物升级检查
    local okA, Ach = pcall(require, "Achievement")
    if okA and Ach and Ach.CheckRelicUpgrade then
        Ach.CheckRelicUpgrade()
    end
end

--- 能否再看广告获取金币（今日不超过10次）
---@return boolean
function SaveData.CanWatchAdForGold()
    if SaveData.adGoldDate ~= TodayKey() then
        SaveData.adGoldCount = 0
        SaveData.adGoldDate  = TodayKey()
    end
    return SaveData.adGoldCount < 10
end

--- 看完广告后获得 500 金币
function SaveData.ClaimAdGold()
    if SaveData.adGoldDate ~= TodayKey() then
        SaveData.adGoldCount = 0
        SaveData.adGoldDate  = TodayKey()
    end
    if SaveData.adGoldCount >= 10 then return end
    SaveData.adGoldCount = SaveData.adGoldCount + 1
    SaveData.metaGold    = SaveData.metaGold + 500
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
end

-- ============================================================================
-- 图腾系统 - 背包 CRUD
-- ============================================================================

--- 添加图腾到背包（超出600上限则丢弃）
---@param totem table { typeId, rarity }
---@return boolean 是否成功添加
function SaveData.AddTotem(totem)
    if #SaveData.totems >= TotemSystem.MAX_INVENTORY then
        print("[SaveData] Totem inventory full (" .. TotemSystem.MAX_INVENTORY .. ")")
        return false
    end
    table.insert(SaveData.totems, { typeId = totem.typeId, rarity = totem.rarity })
    SaveData._totemsDirty = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 出售背包中指定索引的图腾
---@param index number 背包索引（1-based）
---@return number 获得的金币（0表示失败）
function SaveData.SellTotem(index)
    local totem = SaveData.totems[index]
    if not totem then return 0 end
    local price = TotemSystem.GetSellPrice(totem.rarity)
    table.remove(SaveData.totems, index)
    SaveData.metaGold = SaveData.metaGold + price
    SaveData._totemsDirty = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return price
end

--- 批量出售指定稀有度的全部图腾
---@param rarity string
---@return number totalGold 总获得金币
---@return number count 出售数量
function SaveData.SellAllByRarity(rarity)
    local price = TotemSystem.GetSellPrice(rarity)
    local count = 0
    for i = #SaveData.totems, 1, -1 do
        if SaveData.totems[i].rarity == rarity then
            table.remove(SaveData.totems, i)
            count = count + 1
        end
    end
    if count > 0 then
        local totalGold = price * count
        SaveData.metaGold = SaveData.metaGold + totalGold
        SaveData._totemsDirty = true
        SaveData.SaveProfile()
        SaveData.SyncMetaToCloud()
        return totalGold, count
    end
    return 0, 0
end

--- 从背包装备图腾（移出背包，放入装备栏）
---@param index number 背包索引
---@return boolean 是否成功
function SaveData.EquipTotem(index)
    if #SaveData.equippedTotems >= TotemSystem.MAX_EQUIPPED then return false end
    local totem = SaveData.totems[index]
    if not totem then return false end
    table.remove(SaveData.totems, index)
    table.insert(SaveData.equippedTotems, { typeId = totem.typeId, rarity = totem.rarity })
    SaveData._totemsDirty = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 卸下装备栏图腾（放回背包）
---@param slotIndex number 装备栏索引（1-3）
---@return boolean 是否成功
function SaveData.UnequipTotem(slotIndex)
    local totem = SaveData.equippedTotems[slotIndex]
    if not totem then return false end
    -- 检查背包是否已满
    if #SaveData.totems >= TotemSystem.MAX_INVENTORY then return false end
    table.remove(SaveData.equippedTotems, slotIndex)
    table.insert(SaveData.totems, { typeId = totem.typeId, rarity = totem.rarity })
    SaveData._totemsDirty = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 合成图腾：从背包中取出3个同稀有度图腾，生成1个新图腾
---@param rarity string 要合成的稀有度
---@return table|nil newTotem 合成结果，nil表示失败
---@return table|nil consumed 被消耗的3个原材料 { {typeId,rarity}, ... }
function SaveData.SynthesizeTotems(rarity)
    if rarity == "legendary" then return nil, nil end

    -- 找出该稀有度的背包索引
    local indices = {}
    for i, t in ipairs(SaveData.totems) do
        if t.rarity == rarity then
            indices[#indices + 1] = i
            if #indices >= 3 then break end
        end
    end
    if #indices < 3 then return nil, nil end

    -- 记录被消耗的原材料信息
    table.sort(indices)
    local consumed = {}
    for _, idx in ipairs(indices) do
        local t = SaveData.totems[idx]
        consumed[#consumed + 1] = { typeId = t.typeId, rarity = t.rarity }
    end

    -- 从后往前删除（避免索引偏移）
    for i = 3, 1, -1 do
        table.remove(SaveData.totems, indices[i])
    end

    -- 生成新图腾（类型从新稀有度对应的类型池随机）
    local newRarity = TotemSystem.Synthesize(rarity)
    local pool = TotemSystem.GetTypesForRarity(newRarity)
    local newTypeId = pool[math.random(1, #pool)]
    local newTotem = { typeId = newTypeId, rarity = newRarity }
    table.insert(SaveData.totems, newTotem)

    SaveData._totemsDirty = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return newTotem, consumed
end

--- 一键合成所有可合成的图腾（非罕见稀有度，每次3→1循环合成）
---@return table[] results 所有合成结果列表
function SaveData.BatchSynthesizeAll()
    local results = {}
    for _, rarity in ipairs({ "junk", "normal", "rare" }) do
        while true do
            local count = 0
            for _, t in ipairs(SaveData.totems) do
                if t.rarity == rarity then count = count + 1 end
            end
            if count < 3 then break end
            local result = SaveData.SynthesizeTotems(rarity)
            if result then
                results[#results + 1] = result
            else
                break
            end
        end
    end
    -- SynthesizeTotems 每次已调用 SaveProfile+SyncMetaToCloud，这里不需重复
    return results
end

--- 获取按稀有度统计的背包图腾数量
---@return table { junk=N, normal=N, rare=N, legendary=N }
function SaveData.GetTotemCounts()
    return TotemSystem.CountByRarity(SaveData.totems)
end

-- ============================================================================
-- 符文系统 - CRUD
-- ============================================================================

--- 添加符文到拥有集合
---@param runeId string
---@return boolean 是否成功（已拥有则返回false）
function SaveData.AddRune(runeId)
    if SaveData.ownedRunes[runeId] then return false end
    if not RuneSystem.GetRune(runeId) then return false end
    SaveData.ownedRunes[runeId] = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 装备符文
---@param runeId string
---@return boolean 是否成功
function SaveData.EquipRune(runeId)
    if not SaveData.ownedRunes[runeId] then return false end
    if #SaveData.equippedRunes >= RuneSystem.MAX_EQUIPPED then return false end
    -- 检查是否已装备
    for _, rid in ipairs(SaveData.equippedRunes) do
        if rid == runeId then return false end
    end
    SaveData.equippedRunes[#SaveData.equippedRunes + 1] = runeId
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 卸下符文
---@param slotIndex number 装备栏索引（1-2）
---@return boolean 是否成功
function SaveData.UnequipRune(slotIndex)
    if not SaveData.equippedRunes[slotIndex] then return false end
    table.remove(SaveData.equippedRunes, slotIndex)
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

-- ============================================================================
-- 皮肤系统 - CRUD
-- ============================================================================

--- 解锁皮肤
---@param skinId string
---@return boolean 是否成功（已拥有则返回false）
function SaveData.UnlockSkin(skinId)
    if SaveData.ownedSkins[skinId] then return false end
    if not SkinSystem.GetSkin(skinId) then return false end
    SaveData.ownedSkins[skinId] = true
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 装备皮肤（为指定角色设置皮肤）
---@param charId string
---@param skinId string
---@return boolean 是否成功
function SaveData.EquipSkin(charId, skinId)
    if not SaveData.ownedSkins[skinId] then return false end
    local skin = SkinSystem.GetSkin(skinId)
    if not skin or skin.charId ~= charId then return false end
    SaveData.equippedSkins[charId] = skinId
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    return true
end

--- 卸下皮肤（恢复默认外观）
---@param charId string
function SaveData.UnequipSkin(charId)
    if not SaveData.equippedSkins[charId] then return end
    SaveData.equippedSkins[charId] = nil
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
end

--- 获取角色当前装备的皮肤ID
---@param charId string
---@return string|nil skinId
function SaveData.GetEquippedSkin(charId)
    return SaveData.equippedSkins[charId]
end

--- 检查皮肤是否已拥有
---@param skinId string
---@return boolean
function SaveData.IsSkinOwned(skinId)
    return SaveData.ownedSkins[skinId] == true
end

-- ============================================================================
-- 每日挑战名人堂
-- ============================================================================

--- 添加名人堂记录（达到每日排行榜 Top3 时调用）
--- 自动去重（同一 dateKey + nickname 不重复添加），最多保留最近 100 条
---@param dateKey string 日期标识（如 "0429"）
---@param rank number 排名 1-3
---@param nickname string 玩家昵称
---@param wave number 到达波次
function SaveData.AddToHallOfFame(dateKey, rank, nickname, wave)
    -- 去重检查
    for _, entry in ipairs(SaveData.hallOfFame) do
        if entry.dateKey == dateKey and entry.nickname == nickname then
            -- 同日同人，更新更好成绩
            if wave > (entry.wave or 0) then
                entry.wave = wave
                entry.rank = rank
                SaveData.SaveProfile()
            end
            return
        end
    end
    SaveData.hallOfFame[#SaveData.hallOfFame + 1] = {
        dateKey  = dateKey,
        rank     = rank,
        nickname = nickname,
        wave     = wave,
    }
    -- 只保留最近 100 条
    while #SaveData.hallOfFame > 100 do
        table.remove(SaveData.hallOfFame, 1)
    end
    SaveData.SaveProfile()
    print("[SaveData] Hall of Fame: " .. nickname .. " rank#" .. rank .. " wave=" .. wave .. " date=" .. dateKey)
end

-- ============================================================================
-- 波次追踪
-- ============================================================================

--- 更新历史最高波次（如有提升则云同步）
---@param wave number
function SaveData.UpdateHighestWave(wave)
    if wave <= SaveData.highestWave then return end
    SaveData.highestWave = wave
    SaveData.SaveProfile()
    SaveData.SyncMetaToCloud()
    print("[SaveData] New highest wave: " .. wave)
end

-- ============================================================================
-- 云端同步（clientCloud）
-- ============================================================================

--- 将 meta 数据推送到云端（BatchSet 链式 API）
function SaveData.SyncMetaToCloud()
    if not getClientCloud() then return end
    local ok2, err = pcall(function()
        local batch = getClientCloud():BatchSet()
        -- 整数字段 → iscores（SetInt）
        batch:SetInt(CLOUD_KEY_META_GOLD,    SaveData.metaGold)
        batch:SetInt(CLOUD_KEY_AD_COUNT,     SaveData.adGoldCount)
        batch:SetInt(CLOUD_KEY_AD_DATE,      SaveData.adGoldDate ~= "" and tonumber(SaveData.adGoldDate) or 0)
        batch:SetInt(CLOUD_KEY_HIGHEST_WAVE, SaveData.highestWave)
        -- 遗物等级（整数）
        for _, rid in ipairs(RELIC_IDS) do
            batch:SetInt(CLOUD_KEY_RELIC_PREFIX .. rid, SaveData.relicLevels[rid] or 0)
        end

        -- 图腾背包（聚合计数JSON → values）
        local totemCounts = TotemSystem.AggregateTotems(SaveData.totems)
        local totemJson = cjson and cjson.encode(totemCounts) or "{}"
        batch:Set(CLOUD_KEY_TOTEMS_V2, totemJson)

        -- 已装备图腾（紧凑 {id,r} 格式 JSON数组 → values）
        local equippedPacked = SaveData._packTotemList(SaveData.equippedTotems)
        local equippedJson = cjson and cjson.encode(equippedPacked) or "[]"
        batch:Set(CLOUD_KEY_EQUIPPED_V2, equippedJson)

        -- 符文（JSON）
        local runeIdList = {}
        for runeId in pairs(SaveData.ownedRunes) do
            runeIdList[#runeIdList + 1] = runeId
        end
        batch:Set(CLOUD_KEY_RUNES, cjson and cjson.encode(runeIdList) or "[]")
        batch:Set(CLOUD_KEY_EQUIPPED_RUNES, cjson and cjson.encode(SaveData.equippedRunes) or "[]")

        -- 皮肤（JSON）
        local skinIdList = {}
        for skinId in pairs(SaveData.ownedSkins) do
            skinIdList[#skinIdList + 1] = skinId
        end
        batch:Set(CLOUD_KEY_SKINS, cjson and cjson.encode(skinIdList) or "[]")
        batch:Set(CLOUD_KEY_EQUIPPED_SKINS, cjson and cjson.encode(SaveData.equippedSkins) or "{}")

        -- 昵称（字符串 → values）
        if SaveData.nickname and SaveData.nickname ~= "" then
            batch:Set(CLOUD_KEY_NICKNAME, SaveData.nickname)
        end

        -- 成就位掩码（整数 → iscores）
        local Achievement = require("Achievement")
        batch:SetInt(CLOUD_KEY_ACHIEVEMENTS, Achievement.EncodeBitmask())

        batch:Save("sync meta v2", {
            ok = function()
                print("[SaveData] Cloud sync OK")
            end,
            error = function(code, reason)
                print("[SaveData] Cloud sync ERROR: code=" .. tostring(code) .. " reason=" .. tostring(reason))
            end,
        })
    end)
    if not ok2 then
        print("[SaveData] Cloud sync pcall failed: " .. tostring(err))
    end
end

--- 从云端拉取 meta 数据，合并到本地
---@param callback function|nil 拉取完成后回调
function SaveData.LoadMetaFromCloud(callback)
    if not getClientCloud() then
        if callback then callback() end
        return
    end

    -- 构建 BatchGet 链
    local batchGet = getClientCloud():BatchGet()
    batchGet:Key(CLOUD_KEY_META_GOLD)
    batchGet:Key(CLOUD_KEY_AD_COUNT)
    batchGet:Key(CLOUD_KEY_AD_DATE)
    batchGet:Key(CLOUD_KEY_HIGHEST_WAVE)
    batchGet:Key(CLOUD_KEY_TOTEMS_V2)
    batchGet:Key(CLOUD_KEY_EQUIPPED_V2)
    batchGet:Key(CLOUD_KEY_NICKNAME)
    batchGet:Key(CLOUD_KEY_ACHIEVEMENTS)
    batchGet:Key(CLOUD_KEY_RUNES)
    batchGet:Key(CLOUD_KEY_EQUIPPED_RUNES)
    batchGet:Key(CLOUD_KEY_SKINS)
    batchGet:Key(CLOUD_KEY_EQUIPPED_SKINS)
    for _, rid in ipairs(RELIC_IDS) do
        batchGet:Key(CLOUD_KEY_RELIC_PREFIX .. rid)
    end

    batchGet:Fetch({
        ok = function(values, iscores)
            local dataChanged = false -- 追踪是否有实际数据变更

            -- 金币（取最大值）
            local cloudGold = iscores[CLOUD_KEY_META_GOLD]
            if cloudGold and type(cloudGold) == "number" and cloudGold > SaveData.metaGold then
                SaveData.metaGold = cloudGold
                dataChanged = true
            end

            -- 广告次数（仅在同一天时同步）
            local cloudDate  = iscores[CLOUD_KEY_AD_DATE]
            local cloudCount = iscores[CLOUD_KEY_AD_COUNT]
            local todayKey   = TodayKey()
            if cloudDate and tostring(cloudDate) == todayKey then
                SaveData.adGoldCount = math.max(SaveData.adGoldCount, cloudCount or 0)
            end
            SaveData.adGoldDate = todayKey

            -- 最高波次
            local cloudWave = iscores[CLOUD_KEY_HIGHEST_WAVE]
            if cloudWave and type(cloudWave) == "number" and cloudWave > SaveData.highestWave then
                SaveData.highestWave = cloudWave
                dataChanged = true
            end

            -- 遗物等级（取最大值）
            for _, rid in ipairs(RELIC_IDS) do
                local cloudLevel = iscores[CLOUD_KEY_RELIC_PREFIX .. rid]
                if cloudLevel and type(cloudLevel) == "number" then
                    local localLevel = SaveData.relicLevels[rid] or 0
                    if cloudLevel > localLevel then
                        SaveData.relicLevels[rid] = cloudLevel
                        dataChanged = true
                    end
                end
            end

            -- 图腾背包（本地权威：本地有数据则保留本地，仅本地为空时用云端恢复）
            -- 合成等操作会减少图腾数量，云端可能存着旧的更多数据，
            -- 如果用"云端权威"会把合成后的结果回退到合成前 → 图腾"丢失"
            local cloudTotemRaw = values[CLOUD_KEY_TOTEMS_V2]
            if #SaveData.totems == 0 and cloudTotemRaw then
                -- 引擎会自动 JSON 解码 table/数组，所以 cloudTotemRaw 可能是 string 也可能是 table
                local cloudCounts = nil
                if type(cloudTotemRaw) == "table" then
                    cloudCounts = cloudTotemRaw
                elseif type(cloudTotemRaw) == "string" and cloudTotemRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudTotemRaw)
                    if okJ and type(decoded) == "table" then
                        cloudCounts = decoded
                    end
                end
                if cloudCounts then
                    local cloudHasData = false
                    for _, cnt in pairs(cloudCounts) do
                        if type(cnt) == "number" and cnt > 0 then
                            cloudHasData = true
                            break
                        end
                    end
                    if cloudHasData then
                        SaveData.totems = TotemSystem.ExpandTotems(cloudCounts)
                        while #SaveData.totems > TotemSystem.MAX_INVENTORY do
                            table.remove(SaveData.totems)
                        end
                        SaveData._totemsDirty = true
                        dataChanged = true
                        print("[SaveData] Local totems empty, restored " .. #SaveData.totems .. " from cloud")
                    end
                end
            else
                print("[SaveData] Keeping local totems (" .. #SaveData.totems .. "), cloud backup skipped")
            end

            -- 已装备图腾（本地权威：同理，本地有则保留，仅本地为空时用云端恢复）
            local cloudEquippedRaw = values[CLOUD_KEY_EQUIPPED_V2]
            if #SaveData.equippedTotems == 0 and cloudEquippedRaw then
                -- 引擎会自动 JSON 解码 table/数组，所以 cloudEquippedRaw 可能是 string 也可能是 table
                local cloudEquipped = nil
                if type(cloudEquippedRaw) == "table" then
                    cloudEquipped = cloudEquippedRaw
                elseif type(cloudEquippedRaw) == "string" and cloudEquippedRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudEquippedRaw)
                    if okJ and type(decoded) == "table" then
                        cloudEquipped = decoded
                    end
                end
                if cloudEquipped then
                    -- 使用 _unpackTotemList 兼容新旧格式
                    local valid = SaveData._unpackTotemList(cloudEquipped)
                    -- 限制最大装备数
                    while #valid > TotemSystem.MAX_EQUIPPED do
                        table.remove(valid)
                    end
                    if #valid > 0 then
                        SaveData.equippedTotems = valid
                        SaveData._totemsDirty = true
                        dataChanged = true
                        print("[SaveData] Local equipped empty, restored " .. #valid .. " from cloud")
                    end
                end
            else
                print("[SaveData] Keeping local equipped (" .. #SaveData.equippedTotems .. "), cloud backup skipped")
            end

            -- 符文（本地权威：本地有则保留，仅本地为空时用云端恢复）
            local localRuneCount = 0
            for _ in pairs(SaveData.ownedRunes) do localRuneCount = localRuneCount + 1 end
            if localRuneCount == 0 then
                local cloudRunesRaw = values[CLOUD_KEY_RUNES]
                local cloudRuneList = nil
                if type(cloudRunesRaw) == "table" then
                    cloudRuneList = cloudRunesRaw
                elseif type(cloudRunesRaw) == "string" and cloudRunesRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudRunesRaw)
                    if okJ and type(decoded) == "table" then cloudRuneList = decoded end
                end
                if cloudRuneList then
                    for _, runeId in ipairs(cloudRuneList) do
                        if RuneSystem.GetRune(runeId) then
                            SaveData.ownedRunes[runeId] = true
                            dataChanged = true
                        end
                    end
                end
                -- 已装备符文
                local cloudEqRunesRaw = values[CLOUD_KEY_EQUIPPED_RUNES]
                local cloudEqRunes = nil
                if type(cloudEqRunesRaw) == "table" then
                    cloudEqRunes = cloudEqRunesRaw
                elseif type(cloudEqRunesRaw) == "string" and cloudEqRunesRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudEqRunesRaw)
                    if okJ and type(decoded) == "table" then cloudEqRunes = decoded end
                end
                if cloudEqRunes then
                    SaveData.equippedRunes = {}
                    for _, runeId in ipairs(cloudEqRunes) do
                        if SaveData.ownedRunes[runeId] and #SaveData.equippedRunes < RuneSystem.MAX_EQUIPPED then
                            SaveData.equippedRunes[#SaveData.equippedRunes + 1] = runeId
                            dataChanged = true
                        end
                    end
                end
                if dataChanged then
                    print("[SaveData] Local runes empty, restored from cloud")
                end
            end

            -- 皮肤（本地权威：本地有则保留，仅本地为空时用云端恢复）
            local localSkinCount = 0
            for _ in pairs(SaveData.ownedSkins) do localSkinCount = localSkinCount + 1 end
            if localSkinCount == 0 then
                local cloudSkinsRaw = values[CLOUD_KEY_SKINS]
                local cloudSkinList = nil
                if type(cloudSkinsRaw) == "table" then
                    cloudSkinList = cloudSkinsRaw
                elseif type(cloudSkinsRaw) == "string" and cloudSkinsRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudSkinsRaw)
                    if okJ and type(decoded) == "table" then cloudSkinList = decoded end
                end
                if cloudSkinList then
                    for _, skinId in ipairs(cloudSkinList) do
                        if SkinSystem.GetSkin(skinId) then
                            SaveData.ownedSkins[skinId] = true
                            dataChanged = true
                        end
                    end
                end
                -- 已装备皮肤
                local cloudEqSkinsRaw = values[CLOUD_KEY_EQUIPPED_SKINS]
                local cloudEqSkins = nil
                if type(cloudEqSkinsRaw) == "table" then
                    cloudEqSkins = cloudEqSkinsRaw
                elseif type(cloudEqSkinsRaw) == "string" and cloudEqSkinsRaw ~= "" and cjson then
                    local okJ, decoded = pcall(cjson.decode, cloudEqSkinsRaw)
                    if okJ and type(decoded) == "table" then cloudEqSkins = decoded end
                end
                if cloudEqSkins then
                    SaveData.equippedSkins = {}
                    for charId, skinId in pairs(cloudEqSkins) do
                        if SaveData.ownedSkins[skinId] and SkinSystem.GetSkin(skinId) then
                            SaveData.equippedSkins[charId] = skinId
                            dataChanged = true
                        end
                    end
                end
                if dataChanged then
                    print("[SaveData] Local skins empty, restored from cloud")
                end
            end

            -- 昵称（云端权威，但跳过空值以防覆盖本地）
            local cloudNickname = values[CLOUD_KEY_NICKNAME]
            if cloudNickname and type(cloudNickname) == "string" and cloudNickname ~= "" then
                if cloudNickname ~= SaveData.nickname then
                    SaveData.nickname = cloudNickname
                    dataChanged = true
                end
            end

            -- 成就位掩码合并
            local cloudAchMask = iscores[CLOUD_KEY_ACHIEVEMENTS]
            if cloudAchMask and type(cloudAchMask) == "number" and cloudAchMask > 0 then
                local Achievement = require("Achievement")
                local hasNew = Achievement.MergeFromBitmask(cloudAchMask)
                if hasNew then
                    -- 保存成就本地文件
                    Achievement.Save()
                end
            end

            if dataChanged then
                SaveData.SaveProfile()
                print("[SaveData] Cloud meta merged & saved: gold=" .. SaveData.metaGold
                      .. " highestWave=" .. SaveData.highestWave
                      .. " totems=" .. #SaveData.totems)
            else
                print("[SaveData] Cloud meta loaded, no changes to save: gold=" .. SaveData.metaGold
                      .. " highestWave=" .. SaveData.highestWave
                      .. " totems=" .. #SaveData.totems)
            end
            if callback then callback() end
        end,
        error = function(code, reason)
            print("[SaveData] Cloud load ERROR: code=" .. tostring(code) .. " reason=" .. tostring(reason))
            if callback then callback() end
        end
    })
end

--- 初始化（加载 profile）
function SaveData.Init()
    SaveData.LoadProfile()
    print("[SaveData] Profile loaded, nickname=" .. tostring(SaveData.nickname))
end

return SaveData
