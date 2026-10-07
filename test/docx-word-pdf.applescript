-- Prints one .docx to a PDF through Microsoft Word's print dialog; driven by
-- test/docx-word-render.sh. Arguments: the document, the PDF to write.
--
-- Word's unlicensed read-only mode refuses a scripted `save as` (PDF export),
-- but it still prints, and the print dialog's PDF menu saves one — so this
-- drives that dialog: ⌘P, the PDF menu button, "Save as PDF…", the save
-- panel's name field (focused, selected), ⌘⇧G to the folder, Save. The save
-- panel is remote-hosted and shows System Events no controls, hence the
-- keystrokes. Prints: "pdf" or an error line.
on run argv
  set f to item 1 of argv
  set pdfPath to item 2 of argv
  set pdfDir to do shell script "dirname " & quoted form of pdfPath
  set pdfName to do shell script "basename " & quoted form of pdfPath & " .pdf"
  set docName to do shell script "basename " & quoted form of f & " .docx"
  do shell script "rm -f " & quoted form of pdfPath
  do shell script "open -a 'Microsoft Word' " & quoted form of f
  -- the document window, or a dialog instead of it
  set opened to false
  repeat with i from 1 to 20
    delay 1
    tell application "System Events"
      tell process "Microsoft Word"
        repeat with w in windows
          set wn to ""
          try
            set wn to name of w
          end try
          if wn is missing value then set wn to ""
          if wn starts with docName then set opened to true
          set txt to ""
          try
            set txt to (value of every static text of w) as string
          end try
          if txt contains "unreadable content" or txt contains "experienced an error" or txt contains "cannot be opened" then
            repeat with bn in {"No", "OK", "Cancel"}
              try
                click button bn of w
              end try
            end repeat
            return "error: Word refused " & docName
          else if txt contains "mail merge main document" then
            -- The data source is long gone; the document renders as a
            -- normal one. Nothing is saved in read-only mode.
            click button "Options..." of w
            delay 1.5
            repeat with w2 in windows
              try
                click button "Remove All Merge Info" of w2
              end try
            end repeat
            delay 2
          else if wn is "" and txt is not "" then
            -- Some other alert: say what it said, try to get past it.
            set bns to ""
            try
              set bns to (name of every button of w) as string
            end try
            repeat with bn in {"OK", "Cancel", "No", "Don't Save"}
              try
                click button bn of w
              end try
            end repeat
            key code 53
            delay 1
            return "error: alert on " & docName & ": " & txt & " [" & bns & "]"
          end if
        end repeat
      end tell
    end tell
    if opened then exit repeat
  end repeat
  if not opened then return "error: no document window for " & docName
  delay 1
  tell application "System Events"
    tell process "Microsoft Word"
      set frontmost to true
      keystroke "p" using command down
      -- the print dialog, and its PDF menu
      set ready to false
      repeat with i from 1 to 15
        delay 1
        -- "The paper size of section 1 is different from the printer's…":
        -- Continue prints it anyway, on the page the document asked for.
        repeat with w in windows
          set txt to ""
          try
            set txt to (value of every static text of w) as string
          end try
          if txt contains "paper size" then
            repeat with bn in {"Continue", "OK", "Yes"}
              try
                click button bn of w
              end try
            end repeat
          end if
        end repeat
        try
          if exists window "Print" then
            if exists menu button 1 of group 2 of splitter group 1 of window "Print" then set ready to true
          end if
        end try
        if ready then exit repeat
      end repeat
      if not ready then
        keystroke (ASCII character 27)
        return "error: no print dialog for " & docName
      end if
      click menu button 1 of group 2 of splitter group 1 of window "Print"
      delay 1
      click menu item "Save as PDF…" of menu 1 of menu button 1 of group 2 of splitter group 1 of window "Print"
      delay 2
      keystroke pdfName
      delay 0.5
      keystroke "g" using {command down, shift down}
      delay 1.5
      keystroke pdfDir
      delay 0.5
      keystroke return
      delay 2
      keystroke return
    end tell
  end tell
  -- the file, then the window
  set written to false
  repeat with i from 1 to 30
    delay 1
    try
      do shell script "test -s " & quoted form of pdfPath
      set written to true
      exit repeat
    end try
  end repeat
  delay 1
  tell application "System Events"
    tell process "Microsoft Word"
      repeat 4 times
        set fn to ""
        try
          set fn to name of front window
        end try
        if fn is missing value then set fn to ""
        if fn is "" or fn is "Word" then exit repeat
        keystroke "w" using command down
        delay 1
      end repeat
    end tell
  end tell
  if written then return "pdf"
  return "error: no PDF written for " & docName
end run
