// SPDX-License-Identifier: BUSL-1.1

use death_mountain::models::adventurer::adventurer::{Adventurer};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IAdventurerSystems<T> {
    fn get_adventurer(self: @T, adventurer_id: u64) -> Adventurer;
    fn get_adventurer_dungeon(self: @T, adventurer_id: u64) -> ContractAddress;
    fn get_adventurer_name(self: @T, adventurer_id: u64) -> felt252;
}

#[dojo::contract]
mod adventurer_systems {
    use death_mountain::constants::world::DEFAULT_NS;
    use death_mountain::models::adventurer::adventurer::{Adventurer, ImplAdventurer};
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use death_mountain::systems::game_token::contracts::{IGameTokenSystemsDispatcher, IGameTokenSystemsDispatcherTrait};

    use game_components_minigame::interface::{IMinigameDispatcher, IMinigameDispatcherTrait};
    use game_components_token::core::interface::{IMinigameTokenDispatcher, IMinigameTokenDispatcherTrait};
    use game_components_token::extensions::minter::interface::{
        IMinigameTokenMinterDispatcher, IMinigameTokenMinterDispatcherTrait,
    };
    use starknet::ContractAddress;

    use super::{IAdventurerSystems};

    #[abi(embed_v0)]
    impl AdventurerSystemsImpl of IAdventurerSystems<ContractState> {

        fn get_adventurer(self: @ContractState, adventurer_id: u64) -> Adventurer {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let adventurer: Adventurer = world.read_model(adventurer_id);
            adventurer
        }

        fn get_adventurer_dungeon(self: @ContractState, adventurer_id: u64) -> ContractAddress {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
            let game_token = IMinigameDispatcher { contract_address: game_token_systems_address };
            let token_address = game_token.token_address();
            let token_metadata = IMinigameTokenDispatcher { contract_address: token_address }
                .token_metadata(adventurer_id);
            let minted_by_address = IMinigameTokenMinterDispatcher { contract_address: token_address }
                .get_minter_address(token_metadata.minted_by);
            minted_by_address
        }

        fn get_adventurer_name(self: @ContractState, adventurer_id: u64) -> felt252 {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            _get_adventurer_name(world, adventurer_id)
        }
    }

    fn _get_adventurer_name(world: WorldStorage, adventurer_id: u64) -> felt252 {
        let (game_token_address, _) = world.dns(@"game_token_systems").unwrap();
        let game_token = IGameTokenSystemsDispatcher { contract_address: game_token_address };
        let player_name = game_token.player_name(adventurer_id);
        player_name
    }
}

