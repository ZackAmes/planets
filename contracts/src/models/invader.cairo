// SPDX-License-Identifier: MIT

/// A spawned invader army threatening the colony.
/// Only one invader can be active per planet at a time.
/// strength: total combat power of the invader force.
/// lon/lat: where the invaders landed (near the colony).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Invader {
    #[key]
    pub planet_id: u64,
    pub active: bool,
    pub strength: u32,
    pub lon: u16,
    pub lat: u16,
    pub spawned_at: u64,
}
