// SPDX-License-Identifier: MIT

use game_components_interfaces::GameDetail;

#[starknet::interface]
pub trait IRendererSystems<T> {
    fn create_metadata(self: @T, planet_id: u64) -> ByteArray;
    fn generate_svg(self: @T, planet_id: u64) -> ByteArray;
    fn generate_details(self: @T, planet_id: u64) -> Span<GameDetail>;
}

#[dojo::contract]
mod renderer_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::utils::renderer::encoding::U256BytesUsedTraitImpl;
    use planets::utils::renderer::renderer_utils::{create_metadata, generate_svg};
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorageTrait;
    use game_components_interfaces::{GameDetail, IMinigameDetails, IMinigameDetailsSVG};
    use super::IRendererSystems;

    #[abi(embed_v0)]
    impl GameDetailsImpl of IMinigameDetails<ContractState> {
        fn token_name(self: @ContractState, token_id: felt252) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet_id: u64 = token_id.try_into().unwrap_or(0);
            let planet: Planet = world.read_model(planet_id);
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
            let planet_id: u64 = token_id.try_into().unwrap_or(0);
            let planet: Planet = world.read_model(planet_id);
            array![
                GameDetail { name: 'Population', value: planet.population.into() },
                GameDetail { name: 'Turns', value: planet.action_count.into() },
                GameDetail { name: 'Seed', value: planet.seed },
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
            let planet_id: u64 = token_id.try_into().unwrap_or(0);
            let planet: Planet = world.read_model(planet_id);
            let planet_name = planet.name;
            generate_svg(planet_id, planet, planet_name)
        }
    }

    #[abi(embed_v0)]
    impl RendererSystemsImpl of IRendererSystems<ContractState> {
        fn create_metadata(self: @ContractState, planet_id: u64) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let planet_name = planet.name;
            create_metadata(planet_id, planet, planet_name)
        }

        fn generate_svg(self: @ContractState, planet_id: u64) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            let planet_name = planet.name;
            generate_svg(planet_id, planet, planet_name)
        }

        fn generate_details(self: @ContractState, planet_id: u64) -> Span<GameDetail> {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(planet_id);
            array![
                GameDetail { name: 'Population', value: planet.population.into() },
                GameDetail { name: 'Turns', value: planet.action_count.into() },
                GameDetail { name: 'Seed', value: planet.seed },
            ]
                .span()
        }
    }
}
