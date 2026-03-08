// SPDX-License-Identifier: MIT

/// Colony resource stockpiles.
/// Only written during collect / tick or when resources are spent.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Resources {
    #[key]
    pub planet_id: felt252,
    pub water: u32,
    pub iron: u32,
    pub defense: u32,
    pub uranium: u32,
    /// Timestamp of the last tick (aligned to epoch boundaries).
    pub last_updated_at: u64,
    /// Timestamp of the last threat probability roll.
    pub last_threat_at: u64,
}
