// SPDX-License-Identifier: MIT

/// Crafted gear stockpile for the colony.
/// weapons: number of weapons crafted (each adds +5 combat power per fighter).
/// armor:   number of armor sets crafted (each adds +3 combat power per fighter).
/// Gear is permanent — not consumed on use.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Gear {
    #[key]
    pub planet_id: u64,
    pub weapons: u32,
    pub armor: u32,
}
