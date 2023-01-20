<# 
Este script intentará listar todas las .iso en la carpeta actual, con la intención de
extraer la información sobre la versión de Windows presente en el.

Procedimiento:

- Se listan todos los ficheros .iso
- De uno en uno se intentan montar en una unidad
- Se efectúa un dism /get-wiminfo sobre ellos para obtener detalles
- Los detalles se guardan en un archivo de texto que tiene el mismo nombre que la .iso
- Se procede a desmontar la .iso  
#>

# Listamos todas las *.iso de la carpeta
Get-ChildItem -path .\* -Include *.iso -Attributes a  | 
# para cada iso
ForEach-Object { 
    # obtenemos la ruta completa de la .iso
    $FullImagePath = $_.FullName 

    # el nombre de archivo de salida, el mismo nombre que la iso pero la extensión .txt
    $Output = $_.BaseName + ".txt" 

    # el nombre de la .iso
    $FileName = $_.Name

    # dedicamos unas palabras 
    Write-Host "Procesando " -NoNewline
    Write-Host $FileName -ForegroundColor Green -NoNewline
    Write-Host " `> " -NoNewline
    Write-Host $Output -ForegroundColor Cyan

    
    # verificamos si la iso es válida 
    try {
        $Image = get-DiskImage -ImagePath $FullImagePath -ErrorAction Stop
    }
    catch {
        Write-Warning "Error en el archivo ISO $FileName"
        return
    }
    # verificamos si la iso en cuestión ya se encuentra montada
    if (!($Image).Attached) {
        # la imagen no está montada, vamos a intentar montarla
        
        # Usamos esta variable para posteriormente saber si debemos desmontar la imagen o no
        $NoDismount = $false

        try {
            $DiskImage = Mount-DiskImage -ImagePath $FullImagePath -PassThru -ErrorAction Stop
        }
        catch {
            # el montaje ha fallado, saltando
            Write-Warning "Error montando la ISO $FileName"
            return
        }
    }
    else {
        $NoDismount = $true
        $DiskImage = get-DiskImage -ImagePath $FullImagePath
        Write-Warning "La iso ya se encuentra montada, utilizando la existente"
    }
    
    # obtenemos el volumen montado
    $DiskVolume = $DiskImage | get-Volume 

    # obtenemos la letra de acceso a la unidad
    $DiskLetter = $($DiskVolume.DriveLetter) 

    # contiene la ruta a la carpeta sources
    $SourceFolder = $DiskLetter + ":\sources" 



    # buscamos el archivo de instalación, puede ser .wim, .esd


    try {
        $SourceFiles = Get-Childitem -Path $SourceFolder\* -Include install.* -ErrorAction Stop
    }
    catch {
        Write-Warning "${DiskLetter}: No parece ser disco de Windows"
        if ($NoDismount -eq $false) {
            Dismount-DiskImage -ImagePath $FullImagePath | Out-Null
        }
        return
    }
    $SourceFile = ($SourceFiles | Where-Object { $_.Extension -In ".wim", ".esd" })[0]

    if ($SourceFile -eq $null) {
        Write-Warning "No se ha encontrado instalación de windows en $SourceFolder"
        if ($NoDismount -eq $false) {
            Dismount-DiskImage -ImagePath $FullImagePath | Out-Null
        }
        return
    }
    
    # intentamos guardar en una variable la información general sobre la imagen
    
    $OutText = dism /get-wiminfo /wimfile:$SourceFile
    
    if ($LastExitCode -ne 0) {
        Write-Warning "No se ha conseguido obtener la información del archivo $SourceFile"
        if ($NoDismount -eq $false) {
            Dismount-DiskImage -ImagePath $FullImagePath | Out-Null
        }
        return
    }

    # Información obtenida con éxito, intentando guardar
    $OutText | Out-File -FilePath "$Output"
    

    foreach ($i in Get-WindowsImage -ImagePath "$SourceFile") {
        # procesamos cada una de las entradas presentes en el archivo .iso de forma extendida
        # y las anexamos al archivo de salida
        dism /get-wiminfo /wimfile:$SourceFile /index:$($i.ImageIndex) >> $Output
        # lo tenía de esta otra forma pero me empezó a dar error y no sabía arreglarlo:
        # dism /get-wiminfo /wimfile:$SourceFile /index:$($i.ImageIndex) | Add-Content -Path $Output
    }

    # desmontamos la iso
    if ($NoDismount -eq $false) {
        Dismount-DiskImage -ImagePath $FullImagePath | Out-Null
    }
}
