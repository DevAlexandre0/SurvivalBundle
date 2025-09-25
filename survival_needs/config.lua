Config = {}

-- Debug
Config.Debug = true
Config.DebugPrefix = '[survival_needs]'

-- Tick
Config.ServerTickMs = 1000 -- 1s
Config.BroadcastOnDelta = true
Config.DeltaEpsilon = 0.5 -- ไม่ซิงค์ถ้าน้อยกว่านี้

-- Coefficients (ต่อวินาที)
Config.Decay = {
  food   = 0.005,   -- base hunger
  water  = 0.007,   -- base thirst
  energy = 0.000,   -- base energy loss when idle handled below
  stress = -0.003,  -- base relax (negative = decrease stress)
}

-- Multipliers ตามกิจกรรม
Config.Activity = {
  idle =    { food=1.0,  water=1.0,  energy=-0.8, stress=-1.0 },
  walk =    { food=1.2,  water=1.2,  energy= 0.2, stress=-0.5 },
  run =     { food=2.0,  water=2.2,  energy= 0.8, stress= 0.1 },
  sprint =  { food=3.0,  water=3.5,  energy= 1.5, stress= 0.2 },
  swim =    { food=2.5,  water=3.0,  energy= 1.2, stress= 0.2 },
  dive =    { food=3.0,  water=3.5,  energy= 1.5, stress= 0.6 }, -- underwater
}

-- Bowel/Urine
Config.Bowel = {
  poop = { base = 0.0008, mealBoost = 0.002 },
  pee  = { base = 0.0012, drinkBoost = 0.003 },
}

-- Clamps
Config.ClampMin, Config.ClampMax = 0.0, 100.0

-- Rate-limit (events per minute)
Config.RateLimit = {
  clientUpdate = 60,
}

-- Persistence
Config.Persistence = {
  Enabled = true,   -- เปิดใช้เมื่อผูก DB
  SaveIntervalSec = 60,
  TableName = 'survival_needs',
}
