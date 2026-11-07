# Sommelier — un gestore di Wine per macOS

[English](README.md) · **Italiano**

Sommelier installa, aggiorna ed esegue le **build ufficiali WineHQ per macOS** con un solo
comando, e offre un'app nativa per gestirle. È composto dal comando `sommelier`, dall'app
**Sommelier** e da un catalogo online di *ricette*: configurazioni pronte per Steam, giochi
classici, applicazioni .NET e altro. App e comando parlano italiano e inglese.

> Sommelier è un progetto indipendente, non affiliato a WineHQ né a CodeWeavers.
> Le build di Wine provengono da [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds),
> la fonte indicata dal [wiki di WineHQ](https://wiki.winehq.org/MacOS).

📖 **[Guida utente](docs/guida-utente.md)**: installazione, uso quotidiano, esempio con Steam, risoluzione dei problemi.
Disponibile anche come pagina web bilingue: [`docs/index.html`](docs/index.html).

## Installazione / aggiornamento (un solo comando)

```sh
git clone https://github.com/homecla/sommelier && cd sommelier
./install.sh                 # comando sommelier + app + Wine (ramo predefinito), o aggiorna quanto già installato
./install.sh --branch devel  # come sopra, usando devel come ramo predefinito
./install.sh --no-wine       # solo il comando e l'app
```

Requisiti: macOS 14 o successivo. Su Apple Silicon serve anche Rosetta 2, che l'installer
propone di installare.

## Riga di comando

```sh
sommelier status -r                 # versioni installate e aggiornamenti disponibili
sommelier install devel             # installa un ramo (stable | devel | staging)
sommelier update                    # aggiorna tutte le versioni installate
sommelier uninstall staging         # rimuove una versione
sommelier default staging           # cambia il ramo predefinito
sommelier bottle create Giochi      # nuova bottiglia (prefisso Wine separato)
sommelier run -B Giochi setup.exe   # esegue un programma nella bottiglia
sommelier winetricks -B Giochi corefonts vcrun2022
sommelier doctor                    # controlla Rosetta, permessi, dipendenze
sommelier help                      # elenco completo
```

La lingua segue quella del sistema. Per forzarla: `SOMMELIER_LANG=it` oppure `SOMMELIER_LANG=en`.

## Ricette

Una ricetta prepara una bottiglia: imposta la versione di Windows, installa i pacchetti
winetricks e applica modifiche al registro. Se serve, scarica e installa anche il programma
e lo aggiunge all'elenco della bottiglia con gli argomenti di avvio giusti.

```sh
sommelier bottle create Steam -P steam     # bottiglia nuova con la ricetta Steam
sommelier bottle apply Giochi giochi-classici
sommelier start -B Steam Steam             # avvia Steam con gli argomenti della ricetta
sommelier preset list | show steam
sommelier preset add https://…/mia.preset  # oppure un file locale
sommelier preset update                    # riscarica le ricette aggiunte da URL
sommelier preset remove mia
sommelier preset new mia                   # modello da modificare
```

Ricette integrate: `steam`, `giochi-classici`, `applicazioni`, `dotnet` (cartella `presets/`).
Le ricette personali stanno in `~/Library/Application Support/Sommelier/Presets/` e hanno la
precedenza su quelle integrate con lo stesso nome.

**Le ricette non vengono mai eseguite.** `sommelier` legge solo le chiavi note,
`INSTALLER_URL` deve essere https e gli argomenti non possono contenere caratteri speciali
della shell. Una ricetta con `INSTALLER_URL` scarica ed esegue un programma nella bottiglia,
quindi aggiungi solo ricette di fonti di cui ti fidi.

### Catalogo online

```sh
sommelier catalog                  # elenco (con stato installata / aggiornamento)
sommelier catalog url URL          # usa un altro catalogo (predefinito: homecla/sommelier-recipes)
sommelier catalog install steam    # scarica e verifica l'impronta SHA-256
sommelier catalog update           # aggiorna le ricette installate dal catalogo
```

Il catalogo ha un repository a parte, [`sommelier-recipes`](https://github.com/homecla/sommelier-recipes).

## L'app

- **Versioni**: installa, aggiorna o rimuove Wine Stable, Devel e Staging, e sceglie il ramo predefinito.
- **Ricette**: sfoglia il catalogo online, installa e aggiorna le ricette, gestisce quelle personali.
- **Bottiglie**: trascina dentro un file `.exe`/`.msi`/`.bat`/`.lnk` per eseguirlo, trova i
  programmi installati e apre gli strumenti di Wine (winecfg, regedit, Esplora risorse,
  prompt dei comandi, Pannello di controllo, winetricks, un Terminale macOS già pronto).
- **Attività**: il registro di ogni operazione.
- **Apri con…**: apri un `.exe` dal Finder con Sommelier e scegli la bottiglia.
- **Lingua**: automatica, inglese o italiano (Impostazioni, ⌘,).

## Dove finiscono le cose

| Cosa | Percorso |
|---|---|
| Wine (build ufficiali WineHQ) | `/Applications/Wine Stable.app`, `Wine Devel.app`, `Wine Staging.app` |
| Bottiglie, ricette, winetricks, cache | `~/Library/Application Support/Sommelier/` |
| App | `/Applications/Sommelier.app` (contiene una copia di `sommelier`) |
| Comando | `~/.local/bin/sommelier` |

## Sviluppo

- `sommelier`: bash 3.2, senza dipendenze. Il JSON viene letto con `osascript -l JavaScript`.
- `app/`: SwiftUI (macOS 14+). Si compila con `app/build-app.sh [destinazione]`.
  Con l'SDK di macOS 27 `@State` è una macro che richiede Xcode con la licenza accettata
  (`sudo xcodebuild -license`). Altrimenti lo script compila con l'SDK 26.x dei Command
  Line Tools, e l'app risultante funziona comunque su macOS 27.
- **Tutto è bilingue (inglese/italiano)**: documentazione, app, comando e ricette.
  Quando modifichi un testo, aggiorna entrambe le lingue.

## Software di terzi e marchi

Sommelier non include né ridistribuisce software di terzi. Su tua richiesta scarica ed esegue:

- **Wine**, le build ufficiali WineHQ per macOS ([Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)),
  distribuite dal progetto Wine con licenza [LGPL 2.1 o successiva](https://gitlab.winehq.org/wine/wine/-/blob/master/LICENSE);
- **winetricks**, con licenza LGPL 2.1 o successiva;
- i componenti e i programmi che scegli (per esempio font Microsoft, Visual C++, .NET o
  l'installer di Steam). Vengono scaricati dai server dei produttori e sono soggetti alle
  loro condizioni di licenza, che accetti installandoli.

Il marchio Wine è detenuto dalla [Software Freedom Conservancy](https://sfconservancy.org/) per conto del
progetto Wine. Windows, Steam, macOS, Apple Silicon e Rosetta sono marchi dei rispettivi titolari.
Sono citati solo per descrivere con cosa funziona Sommelier, che non è affiliato né
approvato da nessuno di loro. L'icona dell'app è un disegno originale.

## Licenza

Sommelier è software libero, distribuito con licenza
[GNU Affero General Public License v3.0 o successiva](LICENSE) (AGPL-3.0-or-later).
Le ricette integrate in `presets/` sono dedicate al pubblico dominio con
[CC0 1.0](LICENSES/CC0-1.0.txt), come quelle del
[catalogo ricette](https://github.com/homecla/sommelier-recipes).
Puoi usarlo, studiarlo, modificarlo e condividerlo. Se lo distribuisci, o metti a
disposizione di altri una versione modificata (anche via rete), devi pubblicarne il codice
sorgente con la stessa licenza. Il testo legale vincolante è quello inglese nel file `LICENSE`.

Wine è distribuito con licenza LGPL dal progetto Wine. Sommelier scarica soltanto le build
ufficiali e non include Wine.
