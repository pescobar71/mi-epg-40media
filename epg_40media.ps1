$ErrorActionPreference = "Stop"

# --- Canales 40Media (JSON) ---
$Canales = [ordered]@{
  entchannel="ENT Channel"; entfamily="ENT Family"; totalmusic="Totalmusic"; totalmusic80s="Totalmusic 80s"
  totalmusic00s="Totalmusic 00s"; entmovies="ENT Movies"; entdrama="ENT Drama"; entclassic="ENT Classic"
  entlife="ENT Life"; entextreme="ENT Extreme"; entcomedy="ENT Comedy"
}
$Base = "https://api.40mediagroup.com/xmltv/programacion"
$Out  = Join-Path $PSScriptRoot "40media_epg.xml"
$H    = @{ referer = "https://www.40mediagroup.com/"; "user-agent" = "Mozilla/5.0" }

# --- Canales SoFast (XMLTV directo) ---
$SoFastCanales = [ordered]@{
  "TYC-SPORTS-FAN" = "TyC Sports FAN"
}
$SoFastBase = "https://epg.sofast.tv/api/ChannelXML/GetEpgXml"
$SoFastHours = 72

function XDate($d) {
  if ($d -is [string]) { $d = [DateTimeOffset]::Parse($d, [Globalization.CultureInfo]::InvariantCulture) }
  else { $d = [DateTimeOffset]$d }
  $d.ToUniversalTime().ToString("yyyyMMddHHmmss") + " +0000"
}
function Add-El($parent, $name, $text, $lang) {
  $e = $xml.CreateElement($name)
  if ($lang) { $e.SetAttribute("lang", $lang) }
  $e.InnerText = $text; [void]$parent.AppendChild($e)
}

[xml]$xml = '<?xml version="1.0" encoding="UTF-8"?><tv generator-info-name="epg-40media"></tv>'

# 1. Descarga de 40Media
$data = @{}
foreach ($id in $Canales.Keys) {
  try { $r = Invoke-RestMethod "$Base/$id/guia.json" -Headers $H -TimeoutSec 20 } catch { $r = $null }
  if ($r -and $r.programmes) { $data[$id] = $r.programmes; Write-Host "OK    $id ($($r.programmes.Count))" }
  else { Write-Host "VACIO $id" -ForegroundColor Yellow }
}

# 2. Descarga de SoFast (TyC Sports FAN)
$sofastData = @{}
foreach ($id in $SoFastCanales.Keys) {
  try {
    $resp = Invoke-WebRequest "$SoFastBase`?ChannelId=$id&DurationHours=$SoFastHours" -Headers @{ "user-agent" = "Mozilla/5.0" } -TimeoutSec 20
    [xml]$sfXml = $resp.Content
    $progs = $sfXml.SelectNodes("//programme")
    if ($progs -and $progs.Count -gt 0) {
      $sofastData[$id] = $progs
      Write-Host "OK    $id ($($progs.Count))"
    } else {
      Write-Host "VACIO $id" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "ERROR $id ($($_.Exception.Message))" -ForegroundColor Yellow
  }
}

# 3. Construcción de nodos <channel>
foreach ($id in $Canales.Keys) {
  if ($data[$id]) {
    $ch = $xml.CreateElement("channel"); $ch.SetAttribute("id", $id)
    Add-El $ch "display-name" $Canales[$id] $null; [void]$xml.tv.AppendChild($ch)
  }
}
foreach ($id in $SoFastCanales.Keys) {
  if ($sofastData[$id]) {
    $ch = $xml.CreateElement("channel"); $ch.SetAttribute("id", $id)
    Add-El $ch "display-name" $SoFastCanales[$id] $null; [void]$xml.tv.AppendChild($ch)
  }
}

# 4. Construcción de nodos <programme>
$total = 0
foreach ($id in $Canales.Keys) {
  foreach ($p in $data[$id]) {
    $pr = $xml.CreateElement("programme")
    $pr.SetAttribute("start", (XDate $p.start)); $pr.SetAttribute("stop", (XDate $p.stop)); $pr.SetAttribute("channel", $id)
    Add-El $pr "title" $p.title "es"
    if ($p.subtitle) { Add-El $pr "sub-title" $p.subtitle "es" }
    if ($p.desc)     { Add-El $pr "desc" $p.desc "es" }
    if ($p.category) { Add-El $pr "category" $p.category "es" }
    if ($p.icon)     { $i = $xml.CreateElement("icon"); $i.SetAttribute("src", $p.icon); [void]$pr.AppendChild($i) }
    [void]$xml.tv.AppendChild($pr); $total++
  }
}

foreach ($id in $SoFastCanales.Keys) {
  foreach ($p in $sofastData[$id]) {
    $pr = $xml.CreateElement("programme")
    $pr.SetAttribute("start", $p.GetAttribute("start"))
    $pr.SetAttribute("stop",  $p.GetAttribute("stop"))
    $pr.SetAttribute("channel", $id)

    $title = $p.SelectSingleNode("title")
    $sub   = $p.SelectSingleNode("sub-title")
    $desc  = $p.SelectSingleNode("desc")
    $cat   = $p.SelectSingleNode("category")
    $icon  = $p.SelectSingleNode("icon")

    if ($title -and $title.InnerText) { Add-El $pr "title" $title.InnerText "es" }
    if ($sub   -and $sub.InnerText)   { Add-El $pr "sub-title" $sub.InnerText "es" }
    if ($desc  -and $desc.InnerText)  { Add-El $pr "desc" $desc.InnerText "es" }
    if ($cat   -and $cat.InnerText)   { Add-El $pr "category" $cat.InnerText "es" }
    if ($icon  -and $icon.GetAttribute("src")) {
      $i = $xml.CreateElement("icon"); $i.SetAttribute("src", $icon.GetAttribute("src")); [void]$pr.AppendChild($i)
    }

    [void]$xml.tv.AppendChild($pr); $total++
  }
}

# 5. Guardado final
$s = New-Object Xml.XmlWriterSettings; $s.Indent = $true; $s.Encoding = New-Object Text.UTF8Encoding($false)
$w = [Xml.XmlWriter]::Create($Out, $s); $xml.Save($w); $w.Close()
Write-Host "Listo: $Out ($total programas)" -ForegroundColor Cyan
