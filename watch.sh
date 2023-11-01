#!/bin/bash

# Exit if no argument has been supplied.
if [ $# -eq 0 ]; then
cat <<< EOF
No command supplied. Run the script like this
  script.sh COMMAND
where COMMAND is one of start, stop, or check-config.
EOF
exit 1
fi
# Assign the command in lowercase
COMMAND=${1,,}

cleanup() {
  # Clean up steps when shutting down watches
  echo "Stopping all inotifywait processes ..."
  # This will stop all inotifywait processes on the system
  sudo pkill inotifywait
  exit 0
}

# Setup a trap to catch these signals
trap 'cleanup' SIGINT SIGTERM SIGKILL

# Handle the stop command
if [[ $COMMAND == "stop" ]]; then
  cleanup
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Change the below line if you want to have a different config file name
CONF_FILE=$SCRIPT_DIR/watches.conf
# Change the below line if you want to have a different handlers directory
HANDLERS_DIR=$SCRIPT_DIR/handlers
# Below is the complete set of events supported by inotifywait: https://man7.org/linux/man-pages/man1/inotifywait.1.html
ALLOWED_EVENTS=( "access" "modify" "attrib" "close_write" "close_nowrite" "close" "open" "moved_to" "moved_from" "move" "move_self" "create" "delete" "delete_self" "unmount" )

if ! test -f $CONF_FILE; then
  echo "Configuration file expected at $CONF_FILE is missing."
  exit 1
fi

echo "Configuration check:"
all_ok=1
while IFS= read -r line; do
  echo "├ Checking: $line"
  IFS=' ' read -r path_to_watch events_and_scripts <<< "$line"
  IFS=',' read -a events <<< "${events_and_scripts% *}"
  IFS=',' read -a scripts <<< "${events_and_scripts#* }"

  unallowed_events=$(echo ${events[@]} ${ALLOWED_EVENTS[@]} ${ALLOWED_EVENTS[@]} | tr ' ' '\n' | sort | uniq -u | tr '\n' ',')
  # Check if any invalid events have been added
  if [ -z "$unallowed_events" ]; then
    echo "│ ├ Events to watch: [ OK ]"
  else
    all_ok=0
    echo "│ ├ Events to watch: [ Unknown events: ${unallowed_events} ]"
  fi

  missing_files=""
  for script in "${scripts[@]}"; do
    if [ ! -e "$HANDLERS_DIR/$script" ]; then
      if [ -n "$missing_files" ]; then
        missing_files="${missing_files}, $HANDLERS_DIR/$script"
      else
        missing_files="$HANDLERS_DIR/$script"
      fi
    fi
  done
  # Check if any invalid handlers have been added
  if [ -z "$missing_files" ]; then
    echo "│ └ Handlers: [ OK ]"
  else
    all_ok=0
    echo "│ └ Handlers: [ Missing handlers: ${missing_files} ]"
  fi
done < "$CONF_FILE"

if [[ $all_ok -eq 0 ]]; then
  echo "└ Correct the errors in $CONF_FILE."
  exit -1
else
  echo "└ Config file OK."
  if [[ "$COMMAND" == "config-check" ]]; then
    exit 0
  fi
fi

if [[ "$COMMAND" == "start" ]]; then
  echo -e "\nStarting watchers ..."
  while IFS= read -r line; do
    IFS=' ' read -r path_to_watch events_and_scripts <<< "$line"
    IFS=',' read -a events <<< "${events_and_scripts% *}"
    IFS=',' read -a scripts <<< "${events_and_scripts#* }"

    printf -v joined '%s,' "${events[@]}"
    eventsStr="${joined%,}"

    # Set the format of the event record, timestamp, and pipe the events.
    sudo inotifywait -rmqs --format "%T %e %w%f" --timefmt "%Y-%m-%dT%H:%M:%S%z" -e ${eventsStr} ${path_to_watch} | while read -r line; do
      for script in "${scripts[@]}"; do
        read -r timestamp events_fired event_path <<< "$line"

        # Invoking the handler scripts will also generate filesystem events, so filter those out
        if [[ $event_path != "$SCRIPT_DIR"* ]]; then
          command="${HANDLERS_DIR}/${script} --timestamp ${timestamp} --events ${events_fired,,} --path ${event_path}"
          $command &
        fi
        done
      done &
  done < "$CONF_FILE"
  echo "Started all. Waiting for watchers to quit ..."
  # Wait for all started inotifywait processes to quit
  wait
fi
