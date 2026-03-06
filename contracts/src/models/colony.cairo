// SPDX-License-Identifier: MIT

/// On-chain colony state. One colony per planet (for now).
/// Terrain bonuses (fertility, mineral_richness) are derived from the planet
/// seed and the chosen location via Poseidon hash so they are deterministic
/// but unpredictable at founding time.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Colony {
    #[key]
    pub planet_id: u64,
    /// Grid coordinates on the planet (matches client hex grid).
    pub col: u32,
    pub row: u32,
    /// Has the colony been placed?
    pub founded: bool,
    /// Stored food (consumed each turn, produced by farmers).
    pub food: u32,
    /// Stored minerals (produced by miners).
    pub minerals: u32,
    /// Accumulated construction progress.
    pub buildings: u32,
    /// Current defense rating (reduces enemy casualties).
    pub defense: u32,
    /// Soil fertility 0-100 — scales food production.
    pub fertility: u8,
    /// Ore density 0-100 — scales mineral production.
    pub mineral_richness: u8,
}
