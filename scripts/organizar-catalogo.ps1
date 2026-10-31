$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object Text.UTF8Encoding($false)
$products = Get-Content (Join-Path $root 'data/catalogo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$original = Get-Content (Join-Path $root 'data/categorias-originais.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$originalMatches=@{}
foreach($group in $original) { foreach($id in $group.ids) { $originalMatches[$id]=$group.name } }
$rules = @(
    @('Copos e garrafas', '\b(copo|copos|garrafa|garrafas|squeeze|squeezes|caneca|canecas|coqueteleira|cantil|canudo|xicara|xicaras|taca|tacas|cuia|porta[- ]latas?)\b'),
    @('Bolsas e mochilas', '\b(bolsa|bolsas|mochila|mochilas|sacola|sacolas|sacochila|saco-mochila|mala|malas|pochete|bag|saco|sacos)\b'),
    @('Tecnologia', '\b(power bank|powerbank|carregador|carregamento|fone|fones|headphone|headset|bluetooth|wireless|usb|mouse|mousepad|mouse pad|webcam|smartwatch|caixa de som|speaker|hub|cabo|cabos|pendrive|pen drive|relogio digital|suporte.*(celular|telemovel|notebook|portatil))\b'),
    @('Escritório', '\b(caneta|canetas|esferografica|esferograficas|escritorio|lapis|lapiseira|borracha|regua|caderno|cadernos|caderneta|agenda|planner|bloco|blocos|anotacoes|marca-texto|marca texto|marcador|pasta|calculadora|calendario|porta-cartao|porta cartao|porta-caneta|porta caneta|papel|impress|receituario|certificado|manuseio)\b'),
    @('Cuidados pessoais', '\b(necessaire|frasqueira|espelho|escova|pente|manicure|higiene|alcool|sabonete|saboneteira|frasco|perfume|balsamo|batom|massageador|mascara|porta-joias|porta joias|porta-relogios|porta relogios|kit costura|kit banho|kit viagem|kit beleza|lixa|toalha)\b'),
    @('Casa e cozinha', '\b(churrasco|churrasqueira|tabua|petisqueira|petisco|petiscos|faca|facas|talher|talheres|garfo|colher|marmita|lancheira|porta alimento|pote|potes|abridor|saca-rolhas|saca rolhas|vinho|vinhos|queijo|queijos|cozinha|salada|avental|cha|cafe|cafezinho|cafeteira|chaleira|cumbuca|bandeja|amassador|temperos|saleiro|farinheira|cerveja|caipirinha|gin|pizza|bar|utensilio|utensilios|servir|frios|hamburguer|copo medidor|termometro culinario|porta-copo|porta copo|tapete|porta-retrato|porta retrato)\b'),
    @('Ferramentas', '\b(ferramenta|ferramentas|trena|lanterna|chave de fenda|canivete|alicate|multifuncional|nivel|martelo)\b'),
    @('Moda e acessórios', '\b(chaveiro|bone|bones|camiseta|camisa|polo|viseira|chapeu|oculos|relogio|pulseira|cordao|carteira|porta-documento|porta documento|crach|leque|sombrinha|guarda-chuva|guarda chuva|poncho|capa de chuva|cachecol|gorro|meia|chinelo|sandalia)\b'),
    @('Esporte e lazer', '\b(fitness|yoga|exercicio|esporte|bola|praia|frisbee|jogo|jogos|baralho|domino|xadrez|pet|cachorro|gato|apito|bicicleta|pular|corrida|raquete|bussola|binoculo|buzina)\b'),
    @('Kits e conjuntos', '\b(kit|kits|conjunto|conjuntos|conj)\b'),
    @('Estojos e embalagens', '\b(estojo|estojos|caixa|caixas|caixinha|caixinhas|embalagem|embalagens)\b')
)
$review = [Collections.Generic.List[object]]::new()
$localImages = @{}
foreach ($cache in (Get-ChildItem (Join-Path $root 'data/cache/pagina-*.html') | Sort-Object { [int]($_.BaseName -replace 'pagina-','') } | Select-Object -First 3)) {
    foreach ($card in ([regex]::Split([IO.File]::ReadAllText($cache.FullName), '<div class="col">') | Select-Object -Skip 1)) {
        $idMatch = [regex]::Match($card, 'id="img_card_prod_(\d+_LOCAL)"')
        if ($idMatch.Success) {
            $localImages[$idMatch.Groups[1].Value] = @([regex]::Matches($card, '<img[^>]+src="([^"]+)"') | ForEach-Object {[Net.WebUtility]::HtmlDecode($_.Groups[1].Value)} | Where-Object {$_ -notmatch 'placeholder'} | Sort-Object -Unique)
        }
    }
}
foreach ($p in $products) {
    # Listing galleries exclude unrelated product suggestions from detail pages.
    if ($localImages.ContainsKey($p.id)) {
        $p.imageUrls = $localImages[$p.id]
        $allowed = @($p.imageUrls | ForEach-Object {'assets/images/catalogo/'+[IO.Path]::GetFileName(([uri]$_).LocalPath)})
        $p.images = @($p.images | Where-Object {$allowed -contains $_})
    }
    $name = $p.name.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $name = $name.ToLowerInvariant()
    $category = 'Outros brindes'
    foreach ($rule in $rules) { if ($name -match $rule[1]) { $category=$rule[0]; break } }
    if ($name -match '\bcrachas?\b') { $category='Moda e acessórios' }
    $sourceCategory = if ($originalMatches.ContainsKey($p.id)) { $originalMatches[$p.id] } else { $null }
    if ($sourceCategory) { $category='Escritório' }
    $p.category = $category
    $p | Add-Member -NotePropertyName sourceCategory -NotePropertyValue $sourceCategory -Force
    $p | Add-Member -NotePropertyName categoryMethod -NotePropertyValue $(if ($sourceCategory) {'source'} elseif ($category -eq 'Outros brindes') {'review'} else {'product-name'}) -Force
    $tags = @()
    if ($name -match '\b(bambu|bamboo|reciclado|reciclada|reciclavel|rpet|cortica|ecologico|ecologica|palha de trigo|fibra de trigo|papel semente)\b') { $tags += 'Linha ecológica' }
    $p | Add-Member -NotePropertyName tags -NotePropertyValue $tags -Force
    if ($category -eq 'Outros brindes') { $review.Add(@{id=$p.id; name=$p.name}) }
}
$json = ConvertTo-Json -InputObject @($products | ForEach-Object {$_}) -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $root 'data/catalogo.json'), $json, $utf8)
$web = @($products | Select-Object id,name,category,images,sourceUrl,tags,@{N='hasSourceImage';E={$_.imageUrls.Count -gt 0}})
$webJson = ConvertTo-Json -InputObject $web -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $root 'data/catalogo.js'), ('window.CHAMA_CATALOGO = '+$webJson+';'), $utf8)
$collectedPath=Join-Path $root 'data/coleta-produtos.json'
if(Test-Path $collectedPath) {
    $collected=Get-Content $collectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($entry in $collected) {
        $entry.category=if($originalMatches.ContainsKey($entry.id)) {$originalMatches[$entry.id]} else {'Sem categoria na origem'}
        if($localImages.ContainsKey($entry.id)) {$entry.imageUrls=$localImages[$entry.id]}
    }
    [IO.File]::WriteAllText($collectedPath,(ConvertTo-Json -InputObject @($collected | ForEach-Object {$_}) -Depth 8 -Compress),$utf8)
}
$summary = @{categories=@($products | Group-Object category | ForEach-Object {@{name=$_.Name; products=$_.Count}}); ecological=@($products | Where-Object {$_.tags -contains 'Linha ecológica'}).Count; needsReview=$review.ToArray(); explanation='Categorias organizadas pelo nome original. sourceCategory preserva somente a categoria confirmada pela origem. Outros brindes contem nomes ambiguos para revisao.'}
[IO.File]::WriteAllText((Join-Path $root 'data/categorias-relatorio.json'), (ConvertTo-Json $summary -Depth 6), $utf8)
$reportPath=Join-Path $root 'data/importacao-relatorio.json'
if(Test-Path $reportPath) {
    $report=Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $report.withoutImages=@($products | Where-Object {!$_.images.Count} | ForEach-Object {$_.id})
    $referenced=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($p in $products) {foreach($image in $p.images) {[void]$referenced.Add($image)}}
    $report | Add-Member -NotePropertyName referencedImageFiles -NotePropertyValue $referenced.Count -Force
    $report | Add-Member -NotePropertyName collectionScope -NotePropertyValue 'All listing pages, all card images including thumbnails; LOCAL detail galleries checked. Supplier-exclusive detail images not exhaustively verified.' -Force
    [IO.File]::WriteAllText($reportPath,(ConvertTo-Json $report -Depth 8),$utf8)
}
$summary.categories | ConvertTo-Json
