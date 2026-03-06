// SPDX-License-Identifier: MIT

use death_mountain::models::adventurer::adventurer::Adventurer;
use starknet::ContractAddress;

// ------------------------------------------ //
// ------------ Models ---------------------- //
// ------------------------------------------ //
#[derive(IntrospectPacked, Copy, Drop, Serde)]
#[dojo::model]
pub struct AdventurerPacked {
    #[key]
    pub adventurer_id: u64,
    pub packed: felt252,
}

#[derive(IntrospectPacked, Copy, Drop, Serde)]
#[dojo::model]
pub struct BagPacked {
    #[key]
    pub adventurer_id: u64,
    pub packed: felt252,
}

#[derive(IntrospectPacked, Copy, Drop, Serde)]
#[dojo::model]
pub struct AdventurerEntropy {
    #[key]
    pub adventurer_id: u64,
    pub market_seed: u64,
    pub beast_seed: u64,
}

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct GameSettingsMetadata {
    #[key]
    pub settings_id: u32,
    pub name: felt252,
    pub description: ByteArray,
    pub created_by: ContractAddress,
    pub created_at: u64,
}

#[derive(Introspect, Copy, Drop, Serde)]
#[dojo::model]
pub struct GameSettings {
    #[key]
    pub settings_id: u32,
    pub adventurer: Adventurer,
    pub game_seed: u64,
    pub game_seed_until_xp: u16,
    pub in_battle: bool,
    pub base_damage_reduction: u8,
    pub market_size: u8,
}

#[derive(IntrospectPacked, Copy, Drop, Serde)]
#[dojo::model]
pub struct SettingsCounter {
    #[key]
    pub id: felt252,
    pub count: u32,
}
