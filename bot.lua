-- 初始化全局变量来存储最新的游戏状态和游戏主机进程。
LatestGameState = LatestGameState or nil
InAction = InAction or false -- 防止代理同时采取多个操作。

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- 函数定义注释用于性能，可用于调试
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- 检查两个点是否在给定范围内。
-- @param x1, y1: 第一个点的坐标
-- @param x2, y2: 第二个点的坐标
-- @param range: 点之间允许的最大距离
-- @return: Boolean 指示点是否在指定范围内
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function calcDistance(x1, y1, x2, y2)
    return math.sqrt(math.pow((y2 - y1), 2) + math.pow((x2 - x1), 2))
end

function is_equal(a, b, epsilon) return math.abs(a - b) < (epsilon or 1e-9) end

-- find near person,return personX,personY
function findRecentPerson()
    local player = LatestGameState.Players[ao.id]
    local minDistance = math.maxinteger
    local x = 0
    local y = 0
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local distance = calcDistance(player.x, player.y, state.x, state.y)
            print(
                colors.blue .. "distance data:" .. distance .. ":" .. player.x ..
                    ',' .. player.y .. ":" .. state.x .. ',' .. state.y ..
                    " minDistance:" .. minDistance)
            if is_equal(minDistance, distance) or distance < minDistance then
                x = state.x
                y = state.y
                minDistance=distance
            end
        end
    end
    return x, y
end

-- go person
function goPerson(personX, personY)
    local player = LatestGameState.Players[ao.id]
    local distanceX = math.abs(personX - player.x)
    local distanceY = math.abs(personY - player.y)
    local moveStr = ""
    if distanceX <= distanceY then
        if player.y <= personY then
            moveStr = moveStr .. "Up"
        else
            moveStr = moveStr .. "Down"
        end

        if player.x ~= personX then
            if player.x < personX then
                moveStr = moveStr .. "Right"
            else
                moveStr = moveStr .. "Left"
            end
        end
    else
        if player.x <= personX then
            moveStr = moveStr .. "Right"
        else
            moveStr = moveStr .. "Left"
        end

        if player.y ~= personY then
            if player.y < personY then
                moveStr = "Up" .. moveStr
            else
                moveStr = "Down" .. moveStr
            end
        end
    end
    return moveStr
end

function getPersonNumber() return #LatestGameState.Players - 1 end

-- void persons
function voidPerson(personX, personY)
    local player = LatestGameState.Players[ao.id]
    local str = goPerson(personX, personY)
    local swtichResult = {
        Up = "Down",
        Down = "Up",
        Left = "Right",
        Right = "Left",
        UpRight = "UpLeft",
        UpLeft = "UpRight",
        DownRight = "DownLeft",
        DownLeft = "DownRight"
    }
    -- void go person in border when only have one person
    if getPersonNumber() == 1 then
        if player.x == 40 or player.y == 40 or player.y == 1 or player.x == 1 then
            return swtichResult[swtichResult[str]]
        end
    end
    return swtichResult[str]
end

-- if have one person,attack he!
-- if have moer person,avoid all person,wait only hava one person!
-- if i can't beat he ,avoid him until the end of the game
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local personNum = getPersonNumber()
    local personX, personY = findRecentPerson()
    local playerEnergy = LatestGameState.Players[ao.id].energy
    if playerEnergy == undefined then playerEnergy = 0 end
    local moveOrder = ""
    print(colors.red .. "Recent Person:" .. personX .. ',' .. personY)
    print(colors.red .. "My Position:" .. player.x .. ',' .. player.y)
    if personNum ~= 1 then
        moveOrder = voidPerson(personX, personY)
        print(colors.red .. "personNum != 1 move:" .. moveOrder)
        ao.send({
            Target = Game,
            Action = "PlayerMove",
            Player = ao.id,
            Direction = moveOrder
        })
    else
        local targetInRange = false
        for target, state in pairs(LatestGameState.Players) do
            if target ~= ao.id and
                inRange(player.x, player.y, state.x, state.y, 1) then
                targetInRange = true
                break
            end
        end
        if playerEnergy <= 10 then
            moveOrder = voidPerson(personX, personY)
            print(colors.red .. "playerEnergy <= 10 move:" .. moveOrder)
            ao.send({
                Target = Game,
                Action = "PlayerMove",
                Player = ao.id,
                Direction = moveOrder
            })
        else
            if targetInRange then
                print(colors.red .. "Player in range. Attacking." ..
                          colors.reset)
                ao.send({
                    Target = Game,
                    Action = "PlayerAttack",
                    Player = ao.id,
                    AttackEnergy = tostring(player.energy)
                })
            else
                moveOrder = goPerson(personX, personY)
                print(colors.red .. "go target:" .. moveOrder)
                ao.send({
                    Target = Game,
                    Action = "PlayerMove",
                    Player = ao.id,
                    Direction = moveOrder
                })
            end
        end
    end
    InAction = false -- InAction 逻辑添加
end

-- 打印游戏公告并触发游戏状态更新的handler。
Handlers.add("PrintAnnouncements",
             Handlers.utils.hasMatchingTag("Action", "Announcement"),
             function(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true --  InAction 逻辑添加
        ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then --  InAction 逻辑添加
        print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end)

-- 触发游戏状态更新的handler。
Handlers.add("GetGameStateOnTick",
             Handlers.utils.hasMatchingTag("Action", "Tick"), function()
    if not InAction then -- InAction 逻辑添加
        InAction = true -- InAction 逻辑添加
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({Target = Game, Action = "GetGameState"})
    else
        print("Previous action still in progress. Skipping.")
    end
end)

-- 等待期开始时自动付款确认的handler。
Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"),
             function(msg)
    print("Auto-paying confirmation fees.")
    ao.send({
        Target = Game,
        Action = "Transfer",
        Recipient = Game,
        Quantity = "1000"
    })
end)

-- 接收游戏状态信息后更新游戏状态的handler。
Handlers.add("UpdateGameState",
             Handlers.utils.hasMatchingTag("Action", "GameState"), function(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
end)

-- 决策下一个最佳操作的handler。
Handlers.add("decideNextAction",
             Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
             function()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false -- InAction 逻辑添加
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
end)

-- 被其他玩家击中时自动攻击的handler。
Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"),
             function(msg)
    if not InAction then --  InAction 逻辑添加
        InAction = true --  InAction 逻辑添加
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == undefined then
            print(colors.red .. "Unable to read energy." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "Attack-Failed",
                Reason = "Unable to read energy."
            })
        elseif playerEnergy == 0 then
            print(colors.red .. "Player has insufficient energy." ..
                      colors.reset)
            ao.send({
                Target = Game,
                Action = "Attack-Failed",
                Reason = "Player has no energy."
            })
        else
            print(colors.red .. "Returning attack." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                AttackEnergy = tostring(playerEnergy)
            })
        end
        InAction = false --  InAction 逻辑添加
        ao.send({Target = ao.id, Action = "Tick"})
    else
        print("Previous action still in progress. Skipping.")
    end
end)
