#!/usr/bin/env python3
"""Dependency map of src/world/main.gd (#526). Run by hand, never in CI:

    python3 tools/main_map.py            # ranked seam table
    python3 tools/main_map.py --seam report   # one seam in detail
    python3 tools/main_map.py --name _reorder # who uses one function or member

It reads the code as text (no Godot needed), so it is approximate:
  * a name counts as Main's only when it is not written after a dot;
  * a local variable that shadows a member counts as a use of the member;
  * outside main.gd, a bare name counts in scripts that extend main.gd, and
    `.name` or a quoted "name" counts in any script that mentions Main, so a
    common name (`sim`, `world`) is over-counted and a private one is not.
A seam is a guess written below as a pattern; the script then pulls in every
function and member that only that seam uses, and reports what is left
crossing the boundary.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MAIN = "src/world/main.gd"
TOKEN = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)")
DECL = re.compile(
    r"^(?:@[a-z_]+(?:\([^)]*\))?\s+)*(static func|func|var|const|signal|enum|class)\s+([A-Za-z_][A-Za-z0-9_]*)")
AUTOLOADS = ("SaveSystem", "Economy", "Clock", "GameState", "EventBus", "Settings", "GameMode")

# Seams to test. Patterns match FUNCTION names; members follow their users.
SEAMS = {
    "save-sections": r"_(capture|restore)_.*",
    "save-load-staging": r"_load_autosave.*|_validate_staged_sections|_stage_site_hours|_refuse_staged|"
                         r"_install_staged_sections|_clear_site_staging",
    "new-game": r"_new_game",
    "report": r"build_report",
    "panels": r"(is|set)_\w+_visible|toggle_\w+|_dismiss_\w+|_on_\w+_close_requested",
    "stock-ordering": r"stock_\w+|_on_stock_\w+|_refresh_stock_panel|_cart_order|_trim_cart|"
                      r"\w*haggle\w*|delivery_countdown|_due_text|_menu_ingredients|_dish_ingredients",
    "stock-morning": r"_expire_stock|_restock\w*|_buy_standing|_deliver_due|_on_dock_stored|_on_the_way|"
                     r"_on_delivery_tick|_shelf_lives|_unit_costs|_storage_\w+|storage_space|_reorder|"
                     r"restock_forecast_targets",
    "service-events": r"\w*service_event\w*|can_send_home",
    "opening-week": r"\w*opening_week\w*|_opening_\w+|_observe_opening\w*|_chain_\w+|_five_star_reviews_today|"
                    r"_turned_away_today|_calm_day_value|_items_counted|_refresh_opening_tracker",
    "goals-milestones": r"_award_\w+|_milestone_observation|_begin_weekly_challenge_if_needed|_refresh_goals|"
                        r"_collection_progress_snapshot|\w*collection_toast\w*",
    "paint-input": r"\w*paint\w*|\w*swatch\w*|\w*copied_look|_on_copy_look_requested",
    "build-input": r"route_build_input|\w*build\w*|begin_\w+|\w+_at_screen_position|_on_\w+_tool_requested|"
                   r"_on_blueprint_\w+|_on_catalogue_\w+|_set_catalogue_room_for|_undo_key|_on_shift_changed",
    "shop-edits": r"shop_(move|buy|stamp|walls|floor|patio|flooring|wall_finishes|hang|rehang|take_down|rooms|sell)|"
                  r"_after_edit|undo_edit|redo_edit|_step_history|_clear_rooms_note|_show_aisle_note",
    "menu": r"menu_\w+|_on_menu_(enable|signature|price|reset_prices)_requested|_cookable\w*|_station_reachable|"
            r"_refresh_menu\w*|_track_menu_access_losses|_apply_menu|_expected_dish_quality|_remember_menu_quality|"
            r"_menu_station_state|_equipment_\w+|_support_item_name|_station_item_name|drink_station_hints|"
            r"_on_special_requested|_on_restaurant_name_requested",
    "staff": r"staff_\w+|_on_staff_\w+|can_(view|edit)_staff|_change_staff|_site_managed|_frozen_roster|"
             r"_refresh_staff_transfer_sites|_may_hire_role|_managers_on_offer|_candidate_role|"
             r"\w*site_manager\w*|_is_roster_manager",
    "sites-property": r"can_switch_site|switch_site|_log_switch_refusal|\w*property\w*|\w*_lot\w*|lot_\w+|"
                      r"_new_site_sections|offer_new_site|_on_site_\w+|site_(switch|opening)_refusal|"
                      r"_refresh_opening_block|close_for_today|\w*site_card\w*|_close_away_sites|_home_rent|"
                      r"closing_reputation|_purchase_refusal",
    "owner": r"owner_set_appearance|_sync_owner_appearance|show_owner_picker|is_owner_picker_visible|"
             r"_on_owner_\w+|_selected_owner|assign_owner_mode|_owner_mode_for_key",
    "bookings": r"\w*booking\w*",
    "demand-vibe-curb": r"\w*vibe\w*|\w*curb_appeal\w*|\w*demand\w*|_street_factor|\w*effective_signature\w*",
    "offers(lease,cat,tray)": r"\w*lease\w*|\w*cat_\w+|adopt_cat|cat_refusal|tray_buy|_on_tray_requested",
    "day-light-weather": r"_select_morning_weather|_refresh_day_light|lamp_visuals|day_light_\w+|_refresh_weather",
    "hints": r"refresh_hints|_hint_target|_on_hint_acknowledged|_on_guide_skipped|_on_show_guide_requested",
    "closing": r"_on_service_closed|_charge_closing_costs|_show_evening_report|show_closed_report|"
               r"_sync_report_button|_on_customer_paid|_restock_station_supplies",
    "selection": r"pick_screen_position|select_\w+|clear_selection|shop_menu_board_section|shop_item_look|"
                 r"_on_item_look_requested|_on_menu_board_section_requested|inspection_state|_on_inspection_tick",
}


def strip(line):
    """Drop comments and string contents (keeps quotes) so tokens are code."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
                out.append(ch)
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def strings(line):
    return re.findall(r"[&^]?\"([A-Za-z_][A-Za-z0-9_]*)\"", line)


def parse_main(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    decls = []  # [kind, name, start, end)
    for index, line in enumerate(lines):
        found = DECL.match(line)
        if found:
            kind = "func" if "func" in found.group(1) else found.group(1)
            decls.append([kind, found.group(2), index, index + 1])
    for position, decl in enumerate(decls):
        limit = decls[position + 1][2] if position + 1 < len(decls) else len(lines)
        end = decl[2] + 1
        for index in range(decl[2] + 1, limit):
            text = lines[index]
            if text.strip() and (text[0] in "\t " or text.lstrip().startswith(")")):
                end = index + 1
            elif text.strip() and not text.startswith("#") and not text.startswith("@"):
                break
        decl[3] = end
    return lines, decls


def bare_tokens(text):
    """Names not written after a dot (so `sim.orders` gives `sim` only)."""
    found = set()
    for match in TOKEN.finditer(text):
        start = match.start(1)
        if start > 0 and text[start - 1] == ".":
            if not text[:start].endswith("self."):
                continue
        found.add(match.group(1))
    return found


def dotted_tokens(text):
    return set(re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", text))


def project_files():
    for base in ("src", "tools", "tests"):
        for folder, _dirs, names in os.walk(os.path.join(ROOT, base)):
            for name in names:
                if name.endswith((".gd", ".tscn")):
                    yield os.path.relpath(os.path.join(folder, name), ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seam")
    parser.add_argument("--name")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()

    lines, decls = parse_main(os.path.join(ROOT, MAIN))
    funcs = {d[1]: d for d in decls if d[0] == "func"}
    members = {d[1]: d for d in decls if d[0] in ("var", "const", "signal", "enum")}
    names = set(funcs) | set(members)

    uses = {}       # function -> Main names its body mentions
    autoload = {}   # function -> autoloads its body mentions
    node_paths = {}
    for name, (_kind, _n, start, end) in funcs.items():
        body = "\n".join(strip(line) for line in lines[start + 1:end])
        raw = "\n".join(lines[start + 1:end])
        tokens = bare_tokens(body)
        quoted = set(strings(raw))
        uses[name] = ((tokens | quoted) & names) - {name}
        autoload[name] = tokens & set(AUTOLOADS)
        node_paths[name] = len(re.findall(r"\$[A-Za-z\"]|get_node", body))
    used_by = defaultdict(set)
    for user, targets in uses.items():
        for target in targets:
            used_by[target].add(user)
    # Member initialisers and getters can use other members/functions too.
    for name, (_kind, _n, start, end) in members.items():
        body = "\n".join(strip(line) for line in lines[start:end])
        for target in (bare_tokens(body) & names) - {name}:
            used_by[target].add("<member %s>" % name)

    # Outside reach.
    extenders = set()
    texts = {}
    for path in project_files():
        if path == MAIN:
            continue
        texts[path] = open(os.path.join(ROOT, path), encoding="utf-8", errors="replace").read()
    changed = True
    bases = {"res://" + MAIN}
    while changed:
        changed = False
        for path, text in texts.items():
            if path in extenders:
                continue
            found = re.search(r'^extends\s+"([^"]+)"', text, re.M)
            if found and found.group(1) in bases:
                extenders.add(path)
                bases.add("res://" + path)
                changed = True
    outside = defaultdict(set)  # name -> files
    for path, text in texts.items():
        mentions_main = path in extenders or "world/main" in text or re.search(r"\bmain\b", text) is not None
        if not mentions_main:
            continue
        code = "\n".join(strip(line) for line in text.split("\n"))
        found = set(dotted_tokens(code)) | set(strings(text))
        if path in extenders:
            found |= bare_tokens(code)
        if path.endswith(".tscn"):
            found |= set(re.findall(r'method="([^"]+)"', text))
        for name in found & names:
            outside[name].add(path)

    if args.name:
        name = args.name
        if name not in names:
            sys.exit("no such top-level name in main.gd")
        decl = funcs.get(name) or members[name]
        print("%s %s  lines %d-%d" % (decl[0], name, decl[2] + 1, decl[3]))
        if name in uses:
            print("  uses:", ", ".join(sorted(uses[name])))
            print("  autoloads:", ", ".join(sorted(autoload[name])))
        print("  used by (main.gd):", ", ".join(sorted(used_by.get(name, []))))
        print("  outside files (%d):" % len(outside.get(name, [])))
        for path in sorted(outside.get(name, [])):
            print("    " + path)
        return

    def closure(pattern):
        regex = re.compile(r"^(?:%s)$" % pattern)
        seeds = {name for name in funcs if regex.match(name)}
        inside = set(seeds)
        grown = True
        while grown:
            grown = False
            for name in names - inside:
                users = used_by.get(name, set())
                if not users or not users <= inside:
                    continue
                if name in funcs and (outside.get(name) or name.startswith("_on_")
                                      or name in ("_ready", "_process", "_exit_tree", "_unhandled_input")):
                    continue  # reached from outside, or wired as a signal handler elsewhere
                inside.add(name)
                grown = True
        return seeds, inside

    rows = []
    detail = {}
    for label, pattern in SEAMS.items():
        seeds, inside = closure(pattern)
        inside_funcs = {n for n in inside if n in funcs}
        inside_members = {n for n in inside if n in members}
        size = sum(funcs[n][3] - funcs[n][2] for n in inside_funcs) \
            + sum(members[n][3] - members[n][2] for n in inside_members)
        out_names = set()
        for name in inside_funcs:
            out_names |= uses[name] - inside
        out_funcs = {n for n in out_names if n in funcs}
        out_vars = {n for n in out_names if n in members and members[n][0] == "var"}
        out_consts = {n for n in out_names if n in members and members[n][0] != "var"}
        in_names = {n for n in inside if (used_by.get(n, set()) - inside
                                         - {"<member %s>" % m for m in inside_members})}
        ext_names = {n for n in inside if outside.get(n)}
        ext_files = set()
        for name in ext_names:
            ext_files |= outside[name]
        loads = set()
        nodes = 0
        for name in inside_funcs:
            loads |= autoload[name]
            nodes += node_paths[name]
        width = len(out_funcs) + len(out_vars) + len(in_names)
        reach = len(ext_names)
        score = size / float(width + reach + 1)
        rows.append((score, label, size, len(inside_funcs), len(inside_members), len(out_funcs), len(out_vars),
                     len(out_consts), len(in_names), len(ext_names), len(ext_files), ",".join(sorted(loads)), nodes))
        detail[label] = (inside_funcs, inside_members, out_funcs, out_vars, out_consts, in_names, ext_names,
                         ext_files, seeds)

    if args.seam:
        if args.seam not in detail:
            sys.exit("seams: " + ", ".join(SEAMS))
        (inside_funcs, inside_members, out_funcs, out_vars, out_consts, in_names, ext_names, ext_files,
         seeds) = detail[args.seam]
        print("== %s" % args.seam)
        print("functions (%d): %s" % (len(inside_funcs), ", ".join(sorted(inside_funcs))))
        print("  of which pulled in (not matched by the pattern): %s" % ", ".join(sorted(inside_funcs - seeds)))
        print("members only it uses (%d): %s" % (len(inside_members), ", ".join(sorted(inside_members))))
        print("calls out to Main functions (%d): %s" % (len(out_funcs), ", ".join(sorted(out_funcs))))
        print("reads/writes Main vars it shares (%d): %s" % (len(out_vars), ", ".join(sorted(out_vars))))
        print("constants/signals it reads (%d): %s" % (len(out_consts), ", ".join(sorted(out_consts))))
        print("names the rest of main.gd uses (%d): %s" % (len(in_names), ", ".join(sorted(in_names))))
        print("names used outside main.gd (%d):" % len(ext_names))
        for name in sorted(ext_names):
            print("  %-36s %d file(s)" % (name, len(outside[name])))
        print("outside files (%d)" % len(ext_files))
        return

    rows.sort(reverse=True)
    total = len(lines)
    head = ("seam", "lines", "funcs", "own members", "calls out", "shared vars", "consts", "called in",
            "names used outside", "outside files", "autoloads", "node paths", "score")
    if args.markdown:
        print("| " + " | ".join(head) + " |")
        print("|" + "---|" * len(head))
        for (score, label, size, nf, nm, of, ov, oc, inn, en, ef, loads, nodes) in rows:
            print("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s | %d | %.1f |" % (
                label, size, nf, nm, of, ov, oc, inn, en, ef, loads or "-", nodes, score))
    else:
        print("main.gd: %d lines, %d functions, %d members; %d scripts extend it" % (
            total, len(funcs), len(members), len(extenders)))
        print("score = lines / (calls out + shared vars + called in + names used outside + 1)")
        print("%-24s %5s %5s %4s %5s %6s %6s %6s %7s %6s %5s  %s" % (
            "seam", "lines", "funcs", "own", "out", "shared", "consts", "in", "ext.nm", "ext.f", "score", "autoloads"))
        for (score, label, size, nf, nm, of, ov, oc, inn, en, ef, loads, nodes) in rows:
            print("%-24s %5d %5d %4d %5d %6d %6d %6d %7d %6d %5.1f  %s" % (
                label, size, nf, nm, of, ov, oc, inn, en, ef, score, loads))


if __name__ == "__main__":
    main()
