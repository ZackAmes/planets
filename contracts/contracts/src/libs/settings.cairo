use death_mountain::models::game::GameSettings;
use game_components_minigame::extensions::settings::structs::GameSetting;

pub fn generate_settings_array(game_settings: GameSettings) -> Span<GameSetting> {
    // Equipment and bag has been removed
    array![
        GameSetting { name: "Starting XP", value: format!("{}", game_settings.adventurer.xp) },
    ]
        .span()
}
