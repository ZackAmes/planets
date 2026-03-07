// SPDX-License-Identifier: MIT

#[starknet::interface]
pub trait IPlanetSystems<T> {
    fn spawn_planet(ref self: T, planet_id: u64, name: felt252);
}

#[dojo::contract]
pub mod planet_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::player_planets::{PlayerPlanets, PlayerPlanetEntry};
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use starknet::{get_caller_address, get_block_timestamp};
    use planets::utils::vrf::VRFTrait;

    const PLANET_WIDTH: u32 = 50;
    const PLANET_HEIGHT: u32 = 40;
    const STARTING_POPULATION: u32 = 100;

    #[abi(embed_v0)]
    impl PlanetSystemsImpl of super::IPlanetSystems<ContractState> {
        /// Creates a planet for `planet_id` (== the caller's game token id).
        /// The seed is the transaction hash, ensuring each planet is unique.
        fn spawn_planet(ref self: ContractState, planet_id: u64, name: felt252) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let caller = get_caller_address();
            let seed: felt252 = VRFTrait::seed(VRFTrait::cartridge_vrf_address());

            let now = get_block_timestamp();
            world
                .write_model(
                    @Planet {
                        planet_id,
                        owner: caller,
                        seed,
                        width: PLANET_WIDTH,
                        height: PLANET_HEIGHT,
                        name,
                        spawned_at: now,
                        last_action_at: now,
                        population: STARTING_POPULATION,
                        action_count: 0,
                    }
                );

            // Index this planet under the caller's address so it can be
            // looked up onchain without relying on client-side storage.
            let mut registry: PlayerPlanets = world.read_model(caller);
            let index = registry.count;
            world.write_model(@PlayerPlanetEntry { player: caller, index, planet_id });
            registry.count = index + 1;
            world.write_model(@registry);
        }
    }
}
