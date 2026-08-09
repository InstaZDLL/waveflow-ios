# Security Policy

Thank you for reporting security vulnerabilities responsibly before any public
disclosure.

## Supported Versions

WaveFlow for iOS does not have long-term version support yet. The main branch
and the latest published release should be considered the only supported
versions for security fixes.

| Version                                           | Supported |
| ------------------------------------------------- | --------- |
| `main` / latest published release                 | Yes       |
| Older versions, snapshots, and unmaintained forks | No        |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Use one of these channels, depending on what is available on the public
repository:

1. **GitHub Security Advisories**: open the repository's _Security_ tab, then
   choose _Report a vulnerability_. This is the recommended confidential
   channel.
2. Contact the maintainers privately if GitHub Security Advisories are not
   available.

Your report should include:

- the affected version (or commit) and the iOS version you ran it on;
- a description of the vulnerability and its impact;
- reproduction steps, and a sample file if the issue is triggered by one;
- any suggested fix, if you have one.

Please allow a reasonable delay for a fix before public disclosure.

## Scope

Things that are in scope for this repository:

- reading and parsing audio files from the app's `Documents` folder — malformed
  or hostile tags, artwork, and container structures;
- anything that could let a file escape the app sandbox or overwrite data
  outside the app container;
- the future WaveFlow server sync (signed URLs, credential handling) once it
  lands.

Out of scope:

- vulnerabilities in Apple's own frameworks (report those to Apple);
- issues that require a jailbroken device or physical access to an unlocked
  phone;
- the desktop and Android clients — report those on their own repositories.
