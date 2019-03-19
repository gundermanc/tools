# MSBuild Error List
# By: Christian Gunderman
# gundermanc@gmail.com

# Must be run from within PowerShell.exe session. Cmd sessions do not work properly.
# msbuild.exe | .\MSBuildErrorList.ps1
# Parses MSBuild output that is piped in and creates a clickable error list.
# Opens VS to the specific file when double clicked.

Begin {
    # Executes once before first item in pipeline is processed
    $errorCount = 0
    $warningCount = 0
    $items = New-Object System.Collections.ArrayList
    $itemsPath = New-Object System.Collections.ArrayList
    $itemsLine = New-Object System.Collections.ArrayList
}

Process {
    # Executes once for each pipeline object
    if ($_ -imatch "(^.*:( )*$)|(WARNING)")
    {
        Write-Host $_ -ForegroundColor Yellow
    }
    elseif ($_ -imatch "(FAILED)|(ERROR)|(UNSUCCESS)" -and $_ -inotmatch "unsuccessfulbuild")
    {
        Write-Host $_ -ForegroundColor Red
    }
    elseif ($_ -imatch "(SUCCESS)|(SUCCEED)" -and $_ -inotmatch "unsuccessfulbuild")
    {
        Write-Host $_ -ForegroundColor Green
    }
    else
    {
        Write-Host $_ -ForegroundColor Cyan
    }

    # Classify errors
    if ($_ -imatch " *(([A-Z]|[A-Z]):\\.*)\(([0-9]+)(,[0-9]+)?\):( *)(error|warning)( *)(.*)")
    {
        $path = $Matches[1]
        $lineNum = $Matches[3]
        $errOrWarn = $Matches[6].ToUpperInvariant()
        $message = $Matches[8]

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($path)

        $newItem = "$errOrWarn`t$fileName`t($lineNum)`t$message"
        
        # Hope you don't have a lot of errors because this will be slow.
        if (!$items.Contains($newItem))
        {
            [void]$items.Add($newItem)
            [void]$itemsPath.Add($path)
            [void]$itemsLine.Add($lineNum)
        }
    }

    if ($_ -match "^( )*([0-9]+) Error\(s\).*$")
    {
        $errorCount = $Matches[2]
    }

    if ($_ -match "^( )*([0-9]+) Warning\(s\).*$")
    {
        $warningCount = $Matches[2]
    }
}

End {
    # Executes once after last pipeline object is processed

    function Launch-VS($path, $lineNum)
    {
        Trap
        {
            [System.Windows.Forms.MessageBox]::Show("Error creating Visual Studio COM object.")
        }

        function Get-VS
        {
            Trap
            {
                return New-Object -ComObject VisualStudio.DTE
            }

            return [System.Runtime.InteropServices.Marshal]::GetActiveObject("VisualStudio.DTE")
        }

        $vs = Get-VS

        $vs.ExecuteCommand("File.OpenFile", "`"$path`"")
        $vs.ExecuteCommand("Edit.Goto", "$lineNum")

        $vs.MainWindow.Activate();
    }

    function Error-Dialog($errorCount, $warningCount, $items, $itemsPath, $itemsLine)
    {
        Add-Type -AssemblyName System.Windows.Forms  # Technically deprecated, but YOLO :)

        $font = New-Object System.Drawing.Font("Segoe UI", 12,[System.Drawing.FontStyle]::Regular)

        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Width = 650
        $dialog.Height = 450
        $dialog.Text = "MSBuild Error List: (E $errorCount) (W $warningCount)"
        $dialog.BackColor = [System.Drawing.Color]::LightBlue

        $errorLabel = New-Object System.Windows.Forms.Label
        $errorLabel.Width = $dialog.ClientSize.Width - 10
        $errorLabel.Font = $font

        $errorLabel.Text = "$errorCount Errors, $warningCount Warnings          By: Christian Gunderman"
        $loc = New-Object System.Drawing.Point
        $loc.X = 10
        $loc.Y = 10
        $errorLabel.Location = $loc
        $dialog.Controls.Add($errorLabel)

        $errorList = New-Object System.Windows.Forms.ListBox
        $loc = New-Object System.Drawing.Point
        $loc.X = 10
        $loc.Y = 35
        $errorlist.BackColor = [System.Drawing.Color]::DarkGray
        $errorList.Location = $loc
        $errorList.Font = $font
        $errorList.Update()
        $errorList.Width = $dialog.ClientSize.Width - 20
        $errorList.Height = $dialog.ClientSize.Height - 45
        $errorList.ScrollAlwaysVisible = $true
        $errorList.HorizontalScrollbar = $true
        $dialog.Controls.Add($errorList)
        $errorList.Items.AddRange($items)
        $errorList.add_MouseDoubleClick(
            {
                $index = $errorList.SelectedIndex

                if ($index -eq -1)
                {
                    return
                }

                $path = $itemsPath[$index]
                $lineNum = $itemsLine[$index]

                Launch-VS  $path $lineNum
            })
        $dialog.add_SizeChanged(
            {
                $errorList.Width = $dialog.ClientSize.Width - 20
                $errorList.Height = $dialog.ClientSize.Height - 45
            })

        [void]$dialog.ShowDialog()
    }

    if ($errorCount -gt 0 -or $warningCount -gt 0)
    {
        Error-Dialog $errorCount $warningCount $items.ToArray() $itemsPath.ToArray() $itemsLine.ToArray()
    }
}
