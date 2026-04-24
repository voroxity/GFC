local module = {}

local twPeripheral = nil

local axes = {
    throttle = 0,
    strafe = 0,
    lift = 0,
    turn = 0
}

local KEY_MAP = {
    [87] = { axis = "throttle", force = 1 },  -- W
    [83] = { axis = "throttle", force = -1 }, -- S
    [65] = { axis = "strafe",   force = -1 }, -- A
    [68] = { axis = "strafe",   force = 1 },  -- D
    [32] = { axis = "lift",     force = 1 },  -- Space
    [340] = { axis = "lift",     force = -1 }, -- LShift
    [81] = { axis = "turn",     force = -1 }, -- Q
    [69] = { axis = "turn",     force = 1 }   -- E
}

function module.init(name)
    twPeripheral = peripheral.wrap(name)
    
    if not twPeripheral then
        error("Critical error: can't find '" .. tostring(name) .. "' on the network.")
    end
end

function module.update()
    if not twPeripheral then return end

    axes.throttle = 0
    axes.strafe = 0
    axes.lift = 0
    axes.turn = 0

    local pressedKeys = twPeripheral.getPressedKeyCodes()
    
    if not pressedKeys or #pressedKeys == 0 then return end

    for _, keyCode in pairs(pressedKeys) do
        local mapping = KEY_MAP[keyCode]
        if mapping then
            axes[mapping.axis] = axes[mapping.axis] + mapping.force
        end
    end


    for axisName, value in pairs(axes) do
        if value > 1 then axes[axisName] = 1 end
        if value < -1 then axes[axisName] = -1 end
    end
end

----------------------------------------------------------------------------------
--- Exemple of use :
--- local typewriter = require("typewriter")
--- typewriter.init("typewriter_1")
--- while true do
---    typewriter.update()
---    local controlData = module.getControlData()
---    print("Throttle:", controlData.throttle, "Strafe:", controlData.strafe)
--- end
----------------------------------------------------------------------------------
-- @return table
function module.getControlData()
    return {
        throttle = axes.throttle,
        strafe   = axes.strafe,
        lift     = axes.lift,
        turn     = axes.turn
    }
end

return module