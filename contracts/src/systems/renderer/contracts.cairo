// SPDX-License-Identifier: MIT

use game_components_minigame::structs::GameDetail;

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
    use planets::utils::renderer::renderer_utils::{create_metadata, generate_details, generate_svg};
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorageTrait;
    use game_components_minigame::interface::{
        IMinigameDetails, IMinigameDetailsSVG, IMinigameDispatcher, IMinigameDispatcherTrait,
    };
    use game_components_minigame::libs::require_owned_token;
    use game_components_minigame::structs::GameDetail;
    use super::IRendererSystems;

    #[abi(embed_v0)]
    impl GameDetailsImpl of IMinigameDetails<ContractState> {
        fn token_name(self: @ContractState, token_id: u64) -> ByteArray {
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

        fn token_description(self: @ContractState, token_id: u64) -> ByteArray {
            format!("An onchain colony - planet #{}", token_id)
        }

        fn game_details(self: @ContractState, token_id: u64) -> Span<GameDetail> {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            generate_details(planet)
        }
    }

    #[abi(embed_v0)]
    impl GameDetailsSVGImpl of IMinigameDetailsSVG<ContractState> {
        fn game_details_svg(self: @ContractState, token_id: u64) -> ByteArray {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            let planet_name = planet.name;
            generate_svg(token_id, planet, planet_name)
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
            generate_details(planet)
        }
    }
}
