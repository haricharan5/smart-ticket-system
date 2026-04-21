# Run on VM4 (Windows Server 2022) as Administrator
# Sets up Active Directory Domain Services for the smart ticket system

# Install AD DS role
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote to Domain Controller
$securePassword = ConvertTo-SecureString "Ticket@2024Secure!" -AsPlainText -Force
Install-ADDSForest `
    -DomainName "ticket.local" `
    -DomainNetbiosName "TICKET" `
    -SafeModeAdministratorPassword $securePassword `
    -InstallDns `
    -Force

# After reboot, create OUs and groups
# Run this section AFTER the server reboots as DC

Import-Module ActiveDirectory

# Organizational Units
New-ADOrganizationalUnit -Name "SupportTeams" -Path "DC=ticket,DC=local"
New-ADOrganizationalUnit -Name "Agents" -Path "OU=SupportTeams,DC=ticket,DC=local"
New-ADOrganizationalUnit -Name "TeamLeads" -Path "OU=SupportTeams,DC=ticket,DC=local"
New-ADOrganizationalUnit -Name "Managers" -Path "OU=SupportTeams,DC=ticket,DC=local"

# Security Groups (map to ticket categories)
$groups = @(
    "Technical-Support-Team",
    "Billing-Finance-Team",
    "Customer-Success-Team",
    "HR-People-Team",
    "General-Operations-Team",
    "Support-Team-Leads",
    "Operations-Managers"
)
foreach ($group in $groups) {
    New-ADGroup -Name $group -GroupScope Global -Path "OU=SupportTeams,DC=ticket,DC=local"
}

# Sample users
$users = @(
    @{Name="John Smith"; Sam="jsmith"; Group="Technical-Support-Team"; OU="Agents"},
    @{Name="Sarah Jones"; Sam="sjones"; Group="Billing-Finance-Team"; OU="Agents"},
    @{Name="Mike Patel"; Sam="mpatel"; Group="Technical-Support-Team"; OU="Agents"},
    @{Name="Emily Chen"; Sam="echen"; Group="Customer-Success-Team"; OU="Agents"},
    @{Name="David Brown"; Sam="dbrown"; Group="Support-Team-Leads"; OU="TeamLeads"},
    @{Name="Lisa Wilson"; Sam="lwilson"; Group="Operations-Managers"; OU="Managers"}
)

$pass = ConvertTo-SecureString "Welcome@2024!" -AsPlainText -Force
foreach ($u in $users) {
    New-ADUser `
        -Name $u.Name `
        -SamAccountName $u.Sam `
        -UserPrincipalName "$($u.Sam)@ticket.local" `
        -AccountPassword $pass `
        -Enabled $true `
        -Path "OU=$($u.OU),OU=SupportTeams,DC=ticket,DC=local"
    Add-ADGroupMember -Identity $u.Group -Members $u.Sam
}

Write-Host "✅ Active Directory setup complete."
Write-Host "Domain: ticket.local"
Write-Host "Users created: $($users.Count)"
Write-Host "Groups created: $($groups.Count)"
