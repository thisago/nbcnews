# Package

version       = "1.0.4"
author        = "Thiago Navarro"
description   = "NBC News scraper"
license       = "gpl-3-only"
installExt    = @["nim"]
srcDir        = "src"

bin = @["nbcnews"]
binDir = "build"

# Dependencies

requires "nim >= 1.6.4"
requires "scraper"
requires "https://gitlab.com/lurlo/useragent"

# CLI
requires "cligen"

task buildRelease, "Builds the release version of CLI":
  exec "nimble -d:release build"
