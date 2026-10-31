
document.addEventListener("DOMContentLoaded", () => {
    initIcons();
    initPreloader();
    initMobileMenu();
    initHeader();
    initScrollAnimations();
});

// Ícones Lucide
function initIcons() {
    if (window.lucide) {
        lucide.createIcons();
    }
}

// Tela inicial de carregamento
function initPreloader() {
    const preloader = document.querySelector(".preloader");

    if (!preloader) return;

    window.addEventListener("load", () => {
        setTimeout(() => {
            preloader.classList.add("hidden");

            setTimeout(() => {
                preloader.remove();
            }, 750);
        }, 1500);
    });

    // Evita deixar a tela presa se algum recurso demorar
    setTimeout(() => {
        if (document.body.contains(preloader)) {
            preloader.classList.add("hidden");

            setTimeout(() => {
                preloader.remove();
            }, 750);
        }
    }, 4000);
}

// Menu para celular
function initMobileMenu() {
    const menuButton = document.querySelector(".menu-mobile");
    const nav = document.querySelector(".nav");

    if (!menuButton || !nav) return;

    menuButton.setAttribute("aria-expanded", "false");
    function updateMenuIcon() {
        const open = nav.classList.contains("active");
        menuButton.setAttribute("aria-expanded", String(open));
        menuButton.setAttribute("aria-label", open ? "Fechar menu" : "Abrir menu");
        const icon = document.createElement("i");
        icon.setAttribute("data-lucide", open ? "x" : "menu");
        menuButton.replaceChildren(icon);
        initIcons();
    }

    menuButton.addEventListener("click", () => {
        nav.classList.toggle("active");

        updateMenuIcon();
    });

    nav.querySelectorAll("a").forEach(link => {
        link.addEventListener("click", () => {
            nav.classList.remove("active");

            updateMenuIcon();
        });
    });
    document.addEventListener("keydown", event => {
        if (event.key === "Escape" && nav.classList.contains("active")) {
            nav.classList.remove("active");
            updateMenuIcon();
            menuButton.focus();
        }
    });
}

// Cabeçalho muda ao rolar
function initHeader() {
    const header = document.querySelector(".header");

    if (!header) return;

    function updateHeader() {
        if (window.scrollY > 50) {
            header.classList.add("scrolled");
        } else {
            header.classList.remove("scrolled");
        }
    }

    window.addEventListener("scroll", updateHeader, {
        passive: true
    });

    updateHeader();
}

// Elementos aparecem conforme a rolagem
function initScrollAnimations() {
    const elements = document.querySelectorAll(
        ".section-heading, .category-card, .product-card, .about-content, .about-visual, .differential-card, .contact-box, .catalog-cta"
    );

    // Se o navegador não suportar IntersectionObserver,
    // mostra todos os elementos normalmente.
    if (!("IntersectionObserver" in window)) {
        elements.forEach(element => {
            element.classList.add("visible");
        });
        return;
    }

    const observer = new IntersectionObserver(
        (entries, currentObserver) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add("visible");
                    currentObserver.unobserve(entry.target);
                }
            });
        },
        {
            threshold: 0.12,
            rootMargin: "0px 0px -40px 0px"
        }
    );

    elements.forEach(element => {
        observer.observe(element);
    });
}

/*
    IMPORTANTE:
    Os links do WhatsApp estão diretamente no HTML usando href="https://wa.me/...".
    Não adicionamos eventos de clique nesses links.
    Assim, o JavaScript não interfere na abertura do WhatsApp.
*/
