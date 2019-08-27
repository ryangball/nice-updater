# Nice Updater
A tool to update macOS that (nicely) gives the user several chances to install updates prior to a forced installation and restart (if required).

This fork removes the requirement for the Yo.app and uses the `jamfHelper` tool instead. Additional configuration opportunities have also been added.

## Requirements
### Jamf Pro Requirements
- `jamfHelper` is used to display the user dialogs when updates are required or are being installed.
- The Jamf Binary is used to reboot the Mac (if required).

## Build the Project into a .PKG
To build new versions you can simply run the `./build.sh` script and specify a version number for the `.pkg`. The resulting `.pkg` will include the LaunchDaemons and target script as well as necessary preinstall/postinstall scripts. If you do not include a version number as a parameter then the current tag will be assigned as the default.

You can customise the settings of the script within `build.sh`. For instance, you can change the default time between script runs, and you can change the identifier of the preferences files.

```bash
git clone https://github.com/grahampugh/nice-updater.git
cd nice-updater
# (edit build.sh to suit your settings)
./build.sh 1.7
```

## Testing
If you [build](https://github.com/ryangball/nice-updater#build-the-project-into-a-pkg) the .pkg or download one of the [releases](https://github.com/grahampugh/nice-updater/releases), after installation the Launch Daemon is automatically started.

Tail the log to see the current state:
```bash
tail -f /Library/Logs/Nice_Updater.log
```
You can do this several times to see the entire alerting/force-update workflow.

## Workflow and Options
The `nice_updater.sh` script is not intended to be executed by simply running the script. It is intended to be executed by passing a parameter into it indicating which function to run. If you do not specify a function, then the script just exits. As an example the primary LaunchDaemon executes the script in this fashion: `/bin/bash /Library/Scripts/nice_updater main`. "Main" indicates the function that is being run.

Default settings are set in `build.sh`. This script overwrites the contents of the LaunchDaemons and Preferences file when run.

### Overriding parameters with a Jamf postinstall script

The settings can also be overridden using a Jamf script, for example as a postinstall script in the policy that installs the nice updater. A working postinstall script is provided in this repo named `jamf_postinstall_script_for_nice_updater.sh`. The overridable parameters are as follows:

| Parameter | Description | Default |
|:---------:|:------------|:-------:|
| 4 | Start interval - hour of the day, e.g. 13 = 1pm. If left blank, the policy would run every hour. | 13 |
| 5 | Start interval - minute of the hour, e.g. 45 = 45 mins past the hour, e.g. 13:45 | 0 |
| 6 | Alert timeout in seconds. The time that the alert should stay on the screen (should be less than the start interval) | 3590 |
| 7 | Max number of deferrals. Default is 11 so first message says "10 remaining alerts". | 11 |
| 8 | Number of days to wait after an empty software update run | 3 |
| 9 | Number of days to wait after a full software update is carried out | 14 |
| 10 | Custom icon path - must exist on the device before the policy is run. Empty by default, so that the standard "Software updates" icon is used. | - |

The primary LaunchDaemon is therefore scheduled to be run at 13:00 every day, but overridable. What happens when it runs is determined by a few things:

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
If you want to block updates from running during a certain period, you can write a "updates_blocked" key with a boolean value of "true" to the main preference file (/Library/Preferences/com.github.grahampugh.nice_updater.plist).

```bash
defaults write /Library/Preferences/com.github.grahampugh.nice_updater.plist updates_blocked -bool true
```

To reverse this setting simply set the key value to false or delete the key.

## Alert Logic
A user is only alerted when updates are pending that require a restart. If a user is being alerted, they will receive a **persistent** Notification Center alert, which they can dismiss. By default a single user can be alerted 10 times before they will receive a jamfHelper message indicating that updates are in progress and the Mac will restart soon. The built-in alert logic tracks which users receive the alerts. In multi-user environments, this is very important because if you simply alert whichever user is logged in at that moment then count those alerts up, you might have a situation where a specific user is only alerted once or not at all before restart-required updates are force-installed.

### Alert Examples
The alert indicates that updates requiring a restart are pending. It will timeout after the specified time in the `AlertTimeout` preferences key. If it times out, the remaining alerts stays unchanged. If Cancel is pressed, one remaining alert is taken away.
![img-1](images/first_alert.png)

The second to the last alert lets the user know that they will receive one more alert prior to force-installing updates and restarting.
![img-2](images/second_alert.png)

In the final alert that the user receives, they will be warned to "Install now to avoid interruptions". This alert cannot be cancelled, and has a pre-set duration of 5 minutes (not overridable).
![img-3](images/third_alert.png)


Once the user has received their final alert and they do not choose to install, the updates will be force-installed and this message will be displayed. This is also the message the user will receive if they select the "Install Now" button from any of the above alerts.

![img-3](images/updates_in_progress_message.png)

After a full update is carried out, the remaining alerts is reset, and updates will not be checked for 14 days.

## What's with the two LaunchDaemons?
When a user is alerted via one of the jamfHelper alerts, the user has the option to install updates now. This is done through the jamfHelper default action button, which in this case is the "Install Now" button. These actions are performed as the user, meaning that actions which require root permissions could not be performed when a standard user is clicking the "Install Now" button.

To address this issue, when the user is alerted a random key string is generated and stored. This key is then simultaneously written to the main preference file and to the command that gets executed if and when the user clicks the "Install Now" button. Once the user clicks the "Install Now" button, that key is then written to a second preference file and used later in the process. I call this second preference file the "trigger".

The second LaunchDaemon (`com.github.grahampugh.nice_updater_on_demand`) runs the on_demand function of the script. This LaunchDaemon is configured with a "WatchPaths" key, and is set to execute the LaunchDaemon when the trigger file is modified in any way. Because the user has access to modify this trigger file at any time (if they know where to look) a mechanism was put in place to validate that the LaunchDaemon should in fact be running. Since the update key was stored in the main preference file, we can compare it with the key that will be written to the trigger file, and if they match the update process will continue. If the keys don't match, meaning the trigger file was modified by the user without clicking the "Install Now" button, the process will exit without action. This allows us to avoid potentially updating the system when a user inadvertently modifies the trigger file.

## Uninstaller
An uninstall script named `nice_updater_uninstall.sh` is provided here, which removes the preferences and scripts, and unloads and deletes the LaunchDaemons. This could be used in an Uninstaller policy in Jamf Pro.
