Minecraft Bedrock - Setup & Online Play Doctor
==============================================

Contents of this folder
-----------------------
  Minecraft-Bedrock-Setup.bat   the whole tool (batch + embedded PowerShell)
  README.txt                    this file

SHA-256 of Minecraft-Bedrock-Setup.bat
  685b06e6b1d5fcc5deca7f8fb50f2bb6d9510959b4791008b52a075c931a2f89

How to use
----------
  1. Download Minecraft-Bedrock-Setup.bat
  2. Right-click it -> Run as administrator (or double-click; it offers to elevate)
  3. Choose 1 for the health check, then 3 to fix online play

It is plain text. Right-click -> Edit opens it in Notepad, so you can read every
line before running it. Windows SmartScreen may warn about an unknown publisher
because the file is unsigned - verify the SHA-256 above.

What is NOT in this folder, on purpose
------------------------------------
  No crack. No 'onlinefix' jar. No patched DLL. No licence bypass.

A Store trial cannot be turned into the full game with a file drop. Microsoft checks
the entitlement for your Microsoft account on their servers at every sign-in - that
is exactly why patched copies can play single player but cannot join worlds or
servers. Shipping or using such a patch is piracy, so this project does not do it.

What does work
--------------
  * Own Minecraft for Windows on the account you sign in with (Store or Xbox app),
    then run this tool - option 1 tells you what is blocking online play, option 3
    fixes the common causes (Xbox services, Teredo/NAT, hosts-file blocks, firewall
    block rules, clock drift, proxy/VPN).
  * Use the free trial offline for single player only - that is its designed limit.

Requirements
------------
  Windows 10 version 2004 (build 19041) or newer. Nothing to install.

License: MIT (see ../LICENSE)
