#!/bin/sh
# Print WFMU transmitter status. Used as an SSH/login banner (installed as a
# dynamic MOTD by install_autostart.sh) and runnable by hand: ./wfmu-status.sh
set -eu

UNIT=/etc/systemd/system/si4713.service

# Derive the broadcast frequency + station from the installed unit's ExecStart
# so this banner always matches what the service actually tunes.
freq="91.1"
station="WFMU"
if [ -r "$UNIT" ]; then
  args="$(sed -n 's/^ExecStart=.*si4713_bringup\.sh \(.*\)$/\1/p' "$UNIT")"
  # shellcheck disable=SC2086
  set -- $args
  [ -n "${1:-}" ] && freq="$1"
  [ -n "${2:-}" ] && station="$2"
fi

tx="$(systemctl is-active si4713.service 2>/dev/null || echo unknown)"
au="$(systemctl is-active wfmu-audio.service 2>/dev/null || echo unknown)"

# Only draw the art if the window is wide enough (it's ~85 cols); otherwise it
# wraps and looks sheared, so suppress it and just show the status line.
cols="$(tput cols 2>/dev/null || echo 80)"
if [ "$cols" -ge 85 ] 2>/dev/null; then
  # Quoted heredoc: print the WFMU art verbatim, no shell expansion of * @ etc.
  cat <<'ART'
            **********************************= :***********************************                    
           :*       +      .    =            +* =*        +*:       -       +     +*                    
           -*.      +      :    =            +* =*.        *        -       +     +*                    
           -***     *:    =*  :***     **-   +* =**-               +**.    **=   +**                    
           -***=    -         ****       ****** =**-  .-      -    +**:    **=   +**                    
           -****:     -.     +****     ******** =**-  .*.    +-    ***:    **-   +**                    
           -*****    .*+    +***+       ******* =*      *   +:      -**.        :***                    
           :*****+===***+===*****=======******* =*======*+==*=======+****+-::-+*****                    
             ::::::::::::::::::::-****+::::::.    ::::::::-***+::::::::::::::::::::                     
                                   +***:                  -**:                                          
                                    =***.                 **                                            
                                     :**+                 +                                             
                                       +*=                @@                                            
                                        =*-             @@@@@@@@%%@@@@@%%##*++=::=*@@@@@#               
                      =:                 :*            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            
                       *-                  *          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
                        -=                  =        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
                         *+  :-.                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
                         -@@@@@@@@@@@@@@@@@@@@@@@#          #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%*           
                        @@@@@@@@@@@@@@@@@@@@@@@@@%.          .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-           
                       =@@@@#:*@@@@@@@@@@@=.                  :@@@@@@@@@@@@@@@@@@%*@@@=@@@@@-           
                       @@@# *@@+ @@@@@@@@@#:                   :@@@@@@@.               @@@@@#           
                     =@@-   +@-    @@.   .@                        @@@@#               %@:@@@           
                    @@     +@*     .@.   ++                        @@ @@               @@ @@:           
                   .@       :@+     =@                             @# +@               @% @#            
                   +@                :@@                           @+ +@:             @@ +@#            
                                                                 +@@  @@=            *#:.@@         
ART
fi

echo
if [ "$tx" = active ] && [ "$au" = active ]; then
  echo "  ON AIR — $station broadcasting on $freq MHz"
else
  echo "  OFF AIR — $station is NOT fully broadcasting on $freq MHz"
fi
echo "    transmitter (si4713.service):     $tx"
echo "    audio       (wfmu-audio.service): $au"
if [ "$tx" != active ] || [ "$au" != active ]; then
  echo "    diagnose: journalctl -u si4713.service -u wfmu-audio.service -b"
fi
echo
