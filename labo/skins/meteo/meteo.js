/* ==================================================================
   meteo.js — poste de travail « page unique » du webmail Météo
   ------------------------------------------------------------------
   Skin de surcouche : aucun PHP, aucun changement du code de Roundcube.
   Le script ne fait que trois choses :
     1. transformer la page « mail » en poste de travail (mise en page
        et panneau lateral, recherche) ;
     2. ouvrir la rédaction dans un panneau superposé au lieu d'une
        navigation (le paramètre _framed=1 est natif en Roundcube 1.7) ;
     3. afficher la lecture d'un message en plein ecran, par-dessus la
        liste qui reste visible.
   ================================================================== */

(function () {
    'use strict';

    /* Le script est charge dans le <head> : le corps de la page n'existe
       pas encore. Le corps est donc resolu au moment du demarrage, et
       toutes les fonctions referencent cette meme variable. */
    var body = null;

    /* ------------------------------------------------------------------
       Utilitaires
       ------------------------------------------------------------------ */

    function byId(id) {
        return document.getElementById(id);
    }

    function ready(fn) {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', fn);
        } else {
            fn();
        }
    }

    /* ------------------------------------------------------------------
       1. Panneau lateral (mobile)
       ------------------------------------------------------------------ */

    window.meteoToggleSide = function () {
        body.classList.toggle('meteo-side-open');
        return false;
    };

    /* ------------------------------------------------------------------
       2. Tuiles « boite de reception » et « envoyes »
       Le nom reel du dossier (rel="INBOX", rel="Sent"...) n'est connu
       qu'a l'execution : on le lit dans la liste des dossiers rendue
       par le moteur, jamais en dur.
       ------------------------------------------------------------------ */

    function folderRel(wanted) {
        var list = byId('mailboxlist');
        if (!list) {
            return null;
        }
        var links = list.querySelectorAll('a[rel]');
        var fallback = null;
        for (var i = 0; i < links.length; i++) {
            var rel = links[i].getAttribute('rel') || '';
            if (rel === wanted) {
                return rel;
            }
            if (!fallback && rel.toLowerCase() === wanted.toLowerCase()) {
                fallback = rel;
            }
        }
        return fallback;
    }

    window.meteoGoFolder = function (wanted, el, ev) {
        var rel = folderRel(wanted);
        if (!rel) {
            return true;
        }
        return rcmail.command('list', rel, el, ev);
    };

    /* Compteur de non-lus de la boite de reception, copie sur la tuile. */
    function refreshInboxCount() {
        var list = byId('mailboxlist');
        var badge = byId('meteo-count-inbox');
        if (!list || !badge) {
            return;
        }
        var item = list.querySelector('li.mailbox.inbox .unreadcount');
        var n = item ? item.textContent.trim() : '';
        badge.textContent = n;
        badge.style.display = n ? '' : 'none';
        renameJunk();
    }

    /* Etiquette du dossier des messages indesirables : Roundcube l'appelle
       « Pourriel » ; on affiche « Indesirables », plus clair car « courriel »
       veut dire e-mail. L'operation repete plus d'une fois ne casse rien. */
    function renameJunk() {
        var list = byId('mailboxlist');
        if (!list) {
            return;
        }
        var links = list.querySelectorAll('a');
        for (var k = 0; k < links.length; k++) {
            var a = links[k];
            if (a.textContent.indexOf('Pourriel') === -1) {
                continue;
            }
            var nodes = a.childNodes;
            for (var i = 0; i < nodes.length; i++) {
                if (nodes[i].nodeType === 3 && nodes[i].nodeValue.indexOf('Pourriel') !== -1) {
                    nodes[i].nodeValue = nodes[i].nodeValue.replace(/Pourriels?/g, 'Indesirables');
                }
            }
        }
    }

    /* ------------------------------------------------------------------
       2 bis. Titre de la liste : nom du dossier selectionne.
       ------------------------------------------------------------------ */

    function refreshListTitle() {
        var title = document.querySelector('.meteo-list-title');
        var list = byId('mailboxlist');
        if (!title || !list) {
            return;
        }
        var sel = list.querySelector('li.mailbox.selected a');
        if (!sel) {
            return;
        }
        var clone = sel.cloneNode(true);
        var counts = clone.querySelectorAll('.unreadcount');
        for (var i = 0; i < counts.length; i++) {
            counts[i].parentNode.removeChild(counts[i]);
        }
        var name = clone.textContent.replace(/\s+/g, ' ').trim();
        if (name) {
            title.textContent = name;
        }
    }

    /* Le dossier selectionne change quand l'utilisateur clique une boite :
       on observe la liste pour reactir sans reecrire le HTML. */
    function watchFolders() {
        var list = byId('mailboxlist');
        if (!list || !window.MutationObserver) {
            return;
        }
        var obs = new MutationObserver(function () {
            refreshListTitle();
            refreshInboxCount();
        });
        obs.observe(list, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['class']
        });
    }

    /* ------------------------------------------------------------------
       3. Recherche : champ large dans le bandeau (bureau) ou dans la
       grille d'actions en telephone.
       Le champ est un seul et meme noeud, deplace selon la largeur.
       ------------------------------------------------------------------ */

    function placeSearch() {
        var slot = byId('meteo-search-slot');
        var mobile = byId('meteo-search-mobile');
        if (!slot || !mobile) {
            return;
        }
        var isMobile = window.matchMedia('(max-width: 767.98px)').matches;
        var parent = isMobile ? mobile : slot.parentNode;
        if (parent && slot.parentNode !== parent) {
            parent.appendChild(slot);
            slot.classList.toggle('meteo-search-mobile-slot', isMobile);
        }
    }

    /* ------------------------------------------------------------------
       4. Redaction : panneau superpose (iframe _framed=1)
       ------------------------------------------------------------------ */

    var composeFrame = null;
    var composeObserver = null;
    var composeLoaded = false;

    function composeUrl() {
        var base = window.location.pathname;
        return base + '?_task=mail&_action=compose&_framed=1';
    }

    function openCompose(url) {
        var overlay = byId('meteo-compose-overlay');
        if (!overlay) {
            return false;
        }
        overlay.hidden = false;
        body.classList.add('meteo-compose-open');
        if (!composeFrame) {
            composeFrame = byId('meteo-compose-frame');
        }
        if (composeFrame && !composeLoaded) {
            composeLoaded = true;
            composeFrame.src = url || composeUrl();
        }
        watchCompose();
        return false;
    }

    window.meteoComposeClose = function () {
        var overlay = byId('meteo-compose-overlay');
        if (!overlay) {
            return false;
        }
        overlay.hidden = true;
        body.classList.remove('meteo-compose-open');
        if (composeFrame) {
            composeFrame.src = 'about:blank';
        }
        composeLoaded = false;
        if (composeObserver) {
            composeObserver.disconnect();
            composeObserver = null;
        }
        return false;
    };

    /* Arret de la redaction quand le message est parti : le formulaire
       disparaît de la page de redaction. Le bouton « Fermer » reste
       toujours disponible (c'est la garantie). */
    function watchCompose() {
        if (!composeFrame || composeObserver) {
            return;
        }
        var attach = function () {
            var doc = null;
            try {
                doc = composeFrame.contentDocument;
            } catch (e) {
                doc = null;
            }
            if (!doc || !doc.body) {
                return;
            }
            composeObserver = new MutationObserver(function () {
                var d = null;
                try {
                    d = composeFrame.contentDocument;
                } catch (e) {
                    d = null;
                }
                if (!d || !d.body) {
                    return;
                }
                if (!d.getElementById('composebody')) {
                    window.meteoComposeClose();
                    rcmail.command('checkmail');
                }
            });
            composeObserver.observe(doc.body, { childList: true, subtree: true });
            window.setTimeout(function () { injectSignature(composeFrame); }, 700);
            window.setTimeout(function () { injectSignature(composeFrame); }, 1600);
            window.setTimeout(function () { injectSignature(composeFrame); }, 3400);
        };
        composeFrame.addEventListener('load', attach);
        attach();
    }

    /* ------------------------------------------------------------------
       5. Lecture : le message s'ouvre par-dessus la liste
       Roundcube 1.7 remplace la page entiere a l'ouverture d'un message
       (le cadre de lecture disparait du DOM). On intercepte donc le clic
       sur le sujet, en phase de capture, et on affiche le message dans
       un iframe cadre (_framed=1) pose au-dessus de la liste.
       ------------------------------------------------------------------ */

    function closeRead() {
        var overlay = byId('meteo-read-overlay');
        var frame = byId('meteo-read-frame');
        if (frame) {
            frame.setAttribute('src', 'about:blank');
        }
        if (overlay) {
            overlay.hidden = true;
        }
        body.classList.remove('meteo-read-open');
    }

    window.meteoCloseRead = function () {
        closeRead();
        return false;
    };

    function queryParams(url) {
        var out = {};
        var pos = url.indexOf('?');
        if (pos === -1) {
            return out;
        }
        url.slice(pos + 1).split('&').forEach(function (pair) {
            if (!pair) {
                return;
            }
            var kv = pair.split('=');
            out[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1] || '');
        });
        return out;
    }

    /* Reconstruction d'une URL d'action a partir de l'uid du message.
       La vue cadree ne contient pas la barre d'actions d'elastic : ce
       sont ces liens qui la remplacent dans l'overlay. */
    function actionUrl(params, action, framed) {
        var url = '?_task=mail&_mbox=' + encodeURIComponent(params._mbox || '')
            + '&_uid=' + encodeURIComponent(params._uid || '')
            + '&_action=' + action;
        if (framed) {
            url += '&_framed=1';
        }
        return url;
    }

    /* URL de redaction a partir du message lu. L'action compose de
       Roundcube 1.7.4 accepte _reply_uid / _forward_uid / _all
       (program/actions/mail/compose.php l.156-162 et l.230) : c'est la
       seule voie qui produise un formulaire complet, l'action "reply"
       seule ne renvoyant aucune page. */
    function composeUrlFrom(params, mode, all) {
        var url = '?_task=mail&_action=compose'
            + '&_mbox=' + encodeURIComponent(params._mbox || '')
            + '&_' + mode + '_uid=' + encodeURIComponent(params._uid || '');
        if (mode === 'reply' && all) {
            url += '&_all=1';
        }
        return url + '&_framed=1';
    }

    /* Ouvre le formulaire de reponse ou de transfert dans l'overlay.
       L'action compose cree d'abord un brouillon puis redirige vers
       ?_action=compose&_id=<brouillon> ; cette redirection perd le
       drapeau _framed, et la page non cadre est alors refusee par
       l'en-tete X-Frame-Options (l'iframe resterait vide). On recupere
       donc l'identifiant du brouillon par une requete, puis on recharge
       sa page en mode cadre. */
    function openComposeFor(params, mode, all) {
        var url = composeUrlFrom(params, mode, all);
        var fallback = function () {
            openCompose(url);
        };
        if (!window.fetch) {
            fallback();
            return;
        }
        window.fetch(url, { credentials: 'same-origin' })
            .then(function (res) {
                var m = /[?&]_id=([0-9a-zA-Z]+)/.exec(res.url || '');
                if (m) {
                    openCompose('?_task=mail&_action=compose&_id=' + m[1] + '&_framed=1');
                } else {
                    fallback();
                }
            })
            .catch(fallback);
    }

    function openRead(href, subject) {
        var overlay = byId('meteo-read-overlay');
        var frame = byId('meteo-read-frame');
        if (!overlay || !frame) {
            window.location.href = href;
            return;
        }
        var title = byId('meteo-read-title');
        if (title) {
            title.textContent = subject || 'Message';
        }
        var params = queryParams(href);
        /* Dans la corbeille, les actions de reponse n'ont pas de sens :
           on propose « Restaurer » (retour dans la boite de reception)
           et « Supprimer definitivement ». */
        var trash = (window.rcmail && rcmail.env && rcmail.env.trash_mailbox) || 'Trash';
        var inTrash = params._mbox === trash;
        var reply = byId('meteo-read-reply');
        var replyall = byId('meteo-read-replyall');
        var forward = byId('meteo-read-forward');
        var print = byId('meteo-read-print');
        var restore = byId('meteo-read-restore');
        var purge = byId('meteo-read-delete');
        if (reply) {
            reply.hidden = inTrash;
            reply.onclick = function () {
                openComposeFor(params, 'reply');
                return false;
            };
        }
        if (replyall) {
            replyall.hidden = inTrash;
            replyall.onclick = function () {
                openComposeFor(params, 'reply', true);
                return false;
            };
        }
        if (forward) {
            forward.hidden = inTrash;
            forward.onclick = function () {
                openComposeFor(params, 'forward');
                return false;
            };
        }
        if (print) {
            print.hidden = inTrash;
            print.setAttribute('href', actionUrl(params, 'print', false));
            print.setAttribute('target', '_blank');
        }
        if (restore) {
            restore.hidden = !inTrash;
            restore.onclick = function () {
                if (inTrash) {
                    rcmail.move_messages('INBOX', null, [params._uid]);
                }
                closeRead();
                return false;
            };
        }
        if (purge) {
            purge.hidden = !inTrash;
            purge.onclick = function () {
                if (inTrash) {
                    rcmail.permanently_remove_messages(params._uid);
                }
                closeRead();
                return false;
            };
        }
        overlay.hidden = false;
        body.classList.add('meteo-read-open');
        frame.setAttribute('src', href + (href.indexOf('_framed=') === -1 ? '&_framed=1' : ''));
    }

    /* Interception du clic sur le sujet, en phase de capture : on empeche
       la navigation de Roundcube et on ouvre l'overlay de lecture. */
    /* Interception du clic dans la liste : TOUTE la ligne ouvre le
       message (le geste le plus simple pour le personnel), sauf icone
       d'etoile/piece jointe ou clic avec Ctrl/Maj/Alt (selection). */
    function interceptRead() {
        document.addEventListener('click', function (ev) {
            if (!ev.target || !ev.target.closest) {
                return;
            }
            /* Ctrl/Maj/Alt restent des selections pour Roundcube. */
            if (ev.ctrlKey || ev.shiftKey || ev.metaKey || ev.altKey) {
                return;
            }
            var row = ev.target.closest('#messagelist tbody tr');
            if (!row) {
                return;
            }
            /* Etoile, fils de discussion et icone de piece jointe gardent
               leur propre fonction. */
            if (ev.target.closest('td.flag, td.threads, td.icon, td.attachment, a.recyclerview')) {
                return;
            }
            var cell = ev.target.closest('#messagelist td.subject');
            var link = cell
                ? cell.querySelector('a[href*="_action=show"], a[href*="_action=compose"]')
                : row.querySelector('td.subject a[href*="_action=show"], td.subject a[href*="_action=compose"]');
            if (!link) {
                return;
            }
            ev.preventDefault();
            ev.stopPropagation();
            var href = link.getAttribute('href') || '';
            if (href.indexOf('_action=compose') !== -1) {
                /* Brouillon : on ouvre la redaction chargee depuis ce
                   brouillon (action compose + _draft_uid). */
                openComposeFor(queryParams(href), 'draft');
                return;
            }
            openRead(href, (link.textContent || '').trim());
        }, true);
    }

    /* ------------------------------------------------------------------
       5 bis. Mise en forme des echanges dans le cadre de lecture.
       La citation (message precedent) reste neutre ; la reponse qui la
       suit est enveloppee et posee en retrait avec un liseré vert.
       ------------------------------------------------------------------ */

    function restyleReadFrame(frame) {
        var doc;
        try {
            doc = frame.contentDocument;
        } catch (err) {
            return;
        }
        if (!doc || !doc.body || doc.querySelector('.meteo-reply-part')) {
            return;
        }
        var text = doc.querySelector('#messagebody .rcmBody')
            || doc.getElementById('messagebody')
            || doc.body;

        /* Facon conversation : dans la boite de reception, le message recu
           (l'expediteur) reste neutre a gauche et la citation (nos propres
           messages) devient la bulle verte a droite. Dans les autres
           dossiers (Envoyes...), on garde la reponse de l'utilisateur en
           bulle verte a droite. */
        var mboxMatch = /[?&]_mbox=([^&]+)/.exec(frame.getAttribute('src') || '');
        var mbox = mboxMatch ? decodeURIComponent(mboxMatch[1]) : '';
        var sentBox = (window.rcmail && rcmail.env && rcmail.env.sent_mailbox) || 'Sent';
        doc.documentElement.classList.add(mbox === sentBox ? 'meteo-sent-view' : 'meteo-incoming-view');

        var quote = text.querySelector('blockquote[type="cite"]');
        if (!quote) {
            return;
        }
        /* Remonter jusqu'au bloc de premier niveau qui contient la citation. */
        var top = quote;
        while (top.parentNode && top.parentNode !== text) {
            top = top.parentNode;
        }
        var nodes = [];
        var node = top.nextSibling;
        while (node) {
            nodes.push(node);
            node = node.nextSibling;
        }
        if (!nodes.length) {
            return;
        }
        /* La reponse (tout ce qui suit la citation) recoit le liseré vert. */
        var wrap = doc.createElement('div');
        wrap.className = 'meteo-reply-part';
        text.insertBefore(wrap, nodes[0]);
        nodes.forEach(function (n) {
            wrap.appendChild(n);
        });
    }

    function watchReadFrame() {
        var frame = byId('meteo-read-frame');
        if (!frame || frame.__meteoRestyle) {
            return;
        }
        frame.__meteoRestyle = true;
        frame.addEventListener('load', function () {
            restyleReadFrame(frame);
        });
    }

    /* ------------------------------------------------------------------
       6. Interception de la commande « compose »
       Roundcube ouvre la redaction par une navigation complete. On la
       remplace par le panneau superpose, sans toucher au PHP.
       ------------------------------------------------------------------ */

    function interceptCompose() {
        if (!window.rcmail || typeof rcmail.command !== 'function') {
            return;
        }
        var original = rcmail.command;
        rcmail.command = function (command) {
            if (command === 'compose') {
                return openCompose();
            }
            if (typeof command === 'string' && command.indexOf('sent') !== -1) {
                window.meteoComposeClose();
                rcmail.command('checkmail');
            }
            return original.apply(this, arguments);
        };
    }

    /* ------------------------------------------------------------------
       7. Clavier : Echap ferme le panneau ouvert
       ------------------------------------------------------------------ */

    function bindKeys() {
        document.addEventListener('keydown', function (ev) {
            if (ev.key !== 'Escape') {
                return;
            }
            if (body.classList.contains('meteo-compose-open')) {
                window.meteoComposeClose();
            } else if (body.classList.contains('meteo-read-open')) {
                closeRead();
            } else if (body.classList.contains('meteo-side-open')) {
                body.classList.remove('meteo-side-open');
            }
        });
    }

    /* ------------------------------------------------------------------
       Bandeau des taches hors messagerie (parametres, contacts)
       ------------------------------------------------------------------ */

    function installBand(label) {
        var band = document.createElement('header');
        band.id = 'meteo-band';
        band.innerHTML =
            '<div class="meteo-band-brand">' +
                '<img class="meteo-band-logo" src="/static.php/skins/meteo/images/logo.svg" alt="Meteo Madagascar" />' +
                '<span class="meteo-band-names">' +
                    '<span class="meteo-band-title">Meteo Madagascar</span>' +
                    '<span class="meteo-band-sub">' + label + '</span>' +
                '</span>' +
            '</div>' +
            '<nav class="meteo-band-nav" aria-label="Changer de service">' +
                '<a href="./?_task=mail&amp;_mbox=INBOX">Mes messages</a>' +
                '<a href="./?_task=addressbook">Mes contacts</a>' +
                '<a href="./?_task=settings">Mes parametres</a>' +
            '</nav>' +
            '<div class="meteo-band-user"></div>';
        document.body.prepend(band);
    }

    /* ------------------------------------------------------------------
       Accueil des parametres, facon Gmail : des cartes simples.
       ------------------------------------------------------------------ */

    var COLOR_COOKIE = 'colorMode';
    var SIGNATURE_KEY = 'meteo_signature';

    /* Mode sombre : meme convention qu'Elastic (cookie « colorMode » et
       classe « dark-mode » sur <html>), appliquee aussi aux cadres. */

    function readColorMode() {
        try {
            if (window.rcmail && typeof rcmail.get_cookie === 'function') {
                var v = rcmail.get_cookie(COLOR_COOKIE);
                if (v) {
                    return v;
                }
            }
        } catch (e) { /* cookie indisponible */ }
        var m = /(?:^|;\s*)colorMode=([^;]+)/.exec(document.cookie);
        return m ? decodeURIComponent(m[1]) : '';
    }

    function writeColorMode(mode) {
        try {
            if (window.rcmail && typeof rcmail.set_cookie === 'function') {
                rcmail.set_cookie(COLOR_COOKIE, mode, false);
                return;
            }
        } catch (e) { /* cookie indisponible */ }
        document.cookie = COLOR_COOKIE + '=' + mode + '; path=/; max-age=31536000';
    }

    function paintFrame(frame) {
        try {
            var doc = frame.contentDocument;
            if (!doc || !doc.documentElement) {
                return;
            }
            if (document.documentElement.classList.contains('dark-mode')) {
                doc.documentElement.classList.add('dark-mode');
            } else {
                doc.documentElement.classList.remove('dark-mode');
            }
        } catch (e) { /* cadre inaccessible */ }
    }

    function paintFrames() {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            paintFrame(frames[i]);
        }
    }

    function applyColorMode(mode) {
        if (mode === 'dark') {
            document.documentElement.classList.add('dark-mode');
        } else {
            document.documentElement.classList.remove('dark-mode');
        }
        paintFrames();
        var sw = byId('meteo-switch-dark');
        if (sw) {
            if (mode === 'dark') {
                sw.classList.add('on');
            } else {
                sw.classList.remove('on');
            }
            sw.setAttribute('aria-checked', mode === 'dark' ? 'true' : 'false');
        }
    }

    function toggleColorMode() {
        var dark = document.documentElement.classList.contains('dark-mode');
        var mode = dark ? 'light' : 'dark';
        applyColorMode(mode);
        writeColorMode(mode);
    }

    function initColorMode() {
        if (window.rcmail && rcmail.env && rcmail.env.action === 'print') {
            return;
        }
        var pref = readColorMode();
        var mode = pref || (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
            ? 'dark' : 'light');
        applyColorMode(mode);
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            (function (frame) {
                frame.addEventListener('load', function () { paintFrame(frame); });
            })(frames[i]);
        }
        window.setTimeout(paintFrames, 1500);
        window.setTimeout(paintFrames, 4000);
    }

    /* Signature : un texte simple, ajoute au bas de chaque message.
       Enregistree dans le navigateur et posee dans l'editeur. */

    function getSignature() {
        try {
            return window.localStorage.getItem(SIGNATURE_KEY) || '';
        } catch (e) {
            return '';
        }
    }

    function saveSignature(text) {
        try {
            if (text) {
                window.localStorage.setItem(SIGNATURE_KEY, text);
            } else {
                window.localStorage.removeItem(SIGNATURE_KEY);
            }
        } catch (e) { /* stockage indisponible */ }
    }

    function injectSignature(frame) {
        var sig = getSignature();
        if (!sig || !frame) {
            return;
        }
        try {
            var doc = frame.contentDocument;
            if (!doc) {
                return;
            }
            var tester = doc.getElementById('composebody_ifr');
            var edoc = tester && tester.contentDocument;
            if (!edoc || !edoc.body || edoc.querySelector('.meteo-signature')) {
                return;
            }
            var wrap = edoc.createElement('div');
            wrap.className = 'meteo-signature';
            wrap.textContent = sig;
            edoc.body.appendChild(wrap);
        } catch (e) { /* editeur indisponible */ }
    }

    function esc(text) {
        return String(text == null ? '' : text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function bandBottom() {
        var band = byId('meteo-band');
        return band ? Math.round(band.getBoundingClientRect().bottom) : 35;
    }

    function placeOverlay(el) {
        var place = function () {
            el.style.top = bandBottom() + 'px';
        };
        place();
        window.addEventListener('resize', place);
    }

    /* Accueil simplifie : seuls les reglages utiles, actionnables ici.
       Le reste de Roundcube reste joignable par « Options avancees ». */

    function settingsHome() {
        if (byId('meteo-settings-home')) {
            return;
        }
        var home = document.createElement('section');
        home.id = 'meteo-settings-home';
        home.setAttribute('aria-label', 'Parametres');
        home.innerHTML =
            '<div class="meteo-home-inner" id="meteo-home-main">'
            + '<h1 class="meteo-home-title">Parametres</h1>'
            + '<p class="meteo-home-lead">Les reglages utiles au quotidien, rien de plus.</p>'
            + '<div class="meteo-home-grid">'
            + '<button type="button" class="meteo-setting-card" data-meteo-set="dark">'
            + '<span class="meteo-setting-title">Mode sombre</span>'
            + '<span class="meteo-setting-desc">Basculer l ecran entre clair et sombre, comme sur une application.</span>'
            + '<span class="meteo-switch" id="meteo-switch-dark" role="switch" aria-checked="false" aria-label="Mode sombre"></span>'
            + '</button>'
            + '<button type="button" class="meteo-setting-card" data-meteo-set="signature">'
            + '<span class="meteo-setting-title">Ma signature</span>'
            + '<span class="meteo-setting-desc">Le texte ajoute automatiquement au bas de vos messages.</span>'
            + '</button>'
            + '<button type="button" class="meteo-setting-card" data-meteo-set="guide">'
            + '<span class="meteo-setting-title">Comment utiliser la messagerie</span>'
            + '<span class="meteo-setting-desc">Lire, ecrire, retrouver et ranger vos messages en quelques gestes.</span>'
            + '</button>'
            + '</div>'
            + '<p class="meteo-home-advanced"><a href="./?_task=settings&amp;_action=preferences">Options avancees</a></p>'
            + '</div>'
            + '<div class="meteo-home-inner" id="meteo-home-signature" hidden>'
            + '<button type="button" class="meteo-back" data-meteo-back="1">&#8592; Retour</button>'
            + '<h1 class="meteo-home-title">Ma signature</h1>'
            + '<p class="meteo-home-lead">Elle est ajoutee au bas de chaque nouveau message.</p>'
            + '<textarea id="meteo-sign-text" class="meteo-sign-text" rows="6" placeholder="Exemple : Rasoa Andria, Station meteo Ivato"></textarea>'
            + '<div class="meteo-sign-actions">'
            + '<button type="button" class="meteo-btn" id="meteo-sign-save">Enregistrer</button>'
            + '<span id="meteo-sign-status" class="meteo-sign-status"></span>'
            + '</div>'
            + '</div>'
            + '<div class="meteo-home-inner" id="meteo-home-guide" hidden>'
            + '<button type="button" class="meteo-back" data-meteo-back="1">&#8592; Retour</button>'
            + '<h1 class="meteo-home-title">Comment utiliser la messagerie</h1>'
            + '<ul class="meteo-guide-list">'
            + '<li><strong>Lire un message</strong> : cliquez sur sa ligne dans la liste, il s ouvre au-dessus.</li>'
            + '<li><strong>Ecrire</strong> : bouton jaune « Ecrire un message », en haut de la boite.</li>'
            + '<li><strong>Tous les messages</strong> : le bouton en haut regroupe recus et envoyes.</li>'
            + '<li><strong>Repondre</strong> : ouvrez un message puis « Repondre » ; vos messages apparaissent en bulle verte.</li>'
            + '<li><strong>Corbeille</strong> : « Restaurer » remet le message en boite, « Supprimer definitivement » l efface.</li>'
            + '<li><strong>Contacts</strong> : onglet « Mes contacts », cherchez un agent puis « Ecrire ».</li>'
            + '<li><strong>Mode sombre</strong> : la carte ci-dessus, effet immediat.</li>'
            + '</ul>'
            + '</div>';
        document.body.appendChild(home);
        placeOverlay(home);
        home.addEventListener('click', function (ev) {
            if (ev.target.closest && ev.target.closest('[data-meteo-back]')) {
                showHomeView('main');
                return;
            }
            var card = ev.target.closest ? ev.target.closest('[data-meteo-set]') : null;
            if (!card) {
                return;
            }
            var key = card.getAttribute('data-meteo-set');
            if (key === 'dark') {
                toggleColorMode();
            } else if (key === 'signature') {
                openSignatureView();
            } else if (key === 'guide') {
                showHomeView('guide');
            }
        });
        var save = byId('meteo-sign-save');
        if (save) {
            save.addEventListener('click', function () {
                var field = byId('meteo-sign-text');
                var text = field ? field.value.replace(/\r\n/g, '\n').trim() : '';
                saveSignature(text);
                var status = byId('meteo-sign-status');
                if (status) {
                    status.textContent = text ? 'Signature enregistree.' : 'Signature effacee.';
                }
            });
        }
        applyColorMode(document.documentElement.classList.contains('dark-mode') ? 'dark' : 'light');
    }

    function showHomeView(name) {
        var views = { main: 'meteo-home-main', signature: 'meteo-home-signature', guide: 'meteo-home-guide' };
        Object.keys(views).forEach(function (key) {
            var el = byId(views[key]);
            if (el) {
                el.hidden = key !== name;
            }
        });
    }

    function openSignatureView() {
        showHomeView('signature');
        var field = byId('meteo-sign-text');
        if (field) {
            field.value = getSignature();
        }
        var status = byId('meteo-sign-status');
        if (status) {
            status.textContent = '';
        }
    }

    /* Annuaire des agents : liste des boites du domaine, generee au
       deploiement dans agents.js par le script 19-deploy-skin.sh. */

    function agentsPanel() {
        if (byId('meteo-agents-panel')) {
            return;
        }
        var panel = document.createElement('section');
        panel.id = 'meteo-agents-panel';
        panel.setAttribute('aria-label', 'Agents Meteo');
        panel.innerHTML =
            '<div class="meteo-agents-inner">'
            + '<h1 class="meteo-home-title">Agents Meteo Madagascar</h1>'
            + '<p class="meteo-home-lead">Annuaire de la messagerie. Cliquez sur Ecrire pour joindre un agent.</p>'
            + '<input type="search" id="meteo-agent-search" class="meteo-agent-search" placeholder="Rechercher un nom ou un courriel" autocomplete="off" />'
            + '<p id="meteo-agent-count" class="meteo-home-lead"></p>'
            + '<ul id="meteo-agent-list" class="meteo-agent-list"></ul>'
            + '</div>';
        document.body.appendChild(panel);
        placeOverlay(panel);
        var search = byId('meteo-agent-search');
        if (search) {
            search.addEventListener('input', filterAgents);
        }
        loadAgents();
    }

    function loadAgents() {
        var done = function () {
            filterAgents();
        };
        if (window.METEO_AGENTS) {
            done();
            return;
        }
        var script = document.createElement('script');
        script.src = '/static.php/skins/meteo/agents.js';
        script.onload = done;
        script.onerror = function () {
            window.METEO_AGENTS = [];
            done();
        };
        document.head.appendChild(script);
    }

    function filterAgents() {
        var list = byId('meteo-agent-list');
        if (!list) {
            return;
        }
        var search = byId('meteo-agent-search');
        var query = search ? search.value.trim().toLowerCase() : '';
        var agents = (window.METEO_AGENTS || []).filter(function (agent) {
            return !query || (agent.name + ' ' + agent.email).toLowerCase().indexOf(query) !== -1;
        });
        list.innerHTML = agents.slice(0, 200).map(function (agent) {
            var initial = (agent.name || agent.email).charAt(0).toUpperCase();
            return '<li class="meteo-agent" data-search="' + esc((agent.name + ' ' + agent.email).toLowerCase()) + '">'
                + '<span class="meteo-agent-avatar" aria-hidden="true">' + esc(initial) + '</span>'
                + '<span class="meteo-agent-id">'
                + '<span class="meteo-agent-name">' + esc(agent.name) + '</span>'
                + '<span class="meteo-agent-mail">' + esc(agent.email) + '</span>'
                + '</span>'
                + '<a class="meteo-agent-write" href="./?_task=mail&amp;_mbox=INBOX&amp;_meteo_to=' + encodeURIComponent(agent.email) + '">Ecrire</a>'
                + '</li>';
        }).join('');
        if (!agents.length) {
            list.innerHTML = '<li class="meteo-agent-empty">Aucun agent ne correspond.</li>';
        }
        var count = byId('meteo-agent-count');
        if (count) {
            count.textContent = agents.length + ' agent' + (agents.length > 1 ? 's' : '') + ' affiche' + (agents.length > 1 ? 's' : '');
        }
    }

    /* Depuis l'annuaire, « Ecrire » revient sur la messagerie : on ouvre
       directement la redaction adressee a l'agent. */

    function composeToFromUrl() {
        var match = /[?&]_meteo_to=([^&]+)/.exec(location.search);
        if (!match) {
            return;
        }
        var email = decodeURIComponent(match[1]);
        try {
            var clean = location.search.replace(/([?&])_meteo_to=[^&]*&?/, '$1').replace(/[?&]$/, '');
            window.history.replaceState({}, document.title, location.pathname + clean);
        } catch (e) { /* historique indisponible */ }
        openCompose('?_task=mail&_action=compose&_framed=1&_to=' + encodeURIComponent(email));
    }

    /* La tuile « Tous les messages » declenche une recherche multifolder
       en XHR (scope=all) : la navigation pleine page vers _action=search
       n'a pas de gabarit et renvoie 404. Repli : navigation ordinaire si
       l'API Roundcube n'est pas disponible. */
    function interceptAllMail() {
        document.addEventListener('click', function (ev) {
            var tile = ev.target && ev.target.closest
                ? ev.target.closest('a.meteo-tile-all') : null;
            if (!tile) {
                return;
            }
            if (!window.rcmail || typeof rcmail.qsearch !== 'function'
                || typeof rcmail.set_searchscope !== 'function') {
                return;
            }
            ev.preventDefault();
            ev.stopPropagation();
            rcmail.set_searchscope('all');
            rcmail.qsearch('text:@');
        }, true);
    }

    function startNonMail() {
        var label = null;
        if (document.documentElement.classList.contains('iframe')) {
            return;
        }
        if (body.classList.contains('task-settings')) {
            label = 'Parametres';
        } else if (body.classList.contains('task-addressbook')) {
            label = 'Contacts';
        }
        if (label === null || body.classList.contains('action-compose')) {
            return;
        }
        installBand(label);
        if (body.classList.contains('task-settings')
            && body.classList.contains('action-none')) {
            settingsHome();
        } else if (body.classList.contains('task-addressbook')
            && body.classList.contains('action-none')) {
            agentsPanel();
        }
    }

    /* ------------------------------------------------------------------
       Demarrage
       ------------------------------------------------------------------ */

    ready(function () {
        body = document.body;
        initColorMode();

        /* La page unique ne concerne que la tache « mail ». La page de
           redaction (action-compose) a son propre gabarit : on n'y touche
           pas. Les autres taches (parametres, contacts) recoivent le
           bandeau Météo via startNonMail(). */
        if (!body || !body.classList.contains('task-mail')
            || body.classList.contains('action-compose')) {
            startNonMail();
            return;
        }

        interceptCompose();
        interceptRead();
        interceptAllMail();
        watchReadFrame();
        composeToFromUrl();
        bindKeys();
        placeSearch();
        refreshInboxCount();
        refreshListTitle();
        watchFolders();
        window.setTimeout(refreshInboxCount, 1200);
        window.setTimeout(refreshListTitle, 1200);
        window.addEventListener('resize', placeSearch);
        if (window.matchMedia) {
            var mq = window.matchMedia('(max-width: 767.98px)');
            if (mq.addEventListener) {
                mq.addEventListener('change', placeSearch);
            } else if (mq.addListener) {
                mq.addListener(placeSearch);
            }
        }
    });
})();
