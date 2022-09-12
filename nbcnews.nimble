# Package

version       = "1.0.6"
author        = "Thiago Navarro"
description   = "NBC News scraper"
license       = "gpl-3.0-only"
installExt    = @["nim"]
srcDir        = "src"

bin = @["nbcnews"]
binDir = "build"

# Dependencies

requires "nim >= 1.6.4"
requires "https://github.com/thisago/useragent"
requires "util"

# CLI
requires "cligen"

task buildRelease, "Builds the release version of CLI":
  exec "nimble -d:release build"

task genDocs, "Generate documentation":
  exec "rm -r docs; nim doc -d:usestd --git.commit:master --git.url:https://github.com/thisago/nbcnews --project -d:ssl --out:docs ./src/nbcnews.nim"
