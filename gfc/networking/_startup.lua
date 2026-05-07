--startup.lua (refrence computer)
--this file runs on the refrence computer to give the main GFC data that it needs.
--Works with either a wired or wireless modem.

local CHANNEL = 1 -- wireless channel

--Modem detection
local net = {}
local function setupModem()-- Prefer wired if available
    local wired = peripheral.find("modem", function(_, m) return not m.isWireless() end)
    if wired then
        print("Using wired modem (rednet)")
        peripheral.find("modem", rednet.open)   -- open all attached modems
        net.mode = "wired"
        function net.send(targetID, message)
            rednet.send(targetID, message)
        end
        function net.receive()-- returns: senderID, message
            local senderID, message = rednet.receive()
            return senderID, message
        end
        return
    end

    -- Fall back to wireless
    local wireless = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if wireless then
        print("Using wireless modem (channel " .. CHANNEL .. ")")
        wireless.open(CHANNEL)
        net.mode = "wireless"
        net.modem = wireless
        function net.send(targetID, message)-- targetID is the reply channel when using wireless
            wireless.transmit(targetID, CHANNEL, message)
        end
        function net.receive()
            while true do
                local _, _, senderCh, replyCh, message = os.pullEvent("modem_message")
                if senderCh == CHANNEL then-- use replyCh as the "sender ID" so net.send knows where to reply
                    return replyCh, message
                end
            end
        end
        return
    end
    error("No modem found! Attach a wired or wireless modem.")
end

--Main
setupModem()
print("Server ready and listening...")
while true do
    local senderID, message = net.receive()
    if message == "GET_REF" then
        print("Request received from " .. tostring(senderID))
        local ok, result = pcall(function()
            return sublevel.getLogicalPose()
        end)
        local response
        if ok then
            response = { success = true, value = result }
            print("Sending RefPoint: " .. tostring(result))
        else
            response = { success = false, error = tostring(result) }
            print("Error: " .. tostring(result))
        end
        net.send(senderID, response)
    end
end