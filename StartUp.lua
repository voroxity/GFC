local functions = require("functions")
local completion = require "cc.completion"
local net = {}

--initialization stage
term.clear()
term.setCursorPos(1, 1)
print("Starting script...")
local config = loadConfig()-- loads the config file, if it exists
print("Loading config...")
if config == nil then-- if the config file does not exist, create one and have the user input the necessary information
    print("No config found\ncreating default config...\n")
    local BLOCK_TYPES = {"SLAVE", "MASTER"}
    config = {
        type = confirmedRead(
        "== SETUP (1/2) ==\n",
        "Is this the master computer or a slave computer? There can only be one master computer in the network but multiple slaves!!!\nEnter block type (SLAVE/MASTER):",
        function(t) return completion.choice(t, BLOCK_TYPES) end),
        id = confirmedRead(
        "== SETUP (2/2) ==\n",
        "what do you want to make the network id? the network id needs to be the same for all computers in the network!!!\nEnter network ID:",
        nil)
    }
    saveConfig(config)
    prompt("== SETUP COMPLETE ==\n", "Setup complete! The computer will now reboot to apply the new configuration.\nrebooting in 5 seconds...")
    os.sleep(5)
    os.reboot()
end
print("Config found")
print("TYPE:" .. config.type)
print("NETWORK ID:" .. config.id)
config = handshake(config)