-- client.lua (client computer)
-- Works with either a wired or wireless modem.

local SERVER_ID   = nil   -- set this to the server's computer ID if using wired (run `id` on the server to find it, e.g. SERVER_ID = 5)
local CHANNEL     = 1     -- must match server (wireless only)
local REPLY_CH    = 2     -- client reply channel (wireless only)
local TIMEOUT     = 5     -- seconds to wait for a response
local pretty = require "cc.pretty"
--Modem detection
local net = {}
local function setupModem()
    print("warapping wired modem")
    local wired = peripheral.find("modem", function(_, m) return not m.isWireless() end)
    if wired then
        if not SERVER_ID then
            error("Wired mode requires SERVER_ID to be set at the top of client.lua")
        end
        print("Using wired modem (rednet) -> server ID " .. SERVER_ID)
        peripheral.find("modem", rednet.open)
        net.mode = "wired"
        function net.send(message)
            rednet.send(SERVER_ID, message)
        end
        function net.receive()
            local senderID, message = rednet.receive(TIMEOUT)
            if senderID == nil then return nil end   -- timed out
            return message
        end
        return
    end
    print("Could not find wired modem. Attempting to find wireless modem")
    local wireless = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if wireless then
        print("Using wireless modem (channel " .. CHANNEL .. ", reply on " .. REPLY_CH .. ")")
        wireless.open(REPLY_CH)
        net.mode  = "wireless"
        net.modem = wireless
        function net.send(message)
            wireless.transmit(CHANNEL, REPLY_CH, message)
        end
        function net.receive()
            local timer = os.startTimer(TIMEOUT)
            while true do
                local event, p1, p2, p3, p4 = os.pullEvent()
                if event == "modem_message" then
                    local senderCh, _, msg = p2, p3, p4
                    if senderCh == CHANNEL then
                        os.cancelTimer(timer)
                        return msg
                    end
                elseif event == "timer" and p1 == timer then
                    return nil   -- timed out
                end
            end
        end
        return
    end
    error("No modem found! Attach a wired or wireless modem.")
end

--- Fetches the sublevel information from the server computer.
-- @return value, or nil + error string on failure
local function getRefPoint()
    net.send("GET_REF")
    local response = net.receive()
    if response == nil then
        return nil, "Timed out waiting for server response"
    elseif response.success then
        return response.value
    else
        return nil, response.error
    end
end

--[[Example usage
setupModem()
local RefPoint, err = getRefPoint()
if RefPoint then
    print("RefPoint aquired")
    pretty.pretty_print(RefPoint.position)
    pretty.pretty_print(RefPoint.orientation)
else
    print("Error: " .. err)
end]]