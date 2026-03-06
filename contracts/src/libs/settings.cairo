// SPDX-License-Identifier: MIT

use game_components_interfaces::GameSetting;

pub fn generate_settings_array() -> Span<GameSetting> {
    array![
        GameSetting { name: 'Width', value: 50 },
        GameSetting { name: 'Height', value: 40 },
        GameSetting { name: 'Pop', value: 100 },
    ]
        .span()
}
