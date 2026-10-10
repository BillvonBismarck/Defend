-- 可重放独立随机源：新模式使用 xorshift32，不改变原幸存者 math.random。
-- 完整 state/calls 在快照中可观察；表现随机不消费这个实例。
local R = {}
R.__index = R
function R.New(seed)
    local self = setmetatable({}, R)
    self:init(seed)
    return self
end
function R:init(seed)
    self.state = math.floor(seed or 20261002) & 0xffffffff
    if self.state == 0 then self.state = 1 end
    self.calls = 0
end
function R:Next()
    local x = self.state
    local a = (x ~ (x << 13)) & 0xffffffff
    local b = (a ~ (a >> 17)) & 0xffffffff
    self.state = (b ~ (b << 5)) & 0xffffffff
    self.calls = self.calls + 1
    return self.state / 4294967296
end
function R:Index(count)
    assert(count > 0, "随机候选数必须大于0")
    return math.floor(self:Next() * count) + 1
end
return R
