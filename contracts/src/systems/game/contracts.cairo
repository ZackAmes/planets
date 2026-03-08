// SPDX-License-Identifier: MIT

use planets::models::building::BuildingType;

#[starknet::interface]
pub trait IGameSystems<T> {
    fn found_colony(ref self: T, planet_id: felt252, col: u32, row: u32);
    fn construct_building(
        ref self: T, planet_id: felt252, lon: u16, lat: u16, building_type: BuildingType,
    );
    fn assign_workers(ref self: T, planet_id: felt252, lon: u16, lat: u16, workers: u8);
    fn collect(ref self: T, planet_id: felt252);
    /// Upgrade the Town Center. Raises pop cap, building limit, and max building level.
    fn upgrade_tc(ref self: T, planet_id: felt252);
    /// Upgrade a building to the next level. Increases output_per_worker_epoch.
    fn upgrade_building(ref self: T, planet_id: felt252, lon: u16, lat: u16);
    fn craft_gear(ref self: T, planet_id: felt252, weapons: u32, armor: u32);
    fn fight_invader(ref self: T, planet_id: felt252, colonists: u8, weapons: u32, armor: u32);
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
    const COLONIST_DEFAULT_STRENGTH: u8 = 2;
    const COLONIST_MAX_STRENGTH: u8 = 10;

    const STARTING_WATER: u32 = 100;
    const STARTING_IRON: u32 = 200;
    const STARTING_DEFENSE: u32 = 10;

    const EPOCH_SECONDS: u64 = 600;
    const MAX_EPOCHS: u64 = 144;

    // Building iron costs
    const WATER_WELL_COST: u32 = 50;
    const IRON_MINE_COST: u32 = 80;
    const HOUSE_IRON_COST: u32 = 60;
    const HOUSE_WATER_COST: u32 = 50;
    const BARRACKS_COST: u32 = 100;
    const URANIUM_MINE_COST: u32 = 150;
    const SPACEPORT_IRON_COST: u32 = 500;
    const SPACEPORT_URANIUM_COST: u32 = 100;
    const WORKSHOP_COST: u32 = 120;
    const CANNON_COST: u32 = 120;
    const CANNON_DEFENSE_BASE: u32 = 6;

    // Base output per worker per epoch (terrain-scaled at construct time)
    const WATER_WELL_BASE: u32 = 10;
    const IRON_MINE_BASE: u32 = 8;
    const URANIUM_MINE_BASE: u32 = 3;
    // Barracks has no resource output — it trains colonist strength instead
    const MAX_WORKERS: u8 = 3;

    // TC upgrade costs: iron = TC_UPGRADE_IRON_BASE * current_level
    // Levels 3→4 and 4→5 also require uranium
    const TC_UPGRADE_IRON_BASE: u32 = 100;
    const TC_UPGRADE_URANIUM_LV4: u32 = 10;  // upgrading lv3 → lv4
    const TC_UPGRADE_URANIUM_LV5: u32 = 25;  // upgrading lv4 → lv5

    // Building upgrade: iron = UPGRADE_IRON_BASE * current_level
    // Upgrading to level 4 or 5 also costs uranium
    const UPGRADE_IRON_BASE: u32 = 80;
    const UPGRADE_URANIUM_LV4: u32 = 5;   // upgrading lv3 → lv4
    const UPGRADE_URANIUM_LV5: u32 = 15;  // upgrading lv4 → lv5

    // Output level factors (as % of lv1 output): lv1=100, lv2=150, lv3=220, lv4=310, lv5=420
    // Applied as: output_lv1 * factor / 100
    const LV2_FACTOR: u32 = 150;
    const LV3_FACTOR: u32 = 220;
    const LV4_FACTOR: u32 = 310;
    const LV5_FACTOR: u32 = 420;

    // Hex grid → lon/lat (planet 50×40)
    const LON_PER_HEX: u32 = 72;
    const LAT_PER_HEX: u32 = 45;

    // Gear
    const WEAPON_COST: u32 = 20;
    const ARMOR_COST: u32 = 30;
    const WEAPON_POWER: u32 = 5;
    const ARMOR_POWER: u32 = 3;

    // Threat
    const THREAT_CHECK_INTERVAL: u64 = 600;
    const PASSIVE_DAMAGE_DIV: u32 = 10;

    // Building / upgrade / training timers (seconds)
    const BUILD_TIME: u64 = 60;          // 1 min — new construction
    const UPGRADE_TIME_LV2: u64 = 120;   // 2 min — upgrade to level 2
    const UPGRADE_TIME_LV3: u64 = 300;   // 5 min — upgrade to level 3
    const UPGRADE_TIME_LV4: u64 = 480;   // 8 min — upgrade to level 4
    const UPGRADE_TIME_LV5: u64 = 600;   // 10 min — upgrade to level 5
    const BARRACKS_TRAIN_BASE: u64 = 60; // 60s * building.level per training session

    // -----------------------------------------------------------------------
    // Interface implementation
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl GameSystemsImpl of super::IGameSystems<ContractState> {

        fn found_colony(ref self: ContractState, planet_id: felt252, col: u32, row: u32) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            pre_action(token_address, planet_id);

            let mut planet: Planet = world.read_model(planet_id);
            assert!(planet.seed != 0, "Planets: planet not spawned");
            assert!(col < planet.width, "Planets: col out of bounds");
            assert!(row < planet.height, "Planets: row out of bounds");

            let colony: Colony = world.read_model(planet_id);
            assert!(!colony.founded, "Planets: colony already founded");

            let tc_lon: u16 = (col * LON_PER_HEX + LON_PER_HEX / 2).try_into().unwrap();
            let tc_lat: u16 = (row * LAT_PER_HEX + LAT_PER_HEX / 2).try_into().unwrap();

            let tc_terrain = planets::libs::terrain::terrain_at(planet.seed, tc_lon, tc_lat);
            assert!(planets::libs::terrain::is_buildable(tc_terrain), "Planets: cannot settle on ocean");

            world
                .write_model(
                    @Building {
                        planet_id,
                        lon: tc_lon,
                        lat: tc_lat,
                        building_type: 0,
                        exists: true,
                        terrain_bonus: 0,
                        level: 1,
                        workers: 0,
                        max_workers: 0,
                        output_per_worker_epoch: 0,
                        completes_at: 0,
                    },
                );
            let mut bcount: PlanetBuildingCount = world.read_model(planet_id);
            world.write_model(@PlanetBuildingEntry { planet_id, index: bcount.count, lon: tc_lon, lat: tc_lat });
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
                        uranium: 0,
                        last_updated_at: now,
                        last_threat_at: now,
                    },
                );

            world.write_model(@ColonistsAssigned { planet_id, count: 0 });
            world.write_model(@ColonistsUnassigned { planet_id, count: 0 });
            world.write_model(@PlanetColonistCount { planet_id, count: 0 });
            world.write_model(@Gear { planet_id, weapons: 0, armor: 0 });
            world.write_model(@Invader { planet_id, active: false, strength: 0, lon: 0, lat: 0, spawned_at: 0 });

            let mut i: u32 = 0;
            loop {
                if i >= STARTING_COLONISTS { break; }
                _spawn_colonist(ref world, planet_id);
                i += 1;
            };

            planet.population = STARTING_COLONISTS;
            planet.last_action_at = now;
            world.write_model(@planet);

            post_action(token_address, planet_id);
        }

        fn construct_building(
            ref self: ContractState,
            planet_id: felt252,
            lon: u16,
            lat: u16,
            building_type: BuildingType,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            _tick(ref world, planet_id);

            let mut planet: Planet = world.read_model(planet_id);
            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: found a colony first");
            assert!(building_type != BuildingType::TownCenter, "Planets: TC is auto-placed");

            // Dynamic building limit based on TC level: (tc_level + 1) * 2 = 4, 6, 8, 10, 12
            let max_buildings: u32 = (colony.tc_level.into() + 1) * 2;
            let bcount: PlanetBuildingCount = world.read_model(planet_id);
            assert!(bcount.count < max_buildings, "Planets: building limit reached (upgrade TC)");

            // Gate high-tier buildings on TC level
            if building_type == BuildingType::Workshop {
                assert!(colony.tc_level >= 2, "Planets: requires TC level 2");
            }
            if building_type == BuildingType::UraniumMine {
                assert!(colony.tc_level >= 3, "Planets: requires TC level 3");
            }
            if building_type == BuildingType::Spaceport {
                assert!(colony.tc_level >= 5, "Planets: requires TC level 5");
            }

            assert!(lon < 3600, "Planets: lon out of range");
            assert!(lat < 1800, "Planets: lat out of range");

            let existing: Building = world.read_model((planet_id, lon, lat));
            assert!(!existing.exists, "Planets: location occupied");

            let building_type_u8: u8 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => 1,
                BuildingType::IronMine => 2,
                BuildingType::House => 3,
                BuildingType::Barracks => 4,
                BuildingType::UraniumMine => 5,
                BuildingType::Spaceport => 6,
                BuildingType::Workshop => 7,
                BuildingType::Cannon => 8,
            };

            let iron_cost: u32 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => WATER_WELL_COST,
                BuildingType::IronMine => IRON_MINE_COST,
                BuildingType::House => HOUSE_IRON_COST,
                BuildingType::Barracks => BARRACKS_COST,
                BuildingType::UraniumMine => URANIUM_MINE_COST,
                BuildingType::Spaceport => SPACEPORT_IRON_COST,
                BuildingType::Workshop => WORKSHOP_COST,
                BuildingType::Cannon => CANNON_COST,
            };

            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= iron_cost, "Planets: insufficient iron");
            resources.iron -= iron_cost;

            // House: costs water + needs population room
            if building_type == BuildingType::House {
                let max_pop: u32 = colony.tc_level.into() * POP_PER_TC_LEVEL;
                assert!(planet.population < max_pop, "Planets: population at cap, upgrade TC first");
                assert!(resources.water >= HOUSE_WATER_COST, "Planets: insufficient water");
                resources.water -= HOUSE_WATER_COST;
            }

            // Spaceport: costs uranium
            if building_type == BuildingType::Spaceport {
                assert!(resources.uranium >= SPACEPORT_URANIUM_COST, "Planets: insufficient uranium");
                resources.uranium -= SPACEPORT_URANIUM_COST;
            }

            let terrain_type = planets::libs::terrain::terrain_at(planet.seed, lon, lat);
            assert!(planets::libs::terrain::is_buildable(terrain_type), "Planets: cannot build on ocean");
            let terrain_bonus = planets::libs::terrain::terrain_bonus(building_type_u8, terrain_type);

            let base_output: u32 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => WATER_WELL_BASE,
                BuildingType::IronMine => IRON_MINE_BASE,
                BuildingType::House => 0,
                BuildingType::Barracks => 0,  // barracks trains colonists, no resource output
                BuildingType::UraniumMine => URANIUM_MINE_BASE,
                BuildingType::Spaceport => 0,
                BuildingType::Workshop => 0,
                BuildingType::Cannon => CANNON_DEFENSE_BASE,
            };

            let output_per_worker_epoch: u32 = if base_output == 0 {
                0
            } else {
                base_output * (50_u32 + terrain_bonus.into()) / 100_u32
            };

            let max_workers: u8 = match building_type {
                BuildingType::TownCenter => 0,
                BuildingType::WaterWell => MAX_WORKERS,
                BuildingType::IronMine => MAX_WORKERS,
                BuildingType::House => 0,
                BuildingType::Barracks => MAX_WORKERS,
                BuildingType::UraniumMine => MAX_WORKERS,
                BuildingType::Spaceport => 0,
                BuildingType::Workshop => 0,
                BuildingType::Cannon => MAX_WORKERS,
            };

            let now = get_block_timestamp();
            // House is instant (colonist spawns on build); TC is auto-placed (completes_at: 0).
            // All other buildings take BUILD_TIME (60s) to construct before they're usable.
            let build_completes_at: u64 = match building_type {
                BuildingType::House => 0,
                BuildingType::TownCenter => 0,
                _ => now + BUILD_TIME,
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
                        level: 1,
                        workers: 0,
                        max_workers,
                        output_per_worker_epoch,
                        completes_at: build_completes_at,
                    },
                );

            let mut bcount: PlanetBuildingCount = world.read_model(planet_id);
            world.write_model(@PlanetBuildingEntry { planet_id, index: bcount.count, lon, lat });
            bcount.count += 1;
            world.write_model(@bcount);

            // House: spawn one colonist immediately
            if building_type == BuildingType::House {
                _spawn_colonist(ref world, planet_id);
                planet.population += 1;
                world.write_model(@planet);
            }

            world.write_model(@resources);
        }

        fn assign_workers(
            ref self: ContractState, planet_id: felt252, lon: u16, lat: u16, workers: u8,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            _tick(ref world, planet_id);

            let now = get_block_timestamp();

            let mut building: Building = world.read_model((planet_id, lon, lat));
            assert!(building.exists, "Planets: building not found");
            assert!(building.max_workers > 0, "Planets: building has no worker slots");
            assert!(workers <= building.max_workers, "Planets: exceeds building capacity");
            assert!(
                building.completes_at == 0 || now >= building.completes_at,
                "Planets: building is busy",
            );

            let old: u8 = building.workers;

            if workers > old {
                let delta: u32 = (workers - old).into();
                let ua_check: ColonistsUnassigned = world.read_model(planet_id);
                assert!(ua_check.count >= delta, "Planets: not enough idle colonists");

                let mut i: u32 = 0;
                loop {
                    if i >= delta { break; }
                    let ua: ColonistsUnassigned = world.read_model(planet_id);
                    let last_idx = ua.count - 1;
                    let entry: ColonistUnassignedEntry = world.read_model((planet_id, last_idx));
                    let cid = entry.colonist_id;
                    _remove_from_unassigned(ref world, planet_id, cid);
                    _add_to_assigned(ref world, planet_id, cid);
                    let existing_c: Colonist = world.read_model((planet_id, cid));
                    world
                        .write_model(
                            @Colonist {
                                planet_id, colonist_id: cid, is_assigned: true,
                                building_lon: lon, building_lat: lat,
                                strength: existing_c.strength,
                            },
                        );
                    i += 1;
                };
            } else if workers < old {
                let delta: u8 = old - workers;
                let mut found: u8 = 0;
                let mut i: u32 = 0;
                loop {
                    if found >= delta { break; }
                    let assigned: ColonistsAssigned = world.read_model(planet_id);
                    if i >= assigned.count { break; }
                    let entry: ColonistAssignedEntry = world.read_model((planet_id, i));
                    let colonist: Colonist = world.read_model((planet_id, entry.colonist_id));
                    if colonist.building_lon == lon && colonist.building_lat == lat {
                        let cid = entry.colonist_id;
                        _remove_from_assigned(ref world, planet_id, cid);
                        _add_to_unassigned(ref world, planet_id, cid);
                        world
                            .write_model(
                                @Colonist {
                                    planet_id, colonist_id: cid, is_assigned: false,
                                    building_lon: 0, building_lat: 0,
                                    strength: colonist.strength,
                                },
                            );
                        found += 1;
                    } else {
                        i += 1;
                    }
                };
            }

            building.workers = workers;

            // Barracks: start (or clear) a training session when worker count changes.
            if building.building_type == 4 {
                if workers > 0 {
                    building.completes_at = now + BARRACKS_TRAIN_BASE * building.level.into();
                } else {
                    building.completes_at = 0;
                }
            }

            world.write_model(@building);
        }

        fn collect(ref self: ContractState, planet_id: felt252) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            pre_action(token_address, planet_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");

            _tick(ref world, planet_id);

            post_action(token_address, planet_id);
        }

        fn upgrade_tc(ref self: ContractState, planet_id: felt252) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            pre_action(token_address, planet_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");
            assert!(colony.tc_level < 5, "Planets: TC already at max level");

            _tick(ref world, planet_id);

            let iron_cost: u32 = TC_UPGRADE_IRON_BASE * colony.tc_level.into();
            let uranium_cost: u32 = match colony.tc_level {
                3 => TC_UPGRADE_URANIUM_LV4,
                4 => TC_UPGRADE_URANIUM_LV5,
                _ => 0,
            };

            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= iron_cost, "Planets: insufficient iron");
            if uranium_cost > 0 {
                assert!(resources.uranium >= uranium_cost, "Planets: insufficient uranium");
                resources.uranium -= uranium_cost;
            }
            resources.iron -= iron_cost;
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

            post_action(token_address, planet_id);
        }

        fn upgrade_building(ref self: ContractState, planet_id: felt252, lon: u16, lat: u16) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            pre_action(token_address, planet_id);

            _tick(ref world, planet_id);

            let now = get_block_timestamp();

            let mut building: Building = world.read_model((planet_id, lon, lat));
            assert!(building.exists, "Planets: building not found");
            assert!(building.max_workers > 0, "Planets: cannot upgrade this building type");
            assert!(building.level < 5, "Planets: building already at max level");
            assert!(
                building.completes_at == 0 || now >= building.completes_at,
                "Planets: building is busy",
            );

            let colony: Colony = world.read_model(planet_id);
            assert!(building.level < colony.tc_level, "Planets: upgrade TC first");

            let iron_cost: u32 = UPGRADE_IRON_BASE * building.level.into();
            let uranium_cost: u32 = match building.level {
                3 => UPGRADE_URANIUM_LV4,
                4 => UPGRADE_URANIUM_LV5,
                _ => 0,
            };

            let mut resources: Resources = world.read_model(planet_id);
            assert!(resources.iron >= iron_cost, "Planets: insufficient iron");
            if uranium_cost > 0 {
                assert!(resources.uranium >= uranium_cost, "Planets: insufficient uranium");
                resources.uranium -= uranium_cost;
            }
            resources.iron -= iron_cost;
            world.write_model(@resources);

            // Recompute output at the new level
            // Note: Barracks (4) has 0 base output — its benefit is training speed via building.level
            let new_level: u8 = building.level + 1;
            let base_output: u32 = match building.building_type {
                1 => WATER_WELL_BASE,
                2 => IRON_MINE_BASE,
                5 => URANIUM_MINE_BASE,
                8 => CANNON_DEFENSE_BASE,
                _ => 0,
            };
            let lv1_output: u32 = if base_output == 0 {
                0
            } else {
                base_output * (50_u32 + building.terrain_bonus.into()) / 100_u32
            };
            let level_factor: u32 = match new_level {
                2 => LV2_FACTOR,
                3 => LV3_FACTOR,
                4 => LV4_FACTOR,
                5 => LV5_FACTOR,
                _ => 100,
            };
            let new_output: u32 = lv1_output * level_factor / 100;

            let upgrade_completes_at: u64 = match new_level {
                2 => now + UPGRADE_TIME_LV2,
                3 => now + UPGRADE_TIME_LV3,
                4 => now + UPGRADE_TIME_LV4,
                5 => now + UPGRADE_TIME_LV5,
                _ => now + UPGRADE_TIME_LV2,
            };

            building.level = new_level;
            building.output_per_worker_epoch = new_output;
            building.completes_at = upgrade_completes_at;
            world.write_model(@building);

            post_action(token_address, planet_id);
        }

        fn craft_gear(ref self: ContractState, planet_id: felt252, weapons: u32, armor: u32) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            pre_action(token_address, planet_id);

            let colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: no colony yet");
            assert!(weapons + armor > 0, "Planets: nothing to craft");

            // Require a Workshop to craft gear
            let bcount_check: PlanetBuildingCount = world.read_model(planet_id);
            let mut has_workshop = false;
            let mut wi: u32 = 0;
            loop {
                if wi >= bcount_check.count { break; }
                let wentry: PlanetBuildingEntry = world.read_model((planet_id, wi));
                let wb: Building = world.read_model((planet_id, wentry.lon, wentry.lat));
                if wb.building_type == 7 { has_workshop = true; break; }
                wi += 1;
            };
            assert!(has_workshop, "Planets: Workshop required to craft gear");

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

            post_action(token_address, planet_id);
        }

        fn fight_invader(
            ref self: ContractState, planet_id: felt252, colonists: u8, weapons: u32, armor: u32,
        ) {
            let mut world = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);

            assert_token_ownership(token_address, planet_id);
            pre_action(token_address, planet_id);

            let invader: Invader = world.read_model(planet_id);
            assert!(invader.active, "Planets: no active invader");

            _tick(ref world, planet_id);

            let ua: ColonistsUnassigned = world.read_model(planet_id);
            let col_count: u32 = colonists.into();
            assert!(ua.count >= col_count, "Planets: not enough idle colonists");

            let gear: Gear = world.read_model(planet_id);
            assert!(gear.weapons >= weapons, "Planets: not enough weapons");
            assert!(gear.armor >= armor, "Planets: not enough armor");

            // Sum strength of all unassigned colonists scaled by proportion being sent
            let mut total_ua_strength: u32 = 0;
            let mut si: u32 = 0;
            loop {
                if si >= ua.count { break; }
                let sentry: ColonistUnassignedEntry = world.read_model((planet_id, si));
                let sc: Colonist = world.read_model((planet_id, sentry.colonist_id));
                total_ua_strength += sc.strength.into();
                si += 1;
            };
            let avg_str: u32 = if ua.count > 0 { total_ua_strength / ua.count } else { 1 };
            let base_power: u32 = col_count * avg_str
                + weapons * WEAPON_POWER
                + armor * ARMOR_POWER;

            let now = get_block_timestamp();
            let mut planet: Planet = world.read_model(planet_id);
            let combat_rng: felt252 = poseidon_hash_span(
                array![planet.seed, planet.action_count.into(), now.into(), 42].span(),
            );
            let variance: u32 = (Into::<felt252, u256>::into(combat_rng) % 51).try_into().unwrap_or(25);
            let fighter_power: u32 = if variance >= 25 {
                base_power + base_power * (variance - 25) / 100
            } else {
                let reduction = base_power * (25 - variance) / 100;
                if base_power > reduction { base_power - reduction } else { 0 }
            };

            let invader: Invader = world.read_model(planet_id);

            if fighter_power >= invader.strength {
                let casualties: u32 = if invader.strength / 20 > col_count {
                    col_count
                } else {
                    invader.strength / 20
                };
                _kill_random(ref world, planet_id, casualties, planet.seed, planet.action_count, now);
                planet.population = if planet.population > casualties { planet.population - casualties } else { 0 };
                world.write_model(@Invader { planet_id, active: false, strength: 0, lon: 0, lat: 0, spawned_at: 0 });
            } else {
                let excess = invader.strength - fighter_power;
                let casualties: u32 = if excess / 5 + 1 > col_count { col_count } else { excess / 5 + 1 };
                _kill_random(ref world, planet_id, casualties, planet.seed, planet.action_count, now);
                planet.population = if planet.population > casualties { planet.population - casualties } else { 0 };
                let new_strength = if invader.strength > fighter_power { invader.strength - fighter_power } else { 0 };
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
            post_action(token_address, planet_id);
        }
    }

    // -----------------------------------------------------------------------
    // Tick
    // -----------------------------------------------------------------------

    fn _tick(ref world: WorldStorage, planet_id: felt252) {
        let mut resources: Resources = world.read_model(planet_id);
        let mut planet: Planet = world.read_model(planet_id);

        let now = get_block_timestamp();
        let elapsed = now - resources.last_updated_at;
        let epochs_raw = elapsed / EPOCH_SECONDS;
        if epochs_raw == 0 { return; }

        let epochs: u32 = if epochs_raw > MAX_EPOCHS {
            MAX_EPOCHS.try_into().unwrap()
        } else {
            epochs_raw.try_into().unwrap()
        };

        let bcount: PlanetBuildingCount = world.read_model(planet_id);

        // --- Barracks training completion pass ---
        // For each barracks whose session timer has elapsed: boost assigned colonist strengths,
        // then restart the session if workers remain.
        let mut ci: u32 = 0;
        loop {
            if ci >= bcount.count { break; }
            let centry: PlanetBuildingEntry = world.read_model((planet_id, ci));
            let mut cb: Building = world.read_model((planet_id, centry.lon, centry.lat));
            if cb.building_type == 4 && cb.completes_at > 0 && now >= cb.completes_at {
                if cb.workers > 0 {
                    // Apply strength gain to each colonist assigned to this barracks
                    let assigned_list: ColonistsAssigned = world.read_model(planet_id);
                    let mut ai: u32 = 0;
                    loop {
                        if ai >= assigned_list.count { break; }
                        let aentry: ColonistAssignedEntry = world.read_model((planet_id, ai));
                        let colonist: Colonist = world.read_model((planet_id, aentry.colonist_id));
                        if colonist.building_lon == centry.lon && colonist.building_lat == centry.lat
                            && colonist.strength < COLONIST_MAX_STRENGTH {
                            let new_str: u32 = colonist.strength.into() + cb.level.into();
                            let capped: u8 = if new_str >= COLONIST_MAX_STRENGTH.into() {
                                COLONIST_MAX_STRENGTH
                            } else {
                                new_str.try_into().unwrap_or(COLONIST_MAX_STRENGTH)
                            };
                            world.write_model(@Colonist {
                                planet_id, colonist_id: colonist.colonist_id,
                                is_assigned: colonist.is_assigned,
                                building_lon: colonist.building_lon, building_lat: colonist.building_lat,
                                strength: capped,
                            });
                        }
                        ai += 1;
                    };
                    // Restart training session
                    cb.completes_at = now + BARRACKS_TRAIN_BASE * cb.level.into();
                } else {
                    cb.completes_at = 0;
                }
                world.write_model(@cb);
            }
            ci += 1;
        };

        // --- Non-barracks construction/upgrade completion: clear elapsed timers ---
        let mut cli: u32 = 0;
        loop {
            if cli >= bcount.count { break; }
            let clentry: PlanetBuildingEntry = world.read_model((planet_id, cli));
            let mut clb: Building = world.read_model((planet_id, clentry.lon, clentry.lat));
            if clb.building_type != 4 && clb.completes_at > 0 && now >= clb.completes_at {
                clb.completes_at = 0;
                world.write_model(@clb);
            }
            cli += 1;
        };

        // --- Compute production rates (skip buildings still under construction/upgrade/training) ---
        let mut water_rate: u32 = 0;
        let mut iron_rate: u32 = 0;
        let mut defense_rate: u32 = 0;
        let mut uranium_rate: u32 = 0;
        let mut cannon_damage_rate: u32 = 0;

        let mut i: u32 = 0;
        loop {
            if i >= bcount.count { break; }
            let entry: PlanetBuildingEntry = world.read_model((planet_id, i));
            let b: Building = world.read_model((planet_id, entry.lon, entry.lat));
            // Skip buildings that are still busy (construction, upgrade, or training in progress)
            let active = b.completes_at == 0 || now >= b.completes_at;
            if active {
                let w: u32 = b.workers.into();
                if b.building_type == 1 { water_rate   += w * b.output_per_worker_epoch; }
                else if b.building_type == 2 { iron_rate    += w * b.output_per_worker_epoch; }
                else if b.building_type == 5 { uranium_rate += w * b.output_per_worker_epoch; }
                else if b.building_type == 8 {
                    defense_rate += w * b.output_per_worker_epoch;
                    cannon_damage_rate += w * b.output_per_worker_epoch;
                }
            }
            i += 1;
        };

        resources.iron    += iron_rate    * epochs;
        resources.defense += defense_rate * epochs;
        resources.uranium += uranium_rate * epochs;

        // Invader passive damage and cannon fire
        let mut invader: Invader = world.read_model(planet_id);

        // Cannon fires before passive damage — may kill invader entirely
        if invader.active && cannon_damage_rate > 0 {
            let cannon_total = cannon_damage_rate * epochs;
            let new_inv_str = if invader.strength > cannon_total { invader.strength - cannon_total } else { 0 };
            let new_inv_active = new_inv_str > 0;
            world.write_model(@Invader {
                planet_id, active: new_inv_active, strength: new_inv_str,
                lon: invader.lon, lat: invader.lat, spawned_at: invader.spawned_at,
            });
            invader.active = new_inv_active;
            invader.strength = new_inv_str;
        }
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
                let casualties: u32 = if overflow / 10 < 1 { 1 } else { overflow / 10 };
                let actual = if casualties > planet.population { planet.population } else { casualties };
                if actual > 0 {
                    _kill_random(ref world, planet_id, actual, planet.seed, planet.action_count + 2000, now);
                    planet.population = if planet.population > actual { planet.population - actual } else { 0 };
                }
            }
        }

        // Water: produce then consume (1 per colonist per epoch)
        let water_produced = water_rate * epochs;
        let water_consumed = planet.population * epochs;
        let available = resources.water + water_produced;

        if available >= water_consumed {
            resources.water = available - water_consumed;

            let colony: Colony = world.read_model(planet_id);
            let max_pop: u32 = colony.tc_level.into() * POP_PER_TC_LEVEL;
            if resources.water > planet.population * 5 && planet.population < max_pop {
                let raw_growth = planet.population / 10;
                let growth: u32 = if raw_growth < 1 { 1 } else if raw_growth > 3 { 3 } else { raw_growth };
                let to_spawn: u32 = if planet.population + growth > max_pop {
                    max_pop - planet.population
                } else {
                    growth
                };
                let mut j: u32 = 0;
                loop {
                    if j >= to_spawn { break; }
                    _spawn_colonist(ref world, planet_id);
                    j += 1;
                };
                planet.population += to_spawn;
            }
        } else {
            resources.water = 0;
            let deaths_per_epoch: u32 = if planet.population / 10 < 1 { 1 } else { planet.population / 10 };
            let total_deaths: u32 = if deaths_per_epoch * epochs / 2 > planet.population {
                planet.population
            } else {
                deaths_per_epoch * epochs / 2
            };
            _kill_random(ref world, planet_id, total_deaths, planet.seed, planet.action_count, now);
            planet.population = if planet.population > total_deaths { planet.population - total_deaths } else { 0 };
        }

        // Threat check
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

            if rng_pct < threat / 3 {
                let colony: Colony = world.read_model(planet_id);
                let base_lon: u32 = colony.col * LON_PER_HEX + LON_PER_HEX / 2;
                let base_lat: u32 = colony.row * LAT_PER_HEX + LAT_PER_HEX / 2;
                let rng2: felt252 = poseidon_hash_span(
                    array![planet.seed, planet.action_count.into(), now.into(), 1337].span(),
                );
                let offset_u256: u256 = rng2.into();
                let lon_offset: u32 = (offset_u256 % 360).try_into().unwrap_or(180);
                let lat_offset: u32 = ((offset_u256 / 360) % 180).try_into().unwrap_or(90);
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
                invader.active = true;
            }
        }

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
        ref world: WorldStorage, planet_id: felt252, count: u32,
        seed: felt252, base_nonce: u32, now: u64,
    ) {
        let mut left = count;
        let mut nonce = base_nonce;

        loop {
            if left == 0 { break; }
            let ua: ColonistsUnassigned = world.read_model(planet_id);
            if ua.count == 0 { break; }
            let rng: felt252 = poseidon_hash_span(array![seed, nonce.into(), now.into()].span());
            let victim_idx: u32 = (Into::<felt252, u256>::into(rng) % ua.count.into()).try_into().unwrap_or(0);
            let entry: ColonistUnassignedEntry = world.read_model((planet_id, victim_idx));
            _remove_from_unassigned(ref world, planet_id, entry.colonist_id);
            nonce += 1;
            left -= 1;
        };

        loop {
            if left == 0 { break; }
            let assigned: ColonistsAssigned = world.read_model(planet_id);
            if assigned.count == 0 { break; }
            let rng: felt252 = poseidon_hash_span(array![seed, nonce.into(), now.into()].span());
            let victim_idx: u32 = (Into::<felt252, u256>::into(rng) % assigned.count.into()).try_into().unwrap_or(0);
            let entry: ColonistAssignedEntry = world.read_model((planet_id, victim_idx));
            let colonist: Colonist = world.read_model((planet_id, entry.colonist_id));
            let mut building: Building = world.read_model((planet_id, colonist.building_lon, colonist.building_lat));
            if building.workers > 0 { building.workers -= 1; world.write_model(@building); }
            _remove_from_assigned(ref world, planet_id, entry.colonist_id);
            nonce += 1;
            left -= 1;
        };
    }

    // -----------------------------------------------------------------------
    // Colonist helpers
    // -----------------------------------------------------------------------

    fn _spawn_colonist(ref world: WorldStorage, planet_id: felt252) {
        let mut pcc: PlanetColonistCount = world.read_model(planet_id);
        let cid = pcc.count;
        world.write_model(@Colonist { planet_id, colonist_id: cid, is_assigned: false, building_lon: 0, building_lat: 0, strength: COLONIST_DEFAULT_STRENGTH });
        _add_to_unassigned(ref world, planet_id, cid);
        pcc.count += 1;
        world.write_model(@pcc);
    }

    fn _add_to_unassigned(ref world: WorldStorage, planet_id: felt252, colonist_id: u32) {
        let mut ua: ColonistsUnassigned = world.read_model(planet_id);
        let idx = ua.count;
        world.write_model(@ColonistUnassignedEntry { planet_id, index: idx, colonist_id });
        world.write_model(@ColonistUnassignedIdx { planet_id, colonist_id, index: idx });
        ua.count += 1;
        world.write_model(@ua);
    }

    fn _remove_from_unassigned(ref world: WorldStorage, planet_id: felt252, colonist_id: u32) {
        let mut ua: ColonistsUnassigned = world.read_model(planet_id);
        if ua.count == 0 { return; }
        let idx_model: ColonistUnassignedIdx = world.read_model((planet_id, colonist_id));
        let idx = idx_model.index;
        let last_idx = ua.count - 1;
        if idx < last_idx {
            let last: ColonistUnassignedEntry = world.read_model((planet_id, last_idx));
            world.write_model(@ColonistUnassignedEntry { planet_id, index: idx, colonist_id: last.colonist_id });
            world.write_model(@ColonistUnassignedIdx { planet_id, colonist_id: last.colonist_id, index: idx });
        }
        ua.count = last_idx;
        world.write_model(@ua);
    }

    fn _add_to_assigned(ref world: WorldStorage, planet_id: felt252, colonist_id: u32) {
        let mut assigned: ColonistsAssigned = world.read_model(planet_id);
        let idx = assigned.count;
        world.write_model(@ColonistAssignedEntry { planet_id, index: idx, colonist_id });
        world.write_model(@ColonistAssignedIdx { planet_id, colonist_id, index: idx });
        assigned.count += 1;
        world.write_model(@assigned);
    }

    fn _remove_from_assigned(ref world: WorldStorage, planet_id: felt252, colonist_id: u32) {
        let mut assigned: ColonistsAssigned = world.read_model(planet_id);
        if assigned.count == 0 { return; }
        let idx_model: ColonistAssignedIdx = world.read_model((planet_id, colonist_id));
        let idx = idx_model.index;
        let last_idx = assigned.count - 1;
        if idx < last_idx {
            let last: ColonistAssignedEntry = world.read_model((planet_id, last_idx));
            world.write_model(@ColonistAssignedEntry { planet_id, index: idx, colonist_id: last.colonist_id });
            world.write_model(@ColonistAssignedIdx { planet_id, colonist_id: last.colonist_id, index: idx });
        }
        assigned.count = last_idx;
        world.write_model(@assigned);
    }

    fn _get_token_address(world: WorldStorage) -> ContractAddress {
        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher { contract_address: game_token_systems_address };
        minigame_dispatcher.token_address()
    }
}
