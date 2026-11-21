@echo off
rem Starts bsg on Windows: bsg.bat whoami. Build once with mvnw.cmd -q package
rem (Java 21, JAVA_HOME set). See README.md. Messages are plain ASCII here on
rem purpose, the Windows console reads .bat files in its own code page.
setlocal
set "BSG_DIR=%~dp0"
set "BSG_JAR=%BSG_DIR%target\bsg.jar"
if not exist "%BSG_JAR%" (
  echo bsg ist noch nicht gebaut. Bitte im Ordner %BSG_DIR% ausfuehren: mvnw.cmd -q package 1>&2
  exit /b 2
)
set "BSG_JAVA="
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "BSG_JAVA=%JAVA_HOME%\bin\java.exe"
if not defined BSG_JAVA (
  where java >nul 2>nul && set "BSG_JAVA=java"
)
if not defined BSG_JAVA (
  echo Kein Java 21 gefunden. Bitte installieren, z. B. winget install EclipseAdoptium.Temurin.21.JDK 1>&2
  exit /b 2
)
"%BSG_JAVA%" -jar "%BSG_JAR%" %*
exit /b %ERRORLEVEL%
