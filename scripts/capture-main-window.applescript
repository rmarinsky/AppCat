-- Captures the main AppCat DEV screens for Figma comparison.
--
-- Requirements:
-- 1. Grant Accessibility access to the terminal/Codex host that runs this script.
-- 2. Grant Screen Recording access to the same host for screencapture.
--
-- Usage:
--   osascript scripts/capture-main-window.applescript /tmp/appcat-captures

property screenSlugs : {"overview", "history", "suggestions", "general", "browsers", "apps", "rules", "shortcuts", "account"}

on run argv
    if (count of argv) > 0 then
        set outputDir to item 1 of argv
    else
        set outputDir to "/tmp/appcat-captures"
    end if

    do shell script "mkdir -p " & quoted form of outputDir

    tell application "AppCat DEV" to activate
    delay 0.8

    tell application "System Events"
        tell process "AppCat DEV"
            set frontmost to true
            delay 0.4

            if (count of windows) is 0 then error "AppCat DEV has no visible windows."
            set mainWindow to window 1

            set sidebarButtonCenters to {}
            repeat with elementRef in UI elements of group 1 of mainWindow
                if role of elementRef is "AXButton" then
                    set elementSize to size of elementRef
                    if (item 1 of elementSize) is greater than 180 and (item 2 of elementSize) is greater than 24 then
                        set elementPosition to position of elementRef
                        set centerX to (item 1 of elementPosition) + ((item 1 of elementSize) / 2)
                        set centerY to (item 2 of elementPosition) + ((item 2 of elementSize) / 2)
                        set end of sidebarButtonCenters to {round centerX, round centerY}
                    end if
                end if
            end repeat

            if (count of sidebarButtonCenters) < (count of screenSlugs) then error "Expected sidebar buttons were not found."

            repeat with itemIndex from 1 to count of screenSlugs
                click at item itemIndex of sidebarButtonCenters
                delay 0.5
                set outputPath to outputDir & "/" & (item itemIndex of screenSlugs) & ".png"
                do shell script "screencapture -x " & quoted form of outputPath
            end repeat
        end tell
    end tell
end run
