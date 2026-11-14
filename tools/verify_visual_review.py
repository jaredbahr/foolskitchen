"""Verify one visual review batch and preserve the existing capture checks."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


# The exact requested screenshot.sh frames. The four special PNGs are verified
# separately because their producers use different metadata contracts.
CAPTURE_FRAMES = {
    "shop": {
        "default": (60,),
        "movement-passing": (60,),
        "street-front": (60,),
        "curb-appeal": (60,),
        "a-frame-sign": (60,),
        "quarter-0": (60,),
        "quarter-1": (60,),
        "quarter-2": (60,),
        "quarter-3": (60,),
        "neighbourhood-street": (60,),
        "inspect-guest": (60,),
        "debug-busy": (60,),
        "owner-kitchen": (60,),
        "mood-waits": (120, 180, 240, 300),
        "people-poses": (60, 240),
        "door-queue": (240,),
        "waiting-bench": (60,),
        "thin-divider": (30,),
        "divider-remove-restroom": (60,),
        "loan-review": (12, 90),
        "milestone-review": (12, 90),
        "records": (30, 90),
        "collections": (240,),
        "catalogue-rustic": (90, 120),
        "catalogue-modern": (90, 120),
        "joined-tables": (12, 90),
        "diner-review": (12, 90),
        "menu": (12,),
        "season-stock": (60,),
        "lease-short": (12,),
        "lease-expand": (12,),
        "staff": (12,),
        "property": (12,),
        "site-card": (12, 30),
        "haggle": (30, 90),
        "first-day-guide": (30,),
        "food-service": (12, 90),
        "icons-review": (12, 60),
        "restaurant-cat": (30, 70, 110),
        "aquarium": (30, 60, 90),
        "health-inspector": (30, 70, 110),
        "owner-picker": (60,),
        "owner-character": (60,),
    },
    "service": {
        "order-counter": (90, 330),
        "report": (60,),
        "blueprint-codes": (30,),
        "report-slowest": (60,),
        "daily-special": (30, 120),
        "profit-review": (60,),
        "demand-report": (60,),
        "staff-activity-report": (60,),
        "business-trend": (60,),
        "business-trend-30": (60,),
        "regulars-review": (12, 90),
        "food-critic": (12, 90),
        "rush-hour": (12, 90),
        "service-event": (60,),
        "paint": (60,),
        "floors-review": (12, 30),
        "seafood-floor": (30,),
        "seafood-menu": (30,),
        "walls-review": (12, 30),
        "weather-sunny": (60,),
        "weather-rain": (60,),
        "patio-sunny": (60,),
        "patio-rain": (60,),
        "restroom-review": (12, 30),
        "hygiene-review": (12, 60),
        "cutaway-review": (30,),
        "day-night-golden": (30,),
        "day-night-closed": (30,),
        "lamps-night": (30,),
        "openings-before": (30,),
        "openings-after": (30,),
        "menu-boards-review": (12, 30),
        "signature-menu": (60,),
        "signature-demand": (60,),
        "jukebox": (12, 40),
        "build-green": (12,),
        "build-red": (12,),
        "build-pinch": (12,),
        "viral": (30, 90),
        "menu-access-preview": (12,),
        "blueprint-looks": (12, 60),
        "menu-access-open": (12,),
        "settings": (12,),
        "shortcuts": (12,),
        "settings-world": (90,),
        "hud-1280": (12, 90),
        "hud-1600": (12, 90),
        "messes-dark": (60,),
        "messes-light": (60,),
    },
}


def verify_inventory(root, batch):
    expected = {
        f"{name}/shot_{frame:04d}.png"
        for name, frames in CAPTURE_FRAMES[batch].items()
        for frame in frames
    }
    for relative in sorted(expected):
        png = root / relative
        size, digest = image_identity(png)
        data = json.loads(png.with_suffix(".json").read_text())
        frame = int(png.stem.removeprefix("shot_"))
        expected_size = (1280, 720) if png.parent.name == "hud-1280" else (1600, 900)
        assert size == expected_size == (data["width"], data["height"]), f"{relative}: wrong dimensions"
        assert data["image_file"] == png.name and data["image_sha256"] == digest, f"{relative}: image identity mismatch"
        assert data["frame"] == frame and data["capture_timing"] == "frame_post_draw", f"{relative}: wrong frame"
        # Some fixture helpers round-trip JSON through Godot, which writes 0.0.
        assert type(data["engine_errors"]) in (int, float) and data["engine_errors"] == 0, f"{relative}: engine errors"
        assert "llvmpipe" in data["video_adapter"].lower(), f"{relative}: unexpected renderer"

    if batch == "shop":
        # The native diner validator checks this crop against its source frame.
        expected.add("diner-review/shot_0090_booth_3x.png")
    else:
        expected.update(verify_native_captures(root))
    actual = {png.relative_to(root).as_posix() for png in root.rglob("*.png")}
    assert actual == expected, f"{batch}: capture inventory mismatch; missing {sorted(expected - actual)}, unexpected {sorted(actual - expected)}"
    print(f"{batch}: verified inventory of {len(expected)} PNGs")


def image_identity(png):
    raw = png.read_bytes()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n" and len(raw) > 1000, f"{png}: missing or invalid PNG"
    return struct.unpack(">II", raw[16:24]), hashlib.sha256(raw).hexdigest()


def verify_native_captures(root):
    title_path = root / "title/title.png"
    size, digest = image_identity(title_path)
    title = json.loads(title_path.with_suffix(".json").read_text())
    assert size == (1600, 900) == (title["width"], title["height"]), "title: wrong dimensions"
    assert title["image_file"] == title_path.name and title["image_sha256"] == digest, "title: image identity mismatch"
    assert title["capture_timing"] == "frame_post_draw" and title["engine_errors"] == 0, "title: invalid capture"

    seated_path = root / "seated-tables/cross_table-lean-0_0.png"
    size, digest = image_identity(seated_path)
    seated = json.loads(seated_path.with_name("table-clearance.json").read_text())
    capture, = seated["captures"]
    assert size == (1200, 850) == (capture["width"], capture["height"]), "seated-tables: wrong dimensions"
    assert capture["image_file"] == seated_path.name and capture["image_sha256"] == digest, "seated-tables: image identity mismatch"
    assert capture["capture_timing"] == "frame_post_draw" and seated["engine_errors"] == 0, "seated-tables: invalid capture"
    assert seated["coverage_complete"] is True, "seated-tables: incomplete native coverage"

    restock_path = root / "restock-warning/restock-warning.png"
    size, _ = image_identity(restock_path)
    restock = json.loads(restock_path.with_suffix(".json").read_text())
    assert size == (1600, 900), "restock-warning: wrong dimensions"
    assert restock["engine_errors"] == 0 and restock["placement_allowed"] is True, "restock-warning: invalid capture"
    assert restock["warning_in_viewport"] is True and restock["warning_amber"] is True, "restock-warning: wrong warning"
    return ["title/title.png", "seated-tables/cross_table-lean-0_0.png", "restock-warning/restock-warning.png"]


def verify_standard_views(root, batch):
    captures = [('default', -1, False, False, 60)] + [(f'quarter-{q}', q, False, False, 60) for q in range(4)]
    captures += [('report', -1, False, False, 60)]
    captures += [('inspect-guest', -1, True, False, 60), ('debug-busy', -1, True, True, 60)]
    captures += [('owner-kitchen', -1, False, False, 60)]
    captures += [('milestone-review', -1, False, False, frame) for frame in (12, 90)]
    captures += [('mood-waits', -1, False, False, frame) for frame in (120, 180, 240, 300)]
    captures += [('menu', -1, False, False, 12)]
    captures += [('staff', -1, False, False, 12)]
    captures += [('paint', -1, False, False, 60)]
    captures += [('build-green', 0, False, False, 12), ('build-red', 0, False, False, 12)]
    captures += [('settings', -1, False, False, 12)]
    captures += [('shortcuts', -1, False, False, 12)]
    captures += [('settings-world', -1, False, False, 90)]
    captures = [capture for capture in captures if capture[0] in CAPTURE_FRAMES[batch]]
    observed_bands = set()
    for name, requested, inspect_guest, debug, frame in captures:
        inspect_owner = name == 'owner-kitchen'
        png = root / name / f'shot_{frame:04d}.png'
        raw = png.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n' and len(raw) > 1000, f'{name}: missing/invalid PNG'
        assert struct.unpack('>II', raw[16:24]) == (1600, 900), f'{name}: wrong PNG dimensions'
        data = json.loads(png.with_suffix('.json').read_text())
        assert data['image_file'] == png.name, f'{name}: metadata names another image'
        assert data['image_sha256'] == hashlib.sha256(raw).hexdigest(), f'{name}: image/metadata digest mismatch'
        expected = 0 if requested == -1 else requested
        assert data['scene'] == 'res://src/world/main.tscn', f'{name}: wrong captured scene'
        assert data['capture_timing'] == 'frame_post_draw', f'{name}: pixels/state were not captured after draw'
        if name == 'milestone-review':
            review = data.get('milestone_review')
            assert isinstance(review, dict) and isinstance(review.get('fixture'), dict) and isinstance(review.get('state'), dict), f'{name}: missing GDScript-validated milestone evidence'
            assert review['state'].get('frame') == frame, f'{name}: milestone evidence frame does not match this image'
        if name == 'shortcuts':
            shortcuts = data.get('shortcuts')
            assert isinstance(shortcuts, dict), 'shortcuts: missing runtime panel evidence'
            assert data.get('requested_shortcuts_visible') is True and shortcuts.get('visible') is True, 'shortcuts: production F1 path did not leave the panel visible'
            assert shortcuts.get('close_button_focused') is True, 'shortcuts: Close did not receive actual focus'
            assert shortcuts.get('input') == {'delivery': 'Viewport.push_input', 'key': 'F1', 'frame': 3}, 'shortcuts: capture was not opened through the actual viewport F1 event'
            assert shortcuts.get('group_headings') == ['Game', 'Owner', 'Build'], 'shortcuts: wrong visible groups/order'
            assert shortcuts.get('row_count') == shortcuts.get('expected_row_count') and shortcuts['row_count'] > 0, 'shortcuts: visible table rows are incomplete'
            assert shortcuts.get('column_count') == 2 and shortcuts.get('two_cell_rows') is True, 'shortcuts: expected key/action two-column rows'
            x, y, width, height = shortcuts['panel_bounds']
            assert width > 0 and height > 0 and x >= 0 and y >= 0 and x + width <= data['width'] and y + height <= data['height'], 'shortcuts: panel card is outside the viewport'
        assert data['requested_quarter'] == requested, f'{name}: wrong requested quarter'
        assert data['actual_quarter'] == expected, f'{name}: wrong actual quarter'
        assert math.isclose(data['yaw_degrees'], 45 + 90 * expected, abs_tol=0.01), f'{name}: wrong rendered yaw'
        assert data['wall_mode'] == 1, f'{name}: not Cutaway'
        assert type(data['engine_errors']) is int and data['engine_errors'] == 0, f'{name}: engine/script errors'
        assert (data['width'], data['height'], data['frame']) == (1600, 900, frame), f'{name}: wrong viewport/frame'
        assert 'llvmpipe' in data['video_adapter'].lower(), f'{name}: not the requested software Mesa adapter'
        assert data['lowered_wall_cells'], f'{name}: no lowered walls'
        assert data['requested_selection'] == ('owner' if inspect_owner else 'guest' if inspect_guest else ''), f'{name}: wrong requested selection'
        assert data['requested_debug_visible'] is debug, f'{name}: wrong requested F3 state'
        menu = name == 'menu'
        assert data['requested_menu_visible'] is menu, f'{name}: wrong requested menu state'
        assert data['menu_visible'] is menu, f'{name}: wrong actual menu visibility'
        staff = name == 'staff'
        assert data['requested_staff_visible'] is staff, f'{name}: wrong requested Staff state'
        assert data['staff']['visible'] is staff, f'{name}: wrong actual Staff visibility'
        build_kind = name.removeprefix('build-') if name.startswith('build-') else ''
        assert data['requested_build'] == build_kind, f'{name}: wrong requested build preview'
        if build_kind:
            build = data['build']
            assert build['active'] is True and build['has_ghost'] is True and build['ghost_visible'] is True, f'{name}: missing native ghost'
            assert build['ok'] is build['ghost_valid'] is (build_kind == 'green'), f'{name}: wrong editor/native validity'
            assert build['state'] == 3 and build['origin'] == build['pointer_cell'], f'{name}: incoherent buy preview pointer'
            assert data['day_phase'] == 0 and data['capture_parameters'] == {'open': False, 'fast_ticks_per_frame': 0, 'speed': 1}
            assert build_kind != 'red' or build['why'], f'{name}: missing placement reason'
        assert data['debug_visible'] is debug, f'{name}: wrong actual F3 state'
        assert data['panel_visible'] is (inspect_guest or inspect_owner), f'{name}: wrong actual inspect panel state'
        assert data['selected_item_id'] == -1, f'{name}: unexpected item selection'
        assert type(data['world_tick']) is int and data['world_tick'] >= 0, f'{name}: invalid world tick'
        if inspect_guest or inspect_owner:
            assert type(data['selected_agent_id']) is int and data['selected_agent_id'] > 0, f'{name}: no selected agent id'
            assert data['selected_role'] == ('owner' if inspect_owner else 'guest') and data['selected_agent_live'] is True, f'{name}: selected agent is not the requested live agent'
            assert data['world_tick'] > 0, f'{name}: busy world did not advance'
        else:
            assert data['selected_agent_id'] == -1 and data['selected_role'] == '', f'{name}: unexpected agent selection'
            assert data['selected_agent_live'] is False, f'{name}: unexpected live selection'
        assert data['requested_owner_mode'] == ('kitchen' if inspect_owner else ''), f'{name}: wrong requested owner mode'
        if inspect_owner:
            assert data['capture_parameters'] == {'open': True, 'fast_ticks_per_frame': 5, 'speed': 1}, 'wrong owner capture parameters'
            assert data['owner_mode'] == 'kitchen', 'owner is not assigned to kitchen'
            assert type(data['owner_warmup_ticks']) is int and 0 <= data['owner_warmup_ticks'] <= 900, 'invalid owner warmup budget'
            assert type(data['selected_task_id']) is int and data['selected_task_id'] > 0, 'owner has no actual task'
            assert data['selected_task_role'] == 'cook' and data['selected_task_label'], 'owner is not cooking'
            assert data['selected_task_state'] == 1 and data['selected_task_claimant'] == data['selected_agent_id'], 'owner does not hold the real CLAIMED task'
            assert type(data['selected_task_step']) is int and data['selected_task_step'] >= 0, 'invalid actual task step'
        if menu:
            assert type(data['day_phase']) is int and data['day_phase'] == 0, 'menu capture is not MORNING'
            assert data['capture_parameters'] == {'open': False, 'fast_ticks_per_frame': 0, 'speed': 0}, 'wrong paused menu capture parameters'
            assert data['world_tick'] == 0, 'paused morning menu capture advanced the simulation'
        if name == 'mood-waits':
            assert data['capture_parameters'] == {'open': True, 'fast_ticks_per_frame': 8, 'speed': 1}, 'wrong mood capture parameters'
            assert data['world_tick'] > 0, 'normal mood capture did not advance the simulation'
            assert type(data['master_seed']) is str and data['master_seed'].lstrip('-').isdigit(), 'missing actual master seed'
            assert set(data['restaurant_rng']) == {'seed', 'state'}, 'missing actual restaurant RNG snapshot'
            assert all(type(value) is str and value.lstrip('-').isdigit() for value in data['restaurant_rng'].values()), 'invalid restaurant RNG snapshot'
            mood = data['mood']
            assert mood['available'] is True and mood['fixture'] == 'none', 'mood capture must use the normal live scene'
            waiting = mood['waiting_guests']
            visible = mood['visible_indicators']
            guests = {row['id']: row for row in waiting}
            icons = {row['id']: row for row in visible}
            assert len(guests) == len(waiting) and len(icons) == len(visible), 'duplicate mood evidence ids'
            assert set(guests) == set(icons), 'visible indicator ids do not match actual waiting guests'
            colors = ((56, 118, 75), (201, 163, 70), (200, 116, 58), (168, 62, 53))
            for guest_id, guest in guests.items():
                assert type(guest_id) is int and guest_id > 0 and type(guest['state']) is int and guest['state'] in (1, 3, 4), 'invalid waiting guest'
                assert all(type(guest[key]) is int for key in ('queue_wait', 'queue_patience', 'food_wait', 'food_patience')), 'invalid patience snapshot'
                elapsed, budget = (guest['queue_wait'], guest['queue_patience']) if guest['state'] == 1 else (guest['food_wait'], guest['food_patience'])
                expected_mood = 0.0 if budget <= 0 else (budget - min(max(elapsed, 0), budget)) / budget
                assert math.isfinite(guest['mood']) and math.isclose(guest['mood'], expected_mood, rel_tol=0, abs_tol=1e-12), 'mood does not match actual patience'
                band = 0 if expected_mood >= .6 else 1 if expected_mood >= .35 else 2 if expected_mood >= .15 else 3
                icon = icons[guest_id]
                assert type(icon['parent_agent_id']) is int and icon['parent_agent_id'] == guest_id, 'indicator is attached to another agent'
                assert type(guest['band']) is int and type(icon['band']) is int and guest['band'] == icon['band'] == band, 'displayed band differs from waiting guest'
                assert icon['visible_in_tree'] is True and icon['dot_visible'] is True, 'indicator is hidden'
                assert icon['mark'] == ('', '', '!', '!!')[band] and icon['mark_visible'] is (band >= 2), 'wrong visible mood punctuation'
                assert len(icon['color']) == 4 and all(math.isclose(actual, expected / 255, rel_tol=0, abs_tol=1e-7) for actual, expected in zip(icon['color'], (*colors[band], 255))), 'wrong native dot color'
                assert icon['in_camera_frustum'] is True, 'waiting indicator is outside the captured camera'
                assert len(icon['screen_position']) == 2 and 0 <= icon['screen_position'][0] < data['width'] and 0 <= icon['screen_position'][1] < data['height'], 'indicator center is outside the image'
                assert all(type(guest[key]) is str and guest[key].lstrip('-').isdigit() for key in ('rng_seed', 'rng_state')), 'missing actual guest RNG snapshot'
                observed_bands.add(band)
            print(f'mood-waits frame={frame}: observed bands={sorted({row["band"] for row in visible})}, waiting ids={sorted(guests)}, seed={data["master_seed"]}, fixture=none')
        print(f'{name}: actual quarter={expected}, Cutaway, guest={data["selected_agent_id"]}, F3={debug}, tick={data["world_tick"]}, 1600x900, sha256={hashlib.sha256(raw).hexdigest()}')
    if batch == "shop":
        print(f'Normal mood capture observed bands across frames: {sorted(observed_bands)}; multiple-band screenshot acceptance still requires image review.')


def verify_service_views(root):
    # These are image/scale/frame identity checks. Native state and HUD
    # geometry remain GDScript tests and director image review.
    def verify_hud_identity(name, size, frame, percent):
        png = root / name / f'shot_{frame:04d}.png'
        raw = png.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n' and len(raw) > 1000, f'{name}: missing/invalid PNG'
        assert struct.unpack('>II', raw[16:24]) == size, f'{name}: wrong PNG dimensions'
        data = json.loads(png.with_suffix('.json').read_text())
        assert data['image_file'] == png.name, f'{name}: metadata names another image'
        assert data['image_sha256'] == hashlib.sha256(raw).hexdigest(), f'{name}: image/metadata digest mismatch'
        assert data['scene'] == 'res://src/world/main.tscn' and data['capture_timing'] == 'frame_post_draw', f'{name}: wrong image source'
        hud = data['hud_layout']
        assert data['requested_hud_layout'] is True and data['frame'] == hud['frame'] == frame, f'{name}: wrong frame identity'
        assert (data['width'], data['height']) == size and data['requested_window_size'] == list(size), f'{name}: wrong viewport identity'
        assert hud['window_size'] == hud['display_size'] == list(size), f'{name}: wrong native window identity'
        assert data['requested_ui_scale_percent'] == hud['ui_scale_percent'] == hud['selected_ui_scale_percent'] == percent, f'{name}: wrong UI scale identity'
        assert math.isclose(hud['content_scale_factor'], percent / 100, abs_tol=1e-7), f'{name}: wrong rendered UI scale'
        print(f'{name}: frame={frame}, scale={percent}%, size={size}, sha256={hashlib.sha256(raw).hexdigest()}')

    verify_hud_identity('hud-1280', (1280, 720), 12, 125)
    verify_hud_identity('hud-1280', (1280, 720), 90, 150)
    verify_hud_identity('hud-1600', (1600, 900), 12, 125)
    verify_hud_identity('hud-1600', (1600, 900), 90, 150)

    # One actual five-day service capture; the scene validates native forecast text and bounds.
    png = root / 'demand-report' / 'shot_0060.png'
    raw = png.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n' and len(raw) > 1000, 'demand-report: missing/invalid PNG'
    assert struct.unpack('>II', raw[16:24]) == (1600, 900), 'demand-report: wrong PNG dimensions'
    data = json.loads(png.with_suffix('.json').read_text())
    assert data['image_file'] == png.name and data['image_sha256'] == hashlib.sha256(raw).hexdigest(), 'demand-report: image identity mismatch'
    assert data['scene'] == 'res://tools/demand_report_review.tscn' and data['capture_timing'] == 'frame_post_draw', 'demand-report: wrong image source'
    assert (data['width'], data['height'], data['frame']) == (1600, 900, 60), 'demand-report: wrong viewport/frame'
    assert type(data['engine_errors']) is int and data['engine_errors'] == 0, 'demand-report: engine/script errors'
    assert 'llvmpipe' in data['video_adapter'].lower(), 'demand-report: wrong software Mesa adapter'
    assert data['day_phase'] == 3 and data['world_tick'] > 0, 'demand-report: service did not close'
    assert data['capture_parameters'] == {'open': False, 'fast_ticks_per_frame': 0, 'speed': 0}, 'demand-report: wrong paused capture parameters'
    assert data['master_seed'] == data['new_game_seed_override'] == '1', 'demand-report: wrong actual seed'
    log = (root / 'demand-report' / 'capture.log').read_text()
    assert log.count('DEMAND_REPORT_REVIEW ') == 1, 'demand-report: missing unique native validation receipt'
    review = json.loads(log.split('DEMAND_REPORT_REVIEW ', 1)[1].splitlines()[0])
    assert review['unchanged'] is True and review['day'] == 5 and review['forecast']['day'] == 6, 'demand-report: incoherent actual forecast'
    print(f'demand-report: actual day5 forecast, unchanged session, sha256={hashlib.sha256(raw).hexdigest()}')

    # One fixed real ten-day service; GDScript validates team/reason text and geometry.
    png = root / 'staff-activity-report' / 'shot_0060.png'
    raw = png.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n' and len(raw) > 1000, 'staff-activity-report: missing/invalid PNG'
    assert struct.unpack('>II', raw[16:24]) == (1600, 900), 'staff-activity-report: wrong PNG dimensions'
    data = json.loads(png.with_suffix('.json').read_text())
    assert data['image_file'] == png.name and data['image_sha256'] == hashlib.sha256(raw).hexdigest(), 'staff-activity-report: image identity mismatch'
    assert data['scene'] == 'res://tools/staff_activity_review.tscn' and data['capture_timing'] == 'frame_post_draw', 'staff-activity-report: wrong image source'
    assert (data['width'], data['height'], data['frame']) == (1600, 900, 60), 'staff-activity-report: wrong viewport/frame'
    assert type(data['engine_errors']) is int and data['engine_errors'] == 0, 'staff-activity-report: engine/script errors'
    assert 'llvmpipe' in data['video_adapter'].lower() and data['day_phase'] == 3, 'staff-activity-report: wrong renderer or phase'
    assert data['capture_parameters'] == {'open': False, 'fast_ticks_per_frame': 0, 'speed': 0}, 'staff-activity-report: wrong paused capture parameters'
    log = (root / 'staff-activity-report' / 'capture.log').read_text()
    assert log.count('STAFF_ACTIVITY_REPORT_REVIEW ') == 1, 'staff-activity-report: missing unique native validation receipt'
    review = json.loads(log.split('STAFF_ACTIVITY_REPORT_REVIEW ', 1)[1].splitlines()[0])
    assert review['seed'] == data['master_seed'] == data['new_game_seed_override'] == '1', 'staff-activity-report: wrong actual seed'
    assert review['setup'] == 'expanded_tables' and review['days'] == review['day'] == 10, 'staff-activity-report: wrong fixed service case'
    assert review['unchanged'] is True and review['validation_timing'] == 'frame_post_draw' and review['world_tick'] == data['world_tick'] > 0, 'staff-activity-report: incoherent native receipt'
    assert review['advice_id'] == 'cook' and 'hiring another cook' in review['advice'], 'staff-activity-report: missing natural cook advice'
    print(f'staff-activity-report: actual expanded_tables day10 cook advice, unchanged session, sha256={hashlib.sha256(raw).hexdigest()}')

    # One ordinary seed-one run: morning choice, live service HUD, and
    # paid evening report. Native GDScript checks validate the real UI state.
    special_dir = root / 'daily-special'
    special_context = (root / 'capture-context.txt').read_text().splitlines()
    context = dict(line.split('=', 1) for line in special_context if '=' in line)
    for key, relative in [('daily_special_review_gd_sha256', 'tools/daily_special_review.gd'),
                          ('daily_special_review_tscn_sha256', 'tools/daily_special_review.tscn')]:
        assert context.get(key) == hashlib.sha256(Path(relative).read_bytes()).hexdigest(), f'daily-special: source context mismatch for {relative}'
    log = (special_dir / 'capture.log').read_text()
    assert log.count('SPECIAL_REVIEW ') == 3, 'daily-special: missing unique morning/HUD/report receipts'
    reviews = {}
    for line in log.splitlines():
        if 'SPECIAL_REVIEW ' not in line:
            continue
        review = json.loads(line.split('SPECIAL_REVIEW ', 1)[1])
        assert review['view'] not in reviews, 'daily-special: duplicate native review receipt'
        reviews[review['view']] = review
    assert set(reviews) == {'morning', 'service_hud', 'evening_report'}, 'daily-special: incomplete native view receipts'
    for name, frame, phase in [('morning', 30, 0), ('report', 120, 3)]:
        png = special_dir / f'shot_{frame:04d}.png'
        raw = png.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n' and len(raw) > 1000, f'daily-special/{name}: missing/invalid PNG'
        assert struct.unpack('>II', raw[16:24]) == (1600, 900), f'daily-special/{name}: wrong PNG dimensions'
        data = json.loads(png.with_suffix('.json').read_text())
        assert data['image_file'] == png.name and data['image_sha256'] == hashlib.sha256(raw).hexdigest(), f'daily-special/{name}: image metadata mismatch'
        assert data['scene'] == 'res://tools/daily_special_review.tscn' and data['capture_timing'] == 'frame_post_draw', f'daily-special/{name}: wrong source or capture timing'
        assert (data['width'], data['height'], data['frame'], data['day_phase']) == (1600, 900, frame, phase), f'daily-special/{name}: wrong size/frame/phase'
        assert type(data['engine_errors']) is int and data['engine_errors'] == 0 and 'llvmpipe' in data['video_adapter'].lower(), f'daily-special/{name}: renderer or engine diagnostics mismatch'
        assert data['capture_parameters'] == {'open': False, 'fast_ticks_per_frame': 0, 'speed': 0}, f'daily-special/{name}: wrong normal paused capture parameters'
        assert data['master_seed'] == data['new_game_seed_override'] == '1', f'daily-special/{name}: wrong seed'
        assert data['world_tick'] == 0 if name == 'morning' else data['world_tick'] > 0, f'daily-special/{name}: wrong simulation time'
        print(f'daily-special/{name}: frame={frame}, phase={phase}, seed=1, sha256={hashlib.sha256(raw).hexdigest()}')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("batch", choices=CAPTURE_FRAMES)
    parser.add_argument("--root", type=Path, default=Path("screens/visual-review"))
    args = parser.parse_args()
    verify_inventory(args.root, args.batch)
    verify_standard_views(args.root, args.batch)
    if args.batch == "service":
        verify_service_views(args.root)


if __name__ == "__main__":
    main()
