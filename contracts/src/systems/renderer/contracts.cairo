// SPDX-License-Identifier: MIT

use game_components_interfaces::GameDetail;

#[starknet::interface]
pub trait IRendererSystems<T> {
    fn create_metadata(self: @T, planet_id: felt252) -> ByteArray;
    fn generate_svg(self: @T, planet_id: felt252) -> ByteArray;
    fn generate_details(self: @T, planet_id: felt252) -> Span<GameDetail>;
}

#[dojo::contract]
mod renderer_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::building::{Building, PlanetBuildingCount, PlanetBuildingEntry};
    use planets::models::colony::Colony;
    use planets::models::resources::Resources;
    use planets::models::invader::Invader;
    use planets::utils::renderer::encoding::U256BytesUsedTraitImpl;
    use planets::utils::renderer::renderer_utils::{create_metadata, generate_svg};
    use dojo::world::WorldStorage;
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorageTrait;
    use game_components_interfaces::{GameDetail, IMinigameDetails, IMinigameDetailsSVG};
    use super::IRendererSystems;

    #[abi(embed_v0)]
    impl GameDetailsImpl of IMinigameDetails<ContractState> {
        fn token_name(self: @ContractState, token_id: felt252) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            let mut name: ByteArray = Default::default();
            if planet.name != 0 {
                name
                    .append_word(
                        planet.name,
                        U256BytesUsedTraitImpl::bytes_used(planet.name.into()).into(),
                    );
            }
            name
        }

        fn token_description(self: @ContractState, token_id: felt252) -> ByteArray {
            format!("An onchain colony - planet #{}", token_id)
        }

        fn game_details(self: @ContractState, token_id: felt252) -> Span<GameDetail> {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            let colony: Colony = world.read_model(token_id);
            let resources: Resources = world.read_model(token_id);
            let tc_u32: u32 = colony.tc_level.into();
            array![
                GameDetail { name: 'Population', value: planet.population.into() },
                GameDetail { name: 'Pop Cap', value: (tc_u32 * 10_u32).into() },
                GameDetail { name: 'TC Level', value: colony.tc_level.into() },
                GameDetail { name: 'Water', value: resources.water.into() },
                GameDetail { name: 'Iron', value: resources.iron.into() },
                GameDetail { name: 'Defense', value: resources.defense.into() },
                GameDetail { name: 'Uranium', value: resources.uranium.into() },
                GameDetail { name: 'Age (epochs)', value: ((resources.last_updated_at - colony.founded_at) / 120).into() },
            ]
                .span()
        }

        fn token_name_batch(self: @ContractState, token_ids: Span<felt252>) -> Array<ByteArray> {
            let mut results = array![];
            let mut i: u32 = 0;
            loop {
                if i >= token_ids.len() {
                    break;
                }
                results.append(self.token_name(*token_ids.at(i)));
                i += 1;
            };
            results
        }

        fn token_description_batch(
            self: @ContractState, token_ids: Span<felt252>,
        ) -> Array<ByteArray> {
            let mut results = array![];
            let mut i: u32 = 0;
            loop {
                if i >= token_ids.len() {
                    break;
                }
                results.append(self.token_description(*token_ids.at(i)));
                i += 1;
            };
            results
        }

        fn game_details_batch(
            self: @ContractState, token_ids: Span<felt252>,
        ) -> Array<Span<GameDetail>> {
            let mut results = array![];
            let mut i: u32 = 0;
            loop {
                if i >= token_ids.len() {
                    break;
                }
                results.append(self.game_details(*token_ids.at(i)));
                i += 1;
            };
            results
        }
    }

    #[abi(embed_v0)]
    impl GameDetailsSVGImpl of IMinigameDetailsSVG<ContractState> {
        fn game_details_svg(self: @ContractState, token_id: felt252) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            let planet_name = planet.name;
            let buildings = _read_buildings(@world, token_id);
            let colony: Colony = world.read_model(token_id);
            let resources: Resources = world.read_model(token_id);
            let invader: Invader = world.read_model(token_id);
            generate_svg(token_id, planet, planet_name, buildings.span(), colony, resources, invader)
        }
    }

    #[abi(embed_v0)]
    impl RendererSystemsImpl of IRendererSystems<ContractState> {
        fn create_metadata(self: @ContractState, planet_id: felt252) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let planet_name = planet.name;
            let buildings = _read_buildings(@world, planet_id);
            let colony: Colony = world.read_model(planet_id);
            let resources: Resources = world.read_model(planet_id);
            let invader: Invader = world.read_model(planet_id);
            create_metadata(
                planet_id, planet, planet_name, buildings.span(), colony, resources, invader,
            )
        }

        fn generate_svg(self: @ContractState, planet_id: felt252) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let planet_name = planet.name;
            let buildings = _read_buildings(@world, planet_id);
            let colony: Colony = world.read_model(planet_id);
            let resources: Resources = world.read_model(planet_id);
            let invader: Invader = world.read_model(planet_id);
            generate_svg(
                planet_id, planet, planet_name, buildings.span(), colony, resources, invader,
            )
        }

        fn generate_details(self: @ContractState, planet_id: felt252) -> Span<GameDetail> {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let colony: Colony = world.read_model(planet_id);
            let resources: Resources = world.read_model(planet_id);
            let tc_u32: u32 = colony.tc_level.into();
            array![
                GameDetail { name: 'Population', value: planet.population.into() },
                GameDetail { name: 'Pop Cap', value: (tc_u32 * 10_u32).into() },
                GameDetail { name: 'TC Level', value: colony.tc_level.into() },
                GameDetail { name: 'Water', value: resources.water.into() },
                GameDetail { name: 'Iron', value: resources.iron.into() },
                GameDetail { name: 'Defense', value: resources.defense.into() },
                GameDetail { name: 'Uranium', value: resources.uranium.into() },
                GameDetail { name: 'Age (epochs)', value: ((resources.last_updated_at - colony.founded_at) / 120).into() },
            ]
                .span()
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
