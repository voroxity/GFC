local so3 = require("SO3")

local tw = require("tw")
tw.init("right")
local m = peripheral.wrap('top')
m.setTextScale(0.5)
m.setCursorPos(0, 0)
m.clear()
term.redirect(m)

while true do
    local data = tw.update()

    local input = {
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

    local result = so3(input.q_desired, input.v_desired, I, q, omega, mass, g, v_world)
    print(result)
    os.sleep(0.5)
end
