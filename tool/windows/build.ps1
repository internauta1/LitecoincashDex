param(
  [ValidateSet('Production','Validation')][string]$Mode='Production',
  [string]$KdfFile,
  [string]$KdfUrl,
  [string]$NativeDependencyCache,
  [switch]$Offline
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $env:OS -or $env:OS -ne 'Windows_NT'){throw 'This release build supports Windows only'}
if($KdfFile -and $KdfUrl){throw 'Select one explicit KDF source'}
$oldOffline=$env:LCC_NEXT_OFFLINE_BUILD
$oldFirebaseCache=$env:LCC_NEXT_FIREBASE_SDK_DIR
Push-Location $root
try {
  $output=Join-Path $root 'build/windows/x64/runner/Release'
  $otherEngine=if($Mode -eq 'Validation'){'mm2_lccnext_8762.exe'}else{'mm2_lccnext_isolated.exe'}
  if(Test-Path -LiteralPath (Join-Path $output $otherEngine)){
    throw 'Artifacts for the other mode are present. Preserve them and use a separate clean checkout.'
  }
  $running=@(Get-CimInstance Win32_Process -Property ExecutablePath | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($output+'\',[StringComparison]::OrdinalIgnoreCase)
  })
  if($running.Count){throw 'Build output is in use; do not rebuild a running wallet or engine'}
  $env:FLUTTER_SUPPRESS_ANALYTICS='true';$env:CI='true'
  $flutter=Get-Command flutter -ErrorAction Stop
  $version=(& $flutter.Source --version --machine | Out-String | ConvertFrom-Json)
  if($version.flutterVersion -cne '3.41.4'){throw 'Flutter 3.41.4 is required'}
  & python (Join-Path $PSScriptRoot 'verify_sources.py')
  if($LASTEXITCODE -ne 0){throw 'Vendored SDK source verification failed'}
  if($KdfFile){& python (Join-Path $PSScriptRoot 'prepare_kdf.py') --file $KdfFile}
  elseif($KdfUrl){& python (Join-Path $PSScriptRoot 'prepare_kdf.py') --url $KdfUrl}
  else{& python (Join-Path $PSScriptRoot 'prepare_kdf.py')}
  if($LASTEXITCODE -ne 0){throw 'Exact approved KDF must be provisioned before building'}
  $lock=Join-Path $root 'pubspec.lock';$before=(Get-FileHash $lock).Hash
  $arguments=@('pub','get','--enforce-lockfile');if($Offline){$arguments+='--offline'}
  & $flutter.Source @arguments
  if($LASTEXITCODE -ne 0 -or (Get-FileHash $lock).Hash -cne $before){throw 'Locked dependency resolution failed'}
  if($Offline){
    if(-not $NativeDependencyCache){throw 'Offline builds require an explicit native dependency cache'}
    $cache=(Resolve-Path -LiteralPath $NativeDependencyCache).Path
    $build=Join-Path $root 'build/windows/x64'
    $null=New-Item -ItemType Directory -Path (Join-Path $build 'packages') -Force
    foreach($name in @('Microsoft.Web.WebView2','Microsoft.Windows.CppWinRT.2.0.220418.1',
      'Microsoft.Windows.ImplementationLibrary','Microsoft.Windows.ImplementationLibrary.1.0.220201.1','nlohmann.json')){
      $cachedPackage=Join-Path $cache ('packages/'+$name);$output=Join-Path $build ('packages/'+$name)
      if(-not(Test-Path -LiteralPath $cachedPackage -PathType Container)){throw "Missing native dependency: $name"}
      if(-not(Test-Path -LiteralPath $output)){Copy-Item -LiteralPath $cachedPackage -Destination $output -Recurse}
    }
    # Native SDK dependency cache only: CMake reads headers/libraries in place.
    # Never copy a previous wallet build or any application DLL/AOT output.
    $env:LCC_NEXT_FIREBASE_SDK_DIR=Join-Path $cache 'extracted/firebase_cpp_sdk_windows'
    if(-not(Test-Path -LiteralPath $env:LCC_NEXT_FIREBASE_SDK_DIR -PathType Container)){
      throw 'Firebase 12.7.0 native dependency cache missing'
    }
    $env:LCC_NEXT_OFFLINE_BUILD='1'
  }else{$env:LCC_NEXT_OFFLINE_BUILD=$null}
  $arguments=@('build','windows','--release','--no-pub',
    '--dart-define=LCC_NEXT_WINDOWS_8762=true','--dart-define=GEO_BLOCK=disabled')
  if($Mode -eq 'Validation'){
    $arguments+=@('--target=lib/main_isolated.dart','--dart-define=LCC_NEXT_ISOLATED=true',
      '--dart-define=LCC_NEXT_WALLET_ONLY_TEST=true','--dart-define=LCC_NEXT_FULL_TEST=false',
      '--dart-define=LCC_NEXT_LEGACY_KDF_TEST=true','--dart-define=LCC_NEXT_TEST_RPC_PORT=17993',
      '--dart-define=LCC_NEXT_SSE_DIAGNOSTICS=true',
      '--dart-define=LCC_NEXT_TEST_ROOT=E:\codex\LitecoinCashDEX-Next\.isolated-testing\mission-20261103')
  }else{$arguments+='--target=lib/main.dart'}
  & $flutter.Source @arguments
  if($LASTEXITCODE -ne 0){throw 'Windows Release compilation failed'}
  & python (Join-Path $PSScriptRoot 'verify_sources.py')
  if($LASTEXITCODE -ne 0){throw 'Build changed the reviewed SDK/static assets'}
  $output=Join-Path $root 'build/windows/x64/runner/Release'
  $engine=if($Mode -eq 'Validation'){'mm2_lccnext_isolated.exe'}else{'mm2_lccnext_8762.exe'}
  if((Get-FileHash (Join-Path $output $engine)).Hash -cne 'E752B26C8208111DA9AA2F4A1AF61CA0ED818C5BF65E745C1DB21ACF5C34B6D8'){
    throw 'Packaged KDF mismatch'
  }
  [pscustomobject]@{mode=$Mode;netid=8762;rpc=$(if($Mode -eq 'Validation'){17993}else{17883});
    guiStarted=$false;kdfStarted=$false;output=$output} | ConvertTo-Json
}finally{$env:LCC_NEXT_OFFLINE_BUILD=$oldOffline;$env:LCC_NEXT_FIREBASE_SDK_DIR=$oldFirebaseCache;Pop-Location}
