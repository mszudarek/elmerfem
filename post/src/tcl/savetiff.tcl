#*******************************************************************************
#*
#*       ELMER, A Computational Fluid Dynamics Program.
#*
#*       Copyright 1st April 1995 - , CSC - IT Center for Science Ltd.,
#*                                    Finland.
#*
#*       All rights reserved. No part of this program may be used,
#*       reproduced or transmitted in any form or by any means
#*       without the written permission of CSC.
#*
#*******************************************************************************

#*******************************************************************************
#*
#*    TIFF save utility routines
#*
#*******************************************************************************
#*
#*                     Author:       Mikko Lyly
#*
#*                    Address: CSC - IT Center for Science Ltd.
#*                                Keilaranta 14, P.O. BOX 405
#*                                  02101 Espoo, Finland
#*                                  Tel. +358 0 457 2723
#*                                Telefax: +358 0 457 2302
#*                              EMail: Juha.Ruokolainen@csc.fi
#*
#*                       Date: 04 Oct 2007
#*
#*                Modified by:
#*
#*       Date of modification:
#*
#******************************************************************************
set TIFFFileName "elmerpost.tif"

proc savetiff.Control { } {
    global savetiff_control TIFFFileName 

    set savetiff_control .savetiff_control
    
    if { [winfo exists $savetiff_control] } {
	destroy $savetiff_control.title
	destroy $savetiff_control.file
	destroy $savetiff_control.save_button
	destroy $savetiff_control.buttons
    } else {
	toplevel $savetiff_control
	place_window $savetiff_control
    }

    wm title $savetiff_control "Savetiff control"
    #
    # File name:
    #
    frame $savetiff_control.file
    
    label $savetiff_control.file.label -width 8 -text "File name:"
    entry $savetiff_control.file.name -width 30 -textvariable TIFFFileName
    button $savetiff_control.file.button -text "Browse.." \
	-command { set TIFFFileName [tk_getSaveFile -parent .savetiff_control \
					-title "Save Picture To File"]; }
    pack $savetiff_control.file.label $savetiff_control.file.name \
	$savetiff_control.file.button -side left -expand 1

    pack $savetiff_control.file -expand 1 -fill both -side top
    #
    #   Buttons:
    #
    frame $savetiff_control.buttons

    button $savetiff_control.buttons.close -text "Close" \
	-command { destroy $savetiff_control }

    frame $savetiff_control.save_button
    button $savetiff_control.save_button.save \
	-text "Save" -command { savetiff $TIFFFileName  }
    pack $savetiff_control.save_button.save \
	-side left -expand 1 -fill x

    pack $savetiff_control.buttons.close -side right

    pack $savetiff_control.save_button -side top -expand 1 -fill x
    pack $savetiff_control.buttons -side top -fill x -expand 1
}
