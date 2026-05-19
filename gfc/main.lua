--imports
local so3 = require("SO3")
local mixer = require("mixer")
local tw = require("controls/tw")
local profile = require("config/profile")
local client = require("networking/client")
--[[
initialization setps
1: conect tw and make sure it works.
2: setup modem and make sure ref point server can get and send info.
3: load craft profile from config.
    3.1: run setup wizard if profile cant be found then load it.
]]
-- STARTUP
local m = peripheral.wrap('top')
m.setTextScale(0.5)
m.setCursorPos(0, 0)
m.clear()
term.redirect(m)
-- INITIALIZATION
print("initialize typewritter")
tw.init("right")-- initialize typewritter
print("setting up client modem")
client.setupModem()-- modem setup
local config = profile.loadConfig()-- trys to load config
if config == nil then--if it cant find a config
    print("Profile config not found starting wizard...")
    profile.setupWizard()
    config = profile.loadConfig()
end
mixer.StopThrust(config)
--main loop
while true do
    local data = tw.update()--pull data from typewritter

    local input = {--defaults for pilot inputs
        q_desired = quaternion.new(vector.new(0, 1, 0), 0),
        v_desired = vector.new(0, 0, 0)
    }

    if data ~= nil then
        input.q_desired = quaternion.new(vector.new(0, 1, 0), data.turn*15) -- very very temporary
        input.v_desired = vector.new(data.throttle, data.lift, data.strafe)
        -- print(string.format("Throttle: %d, strafe: %d, lift: %d, turn: %d", data.throttle, data.strafe, data.lift, data.turn));
    end

    local q = sublevel.getLastPose().orientation
    local I = sublevel.getInertiaTensor()
    local v_world = sublevel.getVelocity()
    local omega = sublevel.getAngularVelocity()
    local mass = sublevel.getMass()
    local g = aero.getDefault().gravity

    local force, torque = so3(input.q_desired, input.v_desired, I, q, omega, mass, g, v_world)
    --print(string.format("force vector: %, torque vector: %", force, torque))

    -- math to account for a changing COM without mutating the saved config
    local COMvector = (profile.tableToVec(client.getRefPoint().position) - sublevel.getLogicalPose().position)
    local revisedConfig = {}
    for i = 1, #config do
        revisedConfig[i] = {
            pos = config[i].pos + COMvector,
            facing = config[i].facing,
            type = config[i].type,
            sails = config[i].sails,
            constant = config[i].constant,
            name = config[i].name,
        }
    end

    local RPM, T_achieved, err = mixer.mixer(revisedConfig, torque, force)
    -- RPM: a table with the same length as profile. each entry should be an intager that is positive or negitive.
    -- T_achieved: rotation math output. should be the same as torque.
    -- err: a value that represents the error of the mixer rotation math.

    mixer.updateRPM(revisedConfig,RPM)
    os.sleep(0.1)
end
