# Nice Updater
A tool to update macOS that (nicely) gives the user several chances to install updates prior to a forced installation and restart (if required).

This fork removes the requirement for the Yo.app and uses the `jamfHelper` tool instead. Functionality is otherwise identical.

## Requirements
### Jamf Pro Requirements
*Note: There are no Jamf Pro policies required in order for this tool to function (if yo.app is installed). However, I use Jamf Pro to manage Macs. Consequently, I've created this minimally leveraging Jamf Pro. You could easily adapt this for use in other environments.*
- jamfHelper is used to display the user dialogs when updates are being installed.
- The Jamf Binary is used to reboot the Mac (if required).

## Build the Project into a .PKG
To build new versions you can simply run the build.sh script and specify a version number for the .pkg. The resulting .pkg will include the LaunchDaemons and target script as well as necessary preinstall/postinstall scripts. If you do not include a version number as a parameter then version 1.0 will be assigned as the default.
```
$ git clone https://github.com/ryangball/nice-updater.git
$ cd nice-updater
$ ./build.sh 1.5
Version set to 1.5
Building the .pkg in /Users/ryangball/nice-updater/build/
Revealing Nice_Updater_1.5.pkg in Finder
```

## Testing
If you [build](https://github.com/ryangball/nice-updater#build-the-project-into-a-pkg) the .pkg or download one of the [releases](https://github.com/ryangball/nice-updater/releases), after installation you can start the LaunchDaemon to begin:
```
sudo launchctl start com.github.ryangball.nice_updater
```
Tail the log to see the current state:
```
tail -f /Library/Logs/Nice_Updater.log
```
You can do this several times to see the entire alerting/force-update workflow.

## Workflow and Options
The nice_updater.sh script is not intended to be executed by simply running the script. It is intended to be executed by passing a parameter into it indicating which function to run. If you do not specify a function, then the script just exits. As an example the primary LaunchDaemon executes the script in this fashion: `bash /Library/Scripts/nice_updater main`. "Main" indicates the function that is being run.

The primary LaunchDaemon is scheduled to be run every 24 hours (86400 seconds). What happens when it runs is determined by a few things:

### When a User is Not Logged In
- Updates are downloaded, applied immediately, and the Mac is restarted (if required).
- If a restart *is* required and a user logs into the Mac while updates are being applied, the user is notified that updates are being applied and the Mac will be restarted.

### When a User is Logged In
- Updates are downloaded, and if no restart is required the updates are installed immediately in the background.
- If a restart *is* required the user will be alerted via a jamfHelper dialog. The user can choose to cancel the alert, or install the restart-required updates now and the Mac will restart afterward.
- The default number of alerts before a forced install of the restart-required updates is 10, this can be changed for your environment. When using this default value a single user gets alerted 10 times (once every day) and has the option to install at any of those points, if they do not, one day after the last alert the update will be applied and the Mac will restart. The user is will also receive a jamfHelper dialog when the updates are being applied letting them know their machine will restart soon.
- The alert logic tracks which users are alerted, so it will only forcibly install those restart-required updates if the same user is alerted 3 times (when using the default value) **or** of course if a user is not logged in.

### Delay Running After Full Update
By default, after a full update has been performed (all updates available are installed), updates will not be checked again until 14 days have passed. You can specify the number of days to delay if you'd like to change this value.

### Delay Running After No Updates Available
You can also specify the number of days to delay the process after an update check occurs where no updates were found (default is 3). This delay will ensure that we are not checking for updates all day long if there are no updates found in the morning. This is also a good way to stagger updates out over your entire fleet.

### Blocking Updates
If you want to block updates from running during a certain period, you can write a "updates_blocked" key with a boolean value of "true" to the main preference file (/Library/Preferences/com.github.ryangball.nice_updater.plist).
```
defaults write /Library/Preferences/com.github.ryangball.nice_updater.plist updates_blocked -bool true
```
To reverse this setting simply set the key value to false or delete the key.

## Alert Logic
A user is only alerted when updates are pending that require a restart. If a user is being alerted, they will receive a **persistent** Notification Center alert, which they can dismiss. By default a single user can be alerted 3 times before they will receive a jamfHelper message indicating that updates are in progress and the Mac will restart soon. The built-in alert logic tracks which users receive the alerts. In multi-user environments, this is very important because if you simply alert whichever user is logged in at that moment then count those alerts up, you might have a situation where a specific user is only alerted once or not at all before restart-required updates are force-installed.

### Alert Examples
The alert indicates that updates requiring a restart are pending.
![img-1](images/first_alert.png)

The second to the last alert lets the user know that they will receive one more alert prior to force-installing updates and restarting.
![img-2](images/second_alert.png)

In the final alert that the user receives, they will be warned to "Install now to avoid interruptions".
![img-3](images/third_alert.png)


Once the user has received their final alert and they do not choose to install, the updates will be force-installed and this message will be displayed. This is also the message the user will receive if they select the "Install Now" button from any of the above alerts.

![img-3](images/updates_in_progress_message.png)

## What's With Two LaunchDaemons?
When a user is alerted via one of the persistent Notification Center alerts, the user has the option to install updates now. This is done through the yo.app action button, which in this case is the "Install Now" button. These actions are performed as the user, meaning that actions which require root permissions could not be performed when a standard user is clicking the "Install Now" button.

To address this issue, when the user is alerted a random key string is generated and stored. This key is then simultaneously written to the main preference file and to the command that gets executed if and when the user clicks the "Install Now" button. Once the user clicks the "Install Now" button, that key is then written to a second preference file and used later in the process. I call this second preference file the "trigger".

The second LaunchDaemon (com.github.ryangball.nice_updater_on_demand) runs the on_demand function of the script. This LaunchDaemon is configured with a "WatchPaths" key, and is set to execute the LaunchDaemon when the trigger file is modified in any way. Because the user has access to modify this trigger file at any time (if they know where to look) a mechanism was put in place to validate that the LaunchDaemon should in fact be running. Since the update key was stored in the main preference file, we can compare it with the key that will be written to the trigger file, and if they match the update process will continue. If the keys don't match, meaning the trigger file was modified by the user without clicking the "Install Now" button, the process will exit without action. This allows us to avoid potentially updating the system when a user inadvertently modifies the trigger file.
