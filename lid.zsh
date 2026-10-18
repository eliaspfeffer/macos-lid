# Toggle system sleep when the lid is closed.
lid() {
  local state
  state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')

  if [[ "${state:-0}" == "1" ]]; then
    if sudo pmset disablesleep 0; then
      state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')
      if [[ "${state:-0}" != "1" ]]; then
        printf '\n\033[1;30;42m %-68s \033[0m\n\n' \
          "GREEN — NORMAL MODE: Closing the lid puts your Mac to sleep."
      else
        echo "Error: macOS still reports SleepDisabled 1."
        return 1
      fi
    else
      return 1
    fi
  else
    if sudo pmset disablesleep 1; then
      state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')
      if [[ "$state" == "1" ]]; then
        printf '\n\033[1;37;41m %-68s \033[0m\n' \
          "RED — STAY-AWAKE MODE: Your Mac stays awake with the lid closed."
        printf '\033[1;37;41m %-68s \033[0m\n\n' \
          "Do NOT use in a bag — keep your Mac well ventilated!"
      else
        echo "Error: macOS did not confirm stay-awake mode."
        return 1
      fi
    else
      return 1
    fi
  fi
}
