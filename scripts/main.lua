--- ============================================================================
--- Emoji幸存者 - 入口分流
--- 服务端 headless 只加载 network.Server；客户端走 game.client_main
--- ============================================================================

if IsServerMode and IsServerMode() then
    local Server = require("network.Server")

    function Start()
        Server.Start()
    end

    function Stop()
        if Server.Stop then Server.Stop() end
    end

    return
end

local ClientMain = require("game.client_main")

function Start()
    ClientMain.Start()
end

function Stop()
    ClientMain.Stop()
end
