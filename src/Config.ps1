# Configuration
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    powershell -STA -File $PSCommandPath $args
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$baseOrange = [System.Drawing.ColorTranslator]::FromHtml("#E26E2A")
$script:borderColor = $baseOrange
$script:formBackColor = [System.Drawing.ColorTranslator]::FromHtml("#F5F5F5")
$script:textBoxForeColor = [System.Drawing.ColorTranslator]::FromHtml("#272727")
$script:placeholderColor = [System.Drawing.Color]::Gray

try { 
    $script:font = New-Object System.Drawing.Font("Arial", 10) 
} catch { 
    $script:font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10) 
}

$script:placeholder = "Renseigner le point de collecte"