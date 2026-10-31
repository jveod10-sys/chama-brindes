param([switch]$Resume)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$base = 'https://chamabrindes.com.br'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Save-Text($path, $text) { [IO.File]::WriteAllText((Join-Path $root $path), $text, $utf8) }
function Get-Page($url) {
    for ($attempt=1; $attempt -le 3; $attempt++) {
        try { return (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 45).Content } catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 1 }
    }
}
function Decode($s) { [Net.WebUtility]::HtmlDecode($s).Trim() }
foreach ($directory in @('assets/images/catalogo', 'data', 'data/cache')) { New-Item -ItemType Directory -Force -Path (Join-Path $root $directory) | Out-Null }
$failures = [Collections.Generic.List[object]]::new()
$downloads = @{}; $hashes = @{}; $duplicates = [Collections.Generic.List[object]]::new()
$knownWebp=@{}
$webpPath=Join-Path $root 'data/validacao-webp.json'
if(Test-Path $webpPath) { foreach($entry in (Get-Content $webpPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {if($entry.valid) {$knownWebp[$entry.src]=$entry.sha256}} }
if ($Resume) {
    $products = Get-Content (Join-Path $root 'data/coleta-produtos.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $lastPage = [int][Math]::Ceiling($products.Count / 24.0) + 1
} else {
$products = [Collections.Generic.List[object]]::new()
$seen = @{}
$categoryMap = @{}
$originalCategories=[Collections.Generic.List[object]]::new()
$catalog = Get-Page "$base/Catalogo"
$categories = [regex]::Matches($catalog, 'href="(/categoria/(\d+)/[^"?]+)"') | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique
foreach ($category in $categories) {
    $categoryName = ''
    $link = [regex]::Match($catalog, ('href="/categoria/'+$category+'/[^" ]+"[^>]*>\s*<span[^>]*>([^<]+)'))
    if ($link.Success) { $categoryName = Decode $link.Groups[1].Value }
    if (!$categoryName) { continue }
    $categoryIds=[Collections.Generic.List[string]]::new()
    for ($page=1; $page -le 1000; $page++) {
        $body = Get-Page "$base/Catalogo/FiltrarProdutos?categoriaSite=$category&pagina=$page"
        $ids = [regex]::Matches($body, 'id="img_card_prod_(\d+)_([^" ]+)"')
        if (!$ids.Count) { break }
        foreach ($id in $ids) { $key=$id.Groups[1].Value+'_'+$id.Groups[2].Value; $categoryMap[$key] = $categoryName; $categoryIds.Add($key) }
        if ($page -eq 1000) { throw 'Limite de paginas atingido nas categorias.' }
    }
    $originalCategories.Add(@{name=$categoryName; ids=$categoryIds.ToArray()})
}
Save-Text 'data/categorias-originais.json' (ConvertTo-Json -InputObject @($originalCategories.ToArray()) -Depth 5)
$lastPage = 0
for ($page=1; $page -le 1000; $page++) {
    $cache = Join-Path $root "data/cache/pagina-$page.html"
    if (Test-Path $cache) { $body = [IO.File]::ReadAllText($cache) } else { $body = Get-Page "$base/Catalogo/FiltrarProdutos?pagina=$page"; [IO.File]::WriteAllText($cache, $body, $utf8) }
    $cards = [regex]::Split($body, '<div class="col">') | Select-Object -Skip 1
    if (!$cards.Count) {
        if ($body.Trim() -and $body -notmatch 'id="vazio-catalogo"') { throw 'Resposta inesperada ao terminar a paginacao.' }
        $lastPage = $page; break
    }
    $added = 0
    foreach ($card in $cards) {
        $image = [regex]::Match($card, '<img id="img_card_prod_(\d+)_([^" ]+)"[^>]*src="([^"]+)"[^>]*alt="([^"]*)"')
        $link = [regex]::Match($card, 'href="(/produto/[^" ]+)"')
        if (!$image.Success -or !$link.Success) { throw 'Card sem estrutura reconhecida.' }
        $key = $image.Groups[1].Value+'_'+$image.Groups[2].Value
        if ($seen.ContainsKey($key)) { continue }; $seen[$key]=$true; $added++
        $urls = @([regex]::Matches($card, '<img[^>]+src="([^"]+)"') | ForEach-Object { Decode $_.Groups[1].Value } | Where-Object { $_ -notmatch 'placeholder' } | Select-Object -Unique)
        $products.Add([ordered]@{id=$key; name=(Decode $image.Groups[4].Value); category=$(if ($categoryMap.ContainsKey($key)) {$categoryMap[$key]} else {'Sem categoria na origem'}); sourceUrl="$base$(Decode $link.Groups[1].Value)"; imageUrls=$urls; images=@()})
    }
    Write-Output "Pagina $page : $($cards.Count) produtos"
    if (!$added) { throw 'Pagina repetida; importacao interrompida para nao declarar completude incorretamente.' }
    if ($page -eq 1000) { throw 'Limite de paginas atingido.' }
}
$failures = [Collections.Generic.List[object]]::new()
Save-Text 'data/coleta-produtos.json' (ConvertTo-Json -InputObject @($products.ToArray()) -Depth 8)
$downloads = @{}; $hashes = @{}; $duplicates = [Collections.Generic.List[object]]::new()
foreach ($product in $products) {
    # Inspect product details for additional gallery images not exposed in the listing.
    if ($product.id -like '*_LOCAL') { try {
        $detail = Get-Page $product.sourceUrl
        $extra = @([regex]::Matches($detail, 'imgPrincipalDetalhe[^\r\n]*?src=''([^'']+)''') | ForEach-Object { Decode $_.Groups[1].Value } | Where-Object { $_ -notmatch 'placeholder' } | Select-Object -Unique)
        $product.imageUrls = @(@($product.imageUrls) + $extra | Select-Object -Unique)
    } catch { $failures.Add(@{product=$product.id; url=$product.sourceUrl; error=$_.Exception.Message; stage='details'}) } }
}
Save-Text 'data/coleta-produtos.json' (ConvertTo-Json -InputObject @($products.ToArray()) -Depth 8)
}
# Download unique URLs concurrently; validate every file before integrating it.
[Net.ServicePointManager]::DefaultConnectionLimit = 12
$allUrls = @($products | ForEach-Object { $_.imageUrls } | Sort-Object -Unique)
Write-Output "URLs unicas para download: $($allUrls.Count)"
for ($offset=0; $offset -lt $allUrls.Count; $offset+=12) {
    $pending = @()
    foreach ($url in $allUrls[$offset..([Math]::Min($offset+11,$allUrls.Count-1))]) {
        $uri = [uri]::new([uri]$base, $url)
        $path = Join-Path $root ('assets/images/catalogo/'+[IO.Path]::GetFileName($uri.LocalPath))
        if (!(Test-Path -LiteralPath $path)) {
            $client = New-Object Net.WebClient
            $pending += @{client=$client; task=$client.DownloadFileTaskAsync($uri, $path); url=$url}
        }
    }
    foreach ($job in $pending) { try { $job.task.GetAwaiter().GetResult() } catch { Write-Output "Download pendente de nova tentativa: $($job.url)" } finally { $job.client.Dispose() } }
    if ($offset % 120 -eq 0 -or $offset+12 -ge $allUrls.Count) { Write-Output "Downloads: $([Math]::Min($offset+12,$allUrls.Count)) / $($allUrls.Count)" }
}
$verifiedProducts=0
foreach ($product in $products) {
    foreach ($url in $product.imageUrls) {
        if (!$downloads.ContainsKey($url)) {
            $uri = [uri]::new([uri]$base, $url)
            $file = [IO.Path]::GetFileName($uri.LocalPath)
            $relative = 'assets/images/catalogo/'+$file
            $path = Join-Path $root $relative
            try {
              for ($attempt=1; $attempt -le 3; $attempt++) { try {
                if (!(Test-Path -LiteralPath $path)) { Invoke-WebRequest $uri.AbsoluteUri -UseBasicParsing -OutFile $path -TimeoutSec 45 }
                if($knownWebp.ContainsKey($relative)) {
                    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $knownWebp[$relative]) {throw 'WebP alterado desde a validacao no navegador.'}
                } else {
                    $bitmap = [Drawing.Image]::FromFile($path)
                    try { if ($bitmap.Width -lt 1 -or $bitmap.Height -lt 1) { throw 'Imagem invalida' } } finally { $bitmap.Dispose() }
                }
                $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
                if ($hashes.ContainsKey($hash) -and $hashes[$hash] -ne $relative) { $duplicates.Add(@{file=$relative; sameAs=$hashes[$hash]; sha256=$hash}) } else { $hashes[$hash]=$relative }
                $downloads[$url]=$relative
                break
              } catch { if ($attempt -eq 3) { throw }; Invoke-WebRequest $uri.AbsoluteUri -UseBasicParsing -OutFile $path -TimeoutSec 45 } }
            } catch { $downloads[$url]=$null; $failures.Add(@{product=$product.id; url=$url; error=$_.Exception.Message; stage='image'}) }
        }
        if ($downloads[$url]) { $product.images += $downloads[$url] }
    }
    $verifiedProducts++
    if ($verifiedProducts % 100 -eq 0 -or $verifiedProducts -eq $products.Count) { Write-Output "Produtos verificados: $verifiedProducts / $($products.Count)" }
}
$report = [ordered]@{source="$base/Catalogo"; collectedAt=[DateTimeOffset]::Now.ToString('o'); products=$products.Count; terminalPage=$lastPage; uniqueImageUrls=$downloads.Count; downloadedImages=@($downloads.Values | Where-Object {$_}).Count; withoutImages=@($products | Where-Object {!$_.images.Count} | ForEach-Object {$_.id}); failures=@($failures.ToArray()); duplicates=@($duplicates.ToArray())}
$json = ConvertTo-Json -InputObject @($products | ForEach-Object { $_ }) -Depth 8
Save-Text 'data/catalogo.json' $json
Save-Text 'data/catalogo.js' ('window.CHAMA_CATALOGO = '+$json+';')
Save-Text 'data/importacao-relatorio.json' (ConvertTo-Json $report -Depth 8)
& (Join-Path $PSScriptRoot 'organizar-catalogo.ps1')
& (Join-Path $PSScriptRoot 'exportar-vitrine.ps1')
Write-Output "Importacao concluida: $($report.products) produtos; $($report.downloadedImages) imagens verificadas; $($report.failures.Count) falhas. Relatorio: data/importacao-relatorio.json"
