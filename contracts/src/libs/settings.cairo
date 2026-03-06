// SPDX-License-Identifier: MIT

use game_components_minigame::extensions::settings::structs::GameSetting;

pub fn generate_settings_array() -> Span<GameSetting> {
    array![
        GameSetting { name: "Width", value: "50" },
        GameSetting { name: "Height", value: "40" },
        GameSetting { name: "Starting Population", value: "100" },
    ]
        .span()
}
