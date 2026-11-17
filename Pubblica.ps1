<#
  Pubblica.ps1 - prepara una nuova versione di Regia per la pubblicazione online.
  Uso:  .\Pubblica.ps1 -Utente NOMEUTENTE -Repo regia -Note "Cosa c'è di nuovo"
  Crea Distribuzione\Regia_<versione>.zip e versione.json (con SHA-256). Non carica niente: i due file
  si caricano a mano su GitHub (vedi PUBBLICARE_ONLINE.txt).
#>
param(
    [Parameter(Mandatory)][string]$Utente,
    [Parameter(Mandatory)][string]$Repo,
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
$cartella = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1 = Join-Path $cartella 'Regia.ps1'
$testo = [IO.File]::ReadAllText($ps1)
if ($testo -notmatch "\`$Script:Versione\s*=\s*'([0-9.]+)'") { throw 'Non trovo il numero di versione in Regia.ps1.' }
$versione = $Matches[1]
$b = [IO.File]::ReadAllBytes($ps1)
if ($b[0] -ne 239 -or $b[1] -ne 187 -or $b[2] -ne 191) { throw 'Regia.ps1 non ha il BOM UTF-8: non lo pubblico.' }
$err = $null; $tk = $null
[void][Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$tk, [ref]$err)
if ($err.Count -gt 0) { throw "Errori di sintassi in Regia.ps1: $($err[0].Message)" }

$dist = Join-Path $cartella 'Distribuzione'
if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
$zip = Join-Path $dist "Regia_$versione.zip"
if (Test-Path $zip) { throw "$zip esiste già: aumenta il numero di versione." }
Add-Type -AssemblyName System.IO.Compression
$fs = [IO.File]::Open($zip, 'Create'); $za = New-Object IO.Compression.ZipArchive($fs, 'Create')
foreach ($f in 'Regia.ps1', 'Avvia.cmd', 'LEGGIMI.txt', 'INIZIA_QUI.html', 'Regia.ico') {
    $en = $za.CreateEntry("Regia/$f"); $s = $en.Open(); $by = [IO.File]::ReadAllBytes((Join-Path $cartella $f)); $s.Write($by, 0, $by.Length); $s.Close()
}
$za.Dispose(); $fs.Close()
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$json = [ordered]@{
    versione = $versione
    url      = "https://github.com/$Utente/$Repo/releases/download/v$versione/Regia_$versione.zip"
    sha256   = $sha
    note     = $Note
}
$out = Join-Path $cartella 'versione.json'
[IO.File]::WriteAllText($out, ($json | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
"Creato: $zip"
"Creato: $out"
"SHA-256: $sha"
"Ora su GitHub: nuova Release con tag v$versione e lo zip allegato, poi carica versione.json nel repository."