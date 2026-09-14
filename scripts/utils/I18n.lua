--- ============================================================================
--- I18n 轻量级本地化模块
--- 支持 zh / en 两种语言，通过 I18n.t(key) 获取翻译文本
--- ============================================================================

local I18n = {}

--- 当前语言（默认中文）
I18n.lang = "zh"

--- 可用语言列表
I18n.LANGUAGES = { "zh", "en" }
I18n.LANG_LABELS = { zh = "中文", en = "EN" }

-- ========== 翻译表 ==========
local strings = {
    -- ===== 暂停菜单 =====
    pause_title           = { zh = "PAUSED",           en = "PAUSED" },
    pause_resume          = { zh = "继续游戏",          en = "Resume" },
    pause_joystick        = { zh = "🕹 摇杆位置",       en = "🕹 Joystick" },
    pause_joy_left        = { zh = "靠左",              en = "Left" },
    pause_joy_center      = { zh = "居中",              en = "Center" },
    pause_joy_right       = { zh = "靠右",              en = "Right" },
    pause_joy_hide        = { zh = "隐藏",              en = "Hide" },
    pause_move_mode       = { zh = "🎮 移动模式",       en = "🎮 Move Mode" },
    pause_free_dir        = { zh = "自由方向",           en = "Free" },
    pause_eight_dir       = { zh = "八向移动",           en = "8-Way" },
    pause_glow            = { zh = "✨ 辉光效果",       en = "✨ Glow" },
    pause_perf_quality    = { zh = "⚙️ 性能档位",       en = "⚙️ Quality" },
    pause_off             = { zh = "关闭",              en = "OFF" },
    pause_on              = { zh = "开启",              en = "ON" },
    pause_lang            = { zh = "🌐 语言",           en = "🌐 Lang" },
    pause_save_exit       = { zh = "📊 结算退出",       en = "📊 Exit" },

    -- ===== 结算屏 =====
    result_victory        = { zh = "大获全胜！",        en = "VICTORY!" },
    result_fell           = { zh = "倒下了",            en = "Fell" },
    result_survive_time   = { zh = "存活时间",          en = "Time" },
    result_kills          = { zh = "击杀数",            en = "Kills" },
    result_level          = { zh = "到达等级",          en = "Level" },
    result_wave           = { zh = "到达波次",          en = "Wave" },
    result_totems         = { zh = "本局获得图腾",      en = "Totems" },

    -- ===== 标题/通用 =====
    title_leaderboard     = { zh = "全球排行榜",        en = "Leaderboard" },
    title_view_stats      = { zh = "查看全球战绩",      en = "View Stats" },
    title_achievements    = { zh = "成就",              en = "Achieve." },
    title_unlocked        = { zh = "已解锁",            en = "Unlocked" },
    title_local_best      = { zh = "本地 W",            en = "Best W" },
    title_set_name        = { zh = "为自己取一个名字吧", en = "Enter your name" },
    title_name_hint       = { zh = "输入昵称...",        en = "Name..." },
    title_cancel          = { zh = "取消",              en = "Cancel" },
    title_confirm         = { zh = "就这个",            en = "Confirm" },
    title_random          = { zh = "随机",              en = "Random" },
    title_custom          = { zh = "自定义",            en = "Custom" },
    net_unavailable       = { zh = "联网不可用",         en = "Offline" },
    load_failed           = { zh = "加载失败",           en = "Load Error" },

    -- ===== 技能选择 =====
    skill_choose          = { zh = "选择一项强化义体",    en = "Choose Enhancement" },
    skill_weapon          = { zh = "武器",              en = "Weapon" },
    skill_defense         = { zh = "防御",              en = "Defense" },
    skill_attribute       = { zh = "属性",              en = "Attribute" },
    skill_max_stack       = { zh = "最高叠加",           en = "Max Stack" },
    skill_ult_choose      = { zh = "选择你的终极奖励",    en = "Choose Ultimate" },
    skill_full_hp         = { zh = "满血 + 无敌",        en = "Full HP + Invincible" },
    skill_full_hp_desc    = { zh = "完全恢复HP并获得10秒无敌", en = "Restore HP, 10s invincibility" },
    skill_rage            = { zh = "狂暴模式",           en = "Rage Mode" },
    skill_rage_desc       = { zh = "20秒内攻击力x3",     en = "3x ATK for 20s" },

    -- ===== 商店通用 =====
    shop_back             = { zh = "◀ 返回",            en = "◀ Back" },
    shop_equip            = { zh = "装备",              en = "Equip" },
    shop_unequip          = { zh = "卸下",              en = "Unequip" },
    shop_equipped         = { zh = "已装备",            en = "Equipped" },
    shop_sell             = { zh = "出售",              en = "Sell" },
    shop_owned            = { zh = "✓ 已拥有",          en = "✓ Owned" },
    shop_slots_full       = { zh = "槽位已满",           en = "Slots Full" },
    shop_empty            = { zh = "空",                en = "Empty" },

    -- ===== 皮肤商店 =====
    skin_title            = { zh = "🎨 皮肤商店",       en = "🎨 Skins" },
    skin_default          = { zh = "默认外观",           en = "Default" },
    skin_current          = { zh = "当前:",             en = "Current:" },
    skin_restore          = { zh = "恢复默认",           en = "Reset" },
    skin_available        = { zh = "可用皮肤",           en = "Available" },
    skin_none             = { zh = "暂无皮肤",           en = "No Skins" },
    skin_idle             = { zh = "待机",              en = "Idle" },
    skin_move             = { zh = "移动",              en = "Move" },
    skin_hurt             = { zh = "受伤",              en = "Hurt" },
    skin_overload         = { zh = "过载",              en = "Overload" },
    skin_shield           = { zh = "护盾",              en = "Shield" },
    skin_ad_free          = { zh = "看广告免费获取",      en = "Free via Ad" },

    -- ===== 符文商店 =====
    rune_title            = { zh = "🔮 符文管理",       en = "🔮 Runes" },
    rune_collection       = { zh = "符文收藏",           en = "Collection" },
    rune_source           = { zh = "来源:",             en = "Source:" },
    rune_boss_drop        = { zh = "击败Boss · ",       en = "Boss Drop · " },
    rune_locked           = { zh = "🔒 击败对应Boss后有概率掉落", en = "🔒 Drops from Boss" },
    rune_equip_btn        = { zh = "装备符文",           en = "Equip Rune" },
    rune_unequip_btn      = { zh = "卸下符文",           en = "Unequip Rune" },
    rune_no_runes         = { zh = "还没有符文，击败Boss有概率掉落", en = "No runes yet" },

    -- ===== 图腾背包 =====
    totem_title           = { zh = "🏺 图腾背包",       en = "🏺 Totems" },
    totem_rarity_all      = { zh = "全部",              en = "All" },
    totem_rarity_junk     = { zh = "垃圾",              en = "Junk" },
    totem_rarity_normal   = { zh = "普通",              en = "Normal" },
    totem_rarity_rare     = { zh = "稀有",              en = "Rare" },
    totem_rarity_legend   = { zh = "罕见",              en = "Legend" },
    totem_quality         = { zh = "品质:",             en = "Quality:" },
    totem_sell_junk       = { zh = "卖垃圾",            en = "Sell Junk" },
    totem_bonus           = { zh = "加成:",             en = "Bonus:" },
    totem_cross_talent    = { zh = "异界天赋",           en = "Cross Talent" },
    totem_empty           = { zh = "背包为空\n击败Boss可获得图腾", en = "Empty\nDefeat Boss for Totems" },
    totem_none_cat        = { zh = "该分类下没有图腾",    en = "None in category" },
    totem_synth_hold      = { zh = "按住中…",            en = "Hold..." },
    totem_synth_release   = { zh = "松手：全部合成",      en = "Release: Synth All" },
    totem_synth_progress  = { zh = "合成中… 点击可打断",   en = "Synth... Tap to stop" },
    totem_synth_done      = { zh = "合成完成",           en = "Synth Done" },
    totem_synth_all_done  = { zh = "全部合成完成",        en = "All Synth Done" },
    totem_synth_break     = { zh = "已打断合成",          en = "Synth Stopped" },
    totem_synth_none      = { zh = "无可合成图腾",        en = "Nothing to Synth" },
    totem_equip_ok        = { zh = "装备成功！",          en = "Equipped!" },
    totem_equip_full      = { zh = "装备栏已满",          en = "Slots Full" },
    totem_unequipped      = { zh = "已卸下图腾",          en = "Unequipped" },
    totem_sold            = { zh = "出售",               en = "Sold" },
    totem_bulk_sold       = { zh = "批量出售",            en = "Bulk Sold" },

    -- ===== HUD 状态 =====
    hud_crit              = { zh = "暴击+",             en = "Crit+" },
    hud_fire_rate         = { zh = "射速+",             en = "ASpd+" },
    hud_regen             = { zh = "再生+",             en = "Regen+" },
    hud_loot              = { zh = "掉落+",             en = "Loot+" },

    -- ===== 结算 / 每日挑战奖励 =====
    result_gold_reward    = { zh = "💰 +%d 金币",       en = "💰 +%d Gold" },
    result_dc_title       = { zh = "🏆 每日挑战奖励",    en = "🏆 Daily Reward" },
    result_dc_reached     = { zh = "达成: %s",          en = "Reached: %s" },

    -- ===== 技能选择 (SkillSelect) =====
    skill_level_up        = { zh = "LEVEL UP!",        en = "LEVEL UP!" },
    skill_max_stack_fmt   = { zh = "最高叠加 %d 层",    en = "Max %d stacks" },
    skill_ult_title       = { zh = "ULTIMATE REWARD",  en = "ULTIMATE REWARD" },
    skill_type_weapon     = { zh = "⚔ 武器",           en = "⚔ Weapon" },
    skill_type_defense    = { zh = "🛡 防御",           en = "🛡 Defense" },
    skill_type_attr       = { zh = "✧ 属性",           en = "✧ Attribute" },
    skill_countdown_fmt   = { zh = "%d 秒后自动选择",    en = "Auto pick in %ds" },
    skill_countdown_paused = { zh = "广告播放中 · 倒计时已暂停", en = "Ad playing · Timer paused" },
    skill_refresh_ad      = { zh = "📺 看广告换一批",    en = "📺 Watch Ad to Refresh" },
    skill_refresh_loading = { zh = "正在播放广告…",      en = "Playing ad..." },
    skill_refresh_success = { zh = "已换一批新天赋",      en = "Choices refreshed" },
    skill_refresh_incomplete = { zh = "完整观看后才能换一批", en = "Finish the ad to refresh" },
    skill_refresh_unavailable = { zh = "当前环境暂不支持广告", en = "Ads unavailable" },
    skill_refresh_no_choices = { zh = "暂无可刷新的天赋", en = "No choices available" },

    -- ===== 图腾背包 (TotemShop) 额外 =====
    totem_quality_fmt     = { zh = "品质: %s",         en = "Quality: %s" },
    totem_bonus_prefix    = { zh = "加成: ",            en = "Bonus: " },
    totem_bonus_crit      = { zh = "暴击+%d%%",         en = "Crit+%d%%" },
    totem_bonus_firerate  = { zh = "射速+%d%%",         en = "ASpd+%d%%" },
    totem_bonus_regen     = { zh = "再生+%.1f%%/s",     en = "Regen+%.1f%%/s" },
    totem_bonus_loot      = { zh = "掉落+%d%%",         en = "Loot+%d%%" },
    totem_btn_unequip     = { zh = "卸下",              en = "Remove" },
    totem_btn_equip       = { zh = "装备",              en = "Equip" },
    totem_btn_sell        = { zh = "出售 🪙%d",         en = "Sell 🪙%d" },
    totem_btn_sell_junk   = { zh = "卖垃圾×%d",         en = "Sell Junk×%d" },
    totem_empty_bag       = { zh = "背包为空\n击败Boss可获得图腾", en = "Empty\nDefeat Boss for Totems" },

    -- ===== 符文商店 (RuneShop) 额外 =====
    rune_source_fmt       = { zh = "来源: 击败Boss · %s", en = "Drop from Boss · %s" },
    rune_no_runes_long    = { zh = "还没有符文，击败Boss有概率掉落", en = "No runes yet. Drop from Bosses." },
    rune_slots_full       = { zh = "槽位已满",             en = "Slots Full" },

    -- ===== 皮肤商店 (SkinShop) 额外 =====
    skin_ad_price         = { zh = "📺 看广告免费获取  或  🪙%d", en = "📺 Watch Ad (Free)  or  🪙%d" },
    skin_ad_btn_short     = { zh = "📺 免费",              en = "📺 Free" },
    skin_price_fmt        = { zh = "🪙 %d 金币",        en = "🪙 %d Gold" },
    skin_buy_price        = { zh = "🪙%d",              en = "🪙%d" },

    -- ===== 广告礼包 (GiftAd) =====
    gift_ad_exp_tip       = { zh = "观看广告可获得 %d EXP", en = "Watch ad for +%d EXP" },
    gift_ad_give_up       = { zh = "放弃（仅获得 %d EXP）", en = "Skip (only %d EXP)" },

    -- ===== 广告金币 (SkinShop ad area) =====
    ad_gold_btn           = { zh = "📺 观看广告 +500🪙",  en = "📺 Watch Ad +500🪙" },
    ad_gold_remain        = { zh = "今日剩余 %d/10 次",   en = "Today: %d/10 left" },
    ad_gold_done          = { zh = "明天再来吧 (0/10)",    en = "Come back tomorrow" },

    -- ===== 主界面卡片 (main.lua) =====
    card_best_wave        = { zh = "最高 Wave %d",       en = "Best Wave %d" },
    card_local_best       = { zh = "本地 W%d Lv%d",      en = "Local W%d Lv%d" },
    card_unlocked_fmt     = { zh = "%d/%d 已解锁",        en = "%d/%d Unlocked" },
    card_wave_unlock      = { zh = "Wave%d 后解锁",       en = "Unlock at Wave%d" },
    card_relic_unlocked   = { zh = "%d/%d 已解锁",        en = "%d/%d Unlocked" },
    card_rune_equipped    = { zh = "装备 %d/%d",          en = "Equip %d/%d" },
    card_rune_collected   = { zh = "%d/%d 已收集",         en = "%d/%d Collected" },
    card_rune_badge       = { zh = "%d/%d 符文",           en = "%d/%d Runes" },
    card_totem_status     = { zh = "%d/3 装备 · %d 持有",  en = "%d/3 Equip · %d Owned" },
    card_totem_badge      = { zh = "%d/3 图腾",            en = "%d/3 Totems" },
    card_skin_owned       = { zh = "%d/%d 已拥有",         en = "%d/%d Owned" },
    card_skin_badge       = { zh = "%d/%d 皮肤",           en = "%d/%d Skins" },
    card_codex_found      = { zh = "%d/%d 已发现",          en = "%d/%d Found" },
    card_codex_hint       = { zh = "收集所有敌人·Boss·技能·符文·图腾·地图", en = "Collect Enemies·Bosses·Skills·Runes·Totems·Maps" },
    card_best_wave_cur    = { zh = "当前最高：第%d波",      en = "Best: Wave %d" },
    card_locked_wave      = { zh = "🔒 需通关第%d波",      en = "🔒 Reach Wave %d" },
    card_gold_badge       = { zh = "🪙 %d",               en = "🪙 %d" },

    -- ===== 主界面标题 =====
    game_title            = { zh = "emoji 英雄战斗",         en = "Emoji Hero Battle" },
    game_welcome          = { zh = "欢迎来到 emoji 英雄战斗！", en = "Welcome to Emoji Hero Battle!" },
    game_version          = { zh = "v2.0 - emoji 英雄战斗",  en = "v2.0 - Emoji Hero Battle" },

    -- ===== 角色选择 =====
    charsel_start         = { zh = "开始战斗！",           en = "Start Battle!" },
    charsel_diff          = { zh = "难度选择",             en = "Difficulty" },
    charsel_hint          = { zh = "◀ ▶ 切换角色 · 点击按钮开始", en = "◀ ▶ Switch · Tap to Start" },
    charsel_title         = { zh = "选择你的角色",          en = "Choose Your Hero" },
    charsel_subtitle      = { zh = "每个角色拥有独特技能和风格", en = "Each hero has unique skills & style" },
    charsel_skill_label   = { zh = "专属技能",             en = "Unique Skill" },
    charsel_continue      = { zh = "▶️ 继续游戏",          en = "▶️ Continue" },
    charsel_new           = { zh = "🎮 新游戏",            en = "🎮 New Game" },
    charsel_unlock_all    = { zh = "🔗 评价解锁全部",       en = "🔗 Review → Unlock All" },
    charsel_unlock_ad     = { zh = "🎬 广告解锁当前",       en = "🎬 Ad → Unlock This" },
    charsel_unlock_msg    = { zh = "评价解锁全部 · 广告解锁当前角色", en = "Review: All · Ad: Current" },
    charsel_unlocked_all  = { zh = "✅ 已解锁全部角色！感谢评价支持", en = "✅ All heroes unlocked! Thanks!" },
    charsel_dc_title      = { zh = "每日挑战",             en = "Daily Challenge" },

    -- ===== 排行榜 =====
    lb_rank               = { zh = "排名",                 en = "Rank" },
    lb_player             = { zh = "玩家",                 en = "Player" },
    lb_wave               = { zh = "波次",                 en = "Wave" },
    lb_kills              = { zh = "击杀",                 en = "Kills" },
    lb_back               = { zh = "← 返回",              en = "← Back" },
    lb_load_more          = { zh = "加载更多",              en = "Load More" },
    lb_all_loaded         = { zh = "— 已加载全部 —",        en = "— All Loaded —" },
    lb_empty              = { zh = "暂无排行数据",           en = "No data yet" },
    lb_empty_hint         = { zh = "完成一局游戏后你的成绩将自动上传", en = "Play a game to upload your score" },
    lb_retry              = { zh = "请检查网络后重试",        en = "Check network and retry" },

    -- ===== 昵称设置 =====
    nick_prompt           = { zh = "为自己取一个名字吧",     en = "Choose your nickname" },
    nick_prompt_kb        = { zh = "用键盘输入你的名字（回车确认）", en = "Type name (Enter to confirm)" },
    nick_placeholder      = { zh = "输入昵称...",           en = "Enter nickname..." },
    nick_cancel           = { zh = "取消",                  en = "Cancel" },
    nick_done             = { zh = "✅ 完成",               en = "✅ Done" },
    nick_random           = { zh = "🎲 随机",               en = "🎲 Random" },
    nick_custom           = { zh = "✏️ 自定义",             en = "✏️ Custom" },
    nick_confirm          = { zh = "✅ 就这个",              en = "✅ Pick This" },

    -- ===== 首页卡片标题 =====
    card_leaderboard      = { zh = "全球排行榜",             en = "Leaderboard" },
    card_lb_view          = { zh = "查看全球战绩",            en = "View Rankings" },
    card_achievement      = { zh = "成就",                   en = "Achievements" },
    card_relic_shop       = { zh = "遗物商店",                en = "Relic Shop" },
    card_totem_shop       = { zh = "图腾商店",                en = "Totem Shop" },
    card_rune_mgr         = { zh = "符文管理",                en = "Rune Manager" },
    card_skin_shop        = { zh = "皮肤商店",                en = "Skin Shop" },
    card_codex            = { zh = "图鉴收集册",              en = "Codex" },
    card_slot_empty       = { zh = "空",                     en = "—" },
    card_skin_change      = { zh = "更换角色外观",             en = "Change Appearance" },
    card_weekly           = { zh = "周挑战赛季",              en = "Weekly Season" },
    card_weekly_today_fmt = { zh = "今日: %s %s",             en = "Today: %s %s" },
    card_weekly_score_days= { zh = "%d 积分 · 剩余 %d 天",    en = "%d pts · %d days left" },
    card_weekly_last_day  = { zh = "%d 积分 · 最后一天",       en = "%d pts · Last day" },

    -- ===== 排行榜页 =====
    lb_title              = { zh = "🌐 全球排行榜",           en = "🌐 Leaderboard" },
    lb_loading            = { zh = "加载中",                  en = "Loading" },
    lb_error_prefix       = { zh = "⚠️ ",                    en = "⚠️ " },
    lb_subtitle_wave      = { zh = "最高波次排名",              en = "Top Wave" },
    lb_subtitle_kills     = { zh = "累计击杀排名",              en = "Top Kills" },
    lb_subtitle_daily_fmt = { zh = "今日挑战 · %s",            en = "Daily · %s" },
    lb_count_fmt          = { zh = " · 共 %d 人",             en = " · %d players" },
    lb_load_more_loading  = { zh = "加载更多",                 en = "Loading more" },
    lb_me_suffix          = { zh = " (我)",                   en = " (Me)" },
    lb_tab_wave           = { zh = "⚔️ 波次",                 en = "⚔️ Wave" },
    lb_tab_kills          = { zh = "💀 击杀",                 en = "💀 Kills" },
    lb_tab_daily          = { zh = "📅 每日",                 en = "📅 Daily" },

    -- ===== 角色选择页 =====
    charsel_diff          = { zh = "难度选择",                 en = "Difficulty" },
    charsel_unlock_msg2   = { zh = "评价解锁全部 · 广告解锁当前角色", en = "Review: All · Ad: Current" },

    -- ===== 墓碑 =====
    tomb_approach         = { zh = "💬 靠近查看遗言",    en = "💬 View Message" },
    tomb_traveler         = { zh = "旅人",              en = "Traveler" },
    tomb_input_hint       = { zh = "✏️ 留下你的遗言（点击输入）", en = "✏️ Leave your last words (tap)" },
    tomb_input_placeholder = { zh = "写点什么吧…",       en = "Write something..." },
}

--- 获取翻译文本
---@param key string 翻译键
---@param ... any format 参数
---@return string
function I18n.t(key, ...)
    local entry = strings[key]
    if not entry then return key end
    local text = entry[I18n.lang] or entry["zh"] or key
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

--- 切换到下一种语言
function I18n.NextLang()
    for i, lang in ipairs(I18n.LANGUAGES) do
        if lang == I18n.lang then
            I18n.lang = I18n.LANGUAGES[i % #I18n.LANGUAGES + 1]
            return
        end
    end
    I18n.lang = "zh"
end

return I18n
