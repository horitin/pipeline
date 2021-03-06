######################################################################
# 2008 Digital Domain Inc.  
######################################################################
                                                                                
                                                              
######################################################################
#
# SOURCE FILE:  ImportSSF.tcl
#
# DESCRIPTION:  Use this script to import ssf files generated by shake.
#
# MENU OPTION:  Put the following line in your menu.tcl file if you want 
#		a menu option with a file browser...
#		menu "Draw/Import .ssf" {panel -w500 "Import ssf" {{"ssf file: " ssfFileName__ f}}; import_ssf $ssfFileName__; return ""}
#
# AUTHOR:       Remy Torre 
# DATE:         July 18, 2006
# VERSION:      2.5.1
#
# MODIFICATIONS:
#               Jun 17 2006 (1.0)
#                       Original version. shape import functionality.
#               Jul 18 2006 (2.0)
#			Fixed shape importer bug when using non-default exporting of ssf files.
#                       Added support for ssf opacity keyframes
#		Nov 12 2008 (2.5)
#			added shape colour, made sure Beziers draw into rgba and never replace the upstream channels
#		Nov 14 2008 (2.5.1)
#			Bug fixes.
######################################################################


# What the hell
global pi
set pi 3.1415926535897931

global epsilon
set epsilon 0.0001


proc ImportSSF args {
    
    # The first argument is the .ssf file
    set ssf_file [open [lindex $args 0]]
    set data [read $ssf_file]
    
    if {[catch {close $ssf_file} err]} {
        message "read $lensfile failed: $err"
		return 0
    }

    # split the lines in a list
    set lines [split $data \n]
    
    set shapedata [list]
    set shapename 0
    
    # Read the file, gather all information about a shape (we can have several shapes in one file)
    # and create a bezier node with that information
    foreach line $lines {
        # Record the current line
        lappend shapedata $line
    if [regexp {^color_} $line] {lappend shapeColour [lindex $line 1]}
        # 'shape_name' defines the beginning of a new shape data set
        if {[string compare "shape_name" [lindex $line 0]] == 0} {
            if {$shapename == 0} {
                set shapename [lindex $line 1]
                continue
            }
            
            create_bezier $shapename $shapedata $shapeColour
            set shapedata [list]
            set shapename [lindex $line 1]
        set shapeColour {}
        }    
    }
        
    # Create the last bezier here
    create_bezier $shapename $shapedata $shapeColour
    return 1
}


# Create a Bezier node with info passed as parameter
proc create_bezier args {

    # Name of the shape
    set shapename [lindex $args 0]
    set shapedata [lindex $args 1]
    set shapeColour [lindex $args 2]
        
    # Recording list
    set key_frames [list]
    set points_info [list]
    set color_a [list]
    
    # blur flag
    set edge_shape 0
    
    # Parse the file and extract the information needed for the nuke bezier stuff
    foreach line $shapedata {        
        
        # Looking for "edge_shape" that will say if each point is defined by 6 figures (=0)
        # or 12 (=1)
        if {[string compare "edge_shape" [lindex $line 0]] == 0} {
            set edge_shape [lindex $line 1]
        }
                                
        # We need to record the keyframes number ('key_time' keyword).
        # Let's make a list of that
        if {[string compare "key_time" [lindex $line 0]] == 0} {
            lappend key_frames [lindex $line 1]
        }
        
        # Check for the "color_a" keyword which is going to drive the mix slider of the
        # bezier node we are creating
        if {[string compare "color_a" [lindex $line 0]] == 0} {        
            lappend color_a [lindex $line 1]
        }
        
        # When we found a vertex data, process the entire (possibly very big) line
        # let's build a list of list of list 
        if {[string compare "vertex_data" [lindex $line 0]] == 0} {         
            lappend points_info [process_vertex [lrange $line 1 end] $edge_shape]
        }        
    }
    
    
    # We can now create a Bezier node and set all that it's key frames now !
    # Generate the shape parameter and the knob command, the most interesting one
    # nuke> knob Bezier1.points {{{0 0} {10 0} {0 10}} {{100 100} {120 100} {100 120}}}
    # nuke> knob Bezier1.shape {{curve L x1 0 x10 2}}
    set shape  "{{curve L "
    set pointslist "{"
    set mix_key "{{curve "
    
    set framecount 0
    foreach key $points_info {
        # Get the key frame number
        set key_value [lindex $key_frames $framecount]
        
        # Update the shape (incremental count for each key)
        append shape " x$key_value $framecount"

        # Get the mix value and update the curve for this keyframe
        set current_mix_value [lindex $color_a $framecount]
        append mix_key " x$key_value $current_mix_value"

        set framecount [expr $framecount + 1]
        append pointslist "{ "
        
        set pointNb 0
        foreach point $key {
            set nuke_points [process_one_vertice $point $edge_shape]
            append pointslist "{$nuke_points} "            
            set pointNb [expr $pointNb + 1] 
        }
        
        append pointslist "} "
    }
    
    append shape "}}"
    append pointslist "}"
    append mix_key "}}"
    
    # Now we can create our Bezier node
    Bezier -new "name $shapename output {rgba} replace 0 points $pointslist shape $shape mix $mix_key color [list [lrange $shapeColour 0 2]]"
}



# This will process a vertex_data line and order the needed informations
# The "blur_param" parameter tells us if we will have 6 (0) or 12 (1) figures per point
proc process_vertex {line blur_param} {
    
    set offset [expr 6 + 6 * $blur_param]
    
    # Create a list of points
    set points [list]
    
    # Each 12 (or 6 if blur is zero) contiguous numbers are information about a point, 
    # create a list of those and store
    set vertex_length [llength $line]
        
    set vertex_count 0
    
    # Extract the list of the 12/6 first number numbers, and store this list into the points list
    while {$vertex_count != $vertex_length} {
        set param12 [lrange $line $vertex_count [expr $vertex_count + $offset - 1]]
        lappend points $param12
        
        set vertex_count [expr $vertex_count + $offset]        
    }
    
    return $points
}


# Process the 12/6 shake points to nuke format
# ssf format is
# [x, y, xbackward, ybackward, xforward, yforward, (same for blur point)]
#
# Nuke format is
# [x, y, forward_length, forward_angle, backward_length, backward_angle (not sure), (and some weird shit for blur)]
#
# the "blur_param" parameter will indicate if we can expect 6 or 12 parameters per point
proc process_one_vertice {points blur_param} {
        
    global pi
    global epsilon
        
    # That's the final list we will return
    set nuke_points [list]
    
    # Get the each point information and be ready to compute
    set x  [lindex $points 0]
    set y  [lindex $points 1]
    set xbackward [lindex $points 2]
    set ybackward [lindex $points 3]
    set xforward  [lindex $points 4]
    set yforward  [lindex $points 5]
    
    # Compute the length of each handle    
    set backward_length [expr {sqrt(($x-$xbackward)*($x-$xbackward) + ($y-$ybackward)*($y-$ybackward))}]
    set forward_length  [expr {sqrt(($x-$xforward) *($x-$xforward)  + ($y-$yforward) *($y-$yforward))}]
    
    # Compute the angle made by each handle and the horizontal
    set backward_angle 0
    set forward_angle  0
        
    set backward_diff_angle 0
        
    if {$backward_length != 0} {set backward_angle [expr {acos(($xbackward - $x) / $backward_length)}]}
    if {$forward_length  != 0} {set forward_angle  [expr {acos(($xforward  - $x) / $forward_length)}]}
    
    # Make sure the angles have the good sign
    if {$ybackward < $y} {set backward_angle [expr 2*$pi - $backward_angle]}
    if {$yforward  < $y} {set forward_angle  [expr 2*$pi - $forward_angle]}
        
    # Compute the opposite angle of forward_angle and make sure it has a good sign
    set alpha [expr $forward_angle - $pi]
    if {$alpha < 0} {set alpha [expr 2*$pi + $alpha]}
        
    # Compute the nuke backward angle which is defined relative to the forward angle.
    set backward_diff_angle [expr $backward_angle - $alpha]
            
    # Define the parameters we are going to pass to nuke
    set blur_angle 0
    set blur_length 0
    set blur_forward_length_diff  0
    set blur_backward_length_diff 0
    set forward_blur_angle_diff   0
    set backward_blur_angle_diff  0
    
    if {$blur_param} {
    
    	# Get the blur points information
    	set xblur [lindex $points 6]
    	set yblur [lindex $points 7]
    	set xblur_backward [lindex $points 8]
    	set yblur_backward [lindex $points 9]
    	set xblur_forward  [lindex $points 10]
    	set yblur_forward  [lindex $points 11]
        	
    	# Compute the distance between the main point and the blur point
    	set blur_length [expr sqrt(($x-$xblur)*($x-$xblur) + ($y-$yblur)*($y-$yblur))]
    	    	
    	# Continue to compute the blur parameters if we need to
    	if {$blur_length != 0} {
    	
        	# Compute the angle formed by [(x, y), (xblur, yblur)] and the vertical
        	set blur_angle [expr acos(($yblur - $y) / $blur_length)]
        	
        	# Make sure we have a good angle
        	if {$xblur > $x} {set blur_angle [expr 2*$pi - $blur_angle]}
        	
        	# Do as nuke says (!)
        	set blur_angle [expr $blur_angle - $forward_angle]
        	        	
        	# Compute now the length of the forward blur handle minus the length of the forward handle (non blur)
        	set blur_forward_length      [expr sqrt(($xblur_forward-$xblur)*($xblur_forward-$xblur) + ($yblur_forward-$yblur)*($yblur_forward-$yblur))]
        	set blur_forward_length_diff [expr $blur_forward_length - $forward_length]
        	
        	# Same with backward blur handle
        	set blur_backward_length      [expr sqrt(($xblur_backward-$xblur)*($xblur_backward-$xblur) + ($yblur_backward-$yblur)*($yblur_backward-$yblur))]
        	set blur_backward_length_diff [expr $blur_backward_length - $backward_length]

        	if {$blur_forward_length != 0} {
            	# The angle with the horizontal of the forward blur handle minus the angle of the 'normal' forward handle($backward_angle)
            	set forward_blur_angle [expr {acos(($xblur_forward - $xblur) / $blur_forward_length)}]
        	
            	# Make sure it's between [0, 2pi]
            	if {$yblur_forward  < $yblur} {set forward_blur_angle  [expr 2*$pi - $forward_blur_angle]}
        	
            	# Get the angle diff then
            	set forward_blur_angle_diff [expr $forward_blur_angle - $forward_angle]
        	}
        	
        	if {$blur_backward_length != 0} {
            	# Almost the same with the backward angle
            	set backward_blur_angle [expr {acos(($xblur_backward - $xblur) / $blur_backward_length)}]
        	
            	# Make sure it's between [0, 2pi]
            	if {$yblur_backward  < $yblur} {set backward_blur_angle  [expr 2*$pi - $backward_blur_angle]}
        	
            	# Get the angle diff then
            	set backward_blur_angle_diff [expr $backward_blur_angle - ($forward_angle + $forward_blur_angle_diff + $pi)]
        	}
    	}
    }    
        
    # Build the list of points we want to return for the nuke Bezier
    lappend nuke_points $x
    lappend nuke_points $y
    
    lappend nuke_points $forward_length
    lappend nuke_points $forward_angle
    
    lappend nuke_points $backward_length
    lappend nuke_points $backward_diff_angle
    
    # Add blur information
    lappend nuke_points $blur_length
    lappend nuke_points $blur_angle
    
    lappend nuke_points $blur_forward_length_diff
    lappend nuke_points $forward_blur_angle_diff
    
    lappend nuke_points $blur_backward_length_diff
    
    if {$backward_blur_angle_diff != 0} {
        lappend nuke_points $backward_blur_angle_diff
    } else {
        lappend nuke_points $backward_diff_angle
    }    
    
    return $nuke_points
}

