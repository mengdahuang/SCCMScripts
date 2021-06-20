Clear-Host

# Hide the PowerShell Window - https://community.spiceworks.com/topic/1710213-hide-a-powershell-console-window-when-running-a-script
$Script:showWindowAsync = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@ -Name "Win32ShowWindowAsync" -Namespace Win32Functions -PassThru
$null = $showWindowAsync::ShowWindowAsync((Get-Process -Id $pid).MainWindowHandle, 2) #>

# Assign current script directory to a global variable
$Global:MyScriptDir = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)

# Load presentationframework and Dlls for the MahApps.Metro theme
[System.Reflection.Assembly]::LoadWithPartialName("presentationframework") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$Global:MyScriptDir\assembly\System.Windows.Interactivity.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$Global:MyScriptDir\assembly\MahApps.Metro.dll") | Out-Null

# Temporarily close the TS progress UI
$TSProgressUI = New-Object -COMObject Microsoft.SMS.TSProgressUI
$TSProgressUI.CloseProgressDialog()

# Set console size and title
$host.ui.RawUI.WindowTitle = "Choose hard disk..."

Function LoadForm {
    [CmdletBinding()]
    Param(
     [Parameter(Mandatory=$True,Position=1)]
     [string]$XamlPath
    )
    
    # Import the XAML code
    [xml]$Global:xmlWPF = Get-Content -Path $XamlPath

    # Add WPF and Windows Forms assemblies
    Try {
        Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,system.windows.forms
    } 
    Catch {
        Throw "Failed to load Windows Presentation Framework assemblies."
    }

    #Create the XAML reader using a new XML node reader
    $Global:xamGUI = [Windows.Markup.XamlReader]::Load((new-object System.Xml.XmlNodeReader $xmlWPF))

    #Create hooks to each named object in the XAML
    $xmlWPF.SelectNodes("//*[@Name]") | ForEach {
        Set-Variable -Name ($_.Name) -Value $xamGUI.FindName($_.Name) -Scope Global
    }
}

Function Get-SelectedDiskInfo {
    
    # Get the selected disk with the model which matches the model selected in the List Box
    $SelectedDisk = Get-Disk | Where-Object { $_.Number -eq $Global:ArrayOfDiskNumbers[$ListBox.SelectedIndex] }

    # Unhide the disk information labels
    $DiskInfoLabel.Visibility = "Visible"
    $DiskNumberLabel.Visibility = "Visible"
    $SizeLabel.Visibility = "Visible"
    $HealthStatusLabel.Visibility = "Visible"
    $PartitionStyleLabel.Visibility = "Visible"

    # Populate the labels with the disk information
    $DiskNumber.Content = "$($SelectedDisk.Number)"
    $HealthStatus.Content = "$($SelectedDisk.HealthStatus), $($SelectedDisk.OperationalStatus)"
    $PartitionStyle.Content = $SelectedDisk.PartitionStyle

    # Work out if the size should be in GB or TB
    If ([math]::Round(($SelectedDisk.Size/1TB),2) -lt 1) {
        $Size.Content = "$([math]::Round(($SelectedDisk.Size/1GB),0)) GB"
    }
    Else {
        $Size.Content = "$([math]::Round(($SelectedDisk.Size/1TB),2)) TB"
    }
}

# Load the XAML form and create the PowerShell Variables
LoadForm -XamlPath “$MyScriptDir\ChooseDiskXAML.xaml“

# Create empty array of hard disk numbers
$Global:ArrayOfDiskNumbers = @()

# Populate the listbox with hard disk models and the array with disk numbers
Get-Disk | Where-Object -FilterScript {$_.Bustype -ne 'USB'} | Sort-Object {$_.Number}| ForEach {
    # Add item to the List Box
    $ListBox.Items.Add($_.Model) | Out-Null
    
    # Add the serial number to the array
    $ArrayOfDiskNumbers += $_.Number

}

# EVENT Handlers 
$OKButton.add_Click({
    # If no disk is selected in the ListBox then do nothing
    If (-not ($ListBox.SelectedItem)) {
        # Do nothing 
    }
    Else {
        # Else If a disk is selected then get the disk with a matching disk number according to the selection in the ListBox
        $Disk = Get-Disk | Where-Object {$_.Number -eq $Global:ArrayOfDiskNumbers[$ListBox.SelectedIndex]}
        
        # Set the Task Sequence environment object
        $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment

        # Populate the OSDDiskIndex variable with the disk number
        $TSEnv.Value("OSDDiskIndex") = $Disk.Number

        # Close the WPF GUI
        $xamGUI.Close()
    }
})

$ListBox.add_SelectionChanged({  
    # Call function to pull the disk informaiton and populate the details on the form
    Get-SelectedDiskInfo
})

# Launch the window
$xamGUI.ShowDialog() | Out-Null