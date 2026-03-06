// SPDX-License-Identifier: MIT

#[starknet::interface]
pub trait IPlanetSystems<T> {
    fn spawn_planet(ref self: T, planet_id: u64, name: felt252);
}

#[dojo::contract]
pub mod planet_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use starknet::{get_caller_address, get_block_timestamp, get_tx_info};

    const PLANET_WIDTH: u32 = 50;
    const PLANET_HEIGHT: u32 = 40;
    const STARTING_POPULATION: u32 = 100;

    #[abi(embed_v0)]
    impl PlanetSystemsImpl of super::IPlanetSystems<ContractState> {
        /// Creates a planet for `planet_id` (== the caller's game token id).
        /// The seed is the transaction hash, ensuring each planet is unique.
        fn spawn_planet(ref self: ContractState, planet_id: u64, name: felt252) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let seed: felt252 = get_tx_info().unbox().transaction_hash;

            world.write_model(
                @Planet {
                    planet_id,
                    owner: get_caller_address(),
                    seed,
                    width: PLANET_WIDTH,
                    height: PLANET_HEIGHT,
                    name,
                    spawned_at: get_block_timestamp(),
                    population: STARTING_POPULATION,
                    action_count: 0,
                }
            );
        }
    }
}
