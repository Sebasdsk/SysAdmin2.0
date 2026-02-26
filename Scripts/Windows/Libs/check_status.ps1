Write-Host "Bienvenido! $env:COMPUTERNAME"

Write-Host "Direccion IP actual:"
Get-NetIPAddress 

Write-Host "Espacio en el disco:"
Get-PSDrive 