--- ============================================================================
--- SafeMath - 防止数值溢出为负值的安全数学运算
---
--- Lua 5.4 整数范围：-2^63 ~ 2^63-1，但游戏数值超过 2^31 后
--- 在显示、UI渲染、网络传输等场景容易出问题。
--- 本模块将所有游戏数值钳位到安全范围，从源头杜绝溢出。
---
--- 用法：
---   local SM = require("utils.SafeMath")
---   local hp = SM.floor(baseDef.baseHp * waveCoeff)
---   local dmg = SM.mul(atk, multiplier)
--- ============================================================================

local SafeMath = {}

--- 安全整数上限（2^31 - 1 = 2,147,483,647）
--- 选择 2^31 而非 2^53 是因为：
---   1. 伤害数字在 UI 上能正常显示
---   2. 与 32 位系统/协议兼容
---   3. 玩家能理解的数值范围
SafeMath.MAX_INT = 2147483647

--- 安全浮点上限（用于中间计算）
SafeMath.MAX_FLOAT = 2147483647.0

--- 钳位到安全范围 [0, MAX_INT]（游戏数值不应为负）
---@param v number
---@return number
function SafeMath.clamp(v)
    if v ~= v then return 0 end  -- NaN 保护
    if v < 0 then return 0 end
    if v > SafeMath.MAX_INT then return SafeMath.MAX_INT end
    return v
end

--- 安全的 math.floor，结果钳位到 [0, MAX_INT]
--- 替代所有 math.floor(damage)、math.floor(hp) 等场景
---@param v number
---@return integer
function SafeMath.floor(v)
    if v ~= v then return 0 end  -- NaN 保护
    if v < 0 then return 0 end
    if v > SafeMath.MAX_FLOAT then return SafeMath.MAX_INT end
    return math.floor(v)
end

--- 安全乘法：a * b，结果钳位
--- 防止两个大数相乘溢出
---@param a number
---@param b number
---@return number
function SafeMath.mul(a, b)
    local result = a * b
    if result ~= result then return 0 end  -- NaN
    if result < 0 then return 0 end
    if result > SafeMath.MAX_FLOAT then return SafeMath.MAX_FLOAT end
    return result
end

--- 安全乘法取整：math.floor(a * b)，结果钳位
---@param a number
---@param b number
---@return integer
function SafeMath.mulFloor(a, b)
    return SafeMath.floor(a * b)
end

--- 安全指数：base ^ exp，结果钳位
--- 防止 1.05^250 这类指数爆炸
---@param base number
---@param exp number
---@return number
function SafeMath.pow(base, exp)
    local result = base ^ exp
    if result ~= result then return 0 end  -- NaN
    if result < 0 then return 0 end
    if result > SafeMath.MAX_FLOAT then return SafeMath.MAX_FLOAT end
    return result
end

--- 安全加法：a + b，结果钳位
---@param a number
---@param b number
---@return number
function SafeMath.add(a, b)
    local result = a + b
    if result > SafeMath.MAX_FLOAT then return SafeMath.MAX_FLOAT end
    if result < 0 then return 0 end
    return result
end

return SafeMath
