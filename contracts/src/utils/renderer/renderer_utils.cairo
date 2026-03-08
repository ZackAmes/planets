// SPDX-License-Identifier: MIT

use planets::models::planet::Planet;
use planets::models::building::Building;
use planets::utils::renderer::encoding::{U256BytesUsedTraitImpl, bytes_base64_encode};
use planets::libs::terrain::terrain_at;
use game_components_interfaces::GameDetail;
use graffiti::json::JsonImpl;

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

pub fn create_metadata(
    planet_id: felt252, planet: Planet, planet_name: felt252, buildings: Span<Building>,
) -> ByteArray {
    let pop = planet.population;
    let seed_val = planet.seed;

    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id, buildings);
    let base64_image = format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg));

    let _id = format!("{}", planet_id);
    let _pop = format!("{}", pop);
    let _seed = format!("{}", seed_val);
    let _name = _felt_to_ba(planet_name);

    let mut metadata = JsonImpl::new()
        .add("name", "Planet #" + _id.clone())
        .add("description", "An onchain colony builder planet.")
        .add("image", base64_image);

    let name_attr: ByteArray = JsonImpl::new()
        .add("trait", "Name")
        .add("value", _name)
        .build();
    let pop_attr: ByteArray = JsonImpl::new()
        .add("trait", "Population")
        .add("value", _pop)
        .build();
    let seed_attr: ByteArray = JsonImpl::new()
        .add("trait", "Seed")
        .add("value", _seed)
        .build();
    let attributes = array![name_attr, pop_attr, seed_attr].span();

    let metadata = metadata.add_array("attributes", attributes).build();
    format!("data:application/json;base64,{}", bytes_base64_encode(metadata))
}

pub fn generate_svg(
    planet_id: felt252, planet: Planet, planet_name: felt252, buildings: Span<Building>,
) -> ByteArray {
    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id, buildings);
    format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg))
}

pub fn generate_details(planet: Planet) -> Span<GameDetail> {
    array![
        GameDetail { name: 'Population', value: planet.population.into() },
        GameDetail { name: 'Turns', value: planet.action_count.into() },
        GameDetail { name: 'Seed', value: planet.seed },
    ]
        .span()
}

// ---------------------------------------------------------------------------
// Animated rotating planet SVG
// ---------------------------------------------------------------------------

fn _build_rotating_planet_svg(
    planet: Planet,
    planet_name: felt252,
    planet_id: felt252,
    buildings: Span<Building>,
) -> ByteArray {
    let _name = _felt_to_ba(planet_name);
    let _id = format!("{}", planet_id);
    let _pop = format!("{}", planet.population);
    let _turns = format!("{}", planet.action_count);

    let strips = _build_terrain_grid(planet.seed);
    let building_markers = _build_building_markers(buildings);
    let stars = _build_starfield();

    "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600'>"
        + "<defs>"
        + "<clipPath id='pc'><circle cx='300' cy='300' r='255'/></clipPath>"
        + "<radialGradient id='lit' cx='35%' cy='28%' r='65%'>"
        + "<stop offset='0%' stop-color='#fff' stop-opacity='0.38'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0'/>"
        + "</radialGradient>"
        + "<radialGradient id='shad' cx='78%' cy='78%' r='55%'>"
        + "<stop offset='30%' stop-color='#000' stop-opacity='0'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0.82'/>"
        + "</radialGradient>"
        + "</defs>"
        + "<rect width='600' height='600' fill='#050510'/>"
        + stars
        + "<g clip-path='url(#pc)'>"
        // Scrolling terrain + building markers share the same animating group
        + "<g>"
        + "<animateTransform attributeName='transform' type='translate' "
        + "from='0,0' to='-600,0' dur='20s' repeatCount='indefinite'/>"
        + strips
        + building_markers
        + "</g>"
        // Polar ice-cap overlays
        + "<ellipse cx='300' cy='55' rx='255' ry='65' fill='#e4eff4' opacity='0.78'/>"
        + "<ellipse cx='300' cy='545' rx='255' ry='65' fill='#e4eff4' opacity='0.78'/>"
        + "</g>"
        // Atmosphere glow rings (outside clip path)
        + "<circle cx='300' cy='300' r='258' fill='none' stroke='#6ab4ff' stroke-width='3' opacity='0.22'/>"
        + "<circle cx='300' cy='300' r='264' fill='none' stroke='#3a7ab8' stroke-width='2' opacity='0.12'/>"
        + "<circle cx='300' cy='300' r='272' fill='none' stroke='#2a5a90' stroke-width='1.5' opacity='0.06'/>"
        + "<circle cx='300' cy='300' r='255' fill='url(#lit)'/>"
        + "<circle cx='300' cy='300' r='255' fill='url(#shad)'/>"
        + "<text x='300' y='578' text-anchor='middle' fill='#6ab4ff' "
        + "font-size='18' font-family='monospace' letter-spacing='2'>"
        + _name
        + "</text>"
        + "<text x='300' y='594' text-anchor='middle' fill='#33506a' "
        + "font-size='11' font-family='monospace'>pop "
        + _pop
        + "  |  turn "
        + _turns
        + "</text>"
        + "<text x='300' y='22' text-anchor='middle' fill='#3a5570' "
        + "font-size='12' font-family='monospace' letter-spacing='1'>PLANET #"
        + _id
        + "</text>"
        + "</svg>"
}

// ---------------------------------------------------------------------------
// Star field — hardcoded positions scattered outside the planet circle
// (cx=300, cy=300, r=255). Stars inside the circle are hidden by terrain.
// ---------------------------------------------------------------------------

fn _build_starfield() -> ByteArray {
    "<circle cx='42' cy='87' r='1.2' fill='#ffffff' opacity='0.65'/>"
        + "<circle cx='118' cy='28' r='0.8' fill='#ffffff' opacity='0.5'/>"
        + "<circle cx='175' cy='14' r='1.5' fill='#ffffff' opacity='0.7'/>"
        + "<circle cx='260' cy='5' r='0.9' fill='#ffffff' opacity='0.45'/>"
        + "<circle cx='395' cy='9' r='1.1' fill='#ffffff' opacity='0.6'/>"
        + "<circle cx='468' cy='22' r='0.8' fill='#ffffff' opacity='0.55'/>"
        + "<circle cx='540' cy='12' r='1.4' fill='#ffffff' opacity='0.68'/>"
        + "<circle cx='587' cy='68' r='1.0' fill='#ffffff' opacity='0.5'/>"
        + "<circle cx='594' cy='185' r='0.9' fill='#ffffff' opacity='0.6'/>"
        + "<circle cx='591' cy='328' r='1.2' fill='#ffffff' opacity='0.45'/>"
        + "<circle cx='588' cy='445' r='0.8' fill='#ffffff' opacity='0.55'/>"
        + "<circle cx='572' cy='538' r='1.3' fill='#ffffff' opacity='0.65'/>"
        + "<circle cx='490' cy='578' r='0.9' fill='#ffffff' opacity='0.5'/>"
        + "<circle cx='365' cy='590' r='1.0' fill='#ffffff' opacity='0.6'/>"
        + "<circle cx='220' cy='585' r='0.8' fill='#ffffff' opacity='0.45'/>"
        + "<circle cx='98' cy='568' r='1.1' fill='#ffffff' opacity='0.55'/>"
        + "<circle cx='22' cy='512' r='0.9' fill='#ffffff' opacity='0.65'/>"
        + "<circle cx='8' cy='385' r='1.3' fill='#ffffff' opacity='0.5'/>"
        + "<circle cx='12' cy='245' r='0.8' fill='#ffffff' opacity='0.6'/>"
        + "<circle cx='28' cy='145' r='1.0' fill='#ffffff' opacity='0.55'/>"
        + "<circle cx='78' cy='200' r='0.7' fill='#c8d8ff' opacity='0.4'/>"
        + "<circle cx='510' cy='155' r='0.7' fill='#c8d8ff' opacity='0.4'/>"
        + "<circle cx='85' cy='430' r='0.7' fill='#c8d8ff' opacity='0.35'/>"
        + "<circle cx='508' cy='470' r='0.9' fill='#c8d8ff' opacity='0.4'/>"
}

// ---------------------------------------------------------------------------
// Building markers
//
// Each building is rendered as a small labelled circle at its terrain
// position, duplicated at x+600 so it loops with the 12-second scroll.
//
// Coordinate mapping (600px canvas):
//   x = lon / 6    (lon 0-3599 → x 0-599)
//   y = lat / 3    (lat 0-1799 → y 0-599)
// ---------------------------------------------------------------------------

fn _build_building_markers(buildings: Span<Building>) -> ByteArray {
    let mut result: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= buildings.len() {
            break;
        }
        let b = buildings.at(i);
        let lon: u16 = *b.lon;
        let lat: u16 = *b.lat;
        let bt: u8 = *b.building_type;

        let x: u32 = lon.into() / 6_u32;
        let y: u32 = lat.into() / 3_u32;
        let x2: u32 = x + 600;

        let xs = format!("{}", x);
        let ys = format!("{}", y);
        let x2s = format!("{}", x2);

        let (fill, letter): (ByteArray, ByteArray) = if bt == 0 {
            ("#ffdd44", "T") // TownCenter — gold
        } else if bt == 1 {
            ("#44aaff", "W") // WaterWell — blue
        } else if bt == 2 {
            ("#aaaaaa", "I") // IronMine — gray
        } else if bt == 3 {
            ("#44ff88", "H") // House — green
        } else if bt == 4 {
            ("#4466ff", "B") // Barracks — dark-blue
        } else if bt == 5 {
            ("#bb44ff", "U") // UraniumMine — purple
        } else {
            ("#ffffff", "S") // Spaceport — white
        };

        let dot = "<circle r='9' fill='#000' opacity='0.35'/>"
            + "<circle r='7' fill='"
            + fill.clone()
            + "' stroke='#fff' stroke-width='0.8' opacity='0.95'/>"
            + "<text dy='0.38em' text-anchor='middle' fill='#fff' "
            + "font-size='6' font-weight='bold' font-family='monospace'>"
            + letter.clone()
            + "</text>";

        result += "<g transform='translate("
            + xs.clone()
            + ","
            + ys.clone()
            + ")'>"
            + dot.clone()
            + "</g>"
            + "<g transform='translate("
            + x2s
            + ","
            + ys
            + ")'>"
            + dot
            + "</g>";

        i += 1;
    };
    result
}

// ---------------------------------------------------------------------------
// Terrain grid generation
//
// Renders a 20-column x 10-row grid of terrain cells, each 30x60 px.
// The grid is duplicated (columns rendered at x and x+600) so the
// animateTransform scroll from 0 to -600 loops seamlessly.
//
// We keep 20x10 visually (400 rects) to keep the SVG compact, but sample
// via terrain_at() so the colors match the authoritative 80x40 game grid.
// ---------------------------------------------------------------------------

fn _build_terrain_grid(seed: felt252) -> ByteArray {
    let mut result: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= 200 {
            break;
        }
        let col: u32 = i / 10;
        let row: u32 = i % 10;

        let x: u32 = col * 30;
        let y: u32 = row * 60;
        let x2: u32 = x + 600;

        // Sample at center of this SVG cell — terrain_at uses the 80x40 game grid internally
        let lon: u16 = (col * 180 + 90).try_into().unwrap_or(0);
        let lat: u16 = (row * 180 + 90).try_into().unwrap_or(0);
        let terrain_type = terrain_at(seed, lon, lat);
        let color = _terrain_color(terrain_type);

        let xs = format!("{}", x);
        let ys = format!("{}", y);
        let x2s = format!("{}", x2);

        result += "<rect x='"
            + xs
            + "' y='"
            + ys.clone()
            + "' width='30' height='60' fill='"
            + color.clone()
            + "'/>";
        result += "<rect x='"
            + x2s
            + "' y='"
            + ys
            + "' width='30' height='60' fill='"
            + color
            + "'/>";

        i += 1;
    };
    result
}

fn _terrain_color(idx: u32) -> ByteArray {
    match idx {
        0 => "#0d3d5c", // deep ocean
        1 => "#1a6b8a", // shallow ocean
        2 => "#3d7a2a", // grassland
        3 => "#163d12", // forest
        4 => "#c47d15", // desert
        5 => "#6b5a48", // highland
        6 => "#4a3a2c", // mountain
        7 => "#e8f2f5", // snow
        8 => "#c4a85c", // beach
        _ => "#7a6840", // scrubland (idx 9)
    }
}

fn _felt_to_ba(name: felt252) -> ByteArray {
    let mut out: ByteArray = Default::default();
    if name != 0 {
        out.append_word(name, U256BytesUsedTraitImpl::bytes_used(name.into()).into());
    }
    out
}
