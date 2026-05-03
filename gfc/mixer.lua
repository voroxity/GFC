local matrix = require("rom/apis/matrix")

local function round(x)-- rounds to the nearest intager
    if x >= 0 then
        return math.floor(x + 0.5)
    else
        return math.ceil(x - 0.5)
    end 
end

local function pressure(v)-- returns the presure at a point (v) on the sublevel.
    local q = sublevel.getLogicalPose().orientation
    local o = sublevel.getLogicalPose().position
    local v_quat = quaternion.new(v, 0)
    local rotated = q * v_quat * q:conjugate()
    local v_rot = (rotated.v) * (v:length())
    return aero.getAirPressure(v_rot + o)-- returns the air pressure at (v + o).
end

local function bearing_RPM(f,s,c,p)-- gets the rpm for the porp baring that meets the required force.
    -- s: number of sail blocks on the prop.
    -- c: prop constant (found in the games configs. defalt is 0.2).
    -- p: air pressure at prop barings center (find a way to calculate it).
    return round(f / (s^1.5 * c * p))
end

local function prop_RPM(f,c,p)-- gets the rpm for prop that meets the required force.
    -- t: torque that the prop needs to meet.
    -- c: prop constant (found in the games configs. defalt is 1.0).
    -- p: air pressure at blocks center.
    return round(f / (c * p))
end

--[[
-- TODO: as of 29/4/2026 only propellers are suported. add supported for lift blocks
-- profile is a table the stores specific craft data for the mixer and other functions
-- i: the index number. think of this a a blocks id
-- pos: position vector of the block relitive to center of mass.
--      this represents the moment arm for force calculations.
-- facing: a unit vector that denotes the direction the block is facing.
-- type: the type of block.
--  "B" = propeller baring 
--  "W" = wodden propeller
--  "A" = andesite propller
-- sails: the number of sailes if the block is a propeller baring.
-- constant: block related config constants
profile = { [i] = {pos = vector.new(x, y, z), facing = vector.new(x, y, z), type = "A", sails = #, constant = #} }
]]
-- compute the forces needed to achieve input torque vector
local function computeRotationForces(profile, T)
    local data  = { {}, {}, {} }
    local key = {}
    local k = 0
    for i = 1, #profile do
        local p = profile[i]
        local ai = p.facing
        local pos = p.pos
        local ci = pos:cross(ai)
        if ci:length() > 1 then
            k = (k + 1)
            data[1][k] = ci.x
            data[2][k] = ci.y
            data[3][k] = ci.z
            key[i] = true
        else
            key[i] = false
        end
    end
    k = 0
    local C = from2DArray(data)
    local b = from2DArray({ {T.x}, {T.y}, {T.z} })
    local Ct = C:transpose()
    local CCt = C * Ct
    local y, warning = solve(CCt, b)
    if warning then
        print("[computeRotationForces] " .. warning)
    end
    local f_mat = Ct * y
    local Rforces = {}
    for i = 1, #profile do
        if key[i] then
            k = (k + 1)
            Rforces[i] = f_mat[k][1]
        else
            Rforces[i] = 0
        end
    end
    --verification
    local T_mat = C * f_mat-- (3 x 1)
    local T_achieved = vector.new(T_mat[1][1], T_mat[2][1], T_mat[3][1])

    local diff = T_achieved - T
    local err  = math.sqrt(diff.x^2 + diff.y^2 + diff.z^2)
    return Rforces, T_achieved, err
end

local function computeTranslationForces(profile,F)
    local x = 0-- x axis
    local y = 0-- y axis
    local z = 0-- z axis
    for i=1, #profile do
        local p = profile[i]
        local facing = p.facing
        if p.type == "A" or p.type == "B" or p.type == "W" then-- checks to see if entry is a prop block
            x = x + math.abs(facing.x)
            y = y + math.abs(facing.y)
            z = z + math.abs(facing.z)
        end
    end
    local F_out = vector.new(
        x ~= 0 and (F.x / x) or 0,
        y ~= 0 and (F.y / y) or 0,
        z ~= 0 and (F.z / z) or 0
    )
    local TForces = {}
    for i = 1, #profile do
        local p = profile[i]
        if p.type == "A" or p.type == "B" or p.type == "W" then-- checks to see if entry is a prop block
            local F_dot = F_out:dot(p.facing)
            TForces[i] = F_dot
        else
            TForces[i] = 0
        end
    end
    return TForces
end
-- profile: craft specific layout and block data.
-- T: a vector that represents the rotational torque about the XYZ axis, aka pitch yaw rol.
-- F: a vector that represents the transition forces along the XYZ axis.
local function mixer(profile, T, F)
    local Rforces, T_achieved, err = computeRotationForces(profile, T)
    local TForces = computeTranslationForces(profile,F)
    local RPM = {}
    for i = 1, #profile do
        local P = profile[i]
        local f = Rforces[i] + TForces[i]
        local s = P.sails
        local c = P.constant
        local p = pressure(P.pos)
        if P.type == "A" or P.type == "W" then-- checks to see if entry is a prop block
            RPM[i] = prop_RPM(f,c,p)
        elseif P.type == "B" then
            RPM[i] = bearing_RPM(f,s,c,p)
        else
            RPM[i] = 0
        end
    end
    return RPM, T_achieved, err
end

return mixer