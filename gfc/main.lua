local so3 = require("SO3")
local mixer = require("mixer")

local tw = require("tw")
tw.init("right")
local m = peripheral.wrap('top')
m.setTextScale(0.5)
m.setCursorPos(0, 0)
m.clear()
term.redirect(m)

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
    print(string.format("force vector: %, torque vector: %", force, torque))

    local RPM, T_achieved, err = mixer(profile, torque, force)
    -- RPM: a table with the same length as profile. each entry should be an intager that is positive or negitive.
    -- T_achieved: rotation math output. should be the same as torque.
    -- err: a value that represents the error of the mixer rotation math.
    os.sleep(0.5)
end
