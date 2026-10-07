-- Opens one .docx in Microsoft Word and reports what happened; driven by
-- test/docx-word.sh. Prints: verdict TAB paragraph-count TAB dialog text.
-- Verdicts as test/pptx-powerpoint.applescript's: clean, REPAIR ("Word found
-- unreadable content…", Yes/No to recover), CANTREAD, GRANT (the sandbox
-- asked for access), OTHERWIN/ALERT (anything else).
--
-- Only windows that APPEAR for this file are judged: Word's gallery window
-- ("Word") and any document left open are in the snapshot taken first.
-- Opened through Launch Services, which grants the sandbox read access that
-- a scripted open does not; closed with ⌘W through System Events, because
-- in Word's unlicensed read-only mode `close every document` returns and
-- closes nothing.
on run argv
  set f to item 1 of argv
  set docName to do shell script "basename " & quoted form of f & " .docx"
  set priorNames to {}
  tell application "System Events"
    tell process "Microsoft Word"
      repeat with w in windows
        set wn to name of w
        if wn is missing value then set wn to ""
        set end of priorNames to wn
      end repeat
    end tell
  end tell
  do shell script "open -a 'Microsoft Word' " & quoted form of f
  set verdict to "clean"
  set detail to ""
  set n to -1
  set sawDoc to false
  repeat with i from 1 to 20
    delay 1
    tell application "System Events"
      tell process "Microsoft Word"
        repeat with w in windows
          set wn to name of w
          if wn is missing value then set wn to ""
          set txt to ""
          try
            set txt to (value of every static text of w) as string
          end try
          if txt contains "unreadable content" or txt contains "recover the contents" or txt contains "found a problem" then
            set verdict to "REPAIR"
          else if txt contains "cannot be opened" or txt contains "can’t be opened" or txt contains "can't open" or txt contains "is corrupt" or txt contains "not a valid" then
            set verdict to "CANTREAD"
          else if wn is "Grant File Access" then
            set verdict to "GRANT"
          else if wn starts with docName then
            set sawDoc to true
          else if priorNames does not contain wn then
            if wn is "" and txt is not "" then
              if verdict is "clean" then set verdict to "ALERT"
            else if wn is not "" then
              if verdict is "clean" then set verdict to "OTHERWIN"
            end if
          end if
          if txt is not "" and (priorNames does not contain wn) then set detail to detail & " {" & wn & ": " & txt & "}"
        end repeat
      end tell
    end tell
    if verdict is not "clean" then exit repeat
    if sawDoc then
      delay 1
      try
        with timeout of 5 seconds
          tell application "Microsoft Word"
            if (count of documents) > 0 then set n to count paragraphs of active document
          end tell
        end timeout
      end try
      exit repeat
    end if
  end repeat
  -- dismiss anything (No = do not recover), then close what this file opened
  repeat 3 times
    tell application "System Events"
      tell process "Microsoft Word"
        repeat with w in windows
          repeat with bn in {"No", "Cancel", "OK", "Don't Save", "Close"}
            try
              click button bn of w
            end try
          end repeat
        end repeat
      end tell
    end tell
    delay 1
  end repeat
  tell application "System Events"
    tell process "Microsoft Word"
      repeat 6 times
        set frontName to ""
        try
          set frontName to name of front window
        end try
        if frontName is missing value then set frontName to ""
        if frontName is "" or frontName is "Word" or (priorNames contains frontName) then exit repeat
        set frontmost to true
        keystroke "w" using command down
        delay 1
      end repeat
    end tell
  end tell
  set tabc to ASCII character 9
  set detail to do shell script "printf %s " & quoted form of detail & " | tr '\\n' ' '"
  return verdict & tabc & n & tabc & detail
end run
