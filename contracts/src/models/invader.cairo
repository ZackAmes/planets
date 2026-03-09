// SPDX-License-Identifier: MIT

/// A spawned invader army threatening the colony.
/// Only one invader can be active per planet at a time.
/// strength: total combat power of the invader force.
/// lon/lat: where the invaders landed (near the colony).
/// epochs_until_attack: countdown timer (starts at 3, attacks at 0)
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Invader {
    #[key]
    pub planet_id: felt252,
    pub active: bool,
    pub strength: u32,
    pub lon: u16,
    pub lat: u16,
    pub spawned_at: u64,
    pub epochs_until_attack: u8,
}
