# Compila o APK sem Gradle: aapt2 + javac + d8 + apksigner.
# Requer: JDK 17 e Android SDK (platforms;android-35, build-tools;35.0.0).
#   $env:JAVA_HOME e $env:ANDROID_HOME apontando para eles.
param([string]$Out = "$PSScriptRoot\build")
$ErrorActionPreference = 'Stop'
$bt = "$env:ANDROID_HOME\build-tools\35.0.0"
$jar = "$env:ANDROID_HOME\platforms\android-35\android.jar"
$java = "$env:JAVA_HOME\bin"

Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Out\gen", "$Out\classes", "$Out\dex" | Out-Null

& "$bt\aapt2.exe" compile --dir "$PSScriptRoot\res" -o "$Out\res.zip"
& "$bt\aapt2.exe" link -I $jar --manifest "$PSScriptRoot\AndroidManifest.xml" -o "$Out\base.apk" "$Out\res.zip" `
    --java "$Out\gen" --min-sdk-version 31 --target-sdk-version 35 --version-code 1 --version-name 1.0.0
if ($LASTEXITCODE) { throw 'aapt2 link falhou' }

$src = Get-ChildItem "$PSScriptRoot\src", "$Out\gen" -Recurse -Filter *.java | ForEach-Object FullName
& "$java\javac.exe" --release 17 -encoding UTF-8 -classpath $jar -d "$Out\classes" -Xlint:-options @src
if ($LASTEXITCODE) { throw 'javac falhou' }

$cls = Get-ChildItem "$Out\classes" -Recurse -Filter *.class | ForEach-Object FullName
& "$bt\d8.bat" --lib $jar --min-api 31 --output "$Out\dex" @cls
if ($LASTEXITCODE) { throw 'd8 falhou' }

Copy-Item "$Out\base.apk" "$Out\unsigned.apk"
Push-Location "$Out\dex"; & "$java\jar.exe" uf "$Out\unsigned.apk" classes.dex; Pop-Location
& "$bt\zipalign.exe" -f -p 4 "$Out\unsigned.apk" "$Out\aligned.apk"

$ks = "$PSScriptRoot\debug.keystore"
if (-not (Test-Path $ks)) {
    & "$java\keytool.exe" -genkeypair -keystore $ks -storepass android -keypass android -alias logisync `
        -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=LogiSync" | Out-Null
}
& "$bt\apksigner.bat" sign --ks $ks --ks-pass pass:android --out "$Out\LogiSync.apk" "$Out\aligned.apk"
if ($LASTEXITCODE) { throw 'apksigner falhou' }
Write-Host "OK: $Out\LogiSync.apk"
