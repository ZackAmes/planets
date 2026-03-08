// SPDX-License-Identifier: MIT

use starknet::ContractAddress;

/// Tracks how many planets a player has spawned.
/// Used together with PlayerPlanetEntry to enumerate player→planet_id.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlayerPlanets {
    #[key]
    pub player: ContractAddress,
    pub count: u32,
}

/// One entry in the player's planet list.
/// planet_id at position `index` for `player`.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlayerPlanetEntry {
    #[key]
    pub player: ContractAddress,
    #[key]
    pub index: u32,
    pub planet_id: felt252,
}
