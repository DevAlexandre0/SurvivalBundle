HealthShared = {}

-- simple weapon classifier stub; expand as needed
function HealthShared.classifyWeapon(weaponHash)
  if not weaponHash then return 'melee' end
  if weaponHash == `WEAPON_UNARMED` then return 'melee' end
  local bullets = { `WEAPON_PISTOL`, `WEAPON_SMG`, `WEAPON_CARBINERIFLE` }
  local blades  = { `WEAPON_KNIFE`, `WEAPON_MACHETE` }
  local shotguns= { `WEAPON_PUMPSHOTGUN`, `WEAPON_SAWNOFFSHOTGUN` }
  local blasts  = { `WEAPON_GRENADE`, `WEAPON_STICKYBOMB` }

  for _,h in ipairs(bullets) do if weaponHash == h then return 'bullet' end end
  for _,h in ipairs(blades)  do if weaponHash == h then return 'blade'  end end
  for _,h in ipairs(shotguns)do if weaponHash == h then return 'shotgun'end end
  for _,h in ipairs(blasts)  do if weaponHash == h then return 'blast'   end end
  return 'melee'
end

-- bone group mapping; fill with more as needed
local ARM = { `IK_R_Hand`, `IK_L_Hand`, `PH_R_UpperArm`, `PH_L_UpperArm` }
local LEG = { `IK_R_Foot`, `IK_L_Foot`, `PH_R_Calf`, `PH_L_Calf` }
function HealthShared.classifyBone(boneId)
  if not boneId then return 'torso' end
  for _,b in ipairs(ARM) do if b == boneId then return 'arm' end end
  for _,b in ipairs(LEG) do if b == boneId then return 'leg' end end
  if boneId == `SKEL_Head` then return 'head' end
  return 'torso'
end
