import asyncdispatch
from std/json import parseJson, `{}`, getStr, JsonNode, items, hasKey, JNull,
                      getBool, getInt, getFloat 
from std/xmltree import XmlNode
from std/htmlparser import parseHtml
from std/httpclient import newAsyncHttpClient, newHttpHeaders, getContent, close
from std/tables import Table, `[]`, `[]=`, hasKey
from std/strutils import strip, join, Digits, parseInt

from pkg/scraper import findAll, text
from pkg/useragent import mozilla

const debugging = false

proc getNextData(html: XmlNode): JsonNode =
  parseJson html.findAll("script", {"id": "__NEXT_DATA__"}).text

type
  NbcHome* = ref object
    highlighted*: seq[NbcPost]
    byCategory*: GroupedPosts ## Example: politics
    byGroup*: GroupedPosts ## Example: top stories
    teases*: GroupedPosts
  GroupedPosts = Table[string, seq[NbcPost]]

  NbcPostKind* = enum
    pkArticle, pkVideo
  NbcPost* = ref object
    image*: NbcArticleImage
    topic*: NbcArticleTopic
    url*: string
    headline*: string
    datePublished*, dateCreated*, dateModified*: string ## TODO: parse date
    case kind: NbcPostKind
    of pkArticle:
      authors: seq[NbcArticleAuthor]
      breakingNews*: bool
      related: seq[NbcPost]
      subhead*: string
    of pkVideo:
      captions: NbcVideoCaption
      dateBroadcast*: string
      description*: string
      publisher*: string
      source*: string
      duration*: int ## seconds
      src*: seq[NbcVideoSource]
  NbcVideoSource* = ref object
    format*: string
    url*: string
    duration*: float ## seconds
    bitrate*: int
    width*, height*: int
  NbcVideoCaption* = ref object
    smptett*: string
    srt*: string
    webvtt*: string
  NbcArticleAuthor* = ref object
    name*: string
    url*: string
    image*: string
    isFeatured: bool
    job*: string
  NbcArticleTopic* = ref object
    name*: string
    url*: string
  NbcArticleImage* = ref object
    src*: string
    authors*: seq[string]
    publisher*: string
    source*: string
    alt*: string
    caption*: string

proc extractArticle(node: JsonNode): NbcPost =
  result = NbcPost(
    kind: pkArticle
  )
  let
    computedValues = node{"computedValues"}
    item = node{"item"}
    unibrow = computedValues{"unibrow"}
  result.headline = computedValues{"headline"}.getStr
  result.subhead = computedValues{"dek"}.getStr
  result.url = computedValues{"url"}.getStr

  result.topic = new NbcArticleTopic
  result.topic.name = unibrow{"text"}.getStr
  result.topic.url = unibrow{"url", "primary"}.getStr

  result.breakingNews = item{"breakingNews"}.getBool
  result.datePublished = item{"datePublished"}.getStr
  result.dateModified = item{"dateModified"}.getStr
  result.dateCreated = item{"dateCreated"}.getStr

  block authors:
    if node{"item"}.kind == JNull: break
    for a in item{"authors"}:
      let person = a{"person"}
      var author = new NbcArticleAuthor
      author.isFeatured = a{"featuredAuthor", "isFeaturedAuthor"}.getBool
      author.name = person{"name"}.getStr
      author.url = person{"url", "primary"}.getStr
      author.image = person{"primaryImage", "url", "primary"}.getStr

      var jobs: seq[string]
      for job in person{"jobTitle"}.items:
        jobs.add job.getStr
      author.job = jobs.join ", "

      result.authors.add author
      
  block image:
    let teaseImage = computedValues{"teaseImage"}
    if teaseImage.kind == JNull: break image
    result.image = new NbcArticleImage
    result.image.src = teaseImage{"url", "primary"}.getStr
    result.image.publisher = teaseImage{"publisher", "name"}.getStr
    result.image.source = teaseImage{"source", "name"}.getStr
    result.image.alt = teaseImage{"altText"}.getStr
    result.image.caption = teaseImage{"caption"}.getStr
    for author in teaseImage{"authors"}:
      result.image.authors.add author{"name"}.getStr

proc extractVideo(node: JsonNode): NbcPost =
  result = NbcPost(
    kind: pkVideo
  )
  let
    computedValues = node{"computedValues"}
    item = node{"item"}
    unibrow = computedValues{"unibrow"}
  result.headline = computedValues{"headline"}.getStr
  result.url = computedValues{"url"}.getStr

  result.topic = new NbcArticleTopic
  result.topic.name = unibrow{"text"}.getStr
  result.topic.url = unibrow{"url", "primary"}.getStr

  result.datePublished = item{"datePublished"}.getStr
  result.dateModified = item{"dateModified"}.getStr
  result.dateCreated = item{"dateCreated"}.getStr
  result.dateBroadcast = item{"dateBroadcast"}.getStr
  result.description = item{"description", "primary"}.getStr
      
  result.publisher = item{"publisher", "name"}.getStr
  result.source = item{"source", "name"}.getStr

  block duration:
    const
      secInMin = 60
      secInHour = secInMin * 60
    let str = item{"duration"}.getStr[2..^1]
    var strNum: string
    for ch in str:
      if ch in Digits:
        strNum.add ch
      else:
        let num = parseInt strNum
        case ch:
        of 'H': result.duration += num * secInHour
        of 'M': result.duration += num * secInMin
        of 'S': result.duration += num
        else: discard

  block image:
    let teaseImage = computedValues{"teaseImage"}
    if teaseImage.kind == JNull: break image
    result.image = new NbcArticleImage
    result.image.src = teaseImage{"url", "primary"}.getStr
    result.image.publisher = teaseImage{"publisher", "name"}.getStr
    result.image.source = teaseImage{"source", "name"}.getStr
    result.image.alt = teaseImage{"altText"}.getStr
    result.image.caption = teaseImage{"caption"}.getStr
    for author in teaseImage{"authors"}:
      result.image.authors.add author{"name"}.getStr

  block assets:
    for videoAsset in item{"videoAssets"}:
      var asset = new NbcVideoSource
      asset.bitrate = videoAsset{"bitrate"}.getInt
      asset.width = videoAsset{"width"}.getInt
      asset.height = videoAsset{"height"}.getInt
      asset.duration = videoAsset{"assetDuration"}.getFloat
      asset.url = videoAsset{"publicUrl"}.getStr
      asset.format = videoAsset{"format"}.getStr
      result.src.add asset

  block captions:
    if item{"hasCaptions"}.getBool:
      let closedCaptioning = item{"closedCaptioning"}
      result.captions = new NbcVideoCaption
      result.captions.smptett = closedCaptioning{"smptett"}.getStr
      result.captions.srt = closedCaptioning{"srt"}.getStr
      result.captions.webvtt = closedCaptioning{"webvtt"}.getStr


func addGrouped(group: var GroupedPosts; name: string; post: NbcPost) =
  var groupName = name.strip
  if not group.hasKey groupName:
    group[groupName] = @[]
  group[groupName].add post

# const jsonData = """"""
proc extractPost(node: JsonNode): NbcPost =
  case node{"type"}.getStr:
  of "article":
    result =  extractArticle node
  of "video":
    result =  extractVideo node
  else:
    return
  for related in node{"related"}:
    let relatedArticle = extractArticle related
    if not relatedArticle.isNil:
      result.related.add relatedArticle

proc getNbcPage*(url = "https://www.nbcnews.com/"): Future[NbcHome] {.async.} =
  ## Extracts the main page of NBC NEWS
  ## 
  ## Works with:
  ## - https://www.nbcnews.com
  ## - https://www.today.com
  ## - https://www.today.com/news
  ## - https://www.nbcnews.com/video
  ## - https://www.nbcnews.com/category
  new result
  let
    client = newAsyncHttpClient(headers = newHttpHeaders({
      "user-agent": mozilla
    }))
    html = parseHtml await client.getContent url
    data = html.getNextData
    # data = jsonData.parseJson

  for layout in data{"props", "initialState", "front", "curation", "layouts"}:
    for package in layout{"packages"}:
      for it in package{"items"}:
        var post = extractPost it
        if not post.isNil:
          case package{"type"}.getStr:
          of "threeUp", "oneUp", "leadSectionFront", "straightUp", "twoUp",
            "liveVideoEmbed", "coverSpread":
              result.highlighted.add post
          of "aLaCarte", "bacon", "feeds": result.byGroup.addGrouped(package{"name"}.getStr, post)
          of "pancake": result.byCategory.addGrouped(package{"name"}.getStr, post)
          of "teaseList": result.teases.addGrouped(package{"metadata", "title"}.getStr, post)
          else:
            when debugging:
              echo $(%*{
                "type": package{"type"}.getStr,
                "headline": post.headline
              })

  close client

when isMainModule:
  from std/json import pretty
  from std/jsonutils import toJson
  # echo (waitFor getNbcPage("https://www.nbcnews.com/news/world/mysterious-putin-ally-russian-gatsby-moves-billions-rcna23603")).toJson.pretty
  echo (waitFor getNbcPage("https://www.nbcnews.com")).toJson.pretty
