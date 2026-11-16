#!/usr/bin/env bash
# Builds gamedata/spawns/ps_lobby.spawn: the game's all.spawn with only
# fake_start's objects (the actor and its level changer) and every level's
# smart terrains (scripts look them up by name). The world graph,
# patrol paths and artefact spawn places are kept as they are, so every level
# name and graph vertex a script looks up still exists.
#
# Run from Git Bash:  tools/build_lobby_spawn.sh [all.spawn] [acdc dir] [work dir]
#   all.spawn  the spawn the game uses (the highest mod in MO2 with
#              gamedata/spawns/all.spawn; default: New Storylines')
#   acdc dir   ACDC (universal_acdc.pl and stkutils); default ../ACDC_update_for_1.4
#   work dir   scratch folder for the decompiled text; default ../Lobby_spawn
# Rebuild after a modpack update that changes all.spawn.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-/d/GAMMA/mods/197- New Storylines (DLTX minimodpack) - Demonized/gamedata/spawns/all.spawn}"
acdc_src="${2:-$repo/../ACDC_update_for_1.4}"
work="${3:-$repo/../Lobby_spawn}"
out="$repo/gamedata/spawns/ps_lobby.spawn"

[ -f "$src" ] || { echo "no spawn at $src" >&2; exit 1; }
[ -f "$acdc_src/universal_acdc.pl" ] || { echo "no ACDC at $acdc_src" >&2; exit 1; }

mkdir -p "$work"
work="$(cd "$work" && pwd)"
# ACDC is copied, its ini files made LF: with CRLF this Perl keeps a "\r" on
# every class name ("unknown clsid cse_alife_item_ammo")
rm -rf "$work/acdc" "$work/decompiled" "$work/lobby"
cp -r "$acdc_src" "$work/acdc"
for f in "$work"/acdc/*.ini "$work"/acdc/*.ltx "$work"/acdc/*.txt; do sed -i 's/\r$//' "$f"; done
cp "$src" "$work/all.spawn"

cd "$work/acdc"
# -I.: Perl 5.26+ no longer looks for modules (stkutils) in the current folder
perl -I. universal_acdc.pl -d ../all.spawn -out ../decompiled -sort complex
[ -f ../decompiled/alife_fake_start.ltx ] || { echo "no fake_start objects in the decompiled spawn" >&2; exit 1; }

cp -r ../decompiled ../lobby
# every level's smart terrains, kept in one file: G.A.M.M.A.'s first-update
# scripts look them up by name with no nil check (lc_custom.script:
# SIMBOARD.smarts_by_names["gar_smart_terrain_5_2"]), and under xrRazom one
# failing first-update callback skips all the later ones (in game
# 2026-11-15: Body Health System then crashed on its next update). The
# test-map switch keeps them from filling squads.
perl -e '
	my $n = 0;
	open(my $out, ">", "../lobby/alife_ps_smarts.ltx") or die $!;
	for my $f (glob("../decompiled/alife_*.ltx")) {
		next if $f =~ /alife_fake_start\.ltx$/;
		local $/; open(my $in, "<", $f) or die $!; my $t = <$in>; close $in;
		for my $b (split /(?=^\[\d+\]\s*$)/m, $t) {
			if ($b =~ /^section_name = smart_terrain\s*$/m) { print $out $b; $n++ }
		}
	}
	close $out;
	print "smart terrains kept: $n\n";
'
# the [alife] list: fake_start's objects and the smart terrains
perl -0pi -e 's/(\[alife\]\s*source_files\s*=\s*<<END\s*\n).*?(\nEND)/$1alife_fake_start.ltx,\nalife_ps_smarts.ltx$2/s' ../lobby/all.ltx
grep -A3 '^\[alife\]' ../lobby/all.ltx

perl -I. universal_acdc.pl -compile ../lobby -out ../ps_lobby.spawn
mkdir -p "$(dirname "$out")"
cp ../ps_lobby.spawn "$out"
ls -l "$src" "$out"
echo "built $out"
