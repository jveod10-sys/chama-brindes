document.addEventListener('DOMContentLoaded', () => {
    const source = window.CHAMA_CATALOGO;
    const grid = document.querySelector('.product-grid');
    if (!Array.isArray(source) || !source.length || !grid) return;
    const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    const available = [...source].sort((a,b) => Number(Boolean(b.images.length)) - Number(Boolean(a.images.length)));
    const featured = [];
    for (const term of ['copo termico', 'garrafa termica', 'mochila', 'caneta metal', 'caderneta', 'necessaire', 'sacola', 'power bank', 'kit churrasco', 'chaveiro', 'guarda-chuva', 'caixa de som']) {
        const product = available.find(p => p.images.length && normalize(p.name).includes(term) && !featured.includes(p));
        if (product) featured.push(product);
    }
    const products = [...featured, ...available.filter(p => !featured.includes(p))];
    const controls = document.createElement('div');
    controls.className = 'catalog-controls';
    controls.innerHTML = '<label>Buscar produto<input type="search" placeholder="Nome ou código do produto" aria-label="Buscar produto"></label><label>Categoria<select aria-label="Filtrar por categoria"><option value="">Todas as categorias</option></select></label><p class="catalog-count" role="status" aria-live="polite"></p>';
    grid.before(controls);
    const search = controls.querySelector('input');
    const select = controls.querySelector('select');
    const count = controls.querySelector('p');
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'button button-outline catalog-more';
    more.textContent = 'Carregar mais produtos';
    grid.after(more);
    const categories = [...new Set(products.map(p => p.category))].sort((a,b) => a.localeCompare(b, 'pt-BR'));
    if (products.some(p => (p.tags || []).includes('Linha ecológica'))) categories.push('Linha ecológica');
    categories.forEach(category => {
        const option = document.createElement('option');
        option.value = category;
        option.textContent = category;
        select.append(option);
    });
    const imagePath = value => value.split('/').map(encodeURIComponent).join('/');
    let limit = 24;
    const normalized = new Map(products.map(p => [p.id, normalize(p.name + ' ' + p.id + ' ' + p.category)]));
    const matchesCategory = (p, category) => !category || p.category === category || (p.tags || []).includes(category);
    function render() {
        const term = normalize(search.value.trim());
        const filtered = products.filter(p => matchesCategory(p, select.value) && normalized.get(p.id).includes(term));
        grid.replaceChildren();
        filtered.slice(0, limit).forEach(product => {
            const card = document.createElement('article');
            card.className = 'product-card';
            const visual = document.createElement('div');
            visual.className = 'product-image';
            if (product.images.length) {
                const img = document.createElement('img');
                img.src = imagePath(product.images[0]); img.alt = product.name; img.loading = 'lazy'; img.decoding = 'async';
                img.addEventListener('error', () => { visual.textContent = 'Foto indisponível'; }, {once:true});
                visual.append(img);
                if (product.images.length > 1) {
                    const gallery = document.createElement('div');
                    gallery.className = 'product-gallery';
                    product.images.forEach((src, index) => {
                        const button = document.createElement('button');
                        button.type = 'button'; button.textContent = String(index + 1);
                        button.setAttribute('aria-label', `Ver foto ${index + 1} de ${product.name}`);
                        button.setAttribute('aria-pressed', String(index === 0));
                        button.addEventListener('click', () => {
                            img.src = imagePath(src);
                            gallery.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
                        });
                        gallery.append(button);
                    });
                    visual.append(gallery);
                }
            } else { visual.textContent = product.hasSourceImage ? 'Foto indisponível' : 'Sem foto no catálogo original'; }
            const info = document.createElement('div'); info.className = 'product-info';
            const details = document.createElement('div');
            const category = document.createElement('span'); category.className = 'product-category'; category.textContent = product.category;
            const title = document.createElement('h3'); title.textContent = product.name;
            const code = document.createElement('small'); code.className = 'product-code'; code.textContent = 'Código: ' + product.id;
            details.append(category, title, code);
            const quote = document.createElement('a');
            quote.href = 'https://wa.me/5511947582966?text=' + encodeURIComponent(`Olá! Gostaria de um orçamento para ${product.name} (código ${product.id}). Referência: ${product.sourceUrl}`);
            quote.target = '_blank'; quote.rel = 'noopener noreferrer'; quote.textContent = '↗';
            quote.setAttribute('aria-label', 'Solicitar orçamento de ' + product.name);
            info.append(details, quote); card.append(visual, info); grid.append(card);
        });
        count.textContent = `${filtered.length.toLocaleString('pt-BR')} ${filtered.length === 1 ? 'produto encontrado' : 'produtos encontrados'} · ${Math.min(limit, filtered.length)} em exibição`;
        if (!filtered.length) { const empty = document.createElement('p'); empty.textContent = 'Nenhum produto encontrado. Tente outro nome ou categoria.'; grid.append(empty); }
        more.hidden = filtered.length <= limit;
    }
    const address = new URL(window.location.href);
    search.value = address.searchParams.get('busca') || '';
    select.value = categories.includes(address.searchParams.get('categoria')) ? address.searchParams.get('categoria') : '';
    function updateAddress() {
        const url = new URL(window.location.href);
        for (const [key, value] of [['busca', search.value.trim()], ['categoria', select.value]]) {
            if (value) url.searchParams.set(key, value); else url.searchParams.delete(key);
        }
        try { window.history.replaceState(null, '', url); } catch (_) { /* file:// pode restringir o histórico */ }
    }
    search.addEventListener('input', () => { limit = 24; render(); updateAddress(); });
    select.addEventListener('change', () => { limit = 24; render(); updateAddress(); });
    more.addEventListener('click', () => { limit += 24; render(); });
    const categoryGrid = document.querySelector('.category-grid');
    if (categoryGrid) {
        categoryGrid.replaceChildren();
        categories.forEach((category, index) => {
            const members = products.filter(p => matchesCategory(p, category));
            const featured = members.find(p => p.images.length);
            const card = document.createElement('a');
            card.href = '#produtos'; card.className = 'category-card category-with-photo';
            if (featured) {
                const img = document.createElement('img'); img.src = imagePath(featured.images[0]); img.alt = category; img.loading = 'lazy'; img.decoding = 'async';
                card.append(img);
            }
            const body = document.createElement('div'); body.className = 'category-body';
            const number = document.createElement('span'); number.className = 'category-number'; number.textContent = String(index + 1).padStart(2, '0');
            const title = document.createElement('h3'); title.textContent = category;
            const total = document.createElement('p'); total.textContent = `${members.length.toLocaleString('pt-BR')} produtos para explorar`;
            body.append(number, title, total); card.append(body);
            card.addEventListener('click', () => { search.value = ''; select.value = category; limit = 24; render(); updateAddress(); });
            categoryGrid.append(card);
        });
    }
    render();
});
