require("functions")

--stage 1:initialization.
startup()
term.clear()
term.setCursorPos(1, 1)
print("Starting script...\nLoading config...")
local config = loadConfig()--loads the config file, if it exists
print("Config found")
print("TYPE:" .. config.type)
print("NETWORK ID:" .. config.id)
config = handshake()
config = Validate()