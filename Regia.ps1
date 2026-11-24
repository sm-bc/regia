<#
================================================================================
  REGIA  -  versione 3.9
  (fino alla 3.1 si chiamava "Ottimizza Windows")
  Analisi e ottimizzazione di Windows 10 e 11 con interfaccia grafica (WPF).
  Funziona su qualsiasi PC: portatili e fissi, con scheda video NVIDIA, AMD o Intel.
  Le voci che non riguardano il PC in uso non vengono mostrate.

  Novità della 3.0: sezione "Driver video" separata dagli altri driver, impostazioni AMD
  (libreria ufficiale ADLX), scelta della versione del driver AMD, installazione di più driver
  insieme, barra di avanzamento, menu a tendina nelle voci con più scelte, sezione
  "App installate" con disinstallazione completa, sei nuovi profili.
  Novità della 3.1: punto di ripristino consigliato ma facoltativo (viene sempre chiesto),
  sezione "Latenza e reattività" (accessori, USB/Bluetooth, rete, processore, memoria, timer)
  con misura del ping verso router e DNS.
  Novità della 3.2: proposta di riavvio dal programma (con avvisi sul lavoro aperto e pulsante
  "Riavvia ora"), pulsante "Riavvia il PC" nella barra laterale, icone delle app nella sezione
  "App installate", icona propria del programma.
  Novità della 3.3: ruota di attesa accanto alla barra di avanzamento, sezioni della barra laterale
  e della Panoramica che si aprono e chiudono, dati in tempo reale nella Panoramica (carico,
  frequenza, memoria, scheda NVIDIA, batteria), preset della scheda video separati dai profili
  (Prestazioni, Bilanciato, Qualità), tasti "Pulizia sicura" e "Pulizia accurata".
  Novità della 3.4: sensori avanzati facoltativi (temperatura e consumo del processore, grafiche AMD/Intel)
  con LibreHardwareMonitor e il driver PawnIO, scaricati solo dopo conferma e controllati con SHA-256.
  Novità della 3.5: rete e dischi in tempo reale, report sullo stato del PC dopo la scansione (con simboli),
  opzioni avanzate NVIDIA (come NVIDIA Profile Inspector), file per il feedback degli amici.
  Novità della 3.6: opzione DLSS "Forced preset letter" (lettera del preset) tra le opzioni avanzate NVIDIA, impaginazione rivista.
  Novità della 3.6.1: piani energetici e programmi di avvio già disattivati non sono più "da modificare" (solo suggerimenti); i Widget non installati risultano a posto.
  Novità della 3.10: "Annulla tutto" apre l'elenco delle voci modificate con un interruttore per ognuna:
  si annullano solo quelle accese, le altre restano e si possono annullare più tardi.
  Novità della 3.9: pulsante God Mode; sezione "Pulizia registro" (solo voci di programmi cancellati, con backup .reg e Annulla);
  nuove voci di Prestazioni (ritardo dei menu, ultimo accesso NTFS, precedenza ai programmi, Power Throttling in Avanzate).
  Novità della 3.8.2: versione di prova per verificare gli aggiornamenti online (nessun cambiamento di funzioni).
  Novità della 3.8: programma tradotto in inglese (di serie con Windows non italiano) con selettore English/Italiano in alto a destra.
  Novità della 3.7: avviso di Modalità prova all'apertura, nuovi strumenti in Manutenzione (salute dischi, controllo disco, report batteria ed energia, Store, icone, ora, RAM, rete),
  controllo automatico degli aggiornamenti all'avvio e pulsante "Aggiorna" (vedi PUBBLICARE_ONLINE.txt).

  Come si avvia: doppio clic su "Avvia.cmd" (chiede i permessi di amministratore).

  Struttura del file:
    1. Controlli iniziali (amministratore, modalità STA)
    2. Percorsi, log e utilità generiche
    3. Funzioni di supporto (registro, servizi, energia, file, processi)
    4. CATALOGO delle voci   <-- per aggiungere una voce basta lavorare qui
    5. Motori: leggono / applicano / annullano ogni tipo di voce
    6. Scansione, anteprima, applicazione, "Annulla tutto"
    7. Interfaccia grafica (XAML) e collegamento dei pulsanti

  Sicurezza:
    - la scansione legge soltanto, non modifica niente;
    - "Modalità prova" (attiva all'avvio): mostra e scrive nel log, ma non tocca niente;
    - prima di applicare: anteprima, punto di ripristino, backup JSON dei valori
      originali (cartella Dati\Backup), log di tutto in Dati\Log;
    - "Annulla tutto" rimette i valori salvati nei backup, dal più recente al più vecchio
      (si può scegliere quali voci annullare);
    - Store, Windows Update, Defender, driver e componenti di sistema sono protetti.
================================================================================
#>

$ErrorActionPreference = 'Continue'

# ==============================================================================
# 1. CONTROLLI INIZIALI
# ==============================================================================

# Servono i permessi di amministratore (servizi, HKLM, punto di ripristino).
$identita   = [Security.Principal.WindowsIdentity]::GetCurrent()
$principale = New-Object Security.Principal.WindowsPrincipal($identita)
if (-not $principale.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("Servono i permessi di amministratore.`nAvvia il programma con un doppio clic su Avvia.cmd.", 'Regia', 'OK', 'Warning')
    exit 1
}

# WPF funziona solo in modalità STA: se manca, il programma si riavvia da solo.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ==============================================================================
# 2. PERCORSI, LOG E UTILITÀ GENERICHE
# ==============================================================================

$Script:Versione       = '3.10'
$Script:FileProgramma  = $PSCommandPath
$Script:CartellaBase   = Split-Path -Parent $PSCommandPath
$Script:CartellaDati   = Join-Path $Script:CartellaBase 'Dati'
$Script:AvvisoAvvio    = ''
# Numero di build di Windows: 19041+ = Windows 10, 22000+ = Windows 11. Serve a nascondere le voci non adatte.
$Script:Build = 0
try { $Script:Build = [int][Environment]::OSVersion.Version.Build } catch { }
# Se la cartella del programma non è scrivibile (chiavetta protetta, CD, cartella di rete) i dati
# vanno nella cartella dell'utente, così il programma funziona lo stesso.
try {
    if (-not (Test-Path -LiteralPath $Script:CartellaDati)) { New-Item -ItemType Directory -Path $Script:CartellaDati -ErrorAction Stop | Out-Null }
    $prova = Join-Path $Script:CartellaDati '.scrittura'
    [IO.File]::WriteAllText($prova, 'ok'); Remove-Item -LiteralPath $prova -Force -ErrorAction Stop
} catch {
    $Script:CartellaDati = Join-Path $env:LOCALAPPDATA 'Regia\Dati'
    $Script:AvvisoAvvio = "La cartella del programma non è scrivibile: log, backup e profili vengono salvati in $Script:CartellaDati"
}
$Script:CartellaBackup = Join-Path $Script:CartellaDati 'Backup'
$Script:CartellaLog    = Join-Path $Script:CartellaDati 'Log'
foreach ($c in @($Script:CartellaDati, $Script:CartellaBackup, $Script:CartellaLog)) {
    if (-not (Test-Path -LiteralPath $c)) { New-Item -ItemType Directory -Path $c -Force | Out-Null }
}

# ---------- Impostazioni del programma (Dati\impostazioni.json) ----------
#   Tema                   'Scuro' (di serie) oppure 'Chiaro'
#   Computer               nome del PC su cui la cartella Dati è stata usata per la prima volta
#   PianiPrestazioniExtra  GUID di piani energetici personalizzati che valgono come "Prestazioni"
$Script:FileImpostazioni = Join-Path $Script:CartellaDati 'impostazioni.json'

function Leggi-Impostazioni {
    $i = @{ Tema = 'Scuro'; Computer = ''; PianiPrestazioniExtra = @() }
    try {
        if (Test-Path -LiteralPath $Script:FileImpostazioni) {
            $j = Get-Content -LiteralPath $Script:FileImpostazioni -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $i[$p.Name] = $p.Value }
        }
    } catch { }
    return $i
}

function Salva-Impostazione([string]$Nome, $Valore) {
    $i = Leggi-Impostazioni
    $i[$Nome] = $Valore
    try { $i | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Script:FileImpostazioni -Encoding UTF8 } catch { }
}

# ==============================================================================
# TRADUZIONE (English / Italiano)
# Il programma è scritto in italiano: i testi originali restano la "chiave". Con la lingua inglese ogni
# testo mostrato passa da Tr, che lo cerca nel dizionario qui sotto (una riga = italiano <TAB> inglese;
# "\n" = a capo; {} o {0} = valori che cambiano, es. numeri e nomi). Se un testo non è nel dizionario
# resta in italiano. Lingua: Dati\impostazioni.json ("Lingua": "en" o "it"); se manca si usa la lingua di Windows.
# Per controllare cosa manca: imposta la variabile d'ambiente REGIA_TRLOG su un file di testo.
# ==============================================================================
$Script:Lingua = 'it'
try {
    $lg = [string](Leggi-Impostazioni).Lingua
    if ($env:REGIA_LANG -eq 'en' -or $env:REGIA_LANG -eq 'it') { $lg = $env:REGIA_LANG }
    if ($lg -eq 'en' -or $lg -eq 'it') { $Script:Lingua = $lg }
    elseif ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'it') { $Script:Lingua = 'en' }
} catch { }
$Script:TrDiz = $null
$Script:TrModelli = $null
$Script:TrCache = @{}

function Carica-Traduzioni {
    $Script:TrDiz = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $Script:TrModelli = New-Object System.Collections.ArrayList
    $tok = [regex]'\{(\d*)(?::[^}]*)?\}'
    foreach ($riga in ($Script:DizionarioEn -split '\r?\n')) {
        $i = $riga.IndexOf("`t")
        if ($i -lt 1) { continue }
        $k = $riga.Substring(0, $i).Replace('\n', "`n"); $v = $riga.Substring($i + 1).Replace('\n', "`n")
        if (-not $tok.IsMatch($k)) { $Script:TrDiz[$k] = $v; continue }
        $re = '^'; $pos = 0; $seq = 0; $etichette = New-Object System.Collections.ArrayList; $lit = ''
        foreach ($m in $tok.Matches($k)) {
            $pezzo = $k.Substring($pos, $m.Index - $pos)
            if (-not $lit -and $pezzo.Length -ge 3) { $lit = $pezzo }
            $re += [regex]::Escape($pezzo) + '(.*?)'
            if ($m.Groups[1].Value -eq '') { [void]$etichette.Add($seq); $seq++ } else { [void]$etichette.Add([int]$m.Groups[1].Value) }
            $pos = $m.Index + $m.Length
        }
        $coda = $k.Substring($pos); if (-not $lit -and $coda.Length -ge 3) { $lit = $coda }
        $re += [regex]::Escape($coda) + '$'
        [void]$Script:TrModelli.Add(@{ Re = (New-Object regex($re, 'Singleline')); Lit = $lit; Lun = $k.Length; Etichette = @($etichette); En = $v })
    }
    $ordinati = @($Script:TrModelli | Sort-Object { $_.Lun } -Descending)
    $Script:TrModelli = New-Object System.Collections.ArrayList
    [void]$Script:TrModelli.AddRange($ordinati)
}

function Tr-Modello($M, [string]$Testo) {
    $mm = $M.Re.Match($Testo)
    if (-not $mm.Success) { return $null }
    $tok = [regex]'\{(\d*)(?::[^}]*)?\}'
    $seq = New-Object psobject -Property @{ N = 0 }
    return $tok.Replace($M.En, [System.Text.RegularExpressions.MatchEvaluator] {
        param($x)
        $lab = $(if ($x.Groups[1].Value -eq '') { $seq.N++; $seq.N - 1 } else { [int]$x.Groups[1].Value })
        $gi = [array]::IndexOf(@($M.Etichette), $lab)
        if ($gi -lt 0) { return $x.Value }
        return (Tr $mm.Groups[$gi + 1].Value)
    })
}

function Tr([string]$Testo) {
    if ($Script:Lingua -ne 'en' -or [string]::IsNullOrEmpty($Testo)) { return $Testo }
    if ($null -eq $Script:TrDiz) { Carica-Traduzioni }
    $v = $null
    if ($Script:TrDiz.TryGetValue($Testo, [ref]$v)) { return $v }
    if ($Script:TrCache.ContainsKey($Testo)) { return $Script:TrCache[$Testo] }
    $r = Tr-Calcola $Testo
    if ($Script:TrCache.Count -lt 6000) { $Script:TrCache[$Testo] = $r }
    return $r
}

function Tr-Calcola([string]$Testo) {
    $pulito = $Testo.Trim()
    if ($pulito -eq '') { return $Testo }
    if ($pulito -ne $Testo) {
        $x = Tr $pulito
        if ($x -ne $pulito) { return $Testo.Substring(0, $Testo.IndexOf($pulito[0])) + $x + $Testo.Substring($Testo.LastIndexOf($pulito[$pulito.Length - 1]) + 1) }
    }
    foreach ($m in $Script:TrModelli) {
        if ($m.Lit -and $Testo.IndexOf($m.Lit, [StringComparison]::Ordinal) -lt 0) { continue }
        $r = Tr-Modello $m $Testo
        if ($null -ne $r) { return $r }
    }
    $uni = $Testo.Replace("`r`n", "`n")
    if ($uni.Contains("`n")) {
        $cambiato = $false
        $righe = foreach ($r in ($uni -split "`n")) { $x = Tr $r; if ($x -ne $r) { $cambiato = $true }; $x }
        if ($cambiato) { return ($righe -join "`n") }
    }
    if ($env:REGIA_TRLOG -and $Testo -match '[A-Za-zàèéìòù]{3}') { try { Add-Content -LiteralPath $env:REGIA_TRLOG -Value ($Testo.Replace("`r", '').Replace("`n", '\n')) -Encoding UTF8 } catch { } }
    return $Testo
}

# Traduce i testi fissi di una finestra o di un pannello (TextBlock, pulsanti, suggerimenti, intestazioni di tabella).
# I testi collegati a dati (Binding) non si toccano: li traducono le proprietà "...Vis" delle righe.
function Traduci-Albero($Radice) {
    if ($Script:Lingua -ne 'en' -or $null -eq $Radice) { return }
    $coda = New-Object System.Collections.Generic.Queue[object]
    $coda.Enqueue($Radice)
    while ($coda.Count -gt 0) {
        $e = $coda.Dequeue()
        if ($e -is [System.Windows.Window]) { try { $e.Title = Tr $e.Title } catch { } }
        if ($e -is [System.Windows.FrameworkElement] -and $e.ToolTip -is [string] -and $e.ToolTip) { try { $e.ToolTip = Tr ([string]$e.ToolTip) } catch { } }
        if ($e -is [System.Windows.Controls.TextBlock]) {
            if (-not [System.Windows.Data.BindingOperations]::IsDataBound($e, [System.Windows.Controls.TextBlock]::TextProperty) -and $e.Text -and $e.Inlines.Count -le 1) { $e.Text = Tr $e.Text }
        } elseif ($e -is [System.Windows.Controls.ContentControl]) {
            if ($e.Content -is [string] -and $e.Content -and -not [System.Windows.Data.BindingOperations]::IsDataBound($e, [System.Windows.Controls.ContentControl]::ContentProperty)) { try { $e.Content = Tr ([string]$e.Content) } catch { } }
        } elseif ($e -is [System.Windows.Controls.DataGrid]) {
            foreach ($c in $e.Columns) { if ($c.Header -is [string] -and $c.Header) { $c.Header = Tr ([string]$c.Header) } }
        }
        if ($e -is [System.Windows.DependencyObject]) { foreach ($f in [System.Windows.LogicalTreeHelper]::GetChildren($e)) { if ($f -is [System.Windows.DependencyObject]) { $coda.Enqueue($f) } } }
    }
}

$Script:DizionarioEn = @'
Servono i permessi di amministratore.\nAvvia il programma con un doppio clic su Avvia.cmd.	Administrator permissions are required.\nStart the program by double-clicking Avvia.cmd.
La cartella del programma non è scrivibile: log, backup e profili vengono salvati in {}	The program folder is not writable: log, backups and profiles are saved in {}
La cartella Dati proviene da un altro PC ({}): i suoi backup vengono ignorati, i profili personali restano utilizzabili. 	The Dati folder comes from another PC ({}): its backups are ignored, personal profiles can still be used.
{}  (riga {})	{}  (line {})
Errore imprevisto: {}	Unexpected error: {}
Si è verificato un errore:\n\n{}\n\nI dettagli sono nel log.	An error occurred:\n\n{}\n\nDetails are in the log.
{} byte	{} bytes
Automatico	Automatic
AutomaticoRitardato	AutomaticDelayed
Automatico (ritardato)	Automatic (delayed)
Manuale	Manual
Disattivato	Disabled
Sistema	System
Il servizio {} è protetto e non viene modificato.	The service {} is protected and is not modified.
Tipo di avvio non valido per {}: {}	Invalid startup type for {}: {}
sc.exe ha restituito il codice {} per {}: {}	sc.exe returned code {} for {}: {}
(sconosciuto)	(unknown)
Modalità di risparmio energia non impostata (codice {}).	Power-saving mode not set (code {}).
Modalità di risparmio energia non disponibile: {}	Power-saving mode not available: {}
massima efficienza	maximum efficiency
prestazioni migliori	better performance
prestazioni bilanciate	balanced performance
equilibrata	balanced
powercfg /setactive {} non riuscito (codice {}).	powercfg /setactive {} failed (code {}).
Il piano 'Prestazioni elevate' non è presente: provo a ricrearlo dal modello di Windows.	The 'High performance' plan is missing: trying to recreate it from the Windows template.
Piano 'Prestazioni elevate' non attivabile: uso Bilanciato + modalità 'Prestazioni migliori'.	Plan 'High performance' cannot be activated: using Balanced + 'Better performance' mode.
 · modalità {}	 · {} mode
Prestazioni	Performance
Bilanciato	Balanced
Efficienza	Efficiency
A posto	OK
Percorso non sicuro, pulizia rifiutata: {}	Unsafe path, cleanup refused: {}
powercfg /setacvalueindex non riuscito (codice {}).	powercfg /setacvalueindex failed (code {}).
Personalizzato	Custom
basso	low
Non disponibile	Not available
Non presente	Not present
valore {}	value {}
Da modificare	To change
Predefinito	Default
Rete	Network
Latenza	Latency
Mai spenti	Never turned off
Spegnibili (Windows)	Can be turned off (Windows)
Impostazioni di risparmio dei dispositivi non leggibili su questo PC (WMI: {}): le voci relative non vengono mostrate.	Device power-saving settings cannot be read on this PC (WMI: {}): the related items are not shown.
Non leggibile su questo PC	Cannot be read on this PC
Nessun dispositivo	No devices
Mai spenti (tutti i {})	Never turned off (all {})
{} di {} possono essere spenti	{} of {} can be turned off
Attivato	Enabled
Attivato su {} di {} schede	Enabled on {} of {} adapters
bcdedit non leggibile (codice {})	bcdedit cannot be read (code {})
Gaming	Gaming
Produttivita	Productivity
Design	Design
Notizie e Meteo (Bing)	News and Weather (Bing)
Debloat app	App debloat
App di notizie e meteo preinstallate. Le stesse informazioni sono disponibili nel browser.	Preinstalled news and weather apps. The same information is available in the browser.
Suggerimenti, Guida e Hub di Feedback	Tips, Get Help and Feedback Hub
App di aiuto e per inviare commenti a Microsoft. Non servono al funzionamento di Windows.	Help apps and apps for sending feedback to Microsoft. Windows does not need them to work.
Microsoft Solitaire Collection	Microsoft Solitaire Collection
Raccolta di giochi di carte con pubblicità.	Collection of card games with ads.
Clipchamp (editor video)	Clipchamp (video editor)
Editor video online di Microsoft. Rimuovilo se non lo usi.	Microsoft's online video editor. Remove it if you don't use it.
Microsoft 365 (Office Hub)	Microsoft 365 (Office Hub)
È solo un'app-vetrina per Microsoft 365. Word, Excel ecc. se installati NON vengono toccati.	It is only a showcase app for Microsoft 365. Word, Excel etc., if installed, are NOT touched.
Power Automate	Power Automate
Strumento per automatizzare attività. Serve solo a chi lo usa esplicitamente.	Tool for automating tasks. Only useful to those who use it explicitly.
Microsoft To Do	Microsoft To Do
App per le liste di cose da fare. Rimuovila se non la usi.	To-do list app. Remove it if you don't use it.
Ricerca Bing (app)	Bing Search (app)
Componente di ricerca web Bing. La ricerca di file e app di Windows continua a funzionare.	Bing web search component. Searching for files and apps in Windows keeps working.
Mappe	Maps
App Mappe di Windows (dismessa da Microsoft).	Windows Maps app (discontinued by Microsoft).
Dev Home	Dev Home
Pannello per sviluppatori (dismesso da Microsoft).	Developer dashboard (discontinued by Microsoft).
Lettore multimediale e Film e TV	Media Player and Movies & TV
Lettore predefinito di musica e video. Se lo usi per aprire MP3/MP4, NON rimuoverlo (oppure usa VLC o simili).	Default music and video player. If you use it to open MP3/MP4 files, do NOT remove it (or use VLC or similar).
Registratore di suoni, Sveglie e orologio	Sound Recorder, Alarms & Clock
Piccole app di utilità. Rimuovile solo se non usi sveglie, timer o registrazioni audio.	Small utility apps. Remove them only if you don't use alarms, timers or audio recordings.
Contatti (People)	Contacts (People)
Vecchia rubrica di Windows.	Old Windows address book.
Assistenza rapida	Quick Assist
Permette a qualcuno di controllare il PC a distanza per aiutarti. Rimuovila se non la usi.	Lets someone control your PC remotely to help you. Remove it if you don't use it.
Copilot	Copilot
medio	medium
Assistente AI di Microsoft. Non è in nessun profilo: spuntalo tu se non lo usi.	Microsoft's AI assistant. It is in no profile: tick it yourself if you don't use it.
Nuovo Outlook e Posta/Calendario	New Outlook and Mail/Calendar
App di posta di Windows. Rimuovile solo se usi un altro programma di posta (o la posta dal browser).	Windows mail apps. Remove them only if you use another mail program (or webmail).
Microsoft Teams (personale)	Microsoft Teams (personal)
Teams per uso personale. Rimuovilo solo se non lo usi per lavoro o scuola.	Teams for personal use. Remove it only if you don't use it for work or school.
Collegamento al telefono	Phone Link
Collega lo smartphone al PC (notifiche, foto, SMS). Senza di essa queste funzioni spariscono.	Links your smartphone to the PC (notifications, photos, SMS). Without it these features disappear.
App Xbox	Xbox app
Necessaria per Game Pass e per i giochi del Microsoft Store. La Game Bar e l'accesso Xbox nei giochi non vengono toccati.	Required for Game Pass and Microsoft Store games. The Game Bar and Xbox sign-in inside games are not touched.
Telemetria (Esperienze utente connesse)	Telemetry (Connected User Experiences)
Servizi	Services
Servizio	Service
Invia a Microsoft dati di utilizzo e diagnostica. Disattivarlo non ha effetti sul funzionamento del PC.	Sends usage and diagnostic data to Microsoft. Disabling it has no effect on how the PC works.
Instradamento messaggi push WAP	WAP Push Message Routing
Servizio legato alla telemetria e alla gestione aziendale dei dispositivi. Inutile su un PC personale.	Service related to telemetry and enterprise device management. Useless on a personal PC.
Modalità demo per negozi	Retail demo mode
Usato solo dai PC esposti nei negozi.	Only used by PCs on display in shops.
Gestione mappe scaricate	Downloaded maps manager
Aggiorna le mappe offline dell'app Mappe. Inutile se non usi mappe offline.	Updates the offline maps of the Maps app. Useless if you don't use offline maps.
Invio e ricezione di fax tramite modem.	Sending and receiving faxes through a modem.
Registro di sistema remoto	Remote Registry
Permette di modificare il registro da un altro PC. Per sicurezza deve restare disattivato (lo è già in Windows 11).	Allows the registry to be modified from another PC. For security it must stay disabled (it already is in Windows 11).
Segnalazione errori di Windows	Windows Error Reporting
Raccoglie e invia a Microsoft i rapporti sugli arresti anomali dei programmi. Disattivato non vengono più creati.	Collects and sends Microsoft reports about program crashes. When disabled they are no longer created.
Servizio di localizzazione	Location service
Se è disattivato, app come Meteo, Mappe e 'Trova il mio dispositivo' non sanno dove sei. 'Manuale' = parte solo quando serve. La privacy della posizione si gestisce comunque da Impostazioni.	When disabled, apps such as Weather, Maps and 'Find my device' do not know where you are. 'Manual' = starts only when needed. Location privacy can still be managed from Settings.
Servizio telefonico	Phone service
Usato da 'Collegamento al telefono' per le chiamate. 'Manuale' = parte solo quando serve, non pesa sul sistema.	Used by 'Phone Link' for calls. 'Manual' = starts only when needed, no load on the system.
Servizi Xbox (accesso, salvataggi, rete, controller)	Xbox services (sign-in, saves, network, controllers)
Se disattivati, Game Pass, app Xbox, salvataggi nel cloud e alcuni controller Xbox non funzionano. In 'Manuale' partono solo quando un gioco li usa: nessun peso sul sistema.	If disabled, Game Pass, the Xbox app, cloud saves and some Xbox controllers do not work. In 'Manual' they start only when a game uses them: no load on the system.
SysMain (Superfetch)	SysMain (Superfetch)
Precarica in memoria i programmi che usi spesso. Con molta RAM e SSD veloci aiuta l'apertura delle app; disattivarlo serve solo su PC con poca RAM o dischi meccanici.	Preloads the programs you use often into memory. With plenty of RAM and fast SSDs it helps apps open faster; disabling it is only useful on PCs with little RAM or hard drives.
Windows Search (indicizzazione)	Windows Search (indexing)
Indicizza i file per trovarli subito. Se è disattivato, la ricerca nel menu Start, in Esplora file e in Outlook diventa lenta o incompleta. Il consiglio è tenerlo acceso.	Indexes files so they can be found instantly. If disabled, search in the Start menu, File Explorer and Outlook becomes slow or incomplete. We recommend leaving it on.
Spooler di stampa	Print spooler
Gestisce la stampa. Disattivalo SOLO se non stampi mai: smettono di funzionare anche 'Stampa su PDF' e la scansione da stampanti multifunzione.	Handles printing. Disable it ONLY if you never print: 'Print to PDF' and scanning from multifunction printers stop working too.
Dati di diagnostica al minimo	Minimal diagnostic data
Privacy	Privacy
Registro	Registry
Minimo (solo obbligatori)	Minimum (required only)
Scelta dell'utente	User's choice
Limita i dati inviati a Microsoft al minimo consentito dalle edizioni Home e Pro. In Impostazioni comparirà la scritta 'alcune impostazioni sono gestite dall'organizzazione': è normale.	Limits the data sent to Microsoft to the minimum allowed by Home and Pro editions. Settings will show 'some settings are managed by your organization': this is normal.
ID pubblicità personalizzata	Personalized advertising ID
Spento	Off
Acceso	On
Codice che le app usano per mostrarti pubblicità mirata. Spegnendolo la pubblicità resta, ma non è personalizzata.	Code that apps use to show you targeted ads. When turned off, ads still appear but are not personalized.
Suggerimenti e app promosse in Start e Impostazioni	Suggestions and promoted apps in Start and Settings
Spenti	Off
Accesi	On
Toglie le app 'consigliate' nel menu Start, i contenuti suggeriti in Impostazioni e l'installazione automatica di app promozionali.	Removes 'recommended' apps in the Start menu, suggested content in Settings and the automatic installation of promotional apps.
Curiosità e suggerimenti nella schermata di blocco	Fun facts and tips on the lock screen
Toglie testi, curiosità e pubblicità sopra l'immagine della schermata di blocco. L'immagine resta.	Removes texts, fun facts and ads over the lock screen picture. The picture stays.
Esperienze personalizzate con i dati di diagnostica	Personalized experiences using diagnostic data
Spente	Off
Accese	On
Impedisce a Microsoft di usare i dati di diagnostica per suggerimenti e pubblicità su misura.	Prevents Microsoft from using diagnostic data for tailored suggestions and ads.
Cronologia attività	Activity history
spenta	off
Non impostata	Not set
Windows smette di registrare quali app e documenti apri (e di inviarlo al cloud).	Windows stops recording which apps and documents you open (and sending it to the cloud).
Richieste di feedback	Feedback requests
Automatiche	Automatic
Windows non ti chiederà più di dare un voto o un commento.	Windows will no longer ask you to give a rating or comment.
Widget (notizie sulla barra delle applicazioni) - da fare a mano	Widgets (news on the taskbar) - to do by hand
Windows protegge questa impostazione e non permette ai programmi di cambiarla. Fallo tu: Impostazioni > Personalizzazione > Barra delle applicazioni > Widget: Disattivato.	Windows protects this setting and does not let programs change it. Do it yourself: Settings > Personalization > Taskbar > Widgets: Off.
Il pannello Widget (meteo e notizie) resta attivo in background. Windows protegge questa impostazione (driver UCPD), quindi il programma la legge soltanto. Per spegnerla: Impostazioni > Personalizzazione > Barra delle applicazioni > Widget: Disattivato.	The Widgets panel (weather and news) stays active in the background. Windows protects this setting (UCPD driver), so the program only reads it. To turn it off: Settings > Personalization > Taskbar > Widgets: Off.
Notifiche: suggerimenti e consigli di Windows	Notifications: Windows tips and suggestions
Toglie le notifiche con consigli, 'completa la configurazione' e la schermata di benvenuto dopo gli aggiornamenti. Le notifiche delle tue app restano.	Removes notifications with tips, 'finish setting up your device' and the welcome screen after updates. Your apps' notifications stay.
Notifiche delle app (interruttore generale)	App notifications (master switch)
Tutte spente	All off
Disconnessione	Sign-out
Se le notifiche sono tutte spente perdi anche avvisi utili (promemoria, Defender, batteria). Il consiglio è tenerle accese e togliere solo i suggerimenti. Per i giochi c'è già 'Non disturbare' automatico.	If notifications are all off you also lose useful alerts (reminders, Defender, battery). We recommend keeping them on and removing only the suggestions. For games there is already automatic 'Do not disturb'.
Risultati web (Bing) nella ricerca di Start	Web results (Bing) in Start search
La ricerca di Start mostra solo app, file e impostazioni del PC, senza risultati web. Su alcune versioni di Windows spegne anche i suggerimenti di ricerca recenti.	Start search shows only apps, files and settings of the PC, with no web results. On some Windows versions it also turns off recent search suggestions.
Recall e istantanee AI	Recall and AI snapshots
Bloccati	Blocked
Non impostato	Not set
Riavvio	Restart
Impedisce a Windows di salvare istantanee dello schermo per la funzione Recall. Recall esiste solo sui PC Copilot+; sugli altri la voce non ha effetti visibili.	Prevents Windows from saving screen snapshots for the Recall feature. Recall only exists on Copilot+ PCs; on other PCs this item has no visible effect.
Piano energetico: Prestazioni elevate	Power plan: High performance
Energia	Power
Prestazioni elevate	High performance
CPU e GPU restano pronte al massimo: ideale su un PC fisso o con l'alimentatore collegato. A batteria consuma e scalda di più. Se il piano manca viene ricreato; se Windows non lo permette (portatili con 'Modern Standby') si usa 'Bilanciato' con modalità 'Prestazioni migliori'. Valgono come 'a posto' anche 'Prestazioni eccellenti' e i piani personalizzati elencati in Dati\impostazioni.json. Nota: i programmi del produttore del portatile (Lenovo Vantage/Legion, Armoury Crate, MSI Center, Dell/Alienware...) possono cambiare il piano da soli: se 'torna indietro', disattiva lì il cambio automatico.	CPU and GPU stay ready at maximum: ideal on a desktop PC or when plugged in. On battery it uses and heats more. If the plan is missing it is recreated; if Windows doesn't allow it (laptops with 'Modern Standby') 'Balanced' with 'Better performance' mode is used. 'Ultimate performance' and the custom plans listed in Dati\impostazioni.json also count as 'OK'. Note: laptop manufacturer programs (Lenovo Vantage/Legion, Armoury Crate, MSI Center, Dell/Alienware...) can change the plan on their own: if it 'goes back', turn off the automatic switch there.
Piano energetico: Bilanciato	Power plan: Balanced
Il piano standard di Windows: prestazioni piene quando servono, consumi bassi quando il PC è fermo. È la scelta migliore per l'uso quotidiano.	The standard Windows plan: full performance when needed, low consumption when the PC is idle. It is the best choice for everyday use.
Piano energetico: Massima efficienza	Power plan: Maximum efficiency
Bilanciato · massima efficienza	Balanced · maximum efficiency
Piano Bilanciato con la modalità 'Massima efficienza' di Windows 11: più autonomia e meno calore, prestazioni ridotte.	Balanced plan with the Windows 11 'Maximum efficiency' mode: more battery life and less heat, reduced performance.
Modalità gioco (Game Mode)	Game Mode
Attiva	On
Quando giochi, Windows dà priorità al gioco e rimanda aggiornamenti e attività in background.	When you play, Windows gives priority to the game and postpones updates and background tasks.
App dello Store in background	Store apps in the background
Bloccate	Blocked
Decide Windows	Windows decides
Le app dello Store (es. WhatsApp, Telefono, Posta) non lavorano quando sono chiuse: meno consumi, ma possono arrivare notifiche in ritardo. I programmi classici non sono toccati.	Store apps (e.g. WhatsApp, Phone, Mail) do not work when closed: lower consumption, but notifications may arrive late. Classic programs are not touched.
Ritardo dei programmi all'avvio	Startup programs delay
Nessun ritardo	No delay
Ritardo di Windows	Windows delay
Windows aspetta qualche secondo prima di aprire i programmi all'avvio. Togliendo l'attesa il desktop è pronto prima.	Windows waits a few seconds before opening startup programs. Removing the wait makes the desktop ready sooner.
Avvio rapido (Fast Startup)	Fast Startup
Attivo	On
Il PC si accende più in fretta perché parte del sistema viene salvata su disco allo spegnimento. Richiede l'ibernazione attiva. Se usi due sistemi operativi (dual boot) è meglio spento.	The PC starts faster because part of the system is saved to disk at shutdown. Requires hibernation to be on. If you use two operating systems (dual boot) it is better off.
Priorità alle attività multimediali (MMCSS)	Priority for multimedia tasks (MMCSS)
Quanta CPU Windows riserva alle attività in background mentre giochi o riproduci audio/video. Il guadagno è piccolo; valori diversi da 10 o 20 sconsigliati.	How much CPU Windows reserves for background tasks while you play or watch audio/video. The gain is small; values other than 10 or 20 are not recommended.
Ibernazione	Hibernation
Disattivata	Off
Spegnendo l'ibernazione si libera su C: lo spazio del file hiberfil.sys (grande quanto una parte della RAM), ma si perdono l'ibernazione e l'Avvio rapido. Su un portatile di solito conviene tenerla.	Turning hibernation off frees the space of hiberfil.sys on C: (as large as part of the RAM), but you lose hibernation and Fast Startup. On a laptop it is usually better to keep it.
 (file di {})	 (file of {})
powercfg /hibernate {} non riuscito (codice {}).	powercfg /hibernate {} failed (code {}).
Pianificazione GPU con accelerazione hardware (HAGS)	Hardware-accelerated GPU scheduling (HAGS)
Grafica	Graphics
Decide il driver	Driver decides
La scheda video gestisce da sola la propria memoria: meno carico sulla CPU e latenza più bassa. Necessaria per la Frame Generation NVIDIA (DLSS 3/4). Il profilo Grafica e design non la tocca.	The graphics card manages its own memory: less load on the CPU and lower latency. Required for NVIDIA Frame Generation (DLSS 3/4). The Graphics and design profile does not touch it.
Registrazione in background (Game Bar / DVR)	Background recording (Game Bar / DVR)
accesa	on
Spegne la registrazione continua dei giochi in background, che costa qualche FPS. La Game Bar (Win+G) resta disponibile.	Turns off continuous background game recording, which costs a few FPS. The Game Bar (Win+G) remains available.
Ottimizzazioni per giochi in finestra	Optimizations for windowed games
Attive	On
Migliora latenza e fluidità dei giochi in finestra o finestra senza bordi, e abilita Auto HDR/VRR su più giochi. Le altre impostazioni grafiche di Windows (come Auto HDR) restano come sono.	Improves latency and smoothness of windowed or borderless windowed games, and enables Auto HDR/VRR in more games. Other Windows graphics settings (such as Auto HDR) stay as they are.
Decide Windows (letto: {})	Windows decides (read: {})
Animazioni di finestre e barra delle applicazioni	Window and taskbar animations
Finestre che si aprono e si riducono a icona senza animazione: il sistema sembra più reattivo.	Windows open and minimize without animation: the system feels more responsive.
Effetti visivi leggeri (ombre, anteprime, selezione)	Light visual effects (shadows, previews, selection)
Leggeri	Light
Completi	Full
Toglie ombre sotto le icone, rettangolo di selezione trasparente e anteprima 'Aero Peek'. Il testo resta smussato (ClearType). Il profilo Grafica e design non la tocca.	Removes shadows under icons, the translucent selection rectangle and 'Aero Peek' preview. Text stays smooth (ClearType). The Graphics and design profile does not touch it.
Effetti di trasparenza	Transparency effects
Menu e barre diventano opachi: un po' meno lavoro per la GPU e qualche minuto di batteria in più.	Menus and bars become opaque: slightly less work for the GPU and a few more minutes of battery.
Condivisione in rete di Windows Media Player	Windows Media Player network sharing
Condivide musica e video del vecchio Windows Media Player con altri dispositivi della rete. Quasi nessuno lo usa.	Shares music and videos from the old Windows Media Player with other devices on the network. Almost nobody uses it.
Attività: analisi di compatibilità (telemetria)	Task: compatibility analysis (telemetry)
Attivita	Task
Attività pianificate che ogni tanto analizzano programmi e file del PC (processo CompatTelRunner) e inviano i dati a Microsoft: possono occupare CPU e disco per diversi minuti. Windows Update continua a funzionare.	Scheduled tasks that now and then analyze programs and files on the PC (CompatTelRunner process) and send data to Microsoft: they can use CPU and disk for several minutes. Windows Update keeps working.
Attività: programma Analisi utilizzo software	Task: Software Usage Analysis program
Raccolgono e inviano a Microsoft statistiche di utilizzo (anche dei dispositivi USB). Nessun effetto sul funzionamento del PC.	They collect and send usage statistics to Microsoft (including USB devices). No effect on how the PC works.
Attività: raccolta dati diagnostica dischi	Task: disk diagnostic data collection
Invia a Microsoft informazioni generiche sui dischi. Gli avvisi sullo stato dei dischi (SMART) non vengono toccati.	Sends generic disk information to Microsoft. Disk health alerts (SMART) are not touched.
Attività: richieste di feedback	Task: feedback requests
Scaricano le domande di feedback che Windows mostra ogni tanto.	They download the feedback questions that Windows shows from time to time.
Consigli e app suggerite nel menu Start	Tips and suggested apps in the Start menu
Toglie dalla sezione 'Consigliati' di Start i suggerimenti su app, consigli e collegamenti promozionali. I tuoi file recenti restano.	Removes app suggestions, tips and promotional links from the 'Recommended' section of Start. Your recent files stay.
Personalizzazione di digitazione e input penna	Typing and inking personalization
Windows smette di raccogliere quello che scrivi per costruire un dizionario personale. La correzione automatica normale continua a funzionare.	Windows stops collecting what you type to build a personal dictionary. Normal autocorrect keeps working.
Elenco delle lingue visibile ai siti web	Language list visible to websites
Nascosto	Hidden
Visibile	Visible
I siti non possono leggere l'elenco delle lingue installate in Windows (usato anche per riconoscerti).	Websites cannot read the list of languages installed in Windows (also used to recognize you).
Pubblicità e proposte in Esplora file	Ads and suggestions in File Explorer
Toglie i riquadri promozionali (OneDrive, Microsoft 365) che compaiono in Esplora file.	Removes the promotional banners (OneDrive, Microsoft 365) that appear in File Explorer.
Contenuti in evidenza nella casella di ricerca	Highlights in the search box
Toglie illustrazioni, ricorrenze e notizie dalla casella di ricerca della barra delle applicazioni.	Removes illustrations, anniversaries and news from the taskbar search box.
Aggiornamenti condivisi con altri PC (Ottimizzazione recapito)	Updates shared with other PCs (Delivery Optimization)
Il PC scarica gli aggiornamenti solo da Microsoft e non li ricarica verso altri PC: niente banda in upload usata di nascosto. Impostazione documentata da Microsoft (DODownloadMode).	The PC downloads updates only from Microsoft and does not upload them to other PCs: no upload bandwidth used behind your back. Setting documented by Microsoft (DODownloadMode).
Microsoft Edge in background e avvio anticipato	Microsoft Edge in the background and early start
Edge non resta caricato in memoria all'avvio di Windows e dopo averlo chiuso. Si apre un attimo più lentamente, ma libera RAM e processi. In Edge comparirà 'gestito dall'organizzazione': è normale (sono criteri ufficiali di Edge).	Edge does not stay loaded in memory at Windows startup or after closing it. It opens slightly slower, but frees RAM and processes. Edge will show 'managed by your organization': this is normal (they are official Edge policies).
Premere 5 volte Maiusc (o tenerlo premuto) non fa più comparire la finestra 'Tasti permanenti' che interrompe i giochi. Le funzioni di accessibilità restano attivabili da Impostazioni.	Pressing Shift 5 times (or holding it down) no longer shows the 'Sticky Keys' window that interrupts games. Accessibility features can still be turned on from Settings.
Accelerazione del mouse (precisione puntatore)	Mouse acceleration (pointer precision)
Il puntatore si muove sempre in proporzione al movimento della mano: mira più costante negli sparatutto. È una preferenza personale (per questo non è in nessun profilo): all'inizio il mouse sembra diverso.	The pointer always moves in proportion to your hand movement: more consistent aim in shooters. It is a personal preference (that is why it is in no profile): at first the mouse feels different.
Attivata	Enabled
Con l'alimentatore collegato Windows non spegne più le porte USB inattive: evita micro-disconnessioni di mouse, tastiere, cuffie e controller. Vale per il piano energetico attivo in questo momento; a batteria non cambia niente.	When plugged in, Windows no longer turns off idle USB ports: avoids micro-disconnections of mice, keyboards, headsets and controllers. Applies to the power plan that is active right now; nothing changes on battery.
Moderato	Moderate
Massimo	Maximum
Con l'alimentatore collegato scheda video e SSD NVMe non entrano negli stati di risparmio del collegamento PCI Express: meno latenza al risveglio. Vale per il piano energetico attivo in questo momento; a batteria non cambia niente.	When plugged in, the graphics card and NVMe SSDs do not enter the PCI Express link power-saving states: lower wake-up latency. Applies to the power plan that is active right now; nothing changes on battery.
Limitazione della rete durante audio/video (MMCSS)	Network throttling during audio/video (MMCSS)
Nessuna limitazione	No throttling
Mentre c'è audio o video in riproduzione Windows limita il traffico di rete non multimediale (valore NetworkThrottlingIndex, documentato da Microsoft). Toglierla può aiutare con reti molto veloci; su CPU deboli può causare scatti audio.	While audio or video is playing, Windows limits non-multimedia network traffic (NetworkThrottlingIndex value, documented by Microsoft). Removing it can help on very fast networks; on weak CPUs it can cause audio glitches.
Integrità della memoria (Isolamento core)	Memory integrity (Core isolation)
È una PROTEZIONE di Windows contro i driver malevoli. Microsoft stessa indica che spegnerla può dare qualche FPS in più nei giochi, ma il PC diventa meno protetto: fallo solo su un PC usato per giocare e riaccendila quando non serve. Alcuni giochi con anti-cheat la richiedono accesa.	It is a Windows PROTECTION against malicious drivers. Microsoft itself says that turning it off can give a few more FPS in games, but the PC becomes less protected: do it only on a PC used for gaming and turn it back on when not needed. Some games with anti-cheat require it on.
Mostra le estensioni dei file (.exe, .pdf, .jpg)	Show file extensions (.exe, .pdf, .jpg)
Esplora file	File Explorer
Visibili	Visible
Nascoste	Hidden
Vedi subito di che tipo è un file: utile per lavorare e per riconoscere i falsi documenti (es. 'fattura.pdf.exe').	You immediately see what type a file is: useful for work and for spotting fake documents (e.g. 'invoice.pdf.exe').
Esplora file si apre su "Questo PC"	File Explorer opens on "This PC"
Esplora file mostra subito dischi e cartelle principali invece dei file recenti.	File Explorer immediately shows drives and main folders instead of recent files.
"Termina attività" nel clic destro sulla barra	"End task" in the taskbar right-click menu
Con il clic destro su un'icona della barra delle applicazioni puoi chiudere subito un programma bloccato, senza aprire Gestione attività.	With a right-click on a taskbar icon you can immediately close a frozen program, without opening Task Manager.
Consentiti	Allowed
I programmi moderni possono usare cartelle e nomi molto lunghi senza errori 'percorso troppo lungo' (utile con progetti, archivi e strumenti di sviluppo).	Modern programs can use very long folders and names without 'path too long' errors (useful with projects, archives and development tools).
Spegnimento di USB, controller e Bluetooth per risparmiare energia	Turning off USB, controllers and Bluetooth to save power
È l'opzione 'Consenti al computer di spegnere il dispositivo' di Gestione dispositivi, per hub USB, mouse, tastiere, controller di gioco e Bluetooth. Spenta, le periferiche non vengono mai sospese: niente ritardo al primo movimento e niente disconnessioni dei controller. Consumo in più minimo. I dispositivi collegati per la prima volta in futuro tornano con l'opzione accesa: basta riapplicare la voce.	It is the 'Allow the computer to turn off this device' option in Device Manager, for USB hubs, mice, keyboards, game controllers and Bluetooth. When off, peripherals are never suspended: no delay on the first movement and no controller disconnections. Minimal extra consumption. Devices connected for the first time in the future come back with the option on: just apply the item again.
Spegnimento della scheda di rete per risparmiare energia	Turning off the network adapter to save power
La stessa opzione per le schede di rete (Wi-Fi ed Ethernet). Spenta, Windows non mette in pausa la scheda: meno micro-interruzioni e ping più stabile. Consiglio ufficiale Microsoft per i problemi di rete dopo la sospensione (KB 2740020).	The same option for network adapters (Wi-Fi and Ethernet). When off, Windows does not pause the adapter: fewer micro-interruptions and more stable ping. Official Microsoft advice for network problems after sleep (KB 2740020).
Timer eventi alta precisione (HPET) in Gestione dispositivi	High Precision Event Timer (HPET) in Device Manager
Attivo (come Windows)	Enabled (like Windows)
Molti 'ottimizzatori' disattivano questo dispositivo pensando di ridurre la latenza; in Windows deve restare attivo (è attivo di serie) e Windows sceglie da solo il timer migliore. Riattivarlo non forza l'uso dell'HPET: rimette solo la configurazione normale.	Many 'optimizers' disable this device thinking they reduce latency; in Windows it must stay enabled (it is on by default) and Windows chooses the best timer by itself. Re-enabling it does not force HPET use: it only restores the normal configuration.
Timer della piattaforma nel caricatore di avvio (bcdedit)	Platform timers in the boot loader (bcdedit)
Valori di Windows	Windows values
Alcuni programmi di 'tweak' forzano useplatformclock, useplatformtick, disabledynamictick o tscsyncpolicy: di solito peggiorano la latenza e i FPS. La voce toglie questi valori e lascia scegliere a Windows. Se il disco è protetto da BitLocker tieni a portata di mano la chiave di ripristino: in rari casi un cambio dell'avvio la chiede.	Some 'tweak' programs force useplatformclock, useplatformtick, disabledynamictick or tscsyncpolicy: they usually worsen latency and FPS. This item removes those values and lets Windows choose. If the disk is protected by BitLocker keep the recovery key at hand: in rare cases a boot change asks for it.
bcdedit /deletevalue {} non riuscito (codice {})	bcdedit /deletevalue {} failed (code {})
Con EEE la scheda Ethernet si 'addormenta' tra un pacchetto e l'altro: può aggiungere qualche millisecondo e piccoli scatti nel ping. Spento costa pochissima energia in più. Quando la voce viene applicata la connessione si interrompe per qualche secondo.	With EEE the Ethernet adapter 'falls asleep' between packets: it can add a few milliseconds and small ping spikes. Turned off it costs very little extra power. When the item is applied the connection drops for a few seconds.
Moderazione degli interrupt della scheda di rete	Network adapter interrupt moderation
La scheda raggruppa i pacchetti prima di avvisare il processore: meno lavoro per la CPU, ma un po' più di latenza. Spenta, ogni pacchetto arriva subito; su processori deboli o con download molto veloci può aumentare l'uso della CPU. La connessione si interrompe per qualche secondo quando la voce viene applicata.	The adapter groups packets before alerting the processor: less work for the CPU, but slightly more latency. When off, every packet arrives immediately; on weak processors or with very fast downloads it can increase CPU use. The connection drops for a few seconds when the item is applied.
Regolazione automatica della finestra TCP	TCP window auto-tuning
Normale (come Windows)	Normal (like Windows)
Windows adatta da solo la quantità di dati in viaggio sulla rete. Alcuni vecchi 'tweak' la disattivano o la limitano: download lenti e ping peggiore. Il valore giusto è 'Normale', quello di serie.	Windows adapts by itself the amount of data in flight on the network. Some old 'tweaks' turn it off or limit it: slow downloads and worse ping. The right value is 'Normal', the default.
Normale	Normal
Limitata	Limited
Molto limitata	Highly restricted
Sperimentale	Experimental
netsh non riuscito (codice {})	netsh failed (code {})
Conferme TCP immediate (niente ritardo di Nagle / Delayed ACK)	Immediate TCP acknowledgements (no Nagle / Delayed ACK delay)
Immediate	Immediate
Imposta TcpAckFrequency = 1 e TCPNoDelay = 1 sulle schede di rete con un indirizzo IP (valori documentati da Microsoft, KB 328890). Aiuta solo i giochi e i programmi che usano TCP (alcuni MMO e giochi più vecchi); i giochi moderni usano UDP e non cambiano. Microsoft consiglia di cambiarlo solo se serve: per questo non è in nessun profilo.	Sets TcpAckFrequency = 1 and TCPNoDelay = 1 on network adapters with an IP address (values documented by Microsoft, KB 328890). It only helps games and programs that use TCP (some MMOs and older games); modern games use UDP and do not change. Microsoft recommends changing it only if needed: that is why it is in no profile.
Nessuna scheda con IP	No adapter with an IP
Immediate su {} di {} schede	Immediate on {} of {} adapters
Priorità dei giochi nello scheduler multimediale (MMCSS)	Game priority in the multimedia scheduler (MMCSS)
Alta	High
I giochi che si registrano al servizio multimediale di Windows (MMCSS) ricevono più priorità di CPU e di disco. Valori documentati da Microsoft (Priority, Scheduling Category, SFIO Priority dell'attività 'Games'). Effetto solo sui giochi che usano MMCSS; non toglie niente agli altri programmi.	Games that register with the Windows multimedia service (MMCSS) receive more CPU and disk priority. Values documented by Microsoft (Priority, Scheduling Category, SFIO Priority of the 'Games' task). Only affects games that use MMCSS; it takes nothing away from other programs.
Frequenza minima del processore (a corrente)	Minimum processor frequency (plugged in)
Con l'alimentatore collegato il processore non scende sotto la frequenza scelta: risponde subito senza tempo di 'risveglio'. Più consumo, calore e rumore della ventola anche quando il PC non fa niente. Vale per il piano energetico attivo; a batteria non cambia niente.	When plugged in, the processor does not drop below the chosen frequency: it responds immediately with no 'wake-up' time. More consumption, heat and fan noise even when the PC is idle. Applies to the active power plan; nothing changes on battery.
Risoluzione del timer valida per tutto il sistema	System-wide timer resolution
Globale	Global
Da Windows 10 2004 ogni programma ha la sua risoluzione del timer; con questo valore (Windows 11) una richiesta di timer preciso vale di nuovo per tutto il sistema, come prima. Può rendere più regolari alcuni giochi vecchi e programmi audio, ma aumenta un po' i consumi. È una correzione di nicchia: non è in nessun profilo.	Since Windows 10 2004 each program has its own timer resolution; with this value (Windows 11) a precise timer request applies to the whole system again, as before. It can make some old games and audio programs smoother, but increases consumption a little. It is a niche fix: it is in no profile.
File di paging gestito da Windows	Paging file managed by Windows
La memoria virtuale deve essere gestita da Windows. Alcuni 'ottimizzatori' la disattivano o la impostano troppo piccola: con giochi pesanti si hanno blocchi, chiusure improvvise ed errori di memoria esaurita anche con tanta RAM.	Virtual memory must be managed by Windows. Some 'optimizers' turn it off or set it too small: with heavy games you get freezes, sudden closures and out-of-memory errors even with plenty of RAM.
Frequenza di aggiornamento dello schermo - da fare a mano	Screen refresh rate - to do by hand
La più alta	The highest
Imposta la frequenza più alta: Impostazioni > Sistema > Schermo > Schermo avanzato > Scegli una frequenza di aggiornamento. Su Windows 11 puoi anche lasciare 'Dinamica' se c'è: sale da sola al massimo nei giochi.	Set the highest rate: Settings > System > Display > Advanced display > Choose a refresh rate. On Windows 11 you can also leave 'Dynamic' if available: it goes up to the maximum by itself in games.
Più Hz = immagine più fluida e meno ritardo tra comando e schermo (a 240 Hz un fotogramma dura 4 ms, a 60 Hz 17 ms). Molti portatili a batteria scendono a 60 Hz. Il programma la controlla soltanto: si cambia da Impostazioni.	More Hz = smoother image and less delay between input and screen (at 240 Hz a frame lasts 4 ms, at 60 Hz 17 ms). Many laptops on battery drop to 60 Hz. The program only checks it: it is changed from Settings.
{} Hz (massimo {} Hz)	{} Hz (maximum {} Hz)
Modalità di gestione dell'alimentazione	Power management mode
Adattiva	Adaptive
Prestazioni massime	Maximum performance
Prestazioni costanti	Consistent performance
Consumo minimo	Minimum consumption
Controllata dal driver	Controlled by the driver
Con 'Prestazioni massime' la GPU resta alle frequenze più alte mentre un gioco è in esecuzione: meno cali e scatti, più consumo e calore. 'Normale' abbassa le frequenze quando il carico è leggero.	With 'Maximum performance' the GPU stays at its highest clocks while a game is running: fewer drops and stutters, more consumption and heat. 'Normal' lowers the clocks when the load is light.
Quanti fotogrammi la CPU prepara in anticipo. Con 1 i comandi arrivano sullo schermo prima (equivale a 'Modalità bassa latenza: Attiva'). Nei giochi con NVIDIA Reflex vale l'impostazione del gioco. La modalità 'Ultra' si attiva solo dal Pannello NVIDIA.	How many frames the CPU prepares in advance. With 1, inputs reach the screen sooner (equivalent to 'Low latency mode: On'). In games with NVIDIA Reflex the game's setting applies. 'Ultra' mode can only be turned on from the NVIDIA Control Panel.
Frequenza fotogrammi massima	Maximum frame rate
Nessun limite	No limit
Limita gli FPS di tutti i giochi e programmi 3D. Con G-SYNC conviene un limite di 3 FPS sotto la frequenza dello schermo (117, 141, 162, 237, 357). Un limite più basso riduce consumi, calore e rumore.	Limits the FPS of all games and 3D programs. With G-SYNC a limit of 3 FPS below the screen refresh rate is best (117, 141, 162, 237, 357). A lower limit reduces consumption, heat and noise.
Frequenza di aggiornamento preferita	Preferred refresh rate
La più alta disponibile	Highest available
I giochi a schermo intero usano la frequenza più alta dello schermo anche se ne chiedono una più bassa.	Full-screen games use the screen's highest refresh rate even if they ask for a lower one.
Cache shader	Shader cache
Salva su disco gli shader già compilati: meno scatti e caricamenti più rapidi. Conviene sempre lasciarla attivata.	Saves already compiled shaders to disk: fewer stutters and faster loading. It is always best to leave it enabled.
Dimensione massima della cache shader	Maximum shader cache size
Predefinita del driver	Driver default
Illimitata	Unlimited
Spazio massimo su disco per gli shader salvati. La cache cresce solo quando serve; con molti giochi 10 GB o più evitano ricompilazioni. I preset non la riducono mai se è già più grande.	Maximum disk space for saved shaders. The cache grows only when needed; with many games 10 GB or more avoids recompilation. Presets never reduce it if it is already larger.
Sincronizzazione	Synchronization
Metà della frequenza	Half the refresh rate
Un terzo della frequenza	One third of the refresh rate
Un quarto della frequenza	One quarter of the refresh rate
Lasciarla decidere al gioco è la scelta più flessibile. Con G-SYNC attivo molti preferiscono 'Attivata' qui e un limite di FPS poco sotto la frequenza dello schermo. 'Disattivata' dà la latenza minima ma può 'strappare' l'immagine.	Letting the game decide is the most flexible choice. With G-SYNC on, many prefer 'On' here and an FPS limit just below the screen refresh rate. 'Off' gives the lowest latency but may 'tear' the image.
Con 'Adattiva' la V-Sync (se attivata) si spegne da sola quando gli FPS scendono sotto la frequenza dello schermo, evitando rallentamenti. Ha effetto solo insieme a V-Sync 'Attivata'.	With 'Adaptive', V-Sync (if on) turns itself off when FPS drops below the screen refresh rate, avoiding slowdowns. It only works together with V-Sync 'On'.
Riguarda solo i programmi OpenGL con V-Sync attiva: rende più regolari gli FPS quando scendono sotto la frequenza dello schermo, usando un po' più di memoria video.	Only concerns OpenGL programs with V-Sync on: makes FPS more even when they drop below the screen refresh rate, using a little more video memory.
Filtro texture - qualità	Texture filtering - quality
Filtro texture	Texture filtering
Alta qualità	High quality
Qualità	Quality
Verso 'Prestazioni' il driver usa scorciatoie nel filtraggio delle texture: qualche FPS in più, differenza visiva minima. 'Alta qualità' le toglie tutte: adatta a grafica e design.	Towards 'Performance' the driver uses shortcuts in texture filtering: a few more FPS, minimal visual difference. 'High quality' removes them all: suitable for graphics and design.
Semplifica il filtro trilineare dove la differenza non si nota: un po' più di prestazioni. Con qualità 'Alta qualità' va disattivata.	Simplifies trilinear filtering where the difference is not noticeable: slightly more performance. With 'High quality' it should be turned off.
Riduce i campioni usati dal filtro anisotropico: qualche FPS in più con una perdita di nitidezza appena visibile sulle superfici inclinate.	Reduces the samples used by anisotropic filtering: a few more FPS with a barely visible loss of sharpness on slanted surfaces.
Consenti	Allow
Blocca	Block
'Consenti' lascia ai giochi la possibilità di rendere le texture più nitide. 'Blocca' riduce lo sfarfallio delle texture in lontananza quando forzi il filtro anisotropico.	'Allow' lets games make textures sharper. 'Block' reduces flicker of distant textures when you force anisotropic filtering.
Filtro anisotropico - modalità	Anisotropic filtering - mode
Forzato dal driver (usa il livello qui sotto)	Forced by the driver (uses the level below)
Il filtro anisotropico rende nitide le texture viste di sbieco (strade, pavimenti). Di norma lo decide il gioco; 'Forzato' applica a tutti il livello scelto nella voce successiva.	Anisotropic filtering sharpens textures seen at an angle (roads, floors). It is normally decided by the game; 'Forced' applies to all games the level chosen in the next item.
Nessuno	None
Livello usato solo quando la modalità qui sopra è 'Forzato dal driver'. 16x è la qualità massima e sulle schede moderne costa pochissimo.	Level used only when the mode above is 'Forced by the driver'. 16x is the maximum quality and on modern cards it costs very little.
Antialiasing - modalità	Antialiasing - mode
Antialiasing	Antialiasing
Chi decide l'antialiasing (la smussatura dei bordi). Lasciarlo all'applicazione è quasi sempre la scelta giusta: i giochi moderni usano i propri metodi (TAA, DLSS).	Who decides antialiasing (edge smoothing). Leaving it to the application is almost always the right choice: modern games use their own methods (TAA, DLSS).
Smussatura veloce applicata a tutta l'immagine. Attivata per tutti i programmi rende leggermente sfocati anche testi e interfacce: meglio lasciarla spenta qui.	Fast smoothing applied to the whole image. Enabled for all programs it makes text and interfaces slightly blurry too: better to leave it off here.
Attivata solo con sovracampionamento	On only with supersampling
Migliora i colori dei bordi smussati nei programmi OpenGL. Nessun costo sulle prestazioni.	Improves the colors of smoothed edges in OpenGL programs. No performance cost.
Smussa anche i bordi di oggetti con parti trasparenti (reti, foglie, recinzioni) nei giochi che usano MSAA. Costa qualche FPS.	Also smooths the edges of objects with transparent parts (fences, leaves, grids) in games that use MSAA. Costs a few FPS.
Nei giochi con MSAA dà una qualità simile a un livello più alto con meno lavoro per la GPU. Funziona solo con i giochi compatibili.	In games with MSAA it gives a quality similar to a higher level with less work for the GPU. Only works with compatible games.
Ottimizzazione thread	Thread optimization
Automatica	Automatic
Uso di più core della CPU nei programmi OpenGL. 'Automatica' (decide il driver) è la scelta migliore quasi sempre.	Use of multiple CPU cores in OpenGL programs. 'Automatic' (driver decides) is almost always the best choice.
Metodo di presentazione Vulkan/OpenGL	Vulkan/OpenGL presentation method
Nativo	Native
Preferisci a livelli su DXGI	Prefer layered on DXGI
Come i giochi Vulkan e OpenGL mostrano l'immagine. 'A livelli su DXGI' li fa comportare come i giochi DirectX (finestra senza bordi più fluida, Auto HDR, G-SYNC in finestra). 'Automatico' lascia decidere al driver.	How Vulkan and OpenGL games show the image. 'Layered on DXGI' makes them behave like DirectX games (smoother borderless window, Auto HDR, windowed G-SYNC). 'Automatic' lets the driver decide.
Riduce il ritardo tra i comandi (mouse, tastiera) e l'immagine sullo schermo. Non si può usare insieme a Radeon Chill: accendendo uno, il driver spegne l'altro.	Reduces the delay between inputs (mouse, keyboard) and the image on the screen. Cannot be used together with Radeon Chill: turning one on makes the driver turn the other off.
Abbassa da solo gli FPS quando nel gioco ti muovi poco: meno consumi, calore e rumore. Utile a batteria. Non si usa insieme ad Anti-Lag.	Lowers FPS by itself when you move little in the game: less consumption, heat and noise. Useful on battery. Not used together with Anti-Lag.
Il limite più alto di FPS che Chill usa quando ti muovi. Con la batteria 60 FPS è un buon compromesso. Valori fuori dall'intervallo della tua scheda vengono rifiutati dal driver.	The highest FPS limit Chill uses when you move. On battery 60 FPS is a good compromise. Values outside your card's range are refused by the driver.
Abbassa la risoluzione durante i movimenti veloci per guadagnare FPS. Funziona solo nei giochi compatibili e rende l'immagine meno nitida mentre ti muovi.	Lowers the resolution during fast movements to gain FPS. Only works in compatible games and makes the image less sharp while you move.
Qualità immagine	Image quality
Rende più nitida l'immagine dei giochi con un costo minimo. Per grafica e video conviene spento, così i colori e i dettagli restano quelli originali.	Sharpens the image of games at minimal cost. For graphics and video it is better off, so colors and details stay original.
Image Sharpening - intensità	Image Sharpening - intensity
Quanto è forte la nitidezza quando Image Sharpening è attivo. Valori alti possono far vedere i bordi troppo marcati.	How strong sharpening is when Image Sharpening is on. High values can make edges look too marked.
Toglie lo 'strappo' dell'immagine con meno ritardo della V-Sync classica. Con uno schermo FreeSync di solito non serve. Non si usa insieme alla V-Sync forzata.	Removes image 'tearing' with less delay than classic V-Sync. With a FreeSync screen it is usually not needed. Not used together with forced V-Sync.
Sempre disattivata	Always off
Sempre attivata	Always on
Sincronizza i fotogrammi con lo schermo. Di solito conviene lasciare decidere al gioco.	Synchronizes frames with the screen. It is usually best to let the game decide.
Limita gli FPS di tutti i giochi al valore qui sotto: meno consumi e calore. Spento = nessun limite.	Limits the FPS of all games to the value below: less consumption and heat. Off = no limit.
Il limite di FPS usato quando Frame Rate Target Control è attivo. Con FreeSync conviene qualche FPS sotto la frequenza dello schermo.	The FPS limit used when Frame Rate Target Control is on. With FreeSync a few FPS below the screen refresh rate is best.
Usa le impostazioni dell'applicazione	Use application settings
Migliora le impostazioni dell'applicazione	Enhance application settings
Sostituisci le impostazioni dell'applicazione	Override application settings
Chi decide l'antialiasing. Lasciarlo all'applicazione è quasi sempre la scelta migliore.	Who decides antialiasing. Leaving it to the application is almost always the best choice.
Livello usato quando la modalità è 'Migliora' o 'Sostituisci'. Più alto = bordi più lisci ma meno FPS.	Level used when the mode is 'Enhance' or 'Override'. Higher = smoother edges but fewer FPS.
Multicampionamento	Multisampling
Multicampionamento adattivo	Adaptive multisampling
Supercampionamento	Supersampling
Tecnica usata dall'antialiasing del driver. Il supercampionamento è il più bello ma pesa molto sulla scheda.	Technique used by the driver's antialiasing. Supersampling is the nicest but is very heavy on the card.
Antialiasing morfologico	Morphological antialiasing
Ammorbidisce i bordi in tutti i giochi, ma sfoca un po' anche testi e interfaccia.	Softens edges in all games, but also blurs text and interface a bit.
Filtro anisotropico	Anisotropic filtering
Texture	Textures
Attivato (forzato dal driver)	Enabled (forced by the driver)
Rende più nitide le texture viste di sbieco (strade, pavimenti). Costa pochissimo sulle schede moderne.	Makes textures seen at an angle sharper (roads, floors). Costs very little on modern cards.
Livello del filtro anisotropico quando è forzato dal driver.	Level of anisotropic filtering when it is forced by the driver.
Tassellatura - modalità	Tessellation - mode
Ottimizzata da AMD	AMD optimized
Dettaglio delle superfici 3D. 'Ottimizzata da AMD' limita i casi esagerati che rallentano; per lavori di grafica conviene lasciare decidere all'applicazione.	Detail of 3D surfaces. 'AMD optimized' limits excessive cases that slow things down; for graphics work it is better to let the application decide.
Livello massimo usato quando la modalità è 'Sostituisci'.	Maximum level used when the mode is 'Override'.
Fa girare i giochi a schermo intero a una risoluzione più bassa e la ingrandisce: più FPS ma immagine meno definita. Utile solo sulle schede poco potenti.	Runs full-screen games at a lower resolution and enlarges it: more FPS but a less sharp image. Only useful on low-power cards.
Pulizia	Cleanup
Cartella Temp del tuo utente. Vengono cancellati solo i file più vecchi di 1 giorno; quelli in uso vengono saltati.	Temp folder of your user. Only files older than 1 day are deleted; files in use are skipped.
File temporanei di Windows	Windows temporary files
Cartella C:\Windows\Temp. Solo i file più vecchi di 1 giorno; quelli in uso vengono saltati.	The C:\Windows\Temp folder. Only files older than 1 day; files in use are skipped.
Cache delle miniature	Thumbnail cache
Anteprime di foto e video salvate da Esplora file. Vengono ricreate quando servono. I file in uso vengono saltati.	Photo and video previews saved by File Explorer. They are recreated when needed. Files in use are skipped.
Rapporti errori e dump degli arresti anomali	Error reports and crash dumps
Rapporti già inviati o in attesa e dump di programmi che si sono chiusi in errore.	Reports already sent or pending and dumps of programs that closed with an error.
Cache di Ottimizzazione recapito	Delivery Optimization cache
Pezzi di aggiornamenti tenuti per condividerli con altri PC. Svuotata con il comando ufficiale di Windows.	Pieces of updates kept to share them with other PCs. Emptied with the official Windows command.
Download di Windows Update già usati	Windows Update downloads already used
File scaricati per aggiornamenti già installati. Windows Update viene fermato per un attimo e poi riavviato. Se un aggiornamento era in download, verrà riscaricato. Non usarla mentre Windows sta aggiornando.	Files downloaded for updates already installed. Windows Update is stopped for a moment and then restarted. If an update was downloading, it will be downloaded again. Do not use it while Windows is updating.
Svuota il Cestino	Empty the Recycle Bin
Elimina DEFINITIVAMENTE i file nel Cestino. Controlla prima che non ci sia niente da recuperare.	PERMANENTLY deletes the files in the Recycle Bin. Check first that there is nothing to recover.
Pulizia componenti di Windows (DISM)	Windows components cleanup (DISM)
DISM ha restituito il codice {}.	DISM returned code {}.
Elimina le vecchie versioni dei componenti sostituite dagli aggiornamenti (anche alcuni GB). Dopo NON potrai più disinstallare gli aggiornamenti già installati. Richiede diversi minuti.	Deletes the old versions of components replaced by updates (sometimes several GB). Afterwards you will NOT be able to uninstall updates already installed. Takes several minutes.
File temporanei Internet di Windows	Windows temporary Internet files
Copie temporanee di pagine e immagini scaricate da Windows e dalle app. Solo i file più vecchi di 1 giorno.	Temporary copies of pages and images downloaded by Windows and apps. Only files older than 1 day.
Dump di memoria delle schermate blu	Blue screen memory dumps
File creati quando Windows o un driver vanno in errore. Vengono eliminati solo quelli più vecchi di 30 giorni: i recenti restano, nel caso servano per capire un problema.	Files created when Windows or a driver fails. Only those older than 30 days are deleted: recent ones stay, in case they are needed to understand a problem.
Vecchi registri degli aggiornamenti (CBS)	Old update logs (CBS)
Registri archiviati dell'installazione degli aggiornamenti, a volte molto grandi. Solo i file più vecchi di 14 giorni; quello in uso viene saltato.	Archived logs of update installation, sometimes very large. Only files older than 14 days; the one in use is skipped.
Cache dei browser (Edge, Chrome, Brave, Firefox)	Browser cache (Edge, Chrome, Brave, Firefox)
Solo la cache (copie temporanee delle pagine): password, cronologia, preferiti e accessi ai siti NON vengono toccati. Chiudi i browser prima, altrimenti i file in uso vengono saltati. Le prime pagine si caricheranno un po' più lentamente.	Cache only (temporary copies of pages): passwords, history, bookmarks and site logins are NOT touched. Close browsers first, otherwise files in use are skipped. The first pages will load a bit more slowly.
Cache degli shader (DirectX, NVIDIA, AMD, Intel)	Shader caches (DirectX, NVIDIA, AMD, Intel)
Shader già compilati dei giochi. Va svuotata solo dopo un cambio di driver video o se un gioco ha difetti grafici: i giochi la ricreano, ma al primo avvio possono scattare. Per questo non è in nessun profilo.	Already compiled game shaders. It should be emptied only after a video driver change or if a game has graphical glitches: games recreate it, but on first launch they may stutter. That is why it is in no profile.
Controllo dei file di sistema (SFC)	System file check (SFC)
Manutenzione	Maintenance
  SFC terminato con codice {} (0 = nessun problema o problemi riparati). Dettagli: {}\Logs\CBS\CBS.log	  SFC finished with code {} (0 = no problems or problems repaired). Details: {}\Logs\CBS\CBS.log
Controlla che i file di Windows siano integri e ripara quelli danneggiati (comando 'sfc /scannow'). Dura 5-15 minuti. Utile dopo blocchi, errori strani o spegnimenti improvvisi.	Checks that Windows files are intact and repairs damaged ones ('sfc /scannow' command). Takes 5-15 minutes. Useful after freezes, strange errors or sudden shutdowns.
Riparazione dell'immagine di Windows (DISM)	Windows image repair (DISM)
DISM ha restituito il codice {} (dettagli in {}\Logs\DISM\dism.log).	DISM returned code {} (details in {}\Logs\DISM\dism.log).
Ripara l'archivio dei componenti di Windows scaricando da Windows Update le parti danneggiate. Serve Internet, dura 10-20 minuti. Se SFC non riesce a riparare, esegui prima questo e poi di nuovo SFC.	Repairs the Windows component store by downloading damaged parts from Windows Update. Needs Internet, takes 10-20 minutes. If SFC cannot repair, run this first and then SFC again.
Svuota la cache DNS	Flush the DNS cache
ipconfig /flushdns ha restituito il codice {}.	ipconfig /flushdns returned code {}.
Cancella gli indirizzi dei siti ricordati da Windows. Utile se un sito non si apre più o apre una versione vecchia. Nessun effetto collaterale.	Clears the website addresses remembered by Windows. Useful if a site no longer opens or opens an old version. No side effects.
Ottimizza il disco di sistema (TRIM / deframmentazione)	Optimize the system disk (TRIM / defragmentation)
defrag ha restituito il codice {}.	defrag returned code {}.
Esegue l'ottimizzazione giusta per il tipo di disco, scelta da Windows: TRIM sugli SSD, deframmentazione sui dischi meccanici. È la stessa operazione di 'Ottimizza unità'.	Runs the right optimization for the disk type, chosen by Windows: TRIM on SSDs, defragmentation on hard drives. It is the same operation as 'Optimize Drives'.
Stato di salute dei dischi (SMART)	Disk health status (SMART)
  {0} ({1}, {2:N0} GB): salute {3}, stato {4}	  {0} ({1}, {2:N0} GB): health {3}, status {4}
Legge lo stato di salute che Windows riporta per ogni disco (sano, a rischio, guasto) e lo scrive nel registro attività. Non modifica niente. Se un disco non risulta 'Healthy' fai subito una copia dei dati importanti.	Reads the health status Windows reports for each disk (healthy, at risk, failing) and writes it to the activity log. Changes nothing. If a disk is not 'Healthy', immediately back up important data.
Controllo degli errori del disco di sistema (sola lettura)	System disk error check (read-only)
Esegue 'chkdsk' senza riparare niente: cerca soltanto errori nel file system e scrive il risultato in Dati\Report. Dura qualche minuto e non richiede il riavvio. Se trova problemi, la riparazione (chkdsk /f) va fatta a parte.	Runs 'chkdsk' without repairing anything: it only looks for file system errors and writes the result to Dati\Report. Takes a few minutes and does not require a restart. If it finds problems, repair (chkdsk /f) must be done separately.
Verifica veloce dell'immagine di Windows (DISM, sola lettura)	Quick Windows image check (DISM, read-only)
  DISM: controllo terminato senza errori. Se SFC segnala problemi usa "Riparazione dell'immagine di Windows".	  DISM: check finished without errors. If SFC reports problems use "Windows image repair".
Controlla se l'archivio dei componenti di Windows è danneggiato, senza riparare niente. Più veloce della riparazione completa: usalo per capire se serve.	Checks whether the Windows component store is damaged, without repairing anything. Faster than the full repair: use it to see whether it is needed.
Report sulla batteria (solo portatili)	Battery report (laptops only)
Windows non ha creato il report: probabilmente questo PC non ha una batteria.	Windows did not create the report: this PC probably has no battery.
  Report creato: {} (capacità di progetto, capacità attuale, cicli, uso recente).	  Report created: {} (design capacity, current capacity, cycles, recent use).
Crea e apre il report ufficiale di Windows sulla batteria: quanta capacità ha perso rispetto al nuovo, cicli di carica e uso degli ultimi giorni.	Creates and opens the official Windows battery report: how much capacity it has lost compared to new, charge cycles and use over the last days.
Windows non ha creato il report energetico.	Windows did not create the energy report.
Osserva il PC per 20 secondi (lascialo fermo) e crea un report con errori e avvisi su consumi, USB, risparmio energetico e driver che impediscono la sospensione. Non modifica niente.	Observes the PC for 20 seconds (leave it idle) and creates a report with errors and warnings about consumption, USB, power saving and drivers that prevent sleep. Changes nothing.
Reimposta la cache del Microsoft Store	Reset the Microsoft Store cache
  Cache del Store reimpostata (il Store può aprirsi da solo alla fine).	  Store cache reset (the Store may open by itself at the end).
Svuota la cache del Microsoft Store senza toccare app e account. Utile se il Store non si apre, non scarica o dà errori.	Empties the Microsoft Store cache without touching apps and accounts. Useful if the Store does not open, does not download or gives errors.
Aggiorna la cache delle icone	Refresh the icon cache
ie4uinit ha restituito il codice {}.	ie4uinit returned code {}.
Fa ricaricare a Windows le icone di file e programmi: utile se compaiono icone bianche, sbagliate o vecchie. Non chiude Esplora file.	Makes Windows reload the icons of files and programs: useful if white, wrong or old icons appear. Does not close File Explorer.
Sincronizza data e ora con Internet	Sync date and time with the Internet
Sincronizzazione non riuscita (codice {}): controlla che il servizio 'Ora di Windows' sia attivo e che ci sia Internet.	Synchronization failed (code {}): check that the 'Windows Time' service is running and that you have Internet.
Allinea subito l'orologio del PC con il server orario di Windows. Un orologio sbagliato causa errori di certificato nei siti e negli accessi.	Immediately aligns the PC clock with the Windows time server. A wrong clock causes certificate errors on websites and sign-ins.
Diagnostica della memoria RAM (richiede il riavvio)	RAM memory diagnostics (requires a restart)
  Aperto lo strumento di Windows: lì scegli se riavviare subito o al prossimo avvio. Il risultato compare dopo il riavvio come notifica.	  Windows tool opened: there you choose whether to restart now or at the next startup. The result appears after the restart as a notification.
Apre 'Diagnostica memoria di Windows'. Il test avviene al riavvio e può durare 10-20 minuti: salva il lavoro aperto prima di scegliere. Utile se hai blocchi o schermate blu.	Opens 'Windows Memory Diagnostic'. The test runs at restart and can take 10-20 minutes: save your open work before choosing. Useful if you have freezes or blue screens.
Reimposta la rete (Winsock)	Reset the network (Winsock)
netsh winsock reset ha restituito il codice {}.	netsh winsock reset returned code {}.
  Winsock reimpostato: riavvia il PC per completare.	  Winsock reset: restart the PC to complete.
Riporta a zero le impostazioni del catalogo di rete di Windows. Serve quando la rete è collegata ma i programmi non navigano (dopo virus, VPN o programmi di rete rimossi male). Richiede il riavvio; VPN e firewall di terze parti potrebbero doversi reinstallare o riconfigurare.	Resets the Windows network catalog settings to zero. Needed when the network is connected but programs cannot browse (after viruses, VPNs or badly removed network programs). Requires a restart; third-party VPNs and firewalls may need to be reinstalled or reconfigured.
Massimo (con avvertenze)	Maximum (with warnings)
Grafica ed editing	Graphics and editing
Portatile a batteria	Laptop on battery
Sicuro	Safe
Batteria	Battery
Avvio	Startup
Profili	Profiles
Gruppo	Group
Rimossa	Removed
Installata	Installed
Eseguire	Run
Pulire	Clean
Disattivate	Disabled
Scelta dal menu	Chosen from the menu
Valore di serie del driver	Driver default value
Valore tipico di serie	Typical default value
DLSS Super Resolution: usa la versione più recente installata	DLSS Super Resolution: use the latest installed version
Sostituisce la libreria DLSS dei giochi con l'ultima versione presente nel driver (solo giochi con DLSS 2 o successivo; alcuni giochi non lo permettono). Può migliorare nitidezza e stabilità.	Replaces the DLSS library of games with the latest version present in the driver (only games with DLSS 2 or later; some games do not allow it). It can improve sharpness and stability.
DLSS Frame Generation: usa la versione più recente installata	DLSS Frame Generation: use the latest installed version
Come sopra, ma per la generazione di fotogrammi (DLSS-FG).	Same as above, but for frame generation (DLSS-FG).
DLSS Ray Reconstruction: usa la versione più recente installata	DLSS Ray Reconstruction: use the latest installed version
Come sopra, per la ricostruzione dei raggi (DLSS-RR) nei giochi con ray tracing.	Same as above, for ray reconstruction (DLSS-RR) in games with ray tracing.
DLSS: livello di qualità forzato	DLSS: forced quality level
Decide il gioco	Game decides
DLAA (massima qualità)	DLAA (maximum quality)
Ultra prestazioni	Ultra performance
Obbliga tutti i giochi con DLSS a usare questo livello. 'Prestazioni' = più FPS, immagine meno definita. Alcuni giochi ignorano la scelta.	Forces all DLSS games to use this level. 'Performance' = more FPS, less sharp image. Some games ignore the choice.
DLSS Super Resolution: lettera del preset forzata (Forced preset letter)	DLSS Super Resolution: forced preset letter
Decide il gioco / driver	Game / driver decides
Obbliga il DLSS Super Resolution a usare un preset preciso (la 'lettera' con cui NVIDIA ha addestrato la rete). Ogni preset è un compromesso tra nitidezza, stabilità dell'immagine e fantasmi: di solito K, L, M o 'Ultima disponibile' sono i più recenti. Funziona solo nei giochi con DLSS 2 o successivo; se un gioco mostra difetti, torna a 'Decide il gioco / driver'.	Forces DLSS Super Resolution to use a specific preset (the 'letter' NVIDIA used to train the network). Each preset is a compromise between sharpness, image stability and ghosting: usually K, L, M or 'Latest' are the most recent. Only works in games with DLSS 2 or later; if a game shows glitches, go back to 'Game / driver decides'.
Per schede RTX serie 50: forza il moltiplicatore di fotogrammi generati. Più fotogrammi mostrati, ma anche più latenza.	For RTX 50 series cards: forces the multiplier of generated frames. More frames shown, but also more latency.
Smooth Motion (fluidità a livello di driver)	Smooth Motion (driver-level smoothness)
Genera fotogrammi intermedi nei giochi che non supportano il DLSS Frame Generation. Per schede RTX serie 40 e 50.	Generates intermediate frames in games that do not support DLSS Frame Generation. For RTX 40 and 50 series cards.
Rendering	Rendering
Aumenta la vivacità dei colori nei giochi. Si regola con 'intensità' e 'aumento saturazione' qui sotto.	Increases color vividness in games. It is adjusted with 'intensity' and 'saturation boost' below.
RTX Dynamic Vibrance: intensità	RTX Dynamic Vibrance: intensity
Quanto è forte l'effetto di Dynamic Vibrance.	How strong the Dynamic Vibrance effect is.
RTX Dynamic Vibrance: aumento della saturazione	RTX Dynamic Vibrance: saturation boost
Quanta saturazione in più aggiunge Dynamic Vibrance.	How much extra saturation Dynamic Vibrance adds.
Disattivando il ray tracing i giochi che lo usano girano molto più veloci ma senza quegli effetti. Funziona solo se il gioco lo permette.	Turning off ray tracing makes games that use it run much faster but without those effects. Only works if the game allows it.
Come sopra, per i giochi Vulkan.	Same as above, for Vulkan games.
NVIDIA Ansel (foto in gioco)	NVIDIA Ansel (in-game photos)
Strumento per scattare foto speciali nei giochi compatibili. Spegnerlo libera un po' di risorse.	Tool for taking special photos in compatible games. Turning it off frees a few resources.
Ombre più realistiche negli angoli, solo nei giochi compatibili. 'Qualità' costa più FPS.	More realistic shadows in corners, only in compatible games. 'Quality' costs more FPS.
Modalità bassa latenza (come nel Pannello NVIDIA)	Low latency mode (as in the NVIDIA Control Panel)
Sincronizzazione e latenza	Synchronization and latency
Ultra	Ultra
'Ultra' invia i fotogrammi alla GPU appena in tempo: meno ritardo nei giochi senza NVIDIA Reflex.	'Ultra' sends frames to the GPU just in time: less delay in games without NVIDIA Reflex.
Nitidezza dell'immagine (filtro del driver)	Image sharpening (driver filter)
Nitidezza e antialiasing	Sharpening and antialiasing
Attiva il filtro di nitidezza del driver, valido per tutti i giochi. L'intensità si sceglie nella riga sotto.	Turns on the driver's sharpening filter, valid for all games. The intensity is chosen in the row below.
Nitidezza: intensità	Sharpening: intensity
Da 0,00 (niente) a 1,00 (massima). Valori oltre 0,6 danno spesso un effetto artificiale.	From 0.00 (none) to 1.00 (maximum). Values above 0.6 often give an artificial effect.
Antialiasing: supercampionamento della trasparenza	Antialiasing: transparency supersampling
Leviga bordi di foglie, recinzioni e vetri. Livelli alti costano molti FPS.	Smooths the edges of leaves, fences and glass. High levels cost a lot of FPS.
Filtro texture: sostituzione della qualità	Texture filtering: quality substitution
Nessuna sostituzione	No substitution
Alta qualità diventa qualità	High quality becomes quality
Se attiva, usa un filtro più leggero al posto di quello di alta qualità: più FPS, texture un po' meno pulite.	If on, uses a lighter filter instead of the high-quality one: more FPS, slightly less clean textures.
Filtro texture: impedisci il filtro anisotropico	Texture filtering: prevent anisotropic filtering
Blocca il filtro anisotropico (texture nitide in lontananza) anche se il gioco lo chiede. Lascialo disattivato salvo prove di compatibilità.	Blocks anisotropic filtering (sharp distant textures) even if the game requests it. Leave it off unless compatibility tests require it.
Filtro texture: regola il LOD bias in automatico	Texture filtering: adjust LOD bias automatically
Compensa il LOD bias quando si usa il supercampionamento (SGSSAA). Serve solo agli appassionati di antialiasing.	Compensates the LOD bias when supersampling (SGSSAA) is used. Only useful for antialiasing enthusiasts.
Resizable BAR (accesso completo alla memoria video)	Resizable BAR (full access to video memory)
Permette alla CPU di usare tutta la memoria video. Serve anche l'opzione attiva nel BIOS. Il driver ha già un elenco di giochi dove conviene.	Lets the CPU use all of the video memory. The option must also be on in the BIOS. The driver already has a list of games where it helps.
CUDA: forza lo stato P2	CUDA: force P2 state
Quando attivo la GPU, nei calcoli CUDA, non sale alle frequenze massime (stato P2). Disattivarlo può dare più prestazioni nei programmi di calcolo e rendering, con più consumo.	When on, the GPU does not reach maximum clocks in CUDA calculations (P2 state). Turning it off can give more performance in compute and rendering programs, with more consumption.
CUDA: uso della memoria di sistema quando finisce la VRAM	CUDA: use of system memory when VRAM runs out
Preferisci niente memoria di sistema	Prefer no system memory
Preferisci la memoria di sistema	Prefer system memory
Se la memoria video finisce, il driver può appoggiarsi alla RAM (più lento ma senza errori). 'Preferisci niente' evita i rallentamenti, ma i programmi possono chiudersi con un errore.	If video memory runs out, the driver can fall back on RAM (slower but without errors). 'Prefer no system memory' avoids slowdowns, but programs may close with an error.
Prestazioni con più schermi o più GPU	Performance with multiple screens or multiple GPUs
Prestazioni con un solo schermo	Single-screen performance
Compatibilità	Compatibility
Prestazioni con più schermi	Multi-screen performance
Scelta del comportamento della GPU quando ci sono più monitor.	Choice of GPU behavior when there are multiple monitors.
Precompilazione automatica degli shader	Automatic shader precompilation
Bassa	Low
Quando il PC è inattivo la CPU compila in anticipo gli shader dei giochi: meno scatti al primo avvio, ma più lavoro in background.	When the PC is idle the CPU precompiles game shaders: fewer stutters on first launch, but more background work.
Cache degli shader OpenGL	OpenGL shader cache
Conserva gli shader OpenGL già compilati: meno scatti alle riaperture.	Keeps already compiled OpenGL shaders: fewer stutters on reopening.
PhysX a 32 bit su GPU (schede RTX serie 50)	32-bit PhysX on GPU (RTX 50 series cards)
Le RTX serie 50 non accelerano più il PhysX a 32 bit dei vecchi giochi (es. Borderlands 2, Mirror's Edge): con questa voce attiva si prova a riabilitarlo. Funziona solo se il driver lo supporta.	RTX 50 series cards no longer accelerate 32-bit PhysX of old games (e.g. Borderlands 2, Mirror's Edge): with this item on, an attempt is made to re-enable it. Only works if the driver supports it.
OpenGL: limita le estensioni	OpenGL: limit extensions
Per vecchi programmi OpenGL che si bloccano con troppe estensioni.	For old OpenGL programs that crash with too many extensions.
Id duplicato nel catalogo: {}	Duplicate id in the catalog: {}
App non installata	App not installed
(non impostato)	(not set)
Misto ({0} di {1} come consigliato)	Mixed ({0} of {1} as recommended)
 · in esecuzione	 · running
 · {} in esecuzione	 · {} running
Modo di avvio non valido: {}	Invalid startup mode: {}
Per reinstallare un'app usa 'Annulla tutto' oppure il Microsoft Store.	To reinstall an app use 'Undo all' or the Microsoft Store.
L'app {} è protetta e non viene rimossa.	The app {} is protected and is not removed.
  {}: file non più presenti, aperta la pagina nel Microsoft Store per reinstallarla.	  {}: files no longer present, the Microsoft Store page was opened to reinstall it.
Programma non riconosciuto: disattivalo solo se sai cos'è. Puoi sempre riattivarlo.	Unrecognized program: disable it only if you know what it is. You can always re-enable it.
Sembra un componente di driver, audio o sicurezza: è consigliato lasciarlo attivo.	It looks like a driver, audio or security component: leaving it enabled is recommended.
Programma che non serve all'avvio: puoi aprirlo a mano quando ti serve.	Program not needed at startup: you can open it by hand when you need it.
Registro, solo il tuo utente	Registry, current user only
Registro, tutti gli utenti	Registry, all users
Registro, tutti gli utenti (32 bit)	Registry, all users (32-bit)
Startup	Startup
Cartella Esecuzione automatica (tutti gli utenti)	Startup folder (all users)
Non misurabile in anticipo	Cannot be measured in advance
  liberati {0} ({1} file eliminati, {2} in uso saltati)	  freed {0} ({1} files deleted, {2} in use skipped)
Attive: {} di {}	Active: {} of {}
NVAPI ha restituito il codice {} leggendo '{}'.	NVAPI returned code {} while reading '{}'.
NVIDIA non disponibile	NVIDIA not available
  (di serie)	  (default)
Attuale	Current
Prestazioni (più FPS)	Performance (more FPS)
Predefinite del driver	Driver defaults
Scheda video	Graphics card
Scelte {} annullate: i menu mostrano di nuovo i valori attuali.	{} choices cleared: the menus show the current values again.
Preset {} '{}' selezionato: {} impostazioni da cambiare.	{} preset '{}' selected: {} settings to change.
Preset {} '{}': {} impostazioni da cambiare (evidenziate come 'Da applicare'). Puoi ritoccare i menu, poi premi 'Anteprima e applica'.	{} preset '{}': {} settings to change (highlighted as 'To apply'). You can adjust the menus, then press 'Preview and apply'.
AMD non disponibile	AMD not available
Non supportata da questa scheda	Not supported by this card
Voce {} non trovata nel catalogo.	Item {} not found in the catalog.
Tipo di voce sconosciuto: {}	Unknown item type: {}
Voce {} non trovata nel catalogo: impossibile annullarla.	Item {} not found in the catalog: cannot undo it.
Tipo non annullabile: {}	Type cannot be undone: {}
Consigliato	Recommended
DA FARE A MANO (protetta da Windows)	TO DO BY HAND (protected by Windows)
Avanzate	Advanced
App preinstallate che puoi rimuovere. Sono elencate solo quelle presenti su questo PC. Store, Sicurezza di Windows, driver e componenti di sistema non compaiono mai.	Preinstalled apps you can remove. Only those present on this PC are listed. Store, Windows Security, drivers and system components never appear.
Programmi che partono quando accedi a Windows. Disattivarli è sempre reversibile (è lo stesso interruttore di Gestione attività).	Programs that start when you sign in to Windows. Disabling them is always reversible (it is the same switch as Task Manager).
Servizi di Windows non essenziali e attività pianificate di telemetria. Si cambia solo il modo in cui partono. Windows Update e Defender sono protetti.	Non-essential Windows services and scheduled telemetry tasks. Only the way they start is changed. Windows Update and Defender are protected.
Piccole impostazioni che rendono più pratico Esplora file e la barra delle applicazioni. Tutte reversibili.	Small settings that make File Explorer and the taskbar more practical. All reversible.
Strumenti ufficiali di Windows per controllare e riparare il sistema. Si eseguono solo quando li accendi e premi 'Anteprima e applica'; non c'è niente da annullare.	Official Windows tools to check and repair the system. They run only when you turn them on and press 'Preview and apply'; there is nothing to undo.
Telemetria, pubblicità, suggerimenti e notifiche promozionali. Solo impostazioni documentate.	Telemetry, ads, suggestions and promotional notifications. Documented settings only.
Piano energetico e comportamento del sistema. Per i piani energetici se ne può scegliere uno solo.	Power plan and system behavior. Only one power plan can be chosen.
Reattività del PC: accessori (mouse, tastiere, controller), USB e Bluetooth, rete, processore, memoria e timer di sistema. Correggono anche i 'tweak' sbagliati lasciati da altri programmi. Le voci a rischio medio non sono in nessun profilo: accendile tu dopo aver letto la descrizione. 'Misura la latenza' controlla il ping verso il router e il DNS (solo lettura).	PC responsiveness: accessories (mouse, keyboards, controllers), USB and Bluetooth, network, processor, memory and system timers. They also fix wrong 'tweaks' left by other programs. Medium-risk items are in no profile: turn them on yourself after reading the description. 'Measure latency' checks the ping to the router and DNS (read-only).
Impostazioni grafiche ed effetti visivi. Colori, HDR, profili colore e impostazioni GPU delle singole app non vengono mai toccati.	Graphics settings and visual effects. Colors, HDR, color profiles and GPU settings of individual apps are never touched.
Impostazioni globali del Pannello di controllo NVIDIA, lette e scritte con NVAPI (la libreria ufficiale del driver). Scegli uno dei preset (Prestazioni, Bilanciato, Qualità: cambiano solo queste impostazioni, i profili non le toccano) oppure cambia i singoli menu a tendina: le righe 'Da applicare' vengono scritte solo con 'Anteprima e applica'. Valgono per i programmi avviati dopo la modifica; un'installazione pulita del driver le riporta ai valori di serie.	Global NVIDIA Control Panel settings, read and written with NVAPI (the official driver library). Choose one of the presets (Performance, Balanced, Quality: they only change these settings, profiles do not touch them) or change the individual drop-down menus: the 'To apply' rows are written only with 'Preview and apply'. They apply to programs started after the change; a clean driver installation resets them to default values.
⚠  OPZIONI AVANZATE: le impostazioni che di solito si cambiano con NVIDIA Profile Inspector (DLSS, Smooth Motion, Resizable BAR, nitidezza, ray tracing, memoria CUDA...), scritte nel profilo globale con NVAPI. Non fanno parte dei preset: scegli tu, una per una, dal menu a tendina. Cambiarle male può causare errori nei giochi: 'Predefinite del driver' rimette tutto a posto e 'Annulla tutto' ripristina i valori originali. Compaiono solo quelle che il tuo driver conosce.	⚠  ADVANCED OPTIONS: the settings usually changed with NVIDIA Profile Inspector (DLSS, Smooth Motion, Resizable BAR, sharpening, ray tracing, CUDA memory...), written to the global profile with NVAPI. They are not part of the presets: you choose, one by one, from the drop-down menu. Changing them wrongly can cause errors in games: 'Driver defaults' puts everything back and 'Undo all' restores the original values. Only those your driver knows appear.
Impostazioni grafiche globali di AMD Software: Adrenalin Edition, lette e scritte con ADLX (la libreria ufficiale del driver AMD). Scegli uno dei preset (Prestazioni, Bilanciato, Qualità: cambiano solo queste impostazioni, i profili non le toccano) oppure cambia i singoli menu a tendina: le righe 'Da applicare' vengono scritte solo con 'Anteprima e applica'. Compaiono solo le funzioni che la tua scheda supporta.	Global graphics settings of AMD Software: Adrenalin Edition, read and written with ADLX (the official AMD driver library). Choose one of the presets (Performance, Balanced, Quality: they only change these settings, profiles do not touch them) or change the individual drop-down menus: the 'To apply' rows are written only with 'Preview and apply'. Only the features your card supports appear.
File temporanei e cache. Attenzione: la pulizia NON si può annullare (i file vengono eliminati).	Temporary files and caches. Warning: cleanup CANNOT be undone (files are deleted).
⚠  VOCI AVANZATE: possono togliere funzioni o avere effetti collaterali. Non sono mai incluse nei profili: spuntale solo se hai letto la descrizione e sai cosa fanno.	⚠  ADVANCED ITEMS: they can remove features or have side effects. They are never included in profiles: tick them only if you have read the description and know what they do.
Selezionata	Selected
Niente da mostrare su questo PC	Nothing to show on this PC
{} strumenti su richiesta	{} tools on request
{} da applicare · {} impostazioni	{} to apply · {} settings
{} impostazioni	{} settings
{} voci · tutto a posto	{} items · all OK
{} da sistemare · {} voci	{} to fix · {} items
Video	Video
Driver	Drivers
Chipset, audio, rete: più driver insieme	Chipset, audio, network: several drivers together
Disinstallazione completa dei programmi	Complete uninstall of programs
Scansione in corso (sola lettura, non modifica niente)...	Scanning (read-only, changes nothing)...
Scansione in corso... {} di {}	Scanning... {} of {}
Preparo il report dello stato del PC...	Preparing the PC status report...
Report non riuscito: {}	Report failed: {}
{} voci da sistemare su {}  ·  circa {} recuperabili con la pulizia	{} items to fix out of {}  ·  about {} recoverable with cleanup
Scansione completata: {} voci, {} da sistemare, circa {} recuperabili con la pulizia.	Scan completed: {} items, {} to fix, about {} recoverable with cleanup.
{}  Scegli un profilo o accendi le voci, poi premi 'Anteprima e applica'.	{}  Choose a profile or turn on items, then press 'Preview and apply'.
Il profilo 'Massimo' accende TUTTO quello che il programma ritiene utile per migliorare il PC, comprese voci a rischio medio:	The 'Maximum' profile turns on EVERYTHING the program considers useful to improve the PC, including medium-risk items:
•  rimuove le app preinstallate non essenziali (anche Copilot, Teams personale, Posta di Windows se presenti);	•  removes non-essential preinstalled apps (also Copilot, personal Teams, Windows Mail if present);
•  disattiva servizi e attività di telemetria e il servizio Segnalazione errori;	•  disables telemetry services and tasks and the Error Reporting service;
•  blocca le app dello Store in background (le notifiche di alcune app possono arrivare in ritardo);	•  blocks Store apps in the background (notifications from some apps may arrive late);
•  imposta il piano 'Prestazioni elevate' (la scheda video non viene toccata: ha i suoi preset);	•  sets the 'High performance' plan (the graphics card is not touched: it has its own presets);
•  pulisce i file temporanei (non annullabile).	•  cleans temporary files (cannot be undone).
Le voci 'Avanzate' restano escluse. Niente viene applicato finché non confermi l'anteprima, e quasi tutto si annulla con 'Annulla tutto'.\n\nVuoi accendere le voci del profilo Massimo?	'Advanced' items stay excluded. Nothing is applied until you confirm the preview, and almost everything can be undone with 'Undo all'.\n\nDo you want to turn on the items of the Maximum profile?
Su questo PC non c'è una batteria: il profilo 'Portatile a batteria' riduce i consumi ma è pensato per i portatili. Puoi usarlo lo stesso se vuoi un PC più silenzioso e fresco.	This PC has no battery: the 'Laptop on battery' profile reduces consumption but is designed for laptops. You can still use it if you want a quieter, cooler PC.
Profilo '{}' selezionato: {} voci da modificare.	Profile '{}' selected: {} items to change.
Profilo '{}': spuntate le voci del profilo ({} da modificare). Controlla le schede e poi premi 'Anteprima e applica'.	Profile '{}': profile items ticked ({} to change). Check the tabs, then press 'Preview and apply'.
{}: non leggibile, saltata ({})	{}: cannot be read, skipped ({})
Vuoi creare un punto di ripristino di Windows prima di continuare?	Do you want to create a Windows restore point before continuing?
È CONSIGLIATO: se qualcosa non va, con il punto di ripristino puoi riportare il PC a com'era adesso.	It is RECOMMENDED: if something goes wrong, with the restore point you can bring the PC back to how it is now.
Richiede fino a un minuto e un po' di spazio sul disco.	Takes up to a minute and some disk space.
Sì = crea il punto di ripristino e continua\nNo = continua senza (il backup dei valori originali per 'Annulla tutto' viene creato comunque)\nAnnulla = non fare niente	Yes = create the restore point and continue\nNo = continue without it (the backup of original values for 'Undo all' is still created)\nCancel = do nothing
Punto di ripristino (consigliato)	Restore point (recommended)
Operazione annullata alla domanda sul punto di ripristino.	Operation cancelled at the restore point question.
Punto di ripristino non creato: scelta dell'utente.	Restore point not created: user's choice.
Regia - prima delle modifiche {0:yyyy-MM-dd HH:mm}	Regia - before changes {0:yyyy-MM-dd HH:mm}
Creo il punto di ripristino (può richiedere fino a un minuto)...	Creating the restore point (it can take up to a minute)...
Punto di ripristino creato: {}	Restore point created: {}
Punto di ripristino non creato: {}	Restore point not created: {}
Il punto di ripristino non è stato creato nemmeno dopo aver attivato la Protezione sistema.\n\nMotivo: {}\n\nVuoi continuare lo stesso? (Il backup JSON dei valori originali viene creato comunque.)	The restore point was not created even after enabling System Protection.\n\nReason: {}\n\nDo you want to continue anyway? (The JSON backup of the original values is still created.)
Punto di ripristino	Restore point
Non sono riuscito a creare il punto di ripristino.\n\nMotivo: {}\n\nDi solito succede perché la Protezione sistema è disattivata sul disco C:.\n\nSì = attiva la Protezione sistema su C: e riprova\nNo = continua senza punto di ripristino (il backup JSON dei valori originali viene creato comunque)\nAnnulla = non applicare niente	I could not create the restore point.\n\nReason: {}\n\nThis usually happens because System Protection is turned off on drive C:.\n\nYes = turn on System Protection on C: and retry\nNo = continue without a restore point (the JSON backup of the original values is still created)\nCancel = apply nothing
Protezione sistema attivata su C:.	System Protection turned on for C:.
Impossibile attivare la Protezione sistema: {}	Cannot turn on System Protection: {}
Non hai spuntato nessuna voce.	You have not ticked any item.
Le voci spuntate sono già nello stato richiesto: non c'è niente da modificare.	The ticked items are already in the requested state: there is nothing to change.
Niente da applicare (obiettivo: {}): {}	Nothing to apply (goal: {}): {}
Niente da fare	Nothing to do
ai valori PREDEFINITI di Windows	to the Windows DEFAULT values
ai valori scelti (consigliati o indicati nei menu a tendina)	to the chosen values (recommended or set in the drop-down menus)
Stai per portare {} voci {}.	You are about to bring {} items {}.
 {} voci spuntate sono già a posto (o non applicabili) e verranno saltate.	 {} ticked items are already OK (or not applicable) and will be skipped.
Prima di iniziare: punto di ripristino + backup JSON dei valori originali (per 'Annulla tutto').	Before starting: restore point + JSON backup of the original values (for 'Undo all').
\n⚠ {} operazioni di pulizia NON annullabili.	\n⚠ {} cleanup operations CANNOT be undone.
MODALITÀ PROVA: non verrà modificato niente, le operazioni verranno solo scritte nel log.	DRY-RUN MODE: nothing will be changed, operations will only be written to the log.
Simula (modalità prova)	Simulate (dry-run mode)
Conferma e applica	Confirm and apply
Anteprima delle modifiche	Preview of changes
--- MODALITÀ PROVA: {} modifiche simulate ---	--- DRY-RUN MODE: {} changes simulated ---
Modalità prova: {} modifiche simulate e scritte nel log. Niente è stato cambiato.	Dry-run mode: {} changes simulated and written to the log. Nothing was changed.
Niente è stato modificato.\nLe {} operazioni sono elencate nella scheda Log.\n\nPer applicarle davvero spegni l'interruttore 'Modalità prova'.	Nothing was changed.\nThe {} operations are listed in the Log tab.\n\nTo really apply them turn off the 'Dry-run mode' switch.
Modalità prova	Dry-run mode
Applicazione annullata: punto di ripristino non creato.	Application cancelled: restore point not created.
--- Applicazione di {} modifiche (obiettivo: {}) ---	--- Applying {} changes (goal: {}) ---
Applico ({} di {}): {}...	Applying ({} of {}): {}...
Backup dei valori originali: {}	Backup of the original values: {}
I dettagli degli errori sono nella scheda Log.	Error details are in the Log tab.
Alcune modifiche hanno effetto dopo il RIAVVIO del PC.	Some changes take effect after the PC RESTARTS.
Alcune modifiche hanno effetto dopo la disconnessione (o il riavvio).	Some changes take effect after signing out (or restarting).
Modifiche applicate il {}.	Changes applied on {}.
Modifiche applicate	Changes applied
Annulla tutto: nessun backup da ripristinare.	Undo all: no backup to restore.
Non ci sono modifiche da annullare.	There are no changes to undo.
Annulla tutto	Undo all
modificata il {}	changed on {}
com'era prima ({})	as it was before ({})
Annulla tutto: ignorati {} file di backup creati su un altro PC.	Undo all: ignored {} backup files created on another PC.
Non ci sono modifiche da annullare su questo PC.{}	There are no changes to undo on this PC.{}
\n({} file di backup appartengono a un altro PC e vengono ignorati.)	\n({} backup files belong to another PC and are ignored.)
Verranno rimessi i valori originali di {} voci, salvati in {} file di backup. Le pulizie non si possono annullare.\nLe app rimosse vengono reinstallate se possibile, altrimenti si apre la loro pagina nel Microsoft Store.	The original values of {} items, saved in {} backup files, will be restored. Cleanups cannot be undone.\nRemoved apps are reinstalled if possible, otherwise their Microsoft Store page opens.
MODALITÀ PROVA: non verrà modificato niente.	DRY-RUN MODE: nothing will be changed.
Annulla le modifiche	Undo changes
--- MODALITÀ PROVA: annullamento simulato di {} voci ---	--- DRY-RUN MODE: simulated undo of {} items ---
Modalità prova: annullamento simulato, niente è stato cambiato.	Dry-run mode: simulated undo, nothing was changed.
--- Annulla tutto: {} voci ---	--- Undo all: {} items ---
Ripristino di {} non riuscito: {}	Restoring {} failed: {}
Voci ripristinate: {}.  Errori: {}.\nAlcune modifiche hanno effetto dopo il riavvio o la disconnessione.	Items restored: {}.  Errors: {}.\nSome changes take effect after a restart or sign-out.
I file di backup con errori sono rimasti attivi: puoi riprovare.	Backup files with errors stayed active: you can try again.
Annulla tutto il {}.	Undo all on {}.
Opzione avanzata: non fa parte dei preset	Advanced option: not part of the presets
non cambia	unchanged
valore di serie	default value
 (o più)	 (or more)
Strumento ufficiale di Windows	Official Windows tool
Obbligatorio	Required
Fisica PhysX usata da alcuni giochi	PhysX physics used by some games
Driver USB-C collegato alla GPU	USB-C driver connected to the GPU
Controller di piattaforma (portatili)	Platform controller (laptops)
Pannello di controllo NVIDIA (impostazioni 3D, schermo, colori)	NVIDIA Control Panel (3D settings, display, colors)
DLDSR: risoluzione superiore con l'IA, da attivare nel Pannello NVIDIA	DLDSR: higher resolution with AI, to be turned on in the NVIDIA Control Panel
Facoltativo	Optional
Audio virtuale usato da registrazione e overlay NVIDIA	Virtual audio used by NVIDIA recording and overlay
FrameView (misura delle prestazioni)	FrameView (performance measurement)
Registrazione e overlay	Recording and overlay
Servizio di aggiornamento automatico	Automatic update service
Contenitore dei servizi di NVIDIA App	NVIDIA App services container
Aggiornamento automatico	Automatic update
Ansel / fotocamera dei giochi	Ansel / in-game camera
Componente aggiuntivo	Add-on component
Il modello '{}' non è nell'elenco dei prodotti NVIDIA.	The model '{}' is not in the NVIDIA product list.
Questo driver non è più disponibile su Windows Update.	This driver is no longer available on Windows Update.
Questo driver richiede di accettare una licenza: installalo da Impostazioni > Windows Update > Opzioni avanzate > Aggiornamenti facoltativi.	This driver requires accepting a license: install it from Settings > Windows Update > Advanced options > Optional updates.
Download non riuscito (codice {}).	Download failed (code {}).
Chiedo a nvidia.com l'elenco delle versioni del driver...	Asking nvidia.com for the list of driver versions...
   ·   la più recente	   ·   the latest
Nessun driver Studio per questo modello	No Studio driver for this model
Nessun driver trovato	No driver found
NVIDIA: trovate {} versioni {} per {}.	NVIDIA: found {} {} versions for {}.
Per '{}' ({}) non c'è un elenco automatico delle versioni: usa 'Installazione pulita da file' con il programma scaricato dal sito AMD o del produttore del PC.	For '{}' ({}) there is no automatic list of versions: use 'Clean install from file' with the program downloaded from the AMD or PC manufacturer's site.
Chiedo ad amd.com l'elenco delle versioni del driver...	Asking amd.com for the list of driver versions...
AMD: trovate {} versioni Adrenalin per {} (pagina {}).	AMD: found {} Adrenalin versions for {} (page {}).
NVIDIA non ha restituito driver per questo modello.	NVIDIA returned no drivers for this model.
Disponibile la {} del {} (nuova)	Version {} of {} available (new)
La {} è la più recente: già installata	Version {} is the latest: already installed
NVIDIA: installato {}, ultimo disponibile {} del {}	NVIDIA: installed {}, latest available {} of {}
Controllo non riuscito	Check failed
Controllo NVIDIA non riuscito: {}	NVIDIA check failed: {}
amd.com non ha restituito driver per questa scheda.	amd.com returned no drivers for this card.
Disponibile la {} del {}{}	Version {} of {} available{}
AMD: installato {}, ultimo disponibile {} del {}	AMD: installed {}, latest available {} of {}
Controllo AMD non riuscito: {}	AMD check failed: {}
Controllo dei driver video completato: scegli la versione e premi "Installazione pulita".	Video driver check completed: choose the version and press "Clean install".
Cerco driver nel catalogo di Windows Update (può richiedere un minuto)...	Searching drivers in the Windows Update catalog (it can take a minute)...
Aggiornamento del {}	Update of {}
Nessun aggiornamento	No updates
Ricerca su Windows Update non riuscita: {}	Windows Update search failed: {}
Controllo driver completato: tutti i driver sono aggiornati.	Driver check completed: all drivers are up to date.
Controllo driver completato: {} aggiornamenti disponibili. Accendi quelli che vuoi e premi 'Installa selezionati', oppure 'Installa tutto'.	Driver check completed: {} updates available. Turn on the ones you want and press 'Install selected', or 'Install all'.
Download {0}: {1}% ({2} di {3})	Download {0}: {1}% ({2} of {3})
Download {} in corso...	Download {} in progress...
Download non riuscito: {}	Download failed: {}
Download {} in corso... {}	Download {} in progress... {}
Non sono riuscito a riattivare la ricerca automatica dei driver: {}	I could not re-enable automatic driver search: {}
Cerco i driver {} presenti nell'archivio di Windows...	Looking for {} drivers in the Windows store...
Nessun pacchetto driver {} da rimuovere nell'archivio di Windows.	No {} driver package to remove in the Windows store.
Rimuovo il vecchio driver {} {}...	Removing the old {} driver {}...
  rimosso {} ({} {}): si completa al riavvio	  removed {} ({} {}): completes at restart
  {} ({} {}) non rimosso: pnputil ha restituito il codice {}	  {} ({} {}) not removed: pnputil returned code {}
  cache degli shader svuotata ({})	  shader cache emptied ({})
Titolo	Title
Passi	Steps
1.  Punto di ripristino di Windows (per poter tornare indietro)	1.  Windows restore point (to be able to go back)
2.  Rimozione dei driver {} presenti, comprese le vecchie versioni rimaste nell'archivio di Windows\n	2.  Removal of the {} drivers present, including old versions left in the Windows store\n
3.  Installazione del driver scelto con l'opzione di installazione pulita del produttore	3.  Installation of the chosen driver with the manufacturer's clean installation option
4.  Verifica della versione installata.  Lo schermo può diventare nero o cambiare risoluzione per qualche secondo: è normale.	4.  Check of the installed version.  The screen may go black or change resolution for a few seconds: this is normal.
Indirizzo di download non riconosciuto come NVIDIA: {}	Download address not recognized as NVIDIA: {}
 È una versione PRECEDENTE a quella installata ({}): Windows Update o NVIDIA App potrebbero riproporre in seguito quella più recente.	 It is an OLDER version than the installed one ({}): Windows Update or NVIDIA App may offer the newer one again later.
 È la STESSA versione già installata: verrà reinstallata da zero.	 It is the SAME version already installed: it will be reinstalled from scratch.
Scaricare il driver NVIDIA {}?\n\nFile: {}\nFonte: {}\nDimensione: {}\nCartella: Dati\Driver\n\nDopo il download vedrai la procedura e i componenti, e deciderai se installare.	Download the NVIDIA driver {}?\n\nFile: {}\nSource: {}\nSize: {}\nFolder: Dati\Driver\n\nAfter the download you will see the procedure and the components, and you will decide whether to install.
Download driver NVIDIA {} da {}	Download NVIDIA driver {} from {}
La firma digitale del file non è valida o non è di NVIDIA (stato: {}). Il file NON verrà usato: {}	The file's digital signature is not valid or is not from NVIDIA (status: {}). The file will NOT be used: {}
Estraggo il pacchetto del driver...	Extracting the driver package...
Estrazione non riuscita (codice {}). Puoi installare il driver avviando {} e scegliendo 'Personalizzata' > 'Esegui un'installazione pulita'.	Extraction failed (code {}). You can install the driver by running {} and choosing 'Custom' > 'Perform a clean installation'.
Nel pacchetto manca Display.Driver: formato non riconosciuto, installazione annullata.	The package lacks Display.Driver: format not recognized, installation cancelled.
Le impostazioni del Pannello NVIDIA tornano ai valori di serie: dopo potrai riapplicarle dalla sezione NVIDIA. Se torni indietro i file restano pronti in Dati\Driver.	The NVIDIA Control Panel settings return to default values: afterwards you can reapply them from the NVIDIA section. If you go back the files stay ready in Dati\Driver.
MODALITÀ PROVA: il driver non verrà rimosso né installato.	DRY-RUN MODE: the driver will not be removed or installed.
Avvia installazione pulita	Start clean installation
Installazione NVIDIA annullata dall'utente (file pronti nella cartella Dati\Driver).	NVIDIA installation cancelled by the user (files ready in the Dati\Driver folder).
Installazione annullata: nessuna modifica.	Installation cancelled: no changes.
rimozione completa dei vecchi driver	complete removal of old drivers
Rimuoverei dall'archivio di Windows: {} ({} {})	I would remove from the Windows store: {} ({} {})
Elenco dei vecchi driver non disponibile: {}	List of old drivers not available: {}
Modalità prova: niente è stato rimosso o installato.	Dry-run mode: nothing was removed or installed.
Modalità prova: il driver NON è stato toccato.\nNel log trovi i componenti scelti e i vecchi driver che verrebbero rimossi; i file sono pronti in Dati\Driver.	Dry-run mode: the driver was NOT touched.\nThe log shows the chosen components and the old drivers that would be removed; the files are ready in Dati\Driver.
Installazione NVIDIA annullata: punto di ripristino non creato.	NVIDIA installation cancelled: restore point not created.
Vecchi driver NVIDIA rimossi: {}, non rimossi: {}.	Old NVIDIA drivers removed: {}, not removed: {}.
Installazione del driver NVIDIA in corso (qualche minuto, lo schermo può lampeggiare)...	NVIDIA driver installation in progress (a few minutes, the screen may flicker)...
Installazione NVIDIA terminata con codice {}	NVIDIA installation finished with code {}
L'installazione è terminata con codice {}, ma la versione rilevata adesso è: {}.\n	The installation finished with code {}, but the version detected now is: {}.\n
nessun driver NVIDIA	no NVIDIA driver
Riavvia il PC e controlla di nuovo. Se il driver manca, avvia a mano il file scaricato:\n{}\noppure usa il punto di ripristino creato poco fa.	Restart the PC and check again. If the driver is missing, run the downloaded file by hand:\n{}\nor use the restore point created a moment ago.
File del driver eliminati: {}	Driver files deleted: {}
Driver NVIDIA {} installato. Riavvia il PC.	NVIDIA driver {} installed. Restart the PC.
 ed è necessario: alcuni vecchi file vengono tolti solo al riavvio	 and it is needed: some old files are removed only at restart
Premi prima 'Cerca versioni': il programma chiede a nvidia.com l'elenco dei driver disponibili per la tua scheda, poi scegli la versione dal menu.	Press 'Search versions' first: the program asks nvidia.com for the list of drivers available for your card, then choose the version from the menu.
Scegli la versione	Choose the version
{} per {}	{} for {}
Scegli il programma di installazione del driver {} scaricato dal sito ufficiale	Choose the {} driver installer downloaded from the official site
Programmi di installazione (*.exe)|*.exe	Installers (*.exe)|*.exe
Premi prima 'Cerca versioni': il programma chiede ad amd.com l'elenco dei driver per la tua scheda, poi scegli la versione dal menu.	Press 'Search versions' first: the program asks amd.com for the list of drivers for your card, then choose the version from the menu.
Indirizzo di download non riconosciuto come AMD: {}	Download address not recognized as AMD: {}
Scaricare il driver AMD {}?\n\nFile: {}\nFonte: drivers.amd.com\nDimensione: {}\nCartella: Dati\Driver\n\nScaricando accetti i termini di licenza di AMD per il software (gli stessi del sito amd.com).\nDopo il download vedrai la procedura e deciderai se installare.	Download the AMD driver {}?\n\nFile: {}\nSource: drivers.amd.com\nSize: {}\nFolder: Dati\Driver\n\nBy downloading you accept AMD's software license terms (the same as on amd.com).\nAfter the download you will see the procedure and you will decide whether to install.
Download driver AMD {} da {}	Download AMD driver {} from {}
La firma digitale del file non è valida o non è di {} (stato: {}). Il file NON verrà usato: {}	The file's digital signature is not valid or is not from {} (status: {}). The file will NOT be used: {}
Dopo la rimozione dei vecchi driver si apre il programma di installazione del produttore: segui le sue istruzioni{}.	After removing the old drivers the manufacturer's installer opens: follow its instructions{}.
 (se lo propone, scegli 'Ripristino impostazioni di fabbrica')	 (if it offers it, choose 'Factory reset')
 (se lo propone, spunta 'Installazione pulita')	 (if it offers it, tick 'Clean installation')
Installazione pulita {} da {} (rimozione completa: {}; cache shader: {})	Clean installation {} from {} (complete removal: {}; shader cache: {})
Modalità prova: il driver NON è stato toccato. Le operazioni sono scritte nel log.	Dry-run mode: the driver was NOT touched. The operations are written to the log.
--- Installazione pulita driver {} da {} ---	--- Clean driver installation {} from {} ---
Vecchi driver {} rimossi: {}, non rimossi: {}.	Old {} drivers removed: {}, not removed: {}.
Programma di installazione {} aperto: completa l'installazione nella sua finestra...	{} installer opened: complete the installation in its window...
Programma di installazione {} chiuso con codice {}	{} installer closed with code {}
Il programma di installazione {} si è chiuso (codice {}).\nControlla la versione nella tabella; il riavvio completa l'installazione.	The {} installer closed (code {}).\nCheck the version in the table; a restart completes the installation.
Installare questo driver da Windows Update?\n\n{}\nDimensione: {}\n\nPrima verrà creato un punto di ripristino.	Install this driver from Windows Update?\n\n{}\nSize: {}\n\nA restore point will be created first.
Driver da Windows Update	Driver from Windows Update
Installerei da Windows Update: {}	I would install from Windows Update: {}
Modalità prova: il driver NON è stato installato. L'operazione è scritta nel log.	Dry-run mode: the driver was NOT installed. The operation is written to the log.
Installazione da Windows Update: {}	Installation from Windows Update: {}
Installazione non riuscita (codice {}).	Installation failed (code {}).
Driver da Windows Update: {}.	Driver from Windows Update: {}.
{}\nServe un riavvio per completare l'installazione.	{}\nA restart is needed to complete the installation.
Non ci sono aggiornamenti in elenco: premi prima 'Controlla aggiornamenti'.	There are no updates in the list: press 'Check for updates' first.
Accendi la casella dei driver che vuoi installare, poi premi 'Installa selezionati'.	Turn on the checkbox of the drivers you want to install, then press 'Install selected'.
Installa driver	Install drivers
Installare {} driver da Windows Update?\n\n{}\n\nPrima verrà creato un punto di ripristino; poi i driver vengono scaricati e installati uno alla volta.	Install {} drivers from Windows Update?\n\n{}\n\nA restore point will be created first; then the drivers are downloaded and installed one at a time.
Modalità prova: nessun driver è stato installato. Le {} operazioni sono scritte nel log.	Dry-run mode: no driver was installed. The {} operations are written to the log.
--- Installazione di {} driver da Windows Update ---	--- Installing {} drivers from Windows Update ---
Driver {} di {}: scarico e installo {}...	Driver {} of {}: downloading and installing {}...
Serve un riavvio per completare l'installazione.	A restart is needed to complete the installation.
I dettagli sono nel Registro attività.	Details are in the Activity log.
{} driver da Windows Update installati.	{} drivers installed from Windows Update.
portatile, batteria al {}%	laptop, battery at {}%
Desktop	Desktop
Informazioni di sistema non disponibili	System information not available
Chiaro	Light
Tema	Theme
Sul desktop c'è già il collegamento 'Regia'.\nVuoi sostituirlo con uno nuovo (stessa posizione del programma, icona aggiornata)?	A 'Regia' shortcut already exists on the desktop.\nDo you want to replace it with a new one (same program location, updated icon)?
Collegamento sul desktop	Desktop shortcut
Analizza e ottimizza Windows (chiede i permessi di amministratore)	Analyze and optimize Windows (asks for administrator permissions)
Collegamento 'Regia' creato sul desktop.\n\nAvvia il programma direttamente come amministratore, senza la finestra nera. Se sposti la cartella del programma, crealo di nuovo da qui.	'Regia' shortcut created on the desktop.\n\nIt starts the program directly as administrator, without the black window. If you move the program folder, create it again from here.
Riavvio consigliato	Restart recommended
Riavvia il PC	Restart the PC
Riavviare il PC?	Restart the PC?
Il riavvio completa queste operazioni:\n{}	The restart completes these operations:\n{}
Windows ha aggiornamenti o componenti che si completano al riavvio.	Windows has updates or components that complete at restart.
In questo momento non risultano operazioni in attesa di riavvio.	At the moment there are no operations waiting for a restart.
Non risultano altri programmi aperti.	No other open programs found.
Riavvio del PC chiesto dall'utente.	PC restart requested by the user.
Riavvio non avviato (codice {}).	Restart not started (code {}).
Windows non ha avviato il riavvio (codice {}).\nRiavvia dal menu Start.	Windows did not start the restart (code {}).\nRestart from the Start menu.
Disconnessione non avviata (codice {}).	Sign-out not started (code {}).
Riavvio rimandato: resta segnalato nella barra laterale.	Restart postponed: it stays flagged in the sidebar.
Profilo personale con {} voci.  Clic: applica  ·  Clic destro: elimina	Personal profile with {} items.  Click: apply  ·  Right-click: delete
Accendi prima le voci che vuoi nel profilo, poi premi "Salva profilo".	First turn on the items you want in the profile, then press "Save profile".
Salva profilo	Save profile
Nome del profilo ({} voci accese adesso):	Profile name ({} items on right now):
Esiste già un profilo chiamato '{}'. Vuoi sostituirlo con la selezione attuale?	A profile named '{}' already exists. Do you want to replace it with the current selection?
Profilo personale '{}' salvato con {} voci.	Personal profile '{}' saved with {} items.
 ({} voci del profilo non sono presenti su questo PC)	 ({} profile items are not present on this PC)
Profilo '{}': {} voci accese{}. Controlla le schede e poi premi 'Anteprima e applica'.	Profile '{}': {} items on{}. Check the tabs, then press 'Preview and apply'.
Eliminare il profilo '{}'?\nVerrà tolto solo dall'elenco dei profili: le impostazioni del PC non cambiano.	Delete the profile '{}'?\nIt will only be removed from the list of profiles: PC settings do not change.
Elimina profilo	Delete profile
Programma	Program
App dello Store	Store app
{} app installate ({} programmi classici, {} app dello Store)  ·  mostrate: {}.  Scegli una riga e premi 'Disinstalla e pulisci'.	{} apps installed ({} classic programs, {} Store apps)  ·  shown: {}.  Choose a row and press 'Uninstall and clean up'.
Leggo l'elenco delle app installate (sola lettura)...	Reading the list of installed apps (read-only)...
Cartella	Folder
Chiave di registro	Registry key
Il programma di disinstallazione non esiste più: {}	The uninstaller no longer exists: {}
Scegli prima un'app dall'elenco.	First choose an app from the list.
Disinstalla	Uninstall
'{}' è un driver, un componente usato da altri programmi o una parte di Windows: il programma non lo disinstalla da qui.\n\nI driver si gestiscono nelle sezioni 'Driver video' e 'Altri driver'.	'{}' is a driver, a component used by other programs or part of Windows: the program does not uninstall it from here.\n\nDrivers are managed in the 'Video drivers' and 'Other drivers' sections.
È un'app dello Store: viene rimossa per il tuo utente; i suoi dati vengono eliminati da Windows. Si può reinstallare dal Microsoft Store.	It is a Store app: it is removed for your user; its data is deleted by Windows. It can be reinstalled from the Microsoft Store.
1.  Punto di ripristino\n2.  Si apre il programma di disinstallazione dell'app: seguilo fino alla fine\n3.  Il programma cerca le cartelle e le chiavi di registro rimaste e te le mostra: scegli tu cosa togliere\n4.  Le cartelle vanno nel Cestino e le chiavi di registro vengono salvate in un file .reg prima di essere tolte	1.  Restore point\n2.  The app's uninstaller opens: follow it to the end\n3.  The program looks for leftover folders and registry keys and shows them to you: you choose what to remove\n4.  Folders go to the Recycle Bin and registry keys are saved in a .reg file before being removed
MODALITÀ PROVA: niente verrà disinstallato o cancellato.	DRY-RUN MODE: nothing will be uninstalled or deleted.
Disinstallerei '{}' con: {}	I would uninstall '{}' with: {}
Controllerei dopo la disinstallazione: {} {}	I would check after the uninstall: {} {}
Modalità prova: '{}' NON è stato disinstallato.\nNel log trovi il comando che verrebbe usato e i {} percorsi che verrebbero controllati dopo la disinstallazione (adesso contengono ancora l'app installata).	Dry-run mode: '{}' was NOT uninstalled.\nThe log shows the command that would be used and the {} paths that would be checked after the uninstall (they still contain the installed app now).
Modalità prova: l'app NON è stata rimossa. L'operazione è scritta nel log.	Dry-run mode: the app was NOT removed. The operation is written to the log.
--- Disinstallazione di '{}' {} ({}) ---	--- Uninstalling '{}' {} ({}) ---
App dello Store rimossa: {}	Store app removed: {}
'{}' è stata rimossa.	'{}' was removed.
Programma di disinstallazione di {} aperto: completalo nella sua finestra...	Uninstaller of {} opened: complete it in its window...
Programma di disinstallazione chiuso con codice {}	Uninstaller closed with code {}
Se il programma di disinstallazione di '{}' è ancora aperto (alcuni si riaprono in una seconda finestra), finiscilo.\n\nQuando ha finito premi OK: il programma cerca i residui.	If the uninstaller of '{}' is still open (some reopen in a second window), finish it.\n\nWhen it is done press OK: the program looks for leftovers.
'{}' risulta ancora installato (forse la disinstallazione è stata annullata).\n\nVuoi cercare lo stesso i residui? Attenzione: toglierli adesso può rovinare il programma ancora installato.	'{}' still appears installed (maybe the uninstall was cancelled).\n\nDo you want to look for leftovers anyway? Warning: removing them now can break the program that is still installed.
Disinstallazione di '{}' non completata: nessun residuo rimosso.	Uninstall of '{}' not completed: no leftovers removed.
Cerco cartelle e chiavi di registro rimaste...	Looking for leftover folders and registry keys...
Nessun residuo trovato per '{}'.	No leftovers found for '{}'.
Disinstallazione completata: non sono rimasti residui riconoscibili di '{}'.	Uninstall completed: no recognizable leftovers of '{}' remain.
Sono rimasti {} elementi con il nome di '{}'. Spegni quelli che vuoi tenere (per esempio salvataggi o impostazioni che ti servono).\nLe cartelle vanno nel Cestino; le chiavi di registro vengono salvate in un file .reg nella cartella Dati\Backup\App prima di essere tolte (per rimetterle basta un doppio clic sul file).	{} items with the name of '{}' remain. Turn off those you want to keep (for example saves or settings you need).\nFolders go to the Recycle Bin; registry keys are saved in a .reg file in the Dati\Backup\App folder before being removed (to put them back just double-click the file).
\n⚠ {} cartelle sono segnate 'Dati personali?' e sono SPENTE: possono contenere posta, profili, salvataggi o documenti. Accendile solo se sei sicuro di non volerli più.	\n⚠ {} folders are marked 'Personal data?' and are OFF: they may contain mail, profiles, saves or documents. Turn them on only if you are sure you no longer want them.
Residui di {}	Leftovers of {}
Pulizia dei residui annullata dall'utente.	Leftover cleanup cancelled by the user.
Sposto nel Cestino: {}	Moving to the Recycle Bin: {}
  cartella nel Cestino: {}	  folder in the Recycle Bin: {}
Salvo e tolgo la chiave: {}	Saving and removing the key: {}
backup della chiave non riuscito (reg export codice {}): la chiave NON viene tolta	registry key backup failed (reg export code {}): the key is NOT removed
  chiave tolta (backup in {}): {}	  key removed (backup in {}): {}
  non rimosso: {}: {}	  not removed: {}: {}
Residui di '{}' rimossi: {}.  Non rimossi: {}.\nLe cartelle sono nel Cestino; il backup del registro è in {}.	Leftovers of '{}' removed: {}.  Not removed: {}.\nFolders are in the Recycle Bin; the registry backup is in {}.
Pulizia completata	Cleanup completed
Regia {} - ottimizzazione di Windows	Regia {} - Windows optimization
Icona del programma non impostata: {}	Program icon not set: {}
Ottimizzazione di Windows · {}	Windows optimization · {}
Clic per mostrare o nascondere le sezioni	Click to show or hide the sections
Panoramica	Overview
\nSu questo PC non c'è una scheda video {} con il driver installato: questa sezione non serve.	\nThis PC has no {} graphics card with the driver installed: this section is not needed.
Nessuna voce di questa sezione è presente su questo PC.	No item of this section is present on this PC.
Nessuna voce accesa	No items on
{} voci accese	{} items on
{} core · {} thread	{} cores · {} threads
{} GB di RAM	{} GB of RAM
Clic per mostrare o nascondere	Click to show or hide
Nessuna	None
Dati in tempo reale non disponibili: {}	Real-time data not available: {}
Lettura in corso	Reading
Sensori	Sensors
Download con BITS non riuscito ({}): riprovo in modo diretto.	Download with BITS failed ({}): retrying directly.
L'impronta del file scaricato ({}) non corrisponde a quella attesa: il file è stato scartato.	The fingerprint of the downloaded file ({}) does not match the expected one: the file was discarded.
Per leggere la temperatura e il consumo del processore serve un driver di sistema.	A system driver is needed to read the processor temperature and power consumption.
Verranno scaricati da GitHub:	They will be downloaded from GitHub:
•  LibreHardwareMonitor 0.9.6 (libreria libera, {}) nella cartella Dati\Sensori;\n	•  LibreHardwareMonitor 0.9.6 (free library, {}) in the Dati\Sensori folder;\n
•  PawnIO 2.2.0 (driver firmato, {}): è un driver che gira nel sistema e viene installato in C:\Program Files\PawnIO.\n\n	•  PawnIO 2.2.0 (signed driver, {}): it is a driver that runs in the system and is installed in C:\Program Files\PawnIO.\n\n
Prima dell'uso i file vengono controllati con l'impronta SHA-256 e, per PawnIO, con la firma digitale. 	Before use the files are checked with the SHA-256 fingerprint and, for PawnIO, with the digital signature.
Per togliere tutto: Impostazioni > App > PawnIO > Disinstalla, poi cancella la cartella Dati\Sensori.	To remove everything: Settings > Apps > PawnIO > Uninstall, then delete the Dati\Sensori folder.
MODALITÀ PROVA: non verrà scaricato né installato niente.	DRY-RUN MODE: nothing will be downloaded or installed.
Sensori avanzati	Advanced sensors
Sensori avanzati: simulati in modalità prova (niente scaricato né installato).	Advanced sensors: simulated in dry-run mode (nothing downloaded or installed).
Modalità prova: sensori avanzati non installati.	Dry-run mode: advanced sensors not installed.
Download LibreHardwareMonitor da {}	Download LibreHardwareMonitor from {}
LibreHardwareMonitor pronto in {}	LibreHardwareMonitor ready in {}
Download PawnIO da {}	Download PawnIO from {}
La firma digitale di PawnIO non è valida (stato: {}): il file non verrà usato.	The PawnIO digital signature is not valid (status: {}): the file will not be used.
Installo il driver PawnIO...	Installing the PawnIO driver...
L'installazione di PawnIO non è riuscita (codice {}).	The PawnIO installation failed (code {}).
Sensori avanzati attivi: tra pochi secondi la Panoramica mostra la temperatura del processore.	Advanced sensors active: in a few seconds the Overview shows the processor temperature.
Processore	Processor
Memoria	Memory
Disco	Disk
Dischi	Disks
Alimentazione	Power
Attiva la temperatura del processore...	Enable processor temperature...
Scarica LibreHardwareMonitor e il driver PawnIO (con la tua conferma) per leggere temperatura e consumo del processore	Downloads LibreHardwareMonitor and the PawnIO driver (with your confirmation) to read processor temperature and power consumption
  ·  temperatura non disponibile	  ·  temperature not available
Contatori di Windows non disponibili	Windows counters not available
{0:N1} di {1:N1} GB in uso	{0:N1} of {1:N1} GB in use
Temperature e frequenze: schede NVIDIA, oppure attiva i sensori avanzati	Temperatures and clocks: NVIDIA cards, or turn on advanced sensors
attività {0:N0} %	activity {0:N0} %
{0} {1} liberi su {2}	{0} {1} free of {2}
Contatori del disco non disponibili	Disk counters not available
Nessuna rete	No network
Nessuna connessione attiva con accesso al router	No active connection with access to the router
acceso da {0}h {1:00}m	on for {0}h {1:00}m
Rete elettrica	Mains power
I sensori avanzati sono installati ma il processore non ha restituito la temperatura{}.	Advanced sensors are installed but the processor did not return a temperature{}.
Windows non fornisce la temperatura del processore: serve un driver di sistema dedicato. Regia può installarlo (LibreHardwareMonitor + PawnIO) solo se lo chiedi e confermi. Carico e frequenza sono già reali.	Windows does not provide the processor temperature: a dedicated system driver is needed. Regia can install it (LibreHardwareMonitor + PawnIO) only if you ask and confirm. Load and frequency are already real.
Apri	Open
Il supporto gratuito di Windows 10 è terminato (ottobre 2025): meglio passare a Windows 11 o attivare gli aggiornamenti di sicurezza estesi.	Free Windows 10 support has ended (October 2025): better to move to Windows 11 or enable extended security updates.
Versione moderna di Windows.	Modern version of Windows.
Aggiornamenti di Windows	Windows updates
Ultimo aggiornamento installato il {} ({} giorni fa).	Last update installed on {} ({} days ago).
Riavvio in sospeso	Pending restart
Windows ha operazioni che si completano solo dopo un riavvio.	Windows has operations that complete only after a restart.
Acceso da {} giorni: va bene.	On for {} days: fine.
Acceso da {} giorni: un riavvio ripulisce la memoria e completa gli aggiornamenti.	On for {} days: a restart clears memory and completes updates.
{} dispositivi con problemi di driver	{} devices with driver problems
In uso {0:N0} % ({1:N1} di {2:N1} GB).	In use {0:N0} % ({1:N1} of {2:N1} GB).
Piano energetico	Power plan
Temperatura del processore	Processor temperature
{0:N0} °C in questo momento.	{0:N0} °C right now.
Temperatura della scheda video	Graphics card temperature
Nessuna connessione attiva con accesso al router.	No active connection with access to the router.
1 programma non essenziale parte con Windows.	1 non-essential program starts with Windows.
{} programmi non essenziali partono con Windows.	{} non-essential programs start with Windows.
Ottimizzazioni disponibili	Available optimizations
Le impostazioni di Windows sono già a posto.	Windows settings are already fine.
{} impostazioni di Windows si possono migliorare (privacy, servizi, prestazioni...).	{} Windows settings can be improved (privacy, services, performance...).
File temporanei e cache	Temporary files and caches
Poco da pulire.	Little to clean.
Circa {} si possono recuperare con la pulizia.	About {} can be recovered with cleanup.
Dischi e hardware	Disks and hardware
Spazio su {}	Space on {}
{0} liberi su {1} ({2:N0} %).	{0} free of {1} ({2:N0} %).
Salute dei dischi	Disk health
{} dischi, tutti in buono stato secondo Windows.	{} disks, all in good condition according to Windows.
Usura degli SSD	SSD wear
Temperatura dei dischi	Disk temperature
Capacità residua {0:N0} % di quella originale.	Remaining capacity {0:N0} % of the original.
Defender	Defender
Sicurezza	Security
Protezione antivirus	Antivirus protection
Microsoft Defender è attivo in tempo reale.	Microsoft Defender is active in real time.
Definizioni antivirus	Antivirus definitions
{} giorni fa	{} days ago
Protezione fornita da: {}.	Protection provided by: {}.
Antivirus	Antivirus
Firewall	Firewall
Attivo su tutte le reti.	Active on all networks.
Spento su: {}.	Off on: {}.
Disattivato nel BIOS: Windows 11 e alcuni giochi lo richiedono.	Disabled in the BIOS: Windows 11 and some games require it.
Assente o non pronto.	Missing or not ready.
Il PC è in ottima forma	The PC is in great shape
Nessun problema importante: restano solo piccoli miglioramenti.	No important problems: only small improvements remain.
Il PC va bene, ma c'è qualcosa da sistemare	The PC is fine, but something needs fixing
Guarda le voci con il triangolo arancio.	Look at the items with the orange triangle.
Il PC ha bisogno di attenzione	The PC needs attention
Ci sono problemi da risolvere: guarda le voci con la croce rossa.	There are problems to solve: look at the items with the red cross.
{}   {} a posto · {} da guardare · {} problemi   (controllo del {})	{}   {} OK · {} to check · {} problems   (checked on {})
   ·   {} da guardare	   ·   {} to check
   ·   tutto a posto	   ·   all OK
Report dello stato del PC: {}/100 ({} a posto, {} da guardare, {} problemi).	PC status report: {}/100 ({} OK, {} to check, {} problems).
Memoria e disco	Memory and disk
Scansione in corso...	Scanning...
Come si usa:  1) scegli una sezione qui sotto o un profilo   2) accendi le voci che vuoi   3) premi 'Anteprima e applica'.  Con la Modalità prova accesa non viene modificato niente; ogni modifica vera è preceduta da punto di ripristino e backup, e si annulla con 'Annulla tutto'.	How to use:  1) choose a section below or a profile   2) turn on the items you want   3) press 'Preview and apply'.  With Dry-run mode on nothing is changed; every real change is preceded by a restore point and backup, and can be undone with 'Undo all'.
Stato in tempo reale	Real-time status
Il report compare quando finisce la scansione.	The report appears when the scan finishes.
Report dello stato del PC	PC status report
Generale	General
Scheda	Card
Servizi e attività	Services and tasks
Privacy e pubblicità	Privacy and ads
Prestazioni ed energia	Performance and power
Grafica ed effetti	Graphics and effects
Latenza e reattività	Latency and responsiveness
Pulizia disco	Disk cleanup
Accurata	Thorough
Misura la latenza	Measure latency
Invia 20 ping al router e al server DNS e mostra tempo medio, minimo, massimo, variazione (jitter) e pacchetti persi. Non modifica niente.	Sends 20 pings to the router and the DNS server and shows average, minimum and maximum time, variation (jitter) and lost packets. Changes nothing.
Misura prima e dopo le modifiche per vedere la differenza (meglio con il cavo e senza download in corso).	Measure before and after the changes to see the difference (best with a cable and no downloads in progress).
Pulizia sicura	Safe cleanup
Sicura	Safe
Spunta solo le voci a rischio basso (temporanei, cache, vecchi registri) e mostra l'anteprima. Non tocca Cestino e Windows Update.	Ticks only low-risk items (temporary files, caches, old logs) and shows the preview. Does not touch the Recycle Bin and Windows Update.
Pulizia accurata	Thorough cleanup
Spunta anche le voci a rischio medio (download di Windows Update già usati, Cestino) e mostra l'anteprima. La pulizia dei componenti di Windows (DISM) resta in Avanzate.	Also ticks medium-risk items (Windows Update downloads already used, Recycle Bin) and shows the preview. Windows components cleanup (DISM) stays in Advanced.
Solo impostazioni della scheda video: massimi FPS e minima latenza, a scapito della qualità dell'immagine	Graphics card settings only: maximum FPS and minimum latency, at the expense of image quality
Solo impostazioni della scheda video: valori equilibrati tra FPS, qualità, consumi e calore	Graphics card settings only: balanced values between FPS, quality, consumption and heat
Solo impostazioni della scheda video: migliore qualità dell'immagine (filtri e anti-aliasing al massimo), con meno FPS	Graphics card settings only: best image quality (filters and anti-aliasing at maximum), with fewer FPS
Riporta ogni impostazione al valore di serie del driver	Resets every setting to the driver's default value
Annulla scelte	Clear choices
I menu tornano a mostrare i valori attuali: niente da applicare	The menus show the current values again: nothing to apply
Nessuna connessione di rete attiva: non c'è niente da misurare.	No active network connection: there is nothing to measure.
Misuro la latenza verso {} (20 ping ciascuno)...	Measuring latency to {} (20 pings each)...
{} ({}): non risponde	{} ({}): not responding
Misura delle {}:\n{}	Measurement of {}:\n{}
Misura della latenza: {}	Latency measurement: {}
Misura della latenza completata.	Latency measurement completed.
Game Ready: ottimizzati per i giochi più recenti.  Studio: più collaudati, per programmi di grafica e video.	Game Ready: optimized for the newest games.  Studio: more thoroughly tested, for graphics and video programs.
Versione da installare: la più recente, la stessa già installata o una precedente	Version to install: the latest, the same one already installed or an earlier one
Premi "Cerca versioni" per l'elenco	Press "Search versions" for the list
Cerca versioni	Search versions
Chiede a nvidia.com l'elenco dei driver per questa scheda (non scarica e non installa niente)	Asks nvidia.com for the list of drivers for this card (does not download or install anything)
Elenco aggiornato: scegli la versione e premi 'Installazione pulita'.	List updated: choose the version and press 'Clean install'.
Scarica la versione scelta, toglie i vecchi driver e la installa da zero (con punto di ripristino). Prima vedi tutto e confermi.	Downloads the chosen version, removes the old drivers and installs it from scratch (with a restore point). You see everything first and confirm.
Versione di AMD Software: Adrenalin Edition da installare: la più recente, la stessa già installata o una precedente	AMD Software: Adrenalin Edition version to install: the latest, the same one already installed or an earlier one
Chiede ad amd.com l'elenco dei driver per questa scheda (non scarica e non installa niente)	Asks amd.com for the list of drivers for this card (does not download or install anything)
Scarica la versione scelta da drivers.amd.com, toglie i vecchi driver e avvia l'installazione (con punto di ripristino). Prima vedi tutto e confermi.	Downloads the chosen version from drivers.amd.com, removes the old drivers and starts the installation (with a restore point). You see everything first and confirm.
Usa un programma di installazione AMD già scaricato	Use an AMD installer already downloaded
Sito ufficiale	Official site
Apre la pagina ufficiale dei driver {}: lì scegli e scarichi la versione che vuoi	Opens the official {} driver page: there you choose and download the version you want
Installazione pulita da file...	Clean install from file...
Scegli il programma di installazione scaricato dal sito ufficiale: il programma verifica la firma, toglie i vecchi driver e lo avvia (con punto di ripristino)	Choose the installer downloaded from the official site: the program checks the signature, removes the old drivers and starts it (with a restore point)
Driver di base di Windows: il driver del produttore non è installato	Basic Windows driver: the manufacturer's driver is not installed
Driver {} del {}  ·  {}	Driver {} of {}  ·  {}
non riuscito	failed
Tutti i programmi e le app dello Store installati. 'Disinstalla e pulisci' avvia il programma di disinstallazione dell'app e poi cerca le cartelle e le chiavi di registro rimaste: le vedi una per una e scegli tu cosa togliere. Le cartelle vanno nel Cestino e le chiavi vengono salvate in un file .reg. Driver, runtime e componenti di Windows sono protetti.	All installed programs and Store apps. 'Uninstall and clean up' runs the app's uninstaller and then looks for leftover folders and registry keys: you see them one by one and choose what to remove. Folders go to the Recycle Bin and keys are saved in a .reg file. Drivers, runtimes and Windows components are protected.
Driver video	Video drivers
Driver delle schede video. 'Controlla aggiornamenti' chiede l'ultima versione a nvidia.com e ad amd.com: non installa niente. Puoi scegliere la versione da installare (anche la stessa o una precedente) e fare un'installazione pulita; ogni installazione parte solo dopo la tua conferma, con punto di ripristino.	Video card drivers. 'Check for updates' asks nvidia.com and amd.com for the latest version: it installs nothing. You can choose the version to install (even the same one or an earlier one) and do a clean installation; every installation starts only after your confirmation, with a restore point.
Altri driver	Other drivers
Chipset, audio, rete, Bluetooth e driver del produttore del PC. 'Controlla aggiornamenti' cerca nel catalogo driver di Windows Update (driver certificati dai produttori): non installa niente. Accendi i driver che vuoi e premi 'Installa selezionati', oppure 'Installa tutto'.	Chipset, audio, network, Bluetooth and PC manufacturer drivers. 'Check for updates' searches the Windows Update driver catalog (drivers certified by manufacturers): it installs nothing. Turn on the drivers you want and press 'Install selected', or 'Install all'.
Altro	Other
Registro attività	Activity log
Tutto quello che il programma legge e fa viene scritto qui e nei file della cartella Dati\Log.	Everything the program reads and does is written here and in the files of the Dati\Log folder.
QUESTIONARIO DI FEEDBACK - REGIA\n=================================\nCompila quello che ti va (anche solo alcune righe) e rimanda questo file insieme al resto dello .zip.\n\nIl tuo PC (portatile/fisso, marca, scheda video):\n______________________________________________\n\n1) Il programma si e' avviato senza problemi?   SI / NO   (se no, cosa e' successo?)\n______________________________________________\n\n2) La Panoramica era chiara? I dati in tempo reale (processore, memoria, scheda video, dischi, rete)\n   e il report con i simboli ti sono sembrati corretti e utili?\n______________________________________________\n\n3) Hai provato un profilo o delle voci in "Modalita' prova"? Cosa hai visto nell'anteprima?\n______________________________________________\n\n4) Hai applicato davvero delle modifiche? Quali? Il PC e' migliorato, uguale o peggiorato?\n______________________________________________\n\n5) Qualche testo non si capiva, o c'era un termine troppo tecnico?\n______________________________________________\n\n6) Qualcosa non ha funzionato, e' sembrato lento o si e' bloccato? (quando, in quale sezione)\n______________________________________________\n\n7) Cosa manca? Cosa useresti di piu'?\n______________________________________________\n\n8) Voto da 1 a 10 e un commento libero:\n______________________________________________	FEEDBACK QUESTIONNAIRE - REGIA\n=================================\nFill in whatever you like (even just a few lines) and send this file back together with the rest of the .zip.\n\nYour PC (laptop/desktop, brand, graphics card):\n______________________________________________\n\n1) Did the program start without problems?   YES / NO   (if not, what happened?)\n______________________________________________\n\n2) Was the Overview clear? Did the real-time data (processor, memory, graphics card, disks, network)\n   and the report with the symbols seem correct and useful?\n______________________________________________\n\n3) Did you try a profile or some items in "Dry-run mode"? What did you see in the preview?\n______________________________________________\n\n4) Did you really apply any changes? Which ones? Did the PC get better, the same or worse?\n______________________________________________\n\n5) Was any text unclear, or was there a term that was too technical?\n______________________________________________\n\n6) Did something not work, seem slow or freeze? (when, in which section)\n______________________________________________\n\n7) What is missing? What would you use more?\n______________________________________________\n\n8) Score from 1 to 10 and a free comment:\n______________________________________________
Creo sul desktop un file .zip da mandare a chi ti ha dato Regia.\n\nContiene:\n•  informazioni sul PC (Windows, processore, scheda video, memoria);\n•  il report sullo stato del PC e l'elenco delle voci trovate dalla scansione;\n•  il registro di oggi (cosa ha fatto il programma);\n•  il questionario da compilare.\n\nIl nome utente e il nome del PC vengono sostituiti con 'UTENTE' e 'PC'. Non contiene password, file personali, documenti o foto. Niente viene inviato: il file lo mandi tu.\n\nVuoi crearlo?	I will create a .zip file on the desktop to send to whoever gave you Regia.\n\nIt contains:\n•  information about the PC (Windows, processor, graphics card, memory);\n•  the PC status report and the list of items found by the scan;\n•  today's log (what the program did);\n•  the questionnaire to fill in.\n\nThe user name and PC name are replaced with 'UTENTE' and 'PC'. It contains no passwords, personal files, documents or photos. Nothing is sent: you send the file yourself.\n\nDo you want to create it?
File per il feedback	Feedback file
Regia {}\nData: {}\n{}\nPowerShell {}\nModalità prova: {}\n	Regia {}\nDate: {}\n{}\nPowerShell {}\nDry-run mode: {}\n
Punteggio: {}/100  ({} a posto, {} da guardare, {} problemi)\n\n	Score: {}/100  ({} OK, {} to check, {} problems)\n\n
Report non disponibile (scansione non completata).	Report not available (scan not completed).
File per il feedback creato: {}	Feedback file created: {}
File per il feedback creato sul desktop.	Feedback file created on the desktop.
Creato sul desktop:\n{}\n\nApri il file 05_QUESTIONARIO.txt dentro lo .zip, rispondi alle domande che vuoi, poi manda lo .zip a chi ti ha dato Regia.\n\nGrazie!	Created on the desktop:\n{}\n\nOpen the 05_QUESTIONARIO.txt file inside the .zip, answer the questions you like, then send the .zip to whoever gave you Regia.\n\nThank you!
Gli aggiornamenti online non sono ancora attivati in questa copia di Regia.\n\nChi pubblica il programma deve indicare l'indirizzo del file versione.json (vedi PUBBLICARE_ONLINE.txt).	Online updates are not yet enabled in this copy of Regia.\n\nWhoever publishes the program must provide the address of the versione.json file (see PUBBLICARE_ONLINE.txt).
Aggiornamenti	Updates
Indirizzo aggiornamenti non valido (serve https): {}	Invalid updates address (https required): {}
Controllo aggiornamenti di Regia...	Checking for Regia updates...
ERRORE: nessuna risposta	ERROR: no response
Controllo aggiornamenti non riuscito: {}	Update check failed: {}
Controllo aggiornamenti non riuscito (nessuna connessione?).	Update check failed (no connection?).
Non sono riuscito a controllare gli aggiornamenti.\n\nControlla la connessione a Internet e riprova.\n\n{}	I could not check for updates.\n\nCheck your Internet connection and try again.\n\n{}
versione.json incompleto o non valido.	versione.json incomplete or not valid.
Il pacchetto è su un sito diverso da versione.json ({}): ignorato.	The package is on a different site from versione.json ({}): ignored.
File versione.json non valido: {}	Invalid versione.json file: {}
Controllo aggiornamenti: file versione.json non valido.	Update check: invalid versione.json file.
Il file con le informazioni sull'aggiornamento non è valido.\n\n{}	The file with the update information is not valid.\n\n{}
Regia {} è la versione più recente.	Regia {} is the latest version.
Hai già la versione più recente di Regia ({}).	You already have the latest version of Regia ({}).
Aggiorna alla {}	Update to {}
Aggiornamento disponibile: Regia {} (hai la {}).	Update available: Regia {} (you have {}).
È disponibile Regia {}: premi 'Aggiorna' in basso a sinistra.	Regia {} is available: press 'Update' at the bottom left.
\n\nNovità:\n{}	\n\nWhat's new:\n{}
Aggiorno Regia dalla versione {} alla {}?{}\n\nIl pacchetto viene scaricato da:\n{}\ne controllato con l'impronta SHA-256. Prima di sostituire il programma ne salvo una copia nella cartella Versioni. Dati, backup, log e profili non vengono toccati. Alla fine Regia si riavvia.	Update Regia from version {} to {}?{}\n\nThe package is downloaded from:\n{}\nand checked with the SHA-256 fingerprint. Before replacing the program I save a copy in the Versioni folder. Data, backups, logs and profiles are not touched. At the end Regia restarts.
Aggiornamento di Regia	Regia update
Download non riuscito. {}	Download failed. {}
Il file scaricato non corrisponde all'impronta SHA-256 attesa: aggiornamento annullato, il programma non è stato modificato.	The downloaded file does not match the expected SHA-256 fingerprint: update cancelled, the program was not modified.
Il nuovo Regia.ps1 non è nel formato atteso (manca il BOM UTF-8).	The new Regia.ps1 is not in the expected format (UTF-8 BOM missing).
Il nuovo Regia.ps1 contiene errori di sintassi: {}	The new Regia.ps1 contains syntax errors: {}
La versione dentro il pacchetto non è la {}.	The version inside the package is not {}.
Versione attuale salvata in {}	Current version saved in {}
Regia aggiornato alla versione {}.	Regia updated to version {}.
Aggiornato alla versione {}.	Updated to version {}.
Aggiornamento completato: ora hai la versione {}.\n\nRiavvio Regia adesso?	Update completed: you now have version {}.\n\nRestart Regia now?
Aggiornamento non riuscito: {}	Update failed: {}
Tutte le voci sono state spente.	All items have been turned off.
Modalità prova ATTIVATA: nessuna modifica verrà applicata.	Dry-run mode TURNED ON: no changes will be applied.
Modalità prova DISATTIVATA: le modifiche confermate verranno applicate davvero.	Dry-run mode TURNED OFF: confirmed changes will be really applied.
Regia è in MODALITÀ PROVA.\n\nPuoi guardare, scegliere e vedere l'anteprima di tutto, ma le modifiche NON vengono applicate al PC finché non togli la spunta da «Modalità prova» (interruttore in alto a destra).\n\nQuando sei pronto a modificare davvero, spegni l'interruttore: prima di ogni modifica ti verrà chiesta conferma e potrai creare un punto di ripristino.	Regia is in DRY-RUN MODE.\n\nYou can look, choose and preview everything, but changes are NOT applied to the PC until you untick «Dry-run mode» (switch at the top right).\n\nWhen you are ready to really make changes, turn the switch off: before every change you will be asked to confirm and you can create a restore point.
Modalità prova attiva	Dry-run mode on
Elenco dispositivi non disponibile: {}	Device list not available: {}
Elenco app non disponibile: {}	App list not available: {}
Windows ha operazioni che si completano al riavvio.	Windows has operations that complete at restart.
Modalità prova ATTIVA: nessuna modifica verrà applicata finché non spegni l'interruttore.	Dry-run mode ON: no changes will be applied until you turn the switch off.
• Salva documenti, progetti e partite: i programmi aperti verranno chiusi.\n• Aspetta che finiscano download, copie di file e installazioni.\n• Se un programma ha lavoro non salvato, Windows te lo chiede e puoi ancora annullare il riavvio.	• Save documents, projects and game progress: open programs will be closed.\n• Wait for downloads, file copies and installations to finish.\n• If a program has unsaved work, Windows asks you and you can still cancel the restart.
1. Scegli la versione (la più recente, la stessa già installata o una precedente).   2. Il programma la scarica dal sito ufficiale del produttore e controlla la firma digitale.   3. Punto di ripristino.   4. Rimozione dei driver video presenti, comprese le vecchie versioni rimaste nell'archivio di Windows, con lo strumento ufficiale di Windows (pnputil).   5. Installazione del nuovo driver e verifica della versione. Con la Modalità prova accesa vedi tutti i passi senza che il driver venga toccato.	1. Choose the version (the latest, the same one already installed or an earlier one).   2. The program downloads it from the manufacturer's official site and checks the digital signature.   3. Restore point.   4. Removal of the video drivers present, including old versions left in the Windows store, with the official Windows tool (pnputil).   5. Installation of the new driver and version check. With Dry-run mode on you see all the steps without the driver being touched.
A COSA SERVE	WHAT IT'S FOR
Accende tutto quello che serve a migliorare il PC, anche voci a rischio medio (rimozione app, servizi, app in background). Prima mostra un avviso.	Turns on everything that helps improve the PC, including medium-risk items (app removal, services, background apps). A warning is shown first.
Accesa: il programma mostra e scrive nel log cosa farebbe, ma non modifica niente	On: the program shows and writes to the log what it would do, but changes nothing
Acceso = applica questa voce	On = apply this item
Acceso = installa questo driver con 'Installa selezionati'	On = install this driver with 'Install selected'
ADESSO	NOW
Aggiorna elenco	Refresh list
AGGIORNAMENTI DISPONIBILI	AVAILABLE UPDATES
Aggiornamento disponibile	Update available
Annulla	Cancel
Annulla tutto	Undo all
Anteprima	Preview
Anteprima e applica	Preview and apply
APP	APP
Apri la pagina dei driver del produttore nel browser	Open the manufacturer's driver page in the browser
AREA	AREA
Attività in corso	Activity in progress
Avvia la disinstallazione dell'app scelta, poi cerca e rimuove i residui (cartelle e chiavi di registro), con backup	Starts uninstalling the chosen app, then looks for and removes leftovers (folders and registry keys), with backup
Bilanciato	Balanced
Cambia tema scuro / chiaro	Switch dark / light theme
Cartella dati: apre la cartella con log, backup e profili	Data folder: opens the folder with logs, backups and profiles
CATEGORIA	CATEGORY
Cerca aggiornamenti: controlla se esiste una versione più recente di Regia	Check for updates: checks whether a newer version of Regia exists
Cerca per nome o editore...	Search by name or publisher...
Chiude la sessione di Windows senza spegnere il PC: basta per le modifiche che hanno effetto alla disconnessione	Signs out of Windows without shutting down the PC: enough for changes that take effect at sign-out
Collegamento sul desktop: crea sul desktop un collegamento con l'icona del programma, che lo avvia come amministratore	Desktop shortcut: creates a shortcut with the program icon on the desktop, which starts it as administrator
COME FUNZIONA L'INSTALLAZIONE PULITA	HOW CLEAN INSTALLATION WORKS
COMPONENTE	COMPONENT
COMPONENTI DA INSTALLARE	COMPONENTS TO INSTALL
Conferma	Confirm
Controlla aggiornamenti	Check for updates
Crea file per il feedback: un .zip sul desktop con report, scansione e registro (senza nome utente né nome del PC) da inviare a chi ti ha dato Regia	Create feedback file: a .zip on the desktop with report, scan and log (without user name or PC name) to send to whoever gave you Regia
DA APPLICARE	TO APPLY
DA IMPOSTARE	TO SET
DATA	DATE
DIMENSIONE	SIZE
Disconnetti	Sign out
Disinstalla e pulisci...	Uninstall and clean up...
DISPOSITIVI E DRIVER INSTALLATI	INSTALLED DEVICES AND DRIVERS
DISPOSITIVO	DEVICE
DIVENTERÀ	WILL BECOME
DRIVER	DRIVER
È disponibile una versione più recente di Regia: premi per aggiornare (prima ti mostra le novità e chiede conferma)	A newer version of Regia is available: press to update (it first shows what's new and asks for confirmation)
EDITORE	PUBLISHER
Equilibrio per l'uso di tutti i giorni: piano Bilanciato, meno notifiche inutili, avvio veloce, Esplora file più pratico	Balance for everyday use: Balanced plan, fewer useless notifications, fast startup, more practical File Explorer
ESITO	RESULT
FONTE	SOURCE
Grafica ed editing	Graphics and editing
IMPOSTAZIONE	SETTING
Installa i driver con la casella accesa, uno dopo l'altro (un solo punto di ripristino)	Installs the drivers with the checkbox on, one after the other (a single restore point)
Installa il pacchetto completo, senza togliere niente (compresa NVIDIA App)	Installs the full package, removing nothing (including NVIDIA App)
Installa selezionati	Install selected
Installa tutti i driver in elenco, uno dopo l'altro (un solo punto di ripristino)	Installs all the drivers in the list, one after the other (a single restore point)
Installa tutto	Install all
Installa...	Install...
INSTALLATA	INSTALLED
Installazione pulita	Clean install
Massimo	Maximum
Migliori prestazioni nei giochi: Game Mode, HAGS, piano Prestazioni elevate, meno processi in background. Non tocca la scheda video.	Better performance in games: Game Mode, HAGS, High performance plan, fewer background processes. Does not touch the graphics card.
Migliori prestazioni per grafica ed editing, senza toccare colori, HDR e impostazioni delle app creative. Non tocca la scheda video.	Better performance for graphics and editing, without touching colors, HDR and creative apps' settings. Does not touch the graphics card.
Modalità prova	Dry-run mode
Non rimuovere niente	Remove nothing
NOTE	NOTES
PERCORSO	PATH
Più tardi	Later
Portatile a batteria	Laptop on battery
Portatili a batteria: massima autonomia, app in background bloccate, effetti ridotti. Non tocca la scheda video.	Battery laptops: maximum battery life, background apps blocked, reduced effects. Does not touch the graphics card.
PREDEFINITO	DEFAULT
PRIMA DI RIAVVIARE	BEFORE RESTARTING
PROCEDURA	PROCEDURE
PRODUTTORE	MANUFACTURER
PROFILO	PROFILE
Regia è gratuito e senza pubblicità: se ti è utile puoi offrire un caffè allo sviluppatore (apre la pagina nel browser)	Regia is free and ad-free: if it is useful you can buy the developer a coffee (opens the page in the browser)
Residui	Leftovers
Riavvia il PC	Restart the PC
Riavvia il PC (prima ti ricorda di salvare il lavoro aperto)	Restart the PC (first it reminds you to save open work)
Riavvia ora	Restart now
Rilegge l'elenco dei programmi installati	Re-reads the list of installed programs
Rilegge lo stato del PC (sola lettura)	Re-reads the PC status (read-only)
Rimette i valori originali salvati nei backup di questo PC	Restores the original values saved in this PC's backups
Rimette le voci accese come in un Windows appena installato (non vale per app e pulizia)	Puts the items turned on back as in a freshly installed Windows (not for apps and cleanup)
Rimozione completa: toglie i vecchi driver anche dall'archivio di Windows	Complete removal: removes old drivers from the Windows store too
Rimuovi i residui accesi	Remove the ticked leftovers
Riporta al predefinito	Restore defaults
RISCHIO	RISK
Salva	Save
Salva profilo: salva le voci accese adesso come un tuo profilo	Save profile: saves the items turned on right now as your own profile
Scansiona	Scan
Scegli il valore da applicare con 'Anteprima e applica'	Choose the value to apply with 'Preview and apply'
SCHEDE VIDEO  ·  INSTALLAZIONE PULITA	GRAPHICS CARDS  ·  CLEAN INSTALL
Seleziona una voce per leggerne la spiegazione	Select an item to read its explanation
Sicuro	Safe
Solo app dello Store	Store apps only
Solo modifiche leggere e reversibili: privacy, pubblicità, Esplora file e file temporanei. Non rimuove app e non tocca servizi, energia e scheda video.	Only light, reversible changes: privacy, ads, File Explorer and temporary files. Does not remove apps and does not touch services, power and the graphics card.
Solo programmi classici	Classic programs only
Sostieni Regia	Support Regia
Standard: solo l'installazione pulita del produttore	Standard: only the manufacturer's clean installation
STATO	STATUS
STATO ATTUALE	CURRENT STATE
Svuota anche la cache degli shader (consigliato quando cambi versione)	Also empties the shader cache (recommended when you change version)
TIPO	TYPE
Togli spunte: spegne tutte le voci accese	Clear ticks: turns off all items that are on
Torna indietro	Go back
Tutte le app	All apps
ULTIMA DISPONIBILE	LATEST AVAILABLE
Vecchi driver	Old drivers
VERSIONE	VERSION
VOCE	ITEM
Windows sta lavorando ad aggiornamenti in questo momento: se puoi, aspetta qualche minuto prima di riavviare.	Windows is working on updates right now: if you can, wait a few minutes before restarting.
Attivo	Active
Attiva	On
Attivata	On
Disattivata	Off
Spento	Off
Acceso	On
A posto	OK
Da modificare	To change
Da pulire	To clean
Da applicare	To apply
Info	Info
Errore	Error
Non presente	Not present
Su richiesta	On request
Eseguire	Run
Pulire	Clean
Rimossa	Removed
Installata	Installed
Scelta dal menu	Chosen from the menu
Predefinita	Default
basso	low
medio	medium
alto	high
Generale	General
Windows	Windows
Scheda video	Graphics card
Sistema	System
Manutenzione	Maintenance
Panoramica	Overview
App preinstallate	Preinstalled apps
Programmi all'avvio	Startup programs
Servizi e attività	Services and tasks
Privacy e pubblicità	Privacy and ads
Prestazioni ed energia	Performance and power
Latenza e reattività	Latency and responsiveness
Grafica ed effetti	Graphics and effects
Esplora file	File Explorer
App installate	Installed apps
Impostazioni NVIDIA	NVIDIA settings
NVIDIA - opzioni avanzate	NVIDIA - advanced options
Impostazioni AMD	AMD settings
Driver video	Video drivers
Altri driver	Other drivers
Pulizia	Cleanup
Avanzate	Advanced
Registro attività	Activity log
Nessuna voce accesa	No items on
1 voce accesa	1 item on
Elenco app aggiornato: {} app.	App list updated: {} apps.
Usa un programma di installazione AMD già scaricato	Use an AMD installer already downloaded
Chiaro	Light
Scuro	Dark
{}  (consigliato)	{}  (recommended)
{}  (di serie)	{}  (default)
{}  (Windows)	{}  (Windows)
{} (consigliato)	{} (recommended)
{} · in esecuzione	{} · running
{} ({} file)	{} ({} files)
{} byte	{} bytes
{}   ·   tutto a posto	{}   ·   all OK
{}   ·   {} da guardare	{}   ·   {} to check
Sistema: {}	System: {}
PowerShell {} · cartella dati: {}	PowerShell {} · data folder: {}
=== Regia {} avviato (utente: {}, PC: {}) ===	=== Regia {} started (user: {}, PC: {}) ===
--- Scansione avviata (sola lettura) ---	--- Scan started (read-only) ---
=== Programma chiuso ===	=== Program closed ===
disco {}: {} liberi · portatile	disk {}: {} free · laptop
disco {}: {} liberi · fisso	disk {}: {} free · desktop
versione {} · build {}	version {} · build {}
Connessa ({}).	Connected ({}).
Connessa ({}, router {} ms).	Connected ({}, router {} ms).
Attivo: {}.	Active: {}.
Disattivate ({})	Disabled ({})
Sì	Yes
SISTEMA	SYSTEM
PRESTAZIONI	PERFORMANCE
DISCHI E HARDWARE	DISKS AND HARDWARE
SICUREZZA	SECURITY
EFFICIENZA	EFFICIENCY
MANUTENZIONE	MAINTENANCE
SCHEDA VIDEO	GRAPHICS CARD
ALTRO	OTHER
PRESET	PRESET
PULIZIA RAPIDA	QUICK CLEANUP
STATO IN TEMPO REALE	REAL-TIME STATUS
REPORT DELLO STATO DEL PC	PC STATUS REPORT
Accesa	On
Accese	On
Alta	High
Mai	Never
Aggiornate oggi.	Updated today.
Attivo.	Active.
Presente e pronto.	Present and ready.
Nessun dispositivo segnala errori.	No device reports errors.
Nessun programma superfluo all'avvio.	No unnecessary programs at startup.
Automatica	Automatic
Consenti	Allow
Consentiti	Allowed
Non consentiti	Not allowed
Decide l'applicazione	Application decides
Decide Edge	Edge decides
Globale	Global
Leggeri	Light
Media (Windows)	Medium (Windows)
Minimo (solo obbligatori)	Minimum (required only)
Nascosto	Hidden
Nessun limite	No limit
Nessun ritardo	No delay
Nessuna limitazione	No throttling
Nessuna sostituzione	No substitution
Nessuno	None
Normale (ottimale)	Normal (optimal)
Per singola app (Windows)	Per app (Windows)
Predefinita del driver	Driver default
Predefinito	Default
Prestazioni con un solo schermo	Single-screen performance
Qualità	Quality
Questo PC	This PC
Ritardate (Windows)	Delayed (Windows)
Solo dai server Microsoft	Only from Microsoft servers
Spenta	Off
Spente	Off
Spenti	Off
Spento	Off
Visibili	Visible
Bloccate	Blocked
Bloccati	Blocked
Disattivate	Disabled
Antialiasing - correzione gamma	Antialiasing - gamma correction
Antialiasing - FXAA	Antialiasing - FXAA
Antialiasing - MFAA	Antialiasing - MFAA
Antialiasing - trasparenza (multisampling)	Antialiasing - transparency (multisampling)
Disattivato (multicampionamento)	Disabled (multisampling)
Bassa latenza (fotogrammi pre-renderizzati)	Low latency (pre-rendered frames)
DLSS e fotogrammi	DLSS and frames
DLSS Multi Frame Generation: numero fotogrammi fissato	DLSS Multi Frame Generation: fixed number of frames
Filtro anisotropico - livello	Anisotropic filtering - level
Filtro texture - LOD bias negativo	Texture filtering - negative LOD bias
Filtro texture - ottimizzazione campione anisotropico	Texture filtering - anisotropic sample optimization
Filtro texture - ottimizzazione trilineare	Texture filtering - trilinear optimization
Occlusione ambientale (ambient occlusion)	Ambient occlusion
OpenGL e Vulkan	OpenGL and Vulkan
Risparmio energia PCI Express (a corrente)	PCI Express power saving (plugged in)
Sincronizzazione verticale (V-Sync)	Vertical sync (V-Sync)
Sistema, memoria e calcolo	System, memory and compute
Sospensione selettiva USB (a corrente)	USB selective suspend (plugged in)
Triplo buffering (OpenGL)	Triple buffering (OpenGL)
V-Sync adattiva (controllo strappi)	Adaptive V-Sync (tear control)
Percorsi lunghi (oltre 260 caratteri)	Long paths (over 260 characters)
Home / Accesso rapido	Home / Quick access
Avvio protetto (Secure Boot)	Secure Boot
Modulo TPM	TPM module
Memoria RAM	RAM memory
Tempo dall'ultimo avvio	Time since last startup
File temporanei dell'utente	User temporary files
Scorciatoie Tasti permanenti / Filtro tasti	Sticky Keys / Filter Keys shortcuts
Report sui consumi e sulle impostazioni energetiche	Report on consumption and power settings
Installazione pulita...	Clean install...
Usura massima dichiarata: {} %.	Maximum declared wear: {} %.
Intel Corporation	Intel Corporation
Disattivato (meglio attivo)	Disabled (better enabled)
temperatura non disponibile	temperature not available
lett. {} · scr. {}	read {} · write {}
attività {} %	activity {} %
{} di {} GB in uso	{} of {} GB in use
alimentatore collegato	plugged in
a batteria	on battery
cavo	wired
segnale {}	signal {}
ventola {} %	fan {} %
n.d.	n/a
Rete elettrica	Mains power
Nessuna rete	No network
Riavvio consigliato	Restart recommended
Riavvia il PC	Restart the PC
{} voci accese	{} items on
1 voce accesa	1 item on
Nessuna voce accesa	No items on
Disinstalla	Uninstall
Aggiorna alla {}	Update to {}
Programma	Program
Programma ({})	Program ({})
utente	user
32 bit	32-bit
App dello Store	Store app
Chiave	Key
Cartella	Folder
God Mode (tutte le impostazioni)	God Mode (all settings)
Apre la cartella 'God Mode' di Windows: tutte le impostazioni del Pannello di controllo (circa 200) in un unico elenco con ricerca. Da sola non cambia niente	Opens the Windows 'God Mode' folder: all Control Panel settings (about 200) in one searchable list. It changes nothing by itself
Aperto God Mode (tutte le impostazioni del Pannello di controllo).	Opened God Mode (all Control Panel settings).
Pulizia registro	Registry cleanup
Registro	Registry
Voci del registro rimaste da programmi che non esistono più: programmi all'avvio, comandi di Esegui e nomi ricordati. Si tocca solo quello che punta a un file sicuramente cancellato su un disco interno; chiavi di sistema, estensioni dei file e driver non vengono mai toccati. Prima di togliere qualcosa viene salvato tutto in Dati\Backup e 'Annulla tutto' lo rimette. Nota onesta: pulire il registro non rende il PC più veloce, serve a togliere errori e righe inutili. Le righe rotte di 'App installate' sono in Avanzate.	Registry entries left behind by programs that no longer exist: startup programs, Run commands and remembered names. Only entries pointing to a file that is definitely deleted on an internal drive are touched; system keys, file extensions and drivers are never touched. Before removing anything everything is saved in Dati\Backup and 'Undo all' puts it back. Honest note: cleaning the registry does not make the PC faster, it removes errors and useless entries. Broken 'Installed apps' entries are in Advanced.
Programmi all'avvio che non esistono più	Startup programs that no longer exist
Righe delle chiavi 'Run' che fanno partire all'accesso un file ormai cancellato (programmi disinstallati male): Windows prova ad aprirle ogni volta e fallisce. Si controllano solo percorsi completi su dischi interni presenti; chiavette e dischi scollegati non vengono mai giudicati. I valori tolti restano nel backup e 'Annulla tutto' li rimette.	Entries in the 'Run' keys that start a file that has been deleted (badly uninstalled programs) at sign-in: Windows tries to open them every time and fails. Only full paths on connected internal drives are checked; USB sticks and disconnected drives are never judged. Removed values stay in the backup and 'Undo all' puts them back.
Comandi "Esegui" di programmi cancellati (App Paths)	"Run" commands of deleted programs (App Paths)
Chiavi che permettono di avviare un programma scrivendone il nome in Esegui (Win+R) ma che puntano a un file che non c'è più. Prima di toglierla ogni chiave viene salvata in un file .reg in Dati\Backup; 'Annulla tutto' la rimette.	Keys that let you start a program by typing its name in Run (Win+R) but that point to a file that no longer exists. Each key is saved to a .reg file in Dati\Backup before it is removed; 'Undo all' puts it back.
Nomi ricordati di programmi cancellati (MuiCache)	Remembered names of deleted programs (MuiCache)
Windows ricorda il nome di ogni programma aperto (per esempio per il menu 'Apri con'). Si tolgono solo i nomi dei programmi che non esistono più. È soltanto una cache: serve all'ordine, non alla velocità.	Windows remembers the name of every program you open (for example for the 'Open with' menu). Only names of programs that no longer exist are removed. It is just a cache: this is about tidiness, not speed.
Programmi in "App installate" che non si possono più disinstallare	Programs in "Installed apps" that can no longer be uninstalled
Righe dell'elenco delle app installate il cui programma di disinstallazione e la cui cartella non esistono più: restano nell'elenco ma danno errore se provi a toglierle. Esclusi i pacchetti Windows Installer (MSI), i componenti di sistema e le righe senza nome. Controlla i nomi nella colonna 'Attuale' prima di applicare. Ogni chiave viene salvata in un file .reg in Dati\Backup; 'Annulla tutto' la rimette.	Entries in the installed apps list whose uninstaller and folder no longer exist: they stay in the list but give an error if you try to remove them. Windows Installer (MSI) packages, system components and entries without a name are excluded. Check the names in the 'Current' column before applying. Each key is saved to a .reg file in Dati\Backup; 'Undo all' puts it back.
Tolte (con backup)	Removed (with backup)
Nessuna voce rimasta	No leftover entries
1 voce rimasta: {}	1 leftover entry: {}
{} voci rimaste: {}	{} leftover entries: {}
Backup non preparato: non viene tolto niente.	Backup not prepared: nothing is removed.
Ritardo di apertura dei menu	Menu opening delay
100 ms	100 ms
400 ms (Windows)	400 ms (Windows)
Windows aspetta 0,4 secondi prima di aprire i sottomenu (clic destro, menu dei programmi, 'Invia a'). Con 100 ms si aprono quasi subito, ma non per sbaglio mentre passi sopra col mouse. Se il valore è già più basso (0-100 ms) resta com'è. È il valore MenuShowDelay del Pannello di controllo.	Windows waits 0.4 seconds before opening submenus (right-click, program menus, 'Send to'). With 100 ms they open almost instantly, but not by accident while you move the mouse over them. If the value is already lower (0-100 ms) it is left as it is. It is the MenuShowDelay value of the Control Panel.
{} ms	{} ms
Data di ultimo accesso ai file (NTFS)	File last-access date (NTFS)
Non aggiornata	Not updated
Decide Windows	Windows decides
Non aggiornata (decide Windows)	Not updated (Windows decides)
Non aggiornata (scelta a mano)	Not updated (set manually)
Aggiornata (decide Windows)	Updated (Windows decides)
Aggiornata (scelta a mano)	Updated (set manually)
Ogni volta che un file viene solo letto, Windows può scrivere sul disco anche la data di 'ultimo accesso'. Spegnendola si risparmiano piccole scritture continue (utile con giochi che leggono migliaia di file). Unico effetto collaterale: 'Sensore memoria' non sa più da quanto non apri un file nei Download, e i programmi di backup che usano questa data la vedono ferma. Stesso comando di 'fsutil behavior set disablelastaccess'.	Every time a file is merely read, Windows can also write its 'last access' date to the disk. Turning this off saves small continuous writes (useful with games that read thousands of files). Only side effect: 'Storage Sense' no longer knows how long ago you opened a file in Downloads, and backup programs that use this date see it frozen. Same as the 'fsutil behavior set disablelastaccess' command.
Precedenza ai programmi in primo piano	Priority for foreground programs
Programmi (come Windows)	Programs (as in Windows)
Programmi (valore {})	Programs (value {})
Servizi in background (valore 24)	Background services (value 24)
Valore cambiato da un altro programma ({})	Value changed by another program ({})
È l'opzione 'Ottimizza le prestazioni di: Programmi' (Win32PrioritySeparation): la finestra in primo piano, per esempio il gioco, riceve turni di CPU più lunghi dei programmi in background. Su Windows 10 e 11 è già così di serie (valore 2 o 38, che si equivalgono). Alcuni 'ottimizzatori' la cambiano con valori che favoriscono i servizi in background o che tolgono la precedenza: la voce controlla e, se serve, rimette il valore giusto.	It is the 'Adjust for best performance of: Programs' option (Win32PrioritySeparation): the foreground window, for example the game, gets longer CPU time slices than background programs. On Windows 10 and 11 this is already the default (value 2 or 38, which are equivalent). Some 'optimizers' change it to values that favour background services or remove the priority: this item checks it and, if needed, puts the right value back.
Rallentamento dei programmi in background (Power Throttling)	Background program slowdown (Power Throttling)
Spento	Off
Acceso (Windows)	On (Windows)
Windows mette i programmi in background in modalità a basso consumo (e sui processori Intel di nuova generazione li sposta sui core di efficienza). Spento, anche i programmi dietro al gioco (registrazione, streaming, chat vocale) girano a piena velocità. Vale anche a batteria: più consumo e calore. È l'impostazione ufficiale 'Disattiva la limitazione dell'alimentazione' dei Criteri di gruppo.	Windows puts background programs into a low-power mode (and on newer Intel processors moves them to the efficiency cores). With it off, programs behind the game (recording, streaming, voice chat) also run at full speed. It also applies on battery: more power use and heat. It is the official 'Turn off Power Throttling' Group Policy setting.
Rimette i valori originali salvati nei backup di questo PC: puoi scegliere quali voci	Restores the original values saved in this PC's backups: you can choose which items
Accendi tutte	Turn all on
Spegni tutte	Turn all off
MODIFICATA IL	CHANGED ON
TORNA A	GOES BACK TO
Annulla 1 voce	Undo 1 item
Annulla {} voci	Undo {} items
Simula: annulla 1 voce	Simulate: undo 1 item
Simula: annulla {} voci	Simulate: undo {} items
cambiata {} volte	changed {} times
reinstallabile dallo Store	reinstallable from the Store
richiede {}	requires {}
riavvio	restart
disconnessione	sign-out
NON annullabile	CANNOT be undone
AVANZATA	ADVANCED
DA FARE A MANO (protetta da Windows)	TO DO MANUALLY (protected by Windows)
Queste voci sono state modificate da Regia e hanno un backup su questo PC. Quelle accese tornano com'erano prima: spegni quelle che vuoi tenere (potrai annullarle anche più tardi).	These items were changed by Regia and have a backup on this PC. The ones switched on go back to how they were: switch off the ones you want to keep (you can undo them later too).
Se una voce è stata cambiata più volte, torna al valore che aveva prima della prima modifica. Le pulizie non si possono annullare. Le app rimosse vengono reinstallate se possibile, altrimenti si apre la loro pagina nel Microsoft Store.	If an item was changed several times, it goes back to the value it had before the first change. Cleanups cannot be undone. Removed apps are reinstalled if possible, otherwise their Microsoft Store page opens.
Annulla tutto: finestra chiusa senza annullare niente.	Undo all: window closed without undoing anything.
Elenco delle voci già annullate non leggibile: {}	List of items already undone cannot be read: {}
Backup {} non rinominato: {}	Backup {} not renamed: {}
Backup non leggibile, saltato: {} ({})	Unreadable backup, skipped: {} ({})
Ripristinerei: [{}] {}	Would restore: [{}] {}
Ripristino: {}...	Restoring: {}...
Ripristinato: [{}] {}	Restored: [{}] {}
Voci ripristinate: {}.  Errori: {}.	Items restored: {}.  Errors: {}.
Alcune modifiche hanno effetto dopo il riavvio o la disconnessione.	Some changes take effect after a restart or sign-out.
Le voci con errori restano nell'elenco di 'Annulla tutto': puoi riprovare.	Items with errors stay in the 'Undo all' list: you can try again.
Voci ripristinate: {}.  Errori: {}.\nAlcune modifiche hanno effetto dopo il riavvio o la disconnessione.\nLe voci con errori restano nell'elenco di 'Annulla tutto': puoi riprovare.	Items restored: {}.  Errors: {}.\nSome changes take effect after a restart or sign-out.\nItems with errors stay in the 'Undo all' list: you can try again.
'@

# I backup valgono solo per il PC su cui sono stati creati: se la cartella viene copiata su un altro PC,
# "Annulla tutto" non deve rimettere lì i valori di questo.
$imp = Leggi-Impostazioni
if (-not $imp.Computer) { Salva-Impostazione 'Computer' $env:COMPUTERNAME; $imp.Computer = $env:COMPUTERNAME }
$Script:BackupVecchiValidi = ([string]$imp.Computer -eq $env:COMPUTERNAME)
if (-not $Script:BackupVecchiValidi) {
    $Script:AvvisoAvvio = ("La cartella Dati proviene da un altro PC ($($imp.Computer)): i suoi backup vengono ignorati, i profili personali restano utilizzabili. " + $Script:AvvisoAvvio).Trim()
}
$Script:FileLog = Join-Path $Script:CartellaLog ('log_{0:yyyyMMdd}.txt' -f (Get-Date))

# Elementi dell'interfaccia (vengono impostati nella sezione 7)
$Script:Finestra   = $null
$Script:CasellaLog = $null
$Script:TestoStato = $null

# Scrive una riga nel file di log e nella scheda "Log" della finestra.
function Scrivi-Log {
    param(
        [string]$Messaggio,
        [ValidateSet('INFO', 'OK', 'AVVISO', 'ERRORE', 'PROVA')][string]$Livello = 'INFO'
    )
    $Messaggio = Tr $Messaggio
    $riga = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Livello, $Messaggio
    try { Add-Content -LiteralPath $Script:FileLog -Value $riga -Encoding UTF8 } catch { }
    if ($Script:CasellaLog) {
        $Script:CasellaLog.AppendText($riga + "`r`n")
        $Script:CasellaLog.ScrollToEnd()
    }
}

# Fa "respirare" la finestra durante le operazioni lunghe (ridisegna e risponde).
function Aggiorna-UI {
    if ($Script:Finestra) {
        $Script:Finestra.Dispatcher.Invoke([Action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

# Testo nella barra di stato in basso.
function Imposta-Stato([string]$Testo) {
    if ($Script:TestoStato) { $Script:TestoStato.Text = (Tr $Testo); Aggiorna-UI }
}

# Barra di avanzamento accanto al testo di stato.
#   $Percento da 0 a 100 = avanzamento preciso;  -1 = operazione in corso senza percentuale
#   (la barra scorre);  $null = nascosta.
$Script:BarraAvanzamento = $null
$Script:TestoAvanzamento = $null
$Script:RuotaAttesa = $null
function Imposta-Avanzamento($Percento) {
    $b = $Script:BarraAvanzamento
    if (-not $b) { return }
    if ($Script:RuotaAttesa) { $Script:RuotaAttesa.Visibility = $(if ($null -eq $Percento) { 'Collapsed' } else { 'Visible' }) }
    if ($null -eq $Percento) {
        $b.Visibility = 'Collapsed'; $b.IsIndeterminate = $false
        if ($Script:TestoAvanzamento) { $Script:TestoAvanzamento.Visibility = 'Collapsed' }
    } elseif ([double]$Percento -lt 0) {
        $b.IsIndeterminate = $true; $b.Visibility = 'Visible'
        if ($Script:TestoAvanzamento) { $Script:TestoAvanzamento.Visibility = 'Collapsed' }
    } else {
        $p = [math]::Max(0, [math]::Min(100, [double]$Percento))
        $b.IsIndeterminate = $false; $b.Value = $p; $b.Visibility = 'Visible'
        if ($Script:TestoAvanzamento) { $Script:TestoAvanzamento.Text = ('{0:N0}%' -f $p); $Script:TestoAvanzamento.Visibility = 'Visible' }
    }
    Aggiorna-UI
}

# Mostra un errore in modo comprensibile e lo scrive nel log.
function Mostra-Errore($Errore) {
    if ($Errore -is [System.Management.Automation.ErrorRecord]) {
        $msg = "$($Errore.Exception.Message)  (riga $($Errore.InvocationInfo.ScriptLineNumber))"
    } else {
        $msg = "$($Errore.Message)"
    }
    Scrivi-Log "Errore imprevisto: $msg" 'ERRORE'
    $testo = "Si è verificato un errore:`n`n$msg`n`nI dettagli sono nel log."
    try { [void](Mostra-Messaggio $testo 'Errore' 'OK' 'Error') }
    catch { [void][System.Windows.MessageBox]::Show($testo, 'Regia', 'OK', 'Error') }
}

# 1536000 -> "1,5 MB"
function Formatta-Dimensione([int64]$Byte) {
    if ($Byte -ge 1GB) { return '{0:N1} GB' -f ($Byte / 1GB) }
    if ($Byte -ge 1MB) { return '{0:N0} MB' -f ($Byte / 1MB) }
    if ($Byte -ge 1KB) { return '{0:N0} KB' -f ($Byte / 1KB) }
    return "$Byte byte"
}

# Converte "#RRGGBB" in un pennello WPF.
function Pennello([string]$Colore) {
    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Colore)
}

# I valori binari (byte[]) vengono salvati come elenco di numeri, così il JSON resta leggibile.
function Valore-PerJson($Valore) {
    if ($Valore -is [byte[]]) { return , @($Valore | ForEach-Object { [int]$_ }) }
    return $Valore
}

# Salva un oggetto in un file JSON (UTF-8).
function Salva-Json($Oggetto, [string]$Percorso) {
    $Oggetto | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Percorso -Encoding UTF8
}

# ==============================================================================
# 3. FUNZIONI DI SUPPORTO
# ==============================================================================

# ---------- 3a. Registro di sistema --------------------------------------------

# Legge un valore. Restituisce: Esiste (vero/falso), Valore, Tipo (DWord, String, Binary...).
function Leggi-Registro([string]$Percorso, [string]$Nome) {
    $assente = [pscustomobject]@{ Esiste = $false; Valore = $null; Tipo = $null }
    try { $chiave = Get-Item -LiteralPath $Percorso -ErrorAction Stop } catch { return $assente }
    if (-not ($chiave.GetValueNames() -contains $Nome)) { return $assente }
    $valore = $chiave.GetValue($Nome, $null, 'DoNotExpandEnvironmentNames')
    $tipo   = $chiave.GetValueKind($Nome).ToString()
    return [pscustomobject]@{ Esiste = $true; Valore = $valore; Tipo = $tipo }
}

# Scrive un valore (crea la chiave se manca, senza toccare il resto della chiave).
function Scrivi-Registro([string]$Percorso, [string]$Nome, $Valore, [string]$Tipo = 'DWord') {
    if (-not (Test-Path -LiteralPath $Percorso)) { New-Item -Path $Percorso -Force | Out-Null }
    if ($Tipo -eq 'Binary')      { $Valore = [byte[]]@($Valore | ForEach-Object { [byte]$_ }) }
    if ($Tipo -eq 'MultiString') { $Valore = [string[]]@($Valore) }
    New-ItemProperty -LiteralPath $Percorso -Name $Nome -Value $Valore -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
}

# Elimina un valore (usato per tornare a "non impostato").
function Rimuovi-Registro([string]$Percorso, [string]$Nome) {
    if (Test-Path -LiteralPath $Percorso) {
        Remove-ItemProperty -LiteralPath $Percorso -Name $Nome -ErrorAction SilentlyContinue
    }
}

# Confronta due valori di registro ($null = "non impostato").
function Confronta-Valori($A, $B) {
    if ($null -eq $A -and $null -eq $B) { return $true }
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A -is [array] -or $B -is [array]) { return ((@($A) -join ',') -eq (@($B) -join ',')) }
    return ([string]$A -eq [string]$B)
}

# ---------- 3b. Servizi ----------------------------------------------------------

# Servizi che il programma non modifica MAI, qualunque cosa ci sia nel catalogo.
$Script:ServiziProtetti = @(
    'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE',
    'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'BITS', 'TrustedInstaller', 'CryptSvc',
    'RpcSs', 'RpcEptMapper', 'DcomLaunch', 'EventLog', 'Dhcp', 'Dnscache', 'nsi',
    'Winmgmt', 'Schedule', 'ProfSvc', 'gpsvc', 'AppXSvc', 'ClipSVC', 'InstallService',
    'StateRepository', 'Power', 'PlugPlay', 'AudioSrv', 'AudioEndpointBuilder'
)

function Nome-Modo([string]$Modo) {
    switch ($Modo) {
        'Automatico'          { 'Automatico' }
        'AutomaticoRitardato' { 'Automatico (ritardato)' }
        'Manuale'             { 'Manuale' }
        'Disattivato'         { 'Disattivato' }
        default               { $Modo }
    }
}

# Legge come parte un servizio. Restituisce $null se il servizio non esiste.
function Leggi-AvvioServizio([string]$Nome) {
    $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $chiave = "HKLM:\SYSTEM\CurrentControlSet\Services\$Nome"
    $start  = (Leggi-Registro $chiave 'Start').Valore
    $rit    = (Leggi-Registro $chiave 'DelayedAutostart').Valore
    switch ([int]$start) {
        2       { $modo = $(if ($rit -eq 1) { 'AutomaticoRitardato' } else { 'Automatico' }) }
        3       { $modo = 'Manuale' }
        4       { $modo = 'Disattivato' }
        default { $modo = 'Sistema' }   # avvio di sistema/driver: mai toccato
    }
    return [pscustomobject]@{ Nome = $Nome; Modo = $modo; InEsecuzione = ($svc.Status -eq 'Running') }
}

# Cambia come parte un servizio (con sc.exe, che gestisce anche l'avvio ritardato).
function Imposta-AvvioServizio([string]$Nome, [string]$Modo) {
    if ($Script:ServiziProtetti -contains $Nome) { throw "Il servizio $Nome è protetto e non viene modificato." }
    $mappa = @{ 'Automatico' = 'auto'; 'AutomaticoRitardato' = 'delayed-auto'; 'Manuale' = 'demand'; 'Disattivato' = 'disabled' }
    $param = $mappa[$Modo]
    if (-not $param) { throw "Tipo di avvio non valido per ${Nome}: $Modo" }
    $uscita = & sc.exe config $Nome start= $param
    if ($LASTEXITCODE -ne 0) { throw "sc.exe ha restituito il codice $LASTEXITCODE per ${Nome}: $uscita" }
}

# ---------- 3c. Energia ----------------------------------------------------------

$Script:GuidBilanciato     = '381b4222-f694-41f0-9685-ff5bb260df2e'
$Script:GuidPrestazioni    = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
# "Modalità risparmio energia" di Windows 11 (Impostazioni > Sistema > Alimentazione).
# Funziona sopra al piano Bilanciato.
$Script:OverlayEquilibrato = '00000000-0000-0000-0000-000000000000'
$Script:OverlayEfficienza  = '961cc777-2547-4f9d-8174-7d86181b8a7a'
$Script:OverlayPrestazioni = 'ded574b5-45a0-4f42-8737-46345c09c238'

# Funzioni di Windows (powrprof.dll) per leggere/impostare la modalità di risparmio energia.
try {
    if (-not ('OttWin.Energia' -as [type])) {
        Add-Type -Namespace OttWin -Name Energia -MemberDefinition @'
[DllImport("powrprof.dll")] public static extern uint PowerGetActualOverlayScheme(out Guid actualOverlayGuid);
[DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid overlaySchemeGuid);
'@
    }
} catch { }

# Piani che valgono come "Prestazioni": "Prestazioni eccellenti" di Windows, più quelli personalizzati
# elencati in Dati\impostazioni.json (PianiPrestazioniExtra). Se uno di questi è attivo, la voce
# "Piano energetico: Prestazioni elevate" risulta già a posto.
# Per aggiungerne uno: powercfg /list, poi copia il suo GUID in impostazioni.json.
$Script:GuidPrestazioniEccellenti = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$Script:PianiPrestazioniExtra = @($Script:GuidPrestazioniEccellenti) + @((Leggi-Impostazioni).PianiPrestazioniExtra | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() })

$Script:RegexGuid ='([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]*)\)'

function Ottieni-PianoAttivo {
    $testo = (& powercfg.exe /getactivescheme) -join ' '
    if ($testo -match $Script:RegexGuid) { return [pscustomobject]@{ Guid = $Matches[1].ToLower(); Nome = $Matches[2] } }
    return [pscustomobject]@{ Guid = ''; Nome = '(sconosciuto)' }
}

function Ottieni-Piani {
    foreach ($riga in (& powercfg.exe /list)) {
        if ($riga -match $Script:RegexGuid) { [pscustomobject]@{ Guid = $Matches[1].ToLower(); Nome = $Matches[2] } }
    }
}

function Ottieni-Overlay {
    try {
        $g = [guid]::Empty
        if ([OttWin.Energia]::PowerGetActualOverlayScheme([ref]$g) -eq 0) { return $g.ToString().ToLower() }
    } catch { }
    $v = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme'
    if ($v.Esiste) { return ([string]$v.Valore).ToLower() }
    return $null
}

function Imposta-Overlay([string]$Guid) {
    try {
        $r = [OttWin.Energia]::PowerSetActiveOverlayScheme([guid]$Guid)
        if ($r -ne 0) { Scrivi-Log "Modalità di risparmio energia non impostata (codice $r)." 'AVVISO' }
    } catch {
        Scrivi-Log "Modalità di risparmio energia non disponibile: $($_.Exception.Message)" 'AVVISO'
    }
}

function Nome-Overlay([string]$Guid) {
    switch ($Guid) {
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'massima efficienza' }
        'ded574b5-45a0-4f42-8737-46345c09c238' { 'prestazioni migliori' }
        '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { 'prestazioni bilanciate' }
        '00000000-0000-0000-0000-000000000000' { 'equilibrata' }
        default { '' }
    }
}

function Imposta-Piano([string]$Guid) {
    & powercfg.exe /setactive $Guid | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive $Guid non riuscito (codice $LASTEXITCODE)." }
}

# Fotografia dello stato energetico (per il backup).
function Ottieni-StatoEnergia {
    $p = Ottieni-PianoAttivo
    return @{ Piano = $p.Guid; NomePiano = $p.Nome; Overlay = (Ottieni-Overlay) }
}

function Ripristina-StatoEnergia($O) {
    if ($O.Piano) { Imposta-Piano $O.Piano }
    if ($O.Overlay) { Imposta-Overlay $O.Overlay }
}

function Imposta-EnergiaPredefinita {
    Imposta-Piano $Script:GuidBilanciato
    Imposta-Overlay $Script:OverlayEquilibrato
}

# Attiva "Prestazioni elevate"; se manca lo ricrea; se Windows non lo consente
# usa Bilanciato + modalità "Prestazioni migliori".
function Attiva-PianoPrestazioni {
    $esiste = @(Ottieni-Piani | Where-Object { $_.Guid -eq $Script:GuidPrestazioni }).Count -gt 0
    if (-not $esiste) {
        Scrivi-Log "Il piano 'Prestazioni elevate' non è presente: provo a ricrearlo dal modello di Windows."
        & powercfg.exe -duplicatescheme $Script:GuidPrestazioni $Script:GuidPrestazioni | Out-Null
    }
    & powercfg.exe /setactive $Script:GuidPrestazioni | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    Scrivi-Log "Piano 'Prestazioni elevate' non attivabile: uso Bilanciato + modalità 'Prestazioni migliori'." 'AVVISO'
    Imposta-Piano $Script:GuidBilanciato
    Imposta-Overlay $Script:OverlayPrestazioni
}

# Legge lo stato energetico e dice se corrisponde al modo richiesto.
function Leggi-Energia([string]$Modo) {
    $piano = Ottieni-PianoAttivo
    $ov    = Ottieni-Overlay
    $bil   = ($piano.Guid -eq $Script:GuidBilanciato)
    $ovEq  = (($null -eq $ov) -or ($ov -eq $Script:OverlayEquilibrato))
    $testo = $piano.Nome
    if ($bil -and $ov) { $n = Nome-Overlay $ov; if ($n) { $testo += " · modalità $n" } }
    switch ($Modo) {
        'prestazioni' {
            $ok = ($piano.Guid -eq $Script:GuidPrestazioni) -or ($bil -and $ov -eq $Script:OverlayPrestazioni) -or
                  ($Script:PianiPrestazioniExtra -contains $piano.Guid)
        }
        'bilanciato'  { $ok = $bil -and $ovEq }
        'efficienza'  { $ok = $bil -and ($ov -eq $Script:OverlayEfficienza) }
    }
    # Il piano energetico è una scelta personale (Legion Toolkit, piani propri...): mai "da modificare", al massimo un'informazione.
    return Nuova-Lettura $testo $(if ($ok) { 'A posto' } else { 'Info' }) $true ($bil -and $ovEq)
}

# ---------- 3d. File e cartelle -----------------------------------------------------

# Elenca i file di una cartella senza seguire collegamenti/giunzioni (più sicuro).
function Elenca-File([string]$Cartella, [string]$Filtro = '*', [bool]$Ricorsivo = $true) {
    $risultato = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    if ([string]::IsNullOrWhiteSpace($Cartella) -or -not [System.IO.Directory]::Exists($Cartella)) { return , $risultato }
    $pila = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pila.Push((New-Object System.IO.DirectoryInfo($Cartella)))
    while ($pila.Count -gt 0) {
        $d = $pila.Pop()
        try { foreach ($f in $d.GetFiles($Filtro)) { $risultato.Add($f) } } catch { }
        if ($Ricorsivo) {
            try {
                foreach ($s in $d.GetDirectories()) {
                    if (($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { $pila.Push($s) }
                }
            } catch { }
        }
    }
    return , $risultato
}

# Elenca le sottocartelle (esclusa quella di partenza), senza seguire giunzioni.
function Elenca-Cartelle([string]$Cartella) {
    $risultato = New-Object 'System.Collections.Generic.List[System.IO.DirectoryInfo]'
    if (-not [System.IO.Directory]::Exists($Cartella)) { return , $risultato }
    $pila = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pila.Push((New-Object System.IO.DirectoryInfo($Cartella)))
    while ($pila.Count -gt 0) {
        $d = $pila.Pop()
        try {
            foreach ($s in $d.GetDirectories()) {
                if (($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { $risultato.Add($s); $pila.Push($s) }
            }
        } catch { }
    }
    return , $risultato
}

# Descrive un percorso da pulire.
#   Giorni = cancella solo i file più vecchi di N giorni (0 = tutti)
function Nuovo-PercorsoPulizia([string]$Percorso, [int]$Giorni = 1, [string]$Filtro = '*', [bool]$Ricorsivo = $true) {
    return @{ Percorso = $Percorso; Giorni = $Giorni; Filtro = $Filtro; Ricorsivo = $Ricorsivo }
}

# Controllo di sicurezza: mai pulire radici di disco, Windows, System32 o la cartella utente.
function Verifica-PercorsoSicuro([string]$Cartella) {
    $c = $Cartella.TrimEnd('\')
    $vietati = @($env:SystemDrive, $env:WINDIR, "$env:WINDIR\System32", $env:USERPROFILE, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    if ($c.Length -lt 8 -or ($vietati -contains $c)) { throw "Percorso non sicuro, pulizia rifiutata: $Cartella" }
}

# Cartelle reali di un percorso da pulire. Il percorso può contenere "*" al posto di una cartella
# (es. i profili dei browser: ...\User Data\*\Cache): vengono restituite tutte quelle che esistono.
function Espandi-Percorso([string]$Percorso) {
    $p = [Environment]::ExpandEnvironmentVariables($Percorso)
    if ($p -notmatch '\*') { return , @($p) }
    $trovate = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and (($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) } | ForEach-Object { $_.FullName })
    return , $trovate
}

function Misura-Percorso($P) {
    $limite = (Get-Date).AddDays(-[double]$P.Giorni)
    $byte = [int64]0; $n = 0
    foreach ($dir in (Espandi-Percorso $P.Percorso)) {
        foreach ($f in (Elenca-File $dir $P.Filtro $P.Ricorsivo)) {
            if ($f.LastWriteTime -lt $limite) { $byte += $f.Length; $n++ }
        }
    }
    return @{ Byte = $byte; File = $n }
}

function Pulisci-Percorso($P) {
    $tot = @{ Byte = [int64]0; File = 0; Saltati = 0 }
    foreach ($dir in (Espandi-Percorso $P.Percorso)) {
        $x = Pulisci-Cartella $P $dir
        $tot.Byte += $x.Byte; $tot.File += $x.File; $tot.Saltati += $x.Saltati
    }
    return $tot
}

# Cancella i file (quelli in uso vengono saltati senza errori) e le cartelle rimaste vuote.
function Pulisci-Cartella($P, [string]$dir) {
    if (-not [System.IO.Directory]::Exists($dir)) { return @{ Byte = [int64]0; File = 0; Saltati = 0 } }
    Verifica-PercorsoSicuro $dir
    $limite = (Get-Date).AddDays(-[double]$P.Giorni)
    $byte = [int64]0; $n = 0; $saltati = 0
    foreach ($f in (Elenca-File $dir $P.Filtro $P.Ricorsivo)) {
        if ($f.LastWriteTime -ge $limite) { continue }
        $lunghezza = $f.Length
        try { $f.Attributes = 'Normal'; $f.Delete(); $byte += $lunghezza; $n++ } catch { $saltati++ }
    }
    if ($P.Ricorsivo) {
        $cartelle = Elenca-Cartelle $dir
        foreach ($c in ($cartelle | Sort-Object { $_.FullName.Length } -Descending)) {
            try {
                $c.Refresh()
                if ($c.LastWriteTime -lt $limite -and -not $c.EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $c.Delete() }
            } catch { }
        }
    }
    return @{ Byte = $byte; File = $n; Saltati = $saltati }
}

# ---------- 3e. Processi e operazioni lunghe -----------------------------------------

# Avvia un programma e aspetta la fine senza bloccare la finestra.
#   $Visibile = $true: la finestra del programma resta visibile (es. programmi di installazione da seguire a mano)
function Esegui-Processo([string]$File, [string]$Argomenti = '', [bool]$Visibile = $false) {
    $param = @{ FilePath = $File; PassThru = $true }
    if ($Argomenti) { $param.ArgumentList = $Argomenti }
    if (-not $Visibile) { $param.WindowStyle = 'Hidden' }
    $p = Start-Process @param
    $null = $p.Handle   # necessario per leggere poi il codice di uscita
    while (-not $p.HasExited) { Aggiorna-UI; Start-Sleep -Milliseconds 200 }
    $p.WaitForExit()
    return $p.ExitCode
}

# Esegue un blocco di codice in parallelo (es. punto di ripristino) tenendo viva la finestra.
function Esegui-InBackground([scriptblock]$Codice, [object[]]$Argomenti = @()) {
    $ps = [powershell]::Create()
    [void]$ps.AddScript($Codice.ToString())
    foreach ($a in $Argomenti) { [void]$ps.AddArgument($a) }
    $h = $ps.BeginInvoke()
    while (-not $h.IsCompleted) { Aggiorna-UI; Start-Sleep -Milliseconds 150 }
    try {
        $risultato = $ps.EndInvoke($h)
        $errori = @($ps.Streams.Error)
    } finally { $ps.Dispose() }
    if ($errori.Count -gt 0) { throw $errori[0].Exception }
    return $risultato
}

# ---------- 3f. Impostazioni NVIDIA (NVAPI) ---------------------------------------
# Il Pannello di controllo NVIDIA salva le impostazioni globali in un archivio del driver (DRS).
# Per leggerle e scriverle si usa NVAPI, la libreria ufficiale già installata con il driver
# (nvapi64.dll). Codici delle funzioni e delle impostazioni: SDK pubblico NVIDIA (github.com/NVIDIA/nvapi).
try {
    if (-not ('OttWin.NvDrs' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OttWin
{
    public static class NvDrs
    {
        [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr QueryInterface(uint id);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DSemplice();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DCreaSessione(out IntPtr sessione);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DSessione(IntPtr sessione);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DProfiloGlobale(IntPtr sessione, out IntPtr profilo);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DLeggi(IntPtr sessione, IntPtr profilo, uint id, IntPtr impostazione);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DScrivi(IntPtr sessione, IntPtr profilo, IntPtr impostazione);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DRipristina(IntPtr sessione, IntPtr profilo, uint id);

        // Codici delle funzioni (nvapi_interface.h)
        private const uint ID_INIT = 0x0150e828, ID_CREA = 0x0694d52e, ID_DISTRUGGI = 0xdad9cff8,
            ID_CARICA = 0x375dbd6b, ID_SALVA = 0xfcbc7e14, ID_GLOBALE = 0x617bff9f,
            ID_LEGGI = 0x73bf8338, ID_SCRIVI = 0x577dd202, ID_RIPRISTINA = 0x53f0381e;

        // NVDRS_SETTING_V1: 4 + 4096 (nome) + 5*4 + 4100 (valore predefinito) + 4100 (valore attuale) = 12320 byte
        private const int DIMENSIONE = 12320;
        private const uint VERSIONE = DIMENSIONE | (1u << 16);
        private const int OFS_ID = 4100, OFS_TIPO = 4104, OFS_POSIZIONE = 4108, OFS_E_PREDEF = 4112, OFS_SERIE_VALIDA = 4116, OFS_SERIE = 4120, OFS_VALORE = 8220;
        public const int NON_TROVATA = -160;   // NVAPI_SETTING_NOT_FOUND

        private static bool inizializzato;

        private static T Funzione<T>(uint id) where T : class
        {
            IntPtr p = QueryInterface(id);
            if (p == IntPtr.Zero) throw new InvalidOperationException("Funzione NVAPI non disponibile: 0x" + id.ToString("X8"));
            return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
        }

        private static void Controlla(int codice, string cosa)
        {
            if (codice != 0) throw new InvalidOperationException("NVAPI " + cosa + " non riuscito (codice " + codice + ")");
        }

        public static bool Disponibile()
        {
            try
            {
                if (!inizializzato) { inizializzato = Funzione<DSemplice>(ID_INIT)() == 0; }
                return inizializzato;
            }
            catch { return false; }
        }

        // Apre una sessione sull'archivio delle impostazioni, esegue l'azione e chiude sempre.
        private static int ConSessione(Func<IntPtr, IntPtr, int> azione, bool salva)
        {
            if (!Disponibile()) throw new InvalidOperationException("NVAPI non disponibile (nessuna scheda o driver NVIDIA).");
            IntPtr s;
            Controlla(Funzione<DCreaSessione>(ID_CREA)(out s), "apertura sessione");
            try
            {
                Controlla(Funzione<DSessione>(ID_CARICA)(s), "caricamento impostazioni");
                IntPtr p;
                Controlla(Funzione<DProfiloGlobale>(ID_GLOBALE)(s, out p), "lettura profilo globale");
                int esito = azione(s, p);
                if (salva && esito == 0) Controlla(Funzione<DSessione>(ID_SALVA)(s), "salvataggio");
                return esito;
            }
            finally { Funzione<DSessione>(ID_DISTRUGGI)(s); }
        }

        // Legge un'impostazione DWORD del profilo globale.
        // Restituisce il codice NVAPI (0 = trovata, -160 = non impostata: vale il valore del driver).
        // "serie" = valore di serie dichiarato dal driver (valido solo se serieValida è vero).
        public static int Leggi(uint id, out uint valore, out int posizione, out bool ePredefinito, out uint serie, out bool serieValida)
        {
            uint v = 0; int pos = -1; bool pred = false; uint ser = 0; bool serOk = false;
            int codice = ConSessione((s, p) =>
            {
                IntPtr buf = Marshal.AllocHGlobal(DIMENSIONE);
                try
                {
                    for (int i = 0; i < DIMENSIONE; i += 4) Marshal.WriteInt32(buf, i, 0);
                    Marshal.WriteInt32(buf, 0, unchecked((int)VERSIONE));
                    int c = Funzione<DLeggi>(ID_LEGGI)(s, p, id, buf);
                    if (c == 0)
                    {
                        v = unchecked((uint)Marshal.ReadInt32(buf, OFS_VALORE));
                        pos = Marshal.ReadInt32(buf, OFS_POSIZIONE);
                        pred = Marshal.ReadInt32(buf, OFS_E_PREDEF) != 0;
                        serOk = Marshal.ReadInt32(buf, OFS_SERIE_VALIDA) != 0;
                        ser = unchecked((uint)Marshal.ReadInt32(buf, OFS_SERIE));
                    }
                    return c;
                }
                finally { Marshal.FreeHGlobal(buf); }
            }, false);
            valore = v; posizione = pos; ePredefinito = pred; serie = ser; serieValida = serOk;
            return codice;
        }

        // Scrive un'impostazione DWORD nel profilo globale e salva.
        public static void Scrivi(uint id, uint valore)
        {
            int c = ConSessione((s, p) =>
            {
                IntPtr buf = Marshal.AllocHGlobal(DIMENSIONE);
                try
                {
                    for (int i = 0; i < DIMENSIONE; i += 4) Marshal.WriteInt32(buf, i, 0);
                    Marshal.WriteInt32(buf, 0, unchecked((int)VERSIONE));
                    Marshal.WriteInt32(buf, OFS_ID, unchecked((int)id));
                    Marshal.WriteInt32(buf, OFS_TIPO, 0);   // NVDRS_DWORD_TYPE
                    Marshal.WriteInt32(buf, OFS_VALORE, unchecked((int)valore));
                    return Funzione<DScrivi>(ID_SCRIVI)(s, p, buf);
                }
                finally { Marshal.FreeHGlobal(buf); }
            }, true);
            Controlla(c, "scrittura impostazione 0x" + id.ToString("X8"));
        }

        // Rimette l'impostazione al valore predefinito del driver.
        public static void Ripristina(uint id)
        {
            int c = ConSessione((s, p) => Funzione<DRipristina>(ID_RIPRISTINA)(s, p, id), true);
            if (c != 0 && c != NON_TROVATA) Controlla(c, "ripristino impostazione 0x" + id.ToString("X8"));
        }
    }
}
'@
    }
} catch { }

# ---------- 3g. Impostazioni AMD (ADLX) ---------------------------------------------
# AMD Software: Adrenalin Edition salva le impostazioni grafiche globali nel driver; si leggono e
# scrivono con ADLX, la libreria ufficiale installata con il driver (amdadlx64.dll).
# Ordine delle funzioni (vtable) e valori: SDK pubblico AMD (github.com/GPUOpen-LibrariesAndSDKs/ADLX,
# file ADLX.h, ISystem.h, I3DSettings.h, ADLXDefines.h). Su un PC senza scheda AMD la libreria
# non c'è e la sezione AMD semplicemente non compare.
try {
    if (-not ('OttWin.AmdAdlx' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OttWin
{
    public static class AmdAdlx
    {
        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr LoadLibraryW(string nome);
        [DllImport("kernel32", CharSet = CharSet.Ansi, ExactSpelling = true)] private static extern IntPtr GetProcAddress(IntPtr modulo, string funzione);

        // Funzioni esportate: __cdecl.  Metodi delle interfacce: __stdcall (su 64 bit è la stessa convenzione).
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DInit(ulong versione, out IntPtr sistema);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DVersione(out ulong versione);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DOut(IntPtr self, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate uint DSize(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DAt(IntPtr self, uint i, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DGpuOut(IntPtr self, IntPtr gpu, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DOutBuf(IntPtr self, IntPtr buf);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DSetInt(IntPtr self, int valore);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int DRelease(IntPtr self);

        private static IntPtr sistema, gpu, servizi;
        private static bool tentato, pronto;
        public static string Errore = "";
        public static string NomeGpu = "";

        // ADLX_OK = 0, ADLX_ALREADY_ENABLED = 1, ADLX_ALREADY_INITIALIZED = 2 (macro ADLX_SUCCEEDED)
        private static bool Ok(int r) { return r == 0 || r == 1 || r == 2; }

        private static T Fn<T>(IntPtr obj, int posto) where T : class
        {
            IntPtr tabella = Marshal.ReadIntPtr(obj);
            IntPtr f = Marshal.ReadIntPtr(tabella, posto * IntPtr.Size);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(f, typeof(T));
        }

        private static void Rilascia(IntPtr obj) { if (obj != IntPtr.Zero) Fn<DRelease>(obj, 1)(obj); }   // IADLXInterface::Release

        public static bool Disponibile()
        {
            if (tentato) return pronto;
            tentato = true;
            try
            {
                IntPtr dll = LoadLibraryW("amdadlx64.dll");
                if (dll == IntPtr.Zero) { Errore = "amdadlx64.dll non trovata (driver AMD non installato)"; return false; }
                ulong ver = (2UL << 48) | 125UL;   // ADLX 2.0.0.125, sostituita dalla versione della libreria installata
                IntPtr pv = GetProcAddress(dll, "ADLXQueryFullVersion");
                if (pv != IntPtr.Zero)
                {
                    ulong v;
                    if (((DVersione)Marshal.GetDelegateForFunctionPointer(pv, typeof(DVersione)))(out v) == 0 && v != 0) ver = v;
                }
                int r = -1;
                foreach (string nome in new string[] { "ADLXInitialize", "ADLXInitializeWithIncompatibleDriver" })
                {
                    IntPtr pi = GetProcAddress(dll, nome);
                    if (pi == IntPtr.Zero) continue;
                    r = ((DInit)Marshal.GetDelegateForFunctionPointer(pi, typeof(DInit)))(ver, out sistema);
                    if (Ok(r) && sistema != IntPtr.Zero) break;
                }
                if (!Ok(r) || sistema == IntPtr.Zero) { Errore = "ADLX non inizializzato (codice " + r + ")"; return false; }

                IntPtr lista;
                r = Fn<DOut>(sistema, 1)(sistema, out lista);                 // IADLXSystem::GetGPUs
                if (!Ok(r) || lista == IntPtr.Zero) { Errore = "nessuna scheda AMD (codice " + r + ")"; return false; }
                uint n = Fn<DSize>(lista, 3)(lista);                          // IADLXList::Size
                IntPtr buf = Marshal.AllocHGlobal(8);
                try
                {
                    // Si preferisce la scheda dedicata (ADLX_GPU_TYPE: 2 = discreta)
                    for (uint i = 0; i < n; i++)
                    {
                        IntPtr g;
                        if (!Ok(Fn<DAt>(lista, 11)(lista, i, out g)) || g == IntPtr.Zero) continue;   // IADLXGPUList::At_GPUList
                        Marshal.WriteInt64(buf, 0);
                        int tipo = Ok(Fn<DOutBuf>(g, 5)(g, buf)) ? Marshal.ReadInt32(buf) : 0;      // IADLXGPU::Type
                        if (gpu == IntPtr.Zero) { gpu = g; if (tipo == 2) break; }
                        else if (tipo == 2) { Rilascia(gpu); gpu = g; break; }
                        else Rilascia(g);
                    }
                }
                finally { Marshal.FreeHGlobal(buf); }
                Rilascia(lista);
                if (gpu == IntPtr.Zero) { Errore = "nessuna scheda AMD"; return false; }
                IntPtr nome2;
                if (Ok(Fn<DOut>(gpu, 7)(gpu, out nome2)) && nome2 != IntPtr.Zero) NomeGpu = Marshal.PtrToStringAnsi(nome2);   // IADLXGPU::Name
                r = Fn<DOut>(sistema, 7)(sistema, out servizi);               // IADLXSystem::Get3DSettingsServices
                if (!Ok(r) || servizi == IntPtr.Zero) { Errore = "servizi 3D AMD non disponibili (codice " + r + ")"; return false; }
                pronto = true;
            }
            catch (Exception e) { Errore = e.Message; pronto = false; }
            return pronto;
        }

        // Interfaccia di una funzione (Anti-Lag, Chill, ...) dal servizio 3D: posto nella vtable di IADLX3DSettingsServices.
        private static IntPtr Funzione(int posto, bool conGpu)
        {
            IntPtr f;
            int r = conGpu ? Fn<DGpuOut>(servizi, posto)(servizi, gpu, out f) : Fn<DOut>(servizi, posto)(servizi, out f);
            if (!Ok(r) || f == IntPtr.Zero) throw new InvalidOperationException("funzione AMD non disponibile (codice " + r + ")");
            return f;
        }

        private static int LeggiDa(IntPtr f, int posto, bool booleano)
        {
            IntPtr buf = Marshal.AllocHGlobal(8);
            try
            {
                Marshal.WriteInt64(buf, 0);
                int r = Fn<DOutBuf>(f, posto)(f, buf);
                if (!Ok(r)) throw new InvalidOperationException("lettura AMD non riuscita (codice " + r + ")");
                return booleano ? (Marshal.ReadByte(buf) != 0 ? 1 : 0) : Marshal.ReadInt32(buf);
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        // IsSupported è sempre al posto 3.
        public static bool Supportata(int posto, bool conGpu)
        {
            if (!Disponibile()) return false;
            try { IntPtr f = Funzione(posto, conGpu); try { return LeggiDa(f, 3, true) != 0; } finally { Rilascia(f); } }
            catch { return false; }
        }

        public static int Leggi(int posto, bool conGpu, int postoLeggi, bool booleano)
        {
            if (!Disponibile()) throw new InvalidOperationException("ADLX non disponibile: " + Errore);
            IntPtr f = Funzione(posto, conGpu);
            try { return LeggiDa(f, postoLeggi, booleano); } finally { Rilascia(f); }
        }

        public static void Scrivi(int posto, bool conGpu, int postoScrivi, int valore)
        {
            if (!Disponibile()) throw new InvalidOperationException("ADLX non disponibile: " + Errore);
            IntPtr f = Funzione(posto, conGpu);
            try
            {
                int r = Fn<DSetInt>(f, postoScrivi)(f, valore);
                if (!Ok(r)) throw new InvalidOperationException("scrittura AMD non riuscita (codice " + r + ")");
            }
            finally { Rilascia(f); }
        }
    }

    // Download in un thread separato, con avanzamento leggibile dalla finestra.
    // Serve per i siti che chiedono l'intestazione "Referer" (drivers.amd.com) che BITS non sa inviare.
    public class Scaricatore
    {
        public long Ricevuti;
        public long Totale = -1;
        public volatile bool Finito;
        public volatile bool Annulla;
        public string Errore;

        public void Avvia(string url, string destinazione, string referer)
        {
            System.Threading.Thread t = new System.Threading.Thread(() =>
            {
                try
                {
                    System.Net.ServicePointManager.SecurityProtocol = System.Net.SecurityProtocolType.Tls12;
                    System.Net.HttpWebRequest req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                    req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
                    if (!string.IsNullOrEmpty(referer)) req.Referer = referer;
                    req.Timeout = 60000; req.ReadWriteTimeout = 120000; req.AllowAutoRedirect = true;
                    using (System.Net.HttpWebResponse risposta = (System.Net.HttpWebResponse)req.GetResponse())
                    {
                        if (risposta.ContentType != null && risposta.ContentType.StartsWith("text/html"))
                            throw new Exception("il server ha risposto con una pagina web invece del file: download rifiutato");
                        Totale = risposta.ContentLength;
                        using (System.IO.Stream s = risposta.GetResponseStream())
                        using (System.IO.FileStream f = new System.IO.FileStream(destinazione, System.IO.FileMode.Create))
                        {
                            byte[] b = new byte[1 << 16];
                            int n;
                            while ((n = s.Read(b, 0, b.Length)) > 0)
                            {
                                f.Write(b, 0, n);
                                Ricevuti += n;
                                if (Annulla) throw new Exception("download annullato");
                            }
                        }
                    }
                }
                catch (Exception e) { Errore = e.Message; }
                finally { Finito = true; }
            });
            t.IsBackground = true;
            t.Start();
        }
    }
}
'@
    }
} catch { }

# ==============================================================================
# 4. CATALOGO DELLE VOCI
# ------------------------------------------------------------------------------
# Ogni voce è una tabella con questi campi:
#   Id            identificativo unico (es. 'priv.adid')
#   Nome          nome mostrato nella lista
#   Categoria     'Debloat app','Avvio','Servizi','Privacy','Prestazioni','Grafica','Pulizia'
#   Descrizione   spiegazione semplice (compare in basso quando selezioni la voce)
#   Rischio       'basso' | 'medio' | 'alto'
#   Avanzata      $true = va nella scheda "Avanzate" e NON entra mai nei profili
#   Profili       profili che la spuntano: 'Gaming','Produttivita','Design','Efficienza'
#   Riavvio       '' oppure 'riavvio' / 'disconnessione' (quando serve per vedere l'effetto)
#   Gruppo        voci alternative tra loro (es. piani energetici): se ne spunti una, le altre si tolgono
#   Tipo          come viene letta/applicata/annullata:
#     'Registro'       -> Valori = @( Nuovo-ValoreReg percorso nome consigliato predefinito [tipo] )
#                         (predefinito $null = "valore non impostato", come in un Windows pulito)
#     'Servizio'       -> Servizi = @('nome'), Consigliato / Predefinito = 'Automatico',
#                         'AutomaticoRitardato', 'Manuale', 'Disattivato'
#     'App'            -> Pacchetti = @('NomePacchettoAppx')
#     'Pulizia'        -> Percorsi = @( Nuovo-PercorsoPulizia ... ), oppure Misura/Azione personalizzate
#     'Personalizzato' -> blocchi di codice Leggi / Applica / Originale / Ripristina
#   TestoConsigliato / TestoPredefinito   come mostrare i due valori (per Servizio, App e Pulizia
#                                         vengono compilati da soli)
#   Etichette     (facoltativo) nomi leggibili per valori "strani", es. @{ '0' = 'Spente' }
#
# Le voci "Avvio" (programmi all'avvio) non stanno qui: vengono lette dal PC a ogni scansione.
# ==============================================================================

function Nuovo-ValoreReg {
    param(
        [string]$Percorso, [string]$Nome, $Consigliato, $Predefinito,
        [string]$Tipo = 'DWord',
        [switch]$AssenteOk    # "non impostato" equivale già al valore consigliato
    )
    return @{ Percorso = $Percorso; Nome = $Nome; Consigliato = $Consigliato; Predefinito = $Predefinito; Tipo = $Tipo; AssenteOk = [bool]$AssenteOk }
}

# "1057EB71" -> numero senza segno a 32 bit (in PowerShell 0xFFFFFFF6 sarebbe un numero negativo).
function Nv-Hex([string]$Esadecimale) { return [Convert]::ToUInt32($Esadecimale, 16) }

# Legge un'impostazione del piano energetico attivo (indici "a corrente" e "a batteria").
# Restituisce $null se l'impostazione non esiste su questo PC.
function Leggi-IndiceEnergia([string]$Sottogruppo, [string]$Impostazione) {
    $righe = & powercfg.exe /query SCHEME_CURRENT $Sottogruppo $Impostazione 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    # Le ultime due righe con un valore esadecimale sono sempre: a corrente, a batteria (in qualsiasi lingua).
    $v = @(foreach ($r in $righe) { if ("$r" -match ':\s*0x([0-9a-fA-F]{8})\s*$') { [Convert]::ToInt32($Matches[1], 16) } })
    if ($v.Count -lt 2) { return $null }
    return [pscustomobject]@{ AC = $v[$v.Count - 2]; DC = $v[$v.Count - 1] }
}

function Scrivi-IndiceEnergia([string]$Schema, [string]$Sottogruppo, [string]$Impostazione, [int]$Valore) {
    & powercfg.exe /setacvalueindex $Schema $Sottogruppo $Impostazione $Valore | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setacvalueindex non riuscito (codice $LASTEXITCODE)." }
    & powercfg.exe /setactive SCHEME_CURRENT | Out-Null   # rende subito effettiva la modifica
}

# Crea una voce che cambia un'impostazione "a corrente" del piano energetico attivo.
# I blocchi ricevono la voce come ultimo argomento ($V).
function Nuova-VoceEnergia([string]$Id, [string]$Nome, [string]$Sottogruppo, [string]$Impostazione, [int]$Consigliato, [int]$Predefinito,
                           [hashtable]$Etichette, [string[]]$Profili, [string]$Descrizione) {
    return @{
        Id = $Id; Nome = $Nome; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = $Profili; Descrizione = $Descrizione
        Sottogruppo = $Sottogruppo; Impostazione = $Impostazione; ValoreCons = $Consigliato; ValorePred = $Predefinito; Etichette = $Etichette
        TestoConsigliato = $Etichette["$Consigliato"]; TestoPredefinito = $Etichette["$Predefinito"]
        Leggi = {
            param($V)
            $i = Leggi-IndiceEnergia $V.Sottogruppo $V.Impostazione
            if ($null -eq $i) { return Nuova-Lettura 'Non disponibile' 'Non presente' $false }
            $t = $(if ($V.Etichette.ContainsKey("$($i.AC)")) { $V.Etichette["$($i.AC)"] } else { "valore $($i.AC)" })
            Nuova-Lettura $t $(if ($i.AC -eq $V.ValoreCons) { 'A posto' } else { 'Da modificare' }) $true ($i.AC -eq $V.ValorePred)
        }
        Applica = {
            param($Obiettivo, $V)
            $nuovo = $(if ($Obiettivo -eq 'Predefinito') { $V.ValorePred } elseif ($Obiettivo -like 'Valore:*') { [int]$Obiettivo.Substring(7) } else { $V.ValoreCons })
            Scrivi-IndiceEnergia 'SCHEME_CURRENT' $V.Sottogruppo $V.Impostazione $nuovo
        }
        Originale = {
            param($V)
            $i = Leggi-IndiceEnergia $V.Sottogruppo $V.Impostazione
            @{ Schema = (Ottieni-PianoAttivo).Guid; AC = $(if ($null -ne $i) { $i.AC } else { $V.ValorePred }) }
        }
        Ripristina = {
            param($O, $V)
            $schema = $(if ($O.Schema) { [string]$O.Schema } else { 'SCHEME_CURRENT' })
            Scrivi-IndiceEnergia $schema $V.Sottogruppo $V.Impostazione ([int]$O.AC)
        }
    }
}

# ---------- Supporto per la sezione Latenza ----------
# "Consenti al computer di spegnere il dispositivo per risparmiare energia" (scheda Risparmio energia di
# Gestione dispositivi): è la classe WMI MSPower_DeviceEnable. 'periferiche' = USB, HID, Bluetooth;
# 'rete' = schede di rete fisiche.
function Dispositivi-Risparmio([string]$Gruppo) {
    $tutti = @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSPower_DeviceEnable -ErrorAction Stop)
    if ($Gruppo -eq 'rete') {
        $pnp = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.PnPDeviceID } | Where-Object { $_ })
        return @($tutti | Where-Object { $n = [string]$_.InstanceName; @($pnp | Where-Object { $n.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 })
    }
    return @($tutti | Where-Object { [string]$_.InstanceName -match '^(USB|HID|BTHENUM|BTH)\\' })
}

function Nuova-VoceRisparmioDispositivi([string]$Id, [string]$Nome, [string]$Gruppo, [string[]]$Profili, [string]$Descrizione) {
    return @{
        Id = $Id; Nome = $Nome; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = $Profili; Descrizione = $Descrizione
        GruppoDispositivi = $Gruppo; TestoConsigliato = 'Mai spenti'; TestoPredefinito = 'Spegnibili (Windows)'
        Leggi = {
            param($V)
            # Su alcuni PC la classe WMI non risponde ("Oggetto non valido"): la voce allora non compare.
            try { $d = @(Dispositivi-Risparmio $V.GruppoDispositivi) }
            catch {
                if (-not $Script:AvvisoWmiPotenza) { $Script:AvvisoWmiPotenza = $true; Scrivi-Log "Impostazioni di risparmio dei dispositivi non leggibili su questo PC (WMI: $($_.Exception.Message)): le voci relative non vengono mostrate." 'AVVISO' }
                return Nuova-Lettura 'Non leggibile su questo PC' 'Non presente' $false
            }
            if ($d.Count -eq 0) { return Nuova-Lettura 'Nessun dispositivo' 'Non presente' $false }
            $acc = @($d | Where-Object { $_.Enable }).Count
            if ($acc -eq 0) { return Nuova-Lettura "Mai spenti (tutti i $($d.Count))" 'A posto' }
            Nuova-Lettura "$acc di $($d.Count) possono essere spenti" 'Da modificare' $true ($acc -eq $d.Count)
        }
        Applica = {
            param($Obiettivo, $V)
            $val = ($Obiettivo -eq 'Predefinito')
            foreach ($d in @(Dispositivi-Risparmio $V.GruppoDispositivi)) {
                if ([bool]$d.Enable -ne $val) { Set-CimInstance -InputObject $d -Property @{ Enable = $val } -ErrorAction Stop }
            }
        }
        Originale = { param($V) @{ Accesi = @(Dispositivi-Risparmio $V.GruppoDispositivi | Where-Object { $_.Enable } | ForEach-Object { [string]$_.InstanceName }) } }
        Ripristina = {
            param($O, $V)
            foreach ($d in @(Dispositivi-Risparmio $V.GruppoDispositivi)) {
                $val = (@($O.Accesi) -contains [string]$d.InstanceName)
                if ([bool]$d.Enable -ne $val) { Set-CimInstance -InputObject $d -Property @{ Enable = $val } -ErrorAction SilentlyContinue }
            }
        }
    }
}

# Proprietà avanzate standard delle schede di rete (parole chiave NDIS: *EEE, *InterruptModeration).
function Nuova-VoceProprietaRete([string]$Id, [string]$Nome, [string]$Parola, [string]$Rischio, [string[]]$Profili, [string]$Descrizione) {
    return @{
        Id = $Id; Nome = $Nome; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = $Rischio; Profili = $Profili; Descrizione = $Descrizione
        Parola = $Parola; TestoConsigliato = 'Disattivato'; TestoPredefinito = 'Attivato'
        Leggi = {
            param($V)
            $p = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterAdvancedProperty -RegistryKeyword $V.Parola -ErrorAction SilentlyContinue)
            if ($p.Count -eq 0) { return Nuova-Lettura 'Non presente' 'Non presente' $false }
            $acc = @($p | Where-Object { [string]@($_.RegistryValue)[0] -ne '0' }).Count
            if ($acc -eq 0) { return Nuova-Lettura 'Disattivato' 'A posto' }
            Nuova-Lettura $(if ($acc -eq $p.Count) { 'Attivato' } else { "Attivato su $acc di $($p.Count) schede" }) 'Da modificare' $true ($acc -eq $p.Count)
        }
        Applica = {
            param($Obiettivo, $V)
            $val = $(if ($Obiettivo -eq 'Predefinito') { '1' } else { '0' })
            foreach ($p in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterAdvancedProperty -RegistryKeyword $V.Parola -ErrorAction SilentlyContinue)) {
                if ([string]@($p.RegistryValue)[0] -ne $val) { Set-NetAdapterAdvancedProperty -Name $p.Name -RegistryKeyword $V.Parola -RegistryValue $val -ErrorAction Stop }
            }
        }
        Originale = { param($V) @{ Schede = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterAdvancedProperty -RegistryKeyword $V.Parola -ErrorAction SilentlyContinue | ForEach-Object { @{ Nome = $_.Name; Valore = [string]@($_.RegistryValue)[0] } }) } }
        Ripristina = { param($O, $V) foreach ($s in @($O.Schede)) { Set-NetAdapterAdvancedProperty -Name $s.Nome -RegistryKeyword $V.Parola -RegistryValue ([string]$s.Valore) -ErrorAction Stop } }
    }
}

# Interfacce di rete con un indirizzo IP (per le conferme TCP).
function Interfacce-Tcp {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    return @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        ([string]$p.DhcpIPAddress -and [string]$p.DhcpIPAddress -ne '0.0.0.0') -or (@($p.IPAddress) | Where-Object { $_ -and $_ -ne '0.0.0.0' })
    } | ForEach-Object { $_.PSPath })
}

# Valori del caricatore di avvio che alcuni "ottimizzatori" cambiano (timer della piattaforma).
$Script:ChiaviBcdTimer = @('useplatformclock', 'useplatformtick', 'disabledynamictick', 'tscsyncpolicy')
function Leggi-BcdTimer {
    $r = @{}
    $righe = @(& bcdedit.exe /enum '{current}' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "bcdedit non leggibile (codice $LASTEXITCODE)" }
    foreach ($riga in $righe) {
        if ("$riga" -match '^\s*(useplatformclock|useplatformtick|disabledynamictick|tscsyncpolicy)\s+(\S+)') { $r[$Matches[1].ToLower()] = $Matches[2] }
    }
    return $r
}

# Imposta campi in una voce già creata (per riusare Nuova-VoceEnergia in un'altra sezione).
function Con-Campi([hashtable]$Voce, [hashtable]$Campi) { foreach ($k in $Campi.Keys) { $Voce[$k] = $Campi[$k] }; return $Voce }

# ---------- Pulizia del registro (dalla 3.9) ----------
# Si tolgono SOLO voci rimaste di programmi che non esistono più, e solo se il file mancante è su un disco
# interno presente (chiavette e dischi scollegati non vengono mai giudicati). Niente chiavi COM, estensioni
# dei file, driver o servizi: lì un errore può rompere Windows e il guadagno sarebbe comunque nullo.
# Prima di togliere qualcosa si salva tutto: le chiavi in file .reg (Dati\Backup\registro_...), i valori
# nel backup JSON. "Annulla tutto" li rimette.

# Dal testo di un comando ricava i possibili file da avviare ("C:\x\a.exe" -b, C:\Program Files\a.exe /q, %ProgramFiles%\a.exe).
# Senza virgolette restituisce tutti i tagli possibili dopo un'estensione eseguibile (C:\a.exe dir\b.exe -> due candidati).
function Candidati-FileComando([string]$Comando) {
    if ([string]::IsNullOrWhiteSpace($Comando)) { return @() }
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c.StartsWith('"')) {
        $j = $c.IndexOf('"', 1)
        if ($j -lt 2) { return @() }
        $lista = @($c.Substring(1, $j - 1))
    } else {
        $lista = @(foreach ($m in [regex]::Matches($c, '(?i)\.(exe|com|bat|cmd|vbs|vbe|js|wsf|ps1|lnk|dll|scr|msc|cpl)(?=\s|,|$)')) { $c.Substring(0, $m.Index + $m.Length) })
    }
    return @($lista | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z]:\\' })
}

# $true solo se TUTTI i file candidati mancano davvero su un disco interno presente. Nel dubbio $false (non si tocca).
function File-Mancante([string]$Comando) {
    $cand = @(Candidati-FileComando $Comando)
    if ($cand.Count -eq 0) { return $false }
    foreach ($f in $cand) {
        try {
            $radice = [IO.Path]::GetPathRoot($f)
            if (-not $radice) { return $false }
            $disco = New-Object IO.DriveInfo($radice)
            if (-not $disco.IsReady -or [string]$disco.DriveType -ne 'Fixed') { return $false }
            if (Test-Path -LiteralPath $f) { return $false }
            # programmi a 32 bit: "System32" per loro è SysWOW64
            $alt = $f -replace '(?i)\\System32\\', '\SysWOW64\'
            if ($alt -ne $f -and (Test-Path -LiteralPath $alt)) { return $false }
        } catch { return $false }
    }
    return $true
}

function Esiste-Percorso([string]$P) {
    try { $p2 = [Environment]::ExpandEnvironmentVariables($P).Trim().Trim('"'); return ($p2 -and (Test-Path -LiteralPath $p2)) } catch { return $true }
}

# Apre una chiave dal nome completo (HKEY_LOCAL_MACHINE\...), sempre nella vista a 64 bit.
function Apri-ChiaveReg([string]$Nome, [bool]$Scrittura = $false) {
    $i = $Nome.IndexOf('\')
    $radice = $(if ($i -gt 0) { $Nome.Substring(0, $i) } else { $Nome })
    $resto = $(if ($i -gt 0) { $Nome.Substring($i + 1) } else { '' })
    $hive = switch ($radice) { 'HKEY_LOCAL_MACHINE' { 'LocalMachine' } 'HKEY_CURRENT_USER' { 'CurrentUser' } default { throw "Radice del registro non gestita: $radice" } }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$hive, [Microsoft.Win32.RegistryView]::Registry64)
    if (-not $resto) { return $base }
    return $base.OpenSubKey($resto, $Scrittura)
}

function Nuovo-ElementoValore([string]$Chiave, [string]$Nome, [string]$Etichetta, [string]$IdElemento) {
    $k = Apri-ChiaveReg $Chiave
    if (-not $k) { return $null }
    try {
        $tipo = [string]$k.GetValueKind($Nome)
        $val = $k.GetValue($Nome, $null, 'DoNotExpandEnvironmentNames')
        if ($val -is [byte[]]) { $val = @($val | ForEach-Object { [int]$_ }) }
    } finally { $k.Close() }
    return @{ Tipo = 'Valore'; Chiave = $Chiave; Nome = $Nome; Etichetta = $Etichetta; Id = $IdElemento; Valore = $val; TipoValore = $tipo }
}

function Scrivi-ValoreGrezzo([string]$Chiave, [string]$Nome, $Valore, [string]$TipoValore) {
    $k = Apri-ChiaveReg $Chiave $true
    if (-not $k) {
        $i = $Chiave.IndexOf('\')
        $b = Apri-ChiaveReg $Chiave.Substring(0, $i)
        $k = $b.CreateSubKey($Chiave.Substring($i + 1))
    }
    try {
        $tipo = [Microsoft.Win32.RegistryValueKind]$TipoValore
        # niente "switch" con assegnazione: PowerShell srotolerebbe gli array (byte[] -> object[])
        if ($tipo -eq 'Binary') { [byte[]]$v = @($Valore | ForEach-Object { [byte]$_ }) }
        elseif ($tipo -eq 'MultiString') { [string[]]$v = @($Valore | ForEach-Object { [string]$_ }) }
        elseif ($tipo -eq 'DWord') { $v = [int]$Valore }
        elseif ($tipo -eq 'QWord') { $v = [long]$Valore }
        else { $v = [string]$Valore }
        $k.SetValue($Nome, $v, $tipo)
    } finally { $k.Close() }
}

# Programmi all'avvio (chiavi Run) che puntano a un file cancellato. Insieme si toglie la riga
# "attivo/disattivato" che Gestione attività tiene per lo stesso nome (StartupApproved).
$Script:ChiaviAvvioReg = @(
    @{ Run = 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'; Ok = 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
    @{ Run = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Ok = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
    @{ Run = 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Ok = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' } )

function Trova-AvvioOrfani {
    $r = @()
    foreach ($c in $Script:ChiaviAvvioReg) {
        $k = Apri-ChiaveReg $c.Run
        if (-not $k) { continue }
        try { $nomi = @($k.GetValueNames() | Where-Object { $_ }) ; $cmd = @{}; foreach ($n in $nomi) { $cmd[$n] = [string]$k.GetValue($n, $null, 'DoNotExpandEnvironmentNames') } } finally { $k.Close() }
        $ok = Apri-ChiaveReg $c.Ok
        $nomiOk = @(); if ($ok) { try { $nomiOk = @($ok.GetValueNames()) } finally { $ok.Close() } }
        foreach ($n in $nomi) {
            if (-not (File-Mancante $cmd[$n])) { continue }
            $id = "$($c.Run)|$n"
            $e = Nuovo-ElementoValore $c.Run $n $n $id; if ($e) { $r += $e }
            if ($nomiOk -contains $n) { $e = Nuovo-ElementoValore $c.Ok $n $n $id; if ($e) { $r += $e } }
        }
    }
    return $r
}

# App Paths: nomi che si possono scrivere in Esegui (Win+R) e che aprono un file cancellato.
function Trova-AppPathsOrfani {
    $r = @()
    foreach ($base in @('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
                        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
                        'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths')) {
        foreach ($s in @(Get-ChildItem -LiteralPath "Registry::$base" -ErrorAction SilentlyContinue)) {
            $cmd = [string]$s.GetValue('', $null, 'DoNotExpandEnvironmentNames')
            if (-not $cmd.Trim()) { continue }
            # il valore è sempre un solo file (anche con spazi): lo si mette tra virgolette se non lo è
            if ($cmd.Trim() -notmatch '^"') { $cmd = '"' + $cmd.Trim() + '"' }
            if (File-Mancante $cmd) { $r += @{ Tipo = 'Chiave'; Chiave = $s.Name; Etichetta = $s.PSChildName; Id = $s.Name } }
        }
    }
    return $r
}

# MuiCache: nomi di programmi ricordati da Windows (es. per "Apri con"). Solo una cache.
function Trova-MuiCacheOrfani {
    $chiave = 'HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    $k = Apri-ChiaveReg $chiave
    if (-not $k) { return @() }
    try { $nomi = @($k.GetValueNames()) } finally { $k.Close() }
    $r = @()
    foreach ($n in $nomi) {
        if ($n -notmatch '^([A-Za-z]:\\.+)\.(FriendlyAppName|ApplicationCompany)$') { continue }
        $file = $Matches[1]
        if (File-Mancante ('"' + $file + '"')) { $e = Nuovo-ElementoValore $chiave $n ([IO.Path]::GetFileName($file)) $file; if ($e) { $r += $e } }
    }
    return $r
}

# "App installate": righe il cui programma di disinstallazione E la cui cartella non esistono più.
# Esclusi: pacchetti Windows Installer (MSI, li gestisce Windows), componenti di sistema, righe senza nome,
# programmi di disinstallazione dentro la cartella di Windows.
function Trova-DisinstallazioniRotte {
    $r = @()
    foreach ($base in @('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($s in @(Get-ChildItem -LiteralPath "Registry::$base" -ErrorAction SilentlyContinue)) {
            try {
                $nome = [string]$s.GetValue('DisplayName')
                if (-not $nome.Trim()) { continue }
                if ([string]$s.GetValue('SystemComponent') -eq '1' -or [string]$s.GetValue('WindowsInstaller') -eq '1') { continue }
                if ($s.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { continue }
                $cmd = [string]$s.GetValue('UninstallString', $null, 'DoNotExpandEnvironmentNames')
                if (-not $cmd.Trim() -or $cmd -match '(?i)msiexec') { continue }
                if ([Environment]::ExpandEnvironmentVariables($cmd).Trim().Trim('"') -like "$env:WINDIR\*") { continue }
                if (-not (File-Mancante $cmd)) { continue }
                $q = [string]$s.GetValue('QuietUninstallString', $null, 'DoNotExpandEnvironmentNames')
                if ($q.Trim() -and -not (File-Mancante $q)) { continue }
                $loc = [string]$s.GetValue('InstallLocation', $null, 'DoNotExpandEnvironmentNames')
                if ($loc.Trim() -and (Esiste-Percorso $loc)) { continue }
                $r += @{ Tipo = 'Chiave'; Chiave = $s.Name; Etichetta = $nome.Trim(); Id = $s.Name }
            } catch { continue }
        }
    }
    return $r
}

function Leggi-PuliziaRegistro($V) {
    $el = @(& $V.Trova)
    $n = @($el | ForEach-Object { $_.Id } | Select-Object -Unique).Count
    if ($n -eq 0) { return Nuova-Lettura 'Nessuna voce rimasta' 'A posto' $true $true }
    $nomi = @($el | ForEach-Object { $_.Etichetta } | Where-Object { $_ } | Select-Object -Unique)
    $elenco = (@($nomi | Select-Object -First 3)) -join ', '
    if ($nomi.Count -gt 3) { $elenco += ', …' }
    $t = $(if ($n -eq 1) { "1 voce rimasta: $elenco" } else { "$n voci rimaste: $elenco" })
    return Nuova-Lettura $t 'Da modificare' $true $true
}

# Chiamata subito prima di Applica: salva tutto (chiavi in .reg, valori nel JSON) e prepara l'elenco
# esatto da togliere. Applica toglie solo quello che è stato salvato qui.
function Originale-PuliziaRegistro($V) {
    $el = @(& $V.Trova)
    $salvati = New-Object System.Collections.ArrayList
    $cartella = $null; $i = 0
    foreach ($e in $el) {
        $i++
        if ($e.Tipo -eq 'Chiave') {
            if (-not $cartella) {
                $cartella = Join-Path $Script:CartellaBackup ('registro_{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), ($V.Id -replace '[^\w]', '_'))
                New-Item -ItemType Directory -Path $cartella -Force | Out-Null
            }
            $file = Join-Path $cartella ('chiave_{0:D3}.reg' -f $i)
            $codice = Esegui-Processo "$env:windir\System32\reg.exe" "export `"$($e.Chiave)`" `"$file`" /y"
            if ($codice -ne 0 -or -not (Test-Path -LiteralPath $file)) { $V.DaTogliere = $null; throw "Backup della chiave non riuscito (reg export codice $codice): non viene tolto niente. Chiave: $($e.Chiave)" }
            [void]$salvati.Add(@{ Tipo = 'Chiave'; Chiave = $e.Chiave; Etichetta = $e.Etichetta; File = $file })
        } else {
            [void]$salvati.Add(@{ Tipo = 'Valore'; Chiave = $e.Chiave; Nome = $e.Nome; Etichetta = $e.Etichetta; Valore = $e.Valore; TipoValore = $e.TipoValore })
        }
    }
    $V.DaTogliere = @($salvati)
    return @{ Elementi = @($salvati) }
}

function Applica-PuliziaRegistro($V) {
    if ($null -eq $V.DaTogliere) { throw 'Backup non preparato: non viene tolto niente.' }
    $el = @($V.DaTogliere)
    $V.DaTogliere = $null
    foreach ($e in $el) {
        if ($e.Tipo -eq 'Chiave') {
            Remove-Item -LiteralPath "Registry::$($e.Chiave)" -Recurse -Force -ErrorAction Stop
            Scrivi-Log "  chiave tolta: $($e.Etichetta)  ($($e.Chiave), backup in $($e.File))" 'OK'
        } else {
            $k = Apri-ChiaveReg $e.Chiave $true
            if ($k) { try { $k.DeleteValue($e.Nome, $false) } finally { $k.Close() } }
            Scrivi-Log "  valore tolto: $($e.Chiave) -> $($e.Nome)" 'OK'
        }
    }
}

function Ripristina-PuliziaRegistro($O) {
    foreach ($e in @($O.Elementi)) {
        if ($e.Tipo -eq 'Chiave') {
            if (-not (Test-Path -LiteralPath $e.File)) { throw "File di backup mancante: $($e.File)" }
            $codice = Esegui-Processo "$env:windir\System32\reg.exe" "import `"$($e.File)`""
            if ($codice -ne 0) { throw "reg import non riuscito (codice $codice): $($e.File)" }
        } else {
            Scrivi-ValoreGrezzo $e.Chiave $e.Nome $e.Valore $e.TipoValore
        }
    }
}

function Nuova-VocePuliziaRegistro([string]$Id, [string]$Nome, [scriptblock]$Trova, [string]$Rischio, [bool]$Avanzata, [string]$Descrizione) {
    return @{
        Id = $Id; Nome = $Nome; Categoria = 'Registro'; Tipo = 'Personalizzato'; Rischio = $Rischio; Profili = @(); Avanzata = $Avanzata
        TestoConsigliato = 'Tolte (con backup)'; TestoPredefinito = 'Tolte (con backup)'
        Trova = $Trova; DaTogliere = $null
        Descrizione = $Descrizione
        Leggi      = { param($V) Leggi-PuliziaRegistro $V }
        Applica    = { param($Obiettivo, $V) Applica-PuliziaRegistro $V }
        Originale  = { param($V) Originale-PuliziaRegistro $V }
        Ripristina = { param($O, $V) Ripristina-PuliziaRegistro $O }
    }
}

# Voci spostate nella sezione Latenza dalla 3.1 (stesso Id: backup e profili personali restano validi).
$Script:VociInLatenza = @('perf.usb', 'perf.pcie', 'perf.rete', 'perf.mmcss', 'perf.mouse')

$Tutti = @('Gaming', 'Produttivita', 'Design', 'Efficienza')
$CDM   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

$Script:Catalogo = @(

    # ---------------------------------------------------------------- DEBLOAT APP
    @{ Id = 'app.notizie'; Nome = 'Notizie e Meteo (Bing)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.BingNews', 'Microsoft.BingWeather'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "App di notizie e meteo preinstallate. Le stesse informazioni sono disponibili nel browser." }

    @{ Id = 'app.guida'; Nome = 'Suggerimenti, Guida e Hub di Feedback'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.WindowsFeedbackHub'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "App di aiuto e per inviare commenti a Microsoft. Non servono al funzionamento di Windows." }

    @{ Id = 'app.solitario'; Nome = 'Microsoft Solitaire Collection'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.MicrosoftSolitaireCollection'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Raccolta di giochi di carte con pubblicità." }

    @{ Id = 'app.clipchamp'; Nome = 'Clipchamp (editor video)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Clipchamp.Clipchamp'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Editor video online di Microsoft. Rimuovilo se non lo usi." }

    @{ Id = 'app.officehub'; Nome = 'Microsoft 365 (Office Hub)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.MicrosoftOfficeHub'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "È solo un'app-vetrina per Microsoft 365. Word, Excel ecc. se installati NON vengono toccati." }

    @{ Id = 'app.powerautomate'; Nome = 'Power Automate'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.PowerAutomateDesktop'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Strumento per automatizzare attività. Serve solo a chi lo usa esplicitamente." }

    @{ Id = 'app.todo'; Nome = 'Microsoft To Do'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.Todos'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "App per le liste di cose da fare. Rimuovila se non la usi." }

    @{ Id = 'app.bingsearch'; Nome = 'Ricerca Bing (app)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.BingSearch'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Componente di ricerca web Bing. La ricerca di file e app di Windows continua a funzionare." }

    @{ Id = 'app.mappe'; Nome = 'Mappe'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.WindowsMaps'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "App Mappe di Windows (dismessa da Microsoft)." }

    @{ Id = 'app.devhome'; Nome = 'Dev Home'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.Windows.DevHome'); Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Pannello per sviluppatori (dismesso da Microsoft)." }

    @{ Id = 'app.media'; Nome = 'Lettore multimediale e Film e TV'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.ZuneMusic', 'Microsoft.ZuneVideo'); Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       Descrizione = "Lettore predefinito di musica e video. Se lo usi per aprire MP3/MP4, NON rimuoverlo (oppure usa VLC o simili)." }

    @{ Id = 'app.utilita'; Nome = 'Registratore di suoni, Sveglie e orologio'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.WindowsSoundRecorder', 'Microsoft.WindowsAlarms'); Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       Descrizione = "Piccole app di utilità. Rimuovile solo se non usi sveglie, timer o registrazioni audio." }

    @{ Id = 'app.contatti'; Nome = 'Contatti (People)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.People'); Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       Descrizione = "Vecchia rubrica di Windows." }

    @{ Id = 'app.assistenza'; Nome = 'Assistenza rapida'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('MicrosoftCorporationII.QuickAssist'); Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       Descrizione = "Permette a qualcuno di controllare il PC a distanza per aiutarti. Rimuovila se non la usi." }

    @{ Id = 'app.copilot'; Nome = 'Copilot'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.Copilot'); Rischio = 'medio'; Profili = @()
       Descrizione = "Assistente AI di Microsoft. Non è in nessun profilo: spuntalo tu se non lo usi." }

    @{ Id = 'app.outlook'; Nome = 'Nuovo Outlook e Posta/Calendario'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('Microsoft.OutlookForWindows', 'microsoft.windowscommunicationsapps'); Rischio = 'medio'; Profili = @()
       Descrizione = "App di posta di Windows. Rimuovile solo se usi un altro programma di posta (o la posta dal browser)." }

    @{ Id = 'app.teams'; Nome = 'Microsoft Teams (personale)'; Categoria = 'Debloat app'; Tipo = 'App'
       Pacchetti = @('MSTeams', 'MicrosoftTeams'); Rischio = 'medio'; Profili = @()
       Descrizione = "Teams per uso personale. Rimuovilo solo se non lo usi per lavoro o scuola." }

    @{ Id = 'app.telefono'; Nome = 'Collegamento al telefono'; Categoria = 'Debloat app'; Tipo = 'App'; Avanzata = $true
       Pacchetti = @('Microsoft.YourPhone'); Rischio = 'medio'
       Descrizione = "Collega lo smartphone al PC (notifiche, foto, SMS). Senza di essa queste funzioni spariscono." }

    @{ Id = 'app.xbox'; Nome = 'App Xbox'; Categoria = 'Debloat app'; Tipo = 'App'; Avanzata = $true
       Pacchetti = @('Microsoft.GamingApp'); Rischio = 'medio'
       Descrizione = "Necessaria per Game Pass e per i giochi del Microsoft Store. La Game Bar e l'accesso Xbox nei giochi non vengono toccati." }

    # ---------------------------------------------------------------- SERVIZI
    @{ Id = 'svc.telemetria'; Nome = 'Telemetria (Esperienze utente connesse)'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('DiagTrack'); Consigliato = 'Disattivato'; Predefinito = 'Automatico'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Invia a Microsoft dati di utilizzo e diagnostica. Disattivarlo non ha effetti sul funzionamento del PC." }

    @{ Id = 'svc.wap'; Nome = 'Instradamento messaggi push WAP'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('dmwappushservice'); Consigliato = 'Disattivato'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Servizio legato alla telemetria e alla gestione aziendale dei dispositivi. Inutile su un PC personale." }

    @{ Id = 'svc.demo'; Nome = 'Modalità demo per negozi'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('RetailDemo'); Consigliato = 'Disattivato'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Usato solo dai PC esposti nei negozi." }

    @{ Id = 'svc.mappe'; Nome = 'Gestione mappe scaricate'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('MapsBroker'); Consigliato = 'Disattivato'; Predefinito = 'AutomaticoRitardato'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Aggiorna le mappe offline dell'app Mappe. Inutile se non usi mappe offline." }

    @{ Id = 'svc.fax'; Nome = 'Fax'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('Fax'); Consigliato = 'Disattivato'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Invio e ricezione di fax tramite modem." }

    @{ Id = 'svc.registroremoto'; Nome = 'Registro di sistema remoto'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('RemoteRegistry'); Consigliato = 'Disattivato'; Predefinito = 'Disattivato'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Permette di modificare il registro da un altro PC. Per sicurezza deve restare disattivato (lo è già in Windows 11)." }

    @{ Id = 'svc.errori'; Nome = 'Segnalazione errori di Windows'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('WerSvc'); Consigliato = 'Disattivato'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       Descrizione = "Raccoglie e invia a Microsoft i rapporti sugli arresti anomali dei programmi. Disattivato non vengono più creati." }

    @{ Id = 'svc.posizione'; Nome = 'Servizio di localizzazione'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('lfsvc'); Consigliato = 'Manuale'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = @()
       Descrizione = "Se è disattivato, app come Meteo, Mappe e 'Trova il mio dispositivo' non sanno dove sei. 'Manuale' = parte solo quando serve. La privacy della posizione si gestisce comunque da Impostazioni." }

    @{ Id = 'svc.telefono'; Nome = 'Servizio telefonico'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('PhoneSvc'); Consigliato = 'Manuale'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = @()
       Descrizione = "Usato da 'Collegamento al telefono' per le chiamate. 'Manuale' = parte solo quando serve, non pesa sul sistema." }

    @{ Id = 'svc.xbox'; Nome = 'Servizi Xbox (accesso, salvataggi, rete, controller)'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc'); Consigliato = 'Manuale'; Predefinito = 'Manuale'; Rischio = 'medio'; Profili = @('Gaming')
       Descrizione = "Se disattivati, Game Pass, app Xbox, salvataggi nel cloud e alcuni controller Xbox non funzionano. In 'Manuale' partono solo quando un gioco li usa: nessun peso sul sistema." }

    @{ Id = 'svc.sysmain'; Nome = 'SysMain (Superfetch)'; Categoria = 'Servizi'; Tipo = 'Servizio'; Avanzata = $true
       Servizi = @('SysMain'); Consigliato = 'Automatico'; Predefinito = 'Automatico'; Rischio = 'medio'
       Descrizione = "Precarica in memoria i programmi che usi spesso. Con molta RAM e SSD veloci aiuta l'apertura delle app; disattivarlo serve solo su PC con poca RAM o dischi meccanici." }

    @{ Id = 'svc.ricerca'; Nome = 'Windows Search (indicizzazione)'; Categoria = 'Servizi'; Tipo = 'Servizio'; Avanzata = $true
       Servizi = @('WSearch'); Consigliato = 'AutomaticoRitardato'; Predefinito = 'AutomaticoRitardato'; Rischio = 'medio'
       Descrizione = "Indicizza i file per trovarli subito. Se è disattivato, la ricerca nel menu Start, in Esplora file e in Outlook diventa lenta o incompleta. Il consiglio è tenerlo acceso." }

    @{ Id = 'svc.stampa'; Nome = 'Spooler di stampa'; Categoria = 'Servizi'; Tipo = 'Servizio'; Avanzata = $true
       Servizi = @('Spooler'); Consigliato = 'Disattivato'; Predefinito = 'Automatico'; Rischio = 'medio'
       Descrizione = "Gestisce la stampa. Disattivalo SOLO se non stampi mai: smettono di funzionare anche 'Stampa su PDF' e la scansione da stampanti multifunzione." }

    # ---------------------------------------------------------------- PRIVACY
    @{ Id = 'priv.telemetria'; Nome = 'Dati di diagnostica al minimo'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Minimo (solo obbligatori)'; TestoPredefinito = "Scelta dell'utente"
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 $null) )
       Descrizione = "Limita i dati inviati a Microsoft al minimo consentito dalle edizioni Home e Pro. In Impostazioni comparirà la scritta 'alcune impostazioni sono gestite dall'organizzazione': è normale." }

    @{ Id = 'priv.adid'; Nome = 'ID pubblicità personalizzata'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spento'; TestoPredefinito = 'Acceso'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 1) )
       Descrizione = "Codice che le app usano per mostrarti pubblicità mirata. Spegnendolo la pubblicità resta, ma non è personalizzata." }

    @{ Id = 'priv.suggerimenti'; Nome = 'Suggerimenti e app promosse in Start e Impostazioni'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @(
           (Nuovo-ValoreReg $CDM 'SubscribedContent-338388Enabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SubscribedContent-338393Enabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SubscribedContent-353694Enabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SubscribedContent-353696Enabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SystemPaneSuggestionsEnabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SilentInstalledAppsEnabled' 0 1) )
       Descrizione = "Toglie le app 'consigliate' nel menu Start, i contenuti suggeriti in Impostazioni e l'installazione automatica di app promozionali." }

    @{ Id = 'priv.lockscreen'; Nome = 'Curiosità e suggerimenti nella schermata di blocco'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @(
           (Nuovo-ValoreReg $CDM 'RotatingLockScreenOverlayEnabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SubscribedContent-338387Enabled' 0 1) )
       Descrizione = "Toglie testi, curiosità e pubblicità sopra l'immagine della schermata di blocco. L'immagine resta." }

    @{ Id = 'priv.esperienze'; Nome = 'Esperienze personalizzate con i dati di diagnostica'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spente'; TestoPredefinito = 'Accese'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 1) )
       Descrizione = "Impedisce a Microsoft di usare i dati di diagnostica per suggerimenti e pubblicità su misura." }

    @{ Id = 'priv.attivita'; Nome = 'Cronologia attività'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenta'; TestoPredefinito = 'Non impostata'
       Valori = @(
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 $null),
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0 $null) )
       Descrizione = "Windows smette di registrare quali app e documenti apri (e di inviarlo al cloud)." }

    @{ Id = 'priv.feedback'; Nome = 'Richieste di feedback'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Mai'; TestoPredefinito = 'Automatiche'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 $null),
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 $null) )
       Descrizione = "Windows non ti chiederà più di dare un voto o un commento." }

    # Windows protegge questa impostazione (driver UCPD): il programma la legge soltanto.
    @{ Id = 'priv.widget'; Nome = 'Widget (notizie sulla barra delle applicazioni) - da fare a mano'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @()
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'; SoloSeApp = 'MicrosoftWindows.Client.WebExperience*'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 $null) )
       Manuale = "Windows protegge questa impostazione e non permette ai programmi di cambiarla. Fallo tu: Impostazioni > Personalizzazione > Barra delle applicazioni > Widget: Disattivato."
       Descrizione = "Il pannello Widget (meteo e notizie) resta attivo in background. Windows protegge questa impostazione (driver UCPD), quindi il programma la legge soltanto. Per spegnerla: Impostazioni > Personalizzazione > Barra delle applicazioni > Widget: Disattivato." }

    @{ Id = 'notif.suggerimenti'; Nome = 'Notifiche: suggerimenti e consigli di Windows'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @(
           (Nuovo-ValoreReg $CDM 'SubscribedContent-338389Enabled' 0 1),
           (Nuovo-ValoreReg $CDM 'SubscribedContent-310093Enabled' 0 1),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 1),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' 'Enabled' 0 $null) )
       Descrizione = "Toglie le notifiche con consigli, 'completa la configurazione' e la schermata di benvenuto dopo gli aggiornamenti. Le notifiche delle tue app restano." }

    @{ Id = 'notif.globali'; Nome = 'Notifiche delle app (interruttore generale)'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @()
       TestoConsigliato = 'Accese'; TestoPredefinito = 'Accese'; Etichette = @{ '0' = 'Tutte spente' }
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 1 1) )
       Riavvio = 'disconnessione'
       Descrizione = "Se le notifiche sono tutte spente perdi anche avvisi utili (promemoria, Defender, batteria). Il consiglio è tenerle accese e togliere solo i suggerimenti. Per i giochi c'è già 'Non disturbare' automatico." }

    @{ Id = 'priv.bing'; Nome = 'Risultati web (Bing) nella ricerca di Start'; Categoria = 'Privacy'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 $null) )
       Riavvio = 'disconnessione'
       Descrizione = "La ricerca di Start mostra solo app, file e impostazioni del PC, senza risultati web. Su alcune versioni di Windows spegne anche i suggerimenti di ricerca recenti." }

    @{ Id = 'priv.recall'; Nome = 'Recall e istantanee AI'; Categoria = 'Privacy'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = 'Bloccati'; TestoPredefinito = 'Non impostato'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 $null) )
       Riavvio = 'riavvio'
       Descrizione = "Impedisce a Windows di salvare istantanee dello schermo per la funzione Recall. Recall esiste solo sui PC Copilot+; sugli altri la voce non ha effetti visibili." }

    # ---------------------------------------------------------------- PRESTAZIONI
    @{ Id = 'energia.prestazioni'; Nome = 'Piano energetico: Prestazioni elevate'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Gruppo = 'Energia'
       Rischio = 'basso'; Profili = @('Gaming', 'Design'); TestoConsigliato = 'Prestazioni elevate'; TestoPredefinito = 'Bilanciato'
       Descrizione = "CPU e GPU restano pronte al massimo: ideale su un PC fisso o con l'alimentatore collegato. A batteria consuma e scalda di più. Se il piano manca viene ricreato; se Windows non lo permette (portatili con 'Modern Standby') si usa 'Bilanciato' con modalità 'Prestazioni migliori'. Valgono come 'a posto' anche 'Prestazioni eccellenti' e i piani personalizzati elencati in Dati\impostazioni.json. Nota: i programmi del produttore del portatile (Lenovo Vantage/Legion, Armoury Crate, MSI Center, Dell/Alienware...) possono cambiare il piano da soli: se 'torna indietro', disattiva lì il cambio automatico."
       Leggi      = { Leggi-Energia 'prestazioni' }
       Applica    = { param($Obiettivo) if ($Obiettivo -eq 'Predefinito') { Imposta-EnergiaPredefinita } else { Attiva-PianoPrestazioni } }
       Originale  = { Ottieni-StatoEnergia }
       Ripristina = { param($O) Ripristina-StatoEnergia $O } }

    @{ Id = 'energia.bilanciato'; Nome = 'Piano energetico: Bilanciato'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Gruppo = 'Energia'
       Rischio = 'basso'; Profili = @('Produttivita'); TestoConsigliato = 'Bilanciato'; TestoPredefinito = 'Bilanciato'
       Descrizione = "Il piano standard di Windows: prestazioni piene quando servono, consumi bassi quando il PC è fermo. È la scelta migliore per l'uso quotidiano."
       Leggi      = { Leggi-Energia 'bilanciato' }
       Applica    = { param($Obiettivo) Imposta-EnergiaPredefinita }
       Originale  = { Ottieni-StatoEnergia }
       Ripristina = { param($O) Ripristina-StatoEnergia $O } }

    @{ Id = 'energia.efficienza'; Nome = 'Piano energetico: Massima efficienza'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Gruppo = 'Energia'
       Rischio = 'basso'; Profili = @('Efficienza'); TestoConsigliato = 'Bilanciato · massima efficienza'; TestoPredefinito = 'Bilanciato'
       Descrizione = "Piano Bilanciato con la modalità 'Massima efficienza' di Windows 11: più autonomia e meno calore, prestazioni ridotte."
       Leggi      = { Leggi-Energia 'efficienza' }
       Applica    = { param($Obiettivo) if ($Obiettivo -eq 'Predefinito') { Imposta-EnergiaPredefinita } else { Imposta-Piano $Script:GuidBilanciato; Imposta-Overlay $Script:OverlayEfficienza } }
       Originale  = { Ottieni-StatoEnergia }
       Ripristina = { param($O) Ripristina-StatoEnergia $O } }

    @{ Id = 'perf.gamemode'; Nome = 'Modalità gioco (Game Mode)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Attiva'; TestoPredefinito = 'Attiva'; Etichette = @{ '0' = 'Spenta' }
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 $null -AssenteOk) )
       Descrizione = "Quando giochi, Windows dà priorità al gioco e rimanda aggiornamenti e attività in background." }

    @{ Id = 'perf.background'; Nome = 'App dello Store in background'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'medio'; Profili = @('Efficienza')
       TestoConsigliato = 'Bloccate'; TestoPredefinito = 'Decide Windows'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 $null) )
       Descrizione = "Le app dello Store (es. WhatsApp, Telefono, Posta) non lavorano quando sono chiuse: meno consumi, ma possono arrivare notifiche in ritardo. I programmi classici non sono toccati." }

    @{ Id = 'perf.ritardo'; Nome = 'Ritardo dei programmi all''avvio'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Produttivita')
       TestoConsigliato = 'Nessun ritardo'; TestoPredefinito = 'Ritardo di Windows'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0 $null),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'WaitForIdleState' 0 $null) )
       Descrizione = "Windows aspetta qualche secondo prima di aprire i programmi all'avvio. Togliendo l'attesa il desktop è pronto prima." }

    @{ Id = 'perf.avviorapido'; Nome = 'Avvio rapido (Fast Startup)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Produttivita', 'Efficienza')
       TestoConsigliato = 'Attivo'; TestoPredefinito = 'Attivo'; Etichette = @{ '0' = 'Spento' }
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1 1) )
       Descrizione = "Il PC si accende più in fretta perché parte del sistema viene salvata su disco allo spegnimento. Richiede l'ibernazione attiva. Se usi due sistemi operativi (dual boot) è meglio spento." }

    @{ Id = 'perf.mmcss'; Nome = 'Priorità alle attività multimediali (MMCSS)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = '10%'; TestoPredefinito = '20%'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10 20) )
       Riavvio = 'riavvio'
       Descrizione = "Quanta CPU Windows riserva alle attività in background mentre giochi o riproduci audio/video. Il guadagno è piccolo; valori diversi da 10 o 20 sconsigliati." }

    @{ Id = 'perf.ibernazione'; Nome = 'Ibernazione'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = 'Disattivata'; TestoPredefinito = 'Attiva'
       Descrizione = "Spegnendo l'ibernazione si libera su C: lo spazio del file hiberfil.sys (grande quanto una parte della RAM), ma si perdono l'ibernazione e l'Avvio rapido. Su un portatile di solito conviene tenerla."
       Leggi = {
           $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
           $attiva = (-not $l.Esiste) -or ($l.Valore -eq 1)
           $dim = ''
           try { $f = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction Stop; $dim = " (file di $(Formatta-Dimensione $f.Length))" } catch { }
           if ($attiva) { Nuova-Lettura ('Attiva' + $dim) 'Da modificare' $true $true } else { Nuova-Lettura 'Disattivata' 'A posto' $true $false }
       }
       Applica = {
           param($Obiettivo)
           $arg = $(if ($Obiettivo -eq 'Predefinito') { 'on' } else { 'off' })
           & powercfg.exe /hibernate $arg | Out-Null
           if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate $arg non riuscito (codice $LASTEXITCODE)." }
       }
       Originale = {
           $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
           @{ Attiva = ((-not $l.Esiste) -or ($l.Valore -eq 1)) }
       }
       Ripristina = { param($O) $arg = $(if ($O.Attiva) { 'on' } else { 'off' }); & powercfg.exe /hibernate $arg | Out-Null } }

    # ---------------------------------------------------------------- GRAFICA
    @{ Id = 'gfx.hags'; Nome = 'Pianificazione GPU con accelerazione hardware (HAGS)'; Categoria = 'Grafica'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Attiva'; TestoPredefinito = 'Decide il driver'; Etichette = @{ '1' = 'Spenta' }
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 $null) )
       Riavvio = 'riavvio'
       Descrizione = "La scheda video gestisce da sola la propria memoria: meno carico sulla CPU e latenza più bassa. Necessaria per la Frame Generation NVIDIA (DLSS 3/4). Il profilo Grafica e design non la tocca." }

    @{ Id = 'gfx.gamedvr'; Nome = 'Registrazione in background (Game Bar / DVR)'; Categoria = 'Grafica'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       TestoConsigliato = 'Spenta'; TestoPredefinito = 'Accesa'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 1),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 1) )
       Descrizione = "Spegne la registrazione continua dei giochi in background, che costa qualche FPS. La Game Bar (Win+G) resta disponibile." }

    @{ Id = 'gfx.finestra'; Nome = 'Ottimizzazioni per giochi in finestra'; Categoria = 'Grafica'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Attive'; TestoPredefinito = 'Decide Windows'
       Descrizione = "Migliora latenza e fluidità dei giochi in finestra o finestra senza bordi, e abilita Auto HDR/VRR su più giochi. Le altre impostazioni grafiche di Windows (come Auto HDR) restano come sono."
       Leggi = {
           $d = Leggi-ImpostazioniDirectX
           $v = $d.Mappa['SwapEffectUpgradeEnable']
           if ($v -eq '1') { Nuova-Lettura 'Attive' 'A posto' $true $false }
           elseif ($v -eq '0') { Nuova-Lettura 'Spente' 'Da modificare' $true $false }
           elseif ($d.Esiste) { Nuova-Lettura "Decide Windows (letto: $($d.Testo))" 'Da modificare' $true $true }   # diagnostica
           else { Nuova-Lettura 'Decide Windows' 'Da modificare' $true $true }
       }
       Applica = {
           param($Obiettivo)
           $d = Leggi-ImpostazioniDirectX
           if ($Obiettivo -eq 'Predefinito') { $d.Mappa.Remove('SwapEffectUpgradeEnable') } else { $d.Mappa['SwapEffectUpgradeEnable'] = '1' }
           Scrivi-ImpostazioniDirectX $d.Mappa
       }
       Originale  = { $d = Leggi-ImpostazioniDirectX; @{ Esiste = $d.Esiste; Testo = $d.Testo } }
       Ripristina = {
           param($O)
           if ($O.Esiste) { Scrivi-Registro $Script:ChiaveDirectX 'DirectXUserGlobalSettings' $O.Testo 'String' }
           else { Rimuovi-Registro $Script:ChiaveDirectX 'DirectXUserGlobalSettings' }
       } }

    @{ Id = 'gfx.animazioni'; Nome = 'Animazioni di finestre e barra delle applicazioni'; Categoria = 'Grafica'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       TestoConsigliato = 'Spente'; TestoPredefinito = 'Accese'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' '1' 'String'),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 1) )
       Riavvio = 'disconnessione'
       Descrizione = "Finestre che si aprono e si riducono a icona senza animazione: il sistema sembra più reattivo." }

    @{ Id = 'gfx.effetti'; Nome = 'Effetti visivi leggeri (ombre, anteprime, selezione)'; Categoria = 'Grafica'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       TestoConsigliato = 'Leggeri'; TestoPredefinito = 'Completi'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3 $null),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0 1),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0 1),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0 1) )
       Riavvio = 'disconnessione'
       Descrizione = "Toglie ombre sotto le icone, rettangolo di selezione trasparente e anteprima 'Aero Peek'. Il testo resta smussato (ClearType). Il profilo Grafica e design non la tocca." }

    @{ Id = 'gfx.trasparenza'; Nome = 'Effetti di trasparenza'; Categoria = 'Grafica'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Efficienza')
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 1) )
       Descrizione = "Menu e barre diventano opachi: un po' meno lavoro per la GPU e qualche minuto di batteria in più." }

    # ================================================================ VOCI AGGIUNTE NELLA 2.0
    # ---------------------------------------------------------------- SERVIZI E ATTIVITÀ PIANIFICATE
    @{ Id = 'svc.wmp'; Nome = 'Condivisione in rete di Windows Media Player'; Categoria = 'Servizi'; Tipo = 'Servizio'
       Servizi = @('WMPNetworkSvc'); Consigliato = 'Disattivato'; Predefinito = 'Manuale'; Rischio = 'basso'; Profili = $Tutti
       Descrizione = "Condivide musica e video del vecchio Windows Media Player con altri dispositivi della rete. Quasi nessuno lo usa." }

    @{ Id = 'att.compat'; Nome = 'Attività: analisi di compatibilità (telemetria)'; Categoria = 'Servizi'; Tipo = 'Attivita'; Rischio = 'basso'; Profili = $Tutti
       Attivita = @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', '\Microsoft\Windows\Application Experience\ProgramDataUpdater')
       Descrizione = "Attività pianificate che ogni tanto analizzano programmi e file del PC (processo CompatTelRunner) e inviano i dati a Microsoft: possono occupare CPU e disco per diversi minuti. Windows Update continua a funzionare." }

    @{ Id = 'att.ceip'; Nome = 'Attività: programma Analisi utilizzo software'; Categoria = 'Servizi'; Tipo = 'Attivita'; Rischio = 'basso'; Profili = $Tutti
       Attivita = @('\Microsoft\Windows\Customer Experience Improvement Program\Consolidator', '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip')
       Descrizione = "Raccolgono e inviano a Microsoft statistiche di utilizzo (anche dei dispositivi USB). Nessun effetto sul funzionamento del PC." }

    @{ Id = 'att.disco'; Nome = 'Attività: raccolta dati diagnostica dischi'; Categoria = 'Servizi'; Tipo = 'Attivita'; Rischio = 'basso'; Profili = $Tutti
       Attivita = @('\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector')
       Descrizione = "Invia a Microsoft informazioni generiche sui dischi. Gli avvisi sullo stato dei dischi (SMART) non vengono toccati." }

    @{ Id = 'att.feedback'; Nome = 'Attività: richieste di feedback'; Categoria = 'Servizi'; Tipo = 'Attivita'; Rischio = 'basso'; Profili = $Tutti
       Attivita = @('\Microsoft\Windows\Feedback\Siuf\DmClient', '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload')
       Descrizione = "Scaricano le domande di feedback che Windows mostra ogni tanto." }

    # ---------------------------------------------------------------- PRIVACY (altre)
    @{ Id = 'priv.consigliati'; Nome = 'Consigli e app suggerite nel menu Start'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti; MinBuild = 22621
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 1 -AssenteOk:$false) )
       Descrizione = "Toglie dalla sezione 'Consigliati' di Start i suggerimenti su app, consigli e collegamenti promozionali. I tuoi file recenti restano." }

    @{ Id = 'priv.inchiostro'; Nome = 'Personalizzazione di digitazione e input penna'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenta'; TestoPredefinito = 'Accesa'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 0),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 0),
           (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 1) )
       Descrizione = "Windows smette di raccogliere quello che scrivi per costruire un dizionario personale. La correzione automatica normale continua a funzionare." }

    @{ Id = 'priv.lingua'; Nome = 'Elenco delle lingue visibile ai siti web'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Nascosto'; TestoPredefinito = 'Visibile'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 $null) )
       Descrizione = "I siti non possono leggere l'elenco delle lingue installate in Windows (usato anche per riconoscerti)." }

    @{ Id = 'priv.esplora'; Nome = 'Pubblicità e proposte in Esplora file'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spente'; TestoPredefinito = 'Accese'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 1) )
       Descrizione = "Toglie i riquadri promozionali (OneDrive, Microsoft 365) che compaiono in Esplora file." }

    @{ Id = 'priv.ricerca'; Nome = 'Contenuti in evidenza nella casella di ricerca'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Accesi'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0 1) )
       Descrizione = "Toglie illustrazioni, ricorrenze e notizie dalla casella di ricerca della barra delle applicazioni." }

    @{ Id = 'priv.recapito'; Nome = 'Aggiornamenti condivisi con altri PC (Ottimizzazione recapito)'; Categoria = 'Privacy'; Tipo = 'Registro'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Solo dai server Microsoft'; TestoPredefinito = 'Decide Windows'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 $null) )
       Descrizione = "Il PC scarica gli aggiornamenti solo da Microsoft e non li ricarica verso altri PC: niente banda in upload usata di nascosto. Impostazione documentata da Microsoft (DODownloadMode)." }

    # ---------------------------------------------------------------- PRESTAZIONI (altre)
    @{ Id = 'perf.edge'; Nome = 'Microsoft Edge in background e avvio anticipato'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming', 'Efficienza')
       TestoConsigliato = 'Spenti'; TestoPredefinito = 'Decide Edge'
       Valori = @(
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0 $null),
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0 $null) )
       Descrizione = "Edge non resta caricato in memoria all'avvio di Windows e dopo averlo chiuso. Si apre un attimo più lentamente, ma libera RAM e processi. In Edge comparirà 'gestito dall'organizzazione': è normale (sono criteri ufficiali di Edge)." }

    @{ Id = 'perf.tasti'; Nome = 'Scorciatoie Tasti permanenti / Filtro tasti'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Spente'; TestoPredefinito = 'Accese'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' '510' 'String'),
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' '126' 'String'),
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' '62' 'String') )
       Riavvio = 'disconnessione'
       Descrizione = "Premere 5 volte Maiusc (o tenerlo premuto) non fa più comparire la finestra 'Tasti permanenti' che interrompe i giochi. Le funzioni di accessibilità restano attivabili da Impostazioni." }

    @{ Id = 'perf.mouse'; Nome = 'Accelerazione del mouse (precisione puntatore)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @()
       TestoConsigliato = 'Spenta'; TestoPredefinito = 'Accesa'
       Valori = @(
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' '1' 'String'),
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' '6' 'String'),
           (Nuovo-ValoreReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' '10' 'String') )
       Riavvio = 'disconnessione'
       Descrizione = "Il puntatore si muove sempre in proporzione al movimento della mano: mira più costante negli sparatutto. È una preferenza personale (per questo non è in nessun profilo): all'inizio il mouse sembra diverso." }

    (Nuova-VoceEnergia 'perf.usb' 'Sospensione selettiva USB (a corrente)' '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 1 `
        @{ '0' = 'Disattivata'; '1' = 'Attivata' } @('Gaming') `
        "Con l'alimentatore collegato Windows non spegne più le porte USB inattive: evita micro-disconnessioni di mouse, tastiere, cuffie e controller. Vale per il piano energetico attivo in questo momento; a batteria non cambia niente.")

    (Nuova-VoceEnergia 'perf.pcie' 'Risparmio energia PCI Express (a corrente)' '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 1 `
        @{ '0' = 'Disattivato'; '1' = 'Moderato'; '2' = 'Massimo' } @('Gaming') `
        "Con l'alimentatore collegato scheda video e SSD NVMe non entrano negli stati di risparmio del collegamento PCI Express: meno latenza al risveglio. Vale per il piano energetico attivo in questo momento; a batteria non cambia niente.")

    @{ Id = 'perf.rete'; Nome = 'Limitazione della rete durante audio/video (MMCSS)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = 'Nessuna limitazione'; TestoPredefinito = '10 pacchetti/ms'; Etichette = @{ '-1' = 'Nessuna limitazione'; '10' = '10 pacchetti/ms' }
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' -1 10) )
       Riavvio = 'riavvio'
       Descrizione = "Mentre c'è audio o video in riproduzione Windows limita il traffico di rete non multimediale (valore NetworkThrottlingIndex, documentato da Microsoft). Toglierla può aiutare con reti molto veloci; su CPU deboli può causare scatti audio." }

    # ---------------------------------------------------------------- PRESTAZIONI (aggiunte nella 3.9)
    @{ Id = 'perf.menu'; Nome = 'Ritardo di apertura dei menu'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = @('Gaming', 'Produttivita')
       TestoConsigliato = '100 ms'; TestoPredefinito = '400 ms (Windows)'
       Riavvio = 'disconnessione'
       Descrizione = "Windows aspetta 0,4 secondi prima di aprire i sottomenu (clic destro, menu dei programmi, 'Invia a'). Con 100 ms si aprono quasi subito, ma non per sbaglio mentre passi sopra col mouse. Se il valore è già più basso (0-100 ms) resta com'è. È il valore MenuShowDelay del Pannello di controllo."
       Leggi = {
           $l = Leggi-Registro 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
           $ms = 400; if ($l.Esiste) { [void][int]::TryParse([string]$l.Valore, [ref]$ms) }
           Nuova-Lettura "$ms ms" $(if ($ms -le 100) { 'A posto' } else { 'Da modificare' }) $true ($ms -eq 400)
       }
       Applica = { param($Obiettivo) Scrivi-Registro 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' $(if ($Obiettivo -eq 'Predefinito') { '400' } else { '100' }) 'String' }
       Originale = { $l = Leggi-Registro 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'; @{ Esiste = $l.Esiste; Valore = [string]$l.Valore } }
       Ripristina = {
           param($O)
           if ($O.Esiste) { Scrivi-Registro 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' ([string]$O.Valore) 'String' }
           else { Rimuovi-Registro 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' }
       } }

    @{ Id = 'perf.ultimoaccesso'; Nome = 'Data di ultimo accesso ai file (NTFS)'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Non aggiornata'; TestoPredefinito = 'Decide Windows'; Riavvio = 'riavvio'
       Descrizione = "Ogni volta che un file viene solo letto, Windows può scrivere sul disco anche la data di 'ultimo accesso'. Spegnendola si risparmiano piccole scritture continue (utile con giochi che leggono migliaia di file). Unico effetto collaterale: 'Sensore memoria' non sa più da quanto non apri un file nei Download, e i programmi di backup che usano questa data la vedono ferma. Stesso comando di 'fsutil behavior set disablelastaccess'."
       Leggi = {
           $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
           if (-not $l.Esiste) { return Nuova-Lettura 'Decide Windows' 'Da modificare' $true $true }
           # DWord letto come numero con segno: 0x80000001 = -2147483647, 0x80000002 = -2147483646
           $v = [int64]$l.Valore; if ($v -lt 0) { $v += [int64]4294967296 }
           $spenta = (($v -band 1) -eq 1)
           $gestita = $(if (($v -band 2) -eq 2) { 'decide Windows' } else { 'scelta a mano' })
           Nuova-Lettura $(if ($spenta) { "Non aggiornata ($gestita)" } else { "Aggiornata ($gestita)" }) $(if ($spenta) { 'A posto' } else { 'Da modificare' }) $true ($v -eq [int64]2147483650)
       }
       Applica = {
           param($Obiettivo)
           $val = $(if ($Obiettivo -eq 'Predefinito') { [int]-2147483646 } else { [int]-2147483647 })
           Scrivi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' $val 'DWord'
       }
       Originale = { $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'; @{ Esiste = $l.Esiste; Valore = $(if ($l.Esiste) { [int]$l.Valore } else { $null }) } }
       Ripristina = {
           param($O)
           if ($O.Esiste) { Scrivi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' ([int]$O.Valore) 'DWord' }
           else { Rimuovi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' }
       } }

    @{ Id = 'perf.priorita'; Nome = 'Precedenza ai programmi in primo piano'; Categoria = 'Prestazioni'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = $Tutti
       TestoConsigliato = 'Programmi (come Windows)'; TestoPredefinito = 'Programmi (come Windows)'
       Descrizione = "È l'opzione 'Ottimizza le prestazioni di: Programmi' (Win32PrioritySeparation): la finestra in primo piano, per esempio il gioco, riceve turni di CPU più lunghi dei programmi in background. Su Windows 10 e 11 è già così di serie (valore 2 o 38, che si equivalgono). Alcuni 'ottimizzatori' la cambiano con valori che favoriscono i servizi in background o che tolgono la precedenza: la voce controlla e, se serve, rimette il valore giusto."
       Leggi = {
           $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
           if (-not $l.Esiste) { return Nuova-Lettura 'Programmi (come Windows)' 'A posto' $true $true }
           $v = [int]$l.Valore
           if ($v -eq 2 -or $v -eq 38) { return Nuova-Lettura "Programmi (valore $v)" 'A posto' $true $true }
           if ($v -eq 24) { return Nuova-Lettura 'Servizi in background (valore 24)' 'Da modificare' }
           Nuova-Lettura "Valore cambiato da un altro programma ($v)" 'Da modificare'
       }
       Applica = { Scrivi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2 'DWord' }
       Originale = { $l = Leggi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'; @{ Esiste = $l.Esiste; Valore = $(if ($l.Esiste) { [int]$l.Valore } else { $null }) } }
       Ripristina = {
           param($O)
           if ($O.Esiste) { Scrivi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' ([int]$O.Valore) 'DWord' }
           else { Rimuovi-Registro 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' }
       } }

    @{ Id = 'perf.throttling'; Nome = 'Rallentamento dei programmi in background (Power Throttling)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'medio'
       TestoConsigliato = 'Spento'; TestoPredefinito = 'Acceso (Windows)'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 $null) )
       Riavvio = 'riavvio'
       Descrizione = "Windows mette i programmi in background in modalità a basso consumo (e sui processori Intel di nuova generazione li sposta sui core di efficienza). Spento, anche i programmi dietro al gioco (registrazione, streaming, chat vocale) girano a piena velocità. Vale anche a batteria: più consumo e calore. È l'impostazione ufficiale 'Disattiva la limitazione dell'alimentazione' dei Criteri di gruppo." }

    @{ Id = 'sic.hvci'; Nome = 'Integrità della memoria (Isolamento core)'; Categoria = 'Prestazioni'; Tipo = 'Registro'; Avanzata = $true; Rischio = 'alto'
       TestoConsigliato = 'Spenta'; TestoPredefinito = 'Accesa'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 1) )
       Riavvio = 'riavvio'
       Descrizione = "È una PROTEZIONE di Windows contro i driver malevoli. Microsoft stessa indica che spegnerla può dare qualche FPS in più nei giochi, ma il PC diventa meno protetto: fallo solo su un PC usato per giocare e riaccendila quando non serve. Alcuni giochi con anti-cheat la richiedono accesa." }

    # ---------------------------------------------------------------- ESPLORA FILE
    @{ Id = 'ui.estensioni'; Nome = 'Mostra le estensioni dei file (.exe, .pdf, .jpg)'; Categoria = 'Esplora file'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Produttivita', 'Design')
       TestoConsigliato = 'Visibili'; TestoPredefinito = 'Nascoste'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 1) )
       Descrizione = "Vedi subito di che tipo è un file: utile per lavorare e per riconoscere i falsi documenti (es. 'fattura.pdf.exe')." }

    @{ Id = 'ui.questopc'; Nome = 'Esplora file si apre su "Questo PC"'; Categoria = 'Esplora file'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Produttivita')
       TestoConsigliato = 'Questo PC'; TestoPredefinito = 'Home / Accesso rapido'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 $null) )
       Descrizione = "Esplora file mostra subito dischi e cartelle principali invece dei file recenti." }

    @{ Id = 'ui.endtask'; Nome = '"Termina attività" nel clic destro sulla barra'; Categoria = 'Esplora file'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming', 'Produttivita'); MinBuild = 22631
       TestoConsigliato = 'Attivo'; TestoPredefinito = 'Spento'
       Valori = @( (Nuovo-ValoreReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1 $null) )
       Descrizione = "Con il clic destro su un'icona della barra delle applicazioni puoi chiudere subito un programma bloccato, senza aprire Gestione attività." }

    @{ Id = 'ui.percorsi'; Nome = 'Percorsi lunghi (oltre 260 caratteri)'; Categoria = 'Esplora file'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Produttivita', 'Design')
       TestoConsigliato = 'Consentiti'; TestoPredefinito = 'Non consentiti'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 0) )
       Descrizione = "I programmi moderni possono usare cartelle e nomi molto lunghi senza errori 'percorso troppo lungo' (utile con progetti, archivi e strumenti di sviluppo)." }

    # ---------------------------------------------------------------- LATENZA (dalla 3.1)
    # Reattività di sistema, accessori (mouse, tastiere, controller), rete, processore e memoria.
    # Qui ci sono anche le voci USB, PCI Express, mouse e MMCSS spostate da Prestazioni.
    # Fonti: Microsoft Learn (MMCSS, powercfg), KB 328890 (TcpAckFrequency), parole chiave NDIS standard.

    # --- Accessori e dispositivi
    (Nuova-VoceRisparmioDispositivi 'lat.periferiche' 'Spegnimento di USB, controller e Bluetooth per risparmiare energia' 'periferiche' @('Gaming') `
        "È l'opzione 'Consenti al computer di spegnere il dispositivo' di Gestione dispositivi, per hub USB, mouse, tastiere, controller di gioco e Bluetooth. Spenta, le periferiche non vengono mai sospese: niente ritardo al primo movimento e niente disconnessioni dei controller. Consumo in più minimo. I dispositivi collegati per la prima volta in futuro tornano con l'opzione accesa: basta riapplicare la voce.")

    (Nuova-VoceRisparmioDispositivi 'lat.retepm' 'Spegnimento della scheda di rete per risparmiare energia' 'rete' @('Gaming') `
        "La stessa opzione per le schede di rete (Wi-Fi ed Ethernet). Spenta, Windows non mette in pausa la scheda: meno micro-interruzioni e ping più stabile. Consiglio ufficiale Microsoft per i problemi di rete dopo la sospensione (KB 2740020).")

    @{ Id = 'lat.hpet'; Nome = 'Timer eventi alta precisione (HPET) in Gestione dispositivi'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'
       Profili = @('Gaming', 'Produttivita', 'Design'); TestoConsigliato = 'Attivo (come Windows)'; TestoPredefinito = 'Attivo (come Windows)'; Riavvio = 'riavvio'
       Descrizione = "Molti 'ottimizzatori' disattivano questo dispositivo pensando di ridurre la latenza; in Windows deve restare attivo (è attivo di serie) e Windows sceglie da solo il timer migliore. Riattivarlo non forza l'uso dell'HPET: rimette solo la configurazione normale."
       Leggi = {
           $d = Get-PnpDevice -InstanceId 'ACPI\PNP0103*' -ErrorAction SilentlyContinue | Select-Object -First 1
           if (-not $d) { return Nuova-Lettura 'Non presente' 'Non presente' $false }
           if ([string]$d.Problem -match 'DISABLED' -or [string]$d.Status -eq 'Error') { return Nuova-Lettura 'Disattivato' 'Da modificare' }
           Nuova-Lettura 'Attivo' 'A posto' $true $true
       }
       Applica = { $d = Get-PnpDevice -InstanceId 'ACPI\PNP0103*' -ErrorAction Stop | Select-Object -First 1; Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop }
       Originale = { $d = Get-PnpDevice -InstanceId 'ACPI\PNP0103*' -ErrorAction Stop | Select-Object -First 1; @{ Id = $d.InstanceId; Attivo = -not ([string]$d.Problem -match 'DISABLED') } }
       Ripristina = { param($O) if ($O.Attivo) { Enable-PnpDevice -InstanceId $O.Id -Confirm:$false -ErrorAction Stop } else { Disable-PnpDevice -InstanceId $O.Id -Confirm:$false -ErrorAction Stop } } }

    @{ Id = 'lat.bcd'; Nome = 'Timer della piattaforma nel caricatore di avvio (bcdedit)'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'
       Profili = @('Gaming', 'Produttivita', 'Design'); TestoConsigliato = 'Valori di Windows'; TestoPredefinito = 'Valori di Windows'; Riavvio = 'riavvio'
       Descrizione = "Alcuni programmi di 'tweak' forzano useplatformclock, useplatformtick, disabledynamictick o tscsyncpolicy: di solito peggiorano la latenza e i FPS. La voce toglie questi valori e lascia scegliere a Windows. Se il disco è protetto da BitLocker tieni a portata di mano la chiave di ripristino: in rari casi un cambio dell'avvio la chiede."
       Leggi = {
           $b = Leggi-BcdTimer
           if ($b.Count -eq 0) { return Nuova-Lettura 'Valori di Windows' 'A posto' $true $true }
           Nuova-Lettura ('Forzati: ' + (($b.Keys | ForEach-Object { "$_ $($b[$_])" }) -join ', ')) 'Da modificare'
       }
       Applica = { foreach ($k in @((Leggi-BcdTimer).Keys)) { & bcdedit.exe /deletevalue '{current}' $k | Out-Null; if ($LASTEXITCODE -ne 0) { throw "bcdedit /deletevalue $k non riuscito (codice $LASTEXITCODE)" } } }
       Originale = { $b = Leggi-BcdTimer; @{ Valori = @($b.Keys | ForEach-Object { @{ Chiave = $_; Valore = $b[$_] } }) } }
       Ripristina = {
           param($O)
           foreach ($x in @($O.Valori)) {
               $val = switch -Regex ([string]$x.Valore) { '^(Yes|Sì|Si|On)$' { 'yes' } '^(No|Off)$' { 'no' } default { ([string]$x.Valore).ToLower() } }
               & bcdedit.exe /set '{current}' $x.Chiave $val | Out-Null
           }
       } }

    # --- Rete
    (Nuova-VoceProprietaRete 'lat.eee' 'Ethernet a risparmio energetico (EEE / Green Ethernet)' '*EEE' 'basso' @('Gaming') `
        "Con EEE la scheda Ethernet si 'addormenta' tra un pacchetto e l'altro: può aggiungere qualche millisecondo e piccoli scatti nel ping. Spento costa pochissima energia in più. Quando la voce viene applicata la connessione si interrompe per qualche secondo.")

    (Nuova-VoceProprietaRete 'lat.interrupt' 'Moderazione degli interrupt della scheda di rete' '*InterruptModeration' 'medio' @() `
        "La scheda raggruppa i pacchetti prima di avvisare il processore: meno lavoro per la CPU, ma un po' più di latenza. Spenta, ogni pacchetto arriva subito; su processori deboli o con download molto veloci può aumentare l'uso della CPU. La connessione si interrompe per qualche secondo quando la voce viene applicata.")

    @{ Id = 'lat.autotuning'; Nome = 'Regolazione automatica della finestra TCP'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'
       Profili = $Tutti; TestoConsigliato = 'Normale (come Windows)'; TestoPredefinito = 'Normale (come Windows)'
       Descrizione = "Windows adatta da solo la quantità di dati in viaggio sulla rete. Alcuni vecchi 'tweak' la disattivano o la limitano: download lenti e ping peggiore. Il valore giusto è 'Normale', quello di serie."
       Leggi = {
           $s = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue | Select-Object -First 1
           if (-not $s) { return Nuova-Lettura 'Non disponibile' 'Non presente' $false }
           $l = [string]$s.AutoTuningLevelLocal
           if ($l -eq 'Normal') { return Nuova-Lettura 'Normale' 'A posto' $true $true }
           $t = switch ($l) { 'Disabled' { 'Disattivata' } 'Restricted' { 'Limitata' } 'HighlyRestricted' { 'Molto limitata' } 'Experimental' { 'Sperimentale' } default { $l } }
           Nuova-Lettura $t 'Da modificare'
       }
       Applica = { & netsh.exe interface tcp set global autotuninglevel=normal | Out-Null; if ($LASTEXITCODE -ne 0) { throw "netsh non riuscito (codice $LASTEXITCODE)" } }
       Originale = { @{ Livello = [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop | Select-Object -First 1).AutoTuningLevelLocal } }
       Ripristina = { param($O) & netsh.exe interface tcp set global "autotuninglevel=$(([string]$O.Livello).ToLower())" | Out-Null } }

    @{ Id = 'lat.nagle'; Nome = 'Conferme TCP immediate (niente ritardo di Nagle / Delayed ACK)'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'medio'
       Profili = @(); TestoConsigliato = 'Immediate'; TestoPredefinito = 'Ritardate (Windows)'; Riavvio = 'riavvio'
       Descrizione = "Imposta TcpAckFrequency = 1 e TCPNoDelay = 1 sulle schede di rete con un indirizzo IP (valori documentati da Microsoft, KB 328890). Aiuta solo i giochi e i programmi che usano TCP (alcuni MMO e giochi più vecchi); i giochi moderni usano UDP e non cambiano. Microsoft consiglia di cambiarlo solo se serve: per questo non è in nessun profilo."
       Leggi = {
           $i = @(Interfacce-Tcp)
           if ($i.Count -eq 0) { return Nuova-Lettura 'Nessuna scheda con IP' 'Non presente' $false }
           $ok = @($i | Where-Object { $p = Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue; $p.TcpAckFrequency -eq 1 -and $p.TCPNoDelay -eq 1 }).Count
           $nessuno = @($i | Where-Object { $p = Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue; $null -eq $p.TcpAckFrequency -and $null -eq $p.TCPNoDelay }).Count
           if ($ok -eq $i.Count) { return Nuova-Lettura 'Immediate' 'A posto' }
           if ($nessuno -eq $i.Count) { return Nuova-Lettura 'Ritardate (Windows)' 'Da modificare' $true $true }
           Nuova-Lettura "Immediate su $ok di $($i.Count) schede" 'Da modificare'
       }
       Applica = {
           param($Obiettivo)
           foreach ($k in @(Interfacce-Tcp)) {
               if ($Obiettivo -eq 'Predefinito') { foreach ($n in @('TcpAckFrequency', 'TCPNoDelay')) { Remove-ItemProperty -LiteralPath $k -Name $n -ErrorAction SilentlyContinue } }
               else { foreach ($n in @('TcpAckFrequency', 'TCPNoDelay')) { New-ItemProperty -LiteralPath $k -Name $n -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null } }
           }
       }
       Originale = {
           @{ Interfacce = @(foreach ($k in @(Interfacce-Tcp)) { $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue; @{ Chiave = [string]$k; Ack = $p.TcpAckFrequency; NoDelay = $p.TCPNoDelay } }) }
       }
       Ripristina = {
           param($O)
           foreach ($x in @($O.Interfacce)) {
               foreach ($c in @(@('TcpAckFrequency', $x.Ack), @('TCPNoDelay', $x.NoDelay))) {
                   if ($null -eq $c[1]) { Remove-ItemProperty -LiteralPath $x.Chiave -Name $c[0] -ErrorAction SilentlyContinue }
                   else { New-ItemProperty -LiteralPath $x.Chiave -Name $c[0] -Value ([int]$c[1]) -PropertyType DWord -Force | Out-Null }
               }
           }
       } }

    # --- Processore, memoria e sistema
    @{ Id = 'lat.mmcssgiochi'; Nome = 'Priorità dei giochi nello scheduler multimediale (MMCSS)'; Categoria = 'Latenza'; Tipo = 'Registro'; Rischio = 'basso'; Profili = @('Gaming')
       TestoConsigliato = 'Alta'; TestoPredefinito = 'Media (Windows)'
       Valori = @(
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6 2),
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'Medium' 'String'),
           (Nuovo-ValoreReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'Normal' 'String') )
       Riavvio = 'riavvio'
       Descrizione = "I giochi che si registrano al servizio multimediale di Windows (MMCSS) ricevono più priorità di CPU e di disco. Valori documentati da Microsoft (Priority, Scheduling Category, SFIO Priority dell'attività 'Games'). Effetto solo sui giochi che usano MMCSS; non toglie niente agli altri programmi." }

    (Con-Campi (Nuova-VoceEnergia 'lat.cpumin' 'Frequenza minima del processore (a corrente)' '54533251-82be-4824-96c1-47b60b740d00' '893dee8e-2bef-41e0-89c6-b55d0929964c' 100 5 `
        @{ '5' = '5% (Windows)'; '50' = '50%'; '100' = '100% (sempre pronta)' } @() `
        "Con l'alimentatore collegato il processore non scende sotto la frequenza scelta: risponde subito senza tempo di 'risveglio'. Più consumo, calore e rumore della ventola anche quando il PC non fa niente. Vale per il piano energetico attivo; a batteria non cambia niente.") `
        @{ Categoria = 'Latenza'; Rischio = 'medio' })

    @{ Id = 'lat.timer'; Nome = 'Risoluzione del timer valida per tutto il sistema'; Categoria = 'Latenza'; Tipo = 'Registro'; Rischio = 'medio'; Profili = @(); MinBuild = 22000
       TestoConsigliato = 'Globale'; TestoPredefinito = 'Per singola app (Windows)'
       Valori = @( (Nuovo-ValoreReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1 $null) )
       Riavvio = 'riavvio'
       Descrizione = "Da Windows 10 2004 ogni programma ha la sua risoluzione del timer; con questo valore (Windows 11) una richiesta di timer preciso vale di nuovo per tutto il sistema, come prima. Può rendere più regolari alcuni giochi vecchi e programmi audio, ma aumenta un po' i consumi. È una correzione di nicchia: non è in nessun profilo." }

    @{ Id = 'lat.pagefile'; Nome = 'File di paging gestito da Windows'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'
       Profili = $Tutti; TestoConsigliato = 'Automatico'; TestoPredefinito = 'Automatico'; Riavvio = 'riavvio'
       Descrizione = "La memoria virtuale deve essere gestita da Windows. Alcuni 'ottimizzatori' la disattivano o la impostano troppo piccola: con giochi pesanti si hanno blocchi, chiusure improvvise ed errori di memoria esaurita anche con tanta RAM."
       Leggi = {
           $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
           if ($cs.AutomaticManagedPagefile) { return Nuova-Lettura 'Automatico' 'A posto' $true $true }
           $f = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
           Nuova-Lettura $(if ($f.Count -eq 0) { 'Disattivato' } else { 'Manuale: ' + (($f | ForEach-Object { "$($_.Name) $($_.InitialSize)-$($_.MaximumSize) MB" }) -join ', ') }) 'Da modificare'
       }
       Applica = { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop }
       Originale = {
           $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
           @{ Automatico = [bool]$cs.AutomaticManagedPagefile; File = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object { @{ Nome = [string]$_.Name; Iniziale = [int]$_.InitialSize; Massimo = [int]$_.MaximumSize } }) }
       }
       Ripristina = {
           param($O)
           $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
           Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = [bool]$O.Automatico } -ErrorAction Stop
           if (-not $O.Automatico) {
               foreach ($f in @($O.File)) {
                   $e = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $f.Nome }
                   if ($e) { Set-CimInstance -InputObject $e -Property @{ InitialSize = [uint32]$f.Iniziale; MaximumSize = [uint32]$f.Massimo } }
                   else { New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $f.Nome; InitialSize = [uint32]$f.Iniziale; MaximumSize = [uint32]$f.Massimo } | Out-Null }
               }
           }
       } }

    @{ Id = 'lat.refresh'; Nome = 'Frequenza di aggiornamento dello schermo - da fare a mano'; Categoria = 'Latenza'; Tipo = 'Personalizzato'; Rischio = 'basso'; Profili = @()
       TestoConsigliato = 'La più alta'; TestoPredefinito = 'La più alta'
       Manuale = "Imposta la frequenza più alta: Impostazioni > Sistema > Schermo > Schermo avanzato > Scegli una frequenza di aggiornamento. Su Windows 11 puoi anche lasciare 'Dinamica' se c'è: sale da sola al massimo nei giochi."
       Descrizione = "Più Hz = immagine più fluida e meno ritardo tra comando e schermo (a 240 Hz un fotogramma dura 4 ms, a 60 Hz 17 ms). Molti portatili a batteria scendono a 60 Hz. Il programma la controlla soltanto: si cambia da Impostazioni."
       Leggi = {
           $v = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentRefreshRate -gt 1 -and $_.MaxRefreshRate -gt 1 })
           if ($v.Count -eq 0) { return Nuova-Lettura 'Non disponibile' 'Non presente' $false }
           $att = ($v | Measure-Object CurrentRefreshRate -Maximum).Maximum; $max = ($v | Measure-Object MaxRefreshRate -Maximum).Maximum
           Nuova-Lettura "$att Hz (massimo $max Hz)" $(if ($att -ge $max) { 'A posto' } else { 'Da modificare' })
       }
       Applica = { } ; Originale = { @{} } ; Ripristina = { } }

    # ---------------------------------------------------------------- NVIDIA
    # Impostazioni globali del Pannello di controllo NVIDIA (profilo "Impostazioni globali").
    # Codici e valori: file ufficiale NvApiDriverSettings.h dell'SDK pubblico NVIDIA (github.com/NVIDIA/nvapi).
    #   IdNv          codice dell'impostazione
    #   ValoreDriver  valore di serie (usato solo se il driver non lo comunica da solo)
    #   Opzioni       scelte del menu a tendina: coppie (valore, testo)
    #   Preset        valore per ogni preset; $null = "lascia il valore di serie del driver"
    #   PresetAlmeno  il preset indica un minimo: se il valore attuale è più alto resta com'è
    # "Annulla tutto" rimette quello che c'era prima.
    @{ Id = 'nv.energia'; Nome = 'Modalità di gestione dell''alimentazione'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '1057EB71'); ValoreDriver = 5
       Opzioni = @( @(5, 'Normale (ottimale)'), @(0, 'Adattiva'), @(1, 'Prestazioni massime'), @(3, 'Prestazioni costanti'), @(4, 'Consumo minimo'), @(2, 'Controllata dal driver') )
       Preset = @{ Gaming = 1; Grafica = 5; Produttivita = 5 }
       Descrizione = "Con 'Prestazioni massime' la GPU resta alle frequenze più alte mentre un gioco è in esecuzione: meno cali e scatti, più consumo e calore. 'Normale' abbassa le frequenze quando il carico è leggero." }

    @{ Id = 'nv.latenza'; Nome = 'Bassa latenza (fotogrammi pre-renderizzati)'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '007BA09E'); ValoreDriver = 0
       Opzioni = @( @(0, "Decide l'applicazione"), @(1, '1 fotogramma (bassa latenza)'), @(2, '2 fotogrammi'), @(3, '3 fotogrammi'), @(4, '4 fotogrammi') )
       Preset = @{ Gaming = 1; Grafica = 0; Produttivita = 0 }
       Descrizione = "Quanti fotogrammi la CPU prepara in anticipo. Con 1 i comandi arrivano sullo schermo prima (equivale a 'Modalità bassa latenza: Attiva'). Nei giochi con NVIDIA Reflex vale l'impostazione del gioco. La modalità 'Ultra' si attiva solo dal Pannello NVIDIA." }

    @{ Id = 'nv.fps'; Nome = 'Frequenza fotogrammi massima'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '10835002'); ValoreDriver = 0
       Opzioni = @( @(0, 'Nessun limite'), @(30, '30 FPS'), @(60, '60 FPS'), @(72, '72 FPS'), @(90, '90 FPS'), @(117, '117 FPS'), @(120, '120 FPS'), @(141, '141 FPS'), @(144, '144 FPS'),
                    @(162, '162 FPS'), @(165, '165 FPS'), @(237, '237 FPS'), @(240, '240 FPS'), @(357, '357 FPS'), @(360, '360 FPS') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Limita gli FPS di tutti i giochi e programmi 3D. Con G-SYNC conviene un limite di 3 FPS sotto la frequenza dello schermo (117, 141, 162, 237, 357). Un limite più basso riduce consumi, calore e rumore." }

    @{ Id = 'nv.refresh'; Nome = 'Frequenza di aggiornamento preferita'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '0064B541'); ValoreDriver = 0
       Opzioni = @( @(0, "Decide l'applicazione"), @(1, 'La più alta disponibile') )
       Preset = @{ Gaming = 1; Grafica = 0; Produttivita = 0 }
       Descrizione = "I giochi a schermo intero usano la frequenza più alta dello schermo anche se ne chiedono una più bassa." }

    @{ Id = 'nv.cacheon'; Nome = 'Cache shader'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '00198FFF'); ValoreDriver = 1
       Opzioni = @( @(1, 'Attivata'), @(0, 'Disattivata') )
       Preset = @{ Gaming = 1; Grafica = 1; Produttivita = 1 }
       Descrizione = "Salva su disco gli shader già compilati: meno scatti e caricamenti più rapidi. Conviene sempre lasciarla attivata." }

    @{ Id = 'nv.cache'; Nome = 'Dimensione massima della cache shader'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Prestazioni'; Rischio = 'basso'
       IdNv = (Nv-Hex '00AC8497'); ValoreDriver = 16384; PresetAlmeno = $true
       Opzioni = @( @(16384, 'Predefinita del driver'), @(1024, '1 GB'), @(5120, '5 GB'), @(10240, '10 GB'), @(102400, '100 GB'), @((Nv-Hex 'FFFFFFFF'), 'Illimitata') )
       Preset = @{ Gaming = 10240; Grafica = 10240; Produttivita = $null }
       Descrizione = "Spazio massimo su disco per gli shader salvati. La cache cresce solo quando serve; con molti giochi 10 GB o più evitano ricompilazioni. I preset non la riducono mai se è già più grande." }

    @{ Id = 'nv.vsync'; Nome = 'Sincronizzazione verticale (V-Sync)'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Sincronizzazione'; Rischio = 'basso'
       IdNv = (Nv-Hex '00A879CF'); ValoreDriver = (Nv-Hex '60925292')
       Opzioni = @( @((Nv-Hex '60925292'), "Decide l'applicazione"), @((Nv-Hex '08416747'), 'Disattivata'), @((Nv-Hex '47814940'), 'Attivata'), @((Nv-Hex '18888888'), 'Veloce (Fast Sync)'),
                    @((Nv-Hex '32610244'), 'Metà della frequenza'), @((Nv-Hex '71271021'), 'Un terzo della frequenza'), @((Nv-Hex '13245256'), 'Un quarto della frequenza') )
       Preset = @{ Gaming = (Nv-Hex '60925292'); Grafica = (Nv-Hex '60925292'); Produttivita = (Nv-Hex '60925292') }
       Descrizione = "Lasciarla decidere al gioco è la scelta più flessibile. Con G-SYNC attivo molti preferiscono 'Attivata' qui e un limite di FPS poco sotto la frequenza dello schermo. 'Disattivata' dà la latenza minima ma può 'strappare' l'immagine." }

    @{ Id = 'nv.vsyncadattiva'; Nome = 'V-Sync adattiva (controllo strappi)'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Sincronizzazione'; Rischio = 'basso'
       IdNv = (Nv-Hex '005A375C'); ValoreDriver = (Nv-Hex '96861077')
       Opzioni = @( @((Nv-Hex '96861077'), 'Standard'), @((Nv-Hex '99941284'), 'Adattiva') )
       Preset = @{ Gaming = (Nv-Hex '96861077'); Grafica = (Nv-Hex '96861077'); Produttivita = (Nv-Hex '96861077') }
       Descrizione = "Con 'Adattiva' la V-Sync (se attivata) si spegne da sola quando gli FPS scendono sotto la frequenza dello schermo, evitando rallentamenti. Ha effetto solo insieme a V-Sync 'Attivata'." }

    @{ Id = 'nv.triplo'; Nome = 'Triplo buffering (OpenGL)'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Sincronizzazione'; Rischio = 'basso'
       IdNv = (Nv-Hex '20FDD1F9'); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Riguarda solo i programmi OpenGL con V-Sync attiva: rende più regolari gli FPS quando scendono sotto la frequenza dello schermo, usando un po' più di memoria video." }

    @{ Id = 'nv.texture'; Nome = 'Filtro texture - qualità'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '00CE2691'); ValoreDriver = 0
       Opzioni = @( @((Nv-Hex 'FFFFFFF6'), 'Alta qualità'), @(0, 'Qualità'), @(10, 'Prestazioni'), @(20, 'Prestazioni elevate') )
       Preset = @{ Gaming = 20; Grafica = (Nv-Hex 'FFFFFFF6'); Produttivita = 0 }
       Descrizione = "Verso 'Prestazioni' il driver usa scorciatoie nel filtraggio delle texture: qualche FPS in più, differenza visiva minima. 'Alta qualità' le toglie tutte: adatta a grafica e design." }

    @{ Id = 'nv.trilineare'; Nome = 'Filtro texture - ottimizzazione trilineare'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '002ECAF2'); ValoreDriver = 0
       Opzioni = @( @(0, 'Attivata'), @(1, 'Disattivata') )
       Preset = @{ Gaming = 0; Grafica = 1; Produttivita = 0 }
       Descrizione = "Semplifica il filtro trilineare dove la differenza non si nota: un po' più di prestazioni. Con qualità 'Alta qualità' va disattivata." }

    @{ Id = 'nv.anisoopt'; Nome = 'Filtro texture - ottimizzazione campione anisotropico'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '00E73211'); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivata'), @(1, 'Attivata') )
       Preset = @{ Gaming = 1; Grafica = 0; Produttivita = 0 }
       Descrizione = "Riduce i campioni usati dal filtro anisotropico: qualche FPS in più con una perdita di nitidezza appena visibile sulle superfici inclinate." }

    @{ Id = 'nv.lodbias'; Nome = 'Filtro texture - LOD bias negativo'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '0019BB68'); ValoreDriver = 0
       Opzioni = @( @(0, 'Consenti'), @(1, 'Blocca') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "'Consenti' lascia ai giochi la possibilità di rendere le texture più nitide. 'Blocca' riduce lo sfarfallio delle texture in lontananza quando forzi il filtro anisotropico." }

    @{ Id = 'nv.anisomodo'; Nome = 'Filtro anisotropico - modalità'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '10D2BB16'); ValoreDriver = 0
       Opzioni = @( @(0, "Decide l'applicazione"), @(1, 'Forzato dal driver (usa il livello qui sotto)') )
       Preset = @{ Gaming = 0; Grafica = 1; Produttivita = 0 }
       Descrizione = "Il filtro anisotropico rende nitide le texture viste di sbieco (strade, pavimenti). Di norma lo decide il gioco; 'Forzato' applica a tutti il livello scelto nella voce successiva." }

    @{ Id = 'nv.anisolivello'; Nome = 'Filtro anisotropico - livello'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Filtro texture'; Rischio = 'basso'
       IdNv = (Nv-Hex '101E61A9'); ValoreDriver = 1
       Opzioni = @( @(1, 'Nessuno'), @(2, '2x'), @(4, '4x'), @(8, '8x'), @(16, '16x') )
       Preset = @{ Gaming = $null; Grafica = 16; Produttivita = $null }
       Descrizione = "Livello usato solo quando la modalità qui sopra è 'Forzato dal driver'. 16x è la qualità massima e sulle schede moderne costa pochissimo." }

    @{ Id = 'nv.aamodo'; Nome = 'Antialiasing - modalità'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Antialiasing'; Rischio = 'basso'
       IdNv = (Nv-Hex '107EFC5B'); ValoreDriver = 0
       Opzioni = @( @(0, "Decide l'applicazione"), @(1, "Sostituisci l'impostazione dell'applicazione"), @(2, "Migliora l'impostazione dell'applicazione") )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Chi decide l'antialiasing (la smussatura dei bordi). Lasciarlo all'applicazione è quasi sempre la scelta giusta: i giochi moderni usano i propri metodi (TAA, DLSS)." }

    @{ Id = 'nv.fxaa'; Nome = 'Antialiasing - FXAA'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Antialiasing'; Rischio = 'basso'
       IdNv = (Nv-Hex '1074C972'); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Smussatura veloce applicata a tutta l'immagine. Attivata per tutti i programmi rende leggermente sfocati anche testi e interfacce: meglio lasciarla spenta qui." }

    @{ Id = 'nv.aagamma'; Nome = 'Antialiasing - correzione gamma'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Antialiasing'; Rischio = 'basso'
       IdNv = (Nv-Hex '107D639D'); ValoreDriver = 2
       Opzioni = @( @(2, 'Attivata'), @(0, 'Disattivata'), @(1, 'Attivata solo con sovracampionamento') )
       Preset = @{ Gaming = $null; Grafica = 2; Produttivita = $null }
       Descrizione = "Migliora i colori dei bordi smussati nei programmi OpenGL. Nessun costo sulle prestazioni." }

    @{ Id = 'nv.aatrasp'; Nome = 'Antialiasing - trasparenza (multisampling)'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Antialiasing'; Rischio = 'basso'
       IdNv = (Nv-Hex '10FC2D9C'); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(4, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Smussa anche i bordi di oggetti con parti trasparenti (reti, foglie, recinzioni) nei giochi che usano MSAA. Costa qualche FPS." }

    @{ Id = 'nv.mfaa'; Nome = 'Antialiasing - MFAA'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'Antialiasing'; Rischio = 'basso'
       IdNv = (Nv-Hex '0098C1AC'); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Nei giochi con MSAA dà una qualità simile a un livello più alto con meno lavoro per la GPU. Funziona solo con i giochi compatibili." }

    @{ Id = 'nv.thread'; Nome = 'Ottimizzazione thread'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'OpenGL e Vulkan'; Rischio = 'basso'
       IdNv = (Nv-Hex '20C1221E'); ValoreDriver = 0
       Opzioni = @( @(0, 'Automatica'), @(1, 'Attivata'), @(2, 'Disattivata') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Uso di più core della CPU nei programmi OpenGL. 'Automatica' (decide il driver) è la scelta migliore quasi sempre." }

    @{ Id = 'nv.present'; Nome = 'Metodo di presentazione Vulkan/OpenGL'; Categoria = 'NVIDIA'; Tipo = 'NVIDIA'; Area = 'OpenGL e Vulkan'; Rischio = 'basso'
       IdNv = (Nv-Hex '20D690F8'); ValoreDriver = 2
       Opzioni = @( @(2, 'Automatico'), @(0, 'Nativo'), @(1, 'Preferisci a livelli su DXGI') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null }
       Descrizione = "Come i giochi Vulkan e OpenGL mostrano l'immagine. 'A livelli su DXGI' li fa comportare come i giochi DirectX (finestra senza bordi più fluida, Auto HDR, G-SYNC in finestra). 'Automatico' lascia decidere al driver." }

    # ---------------------------------------------------------------- AMD
    # Impostazioni grafiche globali di AMD Software: Adrenalin Edition, lette e scritte con ADLX.
    #   Amd = @( posto in IADLX3DSettingsServices, con GPU, posto di lettura, booleano, posto di scrittura )
    #         (posti e funzioni: file I3DSettings.h dell'SDK ADLX)
    #   ValoreDriver  valore tipico di serie ($null = nessun valore fisso: "Riporta al predefinito" non la tocca)
    #   Opzioni / Preset come per NVIDIA; Preset 'Batteria' facoltativo (se manca vale 'Produttivita')
    @{ Id = 'amd.antilag'; Nome = 'Radeon Anti-Lag'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(3, $true, 4, $true, 5); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 1; Grafica = 0; Produttivita = 0; Batteria = 0 }
       Descrizione = "Riduce il ritardo tra i comandi (mouse, tastiera) e l'immagine sullo schermo. Non si può usare insieme a Radeon Chill: accendendo uno, il driver spegne l'altro." }

    @{ Id = 'amd.chill'; Nome = 'Radeon Chill'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(4, $true, 4, $true, 8); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0; Batteria = 1 }
       Descrizione = "Abbassa da solo gli FPS quando nel gioco ti muovi poco: meno consumi, calore e rumore. Utile a batteria. Non si usa insieme ad Anti-Lag." }

    @{ Id = 'amd.chill.max'; Nome = 'Radeon Chill - FPS massimi'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(4, $true, 7, $false, 10); ValoreDriver = $null
       Opzioni = @( @(30, '30 FPS'), @(45, '45 FPS'), @(60, '60 FPS'), @(75, '75 FPS'), @(90, '90 FPS'), @(120, '120 FPS'), @(144, '144 FPS'), @(165, '165 FPS'), @(240, '240 FPS') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null; Batteria = 60 }
       Descrizione = "Il limite più alto di FPS che Chill usa quando ti muovi. Con la batteria 60 FPS è un buon compromesso. Valori fuori dall'intervallo della tua scheda vengono rifiutati dal driver." }

    @{ Id = 'amd.boost'; Nome = 'Radeon Boost'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(5, $true, 4, $true, 7); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Abbassa la risoluzione durante i movimenti veloci per guadagnare FPS. Funziona solo nei giochi compatibili e rende l'immagine meno nitida mentre ti muovi." }

    @{ Id = 'amd.ris'; Nome = 'Radeon Image Sharpening'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Qualità immagine'; Rischio = 'basso'
       Amd = @(6, $true, 4, $true, 7); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 1; Grafica = 0; Produttivita = 0 }
       Descrizione = "Rende più nitida l'immagine dei giochi con un costo minimo. Per grafica e video conviene spento, così i colori e i dettagli restano quelli originali." }

    @{ Id = 'amd.ris.liv'; Nome = 'Image Sharpening - intensità'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Qualità immagine'; Rischio = 'basso'
       Amd = @(6, $true, 6, $false, 8); ValoreDriver = 80
       Opzioni = @( @(10, '10%'), @(20, '20%'), @(30, '30%'), @(40, '40%'), @(50, '50%'), @(60, '60%'), @(70, '70%'), @(80, '80%'), @(90, '90%'), @(100, '100%') )
       Preset = @{ Gaming = 50; Grafica = $null; Produttivita = $null }
       Descrizione = "Quanto è forte la nitidezza quando Image Sharpening è attivo. Valori alti possono far vedere i bordi troppo marcati." }

    @{ Id = 'amd.esync'; Nome = 'Enhanced Sync'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Sincronizzazione'; Rischio = 'basso'
       Amd = @(7, $true, 4, $true, 5); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Toglie lo 'strappo' dell'immagine con meno ritardo della V-Sync classica. Con uno schermo FreeSync di solito non serve. Non si usa insieme alla V-Sync forzata." }

    @{ Id = 'amd.vsync'; Nome = 'Attendi aggiornamento verticale (V-Sync)'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Sincronizzazione'; Rischio = 'basso'
       Amd = @(8, $true, 5, $false, 6); ValoreDriver = 1
       Opzioni = @( @(0, 'Sempre disattivata'), @(1, "Disattivata, salvo indicazione dell'app"), @(2, "Attivata, salvo indicazione dell'app"), @(3, 'Sempre attivata') )
       Preset = @{ Gaming = 1; Grafica = 1; Produttivita = 1 }
       Descrizione = "Sincronizza i fotogrammi con lo schermo. Di solito conviene lasciare decidere al gioco." }

    @{ Id = 'amd.frtc'; Nome = 'Frame Rate Target Control (limite FPS)'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(9, $true, 4, $true, 7); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Limita gli FPS di tutti i giochi al valore qui sotto: meno consumi e calore. Spento = nessun limite." }

    @{ Id = 'amd.frtc.fps'; Nome = 'Frame Rate Target Control - FPS'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Prestazioni'; Rischio = 'basso'
       Amd = @(9, $true, 6, $false, 8); ValoreDriver = $null
       Opzioni = @( @(30, '30 FPS'), @(60, '60 FPS'), @(75, '75 FPS'), @(90, '90 FPS'), @(117, '117 FPS'), @(120, '120 FPS'), @(141, '141 FPS'), @(144, '144 FPS'), @(162, '162 FPS'), @(165, '165 FPS'), @(237, '237 FPS'), @(240, '240 FPS') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null }
       Descrizione = "Il limite di FPS usato quando Frame Rate Target Control è attivo. Con FreeSync conviene qualche FPS sotto la frequenza dello schermo." }

    @{ Id = 'amd.aa.modo'; Nome = 'Antialiasing - modalità'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Antialiasing'; Rischio = 'basso'
       Amd = @(10, $true, 4, $false, 7); ValoreDriver = 0
       Opzioni = @( @(0, "Usa le impostazioni dell'applicazione"), @(1, "Migliora le impostazioni dell'applicazione"), @(2, "Sostituisci le impostazioni dell'applicazione") )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Chi decide l'antialiasing. Lasciarlo all'applicazione è quasi sempre la scelta migliore." }

    @{ Id = 'amd.aa.livello'; Nome = 'Antialiasing - livello'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Antialiasing'; Rischio = 'basso'
       Amd = @(10, $true, 5, $false, 8); ValoreDriver = $null
       Opzioni = @( @(2, '2x'), @(3, '2x EQ'), @(4, '4x'), @(5, '4x EQ'), @(8, '8x'), @(9, '8x EQ') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null }
       Descrizione = "Livello usato quando la modalità è 'Migliora' o 'Sostituisci'. Più alto = bordi più lisci ma meno FPS." }

    @{ Id = 'amd.aa.metodo'; Nome = 'Antialiasing - metodo'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Antialiasing'; Rischio = 'basso'
       Amd = @(10, $true, 6, $false, 9); ValoreDriver = 0
       Opzioni = @( @(0, 'Multicampionamento'), @(1, 'Multicampionamento adattivo'), @(2, 'Supercampionamento') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null }
       Descrizione = "Tecnica usata dall'antialiasing del driver. Il supercampionamento è il più bello ma pesa molto sulla scheda." }

    @{ Id = 'amd.mlaa'; Nome = 'Antialiasing morfologico'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Antialiasing'; Rischio = 'basso'
       Amd = @(11, $true, 4, $true, 5); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Ammorbidisce i bordi in tutti i giochi, ma sfoca un po' anche testi e interfaccia." }

    @{ Id = 'amd.af'; Nome = 'Filtro anisotropico'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Texture'; Rischio = 'basso'
       Amd = @(12, $true, 4, $true, 6); ValoreDriver = 0
       Opzioni = @( @(0, "Disattivato (decide l'applicazione)"), @(1, 'Attivato (forzato dal driver)') )
       Preset = @{ Gaming = 0; Grafica = 1; Produttivita = 0 }
       Descrizione = "Rende più nitide le texture viste di sbieco (strade, pavimenti). Costa pochissimo sulle schede moderne." }

    @{ Id = 'amd.af.livello'; Nome = 'Filtro anisotropico - livello'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Texture'; Rischio = 'basso'
       Amd = @(12, $true, 5, $false, 7); ValoreDriver = $null
       Opzioni = @( @(2, '2x'), @(4, '4x'), @(8, '8x'), @(16, '16x') )
       Preset = @{ Gaming = $null; Grafica = 16; Produttivita = $null }
       Descrizione = "Livello del filtro anisotropico quando è forzato dal driver." }

    @{ Id = 'amd.tess.modo'; Nome = 'Tassellatura - modalità'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Qualità immagine'; Rischio = 'basso'
       Amd = @(13, $true, 4, $false, 6); ValoreDriver = 0
       Opzioni = @( @(0, 'Ottimizzata da AMD'), @(1, "Usa le impostazioni dell'applicazione"), @(2, "Sostituisci le impostazioni dell'applicazione") )
       Preset = @{ Gaming = 0; Grafica = 1; Produttivita = 0 }
       Descrizione = "Dettaglio delle superfici 3D. 'Ottimizzata da AMD' limita i casi esagerati che rallentano; per lavori di grafica conviene lasciare decidere all'applicazione." }

    @{ Id = 'amd.tess.livello'; Nome = 'Tassellatura - livello massimo'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Qualità immagine'; Rischio = 'basso'
       Amd = @(13, $true, 5, $false, 7); ValoreDriver = $null
       Opzioni = @( @(1, 'Spenta'), @(2, '2x'), @(4, '4x'), @(6, '6x'), @(8, '8x'), @(16, '16x'), @(32, '32x'), @(64, '64x') )
       Preset = @{ Gaming = $null; Grafica = $null; Produttivita = $null }
       Descrizione = "Livello massimo usato quando la modalità è 'Sostituisci'." }

    @{ Id = 'amd.rsr'; Nome = 'Radeon Super Resolution'; Categoria = 'AMD'; Tipo = 'AMD'; Area = 'Qualità immagine'; Rischio = 'basso'
       Amd = @(14, $false, 4, $true, 5); ValoreDriver = 0
       Opzioni = @( @(0, 'Disattivato'), @(1, 'Attivato') )
       Preset = @{ Gaming = 0; Grafica = 0; Produttivita = 0 }
       Descrizione = "Fa girare i giochi a schermo intero a una risoluzione più bassa e la ingrandisce: più FPS ma immagine meno definita. Utile solo sulle schede poco potenti." }


    # ---------------------------------------------------------------- PULIZIA
    @{ Id = 'pul.tempUtente'; Nome = 'File temporanei dell''utente'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @( (Nuovo-PercorsoPulizia '%TEMP%' 1) )
       Descrizione = "Cartella Temp del tuo utente. Vengono cancellati solo i file più vecchi di 1 giorno; quelli in uso vengono saltati." }

    @{ Id = 'pul.tempWindows'; Nome = 'File temporanei di Windows'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @( (Nuovo-PercorsoPulizia '%WINDIR%\Temp' 1) )
       Descrizione = "Cartella C:\Windows\Temp. Solo i file più vecchi di 1 giorno; quelli in uso vengono saltati." }

    @{ Id = 'pul.miniature'; Nome = 'Cache delle miniature'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @( (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Microsoft\Windows\Explorer' 0 'thumbcache_*.db' $false) )
       Descrizione = "Anteprime di foto e video salvate da Esplora file. Vengono ricreate quando servono. I file in uso vengono saltati." }

    @{ Id = 'pul.errori'; Nome = 'Rapporti errori e dump degli arresti anomali'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @(
           (Nuovo-PercorsoPulizia '%ProgramData%\Microsoft\Windows\WER\ReportArchive' 0),
           (Nuovo-PercorsoPulizia '%ProgramData%\Microsoft\Windows\WER\ReportQueue' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\CrashDumps' 0) )
       Descrizione = "Rapporti già inviati o in attesa e dump di programmi che si sono chiusi in errore." }

    @{ Id = 'pul.recapito'; Nome = 'Cache di Ottimizzazione recapito'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @( (Nuovo-PercorsoPulizia '%WINDIR%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache' 0) )
       Azione = { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }
       Descrizione = "Pezzi di aggiornamenti tenuti per condividerli con altri PC. Svuotata con il comando ufficiale di Windows." }

    @{ Id = 'pul.windowsupdate'; Nome = 'Download di Windows Update già usati'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'medio'; Profili = @('Gaming', 'Produttivita')
       Percorsi = @( (Nuovo-PercorsoPulizia '%WINDIR%\SoftwareDistribution\Download' 0) )
       Prima = {
           $stato = @{}
           foreach ($s in @('wuauserv', 'bits')) {
               $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
               if ($svc) { $stato[$s] = ($svc.Status -eq 'Running'); if ($stato[$s]) { Stop-Service -Name $s -Force -ErrorAction Stop } }
           }
           $stato
       }
       Dopo = { param($Stato) foreach ($k in @($Stato.Keys)) { if ($Stato[$k]) { Start-Service -Name $k -ErrorAction SilentlyContinue } } }
       Descrizione = "File scaricati per aggiornamenti già installati. Windows Update viene fermato per un attimo e poi riavviato. Se un aggiornamento era in download, verrà riscaricato. Non usarla mentre Windows sta aggiornando." }

    @{ Id = 'pul.cestino'; Nome = 'Svuota il Cestino'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'medio'; Profili = @()
       Misura = {
           $tot = [int64]0; $n = 0
           try { $sh = New-Object -ComObject Shell.Application; foreach ($i in $sh.NameSpace(10).Items()) { $tot += [int64]$i.Size; $n++ } } catch { }
           @{ Byte = $tot; File = $n }
       }
       Azione = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
       Descrizione = "Elimina DEFINITIVAMENTE i file nel Cestino. Controlla prima che non ci sia niente da recuperare." }

    @{ Id = 'pul.dism'; Nome = 'Pulizia componenti di Windows (DISM)'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Avanzata = $true; Rischio = 'alto'
       SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\Dism.exe" '/Online /Cleanup-Image /StartComponentCleanup'
           if ($codice -ne 0) { throw "DISM ha restituito il codice $codice." }
       }
       Descrizione = "Elimina le vecchie versioni dei componenti sostituite dagli aggiornamenti (anche alcuni GB). Dopo NON potrai più disinstallare gli aggiornamenti già installati. Richiede diversi minuti." }

    # ---------------------------------------------------------------- PULIZIA (aggiunte nella 2.0)
    @{ Id = 'pul.inet'; Nome = 'File temporanei Internet di Windows'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @( (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Microsoft\Windows\INetCache' 1) )
       Descrizione = "Copie temporanee di pagine e immagini scaricate da Windows e dalle app. Solo i file più vecchi di 1 giorno." }

    @{ Id = 'pul.dump'; Nome = 'Dump di memoria delle schermate blu'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = $Tutti
       Percorsi = @(
           (Nuovo-PercorsoPulizia '%WINDIR%\Minidump' 30),
           (Nuovo-PercorsoPulizia '%WINDIR%\LiveKernelReports' 30 '*.dmp') )
       Descrizione = "File creati quando Windows o un driver vanno in errore. Vengono eliminati solo quelli più vecchi di 30 giorni: i recenti restano, nel caso servano per capire un problema." }

    @{ Id = 'pul.log'; Nome = 'Vecchi registri degli aggiornamenti (CBS)'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @('Gaming', 'Produttivita')
       Percorsi = @( (Nuovo-PercorsoPulizia '%WINDIR%\Logs\CBS' 14) )
       Descrizione = "Registri archiviati dell'installazione degli aggiornamenti, a volte molto grandi. Solo i file più vecchi di 14 giorni; quello in uso viene saltato." }

    @{ Id = 'pul.browser'; Nome = 'Cache dei browser (Edge, Chrome, Brave, Firefox)'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @()
       Percorsi = @(
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Cache\Cache_Data' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Code Cache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Google\Chrome\User Data\*\Cache\Cache_Data' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Google\Chrome\User Data\*\Code Cache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Cache\Cache_Data' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Code Cache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2' 0) )
       Descrizione = "Solo la cache (copie temporanee delle pagine): password, cronologia, preferiti e accessi ai siti NON vengono toccati. Chiudi i browser prima, altrimenti i file in uso vengono saltati. Le prime pagine si caricheranno un po' più lentamente." }

    @{ Id = 'pul.shader'; Nome = 'Cache degli shader (DirectX, NVIDIA, AMD, Intel)'; Categoria = 'Pulizia'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @()
       Percorsi = @(
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\D3DSCache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\NVIDIA\DXCache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\NVIDIA\GLCache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\AMD\DxCache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\AMD\DxcCache' 0),
           (Nuovo-PercorsoPulizia '%LOCALAPPDATA%\Intel\ShaderCache' 0) )
       Descrizione = "Shader già compilati dei giochi. Va svuotata solo dopo un cambio di driver video o se un gioco ha difetti grafici: i giochi la ricreano, ma al primo avvio possono scattare. Per questo non è in nessun profilo." }

    # ---------------------------------------------------------------- MANUTENZIONE (strumenti ufficiali di Windows, su richiesta)
    @{ Id = 'man.sfc'; Nome = 'Controllo dei file di sistema (SFC)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\sfc.exe" '/scannow'
           Scrivi-Log "  SFC terminato con codice $codice (0 = nessun problema o problemi riparati). Dettagli: $env:WINDIR\Logs\CBS\CBS.log"
       }
       Descrizione = "Controlla che i file di Windows siano integri e ripara quelli danneggiati (comando 'sfc /scannow'). Dura 5-15 minuti. Utile dopo blocchi, errori strani o spegnimenti improvvisi." }

    @{ Id = 'man.dism'; Nome = 'Riparazione dell''immagine di Windows (DISM)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\Dism.exe" '/Online /Cleanup-Image /RestoreHealth'
           if ($codice -ne 0) { throw "DISM ha restituito il codice $codice (dettagli in $env:WINDIR\Logs\DISM\dism.log)." }
       }
       Descrizione = "Ripara l'archivio dei componenti di Windows scaricando da Windows Update le parti danneggiate. Serve Internet, dura 10-20 minuti. Se SFC non riesce a riparare, esegui prima questo e poi di nuovo SFC." }

    @{ Id = 'man.dns'; Nome = 'Svuota la cache DNS'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\ipconfig.exe" '/flushdns'
           if ($codice -ne 0) { throw "ipconfig /flushdns ha restituito il codice $codice." }
       }
       Descrizione = "Cancella gli indirizzi dei siti ricordati da Windows. Utile se un sito non si apre più o apre una versione vecchia. Nessun effetto collaterale." }

    @{ Id = 'man.dischi'; Nome = 'Ottimizza il disco di sistema (TRIM / deframmentazione)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\defrag.exe" "$env:SystemDrive /O"
           if ($codice -ne 0) { throw "defrag ha restituito il codice $codice." }
       }
       Descrizione = "Esegue l'ottimizzazione giusta per il tipo di disco, scelta da Windows: TRIM sugli SSD, deframmentazione sui dischi meccanici. È la stessa operazione di 'Ottimizza unità'." }

    # ---------------------------------------------------------------- MANUTENZIONE (aggiunte nella 3.7: solo strumenti ufficiali di Windows)
    @{ Id = 'man.salute'; Nome = 'Stato di salute dei dischi (SMART)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $dischi = @(Get-PhysicalDisk -ErrorAction Stop)
           if ($dischi.Count -eq 0) { throw 'Nessun disco trovato.' }
           foreach ($d in $dischi) {
               $liv = $(if ([string]$d.HealthStatus -eq 'Healthy') { 'OK' } else { 'AVVISO' })
               Scrivi-Log ("  {0} ({1}, {2:N0} GB): salute {3}, stato {4}" -f $d.FriendlyName, $d.MediaType, ($d.Size / 1GB), $d.HealthStatus, $d.OperationalStatus) $liv
           }
       }
       Descrizione = "Legge lo stato di salute che Windows riporta per ogni disco (sano, a rischio, guasto) e lo scrive nel registro attività. Non modifica niente. Se un disco non risulta 'Healthy' fai subito una copia dei dati importanti." }

    @{ Id = 'man.chkdsk'; Nome = 'Controllo degli errori del disco di sistema (sola lettura)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $cartella = Join-Path $Script:CartellaDati 'Report'
           if (-not (Test-Path -LiteralPath $cartella)) { New-Item -ItemType Directory -Path $cartella -Force | Out-Null }
           $file = Join-Path $cartella 'controllo_disco.txt'
           [void](Esegui-Processo "$env:WINDIR\System32\cmd.exe" "/c chkdsk $env:SystemDrive > `"$file`" 2>&1")
           if (Test-Path -LiteralPath $file) {
               $righe = @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue | Where-Object { $_.Trim() } | Select-Object -Last 6)
               foreach ($r in $righe) { Scrivi-Log "  $r" }
               Scrivi-Log "  Risultato completo: $file"
           }
       }
       Descrizione = "Esegue 'chkdsk' senza riparare niente: cerca soltanto errori nel file system e scrive il risultato in Dati\Report. Dura qualche minuto e non richiede il riavvio. Se trova problemi, la riparazione (chkdsk /f) va fatta a parte." }

    @{ Id = 'man.dismcheck'; Nome = 'Verifica veloce dell''immagine di Windows (DISM, sola lettura)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\Dism.exe" '/Online /Cleanup-Image /ScanHealth'
           if ($codice -ne 0) { throw "DISM ha restituito il codice $codice (dettagli in $env:WINDIR\Logs\DISM\dism.log)." }
           Scrivi-Log '  DISM: controllo terminato senza errori. Se SFC segnala problemi usa "Riparazione dell''immagine di Windows".' 'OK'
       }
       Descrizione = "Controlla se l'archivio dei componenti di Windows è danneggiato, senza riparare niente. Più veloce della riparazione completa: usalo per capire se serve." }

    @{ Id = 'man.batteria'; Nome = 'Report sulla batteria (solo portatili)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $cartella = Join-Path $Script:CartellaDati 'Report'
           if (-not (Test-Path -LiteralPath $cartella)) { New-Item -ItemType Directory -Path $cartella -Force | Out-Null }
           $file = Join-Path $cartella 'batteria.html'
           [void](Esegui-Processo "$env:WINDIR\System32\powercfg.exe" "/batteryreport /output `"$file`"")
           if (-not (Test-Path -LiteralPath $file)) { throw 'Windows non ha creato il report: probabilmente questo PC non ha una batteria.' }
           Scrivi-Log "  Report creato: $file (capacità di progetto, capacità attuale, cicli, uso recente)." 'OK'
           Start-Process -FilePath $file
       }
       Descrizione = "Crea e apre il report ufficiale di Windows sulla batteria: quanta capacità ha perso rispetto al nuovo, cicli di carica e uso degli ultimi giorni." }

    @{ Id = 'man.energia'; Nome = 'Report sui consumi e sulle impostazioni energetiche'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $cartella = Join-Path $Script:CartellaDati 'Report'
           if (-not (Test-Path -LiteralPath $cartella)) { New-Item -ItemType Directory -Path $cartella -Force | Out-Null }
           $file = Join-Path $cartella 'energia.html'
           [void](Esegui-Processo "$env:WINDIR\System32\powercfg.exe" "/energy /duration 20 /output `"$file`"")
           if (-not (Test-Path -LiteralPath $file)) { throw 'Windows non ha creato il report energetico.' }
           Scrivi-Log "  Report creato: $file" 'OK'
           Start-Process -FilePath $file
       }
       Descrizione = "Osserva il PC per 20 secondi (lascialo fermo) e crea un report con errori e avvisi su consumi, USB, risparmio energetico e driver che impediscono la sospensione. Non modifica niente." }

    @{ Id = 'man.store'; Nome = 'Reimposta la cache del Microsoft Store'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           [void](Esegui-Processo "$env:WINDIR\System32\wsreset.exe" '')
           Scrivi-Log '  Cache del Store reimpostata (il Store può aprirsi da solo alla fine).'
       }
       Descrizione = "Svuota la cache del Microsoft Store senza toccare app e account. Utile se il Store non si apre, non scarica o dà errori." }

    @{ Id = 'man.icone'; Nome = 'Aggiorna la cache delle icone'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\ie4uinit.exe" '-show'
           if ($codice -ne 0) { throw "ie4uinit ha restituito il codice $codice." }
       }
       Descrizione = "Fa ricaricare a Windows le icone di file e programmi: utile se compaiono icone bianche, sbagliate o vecchie. Non chiude Esplora file." }

    @{ Id = 'man.ora'; Nome = 'Sincronizza data e ora con Internet'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'basso'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\w32tm.exe" '/resync'
           if ($codice -ne 0) { throw "Sincronizzazione non riuscita (codice $codice): controlla che il servizio 'Ora di Windows' sia attivo e che ci sia Internet." }
       }
       Descrizione = "Allinea subito l'orologio del PC con il server orario di Windows. Un orologio sbagliato causa errori di certificato nei siti e negli accessi." }

    @{ Id = 'man.memoria'; Nome = 'Diagnostica della memoria RAM (richiede il riavvio)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'medio'; Profili = @(); SoloAzione = $true
       Azione = {
           Start-Process -FilePath "$env:WINDIR\System32\mdsched.exe"
           Scrivi-Log '  Aperto lo strumento di Windows: lì scegli se riavviare subito o al prossimo avvio. Il risultato compare dopo il riavvio come notifica.'
       }
       Descrizione = "Apre 'Diagnostica memoria di Windows'. Il test avviene al riavvio e può durare 10-20 minuti: salva il lavoro aperto prima di scegliere. Utile se hai blocchi o schermate blu." }

    @{ Id = 'man.winsock'; Nome = 'Reimposta la rete (Winsock)'; Categoria = 'Manutenzione'; Tipo = 'Pulizia'; Rischio = 'medio'; Profili = @(); SoloAzione = $true
       Azione = {
           $codice = Esegui-Processo "$env:WINDIR\System32\netsh.exe" 'winsock reset'
           if ($codice -ne 0) { throw "netsh winsock reset ha restituito il codice $codice." }
           Scrivi-Log '  Winsock reimpostato: riavvia il PC per completare.' 'AVVISO'
       }
       Descrizione = "Riporta a zero le impostazioni del catalogo di rete di Windows. Serve quando la rete è collegata ma i programmi non navigano (dopo virus, VPN o programmi di rete rimossi male). Richiede il riavvio; VPN e firewall di terze parti potrebbero doversi reinstallare o riconfigurare." }

    # ---------------------------------------------------------------- PULIZIA DEL REGISTRO (dalla 3.9)
    (Nuova-VocePuliziaRegistro 'reg.avvio' 'Programmi all''avvio che non esistono più' { Trova-AvvioOrfani } 'basso' $false `
        "Righe delle chiavi 'Run' che fanno partire all'accesso un file ormai cancellato (programmi disinstallati male): Windows prova ad aprirle ogni volta e fallisce. Si controllano solo percorsi completi su dischi interni presenti; chiavette e dischi scollegati non vengono mai giudicati. I valori tolti restano nel backup e 'Annulla tutto' li rimette.")

    (Nuova-VocePuliziaRegistro 'reg.apppaths' 'Comandi "Esegui" di programmi cancellati (App Paths)' { Trova-AppPathsOrfani } 'basso' $false `
        "Chiavi che permettono di avviare un programma scrivendone il nome in Esegui (Win+R) ma che puntano a un file che non c'è più. Prima di toglierla ogni chiave viene salvata in un file .reg in Dati\Backup; 'Annulla tutto' la rimette.")

    (Nuova-VocePuliziaRegistro 'reg.muicache' 'Nomi ricordati di programmi cancellati (MuiCache)' { Trova-MuiCacheOrfani } 'basso' $false `
        "Windows ricorda il nome di ogni programma aperto (per esempio per il menu 'Apri con'). Si tolgono solo i nomi dei programmi che non esistono più. È soltanto una cache: serve all'ordine, non alla velocità.")

    (Nuova-VocePuliziaRegistro 'reg.disinstalla' 'Programmi in "App installate" che non si possono più disinstallare' { Trova-DisinstallazioniRotte } 'medio' $true `
        "Righe dell'elenco delle app installate il cui programma di disinstallazione e la cui cartella non esistono più: restano nell'elenco ma danno errore se provi a toglierle. Esclusi i pacchetti Windows Installer (MSI), i componenti di sistema e le righe senza nome. Controlla i nomi nella colonna 'Attuale' prima di applicare. Ogni chiave viene salvata in un file .reg in Dati\Backup; 'Annulla tutto' la rimette.")
)

# Chiave usata da "Ottimizzazioni per giochi in finestra" (contiene più impostazioni in un'unica stringa).
$Script:ChiaveDirectX = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'

function Leggi-ImpostazioniDirectX {
    $l = Leggi-Registro $Script:ChiaveDirectX 'DirectXUserGlobalSettings'
    $mappa = [ordered]@{}
    if ($l.Esiste) {
        foreach ($parte in ([string]$l.Valore).Split(';')) {
            if ($parte -match '^\s*([^=]+)=(.*)$') { $mappa[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
    }
    return [pscustomobject]@{ Esiste = $l.Esiste; Testo = [string]$l.Valore; Mappa = $mappa }
}

function Scrivi-ImpostazioniDirectX($Mappa) {
    $parti = @(foreach ($k in @($Mappa.Keys)) { "$k=$($Mappa[$k])" })
    if ($parti.Count -gt 0) { Scrivi-Registro $Script:ChiaveDirectX 'DirectXUserGlobalSettings' (($parti -join ';') + ';') 'String' }
    else { Rimuovi-Registro $Script:ChiaveDirectX 'DirectXUserGlobalSettings' }
}

# ---------- Programmi all'avvio: riconoscimento ------------------------------------
# Parole che indicano componenti da lasciare attivi (driver, audio, sicurezza).
$Script:AvvioEssenziali = @('SecurityHealth', 'RtkAud', 'Realtek', 'Nahimic', 'Waves', 'igfx', 'IntelGraphics',
    'Synaptics', 'ELAN', 'Dolby', 'Bluetooth', 'Windows Defender', 'ctfmon', 'NVIDIA Broadcast')
# Programmi noti che non servono all'avvio (si possono aprire a mano).
$Script:AvvioNonEssenziali = @('Spotify', 'Discord', 'Steam', 'EpicGames', 'Teams', 'Skype', 'MicrosoftEdgeAutoLaunch',
    'Opera', 'CCleaner', 'uTorrent', 'qBittorrent', 'AdobeGCInvoker', 'iTunesHelper', 'Zoom', 'WhatsApp', 'Telegram')

# App che non vengono MAI rimosse, anche se finissero per errore nel catalogo.
$Script:AppProtette = @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
    'Microsoft.SecHealthUI', 'Microsoft.VCLibs*', 'Microsoft.NET.*', 'Microsoft.UI.Xaml*', 'Microsoft.WindowsAppRuntime*',
    'MicrosoftCorporationII.WinAppRuntime*', 'Microsoft.Services.Store.Engagement', 'NVIDIACorp.*', 'DolbyLaboratories.*',
    'RealtekSemiconductorCorp.*', 'AppUp.Intel*', '*VideoExtension*', '*ImageExtension*', 'Microsoft.WebMediaExtensions',
    'Microsoft.WindowsTerminal', 'Microsoft.WindowsCalculator', 'Microsoft.WindowsNotepad', 'Microsoft.XboxIdentityProvider',
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxGamingOverlay', 'Microsoft.AAD.BrokerPlugin', 'Microsoft.AccountsControl',
    'Microsoft.LanguageExperiencePack*', 'Microsoft.Winget.Source', 'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost', 'MicrosoftWindows.Client.*')

# ---------- Preparazione del catalogo ----------------------------------------------
# PROFILI (dalla 3.0). Nel catalogo ogni voce indica ancora i "gruppi base" Gaming, Produttivita, Design,
# Efficienza; da questi, con le regole qui sotto, nascono i sei profili mostrati nella finestra:
#   Massimo     tutto ciò che serve a migliorare il PC, anche voci a rischio medio (con avvertenze)
#   Gaming      migliori prestazioni nei giochi
#   Grafica     migliori prestazioni per grafica ed editing, senza toccare colori, HDR e app creative
#   Bilanciato  equilibrio per l'uso di tutti i giorni
#   Batteria    portatili: massima autonomia quando si usa la batteria
#   Sicuro      solo modifiche leggere e reversibili (privacy, Esplora file, file temporanei)
# Le voci avanzate non entrano mai in nessun profilo.
$Script:NomiProfili = [ordered]@{ Massimo = 'Massimo (con avvertenze)'; Gaming = 'Gaming'; Grafica = 'Grafica ed editing'; Bilanciato = 'Bilanciato'; Batteria = 'Portatile a batteria'; Sicuro = 'Sicuro' }
# Preset delle schede video abbinato a ogni profilo ($null = le impostazioni NVIDIA/AMD non vengono toccate)
$Script:PresetDeiProfili = @{ Massimo = 'Gaming'; Gaming = 'Gaming'; Grafica = 'Grafica'; Bilanciato = 'Produttivita'; Batteria = 'Batteria'; Sicuro = $null }
$Script:Voci = [ordered]@{}

function Calcola-Profili($V) {
    $base = @($V.Profili)
    if ($V.Avanzata) { return @() }
    $p = New-Object System.Collections.ArrayList
    if ($base -contains 'Gaming')       { [void]$p.Add('Gaming') }
    if ($base -contains 'Design')       { [void]$p.Add('Grafica') }
    if ($base -contains 'Produttivita') { [void]$p.Add('Bilanciato') }
    if ($base -contains 'Efficienza')   { [void]$p.Add('Batteria') }
    # Massimo: tutto il Gaming e il Bilanciato, più privacy, app e servizi di ogni gruppo (anche a rischio medio).
    # Per le voci alternative (piani energetici) vale la scelta del Gaming.
    $categorieLibere = @('Debloat app', 'Privacy', 'Servizi', 'Esplora file', 'Pulizia', 'Avvio')
    $massimo = $false
    if ($V.Gruppo) { $massimo = ($base -contains 'Gaming') }
    elseif ($base -contains 'Gaming' -or $base -contains 'Produttivita') { $massimo = $true }
    elseif ($base.Count -gt 0 -and $categorieLibere -contains $V.Categoria) { $massimo = $true }
    elseif ($V.Rischio -eq 'medio' -and @('Debloat app', 'Privacy', 'Servizi') -contains $V.Categoria -and -not $V.Manuale) { $massimo = $true }
    if ($massimo) { [void]$p.Add('Massimo') }
    # Sicuro: solo voci a rischio basso che non tolgono niente (niente app, servizi, piani energetici).
    $sicuro = ($base.Count -gt 0 -and $V.Rischio -eq 'basso' -and -not $V.Gruppo -and
               ((@('Privacy', 'Esplora file') -contains $V.Categoria -and @('Registro', 'Attivita') -contains $V.Tipo) -or
                ($V.Categoria -eq 'Pulizia' -and $V.Tipo -eq 'Pulizia')))
    if ($sicuro) { [void]$p.Add('Sicuro') }
    return @($p)
}

function Completa-Voce($V) {
    foreach ($campo in @('Avanzata', 'Profili', 'Riavvio', 'Gruppo')) {
        if (-not $V.ContainsKey($campo)) { $V[$campo] = $(switch ($campo) { 'Avanzata' { $false } 'Profili' { @() } default { '' } }) }
    }
    switch ($V.Tipo) {
        'Servizio' { $V.TestoConsigliato = Nome-Modo $V.Consigliato; $V.TestoPredefinito = Nome-Modo $V.Predefinito }
        'App'      { $V.TestoConsigliato = 'Rimossa'; $V.TestoPredefinito = 'Installata' }
        'Pulizia'  { $V.TestoConsigliato = $(if ($V.Categoria -eq 'Manutenzione') { 'Eseguire' } else { 'Pulire' }); $V.TestoPredefinito = '—' }
        'Attivita' { $V.TestoConsigliato = 'Disattivate'; $V.TestoPredefinito = 'Attive' }
        'NVIDIA'   {
            # Nomi leggibili dei valori (dalle scelte del menu a tendina); i preset sostituiscono i profili.
            $V.Etichette = @{}
            foreach ($o in $V.Opzioni) { $V.Etichette[[string][uint32]$o[0]] = [string]$o[1] }
            $V.IdNv = [uint32]$V.IdNv; $V.ValoreDriver = [uint32]$V.ValoreDriver
            $V.TestoConsigliato = 'Scelta dal menu'; $V.TestoPredefinito = 'Valore di serie del driver'
            $V.Profili = @()
        }
        'AMD'      {
            $V.Etichette = @{}
            foreach ($o in $V.Opzioni) { $V.Etichette[[string][int]$o[0]] = [string]$o[1] }
            $V.TestoConsigliato = 'Scelta dal menu'; $V.TestoPredefinito = 'Valore tipico di serie'
            $V.Profili = @()
        }
    }
    if ($V.Avanzata) { $V.Profili = @() }   # sicurezza: le voci avanzate non entrano mai nei profili
    $V.Profili = @(Calcola-Profili $V)
}

# ---------------------------------------------------------------- NVIDIA - OPZIONI AVANZATE
# Impostazioni che si cambiano con NVIDIA Profile Inspector (profilo globale), scritte con NVAPI come le altre.
# Codici e valori: elenco CustomSettingNames.xml di NVIDIA Profile Inspector (github.com/Orbmu2k/nvidiaProfileInspector,
# licenza MIT) e NvApiDriverSettings.h. Non fanno parte dei preset: si cambiano una per una (o "Predefinite del driver").
# Se il driver non ne conosce una, la riga non compare. Formato: Id, Nome, Area, Codice, Rischio, ValoreDriver (se il
# driver non lo comunica), Opzioni (valore, testo), Descrizione.
$pctNv  = @(0..20 | ForEach-Object { , @(($_ * 5), "$($_ * 5)%") })
$nitNv  = @(0..20 | ForEach-Object { , @(($_ * 5), ('{0:N2}' -f ($_ * 5 / 100.0))) })
$onOff  = @( @(0, 'Disattivato'), @(1, 'Attivato') )
$defNva = @(
  @('dlssover', 'DLSS Super Resolution: usa la versione più recente installata', 'DLSS e fotogrammi', '10E41E01', 'basso', 0, $onOff,
    "Sostituisce la libreria DLSS dei giochi con l'ultima versione presente nel driver (solo giochi con DLSS 2 o successivo; alcuni giochi non lo permettono). Può migliorare nitidezza e stabilità."),
  @('dlssfgover', 'DLSS Frame Generation: usa la versione più recente installata', 'DLSS e fotogrammi', '10E41E03', 'basso', 0, $onOff,
    "Come sopra, ma per la generazione di fotogrammi (DLSS-FG)."),
  @('dlssrrover', 'DLSS Ray Reconstruction: usa la versione più recente installata', 'DLSS e fotogrammi', '10E41E02', 'basso', 0, $onOff,
    "Come sopra, per la ricostruzione dei raggi (DLSS-RR) nei giochi con ray tracing."),
  @('dlssqual', 'DLSS: livello di qualità forzato', 'DLSS e fotogrammi', '10AFB768', 'medio', 3,
    @( @(3, 'Decide il gioco'), @(4, 'DLAA (massima qualità)'), @(2, 'Qualità'), @(1, 'Bilanciato'), @(0, 'Prestazioni'), @(5, 'Ultra prestazioni') ),
    "Obbliga tutti i giochi con DLSS a usare questo livello. 'Prestazioni' = più FPS, immagine meno definita. Alcuni giochi ignorano la scelta."),
  @('dlsspreset', 'DLSS Super Resolution: lettera del preset forzata (Forced preset letter)', 'DLSS e fotogrammi', '10E41DF3', 'medio', 0,
    @( @(0, 'Decide il gioco / driver'), @(16777215, 'Ultima disponibile (Latest)'), @(1, 'Preset A'), @(2, 'Preset B'), @(3, 'Preset C'), @(4, 'Preset D'),
       @(5, 'Preset E'), @(6, 'Preset F'), @(7, 'Preset G'), @(8, 'Preset H'), @(9, 'Preset I'), @(10, 'Preset J'), @(11, 'Preset K'),
       @(12, 'Preset L'), @(13, 'Preset M'), @(14, 'Preset N'), @(15, 'Preset O') ),
    "Obbliga il DLSS Super Resolution a usare un preset preciso (la 'lettera' con cui NVIDIA ha addestrato la rete). Ogni preset è un compromesso tra nitidezza, stabilità dell'immagine e fantasmi: di solito K, L, M o 'Ultima disponibile' sono i più recenti. Funziona solo nei giochi con DLSS 2 o successivo; se un gioco mostra difetti, torna a 'Decide il gioco / driver'."),
  @('mfgnum', 'DLSS Multi Frame Generation: numero fotogrammi fissato', 'DLSS e fotogrammi', '104D6667', 'medio', 0,
    @( @(0, 'Decide il gioco'), @(1, '2x'), @(2, '3x'), @(3, '4x'), @(4, '5x'), @(5, '6x') ),
    "Per schede RTX serie 50: forza il moltiplicatore di fotogrammi generati. Più fotogrammi mostrati, ma anche più latenza."),
  @('smooth', 'Smooth Motion (fluidità a livello di driver)', 'DLSS e fotogrammi', 'B0D384C0', 'basso', 0, $onOff,
    "Genera fotogrammi intermedi nei giochi che non supportano il DLSS Frame Generation. Per schede RTX serie 40 e 50."),
  @('vibr', 'RTX Dynamic Vibrance', 'Rendering', '00980880', 'basso', 0, $onOff,
    "Aumenta la vivacità dei colori nei giochi. Si regola con 'intensità' e 'aumento saturazione' qui sotto."),
  @('vibrint', 'RTX Dynamic Vibrance: intensità', 'Rendering', '00ABAB22', 'basso', 0, $pctNv, "Quanto è forte l'effetto di Dynamic Vibrance."),
  @('vibrsat', 'RTX Dynamic Vibrance: aumento della saturazione', 'Rendering', '00ABAB13', 'basso', 0, $pctNv, "Quanta saturazione in più aggiunge Dynamic Vibrance."),
  @('dxr', 'Ray tracing DirectX (DXR)', 'Rendering', '00DE429A', 'medio', 1, @( @(1, 'Predefinito'), @(0, 'Disattivato') ),
    "Disattivando il ray tracing i giochi che lo usano girano molto più veloci ma senza quegli effetti. Funziona solo se il gioco lo permette."),
  @('vkrt', 'Ray tracing Vulkan', 'Rendering', '20BC1A2B', 'medio', 1, @( @(1, 'Predefinito'), @(0, 'Disattivato') ),
    "Come sopra, per i giochi Vulkan."),
  @('ansel', 'NVIDIA Ansel (foto in gioco)', 'Rendering', '1075D972', 'basso', 1, $onOff, "Strumento per scattare foto speciali nei giochi compatibili. Spegnerlo libera un po' di risorse."),
  @('ao', 'Occlusione ambientale (ambient occlusion)', 'Rendering', '00667329', 'basso', 0,
    @( @(0, 'Disattivata'), @(1, 'Prestazioni'), @(2, 'Qualità') ), "Ombre più realistiche negli angoli, solo nei giochi compatibili. 'Qualità' costa più FPS."),
  @('ull', 'Modalità bassa latenza (come nel Pannello NVIDIA)', 'Sincronizzazione e latenza', '0005F543', 'basso', 0,
    @( @(0, 'Disattivata'), @(1, 'Attivata'), @(2, 'Ultra') ), "'Ultra' invia i fotogrammi alla GPU appena in tempo: meno ritardo nei giochi senza NVIDIA Reflex."),
  @('sharp', 'Nitidezza dell''immagine (filtro del driver)', 'Nitidezza e antialiasing', '00598928', 'basso', 0, $onOff,
    "Attiva il filtro di nitidezza del driver, valido per tutti i giochi. L'intensità si sceglie nella riga sotto."),
  @('sharpval', 'Nitidezza: intensità', 'Nitidezza e antialiasing', '002ED8CD', 'basso', 50, $nitNv, "Da 0,00 (niente) a 1,00 (massima). Valori oltre 0,6 danno spesso un effetto artificiale."),
  @('aasuper', 'Antialiasing: supercampionamento della trasparenza', 'Nitidezza e antialiasing', '10D48A85', 'medio', 0,
    @( @(0, 'Disattivato (multicampionamento)'), @(20, '2x'), @(36, '4x'), @(52, '8x'), @(35, 'Supercampionamento'), @(24, '2x a griglia sparsa'), @(40, '4x a griglia sparsa'), @(56, '8x a griglia sparsa') ),
    "Leviga bordi di foglie, recinzioni e vetri. Livelli alti costano molti FPS."),
  @('sosttex', 'Filtro texture: sostituzione della qualità', 'Filtro texture', '00CE2692', 'basso', 0,
    @( @(0, 'Nessuna sostituzione'), @(1, 'Alta qualità diventa qualità') ), "Se attiva, usa un filtro più leggero al posto di quello di alta qualità: più FPS, texture un po' meno pulite."),
  @('noaniso', 'Filtro texture: impedisci il filtro anisotropico', 'Filtro texture', '103BCCB5', 'medio', 0, $onOff,
    "Blocca il filtro anisotropico (texture nitide in lontananza) anche se il gioco lo chiede. Lascialo disattivato salvo prove di compatibilità."),
  @('lodauto', 'Filtro texture: regola il LOD bias in automatico', 'Filtro texture', '00638E8F', 'basso', 0, $onOff,
    "Compensa il LOD bias quando si usa il supercampionamento (SGSSAA). Serve solo agli appassionati di antialiasing."),
  @('rebar', 'Resizable BAR (accesso completo alla memoria video)', 'Sistema, memoria e calcolo', '000BFA21', 'medio', 1,
    @( @(0, 'Disattivato'), @(1, 'Automatico'), @(2, 'Attivato') ), "Permette alla CPU di usare tutta la memoria video. Serve anche l'opzione attiva nel BIOS. Il driver ha già un elenco di giochi dove conviene."),
  @('p2', 'CUDA: forza lo stato P2', 'Sistema, memoria e calcolo', '50166C5E', 'medio', 1, $onOff,
    "Quando attivo la GPU, nei calcoli CUDA, non sale alle frequenze massime (stato P2). Disattivarlo può dare più prestazioni nei programmi di calcolo e rendering, con più consumo."),
  @('sysmem', 'CUDA: uso della memoria di sistema quando finisce la VRAM', 'Sistema, memoria e calcolo', '10ECECC9', 'medio', 0,
    @( @(0, 'Predefinito'), @(1, 'Preferisci niente memoria di sistema'), @(2, 'Preferisci la memoria di sistema') ),
    "Se la memoria video finisce, il driver può appoggiarsi alla RAM (più lento ma senza errori). 'Preferisci niente' evita i rallentamenti, ma i programmi possono chiudersi con un errore."),
  @('multidisp', 'Prestazioni con più schermi o più GPU', 'Sistema, memoria e calcolo', '200AEBFC', 'medio', 0,
    @( @(0, 'Prestazioni con un solo schermo'), @(1, 'Compatibilità'), @(3, 'Prestazioni con più schermi') ), "Scelta del comportamento della GPU quando ci sono più monitor."),
  @('precomp', 'Precompilazione automatica degli shader', 'Sistema, memoria e calcolo', '00EAD189', 'basso', 0,
    @( @(0, 'Disattivata'), @(1, 'Bassa'), @(2, 'Media'), @(3, 'Alta') ), "Quando il PC è inattivo la CPU compila in anticipo gli shader dei giochi: meno scatti al primo avvio, ma più lavoro in background."),
  @('shaderogl', 'Cache degli shader OpenGL', 'Sistema, memoria e calcolo', '208F3F2E', 'basso', 1, $onOff, "Conserva gli shader OpenGL già compilati: meno scatti alle riaperture."),
  @('physx32', 'PhysX a 32 bit su GPU (schede RTX serie 50)', 'Sistema, memoria e calcolo', '5067ECC4', 'basso', 0, $onOff,
    "Le RTX serie 50 non accelerano più il PhysX a 32 bit dei vecchi giochi (es. Borderlands 2, Mirror's Edge): con questa voce attiva si prova a riabilitarlo. Funziona solo se il driver lo supporta."),
  @('extlimit', 'OpenGL: limita le estensioni', 'Sistema, memoria e calcolo', '20FF7493', 'basso', 0, $onOff, "Per vecchi programmi OpenGL che si bloccano con troppe estensioni.")
)
foreach ($d in $defNva) {
    $Script:Catalogo += , @{ Id = "nva.$($d[0])"; Nome = $d[1]; Categoria = 'NVIDIAAvanz'; Tipo = 'NVIDIA'; Area = $d[2]; Rischio = $d[4]
        IdNv = (Nv-Hex $d[3]); ValoreDriver = $d[5]; Opzioni = $d[6]; Preset = @{}; Descrizione = $d[7] }
}

foreach ($v in $Script:Catalogo) {
    if ($Script:Voci.Contains($v.Id)) { throw "Id duplicato nel catalogo: $($v.Id)" }
    if ($Script:VociInLatenza -contains $v.Id) { $v.Categoria = 'Latenza'; $v.Avanzata = $false }
    Completa-Voce $v
    $Script:Voci[$v.Id] = $v
}

# ==============================================================================
# 5. MOTORI: LETTURA, APPLICAZIONE E RIPRISTINO PER OGNI TIPO DI VOCE
# ==============================================================================

# Risultato di una lettura.
#   Esito: 'A posto' | 'Da modificare' | 'Da pulire' | 'Info' | 'Errore' | 'Non presente'
#   EPredefinito: la voce è già al valore predefinito di Windows
function Nuova-Lettura([string]$Attuale, [string]$Esito, [bool]$Presente = $true, [bool]$EPredefinito = $false, [int64]$Byte = 0) {
    return [pscustomobject]@{ Attuale = $Attuale; Esito = $Esito; Presente = $Presente; EPredefinito = $EPredefinito; Byte = $Byte }
}

# ---------- Registro ----------
function Leggi-VoceRegistro($Voce) {
    # Voce che riguarda un'app (es. Widget): se l'app non è installata non c'è niente da disattivare.
    if ($Voce.SoloSeApp) {
        $elenco = $(if ($null -ne $Script:CacheAppx) { $Script:CacheAppx } else { @(Get-AppxPackage -ErrorAction SilentlyContinue) })
        if (@($elenco | Where-Object { $_.Name -like $Voce.SoloSeApp }).Count -eq 0) { return Nuova-Lettura 'App non installata' 'A posto' $true $true }
    }
    $tot = @($Voce.Valori).Count; $nOk = 0; $nPred = 0; $ultimo = $null
    foreach ($v in $Voce.Valori) {
        $l = Leggi-Registro $v.Percorso $v.Nome
        $att = $(if ($l.Esiste) { $l.Valore } else { $null })
        $ultimo = $att
        if ($null -eq $att -and $v.AssenteOk) { $att = $v.Consigliato }
        if (Confronta-Valori $att $v.Consigliato) { $nOk++ }
        if (Confronta-Valori $att $v.Predefinito) { $nPred++ }
    }
    if ($nOk -eq $tot)   { return Nuova-Lettura $Voce.TestoConsigliato 'A posto' $true ($nPred -eq $tot) }
    if ($nPred -eq $tot) { return Nuova-Lettura $Voce.TestoPredefinito 'Da modificare' $true $true }
    if ($tot -eq 1) {
        if ($null -eq $ultimo) { $t = '(non impostato)' }
        elseif ($Voce.Etichette -and $Voce.Etichette.ContainsKey("$ultimo")) { $t = $Voce.Etichette["$ultimo"] }
        else { $t = "valore $ultimo" }
        return Nuova-Lettura $t 'Da modificare'
    }
    return Nuova-Lettura ('Misto ({0} di {1} come consigliato)' -f $nOk, $tot) 'Da modificare'
}

function Originale-Registro($Voce) {
    $valori = @(foreach ($v in $Voce.Valori) {
        $l = Leggi-Registro $v.Percorso $v.Nome
        @{ Percorso = $v.Percorso; Nome = $v.Nome; Esiste = $l.Esiste; Valore = (Valore-PerJson $l.Valore); Tipo = $(if ($l.Esiste) { $l.Tipo } else { $v.Tipo }) }
    })
    return @{ Valori = $valori }
}

function Applica-Registro($Voce, [string]$Obiettivo) {
    foreach ($v in $Voce.Valori) {
        # 'Valore:N' = valore scelto nel menu a tendina (solo voci con un unico valore e con etichette)
        if ($Obiettivo -like 'Valore:*') {
            $t = $Obiettivo.Substring(7)
            $nuovo = $(if ($t -eq '') { $null } elseif ($v.Tipo -eq 'DWord') { [int]$t } elseif ($v.Tipo -eq 'QWord') { [int64]$t } else { $t })
        }
        else { $nuovo = $(if ($Obiettivo -eq 'Predefinito') { $v.Predefinito } else { $v.Consigliato }) }
        if ($null -eq $nuovo) { Rimuovi-Registro $v.Percorso $v.Nome } else { Scrivi-Registro $v.Percorso $v.Nome $nuovo $v.Tipo }
    }
}

function Ripristina-Registro($O) {
    foreach ($v in @($O.Valori)) {
        if ($v.Esiste) { Scrivi-Registro $v.Percorso $v.Nome $v.Valore $v.Tipo } else { Rimuovi-Registro $v.Percorso $v.Nome }
    }
}

# ---------- Servizi ----------
function Stati-Servizi($Voce) {
    return @(@(foreach ($n in $Voce.Servizi) { Leggi-AvvioServizio $n }) | Where-Object { $null -ne $_ })
}

function Leggi-VoceServizio($Voce) {
    # @(...) obbligatorio: in PowerShell 5.1 un solo risultato perde il conteggio (.Count)
    $stati = @(Stati-Servizi $Voce)
    if ($stati.Count -eq 0) { return Nuova-Lettura 'Non presente' 'Non presente' $false }
    $modi = @($stati | ForEach-Object { $_.Modo } | Select-Object -Unique)
    if ($modi.Count -eq 1) { $testo = Nome-Modo $modi[0] }
    else { $testo = 'Misto: ' + (($stati | ForEach-Object { "$($_.Nome) $(Nome-Modo $_.Modo)" }) -join ', ') }
    $inEsec = @($stati | Where-Object { $_.InEsecuzione }).Count
    if ($inEsec -gt 0) { $testo += $(if ($stati.Count -eq 1) { ' · in esecuzione' } else { " · $inEsec in esecuzione" }) }
    $ok   = @($stati | Where-Object { $_.Modo -ne $Voce.Consigliato }).Count -eq 0
    $pred = @($stati | Where-Object { $_.Modo -ne $Voce.Predefinito }).Count -eq 0
    return Nuova-Lettura $testo $(if ($ok) { 'A posto' } else { 'Da modificare' }) $true $pred
}

function Originale-Servizio($Voce) {
    $servizi = @(Stati-Servizi $Voce | Where-Object { $_.Modo -ne 'Sistema' } | ForEach-Object { @{ Nome = $_.Nome; Modo = $_.Modo; InEsecuzione = $_.InEsecuzione } })
    return @{ Servizi = $servizi }
}

function Applica-Servizio($Voce, [string]$Obiettivo) {
    $modo = $(if ($Obiettivo -eq 'Predefinito') { $Voce.Predefinito } elseif ($Obiettivo -like 'Modo:*') { $Obiettivo.Substring(5) } else { $Voce.Consigliato })
    if (@('Automatico', 'AutomaticoRitardato', 'Manuale', 'Disattivato') -notcontains $modo) { throw "Modo di avvio non valido: $modo" }
    foreach ($s in @(Stati-Servizi $Voce)) {
        if ($s.Modo -eq 'Sistema') { continue }
        Imposta-AvvioServizio $s.Nome $modo
        if ($modo -eq 'Disattivato' -and $s.InEsecuzione) { Stop-Service -Name $s.Nome -Force -ErrorAction SilentlyContinue }
        if ($modo -like 'Automatico*' -and -not $s.InEsecuzione) { Start-Service -Name $s.Nome -ErrorAction SilentlyContinue }
    }
}

function Ripristina-Servizio($O) {
    foreach ($s in @($O.Servizi)) {
        Imposta-AvvioServizio $s.Nome $s.Modo
        if ($s.InEsecuzione) { Start-Service -Name $s.Nome -ErrorAction SilentlyContinue }
        elseif ($s.Modo -eq 'Disattivato') { Stop-Service -Name $s.Nome -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- App (Appx) ----------
$Script:CacheAppx = $null   # elenco pacchetti letto una volta per scansione (più veloce)

function E-AppProtetta($Pacchetto) {
    if ($Pacchetto.IsFramework -or "$($Pacchetto.SignatureKind)" -eq 'System') { return $true }
    foreach ($m in $Script:AppProtette) { if ($Pacchetto.Name -like $m) { return $true } }
    return $false
}

function Trova-Pacchetti($Voce) {
    $tutti = $(if ($null -ne $Script:CacheAppx) { $Script:CacheAppx } else { @(Get-AppxPackage -ErrorAction SilentlyContinue) })
    return @($tutti | Where-Object { ($Voce.Pacchetti -contains $_.Name) -and -not (E-AppProtetta $_) })
}

function Leggi-VoceApp($Voce) {
    $p = @(Trova-Pacchetti $Voce)
    if ($p.Count -eq 0) { return Nuova-Lettura 'Non installata' 'Non presente' $false }
    $testo = $(if ($p.Count -eq 1) { 'Installata' } else { "Installata ($($p.Count) app)" })
    return Nuova-Lettura $testo 'Da modificare' $true $true
}

function Originale-App($Voce) {
    $pacchetti = @(Trova-Pacchetti $Voce | ForEach-Object {
        @{ Nome = $_.Name; NomeCompleto = $_.PackageFullName; Famiglia = $_.PackageFamilyName; Percorso = $_.InstallLocation } })
    return @{ Pacchetti = $pacchetti }
}

function Applica-App($Voce, [string]$Obiettivo) {
    if ($Obiettivo -eq 'Predefinito') { throw "Per reinstallare un'app usa 'Annulla tutto' oppure il Microsoft Store." }
    foreach ($p in (Trova-Pacchetti $Voce)) {
        if (E-AppProtetta $p) { throw "L'app $($p.Name) è protetta e non viene rimossa." }
        Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
        Scrivi-Log "  rimossa: $($p.Name)"
    }
}

function Ripristina-App($O) {
    foreach ($p in @($O.Pacchetti)) {
        $manifesto = $(if ($p.Percorso) { Join-Path $p.Percorso 'AppxManifest.xml' } else { '' })
        if ($manifesto -and (Test-Path -LiteralPath $manifesto)) {
            Add-AppxPackage -DisableDevelopmentMode -Register $manifesto -ErrorAction Stop
            Scrivi-Log "  reinstallata: $($p.Nome)" 'OK'
        } else {
            Start-Process "ms-windows-store://pdp/?PFN=$($p.Famiglia)"
            Scrivi-Log "  $($p.Nome): file non più presenti, aperta la pagina nel Microsoft Store per reinstallarla." 'AVVISO'
        }
    }
}

# ---------- Programmi all'avvio ----------
# Stesso metodo di Gestione attività: un valore "StartupApproved" (02 = attivo, 03 = disattivato).
function Nuova-VoceAvvio([string]$Nome, [string]$Comando, [string]$Approvato, [string]$Dove) {
    $testo = "$Nome $Comando"
    $rischio = 'medio'; $consigliato = 'Disattivato'; $profili = @()
    $nota = "Programma non riconosciuto: disattivalo solo se sai cos'è. Puoi sempre riattivarlo."
    foreach ($m in $Script:AvvioEssenziali) {
        if ($testo -like "*$m*") { $rischio = 'alto'; $consigliato = 'Attivo'; $nota = 'Sembra un componente di driver, audio o sicurezza: è consigliato lasciarlo attivo.'; break }
    }
    if ($rischio -eq 'medio') {
        foreach ($m in $Script:AvvioNonEssenziali) {
            if ($testo -like "*$m*") { $rischio = 'basso'; $profili = @('Gaming', 'Produttivita', 'Efficienza'); $nota = "Programma che non serve all'avvio: puoi aprirlo a mano quando ti serve."; break }
        }
    }
    $v = @{
        Id = "avvio|$Approvato|$Nome"; Nome = $Nome; Categoria = 'Avvio'; Tipo = 'Avvio'; Rischio = $rischio; Profili = $profili
        Descrizione = "$nota`nComando: $Comando`nOrigine: $Dove"
        TestoConsigliato = $consigliato; TestoPredefinito = 'Attivo'; ConsigliatoStato = $consigliato
        Approvato = $Approvato; NomeValore = $Nome
    }
    Completa-Voce $v
    return $v
}

function Trova-VociAvvio {
    $base = 'Software\Microsoft\Windows\CurrentVersion'
    $fonti = @(
        @{ Run = "HKCU:\$base\Run"; Approvato = "HKCU:\$base\Explorer\StartupApproved\Run"; Dove = 'Registro, solo il tuo utente' },
        @{ Run = "HKLM:\$base\Run"; Approvato = "HKLM:\$base\Explorer\StartupApproved\Run"; Dove = 'Registro, tutti gli utenti' },
        @{ Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Approvato = "HKLM:\$base\Explorer\StartupApproved\Run32"; Dove = 'Registro, tutti gli utenti (32 bit)' }
    )
    foreach ($f in $fonti) {
        if (-not (Test-Path -LiteralPath $f.Run)) { continue }
        $k = Get-Item -LiteralPath $f.Run
        foreach ($n in $k.GetValueNames()) {
            if ([string]::IsNullOrEmpty($n)) { continue }
            Nuova-VoceAvvio $n ([string]$k.GetValue($n)) $f.Approvato $f.Dove
        }
    }
    $cartelle = @(
        @{ Cartella = [Environment]::GetFolderPath('Startup'); Approvato = "HKCU:\$base\Explorer\StartupApproved\StartupFolder"; Dove = 'Cartella Esecuzione automatica (tuo utente)' },
        @{ Cartella = [Environment]::GetFolderPath('CommonStartup'); Approvato = "HKLM:\$base\Explorer\StartupApproved\StartupFolder"; Dove = 'Cartella Esecuzione automatica (tutti gli utenti)' }
    )
    foreach ($c in $cartelle) {
        foreach ($file in (Elenca-File $c.Cartella '*' $false)) {
            if ($file.Name -eq 'desktop.ini') { continue }
            Nuova-VoceAvvio $file.Name $file.FullName $c.Approvato $c.Dove
        }
    }
}

function Avvio-Attivo($Voce) {
    $l = Leggi-Registro $Voce.Approvato $Voce.NomeValore
    if (-not $l.Esiste) { return $true }
    $b = @($l.Valore)
    return -not ($b.Count -gt 0 -and (([int]$b[0]) -band 1))
}

function Leggi-VoceAvvio($Voce) {
    $attivo = Avvio-Attivo $Voce
    $ok = $(if ($Voce.ConsigliatoStato -eq 'Attivo') { $attivo } else { -not $attivo })
    # Un programma già disattivato non è mai "da modificare": se sarebbe meglio lasciarlo attivo è solo un suggerimento (Info).
    $esito = $(if ($ok) { 'A posto' } elseif (-not $attivo) { 'Info' } else { 'Da modificare' })
    return Nuova-Lettura $(if ($attivo) { 'Attivo' } elseif (-not $ok) { 'Disattivato (meglio attivo)' } else { 'Disattivato' }) $esito $true $attivo
}

function Originale-Avvio($Voce) {
    $l = Leggi-Registro $Voce.Approvato $Voce.NomeValore
    return @{ Approvato = $Voce.Approvato; NomeValore = $Voce.NomeValore; Esiste = $l.Esiste; Valore = (Valore-PerJson $l.Valore); Tipo = $(if ($l.Esiste) { $l.Tipo } else { 'Binary' }) }
}

function Applica-Avvio($Voce, [string]$Obiettivo) {
    $stato = $(if ($Obiettivo -eq 'Predefinito') { 'Attivo' } else { $Voce.ConsigliatoStato })
    $b = New-Object byte[] 12
    if ($stato -eq 'Disattivato') {
        $b[0] = 3
        [Array]::Copy([BitConverter]::GetBytes((Get-Date).ToFileTime()), 0, $b, 4, 8)
    } else { $b[0] = 2 }
    Scrivi-Registro $Voce.Approvato $Voce.NomeValore $b 'Binary'
}

function Ripristina-Avvio($O) {
    if ($O.Esiste) { Scrivi-Registro $O.Approvato $O.NomeValore $O.Valore $O.Tipo } else { Rimuovi-Registro $O.Approvato $O.NomeValore }
}

# ---------- Pulizia (non annullabile) ----------
function Leggi-VocePulizia($Voce) {
    if ($Voce.SoloAzione) { return Nuova-Lettura $(if ($Voce.Categoria -eq 'Manutenzione') { 'Su richiesta' } else { 'Non misurabile in anticipo' }) 'Info' }
    if ($Voce.Misura) { $m = & $Voce.Misura }
    else {
        $m = @{ Byte = [int64]0; File = 0 }
        foreach ($p in $Voce.Percorsi) { $x = Misura-Percorso $p; $m.Byte += $x.Byte; $m.File += $x.File }
    }
    $testo = '{0} ({1} file)' -f (Formatta-Dimensione $m.Byte), $m.File
    return Nuova-Lettura $testo $(if ($m.Byte -ge 1MB) { 'Da pulire' } else { 'A posto' }) $true $false $m.Byte
}

function Applica-Pulizia($Voce, [string]$Obiettivo) {
    if ($Obiettivo -eq 'Predefinito') { return }
    $stato = $null
    if ($Voce.Prima) { $stato = & $Voce.Prima }
    try {
        if ($Voce.Azione) { & $Voce.Azione; return }
        $tot = @{ Byte = [int64]0; File = 0; Saltati = 0 }
        foreach ($p in $Voce.Percorsi) { $x = Pulisci-Percorso $p; $tot.Byte += $x.Byte; $tot.File += $x.File; $tot.Saltati += $x.Saltati }
        Scrivi-Log ('  liberati {0} ({1} file eliminati, {2} in uso saltati)' -f (Formatta-Dimensione $tot.Byte), $tot.File, $tot.Saltati)
    } finally {
        if ($Voce.Dopo) { & $Voce.Dopo $stato }
    }
}

# ---------- Attività pianificate ----------
function Trova-Attivita($Voce) {
    foreach ($t in $Voce.Attivita) {
        $i = $t.LastIndexOf('\')
        Get-ScheduledTask -TaskPath $t.Substring(0, $i + 1) -TaskName $t.Substring($i + 1) -ErrorAction SilentlyContinue
    }
}

function Leggi-VoceAttivita($Voce) {
    $a = @(Trova-Attivita $Voce)
    if ($a.Count -eq 0) { return Nuova-Lettura 'Non presente' 'Non presente' $false }
    $attive = @($a | Where-Object { "$($_.State)" -ne 'Disabled' }).Count
    if ($attive -eq 0) { return Nuova-Lettura $(if ($a.Count -eq 1) { 'Disattivata' } else { "Disattivate ($($a.Count))" }) 'A posto' $true $false }
    $testo = $(if ($a.Count -eq 1) { 'Attiva' } else { "Attive: $attive di $($a.Count)" })
    return Nuova-Lettura $testo 'Da modificare' $true ($attive -eq $a.Count)
}

function Originale-Attivita($Voce) {
    $lista = @(Trova-Attivita $Voce | ForEach-Object { @{ Percorso = [string]$_.TaskPath; Nome = [string]$_.TaskName; Attiva = ("$($_.State)" -ne 'Disabled') } })
    return @{ Attivita = $lista }
}

function Imposta-Attivita([string]$Percorso, [string]$Nome, [bool]$Attiva) {
    if ($Attiva) { Enable-ScheduledTask -TaskPath $Percorso -TaskName $Nome -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskPath $Percorso -TaskName $Nome -ErrorAction Stop | Out-Null }
}

function Applica-Attivita($Voce, [string]$Obiettivo) {
    foreach ($t in @(Trova-Attivita $Voce)) { Imposta-Attivita ([string]$t.TaskPath) ([string]$t.TaskName) ($Obiettivo -eq 'Predefinito') }
}

function Ripristina-Attivita($O) {
    foreach ($t in @($O.Attivita)) { Imposta-Attivita ([string]$t.Percorso) ([string]$t.Nome) ([bool]$t.Attiva) }
}

# ---------- Impostazioni NVIDIA ----------
function Nvidia-Disponibile {
    return [bool](('OttWin.NvDrs' -as [type]) -and [OttWin.NvDrs]::Disponibile())
}

# Stato di un'impostazione nel profilo globale.
#   Posizione (NVDRS_SETTING_LOCATION): 0 = profilo corrente, 1 = globale (cioè impostato qui),
#   2 = profilo base, 3 = valori di serie (cioè ereditato dal driver).
#   NelProfilo  = il valore è scritto nel profilo globale e non è quello di serie.
#   Predefinito = valore di serie comunicato dal driver (se non lo comunica: quello del catalogo).
function Leggi-StatoNvidia($Voce) {
    $valore = [uint32]0; $posizione = 0; $predef = $false; $serie = [uint32]0; $serieValida = $false
    $codice = [OttWin.NvDrs]::Leggi([uint32]$Voce.IdNv, [ref]$valore, [ref]$posizione, [ref]$predef, [ref]$serie, [ref]$serieValida)
    $predefinito = $(if ($codice -eq 0 -and $serieValida) { [uint32]$serie } else { [uint32]$Voce.ValoreDriver })
    if ($codice -eq 0) {
        $nel = ($posizione -le 1) -and (-not $predef)
        return [pscustomobject]@{ Impostata = $true; Valore = [uint32]$valore; Posizione = $posizione; NelProfilo = $nel; Predefinito = $predefinito }
    }
    if ($codice -eq [OttWin.NvDrs]::NON_TROVATA) {
        return [pscustomobject]@{ Impostata = $false; Valore = $predefinito; Posizione = -1; NelProfilo = $false; Predefinito = $predefinito }
    }
    throw "NVAPI ha restituito il codice $codice leggendo '$($Voce.Nome)'."
}

function Testo-Nvidia($Voce, $Valore) {
    $k = [string][uint32]$Valore
    if ($Voce.Etichette -and $Voce.Etichette.ContainsKey($k)) { return $Voce.Etichette[$k] }
    return "valore $k"
}

function Leggi-VoceNvidia($Voce) {
    if (-not (Nvidia-Disponibile)) { return Nuova-Lettura 'NVIDIA non disponibile' 'Non presente' $false }
    $s = Leggi-StatoNvidia $Voce
    $pred = (-not $s.NelProfilo) -or ([uint32]$s.Valore -eq [uint32]$s.Predefinito)
    $l = Nuova-Lettura (Testo-Nvidia $Voce $s.Valore) $(if ($pred) { 'Predefinito' } else { 'Personalizzato' }) $true $pred
    $l | Add-Member -NotePropertyName Valore -NotePropertyValue ([uint32]$s.Valore)
    $l | Add-Member -NotePropertyName ValorePredefinito -NotePropertyValue ([uint32]$s.Predefinito)
    return $l
}

# Scelte del menu a tendina di una riga: quelle del catalogo, più il valore attuale se non è in elenco.
function Opzioni-Nvidia($Voce, [uint32]$Attuale, [uint32]$Predefinito) {
    $lista = New-Object 'System.Collections.Generic.List[OttWin.OpzioneVoce]'
    $presente = $false
    foreach ($o in $Voce.Opzioni) {
        $val = [uint32]$o[0]
        $op = New-Object OttWin.OpzioneVoce
        $op.Valore = [string]$val
        $op.Testo = [string]$o[1] + $(if ($val -eq $Predefinito) { '  (di serie)' } else { '' })
        $lista.Add($op)
        if ($val -eq $Attuale) { $presente = $true }
    }
    foreach ($extra in @($Attuale, $Predefinito)) {
        if (-not ($lista | Where-Object { $_.Valore -eq [string]$extra })) {
            $op = New-Object OttWin.OpzioneVoce
            $op.Valore = [string]$extra
            $op.Testo = "valore $extra" + $(if ($extra -eq $Predefinito) { '  (di serie)' } else { '' })
            $lista.Add($op)
        }
    }
    return , $lista
}

# PRESET DELLE SCHEDE VIDEO: sceglie nei menu a tendina i valori del preset (non applica niente: serve "Anteprima e applica").
#   'Gaming' | 'Grafica' | 'Produttivita' | 'Batteria' | 'Predefinito' (valori di serie) | 'Attuale' (annulla le scelte)
#   $Solo = 'NVIDIA' o 'AMD' per un solo produttore; vuoto = tutti e due.
function Applica-PresetNvidia([string]$Preset, [switch]$Silenzioso, [string]$Solo = '', [string]$Categoria = '') {
    $n = 0; $tot = 0
    foreach ($r in $Script:TutteLeRighe) {
        $v = $Script:Voci[$r.Id]
        if (-not $v -or @('NVIDIA', 'AMD') -notcontains $v.Tipo -or -not $r.Opzioni) { continue }
        if ($Solo -and $v.Tipo -ne $Solo) { continue }
        if ($Categoria -and $v.Categoria -ne $Categoria) { continue }
        # Le opzioni avanzate non fanno parte dei preset Prestazioni/Bilanciato/Qualità: solo "Predefinite" e "Annulla scelte" le toccano.
        if ($v.Categoria -eq 'NVIDIAAvanz' -and @('Predefinito', 'Attuale') -notcontains $Preset) { continue }
        $tot++
        $attuale = [int64]$r.ValoreAttuale
        $predef = $(if ([string]$r.ValorePredefinito -ne '') { [int64]$r.ValorePredefinito } else { $null })
        switch ($Preset) {
            'Attuale'     { $bersaglio = $attuale }
            'Predefinito' { $bersaglio = $(if ($null -ne $predef) { $predef } else { $attuale }) }
            default {
                $chiave = $Preset
                if (-not $v.Preset.ContainsKey($chiave) -and $chiave -eq 'Batteria') { $chiave = 'Produttivita' }
                $p = $v.Preset[$chiave]
                $bersaglio = $(if ($null -ne $p) { [int64]$p } elseif ($null -ne $predef) { $predef } else { $attuale })
                if ($v.PresetAlmeno -and $attuale -ge $bersaglio) { $bersaglio = $attuale }
            }
        }
        $op = $r.Opzioni | Where-Object { $_.Valore -eq [string]$bersaglio } | Select-Object -First 1
        if ($op) { $r.Scelta = $op }
        if ($r.Selezionata) { $n++ }
    }
    if (-not $Silenzioso -and $tot -gt 0) {
        $nome = switch ($Preset) { 'Gaming' { 'Prestazioni (più FPS)' } 'Grafica' { 'Qualità' } 'Produttivita' { 'Bilanciato' } 'Batteria' { 'Batteria' } 'Predefinito' { 'Predefinite del driver' } default { '' } }
        $chi = $(if ($Solo) { $Solo } else { 'scheda video' })
        if ($Preset -eq 'Attuale') { Imposta-Stato "Scelte $chi annullate: i menu mostrano di nuovo i valori attuali." }
        else {
            Scrivi-Log "Preset $chi '$nome' selezionato: $n impostazioni da cambiare."
            Imposta-Stato "Preset $chi '$nome': $n impostazioni da cambiare (evidenziate come 'Da applicare'). Puoi ritoccare i menu, poi premi 'Anteprima e applica'."
        }
    }
    return $n
}

function Originale-Nvidia($Voce) {
    $s = Leggi-StatoNvidia $Voce
    return @{ IdNv = [uint32]$Voce.IdNv; NelProfilo = [bool]$s.NelProfilo; Valore = [uint32]$s.Valore }
}

# Scrive il valore scelto ($Voce.Scelto). Se coincide con quello di serie, l'impostazione viene
# tolta dal profilo: così resta "di serie" anche se un driver futuro cambia il proprio valore.
function Applica-Nvidia($Voce, [string]$Obiettivo) {
    $s = Leggi-StatoNvidia $Voce
    if ($Obiettivo -eq 'Predefinito' -or $null -eq $Voce.Scelto -or [uint32]$Voce.Scelto -eq [uint32]$s.Predefinito) {
        [OttWin.NvDrs]::Ripristina([uint32]$Voce.IdNv)
    } else {
        [OttWin.NvDrs]::Scrivi([uint32]$Voce.IdNv, [uint32]$Voce.Scelto)
    }
}

function Ripristina-Nvidia($O) {
    if ($O.NelProfilo) { [OttWin.NvDrs]::Scrivi([uint32]$O.IdNv, [uint32]$O.Valore) }
    else { [OttWin.NvDrs]::Ripristina([uint32]$O.IdNv) }
}

# ---------- Impostazioni AMD ----------
function Amd-Disponibile {
    return [bool](('OttWin.AmdAdlx' -as [type]) -and [OttWin.AmdAdlx]::Disponibile())
}

function Leggi-ValoreAmd($Voce) {
    $a = $Voce.Amd
    return [int][OttWin.AmdAdlx]::Leggi([int]$a[0], [bool]$a[1], [int]$a[2], [bool]$a[3])
}

function Scrivi-ValoreAmd($Voce, [int]$Valore) {
    $a = $Voce.Amd
    [OttWin.AmdAdlx]::Scrivi([int]$a[0], [bool]$a[1], [int]$a[4], $Valore)
}

function Testo-Amd($Voce, $Valore) {
    $k = [string][int]$Valore
    if ($Voce.Etichette -and $Voce.Etichette.ContainsKey($k)) { return $Voce.Etichette[$k] }
    return "valore $k"
}

function Leggi-VoceAmd($Voce) {
    if (-not (Amd-Disponibile)) { return Nuova-Lettura 'AMD non disponibile' 'Non presente' $false }
    if (-not [OttWin.AmdAdlx]::Supportata([int]$Voce.Amd[0], [bool]$Voce.Amd[1])) { return Nuova-Lettura 'Non supportata da questa scheda' 'Non presente' $false }
    $val = Leggi-ValoreAmd $Voce
    $pred = ($null -eq $Voce.ValoreDriver) -or ($val -eq [int]$Voce.ValoreDriver)
    $l = Nuova-Lettura (Testo-Amd $Voce $val) $(if ($pred) { 'Predefinito' } else { 'Personalizzato' }) $true $pred
    $l | Add-Member -NotePropertyName Valore -NotePropertyValue $val
    $l | Add-Member -NotePropertyName ValorePredefinito -NotePropertyValue $(if ($null -ne $Voce.ValoreDriver) { [string][int]$Voce.ValoreDriver } else { '' })
    return $l
}

# Scelte del menu: quelle del catalogo, più il valore attuale se non è in elenco.
function Opzioni-Amd($Voce, [int]$Attuale) {
    $lista = New-Object 'System.Collections.Generic.List[OttWin.OpzioneVoce]'
    $pred = $(if ($null -ne $Voce.ValoreDriver) { [int]$Voce.ValoreDriver } else { $null })
    foreach ($o in $Voce.Opzioni) {
        $op = New-Object OttWin.OpzioneVoce
        $op.Valore = [string][int]$o[0]
        $op.Testo = [string]$o[1] + $(if ($null -ne $pred -and [int]$o[0] -eq $pred) { '  (di serie)' } else { '' })
        $lista.Add($op)
    }
    if (-not ($lista | Where-Object { $_.Valore -eq [string]$Attuale })) {
        $op = New-Object OttWin.OpzioneVoce
        $op.Valore = [string]$Attuale; $op.Testo = "valore $Attuale"
        $lista.Add($op)
    }
    return , $lista
}

function Originale-Amd($Voce) { return @{ Id = $Voce.Id; Valore = (Leggi-ValoreAmd $Voce) } }

function Applica-Amd($Voce, [string]$Obiettivo) {
    if ($Obiettivo -eq 'Predefinito' -or $null -eq $Voce.Scelto) {
        if ($null -eq $Voce.ValoreDriver) { return }   # nessun valore di serie fisso: si lascia com'è
        Scrivi-ValoreAmd $Voce ([int]$Voce.ValoreDriver)
    } else { Scrivi-ValoreAmd $Voce ([int]$Voce.Scelto) }
}

function Ripristina-Amd($Record) {
    $v = $Script:Voci[$Record.Id]
    if (-not $v) { throw "Voce $($Record.Id) non trovata nel catalogo." }
    Scrivi-ValoreAmd $v ([int]$Record.Originale.Valore)
}


# ---------- Smistamento per tipo ----------
function Leggi-Voce($Voce) {
    switch ($Voce.Tipo) {
        'NVIDIA'         { return Leggi-VoceNvidia $Voce }
        'AMD'            { return Leggi-VoceAmd $Voce }
        'Registro'       { return Leggi-VoceRegistro $Voce }
        'Servizio'       { return Leggi-VoceServizio $Voce }
        'App'            { return Leggi-VoceApp $Voce }
        'Avvio'          { return Leggi-VoceAvvio $Voce }
        'Pulizia'        { return Leggi-VocePulizia $Voce }
        'Attivita'       { return Leggi-VoceAttivita $Voce }
        'Personalizzato' { return (& $Voce.Leggi $Voce) }
        default          { throw "Tipo di voce sconosciuto: $($Voce.Tipo)" }
    }
}

function Ottieni-Originale($Voce) {
    switch ($Voce.Tipo) {
        'Registro'       { return Originale-Registro $Voce }
        'Servizio'       { return Originale-Servizio $Voce }
        'App'            { return Originale-App $Voce }
        'Avvio'          { return Originale-Avvio $Voce }
        'NVIDIA'         { return Originale-Nvidia $Voce }
        'AMD'            { return Originale-Amd $Voce }
        'Attivita'       { return Originale-Attivita $Voce }
        'Personalizzato' { return (& $Voce.Originale $Voce) }
        default          { return $null }
    }
}

function Applica-Voce($Voce, [string]$Obiettivo) {
    # Voci che Windows non lascia cambiare ai programmi: solo istruzioni per farlo a mano
    if ($Voce.Manuale) { throw $Voce.Manuale }
    switch ($Voce.Tipo) {
        'Registro'       { Applica-Registro $Voce $Obiettivo }
        'Servizio'       { Applica-Servizio $Voce $Obiettivo }
        'App'            { Applica-App $Voce $Obiettivo }
        'Avvio'          { Applica-Avvio $Voce $Obiettivo }
        'Pulizia'        { Applica-Pulizia $Voce $Obiettivo }
        'NVIDIA'         { Applica-Nvidia $Voce $Obiettivo }
        'AMD'            { Applica-Amd $Voce $Obiettivo }
        'Attivita'       { Applica-Attivita $Voce $Obiettivo }
        'Personalizzato' { & $Voce.Applica $Obiettivo $Voce }
    }
}

# Rimette i valori salvati in un record del file di backup.
function Ripristina-Record($Record) {
    switch ($Record.Tipo) {
        'Registro' { Ripristina-Registro $Record.Originale }
        'Servizio' { Ripristina-Servizio $Record.Originale }
        'App'      { Ripristina-App $Record.Originale }
        'Avvio'    { Ripristina-Avvio $Record.Originale }
        'NVIDIA'   { Ripristina-Nvidia $Record.Originale }
        'AMD'      { Ripristina-Amd $Record }
        'Attivita' { Ripristina-Attivita $Record.Originale }
        'Personalizzato' {
            $v = $Script:Voci[$Record.Id]
            if (-not $v) { throw "Voce $($Record.Id) non trovata nel catalogo: impossibile annullarla." }
            & $v.Ripristina $Record.Originale $v
        }
        default { throw "Tipo non annullabile: $($Record.Tipo)" }
    }
}

# Riga dell'anteprima: cosa cambia e con quali avvertenze.
function Testo-Verso($Voce, [string]$Obiettivo, [string]$TestoScelta = '') {
    if ($Voce.Tipo -eq 'NVIDIA' -or $Voce.Tipo -eq 'AMD') { return [string]$Voce.TestoScelto }
    if ($TestoScelta) { return $TestoScelta }
    if ($Obiettivo -eq 'Predefinito') { return [string]$Voce.TestoPredefinito }
    return [string]$Voce.TestoConsigliato
}

# Scelte del menu a tendina "Da applicare" per le voci di Windows (non NVIDIA/AMD).
# Valore: 'Consigliato' | 'Predefinito' | 'Modo:<avvio servizio>' | 'Valore:<numero>'.
# Restituisce $null se la voce ha una sola scelta sensata (resta il solo interruttore).
function Scelte-Voce($Voce) {
    $lista = New-Object 'System.Collections.Generic.List[OttWin.OpzioneVoce]'
    $aggiungi = { param($val, $testo) $o = New-Object OttWin.OpzioneVoce; $o.Valore = $val; $o.Testo = $testo; $lista.Add($o) }
    switch ($Voce.Tipo) {
        'Servizio' {
            foreach ($m in @('Automatico', 'AutomaticoRitardato', 'Manuale', 'Disattivato')) {
                $t = Nome-Modo $m
                if ($m -eq $Voce.Consigliato) { $t += '  (consigliato)' } elseif ($m -eq $Voce.Predefinito) { $t += '  (Windows)' }
                & $aggiungi $(if ($m -eq $Voce.Consigliato) { 'Consigliato' } else { "Modo:$m" }) $t
            }
        }
        'Attivita' { & $aggiungi 'Consigliato' 'Disattivate  (consigliato)'; & $aggiungi 'Predefinito' 'Attive  (Windows)' }
        'Registro' {
            $vals = @($Voce.Valori)
            if ($vals.Count -eq 1 -and $Voce.Etichette -and $Voce.Etichette.Count -gt 0) {
                # Valore unico con etichette: tutte le scelte conosciute
                & $aggiungi 'Consigliato' "$($Voce.TestoConsigliato)  (consigliato)"
                $visti = @{ ([string]$vals[0].Consigliato) = $true }
                if ($null -ne $vals[0].Predefinito -and -not $visti.ContainsKey([string]$vals[0].Predefinito)) {
                    & $aggiungi 'Predefinito' "$($Voce.TestoPredefinito)  (Windows)"; $visti[[string]$vals[0].Predefinito] = $true
                }
                foreach ($k in @($Voce.Etichette.Keys | Sort-Object)) {
                    if ($visti.ContainsKey([string]$k)) { continue }
                    & $aggiungi "Valore:$k" ([string]$Voce.Etichette[$k])
                }
            } elseif ([string]$Voce.TestoPredefinito -and $Voce.TestoPredefinito -ne $Voce.TestoConsigliato) {
                & $aggiungi 'Consigliato' "$($Voce.TestoConsigliato)  (consigliato)"
                & $aggiungi 'Predefinito' "$($Voce.TestoPredefinito)  (Windows)"
            }
        }
        'Personalizzato' {
            if ($Voce.Sottogruppo -and $Voce.Etichette) {
                # impostazione del piano energetico: tutte le scelte
                foreach ($k in @($Voce.Etichette.Keys | Sort-Object { [int]$_ })) {
                    $t = [string]$Voce.Etichette[$k]
                    if ([int]$k -eq [int]$Voce.ValoreCons) { & $aggiungi 'Consigliato' "$t  (consigliato)" }
                    elseif ([int]$k -eq [int]$Voce.ValorePred) { & $aggiungi 'Predefinito' "$t  (Windows)" }
                    else { & $aggiungi "Valore:$k" $t }
                }
            } elseif ([string]$Voce.TestoPredefinito -and $Voce.TestoPredefinito -ne $Voce.TestoConsigliato -and -not $Voce.Gruppo) {
                & $aggiungi 'Consigliato' "$($Voce.TestoConsigliato)  (consigliato)"
                & $aggiungi 'Predefinito' "$($Voce.TestoPredefinito)  (Windows)"
            }
        }
    }
    if ($lista.Count -lt 2) { return $null }
    return , $lista
}

# La voce è già nello stato scelto? (così l'anteprima mostra solo le modifiche vere)
function Gia-AlBersaglio($Voce, $Lettura, [string]$Obiettivo) {
    if ($Obiettivo -eq 'Consigliato') { return ($Lettura.Esito -eq 'A posto') }
    if ($Obiettivo -eq 'Predefinito') { return [bool]$Lettura.EPredefinito }
    if ($Obiettivo -like 'Modo:*') {
        $m = $Obiettivo.Substring(5)
        $stati = @(Stati-Servizi $Voce | Where-Object { $_.Modo -ne 'Sistema' })
        return ($stati.Count -gt 0 -and @($stati | Where-Object { $_.Modo -ne $m }).Count -eq 0)
    }
    if ($Obiettivo -like 'Valore:*') {
        $t = $Obiettivo.Substring(7)
        if ($Voce.Sottogruppo) { $i = Leggi-IndiceEnergia $Voce.Sottogruppo $Voce.Impostazione; return ($null -ne $i -and [string]$i.AC -eq $t) }
        if ($Voce.Tipo -eq 'Registro') { $v = @($Voce.Valori)[0]; $l = Leggi-Registro $v.Percorso $v.Nome; return ($l.Esiste -and [string]$l.Valore -eq $t) }
    }
    return $false
}

function Descrivi-Modifica($Voce, $Lettura, [string]$Obiettivo, [string]$TestoScelta = '') {
    $verso = Testo-Verso $Voce $Obiettivo $TestoScelta
    $note = @()
    if ($Voce.Tipo -eq 'Pulizia') { $note += 'NON annullabile' }
    if ($Voce.Tipo -eq 'App') { $note += 'reinstallabile dallo Store' }
    if ($Voce.Riavvio) { $note += "richiede $($Voce.Riavvio)" }
    if ($Voce.Avanzata) { $note += 'AVANZATA' }
    if ($Voce.Manuale) { $note += 'DA FARE A MANO (protetta da Windows)' }
    return [pscustomobject]@{ Categoria = (Tr $Voce.Categoria); Voce = (Tr $Voce.Nome); Da = (Tr $Lettura.Attuale); A = (Tr $verso); Rischio = (Tr $Voce.Rischio); Note = ((@($note | ForEach-Object { Tr $_ })) -join ', ') }
}

# ==============================================================================
# 6. SCANSIONE, ANTEPRIMA, APPLICAZIONE, ANNULLA TUTTO
# ==============================================================================

$Script:Categorie = @('Debloat app', 'Avvio', 'Servizi', 'Privacy', 'Prestazioni', 'Latenza', 'Grafica', 'Esplora file', 'NVIDIA', 'NVIDIAAvanz', 'AMD', 'Pulizia', 'Registro', 'Manutenzione', 'Avanzate')
$Script:TestiIntro = @{
    'Registro'    = "Voci del registro rimaste da programmi che non esistono più: programmi all'avvio, comandi di Esegui e nomi ricordati. Si tocca solo quello che punta a un file sicuramente cancellato su un disco interno; chiavi di sistema, estensioni dei file e driver non vengono mai toccati. Prima di togliere qualcosa viene salvato tutto in Dati\Backup e 'Annulla tutto' lo rimette. Nota onesta: pulire il registro non rende il PC più veloce, serve a togliere errori e righe inutili. Le righe rotte di 'App installate' sono in Avanzate."
    'Debloat app' = "App preinstallate che puoi rimuovere. Sono elencate solo quelle presenti su questo PC. Store, Sicurezza di Windows, driver e componenti di sistema non compaiono mai."
    'Avvio'       = "Programmi che partono quando accedi a Windows. Disattivarli è sempre reversibile (è lo stesso interruttore di Gestione attività)."
    'Servizi'     = "Servizi di Windows non essenziali e attività pianificate di telemetria. Si cambia solo il modo in cui partono. Windows Update e Defender sono protetti."
    'Esplora file' = "Piccole impostazioni che rendono più pratico Esplora file e la barra delle applicazioni. Tutte reversibili."
    'Manutenzione' = "Strumenti ufficiali di Windows per controllare e riparare il sistema. Si eseguono solo quando li accendi e premi 'Anteprima e applica'; non c'è niente da annullare."
    'Privacy'     = "Telemetria, pubblicità, suggerimenti e notifiche promozionali. Solo impostazioni documentate."
    'Prestazioni' = "Piano energetico e comportamento del sistema. Per i piani energetici se ne può scegliere uno solo."
    'Latenza'     = "Reattività del PC: accessori (mouse, tastiere, controller), USB e Bluetooth, rete, processore, memoria e timer di sistema. Correggono anche i 'tweak' sbagliati lasciati da altri programmi. Le voci a rischio medio non sono in nessun profilo: accendile tu dopo aver letto la descrizione. 'Misura la latenza' controlla il ping verso il router e il DNS (solo lettura)."
    'Grafica'     = "Impostazioni grafiche ed effetti visivi. Colori, HDR, profili colore e impostazioni GPU delle singole app non vengono mai toccati."
    'NVIDIA'      = "Impostazioni globali del Pannello di controllo NVIDIA, lette e scritte con NVAPI (la libreria ufficiale del driver). Scegli uno dei preset (Prestazioni, Bilanciato, Qualità: cambiano solo queste impostazioni, i profili non le toccano) oppure cambia i singoli menu a tendina: le righe 'Da applicare' vengono scritte solo con 'Anteprima e applica'. Valgono per i programmi avviati dopo la modifica; un'installazione pulita del driver le riporta ai valori di serie."
    'NVIDIAAvanz' = "⚠  OPZIONI AVANZATE: le impostazioni che di solito si cambiano con NVIDIA Profile Inspector (DLSS, Smooth Motion, Resizable BAR, nitidezza, ray tracing, memoria CUDA...), scritte nel profilo globale con NVAPI. Non fanno parte dei preset: scegli tu, una per una, dal menu a tendina. Cambiarle male può causare errori nei giochi: 'Predefinite del driver' rimette tutto a posto e 'Annulla tutto' ripristina i valori originali. Compaiono solo quelle che il tuo driver conosce."
    'AMD'         = "Impostazioni grafiche globali di AMD Software: Adrenalin Edition, lette e scritte con ADLX (la libreria ufficiale del driver AMD). Scegli uno dei preset (Prestazioni, Bilanciato, Qualità: cambiano solo queste impostazioni, i profili non le toccano) oppure cambia i singoli menu a tendina: le righe 'Da applicare' vengono scritte solo con 'Anteprima e applica'. Compaiono solo le funzioni che la tua scheda supporta."
    'Pulizia'     = "File temporanei e cache. Attenzione: la pulizia NON si può annullare (i file vengono eliminati)."
    'Avanzate'    = "⚠  VOCI AVANZATE: possono togliere funzioni o avere effetti collaterali. Non sono mai incluse nei profili: spuntale solo se hai letto la descrizione e sai cosa fanno."
}

$Script:TutteLeRighe = New-Object System.Collections.ArrayList
$Script:Collezioni   = @{}
$Script:TabCategorie = @{}
$Script:IntroCategorie = @{}

# Se spunti una voce di un gruppo (es. piani energetici), le altre dello stesso gruppo si tolgono.
$Script:GestoreSelezione = [System.ComponentModel.PropertyChangedEventHandler] {
    param($Riga, $Evento)
    try {
        if ($Evento.PropertyName -eq 'Selezionata' -and $Riga.Selezionata -and $Riga.Gruppo) {
            foreach ($altra in $Script:TutteLeRighe) {
                if (-not [object]::ReferenceEquals($altra, $Riga) -and $altra.Gruppo -eq $Riga.Gruppo) { $altra.Selezionata = $false }
            }
        }
        if ($Evento.PropertyName -eq 'Selezionata' -and -not $Script:ScansioneInCorso) { Aggiorna-ConteggioSelezione }
    } catch { }
}
$Script:ScansioneInCorso = $false

function Nuova-Riga($Voce, $Lettura) {
    $r = New-Object OttWin.RigaVoce
    $r.Id = $Voce.Id; $r.Nome = $Voce.Nome; $r.Categoria = $Voce.Categoria
    $r.Consigliato = $Voce.TestoConsigliato; $r.Predefinito = $Voce.TestoPredefinito
    $r.Rischio = $Voce.Rischio; $r.Gruppo = [string]$Voce.Gruppo
    $r.Attuale = $Lettura.Attuale; $r.Esito = $Lettura.Esito
    if (($Voce.Tipo -eq 'NVIDIA' -or $Voce.Tipo -eq 'AMD') -and $Lettura.Esito -ne 'Errore') {
        # Riga con menu a tendina: la scelta iniziale è il valore attuale (quindi niente da applicare).
        $r.Area = [string]$Voce.Area
        $r.EsitoBase = $Lettura.Esito
        if ($Voce.Tipo -eq 'NVIDIA') {
            $r.ValoreAttuale = [string][uint32]$Lettura.Valore
            $r.ValorePredefinito = [string][uint32]$Lettura.ValorePredefinito
            $opzioni = Opzioni-Nvidia $Voce ([uint32]$Lettura.Valore) ([uint32]$Lettura.ValorePredefinito)
        } else {
            $r.ValoreAttuale = [string][int]$Lettura.Valore
            $r.ValorePredefinito = [string]$Lettura.ValorePredefinito
            $opzioni = Opzioni-Amd $Voce ([int]$Lettura.Valore)
        }
        $r.Opzioni = $opzioni
        $r.Scelta = ($opzioni | Where-Object { $_.Valore -eq $r.ValoreAttuale } | Select-Object -First 1)
    } elseif ($Lettura.Esito -ne 'Errore') {
        # Voci di Windows con più scelte: menu "Da applicare" (di serie il valore consigliato)
        $scelte = Scelte-Voce $Voce
        if ($scelte) {
            $r.Scelte = $scelte
            $r.SceltaVoce = ($scelte | Where-Object { $_.Valore -eq 'Consigliato' } | Select-Object -First 1)
            if (-not $r.SceltaVoce) { $r.SceltaVoce = $scelte[0] }
        }
    }
    $r.add_PropertyChanged($Script:GestoreSelezione)
    return $r
}

function Blocca-Pulsanti([bool]$Occupato) {
    foreach ($n in @('BtnMassimo', 'BtnGaming', 'BtnGrafica', 'BtnBilanciato', 'BtnBatteria', 'BtnSicuro', 'BtnNessuno', 'BtnScansiona', 'BtnApplica', 'BtnPredefinito', 'BtnAnnullaTutto', 'BtnSalvaProfilo', 'BtnRiavvia')) {
        $b = $Script:Finestra.FindName($n); if ($b) { $b.IsEnabled = -not $Occupato }
    }
    foreach ($c in @($Script:PannelloGpu, $Script:PannelloDriver, $Script:PannelloApp)) { if ($c) { $c.IsEnabled = -not $Occupato } }
    # Durante un'operazione la barra scorre; le operazioni con una percentuale la aggiornano da sole.
    if ($Occupato) { Imposta-Avanzamento -1 } else { Imposta-Avanzamento $null }
    Aggiorna-UI
}

# Aggiorna i numeri accanto alle sezioni (voci da sistemare), la Panoramica e il conteggio delle voci accese.
function Aggiorna-Intestazioni {
    $totale = 0
    foreach ($cat in $Script:Categorie) {
        $coll = $Script:Collezioni[$cat]
        $p = $Script:Pagine[$cat]
        if ($null -eq $coll -or -not $p) { continue }
        $n = @($coll | Where-Object { $_.Esito -eq 'Da modificare' -or $_.Esito -eq 'Da pulire' -or $_.Esito -eq 'Da applicare' }).Count
        $totale += $n
        $p.Numero.Text = "$n"
        $p.Badge.Visibility = $(if ($n -gt 0) { 'Visible' } else { 'Collapsed' })
        $t = $Script:TesserePanoramica[$cat]
        if ($t) {
            if ($coll.Count -eq 0) { $t.Text = 'Niente da mostrare su questo PC' }
            elseif ($cat -eq 'Manutenzione') { $t.Text = "$($coll.Count) strumenti su richiesta" }
            elseif ($cat -eq 'NVIDIA' -or $cat -eq 'NVIDIAAvanz' -or $cat -eq 'AMD') { $t.Text = $(if ($n -gt 0) { "$n da applicare · $($coll.Count) impostazioni" } else { "$($coll.Count) impostazioni" }) }
            elseif ($n -eq 0) { $t.Text = "$($coll.Count) voci · tutto a posto" }
            else { $t.Text = "$n da sistemare · $($coll.Count) voci" }
            $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($n -gt 0) { 'Arancio' } else { 'Testo2' }))
        }
    }
    if ($Script:TesserePanoramica['Video']) { $Script:TesserePanoramica['Video'].Text = 'Versioni, aggiornamenti, installazione pulita' }
    if ($Script:TesserePanoramica['Driver']) { $Script:TesserePanoramica['Driver'].Text = 'Chipset, audio, rete: più driver insieme' }
    if ($Script:TesserePanoramica['App']) { $Script:TesserePanoramica['App'].Text = 'Disinstallazione completa dei programmi' }
    # Senza scheda NVIDIA (o AMD) la sezione non serve: sparisce dalla barra laterale.
    foreach ($marca in @('NVIDIA', 'NVIDIAAvanz', 'AMD')) {
        if ($Script:ScansioneFatta -and $Script:Pagine[$marca]) {
            $vis = $(if ($Script:Collezioni[$marca].Count -gt 0) { 'Visible' } else { 'Collapsed' })
            $Script:Pagine[$marca].Nascosta = ($vis -eq 'Collapsed')
            if ($Script:Pannelli -and $Script:Pannelli[$marca]) { $Script:Pannelli[$marca].Visibility = $vis }
        }
    }
    Aggiorna-VisibilitaNav
    Aggiorna-ConteggioSelezione
    if ($Script:PaginaAttuale) { Mostra-Pagina $Script:PaginaAttuale }
}

# SCANSIONE: legge lo stato di tutte le voci. Non modifica niente.
function Esegui-Scansione {
    Blocca-Pulsanti $true
    try {
        Imposta-Stato 'Scansione in corso (sola lettura, non modifica niente)...'
        Scrivi-Log '--- Scansione avviata (sola lettura) ---'
        $Script:ScansioneInCorso = $true
        $selezionate = @($Script:TutteLeRighe | Where-Object { $_.Selezionata -and -not $_.Opzioni } | ForEach-Object { $_.Id })
        # Scelte in sospeso nei menu a tendina NVIDIA: vengono rimesse dopo la rilettura
        $scelte = @{}
        foreach ($r in @($Script:TutteLeRighe | Where-Object { $_.Opzioni -and $_.Selezionata -and $_.Scelta })) { $scelte[$r.Id] = $r.Scelta.Valore }
        # ...e le scelte dei menu "Da applicare" delle voci di Windows
        $scelteVoci = @{}
        foreach ($r in @($Script:TutteLeRighe | Where-Object { $_.Scelte -and $_.SceltaVoce })) { $scelteVoci[$r.Id] = $r.SceltaVoce.Valore }

        # Le voci "Avvio" vengono rilette ogni volta dal PC
        foreach ($id in @($Script:Voci.Keys | Where-Object { $_ -like 'avvio|*' })) { $Script:Voci.Remove($id) }
        foreach ($v in @(Trova-VociAvvio)) { $Script:Voci[$v.Id] = $v }

        $Script:CacheAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
        foreach ($c in $Script:Collezioni.Values) { $c.Clear() }
        $Script:TutteLeRighe.Clear()

        $risultati = New-Object System.Collections.ArrayList
        $voci = @($Script:Voci.Values)
        $i = 0; $daFare = 0; [int64]$pulibile = 0
        foreach ($v in $voci) {
            $i++
            if ($i % 3 -eq 0) { Imposta-Stato "Scansione in corso... $i di $($voci.Count)"; Imposta-Avanzamento (100 * $i / [math]::Max(1, $voci.Count)) }
            # Voci che esistono solo da una certa versione di Windows in poi (o fino a una certa versione)
            if (($v.MinBuild -and $Script:Build -lt [int]$v.MinBuild) -or ($v.MaxBuild -and $Script:Build -gt [int]$v.MaxBuild)) { continue }
            try { $l = Leggi-Voce $v } catch { $l = Nuova-Lettura ('Errore: ' + $_.Exception.Message) 'Errore' }
            if (-not $l.Presente) { continue }
            $r = Nuova-Riga $v $l
            if ($selezionate -contains $v.Id) { $r.Selezionata = $true }
            if ($scelte.ContainsKey($v.Id) -and $r.Opzioni) {
                $op = $r.Opzioni | Where-Object { $_.Valore -eq $scelte[$v.Id] } | Select-Object -First 1
                if ($op) { $r.Scelta = $op }
            }
            if ($scelteVoci.ContainsKey($v.Id) -and $r.Scelte) {
                $op = $r.Scelte | Where-Object { $_.Valore -eq $scelteVoci[$v.Id] } | Select-Object -First 1
                if ($op) { $r.ImpostaSceltaSenzaAccendere($op) }
            }
            $cat = $(if ($v.Avanzata) { 'Avanzate' } else { $v.Categoria })
            if (-not $Script:Collezioni.ContainsKey($cat)) { continue }
            $Script:Collezioni[$cat].Add($r)
            [void]$Script:TutteLeRighe.Add($r)
            if ($l.Esito -eq 'Da modificare' -or $l.Esito -eq 'Da pulire') { $daFare++ }
            if ($v.Tipo -eq 'Pulizia') { $pulibile += $l.Byte }
            [void]$risultati.Add([pscustomobject]@{ Id = $v.Id; Categoria = $v.Categoria; Avanzata = $v.Avanzata; Voce = $v.Nome
                Attuale = $l.Attuale; Consigliato = $v.TestoConsigliato; Predefinito = $v.TestoPredefinito; Rischio = $v.Rischio; Esito = $l.Esito })
        }
        $Script:CacheAppx = $null

        Salva-Json @{ Data = (Get-Date).ToString('s'); Computer = $env:COMPUTERNAME; Versione = $Script:Versione; Voci = $risultati } (Join-Path $Script:CartellaDati 'ultima_scansione.json')
        $Script:ScansioneFatta = $true
        $Script:ScansioneInCorso = $false
        $Script:UltimoPulibile = $pulibile
        Aggiorna-Intestazioni
        try { Imposta-Stato 'Preparo il report dello stato del PC...'; Costruisci-Report } catch { Scrivi-Log "Report non riuscito: $($_.Exception.Message)" 'AVVISO' }
        if ($Script:RiepilogoPanoramica) { $Script:RiepilogoPanoramica.Text = Tr "$daFare voci da sistemare su $($risultati.Count)  ·  circa $(Formatta-Dimensione $pulibile) recuperabili con la pulizia" }
        $msg = "Scansione completata: $($risultati.Count) voci, $daFare da sistemare, circa $(Formatta-Dimensione $pulibile) recuperabili con la pulizia."
        Scrivi-Log $msg 'OK'
        Imposta-Stato "$msg  Scegli un profilo o accendi le voci, poi premi 'Anteprima e applica'."
    } finally {
        $Script:ScansioneInCorso = $false
        $Script:CacheAppx = $null
        Blocca-Pulsanti $false
    }
}

# PROFILI: spuntano le voci del profilo e tolgono le altre (le voci avanzate mai).
function Applica-Profilo([string]$Profilo) {
    if ($Profilo -eq 'Massimo') {
        $avviso = "Il profilo 'Massimo' accende TUTTO quello che il programma ritiene utile per migliorare il PC, comprese voci a rischio medio:`n`n" +
                  "•  rimuove le app preinstallate non essenziali (anche Copilot, Teams personale, Posta di Windows se presenti);`n" +
                  "•  disattiva servizi e attività di telemetria e il servizio Segnalazione errori;`n" +
                  "•  blocca le app dello Store in background (le notifiche di alcune app possono arrivare in ritardo);`n" +
                  "•  imposta il piano 'Prestazioni elevate' (la scheda video non viene toccata: ha i suoi preset);`n" +
                  "•  pulisce i file temporanei (non annullabile).`n`n" +
                  "Le voci 'Avanzate' restano escluse. Niente viene applicato finché non confermi l'anteprima, e quasi tutto si annulla con 'Annulla tutto'.`n`nVuoi accendere le voci del profilo Massimo?"
        if ((Mostra-Messaggio $avviso 'Profilo Massimo' 'YesNo' 'Warning') -ne 'Yes') { return $false }
    }
    if ($Profilo -eq 'Batteria' -and -not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) {
        [void](Mostra-Messaggio "Su questo PC non c'è una batteria: il profilo 'Portatile a batteria' riduce i consumi ma è pensato per i portatili. Puoi usarlo lo stesso se vuoi un PC più silenzioso e fresco." 'Portatile a batteria')
    }
    $n = 0
    foreach ($r in $Script:TutteLeRighe) {
        $v = $Script:Voci[$r.Id]
        if ($v.Tipo -eq 'NVIDIA' -or $v.Tipo -eq 'AMD') { continue }   # le schede video seguono il preset abbinato (qui sotto)
        $sel = (-not $v.Avanzata) -and (@($v.Profili) -contains $Profilo)
        $r.Selezionata = $sel
        # Il menu "Da applicare" torna sul valore consigliato
        if ($r.Scelte) { $c = $r.Scelte | Where-Object { $_.Valore -eq 'Consigliato' } | Select-Object -First 1; if ($c) { $r.ImpostaSceltaSenzaAccendere($c) } }
        if ($sel -and $r.Esito -ne 'A posto') { $n++ }
    }
    # Le impostazioni delle schede video (NVIDIA/AMD) non fanno parte dei profili: hanno i loro preset nella sezione Scheda video.
    Aggiorna-Intestazioni
    $nome = $Script:NomiProfili[$Profilo]
    Scrivi-Log "Profilo '$nome' selezionato: $n voci da modificare."
    Imposta-Stato "Profilo '$nome': spuntate le voci del profilo ($n da modificare). Controlla le schede e poi premi 'Anteprima e applica'."
    return $true
}

# Se non è vuota, "Anteprima e applica" considera solo le voci spuntate di questa categoria (usata dai tasti rapidi della pulizia).
$Script:SoloCategoria = ''

# Prepara l'elenco delle modifiche reali (salta le voci già nello stato richiesto).
function Prepara-Modifiche([string]$Obiettivo) {
    $lista = New-Object System.Collections.ArrayList
    $saltate = 0
    $Script:CacheAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    try {
        foreach ($r in @($Script:TutteLeRighe | Where-Object { $_.Selezionata -and (-not $Script:SoloCategoria -or $_.Categoria -eq $Script:SoloCategoria) })) {
            $v = $Script:Voci[$r.Id]
            if (-not $v) { continue }
            if ($v.Manuale) {
                Scrivi-Log "$($v.Nome): $($v.Manuale)" 'AVVISO'
                [void](Mostra-Messaggio "$($v.Nome)`n`n$($v.Manuale)" 'Da fare a mano' 'OK' 'Information')
                $saltate++; continue
            }
            if ($Obiettivo -eq 'Predefinito' -and ($v.Tipo -eq 'App' -or $v.Tipo -eq 'Pulizia')) { $saltate++; continue }
            # Un errore di lettura su una voce non deve bloccare tutte le altre
            try { $l = Leggi-Voce $v } catch { Scrivi-Log "$($v.Nome): non leggibile, saltata ($($_.Exception.Message))" 'AVVISO'; $saltate++; continue }
            if (-not $l.Presente -or $l.Esito -eq 'Errore') { continue }
            if ($v.Tipo -eq 'NVIDIA') {
                # Il valore da scrivere è quello scelto nel menu a tendina (o quello di serie per "Riporta al predefinito")
                $bersaglio = $(if ($Obiettivo -eq 'Predefinito' -or -not $r.Scelta) { [uint32]$l.ValorePredefinito } else { [uint32]$r.Scelta.Valore })
                if ([uint32]$l.Valore -eq $bersaglio) { $saltate++; continue }
                $v.Scelto = $bersaglio
                $v.TestoScelto = Testo-Nvidia $v $bersaglio
                [void]$lista.Add([pscustomobject]@{ Voce = $v; Lettura = $l; Obiettivo = $Obiettivo; TestoScelta = '' })
                continue
            }
            if ($v.Tipo -eq 'AMD') {
                if ($Obiettivo -eq 'Predefinito' -or -not $r.Scelta) {
                    if ($null -eq $v.ValoreDriver) { $saltate++; continue }
                    $bersaglio = [int]$v.ValoreDriver
                } else { $bersaglio = [int]$r.Scelta.Valore }
                if ([int]$l.Valore -eq $bersaglio) { $saltate++; continue }
                $v.Scelto = $bersaglio
                $v.TestoScelto = Testo-Amd $v $bersaglio
                [void]$lista.Add([pscustomobject]@{ Voce = $v; Lettura = $l; Obiettivo = $Obiettivo; TestoScelta = '' })
                continue
            }
            # Voci di Windows: con "Anteprima e applica" vale la scelta del menu "Da applicare" (se c'è)
            $obVoce = $Obiettivo; $testoScelta = ''
            if ($Obiettivo -eq 'Consigliato' -and $r.Scelte -and $r.SceltaVoce) {
                $obVoce = [string]$r.SceltaVoce.Valore
                if ($obVoce -ne 'Consigliato') { $testoScelta = ([string]$r.SceltaVoce.Testo -replace '\s+\((consigliato|Windows)\)$', '') }
            }
            if (Gia-AlBersaglio $v $l $obVoce) { $saltate++; continue }
            [void]$lista.Add([pscustomobject]@{ Voce = $v; Lettura = $l; Obiettivo = $obVoce; TestoScelta = $testoScelta })
        }
    } finally { $Script:CacheAppx = $null }
    return @{ Lista = $lista; Saltate = $saltate }
}

# Finestra di anteprima: restituisce $true se l'utente conferma.
function Mostra-Anteprima([string]$Titolo, [string]$Intro, $Righe, [string]$TestoConferma) {
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlAnteprima)
    Applica-TemaFinestra $w
    $w.Owner = $Script:Finestra
    $w.Title = $Titolo
    $w.FindName('TitoloAnteprima').Text = $Titolo
    $w.FindName('Intro').Text = $Intro
    $elenco = New-Object System.Collections.ArrayList
    foreach ($r in $Righe) { [void]$elenco.Add($r) }
    $w.FindName('Lista').ItemsSource = $elenco
    $b = $w.FindName('BtnConferma')
    $b.Content = $TestoConferma
    $b.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    return ($w.ShowDialog() -eq $true)
}

# Punto di ripristino. Restituisce $true se si può proseguire.
function Crea-PuntoRipristino {
    # Consigliato ma facoltativo: si chiede ogni volta.
    $domanda = "Vuoi creare un punto di ripristino di Windows prima di continuare?`n`n" +
               "È CONSIGLIATO: se qualcosa non va, con il punto di ripristino puoi riportare il PC a com'era adesso.`n" +
               "Richiede fino a un minuto e un po' di spazio sul disco.`n`n" +
               "Sì = crea il punto di ripristino e continua`nNo = continua senza (il backup dei valori originali per 'Annulla tutto' viene creato comunque)`nAnnulla = non fare niente"
    $risposta = Mostra-Messaggio $domanda 'Punto di ripristino (consigliato)' 'YesNoCancel' 'Information'
    if ($risposta -eq 'Cancel') { Scrivi-Log 'Operazione annullata alla domanda sul punto di ripristino.'; return $false }
    if ($risposta -eq 'No') { Scrivi-Log 'Punto di ripristino non creato: scelta dell''utente.' 'AVVISO'; return $true }
    $chiave = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    # Windows crea al massimo un punto ogni 24 ore: questo valore (documentato da Microsoft)
    # toglie il limite solo per il tempo necessario e poi viene rimesso com'era.
    $freq = Leggi-Registro $chiave 'SystemRestorePointCreationFrequency'
    $descr = 'Regia - prima delle modifiche {0:yyyy-MM-dd HH:mm}' -f (Get-Date)
    $tentativo = 0
    while ($true) {
        $tentativo++
        Imposta-Stato 'Creo il punto di ripristino (può richiedere fino a un minuto)...'
        try {
            Scrivi-Registro $chiave 'SystemRestorePointCreationFrequency' 0 'DWord'
            Esegui-InBackground { param($d) Checkpoint-Computer -Description $d -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop } @($descr) | Out-Null
            Scrivi-Log "Punto di ripristino creato: $descr" 'OK'
            return $true
        } catch {
            $motivo = $_.Exception.Message
            Scrivi-Log "Punto di ripristino non creato: $motivo" 'AVVISO'
            if ($tentativo -gt 1) {
                $r = Mostra-Messaggio "Il punto di ripristino non è stato creato nemmeno dopo aver attivato la Protezione sistema.`n`nMotivo: $motivo`n`nVuoi continuare lo stesso? (Il backup JSON dei valori originali viene creato comunque.)" 'Punto di ripristino' 'YesNo' 'Warning'
                return ($r -eq 'Yes')
            }
            $r = Mostra-Messaggio "Non sono riuscito a creare il punto di ripristino.`n`nMotivo: $motivo`n`nDi solito succede perché la Protezione sistema è disattivata sul disco C:.`n`nSì = attiva la Protezione sistema su C: e riprova`nNo = continua senza punto di ripristino (il backup JSON dei valori originali viene creato comunque)`nAnnulla = non applicare niente" 'Punto di ripristino' 'YesNoCancel' 'Warning'
            if ($r -eq 'Cancel') { return $false }
            if ($r -eq 'No') { return $true }
            try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; Scrivi-Log 'Protezione sistema attivata su C:.' 'OK' }
            catch { Scrivi-Log "Impossibile attivare la Protezione sistema: $($_.Exception.Message)" 'ERRORE' }
        } finally {
            if ($freq.Esiste) { Scrivi-Registro $chiave 'SystemRestorePointCreationFrequency' $freq.Valore $freq.Tipo }
            else { Rimuovi-Registro $chiave 'SystemRestorePointCreationFrequency' }
        }
    }
}

# APPLICA: Obiettivo 'Consigliato' (pulsante principale) o 'Predefinito' (riporta a Windows standard).
function Applica-Modifiche([string]$Obiettivo) {
    $prova = [bool]$Script:ChkProva.IsChecked
    Imposta-Stato 'Preparo l''anteprima...'
    $prep = Prepara-Modifiche $Obiettivo
    $elenco = $prep.Lista
    if ($elenco.Count -eq 0) {
        $testo = $(if (@($Script:TutteLeRighe | Where-Object { $_.Selezionata }).Count -eq 0) { 'Non hai spuntato nessuna voce.' } else { 'Le voci spuntate sono già nello stato richiesto: non c''è niente da modificare.' })
        Imposta-Stato $testo
        Scrivi-Log "Niente da applicare (obiettivo: $Obiettivo): $testo"
        [void](Mostra-Messaggio $testo 'Niente da fare' 'OK' 'Information')
        return
    }

    $righe = @($elenco | ForEach-Object { Descrivi-Modifica $_.Voce $_.Lettura $_.Obiettivo $_.TestoScelta })
    $nAvanzate = @($elenco | Where-Object { $_.Voce.Avanzata }).Count
    $nPulizia  = @($elenco | Where-Object { $_.Voce.Tipo -eq 'Pulizia' }).Count
    $dove = $(if ($Obiettivo -eq 'Predefinito') { 'ai valori PREDEFINITI di Windows' } else { 'ai valori scelti (consigliati o indicati nei menu a tendina)' })
    $intro = "Stai per portare $($elenco.Count) voci $dove."
    if ($prep.Saltate -gt 0) { $intro += " $($prep.Saltate) voci spuntate sono già a posto (o non applicabili) e verranno saltate." }
    $intro += "`nPrima di iniziare: punto di ripristino + backup JSON dei valori originali (per 'Annulla tutto')."
    if ($nAvanzate -gt 0) { $intro += "`n⚠ $nAvanzate voci AVANZATE." }
    if ($nPulizia -gt 0)  { $intro += "`n⚠ $nPulizia operazioni di pulizia NON annullabili." }
    if ($prova) { $intro = "MODALITÀ PROVA: non verrà modificato niente, le operazioni verranno solo scritte nel log.`n`n" + $intro }

    $conferma = $(if ($prova) { 'Simula (modalità prova)' } else { 'Conferma e applica' })
    if (-not (Mostra-Anteprima 'Anteprima delle modifiche' $intro $righe $conferma)) {
        Scrivi-Log 'Applicazione annullata dall''utente nell''anteprima.'
        Imposta-Stato 'Nessuna modifica applicata.'
        return
    }

    if ($prova) {
        Scrivi-Log "--- MODALITÀ PROVA: $($righe.Count) modifiche simulate ---" 'PROVA'
        foreach ($r in $righe) { Scrivi-Log "[$($r.Categoria)] $($r.Voce): '$($r.Da)' -> '$($r.A)'" 'PROVA' }
        Imposta-Stato "Modalità prova: $($righe.Count) modifiche simulate e scritte nel log. Niente è stato cambiato."
        [void](Mostra-Messaggio "Niente è stato modificato.`nLe $($righe.Count) operazioni sono elencate nella scheda Log.`n`nPer applicarle davvero spegni l'interruttore 'Modalità prova'." 'Modalità prova' 'OK' 'Information')
        return
    }

    Blocca-Pulsanti $true
    $chiediRiavvio = $false
    try {
        if (-not (Crea-PuntoRipristino)) {
            Scrivi-Log 'Applicazione annullata: punto di ripristino non creato.' 'AVVISO'
            Imposta-Stato 'Nessuna modifica applicata.'
            return
        }

        $fileBackup = Join-Path $Script:CartellaBackup ('originali_{0:yyyyMMdd_HHmmss}.json' -f (Get-Date))
        $backup = [ordered]@{ Versione = $Script:Versione; Computer = $env:COMPUTERNAME; Creato = (Get-Date).ToString('s'); Obiettivo = $Obiettivo; Modifiche = (New-Object System.Collections.ArrayList) }
        Scrivi-Log "--- Applicazione di $($elenco.Count) modifiche (obiettivo: $Obiettivo) ---"
        $ok = 0; $errori = 0; $riavvio = @()
        $i = 0
        foreach ($m in $elenco) {
            $i++
            $v = $m.Voce
            Imposta-Stato "Applico ($i di $($elenco.Count)): $($v.Nome)..."
            Imposta-Avanzamento (100 * ($i - 1) / $elenco.Count)
            try {
                # Prima si salva l'originale, poi si modifica: così il backup c'è sempre.
                if ($v.Tipo -ne 'Pulizia') {
                    $orig = Ottieni-Originale $v
                    [void]$backup.Modifiche.Add([ordered]@{ Id = $v.Id; Nome = $v.Nome; Categoria = $v.Categoria; Tipo = $v.Tipo; Data = (Get-Date).ToString('s'); Prima = $m.Lettura.Attuale; Originale = $orig })
                    Salva-Json $backup $fileBackup
                }
                Applica-Voce $v $m.Obiettivo
                $ok++
                Scrivi-Log "[$($v.Categoria)] $($v.Nome): '$($m.Lettura.Attuale)' -> '$(Testo-Verso $v $m.Obiettivo $m.TestoScelta)'" 'OK'
                if ($v.Riavvio) { $riavvio += $v.Riavvio }
            } catch {
                $errori++
                Scrivi-Log "[$($v.Categoria)] $($v.Nome): ERRORE - $($_.Exception.Message)" 'ERRORE'
            }
        }
        if ($backup.Modifiche.Count -gt 0) { Scrivi-Log "Backup dei valori originali: $fileBackup" 'OK' }

        Esegui-Scansione
        $riepilogo = "Modifiche applicate: $ok.  Errori: $errori."
        if ($errori -gt 0) { $riepilogo += "`nI dettagli degli errori sono nella scheda Log." }
        $riavvio = @($riavvio | Select-Object -Unique)
        if ($riavvio -contains 'riavvio') { $riepilogo += "`n`nAlcune modifiche hanno effetto dopo il RIAVVIO del PC." }
        elseif ($riavvio -contains 'disconnessione') { $riepilogo += "`n`nAlcune modifiche hanno effetto dopo la disconnessione (o il riavvio)." }
        Scrivi-Log ($riepilogo -replace "`n", ' ') 'OK'
        $chiediRiavvio = ($ok -gt 0 -and $riavvio.Count -gt 0)
        if ($chiediRiavvio) { Segna-Riavvio "Modifiche applicate il $(Get-Date -Format 'dd/MM HH:mm')." }
        else { [void](Mostra-Messaggio $riepilogo 'Modifiche applicate' 'OK' $(if ($errori -gt 0) { 'Warning' } else { 'Information' })) }
    } finally {
        Blocca-Pulsanti $false
    }
    # Il riavvio si propone a operazione finita, con i pulsanti già sbloccati.
    if ($chiediRiavvio) { [void](Proponi-Riavvio $riepilogo 'Modifiche applicate' (-not ($riavvio -contains 'riavvio'))) }
}

# ANNULLA TUTTO: rimette i valori originali salvati nei backup. Una finestra elenca ogni voce modificata
# con un interruttore: si annullano solo le voci accese (di serie tutte), dalla modifica più recente alla più vecchia.
# Le voci già annullate di un file di backup vengono segnate in 'annullate.json', così non si ripristinano due volte;
# quando un file è annullato del tutto diventa '.ripristinato.json' e resta solo come archivio.
function Leggi-Annullate {
    $h = @{}
    $f = Join-Path $Script:CartellaBackup 'annullate.json'
    if (-not (Test-Path -LiteralPath $f)) { return $h }
    try {
        $d = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $d.PSObject.Properties) { $h[$p.Name] = @($p.Value | ForEach-Object { [string]$_ }) }
    } catch { Scrivi-Log "Elenco delle voci già annullate non leggibile: $($_.Exception.Message)" 'AVVISO' }
    return $h
}

function Salva-Annullate($Tabella) {
    $f = Join-Path $Script:CartellaBackup 'annullate.json'
    $o = [ordered]@{}
    foreach ($k in @($Tabella.Keys | Sort-Object)) { $ids = @($Tabella[$k] | Where-Object { $_ }); if ($ids.Count -gt 0) { $o[$k] = $ids } }
    if ($o.Count -eq 0) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; return }
    Salva-Json $o $f
}

# Un file di backup diventa archivio quando tutte le sue voci sono state annullate.
function Chiudi-BackupAnnullato($File, $Annullate, $IdFile) {
    $fatti = @($Annullate[$File.Name])
    if (@($IdFile | Where-Object { $fatti -notcontains $_ }).Count -gt 0) { return }
    try {
        Rename-Item -LiteralPath $File.FullName -NewName ($File.BaseName + '.ripristinato.json') -ErrorAction Stop
        [void]$Annullate.Remove($File.Name)
    } catch { Scrivi-Log "Backup $($File.Name) non rinominato: $($_.Exception.Message)" 'AVVISO' }
}

function Formatta-DataBackup($Data) {
    if ($Data -is [datetime]) { return $Data.ToString('dd/MM/yyyy HH:mm') }
    $s = [string]$Data
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.ToString('dd/MM/yyyy HH:mm') }
    return ($s -replace 'T', ' ')
}

# Testo del pulsante di conferma: dice quante voci verranno annullate.
function Aggiorna-PulsanteAnnulla {
    $s = $Script:StatoAnnulla
    if (-not $s) { return }
    $n = @($s.Righe | Where-Object { $_.Includi }).Count
    $t = $(if ($n -eq 1) { 'Annulla 1 voce' } else { "Annulla $n voci" })
    if ($s.Prova) { $t = "Simula: $($t.Substring(0, 1).ToLower())$($t.Substring(1))" }
    $s.Bottone.Content = Tr $t
    $s.Bottone.IsEnabled = ($n -gt 0)
}

function Mostra-SceltaAnnulla([string]$Intro, $Righe, [bool]$Prova) {
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlAnnulla)
    Applica-TemaFinestra $w
    $w.Owner = $Script:Finestra
    $w.FindName('Titolo').Text = Tr 'Annulla tutto'
    $w.FindName('Intro').Text = Tr $Intro
    $w.FindName('Lista').ItemsSource = $Righe
    $Script:StatoAnnulla = @{ Righe = $Righe; Bottone = $w.FindName('BtnConferma'); Prova = $Prova }
    foreach ($r in $Righe) { $r.add_PropertyChanged({ Aggiorna-PulsanteAnnulla }) }
    $w.FindName('BtnTutte').add_Click({ foreach ($r in $Script:StatoAnnulla.Righe) { $r.Includi = $true } })
    $w.FindName('BtnNessuna').add_Click({ foreach ($r in $Script:StatoAnnulla.Righe) { $r.Includi = $false } })
    $Script:StatoAnnulla.Bottone.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    Aggiorna-PulsanteAnnulla
    try { return ($w.ShowDialog() -eq $true) }
    finally { $Script:StatoAnnulla = $null }
}

function Annulla-Tutto {
    $prova = [bool]$Script:ChkProva.IsChecked
    $file = @(Get-ChildItem -LiteralPath $Script:CartellaBackup -Filter 'originali_*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.ripristinato.json' } | Sort-Object Name -Descending)
    if ($file.Count -eq 0) {
        Scrivi-Log 'Annulla tutto: nessun backup da ripristinare.'
        [void](Mostra-Messaggio 'Non ci sono modifiche da annullare.' 'Annulla tutto' 'OK' 'Information')
        return
    }
    $annullate = Leggi-Annullate
    $record = New-Object System.Collections.ArrayList   # dal più recente al più vecchio
    $idFile = @{}
    $altroPc = 0
    foreach ($f in $file) {
        try { $dati = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Scrivi-Log "Backup non leggibile, saltato: $($f.Name) ($($_.Exception.Message))" 'AVVISO'; continue }
        # Sicurezza: si ripristinano solo i backup creati su QUESTO PC.
        $pc = [string]$dati.Computer
        if (($pc -and $pc -ne $env:COMPUTERNAME) -or (-not $pc -and -not $Script:BackupVecchiValidi)) { $altroPc++; continue }
        $mods = @($dati.Modifiche)
        $idFile[$f.Name] = @($mods | ForEach-Object { [string]$_.Id } | Select-Object -Unique)
        $gia = @($annullate[$f.Name])
        for ($i = $mods.Count - 1; $i -ge 0; $i--) {
            if ($gia -contains [string]$mods[$i].Id) { continue }
            [void]$record.Add([pscustomobject]@{ File = $f; Mod = $mods[$i] })
        }
        # Un file già annullato del tutto (per esempio se il programma si è chiuso a metà) diventa archivio.
        if ($idFile[$f.Name].Count -gt 0 -and $gia.Count -gt 0 -and -not $prova) { Chiudi-BackupAnnullato $f $annullate $idFile[$f.Name] }
    }
    if ($altroPc -gt 0) { Scrivi-Log "Annulla tutto: ignorati $altroPc file di backup creati su un altro PC." 'AVVISO' }
    if ($record.Count -eq 0) {
        if (-not $prova) { Salva-Annullate $annullate }
        [void](Mostra-Messaggio "Non ci sono modifiche da annullare su questo PC.$(if ($altroPc -gt 0) { "`n($altroPc file di backup appartengono a un altro PC e vengono ignorati.)" } else { '' })" 'Annulla tutto' 'OK' 'Information')
        return
    }

    # Una riga per voce. Se una voce è stata cambiata più volte si torna al valore di prima della prima modifica.
    $gruppi = [ordered]@{}
    foreach ($r in $record) {
        $id = [string]$r.Mod.Id
        if (-not $gruppi.Contains($id)) { $gruppi[$id] = New-Object System.Collections.ArrayList }
        [void]$gruppi[$id].Add($r)
    }
    $righe = New-Object System.Collections.ArrayList
    foreach ($id in $gruppi.Keys) {
        $g = $gruppi[$id]; $recente = $g[0].Mod; $vecchio = $g[$g.Count - 1].Mod
        $vc = $Script:Voci[$id]
        $note = @()
        if ($g.Count -gt 1) { $note += "cambiata $($g.Count) volte" }
        if ([string]$recente.Tipo -eq 'App') { $note += 'reinstallabile dallo Store' }
        if ($vc -and $vc.Riavvio) { $note += "richiede $($vc.Riavvio)" }
        $x = New-Object OttWin.RigaAnnulla
        $x.Includi = $true
        $x.Id = $id
        $x.Categoria = Tr $(if ([string]$recente.Categoria -eq 'NVIDIAAvanz') { 'NVIDIA - opzioni avanzate' } else { [string]$recente.Categoria })
        $x.Voce = Tr ([string]$recente.Nome)
        $x.Modificata = Formatta-DataBackup $recente.Data
        $x.TornaA = Tr ([string]$vecchio.Prima)
        $x.Note = (@($note | ForEach-Object { Tr $_ })) -join ', '
        [void]$righe.Add($x)
    }

    $intro = "Queste voci sono state modificate da Regia e hanno un backup su questo PC. Quelle accese tornano com'erano prima: spegni quelle che vuoi tenere (potrai annullarle anche più tardi).`nSe una voce è stata cambiata più volte, torna al valore che aveva prima della prima modifica. Le pulizie non si possono annullare. Le app rimosse vengono reinstallate se possibile, altrimenti si apre la loro pagina nel Microsoft Store."
    if ($prova) { $intro = "MODALITÀ PROVA: non verrà modificato niente.`n`n" + $intro }
    if (-not (Mostra-SceltaAnnulla $intro $righe $prova)) { Scrivi-Log 'Annulla tutto: finestra chiusa senza annullare niente.'; return }

    $scelte = @{}
    foreach ($r in $righe) { if ($r.Includi) { $scelte[$r.Id] = $true } }
    if ($scelte.Count -eq 0) { return }
    $daFare = @($record | Where-Object { $scelte.ContainsKey([string]$_.Mod.Id) })

    if ($prova) {
        Scrivi-Log "--- MODALITÀ PROVA: annullamento simulato di $($scelte.Count) voci ---" 'PROVA'
        foreach ($id in $gruppi.Keys) { if ($scelte.ContainsKey($id)) { $m = $gruppi[$id][0].Mod; Scrivi-Log "Ripristinerei: [$($m.Categoria)] $($m.Nome)" 'PROVA' } }
        Imposta-Stato 'Modalità prova: annullamento simulato, niente è stato cambiato.'
        return
    }

    Blocca-Pulsanti $true
    $chiediRiavvio = $false
    try {
        Scrivi-Log "--- Annulla tutto: $($scelte.Count) voci ---"
        $fallite = @{}; $riuscite = @{}; $riavvio = @(); $toccati = @{}; $n = 0
        foreach ($r in $daFare) {
            $n++
            $m = $r.Mod; $id = [string]$m.Id
            # Se il ripristino più recente di una voce non riesce, quelli più vecchi non si fanno:
            # la voce resta com'è e si può riprovare.
            if ($fallite.ContainsKey($id)) { continue }
            Imposta-Stato "Ripristino: $($m.Nome)..."
            Imposta-Avanzamento (100 * ($n - 1) / [math]::Max(1, $daFare.Count))
            $toccati[$r.File.Name] = $r.File
            try {
                Ripristina-Record $m
                $riuscite[$id] = $true
                Scrivi-Log "Ripristinato: [$($m.Categoria)] $($m.Nome)" 'OK'
                $annullate[$r.File.Name] = @(@($annullate[$r.File.Name]) + $id | Where-Object { $_ } | Select-Object -Unique)
                Salva-Annullate $annullate
                $vc = $Script:Voci[$id]; if ($vc -and $vc.Riavvio) { $riavvio += $vc.Riavvio }
            }
            catch { $fallite[$id] = $true; Scrivi-Log "Ripristino di $($m.Nome) non riuscito: $($_.Exception.Message)" 'ERRORE' }
        }
        foreach ($nome in @($toccati.Keys)) { Chiudi-BackupAnnullato $toccati[$nome] $annullate $idFile[$nome] }
        Salva-Annullate $annullate
        $ok = @($riuscite.Keys | Where-Object { -not $fallite.ContainsKey($_) }).Count
        $errori = $fallite.Count
        Esegui-Scansione
        $msg = "Voci ripristinate: $ok.  Errori: $errori.`nAlcune modifiche hanno effetto dopo il riavvio o la disconnessione."
        if ($errori -gt 0) { $msg += "`nLe voci con errori restano nell'elenco di 'Annulla tutto': puoi riprovare." }
        foreach ($riga in ($msg -split "`n")) { Scrivi-Log $riga $(if ($errori -gt 0) { 'AVVISO' } else { 'OK' }) }
        $riavvio = @($riavvio | Select-Object -Unique)
        $chiediRiavvio = ($riavvio.Count -gt 0)
        if ($chiediRiavvio) { Segna-Riavvio "Annulla tutto il $(Get-Date -Format 'dd/MM HH:mm')." }
        else { [void](Mostra-Messaggio $msg 'Annulla tutto' 'OK' $(if ($errori -gt 0) { 'Warning' } else { 'Information' })) }
    } finally {
        Blocca-Pulsanti $false
    }
    if ($chiediRiavvio) { [void](Proponi-Riavvio $msg 'Annulla tutto' (-not ($riavvio -contains 'riavvio'))) }
}

function Mostra-Descrizione($Riga) {
    $v = $Script:Voci[$Riga.Id]
    if (-not $v) { return }
    $profili = $(if (@($v.Profili).Count -gt 0) { (@($v.Profili) | ForEach-Object { $Script:NomiProfili[$_] }) -join ', ' } else { 'nessuno (scelta manuale)' })
    $extra = @("Rischio: $($v.Rischio)", "Profili: $profili")
    if ($v.Categoria -eq 'NVIDIAAvanz') { $extra = @("Rischio: $($v.Rischio)", 'Opzione avanzata: non fa parte dei preset') }
    elseif ($v.Tipo -eq 'NVIDIA' -or $v.Tipo -eq 'AMD') {
        # Per le impostazioni delle schede video: cosa sceglie ogni preset
        $elencoPreset = @(@('Gaming', 'Prestazioni'), @('Produttivita', 'Bilanciato'), @('Grafica', 'Qualità'))
        $extra = @(foreach ($p in $elencoPreset) {
            $val = $v.Preset[$p[0]]
            $testo = $(if ($null -eq $val) { $(if ($v.Tipo -eq 'AMD' -and $null -eq $v.ValoreDriver) { 'non cambia' } else { 'valore di serie' }) }
                      elseif ($v.Tipo -eq 'AMD') { Testo-Amd $v $val } else { (Testo-Nvidia $v $val) + $(if ($v.PresetAlmeno) { ' (o più)' } else { '' }) })
            "$(Tr $p[1]): $(Tr $testo)"
        })
        $extra = @('Preset  →  ' + ($extra -join '    ·    '))
    }
    if ($v.Riavvio) { $extra += "Richiede $($v.Riavvio)" }
    if ($v.Tipo -eq 'Pulizia') { $extra += $(if ($v.Categoria -eq 'Manutenzione') { 'Strumento ufficiale di Windows' } else { 'Non annullabile' }) }
    $Script:TitoloVoce.Text = (Tr $v.Nome)
    $Script:TestoDescrizione.Text = (Tr $v.Descrizione) + "`n" + ((@($extra | ForEach-Object { Tr $_ })) -join '    ·    ')
}

# ==============================================================================
# 6b. DRIVER: rilevamento, scelta della versione, installazione pulita
# ------------------------------------------------------------------------------
#  - NVIDIA: elenco delle versioni dal servizio ufficiale nvidia.com (anche la stessa già
#    installata o una precedente), download con conferma, verifica della firma digitale NVIDIA,
#    estrazione con tar.exe di Windows, scelta dei componenti, e installazione pulita:
#      1) punto di ripristino
#      2) rimozione dei vecchi driver dall'archivio di Windows (pnputil, strumento ufficiale)
#      3) installazione con l'opzione ufficiale "-clean"
#      4) verifica della versione installata
#  - AMD / Intel: stessa procedura partendo dal programma di installazione scaricato dal sito
#    ufficiale (la firma digitale deve essere del produttore).
#  - Altri dispositivi: catalogo driver di Windows Update, installati solo su richiesta.
#  Internet viene usato solo quando premi "Controlla aggiornamenti" o "Cerca versioni".
# ==============================================================================

$Script:CartellaDriver = Join-Path $Script:CartellaDati 'Driver'
$Script:Dispositivi    = @()
$Script:Aggiornamenti  = @()
$Script:SchedeVideo    = @()
$Script:VersioniNvidia = @()
$Script:VersioniAmd    = @()
$Script:CmbVersioniAmd = $null
$Script:UltimaVideo    = @{}
$Script:TestoAggiornamenti = $null
$Script:PannelloDriver = $null
$Script:PannelloApp    = $null
$Script:Pannelli       = @{}
$Script:ModelloPC      = ''
$Script:ProduttorePC   = ''
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $Script:ModelloPC = [string]$cs.Model
    $Script:ProduttorePC = [string]$cs.Manufacturer
} catch { }

# Componenti del pacchetto NVIDIA (cartelle del pacchetto estratto).
#   Obbligatorio = sempre installato;  Consigliato = acceso di serie;  Facoltativo = spento di serie.
$Script:NvComponenti = @(
    @{ Modello = '^Display\.Driver$';     Stato = 'Obbligatorio'; Descr = 'Driver grafico (indispensabile)' }
    @{ Modello = '^NVI2$';                Stato = 'Obbligatorio'; Descr = 'Motore dell''installazione (indispensabile)' }
    @{ Modello = '^MSVCRT';               Stato = 'Obbligatorio'; Descr = 'Librerie necessarie all''installazione' }
    @{ Modello = '^Display\.Optimus$';    Stato = 'Consigliato';  Descr = 'Commutazione tra grafica integrata e NVIDIA (portatili)' }
    @{ Modello = '^HDAudio$';             Stato = 'Consigliato';  Descr = 'Audio via HDMI / DisplayPort' }
    @{ Modello = '^PhysX$';               Stato = 'Consigliato';  Descr = 'Fisica PhysX usata da alcuni giochi' }
    @{ Modello = '^PPC$';                 Stato = 'Consigliato';  Descr = 'Driver USB-C collegato alla GPU' }
    @{ Modello = '^NVPCF$';               Stato = 'Consigliato';  Descr = 'Platform Controllers and Framework (Dynamic Boost, portatili)' }
    @{ Modello = 'PlatformController';    Stato = 'Consigliato';  Descr = 'Controller di piattaforma (portatili)' }
    @{ Modello = '^NvCpl$';               Stato = 'Consigliato';  Descr = 'Pannello di controllo NVIDIA (impostazioni 3D, schermo, colori)' }
    @{ Modello = '^NvDLISR$';             Stato = 'Consigliato';  Descr = 'DLDSR: risoluzione superiore con l''IA, da attivare nel Pannello NVIDIA' }
    @{ Modello = '^NvVAD$';               Stato = 'Facoltativo';  Descr = 'Audio virtuale usato da registrazione e overlay NVIDIA' }
    @{ Modello = '^NvApp';                Stato = 'Facoltativo';  Descr = 'NVIDIA App (pannello, overlay, aggiornamenti)' }
    @{ Modello = 'Telemetry';             Stato = 'Facoltativo';  Descr = 'Telemetria NVIDIA' }
    @{ Modello = '^FrameViewSDK';         Stato = 'Facoltativo';  Descr = 'FrameView (misura delle prestazioni)' }
    @{ Modello = '^ShadowPlay';           Stato = 'Facoltativo';  Descr = 'Registrazione e overlay' }
    @{ Modello = '^NvBackend';            Stato = 'Facoltativo';  Descr = 'Servizio di aggiornamento automatico' }
    @{ Modello = '^GFExperience';         Stato = 'Facoltativo';  Descr = 'GeForce Experience' }
    @{ Modello = '^NvContainer';          Stato = 'Facoltativo';  Descr = 'Contenitore dei servizi di NVIDIA App' }
    @{ Modello = '^Update\.Core';         Stato = 'Facoltativo';  Descr = 'Aggiornamento automatico' }
    @{ Modello = '^NvCamera';             Stato = 'Facoltativo';  Descr = 'Ansel / fotocamera dei giochi' }
)

function Descrivi-ComponenteNvidia([string]$Nome) {
    foreach ($c in $Script:NvComponenti) { if ($Nome -match $c.Modello) { return $c } }
    return @{ Stato = 'Facoltativo'; Descr = 'Componente aggiuntivo' }
}

# 32.0.16.2124 (versione Windows) -> 621.24 (versione NVIDIA)
function Versione-Nvidia([string]$VersioneWindows) {
    $c = ($VersioneWindows -replace '\.', '')
    if ($c.Length -lt 5) { return $null }
    $c = $c.Substring($c.Length - 5)
    return '{0}.{1}' -f $c.Substring(0, 3), $c.Substring(3)
}

function Marca-Video([string]$Nome, [string]$Produttore) {
    $t = "$Nome $Produttore"
    if ($t -match 'NVIDIA') { return 'NVIDIA' }
    if ($t -match 'AMD|Radeon|Advanced Micro Devices') { return 'AMD' }
    if ($t -match 'Intel') { return 'Intel' }
    return ''
}

# Pagina di supporto giusta per il dispositivo, su qualsiasi PC.
function Pagina-Produttore([string]$Produttore, [string]$Nome, [string]$Classe = '') {
    if ($Classe -eq 'DISPLAY') {
        switch (Marca-Video $Nome $Produttore) {
            'NVIDIA' { return 'https://www.nvidia.com/it-it/drivers/' }
            'AMD'    { return 'https://www.amd.com/it/support/download/drivers.html' }
            'Intel'  { return 'https://www.intel.com/content/www/us/en/support/detect.html' }
        }
    }
    # Per il resto (chipset, audio, Wi-Fi, Bluetooth) la fonte giusta è il supporto del produttore del PC.
    $p = $Script:ProduttorePC
    $m = [uri]::EscapeDataString($Script:ModelloPC)
    if ($p -match 'LENOVO')            { return "https://pcsupport.lenovo.com/search?query=$m" }
    if ($p -match 'HP|Hewlett')        { return 'https://support.hp.com/it-it/drivers' }
    if ($p -match 'Dell|Alienware')    { return 'https://www.dell.com/support/home/it-it?app=drivers' }
    if ($p -match 'ASUS')              { return 'https://www.asus.com/it/support/download-center/' }
    if ($p -match 'Acer')              { return 'https://www.acer.com/it-it/support/drivers-and-manuals' }
    if ($p -match 'Micro-Star|MSI')    { return 'https://it.msi.com/support/download' }
    if ($p -match 'GIGABYTE|AORUS')    { return 'https://www.gigabyte.com/it/Support' }
    if ($p -match 'Microsoft')         { return 'https://support.microsoft.com/surface' }
    if ($p -match 'HUAWEI')            { return 'https://consumer.huawei.com/it/support/' }
    if ($p -match 'SAMSUNG')           { return 'https://www.samsung.com/it/support/' }
    # PC assemblati o produttore non riconosciuto: ricerca del modello sul web.
    $q = [uri]::EscapeDataString(("$p $($Script:ModelloPC) $Nome driver").Trim())
    return "https://www.bing.com/search?q=$q"
}

function Formatta-DataDriver($Data) {
    if ($Data -and $Data.Year -gt 1990) { return $Data.ToString('dd/MM/yyyy') }
    return '—'
}

# Schede video presenti (anche con il driver di base Microsoft). Sola lettura, nessuna connessione.
function Leggi-SchedeVideo {
    $visti = @{}
    $righe = foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceName })) {
        $nome = $d.DeviceName.Trim()
        if ($visti.ContainsKey($nome)) { continue }
        $visti[$nome] = $true
        $marca = Marca-Video $nome ([string]$d.DriverProviderName)
        $base = ([string]$d.DriverProviderName -match '^Microsoft')
        [pscustomobject]@{
            Nome = $nome; Marca = $marca; Produttore = ([string]$d.DriverProviderName).Trim(); Base = $base
            Versione = $(if ($marca -eq 'NVIDIA' -and -not $base) { Versione-Nvidia $d.DriverVersion } else { [string]$d.DriverVersion })
            VersioneWindows = [string]$d.DriverVersion; Data = (Formatta-DataDriver $d.DriverDate); Inf = [string]$d.InfName
            Pagina = (Pagina-Produttore ([string]$d.DriverProviderName) $nome 'DISPLAY')
            IdPci = [string]$d.DeviceID
        }
    }
    return @($righe)
}

# Dispositivi principali con il driver installato (solo lettura, nessuna connessione).
function Leggi-Dispositivi {
    $ordine = @{ 'DISPLAY' = 1; 'MEDIA' = 2; 'NET' = 3; 'BLUETOOTH' = 4; 'SYSTEM' = 5 }
    $utiliSistema = 'Management Engine|Smart Sound|Innovation Platform Framework Manager|Serial IO|Chipset|SMBus|Thunderbolt|Dynamic Tuning|GPIO|PSP|Lenovo|Dell|ASUS|Acer|MSI'
    $virtuali = 'Virtual|TAP-Windows|VPN|mirroring|VAD|Easy Surround|Hyper-V|WAN Miniport'
    $driver = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
        $_.DeviceName -and $_.DriverProviderName -and $_.DriverProviderName -notmatch '^Microsoft' -and $_.DeviceName -notmatch $virtuali -and
        ($ordine.ContainsKey([string]$_.DeviceClass)) -and ($_.DeviceClass -ne 'SYSTEM' -or $_.DeviceName -match $utiliSistema) })
    $visti = @{}
    $righe = foreach ($d in ($driver | Sort-Object { $ordine[[string]$_.DeviceClass] }, DeviceName)) {
        # "Controller - 7F4C", "Controller - 7F4D"... sono lo stesso driver: una riga sola
        $nome = ($d.DeviceName.Trim() -replace '\s+-\s+[0-9A-Fa-f]{4}$', '')
        if ($visti.ContainsKey($nome)) { continue }
        $visti[$nome] = $true
        $nvidia = ($d.DeviceClass -eq 'DISPLAY' -and $nome -match 'NVIDIA')
        [pscustomobject]@{
            Dispositivo = $nome; Produttore = $d.DriverProviderName.Trim(); Data = (Formatta-DataDriver $d.DriverDate)
            Versione = $(if ($nvidia) { Versione-Nvidia $d.DriverVersion } else { $d.DriverVersion }); VersioneWindows = $d.DriverVersion
            Ultima = 'Non controllato'; Fonte = $(if ($nvidia) { 'nvidia.com' } else { 'Windows Update' })
            Pagina = (Pagina-Produttore $d.DriverProviderName $nome ([string]$d.DeviceClass)); Nvidia = $nvidia
            Classe = [string]$d.DeviceClass
        }
    }
    return @($righe)
}

# Codice eseguito in parallelo (non vede le funzioni del programma): chiede a NVIDIA l'elenco dei driver
# per il modello di scheda, dal più recente al più vecchio.
$Script:CodiceCercaNvidia = {
    param($NomeGpu, $Quanti, $Studio, $Windows11)
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $h = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
    $nome = ($NomeGpu -replace '^NVIDIA\s+', '').Trim()
    $r = Invoke-WebRequest -UseBasicParsing -Headers $h -TimeoutSec 30 -Uri 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3'
    $prod = ([xml]$r.Content).LookupValueSearch.LookupValues.LookupValue | Where-Object { ($_.Name -replace '^NVIDIA\s+', '').Trim() -eq $nome } | Select-Object -First 1
    if (-not $prod) { throw "Il modello '$nome' non è nell'elenco dei prodotti NVIDIA." }
    $osId = $(if ($Windows11) { 135 } else { 57 })   # 135 = Windows 11, 57 = Windows 10 a 64 bit
    $crd = $(if ($Studio) { 1 } else { 0 })
    $u = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$($prod.ParentID)&pfid=$($prod.Value)&osID=$osId&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=$crd&qnf=0&sort1=1&numberOfResults=$Quanti"
    $j = (Invoke-WebRequest -UseBasicParsing -Headers $h -TimeoutSec 30 -Uri $u).Content | ConvertFrom-Json
    $visti = @{}
    foreach ($x in @($j.IDS)) {
        $d = $x.downloadInfo
        if (-not $d -or -not $d.Version -or -not $d.DownloadURL -or $visti.ContainsKey([string]$d.Version)) { continue }
        $visti[[string]$d.Version] = $true
        $data = [string]$d.ReleaseDateTime
        try { $data = [datetime]::ParseExact($data, 'ddd MMM dd, yyyy', [cultureinfo]::InvariantCulture).ToString('dd/MM/yyyy') } catch { }
        [pscustomobject]@{ Versione = [string]$d.Version; Data = $data; Nome = [uri]::UnescapeDataString([string]$d.Name)
                           Url = [string]$d.DownloadURL; Dimensione = [string]$d.DownloadURLFileSize }
    }
}

# Codice eseguito in parallelo: legge da amd.com l'elenco dei driver Adrenalin (versione, data, dimensione, link).
# La pagina "driver precedenti" di AMD contiene, per ogni versione, un blocco <article class="... driver-download-details">
# con "Revision Number", "File Size", "Release Date" e il link diretto a drivers.amd.com.
$Script:CodiceCercaAmd = {
    param($Url, $Windows11)
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $Url -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    $html = [string]$r.Content
    $blocchi = [regex]::Split($html, '<article[^>]*driver-download-details[^>]*>')
    $visti = @{}
    foreach ($b in ($blocchi | Select-Object -Skip 1)) {
        $link = [regex]::Match($b, 'href="(https://drivers\.amd\.com/drivers/[^"]+\.exe)"').Groups[1].Value
        if (-not $link -or $link -notmatch 'adrenalin') { continue }
        $os11 = ($link -match 'win11'); $os10 = ($link -match 'win10')
        if ($Windows11 -and -not $os11) { continue }
        if (-not $Windows11 -and -not $os10) { continue }
        $rev  = [regex]::Match($b, 'Revision Number</strong>\s*<p>\s*([^<]+?)\s*</p>').Groups[1].Value
        $dim  = [regex]::Match($b, 'File Size</strong>\s*<p>\s*([^<]+?)\s*</p>').Groups[1].Value
        $data = [regex]::Match($b, 'Release Date</strong>\s*<p>\s*([^<]+?)\s*</p>').Groups[1].Value
        $ver  = [regex]::Match($link, 'edition-(\d+\.\d+\.\d+)').Groups[1].Value
        if (-not $ver -or $visti.ContainsKey($ver)) { continue }
        $visti[$ver] = $true
        try { $data = ([datetime]::ParseExact($data.Trim(), 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)).ToString('dd/MM/yyyy') } catch { }
        [pscustomobject]@{ Versione = $ver; Nome = $rev; Data = $data; Dimensione = $dim; Url = $link
                           Consigliato = ($rev -match 'Recommended'); Facoltativo = ($rev -match 'Optional') }
    }
}

# Pagina AMD da cui leggere l'elenco. AMD pubblica pacchetti diversi per famiglia (verificato su amd.com):
#   RX 7000 / RX 9000 e integrate Radeon 7xxM, 8xxM, 8x0S (RDNA 3/4)  -> pacchetti "...-win11-b.exe"
#   RX 5000 / RX 6000 e integrate Radeon 6xxM (RDNA 1/2)              -> pacchetti "...-win11-a.exe"
#   RX 400/500, Vega, Radeon VII (Polaris/Vega)                        -> pacchetti "...-vega-polaris.exe"
# Le grafiche integrate hanno spesso un nome generico ("AMD Radeon(TM) Graphics": Legion Go, ROG Ally,
# portatili Ryzen). Allora la famiglia si riconosce dal codice del chip (DEV_xxxx) o dal nome del processore,
# e si legge la pagina di un processore con la stessa grafica (verificato su amd.com, 11/2026):
#   RDNA 3 / 3.5 (780M, 760M, 740M, 890M, 880M, 860M, 8060S: Ryzen Z1/Z2 Extreme, 7x40, 8x40, AI 300) -> "-b"
#   RDNA 2 (680M, 660M, 610M, grafica dei Ryzen 7000/9000 desktop, Ryzen Z2 Go)                        -> "-a"
#   Vega (Ryzen 2000-5000 e 7x30 con grafica)                                                           -> "vega-polaris"
$Script:ChipAmdIntegrati = @{
    RDNA3 = @('15BF', '15C8', '1900', '1901', '150E', '1586', '1114')
    RDNA2 = @('1681', '164E', '13C0', '1506')
    Vega  = @('15DD', '15D8', '1636', '1638', '164C', '15E7')
}
function Pagina-VersioniAmd([string]$NomeGpu, [string]$IdPci = '') {
    $n = $NomeGpu
    $base = 'https://www.amd.com/en/support/downloads/previous-drivers.html/graphics'
    $proc = 'https://www.amd.com/en/support/downloads/previous-drivers.html/processors/ryzen'
    $pagRdna3 = "$proc/ryzen-7000-series/amd-ryzen-7-7840u.html"
    $pagRdna2 = "$proc/ryzen-6000-series/amd-ryzen-7-6800u.html"
    $pagVega  = "$proc/ryzen-5000-series/amd-ryzen-5-5625u.html"
    if ($n -match 'RX\s*(4\d\d|5[0-9]{2})(?!\d)|RX\s*Vega|Radeon\s+VII|Vega\s*\d') { return "$base/radeon-600-500-400/radeon-rx-500-series/radeon-rx-570.html" }
    if ($n -match 'RX\s*(7|9)\d{3}|Radeon\s*(7|8)\d{2}M|Radeon\s*8\d{2}0S') { return "$base/radeon-rx/radeon-rx-7000-series/amd-radeon-rx-7800-xt.html" }
    if ($n -match 'RX\s*6\d{3}|Radeon\s*6\d{2}M') { return "$base/radeon-rx/radeon-rx-6000-series/amd-radeon-rx-6600.html" }
    if ($n -match 'RX\s*5\d{3}') { return "$base/radeon-rx/radeon-rx-5000-series/amd-radeon-rx-5700-xt.html" }
    # Nome generico: codice del chip
    $dev = [regex]::Match($IdPci, 'VEN_1002&DEV_([0-9A-Fa-f]{4})').Groups[1].Value.ToUpper()
    if ($dev) {
        if ($Script:ChipAmdIntegrati.RDNA3 -contains $dev) { return $pagRdna3 }
        if ($Script:ChipAmdIntegrati.RDNA2 -contains $dev) { return $pagRdna2 }
        if ($Script:ChipAmdIntegrati.Vega -contains $dev)  { return $pagVega }
    }
    # Ultima possibilità: nome del processore
    if ($n -match 'Radeon.*Graphics') {
        $cpu = ''
        try { $cpu = [string](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name } catch { }
        if ($cpu -match 'Z2 Go') { return $pagRdna2 }
        # Z1, Z1 Extreme, Z2, Z2 Extreme, Ryzen AI, 7x40/8x40 (U, HS, H, F; non HX), 8x00G
        if ($cpu -match 'Ryzen Z1|Ryzen Z2|Ryzen AI|\b[78]\d4\d(U|HS|H|F)?\b|\b8\d00GE?\b') { return $pagRdna3 }
        # 6x00U/H/HS, 7x35, desktop Ryzen 7000/9000, portatili HX
        if ($cpu -match '\b6\d00(U|H|HS|HX)\b|\b7\d35(U|H|HS)\b|\b[79]\d00(X3D|X|F)?\b|\b[79]\d\d5HX\b|\b\d{4}HX3?D?\b') { return $pagRdna2 }
        # Ryzen 2000-5000 con grafica, 7x30U
        if ($cpu -match '\b[2-5]\d00(U|H|HS|G|GE)\b|\b[2-5]\d25U\b|\b7\d30U\b') { return $pagVega }
    }
    return $null
}

# Codice eseguito in parallelo: cerca nel catalogo di Windows Update i driver non installati (non installa niente).
$Script:CodiceCercaWU = {
    $sess = New-Object -ComObject Microsoft.Update.Session
    $sess.ClientApplicationID = 'Regia'
    $r = $sess.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
    foreach ($u in $r.Updates) {
        [pscustomobject]@{ Id = [string]$u.Identity.UpdateID; Titolo = [string]$u.Title; Produttore = [string]$u.DriverManufacturer
                           Modello = [string]$u.DriverModel; Data = $(try { ([datetime]$u.DriverVerDate).ToString('dd/MM/yyyy') } catch { '' })
                           DimensioneMB = [math]::Round($u.MaxDownloadSize / 1MB); Eula = [bool]($u.EulaText -and -not $u.EulaAccepted) }
    }
}

# Codice eseguito in parallelo: scarica e installa UN driver di Windows Update (per ID).
$Script:CodiceInstallaWU = {
    param($Id)
    $sess = New-Object -ComObject Microsoft.Update.Session
    $sess.ClientApplicationID = 'Regia'
    $r = $sess.CreateUpdateSearcher().Search("UpdateID='$Id'")
    if ($r.Updates.Count -eq 0) { throw 'Questo driver non è più disponibile su Windows Update.' }
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $r.Updates) {
        if ($u.EulaText -and -not $u.EulaAccepted) { throw 'Questo driver richiede di accettare una licenza: installalo da Impostazioni > Windows Update > Opzioni avanzate > Aggiornamenti facoltativi.' }
        [void]$coll.Add($u)
    }
    $dl = $sess.CreateUpdateDownloader(); $dl.Updates = $coll
    $d = $dl.Download()
    if ($d.ResultCode -ne 2 -and $d.ResultCode -ne 3) { throw "Download non riuscito (codice $($d.ResultCode))." }
    $inst = $sess.CreateUpdateInstaller(); $inst.Updates = $coll
    $i = $inst.Install()
    [pscustomobject]@{ Esito = [int]$i.ResultCode; Riavvio = [bool]$i.RebootRequired }
}

# Codice eseguito in parallelo: pacchetti driver video di un produttore presenti nell'archivio di Windows.
$Script:CodiceElencaPacchettiVideo = {
    param($Modello)
    Get-WindowsDriver -Online -ErrorAction Stop |
        Where-Object { -not $_.Inbox -and "$($_.ProviderName)" -match $Modello -and ("$($_.ClassName)" -eq 'Display' -or "$($_.OriginalFileName)" -match '\\nvhda[^\\]*\.inf$') } |
        ForEach-Object { [pscustomobject]@{ Inf = [string]$_.Driver; File = [IO.Path]::GetFileName([string]$_.OriginalFileName); Versione = [string]$_.Version; Classe = [string]$_.ClassName } }
}

# Mostra nelle tabelle gli elenchi attuali (senza rileggere niente).
# Le schede video stanno nella sezione "Driver video"; qui restano gli altri dispositivi.
function Mostra-Dispositivi {
    if ($Script:GrigliaDispositivi) { $Script:GrigliaDispositivi.ItemsSource = $null; $Script:GrigliaDispositivi.ItemsSource = @($Script:Dispositivi | Where-Object { $_.Classe -ne 'DISPLAY' }) }
    if ($Script:GrigliaAggiornamenti) {
        $coll = New-Object 'System.Collections.ObjectModel.ObservableCollection[OttWin.RigaAggiornamento]'
        foreach ($a in @($Script:Aggiornamenti)) { $coll.Add($a) }
        $Script:GrigliaAggiornamenti.ItemsSource = $coll
    }
    if ($Script:TestoAggiornamenti) {
        $n = @($Script:Aggiornamenti).Count
        $Script:TestoAggiornamenti.Text = $(if ($n -eq 0) { 'AGGIORNAMENTI DISPONIBILI' } else { "AGGIORNAMENTI DISPONIBILI  ·  $n" })
    }
}

# Nuova riga della tabella degli aggiornamenti (con la casella per sceglierla).
function Nuovo-Aggiornamento([string]$Tipo, [string]$Driver, [string]$Versione, [string]$Data, [string]$Dimensione, [string]$Fonte, [string]$Id) {
    $a = New-Object OttWin.RigaAggiornamento
    $a.Tipo = $Tipo; $a.Driver = $Driver; $a.Versione = $Versione; $a.Data = $Data; $a.Dimensione = $Dimensione; $a.Fonte = $Fonte; $a.Id = $Id
    return $a
}

# Rilegge i driver installati (es. dopo un'installazione) e li mostra.
# Per i dispositivi con la stessa versione di prima mantiene il risultato dell'ultimo controllo.
function Aggiorna-Dispositivi {
    $prima = @{}
    foreach ($d in @($Script:Dispositivi)) { $prima[$d.Dispositivo] = $d }
    $Script:Dispositivi = Leggi-Dispositivi
    foreach ($d in $Script:Dispositivi) {
        $p = $prima[$d.Dispositivo]
        if ($p -and $p.Versione -eq $d.Versione) { $d.Ultima = $p.Ultima }
    }
    $Script:SchedeVideo = Leggi-SchedeVideo
    Mostra-Dispositivi
    if (Get-Command Mostra-SchedeVideo -ErrorAction SilentlyContinue) { Mostra-SchedeVideo }
}

function Scheda-Nvidia { return ($Script:SchedeVideo | Where-Object { $_.Marca -eq 'NVIDIA' -and -not $_.Base } | Select-Object -First 1) }

# Chiede a nvidia.com l'elenco delle versioni e riempie il menu a tendina.
function Cerca-VersioniNvidia {
    $nv = Scheda-Nvidia
    if (-not $nv) { return @() }
    $studio = ($Script:CmbTipoNvidia -and $Script:CmbTipoNvidia.SelectedIndex -eq 1)
    Imposta-Stato 'Chiedo a nvidia.com l''elenco delle versioni del driver...'
    $lista = @(Esegui-InBackground $Script:CodiceCercaNvidia @($nv.Nome, 40, $studio, ($Script:Build -ge 22000)))
    $Script:VersioniNvidia = $lista
    if ($Script:CmbVersioniNvidia) {
        $Script:CmbVersioniNvidia.Items.Clear()
        foreach ($v in $lista) {
            $t = "$($v.Versione)   ·   $($v.Data)"
            if ($v.Versione -eq $nv.Versione) { $t += '   ·   installata adesso' }
            elseif ($lista[0] -and $v.Versione -eq $lista[0].Versione) { $t += '   ·   la più recente' }
            [void]$Script:CmbVersioniNvidia.Items.Add($t)
        }
        if ($lista.Count -eq 0) { [void]$Script:CmbVersioniNvidia.Items.Add($(if ($studio) { 'Nessun driver Studio per questo modello' } else { 'Nessun driver trovato' })) }
        $Script:CmbVersioniNvidia.SelectedIndex = 0
    }
    Scrivi-Log "NVIDIA: trovate $($lista.Count) versioni $(if ($studio) { 'Studio' } else { 'Game Ready' }) per $($nv.Nome)." 'OK'
    return $lista
}

function Scheda-Amd { return ($Script:SchedeVideo | Where-Object { $_.Marca -eq 'AMD' -and -not $_.Base } | Select-Object -First 1) }

# "26.10.2" dal nome del pacchetto Adrenalin installato (il numero di versione Windows del driver è diverso):
# si legge la versione di "AMD Software" registrata tra i programmi installati.
function Versione-Adrenalin {
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { [string]$_.DisplayName -match '^AMD Software' -and $_.DisplayVersion } | Select-Object -First 1
        if ($p) { $m = [regex]::Match([string]$p.DisplayVersion, '^\d+\.\d+\.\d+'); if ($m.Success) { return $m.Value } }
    }
    return ''
}

# Chiede ad amd.com l'elenco delle versioni Adrenalin e riempie il menu a tendina.
function Cerca-VersioniAmd {
    $amd = Scheda-Amd
    if (-not $amd) { return @() }
    $pagina = Pagina-VersioniAmd $amd.Nome $amd.IdPci
    if (-not $pagina) { throw "Per '$($amd.Nome)' ($($amd.IdPci -replace '^.*?(DEV_[0-9A-Fa-f]{4}).*$', '$1')) non c'è un elenco automatico delle versioni: usa 'Installazione pulita da file' con il programma scaricato dal sito AMD o del produttore del PC." }
    Imposta-Stato 'Chiedo ad amd.com l''elenco delle versioni del driver...'
    $lista = @(Esegui-InBackground $Script:CodiceCercaAmd @($pagina, ($Script:Build -ge 22000)))
    $Script:VersioniAmd = $lista
    $installata = Versione-Adrenalin
    if ($Script:CmbVersioniAmd) {
        $Script:CmbVersioniAmd.Items.Clear()
        foreach ($v in $lista) {
            $t = "$($v.Versione)   ·   $($v.Data)"
            if ($v.Consigliato) { $t += '   ·   consigliata (WHQL)' } elseif ($v.Facoltativo) { $t += '   ·   facoltativa' }
            if ($installata -and $v.Versione -eq $installata) { $t += '   ·   installata adesso' }
            [void]$Script:CmbVersioniAmd.Items.Add($t)
        }
        if ($lista.Count -eq 0) { [void]$Script:CmbVersioniAmd.Items.Add('Nessun driver trovato') }
        $Script:CmbVersioniAmd.SelectedIndex = 0
    }
    Scrivi-Log "AMD: trovate $($lista.Count) versioni Adrenalin per $($amd.Nome) (pagina $pagina)." 'OK'
    return $lista
}

# Controlla la versione più recente dei driver video (nvidia.com, amd.com). Non installa niente.
function Controlla-AggiornamentiVideo {
    Blocca-Pulsanti $true
    try {
        Scrivi-Log '--- Controllo aggiornamenti driver video ---'
        $Script:SchedeVideo = Leggi-SchedeVideo
        $Script:UltimaVideo = @{}
        if (Scheda-Nvidia) {
            try {
                if ($Script:CmbTipoNvidia) { $Script:CmbTipoNvidia.SelectedIndex = 0 }
                $nv = Scheda-Nvidia
                $info = @(Cerca-VersioniNvidia)[0]
                if (-not $info) { throw 'NVIDIA non ha restituito driver per questo modello.' }
                $nuovo = ([version]$info.Versione -gt [version]$nv.Versione)
                $Script:UltimaVideo['NVIDIA'] = $(if ($nuovo) { "Disponibile la $($info.Versione) del $($info.Data) (nuova)" } else { "La $($info.Versione) è la più recente: già installata" })
                Scrivi-Log "NVIDIA: installato $($nv.Versione), ultimo disponibile $($info.Versione) del $($info.Data)" 'OK'
            } catch { $Script:UltimaVideo['NVIDIA'] = 'Controllo non riuscito'; Scrivi-Log "Controllo NVIDIA non riuscito: $($_.Exception.Message)" 'ERRORE' }
        }
        if (Scheda-Amd) {
            try {
                $info = @(Cerca-VersioniAmd)[0]
                if (-not $info) { throw 'amd.com non ha restituito driver per questa scheda.' }
                $inst = Versione-Adrenalin
                $nuovo = (-not $inst) -or ([version]$info.Versione -gt [version]$inst)
                $Script:UltimaVideo['AMD'] = $(if ($nuovo) { "Disponibile la $($info.Versione) del $($info.Data)$(if ($inst) { ' (nuova)' })" } else { "La $($info.Versione) è la più recente: già installata" })
                Scrivi-Log "AMD: installato $(if ($inst) { $inst } else { 'sconosciuto' }), ultimo disponibile $($info.Versione) del $($info.Data)" 'OK'
            } catch { $Script:UltimaVideo['AMD'] = 'Controllo non riuscito'; Scrivi-Log "Controllo AMD non riuscito: $($_.Exception.Message)" 'ERRORE' }
        }
        Mostra-SchedeVideo
        Imposta-Stato 'Controllo dei driver video completato: scegli la versione e premi "Installazione pulita".'
    } finally { Blocca-Pulsanti $false }
}

# Controlla gli aggiornamenti degli altri driver nel catalogo di Windows Update. Non installa niente.
function Controlla-AggiornamentiDriver {
    Blocca-Pulsanti $true
    try {
        Scrivi-Log '--- Controllo aggiornamenti driver ---'
        $Script:Dispositivi = Leggi-Dispositivi
        $trovati = New-Object System.Collections.ArrayList
        Imposta-Stato 'Cerco driver nel catalogo di Windows Update (può richiedere un minuto)...'
        try {
            $wu = @(Esegui-InBackground $Script:CodiceCercaWU)
            foreach ($u in $wu) {
                [void]$trovati.Add((Nuovo-Aggiornamento 'WU' $u.Titolo $u.Modello $u.Data "$($u.DimensioneMB) MB" "Windows Update ($($u.Produttore))" $u.Id))
            }
            foreach ($d in $Script:Dispositivi) {
                $m = $wu | Where-Object { $_.Modello -and ($_.Modello -eq $d.Dispositivo -or $_.Titolo -like "*$($d.Dispositivo)*") } | Select-Object -First 1
                $d.Ultima = $(if ($m) { "Aggiornamento del $($m.Data)" } else { 'Nessun aggiornamento' })
            }
            Scrivi-Log "Windows Update: $($wu.Count) driver disponibili." 'OK'
        } catch {
            Scrivi-Log "Ricerca su Windows Update non riuscita: $($_.Exception.Message)" 'ERRORE'
            foreach ($d in $Script:Dispositivi) { $d.Ultima = 'Controllo non riuscito' }
        }
        $Script:Aggiornamenti = @($trovati)
        Mostra-Dispositivi   # solo visualizzazione: rileggere cancellerebbe i risultati appena trovati
        $msg = $(if ($trovati.Count -eq 0) { 'Controllo driver completato: tutti i driver sono aggiornati.' } else { "Controllo driver completato: $($trovati.Count) aggiornamenti disponibili. Accendi quelli che vuoi e premi 'Installa selezionati', oppure 'Installa tutto'." })
        Scrivi-Log $msg 'OK'
        Imposta-Stato $msg
    } finally { Blocca-Pulsanti $false }
}

# Download con BITS (il servizio di Windows usato anche da Windows Update), con avanzamento.
function Scarica-File([string]$Url, [string]$Destinazione, [string]$Descrizione) {
    Import-Module BitsTransfer -ErrorAction Stop
    $parziale = "$Destinazione.part"
    $job = Start-BitsTransfer -Source $Url -Destination $parziale -Asynchronous -DisplayName 'Regia' -Priority Foreground -ErrorAction Stop
    try {
        while (@('Queued', 'Connecting', 'Transferring', 'TransientError') -contains [string]$job.JobState) {
            $tot = [uint64]$job.BytesTotal
            if ($tot -gt 0 -and $tot -ne [uint64]::MaxValue) {
                $perc = [math]::Floor(100 * [double]$job.BytesTransferred / [double]$tot)
                Imposta-Stato ("Download {0}: {1}% ({2} di {3})" -f $Descrizione, $perc, (Formatta-Dimensione ([int64]$job.BytesTransferred)), (Formatta-Dimensione ([int64]$tot)))
                Imposta-Avanzamento $perc
            } else { Imposta-Stato "Download $Descrizione in corso..."; Imposta-Avanzamento -1 }
            for ($i = 0; $i -lt 5; $i++) { Aggiorna-UI; Start-Sleep -Milliseconds 100 }
        }
        if ([string]$job.JobState -ne 'Transferred') { throw "Download non riuscito: $($job.ErrorDescription)" }
        Complete-BitsTransfer -BitsJob $job
        Move-Item -LiteralPath $parziale -Destination $Destinazione -Force
    } catch {
        try { Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue } catch { }
        throw
    }
}

# Download con intestazione "Referer" (richiesta da drivers.amd.com) e barra di avanzamento.
function Scarica-ConReferer([string]$Url, [string]$Destinazione, [string]$Referer, [string]$Descrizione) {
    $parziale = "$Destinazione.part"
    $s = New-Object OttWin.Scaricatore
    $s.Avvia($Url, $parziale, $Referer)
    while (-not $s.Finito) {
        $tot = [int64]$s.Totale; $ric = [int64]$s.Ricevuti
        if ($tot -gt 0) {
            $perc = [math]::Floor(100 * [double]$ric / [double]$tot)
            Imposta-Stato ("Download {0}: {1}% ({2} di {3})" -f $Descrizione, $perc, (Formatta-Dimensione $ric), (Formatta-Dimensione $tot))
            Imposta-Avanzamento $perc
        } else { Imposta-Stato "Download $Descrizione in corso... $(Formatta-Dimensione $ric)"; Imposta-Avanzamento -1 }
        for ($i = 0; $i -lt 5; $i++) { Aggiorna-UI; Start-Sleep -Milliseconds 100 }
    }
    if ($s.Errore) { Remove-Item -LiteralPath $parziale -Force -ErrorAction SilentlyContinue; throw "Download non riuscito: $($s.Errore)" }
    if ([int64]$s.Totale -gt 0 -and [int64]$s.Ricevuti -ne [int64]$s.Totale) { Remove-Item -LiteralPath $parziale -Force -ErrorAction SilentlyContinue; throw 'Download incompleto: riprova.' }
    Move-Item -LiteralPath $parziale -Destination $Destinazione -Force
}

# ---------- Rimozione dei vecchi driver video (con lo strumento ufficiale di Windows pnputil) ----------
# Durante la rimozione Windows Update non deve installare da solo un driver video: questo valore
# (lo stesso usato da "Impostazioni installazione dispositivi") lo ferma, e alla fine viene rimesso com'era.
$Script:ChiaveRicercaDriver = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'

function Blocca-DriverWU {
    $o = Leggi-Registro $Script:ChiaveRicercaDriver 'SearchOrderConfig'
    Scrivi-Registro $Script:ChiaveRicercaDriver 'SearchOrderConfig' 0 'DWord'
    return $o
}

function Sblocca-DriverWU($Originale) {
    try {
        if ($Originale.Esiste) { Scrivi-Registro $Script:ChiaveRicercaDriver 'SearchOrderConfig' $Originale.Valore $Originale.Tipo }
        else { Rimuovi-Registro $Script:ChiaveRicercaDriver 'SearchOrderConfig' }
    } catch { Scrivi-Log "Non sono riuscito a riattivare la ricerca automatica dei driver: $($_.Exception.Message)" 'ERRORE' }
}

# Toglie dai dispositivi e dall'archivio di Windows tutti i pacchetti driver video del produttore
# (anche le vecchie versioni rimaste). Lo schermo passa per un momento al driver di base di Windows.
function Rimuovi-DriverVideo([string]$Modello, [string]$Marca) {
    Imposta-Stato "Cerco i driver $Marca presenti nell'archivio di Windows..."
    $pacchetti = @(Esegui-InBackground $Script:CodiceElencaPacchettiVideo @($Modello))
    $esito = @{ Rimossi = 0; Errori = 0; Riavvio = $false }
    if ($pacchetti.Count -eq 0) { Scrivi-Log "Nessun pacchetto driver $Marca da rimuovere nell'archivio di Windows."; return $esito }
    foreach ($p in $pacchetti) {
        if ($p.Inf -notmatch '^oem\d+\.inf$') { continue }   # sicurezza: solo pacchetti di terze parti (oemNN.inf)
        Imposta-Stato "Rimuovo il vecchio driver $($p.File) $($p.Versione)..."
        $codice = Esegui-Processo "$env:WINDIR\System32\pnputil.exe" "/delete-driver $($p.Inf) /uninstall /force"
        if ($codice -eq 0) { $esito.Rimossi++; Scrivi-Log "  rimosso $($p.Inf) ($($p.File) $($p.Versione))" 'OK' }
        elseif ($codice -eq 3010 -or $codice -eq 1641) { $esito.Rimossi++; $esito.Riavvio = $true; Scrivi-Log "  rimosso $($p.Inf) ($($p.File) $($p.Versione)): si completa al riavvio" 'OK' }
        else { $esito.Errori++; Scrivi-Log "  $($p.Inf) ($($p.File) $($p.Versione)) non rimosso: pnputil ha restituito il codice $codice" 'AVVISO' }
    }
    return $esito
}

function Svuota-CacheShader {
    $v = $Script:Voci['pul.shader']
    if (-not $v) { return }
    $tot = [int64]0
    foreach ($p in $v.Percorsi) { try { $x = Pulisci-Percorso $p; $tot += $x.Byte } catch { } }
    Scrivi-Log "  cache degli shader svuotata ($(Formatta-Dimensione $tot))"
}

# ---------- Finestra "Installazione pulita": procedura, opzioni, componenti ----------
$Script:XamlPulita = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installazione pulita" Width="900" SizeToContent="Height" MaxHeight="820" MinWidth="760" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" ResizeMode="NoResize"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel Margin="28,24,28,20">
    <TextBlock x:Name="Titolo" DockPanel.Dock="Top" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock x:Name="Intro" DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,8,0,16" LineHeight="19"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="BtnIndietro" Content="Torna indietro" IsCancel="True"/>
      <Button x:Name="BtnConferma" Content="Conferma" Style="{DynamicResource Primario}" Margin="4,0,0,0"/>
    </StackPanel>
    <Border DockPanel.Dock="Top" CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}" Padding="18,14">
      <StackPanel>
        <TextBlock Text="PROCEDURA" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}"/>
        <TextBlock x:Name="Passi" TextWrapping="Wrap" Margin="0,8,0,0" LineHeight="21"/>
        <DockPanel Margin="0,14,0,0">
          <TextBlock DockPanel.Dock="Left" Text="Vecchi driver" VerticalAlignment="Center" Width="110" Foreground="{DynamicResource Testo2}"/>
          <ComboBox x:Name="Modo" SelectedIndex="0">
            <ComboBoxItem Content="Rimozione completa: toglie i vecchi driver anche dall'archivio di Windows"/>
            <ComboBoxItem Content="Standard: solo l'installazione pulita del produttore"/>
          </ComboBox>
        </DockPanel>
        <CheckBox x:Name="ChkCache" IsChecked="True" Margin="110,12,0,0" Content="Svuota anche la cache degli shader (consigliato quando cambi versione)"/>
        <CheckBox x:Name="ChkTutto" Margin="110,10,0,0" Content="Installa il pacchetto completo, senza togliere niente (compresa NVIDIA App)"/>
      </StackPanel>
    </Border>
    <StackPanel x:Name="PannelloComponenti" Margin="0,16,0,0">
      <TextBlock Text="COMPONENTI DA INSTALLARE" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}" Margin="2,0,0,8"/>
      <Border CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}" Padding="1">
        <DataGrid x:Name="Lista" AutoGenerateColumns="False" MaxHeight="300" EnableRowVirtualization="False">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="" Width="54" CanUserResize="False">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding Includi, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" IsEnabled="{Binding Modificabile}"
                            Style="{DynamicResource InterruttorePiccolo}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="COMPONENTE" Binding="{Binding Nome}" Width="1.2*" IsReadOnly="True"/>
            <DataGridTextColumn Header="TIPO" Binding="{Binding Stato}" Width="0.7*" IsReadOnly="True"/>
            <DataGridTextColumn Header="A COSA SERVE" Binding="{Binding Descrizione}" Width="2.4*" IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>
    </StackPanel>
  </DockPanel>
</Window>
'@

# Mostra la finestra. $Componenti = elenco di OttWin.RigaComponente oppure $null (nessuna scelta dei componenti).
# Restituisce $null se l'utente torna indietro, altrimenti @{ Completa; Cache; Tutto }.
function Chiedi-InstallazionePulita([string]$Titolo, [string]$Intro, [string]$Marca, $Componenti, [string]$TestoConferma) {
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlPulita)
    Applica-TemaFinestra $w
    $w.Owner = $Script:Finestra
    $w.Title = $Titolo
    $w.FindName('Titolo').Text = $Titolo
    $w.FindName('Intro').Text = $Intro
    $w.FindName('Passi').Text = "1.  Punto di ripristino di Windows (per poter tornare indietro)`n" +
        "2.  Rimozione dei driver $Marca presenti, comprese le vecchie versioni rimaste nell'archivio di Windows`n" +
        "3.  Installazione del driver scelto con l'opzione di installazione pulita del produttore`n" +
        "4.  Verifica della versione installata.  Lo schermo può diventare nero o cambiare risoluzione per qualche secondo: è normale."
    if ($Componenti) {
        $w.FindName('Lista').ItemsSource = $Componenti
        $w.FindName('ChkTutto').add_Click({ $f = [System.Windows.Window]::GetWindow($this); $f.FindName('Lista').IsEnabled = -not $this.IsChecked; $f.FindName('Lista').Opacity = $(if ($this.IsChecked) { 0.4 } else { 1 }) })
    } else {
        $w.FindName('PannelloComponenti').Visibility = 'Collapsed'
        $w.FindName('ChkTutto').Visibility = 'Collapsed'
    }
    $b = $w.FindName('BtnConferma')
    $b.Content = $TestoConferma
    $b.add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    if ($w.ShowDialog() -ne $true) { return $null }
    return @{ Completa = ($w.FindName('Modo').SelectedIndex -eq 0); Cache = [bool]$w.FindName('ChkCache').IsChecked; Tutto = [bool]$w.FindName('ChkTutto').IsChecked }
}

# Installazione pulita del driver NVIDIA (versione scelta dall'utente: nuova, uguale o precedente).
function Installa-DriverNvidia($Agg) {
    $url = [string]$Agg.Url
    if ($url -notmatch '^https://([a-z0-9-]+\.)*nvidia\.com/') { throw "Indirizzo di download non riconosciuto come NVIDIA: $url" }
    $nomeFile = [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
    $cartella = Join-Path $Script:CartellaDriver ('NVIDIA_' + $Agg.Versione)
    $file = Join-Path $cartella $nomeFile
    $nvPrima = Scheda-Nvidia
    $installata = $(if ($nvPrima) { [string]$nvPrima.Versione } else { '' })
    $confronto = ''
    try {
        if ($installata) {
            if ([version]$Agg.Versione -lt [version]$installata) { $confronto = " È una versione PRECEDENTE a quella installata ($installata): Windows Update o NVIDIA App potrebbero riproporre in seguito quella più recente." }
            elseif ([version]$Agg.Versione -eq [version]$installata) { $confronto = " È la STESSA versione già installata: verrà reinstallata da zero." }
        }
    } catch { }

    if (-not (Test-Path -LiteralPath $file)) {
        $r = Mostra-Messaggio ("Scaricare il driver NVIDIA $($Agg.Versione)?`n`nFile: $nomeFile`nFonte: $(([uri]$url).Host)`nDimensione: $($Agg.Dimensione)`nCartella: Dati\Driver`n`nDopo il download vedrai la procedura e i componenti, e deciderai se installare.") 'Download driver NVIDIA' 'YesNo' 'Information'
        if ($r -ne 'Yes') { return }
        New-Item -ItemType Directory -Force -Path $cartella | Out-Null
        Scrivi-Log "Download driver NVIDIA $($Agg.Versione) da $url"
        Scarica-File $url $file "driver NVIDIA $($Agg.Versione)"
        Scrivi-Log "Download completato: $file" 'OK'
    }

    # La firma digitale deve essere valida e intestata a NVIDIA, altrimenti il file non si usa.
    $firma = Get-AuthenticodeSignature -LiteralPath $file
    if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'NVIDIA Corporation') {
        throw "La firma digitale del file non è valida o non è di NVIDIA (stato: $($firma.Status)). Il file NON verrà usato: $file"
    }
    Scrivi-Log "Firma digitale verificata: $($firma.SignerCertificate.Subject)" 'OK'

    # Estrazione con tar.exe di Windows (legge il formato 7-Zip del pacchetto NVIDIA)
    $estratti = Join-Path $cartella 'pacchetto'
    if (Test-Path -LiteralPath $estratti) { Remove-Item -LiteralPath $estratti -Recurse -Force }
    New-Item -ItemType Directory -Path $estratti | Out-Null
    Imposta-Stato 'Estraggo il pacchetto del driver...'
    $tar = "$env:WINDIR\System32\tar.exe"
    $codice = $(if (Test-Path -LiteralPath $tar) { Esegui-Processo $tar ("-xf `"$file`" -C `"$estratti`"") } else { -1 })
    if ($codice -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $estratti 'setup.exe'))) {
        throw "Estrazione non riuscita (codice $codice). Puoi installare il driver avviando $file e scegliendo 'Personalizzata' > 'Esegui un'installazione pulita'."
    }
    $cartelle = @(Get-ChildItem -LiteralPath $estratti -Directory)
    if (-not ($cartelle | Where-Object { $_.Name -eq 'Display.Driver' })) { throw 'Nel pacchetto manca Display.Driver: formato non riconosciuto, installazione annullata.' }

    $componenti = New-Object 'System.Collections.Generic.List[OttWin.RigaComponente]'
    foreach ($c in ($cartelle | Sort-Object { @('Obbligatorio', 'Consigliato', 'Facoltativo').IndexOf((Descrivi-ComponenteNvidia $_.Name).Stato) }, Name)) {
        $d = Descrivi-ComponenteNvidia $c.Name
        $r = New-Object OttWin.RigaComponente
        $r.Nome = $c.Name; $r.Stato = $d.Stato; $r.Descrizione = $d.Descr
        $r.Includi = ($d.Stato -ne 'Facoltativo'); $r.Modificabile = ($d.Stato -ne 'Obbligatorio')
        $componenti.Add($r)
    }

    $prova = [bool]$Script:ChkProva.IsChecked
    $intro = "Driver NVIDIA $($Agg.Versione) scaricato e verificato (firma digitale NVIDIA valida).$confronto`n" +
             "Le impostazioni del Pannello NVIDIA tornano ai valori di serie: dopo potrai riapplicarle dalla sezione NVIDIA. Se torni indietro i file restano pronti in Dati\Driver."
    if ($prova) { $intro = "MODALITÀ PROVA: il driver non verrà rimosso né installato.`n`n" + $intro }
    $scelta = Chiedi-InstallazionePulita "Installazione pulita NVIDIA $($Agg.Versione)" $intro 'NVIDIA' $componenti $(if ($prova) { 'Simula (modalità prova)' } else { 'Avvia installazione pulita' })
    if (-not $scelta) {
        Scrivi-Log 'Installazione NVIDIA annullata dall''utente (file pronti nella cartella Dati\Driver).'
        Imposta-Stato 'Installazione annullata: nessuna modifica.'
        return
    }
    $tenuti = @($componenti | Where-Object { $scelta.Tutto -or $_.Includi })
    $tolti  = @($componenti | Where-Object { -not $scelta.Tutto -and -not $_.Includi })
    $modo = $(if ($scelta.Completa) { 'rimozione completa dei vecchi driver' } else { 'standard' })
    if ($prova) {
        Scrivi-Log "Installazione pulita NVIDIA $($Agg.Versione) ($modo; cache shader: $($scelta.Cache)). Tenuti: $(($tenuti | ForEach-Object Nome) -join ', '). Tolti: $(($tolti | ForEach-Object Nome) -join ', ')" 'PROVA'
        if ($scelta.Completa) {
            try { foreach ($p in @(Esegui-InBackground $Script:CodiceElencaPacchettiVideo @('NVIDIA'))) { Scrivi-Log "Rimuoverei dall'archivio di Windows: $($p.Inf) ($($p.File) $($p.Versione))" 'PROVA' } }
            catch { Scrivi-Log "Elenco dei vecchi driver non disponibile: $($_.Exception.Message)" 'AVVISO' }
        }
        Imposta-Stato 'Modalità prova: niente è stato rimosso o installato.'
        [void](Mostra-Messaggio "Modalità prova: il driver NON è stato toccato.`nNel log trovi i componenti scelti e i vecchi driver che verrebbero rimossi; i file sono pronti in Dati\Driver." 'Modalità prova')
        return
    }

    if (-not $scelta.Tutto) {
        # Componenti esclusi: cancellati SOLO dalla cartella estratta (il PC non viene toccato)
        foreach ($c in $tolti) { Remove-Item -LiteralPath (Join-Path $estratti $c.Nome) -Recurse -Force; Scrivi-Log "  componente escluso: $($c.Nome)" }
        # setup.cfg: tolte le righe che richiedono i file di consenso/telemetria esclusi
        $cfg = Join-Path $estratti 'setup.cfg'
        if (Test-Path -LiteralPath $cfg) {
            $lettore = New-Object System.IO.StreamReader($cfg, $true); $testo = $lettore.ReadToEnd(); $codifica = $lettore.CurrentEncoding; $lettore.Close()
            $nuovo = ($testo -split "`r?`n" | Where-Object { $_ -notmatch 'EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile' }) -join "`r`n"
            [IO.File]::WriteAllText($cfg, $nuovo, $codifica)
        }
    }

    if (-not (Crea-PuntoRipristino)) { Scrivi-Log 'Installazione NVIDIA annullata: punto di ripristino non creato.' 'AVVISO'; return }
    Blocca-Pulsanti $true
    $wu = $null; $testoRiavvio = ''
    try {
        Scrivi-Log "--- Installazione pulita NVIDIA $($Agg.Versione) ($modo) ---"
        $riavvio = $false
        if ($scelta.Completa) {
            $wu = Blocca-DriverWU
            $rim = Rimuovi-DriverVideo 'NVIDIA' 'NVIDIA'
            $riavvio = $rim.Riavvio
            Scrivi-Log "Vecchi driver NVIDIA rimossi: $($rim.Rimossi), non rimossi: $($rim.Errori)." $(if ($rim.Errori -gt 0) { 'AVVISO' } else { 'OK' })
        }
        if ($scelta.Cache) { Svuota-CacheShader }
        Imposta-Stato 'Installazione del driver NVIDIA in corso (qualche minuto, lo schermo può lampeggiare)...'
        Scrivi-Log 'Avvio: setup.exe -s -clean -noreboot -noeula'
        $codice = Esegui-Processo (Join-Path $estratti 'setup.exe') '-s -clean -noreboot -noeula'
        Scrivi-Log "Installazione NVIDIA terminata con codice $codice" $(if ($codice -eq 0) { 'OK' } else { 'AVVISO' })
        $Script:Aggiornamenti = @($Script:Aggiornamenti | Where-Object { $_.Tipo -ne 'NVIDIA' })
        Aggiorna-Dispositivi
        $nvOra = Scheda-Nvidia
        $riuscita = [bool]($nvOra -and $nvOra.Versione -eq $Agg.Versione)
        if ($riuscita) { $esito = "Driver NVIDIA $($Agg.Versione) installato correttamente." }
        else {
            $esito = "L'installazione è terminata con codice $codice, ma la versione rilevata adesso è: $(if ($nvOra) { $nvOra.Versione } else { 'nessun driver NVIDIA' }).`n" +
                     "Riavvia il PC e controlla di nuovo. Se il driver manca, avvia a mano il file scaricato:`n$file`noppure usa il punto di ripristino creato poco fa."
        }
        Scrivi-Log ($esito -replace "`n", ' ') $(if ($riuscita) { 'OK' } else { 'ERRORE' })
        if (-not $riuscita) { [void](Mostra-Messaggio $esito 'Driver NVIDIA' 'OK' 'Warning'); return }
        $r = Mostra-Messaggio "$esito`n`nVuoi eliminare i file scaricati ed estratti (cartella Dati\Driver\NVIDIA_$($Agg.Versione))?" 'Driver NVIDIA' 'YesNo' 'Information'
        if ($r -eq 'Yes') { Remove-Item -LiteralPath $cartella -Recurse -Force -ErrorAction SilentlyContinue; Scrivi-Log "File del driver eliminati: $cartella" }
        Imposta-Stato "Driver NVIDIA $($Agg.Versione) installato. Riavvia il PC."
        Segna-Riavvio "Driver NVIDIA $($Agg.Versione) installato."
        $testoRiavvio = "Driver NVIDIA $($Agg.Versione) installato. Il riavvio completa l'installazione$(if ($riavvio) { ' ed è necessario: alcuni vecchi file vengono tolti solo al riavvio' } else { '' })."
    } finally {
        # Windows Update viene sbloccato PRIMA dell'eventuale riavvio.
        if ($null -ne $wu) { Sblocca-DriverWU $wu }
        Blocca-Pulsanti $false
    }
    if ($testoRiavvio) { [void](Proponi-Riavvio $testoRiavvio 'Driver NVIDIA') }
}

# Avvia l'installazione pulita della versione scelta nel menu a tendina.
function Installa-VersioneNvidiaScelta {
    $i = $(if ($Script:CmbVersioniNvidia) { $Script:CmbVersioniNvidia.SelectedIndex } else { -1 })
    if (@($Script:VersioniNvidia).Count -eq 0 -or $i -lt 0 -or $i -ge @($Script:VersioniNvidia).Count) {
        [void](Mostra-Messaggio "Premi prima 'Cerca versioni': il programma chiede a nvidia.com l'elenco dei driver disponibili per la tua scheda, poi scegli la versione dal menu." 'Scegli la versione')
        return
    }
    $v = @($Script:VersioniNvidia)[$i]
    $nv = Scheda-Nvidia
    Installa-DriverNvidia ([pscustomobject]@{ Tipo = 'NVIDIA'; Driver = "$($v.Nome) per $($nv.Nome)"; Versione = $v.Versione; Data = $v.Data
        Dimensione = $v.Dimensione; Fonte = 'nvidia.com'; Url = $v.Url; Id = '' })
}

# AMD / Intel: installazione pulita partendo dal programma di installazione scaricato dal sito ufficiale.
function Installa-DriverDaFile($Scheda) {
    if (@('AMD', 'Intel') -notcontains $Scheda.Marca) { return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Scegli il programma di installazione del driver $($Scheda.Marca) scaricato dal sito ufficiale"
    $dlg.Filter = 'Programmi di installazione (*.exe)|*.exe'
    $scaricati = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $scaricati) { $dlg.InitialDirectory = $scaricati }
    if ($dlg.ShowDialog($Script:Finestra) -ne $true) { return }
    Installa-DriverVideoDaFile $Scheda $dlg.FileName
}

# Installazione pulita AMD della versione scelta nel menu: download da drivers.amd.com, poi come da file.
function Installa-VersioneAmdScelta {
    $amd = Scheda-Amd
    $i = $(if ($Script:CmbVersioniAmd) { $Script:CmbVersioniAmd.SelectedIndex } else { -1 })
    if (-not $amd -or @($Script:VersioniAmd).Count -eq 0 -or $i -lt 0 -or $i -ge @($Script:VersioniAmd).Count) {
        [void](Mostra-Messaggio "Premi prima 'Cerca versioni': il programma chiede ad amd.com l'elenco dei driver per la tua scheda, poi scegli la versione dal menu." 'Scegli la versione')
        return
    }
    $v = @($Script:VersioniAmd)[$i]
    $url = [string]$v.Url
    if ($url -notmatch '^https://drivers\.amd\.com/drivers/[^/]+\.exe$') { throw "Indirizzo di download non riconosciuto come AMD: $url" }
    $nomeFile = [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
    $cartella = Join-Path $Script:CartellaDriver ('AMD_' + $v.Versione)
    $file = Join-Path $cartella $nomeFile
    if (-not (Test-Path -LiteralPath $file)) {
        $r = Mostra-Messaggio ("Scaricare il driver AMD $($v.Versione)?`n`nFile: $nomeFile`nFonte: drivers.amd.com`nDimensione: $($v.Dimensione)`nCartella: Dati\Driver`n`nScaricando accetti i termini di licenza di AMD per il software (gli stessi del sito amd.com).`nDopo il download vedrai la procedura e deciderai se installare.") 'Download driver AMD' 'YesNo' 'Information'
        if ($r -ne 'Yes') { return }
        New-Item -ItemType Directory -Force -Path $cartella | Out-Null
        Blocca-Pulsanti $true
        try {
            Scrivi-Log "Download driver AMD $($v.Versione) da $url"
            Scarica-ConReferer $url $file 'https://www.amd.com/' "driver AMD $($v.Versione)"
            Scrivi-Log "Download completato: $file" 'OK'
        } finally { Blocca-Pulsanti $false }
    }
    Installa-DriverVideoDaFile $amd $file $v.Versione
}

# Installazione pulita AMD / Intel da un programma di installazione già scaricato (firma verificata).
function Installa-DriverVideoDaFile($Scheda, [string]$File, [string]$Versione = '') {
    $attesa = switch ($Scheda.Marca) { 'AMD' { 'Advanced Micro Devices' } 'Intel' { 'Intel' } default { $null } }
    if (-not $attesa) { return }
    $modello = $(if ($Scheda.Marca -eq 'AMD') { 'Advanced Micro Devices|AMD' } else { '^Intel' })
    $file = $File
    $firma = Get-AuthenticodeSignature -LiteralPath $file
    if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch $attesa) {
        throw "La firma digitale del file non è valida o non è di $($Scheda.Marca) (stato: $($firma.Status)). Il file NON verrà usato: $file"
    }
    Scrivi-Log "Firma digitale verificata: $($firma.SignerCertificate.Subject)" 'OK'

    $prova = [bool]$Script:ChkProva.IsChecked
    $intro = "File: $([IO.Path]::GetFileName($file))  (firma digitale $($Scheda.Marca) valida)`nDispositivo: $($Scheda.Nome), driver attuale $($Scheda.Versione).`n" +
             "Dopo la rimozione dei vecchi driver si apre il programma di installazione del produttore: segui le sue istruzioni$(if ($Scheda.Marca -eq 'AMD') { " (se lo propone, scegli 'Ripristino impostazioni di fabbrica')" } else { " (se lo propone, spunta 'Installazione pulita')" })."
    if ($prova) { $intro = "MODALITÀ PROVA: il driver non verrà rimosso né installato.`n`n" + $intro }
    $scelta = Chiedi-InstallazionePulita "Installazione pulita driver $($Scheda.Marca)" $intro $Scheda.Marca $null $(if ($prova) { 'Simula (modalità prova)' } else { 'Avvia installazione pulita' })
    if (-not $scelta) { Imposta-Stato 'Installazione annullata: nessuna modifica.'; return }
    if ($prova) {
        Scrivi-Log "Installazione pulita $($Scheda.Marca) da $file (rimozione completa: $($scelta.Completa); cache shader: $($scelta.Cache))" 'PROVA'
        if ($scelta.Completa) {
            try { foreach ($p in @(Esegui-InBackground $Script:CodiceElencaPacchettiVideo @($modello))) { Scrivi-Log "Rimuoverei dall'archivio di Windows: $($p.Inf) ($($p.File) $($p.Versione))" 'PROVA' } }
            catch { Scrivi-Log "Elenco dei vecchi driver non disponibile: $($_.Exception.Message)" 'AVVISO' }
        }
        [void](Mostra-Messaggio 'Modalità prova: il driver NON è stato toccato. Le operazioni sono scritte nel log.' 'Modalità prova')
        return
    }
    if (-not (Crea-PuntoRipristino)) { return }
    Blocca-Pulsanti $true
    $wu = $null; $testoRiavvio = ''
    try {
        Scrivi-Log "--- Installazione pulita driver $($Scheda.Marca) da $file ---"
        if ($scelta.Completa) {
            $wu = Blocca-DriverWU
            $rim = Rimuovi-DriverVideo $modello $Scheda.Marca
            Scrivi-Log "Vecchi driver $($Scheda.Marca) rimossi: $($rim.Rimossi), non rimossi: $($rim.Errori)." $(if ($rim.Errori -gt 0) { 'AVVISO' } else { 'OK' })
        }
        if ($scelta.Cache) { Svuota-CacheShader }
        Imposta-Stato "Programma di installazione $($Scheda.Marca) aperto: completa l'installazione nella sua finestra..."
        $codice = Esegui-Processo $file '' $true
        Scrivi-Log "Programma di installazione $($Scheda.Marca) chiuso con codice $codice" $(if ($codice -eq 0) { 'OK' } else { 'AVVISO' })
        Aggiorna-Dispositivi
        Segna-Riavvio "Driver $($Scheda.Marca) installato."
        $testoRiavvio = "Il programma di installazione $($Scheda.Marca) si è chiuso (codice $codice).`nControlla la versione nella tabella; il riavvio completa l'installazione."
    } finally {
        if ($null -ne $wu) { Sblocca-DriverWU $wu }
        Blocca-Pulsanti $false
    }
    if ($testoRiavvio) { [void](Proponi-Riavvio $testoRiavvio "Driver $($Scheda.Marca)") }
}

# Installazione di un driver dal catalogo di Windows Update.
function Installa-DriverWU($Agg) {
    $r = Mostra-Messaggio "Installare questo driver da Windows Update?`n`n$($Agg.Driver)`nDimensione: $($Agg.Dimensione)`n`nPrima verrà creato un punto di ripristino." 'Driver da Windows Update' 'YesNo' 'Information'
    if ($r -ne 'Yes') { return }
    if ($Script:ChkProva.IsChecked) {
        Scrivi-Log "Installerei da Windows Update: $($Agg.Driver)" 'PROVA'
        [void](Mostra-Messaggio 'Modalità prova: il driver NON è stato installato. L''operazione è scritta nel log.' 'Modalità prova')
        return
    }
    if (-not (Crea-PuntoRipristino)) { return }
    Blocca-Pulsanti $true
    $chiediRiavvio = $false
    try {
        Imposta-Stato "Scarico e installo: $($Agg.Driver)..."
        Scrivi-Log "Installazione da Windows Update: $($Agg.Driver)"
        $esito = @(Esegui-InBackground $Script:CodiceInstallaWU @($Agg.Id))[0]
        $ok = ($esito.Esito -eq 2 -or $esito.Esito -eq 3)
        Scrivi-Log "Windows Update: esito $($esito.Esito), riavvio necessario: $($esito.Riavvio)" $(if ($ok) { 'OK' } else { 'ERRORE' })
        $Script:Aggiornamenti = @($Script:Aggiornamenti | Where-Object { $_.Id -ne $Agg.Id })
        Aggiorna-Dispositivi
        $testo = $(if ($ok) { 'Driver installato.' } else { "Installazione non riuscita (codice $($esito.Esito))." })
        $chiediRiavvio = ($ok -and $esito.Riavvio)
        if ($chiediRiavvio) { Segna-Riavvio "Driver da Windows Update: $($Agg.Driver)." }
        else { [void](Mostra-Messaggio $testo 'Driver da Windows Update' 'OK' $(if ($ok) { 'Information' } else { 'Warning' })) }
    } finally { Blocca-Pulsanti $false }
    if ($chiediRiavvio) { [void](Proponi-Riavvio "$testo`nServe un riavvio per completare l'installazione." 'Driver da Windows Update') }
}

# Installa più driver di Windows Update uno dopo l'altro: una sola conferma e un solo punto di ripristino.
#   $Tutti = $true: tutti quelli in elenco;  $false: solo quelli con la casella accesa.
function Installa-DriverWUMultipli([bool]$Tutti) {
    $lista = @($Script:Aggiornamenti | Where-Object { $_.Tipo -eq 'WU' -and ($Tutti -or $_.Selezionato) })
    if ($lista.Count -eq 0) {
        [void](Mostra-Messaggio $(if ($Tutti) { "Non ci sono aggiornamenti in elenco: premi prima 'Controlla aggiornamenti'." } else { "Accendi la casella dei driver che vuoi installare, poi premi 'Installa selezionati'." }) 'Installa driver')
        return
    }
    $elenco = ($lista | ForEach-Object { "•  $($_.Driver)  ($($_.Dimensione))" }) -join "`n"
    $r = Mostra-Messaggio "Installare $($lista.Count) driver da Windows Update?`n`n$elenco`n`nPrima verrà creato un punto di ripristino; poi i driver vengono scaricati e installati uno alla volta." 'Installa driver' 'YesNo' 'Information'
    if ($r -ne 'Yes') { return }
    if ($Script:ChkProva.IsChecked) {
        foreach ($a in $lista) { Scrivi-Log "Installerei da Windows Update: $($a.Driver)" 'PROVA' }
        [void](Mostra-Messaggio "Modalità prova: nessun driver è stato installato. Le $($lista.Count) operazioni sono scritte nel log." 'Modalità prova')
        return
    }
    if (-not (Crea-PuntoRipristino)) { return }
    Blocca-Pulsanti $true
    $ok = 0; $errori = 0; $riavvio = $false; $i = 0
    try {
        Scrivi-Log "--- Installazione di $($lista.Count) driver da Windows Update ---"
        foreach ($a in $lista) {
            $i++
            Imposta-Stato "Driver $i di $($lista.Count): scarico e installo $($a.Driver)..."
            Imposta-Avanzamento (100 * ($i - 1) / $lista.Count)
            try {
                $esito = @(Esegui-InBackground $Script:CodiceInstallaWU @($a.Id))[0]
                if ($esito.Esito -eq 2 -or $esito.Esito -eq 3) {
                    $ok++; if ($esito.Riavvio) { $riavvio = $true }
                    Scrivi-Log "Installato: $($a.Driver) (esito $($esito.Esito), riavvio: $($esito.Riavvio))" 'OK'
                    $Script:Aggiornamenti = @($Script:Aggiornamenti | Where-Object { $_.Id -ne $a.Id })
                } else { $errori++; Scrivi-Log "Non installato: $($a.Driver) (codice $($esito.Esito))" 'ERRORE' }
            } catch { $errori++; Scrivi-Log "Non installato: $($a.Driver): $($_.Exception.Message)" 'ERRORE' }
        }
        Imposta-Avanzamento 100
        Aggiorna-Dispositivi
        $msg = "Driver installati: $ok.  Non riusciti: $errori.$(if ($riavvio) { "`nServe un riavvio per completare l'installazione." } else { '' })$(if ($errori -gt 0) { "`nI dettagli sono nel Registro attività." } else { '' })"
        Scrivi-Log ($msg -replace "`n", ' ') $(if ($errori -gt 0) { 'AVVISO' } else { 'OK' })
        if ($riavvio) { Segna-Riavvio "$ok driver da Windows Update installati." }
        else { [void](Mostra-Messaggio $msg 'Installa driver' 'OK' $(if ($errori -gt 0) { 'Warning' } else { 'Information' })) }
    } finally { Blocca-Pulsanti $false }
    if ($riavvio) { [void](Proponi-Riavvio $msg 'Installa driver') }
}

function Leggi-InfoSistema {
    try {
        $os  = Get-CimInstance Win32_OperatingSystem
        $cs  = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpu = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ' + '
        $ver = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        $batTxt = $(if ($bat) { "portatile, batteria al $($bat.EstimatedChargeRemaining)%" } else { 'desktop' })
        return ('{0} {1} (build {2})   ·   {3}   ·   {4}   ·   RAM {5} GB   ·   {6}' -f $os.Caption.Replace('Microsoft ', ''), $ver, $os.BuildNumber, $cpu.Name.Trim(), $gpu, [math]::Round($cs.TotalPhysicalMemory / 1GB), $batTxt)
    } catch { return 'Informazioni di sistema non disponibili' }
}

# ==============================================================================
# 7. INTERFACCIA GRAFICA
# ==============================================================================

# Riga della tabella (classe C# perché le caselle si aggiornino subito sullo schermo).
if (-not ('OttWin.RigaVoce' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System.ComponentModel;
namespace OttWin
{
    public class RigaVoce : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Notifica(string nome)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(nome));
        }
        private bool _selezionata;
        public bool Selezionata
        {
            get { return _selezionata; }
            set { if (_selezionata != value) { _selezionata = value; Notifica("Selezionata"); } }
        }
        private string _attuale;
        public string Attuale { get { return _attuale; } set { _attuale = value; Notifica("Attuale"); Notifica("AttualeVis"); } }
        private string _esito;
        public string Esito { get { return _esito; } set { _esito = value; Notifica("Esito"); Notifica("EsitoVis"); } }
        // Versioni tradotte per lo schermo (i valori originali restano in italiano: servono alla logica del programma)
        public static System.Func<string, string> Tr;
        private static string T(string s) { return (Tr != null && s != null) ? Tr(s) : s; }
        public string AttualeVis { get { return T(_attuale); } }
        public string EsitoVis { get { return T(_esito); } }
        public string NomeVis { get { return T(Nome); } }
        public string ConsigliatoVis { get { return T(Consigliato); } }
        public string PredefinitoVis { get { return T(Predefinito); } }
        public string AreaVis { get { return T(Area); } }
        public string CategoriaVis { get { return T(Categoria); } }
        public string RischioVis { get { return T(Rischio); } }
        public string Id { get; set; }
        public string Nome { get; set; }
        public string Categoria { get; set; }
        public string Consigliato { get; set; }
        public string Predefinito { get; set; }
        public string Rischio { get; set; }
        public string Gruppo { get; set; }

        // --- Righe con menu a tendina (impostazioni NVIDIA) ---
        public string Area { get; set; }
        public string ValoreAttuale { get; set; }
        public string ValorePredefinito { get; set; }
        public string EsitoBase { get; set; }
        public System.Collections.Generic.List<OpzioneVoce> Opzioni { get; set; }
        private OpzioneVoce _scelta;
        // Scegliere un valore diverso da quello attuale "accende" la riga (da applicare).
        public OpzioneVoce Scelta
        {
            get { return _scelta; }
            set
            {
                if (value == null || _scelta == value) return;
                _scelta = value;
                Notifica("Scelta");
                if (Opzioni != null)
                {
                    Selezionata = value.Valore != ValoreAttuale;
                    Esito = Selezionata ? "Da applicare" : EsitoBase;
                }
            }
        }

        // --- Voci di Windows con più scelte: menu "Da applicare" ---
        private System.Collections.Generic.List<OpzioneVoce> _scelte;
        public System.Collections.Generic.List<OpzioneVoce> Scelte
        {
            get { return _scelte; }
            set { _scelte = value; Notifica("Scelte"); Notifica("HaScelte"); }
        }
        public bool HaScelte { get { return _scelte != null && _scelte.Count > 1; } }
        private OpzioneVoce _sceltaVoce;
        // Cambiare la scelta dal menu accende la voce (la prima impostazione, fatta dal programma, no).
        public OpzioneVoce SceltaVoce
        {
            get { return _sceltaVoce; }
            set
            {
                if (value == null || _sceltaVoce == value) return;
                bool primaVolta = _sceltaVoce == null;
                _sceltaVoce = value;
                Notifica("SceltaVoce");
                if (!primaVolta) Selezionata = true;
            }
        }
        public void ImpostaSceltaSenzaAccendere(OpzioneVoce valore)
        {
            if (valore == null) return;
            _sceltaVoce = valore;
            Notifica("SceltaVoce");
        }
    }

    // Una riga della tabella "Aggiornamenti disponibili" (con la casella per sceglierla).
    public class RigaAggiornamento : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool _sel;
        public bool Selezionato
        {
            get { return _sel; }
            set { if (_sel != value) { _sel = value; PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs("Selezionato")); } }
        }
        public string Tipo { get; set; }
        public string Driver { get; set; }
        public string Versione { get; set; }
        public string Data { get; set; }
        public string Dimensione { get; set; }
        public string Fonte { get; set; }
        public string Id { get; set; }
        public string Url { get; set; }
    }

    // Un programma installato (sezione "App installate").
    public class RigaApp
    {
        public string Nome { get; set; }
        public string Editore { get; set; }
        public string Versione { get; set; }
        public string Dimensione { get; set; }
        public long Byte { get; set; }
        public string Data { get; set; }
        public string Tipo { get; set; }
        public string TipoVis { get { return (RigaVoce.Tr != null && Tipo != null) ? RigaVoce.Tr(Tipo) : Tipo; } }
        public string Chiave { get; set; }
        public string Disinstalla { get; set; }
        public string DisinstallaSilenzioso { get; set; }
        public string Cartella { get; set; }
        public string Pacchetto { get; set; }
        public bool Protetta { get; set; }
        public string FileIcona { get; set; }
        public object Icona { get; set; }
    }

    // Un residuo trovato dopo la disinstallazione (cartella o chiave di registro).
    public class RigaResiduo
    {
        public bool Includi { get; set; }
        public string Tipo { get; set; }
        public string TipoVis { get { return (RigaVoce.Tr != null && Tipo != null) ? RigaVoce.Tr(Tipo) : Tipo; } }
        public string Percorso { get; set; }
        public string Dimensione { get; set; }
    }

    // Una voce della finestra "Annulla tutto": si sceglie quali modifiche riportare com'erano.
    public class RigaAnnulla : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool _inc;
        public bool Includi
        {
            get { return _inc; }
            set { if (_inc != value) { _inc = value; PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs("Includi")); } }
        }
        public string Id { get; set; }
        public string Categoria { get; set; }
        public string Voce { get; set; }
        public string Modificata { get; set; }
        public string TornaA { get; set; }
        public string Note { get; set; }
    }

    // Una scelta di un menu a tendina.
    public class OpzioneVoce
    {
        public static System.Func<string, string> Tr;
        private string _testo;
        public string Testo { get { return (Tr != null && _testo != null) ? Tr(_testo) : _testo; } set { _testo = value; } }
        public string Valore { get; set; }
        public override string ToString() { return Testo; }
    }

    // Un componente del pacchetto driver nella finestra "Installazione pulita".
    public class RigaComponente
    {
        public bool Includi { get; set; }
        public bool Modificabile { get; set; }
        public string Nome { get; set; }
        public string Stato { get; set; }
        public string Descrizione { get; set; }
    }
}
'@
}

# Le righe e le scelte dei menu mostrano i testi tradotti (inglese/italiano)
[OttWin.RigaVoce]::Tr = [Func[string, string]] { param($s) Tr $s }
[OttWin.OpzioneVoce]::Tr = [Func[string, string]] { param($s) Tr $s }

# ---------- Tema grafico (scuro di serie / chiaro) con un solo colore d'accento ----------
# Tutti i colori sono "risorse" con un nome: cambiando tema si sostituiscono solo i colori,
# e finestre, tabelle e messaggi si aggiornano da soli.

$Script:Palette = @{
    Scuro  = @{ Sfondo = '#0E1014'; Superficie = '#15181E'; Superficie2 = '#1C2028'; Selezione = '#242A36'; Bordo = '#252A34'
                Testo = '#E7EAF0'; Testo2 = '#939AA9'; Testo3 = '#5F6675'; Verde = '#3FB950'; Arancio = '#E3A008'; Rosso = '#F0524A'; Avviso = '#2A1416'; Accento = '#4C8DF6' }
    Chiaro = @{ Sfondo = '#F4F5F7'; Superficie = '#FFFFFF'; Superficie2 = '#F1F3F6'; Selezione = '#E4E9F2'; Bordo = '#DFE3EA'
                Testo = '#14161B'; Testo2 = '#5A6170'; Testo3 = '#8E95A3'; Verde = '#1A7F37'; Arancio = '#A15C00'; Rosso = '#C42B1C'; Avviso = '#FDECEC'; Accento = '#2563EB' }
}
# Per cambiare il colore d'accento (pulsante principale, icone, voce attiva) basta cambiare "Accento" qui sopra.

$Script:XamlTema = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <!-- Colori (sostituiti da Imposta-Tema) -->
  <SolidColorBrush x:Key="Sfondo" Color="#0E0F13"/>
  <SolidColorBrush x:Key="Superficie" Color="#16181D"/>
  <SolidColorBrush x:Key="Superficie2" Color="#1D2027"/>
  <SolidColorBrush x:Key="Selezione" Color="#252935"/>
  <SolidColorBrush x:Key="Bordo" Color="#262A33"/>
  <SolidColorBrush x:Key="Testo" Color="#E8EAF0"/>
  <SolidColorBrush x:Key="Testo2" Color="#9097A6"/>
  <SolidColorBrush x:Key="Testo3" Color="#5A606D"/>
  <SolidColorBrush x:Key="Verde" Color="#30D158"/>
  <SolidColorBrush x:Key="Arancio" Color="#FF9F0A"/>
  <SolidColorBrush x:Key="Rosso" Color="#FF453A"/>
  <SolidColorBrush x:Key="Avviso" Color="#2A1416"/>

  <SolidColorBrush x:Key="Accento" Color="#4C8DF6"/>

  <!-- Icone (Segoe Fluent Icons su Windows 11, Segoe MDL2 Assets su Windows 10: stessi codici) -->
  <Style x:Key="Icona" TargetType="TextBlock">
    <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
    <Setter Property="FontSize" Value="15"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
  </Style>

  <!-- Pulsante normale -->
  <Style TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="Background" Value="{DynamicResource Superficie}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Bordo}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="14,7"/>
    <Setter Property="Margin" Value="4,0"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Superficie2}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Selezione}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Pulsante principale: bordo RGB e bagliore al passaggio del mouse -->
  <Style x:Key="Primario" TargetType="Button">
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Padding" Value="18,8"/>
    <Setter Property="Margin" Value="4,0"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{DynamicResource Accento}" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Opacity" Value="0.88"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Opacity" Value="0.75"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Voce di menu nella barra laterale (testo allineato a sinistra) -->
  <Style x:Key="Menu" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="12,8,10,8" Margin="0,1">
            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Superficie2}"/>
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Riquadro cliccabile della Panoramica -->
  <Style x:Key="Scheda" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1"
                  CornerRadius="8" Padding="16,13" Margin="0,0,10,10">
            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Superficie2}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Testo3}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Barra laterale: elenco delle sezioni -->
  <Style x:Key="ListaNav" TargetType="ListBox">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBox">
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
            <StackPanel IsItemsHost="True" Margin="0,0,4,0"/>
          </ScrollViewer>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="VoceNav" TargetType="ListBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Grid Margin="0,1" Background="Transparent">
            <Border x:Name="b" CornerRadius="6" Background="Transparent"/>
            <Border x:Name="tacca" Width="3" Height="16" CornerRadius="1.5" HorizontalAlignment="Left" VerticalAlignment="Center"
                    Background="{DynamicResource Accento}" Visibility="Hidden"/>
            <ContentPresenter Margin="12,7,8,7"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Superficie2}"/>
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Selezione}"/>
              <Setter TargetName="tacca" Property="Visibility" Value="Visible"/>
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="TitoloNav" TargetType="ListBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Testo3}"/>
    <Setter Property="FontSize" Value="10.5"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Focusable" Value="False"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="b" Background="Transparent" CornerRadius="6" Margin="0,4,0,0">
            <ContentPresenter Margin="8,8,6,5"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Superficie2}"/>
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Menu a tendina -->
  <Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="b" Background="Transparent" CornerRadius="4" Padding="10,7" Margin="2,1">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource Selezione}"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ComboBox">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="MinHeight" Value="30"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="MaxDropDownHeight" Value="340"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template>
                <ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="bd" Background="{DynamicResource Superficie2}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1" CornerRadius="6">
                    <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,11,0" Data="M 0,0 L 4,4 L 8,0"
                          Stroke="{DynamicResource Testo2}" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Testo3}"/>
                    </Trigger>
                    <Trigger Property="IsChecked" Value="True">
                      <Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accento}"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter IsHitTestVisible="False" Margin="11,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                              Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                              ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"/>
            <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade"
                   IsOpen="{TemplateBinding IsDropDownOpen}">
              <Border Background="{DynamicResource Superficie2}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1" CornerRadius="6"
                      Margin="0,4,0,8" Padding="2" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                  <StackPanel IsItemsHost="True"/>
                </ScrollViewer>
              </Border>
            </Popup>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Pulsante discreto (senza bordo) -->
  <Style x:Key="Fantasma" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderBrush" Value="Transparent"/>
    <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <!-- Casella di spunta: si riempie di RGB -->
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Grid Width="16" Height="16" VerticalAlignment="Center">
              <Border x:Name="box" CornerRadius="4" BorderThickness="1.5" BorderBrush="{DynamicResource Testo3}" Background="Transparent"/>
              <Border x:Name="fill" CornerRadius="4" Background="{DynamicResource Accento}" Visibility="Collapsed"/>
              <Path x:Name="mark" Data="M 3.5,8.5 L 6.5,11.5 L 12.5,4.5" Stroke="White" StrokeThickness="2"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
            </Grid>
            <ContentPresenter x:Name="cp" Margin="8,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Testo2}"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="fill" Property="Visibility" Value="Visible"/>
              <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="HasContent" Value="False">
              <Setter TargetName="cp" Property="Visibility" Value="Collapsed"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Interruttore (per la Modalità prova) -->
  <Style x:Key="Interruttore" TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Grid Width="38" Height="20" VerticalAlignment="Center">
              <Border x:Name="pista" CornerRadius="10" Background="{DynamicResource Selezione}" BorderBrush="{DynamicResource Testo3}" BorderThickness="1"/>
              <Border x:Name="pistaOn" CornerRadius="10" Background="{DynamicResource Accento}" Visibility="Collapsed"/>
              <Ellipse x:Name="pomello" Width="12" Height="12" Fill="{DynamicResource Testo2}" HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="pistaOn" Property="Visibility" Value="Visible"/>
              <Setter TargetName="pomello" Property="HorizontalAlignment" Value="Right"/>
              <Setter TargetName="pomello" Property="Margin" Value="0,0,4,0"/>
              <Setter TargetName="pomello" Property="Fill" Value="White"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Interruttore piccolo (nelle tabelle, al posto delle caselle di spunta) -->
  <Style x:Key="InterruttorePiccolo" TargetType="CheckBox">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Grid Width="32" Height="18" Background="Transparent">
            <Border x:Name="pista" CornerRadius="9" Background="{DynamicResource Selezione}" BorderBrush="{DynamicResource Testo3}" BorderThickness="1"/>
            <Border x:Name="pistaOn" CornerRadius="9" Background="{DynamicResource Accento}" Visibility="Collapsed"/>
            <Ellipse x:Name="pomello" Width="10" Height="10" Fill="{DynamicResource Testo2}" HorizontalAlignment="Left" Margin="4,0,0,0"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="pista" Property="BorderBrush" Value="{DynamicResource Testo2}"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="pistaOn" Property="Visibility" Value="Visible"/>
              <Setter TargetName="pomello" Property="HorizontalAlignment" Value="Right"/>
              <Setter TargetName="pomello" Property="Margin" Value="0,0,4,0"/>
              <Setter TargetName="pomello" Property="Fill" Value="White"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Schede: solo testo, la scheda attiva ha una sottolineatura RGB -->
  <Style TargetType="TabControl">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="0"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TabControl">
          <DockPanel>
            <Border DockPanel.Dock="Top" BorderBrush="{DynamicResource Bordo}" BorderThickness="0,0,0,1">
              <TabPanel IsItemsHost="True" Background="Transparent"/>
            </Border>
            <ContentPresenter ContentSource="SelectedContent" Margin="0,12,0,0"/>
          </DockPanel>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="TabItem">
    <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TabItem">
          <Grid Background="Transparent">
            <ContentPresenter ContentSource="Header" Margin="12,8,12,10" HorizontalAlignment="Center"/>
            <Border x:Name="linea" Height="2" VerticalAlignment="Bottom" CornerRadius="1" Margin="8,0"
                    Background="{DynamicResource Accento}" Visibility="Hidden"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="linea" Property="Visibility" Value="Visible"/>
              <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Tabelle -->
  <Style TargetType="DataGrid">
    <Setter Property="Background" Value="{DynamicResource Superficie}"/>
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="GridLinesVisibility" Value="Horizontal"/>
    <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource Bordo}"/>
    <Setter Property="HeadersVisibility" Value="Column"/>
    <Setter Property="RowHeaderWidth" Value="0"/>
    <Setter Property="MinRowHeight" Value="36"/>
    <Setter Property="SelectionMode" Value="Single"/>
    <Setter Property="CanUserAddRows" Value="False"/>
    <Setter Property="CanUserDeleteRows" Value="False"/>
    <Setter Property="CanUserReorderColumns" Value="False"/>
    <Setter Property="CanUserResizeRows" Value="False"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  </Style>
  <Style TargetType="DataGridColumnHeader">
    <Setter Property="Foreground" Value="{DynamicResource Testo3}"/>
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="DataGridColumnHeader">
          <Border Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="0,0,0,1" Padding="10,10,10,9">
            <ContentPresenter VerticalAlignment="Center"/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="DataGridRow">
    <Setter Property="Background" Value="Transparent"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource Superficie2}"/>
      </Trigger>
      <Trigger Property="IsSelected" Value="True">
        <Setter Property="Background" Value="{DynamicResource Selezione}"/>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style TargetType="DataGridCell">
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="DataGridCell">
          <Border Background="Transparent" Padding="10,0">
            <ContentPresenter VerticalAlignment="Center"/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="IsSelected" Value="True">
        <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <!-- Barre di scorrimento sottili -->
  <Style x:Key="Pollice" TargetType="Thumb">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Thumb">
          <Border CornerRadius="4" Background="{DynamicResource Testo3}"/>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="10"/>
    <Setter Property="MinWidth" Value="10"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb><Thumb Style="{StaticResource Pollice}" Margin="2"/></Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Orientation" Value="Horizontal">
        <Setter Property="Width" Value="Auto"/>
        <Setter Property="MinWidth" Value="0"/>
        <Setter Property="Height" Value="10"/>
        <Setter Property="MinHeight" Value="10"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="ScrollBar">
              <Grid Background="Transparent">
                <Track x:Name="PART_Track" IsDirectionReversed="False">
                  <Track.Thumb><Thumb Style="{StaticResource Pollice}" Margin="2"/></Track.Thumb>
                </Track>
              </Grid>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Trigger>
    </Style.Triggers>
  </Style>

  <!-- Suggerimenti e caselle di testo -->
  <Style TargetType="ToolTip">
    <Setter Property="Background" Value="{DynamicResource Superficie2}"/>
    <Setter Property="Foreground" Value="{DynamicResource Testo}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Bordo}"/>
    <Setter Property="Padding" Value="10,6"/>
  </Style>
  <Style TargetType="TextBox">
    <Setter Property="Background" Value="{DynamicResource Superficie}"/>
    <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="12,10"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Testo}"/>
  </Style>
</ResourceDictionary>
'@

$Script:Tema = [Windows.Markup.XamlReader]::Parse($Script:XamlTema)
$Script:TemaAttuale = 'Scuro'

# Barra del titolo di Windows scura/chiara (funzione ufficiale di Windows 11, dwmapi.dll).
try {
    if (-not ('OttWin.Dwm' -as [type])) {
        Add-Type -Namespace OttWin -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
'@
    }
} catch { }

function Imposta-BarraTitolo($Finestra) {
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($Finestra)).EnsureHandle()
        $scuro = [int]($Script:TemaAttuale -eq 'Scuro')
        [void][OttWin.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$scuro, 4)              # modalità scura
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Script:Palette[$Script:TemaAttuale].Sfondo)
        $colore = [int]$c.R + ([int]$c.G -shl 8) + ([int]$c.B -shl 16)                  # formato 0x00BBGGRR
        [void][OttWin.Dwm]::DwmSetWindowAttribute($h, 35, [ref]$colore, 4)             # colore della barra
    } catch { }
}

# Applica il tema a una finestra appena creata.
function Applica-TemaFinestra($Finestra) {
    [void]$Finestra.Resources.MergedDictionaries.Add($Script:Tema)
    Imposta-BarraTitolo $Finestra
    Traduci-Albero $Finestra
}

function Imposta-Tema([string]$Nome) {
    if (-not $Script:Palette.ContainsKey($Nome)) { $Nome = 'Scuro' }
    $Script:TemaAttuale = $Nome
    $p = $Script:Palette[$Nome]
    foreach ($k in @($p.Keys)) { $Script:Tema[$k] = Pennello $p[$k] }
    if ($Script:Finestra) {
        Imposta-BarraTitolo $Script:Finestra
        $chiaro = ($Nome -eq 'Scuro')
        $Script:Finestra.FindName('IconaTema').Text = [string][char]$(if ($chiaro) { 0xE706 } else { 0xE708 })
        $Script:Finestra.FindName('TestoTema').Text = $(if ($chiaro) { 'Chiaro' } else { 'Scuro' })
    }
    Salva-Impostazione 'Tema' $Nome
}

# ---------- Icona del programma (disegnata qui, niente file esterni) ----------
# Un quadrato arrotondato blu con un indicatore di velocità: arco di fondo, arco "pieno" fino
# all'ago, ago e perno. Disegno vettoriale su 256x256: resta nitido a ogni dimensione.
$Script:XamlLogo = @'
<DrawingImage xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
  <DrawingImage.Drawing>
    <DrawingGroup>
      <GeometryDrawing Geometry="M0,0 L256,0 L256,256 L0,256 Z" Brush="Transparent"/>
      <GeometryDrawing>
        <GeometryDrawing.Brush>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#6AAEFF" Offset="0"/>
            <GradientStop Color="#3B74F0" Offset="0.55"/>
            <GradientStop Color="#2447C2" Offset="1"/>
          </LinearGradientBrush>
        </GeometryDrawing.Brush>
        <GeometryDrawing.Geometry><RectangleGeometry Rect="8,8,240,240" RadiusX="58" RadiusY="58"/></GeometryDrawing.Geometry>
      </GeometryDrawing>
      <GeometryDrawing Geometry="M77.1,190.9 A72,72 0 1 1 178.9,190.9">
        <GeometryDrawing.Pen><Pen Brush="#55FFFFFF" Thickness="24" StartLineCap="Round" EndLineCap="Round"/></GeometryDrawing.Pen>
      </GeometryDrawing>
      <GeometryDrawing Geometry="M77.1,190.9 A72,72 0 1 1 190.4,104">
        <GeometryDrawing.Pen><Pen Brush="White" Thickness="24" StartLineCap="Round" EndLineCap="Round"/></GeometryDrawing.Pen>
      </GeometryDrawing>
      <GeometryDrawing Geometry="M128.5,153.8 L113.5,127.8 L180,110 Z" Brush="#FFD24A"/>
      <GeometryDrawing Brush="White"><GeometryDrawing.Geometry><EllipseGeometry Center="128,140" RadiusX="18" RadiusY="18"/></GeometryDrawing.Geometry></GeometryDrawing>
      <GeometryDrawing Brush="#2A52CF"><GeometryDrawing.Geometry><EllipseGeometry Center="128,140" RadiusX="7" RadiusY="7"/></GeometryDrawing.Geometry></GeometryDrawing>
      <GeometryDrawing Geometry="M136,170 L112,202 L127,202 L120,228 L146,193 L131,193 L140,170 Z" Brush="#FFD24A"/>
    </DrawingGroup>
  </DrawingImage.Drawing>
</DrawingImage>
'@

# Icona come immagine a pixel (per la finestra e la barra delle applicazioni).
function Crea-IconaBitmap([int]$Lato = 64) {
    $logo = [Windows.Markup.XamlReader]::Parse($Script:XamlLogo)
    $v = New-Object System.Windows.Media.DrawingVisual
    $dc = $v.RenderOpen()
    $dc.DrawImage($logo, (New-Object System.Windows.Rect(0, 0, $Lato, $Lato)))
    $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Lato, $Lato, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($v)
    $bmp.Freeze()
    return $bmp
}

# Salva l'icona come file .ico (16-256 pixel), serve al collegamento sul desktop.
function Salva-IconaIco([string]$Percorso) {
    $lati = @(16, 24, 32, 48, 64, 128, 256)
    $dati = New-Object System.Collections.ArrayList
    foreach ($l in $lati) {
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create((Crea-IconaBitmap $l)))
        $ms = New-Object IO.MemoryStream; $enc.Save($ms); [void]$dati.Add($ms.ToArray()); $ms.Dispose()
    }
    $fs = [IO.File]::Create($Percorso)
    try {
        $w = New-Object IO.BinaryWriter($fs)
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$lati.Count)
        $pos = 6 + 16 * $lati.Count
        for ($i = 0; $i -lt $lati.Count; $i++) {
            $l = $lati[$i] % 256; $d = [byte[]]$dati[$i]
            $w.Write([byte]$l); $w.Write([byte]$l); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$d.Length); $w.Write([uint32]$pos); $pos += $d.Length
        }
        foreach ($d in $dati) { $w.Write([byte[]]$d) }
        $w.Flush()
    } finally { $fs.Dispose() }
}

# Crea (o ricrea) il collegamento "Regia" sul desktop, con l'icona del programma.
# Il collegamento avvia direttamente PowerShell come amministratore (chiede l'UAC) senza finestra nera.
#   $Cartella: dove crearlo (di serie il desktop dell'utente).
function Crea-Collegamento([string]$Cartella = '', [switch]$Silenzioso) {
    if (-not $Cartella) { $Cartella = [Environment]::GetFolderPath('Desktop') }
    $lnk = Join-Path $Cartella 'Regia.lnk'
    if ((Test-Path -LiteralPath $lnk) -and -not $Silenzioso) {
        $r = Mostra-Messaggio "Sul desktop c'è già il collegamento 'Regia'.`nVuoi sostituirlo con uno nuovo (stessa posizione del programma, icona aggiornata)?" 'Collegamento sul desktop' 'YesNo' 'Information'
        if ($r -ne 'Yes') { return $false }
    }
    $ico = Join-Path $Script:CartellaDati 'Regia.ico'
    Salva-IconaIco $ico
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shell = New-Object -ComObject WScript.Shell
    try {
        $c = $shell.CreateShortcut($lnk)
        $c.TargetPath = $ps
        $c.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Script:FileProgramma`""
        $c.WorkingDirectory = $Script:CartellaBase
        $c.IconLocation = "$ico,0"
        $c.Description = 'Analizza e ottimizza Windows (chiede i permessi di amministratore)'
        $c.WindowStyle = 7   # ridotta a icona: la finestra di PowerShell non si vede
        $c.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    # "Esegui come amministratore": bit 0x20 del byte 0x15 del file .lnk (come la casella nelle Proprietà)
    $b = [IO.File]::ReadAllBytes($lnk); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnk, $b)
    Scrivi-Log "Collegamento creato: $lnk (icona $ico)" 'OK'
    if (-not $Silenzioso) {
        [void](Mostra-Messaggio "Collegamento 'Regia' creato sul desktop.`n`nAvvia il programma direttamente come amministratore, senza la finestra nera. Se sposti la cartella del programma, crealo di nuovo da qui." 'Collegamento sul desktop' 'OK' 'Information')
    }
    return $true
}

# ---------- Messaggi nello stile del programma (al posto di quelli grigi di Windows) ----------
$Script:XamlMessaggio = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="480" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Accento}"/>
    <StackPanel Margin="24,20,24,20">
      <StackPanel Orientation="Horizontal">
        <Ellipse x:Name="Punto" Width="8" Height="8" Margin="0,0,10,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="Titolo" FontSize="15" FontWeight="SemiBold"/>
      </StackPanel>
      <TextBlock x:Name="Testo" TextWrapping="Wrap" Margin="0,12,0,0" Foreground="{DynamicResource Testo2}" LineHeight="20"/>
      <StackPanel x:Name="Pulsanti" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0"/>
    </StackPanel>
  </DockPanel>
</Window>
'@

# Pulsanti: 'OK' | 'YesNo' | 'YesNoCancel'.  Tipo: 'Information' | 'Warning' | 'Error'.
# Restituisce 'OK', 'Yes', 'No' oppure 'Cancel' (come i messaggi di Windows).
function Mostra-Messaggio([string]$Testo, [string]$Titolo = 'Regia', [string]$Pulsanti = 'OK', [string]$Tipo = 'Information') {
    $Testo = Tr $Testo; $Titolo = Tr $Titolo
    if (-not $Script:Finestra) { return [string][System.Windows.MessageBox]::Show($Testo, $Titolo, $Pulsanti, $Tipo) }
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlMessaggio)
    Applica-TemaFinestra $w
    if ($Script:Finestra.IsVisible) { $w.Owner = $Script:Finestra }
    $w.Title = $Titolo
    $w.FindName('Titolo').Text = $Titolo
    $w.FindName('Testo').Text = $Testo
    $chiavePunto = switch ($Tipo) { 'Warning' { 'Arancio' } 'Error' { 'Rosso' } default { 'Verde' } }
    $w.FindName('Punto').SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $chiavePunto)
    switch ($Pulsanti) {
        'YesNo'       { $scelte = @(@((Tr 'No'), 'No'), @((Tr 'Sì'), 'Yes')); $w.Tag = 'No' }
        'YesNoCancel' { $scelte = @(@((Tr 'Annulla'), 'Cancel'), @((Tr 'No'), 'No'), @((Tr 'Sì'), 'Yes')); $w.Tag = 'Cancel' }
        default       { $scelte = @(, @('OK', 'OK')); $w.Tag = 'OK' }
    }
    $pannello = $w.FindName('Pulsanti')
    for ($i = 0; $i -lt $scelte.Count; $i++) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $scelte[$i][0]
        $b.Tag = $scelte[$i][1]
        $b.MinWidth = 90
        if ($i -eq $scelte.Count - 1) { $b.Style = $Script:Tema['Primario']; $b.IsDefault = $true }
        if ($scelte[$i][1] -eq 'Cancel' -or ($Pulsanti -eq 'OK')) { $b.IsCancel = $true }
        $b.add_Click({ $f = [System.Windows.Window]::GetWindow($this); $f.Tag = $this.Tag; $f.Close() })
        [void]$pannello.Children.Add($b)
    }
    [void]$w.ShowDialog()
    return [string]$w.Tag
}

# ---------- Riavvio del PC dal programma ----------
# Quando una modifica ha effetto solo dopo il riavvio, il programma lo propone con le avvertenze
# sul lavoro aperto. Il riavvio NON è forzato: se un programma ha lavoro non salvato, Windows lo
# chiede e si può ancora annullare.
$Script:MotivoRiavvio = ''

$Script:XamlRiavvio = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Arancio}"/>
    <StackPanel Margin="24,20,24,20">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="&#xE7E8;" Style="{DynamicResource Icona}" FontSize="18" Foreground="{DynamicResource Arancio}" Margin="0,0,12,0"/>
        <TextBlock x:Name="Titolo" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock x:Name="Testo" TextWrapping="Wrap" Margin="0,12,0,0" Foreground="{DynamicResource Testo2}" LineHeight="20"/>
      <Border Margin="0,16,0,0" Padding="14,12" CornerRadius="8" Background="{DynamicResource Avviso}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1">
        <StackPanel>
          <TextBlock Text="PRIMA DI RIAVVIARE" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Arancio}"/>
          <TextBlock TextWrapping="Wrap" Margin="0,6,0,0" LineHeight="20"
                     Text="• Salva documenti, progetti e partite: i programmi aperti verranno chiusi.&#x0a;• Aspetta che finiscano download, copie di file e installazioni.&#x0a;• Se un programma ha lavoro non salvato, Windows te lo chiede e puoi ancora annullare il riavvio."/>
          <TextBlock x:Name="ProgrammiAperti" TextWrapping="Wrap" Margin="0,10,0,0" LineHeight="20" Foreground="{DynamicResource Testo}"/>
          <TextBlock x:Name="AvvisoUpdate" TextWrapping="Wrap" Margin="0,10,0,0" LineHeight="20" Foreground="{DynamicResource Arancio}" Visibility="Collapsed"
                     Text="Windows sta lavorando ad aggiornamenti in questo momento: se puoi, aspetta qualche minuto prima di riavviare."/>
        </StackPanel>
      </Border>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
        <Button x:Name="BtnDopo" Content="Più tardi" MinWidth="100" IsCancel="True"/>
        <Button x:Name="BtnDisconnetti" Content="Disconnetti" MinWidth="100" Visibility="Collapsed"
                ToolTip="Chiude la sessione di Windows senza spegnere il PC: basta per le modifiche che hanno effetto alla disconnessione"/>
        <Button x:Name="BtnRiavviaOra" Style="{DynamicResource Primario}" MinWidth="130" IsDefault="True">
          <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE777;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0" Foreground="White"/><TextBlock Text="Riavvia ora"/></StackPanel>
        </Button>
      </StackPanel>
    </StackPanel>
  </DockPanel>
</Window>
'@

# Windows stesso aspetta un riavvio? (aggiornamenti o componenti installati)
function Serve-RiavvioWindows {
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                     'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path -LiteralPath $k) { return $true }
    }
    return $false
}

# Programmi con una finestra aperta (tranne questo), per ricordare cosa salvare.
function Leggi-ProgrammiAperti {
    $nomi = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Id -ne $PID -and $_.MainWindowTitle })) {
        $n = ''
        try { $n = [string]$p.MainModule.FileVersionInfo.FileDescription } catch { }
        if (-not $n) { $n = $p.ProcessName }
        if ($p.ProcessName -match '^(explorer|ApplicationFrameHost|TextInputHost|SystemSettings|ShellExperienceHost|StartMenuExperienceHost|SearchHost|LockApp|conhost|OpenConsole|WindowsTerminal)$') { continue }
        $nomi += $n.Trim()
    }
    return @($nomi | Sort-Object -Unique)
}

# Accende o spegne l'avviso "Riavvio consigliato" nella barra laterale.
function Aggiorna-StatoRiavvio {
    if (-not $Script:Finestra) { return }
    $serve = [bool]$Script:MotivoRiavvio
    if (-not $serve -and (Serve-RiavvioWindows)) { $serve = $true }
    $t = $Script:Finestra.FindName('TestoRiavvio'); $p = $Script:Finestra.FindName('PuntoRiavvio')
    if ($t) { $t.Text = Tr $(if ($serve) { 'Riavvio consigliato' } else { 'Riavvia il PC' }) }
    if ($p) { $p.Visibility = $(if ($serve) { 'Visible' } else { 'Collapsed' }) }
}

# Ricorda che serve un riavvio (resta segnalato nella barra laterale finché non riavvii).
function Segna-Riavvio([string]$Motivo) {
    if ($Motivo -and $Script:MotivoRiavvio -notlike "*$Motivo*") { $Script:MotivoRiavvio = ("$Script:MotivoRiavvio`n$Motivo").Trim() }
    Aggiorna-StatoRiavvio
}

# Mostra la finestra del riavvio.  $Testo: cosa è successo e perché serve riavviare.
#   $Disconnessione = $true: basta anche disconnettersi (compare il pulsante "Disconnetti").
# Restituisce 'Riavvio', 'Disconnessione' oppure 'Dopo'.
function Proponi-Riavvio([string]$Testo = '', [string]$Titolo = 'Riavviare il PC?', [bool]$Disconnessione = $false) {
    if (-not $Testo) {
        $Testo = $(if ($Script:MotivoRiavvio) { "Il riavvio completa queste operazioni:`n$Script:MotivoRiavvio" }
                   elseif (Serve-RiavvioWindows) { 'Windows ha aggiornamenti o componenti che si completano al riavvio.' }
                   else { 'In questo momento non risultano operazioni in attesa di riavvio.' })
    }
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlRiavvio)
    Applica-TemaFinestra $w
    if ($Script:Finestra -and $Script:Finestra.IsVisible) { $w.Owner = $Script:Finestra }
    $w.Title = $Titolo
    $w.FindName('Titolo').Text = $Titolo
    $w.FindName('Testo').Text = $Testo
    $aperti = @(Leggi-ProgrammiAperti)
    $w.FindName('ProgrammiAperti').Text = $(if ($aperti.Count -gt 0) { "Programmi aperti adesso: $($aperti -join ', ')." } else { 'Non risultano altri programmi aperti.' })
    if (@(Get-Process -Name 'TiWorker', 'TrustedInstaller', 'msiexec' -ErrorAction SilentlyContinue).Count -gt 0) { $w.FindName('AvvisoUpdate').Visibility = 'Visible' }
    if ($Disconnessione) { $w.FindName('BtnDisconnetti').Visibility = 'Visible' }
    $w.Tag = 'Dopo'
    $w.FindName('BtnRiavviaOra').add_Click({ $f = [System.Windows.Window]::GetWindow($this); $f.Tag = 'Riavvio'; $f.Close() })
    $w.FindName('BtnDisconnetti').add_Click({ $f = [System.Windows.Window]::GetWindow($this); $f.Tag = 'Disconnessione'; $f.Close() })
    [void]$w.ShowDialog()
    $scelta = [string]$w.Tag
    switch ($scelta) {
        'Riavvio' {
            Scrivi-Log 'Riavvio del PC chiesto dall''utente.' 'AVVISO'
            # /t 0 senza /f: Windows chiede di chiudere i programmi e chi ha lavoro non salvato può bloccare il riavvio.
            $c = Esegui-Processo "$env:SystemRoot\System32\shutdown.exe" '/r /t 0 /d p:4:1'
            if ($c -ne 0) { Scrivi-Log "Riavvio non avviato (codice $c)." 'ERRORE'; [void](Mostra-Messaggio "Windows non ha avviato il riavvio (codice $c).`nRiavvia dal menu Start." 'Riavvio' 'OK' 'Warning') }
        }
        'Disconnessione' {
            Scrivi-Log 'Disconnessione chiesta dall''utente.' 'AVVISO'
            $c = Esegui-Processo "$env:SystemRoot\System32\shutdown.exe" '/l'
            if ($c -ne 0) { Scrivi-Log "Disconnessione non avviata (codice $c)." 'ERRORE' }
        }
        default { if ($Script:MotivoRiavvio) { Scrivi-Log 'Riavvio rimandato: resta segnalato nella barra laterale.' } }
    }
    return $scelta
}

# ---------- Finestra principale ----------
# A sinistra la barra di navigazione (una voce con icona per ogni sezione), a destra la sezione scelta.
$Script:XamlFinestra = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Regia" Width="1320" Height="860" MinWidth="1040" MinHeight="640"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="248"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Barra laterale -->
    <Border Grid.Column="0" Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="0,0,1,0">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="20,22,16,10">
          <Image x:Name="LogoProgramma" Width="36" Height="36" VerticalAlignment="Center"/>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="Regia" FontSize="16" FontWeight="SemiBold"/>
            <TextBlock x:Name="TestoVersione" FontSize="11" Foreground="{DynamicResource Testo3}" Margin="0,1,0,0"/>
          </StackPanel>
        </StackPanel>
        <Border DockPanel.Dock="Bottom" BorderBrush="{DynamicResource Bordo}" BorderThickness="0,1,0,0" Padding="10,8,10,10">
          <StackPanel>
            <Button x:Name="BtnAggiorna" Style="{DynamicResource Menu}" Visibility="Collapsed" ToolTip="È disponibile una versione più recente di Regia: premi per aggiornare (prima ti mostra le novità e chiede conferma)">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE896;" Style="{DynamicResource Icona}" Width="26" Foreground="{DynamicResource Verde}"/>
                <TextBlock x:Name="TestoAggiorna" Text="Aggiornamento disponibile" Foreground="{DynamicResource Verde}" FontWeight="SemiBold" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnGodMode" Style="{DynamicResource Menu}" ToolTip="Apre la cartella 'God Mode' di Windows: tutte le impostazioni del Pannello di controllo (circa 200) in un unico elenco con ricerca. Da sola non cambia niente">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE713;" Style="{DynamicResource Icona}" Width="26"/>
                <TextBlock Text="God Mode (tutte le impostazioni)" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnRiavvia" Style="{DynamicResource Menu}" ToolTip="Riavvia il PC (prima ti ricorda di salvare il lavoro aperto)">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE7E8;" Style="{DynamicResource Icona}" Width="26"/>
                <TextBlock x:Name="TestoRiavvio" Text="Riavvia il PC" VerticalAlignment="Center"/>
                <Ellipse x:Name="PuntoRiavvio" Width="8" Height="8" Margin="10,0,0,0" Fill="{DynamicResource Arancio}" VerticalAlignment="Center" Visibility="Collapsed"/>
              </StackPanel>
            </Button>
            <UniformGrid Columns="4" Margin="0,2">
              <Button x:Name="BtnCollegamento" Style="{DynamicResource Menu}" ToolTip="Collegamento sul desktop: crea sul desktop un collegamento con l'icona del programma, che lo avvia come amministratore">
                <TextBlock Text="&#xE71B;" Style="{DynamicResource Icona}" Width="30" TextAlignment="Center"/>
              </Button>
              <Button x:Name="BtnFeedback" Style="{DynamicResource Menu}" ToolTip="Crea file per il feedback: un .zip sul desktop con report, scansione e registro (senza nome utente né nome del PC) da inviare a chi ti ha dato Regia">
                <TextBlock Text="&#xE939;" Style="{DynamicResource Icona}" Width="30" TextAlignment="Center"/>
              </Button>
              <Button x:Name="BtnCartella" Style="{DynamicResource Menu}" ToolTip="Cartella dati: apre la cartella con log, backup e profili">
                <TextBlock Text="&#xE8B7;" Style="{DynamicResource Icona}" Width="30" TextAlignment="Center"/>
              </Button>
              <Button x:Name="BtnControllaAgg" Style="{DynamicResource Menu}" ToolTip="Cerca aggiornamenti: controlla se esiste una versione più recente di Regia">
                <TextBlock Text="&#xE895;" Style="{DynamicResource Icona}" Width="30" TextAlignment="Center"/>
              </Button>
            </UniformGrid>
            <Button x:Name="BtnSostieni" Style="{DynamicResource Menu}" Visibility="Collapsed" ToolTip="Regia è gratuito e senza pubblicità: se ti è utile puoi offrire un caffè allo sviluppatore (apre la pagina nel browser)">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xEB51;" Style="{DynamicResource Icona}" Width="26" Foreground="{DynamicResource Arancio}"/>
                <TextBlock Text="Sostieni Regia" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnTema" Style="{DynamicResource Menu}" ToolTip="Cambia tema scuro / chiaro">
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="IconaTema" Style="{DynamicResource Icona}" Width="26"/>
                <TextBlock x:Name="TestoTema" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </StackPanel>
        </Border>
        <ListBox x:Name="Navigazione" Style="{DynamicResource ListaNav}" Margin="10,0,6,0"/>
      </DockPanel>
    </Border>

    <!-- Sezione scelta -->
    <Grid Grid.Column="1" Margin="32,24,32,14">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Intestazione della sezione -->
      <DockPanel Grid.Row="0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
          <Button x:Name="BtnLingua" Style="{DynamicResource Fantasma}" Margin="0,0,10,0" VerticalAlignment="Center" ToolTip="Language / Lingua: English - Italiano"/>
          <CheckBox x:Name="ChkProva" Style="{DynamicResource Interruttore}" IsChecked="True" VerticalAlignment="Center" Margin="0,0,14,0"
                    Content="Modalità prova" ToolTip="Accesa: il programma mostra e scrive nel log cosa farebbe, ma non modifica niente"/>
          <Button x:Name="BtnScansiona" ToolTip="Rilegge lo stato del PC (sola lettura)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/>
              <TextBlock Text="Scansiona"/>
            </StackPanel>
          </Button>
        </StackPanel>
        <StackPanel>
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="IconaPagina" Style="{DynamicResource Icona}" FontSize="21" Foreground="{DynamicResource Accento}" Margin="0,2,12,0"/>
            <TextBlock x:Name="TitoloPagina" FontSize="23" FontWeight="SemiBold"/>
          </StackPanel>
          <TextBlock x:Name="IntroPagina" Foreground="{DynamicResource Testo2}" Margin="0,8,24,0" TextWrapping="Wrap" LineHeight="19"/>
        </StackPanel>
      </DockPanel>

      <!-- Profili rapidi -->
      <Border x:Name="BarraProfili" Grid.Row="1" Margin="0,18,0,0" Padding="14,10" CornerRadius="8"
              Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top" Margin="12,0,0,0">
            <Button x:Name="BtnSalvaProfilo" Style="{DynamicResource Fantasma}" ToolTip="Salva profilo: salva le voci accese adesso come un tuo profilo">
              <TextBlock Text="&#xE74E;" Style="{DynamicResource Icona}" FontSize="15"/>
            </Button>
            <Button x:Name="BtnNessuno" Style="{DynamicResource Fantasma}" ToolTip="Togli spunte: spegne tutte le voci accese">
              <TextBlock Text="&#xE8E6;" Style="{DynamicResource Icona}" FontSize="15"/>
            </Button>
          </StackPanel>
          <WrapPanel Orientation="Horizontal">
            <TextBlock Text="PROFILO" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}" VerticalAlignment="Center" Margin="2,0,10,0"/>
            <Button x:Name="BtnMassimo" ToolTip="Accende tutto quello che serve a migliorare il PC, anche voci a rischio medio (rimozione app, servizi, app in background). Prima mostra un avviso.">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7BA;" Style="{DynamicResource Icona}" Foreground="{DynamicResource Arancio}" Margin="0,0,8,0"/><TextBlock Text="Massimo"/></StackPanel>
            </Button>
            <Button x:Name="BtnGaming" ToolTip="Migliori prestazioni nei giochi: Game Mode, HAGS, piano Prestazioni elevate, meno processi in background. Non tocca la scheda video.">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7FC;" Style="{DynamicResource Icona}" Margin="0,0,8,0"/><TextBlock Text="Gaming"/></StackPanel>
            </Button>
            <Button x:Name="BtnGrafica" ToolTip="Migliori prestazioni per grafica ed editing, senza toccare colori, HDR e impostazioni delle app creative. Non tocca la scheda video.">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE790;" Style="{DynamicResource Icona}" Margin="0,0,8,0"/><TextBlock Text="Grafica ed editing"/></StackPanel>
            </Button>
            <Button x:Name="BtnBilanciato" ToolTip="Equilibrio per l'uso di tutti i giorni: piano Bilanciato, meno notifiche inutili, avvio veloce, Esplora file più pratico">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE821;" Style="{DynamicResource Icona}" Margin="0,0,8,0"/><TextBlock Text="Bilanciato"/></StackPanel>
            </Button>
            <Button x:Name="BtnBatteria" ToolTip="Portatili a batteria: massima autonomia, app in background bloccate, effetti ridotti. Non tocca la scheda video.">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE83F;" Style="{DynamicResource Icona}" Margin="0,0,8,0"/><TextBlock Text="Portatile a batteria"/></StackPanel>
            </Button>
            <Button x:Name="BtnSicuro" ToolTip="Solo modifiche leggere e reversibili: privacy, pubblicità, Esplora file e file temporanei. Non rimuove app e non tocca servizi, energia e scheda video.">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72E;" Style="{DynamicResource Icona}" Foreground="{DynamicResource Verde}" Margin="0,0,8,0"/><TextBlock Text="Sicuro"/></StackPanel>
            </Button>
            <StackPanel x:Name="ProfiliPersonali" Orientation="Horizontal"/>
          </WrapPanel>
        </DockPanel>
      </Border>

      <ContentControl x:Name="AreaContenuto" Grid.Row="2" Margin="0,16,0,0" Focusable="False"/>

      <!-- Spiegazione della voce selezionata -->
      <Border x:Name="PannelloDescrizione" Grid.Row="3" Margin="0,14,0,0" Padding="16,12" CornerRadius="8" MinHeight="76"
              Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1">
        <DockPanel>
          <TextBlock DockPanel.Dock="Left" Text="&#xE946;" Style="{DynamicResource Icona}" FontSize="16" Foreground="{DynamicResource Testo3}" VerticalAlignment="Top" Margin="0,2,14,0"/>
          <StackPanel>
            <TextBlock x:Name="TitoloVoce" FontWeight="SemiBold" Text="Seleziona una voce per leggerne la spiegazione"/>
            <TextBlock x:Name="TestoDescrizione" TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,5,0,0" LineHeight="19"/>
          </StackPanel>
        </DockPanel>
      </Border>

      <!-- Azioni -->
      <DockPanel x:Name="BarraAzioni" Grid.Row="4" Margin="0,14,0,0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="BtnAnnullaTutto" ToolTip="Rimette i valori originali salvati nei backup di questo PC: puoi scegliere quali voci">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7A7;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Annulla tutto"/></StackPanel>
          </Button>
          <Button x:Name="BtnPredefinito" Content="Riporta al predefinito"
                  ToolTip="Rimette le voci accese come in un Windows appena installato (non vale per app e pulizia)"/>
          <Button x:Name="BtnApplica" Style="{DynamicResource Primario}" Margin="4,0,0,0">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE73E;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Anteprima e applica"/></StackPanel>
          </Button>
        </StackPanel>
        <TextBlock x:Name="TestoSelezione" VerticalAlignment="Center" Foreground="{DynamicResource Testo2}"/>
      </DockPanel>

      <Border Grid.Row="5" Margin="0,12,0,0" Padding="0,10,0,0" BorderBrush="{DynamicResource Bordo}" BorderThickness="0,1,0,0">
        <DockPanel>
          <!-- Barra di avanzamento: sottile, colore d'accento; quando non c'è una percentuale scorre -->
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
            <!-- Ruota che gira: si vede quando c'è un'attività in corso, anche se la percentuale è ferma -->
            <Ellipse x:Name="RuotaAttesa" Width="18" Height="18" Margin="0,0,10,0" Visibility="Collapsed" VerticalAlignment="Center"
                     Stroke="{DynamicResource Accento}" StrokeThickness="2.4" StrokeDashArray="5.5,10" StrokeDashCap="Round"
                     RenderTransformOrigin="0.5,0.5" ToolTip="Attività in corso">
              <Ellipse.RenderTransform><RotateTransform Angle="0"/></Ellipse.RenderTransform>
              <Ellipse.Style>
                <Style TargetType="Ellipse">
                  <Style.Triggers>
                    <Trigger Property="IsVisible" Value="True">
                      <Trigger.EnterActions>
                        <BeginStoryboard x:Name="GiraRuota">
                          <Storyboard RepeatBehavior="Forever">
                            <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="0" To="360" Duration="0:0:0.9"/>
                          </Storyboard>
                        </BeginStoryboard>
                      </Trigger.EnterActions>
                      <Trigger.ExitActions>
                        <StopStoryboard BeginStoryboardName="GiraRuota"/>
                      </Trigger.ExitActions>
                    </Trigger>
                  </Style.Triggers>
                </Style>
              </Ellipse.Style>
            </Ellipse>
            <TextBlock x:Name="TestoAvanzamento" FontSize="11" Foreground="{DynamicResource Testo3}" Width="36" TextAlignment="Right" Margin="0,0,8,0" Visibility="Collapsed"/>
            <ProgressBar x:Name="BarraAvanzamento" Width="220" Height="6" Minimum="0" Maximum="100" Visibility="Collapsed">
              <ProgressBar.Template>
                <ControlTemplate TargetType="ProgressBar">
                  <Border CornerRadius="3" Background="{DynamicResource Bordo}" ClipToBounds="True">
                    <Grid>
                      <Border x:Name="PART_Track"/>
                      <Border x:Name="PART_Indicator" CornerRadius="3" Background="{DynamicResource Accento}" HorizontalAlignment="Left"/>
                      <Canvas x:Name="Scorrimento" ClipToBounds="True" Visibility="Collapsed">
                        <Border x:Name="Pezzo" Width="70" Height="6" CornerRadius="3" Background="{DynamicResource Accento}" Canvas.Left="-70"/>
                      </Canvas>
                    </Grid>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsIndeterminate" Value="True">
                      <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                      <Setter TargetName="Scorrimento" Property="Visibility" Value="Visible"/>
                      <Trigger.EnterActions>
                        <BeginStoryboard x:Name="Animazione">
                          <Storyboard RepeatBehavior="Forever">
                            <DoubleAnimation Storyboard.TargetName="Pezzo" Storyboard.TargetProperty="(Canvas.Left)" From="-70" To="230" Duration="0:0:1.3"/>
                          </Storyboard>
                        </BeginStoryboard>
                      </Trigger.EnterActions>
                      <Trigger.ExitActions>
                        <StopStoryboard BeginStoryboardName="Animazione"/>
                      </Trigger.ExitActions>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ProgressBar.Template>
            </ProgressBar>
          </StackPanel>
          <TextBlock x:Name="TestoStato" FontSize="12" Foreground="{DynamicResource Testo3}" TextWrapping="Wrap" VerticalAlignment="Center"/>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

$Script:XamlGriglia = @'
<DataGrid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
          AutoGenerateColumns="False" CanUserAddRows="False">
  <DataGrid.Columns>
    <DataGridTemplateColumn Header="" Width="54" CanUserResize="False">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <CheckBox IsChecked="{Binding Selezionata, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Style="{DynamicResource InterruttorePiccolo}"
                    HorizontalAlignment="Center" VerticalAlignment="Center" ToolTip="Acceso = applica questa voce"/>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
    <!--COLONNA_CATEGORIA-->
    <DataGridTextColumn Header="VOCE" Binding="{Binding NomeVis}" Width="2.7*" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock"><Setter Property="TextTrimming" Value="CharacterEllipsis"/><Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/></Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTextColumn Header="STATO ATTUALE" Binding="{Binding AttualeVis}" Width="1.5*" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock"><Setter Property="TextTrimming" Value="CharacterEllipsis"/><Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/></Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTemplateColumn Header="DA APPLICARE" Width="2.2*" MinWidth="240" SortMemberPath="Consigliato">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <Grid>
            <!-- Voci con più scelte: menu a tendina; le altre: il valore consigliato -->
            <TextBlock x:Name="SoloTesto" Text="{Binding ConsigliatoVis}" Foreground="{DynamicResource Testo2}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
            <ComboBox x:Name="Menu" ItemsSource="{Binding Scelte}" DisplayMemberPath="Testo" Margin="0,3,6,3" Visibility="Collapsed"
                      SelectedItem="{Binding SceltaVoce, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                      ToolTip="Scegli il valore da applicare con 'Anteprima e applica'"/>
          </Grid>
          <DataTemplate.Triggers>
            <DataTrigger Binding="{Binding HaScelte}" Value="True">
              <Setter TargetName="SoloTesto" Property="Visibility" Value="Collapsed"/>
              <Setter TargetName="Menu" Property="Visibility" Value="Visible"/>
            </DataTrigger>
          </DataTemplate.Triggers>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
    <DataGridTextColumn Header="PREDEFINITO" Binding="{Binding PredefinitoVis}" Width="0.9*" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock">
          <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
          <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
          <Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/>
        </Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTemplateColumn Header="RISCHIO" Width="90" SortMemberPath="Rischio">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Ellipse Width="7" Height="7" Margin="0,0,8,0" VerticalAlignment="Center">
              <Ellipse.Style>
                <Style TargetType="Ellipse">
                  <Setter Property="Fill" Value="{DynamicResource Verde}"/>
                  <Style.Triggers>
                    <DataTrigger Binding="{Binding Rischio}" Value="medio"><Setter Property="Fill" Value="{DynamicResource Arancio}"/></DataTrigger>
                    <DataTrigger Binding="{Binding Rischio}" Value="alto"><Setter Property="Fill" Value="{DynamicResource Rosso}"/></DataTrigger>
                  </Style.Triggers>
                </Style>
              </Ellipse.Style>
            </Ellipse>
            <TextBlock Text="{Binding RischioVis}" Foreground="{DynamicResource Testo2}"/>
          </StackPanel>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
    <DataGridTemplateColumn Header="ESITO" Width="120" SortMemberPath="Esito">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <TextBlock Text="{Binding EsitoVis}" VerticalAlignment="Center" FontWeight="SemiBold">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="{DynamicResource Arancio}"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Esito}" Value="A posto"><Setter Property="Foreground" Value="{DynamicResource Verde}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Esito}" Value="Errore"><Setter Property="Foreground" Value="{DynamicResource Rosso}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Esito}" Value="Info"><Setter Property="Foreground" Value="{DynamicResource Testo3}"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
  </DataGrid.Columns>
</DataGrid>
'@

$Script:XamlColonnaCategoria = '<DataGridTextColumn Header="CATEGORIA" Binding="{Binding CategoriaVis}" Width="0.9*" IsReadOnly="True"/>'

$Script:XamlAnteprima = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Anteprima" Width="1080" Height="600" MinWidth="760" MinHeight="400" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Accento}"/>
    <DockPanel Margin="26,20,26,18">
      <TextBlock x:Name="TitoloAnteprima" DockPanel.Dock="Top" FontSize="18" FontWeight="SemiBold"/>
      <TextBlock x:Name="Intro" DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,8,0,16" LineHeight="19"/>
      <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button x:Name="BtnIndietro" Content="Torna indietro" IsCancel="True"/>
        <Button x:Name="BtnConferma" Content="Conferma" Style="{DynamicResource Primario}" Margin="4,0,0,0"/>
      </StackPanel>
      <Border CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}" Padding="1">
        <DataGrid x:Name="Lista" AutoGenerateColumns="False" IsReadOnly="True">
          <DataGrid.Columns>
            <DataGridTextColumn Header="CATEGORIA" Binding="{Binding Categoria}" Width="0.8*"/>
            <DataGridTextColumn Header="VOCE" Binding="{Binding Voce}" Width="2*"/>
            <DataGridTextColumn Header="ADESSO" Binding="{Binding Da}" Width="1.3*"/>
            <DataGridTextColumn Header="DIVENTERÀ" Binding="{Binding A}" Width="1.3*"/>
            <DataGridTextColumn Header="RISCHIO" Binding="{Binding Rischio}" Width="0.5*"/>
            <DataGridTextColumn Header="NOTE" Binding="{Binding Note}" Width="1.3*"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>
    </DockPanel>
  </DockPanel>
</Window>
'@

# ---------- Finestra per scrivere un nome (profili personalizzati) ----------
$Script:XamlNome = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="440" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Accento}"/>
    <StackPanel Margin="24,20,24,20">
      <TextBlock x:Name="Titolo" FontSize="15" FontWeight="SemiBold"/>
      <TextBlock x:Name="Testo" TextWrapping="Wrap" Margin="0,8,0,12" Foreground="{DynamicResource Testo2}"/>
      <Border CornerRadius="6" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}">
        <TextBox x:Name="Campo" Padding="10,8" Foreground="{DynamicResource Testo}" MaxLength="40"/>
      </Border>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
        <Button x:Name="BtnAnnulla" Content="Annulla" IsCancel="True" MinWidth="90"/>
        <Button x:Name="BtnOk" Content="Salva" IsDefault="True" MinWidth="90" Style="{DynamicResource Primario}"/>
      </StackPanel>
    </StackPanel>
  </DockPanel>
</Window>
'@

# Chiede un testo all'utente. Restituisce il testo oppure $null se annulla.
function Chiedi-Testo([string]$Titolo, [string]$Testo, [string]$Valore = '') {
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlNome)
    Applica-TemaFinestra $w
    $w.Owner = $Script:Finestra
    $w.Title = $Titolo
    $w.FindName('Titolo').Text = $Titolo
    $w.FindName('Testo').Text = $Testo
    $campo = $w.FindName('Campo'); $campo.Text = $Valore
    $w.FindName('BtnOk').add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $w.add_ContentRendered({ $c = $this.FindName('Campo'); [void]$c.Focus(); $c.SelectAll() })
    if ($w.ShowDialog() -eq $true) { return $campo.Text.Trim() }
    return $null
}

# ---------- Profili personalizzati (salvati in Dati\profili.json) ----------
$Script:FileProfili = Join-Path $Script:CartellaDati 'profili.json'

function Leggi-ProfiliPersonali {
    try {
        if (Test-Path -LiteralPath $Script:FileProfili) {
            $d = Get-Content -LiteralPath $Script:FileProfili -Raw -Encoding UTF8 | ConvertFrom-Json
            return @($d.Profili | Where-Object { $_.Nome })
        }
    } catch { Scrivi-Log "Impossibile leggere profili.json: $($_.Exception.Message)" 'AVVISO' }
    return @()
}

function Salva-ProfiliPersonali($Profili) {
    $lista = @($Profili | ForEach-Object { [ordered]@{ Nome = [string]$_.Nome; Creato = [string]$_.Creato; Voci = @($_.Voci) } })
    Salva-Json ([ordered]@{ Versione = $Script:Versione; Profili = $lista }) $Script:FileProfili
}

# Ricrea i pulsanti dei profili personalizzati (clic = applica, clic destro = elimina).
function Aggiorna-PulsantiPersonali {
    $pannello = $Script:Finestra.FindName('ProfiliPersonali')
    $pannello.Children.Clear()
    foreach ($k in @($Script:PulsantiProfilo.Keys | Where-Object { $_ -like 'pers:*' })) { $Script:PulsantiProfilo.Remove($k) }
    foreach ($p in (Leggi-ProfiliPersonali)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = [string]$p.Nome
        $b.Tag = [string]$p.Nome
        $b.ToolTip = "Profilo personale con $(@($p.Voci).Count) voci.  Clic: applica  ·  Clic destro: elimina"
        $b.add_Click({ try { Applica-ProfiloPersonale ([string]$this.Tag) } catch { Mostra-Errore $_ } })
        $b.add_MouseRightButtonUp({ try { Elimina-ProfiloPersonale ([string]$this.Tag) } catch { Mostra-Errore $_ } })
        [void]$pannello.Children.Add($b)
        $Script:PulsantiProfilo["pers:$($p.Nome)"] = $b
    }
}

function Salva-ProfiloPersonale {
    # Per le impostazioni NVIDIA si salva anche il valore scelto nel menu: "nv.energia=1"
    $ids = @($Script:TutteLeRighe | Where-Object { $_.Selezionata } | ForEach-Object {
        if ($_.Opzioni -and $_.Scelta) { "$($_.Id)=$($_.Scelta.Valore)" }
        elseif ($_.Scelte -and $_.SceltaVoce -and $_.SceltaVoce.Valore -ne 'Consigliato') { "$($_.Id)=$($_.SceltaVoce.Valore)" }
        else { $_.Id } })
    if ($ids.Count -eq 0) { [void](Mostra-Messaggio 'Accendi prima le voci che vuoi nel profilo, poi premi "Salva profilo".' 'Salva profilo'); return }
    $nome = Chiedi-Testo 'Salva profilo' "Nome del profilo ($($ids.Count) voci accese adesso):" 'Il mio profilo'
    if (-not $nome) { return }
    $profili = @(Leggi-ProfiliPersonali)
    if ($profili | Where-Object { $_.Nome -eq $nome }) {
        if ((Mostra-Messaggio "Esiste già un profilo chiamato '$nome'. Vuoi sostituirlo con la selezione attuale?" 'Salva profilo' 'YesNo' 'Warning') -ne 'Yes') { return }
        $profili = @($profili | Where-Object { $_.Nome -ne $nome })
    }
    $profili += [pscustomobject]@{ Nome = $nome; Creato = (Get-Date).ToString('s'); Voci = $ids }
    Salva-ProfiliPersonali $profili
    Aggiorna-PulsantiPersonali
    Evidenzia-Profilo "pers:$nome"
    Scrivi-Log "Profilo personale '$nome' salvato con $($ids.Count) voci." 'OK'
    Imposta-Stato "Profilo '$nome' salvato ($($ids.Count) voci)."
}

function Applica-ProfiloPersonale([string]$Nome) {
    $p = Leggi-ProfiliPersonali | Where-Object { $_.Nome -eq $Nome } | Select-Object -First 1
    if (-not $p) { return }
    $ids = @(); $valori = @{}
    foreach ($x in @($p.Voci)) {
        $parti = ([string]$x).Split('=', 2)
        $ids += $parti[0]
        if ($parti.Count -eq 2) { $valori[$parti[0]] = $parti[1] }
    }
    $n = 0
    [void](Applica-PresetNvidia 'Attuale' -Silenzioso)
    foreach ($r in $Script:TutteLeRighe) {
        if ($r.Opzioni) {
            # impostazione NVIDIA: si sceglie nel menu il valore salvato (i profili vecchi senza valore la lasciano com'è)
            if ($valori.ContainsKey($r.Id)) {
                $op = $r.Opzioni | Where-Object { $_.Valore -eq $valori[$r.Id] } | Select-Object -First 1
                if ($op) { $r.Scelta = $op; $n++ }
            } elseif ($ids -contains $r.Id) { $n++ }
            continue
        }
        if ($r.Scelte) {
            $val = $(if ($valori.ContainsKey($r.Id)) { $valori[$r.Id] } else { 'Consigliato' })
            $op = $r.Scelte | Where-Object { $_.Valore -eq $val } | Select-Object -First 1
            if ($op) { $r.ImpostaSceltaSenzaAccendere($op) }
        }
        $r.Selezionata = ($ids -contains $r.Id)
        if ($r.Selezionata) { $n++ }
    }
    $mancanti = $ids.Count - $n
    Aggiorna-Intestazioni
    Evidenzia-Profilo "pers:$Nome"
    $extra = $(if ($mancanti -gt 0) { " ($mancanti voci del profilo non sono presenti su questo PC)" } else { '' })
    Scrivi-Log "Profilo personale '$Nome' selezionato: $n voci accese$extra."
    Imposta-Stato "Profilo '$Nome': $n voci accese$extra. Controlla le schede e poi premi 'Anteprima e applica'."
}

function Elimina-ProfiloPersonale([string]$Nome) {
    if ((Mostra-Messaggio "Eliminare il profilo '$Nome'?`nVerrà tolto solo dall'elenco dei profili: le impostazioni del PC non cambiano." 'Elimina profilo' 'YesNo' 'Warning') -ne 'Yes') { return }
    Salva-ProfiliPersonali @(Leggi-ProfiliPersonali | Where-Object { $_.Nome -ne $Nome })
    Aggiorna-PulsantiPersonali
    Scrivi-Log "Profilo personale '$Nome' eliminato."
    Imposta-Stato "Profilo '$Nome' eliminato."
}

# ---------- Tabella della sezione NVIDIA: un menu a tendina per ogni impostazione ----------
$Script:XamlGrigliaNvidia = @'
<DataGrid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
          AutoGenerateColumns="False" CanUserAddRows="False" EnableRowVirtualization="False" MinRowHeight="40">
  <DataGrid.Columns>
    <DataGridTextColumn Header="AREA" Binding="{Binding AreaVis}" Width="1.05*" MinWidth="150" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock">
          <Setter Property="Foreground" Value="{DynamicResource Testo3}"/>
          <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
        </Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTextColumn Header="IMPOSTAZIONE" Binding="{Binding NomeVis}" Width="2.6*" MinWidth="220" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock"><Setter Property="TextTrimming" Value="CharacterEllipsis"/><Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/></Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTextColumn Header="ADESSO" Binding="{Binding AttualeVis}" Width="1.2*" IsReadOnly="True">
      <DataGridTextColumn.ElementStyle>
        <Style TargetType="TextBlock">
          <Setter Property="Foreground" Value="{DynamicResource Testo2}"/>
          <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
          <Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/>
        </Style>
      </DataGridTextColumn.ElementStyle>
    </DataGridTextColumn>
    <DataGridTemplateColumn Header="DA IMPOSTARE" Width="1.8*" MinWidth="200">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <ComboBox ItemsSource="{Binding Opzioni}" DisplayMemberPath="Testo" Margin="0,5"
                    SelectedItem="{Binding Scelta, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"/>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
    <DataGridTemplateColumn Header="STATO" Width="130" SortMemberPath="Esito">
      <DataGridTemplateColumn.CellTemplate>
        <DataTemplate>
          <TextBlock Text="{Binding EsitoVis}" VerticalAlignment="Center" FontWeight="SemiBold">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="{DynamicResource Arancio}"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Esito}" Value="Predefinito"><Setter Property="Foreground" Value="{DynamicResource Testo3}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Esito}" Value="Personalizzato"><Setter Property="Foreground" Value="{DynamicResource Verde}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Esito}" Value="Errore"><Setter Property="Foreground" Value="{DynamicResource Rosso}"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </DataTemplate>
      </DataGridTemplateColumn.CellTemplate>
    </DataGridTemplateColumn>
  </DataGrid.Columns>
</DataGrid>
'@

# ---------- Sezione Driver ----------
# Sezione "Driver video": una riga per ogni scheda video, con scelta della versione e installazione pulita.
$Script:XamlVideo = @'
<ScrollViewer xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
  <StackPanel x:Name="PannelloGpu">
    <Border Padding="18,14" CornerRadius="8" Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1">
      <StackPanel>
        <DockPanel>
          <Button x:Name="BtnControllaVideo" DockPanel.Dock="Right" Style="{DynamicResource Primario}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE721;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Controlla aggiornamenti"/></StackPanel>
          </Button>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="&#xE7F4;" Style="{DynamicResource Icona}" Foreground="{DynamicResource Testo3}" Margin="0,0,10,0"/>
            <TextBlock Text="SCHEDE VIDEO  ·  INSTALLAZIONE PULITA" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}" VerticalAlignment="Center"/>
          </StackPanel>
        </DockPanel>
        <StackPanel x:Name="ElencoGpu" Margin="0,8,0,0"/>
      </StackPanel>
    </Border>
    <Border Margin="0,14,0,0" Padding="18,14" CornerRadius="8" Background="{DynamicResource Superficie}" BorderBrush="{DynamicResource Bordo}" BorderThickness="1">
      <StackPanel>
        <TextBlock Text="COME FUNZIONA L'INSTALLAZIONE PULITA" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}"/>
        <TextBlock TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,8,0,0" LineHeight="20"
                   Text="1. Scegli la versione (la più recente, la stessa già installata o una precedente).   2. Il programma la scarica dal sito ufficiale del produttore e controlla la firma digitale.   3. Punto di ripristino.   4. Rimozione dei driver video presenti, comprese le vecchie versioni rimaste nell'archivio di Windows, con lo strumento ufficiale di Windows (pnputil).   5. Installazione del nuovo driver e verifica della versione. Con la Modalità prova accesa vedi tutti i passi senza che il driver venga toccato."/>
      </StackPanel>
    </Border>
  </StackPanel>
</ScrollViewer>
'@

# Sezione "Altri driver": dispositivi (senza le schede video) e aggiornamenti di Windows Update.
$Script:XamlDriver = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
           xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="PannelloDriver">
  <DockPanel DockPanel.Dock="Top" Margin="0,0,0,12">
    <Button x:Name="BtnControllaDriver" DockPanel.Dock="Right" Style="{DynamicResource Primario}">
      <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE721;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Controlla aggiornamenti"/></StackPanel>
    </Button>
    <TextBlock Text="DISPOSITIVI E DRIVER INSTALLATI" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}" VerticalAlignment="Center" Margin="2,0,0,0"/>
  </DockPanel>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto" MinHeight="80"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="8" BorderThickness="1" Padding="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}">
      <DataGrid x:Name="GrigliaDispositivi" AutoGenerateColumns="False" IsReadOnly="True">
        <DataGrid.Columns>
          <DataGridTextColumn Header="DISPOSITIVO" Binding="{Binding Dispositivo}" Width="2.2*"/>
          <DataGridTextColumn Header="PRODUTTORE" Binding="{Binding Produttore}" Width="1.2*"/>
          <DataGridTextColumn Header="VERSIONE" Binding="{Binding Versione}" Width="1*"/>
          <DataGridTextColumn Header="DATA" Binding="{Binding Data}" Width="96"/>
          <DataGridTextColumn Header="ULTIMA DISPONIBILE" Binding="{Binding Ultima}" Width="1.3*"/>
          <DataGridTextColumn Header="FONTE" Binding="{Binding Fonte}" Width="128"/>
          <DataGridTemplateColumn Header="" Width="112">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <Button Content="Produttore" Tag="{Binding}" Style="{DynamicResource Fantasma}" Padding="8,3" Margin="0" ToolTip="Apri la pagina dei driver del produttore nel browser"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
        </DataGrid.Columns>
      </DataGrid>
    </Border>
    <DockPanel Grid.Row="1" Margin="2,14,0,8">
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="BtnInstallaSelezionati" ToolTip="Installa i driver con la casella accesa, uno dopo l'altro (un solo punto di ripristino)">
          <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE896;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Installa selezionati"/></StackPanel>
        </Button>
        <Button x:Name="BtnInstallaTutto" Style="{DynamicResource Primario}" Margin="4,0,0,0" ToolTip="Installa tutti i driver in elenco, uno dopo l'altro (un solo punto di ripristino)">
          <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE73E;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Installa tutto"/></StackPanel>
        </Button>
      </StackPanel>
      <TextBlock x:Name="TestoAggiornamenti" Text="AGGIORNAMENTI DISPONIBILI" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource Testo3}" VerticalAlignment="Center"/>
    </DockPanel>
    <Border Grid.Row="2" CornerRadius="8" BorderThickness="1" Padding="1" MaxHeight="200" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}">
      <DataGrid x:Name="GrigliaAggiornamenti" AutoGenerateColumns="False" CanUserAddRows="False">
        <DataGrid.Columns>
          <DataGridTemplateColumn Header="" Width="54" CanUserResize="False">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <CheckBox IsChecked="{Binding Selezionato, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Style="{DynamicResource InterruttorePiccolo}"
                          HorizontalAlignment="Center" VerticalAlignment="Center" ToolTip="Acceso = installa questo driver con 'Installa selezionati'"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="DRIVER" Binding="{Binding Driver}" Width="2.6*" IsReadOnly="True"/>
          <DataGridTextColumn Header="VERSIONE" Binding="{Binding Versione}" Width="1*" IsReadOnly="True"/>
          <DataGridTextColumn Header="DATA" Binding="{Binding Data}" Width="0.9*" IsReadOnly="True"/>
          <DataGridTextColumn Header="DIMENSIONE" Binding="{Binding Dimensione}" Width="0.7*" IsReadOnly="True"/>
          <DataGridTextColumn Header="FONTE" Binding="{Binding Fonte}" Width="1.2*" IsReadOnly="True"/>
          <DataGridTemplateColumn Header="" Width="120">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <Button Content="Installa..." Tag="{Binding}" Padding="10,3" Margin="0,3"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
        </DataGrid.Columns>
      </DataGrid>
    </Border>
  </Grid>
</DockPanel>
'@

# ---------- Sezione "App installate" ----------
$Script:XamlApp = @'
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
           xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="PannelloApp">
  <DockPanel DockPanel.Dock="Top" Margin="0,0,0,12">
    <Button x:Name="BtnAggiornaApp" DockPanel.Dock="Right" ToolTip="Rilegge l'elenco dei programmi installati">
      <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72C;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Aggiorna elenco"/></StackPanel>
    </Button>
    <ComboBox x:Name="FiltroTipoApp" DockPanel.Dock="Right" Width="190" Margin="0,0,8,0" SelectedIndex="0" VerticalAlignment="Center">
      <ComboBoxItem Content="Tutte le app"/>
      <ComboBoxItem Content="Solo programmi classici"/>
      <ComboBoxItem Content="Solo app dello Store"/>
    </ComboBox>
    <Grid Margin="0,0,10,0">
      <TextBox x:Name="CercaApp" VerticalContentAlignment="Center" Padding="30,6,8,6"/>
      <TextBlock Text="&#xE721;" Style="{DynamicResource Icona}" FontSize="13" Foreground="{DynamicResource Testo3}" Margin="10,0,0,0" IsHitTestVisible="False"/>
      <TextBlock x:Name="SuggerimentoCerca" Text="Cerca per nome o editore..." Foreground="{DynamicResource Testo3}" Margin="31,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
    </Grid>
  </DockPanel>
  <DockPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
      <Button x:Name="BtnDisinstallaApp" Style="{DynamicResource Primario}" ToolTip="Avvia la disinstallazione dell'app scelta, poi cerca e rimuove i residui (cartelle e chiavi di registro), con backup">
        <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE74D;" Style="{DynamicResource Icona}" FontSize="13" Margin="0,0,8,0"/><TextBlock Text="Disinstalla e pulisci..."/></StackPanel>
      </Button>
    </StackPanel>
    <TextBlock x:Name="TestoApp" VerticalAlignment="Center" Foreground="{DynamicResource Testo2}" TextWrapping="Wrap" Margin="2,0,16,0"/>
  </DockPanel>
  <Border CornerRadius="8" BorderThickness="1" Padding="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}">
    <DataGrid x:Name="GrigliaApp" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single">
      <DataGrid.Columns>
        <DataGridTemplateColumn Header="APP" Width="2.2*" SortMemberPath="Nome" CanUserSort="True">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <DockPanel Margin="2,3" LastChildFill="True">
                <Grid DockPanel.Dock="Left" Width="22" Height="22" Margin="0,0,10,0" VerticalAlignment="Center">
                  <TextBlock x:Name="IconaGenerica" Text="&#xE74C;" Style="{DynamicResource Icona}" FontSize="16" Foreground="{DynamicResource Testo3}"
                             HorizontalAlignment="Center" Visibility="Collapsed"/>
                  <Image Source="{Binding Icona}" Width="22" Height="22" RenderOptions.BitmapScalingMode="HighQuality"/>
                </Grid>
                <TextBlock Text="{Binding Nome}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
              </DockPanel>
              <DataTemplate.Triggers>
                <DataTrigger Binding="{Binding Icona}" Value="{x:Null}">
                  <Setter TargetName="IconaGenerica" Property="Visibility" Value="Visible"/>
                </DataTrigger>
              </DataTemplate.Triggers>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>
        <DataGridTextColumn Header="EDITORE" Binding="{Binding Editore}" Width="1.4*"/>
        <DataGridTextColumn Header="VERSIONE" Binding="{Binding Versione}" Width="0.9*"/>
        <DataGridTextColumn Header="DIMENSIONE" Binding="{Binding Dimensione}" Width="0.8*" SortMemberPath="Byte"/>
        <DataGridTextColumn Header="INSTALLATA" Binding="{Binding Data}" Width="0.8*"/>
        <DataGridTextColumn Header="TIPO" Binding="{Binding TipoVis}" Width="1.2*"/>
      </DataGrid.Columns>
    </DataGrid>
  </Border>
</DockPanel>
'@

# Finestra con l'elenco dei residui trovati (cartelle e chiavi di registro), ognuno con il suo interruttore.
$Script:XamlResidui = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Residui" Width="980" Height="560" MinWidth="720" MinHeight="380" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Accento}"/>
    <DockPanel Margin="26,20,26,18">
      <TextBlock x:Name="Titolo" DockPanel.Dock="Top" FontSize="18" FontWeight="SemiBold"/>
      <TextBlock x:Name="Intro" DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,8,0,16" LineHeight="19"/>
      <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button x:Name="BtnIndietro" Content="Non rimuovere niente" IsCancel="True"/>
        <Button x:Name="BtnConferma" Content="Rimuovi i residui accesi" Style="{DynamicResource Primario}" Margin="4,0,0,0"/>
      </StackPanel>
      <Border CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}" Padding="1">
        <DataGrid x:Name="Lista" AutoGenerateColumns="False" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="" Width="54" CanUserResize="False">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding Includi, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Style="{DynamicResource InterruttorePiccolo}"
                            HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="TIPO" Binding="{Binding TipoVis}" Width="130" IsReadOnly="True"/>
            <DataGridTextColumn Header="PERCORSO" Binding="{Binding Percorso}" Width="4*" IsReadOnly="True"/>
            <DataGridTextColumn Header="DIMENSIONE" Binding="{Binding Dimensione}" Width="100" IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>
    </DockPanel>
  </DockPanel>
</Window>
'@

# ---------- Finestra "Annulla tutto": un interruttore per ogni voce modificata ----------
$Script:XamlAnnulla = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Annulla tutto" Width="1080" Height="600" MinWidth="760" MinHeight="400" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Background="{DynamicResource Sfondo}" Foreground="{DynamicResource Testo}" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="2" Background="{DynamicResource Accento}"/>
    <DockPanel Margin="26,20,26,18">
      <TextBlock x:Name="Titolo" DockPanel.Dock="Top" FontSize="18" FontWeight="SemiBold"/>
      <TextBlock x:Name="Intro" DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="{DynamicResource Testo2}" Margin="0,8,0,16" LineHeight="19"/>
      <DockPanel DockPanel.Dock="Bottom" Margin="0,16,0,0">
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
          <Button x:Name="BtnTutte" Content="Accendi tutte"/>
          <Button x:Name="BtnNessuna" Content="Spegni tutte" Margin="4,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnIndietro" Content="Torna indietro" IsCancel="True"/>
          <Button x:Name="BtnConferma" Content="Conferma" Style="{DynamicResource Primario}" Margin="4,0,0,0"/>
        </StackPanel>
      </DockPanel>
      <Border CornerRadius="8" BorderThickness="1" BorderBrush="{DynamicResource Bordo}" Background="{DynamicResource Superficie}" Padding="1">
        <DataGrid x:Name="Lista" AutoGenerateColumns="False" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="" Width="54" CanUserResize="False">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding Includi, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Style="{DynamicResource InterruttorePiccolo}"
                            HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="CATEGORIA" Binding="{Binding Categoria}" Width="0.8*" IsReadOnly="True"/>
            <DataGridTextColumn Header="VOCE" Binding="{Binding Voce}" Width="2*" IsReadOnly="True"/>
            <DataGridTextColumn Header="MODIFICATA IL" Binding="{Binding Modificata}" Width="0.9*" IsReadOnly="True"/>
            <DataGridTextColumn Header="TORNA A" Binding="{Binding TornaA}" Width="1.3*" IsReadOnly="True"/>
            <DataGridTextColumn Header="NOTE" Binding="{Binding Note}" Width="1.1*" IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>
    </DockPanel>
  </DockPanel>
</Window>
'@

# Programmi che non si disinstallano da qui: driver, runtime usati da altri programmi, componenti di Windows.
$Script:AppNonDisinstallabili = 'Microsoft Visual C\+\+|\.NET (Framework|Runtime|Desktop Runtime)|Windows (SDK|Driver|Software Development)|Microsoft Edge( WebView2)?$|Microsoft Update Health|Windows PC Health|NVIDIA (Graphics|HD Audio|PhysX|Platform|USB|FrameView)|AMD (Chipset|Software)|Realtek|Intel\(R\)|Dolby|Synaptics|ELAN|Microsoft GameInput|Teams Machine-Wide|Office 16 Click-to-Run|DirectX'
# Nomi troppo generici per cercare residui con quel nome.
$Script:NomiGenerici = @('microsoft', 'windows', 'program files', 'programs', 'common files', 'system', 'system32', 'update', 'updates', 'driver', 'drivers', 'intel', 'nvidia', 'amd', 'realtek',
    'google', 'adobe', 'apple', 'packages', 'temp', 'cache', 'data', 'app', 'apps', 'tools', 'games', 'software', 'users', 'public', 'default', 'classes', 'policies', 'wow6432node', 'microsoft corporation')

$Script:ElencoApp = @()
$Script:CacheIcone = @{}

# Icona di un programma: "C:\...\app.exe,0", un file .ico/.dll/.exe oppure un'immagine (.png).
# Restituisce un'immagine pronta per la tabella, oppure $null (allora si vede un'icona generica).
function Leggi-IconaFile([string]$Rif) {
    if (-not $Rif) { return $null }
    if ($Script:CacheIcone.ContainsKey($Rif)) { return $Script:CacheIcone[$Rif] }
    $img = $null
    try {
        $file = $Rif.Trim(); $indice = 0
        if ($file -match '^(.*?),\s*(-?\d+)$') { $file = $Matches[1]; $indice = [int]$Matches[2] }
        $file = [Environment]::ExpandEnvironmentVariables($file.Trim().Trim('"'))
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            if ($file -match '\.(png|jpe?g|bmp)$') {
                $b = New-Object System.Windows.Media.Imaging.BitmapImage
                $b.BeginInit(); $b.UriSource = New-Object Uri($file); $b.DecodePixelWidth = 32
                $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $b.EndInit()
                $img = $b
            } else {
                if (-not ('OttWin.IconeShell' -as [type])) {
                    Add-Type -Namespace OttWin -Name IconeShell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern uint ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, uint n);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
'@
                }
                $grandi = New-Object IntPtr[] 1; $piccole = New-Object IntPtr[] 1
                $n = [OttWin.IconeShell]::ExtractIconEx($file, $indice, $grandi, $piccole, 1)
                if ($n -gt 0 -and $grandi[0] -ne [IntPtr]::Zero) {
                    try {
                        $img = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($grandi[0], [System.Windows.Int32Rect]::Empty,
                            [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                    } finally { foreach ($h in @($grandi[0], $piccole[0])) { if ($h -ne [IntPtr]::Zero) { [void][OttWin.IconeShell]::DestroyIcon($h) } } }
                }
            }
            if ($img) { $img.Freeze() }
        }
    } catch { $img = $null }
    $Script:CacheIcone[$Rif] = $img
    return $img
}

# Logo di un'app dello Store: il manifesto indica "Assets\Logo.png", ma sul disco il file
# ha spesso un suffisso di dimensione ("Logo.scale-100.png", "Logo.targetsize-32.png").
function Trova-LogoStore([string]$Cartella, [string]$Logo) {
    if (-not $Cartella -or -not $Logo) { return '' }
    $pieno = Join-Path $Cartella $Logo
    if (Test-Path -LiteralPath $pieno -PathType Leaf) { return $pieno }
    $dir = Split-Path -Parent $pieno
    if (-not (Test-Path -LiteralPath $dir)) { return '' }
    $base = [IO.Path]::GetFileNameWithoutExtension($pieno); $est = [IO.Path]::GetExtension($pieno)
    $varianti = @(Get-ChildItem -LiteralPath $dir -Filter "$base.*$est" -File -ErrorAction SilentlyContinue)
    if ($varianti.Count -eq 0) { return '' }
    foreach ($pref in @('targetsize-32.', 'targetsize-48.', 'scale-100.', 'scale-125.', 'scale-150.', 'scale-200.')) {
        $v = $varianti | Where-Object { $_.Name -like "*$pref*" -and $_.Name -notlike '*contrast*' } | Select-Object -First 1
        if ($v) { return $v.FullName }
    }
    $v = $varianti | Where-Object { $_.Name -notlike '*contrast*' } | Select-Object -First 1
    return $(if ($v) { $v.FullName } else { '' })
}

function Leggi-AppInstallate {
    $app = New-Object System.Collections.ArrayList
    $visti = @{}
    $chiavi = @(
        @('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'Programma'),
        @('HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'Programma (32 bit)'),
        @('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'Programma (utente)'))
    foreach ($c in $chiavi) {
        foreach ($k in @(Get-ChildItem -LiteralPath "Registry::$($c[0])" -ErrorAction SilentlyContinue)) {
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                $nome = ([string]$p.DisplayName).Trim()
                if (-not $nome -or -not $p.UninstallString) { continue }
                if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or [string]$p.ReleaseType -match 'Update|Hotfix') { continue }
                $id = "$nome|$($p.DisplayVersion)"
                if ($visti.ContainsKey($id)) { continue }
                $visti[$id] = $true
                $r = New-Object OttWin.RigaApp
                $r.Nome = $nome; $r.Editore = ([string]$p.Publisher).Trim(); $r.Versione = [string]$p.DisplayVersion
                $kb = 0; try { $kb = [int64]$p.EstimatedSize } catch { }
                $r.Byte = $kb * 1KB; $r.Dimensione = $(if ($kb -gt 0) { Formatta-Dimensione ($kb * 1KB) } else { '' })
                $d = [string]$p.InstallDate
                $r.Data = ''
                try { $r.Data = ([datetime]::ParseExact($d, 'yyyyMMdd', [cultureinfo]::InvariantCulture)).ToString('dd/MM/yyyy') } catch { }
                $r.Tipo = $c[1]
                $r.Chiave = ($k.Name -replace '^HKEY_LOCAL_MACHINE', 'HKEY_LOCAL_MACHINE' -replace '^HKEY_CURRENT_USER', 'HKEY_CURRENT_USER')
                $r.Disinstalla = [string]$p.UninstallString; $r.DisinstallaSilenzioso = [string]$p.QuietUninstallString
                $r.Cartella = ([string]$p.InstallLocation).Trim().Trim('"').TrimEnd('\')
                $r.Protetta = ($nome -match $Script:AppNonDisinstallabili)
                # Icona: quella indicata dal programma; se manca, l'eseguibile del disinstallatore se è proprio dell'app
                $r.FileIcona = [string]$p.DisplayIcon
                if (-not $r.FileIcona -and $r.Cartella -and $r.Disinstalla -match '^\s*"?([^"]+?\.exe)') {
                    $exe = $Matches[1]; if ($exe -like "$($r.Cartella)\*" -and (Split-Path -Leaf $exe) -notmatch '^(unins|uninst|uninstall)') { $r.FileIcona = $exe }
                }
                $r.Icona = Leggi-IconaFile $r.FileIcona
                # Ultima possibilità: il primo programma .exe nella cartella di installazione
                if (-not $r.Icona -and $r.Cartella -and (Test-Path -LiteralPath $r.Cartella -PathType Container)) {
                    $exe = Get-ChildItem -LiteralPath $r.Cartella -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch '^(unins|uninst|uninstall|update|setup|crash|helper)' } | Select-Object -First 1
                    if ($exe) { $r.FileIcona = $exe.FullName; $r.Icona = Leggi-IconaFile $exe.FullName }
                }
                [void]$app.Add($r)
            } catch { }
        }
    }
    # App dello Store dell'utente (non i framework, non i componenti di sistema, non quelle protette)
    foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if ($p.IsFramework -or $p.NonRemovable -or "$($p.SignatureKind)" -eq 'System' -or (E-AppProtetta $p)) { continue }
        $r = New-Object OttWin.RigaApp
        # Nome mostrato dal manifesto dell'app; se è un riferimento a una risorsa si usa il nome del pacchetto
        $nome = ''; $editore = ''; $logo = ''
        try {
            $man = (Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction Stop).Package
            $nome = [string]$man.Properties.DisplayName; $editore = [string]$man.Properties.PublisherDisplayName
            # Logo piccolo dell'app (quello della barra delle applicazioni), altrimenti il logo del pacchetto
            try { $logo = [string]@($man.Applications.Application)[0].VisualElements.Square44x44Logo } catch { }
            if (-not $logo) { $logo = [string]$man.Properties.Logo }
        } catch { }
        if (-not $nome -or $nome -like 'ms-resource:*') { $nome = ($p.Name -replace '^[^.]+\.', '' -creplace '([a-z])([A-Z])', '$1 $2') }
        $r.Nome = $(if ($nome) { $nome } else { $p.Name })
        $r.FileIcona = Trova-LogoStore ([string]$p.InstallLocation) $logo
        $r.Icona = Leggi-IconaFile $r.FileIcona
        if (-not $editore -or $editore -like 'ms-resource:*') { $editore = ([string]$p.Publisher -replace '^CN=([^,]+).*$', '$1').Trim('"') }
        $r.Editore = $editore; $r.Versione = [string]$p.Version
        $r.Dimensione = ''; $r.Data = ''; $r.Tipo = 'App dello Store'; $r.Pacchetto = $p.PackageFullName; $r.Cartella = [string]$p.InstallLocation
        [void]$app.Add($r)
    }
    return @($app | Sort-Object Nome)
}

function Mostra-AppInstallate {
    if (-not $Script:GrigliaApp) { return }
    $testo = [string]$Script:CercaApp.Text
    $tipo = $Script:FiltroTipoApp.SelectedIndex
    $lista = @($Script:ElencoApp | Where-Object {
        (-not $testo -or $_.Nome -like "*$testo*" -or $_.Editore -like "*$testo*") -and
        ($tipo -eq 0 -or ($tipo -eq 1 -and $_.Tipo -ne 'App dello Store') -or ($tipo -eq 2 -and $_.Tipo -eq 'App dello Store')) })
    $Script:GrigliaApp.ItemsSource = $lista
    $nProg = @($Script:ElencoApp | Where-Object { $_.Tipo -ne 'App dello Store' }).Count
    $Script:TestoApp.Text = "$($Script:ElencoApp.Count) app installate ($nProg programmi classici, $($Script:ElencoApp.Count - $nProg) app dello Store)  ·  mostrate: $($lista.Count).  Scegli una riga e premi 'Disinstalla e pulisci'."
}

function Aggiorna-AppInstallate {
    Imposta-Stato 'Leggo l''elenco delle app installate (sola lettura)...'
    Imposta-Avanzamento -1
    try { $Script:ElencoApp = @(Leggi-AppInstallate) } finally { Imposta-Avanzamento $null }
    Mostra-AppInstallate
    Imposta-Stato "Elenco app aggiornato: $($Script:ElencoApp.Count) app."
}

# "Spotify 1.2.3 (x64)" -> "Spotify";  "Google LLC" -> "Google"
function Pulisci-NomeApp([string]$Nome) {
    $n = $Nome -replace '[®™©]', ''
    $n = $n -replace '\s*[\(\[][^\)\]]*[\)\]]', ''   # tutto ciò che è tra parentesi: "(x64 it)", "(64-bit)", "[versione 2]"...
    $n = $n -replace '\s+-\s+.*$', ''
    $n = $n -replace '\s+v?\d+([.,]\d+)+.*$', ''
    $n = $n -replace '\s+(x64|x86|64-bit|32-bit)$', ''
    return $n.Trim()
}
function Pulisci-Editore([string]$Editore) {
    $e = $Editore -replace '[®™©,.]', ''
    $e = $e -replace '\s+(Inc|LLC|Ltd|Limited|Corporation|Corp|GmbH|SpA|S p A|SRL|S r l|AG|BV|SA|Co|Company|Software|Technologies|Technology|Entertainment|Games)\b.*$', ''
    return $e.Trim()
}

# Cartelle e chiavi di registro rimaste dopo la disinstallazione. Regole prudenti:
# solo nomi IDENTICI al nome dell'app (o alla sua cartella di installazione), mai cartelle di Windows,
# mai le cartelle principali (Programmi, AppData...), mai cartelle che contengono un'altra app installata.
function Trova-Residui($App) {
    $nome = Pulisci-NomeApp $App.Nome
    $editore = Pulisci-Editore $App.Editore
    $nomi = New-Object System.Collections.ArrayList
    foreach ($n in @($nome, ($nome -replace '\s', ''), $(if ($App.Cartella) { Split-Path -Leaf $App.Cartella }))) {
        if ($n -and $n.Length -ge 3 -and $Script:NomiGenerici -notcontains $n.ToLower() -and -not ($nomi -contains $n)) { [void]$nomi.Add($n) }
    }
    # "Google Chrome" con editore "Google" -> anche la sottocartella "Google\Chrome"
    $prodotto = $(if ($editore -and $nome -like "$editore *") { $nome.Substring($editore.Length).Trim() } else { $nome })
    # La sottocartella "Editore\Prodotto" è abbastanza precisa anche con editori grandi (Google\Chrome);
    # restano esclusi solo Windows e i produttori di driver.
    $editoreOk = ($editore -and $editore.Length -ge 3 -and @('microsoft', 'microsoft corporation', 'windows', 'intel', 'nvidia', 'amd', 'realtek', 'classes', 'policies', 'wow6432node') -notcontains $editore.ToLower())
    # "Mozilla Thunderbird" con editore "Mozilla" -> anche il nome senza editore: "Thunderbird"
    # (solo se resta un nome di almeno 4 lettere e non generico)
    if ($prodotto -ne $nome -and $prodotto.Length -ge 4 -and $Script:NomiGenerici -notcontains $prodotto.ToLower() -and -not ($nomi -contains $prodotto)) {
        [void]$nomi.Add($prodotto)
        if (($prodotto -replace '\s', '') -ne $prodotto) { [void]$nomi.Add(($prodotto -replace '\s', '')) }
    }

    $radici = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA 'Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $vietate = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, "$env:SystemDrive\") + $radici |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() }
    $altre = @($Script:ElencoApp | Where-Object { $_.Cartella -and -not [object]::ReferenceEquals($_, $App) -and $_.Nome -ne $App.Nome } | ForEach-Object { $_.Cartella.TrimEnd('\').ToLower() })

    $cartelle = New-Object System.Collections.ArrayList
    $candidati = @()
    if ($App.Cartella) { $candidati += $App.Cartella }
    foreach ($r in $radici) {
        foreach ($n in $nomi) { $candidati += (Join-Path $r $n) }
        if ($editoreOk -and $prodotto) { $candidati += (Join-Path (Join-Path $r $editore) $prodotto) }
    }
    foreach ($c in $candidati) {
        $pieno = $null
        try { if ($c -and (Test-Path -LiteralPath $c -PathType Container)) { $pieno = (Resolve-Path -LiteralPath $c).ProviderPath.TrimEnd('\') } } catch { }
        if (-not $pieno) { continue }
        $basso = $pieno.ToLower()
        if ($vietate -contains $basso -or $basso.StartsWith($env:windir.ToLower()) -or $pieno.Length -lt 12) { continue }
        # un'altra app installata vive qui dentro (o questa cartella sta dentro un'altra app)
        if (@($altre | Where-Object { $_ -eq $basso -or $_.StartsWith($basso + '\') }).Count -gt 0) { continue }
        if (@($cartelle | Where-Object { $basso -eq $_.ToLower() -or $basso.StartsWith($_.ToLower() + '\') }).Count -gt 0) { continue }
        [void]$cartelle.Add($pieno)
    }

    $chiavi = New-Object System.Collections.ArrayList
    $radiciReg = @('HKEY_CURRENT_USER\Software', 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')
    $candReg = @()
    if ($App.Chiave) { $candReg += $App.Chiave }
    foreach ($r in $radiciReg) {
        foreach ($n in $nomi) { $candReg += "$r\$n" }
        if ($editoreOk -and $prodotto) { $candReg += "$r\$editore\$prodotto" }
    }
    foreach ($k in $candReg) {
        if ($chiavi -contains $k) { continue }
        $foglia = ($k -split '\\')[-1].ToLower()
        if ($k -ne $App.Chiave -and $Script:NomiGenerici -contains $foglia) { continue }
        try { if (Test-Path -LiteralPath "Registry::$k") { [void]$chiavi.Add($k) } } catch { }
    }

    $righe = New-Object System.Collections.ArrayList
    foreach ($c in $cartelle) {
        $byte = 0; try { $byte = [int64](Get-ChildItem -LiteralPath $c -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
        $x = New-Object OttWin.RigaResiduo; $x.Includi = $true; $x.Tipo = 'Cartella'; $x.Percorso = $c; $x.Dimensione = (Formatta-Dimensione $byte)
        # Cartelle che possono contenere dati personali (posta, profili, salvataggi): spente di serie.
        if (Contiene-DatiPersonali $c $byte) { $x.Includi = $false; $x.Tipo = 'Dati personali?' }
        [void]$righe.Add($x)
    }
    foreach ($k in $chiavi) {
        $x = New-Object OttWin.RigaResiduo; $x.Includi = $true; $x.Tipo = 'Chiave di registro'; $x.Percorso = $k; $x.Dimensione = ''
        [void]$righe.Add($x)
    }
    return , $righe
}

# Una cartella nei dati dell'utente (AppData) che ha profili, posta, salvataggi o database, oppure è grande
# (oltre 100 MB), può contenere dati personali: va mostrata spenta, e la cancella solo chi la accende.
function Contiene-DatiPersonali([string]$Cartella, [int64]$Byte) {
    $utente = @($env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE) | Where-Object { $_ } | ForEach-Object { $_.ToLower() }
    $basso = $Cartella.ToLower()
    if (-not ($utente | Where-Object { $basso.StartsWith($_ + '\') })) { return $false }
    if ($basso.StartsWith((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu').ToLower())) { return $false }
    if ($Byte -gt 100MB) { return $true }
    $nomiPersonali = '^(Profiles?|Mail|ImapMail|Saves?|SaveGames?|Saved Games|Backups?|User Data|Documents|Projects?|Library|Archives?|Database|Data)$'
    if (Get-ChildItem -LiteralPath $Cartella -Directory -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $nomiPersonali } | Select-Object -First 1) { return $true }
    if (Get-ChildItem -LiteralPath $Cartella -File -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(sqlite|db|mdb|pst|ost|msf|mbox|eml|sav|kdbx|wallet)$' } | Select-Object -First 1) { return $true }
    return $false
}

function Mostra-Residui([string]$Titolo, [string]$Intro, $Righe) {
    $w = [Windows.Markup.XamlReader]::Parse($Script:XamlResidui)
    Applica-TemaFinestra $w
    $w.Owner = $Script:Finestra
    $w.Title = $Titolo
    $w.FindName('Titolo').Text = $Titolo
    $w.FindName('Intro').Text = $Intro
    $w.FindName('Lista').ItemsSource = $Righe
    $w.FindName('BtnConferma').add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    return ($w.ShowDialog() -eq $true)
}

# Avvia il programma di disinstallazione dell'app (quello del produttore, con la sua finestra).
function Avvia-Disinstallatore($App) {
    $cmd = [string]$App.Disinstalla
    if ($cmd -match '(?i)msiexec(\.exe)?"?\s+.*?(\{[0-9A-F-]{36}\})') {
        return (Esegui-Processo "$env:windir\System32\msiexec.exe" "/x $($Matches[2])" $true)
    }
    if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $arg = $Matches[2] }
    elseif ($cmd -match '^\s*(.+?\.exe)\s*(.*)$') { $exe = $Matches[1]; $arg = $Matches[2] }
    else { $exe = $cmd; $arg = '' }
    if (-not (Test-Path -LiteralPath $exe)) { throw "Il programma di disinstallazione non esiste più: $exe" }
    return (Esegui-Processo $exe $arg $true)
}

function Disinstalla-AppScelta {
    $App = $Script:GrigliaApp.SelectedItem
    if (-not $App) { [void](Mostra-Messaggio "Scegli prima un'app dall'elenco." 'Disinstalla'); return }
    if ($App.Protetta) {
        [void](Mostra-Messaggio "'$($App.Nome)' è un driver, un componente usato da altri programmi o una parte di Windows: il programma non lo disinstalla da qui.`n`nI driver si gestiscono nelle sezioni 'Driver video' e 'Altri driver'." 'Disinstalla' 'OK' 'Warning')
        return
    }
    $prova = [bool]$Script:ChkProva.IsChecked
    $store = ($App.Tipo -eq 'App dello Store')
    $msg = "Disinstallare '$($App.Nome)'?`n`nEditore: $($App.Editore)`nVersione: $($App.Versione)`n`n"
    $msg += $(if ($store) { "È un'app dello Store: viene rimossa per il tuo utente; i suoi dati vengono eliminati da Windows. Si può reinstallare dal Microsoft Store." }
              else { "1.  Punto di ripristino`n2.  Si apre il programma di disinstallazione dell'app: seguilo fino alla fine`n3.  Il programma cerca le cartelle e le chiavi di registro rimaste e te le mostra: scegli tu cosa togliere`n4.  Le cartelle vanno nel Cestino e le chiavi di registro vengono salvate in un file .reg prima di essere tolte" })
    if ($prova) { $msg = "MODALITÀ PROVA: niente verrà disinstallato o cancellato.`n`n" + $msg }
    if ((Mostra-Messaggio $msg 'Disinstalla' 'YesNo' 'Warning') -ne 'Yes') { return }

    if ($prova) {
        Scrivi-Log "Disinstallerei '$($App.Nome)' con: $(if ($store) { "Remove-AppxPackage $($App.Pacchetto)" } else { $App.Disinstalla })" 'PROVA'
        if (-not $store) {
            $res = Trova-Residui $App
            foreach ($x in $res) { Scrivi-Log "Controllerei dopo la disinstallazione: $($x.Tipo) $($x.Percorso)" 'PROVA' }
            [void](Mostra-Messaggio "Modalità prova: '$($App.Nome)' NON è stato disinstallato.`nNel log trovi il comando che verrebbe usato e i $($res.Count) percorsi che verrebbero controllati dopo la disinstallazione (adesso contengono ancora l'app installata)." 'Modalità prova')
        } else { [void](Mostra-Messaggio "Modalità prova: l'app NON è stata rimossa. L'operazione è scritta nel log." 'Modalità prova') }
        return
    }

    if (-not (Crea-PuntoRipristino)) { return }
    Blocca-Pulsanti $true
    try {
        Scrivi-Log "--- Disinstallazione di '$($App.Nome)' $($App.Versione) ($($App.Tipo)) ---"
        if ($store) {
            Imposta-Stato "Rimuovo l'app $($App.Nome)..."
            Esegui-InBackground { param($p) Remove-AppxPackage -Package $p -ErrorAction Stop } @($App.Pacchetto) | Out-Null
            Scrivi-Log "App dello Store rimossa: $($App.Pacchetto)" 'OK'
            [void](Mostra-Messaggio "'$($App.Nome)' è stata rimossa." 'Disinstalla')
            return
        }
        Imposta-Stato "Programma di disinstallazione di $($App.Nome) aperto: completalo nella sua finestra..."
        $codice = Avvia-Disinstallatore $App
        Scrivi-Log "Programma di disinstallazione chiuso con codice $codice"
        [void](Mostra-Messaggio "Se il programma di disinstallazione di '$($App.Nome)' è ancora aperto (alcuni si riaprono in una seconda finestra), finiscilo.`n`nQuando ha finito premi OK: il programma cerca i residui." 'Disinstalla')
        $ancora = ($App.Chiave -and (Test-Path -LiteralPath "Registry::$($App.Chiave)") -and (Get-ItemProperty -LiteralPath "Registry::$($App.Chiave)" -ErrorAction SilentlyContinue).UninstallString)
        if ($ancora) {
            $r = Mostra-Messaggio "'$($App.Nome)' risulta ancora installato (forse la disinstallazione è stata annullata).`n`nVuoi cercare lo stesso i residui? Attenzione: toglierli adesso può rovinare il programma ancora installato." 'Disinstalla' 'YesNo' 'Warning'
            if ($r -ne 'Yes') { Scrivi-Log "Disinstallazione di '$($App.Nome)' non completata: nessun residuo rimosso." 'AVVISO'; return }
        }
        Imposta-Stato 'Cerco cartelle e chiavi di registro rimaste...'
        $res = Trova-Residui $App
        if ($res.Count -eq 0) {
            Scrivi-Log "Nessun residuo trovato per '$($App.Nome)'." 'OK'
            [void](Mostra-Messaggio "Disinstallazione completata: non sono rimasti residui riconoscibili di '$($App.Nome)'." 'Disinstalla')
            return
        }
        $intro = "Sono rimasti $($res.Count) elementi con il nome di '$($App.Nome)'. Spegni quelli che vuoi tenere (per esempio salvataggi o impostazioni che ti servono).`nLe cartelle vanno nel Cestino; le chiavi di registro vengono salvate in un file .reg nella cartella Dati\Backup\App prima di essere tolte (per rimetterle basta un doppio clic sul file)."
        $nPers = @($res | Where-Object { $_.Tipo -eq 'Dati personali?' }).Count
        if ($nPers -gt 0) { $intro += "`n⚠ $nPers cartelle sono segnate 'Dati personali?' e sono SPENTE: possono contenere posta, profili, salvataggi o documenti. Accendile solo se sei sicuro di non volerli più." }
        if (-not (Mostra-Residui "Residui di $($App.Nome)" $intro $res)) { Scrivi-Log 'Pulizia dei residui annullata dall''utente.'; return }
        Rimuovi-Residui $App @($res | Where-Object { $_.Includi })
    } finally {
        Blocca-Pulsanti $false
        Aggiorna-AppInstallate
    }
}

function Rimuovi-Residui($App, $Righe) {
    if (@($Righe).Count -eq 0) { return }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $sicuro = (Pulisci-NomeApp $App.Nome) -replace '[^\w\-]', '_'
    $cartellaBackup = Join-Path $Script:CartellaBackup ("App\{0}_{1:yyyyMMdd_HHmmss}" -f $sicuro, (Get-Date))
    New-Item -ItemType Directory -Force -Path $cartellaBackup | Out-Null
    $ok = 0; $errori = 0; $i = 0
    foreach ($x in $Righe) {
        $i++
        Imposta-Avanzamento (100 * ($i - 1) / @($Righe).Count)
        try {
            if ($x.Tipo -eq 'Cartella') {
                Imposta-Stato "Sposto nel Cestino: $($x.Percorso)"
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($x.Percorso, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                Scrivi-Log "  cartella nel Cestino: $($x.Percorso)" 'OK'
                # Se la cartella dell'editore resta vuota, si toglie anche quella
                $padre = Split-Path -Parent $x.Percorso
                if ($padre -and (Test-Path -LiteralPath $padre) -and @(Get-ChildItem -LiteralPath $padre -Force -ErrorAction SilentlyContinue).Count -eq 0 -and
                    @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA) -notcontains $padre) {
                    Remove-Item -LiteralPath $padre -Force -ErrorAction SilentlyContinue
                }
            } else {
                Imposta-Stato "Salvo e tolgo la chiave: $($x.Percorso)"
                $file = Join-Path $cartellaBackup ("chiave_{0:D2}.reg" -f $i)
                $codice = Esegui-Processo "$env:windir\System32\reg.exe" "export `"$($x.Percorso)`" `"$file`" /y"
                if ($codice -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "backup della chiave non riuscito (reg export codice $codice): la chiave NON viene tolta" }
                Remove-Item -LiteralPath "Registry::$($x.Percorso)" -Recurse -Force -ErrorAction Stop
                Scrivi-Log "  chiave tolta (backup in $file): $($x.Percorso)" 'OK'
            }
            $ok++
        } catch { $errori++; Scrivi-Log "  non rimosso: $($x.Percorso): $($_.Exception.Message)" 'ERRORE' }
    }
    Imposta-Avanzamento 100
    $msg = "Residui di '$($App.Nome)' rimossi: $ok.  Non rimossi: $errori.`nLe cartelle sono nel Cestino; il backup del registro è in $cartellaBackup."
    Scrivi-Log ($msg -replace "`n", ' ') $(if ($errori -gt 0) { 'AVVISO' } else { 'OK' })
    [void](Mostra-Messaggio $msg 'Pulizia completata' 'OK' $(if ($errori -gt 0) { 'Warning' } else { 'Information' }))
}

# ---------- Costruzione della finestra ----------
$Script:Finestra = [Windows.Markup.XamlReader]::Parse($Script:XamlFinestra)
$Script:Finestra.Title = "Regia $Script:Versione - ottimizzazione di Windows"
# Icona: nella barra laterale (vettoriale) e sulla finestra / barra delle applicazioni (a pixel).
# Un "ID applicazione" proprio fa sì che sulla barra delle applicazioni compaia questa icona e non quella di PowerShell.
try {
    $Script:Finestra.FindName('LogoProgramma').Source = [Windows.Markup.XamlReader]::Parse($Script:XamlLogo)
    if (-not ('OttWin.IdApp' -as [type])) {
        Add-Type -Namespace OttWin -Name IdApp -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);'
    }
    [void][OttWin.IdApp]::SetCurrentProcessExplicitAppUserModelID('Regia.Programma')
    $Script:Finestra.Icon = Crea-IconaBitmap 64
} catch { Scrivi-Log "Icona del programma non impostata: $($_.Exception.Message)" 'AVVISO' }
Applica-TemaFinestra $Script:Finestra
Imposta-Tema ([string](Leggi-Impostazioni).Tema)

# La finestra non deve mai essere più grande dello schermo (portatili piccoli, schermi 1366x768).
$area = [System.Windows.SystemParameters]::WorkArea
$Script:Finestra.Width  = [math]::Min(1320, [math]::Max(800, $area.Width - 16))
$Script:Finestra.Height = [math]::Min(860, [math]::Max(560, $area.Height - 16))
$Script:Finestra.MinWidth  = [math]::Min(1040, $Script:Finestra.Width)
$Script:Finestra.MinHeight = [math]::Min(640, $Script:Finestra.Height)

$Script:Nav                 = $Script:Finestra.FindName('Navigazione')
$Script:AreaContenuto       = $Script:Finestra.FindName('AreaContenuto')
$Script:TitoloPagina        = $Script:Finestra.FindName('TitoloPagina')
$Script:IconaPagina         = $Script:Finestra.FindName('IconaPagina')
$Script:IntroPagina         = $Script:Finestra.FindName('IntroPagina')
$Script:BarraProfili        = $Script:Finestra.FindName('BarraProfili')
$Script:PannelloDescrizione = $Script:Finestra.FindName('PannelloDescrizione')
$Script:BarraAzioni         = $Script:Finestra.FindName('BarraAzioni')
$Script:TestoSelezione      = $Script:Finestra.FindName('TestoSelezione')
$Script:TestoStato          = $Script:Finestra.FindName('TestoStato')
$Script:TitoloVoce          = $Script:Finestra.FindName('TitoloVoce')
$Script:TestoDescrizione    = $Script:Finestra.FindName('TestoDescrizione')
$Script:ChkProva            = $Script:Finestra.FindName('ChkProva')
$Script:BarraAvanzamento    = $Script:Finestra.FindName('BarraAvanzamento')
$Script:TestoAvanzamento    = $Script:Finestra.FindName('TestoAvanzamento')
$Script:RuotaAttesa         = $Script:Finestra.FindName('RuotaAttesa')
$Script:Finestra.FindName('TestoVersione').Text = "Ottimizzazione di Windows · $Script:Versione"
$Script:FontIcone = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')

# Pulsanti dei profili: quello scelto viene evidenziato con il bordo colorato.
$Script:PulsantiProfilo = [ordered]@{
    Massimo    = $Script:Finestra.FindName('BtnMassimo')
    Gaming     = $Script:Finestra.FindName('BtnGaming')
    Grafica    = $Script:Finestra.FindName('BtnGrafica')
    Bilanciato = $Script:Finestra.FindName('BtnBilanciato')
    Batteria   = $Script:Finestra.FindName('BtnBatteria')
    Sicuro     = $Script:Finestra.FindName('BtnSicuro')
}
function Evidenzia-Profilo([string]$Profilo) {
    foreach ($k in @($Script:PulsantiProfilo.Keys)) {
        $b = $Script:PulsantiProfilo[$k]
        if ($k -eq $Profilo) {
            $b.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'Accento')
            $b.BorderThickness = New-Object System.Windows.Thickness(1.5)
        } else {
            $b.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
            $b.ClearValue([System.Windows.Controls.Control]::BorderThicknessProperty)
        }
    }
}

# ---------- Piccoli aiuti per costruire l'interfaccia ----------
function Nuova-Icona([int]$Codice, [double]$Dimensione = 15) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = [string][char]$Codice
    $t.FontFamily = $Script:FontIcone
    $t.FontSize = $Dimensione
    $t.VerticalAlignment = 'Center'
    return $t
}

function Nuovo-Testo([string]$Testo, [string]$Colore = '', [double]$Dimensione = 0, [bool]$Grassetto = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = (Tr $Testo)
    $t.TextWrapping = 'Wrap'
    if ($Colore) { $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Colore) }
    if ($Dimensione -gt 0) { $t.FontSize = $Dimensione }
    if ($Grassetto) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $t
}

function Nuova-Cornice($Contenuto) {
    $c = New-Object System.Windows.Controls.Border
    $c.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $c.BorderThickness = New-Object System.Windows.Thickness(1)
    $c.Padding = New-Object System.Windows.Thickness(1)
    $c.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Bordo')
    $c.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'Superficie')
    $c.Child = $Contenuto
    return $c
}

# Pulsante con (facoltativa) icona a sinistra.
function Nuovo-Pulsante([string]$Testo, [int]$Icona = 0, [string]$Stile = '') {
    $b = New-Object System.Windows.Controls.Button
    if ($Icona -gt 0) {
        $s = New-Object System.Windows.Controls.StackPanel
        $s.Orientation = 'Horizontal'
        $i = Nuova-Icona $Icona 13
        $i.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [void]$s.Children.Add($i)
        [void]$s.Children.Add((Nuovo-Testo $Testo))
        $b.Content = $s
    } else { $b.Content = $Testo }
    if ($Stile) { $b.Style = $Script:Tema[$Stile] }
    return $b
}

# ---------- Navigazione: sezioni con icona nella barra laterale ----------
$Script:Pagine = [ordered]@{}
$Script:PaginaAttuale = ''
$Script:ScansioneFatta = $false

# Gruppi della barra laterale: il titolo ha una freccia e, con un clic, mostra o nasconde le sue sezioni.
$Script:GruppiNav = [ordered]@{}
$Script:GruppoCorrente = ''
$Script:NavChiusi = @()
try { $Script:NavChiusi = @((Leggi-Impostazioni).NavChiusi | Where-Object { $_ }) } catch { }

function Aggiorna-VisibilitaNav {
    foreach ($p in $Script:Pagine.Values) {
        $g = $Script:GruppiNav[[string]$p.Gruppo]
        $aperto = (-not $g) -or $g.Aperto
        $p.Elemento.Visibility = $(if ($aperto -and -not $p.Nascosta) { 'Visible' } else { 'Collapsed' })
    }
}

function Imposta-GruppoNav([string]$Nome, [bool]$Aperto, [bool]$Salva = $true) {
    $g = $Script:GruppiNav[$Nome]
    if (-not $g) { return }
    $g.Aperto = $Aperto
    $g.Freccia.Text = [string][char]$(if ($Aperto) { 0xE70D } else { 0xE76C })
    Aggiorna-VisibilitaNav
    if ($Salva) {
        $chiusi = @($Script:GruppiNav.Keys | Where-Object { -not $Script:GruppiNav[$_].Aperto })
        $Script:NavChiusi = $chiusi
        Salva-Impostazione 'NavChiusi' @($chiusi)
    }
}

function Aggiungi-TitoloNav([string]$Testo) {
    $i = New-Object System.Windows.Controls.ListBoxItem
    $riga = New-Object System.Windows.Controls.DockPanel
    $freccia = Nuova-Icona 0xE70D 10
    $freccia.Width = 18
    [System.Windows.Controls.DockPanel]::SetDock($freccia, [System.Windows.Controls.Dock]::Left)
    $nome = New-Object System.Windows.Controls.TextBlock
    $nome.Text = (Tr $Testo).ToUpper()
    $nome.VerticalAlignment = 'Center'
    [void]$riga.Children.Add($freccia); [void]$riga.Children.Add($nome)
    $i.Content = $riga
    $i.Style = $Script:Tema['TitoloNav']
    $i.Tag = $null
    $i.ToolTip = (Tr 'Clic per mostrare o nascondere le sezioni')
    $i.add_PreviewMouseLeftButtonDown({
        param($s, $e)
        try {
            $nomeGruppo = ([string]$s.Content.Children[1].Text)
            foreach ($k in @($Script:GruppiNav.Keys)) {
                if ((Tr $k).ToUpper() -eq $nomeGruppo) { Imposta-GruppoNav $k (-not $Script:GruppiNav[$k].Aperto); break }
            }
        } catch { }
        $e.Handled = $true
    })
    [void]$Script:Nav.Items.Add($i)
    $Script:GruppiNav[$Testo] = @{ Titolo = $i; Freccia = $freccia; Aperto = $true }
    $Script:GruppoCorrente = $Testo
}

function Aggiungi-Pagina([string]$Chiave, [string]$Titolo, [int]$Icona, $Contenuto, [string]$Intro, [bool]$ConVoci = $true, [bool]$ConProfili = $true) {
    $Titolo = Tr $Titolo; $Intro = Tr $Intro
    if ($Contenuto -is [System.Windows.DependencyObject]) { Traduci-Albero $Contenuto }
    $riga = New-Object System.Windows.Controls.DockPanel
    $ic = Nuova-Icona $Icona 15
    $ic.Width = 28
    $numero = Nuovo-Testo '' 'Arancio' 11 $true
    $badge = New-Object System.Windows.Controls.Border
    $badge.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $badge.Padding = New-Object System.Windows.Thickness(7, 1, 7, 1)
    $badge.VerticalAlignment = 'Center'
    $badge.Visibility = 'Collapsed'
    $badge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'Sfondo')
    $badge.Child = $numero
    $nome = New-Object System.Windows.Controls.TextBlock
    $nome.Text = $Titolo
    $nome.VerticalAlignment = 'Center'
    $nome.TextTrimming = 'CharacterEllipsis'
    [System.Windows.Controls.DockPanel]::SetDock($ic, [System.Windows.Controls.Dock]::Left)
    [System.Windows.Controls.DockPanel]::SetDock($badge, [System.Windows.Controls.Dock]::Right)
    [void]$riga.Children.Add($ic)
    [void]$riga.Children.Add($badge)
    [void]$riga.Children.Add($nome)

    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = $riga
    $item.Tag = $Chiave
    $item.Style = $Script:Tema['VoceNav']
    [void]$Script:Nav.Items.Add($item)
    $Script:Pagine[$Chiave] = @{ Titolo = $Titolo; Icona = $Icona; Contenuto = $Contenuto; Intro = $Intro; ConVoci = $ConVoci; ConProfili = $ConProfili
                                 Badge = $badge; Numero = $numero; Elemento = $item; Gruppo = $Script:GruppoCorrente; Nascosta = $false }
}

function Mostra-Pagina([string]$Chiave) {
    $p = $Script:Pagine[$Chiave]
    if (-not $p) { return }
    $Script:PaginaAttuale = $Chiave
    if ($Script:Sensori) { $Script:Sensori.Richiesta = ($Chiave -eq 'Panoramica') }   # i sensori si leggono solo mentre servono
    if ($Chiave -eq 'Panoramica' -and $Script:CarteLive.Count -gt 0) { try { Aggiorna-Live } catch { } }
    $Script:TitoloPagina.Text = $p.Titolo
    $Script:IconaPagina.Text = [string][char]$p.Icona
    $intro = [string]$p.Intro
    $coll = $Script:Collezioni[$Chiave]
    if ($p.ConVoci -and $Script:ScansioneFatta -and $null -ne $coll -and $coll.Count -eq 0) {
        $intro += $(if ($Chiave -eq 'NVIDIA' -or $Chiave -eq 'NVIDIAAvanz' -or $Chiave -eq 'AMD') { Tr "`nSu questo PC non c'è una scheda video $($Chiave -replace 'Avanz','') con il driver installato: questa sezione non serve." } else { Tr "`nNessuna voce di questa sezione è presente su questo PC." })
    }
    $Script:IntroPagina.Text = $intro
    $Script:IntroPagina.Visibility = $(if ($intro) { 'Visible' } else { 'Collapsed' })
    $Script:IntroPagina.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Chiave -eq 'Avanzate') { 'Rosso' } else { 'Testo2' }))
    if ($Script:Lingua -eq 'en' -and -not $p.Tradotta -and $p.Contenuto -is [System.Windows.DependencyObject]) { Traduci-Albero $p.Contenuto; $p.Tradotta = $true }
    $Script:AreaContenuto.Content = $p.Contenuto
    $Script:BarraProfili.Visibility = $(if ($p.ConVoci -and $p.ConProfili) { 'Visible' } else { 'Collapsed' })
    $Script:PannelloDescrizione.Visibility = $(if ($p.ConVoci) { 'Visible' } else { 'Collapsed' })
    $Script:BarraAzioni.Visibility = $(if ($p.ConVoci) { 'Visible' } else { 'Collapsed' })
}

function Vai-A([string]$Chiave) {
    $p = $Script:Pagine[$Chiave]
    if (-not $p) { return }
    $g = $Script:GruppiNav[[string]$p.Gruppo]
    if ($g -and -not $g.Aperto) { Imposta-GruppoNav ([string]$p.Gruppo) $true }   # il gruppo si riapre da solo
    $Script:Nav.SelectedItem = $p.Elemento
}

# Aggiorna il conteggio "N voci accese" accanto ai pulsanti di applicazione.
function Aggiorna-ConteggioSelezione {
    $n = @($Script:TutteLeRighe | Where-Object { $_.Selezionata }).Count
    $Script:TestoSelezione.Text = Tr $(if ($n -eq 0) { 'Nessuna voce accesa' } elseif ($n -eq 1) { '1 voce accesa' } else { "$n voci accese" })
}

# ---------- Sezione Panoramica ----------
$Script:TesserePanoramica = @{}
$Script:RiepilogoPanoramica = $null

function Leggi-DatiSistema {
    $d = [ordered]@{ Sistema = 'Windows'; SistemaSotto = ''; Cpu = '—'; CpuSotto = ''; Gpu = '—'; GpuSotto = ''; Memoria = '—'; MemoriaSotto = '' }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ver = [string](Leggi-Registro 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion').Valore
        $d.Sistema = ([string]$os.Caption).Replace('Microsoft ', '')
        $d.SistemaSotto = "versione $ver · build $($os.BuildNumber)"
    } catch { }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $d.Cpu = ([string]$cpu.Name).Trim()
        $d.CpuSotto = "$($cpu.NumberOfCores) core · $($cpu.NumberOfLogicalProcessors) thread"
    } catch { }
    try {
        $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [string]$_.Name } | Where-Object { $_ })
        if ($gpu.Count -gt 0) { $d.Gpu = $gpu[$gpu.Count - 1]; if ($gpu.Count -gt 1) { $d.GpuSotto = '+ ' + (($gpu | Select-Object -First ($gpu.Count - 1)) -join ', ') } }
    } catch { }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        $d.Memoria = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB di RAM"
        $d.MemoriaSotto = "disco $($env:SystemDrive) $(Formatta-Dimensione ([int64]$disco.FreeSpace)) liberi · $(if ($bat) { 'portatile' } else { 'PC fisso' })"
    } catch { }
    return $d
}

function Nuova-SchedaInfo([int]$Icona, [string]$Etichetta, [string]$Valore, [string]$Sotto) {
    $Etichetta = Tr $Etichetta; $Valore = Tr $Valore; $Sotto = Tr $Sotto
    $s = New-Object System.Windows.Controls.StackPanel
    $testa = New-Object System.Windows.Controls.StackPanel
    $testa.Orientation = 'Horizontal'
    $ic = Nuova-Icona $Icona 14
    $ic.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Accento')
    $ic.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    [void]$testa.Children.Add($ic)
    [void]$testa.Children.Add((Nuovo-Testo $Etichetta.ToUpper() 'Testo3' 11 $true))
    $v = Nuovo-Testo $Valore '' 14 $true
    $v.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    $v.TextWrapping = 'Wrap'; $v.TextTrimming = 'CharacterEllipsis'; $v.ToolTip = $Valore; $v.MaxHeight = 38   # fino a 2 righe: nomi lunghi di CPU e GPU restano leggibili
    $x = Nuovo-Testo $Sotto 'Testo2' 12
    $x.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    $x.TextWrapping = 'NoWrap'; $x.TextTrimming = 'CharacterEllipsis'; $x.ToolTip = $Sotto
    [void]$s.Children.Add($testa); [void]$s.Children.Add($v); [void]$s.Children.Add($x)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $b.BorderThickness = New-Object System.Windows.Thickness(1)
    $b.Padding = New-Object System.Windows.Thickness(16, 14, 16, 14)
    $b.Margin = New-Object System.Windows.Thickness(0, 0, 10, 10)
    $b.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Bordo')
    $b.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'Superficie')
    $b.Child = $s
    return $b
}

# Gruppo con titolo cliccabile e freccia: mostra o nasconde il contenuto (lo stato si ricorda tra un avvio e l'altro).
$Script:PanoramicaChiusi = @()
try { $Script:PanoramicaChiusi = @((Leggi-Impostazioni).PanoramicaChiusi | Where-Object { $_ }) } catch { }
function Nuovo-GruppoEspandibile([string]$Titolo, $Contenuto, [bool]$Aperto = $true) {
    if ($Script:PanoramicaChiusi -contains $Titolo) { $Aperto = $false }
    $radice = New-Object System.Windows.Controls.StackPanel
    $radice.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $testa = New-Object System.Windows.Controls.Border
    $testa.Background = [System.Windows.Media.Brushes]::Transparent
    $testa.Cursor = [System.Windows.Input.Cursors]::Hand
    $testa.Padding = New-Object System.Windows.Thickness(2, 6, 2, 6)
    $testa.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
    $riga = New-Object System.Windows.Controls.StackPanel
    $riga.Orientation = 'Horizontal'
    $freccia = Nuova-Icona $(if ($Aperto) { 0xE70D } else { 0xE76C }) 11
    $freccia.Width = 20
    $freccia.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Testo3')
    $nome = Nuovo-Testo $Titolo.ToUpper() 'Testo3' 11 $true
    $nome.VerticalAlignment = 'Center'
    [void]$riga.Children.Add($freccia); [void]$riga.Children.Add($nome)
    $testa.Child = $riga
    $testa.ToolTip = 'Clic per mostrare o nascondere'
    $Contenuto.Visibility = $(if ($Aperto) { 'Visible' } else { 'Collapsed' })
    $testa.Tag = @{ Titolo = $Titolo; Contenuto = $Contenuto; Freccia = $freccia }
    $testa.add_MouseLeftButtonUp({
        param($s, $e)
        try {
            $t = $s.Tag
            $apri = ($t.Contenuto.Visibility -ne 'Visible')
            $t.Contenuto.Visibility = $(if ($apri) { 'Visible' } else { 'Collapsed' })
            $t.Freccia.Text = [string][char]$(if ($apri) { 0xE70D } else { 0xE76C })
            $chiusi = @($Script:PanoramicaChiusi | Where-Object { $_ -ne $t.Titolo })
            if (-not $apri) { $chiusi += $t.Titolo }
            $Script:PanoramicaChiusi = $chiusi
            Salva-Impostazione 'PanoramicaChiusi' @($chiusi)
        } catch { }
    })
    [void]$radice.Children.Add($testa); [void]$radice.Children.Add($Contenuto)
    return $radice
}

# ---------- Dati in tempo reale (sola lettura) ----------
# Un thread in background legge i sensori ogni ~2 secondi solo quando la Panoramica è aperta:
#  - carico e frequenza del processore: contatori prestazioni di Windows;
#  - memoria, batteria: WMI;
#  - scheda NVIDIA: nvidia-smi (installato col driver): temperatura, carico, frequenze, consumo, VRAM, ventola;
#  - temperatura del processore: solo se Windows la espone (zone termiche ACPI). Se no, si dice chiaramente.
$Script:Sensori = [hashtable]::Synchronized(@{ Attivo = $true; Richiesta = $false; Dati = @{}; Ora = $null })
$Script:CarteLive = @{}
$Script:CodiceSensori = {
    param($Sync)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $uso = $null; $base = $null; $perf = $null
    try {
        $uso = New-Object Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total')
        $base = New-Object Diagnostics.PerformanceCounter('Processor Information', 'Processor Frequency', '_Total')
        $perf = New-Object Diagnostics.PerformanceCounter('Processor Information', '% Processor Performance', '_Total')
        [void]$uso.NextValue(); [void]$perf.NextValue()
    } catch { $uso = $null }
    $smi = $null
    try { $smi = (Get-Command nvidia-smi.exe -ErrorAction Stop).Source } catch { }
    $zonaOk = $true
    # Disco: contatori del disco fisico (tutti i dischi insieme)
    $dAtt = $null; $dLet = $null; $dScr = $null
    try {
        $dAtt = New-Object Diagnostics.PerformanceCounter('PhysicalDisk', '% Disk Time', '_Total')
        $dLet = New-Object Diagnostics.PerformanceCounter('PhysicalDisk', 'Disk Read Bytes/sec', '_Total')
        $dScr = New-Object Diagnostics.PerformanceCounter('PhysicalDisk', 'Disk Write Bytes/sec', '_Total')
        [void]$dAtt.NextValue(); [void]$dLet.NextValue(); [void]$dScr.NextValue()
    } catch { $dAtt = $null }
    # Rete: contatori della scheda attiva (quella con un gateway); riletta ogni ~20 secondi
    $nRic = $null; $nInv = $null; $nInfo = $null; $nNome = ''; $giro = 0; $wifi = $null
    $lhm = $null; $lhmProvato = $false
    while ($Sync.Attivo) {
        if (-not $Sync.Richiesta) { Start-Sleep -Milliseconds 300; continue }
        # Sensori avanzati (LibreHardwareMonitor + driver PawnIO), solo se l'utente li ha attivati dal programma.
        if ($Sync.Ricarica) { $Sync.Ricarica = $false; $lhmProvato = $false }
        if (-not $lhm -and -not $lhmProvato -and $Sync.DllLhm -and (Test-Path -LiteralPath $Sync.DllLhm)) {
            $lhmProvato = $true
            try {
                Get-ChildItem -LiteralPath (Split-Path -Parent $Sync.DllLhm) -Filter *.dll | ForEach-Object { try { [void][Reflection.Assembly]::LoadFrom($_.FullName) } catch { } }
                $pc = New-Object LibreHardwareMonitor.Hardware.Computer
                $pc.IsCpuEnabled = $true; $pc.IsGpuEnabled = $true; $pc.IsStorageEnabled = $true
                $pc.Open()
                $lhm = $pc
                $Sync.ErroreLhm = ''
            } catch { $lhm = $null; $Sync.ErroreLhm = $_.Exception.Message }
        }
        $d = @{}
        $giro++
        # ---- Dischi ----
        try {
            if ($dAtt) { $d.DiscoUso = [math]::Min(100.0, [double]$dAtt.NextValue()); $d.DiscoLet = [double]$dLet.NextValue(); $d.DiscoScr = [double]$dScr.NextValue() }
            $d.Unita = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { @{ Nome = $_.Name.Substring(0, 2); Libero = [double]$_.AvailableFreeSpace; Totale = [double]$_.TotalSize } })
        } catch { }
        # ---- Rete ----
        try {
            if ($giro % 10 -eq 1 -or -not $nInfo) {
                $att = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
                    $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -notin 'Loopback', 'Tunnel' -and @($_.GetIPProperties().GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' }).Count -gt 0 })
                $nInfo = $att | Select-Object -First 1
                if ($nInfo -and $nInfo.Description -ne $nNome) {
                    $nNome = $nInfo.Description
                    $istanza = ($nNome -replace '\(', '[' -replace '\)', ']' -replace '#', '_' -replace '[\\/]', '_')
                    try {
                        $nRic = New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Received/sec', $istanza)
                        $nInv = New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Sent/sec', $istanza)
                        [void]$nRic.NextValue(); [void]$nInv.NextValue()
                    } catch { $nRic = $null; $nInv = $null }
                }
                if (-not $nInfo) { $nRic = $null; $nInv = $null; $nNome = '' }
                $wifi = $null
                if ($nInfo -and [string]$nInfo.NetworkInterfaceType -eq 'Wireless80211') {
                    try {
                        $righe = @(netsh wlan show interfaces 2>$null)
                        $ss = ($righe | Where-Object { $_ -match '^\s*SSID\s*:' } | Select-Object -First 1)
                        $sg = ($righe | Where-Object { $_ -match '^\s*(Signal|Segnale)\s*:' } | Select-Object -First 1)
                        $wifi = @{ Ssid = $(if ($ss) { ($ss -split ':', 2)[1].Trim() } else { '' }); Segnale = $(if ($sg) { ($sg -split ':', 2)[1].Trim() } else { '' }) }
                    } catch { }
                }
            }
            if ($nInfo) {
                $d.Rete = @{ Nome = [string]$nInfo.Name; Tipo = [string]$nInfo.NetworkInterfaceType; Mbps = [double]$nInfo.Speed / 1e6
                             Giu = $(if ($nRic) { [double]$nRic.NextValue() } else { $null }); Su = $(if ($nInv) { [double]$nInv.NextValue() } else { $null })
                             Wifi = $wifi; Ping = $null }
                $gw = @($nInfo.GetIPProperties().GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' })[0]
                if ($gw) {
                    try { $pg = (New-Object Net.NetworkInformation.Ping).Send($gw.Address, 800); if ($pg.Status -eq 'Success') { $d.Rete.Ping = [double]$pg.RoundtripTime } } catch { }
                }
            } else { $d.Rete = @{ Nome = ''; Tipo = 'Nessuna' } }
        } catch { }
        if ($lhm) {
            try {
                foreach ($hw in @($lhm.Hardware)) {
                    $hw.Update()
                    $tipo = [string]$hw.HardwareType
                    $val = { param($tp, $rx) $s = @($hw.Sensors | Where-Object { [string]$_.SensorType -eq $tp -and $_.Name -match $rx -and $null -ne $_.Value })[0]; if ($s) { [double]$s.Value } else { $null } }
                    if ($tipo -eq 'Cpu') {
                        $t = & $val 'Temperature' '^(CPU Package|Core \(Tctl/Tdie\)|CPU Cores \(Tctl/Tdie\)|Core Max)$'
                        if ($null -eq $t) { $t = & $val 'Temperature' 'Core Average|Tdie|Tctl' }
                        if ($null -ne $t -and $t -gt 0) { $d.CpuTemp = $t }
                        $w = & $val 'Power' '^(CPU Package|Package)$'
                        if ($null -ne $w) { $d.CpuWatt = $w }
                    } elseif ($tipo -eq 'Storage') {
                        $t = & $val 'Temperature' '^Temperature'
                        if ($null -ne $t -and $t -gt 0 -and $t -lt 120) { if ($null -eq $d.DiscoTemp -or $t -gt $d.DiscoTemp) { $d.DiscoTemp = $t } }
                    } elseif ($tipo -eq 'GpuAmd' -or $tipo -eq 'GpuIntel') {
                        $d.GpuAlt = @{ Nome = [string]$hw.Name; Temp = (& $val 'Temperature' '^GPU (Core|Hot Spot)$'); Uso = (& $val 'Load' '^GPU Core$')
                                       MhzGpu = (& $val 'Clock' '^GPU Core$'); Watt = (& $val 'Power' 'GPU|Package') }
                    }
                }
            } catch { }
        }
        try { if ($uso) { $d.CpuUso = [math]::Min(100.0, [double]$uso.NextValue()); $d.CpuMhz = [double]$base.NextValue() * [double]$perf.NextValue() / 100.0 } } catch { }
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $d.RamTot = [double]$os.TotalVisibleMemorySize / 1MB; $d.RamLib = [double]$os.FreePhysicalMemory / 1MB
            $d.Avvio = $os.LastBootUpTime
        } catch { }
        try {
            $bat = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1
            if ($bat) { $d.BatPerc = [double]$bat.EstimatedChargeRemaining; $d.BatRete = (@(2, 3, 6, 7, 8, 9, 11) -contains [int]$bat.BatteryStatus) }
        } catch { }
        if ($smi) {
            try {
                $campi = 'name,temperature.gpu,utilization.gpu,clocks.gr,clocks.mem,power.draw,fan.speed,memory.used,memory.total'
                $riga = @(& $smi "--query-gpu=$campi" '--format=csv,noheader,nounits' 2>$null)[0]
                if ($riga) {
                    $v = @($riga -split ',' | ForEach-Object { $_.Trim() })
                    $num = { param($x) $n = 0.0; if ([double]::TryParse([string]$x, [Globalization.NumberStyles]::Float, $inv, [ref]$n)) { $n } else { $null } }
                    $d.Gpu = @{ Nome = $v[0]; Temp = (& $num $v[1]); Uso = (& $num $v[2]); MhzGpu = (& $num $v[3]); MhzMem = (& $num $v[4])
                                Watt = (& $num $v[5]); Ventola = (& $num $v[6]); VramUsata = (& $num $v[7]); VramTot = (& $num $v[8]) }
                }
            } catch { }
        }
        if ($zonaOk -and $null -eq $d.CpuTemp) {
            try {
                $z = @(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop)
                $t = @($z | ForEach-Object { [double]$_.Temperature - 273.15 } | Where-Object { $_ -gt 5 -and $_ -lt 120 })
                if ($t.Count -gt 0) { $d.CpuTemp = ($t | Measure-Object -Maximum).Maximum } else { $zonaOk = $false }
            } catch { $zonaOk = $false }
        }
        $Sync.Dati = $d
        $Sync.Ora = Get-Date
        Start-Sleep -Milliseconds 1500
    }
}
$Script:RunspaceSensori = $null
function Avvia-Sensori {
    if ($Script:RunspaceSensori) { return }
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($Script:CodiceSensori.ToString()).AddArgument($Script:Sensori)
        [void]$ps.BeginInvoke()
        $Script:RunspaceSensori = $ps
    } catch { Scrivi-Log "Dati in tempo reale non disponibili: $($_.Exception.Message)" 'AVVISO' }
}

# Riquadro che si aggiorna: icona, etichetta, valore grande e riga di dettaglio.
function Nuova-CartaLive([string]$Chiave, [int]$Icona, [string]$Etichetta) {
    $c = Nuova-SchedaInfo $Icona $Etichetta '...' 'Lettura in corso'
    $pila = $c.Child
    $Script:CarteLive[$Chiave] = @{ Carta = $c; Valore = $pila.Children[1]; Sotto = $pila.Children[2] }
    return $c
}

# ---------- Sensori avanzati (facoltativi): temperatura e consumo del processore ----------
# Windows non dà la temperatura del processore: serve un driver di sistema. Regia usa LibreHardwareMonitor
# (libreria libera, licenza MPL 2.0) e il driver PawnIO (firmato). Si attivano solo se premi il pulsante e confermi;
# i file sono controllati con l'impronta SHA-256 e, per PawnIO, anche con la firma digitale.
# PawnIO si toglie da Impostazioni > App; la cartella Dati\Sensori si può cancellare.
$Script:SensoriRelease = @{
    ZipUrl = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'
    ZipSha = '086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001'; ZipByte = 6632626
    PawnUrl = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'
    PawnSha = '1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032'; PawnByte = 3410960
}
function Cartella-Sensori { return (Join-Path $Script:CartellaDati 'Sensori') }
function Libreria-SensoriPresente { return (Test-Path -LiteralPath (Join-Path (Cartella-Sensori) 'LibreHardwareMonitorLib.dll')) }
function PawnIO-Presente { return [bool](Get-Service -Name 'PawnIO' -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath "$env:ProgramFiles\PawnIO") }

function Scarica-Verificato([string]$Url, [string]$File, [string]$Sha, [string]$Descrizione) {
    try { Scarica-File $Url $File $Descrizione }
    catch {
        Scrivi-Log "Download con BITS non riuscito ($($_.Exception.Message)): riprovo in modo diretto." 'AVVISO'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing -ErrorAction Stop
    }
    $h = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    if ($h -ne $Sha) { Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue; throw "L'impronta del file scaricato ($Descrizione) non corrisponde a quella attesa: il file è stato scartato." }
}

function Installa-SensoriAvanzati {
    $r = $Script:SensoriRelease
    $prova = [bool]$Script:ChkProva.IsChecked
    $testo = "Per leggere la temperatura e il consumo del processore serve un driver di sistema.`n`n" +
             "Verranno scaricati da GitHub:`n" +
             "•  LibreHardwareMonitor 0.9.6 (libreria libera, $(Formatta-Dimensione $r.ZipByte)) nella cartella Dati\Sensori;`n" +
             "•  PawnIO 2.2.0 (driver firmato, $(Formatta-Dimensione $r.PawnByte)): è un driver che gira nel sistema e viene installato in C:\Program Files\PawnIO.`n`n" +
             "Prima dell'uso i file vengono controllati con l'impronta SHA-256 e, per PawnIO, con la firma digitale. " +
             "Per togliere tutto: Impostazioni > App > PawnIO > Disinstalla, poi cancella la cartella Dati\Sensori.`n`n" +
             $(if ($prova) { "MODALITÀ PROVA: non verrà scaricato né installato niente.`n`n" } else { '' }) + "Vuoi procedere?"
    if ((Mostra-Messaggio $testo 'Sensori avanzati' 'YesNo' 'Information') -ne 'Yes') { return }
    if ($prova) { Scrivi-Log 'Sensori avanzati: simulati in modalità prova (niente scaricato né installato).' 'PROVA'; Imposta-Stato 'Modalità prova: sensori avanzati non installati.'; return }
    Blocca-Pulsanti $true
    try {
        $cartella = Cartella-Sensori
        New-Item -ItemType Directory -Force -Path $cartella | Out-Null
        if (-not (Libreria-SensoriPresente)) {
            $zip = Join-Path $cartella 'lhm.zip'
            Scrivi-Log "Download LibreHardwareMonitor da $($r.ZipUrl)"
            Scarica-Verificato $r.ZipUrl $zip $r.ZipSha 'LibreHardwareMonitor'
            Expand-Archive -LiteralPath $zip -DestinationPath $cartella -Force
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $cartella -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
            Scrivi-Log "LibreHardwareMonitor pronto in $cartella" 'OK'
        }
        if (-not (PawnIO-Presente)) {
            $exe = Join-Path $cartella 'PawnIO_setup.exe'
            Scrivi-Log "Download PawnIO da $($r.PawnUrl)"
            Scarica-Verificato $r.PawnUrl $exe $r.PawnSha 'PawnIO'
            $firma = Get-AuthenticodeSignature -LiteralPath $exe
            if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'namazso') {
                Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
                throw "La firma digitale di PawnIO non è valida (stato: $($firma.Status)): il file non verrà usato."
            }
            Scrivi-Log "Firma digitale verificata: $($firma.SignerCertificate.Subject)" 'OK'
            Imposta-Stato 'Installo il driver PawnIO...'; Imposta-Avanzamento -1
            $p = Start-Process -FilePath $exe -ArgumentList '-install', '-silent' -Wait -PassThru -WindowStyle Hidden
            Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
            if ($p.ExitCode -ne 0 -or -not (PawnIO-Presente)) { throw "L'installazione di PawnIO non è riuscita (codice $($p.ExitCode))." }
            Scrivi-Log 'PawnIO installato.' 'OK'
        }
        $Script:Sensori.Ricarica = $true
        Imposta-Stato 'Sensori avanzati attivi: tra pochi secondi la Panoramica mostra la temperatura del processore.'
        Scrivi-Log 'Sensori avanzati attivati.' 'OK'
        if ($Script:BtnSensori) { $Script:BtnSensori.Visibility = 'Collapsed' }
    } finally { Blocca-Pulsanti $false }
}

function Crea-PannelloLive {
    $radice = New-Object System.Windows.Controls.StackPanel
    $griglia = New-Object System.Windows.Controls.Primitives.UniformGrid
    $griglia.Columns = 3
    [void]$griglia.Children.Add((Nuova-CartaLive 'Cpu' 0xE950 'Processore'))
    [void]$griglia.Children.Add((Nuova-CartaLive 'Ram' 0xE964 'Memoria'))
    [void]$griglia.Children.Add((Nuova-CartaLive 'Gpu' 0xE7F4 'Scheda video'))
    [void]$griglia.Children.Add((Nuova-CartaLive 'Disco' 0xEDA2 'Dischi'))
    [void]$griglia.Children.Add((Nuova-CartaLive 'Rete' 0xE774 'Rete'))
    [void]$griglia.Children.Add((Nuova-CartaLive 'Energia' 0xE83F 'Alimentazione'))
    [void]$radice.Children.Add($griglia)
    $Script:NotaLive = Nuovo-Testo '' 'Testo3' 11.5
    $Script:NotaLive.Margin = New-Object System.Windows.Thickness(2, 0, 0, 6)
    [void]$radice.Children.Add($Script:NotaLive)
    $Script:BtnSensori = Nuovo-Pulsante 'Attiva la temperatura del processore...' 0xE9CA
    $Script:BtnSensori.HorizontalAlignment = 'Left'
    $Script:BtnSensori.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
    $Script:BtnSensori.Visibility = 'Collapsed'
    $Script:BtnSensori.ToolTip = 'Scarica LibreHardwareMonitor e il driver PawnIO (con la tua conferma) per leggere temperatura e consumo del processore'
    $Script:BtnSensori.add_Click({ try { Installa-SensoriAvanzati } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
    [void]$radice.Children.Add($Script:BtnSensori)
    $Script:Sensori.DllLhm = (Join-Path (Cartella-Sensori) 'LibreHardwareMonitorLib.dll')
    Avvia-Sensori
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(2)
    $t.add_Tick({ try { if ($Script:PaginaAttuale -eq 'Panoramica') { Aggiorna-Live } } catch { } })
    $t.Start()
    $Script:TimerLive = $t
    return $radice
}

function Formatta-Velocita($BytesAlSecondo) {
    if ($null -eq $BytesAlSecondo) { return '—' }
    $b = [double]$BytesAlSecondo
    if ($b -ge 1MB) { return ('{0:N1} MB/s' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB/s' -f ($b / 1KB)) }
    return ('{0:N0} B/s' -f $b)
}

function Aggiorna-Live {
    $d = $Script:Sensori.Dati
    if (-not $d -or $d.Count -eq 0) { return }
    $it = [Globalization.CultureInfo]::GetCultureInfo('it-IT')
    $c = $Script:CarteLive
    # Processore
    if ($null -ne $d.CpuUso) {
        $c.Cpu.Valore.Text = ('{0:N0} %' -f $d.CpuUso)
        $sotto = ('{0:N2} GHz' -f ($d.CpuMhz / 1000))
        if ($null -ne $d.CpuTemp) { $sotto += ('  ·  {0:N0} °C' -f $d.CpuTemp) } else { $sotto += '  ·  temperatura non disponibile' }
        if ($null -ne $d.CpuWatt) { $sotto += ('  ·  {0:N0} W' -f $d.CpuWatt) }
        $c.Cpu.Sotto.Text = $sotto; $c.Cpu.Sotto.ToolTip = $sotto
    } else { $c.Cpu.Valore.Text = '—'; $c.Cpu.Sotto.Text = 'Contatori di Windows non disponibili' }
    # Memoria
    if ($null -ne $d.RamTot) {
        $usata = $d.RamTot - $d.RamLib
        $c.Ram.Valore.Text = ('{0:N0} %' -f (100 * $usata / [math]::Max(0.1, $d.RamTot)))
        $c.Ram.Sotto.Text = ('{0:N1} di {1:N1} GB in uso' -f $usata, $d.RamTot)
    }
    # Scheda video (NVIDIA tramite nvidia-smi)
    $g = $d.Gpu
    if ($g) {
        $v = $(if ($null -ne $g.Temp) { ('{0:N0} °C' -f $g.Temp) } else { '—' })
        if ($null -ne $g.Uso) { $v += ('  ·  {0:N0} %' -f $g.Uso) }
        $c.Gpu.Valore.Text = $v
        $parti = New-Object System.Collections.ArrayList
        if ($null -ne $g.MhzGpu) { [void]$parti.Add(('{0:N0} MHz' -f $g.MhzGpu)) }
        if ($null -ne $g.Watt) { [void]$parti.Add(('{0:N0} W' -f $g.Watt)) }
        if ($null -ne $g.VramUsata -and $null -ne $g.VramTot) { [void]$parti.Add(('VRAM {0:N1}/{1:N1} GB' -f ($g.VramUsata / 1024), ($g.VramTot / 1024))) }
        if ($null -ne $g.Ventola) { [void]$parti.Add(('ventola {0:N0} %' -f $g.Ventola)) }
        $c.Gpu.Sotto.Text = ($parti -join '  ·  '); $c.Gpu.Sotto.ToolTip = $g.Nome + "`n" + ($parti -join "`n")
    } elseif ($d.GpuAlt) {
        $a = $d.GpuAlt
        $v = $(if ($null -ne $a.Temp) { ('{0:N0} °C' -f $a.Temp) } else { '—' })
        if ($null -ne $a.Uso) { $v += ('  ·  {0:N0} %' -f $a.Uso) }
        $c.Gpu.Valore.Text = $v
        $parti = New-Object System.Collections.ArrayList
        if ($null -ne $a.MhzGpu) { [void]$parti.Add(('{0:N0} MHz' -f $a.MhzGpu)) }
        if ($null -ne $a.Watt) { [void]$parti.Add(('{0:N0} W' -f $a.Watt)) }
        $c.Gpu.Sotto.Text = ($parti -join '  ·  '); $c.Gpu.Sotto.ToolTip = $a.Nome
    } else {
        $c.Gpu.Valore.Text = 'n.d.'
        $c.Gpu.Sotto.Text = 'Temperature e frequenze: schede NVIDIA, oppure attiva i sensori avanzati'
    }
    # Dischi
    if ($null -ne $d.DiscoUso) {
        $c.Disco.Valore.Text = ('attività {0:N0} %' -f $d.DiscoUso)
        $parti = New-Object System.Collections.ArrayList
        [void]$parti.Add(('lett. {0} · scr. {1}' -f (Formatta-Velocita $d.DiscoLet), (Formatta-Velocita $d.DiscoScr)))
        if ($null -ne $d.DiscoTemp) { [void]$parti.Add(('{0:N0} °C' -f $d.DiscoTemp)) }
        $c.Disco.Sotto.Text = ($parti -join '  ·  ')
        $liberi = @($d.Unita | ForEach-Object { '{0} {1} liberi su {2}' -f $_.Nome, (Formatta-Dimensione ([int64]$_.Libero)), (Formatta-Dimensione ([int64]$_.Totale)) })
        $c.Disco.Sotto.ToolTip = (@($c.Disco.Sotto.Text) + $liberi) -join "`n"
        $c.Disco.Carta.ToolTip = $c.Disco.Sotto.ToolTip
    } else { $c.Disco.Valore.Text = '—'; $c.Disco.Sotto.Text = 'Contatori del disco non disponibili' }
    # Rete
    $n = $d.Rete
    if ($n -and $n.Nome) {
        $c.Rete.Valore.Text = ('↓ {0}   ↑ {1}' -f (Formatta-Velocita $n.Giu), (Formatta-Velocita $n.Su))
        $parti = New-Object System.Collections.ArrayList
        [void]$parti.Add($(if ($n.Tipo -eq 'Wireless80211') { 'Wi-Fi' + $(if ($n.Wifi -and $n.Wifi.Ssid) { " $($n.Wifi.Ssid)" }) } elseif ($n.Tipo -eq 'Ethernet') { 'cavo' } else { $n.Nome }))
        if ($n.Mbps -gt 0) { [void]$parti.Add(('{0:N0} Mbps' -f $n.Mbps)) }
        if ($n.Wifi -and $n.Wifi.Segnale) { [void]$parti.Add("segnale $($n.Wifi.Segnale)") }
        if ($null -ne $n.Ping) { [void]$parti.Add(('router {0:N0} ms' -f $n.Ping)) }
        $c.Rete.Sotto.Text = ($parti -join '  ·  '); $c.Rete.Sotto.ToolTip = ($parti -join "`n")
    } else { $c.Rete.Valore.Text = 'Nessuna rete'; $c.Rete.Sotto.Text = 'Nessuna connessione attiva con accesso al router' }
    # Alimentazione
    $avvio =$(if ($d.Avvio) { [DateTime]$d.Avvio } else { $null })
    $durata = $(if ($avvio) { (Get-Date) - $avvio } else { $null })
    $acceso = $(if ($durata) { "acceso da {0}h {1:00}m" -f [int][math]::Floor($durata.TotalHours), $durata.Minutes } else { '' })
    if ($null -ne $d.BatPerc) {
        $c.Energia.Valore.Text = ('{0:N0} %' -f $d.BatPerc)
        $c.Energia.Sotto.Text = (@($(if ($d.BatRete) { 'alimentatore collegato' } else { 'a batteria' }), $acceso) | Where-Object { $_ }) -join '  ·  '
    } else {
        $c.Energia.Valore.Text = 'Rete elettrica'
        $c.Energia.Sotto.Text = $acceso
    }
    if ($Script:NotaLive) {
        $manca = ($null -eq $d.CpuTemp)
        $pronti = (Libreria-SensoriPresente) -and (PawnIO-Presente)
        $Script:NotaLive.Text = $(if (-not $manca) { '' }
            elseif ($pronti) { "I sensori avanzati sono installati ma il processore non ha restituito la temperatura$(if ($Script:Sensori.ErroreLhm) { ' (' + $Script:Sensori.ErroreLhm + ')' })." }
            else { "Windows non fornisce la temperatura del processore: serve un driver di sistema dedicato. Regia può installarlo (LibreHardwareMonitor + PawnIO) solo se lo chiedi e confermi. Carico e frequenza sono già reali." })
        $Script:NotaLive.Text = Tr $Script:NotaLive.Text
        $Script:NotaLive.Visibility = $(if ($Script:NotaLive.Text) { 'Visible' } else { 'Collapsed' })
        if ($Script:BtnSensori) { $Script:BtnSensori.Visibility = $(if ($manca -and -not $pronti) { 'Visible' } else { 'Collapsed' }) }
    }
    # Testi delle carte: in inglese si traducono i singoli pezzi (separati da '  ·  ')
    if ($Script:Lingua -eq 'en') {
        foreach ($k in @($c.Keys)) { foreach ($q in @('Valore', 'Sotto')) { $tb = $c[$k].$q; if ($tb -and $tb.Text) { $tb.Text = (($tb.Text -split '  ·  ' | ForEach-Object { Tr $_ }) -join '  ·  ') } } }
    }
}

# ---------- Report sullo stato del PC (dopo ogni scansione) ----------
# Solo lettura. Raccoglie dati in background (Windows Defender, firewall, dischi, batteria, driver, aggiornamenti...)
# e li valuta con soglie semplici: spunta verde = a posto, triangolo arancio = da guardare, croce rossa = problema.
$Script:CodiceReport = {
    $r = @{}
    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $r.Avvio = $os.LastBootUpTime; $r.RamTot = [double]$os.TotalVisibleMemorySize; $r.RamLib = [double]$os.FreePhysicalMemory } catch { }
    try { $mp = Get-MpComputerStatus -ErrorAction Stop; $r.Difender = @{ Attivo = [bool]$mp.RealTimeProtectionEnabled; EtaFirme = [int]$mp.AntivirusSignatureAge } } catch { }
    try { $r.Antivirus = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { [string]$_.displayName }) } catch { }
    try { $r.Firewall = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { @{ Nome = [string]$_.Name; Attivo = ([string]$_.Enabled -eq 'True') } }) } catch { }
    try { $r.Dischi = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { @{ Nome = [string]$_.FriendlyName; Salute = [string]$_.HealthStatus; Stato = [string]$_.OperationalStatus; Tipo = [string]$_.MediaType } }) } catch { }
    try { $r.Usura = @(Get-PhysicalDisk -ErrorAction Stop | Get-StorageReliabilityCounter -ErrorAction Stop | ForEach-Object { @{ Usura = $_.Wear; Temp = $_.Temperature } }) } catch { }
    try {
        $st = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1
        $fc = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1
        if ($st -and $fc -and [double]$st.DesignedCapacity -gt 0) { $r.Batteria = @{ Progetto = [double]$st.DesignedCapacity; Piena = [double]$fc.FullChargedCapacity } }
    } catch { }
    try { $r.Driver = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop | Where-Object { @(22, 24, 45) -notcontains [int]$_.ConfigManagerErrorCode } | ForEach-Object { [string]$_.Name }) } catch { }
    try { $h = Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1; if ($h) { $r.UltimoAgg = [datetime]$h.InstalledOn } } catch { }
    try { $r.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { }
    try { $t = Get-Tpm -ErrorAction Stop; $r.Tpm = @{ Presente = [bool]$t.TpmPresent; Pronto = [bool]$t.TpmReady } } catch { }
    $r
}
$Script:ContenitoreReport = $null
$Script:UltimoPulibile = [int64]0

function Nuova-RigaReport($Contenitore, [string]$Stato, [string]$Titolo, [string]$Dettaglio, [string]$Vai = '') {
    $Titolo = Tr $Titolo; $Dettaglio = Tr $Dettaglio
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 0)
    foreach ($w in @((New-Object System.Windows.GridLength(34)), (New-Object System.Windows.GridLength(1, 'Star')), [System.Windows.GridLength]::Auto)) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $w
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $simbolo = switch ($Stato) { 'ok' { 0xE73E } 'avviso' { 0xE7BA } 'errore' { 0xE711 } default { 0xE946 } }
    $colore = switch ($Stato) { 'ok' { 'Verde' } 'avviso' { 'Arancio' } 'errore' { 'Rosso' } default { 'Testo3' } }
    $ic = Nuova-Icona $simbolo 16
    $ic.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $colore)
    $ic.HorizontalAlignment = 'Center'; $ic.VerticalAlignment = 'Top'; $ic.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($ic, 0)
    $pila = New-Object System.Windows.Controls.StackPanel
    $pila.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    [void]$pila.Children.Add((Nuovo-Testo $Titolo '' 13 $true))
    if ($Dettaglio) { $d = Nuovo-Testo $Dettaglio 'Testo2' 12; $d.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0); [void]$pila.Children.Add($d) }
    [System.Windows.Controls.Grid]::SetColumn($pila, 1)
    [void]$g.Children.Add($ic); [void]$g.Children.Add($pila)
    if ($Vai) {
        $b = Nuovo-Pulsante 'Apri' 0 'Fantasma'
        $b.Tag = $Vai; $b.VerticalAlignment = 'Center'
        $b.add_Click({ try { Vai-A ([string]$this.Tag) } catch { } })
        [System.Windows.Controls.Grid]::SetColumn($b, 2)
        [void]$g.Children.Add($b)
    }
    $bordo = New-Object System.Windows.Controls.Border
    $bordo.Padding = New-Object System.Windows.Thickness(8, 8, 8, 8)
    $bordo.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
    $bordo.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Bordo')
    $bordo.Child = $g
    [void]$Contenitore.Children.Add($bordo)
}

function Costruisci-Report {
    if (-not $Script:ContenitoreReport) { return }
    $dati = @{}
    try { $dati = @(Esegui-InBackground $Script:CodiceReport)[0] } catch { Scrivi-Log "Report: lettura dati incompleta ($($_.Exception.Message))" 'AVVISO' }
    if ($dati -isnot [hashtable]) { $dati = @{} }
    $live = $Script:Sensori.Dati
    $sezioni = [ordered]@{}
    $aggiungi = {
        param($Sezione, $Stato, $Titolo, $Dettaglio, $Vai)
        if (-not $sezioni.Contains($Sezione)) { $sezioni[$Sezione] = New-Object System.Collections.ArrayList }
        [void]$sezioni[$Sezione].Add(@{ Stato = $Stato; Titolo = $Titolo; Dettaglio = $Dettaglio; Vai = $Vai })
    }

    # --- Sistema ---
    $sis = [string]$Script:NomeSistema
    if ($Script:Build -lt 22000) { & $aggiungi 'Sistema' 'avviso' 'Windows 10' 'Il supporto gratuito di Windows 10 è terminato (ottobre 2025): meglio passare a Windows 11 o attivare gli aggiornamenti di sicurezza estesi.' '' }
    else { & $aggiungi 'Sistema' 'ok' "Windows 11 (build $($Script:Build))" 'Versione moderna di Windows.' '' }
    if ($dati.UltimoAgg) {
        $gg = [int]((Get-Date) - $dati.UltimoAgg).TotalDays
        & $aggiungi 'Sistema' $(if ($gg -le 60) { 'ok' } elseif ($gg -le 120) { 'avviso' } else { 'errore' }) 'Aggiornamenti di Windows' "Ultimo aggiornamento installato il $(([datetime]$dati.UltimoAgg).ToString('dd/MM/yyyy')) ($gg giorni fa)." ''
    }
    if (Serve-RiavvioWindows) { & $aggiungi 'Sistema' 'avviso' 'Riavvio in sospeso' 'Windows ha operazioni che si completano solo dopo un riavvio.' '' }
    if ($dati.Avvio) {
        $gu = [int]((Get-Date) - [datetime]$dati.Avvio).TotalDays
        & $aggiungi 'Sistema' $(if ($gu -le 14) { 'ok' } else { 'avviso' }) 'Tempo dall''ultimo avvio' $(if ($gu -le 14) { "Acceso da $gu giorni: va bene." } else { "Acceso da $gu giorni: un riavvio ripulisce la memoria e completa gli aggiornamenti." }) ''
    }
    if ($dati.Driver) {
        $n = @($dati.Driver).Count
        & $aggiungi 'Sistema' 'avviso' "$n dispositivi con problemi di driver" ((@($dati.Driver) | Select-Object -First 3) -join ', ') 'Driver'
    } elseif ($dati.ContainsKey('Driver')) { & $aggiungi 'Sistema' 'ok' 'Driver' 'Nessun dispositivo segnala errori.' '' }

    # --- Prestazioni ---
    if ($dati.RamTot) {
        $perc = 100 * (1 - $dati.RamLib / $dati.RamTot)
        & $aggiungi 'Prestazioni' $(if ($perc -lt 80) { 'ok' } elseif ($perc -lt 92) { 'avviso' } else { 'errore' }) 'Memoria RAM' ("In uso {0:N0} % ({1:N1} di {2:N1} GB)." -f $perc, (($dati.RamTot - $dati.RamLib) / 1MB), ($dati.RamTot / 1MB)) ''
    }
    try {
        $piano = Ottieni-PianoAttivo
        $stP = $(if ($piano.Nome -match 'risparmio|saver') { 'avviso' } else { 'ok' })
        & $aggiungi 'Prestazioni' $stP 'Piano energetico' "Attivo: $($piano.Nome)." 'Prestazioni'
    } catch { }
    if ($live -and $null -ne $live.CpuTemp) {
        & $aggiungi 'Prestazioni' $(if ($live.CpuTemp -lt 85) { 'ok' } elseif ($live.CpuTemp -lt 95) { 'avviso' } else { 'errore' }) 'Temperatura del processore' ('{0:N0} °C in questo momento.' -f $live.CpuTemp) ''
    }
    if ($live -and $live.Gpu -and $null -ne $live.Gpu.Temp) {
        & $aggiungi 'Prestazioni' $(if ($live.Gpu.Temp -lt 82) { 'ok' } elseif ($live.Gpu.Temp -lt 90) { 'avviso' } else { 'errore' }) 'Temperatura della scheda video' ('{0:N0} °C in questo momento.' -f $live.Gpu.Temp) ''
    }
    if ($live -and $live.Rete) {
        if ($live.Rete.Nome) { & $aggiungi 'Prestazioni' 'ok' 'Rete' ("Connessa ($(switch ($live.Rete.Tipo) { 'Wireless80211' { 'Wi-Fi' } 'Ethernet' { 'cavo' } default { $live.Rete.Tipo } })$(if ($null -ne $live.Rete.Ping) { ', router ' + [int]$live.Rete.Ping + ' ms' })).") '' }
        else { & $aggiungi 'Prestazioni' 'avviso' 'Rete' 'Nessuna connessione attiva con accesso al router.' '' }
    }

    # --- Efficienza ---
    $avv = $Script:Collezioni['Avvio']
    if ($avv) {
        $n = @($avv | Where-Object { $_.Esito -eq 'Da modificare' }).Count
        & $aggiungi 'Efficienza' $(if ($n -le 3) { 'ok' } elseif ($n -le 8) { 'avviso' } else { 'errore' }) 'Programmi all''avvio' $(if ($n -eq 0) { 'Nessun programma superfluo all''avvio.' } else { $(if ($n -eq 1) { "1 programma non essenziale parte con Windows." } else { "$n programmi non essenziali partono con Windows." }) }) $(if ($n -gt 0) { 'Avvio' } else { '' })
    }
    $totDaFare = 0
    foreach ($cat in @('Debloat app', 'Servizi', 'Privacy', 'Prestazioni', 'Latenza', 'Grafica', 'Esplora file')) {
        $cl = $Script:Collezioni[$cat]; if ($cl) { $totDaFare += @($cl | Where-Object { $_.Esito -eq 'Da modificare' }).Count }
    }
    & $aggiungi 'Efficienza' $(if ($totDaFare -le 3) { 'ok' } elseif ($totDaFare -le 15) { 'avviso' } else { 'errore' }) 'Ottimizzazioni disponibili' $(if ($totDaFare -eq 0) { 'Le impostazioni di Windows sono già a posto.' } else { "$totDaFare impostazioni di Windows si possono migliorare (privacy, servizi, prestazioni...)." }) ''
    $mb = $Script:UltimoPulibile / 1MB
    & $aggiungi 'Efficienza' $(if ($mb -lt 500) { 'ok' } elseif ($mb -lt 5000) { 'avviso' } else { 'errore' }) 'File temporanei e cache' $(if ($mb -lt 50) { 'Poco da pulire.' } else { "Circa $(Formatta-Dimensione $Script:UltimoPulibile) si possono recuperare con la pulizia." }) $(if ($mb -ge 500) { 'Pulizia' } else { '' })

    # --- Archiviazione e hardware ---
    try {
        $sd = New-Object IO.DriveInfo($env:SystemDrive)
        $lib = 100.0 * $sd.AvailableFreeSpace / $sd.TotalSize
        & $aggiungi 'Dischi e hardware' $(if ($lib -ge 20) { 'ok' } elseif ($lib -ge 10) { 'avviso' } else { 'errore' }) "Spazio su $($env:SystemDrive)" ("{0} liberi su {1} ({2:N0} %)." -f (Formatta-Dimensione $sd.AvailableFreeSpace), (Formatta-Dimensione $sd.TotalSize), $lib) $(if ($lib -lt 20) { 'Pulizia' } else { '' })
    } catch { }
    if ($dati.Dischi) {
        $male = @($dati.Dischi | Where-Object { $_.Salute -ne 'Healthy' -or $_.Stato -ne 'OK' })
        if ($male.Count -eq 0) { & $aggiungi 'Dischi e hardware' 'ok' 'Salute dei dischi' "$(@($dati.Dischi).Count) dischi, tutti in buono stato secondo Windows." '' }
        else { & $aggiungi 'Dischi e hardware' 'errore' 'Salute dei dischi' (($male | ForEach-Object { "$($_.Nome): $($_.Salute)" }) -join '; ') '' }
    }
    $us = @($dati.Usura | Where-Object { $null -ne $_.Usura } | ForEach-Object { [int]$_.Usura })
    if ($us.Count -gt 0) {
        $mx = ($us | Measure-Object -Maximum).Maximum
        & $aggiungi 'Dischi e hardware' $(if ($mx -lt 60) { 'ok' } elseif ($mx -lt 85) { 'avviso' } else { 'errore' }) 'Usura degli SSD' "Usura massima dichiarata: $mx %."  ''
    }
    if ($live -and $null -ne $live.DiscoTemp) {
        & $aggiungi 'Dischi e hardware' $(if ($live.DiscoTemp -lt 65) { 'ok' } elseif ($live.DiscoTemp -lt 75) { 'avviso' } else { 'errore' }) 'Temperatura dei dischi' ('{0:N0} °C.' -f $live.DiscoTemp) ''
    }
    if ($dati.Batteria) {
        $res = 100.0 * $dati.Batteria.Piena / $dati.Batteria.Progetto
        & $aggiungi 'Dischi e hardware' $(if ($res -ge 80) { 'ok' } elseif ($res -ge 60) { 'avviso' } else { 'errore' }) 'Batteria' ("Capacità residua {0:N0} % di quella originale." -f $res) ''
    }

    # --- Sicurezza ---
    $altri = @($dati.Antivirus | Where-Object { $_ -and $_ -notmatch 'Defender' })
    if ($dati.Difender -and $dati.Difender.Attivo) {
        & $aggiungi 'Sicurezza' 'ok' 'Protezione antivirus' 'Microsoft Defender è attivo in tempo reale.' ''
        $et = $dati.Difender.EtaFirme
        & $aggiungi 'Sicurezza' $(if ($et -le 3) { 'ok' } elseif ($et -le 7) { 'avviso' } else { 'errore' }) 'Definizioni antivirus' "Aggiornate $(if ($et -eq 0) { 'oggi' } else { "$et giorni fa" })." ''
    } elseif ($altri.Count -gt 0) { & $aggiungi 'Sicurezza' 'ok' 'Protezione antivirus' "Protezione fornita da: $($altri -join ', ')." '' }
    elseif ($dati.ContainsKey('Difender') -or $dati.ContainsKey('Antivirus')) { & $aggiungi 'Sicurezza' 'errore' 'Protezione antivirus' 'Nessuna protezione antivirus attiva rilevata.' '' }
    if ($dati.Firewall) {
        $spenti = @($dati.Firewall | Where-Object { -not $_.Attivo })
        if ($spenti.Count -eq 0) { & $aggiungi 'Sicurezza' 'ok' 'Firewall' 'Attivo su tutte le reti.' '' }
        else { & $aggiungi 'Sicurezza' 'avviso' 'Firewall' "Spento su: $((($spenti | ForEach-Object { $_.Nome }) -join ', '))." '' }
    }
    if ($dati.ContainsKey('SecureBoot')) { & $aggiungi 'Sicurezza' $(if ($dati.SecureBoot) { 'ok' } else { 'avviso' }) 'Avvio protetto (Secure Boot)' $(if ($dati.SecureBoot) { 'Attivo.' } else { 'Disattivato nel BIOS: Windows 11 e alcuni giochi lo richiedono.' }) '' }
    if ($dati.Tpm) { & $aggiungi 'Sicurezza' $(if ($dati.Tpm.Presente -and $dati.Tpm.Pronto) { 'ok' } else { 'avviso' }) 'Modulo TPM' $(if ($dati.Tpm.Presente -and $dati.Tpm.Pronto) { 'Presente e pronto.' } else { 'Assente o non pronto.' }) '' }

    # --- Disegno ---
    $c = $Script:ContenitoreReport
    $c.Children.Clear()
    $ok = 0; $av = 0; $er = 0
    foreach ($lista in $sezioni.Values) { foreach ($x in $lista) { switch ($x.Stato) { 'ok' { $ok++ } 'avviso' { $av++ } 'errore' { $er++ } } } }
    $punti = [math]::Max(0, [math]::Min(100, 100 - 5 * $av - 15 * $er))
    $verdetto = $(if ($er -eq 0 -and $punti -ge 85) { @('ok', 'Il PC è in ottima forma', 'Nessun problema importante: restano solo piccoli miglioramenti.') }
                  elseif ($punti -ge 65) { @('avviso', 'Il PC va bene, ma c''è qualcosa da sistemare', 'Guarda le voci con il triangolo arancio.') }
                  else { @('errore', 'Il PC ha bisogno di attenzione', 'Ci sono problemi da risolvere: guarda le voci con la croce rossa.') })
    $testa = New-Object System.Windows.Controls.DockPanel
    $testa.Margin = New-Object System.Windows.Thickness(2, 2, 0, 10)
    $simb = switch ($verdetto[0]) { 'ok' { 0xE73E } 'avviso' { 0xE7BA } default { 0xE711 } }
    $col = switch ($verdetto[0]) { 'ok' { 'Verde' } 'avviso' { 'Arancio' } default { 'Rosso' } }
    $big = Nuova-Icona $simb 34
    $big.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $col)
    $big.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
    [System.Windows.Controls.DockPanel]::SetDock($big, [System.Windows.Controls.Dock]::Left)
    $pt = Nuovo-Testo "$punti/100" $col 26 $true
    $pt.VerticalAlignment = 'Center'; $pt.Margin = New-Object System.Windows.Thickness(10, 0, 8, 0)
    [System.Windows.Controls.DockPanel]::SetDock($pt, [System.Windows.Controls.Dock]::Right)
    $tt = New-Object System.Windows.Controls.StackPanel
    [void]$tt.Children.Add((Nuovo-Testo $verdetto[1] '' 17 $true))
    [void]$tt.Children.Add((Nuovo-Testo "$($verdetto[2])   $ok a posto · $av da guardare · $er problemi   (controllo del $((Get-Date).ToString('dd/MM/yyyy HH:mm')))" 'Testo2' 12))
    [void]$testa.Children.Add($big); [void]$testa.Children.Add($pt); [void]$testa.Children.Add($tt)
    [void]$c.Children.Add($testa)

    # Due colonne indipendenti: le sezioni si alternano e ognuna ha l'altezza che le serve.
    $griglia = New-Object System.Windows.Controls.Grid
    foreach ($cdw in @((New-Object System.Windows.GridLength(1, 'Star')), (New-Object System.Windows.GridLength(1, 'Star')))) { $cdd = New-Object System.Windows.Controls.ColumnDefinition; $cdd.Width = $cdw; [void]$griglia.ColumnDefinitions.Add($cdd) }
    $colonne = @((New-Object System.Windows.Controls.StackPanel), (New-Object System.Windows.Controls.StackPanel))
    [System.Windows.Controls.Grid]::SetColumn($colonne[1], 1)
    [void]$griglia.Children.Add($colonne[0]); [void]$griglia.Children.Add($colonne[1])
    $ci = 0
    foreach ($nome in $sezioni.Keys) {
        $pila = New-Object System.Windows.Controls.StackPanel
        $pila.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
        $nAv = @($sezioni[$nome] | Where-Object { $_.Stato -ne 'ok' -and $_.Stato -ne 'info' }).Count
        $tit = Nuovo-Testo ($nome.ToUpper() + $(if ($nAv -gt 0) { "   ·   $nAv da guardare" } else { '   ·   tutto a posto' })) $(if ($nAv -gt 0) { 'Arancio' } else { 'Verde' }) 11 $true
        $tit.Margin = New-Object System.Windows.Thickness(8, 8, 0, 4)
        [void]$pila.Children.Add($tit)
        foreach ($x in $sezioni[$nome]) { Nuova-RigaReport $pila $x.Stato $x.Titolo $x.Dettaglio $x.Vai }
        $cornice = Nuova-Cornice $pila
        $cornice.Margin = New-Object System.Windows.Thickness(0, 0, 10, 10)
        [void]$colonne[$ci % 2].Children.Add($cornice); $ci++
    }
    [void]$c.Children.Add($griglia)
    Scrivi-Log "Report dello stato del PC: $punti/100 ($ok a posto, $av da guardare, $er problemi)." 'OK'
    $Script:UltimoReport = @{ Punti = $punti; Ok = $ok; Avvisi = $av; Problemi = $er; Voci = @($sezioni.GetEnumerator() | ForEach-Object { $s = $_.Key; $_.Value | ForEach-Object { "$s | $($_.Stato) | $($_.Titolo) | $($_.Dettaglio)" } }) }
}

function Crea-Panoramica {
    $radice = New-Object System.Windows.Controls.StackPanel
    $d = Leggi-DatiSistema
    $info = New-Object System.Windows.Controls.Primitives.UniformGrid
    $info.Columns = 4
    [void]$info.Children.Add((Nuova-SchedaInfo 0xE7F8 'Sistema' $d.Sistema $d.SistemaSotto))
    [void]$info.Children.Add((Nuova-SchedaInfo 0xE950 'Processore' $d.Cpu $d.CpuSotto))
    [void]$info.Children.Add((Nuova-SchedaInfo 0xE7F4 'Scheda video' $d.Gpu $d.GpuSotto))
    [void]$info.Children.Add((Nuova-SchedaInfo 0xEDA2 'Memoria e disco' $d.Memoria $d.MemoriaSotto))
    [void]$radice.Children.Add($info)

    $Script:RiepilogoPanoramica = Nuovo-Testo 'Scansione in corso...' '' 15 $true
    $Script:RiepilogoPanoramica.Margin = New-Object System.Windows.Thickness(2, 12, 0, 4)
    [void]$radice.Children.Add($Script:RiepilogoPanoramica)
    $guida = Nuovo-Testo "Come si usa:  1) scegli una sezione qui sotto o un profilo   2) accendi le voci che vuoi   3) premi 'Anteprima e applica'.  Con la Modalità prova accesa non viene modificato niente; ogni modifica vera è preceduta da punto di ripristino e backup, e si annulla con 'Annulla tutto'." 'Testo2'
    $guida.Margin = New-Object System.Windows.Thickness(2, 0, 0, 14)
    $guida.LineHeight = 19
    [void]$radice.Children.Add($guida)

    # Dati in tempo reale (temperature, frequenze, carico): si aggiornano da soli mentre questa pagina è aperta.
    [void]$radice.Children.Add((Nuovo-GruppoEspandibile 'Stato in tempo reale' (Crea-PannelloLive) $true))

    # Report riassuntivo dello stato del PC: si compila dopo ogni scansione.
    $Script:ContenitoreReport = New-Object System.Windows.Controls.StackPanel
    [void]$Script:ContenitoreReport.Children.Add((Nuovo-Testo 'Il report compare quando finisce la scansione.' 'Testo2'))
    [void]$radice.Children.Add((Nuovo-GruppoEspandibile 'Report dello stato del PC' $Script:ContenitoreReport $true))

    foreach ($nomeGruppo in @($Script:GruppiNav.Keys)) {
    if ($nomeGruppo -eq 'Generale') { continue }
    $tessere = New-Object System.Windows.Controls.Primitives.UniformGrid
    $tessere.Columns = 3
    foreach ($k in @($Script:Pagine.Keys | Where-Object { $Script:Pagine[$_].Gruppo -eq $nomeGruppo })) {
        $p = $Script:Pagine[$k]
        if ($k -eq 'Panoramica' -or $k -eq 'Log') { continue }
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $Script:Tema['Scheda']
        $b.Tag = $k
        $riga = New-Object System.Windows.Controls.DockPanel
        $ic = Nuova-Icona $p.Icona 18
        $ic.Width = 36
        $ic.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Accento')
        [System.Windows.Controls.DockPanel]::SetDock($ic, [System.Windows.Controls.Dock]::Left)
        $freccia = Nuova-Icona 0xE76C 11
        $freccia.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Testo3')
        [System.Windows.Controls.DockPanel]::SetDock($freccia, [System.Windows.Controls.Dock]::Right)
        $testi = New-Object System.Windows.Controls.StackPanel
        [void]$testi.Children.Add((Nuovo-Testo $p.Titolo '' 13.5 $true))
        $stato = Nuovo-Testo '—' 'Testo2' 12
        $stato.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        [void]$testi.Children.Add($stato)
        [void]$riga.Children.Add($ic); [void]$riga.Children.Add($freccia); [void]$riga.Children.Add($testi)
        $b.Content = $riga
        $b.add_Click({ try { Vai-A ([string]$this.Tag) } catch { } })
        [void]$tessere.Children.Add($b)
        $Script:TesserePanoramica[$k] = $stato
        $Script:Pannelli[$k] = $b
    }
    if ($tessere.Children.Count -gt 0) { [void]$radice.Children.Add((Nuovo-GruppoEspandibile $nomeGruppo $tessere $true)) }
    }

    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sv.HorizontalScrollBarVisibility = 'Disabled'
    $sv.Focusable = $false
    $sv.Content = $radice
    return $sv
}

# ---------- Creazione delle sezioni ----------
$Script:IconeCategorie = @{ 'Debloat app' = 0xE71D; 'Avvio' = 0xE7E8; 'Servizi' = 0xE713; 'Privacy' = 0xE72E; 'Prestazioni' = 0xE945; 'Grafica' = 0xE790
                            'Esplora file' = 0xE8B7; 'NVIDIA' = 0xE950; 'NVIDIAAvanz' = 0xE713; 'AMD' = 0xE9D9; 'Latenza' = 0xE916; 'Pulizia' = 0xE74D; 'Registro' = 0xE8F1; 'Manutenzione' = 0xE90F; 'Avanzate' = 0xE7BA }
$Script:TitoliCategorie = @{ 'Debloat app' = 'App preinstallate'; 'Avvio' = 'Programmi all''avvio'; 'Servizi' = 'Servizi e attività'; 'Privacy' = 'Privacy e pubblicità'
                             'Prestazioni' = 'Prestazioni ed energia'; 'Grafica' = 'Grafica ed effetti'; 'Esplora file' = 'Esplora file'; 'NVIDIA' = 'Impostazioni NVIDIA'; 'NVIDIAAvanz' = 'NVIDIA - opzioni avanzate'
                             'AMD' = 'Impostazioni AMD'; 'Latenza' = 'Latenza e reattività'; 'Pulizia' = 'Pulizia disco'; 'Registro' = 'Pulizia registro'; 'Manutenzione' = 'Manutenzione'; 'Avanzate' = 'Avanzate' }

# Tasti rapidi della pulizia: 'Sicura' = voci a rischio basso; 'Accurata' = anche rischio medio. Poi anteprima e conferma.
function Pulizia-Rapida([string]$Livello) {
    $n = 0
    foreach ($r in @($Script:Collezioni['Pulizia'])) {
        $v = $Script:Voci[$r.Id]
        if (-not $v) { continue }
        $ok = ($v.Rischio -eq 'basso') -or ($Livello -eq 'Accurata' -and $v.Rischio -eq 'medio')
        $r.Selezionata = [bool]($ok -and -not $v.Avanzata -and -not $v.Manuale)
        if ($r.Selezionata) { $n++ }
    }
    Aggiorna-ConteggioSelezione
    Scrivi-Log "Pulizia $($Livello.ToLower()): $n voci spuntate."
    $Script:SoloCategoria = 'Pulizia'
    try { Applica-Modifiche 'Consigliato' } finally { $Script:SoloCategoria = '' }
}

# Contenuto di una sezione con voci: tabella (per NVIDIA: barra dei preset + tabella con i menu a tendina).
function Crea-ContenutoCategoria([string]$Cat) {
    $coll = New-Object 'System.Collections.ObjectModel.ObservableCollection[OttWin.RigaVoce]'
    $Script:Collezioni[$Cat] = $coll
    $gpu = ($Cat -eq 'NVIDIA' -or $Cat -eq 'AMD' -or $Cat -eq 'NVIDIAAvanz')
    if ($gpu) { $griglia = [Windows.Markup.XamlReader]::Parse($Script:XamlGrigliaNvidia) }
    else {
        $colonna = $(if ($Cat -eq 'Avanzate') { $Script:XamlColonnaCategoria } else { '' })
        $griglia = [Windows.Markup.XamlReader]::Parse($Script:XamlGriglia.Replace('<!--COLONNA_CATEGORIA-->', $colonna))
        $griglia.EnableRowVirtualization = $false
    }
    $griglia.ItemsSource = $coll
    $griglia.add_SelectionChanged({ param($s, $e) try { if ($s.SelectedItem) { Mostra-Descrizione $s.SelectedItem } } catch { } })
    $cornice = Nuova-Cornice $griglia
    if ($Cat -eq 'Latenza') {
        # Barra con la misura del ping (solo lettura): serve a vedere l'effetto delle modifiche.
        $barra = New-Object System.Windows.Controls.DockPanel
        $barra.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
        $b = Nuovo-Pulsante 'Misura la latenza' 0xE916
        $b.ToolTip = 'Invia 20 ping al router e al server DNS e mostra tempo medio, minimo, massimo, variazione (jitter) e pacchetti persi. Non modifica niente.'
        [System.Windows.Controls.DockPanel]::SetDock($b, [System.Windows.Controls.Dock]::Left)
        $Script:TestoMisura = Nuovo-Testo 'Misura prima e dopo le modifiche per vedere la differenza (meglio con il cavo e senza download in corso).' 'Testo2' 12
        $Script:TestoMisura.VerticalAlignment = 'Center'
        $Script:TestoMisura.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
        $b.add_Click({ try { Misura-Latenza } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
        [void]$barra.Children.Add($b); [void]$barra.Children.Add($Script:TestoMisura)
        $pannelloL = New-Object System.Windows.Controls.DockPanel
        [System.Windows.Controls.DockPanel]::SetDock($barra, [System.Windows.Controls.Dock]::Top)
        [void]$pannelloL.Children.Add($barra); [void]$pannelloL.Children.Add($cornice)
        return $pannelloL
    }
    if ($Cat -eq 'Pulizia') {
        # Tasti rapidi: spuntano le voci giuste e aprono subito l'anteprima (si conferma sempre prima di cancellare).
        $barra = New-Object System.Windows.Controls.WrapPanel
        $barra.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
        $et = Nuovo-Testo 'PULIZIA RAPIDA' 'Testo3' 11 $true
        $et.VerticalAlignment = 'Center'
        $et.Margin = New-Object System.Windows.Thickness(2, 0, 10, 0)
        [void]$barra.Children.Add($et)
        $bs = Nuovo-Pulsante 'Pulizia sicura' 0xE72E
        $bs.Tag = 'Sicura'
        $bs.ToolTip = 'Spunta solo le voci a rischio basso (temporanei, cache, vecchi registri) e mostra l''anteprima. Non tocca Cestino e Windows Update.'
        $ba = Nuovo-Pulsante 'Pulizia accurata' 0xE74D 'Primario'
        $ba.Tag = 'Accurata'
        $ba.ToolTip = 'Spunta anche le voci a rischio medio (download di Windows Update già usati, Cestino) e mostra l''anteprima. La pulizia dei componenti di Windows (DISM) resta in Avanzate.'
        foreach ($x in @($bs, $ba)) {
            $x.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
            $x.add_Click({ try { Pulizia-Rapida ([string]$this.Tag) } catch { $Script:SoloCategoria = ''; Blocca-Pulsanti $false; Mostra-Errore $_ } })
            [void]$barra.Children.Add($x)
        }
        $pannelloP = New-Object System.Windows.Controls.DockPanel
        [System.Windows.Controls.DockPanel]::SetDock($barra, [System.Windows.Controls.Dock]::Top)
        [void]$pannelloP.Children.Add($barra); [void]$pannelloP.Children.Add($cornice)
        return $pannelloP
    }
    if (-not $gpu) { return $cornice }

    $barra = New-Object System.Windows.Controls.WrapPanel
    $barra.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
    $et = Nuovo-Testo 'PRESET' 'Testo3' 11 $true
    $et.VerticalAlignment = 'Center'
    $et.Margin = New-Object System.Windows.Thickness(2, 0, 10, 0)
    [void]$barra.Children.Add($et)
    # Preset solo per la scheda video: cambiano le scelte di questa sezione e nient'altro (i profili non le toccano).
    $definizioni = @( @('Gaming', 0xE7FC, 'Prestazioni (più FPS)', 'Solo impostazioni della scheda video: massimi FPS e minima latenza, a scapito della qualità dell''immagine'),
                      @('Produttivita', 0xE821, 'Bilanciato', 'Solo impostazioni della scheda video: valori equilibrati tra FPS, qualità, consumi e calore'),
                      @('Grafica', 0xE790, 'Qualità', 'Solo impostazioni della scheda video: migliore qualità dell''immagine (filtri e anti-aliasing al massimo), con meno FPS') )
    if ($Cat -eq 'NVIDIAAvanz') { $definizioni = @() }   # le opzioni avanzate non hanno preset
    $definizioni += @( @('Predefinito', 0xE777, 'Predefinite del driver', 'Riporta ogni impostazione al valore di serie del driver'),
                       @('Attuale', 0xE7A7, 'Annulla scelte', 'I menu tornano a mostrare i valori attuali: niente da applicare') )
    foreach ($def in $definizioni) {
        $b = Nuovo-Pulsante $def[2] $def[1] $(if ($def[0] -eq 'Attuale') { 'Fantasma' } else { '' })
        $b.Tag = "$Cat|$($def[0])"
        $b.ToolTip = $def[3]
        $b.add_Click({ try { $p = ([string]$this.Tag).Split('|'); [void](Applica-PresetNvidia $p[1] -Solo $(if ($p[0] -eq 'NVIDIAAvanz') { 'NVIDIA' } else { $p[0] }) -Categoria $p[0]); Aggiorna-Intestazioni } catch { Mostra-Errore $_ } })
        [void]$barra.Children.Add($b)
    }
    $pannello = New-Object System.Windows.Controls.DockPanel
    [System.Windows.Controls.DockPanel]::SetDock($barra, [System.Windows.Controls.Dock]::Top)
    [void]$pannello.Children.Add($barra)
    [void]$pannello.Children.Add($cornice)
    return $pannello
}

# Ping verso il router (gateway) e verso il primo server DNS configurato: solo lettura, nessun server esterno scelto da noi.
$Script:TestoMisura = $null
$Script:CodiceMisura = {
    param($Destinazioni)
    foreach ($d in $Destinazioni) {
        $tempi = New-Object System.Collections.ArrayList; $persi = 0
        $ping = New-Object System.Net.NetworkInformation.Ping
        for ($i = 0; $i -lt 20; $i++) {
            try { $r = $ping.Send($d.Indirizzo, 1000); if ($r.Status -eq 'Success') { [void]$tempi.Add([double]$r.RoundtripTime) } else { $persi++ } } catch { $persi++ }
            Start-Sleep -Milliseconds 100
        }
        $jit = 0
        if ($tempi.Count -gt 1) { $diff = for ($j = 1; $j -lt $tempi.Count; $j++) { [math]::Abs($tempi[$j] - $tempi[$j - 1]) }; $jit = ($diff | Measure-Object -Average).Average }
        $m = $tempi | Measure-Object -Average -Minimum -Maximum
        [pscustomobject]@{ Nome = $d.Nome; Indirizzo = $d.Indirizzo; Media = [math]::Round([double]$m.Average, 1); Min = $m.Minimum; Max = $m.Maximum; Jitter = [math]::Round([double]$jit, 1); Persi = $persi; Tot = 20 }
    }
}

function Misura-Latenza {
    $dest = New-Object System.Collections.ArrayList
    $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if ($gw -and $gw.NextHop -and $gw.NextHop -ne '0.0.0.0') { [void]$dest.Add(@{ Nome = 'Router'; Indirizzo = [string]$gw.NextHop }) }
    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | Select-Object -First 1
    if ($dns) { $ip = @($dns.ServerAddresses)[0]; if ($ip -and -not ($dest | Where-Object { $_.Indirizzo -eq $ip })) { [void]$dest.Add(@{ Nome = 'DNS'; Indirizzo = [string]$ip }) } }
    if ($dest.Count -eq 0) { [void](Mostra-Messaggio 'Nessuna connessione di rete attiva: non c''è niente da misurare.' 'Misura la latenza'); return }
    Blocca-Pulsanti $true
    try {
        Imposta-Stato "Misuro la latenza verso $(($dest | ForEach-Object { $_.Nome }) -join ' e ') (20 ping ciascuno)..."
        $ris = @(Esegui-InBackground $Script:CodiceMisura @(, @($dest)))
        $righe = foreach ($r in $ris) {
            if ($r.Persi -ge $r.Tot) { "$($r.Nome) ($($r.Indirizzo)): non risponde" }
            else { "$($r.Nome) ($($r.Indirizzo)): media $($r.Media) ms  ·  min $($r.Min)  ·  max $($r.Max)  ·  jitter $($r.Jitter) ms  ·  persi $($r.Persi)/$($r.Tot)" }
        }
        $testo = $righe -join "`n"
        if ($Script:TestoMisura) { $Script:TestoMisura.Text = "Misura delle $('{0:HH:mm}' -f (Get-Date)):`n$testo" }
        Scrivi-Log "Misura della latenza: $($righe -join ' | ')" 'OK'
        Imposta-Stato 'Misura della latenza completata.'
    } finally { Blocca-Pulsanti $false }
}

function Aggiungi-Categoria([string]$Cat) {
    $conProfili = ($Cat -ne 'NVIDIA' -and $Cat -ne 'NVIDIAAvanz' -and $Cat -ne 'AMD' -and $Cat -ne 'Registro' -and $Cat -ne 'Manutenzione' -and $Cat -ne 'Avanzate')
    Aggiungi-Pagina $Cat $Script:TitoliCategorie[$Cat] $Script:IconeCategorie[$Cat] (Crea-ContenutoCategoria $Cat) $Script:TestiIntro[$Cat] $true $conProfili
}

# Sezione "Driver video"
$pannelloVideo = [Windows.Markup.XamlReader]::Parse($Script:XamlVideo)
$Script:PannelloGpu          = $pannelloVideo.FindName('PannelloGpu')
$Script:ElencoGpu            = $pannelloVideo.FindName('ElencoGpu')
$Script:CmbTipoNvidia        = $null
$Script:CmbVersioniNvidia    = $null
$pannelloVideo.FindName('BtnControllaVideo').add_Click({ try { Controlla-AggiornamentiVideo } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })

# Sezione "Altri driver"
$pannelloDriver = [Windows.Markup.XamlReader]::Parse($Script:XamlDriver)
$Script:PannelloDriver       = $pannelloDriver
$Script:GrigliaDispositivi   = $pannelloDriver.FindName('GrigliaDispositivi')
$Script:GrigliaAggiornamenti = $pannelloDriver.FindName('GrigliaAggiornamenti')
$Script:BtnControllaDriver   = $pannelloDriver.FindName('BtnControllaDriver')
$Script:TestoAggiornamenti   = $pannelloDriver.FindName('TestoAggiornamenti')
$Script:BtnControllaDriver.add_Click({ try { Controlla-AggiornamentiDriver } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
$pannelloDriver.FindName('BtnInstallaSelezionati').add_Click({ try { Installa-DriverWUMultipli $false } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
$pannelloDriver.FindName('BtnInstallaTutto').add_Click({ try { Installa-DriverWUMultipli $true } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })

# Sezione "App installate"
$pannelloApp = [Windows.Markup.XamlReader]::Parse($Script:XamlApp)
$Script:PannelloApp   = $pannelloApp
$Script:GrigliaApp    = $pannelloApp.FindName('GrigliaApp')
$Script:CercaApp      = $pannelloApp.FindName('CercaApp')
$Script:FiltroTipoApp = $pannelloApp.FindName('FiltroTipoApp')
$Script:TestoApp      = $pannelloApp.FindName('TestoApp')
$Script:CercaApp.add_TextChanged({ try { $pannelloApp.FindName('SuggerimentoCerca').Visibility = $(if ($Script:CercaApp.Text) { 'Collapsed' } else { 'Visible' }); Mostra-AppInstallate } catch { } })
$Script:FiltroTipoApp.add_SelectionChanged({ try { Mostra-AppInstallate } catch { } })
$pannelloApp.FindName('BtnAggiornaApp').add_Click({ try { Aggiorna-AppInstallate } catch { Mostra-Errore $_ } })
$pannelloApp.FindName('BtnDisinstallaApp').add_Click({ try { Disinstalla-AppScelta } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
$Script:GrigliaApp.add_MouseDoubleClick({ try { if ($Script:GrigliaApp.SelectedItem) { Disinstalla-AppScelta } } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
# Pulsanti dentro le righe: "Produttore" apre la pagina nel browser, "Installa..." avvia l'installazione.
$Script:GrigliaDispositivi.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    try { $d = $e.OriginalSource.Tag; if ($d -and $d.Pagina) { Start-Process ([string]$d.Pagina); Scrivi-Log "Aperta pagina driver: $($d.Pagina)" } } catch { Mostra-Errore $_ }
})
$Script:GrigliaAggiornamenti.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    try {
        $a = $e.OriginalSource.Tag
        if (-not $a -or -not ($a -is [OttWin.RigaAggiornamento])) { return }
        Installa-DriverWU $a
    } catch { Blocca-Pulsanti $false; Mostra-Errore $_ }
})

# Riquadro "Schede video": per NVIDIA la scelta della versione, per AMD/Intel l'installazione da file.
function Mostra-SchedeVideo {
    if (-not $Script:ElencoGpu) { return }
    $tipoPrima = $(if ($Script:CmbTipoNvidia) { $Script:CmbTipoNvidia.SelectedIndex } else { 0 })
    $versionePrima = $(if ($Script:CmbVersioniNvidia) { $Script:CmbVersioniNvidia.SelectedIndex } else { 0 })
    $Script:ElencoGpu.Children.Clear()
    $Script:CmbTipoNvidia = $null; $Script:CmbVersioniNvidia = $null
    $nvFatta = $false; $amdFatta = $false
    if (@($Script:SchedeVideo).Count -eq 0) { [void]$Script:ElencoGpu.Children.Add((Nuovo-Testo 'Nessuna scheda video rilevata.' 'Testo2')); return }
    foreach ($g in @($Script:SchedeVideo)) {
        $riga = New-Object System.Windows.Controls.DockPanel
        $riga.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
        $azioni = New-Object System.Windows.Controls.StackPanel
        $azioni.Orientation = 'Horizontal'
        $azioni.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($azioni, [System.Windows.Controls.Dock]::Right)

        if ($g.Marca -eq 'NVIDIA' -and -not $g.Base -and -not $nvFatta) {
            $nvFatta = $true
            $tipo = New-Object System.Windows.Controls.ComboBox
            $tipo.Width = 130; $tipo.Margin = New-Object System.Windows.Thickness(4, 0, 4, 0)
            [void]$tipo.Items.Add('Game Ready'); [void]$tipo.Items.Add('Studio')
            $tipo.SelectedIndex = [math]::Max(0, $tipoPrima)
            $tipo.ToolTip = 'Game Ready: ottimizzati per i giochi più recenti.  Studio: più collaudati, per programmi di grafica e video.'
            $vers = New-Object System.Windows.Controls.ComboBox
            $vers.Width = 300; $vers.Margin = New-Object System.Windows.Thickness(4, 0, 4, 0)
            $vers.ToolTip = 'Versione da installare: la più recente, la stessa già installata o una precedente'
            if (@($Script:VersioniNvidia).Count -gt 0) {
                foreach ($v in @($Script:VersioniNvidia)) {
                    $t = "$($v.Versione)   ·   $($v.Data)"
                    if ($v.Versione -eq $g.Versione) { $t += '   ·   installata adesso' }
                    [void]$vers.Items.Add($t)
                }
                $vers.SelectedIndex = [math]::Max(0, [math]::Min($versionePrima, $vers.Items.Count - 1))
            } else { [void]$vers.Items.Add((Tr 'Premi "Cerca versioni" per l''elenco')); $vers.SelectedIndex = 0 }
            $Script:CmbTipoNvidia = $tipo; $Script:CmbVersioniNvidia = $vers
            $tipo.add_SelectionChanged({
                try {
                    if (-not $Script:CmbVersioniNvidia -or -not [object]::ReferenceEquals($this, $Script:CmbTipoNvidia)) { return }
                    $Script:VersioniNvidia = @()
                    $Script:CmbVersioniNvidia.Items.Clear()
                    [void]$Script:CmbVersioniNvidia.Items.Add((Tr 'Premi "Cerca versioni" per l''elenco')); $Script:CmbVersioniNvidia.SelectedIndex = 0
                } catch { }
            })
            $cerca = Nuovo-Pulsante 'Cerca versioni' 0xE721
            $cerca.ToolTip = 'Chiede a nvidia.com l''elenco dei driver per questa scheda (non scarica e non installa niente)'
            $cerca.add_Click({ Blocca-Pulsanti $true; try { $tipoScelto = $Script:CmbTipoNvidia.SelectedIndex; [void](Cerca-VersioniNvidia); Imposta-Stato "Elenco aggiornato: scegli la versione e premi 'Installazione pulita'." } catch { Mostra-Errore $_ } finally { Blocca-Pulsanti $false } })
            $inst = Nuovo-Pulsante 'Installazione pulita...' 0xE896 'Primario'
            $inst.ToolTip = 'Scarica la versione scelta, toglie i vecchi driver e la installa da zero (con punto di ripristino). Prima vedi tutto e confermi.'
            $inst.add_Click({ try { Installa-VersioneNvidiaScelta } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
            foreach ($x in @($tipo, $vers, $cerca, $inst)) { [void]$azioni.Children.Add($x) }
        } elseif ($g.Marca -eq 'AMD' -and -not $g.Base -and -not $amdFatta -and (Pagina-VersioniAmd $g.Nome $g.IdPci)) {
            # AMD: elenco delle versioni da amd.com, come per NVIDIA
            $amdFatta = $true
            $versioneAmdPrima = $(if ($Script:CmbVersioniAmd) { $Script:CmbVersioniAmd.SelectedIndex } else { 0 })
            $vers = New-Object System.Windows.Controls.ComboBox
            $vers.Width = 340; $vers.Margin = New-Object System.Windows.Thickness(4, 0, 4, 0)
            $vers.ToolTip = 'Versione di AMD Software: Adrenalin Edition da installare: la più recente, la stessa già installata o una precedente'
            $installataAmd = Versione-Adrenalin
            if (@($Script:VersioniAmd).Count -gt 0) {
                foreach ($v in @($Script:VersioniAmd)) {
                    $t = "$($v.Versione)   ·   $($v.Data)"
                    if ($v.Consigliato) { $t += '   ·   consigliata (WHQL)' } elseif ($v.Facoltativo) { $t += '   ·   facoltativa' }
                    if ($installataAmd -and $v.Versione -eq $installataAmd) { $t += '   ·   installata adesso' }
                    [void]$vers.Items.Add($t)
                }
                $vers.SelectedIndex = [math]::Max(0, [math]::Min($versioneAmdPrima, $vers.Items.Count - 1))
            } else { [void]$vers.Items.Add((Tr 'Premi "Cerca versioni" per l''elenco')); $vers.SelectedIndex = 0 }
            $Script:CmbVersioniAmd = $vers
            $cerca = Nuovo-Pulsante 'Cerca versioni' 0xE721
            $cerca.ToolTip = 'Chiede ad amd.com l''elenco dei driver per questa scheda (non scarica e non installa niente)'
            $cerca.add_Click({ Blocca-Pulsanti $true; try { [void](Cerca-VersioniAmd); Mostra-SchedeVideo; Imposta-Stato "Elenco aggiornato: scegli la versione e premi 'Installazione pulita'." } catch { Mostra-Errore $_ } finally { Blocca-Pulsanti $false } })
            $inst = Nuovo-Pulsante 'Installazione pulita...' 0xE896 'Primario'
            $inst.ToolTip = 'Scarica la versione scelta da drivers.amd.com, toglie i vecchi driver e avvia l''installazione (con punto di ripristino). Prima vedi tutto e confermi.'
            $inst.add_Click({ try { Installa-VersioneAmdScelta } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
            $file = Nuovo-Pulsante 'Da file...' 0xE8E5 'Fantasma'
            $file.Tag = $g
            $file.ToolTip = 'Usa un programma di installazione AMD già scaricato'
            $file.add_Click({ try { Installa-DriverDaFile $this.Tag } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
            foreach ($x in @($vers, $cerca, $inst, $file)) { [void]$azioni.Children.Add($x) }
        } elseif ($g.Marca -eq 'AMD' -or $g.Marca -eq 'Intel' -or $g.Marca -eq 'NVIDIA') {
            $sito = Nuovo-Pulsante 'Sito ufficiale' 0xE774
            $sito.Tag = $g
            $sito.ToolTip = "Apre la pagina ufficiale dei driver $($g.Marca): lì scegli e scarichi la versione che vuoi"
            $sito.add_Click({ try { Start-Process ([string]$this.Tag.Pagina); Scrivi-Log "Aperta pagina driver: $($this.Tag.Pagina)" } catch { Mostra-Errore $_ } })
            [void]$azioni.Children.Add($sito)
            if ($g.Marca -ne 'NVIDIA') {
                $inst = Nuovo-Pulsante 'Installazione pulita da file...' 0xE896
                $inst.Tag = $g
                $inst.ToolTip = 'Scegli il programma di installazione scaricato dal sito ufficiale: il programma verifica la firma, toglie i vecchi driver e lo avvia (con punto di ripristino)'
                $inst.add_Click({ try { Installa-DriverDaFile $this.Tag } catch { Blocca-Pulsanti $false; Mostra-Errore $_ } })
                [void]$azioni.Children.Add($inst)
            }
        }
        $testi = New-Object System.Windows.Controls.StackPanel
        $testi.VerticalAlignment = 'Center'
        [void]$testi.Children.Add((Nuovo-Testo $g.Nome '' 13.5 $true))
        $sotto = $(if ($g.Base) { 'Driver di base di Windows: il driver del produttore non è installato' } else { "Driver $($g.Versione) del $($g.Data)  ·  $($g.Produttore)" })
        if ($g.Marca -eq 'AMD' -and -not $g.Base) { $va = Versione-Adrenalin; if ($va) { $sotto += "  ·  AMD Software $va" } }
        $ts = Nuovo-Testo $sotto 'Testo2' 12
        $ts.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$testi.Children.Add($ts)
        $ultima = $Script:UltimaVideo[$g.Marca]
        if ($ultima -and -not $g.Base) {
            $tu = Nuovo-Testo $ultima $(if ($ultima -match 'nuova') { 'Arancio' } elseif ($ultima -match 'non riuscito') { 'Rosso' } else { 'Verde' }) 12
            $tu.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
            [void]$testi.Children.Add($tu)
        }
        [void]$riga.Children.Add($azioni)
        [void]$riga.Children.Add($testi)
        [void]$Script:ElencoGpu.Children.Add($riga)
    }
}

# Sezione "Log": mostra in tempo reale cosa viene fatto.
$Script:CasellaLog = New-Object System.Windows.Controls.TextBox
$Script:CasellaLog.IsReadOnly = $true
$Script:CasellaLog.FontFamily = New-Object System.Windows.Media.FontFamily('Cascadia Mono, Consolas')
$Script:CasellaLog.FontSize = 12
$Script:CasellaLog.VerticalScrollBarVisibility = 'Auto'
$Script:CasellaLog.HorizontalScrollBarVisibility = 'Auto'

# Ordine delle sezioni nella barra laterale (la Panoramica viene creata per ultima perché elenca le altre).
Aggiungi-TitoloNav 'Generale'
$Script:Nav.Items.Add((New-Object System.Windows.Controls.ListBoxItem)) | Out-Null   # segnaposto della Panoramica
Aggiungi-TitoloNav 'Windows'
foreach ($c in @('Debloat app', 'Avvio', 'Servizi', 'Privacy', 'Prestazioni', 'Latenza', 'Grafica', 'Esplora file')) { Aggiungi-Categoria $c }
Aggiungi-Pagina 'App' 'App installate' 0xE74C $pannelloApp "Tutti i programmi e le app dello Store installati. 'Disinstalla e pulisci' avvia il programma di disinstallazione dell'app e poi cerca le cartelle e le chiavi di registro rimaste: le vedi una per una e scegli tu cosa togliere. Le cartelle vanno nel Cestino e le chiavi vengono salvate in un file .reg. Driver, runtime e componenti di Windows sono protetti." $false $false
Aggiungi-TitoloNav 'Scheda video'
Aggiungi-Categoria 'NVIDIA'
Aggiungi-Categoria 'NVIDIAAvanz'
Aggiungi-Categoria 'AMD'
Aggiungi-Pagina 'Video' 'Driver video' 0xE7F4 $pannelloVideo "Driver delle schede video. 'Controlla aggiornamenti' chiede l'ultima versione a nvidia.com e ad amd.com: non installa niente. Puoi scegliere la versione da installare (anche la stessa o una precedente) e fare un'installazione pulita; ogni installazione parte solo dopo la tua conferma, con punto di ripristino." $false $false
Aggiungi-TitoloNav 'Sistema'
Aggiungi-Pagina 'Driver' 'Altri driver' 0xE772 $pannelloDriver "Chipset, audio, rete, Bluetooth e driver del produttore del PC. 'Controlla aggiornamenti' cerca nel catalogo driver di Windows Update (driver certificati dai produttori): non installa niente. Accendi i driver che vuoi e premi 'Installa selezionati', oppure 'Installa tutto'." $false $false
Aggiungi-TitoloNav 'Manutenzione'
Aggiungi-Categoria 'Pulizia'
Aggiungi-Categoria 'Registro'
Aggiungi-Categoria 'Manutenzione'
Aggiungi-TitoloNav 'Altro'
Aggiungi-Categoria 'Avanzate'
Aggiungi-Pagina 'Log' 'Registro attività' 0xE8A5 (Nuova-Cornice $Script:CasellaLog) 'Tutto quello che il programma legge e fa viene scritto qui e nei file della cartella Dati\Log.' $false $false

# Panoramica: creata adesso (conosce tutte le sezioni) e messa al posto del segnaposto in alto.
$segnaposto = $Script:Nav.Items[1]
$Script:GruppoCorrente = 'Generale'
Aggiungi-Pagina 'Panoramica' 'Panoramica' 0xE80F $null '' $false $false
$voceNav = $Script:Pagine['Panoramica'].Elemento
$Script:Nav.Items.Remove($voceNav)
$Script:Nav.Items.Remove($segnaposto)
$Script:Nav.Items.Insert(1, $voceNav)
$Script:Pagine['Panoramica'].Contenuto = Crea-Panoramica
foreach ($nomeGruppo in @($Script:NavChiusi)) { if ($Script:GruppiNav.Contains([string]$nomeGruppo) -and $nomeGruppo -ne 'Generale') { Imposta-GruppoNav ([string]$nomeGruppo) $false $false } }
Aggiorna-VisibilitaNav

$Script:Nav.add_SelectionChanged({
    try { $i = $Script:Nav.SelectedItem; if ($i -and $i.Tag) { Mostra-Pagina ([string]$i.Tag) } } catch { Mostra-Errore $_ }
})

# Profili personalizzati
$Script:Finestra.FindName('BtnSalvaProfilo').add_Click({ try { Salva-ProfiloPersonale } catch { Mostra-Errore $_ } })
Aggiorna-PulsantiPersonali

# ---------- File per il feedback ----------
# Raccoglie in un .zip sul desktop: informazioni sul PC, report, scansione e registro di oggi, più il questionario.
# Nome utente e nome del PC vengono sostituiti con "UTENTE" e "PC". Niente viene inviato: il file lo mandi tu.
$Script:TestoQuestionario = @'
QUESTIONARIO DI FEEDBACK - REGIA
=================================
Compila quello che ti va (anche solo alcune righe) e rimanda questo file insieme al resto dello .zip.

Il tuo PC (portatile/fisso, marca, scheda video):
______________________________________________

1) Il programma si e' avviato senza problemi?   SI / NO   (se no, cosa e' successo?)
______________________________________________

2) La Panoramica era chiara? I dati in tempo reale (processore, memoria, scheda video, dischi, rete)
   e il report con i simboli ti sono sembrati corretti e utili?
______________________________________________

3) Hai provato un profilo o delle voci in "Modalita' prova"? Cosa hai visto nell'anteprima?
______________________________________________

4) Hai applicato davvero delle modifiche? Quali? Il PC e' migliorato, uguale o peggiorato?
______________________________________________

5) Qualche testo non si capiva, o c'era un termine troppo tecnico?
______________________________________________

6) Qualcosa non ha funzionato, e' sembrato lento o si e' bloccato? (quando, in quale sezione)
______________________________________________

7) Cosa manca? Cosa useresti di piu'?
______________________________________________

8) Voto da 1 a 10 e un commento libero:
______________________________________________
'@

function Pulisci-DatiPersonali([string]$Testo) {
    $t = $Testo
    foreach ($par in @(@($env:USERPROFILE, 'C:\Users\UTENTE'), @($env:USERNAME, 'UTENTE'), @($env:COMPUTERNAME, 'PC'))) {
        if ($par[0] -and $par[0].Length -gt 2) { $t = [regex]::Replace($t, [regex]::Escape($par[0]), $par[1], 'IgnoreCase') }
    }
    return $t
}

function Crea-FileFeedback {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $domanda = "Creo sul desktop un file .zip da mandare a chi ti ha dato Regia.`n`nContiene:`n•  informazioni sul PC (Windows, processore, scheda video, memoria);`n•  il report sullo stato del PC e l'elenco delle voci trovate dalla scansione;`n•  il registro di oggi (cosa ha fatto il programma);`n•  il questionario da compilare.`n`nIl nome utente e il nome del PC vengono sostituiti con 'UTENTE' e 'PC'. Non contiene password, file personali, documenti o foto. Niente viene inviato: il file lo mandi tu.`n`nVuoi crearlo?"
    if ((Mostra-Messaggio $domanda 'File per il feedback' 'YesNo' 'Information') -ne 'Yes') { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('regia_fb_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $info = "Regia $Script:Versione`r`nData: $((Get-Date).ToString('dd/MM/yyyy HH:mm'))`r`n$(Leggi-InfoSistema)`r`nPowerShell $($PSVersionTable.PSVersion)`r`nModalità prova: $(if ($Script:ChkProva.IsChecked) { 'accesa' } else { 'spenta' })`r`n"
        [IO.File]::WriteAllText((Join-Path $tmp '01_info_pc.txt'), (Pulisci-DatiPersonali $info), (New-Object Text.UTF8Encoding($true)))
        $rep = $(if ($Script:UltimoReport) { "Punteggio: $($Script:UltimoReport.Punti)/100  ($($Script:UltimoReport.Ok) a posto, $($Script:UltimoReport.Avvisi) da guardare, $($Script:UltimoReport.Problemi) problemi)`r`n`r`n" + ($Script:UltimoReport.Voci -join "`r`n") } else { 'Report non disponibile (scansione non completata).' })
        [IO.File]::WriteAllText((Join-Path $tmp '02_report.txt'), (Pulisci-DatiPersonali $rep), (New-Object Text.UTF8Encoding($true)))
        $scan = Join-Path $Script:CartellaDati 'ultima_scansione.json'
        if (Test-Path -LiteralPath $scan) { [IO.File]::WriteAllText((Join-Path $tmp '03_scansione.json'), (Pulisci-DatiPersonali ([IO.File]::ReadAllText($scan))), (New-Object Text.UTF8Encoding($true))) }
        if (Test-Path -LiteralPath $Script:FileLog) { [IO.File]::WriteAllText((Join-Path $tmp '04_registro.txt'), (Pulisci-DatiPersonali ([IO.File]::ReadAllText($Script:FileLog))), (New-Object Text.UTF8Encoding($true))) }
        [IO.File]::WriteAllText((Join-Path $tmp '05_QUESTIONARIO.txt'), $Script:TestoQuestionario.Replace("`r`n", "`n").Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding($true)))
        $zip = Join-Path $desktop ('Regia_feedback_{0:yyyyMMdd_HHmm}.zip' -f (Get-Date))
        Add-Type -AssemblyName System.IO.Compression
        $fs = [IO.File]::Open($zip, 'Create'); $za = New-Object IO.Compression.ZipArchive($fs, 'Create')
        foreach ($f in @(Get-ChildItem -LiteralPath $tmp -File)) {
            $en = $za.CreateEntry($f.Name); $s = $en.Open(); $b = [IO.File]::ReadAllBytes($f.FullName); $s.Write($b, 0, $b.Length); $s.Close()
        }
        $za.Dispose(); $fs.Close()
        Scrivi-Log "File per il feedback creato: $zip" 'OK'
        Imposta-Stato 'File per il feedback creato sul desktop.'
        [void](Mostra-Messaggio "Creato sul desktop:`n$(Split-Path -Leaf $zip)`n`nApri il file 05_QUESTIONARIO.txt dentro lo .zip, rispondi alle domande che vuoi, poi manda lo .zip a chi ti ha dato Regia.`n`nGrazie!" 'File per il feedback' 'OK' 'Information')
        Start-Process explorer.exe -ArgumentList "/select,`"$zip`""
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
$Script:Finestra.FindName('BtnFeedback').add_Click({ try { Crea-FileFeedback } catch { Mostra-Errore $_ } })

# ---------- Aggiornamenti online ----------
# Il programma controlla all'avvio se esiste una versione più recente e, solo se lo confermi, la scarica,
# verifica l'impronta SHA-256, salva la versione attuale in Versioni\ e sostituisce i file del programma.
# Dati, backup, log e profili non vengono toccati. Per pubblicare una versione leggi PUBBLICARE_ONLINE.txt.
# Indirizzo del file "versione.json" (HTTPS). Si può anche mettere in Dati\impostazioni.json come "UrlAggiornamenti".
$Script:UrlAggiornamenti = 'https://raw.githubusercontent.com/sm-bc/regia/main/versione.json'
$Script:Aggiornamento = $null

function Leggi-UrlAggiornamenti {
    $u = [string]$Script:UrlAggiornamenti
    try { $x = [string](Leggi-Impostazioni).UrlAggiornamenti; if ($x) { $u = $x } } catch { }
    return $u.Trim()
}

function Url-Https([string]$Url) {
    $r = $null
    return ([Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$r) -and $r.Scheme -eq 'https')
}

# Il pacchetto deve stare sullo stesso sito del file versione.json (o su GitHub se versione.json è su GitHub).
function Sito-Fidato([string]$UrlVersione, [string]$UrlPacchetto) {
    $m = ([Uri]$UrlVersione).Host; $z = ([Uri]$UrlPacchetto).Host
    if ($m -eq $z) { return $true }
    $gh = '(^|\.)github(usercontent)?\.com$'
    return ($m -match $gh -and $z -match $gh)
}

function Cerca-Aggiornamento([bool]$Silenzioso = $true) {
    $btn = $Script:Finestra.FindName('BtnAggiorna')
    $url = Leggi-UrlAggiornamenti
    if (-not $url) {
        if (-not $Silenzioso) { [void](Mostra-Messaggio "Gli aggiornamenti online non sono ancora attivati in questa copia di Regia.`n`nChi pubblica il programma deve indicare l'indirizzo del file versione.json (vedi PUBBLICARE_ONLINE.txt)." 'Aggiornamenti' 'OK' 'Information') }
        return $false
    }
    if (-not (Url-Https $url)) { Scrivi-Log "Indirizzo aggiornamenti non valido (serve https): $url" 'AVVISO'; return $false }
    Imposta-Stato 'Controllo aggiornamenti di Regia...'
    $r = Esegui-InBackground {
        param($u)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $q = [Net.HttpWebRequest]::Create($u); $q.Timeout = 8000; $q.ReadWriteTimeout = 8000; $q.Headers.Add('Cache-Control', 'no-cache')
            $risp = $q.GetResponse(); $ms = New-Object IO.MemoryStream
            try { $risp.GetResponseStream().CopyTo($ms) } finally { $risp.Close() }
            ([Text.Encoding]::UTF8.GetString($ms.ToArray())).TrimStart([char]0xFEFF)
        } catch { 'ERRORE: ' + $_.Exception.Message }
    } @($url)
    $testo = $(if ($r -and $r.Count -gt 0) { (@($r | ForEach-Object { [string]$_ }) -join "`n") } else { 'ERRORE: nessuna risposta' })
    if ($testo -like 'ERRORE:*') {
        Scrivi-Log "Controllo aggiornamenti non riuscito: $testo" 'AVVISO'
        Imposta-Stato 'Controllo aggiornamenti non riuscito (nessuna connessione?).'
        if (-not $Silenzioso) { [void](Mostra-Messaggio "Non sono riuscito a controllare gli aggiornamenti.`n`nControlla la connessione a Internet e riprova.`n`n$testo" 'Aggiornamenti' 'OK' 'Warning') }
        return $false
    }
    try {
        $j = $testo.TrimStart([char]0xFEFF) | ConvertFrom-Json
        $nuova = [version][string]$j.versione
        $attuale = [version]$Script:Versione
        $pacchetto = [string]$j.url; $sha = ([string]$j.sha256).Trim().ToLower()
        if (-not (Url-Https $pacchetto) -or $sha -notmatch '^[0-9a-f]{64}$') { throw 'versione.json incompleto o non valido.' }
        if (-not (Sito-Fidato $url $pacchetto)) { throw "Il pacchetto è su un sito diverso da versione.json ($pacchetto): ignorato." }
    } catch {
        Scrivi-Log "File versione.json non valido: $($_.Exception.Message)" 'AVVISO'
        Imposta-Stato 'Controllo aggiornamenti: file versione.json non valido.'
        if (-not $Silenzioso) { [void](Mostra-Messaggio "Il file con le informazioni sull'aggiornamento non è valido.`n`n$($_.Exception.Message)" 'Aggiornamenti' 'OK' 'Warning') }
        return $false
    }
    if ($nuova -le $attuale) {
        $Script:Aggiornamento = $null
        $btn.Visibility = 'Collapsed'
        Imposta-Stato "Regia $Script:Versione è la versione più recente."
        if (-not $Silenzioso) { [void](Mostra-Messaggio "Hai già la versione più recente di Regia ($Script:Versione)." 'Aggiornamenti' 'OK' 'Information') }
        return $false
    }
    $Script:Aggiornamento = @{ Versione = [string]$j.versione; Url = $pacchetto; Sha256 = $sha; Note = [string]$j.note }
    $Script:Finestra.FindName('TestoAggiorna').Text = "Aggiorna alla $($Script:Aggiornamento.Versione)"
    $btn.Visibility = 'Visible'
    Scrivi-Log "Aggiornamento disponibile: Regia $($Script:Aggiornamento.Versione) (hai la $Script:Versione)." 'OK'
    Imposta-Stato "È disponibile Regia $($Script:Aggiornamento.Versione): premi 'Aggiorna' in basso a sinistra."
    return $true
}

function Applica-Aggiornamento {
    $a = $Script:Aggiornamento
    if (-not $a) { return }
    $note = $(if ($a.Note) { "`n`nNovità:`n$($a.Note)" } else { '' })
    $domanda = "Aggiorno Regia dalla versione $Script:Versione alla $($a.Versione)?$note`n`nIl pacchetto viene scaricato da:`n$($a.Url)`ne controllato con l'impronta SHA-256. Prima di sostituire il programma ne salvo una copia nella cartella Versioni. Dati, backup, log e profili non vengono toccati. Alla fine Regia si riavvia."
    if ((Mostra-Messaggio $domanda 'Aggiornamento di Regia' 'YesNo' 'Information') -ne 'Yes') { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('regia_agg_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Imposta-Stato "Scarico Regia $($a.Versione)..."
        $zip = Join-Path $tmp 'regia.zip'
        $r = Esegui-InBackground {
            param($u, $f)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $q = [Net.HttpWebRequest]::Create($u); $q.Timeout = 30000; $q.ReadWriteTimeout = 30000; $risp = $q.GetResponse()
                try { $fs = [IO.File]::Create($f); try { $risp.GetResponseStream().CopyTo($fs) } finally { $fs.Close() } } finally { $risp.Close() }
                (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower()
            } catch { 'ERRORE: ' + $_.Exception.Message }
        } @($a.Url, $zip)
        $hash = $(if ($r -and $r.Count -gt 0) { [string]@($r)[-1] } else { 'ERRORE: nessuna risposta' })
        if ($hash -like 'ERRORE:*') { throw "Download non riuscito. $hash" }
        if ($hash -ne $a.Sha256) { throw "Il file scaricato non corrisponde all'impronta SHA-256 attesa: aggiornamento annullato, il programma non è stato modificato." }
        Scrivi-Log "Pacchetto $($a.Versione) scaricato e verificato (SHA-256 $hash)." 'OK'

        $estratto = Join-Path $tmp 'x'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $estratto)
        $nuovoPs1 = @(Get-ChildItem -LiteralPath $estratto -Recurse -Filter 'Regia.ps1' -File | Select-Object -First 1)
        if ($nuovoPs1.Count -eq 0) { throw 'Nel pacchetto manca Regia.ps1.' }
        $cartellaNuova = $nuovoPs1[0].DirectoryName
        $byte = [IO.File]::ReadAllBytes($nuovoPs1[0].FullName)
        if ($byte.Length -lt 3 -or $byte[0] -ne 239 -or $byte[1] -ne 187 -or $byte[2] -ne 191) { throw 'Il nuovo Regia.ps1 non è nel formato atteso (manca il BOM UTF-8).' }
        $err = $null; $tk = $null
        [void][Management.Automation.Language.Parser]::ParseFile($nuovoPs1[0].FullName, [ref]$tk, [ref]$err)
        if ($err -and $err.Count -gt 0) { throw "Il nuovo Regia.ps1 contiene errori di sintassi: $($err[0].Message)" }
        if ([IO.File]::ReadAllText($nuovoPs1[0].FullName) -notmatch [regex]::Escape("`$Script:Versione       = '$($a.Versione)'")) { throw "La versione dentro il pacchetto non è la $($a.Versione)." }

        $cartVersioni = Join-Path $Script:CartellaBase 'Versioni'
        if (-not (Test-Path -LiteralPath $cartVersioni)) { New-Item -ItemType Directory -Path $cartVersioni -Force | Out-Null }
        $copia = Join-Path $cartVersioni "Regia_$Script:Versione.ps1"
        if (Test-Path -LiteralPath $copia) { $copia = Join-Path $cartVersioni ("Regia_{0}_{1:yyyyMMddHHmm}.ps1" -f $Script:Versione, (Get-Date)) }
        Copy-Item -LiteralPath $Script:FileProgramma -Destination $copia -Force
        Scrivi-Log "Versione attuale salvata in $copia" 'OK'

        foreach ($nome in @('Regia.ps1', 'Avvia.cmd', 'LEGGIMI.txt', 'INIZIA_QUI.html', 'Regia.ico')) {
            $da = Join-Path $cartellaNuova $nome
            if (Test-Path -LiteralPath $da) { Copy-Item -LiteralPath $da -Destination (Join-Path $Script:CartellaBase $nome) -Force }
        }
        Scrivi-Log "Regia aggiornato alla versione $($a.Versione)." 'OK'
        Imposta-Stato "Aggiornato alla versione $($a.Versione)."
        if ((Mostra-Messaggio "Aggiornamento completato: ora hai la versione $($a.Versione).`n`nRiavvio Regia adesso?" 'Aggiornamento di Regia' 'YesNo' 'Information') -eq 'Yes') {
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$Script:FileProgramma`"")
            $Script:Finestra.Close()
        }
        $Script:Finestra.FindName('BtnAggiorna').Visibility = 'Collapsed'
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
# Pulsante "Sostieni Regia": compare solo se è indicata una pagina per le donazioni (https). Si apre solo quando lo premi.
$Script:UrlDonazioni = ''
try { $ud = [string](Leggi-Impostazioni).UrlDonazioni; if ($ud) { $Script:UrlDonazioni = $ud } } catch { }
if (Url-Https $Script:UrlDonazioni) {
    $Script:Finestra.FindName('BtnSostieni').Visibility = 'Visible'
    $Script:Finestra.FindName('BtnSostieni').add_Click({ try { Start-Process $Script:UrlDonazioni } catch { Mostra-Errore $_ } })
}
$Script:Finestra.FindName('BtnAggiorna').add_Click({ try { Applica-Aggiornamento } catch { Scrivi-Log "Aggiornamento non riuscito: $($_.Exception.Message)" 'ERRORE'; Mostra-Errore $_ } })
# Selettore della lingua (English / Italiano): la scelta vale dal prossimo avvio, il programma propone di riavviare.
$Script:Finestra.FindName('BtnLingua').Content = ([string]$Script:Lingua).ToUpper()
$Script:Finestra.FindName('BtnLingua').add_Click({
    try {
        $nuova = $(if ($Script:Lingua -eq 'en') { 'it' } else { 'en' })
        Salva-Impostazione 'Lingua' $nuova
        $domanda = $(if ($nuova -eq 'en') { 'Language changed to English. Restart Regia now to apply it?' } else { 'Lingua cambiata in italiano. Riavviare Regia adesso per applicarla?' })
        if ((Mostra-Messaggio $domanda 'Language / Lingua' 'YesNo' 'Information') -eq 'Yes') {
            Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$Script:FileProgramma`"")
            $Script:Finestra.Close()
        }
    } catch { Mostra-Errore $_ }
})
$Script:Finestra.FindName('BtnControllaAgg').add_Click({ try { [void](Cerca-Aggiornamento $false) } catch { Mostra-Errore $_ } })

# ---------- Pulsanti ----------
foreach ($k in @($Script:PulsantiProfilo.Keys)) {
    $Script:PulsantiProfilo[$k].Tag = $k
    $Script:PulsantiProfilo[$k].add_Click({ try { $p = [string]$this.Tag; if (Applica-Profilo $p) { Evidenzia-Profilo $p } } catch { Mostra-Errore $_ } })
}
$Script:Finestra.FindName('BtnNessuno').add_Click({
    try {
        [void](Applica-PresetNvidia 'Attuale' -Silenzioso)
        foreach ($r in $Script:TutteLeRighe) { if (-not $r.Opzioni) { $r.Selezionata = $false } }
        Evidenzia-Profilo ''
        Aggiorna-Intestazioni
        Imposta-Stato 'Tutte le voci sono state spente.'
    } catch { Mostra-Errore $_ }
})
$Script:Finestra.FindName('BtnScansiona').add_Click({ try { Esegui-Scansione } catch { Mostra-Errore $_ } })
$Script:Finestra.FindName('BtnApplica').add_Click({ try { Applica-Modifiche 'Consigliato' } catch { Mostra-Errore $_ } })
$Script:Finestra.FindName('BtnPredefinito').add_Click({ try { Applica-Modifiche 'Predefinito' } catch { Mostra-Errore $_ } })
$Script:Finestra.FindName('BtnAnnullaTutto').add_Click({ try { Annulla-Tutto } catch { Mostra-Errore $_ } })
$Script:Finestra.FindName('BtnCartella').add_Click({ Start-Process explorer.exe -ArgumentList "`"$Script:CartellaDati`"" })
$Script:Finestra.FindName('BtnRiavvia').add_Click({ try { [void](Proponi-Riavvio) } catch { Mostra-Errore $_ } })
# God Mode: la cartella speciale di Windows con tutte le impostazioni del Pannello di controllo.
# Si apre direttamente con il suo codice (shell:::{...}): non si crea nessuna cartella sul desktop.
$Script:Finestra.FindName('BtnGodMode').add_Click({
    try {
        Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList 'shell:::{ED7BA470-8E54-465E-825C-99712043E01C}'
        Scrivi-Log 'Aperto God Mode (tutte le impostazioni del Pannello di controllo).'
    } catch { Mostra-Errore $_ }
})
$Script:Finestra.FindName('BtnCollegamento').add_Click({ try { [void](Crea-Collegamento) } catch { Mostra-Errore $_ } })
$Script:Finestra.FindName('BtnTema').add_Click({
    try { Imposta-Tema $(if ($Script:TemaAttuale -eq 'Scuro') { 'Chiaro' } else { 'Scuro' }) } catch { Mostra-Errore $_ }
})
$Script:ChkProva.add_Click({
    if ($Script:ChkProva.IsChecked) { Scrivi-Log 'Modalità prova ATTIVATA: nessuna modifica verrà applicata.' }
    else { Scrivi-Log 'Modalità prova DISATTIVATA: le modifiche confermate verranno applicate davvero.' 'AVVISO' }
})

# Errori imprevisti dell'interfaccia: mostrati e registrati, senza chiudere il programma.
$Script:Finestra.Dispatcher.add_UnhandledException({
    param($s, $e)
    $e.Handled = $true
    Mostra-Errore $e.Exception
})

# Prima scansione automatica appena la finestra è visibile (solo lettura).
$Script:Finestra.add_ContentRendered({
    # Avviso all'apertura: la Modalità prova è accesa e non viene applicato niente finché non si toglie la spunta.
    try {
        if ($Script:ChkProva.IsChecked) {
            [void](Mostra-Messaggio "Regia è in MODALITÀ PROVA.`n`nPuoi guardare, scegliere e vedere l'anteprima di tutto, ma le modifiche NON vengono applicate al PC finché non togli la spunta da «Modalità prova» (interruttore in alto a destra).`n`nQuando sei pronto a modificare davvero, spegni l'interruttore: prima di ogni modifica ti verrà chiesta conferma e potrai creare un punto di ripristino." 'Modalità prova attiva' 'OK' 'Information')
        }
    } catch { }
    try { Esegui-Scansione } catch { Mostra-Errore $_ }
    try { Aggiorna-Dispositivi } catch { Scrivi-Log "Elenco dispositivi non disponibile: $($_.Exception.Message)" 'AVVISO' }
    try { Aggiorna-AppInstallate } catch { Scrivi-Log "Elenco app non disponibile: $($_.Exception.Message)" 'AVVISO' }
    try { Aggiorna-StatoRiavvio; if (Serve-RiavvioWindows) { Scrivi-Log 'Windows ha operazioni che si completano al riavvio.' 'AVVISO' } } catch { }
    try { [void](Cerca-Aggiornamento $true) } catch { Scrivi-Log "Controllo aggiornamenti: $($_.Exception.Message)" 'AVVISO' }
})

Traduci-Albero $Script:Finestra
Vai-A 'Panoramica'
Aggiorna-ConteggioSelezione
Scrivi-Log "=== Regia $Script:Versione avviato (utente: $env:USERNAME, PC: $env:COMPUTERNAME) ==="
Scrivi-Log "Sistema: $(Leggi-InfoSistema)"
Scrivi-Log "PowerShell $($PSVersionTable.PSVersion) · cartella dati: $Script:CartellaDati"
if ($Script:AvvisoAvvio) { Scrivi-Log $Script:AvvisoAvvio 'AVVISO' }
Scrivi-Log 'Modalità prova ATTIVA: nessuna modifica verrà applicata finché non spegni l''interruttore.'
[void]$Script:Finestra.ShowDialog()
$Script:Sensori.Attivo = $false
Scrivi-Log '=== Programma chiuso ==='
exit 0
