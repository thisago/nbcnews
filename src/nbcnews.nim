import nbcnews/extractor
export extractor

when isMainModule:
  from std/asyncdispatch import waitFor
  import std/jsonutils
  from std/json import `$`

  proc cli(url: string) =
    echo (waitFor getNbcPage url).toJson
    
  import cligen
  dispatch cli
