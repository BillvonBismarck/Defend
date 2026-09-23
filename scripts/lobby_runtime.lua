--- ============================================================================
--- 自定义大厅：启动即快速匹配，超时进离线模式
--- ============================================================================

local UI = require("urhox-libs.UI")
local GameMode = require("GameMode")

UI.Init({
    theme = "default-dark",
    scale = UI.Scale.DEFAULT,
})

local MATCH_TIMEOUT = 5.0

return function(ctx)
    local client, root = ctx.client, ctx.root
    local input = GetInput and GetInput()
    if input then input.mouseVisible = true end

    local statusLabel
    local progressBar
    local matched = false
    local fallbacked = false
    local elapsed = 0
    local updateSub = nil
    local localGame = nil

    local function setStatus(text)
        if statusLabel and statusLabel.SetText then
            statusLabel:SetText(text)
        end
        print("[Lobby] " .. tostring(text))
    end

    local function clearRoot()
        local children = {}
        for _, child in ipairs(root.children or {}) do
            children[#children + 1] = child
        end
        for _, child in ipairs(children) do
            if child.Destroy then child:Destroy() end
        end
    end

    local function stopLocalGame()
        if localGame and type(localGame.Stop) == "function" then
            pcall(localGame.Stop)
        end
        localGame = nil
    end

    local function startOffline()
        if fallbacked then return end
        fallbacked = true
        if client.CancelMatch then
            pcall(function() client:CancelMatch() end)
        end
        if updateSub then
            UnsubscribeFromEvent(updateSub)
            updateSub = nil
        end
        clearRoot()
        GameMode.SetOffline(true)
        print("[Lobby] 匹配超时/失败，进入离线模式")
        local ClientMain = require("game.client_main")
        ClientMain.Start({ offline = true })
        localGame = ClientMain
    end

    local startMatch

    local function retryOnline()
        print("[Lobby] 重试联机")
        stopLocalGame()
        fallbacked = false
        matched = false
        elapsed = 0
        GameMode.SetOffline(false)
        startMatch()
    end

    local function buildWaitingUI()
        clearRoot()
        local view = UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = { 10, 8, 25, 255 },
            flexDirection = "column",
            alignItems = "center",
            justifyContent = "center",
            gap = 18,
        }
        view:AddChild(UI.Label {
            text = "Emoji幸存者",
            fontSize = 36,
            fontColor = { 255, 225, 85, 255 },
        })
        statusLabel = UI.Label {
            text = "正在匹配对局…",
            fontSize = 22,
            fontColor = { 180, 210, 255, 255 },
        }
        view:AddChild(statusLabel)
        progressBar = UI.ProgressBar {
            width = 360, height = 12, value = 0,
        }
        view:AddChild(progressBar)
        root:AddChild(view)
    end

    startMatch = function()
        buildWaitingUI()
        local userId = client.GetMyUserId and client:GetMyUserId() or 0
        print("[Lobby] 进入自定义大厅入口 userId=" .. tostring(userId)
            .. " networkMode=" .. tostring(IsNetworkMode and IsNetworkMode() or false))
        print("[Lobby] 发起快速匹配，等待上限 " .. MATCH_TIMEOUT .. " 秒")

        local ok, err = pcall(function()
            client:StartMatch {
                onStarted = function()
                    setStatus("正在匹配对局…")
                end,
                onMatchFound = function()
                    matched = true
                    setStatus("已匹配到对局，等待引擎连服并切换游戏脚本")
                    print("[Lobby] 已匹配到对局，等待引擎连服并切换游戏脚本")
                end,
                onProgress = function(p, s)
                    if progressBar and progressBar.SetValue then
                        progressBar:SetValue(p or 0)
                    end
                    if s and s ~= "" then
                        setStatus("连服中 " .. tostring(math.floor((p or 0) * 100)) .. "% " .. s)
                    end
                end,
                onError = function(code, message)
                    print("[Lobby] StartMatch 失败 code=" .. tostring(code)
                        .. " msg=" .. tostring(message))
                    startOffline()
                end,
            }
        end)
        if not ok then
            print("[Lobby] StartMatch 调用异常: " .. tostring(err))
            startOffline()
        end
    end

    updateSub = SubscribeToEvent("Update", function(_, eventData)
        if fallbacked or matched then return end
        local dt = 0
        if eventData and eventData["TimeStep"] then
            dt = eventData["TimeStep"]:GetFloat()
        end
        elapsed = elapsed + dt
        if progressBar and progressBar.SetValue and not matched then
            progressBar:SetValue(math.min(0.99, elapsed / MATCH_TIMEOUT))
        end
        if elapsed >= MATCH_TIMEOUT then
            startOffline()
        end
    end)

    -- 给游戏标题页「重试联机」用
    rawset(_G, "LobbyRetryOnline", retryOnline)

    startMatch()

    return {
        stop = function()
            print("[Lobby] 大厅入口退出")
            rawset(_G, "LobbyRetryOnline", nil)
            if updateSub then
                UnsubscribeFromEvent(updateSub)
                updateSub = nil
            end
            -- 匹配成功切游戏脚本时，不要停掉即将启动的 ClientMain
            if fallbacked then
                -- 离线本地游戏仍由大厅 Runtime 托管，stop 时一并停
                stopLocalGame()
            end
        end,
    }
end
