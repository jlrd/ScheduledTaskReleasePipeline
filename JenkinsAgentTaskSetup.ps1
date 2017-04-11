param (
    [string]$Jvm,
    [string]$JarFile,
    [string]$JnlpUrl,
    [string]$Secret,
    [string]$InstanceName,
    [string]$UserName,
    [string]$Password,
    [string]$TaskWorkingDirectory
)

$arguments = "-jar $($JarFile) -jnlpUrl $($JnlpUrl) -secret $($Secret)"

$workingDir = 'C:\ProgramData\Glynlyon\Jenkins'

$action = New-ScheduledTaskAction -Execute $("""{0}""" -f $Jvm) -Argument $arguments -WorkingDirectory $TaskWorkingDirectory

$trigger =  New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet -Compatibility 'Win8'

$TaskParameters = @{'Action' = $action;
                    'Trigger' = $trigger;
                    'TaskName' = "Jenkins-JNLP-SlaveAgent ($InstanceName)";
                    'Description' = 'Jenkins Java JNLP Slave Agent "On Startup" task';
                    'RunLevel' = 'Highest';
                    'Settings' = $settings;
                    'User' = $UserName;
                    'Password' = $Password
                   }

Register-ScheduledTask @TaskParameters