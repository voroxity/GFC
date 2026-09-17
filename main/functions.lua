require("sha256")
local completion = require("cc.completion")
local wrap = require("cc.strings").wrap

-- Name of the file config is saved to/loaded from.
local CFG_FILE = "GFC_config.toml"

-- Settings applied to a brand new config if none exists yet.
local DefaultSettings = {
    autoaddnew = true, -- whether to automatically add newly-seen slaves/actors to existing lists
}

-- Y/N choices used by confirmedRead()'s tab-completion.
local YES_NO = { "Y", "N" }

-- Valid computer roles, used by loadConfig()'s tab-completion during setup.
local BLOCK_TYPES = { "SLAVE", "MASTER" }

--- Prints a message in red via printError, then raises a (message-less)
--- native error to unwind the call stack.
-- @tparam string text The error message to display
function Error(text)
    printError("ERROR:" .. text)
    error()
end

--- Ensures a startup.lua exists that boots this program's core script.
--- If startup.lua is missing, creates it and reboots the computer so it
--- takes effect immediately.
function startup()
    local corePath = "/main/core.lua"
    if not fs.exists("/startup.lua") then
        local file = fs.open("/startup.lua", "w")
        file.writeLine('shell.run("' .. corePath .. '")')
        file.close()
        os.reboot() -- reboot so the new startup.lua actually runs
    end
end

--- Serialises and writes the config table to disk.
-- @tparam table config The config table to persist
function saveConfig(config)
    local file = fs.open(CFG_FILE, "w")
    if not file then
        Error("Could not open file for writing: " .. CFG_FILE)
    end
    file.write(textutils.serialise(config))
    file.close()
end

--- Loads the config file from disk, or runs first-time interactive setup
--- and creates one if it doesn't exist yet.
-- @treturn table config
-- @treturn nil|string On failure, returns nil plus an error message instead
function loadConfig()
    local raw

    if not fs.exists(CFG_FILE) then
        -- First run: no config yet, so walk the user through setup.
        print("No config found\ncreating default config...\n")

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

    -- Config already exists: read and deserialise it.
    local file = fs.open(CFG_FILE, "r")
    if not file then
        return nil, "Could not open file for reading: " .. CFG_FILE
    end

    raw = textutils.unserialise(file.readAll())
    file.close()

    if not raw then
        return nil, "Failed to parse file: " .. CFG_FILE
    end

    return raw
end


--- Clears the screen and shows a title + message, ready for a prompt.
-- @tparam string title Header text
-- @tparam string message Body text shown below the title
function prompt(title, message)
    term.clear()
    term.setCursorPos(1, 1)
    print(title)
    print(message)
    print("")
end

--- Reads a line of input from the user, then asks them to confirm it
--- (Y/N) before returning. Loops until the user confirms with "Y".
-- @tparam string title Shown above the message (see prompt())
-- @tparam string message The question/instructions to show the user
-- @tparam function|nil completionFn Optional tab-completion function passed straight to read()
-- @treturn string The confirmed input value
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
        -- otherwise loop back and ask again
    end
end

--- Builds a "set" (a table used purely for O(1) membership checks) out of
--- another table's keys or values.
-- @tparam table|nil tbl Source table; if nil, returns nil
-- @tparam string mode "value" to index by tbl's values, anything else to index by tbl's keys
-- @treturn table|nil A table where known[x] == true for each key/value x, or nil if tbl was nil
-- @usage lookup({10, 20, 30}, "value") --> {[10]=true, [20]=true, [30]=true}
-- @usage lookup({a=1, b=2}, "key")     --> {a=true, b=true}
function lookup(tbl, mode)
    if not tbl then return nil end
    local known = {}
    for key, value in pairs(tbl) do
        known[mode == "value" and value or key] = true
    end
    return known
end

--- Finds every peripheral of a given type currently attached to the computer.
-- @tparam string targetType Peripheral type to match (e.g. "modem")
-- @treturn table Array of peripheral names matching targetType
local function findPeripheralsByType(targetType)
    local matches = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, targetType) then
            matches[#matches + 1] = name
        end
    end
    return matches
end

--- Establishes a handshake between the MASTER and its SLAVE computers over
--- rednet, confirming they share the same network ID before doing anything
--- else. Behaviour depends on config.type:
---
--- MASTER:
---   Broadcasts a hash of the network ID, waits 5 seconds collecting replies,
---   then reconciles who responded against config.slaves:
---     - exact match           -> all good
---     - more responded        -> new slaves get added to config and saved
---     - fewer responded       -> errors out, naming the missing slave IDs
---
--- SLAVE:
---   Waits for the MASTER's broadcast, verifies the hash, records/validates
---   the MASTER's computer ID, then replies and waits for MASTER's
---   confirmation.
--
-- @treturn table The (possibly updated) config table
function handshake()
    local config = loadConfig()
    -- Hash the network ID so it isn't sent/compared in plain text.
    local hash = sha256(tostring(config.id))

    if not peripheral.find("modem") then
        Error("No modem found. Please attach a modem to this computer.")
    end
    peripheral.find("modem", rednet.open)

    if config.type == "MASTER" then
        config.slaves = config.slaves or {} -- ensure config.slaves always exists

        print("searching for slave computers...")
        sleep(2)
        rednet.broadcast(hash, hash)

        -- Collect replies for up to 5 seconds.
        local slaves = {}
        local slaveCount = 0
        local deadline = os.clock() + 5
        while os.clock() < deadline do
            local senderID, message = rednet.receive(hash, 5)
            if senderID then
                if message == hash then
                    if not slaves[senderID] then
                        slaves[senderID] = true
                        slaveCount = slaveCount + 1
                        rednet.send(senderID, hash, hash) -- confirm receipt back to the slave
                        sleep(0.25)
                    end
                else
                    print("Received invalid handshake message from computer ID: " .. senderID)
                end
            end
        end

        -- Build a lookup set of the slave IDs already known to config, for
        -- quick "have we seen this one before?" checks below.
        local knownSlaves = lookup(config.slaves, "value")

        if slaveCount == #config.slaves then
            if slaveCount == 0 then
                Error("No slaves configured and/or none responded.")
            else
                print("All slaves connected (" .. slaveCount .. "/" .. #config.slaves .. ").")
            end

        elseif slaveCount > #config.slaves then
            -- More slaves responded than we knew about: add the new ones.
            for id in pairs(slaves) do
                if not knownSlaves[id] then
                    table.insert(config.slaves, id)
                    knownSlaves[id] = true
                    print("New slave found and added to config: " .. id)
                end
            end
            saveConfig(config)

        else
            -- Fewer slaves responded than expected: report which are missing.
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
        local master, message = rednet.receive(hash)

        if message ~= hash then
            Error("Received invalid handshake message from master computer. Please check the network ID and try again.")
        end
        print("handshake started")

        if not config.master then
            -- First time meeting this master: remember its ID.
            config.master = master
            saveConfig(config)
            print("pairing slave to master with iD:" .. master)
        elseif config.master ~= master then
            -- A different computer is claiming to be master on this network ID.
            printError("ERROR:\nmaster computer has correct network id but incorrect computer id.")
            Error("\nnew Master with id:" .. master .. "\nold master id: " .. config.master)
        end

        -- Reply to the master and keep retrying until it confirms.
        local confirmation, confirmMessage
        repeat
            rednet.send(master, hash, hash)
            confirmation, confirmMessage = rednet.receive(hash, 0.05)
        until confirmation ~= nil

        if confirmation == master and confirmMessage == hash then
            print("Handshake complete")
            return config
        else
            peripheral.find("modem", rednet.close)
            Error("Failed to complete handshake with master computer.")
        end
    end
end

--- Cross-checks each SLAVE's set of "actor" peripherals (currently
--- Create_RotationSpeedController blocks) against what config.actors already
--- knows about, reporting or auto-fixing any differences. Behaviour depends
--- on config.type:
---
--- MASTER:
---   Asks each known slave to validate itself, then reports per-slave
---   success/failure. Any slave-side errors bubble up as an overall Error().
---
--- SLAVE:
---   Waits for the MASTER's "Validate" request, then compares the actors it
---   can currently see against config.actors:
---     - no known actors yet         -> record everything found
---     - counts match                -> all good
---     - more actors found than known -> optionally auto-add the new ones
---       (governed by config.settings.autoaddnew)
---     - fewer actors found than known -> reports which ones are missing
---       and errors out
--
-- @treturn table The (possibly updated) config table
function Validate()
    local config = loadConfig()
    local hash = sha256(tostring(config.id))
    local errIDs = {}

    if config.type == "MASTER" then
        for _, id in ipairs(config.slaves) do
            rednet.send(id, "Validate", hash)
            local sender, message = rednet.receive(hash)

            if sender == id and message == "clear" then
                print("S" .. id .. ": verified")
            elseif sender == id and type(message) == "table" then
                -- Slave replied with a list of problems instead of "clear".
                printError("S" .. id .. ": experienced an error")
                for _, value in pairs(message) do
                    printError(value)
                end
                table.insert(errIDs, id)
            else
                printError("S" .. id .. ": timed out")
            end
        end

        if #errIDs > 0 then
            Error("(" .. #errIDs .. "/" .. #config.slaves .. "): experienced and error")
        end

    elseif config.type == "SLAVE" then
        local sender, message = rednet.receive(hash)
        sleep(0.25)
        print("parsing peripheral(s)")

        if sender == config.master and message == "Validate" then
            local RSC = findPeripheralsByType("Create_RotationSpeedController")
            config.actors = config.actors or {}

            -- Lookup set of actor names we already know about.
            local KnownActors = lookup(config.actors, "key")

            -- Count existing known actors (config.actors is keyed by name,
            -- so #config.actors wouldn't work here).
            local count = 0
            for _ in pairs(config.actors) do count = count + 1 end

            if count == 0 then
                -- Nothing recorded yet: adopt everything currently found.
                print("no previous actors found")
                for i = 1, #RSC do
                    config.actors[RSC[i]] = { type = peripheral.getType(RSC[i]) }
                end
                rednet.send(sender, "clear", hash)
                print("actor(s) verified")

            elseif #RSC == count then
                -- Same number found as known: assume all accounted for.
                print("all actors are accounted for")
                rednet.send(sender, "clear", hash)

            elseif #RSC > count then
                -- Found more actors than we know about: add any new ones
                -- (only if autoaddnew is enabled in settings).
                for _, name in ipairs(RSC) do
                    if not KnownActors[name] then
                        if config.settings.autoaddnew then
                            print(name)
                            config.actors[name] = { type = peripheral.getType(name) }
                        end
                    end
                end
                rednet.send(sender, "clear", hash)

            else
                -- Found fewer actors than we know about: something's missing.
                local known = lookup(RSC, "value")
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