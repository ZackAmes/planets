// SPDX-License-Identifier: MIT

use starknet::ContractAddress;

/// Terrain region types — stored on-chain for reference; the full tile map
/// is derived client-side from `Planet.seed` via simplex noise.
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
    pub planet_id: u64,
    pub owner: ContractAddress,
    /// VRF-derived seed used by the client noise generator.
    /// The same seed always produces the same planet map.
    pub seed: felt252,
    pub width: u32,
    pub height: u32,
    pub name: felt252,
    pub spawned_at: u64,
    /// Starting colonist population.
    pub population: u32,
    /// Number of allocation turns taken so far.
    pub action_count: u32,
}
