# create-structure.ps1

$root = "."

# Création des dossiers
$folders = @(
    "docs\images",
    "docs\rtos",
    "docs\mcu",
    "docs\stm32f4\gpio",
    "docs\stm32f4\timer",
    "docs\stm32f4\adc",
    "docs\stm32f4\usart",
    "docs\stm32f4\i2c",
    "docs\stm32f4\spi",
    "docs\stm32f4\can",
    "docs\stm32f4\dma",
    "docs\fsm",
    "docs\pid",
    "docs\estimation",
    "docs\filtre",
    "docs\fft",
    "docs\dds",
    "docs\graphisme",
    "docs\projects\imu_compl",
    "docs\labos",
    "docs\ressources"
)

foreach ($folder in $folders) {
    $path = Join-Path $root $folder
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Créé : $path"
    } else {
        Write-Host "Existe déjà : $path"
    }
}

# Création des fichiers Markdown avec un titre
$files = @(
    "docs\index.md",
    "docs\404.md",
    "docs\rtos\index.md",
    "docs\mcu\index.md",
    "docs\stm32f4\gpio\index.md",
    "docs\stm32f4\timer\index.md",
    "docs\stm32f4\adc\index.md",
    "docs\stm32f4\usart\index.md",
    "docs\stm32f4\i2c\index.md",
    "docs\stm32f4\spi\index.md",
    "docs\stm32f4\can\index.md",
    "docs\stm32f4\dma\index.md",
    "docs\fsm\index.md",
    "docs\pid\index.md",
    "docs\estimation\index.md",
    "docs\filtre\index.md",
    "docs\fft\index.md",
    "docs\dds\index.md",
    "docs\graphisme\index.md",
    "docs\projects\imu_compl\index.md",
    "docs\labos\stabilisation1.md",
    "docs\labos\monitoringEsp8266.md",
    "docs\labos\fft1.md",
    "docs\ressources\installation.md",
    "docs\ressources\datasheets.md",
    "docs\ressources\rfm1.md",
    "docs\ressources\rfm2.md",
    "docs\ressources\freeRTOS.md",
    "docs\ressources\demarrerKiel.md",
    "docs\ressources\configRtosKiel.md",
    "docs\ressources\langageC.md"
)

foreach ($file in $files) {
    $path = Join-Path $root $file
    if (!(Test-Path $path)) {
        $title = (Get-Item $file).BaseName
        $content = "# $title`n`nContenu à rédiger..."
        Set-Content -Path $path -Value $content -Encoding UTF8
        Write-Host "Créé : $path"
    } else {
        Write-Host "Existe déjà : $path"
    }
}

# Création du favicon (fichier vide)
$favicon = Join-Path $root "docs\images\favicon.ico"
if (!(Test-Path $favicon)) {
    New-Item -ItemType File -Path $favicon -Force | Out-Null
    Write-Host "Créé : $favicon (vide)"
} else {
    Write-Host "Existe déjà : $favicon"
}

Write-Host "✅ Structure terminée."