-- 固定据点防守 v0.2 唯一玩法入口；旧幸存者不再提供菜单入口。
-- 当前工程为单机，网络发布入口仅保留原平台服务生命周期。
if IsServerMode and IsServerMode() then
    local Server = require("network.Server")
    function Start() Server.Start() end
    function Stop() if Server.Stop then Server.Stop() end end
    return
end
local Runtime = require("defense.Runtime")
function Start() Runtime.Start() end
function Stop() Runtime.Stop() end
