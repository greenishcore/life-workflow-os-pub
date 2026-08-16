-- reminders2obsidian.scpt — 读取 Apple 提醒事项并输出 Markdown（到 stdout）
-- 用法: osascript reminders2obsidian.scpt [列表名] [--all]
--   默认导出「提醒事项」列表中未完成项；--all 导出全部（含已完成）
on run argv
	set listName to "提醒事项"
	set includeDone to false
	if (count of argv) >= 1 then set listName to item 1 of argv
	if (count of argv) >= 2 then
		if item 2 of argv is "--all" then set includeDone to true
	end if

	set outLines to {}
	tell application "Reminders"
		set theList to list listName
		set theReminders to reminders of theList
		repeat with aReminder in theReminders
			set n to name of aReminder
			set isDone to completed of aReminder
			set theDue to due date of aReminder
			set theBody to body of aReminder
			if (not isDone) or includeDone then
				set l to ""
				if isDone then
					set l to "- [x] " & n
				else
					set l to "- [ ] " & n
				end if
				if theDue is not missing value then
					set l to l & " 📅 " & (theDue as string)
				end if
				if theBody is not missing value and theBody is not "" then
					set l to l & " — " & theBody
				end if
				set end of outLines to l
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	set outText to outLines as string
	set AppleScript's text item delimiters to ""
	return outText
end run
