// SPDX-License-Identifier: MIT

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Colony {
    #[key]
    pub planet_id: u64,
    pub col: u32,
    pub row: u32,
    pub founded: bool,
    pub food: u32,
    pub minerals: u32,
    /// Accumulated construction labor (building% allocation × time).
    pub build_points: u32,
    pub defense: u32,
    pub fertility: u8,
    pub mineral_richness: u8,
    /// Building counts (for display/UI).
    pub farms: u8,
    pub mines: u8,
    pub barracks: u8,
    pub workshops: u8,
    /// Aggregate per-epoch output from all placed buildings (terrain-adjusted).
    /// Updated whenever a building is constructed.
    /// assign_orders multiplies these by elapsed epochs each turn.
    pub farm_output: u32,
    pub mine_output: u32,
    pub barracks_output: u32,
    pub workshop_output: u32,
}
