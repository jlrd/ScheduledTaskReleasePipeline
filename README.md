# Knowing is Half the Battle

[The Release Pipeline Model](http://aka.ms/TheReleasePipelineModel) - Steven Murawski and Michael Greene 

[Hitchhikers Guide to the PowerShell Module Pipeline](https://xainey.github.io/2017/powershell-module-pipeline/) - Michael Willis 

# Scheduled Task Release Pipeline

PS1 (Git) > Jenkins (Pipeline Job) > Jenkins Agent (Scheduled Task)

I'm a proponent of the release pipelines of all shapes, sizes, and make-ups. They are process automation implementations that take input, typically a "source of truth", such as code or config from source code management and resulting in some production output. Using structured, repeatable, and robust processes.

My use of Jenkins is slightly off what I think the mainstream use is. My "slaves" aka (Agents) are not "building" anything but they are facilitating something. That something is delivering my up to the minute "scheduled task" code to a location where it can be successfully executed. It is also driven more by schedule then by a code change. Typically that is targeted to a Agent instance that is running with credentials that will allow code to do what it needs.

In my Scheduled Task consolidation project there many dozen of scheduled tasks running on many dozens of servers. After consolidation I had about a half dozen management hosts running all scheduled tasks that are delivered and executed code sourced from Git. Each of those management hosts has 2 or 3 agent instances.

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
+ Success/Failure response plus accessible output drives the feedback and improvement life cycle

# Git "The One Source of Truth To Rule Them All"

There were two types of code that represented the existing scheduled task code that I was migrating into this effort.

## Controller Code

PS1 files that consume first party, third party, or custom modules, i.e. ActiveDirectory, PowerCLI, and/or CustomCorpFoo. Script is mainly glue logic for work done by cmdlets.

+ Typically simple logic
+ Static logic, meat of the action is in the modules
+ However "Controller Code" scripts often had connection strings, URLs, or other potentially changeable and/or modifiable environment style variables. Small changes can hurt bad if lost or drifted by haphazard changes.

## Script Code

PS1 files that are monolithic in nature, contain all the logic and do all the things. 

+ Lots of unique logic, non-shared logic.
+ Lots of business logic, as processes change, logic may change. 

# Jenkins "The Butler"

Jenkins strength is around centralized automation. Traditionally that automation is in support of software development continuous integration (CI) and continuous development (CD). The typical workflow is capture code from source control, test that code, build that code, produce an "artifact" (exe, msi, java jar or war, a zip file, "a thing" etc), initiate further testing, and lastly initiate a deployment to production. 

For ScheduledTasks that is a little different. While the "build" phase and the "testing" phase might be non-existent or truncated, the capturing code from source control, and deploy to production are still in effect. We therefore have a compressed, shortened, or simplified pipeline. This scheduled task pipeline gets the benefits of keeping your scheduled task script code in Git but still facilitates having it reliably executed when and where needed. Its the butler that shuttles your code from source control to production, and keeps track of all the intervening details.

## Jenkins Pipeline

This is achieved with Jenkins Pipeline functionality. There are two types of Jenkins Pipelines. Its very important to know this so when you are searching documentation or Googling for help you make sure you find the right solution to your need.

Scripted Pipeline vs. Declaritive Pipeline

+ [Getting Started with Pipeline](https://jenkins.io/doc/book/pipeline/getting-started/)
+ [Declarative Pipeline Syntax](https://jenkins.io/doc/book/pipeline/syntax/)
+ [Pipeline Steps Reference](https://jenkins.io/doc/pipeline/steps/)

## Jenkinsfile

### Declaritive Examples

https://github.com/jlrd/ScheduledTaskReleasePipeline

## Jenkins Pipeline Job

1. Click "New Item"
2. Enter a name
3. Choose "Pipeline Job"
4. Click Ok
5. Select from Pipeline definition "Pipeline Script from SCM"
6. Select your SCM, i.e. Git 
    + If you are using alternate source code manager you may need to install the appropriate Jenkins plugin. For example to get TFS or Mercurial to appear in the drop down menu.
7. Enter the repository URL, i.e. clone url
    + If your repo needs credentials you will need to add and select them.
    + If there are not "red alerts" it means Jenkins could connect
8. [Optional] Add additional behaviors; "Wipe out repo and force clone"
    + Scheduled Task pipelines are usually small repos. I like piece of mind that I'm getting the latest bits on each run. Your mileage and thought process may vary.


# Jenkins Agent "The Scheduled Task"

Using an "On Startup" Scheduled Task to run the Jenkins Agent has some advantages over using the msi install, or other methods. One of my concerns with Jenkins is while it stores credentials in Jenkins master credential store as encrypted, it shuttles the username **and password** to the agent in clear text. It also makes the password available to your code via a clear text environment variable. To avoid this I put the credentials in the "run as" portion of the Task Scheduler, and as such it is stored in the Windows Credential Store, it never leaves the server. While not infalliable it seemed a better tradeoff. Additionally you can then run additional instances of the Agent scheduled task, each with its own credential context. Then you can target the instance from your Jenkinsfile with agent/node labels.

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

The user the task run as is the user credentials that your script coming from Jenkins will use. Best practice for service accounts is principal of least privilege. 

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

https://github.com/jlrd/ScheduledTaskReleasePipeline


