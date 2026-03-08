// SPDX-License-Identifier: MIT

use planets::models::building::BuildingType;

#[starknet::interface]
pub trait IGameSystems<T> {
    /// Found the colony at hex (col, row). Places Town Center and spawns starting colonists.
    fn found_colony(ref self: T, planet_id: u64, col: u32, row: u32);

    /// Construct a building. Costs iron. Triggers a resource tick first.
    fn construct_building(
        ref self: T, planet_id: u64, lon: u16, lat: u16, building_type: BuildingType,
    );

    /// Assign workers to a building. Triggers a tick first so dead colonists can't be assigned.
    /// workers = desired total workers at this building (not a delta).
    fn assign_workers(ref self: T, planet_id: u64, lon: u16, lat: u16, workers: u8);

    /// Explicitly trigger a resource tick (collect production, process time-based events).
    fn collect(ref self: T, planet_id: u64);

    /// Craft weapons and/or armor. Costs iron. Gear is permanent and reusable.
    /// Upgrade the Town Center to the next level. Increases population cap by 10.
    /// Cost: TC_UPGRADE_BASE_COST * current_level iron.
    fn upgrade_tc(ref self: T, planet_id: u64);

    fn craft_gear(ref self: T, planet_id: u64, weapons: u32, armor: u32);

    /// Send colonists to fight the active invader.
    /// Colonists are drawn from the unassigned pool.
    /// weapons/armor: how many pieces of gear to equip (must be <= stockpile).
    fn fight_invader(ref self: T, planet_id: u64, colonists: u8, weapons: u32, armor: u32);
}

#[dojo::contract]
mod game_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::colony::Colony;
    use planets::models::resources::Resources;
    use planets::models::colonists::{
        Colonist, PlanetColonistCount,
        ColonistsAssigned, ColonistAssignedEntry, ColonistAssignedIdx,
        ColonistsUnassigned, ColonistUnassignedEntry, ColonistUnassignedIdx,
    };
    use planets::models::building::{
        Building, BuildingType, PlanetBuildingCount, PlanetBuildingEntry,
    };
    use planets::models::invader::Invader;
    use planets::models::gear::Gear;
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_embeddable_game_standard::minigame::minigame::{
        assert_token_ownership, post_action, pre_action,
    };
    use game_components_interfaces::{IMinigameDispatcher, IMinigameDispatcherTrait};
    use starknet::{ContractAddress, get_block_timestamp};
    use core::poseidon::poseidon_hash_span;

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    const STARTING_COLONISTS: u32 = 5;
    const POP_PER_TC_LEVEL: u32 = 10;

    const STARTING_WATER: u32 = 100;
    const STARTING_IRON: u32 = 50;
    const STARTING_DEFENSE: u32 = 10;

    const EPOCH_SECONDS: u64 = 600;  // 10 min
    const MAX_EPOCHS: u64 = 144;     // 24 h cap

    const MAX_BUILDINGS: u32 = 8;

    // Iron costs for buildings
    const WATER_WELL_COST: u32 = 50;
    const IRON_MINE_COST: u32 = 80;
    const HOUSE_IRON_COST: u32 = 60;
    const HOUSE_WATER_COST: u32 = 50; // House also costs water (you need water to house people)
    const BARRACKS_COST: u32 = 100;

    // TC upgrade: costs TC_UPGRADE_BASE_COST * current_level iron per upgrade
    const TC_UPGRADE_BASE_COST: u32 = 100;

    // Base output per assigned worker per epoch (terrain-scaled at construct time)
    const WATER_WELL_BASE: u32 = 10;
    const IRON_MINE_BASE: u32 = 8;
    const BARRACKS_BASE: u32 = 8;
    const MAX_WORKERS: u8 = 3;

    // Hex grid → lon/lat
    const LON_PER_HEX: u32 = 72;  // 3600 / 50
    const LAT_PER_HEX: u32 = 45;  // 1800 / 40

    // Gear crafting costs
    const WEAPON_COST: u32 = 20;  // iron per weapon
    const ARMOR_COST: u32 = 30;   // iron per armor set

    // Combat: base power per colonist, bonus per weapon, bonus per armor
    const COLONIST_BASE_POWER: u32 = 10;
    const WEAPON_POWER: u32 = 5;
    const ARMOR_POWER: u32 = 3;

    // Threat: how often to roll for invasion (seconds) — one check per epoch
    const THREAT_CHECK_INTERVAL: u64 = 600;

    // Invader passive damage per epoch = strength / PASSIVE_DAMAGE_DIV
    const PASSIVE_DAMAGE_DIV: u32 = 10;

    // -----------------------------------------------------------------------
    // Interface implementation
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl GameSystemsImpl of super::IGameSystems<ContractState> {
        fn found_colony(ref self: ContractState, planet_id: u64, col: u32, row: u32) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let mut planet: Planet = world.read_model(planet_id);
            assert!(planet.population > 0, "Planets: planet not spawned");
            assert!(col < planet.width, "Planets: col out of bounds");
            assert!(row < planet.height, "Planets: row out of bounds");

            let colony: Colony = world.read_model(planet_id);
            assert!(!colony.founded, "Planets: colony already founded");

            // Place Town Center at the center of the chosen hex
            let tc_lon: u16 = (col * LON_PER_HEX + LON_PER_HEX / 2).try_into().unwrap();
            let tc_lat: u16 = (row * LAT_PER_HEX + LAT_PER_HEX / 2).try_into().unwrap();

            world
                .write_model(
                    @Building {
                        planet_id,
                        lon: tc_lon,
                        lat: tc_lat,
                        building_type: 0,
                        exists: true,
                        terrain_bonus: 0,
                        workers: 0,
                        max_workers: 0,
                        output_per_worker_epoch: 0,
                    },
                );
            let mut bcount: PlanetBuildingCount = world.read_model(planet_id);
            world
                .write_model(
                    @PlanetBuildingEntry {
                        planet_id, index: bcount.count, lon: tc_lon, lat: tc_lat,
                    },
                );
            bcount.count += 1;
            world.write_model(@bcount);

            let now = get_block_timestamp();

            world.write_model(@Colony { planet_id, col, row, founded: true, tc_level: 1 });
            world
                .write_model(
                    @Resources {
                        planet_id,
                        water: STARTING_WATER,
                        iron: STARTING_IRON,
                        defense: STARTING_DEFENSE,
                        last_updated_at: now,
                        last_threat_at: now,
                    },
                );

            // Initialise colonist tracking
            world.write_model(@ColonistsAssigned { planet_id, count: 0 });
            world.write_model(@ColonistsUnassigned { planet_id, count: 0 });
            world.write_model(@PlanetColonistCount { planet_id, count: 0 });

            // Initialise gear and invader
            world.write_model(@Gear { planet_id, weapons: 0, armor: 0 });
            world.write_model(@Invader { planet_id, active: false, strength: 0, lon: 0, lat: 0, spawned_at: 0 });

            // Spawn starting colonists into the unassigned pool
            let mut i: u32 = 0;
            loop {
                if i >= STARTING_COLONISTS {
                    break;
                }
                _spawn_colonist(ref world, planet_id);
                i += 1;
            };

            planet.population = STARTING_COLONISTS;
            planet.last_action_at = now;
            world.write_model(@planet);

            post_action(token_address, token_id);
        }

        fn construct_building(
            ref self: ContractState,
            planet_id: u64,
            lon: u16,
            lat: u16,
            building_type: BuildingType,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            _tick(ref world, planet_id);

            let mut planet: Planet = world.read_model(planet_id);
            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: found a colony first");
            assert!(building_type != BuildingType::TownCenter, "Planets: TC is auto-placed");

            let bcount: PlanetBuildingCount = world.read_model(planet_id);
            assert!(bcount.count <= MAX_BUILDINGS, "Planets: building limit reached");

            assert!(lon < 3600, "Planets: lon out of range");
            assert!(lat < 1800, "Planets: lat out of range");

            let existing: Building = world.read_model((planet_id, lon, lat));
            assert!(!existing.exists, "Planets: location occupied");

            let iron_cost: u32 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => WATER_WELL_COST,
                BuildingType::IronMine => IRON_MINE_COST,
                BuildingType::House => HOUSE_IRON_COST,
                BuildingType::Barracks => BARRACKS_COST,
            };

            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= iron_cost, "Planets: insufficient iron");
            resources.iron -= iron_cost;

            // House also costs water and requires room in the colony
            if building_type == BuildingType::House {
                let colony: Colony = world.read_model(planet_id);
                let max_pop: u32 = colony.tc_level.into() * POP_PER_TC_LEVEL;
                assert!(planet.population < max_pop, "Planets: population at cap, upgrade TC first");
                assert!(resources.water >= HOUSE_WATER_COST, "Planets: insufficient water");
                resources.water -= HOUSE_WATER_COST;
            }

            let building_type_u8: u8 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => 1,
                BuildingType::IronMine => 2,
                BuildingType::House => 3,
                BuildingType::Barracks => 4,
            };

            let terrain_type = planets::libs::terrain::terrain_at(planet.seed, lon, lat);
            let terrain_bonus = planets::libs::terrain::terrain_bonus(
                building_type_u8, terrain_type,
            );

            let base: u32 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => WATER_WELL_BASE,
                BuildingType::IronMine => IRON_MINE_BASE,
                BuildingType::House => 0,
                BuildingType::Barracks => BARRACKS_BASE,
            };
            let output_per_worker_epoch: u32 = if base == 0 {
                0
            } else {
                base * (50_u32 + terrain_bonus.into()) / 100_u32
            };

            let max_workers: u8 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => MAX_WORKERS,
                BuildingType::IronMine => MAX_WORKERS,
                BuildingType::House => 0,
                BuildingType::Barracks => MAX_WORKERS,
            };

            world
                .write_model(
                    @Building {
                        planet_id,
                        lon,
                        lat,
                        building_type: building_type_u8,
                        exists: true,
                        terrain_bonus,
                        workers: 0,
                        max_workers,
                        output_per_worker_epoch,
                    },
                );

            let mut bcount: PlanetBuildingCount = world.read_model(planet_id);
            world.write_model(@PlanetBuildingEntry { planet_id, index: bcount.count, lon, lat });
            bcount.count += 1;
            world.write_model(@bcount);

            // House: spawn one colonist immediately into the unassigned pool
            if building_type == BuildingType::House {
                _spawn_colonist(ref world, planet_id);
                planet.population += 1;
                world.write_model(@planet);
            }

            world.write_model(@resources);
        }

        fn assign_workers(
            ref self: ContractState, planet_id: u64, lon: u16, lat: u16, workers: u8,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            _tick(ref world, planet_id);

            let mut building: Building = world.read_model((planet_id, lon, lat));
            assert!(building.exists, "Planets: building not found");
            assert!(building.max_workers > 0, "Planets: building has no worker slots");
            assert!(workers <= building.max_workers, "Planets: exceeds building capacity");

            let old: u8 = building.workers;

            if workers > old {
                let delta: u32 = (workers - old).into();
                let ua_check: ColonistsUnassigned = world.read_model(planet_id);
                assert!(ua_check.count >= delta, "Planets: not enough idle colonists");

                let mut i: u32 = 0;
                loop {
                    if i >= delta {
                        break;
                    }
                    let ua: ColonistsUnassigned = world.read_model(planet_id);
                    let last_idx = ua.count - 1;
                    let entry: ColonistUnassignedEntry = world.read_model((planet_id, last_idx));
                    let cid = entry.colonist_id;
                    _remove_from_unassigned(ref world, planet_id, cid);
                    _add_to_assigned(ref world, planet_id, cid);
                    world
                        .write_model(
                            @Colonist {
                                planet_id,
                                colonist_id: cid,
                                is_assigned: true,
                                building_lon: lon,
                                building_lat: lat,
                            },
                        );
                    i += 1;
                };
            } else if workers < old {
                let delta: u8 = old - workers;
                let mut found: u8 = 0;
                let mut i: u32 = 0;
                loop {
                    if found >= delta {
                        break;
                    }
                    let assigned: ColonistsAssigned = world.read_model(planet_id);
                    if i >= assigned.count {
                        break;
                    }
                    let entry: ColonistAssignedEntry = world.read_model((planet_id, i));
                    let colonist: Colonist = world.read_model((planet_id, entry.colonist_id));
                    if colonist.building_lon == lon && colonist.building_lat == lat {
                        let cid = entry.colonist_id;
                        _remove_from_assigned(ref world, planet_id, cid);
                        _add_to_unassigned(ref world, planet_id, cid);
                        world
                            .write_model(
                                @Colonist {
                                    planet_id,
                                    colonist_id: cid,
                                    is_assigned: false,
                                    building_lon: 0,
                                    building_lat: 0,
                                },
                            );
                        found += 1;
                    } else {
                        i += 1;
                    }
                };
            }

            building.workers = workers;
            world.write_model(@building);
        }

        fn collect(ref self: ContractState, planet_id: u64) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");

            _tick(ref world, planet_id);

            post_action(token_address, token_id);
        }

        fn upgrade_tc(ref self: ContractState, planet_id: u64) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");
            assert!(colony.tc_level < 5, "Planets: TC already at max level");

            _tick(ref world, planet_id);

            let upgrade_cost: u32 = TC_UPGRADE_BASE_COST * colony.tc_level.into();
            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= upgrade_cost, "Planets: insufficient iron");
            resources.iron -= upgrade_cost;
            world.write_model(@resources);

            world
                .write_model(
                    @Colony {
                        planet_id,
                        col: colony.col,
                        row: colony.row,
                        founded: colony.founded,
                        tc_level: colony.tc_level + 1,
                    },
                );

            post_action(token_address, token_id);
        }

        fn craft_gear(ref self: ContractState, planet_id: u64, weapons: u32, armor: u32) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");
            assert!(weapons + armor > 0, "Planets: nothing to craft");

            _tick(ref world, planet_id);

            let total_iron = weapons * WEAPON_COST + armor * ARMOR_COST;
            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= total_iron, "Planets: insufficient iron");
            resources.iron -= total_iron;
            world.write_model(@resources);

            let mut gear: Gear = world.read_model(planet_id);
            gear.weapons += weapons;
            gear.armor += armor;
            world.write_model(@gear);

            post_action(token_address, token_id);
        }

        fn fight_invader(
            ref self: ContractState, planet_id: u64, colonists: u8, weapons: u32, armor: u32,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let invader: Invader = world.read_model(planet_id);
            assert!(invader.active, "Planets: no active invader");

            _tick(ref world, planet_id);

            let ua: ColonistsUnassigned = world.read_model(planet_id);
            assert!(ua.count >= colonists.into(), "Planets: not enough idle colonists");

            let gear: Gear = world.read_model(planet_id);
            assert!(gear.weapons >= weapons, "Planets: not enough weapons");
            assert!(gear.armor >= armor, "Planets: not enough armor");

            let col_count: u32 = colonists.into();
            let base_power: u32 = col_count * COLONIST_BASE_POWER
                + weapons * WEAPON_POWER
                + armor * ARMOR_POWER;

            // ±25% random variance on fighter effectiveness
            let now = get_block_timestamp();
            let mut planet: Planet = world.read_model(planet_id);
            let combat_rng: felt252 = poseidon_hash_span(
                array![planet.seed, planet.action_count.into(), now.into(), 42].span(),
            );
            let variance: u32 = (Into::<felt252, u256>::into(combat_rng) % 51)
                .try_into()
                .unwrap_or(25); // 0-50
            // variance 0 = -25%, 25 = 0%, 50 = +25%
            let fighter_power: u32 = if variance >= 25 {
                base_power + base_power * (variance - 25) / 100
            } else {
                let reduction = base_power * (25 - variance) / 100;
                if base_power > reduction { base_power - reduction } else { 0 }
            };

            let invader: Invader = world.read_model(planet_id); // re-read after tick

            if fighter_power >= invader.strength {
                // Victory — some casualties, invader defeated
                let casualties: u32 = if invader.strength / 20 > col_count {
                    col_count
                } else {
                    invader.strength / 20
                };
                _kill_random(
                    ref world, planet_id, casualties, planet.seed, planet.action_count, get_block_timestamp(),
                );
                planet.population = if planet.population > casualties {
                    planet.population - casualties
                } else {
                    0
                };
                world.write_model(@Invader { planet_id, active: false, strength: 0, lon: 0, lat: 0, spawned_at: 0 });
            } else {
                // Defeat — heavier casualties, invader weakened
                let excess = invader.strength - fighter_power;
                let casualties: u32 = if excess / 5 + 1 > col_count {
                    col_count
                } else {
                    excess / 5 + 1
                };
                _kill_random(
                    ref world, planet_id, casualties, planet.seed, planet.action_count, get_block_timestamp(),
                );
                planet.population = if planet.population > casualties {
                    planet.population - casualties
                } else {
                    0
                };
                // Invader weakened by how hard we fought
                let new_strength = if invader.strength > fighter_power {
                    invader.strength - fighter_power
                } else {
                    0
                };
                world
                    .write_model(
                        @Invader {
                            planet_id,
                            active: new_strength > 0,
                            strength: new_strength,
                            lon: invader.lon,
                            lat: invader.lat,
                            spawned_at: invader.spawned_at,
                        },
                    );
            }

            world.write_model(@planet);
            post_action(token_address, token_id);
        }
    }

    // -----------------------------------------------------------------------
    // Tick: compute rates, apply production, handle deaths, check threats
    // -----------------------------------------------------------------------

    fn _tick(ref world: WorldStorage, planet_id: u64) {
        let mut resources: Resources = world.read_model(planet_id);
        let mut planet: Planet = world.read_model(planet_id);

        let now = get_block_timestamp();
        let elapsed = now - resources.last_updated_at;
        let epochs_raw = elapsed / EPOCH_SECONDS;

        if epochs_raw == 0 {
            return;
        }

        let epochs: u32 = if epochs_raw > MAX_EPOCHS {
            MAX_EPOCHS.try_into().unwrap()
        } else {
            epochs_raw.try_into().unwrap()
        };

        // Compute production rates by iterating buildings
        let bcount: PlanetBuildingCount = world.read_model(planet_id);
        let mut water_rate: u32 = 0;
        let mut iron_rate: u32 = 0;
        let mut defense_rate: u32 = 0;

        let mut i: u32 = 0;
        loop {
            if i >= bcount.count {
                break;
            }
            let entry: PlanetBuildingEntry = world.read_model((planet_id, i));
            let b: Building = world.read_model((planet_id, entry.lon, entry.lat));
            let w: u32 = b.workers.into();
            if b.building_type == 1 {
                water_rate += w * b.output_per_worker_epoch;
            } else if b.building_type == 2 {
                iron_rate += w * b.output_per_worker_epoch;
            } else if b.building_type == 4 {
                defense_rate += w * b.output_per_worker_epoch;
            }
            i += 1;
        };

        resources.iron += iron_rate * epochs;
        resources.defense += defense_rate * epochs;

        // Invader passive damage (applied before water/population math)
        let mut invader: Invader = world.read_model(planet_id);
        if invader.active {
            let dmg_per_epoch: u32 = if invader.strength / PASSIVE_DAMAGE_DIV < 1 {
                1
            } else {
                invader.strength / PASSIVE_DAMAGE_DIV
            };
            let total_dmg = dmg_per_epoch * epochs;
            if resources.defense >= total_dmg {
                resources.defense -= total_dmg;
            } else {
                let overflow = total_dmg - resources.defense;
                resources.defense = 0;
                // Kill 1 colonist per 10 overflow damage
                let casualties: u32 = if overflow / 10 < 1 { 1 } else { overflow / 10 };
                let actual_casualties = if casualties > planet.population {
                    planet.population
                } else {
                    casualties
                };
                if actual_casualties > 0 {
                    _kill_random(
                        ref world, planet_id, actual_casualties, planet.seed, planet.action_count + 2000, now,
                    );
                    planet.population = if planet.population > actual_casualties {
                        planet.population - actual_casualties
                    } else {
                        0
                    };
                }
            }
        }

        // Water: produce then consume (1 per colonist per epoch)
        let water_produced = water_rate * epochs;
        let water_consumed = planet.population * epochs;
        let available = resources.water + water_produced;

        if available >= water_consumed {
            resources.water = available - water_consumed;

            // Population growth if comfortable surplus and below cap
            let colony: Colony = world.read_model(planet_id);
            let max_pop: u32 = colony.tc_level.into() * POP_PER_TC_LEVEL;
            if resources.water > planet.population * 5 && planet.population < max_pop {
                let raw_growth = planet.population / 10;
                let growth: u32 = if raw_growth < 1 {
                    1
                } else if raw_growth > 3 {
                    3
                } else {
                    raw_growth
                };
                let to_spawn: u32 = if planet.population + growth > max_pop {
                    max_pop - planet.population
                } else {
                    growth
                };
                let mut j: u32 = 0;
                loop {
                    if j >= to_spawn {
                        break;
                    }
                    _spawn_colonist(ref world, planet_id);
                    j += 1;
                };
                planet.population += to_spawn;
            }
        } else {
            // Water shortage — colonists die
            resources.water = 0;
            let deaths_per_epoch: u32 = if planet.population / 10 < 1 {
                1
            } else {
                planet.population / 10
            };
            let total_deaths: u32 = if deaths_per_epoch * epochs / 2 > planet.population {
                planet.population
            } else {
                deaths_per_epoch * epochs / 2
            };

            _kill_random(ref world, planet_id, total_deaths, planet.seed, planet.action_count, now);
            planet.population = if planet.population > total_deaths {
                planet.population - total_deaths
            } else {
                0
            };
        }

        // Threat check: roll for invasion once per THREAT_CHECK_INTERVAL
        if now - resources.last_threat_at >= THREAT_CHECK_INTERVAL && !invader.active {
            resources.last_threat_at = now;

            let time_alive = now - planet.spawned_at;
            let time_comp: u32 = ((time_alive / EPOCH_SECONDS) / 10).try_into().unwrap_or(255);
            let wealth_comp = resources.iron / 100;
            let size_comp = planet.population / 5;
            let threat_raw = time_comp + wealth_comp + size_comp;
            let threat: u32 = if threat_raw > 100 { 100 } else { threat_raw };

            let rng: felt252 = poseidon_hash_span(
                array![planet.seed, planet.action_count.into(), now.into(), 999].span(),
            );
            let rng_pct: u32 = (Into::<felt252, u256>::into(rng) % 100).try_into().unwrap_or(50);

            // Probability = threat/3 per epoch: 3% at threat=10, 17% at threat=50, 33% at threat=100
            if rng_pct < threat / 3 {
                // Spawn invader near the colony
                let colony: Colony = world.read_model(planet_id);
                let base_lon: u32 = colony.col * LON_PER_HEX + LON_PER_HEX / 2;
                let base_lat: u32 = colony.row * LAT_PER_HEX + LAT_PER_HEX / 2;

                // Offset using a second rng pass
                let rng2: felt252 = poseidon_hash_span(
                    array![planet.seed, planet.action_count.into(), now.into(), 1337].span(),
                );
                let offset_u256: u256 = rng2.into();
                let lon_offset: u32 = ((offset_u256 % 360).try_into().unwrap_or(180));
                let lat_offset: u32 = (((offset_u256 / 360) % 180).try_into().unwrap_or(90));

                let inv_lon: u32 = (base_lon + lon_offset) % 3600;
                let inv_lat: u32 = (base_lat + lat_offset) % 1800;
                let inv_strength: u32 = threat * 3;

                world
                    .write_model(
                        @Invader {
                            planet_id,
                            active: true,
                            strength: inv_strength,
                            lon: inv_lon.try_into().unwrap_or(0),
                            lat: inv_lat.try_into().unwrap_or(0),
                            spawned_at: now,
                        },
                    );
                invader.active = true; // local flag so passive damage skips this tick
            }
        }

        // Advance time
        resources.last_updated_at += epochs_raw * EPOCH_SECONDS;
        planet.action_count += 1;
        planet.last_action_at = now;

        world.write_model(@resources);
        world.write_model(@planet);
    }

    // -----------------------------------------------------------------------
    // Kill colonists randomly (unassigned first, then assigned)
    // -----------------------------------------------------------------------

    fn _kill_random(
        ref world: WorldStorage,
        planet_id: u64,
        count: u32,
        seed: felt252,
        base_nonce: u32,
        now: u64,
    ) {
        let mut left = count;
        let mut nonce = base_nonce;

        loop {
            if left == 0 {
                break;
            }
            let ua: ColonistsUnassigned = world.read_model(planet_id);
            if ua.count == 0 {
                break;
            }
            let rng: felt252 = poseidon_hash_span(array![seed, nonce.into(), now.into()].span());
            let victim_idx: u32 = (Into::<felt252, u256>::into(rng) % ua.count.into())
                .try_into()
                .unwrap_or(0);
            let entry: ColonistUnassignedEntry = world.read_model((planet_id, victim_idx));
            _remove_from_unassigned(ref world, planet_id, entry.colonist_id);
            nonce += 1;
            left -= 1;
        };

        loop {
            if left == 0 {
                break;
            }
            let assigned: ColonistsAssigned = world.read_model(planet_id);
            if assigned.count == 0 {
                break;
            }
            let rng: felt252 = poseidon_hash_span(array![seed, nonce.into(), now.into()].span());
            let victim_idx: u32 = (Into::<felt252, u256>::into(rng) % assigned.count.into())
                .try_into()
                .unwrap_or(0);
            let entry: ColonistAssignedEntry = world.read_model((planet_id, victim_idx));
            let colonist: Colonist = world.read_model((planet_id, entry.colonist_id));
            let mut building: Building = world
                .read_model((planet_id, colonist.building_lon, colonist.building_lat));
            if building.workers > 0 {
                building.workers -= 1;
                world.write_model(@building);
            }
            _remove_from_assigned(ref world, planet_id, entry.colonist_id);
            nonce += 1;
            left -= 1;
        };
    }

    // -----------------------------------------------------------------------
    // Colonist list helpers (O(1) add/remove via swap-and-pop)
    // -----------------------------------------------------------------------

    fn _spawn_colonist(ref world: WorldStorage, planet_id: u64) {
        let mut pcc: PlanetColonistCount = world.read_model(planet_id);
        let cid = pcc.count;
        world
            .write_model(
                @Colonist {
                    planet_id, colonist_id: cid, is_assigned: false, building_lon: 0, building_lat: 0,
                },
            );
        _add_to_unassigned(ref world, planet_id, cid);
        pcc.count += 1;
        world.write_model(@pcc);
    }

    fn _add_to_unassigned(ref world: WorldStorage, planet_id: u64, colonist_id: u32) {
        let mut ua: ColonistsUnassigned = world.read_model(planet_id);
        let idx = ua.count;
        world.write_model(@ColonistUnassignedEntry { planet_id, index: idx, colonist_id });
        world.write_model(@ColonistUnassignedIdx { planet_id, colonist_id, index: idx });
        ua.count += 1;
        world.write_model(@ua);
    }

    fn _remove_from_unassigned(ref world: WorldStorage, planet_id: u64, colonist_id: u32) {
        let mut ua: ColonistsUnassigned = world.read_model(planet_id);
        if ua.count == 0 {
            return;
        }
        let idx_model: ColonistUnassignedIdx = world.read_model((planet_id, colonist_id));
        let idx = idx_model.index;
        let last_idx = ua.count - 1;
        if idx < last_idx {
            let last: ColonistUnassignedEntry = world.read_model((planet_id, last_idx));
            world
                .write_model(
                    @ColonistUnassignedEntry { planet_id, index: idx, colonist_id: last.colonist_id },
                );
            world
                .write_model(
                    @ColonistUnassignedIdx { planet_id, colonist_id: last.colonist_id, index: idx },
                );
        }
        ua.count = last_idx;
        world.write_model(@ua);
    }

    fn _add_to_assigned(ref world: WorldStorage, planet_id: u64, colonist_id: u32) {
        let mut assigned: ColonistsAssigned = world.read_model(planet_id);
        let idx = assigned.count;
        world.write_model(@ColonistAssignedEntry { planet_id, index: idx, colonist_id });
        world.write_model(@ColonistAssignedIdx { planet_id, colonist_id, index: idx });
        assigned.count += 1;
        world.write_model(@assigned);
    }

    fn _remove_from_assigned(ref world: WorldStorage, planet_id: u64, colonist_id: u32) {
        let mut assigned: ColonistsAssigned = world.read_model(planet_id);
        if assigned.count == 0 {
            return;
        }
        let idx_model: ColonistAssignedIdx = world.read_model((planet_id, colonist_id));
        let idx = idx_model.index;
        let last_idx = assigned.count - 1;
        if idx < last_idx {
            let last: ColonistAssignedEntry = world.read_model((planet_id, last_idx));
            world
                .write_model(
                    @ColonistAssignedEntry { planet_id, index: idx, colonist_id: last.colonist_id },
                );
            world
                .write_model(
                    @ColonistAssignedIdx { planet_id, colonist_id: last.colonist_id, index: idx },
                );
        }
        assigned.count = last_idx;
        world.write_model(@assigned);
    }

    fn _get_token_address(world: WorldStorage) -> ContractAddress {
        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher {
            contract_address: game_token_systems_address,
        };
        minigame_dispatcher.token_address()
    }
}
