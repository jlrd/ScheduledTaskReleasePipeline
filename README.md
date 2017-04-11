# Knowing is Half the Battle

[The Release Pipeline Model](http://aka.ms/TheReleasePipelineModel) - Steven Murawski and Michael Greene 

[Hitchhikers Guide to the PowerShell Module Pipeline](https://xainey.github.io/2017/powershell-module-pipeline/) - Michael Willis 

# Scheduled Task Release Pipeline

PS1 (Git) > Jenkins (Pipeline Job) > Jenkins Agent (Scheduled Task)

## From

+ Scripts on file systems all over ...
+ Maybe script in TaskScheduler is in source control, maybe not ...
+ Have to go to many systems to find out whether scripts and tasks are working ...
+ What is the script output, is it logged to a file or event log, lots of variation, and some with no output ...

## To

+ Script files in source control, so are Jenkins instructions/orchestration (aka the Jenkinsfile)
+ Source control is THE single source of truth!
+ Jenkins can also send notifications on success or failure, lots of options; Email, Slack, HipChat, MS Teams, JIRA, etc Jenkins ecosystem is huge win here.
+ Output of script is nicely presented and preserved in Jenkins as long as needed, one central place! 
+ Success/Failure response plus accessible output drives the feeback and improvement lifecycle

# Git "The One Source of Truth To Rule Them All"

## Controler Code

PS1 files that consume first party, third party, or custom modules, i.e. ActiveDirectory, PowerCLI, and/or CustomCorpFoo. Script is mainly glue logic for work done by cmdlets.

+ Typically simple logic
+ Static logic, meat of the action is in the modules (you build your tools in modules and source control your modules right?)
+ However "Controller Code" scripts often have connection strings, URLs, or other potentially changeable and/or modifiable environment style variables. Small changes can hurt bad if lost or drifted by haphazard changes.

## Script Code

PS1 files that are monolithic in nature, contain all the logic and do all the things. 

+ Lots of unique logic, non-shared logic.
+ Lots of business logic, as processes change, logic may change. 

# Jenkins "The Butler"

Jenkins strength is around centralized automation. Traditionally traditionally that automation is in support of software development continuous integration (CI) and continous development (CD). The typical workflow is capture code from source control, test that code, build that code, produce an "artifact" (exe, msi, java jar or war, a zip file, "a thing" etc), intiate further testing, and lastly initiate a deployment to production. 

For ScheduledTasks that is a little different. While the "build" phase and the "testing" phase might be non-existant or truncated, the capturing code from source control, and deploy to production are still in effect. We therefore have a compressed, shhortened, or simplified pipeline. This scheduled task pipeline gets the benifits of keeping your scheduled task script code in Git but still facilitates having it reliabley executed when and where needed. Its the butler that shuttles your code from source control to production, and keeps track of all the intervening details.

## Jenkins Pipeline

This is achieved with Jenkins Pipeline functionality. There are two types of Jenkins Pipelines. Its very important to know this so when you are searching documenation or Googling for help you make sure you find the right solution to your need.

Scripted Pipline vs. Declaritive Pipeline

+ [Getting Started with Pipeline](https://jenkins.io/doc/book/pipeline/getting-started/)
+ [Declarative Pipeline Syntax](https://jenkins.io/doc/book/pipeline/syntax/)
+ [Pipeline Steps Reference](https://jenkins.io/doc/pipeline/steps/)

## Jenkinsfile

### Declaritive Examples

Most Basic

```
pipeline {
	agent { label 'ActiveDirectory' } 
	triggers { cron('*/5 * * * *') }   
	stages {
        stage('DoThatThing') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\DoThatThingWithProcesses.ps1'\""
            }
        }
    }
}
```

"Scheduled Task Native-ish"

```
pipeline {
	agent { label 'ActiveDirectory' } 
	triggers { cron('*/5 * * * *') }
    options { disableConcurrentBuilds()
              timeout(time: 1, unit: 'HOURS')
              retry(3)
              disableConcurrentBuilds() }   
	stages {
        stage('DoThatThing') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\DoThatThingWithProcesses.ps1'\""
            }
        }
    }
}
```

"Lifes a Stage"

```
pipeline {
	agent { label 'ActiveDirectory' } 
	triggers { cron('*/5 * * * *') }
    options { disableConcurrentBuilds()
              timeout(time: 1, unit: 'HOURS')
              retry(3) }   
	stages {
        stage('Get New Hire Info') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\NewHireInfo.ps1'\""
            }
        }
        stage('Create AD User') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\CreateADUser.ps1'\""
            }
        }
        stage('New Hire Email') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\NewHireEmail.ps1'\""
            }
        }
        stage('New Hire HomeDrive') {
            steps {
                bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"& '.\\NewHireHome.ps1'\""
            }
        }
    }
    post { 
        failure { 
            mail to:"ImportantPeople@example.com", subject:"FAILURE: New User Creation Job", body: "Uh oh, job failed."
            office365ConnectorSend message: "New User Creation FAILED", webhookUrl:'http://some.thing.something.microsoft.com/randomgook'
        }
        success { 
            office365ConnectorSend message: "New User Creation SUCCEEDED", webhookUrl:'http://some.thing.something.microsoft.com/randomgook'
        }
    }
}
```

# Jenkins Agent "The Scheduled Task"

## Create the Node(s)

1. Click "Manage Jenkins"
2. Click "Configure Global Security"
3. On "TCP port for JNLP agents", enable "Fixed" choose a high unused port on the host. I typically use 60123.
4. Click Save
5. Click "Manage Nodes"
6. Click "New Node"
    + Choose a Node Name, I usually go with <Hostname> (<InstanceName>) i.e. "MGMT01.contoso.com (ActiveDirectory)"
    + Choose "Permanent Agent"
    + Click "OK"
    + Enter "Remote Root Directory", this is the nodes working directory i.e. C:\Jenkins
    + Enter "Labels", space delimited. I typically use hostname and instance name "mgmt01 ActiveDirectory", case matters later.
    + Select "Usage" as "Only build jobs with label expressions matching this node"
    + Select "Launch Method" as "Launch Agent via Java Web Start"
7. Redo the "New Node" step as needed for various instances
8. Under "Manage Nodes" click into each unconnected "red X" node and record the following information.
    + jnlpUrl
    + secret
    + click and save the slave.jar link, you need the slave.jar later

## The Scheduled Task

### The Action

The action command line 

```
java.exe -jar C:\path\to\slave.jar -jnlpUrl xxxx -secret xyxyxy
```

### Trigger

Task Trigger "At Startup"

### Run As

The user the task run as is the user credentials that your script coming from Jenkins will use. Best practice for service accounts is principal of least privilige. 

### JenkinsAgentTaskSetup.ps1

```
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

$action = New-ScheduledTaskAction -Execute $("'{0}'" -f $Jvm) -Argument $arguments -WorkingDirectory $TaskWorkingDirectory

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
```

## Multiple tasks = labeled targeted instances

```
.\JenkinsAgentTaskSetup.ps1 -Jvm "C:\Program Files\Java\jre1.8.0_121\bin\java.exe" -JarFile "C:\JenkinsAgent\slave.jar" -JnlpUrl 'http://localhost:8080/computer/LocalHost%20(AD)/slave-agent.jnlp' -Secret '123456789012345678901234567890' -InstanceName 'ActiveDirectory' -UserName 'ADServiceAcct' -Password 'Password1' -TaskWorkingDirectory 'C:\Jenkins'
```

```
.\JenkinsAgentTaskSetup.ps1 -Jvm "C:\Program Files\Java\jre1.8.0_121\bin\java.exe" -JarFile "C:\JenkinsAgent\slave.jar" -JnlpUrl 'http://localhost:8080/computer/LocalHost%20(SQL)/slave-agent.jnlp' -Secret '098765432112345678901234567890' -InstanceName 'SQL' -UserName 'SQLServiceAcct' -Password 'Password1' -TaskWorkingDirectory 'C:\Jenkins'
```

You will create a Node and a Task for each "instance" (or user context) you will be running code in. The "Label" is the pointer you will use later to target your code at an Instance/User. Each Task instance can use the same slave.jar file, but each will need to have the unique Action parameters that point at the jnlpUrl and secret. You can have multiple instances use the same local "Remote Root Directory" as well. Each instance will create sub-directories as needed.

Need an AD context, setup a task with AD delegated service account with the appropriate permissions

+ In Jenkins Nodes, give this instance a "ActiveDirectory" label
+ In the Task, use the corresponding Nodes jnlpUrl and secret
+ Make sure to grant FullControl file system rights to the Task user on "Remote Root Directory" specified in the Node configuration, i.e. C:\Jenkins
+ Make sure to grant the service account the "Log on as a batch job" user right.

Need a SQL context, setup a task with SQL service account with appropriate rights and roles

+ In Jenkins Nodes, give this instance a "SQL" label
+ In the Task, use the corresponding Nodes jnlpUrl and secret
+ Make sure to grant FullControl file system rights to the Task user on "Remote Root Directory" specified in the Node configuration, i.e. C:\Jenkins
+ Make sure to grant the service account the "Log on as a batch job" user right.


# Tips

+ Understand PowerShell Terminating vs Non-terminating Errors; use ErrorAction Stop and throw when/where necessary.

# Contact

Joel Reed 
@AKAJoelReed
joelreed@outlook.com




