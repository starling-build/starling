-- Opens one .pptx in Microsoft PowerPoint and reports what happened; driven by test/pptx-powerpoint.sh.
on run argv
  set f to item 1 of argv
  set docName to do shell script "basename " & quoted form of f & " .pptx"
  do shell script "open -a 'Microsoft PowerPoint' " & quoted form of f
  set verdict to "clean"
  set detail to ""
  set n to -1
  repeat with i from 1 to 12
    delay 1
    tell application "System Events"
      tell process "Microsoft PowerPoint"
        repeat with w in windows
          set wn to name of w
          if wn is missing value then set wn to ""
          set txt to ""
          try
            set txt to (value of every static text of w) as string
          end try
          if txt contains "found a problem" then
            set verdict to "REPAIR"
          else if txt contains "can't read" or txt contains "cannot read" or txt contains "can’t read" then
            set verdict to "CANTREAD"
          else if wn is "Grant File Access" then
            set verdict to "GRANT"
          else if wn does not start with docName and wn is not "" then
            if verdict is "clean" then set verdict to "OTHERWIN"
          else if wn is "" and txt is not "" then
            if verdict is "clean" then set verdict to "ALERT"
          end if
          if txt is not "" then set detail to detail & " {" & wn & ": " & txt & "}"
        end repeat
      end tell
    end tell
    if verdict is not "clean" then exit repeat
    try
      with timeout of 5 seconds
        tell application "Microsoft PowerPoint"
          if (count of presentations) > 0 then set n to count slides of active presentation
        end tell
      end timeout
    end try
    if n ≥ 0 then exit repeat
  end repeat
  -- dismiss anything, then close
  repeat 3 times
    tell application "System Events"
      tell process "Microsoft PowerPoint"
        repeat with w in windows
          repeat with bn in {"Cancel", "OK", "No", "Don't Save", "Close"}
            try
              click button bn of w
            end try
          end repeat
        end repeat
      end tell
    end tell
    delay 1
  end repeat
  try
    with timeout of 10 seconds
      tell application "Microsoft PowerPoint" to close every presentation saving no
    end timeout
  end try
  set tabc to ASCII character 9
  set detail to do shell script "printf %s " & quoted form of detail & " | tr '\\n' ' '"
  return verdict & tabc & n & tabc & detail
end run
