@echo off
rem Hermes cannot exec a .sh on Windows (WinError 193), so the hook entry point
rem is batch and the matcher stays PowerShell like every other script here.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0mewai-hook.ps1"
if errorlevel 1 echo {"action":"block","message":"mewai: the policy hook could not run, so this read is not verifiable."}
