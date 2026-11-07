# Sommelier — a Wine manager for macOS

**English** · [Italiano](README.it.md)

Sommelier installs, updates and runs the **official WineHQ builds for macOS** with a single
command, and gives you a native app to manage them. It comes with the `sommelier`
command-line tool, the **Sommelier** app and an online catalog of *recipes*: ready-made
setups for Steam, classic games, .NET apps and more. The app and the command speak English
and Italian.

> Sommelier is an independent project. It is not affiliated with WineHQ or CodeWeavers.
> Wine builds come from [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds),
> the source linked from the [WineHQ wiki](https://wiki.winehq.org/MacOS).

📖 **User Guide: [homecla.github.io/sommelier](https://homecla.github.io/sommelier/)** (English/Italian).
Installation, everyday use, Steam example, troubleshooting. Also in Markdown: [docs/user-guide.md](docs/user-guide.md).

## Install / update (one command)

```sh
git clone https://github.com/homecla/sommelier && cd sommelier
./install.sh                 # sommelier command + app + Wine (default branch), or update what is installed
./install.sh --branch devel  # same, using devel as the default branch
./install.sh --no-wine       # only the command and the app
```

Requirements: macOS 14 or later. On Apple Silicon you also need Rosetta 2, and the installer
offers to install it.

## Command line

```sh
sommelier status -r                 # installed versions and available updates
sommelier install devel             # install a branch (stable | devel | staging)
sommelier update                    # update every installed version
sommelier uninstall staging         # remove a version
sommelier default staging           # change the default branch
sommelier bottle create Games       # new bottle (separate Wine prefix)
sommelier run -B Games setup.exe    # run a program inside a bottle
sommelier winetricks -B Games corefonts vcrun2022
sommelier doctor                    # check Rosetta, permissions, dependencies
sommelier help                      # full list
```

The language follows the system. To force it, set `SOMMELIER_LANG=en` or `SOMMELIER_LANG=it`.

## Recipes

A recipe prepares a bottle. It sets the Windows version, installs winetricks packages and
applies registry tweaks. When needed, it also downloads and installs the program and adds it
to the bottle's list with the right launch arguments.

```sh
sommelier bottle create Steam -P steam     # new bottle with the Steam recipe
sommelier bottle apply Games giochi-classici
sommelier start -B Steam Steam             # launch Steam with the recipe's arguments
sommelier preset list | show steam
sommelier preset add https://…/my.preset   # or a local file
sommelier preset update                    # re-download recipes added from a URL
sommelier preset remove my
sommelier preset new my                    # template to edit
```

Built-in recipes: `steam`, `giochi-classici` (classic games), `applicazioni` (apps),
`dotnet` (folder `presets/`). Personal recipes live in
`~/Library/Application Support/Sommelier/Presets/` and override built-in recipes with
the same name.

**Recipes are never executed.** `sommelier` reads only known keys, `INSTALLER_URL` must be
https, and arguments cannot contain shell special characters. A recipe with `INSTALLER_URL`
downloads and runs a program in the bottle, so only add recipes from sources you trust.

### Online catalog

```sh
sommelier catalog                  # list (with installed / update status)
sommelier catalog url URL          # use a different catalog (default: homecla/sommelier-recipes)
sommelier catalog install steam    # download and verify the SHA-256 fingerprint
sommelier catalog update           # update recipes installed from the catalog
```

The catalog lives in its own repository, [`sommelier-recipes`](https://github.com/homecla/sommelier-recipes).

## The app

- **Versions**: install, update or remove Wine Stable, Devel and Staging, and choose the default branch.
- **Recipes**: browse the online catalog, install and update recipes, manage personal ones.
- **Bottles**: drag a `.exe`/`.msi`/`.bat`/`.lnk` file in to run it, find installed programs,
  and open the Wine tools (winecfg, regedit, Explorer, command prompt, Control Panel,
  winetricks, a macOS Terminal ready to use).
- **Activity**: the log of every operation.
- **Open with…**: open a `.exe` from Finder with Sommelier and pick the bottle.
- **Language**: automatic, English or Italian (Settings, ⌘,).

## Where things go

| What | Path |
|---|---|
| Wine (official WineHQ builds) | `/Applications/Wine Stable.app`, `Wine Devel.app`, `Wine Staging.app` |
| Bottles, recipes, winetricks, cache | `~/Library/Application Support/Sommelier/` |
| App | `/Applications/Sommelier.app` (contains a copy of `sommelier`) |
| Command | `~/.local/bin/sommelier` |

## Development

- `sommelier`: bash 3.2 with no dependencies. JSON is read with `osascript -l JavaScript`.
- `app/`: SwiftUI (macOS 14+). Build with `app/build-app.sh [destination]`.
  With the macOS 27 SDK, `@State` is a macro that needs Xcode with its license accepted
  (`sudo xcodebuild -license`). Without it, the script builds against the Command Line
  Tools' 26.x SDK, and the resulting app runs fine on macOS 27.
- **Everything is bilingual (English/Italian)**: documentation, app, command and recipes.
  When you change a text, update both languages.

## Third-party software and trademarks

Sommelier does not include or redistribute any third-party software. At your request it
downloads and runs:

- **Wine**, the official WineHQ builds for macOS ([Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)),
  distributed by the Wine project under the [LGPL 2.1 or later](https://gitlab.winehq.org/wine/wine/-/blob/master/LICENSE);
- **winetricks**, under the LGPL 2.1 or later;
- the components and programs you choose (for example Microsoft fonts, Visual C++, .NET,
  or the Steam installer). They are downloaded from their vendors' servers and are subject
  to the vendors' license terms, which you accept by installing them.

The Wine trademark is held by the [Software Freedom Conservancy](https://sfconservancy.org/) on behalf of the
Wine project. Windows, Steam, macOS, Apple Silicon and Rosetta are trademarks of their respective
owners. They are mentioned only to describe what Sommelier works with; Sommelier is not
affiliated with or endorsed by any of them. The app icon is original artwork.

## License

Sommelier is free software, released under the
[GNU Affero General Public License v3.0 or later](LICENSE) (AGPL-3.0-or-later).
The built-in recipes in `presets/` are dedicated to the public domain under
[CC0 1.0](LICENSES/CC0-1.0.txt), like those in the
[recipe catalog](https://github.com/homecla/sommelier-recipes).
You can use, study, modify and share it. If you distribute it, or make a modified version
available to others (including over a network), you must release your source code under
the same license.

Wine is distributed under the LGPL by the Wine project. Sommelier only downloads the
official builds and does not include Wine.
