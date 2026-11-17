#!/usr/bin/env bash
# Builds gamedata/spawns/ps_lobby.spawn: the game's all.spawn with only the
# actor, moved to the selected place of mod_system_persistent_stalkers.ltx
# (LOBBY_PLACE to pick another: see below), the campfires near it, and every
# level's smart terrains (scripts look them up by name). The world graph,
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
# the lobby's place (2026-11-16, user's request): xrRazom does not host on
# fake_start, so the actor starts where the selected place of
# gamedata/configs/mod_system_persistent_stalkers.ltx puts the host
# ([persistent_stalkers_lobby] place, or LOBBY_PLACE): its map and
# host_position. The game and level vertices are the nearest object's on that
# map. The campfires within 40 m are kept (the lobby lights them); fake_start's
# level changer is not.
config="$repo/gamedata/configs/mod_system_persistent_stalkers.ltx"
perl -e '
	my ($config, $want) = @ARGV;
	open(my $c, "<", $config) or die "no config $config\n";
	my (%ini, $sec);
	while (<$c>) {
		s/\r?\n$//;
		next if /^\s*;/ || /^\s*$/;
		if (/^\s*!*\[([^\]]+)\]/) { $sec = $1; next }
		if ($sec && /^\s*(\w+)\s*=\s*(.*?)\s*(;.*)?$/) { $ini{$sec}{$1} = $2 }
	}
	close $c;
	my $name = $want || $ini{persistent_stalkers_lobby}{place} or die "no place selected in $config\n";
	my $p = $ini{"ps_lobby_place_$name"} or die "no [ps_lobby_place_$name] in $config\n";
	my $map = $p->{map} or die "[ps_lobby_place_$name] has no map\n";
	my ($hx, $hy, $hz) = split /\s*,\s*/, ($p->{host_position} // "");
	defined $hz or die "[ps_lobby_place_$name] has no host_position (x, y, z)\n";
	my $file = "../decompiled/alife_$map.ltx";
	-f $file or die "no objects for map $map in the decompiled spawn ($file)\n";
	my $actor;
	{
		local $/; open(my $in, "<", "../decompiled/alife_fake_start.ltx") or die $!; my $t = <$in>; close $in;
		for my $b (split /(?=^\[\d+\]\s*$)/m, $t) { $actor = $b if $b =~ /^section_name = actor\s*$/m }
	}
	die "no actor in alife_fake_start.ltx\n" unless $actor;
	my ($best, $bd, @fires) = (undef, 1e18);
	{
		local $/; open(my $in, "<", $file) or die $!; my $t = <$in>; close $in;
		for my $b (split /(?=^\[\d+\]\s*$)/m, $t) {
			my ($x, $y, $z) = $b =~ /^position = ([^,]+),\s*([^,]+),\s*(\S+)\s*$/m or next;
			my ($gv) = $b =~ /^game_vertex_id = (\d+)/m;
			my ($lv) = $b =~ /^level_vertex_id = (\d+)/m;
			my $d = ($x - $hx) ** 2 + ($y - $hy) ** 2 + ($z - $hz) ** 2;
			push @fires, $b if $b =~ /^section_name = campfire\s*$/m && $d <= 40 * 40;
			next unless defined $gv && defined $lv && $lv < 4294967295;
			($best, $bd) = ([$gv, $lv], $d) if $d < $bd;
		}
	}
	die "no object with graph vertices on $map\n" unless $best;
	my $pos = sprintf("%.4f, %.4f, %.4f", $hx, $hy, $hz);
	$actor =~ s/^position = .*$/position = $pos/m;
	$actor =~ s/^upd:position = .*$/upd:position = $pos/m;
	$actor =~ s/^game_vertex_id = .*$/game_vertex_id = $best->[0]/m;
	$actor =~ s/^level_vertex_id = .*$/level_vertex_id = $best->[1]/m;
	open(my $out, ">", "../lobby/alife_ps_lobby.ltx") or die $!;
	print $out $actor, @fires;
	close $out;
	printf "place %s: the actor on %s at %s (game vertex %d, level vertex %d, from an object %.1f m away); %d campfires within 40 m kept\n",
		$name, $map, $pos, $best->[0], $best->[1], sqrt($bd), scalar(@fires);
' "$config" "${LOBBY_PLACE:-}"
# the [alife] list: the actor and the campfires, and the smart terrains
perl -0pi -e 's/(\[alife\]\s*source_files\s*=\s*<<END\s*\n).*?(\nEND)/$1alife_ps_lobby.ltx,\nalife_ps_smarts.ltx$2/s' ../lobby/all.ltx
grep -A3 '^\[alife\]' ../lobby/all.ltx

perl -I. universal_acdc.pl -compile ../lobby -out ../ps_lobby.spawn
mkdir -p "$(dirname "$out")"
cp ../ps_lobby.spawn "$out"
ls -l "$src" "$out"
echo "built $out"
