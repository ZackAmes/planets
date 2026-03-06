// SPDX-License-Identifier: MIT

#[starknet::interface]
pub trait IGameTokenSystems<T> {
    fn player_name(self: @T, planet_id: u64) -> felt252;
}

#[dojo::contract]
mod game_token_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_minigame::interface::{IMinigameDetails, IMinigameTokenData};
    use game_components_minigame::minigame::MinigameComponent;
    use game_components_minigame::structs::GameDetail;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;

    component!(path: MinigameComponent, storage: minigame, event: MinigameEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl MinigameImpl = MinigameComponent::MinigameImpl<ContractState>;
    impl MinigameInternalImpl = MinigameComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        minigame: MinigameComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        MinigameEvent: MinigameComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    fn dojo_init(
        ref self: ContractState,
        creator_address: ContractAddress,
        denshokan_address: ContractAddress,
        renderer_address: Option<ContractAddress>,
    ) {
        self
            .minigame
            .initializer(
                creator_address,
                "Starnet Planets",
                "An onchain colony builder. Land on a planet and survive.",
                "Presorts Games",
                "Presorts Games",
                "Strategy",
                "",
                Option::None,
                Option::None,
                renderer_address,
                Option::None,
                Option::None,
                denshokan_address,
            );
    }

    // ------------------------------------------------------------------
    // IMinigameTokenData — exposes game state to the token/registry system
    // ------------------------------------------------------------------
    #[abi(embed_v0)]
    impl GameTokenDataImpl of IMinigameTokenData<ContractState> {
        fn score(self: @ContractState, token_id: u64) -> u32 {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            planet.population
        }

        fn game_over(self: @ContractState, token_id: u64) -> bool {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            planet.action_count > 0 && planet.population == 0
        }
    }

    // ------------------------------------------------------------------
    // IMinigameDetails — renderer details
    // ------------------------------------------------------------------
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
                        planets::utils::renderer::encoding::U256BytesUsedTraitImpl::bytes_used(
                            planet.name.into(),
                        )
                            .into(),
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
            let pop = format!("{}", planet.population);
            let turns = format!("{}", planet.action_count);
            array![
                GameDetail { name: "Population", value: pop },
                GameDetail { name: "Turns", value: turns },
            ]
                .span()
        }
    }

    // ------------------------------------------------------------------
    // IGameTokenSystems — extra game queries
    // ------------------------------------------------------------------
    #[abi(embed_v0)]
    impl GameTokenSystemsImpl of super::IGameTokenSystems<ContractState> {
        fn player_name(self: @ContractState, planet_id: u64) -> felt252 {
            self.minigame.get_player_name(planet_id)
        }
    }
}
