// SPDX-License-Identifier: BUSL-1.1
#[starknet::interface]
pub trait IGameSystems<T> {
    // ------ Game Actions ------
    fn start_game(ref self: T, adventurer_id: u64, weapon: u8);
    fn explore(ref self: T, adventurer_id: u64);

}


#[dojo::contract]
mod game_systems {
    use death_mountain::constants::world::DEFAULT_NS;
    use death_mountain::libs::game::{GameLibs, ImplGameLibs};
    use death_mountain::models::adventurer::adventurer::{Adventurer};
    use death_mountain::systems::adventurer::contracts::IAdventurerSystemsDispatcherTrait;
    use death_mountain::systems::settings::contracts::{ISettingsSystemsDispatcher, ISettingsSystemsDispatcherTrait};
    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_minigame::interface::{IMinigameDispatcher, IMinigameDispatcherTrait};
    use game_components_minigame::libs::{assert_token_ownership, post_action, pre_action};
    use starknet::{ContractAddress, get_tx_info};

    // ------------------------------------------ //
    // ------------ Helper Functions ------------ //
    // ------------------------------------------ //

    fn _init_game_context(world: WorldStorage) -> GameLibs {
        ImplGameLibs::new(world)
    }


    // ------------------------------------------ //
    // ------------ Impl ------------------------ //
    // ------------------------------------------ //
    #[abi(embed_v0)]
    impl GameSystemsImpl of super::IGameSystems<ContractState> {
        fn start_game(ref self: ContractState, adventurer_id: u64, weapon: u8) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());

            let token_address = _get_token_address(world);
            assert_token_ownership(token_address, adventurer_id);
            pre_action(token_address, adventurer_id);

            _assert_game_not_started(world, adventurer_id);

            let game_libs = ImplGameLibs::new(world);

            let mut adventurer = game_libs.adventurer.get_adventurer(adventurer_id);
            adventurer.xp += 5;
            adventurer.action_count += 1;
            world.write_model(@adventurer);

            post_action(token_address, adventurer_id)
        }

        fn explore(ref self: ContractState, adventurer_id: u64) {
            let mut world: WorldStorage = self.world(@DEFAULT_NS());

            let token_address = _get_token_address(world);
            assert_token_ownership(token_address, adventurer_id);
            pre_action(token_address, adventurer_id);

            let game_libs = _init_game_context(world);
            let mut adventurer = game_libs.adventurer.get_adventurer(adventurer_id);
            adventurer.xp += 10;
            adventurer.action_count += 1;
            world.write_model(@adventurer);

            post_action(token_address, adventurer_id);
        }
    }
    // ------------------------------------------ //
    // ------------ Helper Functions ------------ //
    // ------------------------------------------ //

    fn _get_token_address(world: WorldStorage) -> ContractAddress {
        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher { contract_address: game_token_systems_address };
        minigame_dispatcher.token_address()
    }

    fn _assert_game_not_started(world: WorldStorage, adventurer_id: u64) {
        let game_libs = ImplGameLibs::new(world);
        let adventurer = game_libs.adventurer.get_adventurer(adventurer_id);
        assert!(
            adventurer.xp == 0 && adventurer.action_count == 0,
            "Death Mountain: Adventurer {} has already started",
            adventurer_id,
        );
    }

}
