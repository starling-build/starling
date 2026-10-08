-- Opens one .pptx in Microsoft PowerPoint and has PowerPoint export it as a
-- PDF; driven by test/pptx-powerpoint-render.sh. Arguments: the deck, the
-- PDF to write. The PDF must land in a folder under $HOME that PowerPoint's
-- sandbox has been granted once (the "Grant File Access" dialog); /tmp and
-- the scratchpad get nothing. A deck PowerPoint asks to repair is repaired
-- and still exported, and the verdict says so, because what PowerPoint draws
-- after its own repair is still the picture to compare against. Prints one
-- of: "pdf", "pdf repaired", or "error: …".
on run argv
  set f to item 1 of argv
  set pdfPath to item 2 of argv
  set docName to do shell script "basename " & quoted form of f & " .pptx"
  do shell script "rm -f " & quoted form of pdfPath
  do shell script "open -a 'Microsoft PowerPoint' " & quoted form of f
  set repaired to false
  set opened to false
  set n to -1
  -- 45 s: a deck with an external sound at an unroutable address
  -- (lo-animation-sound-external) keeps PowerPoint busy past 20.
  repeat with i from 1 to 45
    delay 1
    tell application "System Events"
      tell process "Microsoft PowerPoint"
        repeat with w in windows
          set wn to ""
          try
            set wn to name of w
          end try
          if wn is missing value then set wn to ""
          set txt to ""
          try
            set txt to (value of every static text of w) as string
          end try
          if txt contains "found a problem" then
            -- "PowerPoint found a problem with content… can attempt to repair"
            set repaired to true
            try
              click button "Repair" of w
            end try
          else if txt contains "can't read" or txt contains "cannot read" or txt contains "can’t read" or txt contains "cannot be opened" then
            repeat with bn in {"OK", "Cancel"}
              try
                click button bn of w
              end try
            end repeat
            return "error: PowerPoint refused " & docName
          else if wn is "Grant File Access" then
            return "error: grant file access for the output folder first"
          else if wn is "" and txt is not "" then
            -- Some other alert (fonts, links, macros): get past it.
            repeat with bn in {"OK", "Cancel", "No", "Don't Update", "Continue"}
              try
                click button bn of w
              end try
            end repeat
          end if
        end repeat
      end tell
    end tell
    try
      with timeout of 5 seconds
        tell application "Microsoft PowerPoint"
          if (count of presentations) > 0 then set n to count slides of active presentation
        end tell
      end timeout
    end try
    if n ≥ 0 then
      set opened to true
      exit repeat
    end if
  end repeat
  if not opened then
    try
      with timeout of 10 seconds
        tell application "Microsoft PowerPoint" to close every presentation saving no
      end timeout
    end try
    return "error: no presentation after 45s (" & docName & ")"
  end if
  set verdict to "pdf"
  try
    with timeout of 120 seconds
      tell application "Microsoft PowerPoint"
        save active presentation in POSIX file pdfPath as save as PDF
      end tell
    end timeout
  on error msg
    set verdict to "error: export: " & msg
  end try
  -- Export can leave the sandbox prompt or a save sheet; dismiss what we can.
  repeat 2 times
    tell application "System Events"
      tell process "Microsoft PowerPoint"
        repeat with w in windows
          set wn to ""
          try
            set wn to name of w
          end try
          if wn is missing value then set wn to ""
          if wn is "Grant File Access" then set verdict to "error: grant file access for the output folder first"
          repeat with bn in {"Cancel", "OK", "No", "Don't Save"}
            try
              click button bn of w
            end try
          end repeat
        end repeat
      end tell
    end tell
    delay 0.5
  end repeat
  try
    with timeout of 10 seconds
      tell application "Microsoft PowerPoint" to close every presentation saving no
    end timeout
  end try
  if verdict is "pdf" and repaired then set verdict to "pdf repaired"
  if verdict is "pdf" or verdict is "pdf repaired" then
    set there to do shell script "test -s " & quoted form of pdfPath & " && echo yes || echo no"
    if there is "no" then set verdict to "error: PowerPoint wrote no PDF (sandbox? " & docName & ")"
  end if
  return verdict
end run
