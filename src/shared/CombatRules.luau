-- Pure Lua: no Roblox globals. The server supplies its own monotonic clock.
local Rules = {}

function Rules.IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Rules.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Rules.NewState(config, now)
    local potions = {}
    for size, potion in pairs(config.Potions) do
        potions[size] = potion.Count
    end
    return {
        Stamina = config.Combat.MaxStamina,
        Sprinting = false,
        Dead = false,
        SpawnProtectedUntil = now + config.Game.SpawnProtectionSeconds,
        LastAttackAt = -math.huge,
        LastSpendAt = now,
        LastPotionAt = -math.huge,
        LastDamagedAt = now,
        LastWorkAt = -math.huge,
        NextSwingSide = 1,
        SwingSide = nil,
        Potions = potions,
    }
end

function Rules.ConsumeAttack(state, config, now)
    if state.Dead then
        return false, "Dead"
    end
    if now - state.LastAttackAt < config.Combat.AttackCooldown then
        return false, "Cooldown"
    end
    if state.Stamina < config.Combat.AttackCost then
        return false, "Stamina"
    end
    state.Stamina = math.max(0, state.Stamina - config.Combat.AttackCost)
    state.LastAttackAt = now
    state.LastSpendAt = now
    -- Only accepted attacks advance the two mirrored sword animations.
    state.SwingSide = state.NextSwingSide
    state.NextSwingSide = -state.SwingSide
    -- Taking an offensive action ends the attacker's own protection.
    state.SpawnProtectedUntil = 0
    return true
end

-- Gathering and combat share the swing lock, so a player cannot mine and
-- strike another player in the same instant. Only the server supplies cost.
function Rules.ConsumeEffort(state, config, now, cost)
    if not Rules.IsFinite(now) or not Rules.IsFinite(cost) or cost <= 0 then
        return false, "Malformed"
    end
    if state.Dead then return false, "Dead" end
    if now - state.LastAttackAt < config.Combat.AttackCooldown then
        return false, "Cooldown"
    end
    if state.Stamina < cost then return false, "Stamina" end
    state.Stamina = math.max(0, state.Stamina - cost)
    state.LastAttackAt, state.LastSpendAt, state.LastWorkAt = now, now, now
    state.SwingSide = state.NextSwingSide
    state.NextSwingSide = -state.SwingSide
    return true
end

function Rules.RecoverHealth(state, config, dt, now, health, maxHealth)
    if state.Dead or not Rules.IsFinite(dt) or dt <= 0 or not Rules.IsFinite(now)
        or not Rules.IsFinite(health) or not Rules.IsFinite(maxHealth)
        or health <= 0 or maxHealth <= 0 or health >= maxHealth then
        return health
    end
    local rate, delay = config.Player.HealthRegenPerSecond, config.Player.HealthRegenDelay
    if not Rules.IsFinite(rate) or rate <= 0 or not Rules.IsFinite(delay) or delay < 0 then
        return health
    end
    local lastCombat = math.max(state.LastDamagedAt or now, state.LastAttackAt or -math.huge, state.LastWorkAt or -math.huge)
    local eligible = math.min(dt, math.max(0, now - lastCombat - delay))
    return math.min(maxHealth, health + rate * eligible)
end

function Rules.TickStamina(state, config, dt, now, moving)
    if state.Dead or not Rules.IsFinite(dt) or dt <= 0 then
        return
    end
    if state.Sprinting and state.Stamina <= 0 then
        state.Sprinting = false
    end
    if state.Sprinting and moving then
        state.Stamina = math.max(0, state.Stamina - config.Combat.SprintDrainPerSecond * dt)
        state.LastSpendAt = now
        if state.Stamina <= 0 then
            state.Sprinting = false
        end
    else
        -- Count only the portion of this step after the regeneration delay.
        local regenerationBegins = state.LastSpendAt + config.Combat.StaminaRegenDelay
        local regenerationTime = math.min(dt, math.max(0, now - regenerationBegins))
        state.Stamina = math.min(config.Combat.MaxStamina, state.Stamina + config.Combat.StaminaRegenPerSecond * regenerationTime)
    end
end

function Rules.ConsumePotion(state, config, size, health, maxHealth, now)
    if state.Dead then
        return false, "Dead"
    end
    if type(size) ~= "string" or config.Potions[size] == nil then
        return false, "InvalidPotion"
    end
    if not Rules.IsFinite(health) or not Rules.IsFinite(maxHealth) or health <= 0 or maxHealth <= 0 then
        return false, "InvalidHealth"
    end
    if health >= maxHealth then
        return false, "FullHealth"
    end
    if now - state.LastPotionAt < config.PotionCooldown then
        return false, "Cooldown"
    end
    if (state.Potions[size] or 0) <= 0 then
        return false, "Empty"
    end
    local newHealth = math.min(maxHealth, health + config.Potions[size].Heal)
    state.Potions[size] = state.Potions[size] - 1
    state.LastPotionAt = now
    return true, newHealth
end

function Rules.InAttackArc(distance, dot, config)
    if not Rules.IsFinite(distance) or not Rules.IsFinite(dot) or distance < 0 then
        return false
    end
    return distance <= config.Combat.AttackRange and dot >= math.cos(math.rad(config.Combat.AttackArc * 0.5))
end

function Rules.CanDamage(attacker, target, now)
    return attacker ~= target
        and not attacker.Dead
        and not target.Dead
        and attacker.TeamId ~= target.TeamId
        and now >= target.SpawnProtectedUntil
end

return Rules
