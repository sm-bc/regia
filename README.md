# Regia

**English** · [Italiano](#italiano)

Free tool for **Windows 10 and 11** that analyzes the PC and optimizes it safely: preinstalled apps, startup, services, privacy, performance, latency, graphics, NVIDIA/AMD settings, drivers, cleanup and maintenance.
A single PowerShell file with a graphical interface, no installation. The interface is available in **English and Italian** (switch with the EN / IT button at the top right; the Windows language is used by default).

## Why it is safe
- **Dry-run mode** is on at startup: you see everything in a preview, nothing is changed.
- Before every real change: confirmation, an optional restore point and a backup.
- **Undo all** restores the original values.
- Store, Windows Update, Defender and system drivers are never touched.
- No telemetry: the program connects to the Internet only when you ask (drivers, advanced sensors) and to check for Regia updates.

## How to use
1. Download the latest `Regia_x.y.zip` from the **Releases** page (on the right).
2. Extract the `Regia` folder (do not run it from inside the zip).
3. Double-click `Avvia.cmd` and accept the administrator prompt.
4. Full guide in `LEGGIMI.txt` and `INIZIA_QUI.html` (Italian).

## Updates
At startup Regia checks whether a new version exists: an **Update** button appears at the bottom left. Before downloading it asks for confirmation, verifies the SHA-256 fingerprint and saves the previous version in the `Versioni` folder.

## Warning
Changing Windows settings always carries some risk. Use Dry-run mode, create the restore point and read the descriptions. The program is provided "as is", without warranty (see `LICENSE`).

## License
MIT. The optional downloadable components (LibreHardwareMonitor, PawnIO) have their own licenses.

---

<a name="italiano"></a>
# Regia (Italiano)

Programma gratuito per **Windows 10 e 11** che analizza il PC e lo ottimizza in modo sicuro: app preinstallate, avvio, servizi, privacy, prestazioni, latenza, grafica, impostazioni NVIDIA/AMD, driver, pulizia e manutenzione.
Un solo file PowerShell con interfaccia grafica, senza installazione. L'interfaccia è in **inglese e italiano** (si cambia con il pulsante EN / IT in alto a destra; di serie usa la lingua di Windows).

## Perché è sicuro
- **Modalità prova** accesa all'avvio: vedi tutto in anteprima, non viene modificato niente.
- Prima di ogni modifica vera: conferma, punto di ripristino (facoltativo) e backup.
- **Annulla tutto** rimette i valori originali.
- Store, Windows Update, Defender e driver di sistema non vengono toccati.
- Niente telemetria: il programma si collega a Internet solo quando lo chiedi (driver, sensori avanzati) e per cercare aggiornamenti di Regia.

## Come si usa
1. Scarica l'ultimo `Regia_x.y.zip` dalla pagina **Releases** (a destra).
2. Estrai la cartella `Regia` (non avviare dentro lo zip).
3. Doppio clic su `Avvia.cmd` e conferma la richiesta di amministratore.
4. Guida completa in `LEGGIMI.txt` e `INIZIA_QUI.html`.

## Aggiornamenti
All'avvio Regia controlla se c'è una versione nuova: compare il pulsante **Aggiorna** in basso a sinistra. Prima di scaricare chiede conferma, verifica l'impronta SHA-256 e salva la versione precedente nella cartella `Versioni`.
