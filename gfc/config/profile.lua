--[[
TODO: as of 29/4/2026 only propellers are supported. add support for lift blocks
profile is a table that stores specific craft data for the mixer and other functions
i: the index number. think of this as a block's id
pos: position vector of the block relative to the reference point.
    this represents the moment arm for force calculations.
facing: a unit vector that denotes the direction the block is facing.
type: the type of block.
    "B" = propeller bearing
    "W" = wooden propeller
    "A" = andesite propeller
sails: the number of sails if the block is a propeller bearing.
constant: block related config constants.
name: the name of the peripheral that block(s) of index i are wrapped to.
profile = { [i] = {pos = vector.new(x, y, z), facing = vector.new(x, y, z), type = "A", sails = #, constant = #, name = "controller1"} }
]]
local completion = require "cc.completion"
local CFG_FILE = "profile.json"

local client = require("networking/client")

local function vecToTable(v)
    return {x = v.x, y = v.y, z = v.z}
end
function tableToVec(t)
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
            name     = entry.name,
        }
    end
    file.write(textutils.serialiseJSON(out))
    file.close()
end

-- Read prof from a file
function loadConfig()
    if not fs.exists(CFG_FILE) then return nil, "File does not exist: " .. CFG_FILE end
    local file = fs.open(CFG_FILE, "r")
    if not file then return nil, "Could not open file for reading: " .. CFG_FILE end
    local raw = textutils.unserialiseJSON(file.readAll())
    file.close()
    if not raw then return nil, "Failed to parse file: " .. CFG_FILE end
    local out = {}
    for i, entry in ipairs(raw) do
        out[i] = {
            pos      = tableToVec(entry.pos),
            facing   = tableToVec(entry.facing),
            type     = entry.type,
            sails    = entry.sails,
            constant = entry.constant,
            name     = entry.name,
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

-- Returns stepsDone, raw plotyard position vector, and the rest of the entry (minus pos).
local function setupController(index, stepsDone, stepsTotal)
    local step = index + 1

    local name = confirmedRead(
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
            string.format("Step %d.5 - Stand on the block and enter its PLOTYARD coordinates.", step))
        io.write("X: "); x = tonumber(read())
        io.write("Y: "); y = tonumber(read())
        io.write("Z: "); z = tonumber(read())
        prompt(progressText(stepsDone, stepsTotal),
            string.format("Step %d.5 - Confirm plotyard position: %d %d %d\nConfirm? (Y/N)", step, x, y, z))
        io.write("> ")
        local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
        if confirm == "Y" then break end
    end
    stepsDone = stepsDone + 1

    -- y-1 converts "standing on block" coords to the block itself
    local plotyardPos = vector.new(x, y - 1, z)

    return stepsDone, plotyardPos, {
        facing   = DIRECTION_VECTORS[facing],
        type     = blockType,
        sails    = sails,
        constant = constant,
        name     = name,
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

    local stepsTotal = (count * 5) + 1
    local stepsDone  = 1

    -- Collect all controller data with raw plotyard positions
    local plotyardPositions = {}
    local partialEntries    = {}
    for i = 1, count do
        local newStepsDone, plotyardPos, entry = setupController(i, stepsDone, stepsTotal)
        stepsDone            = newStepsDone
        plotyardPositions[i] = plotyardPos
        partialEntries[i]    = entry
    end

    -- Fetch the three reference positions from globals
    local comPlotyard = tableToVec(sublevel.getCenterOfMass())
    local comWorld    = tableToVec(sublevel.getLogicalPose().position)
    local refWorld    = tableToVec(client.getRefPoint().position)

    -- Build final profile:
    --   prop_world = com_world + (prop_plotyard - com_plotyard)
    --   pos        = prop_world - ref_world
    --              = (com_world - ref_world) + (prop_plotyard - com_plotyard)
    local comOffset = comWorld - refWorld
    local profile   = {}
    for i = 1, count do
        profile[i]     = partialEntries[i]
        profile[i].pos = comOffset + (plotyardPositions[i] - comPlotyard)
    end

    saveConfig(profile)
end

--setupWizard()

return {
    tableToVec  = tableToVec,
    saveConfig  = saveConfig,
    loadConfig  = loadConfig,
    setupWizard = setupWizard,
}