Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

function New-RectF([float]$x, [float]$y, [float]$w, [float]$h) {
  [System.Drawing.RectangleF]::new($x, $y, $w, $h)
}

function New-PointF([float]$x, [float]$y) {
  [System.Drawing.PointF]::new($x, $y)
}

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $path
}

function New-LinearBrush([System.Drawing.RectangleF]$rect, [string]$start, [string]$end, [float]$angle = 45) {
  [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $rect,
    [System.Drawing.ColorTranslator]::FromHtml($start),
    [System.Drawing.ColorTranslator]::FromHtml($end),
    $angle
  )
}

function New-Pen([System.Drawing.Brush]$brush, [float]$width) {
  $pen = [System.Drawing.Pen]::new($brush, $width)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $pen
}

function Save-LogoPng([string]$path, [int]$size, [Nullable[int]]$padding, [string]$background = "") {
  $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bmp)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

  try {
    if ([string]::IsNullOrWhiteSpace($background)) {
      $graphics.Clear([System.Drawing.Color]::Transparent)
    } else {
      $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml($background))
    }

    $pad = if ($padding.HasValue) { [float]$padding.Value } else { 0.0 }
    $scale = ($size - ($pad * 2)) / 1024.0
    $graphics.TranslateTransform($pad, $pad)
    $graphics.ScaleTransform($scale, $scale)

    $blueCircle = New-LinearBrush (New-RectF 180 170 640 640) "#087CFF" "#0647D8" 45
    $blueDoor = New-LinearBrush (New-RectF 364 304 286 472) "#0870FF" "#043FBD" 80
    $greenArrow = New-LinearBrush (New-RectF 86 440 308 260) "#12EAA6" "#04A58F" 45
    $greenCheck = New-LinearBrush (New-RectF 669 610 272 272) "#18E077" "#07957B" 45

    $whiteBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $blueSolid = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml("#0759DF"))
    $greenDot = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml("#0FC88F"))

    $graphics.FillEllipse($blueCircle, 310, 170, 600, 600)
    $graphics.FillEllipse($whiteBrush, 374, 234, 472, 472)

    $clockPen = New-Pen $blueSolid 36
    $graphics.DrawLine($clockPen, 610, 264, 610, 298)
    $graphics.DrawLine($clockPen, 610, 642, 610, 704)
    $graphics.DrawLine($clockPen, 704, 470, 760, 470)
    $graphics.DrawLine($clockPen, 610, 328, 610, 470)
    $graphics.DrawLine($clockPen, 610, 470, 716, 562)
    $graphics.FillEllipse($greenDot, 570, 430, 80, 80)

    $framePath = New-RoundedRectPath 196 258 300 420 56
    $framePen = New-Pen $blueCircle 48
    $graphics.DrawPath($framePen, $framePath)

    [System.Drawing.PointF[]]$doorPanel = @(
      (New-PointF 364 368),
      (New-PointF 496 304),
      (New-PointF 496 760),
      (New-PointF 364 690)
    )
    $graphics.FillPolygon($blueDoor, $doorPanel)

    $doorSide = [System.Drawing.Drawing2D.GraphicsPath]::new()
    [System.Drawing.PointF[]]$doorSidePoints = @(
        (New-PointF 496 304),
        (New-PointF 582 304),
        (New-PointF 596 306),
        (New-PointF 610 312),
        (New-PointF 623 322),
        (New-PointF 635 335),
        (New-PointF 644 352),
        (New-PointF 650 372),
        (New-PointF 650 708),
        (New-PointF 644 728),
        (New-PointF 635 745),
        (New-PointF 623 758),
        (New-PointF 610 768),
        (New-PointF 596 774),
        (New-PointF 582 776),
        (New-PointF 496 776)
      )
    $doorSide.AddLines($doorSidePoints)
    $doorSide.CloseFigure()
    $graphics.FillPath($blueCircle, $doorSide)
    $graphics.FillEllipse($whiteBrush, 432, 526, 40, 68)

    $arrowPen = New-Pen $greenArrow 40
    $graphics.DrawLine($arrowPen, 96, 528, 222, 528)
    $graphics.DrawLine($arrowPen, 104, 608, 152, 608)
    $graphics.DrawLine($arrowPen, 186, 608, 306, 608)

    $arrowHead = New-Pen $greenArrow 72
    $graphics.DrawLine($arrowHead, 246, 468, 350, 572)
    $graphics.DrawLine($arrowHead, 350, 572, 246, 676)

    $graphics.FillEllipse($greenCheck, 669, 610, 272, 272)
    $checkPen = New-Pen $whiteBrush 50
    [System.Drawing.PointF[]]$checkPoints = @(
        (New-PointF 724 742),
        (New-PointF 783 802),
        (New-PointF 898 686)
      )
    $graphics.DrawLines($checkPen, $checkPoints)

    $outDir = Split-Path -Parent $path
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
      New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bmp.Dispose()
  }
}

$root = Split-Path -Parent $PSScriptRoot

Save-LogoPng (Join-Path $root "frontend/public/logo-checkin.png") 1024 0
Save-LogoPng (Join-Path $root "flutter_app/assets/images/logo-checkin.png") 1024 0

Save-LogoPng (Join-Path $root "frontend/public/favicon-32.png") 32 1 "#F8FBFF"
Save-LogoPng (Join-Path $root "frontend/public/apple-touch-icon.png") 180 14 "#F8FBFF"
Save-LogoPng (Join-Path $root "frontend/public/icon-192.png") 192 14 "#F8FBFF"
Save-LogoPng (Join-Path $root "frontend/public/icon-512.png") 512 36 "#F8FBFF"
Save-LogoPng (Join-Path $root "frontend/public/icon-maskable-512.png") 512 96 "#F8FBFF"

$androidRoot = Join-Path $root "flutter_app/android/app/src/main/res"
Save-LogoPng (Join-Path $androidRoot "mipmap-mdpi/ic_launcher.png") 48 3 "#F8FBFF"
Save-LogoPng (Join-Path $androidRoot "mipmap-hdpi/ic_launcher.png") 72 5 "#F8FBFF"
Save-LogoPng (Join-Path $androidRoot "mipmap-xhdpi/ic_launcher.png") 96 7 "#F8FBFF"
Save-LogoPng (Join-Path $androidRoot "mipmap-xxhdpi/ic_launcher.png") 144 10 "#F8FBFF"
Save-LogoPng (Join-Path $androidRoot "mipmap-xxxhdpi/ic_launcher.png") 192 14 "#F8FBFF"

Write-Output "Generated logo assets."
