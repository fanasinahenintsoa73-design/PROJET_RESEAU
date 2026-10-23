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
        var reply = byId('meteo-read-reply');
        var replyall = byId('meteo-read-replyall');
        var forward = byId('meteo-read-forward');
        var print = byId('meteo-read-print');
        if (reply) {
            reply.onclick = function () {
                openComposeFor(params, 'reply');
                return false;
            };
        }
        if (replyall) {
            replyall.onclick = function () {
                openComposeFor(params, 'reply', true);
                return false;
            };
        }
        if (forward) {
            forward.onclick = function () {
                openComposeFor(params, 'forward');
                return false;
            };
        }
        if (print) {
            print.setAttribute('href', actionUrl(params, 'print', false));
            print.setAttribute('target', '_blank');
        }
        overlay.hidden = false;
        body.classList.add('meteo-read-open');
        frame.setAttribute('src', href + (href.indexOf('_framed=') === -1 ? '&_framed=1' : ''));
    }

    /* Interception du clic sur le sujet, en phase de capture : on empeche
       la navigation de Roundcube et on ouvre l'overlay de lecture. */
    function interceptRead() {
        document.addEventListener('click', function (ev) {
            var link = null;
            if (ev.target && ev.target.closest) {
                link = ev.target.closest('#messagelist a[href*="_action=show"]');
            }
            if (!link) {
                return;
            }
            ev.preventDefault();
            ev.stopPropagation();
            openRead(link.getAttribute('href'), (link.textContent || '').trim());
        }, true);
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
    }

    /* ------------------------------------------------------------------
       Demarrage
       ------------------------------------------------------------------ */

    ready(function () {
        body = document.body;

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
