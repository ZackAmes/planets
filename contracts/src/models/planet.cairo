// SPDX-License-Identifier: MIT

use starknet::ContractAddress;

#[derive(Introspect, Drop, Serde, Copy)]
pub enum TerrainType {
    Ocean,
    Shallow,
    Beach,
    Grassland,
    Farmland,
    Forest,
    Highland,
    Mountain,
    Snow,
    Desert,
    Scrubland,
}

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Planet {
    #[key]
    pub planet_id: felt252,
    pub owner: ContractAddress,
    pub seed: felt252,
    pub width: u32,
    pub height: u32,
    pub name: felt252,
    pub spawned_at: u64,
    /// Timestamp of the last assign_orders call.
    /// Production is proportional to (current_time - last_action_at).
    pub last_action_at: u64,
    pub population: u32,
    pub action_count: u32,
}
