Lab hiddenline (lenovo-3, for macos): the line height Word for Windows gives a paragraph whose text is all
hidden, all deleted or both, with a normal, hidden or deleted mark, at 10, 12 and 16pt.
Print the six documents in docx/ (word-win mode). See build.py's header for how to read them.
Why: lo-ec231ad7 (merge_hidden_redline) — Word keeps a full line for such a paragraph (31pt between
"1 hidden" and "2 visible" where ours leaves 21); the board entry has the details.
