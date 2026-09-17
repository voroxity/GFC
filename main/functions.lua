local completion = require("cc.completion")
local wrap = require("cc.strings").wrap
require("sha256")
local CFG_FILE = "GFC_config.toml"
local SW_SPEED = 80
local DefaultSettings = {
    autoaddnew = true,-- weather or not to auto add new slaves or actors to existing lists
}

--prints a nice clear red error mesage while still using native error handleing
function Error(text)
    printError("ERROR:" .. text)
    error()
end

--
function startup()
    local corePath = "/main/core.lua"
    if not fs.exists("/startup.lua") then
        local file = fs.open("/startup.lua", "w")
        file.writeLine('shell.run("' .. corePath .. '")')
        file.close()
        os.reboot()
    end
end

--saves the config file
function saveConfig(config)
    local file = fs.open(CFG_FILE, "w")--open file for writing
    if not file then--if the file could not be opened, throw an error
        Error("Could not open file for writing: " .. CFG_FILE)
    end
    file.write(textutils.serialise(config))--write the config to the file
    file.close()
end

--loads the config file, if it exists
function loadConfig()
    local raw
    if not fs.exists(CFG_FILE) then--check if the file exists, if not assume that this is the first time loading
        print("No config found\ncreating default config...\n")
        local BLOCK_TYPES = {"SLAVE", "MASTER"}
        raw = {
            type = confirmedRead(
            "== SETUP (1/2) ==\n",
            "Is this the master computer or a slave computer? There can only be one master computer in the network but multiple slaves!!!\nEnter block type (SLAVE/MASTER):",
            function(t) return completion.choice(t, BLOCK_TYPES) end),
            id = confirmedRead(
            "== SETUP (2/2) ==\n",
            "what do you want to make the network id? the network id needs to be the same for all computers in the network!!!\nEnter network ID:",
            nil),
            settings = DefaultSettings
        }
        saveConfig(raw)
        term.clear()
        term.setCursorPos(1, 1)
        print("Starting script...\nLoading config...")
        return raw
    end
    local file = fs.open(CFG_FILE, "r")--opens the file for reading. if none exists it generates one
    if not file then return nil, "Could not open file for reading: " .. CFG_FILE end--if the file could not be opened for reading, throw an error
    raw = textutils.unserialise(file.readAll())--reads the file and unserializes it
    file.close()
    if not raw then return nil, "Failed to parse file: " .. CFG_FILE end--throws an error if the file could not be parsed
    return raw
end

local YES_NO = { "Y", "N" }

--prompts the user with a title and message, clearing the screen first
function prompt(title, message)
    term.clear()
    term.setCursorPos(1, 1)
    print(title)
    print(message)
    print("")
end

--prompts the user for input, confirming the input before returning it
function confirmedRead(title, message, completionFn)
    while true do
        prompt(title, message)
        io.write("> ")
        local value = read(nil, nil, completionFn)
        prompt(title, "\nYou entered: " .. tostring(value) .. "\nConfirm? (Y/N)")
        io.write("> ")
        local confirm = read(nil, nil, function(t) return completion.choice(t, YES_NO) end)
        if confirm == "Y" then
            return value
        end
    end
end

--displays text to the screen at a specified speed, wrapping lines as necessary, more versitial then slowWrite
function SW(text)
    if SW_SPEED < 0 then
        Error("Rate must be positive")
    end

    local wrapped_lines = wrap(tostring(text), (term.getSize()))
    local wrapped_str = table.concat(wrapped_lines)
    local len = #wrapped_str

    if SW_SPEED <= 20 then
        --slow enough that per-character sleeping still works fine
        local to_sleep = 1 / SW_SPEED
        for n = 1, len do
            sleep(to_sleep)
            write(wrapped_str:sub(n, n))
        end
    else
        --faster than tick rate: batch several chars into each tick,
        --using a fractional accumulator so the average rate is exact
        local chars_per_tick = SW_SPEED / 20
        local owed = 0
        local n = 1
        while n <= len do
            sleep(0.05)
            owed = owed + chars_per_tick
            local to_write = math.floor(owed)
            if to_write > 0 then
                local chunk_end = math.min(n + to_write - 1, len)
                write(wrapped_str:sub(n, chunk_end))
                owed = owed - (chunk_end - n + 1)
                n = chunk_end + 1
            end
        end
    end
    print("")
    sleep(math.random(5,10)/100)
end

--creates a look table for validation
function lookup(tbl, mode)
    if not tbl then return nil end
    local known = {}
    for key, value in pairs(tbl) do
        known[mode == "value" and value or key] = true
    end
    return known
end

--establishes a handshake between the master and slave computers, ensuring that they are on the same network and can communicate with each other
function handshake()
    local config = loadConfig()
    local hash = sha256(tostring(config.id))--hash the network ID to ensure that it is unique and cannot be easily guessed
    if not peripheral.find("modem") then Error("No modem found. Please attach a modem to this computer.") end
    peripheral.find("modem", rednet.open)

    if config.type == "MASTER" then
        config.slaves = config.slaves or {} --ensure config.slaves always exists as a table
        --Master computer will broadcast a message to all slave computers, and wait for them to respond with their own unique ID.
        print("searching for slave computers...")
        sleep(2)
        rednet.broadcast(hash, hash)

        local slaves = {}
        local slaveCount = 0
        local MASTER = os.clock() + 5
        while os.clock() < MASTER do
            local senderID, message = rednet.receive(hash, 5)
            if senderID then
                if message == hash then
                    if not slaves[senderID] then
                        slaves[senderID] = true
                        slaveCount = slaveCount + 1
                        rednet.send(senderID, hash, hash) --send confirmation back to the slave
                        sleep(0.25)
                    end
                else
                    print("Received invalid handshake message from computer ID: " .. senderID)
                end
            end
        end

        --Build a lookup set from config.slaves for quick membership checks
        local knownSlaves = lookup(config.slaves,"value")

        if slaveCount == #config.slaves then
            if slaveCount == 0 then
                Error("No slaves configured and/or none responded.")
            else
                print("All slaves connected (" .. slaveCount .. "/" .. #config.slaves .. ").")
            end

        elseif slaveCount > #config.slaves then
            --New slave(s) responded that aren't in the config yet — add them and save
            for id in pairs(slaves) do
                if not knownSlaves[id] then
                    table.insert(config.slaves, id)
                    knownSlaves[id] = true
                    print("New slave found and added to config: " .. id)
                end
            end
            saveConfig(config)

        else
            --Fewer slaves responded than expected — report which ones are missing
            local missing = {}
            for _, expectedID in ipairs(config.slaves) do
                if not slaves[expectedID] then
                    table.insert(missing, tostring(expectedID))
                end
            end
            Error("Missing slave(s) with ID(s): " .. table.concat(missing, ", "))
        end

        print("Handshake complete. " .. slaveCount .. " slave(s) found.")
        return config

    elseif config.type == "SLAVE" then
        print("Waiting for master computer...")
        local master, message = rednet.receive(hash)--waits for master broadcast
        if message ~= hash then Error("Received invalid handshake message from master computer. Please check the network ID and try again.") end
        print("handshake started")
        if not config.master then
            config.master = master
            saveConfig(config)
            print("paring slave to master with iD:" .. master)
        elseif config.master ~= master then
            printError("ERROR:\nmaster computer has correct network id but incorect computer id.")
            Error("\nnew Master with id:" .. master .. "\nold master id: " .. config.master)
        end
        local confirmation, confirmMessage
        repeat--replay to master and wait till confirmation signal
            rednet.send(master, hash, hash)
            confirmation, confirmMessage = rednet.receive(hash, 0.05)
        until confirmation ~= nil
        if confirmation == master and confirmMessage == hash then--validates confirmation signal
            print("Handshake complete")
            return config
        else
            peripheral.find("modem", rednet.close)
            Error("Failed to complete handshake with master computer.")
        end
    end
end

local function findPeripheralsByType(targetType)
    local matches = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, targetType) then
            matches[#matches + 1] = name
        end
    end
    return matches
end

--
function Validate()
    local config = loadConfig()
    local hash = sha256(tostring(config.id))--hash the network ID to ensure that it is unique and cannot be easily guessed
    local errIDs = {}
    if config.type == "MASTER" then
        for _, id in ipairs(config.slaves) do
            rednet.send(id,"Validate",hash)
            local sender, message = rednet.receive(hash)
            if sender == id and message == "clear" then
                print("S" .. id .. ": verified")
            elseif sender == id and type(message) == "table" then
                printError("S" .. id .. ": experinced an error")
                for _, value in pairs(message) do
                    printError(value)
                end
                table.insert(errIDs,id)
            else
                printError("S" .. id .. ": timed out")
            end
        end
        if #errIDs > 0 then Error("(" .. #errIDs .. "/" .. #config.slaves .. "): experinced and error") end
    --"Create_RotationSpeedController"
    elseif config.type == "SLAVE" then
        local sender, message = rednet.receive(hash)
        sleep(0.25)
        print("parsing peripheral(s)")
        if sender == config.master and message == "Validate" then
            local RSC = findPeripheralsByType("Create_RotationSpeedController")
            config.actors = config.actors or {}
            local KnownActors = lookup(config.actors,"key")
            local count = 0
            for _ in pairs(config.actors) do count = count + 1 end
            if count == 0 then
                print("no previous actors found")
                for i = 1, #RSC, 1 do
                    config.actors[RSC[i]] = {type = peripheral.getType(RSC[i])}
                end
                rednet.send(sender,"clear",hash)
                print("actor(s) verified")
            elseif #RSC == count then
                print("all actors are accounted for")
                rednet.send(sender,"clear", hash)
            elseif #RSC > count then
                for _,name in ipairs(RSC) do
                    if not KnownActors[name] then
                        if config.settings.autoaddnew then
                            print(name)
                            config.actors[name] = {type = peripheral.getType(name)}
                        end
                    end
                end
                rednet.send(sender,"clear",hash)
            else
                local known = lookup(RSC,"value")
                local missing = {}
                for key, _ in pairs(config.actors) do
                    if not known[key] then
                        table.insert(missing, "missing actor: " .. key)
                    end
                end
                rednet.send(sender, missing, hash)
                Error("Missing actor(s) with name(s):\n" .. table.concat(missing, ", "))
            end
        end
    end
    saveConfig(config)
    return config
end