local K_R = 8.0   -- proportional gain for attitude
local K_w = 3.0   -- derivative gain for attitude (damping)
local K_v = 4.0   -- proportional gain for linear velocity


local function matVecMul(I, v)
    return vector.new(
        I[1][1] * v.x + I[1][2] * v.y + I[1][3] * v.z,
        I[2][1] * v.x + I[2][2] * v.y + I[2][3] * v.z,
        I[3][1] * v.x + I[3][2] * v.y + I[3][3] * v.z
    )
end

local function rotateWorldToBody(q, v)
    return q:conjugate():mul(v)
end

local function computeAttitudeError(q_current, q_desired)
    local q_d_inv = q_desired:conjugate()         
    local q_err   = q_d_inv:mul(q_current)         
    q_err = q_err:normalize()                      

    local sgn = (q_err.a >= 0) and 1.0 or -1.0   
    return vector.new(
        sgn * q_err.v.x,
        sgn * q_err.v.y,
        sgn * q_err.v.z
    )
end
-- q_desired: desired orientation (quaternion)(from pilot)
-- v_desired: desired velocity (vector)(from pilot)
-- I: inertia matrix (matrix)(from CC:sable)
-- q: current orientation (quaternion)(from CC:sable)
-- omega: currant angular velocity
-- mass: mass of sublevel
-- gravity: dimention gravity (vector)
-- v_world: current velocity (vector)
local function geometricControl(q_desired, v_desired, I, q, omega, mass, gravity, v_world)

    local e_R = computeAttitudeError(q, q_desired)

    local e_omega = omega

    local I_omega = matVecMul(I, omega)
    local gyro    = omega:cross(I_omega)

    local torque = vector.new(
        -K_R * e_R.x - K_w * e_omega.x + gyro.x,
        -K_R * e_R.y - K_w * e_omega.y + gyro.y,
        -K_R * e_R.z - K_w * e_omega.z + gyro.z
    )

    local e_v = v_world - v_desired

    local F_world = vector.new(
        -K_v * e_v.x - mass * gravity.x,
        -K_v * e_v.y - mass * gravity.y,
        -K_v * e_v.z - mass * gravity.z
    )

    local F_body = rotateWorldToBody(q, F_world)

    return F_body, torque
end

return geometricControl