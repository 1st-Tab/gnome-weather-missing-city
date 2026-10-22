#!/usr/bin/env bash
#
# Add a city to GNOME Weather when the search does not find it.
#
# The city goes straight into the app's "locations" setting, tied to a
# nearby airport station for the "right now" reading. Forecasts
# still come from met.no for the coordinates given, so the airport can
# be a fair distance away.
#
# usage: add-weather-location.sh [--help]

set -euo pipefail

APP_ID=org.gnome.Weather
KEY=($APP_ID locations)

# Runs under the app's own gjs/GWeather (host or flatpak), so if it loads
# here it loads in the app.
read -r -d '' HELPER <<'JS' || true
imports.gi.versions.GWeather = '4.0';

function die(msg) {
    printerr(msg);
    imports.system.exit(1);
}

// "47.21811, -1.55360", a maps url with @lat,lon, or 47°13'05.2"N 1°33'13.0"W
function parseCoords(text) {
    let lat, lon;
    let m = text.match(/@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/) ||
            text.match(/^\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$/);
    if (m) {
        lat = parseFloat(m[1]);
        lon = parseFloat(m[2]);
    } else {
        let parts = [...text.matchAll(/(\d+(?:\.\d+)?)°\s*(?:(\d+(?:\.\d+)?)['′]\s*)?(?:(\d+(?:\.\d+)?)(?:["″]|'')\s*)?([NSEW])/gi)];
        let ns = parts.find(p => /[NS]/i.test(p[4]));
        let ew = parts.find(p => /[EW]/i.test(p[4]));
        if (parts.length !== 2 || !ns || !ew)
            return null;
        let toDeg = p => (parseFloat(p[1]) + (parseFloat(p[2]) || 0) / 60 + (parseFloat(p[3]) || 0) / 3600) *
                         (/[SW]/i.test(p[4]) ? -1 : 1);
        lat = toDeg(ns);
        lon = toDeg(ew);
    }
    if (!(Math.abs(lat) <= 90 && Math.abs(lon) <= 180))
        return null;
    return [lat, lon];
}

function main([cmd, ...args]) {
    const {GLib, GWeather} = imports.gi;
    const world = GWeather.Location.get_world();
    if (!world)
        die('GWeather has no location database');

    let parseList = text => GLib.Variant.parse(new GLib.VariantType('av'), text, null, null);

    switch (cmd) {
    case 'ping':
        break;
    case 'parse': {
        let c = parseCoords(args[0]);
        if (!c)
            die('bad coordinates');
        print(`${c[0].toFixed(6)} ${c[1].toFixed(6)}`);
        break;
    }
    case 'nearest': {
        let city = world.find_nearest_city(parseFloat(args[0]), parseFloat(args[1]));
        let station = city && city.next_child(null);
        if (station && station.get_code())
            print(`${station.get_code()}\t${city.get_name()}`);
        break;
    }
    case 'station': {
        let station = world.find_by_station_code(args[0]);
        if (!station)
            die(`no station ${args[0]} in the GWeather database`);
        print(station.get_name());
        break;
    }
    case 'add': {
        let [current, name, code, lat, lon] = args;
        let rad = d => parseFloat(d) * Math.PI / 180;
        // format 2: (name, station, is_city, coords, parent coords), in radians.
        // is_city=false, or a name matching a nearby known city loads that
        // city instead, with its coordinates.
        let entry = new GLib.Variant('(uv)', [2,
            new GLib.Variant('(ssba(dd)a(dd))', [name, code, false, [[rad(lat), rad(lon)]], []])]);
        if (!world.deserialize(entry))
            die('GWeather refused the location');
        let items = parseList(current).deep_unpack();
        if (items.some(v => world.deserialize(v)?.get_name() === name))
            die(`'${name}' is already in the list`);
        // like the app: newest first, 10 max (it drops anything past that on load)
        items.unshift(entry);
        print(new GLib.Variant('av', items.slice(0, 10)).print(true));
        break;
    }
    case 'names': {
        // same thing the app does on startup; null = it would drop the entry
        let list = parseList(args[0]);
        let ok = true;
        for (let i = 0; i < list.n_children(); i++) {
            let loc = world.deserialize(list.get_child_value(i).get_variant());
            print(loc ? loc.get_name() : `(entry ${i} is broken)`);
            ok &&= !!loc;
        }
        if (!ok)
            imports.system.exit(1);
        break;
    }
    default:
        die(`unknown command ${cmd}`);
    }
}

try {
    main(ARGV);
} catch (e) {
    // most likely GWeather 4 missing, or a settings value we cannot parse
    die(e.message ?? String(e));
}
JS

die() {
    echo "error: $*" >&2
    exit 1
}

trap 'die "line $LINENO: \"$BASH_COMMAND\" failed"' ERR

case ${1:-} in
    -h|--help) sed -n '3,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
    '') ;;
    *) die "unknown option $1" ;;
esac

# root would get root's settings, not the user's
[[ $EUID -ne 0 ]] || die "do not run this as root"

native=0
flat=0
command -v gnome-weather >/dev/null && native=1
command -v flatpak >/dev/null && flatpak info $APP_ID &>/dev/null && flat=1

if ((native && flat)); then
    echo "Weather is installed both natively and as a flatpak, each with its own settings."
    read -rp "Which one should be updated? [n/f] " ans
    case $ans in
        [nN]*) flat=0 ;;
        [fF]*) native=0 ;;
        *) die "expected n or f" ;;
    esac
fi

if ((flat)); then
    mode=flatpak
    gs() { flatpak run --command=gsettings $APP_ID "$@"; }
    helper() { flatpak run --command=gjs $APP_ID -c "$HELPER" "$@"; }
    restore="flatpak run --command=gsettings $APP_ID set ${KEY[*]}"
elif ((native)); then
    mode=native
    command -v gjs >/dev/null || die "gjs is not installed"
    gs() { gsettings "$@"; }
    helper() { gjs -c "$HELPER" "$@"; }
    restore="gsettings set ${KEY[*]}"
else
    die "GNOME Weather does not seem to be installed"
fi

start_app() {
    if [[ $mode == flatpak ]]; then
        setsid -f flatpak run $APP_ID &>/dev/null
        sleep 4
        flatpak ps --columns=application | grep -qx $APP_ID
    else
        setsid -f gnome-weather &>/dev/null
        sleep 4
        pgrep -u "$UID" -x gnome-weather >/dev/null
    fi
}

# fail now rather than halfway through
gs list-keys $APP_ID &>/dev/null || die "cannot read the $APP_ID settings"
helper ping || die "cannot load GWeather 4 with gjs"

echo "Found $mode install."

read -rp "City name: " name
name=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$name")
[[ -n $name ]] || die "empty name"
((${#name} <= 100)) || die "name too long (100 chars max)"
# no escape sequences sneaking into the terminal or the app
[[ $name != *[[:cntrl:]]* ]] || die "name has control characters"

echo "In Google Maps, right-click the place and click the coordinates to copy them."
read -rp "Coordinates: " coords
latlon=$(helper parse "$coords") || die "cannot read those coordinates"
read -r lat lon <<<"$latlon"
echo "-> $lat, $lon"

# needs the 4-letter ICAO code (LFPG), not the 3-letter IATA one (CDG)
nearest=$(helper nearest "$lat" "$lon") || die "station lookup failed"
if [[ -n $nearest ]]; then
    guess=${nearest%%$'\t'*}
    echo "Closest station: $guess (${nearest#*$'\t'})"
    read -rp "ICAO code [$guess]: " code
    code=${code:-$guess}
else
    read -rp "ICAO code: " code
fi
code=${code^^}
[[ $code =~ ^[A-Z0-9]{4}$ ]] || die "an ICAO code is 4 letters"
station=$(helper station "$code") || die "try another airport nearby"
echo "-> $station"

# catch duplicates etc. while the app is still open
list=$(gs get "${KEY[@]}") || die "cannot read the current cities"
helper add "$list" "$name" "$code" "$lat" "$lon" >/dev/null || die "nothing changed"

mapfile -t names < <(helper names "$list" || true)
if ((${#names[@]} >= 10)); then
    echo "Weather keeps 10 cities at most, so '${names[-1]}' would be removed."
    read -rp "Go ahead? [y/N] " ans
    [[ $ans == [yY]* ]] || die "nothing changed"
fi

# close the app first, otherwise it can write its old list back over ours
gapplication action $APP_ID quit 2>/dev/null || true
if [[ $mode == flatpak ]]; then
    flatpak kill $APP_ID 2>/dev/null || true
else
    pkill -u "$UID" -x gnome-weather || true
fi
sleep 1
# whatever happens from here, do not leave the user without their app
trap 'start_app || true' EXIT

current=$(gs get "${KEY[@]}")
new=$(helper add "$current" "$name" "$code" "$lat" "$lon") || die "nothing changed"

backup=${XDG_CACHE_HOME:-$HOME/.cache}/gnome-weather-locations.$(date +%Y%m%d-%H%M%S).bak
mkdir -p "${backup%/*}"
(umask 077; echo "$current" >"$backup")  # it is basically where the user lives
echo "Old list saved to $backup"

gs set "${KEY[@]}" "$new" || die "could not save, the list is unchanged"

echo "Saved locations:"
if ! helper names "$(gs get "${KEY[@]}")" | sed 's/^/  /'; then
    gs set "${KEY[@]}" "$current"
    die "something does not load, put the old list back"
fi

trap - EXIT
start_app || die "Weather did not start. To undo: $restore \"\$(cat $(printf %q "$backup"))\""

echo "Added $name."
