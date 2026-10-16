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
    -- Taking an offensive action ends the attacker's own protection.
    state.SpawnProtectedUntil = 0
    return true
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
