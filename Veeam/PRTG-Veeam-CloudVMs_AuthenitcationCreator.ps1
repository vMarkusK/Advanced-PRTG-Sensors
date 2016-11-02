[String] $User		= "My\User"
[String] $Password	= "Passw0rd!"	
Write-Host "Basic String: " $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($user):$($password)")))