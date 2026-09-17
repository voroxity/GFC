-- stabilization.lua (consolidated single-file version)
--
-- This replaces the previous multi-file layout (rate_controller.lua,
-- attitude_controller.lua, torque_ff.lua, torque_env.lua, stabilization.lua)
-- with everything folded into one file, in dependency order below. Public
-- interface is UNCHANGED: require("stabilization") returns a table with
-- .new(config) -> instance, instance:step(qCurrent, omega, I, dt),
-- instance:setDesiredOrientation(q). Existing test scripts need no changes.
--
-- torque_gravity.lua is intentionally NOT included: live testing on both a
-- symmetric and a deliberately asymmetric craft confirmed
-- getLogicalPose().rotationPoint always exactly equals getCenterOfMass() --
-- the physics engine always rotates about COM, so gravity's moment arm is
-- architecturally zero. torque_gravity.lua is kept as its own separate file
-- for a possible future translation/altitude module, not bundled here.
--
-- Known library bugs worked around throughout this file (see comments at
-- point of use for detail): pid's quaternionStep uses the wrong (world, not
-- body) frame convention; getAngle/getAxis don't take the shortest
-- rotational path; a metatable-shadowing bug makes pid's clampOutput/
-- limitIntegral unreachable (hence manual integral clamping below);
-- quaternion:mul(vector) silently discards a vector's magnitude for
-- non-unit inputs (hence "rotate unit vector, scale after" throughout).

local pid = require("advanced_math/pid")

-- ============================================================
-- RateController: inner rate loop.
-- P+I via the bundled pid module (kd=0 inside it -- its D-term is
-- unfiltered derivative-on-error and kicks on every setpoint change,
-- confirmed via testing). D-term here is hand-rolled as filtered
-- derivative-on-MEASUREMENT instead, which does not kick. Integral
-- clamping is also manual, since pid's own clampOutput/limitIntegral are
-- unreachable due to a variable-shadowing bug in pid.new().
-- ============================================================

local RateController = {}
RateController.__index = RateController

function RateController.new(target, kp, ki, kd, alpha, integralClamp)
    local self = setmetatable({}, RateController)
    self.innerPid = pid.new(target, kp, ki, 0.0, true) -- kd=0: module never differentiates error
    self.kd = kd
    self.alpha = alpha
    self.integralClamp = integralClamp
    self.filteredDeriv = vector.new(0, 0, 0)
    self.prevMeasured = nil -- nil until first step, avoids a bogus derivative spike on step 1
    return self
end

function RateController:setTarget(newTarget)
    self.innerPid.sp = newTarget
end

local function clampAxis(value, limit)
    if value > limit then return limit
    elseif value < -limit then return -limit
    else return value end
end

function RateController:step(measured, dt)
    local pidOut = self.innerPid:step(measured, dt)

    if self.integralClamp then
        self.innerPid.integral = vector.new(
            clampAxis(self.innerPid.integral.x, self.integralClamp),
            clampAxis(self.innerPid.integral.y, self.integralClamp),
            clampAxis(self.innerPid.integral.z, self.integralClamp)
        )
    end

    local dTerm = vector.new(0, 0, 0)
    if self.prevMeasured ~= nil then
        local rawDeriv = vector.new(
            (measured.x - self.prevMeasured.x) / dt,
            (measured.y - self.prevMeasured.y) / dt,
            (measured.z - self.prevMeasured.z) / dt
        )
        self.filteredDeriv = vector.new(
            self.alpha * rawDeriv.x + (1 - self.alpha) * self.filteredDeriv.x,
            self.alpha * rawDeriv.y + (1 - self.alpha) * self.filteredDeriv.y,
            self.alpha * rawDeriv.z + (1 - self.alpha) * self.filteredDeriv.z
        )
        -- standard form: u = Kp*e + Ki*int(e) - Kd*d(measured)/dt
        dTerm = vector.new(
            -self.kd * self.filteredDeriv.x,
            -self.kd * self.filteredDeriv.y,
            -self.kd * self.filteredDeriv.z
        )
    end
    self.prevMeasured = measured

    return vector.new(
        pidOut.x + dTerm.x,
        pidOut.y + dTerm.y,
        pidOut.z + dTerm.z
    )
end

-- ============================================================
-- AttitudeController: outer attitude loop + inner rate loop.
-- The outer loop does NOT use pid.new()'s quaternion mode -- its
-- quaternionStep computes error as sp*value:inverse(), which is the error
-- expressed in WORLD frame, not body frame, and getAngle/getAxis don't
-- take the shortest path for errors over 180 degrees. Both are wrong for
-- our needs, so the body-frame, shortest-path error is computed directly.
-- ============================================================

local AttitudeController = {}
AttitudeController.__index = AttitudeController

function AttitudeController.new(qDesired, kpAtt, kpRate, kiRate, kdRate, alpha, integralClamp)
    local self = setmetatable({}, AttitudeController)
    self.qDesired = qDesired
    self.kpAtt = kpAtt
    self.rateController = RateController.new(vector.new(0, 0, 0), kpRate, kiRate, kdRate, alpha, integralClamp)
    return self
end

function AttitudeController:setDesiredOrientation(qNewDesired)
    self.qDesired = qNewDesired
end

-- Body-frame, shortest-path orientation error vector.
-- e_body such that qCurrent (x) e_body = qDesired  =>  e_body = qCurrent:inverse() * qDesired
local function bodyFrameErrorVector(qCurrent, qDesired)
    local errorQuat = qCurrent:inverse():mul(qDesired)
    if errorQuat.a < 0 then
        errorQuat = -errorQuat -- shortest-path sign fix, via quaternion's __unm
    end
    return errorQuat.v * 2
end

function AttitudeController:step(qCurrent, omegaMeasured, dt)
    local e = bodyFrameErrorVector(qCurrent, self.qDesired)
    local omegaDes = e * self.kpAtt
    self.rateController:setTarget(omegaDes)
    local torque = self.rateController:step(omegaMeasured, dt)
    return torque, omegaDes
end

-- ============================================================
-- torque_ff: inertia coupling / gyroscopic feedforward.
--   torque_ff = omega x (I * omega)
-- Manual 3x3 matrix-vector multiply since matrix:mul only handles
-- matrix*matrix or matrix*scalar (confirmed from matrix.lua source).
-- ============================================================

local function computeTorqueFF(omega, I)
    local Iomega = vector.new(
        I[1][1] * omega.x + I[1][2] * omega.y + I[1][3] * omega.z,
        I[2][1] * omega.x + I[2][2] * omega.y + I[2][3] * omega.z,
        I[3][1] * omega.x + I[3][2] * omega.y + I[3][3] * omega.z
    )
    return omega:cross(Iomega)
end

-- ============================================================
-- torque_env: envelope lift torque.
--   torque_env = r_env x (F_lift * up_body)
-- up_world = (0,0,1) is rotated as a UNIT vector, then scaled by F_lift
-- AFTERWARD -- quaternion:mul(vector) silently discards a non-unit
-- vector's magnitude, confirmed via isolated testing, so magnitude must
-- always be reapplied after rotation, never combined into the vector
-- before it.
-- ============================================================

local function computeTorqueEnv(qCurrent, rEnv, fLift)
    local upWorld = vector.new(0, 0, 1) -- unit vector, safe to rotate as-is
    local upBody = qCurrent:inverse():mul(upWorld)
    local forceBody = upBody * fLift -- scale AFTER rotation
    return rEnv:cross(forceBody)
end

-- ============================================================
-- Stabilization: combines everything into the final torque_cmd.
--   torque_cmd = torque_pid + torque_ff + torque_env
-- ============================================================

local Stabilization = {}
Stabilization.__index = Stabilization

-- config fields:
--   qDesired, kpAtt, kpRate, kiRate, kdRate, alpha, integralClamp  (gains)
--   hasEnvelope (bool), rEnv, fLift                                (envelope term)
function Stabilization.new(config)
    local self = setmetatable({}, Stabilization)
    self.attitudeController = AttitudeController.new(
        config.qDesired, config.kpAtt, config.kpRate, config.kiRate, config.kdRate,
        config.alpha, config.integralClamp
    )
    self.config = config
    return self
end

function Stabilization:setDesiredOrientation(q)
    self.attitudeController:setDesiredOrientation(q)
end

-- qCurrent, omega: live from cc:sable (sensor_adapter.lua)
-- I: live inertia tensor (matrix) from cc:sable
-- dt: measured tick interval
-- returns: torque_cmd (vector), and a breakdown table for debugging/logging
function Stabilization:step(qCurrent, omega, I, dt)
    local c = self.config

    local torquePid = self.attitudeController:step(qCurrent, omega, dt)
    local torqueFF = computeTorqueFF(omega, I)
    local torqueEnv = vector.new(0, 0, 0)
    if c.hasEnvelope then
        torqueEnv = computeTorqueEnv(qCurrent, c.rEnv, c.fLift)
    end

    local torqueCmd = torquePid + torqueFF + torqueEnv
    return torqueCmd, {
        pid = torquePid,
        ff = torqueFF,
        env = torqueEnv
    }
end

return Stabilization