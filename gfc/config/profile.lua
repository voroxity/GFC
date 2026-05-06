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

local function saveConfig(cfg)
    local f = fs.open(CFG_FILE, "w")
    if f then f.write(textutils.serialize(cfg)); f.close() end
end

local function loadConfig()
    if not fs.exists(CFG_FILE) then return nil end
    local f = fs.open(CFG_FILE, "r")
    if not f then return nil end
    local d = f.readAll(); f.close()
    return textutils.unserialize(d)
end

function SetupWizard()
    local index
    local conf = {"Y","N"}
    while true do
        term.clear(); term.setCursorPos(1, 1)
        print("Progress:0%\n== SETUP ==\n\nStep: 1\nHow many propeller speed controllers does the craft have?\n")
        io.write("Number: ")
        index = read()
        print(string.format("\nConfirm %d is the correct.\ntype Y for yes and N for no.\n", index))
        io.write("Confirm? ")
        local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
        if confirm == "Y" then break end
    end
    local percent = 1
    local function prog(i)
        percent = percent + i
        local pogress = math.floor((percent / ((index * 5) + 1))*100)
        return print("Progress:" .. pogress .. "%")
    end
    local profile = {}
    for i = 1, index do
        local POS
        local FAC
        local TYPE
        local SAIL
        local CON
        local MAP
        while true do-- map
            term.clear(); term.setCursorPos(1, 1)
            prog(0)
            print(string.format("== SETUP ==\n\nStep: %d.1\nSpeed controller name?\n", i+1))    
            io.write("Peripheral: ")
            MAP = read(nil, nil, completion.peripheral)
            print(string.format("\nConfirm "..MAP.." is the correct.\ntype Y for yes and N for no.\n"))
            io.write("Confirm? ")
            local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
            if confirm == "Y" then break end
        end
        prog(1)
        local types = {"A","B","W"}
        while true do-- type
            term.clear(); term.setCursorPos(1, 1)
            prog(0)
            print(string.format("== SETUP ==\n\nStep: %d.2\nWhat type of block?\n\nA = Andesite  B = Bearing  W = Wooden\n", i+1))
            io.write("Type: ")
            TYPE = read(nil, nil, function(text) return completion.choice(text, types) end)
            if TYPE == "B" then
                print(string.format("\nStep: %d.2.5\nHow many sail blocks?\n", i+1))
                io.write("Number: ")
                SAIL = read()
                print(string.format("\nConfirm "..TYPE.." and "..SAIL.." are correct.\ntype Y for yes and N for no.\n"))
            else
                SAIL = 0
                print(string.format("\nConfirm "..TYPE.." is the correct.\ntype Y for yes and N for no.\n"))
            end
            io.write("Confirm? ")
            local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
            if confirm == "Y" then break end
        end
        prog(1)
        local defaults = {"1" ,"0.2"}
        while true do-- constant
            term.clear(); term.setCursorPos(1, 1)
            prog(0)
            print(string.format("== SETUP ==\n\nStep: %d.3\nThrust constant?\ninput the trust constant for last step\n(defaults: A & W = 1, B = 0.2)\n", i+1))
            io.write("Type: ")
            CON = read(nil, nil, function(text) return completion.choice(text, defaults) end)
            print(string.format("\nConfirm "..CON.." is the correct.\ntype Y for yes and N for no.\n"))
            io.write("Confirm? ")
            local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
            if confirm == "Y" then break end
        end
        prog(1)
        local directions = {"Forward","Backward","Left","Right","Up","Down"}
        local dTOv = {Forward = vector.new(0,0,-1),Backward = vector.new(0,0,1),Left = vector.new(-1,0,0),Right = vector.new(1,0,0),Up = vector.new(0,1,0),Down = vector.new(0,-1,0)}
        while true do-- facing
            term.clear(); term.setCursorPos(1, 1)
            prog(0)
            print(string.format("== SETUP ==\n\nStep: %d.4\nWhat direction is the block facing\n", i+1))
            io.write("direction: ")
            FAC = read(nil, nil, function(text) return completion.choice(text, directions) end)
            print(string.format("\nConfirm "..FAC.." is the correct.\ntype Y for yes and N for no.\n"))
            io.write("Confirm? ")
            local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
            if confirm == "Y" then break end
        end
        prog(1)
        FAC = dTOv[FAC]
        local X
        local Y
        local Z
        while true do-- pos
            term.clear(); term.setCursorPos(1, 1)
            prog(0)
            print(string.format("== SETUP ==\n\nStep: %d.5\nstand on the block and record the position.\n", i+1))
            io.write("X: "); X = read()
            io.write("Y: "); Y = read()
            io.write("Z: "); Z = read()
            print(string.format("\nConfirm %d %d %d is the correct.\ntype Y for yes and N for no.\n",X,Y,Z))
            io.write("Confirm? ")
            local confirm = read(nil, nil, function(text) return completion.choice(text, conf) end)
            if confirm == "Y" then break end
        end
        prog(1)
        POS = vector.new(X,(Y-1),Z)
        --asseble profile
        profile[i] = {pos = POS, facing = FAC, type = TYPE, sails = SAIL, constant = CON, map = peripheral.wrap(MAP)}
    end
    saveConfig(profile)
end