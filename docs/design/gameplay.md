# Casino Royale — Gameplay

> **Document purpose:** This file defines the intended gameplay experience for *Casino Royale*.  
> It describes **what the player should be able to do and how the game should feel**, not the technical implementation.

## 1. Gameplay Pillars

*Casino Royale* is built around four main ideas:

1. **The Golden Crown is a social, gambling, shopping, and preparation hub.**
2. **The slums are fast-paced PvPvE shooter spaces.**
3. **Leaving and returning should have almost no friction.**
4. **Money, weapons, loot, gambling, and exploration continually feed into one another.**

The game should feel easy to jump into. A player should be able to leave the casino, fight for thirty seconds, return, gamble, talk to someone, buy something, and immediately leave again.

A trip into the slums does not need to feel like starting a formal match.

## 2. Core Loop

The broad loop is:

**Hang out in the Golden Crown → prepare → enter the elevator → arrive somewhere in the slums → move, fight, explore, and loot → return to the casino → sell/use/spend/gamble → repeat**

Players should be free to engage with only parts of this loop.

Examples:

- A player may spend an entire session gambling.
- A player may repeatedly leave the casino looking for fights.
- A player may explore and collect loot.
- A player may socialize in the casino.
- A player may leave the elevator, decide the destination looks dangerous, and immediately return.

There should be no large commitment required to begin a slum excursion.

## 3. The Golden Crown

The casino is a **safe zone**.

### Casino Rules

- No PvP damage.
- No hostile PvE combat.
- Weapons may be restricted, disabled, or otherwise prevented from being used offensively.
- Players can gamble.
- Players can purchase equipment and services from NPC employees.
- Players can manage inventory and prepare for another trip outside.
- Players can socialize with other players.
- Death and combat pressure should never follow a player into the casino.

The casino acts as the calm half of the game's rhythm.

## 4. Slum Combat

Combat in the slums should feel like a **fast arena shooter**, closer to *Quake* than a slow tactical extraction shooter.

### Target Feel

Combat should emphasize:

- Speed.
- Momentum.
- Constant movement.
- Strong air control.
- Strafing.
- Jumping during fights.
- Aggressive repositioning.
- Fast weapon switching.
- Short time between engagements.
- Vertical combat when a map supports it.
- Weapons that feel distinct rather than statistically interchangeable.

Standing still should usually be a bad idea.

The player should feel capable of rapidly moving through a map rather than carefully inching forward from cover to cover.

## 5. Movement

Movement is one of the most important parts of the game.

The desired movement model should support an arena-shooter style of play.

### Desired Characteristics

- Responsive acceleration.
- Air control.
- Momentum preservation.
- Strafing and rapid direction changes.
- Jumping as a normal part of combat.
- Movement techniques that reward practice.
- Maps designed with movement routes, shortcuts, jumps, ramps, and vertical opportunities.

The exact advanced movement mechanics can evolve over time.

Possible mechanics include bunny hopping, strafe jumping, ramp movement, explosive jumping, or similar techniques, but each should be deliberately adopted rather than added automatically.

Movement should be fun even when no enemies are nearby.

## 6. Weapons

Weapons should complement fast movement.

Good weapon design should prioritize:

- Immediate readability.
- Strong differences between weapons.
- Satisfying impact.
- Fast handling.
- Interesting tradeoffs.
- Weapons that create different movement and positioning decisions.

The game can support both conventional weapons and strange/generated weapons.

Weapon balance should favor fun and variety over strict realism.

## 7. PvPvE

The slums are intended to support **PvPvE**.

Players may encounter:

- Other players.
- Hostile NPCs or creatures.
- Environmental hazards.
- Opportunities to cooperate temporarily.
- Situations where another player is more dangerous than the environment.

Enemy factions, AI types, spawn rules, and encounter structure are still TBD.

PvP should remain completely outside the Golden Crown.

## 8. Slum Excursions

A slum excursion is intentionally lightweight.

It is not necessarily a formal round, raid, or match.

There should be no long queue, ready screen, or mandatory preparation sequence.

The player simply takes the elevator and leaves.

An excursion could last:

- 30 seconds.
- 5 minutes.
- 30 minutes.
- As long as the player wants.

Returning should be similarly easy once the player reaches an appropriate exit.

## 9. Elevator and Destinations

The casino elevator is the gateway to slum gameplay.

In the final game, the destination should be selected from available locations rather than always sending the player to the same map.

Possible destinations include:

- Parking garage.
- Alleys.
- Rooftops.
- Subway areas.
- Industrial interiors.
- Ferry.
- Other urban environments.
- Eventually surreal or absurd destinations.

The destination system allows new maps to be added without changing the basic player loop.

## 10. Slum Map Design

Slum maps should be designed primarily as **combat playgrounds**, not realistic city simulations.

Maps should support:

- Multiple routes.
- Flanking.
- Verticality.
- Fast traversal.
- Ambush opportunities.
- Sightline variation.
- Areas where different weapons excel.
- Environmental landmarks that make navigation easy during fast movement.

### Parking Garage

Gameplay goals:

- Multi-level fighting.
- Long ramps that allow players to build momentum.
- Cars and pillars breaking sightlines.
- Opportunities to jump between elevation changes.
- Tight fights between vehicles.
- Open lanes where faster weapons can shine.
- Loot distributed throughout vehicles and environmental points of interest.

### Alleys

Gameplay goals:

- Rapid close-range encounters.
- Sharp corners.
- Multiple intersections.
- Alternate routes.
- Dumpsters and structures that break sightlines.
- Rooftop/fire-escape opportunities where appropriate.
- Rain and darkness that create atmosphere without making enemies impossible to see.

Atmosphere should never make the shooter frustrating to read.

## 11. Loot

Loot gives players a reason to move through dangerous spaces.

Potential loot categories include:

- Weapons.
- Ammunition.
- Valuable objects.
- Casino currency.
- Consumables.
- Rare or unusual items.

Vehicle, container, world, and enemy loot systems can all eventually feed this loop.

Looting should be quick. The player should not spend long periods navigating inventory menus in the middle of a fast shooter encounter.

## 12. Returning to the Casino

Returning to the Golden Crown should convert dangerous exploration back into downtime and decision-making.

A returning player may:

- Keep equipment.
- Sell valuables.
- Buy new weapons.
- Gamble money.
- Restock.
- Meet other players.
- Immediately leave again.

The exact rules for what is lost on death and what persists between sessions are still TBD.

These rules should eventually be simple enough that a player can understand the risk of leaving the casino without reading a manual.

## 13. Death and Failure

Death should not create a large barrier to getting back into the game.

The game should avoid long spectating periods, lengthy matchmaking, or excessive punishment.

The exact death penalty is still TBD.

Potential consequences may involve some combination of:

- Dropping carried loot.
- Losing temporary items.
- Respawning in or near the casino.
- Allowing other players to recover dropped items.

The goal is to create stakes without turning every excursion into a high-pressure hour-long extraction raid.

## 14. Economy

Money connects the casino and the slums.

Players can earn, find, win, lose, and spend money.

Possible money sinks include:

- Gambling.
- Weapons.
- Ammunition.
- Equipment.
- Cosmetic items.
- Services.
- Strange or novelty purchases.

The economy should encourage players to cycle naturally between the casino and the slums.

Gambling should feel like something players choose to do with their money, not a mandatory progression gate.

## 15. Progression

Progression should primarily come from the player's expanding options rather than forcing a traditional RPG level grind.

Potential progression can include:

- Better or stranger weapons.
- Larger bankrolls.
- Rare items.
- Cosmetics.
- Access to unusual purchases.
- Discovering new locations.
- Personal mastery of movement and weapons.

A formal XP/level system is not currently required.

## 16. Multiplayer Philosophy

The game should support spontaneous player interactions.

Outside the casino, another player may be:

- An enemy.
- A temporary ally.
- Someone racing for the same loot.
- Someone passing through.
- Someone who starts a fight for no reason other than that it is fun.

Inside the casino, those same players return to a shared safe social space.

That contrast is an important part of the game's identity.

## 17. Pacing

The game should avoid unnecessary friction.

Prefer:

- Immediate movement.
- Immediate combat.
- Short interactions.
- Fast looting.
- Fast respawns.
- Easy transitions between casino and slums.

Avoid:

- Long deployment screens.
- Long extraction timers.
- Slow tactical movement as the default.
- Mandatory quest dialogue.
- Large amounts of inventory micromanagement.
- Long periods where dead players cannot play.

## 18. Design Rules

When adding new mechanics, prefer designs that reinforce the following:

1. **Movement should be fun.**
2. **Combat should be fast.**
3. **The casino should feel safe.**
4. **Leaving the casino should be effortless.**
5. **Returning should not require finishing a formal mission.**
6. **Maps should support repeated play rather than one-time scripted sequences.**
7. **Lore should add flavor without blocking gameplay.**
8. **Realism is secondary to fun.**
9. **The game is allowed to be strange or funny.**
10. **Players should be allowed to create their own stories rather than being assigned one.**

## 19. Confirmed Direction vs. TBD

### Confirmed Direction

- The game is called *Casino Royale*.
- The casino is called The Golden Crown.
- The Golden Crown is a combat-free safe zone.
- Slum gameplay is PvPvE.
- Slum combat should be fast and movement-heavy.
- Arena-shooter / Quake-style movement is the target feel.
- Excursions should have a very low barrier to entry.
- The elevator eventually selects from multiple destinations.
- Parking garage and alley environments are part of the intended slum set.
- The player does not require a fixed backstory.

### TBD

- Exact hostile NPC types.
- Exact death penalty.
- Exact loot persistence.
- Exact inventory persistence.
- Whether corpse looting exists.
- Whether players always keep equipped weapons.
- Exact economy balance.
- Exact advanced movement techniques.
- Formal progression systems.
- Additional slum destinations.
- Endgame or final objective.
