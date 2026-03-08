// SPDX-License-Identifier: MIT

use planets::models::planet::Planet;
use planets::models::colony::Colony;
use planets::models::resources::Resources;
use planets::models::colonists::{Colonist, ColonistsAssigned, ColonistsUnassigned, ColonistUnassignedEntry};
use planets::models::building::Building;
use planets::models::invader::Invader;
use planets::models::gear::Gear;
use starknet::ContractAddress;

/// All planet state bundled into a single struct for efficient client reads.
#[derive(Drop, Serde)]
pub struct PlanetState {
    pub planet: Planet,
    pub colony: Colony,
    pub resources: Resources,
    pub assigned_count: u32,
    pub unassigned_count: u32,
    /// Sum of strength of all unassigned colonists (for fight power preview).
    pub unassigned_total_strength: u32,
    pub buildings: Array<Building>,
    pub invader: Invader,
    pub gear: Gear,
}

#[starknet::interface]
pub trait IPlanetSystems<T> {
    fn spawn_planet(ref self: T, planet_id: felt252, name: felt252);
}

#[starknet::interface]
pub trait IPlanetQuery<T> {
    fn get_full_state(self: @T, planet_id: felt252) -> PlanetState;
    fn get_planet(self: @T, planet_id: felt252) -> Planet;
    fn get_colony(self: @T, planet_id: felt252) -> Colony;
    fn get_resources(self: @T, planet_id: felt252) -> Resources;
    fn get_colonists_assigned(self: @T, planet_id: felt252) -> ColonistsAssigned;
    fn get_colonists_unassigned(self: @T, planet_id: felt252) -> ColonistsUnassigned;
    fn get_player_planets(self: @T, player: ContractAddress) -> Array<felt252>;
    fn get_planet_buildings(self: @T, planet_id: felt252) -> Array<Building>;
    fn get_invader(self: @T, planet_id: felt252) -> Invader;
    fn get_gear(self: @T, planet_id: felt252) -> Gear;
}

#[dojo::contract]
pub mod planet_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::colony::Colony;
    use planets::models::resources::Resources;
    use planets::models::colonists::{Colonist, ColonistsAssigned, ColonistsUnassigned, ColonistUnassignedEntry};
    use planets::models::player_planets::{PlayerPlanets, PlayerPlanetEntry};
    use planets::models::building::{Building, PlanetBuildingCount, PlanetBuildingEntry};
    use planets::models::invader::Invader;
    use planets::models::gear::Gear;
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use planets::utils::vrf::VRFTrait;
    use super::PlanetState;

    const PLANET_WIDTH: u32 = 50;
    const PLANET_HEIGHT: u32 = 40;

    #[abi(embed_v0)]
    impl PlanetSystemsImpl of super::IPlanetSystems<ContractState> {
        fn spawn_planet(ref self: ContractState, planet_id: felt252, name: felt252) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            let caller = get_caller_address();
            let seed: felt252 = VRFTrait::seed(VRFTrait::cartridge_vrf_address());

            let planet: Planet = world.read_model(planet_id);
            assert!(planet.spawned_at == 0, "Planet already spawned" );

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
                        population: 0,
                        action_count: 0,
                    }
                );

            let mut registry: PlayerPlanets = world.read_model(caller);
            let index = registry.count;
            world.write_model(@PlayerPlanetEntry { player: caller, index, planet_id });
            registry.count = index + 1;
            world.write_model(@registry);
        }
    }

    #[abi(embed_v0)]
    impl PlanetQueryImpl of super::IPlanetQuery<ContractState> {
        fn get_full_state(self: @ContractState, planet_id: felt252) -> PlanetState {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let colony: Colony = world.read_model(planet_id);
            let resources: Resources = world.read_model(planet_id);
            let assigned: ColonistsAssigned = world.read_model(planet_id);
            let unassigned: ColonistsUnassigned = world.read_model(planet_id);

            // Sum strength of all unassigned colonists for fight power preview
            let mut unassigned_total_strength: u32 = 0;
            let mut ui: u32 = 0;
            loop {
                if ui >= unassigned.count { break; }
                let ue: ColonistUnassignedEntry = world.read_model((planet_id, ui));
                let c: Colonist = world.read_model((planet_id, ue.colonist_id));
                unassigned_total_strength += c.strength.into();
                ui += 1;
            };

            let buildings = _read_buildings(@world, planet_id);
            let invader: Invader = world.read_model(planet_id);
            let gear: Gear = world.read_model(planet_id);
            PlanetState {
                planet,
                colony,
                resources,
                assigned_count: assigned.count,
                unassigned_count: unassigned.count,
                unassigned_total_strength,
                buildings,
                invader,
                gear,
            }
        }

        fn get_planet(self: @ContractState, planet_id: felt252) -> Planet {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_colony(self: @ContractState, planet_id: felt252) -> Colony {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_resources(self: @ContractState, planet_id: felt252) -> Resources {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_colonists_assigned(self: @ContractState, planet_id: felt252) -> ColonistsAssigned {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_colonists_unassigned(
            self: @ContractState, planet_id: felt252,
        ) -> ColonistsUnassigned {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_player_planets(self: @ContractState, player: ContractAddress) -> Array<felt252> {
            let world = self.world(@DEFAULT_NS());
            let registry: PlayerPlanets = world.read_model(player);
            let mut result: Array<felt252> = array![];
            let mut i: u32 = 0;
            loop {
                if i >= registry.count {
                    break;
                }
                let entry: PlayerPlanetEntry = world.read_model((player, i));
                result.append(entry.planet_id);
                i += 1;
            };
            result
        }

        fn get_planet_buildings(self: @ContractState, planet_id: felt252) -> Array<Building> {
            let world = self.world(@DEFAULT_NS());
            _read_buildings(@world, planet_id)
        }

        fn get_invader(self: @ContractState, planet_id: felt252) -> Invader {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }

        fn get_gear(self: @ContractState, planet_id: felt252) -> Gear {
            let world = self.world(@DEFAULT_NS());
            world.read_model(planet_id)
        }
    }

    fn _read_buildings(world: @WorldStorage, planet_id: felt252) -> Array<Building> {
        let bcount: PlanetBuildingCount = world.read_model(planet_id);
        let mut result: Array<Building> = array![];
        let mut i: u32 = 0;
        loop {
            if i >= bcount.count {
                break;
            }
            let entry: PlanetBuildingEntry = world.read_model((planet_id, i));
            let building: Building = world.read_model((planet_id, entry.lon, entry.lat));
            result.append(building);
            i += 1;
        };
        result
    }
}
