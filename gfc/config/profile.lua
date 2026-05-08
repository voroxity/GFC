--[[
TODO: as of 29/4/2026 only propellers are suported. add supported for lift blocks
profile is a table the stores specific craft data for the mixer and other functions
i: the index number. think of this a a blocks id
pos: position vector of the block relitive to center of mass.
    this represents the moment arm for force calculations.
facing: a unit vector that denotes the direction the block is facing.
type: the type of block.
    "B" = propeller baring 
    "W" = wodden propeller
    "A" = andesite propller
sails: the number of sailes if the block is a propeller baring.
constant: block related config constants.
map: the peripheral that block(s) of index i are wraped to.
profile = { [i] = {pos = vector.new(x, y, z), facing = vector.new(x, y, z), type = "A", sails = #, constant = #, map = peripheral.wrap("name")} }
]]
local completion = require "cc.completion"
local CFG_FILE = "/CRAFT_PROFILE"

local function vecToTable(v)
    return {x = v.x, y = v.y, z = v.z}
end
local function tableToVec(t)
    return vector.new(t.x, t.y, t.z)
end
-- Write prof to a file
function saveConfig(prof)
    local file = fs.open(CFG_FILE, "w")
    if not file then
        error("Could not open file for writing: " .. CFG_FILE)
    end
    local out = {}
    for i, entry in ipairs(prof) do
        out[i] = {
            pos      = vecToTable(entry.pos),
            facing   = vecToTable(entry.facing),
            type     = entry.type,
            sails    = entry.sails,
            constant = entry.constant,
            map      = peripheral.getName(entry.map),  -- save the name string
        }
    end
    file.write(textutils.serialise(out))
    file.close()
end
-- Read prof from a file
function loadConfig()
    if not fs.exists(CFG_FILE) then return nil, "File does not exist: " .. CFG_FILE end
    local file = fs.open(CFG_FILE, "r")
    if not file then return nil, "Could not open file for reading: " .. CFG_FILE end
    local raw = textutils.unserialise(file.readAll())
    file.close()
    if not raw then return nil, "Failed to parse file: " .. CFG_FILE end
    local out = {}
    for i, entry in ipairs(raw) do
        local handle = peripheral.wrap(entry.map)
        if not handle then error("Could not wrap peripheral: " .. tostring(entry.map)) end
        out[i] = {
            pos      = tableToVec(entry.pos),
            facing   = tableToVec(entry.facing),
            type     = entry.type,
            sails    = entry.sails,
            constant = entry.constant,
            map      = handle,  -- restored as a live peripheral
        }
    end
    return out
end

local DIRECTION_VECTORS = {
    Forward  = vector.new( 0,  0, -1),
    Backward = vector.new( 0,  0,  1),
    Left     = vector.new(-1,  0,  0),
    Right    = vector.new( 1,  0,  0),
    Up       = vector.new( 0,  1,  0),
    Down     = vector.new( 0, -1,  0),
}

local BLOCK_TYPES     = { "A", "B", "W" }
local DIRECTIONS      = { "Forward", "Backward", "Left", "Right", "Up", "Down" }
local THRUST_DEFAULTS = { "1", "0.2" }
local YES_NO          = { "Y", "N" }

local function prompt(progressText, message)
    term.clear()
    term.setCursorPos(1, 1)
    print("Progress:" .. progressText)
    print("== SETUP ==\n")
    print(message)
end

local function confirmedRead(progressText, message, completionFn)
    while true do
        prompt(progressText, message)
        io.write("> ")
        local value = read(nil, nil, completionFn)
        prompt(progressText, message .. "\nYou entered: " .. tostring(value) .. "\nConfirm? (Y/N)")
        io.write("> ")
        local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
        if confirm == "Y" then
            return value
        end
    end
end

local function progressText(stepsDone, stepsTotal)
    return math.floor((stepsDone / stepsTotal) * 100) .. "%"
end

local function setupController(index, stepsDone, stepsTotal)
    local step = index + 1

    local mapName = confirmedRead(
        progressText(stepsDone, stepsTotal),
        string.format("Step %d.1 - Speed controller peripheral name?", step),
        completion.peripheral
    )
    stepsDone = stepsDone + 1

    local blockType, sails
    while true do
        blockType = confirmedRead(
            progressText(stepsDone, stepsTotal),
            string.format("Step %d.2 - Block type?\n  A = Andesite  B = Bearing  W = Wooden", step),
            function(t) return completion.choice(t, BLOCK_TYPES) end
        )
        if blockType == "B" then
            sails = confirmedRead(
                progressText(stepsDone, stepsTotal),
                string.format("Step %d.2.5 - How many sail blocks?", step),
                nil
            )
            sails = tonumber(sails)
        else
            sails = 0
        end
        break
    end
    stepsDone = stepsDone + 1

    local constant = confirmedRead(
        progressText(stepsDone, stepsTotal),
        string.format("Step %d.3 - Thrust constant?\n  Defaults: A & W = 1, B = 0.2", step),
        function(t) return completion.choice(t, THRUST_DEFAULTS) end
    )
    constant = tonumber(constant)
    stepsDone = stepsDone + 1

    local facing = confirmedRead(
        progressText(stepsDone, stepsTotal),
        string.format("Step %d.4 - Direction the block is facing?", step),
        function(t) return completion.choice(t, DIRECTIONS) end
    )
    stepsDone = stepsDone + 1

    local x, y, z
    while true do
        prompt(progressText(stepsDone, stepsTotal),
            string.format("Step %d.5 - Stand on the block and enter its position.", step))
        io.write("X: "); x = tonumber(read())
        io.write("Y: "); y = tonumber(read())
        io.write("Z: "); z = tonumber(read())
        prompt(progressText(stepsDone, stepsTotal),
            string.format("Step %d.5 - Confirm position: %d %d %d\nConfirm? (Y/N)", step, x, y, z))
        io.write("> ")
        local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
        if confirm == "Y" then break end
    end
    stepsDone = stepsDone + 1

    return stepsDone, {
        pos      = vector.new(x, y - 1, z),
        facing   = DIRECTION_VECTORS[facing],
        type     = blockType,
        sails    = sails,
        constant = constant,
        map      = peripheral.wrap(mapName),
    }
end

function setupWizard()
    local count
    while true do
        term.clear(); term.setCursorPos(1, 1)
        print("Progress:0%\n== SETUP ==\n\nStep 1 - How many propeller speed controllers?")
        io.write("> ")
        local input = tonumber(read())
        if input and input > 0 then
            print(string.format("\nConfirm %d controllers. Correct? (Y/N)", input))
            io.write("> ")
            local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
            if confirm == "Y" then
                count = input
                break
            end
        else
            print("Please enter a valid number.")
            sleep(1)
        end
    end

    local stepsTotal = (count * 5) + 2
    local stepsDone  = 1
    local profile    = {}

    for i = 1, count do
        stepsDone, profile[i] = setupController(i, stepsDone, stepsTotal)
    end

    local x, y, z
    while true do
        prompt(progressText(stepsDone, stepsTotal),
            string.format("Step %d - !!IMPORTANT!! Enter the position of the refrence point.", stepsDone))
        io.write("X: "); x = tonumber(read())
        io.write("Y: "); y = tonumber(read())
        io.write("Z: "); z = tonumber(read())
        prompt(progressText(stepsDone, stepsTotal),
            string.format("Step %d - Confirm position: %d %d %d\nConfirm? (Y/N)", stepsDone, x, y, z))
        io.write("> ")
        local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
        if confirm == "Y" then break end
    end

    local r = vector.new(x,y,z)
    for i = 1, #profile do-- sets the r (ref point) as the origin
        profile[i].pos = profile[i].pos - r
    end
    -- profile has been built
    saveConfig(profile)
end

--setupWizard()

return {
    saveConfig=saveConfig,
    loadConfig=loadConfig,
    setupWizard=setupWizard
}