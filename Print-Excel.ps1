<#
.SYNOPSIS
    Prints an Excel .xlsx file from the terminal, with printer selection when multiple printers are available.
.EXAMPLE
    .\Print-Excel.ps1 C:\path\to\file.xlsx
    .\Print-Excel.ps1 C:\path\to\file.xlsx -Copies 2
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath,

    [int]$Copies = 1
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

# --- Printer selection ---
if ($printers.Count -eq 1) {
    $selectedPrinter = $printers[0]
    Write-Host "Single printer found — using: $selectedPrinter"
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

Write-Host ""
Write-Host "File   : $([System.IO.Path]::GetFileName($FilePath))"
Write-Host "Printer: $selectedPrinter"
Write-Host "Copies : $Copies"
Write-Host ""

# --- Print via Excel COM ---
$excel    = $null
$workbook = $null

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible        = $false
    $excel.DisplayAlerts  = $false

    $workbook = $excel.Workbooks.Open($FilePath, 0, $true)   # ReadOnly = true

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
}
