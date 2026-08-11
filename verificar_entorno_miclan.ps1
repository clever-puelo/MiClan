<#
==============================================================================
 verificar_entorno_miclan.ps1
------------------------------------------------------------------------------
 Verifica y (cuando es seguro) repara el entorno de desarrollo para MiClan
 en Windows 11: Flutter, Android SDK, Node.js, Firebase CLI, FlutterFire CLI,
 y la configuración específica del proyecto (google-services.json,
 firebase_options.dart, .firebaserc, applicationId, dependencias).

 CÓMO USARLO:
   1) Copiá este archivo a la raíz del proyecto MiClan (donde está pubspec.yaml).
   2) Abrí PowerShell en esa carpeta.
   3) Si nunca corriste scripts en esta PC, una sola vez:
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   4) Ejecutá:
        .\verificar_entorno_miclan.ps1

 Al final vas a tener en pantalla (y en un .txt en la misma carpeta) un
 resumen con [OK] / [AVISO] / [ERROR] y, para cada problema, o bien lo
 arregla solo (cosas seguras: pub get, npm install, aceptar licencias
 Android) o te dice EXACTAMENTE qué comando correr o qué click dar.
==============================================================================
#>

[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [bool]$AutoFix = $true
)

$ErrorActionPreference = 'Continue'
$script:okCount = 0
$script:warnCount = 0
$script:errCount = 0
$script:fixedCount = 0
$logLines = New-Object System.Collections.Generic.List[string]

function Write-Section($title) {
    Write-Host ""
    Write-Host "==== $title ====" -ForegroundColor Cyan
    $logLines.Add("")
    $logLines.Add("==== $title ====")
}
function Write-Ok($msg) {
    Write-Host "  [OK]    $msg" -ForegroundColor Green
    $script:okCount++
    $logLines.Add("[OK] $msg")
}
function Write-Warn($msg) {
    Write-Host "  [AVISO] $msg" -ForegroundColor Yellow
    $script:warnCount++
    $logLines.Add("[AVISO] $msg")
}
function Write-Err($msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
    $script:errCount++
    $logLines.Add("[ERROR] $msg")
}
function Write-Fixed($msg) {
    Write-Host "  [ARREGLADO] $msg" -ForegroundColor Magenta
    $script:fixedCount++
    $logLines.Add("[ARREGLADO] $msg")
}
function Write-Step($msg) {
    Write-Host "          -> $msg" -ForegroundColor DarkYellow
    $logLines.Add("    -> $msg")
}
function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}
function Get-CmdVersion($name, $args) {
    try { return (& $name $args 2>&1 | Select-Object -First 1) } catch { return $null }
}

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " Verificacion de entorno - MiClan (Windows 11)" -ForegroundColor Cyan
Write-Host " Carpeta del proyecto: $ProjectPath" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# ==========================================================================
# 0) Confirmar que estamos parados en la raiz del proyecto correcto
# ==========================================================================
Write-Section "0. Ubicacion del proyecto"
$pubspecPath = Join-Path $ProjectPath "pubspec.yaml"
$isProjectRoot = $false
if (Test-Path $pubspecPath) {
    $pubspecContent = Get-Content $pubspecPath -Raw
    if ($pubspecContent -match "(?m)^name:\s*miclan") {
        Write-Ok "pubspec.yaml encontrado y corresponde al proyecto 'miclan'."
        $isProjectRoot = $true
    } else {
        Write-Warn "Hay un pubspec.yaml pero no dice 'name: miclan'. Revisa que sea la carpeta correcta."
    }
} else {
    Write-Err "No se encontro pubspec.yaml en '$ProjectPath'."
    Write-Step "Corre este script desde la raiz del proyecto (la carpeta que contiene pubspec.yaml), o pasa la ruta con -ProjectPath 'C:\ruta\a\MiClan'."
}

# ==========================================================================
# 1) Git
# ==========================================================================
Write-Section "1. Git"
if (Test-Cmd git) {
    Write-Ok "Git instalado: $(Get-CmdVersion git '--version')"
} else {
    Write-Err "Git no esta instalado o no esta en el PATH."
    Write-Step "Descargalo de https://git-scm.com/download/win e instalalo con las opciones por defecto."
}

# ==========================================================================
# 2) Flutter + flutter doctor
# ==========================================================================
Write-Section "2. Flutter SDK"
$flutterOk = $false
if (Test-Cmd flutter) {
    $flutterOk = $true
    Write-Ok "Flutter encontrado en PATH: $(Get-CmdVersion flutter '--version')"

    Write-Host "  Corriendo 'flutter doctor -v' (puede tardar un momento)..." -ForegroundColor DarkGray
    $doctorOutput = & flutter doctor -v 2>&1 | Out-String
    $logLines.Add("--- flutter doctor -v ---")
    $logLines.Add($doctorOutput)

    if ($doctorOutput -match "\[.\] Flutter") {
        Write-Ok "flutter doctor corrio correctamente."
    }

    # Licencias de Android no aceptadas
    if ($doctorOutput -match "Android licenses not accepted" -or $doctorOutput -match "some licenses.*not accepted") {
        Write-Warn "Hay licencias del Android SDK sin aceptar."
        if ($AutoFix -and (Test-Cmd flutter)) {
            Write-Step "Intentando aceptar licencias automaticamente (equivale a responder 'y' a cada una)..."
            try {
                $yesBlock = ("y`n" * 40)
                $yesBlock | & flutter doctor --android-licenses 2>&1 | Out-Null
                $recheck = & flutter doctor -v 2>&1 | Out-String
                if ($recheck -notmatch "Android licenses not accepted" -and $recheck -notmatch "some licenses.*not accepted") {
                    Write-Fixed "Licencias del Android SDK aceptadas."
                } else {
                    Write-Warn "No se pudieron aceptar todas las licencias automaticamente."
                    Write-Step "Corre manualmente: flutter doctor --android-licenses  (y aceptar con 'y' cada una)."
                }
            } catch {
                Write-Warn "Fallo el intento automatico de aceptar licencias."
                Write-Step "Corre manualmente: flutter doctor --android-licenses"
            }
        } else {
            Write-Step "Corre: flutter doctor --android-licenses"
        }
    }

    # Android toolchain / cmdline-tools faltantes
    if ($doctorOutput -match "cmdline-tools component is missing") {
        Write-Err "Faltan los 'Android SDK Command-line Tools'."
        Write-Step "Android Studio -> More Actions -> SDK Manager -> pestana 'SDK Tools' -> marcar 'Android SDK Command-line Tools (latest)' -> Apply."
    }
    if ($doctorOutput -match "Unable to locate Android SDK" -or $doctorOutput -match "cannot find the Android SDK") {
        Write-Err "Flutter no encuentra el Android SDK."
        Write-Step "Abri Android Studio -> Settings -> Languages & Frameworks -> Android SDK, copia la ruta de 'Android SDK Location'."
        Write-Step "Despues corre: flutter config --android-sdk `"C:\ruta\que\copiaste`""
    }

    # Visual Studio / Windows toolchain (no es necesario para MiClan, solo Android)
    if ($doctorOutput -match "\[.\].*Visual Studio") {
        Write-Ok "(informativo) Toolchain de Windows detectado por flutter doctor - no hace falta para MiClan (solo Android)."
    }

    # Chequeo puntual de un dispositivo conectado
    if ($doctorOutput -match "No devices? (available|connected)" -or $doctorOutput -notmatch "\u2022.*android") {
        Write-Warn "No parece haber ningun dispositivo/emulador Android detectado en este momento."
        Write-Step "Conecta el telefono por USB con 'Depuracion USB' activada, o abri un emulador desde Android Studio (Device Manager), y despues corre: flutter devices"
    } else {
        Write-Ok "flutter doctor detecto al menos un dispositivo/emulador."
    }

} else {
    Write-Err "Flutter no esta instalado o no esta en el PATH."
    Write-Step "Descarga el SDK stable de https://docs.flutter.dev/get-started/install/windows"
    Write-Step "Descomprimilo (ej: C:\src\flutter) y agrega 'C:\src\flutter\bin' al PATH (Variables de entorno del sistema)."
    Write-Step "Cerra y volve a abrir PowerShell despues de tocar el PATH."
}

# ==========================================================================
# 3) Editores: VS Code / Android Studio + extensiones Flutter/Dart
# ==========================================================================
Write-Section "3. Editores y plugins"
if (Test-Cmd code) {
    Write-Ok "VS Code encontrado en PATH."
    try {
        $extensions = & code --list-extensions 2>&1
        if ($extensions -match "Dart-Code\.flutter") {
            Write-Ok "Extension 'Flutter' de VS Code instalada."
        } else {
            Write-Warn "No se detecto la extension 'Flutter' en VS Code."
            Write-Step "En VS Code: Ctrl+Shift+X, busca 'Flutter' (Dart-Code), instalala (trae Dart de yapa)."
        }
    } catch {
        Write-Warn "No se pudo consultar la lista de extensiones de VS Code."
    }
} else {
    Write-Warn "El comando 'code' no esta en el PATH (VS Code puede estar instalado igual, pero sin el CLI habilitado)."
    Write-Step "En VS Code: Ctrl+Shift+P -> 'Shell Command: Install code command in PATH'."
}

$androidStudioPaths = @(
    "$env:LOCALAPPDATA\Programs\Android Studio",
    "C:\Program Files\Android\Android Studio"
)
$androidStudioFound = $androidStudioPaths | Where-Object { Test-Path $_ }
if ($androidStudioFound) {
    Write-Ok "Android Studio detectado en: $($androidStudioFound -join ', ')"
} else {
    Write-Warn "No se encontro Android Studio en las rutas usuales."
    Write-Step "Si ya lo instalaste en otra ruta, ignora este aviso. Si no, bajalo de https://developer.android.com/studio"
}

# ==========================================================================
# 4) Node.js y npm
# ==========================================================================
Write-Section "4. Node.js / npm"
$nodeVersion = $null
if (Test-Cmd node) {
    $nodeVersion = (& node --version).Trim()
    Write-Ok "Node.js instalado: $nodeVersion"
} else {
    Write-Err "Node.js no esta instalado o no esta en el PATH."
    Write-Step "Instalalo desde https://nodejs.org (version LTS)."
}
if (Test-Cmd npm) {
    Write-Ok "npm instalado: $(Get-CmdVersion npm '--version')"
} else {
    Write-Err "npm no esta disponible (deberia venir con Node.js)."
}

# ==========================================================================
# 5) Firebase CLI
# ==========================================================================
Write-Section "5. Firebase CLI"
$firebaseOk = $false
if (Test-Cmd firebase) {
    $firebaseOk = $true
    Write-Ok "Firebase CLI instalada: $(Get-CmdVersion firebase '--version')"

    try {
        $loginList = & firebase login:list 2>&1 | Out-String
        if ($loginList -match "No authorized accounts" -or $loginList -match "Error") {
            Write-Warn "No hay ninguna cuenta logueada en Firebase CLI."
            Write-Step "Corre: firebase login   (se abre el navegador para loguearte con la cuenta que tiene acceso al proyecto MiClan)."
        } else {
            Write-Ok "Firebase CLI tiene al menos una cuenta logueada."
            $logLines.Add($loginList)
        }
    } catch {
        Write-Warn "No se pudo verificar el estado de login de Firebase CLI."
    }
} else {
    Write-Err "Firebase CLI no esta instalada."
    if ($AutoFix -and (Test-Cmd npm)) {
        Write-Step "Instalando Firebase CLI globalmente con npm (npm install -g firebase-tools)..."
        try {
            & npm install -g firebase-tools 2>&1 | Out-Null
            if (Test-Cmd firebase) {
                Write-Fixed "Firebase CLI instalada correctamente."
                $firebaseOk = $true
            } else {
                Write-Warn "Se instalo pero el comando 'firebase' no aparece en el PATH todavia. Cerra y reabri la terminal."
            }
        } catch {
            Write-Warn "Fallo la instalacion automatica."
            Write-Step "Instalala manualmente: npm install -g firebase-tools"
        }
    } else {
        Write-Step "Instalala con: npm install -g firebase-tools"
    }
}

# ==========================================================================
# 6) FlutterFire CLI
# ==========================================================================
Write-Section "6. FlutterFire CLI"
if (Test-Cmd flutterfire) {
    Write-Ok "FlutterFire CLI encontrada en PATH."
} else {
    Write-Warn "FlutterFire CLI no esta en el PATH (o no esta instalada)."
    if ($AutoFix -and $flutterOk) {
        Write-Step "Instalando FlutterFire CLI (dart pub global activate flutterfire_cli)..."
        try {
            & dart pub global activate flutterfire_cli 2>&1 | Out-Null
            if (Test-Cmd flutterfire) {
                Write-Fixed "FlutterFire CLI instalada."
            } else {
                Write-Warn "Se instalo pero 'flutterfire' no se reconoce todavia como comando."
                Write-Step "Agrega '%APPDATA%\Pub\Cache\bin' al PATH del sistema y reabri la terminal."
            }
        } catch {
            Write-Warn "Fallo la instalacion automatica de FlutterFire CLI."
            Write-Step "Corre manualmente: dart pub global activate flutterfire_cli"
        }
    } else {
        Write-Step "Corre: dart pub global activate flutterfire_cli"
        Write-Step "Si despues 'flutterfire' no se reconoce, agrega '%APPDATA%\Pub\Cache\bin' al PATH."
    }
}

# ==========================================================================
# 7) google-services.json: presencia, JSON valido, y consistencia cruzada
#    con .firebaserc / firebase_options.dart / applicationId (Gradle)
# ==========================================================================
Write-Section "7. Configuracion de Firebase del proyecto"

$googleServicesPath = Join-Path $ProjectPath "android\app\google-services.json"
$firebaseRcPath      = Join-Path $ProjectPath ".firebaserc"
$firebaseOptionsPath = Join-Path $ProjectPath "lib\firebase_options.dart"
$gradleKtsPath        = Join-Path $ProjectPath "android\app\build.gradle.kts"
$gradleGroovyPath     = Join-Path $ProjectPath "android\app\build.gradle"

$gsProjectId = $null
$gsPackageName = $null

if (Test-Path $googleServicesPath) {
    Write-Ok "google-services.json encontrado en android\app\"
    try {
        $gsJson = Get-Content $googleServicesPath -Raw | ConvertFrom-Json
        $gsProjectId = $gsJson.project_info.project_id
        $gsPackageName = $gsJson.client[0].client_info.android_client_info.package_name
        if ($gsProjectId -and $gsPackageName) {
            Write-Ok "JSON valido. project_id='$gsProjectId', package_name='$gsPackageName'."
        } else {
            Write-Err "google-services.json es JSON valido pero le faltan campos esperados (project_id / package_name)."
            Write-Step "Volve a descargarlo desde Firebase Console -> Configuracion del proyecto -> tus apps -> app Android -> 'google-services.json'."
        }
    } catch {
        Write-Err "google-services.json existe pero no es JSON valido (archivo corrupto o descarga incompleta)."
        Write-Step "Volve a descargarlo desde Firebase Console y reemplaza el archivo en android\app\google-services.json"
    }
} else {
    Write-Err "Falta android\app\google-services.json (este archivo NO se versiona en git, hay que agregarlo a mano en cada PC nueva)."
    Write-Step "Opcion A (recomendada): con 'firebase login' ya hecho, corre 'flutterfire configure' desde la raiz del proyecto y elegi el proyecto 'miclan-6dd12' (o el que corresponda) y la plataforma Android."
    Write-Step "Opcion B: en Firebase Console -> Configuracion del proyecto -> tus apps -> app Android -> boton 'google-services.json', descargalo y copialo a android\app\google-services.json"
}

$rcProjectId = $null
if (Test-Path $firebaseRcPath) {
    try {
        $rcJson = Get-Content $firebaseRcPath -Raw | ConvertFrom-Json
        $rcProjectId = $rcJson.projects.default
        if ($rcProjectId) {
            Write-Ok ".firebaserc encontrado, proyecto por defecto: '$rcProjectId'."
        } else {
            Write-Warn ".firebaserc existe pero no tiene 'projects.default' definido."
        }
    } catch {
        Write-Warn ".firebaserc existe pero no se pudo leer como JSON."
    }
} else {
    Write-Warn "No se encontro .firebaserc en la raiz del proyecto."
    Write-Step "Corre 'firebase use --add' desde la raiz del proyecto y elegi el proyecto correcto para generarlo."
}

$foProjectId = $null
if (Test-Path $firebaseOptionsPath) {
    $foContent = Get-Content $firebaseOptionsPath -Raw
    $foMatch = [regex]::Match($foContent, "android[\s\S]*?projectId:\s*'([^']+)'")
    if ($foMatch.Success) {
        $foProjectId = $foMatch.Groups[1].Value
        Write-Ok "lib\firebase_options.dart encontrado, projectId (Android) = '$foProjectId'."
    } else {
        Write-Warn "lib\firebase_options.dart existe pero no se pudo extraer el projectId de Android (puede ser el placeholder generado por FlutterFire sin configurar)."
    }
} else {
    Write-Err "Falta lib\firebase_options.dart."
    Write-Step "Corre 'flutterfire configure' desde la raiz del proyecto para generarlo (junto con google-services.json)."
}

$gradleApplicationId = $null
$gradleFileUsed = $null
if (Test-Path $gradleKtsPath) { $gradleFileUsed = $gradleKtsPath }
elseif (Test-Path $gradleGroovyPath) { $gradleFileUsed = $gradleGroovyPath }
if ($gradleFileUsed) {
    $gradleContent = Get-Content $gradleFileUsed -Raw
    $gradleMatch = [regex]::Match($gradleContent, 'applicationId\s*=?\s*"([^"]+)"')
    if ($gradleMatch.Success) {
        $gradleApplicationId = $gradleMatch.Groups[1].Value
        Write-Ok "applicationId en Gradle: '$gradleApplicationId'."
    } else {
        Write-Warn "No se pudo leer 'applicationId' desde $($gradleFileUsed | Split-Path -Leaf)."
    }
} else {
    Write-Err "No se encontro android\app\build.gradle(.kts)."
}

# --- Cruces de consistencia (la parte que mas suele fallar) -----------------
if ($gsProjectId -and $rcProjectId -and $gsProjectId -ne $rcProjectId) {
    Write-Err "DESAJUSTE: el project_id de google-services.json ('$gsProjectId') no coincide con el de .firebaserc ('$rcProjectId')."
    Write-Step "Es senal de que google-services.json es de OTRO proyecto de Firebase. Volve a bajarlo del proyecto correcto ('$rcProjectId') en Firebase Console, o corre 'flutterfire configure' y elegi ese proyecto."
}
if ($gsProjectId -and $foProjectId -and $gsProjectId -ne $foProjectId) {
    Write-Err "DESAJUSTE: el project_id de google-services.json ('$gsProjectId') no coincide con el de firebase_options.dart ('$foProjectId')."
    Write-Step "Volve a correr 'flutterfire configure' para regenerar ambos archivos de forma consistente, apuntando al mismo proyecto."
}
if ($gsPackageName -and $gradleApplicationId -and $gsPackageName -ne $gradleApplicationId) {
    Write-Err "DESAJUSTE CRITICO: package_name de google-services.json ('$gsPackageName') no coincide con applicationId de Gradle ('$gradleApplicationId')."
    Write-Step "Este desajuste causa el error tipico 'No matching client found for package name'. Corre 'flutterfire configure' de nuevo eligiendo bien la app Android (com.agiletask.miclan), o edita applicationId en build.gradle.kts para que coincida."
}
if ($gsProjectId -and $rcProjectId -and $gsProjectId -eq $rcProjectId -and $foProjectId -and $gsProjectId -eq $foProjectId -and $gsPackageName -eq $gradleApplicationId) {
    Write-Ok "Todos los identificadores de Firebase (project_id, package_name) coinciden entre google-services.json, .firebaserc, firebase_options.dart y Gradle."
}

# ==========================================================================
# 8) Dependencias del proyecto Flutter (pub get)
# ==========================================================================
Write-Section "8. Dependencias Flutter (pubspec)"
$dartToolPath = Join-Path $ProjectPath ".dart_tool"
$pubspecLockPath = Join-Path $ProjectPath "pubspec.lock"
if ($isProjectRoot) {
    if ((Test-Path $dartToolPath) -and (Test-Path $pubspecLockPath)) {
        Write-Ok "Dependencias de Flutter ya resueltas (.dart_tool y pubspec.lock presentes)."
        if ($AutoFix -and $flutterOk) {
            Write-Step "Corriendo 'flutter pub get' de todas formas, para asegurar que esten al dia..."
            Push-Location $ProjectPath
            & flutter pub get 2>&1 | Out-Null
            Pop-Location
            Write-Fixed "flutter pub get ejecutado."
        }
    } else {
        Write-Warn "No se detectaron las dependencias resueltas todavia."
        if ($AutoFix -and $flutterOk) {
            Write-Step "Corriendo 'flutter pub get'..."
            Push-Location $ProjectPath
            & flutter pub get 2>&1 | Out-Null
            Pop-Location
            if (Test-Path $pubspecLockPath) {
                Write-Fixed "Dependencias instaladas con flutter pub get."
            } else {
                Write-Err "flutter pub get no genero pubspec.lock. Revisa el mensaje de error corriendolo manualmente."
            }
        } else {
            Write-Step "Corre: flutter pub get"
        }
    }
} else {
    Write-Warn "Salteado (no se confirmo que esta parado en la raiz del proyecto - ver seccion 0)."
}

# ==========================================================================
# 9) Cloud Functions (Node 20 + npm install)
# ==========================================================================
Write-Section "9. Cloud Functions"
$functionsPath = Join-Path $ProjectPath "miclan-functions\functions"
if (Test-Path $functionsPath) {
    Write-Ok "Carpeta de Cloud Functions encontrada."

    $pkgJsonPath = Join-Path $functionsPath "package.json"
    if (Test-Path $pkgJsonPath) {
        $pkgJson = Get-Content $pkgJsonPath -Raw | ConvertFrom-Json
        $requiredNode = $pkgJson.engines.node
        if ($requiredNode -and $nodeVersion) {
            $nodeMajor = ($nodeVersion.TrimStart('v')).Split('.')[0]
            if ($nodeMajor -eq $requiredNode) {
                Write-Ok "Version de Node ($nodeVersion) coincide con la requerida por las functions (Node $requiredNode)."
            } else {
                Write-Warn "Tu Node.js es $nodeVersion pero las Cloud Functions piden Node $requiredNode puntual."
                Write-Step "No es bloqueante para desarrollar/deployar (Firebase usa el runtime de Node $requiredNode en la nube igual), pero si queres emular localmente sin sorpresas: instala nvm-windows (https://github.com/coreybutler/nvm-windows) y corre 'nvm install $requiredNode' + 'nvm use $requiredNode' solo quedandote en esa carpeta."
            }
        }
    }

    $nodeModulesPath = Join-Path $functionsPath "node_modules"
    if (Test-Path $nodeModulesPath) {
        Write-Ok "Dependencias de Cloud Functions ya instaladas (node_modules presente)."
    } else {
        Write-Warn "Faltan las dependencias de Cloud Functions (node_modules no existe)."
        if ($AutoFix -and (Test-Cmd npm)) {
            Write-Step "Corriendo 'npm install' dentro de miclan-functions\functions..."
            Push-Location $functionsPath
            & npm install 2>&1 | Out-Null
            Pop-Location
            if (Test-Path $nodeModulesPath) {
                Write-Fixed "Dependencias de Cloud Functions instaladas."
            } else {
                Write-Err "npm install no genero node_modules. Corre a mano dentro de miclan-functions\functions y revisa el error."
            }
        } else {
            Write-Step "Corre: cd miclan-functions\functions ; npm install"
        }
    }
} else {
    Write-Warn "No se encontro la carpeta miclan-functions\functions en esta ubicacion."
}

# ==========================================================================
# 10) Firestore rules / indexes presentes (deploy pendiente, no lo hace el script)
# ==========================================================================
Write-Section "10. Reglas e indices de Firestore"
$rulesPath = Join-Path $ProjectPath "firestore.rules"
$indexesPath = Join-Path $ProjectPath "firestore.indexes.json"
if (Test-Path $rulesPath) {
    Write-Ok "firestore.rules encontrado localmente."
} else {
    Write-Warn "No se encontro firestore.rules en la raiz del proyecto."
}
if (Test-Path $indexesPath) {
    Write-Ok "firestore.indexes.json encontrado localmente."
} else {
    Write-Warn "No se encontro firestore.indexes.json."
}
Write-Host "  (Este script NO hace deploy solo. Si tocaste las reglas, recorda: firebase deploy --only firestore:rules)" -ForegroundColor DarkGray

# ==========================================================================
# RESUMEN FINAL
# ==========================================================================
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " RESUMEN" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  OK:         $script:okCount" -ForegroundColor Green
Write-Host "  Avisos:     $script:warnCount" -ForegroundColor Yellow
Write-Host "  Errores:    $script:errCount" -ForegroundColor Red
Write-Host "  Arreglados: $script:fixedCount automaticamente" -ForegroundColor Magenta

if ($script:errCount -eq 0 -and $script:warnCount -eq 0) {
    Write-Host ""
    Write-Host "  Entorno OK. Deberias poder compilar con: flutter run" -ForegroundColor Green
} elseif ($script:errCount -eq 0) {
    Write-Host ""
    Write-Host "  Sin errores bloqueantes, pero revisa los avisos [AVISO] de arriba." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  Hay errores que necesitan tu accion manual (ver pasos '->' de arriba)." -ForegroundColor Red
}

$logPath = Join-Path $ProjectPath ("verificacion_miclan_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
$logLines | Out-File -FilePath $logPath -Encoding UTF8
Write-Host ""
Write-Host "  Reporte completo guardado en: $logPath" -ForegroundColor DarkGray
Write-Host "  (mandamelo si algo no queda claro y seguimos desde ahi)" -ForegroundColor DarkGray
