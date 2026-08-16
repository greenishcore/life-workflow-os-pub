-- calendar2md.scpt — 读取 Apple 日历（指定日历）未来 N 天事件，输出 Markdown 到 stdout
-- 用法: osascript calendar2md.scpt [日历名] [天数]
on run argv
	set calName to "个人"
	set daysAhead to 7
	if (count of argv) >= 1 then set calName to item 1 of argv
	if (count of argv) >= 2 then set daysAhead to (item 2 of argv as integer)

	set nowDate to current date
	set endDate to nowDate + (daysAhead * days)
	set outLines to {}
	tell application "Calendar"
		set theCal to calendar calName
		set evs to every event of theCal
		repeat with e in evs
			set stDate to start date of e
			if stDate is greater than or equal to nowDate and stDate is less than endDate then
				set summ to summary of e
				set enDate to end date of e
				set locText to location of e
				set l to "- " & (stDate as string) & " → " & (enDate as string) & " | " & summ
				if locText is not missing value and locText is not "" then
					set l to l & " @ " & locText
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
