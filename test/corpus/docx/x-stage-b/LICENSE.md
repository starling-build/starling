# Licences of the staged documents (batch B)

Every file's source address, licence and SHA-256 are in `manifest.tsv`.
Licences present, with the file count:

- CC BY 4.0, CC BY-SA 4.0, CC BY 3.0, CC0: documents deposited on Zenodo
  (https://zenodo.org/records/<id>); the depositor states the licence on the
  record. Attribution = the record address in the manifest.
- Licence Ouverte 1.0 / 2.0 (Etalab): French public-sector files from
  data.gouv.fr datasets; attribution = the dataset page in the manifest.
- PDL 1.0 (Public Data License 1.0, compatible with CC BY 4.0): Japanese ministry
  files from mhlw.go.jp and digital.go.jp; the site-wide notice that applies
  is named in each manifest row. Pages may mark third-party content as
  excluded; we took the site notice at face value.
- MIT: test files from github.com/dolanmiu/docx.
- Apache-2.0: test files from github.com/plutext/docx4j.

Selection rules: no NC or ND licences, no interview/survey transcripts, no
files with e-mail addresses, no DATE/TIME fields, at most 40 pages.
The licence is the one the depositor or publisher states; we have not
verified that they hold the rights. If a rights holder asks, delete the
file and its manifest row.
