-- Portable tuning shared by the authoritative server and the HUD.
local Config = {}
Config.Game = {
    Name = "Fer & Fioles",
    Mode = "Kingdoms", -- "Lobby" retains the invitation-based duel mode.
    TeamSize = 2,
    FillWithBots = false,
    IntermissionSeconds = 8,
    PreparingTimeoutSeconds = 20,
    SpawnProtectionSeconds = 3,
    ResultSeconds = 6,
    LobbyRespawnSeconds = 3,
    AllowedModes = { Duel = true, Teams = true },
}
Config.Invites = { CooldownSeconds = 15, ExpiresSeconds = 25 }
Config.Rewards = { Win = 50, Loss = 10, Draw = 10 }
Config.Persistence = { StoreName = "FerEtFiolesProfiles_v1", AutosaveSeconds = 60, LeaseSeconds = 180 }
Config.Teams = {
    Dawn = { Name = "Bleus", Color = { 75, 151, 222 } },
    Ember = { Name = "Rouges", Color = { 218, 91, 65 } },
}
Config.TeamOrder = { "Dawn", "Ember" }
-- Reference footage/wiki access is unavailable. These are tunable project
-- defaults, not measured Medieval Warfare Reforged constants.
Config.Player = {
    MaxHealth = 100, WalkSpeed = 16, SprintSpeed = 24,
    HealthRegenPerSecond = 2, HealthRegenDelay = 8,
}
Config.KingdomOrder = { "Redcliff", "Korblox", "Greywolf", "Overseer" }
Config.Kingdoms = {
    Redcliff = { Name = "Redcliff", Color = { 184, 53, 47 } },
    Korblox = { Name = "Korblox", Color = { 54, 105, 151 } },
    Greywolf = { Name = "Greywolf", Color = { 107, 114, 126 } },
    Overseer = { Name = "Overseer", Color = { 54, 109, 65 } },
}
for id, kingdom in pairs(Config.Kingdoms) do
    Config.Teams[id] = kingdom
end
Config.World = {
    RespawnSeconds = 5, KingdomChangeCooldown = 60, KingdomChangeSafeSeconds = 8,
    HarvestRange = 12, HarvestCooldown = 1, HarvestStaminaCost = 10,
    BuildRange = 20, CaptureRadius = 18, CaptureSeconds = 15,
    OutpostWoodCost = 30, OutpostOreCost = 15,
    Tree = { Hits = 4, Yield = 8, RespawnSeconds = 45 },
    Mine = { Hits = 5, Yield = 5, RespawnSeconds = 60 },
}
Config.Combat = {
    MaxStamina = 100, AttackCost = 10, AttackDamage = 25, AttackRange = 8, AttackArc = 110,
    AttackWindup = 0.08, AttackCooldown = 0.45, SprintDrainPerSecond = 1,
    StaminaRegenPerSecond = 5, StaminaRegenDelay = 1.5, MaxActionRate = 30,
}
Config.Potions = {
    Small = { Name = "Petite", Key = "Z", Heal = 20, Count = 3, Color = { 102, 211, 135 } },
    Medium = { Name = "Moyenne", Key = "X", Heal = 45, Count = 2, Color = { 82, 174, 233 } },
    Large = { Name = "Grosse", Key = "C", Heal = 75, Count = 1, Color = { 187, 120, 235 } },
}
Config.PotionOrder = { "Small", "Medium", "Large" }
-- One shared cooldown: drinking any size locks all three potions for 60s.
Config.PotionCooldown = 60
return Config
