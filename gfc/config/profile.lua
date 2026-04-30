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