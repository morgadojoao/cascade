-- Cascade
--
-- Shows one dialog with a checklist of every open window (App - Title), a size
-- field (width x height, pre-filled), All / None buttons, and a Cascade button.
-- Press Cascade and the checked windows are resized and stepped diagonally.
-- Each window is cascaded on the display it is currently on, starting from the
-- top-left of that display's usable area (below the menu bar, clear of the Dock).
-- Windows are raised in turn so the last one in the list ends up on top.
-- If any window couldn't be moved, a summary is shown at the end.
--
-- Run it with:   osascript ~/path/to/cascade.applescript
-- or open it in Script Editor and use File > Export... > File Format: Application
-- to get a double-clickable app.
--
-- Requires Accessibility permission for whatever runs it (Terminal, Script Editor,
-- or the exported app): System Settings > Privacy & Security > Accessibility.

use AppleScript version "2.4"
use framework "AppKit"
use scripting additions

property defaultSize : "1200x800" -- pre-filled value in the size field
property stepX : 40 -- horizontal offset between cascaded windows
property stepY : 32 -- vertical offset between cascaded windows
property marginX : 20 -- gap from the left edge of the screen's usable area
property marginY : 20 -- gap from the top edge of the screen's usable area

property checkBoxes : {} -- the checklist controls, so the All / None buttons can reach them
property pickerLabels : {} -- input to the picker (set before hopping to the main thread)
property pickerResult : missing value -- output of the picker (read after the hop)

on run
	try
		activate
		
		-- ---------------------------------------------------------------
		-- 1. Collect all visible windows from non-background apps
		-- ---------------------------------------------------------------
		set windowLabels to {}
		set windowPids to {}
		set windowIdx to {}
		set windowTitles to {}
		
		tell application "System Events"
			set procList to every application process whose background only is false and visible is true
			repeat with p in procList
				set pName to name of p
				set pid to unix id of p
				set winList to {}
				try
					set winList to every window of p
				end try
				set i to 0
				repeat with w in winList
					set i to i + 1
					set wTitle to ""
					try
						set wTitle to name of w
					end try
					if wTitle is missing value then set wTitle to ""
					set shownTitle to wTitle
					if shownTitle is "" then set shownTitle to "(untitled)"
					set end of windowLabels to pName & " - " & shownTitle
					set end of windowPids to pid
					set end of windowIdx to i
					set end of windowTitles to wTitle
				end repeat
			end repeat
		end tell
		
		if (count of windowLabels) is 0 then
			display alert "No windows found" message "Couldn't see any open windows. Make sure the app running this script has Accessibility permission (System Settings > Privacy & Security > Accessibility)." as warning
			return
		end if
		
		-- ---------------------------------------------------------------
		-- 2. One dialog: checklist + size field + Cascade button
		-- ---------------------------------------------------------------
		-- AppKit windows must be created on the main thread. Script Editor runs
		-- scripts on a background thread, so hop over and wait for the result.
		set pickerLabels to windowLabels
		set pickerResult to missing value
		my performSelectorOnMainThread:"showPickerOnMainThread:" withObject:(missing value) waitUntilDone:true
		set picked to pickerResult
		if picked is missing value then return -- Cancel
		set chosenIdx to item 1 of picked
		set winW to item 2 of picked
		set winH to item 3 of picked
		
		-- ---------------------------------------------------------------
		-- 3. Cascade, per display
		-- ---------------------------------------------------------------
		set screenList to my getScreens()
		
		-- One cascade cursor per display
		set curX to {}
		set curY to {}
		set wraps to {}
		repeat with s in screenList
			set end of curX to (vl of s) + marginX
			set end of curY to (vt of s) + marginY
			set end of wraps to 0
		end repeat
		
		-- Raising a window moves it to index 1 of its app, shifting the others.
		-- Remember what we've raised so later lookups by index can compensate.
		set raisedPids to {}
		set raisedIdx to {}
		
		set failures to {}
		
		repeat with idxRef in chosenIdx
			set idx to idxRef as integer
			set lblText to item idx of windowLabels
			set pid to item idx of windowPids
			set wi to item idx of windowIdx
			set wTitle to item idx of windowTitles
			
			try
				-- How many windows of this app with a higher original index have we raised?
				set shiftCount to 0
				repeat with r from 1 to count of raisedPids
					if (item r of raisedPids) is pid and (item r of raisedIdx) > wi then set shiftCount to shiftCount + 1
				end repeat
				
				set theWin to my findWindow(pid, wi, wTitle, shiftCount)
				
				-- Find the window's centre so we know which display it lives on
				set cx to 0
				set cy to 0
				tell application "System Events"
					try
						set {px, py} to position of theWin
						set {pw, ph} to size of theWin
						set cx to px + (pw div 2)
						set cy to py + (ph div 2)
					end try
				end tell
				set k to my screenIndexForPoint(cx, cy, screenList)
				set s to item k of screenList
				set vRight to (vl of s) + (vw of s)
				set vBottom to (vt of s) + (vh of s)
				
				-- Don't let the window be bigger than the display it's on
				set w2 to winW
				set h2 to winH
				if w2 > (vw of s) - (marginX * 2) then set w2 to (vw of s) - (marginX * 2)
				if h2 > (vh of s) - (marginY * 2) then set h2 to (vh of s) - (marginY * 2)
				
				set x to item k of curX
				set y to item k of curY
				
				-- If the next window would run off this display, start a new cascade column
				if (x + w2 > vRight) or (y + h2 > vBottom) then
					set item k of wraps to (item k of wraps) + 1
					set x to (vl of s) + marginX + ((item k of wraps) * stepX * 3)
					set y to (vt of s) + marginY
					if x + w2 > vRight then set x to (vl of s) + marginX
				end if
				
				-- Move first, then resize, then nudge back into place (some apps
				-- clamp or shift on resize). Each step is independent so one
				-- failing doesn't stop the others.
				set errText to ""
				tell application "System Events"
					try
						set position of theWin to {x, y}
					on error m
						set errText to "move: " & m
					end try
					try
						set size of theWin to {w2, h2}
						set position of theWin to {x, y}
					on error m
						if errText is "" then set errText to "resize: " & m
					end try
					try
						perform action "AXRaise" of theWin
						set end of raisedPids to pid
						set end of raisedIdx to wi
					end try
				end tell
				if errText is not "" then set end of failures to lblText & " -> " & errText
				
				set item k of curX to x + stepX
				set item k of curY to y + stepY
				
			on error m
				set end of failures to lblText & " -> " & m
			end try
		end repeat
		
		if (count of failures) > 0 then
			set AppleScript's text item delimiters to return
			set failText to failures as text
			set AppleScript's text item delimiters to ""
			display alert "Some windows couldn't be cascaded" message failText as warning
		end if
		
	on error errMsg number errNum
		if errNum is -128 then return -- user pressed Cancel
		display alert "Cascade failed" message errMsg & " (" & errNum & ")" as critical
	end try
end run

-- ---------------------------------------------------------------------------
-- The picker dialog: an NSAlert whose accessory view holds a scrolling
-- checklist of windows, a size field, and All / None buttons. Buttons are
-- "Cascade" (default, Return) and "Cancel" (Escape).
-- Returns {list of chosen indices, width, height} or missing value on Cancel.
-- ---------------------------------------------------------------------------

-- Main-thread entry point; reads pickerLabels, writes pickerResult.
on showPickerOnMainThread:arg
	set pickerResult to missing value
	try
		set pickerResult to my showPicker(pickerLabels)
	on error m
		-- Surface the error on the main thread rather than letting it vanish
		display alert "Cascade failed" message m as critical
	end try
end showPickerOnMainThread:

on showPicker(windowLabels)
	set n to count of windowLabels
	set rowH to 24
	set panelW to 500
	set listH to n * rowH
	set visH to listH
	if visH > 288 then set visH to 288 -- ~12 rows before it scrolls
	set bottomH to 40 -- room for the size field and All / None buttons
	
	-- Checklist ------------------------------------------------------------
	set docView to current application's NSView's alloc()'s initWithFrame:{{0, 0}, {panelW - 20, listH}}
	set checkBoxes to {}
	repeat with i from 1 to n
		-- AppKit views have a bottom-left origin, so row 1 goes at the top
		set cb to (current application's NSButton's alloc()'s initWithFrame:{{4, (n - i) * rowH}, {panelW - 30, rowH}})
		(cb's setButtonType:3) -- NSButtonTypeSwitch (checkbox)
		(cb's setTitle:(item i of windowLabels))
		(cb's setState:1) -- checked
		(cb's setLineBreakMode:4) -- truncate long titles with an ellipsis
		(docView's addSubview:cb)
		set end of checkBoxes to cb
	end repeat
	
	set scroller to current application's NSScrollView's alloc()'s initWithFrame:{{0, bottomH}, {panelW, visH + 4}}
	scroller's setDocumentView:docView
	scroller's setHasVerticalScroller:true
	scroller's setBorderType:2 -- NSBezelBorder
	docView's scrollPoint:{0, listH} -- start scrolled to the top of the list
	
	-- Size field -------------------------------------------------------------
	set sizeLabel to current application's NSTextField's labelWithString:"Size (W x H):"
	sizeLabel's setFrame:{{2, 9}, {96, 20}}
	set sizeField to current application's NSTextField's alloc()'s initWithFrame:{{98, 6}, {120, 24}}
	sizeField's setStringValue:defaultSize
	
	-- All / None -------------------------------------------------------------
	set allBtn to current application's NSButton's alloc()'s initWithFrame:{{panelW - 168, 3}, {80, 30}}
	allBtn's setTitle:"All"
	allBtn's setBezelStyle:1 -- NSBezelStyleRounded
	allBtn's setTarget:me
	allBtn's setAction:"selectAllWindows:"
	
	set noneBtn to current application's NSButton's alloc()'s initWithFrame:{{panelW - 84, 3}, {80, 30}}
	noneBtn's setTitle:"None"
	noneBtn's setBezelStyle:1
	noneBtn's setTarget:me
	noneBtn's setAction:"selectNoWindows:"
	
	-- Assemble ---------------------------------------------------------------
	set container to current application's NSView's alloc()'s initWithFrame:{{0, 0}, {panelW, visH + 4 + bottomH}}
	container's addSubview:scroller
	container's addSubview:sizeLabel
	container's addSubview:sizeField
	container's addSubview:allBtn
	container's addSubview:noneBtn
	
	set theAlert to current application's NSAlert's alloc()'s init()
	theAlert's setMessageText:"Cascade"
	theAlert's setInformativeText:"Choose the windows to cascade and the size to make them."
	theAlert's addButtonWithTitle:"Cascade"
	theAlert's addButtonWithTitle:"Cancel"
	theAlert's setAccessoryView:container
	
	repeat
		set response to theAlert's runModal()
		if response is not 1000 then return missing value -- 1000 = first button (Cascade)
		
		set dims to my parseSize(sizeField's stringValue() as text)
		set chosenIdx to {}
		repeat with i from 1 to n
			if (((item i of checkBoxes)'s state()) as integer) is 1 then set end of chosenIdx to i
		end repeat
		
		if dims is missing value then
			theAlert's setInformativeText:"Enter the size as width x height, for example 1200x800."
		else if (count of chosenIdx) is 0 then
			theAlert's setInformativeText:"Select at least one window to cascade."
		else
			return {chosenIdx, item 1 of dims, item 2 of dims}
		end if
	end repeat
end showPicker

on selectAllWindows:sender
	repeat with cb in checkBoxes
		(cb's setState:1)
	end repeat
end selectAllWindows:

on selectNoWindows:sender
	repeat with cb in checkBoxes
		(cb's setState:0)
	end repeat
end selectNoWindows:

-- Locate a window of the process with the given pid. Prefer matching by title
-- (immune to z-order changes); fall back to the original index adjusted for
-- windows of this app we've already raised.
on findWindow(pid, wi, wTitle, shiftCount)
	tell application "System Events"
		set theProc to first application process whose unix id is pid
		if wTitle is not "" then
			try
				set matches to every window of theProc whose name is wTitle
				if (count of matches) is 1 then return item 1 of matches
			end try
		end if
		try
			return window (wi + shiftCount) of theProc
		end try
		return window wi of theProc
	end tell
end findWindow

-- Returns one record per display, in System Events coordinates (origin at the
-- top-left of the primary display, y grows downward):
--   fl/ft/fw/fh = full frame, vl/vt/vw/vh = visible frame (no menu bar / Dock)
on getScreens()
	set screenList to {}
	set allScreens to current application's NSScreen's screens()
	set {pfx, pfy, pfw, pfh} to my rectParts((allScreens's objectAtIndex:0)'s frame())
	set primaryH to pfh
	
	repeat with scr in (allScreens as list)
		set {fx, fy, fw, fh} to my rectParts(scr's frame())
		set {vx, vy, vw, vh} to my rectParts(scr's visibleFrame())
		
		set fl to fx as integer
		set fw to fw as integer
		set fh to fh as integer
		-- flip from Cocoa (bottom-left origin) to System Events (top-left origin)
		set ft to (primaryH - (fy + fh)) as integer
		
		set vl to vx as integer
		set vw to vw as integer
		set vh to vh as integer
		set vt to (primaryH - (vy + vh)) as integer
		
		set end of screenList to {fl:fl, ft:ft, fw:fw, fh:fh, vl:vl, vt:vt, vw:vw, vh:vh}
	end repeat
	return screenList
end getScreens

-- An NSRect comes back from AppKit either as a record {origin:{x, y}, size:{width, height}}
-- or as a nested list {{x, y}, {width, height}} depending on the macOS version.
-- Normalise to a flat list {x, y, width, height}.
on rectParts(r)
	try
		return {x of origin of r, y of origin of r, width of size of r, height of size of r}
	on error
		return {item 1 of item 1 of r, item 2 of item 1 of r, item 1 of item 2 of r, item 2 of item 2 of r}
	end try
end rectParts

-- Index of the display whose full frame contains the point; falls back to the primary display
on screenIndexForPoint(px, py, screenList)
	repeat with k from 1 to count of screenList
		set s to item k of screenList
		if px is greater than or equal to (fl of s) and px < (fl of s) + (fw of s) and py is greater than or equal to (ft of s) and py < (ft of s) + (fh of s) then return k
	end repeat
	return 1
end screenIndexForPoint

-- Parse "1200x800", "1200 x 800", "1200,800" -> {1200, 800}; missing value if invalid
on parseSize(t)
	set t to my replaceText(t, ",", "x")
	set t to my replaceText(t, " ", "")
	set AppleScript's text item delimiters to "x"
	set parts to text items of t
	set AppleScript's text item delimiters to ""
	if (count of parts) is not 2 then return missing value
	try
		set w to (item 1 of parts) as integer
		set h to (item 2 of parts) as integer
	on error
		return missing value
	end try
	if w < 100 or h < 100 then return missing value
	return {w, h}
end parseSize

on replaceText(t, findStr, replStr)
	set AppleScript's text item delimiters to findStr
	set parts to text items of t
	set AppleScript's text item delimiters to replStr
	set r to parts as text
	set AppleScript's text item delimiters to ""
	return r
end replaceText
