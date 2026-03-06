
#[derive(Introspect, Drop, Copy, Serde)]
#[dojo::model]
pub struct Adventurer {
    #[key]
    pub adventurer_id: u64,
    pub xp: u16, // 15 bits
    pub action_count: u16,
}

#[generate_trait]
/// @title Adventurer Implementation
/// @notice This module provides the implementation for the Adventurer struct.
pub impl ImplAdventurer of IAdventurer {
    /// @notice Creates a new Adventurer struct.
    /// @param starting_item The ID of the starting weapon item.
    /// @return The new Adventurer struct.
    fn new(adventurer_id: u64) -> Adventurer {
        Adventurer {
            adventurer_id,
            xp: 0,
            action_count: 0,
        }
    }
}