$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$utf8=New-Object Text.UTF8Encoding($false)
$products=Get-Content (Join-Path $root 'data/catalogo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Escape-Html($s) { [Net.WebUtility]::HtmlEncode([string]$s) }
$featured=@()
foreach($term in @('copo termico','garrafa termica','mochila','caneta metal')) {
    $p=$products | Where-Object { $_.images.Count -and (($_.name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLowerInvariant().Contains($term)) } | Select-Object -First 1
    if($p) { $featured+=$p }
}
$cards=@()
if($featured.Count -lt 4) { throw 'Vitrine incompleta; exportacao interrompida para preservar o HTML.' }
foreach($p in $featured) {
    $name=Escape-Html $p.name
    $category=Escape-Html $p.category
    $image=Escape-Html (($p.images[0].Split('/') | ForEach-Object {[uri]::EscapeDataString($_)}) -join '/')
    $quote=Escape-Html ('https://wa.me/5511947582966?text='+[uri]::EscapeDataString("Ola! Gostaria de um orcamento para $($p.name) (codigo $($p.id)). Referencia: $($p.sourceUrl)"))
    $cards+="<article class='product-card'><div class='product-image'><img src='$image' alt='$name' loading='lazy' width='600' height='600'></div><div class='product-info'><div><span class='product-category'>$category</span><h3>$name</h3><small class='product-code'>Codigo: $($p.id)</small></div><a href='$quote' target='_blank' rel='noopener noreferrer' aria-label='Solicitar orcamento de $name'>&#8599;</a></div></article>"
}
$path=Join-Path $root 'index.html'
$html=[IO.File]::ReadAllText($path)
$pattern='(?s)                <div class="product-grid">.*?(?=                <div class="catalog-cta reveal">)'
$old=[regex]::Match($html,$pattern).Value
if(!$old) { throw 'Grade original nao localizada; HTML preservado.' }
$backup=Join-Path $root 'data/vitrine-anterior.html'
if(!(Test-Path $backup)) {[IO.File]::WriteAllText($backup,$old,$utf8)}
$replacement='                <div class="product-grid">'+[Environment]::NewLine+($cards -join [Environment]::NewLine)+[Environment]::NewLine+'                </div>'+[Environment]::NewLine+[Environment]::NewLine
$html=[regex]::Replace($html,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $replacement})
[IO.File]::WriteAllText($path,$html,$utf8)
Write-Output "Vitrine inicial exportada: $($featured.Count) produtos reais."
