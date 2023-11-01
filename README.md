# inotifycron
Setup watchers on filesystem paths, and execute custom scripts on the caught events. Uses inotifywait.


## Architecture
This solution uses [inotifywait](https://man7.org/linux/man-pages/man1/inotifywait.1.html), and sets up watchers on the paths as configured through the `watches.conf` configuration file. The `watch.sh` file parses the configuration file, sets up these watchers, and then pipes every event generated to all the event handlers parallelly.


## Syntax
There are two places that expect things in a specific order: The configuration file (`watches.conf`) and the handlers.

### watches.conf
This file specifies the filesystem paths to watch. Each line is a space-separated record formatted in the following format

    <Path> <Comma-separated list of events to monitor> <Comma-separated list of handler script file names>

Here is an example

    /tmp/ access,modify,attrib,close_write,close_nowrite,close,open,moved_to,moved_from,move,move_self,create,delete,delete_self,unmount handler1.sh

### The handlers
The handler scripts are invoked in the following format

    <handler.sh> --timestamp <Event timestamp> --events <Comma-separated list of filesystem events in a single event> --path <Filesystem path for which this event was raised>

An example for an invocation would be

    handler1.sh --timestamp 2023-11-01T08:07:07+0000 --events open,isdir --path /tmp/

All handler scripts need to be located within the `handlers` directory alongside the `watch.sh` script.


## watch.sh
This is the script that parses the configuration file, sets up the watchers, and can also stop the watchers. It supports three commands, namely: start, stop, and config-check.
You can supply a command to the script as the first and only argument, such as `./watch.sh config-check`, `./watch.sh start` or `./watch.sh stop`.
- **config-check**  
Checks the configuration files for configuration errors. Note that it does not check for the existence of the filesystem path which needs to be watched. This command only checks for the events configured and the existence of the handler scripts that have been configured. It generates an output in the following format:
    ```
    Configuration check:
    ├ Checking: /tmp/ access,modify,attrib,close_write,close_nowrite,close,open,moved_to,moved_from,move,move_self,create,delete,delete_self,unmount handler1.sh
    │ ├ Events to watch: [ OK ]
    │ └ Handlers: [ OK ]
    └ Config file OK.
    ```
- **start**  
This will start all the watchers. Note that this step also does a configuration check (checks that are part of the config-check command described above) and will only proceed to start if all the lines are ok. After starting all the watchers, the script will wait for the processes to finish. This is so that the service file can report back the status once it starts the service through this script.
- **stop**  
This will kill any inotifywait process on the system.


## Systemd Service
This utility is best used as a systemd service so that it can keep watching the files and its status can be monitored through operating system provided interfaces. To that extent, a .service file has also been provided. To start using it, do the following:
1. Copy the contents of this repository to a directory
2. Copy the location of the directory and update it in the .service file, specifically for the `ExecStart`, `ExecStop`, and `WorkingDirectory` fields.
3. Copy the .service file with `sudo cp inotifycron.service /etc/systemd/system/`
Once the above is done, you can use systemctl commands such as
    ```
    systemctl enable inotifycron # Have the service start as the operating system boots up
    systemctl start inotifycron # Start the watchers
    systemctl status inotifycron # Check if the script is running
    systemctl stop inotifycron # Stop all the watchers
    ```


## Typical Use Cases & Recommendations
This can be used to set up monitors on specific filesystem paths, and quickly trigger certain actions. A few examples can be
- Upload a file to a remote destination whenever they become available at a specific directory. Watch for `close_write,close` events for this.
- Send an email whenever a file with the json for the email arrives at a specific directory.
- Fix the SSH key privileges in ~/.ssh/ directories.

While inotifywait supports around 15 events, it is recommended that you run the script with a few custom events to see what kind of events you want to watch for. It would be also helpful to go through the [man page of inotifywait](https://man7.org/linux/man-pages/man1/inotifywait.1.html) which explains what the different events are.


## Things To Note
1. This utility uses [Linux pipes](https://man7.org/linux/man-pages/man7/pipe.7.html) to send the events up to the handlers. If the handlers do not consume events at the same, or better, speeds then this will hit the Linux pipe buffer size. You might need to increase the pipe buffer size to handle such scenarios.
2. This utility sets up watches in recursive mode, which means it will watch all paths under the paths mentioned in `watches.conf`. Be careful as you set this up to watch huge directories.
3. The number of watches that can be set up simultaneously is limited by a [few factors](https://www.baeldung.com/linux/inotify-upper-limit-reached), such as available memory and a few system configuration parameters. Make sure you are either operating under these limits, or tune them to your need.
