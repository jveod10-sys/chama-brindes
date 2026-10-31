$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$products=Get-Content (Join-Path $root 'data/catalogo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$collected=Get-Content (Join-Path $root 'data/coleta-produtos.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$names=@{}; foreach($p in $collected) {$names[$p.id]=$p.name}
$ids=[Collections.Generic.HashSet[string]]::new()
$images=[Collections.Generic.HashSet[string]]::new()
$errors=[Collections.Generic.List[string]]::new()
foreach($p in $products) {
    if(!$ids.Add($p.id)) {$errors.Add("ID repetido: $($p.id)")}
    if($names[$p.id] -cne $p.name) {$errors.Add("Nome alterado: $($p.id)")}
    if(!$p.category) {$errors.Add("Categoria vazia: $($p.id)")}
    foreach($image in $p.images) {
        if($images.Add($image)) {
            if(!$image.StartsWith('assets/images/catalogo/') -or ![IO.File]::Exists((Join-Path $root $image))) {$errors.Add("Imagem ausente: $image")}
        }
    }
}
if($products.Count -ne $collected.Count) {$errors.Add('Total de produtos diverge da coleta.')}
$html=[IO.File]::ReadAllText((Join-Path $root 'index.html'))
foreach($match in [regex]::Matches($html,'<img[^>]+src=["'']([^"'']+)["'']')) {
    $src=[uri]::UnescapeDataString([Net.WebUtility]::HtmlDecode($match.Groups[1].Value))
    if($src -notmatch '^https?://' -and ![IO.File]::Exists((Join-Path $root $src))) {$errors.Add("Imagem da vitrine ausente: $src")}
}
foreach($match in [regex]::Matches($html,'https://wa\.me/(\d+)')) {if($match.Groups[1].Value -ne '5511947582966') {$errors.Add('WhatsApp incorreto no HTML.')}}
$result=@{products=$products.Count; uniqueIds=$ids.Count; referencedImages=$images.Count; originalNamesPreserved=($products.Count -eq $names.Count); errors=$errors.ToArray(); passed=($errors.Count -eq 0)}
[IO.File]::WriteAllText((Join-Path $root 'data/validacao-arquivos.json'),(ConvertTo-Json $result -Depth 6),(New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 6
if($errors.Count) {exit 1}
