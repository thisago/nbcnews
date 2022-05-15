import nbcnews/main
export main

when isMainModule:
  from std/asyncdispatch import waitFor
  import std/jsonutils
  from std/json import `$`

  proc cli(url: string) =
    var opts = initToJsonOptions()
    opts.enumMode = EnumMode.joptEnumString
    echo (waitFor getNbcPage(url)).toJson opts
    
  import cligen
  dispatch cli
