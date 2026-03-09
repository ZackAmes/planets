// SPDX-License-Identifier: MIT

#[starknet::interface]
pub trait IGameTokenSystems<T> {
    fn player_name(self: @T, planet_id: felt252) -> felt252;
}

#[dojo::contract]
mod game_token_systems {
    use planets::constants::world::DEFAULT_NS;
    use planets::models::planet::Planet;
    use planets::models::building::{Building, PlanetBuildingCount, PlanetBuildingEntry};
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorageTrait;
    use game_components_embeddable_game_standard::minigame::minigame_component::MinigameComponent;
    use game_components_interfaces::{GameDetail, IMinigameDetails, IMinigameTokenData};
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
        game_creator: ContractAddress,
        minigame_token_address: ContractAddress,
        renderer_address: ContractAddress,
    ) {
        let renderer = if renderer_address == starknet::contract_address_const::<0>() {
            Option::None
        } else {
            Option::Some(renderer_address)
        };

        let world =self.world(@DEFAULT_NS());

        let renderer = world.dns_address(@"renderer_systems");
        

        self
            .minigame
            .initializer(
                game_creator,
                "Planets",
                "An onchain colony builder. Land on a planet and survive.",
                "Presorts",
                "Presorts",
                "Strategy",
                "",
                Option::None, // color
                Option::None, // client_url
                renderer,
                Option::None, // settings_address
                Option::None, // objectives_address
                minigame_token_address,
                Option::None, // royalty_fraction
                Option::None, // skills_address
                1, // version
            );
    }

    // ------------------------------------------------------------------
    // IMinigameTokenData — exposes game state to the token/registry system
    // ------------------------------------------------------------------
    #[abi(embed_v0)]
    impl GameTokenDataImpl of IMinigameTokenData<ContractState> {
        fn score(self: @ContractState, token_id: felt252) -> u64 {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            planet.population.into()
        }

        fn game_over(self: @ContractState, token_id: felt252) -> bool {
            let world = self.world(@DEFAULT_NS());
            let planet: Planet = world.read_model(token_id);
            // Lose: colony wiped out
            if planet.action_count > 0 && planet.population == 0 { return true; }
            // Win: Spaceport (building_type 6) constructed
            let bcount: PlanetBuildingCount = world.read_model(token_id);
            let mut i: u32 = 0;
            let mut found = false;
            loop {
                if i >= bcount.count { break; }
                let entry: PlanetBuildingEntry = world.read_model((token_id, i));
                let b: Building = world.read_model((token_id, entry.lon, entry.lat));
                if b.building_type == 6 { found = true; break; }
                i += 1;
            };
            found
        }

        fn score_batch(self: @ContractState, token_ids: Span<felt252>) -> Array<u64> {
            let mut results = array![];
            let mut i: u32 = 0;
            loop {
                if i >= token_ids.len() {
                    break;
                }
                results.append(self.score(*token_ids.at(i)));
                i += 1;
            };
            results
        }

        fn game_over_batch(self: @ContractState, token_ids: Span<felt252>) -> Array<bool> {
            let mut results = array![];
            let mut i: u32 = 0;
            loop {
                if i >= token_ids.len() {
                    break;
                }
                results.append(self.game_over(*token_ids.at(i)));
                i += 1;
            };
            results
        }
    }

    // ------------------------------------------------------------------
    // IMinigameDetails — renderer details
    // ------------------------------------------------------------------
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
                        planets::utils::renderer::encoding::U256BytesUsedTraitImpl::bytes_used(
                            planet.name.into(),
                        )
                            .into(),
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
            array![
                GameDetail { name: 'Population', value: planet.population.into() },
                GameDetail { name: 'Age (epochs)', value: planet.action_count.into() },
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

    // ------------------------------------------------------------------
    // IGameTokenSystems — extra game queries
    // ------------------------------------------------------------------
    #[abi(embed_v0)]
    impl GameTokenSystemsImpl of super::IGameTokenSystems<ContractState> {
        fn player_name(self: @ContractState, planet_id: felt252) -> felt252 {
            self.minigame.get_player_name(planet_id)
        }
    }
}
