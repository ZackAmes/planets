// SPDX-License-Identifier: MIT

#[starknet::interface]
pub trait IGameSystems<T> {
    /// Place the initial colony at grid position (col, row).
    /// Must be called once after spawn_planet and before assign_orders.
    fn found_colony(ref self: T, planet_id: u64, col: u32, row: u32);

    /// Process one turn of the colony.
    /// farming + mining + building + defense must sum to <= 100 (percentage points).
    fn assign_orders(
        ref self: T,
        planet_id: u64,
        farming: u8,
        mining: u8,
        building: u8,
        defense: u8,
    );
}

#[dojo::contract]
mod game_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::colony::Colony;
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_embeddable_game_standard::minigame::minigame::{
        assert_token_ownership, post_action, pre_action,
    };
    use game_components_interfaces::{IMinigameDispatcher, IMinigameDispatcherTrait, IMinigame};
    use starknet::ContractAddress;
    use core::poseidon::poseidon_hash_span;

    const STARTING_FOOD: u32 = 500;
    const STARTING_MINERALS: u32 = 200;
    const STARTING_DEFENSE: u32 = 20;

    #[abi(embed_v0)]
    impl GameSystemsImpl of super::IGameSystems<ContractState> {
        fn found_colony(ref self: ContractState, planet_id: u64, col: u32, row: u32) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let token_address = _get_token_address(world);
            let token_id: felt252 = planet_id.into();

            assert_token_ownership(token_address, token_id);
            pre_action(token_address, token_id);

            let planet: Planet = world.read_model(planet_id);
            assert!(planet.population > 0, "Planets: planet not yet spawned");
            assert!(col < planet.width, "Planets: col out of bounds");
            assert!(row < planet.height, "Planets: row out of bounds");

            let colony: Colony = world.read_model(planet_id);
            assert!(!colony.founded, "Planets: colony already founded");

            // Derive terrain bonuses from (seed, col, row) via Poseidon hash.
            // fertility and mineral_richness are in range 0-100.
            let hash: felt252 = poseidon_hash_span(
                array![planet.seed, col.into(), row.into()].span()
            );
            let h: u256 = hash.into();
            let fertility: u8 = ((h % 101).try_into().unwrap_or(50));
            let mineral_richness: u8 = (((h / 256) % 101).try_into().unwrap_or(50));

            world
                .write_model(
                    @Colony {
                        planet_id,
                        col,
                        row,
                        founded: true,
                        food: STARTING_FOOD,
                        minerals: STARTING_MINERALS,
                        buildings: 0,
                        defense: STARTING_DEFENSE,
                        fertility,
                        mineral_richness,
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

            assert!(colony.founded, "Planets: found a colony first");
            assert!(planet.population > 0, "Planets: colony is gone");

            let total: u32 = farming.into() + mining.into() + building.into() + defense.into();
            assert!(total <= 100, "Planets: orders exceed 100 percent");

            let pop = planet.population;

            // ---------------------------------------------------------------
            // Production
            // food_prod   = pop * farming%  * (100 + fertility) / 10000
            //   At pop=100, farming=70, fertility=80 → 100*70*180/10000 = 126
            //   At pop=100, farming=70, fertility=50 → 100*70*150/10000 = 105
            //   At pop=100, farming=50, fertility=50 → 75  (below consumption)
            // mineral_prod = pop * mining% * (100 + mineral_richness) / 10000
            // ---------------------------------------------------------------
            let food_prod: u32 = pop
                * farming.into()
                * (100_u32 + colony.fertility.into())
                / 10000_u32;
            let food_consumed: u32 = pop; // 1 food per person per turn

            let mineral_prod: u32 = pop
                * mining.into()
                * (100_u32 + colony.mineral_richness.into())
                / 10000_u32;

            let build_prog: u32 = pop * building.into() / 100_u32;
            let def_gain: u32 = pop * defense.into() / 100_u32;

            // ---------------------------------------------------------------
            // Apply resources
            // ---------------------------------------------------------------
            let new_food = colony.food + food_prod;
            if new_food >= food_consumed {
                colony.food = new_food - food_consumed;
            } else {
                colony.food = 0;
            }
            colony.minerals += mineral_prod;
            colony.buildings += build_prog;
            colony.defense += def_gain;

            // ---------------------------------------------------------------
            // Population dynamics
            // ---------------------------------------------------------------
            if colony.food == 0 {
                // Starvation: lose ~10% of population per turn
                let deaths = if pop / 10 > 1 {
                    pop / 10
                } else {
                    1
                };
                if pop > deaths {
                    planet.population -= deaths;
                } else {
                    planet.population = 0;
                }
            } else if colony.food > pop * 10 {
                // Large food surplus: ~5% growth, capped at +10 per turn
                let raw_growth = pop / 20;
                let growth = if raw_growth > 10 {
                    10
                } else if raw_growth < 1 {
                    1
                } else {
                    raw_growth
                };
                planet.population += growth;
            }

            // ---------------------------------------------------------------
            // Enemy attack (Poseidon RNG, 20% chance per turn)
            // Attack strength grows with the turn number, capped at 150.
            // ---------------------------------------------------------------
            let turn: felt252 = planet.action_count.into();
            let rng: felt252 = poseidon_hash_span(array![planet.seed, turn].span());
            let rng_u32: u32 = ((Into::<felt252, u256>::into(rng)) % 100)
                .try_into()
                .unwrap_or(50);

            if rng_u32 < 20 {
                let attack_raw = planet.action_count * 3;
                let attack = if attack_raw < 150 {
                    attack_raw
                } else {
                    150
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
                    if planet.population > casualties {
                        planet.population -= casualties;
                    } else {
                        planet.population = 0;
                    }
                    // Defense degrades under attack
                    let def_damage = attack / 2;
                    if colony.defense > def_damage {
                        colony.defense -= def_damage;
                    } else {
                        colony.defense = 0;
                    }
                }
            }

            planet.action_count += 1;
            world.write_model(@planet);
            world.write_model(@colony);

            post_action(token_address, token_id);
        }
    }

    fn _get_token_address(world: WorldStorage) -> ContractAddress {
        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher {
            contract_address: game_token_systems_address,
        };
        minigame_dispatcher.token_address()
    }
}
