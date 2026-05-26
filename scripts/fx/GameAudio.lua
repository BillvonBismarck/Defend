--- ============================================================================
--- 游戏音频管理 - BGM + SFX
--- ============================================================================

local GameAudio = {}

-- 音频节点
local bgmNode = nil
---@type SoundSource
local bgmSource = nil

-- SFX 节点池（避免每次创建新节点）
local SFX_POOL_SIZE = 8
local sfxNodes = {}
local sfxSources = {}
local sfxIndex = 1

-- SFX 冷却防止同一音效过于频繁
local sfxCooldowns = {}   -- { [name] = remainingTime }
local SFX_COOLDOWN = {
    shoot = 0.08,       -- 射击音效冷却短，允许密集播放
    pickup = 0.1,
    enemy_die = 0.06,
    hit = 0.05,
    crit_hit = 0.1,
    coin_pickup = 0.08,
    dodge_roll = 0.3,
}

-- 音量设置
local VOLUME = {
    bgm = 0.35,
    shoot = 0.25,
    explosion = 0.5,
    levelup = 0.6,
    player_hurt = 0.5,
    pickup = 0.3,
    enemy_die = 0.3,
    boss_warning = 0.6,
    -- 新增 AI 生成音效
    crit_hit = 0.45,
    shield_up = 0.5,
    heal = 0.4,
    overload_activate = 0.55,
    freeze = 0.4,
    coin_pickup = 0.3,
    wave_start = 0.55,
    skill_select = 0.45,
    bomb_explode = 0.55,
    dodge_roll = 0.35,
}

-- 缓存的 Sound 资源
local soundCache = {}

--- 初始化音频系统
function GameAudio.Init()
    -- BGM 节点
    bgmNode = Node()
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain = VOLUME.bgm

    -- SFX 节点池
    for i = 1, SFX_POOL_SIZE do
        sfxNodes[i] = Node()
        sfxSources[i] = sfxNodes[i]:CreateComponent("SoundSource")
        sfxSources[i].soundType = "Effect"
    end

    -- 预加载常用音效
    local sfxNames = {
        "shoot", "explosion", "levelup", "player_hurt", "pickup", "enemy_die", "boss_warning",
        -- AI 生成音效
        "crit_hit", "shield_up", "heal", "overload_activate", "freeze",
        "coin_pickup", "wave_start", "skill_select", "bomb_explode", "dodge_roll",
    }
    for _, name in ipairs(sfxNames) do
        local path = "audio/sfx/" .. name .. ".ogg"
        local s = cache:GetResource("Sound", path)
        if s then
            soundCache[name] = s
        else
            print("WARN: Failed to load SFX: " .. path)
        end
    end

    -- 预加载 BGM
    local bgm = cache:GetResource("Sound", "audio/music_1774741474417.ogg")
    if bgm then
        bgm.looped = true
        soundCache["bgm"] = bgm
    else
        print("WARN: Failed to load BGM")
    end
end

--- 播放背景音乐
function GameAudio.PlayBGM()
    if soundCache["bgm"] and bgmSource then
        bgmSource:Play(soundCache["bgm"])
    end
end

--- 停止背景音乐
function GameAudio.StopBGM()
    if bgmSource then
        bgmSource:Stop()
    end
end

--- 播放音效
---@param name string 音效名称
---@param gainOverride number|nil 可选音量覆盖
function GameAudio.PlaySFX(name, gainOverride)
    -- 冷却检查
    if sfxCooldowns[name] and sfxCooldowns[name] > 0 then
        return
    end

    local sound = soundCache[name]
    if not sound then return end

    -- 使用池中的下一个 SoundSource
    local source = sfxSources[sfxIndex]
    source.gain = gainOverride or VOLUME[name] or 0.5
    source:Play(sound)

    -- 轮转索引
    sfxIndex = sfxIndex % SFX_POOL_SIZE + 1

    -- 设置冷却
    local cd = SFX_COOLDOWN[name]
    if cd then
        sfxCooldowns[name] = cd
    end
end

--- 更新冷却计时器（每帧调用）
---@param dt number
function GameAudio.Update(dt)
    for name, remaining in pairs(sfxCooldowns) do
        remaining = remaining - dt
        if remaining <= 0 then
            sfxCooldowns[name] = nil
        else
            sfxCooldowns[name] = remaining
        end
    end
end

return GameAudio
