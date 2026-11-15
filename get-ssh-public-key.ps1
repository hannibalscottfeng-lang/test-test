$ErrorActionPreference = 'Stop'

$sshDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
$privateKey = Join-Path $sshDir 'id_ed25519'
$publicKey = "$privateKey.pub"
$keyPattern = '^ssh-ed25519[ \t]+[A-Za-z0-9+/]{68}(?:[ \t]+[^\r\n]*)?\z'

if (-not (Test-Path -LiteralPath $publicKey)) {
    $keygen = Get-Command ssh-keygen.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $keygen) {
        throw 'ssh-keygen.exe was not found. Enable the Windows OpenSSH Client and try again.'
    }

    [void][IO.Directory]::CreateDirectory($sshDir)
    $lockPath = Join-Path $sshDir '.id_ed25519.lock'
    $keyLock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    try {
        if (-not (Test-Path -LiteralPath $publicKey)) {
            if (Test-Path -LiteralPath $privateKey) {
                $recoveredKey = & $keygen.Source -y -f $privateKey
                if ($LASTEXITCODE -ne 0 -or $recoveredKey -cnotmatch $keyPattern) {
                    throw "Could not recover an Ed25519 public key from $privateKey."
                }
                New-Item -ItemType File -Path $publicKey -Value "$recoveredKey`n" | Out-Null
            } else {
                $keygenArgs = @('-q', '-t', 'ed25519', '-N', '""', '-f', ('"{0}"' -f $privateKey))
                $process = Start-Process -FilePath $keygen.Source -ArgumentList $keygenArgs `
                    -NoNewWindow -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw "OpenSSH could not generate a key at $privateKey."
                }
            }
        }
    } finally {
        $keyLock.Dispose()
    }
}

$keyLine = ([string](Get-Content -LiteralPath $publicKey -Encoding UTF8 -Raw)).TrimEnd([char[]]"`r`n")
if ($keyLine -cnotmatch $keyPattern) {
    throw "Expected one Ed25519 public key line in $publicKey."
}
if (-not (Test-Path -LiteralPath $privateKey -PathType Leaf)) {
    Write-Warning "The public key exists, but the matching default private key is missing at $privateKey."
}
$keyLine
