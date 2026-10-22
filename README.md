# gnome-weather-missing-city

**Add a missing city or custom location to GNOME Weather** (gnome-weather,
org.gnome.Weather), native or Flatpak.

GNOME Weather is lovely, until a search for the user's town comes back empty,
whatever the spelling.

This little script adds the town anyway. It takes a name and the coordinates
from Google Maps, and the town shows up in Weather like any other city.

## Using it

```sh
git clone https://github.com/1st-Tab/gnome-weather-missing-city
cd gnome-weather-missing-city
chmod +x add-weather-location.sh
./add-weather-location.sh
```

The script asks for three things:

1. **The name** to show in the app.
2. **The coordinates.** In Google Maps, a right-click on the town shows its
   coordinates at the top of the menu; a click on them copies them. They can
   be pasted as they are. A Maps link or `47°13'05.2"N 1°33'13.0"W` works too.
3. **An airport code.** The script suggests the closest one, so pressing
   Enter is usually enough. A typed code must be the 4-letter ICAO code
   (`LFPG`), not the 3-letter one printed on luggage tags (`CDG`).
   Codes can be looked up on [World Airport Codes](https://www.world-airport-codes.com/).
   Small airfields are often unknown to GNOME Weather; the script says so,
   and the next bigger airport is worth a try.

Then it closes Weather, saves the town, checks that everything still loads,
and opens Weather again. The new town comes first in the list, just like a
city added from the app.

Weather keeps 10 cities at most. When the list is already full, the script
names the city that would be dropped and asks before going ahead.

It works with the version from the distribution and with the Flathub one.
When both are installed, it asks which one to update.

## Where the weather data comes from

| What the app shows         | Where it comes from |
|----------------------------|---------------------|
| Hourly and daily forecasts | [MET Norway](https://api.met.no), for the exact coordinates given |
| "Right now" at the top     | The airport's live report ([METAR](https://en.wikipedia.org/wiki/METAR), via [aviationweather.gov](https://aviationweather.gov)), if it sent one in the last 3 hours. Otherwise, MET Norway's forecast for the current hour at the town's coordinates |

So the forecast is not the airport's, and a village with no weather station
is fine. The airport only gives the "right now" reading, so the nearest one
keeps it closest to the town. Times in the app use the time zone of the
known city nearest to the coordinates, not the airport's.

(Checked in the source: `weather-metno.c`, `weather-metar.c` and
`fixup_current_conditions()` in libgweather's `gweather-info.c`, and
`hourlyForecast.ts` in GNOME Weather.)

## If something goes wrong

The script checks everything it can before touching anything: that GWeather
loads, that the coordinates and the airport make sense, and that the town
is not already in the list. If any of that fails, nothing changes.

Before saving, it keeps a copy of the current list of cities in
`~/.cache/gnome-weather-locations.<date>.bak`. If the new list does not load,
it puts the old one back by itself. If Weather does not start afterwards, it
prints the exact command to restore the copy. And if anything fails once
Weather has been closed, it opens Weather again.

A town is removed in the app, like any other city.

## Which systems?

Any Linux with GNOME Weather, which mostly means GNOME desktops:
Ubuntu, Fedora Workstation, Debian, Zorin OS, Pop!_OS (22.04 and older),
openSUSE, Arch Linux, Manjaro GNOME, EndeavourOS, RHEL, AlmaLinux,
Rocky Linux, Vanilla OS…

Other desktops (KDE, Cinnamon, XFCE…) work too, as long as GNOME Weather is
installed, for example from Flathub.

## Needs

- bash
- GNOME Weather 42 or newer (libgweather 4)   
- `gjs` for the native version (it comes with GNOME). The Flatpak version
  already ships everything it needs.

## Even better

A fairly big town (around 100,000 people or more) probably belongs in
GNOME's own list, for everyone. Here is
[how to add it](https://gitlab.gnome.org/GNOME/libgweather/-/blob/main/doc/adding-locations.md)
in [gweather-locations](https://gitlab.gnome.org/GNOME/gweather-locations) for [gnome-weather](https://gitlab.gnome.org/GNOME/gnome-weather) and other GNOME apps.
For everywhere else, there is this script.
