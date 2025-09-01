# day2.ps1  — Entra ID user+group + RBAC on RG
Set-StrictMode -Version Latest

# ======= الإعدادات (عدّلها) =======
$SubscriptionId = "4e837a18-8964-4cd7-bcdf-4553a4ce3814"
$TenantId       = ""   # اتركه فارغًا إن كنت داخل Cloud Shell الصحيح
$UserUPN        = "Lab-Shell-User1@ihabsahdgmail784.onmicrosoft.com"
$UserDisplay    = "Lab-Shell-User1"
$UserPassword   = "PowerSellP@assw0rd"   # للتجربة فقط
$GroupName      = "Lab-Shell-Contributors"
$ResourceGroup  = "RG-Bash_Lab01"
$RoleName       = "Contributor"
# ===================================

# 0) اتصال وسياق
if ($TenantId) { Connect-AzAccount -Tenant $TenantId | Out-Null }
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null

# 1) إنشاء المستخدم (إن لم يوجد)
$u = Get-AzADUser -UserPrincipalName $UserUPN -ErrorAction SilentlyContinue
if (-not $u) {
  $secPwd = ConvertTo-SecureString $UserPassword -AsPlainText -Force
  $u = New-AzADUser -DisplayName $UserDisplay -UserPrincipalName $UserUPN -MailNickname $UserDisplay `
        -Password $secPwd -AccountEnabled:$true -ForceChangePasswordNextLogin:$true
}

# 2) إنشاء المجموعة (إن لم توجد)
$g = Get-AzADGroup -DisplayName $GroupName -ErrorAction SilentlyContinue
if (-not $g) {
  $g = New-AzADGroup -DisplayName $GroupName -MailNickname $GroupName
}

# 3) إضافة المستخدم للمجموعة (إن لم يكن عضوًا)
$member = Get-AzADGroupMember -GroupObjectId $g.Id -ErrorAction SilentlyContinue |
          Where-Object { $_.UserPrincipalName -eq $UserUPN }
if (-not $member) {
  Add-AzADGroupMember -TargetGroupObjectId $g.Id -MemberUserPrincipalName $UserUPN
}

# 4) تعيين دور RBAC على مستوى الـ RG
$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
$hasRole = Get-AzRoleAssignment -ObjectId $g.Id -Scope $scope -ErrorAction SilentlyContinue |
           Where-Object { $_.RoleDefinitionName -eq $RoleName }
if (-not $hasRole) {
  New-AzRoleAssignment -ObjectId $g.Id -PrincipalType Group -RoleDefinitionName $RoleName -Scope $scope
}

# 5) تحقّق سريع
Get-AzRoleAssignment -Scope $scope |
  Where-Object { $_.ObjectId -eq $g.Id } |
  Select-Object PrincipalName, RoleDefinitionName, Scope
