-- Cascade
--
-- A menu bar app that cascades open windows diagonally, each on the display it
-- is already on, starting from the top-left of that display's usable area
-- (below the menu bar, clear of the Dock).
--
-- Menu bar icon:
--   double-click          cascade every window at the saved size, no dialog
--   right / Control-click open the menu (a plain click opens it after a short
--                         pause, so a double-click can be told apart)
-- Menu:
--   Select Windows...     checklist of windows + size field, then cascade
--   Size (WxH)...         change the saved size used by double-click
--   Run at Startup        start Cascade when you log in
--   Quit Cascade
--
-- Windows are raised in turn so the last one ends up on top. If any window
-- couldn't be moved or resized, one summary alert lists them at the end.
--
-- Build with scripts/build.command (dev) or scripts/make_installer.command
-- (DMG). Running the source directly with osascript opens the picker once.
--
-- Requires Accessibility permission for whatever runs it (the app, or Terminal
-- for osascript): System Settings > Privacy & Security > Accessibility.

use AppleScript version "2.4"
use framework "AppKit"
use framework "ServiceManagement"
use scripting additions

property defaultSize : "1200x800" -- first-run size; after that the saved size (Size... menu) wins
property stepX : 40 -- horizontal offset between cascaded windows
property stepY : 32 -- vertical offset between cascaded windows
property marginX : 20 -- gap from the left edge of the screen's usable area
property marginY : 20 -- gap from the top edge of the screen's usable area

property appBundleId : "com.morgadoj.cascade" -- must match BUNDLE_ID in scripts/build_app.sh
property sizeKey : "defaultSize" -- preferences key for the saved size

property checkBoxes : {} -- the checklist controls, so the All / None buttons can reach them
property pickerLabels : {} -- input to the picker (set before hopping to the main thread)
property pickerSize : "" -- input to the picker: pre-filled size text
property pickerResult : missing value -- output of the picker (read after the hop)

property statusItem : missing value -- the menu bar item; kept here so it isn't released
property statusMenu : missing value -- its menu, attached only while it is open
property sizeMenuItem : missing value -- "Size (WxH)..." item, retitled when the size changes
property startupMenuItem : missing value -- "Run at Startup" item, ticked to match the system

-- ===========================================================================
-- App lifecycle
-- ===========================================================================

-- The built app is a stay-open menu bar app (LSUIElement set by build_app.sh):
-- launching it only installs the menu bar item. Run from source with
-- osascript there is no such Info.plist flag, so it opens the picker once.
on run
	set isMenuBarApp to false
	try
		set flag to current application's NSBundle's mainBundle()'s objectForInfoDictionaryKey:"LSUIElement"
		if flag is not missing value then set isMenuBarApp to (flag as boolean)
	end try
	if isMenuBarApp then
		if statusItem is missing value then my performSelectorOnMainThread:"setupStatusItem:" withObject:(missing value) waitUntilDone:true
	else
		my cascadeWithPicker()
	end if
end run

-- Launching the app again (Finder, Spotlight) while it is running opens the
-- picker; useful when the menu bar icon is hidden behind the notch.
on reopen
	my cascadeWithPicker()
end reopen

-- A stay-open applet writes its top-level properties back into main.scpt on
-- quit. Clear the ones holding AppKit objects first: they can't be saved, and
-- the write must not fail or change more of the (signed) bundle than needed.
on quit
	set statusItem to missing value
	set statusMenu to missing value
	set sizeMenuItem to missing value
	set startupMenuItem to missing value
	set checkBoxes to {}
	set pickerLabels to {}
	set pickerResult to missing value
	continue quit
end quit

-- ===========================================================================
-- Menu bar item
-- ===========================================================================

-- Main-thread entry point. Creates the status item and its menu. The menu is
-- not attached to the item permanently: an attached menu opens on mouse-down
-- and the button never reports clicks, so double-click could not be detected.
-- Instead the button sends statusItemClicked: and we attach the menu on demand.
on setupStatusItem:arg
	try
		set statusItem to current application's NSStatusBar's systemStatusBar()'s statusItemWithLength:-1 -- NSVariableStatusItemLength
		set btn to statusItem's button()
		set img to current application's NSImage's imageWithSystemSymbolName:"macwindow.on.rectangle" accessibilityDescription:"Cascade"
		if img is missing value then
			btn's setTitle:"Cascade"
		else
			img's setTemplate:true -- follows light / dark menu bar
			btn's setImage:img
		end if
		btn's setToolTip:"Cascade - double-click to cascade all windows, right-click for options"
		btn's setTarget:me
		btn's setAction:"statusItemClicked:"
		btn's sendActionOn:20 -- NSEventMaskLeftMouseUp (4) + NSEventMaskRightMouseUp (16)
		
		set statusMenu to current application's NSMenu's alloc()'s init()
		statusMenu's setDelegate:me -- menuDidClose: detaches it again
		statusMenu's addItem:(my newMenuItem("Select Windows...", "selectWindowsFromMenu:", ""))
		set sizeMenuItem to my newMenuItem("Size...", "sizeFromMenu:", "")
		statusMenu's addItem:sizeMenuItem
		statusMenu's addItem:(current application's NSMenuItem's separatorItem())
		set startupMenuItem to my newMenuItem("Run at Startup", "toggleStartupFromMenu:", "")
		statusMenu's addItem:startupMenuItem
		statusMenu's addItem:(current application's NSMenuItem's separatorItem())
		statusMenu's addItem:(my newMenuItem("Quit Cascade", "quitFromMenu:", "q"))
	on error m
		display alert "Cascade failed" message "Couldn't create the menu bar item: " & m as critical
	end try
end setupStatusItem:

-- Returns an NSMenuItem titled itemTitle whose action is the handler named
-- actionName in this script; keyEq is its key equivalent ("" for none).
on newMenuItem(itemTitle, actionName, keyEq)
	set mi to current application's NSMenuItem's alloc()'s initWithTitle:itemTitle action:actionName keyEquivalent:keyEq
	mi's setTarget:me
	return mi
end newMenuItem

-- Button action, on every left or right mouse-up on the icon (main thread).
--   right-click, or Control + left-click -> menu now
--   left double-click                     -> cascade all
--   left single click                     -> menu after the double-click interval,
--                                            unless a second click cancels it
--   anything else (VoiceOver, keyboard)   -> menu now
on statusItemClicked:sender
	try
		set ev to current application's NSApp's currentEvent()
		if ev is missing value then
			my showStatusMenu()
			return
		end if
		set evType to (ev's |type|()) as integer
		set flags to (ev's modifierFlags()) as integer
		-- AppleScript has no bitwise AND: NSEventModifierFlagControl is 1 << 18 (262144)
		set controlDown to ((flags div 262144) mod 2) is 1
		
		if evType is 4 or controlDown then -- 4 = NSEventTypeRightMouseUp
			current application's NSObject's cancelPreviousPerformRequestsWithTarget:me
			my showStatusMenu()
		else if evType is not 2 then -- 2 = NSEventTypeLeftMouseUp; clickCount() is only valid for mouse events
			my showStatusMenu()
		else if ((ev's clickCount()) as integer) is 2 then
			current application's NSObject's cancelPreviousPerformRequestsWithTarget:me
			my cascadeAll()
		else if ((ev's clickCount()) as integer) is 1 then
			my performSelector:"singleClickTimerFired:" withObject:(missing value) afterDelay:(current application's NSEvent's doubleClickInterval())
		end if
	on error m number n
		my showError(m, n)
	end try
end statusItemClicked:

-- Timer from statusItemClicked: (main run loop). No second click arrived in
-- time, so it was a single click: open the menu.
on singleClickTimerFired:arg
	try
		my showStatusMenu()
	on error m number n
		my showError(m, n)
	end try
end singleClickTimerFired:

-- Refresh the menu, attach it and open it under the icon (main thread). It is
-- detached again in menuDidClose: so the next click goes to statusItemClicked:.
on showStatusMenu()
	my refreshMenu()
	statusItem's setMenu:statusMenu
	statusItem's button()'s performClick:(missing value)
end showStatusMenu

-- NSMenuDelegate, main thread: the menu closed (item chosen or dismissed).
-- Detach it so the button reports clicks again.
on menuDidClose:theMenu
	try
		statusItem's setMenu:(missing value)
	on error m number n
		my showError(m, n)
	end try
end menuDidClose:

-- Main thread. Shows the current size in the Size item and sets the Run at
-- Startup tick from the system: on, off, or mixed (a dash) when macOS is
-- waiting for approval in System Settings.
on refreshMenu()
	sizeMenuItem's setTitle:("Size (" & my loadSize() & ")...")
	set startupState to my runAtStartupState()
	if startupState is "on" then
		startupMenuItem's setState:1 -- NSControlStateValueOn
	else if startupState is "approval" then
		startupMenuItem's setState:-1 -- NSControlStateValueMixed
	else
		startupMenuItem's setState:0 -- NSControlStateValueOff
	end if
end refreshMenu

-- Menu actions. AppKit calls them on the main thread; each one shows its own
-- errors, because an error left uncaught in an action handler only reaches
-- the system log.

-- Menu > Select Windows...
on selectWindowsFromMenu:sender
	my cascadeWithPicker() -- has its own error alert
end selectWindowsFromMenu:

-- Menu > Size...
on sizeFromMenu:sender
	try
		my askForSize()
	on error m number n
		my showError(m, n)
	end try
end sizeFromMenu:

-- Menu > Run at Startup. If macOS is waiting for approval, unregistering
-- would be the wrong answer to a click, so open Login Items instead.
on toggleStartupFromMenu:sender
	try
		set startupState to my runAtStartupState()
		if startupState is "approval" then
			my showApprovalNeeded()
		else
			my setRunAtStartup(startupState is "off")
		end if
	on error m number n
		my showError(m, n)
	end try
end toggleStartupFromMenu:

-- Menu > Quit Cascade (runs the quit handler above)
on quitFromMenu:sender
	tell me to quit
end quitFromMenu:

-- A menu bar app is never frontmost on its own; bring it forward so dialogs
-- get keyboard focus and don't open behind other windows. The NSApp call is
-- the stronger of the two; it is deprecated since macOS 14, so it is allowed
-- to fail and the plain activate still runs.
on bringToFront()
	try
		current application's NSApp's activateIgnoringOtherApps:true
	end try
	activate
end bringToFront

-- The generic "Cascade failed" alert for unexpected errors (m = message,
-- n = number). Main thread: every caller is a menu, button or timer handler.
on showError(m, n)
	my bringToFront()
	display alert "Cascade failed" message m & " (" & n & ")" as critical
end showError

-- ===========================================================================
-- Cascading
-- ===========================================================================

-- Menu > Select Windows... (and reopen, and osascript): collect, pick, cascade
on cascadeWithPicker()
	try
		my bringToFront()
		set wins to my collectWindows()
		if (count of (labels of wins)) is 0 then
			my showNoWindowsAlert(firstErr of wins)
			return
		end if
		
		-- AppKit windows must be created on the main thread. Script Editor runs
		-- scripts on a background thread, so hop over and wait for the result.
		set pickerLabels to labels of wins
		set pickerSize to my loadSize()
		set pickerResult to missing value
		my performSelectorOnMainThread:"showPickerOnMainThread:" withObject:(missing value) waitUntilDone:true
		set picked to pickerResult
		if picked is missing value then return -- Cancel
		
		my cascadeChosen(wins, item 1 of picked, item 2 of picked, item 3 of picked)
	on error errMsg number errNum
		if errNum is -128 then return -- user pressed Cancel
		display alert "Cascade failed" message errMsg & " (" & errNum & ")" as critical
	end try
end cascadeWithPicker

-- Double-click on the icon: cascade every window at the saved size, no dialog.
-- Doesn't activate Cascade unless an alert has to be shown, so keyboard focus
-- stays with the app you were using.
on cascadeAll()
	try
		set wins to my collectWindows()
		set n to count of (labels of wins)
		if n is 0 then
			my showNoWindowsAlert(firstErr of wins)
			return
		end if
		set dims to my parseSize(my loadSize()) -- loadSize only returns valid sizes
		set chosenIdx to {}
		repeat with i from 1 to n
			set end of chosenIdx to i
		end repeat
		my cascadeChosen(wins, chosenIdx, item 1 of dims, item 2 of dims)
	on error errMsg number errNum
		my bringToFront()
		display alert "Cascade failed" message errMsg & " (" & errNum & ")" as critical
	end try
end cascadeAll

-- Lists every window of every visible, non-background app via System Events.
-- Returns {labels, pids, idx, titles, firstErr}: parallel lists with the
-- "App - Title" label, the process's unix id, the window's index in its app,
-- and its title ("" if none); firstErr is the first error hit while reading
-- a window list (usually missing Accessibility permission), or "".
on collectWindows()
	set windowLabels to {}
	set windowPids to {}
	set windowIdx to {}
	set windowTitles to {}
	set firstWinErr to ""
	
	tell application "System Events"
		set procList to every application process whose background only is false and visible is true
		repeat with p in procList
			set pName to name of p
			set pid to unix id of p
			set winList to {}
			try
				set winList to every window of p
			on error m number n
				if firstWinErr is "" then set firstWinErr to pName & ": " & m & " (" & n & ")"
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
	return {labels:windowLabels, pids:windowPids, idx:windowIdx, titles:windowTitles, firstErr:firstWinErr}
end collectWindows

-- Shown when collectWindows() found nothing; errText is its firstErr
on showNoWindowsAlert(errText)
	my bringToFront()
	set msg to "Couldn't see any open windows. Make sure Cascade has Accessibility permission (System Settings > Privacy & Security > Accessibility). After a rebuild, remove Cascade from that list with the minus button and add it again."
	if errText is not "" then set msg to msg & return & return & "First error: " & errText
	set r to display alert "No windows found" message msg as warning buttons {"OK", "Open Accessibility Settings"} default button "Open Accessibility Settings"
	if button returned of r is "Open Accessibility Settings" then open location "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
end showNoWindowsAlert

-- Moves and resizes the windows at chosenIdx (indices into the lists from
-- collectWindows) to winW x winH, one cascade per display. Errors are
-- collected per window and shown in one summary alert at the end.
on cascadeChosen(wins, chosenIdx, winW, winH)
	set windowLabels to labels of wins
	set windowPids to pids of wins
	set windowIdx to idx of wins
	set windowTitles to titles of wins
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
		set i to idxRef as integer
		set lblText to item i of windowLabels
		set pid to item i of windowPids
		set wi to item i of windowIdx
		set wTitle to item i of windowTitles
		
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
		my bringToFront()
		display alert "Some windows couldn't be cascaded" message failText as warning
	end if
end cascadeChosen

-- ===========================================================================
-- Saved size
-- ===========================================================================

-- The preferences domain is always com.morgadoj.cascade (inspect it with
-- `defaults read com.morgadoj.cascade`). Inside the app that is the standard
-- domain; under osascript it has to be opened by name. (Opening the app's own
-- bundle id by name from inside the app is not allowed, hence the branch.)
on prefs()
	set bid to current application's NSBundle's mainBundle()'s bundleIdentifier()
	if bid is not missing value and (bid as text) is appBundleId then return current application's NSUserDefaults's standardUserDefaults()
	return current application's NSUserDefaults's alloc()'s initWithSuiteName:appBundleId
end prefs

-- The saved size as text, e.g. "1200x800"; defaultSize if none is saved or the
-- saved value doesn't parse, so a bad value can never break a cascade.
on loadSize()
	try
		set v to (my prefs()'s stringForKey:sizeKey)
		if v is not missing value then
			set t to v as text
			if my parseSize(t) is not missing value then return t
		end if
	end try
	return defaultSize
end loadSize

-- Saves t (already validated, e.g. "1500x900") as the size for double-click
on saveSize(t)
	my prefs()'s setObject:t forKey:sizeKey
end saveSize

-- Menu > Size... (main thread): ask for a new size, validate it, save it.
-- Loops on invalid input; Cancel leaves the saved size unchanged.
on askForSize()
	my bringToFront()
	set sizeText to my loadSize()
	set usage to "Double-click the menu bar icon to cascade all windows at this size."
	set prompt to "Window size for cascading (W x H)." & return & usage
	repeat
		try
			set r to display dialog prompt default answer sizeText buttons {"Cancel", "Save"} default button "Save" cancel button "Cancel" with title "Cascade"
		on error number -128 -- user pressed Cancel
			return
		end try
		set sizeText to text returned of r
		set dims to my parseSize(sizeText)
		if dims is missing value then
			set prompt to "Enter the size as width x height, for example 1200x800 (minimum 100x100)." & return & usage
		else
			my saveSize((item 1 of dims as text) & "x" & (item 2 of dims as text))
			return
		end if
	end repeat
end askForSize

-- ===========================================================================
-- Run at Startup
-- ===========================================================================
-- Primary: SMAppService's mainAppService (macOS 13+), which lists Cascade
-- under System Settings > General > Login Items. If registering fails (for
-- example because of the ad-hoc signature), fall back to a LaunchAgent in
-- ~/Library/LaunchAgents that runs `open -a <this app>` at login.
-- All of these run on the main thread (called from the menu).

-- Path of the fallback LaunchAgent plist
on launchAgentPath()
	return (POSIX path of (path to home folder)) & "Library/LaunchAgents/" & appBundleId & ".login.plist"
end launchAgentPath

-- The real state, read from the system each time:
--   "on"       login item enabled, or the LaunchAgent plist exists
--   "approval" registered but switched off / not yet allowed in System Settings
--   "off"      neither
-- SMAppService status: 0 not registered, 1 enabled, 2 requires approval,
-- 3 not found.
on runAtStartupState()
	set svcStatus to my loginItemStatus()
	if svcStatus is 1 then return "on"
	if ((current application's NSFileManager's defaultManager()'s fileExistsAtPath:(my launchAgentPath())) as boolean) then return "on"
	if svcStatus is 2 then return "approval"
	return "off"
end runAtStartupState

-- SMAppService status of this app, or 0 if the class isn't available (the
-- LaunchAgent check in runAtStartupState() then decides on its own)
on loginItemStatus()
	try
		return ((current application's SMAppService's mainAppService()'s status()) as integer)
	on error
		return 0
	end try
end loginItemStatus

-- Tells the user that macOS wants Run at Startup approved and opens Login Items
on showApprovalNeeded()
	my bringToFront()
	display alert "Allow Cascade to run at startup" message "macOS needs your approval. In Login Items, switch Cascade on under \"Open at Login\" or \"Allow in the Background\"." as informational
	current application's SMAppService's openSystemSettingsLoginItems()
end showApprovalNeeded

-- Turns Run at Startup on (enable true) or off. Every failure ends in an alert.
on setRunAtStartup(enable)
	set svc to current application's SMAppService's mainAppService()
	if enable then
		set {ok, theError} to svc's registerAndReturnError:(reference)
		if ok as boolean then
			if ((svc's status()) as integer) is 2 then my showApprovalNeeded()
			return
		end if
		-- SMAppService refused: use a LaunchAgent instead
		set smErr to "unknown error"
		if theError is not missing value then set smErr to (theError's localizedDescription()) as text
		-- Launch by path rather than bundle id: a copy in builds/ or on the DMG
		-- has the same id. If the app is moved later, turn this off and on again.
		set appPath to (current application's NSBundle's mainBundle()'s bundlePath()) as text
		set agent to current application's NSDictionary's dictionaryWithDictionary:{|Label|:appBundleId & ".login", |ProgramArguments|:{"/usr/bin/open", "-a", appPath}, |RunAtLoad|:true}
		set agentDir to (POSIX path of (path to home folder)) & "Library/LaunchAgents"
		current application's NSFileManager's defaultManager()'s createDirectoryAtPath:agentDir withIntermediateDirectories:true attributes:(missing value) |error|:(missing value)
		if not ((agent's writeToFile:(my launchAgentPath()) atomically:true) as boolean) then
			my bringToFront()
			display alert "Couldn't turn on Run at Startup" message "Login item: " & smErr & return & "LaunchAgent: couldn't write " & my launchAgentPath() as critical
		end if
	else
		set failText to ""
		set svcStatus to (svc's status()) as integer
		if svcStatus is 1 or svcStatus is 2 then -- only a registered item can be unregistered
			set {ok, theError} to svc's unregisterAndReturnError:(reference)
			if not (ok as boolean) then
				set failText to "Login item: unknown error"
				if theError is not missing value then set failText to "Login item: " & ((theError's localizedDescription()) as text)
			end if
		end if
		set fm to current application's NSFileManager's defaultManager()
		if (fm's fileExistsAtPath:(my launchAgentPath())) as boolean then
			if not ((fm's removeItemAtPath:(my launchAgentPath()) |error|:(missing value)) as boolean) then set failText to failText & return & "LaunchAgent: couldn't remove " & my launchAgentPath()
		end if
		if failText is not "" then
			my bringToFront()
			display alert "Couldn't turn off Run at Startup" message failText as critical
		end if
	end if
end setRunAtStartup

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

-- Builds and runs the picker (main thread only). windowLabels: one label per
-- window; the size field is pre-filled from pickerSize. Returns as above.
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
	sizeField's setStringValue:pickerSize
	
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
			theAlert's setInformativeText:"Enter the size as width x height, for example 1200x800 (minimum 100x100)."
		else if (count of chosenIdx) is 0 then
			theAlert's setInformativeText:"Select at least one window to cascade."
		else
			return {chosenIdx, item 1 of dims, item 2 of dims}
		end if
	end repeat
end showPicker

-- All / None button actions (main thread, while the picker is open)
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

-- Returns t with every findStr replaced by replStr
on replaceText(t, findStr, replStr)
	set AppleScript's text item delimiters to findStr
	set parts to text items of t
	set AppleScript's text item delimiters to replStr
	set r to parts as text
	set AppleScript's text item delimiters to ""
	return r
end replaceText
