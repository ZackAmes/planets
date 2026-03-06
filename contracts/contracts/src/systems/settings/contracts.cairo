// SPDX-License-Identifier: MIT

use death_mountain::models::adventurer::adventurer::Adventurer;
use death_mountain::models::game::{GameSettings};
use starknet::ContractAddress;

#[starknet::interface]
pub trait ISettingsSystems<T> {
    fn add_settings(
        ref self: T,
        name: felt252,
        description: ByteArray,
        adventurer: Adventurer,
        game_seed: u64,
        game_seed_until_xp: u16,
        in_battle: bool,
        base_damage_reduction: u8,
        market_size: u8,
    ) -> u32;
    fn setting_details(self: @T, settings_id: u32) -> GameSettings;
    fn game_settings(self: @T, game_id: u64) -> GameSettings;
    fn settings_count(self: @T) -> u32;
}

#[dojo::contract]
mod settings_systems {
    use death_mountain::constants::world::{DEFAULT_NS, VERSION};
    use death_mountain::libs::settings::generate_settings_array;
    use death_mountain::models::adventurer::adventurer::{Adventurer, ImplAdventurer};
    use death_mountain::models::game::{GameSettings, GameSettingsMetadata, SettingsCounter};
    use death_mountain::utils::renderer::encoding::U256BytesUsedTraitImpl;

    use dojo::model::ModelStorage;
    use dojo::world::{WorldStorage, WorldStorageTrait};
    use game_components_minigame::extensions::settings::interface::{IMinigameSettings, IMinigameSettingsDetails};
    use game_components_minigame::extensions::settings::settings::SettingsComponent;
    use game_components_minigame::extensions::settings::structs::{GameSetting, GameSettingDetails};

    use game_components_minigame::interface::{IMinigameDispatcher, IMinigameDispatcherTrait};

    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use super::ISettingsSystems;

    component!(path: SettingsComponent, storage: settings, event: SettingsEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl SettingsInternalImpl = SettingsComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        settings: SettingsComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SettingsEvent: SettingsComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    fn dojo_init(ref self: ContractState) {
        let mut world: WorldStorage = self.world(@DEFAULT_NS());
        self.settings.initializer();

        let default_settings = GameSettings {
            settings_id: 0,
            adventurer: ImplAdventurer::new(0),
            game_seed: 0,
            game_seed_until_xp: 0,
            in_battle: false,
            base_damage_reduction: 50,
            market_size: 25,
        };

        world.write_model(@default_settings);

        world
            .write_model(
                @GameSettingsMetadata {
                    settings_id: 0,
                    name: 'Default',
                    description: "Default Game Settings",
                    created_by: starknet::get_caller_address(),
                    created_at: starknet::get_block_timestamp(),
                },
            );

        let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
        let minigame_dispatcher = IMinigameDispatcher { contract_address: game_token_systems_address };
        let minigame_token_address = minigame_dispatcher.token_address();

        let settings: Span<GameSetting> = generate_settings_array(default_settings);

        self
            .settings
            .create_settings(
                game_token_systems_address,
                0,
                "Default",
                "These are the default Death Mountain settings",
                settings,
                minigame_token_address,
            );
    }

    #[abi(embed_v0)]
    impl GameSettingsImpl of IMinigameSettings<ContractState> {
        fn settings_exist(self: @ContractState, settings_id: u32) -> bool {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let settings: GameSettings = world.read_model(settings_id);
          //  settings.adventurer.action_count != 0
            true
        }
    }

    #[abi(embed_v0)]
    impl GameSettingsDetailsImpl of IMinigameSettingsDetails<ContractState> {
        fn settings_details(self: @ContractState, settings_id: u32) -> GameSettingDetails {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let settings: GameSettings = world.read_model(settings_id);
            let settings_details: GameSettingsMetadata = world.read_model(settings_id);
            let settings: Span<GameSetting> = generate_settings_array(settings);

            let mut _settings_name = Default::default();
            if settings_details.name != 0 {
                _settings_name
                    .append_word(
                        settings_details.name, U256BytesUsedTraitImpl::bytes_used(settings_details.name.into()).into(),
                    );
            }

            GameSettingDetails { name: _settings_name, description: settings_details.description, settings }
        }
    }

    #[abi(embed_v0)]
    impl SettingsSystemsImpl of ISettingsSystems<ContractState> {
        fn add_settings(
            ref self: ContractState,
            name: felt252,
            description: ByteArray,
            adventurer: Adventurer,
            game_seed: u64,
            game_seed_until_xp: u16,
            in_battle: bool,
            base_damage_reduction: u8,
            market_size: u8,
        ) -> u32 {
            // Validate input parameters
            self._validate_settings(adventurer, game_seed, game_seed_until_xp, base_damage_reduction, market_size);

            let mut world: WorldStorage = self.world(@DEFAULT_NS());
            // increment settings counter
            let mut settings_count: SettingsCounter = world.read_model(VERSION);
            settings_count.count += 1;
            let game_settings = GameSettings {
                settings_id: settings_count.count,
                adventurer,
                game_seed,
                game_seed_until_xp,
                in_battle,
                base_damage_reduction,
                market_size,
            };
            world.write_model(@game_settings);
            world
                .write_model(
                    @GameSettingsMetadata {
                        settings_id: settings_count.count,
                        name,
                        description: description.clone(),
                        created_by: starknet::get_caller_address(),
                        created_at: starknet::get_block_timestamp(),
                    },
                );
            world.write_model(@settings_count);

            let settings: Span<GameSetting> = generate_settings_array(game_settings);

            let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
            let minigame_dispatcher = IMinigameDispatcher { contract_address: game_token_systems_address };
            let minigame_token_address = minigame_dispatcher.token_address();

            let mut _name = Default::default();

            if name != 0 {
                _name.append_word(name, U256BytesUsedTraitImpl::bytes_used(name.into()).into());
            }

            self
                .settings
                .create_settings(
                    game_token_systems_address,
                    settings_count.count,
                    _name,
                    description.clone(),
                    settings,
                    minigame_token_address,
                );

            settings_count.count
        }

        fn setting_details(self: @ContractState, settings_id: u32) -> GameSettings {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let settings: GameSettings = world.read_model(settings_id);
            settings
        }

        fn game_settings(self: @ContractState, game_id: u64) -> GameSettings {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let (game_token_systems_address, _) = world.dns(@"game_token_systems").unwrap();
            let minigame_dispatcher = IMinigameDispatcher { contract_address: game_token_systems_address };
            let minigame_token_address = minigame_dispatcher.token_address();
            let settings_id = self.settings.get_settings_id(game_id, minigame_token_address);
            let game_settings: GameSettings = world.read_model(settings_id);
            game_settings
        }

        fn settings_count(self: @ContractState) -> u32 {
            let world: WorldStorage = self.world(@DEFAULT_NS());
            let settings_count: SettingsCounter = world.read_model(VERSION);
            settings_count.count
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _validate_settings(
            ref self: ContractState,
            adventurer: Adventurer,
            game_seed: u64,
            game_seed_until_xp: u16,
            base_damage_reduction: u8,
            market_size: u8,
        ) {
            // Validate adventurer XP is reasonable
            assert!(adventurer.xp <= 30000, "Adventurer XP cannot exceed 30000");

        }
    }
}
