@echo off
setlocal

if not exist build mkdir build
cargo build --release
if errorlevel 1 exit /b %errorlevel%
cargo test --release
if errorlevel 1 exit /b %errorlevel%
copy target\release\hello.exe build\hello.exe
if errorlevel 1 exit /b %errorlevel%
