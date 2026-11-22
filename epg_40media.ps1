
$ErrorActionPreference = "Stop"

# ==========================================
# 1. CONFIGURACIÓN DE FUENTES Y SALIDA
# ==========================================
$Canales40Media = [ordered]@{
  entchannel    = "ENT Channel"
  entfamily     = "ENT Family"
  totalmusic    = "Totalmusic"
  totalmusic80s = "Totalmusic 80s"
  totalmusic00s = "Totalmusic 00s"
  entmovies     = "ENT Movies"
  entdrama      = "ENT Drama"
  entclassic    = "ENT Classic"
  entlife       = "ENT Life"
  entextreme    = "ENT Extreme"
  entcomedy     = "ENT Comedy"
}
$Base40Media = "https://api.40mediagroup.com/xmltv/programacion"
$Headers40   = @{
  referer      = "https://www.40mediagroup.com/"
  "user-agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}

$SoFastCanales = [ordered]@{
  "TYC-SPORTS-FAN" = "TyC Sports FAN"
}
$SoFastBase  = "https://epg.sofast.tv/api/ChannelXML/GetEpgXml"
$SoFastHours = 72

$ElDestapeId   = "el-destape"
$ElDestapeName = "El Destape"
$ElDestapeUrl  = "https://www.stremiar.tv/canales/el-destape"
$DiasElDestape = 3

# Si se ejecuta como script, usa $PSScriptRoot; si se pega en consola, usa el directorio actual
$BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Out     = Join-Path $BaseDir "epg.xml"

# ==========================================
# 2. FUNCIONES AUXILIARES
# ==========================================
function XDate($d) {
  if ($d -is [string]) {
    $d = [DateTimeOffset]::Parse($d, [Globalization.CultureInfo]::InvariantCulture)
  } else {
    $d = [DateTimeOffset]$d
  }
  $d.ToUniversalTime().ToString("yyyyMMddHHmmss") + " +0000"
}

function Add-El($parent, $name, $text, $lang) {
  if ([string]::IsNullOrWhiteSpace($text)) { return }
  $e = $xml.CreateElement($name)
  if ($lang) { [void]$e.SetAttribute("lang", $lang) }
  $e.InnerText = $text
  [void]$parent.AppendChild($e)
}

function Get-ArgentinaNow {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time")
  return [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
}

function Get-ElDestapeProgrammes {
  param([int]$Dias = 3)

  # Grilla semanal de respaldo (hora de Argentina -03:00)
  $grillaFallback = @(
    @{ Titulo = "Habrá Consecuencias";      Dias = @(1,2,3,4,5); Inicio = "07:00"; Fin = "10:00" }
    @{ Titulo = "El pase";                   Dias = @(1,2,3,4,5); Inicio = "10:00"; Fin = "12:00" }
    @{ Titulo = "Verdades Afiladas";         Dias = @(1,2,3,4,5); Inicio = "12:00"; Fin = "14:00" }
    @{ Titulo = "Maldita Suerte";            Dias = @(1,2,3,4,5); Inicio = "14:00"; Fin = "17:00" }
    @{ Titulo = "Palo y Zanahoria";          Dias = @(1,2,3,4,5); Inicio = "17:00"; Fin = "19:00" }
    @{ Titulo = "El pase de la tarde";       Dias = @(1,2,3,4);   Inicio = "19:00"; Fin = "20:00" }
    @{ Titulo = "Al infinito y más allá";    Dias = @(5);         Inicio = "19:00"; Fin = "20:00" }
    @{ Titulo = "Batalla Cultural";          Dias = @(1,2,3,4);   Inicio = "20:00"; Fin = "22:00" }
    @{ Titulo = "SAD";                       Dias = @(1);         Inicio = "22:00"; Fin = "23:00" }
    @{ Titulo = "Cancha Embarrada";          Dias = @(3);         Inicio = "22:00"; Fin = "22:30" }
    @{ Titulo = "Te toman por boludo";       Dias = @(0);         Inicio = "19:00"; Fin = "21:00" }
    @{ Titulo = "Detrás de lo que vemos";    Dias = @(0);         Inicio = "21:00"; Fin = "22:30" }
  )

  $mapaDias = @{
    "dom" = 0; "lun" = 1; "mar" = 2; "mié" = 3; "mie" = 3
    "jue" = 4; "vie" = 5; "sáb" = 6; "sab" = 6
  }

  $reglas = @()

  try {
    $resp = Invoke-WebRequest -Uri $ElDestapeUrl -Headers @{ "user-agent" = "Mozilla/5.0" } -TimeoutSec 20
    $html = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    $texto = [Regex]::Replace($html, "<[^>]+>", "`n")
    $texto = [Net.WebUtility]::HtmlDecode($texto)

    $rx = [Regex]::new('(?m)^([^\r\n]{2,80})\s+((?:Lun|Mar|Mié|Mie|Jue|Vie|Sáb|Sab|Dom)(?:\s+a\s+(?:lun|mar|mié|mie|jue|vie|sáb|sab|dom))?)\s*·\s*(\d{2}:\d{2})\s*[–-]\s*(\d{2}:\d{2})', 'IgnoreCase')
    foreach ($m in $rx.Matches($texto)) {
      $titulo  = $m.Groups[1].Value.Trim()
      $diasTxt = $m.Groups[2].Value.ToLower().Trim()
      $ini     = $m.Groups[3].Value
      $fin     = $m.Groups[4].Value

      $diasActivos = @()
      if ($diasTxt -match '^([a-záé]+)\s+a\s+([a-záé]+)$') {
        $d1 = $mapaDias[$matches[1]]
        $d2 = $mapaDias[$matches[2]]
        if ($null -ne $d1 -and $null -ne $d2) {
          for ($d = $d1; $d -le $d2; $d++) { $diasActivos += $d }
        }
      } elseif ($mapaDias.ContainsKey($diasTxt)) {
        $diasActivos += $mapaDias[$diasTxt]
      }

      if ($diasActivos.Count -gt 0) {
        $reglas += @{ Titulo = $titulo; Dias = $diasActivos; Inicio = $ini; Fin = $fin }
      }
    }
  } catch {
    Write-Host "AVISO $ElDestapeId : fallo al leer web ($($_.Exception.Message)), usando grilla de respaldo" -ForegroundColor Yellow
  }

  if ($reglas.Count -eq 0) {
    $reglas = $grillaFallback
  }

  $ahoraArg = Get-ArgentinaNow
  $eventos  = @()

  for ($offset = 0; $offset -lt $Dias; $offset++) {
    $fecha = $ahoraArg.Date.AddDays($offset)
    $dow   = [int]$fecha.DayOfWeek
    foreach ($r in $reglas) {
      if ($r.Dias -contains $dow) {
        $eventos += [PSCustomObject]@{
          title    = $r.Titulo
          start    = "$($fecha.ToString('yyyy-MM-dd'))T$($r.Inicio):00-03:00"
          stop     = "$($fecha.ToString('yyyy-MM-dd'))T$($r.Fin):00-03:00"
          category = "Noticias / Política"
        }
      }
    }
  }

  return ($eventos | Sort-Object start, title -Unique)
}

# ==========================================
# 3. DOCUMENTO XMLTV BASE
# ==========================================
[xml]$xml = '<?xml version="1.0" encoding="UTF-8"?><tv generator-info-name="epg-unificado"></tv>'
$data40Media = @{}
$dataSoFast  = @{}

# ==========================================
# 4. RECOLECCIÓN DE DATOS
# ==========================================
foreach ($id in $Canales40Media.Keys) {
  try {
    $r = Invoke-RestMethod -Uri "$Base40Media/$id/guia.json" -Headers $Headers40 -TimeoutSec 20
  } catch {
    $r = $null
  }
  if ($r -and $r.programmes) {
    $data40Media[$id] = $r.programmes
    Write-Host "OK    $id ($($r.programmes.Count))"
  } else {
    Write-Host "VACIO $id" -ForegroundColor Yellow
  }
}

foreach ($id in $SoFastCanales.Keys) {
  try {
    $resp = Invoke-WebRequest -Uri "$SoFastBase`?ChannelId=$id&DurationHours=$SoFastHours" -Headers @{ "user-agent" = "Mozilla/5.0" } -TimeoutSec 20
    $xmlText = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    [xml]$sfXml = $xmlText
    $progs = $sfXml.SelectNodes("//programme")
    if ($progs -and $progs.Count -gt 0) {
      $dataSoFast[$id] = $progs
      Write-Host "OK    $id ($($progs.Count))"
    } else {
      Write-Host "VACIO $id" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "ERROR $id ($($_.Exception.Message))" -ForegroundColor Yellow
  }
}

$dataElDestape = Get-ElDestapeProgrammes -Dias $DiasElDestape
if ($dataElDestape.Count -gt 0) {
  Write-Host "OK    $ElDestapeId ($($dataElDestape.Count))"
} else {
  Write-Host "VACIO $ElDestapeId" -ForegroundColor Yellow
}

# ==========================================
# 5. CREACIÓN DE CANALES (<channel>)
# ==========================================
foreach ($id in $Canales40Media.Keys) {
  if ($data40Media[$id]) {
    $ch = $xml.CreateElement("channel")
    [void]$ch.SetAttribute("id", $id)
    Add-El $ch "display-name" $Canales40Media[$id] $null
    [void]$xml.tv.AppendChild($ch)
  }
}

foreach ($id in $SoFastCanales.Keys) {
  if ($dataSoFast[$id]) {
    $ch = $xml.CreateElement("channel")
    [void]$ch.SetAttribute("id", $id)
    Add-El $ch "display-name" $SoFastCanales[$id] $null
    [void]$xml.tv.AppendChild($ch)
  }
}

if ($dataElDestape.Count -gt 0) {
  $ch = $xml.CreateElement("channel")
  [void]$ch.SetAttribute("id", $ElDestapeId)
  Add-El $ch "display-name" $ElDestapeName $null
  [void]$xml.tv.AppendChild($ch)
}

# ==========================================
# 6. CREACIÓN DE PROGRAMAS (<programme>)
# ==========================================
$total = 0

foreach ($id in $Canales40Media.Keys) {
  foreach ($p in $data40Media[$id]) {
    $pr = $xml.CreateElement("programme")
    [void]$pr.SetAttribute("start", (XDate $p.start))
    [void]$pr.SetAttribute("stop",  (XDate $p.stop))
    [void]$pr.SetAttribute("channel", $id)

    Add-El $pr "title"     $p.title    "es"
    Add-El $pr "sub-title" $p.subtitle "es"
    Add-El $pr "desc"      $p.desc     "es"
    Add-El $pr "category"  $p.category "es"
    if ($p.icon) {
      $i = $xml.CreateElement("icon")
      [void]$i.SetAttribute("src", $p.icon)
      [void]$pr.AppendChild($i)
    }

    [void]$xml.tv.AppendChild($pr)
    $total++
  }
}

foreach ($id in $SoFastCanales.Keys) {
  foreach ($p in $dataSoFast[$id]) {
    $pr = $xml.CreateElement("programme")
    [void]$pr.SetAttribute("start",   $p.GetAttribute("start"))
    [void]$pr.SetAttribute("stop",    $p.GetAttribute("stop"))
    [void]$pr.SetAttribute("channel", $id)

    Add-El $pr "title"     ($p.SelectSingleNode("title")?.InnerText)     "es"
    Add-El $pr "sub-title" ($p.SelectSingleNode("sub-title")?.InnerText) "es"
    Add-El $pr "desc"      ($p.SelectSingleNode("desc")?.InnerText)      "es"
    Add-El $pr "category"  ($p.SelectSingleNode("category")?.InnerText)  "es"

    $iconNode = $p.SelectSingleNode("icon")
    if ($iconNode -and $iconNode.GetAttribute("src")) {
      $i = $xml.CreateElement("icon")
      [void]$i.SetAttribute("src", $iconNode.GetAttribute("src"))
      [void]$pr.AppendChild($i)
    }

    [void]$xml.tv.AppendChild($pr)
    $total++
  }
}

foreach ($p in $dataElDestape) {
  $pr = $xml.CreateElement("programme")
  [void]$pr.SetAttribute("start",   (XDate $p.start))
  [void]$pr.SetAttribute("stop",    (XDate $p.stop))
  [void]$pr.SetAttribute("channel", $ElDestapeId)

  Add-El $pr "title"    $p.title    "es"
  Add-El $pr "category" $p.category "es"

  [void]$xml.tv.AppendChild($pr)
  $total++
}

# ==========================================
# 7. GUARDADO FINAL (UTF-8 SIN BOM)
# ==========================================
$settings = New-Object Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object Text.UTF8Encoding($false)

$writer = [Xml.XmlWriter]::Create($Out, $settings)
$xml.Save($writer)
$writer.Close()

Write-Host "Listo: $Out ($total programas)" -ForegroundColor Cyan
