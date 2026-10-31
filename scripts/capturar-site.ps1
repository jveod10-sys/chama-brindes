param([int]$Width=1440, [int]$Height=1000, [string]$Name='desktop', [string]$Section='produtos')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $root 'data/browser-cdp'
$browser=Start-Process -FilePath 'C:/Program Files/Google/Chrome/Application/chrome.exe' -ArgumentList @('--headless','--no-first-run','--no-default-browser-check','--remote-debugging-port=9228','--use-angle=swiftshader','--enable-unsafe-swiftshader',('--user-data-dir="'+$profile+'"'),'about:blank') -WindowStyle Hidden -PassThru
for($attempt=0;$attempt -lt 30;$attempt++) {
    try { $tabs=Invoke-RestMethod 'http://localhost:9228/json'; break } catch { Start-Sleep -Milliseconds 300 }
}
$tab=$tabs | Where-Object {$_.type -eq 'page'} | Select-Object -First 1
$socket=New-Object Net.WebSockets.ClientWebSocket
$socket.ConnectAsync([uri]$tab.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
$script:commandId=0
function Send-CDP($method,$params) {
    $script:commandId++
    $bytes=[Text.Encoding]::UTF8.GetBytes((@{id=$script:commandId; method=$method; params=$params} | ConvertTo-Json -Depth 12 -Compress))
    $socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    while($true) {
        $buffer=New-Object byte[] 65536
        $stream=New-Object IO.MemoryStream
        do {
            $received=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),[Threading.CancellationToken]::None).GetAwaiter().GetResult()
            $stream.Write($buffer,0,$received.Count)
        } while(!$received.EndOfMessage)
        $message=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
        $stream.Dispose()
        if($message.id -eq $script:commandId) { if($message.error) {throw ($message.error | ConvertTo-Json)}; return $message.result }
    }
}
Send-CDP 'Emulation.setDeviceMetricsOverride' @{width=$Width;height=$Height;deviceScaleFactor=1;mobile=($Width -lt 700)} | Out-Null
$url=([uri](Join-Path $root 'index.html')).AbsoluteUri
Send-CDP 'Page.navigate' @{url=$url} | Out-Null
$expression='new Promise(resolve => { const ready = () => setTimeout(() => { document.querySelector(".preloader")?.remove(); document.getElementById("'+$Section+'").scrollIntoView({behavior:"instant"}); requestAnimationFrame(()=>requestAnimationFrame(()=>resolve({cards:document.querySelectorAll(".product-card").length,width:innerWidth,scrollWidth:document.documentElement.scrollWidth,images:[...document.querySelectorAll(".product-card img")].map(i=>({src:i.getAttribute("src"),loaded:i.complete&&i.naturalWidth>0}))}))); },2500); document.readyState==="complete"?ready():addEventListener("load",ready,{once:true}); })'
$status=Send-CDP 'Runtime.evaluate' @{expression=$expression;awaitPromise=$true;returnByValue=$true}
if($status.exceptionDetails) {throw ($status.exceptionDetails | ConvertTo-Json -Depth 8)}
$status.result.value | ConvertTo-Json -Depth 8
$checks=Send-CDP 'Runtime.evaluate' @{expression='(()=>{const result={};const button=document.querySelector(".menu-mobile");button.click();result.menuOpens=button.getAttribute("aria-expanded")==="true"&&document.querySelector(".nav").classList.contains("active");button.click();result.menuCloses=button.getAttribute("aria-expanded")==="false";const category=document.querySelector(".category-card");category.click();result.categoryLink=document.querySelector(".catalog-controls select").value===category.querySelector("h3").textContent;const select=document.querySelector(".catalog-controls select");select.value="";select.dispatchEvent(new Event("change"));const gallery=[...document.querySelectorAll(".product-gallery")].find(g=>g.children.length>1);if(gallery){gallery.children[1].click();result.gallery=gallery.children[1].getAttribute("aria-pressed")==="true";gallery.children[0].click();}result.whatsapp=[...document.querySelectorAll(".product-info a")].every(a=>new URL(a.href).pathname==="/5511947582966");document.getElementById("'+$Section+'").scrollIntoView({behavior:"instant"});return result;})()';returnByValue=$true}
$checks.result.value | ConvertTo-Json
if($checks.exceptionDetails -or @($checks.result.value.PSObject.Properties | Where-Object {$_.Value -eq $false}).Count) {throw 'Falha nos testes de interacao da pagina.'}
$validation=@{cards=$status.result.value.cards; viewportWidth=$status.result.value.width; documentWidth=$status.result.value.scrollWidth; interactions=$checks.result.value; checkedAt=[DateTimeOffset]::Now.ToString('o')}
[IO.File]::WriteAllText((Join-Path $root "data/validacao-navegador-$Name.json"),(ConvertTo-Json $validation -Depth 6),(New-Object Text.UTF8Encoding($false)))
Send-CDP 'Runtime.evaluate' @{expression='new Promise(resolve=>setTimeout(resolve,600))';awaitPromise=$true} | Out-Null
$overflow = Send-CDP 'Runtime.evaluate' @{expression='[...document.querySelectorAll("body *")].map(e=>({tag:e.tagName,cls:String(e.className),right:e.getBoundingClientRect().right,width:e.getBoundingClientRect().width})).filter(e=>e.right>document.documentElement.clientWidth+1).slice(0,12)';returnByValue=$true}
$overflow.result.value | ConvertTo-Json -Depth 5
$shot=Send-CDP 'Page.captureScreenshot' @{format='png';captureBeyondViewport=$false;fromSurface=$true}
[IO.File]::WriteAllBytes((Join-Path $root "data/catalogo-$Name.png"),[Convert]::FromBase64String($shot.data))
$reportPath=Join-Path $root 'data/importacao-relatorio.json'
if(Test-Path $reportPath) {
    $report=Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $webp=@()
    foreach($failure in $report.failures) {
        $relative='assets/images/catalogo/'+[IO.Path]::GetFileName(([uri]$failure.url).LocalPath)
        $path=Join-Path $root $relative
        $bytes=[IO.File]::ReadAllBytes($path)
        if($bytes.Length -gt 20 -and [Text.Encoding]::ASCII.GetString($bytes,0,4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($bytes,8,4) -eq 'WEBP') { $webp+=($relative.Split('/') | ForEach-Object {[uri]::EscapeDataString($_)}) -join '/' }
    }
    if($webp.Count) {
        $json=ConvertTo-Json -InputObject @($webp) -Compress
        $expression='Promise.all(('+ $json +').map(src=>new Promise(resolve=>{const img=new Image();img.onload=()=>resolve({src,valid:true,width:img.naturalWidth,height:img.naturalHeight});img.onerror=()=>resolve({src,valid:false});img.src=src;})))'
        $decoded=Send-CDP 'Runtime.evaluate' @{expression=$expression;awaitPromise=$true;returnByValue=$true}
        $verified=@($decoded.result.value | ForEach-Object {$_})
        foreach($entry in $verified) {
            $entry.src=[uri]::UnescapeDataString($entry.src)
            $entry | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $root $entry.src) -Algorithm SHA256).Hash
        }
        [IO.File]::WriteAllText((Join-Path $root 'data/validacao-webp.json'),(ConvertTo-Json -InputObject @($verified | ForEach-Object {$_}) -Depth 5),(New-Object Text.UTF8Encoding($false)))
        Write-Output "WebP validos no navegador: $(@($verified | Where-Object {$_.valid}).Count)"
    }
}
try { Send-CDP 'Browser.close' @{} | Out-Null } catch {}
$socket.Dispose()
