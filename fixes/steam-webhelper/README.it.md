# Correttivo: la finestra nera di Steam

[English](README.md) · **Italiano**

Con Wine su macOS, Steam si apre ma la sua finestra resta nera. L'interfaccia di Steam è
Chromium (`steamwebhelper.exe`), e Chromium disegna in un processo GPU separato. Il driver di
Wine per macOS non riesce a mostrare in una finestra ciò che disegna un altro processo. Con
`--in-process-gpu` Chromium disegna invece dentro il processo del browser, che Wine riesce a
mostrare. Steam non ha un'opzione per passare questo parametro, quindi lo aggiunge questo
correttivo.

## Come funziona

- `proxy.c` produce un `winmm.dll` che Sommelier installa nella cartella `system32` della
  bottiglia, accanto al winmm di Wine (copiato come `winmm_orig.dll`). Ogni funzione di winmm
  viene inoltrata all'originale (`winmm.def`, generato dal `winmm.spec` di Wine).
- Un'impostazione di Wine valida per un solo programma lo carica **solo** per `steamwebhelper.exe`:
  `HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides` → `winmm = native,builtin`.
- All'avvio del processo del browser, la DLL fa restituire a `GetCommandLineW` la riga di
  comando con `--in-process-gpu` aggiunto. I sottoprocessi di Chromium (`--type=…`) e tutti gli
  altri programmi non vengono toccati. I file di Steam non vengono mai modificati, quindi Steam
  può continuare ad aggiornarsi da solo.

## Compilazione e pubblicazione

Lo compila GitHub Actions con mingw-w64 (`build.sh`,
[workflow](../../.github/workflows/steam-webhelper-fix.yml)). Un tag `steam-webhelper-v*`
pubblica la DLL come release. `sommelier` la scarica solo per le ricette con
`FIXES="steam-webhelper"` e ne controlla l'impronta SHA-256 fissata nello script.

`test/cmdline.c` è un programma di test: compilato come `steamwebhelper.exe` deve ricevere
`--in-process-gpu`, mentre `steamwebhelper.exe --type=gpu-process` e `other.exe` no.

## Licenze e condizioni

- Il correttivo è codice nostro, con licenza AGPL-3.0-or-later. L'elenco delle funzioni
  inoltrate in `winmm.def` proviene da Wine (LGPL-2.1-or-later), che è compatibile. Il runtime di
  mingw-w64 e libgcc inclusi nella DLL ne permettono la distribuzione con qualsiasi licenza.
- Sommelier distribuisce solo questa DLL, con il suo sorgente in questa cartella. Steam e Wine
  non vengono ridistribuiti: il correttivo si combina con loro solo sul computer dell'utente.
- I file di Steam non vengono modificati, ma il correttivo agisce dentro il processo del browser di Steam. Le condizioni d'uso di Steam (Steam Subscriber Agreement) limitano le modifiche al client: correttivi di compatibilità di questo tipo sono comuni negli strumenti che eseguono Steam con Wine, ma la decisione di usarlo spetta a te.

