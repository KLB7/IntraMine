####################################################
# 32-bit-Test.ps1
# Created: 03/20/2013
# Author: me
# Summary: This script will test if Powershell is 
#          running in 32-bit mode and if true
#          launch itself in 64-bit mode for completion
####################################################
 
########################################################################################################
#If Powershell is running the 32-bit version on a 64-bit machine, we need to force powershell to run in
#64-bit mode to allow the OleDb access to function properly.
########################################################################################################
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    write-warning "Y'arg Matey, we're off to 64-bit land....."
    if ($myInvocation.Line) {
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile $myInvocation.Line
    }else{
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile -file "$($myInvocation.InvocationName)" $args
    }
exit $lastexitcode
} else {
	write-warning "You are there already"
}
 
 
write-host "Main script body"
 
################
# END
################