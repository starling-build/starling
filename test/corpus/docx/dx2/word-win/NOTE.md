# Word for Windows prints of dx2 (Windows 01QbbApP)

Source: 1,808 docs copied to ~/starling-doc-check/lab/corpusdx2/docs by starling-bd; c5a706a26cf1* (a 195-page report,
removed from the set) was skipped, leaving 1,807 to print. One fresh Word per document, 4-way, 8 s settle, warm doc first,
NO cloud-font warm-up pass. 10,476 s for the first pass = 5.8 s/doc. PDFs stay local in
~/starling-doc-check/lab/corpusdx2/docs/<id>-orig.pdf; 1,798 of 1,807 printed (482 MB).
PAGES-DX2.tsv: id, Word page count, PDF sha256 (8,172 pages in all).

## Word could not print 9 documents (each also failed on a retry on its own, so none is a parallelism effect)
- 08f7a4b8024abeb7d6bfdba7bccb04a92f4b3f0e138ba74dbcb8bc52eef096fb — "The export failed due to an unexpected error."
- 23d25d1af2bf1644818528fa1ad0d0b4945c01371537712f2545e441a5ceb9b3 — "The export failed due to an unexpected error."
- 2fedd8febe62434b64e9d8823c6c26eefd9ab7037c3388a6e2e6f95decdf5932 — "The file appears to be corrupted."
- c796dabca60f1a5c1d1e14ada388a29b878886968ec1a55696e80f8ac3ee6067 — "The file appears to be corrupted."
- e70c536011713e418791154bec2f017f8b412db72eed4ab1c80b63354d0406e7 — "The file appears to be corrupted."
- 731809971e4447b188826396db0af4e545517a40257ad8d8c6e8794a0cea15b7 — "The RPC server is unavailable (0x800706BA)"; on the retry Word hung for the 420 s watchdog first.
- dde391cf89ba956c199581f8623c2177c19e14b9efa7911465df9af35d832428 — "The remote procedure call failed (0x800706BE)"; hung for the 420 s watchdog on the retry too.
- bf6b250add4f80f25589a3d5e19500d328a78e1bb5aa71d6327658e247d68cc3 — "Call was rejected by callee (RPC_E_CALL_REJECTED)", again on the retry.
- f88bd7ecf2c0da6a975e09b24f810e6adfbe54450c6a6ee764ec66ac99c9c5cd — "Call was rejected by callee (RPC_E_CALL_REJECTED)", again on the retry.

Repair prompts: none seen. Timeouts: none in the main pass (the watchdog fired only on the two retries named above).
Printed before the cloud-font warm-up round, so some prints may still change in the combined second round.
