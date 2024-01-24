git#!/bin/bash

move_sink_inputs() {
    sink="$1"
    [ -n "$sink" ] || return 1

    sink_inputs=$(pactl list sink-inputs) || return 1

    while read -r sink_input; do
        index=$(echo "$sink_input" | grep -oP "\d+$")
        pactl move-sink-input "$index" "$sink" || return 1
    done < <(echo "$sink_inputs" | grep "Sink Input")
}

list_sinks() {
    raw_sinks=$(pactl list sinks short) || return 1
    echo "$raw_sinks"
}

select_sink() {
    # raw_sinks =
    # 0	alsa_output.pci-0000_01_00.1.hdmi-stereo	module-alsa-card.c	s16le 2ch 44100Hz	SUSPENDED
    # 1 alsa_output.pci-0000_00_1b.0.analog-stereo	module-alsa-card.c	s16le 2ch 44100Hz	RUNNING
    raw_sinks=$(list_sinks)
    sinks=""
    while IFS= read -r line; do #read in raw sink line
        # Split sink line by \t
        IFS=$'\t' read -ra line_elements <<< "$line"
        # Split sink identifier by dot (.)
        IFS=$'.' read -ra description_elements <<< "${line_elements[1]}"
        # Get sink number and description (e.g. "analog-stereo")
        sinks+="${line_elements[0]} ${description_elements[3]}\n"
    done <<< "$raw_sinks"
    
    sink="$(echo -e "$sinks" | rofi -dmenu -dpi 1 -config "~/.config/rofi/powermenu.rasi" \
        -p "Select Audio Source")" || return 1
    sink="$(echo "$sink" | cut -f 1 -d " ")"
    [ -n "$sink" ] || return 1

    pactl set-default-sink $sink || return 1
    move_sink_inputs $sink || return 1
}

case "$1" in
	list) list_sinks || exit 1;;
    current);;
	*) select_sink || exit 1;;
esac

exit 0