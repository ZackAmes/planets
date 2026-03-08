// SPDX-License-Identifier: MIT

/// Core colony record.
/// tc_level drives the population cap: max_population = tc_level * 10.
/// Level 1 = 10 colonists, level 5 = 50 colonists.
/// Only written on founding or when the Town Center is upgraded.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Colony {
    #[key]
    pub planet_id: felt252,
    pub col: u32,
    pub row: u32,
    pub founded: bool,
    pub tc_level: u8,
}
