HealthShared = {}

local function hash(value)
  if type(value) == 'number' then return value end
  if type(value) == 'string' and GetHashKey then
    return GetHashKey(value)
  end
  return value
end

local bullets = { 'WEAPON_PISTOL', 'WEAPON_SMG', 'WEAPON_CARBINERIFLE' }
local blades  = { 'WEAPON_KNIFE', 'WEAPON_MACHETE' }
local shotguns= { 'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN' }
local blasts  = { 'WEAPON_GRENADE', 'WEAPON_STICKYBOMB' }

for i, name in ipairs(bullets) do bullets[i] = hash(name) end
for i, name in ipairs(blades) do blades[i] = hash(name) end
for i, name in ipairs(shotguns) do shotguns[i] = hash(name) end
for i, name in ipairs(blasts) do blasts[i] = hash(name) end

function HealthShared.classifyWeapon(weaponHash)
  if not weaponHash then return 'melee' end
  weaponHash = hash(weaponHash)
  if weaponHash == hash('WEAPON_UNARMED') then return 'melee' end
  for _, h in ipairs(bullets) do if weaponHash == h then return 'bullet' end end
  for _, h in ipairs(blades) do if weaponHash == h then return 'blade' end end
  for _, h in ipairs(shotguns) do if weaponHash == h then return 'shotgun' end end
  for _, h in ipairs(blasts) do if weaponHash == h then return 'blast' end end
  return 'melee'
end

local armBones = { 'IK_R_Hand', 'IK_L_Hand', 'PH_R_UpperArm', 'PH_L_UpperArm' }
local legBones = { 'IK_R_Foot', 'IK_L_Foot', 'PH_R_Calf', 'PH_L_Calf' }
for i, name in ipairs(armBones) do armBones[i] = hash(name) end
for i, name in ipairs(legBones) do legBones[i] = hash(name) end
local headBone = hash('SKEL_Head')

function HealthShared.classifyBone(boneId)
  if not boneId then return 'torso' end
  boneId = hash(boneId)
  for _, b in ipairs(armBones) do if b == boneId then return 'arm' end end
  for _, b in ipairs(legBones) do if b == boneId then return 'leg' end end
  if boneId == headBone then return 'head' end
  return 'torso'
end
