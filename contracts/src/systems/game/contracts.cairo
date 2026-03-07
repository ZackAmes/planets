// SPDX-License-Identifier: MIT

use planets::models::building::BuildingType;

#[starknet::interface]
pub trait IGameSystems<T> {
    /// Place the initial colony at grid position (col, row).
    fn found_colony(ref self: T, planet_id: u64, col: u32, row: u32);

    /// Process one turn of the colony.
    /// farming + mining + building + defense must sum to <= 100.
    /// Production is multiplied by epochs elapsed since last call (1 epoch = 600 s).
    fn assign_orders(
        ref self: T,
        planet_id: u64,
        farming: u8,
        mining: u8,
        building: u8,
        defense: u8,
    );

    /// Construct a building at the given lat/lon coordinates.
    /// lon 0-3599, lat 0-1799 (tenths of a degree).
    /// Costs minerals + build_points. Does not consume a turn.
    fn construct_building(
        ref self: T, planet_id: u64, lon: u16, lat: u16, building_type: BuildingType,
    );
}

#[dojo::contract]
mod game_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::colony::Colony;
    use planets::models::building::{
        Building, BuildingType, PlanetBuildingCount, PlanetBuildingEntry,
    };
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_embeddable_game_standard::minigame::minigame::{
        assert_token_ownership, post_action, pre_action,
    };
    use game_components_interfaces::{IMinigameDispatcher, IMinigameDispatcherTrait, IMinigame};
    use starknet::{ContractAddress, get_block_timestamp};
    use core::poseidon::poseidon_hash_span;

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    const STARTING_FOOD: u32 = 500;
    const STARTING_MINERALS: u32 = 200;
    const STARTING_DEFENSE: u32 = 20;

    /// One epoch = 600 seconds (10 minutes).
    /// Production = per-epoch rate × elapsed epochs.
    const EPOCH_SECONDS: u64 = 600;

    /// Cap accumulated epochs at 144 (24 hours).
    /// Beyond this the colony doesn't gain more — but it also stops
    /// accumulating threat, so the cap is symmetric.
    const MAX_EPOCHS: u64 = 144;

    // Building mineral + build_points costs
    const FARM_MINERAL_COST: u32 = 100;
    const FARM_BUILD_COST: u32 = 75;
    const MINE_MINERAL_COST: u32 = 150;
    const MINE_BUILD_COST: u32 = 75;
    const BARRACKS_MINERAL_COST: u32 = 150;
    const BARRACKS_BUILD_COST: u32 = 125;
    const WORKSHOP_MINERAL_COST: u32 = 200;
    const WORKSHOP_BUILD_COST: u32 = 150;

    // Base output per epoch before terrain bonus
    // actual = base × (50 + terrain_bonus) / 100
    const FARM_BASE_OUTPUT: u32 = 20;   // food / epoch
    const MINE_BASE_OUTPUT: u32 = 15;   // minerals / epoch
    const BARRACKS_BASE_OUTPUT: u32 = 20; // defense / epoch
    const WORKSHOP_BASE_OUTPUT: u32 = 10; // build_points / epoch

    // -----------------------------------------------------------------------
    // Interface implementation
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl GameSystemsImpl of super::IGameSystems<ContractState> {
        fn found_colony(ref self: ContractState, planet_id: u64, col: u32, row: u32) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let mut planet: Planet = world.read_model(planet_id);
            assert!(planet.population > 0, "Planets: planet not yet spawned");
            assert!(col < planet.width, "Planets: col out of bounds");
            assert!(row < planet.height, "Planets: row out of bounds");

            let colony: Colony = world.read_model(planet_id);
            assert!(!colony.founded, "Planets: colony already founded");

            // Terrain bonuses derived from planet seed + chosen location
            let hash: felt252 = poseidon_hash_span(
                array![planet.seed, col.into(), row.into()].span()
            );
            let h: u256 = hash.into();
            let fertility: u8 = ((h % 101).try_into().unwrap_or(50));
            let mineral_richness: u8 = (((h / 256) % 101).try_into().unwrap_or(50));

            // Reset the production clock to colony founding time
            let now = get_block_timestamp();
            planet.last_action_at = now;
            world.write_model(@planet);

            world
                .write_model(
                    @Colony {
                        planet_id,
                        col,
                        row,
                        founded: true,
                        food: STARTING_FOOD,
                        minerals: STARTING_MINERALS,
                        build_points: 0,
                        defense: STARTING_DEFENSE,
                        fertility,
                        mineral_richness,
                        farms: 0,
                        mines: 0,
                        barracks: 0,
                        workshops: 0,
                        farm_output: 0,
                        mine_output: 0,
                        barracks_output: 0,
                        workshop_output: 0,
                    }
                );

            post_action(token_address, token_id);
        }

        fn assign_orders(
            ref self: ContractState,
            planet_id: u64,
            farming: u8,
            mining: u8,
            building: u8,
            defense: u8,
        ) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let mut planet: Planet = world.read_model(planet_id);
            let mut colony: Colony = world.read_model(planet_id);

            assert!(colony.founded, "Planets: find a colony location first");
            assert!(planet.population > 0, "Planets: colony is gone");

            let total: u32 = farming.into() + mining.into() + building.into() + defense.into();
            assert!(total <= 100, "Planets: orders exceed 100 percent");

            // -------------------------------------------------------------------
            // Time elapsed
            // -------------------------------------------------------------------
            let now: u64 = get_block_timestamp();
            let elapsed: u64 = now - planet.last_action_at;
            let epochs_raw: u64 = elapsed / EPOCH_SECONDS;
            let epochs_capped: u64 = if epochs_raw > MAX_EPOCHS {
                MAX_EPOCHS
            } else {
                epochs_raw
            };
            // Always process at least 1 epoch so immediate calls still produce
            let epochs: u32 = if epochs_capped == 0 {
                1_u32
            } else {
                epochs_capped.try_into().unwrap_or(MAX_EPOCHS.try_into().unwrap())
            };

            let pop = planet.population;

            // -------------------------------------------------------------------
            // Per-epoch production rates
            //   Worker output  : population × allocation% × terrain / 10000
            //   Building output: colony aggregate (pre-computed, terrain-adjusted)
            // -------------------------------------------------------------------
            let food_rate: u32 = pop
                * farming.into()
                * (100_u32 + colony.fertility.into())
                / 10000_u32
                + colony.farm_output;

            let food_consumed_rate: u32 = pop; // 1 food per colonist per epoch

            let mineral_rate: u32 = pop
                * mining.into()
                * (100_u32 + colony.mineral_richness.into())
                / 10000_u32
                + colony.mine_output;

            let build_rate: u32 = pop * building.into() / 100_u32 + colony.workshop_output;

            let defense_rate: u32 = pop * defense.into() / 100_u32 + colony.barracks_output;

            // Scale by epochs
            let food_prod: u32 = food_rate * epochs;
            let food_consumed: u32 = food_consumed_rate * epochs;
            let mineral_prod: u32 = mineral_rate * epochs;
            let build_prog: u32 = build_rate * epochs;
            let def_gain: u32 = defense_rate * epochs;

            // -------------------------------------------------------------------
            // Apply resources
            // -------------------------------------------------------------------
            let new_food = colony.food + food_prod;
            colony.food = if new_food >= food_consumed {
                new_food - food_consumed
            } else {
                0
            };
            colony.minerals += mineral_prod;
            colony.build_points += build_prog;
            colony.defense += def_gain;

            // -------------------------------------------------------------------
            // Population dynamics
            // -------------------------------------------------------------------
            if colony.food == 0 {
                // Starvation — scale severity with time elapsed
                let deaths_per_epoch = if pop / 10 > 1 {
                    pop / 10
                } else {
                    1
                };
                let total_deaths = deaths_per_epoch * epochs / 2;
                planet.population = if pop > total_deaths {
                    pop - total_deaths
                } else {
                    0
                };
            } else if colony.food > pop * 10 * epochs {
                // Surplus growth (single pass, capped)
                let raw_growth = pop / 20;
                let growth = if raw_growth > 10 {
                    10_u32
                } else if raw_growth < 1 {
                    1_u32
                } else {
                    raw_growth
                };
                planet.population += growth;
            }

            // -------------------------------------------------------------------
            // Threat level
            //   time_component  : grows as colony ages (incentivises activity)
            //   wealth_component: stockpile attracts raiders (incentivises spending)
            //   size_component  : larger colonies are bigger targets
            // -------------------------------------------------------------------
            let time_alive: u64 = now - planet.spawned_at;
            let time_epochs: u32 = ((time_alive / EPOCH_SECONDS) / 10)
                .try_into()
                .unwrap_or(255);
            let wealth: u32 = (colony.food / 100) + (colony.minerals / 100);
            let size_comp: u32 = planet.population / 20;
            let threat_raw: u32 = time_epochs + wealth + size_comp;
            let threat: u32 = if threat_raw > 100 {
                100_u32
            } else {
                threat_raw
            };

            // -------------------------------------------------------------------
            // Enemy attack — probability proportional to threat (max 80%)
            // -------------------------------------------------------------------
            let attack_prob: u32 = threat * 80 / 100;

            let rng: felt252 = poseidon_hash_span(
                array![planet.seed, planet.action_count.into(), now.into()].span()
            );
            let rng_u32: u32 = ((Into::<felt252, u256>::into(rng)) % 100)
                .try_into()
                .unwrap_or(50);

            if rng_u32 < attack_prob {
                // Attack strength: threat-based, grows with accumulated idle time
                let attack_raw: u32 = threat * 3 + epochs;
                let attack: u32 = if attack_raw > 250 {
                    250_u32
                } else {
                    attack_raw
                };

                if attack > colony.defense {
                    let excess = attack - colony.defense;
                    let casualties_raw = excess / 2;
                    let pop_cap = planet.population / 3;
                    let casualties = if casualties_raw < pop_cap {
                        casualties_raw
                    } else {
                        pop_cap
                    };
                    planet.population = if planet.population > casualties {
                        planet.population - casualties
                    } else {
                        0
                    };
                    let def_damage = attack / 2;
                    colony.defense = if colony.defense > def_damage {
                        colony.defense - def_damage
                    } else {
                        0
                    };
                }
            }

            planet.last_action_at = now;
            planet.action_count += 1;
            world.write_model(@planet);
            world.write_model(@colony);

            post_action(token_address, token_id);
        }

        fn construct_building(
            ref self: ContractState,
            planet_id: u64,
            lon: u16,
            lat: u16,
            building_type: BuildingType,
        ) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);

            let planet: Planet = world.read_model(planet_id);
            let mut colony: Colony = world.read_model(planet_id);
            assert!(colony.founded, "Planets: find a colony location first");

            assert!(lon < 3600, "Planets: lon out of range");
            assert!(lat < 1800, "Planets: lat out of range");

            let existing: Building = world.read_model((planet_id, lon, lat));
            assert!(!existing.exists, "Planets: location already occupied");

            // Cost
            let (mineral_cost, build_cost) = match building_type {
                BuildingType::Farm => (FARM_MINERAL_COST, FARM_BUILD_COST),
                BuildingType::Mine => (MINE_MINERAL_COST, MINE_BUILD_COST),
                BuildingType::Barracks => (BARRACKS_MINERAL_COST, BARRACKS_BUILD_COST),
                BuildingType::Workshop => (WORKSHOP_MINERAL_COST, WORKSHOP_BUILD_COST),
            };

            assert!(colony.minerals >= mineral_cost, "Planets: insufficient minerals");
            assert!(colony.build_points >= build_cost, "Planets: insufficient build points");

            colony.minerals -= mineral_cost;
            colony.build_points -= build_cost;

            // Terrain type from the 2-D hash noise grid (seamless, mirrors client).
            let building_type_u8: u8 = match building_type {
                BuildingType::Farm => 0,
                BuildingType::Mine => 1,
                BuildingType::Barracks => 2,
                BuildingType::Workshop => 3,
            };
            let terrain_type: u32 = planets::libs::terrain::terrain_at(planet.seed, lon, lat);
            let terrain_bonus: u8 = planets::libs::terrain::terrain_bonus(
                building_type_u8, terrain_type,
            );

            // output = base × (50 + bonus) / 100
            // At bonus=0  : 50% of base (poor terrain still produces)
            // At bonus=100: 150% of base (ideal terrain)
            let base: u32 = match building_type {
                BuildingType::Farm => FARM_BASE_OUTPUT,
                BuildingType::Mine => MINE_BASE_OUTPUT,
                BuildingType::Barracks => BARRACKS_BASE_OUTPUT,
                BuildingType::Workshop => WORKSHOP_BASE_OUTPUT,
            };
            let output_per_epoch: u32 = base * (50_u32 + terrain_bonus.into()) / 100_u32;

            // Update colony building counts and aggregate outputs
            match building_type {
                BuildingType::Farm => {
                    colony.farms += 1;
                    colony.farm_output += output_per_epoch;
                },
                BuildingType::Mine => {
                    colony.mines += 1;
                    colony.mine_output += output_per_epoch;
                },
                BuildingType::Barracks => {
                    colony.barracks += 1;
                    colony.barracks_output += output_per_epoch;
                },
                BuildingType::Workshop => {
                    colony.workshops += 1;
                    colony.workshop_output += output_per_epoch;
                },
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
                        output_per_epoch,
                    }
                );

            // Update building index
            let mut bcount: PlanetBuildingCount = world.read_model(planet_id);
            let index = bcount.count;
            world.write_model(@PlanetBuildingEntry { planet_id, index, lon, lat });
            bcount.count = index + 1;
            world.write_model(@bcount);

            world.write_model(@colony);
        }
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    fn _get_token_address(world: WorldStorage) -> ContractAddress {
        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher {
            contract_address: game_token_systems_address,
        };
        minigame_dispatcher.token_address()
    }

}
