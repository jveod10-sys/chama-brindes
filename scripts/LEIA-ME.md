# Importação do catálogo Chama Brindes

Execute na pasta do projeto, com acesso à internet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/importar-catalogo.ps1
```

O script organiza as categorias e atualiza a vitrine inicial automaticamente.
Para retomar somente os downloads da lista já coletada, acrescente `-Resume`.
Para reorganizar sem baixar novamente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/organizar-catalogo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/exportar-vitrine.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verificar-arquivos.ps1
```

O importador usa o endpoint público observado no JavaScript do site original:
`https://chamabrindes.com.br/Catalogo/FiltrarProdutos?pagina=1`.
Percorre as páginas até uma resposta vazia, preservando identificador, origem,
nome e todas as imagens presentes nos cards (incluindo as miniaturas).
Consulta também as páginas de detalhes dos produtos de origem LOCAL.
Imagens adicionais que existam exclusivamente nos detalhes dos fornecedores
externos não são verificadas por esta versão.

As categorias originais são preservadas no campo `sourceCategory` somente
quando confirmadas pelo filtro do site (`categoriaSite`, diferente de
`categoriaId`). O script `organizar-catalogo.ps1` organiza os demais itens
pelo nome. Os casos ambíguos ficam em “Outros brindes”, com uma lista para
revisão em `data/categorias-relatorio.json`. “Linha ecológica” reúne nomes
com materiais ou termos explícitos, como bambu, cortiça, rPET ou reciclado.
Isso não verifica certificações. Nomes
iguais não são removidos: podem representar cores, modelos ou fornecedores
diferentes. Duplicatas de imagem são identificadas pelo SHA-256.

- `data/catalogo.json`: produtos e caminhos das imagens verificadas.
- `data/catalogo.js`: os mesmos dados para abrir o site inclusive via `file://`.
- `data/importacao-relatorio.json`: totais, falhas e duplicatas.
- `data/coleta-produtos.json`: lista coletada antes dos downloads.
- `data/cache/`: respostas da paginação, reutilizadas ao retomar o script.
- `assets/images/catalogo/`: arquivos locais com os nomes originais.

Cada imagem integrada é aberta pelo decodificador do Windows e recebe um hash.
Os seis arquivos WebP com extensão JPG foram decodificados no Chrome; seus
hashes ficam em `data/validacao-webp.json` para validar futuras retomadas.
Arquivos ausentes ou inválidos não entram na galeria do produto. O relatório
identifica as falhas para uma nova tentativa. A coleta é uma fotografia do
catálogo na data registrada; não comprova estoque nem disponibilidade.

Para atualizar a lista no futuro, mova `data/cache` para uma pasta de backup
antes de executar novamente. Sem isso, serão reutilizadas as páginas coletadas.

O site exibe 24 produtos por vez, com busca por nome/código e filtro pela
categoria. As fotos adicionais podem ser escolhidas pelos botões
numerados. Os links de orçamento incluem nome, código e referência original,
sempre no WhatsApp `5511947582966`.
