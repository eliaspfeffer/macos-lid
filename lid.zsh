# Toggle system sleep when the lid is closed.
lid() {
  local state
  state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')

  if [[ "${state:-0}" == "1" ]]; then
    if sudo pmset disablesleep 0; then
      state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')
      if [[ "${state:-0}" != "1" ]]; then
        printf '\n\033[1;30;42m %-68s \033[0m\n\n' \
          "GRÜN — NORMALMODUS: Zuklappen versetzt den Mac in den Ruhezustand."
      else
        echo "Fehler: macOS meldet weiterhin SleepDisabled 1."
        return 1
      fi
    fi
  else
    if sudo pmset disablesleep 1; then
      state=$(pmset -g | awk '$1 == "SleepDisabled" { print $2; exit }')
      if [[ "$state" == "1" ]]; then
        printf '\n\033[1;37;41m %-68s \033[0m\n' \
          "ROT — WACHMODUS: Der Mac bleibt beim Zuklappen eingeschaltet."
        printf '\033[1;37;41m %-68s \033[0m\n\n' \
          "NICHT im Rucksack betreiben — für freie Belüftung sorgen!"
      else
        echo "Fehler: macOS hat den Wachmodus nicht bestätigt."
        return 1
      fi
    fi
  fi
}
