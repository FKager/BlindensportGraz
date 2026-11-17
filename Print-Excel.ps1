<#
.SYNOPSIS
    Converts an Excel .xlsx file to PDF and prints it on the HP Color LaserJet
    (or the first available printer when no HP is found).
.EXAMPLE
    .\Print-Excel.ps1 C:\path\to\file.xlsx
    .\Print-Excel.ps1 C:\path\to\file.xlsx -Copies 2
    .\Print-Excel.ps1 C:\path\to\file.xlsx -NoPdf
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath,

    [int]$Copies = 1,

    [switch]$NoPdf   # skip PDF export
)

# Resolve to absolute path
try {
    $resolved = Resolve-Path -LiteralPath $FilePath -ErrorAction Stop
    $FilePath = $resolved.Path
} catch {
    Write-Error "File not found: $FilePath"
    exit 1
}

if (-not $FilePath.ToLower().EndsWith('.xlsx')) {
    Write-Warning "File does not have an .xlsx extension — Excel may refuse to open it."
}

# --- Printer discovery ---
$printers = @(
    Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name |
        Sort-Object
)

if ($printers.Count -eq 0) {
    Write-Error "No printers found on this system."
    exit 1
}

# --- Printer selection — auto-prefer HP Color LaserJet ---
$hpPrinter = $printers | Where-Object { $_ -match 'HP.+LaserJet' } | Select-Object -First 1

if ($printers.Count -eq 1) {
    $selectedPrinter = $printers[0]
    Write-Host "Single printer found — using: $selectedPrinter"
} elseif ($hpPrinter) {
    $selectedPrinter = $hpPrinter
    Write-Host "HP Color LaserJet found — using: $selectedPrinter"
} else {
    Write-Host "`nAvailable printers:`n"
    for ($i = 0; $i -lt $printers.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $printers[$i])
    }

    $selection = $null
    while ($null -eq $selection) {
        $raw = Read-Host ("`nSelect printer [1-{0}]" -f $printers.Count)
        $n = $raw -as [int]
        if ($n -ge 1 -and $n -le $printers.Count) {
            $selection = $n
        } else {
            Write-Host "  Invalid choice — enter a number between 1 and $($printers.Count)."
        }
    }
    $selectedPrinter = $printers[$selection - 1]
}

# --- PDF path (same folder and base name as the xlsx) ---
$pdfPath = [System.IO.Path]::ChangeExtension($FilePath, '.pdf')

Write-Host ""
Write-Host "File   : $([System.IO.Path]::GetFileName($FilePath))"
if (-not $NoPdf) { Write-Host "PDF    : $([System.IO.Path]::GetFileName($pdfPath))" }
Write-Host "Printer: $selectedPrinter"
Write-Host "Copies : $Copies"
Write-Host ""

# --- Force Tray 1 on HP Color LaserJet ---
# The driver defaults to Tray 2; override via PrintTicket before every job.
$printQueue    = $null
$originalTicket = $null

if ($selectedPrinter -match 'HP.+LaserJet') {
    Add-Type -AssemblyName System.Printing
    $printQueue     = (New-Object System.Printing.LocalPrintServer).GetPrintQueue($selectedPrinter)
    $originalTicket = $printQueue.DefaultPrintTicket

    $reader  = New-Object System.IO.StreamReader($originalTicket.GetXmlStream())
    $ticketXml = $reader.ReadToEnd()
    $reader.Dispose()

    if ($ticketXml -match 'Tray2') {
        $tray1Xml = @"
<psf:PrintTicket xmlns:psf="http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework"
  xmlns:psk="http://schemas.microsoft.com/windows/2003/08/printing/printschemakeywords"
  xmlns:ns0001="http://schemas.hp.com/ptpc/2006/1" version="1">
  <psf:Feature name="psk:JobInputBin">
    <psf:Option name="ns0001:Tray1"/>
  </psf:Feature>
</psf:PrintTicket>
"@
        $tray1Ticket = New-Object System.Printing.PrintTicket(
            [System.IO.MemoryStream][System.Text.Encoding]::UTF8.GetBytes($tray1Xml)
        )
        $printQueue.DefaultPrintTicket = $tray1Ticket
        $printQueue.Commit()
        Write-Host "Paper tray : Tray 2 → Tray 1 (overriding driver default)"
    } else {
        Write-Host "Paper tray : Tray 1 (already set)"
        $printQueue    = $null   # nothing to restore
        $originalTicket = $null
    }
}

# --- Print via Excel COM ---
$excel    = $null
$workbook = $null

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible        = $false
    $excel.DisplayAlerts  = $false

    $workbook = $excel.Workbooks.Open($FilePath, 0, $true)   # ReadOnly = true

    # Export to PDF (0 = xlTypePDF)
    if (-not $NoPdf) {
        $workbook.ExportAsFixedFormat(0, $pdfPath)
        Write-Host "PDF saved : $pdfPath"
    }

    # PrintOut(From, To, Copies, Preview, ActivePrinter, PrintToFile, Collate)
    $workbook.PrintOut(
        [Type]::Missing,   # From  (all sheets)
        [Type]::Missing,   # To
        $Copies,
        $false,            # Preview
        $selectedPrinter
    )

    Write-Host "Print job sent successfully."
} catch {
    Write-Error "Print failed: $_"
    exit 1
} finally {
    if ($null -ne $workbook) {
        $workbook.Close($false) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
    }
    if ($null -ne $excel) {
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if ($null -ne $printQueue -and $null -ne $originalTicket) {
        $printQueue.DefaultPrintTicket = $originalTicket
        $printQueue.Commit()
    }
}
