# Code-signing the Windows package

The package `build/win/package-shell.ps1` produces is unsigned by default.
This is what to do about that, and what it buys.

## Why, exactly

Not the SmartScreen dialog. **Smart App Control.**

- **Smart App Control** blocks "malware, PUA, and unknown, *unsigned* code".
  Where its intelligence service has no opinion about a file — which is every
  build of ours — it still allows one **signed by a CA in the Microsoft
  Trusted Root Program**
  ([overview](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview)).
  Unsigned, this package cannot run on a SAC machine at all. Signed, it can.
  That is the whole return on the money.
- **SmartScreen** still prompts. Reputation accrues per **file hash** and per
  **publisher certificate**, over "several weeks and hundreds of clean
  installs"; there is no submission process for consumer machines, and **EV
  no longer bypasses it**
  ([reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).
  Signing every release with the *same* identity is what makes that
  reputation accumulate instead of resetting per build.

The Microsoft Store would remove the prompt entirely and is not open to us: a
Winlogon `Shell=` replacement cannot be an MSIX-packaged app.

## Which certificate

**Azure Artifact Signing** (formerly Trusted Signing) — $9.99/month Basic,
5,000 signatures, no hardware token, works from CI. Public Trust certificates
need an identity validation:

- **Organizations**: US, Canada, EU, UK, Australia, New Zealand, Japan, South
  Korea, Singapore, Switzerland, Norway, Israel — with **at least three years
  of verifiable operating history**.
- **Individual developers**: US and Canada only, and onboarding has been
  paused during the preview at times.

The fallback, if validation is not available, is an ordinary **OV
certificate** (~$220–400/yr). Since June 2023 its private key must live on
FIPS 140-2 Level 2 hardware, so it arrives as a USB token in the post —
awkward for a build box, which is what the cloud signing add-ons (SSL.com
eSigner, DigiCert KeyLocker) exist to solve. Certificates now expire after
**460 days** at most. EV costs more and buys nothing here.

## One-time setup

Everything except the identity validation can be done from the CLI; the
validation is portal-only.

```powershell
az provider register --namespace Microsoft.CodeSigning
az extension add --name artifact-signing
az group create --name starling-signing --location eastus
az artifact-signing create -n StarlingSigning -l eastus -g starling-signing --sku Basic
```

Then in the portal, on that account:

1. **Identity validations → Organization → New identity → Public.** You need
   the **Artifact Signing Identity Verifier** role first, or the button is
   greyed out with no explanation.
2. Fill in the legal entity: name, website on the entity's own domain, a
   monitored **primary** and **secondary** email *on that domain*, business
   identifier, business address, and the name of the person who will present
   ID — exactly as it appears on their government-issued document.
3. **Check the Certificate subject preview.** That string is what users see
   in the SmartScreen dialog and in file properties for as long as this
   identity lives.
4. The named individual completes a Verified ID check (AU10TIX: email PIN,
   phone, then a QR scan and a photo of the ID from a phone).
5. Processing takes **1 to 20 business days**, longer if documents are
   requested. Submitted documents must be less than 12 months old and valid
   for at least two more.
6. **Certificate profiles → Create → Public Trust**, pointing at that
   identity validation. (A **Public Trust Test** profile signs with a
   non-public root — useful for rehearsing the pipeline while the real
   validation is still in progress.)
7. Assign **Artifact Signing Certificate Profile Signer** to whoever signs —
   for CI, the service principal, not a person.

## The build box

```powershell
winget install -e --id Microsoft.Azure.ArtifactSigningClientTools
```

That pulls the dlib, the .NET 8 runtime and the VC++ redistributable. Then a
`metadata.json` next to the packager:

```json
{
  "Endpoint": "https://eus.codesigning.azure.net",
  "CodeSigningAccountName": "StarlingSigning",
  "CertificateProfileName": "StarlingPublicTrust"
}
```

and:

```powershell
.\build\win\package-shell.ps1 -Sign -SigningMetadata C:\signing\metadata.json
```

An OV certificate on a token instead: `-Sign -CertThumbprint <sha1>`. Both
paths run the same signtool line, differing only in the credential flag.

Authentication is `DefaultAzureCredential` — `az login` interactively, or
`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_CLIENT_SECRET` in CI. Adding
`"ExcludeCredentials"` to the metadata skips the methods that would be tried
and fail first.

## What gets signed

Every PE in the package that is **not already validly signed** — currently 25
files: `WinShellBar.exe`, the two engine DLLs, and the whole Swift runtime.
The 10 MSVC redistributables carry Microsoft's own signature and are left
alone; re-signing them would replace a better signature and burn quota.

Signing the Swift runtime is not optional thoroughness. **SAC judges every
binary a process loads**, so a signed exe beside unsigned DLLs produces
*"Smart App Control has blocked part of this app"* — a worse bug report than
a clean refusal.

Order matters and the packager gets it right: the payload is signed **before**
the zip, the setup exe **after** iexpress builds it. A signature is the last
write to a file; anything that rewrites the file afterwards destroys it.

**Not yet signed: `Install.ps1` and `Uninstall.ps1`.** PowerShell scripts take
a text signature block, which signtool cannot produce — that needs
`Set-AuthenticodeSignature` or the `ArtifactSigning` PowerShell module. Until
then the install instructions have to keep saying `-ExecutionPolicy Bypass`,
which is a bad habit to teach in an installer.

## Traps

- **The endpoint must match the account's region.** A mismatch is a `403
  Forbidden` and an internal `SignerSign()` failure — it reads like an
  authentication problem, not a typo in a URL.
- **Artifact Signing certificates are valid for THREE DAYS.** The timestamp
  is not belt-and-braces, it is the only reason a signature outlives the
  week. `http://timestamp.acs.microsoft.com` is Microsoft's, and the
  packager's default.
- **An identity validation cannot be edited.** Getting the legal name or
  address wrong means a whole new validation, which affects the certificates
  already signing under the old one.
- **SignTool must be 10.0.22621.755 or newer**; the 20348 SDK is explicitly
  unsupported by the dlib, and choosing it fails in a way that looks like
  credentials.
- **Never change signing identity casually.** Publisher reputation is one of
  the two SmartScreen signals; switching CAs resets it to zero.
