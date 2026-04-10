if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    powershell -STA -File $PSCommandPath $args
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Tous les styles sont dans Styles.ps1
